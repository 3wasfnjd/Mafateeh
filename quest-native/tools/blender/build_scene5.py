"""Scene 5 of the tabletop diorama: the guest majlis at evening.

A long open majlis (a riwaq): a back wall with a door, short side walls, a row of four
columns carrying a beam and a flat roof, and a raised floor (dakka) with red carpets and
cushions along the back. In front, a round paved forecourt with a fire pit in the middle
(the coffee is made there) and eight lantern posts round it; palms beyond. Level 5 is played
here: the lanterns and the guests are live (scripts/table/lantern_level.gd).

Reuses the helpers of build_scene1.py. Real metres; writes assets/world/scene5/scene5.glb.
Usage: python3 tools/blender/build_scene5.py [-- --render out_dir]

Layout (Godot x, z; Blender y = -z):
  majlis     back wall z -6.2, x -6 .. 6; columns along z -2.8; floor z -6 .. -2.6, 0.45 high
  forecourt  centred (0, 2.4), radius 4.6; fire pit at its centre (lantern_level.gd: FIRE)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_scene1 as b1  # noqa: E402  (resets Blender to an empty scene)

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from PIL import Image, ImageFilter  # noqa: E402

OUT = os.path.join(b1.ROOT, "assets", "world", "scene5")
os.makedirs(OUT, exist_ok=True)
b1.OUT = OUT
smooth, noise2, place, k, block = b1.smooth, b1.noise2, b1.place, b1.k, b1.block

FIRE = (0.0, 2.4)        # Godot x, z
COURT_R = 4.6
BACK_Z, FRONT_Z = -6.2, -2.8
FLOOR_H = 0.45


def g(x, z, h=0.0):
    return (x, -z, h)


def bake_ground(n=1024):
    S = b1.SIZE
    xs = (np.arange(n) + 0.5) / n * S - S / 2
    X, Y = np.meshgrid(xs, -xs)
    Z = -Y
    H = b1.dune_height(X, Y)
    grain = noise2(n, 51, (16, 32, 64, 128), 1.4)
    ripples = np.sin(X * 5 + Y * 7 + grain * 5) * 0.025 + 0.975
    lo, hi = np.array([0xd9, 0xa6, 0x5e], float), np.array([0xf4, 0xd3, 0x97], float)
    t = np.clip(H * 0.18 + grain * 0.22 + 0.25, 0.1, 0.85)[..., None]
    col = (lo * (1 - t) + hi * t) * ripples[..., None]
    gy, gx = np.gradient(H, S / n)
    col *= np.clip(1 + (-gx * 0.35 + gy * 0.25) * 0.6, 0.8, 1.12)[..., None]
    slabs = np.asarray(Image.open(os.path.join(b1.MOTRI, "slabs.png")).convert("L"), float) / 255
    sx = ((X / 5.71) % 1 * slabs.shape[1]).astype(int) % slabs.shape[1]
    sy = ((Y / 5.71) % 1 * slabs.shape[0]).astype(int) % slabs.shape[0]
    st = slabs[sy, sx]
    slab_col = np.array([0xa8, 0x77, 0x62], float) * (1 - st[..., None]) + np.array([0xff, 0xcf, 0x8b], float) * st[..., None]
    d = np.hypot(X - FIRE[0], Z - FIRE[1])
    court = smooth(COURT_R + 0.3, COURT_R - 0.3, d)
    front = smooth(0.0, 0.4, 6.3 - np.abs(X)) * smooth(0.0, 0.4, Z - BACK_Z) * smooth(0.0, 0.4, FRONT_Z + 1.2 - Z)
    m = (np.clip(court + front, 0, 1) * 0.94)[..., None]
    col = col * (1 - m) + slab_col * m
    # the ash and soot round the fire pit
    ash = smooth(1.3, 0.5, d)[..., None] * 0.55
    col = col * (1 - ash) + np.array([0x6a, 0x5a, 0x4c], float) * ash
    img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8)).filter(ImageFilter.SMOOTH)
    path_out = os.path.join(b1.TEX, "scene5_ground.jpg")
    img.save(path_out, quality=88)
    return path_out


def majlis():
    mud = b1.tile_mat()
    wood = b1.img_mat("scene5_wood", os.path.join(b1.TEX, "kit_lintel.jpg"), 0.85)
    # back wall: wall, door, wall (facing the forecourt), side walls
    for x, name in ((-4.0, "wall"), (0.0, "wall_door"), (4.0, "wall")):
        place(k(name), g(x, BACK_Z), 180)
    for x in (-6.0, 6.0):
        block("SideWall", (0.5, FRONT_Z - BACK_Z + 0.25, 3.2), g(x, (BACK_Z + FRONT_Z) / 2, 1.6), mud)
    # the raised floor, its step, carpets and cushions along the back
    block("Dakka", (11.5, 3.4, FLOOR_H), g(0, (BACK_Z + FRONT_Z) / 2 + 0.1, FLOOR_H / 2), mud)
    block("DakkaStep", (11.5, 0.45, FLOOR_H / 2), g(0, FRONT_Z + 0.35, FLOOR_H / 4), mud)
    carpet = bpy.data.materials.new("scene5_carpet")
    carpet.use_nodes = True
    carpet.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.42, 0.07, 0.05, 1)
    carpet.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    band = bpy.data.materials.new("scene5_band")
    band.use_nodes = True
    band.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.75, 0.52, 0.18, 1)
    cushion = bpy.data.materials.new("scene5_cushion")
    cushion.use_nodes = True
    cushion.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.2, 0.09, 0.06, 1)
    for x in (-3.6, 0.0, 3.6):
        block("Carpet", (3.3, 2.6, 0.03), g(x, -4.4, FLOOR_H + 0.015), carpet)
        block("CarpetBand", (3.34, 0.18, 0.032), g(x, -3.25, FLOOR_H + 0.016), band)
    for x in np.arange(-5.0, 5.1, 1.0):
        block("Cushion", (0.9, 0.3, 0.45), g(x, -5.75, FLOOR_H + 0.23), cushion)
    # four columns, a beam and the roof
    for x in (-4.5, -1.5, 1.5, 4.5):
        place(k("column"), g(x, FRONT_Z, FLOOR_H), 0)
    block("Beam", (12.4, 0.35, 0.3), g(0, FRONT_Z, 3.05), wood, uv_full=True)
    block("Roof", (12.6, 3.9, 0.25), g(0, (BACK_Z + FRONT_Z) / 2 - 0.1, 3.3), mud)
    for i in range(12):  # beam ends along the front of the roof
        block("RoofBeamEnd%d" % i, (0.1, 0.3, 0.1), g(-5.6 + i * 1.02, FRONT_Z + 0.25, 3.25), wood, uv_full=True)
    b1.crenels_on(0, -BACK_Z, 180, length=12.0, z=3.42)   # a crenellated parapet along the back


def fire_pit():
    stone = bpy.data.materials.new("scene5_stone")
    stone.use_nodes = True
    stone.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.3, 0.26, 0.22, 1)
    x, z = FIRE
    for i in range(12):
        a = i / 12 * 6.2832
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.22, location=g(x + np.cos(a) * 0.75, z + np.sin(a) * 0.75, 0.1))
        o = bpy.context.active_object
        o.scale = (1.0, 1.0, 0.6)
        o.data.materials.append(stone)


def life():
    palm = os.path.join(b1.ROOT, "assets", "world", "palm.glb")
    for x, z, s, yaw in ((-8.6, 1.0, 1.0, 30), (8.4, 0.2, 0.95, 120), (-9.0, 7.0, 0.9, 200),
                         (7.4, 7.8, 1.0, 300), (-9.6, -6.0, 0.9, 80), (9.8, -5.0, 0.85, 10)):
        place(palm, g(x, z), yaw, s)


def main():
    tex = bake_ground()
    b1.ground_mesh(tex)
    majlis()
    fire_pit()
    life()
    if b1.RENDER:
        b1.render(b1.RENDER)
    b1.export()


main()
