"""System splash image for the Quest (shown by the OS the moment the app opens,
before the game loads): the studio name in plain white on transparency, no frame
or background. The OpenXR Vendors plugin copies application/boot_splash/image into
the APK as vr_splash.png when "Instant splash screen" is on.
python3 make_splash.py <quest-native/vr_splash.png>"""
import io, os, sys
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "../../vr_splash.png")
FONTS = os.path.join(HERE, "../../assets/fonts")


def font(name, size):
    # Cairo ships as woff2; hand FreeType a plain TrueType copy.
    f = TTFont(os.path.join(FONTS, name))
    f.flavor = None
    buf = io.BytesIO()
    f.save(buf)
    buf.seek(0)
    return ImageFont.truetype(buf, size, layout_engine=ImageFont.Layout.RAQM)


W, H = 2048, 1024
im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(im)
ar = font("cairo-arabic-700-normal.woff2", 230)
en = font("cairo-latin-500-normal.woff2", 96)
# The Arabic subset of Cairo has no space glyph: set the two words apart by hand
# (right to left: «عبودين» then «قيمز»).
gap = 70
words = ["عبودين", "قيمز"]
widths = [d.textlength(w, font=ar, direction="rtl", language="ar") for w in words]
x = W / 2 + (sum(widths) + gap) / 2
for w, wd in zip(words, widths):
    d.text((x - wd, H / 2 - 60), w, font=ar, fill=(255, 255, 255, 255), anchor="lm", direction="rtl", language="ar")
    x -= wd + gap
d.text((W / 2, H / 2 + 170), "ABODEN GAMES", font=en, fill=(255, 255, 255, 235), anchor="mm")
im.save(OUT)
print("splash written to", OUT)
