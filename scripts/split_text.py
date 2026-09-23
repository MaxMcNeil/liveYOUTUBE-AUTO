#!/usr/bin/env python3
"""
Découpe un texte long en N morceaux, jamais au milieu d'une phrase.

Algorithme volontairement simple et déterministe : le même texte + le
même N produisent toujours exactement les mêmes morceaux, peu importe
la machine qui l'exécute. C'est essentiel car chaque job du matrix
GitHub Actions relance ce script indépendamment (pour ne pas avoir à
faire transiter le découpage via un artifact avant même de savoir
combien de jobs lancer) et doit tomber sur le même résultat que les
autres.

Usage :
    python3 split_text.py texte.txt --chunks 20 --out chunks.json
"""
import argparse
import json
import re
import sys

# Découpage en phrases : on coupe après ".", "!", "?" ou "…" suivi d'un
# espace/saut de ligne. Reste volontairement simple (pas de gestion fine
# des abréviations type "M." ou "etc.") — un léger sur-découpage à ces
# endroits n'est pas grave, la contrainte dure est juste de ne jamais
# couper EN PLEIN MILIEU d'une phrase.
SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?…])\s+")


def split_sentences(text: str):
    text = text.strip()
    if not text:
        return []
    # Normalise les espaces multiples/retours à la ligne à l'intérieur
    # d'un paragraphe pour ne pas fausser le comptage de caractères,
    # mais garde les paragraphes comme des frontières de phrase fortes.
    paragraphs = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
    sentences = []
    for para in paragraphs:
        para = re.sub(r"\s+", " ", para)
        parts = SENTENCE_SPLIT_RE.split(para)
        sentences.extend(s.strip() for s in parts if s.strip())
    return sentences


def pack_into_chunks(sentences, n_chunks: int):
    total_chars = sum(len(s) for s in sentences)
    if total_chars == 0:
        return []
    target = total_chars / n_chunks

    chunks = []
    current = []
    current_len = 0
    for sentence in sentences:
        # Si ajouter cette phrase dépasse largement la cible ET qu'on a
        # déjà de quoi faire un chunk, on clôt le chunk courant avant de
        # continuer — jamais au milieu d'une phrase, toujours à une
        # frontière de phrase déjà identifiée.
        if current and (current_len + len(sentence)) > target * 1.15 and len(chunks) < n_chunks - 1:
            chunks.append(" ".join(current))
            current = []
            current_len = 0
        current.append(sentence)
        current_len += len(sentence) + 1

    if current:
        chunks.append(" ".join(current))

    return chunks


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("text_file", help="Fichier texte source (UTF-8)")
    ap.add_argument("--chunks", type=int, required=True, help="Nombre de morceaux visé")
    ap.add_argument("--out", required=True, help="Fichier JSON de sortie")
    args = ap.parse_args()

    with open(args.text_file, "r", encoding="utf-8") as f:
        text = f.read()

    sentences = split_sentences(text)
    if not sentences:
        print("ERREUR : le texte est vide après nettoyage.", file=sys.stderr)
        sys.exit(1)

    n_chunks = min(args.chunks, len(sentences))
    if n_chunks < args.chunks:
        print(
            f"[split_text] Attention : seulement {len(sentences)} phrases détectées, "
            f"impossible de faire {args.chunks} morceaux distincts. "
            f"Réduit automatiquement à {n_chunks}.",
            file=sys.stderr,
        )

    chunks = pack_into_chunks(sentences, n_chunks)

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(chunks, f, ensure_ascii=False, indent=2)

    print(f"[split_text] {len(chunks)} morceau(x) écrits dans {args.out}")
    for i, c in enumerate(chunks):
        print(f"  [{i:03d}] {len(c)} caractères — \"{c[:60]}...\"")


if __name__ == "__main__":
    main()
