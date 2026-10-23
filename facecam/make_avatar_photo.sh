#!/usr/bin/env bash
# Extrait une photo fixe pour le cercle de l'avatar — plus de boucle
# vidéo : une bouche qui bouge sans suivre le texte réellement
# prononcé est plus dérangeante qu'une image fixe (constat visuel
# direct sur un rendu réel). L'anneau audio-réactif reste la seule
# animation du cercle, et porte très bien "c'est vivant" à lui seul.
#
# Fonctionne aussi bien si la source est une vidéo (extrait une frame)
# qu'une photo déjà fixe (ffmpeg traite une image comme une "vidéo"
# d'une seule frame — même commande, aucune branche de code à prévoir).
#
# Usage: make_avatar_photo.sh source.mp4|jpg|png sortie.jpg \
#          [crop_w crop_h crop_x crop_y] [timestamp_s] [taille_px]
set -euo pipefail

SRC="${1:?source manquante}"
OUT="${2:?fichier de sortie manquant}"
CROP_W="${3:-1080}"; CROP_H="${4:-1080}"; CROP_X="${5:-0}"; CROP_Y="${6:-340}"
TIMESTAMP="${7:-1.0}"    # si source vidéo : instant choisi pour la frame
SIZE="${SIZE:-560}"      # côté du carré produit (le composite le réduit ensuite)

# Sécurité : si la source est plus courte que TIMESTAMP (ex: un clip de
# 0.5s), -ss dépasserait la fin du flux et ffmpeg ne produirait AUCUNE
# frame, en silence (pas d'erreur explicite). On vérifie la durée
# d'abord et on recadre l'instant demandé si besoin.
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$SRC" 2>/dev/null || echo "0")
SAFE_TS=$(python3 -c "
d = float('$DUR' or 0)
t = float('$TIMESTAMP')
print(min(t, d * 0.4) if d > 0 else 0)
")

extract() {
  local ts="$1"
  ffmpeg -y -loglevel error -ss "$ts" -i "$SRC" -vframes 1 \
    -vf "crop=${CROP_W}:${CROP_H}:${CROP_X}:${CROP_Y},scale=${SIZE}:${SIZE}:flags=lanczos,unsharp=5:5:0.5,eq=contrast=1.04:saturation=1.06" \
    -q:v 2 "$OUT" 2>/tmp/make_avatar_photo_err.log
}

# Petite retouche "portrait" : un soupçon de netteté + contraste/saturation,
# utile maintenant que c'est une image fixe regardée en continu plutôt
# qu'un flux vidéo où l'œil ne s'attarde pas sur un défaut ponctuel.
if ! extract "$SAFE_TS" || [ ! -s "$OUT" ]; then
  echo "Avertissement : extraction à ${SAFE_TS}s a échoué, nouvel essai à 0s..." >&2
  if ! extract 0 || [ ! -s "$OUT" ]; then
    echo "ERREUR : impossible d'extraire une image depuis $SRC (voir /tmp/make_avatar_photo_err.log) :" >&2
    cat /tmp/make_avatar_photo_err.log >&2
    exit 1
  fi
fi

echo "Photo avatar prête : $OUT"
