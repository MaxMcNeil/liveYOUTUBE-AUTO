#!/usr/bin/env bash
# Titre / description du direct (création, programmation ou reprise d'un direct programmé) — chaque chaîne n'utilise QUE
# ses propres identifiants Google (aucun repli de l'arabe vers le français).
# Entrées : CHAINE (fr|ar), PRIVACY, secrets TOKEN_FR/TOKEN_AR, STREAM_ID_FR/AR, KEY_FR/AR, GOOGLE_CLIENT_ID/SECRET ;
#           facultatif : SCHEDULED_AT (programmer), REUSE_ID (reprise), PREV_ID (ancien direct programmé), BROADCAST_ID_FILE.
cd "$(dirname "$0")"
if [ -s Prerecorded_lives/input_METADATA_faceless.txt ]; then META=Prerecorded_lives/input_METADATA_faceless.txt
elif [ "$CHAINE" = "ar" ]; then META=Prerecorded_lives/input_METADATA_ar.txt
else META=Prerecorded_lives/input_METADATA.txt; fi
if [ "$CHAINE" = "ar" ]; then
  if [ -z "${TOKEN_AR:-}" ]; then
    echo "::warning::Titre et description NON posés sur le direct : l'autorisation Google de la chaîne arabe manque (secret GOOGLE_REFRESH_TOKEN_AR). Le direct part avec le titre réglé dans YouTube Studio${SCHEDULED_AT:+ (et l'annonce du direct programmé n'apparaît pas sur la chaîne)}."
    exit 0
  fi
  export GOOGLE_REFRESH_TOKEN="$TOKEN_AR" YOUTUBE_STREAM_ID="${STREAM_ID_AR:-}" YOUTUBE_STREAM_KEY="${KEY_AR:-}" FALLBACK_TITLE="بث مباشر — Gulf think-tank"
else
  export GOOGLE_REFRESH_TOKEN="${TOKEN_FR:-}" YOUTUBE_STREAM_ID="${STREAM_ID_FR:-}" YOUTUBE_STREAM_KEY="${KEY_FR:-}" FALLBACK_TITLE="Le Journal du NON — en direct"
fi
METADATA_FILE="$META" node create_broadcast_custom.js
