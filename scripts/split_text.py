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

# Plafond dur, indépendant du nombre de morceaux demandé : la limite
# absolue de Chatterbox est 4096 tokens (~163s, 25 tokens/s). En
# supposant un débit plancher très prudent de 10 caractères/seconde
# (personne ne parle aussi lentement), un morceau ne devrait jamais
# dépasser ~1260 caractères pour tenir dans cette limite avec marge.
# On se garde une marge supplémentaire en dessous.
MAX_CHARS_PER_CHUNK = 1000


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


def pack_into_chunks(sentences, n_chunks: int, hard_max_chars: int = MAX_CHARS_PER_CHUNK):
    total_chars = sum(len(s) for s in sentences)
    if total_chars == 0:
        return []
    target = total_chars / n_chunks
    # Jamais au-dessus du plafond dur, même si la tolérance de 15% le permettrait.
    soft_limit = min(target * 1.15, hard_max_chars)

    chunks = []
    current = []
    current_len = 0
    for sentence in sentences:
        # Si ajouter cette phrase dépasse la limite ET qu'on a déjà de
        # quoi faire un chunk, on clôt le chunk courant avant de
        # continuer — jamais au milieu d'une phrase, toujours à une
        # frontière de phrase déjà identifiée.
        if current and (current_len + len(sentence)) > soft_limit:
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

    # Garde-fou : si diviser le texte en n_chunks donnerait des morceaux
    # trop longs pour Chatterbox (risque de coupure au plafond de
    # tokens), on augmente automatiquement le nombre de morceaux — le
    # nombre demandé par l'utilisateur est un MINIMUM, jamais dépassé
    # à la baisse, mais peut être poussé à la hausse pour la sécurité.
    total_chars = sum(len(s) for s in sentences)
    min_chunks_for_safety = max(1, -(-total_chars // MAX_CHARS_PER_CHUNK))  # ceil division
    if min_chunks_for_safety > n_chunks:
        print(
            f"[split_text] Attention : {args.chunks} morceaux donnerait ~"
            f"{total_chars // args.chunks} caractères/morceau, trop long pour Chatterbox "
            f"(risque de coupure). Nombre de morceaux augmenté automatiquement à "
            f"{min_chunks_for_safety} pour rester sous {MAX_CHARS_PER_CHUNK} caractères/morceau.",
            file=sys.stderr,
        )
        n_chunks = min_chunks_for_safety

    chunks = pack_into_chunks(sentences, n_chunks)

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(chunks, f, ensure_ascii=False, indent=2)

    print(f"[split_text] {len(chunks)} morceau(x) écrits dans {args.out}")
    for i, c in enumerate(chunks):
        print(f"  [{i:03d}] {len(c)} caractères — \"{c[:60]}...\"")


if __name__ == "__main__":
    main()
