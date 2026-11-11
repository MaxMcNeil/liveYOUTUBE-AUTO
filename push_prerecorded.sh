#!/usr/bin/env bash
#
# Diffuse en direct sur YouTube une ou plusieurs vidéos du dossier
# Prerecorded_lives/, dans l'ordre alphabétique, enchaînées sans
# coupure ni transition (comme une seule vidéo continue). Aucune
# boucle : chaque vidéo n'est jouée qu'une fois, le direct s'arrête
# automatiquement à la fin de la dernière vidéo.
#
# Les vidéos sont uniformisées (résolution/fps) au vol via le filtre
# concat de ffmpeg, ce qui permet de mélanger des formats/résolutions
# différents sans que ça ne se voie à l'écran.

set -euo pipefail
cd "$(dirname "$0")"

: "${YOUTUBE_STREAM_KEY:?YOUTUBE_STREAM_KEY manquant}"
# un espace ou un retour à la ligne collé par erreur dans le secret casserait l'adresse d'envoi sans message clair
YOUTUBE_STREAM_KEY="$(printf '%s' "$YOUTUBE_STREAM_KEY" | tr -d '[:space:]')"
[ -n "$YOUTUBE_STREAM_KEY" ] || { echo "YOUTUBE_STREAM_KEY vide"; exit 1; }

VIDEOS_DIR="Prerecorded_lives"
TARGET_W=1080
TARGET_H=1920
TARGET_FPS=30

PRIMARY_RTMP="rtmp://x.rtmp.youtube.com/live2/${YOUTUBE_STREAM_KEY}"
BACKUP_RTMP="rtmp://y.rtmp.youtube.com/live2/${YOUTUBE_STREAM_KEY}?backup=1"

mapfile -t VIDEO_FILES < <(find "$VIDEOS_DIR" -maxdepth 1 -type f \
  ! -iname "input_METADATA*" ! -iname "README*" ! -iname ".*" | sort)

if [ ${#VIDEO_FILES[@]} -eq 0 ]; then
  echo "Aucune vidéo trouvée dans ${VIDEOS_DIR}/ — rien à diffuser."
  exit 1
fi

# Orientation du direct = celle de la 1re vidéo (rotation des téléphones prise en compte) : une vidéo horizontale n'est
# plus enfermée dans un cadre vertical avec des bandes noires. Vidéos verticales : rien ne change (1080x1920).
# Pour forcer : LIVE_ORIENTATION=vertical ou horizontal.
dims=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height:stream_side_data=rotation:stream_tags=rotate -of default=nw=1 "${VIDEO_FILES[0]}" 2>/dev/null || true)
vw=$(grep -m1 '^width=' <<<"$dims" | cut -d= -f2); vh=$(grep -m1 '^height=' <<<"$dims" | cut -d= -f2)
rot=$(grep -m1 -E '^(rotation|TAG:rotate)=' <<<"$dims" | cut -d= -f2 | tr -d '-' || true)
if [ "${rot:-0}" = "90" ] || [ "${rot:-0}" = "270" ]; then t=$vw; vw=$vh; vh=$t; fi
orient="${LIVE_ORIENTATION:-}"
if [ -z "$orient" ]; then if [ "${vw:-0}" -gt "${vh:-0}" ] 2>/dev/null; then orient=horizontal; else orient=vertical; fi; fi
if [ "$orient" = "horizontal" ]; then TARGET_W=1920; TARGET_H=1080; fi
echo "Format du direct : ${TARGET_W}x${TARGET_H} ($orient)"

echo "Vidéos à diffuser, dans l'ordre :"
printf '  - %s\n' "${VIDEO_FILES[@]}"

INPUT_ARGS=()
FILTER=""
for i in "${!VIDEO_FILES[@]}"; do
  INPUT_ARGS+=(-re -i "${VIDEO_FILES[$i]}")
  FILTER+="[$i:v]scale=${TARGET_W}:${TARGET_H}:force_original_aspect_ratio=decrease,pad=${TARGET_W}:${TARGET_H}:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=${TARGET_FPS}[v$i];"
  FILTER+="[$i:a]aformat=sample_rates=44100:channel_layouts=stereo[a$i];"
done

CONCAT_INPUTS=""
for i in "${!VIDEO_FILES[@]}"; do
  CONCAT_INPUTS+="[v$i][a$i]"
done
FILTER+="${CONCAT_INPUTS}concat=n=${#VIDEO_FILES[@]}:v=1:a=1[outv][outa]"

echo "Démarrage de la diffusion — arrêt automatique en fin de vidéo(s)..."
ffmpeg -hide_banner -loglevel warning \
  "${INPUT_ARGS[@]}" \
  -filter_complex "$FILTER" \
  -map "[outv]" -map "[outa]" \
  -c:v libx264 -preset ultrafast -tune zerolatency -b:v 4000k -maxrate 4000k -bufsize 8000k \
  -pix_fmt yuv420p -g $((TARGET_FPS * 2)) \
  -c:a aac -b:a 128k -ar 44100 \
  -f tee \
  "[f=flv:onfail=ignore]${PRIMARY_RTMP}|[f=flv:onfail=ignore]${BACKUP_RTMP}"   # un des deux serveurs YouTube qui lâche ne coupe plus le direct

echo "Diffusion terminée — toutes les vidéos ont été jouées, direct coupé."
