# État — liveYOUTUBE-AUTO

Ce qui bloque, pourquoi, quand ça se débloque et quoi faire.

<!-- workflows:start -->
## Workflows

_Vérifié le 25/10/2026 à 10:08 (heure italienne), automatiquement à la fin de chaque workflow et chaque jour._

- ✅ **Debug_List_YouTube_Streams** : dernier lancement réussi (22/09 à 13:33) · [voir](https://github.com/MaxMcNeil/liveYOUTUBE-AUTO/actions/runs/35722026062)
- ✅ **Générer la voix clonée (texte long)** : dernier lancement réussi (13/10 à 19:14) · [voir](https://github.com/MaxMcNeil/liveYOUTUBE-AUTO/actions/runs/38432661279)
- ✅ **Autorisation Google (une seule fois)** : dernier lancement réussi (22/09 à 13:19) · [voir](https://github.com/MaxMcNeil/liveYOUTUBE-AUTO/actions/runs/35720746272)
- ℹ️ **Live — Face Cam Cloné (diffusion YouTube réelle)** : jamais lancé (ou en cours)
- ❌ **Manual one-off live** : dernier lancement en échec (26/09 à 20:52, cancelled), 2 échecs d'affilée — dernier succès le 25/09 à 20:46 · [voir](https://github.com/MaxMcNeil/liveYOUTUBE-AUTO/actions/runs/36253565855)
  - **Cause** : le travail a dépassé le temps maximum (étape « stream → Diffuser (jusqu'à 5h50, ou arrêt manuel via Cancel workflow) »)
  - **Quoi faire** : relance ; si ça se répète, la vidéo/le traitement est trop long
  - Message : `##[error]The operation was canceled.`
- ✅ **Prerecorded_Live_Now** : dernier lancement réussi (07/08 à 23:34) · [voir](https://github.com/MaxMcNeil/liveYOUTUBE-AUTO/actions/runs/31219952867)
- ❌ **Test — Live Face Cam Cloné (aperçu, pas de diffusion)** : dernier lancement en échec (23/10 à 15:14, failure), 2 échecs d'affilée — dernier succès le 13/10 à 13:27 · [voir](https://github.com/MaxMcNeil/liveYOUTUBE-AUTO/actions/runs/39959376355)
  - **Cause** : erreur dans le programme (pas un problème de quota ni de clé) (étape « render_preview → Construit content.json (fiches synchronisées sur le vrai minutage) »)
  - **Quoi faire** : à corriger dans le code : transmets la ligne d'erreur ci-dessous
  - Message : `[36;1mffmpeg -y -f concat -safe 0 -i /tmp/concat_list.txt -c copy "$GITHUB_WORKSPACE/facecam/template/narration.wav" -loglevel error[0m`

<!-- workflows:end -->
