# Live Face Cam Cloné

Avatar en incrustation (cercle, coin bas-droit, anneau audio-réactif)
+ habillage graphique type chaîne d'info, synchronisés sur la narration
en voix clonée (`voice_ia`, voir `../CLONED_VOICE_README.md`).

## ⚠️ Flux YouTube partagé avec le live existant

Ce projet pousse vers le **même flux YouTube persistant**
(`YOUTUBE_STREAM_ID` / `YOUTUBE_STREAM_KEY`) que le live de rotation de
sites (`manual-one-off-live.yml`). Les deux ne peuvent pas tourner en
même temps — lancer l'un pendant que l'autre est actif coupera le
premier. Aucun nouveau secret à configurer : tout est déjà en place
puisque les noms correspondent exactement à l'existant.

## Mise en place (une fois)

1. **Release `avatar_source`** — à créer, un seul fichier vidéo de
   toi (profil ou visage dégagé, cadrage stable, lèvres visibles pas
   nécessaire ici puisqu'il n'y a **pas de lip-sync** — juste une
   boucle vidéo silencieuse avec un anneau qui réagit au volume de la
   narration). 10 à 30s suffisent, la boucle "sans couture"
   (`make_loop.sh`) se charge du reste.
2. **`voice_ia`** doit déjà exister (généré via
   `generate-cloned-voice.yml`, voir `../CLONED_VOICE_README.md`) —
   c'est lui qui fournit à la fois la narration audio ET
   `narration_timing.json`, le minutage réel utilisé pour synchroniser
   les fiches visuelles.
3. **`scenes_source.json`** (à la racine de `facecam/`) décrit les
   fiches graphiques (type de carte, titre, panneau latéral...),
   chacune accrochée à une phrase exacte de la narration plutôt qu'à
   un horodatage — voir `build_content.py`. **Ce fichier est lié au
   texte précis de `voice_script.txt` utilisé pour le générer** : si
   tu changes le texte source, les ancres ne correspondront plus et
   `build_content.py` échouera avec un message clair indiquant
   lesquelles sont introuvables. Dans ce cas, redemande une mise à
   jour des scènes plutôt que de modifier les horodatages à la main.

## Les deux workflows

- **`Test — Live Face Cam Cloné`** : rend tout en un fichier MP4
  téléchargeable (artifact), ne touche jamais YouTube. À lancer
  systématiquement avant le vrai live. Le paramètre
  `max_duration_seconds` permet un aperçu rapide (ex: 60) plutôt que
  d'attendre toute la narration.
- **`Live — Face Cam Cloné`** : diffusion réelle sur YouTube. S'arrête
  pile à la fin de la narration (durée exacte lue dans
  `narration_timing.json`), flux primaire + secours comme le live
  existant.

## Comment ça fonctionne techniquement

`capture.sh` lance un Chromium réel (celui du paquet npm `playwright`,
même binaire que `stream_session.sh` — plus fiable que le paquet apt)
sur un écran virtuel (Xvfb), attend que la page confirme qu'elle est
prête ET que l'audio a démarré (via le protocole de debug Chrome,
CDP), puis capture l'écran en temps réel. L'audio n'est **pas**
capturé depuis une carte son système — le fichier de narration déjà
connu est collé directement en piste audio, calé sur l'instant exact
où la page avait déjà commencé à jouer. Résultat : aucun risque de
silence si le runner n'a pas de device audio, et un calage son/image
fiable même sans matériel audio réel.

Le rendu est une seule passe temps réel (jamais "capture puis envoi
après coup") — en mode test comme en mode live, pour que tester
valide vraiment le même mécanisme que la diffusion réelle.
