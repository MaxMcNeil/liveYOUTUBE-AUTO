#!/usr/bin/env python3
"""
Génère l'audio (voix clonée) d'UN SEUL morceau de texte, avec Chatterbox
Multilingual (CPU). Appelé une fois par job du matrix GitHub Actions,
chacun sur un index différent, pour paralléliser la génération.

Chatterbox a un bug connu : son détecteur de répétition interne
("alignment_stream_analyzer") force parfois un arrêt quasi immédiat de
la génération ("forcing EOS") dès les tout premiers pas d'échantillonnage,
produisant un fichier audio ridiculement court (0.1s) au lieu du texte
demandé. C'est sporadique et dépend de la seed — donc ce script mesure
la durée obtenue et RÉESSAIE avec une seed différente si le résultat est
manifestement trop court pour le texte donné, jusqu'à MAX_ATTEMPTS fois.

Usage :
    python3 generate_voice_chunk.py \
        --chunks-file chunks.json \
        --index 3 \
        --ref-audio voix_reference.wav \
        --language fr \
        --out chunk_0003.wav
"""
import argparse
import json
import random
import sys

BASE_SEED = 42  # seed "normale", gardée pour la grande majorité des morceaux
                # (cohérence de timbre d'un morceau à l'autre) ; seuls les
                # morceaux qui échouent au 1er essai changent de seed.
MAX_ATTEMPTS = 5
MIN_SECONDS_PER_CHAR = 0.02  # ~50 caractères/seconde : aucune voix humaine
                              # ne parle aussi vite, donc en-dessous de ça
                              # pour la durée obtenue, c'est forcément tronqué.
MIN_ABSOLUTE_SECONDS = 1.5


def expected_min_duration(text: str) -> float:
    return max(MIN_ABSOLUTE_SECONDS, len(text) * MIN_SECONDS_PER_CHAR)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--chunks-file", required=True)
    ap.add_argument("--index", type=int, required=True)
    ap.add_argument("--ref-audio", required=True, help="Échantillon de voix, déjà rogné à <=10s")
    ap.add_argument("--language", default="fr")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    with open(args.chunks_file, "r", encoding="utf-8") as f:
        chunks = json.load(f)

    if args.index >= len(chunks):
        print(f"[generate_voice_chunk] index {args.index} hors limites ({len(chunks)} morceaux), rien à faire.")
        sys.exit(0)

    text = chunks[args.index]
    min_ok = expected_min_duration(text)
    print(f"[generate_voice_chunk] Morceau {args.index}: {len(text)} caractères "
          f"(durée minimale plausible attendue : {min_ok:.1f}s)")

    # Imports lourds après le parsing des arguments, pour échouer vite
    # si les arguments sont invalides plutôt qu'après le chargement du modèle.
    import torch
    import torchaudio as ta
    from chatterbox.mtl_tts import ChatterboxMultilingualTTS

    device = "cpu"
    print("[generate_voice_chunk] Chargement du modèle Chatterbox Multilingual (CPU)...")
    model = ChatterboxMultilingualTTS.from_pretrained(device=device)

    wav = None
    duration = 0.0
    for attempt in range(1, MAX_ATTEMPTS + 1):
        seed = BASE_SEED if attempt == 1 else BASE_SEED + attempt * 997
        random.seed(seed)
        torch.manual_seed(seed)

        print(f"[generate_voice_chunk] Génération (essai {attempt}/{MAX_ATTEMPTS}, seed={seed})...")
        candidate = model.generate(
            text,
            audio_prompt_path=args.ref_audio,
            language_id=args.language,
            exaggeration=0.5,
            cfg_weight=0.5,
        )
        duration = candidate.shape[-1] / model.sr
        print(f"[generate_voice_chunk]   -> durée obtenue : {duration:.2f}s")

        if duration >= min_ok:
            wav = candidate
            break

        print(f"[generate_voice_chunk]   Résultat suspect (trop court, probable coupure prématurée "
              f"de Chatterbox / 'forcing EOS') — nouvel essai avec une autre seed.")

    if wav is None:
        print(
            f"ERREUR : après {MAX_ATTEMPTS} essais, le morceau {args.index} reste anormalement "
            f"court ({duration:.2f}s attendu >= {min_ok:.1f}s). Abandon plutôt que de publier un "
            f"fichier tronqué qui casserait le planning du live.",
            file=sys.stderr,
        )
        sys.exit(1)

    ta.save(args.out, wav, model.sr)
    print(f"[generate_voice_chunk] Écrit : {args.out} ({duration:.2f}s)")


if __name__ == "__main__":
    main()
