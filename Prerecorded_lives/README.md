# Dossier Prerecorded_lives/

Déposez ici une ou plusieurs vidéos (MP4 ou tout autre format lisible
par ffmpeg) à diffuser en direct sur YouTube au moment où vous lancez
le workflow **"Prerecorded_Live_Now"**.

## Règles

- **Ordre** : les vidéos sont diffusées dans l'ordre **alphabétique**
  de leur nom de fichier. Pour contrôler l'ordre, préfixez les noms
  (ex. `01-intro.mp4`, `02-suite.mp4`, `03-fin.mov`).
- **Enchaînement** : les vidéos sont reliées bout à bout sans coupure
  ni transition, comme une seule vidéo continue.
- **Pas de boucle** : chaque vidéo n'est jouée qu'une seule fois. Le
  direct s'arrête automatiquement dès que la dernière vidéo est
  terminée.
- **Formats mélangés** : les vidéos peuvent avoir des résolutions,
  formats ou codecs différents — elles sont toutes uniformisées
  automatiquement (1080×1920, 30 fps) avant l'enchaînement.
- **Audio requis** : chaque vidéo doit avoir une piste audio (même
  silencieuse). Une vidéo totalement dépourvue de piste audio fera
  échouer la diffusion.

## Titre et description

Remplissez `input_METADATA.txt` avant de lancer le workflow :

```
Titre: Mon titre du jour
Description : Ma description complète,
peut tenir sur plusieurs lignes.
```

- Si **Titre** est laissé vide → le titre/description YouTube par
  défaut (déjà configurés sur votre flux) sont conservés, rien n'est
  modifié.
- Si **Titre** est rempli → un nouveau live YouTube est créé avec ce
  titre et cette description (la description peut rester vide).

## Attention — taille des fichiers

GitHub refuse les fichiers de plus de 100 Mo poussés normalement avec
`git push`. Pour des vidéos plus lourdes, utilisez [Git LFS](https://git-lfs.com/) :

```bash
git lfs install
git lfs track "Prerecorded_lives/*.mp4"
git add .gitattributes
```

## Attention — minutes GitHub Actions

Le direct pousse les vidéos en temps réel (pas plus vite), donc une
vidéo de 2h consomme 2h de minutes GitHub Actions. Vérifiez votre
quota (Settings > Billing) si vous prévoyez des vidéos longues ou
fréquentes.
