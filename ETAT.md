# État — liveYOUTUBE-AUTO

Ce qui bloque, pourquoi, quand ça se débloque et quoi faire.

<!-- workflows:start -->
## Workflows

_Vérifié le 12/11/2026 à 07:57 (heure italienne), automatiquement à la fin de chacun de tes lancements (aucune exécution planifiée)._

- ✅ **Debug_List_YouTube_Streams** : dernier lancement réussi (22/09 à 13:33) · [voir](https://github.com/MaxMcNeil/liveYOUTUBE-AUTO/actions/runs/35722026062)
- ✅ **Générer la voix clonée (texte long)** : dernier lancement réussi (13/10 à 19:14) · [voir](https://github.com/MaxMcNeil/liveYOUTUBE-AUTO/actions/runs/38432661279)
- ❌ **Autorisation Google (une seule fois)** : dernier lancement en échec (12/11 à 07:57, failure) — dernier succès le 22/09 à 13:19 · [voir](https://github.com/MaxMcNeil/liveYOUTUBE-AUTO/actions/runs/43171733220)
  - **Cause** : clé ou jeton refusé par une API externe (invalide, expiré ou supprimé) (étape « exchange → Échanger le code contre un refresh token »)
  - **Quoi faire** : vérifie / renouvelle le secret de une API externe dans Settings → Secrets
  - Message : `"error_description": "Unauthorized"`
- ℹ️ **Live — Face Cam Cloné (diffusion YouTube réelle)** : jamais lancé (ou en cours)
- ℹ️ **Manual one-off live** : dernier lancement annulé (26/09 à 20:52) — à la main ou remplacé par un plus récent ; dernier succès le 25/09 à 20:46 · [voir](https://github.com/MaxMcNeil/liveYOUTUBE-AUTO/actions/runs/36253565855)
- ✅ **Prerecorded_Live_Now** : dernier lancement réussi (07/08 à 23:34) · [voir](https://github.com/MaxMcNeil/liveYOUTUBE-AUTO/actions/runs/31219952867)
- ❌ **Test — Live Face Cam Cloné (aperçu, pas de diffusion)** : dernier lancement en échec (23/10 à 15:14, failure), 2 échecs d'affilée — dernier succès le 13/10 à 13:27 · [voir](https://github.com/MaxMcNeil/liveYOUTUBE-AUTO/actions/runs/39959376355)
  - **Cause** : erreur dans le programme (pas un problème de quota ni de clé) (étape « render_preview → Construit content.json (fiches synchronisées sur le vrai minutage) »)
  - **Quoi faire** : à corriger dans le code : transmets la ligne d'erreur ci-dessous
  - Message : `ERREUR : certaines ancres n'ont pas pu être localisées dans le minutage :`

<!-- workflows:end -->
