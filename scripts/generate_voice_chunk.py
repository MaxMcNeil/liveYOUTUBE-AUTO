#!/usr/bin/env python3
"""
Génère l'audio (voix clonée) d'UN SEUL morceau de texte, avec Chatterbox
Multilingual (CPU). Appelé une fois par job du matrix GitHub Actions,
chacun sur un index différent, pour paralléliser la génération.

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

SEED = 42  # fixe pour garder un timbre cohérent d'un morceau à l'autre


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
    print(f"[generate_voice_chunk] Morceau {args.index}: {len(text)} caractères")

    # Imports lourds après le parsing des arguments, pour échouer vite
    # si les arguments sont invalides plutôt qu'après le chargement du modèle.
    import torch
    import torchaudio as ta
    from chatterbox.mtl_tts import ChatterboxMultilingualTTS

    random.seed(SEED)
    torch.manual_seed(SEED)

    device = "cpu"
    print("[generate_voice_chunk] Chargement du modèle Chatterbox Multilingual (CPU)...")
    model = ChatterboxMultilingualTTS.from_pretrained(device=device)

    print("[generate_voice_chunk] Génération...")
    wav = model.generate(
        text,
        audio_prompt_path=args.ref_audio,
        language_id=args.language,
        exaggeration=0.5,
        cfg_weight=0.5,
    )

    ta.save(args.out, wav, model.sr)
    print(f"[generate_voice_chunk] Écrit : {args.out}")


if __name__ == "__main__":
    main()
