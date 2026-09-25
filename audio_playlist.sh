#!/usr/bin/env bash
#
# Playlist audio jouée en fond pendant le live, mixée dans le même sink
# PulseAudio que Chromium (donc capturée par ffmpeg avec le reste).
#
# Sources : trois Releases GitHub du dépôt, taguées "music", "voice"
# et "voice_ia".
#   - "music"    : joué en boucle, un morceau à la fois, volume 15 %.
#   - "voice"    : TES vrais enregistrements ponctuels, déposés à la
#                  main. Chaque fichier joué UNE SEULE FOIS, volume
#                  original. Cette release n'est JAMAIS modifiée ni
#                  vidée par le workflow de narration clonée — c'est
#                  entièrement à toi de la gérer.
#   - "voice_ia" : réservée EXCLUSIVEMENT aux morceaux générés par
#                  scripts/schedule_and_publish.py (narration en voix
#                  clonée). Ne jamais y déposer un fichier à la main.
#
# Priorité : si "voice_ia" contient des fichiers, c'est elle qui pilote
# le début du live (voir "mode séquentiel" plus bas) et "voice" est
# ignorée pour ce live-là. Si "voice_ia" est vide, comportement
# classique avec "voice" : voix 1, musique 1, voix 2, musique 2, ...
# jusqu'à la dernière voix, puis musique seule en boucle.
#
# MODE SÉQUENTIEL (voice_ia) : le live démarre par 5s de silence total
# (ni musique ni bips), puis tous les morceaux de voice_ia s'enchaînent
# du premier au dernier SANS musique entre eux. Une fois la narration
# terminée, le live reprend son fonctionnement normal (bips/musique en
# boucle, comme pour tous les autres lives).
#
# Arguments :
#   $1 = nom du sink PulseAudio à utiliser (ex: streamsink)
#
# Variables d'environnement requises :
#   GITHUB_REPOSITORY (déjà fourni automatiquement par GitHub Actions)
#   GITHUB_TOKEN       (pour lire les releases, même sur dépôt public)

set -uo pipefail

SINK_NAME="${1:?nom du sink PulseAudio manquant}"

# Silence total en tout début de live, avant que la narration clonée ne
# démarre (mode séquentiel uniquement — sans effet si voice_ia est vide).
SILENCE_BEFORE_VOICE_IA_S="${SILENCE_BEFORE_VOICE_IA_S:-5}"

MUSIC_DIR="/tmp/audio-music"
VOICE_DIR="/tmp/audio-voice"
VOICE_IA_DIR="/tmp/audio-voice-ia"
mkdir -p "$MUSIC_DIR" "$VOICE_DIR" "$VOICE_IA_DIR"

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY manquant}"

CURRENT_PID=""
cleanup_playlist() {
  if [ -n "$CURRENT_PID" ]; then
    kill "$CURRENT_PID" 2>/dev/null || true
  fi
  exit 0
}
trap cleanup_playlist TERM INT

download_release_assets() {
  local tag="$1"
  local dest_dir="$2"
  local api_url="https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/tags/${tag}"
  local auth_header=()
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    auth_header=(-H "Authorization: token ${GITHUB_TOKEN}")
  fi

  local response
  response="$(curl -s "${auth_header[@]}" "$api_url")"

  local count
  count="$(echo "$response" | jq '.assets | length' 2>/dev/null || echo "")"
  if [ -z "$count" ] || [ "$count" = "0" ] || [ "$count" = "null" ]; then
    echo "[audio-playlist] Aucun fichier trouvé pour la release '${tag}' (release absente ou vide)."
    return 0
  fi

  echo "[audio-playlist] ${count} fichier(s) à télécharger depuis la release '${tag}'."
  echo "$response" | jq -r '.assets[] | "\(.id)\t\(.name)"' | \
  while IFS=$'\t' read -r asset_id name; do
    echo "[audio-playlist]   - ${name}"
    curl -sL "${auth_header[@]}" -H "Accept: application/octet-stream" \
      "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/assets/${asset_id}" \
      -o "${dest_dir}/${name}" || \
      echo "[audio-playlist]     échec du téléchargement de ${name}, ignoré."
  done
}

echo "[audio-playlist] Téléchargement des releases 'music', 'voice' et 'voice_ia'..."
download_release_assets "music" "$MUSIC_DIR"
download_release_assets "voice" "$VOICE_DIR"
download_release_assets "voice_ia" "$VOICE_IA_DIR"

