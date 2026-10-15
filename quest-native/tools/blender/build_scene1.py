"""Scene 1 of the tabletop diorama: a Diriyah courtyard house on a round sand island.

Built from:
  assets/world/kit/*      the Diriyah kit (tools/blender/build_diriyah_kit.py)
  assets/world/house/tower.glb   the owner's tower
  assets/world/props/*    camels, tent, sheep, hens, crate, lantern (tools/blender/import_motri.py)
  assets/world/palm.glb   low-poly palm
  assets/character/shaib.glb, assets/creatures/cat.glb
and a ground baked here: sand dunes round the edge (after Motri's DunesField: ridge
gaussians, sand from #d9a65e to #f4d397 with ripples), slab patches fading into the sand in
the courtyard (Motri's floor: slabs texture x noise) and stone-paved paths.

Real metres; the game scales the whole diorama down onto a table. Front (-Y in Blender) is
the side the player first sees. Writes assets/world/scene1/scene1.glb.
Usage: python3 tools/blender/build_scene1.py [-- --render out_dir]
"""
import math
import os
import sys

import bpy  # noqa: I001
import bmesh
import numpy as np
from mathutils import Matrix, Vector as V
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
A = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RENDER = A[A.index("--render") + 1] if "--render" in A else ""
KIT = os.path.join(ROOT, "assets", "world", "kit")
PROPS = os.path.join(ROOT, "assets", "world", "props")
TEX = os.path.join(ROOT, "art_source", "world", "textures")
MOTRI = os.path.join(ROOT, "art_source", "world", "motri")
OUT = os.path.join(ROOT, "assets", "world", "scene1")
os.makedirs(OUT, exist_ok=True)

ISLAND_R = 16.5      # radius of the sand island
SIZE = 34.0          # ground texture covers SIZE x SIZE metres
GX, GY = 8.25, 6.25  # compound wall centrelines: x = +-GX, y = +-GY
WALL_H = 2.8

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene


