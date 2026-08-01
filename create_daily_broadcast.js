/**
 * Crée automatiquement, avant chaque fenêtre de diffusion, un nouveau
 * "live broadcast" YouTube avec le titre du jour (dd-mm-yyyy) et la
 * description fixe, puis le lie au flux persistant (celui identifié
 * par YOUTUBE_STREAM_ID) sur lequel ffmpeg pousse déjà le RTMP.
 *
 * Prévu pour être lancé par systemd ~5-10 min avant chaque fenêtre
 * (07h00 et 19h00), voir youtube-metadata.timer.
 *
 * Variables requises dans /opt/livestream/.env :
 *   GOOGLE_CLIENT_ID
 *   GOOGLE_CLIENT_SECRET
 *   GOOGLE_REFRESH_TOKEN   (obtenu une fois via get_refresh_token.js)
 *   YOUTUBE_STREAM_ID      (id du flux persistant lié à votre clé de stream)
 */

const { google } = require('googleapis');
const fs = require('fs');
const path = require('path');

require('dotenv').config({ path: path.join(__dirname, '.env') });

const {
  GOOGLE_CLIENT_ID,
  GOOGLE_CLIENT_SECRET,
  GOOGLE_REFRESH_TOKEN,
  YOUTUBE_STREAM_ID,
} = process.env;

function pad(n) {
  return String(n).padStart(2, '0');
}

function formatDateFr(d) {
  return `${pad(d.getDate())}-${pad(d.getMonth() + 1)}-${d.getFullYear()}`;
}

/**
 * Détermine la fenêtre en cours (matin ou soir) à partir de l'heure
 * locale au moment de l'exécution, pour fixer les horaires
 * programmés du broadcast.
 */
function getWindow(now) {
  const hour = now.getHours();
  if (hour < 15) {
    // Fenêtre du matin : 07h00 - 11h00
    const start = new Date(now);
    start.setHours(7, 0, 0, 0);
    const end = new Date(now);
    end.setHours(11, 0, 0, 0);
    return { start, end, label: 'matin' };
  }
  // Fenêtre du soir : 19h00 - minuit
  const start = new Date(now);
  start.setHours(19, 0, 0, 0);
  const end = new Date(now);
  end.setDate(end.getDate() + 1);
  end.setHours(0, 0, 0, 0);
  return { start, end, label: 'soir' };
}

async function main() {
  if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET || !GOOGLE_REFRESH_TOKEN || !YOUTUBE_STREAM_ID) {
    console.error('Variables Google/YouTube manquantes dans .env — voir README.md section "Automatisation YouTube".');
    process.exit(1);
  }

  const oauth2Client = new google.auth.OAuth2(GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET);
  oauth2Client.setCredentials({ refresh_token: GOOGLE_REFRESH_TOKEN });
  const youtube = google.youtube({ version: 'v3', auth: oauth2Client });

  const now = new Date();
  const { start, end, label } = getWindow(now);
  const title = `${formatDateFr(start)} : Dernières dépêches SANS FILTRES`;
  const description = fs.readFileSync(path.join(__dirname, 'youtube_description.txt'), 'utf-8');

  console.log(`Création du broadcast (${label}) : "${title}"`);

  const { data: broadcast } = await youtube.liveBroadcasts.insert({
    part: ['snippet', 'status', 'contentDetails'],
    requestBody: {
      snippet: {
        title,
        description,
        scheduledStartTime: start.toISOString(),
        scheduledEndTime: end.toISOString(),
      },
      status: {
        privacyStatus: 'public',
        selfDeclaredMadeForKids: false,
      },
      contentDetails: {
        enableAutoStart: true,
        enableAutoStop: true,
        enableDvr: true,
        latencyPreference: 'normal',
      },
    },
  });

  console.log(`Broadcast créé : ${broadcast.id}`);

  await youtube.liveBroadcasts.bind({
    id: broadcast.id,
    part: ['id'],
    streamId: YOUTUBE_STREAM_ID,
  });

  console.log(`Broadcast ${broadcast.id} lié au flux persistant ${YOUTUBE_STREAM_ID}.`);
}

main().catch((err) => {
  console.error('Erreur lors de la création du broadcast YouTube :', err.message);
  process.exit(1);
});
