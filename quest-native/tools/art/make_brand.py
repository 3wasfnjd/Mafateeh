"""Aboden Games (عبودين قيمز) studio name art.
python make_brand.py <quest-native/assets/brand> [cairo-arabic.ttf cairo-latin.ttf] [store_dir]
Writes aboden_wordmark.png (the names عبودين قيمز / ABODEN GAMES on transparency), used by
the launch intro. With [store_dir], also aboden_logo.png there: the full lockup with the
eight-point Najdi star and the letter ع, for the store page and docs (not in the APK).
Needs Pillow with libraqm (Arabic shaping) and TTF copies of the Cairo font."""
import math, os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

out = sys.argv[1]
AR = sys.argv[2] if len(sys.argv) > 2 else "/tmp/cairo-arabic.ttf"
LA = sys.argv[3] if len(sys.argv) > 3 else "/tmp/cairo-latin.ttf"
os.makedirs(out, exist_ok=True)
S = 1024
C = S / 2
GOLD_HI, GOLD_LO = (250, 221, 150), (188, 128, 52)
INK = (44, 27, 16)


def star(r, rot=0.0):
    pts = []
    for sq in (0, 45):
        pts.append([(C + r * math.cos(math.radians(a + sq + rot)), C + r * math.sin(math.radians(a + sq + rot)))
                    for a in (45, 135, 225, 315)])
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    for p in pts:
        d.polygon(p, fill=255)
    return m


def disc(r):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).ellipse([C - r, C - r, C + r, C + r], fill=255)
    return m


def gradient(top, bottom):
    g = Image.new("RGBA", (S, S))
    d = ImageDraw.Draw(g)
    for y in range(S):
        t = y / (S - 1)
        d.line([(0, y), (S, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,))
    return g


def layer(mask, fill):
    img = fill if isinstance(fill, Image.Image) else Image.new("RGBA", (S, S), fill + (255,))
    img = img.copy()
    img.putalpha(ImageChops.multiply(img.getchannel("A"), mask))
    return img


emblem = Image.new("RGBA", (S, S), (0, 0, 0, 0))
outer = star(470)
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
shadow.putalpha(outer.filter(ImageFilter.GaussianBlur(14)).point(lambda a: a * 0.35))
emblem.alpha_composite(shadow, (0, 10))
emblem.alpha_composite(layer(outer, gradient(GOLD_HI, GOLD_LO)))
emblem.alpha_composite(layer(star(428), INK))                     # dark inlay
emblem.alpha_composite(layer(ImageChops.subtract(star(404), star(390)), gradient(GOLD_HI, GOLD_LO)))  # inner fillet
emblem.alpha_composite(layer(ImageChops.subtract(disc(300), disc(288)), gradient(GOLD_HI, GOLD_LO)))
# The letter ع, gold, optically centred.
glyph = Image.new("L", (S, S), 0)
font = ImageFont.truetype(AR, 520)
d = ImageDraw.Draw(glyph)
bb = d.textbbox((0, 0), "ع", font=font, direction="rtl", language="ar")
d.text((C - (bb[0] + bb[2]) / 2, C - (bb[1] + bb[3]) / 2 + 6), "ع", font=font, fill=255, direction="rtl", language="ar")
emblem.alpha_composite(layer(glyph, gradient(GOLD_HI, GOLD_LO)))

# Full lockup (emblem + wordmark) on transparency.
W, H = 2048, 1400
lock = Image.new("RGBA", (W, H), (0, 0, 0, 0))
lock.alpha_composite(emblem.resize((720, 720), Image.LANCZOS), ((W - 720) // 2, 40))
far = ImageFont.truetype(AR, 220)
fla = ImageFont.truetype(LA, 96)
cream, edge = (255, 244, 224, 255), (60, 34, 18, 255)


def words(text, font, gap, y, fill, rtl):
    """Text as a mask (outline by dilation, so joined Arabic letters show no seams).
    Words are drawn one by one: the Arabic subset of Cairo has no space glyph."""
    parts = text.split(" ") if rtl else list(text)  # Latin: one letter at a time (tracking)
    if rtl:
        parts = parts[::-1]
    kw = dict(direction="rtl", language="ar") if rtl else {}
    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    boxes = [probe.textbbox((0, 0), w, font=font, **kw) if w.strip() else (0, 0, gap, 0) for w in parts]
    total = sum(b[2] - b[0] for b in boxes) + gap * (len(parts) - 1)
    m = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(m)
    x = (W - total) / 2
    for w, b in zip(parts, boxes):
        d.text((x - b[0], y - b[1]), w, font=font, fill=255, **kw)
        x += b[2] - b[0] + gap
    lock.alpha_composite(layer_wh(m.filter(ImageFilter.MaxFilter(13)), edge))
    lock.alpha_composite(layer_wh(m, fill))


def layer_wh(mask, color):
    img = Image.new("RGBA", mask.size, color)
    img.putalpha(mask)
    return img


words("عبودين قيمز", far, 70, 800, cream, True)
words("ABODEN GAMES", fla, 30, 1180, (232, 190, 120, 255), False)
word = lock.crop((0, 760, W, H))
word.crop(word.getbbox()).save(os.path.join(out, "aboden_wordmark.png"))
lock = lock.crop(lock.getbbox())
if len(sys.argv) > 4:  # the full lockup is for the store page / docs, not the APK
    lock.save(os.path.join(sys.argv[4], "aboden_logo.png"))
print("brand art written to", out)
