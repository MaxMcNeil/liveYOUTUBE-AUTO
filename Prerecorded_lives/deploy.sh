#!/usr/bin/env bash
#
# Installation complète en une seule commande : dépendances système,
# copie du projet, dépendances Node, clé de stream, services systemd,
# et activation de la planification (7h-11h / 19h-minuit).
#
# À exécuter avec les droits root sur le VPS, depuis le dossier
# contenant tous les fichiers du projet (README.md, orchestrator.js,
# config.json, start_stream.sh, package.json, livestream*.service,
# livestream*.timer).
#
#   sudo bash deploy.sh

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Merci de lancer ce script avec sudo : sudo bash deploy.sh"
  exit 1
fi

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="/opt/livestream"

echo "==> Installation des paquets système..."
apt update
apt install -y xvfb chromium ffmpeg curl nodejs npm

echo "==> Copie du projet vers ${TARGET_DIR}..."
mkdir -p "$TARGET_DIR"
cp "$SRC_DIR"/*.js "$SRC_DIR"/*.json "$SRC_DIR"/*.sh "$TARGET_DIR"/
[ -f "$SRC_DIR/youtube_description.txt" ] && cp "$SRC_DIR/youtube_description.txt" "$TARGET_DIR/"
chmod +x "$TARGET_DIR/start_stream.sh"

echo "==> Installation des dépendances Node..."
cd "$TARGET_DIR"
npm install
npx playwright install-deps

if [ -n "${YOUTUBE_STREAM_KEY:-}" ] && [ ! -f "$TARGET_DIR/.env" ]; then
  echo "==> Clé de stream fournie via l'environnement (mode non-interactif)."
  echo "YOUTUBE_STREAM_KEY=${YOUTUBE_STREAM_KEY}" > "$TARGET_DIR/.env"
  chmod 600 "$TARGET_DIR/.env"
elif [ ! -f "$TARGET_DIR/.env" ]; then
  echo "==> Configuration de la clé de stream YouTube."
  echo "    (disponible dans YouTube Studio > Créer > Diffuser en direct > Clé de flux)"
  read -r -s -p "Collez votre clé de stream YouTube puis Entrée : " STREAM_KEY
  echo
  echo "YOUTUBE_STREAM_KEY=${STREAM_KEY}" > "$TARGET_DIR/.env"
  chmod 600 "$TARGET_DIR/.env"
  echo "    Clé enregistrée dans ${TARGET_DIR}/.env (jamais affichée ni transmise ailleurs)."
else
  echo "==> ${TARGET_DIR}/.env existe déjà, clé de stream conservée telle quelle."
fi

echo "==> Installation des services systemd..."
cp "$SRC_DIR"/livestream.service "$SRC_DIR"/livestream-start.service \
   "$SRC_DIR"/livestream-start.timer "$SRC_DIR"/livestream-stop.service \
   "$SRC_DIR"/livestream-stop.timer /etc/systemd/system/

systemctl daemon-reload
systemctl enable --now livestream-start.timer
systemctl enable --now livestream-stop.timer

if [ -f "$SRC_DIR/youtube-metadata.service" ] && [ -f "$TARGET_DIR/.env" ] && grep -q GOOGLE_REFRESH_TOKEN "$TARGET_DIR/.env" 2>/dev/null; then
  echo "==> Identifiants Google détectés, activation de l'automatisation du titre/description YouTube..."
  cp "$SRC_DIR/youtube-metadata.service" "$SRC_DIR/youtube-metadata.timer" /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable --now youtube-metadata.timer
else
  echo "==> Automatisation du titre/description YouTube non activée (GOOGLE_REFRESH_TOKEN absent de .env)."
  echo "    Voir README.md section 'Automatisation YouTube' pour l'ajouter plus tard."
fi

echo
echo "==> Installation terminée."
echo "    Le live démarrera automatiquement à 7h00 et 19h00, et s'arrêtera à 11h00 et minuit."
echo "    Suivi en direct : journalctl -u livestream.service -f"
echo "    Prochains déclenchements : systemctl list-timers livestream-start.timer livestream-stop.timer"
