"""Mafateeh house kit, built to match the owner's sandstone tower.

Pieces (one GLB each in assets/world/house/, metres, origin on the ground, front = -Y in
Blender = +Z in Godot). Walls run 4 m along X so they snap edge to edge:
  tower        the owner's tower (art_source/world/sandstone_tower.usdz), 302k -> ~4.5k tris,
               red specks removed from its texture, 8 m tall
  wall         plain 4 m wall, tapering, soft corners
  wall_door    4 m wall with a painted wooden door (node "Door", hinged at its left edge),
               wooden lintel and a mud frame
  wall_window  4 m wall with two small shuttered windows and a row of triangle vents
  corner       corner pillar whose top rises into a soft horn, like the tower's corners
  crenels      stepped triangle crenellations for the top of a 4 m wall
  beams        roof beam ends and a wooden water spout, for the front of a 4 m wall
  stairs       mud stair up to the roof (2.8 m)
  bench        mud bench (dakka) to sit by the door
and house_sample.glb: all of the above put together as one courtyard house, with palms.

Usage: python3 tools/blender/build_house.py [-- out_dir|- [piece ...]]   (default pieces: tower wall)
Deterministic. Textures come from house_textures.py and are embedded (JPEG).
"""
import math
import os
import random
import sys

import bpy  # noqa: I001  (bpy must load before bmesh)
import bmesh
from mathutils import Matrix, Vector as V

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import house_textures as HT  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(ARGS[0]) if ARGS and ARGS[0] != "-" else os.path.join(ROOT, "assets", "world", "house")
TEX = os.path.join(ROOT, "art_source", "world", "textures")
TOWER_SRC = os.path.join(ROOT, "art_source", "world", "sandstone_tower.usdz")
PALM = os.path.join(ROOT, "assets", "world", "palm.glb")

WALL_LEN = 4.0
WALL_H = 4.2
WALL_T = 0.7       # thickness at the base
WALL_TAPER = 0.1   # each face leans in this much by the top
TOWER_H = 8.0

os.makedirs(OUT, exist_ok=True)
os.makedirs(TEX, exist_ok=True)
HT.write_all(TEX)
HT.sand().save(os.path.join(TEX, "house_sand.png"))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

# --- materials --------------------------------------------------------------------------
_mats = {}


def mat(name, img=None, color=(1, 1, 1), rough=0.95):
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = rough
    b.inputs["Base Color"].default_value = (*color, 1)
    if img:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(img if os.path.isabs(img) else os.path.join(TEX, img + ".png"))
        nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    _mats[name] = m
    return m


WALL = mat("house_wall", os.path.join(TEX, "house_wall.jpg"))
TOP = mat("house_top", "house_top")
WOOD = mat("house_wood", "house_wood", rough=0.85)
DOOR = mat("house_door", "house_door", rough=0.8)
DARK = mat("house_dark", None, (0.07, 0.045, 0.03))
SAND = mat("house_sand", "house_sand")


# --- mesh helpers -----------------------------------------------------------------------

def uv_box(bm, tile=2.0):
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for lp in f.loops:
            co = lp.vert.co
            u, v = (co.y, co.z) if ax == 0 else (co.x, co.z) if ax == 1 else (co.x, co.y)
            lp[uv].uv = (u / tile, v / tile)


def obj_from_bm(bm, name, m, smooth=False):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    sc.collection.objects.link(o)
    me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = smooth
    return o


def soften(o, subdiv=1, disp=0.04, seed=0, tile=2.0, top_mat=True):
    """Catmull-Clark once, a little cloud-noise displacement, world-scale box UVs, and the
    plaster-top material on faces that look up."""
    if subdiv:
        s = o.modifiers.new("s", "SUBSURF")
        s.levels = s.render_levels = subdiv
    if disp:
        tx = bpy.data.textures.new(o.name + "_n", "CLOUDS")
        tx.noise_scale = 0.8
        tx.noise_depth = 2
        d = o.modifiers.new("d", "DISPLACE")
        d.texture = tx
        d.strength = disp
        d.mid_level = 0.5
        d.texture_coords = "GLOBAL"
    dg = bpy.context.evaluated_depsgraph_get()
    new = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
    o.modifiers.clear()
    old = o.data
    o.data = new
    bpy.data.meshes.remove(old)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    uv_box(bm, tile)
    bm.to_mesh(o.data)
    bm.free()
    if top_mat:
        o.data.materials.append(TOP)
        for p in o.data.polygons:
            if p.normal.z > 0.75:
                p.material_index = 1
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def rounded_rect(sx, sy, r, step=0.4):
    hx, hy = sx / 2 - r, sy / 2 - r
    seq = []
    for ox, oy, a0 in ((hx, hy, 0), (-hx, hy, 90), (-hx, -hy, 180), (hx, -hy, 270)):
        for k in range(5):
            a = math.radians(a0 + k * 90 / 4)
            seq.append(V((ox + r * math.cos(a), oy + r * math.sin(a))))
    out = []
    for i in range(len(seq)):
        p, q = seq[i], seq[(i + 1) % len(seq)]
        n = max(1, int((q - p).length / step))
        for k in range(n):
            out.append(p.lerp(q, k / n))
    return out