# play_track FICHIER FILTRE_VOLUME(optionnel)
# Bloque jusqu'à la fin de la lecture. Lance ffmpeg en arrière-plan et
# attend sur son PID (pas un simple appel bloquant) pour que le trap
# TERM/INT puisse le tuer immédiatement si le script reçoit un signal
# pendant la lecture (sinon bash ne transmet pas le signal à un enfant
# lancé au premier plan dans une boucle).
play_track() {
  local file="$1"
  local volume_filter="${2:-}"

  if [ ! -s "$file" ]; then
    echo "[audio-playlist] Fichier introuvable ou vide, ignoré : ${file}"
    return 0
  fi

  if [ -n "$volume_filter" ]; then
    ffmpeg -re -i "$file" -filter:a "$volume_filter" -f pulse -device "$SINK_NAME" \
      -nostats -loglevel warning "livestream-audio" &
  else
    ffmpeg -re -i "$file" -f pulse -device "$SINK_NAME" \
      -nostats -loglevel warning "livestream-audio" &
  fi
  CURRENT_PID=$!
  wait "$CURRENT_PID" 2>/dev/null || true
  CURRENT_PID=""
}


mapfile -t MUSIC_FILES < <(find "$MUSIC_DIR" -maxdepth 1 -type f | sort)
mapfile -t VOICE_IA_FILES < <(find "$VOICE_IA_DIR" -maxdepth 1 -type f ! -name '*.json' | sort)

n_music=${#MUSIC_FILES[@]}

# --- Choix de la source de voix --------------------------------------
# "voice_ia" (narration en voix clonée) est prioritaire dès qu'elle
# contient au moins un fichier. Si elle est vide, on repart sur "voice"
# (tes enregistrements ponctuels), comportement strictement identique
# à avant.
SEQUENTIAL_MODE=false
declare -a VOICE_FILES

if [ "${#VOICE_IA_FILES[@]}" -gt 0 ]; then
  SEQUENTIAL_MODE=true
  VOICE_FILES=("${VOICE_IA_FILES[@]}")
  echo "[audio-playlist] Release 'voice_ia' trouvée (${#VOICE_FILES[@]} morceau(x)) — mode séquentiel, 'voice' ignorée pour ce live."
else
  mapfile -t VOICE_FILES < <(find "$VOICE_DIR" -maxdepth 1 -type f ! -name '*.json' | sort)
fi

n_voice=${#VOICE_FILES[@]}
echo "[audio-playlist] ${n_voice} voix, ${n_music} musiques trouvées."

if [ "$n_voice" -eq 0 ] && [ "$n_music" -eq 0 ]; then
  echo "[audio-playlist] Aucun fichier audio (ni musique ni voix), rien à jouer."
  exit 0
fi

music_idx=0

if [ "$n_voice" -gt 0 ] && [ "$SEQUENTIAL_MODE" = true ]; then
  echo "[audio-playlist] Mode narration clonée séquentielle : ${SILENCE_BEFORE_VOICE_IA_S}s de silence, puis ${n_voice} morceau(x) à la suite, sans musique entre eux."
  sleep "$SILENCE_BEFORE_VOICE_IA_S"

  for ((i = 0; i < n_voice; i++)); do
    echo "[audio-playlist] Voix IA $((i + 1))/${n_voice} (volume original) : ${VOICE_FILES[$i]}"
    play_track "${VOICE_FILES[$i]}" ""
  done

  echo "[audio-playlist] Narration terminée. Reprise du fonctionnement normal (bips/musique en boucle)."
else
  # --- Ancien mode (inchangé) : voix 1, musique 1, voix 2, musique 2... ---
  for ((i = 0; i < n_voice; i++)); do
    echo "[audio-playlist] Voix $((i + 1))/${n_voice} (volume original, sans boucle) : ${VOICE_FILES[$i]}"
    play_track "${VOICE_FILES[$i]}" ""

    if [ "$n_music" -gt 0 ]; then
      idx=$((music_idx % n_music))
      echo "[audio-playlist] Musique (15%) : ${MUSIC_FILES[$idx]}"
      play_track "${MUSIC_FILES[$idx]}" "volume=0.15"
      music_idx=$((music_idx + 1))
    fi
  done

  echo "[audio-playlist] Toutes les voix ont été jouées. Boucle musique uniquement jusqu'à la fin du live."
fi

if [ "$n_music" -eq 0 ]; then
  echo "[audio-playlist] Aucune musique disponible, fin de la playlist."
  exit 0
fi

while true; do
  idx=$((music_idx % n_music))
  echo "[audio-playlist] Musique (boucle, 15%) : ${MUSIC_FILES[$idx]}"
  play_track "${MUSIC_FILES[$idx]}" "volume=0.15"
  music_idx=$((music_idx + 1))
done
