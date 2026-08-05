# Livestream YouTube autonome — @LejournalduNON

Diffusion automatique tous les jours de 7h00 à 11h00 et de 19h00 à minuit,
en rotation continue sur trois sites :

1. https://maxmcneil.github.io/dls-monitor/
2. https://maxmcneil.github.io/FranceLiveNews/
3. https://maxmcneil.github.io/slideshow/

Chaque site tourne en boucle infinie et à durée variable. Le passage au
site suivant est déclenché quand le contenu affiché redevient identique
à son point de départ (détection par empreinte), pas par un minutage
fixe. Un garde-fou (`maxLoopMs` dans `config.json`) force le passage au
site suivant même si la détection échoue, pour ne jamais rester bloqué.

## Architecture

```
Xvfb (écran virtuel) → Chromium en kiosk → ffmpeg (x11grab) → RTMP
                              ↑
                     orchestrator.js (pilote la navigation
                     via le port de debug distant 9222)
```

Le flux vidéo est envoyé **simultanément** au flux RTMP principal et au
flux de secours YouTube (méthode "redundant streaming" recommandée par
YouTube) — YouTube bascule lui-même côté serveur si le flux principal
tombe, pas besoin de logique de bascule manuelle.

## Déploiement 100% automatisé via GitHub Actions (recommandé)

Aucun ordinateur local requis : GitHub Actions exécute tout à votre
place, avec un accès internet complet.

### 1. Créer le repo et y pousser ce dossier

```bash
git init && git add . && git commit -m "livestream autonome"
git remote add origin <votre-repo-github>
git push -u origin main
```

### 2. Renseigner les secrets du repo

**Settings > Secrets and variables > Actions > New repository secret**,
un par un :

| Secret | Valeur |
|---|---|
| `OCI_TENANCY_OCID` | OCID du tenancy (sert aussi de compartiment racine) |
| `OCI_USER_OCID` | OCID de votre utilisateur OCI |
| `OCI_FINGERPRINT` | Empreinte de votre clé API OCI |
| `OCI_PRIVATE_KEY` | Contenu complet de votre clé privée API OCI (le bloc `-----BEGIN PRIVATE KEY-----...`) |
| `OCI_REGION` | ex. `eu-turin-1` |
| `SSH_PRIVATE_KEY` | Une clé privée SSH **dédiée à ce projet** (`ssh-keygen -t ed25519 -f livestream_key -N ""` puis collez le contenu de `livestream_key`) |
| `YOUTUBE_STREAM_KEY` | Clé de stream YouTube Studio |
| `YOUTUBE_STREAM_ID` | Optionnel — voir section automatisation YouTube |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | Optionnels — voir section automatisation YouTube |
| `GH_PAT` | Optionnel, requis seulement pour l'automatisation YouTube — voir plus bas |

⚠️ Utilisez une **nouvelle** clé API OCI, générée après avoir révoqué
celle collée précédemment dans ce chat (Console OCI > Identity &
Security > Users > API Keys).

### 3. Lancer le déploiement

Onglet **Actions** du repo > workflow **"Déployer le livestream"** >
**Run workflow**.

Ce workflow crée le VPS (ARM Ampere A1, Always Free) et y installe
tout le pipeline. Une fois terminé (quelques minutes), **le live
tourne en continu sur le VPS lui-même**, via ses propres timers
systemd — GitHub Actions n'a plus besoin de tourner en permanence, il
ne sert qu'au provisionnement initial (et aux mises à jour futures si
vous relancez le workflow après avoir changé un secret).

### 4. Activer l'automatisation du titre/description YouTube (optionnel)

Nécessite deux choses **une seule fois** — inévitables côté Google et
GitHub, aucune façon de les automatiser davantage :

**a) Créer un jeton GitHub (`GH_PAT`)** — pour que le workflow
d'autorisation puisse enregistrer lui-même le secret
`GOOGLE_REFRESH_TOKEN` :
**Settings (de votre compte) > Developer settings > Personal access
tokens > Fine-grained tokens > Generate new token**, portée limitée à
ce repo, permission **Secrets: Read and write**. Collez-le dans le
secret `GH_PAT` du repo.

