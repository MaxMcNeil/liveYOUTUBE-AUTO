#!/usr/bin/env bash
# Vérifie la clé de flux de la chaîne choisie (CHAINE = fr | ar) avant tout téléchargement.
KEY_FR=$(printf '%s' "${KEY_FR:-}" | tr -d '[:space:]'); KEY_AR=$(printf '%s' "${KEY_AR:-}" | tr -d '[:space:]')
if [ "$CHAINE" = "ar" ]; then
  [ -n "$KEY_AR" ] || { echo "::error::Chaîne arabe choisie mais le secret YOUTUBE_STREAM_KEY_AR n'existe pas. Termux : gh secret set YOUTUBE_STREAM_KEY_AR --repo ${GITHUB_REPOSITORY} (clé : YouTube Studio de Gulf think-tank → Passer au direct → Flux)."; exit 1; }
  [ "$KEY_AR" != "$KEY_FR" ] || { echo "::error::YOUTUBE_STREAM_KEY_AR est identique à la clé française : le direct partirait sur Le Journal du NON. Mets la clé de la chaîne Gulf think-tank."; exit 1; }
else
  [ -n "$KEY_FR" ] || { echo "::error::Secret YOUTUBE_STREAM_KEY manquant."; exit 1; }
fi
echo "Chaîne : $CHAINE — clé de flux présente."
