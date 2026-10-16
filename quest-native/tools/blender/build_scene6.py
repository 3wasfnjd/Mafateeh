"""Scene 6 of the tabletop diorama: the palace square, where the ardah is danced.

A tall palace front (the vented-gable facade and the stepped facade side by side, a flat roof
inside their parapets, a carved door), the owner's sandstone tower at its right corner, low
crenellated walls running off both sides, and a wide paved square in front. Level 6 is
played here: the drums, the flag poles and the line of men are live (drum_level.gd).

Reuses the helpers of build_scene1.py. Real metres; writes assets/world/scene6/scene6.glb.
Usage: python3 tools/blender/build_scene6.py [-- --render out_dir]

Layout (Godot x, z; Blender y = -z):
  palace   front at z -6.0, x -6 .. 6, 6 m deep; tower at (8.2, -6.5)
  square   paved, x -8 .. 8, z -5.6 .. 6
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_scene1 as b1  # noqa: E402  (resets Blender to an empty scene)

import numpy as np  # noqa: E402
from PIL import Image, ImageFilter  # noqa: E402

OUT = os.path.join(b1.ROOT, "assets", "world", "scene6")
os.makedirs(OUT, exist_ok=True)
b1.OUT = OUT
smooth, noise2, place, k, block = b1.smooth, b1.noise2, b1.place, b1.k, b1.block

FRONT_Z = -6.0
SQUARE = (-8.0, 8.0, -5.6, 6.0)


def g(x, z, h=0.0):
    return (x, -z, h)


def bake_ground(n=1024):
    S = b1.SIZE
    xs = (np.arange(n) + 0.5) / n * S - S / 2
    X, Y = np.meshgrid(xs, -xs)
    Z = -Y
    H = b1.dune_height(X, Y)
    grain = noise2(n, 61, (16, 32, 64, 128), 1.4)
    ripples = np.sin(X * 7 + Y * 4 + grain * 5) * 0.025 + 0.975
    lo, hi = np.array([0xd9, 0xa6, 0x5e], float), np.array([0xf4, 0xd3, 0x97], float)
    t = np.clip(H * 0.18 + grain * 0.22 + 0.25, 0.1, 0.85)[..., None]
    col = (lo * (1 - t) + hi * t) * ripples[..., None]
    gy, gx = np.gradient(H, S / n)
    col *= np.clip(1 + (-gx * 0.35 + gy * 0.25) * 0.6, 0.8, 1.12)[..., None]
    paving = np.asarray(Image.open(os.path.join(b1.MOTRI, "stone-paving.png")).convert("L"), float) / 255
    sx = ((X / 4.0) % 1 * paving.shape[1]).astype(int) % paving.shape[1]
    sy = ((Y / 4.0) % 1 * paving.shape[0]).astype(int) % paving.shape[0]
    st = paving[sy, sx]
    x0, x1, z0, z1 = SQUARE
    edge = noise2(n, 63, (8, 16, 32), 1.6) * 0.6
    sq = (smooth(0.0, 0.6, X - x0 + edge) * smooth(0.0, 0.6, x1 - X + edge)
          * smooth(0.0, 0.6, Z - z0 + 1.0) * smooth(0.0, 0.6, z1 - Z + edge))
    pave_col = np.array([0xb8, 0x8c, 0x66], float) * (1 - st[..., None]) + np.array([0xf2, 0xd2, 0xa0], float) * st[..., None]
    m = (sq * 0.92)[..., None]
    col = col * (1 - m) + pave_col * m
    img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8)).filter(ImageFilter.SMOOTH)
    path_out = os.path.join(b1.TEX, "scene6_ground.jpg")
    img.save(path_out, quality=88)
    return path_out


def palace():
    mud = b1.tile_mat()
    wood = b1.img_mat("scene6_wood", os.path.join(b1.TEX, "kit_lintel.jpg"), 0.85)
    door = b1.img_mat("scene6_door", os.path.join(b1.TEX, "house_door.png"), 0.8)
    # two facades side by side to the square, stepped sides, a back, a flat roof
    place(k("facade_steps"), g(-3.0, FRONT_Z), 0)
    place(k("facade_gable"), g(3.0, FRONT_Z), 0)
    for x in (-6.0, 6.0):
        place(k("facade_steps"), g(x, FRONT_Z - 3.0), -90)
    for x in (-3.0, 3.0):
        place(k("facade_steps"), g(x, FRONT_Z - 6.0), 180)
    block("PalaceRoof", (11.44, 5.44, 0.2), g(0, FRONT_Z - 3.0, 3.3), mud)
    block("PalaceDoor", (1.6, 0.06, 2.4), g(3.0, FRONT_Z + 0.27, 1.2), door, uv_full=True)
    block("PalaceLintel", (2.1, 0.3, 0.18), g(3.0, FRONT_Z + 0.3, 2.5), wood, uv_full=True)
    for i in range(13):
        block("BeamEnd%d" % i, (0.12, 0.35, 0.12), g(-5.7 + i * 0.95, FRONT_Z + 0.2, 3.3), wood, uv_full=True)
    place(os.path.join(b1.ROOT, "assets", "world", "house", "tower.glb"), g(8.4, FRONT_Z - 0.6), 180)
    # low crenellated walls off to the left
    for x in (-8.25, -12.25):
        place(k("wall"), g(x, FRONT_Z), 0)
        b1.crenels_on(x, -FRONT_Z, 0)


def life():
    palm = os.path.join(b1.ROOT, "assets", "world", "palm.glb")
    for x, z, s, yaw in ((-10.5, 2.0, 1.0, 40), (10.8, 1.5, 0.95, 160), (-7.0, 9.6, 0.9, 260),
                         (7.6, 9.2, 1.0, 10), (-12.0, -9.0, 0.9, 90)):
        place(palm, g(x, z), yaw, s)


def main():
    tex = bake_ground()
    b1.ground_mesh(tex)
    palace()
    life()
    if b1.RENDER:
        b1.render(b1.RENDER)
    b1.export()


main()
