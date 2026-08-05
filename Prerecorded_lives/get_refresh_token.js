/**
 * À exécuter UNE SEULE FOIS, EN LOCAL sur votre ordinateur (pas sur le
 * VPS), pour obtenir un refresh_token Google réutilisable indéfiniment
 * par create_daily_broadcast.js.
 *
 * Prérequis : créer un identifiant OAuth "Application de bureau" dans
 * Google Cloud Console (voir README.md section "Automatisation
 * YouTube") et activer l'API "YouTube Data API v3" sur le projet.
 *
 * Usage :
 *   npm install googleapis
 *   GOOGLE_CLIENT_ID=... GOOGLE_CLIENT_SECRET=... node get_refresh_token.js
 */

const { google } = require('googleapis');
const http = require('http');
const { URL } = require('url');

const CLIENT_ID = process.env.GOOGLE_CLIENT_ID;
const CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET;
const PORT = 53682;
const REDIRECT_URI = `http://localhost:${PORT}/oauth2callback`;

if (!CLIENT_ID || !CLIENT_SECRET) {
  console.error('Définissez GOOGLE_CLIENT_ID et GOOGLE_CLIENT_SECRET avant de lancer ce script.');
  process.exit(1);
}

const oauth2Client = new google.auth.OAuth2(CLIENT_ID, CLIENT_SECRET, REDIRECT_URI);

const authUrl = oauth2Client.generateAuthUrl({
  access_type: 'offline',
  prompt: 'consent',
  scope: ['https://www.googleapis.com/auth/youtube'],
});

console.log('\nOuvrez cette URL dans votre navigateur et connectez-vous avec le compte propriétaire de la chaîne :\n');
console.log(authUrl);
console.log('\nEn attente de l\'autorisation...\n');

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, REDIRECT_URI);
    if (url.pathname !== '/oauth2callback') {
      res.end('OK');
      return;
    }
    const code = url.searchParams.get('code');
    res.end('Autorisation reçue, vous pouvez fermer cet onglet et revenir au terminal.');
    server.close();

    const { tokens } = await oauth2Client.getToken(code);
    console.log('Refresh token obtenu — ajoutez cette ligne à /opt/livestream/.env sur le VPS :\n');
    console.log(`GOOGLE_REFRESH_TOKEN=${tokens.refresh_token}`);
    console.log(`GOOGLE_CLIENT_ID=${CLIENT_ID}`);
    console.log(`GOOGLE_CLIENT_SECRET=${CLIENT_SECRET}`);
  } catch (err) {
    console.error('Erreur lors de l\'échange du code :', err.message);
    server.close();
  }
});

server.listen(PORT);
