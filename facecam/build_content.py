#!/usr/bin/env python3
"""
Assemble content.json à partir de :
  - un fichier de SCÈNES écrites à la main (scenes_source.json), où
    chaque scène porte une "anchor" : les premiers mots exacts de
    l'énoncé de la narration à partir duquel cette fiche doit
    s'afficher — PAS un horodatage.
  - narration_timing.json, le minutage RÉEL produit par Chatterbox
    (voir generate_voice_chunk.py + schedule_and_publish.py).

Le script cherche chaque "anchor" dans l'ordre des énoncés du
minutage réel et en déduit l'horodatage exact (t) — jamais deviné,
jamais désynchronisé même si un texte est repris/régénéré et que les
durées changent d'une run à l'autre. C'est la seule partie mécanique ;
le choix du type de fiche, du titre, du panneau latéral reste un
travail éditorial fait à la main (ou par Claude) dans scenes_source.json.

Usage :
    python3 build_content.py \
        --scenes scenes_source.json \
        --timing narration_timing.json \
        --out content.json
"""
import argparse
import json
import re
import sys
import unicodedata


def norm(s: str) -> str:
    s = unicodedata.normalize("NFKD", s.lower())
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]+", " ", s).strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scenes", required=True)
    ap.add_argument("--timing", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    with open(args.scenes, "r", encoding="utf-8") as f:
        src = json.load(f)
    with open(args.timing, "r", encoding="utf-8") as f:
        timing = json.load(f)

    utterances = timing["utterances"]
    norm_utt = [norm(u["text"]) for u in utterances]

    scenes_out = []
    search_from = 0
    errors = []

    for i, scene in enumerate(src["scenes"]):
        anchor = norm(scene["anchor"])
        found = None
        for j in range(search_from, len(norm_utt)):
            if norm_utt[j].startswith(anchor) or anchor in norm_utt[j]:
                found = j
                break
        if found is None:
            errors.append(f"scène {i} ({scene.get('stage', {}).get('title', '?')!r}) : "
                           f"ancre introuvable dans le minutage -> {scene['anchor']!r}")
            continue
        t = utterances[found]["start"]
        search_from = found  # ne cherche plus jamais en arrière : une ancre répétée
                              # plus tôt dans le texte n'est jamais reprise par erreur

        out_scene = {k: v for k, v in scene.items() if k != "anchor"}
        out_scene["t"] = round(t, 2)
        scenes_out.append(out_scene)

    if errors:
        print("ERREUR : certaines ancres n'ont pas pu être localisées dans le minutage :",
              file=sys.stderr)
        for e in errors:
            print("  - " + e, file=sys.stderr)
        print(
            "\nCauses fréquentes : l'ancre ne correspond pas mot pour mot au DÉBUT d'un "
            "énoncé (vérifie les coupes de phrases dans split_text.py), ou scenes_source.json "
            "référence un texte qui n'est plus dans voice_script.txt après une réécriture.",
            file=sys.stderr,
        )
        sys.exit(1)

    # Avertit (sans bloquer) si l'ordre des scènes dans scenes_source.json
    # ne correspond pas à l'ordre réel de la narration — signe probable
    # d'une ancre dupliquée ailleurs dans le texte, ou d'un copier-coller
    # mal placé lors de la rédaction des scènes.
    for i in range(1, len(scenes_out)):
        if scenes_out[i]["t"] < scenes_out[i - 1]["t"]:
            print(f"[build_content] Attention : la scène {i} démarre avant la précédente "
                  f"({scenes_out[i]['t']}s < {scenes_out[i-1]['t']}s) — vérifie l'ordre.",
                  file=sys.stderr)

    content = {k: v for k, v in src.items() if k != "scenes"}
    content["scenes"] = scenes_out

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(content, f, ensure_ascii=False, indent=2)

    print(f"[build_content] {len(scenes_out)} scène(s) synchronisée(s) -> {args.out}")
    for s in scenes_out:
        mm, ss = divmod(int(s["t"]), 60)
        print(f"  {mm:02d}:{ss:02d}  {s.get('stage', {}).get('type', '?'):<10} "
              f"{s.get('category', ''):<10} {s.get('lower', '')[:60]}")


if __name__ == "__main__":
    main()