def smooth(a, b, v):
    t = np.clip((v - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def noise2(n, seed, octaves=(4, 8, 16, 32), falloff=1.6):
    r = np.random.default_rng(seed)
    acc = np.zeros((n, n))
    for o, s in enumerate(octaves):
        g = Image.fromarray((r.random((s, s)) * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)
        acc += np.asarray(g, float) / 255 / falloff ** o
    acc -= acc.min()
    return acc / acc.max()


# --- ground --------------------------------------------------------------------------------

def dune_height(x, y):
    """Dunes round the rim; low at the front so the house stays in view."""
    r = np.hypot(x, y)
    th = np.arctan2(y, x)
    w = smooth(11.5, 15.8, r)
    back = 0.3 + 0.7 * smooth(-0.35, 0.7, np.sin(th))       # +Y (back) is higher
    ridges = 1.3 + 0.75 * np.sin(3 * th + 0.7) + 0.45 * np.sin(7 * th + 2.1) + 0.25 * np.sin(13 * th)
    h = w * back * np.maximum(ridges, 0.2) * 2.1
    return h


def bake_ground(n=1024):
    xs = (np.arange(n) + 0.5) / n * SIZE - SIZE / 2
    X, Y = np.meshgrid(xs, -xs)          # row 0 = +Y (image top = back)
    H = dune_height(X, Y)
    grain = noise2(n, 3, (16, 32, 64, 128), 1.4)
    ripples = np.sin(X * 9 + Y * 1.5 + grain * 5) * 0.025 + 0.975
    lo, hi = np.array([0xd9, 0xa6, 0x5e], float), np.array([0xf4, 0xd3, 0x97], float)
    t = np.clip(H * 0.18 + grain * 0.22 + 0.25, 0.1, 0.85)[..., None]
    col = (lo * (1 - t) + hi * t) * ripples[..., None]
    # gentle slope shading (light from the front-left)
    gy, gx = np.gradient(H, SIZE / n)
    shade = np.clip(1 + (-gx * 0.35 + gy * 0.25) * 0.6, 0.8, 1.12)
    col *= shade[..., None]
    # courtyard: compacted earth, with slabs showing in patches (Motri floor)
    court = smooth(0.0, 0.6, GX - 0.2 - np.abs(X)) * smooth(0.0, 0.6, GY - 0.2 - np.abs(Y))
    earth = np.array([0xd3, 0xa8, 0x72], float)
    col = col * (1 - court[..., None] * 0.6) + earth * court[..., None] * 0.6
    slabs = np.asarray(Image.open(os.path.join(MOTRI, "slabs.png")).convert("L"), float) / 255
    sx = ((X / 5.71) % 1 * slabs.shape[1]).astype(int) % slabs.shape[1]
    sy = ((Y / 5.71) % 1 * slabs.shape[0]).astype(int) % slabs.shape[0]
    st = slabs[sy, sx]
    patch = noise2(n, 7, (6, 12, 24), 1.7)
    apron = smooth(0, 1.5, 3.2 - np.hypot(X - 0.0, (Y + GY + 2.2) * 0.8))  # outside the gate
    slab_mask = np.clip(court * smooth(0.5, 0.68, patch) + apron * smooth(0.35, 0.6, patch), 0, 1) * 0.92
    slab_col = np.array([0xa8, 0x77, 0x62], float) * (1 - st[..., None]) + np.array([0xff, 0xcf, 0x8b], float) * st[..., None]
    col = col * (1 - slab_mask[..., None]) + slab_col * slab_mask[..., None]
    # stone-paved paths: gate -> house door, and gate -> front edge
    pave = np.asarray(Image.open(os.path.join(MOTRI, "stone-paving.png")).convert("RGB"), float)
    px = ((X / 2.4) % 1 * pave.shape[1]).astype(int) % pave.shape[1]
    py = ((Y / 2.4) % 1 * pave.shape[0]).astype(int) % pave.shape[0]
    pv = pave[py, px]
    edge = (noise2(n, 11, (32, 64), 1.3) - 0.5) * 0.35
    inner = smooth(0.0, 0.25, 0.85 + edge - np.abs(X)) * smooth(0, 0.2, Y + GY + 0.3) * smooth(0, 0.2, -2.0 - Y)
    outer = smooth(0.0, 0.3, 1.0 + edge - np.abs(X)) * smooth(0, 0.2, -GY + 0.2 - Y) * smooth(0, 2.0, Y + 14.5)
    path = np.clip(inner + outer, 0, 1)
    col = col * (1 - path[..., None]) + pv * path[..., None]
    img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8)).filter(ImageFilter.SMOOTH)
    path_out = os.path.join(TEX, "scene1_ground.jpg")
    img.save(path_out, quality=88)
    return path_out


def ground_mesh(tex_path, ring_step=0.45, seg=120):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.verify()
    rings = [[bm.verts.new((0, 0, float(dune_height(np.array(0.0), np.array(0.0)))))]]
    nr = int(math.ceil(ISLAND_R / ring_step))
    for k in range(1, nr + 1):
        r = min(ISLAND_R, k * ring_step)
        ring = []
        for q in range(seg):
            a = q / seg * math.tau
            x, y = math.cos(a) * r, math.sin(a) * r
            ring.append(bm.verts.new((x, y, float(dune_height(np.array(x), np.array(y))))))
        rings.append(ring)
    for q in range(seg):
        bm.faces.new([rings[0][0], rings[1][q], rings[1][(q + 1) % seg]])
    for k in range(1, nr):
        a, b = rings[k], rings[k + 1]
        for q in range(seg):
            bm.faces.new([a[q], b[q], b[(q + 1) % seg], a[(q + 1) % seg]])
    for f in bm.faces:
        for lp in f.loops:
            c = lp.vert.co
            lp[uv].uv = ((c.x + SIZE / 2) / SIZE, (c.y + SIZE / 2) / SIZE)
    bm.normal_update()
    me = bpy.data.meshes.new("Ground")
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("Ground", me)
    sc.collection.objects.link(o)
    m = bpy.data.materials.new("scene1_ground")
    m.use_nodes = True
    nt = m.node_tree
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = bpy.data.images.load(tex_path)
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 1.0
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = True
    # plinth: a skirt from the island's rim down to the table
    bm = bmesh.new()
    top, bot = [], []
    for k in range(seg):
        a = k / seg * math.tau
        x, y = math.cos(a) * ISLAND_R, math.sin(a) * ISLAND_R
        z = float(dune_height(np.array(x), np.array(y)))
        top.append(bm.verts.new((x, y, z)))
        bot.append(bm.verts.new((x * 0.985, y * 0.985, -0.7)))
    for k in range(seg):
        k2 = (k + 1) % seg
        bm.faces.new([bot[k], bot[k2], top[k2], top[k]])
    me2 = bpy.data.meshes.new("Plinth")
    bm.to_mesh(me2)
    bm.free()
    p = bpy.data.objects.new("Plinth", me2)
    sc.collection.objects.link(p)
    pm = bpy.data.materials.new("scene1_plinth")
    pm.use_nodes = True
    pm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.42, 0.26, 0.14, 1)
    pm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    me2.materials.append(pm)
    return o


