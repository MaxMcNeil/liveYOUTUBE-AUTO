#!/usr/bin/env bash
# Prépare la vidéo de profil pour une lecture en boucle INVISIBLE :
#   1. recadre en carré (pas de déformation, pas de redimensionnement du
#      visage vers du 1920x1080 — on garde le cadrage d'origine)
#   2. fabrique un clip "bouclable" : les X dernières secondes sont fondues
#      dans les X premières, de sorte que la dernière image se raccorde
#      exactement à la première (aucun saut visible quand ça reboucle)
#
# Usage: make_loop.sh video_source.mp4 sortie_loop.mp4 [crop_w crop_h crop_x crop_y] [fondu_s]
set -euo pipefail

SRC="${1:?vidéo source manquante}"
OUT="${2:?fichier de sortie manquant}"
CROP_W="${3:-1080}"; CROP_H="${4:-1080}"; CROP_X="${5:-0}"; CROP_Y="${6:-340}"
XF="${7:-1.5}"          # durée du fondu (secondes)
SIZE="${SIZE:-560}"     # côté du carré produit (le composite le réduit ensuite)

DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$SRC")
python3 - "$DUR" "$XF" << 'PY'
import sys
d, x = float(sys.argv[1]), float(sys.argv[2])
if d < 4 * x:
    sys.exit(f"ERREUR : la vidéo ({d:.1f}s) est trop courte pour un fondu de {x}s (minimum {4*x:.1f}s).")
PY

TAIL_START=$(python3 -c "print(round($DUR - $XF, 3))")

ffmpeg -y -loglevel error -i "$SRC" -filter_complex "
[0:v]crop=${CROP_W}:${CROP_H}:${CROP_X}:${CROP_Y},scale=${SIZE}:${SIZE},fps=30,setsar=1,format=yuv420p,split=3[a][b][c];
[a]trim=start=${TAIL_START}:end=${DUR},setpts=PTS-STARTPTS[tail];
[b]trim=start=0:end=${XF},setpts=PTS-STARTPTS[head];
[c]trim=start=${XF}:end=${TAIL_START},setpts=PTS-STARTPTS[mid];
[tail][head]xfade=transition=fade:duration=${XF}:offset=0[blend];
[blend][mid]concat=n=2:v=1:a=0[out]
" -map "[out]" -an -c:v libx264 -crf 14 -preset medium -pix_fmt yuv420p "$OUT"

echo "Boucle prête : $OUT ($(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT")s)"
