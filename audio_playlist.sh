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
#                  scripts/schedule_and_publish.py (narration longue en
#                  voix clonée, noms préfixés par leur heure de départ
#                  programmée, ex: "01845_v007.wav"). Ne jamais y
#                  déposer un fichier à la main.
#
# Priorité : si "voice_ia" contient des fichiers programmés, c'est elle
# qui pilote la playlist (mode planifié, voir plus bas) et "voice" est
# ignorée pour ce live-là. Si "voice_ia" est vide, comportement
# classique avec "voice" : voix 1, musique 1, voix 2, musique 2, ...
# jusqu'à la dernière voix, puis musique seule en boucle.
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

# play_track_bg : même chose que play_track mais NE bloque PAS — sert
# uniquement au mode planifié ci-dessous, pour pouvoir surveiller
# l'heure pendant que la musique joue et la couper au bon moment.
play_track_bg() {
  local file="$1"
  local volume_filter="${2:-}"

  if [ ! -s "$file" ]; then
    CURRENT_PID=""
    return 1
  fi

  if [ -n "$volume_filter" ]; then
    ffmpeg -re -i "$file" -filter:a "$volume_filter" -f pulse -device "$SINK_NAME" \
      -nostats -loglevel warning "livestream-audio" &
  else
    ffmpeg -re -i "$file" -f pulse -device "$SINK_NAME" \
      -nostats -loglevel warning "livestream-audio" &
  fi
  CURRENT_PID=$!
}

mapfile -t MUSIC_FILES < <(find "$MUSIC_DIR" -maxdepth 1 -type f | sort)
mapfile -t VOICE_IA_FILES < <(find "$VOICE_IA_DIR" -maxdepth 1 -type f ! -name '*.json' | sort)

n_music=${#MUSIC_FILES[@]}

# --- Choix de la source de voix --------------------------------------
# "voice_ia" (narration clonée programmée) est prioritaire dès qu'elle
# contient au moins un fichier valide (préfixe "SSSSS_" = heure de
# départ en secondes, déposé uniquement par scripts/schedule_and_publish.py).
# Si elle est vide ou invalide, on ignore totalement "voice_ia" et on
# repart sur "voice" (tes enregistrements ponctuels), comportement
# strictement identique à avant.
SCHEDULED_MODE=false
declare -a VOICE_OFFSETS
declare -a VOICE_FILES

if [ "${#VOICE_IA_FILES[@]}" -gt 0 ]; then
  all_prefixed=true
  declare -a candidate_offsets
  for f in "${VOICE_IA_FILES[@]}"; do
    base="$(basename "$f")"
    if [[ "$base" =~ ^([0-9]{5})_ ]]; then
      candidate_offsets+=("$((10#${BASH_REMATCH[1]}))")
    else
      all_prefixed=false
      break
    fi
  done

  if [ "$all_prefixed" = true ]; then
    SCHEDULED_MODE=true
    VOICE_FILES=("${VOICE_IA_FILES[@]}")
    VOICE_OFFSETS=("${candidate_offsets[@]}")
    echo "[audio-playlist] Release 'voice_ia' valide trouvée (${#VOICE_FILES[@]} morceau(x)) — 'voice' ignorée pour ce live."
  else
    echo "[audio-playlist] Release 'voice_ia' présente mais fichiers non conformes (préfixe manquant) — ignorée par sécurité, repli sur 'voice'."
  fi
fi

if [ "$SCHEDULED_MODE" = false ]; then
  mapfile -t VOICE_FILES < <(find "$VOICE_DIR" -maxdepth 1 -type f ! -name '*.json' | sort)
fi

n_voice=${#VOICE_FILES[@]}
echo "[audio-playlist] ${n_voice} voix, ${n_music} musiques trouvées."

if [ "$n_voice" -eq 0 ] && [ "$n_music" -eq 0 ]; then
  echo "[audio-playlist] Aucun fichier audio (ni musique ni voix), rien à jouer."
  exit 0
fi

music_idx=0

if [ "$n_voice" -gt 0 ] && [ "$SCHEDULED_MODE" = true ]; then
  DURATION_SECONDS="${DURATION_SECONDS:-20700}"
  echo "[audio-playlist] Mode planifié détecté (${n_voice} voix avec heure de départ programmée)."
  SESSION_START=$(date +%s)
  voice_i=0

  while [ "$voice_i" -lt "$n_voice" ]; do
    target="${VOICE_OFFSETS[$voice_i]}"

    # Lance de la musique en fond en attendant l'heure de la prochaine voix.
    if [ "$n_music" -gt 0 ]; then
      idx=$((music_idx % n_music))
      play_track_bg "${MUSIC_FILES[$idx]}" "volume=0.15"
      music_idx=$((music_idx + 1))
    else
      CURRENT_PID=""
    fi

    # Attend soit l'heure prévue, soit la fin naturelle du morceau de
    # musique (auquel cas on enchaîne le suivant sans attendre).
    elapsed=$(( $(date +%s) - SESSION_START ))
    while [ "$elapsed" -lt "$target" ]; do
      if [ -n "$CURRENT_PID" ] && ! kill -0 "$CURRENT_PID" 2>/dev/null; then
        if [ "$n_music" -gt 0 ]; then
          idx=$((music_idx % n_music))
          play_track_bg "${MUSIC_FILES[$idx]}" "volume=0.15"
          music_idx=$((music_idx + 1))
        fi
      fi
      sleep 1
      elapsed=$(( $(date +%s) - SESSION_START ))
    done

    # Coupe net la musique en cours pour laisser place à la voix.
    if [ -n "$CURRENT_PID" ]; then
      kill "$CURRENT_PID" 2>/dev/null || true
      wait "$CURRENT_PID" 2>/dev/null || true
      CURRENT_PID=""
    fi

    echo "[audio-playlist] t=${elapsed}s — Voix $((voice_i + 1))/${n_voice} (prévue à ${target}s, volume original) : ${VOICE_FILES[$voice_i]}"
    play_track "${VOICE_FILES[$voice_i]}" ""

    voice_i=$((voice_i + 1))
  done

  echo "[audio-playlist] Toutes les voix planifiées ont été jouées. Boucle musique uniquement jusqu'à la fin du live."
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
