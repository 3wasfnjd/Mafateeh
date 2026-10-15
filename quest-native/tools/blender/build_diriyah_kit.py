"""Diriyah building kit made from the owner's reference renders (art_source/world/kit_refs/p1-p8).

Each wall's front is a straight-on texture rectified from the reference image
(tools/art/rectify.py); the top, ends and small pieces use a tileable plaster made from the
same image, so everything is the same mud. The crenellations and column are mud, not white
(the owner's choice). Sizes in metres; origin on the ground at the piece's centre;
front = -Y in Blender (+Z in Godot). Textures are small (the game is a tabletop diorama).

  wall          p1  plain wall, 4 x 2.8 m
  wall_corner   p2  L corner: arms along +X and +Y, each reaching 2.25 m from the corner
  wall_door     p3  wall with an opening and a wooden lintel
  facade_gable  p4  6 m house front, curved top, vent columns (real holes), windows
  facade_steps  p8  6 m house side, stepped top, diamond vents
  crenel        p5  stepped crenellation
  crenel_corner p6  corner crenellation (stepped pyramid)
  column        p7  square column with a stepped capital

Usage: python3 tools/blender/build_diriyah_kit.py [-- out_dir]
"""
import math
import os
import sys

import bpy  # noqa: I001  (bpy before bmesh)
import bmesh
import numpy as np
from mathutils import Vector as V
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "art"))
from rectify import rectify  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
REFS = os.path.join(ROOT, "art_source", "world", "kit_refs")
TEX = os.path.join(ROOT, "art_source", "world", "textures")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(ARGS[0]) if ARGS else os.path.join(ROOT, "assets", "world", "kit")
os.makedirs(TEX, exist_ok=True)
os.makedirs(OUT, exist_ok=True)

T = 0.5          # wall thickness
WALL_H = 2.8     # courtyard walls
PPM = 128        # texture pixels per metre (4 m wall -> 512 px)

# Reference rectangles on each image: TL, TR, BR, BL (pixels), width, height of that rectangle (m)
FACES = {
    "p1": ([(52, 242), (1140, 322), (1140, 1160), (52, 950)], 4.0, 2.8, 2.8),
    "p3": ([(50, 232), (1140, 318), (1140, 1162), (50, 950)], 4.0, 2.8, 2.8),
    # gable / stepped fronts: the reference height is the row of small vents
    "p4": ([(46, 597), (1172, 615), (1172, 1200), (46, 1021)], 6.0, 2.85, 6.9),
    "p8": ([(52, 579), (1172, 612), (1172, 1201), (52, 1030)], 6.0, 2.85, 6.9),
    # the two inside faces of the L corner
    "p2a": ([(140, 362), (628, 252), (628, 842), (140, 1066)], 2.0, 2.8, 2.8),
    "p2b": ([(628, 252), (1140, 372), (1140, 1074), (628, 842)], 2.0, 2.8, 2.8),
}


def ref(name):
    return Image.open(os.path.join(REFS, name + ".png"))


