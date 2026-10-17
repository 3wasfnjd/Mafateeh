"""Extra icons for the table menu (same look as make_icons.py: white on transparency,
tinted in the game; drawn at 4x and downsampled).
python3 tools/art/make_menu_icons.py [out_dir]

  close  music  wind  dust  rain  hand_left  hand_right  haptics  players_1  players_2
  minus  plus  gem  daynight
"""
import math
import os
import sys

from PIL import Image, ImageDraw

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "../../assets/ui/icons")
S = 384
W = (255, 255, 255, 255)
LW = 26


def canvas():
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def save(im, name):
    im.resize((96, 96), Image.LANCZOS).save(os.path.join(OUT, name + ".png"))


def line(d, pts, w=LW):
    d.line(pts, fill=W, width=w, joint="curve")
    for x, y in (pts[0], pts[-1]):
        d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=W)


def close():
    im, d = canvas()
    line(d, [(100, 100), (284, 284)], 34)
    line(d, [(284, 100), (100, 284)], 34)
    save(im, "close")


def music():
    im, d = canvas()
    # two quavers joined by a beam
    for x, y in ((110, 290), (262, 262)):
        d.ellipse([x - 52, y - 38, x + 52, y + 38], fill=W)
    line(d, [(152, 290), (152, 92)])
    line(d, [(304, 262), (304, 64)])
    d.polygon([(140, 80), (316, 52), (316, 110), (140, 138)], fill=W)
    save(im, "music")


def wind():
    im, d = canvas()
    for y, x1, r in ((120, 250, 44), (200, 300, 50), (280, 220, 36)):
        line(d, [(60, y), (x1, y)])
        d.arc([x1 - r, y - 2 * r, x1 + r, y], 200, 450, fill=W, width=LW)
    save(im, "wind")


def dust():
    im, d = canvas()
    # a swirl and drifting motes
    pts = []
    for i in range(60):
        t = i / 59
        a = t * math.pi * 3.2
        r = 30 + 110 * t
        pts.append((190 + r * math.cos(a), 200 + r * math.sin(a) * 0.7))
    line(d, pts, 22)
    for x, y, r in ((300, 90, 16), (330, 160, 11), (80, 300, 14), (300, 310, 12), (70, 110, 10)):
        d.ellipse([x - r, y - r, x + r, y + r], fill=W)
    save(im, "dust")


def cloud(d, cx, cy, k=1.0):
    for x, y, r in ((-70, 10, 56), (0, -30, 78), (72, 6, 60)):
        d.ellipse([cx + (x - r) * k, cy + (y - r) * k, cx + (x + r) * k, cy + (y + r) * k], fill=W)
    d.rounded_rectangle([cx - 126 * k, cy + 4 * k, cx + 132 * k, cy + 66 * k], radius=30 * k, fill=W)


def rain():
    im, d = canvas()
    cloud(d, 192, 140)
    for x in (110, 192, 274):
        line(d, [(x + 14, 250), (x - 12, 330)], 22)
    save(im, "rain")


def hand(name, mirror):
    im, d = canvas()
    # an open palm, fingers up, thumb out to one side
    d.rounded_rectangle([110, 170, 280, 330], radius=60, fill=W)
    for x, top in ((128, 70), (174, 46), (220, 56), (264, 92)):
        d.rounded_rectangle([x - 21, top, x + 21, 220], radius=21, fill=W)
    th = [(110, 250), (60, 170), (46, 140)]
    line(d, th, 40)
    if mirror:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    save(im, name)


def haptics():
    im, d = canvas()
    d.rounded_rectangle([142, 70, 242, 314], radius=46, outline=W, width=LW)
    d.ellipse([172, 116, 212, 156], fill=W)
    for s in (-1, 1):
        for r in (60, 100):
            cx = 192 + s * 0
            d.arc([cx - 50 - r, 192 - r, cx + 50 + r, 192 + r], 145 if s < 0 else -35, 215 if s < 0 else 35, fill=W, width=22)
    save(im, "haptics")


def person(d, cx, k=1.0):
    d.ellipse([cx - 40 * k, 70, cx + 40 * k, 150], fill=W)
    d.pieslice([cx - 86 * k, 170, cx + 86 * k, 400], 180, 360, fill=W)


def players(n):
    im, d = canvas()
    if n == 1:
        person(d, 192)
    else:
        person(d, 120, 0.9)
        person(d, 264, 0.9)
    save(im, "players_%d" % n)


def sign(name, plus):
    im, d = canvas()
    line(d, [(92, 192), (292, 192)], 36)
    if plus:
        line(d, [(192, 92), (192, 292)], 36)
    save(im, name)


def daynight():
    """The day going round: a sun on one side, a crescent moon on the other, an arc between."""
    im, d = canvas()
    d.ellipse([60, 150, 160, 250], fill=W)
    for k in range(8):
        a = k * math.pi / 4
        line(d, [(110 + 70 * math.cos(a), 200 + 70 * math.sin(a)), (110 + 92 * math.cos(a), 200 + 92 * math.sin(a))], 16)
    d.ellipse([214, 120, 334, 240], fill=W)
    d.ellipse([244, 100, 354, 210], fill=(0, 0, 0, 0))
    d.arc([70, 40, 330, 330], 200, 340, fill=W, width=14)
    save(im, "daynight")


def gem():
    im, d = canvas()
    top, mid, bot = 90, 160, 320
    d.polygon([(110, top), (274, top), (330, mid), (192, bot), (54, mid)], outline=W, width=LW)
    d.line([(54, mid), (330, mid)], fill=W, width=18)
    d.line([(150, top), (122, mid), (192, bot), (262, mid), (234, top)], fill=W, width=18)
    d.line([(192, top), (122, mid)], fill=W, width=12)
    d.line([(192, top), (262, mid)], fill=W, width=12)
    save(im, "gem")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    close()
    music()
    wind()
    dust()
    rain()
    hand("hand_right", False)
    hand("hand_left", True)
    haptics()
    players(1)
    players(2)
    sign("minus", False)
    sign("plus", True)
    gem()
    daynight()
    print("menu icons written to", OUT)
