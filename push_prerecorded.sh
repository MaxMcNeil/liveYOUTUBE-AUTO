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
  -c:v libx264 -preset veryfast -tune zerolatency -b:v 4500k -maxrate 4500k -bufsize 9000k \
  -pix_fmt yuv420p -g $((TARGET_FPS * 2)) \
  -c:a aac -b:a 128k -ar 44100 \
  -f tee \
  "[f=flv]${PRIMARY_RTMP}|[f=flv]${BACKUP_RTMP}"

echo "Diffusion terminée — toutes les vidéos ont été jouées, direct coupé."
