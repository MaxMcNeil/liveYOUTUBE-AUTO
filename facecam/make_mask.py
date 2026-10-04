#!/usr/bin/env python3
"""Masque circulaire anti-aliasé (blanc = visible) pour découper la vidéo en rond."""
import sys
from PIL import Image, ImageDraw
size, out = int(sys.argv[1]), sys.argv[2]
k = 4  # sur-échantillonnage pour des bords lisses
m = Image.new("L", (size*k, size*k), 0)
ImageDraw.Draw(m).ellipse([0, 0, size*k-1, size*k-1], fill=255)
m.resize((size, size), Image.LANCZOS).save(out)
