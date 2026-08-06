# Livestream YouTube autonome — @LejournalduNON

Diffusion 100% automatisée sur GitHub Actions, sans serveur/VPS à gérer.

## Deux workflows

### 1. Diffusion programmée (`stream-scheduled.yml`)

Rotation en boucle de 3 sites web (dls-monitor, FranceLiveNews,
slideshow — 3 min chacun), diffusée en format vertical (1080×1920).

Déclenchement automatique chaque semaine :

| Cron (UTC) | Jour | Heure Paris (été, UTC+2) |
|---|---|---|
| `0 8 * * 0` | Dimanche | 10h00 |
| `0 18 * * 6` | Samedi | 20h00 |
| `0 18 * * 2` | Mardi | 20h00 |

⚠️ Fin octobre (passage à l'heure d'hiver UTC+1), décaler chaque cron
de +1h dans `.github/workflows/stream-scheduled.yml`.

Chaque session dure 1h et s'arrête automatiquement. Peut aussi être
lancée manuellement (Actions → workflow → **Run workflow**).

### 2. Vidéos préenregistrées à la demande (`prerecorded-live-now.yml`)

Diffuse en direct, à l'instant où vous lancez le workflow, une ou
plusieurs vidéos hébergées dans une **GitHub Release** taguée
`prerecorded-lives` (voir `Prerecorded_lives/README.md` pour la
procédure d'upload — les gros fichiers ne passent pas par git).

- Vidéos enchaînées par ordre alphabétique, sans coupure ni transition
- Aucune boucle : chaque vidéo n'est jouée qu'une fois, arrêt
  automatique à la fin
- Formats/résolutions mélangés uniformisés automatiquement en 1080×1920
- Titre/description personnalisables via `Prerecorded_lives/input_METADATA.txt`
  (laissé vide → défauts YouTube conservés)

Déclenchement uniquement manuel : Actions → **"Prerecorded_Live_Now"**
→ **Run workflow**.

## Secrets requis (Settings > Secrets and variables > Actions)

| Secret | Description |
|---|---|
| `YOUTUBE_STREAM_KEY` | Clé de stream, YouTube Studio > Diffuser en direct |
| `YOUTUBE_STREAM_ID` | ID du flux persistant correspondant à cette clé (voir `list_streams.js` ci-dessous pour le retrouver) |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | Identifiants OAuth (Google Cloud Console, type "Desktop app") |
| `GOOGLE_REFRESH_TOKEN` | Généré une seule fois via le workflow `google-auth-exchange.yml` |
| `GH_PAT` | Fine-grained token (permission Secrets: Read/write) — seulement pour que `google-auth-exchange.yml` puisse enregistrer `GOOGLE_REFRESH_TOKEN` lui-même |

## Autorisation Google (une seule fois)

1. Google Cloud Console → activer **YouTube Data API v3**, créer un
   identifiant OAuth **Desktop app** → `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET`
2. **Écran de consentement OAuth** → **Publish app** (évite l'expiration
   du token au bout de 7 jours en statut "Testing")
3. Construire l'URL :
   ```
   https://accounts.google.com/o/oauth2/v2/auth?client_id=VOTRE_CLIENT_ID&redirect_uri=http://localhost:53682/oauth2callback&response_type=code&scope=https://www.googleapis.com/auth/youtube&access_type=offline&prompt=consent
   ```
4. Ouvrir sur votre téléphone, autoriser, copier le `code=` dans la
   barre d'adresse (la redirection échoue à charger, c'est normal)
5. Actions → **"Autorisation Google (une seule fois)"** → coller le code

Le refresh token obtenu est permanent et s'enregistre automatiquement
comme secret — cette étape ne se refait plus jamais.

## Outil de diagnostic — retrouver le bon YOUTUBE_STREAM_ID

Si le titre/description ne s'appliquent pas (erreur "Stream not found"
dans les logs), le secret `YOUTUBE_STREAM_ID` ne correspond pas à
`YOUTUBE_STREAM_KEY`. Pour le retrouver :

Actions → **"Debug_List_YouTube_Streams"** → **Run workflow** → les
logs listent tous vos flux avec leur ID et leur clé — comparez la clé
affichée dans YouTube Studio pour identifier le bon ID.

## Fichiers du projet

- `orchestrator.js` — pilote la rotation des 3 sites (mode programmé)
- `stream_session.sh` — capture d'écran + ffmpeg pour le mode programmé
- `push_prerecorded.sh` — enchaîne et diffuse les vidéos préenregistrées
- `create_broadcast_now.js` — titre/description datés (mode programmé)
- `create_broadcast_custom.js` — titre/description depuis `input_METADATA.txt` (mode vidéos)
- `list_streams.js` — diagnostic `YOUTUBE_STREAM_ID`
- `config.json` — timing de rotation des sites
- `youtube_description.txt` — texte de description (mode programmé)
- `Prerecorded_lives/` — dossier d'accueil du fichier de métadonnées (les vidéos vont en Release, pas ici)

## Notes

- Dépôt public → minutes GitHub Actions illimitées, y compris pour
  des vidéos longues.
- Le direct pousse les vidéos en temps réel (pas plus vite) : une
  vidéo de 1h consomme 1h d'exécution du workflow.
- Limite dure GitHub Actions : 6h max par run.
