"""Scene 2 of the tabletop diorama: an open lane between a two-storey house and its low annex.

No courtyard wall this time (scene 1 is the walled courtyard house): a tall two-storey house on
the left, built from the Diriyah kit's facades, a low flat-roofed annex against its right side,
a paved lane in front of both (Motri slabs), dunes round the rim, palms. Level 2 is played here:
the cat is stuck up on the annex roof, and three mud blocks in the lane must be stood against
the annex wall as steps (scripts/table/steps_level.gd adds the blocks, cat and old man live).

Reuses the helpers of build_scene1.py. Real metres; writes assets/world/scene2/scene2.glb.
Usage: python3 tools/blender/build_scene2.py [-- --render out_dir]

Layout (Blender x, y; Godot x = x, z = -y):
  house   x -6.5 .. -0.5, y 0 .. 6, gable about 5 m up, parapets round a flat roof
  annex   x -0.5 .. 3.5,  y 1.5 .. 5.5, roof top at ANNEX_H; its front wall faces the lane
  lane    paved, in front of both (Godot z from about -1 to 7)
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_scene1 as b1  # noqa: E402  (resets Blender to an empty scene)

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from PIL import Image, ImageFilter  # noqa: E402

OUT = os.path.join(b1.ROOT, "assets", "world", "scene2")
os.makedirs(OUT, exist_ok=True)
b1.OUT = OUT
smooth, noise2, place, k, block = b1.smooth, b1.noise2, b1.place, b1.k, b1.block

HOUSE = (-6.5, -0.5, 0.0, 6.0)   # x0, x1, y0, y1
ANNEX = (-0.5, 3.5, 1.5, 5.5)
ANNEX_H = 2.8                    # roof top (scripts/table/steps_level.gd: ROOF_Y)
# the paved lane, Godot coordinates: x0, x1, z0, z1 (soft edges)
LANE = (-8.5, 6.5, -1.0, 7.5)


def bake_ground(n=1024):
    S = b1.SIZE
    xs = (np.arange(n) + 0.5) / n * S - S / 2
    X, Y = np.meshgrid(xs, -xs)
    H = b1.dune_height(X, Y)
    grain = noise2(n, 13, (16, 32, 64, 128), 1.4)
    ripples = np.sin(X * 1.5 + Y * 9 + grain * 5) * 0.025 + 0.975
    lo, hi = np.array([0xd9, 0xa6, 0x5e], float), np.array([0xf4, 0xd3, 0x97], float)
    t = np.clip(H * 0.18 + grain * 0.22 + 0.25, 0.1, 0.85)[..., None]
    col = (lo * (1 - t) + hi * t) * ripples[..., None]
    gy, gx = np.gradient(H, S / n)
    col *= np.clip(1 + (-gx * 0.35 + gy * 0.25) * 0.6, 0.8, 1.12)[..., None]
    # the lane: Motri slabs, edges broken up a little by noise
    Z = -Y
    edge = noise2(n, 17, (8, 16, 32), 1.6) * 0.8
    lane = (smooth(0.0, 0.5, X - LANE[0] + edge) * smooth(0.0, 0.5, LANE[1] - X + edge)
            * smooth(0.0, 0.5, Z - LANE[2] + edge) * smooth(0.0, 0.5, LANE[3] - Z + edge))
    slabs = np.asarray(Image.open(os.path.join(b1.MOTRI, "slabs.png")).convert("L"), float) / 255
    sx = ((X / 5.71) % 1 * slabs.shape[1]).astype(int) % slabs.shape[1]
    sy = ((Y / 5.71) % 1 * slabs.shape[0]).astype(int) % slabs.shape[0]
    st = slabs[sy, sx]
    slab_col = np.array([0xa8, 0x77, 0x62], float) * (1 - st[..., None]) + np.array([0xff, 0xcf, 0x8b], float) * st[..., None]
    m = (lane * 0.94)[..., None]
    col = col * (1 - m) + slab_col * m
    img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8)).filter(ImageFilter.SMOOTH)
    path_out = os.path.join(b1.TEX, "scene2_ground.jpg")
    img.save(path_out, quality=88)
    return path_out


def house():
    """The tall house: the vented-gable facade (two rows of windows) to the lane, stepped
    facades on the other sides, a flat roof inside the parapets, beam ends under it."""
    x0, x1, y0, y1 = HOUSE
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    place(k("facade_gable"), (cx, y0, 0), 0)
    place(k("facade_steps"), (x0, cy, 0), -90)
    place(k("facade_steps"), (x1, cy, 0), -90)
    place(k("facade_steps"), (cx, y1, 0), 180)
    mud = b1.tile_mat()
    w = x1 - x0 - 0.5
    block("HouseRoof", (w, y1 - y0 - 0.5, 0.2), (cx, cy, 3.3), mud)  # flat roof inside the parapets
    wood = b1.img_mat("scene2_wood", os.path.join(b1.TEX, "kit_lintel.jpg"), 0.85)
    for i in range(9):  # beam ends of the upper floor poking out of the facade
        block("BeamEnd%d" % i, (0.12, 0.35, 0.12), (x0 + 0.5 + i * (w / 8), y0 - 0.2, 3.3), wood, uv_full=True)
    door = b1.img_mat("scene2_door", os.path.join(b1.TEX, "house_door.png"), 0.8)
    block("HouseDoor", (1.0, 0.06, 1.9), (cx, y0 - 0.27, 0.95), door, uv_full=True)
    block("HouseLintel", (1.5, 0.3, 0.16), (cx, y0 - 0.3, 2.0), wood, uv_full=True)


def annex():
    """The low annex: plain mud walls, a flat roof, crenels on its back and right edges only
    (the front edge stays clear: the cat steps down from there)."""
    x0, x1, y0, y1 = ANNEX
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    place(k("wall"), (cx, y0, 0), 0)
    place(k("wall"), (cx, y1, 0), 180)
    place(k("wall"), (x1, cy, 0), 90)
    # the roof fits inside the walls, a little below their tops: laid over them, its top
    # would sit in the same plane as theirs and flicker (z-fighting)
    block("AnnexRoof", (x1 - x0 - 0.25, y1 - y0 - 0.5, 0.2), (cx - 0.125, cy, ANNEX_H - 0.14), b1.tile_mat())
    b1.crenels_on(cx, y1, 180, z=ANNEX_H)
    b1.crenels_on(x1, cy, 90, z=ANNEX_H)
    # a small window, high on the lane side
    wood = bpy.data.materials.get("scene2_wood")
    block("AnnexWindow", (0.6, 0.08, 0.5), (cx + 1.0, y0 - 0.27, 1.9), wood, uv_full=True)


def life():
    palm = os.path.join(b1.ROOT, "assets", "world", "palm.glb")
    for x, y, s, yaw in ((7.6, -5.0, 0.9, 40), (-9.6, 4.0, 1.0, 160), (8.5, 7.0, 1.0, 250),
                         (-3.0, 11.5, 0.95, 80), (11.5, -1.0, 0.85, 300)):
        place(palm, (x, y, 0), yaw, s)
    # (the old man, the cat, sparrows and the falcon are live: scripts/preview/diorama.gd)


def main():
    tex = bake_ground()
    b1.ground_mesh(tex)
    house()
    annex()
    life()
    if b1.RENDER:
        b1.render(b1.RENDER)
    b1.export()


main()
