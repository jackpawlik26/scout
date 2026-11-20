#!/usr/bin/env python3
"""Turns raw window captures (2x PNGs with transparent rounded corners) into site/assets/shots/*.webp.

Usage: python3 -I marketing/screenshots/export.py <folder of captures>
"""
import os, sys
from PIL import Image

src = sys.argv[1]
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../site/assets/shots")
os.makedirs(out, exist_ok=True)
WIDTH = 2000   # shown at up to ~1000 CSS px, so this stays sharp on Retina

# name: crop box in window points (None = whole window)
SHOTS = {
    "list": None, "split": None, "cleanup": None, "triage": None, "agents": None,
    "diskmap": None, "packages": None, "shortcuts": None, "icons": None,
    # Just the palette panel (its edges in the 1440×850 window), corners masked so it floats.
    "palette": (380, 97, 1060, 604),
}
PANEL_RADIUS = 30   # px at 2x
for name, box in SHOTS.items():
    im = Image.open(os.path.join(src, name + ".png")).convert("RGBA")
    width = WIDTH
    if box:
        from PIL import ImageDraw
        im = im.crop(tuple(v * 2 for v in box))
        mask = Image.new("L", im.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.width - 1, im.height - 1), PANEL_RADIUS, fill=255)
        im.putalpha(mask)
        width = 1200
    if im.width > width:
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    path = os.path.join(out, name + ".webp")
    im.save(path, "WEBP", quality=86, method=6, alpha_quality=100)
    print(f"{name}.webp  {im.width}×{im.height}  {os.path.getsize(path) // 1024} KB")
