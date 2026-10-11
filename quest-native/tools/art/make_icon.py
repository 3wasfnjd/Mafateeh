"""Draws the launcher icon (icon_192.png): a stylised Najdi doorway with a key."""
from PIL import Image, ImageDraw
import sys

S = 192 * 4
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
d.rounded_rectangle([0, 0, S - 1, S - 1], radius=150, fill=(201, 141, 82, 255))
d.rectangle([110, 300, 658, 700], fill=(232, 195, 143, 255))
for i in range(7):  # stepped crenellations (shurfat)
    x = 110 + i * 80
    d.polygon([(x, 300), (x + 40, 240), (x + 80, 300)], fill=(232, 195, 143, 255))
d.rounded_rectangle([290, 400, 478, 700], radius=20, fill=(110, 68, 38, 255))
d.line([(384, 400), (384, 700)], fill=(80, 48, 26, 255), width=8)
for y in (460, 560, 640):
    for x in (330, 438):
        d.ellipse([x - 9, y - 9, x + 9, y + 9], fill=(60, 50, 44, 255))
for x in (180, 590):  # triangular vents
    d.polygon([(x - 30, 370), (x + 30, 370), (x, 330)], fill=(110, 68, 38, 255))
d.ellipse([340, 150, 428, 238], outline=(246, 214, 120, 255), width=22)
d.rectangle([374, 236, 394, 360], fill=(246, 214, 120, 255))
d.rectangle([394, 316, 430, 336], fill=(246, 214, 120, 255))
img.resize((192, 192), Image.LANCZOS).save(sys.argv[1])
