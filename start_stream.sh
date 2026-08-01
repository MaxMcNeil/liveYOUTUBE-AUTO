#!/usr/bin/env bash
#
# Démarre le pipeline complet de diffusion :
#   1. Affichage virtuel Xvfb
#   2. Chromium en mode kiosk (fenêtre pleine page, sans interface)
#   3. L'orchestrateur Node.js qui pilote la rotation des sites
#   4. ffmpeg qui capture l'affichage et pousse SIMULTANÉMENT vers le flux
#      RTMP principal et le flux de secours YouTube (redondance côté
#      serveur YouTube — pas de bascule manuelle nécessaire).
#
# Variable requise : YOUTUBE_STREAM_KEY (clé de stream, à ne jamais
# commiter en clair — utiliser un fichier .env local ou un secret
# systemd, voir README.md).

set -euo pipefail
cd "$(dirname "$0")"

: "${YOUTUBE_STREAM_KEY:?Il faut définir YOUTUBE_STREAM_KEY dans l'environnement}"

DISPLAY_NUM=":99"
RESOLUTION="1280x720"
FRAMERATE=24
INITIAL_URL="https://maxmcneil.github.io/dls-monitor/"

PRIMARY_RTMP="rtmp://x.rtmp.youtube.com/live2/${YOUTUBE_STREAM_KEY}"
BACKUP_RTMP="rtmp://y.rtmp.youtube.com/live2/${YOUTUBE_STREAM_KEY}?backup=1"

PIDS=()
cleanup() {
  echo "Arrêt du pipeline..."
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

echo "Démarrage de Chromium en mode kiosk..."
chromium --kiosk --noerrdialogs --disable-infobars --disable-session-crashed-bubble \
  --autoplay-policy=no-user-gesture-required --remote-debugging-port=9222 \
  --window-size="${RESOLUTION/x/,}" --window-position=0,0 \
  --no-sandbox --disable-gpu --disable-dev-shm-usage \
  --user-data-dir=/tmp/chromium-livestream-profile \
  "$INITIAL_URL" &
PIDS+=($!)

echo "Attente de la disponibilité de Chromium (port debug 9222)..."
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

echo "Démarrage de ffmpeg (capture + push simultané vers flux principal et secours)..."
ffmpeg -hide_banner -loglevel warning \
  -f x11grab -video_size "$RESOLUTION" -framerate "$FRAMERATE" -i "$DISPLAY_NUM" \
  -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 \
  -c:v libx264 -preset ultrafast -tune zerolatency -b:v 2000k -maxrate 2000k -bufsize 4000k \
  -pix_fmt yuv420p -g $((FRAMERATE * 2)) \
  -c:a aac -b:a 96k -ar 44100 \
  -f tee -map 0:v -map 1:a \
  "[f=flv]${PRIMARY_RTMP}|[f=flv]${BACKUP_RTMP}" &
FFMPEG_PID=$!
PIDS+=($FFMPEG_PID)

wait "$FFMPEG_PID"
