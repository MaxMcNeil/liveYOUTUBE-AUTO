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
  enregistrement à la main.

`audio_playlist.sh` regarde `voice_ia` en premier : si elle contient
des fichiers, c'est elle qui pilote le début du live (mode séquentiel,
voir plus bas) et `voice` est ignorée pour cette diffusion-là. Si
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
- `chunks` : nombre de morceaux minimum, répartis en jobs parallèles
  pour paralléliser la génération. **~15 à 20** fonctionne bien pour un
  texte de plusieurs minutes — le nombre exact n'a plus d'impact sur le
  rythme du live (voir "Comment ça s'intègre au live" plus bas), juste
  sur le temps de génération.
- `language` : `fr`

Le workflow :
1. Découpe le texte en `chunks` morceaux minimum, jamais au milieu
   d'une phrase (et jamais au-delà de ~220 caractères par énoncé — les
   phrases plus longues sont sous-découpées à la virgule).
2. Génère chaque morceau **en parallèle** (un job par morceau, phrase
   par phrase à l'intérieur de chaque morceau) avec Chatterbox
   Multilingual V3, sur CPU, voix clonée depuis `ma_voix_a_cloner`.
3. Remet tous les morceaux dans l'ordre du texte source et les publie
   sur la Release `voice_ia` — en remplaçant tout ce qui s'y trouvait
   avant (jamais `voice`, qui reste intouchée).

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

```
t=0     → live démarre, silence total (ni musique ni bips)
t=5s    → la narration démarre : tous les morceaux de voice_ia
          s'enchaînent du premier au dernier, sans musique entre eux
t=fin   → une fois la narration terminée, reprise normale du live
          (bips/musique en boucle, comme n'importe quel autre live)
```

`audio_playlist.sh` détecte automatiquement ce "mode séquentiel" dès
que la release `voice_ia` contient des fichiers. Si elle est vide,
l'ancien comportement reprend automatiquement avec `voice`, sans rien
à changer.

Le délai de 5s avant le début de la narration est réglable via la
variable d'environnement `SILENCE_BEFORE_VOICE_IA_S` dans
`audio_playlist.sh` (5 par défaut).

## Régénérer avec un nouveau texte

Relance simplement le workflow avec un nouveau `text_file` (ou le même
fichier modifié) : il écrase entièrement l'ancienne release `voice_ia`
(jamais `voice`).
