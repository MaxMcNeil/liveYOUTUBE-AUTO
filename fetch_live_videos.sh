#!/usr/bin/env bash
# Récupère et vérifie les vidéos du direct dans Prerecorded_lives/ (source : release prerecorded-lives de ce dépôt, ou
# dernier résultat « Faceless live arabic » de Push-overlay — version VERTICALE). Utilisé par le direct immédiat ET
# par la programmation d'un direct. Variables : SOURCE, OWNER, THIS_REPO, GH_TOKEN.
cd "$(dirname "$0")"
set -euo pipefail
mkdir -p Prerecorded_lives
find Prerecorded_lives -maxdepth 1 -type f ! -iname "input_METADATA*" ! -iname "README*" -delete
if [[ "$SOURCE" == *Faceless* ]]; then
  REPO="${OWNER}/Push-overlay"
  names=$(gh release view out-explainer --repo "$REPO" --json assets -q '.assets[].name' 2>/dev/null || true)
  [ -n "$names" ] || { echo "::error::Aucun résultat Faceless trouvé (release out-explainer de $REPO). Lance d'abord « Faceless live arabic » et vérifie la vidéo."; exit 1; }
  # le direct est TOUJOURS la version verticale (l'horizontale est pour la première YouTube)
  f=$(grep -E "^explainer-vertical-.*\.mp4$" <<<"$names" | sort | tail -n1 || true)
  [ -n "$f" ] || { echo "::error::Le dernier résultat Faceless n'a pas de version VERTICALE (le direct est toujours vertical). Relance Faceless avec format = « les deux » ou « vertical »."; exit 1; }
  echo "Résultat Faceless diffusé : $f"
  # garde-fous contre « la mauvaise vidéo part en direct » : résultat ancien, ou montage Faceless encore en cours
  pub=$(gh release view out-explainer --repo "$REPO" --json publishedAt -q .publishedAt 2>/dev/null || true)
  if [ -n "$pub" ]; then
    age=$(( ( $(date -u +%s) - $(date -u -d "$pub" +%s) ) / 3600 ))
    echo "Résultat publié le $pub (il y a ${age} h)."
    [ "$age" -lt 48 ] || echo "::warning::Ce résultat Faceless date de plus de 2 jours : vérifie que c'est bien la vidéo voulue."
  fi
  busy=$(gh api "repos/$REPO/actions/workflows/faceless-live-arabic.yml/runs?per_page=5" -q '[.workflow_runs[]|select(.status!="completed")]|length' 2>/dev/null || echo 0)
  [ "$busy" = "0" ] || echo "::warning::Un montage Faceless est en cours dans Push-overlay : la vidéo diffusée est celle du résultat PRÉCÉDENT ($f)."
  gh release download out-explainer --repo "$REPO" --pattern "$f" --dir Prerecorded_lives --clobber
  # fiche YouTube écrite par Faceless (titre, description, tags, hashtags) : posée telle quelle sur le direct
  rm -f Prerecorded_lives/input_METADATA_faceless.txt
  if grep -qx "youtube-metadata.txt" <<<"$names"; then
    gh release download out-explainer --repo "$REPO" --pattern "youtube-metadata.txt" --dir /tmp/ytmeta --clobber \
      && mv /tmp/ytmeta/youtube-metadata.txt Prerecorded_lives/input_METADATA_faceless.txt \
      && echo "Titre du direct : $(grep -m1 -i '^Titre' Prerecorded_lives/input_METADATA_faceless.txt | cut -c1-120)"
  else echo "::warning::Pas de fiche YouTube dans le résultat Faceless : titre habituel conservé."; fi
else
  gh release download prerecorded-lives \
    --repo "${THIS_REPO}" \
    --dir Prerecorded_lives \
    --clobber \
    --pattern "*" || {
      echo "::error::Aucune release nommée 'prerecorded-lives' trouvée, ou aucune vidéo attachée. Voir Prerecorded_lives/README.md."
      exit 1
    }
fi
# chaque fichier doit être une vidéo lisible AVEC du son (sinon le direct s'arrêterait en plein milieu)
n=0
while IFS= read -r v; do
  ffprobe -v error -select_streams v:0 -show_entries stream=codec_type -of csv=p=0 "$v" | grep -q video || { echo "::error::Fichier illisible ou sans image : $(basename "$v")"; exit 1; }
  ffprobe -v error -select_streams a:0 -show_entries stream=codec_type -of csv=p=0 "$v" | grep -q audio || { echo "::error::Vidéo sans son : $(basename "$v")"; exit 1; }
  n=$((n + 1))
done < <(find Prerecorded_lives -maxdepth 1 -type f ! -iname "input_METADATA*" ! -iname "README*" ! -iname ".*" | sort)
[ "$n" -ge 1 ] || { echo "::error::Aucune vidéo à diffuser."; exit 1; }
echo "$n vidéo(s) prête(s)."
