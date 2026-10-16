"""Scene 9 of the tabletop diorama: the palm farm and its well (السانية).

A farm of palms: the stone well with its frame and pulley (the owner's well from
build_water_kit.py) and its basin at the back left, a short stone channel from the basin to
the field, a farm hut of mud with a door at the back right, a fence of palm fronds along the
back, palms in rows down both sides, and tilled earth in the middle where the channels are
laid. The channel tiles, the three palm plots they water and the camel are live
(scripts/table/sania_level.gd).

Reuses the helpers of build_scene1.py. Real metres; writes assets/world/scene9/scene9.glb.
Usage: python3 tools/blender/build_scene9.py [-- --render out_dir]

Layout (Godot x, z; Blender y = -z):
  field   5 x 4 channel tiles of 1.6 m, x -4 .. 4, z -2.1 .. 4.3 (sania_level.gd: GRID)
  basin   (-5.7, -1.3): the water enters the field's first row from the west
  well    (-7.6, -3.6); the camel's walk runs from it towards the front left
  hut     (6.2, -6.2)
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_scene1 as b1  # noqa: E402  (resets Blender to an empty scene)

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from PIL import Image, ImageFilter  # noqa: E402

OUT = os.path.join(b1.ROOT, "assets", "world", "scene9")
os.makedirs(OUT, exist_ok=True)
b1.OUT = OUT
smooth, noise2, place, k, block = b1.smooth, b1.noise2, b1.place, b1.k, b1.block

FIELD = (-4.4, 4.4, -2.5, 4.7)   # Godot x0, x1, z0, z1 (a little round the tiles)


def g(x, z, h=0.0):
    return (x, -z, h)


def bake_ground(n=1024):
    S = b1.SIZE
    xs = (np.arange(n) + 0.5) / n * S - S / 2
    X, Y = np.meshgrid(xs, -xs)
    Z = -Y
    H = b1.dune_height(X, Y)
    grain = noise2(n, 91, (16, 32, 64, 128), 1.4)
    ripples = np.sin(X * 5 + Y * 6 + grain * 5) * 0.025 + 0.975
    lo, hi = np.array([0xd9, 0xa6, 0x5e], float), np.array([0xf4, 0xd3, 0x97], float)
    t = np.clip(H * 0.18 + grain * 0.22 + 0.25, 0.1, 0.85)[..., None]
    col = (lo * (1 - t) + hi * t) * ripples[..., None]
    gy, gx = np.gradient(H, S / n)
    col *= np.clip(1 + (-gx * 0.35 + gy * 0.25) * 0.6, 0.8, 1.12)[..., None]
    # the farm: darker watered earth everywhere inside the frond fence, furrowed in the field
    farm = smooth(11.5, 9.5, np.hypot(X, Z * 1.15))
    earth = np.array([0xa8, 0x7a, 0x4e], float) * (0.88 + 0.22 * grain)[..., None]
    col = col * (1 - farm[..., None] * 0.7) + earth * farm[..., None] * 0.7
    x0, x1, z0, z1 = FIELD
    field = smooth(0.0, 0.3, X - x0) * smooth(0.0, 0.3, x1 - X) * smooth(0.0, 0.3, Z - z0) * smooth(0.0, 0.3, z1 - Z)
    furrow = 0.9 + 0.1 * np.sin(Z * 7.0)
    tilled = np.array([0x8e, 0x63, 0x3e], float) * furrow[..., None]
    col = col * (1 - field[..., None] * 0.6) + tilled * field[..., None] * 0.6
    img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8)).filter(ImageFilter.SMOOTH)
    path_out = os.path.join(b1.TEX, "scene9_ground.jpg")
    img.save(path_out, quality=88)
    return path_out


def well_and_basin():
    place(k("well"), g(-7.6, -3.6), 30)
    place(k("water_basin"), g(-5.7, -1.3), 0)
    ch = place(k("water_channel"), g(-4.3, -1.3), 90)   # a short run from the basin to the field
    ch.scale = (1.0, 0.3, 1.0)


def hut():
    mud = b1.tile_mat()
    cx, cz = 6.2, -6.2
    place(k("wall_door"), g(cx, cz + 2.0), 0)
    place(k("wall"), g(cx, cz - 2.0), 180)
    for x, yaw in ((cx - 2.0, -90), (cx + 2.0, 90)):
        side = place(k("wall"), g(x, cz), yaw)
        side.scale = (0.875, 1.0, 1.0)   # between the front and back walls
    block("HutRoof", (4.4, 4.4, 0.2), g(cx, cz, 2.75), mud)
    b1.crenels_on(cx, -(cz + 2.0), 0, z=2.85)


def fence():
    """A fence of palm fronds along the back: posts and leaning fronds."""
    frond = bpy.data.materials.new("scene9_frond")
    frond.use_nodes = True
    frond.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.32, 0.22, 0.1, 1)
    frond.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    rng = np.random.default_rng(9)
    for i in range(36):
        x = -11.0 + i * 0.42
        if 3.6 < x < 8.8:
            continue   # the hut stands there
        z = -9.2 + 0.3 * math.sin(x * 0.7)
        o = block("Frond%d" % i, (0.12, 0.05, 2.0 + rng.uniform(-0.3, 0.3)), (0, 0, 0), frond)
        o.location = g(x, z, 1.0 + float(b1.dune_height(np.array(x), np.array(-z))))
        o.rotation_euler = (math.radians(rng.uniform(-8, 8)), math.radians(rng.uniform(-10, 10)), 0)


def palms():
    palm = os.path.join(b1.ROOT, "assets", "world", "palm.glb")
    rng = np.random.default_rng(19)
    for side in (-1, 1):
        for row in range(4):
            if side < 0 and row < 2:
                continue   # the well and its basin are there
            x = side * (7.4 + (row % 2) * 1.6) - (1.6 if side < 0 else 0.0)
            z = -4.4 + row * 3.0
            place(palm, g(x + rng.uniform(-0.3, 0.3), z), rng.uniform(0, 360), rng.uniform(0.85, 1.05))
    for x, z in ((-3.0, -7.4), (1.0, -7.8), (-6.0, 8.8), (5.0, 9.0)):
        place(palm, g(x, z), rng.uniform(0, 360), rng.uniform(0.85, 1.0))


def main():
    tex = bake_ground()
    b1.ground_mesh(tex)
    well_and_basin()
    hut()
    fence()
    palms()
    if b1.RENDER:
        b1.render(b1.RENDER)
    b1.export()


main()
