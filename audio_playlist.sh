#!/usr/bin/env bash
#
# Playlist audio jouée en fond pendant le live, mixée dans le même sink
# PulseAudio que Chromium (donc capturée par ffmpeg avec le reste).
#
# Sources : deux Releases GitHub du dépôt, taguées "music" et "voice".
#   - "music"  : joué en boucle, un morceau à la fois, volume 30 %.
#   - "voice"  : chaque fichier joué UNE SEULE FOIS, volume original
#                (jamais de boucle sur la voix).
#
# Ordre : voix 1, musique 1, voix 2, musique 2, ... jusqu'à la dernière
# voix. Une fois toutes les voix jouées, on ignore les voix (il n'y en a
# plus) et on boucle uniquement sur la musique jusqu'à la fin du live.
#
# Arguments :
#   $1 = nom du sink PulseAudio à utiliser (ex: streamsink)
#
# Variables d'environnement requises :
#   GITHUB_REPOSITORY (déjà fourni automatiquement par GitHub Actions)
#   GITHUB_TOKEN       (pour lire les releases, même sur dépôt public)

set -uo pipefail

SINK_NAME="${1:?nom du sink PulseAudio manquant}"

MUSIC_DIR="/tmp/audio-music"
VOICE_DIR="/tmp/audio-voice"
mkdir -p "$MUSIC_DIR" "$VOICE_DIR"

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

echo "[audio-playlist] Téléchargement des releases 'music' et 'voice'..."
download_release_assets "music" "$MUSIC_DIR"
download_release_assets "voice" "$VOICE_DIR"

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
mapfile -t VOICE_FILES < <(find "$VOICE_DIR" -maxdepth 1 -type f | sort)

n_voice=${#VOICE_FILES[@]}
n_music=${#MUSIC_FILES[@]}
echo "[audio-playlist] ${n_voice} voix, ${n_music} musiques trouvées."

if [ "$n_voice" -eq 0 ] && [ "$n_music" -eq 0 ]; then
  echo "[audio-playlist] Aucun fichier audio (ni musique ni voix), rien à jouer."
  exit 0
fi

music_idx=0

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
