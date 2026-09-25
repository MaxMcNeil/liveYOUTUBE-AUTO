#!/usr/bin/env python3
"""
Génère l'audio (voix clonée) d'UN SEUL morceau, avec Chatterbox
Multilingual V3 (CPU). Appelé une fois par job du matrix GitHub
Actions, chacun sur un index différent, pour paralléliser la
génération.

Un morceau (chunk) est une liste d'énoncés courts (phrases ou
sous-clauses, voir split_text.py), chacun avec sa propre pause et son
propre réglage de ton (exaggeration/cfg_weight). CHAQUE ÉNONCÉ EST
GÉNÉRÉ SÉPARÉMENT puis recollé avec un silence — un modèle
autorégressif comme Chatterbox dérive/hallucine bien plus sur un gros
pavé de texte que sur des phrases courtes prises une par une. C'est
aussi ce qui permet de varier le ton phrase par phrase.

Chatterbox a un bug connu : son détecteur de répétition interne
("alignment_stream_analyzer") force parfois un arrêt quasi immédiat de
la génération ("forcing EOS") dès les tout premiers pas
d'échantillonnage, produisant un résultat ridiculement court. C'est
sporadique et dépend de la seed — donc chaque énoncé est vérifié et
RÉESSAYÉ avec une seed différente si le résultat est manifestement
trop court, jusqu'à MAX_ATTEMPTS fois.

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

BASE_SEED = 42  # seed "normale", gardée pour la grande majorité des énoncés
                # (cohérence de timbre d'un énoncé à l'autre) ; seuls ceux
                # qui échouent au 1er essai changent de seed.
MAX_ATTEMPTS = 5

TOKENS_PER_SECOND = 25          # constante Chatterbox (documentée)
MODEL_MAX_TOKENS = 4096         # limite absolue du modèle (~163s)

# Vitesse de parole plancher, volontairement TRÈS prudente (personne ne
# parle aussi lentement en pratique) : sert uniquement à calculer un
# budget de tokens large pour ne JAMAIS être la cause d'une coupure.
# Les énoncés étant désormais courts (une phrase ou une sous-clause),
# ce budget reste presque toujours petit — l'essentiel de la marge de
# sécurité vient maintenant du découpage en amont, pas de ce budget.
FLOOR_CHARS_PER_SECOND = 10
TOKEN_BUDGET_HEADROOM = 1.3     # +30% de marge par rapport au plancher

# Vitesse de parole plafond, tout aussi prudente dans l'autre sens : sert
# à détecter une coupure prématurée (résultat plus court que ce qu'un
# débit humain plausible le plus rapide pourrait justifier).
CEILING_CHARS_PER_SECOND = 45
MIN_ABSOLUTE_SECONDS = 0.3      # les sous-clauses peuvent être très courtes

# Si la durée obtenue arrive à >= 95% du budget de tokens alloué, c'est
# très probablement une coupure par plafond (pas la fin naturelle du
# texte) : on retente avec un budget de tokens plus large, pas juste
# une autre seed.
NEAR_CAP_RATIO = 0.95


def token_budget_for(text: str) -> int:
    seconds_needed = len(text) / FLOOR_CHARS_PER_SECOND
    tokens = int(seconds_needed * TOKENS_PER_SECOND * TOKEN_BUDGET_HEADROOM)
    return max(120, min(MODEL_MAX_TOKENS, tokens))


def expected_min_duration(text: str) -> float:
    return max(MIN_ABSOLUTE_SECONDS, len(text) / CEILING_CHARS_PER_SECOND)


def generate_one_utterance(model, text, ref_audio, language, exaggeration, cfg_weight,
                            utterance_label):
    """Génère UN énoncé, avec retry si le résultat semble tronqué.
    Renvoie le waveform torch (1, n_samples)."""
    import torch

    min_ok = expected_min_duration(text)
    tokens_budget = token_budget_for(text)

    wav = None
    duration = 0.0
    for attempt in range(1, MAX_ATTEMPTS + 1):
        seed = BASE_SEED if attempt == 1 else BASE_SEED + attempt * 997
        random.seed(seed)
        torch.manual_seed(seed)

        cap_seconds = tokens_budget / TOKENS_PER_SECOND
        print(f"[generate_voice_chunk]   {utterance_label} essai {attempt}/{MAX_ATTEMPTS} "
              f"(seed={seed}, max_new_tokens={tokens_budget} ~{cap_seconds:.1f}s, "
              f"exaggeration={exaggeration}, cfg_weight={cfg_weight})...")
        candidate = model.generate(
            text,
            audio_prompt_path=ref_audio,
            language_id=language,
            exaggeration=exaggeration,
            cfg_weight=cfg_weight,
            max_new_tokens=tokens_budget,
        )
        duration = candidate.shape[-1] / model.sr
        near_cap = duration >= NEAR_CAP_RATIO * cap_seconds
        print(f"[generate_voice_chunk]     -> {duration:.2f}s"
              f"{'  ⚠️ proche du plafond (probable coupure)' if near_cap else ''}")

        if duration >= min_ok and not near_cap:
            wav = candidate
            break

        if near_cap:
            tokens_budget = min(MODEL_MAX_TOKENS, int(tokens_budget * 1.5))
        # sinon : trop court sans être proche du plafond -> probable
        # coupure prématurée (bug EOS), on change juste de seed au tour
        # suivant (déjà fait en haut de boucle).

    if wav is None:
        print(
            f"ERREUR : {utterance_label} reste anormalement court ou tronqué après "
            f"{MAX_ATTEMPTS} essais ({duration:.2f}s). Texte : \"{text[:80]}...\"",
            file=sys.stderr,
        )
        sys.exit(1)

    return wav, duration


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

    utterances = chunks[args.index]  # liste de [texte, pause_ms, exaggeration, cfg_weight]
    print(f"[generate_voice_chunk] Morceau {args.index}: {len(utterances)} énoncé(s)")

    # Imports lourds après le parsing des arguments, pour échouer vite
    # si les arguments sont invalides plutôt qu'après le chargement du modèle.
    import torch
    import torchaudio as ta

    from chatterbox.mtl_tts import ChatterboxMultilingualTTS

    device = "cpu"
    print("[generate_voice_chunk] Chargement du modèle Chatterbox Multilingual V3 (CPU)...")
    model = ChatterboxMultilingualTTS.from_pretrained(device=device, t3_model="v3")

    pieces = []
    total_duration = 0.0
    for i, (text, pause_ms, exaggeration, cfg_weight) in enumerate(utterances):
        label = f"énoncé {i + 1}/{len(utterances)}"
        wav, duration = generate_one_utterance(
            model, text, args.ref_audio, args.language, exaggeration, cfg_weight, label,
        )
        pieces.append(wav)
        total_duration += duration

        is_last = (i == len(utterances) - 1)
        if pause_ms > 0 and not is_last:
            silence_samples = int(model.sr * pause_ms / 1000)
            silence = torch.zeros((wav.shape[0], silence_samples), dtype=wav.dtype)
            pieces.append(silence)
            total_duration += pause_ms / 1000

    final_wav = torch.cat(pieces, dim=-1)
    ta.save(args.out, final_wav, model.sr)
    print(f"[generate_voice_chunk] Écrit : {args.out} ({total_duration:.2f}s, "
          f"{len(utterances)} énoncé(s) recollés)")


if __name__ == "__main__":
    main()
