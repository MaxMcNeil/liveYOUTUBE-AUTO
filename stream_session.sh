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
RESOLUTION="1920x1080"
FRAMERATE=30
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
  wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "Démarrage de l'affichage virtuel ${DISPLAY_NUM}..."
Xvfb "$DISPLAY_NUM" -screen 0 "${RESOLUTION}x24" -nolisten tcp &
PIDS+=($!)
export DISPLAY="$DISPLAY_NUM"
sleep 2

echo "Démarrage de Chromium (Playwright) en mode kiosk..."
"$CHROME_PATH" --kiosk --noerrdialogs --disable-infobars --disable-session-crashed-bubble \
  --autoplay-policy=no-user-gesture-required --remote-debugging-port=9222 \
  --window-size="${RESOLUTION/x/,}" --window-position=0,0 \
  --no-sandbox --disable-gpu --disable-dev-shm-usage \
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
  -f x11grab -video_size "$RESOLUTION" -framerate "$FRAMERATE" -i "$DISPLAY_NUM" \
  -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 \
  -c:v libx264 -preset veryfast -tune zerolatency -b:v 4500k -maxrate 4500k -bufsize 9000k \
  -pix_fmt yuv420p -g $((FRAMERATE * 2)) \
  -c:a aac -b:a 128k -ar 44100 \
  -f tee -map 0:v -map 1:a \
  "[f=flv]${PRIMARY_RTMP}|[f=flv]${BACKUP_RTMP}" || true

echo "Session terminée."
