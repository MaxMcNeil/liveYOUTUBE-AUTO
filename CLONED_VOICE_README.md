# Voix clonée sur le live (ajout)

Ce document décrit UNIQUEMENT la nouvelle fonctionnalité. Rien d'autre
dans le repo n'est modifié — `orchestrator.js`, `stream_session.sh`
(rotation des sites, popups, animation) restent exactement tels quels.

## Fichiers ajoutés/modifiés

- **Ajoutés** : `.github/workflows/generate-cloned-voice.yml`,
  `scripts/split_text.py`, `scripts/generate_voice_chunk.py`,
  `scripts/schedule_and_publish.py`
- **Modifié** : `audio_playlist.sh` — ajout d'un "mode planifié"
  (voir plus bas), 100% rétrocompatible avec l'ancien comportement.

## ⚠️ Aucun croisement avec tes enregistrements réels

Ta release `voice` (vrais enregistrements ponctuels que tu déposes à
la main de temps en temps) **n'est jamais touchée** par ce système.
Toute la narration clonée passe par une release **séparée et dédiée** :
`voice_ia`.

- `voice` → à toi, comme aujourd'hui. Ne JAMAIS y déposer les fichiers
  générés par ce workflow.
- `voice_ia` → réservée à ce workflow. Ne JAMAIS y déposer un vrai
  enregistrement à la main (les noms de fichiers doivent garder leur
  préfixe numérique généré automatiquement, ex: `01845_v007.wav`).

`audio_playlist.sh` regarde `voice_ia` en premier : si elle contient
des fichiers valides, c'est elle qui pilote tout le live (narration
programmée) et `voice` est ignorée pour cette diffusion-là. Si
`voice_ia` est vide, comportement strictement identique à avant, avec
`voice`.

**Pour repasser à un live "normal" avec juste tes vrais clips** : vide
la release `voice_ia` (supprime ses assets) avant de lancer le live —
sinon elle prendra le dessus.

## Contrôle du ton (optionnel)

Insère des balises `[ton:xxx]` dans ton texte pour changer le ton à
partir de cet endroit (jusqu'à la balise suivante) :

```
Alors !!!! Vous plaisantez ?

Bon, bref, passons. [ton:calme]
Le 23 septembre 2026, quelque chose saute aux yeux...

[ton:colere]
Ça vous dérange pas de dire n'importe quoi !

[ton:normal]
Et maintenant, regardons la France.
```

Tons disponibles : `normal`, `calme`, `colere`, `sarcastique`. Rien à
mettre si tu ne t'en sers pas — tout reste en `normal` par défaut.

⚠️ Chatterbox n'a pas de vrai moteur d'émotions nommées — seulement 2
curseurs (`exaggeration` = intensité, `cfg_weight` = rythme). Ces tons
sont une approximation à base de ces 2 curseurs. `colere`/`calme`
fonctionnent raisonnablement bien ; `sarcastique` reste expérimental
(l'ironie tient surtout au choix des mots, pas à un simple réglage
audio).

## Comment le texte est transformé en audio (V2)

Chaque phrase (et chaque sous-clause d'une phrase trop longue) est
générée par un appel Chatterbox **séparé**, puis recollée avec un
petit silence — plutôt qu'un seul gros pavé de texte envoyé en une
fois. C'est ce qui rend la génération robuste : un modèle
autorégressif comme Chatterbox dérive/hallucine bien plus sur un long
texte d'un coup que sur des phrases courtes prises une par une. C'est
aussi ce qui permet de faire varier le ton phrase par phrase.

## Mise en place (une fois)

1. **Rendre le repo public** (nécessaire pour les minutes Actions
   illimitées ET pour paralléliser la génération sur plusieurs jobs
   gratuits — jusqu'à 20 en simultané).
2. **Uploader ton échantillon de voix** en Release GitHub taguée
   exactement `ma_voix_a_cloner` (un seul fichier audio, propre, sans
   bruit de fond — 10 à 30s suffisent, il sera de toute façon rogné à
   10s automatiquement car Chatterbox dérive au-delà).
3. **Commiter ton texte** dans le repo (ex: `voice_script.txt`, à la
   racine — un fichier texte se versionne normalement avec git,
   contrairement aux gros fichiers vidéo/audio qui passent par les
   Releases).

## Lancer la génération

Actions → **"Générer la voix clonée (texte long)"** → **Run workflow** :

- `text_file` : chemin du fichier texte (ex: `voice_script.txt`)
- `chunks` : nombre de coupures pendant le live (donc de morceaux
  générés). **~15 à 20** fonctionne bien pour 5h45 — assez pour que ce
  soit "éparpillé", pas trop pour ne pas payer trop de temps CPU.
- `live_duration_seconds` : `20700` pour 5h45 (laisse une marge sous
  la limite GitHub Actions de 6h = 21600s)
- `language` : `fr`

Le workflow :
1. Découpe le texte en `chunks` morceaux, jamais au milieu d'une phrase.
2. Génère chaque morceau **en parallèle** (un job par morceau) avec
   Chatterbox Multilingual, sur CPU, voix clonée depuis
   `ma_voix_a_cloner`.
3. Calcule automatiquement à quel instant du live chaque morceau doit
   démarrer, pour une répartition uniforme sur toute la durée, avec la
   première coupure exactement à t=30s.
4. Publie les fichiers renommés (ex: `01845_v007.wav`) sur la Release
   `voice_ia` — en remplaçant tout ce qui s'y trouvait avant (jamais
   `voice`, qui reste intouchée).

⚠️ **Non testé en conditions réelles ici** (pas de GPU/réseau vers
Hugging Face dans mon bac à sable) : avant de lancer sur ton texte
complet d'1h+, fais un premier essai avec un texte court (2-3 phrases,
`chunks: 2`) pour valider que Chatterbox tourne bien sur les runners
GitHub et que la voix te convient, **avant** de lancer un run de
plusieurs heures.

⏱️ **Temps de génération** : Chatterbox sur CPU est lent (pas de GPU
sur les runners gratuits). Si un morceau met trop longtemps et dépasse
6h, réduis sa taille en augmentant `chunks`. Avec le parallélisme,
même un texte long devrait rester gérable.

## Comment ça s'intègre au live (chronologie)

Exactement ce que tu as décrit :

```
t=0    → live démarre, bips/musique du site comme d'habitude
t=30s  → coupure nette de la musique → 1er morceau de voix clonée
       → fin du morceau → musique/bips reprennent normalement
t=X    → coupure nette → 2e morceau de voix clonée
       → reprise musique...
...    → jusqu'à la fin du live (dernier morceau, puis musique seule
          en boucle jusqu'à l'arrêt)
```

`audio_playlist.sh` détecte automatiquement ce "mode planifié" dès que
la release `voice_ia` contient des fichiers valides. Si elle est vide,
l'ancien comportement reprend automatiquement avec `voice`, sans rien
à changer.

## Régénérer avec un nouveau texte

Relance simplement le workflow avec un nouveau `text_file` (ou le même
fichier modifié) : il écrase entièrement l'ancienne release `voice_ia`
(jamais `voice`).
