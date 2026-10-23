# Dossier Prerecorded_lives/

Ce dossier contient uniquement `input_METADATA.txt` (le titre/
description à utiliser). **Les vidéos elles-mêmes ne se déposent PAS
ici via git** — GitHub limite les fichiers à 100 Mo par git push (25 Mo
via l'upload web), bien trop petit pour des vidéos.

## Comment uploader vos vidéos

Utilisez les **GitHub Releases** (jusqu'à 2 Go par fichier, gratuit,
ne consomme aucun quota) :

1. Sur votre repo GitHub → cliquez sur **Releases** (colonne de droite,
   ou `https://github.com/VOTRE_USER/VOTRE_REPO/releases`)
2. **Draft a new release** (ou **Create a new release**)
3. **Choose a tag** → tapez exactement `prerecorded-lives` → **Create
   new tag**
4. **Release title** : ce que vous voulez (ex. "Vidéos du jour")
5. Faites glisser vos vidéos dans la zone **"Attach binaries by
   dropping them here"** en bas — c'est cette zone-là qui accepte les
   gros fichiers, pas l'explorateur de fichiers habituel du repo
6. **Publish release**

**Pour remplacer les vidéos la fois suivante** : retournez sur cette
même release (`prerecorded-lives`) → **Edit release** → supprimez les
anciens fichiers (icône poubelle) → glissez les nouveaux → **Update
release**. Le workflow prend toujours le contenu actuel de cette
release au moment où vous le lancez.

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

Remplissez `input_METADATA.txt` (dans ce dossier, directement modifiable
sur GitHub — icône crayon) avant de lancer le workflow :

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

## Attention — minutes GitHub Actions

Le direct pousse les vidéos en temps réel (pas plus vite), donc une
vidéo de 2h consomme 2h de minutes GitHub Actions. Sur un dépôt public
(votre cas), c'est illimité et gratuit — aucune limite à surveiller.
