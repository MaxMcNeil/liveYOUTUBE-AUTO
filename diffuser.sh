#!/usr/bin/env bash
# Diffuse les vidéos de Prerecorded_lives/ sur la clé de flux de la chaîne choisie (CHAINE = fr | ar).
cd "$(dirname "$0")"
if [ "$CHAINE" = "ar" ]; then export YOUTUBE_STREAM_KEY="${KEY_AR:-}"; else export YOUTUBE_STREAM_KEY="${KEY_FR:-}"; fi
YOUTUBE_STREAM_KEY=$(printf '%s' "$YOUTUBE_STREAM_KEY" | tr -d '[:space:]')
[ -n "$YOUTUBE_STREAM_KEY" ] || { echo "::error::Clé de flux absente pour la chaîne $CHAINE."; exit 1; }
chmod +x push_prerecorded.sh
./push_prerecorded.sh
