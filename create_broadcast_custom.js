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
} = process.env;
// la clé arrive parfois avec un espace ou un retour à la ligne collé par erreur dans le secret
const YOUTUBE_STREAM_KEY = (process.env.YOUTUBE_STREAM_KEY || '').trim();
let { YOUTUBE_STREAM_ID } = process.env;

// METADATA_FILE : fichier propre à la chaîne choisie (ex. input_METADATA_ar.txt) ; par défaut le fichier habituel.
const METADATA_PATH = process.env.METADATA_FILE
  ? path.resolve(__dirname, process.env.METADATA_FILE)
  : path.join(__dirname, 'Prerecorded_lives', 'input_METADATA.txt');

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

async function cancelOnly(id) {
  if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET || !GOOGLE_REFRESH_TOKEN) { console.log('Annonce non supprimée : autorisation Google absente pour cette chaîne.'); return; }
  const oauth2Client = new google.auth.OAuth2(GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET);
  oauth2Client.setCredentials({ refresh_token: GOOGLE_REFRESH_TOKEN });
  const youtube = google.youtube({ version: 'v3', auth: oauth2Client });
  const { data } = await youtube.liveBroadcasts.list({ part: ['id', 'status'], id: [id] });
  const st = data.items?.[0]?.status?.lifeCycleStatus;
  if (!st) { console.log(`Direct programmé ${id} déjà supprimé.`); return; }
  if (!['created', 'ready'].includes(st)) { console.log(`Direct ${id} en état « ${st} » : pas supprimé (il a déjà commencé).`); return; }
  await youtube.liveBroadcasts.delete({ id });
  console.log(`Direct programmé ${id} supprimé de la chaîne.`);
}