def make_textures():
    tex = {}
    for key, (quad, w, rh, th) in FACES.items():
        im = rectify(ref(key[:2]), quad, w, rh, th, px_per_m=PPM if w <= 4 else 96)
        a = np.asarray(im).copy()
        if key == "p8":  # its vents are painted white in the render: make them holes
            rgb = a[..., :3].astype(int)
            bright = (rgb.mean(-1) > 200) & (a[..., 3] > 0)
            a[bright, 3] = 0
        # opaque, mud-coloured fill behind the alpha edge so mip levels don't go dark
        im = Image.fromarray(a)
        if key in ("p4", "p8"):  # these need their alpha (vent holes)
            path = os.path.join(TEX, "kit_%s.png" % key)
            # 256-colour PNG keeps the alpha and is a third of the size
            im.quantize(256, method=Image.Quantize.FASTOCTREE).save(path, optimize=True)
        else:
            path = os.path.join(TEX, "kit_%s.jpg" % key)
            im.convert("RGB").save(path, quality=88)
        tex[key] = (path, im)
    # tileable plaster: a 2 x 2 m patch of the plain wall, crossfaded so it wraps
    p1 = np.asarray(tex["p1"][1].convert("RGB"), float)
    n = 256
    patch = p1[100:100 + n, 200:200 + n]  # clear of the top edge seen in the render
    b = np.roll(np.roll(patch, n // 2, 0), n // 2, 1)
    y, x = np.mgrid[0:n, 0:n]
    d = np.minimum(np.minimum(x, n - 1 - x), np.minimum(y, n - 1 - y)) / (n / 2)
    w = np.clip((d - 0.05) / 0.35, 0, 1)[..., None]
    tile = Image.fromarray((patch * w + b * (1 - w)).clip(0, 255).astype(np.uint8))
    tile_path = os.path.join(TEX, "kit_mud_tile.jpg")
    tile.save(tile_path, quality=88)
    tex["tile"] = (tile_path, tile)
    # lintel wood, cropped from the door render
    p3 = tex["p3"][1]
    x0, x1, z0, z1 = 1.34, 2.69, 2.29, 2.48
    H = p3.size[1]
    crop = p3.crop((int(x0 * PPM), int(H - z1 * PPM), int(x1 * PPM), int(H - z0 * PPM))).convert("RGB")
    wood_path = os.path.join(TEX, "kit_lintel.jpg")
    crop.resize((256, 40)).save(wood_path, quality=88)
    tex["wood"] = (wood_path, crop)
    return tex


# --- materials ------------------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
_m = {}


def mat(name, path, clip=False):
    if name in _m:
        return _m[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 1.0
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = bpy.data.images.load(path)
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    if clip:
        nt.links.new(t.outputs["Alpha"], b.inputs["Alpha"])
        m.blend_method = "CLIP" if hasattr(m, "blend_method") else m.blend_method
        try:
            m.surface_render_method = "DITHERED"
        except AttributeError:
            pass
    _m[name] = m
    return m


def link(bm, name, mats):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    sc.collection.objects.link(o)
    for m in mats:
        me.materials.append(m)
    return o


def box_uv(face, uv, tile=2.0):
    n = face.normal
    ax = max(range(3), key=lambda i: abs(n[i]))
    for lp in face.loops:
        c = lp.vert.co
        u, v = (c.y, c.z) if ax == 0 else (c.x, c.z) if ax == 1 else (c.x, c.y)
        lp[uv].uv = (u / tile, v / tile)


# --- walls ----------------------------------------------------------------------------------

def slab_wall(name, length, tops, front, back, tile, total_h, opening=None, flip_back=True):
    """A wall of thickness T along X (centred), front face at -Y.
    tops: list of (x, z_top) breakpoints from -length/2 to +length/2 (top outline).
    front/back: materials whose image spans x 0..length and z 0..total_h.
    opening: (x0, x1, z_top) cut from the ground up."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.verify()
    xs = [p[0] for p in tops]
    if opening:
        xs = sorted(set(xs + [opening[0], opening[1]]))
    zt = np.interp(xs, [p[0] for p in tops], [p[1] for p in tops])

    def bottom(x):
        if opening and opening[0] - 1e-6 <= x <= opening[1] + 1e-6:
            return opening[2]
        return 0.0
    yF, yB = -T / 2, T / 2
    cols = []
    for x, z in zip(xs, zt):
        cols.append((x, z))

    def uvf(x, z, mirror):
        u = (x + length / 2) / length
        return (1 - u if mirror else u, z / total_h)
    faces_front, faces_back, faces_tile = [], [], []
    for i in range(len(cols) - 1):
        (xa, za), (xb, zb) = cols[i], cols[i + 1]
        mid = (xa + xb) / 2
        ba = bb = 0.0
        if opening and opening[0] - 1e-6 <= mid <= opening[1] + 1e-6:
            ba = bb = opening[2]
        for y, store, mirror in ((yF, faces_front, False), (yB, faces_back, flip_back)):
            vs = [bm.verts.new((xa, y, ba)), bm.verts.new((xb, y, bb)), bm.verts.new((xb, y, zb)), bm.verts.new((xa, y, za))]
            f = bm.faces.new(vs if y == yF else vs[::-1])
            for lp in f.loops:
                lp[uv].uv = uvf(lp.vert.co.x, lp.vert.co.z, mirror)
            store.append(f)
        # top strip (faces up: the game culls back faces, so winding matters)
        vs = [bm.verts.new((xa, yF, za)), bm.verts.new((xb, yF, zb)), bm.verts.new((xb, yB, zb)), bm.verts.new((xa, yB, za))]
        faces_tile.append(bm.faces.new(vs))
        # soffit over the opening (faces down)
        if ba > 0:
            vs = [bm.verts.new((xa, yF, ba)), bm.verts.new((xb, yF, bb)), bm.verts.new((xb, yB, bb)), bm.verts.new((xa, yB, ba))]
            faces_tile.append(bm.faces.new(vs[::-1]))
    # ends and opening jambs
    for x, z in (cols[0], cols[-1]):
        s = -1 if x < 0 else 1
        vs = [bm.verts.new((x, yF, 0)), bm.verts.new((x, yB, 0)), bm.verts.new((x, yB, z)), bm.verts.new((x, yF, z))]
        f = bm.faces.new(vs if s > 0 else vs[::-1])
        faces_tile.append(f)
    if opening:
        for x, s in ((opening[0], 1), (opening[1], -1)):
            vs = [bm.verts.new((x, yF, 0)), bm.verts.new((x, yB, 0)), bm.verts.new((x, yB, opening[2])), bm.verts.new((x, yF, opening[2]))]
            faces_tile.append(bm.faces.new(vs if s > 0 else vs[::-1]))
    bm.normal_update()  # (box UVs pick the projection from the face normal)
    for f in faces_back:
        f.material_index = 1
    for f in faces_tile:
        f.material_index = 2
        box_uv(f, uv, 2.0)
    bm.normal_update()
    o = link(bm, name, [front, back, tile])
    return o


def profile_from_alpha(im, length, total_h, samples=60, smooth=2):
    """Top outline (x, z) of a rectified wall image from its alpha channel."""
    a = np.asarray(im)[..., 3] > 128
    H, W = a.shape
    pts = []
    for i in range(samples + 1):
        u = i / samples
        cx = min(W - 1, int(u * (W - 1)))
        cols = a[:, max(0, cx - 2):cx + 3].any(1)
        rows = np.nonzero(cols)[0]
        top = rows.min() if len(rows) else H - 1
        pts.append([u * length - length / 2, (H - top) / H * total_h])
    z = np.array([p[1] for p in pts])
    k = np.ones(2 * smooth + 1) / (2 * smooth + 1)
    zs = np.convolve(np.pad(z, smooth, mode="edge"), k, mode="valid")
    return [(p[0], float(zz)) for p, zz in zip(pts, zs)]


def extrude_profile(name, poly, depth, m, axis="y"):
    """Flat polygon in the XZ plane (list of (x, z)), extruded `depth` along Y (centred)."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.verify()
    f0 = bm.faces.new([bm.verts.new((x, -depth / 2, z)) for x, z in poly])
    if f0.normal.y > 0:
        f0.normal_flip()
    r = bmesh.ops.extrude_face_region(bm, geom=[f0])
    bmesh.ops.translate(bm, verts=[e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)], vec=(0, depth, 0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        box_uv(f, uv, 2.0)
    return link(bm, name, [m])


CRENEL = [(-0.30, 0), (0.30, 0), (0.30, 0.15), (0.225, 0.15), (0.225, 0.32), (0.165, 0.32), (0.165, 0.48),
          (0.10, 0.48), (0.10, 0.64), (0, 0.75), (-0.10, 0.64), (-0.10, 0.48), (-0.165, 0.48), (-0.165, 0.32),
          (-0.225, 0.32), (-0.225, 0.15), (-0.30, 0.15)]


def build(tex):
    TILE = mat("kit_mud", tex["tile"][0])
    F = {k: mat("kit_" + k, tex[k][0], clip=k in ("p4", "p8")) for k in ("p1", "p3", "p4", "p8", "p2a", "p2b")}
    WOOD = mat("kit_wood", tex["wood"][0])
    pieces = {}

    flat = [(-2.0, WALL_H), (2.0, WALL_H)]
    pieces["wall"] = [slab_wall("Wall", 4.0, flat, F["p1"], F["p1"], TILE, WALL_H)]

    o = slab_wall("WallDoor", 4.0, flat, F["p3"], F["p3"], TILE, WALL_H, opening=(-0.47, 0.53, 2.29))
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1)
    bmesh.ops.scale(bm, vec=(1.35, 0.6, 0.19), verts=bm.verts)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0.015, -0.02, 2.385))
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        for lp in f.loops:
            c = lp.vert.co
            lp[uv].uv = ((c.x + 0.675) / 1.35 if abs(f.normal.y) > 0.5 or abs(f.normal.z) > 0.5 else (c.y + 0.3) / 0.6,
                         (c.z - 2.29) / 0.19 if abs(f.normal.z) < 0.5 else (c.y + 0.3) / 0.6)
    lint = link(bm, "Lintel", [WOOD])
    lint.parent = o
    pieces["wall_door"] = [o]

    for key, name in (("p4", "FacadeGable"), ("p8", "FacadeSteps")):
        im = tex[key][1]
        prof = profile_from_alpha(im, 6.0, 6.9)
        pieces["facade_gable" if key == "p4" else "facade_steps"] = [slab_wall(name, 6.0, prof, F[key], F[key], TILE, 6.9)]

    # L corner: arm A along +X, arm B along +Y; the textured faces look into the corner
    # both arms reach 2.25 m from the corner (the point where the two wall centrelines meet)
    a = slab_wall("CornerA", 2.5, [(-1.25, WALL_H), (1.25, WALL_H)], F["p2a"], F["p2a"], TILE, WALL_H)
    a.location = (1.0, 0, 0)
    a.rotation_euler = (0, 0, math.pi)  # front (textured) face towards +Y, into the corner
    b = slab_wall("CornerB", 2.0, [(-1.0, WALL_H), (1.0, WALL_H)], F["p2b"], F["p2b"], TILE, WALL_H)
    b.location = (0, 1.25, 0)
    b.rotation_euler = (0, 0, math.pi / 2)  # front face towards +X
    root = bpy.data.objects.new("WallCorner", None)
    sc.collection.objects.link(root)
    a.parent = root
    b.parent = root
    pieces["wall_corner"] = [root]

    pieces["crenel"] = [extrude_profile("Crenel", CRENEL, 0.2, TILE)]

    # corner crenel: a stepped pyramid with the crenel's steps on all four sides, on an L band
    bm = bmesh.new()
    for w, z0, z1 in ((0.6, 0, 0.15), (0.45, 0.15, 0.32), (0.33, 0.32, 0.48), (0.2, 0.48, 0.64)):
        g = bmesh.ops.create_cube(bm, size=1)
        bmesh.ops.scale(bm, vec=(w, w, z1 - z0), verts=g["verts"])
        bmesh.ops.translate(bm, verts=g["verts"], vec=(0, 0, (z0 + z1) / 2))
    g = bmesh.ops.create_cone(bm, cap_ends=True, segments=4, radius1=0.1 * math.sqrt(2), radius2=0, depth=0.12)
    bmesh.ops.rotate(bm, verts=g["verts"], matrix=__import__("mathutils").Matrix.Rotation(math.pi / 4, 3, "Z"))
    bmesh.ops.translate(bm, verts=g["verts"], vec=(0, 0, 0.70))
    for (sx, sy, cx, cy) in ((0.6, 0.2, 0.6, 0.0), (0.2, 0.6, 0.0, 0.6)):  # low band along both walls
        g = bmesh.ops.create_cube(bm, size=1)
        bmesh.ops.scale(bm, vec=(sx, sy, 0.12), verts=g["verts"])
        bmesh.ops.translate(bm, verts=g["verts"], vec=(cx, cy, 0.06))
    bm.normal_update()
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        box_uv(f, uv, 2.0)
    c1 = link(bm, "CrenelCorner", [TILE])
    pieces["crenel_corner"] = [c1]

    bm = bmesh.new()
    for w, z0, z1 in ((0.5, 0, 0.22), (0.34, 0.22, 2.5), (0.44, 2.5, 2.6), (0.54, 2.6, 2.7), (0.64, 2.7, 2.82)):
        g = bmesh.ops.create_cube(bm, size=1)
        bmesh.ops.scale(bm, vec=(w, w, z1 - z0), verts=g["verts"])
        bmesh.ops.translate(bm, verts=g["verts"], vec=(0, 0, (z0 + z1) / 2))
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        box_uv(f, uv, 2.0)
    pieces["column"] = [link(bm, "Column", [TILE])]
    return pieces


def drop_bottoms(objs):
    """Faces lying on the ground and facing down are never seen; they only z-fight the floor."""
    for o in objs:
        for ob in [o] + list(o.children_recursive):
            if ob.type != "MESH":
                continue
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            bm.normal_update()
            dead = [f for f in bm.faces if f.normal.z < -0.9 and f.calc_center_median().z < 0.01]
            bmesh.ops.delete(bm, geom=dead, context="FACES")
            bm.to_mesh(ob.data)
            bm.free()


def check_outward(objs):
    """Each face should point away from the piece's middle (or its own slab's middle line)."""
    bad = 0
    for o in objs:
        for ob in [o] + list(o.children_recursive):
            if ob.type != "MESH":
                continue
            me = ob.data
            me.update()
            for p in me.polygons:
                n, c = p.normal, p.center
                if abs(n.z) > 0.7 and c.z > 0.05 and n.z < 0 and not p.material_index == 2:
                    bad += 1
    return bad


def export(objs, name):
    drop_bottoms(objs)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
        for c in o.children_recursive:
            c.select_set(True)
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_materials="EXPORT", export_image_format="AUTO", export_apply=True)
    sel = [o for o in bpy.context.selected_objects if o.type == "MESH"]
    tris = 0
    for o in sel:
        o.data.calc_loop_triangles()
        tris += len(o.data.loop_triangles)
    print("exported", name, os.path.getsize(path) // 1024, "KB", tris, "tris")


def main():
    tex = make_textures()
    pieces = build(tex)
    for name, objs in pieces.items():
        export(objs, name)


main()
