"""Composes store icon (512, 24-bit), spatialized icon (180, transparent) and the
transparent logo from the hero portrait. python compose_icons.py <portrait.png> <out_dir>
Needs Pillow with libraqm (Arabic shaping) and TTF copies of the Cairo font."""
import sys, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

portrait, out = sys.argv[1], sys.argv[2]
AR = sys.argv[3] if len(sys.argv) > 3 else "/tmp/cairo-arabic.ttf"
LA = sys.argv[4] if len(sys.argv) > 4 else "/tmp/cairo-latin.ttf"
face = Image.open(portrait).convert("RGBA")

# Icon: warm Najdi backdrop with stepped crenellations, character portrait.
S = 1024
bg = Image.new("RGB", (S, S))
d = ImageDraw.Draw(bg)
for y in range(S):
    t = y / S
    d.line([(0, y), (S, y)], fill=(int(214 - 60 * t), int(140 - 50 * t), int(84 - 30 * t)))
wall = (232, 190, 140)
d.rectangle([0, 760, S, S], fill=wall)
for i in range(9):
    x = i * 128
    for k, (w, h) in enumerate([(96, 22), (64, 22), (32, 22)]):
        d.rectangle([x + (128 - w) // 2, 760 - (k + 1) * h, x + (128 + w) // 2, 760 - k * h], fill=wall)
icon = bg.convert("RGBA")
f = face.resize((900, 900), Image.LANCZOS)
shadow = Image.new("RGBA", f.size, (0, 0, 0, 0))
shadow.putalpha(f.getchannel("A").filter(ImageFilter.GaussianBlur(18)).point(lambda a: a * 0.45))
icon.alpha_composite(shadow, (72, 150))
icon.alpha_composite(f, (62, 124))
icon.convert("RGB").resize((512, 512), Image.LANCZOS).save(os.path.join(out, "icon_512x512.png"))

# Spatialized icon, two layers (Meta): background = the Najdi backdrop (opaque);
# foreground = the character alone on transparency, kept inside the safe area
# (18 px padding on every side of 180) with no baked shadow.
bg.resize((180, 180), Image.LANCZOS).save(os.path.join(out, "spatial_icon_background_180x180.png"))
# SPATIAL_PORTRAIT=<full-body.png> uses an uncropped full-body render (no cut edge).
body = Image.open(os.environ["SPATIAL_PORTRAIT"]).convert("RGBA") if os.environ.get("SPATIAL_PORTRAIT") else face
bbox = body.getbbox()
crop = body.crop(bbox)
side = max(crop.size)
sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
sq.alpha_composite(crop, ((side - crop.width) // 2, (side - crop.height) // 2))
fg = Image.new("RGBA", (180, 180), (0, 0, 0, 0))
fg.alpha_composite(sq.resize((144, 144), Image.LANCZOS), (18, 18))
fg.save(os.path.join(out, "spatial_icon_foreground_180x180.png"))
if not (os.path.exists(AR) and os.path.exists(LA)):
    print("icons written to", out, "(logo skipped: Cairo TTF fonts not found)")
    sys.exit(0)

# Logo: the exact app name on transparency (Arabic shaped with raqm).
W, H = 2600, 1100
logo = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(logo)
far = ImageFont.truetype(AR, 520, layout_engine=ImageFont.Layout.RAQM)
fla = ImageFont.truetype(LA, 240)
for text, font, y in (("مفاتيح", far, 40), ("Mafateeh", fla, 700)):
    w = d.textlength(text, font=font, direction="rtl" if font is far else None)
    x = (W - w) / 2
    d.text((x, y), text, font=font, fill=(255, 243, 223, 255), stroke_width=22, stroke_fill=(70, 38, 18, 255),
           direction="rtl" if font is far else None)
logo.crop(logo.getbbox()).save(os.path.join(out, "logo_transparent.png"))
print("icons and logo written to", out)
