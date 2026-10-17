"""The raid scene (level 10, «الغزوة»): open desert, no buildings.

The old man's camp at the front: the goat-hair tent and a kneeling camel (from the owner's
Motri repository); open sand in the middle with a few low rocks and dry shrubs; the high dunes
at the back, over which the raiders come (scripts/table/raid_level.gd brings the riders, so
none are baked here).

Reuses the helpers of build_scene1.py. Real metres; writes assets/world/scene_raid/scene_raid.glb.
Usage: python3 tools/blender/build_scene_raid.py [-- --render out_dir]

Layout (Godot x, z; Blender y = -z):
  tent         front left, centred (-7.6, 7.4)
  defenders    their line along z = 2.6 .. 3.4, clear of the tent (raid_level.gd)
  rocks        a few low ones in the middle
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_scene1 as b1  # noqa: E402  (resets Blender to an empty scene)

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from PIL import Image, ImageFilter  # noqa: E402

OUT = os.path.join(b1.ROOT, "assets", "world", "scene_raid")
os.makedirs(OUT, exist_ok=True)
b1.OUT = OUT
smooth, noise2, place, p = b1.smooth, b1.noise2, b1.place, b1.p
TENT = (-7.6, 7.4)


def bake_ground(n=1024):
    S = b1.SIZE
    xs = (np.arange(n) + 0.5) / n * S - S / 2
    X, Y = np.meshgrid(xs, -xs)
    Z = -Y
    H = b1.dune_height(X, Y)
    grain = noise2(n, 51, (16, 32, 64, 128), 1.4)
    ripples = np.sin(X * 5 + Y * 7 + grain * 6) * 0.03 + 0.97
    lo, hi = np.array([0xd9, 0xa6, 0x5e], float), np.array([0xf4, 0xd3, 0x97], float)
    t = np.clip(H * 0.18 + grain * 0.22 + 0.25, 0.1, 0.85)[..., None]
    col = (lo * (1 - t) + hi * t) * ripples[..., None]
    gy, gx = np.gradient(H, S / n)
    col *= np.clip(1 + (-gx * 0.35 + gy * 0.25) * 0.6, 0.8, 1.12)[..., None]
    # trodden sand round the camp, and the hoof-churned way down from the back dunes
    for cx, cz, r in ((TENT[0], TENT[1] - 1.5, 3.2), (0.0, 4.5, 4.0)):
        d = np.hypot(X - cx, Z - cz)
        w = smooth(r, r * 0.6, d)[..., None] * 0.3
        col = col * (1 - w) + np.array([0xc4, 0x96, 0x60], float) * w
    churn = smooth(5.5, 2.0, np.abs(X)) * smooth(6.0, -2.0, Z) * (0.5 + 0.5 * grain)
    col = col * (1 - churn[..., None] * 0.18) + np.array([0xc8, 0x98, 0x5c], float) * churn[..., None] * 0.18
    img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8)).filter(ImageFilter.SMOOTH)
    path_out = os.path.join(b1.TEX, "scene_raid_ground.jpg")
    img.save(path_out, quality=88)
    return path_out


def g(x, z, h=0.0):
    """Godot (x, z) and a height to Blender (x, y, z)."""
    return (x, -z, h)


def camp():
    place(p("tent"), g(*TENT), 0)
    place(p("camel_kneeling"), g(-2.0, 9.2), 200)
    rock = bpy.data.materials.new("scene_raid_rock")
    rock.use_nodes = True
    rock.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.32, 0.22, 0.13, 1)
    rock.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.95
    shrub = bpy.data.materials.new("scene_raid_shrub")
    shrub.use_nodes = True
    shrub.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.16, 0.12, 0.05, 1)
    shrub.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    rng = np.random.default_rng(10)
    for x, z, s in ((-3.6, -1.6, 0.8), (5.4, -2.8, 0.7), (-8.4, -3.0, 0.9), (8.6, -4.6, 0.8), (0.8, -6.2, 0.6)):
        for k in range(3):
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=s * (0.5 + 0.3 * rng.random()),
                                                  location=g(x + rng.uniform(-0.6, 0.6), z + rng.uniform(-0.5, 0.5), 0.1))
            o = bpy.context.active_object
            o.scale = (1.2, 1.0, 0.6)
            o.rotation_euler.z = rng.uniform(0, 3)
            o.data.materials.append(rock)
    for x, z in ((-10.2, 2.4), (9.8, 3.4), (6.0, 8.8), (-1.2, 9.6), (10.8, -1.6), (-10.8, -6.0), (3.0, -9.4)):
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
    if b1.RENDER:
        b1.render(b1.RENDER)
    b1.export()


main()