# --- placing pieces ------------------------------------------------------------------------
_lib = {}


def piece(path):
    """Imports a GLB once into a hidden library collection; returns its root objects."""
    if path in _lib:
        return _lib[path]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    lib = bpy.data.collections.get("lib") or bpy.data.collections.new("lib")
    for o in new:
        for c in o.users_collection:
            c.objects.unlink(o)
        lib.objects.link(o)
    _lib[path] = [o for o in new if o.parent is None]
    return _lib[path]


def place(path, at, yaw_deg=0.0, scale=1.0, name=None):
    roots = piece(path)
    group = bpy.data.objects.new(name or os.path.basename(path)[:-4], None)
    sc.collection.objects.link(group)

    def dup(o, parent):
        c = o.copy()  # shares the mesh data
        sc.collection.objects.link(c)
        c.parent = parent
        for ch in o.children:
            dup(ch, c)
    for r in roots:
        dup(r, group)
    group.location = at
    group.rotation_euler = (0, 0, math.radians(yaw_deg))
    group.scale = (scale, scale, scale)
    return group


def k(name):
    return os.path.join(KIT, name + ".glb")


def p(name):
    return os.path.join(PROPS, name + ".glb")


def crenels_on(cx, cy, yaw, length=4.0, z=WALL_H, step=0.8, skip_ends=False):
    a = math.radians(yaw)
    d = V((math.cos(a), math.sin(a), 0))
    n = int(round(length / step))
    for i in range(n):
        t = -length / 2 + (i + 0.5) * step
        if skip_ends and (i == 0 or i == n - 1):
            continue
        place(k("crenel"), V((cx, cy, z)) + d * t, yaw)


def compound():
    # corners: (position, yaw) so the corner's arms run along the two walls
    corners = [((-GX, -GY), 0), ((-GX, GY), -90), ((GX, GY), 180)]
    for (x, y), yaw in corners:
        place(k("wall_corner"), (x, y, 0), yaw)
        place(k("crenel_corner"), (x, y, WALL_H), yaw)
        a = math.radians(yaw)
        for ax in (V((math.cos(a), math.sin(a), 0)), V((-math.sin(a), math.cos(a), 0))):
            for t in (0.95, 1.75):
                place(k("crenel"), V((x, y, WALL_H)) + ax * t, math.degrees(math.atan2(ax.y, ax.x)))
    # front (-Y): wall, door, wall; tower on the right corner
    for x, name in ((-4.0, "wall"), (0.0, "wall_door"), (4.0, "wall")):
        place(k(name), (x, -GY, 0), 0)
        crenels_on(x, -GY, 0)
    place(os.path.join(ROOT, "assets", "world", "house", "tower.glb"), (GX, -GY, 0), 180)
    # sides: front of each piece faces outwards
    for y in (-2.0, 2.0):
        place(k("wall"), (-GX, y, 0), -90)
        crenels_on(-GX, y, -90)
        place(k("wall"), (GX, y, 0), 90)
        crenels_on(GX, y, 90)
    # back: the house stands against the middle of it
    for x in (-4.0, 0.0, 4.0):
        place(k("wall"), (x, GY, 0), 180)
        crenels_on(x, GY, 180)