**b) Autoriser l'accès YouTube :**

1. Construisez cette URL en remplaçant `VOTRE_CLIENT_ID` par la valeur
   de votre secret `GOOGLE_CLIENT_ID` :

   ```
   https://accounts.google.com/o/oauth2/v2/auth?client_id=VOTRE_CLIENT_ID&redirect_uri=http://localhost:53682/oauth2callback&response_type=code&scope=https://www.googleapis.com/auth/youtube&access_type=offline&prompt=consent
   ```

2. Ouvrez-la dans le navigateur de votre téléphone, connectez-vous
   avec le compte propriétaire de la chaîne, acceptez les permissions.
3. La redirection échoue à charger (normal — `localhost` pointe vers
   votre téléphone, pas vers un serveur), mais **la barre d'adresse**
   contient désormais une URL du type
   `http://localhost:53682/oauth2callback?code=XXXXX&scope=...`.
   Copiez uniquement la valeur après `code=` et avant le `&` suivant.
4. Onglet **Actions** > workflow **"Autorisation Google (une seule
   fois)"** > **Run workflow** > collez le code.

Le workflow échange le code contre un `refresh_token` permanent et
l'enregistre lui-même comme secret `GOOGLE_REFRESH_TOKEN`. Relancez
ensuite le workflow **"Déployer le livestream"** : l'automatisation du
titre/description quotidiens s'active automatiquement, pour toujours.

Il vous faut aussi le secret `YOUTUBE_STREAM_ID` (ID du flux
persistant, YouTube Studio > Diffuser en direct > paramètres du flux)
pour que ça fonctionne.

---

## Alternative locale — un seul fichier à remplir, une seule commande

Si vous préférez ne pas utiliser GitHub Actions : même logique, mais
lancée depuis votre propre machine. ⚠️ `node bootstrap.js` s'exécute
**depuis votre ordinateur** (pas un outil distant) : c'est votre
machine qui a besoin d'un accès internet, jamais partagé ailleurs.

### 1. Prérequis locaux (une fois)

```bash
brew install terraform oci-cli   # ou apt/choco selon votre OS
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519   # si vous n'avez pas déjà de clé SSH
npm install
```

### 2. Remplir config.yml (une fois)

```bash
cp config.yml.example config.yml
```

Ouvrez `config.yml` et remplissez : vos identifiants OCI (compartment,
région, user OCID, fingerprint, **chemin** vers votre clé privée — ne
collez jamais son contenu), vos chemins SSH, votre IP publique, votre
clé de stream YouTube. La section `google:` est optionnelle (titre/
description quotidiens automatiques) — laissez `enabled: false` pour
la sauter.

⚠️ Si vous avez déjà collé une clé API OCI ailleurs (chat, ticket, etc.),
**révoquez-la et générez-en une nouvelle** avant de la référencer ici
(Console OCI > Identity & Security > Users > API Keys).

### 3. Lancer

```bash
node bootstrap.js
```

Ce script fait tout, dans l'ordre : configure `~/.oci/config`, obtient
(une seule fois, si `google.enabled: true`) l'autorisation YouTube via
un lien à ouvrir dans votre navigateur et l'enregistre pour toujours
dans `config.yml`, génère la configuration Terraform, crée le VPS
(ARM Ampere A1, Always Free) et y déploie tout le pipeline
automatiquement. En quelques minutes le live tourne seul, tous les
jours, sans autre intervention.

Relancer `node bootstrap.js` plus tard (ex. après avoir changé
`instance_ocpus` dans `config.yml`) est sans danger — Terraform
n'ajuste que ce qui a changé.

<details>
<summary>Alternative : Terraform seul, sans config.yml (avancé)</summary>

Voir `terraform/terraform.tfvars.example` — copiez-le en
`terraform.tfvars`, remplissez-le, puis `terraform init && terraform
apply` depuis le dossier `terraform/`.

</details>

<details>
<summary>Installation manuelle sur un VPS déjà existant (sans Terraform)</summary>

```bash
scp -r livestream/ user@votre-vps:~/
ssh user@votre-vps
cd livestream && sudo bash deploy.sh
```

</details>

