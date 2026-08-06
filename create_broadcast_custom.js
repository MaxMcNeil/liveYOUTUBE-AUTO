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
  // flux. Si un ancien broadcast (test précédent, run précédent...) est
  // resté accroché à ce même flux, on le supprime avant d'en créer un
  // nouveau, sinon le nouveau échoue avec "clé de flux déjà attribuée".
  try {
    const { data: existing } = await youtube.liveBroadcasts.list({
      part: ['id', 'contentDetails', 'status'],
      broadcastStatus: 'upcoming',
      mine: true,
    });
    for (const b of existing.items || []) {
      if (b.contentDetails?.boundStreamId === YOUTUBE_STREAM_ID) {
        console.log(`Suppression de l'ancien broadcast ${b.id} (encore lié au même flux)...`);
        await youtube.liveBroadcasts.delete({ id: b.id });
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
  console.error('Erreur lors de la création du broadcast YouTube (non bloquant) :', err.message);
});
