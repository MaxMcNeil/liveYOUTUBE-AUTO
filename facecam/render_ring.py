#!/usr/bin/env python3
"""
Rend l'animation d'anneau audio-réactif (séquence de PNG transparents) à
partir d'un fichier audio. L'anneau "respire" avec le volume de la voix :
il s'élargit et s'illumine sur les syllabes fortes, se calme sur les
silences (jamais complètement éteint : reste visible en veille).

Usage: render_ring.py audio.wav dossier_sortie [--fps 30] [--size 400] [--radius 140]
"""
import argparse, os, subprocess
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ap = argparse.ArgumentParser()
ap.add_argument("audio"); ap.add_argument("outdir")
ap.add_argument("--fps", type=int, default=30)
ap.add_argument("--size", type=int, default=400, help="côté de la toile carrée (px)")
ap.add_argument("--radius", type=int, default=140, help="rayon du cercle vidéo (px)")
ap.add_argument("--color", default="90,200,255", help="couleur R,G,B des anneaux")
ap.add_argument("--max", type=float, default=None, help="durée max à rendre (s)")
a = ap.parse_args()

# Décodage robuste (tout format) -> mono 16 kHz int16
cmd = ["ffmpeg", "-v", "error", "-i", a.audio, "-ac", "1", "-ar", "16000", "-f", "s16le", "-"]
audio = np.frombuffer(subprocess.run(cmd, capture_output=True, check=True).stdout,
                      dtype=np.int16).astype(np.float32) / 32768.0
sr = 16000
if a.max:
    audio = audio[: int(a.max * sr)]

n_frames = int(len(audio) / sr * a.fps)
spf = len(audio) / max(n_frames, 1)
rms = np.array([np.sqrt(np.mean(audio[int(i*spf):int((i+1)*spf)] ** 2) + 1e-12) for i in range(n_frames)])

# Normalisation sur le 95e percentile (un pic isolé n'écrase pas l'échelle)
env = np.clip(rms / (np.percentile(rms, 95) + 1e-6), 0, 1)

# Lissage attack rapide / release plus lent => mouvement organique
smooth, prev = np.zeros_like(env), 0.0
for i, v in enumerate(env):
    prev += (0.6 if v > prev else 0.15) * (v - prev)
    smooth[i] = prev

os.makedirs(a.outdir, exist_ok=True)
S = a.size; C = (S // 2, S // 2); R = a.radius
rgb = tuple(int(x) for x in a.color.split(","))

for i in range(n_frames):
    level = float(smooth[i])
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for gap, width, amax in [(8, 6, 140), (18, 10, 80)]:
        r = R + gap + level * 22
        alpha = int(amax * (0.35 + 0.65 * level))
        d.ellipse([C[0]-r, C[1]-r, C[0]+r, C[1]+r], outline=rgb + (alpha,), width=width)
    glow = img.filter(ImageFilter.GaussianBlur(6))
    Image.alpha_composite(glow, img).save(os.path.join(a.outdir, f"f_{i:05d}.png"))

print(f"{n_frames} images rendues ({n_frames / a.fps:.1f}s)")