## Automatisation YouTube — titre daté + description quotidiens

Chaque jour, avant chaque fenêtre, `create_daily_broadcast.js` crée un
nouveau broadcast YouTube avec le titre `dd-mm-yyyy : Dernières
dépêches SANS FILTRES` et la description dans `youtube_description.txt`,
lié à votre flux persistant.

Pour l'activer : dans `config.yml`, passez `google.enabled: true` et
remplissez `client_id` / `client_secret`. Une seule chose ne peut pas
être automatisée (Google l'exige pour tout accès à un compte YouTube) :

### Étape unique côté Google Cloud Console (5 min, une fois)

1. https://console.cloud.google.com → créer un projet
2. **APIs & Services > Library** → activer **YouTube Data API v3**
3. **APIs & Services > Credentials** → **Create Credentials > OAuth
   client ID** → type **Desktop app**
4. Copiez le `Client ID` et le `Client Secret` dans `config.yml`
   (`google.client_id`, `google.client_secret`)

Il vous faut aussi l'**ID du flux persistant** YouTube
(`youtube.stream_id` dans `config.yml`) : YouTube Studio > Diffuser en
direct > icône paramètres du flux, ou via l'API `liveStreams.list`.

Ensuite, `node bootstrap.js` ouvrira automatiquement une URL
d'autorisation Google dans votre terminal — un clic dans le
navigateur, une seule fois. Le `refresh_token` obtenu est aussitôt
enregistré dans `config.yml` : tous les lancements suivants de
`bootstrap.js` sautent cette étape automatiquement.

## Minutage de rotation

Les news des trois sites ont des formats trop variables (dates, heures,
alertes) pour qu'une empreinte de contenu soit fiable. `config.json` est
donc réglé sur un **défilement fixe de 3 minutes par site**
(`minLoopMs` = `maxLoopMs` = 180000), quel que soit l'état de la boucle
au moment du changement. `signatureSelector` et `stableRepeatsToConfirm`
restent dans le fichier mais n'ont plus d'effet avec ce réglage — c'est
la présence du garde-fou `maxLoopMs` qui déclenche systématiquement le
passage au site suivant.

Pour changer la durée, modifier `minLoopMs` et `maxLoopMs` (en
millisecondes, identiques) pour chacun des trois sites dans
`config.json`, puis redémarrer le service :

```bash
sudo systemctl restart livestream.service
```

## Test manuel (avant de passer par systemd)

```bash
cd /opt/livestream
export YOUTUBE_STREAM_KEY=votre-cle-secrete-ici
./start_stream.sh
```

Vérifiez sur YouTube Studio que le flux principal ET le flux de secours
sont bien reçus ("Statut de l'ingestion" côté principal, endpoint de
secours listé séparément).

## Mise en place de la planification automatique (7h-11h / 19h-minuit)

```bash
sudo cp livestream.service livestream-start.service livestream-start.timer \
        livestream-stop.service livestream-stop.timer /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now livestream-start.timer
sudo systemctl enable --now livestream-stop.timer
```

Le service `livestream.service` n'est pas activé en permanence : il est
uniquement démarré/arrêté par les deux timers. En cas de plantage
pendant une fenêtre de diffusion, `Restart=on-failure` le relance
automatiquement.

## Commandes utiles

```bash
# Statut en direct
sudo systemctl status livestream.service
journalctl -u livestream.service -f

# Forcer un démarrage/arrêt manuel (test)
sudo systemctl start livestream.service
sudo systemctl stop livestream.service

# Voir les prochains déclenchements programmés
systemctl list-timers livestream-start.timer livestream-stop.timer
```

## Notes

- Le serveur doit rester allumé en continu (VPS recommandé, pas un
  poste personnel qui peut se mettre en veille).
- Bande passante recommandée : au moins 3 Mbps montants stables (le
  pipeline encode à ~2,1 Mbps, dimensionné pour le shape Always Free
  E2.1.Micro).
- Si YouTube exige une vérification (compte avec restriction sur les
  lives de longue durée / vérification de téléphone), le stream
  s'arrêtera côté YouTube indépendamment de ce pipeline — à vérifier en
  amont dans YouTube Studio.
