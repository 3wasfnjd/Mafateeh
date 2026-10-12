"""Menu icons for Mafateeh (white on transparency; tinted in the game).
python make_icons.py <quest-native/assets/ui/icons>

Drawn at 4x and downsampled for clean edges. Diriyah motifs where they fit:
a Najdi door for "levels", a palm for "virtual reality", a lantern for hints,
a watchtower for "about", crenellations for the frame ornament."""
import math, os, sys
from PIL import Image, ImageDraw

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "../../assets/ui/icons")
os.makedirs(OUT, exist_ok=True)
S = 384  # drawing size; saved at 96
W = (255, 255, 255, 255)
LW = 26  # stroke


def canvas():
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def save(im, name):
    im.resize((96, 96), Image.LANCZOS).save(os.path.join(OUT, name + ".png"))


def arc_arrow(d, cx, cy, r, a0, a1, head=True):
    d.arc([cx - r, cy - r, cx + r, cy + r], a0, a1, fill=W, width=LW)
    if head:
        a = math.radians(a1)
        x, y = cx + r * math.cos(a), cy + r * math.sin(a)
        t = a + math.pi / 2
        pts = [(x + 46 * math.cos(t - 0.0), y + 46 * math.sin(t - 0.0)),
               (x + 42 * math.cos(a), y + 42 * math.sin(a)), (x - 42 * math.cos(a), y - 42 * math.sin(a))]
        d.polygon(pts, fill=W)