def tile_mat():
    m = bpy.data.materials.get("scene1_mud")
    if m:
        return m
    m = bpy.data.materials.new("scene1_mud")
    m.use_nodes = True
    nt = m.node_tree
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = bpy.data.images.load(os.path.join(TEX, "kit_mud_tile.jpg"))
    nt.links.new(t.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    nt.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    return m


def img_mat(name, path, rough=0.9):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = bpy.data.images.load(path)
    nt.links.new(t.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    nt.nodes["Principled BSDF"].inputs["Roughness"].default_value = rough
    return m


def block(name, size, at, m, uv_tile=2.0, uv_full=False):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    bmesh.ops.translate(bm, verts=bm.verts, vec=at)
    bm.normal_update()
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        ax = max(range(3), key=lambda i: abs(f.normal[i]))
        for lp in f.loops:
            c = lp.vert.co - V(at) + V(size) / 2
            u, v = (c.y / size[1], c.z / size[2]) if ax == 0 else (c.x / size[0], c.z / size[2]) if ax == 1 else (c.x / size[0], c.y / size[1])
            if not uv_full:
                cw = lp.vert.co
                u, v = (cw.y, cw.z) if ax == 0 else (cw.x, cw.z) if ax == 1 else (cw.x, cw.y)
                u, v = u / uv_tile, v / uv_tile
            lp[uv].uv = (u, v)
    dead = [f for f in bm.faces if f.normal.z < -0.9 and f.calc_center_median().z < 0.01]
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    sc.collection.objects.link(o)
    me.materials.append(m)
    return o


def house():
    # front facade (vented gable) and stepped sides; the compound's back wall is its back
    place(k("facade_gable"), (0, 0.25, 0), 0)
    place(k("facade_steps"), (-3.0, 3.25, 0), -90)
    place(k("facade_steps"), (3.0, 3.25, 0), -90)
    block("Roof", (5.5, 5.75, 0.2), (0, 3.375, 2.95), tile_mat())
    door = img_mat("scene1_door", os.path.join(TEX, "house_door.png"), 0.8)
    block("HouseDoor", (1.0, 0.06, 1.9), (0, -0.02, 0.95), door, uv_full=True)
    wood = img_mat("scene1_wood", os.path.join(TEX, "kit_lintel.jpg"), 0.85)
    block("HouseLintel", (1.5, 0.3, 0.16), (0, -0.05, 2.0), wood, uv_full=True)
    # shaded porch: two columns, a beam and a palm-frond roof
    for x in (-2.3, 2.3):
        place(k("column"), (x, -1.7, 0), 0)
    block("PorchBeam", (5.2, 0.28, 0.2), (0, -1.7, 2.92), wood, uv_full=True)
    for i in range(7):  # rafters from the beam to the facade
        block("Rafter%d" % i, (0.12, 1.9, 0.1), (-2.4 + i * 0.8, -0.8, 3.07), wood, uv_full=True)
    straw = bpy.data.materials.new("scene1_straw")
    straw.use_nodes = True
    straw.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.55, 0.40, 0.20, 1)
    straw.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    block("PorchRoof", (5.4, 2.1, 0.06), (0, -0.8, 3.15), straw)


def life():
    # camel camp outside, on the left
    place(p("tent"), (-12.4, 1.2, 0), -90)
    place(p("camel_standing"), (-11.6, -4.6, 0), 35)
    place(p("camel_calf"), (-10.2, -6.0, 0), 60)
    place(p("camel_kneeling"), (-13.3, 5.4, 0), -20)
    place(p("camel_standing"), (-14.2, -1.8, 0), 100)
    # sheep on the right
    for x, y, yaw in ((11.6, 2.6, 10), (12.6, 4.0, -40), (13.2, 1.4, 70), (11.2, 5.2, 150)):
        place(p("sheep"), (x, y, 0), yaw)
    # hens in the courtyard
    for x, y, yaw, kind in ((-4.6, -2.6, 20, "hen"), (-3.8, -3.6, 120, "hen"), (-5.4, -3.4, -60, "rooster")):
        place(p(kind), (x, y, 0), yaw)
    # crates and lanterns
    place(p("crate"), (5.4, 2.6, 0), 10)
    place(p("crate"), (6.2, 2.9, 0), -15)
    place(p("crate"), (5.8, 2.75, 0.8), 30)
    for x in (-1.4, 1.4):
        place(p("lantern"), (x, -GY - 0.7, 0), 0)
    place(p("lantern"), (-1.0, -0.6, 0), 0)
    # palms
    palm = os.path.join(ROOT, "assets", "world", "palm.glb")
    for x, y, s, yaw in ((-6.4, -3.8, 0.8, 10), (-11.0, -10.0, 1.0, 30), (11.5, 9.0, 1.05, 200),
                         (-12.8, 9.4, 0.95, 120), (6.5, -12.0, 0.9, 300), (-4.0, 12.2, 0.9, 0)):
        place(palm, (x, y, 0), yaw, s)
    # the old man and his cat, just inside the gate
    rigged(os.path.join(ROOT, "assets", "character", "shaib.glb"), (0.9, -4.4, 0), 0, "Shaib")
    rigged(os.path.join(ROOT, "assets", "creatures", "cat.glb"), (1.75, -4.9, 0), 25, "Cat", height=0.3)


def rigged(path, at, yaw_deg, name, height=None):
    """Rigged characters are imported as they are and moved by their root."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        if o.animation_data:
            o.animation_data.action = None
    root = bpy.data.objects.new(name, None)
    sc.collection.objects.link(root)
    for o in new:
        if o.parent is None:
            o.parent = root
    if height:
        bpy.context.view_layer.update()
        zs = [(m.matrix_world @ V(c)).z for m in new if m.type == "MESH" for c in m.bound_box]
        root.scale = [height / (max(zs) - min(zs))] * 3
    root.location = at
    root.rotation_euler = (0, 0, math.radians(yaw_deg))
    return root


def render(out):
    os.makedirs(out, exist_ok=True)
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.78, 0.80, 0.82, 1)
    bg.inputs["Strength"].default_value = 1.0
    sun = bpy.data.lights.new("s", "SUN")
    sun.energy = 2.6
    sun.angle = 0.3
    so = bpy.data.objects.new("s", sun)
    sc.collection.objects.link(so)
    so.rotation_euler = (math.radians(42), 0, math.radians(-38))
    # the table under the island
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=60)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, -0.7))
    me = bpy.data.meshes.new("Table")
    bm.to_mesh(me)
    t = bpy.data.objects.new("Table", me)
    sc.collection.objects.link(t)
    tm = bpy.data.materials.new("table")
    tm.use_nodes = True
    tm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.36, 0.25, 0.17, 1)
    me.materials.append(tm)
    cam = bpy.data.cameras.new("c")
    co = bpy.data.objects.new("c", cam)
    sc.collection.objects.link(co)
    sc.camera = co
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 32
    sc.render.resolution_x, sc.render.resolution_y = 1280, 860
    sc.view_settings.view_transform = "Standard"
    shots = {"table": ((0, -36, 26), (0, -1, 0), 35), "close": ((-9, -19, 8.5), (0, -2, 2.0), 30),
             "top": ((0, -6, 44), (0, -0.5, 0), 35), "side": ((30, -16, 15), (0, 0, 1.0), 35)}
    for name, (loc, tgt, lens) in shots.items():
        cam.lens = lens
        co.location = loc
        co.rotation_euler = (V(tgt) - V(loc)).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(out, "scene1_%s.png" % name)
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(t)
    bpy.data.objects.remove(co)
    bpy.data.objects.remove(so)


def export():
    lib = bpy.data.collections.get("lib")
    bpy.ops.object.select_all(action="DESELECT")
    for o in sc.collection.all_objects:
        if lib and o.name in lib.objects:
            continue
        o.select_set(True)
    path = os.path.join(OUT, "scene1.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_materials="EXPORT", export_vertex_color="MATERIAL", export_image_format="AUTO",
                              export_animations=False, export_skins=True)
    tris = 0
    for o in bpy.context.selected_objects:
        if o.type == "MESH":
            o.data.calc_loop_triangles()
            tris += len(o.data.loop_triangles)
    print("exported scene1", os.path.getsize(path) // 1024, "KB", tris, "tris")


def main():
    tex = bake_ground()
    ground_mesh(tex)
    compound()
    house()
    life()
    if RENDER:
        render(RENDER)
    export()


main()
