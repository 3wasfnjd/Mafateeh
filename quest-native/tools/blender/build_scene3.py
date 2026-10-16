"""Scene 3 of the tabletop diorama: a walled palm garden with an arish (palm-frond shade).

Different from scene 1 (courtyard house and tower) and scene 2 (lane, tall house and annex):
no house at all. A low crenellated garden wall with a gate, palms inside, and in the middle an
arish: four wooden posts, beams and a frond roof, where the old man sits. The dunes outside
are open. Level 3 is played here (scripts/table/falcon_level.gd adds the falcon's perches,
the key and the old man live).

Reuses the helpers of build_scene1.py. Real metres; writes assets/world/scene3/scene3.glb.
Usage: python3 tools/blender/build_scene3.py [-- --render out_dir]

Layout (Blender x, y; Godot x = x, z = -y):
  garden wall  x -6 .. 6, y -2 .. 6 (Godot z -6 .. 2); the gate in the front wall (y = -2)
  arish        centred (0, 3.4); the old man sits under it at (0, 3.2), facing the gate
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_scene1 as b1  # noqa: E402  (resets Blender to an empty scene)

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector as V  # noqa: E402
from PIL import Image, ImageFilter  # noqa: E402

OUT = os.path.join(b1.ROOT, "assets", "world", "scene3")
os.makedirs(OUT, exist_ok=True)
b1.OUT = OUT
smooth, noise2, place, k, block = b1.smooth, b1.noise2, b1.place, b1.k, b1.block

GX = 6.0                 # garden wall centrelines: x = +-GX
Y0, Y1 = -2.0, 6.0       # front and back wall centrelines (Blender y)
ARISH = (0.0, 3.4)       # centre of the shade (Blender x, y)


def bake_ground(n=1024):
    S = b1.SIZE
    xs = (np.arange(n) + 0.5) / n * S - S / 2
    X, Y = np.meshgrid(xs, -xs)
    H = b1.dune_height(X, Y)
    grain = noise2(n, 23, (16, 32, 64, 128), 1.4)
    ripples = np.sin(X * 6 + Y * 5 + grain * 5) * 0.025 + 0.975
    lo, hi = np.array([0xd9, 0xa6, 0x5e], float), np.array([0xf4, 0xd3, 0x97], float)
    t = np.clip(H * 0.18 + grain * 0.22 + 0.25, 0.1, 0.85)[..., None]
    col = (lo * (1 - t) + hi * t) * ripples[..., None]
    gy, gx = np.gradient(H, S / n)
    col *= np.clip(1 + (-gx * 0.35 + gy * 0.25) * 0.6, 0.8, 1.12)[..., None]
    # inside the wall: watered garden earth, darker, in soft furrows between the palms
    inside = smooth(0.0, 0.5, GX - 0.2 - np.abs(X)) * smooth(0.0, 0.5, Y - Y0 - 0.2) * smooth(0.0, 0.5, Y1 - 0.2 - Y)
    furrow = 0.92 + 0.08 * np.sin(X * 2.2)
    earth = np.array([0xb9, 0x8a, 0x5c], float) * (furrow * (0.9 + 0.2 * grain))[..., None]
    col = col * (1 - inside[..., None] * 0.85) + earth * inside[..., None] * 0.85
    # a slab path from the gate to the arish, and a paved floor under it (Motri slabs)
    slabs = np.asarray(Image.open(os.path.join(b1.MOTRI, "slabs.png")).convert("L"), float) / 255
    sx = ((X / 5.71) % 1 * slabs.shape[1]).astype(int) % slabs.shape[1]
    sy = ((Y / 5.71) % 1 * slabs.shape[0]).astype(int) % slabs.shape[0]
    st = slabs[sy, sx]
    path = smooth(0.0, 0.3, 0.9 - np.abs(X)) * smooth(0.0, 0.3, Y - Y0 + 0.4) * smooth(0.0, 0.3, ARISH[1] - Y)
    floor = smooth(0.0, 0.3, 2.1 - np.abs(X - ARISH[0])) * smooth(0.0, 0.3, 1.7 - np.abs(Y - ARISH[1]))
    m = (np.clip(path + floor, 0, 1) * 0.94)[..., None]
    slab_col = np.array([0xa8, 0x77, 0x62], float) * (1 - st[..., None]) + np.array([0xff, 0xcf, 0x8b], float) * st[..., None]
    col = col * (1 - m) + slab_col * m
    img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8)).filter(ImageFilter.SMOOTH)
    path_out = os.path.join(b1.TEX, "scene3_ground.jpg")
    img.save(path_out, quality=88)
    return path_out


def garden_wall():
    # the kit's corner piece is textured outside on one handedness only; the front right
    # corner (which would need it mirrored) is a plain block of mud instead
    corners = [((-GX, Y0), 0), ((-GX, Y1), -90), ((GX, Y1), 180)]
    block("CornerFill", (0.56, 0.56, b1.WALL_H + 0.04), (GX, Y0, b1.WALL_H / 2 + 0.02), b1.tile_mat())
    import math
    for (x, y), yaw in corners:
        place(k("wall_corner"), (x, y, 0), yaw)
        place(k("crenel_corner"), (x, y, b1.WALL_H), yaw)
        a = math.radians(yaw)
        for ax in (V((math.cos(a), math.sin(a), 0)), V((-math.sin(a), math.cos(a), 0))):
            for t in (1.15, 1.95):   # clear of the corner crenel's band
                place(k("crenel"), V((x, y, b1.WALL_H)) + ax * t, math.degrees(math.atan2(ax.y, ax.x)))
    # straight runs fill exactly the gaps the corner arms (2.25 m) leave: overlapping walls
    # share planes and flicker on the headset
    runs = [  # (x, y, yaw, length): front with its gate, back, left, right
        (-2.875, Y0, 0, 1.75), (3.875, Y0, 0, 3.75),
        (-1.875, Y1, 180, 3.75), (1.875, Y1, 180, 3.75),
        (-GX, 2.0, -90, 3.5),
        (GX, -0.375, 90, 2.75), (GX, 2.375, 90, 2.75)]
    place(k("wall_door"), (0.0, Y0, 0), 0)
    b1.crenels_on(0.0, Y0, 0)
    for x, y, yaw, length in runs:
        w = place(k("wall"), (x, y, 0), yaw)
        w.scale = (length / 4.0, 1.0, 1.0)
        b1.crenels_on(x, y, yaw, length=length)


def arish():
    """Four posts, two beams, rafters and a roof of palm fronds."""
    cx, cy = ARISH
    wood = b1.img_mat("scene3_wood", os.path.join(b1.TEX, "kit_lintel.jpg"), 0.85)
    for dx in (-1.7, 1.7):
        for dy in (-1.2, 1.2):
            block("ArishPost", (0.16, 0.16, 2.5), (cx + dx, cy + dy, 1.25), wood, uv_full=True)
        block("ArishBeam", (0.18, 2.8, 0.18), (cx + dx, cy, 2.55), wood, uv_full=True)
    for i in range(6):
        block("ArishRafter%d" % i, (3.8, 0.1, 0.08), (cx, cy - 1.25 + i * 0.5, 2.68), wood, uv_full=True)
    straw = bpy.data.materials.new("scene3_straw")
    straw.use_nodes = True
    straw.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.36, 0.25, 0.13, 1)
    straw.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    block("ArishRoof", (4.0, 3.0, 0.07), (cx, cy, 2.76), straw)


def life():
    palm = os.path.join(b1.ROOT, "assets", "world", "palm.glb")
    # inside the garden (kept clear of the falcon's perches), then a few outside
    # (only two inside, at the back: more hid the old man and the perches from the table)
    for x, y, s, yaw in ((-4.4, 4.6, 1.0, 20), (2.4, 5.0, 0.95, 260),
                         (-10.5, -2.5, 1.0, 300), (7.5, 10.0, 0.95, 90),
                         (-7.0, -9.5, 0.9, 200), (11.0, -6.0, 0.9, 30)):
        place(palm, (x, y, 0), yaw, s)


def main():
    tex = bake_ground()
    b1.ground_mesh(tex)
    garden_wall()
    arish()
    life()
    if b1.RENDER:
        b1.render(b1.RENDER)
    b1.export()


main()
