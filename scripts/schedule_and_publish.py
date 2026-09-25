#!/usr/bin/env python3
"""
Une fois tous les morceaux vocaux générés (un .wav par job du matrix,
téléchargés dans un même dossier) :

  1. Trie les fichiers par index de chunk (l'ordre du texte source).
  2. Les renomme en une séquence simple (v000.wav, v001.wav, ...) pour
     garantir que le tri alphabétique = l'ordre de lecture. C'est cet
     ordre que audio_playlist.sh utilise pour enchaîner les morceaux
     du premier au dernier, en mode séquentiel (silence initial, puis
     narration complète sans musique, voir audio_playlist.sh).
  3. Publie (remplace) les fichiers sur la Release GitHub taguée
     "voice_ia" — JAMAIS "voice", qui reste réservée à tes vrais
     enregistrements ponctuels et n'est jamais touchée par ce script.

Usage :
    python3 schedule_and_publish.py \
        --chunks-dir generated/ \
        --repo MaxMcNeil/liveYOUTUBE-AUTO \
        --tag voice_ia
"""
import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys


def ffprobe_duration(path: str) -> float:
    out = subprocess.run(
        [
            "ffprobe", "-v", "error", "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1", path,
        ],
        capture_output=True, text=True, check=True,
    )
    return float(out.stdout.strip())


def chunk_index(path: str) -> int:
    m = re.search(r"chunk_(\d+)\.wav$", os.path.basename(path))
    return int(m.group(1)) if m else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--chunks-dir", required=True, help="Dossier contenant les .wav générés (chunk_0000.wav, ...)")
    ap.add_argument("--repo", required=True, help="owner/repo")
    ap.add_argument("--tag", default="voice_ia",
                     help="Release dédiée à la narration clonée. Ne JAMAIS mettre 'voice' "
                          "ici — cette release est réservée aux vrais enregistrements ponctuels.")
    ap.add_argument("--dry-run", action="store_true", help="Prépare les fichiers sans publier")
    args = ap.parse_args()

    if args.tag == "voice":
        print(
            "ERREUR : --tag ne doit JAMAIS être 'voice' — cette release est réservée à tes "
            "vrais enregistrements ponctuels et ne doit jamais être écrasée par ce script. "
            "Utilise 'voice_ia' (valeur par défaut).",
            file=sys.stderr,
        )
        sys.exit(1)

    files = sorted(glob.glob(os.path.join(args.chunks_dir, "chunk_*.wav")), key=chunk_index)
    if not files:
        print("ERREUR : aucun fichier chunk_*.wav trouvé.", file=sys.stderr)
        sys.exit(1)

    durations = [ffprobe_duration(f) for f in files]
    total = sum(durations)
    print(f"[publish] {len(files)} morceau(x), {total:.0f}s de narration au total "
          f"(lus à la suite, sans musique, après un court silence en début de live).")

    renamed_dir = os.path.join(args.chunks_dir, "sequential")
    os.makedirs(renamed_dir, exist_ok=True)

    new_paths = []
    for idx, (src, dur) in enumerate(zip(files, durations)):
        dest_name = f"v{idx:03d}.wav"
        dest = os.path.join(renamed_dir, dest_name)
        shutil.copy2(src, dest)
        new_paths.append(dest)
        print(f"  [{idx:03d}] {dur:.1f}s — {dest_name}  (source: {os.path.basename(src)})")

    manifest_path = os.path.join(renamed_dir, "manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(
            [{"file": os.path.basename(p), "duration_s": dur} for p, dur in zip(new_paths, durations)],
            f, ensure_ascii=False, indent=2,
        )

    if args.dry_run:
        print("[publish] --dry-run actif : rien publié sur GitHub.")
        return

    # Vide la release "voice_ia" existante — on remplace entièrement son
    # contenu par la nouvelle narration.
    existing = subprocess.run(
        ["gh", "release", "view", args.tag, "--repo", args.repo, "--json", "assets"],
        capture_output=True, text=True,
    )
    if existing.returncode == 0:
        assets = json.loads(existing.stdout).get("assets", [])
        for asset in assets:
            name = asset["name"]
            print(f"[publish] Suppression de l'ancien asset '{name}' sur la release '{args.tag}'...")
            subprocess.run(
                ["gh", "release", "delete-asset", args.tag, name, "--repo", args.repo, "--yes"],
                check=False,
            )
    else:
        print(f"[publish] Release '{args.tag}' introuvable, création...")
        subprocess.run(
            ["gh", "release", "create", args.tag, "--repo", args.repo,
             "--title", args.tag, "--notes", "Narration en voix clonée, générée automatiquement."],
            check=True,
        )

    print(f"[publish] Upload de {len(new_paths)} fichier(s) vers la release '{args.tag}'...")
    subprocess.run(
        ["gh", "release", "upload", args.tag, *new_paths, manifest_path, "--repo", args.repo, "--clobber"],
        check=True,
    )
    print("[publish] Terminé.")


if __name__ == "__main__":
    main()
