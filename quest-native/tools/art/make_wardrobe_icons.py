"""Wardrobe icons for the start card (wordless).
python3 make_wardrobe_icons.py [out_dir]   (default assets/ui/icons)

wardrobe.png   white: the old man's head in a ghutra and agal (the card button)
w_<item>.png   coloured glyphs, one per Wardrobe item, drawn on a light disc in the game:
               ghutra, agal_gold, thobe_beige, thobe_grey, misbaha, glasses, bisht
Drawn at 4x and downsampled.
"""
import math
import os
import sys

from PIL import Image, ImageDraw

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "../../assets/ui/icons")
S = 384
INK = (92, 66, 42, 255)       # dark brown outline
WHITE = (255, 255, 255, 255)


def canvas():
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def save(im, name):
    im.resize((96, 96), Image.LANCZOS).save(os.path.join(OUT, name + ".png"))


def head(d, fill, line, band=None):
    """Old man's head: ghutra falling to the shoulders, face, agal band."""
    d.polygon([(192, 52), (300, 150), (322, 330), (62, 330), (84, 150)], fill=fill, outline=line, width=14)
    d.ellipse([132, 128, 252, 262], fill=(240, 214, 182, 255) if fill != WHITE else (0, 0, 0, 0), outline=line, width=14)
    d.line([(92, 130), (292, 130)], fill=band or line, width=26)


def robe(d, fill, trim=None):
    d.polygon([(150, 70), (234, 70), (300, 330), (84, 330)], fill=fill, outline=INK, width=12)
    d.line([(192, 80), (192, 200)], fill=trim or INK, width=10)
    d.ellipse([168, 52, 216, 92], fill=fill, outline=INK, width=10)


def main():
    os.makedirs(OUT, exist_ok=True)
    # card button: white line drawing
    im, d = canvas()
    d.polygon([(192, 50), (304, 152), (326, 332), (58, 332), (80, 152)], outline=WHITE, width=24)
    d.ellipse([136, 132, 248, 258], outline=WHITE, width=22)
    d.line([(90, 132), (294, 132)], fill=WHITE, width=30)
    save(im, "wardrobe")

    im, d = canvas()
    head(d, (250, 250, 246, 255), INK)
    save(im, "w_ghutra")

    im, d = canvas()
    for k in (0, 1):  # a doubled gold-threaded agal ring
        d.ellipse([64, 120 + k * 46, 320, 216 + k * 46], outline=(214, 170, 64, 255), width=30)
        d.ellipse([64, 120 + k * 46, 320, 216 + k * 46], outline=INK, width=6)
    save(im, "w_agal_gold")

    im, d = canvas()
    robe(d, (233, 218, 190, 255))
    save(im, "w_thobe_beige")

    im, d = canvas()
    robe(d, (165, 165, 158, 255))
    save(im, "w_thobe_grey")

    im, d = canvas()
    cx, cy, r = 192, 170, 110
    for i in range(16):  # beads on a loop, with a tassel
        a = i / 16 * math.tau
        x, y = cx + r * math.cos(a), cy + r * 0.8 * math.sin(a)
        d.ellipse([x - 20, y - 20, x + 20, y + 20], fill=(150, 92, 52, 255), outline=INK, width=5)
    d.line([(192, 258), (192, 330)], fill=INK, width=14)
    d.polygon([(170, 330), (214, 330), (192, 360)], fill=(214, 170, 64, 255))
    save(im, "w_misbaha")

    im, d = canvas()
    for x in (110, 274):  # round reading glasses
        d.ellipse([x - 66, 140, x + 66, 272], outline=INK, width=22)
    d.arc([162, 168, 222, 232], 200, 340, fill=INK, width=18)
    save(im, "w_glasses")

    im, d = canvas()
    d.polygon([(110, 64), (274, 64), (346, 334), (38, 334)], fill=(62, 44, 32, 255), outline=INK, width=10)
    d.line([(150, 64), (110, 334)], fill=(214, 170, 64, 255), width=16)   # gold zari edging
    d.line([(234, 64), (274, 334)], fill=(214, 170, 64, 255), width=16)
    d.polygon([(150, 64), (234, 64), (192, 150)], fill=(240, 236, 224, 255))  # the thobe beneath
    save(im, "w_bisht")


main()
