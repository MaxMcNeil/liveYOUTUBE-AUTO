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

# Vitesse de parole plafond, volontairement prudente : sert à détecter
# une coupure prématurée (résultat plus court que ce qu'un débit humain
# plausible le plus rapide pourrait justifier).
CEILING_CHARS_PER_SECOND = 45
MIN_ABSOLUTE_SECONDS = 0.3      # les sous-clauses peuvent être très courtes

# Vitesse de parole plancher, tout aussi prudente dans l'autre sens :
# sert à détecter une HALLUCINATION (le modèle ajoute des mots/phrases
# absents du texte source, phénomène connu des TTS autorégressifs).
# Si la durée obtenue est plus longue que ce qu'un débit humain
# plausible le plus lent pourrait justifier pour CE texte précis, le
# résultat contient très probablement du contenu en trop.
SLOWEST_CHARS_PER_SECOND = 7
MAX_DURATION_BUFFER_SECONDS = 1.5  # marge fixe pour les très courts énoncés


def expected_min_duration(text: str) -> float:
    return max(MIN_ABSOLUTE_SECONDS, len(text) / CEILING_CHARS_PER_SECOND)


def expected_max_duration(text: str) -> float:
    return len(text) / SLOWEST_CHARS_PER_SECOND + MAX_DURATION_BUFFER_SECONDS


def generate_one_utterance(model, text, ref_audio, language, exaggeration, cfg_weight,
                            utterance_label):
    """Génère UN énoncé, avec retry (nouvelle seed) si le résultat semble
    tronqué par le bug de coupure prématurée de Chatterbox. Renvoie le
    waveform torch (1, n_samples)."""
    import torch

    min_ok = expected_min_duration(text)
    max_ok = expected_max_duration(text)

    wav = None
    duration = 0.0
    for attempt in range(1, MAX_ATTEMPTS + 1):
        seed = BASE_SEED if attempt == 1 else BASE_SEED + attempt * 997
        random.seed(seed)
        torch.manual_seed(seed)

        print(f"[generate_voice_chunk]   {utterance_label} essai {attempt}/{MAX_ATTEMPTS} "
              f"(seed={seed}, exaggeration={exaggeration}, cfg_weight={cfg_weight})...")
        candidate = model.generate(
            text,
            audio_prompt_path=ref_audio,
            language_id=language,
            exaggeration=exaggeration,
            cfg_weight=cfg_weight,
        )
        duration = candidate.shape[-1] / model.sr
        print(f"[generate_voice_chunk]     -> {duration:.2f}s (attendu entre {min_ok:.1f}s et {max_ok:.1f}s)")

        if min_ok <= duration <= max_ok:
            wav = candidate
            break
        if duration < min_ok:
            print(f"[generate_voice_chunk]     Résultat suspect (trop court pour le texte, "
                  f"probable coupure prématurée / 'forcing EOS') — nouvel essai avec une autre seed.")
        else:
            print(f"[generate_voice_chunk]     Résultat suspect (trop long pour le texte, "
                  f"probable HALLUCINATION — mots/phrases ajoutés absents du script) — nouvel "
                  f"essai avec une autre seed.")

    if wav is None:
        print(
            f"ERREUR : {utterance_label} reste anormal après {MAX_ATTEMPTS} essais "
            f"({duration:.2f}s, attendu entre {min_ok:.1f}s et {max_ok:.1f}s). "
            f"Texte : \"{text[:80]}...\"",
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
