"""Diriyah / Najdi identity art for celebrations and menus (no external images).
Usage: python3 make_identity.py <out_dir>   (default assets/ui/identity)
Writes:
  sadu_band.png   tileable Sadu weave band (red, black, ivory, saffron; triangles,
                  diamonds and the "eyes" row), used for panel trims
  najdi_star.png  eight-pointed star (white, alpha) — tinted gold for stars earned
  crenel.png      a row of Najdi stepped crenellations (white, alpha)
  petal.png       rose petal sprite (alpha)
  palm_leaf.png   palm leaflet sprite (alpha)
"""
import os
import sys

import numpy as np
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "../../assets/ui/identity")
os.makedirs(OUT, exist_ok=True)


def hexc(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], dtype=float)


def save(name, rgba):
    Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, name), optimize=True)


# --- Sadu band (512 x 96, tiles horizontally) ---------------------------------------
W, H = 512, 96
y, x = np.mgrid[0:H, 0:W].astype(float)
red, black, ivory, saffron, brown = hexc("#9e2a24"), hexc("#1d1714"), hexc("#efe4cc"), hexc("#d49a2a"), hexc("#5b3a26")
img = np.zeros((H, W, 3)) + ivory
v = y / H
# outer black borders and thin red lines
img[(v < 0.08) | (v > 0.92)] = black
img[((v > 0.1) & (v < 0.14)) | ((v > 0.86) & (v < 0.9))] = red
# central field: red with ivory triangles pointing up and down (shajarah / teeth)
field = (v > 0.18) & (v < 0.82)
img[field] = red
period = 48.0
u = (x % period) / period
tv = (v - 0.18) / 0.64
tri_up = field & (tv > 0.5) & (np.abs(u - 0.5) * 2 < (tv - 0.5) * 2)
tri_dn = field & (tv < 0.5) & (np.abs(u - 0.5) * 2 < (0.5 - tv) * 2)
img[tri_up | tri_dn] = ivory
# diamonds (eyes) in the middle row, black with a saffron centre
dm = np.abs(((x + period / 2) % period) - period / 2) / (period / 2) + np.abs(tv - 0.5) * 4.0
img[field & (dm < 0.55)] = black
img[field & (dm < 0.22)] = saffron
# woven texture: alternating weft rows
weave = ((np.floor(y / 2) % 2) * 0.06 + 0.97)
img = img * weave[..., None]
# the faint warp grain
img *= (0.97 + 0.03 * np.sin(x * 1.7))[..., None]
save("sadu_band.png", np.dstack([img, np.full((H, W), 255.0)]))

# --- Eight-pointed Najdi star (256) -----------------------------------------------------
N = 256
y, x = (np.mgrid[0:N, 0:N] - N / 2 + 0.5) / (N / 2)
r = np.hypot(x, y)
a = np.arctan2(y, x)
# union of two rotated squares = eight-pointed star; soft edge
sq1 = np.maximum(np.abs(x), np.abs(y))
xr, yr = (x + y) / np.sqrt(2), (y - x) / np.sqrt(2)
sq2 = np.maximum(np.abs(xr), np.abs(yr))
d = np.minimum(sq1, sq2)
alpha = np.clip((0.72 - d) / 0.03, 0, 1)
# carved inner line
inner = np.clip(1 - np.abs(d - 0.5) / 0.035, 0, 1) * 0.35
shade = 255 * (1 - inner)
save("najdi_star.png", np.dstack([shade, shade, shade, alpha * 255]))

# --- Stepped crenellations row (512 x 128) ------------------------------------------------
W, H = 512, 128
y, x = np.mgrid[0:H, 0:W].astype(float)
period = 128.0
u = (x % period) / period
h = 1.0 - y / H
steps = np.select([np.abs(u - 0.5) < 0.12, np.abs(u - 0.5) < 0.24, np.abs(u - 0.5) < 0.36], [1.0, 0.72, 0.44], 0.18)
alpha = (h < steps).astype(float)
# small triangular vent in each merlon
tri = (np.abs(u - 0.5) * 2 < (h - 0.3) * 1.6) & (h > 0.3) & (h < 0.5)
alpha[tri] = 0
save("crenel.png", np.dstack([np.full((H, W, 3), 255.0), alpha * 255]))

# --- Rose petal and palm leaflet sprites (128) -------------------------------------------
N = 128
y, x = (np.mgrid[0:N, 0:N] - N / 2 + 0.5) / (N / 2)
petal = ((x / 0.55) ** 2 + ((y + 0.15 * x * x) / 0.85) ** 2) < 1.0
pal = np.clip(1 - ((x / 0.55) ** 2 + (y / 0.85) ** 2), 0, 1)
col = hexc("#c4384a")[None, None] * (0.75 + 0.35 * pal[..., None]) + hexc("#f2b0b8")[None, None] * 0.15 * (y[..., None] < -0.4)
save("petal.png", np.dstack([col, petal * 255.0]))
leaf = (np.abs(x) < 0.12 * (1 - np.abs(y)) + 0.02) & (np.abs(y) < 0.98)
lc = hexc("#6f8a3a")[None, None] * (0.85 + 0.25 * (np.abs(x) < 0.02)[..., None])
save("palm_leaf.png", np.dstack([np.broadcast_to(lc, (N, N, 3)), leaf * 255.0]))
print("identity art written to", OUT)
