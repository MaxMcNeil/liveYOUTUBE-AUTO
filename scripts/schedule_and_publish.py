#!/usr/bin/env python3
"""
Une fois tous les morceaux vocaux générés (un .wav par job du matrix,
téléchargés dans un même dossier) :

  1. Mesure la durée réelle de chaque morceau (ffprobe).
  2. Calcule à quel moment (en secondes depuis le début du live) chaque
     morceau doit démarrer, pour que l'ensemble soit réparti
     UNIFORMÉMENT sur toute la durée du live, avec la première coupure
     exactement à --start-offset (30s par défaut).
  3. Renomme chaque fichier avec un préfixe numérique = son heure de
     départ programmée (en secondes, sur 5 chiffres), ex: "01845_v007.wav".
     C'est ce préfixe que audio_playlist.sh lit pour savoir quand couper
     la musique et lancer la voix.
  4. Publie (remplace) les fichiers sur la Release GitHub taguée
     "voice_ia" — JAMAIS "voice", qui reste réservée à tes vrais
     enregistrements ponctuels et n'est jamais touchée par ce script.

Usage :
    python3 schedule_and_publish.py \
        --chunks-dir generated/ \
        --duration 20700 \
        --start-offset 30 \
        --repo MaxMcNeil/liveYOUTUBE-AUTO \
        --tag voice_ia
"""
import argparse
import glob
import json
import os
import re
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--chunks-dir", required=True, help="Dossier contenant les .wav générés (chunk_0000.wav, ...)")
    ap.add_argument("--duration", type=int, required=True, help="Durée totale du live en secondes (ex: 20700 = 5h45)")
    ap.add_argument("--start-offset", type=int, default=30, help="Instant de la première coupure (défaut 30s)")
    ap.add_argument("--repo", required=True, help="owner/repo")
    ap.add_argument("--tag", default="voice_ia",
                     help="Release dédiée à la narration clonée. Ne JAMAIS mettre 'voice' "
                          "ici — cette release est réservée aux vrais enregistrements ponctuels.")
    ap.add_argument("--dry-run", action="store_true", help="Calcule et affiche le planning sans publier")
    args = ap.parse_args()

    if args.tag == "voice":
        print(
            "ERREUR : --tag ne doit JAMAIS être 'voice' — cette release est réservée à tes "
            "vrais enregistrements ponctuels et ne doit jamais être écrasée par ce script. "
            "Utilise 'voice_ia' (valeur par défaut).",
            file=sys.stderr,
        )
        sys.exit(1)

    files = sorted(glob.glob(os.path.join(args.chunks_dir, "chunk_*.wav")))
    if not files:
        print("ERREUR : aucun fichier chunk_*.wav trouvé.", file=sys.stderr)
        sys.exit(1)

    durations = [ffprobe_duration(f) for f in files]
    n = len(files)
    total_voice = sum(durations)
    available = args.duration - args.start_offset

    # n intervalles de musique (n-1 entre les voix + 1 de "réserve" en fin
    # de live) répartis à parts égales entre les morceaux de voix.
    gap = (available - total_voice) / n

    print(f"[schedule] {n} morceaux, {total_voice:.0f}s de voix au total, "
          f"{available:.0f}s disponibles après le début (t={args.start_offset}s).")
    print(f"[schedule] Intervalle musique calculé entre chaque voix : {gap:.0f}s")

    if gap < 0:
        print(
            "ERREUR : le texte généré est trop long pour la durée du live demandée.\n"
            f"  Voix totale : {total_voice/60:.1f} min — fenêtre disponible : {available/60:.1f} min.\n"
            "  Réduis le texte, augmente le nombre de morceaux (--chunks) n'aidera pas ici,\n"
            "  ou raccourcis --duration n'est pas possible (limite YouTube/Actions).",
            file=sys.stderr,
        )
        sys.exit(1)

    schedule = []
    offset = args.start_offset
    for i in range(n):
        schedule.append((files[i], durations[i], offset))
        offset += durations[i] + gap

    max_offset = schedule[-1][2] + schedule[-1][1]
    print(f"[schedule] Dernière voix se termine vers t={max_offset:.0f}s "
          f"(sur {args.duration}s de live) — le reste tourne en musique seule.")

    renamed_dir = os.path.join(args.chunks_dir, "scheduled")
    os.makedirs(renamed_dir, exist_ok=True)

    new_paths = []
    for idx, (src, dur, off) in enumerate(schedule):
        offset_s = int(round(off))
        dest_name = f"{offset_s:05d}_v{idx:03d}.wav"
        dest = os.path.join(renamed_dir, dest_name)
        os.replace(src, dest) if os.path.exists(src) else None
        # os.replace ne fonctionne que si src existe encore (glob l'a trouvé) ; sécurité :
        if not os.path.exists(dest):
            import shutil
            shutil.copy2(src, dest)
        new_paths.append(dest)
        hh = offset_s // 3600
        mm = (offset_s % 3600) // 60
        ss = offset_s % 60
        print(f"  [{idx:03d}] t={hh:02d}:{mm:02d}:{ss:02d} (+{offset_s}s) — durée {dur:.1f}s — {dest_name}")

    manifest_path = os.path.join(renamed_dir, "schedule_manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(
            [{"file": os.path.basename(p), "offset_s": int(round(off)), "duration_s": dur}
             for p, (_, dur, off) in zip(new_paths, schedule)],
            f, ensure_ascii=False, indent=2,
        )

    if args.dry_run:
        print("[schedule] --dry-run actif : rien publié sur GitHub.")
        return

    # Vide la release "voice" existante (mêmes assets que l'ancien système
    # à un coup — on les remplace entièrement par le nouveau planning).
    existing = subprocess.run(
        ["gh", "release", "view", args.tag, "--repo", args.repo, "--json", "assets"],
        capture_output=True, text=True,
    )
    if existing.returncode == 0:
        assets = json.loads(existing.stdout).get("assets", [])
        for asset in assets:
            name = asset["name"]
            print(f"[schedule] Suppression de l'ancien asset '{name}' sur la release '{args.tag}'...")
            subprocess.run(
                ["gh", "release", "delete-asset", args.tag, name, "--repo", args.repo, "--yes"],
                check=False,
            )
    else:
        print(f"[schedule] Release '{args.tag}' introuvable, création...")
        subprocess.run(
            ["gh", "release", "create", args.tag, "--repo", args.repo,
             "--title", args.tag, "--notes", "Voix clonée programmée automatiquement."],
            check=True,
        )

    print(f"[schedule] Upload de {len(new_paths)} fichier(s) vers la release '{args.tag}'...")
    subprocess.run(
        ["gh", "release", "upload", args.tag, *new_paths, manifest_path, "--repo", args.repo, "--clobber"],
        check=True,
    )
    print("[schedule] Terminé.")


if __name__ == "__main__":
    main()