async function main() {
  if (process.env.CANCEL_ID) return cancelOnly(process.env.CANCEL_ID.trim());
  if (!fs.existsSync(METADATA_PATH) && !process.env.SCHEDULED_AT && !process.env.REUSE_ID) {
    console.log('Aucun input_METADATA.txt trouvé — titre/description YouTube par défaut conservés.');
    return;
  }

  const raw = fs.existsSync(METADATA_PATH) ? fs.readFileSync(METADATA_PATH, 'utf-8') : '';
  const { title, description } = parseMetadata(raw);

  // direct PROGRAMMÉ (SCHEDULED_AT) ou reprise d'un direct programmé (REUSE_ID) : il faut un titre pour l'annonce
  const SCHEDULED_AT = (process.env.SCHEDULED_AT || '').trim();
  const REUSE_ID = (process.env.REUSE_ID || '').trim();
  const PREV_ID = (process.env.PREV_ID || '').trim();
  const ID_FILE = process.env.BROADCAST_ID_FILE || '';
  const effectiveTitle = title || ((SCHEDULED_AT || REUSE_ID) ? (process.env.FALLBACK_TITLE || 'Live') : '');
  if (!effectiveTitle) {
    console.log('Champ "Titre" vide — titre/description YouTube par défaut conservés.');
    return;
  }

  if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET || !GOOGLE_REFRESH_TOKEN || (!YOUTUBE_STREAM_ID && !YOUTUBE_STREAM_KEY)) {
    console.log('Titre renseigné, mais automatisation Google non configurée (secrets absents) — étape ignorée.');
    return;
  }

  const oauth2Client = new google.auth.OAuth2(GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET);
  oauth2Client.setCredentials({ refresh_token: GOOGLE_REFRESH_TOKEN });
  const youtube = google.youtube({ version: 'v3', auth: oauth2Client });

  // Sur quelle chaîne ces identifiants agissent-ils ? Écrit dans le journal du run.
  try {
    const { data: me } = await youtube.channels.list({ part: ['snippet'], mine: true });
    console.log(`Chaîne YouTube de cette autorisation : « ${me.items?.[0]?.snippet?.title || 'inconnue'} »`);
  } catch (chErr) {
    console.log('Nom de la chaîne non lu :', chErr.message);
  }

  // VÉRIFICATION ANTI-ERREUR DE CHAÎNE : la clé de flux qui va servir à diffuser doit appartenir à la chaîne de cette
  // autorisation. Sinon le titre serait posé sur une chaîne et la vidéo partirait sur une autre (ou resterait sans
  // titre) sans que rien ne le signale. L'identifiant du flux est retrouvé à partir de la clé : le secret
  // YOUTUBE_STREAM_ID devient facultatif, et un identifiant périmé est corrigé tout seul.
  if (YOUTUBE_STREAM_KEY) {
    const items = [];
    let pageToken;
    do {
      const { data: page } = await youtube.liveStreams.list({ part: ['id', 'cdn'], mine: true, maxResults: 50, pageToken });
      items.push(...(page.items || []));
      pageToken = page.nextPageToken;
    } while (pageToken && items.length < 500);
    const hit = items.find((x) => x.cdn?.ingestionInfo?.streamName === YOUTUBE_STREAM_KEY);
    if (!hit && YOUTUBE_STREAM_ID) {
      // comportement d'avant conservé : on fait confiance au secret YOUTUBE_STREAM_ID, mais on le signale
      console.log("⚠ La clé de flux n'a pas été retrouvée parmi les flux de cette chaîne : identifiant du secret YOUTUBE_STREAM_ID utilisé tel quel.");
    } else if (!hit) {
      throw new Error("la clé de flux n'appartient pas à la chaîne de cette autorisation Google (clé d'une autre chaîne, ou clé régénérée dans YouTube Studio). Vérifie le secret de la clé de flux et l'autorisation de cette chaîne.");
    }
    if (hit) {
      if (YOUTUBE_STREAM_ID && YOUTUBE_STREAM_ID !== hit.id) console.log('YOUTUBE_STREAM_ID ne correspondait pas à la clé de flux : identifiant corrigé automatiquement.');
      YOUTUBE_STREAM_ID = hit.id;
    }
  }

  // Nettoyage : YouTube n'autorise qu'un seul broadcast actif par clé de
  // flux. On regarde TOUS les statuts (broadcastStatus: 'all'), pas
  // seulement 'upcoming' : un run précédent annulé/coupé en plein direct
  // peut laisser un broadcast bloqué en 'testing' ou 'live', qu'un filtre
  // 'upcoming' seul ne renverrait jamais — et c'est justement ce
  // broadcast bloqué qui reste bindé au flux et récupère le prochain
  // live à la place du nouveau.
  // Programmer un direct : on ne touche à AUCUN autre direct (un direct en cours continue) ; seul l'ancien direct
  // programmé de cette chaîne (PREV_ID) est supprimé, s'il n'a pas encore commencé.
  if (SCHEDULED_AT) {
    if (PREV_ID) {
      try {
        const { data: prev } = await youtube.liveBroadcasts.list({ part: ['id', 'status'], id: [PREV_ID] });
        const st = prev.items?.[0]?.status?.lifeCycleStatus;
        if (st && ['created', 'ready'].includes(st)) { await youtube.liveBroadcasts.delete({ id: PREV_ID }); console.log(`Ancien direct programmé ${PREV_ID} supprimé.`); }
      } catch (e) { console.log('Ancien direct programmé non supprimé :', e.message); }
    }
  } else
  try {
    const { data: existing } = await youtube.liveBroadcasts.list({
      part: ['id', 'contentDetails', 'status', 'snippet'],
      broadcastStatus: 'all',
    });
    for (const b of existing.items || []) {
      if (b.contentDetails?.boundStreamId !== YOUTUBE_STREAM_ID) continue;
      if (REUSE_ID && b.id === REUSE_ID) continue;                       // le direct programmé qu'on va lancer
      const state = b.status?.lifeCycleStatus;
      if (state === 'complete' || state === 'revoked') continue;
      // direct PROGRAMMÉ pour plus tard (annonce visible par le public) : jamais supprimé ; détaché du flux le temps de
      // ce direct-ci, il sera rattaché à son heure par son propre run
      const when = Date.parse(b.snippet?.scheduledStartTime || '');
      if (['created', 'ready'].includes(state) && when > Date.now() + 20 * 60 * 1000) {
        await youtube.liveBroadcasts.bind({ id: b.id, part: ['id'] }).then(() => console.log(`Direct programmé ${b.id} (${b.snippet?.scheduledStartTime}) gardé, détaché du flux le temps de ce direct.`))
          .catch((e) => console.log(`Direct programmé ${b.id} non détaché :`, e.message));
        continue;
      }

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

  if (REUSE_ID) {
    try {
      const { data: r } = await youtube.liveBroadcasts.list({ part: ['id', 'status'], id: [REUSE_ID] });
      const st = r.items?.[0]?.status?.lifeCycleStatus;
      if (st && ['created', 'ready'].includes(st)) {
        await youtube.liveBroadcasts.bind({ id: REUSE_ID, part: ['id'], streamId: YOUTUBE_STREAM_ID });
        console.log(`Direct programmé ${REUSE_ID} rattaché au flux : il démarre avec la diffusion.`);
        if (ID_FILE) fs.writeFileSync(ID_FILE, REUSE_ID);
        return;
      }
      console.log(`Direct programmé ${REUSE_ID} introuvable ou déjà terminé (${st || 'supprimé'}) : un nouveau direct est créé.`);
    } catch (e) { console.log('Direct programmé non relu :', e.message, '— un nouveau direct est créé.'); }
  }

  const safeTitle = effectiveTitle.replace(/[<>]/g, '').slice(0, 100);
  const safeDescription = description.replace(/[<>]/g, '').slice(0, 4900);
  console.log(`Création du broadcast : "${safeTitle}"`);

  const { data: broadcast } = await youtube.liveBroadcasts.insert({
    part: ['snippet', 'status', 'contentDetails'],
    requestBody: {
      snippet: {
        title: safeTitle,
        description: safeDescription,
        scheduledStartTime: SCHEDULED_AT || new Date().toISOString(),
      },
      status: {
        privacyStatus: ['public', 'unlisted', 'private'].includes(process.env.PRIVACY) ? process.env.PRIVACY : 'public',
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
  if (ID_FILE) fs.writeFileSync(ID_FILE, broadcast.id);
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
