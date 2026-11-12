from PIL import Image, ImageDraw, ImageFont, ImageFilter
from pathlib import Path
import math

OUT = Path("GTAConverter/Assets.xcassets/AppIcon.appiconset")
OUT.mkdir(parents=True, exist_ok=True)
S = 1024
im = Image.new("RGB", (S, S))
px = im.load()
for y in range(S):
    for x in range(S):
        t = y / (S - 1)
        glow = max(0.0, 1.0 - math.sqrt(((x - 760) / 850) ** 2 + ((y - 220) / 680) ** 2))
        px[x, y] = (int(9 + 13 * glow), int(11 + 7 * glow), int(17 + 15 * glow + 12 * t))

# Soft red city-light haze
haze = Image.new("RGBA", (S, S), (0, 0, 0, 0))
hd = ImageDraw.Draw(haze)
hd.ellipse((580, 100, 1160, 650), fill=(155, 18, 28, 65))
haze = haze.filter(ImageFilter.GaussianBlur(100))
im = Image.alpha_composite(im.convert("RGBA"), haze)

# Abstract road perspective, deliberately logo-free
road = Image.new("RGBA", (S, S), (0, 0, 0, 0))
rd = ImageDraw.Draw(road)
rd.polygon([(390, 570), (635, 570), (950, 1024), (70, 1024)], fill=(25, 28, 35, 190))
rd.line([(512, 620), (512, 1000)], fill=(238, 125, 44, 150), width=8)
rd.line([(415, 700), (250, 1024)], fill=(90, 98, 110, 100), width=5)
rd.line([(610, 700), (780, 1024)], fill=(90, 98, 110, 100), width=5)
road = road.filter(ImageFilter.GaussianBlur(2))
im = Image.alpha_composite(im, road)

draw = ImageDraw.Draw(im)
font_bold = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
font_regular = "/System/Library/Fonts/Supplemental/Arial.ttf"
title_font = ImageFont.truetype(font_bold, 112)
user_font = ImageFont.truetype(font_bold, 54)

title = "GTAV MODS"
bbox = draw.textbbox((0, 0), title, font=title_font, stroke_width=2)
tw = bbox[2] - bbox[0]
tx = (S - tw) // 2
ty = 330
# Restrained shadow for crisp contrast
draw.text((tx + 5, ty + 8), title, font=title_font, fill=(0, 0, 0, 230), stroke_width=3, stroke_fill=(0, 0, 0, 230))
draw.text((tx, ty), title, font=title_font, fill=(247, 247, 249, 255), stroke_width=2, stroke_fill=(55, 58, 66, 255))

username = "Moa_sa7"
ub = draw.textbbox((0, 0), username, font=user_font)
uw = ub[2] - ub[0]
ux = (S - uw) // 2
uy = 485
draw.rounded_rectangle((ux - 34, uy - 18, ux + uw + 34, uy + 78), radius=24, fill=(8, 10, 15, 210), outline=(238, 125, 44, 220), width=3)
draw.text((ux, uy), username, font=user_font, fill=(255, 145, 55, 255))

im.convert("RGB").save(OUT / "AppIcon.png", "PNG", optimize=True)
print(f"Generated {OUT / 'AppIcon.png'} ({S}x{S})")
