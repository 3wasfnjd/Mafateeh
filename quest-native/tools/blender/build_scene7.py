"""Scene 7 of the tabletop diorama: a night camp of a caravan among the dunes.

High dunes, a dark rock outcrop with a stone shelter built against it (dry-stone walls and
a flat roof of branches), a campfire ring, saddle bags, and a stone cairn (رجم) out at the
gap between the dunes to the south, where the way goes on. Level 7 is played here; the
camels, the sky of stars and the fire are live (scripts/table/stars_level.gd).

Reuses the helpers of build_scene1.py. Real metres; writes assets/world/scene7/scene7.glb.
Usage: python3 tools/blender/build_scene7.py [-- --render out_dir]

Layout (Godot x, z; Blender y = -z):
  outcrop   back left, about (-6, -6); the shelter against it at (-3.4, -5.0)
  campfire  (1.6, -0.6)            cairn  (0.0, 9.2)
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_scene1 as b1  # noqa: E402  (resets Blender to an empty scene)

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from PIL import Image, ImageFilter  # noqa: E402

OUT = os.path.join(b1.ROOT, "assets", "world", "scene7")
os.makedirs(OUT, exist_ok=True)
b1.OUT = OUT
smooth, noise2, place, block = b1.smooth, b1.noise2, b1.place, b1.block

FIRE = (1.6, -0.6)
CAIRN = (0.0, 9.2)


def g(x, z, h=0.0):
    return (x, -z, h)


def bake_ground(n=1024):
    S = b1.SIZE
    xs = (np.arange(n) + 0.5) / n * S - S / 2
    X, Y = np.meshgrid(xs, -xs)
    Z = -Y
    H = b1.dune_height(X, Y)
    grain = noise2(n, 71, (16, 32, 64, 128), 1.4)
    ripples = np.sin(X * 3 + Y * 9 + grain * 6) * 0.03 + 0.97
    lo, hi = np.array([0xc9, 0x96, 0x58], float), np.array([0xeb, 0xc6, 0x8a], float)
    t = np.clip(H * 0.18 + grain * 0.22 + 0.25, 0.1, 0.85)[..., None]
    col = (lo * (1 - t) + hi * t) * ripples[..., None]
    gy, gx = np.gradient(H, S / n)
    col *= np.clip(1 + (-gx * 0.35 + gy * 0.25) * 0.6, 0.8, 1.12)[..., None]
    # gravel round the outcrop, trodden sand round the camp, a track out to the cairn
    for cx, cz, r, c, w in ((-6.0, -6.0, 5.0, (0x9a, 0x80, 0x66), 0.5), (0.0, -1.0, 5.0, (0xc2, 0x92, 0x5a), 0.35)):
        d = np.hypot(X - cx, Z - cz)
        m = smooth(r, r * 0.5, d)[..., None] * w
        col = col * (1 - m) + np.array(c, float) * m
    track = smooth(0.6, 0.2, np.abs(X - 0.3 * np.sin(Z * 0.4))) * smooth(1.0, 2.0, Z) * smooth(10.0, 8.5, Z)
    col = col * (1 - track[..., None] * 0.25) + np.array([0xb8, 0x8a, 0x55], float) * track[..., None] * 0.25
    img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8)).filter(ImageFilter.SMOOTH)
    path_out = os.path.join(b1.TEX, "scene7_ground.jpg")
    img.save(path_out, quality=88)
    return path_out


def rock_mat():
    m = bpy.data.materials.new("scene7_rock")
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.2, 0.13, 0.08, 1)
    m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    return m


def rock(m, at, size, seed):
    rng = np.random.default_rng(seed)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0, location=at)
    o = bpy.context.active_object
    for v in o.data.vertices:
        v.co *= 1.0 + rng.uniform(-0.18, 0.18)
    o.scale = size
    o.rotation_euler = (0, 0, rng.uniform(0, math.tau))
    o.data.materials.append(m)
    for p in o.data.polygons:
        p.use_smooth = False
    return o


def outcrop():
    m = rock_mat()
    # a low ridge of broken rock at the back left, flat-topped like the Tuwaiq edge
    for i, (x, z, sx, sy, sz) in enumerate(((-6.5, -6.5, 3.2, 2.4, 2.6), (-8.8, -4.4, 2.4, 2.2, 1.9),
                                             (-4.2, -7.6, 2.6, 1.8, 2.2), (-9.4, -7.4, 2.0, 2.0, 3.0),
                                             (-6.0, -9.2, 2.6, 1.6, 2.0), (-2.6, -8.6, 1.4, 1.2, 1.2))):
        h = float(b1.dune_height(np.array(x), np.array(-z)))
        rock(m, g(x, z, h + sz * 0.45), (sx, sy, sz), 70 + i)
    for i, (x, z, s) in enumerate(((-1.2, -6.4, 0.5), (3.6, -7.4, 0.7), (-10.0, 0.4, 0.8), (6.4, 3.0, 0.5),
                                   (-5.2, 5.4, 0.6), (8.6, -3.8, 0.9))):
        rock(m, g(x, z, s * 0.4), (s, s * 0.9, s * 0.7), 90 + i)


def shelter():
    """Dry-stone walls against the rock, a doorway, a roof of branches."""
    stone = bpy.data.materials.new("scene7_drystone")
    stone.use_nodes = True
    stone.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.15, 0.1, 0.065, 1)
    stone.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    cx, cz = -3.4, -5.0
    rng = np.random.default_rng(7)
    for side in ((-1.5, 0, 0.4, 3.0), (1.5, 0, 0.4, 3.0)):     # side walls (x offset, , thickness, depth)
        for row in range(5):
            for k in range(5):
                block("Stone", (0.42 + rng.uniform(0, 0.12), 0.6 + rng.uniform(0, 0.2), 0.36),
                      g(cx + side[0] + rng.uniform(-0.04, 0.04), cz - 1.2 + k * 0.6, 0.18 + row * 0.36), stone)
    for row in range(5):                                        # the front wall, a doorway in it
        for k in range(6):
            x = cx - 1.5 + k * 0.6
            if abs(x - cx) < 0.5 and row < 4:
                continue
            block("Stone", (0.6 + rng.uniform(0, 0.12), 0.42, 0.36), g(x, cz + 1.4, 0.18 + row * 0.36), stone)
    wood = b1.img_mat("scene7_wood", os.path.join(b1.TEX, "kit_lintel.jpg"), 0.85)
    for i in range(7):
        block("Branch%d" % i, (3.6, 0.12, 0.1), g(cx, cz - 1.4 + i * 0.47, 1.9), wood, uv_full=True)
    straw = bpy.data.materials.new("scene7_thatch")
    straw.use_nodes = True
    straw.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.3, 0.2, 0.1, 1)
    block("Thatch", (3.7, 3.3, 0.08), g(cx, cz, 2.0), straw)


def camp():
    stone = rock_mat()
    x, z = FIRE
    for i in range(10):
        a = i / 10 * math.tau
        rock(stone, g(x + math.cos(a) * 0.7, z + math.sin(a) * 0.7, 0.08), (0.2, 0.18, 0.13), 200 + i)
    # saddle bags and a rolled rug by the fire
    cloth = bpy.data.materials.new("scene7_saddlebag")
    cloth.use_nodes = True
    cloth.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.42, 0.08, 0.06, 1)
    for i, (dx, dz) in enumerate(((-1.4, 0.8), (-1.0, 1.3), (2.9, 0.6))):
        block("SaddleBag%d" % i, (0.7, 0.4, 0.35), g(x + dx, z + dz, 0.18), cloth)
    # the cairn at the gap between the dunes: stacked flat stones
    cx, cz = CAIRN
    base = float(b1.dune_height(np.array(cx), np.array(-cz)))
    for i, s in enumerate((0.8, 0.65, 0.52, 0.4, 0.3)):
        rock(stone, g(cx, cz, base + 0.15 + i * 0.28), (s, s * 0.9, 0.16), 300 + i)


def main():
    tex = bake_ground()
    b1.ground_mesh(tex)
    outcrop()
    shelter()
    camp()
    if b1.RENDER:
        b1.render(b1.RENDER)
    b1.export()


main()
