#!/usr/bin/env python3
"""Generate the 1024x1024 iOS app icon required by the asset catalog.

The repository intentionally keeps the generated PNG out of source control;
this script recreates it deterministically during CI.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
SIZE = 1024

image = Image.new("RGB", (SIZE, SIZE))
pixels = image.load()
for y in range(SIZE):
    for x in range(SIZE):
        t = (x * 0.42 + y * 0.58) / (2 * (SIZE - 1))
        # Deep navy-to-purple gradient.
        pixels[x, y] = (
            int(12 + 36 * t),
            int(13 + 8 * t),
            int(34 + 92 * t),
        )

draw = ImageDraw.Draw(image)
# Subtle inset frame and a central monogram.
draw.rounded_rectangle((76, 76, 948, 948), radius=190, outline=(118, 91, 235), width=12)
try:
    font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 208)
except OSError:
    try:
        font = ImageFont.truetype("DejaVuSans-Bold.ttf", 208)
    except OSError:
        font = ImageFont.load_default()

label = "INRPF"
bbox = draw.textbbox((0, 0), label, font=font, stroke_width=0)
w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
draw.text(((SIZE - w) / 2, (SIZE - h) / 2 - 24), label, font=font, fill=(248, 247, 255))
# Small accent line anchors the mark without relying on platform-specific fonts.
draw.rounded_rectangle((352, 670, 672, 690), radius=10, fill=(153, 128, 255))

OUT.parent.mkdir(parents=True, exist_ok=True)
image.save(OUT, format="PNG", optimize=True)
print(f"Generated {OUT} ({SIZE}x{SIZE})")
