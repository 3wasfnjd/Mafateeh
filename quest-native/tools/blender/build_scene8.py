"""Scene 8 of the tabletop diorama: the barter market (souq).

A row of four shops along the back (mud shopfronts with doors, each with a wooden awning
on poles and a cloth top), two open stalls on the sides, a packed-earth market lane, and
goods about: sacks, crates (Motri's crate), baskets. The merchants, their goods and the
old man are live (scripts/table/barter_level.gd).

Reuses the helpers of build_scene1.py. Real metres; writes assets/world/scene8/scene8.glb.
Usage: python3 tools/blender/build_scene8.py [-- --render out_dir]

Layout (Godot x, z; Blender y = -z):
  back shops   doors at z -5.0, x -6, -2, 2, 6 (barter_level.gd: STALLS); awnings to z -3
  side stalls  (-8.0, 1.0) facing +x and (8.0, 1.0) facing -x
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_scene1 as b1  # noqa: E402  (resets Blender to an empty scene)

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from PIL import Image, ImageFilter  # noqa: E402

OUT = os.path.join(b1.ROOT, "assets", "world", "scene8")
os.makedirs(OUT, exist_ok=True)
b1.OUT = OUT
smooth, noise2, place, k, p, block = b1.smooth, b1.noise2, b1.place, b1.k, b1.p, b1.block

SHOP_Z = -5.0
AWNING_COLOURS = [(0.55, 0.12, 0.08, 1), (0.75, 0.55, 0.2, 1), (0.25, 0.32, 0.45, 1), (0.6, 0.35, 0.2, 1),
                  (0.45, 0.18, 0.28, 1), (0.7, 0.62, 0.45, 1)]


def g(x, z, h=0.0):
    return (x, -z, h)


def bake_ground(n=1024):
    S = b1.SIZE
    xs = (np.arange(n) + 0.5) / n * S - S / 2
    X, Y = np.meshgrid(xs, -xs)
    Z = -Y
    H = b1.dune_height(X, Y)
    grain = noise2(n, 81, (16, 32, 64, 128), 1.4)
    ripples = np.sin(X * 6 + Y * 6 + grain * 5) * 0.025 + 0.975
    lo, hi = np.array([0xd9, 0xa6, 0x5e], float), np.array([0xf4, 0xd3, 0x97], float)
    t = np.clip(H * 0.18 + grain * 0.22 + 0.25, 0.1, 0.85)[..., None]
    col = (lo * (1 - t) + hi * t) * ripples[..., None]
    gy, gx = np.gradient(H, S / n)
    col *= np.clip(1 + (-gx * 0.35 + gy * 0.25) * 0.6, 0.8, 1.12)[..., None]
    edge = noise2(n, 83, (8, 16, 32), 1.6) * 0.7
    lane = smooth(0.0, 0.7, 9.4 - np.abs(X) + edge) * smooth(0.0, 0.5, Z - SHOP_Z + 0.3) * smooth(0.0, 0.7, 6.5 - Z + edge)
    earth = np.array([0xc8, 0x98, 0x62], float) * (0.9 + 0.2 * grain)[..., None]
    col = col * (1 - lane[..., None] * 0.85) + earth * lane[..., None] * 0.85
    img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8)).filter(ImageFilter.SMOOTH)
    path_out = os.path.join(b1.TEX, "scene8_ground.jpg")
    img.save(path_out, quality=88)
    return path_out


def cloth(i):
    m = bpy.data.materials.new("scene8_awning%d" % i)
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = AWNING_COLOURS[i % len(AWNING_COLOURS)]
    m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    return m


def awning(cx, cz, yaw_deg, i, wood):
    """Two poles, a beam and a sloping cloth top, in front of a shop (local: depth along +z)."""
    a = math.radians(yaw_deg)

    def at(dx, dz, h):  # a point in the awning's frame, to Blender
        x = cx + dx * math.cos(a) + dz * math.sin(a)
        z = cz - dx * math.sin(a) + dz * math.cos(a)
        return g(x, z, h)
    for dx in (-1.5, 1.5):
        block("AwningPole", (0.1, 0.1, 2.3), at(dx, 2.0, 1.15), wood, uv_full=True)
    # (block() bakes its position into the vertices: build it at the origin, then move and tilt it)
    top = block("Awning%d" % i, (3.4, 2.4, 0.05), (0, 0, 0), cloth(i))
    top.rotation_euler = (math.radians(-10), 0, a)   # sloping down towards the lane
    top.location = at(0, 1.0, 2.45)
    # the counter: a crate and a plank
    place(p("crate"), at(-0.7, 1.6, 0), yaw_deg)
    place(p("crate"), at(0.7, 1.6, 0), yaw_deg + 90)
    block("Counter%d" % i, (2.4, 0.6, 0.06), at(0, 1.6, 0.8), wood, uv_full=True)


def shops():
    wood = b1.img_mat("scene8_wood", os.path.join(b1.TEX, "kit_lintel.jpg"), 0.85)
    mud = b1.tile_mat()
    for i, x in enumerate((-6.0, -2.0, 2.0, 6.0)):
        place(k("wall_door"), g(x, SHOP_Z), 180)
        b1.crenels_on(x, -SHOP_Z, 180)
        awning(x, SHOP_Z, 0, i, wood)
    block("ShopRoof", (16.4, 4.0, 0.2), g(0, SHOP_Z - 2.25, 2.8), mud)   # the shops behind their fronts
    for x in (-8.25, 8.25):
        block("ShopEnd", (0.5, 4.2, 2.8), g(x, SHOP_Z - 2.25, 1.4), mud)
    block("ShopBack", (16.4, 0.5, 2.8), g(0, SHOP_Z - 4.25, 1.4), mud)
    awning(-8.4, 0.0, 90, 4, wood)     # open stalls on the sides, facing the lane
    awning(8.4, 0.0, -90, 5, wood)


def goods():
    sack = bpy.data.materials.new("scene8_sack")
    sack.use_nodes = True
    sack.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.3, 0.2, 0.1, 1)
    rng = np.random.default_rng(8)
    for x, z in ((-4.0, -2.4), (-3.4, -2.6), (4.2, -2.3), (0.0, -2.6), (-6.6, 3.6), (6.8, 3.2), (-1.0, 5.6), (1.4, 5.2)):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=0.35, location=g(x, z, 0.3))
        o = bpy.context.active_object
        o.scale = (1.0, 0.9, 1.15)
        o.rotation_euler = (0, 0, rng.uniform(0, math.tau))
        o.data.materials.append(sack)
    for x, z, yaw in ((-5.2, 4.6, 10), (5.6, 5.0, 40), (9.6, -3.0, 70)):
        place(p("crate"), g(x, z), yaw)


def life():
    palm = os.path.join(b1.ROOT, "assets", "world", "palm.glb")
    for x, z, s, yaw in ((-11.0, 4.0, 0.95, 30), (11.0, 4.6, 1.0, 140), (-6.0, 10.4, 0.9, 260), (7.0, 10.0, 0.95, 80)):
        place(palm, g(x, z), yaw, s)


def main():
    tex = bake_ground()
    b1.ground_mesh(tex)
    shops()
    goods()
    life()
    if b1.RENDER:
        b1.render(b1.RENDER)
    b1.export()


main()
