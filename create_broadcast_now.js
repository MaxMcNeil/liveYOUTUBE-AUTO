/**
 * Variante de create_daily_broadcast.js pour les sessions ponctuelles
 * du workflow GitHub Actions (stream-scheduled.yml) — pas de logique
 * de fenêtre horaire fixe (7h-11h/19h-minuit) comme sur le VPS,
 * juste "maintenant" + DURATION_SECONDS.
 *
 * Si les identifiants Google ne sont pas configurés (secrets absents),
 * ce script ne fait rien et se termine proprement (code 0) pour ne
 * jamais faire échouer le workflow — l'automatisation du titre/
 * description est optionnelle.
 */

const { google } = require('googleapis');
const fs = require('fs');
const path = require('path');

const {
  GOOGLE_CLIENT_ID,
  GOOGLE_CLIENT_SECRET,
  GOOGLE_REFRESH_TOKEN,
  YOUTUBE_STREAM_ID,
  DURATION_SECONDS,
} = process.env;

function pad(n) {
  return String(n).padStart(2, '0');
}

function formatDateFr(d) {
  return `${pad(d.getDate())}-${pad(d.getMonth() + 1)}-${d.getFullYear()}`;
}

async function main() {
  if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET || !GOOGLE_REFRESH_TOKEN || !YOUTUBE_STREAM_ID) {
    console.log('Automatisation YouTube non configurée (secrets Google absents) — étape ignorée.');
    return;
  }

  const oauth2Client = new google.auth.OAuth2(GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET);
  oauth2Client.setCredentials({ refresh_token: GOOGLE_REFRESH_TOKEN });
  const youtube = google.youtube({ version: 'v3', auth: oauth2Client });

  // Nettoyage : YouTube n'autorise qu'un seul broadcast actif par clé de
  // flux. On regarde TOUS les statuts (broadcastStatus: 'all'), pas
  // seulement 'upcoming' : un run précédent annulé/coupé en plein direct
  // (job GitHub Actions annulé) peut laisser un broadcast bloqué en
  // 'testing' ou 'live', qu'un filtre 'upcoming' seul ne renverrait
  // jamais — et c'est justement ce broadcast bloqué qui reste bindé au
  // flux et récupère le prochain live à la place du nouveau.
  try {
    const { data: existing } = await youtube.liveBroadcasts.list({
      part: ['id', 'contentDetails', 'status'],
      broadcastStatus: 'all',
    });
    for (const b of existing.items || []) {
      if (b.contentDetails?.boundStreamId !== YOUTUBE_STREAM_ID) continue;
      const state = b.status?.lifeCycleStatus;
      if (state === 'complete' || state === 'revoked') continue;

      if (state === 'live' || state === 'testing') {
        // Impossible de supprimer un broadcast encore en direct : il faut
        // d'abord le faire basculer proprement vers 'complete'.
        console.log(`Ancien broadcast ${b.id} bloqué en '${state}' — transition vers 'complete'...`);
        try {
          await youtube.liveBroadcasts.transition({
            id: b.id,
            broadcastStatus: 'complete',
            part: ['id', 'status'],
          });
        } catch (transitionErr) {
          console.log(`Transition de ${b.id} impossible :`, transitionErr.message);
        }
      } else {
        console.log(`Suppression de l'ancien broadcast ${b.id} (état: ${state})...`);
        await youtube.liveBroadcasts.delete({ id: b.id }).catch((delErr) => {
          console.log(`Suppression de ${b.id} impossible :`, delErr.message);
        });
      }
    }
  } catch (cleanupErr) {
    console.log('Nettoyage des anciens broadcasts ignoré :', cleanupErr.message);
  }

  const now = new Date();
  const durationSec = Number(DURATION_SECONDS || 3600);
  const end = new Date(now.getTime() + durationSec * 1000);

  const title = `${formatDateFr(now)} : Dernières dépêches SANS FILTRES`;
  const description = fs.readFileSync(path.join(__dirname, 'youtube_description.txt'), 'utf-8');

  console.log(`Création du broadcast : "${title}"`);

  const { data: broadcast } = await youtube.liveBroadcasts.insert({
    part: ['snippet', 'status', 'contentDetails'],
    requestBody: {
      snippet: {
        title,
        description,
        scheduledStartTime: now.toISOString(),
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
  // Une vraie erreur ici (contrairement aux secrets absents, gérés plus
  // haut par un retour anticipé) signifie que le broadcast n'a pas été
  // créé/lié correctement : mieux vaut faire échouer le job maintenant
  // que de laisser stream_session.sh démarrer et diffuser sous le
  // titre/la miniature de l'ancien live.
  console.error('Erreur lors de la création du broadcast YouTube :', err.message);
  process.exit(1);
});
