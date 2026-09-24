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

TOKENS_PER_SECOND = 25          # constante Chatterbox (documentée)
MODEL_MAX_TOKENS = 4096         # limite absolue du modèle (~163s)

# Vitesse de parole plancher, volontairement TRÈS prudente (personne ne
# parle aussi lentement en pratique) : sert uniquement à calculer un
# budget de tokens large pour ne JAMAIS être la cause d'une coupure.
FLOOR_CHARS_PER_SECOND = 10
TOKEN_BUDGET_HEADROOM = 1.3     # +30% de marge par rapport au plancher

# Vitesse de parole plafond, tout aussi prudente dans l'autre sens : sert
# à détecter une coupure prématurée (si le résultat est plus court que
# ce qu'un débit humain plausible le plus rapide pourrait justifier).
CEILING_CHARS_PER_SECOND = 45
MIN_ABSOLUTE_SECONDS = 1.5

# Si la durée obtenue arrive à >= 95% du budget de tokens alloué pour ce
# morceau, c'est très probablement une coupure par plafond (pas la fin
# naturelle du texte) : on retente avec un budget de tokens plus large,
# pas juste une autre seed.
NEAR_CAP_RATIO = 0.95


def token_budget_for(text: str) -> int:
    seconds_needed = len(text) / FLOOR_CHARS_PER_SECOND
    tokens = int(seconds_needed * TOKENS_PER_SECOND * TOKEN_BUDGET_HEADROOM)
    return max(200, min(MODEL_MAX_TOKENS, tokens))


def expected_min_duration(text: str) -> float:
    return max(MIN_ABSOLUTE_SECONDS, len(text) / CEILING_CHARS_PER_SECOND)


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
    tokens_budget = token_budget_for(text)
    print(f"[generate_voice_chunk] Morceau {args.index}: {len(text)} caractères — "
          f"budget initial {tokens_budget} tokens (~{tokens_budget / TOKENS_PER_SECOND:.1f}s), "
          f"durée minimale plausible : {min_ok:.1f}s")

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

        cap_seconds = tokens_budget / TOKENS_PER_SECOND
        print(f"[generate_voice_chunk] Génération (essai {attempt}/{MAX_ATTEMPTS}, seed={seed}, "
              f"max_new_tokens={tokens_budget} soit ~{cap_seconds:.1f}s max)...")
        candidate = model.generate(
            text,
            audio_prompt_path=args.ref_audio,
            language_id=args.language,
            exaggeration=0.5,
            cfg_weight=0.5,
            max_new_tokens=tokens_budget,
        )
        duration = candidate.shape[-1] / model.sr
        near_cap = duration >= NEAR_CAP_RATIO * cap_seconds
        print(f"[generate_voice_chunk]   -> durée obtenue : {duration:.2f}s"
              f"{'  ⚠️ proche du plafond de tokens (probable coupure)' if near_cap else ''}")

        if duration >= min_ok and not near_cap:
            wav = candidate
            break

        if near_cap:
            # Le texte a probablement besoin de plus de place : on
            # augmente le budget de tokens plutôt que de juste changer
            # de seed (changer de seed ne résout rien si le texte est
            # simplement trop long pour le budget alloué).
            tokens_budget = min(MODEL_MAX_TOKENS, int(tokens_budget * 1.5))
            print(f"[generate_voice_chunk]   Nouveau budget pour le prochain essai : "
                  f"{tokens_budget} tokens (~{tokens_budget / TOKENS_PER_SECOND:.1f}s)")
        else:
            print(f"[generate_voice_chunk]   Résultat suspect (trop court par rapport au texte, "
                  f"probable coupure prématurée de Chatterbox / 'forcing EOS') — nouvel essai "
                  f"avec une autre seed.")

    if wav is None:
        print(
            f"ERREUR : après {MAX_ATTEMPTS} essais, le morceau {args.index} reste anormalement "
            f"court ou tronqué par le plafond de tokens ({duration:.2f}s, budget final "
            f"{tokens_budget} tokens). Abandon plutôt que de publier un fichier tronqué qui "
            f"casserait le planning du live. Solution : réduis la taille de ce morceau (augmente "
            f"--chunks) ou relance juste ce job.",
            file=sys.stderr,
        )
        sys.exit(1)

    ta.save(args.out, wav, model.sr)
    print(f"[generate_voice_chunk] Écrit : {args.out} ({duration:.2f}s)")


if __name__ == "__main__":
    main()
