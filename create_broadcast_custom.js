/**
 * Lit Prerecorded_lives/input_METADATA.txt et, si le champ "Titre"
 * est renseigné, crée un nouveau broadcast YouTube avec ce titre et
 * la description donnée, lié au flux persistant.
 *
 * Si "Titre" est vide (ou le fichier absent), ne fait rien : les
 * titre/description déjà configurés sur YouTube restent inchangés.
 */

const { google } = require('googleapis');
const fs = require('fs');
const path = require('path');

const {
  GOOGLE_CLIENT_ID,
  GOOGLE_CLIENT_SECRET,
  GOOGLE_REFRESH_TOKEN,
  YOUTUBE_STREAM_ID,
} = process.env;

const METADATA_PATH = path.join(__dirname, 'Prerecorded_lives', 'input_METADATA.txt');

function parseMetadata(raw) {
  const titleMatch = raw.match(/^Titre\s*:\s*(.*)$/im);
  const title = titleMatch ? titleMatch[1].trim() : '';

  const descIndex = raw.search(/^Description\s*:/im);
  let description = '';
  if (descIndex !== -1) {
    const afterLabel = raw.slice(descIndex).replace(/^Description\s*:\s*/i, '');
    description = afterLabel.trim();
  }
  return { title, description };
}

async function main() {
  if (!fs.existsSync(METADATA_PATH)) {
    console.log('Aucun input_METADATA.txt trouvé — titre/description YouTube par défaut conservés.');
    return;
  }

  const raw = fs.readFileSync(METADATA_PATH, 'utf-8');
  const { title, description } = parseMetadata(raw);

  if (!title) {
    console.log('Champ "Titre" vide — titre/description YouTube par défaut conservés.');
    return;
  }

  if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET || !GOOGLE_REFRESH_TOKEN || !YOUTUBE_STREAM_ID) {
    console.log('Titre renseigné, mais automatisation Google non configurée (secrets absents) — étape ignorée.');
    return;
  }

  const oauth2Client = new google.auth.OAuth2(GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET);
  oauth2Client.setCredentials({ refresh_token: GOOGLE_REFRESH_TOKEN });
  const youtube = google.youtube({ version: 'v3', auth: oauth2Client });

  // Nettoyage : YouTube n'autorise qu'un seul broadcast actif par clé de
  // flux. On regarde TOUS les statuts (broadcastStatus: 'all'), pas
  // seulement 'upcoming' : un run précédent annulé/coupé en plein direct
  // peut laisser un broadcast bloqué en 'testing' ou 'live', qu'un filtre
  // 'upcoming' seul ne renverrait jamais — et c'est justement ce
  // broadcast bloqué qui reste bindé au flux et récupère le prochain
  // live à la place du nouveau.
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

  console.log(`Création du broadcast : "${title}"`);

  const { data: broadcast } = await youtube.liveBroadcasts.insert({
    part: ['snippet', 'status', 'contentDetails'],
    requestBody: {
      snippet: {
        title,
        description,
        scheduledStartTime: new Date().toISOString(),
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
  // Une vraie erreur ici (contrairement au titre vide ou aux secrets
  // absents, gérés plus haut par un retour anticipé) signifie que le
  // broadcast n'a pas été créé/lié correctement : mieux vaut faire
  // échouer le job maintenant que de laisser stream_session.sh démarrer
  // et diffuser sous le titre/la miniature de l'ancien live.
  console.error('Erreur lors de la création du broadcast YouTube :', err.message);
  process.exit(1);
});
