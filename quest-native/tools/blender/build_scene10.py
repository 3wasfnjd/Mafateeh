"""Scene 10 of the tabletop diorama: the family house's inner courtyard, the end of the journey.

The largest building: a square courtyard closed on four sides. At the back the house itself
(the vented-gable facade and a stepped facade, a riwaq of four columns before them under a
flat roof), stepped facades along both sides, and at the front a crenellated wall with the
gate. The courtyard is paved with Motri's slabs and laid with carpets in the middle, where
the grandfather's chest stands. The chest, the keepsakes, the lanterns and everyone who
comes to celebrate are live (scripts/table/chest_level.gd).

Reuses the helpers of build_scene1.py. Real metres; writes assets/world/scene10/scene10.glb.
Usage: python3 tools/blender/build_scene10.py [-- --render out_dir]

Layout (Godot x, z; Blender y = -z):
  courtyard   inside x -7 .. 7, z -6.0 .. 6.0; the gate in the front wall (z 6.25)
  house       facades at z -6.25; riwaq columns at z -3.6, roof over z -6.25 .. -3.4
  chest       (0, -0.4) on the carpets
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_scene1 as b1  # noqa: E402  (resets Blender to an empty scene)

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from PIL import Image, ImageFilter  # noqa: E402

OUT = os.path.join(b1.ROOT, "assets", "world", "scene10")
os.makedirs(OUT, exist_ok=True)
b1.OUT = OUT
smooth, noise2, place, k, block = b1.smooth, b1.noise2, b1.place, b1.k, b1.block

GX, GZ = 7.25, 6.25        # wall centrelines


def g(x, z, h=0.0):
    return (x, -z, h)


def bake_ground(n=1024):
    S = b1.SIZE
    xs = (np.arange(n) + 0.5) / n * S - S / 2
    X, Y = np.meshgrid(xs, -xs)
    Z = -Y
    H = b1.dune_height(X, Y)
    grain = noise2(n, 101, (16, 32, 64, 128), 1.4)
    ripples = np.sin(X * 6 + Y * 5 + grain * 5) * 0.025 + 0.975
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
    court = smooth(0.0, 0.3, GX - 0.2 - np.abs(X)) * smooth(0.0, 0.3, GZ - 0.2 - np.abs(Z))
    outside = smooth(0.0, 0.5, 2.0 - np.abs(X)) * smooth(0.0, 0.5, Z - GZ + 0.2) * smooth(0.0, 0.8, 10.5 - Z)  # the way to the gate
    m = (np.clip(court + outside, 0, 1) * 0.95)[..., None]
    col = col * (1 - m) + slab_col * m
    img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8)).filter(ImageFilter.SMOOTH)
    path_out = os.path.join(b1.TEX, "scene10_ground.jpg")
    img.save(path_out, quality=88)
    return path_out


def house():
    mud = b1.tile_mat()
    wood = b1.img_mat("scene10_wood", os.path.join(b1.TEX, "kit_lintel.jpg"), 0.85)
    door = b1.img_mat("scene10_door", os.path.join(b1.TEX, "house_door.png"), 0.8)
    # the house at the back: two facades to the courtyard, a door, a riwaq before them
    # (the 6 m facades and a plain stretch of wall fill the 14.5 m back without gaps)
    place(k("facade_steps"), g(-4.25, -GZ), 0)
    place(k("facade_gable"), g(1.75, -GZ), 0)
    block("BackWallEnd", (2.6, 0.46, 3.4), g(6.05, -GZ, 1.7), mud)
    block("HouseDoor", (1.4, 0.06, 2.2), g(1.75, -GZ + 0.27, 1.1), door, uv_full=True)
    block("HouseLintel", (1.9, 0.3, 0.16), g(1.75, -GZ + 0.3, 2.3), wood, uv_full=True)
    for x in (-5.4, -1.8, 1.8, 5.4):
        place(k("column"), g(x, -3.6), 0)
    block("RiwaqBeam", (12.6, 0.3, 0.22), g(0, -3.6, 2.95), wood, uv_full=True)
    block("RiwaqRoof", (13.0, 3.0, 0.2), g(0, -4.9, 3.15), mud)
    carpet = bpy.data.materials.new("scene10_carpet")
    carpet.use_nodes = True
    carpet.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.42, 0.07, 0.05, 1)
    block("RiwaqCarpet", (12.0, 2.1, 0.03), g(0, -4.85, 0.025), carpet)
    # stepped facades along the sides (their fronts to the courtyard)
    for z in (-3.25, 2.75):
        place(k("facade_steps"), g(-GX, z), 90)
        place(k("facade_steps"), g(GX, z), -90)
    for x in (-GX, GX):
        block("SideWallEnd", (0.44, 0.8, 2.74), g(x, 5.95, 1.37), mud)   # a hair inside the faces round it
    # the front wall and gate, with crenels
    for x, name in ((-4.0, "wall"), (0.0, "wall_door"), (4.0, "wall")):
        place(k(name), g(x, GZ), 0, 1.0)
        b1.crenels_on(x, -GZ, 0)
    for x in (-6.7, 6.7):
        block("FrontWallEnd", (1.5, 0.44, 2.8), g(x, GZ, 1.4), mud)
    # carpets in the middle of the courtyard
    band = bpy.data.materials.new("scene10_band")
    band.use_nodes = True
    band.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.75, 0.52, 0.18, 1)
    block("Carpet", (5.0, 3.6, 0.03), g(0, -0.4, 0.025), carpet)
    for z in (-1.95, 1.15):
        block("CarpetBand", (5.04, 0.2, 0.06), g(0, z, 0.03), band)


def life():
    palm = os.path.join(b1.ROOT, "assets", "world", "palm.glb")
    for x, z, s, yaw in ((-10.5, 4.0, 0.95, 20), (10.4, 3.6, 1.0, 150), (-6.4, 10.0, 0.9, 260), (6.8, 9.6, 0.95, 80),
                         (-10.6, -6.0, 0.9, 200), (10.6, -6.4, 0.95, 300)):
        place(palm, g(x, z), yaw, s)


def main():
    tex = bake_ground()
    b1.ground_mesh(tex)
    house()
    life()
    if b1.RENDER:
        b1.render(b1.RENDER)
    b1.export()


main()
