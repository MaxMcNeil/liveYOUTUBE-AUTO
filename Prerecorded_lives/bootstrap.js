/**
 * Point d'entrée unique du projet.
 *
 * Usage (une seule fois, en local, après avoir rempli config.yml) :
 *   npm install
 *   node bootstrap.js
 *
 * Ce script :
 *   1. Lit config.yml
 *   2. Écrit ~/.oci/config à partir de la section oci: (pour que
 *      Terraform s'authentifie sans rien avoir à coller ailleurs)
 *   3. Si google.enabled=true et refresh_token vide : ouvre
 *      l'autorisation Google dans le navigateur UNE SEULE FOIS, puis
 *      réécrit config.yml avec le refresh_token obtenu — les
 *      lancements suivants sautent cette étape automatiquement.
 *   4. Génère terraform/terraform.tfvars à partir de config.yml
 *   5. Lance `terraform init` puis `terraform apply -auto-approve`
 *
 * Relancer ce script plus tard (ex. pour changer instance_ocpus) est
 * sans danger : Terraform ne recrée que ce qui a changé.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');
const { URL } = require('url');
const { execFileSync, spawnSync } = require('child_process');
const YAML = require('yaml');

const CONFIG_PATH = path.join(__dirname, 'config.yml');
const TERRAFORM_DIR = path.join(__dirname, 'terraform');

function expandHome(p) {
  if (!p) return p;
  return p.startsWith('~') ? path.join(os.homedir(), p.slice(1)) : p;
}

function loadConfig() {
  if (!fs.existsSync(CONFIG_PATH)) {
    console.error(`Fichier introuvable : ${CONFIG_PATH}`);
    console.error('Copiez config.yml.example en config.yml, remplissez-le, puis relancez.');
    process.exit(1);
  }
  return YAML.parse(fs.readFileSync(CONFIG_PATH, 'utf-8'));
}

function saveConfig(doc) {
  fs.writeFileSync(CONFIG_PATH, YAML.stringify(doc));
}

function writeOciConfig(oci) {
  const dir = path.join(os.homedir(), '.oci');
  fs.mkdirSync(dir, { recursive: true });
  const content = [
    '[DEFAULT]',
    `user=${oci.user_ocid}`,
    `fingerprint=${oci.fingerprint}`,
    `tenancy=${oci.compartment_ocid}`,
    `region=${oci.region}`,
    `key_file=${expandHome(oci.key_file)}`,
    '',
  ].join('\n');
  fs.writeFileSync(path.join(dir, 'config'), content, { mode: 0o600 });
  console.log('~/.oci/config généré.');
}

/**
 * Autorisation OAuth Google, une seule fois. Ouvre un petit serveur
 * local le temps de récupérer le code, puis l'échange contre un
 * refresh_token.
 */
function getGoogleRefreshToken(clientId, clientSecret) {
  return new Promise((resolve, reject) => {
    const { google } = require('googleapis');
    const PORT = 53682;
    const REDIRECT_URI = `http://localhost:${PORT}/oauth2callback`;
    const oauth2Client = new google.auth.OAuth2(clientId, clientSecret, REDIRECT_URI);

    const authUrl = oauth2Client.generateAuthUrl({
      access_type: 'offline',
      prompt: 'consent',
      scope: ['https://www.googleapis.com/auth/youtube'],
    });

    console.log('\n=== Autorisation Google requise (une seule fois) ===');
    console.log('Ouvrez cette URL, connectez-vous avec le compte propriétaire de la chaîne :\n');
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
        res.end('Autorisation reçue, vous pouvez fermer cet onglet.');
        server.close();
        const { tokens } = await oauth2Client.getToken(code);
        resolve(tokens.refresh_token);
      } catch (err) {
        server.close();
        reject(err);
      }
    });

    server.listen(PORT);
  });
}

function hclEscape(str) {
  return String(str).replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

function writeTfvars(config) {
  const { oci, ssh, youtube, google } = config;
  const lines = [
    `compartment_ocid      = "${hclEscape(oci.compartment_ocid)}"`,
    `region                = "${hclEscape(oci.region)}"`,
    `ssh_public_key_path   = "${hclEscape(expandHome(ssh.public_key_path))}"`,
    `ssh_private_key_path  = "${hclEscape(expandHome(ssh.private_key_path))}"`,
    `ssh_allowed_cidr      = "${hclEscape(ssh.allowed_cidr)}"`,
    `instance_ocpus        = ${Number(oci.instance_ocpus || 2)}`,
    `instance_memory_gb    = ${Number(oci.instance_memory_gb || 12)}`,
    `youtube_stream_key    = "${hclEscape(youtube.stream_key)}"`,
    `youtube_stream_id     = "${hclEscape(youtube.stream_id || '')}"`,
    `google_client_id      = "${hclEscape(google.enabled ? google.client_id : '')}"`,
    `google_client_secret  = "${hclEscape(google.enabled ? google.client_secret : '')}"`,
    `google_refresh_token  = "${hclEscape(google.enabled ? (google.refresh_token || '') : '')}"`,
    '',
  ];
  fs.writeFileSync(path.join(TERRAFORM_DIR, 'terraform.tfvars'), lines.join('\n'), { mode: 0o600 });
  console.log('terraform/terraform.tfvars généré.');
}

function runTerraform() {
  console.log('\n=== terraform init ===');
  let r = spawnSync('terraform', ['init'], { cwd: TERRAFORM_DIR, stdio: 'inherit' });
  if (r.status !== 0) {
    console.error('Échec de terraform init — vérifiez que Terraform est installé (terraform --version).');
    process.exit(1);
  }

  console.log('\n=== terraform apply ===');
  r = spawnSync('terraform', ['apply', '-auto-approve'], { cwd: TERRAFORM_DIR, stdio: 'inherit' });
  if (r.status !== 0) {
    console.error('Échec de terraform apply — voir le détail ci-dessus.');
    process.exit(1);
  }
}

async function main() {
  const config = loadConfig();

  if (!config.oci || !config.ssh || !config.youtube) {
    console.error('config.yml incomplet — comparez-le avec config.yml.example.');
    process.exit(1);
  }

  writeOciConfig(config.oci);

  if (config.google && config.google.enabled && !config.google.refresh_token) {
    if (!config.google.client_id || !config.google.client_secret) {
      console.error('google.enabled=true mais client_id/client_secret manquants dans config.yml.');
      process.exit(1);
    }
    const refreshToken = await getGoogleRefreshToken(config.google.client_id, config.google.client_secret);
    config.google.refresh_token = refreshToken;
    saveConfig(config);
    console.log('Refresh token obtenu et enregistré dans config.yml — cette étape ne se reproduira plus.');
  }

  writeTfvars(config);
  runTerraform();

  console.log('\n=== Terminé ===');
  console.log('Le VPS est créé et le pipeline déployé. Le live démarrera automatiquement');
  console.log('à 7h00 et 19h00, et s\'arrêtera à 11h00 et minuit, indéfiniment.');
}

main().catch((err) => {
  console.error('Erreur :', err.message);
  process.exit(1);
});
