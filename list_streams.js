/**
 * Liste tous les "liveStreams" (flux persistants) associés au compte
 * YouTube authentifié, avec leur ID et leur clé de stream — pour
 * identifier lequel correspond à YOUTUBE_STREAM_KEY et corriger le
 * secret YOUTUBE_STREAM_ID si besoin.
 */

const { google } = require('googleapis');

const { GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GOOGLE_REFRESH_TOKEN } = process.env;

async function main() {
  if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET || !GOOGLE_REFRESH_TOKEN) {
    console.error('Secrets Google manquants (GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET / GOOGLE_REFRESH_TOKEN).');
    process.exit(1);
  }

  const oauth2Client = new google.auth.OAuth2(GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET);
  oauth2Client.setCredentials({ refresh_token: GOOGLE_REFRESH_TOKEN });
  const youtube = google.youtube({ version: 'v3', auth: oauth2Client });

  const { data } = await youtube.liveStreams.list({
    part: ['id', 'snippet', 'cdn', 'status'],
    mine: true,
    maxResults: 25,
  });

  if (!data.items || data.items.length === 0) {
    console.log('Aucun flux persistant trouvé sur ce compte.');
    return;
  }

  console.log(`${data.items.length} flux trouvé(s) :\n`);
  for (const item of data.items) {
    console.log('----------------------------------------');
    console.log('ID (à utiliser comme YOUTUBE_STREAM_ID) :', item.id);
    console.log('Nom                                     :', item.snippet?.title);
    console.log('Clé de stream (streamName)              :', item.cdn?.ingestionInfo?.streamName);
    console.log('Statut                                  :', item.status?.streamStatus);
  }
  console.log('----------------------------------------');
  console.log('\nComparez "Clé de stream" ci-dessus avec votre secret YOUTUBE_STREAM_KEY.');
  console.log('Celui qui correspond → son "ID" est la bonne valeur pour le secret YOUTUBE_STREAM_ID.');
}

main().catch((err) => {
  console.error('Erreur :', err.message);
  process.exit(1);
});
