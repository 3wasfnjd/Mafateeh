"""Level numbers for the start card's level row: white Arabic-Indic digits (١ .. ١١).
python3 make_level_icons.py [out_dir]   (default assets/ui/icons) -> level_<n>.png
Drawn at 4x and downsampled."""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "../../assets/ui/icons")
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
DIGITS = "٠١٢٣٤٥٦٧٨٩"
S = 384

os.makedirs(OUT, exist_ok=True)
for n in range(1, 12):
    text = "".join(DIGITS[int(c)] for c in str(n))
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    font = ImageFont.truetype(FONT, 250 if n < 10 else 190)
    box = d.textbbox((0, 0), text, font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    d.text(((S - w) / 2 - box[0], (S - h) / 2 - box[1]), text, font=font, fill=(255, 255, 255, 255))
    im.resize((96, 96), Image.LANCZOS).save(os.path.join(OUT, "level_%d.png" % n))
