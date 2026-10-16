"""Scene 4 of the tabletop diorama: a desert camp, no buildings.

Open dunes, the goat-hair tent, the sheep pen with the flock inside, camels by a trough (all
from the owner's Motri repository), and the hard sand in front of the tent where the camp's
cars park. Level 4 is played on that parking ground: the cars (Motri's shas and datsun) and
the water truck are live (scripts/table/camp_level.gd), so they are not baked here.

Reuses the helpers of build_scene1.py. Real metres; writes assets/world/scene4/scene4.glb.
Usage: python3 tools/blender/build_scene4.py [-- --render out_dir]

Layout (Godot x, z; Blender y = -z):
  parking grid  6 x 6 cells of 2.2 m, x -6.6 .. 6.6, z -5.6 .. 7.6 (camp_level.gd: GRID)
  tent          behind the grid, centred (-2.5, -9.2)
  sheep pen     left, centred (-10.3, 3.0), scaled 0.42
  trough        right, beside the way out of the grid (row 2, z -0.1): x 8.4 .. 10.6, z -1.7
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_scene1 as b1  # noqa: E402  (resets Blender to an empty scene)

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from PIL import Image, ImageFilter  # noqa: E402

OUT = os.path.join(b1.ROOT, "assets", "world", "scene4")
os.makedirs(OUT, exist_ok=True)
b1.OUT = OUT
smooth, noise2, place, p, block = b1.smooth, b1.noise2, b1.place, b1.p, b1.block

GRID = (-6.6, 6.6, -5.6, 7.6)      # Godot x0, x1, z0, z1
PEN = (-10.3, 3.0)                 # Godot centre x, z of the sheep pen
PEN_SCALE = 0.42                   # Motri's pen is 17 x 11 m with its gate rails
TROUGH = (9.5, -1.7)               # Godot centre x, z


def bake_ground(n=1024):
    S = b1.SIZE
    xs = (np.arange(n) + 0.5) / n * S - S / 2
    X, Y = np.meshgrid(xs, -xs)
    Z = -Y
    H = b1.dune_height(X, Y)
    grain = noise2(n, 41, (16, 32, 64, 128), 1.4)
    ripples = np.sin(X * 4 + Y * 8 + grain * 6) * 0.03 + 0.97
    lo, hi = np.array([0xd9, 0xa6, 0x5e], float), np.array([0xf4, 0xd3, 0x97], float)
    t = np.clip(H * 0.18 + grain * 0.22 + 0.25, 0.1, 0.85)[..., None]
    col = (lo * (1 - t) + hi * t) * ripples[..., None]
    gy, gx = np.gradient(H, S / n)
    col *= np.clip(1 + (-gx * 0.35 + gy * 0.25) * 0.6, 0.8, 1.12)[..., None]
    # the parking ground: packed sand, a little darker, crossed by old tyre tracks
    x0, x1, z0, z1 = GRID
    edge = noise2(n, 43, (8, 16, 32), 1.6) * 0.6
    park = (smooth(-0.3, 0.6, X - x0 + edge) * smooth(-0.3, 0.6, x1 - X + edge)
            * smooth(-0.3, 0.6, Z - z0 + edge) * smooth(-0.3, 0.6, z1 - Z + edge))
    # faint lines in the packed sand along the cell edges, so the parking grid reads
    cell = (x1 - x0) / 6
    lines = (np.abs(np.sin(np.pi * (X - x0) / cell)) < 0.06) | (np.abs(np.sin(np.pi * (Z - z0) / cell)) < 0.06)
    tracks = 1 - 0.09 * lines
    packed = np.array([0xcf, 0xa2, 0x6a], float) * (0.94 + 0.12 * grain)[..., None] * tracks[..., None]
    col = col * (1 - park[..., None] * 0.8) + packed * park[..., None] * 0.8
    # trodden sand round the pen and the trough
    for cx, cz, r in ((PEN[0], PEN[1], 4.4), (TROUGH[0], TROUGH[1] - 1.0, 2.8), (-2.5, -6.2, 2.6)):
        d = np.hypot(X - cx, Z - cz)
        w = smooth(r, r * 0.6, d)[..., None] * 0.35
        col = col * (1 - w) + np.array([0xc4, 0x96, 0x60], float) * w
    img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8)).filter(ImageFilter.SMOOTH)
    path_out = os.path.join(b1.TEX, "scene4_ground.jpg")
    img.save(path_out, quality=88)
    return path_out


def g(x, z, h=0.0):
    """Godot (x, z) and a height to Blender (x, y, z)."""
    return (x, -z, h)


def pen_and_trough():
    """Motri's sheep pen (fence, shade, feeders and flock, tools/blender/import_motri_camp.py),
    scaled down to fit beside the parking ground, its gate towards the cars; and Motri's
    drinking trough beside the truck's way out."""
    place(p("sheep_pen"), g(PEN[0], PEN[1]), 0, PEN_SCALE)
    place(p("trough"), g(*TROUGH), 90, 1.4)


def camp():
    place(p("tent"), g(-2.5, -9.2), 0)
    # camels by the trough, waiting; one kneeling by the tent, a calf
    place(p("camel_standing"), g(8.4, -4.4), 10)
    place(p("camel_standing"), g(10.6, -4.6), -20)
    place(p("camel_calf"), g(11.6, -2.6), 60)
    place(p("camel_kneeling"), g(-7.6, -6.8), 120)
    # dry desert shrubs (arfaj), low and grey-brown
    shrub = bpy.data.materials.new("scene4_shrub")
    shrub.use_nodes = True
    shrub.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.16, 0.12, 0.05, 1)
    shrub.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    rng = np.random.default_rng(4)
    for x, z in ((-8.5, 8.5), (-4.0, 10.2), (5.2, 9.6), (9.0, 6.8), (-11.0, -3.5), (3.8, -9.4), (11.2, 3.4)):
        for k in range(3):
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.35 + 0.15 * rng.random(),
                                                  location=g(x + rng.uniform(-0.4, 0.4), z + rng.uniform(-0.4, 0.4), 0.2))
            o = bpy.context.active_object
            o.scale = (1.0, 1.0, 0.65)
            o.data.materials.append(shrub)
            o.location.z += float(b1.dune_height(np.array(o.location.x), np.array(o.location.y)))


def main():
    tex = bake_ground()
    b1.ground_mesh(tex)
    camp()
    pen_and_trough()
    if b1.RENDER:
        b1.render(b1.RENDER)
    b1.export()


main()
