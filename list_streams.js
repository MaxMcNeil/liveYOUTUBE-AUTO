/**
 * Diagnostic SANS DIFFUSION : affiche la chaîne YouTube de l'autorisation utilisée, ses flux persistants, et vérifie
 * que la clé de flux enregistrée en secret appartient bien à cette chaîne.
 *
 * SÉCURITÉ : ce dépôt est PUBLIC — n'importe qui peut lire les journaux des workflows. Une clé de flux permet de
 * diffuser sur la chaîne : elle n'est donc JAMAIS écrite en entier dans le journal (4 premiers caractères seulement).
 */

const { google } = require('googleapis');

const { GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GOOGLE_REFRESH_TOKEN } = process.env;
const KEY = (process.env.YOUTUBE_STREAM_KEY || '').trim();
const hide = (k) => (k ? `${String(k).slice(0, 4)}… (${String(k).length} caractères, masquée)` : '—');

async function main() {
  if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET || !GOOGLE_REFRESH_TOKEN) {
    console.error('Secrets Google manquants (GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET / autorisation de la chaîne).');
    process.exit(1);
  }

  const oauth2Client = new google.auth.OAuth2(GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET);
  oauth2Client.setCredentials({ refresh_token: GOOGLE_REFRESH_TOKEN });
  const youtube = google.youtube({ version: 'v3', auth: oauth2Client });

  const { data: me } = await youtube.channels.list({ part: ['snippet'], mine: true });
  console.log(`Chaîne autorisée : « ${me.items?.[0]?.snippet?.title || 'aucune chaîne sur ce compte'} »\n`);

  const items = [];
  let pageToken;
  do {
    const { data } = await youtube.liveStreams.list({ part: ['id', 'snippet', 'cdn', 'status'], mine: true, maxResults: 50, pageToken });
    items.push(...(data.items || []));
    pageToken = data.nextPageToken;
  } while (pageToken && items.length < 500);

  if (!items.length) console.log('Aucun flux persistant sur cette chaîne (YouTube Studio → Passer au direct → Flux).');
  for (const item of items) {
    const mine = KEY && item.cdn?.ingestionInfo?.streamName === KEY;
    console.log('----------------------------------------');
    console.log('ID (YOUTUBE_STREAM_ID…)  :', item.id);
    console.log('Nom                      :', item.snippet?.title);
    console.log('Clé de flux              :', hide(item.cdn?.ingestionInfo?.streamName), mine ? '  ← C\'EST LA CLÉ DU SECRET' : '');
    console.log('Statut                   :', item.status?.streamStatus);
  }
  console.log('----------------------------------------\n');

  if (!KEY) { console.log('Aucune clé de flux en secret pour cette chaîne : rien à comparer.'); return; }
  const ok = items.some((x) => x.cdn?.ingestionInfo?.streamName === KEY);
  if (ok) console.log('✅ La clé de flux du secret appartient bien à cette chaîne : le direct partira au bon endroit.');
  else {
    console.log("❌ La clé de flux du secret n'appartient à AUCUN flux de cette chaîne (clé d'une autre chaîne, ou régénérée dans YouTube Studio).");
    process.exit(1);
  }
}

main().catch((err) => {
  console.error('Erreur :', err.message);
  process.exit(1);
});
