#!/usr/bin/env bash
#
# Variante de start_stream.sh pour une session ponctuelle et limitée
# dans le temps (utilisée par le workflow GitHub Actions programmé),
# au lieu d'un pipeline permanent sur un VPS.
#
# Utilise le Chromium installé par Playwright (fiable sur les runners
# GitHub, contrairement au paquet apt "chromium" souvent cassé sur les
# images Ubuntu récentes).
#
# Variables requises :
#   YOUTUBE_STREAM_KEY
#   DURATION_SECONDS (durée de la session, ex: 3600 pour 1h)

set -euo pipefail
cd "$(dirname "$0")"

: "${YOUTUBE_STREAM_KEY:?YOUTUBE_STREAM_KEY manquant}"
: "${DURATION_SECONDS:?DURATION_SECONDS manquant}"

DISPLAY_NUM=":99"
RESOLUTION="1080x1920"
FRAMERATE=24
INITIAL_URL="https://maxmcneil.github.io/dls-monitor/"

PRIMARY_RTMP="rtmp://x.rtmp.youtube.com/live2/${YOUTUBE_STREAM_KEY}"
BACKUP_RTMP="rtmp://y.rtmp.youtube.com/live2/${YOUTUBE_STREAM_KEY}?backup=1"

CHROME_PATH="$(node -e "console.log(require('playwright').chromium.executablePath())")"

PIDS=()
cleanup() {
  echo "Fin de la session, nettoyage..."
  echo '{"stop": true}' > /tmp/livestream_control.json 2>/dev/null || true
  for pid in "${PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
  pulseaudio --kill 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "Démarrage de l'affichage virtuel ${DISPLAY_NUM}..."
Xvfb "$DISPLAY_NUM" -screen 0 "${RESOLUTION}x24" -nolisten tcp &
PIDS+=($!)
export DISPLAY="$DISPLAY_NUM"
sleep 2

echo "Diagnostic — résolution réelle du serveur X (Xvfb) :"
XDPYINFO_OUT="$(xdpyinfo -display "$DISPLAY_NUM" 2>&1)"
echo "$XDPYINFO_OUT" | grep -i "dimensions" || echo "xdpyinfo indisponible ou a échoué."

ACTUAL_DIMENSIONS="$(echo "$XDPYINFO_OUT" | grep -i "dimensions" | grep -oE '[0-9]+x[0-9]+' | head -1)"
if [ -n "$ACTUAL_DIMENSIONS" ] && [ "$ACTUAL_DIMENSIONS" != "$RESOLUTION" ]; then
  echo "ERREUR : Xvfb a démarré en ${ACTUAL_DIMENSIONS} au lieu de ${RESOLUTION} demandé."
  echo "On arrête ici plutôt que de diffuser un format cassé."
  exit 1
fi

# Sans serveur audio, Chromium n'a nulle part où jouer les bips/effets
# sonores du site (d'où les erreurs ALSA "cannot find card") et ffmpeg
# n'a de toute façon rien à capturer : on créait jusqu'ici une piste
# silencieuse en dur (anullsrc). On démarre un sink PulseAudio virtuel
# pour que Chromium y joue réellement du son, que ffmpeg capture ensuite
# depuis son "monitor". Repli sur le silence si PulseAudio est indisponible,
# pour ne jamais faire échouer la diffusion pour une histoire de son.
echo "Démarrage du serveur audio virtuel (PulseAudio)..."
AUDIO_INPUT_ARGS=(-f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100")
PULSE_AVAILABLE=false
if pulseaudio --start --exit-idle-time=-1 --disallow-exit >/tmp/pulseaudio.log 2>&1; then
  sleep 2
  if pactl load-module module-null-sink sink_name=streamsink sink_properties=device.description=StreamSink >/dev/null 2>&1; then
    pactl set-default-sink streamsink
    export PULSE_SINK=streamsink
    AUDIO_INPUT_ARGS=(-f pulse -i streamsink.monitor)
    PULSE_AVAILABLE=true
    echo "Capture audio via PulseAudio (streamsink.monitor)."
  else
    echo "Sink PulseAudio non créé, audio en silence (anullsrc) en repli."
  fi
else
  echo "Échec du démarrage de PulseAudio, audio en silence (anullsrc) en repli."
fi

# Playlist voix/musique en fond, mixée dans le même sink que Chromium.
# Seulement possible si PulseAudio a démarré (sinon rien où jouer).
if [ "$PULSE_AVAILABLE" = true ]; then
  echo "Démarrage de la playlist audio (musique/voix)..."
  bash "$(dirname "$0")/audio_playlist.sh" streamsink &
  PIDS+=($!)
else
  echo "Playlist audio ignorée (pas de sink PulseAudio disponible)."
fi

echo "Démarrage de Chromium (Playwright) en mode kiosk..."
"$CHROME_PATH" --kiosk --noerrdialogs --disable-infobars --disable-session-crashed-bubble \
  --autoplay-policy=no-user-gesture-required --remote-debugging-port=9222 \
  --window-size="${RESOLUTION/x/,}" --window-position=0,0 \
  --no-sandbox --disable-gpu --disable-dev-shm-usage \
  --no-first-run --no-default-browser-check --disable-sync \
  --disable-features=SigninPromo,SigninInterceptFirstRunExperience,Translate,TranslateUI \
  --disable-translate \
  --user-data-dir=/tmp/chromium-livestream-profile \
  "$INITIAL_URL" &
PIDS+=($!)

echo "Attente de la disponibilité de Chromium..."
for i in $(seq 1 30); do
  if curl -s "http://127.0.0.1:9222/json/version" > /dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo '{"stop": false}' > /tmp/livestream_control.json

echo "Démarrage de l'orchestrateur de rotation..."
node orchestrator.js &
PIDS+=($!)

echo "Démarrage de ffmpeg pour ${DURATION_SECONDS}s (arrêt automatique)..."
timeout "$DURATION_SECONDS" ffmpeg -hide_banner -loglevel warning \
  -thread_queue_size 1024 -f x11grab -video_size "$RESOLUTION" -framerate "$FRAMERATE" -i "$DISPLAY_NUM" \
  -thread_queue_size 1024 "${AUDIO_INPUT_ARGS[@]}" \
  -c:v libx264 -preset veryfast -b:v 6000k -maxrate 6000k -bufsize 12000k \
  -pix_fmt yuv420p -g $((FRAMERATE * 2)) \
  -c:a aac -b:a 128k -ar 44100 \
  -f tee -map 0:v -map 1:a \
  "[f=flv]${PRIMARY_RTMP}|[f=flv]${BACKUP_RTMP}" || true

echo "Session terminée."
