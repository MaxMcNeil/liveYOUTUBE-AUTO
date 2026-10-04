#!/usr/bin/env bash
# Rend l'habillage (template/) en vidéo : lance un Chromium réel sur un
# écran virtuel, capture l'écran EN TEMPS RÉEL, et colle en piste audio
# le fichier de narration déjà connu — plutôt que de capturer un flux
# audio système (plus simple, plus fiable, aucun risque de silence si
# le runner n'a pas de device audio).
#
# UN SEUL passage ffmpeg, en temps réel, que la sortie soit un fichier
# (mode test) ou un flux RTMP (mode live) — c'est important : un live
# doit être poussé au fur et à mesure, jamais capturé-puis-envoyé après
# coup (ça n'aurait plus rien d'un direct).
#
# Usage :
#   capture.sh --template-dir DIR --audio narration.wav --duration 320 \
#              --out sortie.mp4                              # mode fichier (test)
#   capture.sh --template-dir DIR --audio narration.wav --duration 320 \
#              --rtmp rtmp://x.rtmp.youtube.com/live2/CLE     # mode live
#
# --duration : durée exacte du rendu, en secondes (= narration_timing.json
#   -> total_duration, calculé par schedule_and_publish.py). Le live/la
#   vidéo s'arrête pile à la fin de la narration, jamais avant, jamais
#   après.
set -euo pipefail

TEMPLATE_DIR="" AUDIO="" DURATION="" OUT="" RTMP="" DISPLAY_NUM="77" PORT="8791" CDP_PORT="9222"
while [ $# -gt 0 ]; do
  case "$1" in
    --template-dir) TEMPLATE_DIR="$2"; shift 2 ;;
    --audio) AUDIO="$2"; shift 2 ;;
    --duration) DURATION="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --rtmp) RTMP="$2"; shift 2 ;;
    --display) DISPLAY_NUM="$2"; shift 2 ;;
    *) echo "Argument inconnu : $1" >&2; exit 1 ;;
  esac
done
: "${TEMPLATE_DIR:?--template-dir requis}"
: "${AUDIO:?--audio requis}"
: "${DURATION:?--duration requis}"
if [ -z "$OUT" ] && [ -z "$RTMP" ]; then
  echo "ERREUR : --out ou --rtmp requis (l'un des deux)." >&2; exit 1
fi

PIDS=()
cleanup() {
  for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done
  wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "[capture] Écran virtuel ${DISPLAY_NUM} (1920x1080)..."
Xvfb ":${DISPLAY_NUM}" -screen 0 1920x1080x24 >/tmp/capture-xvfb.log 2>&1 &
PIDS+=("$!")
sleep 1

echo "[capture] Serveur local pour ${TEMPLATE_DIR}..."
( cd "$TEMPLATE_DIR" && python3 -m http.server "$PORT" --bind 127.0.0.1 ) >/tmp/capture-http.log 2>&1 &
PIDS+=("$!")
sleep 1

CHROME="${CHROME_BIN:-chromium}"
echo "[capture] Lancement de Chromium (kiosk, autoplay)..."
DISPLAY=":${DISPLAY_NUM}" "$CHROME" \
  --no-sandbox --kiosk --window-size=1920,1080 --window-position=0,0 \
  --autoplay-policy=no-user-gesture-required --disable-infobars --no-first-run \
  --remote-debugging-port="$CDP_PORT" \
  --app="http://127.0.0.1:${PORT}/index.html?audio=$(basename "$AUDIO")" \
  >/tmp/capture-chrome.log 2>&1 &
PIDS+=("$!")

echo "[capture] Attente que la page soit prête ET que l'audio ait démarré..."
AUDIO_OFFSET=$(python3 - "$CDP_PORT" << 'PY'
import sys, time
from playwright.sync_api import sync_playwright
port = sys.argv[1]
with sync_playwright() as p:
    for attempt in range(30):
        try:
            b = p.chromium.connect_over_cdp(f"http://127.0.0.1:{port}")
            pg = b.contexts[0].pages[0]
            for _ in range(40):
                ready = pg.evaluate("window.__TEMPLATE_READY__ === true")
                playing = pg.evaluate("!document.getElementById('voice').paused")
                err = pg.evaluate("window.__TEMPLATE_ERROR__ || null")
                if err:
                    print(f"ERREUR PAGE: {err}", file=sys.stderr); sys.exit(1)
                if ready and playing:
                    ct = pg.evaluate("document.getElementById('voice').currentTime")
                    print(f"{ct:.3f}")
                    sys.exit(0)
                time.sleep(0.2)
            print("ERREUR : page jamais passée en lecture (voir /tmp/capture-chrome.log)", file=sys.stderr)
            sys.exit(1)
        except Exception:
            time.sleep(0.3)
    print("ERREUR : impossible de se connecter à Chromium (CDP).", file=sys.stderr)
    sys.exit(1)
PY
)
echo "[capture] Prêt — audio de la page déjà à ${AUDIO_OFFSET}s, calage de la piste externe sur ce point."

REMAINING=$(python3 -c "print(max(1, ${DURATION} - ${AUDIO_OFFSET}))")

if [ -n "$OUT" ]; then
  echo "[capture] Rendu temps réel -> fichier : ${OUT} (${REMAINING}s restantes)"
  DISPLAY=":${DISPLAY_NUM}" ffmpeg -y \
    -f x11grab -draw_mouse 0 -video_size 1920x1080 -framerate 30 -i ":${DISPLAY_NUM}.0" \
    -ss "$AUDIO_OFFSET" -i "$AUDIO" \
    -t "$REMAINING" -map 0:v:0 -map 1:a:0 \
    -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -c:a aac -b:a 192k \
    "$OUT" -loglevel warning
  echo "[capture] Terminé : ${OUT}"
else
  echo "[capture] Rendu temps réel -> RTMP : ${RTMP} (${REMAINING}s restantes)"
  DISPLAY=":${DISPLAY_NUM}" ffmpeg -y \
    -f x11grab -draw_mouse 0 -video_size 1920x1080 -framerate 30 -i ":${DISPLAY_NUM}.0" \
    -ss "$AUDIO_OFFSET" -i "$AUDIO" \
    -t "$REMAINING" -map 0:v:0 -map 1:a:0 \
    -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -g 60 \
    -c:a aac -b:a 192k -f flv "$RTMP" -loglevel warning
  echo "[capture] Direct terminé."
fi