def mud_solid(name, sx, sy, h, r=0.18, taper_x=0.0, taper_y=WALL_TAPER, top_round=0.08,
              horn=None, seed=0, disp=0.04, subdiv=1, step=0.4, levels=(0.0, 0.06, 0.3, 0.55, 0.8, 0.94, 1.0),
              tile=2.0):
    """A mud mass: rounded-rectangle footprint, faces leaning in by taper_*, soft rounded top.
    horn(x, y) -> extra height lets the top rise (corner horns)."""
    ring = rounded_rect(sx, sy, r, step)
    bm = bmesh.new()

    def at(p, lv, extra=0.0):
        ix = taper_x * lv + extra
        iy = taper_y * lv + extra
        x = p.x - math.copysign(min(ix, abs(p.x)), p.x) * min(1.0, abs(p.x) / (sx / 2))
        y = p.y - math.copysign(min(iy, abs(p.y)), p.y) * min(1.0, abs(p.y) / (sy / 2))
        return x, y

    rings = []
    for lv in levels:
        rings.append([bm.verts.new((*at(p, lv), lv * h + (horn(p.x, p.y) * lv ** 4 if horn else 0))) for p in ring])
    cap = [bm.verts.new((*at(p, 1.0, top_round * 1.2), h + top_round + (horn(p.x, p.y) if horn else 0))) for p in ring]
    rings.append(cap)
    n = len(ring)
    for a, b in zip(rings, rings[1:]):
        for i in range(n):
            bm.faces.new([a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]])
    bm.faces.new(cap)
    bm.faces.new(rings[0][::-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(bm, name, WALL)
    return soften(o, subdiv=subdiv, disp=disp, seed=seed, tile=tile)


def box(name, size, at, m, rot=None, bevel=0.0, tile=1.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=V(size), verts=bm.verts)
    if bevel:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=1, affect="EDGES")
    if rot:
        bmesh.ops.rotate(bm, verts=bm.verts, matrix=rot)
    bmesh.ops.translate(bm, verts=bm.verts, vec=V(at))
    uv_box(bm, tile)
    return obj_from_bm(bm, name, m)


def wall_face_y(z, t=WALL_T, h=WALL_H, taper=WALL_TAPER):
    """Y of the front (-Y) face of a wall at height z."""
    return -(t / 2 - taper * min(z, h) / h)


def frame(name, cx, z0, w, hgt, depth=0.1, border=0.12, t=WALL_T):
    """Raised mud frame around an opening, following the wall's lean."""
    y = wall_face_y(z0 + hgt / 2, t)
    bm = bmesh.new()
    outer = [(-w / 2 - border, 0), (w / 2 + border, 0), (w / 2 + border, hgt + border), (-w / 2 - border, hgt + border)]
    inner = [(-w / 2, 0), (w / 2, 0), (w / 2, hgt), (-w / 2, hgt)]
    fo = [bm.verts.new((cx + x, y - depth, z0 + zz)) for x, zz in outer]
    fi = [bm.verts.new((cx + x, y - depth, z0 + zz)) for x, zz in inner]
    bo = [bm.verts.new((cx + x, y + 0.02, z0 + zz)) for x, zz in outer]
    bi = [bm.verts.new((cx + x, y + 0.02, z0 + zz)) for x, zz in inner]
    for i in range(4):
        j = (i + 1) % 4
        if i != 0:  # no sill strip along the bottom of a door
            bm.faces.new([fo[i], fo[j], fi[j], fi[i]])
        bm.faces.new([bo[j], bo[i], fo[i], fo[j]])
        bm.faces.new([fi[i], fi[j], bi[j], bi[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    uv_box(bm, 2.0)
    o = obj_from_bm(bm, name, WALL)
    return soften(o, subdiv=0, disp=0.0, tile=2.0, top_mat=False)


def recess(name, cx, z0, w, hgt, t=WALL_T):
    """The dark inside of an opening (a shallow box set into the wall face)."""
    y = wall_face_y(z0 + hgt / 2, t)
    return box(name, (w, 0.16, hgt), (cx, y + 0.0, z0 + hgt / 2), DARK)


def tri_vent(cx, z, size=0.2, t=WALL_T):
    y = wall_face_y(z, t)
    bm = bmesh.new()
    pts = [(-size / 2, 0), (size / 2, 0), (0, size * 1.15)]
    f = [bm.verts.new((cx + x, y - 0.025, z + zz)) for x, zz in pts]
    b = [bm.verts.new((cx + x, y + 0.12, z + zz)) for x, zz in pts]
    bm.faces.new(f)
    bm.faces.new(b[::-1])
    for i in range(3):
        j = (i + 1) % 3
        bm.faces.new([f[i], f[j], b[j], b[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(bm, "vent", DARK)


def join(objs, name):
    objs = [o for o in objs if o is not None]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs, selected_objects=objs):
        bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name
    return objs[0]


# --- pieces -----------------------------------------------------------------------------

WALL_LEVELS = tuple(i / 12 for i in range(13))


def wall_horn(x, y):
    """The top of a wall rises a little towards both ends, like the tower's corners."""
    d = abs(x) - (WALL_LEN / 2 - 0.45)
    t = max(0.0, d / 0.45)
    return 0.2 * (3 * t * t - 2 * t * t * t)  # smooth rise


def mud_wall(name, seed):
    """Flat-faced mud wall (no subdivision, so it stays a wall and not a cushion), slightly
    wavy faces, soft vertical edges, ends that rise a little."""
    return mud_solid(name, WALL_LEN + 0.04, WALL_T, WALL_H, r=0.1, top_round=0.06, horn=wall_horn,
                     seed=seed, disp=0.06, subdiv=0, step=0.2, levels=WALL_LEVELS, tile=4.0)


def p_wall(seed=1):
    return mud_wall("wall", seed)


def p_wall_door():
    w, h = 1.25, 2.3
    parts = [mud_wall("wall_door", 2)]
    parts.append(recess("door_recess", 0, 0, w, h))
    parts.append(frame("door_frame", 0, 0, w, h, depth=0.08, border=0.16))
    y = wall_face_y(h)
    parts.append(box("lintel", (w + 0.7, 0.3, 0.2), (0, y - 0.1, h + 0.28), WOOD, bevel=0.02))
    for k in range(3):  # little triangle vents over the door
        parts.append(tri_vent((k - 1) * 0.32, h + 0.75, 0.2))
    body = join(parts, "WallDoor")
    # the door leaf, its own node so the game can swing it (hinge on the left)
    bm = bmesh.new()
    yd = wall_face_y(h / 2) + 0.01
    vs = [bm.verts.new(p) for p in ((0, 0, 0), (w, 0, 0), (w, 0, h), (0, 0, h))]
    f = bm.faces.new(vs)
    bmesh.ops.solidify(bm, geom=[f], thickness=0.06)
    uv = bm.loops.layers.uv.verify()
    for face in bm.faces:
        for lp in face.loops:
            lp[uv].uv = (lp.vert.co.x / w, lp.vert.co.z / h)
    door = obj_from_bm(bm, "Door", DOOR)
    door.location = (-w / 2, yd, 0.0)
    door.parent = body
    return body


def p_wall_window():
    parts = [mud_wall("wall_window", 3)]
    for cx in (-0.95, 0.95):
        w, h, z0 = 0.55, 0.65, 2.25
        parts.append(recess("win_recess", cx, z0, w, h))
        parts.append(frame("win_frame", cx, z0, w, h, depth=0.07, border=0.1))
        y = wall_face_y(z0 + h / 2)
        for sx in (-1, 1):  # two closed wooden shutters
            parts.append(box("shutter", (w / 2 - 0.02, 0.05, h - 0.04), (cx + sx * w / 4, y - 0.02, z0 + h / 2), WOOD, tile=0.6))
        parts.append(box("sill", (w + 0.3, 0.16, 0.08), (cx, y - 0.08, z0 - 0.02), WOOD))
    for k in range(5):
        parts.append(tri_vent(-1.6 + k * 0.8, 3.45, 0.2))
    return join(parts, "WallWindow")


def p_corner():
    def horn(x, y):
        return 0.55
    return mud_solid("corner", 1.25, 1.25, WALL_H + 0.25, r=0.3, taper_x=0.12, taper_y=0.12,
                     top_round=0.22, horn=horn, seed=4)


def p_crenels():
    parts = []
    count = 7
    for k in range(count):
        cx = -WALL_LEN / 2 + (k + 0.5) * WALL_LEN / count
        bm = bmesh.new()
        steps = ((0.46, 0.0), (0.32, 0.16), (0.18, 0.32))
        # step outline: up the left side, across the top, down the right
        outline = []
        for i, (w, z) in enumerate(steps):
            outline += [(-w / 2, z), (-w / 2, z + 0.16 if i < 2 else 0.48)]
        outline += [(0, 0.56)]
        for i, (w, z) in reversed(list(enumerate(steps))):
            outline += [(w / 2, z + 0.16 if i < 2 else 0.48), (w / 2, z)]
        fr = [bm.verts.new((cx + x, -0.11, z)) for x, z in outline]
        bk = [bm.verts.new((cx + x, 0.11, z)) for x, z in outline]
        bm.faces.new(fr)
        bm.faces.new(bk[::-1])
        for i in range(len(outline)):
            j = (i + 1) % len(outline)
            bm.faces.new([fr[i], fr[j], bk[j], bk[i]])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        o = obj_from_bm(bm, "crenel", WALL)
        parts.append(soften(o, subdiv=0, disp=0.0, tile=2.0, top_mat=False))
    c = join(parts, "Crenels")
    for p in c.data.polygons:
        p.use_smooth = False
    return c


def p_beams():
    parts = []
    z = 3.55
    y = wall_face_y(z)
    for k in range(7):
        x = -1.8 + k * 0.6
        if abs(x - 0.6) < 0.05:
            continue
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=7, radius1=0.075, radius2=0.07, depth=0.5)
        bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.pi / 2, 3, "X"))
        bmesh.ops.translate(bm, verts=bm.verts, vec=(x, y - 0.15, z + 0.02 * math.sin(k * 2.1)))
        uv_box(bm, 0.5)
        parts.append(obj_from_bm(bm, "beam", WOOD))
    # water spout: a wooden trough leaning out and down
    bm = bmesh.new()
    pts = [(-0.1, 0.0), (-0.1, 0.12), (-0.06, 0.12), (-0.06, 0.04), (0.06, 0.04), (0.06, 0.12), (0.1, 0.12), (0.1, 0.0)]
    L = 0.9
    a = [bm.verts.new((0.6 + x, y + 0.1, z + zz)) for x, zz in pts]
    b = [bm.verts.new((0.6 + x, y + 0.1 - L, z + zz - 0.14)) for x, zz in pts]
    bm.faces.new(a[::-1])
    bm.faces.new(b)
    for i in range(len(pts)):
        j = (i + 1) % len(pts)
        bm.faces.new([a[i], a[j], b[j], b[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    uv_box(bm, 0.5)
    parts.append(obj_from_bm(bm, "spout", WOOD))
    return join(parts, "Beams")


def p_stairs():
    """Rises along +X: 8 steps of 0.35 m over 3.6 m, 1.0 m wide (Y), solid underneath."""
    steps, rise, run, wid = 8, 0.35, 0.45, 1.0
    bm = bmesh.new()
    prof = [(0.0, 0.0)]
    for i in range(steps):
        prof += [(i * run, (i + 1) * rise), ((i + 1) * run, (i + 1) * rise)]
    prof += [(steps * run, 0.0)]
    x0 = -steps * run / 2
    rnd = random.Random(8)
    fr = [bm.verts.new((x0 + x + rnd.uniform(-0.02, 0.02), -wid / 2, z)) for x, z in prof]
    bk = [bm.verts.new((x0 + x + rnd.uniform(-0.02, 0.02), wid / 2, z)) for x, z in prof]
    bm.faces.new(fr)
    bm.faces.new(bk[::-1])
    for i in range(len(prof)):
        j = (i + 1) % len(prof)
        bm.faces.new([fr[i], fr[j], bk[j], bk[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.035, segments=1, affect="EDGES")
    o = obj_from_bm(bm, "Stairs", WALL)
    return soften(o, subdiv=0, disp=0.015, tile=2.0)


def p_bench():
    return mud_solid("Bench", 2.0, 0.6, 0.42, r=0.18, taper_y=0.03, top_round=0.04, seed=6, disp=0.02)


def p_tower():
    bpy.ops.wm.usd_import(filepath=TOWER_SRC)
    for o in list(bpy.data.objects):
        if o.type == "EMPTY":
            bpy.data.objects.remove(o)
    o = next(x for x in bpy.data.objects if x.type == "MESH" and x.name.startswith("tripo"))
    o.name = "Tower"
    m = o.modifiers.new("d", "DECIMATE")
    m.ratio = 0.015
    dg = bpy.context.evaluated_depsgraph_get()
    new = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
    o.modifiers.clear()
    old = o.data
    o.data = new
    bpy.data.meshes.remove(old)
    # size, and stand it on the ground with its centre at the origin
    lo = V((min(v.co[i] for v in o.data.vertices) for i in range(3)))
    hi = V((max(v.co[i] for v in o.data.vertices) for i in range(3)))
    k = TOWER_H / (hi.z - lo.z)
    c = (lo + hi) / 2
    o.data.transform(Matrix.Scale(k, 4) @ Matrix.Translation((-c.x, -c.y, -lo.z)))
    o.location = (0, 0, 0)
    # cleaned texture
    mtl = o.data.materials[0]
    mtl.name = "tower"
    img = next(n.image for n in mtl.node_tree.nodes if n.type == "TEX_IMAGE" and n.image)
    src = bpy.path.abspath(img.filepath)
    if not os.path.exists(src):
        img.filepath_raw = os.path.join(TEX, "tower_raw.png")
        img.file_format = "PNG"
        img.save()
        src = img.filepath_raw
    dst = os.path.join(TEX, "tower_basecolor.jpg")
    fixed = HT.clean_tower_texture(src, dst)
    print("tower: cleaned", fixed, "red pixels")
    img2 = bpy.data.images.load(dst)
    for n in mtl.node_tree.nodes:
        if n.type == "TEX_IMAGE":
            n.image = img2
        if n.type == "BSDF_PRINCIPLED":
            n.inputs["Roughness"].default_value = 1.0
            n.inputs["Metallic"].default_value = 0.0
    for p in o.data.polygons:
        p.use_smooth = True
    print("tower:", len(o.data.polygons), "faces, size", tuple(round(x * k, 2) for x in (hi - lo)))
    return o


# --- export -----------------------------------------------------------------------------

def tris(objs):
    t = 0
    for o in objs:
        if o.type == "MESH":
            o.data.calc_loop_triangles()
            t += len(o.data.loop_triangles)
    return t


def export(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    allo = []
    for o in objs:
        allo.append(o)
        allo += list(o.children_recursive)
    for o in allo:
        o.select_set(True)
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_materials="EXPORT", export_image_format="JPEG", export_jpeg_quality=85,
                              export_apply=False)
    print("exported", name, os.path.getsize(path) // 1024, "KB", tris(allo), "tris")


def hide_all():
    for o in bpy.data.objects:
        o.hide_set(True)
        o.hide_render = True


def place(src, at, yaw=0.0, name=None):
    """A linked copy (shares the mesh) of a piece and its children."""
    def dup(o, parent):
        c = o.copy()
        sc.collection.objects.link(c)
        c.hide_set(False)
        c.hide_render = False
        if parent:
            c.parent = parent
        for ch in o.children:
            dup(ch, c)
        return c
    c = dup(src, None)
    c.location = at
    c.rotation_euler = (0, 0, math.radians(yaw))
    if name:
        c.name = name
    return c


def main():
    """Builds the pieces named on the command line (default: tower and wall) and a small
    preview scene, house_preview.glb, with them standing side by side on sand."""
    names = [a for a in ARGS[1:] if not a.startswith("--")] or ["tower", "wall"]
    makers = {"wall": p_wall, "wall_door": p_wall_door, "wall_window": p_wall_window,
              "corner": p_corner, "crenels": p_crenels, "beams": p_beams,
              "stairs": p_stairs, "bench": p_bench, "tower": p_tower}
    pieces = {}
    for name in names:
        o = makers[name]()
        pieces[name] = o
        export([o], name)
        o.hide_set(True)
        o.hide_render = True
    placed = []
    ground = bmesh.new()
    bmesh.ops.create_grid(ground, x_segments=1, y_segments=1, size=12)
    uv_box(ground, 4.0)
    placed.append(obj_from_bm(ground, "Ground", SAND))
    if "tower" in pieces:  # the wall runs into the tower's left side, as on a house front
        placed.append(place(pieces["tower"], (2.5, 0, 0)))
    x = 0.0 - WALL_LEN / 2
    for name in names:
        if name != "tower":
            placed.append(place(pieces[name], (x, -1.0, 0)))
            x -= WALL_LEN
    export(placed, "house_preview")


main()