def najdi_door(d, x0, y0, x1, y1, fill=False):
    # Rectangular leaf with a pointed (triangular) head and studs.
    mid = (x0 + x1) / 2
    d.line([(x0, y1), (x0, y0 + 60), (mid, y0), (x1, y0 + 60), (x1, y1)], fill=W, width=LW, joint="curve")
    d.line([(x0 - 20, y1), (x1 + 20, y1)], fill=W, width=LW)
    d.line([(mid, y0 + 70), (mid, y1)], fill=W, width=LW // 2)
    for yy in (y0 + 120, y0 + 190):
        for xx in (mid - 40, mid + 40):
            d.ellipse([xx - 9, yy - 9, xx + 9, yy + 9], fill=W)


def palm(d, cx, base, h, scale=1.0):
    top = base - h
    # Ringed trunk, gently curved.
    d.line([(cx, base), (cx + 8 * scale, (base + top) / 2), (cx + 4 * scale, top)], fill=W, width=int(LW * scale), joint="curve")
    for k in range(1, 5):
        y = base - h * k / 5
        d.line([(cx - 14 * scale, y), (cx + 20 * scale, y)], fill=W, width=int(8 * scale))
    # Drooping fronds: arcs falling away to both sides.
    r = 110 * scale
    for side in (-1, 1):
        for lift in (0.0, 0.5, 1.0):
            x0 = cx + 4 * scale
            pts = []
            for i in range(9):
                t = i / 8
                x = x0 + side * r * t
                y = top - 40 * scale * lift * math.sin(t * math.pi * 0.8) + 70 * scale * t * t
                pts.append((x, y))
            d.line(pts, fill=W, width=int((LW - 8) * scale), joint="curve")


def icon(name):
    im, d = canvas()
    c = S / 2
    if name == "play":
        d.polygon([(130, 90), (130, 294), (290, 192)], fill=W)
    elif name == "restart":
        arc_arrow(d, c, c, 110, 210, 520 - 360 + 360 - 30)
    elif name == "levels":
        najdi_door(d, 110, 70, 274, 320)
    elif name == "settings":
        for k in range(8):
            a = k * math.pi / 4
            d.line([(c + 95 * math.cos(a), c + 95 * math.sin(a)), (c + 145 * math.cos(a), c + 145 * math.sin(a))], fill=W, width=48)
        d.ellipse([c - 105, c - 105, c + 105, c + 105], outline=W, width=LW + 8)
        d.ellipse([c - 40, c - 40, c + 40, c + 40], outline=W, width=LW)
    elif name == "about":  # Diriyah watchtower
        d.polygon([(140, 330), (160, 110), (224, 110), (244, 330)], outline=W, width=LW)
        for xx in (150, 192, 234):
            d.polygon([(xx - 20, 112), (xx, 70), (xx + 20, 112)], fill=W)
        d.rectangle([180, 170, 204, 230], fill=W)
    elif name == "next":
        d.line([(150, 80), (260, 192), (150, 304)], fill=W, width=LW + 10, joint="curve")
    elif name == "prev":
        d.line([(234, 80), (124, 192), (234, 304)], fill=W, width=LW + 10, joint="curve")
    elif name == "hint":  # lantern
        d.line([(c, 50), (c, 85)], fill=W, width=LW)
        d.polygon([(c - 70, 110), (c + 70, 110), (c + 50, 85), (c - 50, 85)], fill=W)
        d.rectangle([c - 70, 120, c + 70, 290], outline=W, width=LW)
        d.polygon([(c, 150), (c + 30, 205), (c, 260), (c - 30, 205)], fill=W)
        d.rectangle([c - 85, 290, c + 85, 320], fill=W)
    elif name == "sound":
        d.polygon([(80, 150), (140, 150), (210, 90), (210, 294), (140, 234), (80, 234)], fill=W)
        d.arc([180, 120, 300, 264], -50, 50, fill=W, width=LW)
        d.arc([180, 70, 350, 314], -50, 50, fill=W, width=LW)
    elif name == "controls":
        d.rounded_rectangle([60, 130, 324, 270], radius=60, outline=W, width=LW)
        d.line([(120, 200), (170, 200)], fill=W, width=LW)
        d.line([(145, 175), (145, 225)], fill=W, width=LW)
        d.ellipse([235, 165, 265, 195], fill=W)
        d.ellipse([265, 200, 295, 230], fill=W)
    elif name == "display":
        d.ellipse([60, 120, 324, 264], outline=W, width=LW)
        d.ellipse([c - 50, c - 50, c + 50, c + 50], fill=W)
    elif name == "atmosphere":  # sun over a dune
        d.ellipse([110, 70, 230, 190], outline=W, width=LW)
        for k in range(8):
            a = k * math.pi / 4
            d.line([(170 + 80 * math.cos(a), 130 + 80 * math.sin(a)), (170 + 105 * math.cos(a), 130 + 105 * math.sin(a))], fill=W, width=LW - 6)
        d.arc([20, 230, 260, 430], 200, 340, fill=W, width=LW)
        d.arc([160, 250, 400, 450], 200, 340, fill=W, width=LW)
    elif name == "language":
        d.ellipse([70, 70, 314, 314], outline=W, width=LW)
        d.ellipse([140, 70, 244, 314], outline=W, width=LW - 6)
        d.line([(70, c), (314, c)], fill=W, width=LW - 6)
    elif name == "quality":
        d.polygon([(c, 60), (c + 40, c - 40), (324, c), (c + 40, c + 40), (c, 324), (c - 40, c + 40), (60, c), (c - 40, c - 40)], fill=W)
    elif name == "board":  # table with a tiny courtyard
        d.rectangle([60, 200, 324, 230], fill=W)
        d.line([(90, 230), (90, 320)], fill=W, width=LW)
        d.line([(294, 230), (294, 320)], fill=W, width=LW)
        d.rectangle([120, 130, 264, 200], outline=W, width=LW - 6)
        for xx in (130, 170, 210, 250):
            d.polygon([(xx, 132), (xx + 12, 105), (xx + 24, 132)], fill=W)
    elif name == "reset":
        d.rectangle([110, 120, 274, 320], outline=W, width=LW)
        d.line([(80, 110), (304, 110)], fill=W, width=LW)
        d.rectangle([160, 70, 224, 110], outline=W, width=LW - 6)
        for xx in (155, 192, 229):
            d.line([(xx, 160), (xx, 280)], fill=W, width=LW - 10)
    elif name == "back":
        d.line([(300, c), (90, c)], fill=W, width=LW + 6)
        d.line([(170, 110), (90, c), (170, 274)], fill=W, width=LW + 6, joint="curve")
    elif name == "lock":
        d.rounded_rectangle([100, 170, 284, 320], radius=24, fill=W)
        d.arc([130, 70, 254, 230], 180, 360, fill=W, width=LW + 4)
        d.line([(130, 150), (130, 175)], fill=W, width=LW + 4)
        d.line([(254, 150), (254, 175)], fill=W, width=LW + 4)
    elif name == "check":
        d.line([(80, 200), (160, 280), (310, 110)], fill=W, width=LW + 14, joint="curve")
    elif name == "mr":  # a room corner with the board on a table
        d.line([(60, 110), (192, 60), (324, 110)], fill=W, width=LW - 6)
        d.line([(60, 110), (60, 300)], fill=W, width=LW - 6)
        d.line([(324, 110), (324, 300)], fill=W, width=LW - 6)
        d.line([(192, 60), (192, 250)], fill=W, width=LW - 10)
        d.rectangle([110, 230, 274, 252], fill=W)
        d.rectangle([140, 180, 244, 230], outline=W, width=LW - 8)
    elif name == "vr":  # headset
        d.rounded_rectangle([40, 120, 344, 270], radius=55, outline=W, width=LW)
        d.ellipse([85, 155, 175, 235], fill=W)
        d.ellipse([209, 155, 299, 235], fill=W)
        d.polygon([(162, 270), (192, 225), (222, 270)], fill=(0, 0, 0, 0))
        d.line([(20, 195), (40, 195)], fill=W, width=LW)
        d.line([(344, 195), (364, 195)], fill=W, width=LW)
    elif name == "privacy":
        d.polygon([(c, 60), (310, 110), (290, 230), (c, 330), (94, 230), (74, 110)], outline=W, width=LW)
        d.line([(140, 195), (180, 240), (250, 150)], fill=W, width=LW, joint="curve")
    elif name == "palm":
        palm(d, 180, 350, 240, 1.2)
    elif name == "door":
        najdi_door(d, 110, 60, 274, 330)
    elif name == "star":
        pts = []
        for k in range(16):
            r = 160 if k % 2 == 0 else 110
            a = k * math.pi / 8 - math.pi / 2
            pts.append((c + r * math.cos(a), c + r * math.sin(a)))
        d.polygon(pts, outline=W, width=LW - 6)
    save(im, name)


NAMES = ["play", "restart", "levels", "settings", "about", "next", "prev", "hint", "sound", "controls",
         "display", "atmosphere", "language", "quality", "board", "reset", "back", "lock", "check", "mr",
         "vr", "privacy", "palm", "door", "star"]
for n in NAMES:
    icon(n)

# Frame ornament: a strip of Najdi crenellations (stepped triangles), tileable.
strip = Image.new("RGBA", (512, 64), (0, 0, 0, 0))
d = ImageDraw.Draw(strip)
for i in range(8):
    x = i * 64
    d.rectangle([x + 8, 44, x + 56, 64], fill=W)
    d.polygon([(x + 14, 46), (x + 32, 6), (x + 50, 46)], fill=W)
strip.save(os.path.join(OUT, "crenellation.png"))
print(len(NAMES), "icons written to", OUT)
