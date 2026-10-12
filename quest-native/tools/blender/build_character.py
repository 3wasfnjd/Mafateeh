"""Builds the Mafateeh hero: a miniature elderly Saudi man in a thobe, red-and-white
shemagh wrapped as a turban, with a full white beard: the comedic "shaib" of the
character reference sheet (big head, round belly, short legs). Run with Blender 5.2:

    blender -b -P build_character.py -- <out_dir>      (or: python -m bpy via the bpy module)

Outputs <out_dir>/hero.blend (editable source) and <out_dir>/hero.glb (runtime).
Everything is procedural: meshes, UVs, skin weights, rig and animation clips, so the
asset is reproducible from this file. Units: board units (1 = one floor tile); the
figure is ~1.25 tall. Blender -Y is the character's front (glTF/Godot +Z).
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Euler, Matrix, Quaternion, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else os.path.join(os.path.dirname(__file__), "../../assets/character")
TEX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../assets/textures")
FPS = 30


def smooth(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a))) if b != a else 0.0
    return t * t * (3 - 2 * t)


# --------------------------------------------------------------------------------------
# Skeleton (rest pose, Blender coordinates: x = character's left, -y = front, z = up)
# --------------------------------------------------------------------------------------
BONES = [
    # name, head, tail, parent
    ("Root", (0, 0, 0), (0, 0, 0.12), None),
    ("Hips", (0, 0, 0.42), (0, 0, 0.55), "Root"),
    ("Spine", (0, 0, 0.55), (0, 0, 0.67), "Hips"),
    ("Chest", (0, 0, 0.67), (0, 0, 0.78), "Spine"),
    ("Neck", (0, 0, 0.78), (0, 0, 0.85), "Chest"),
    ("Head", (0, 0, 0.85), (0, 0, 1.16), "Neck"),
    ("Shemagh.L", (0.17, 0.02, 0.96), (0.215, 0.03, 0.74), "Head"),
    ("Shemagh.R", (-0.17, 0.02, 0.96), (-0.215, 0.03, 0.74), "Head"),
    ("Shemagh.B", (0.0, 0.17, 0.98), (0.0, 0.225, 0.62), "Head"),
    ("UpperArm.L", (0.15, 0.0, 0.715), (0.245, -0.005, 0.6), "Chest"),
    ("LowerArm.L", (0.245, -0.005, 0.6), (0.322, -0.015, 0.49), "UpperArm.L"),
    ("Hand.L", (0.322, -0.015, 0.49), (0.35, -0.025, 0.425), "LowerArm.L"),
    ("UpperArm.R", (-0.15, 0.0, 0.715), (-0.245, -0.005, 0.6), "Chest"),
    ("LowerArm.R", (-0.245, -0.005, 0.6), (-0.322, -0.015, 0.49), "UpperArm.R"),
    ("Hand.R", (-0.322, -0.015, 0.49), (-0.35, -0.025, 0.425), "LowerArm.R"),
    ("Thigh.L", (0.075, 0.0, 0.42), (0.075, 0.0, 0.24), "Hips"),
    ("Shin.L", (0.075, 0.0, 0.24), (0.075, 0.005, 0.065), "Thigh.L"),
    ("Foot.L", (0.075, 0.005, 0.065), (0.075, -0.09, 0.025), "Shin.L"),
    ("Thigh.R", (-0.075, 0.0, 0.42), (-0.075, 0.0, 0.24), "Hips"),
    ("Shin.R", (-0.075, 0.0, 0.24), (-0.075, 0.005, 0.065), "Thigh.R"),
    ("Foot.R", (-0.075, 0.005, 0.065), (-0.075, -0.09, 0.025), "Shin.R"),
    # Where carried objects sit, between the hands in the carry pose.
    ("CarrySocket", (0.0, -0.28, 0.64), (0.0, -0.28, 0.7), "Chest"),
]


def seg_t(p, a, b):
    a, b, p = Vector(a), Vector(b), Vector(p)
    d = b - a
    return max(0.0, min(1.0, (p - a).dot(d) / d.length_squared))


# --------------------------------------------------------------------------------------
# Mesh accumulator: one skinned mesh, several materials, explicit UVs and weights
# --------------------------------------------------------------------------------------
class Builder:
    def __init__(self):
        self.verts, self.faces, self.weights = [], [], []

    def vert(self, p, w):
        self.verts.append(Vector(p))
        tot = sum(w.values()) or 1.0
        self.weights.append({k: v / tot for k, v in w.items() if v > 1e-4})
        return len(self.verts) - 1

    def face(self, idx, mat, uvs):
        self.faces.append((tuple(idx), mat, tuple(uvs)))

    def grid(self, rows, mat, closed_u=True, flip=False):
        """rows: list of rings, each a list of (vertex index, (u, v))."""
        for r in range(len(rows) - 1):
            a, b = rows[r], rows[r + 1]
            n = len(a)
            for i in range(n if closed_u else n - 1):
                j = (i + 1) % n
                quad = [a[i], a[j], b[j], b[i]]
                if flip:
                    quad.reverse()
                uvs = [q[1] for q in quad]
                if closed_u and j == 0 and n > 1:
                    # Seam: the wrapped corners continue u one step past the last column.
                    du = a[1][1][0] - a[0][1][0]
                    fix = {id(a[j]): (a[i][1][0] + du, a[j][1][1]), id(b[j]): (b[i][1][0] + du, b[j][1][1])}
                    uvs = [fix.get(id(q), q[1]) for q in quad]
                self.face([q[0] for q in quad], mat, uvs)

    def ellipsoid(self, c, r, mat, w, segs=16, rings=10, uv_scale=(1, 1), clip=None):
        c = Vector(c)
        rows = []
        for i in range(rings + 1):
            phi = math.pi * i / rings
            row = []
            for j in range(segs):
                th = 2 * math.pi * j / segs
                p = c + Vector((r[0] * math.sin(phi) * math.sin(th), -r[1] * math.sin(phi) * math.cos(th), r[2] * math.cos(phi)))
                row.append((self.vert(p, w(p) if callable(w) else w), (j / segs * uv_scale[0], i / rings * uv_scale[1])))
            rows.append(row)
        self.grid(rows, mat)

    def blob(self, c, r, mat, w, segs=16, rings=10, bump=None, uv_scale=(1, 1)):
        """Ellipsoid whose radius is scaled by bump(theta, phi): tufts, lobes."""
        c = Vector(c)
        rows = []
        for i in range(rings + 1):
            phi = math.pi * i / rings
            row = []
            for j in range(segs):
                th = 2 * math.pi * j / segs
                k = 1.0 + (bump(th, phi) if bump and 0 < i < rings else 0.0)
                p = c + Vector((r[0] * k * math.sin(phi) * math.sin(th), -r[1] * k * math.sin(phi) * math.cos(th),
                                r[2] * k * math.cos(phi)))
                row.append((self.vert(p, w(p) if callable(w) else w), (j / segs * uv_scale[0], i / rings * uv_scale[1])))
            rows.append(row)
        self.grid(rows, mat)

    def lathe(self, profile, mat, w, segs=24, squash=1.0, disp=None, uv_scale=(1, 1), cap_bottom=True):
        rows = []
        for i, (rad, z) in enumerate(profile):
            row = []
            for j in range(segs):
                th = 2 * math.pi * j / segs
                rr = rad + (disp(th, z) if disp else 0.0)
                p = Vector((rr * math.sin(th), -rr * squash * math.cos(th), z))
                row.append((self.vert(p, w(p)), (j / segs * uv_scale[0], z * uv_scale[1])))
            rows.append(row)
        self.grid(rows[::-1], mat)  # top-down keeps normals outward
        if cap_bottom:
            ring = rows[0]
            cz = profile[0][1]
            center = self.vert((0, 0, cz), w(Vector((0, 0, cz))))
            for j in range(segs):
                k = (j + 1) % segs
                self.face([center, ring[j][0], ring[k][0]], mat, [(0.5, 0.5), ring[j][1], ring[k][1]])

    def tube(self, path, radii, mat, w, segs=12, uv_scale=(1, 1)):
        rows = []
        for i, (p, rad) in enumerate(zip(path, radii)):
            p = Vector(p)
            d = (Vector(path[min(i + 1, len(path) - 1)]) - Vector(path[max(i - 1, 0)])).normalized()
            side = d.cross(Vector((0, 1, 0)))
            if side.length < 1e-3:
                side = d.cross(Vector((1, 0, 0)))
            side.normalize()
            up = side.cross(d).normalized()
            row = []
            for j in range(segs):
                th = 2 * math.pi * j / segs
                q = p + (side * math.cos(th) + up * math.sin(th)) * rad
                row.append((self.vert(q, w(q)), (j / segs * uv_scale[0], i / (len(path) - 1) * uv_scale[1])))
            rows.append(row)
        self.grid(rows, mat, flip=True)
        return rows

    def to_object(self, name, materials, armature):
        me = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bverts = [bm.verts.new(v) for v in self.verts]
        uv_layer = bm.loops.layers.uv.new("UVMap")
        for idx, mat, uvs in self.faces:
            if len(set(idx)) < len(idx):
                continue
            try:
                f = bm.faces.new([bverts[i] for i in idx])
            except ValueError:
                continue
            f.material_index = mat
            f.smooth = True
            for loop, uv in zip(f.loops, uvs):
                loop[uv_layer].uv = uv
        bm.normal_update()
        bm.to_mesh(me)
        bm.free()
        obj = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(obj)
        for m in materials:
            me.materials.append(m)
        groups = {b[0]: obj.vertex_groups.new(name=b[0]) for b in BONES}
        for i, w in enumerate(self.weights):
            for bone, val in w.items():
                groups[bone].add([i], val, "REPLACE")
        mod = obj.modifiers.new("Armature", "ARMATURE")
        mod.object = armature
        obj.parent = armature
        return obj


# --------------------------------------------------------------------------------------
# Materials (soft fabric, no plastic gloss)
# --------------------------------------------------------------------------------------
def material(name, color, rough=0.9, image=None, sheen=0.0):
    m = bpy.data.materials.new(name)
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.25
    if sheen and "Sheen Weight" in bsdf.inputs:
        bsdf.inputs["Sheen Weight"].default_value = sheen
    if image:
        path = os.path.join(TEX, image)
        if os.path.exists(path):
            tex = nt.nodes.new("ShaderNodeTexImage")
            tex.image = bpy.data.images.load(path)
            nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    m.diffuse_color = (*color, 1.0)
    return m


def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def make_materials():
    return [
    material("Thobe", srgb("f1e9d8"), 0.95, "thobe_albedo.png", sheen=0.3),   # 0
    material("Skin", srgb("c28862"), 0.7),                                     # 1
    material("Shemagh", srgb("d65a62"), 0.92, "turban_albedo.png", 0.3),       # 2 wrapped shemagh
    material("Agal", srgb("161414"), 0.6),                                     # 3
    material("Hair", srgb("ecebe6"), 0.9, sheen=0.4),                         # 4 beard, brows
    material("Shoe", srgb("4a2c1c"), 0.6),                                    # 5
    material("EyeWhite", srgb("f6f3ee"), 0.35),                                # 6
    material("Iris", srgb("6b4223"), 0.3),                                     # 7
    material("Dark", srgb("1d1410"), 0.4),                                     # 8 pupils, mouth
    ]
THOBE, SKIN, SHEM, AGAL, HAIR, SHOE, WHITE, IRIS, DARK = range(9)


# --------------------------------------------------------------------------------------
# Weight functions
# --------------------------------------------------------------------------------------
def w_body(p):
    z = p.z
    w = {}
    chest = smooth(0.62, 0.74, z)
    spine = smooth(0.48, 0.6, z) * (1 - chest)
    hips = 1 - chest - spine
    w["Chest"] = chest
    w["Spine"] = spine
    # The lower robe follows the legs a little so the hem swings with each step.
    legs = smooth(0.42, 0.12, z) * 0.75
    side = max(-1.0, min(1.0, p.x / 0.12))
    left = legs * max(0.0, 0.5 + side * 0.5)
    right = legs * max(0.0, 0.5 - side * 0.5)
    shin = smooth(0.26, 0.1, z)
    w["Thigh.L"] = left * (1 - shin)
    w["Shin.L"] = left * shin
    w["Thigh.R"] = right * (1 - shin)
    w["Shin.R"] = right * shin
    w["Hips"] = hips * (1 - legs) + 0.0001
    if z > 0.79:
        w = {"Neck": smooth(0.79, 0.84, z), "Chest": 1 - smooth(0.79, 0.84, z)}
    return w


def w_arm(side):
    s = "L" if side > 0 else "R"

    def f(p):
        t_up = seg_t(p, BONES[9][1], BONES[9][2])
        t_lo = seg_t(p, BONES[10][1], BONES[10][2])
        a = Vector((side * 0.15, 0, 0.715))
        e = Vector((side * 0.245, -0.005, 0.6))
        d_up = (p - a).length
        d_el = (p - e).length
        if d_up < 0.05:
            return {"Chest": 0.4, "UpperArm." + s: 0.6}
        elbow = smooth(-0.03, 0.03, (p - e).dot((e - a).normalized()))
        return {"UpperArm." + s: 1 - elbow, "LowerArm." + s: elbow}

    return f


def w_head(p):
    return {"Head": 1.0}


def w_shemagh(p):
    drape = smooth(0.95, 0.7, p.z)
    th = math.atan2(p.x, -(p.y - 0.005))
    wl = max(0.0, math.sin(th)) ** 2
    wr = max(0.0, -math.sin(th)) ** 2
    wb = max(0.0, -math.cos(th)) ** 2
    tot = wl + wr + wb or 1.0
    return {"Head": 1 - drape + 1e-4, "Shemagh.L": drape * wl / tot, "Shemagh.R": drape * wr / tot,
            "Shemagh.B": drape * wb / tot}


# --------------------------------------------------------------------------------------
# Geometry
# --------------------------------------------------------------------------------------
HEAD_C = Vector((0.0, 0.0, 0.96))
HEAD_R = (0.19, 0.18, 0.2)


def build_body(b):
    # Thobe: a pear-shaped lathe (narrow sloping shoulders, round belly) with soft
    # vertical folds toward the hem.
    profile = [(0.05, 0.072), (0.2, 0.072), (0.206, 0.15), (0.226, 0.27), (0.248, 0.38), (0.25, 0.46),
               (0.236, 0.55), (0.205, 0.63), (0.165, 0.695), (0.12, 0.745), (0.078, 0.78), (0.066, 0.795)]

    def folds(th, z):
        k = smooth(0.42, 0.12, z)
        front = max(0.0, math.cos(th)) ** 2
        belly = 0.075 * math.exp(-((z - 0.43) / 0.14) ** 2) * front
        return belly + k * (0.01 * math.sin(th * 7 + 0.6) + 0.005 * math.sin(th * 13))

    b.lathe(profile, THOBE, w_body, segs=36, squash=0.88, disp=folds, uv_scale=(2.0, 2.0))
    # Collar band and the front placket with a button, as on the sheet.
    b.lathe([(0.066, 0.79), (0.072, 0.8), (0.071, 0.835), (0.062, 0.842)], THOBE, w_body, segs=20, squash=0.92,
            cap_bottom=False, uv_scale=(1, 1))
    for z in (0.585, 0.63):
        r = 0.225 + folds(0.0, z) if z < 0.6 else 0.205 + folds(0.0, z)
        b.ellipsoid((0.0, -0.88 * r - 0.004, z), (0.008, 0.004, 0.008), THOBE, w_body, segs=8, rings=4)
    # Sleeves (thobe), chubby to the wrist, and hands (skin).
    for side in (1, -1):
        s = "L" if side > 0 else "R"
        path = [(side * 0.12, 0.0, 0.715), (side * 0.2, -0.003, 0.66), (side * 0.245, -0.005, 0.6),
                (side * 0.29, -0.01, 0.535), (side * 0.322, -0.015, 0.49)]
        b.tube(path, [0.085, 0.078, 0.07, 0.066, 0.068], THOBE, w_arm(side), segs=16, uv_scale=(1, 1))
        b.ellipsoid((side * 0.322, -0.015, 0.49), (0.062, 0.062, 0.02), THOBE, {"LowerArm." + s: 1.0}, segs=12, rings=6)
        hw = {"Hand." + s: 1.0}
        # Palm, four short fingers and a thumb: a friendly cartoon hand.
        b.ellipsoid((side * 0.338, -0.02, 0.448), (0.036, 0.03, 0.04), SKIN, hw, segs=12, rings=8)
        for k in range(4):
            fy = -0.04 + k * 0.022
            b.ellipsoid((side * 0.348, fy + 0.015, 0.41), (0.011, 0.011, 0.024), SKIN, hw, segs=8, rings=6)
        b.ellipsoid((side * 0.322, -0.05, 0.458), (0.013, 0.015, 0.022), SKIN, hw, segs=8, rings=6)
        # Rounded brown shoes, with a pale trouser cuff above them.
        fw = {"Foot." + s: 1.0}
        b.ellipsoid((side * 0.08, -0.07, 0.04), (0.062, 0.11, 0.044), SHOE, fw, segs=16, rings=8)
        b.lathe([(0.042, 0.06), (0.044, 0.1)], THOBE, lambda p, s=s: {"Shin." + s: 1.0}, segs=10, cap_bottom=False)
    # Neck (hidden by the beard from the front).
    b.lathe([(0.06, 0.78), (0.06, 0.88)], SKIN, lambda p: {"Neck": 1.0}, segs=12, cap_bottom=False)


def head_radius(th, z):
    """Horizontal radius of the head ellipsoid at azimuth th (0 = front) and height z."""
    k = math.sqrt(max(0.0, 1 - ((z - HEAD_C.z) / HEAD_R[2]) ** 2))
    rx, ry = HEAD_R[0] * k, HEAD_R[1] * k
    if rx < 1e-5:
        return 0.0
    return rx * ry / math.sqrt((ry * math.sin(th)) ** 2 + (rx * math.cos(th)) ** 2)


def build_head(b):
    b.ellipsoid(HEAD_C, HEAD_R, SKIN, w_head, segs=30, rings=20)
    # Big, round, kind eyes with a highlight.
    for side in (1, -1):
        x = side * 0.068
        b.ellipsoid((x, -0.157, 0.985), (0.037, 0.02, 0.043), WHITE, w_head, segs=14, rings=10)
        b.ellipsoid((x - side * 0.004, -0.174, 0.982), (0.025, 0.008, 0.028), IRIS, w_head, segs=14, rings=8)
        b.ellipsoid((x - side * 0.004, -0.18, 0.981), (0.013, 0.004, 0.015), DARK, w_head, segs=10, rings=6)
        b.ellipsoid((x - side * 0.012, -0.184, 0.993), (0.007, 0.003, 0.007), WHITE, w_head, segs=6, rings=4)
        # Upper lid: a skin fold over the top of the eye (a warm, smiling look).
        b.ellipsoid((x, -0.155, 1.022), (0.04, 0.02, 0.01), SKIN, w_head, segs=12, rings=6)
        # Bushy white eyebrows, sloping down outward.
        for k in range(4):
            bx = x + side * (k - 1.4) * 0.018
            bz = 1.035 - 0.006 * max(0, k - 1) * (1 if side > 0 else 1)
            b.blob((bx, -0.158 + abs(k - 1.5) * 0.006, bz), (0.017, 0.012, 0.012), HAIR, w_head, segs=8, rings=5,
                   bump=lambda th, ph: 0.12 * math.sin(th * 3 + ph * 2))
        # Ears, visible below the turban.
        b.ellipsoid((side * 0.188, 0.005, 0.95), (0.02, 0.032, 0.045), SKIN, w_head, segs=10, rings=8)
        # Round cheeks.
        b.ellipsoid((side * 0.098, -0.14, 0.925), (0.048, 0.036, 0.036), SKIN, w_head, segs=12, rings=8)
        # White hair at the temples and behind the ears, under the turban.
        b.blob((side * 0.172, 0.075, 0.915), (0.026, 0.045, 0.05), HAIR, w_head, segs=12, rings=8,
               bump=lambda th, ph: 0.15 * math.sin(th * 5) * math.sin(ph * 3))
        b.blob((side * 0.07, 0.15, 0.84), (0.09, 0.05, 0.045), HAIR, w_head, segs=12, rings=8,
               bump=lambda th, ph: 0.12 * math.sin(th * 6) * math.sin(ph * 2))
    # A big round nose.
    b.ellipsoid((0.0, -0.19, 0.94), (0.03, 0.032, 0.032), SKIN, w_head, segs=14, rings=10)
    # Smiling mouth with a row of teeth under the moustache.
    b.ellipsoid((0.0, -0.162, 0.874), (0.04, 0.012, 0.014), DARK, w_head, segs=12, rings=6)
    b.ellipsoid((0.0, -0.17, 0.881), (0.03, 0.006, 0.006), WHITE, w_head, segs=10, rings=4)
    # Full moustache: two bushy wings turning down at the ends.
    for side in (1, -1):
        b.blob((side * 0.036, -0.18, 0.902), (0.046, 0.022, 0.019), HAIR, w_head, segs=12, rings=6,
               bump=lambda th, ph: 0.1 * math.sin(th * 4 + 1))
        b.blob((side * 0.08, -0.167, 0.884), (0.03, 0.02, 0.024), HAIR, w_head, segs=10, rings=6,
               bump=lambda th, ph: 0.1 * math.sin(th * 4))
    # Full white beard: cheeks to chest, made of lumpy tufts so it reads as hair.
    tuft = lambda th, ph: 0.045 * math.sin(th * 7 + ph * 3) + 0.03 * math.sin(th * 11 - ph * 5)
    b.blob((0.0, -0.085, 0.77), (0.18, 0.125, 0.125), HAIR, w_head, segs=28, rings=16, bump=tuft)
    b.blob((0.0, -0.12, 0.68), (0.1, 0.075, 0.06), HAIR, w_head, segs=16, rings=10, bump=tuft)
    for side in (1, -1):
        b.blob((side * 0.14, -0.075, 0.862), (0.06, 0.07, 0.085), HAIR, w_head, segs=14, rings=10, bump=tuft)
        b.blob((side * 0.09, -0.135, 0.82), (0.065, 0.05, 0.06), HAIR, w_head, segs=14, rings=10, bump=tuft)


# Turban: the shemagh wrapped round the head, edge over the brow, with a tail
# hanging at the back.
TURBAN_TOP = 1.31
HEAD_SCALE = 1.14


def turban_hem(th):
    a = abs(th)
    if a < 0.8:
        return 1.05
    if a < 1.6:
        return 1.05 + (1.0 - 1.05) * smooth(0.8, 1.6, a)
    return 1.0 + (0.84 - 1.0) * smooth(1.6, math.pi, a)


def turban_point(th, z, hem, offset=0.0):
    zc, rb = 1.1, 0.255
    if z >= zc:
        bulk = rb * math.sqrt(max(0.0, 1 - ((z - zc) / (TURBAN_TOP - zc)) ** 2))
    else:
        bulk = rb - (zc - z) * 0.32
    # The edge hugs the head, then the wraps puff out above it.
    hug = head_radius(th, z) + 0.016
    r = hug + (max(bulk, hug) - hug) * smooth(hem, hem + 0.07, z)
    # Wrapped bands: rolled ridges that slope up toward the back on both sides, so
    # they cross over the forehead as on the sheet; faded on the crown.
    ridge = (0.5 + 0.5 * math.cos(2 * math.pi * (z - 0.05 * abs(th)) / 0.07)) ** 2
    r += 0.02 * ridge * smooth(hem, hem + 0.04, z) * (1 - smooth(1.2, 1.27, z))
    r += offset
    return Vector((r * math.sin(th), -r * math.cos(th) + 0.012 * smooth(0.0, 1.0, abs(th) / math.pi), z))


def build_shemagh(b):
    n_th, n_v = 64, 26
    outer, inner = [], []
    for i in range(n_v + 1):
        s = i / n_v
        ro, ri = [], []
        for j in range(n_th):
            th = -math.pi + 2 * math.pi * j / n_th
            hem = turban_hem(th)
            z = TURBAN_TOP + (hem - TURBAN_TOP) * (s ** 1.25)
            po = turban_point(th, z, hem, 0.0)
            pi_ = turban_point(th, z, hem, -0.012)
            if i == 0:
                po = Vector((0, 0.012, TURBAN_TOP))
                pi_ = Vector((0, 0.012, TURBAN_TOP - 0.012))
            # Rows of the check run along the wraps; the crown uses a top-down projection.
            u = (th + math.pi) / (2 * math.pi) * 2.0
            v = (TURBAN_TOP - z) * 2.2 + 0.25 * abs(th) / math.pi
            if z > 1.25:
                u = 0.5 + po.x * 1.7
                v = 0.5 + po.y * 1.7
            ro.append((b.vert(po, w_head(po)), (u, v)))
            ri.append((b.vert(pi_, w_head(pi_)), (u, v)))
        outer.append(ro)
        inner.append(ri)
    b.grid(outer, SHEM)
    b.grid(inner, SHEM, flip=True)
    last_o, last_i = outer[-1], inner[-1]
    for j in range(n_th):
        k = (j + 1) % n_th
        b.face([last_o[j][0], last_o[k][0], last_i[k][0], last_i[j][0]], SHEM,
               [last_o[j][1], last_o[k][1], last_i[k][1], last_i[j][1]])
    # A rolled band along the front edge, over the brow.
    rows = []
    n, m = 40, 8
    for i in range(n + 1):
        th = -1.7 + 3.4 * i / n
        hem = turban_hem(th)
        c = turban_point(th, hem + 0.02, hem, 0.0)
        out = Vector((math.sin(th), -math.cos(th), 0.0))
        ring = []
        for j in range(m):
            a = 2 * math.pi * j / m
            p = c + out * (0.016 * math.cos(a)) + Vector((0, 0, 0.022 * math.sin(a)))
            ring.append((b.vert(p, w_head(p)), (i / n * 4.0, j / m * 0.3)))
        rows.append(ring)
    b.grid(rows, SHEM)
    # The tail: the loose end of the cloth hanging down the back, a little to one side.
    n_l, n_w = 10, 6
    top_c, bot_c = Vector((-0.03, 0.225, 1.0)), Vector((-0.06, 0.215, 0.76))
    for face_off in (0.0, 0.014):
        rows = []
        for i in range(n_l + 1):
            t = i / n_l
            c = top_c.lerp(bot_c, t)
            c.y += 0.03 * math.sin(t * math.pi) + face_off
            width = 0.2 - 0.06 * t
            row = []
            for j in range(n_w + 1):
                u = j / n_w - 0.5
                p = c + Vector((u * width, 0.012 * math.cos(u * 6.0) * t, -0.02 * u))
                tw = smooth(0.0, 0.35, t)
                row.append((b.vert(p, {"Head": 1 - tw + 1e-4, "Shemagh.B": tw}), (j / n_w * 1.2, t * 1.6)))
            rows.append(row)
        b.grid(rows, SHEM, closed_u=False, flip=face_off > 0)


def build_agal(b):
    # The wrapped turban of the reference sheet has no agal.
    return


# --------------------------------------------------------------------------------------
# Rig and animation
# --------------------------------------------------------------------------------------
def build_armature():
    arm_data = bpy.data.armatures.new("HeroRig")
    arm = bpy.data.objects.new("HeroRig", arm_data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for name, head, tail, parent in BONES:
        eb = arm_data.edit_bones.new(name)
        eb.head = head
        eb.tail = tail
        eb.roll = 0.0
        if parent:
            eb.parent = arm_data.edit_bones[parent]
            eb.use_connect = False
        eb.use_deform = name != "CarrySocket"
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return arm


def pose_key(arm, frame, pose):
    """pose: bone -> (euler degrees in armature space, location offset in armature space)."""
    for pb in arm.pose.bones:
        rest = pb.bone.matrix_local.to_quaternion()
        rot, loc = pose.get(pb.name, ((0, 0, 0), (0, 0, 0)))
        q_world = Euler([math.radians(a) for a in rot], "XYZ").to_quaternion()
        pb.rotation_quaternion = rest.inverted() @ q_world @ rest
        pb.location = rest.inverted() @ Vector(loc)
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.keyframe_insert("location", frame=frame)


def add(p, bone, rot=(0, 0, 0), loc=(0, 0, 0)):
    r0, l0 = p.get(bone, ((0, 0, 0), (0, 0, 0)))
    p[bone] = (tuple(a + b for a, b in zip(r0, rot)), tuple(a + b for a, b in zip(l0, loc)))


ARMS_DOWN = 24.0  # rest arms are spread; this brings them to a relaxed stance


def base_pose(arms=True):
    p = {}
    if arms:
        add(p, "UpperArm.L", (0, ARMS_DOWN, 0))
        add(p, "UpperArm.R", (0, -ARMS_DOWN, 0))
        add(p, "LowerArm.L", (-8, 0, 0))
        add(p, "LowerArm.R", (-8, 0, 0))
    return p


def legs(p, ph, amp=30.0, knee=40.0, bias=0.0, bob=0.014):
    s, c = math.sin(ph), math.cos(ph)
    add(p, "Thigh.L", (-amp * s - bias, 0, 0))
    add(p, "Thigh.R", (amp * s - bias, 0, 0))
    add(p, "Shin.L", (knee * max(0.0, c), 0, 0))
    add(p, "Shin.R", (knee * max(0.0, -c), 0, 0))
    add(p, "Foot.L", (-0.4 * knee * max(0.0, c) + 0.3 * amp * s, 0, 0))
    add(p, "Foot.R", (-0.4 * knee * max(0.0, -c) - 0.3 * amp * s, 0, 0))
    add(p, "Hips", (0, 0, 5 * s), (0, 0, bob * math.cos(2 * ph) - bob * 0.3))
    add(p, "Spine", (0, 0, -3 * s))


def swing_arms(p, ph, amp=20.0):
    s = math.sin(ph)
    add(p, "UpperArm.L", (amp * s, 0, 0))
    add(p, "UpperArm.R", (-amp * s, 0, 0))
    add(p, "LowerArm.L", (-6 - 6 * max(0, -s), 0, 0))
    add(p, "LowerArm.R", (-6 - 6 * max(0, s), 0, 0))


def hold_pose(p):
    """Both hands forward around CarrySocket (arms bent, forearms level)."""
    add(p, "UpperArm.L", (-40, ARMS_DOWN - 20, -22))
    add(p, "UpperArm.R", (-40, -ARMS_DOWN + 20, 22))
    add(p, "LowerArm.L", (-50, -12, -38))
    add(p, "LowerArm.R", (-50, 12, 38))
    add(p, "Hand.L", (0, 0, -15))
    add(p, "Hand.R", (0, 0, 15))


def clip_idle(t, T):
    ph = 2 * math.pi * t / T
    p = base_pose()
    add(p, "Chest", (1.5 * math.sin(ph), 0, 0))
    add(p, "Head", (1.0 * math.sin(ph + 1), 0, 2.0 * math.sin(ph / 2 * 2)))
    add(p, "UpperArm.L", (1.5 * math.sin(ph), 0, 0))
    add(p, "UpperArm.R", (1.5 * math.sin(ph), 0, 0))
    add(p, "Hips", (0, 0, 0), (0, 0, -0.003 + 0.003 * math.sin(ph)))
    return p


def clip_walk(t, T):
    ph = 2 * math.pi * t / T
    p = base_pose()
    legs(p, ph)
    swing_arms(p, ph)
    add(p, "Chest", (3, 0, -2 * math.sin(ph)))
    add(p, "Head", (-2 + 1.5 * math.cos(2 * ph), 0, 2 * math.sin(ph)))
    return p


def clip_turn(t, T):
    ph = 2 * math.pi * t / T
    p = base_pose()
    legs(p, ph, amp=9, knee=30, bob=0.008)
    swing_arms(p, ph, 6)
    return p


def clip_push(t, T):
    ph = 2 * math.pi * t / T
    p = {}
    legs(p, ph, amp=18, knee=26, bias=10, bob=0.008)
    add(p, "Spine", (12, 0, 0))
    add(p, "Chest", (8, 0, 0))
    add(p, "Head", (-14, 0, 0))
    add(p, "UpperArm.L", (-78 + 3 * math.sin(ph), 12, 0))
    add(p, "UpperArm.R", (-78 - 3 * math.sin(ph), -12, 0))
    add(p, "LowerArm.L", (-10, 0, 0))
    add(p, "LowerArm.R", (-10, 0, 0))
    add(p, "Hand.L", (-25, 0, 0))
    add(p, "Hand.R", (-25, 0, 0))
    return p


def crouch_amount(t, T, rising):
    k = t / T
    return smooth(0, 0.45, k) * (1 - smooth(0.55, 1.0, k)) if rising is None else (
        1 - smooth(0.3, 1.0, k) if rising else smooth(0.0, 0.6, k))


def crouch(p, a):
    add(p, "Hips", (0, 0, 0), (0, 0, -0.13 * a))
    add(p, "Thigh.L", (-62 * a, 0, -4 * a))
    add(p, "Thigh.R", (-62 * a, 0, 4 * a))
    add(p, "Shin.L", (95 * a, 0, 0))
    add(p, "Shin.R", (95 * a, 0, 0))
    add(p, "Foot.L", (-33 * a, 0, 0))
    add(p, "Foot.R", (-33 * a, 0, 0))
    add(p, "Spine", (24 * a, 0, 0))
    add(p, "Chest", (10 * a, 0, 0))
    add(p, "Head", (-16 * a, 0, 0))


def clip_pickup(t, T):
    k = t / T
    a = smooth(0.0, 0.42, k) * (1 - smooth(0.55, 1.0, k))
    p = {}
    crouch(p, a)
    reach = smooth(0.1, 0.42, k)
    hold = smooth(0.5, 1.0, k)
    # Reach down toward the object, then lift it into the carry hold.
    add(p, "UpperArm.L", (-45 * reach * (1 - hold), (ARMS_DOWN - 6) * (1 - hold), 0))
    add(p, "UpperArm.R", (-45 * reach * (1 - hold), -(ARMS_DOWN - 6) * (1 - hold), 0))
    q = {}
    hold_pose(q)
    for name, (rot, loc) in q.items():
        add(p, name, tuple(r * hold for r in rot), loc)
    return p


def _place(t, T):
    k = t / T
    a = smooth(0.0, 0.45, k) * (1 - smooth(0.6, 1.0, k))
    p = {}
    crouch(p, a)
    hold = 1 - smooth(0.35, 0.6, k)
    q = {}
    hold_pose(q)
    for name, (rot, loc) in q.items():
        add(p, name, tuple(r * hold for r in rot), loc)
    rest = 1 - hold
    add(p, "UpperArm.L", (-40 * a * rest, ARMS_DOWN * rest, 0))
    add(p, "UpperArm.R", (-40 * a * rest, -ARMS_DOWN * rest, 0))
    return p


def clip_carry(t, T):
    ph = 2 * math.pi * t / T
    p = {}
    hold_pose(p)
    legs(p, ph, amp=22, knee=34)
    add(p, "Chest", (-3, 0, -1.5 * math.sin(ph)))
    add(p, "Head", (-3, 0, 0))
    return p


def clip_carry_idle(t, T):
    ph = 2 * math.pi * t / T
    p = {}
    hold_pose(p)
    add(p, "Chest", (-3 + 1.2 * math.sin(ph), 0, 0))
    add(p, "Hips", (0, 0, 0), (0, 0, -0.004 + 0.003 * math.sin(ph)))
    return p


def clip_stairs(up):
    def f(t, T):
        ph = 2 * math.pi * t / T
        p = base_pose()
        if up:
            legs(p, ph, amp=30, knee=58, bias=12, bob=0.02)
            add(p, "Spine", (9, 0, 0))
        else:
            legs(p, ph, amp=24, knee=30, bias=-4, bob=0.02)
            add(p, "Spine", (-5, 0, 0))
            add(p, "Head", (8, 0, 0))
        swing_arms(p, ph, 14)
        return p
    return f


def clip_think(t, T):
    k = t / T
    a = smooth(0.0, 0.25, k) * (1 - smooth(0.78, 1.0, k))
    p = base_pose()
    add(p, "UpperArm.R", (-62 * a, 6 * a, 18 * a))
    add(p, "LowerArm.R", (-112 * a, 0, -10 * a))
    add(p, "Hand.R", (0, 0, 20 * a))
    add(p, "UpperArm.L", (-25 * a, 6 * a, 0))
    add(p, "LowerArm.L", (-60 * a, 0, 0))
    add(p, "Head", (-6 * a, 0, 9 * a + 2 * a * math.sin(k * 12)))
    add(p, "Chest", (2 * a, 0, 0))
    return p


def clip_celebrate(t, T):
    k = t / T
    a = smooth(0.0, 0.2, k) * (1 - smooth(0.8, 1.0, k))
    hop = math.sin(min(1.0, max(0.0, (k - 0.2) / 0.5)) * math.pi)
    p = base_pose()
    add(p, "UpperArm.L", (-20 * a, -(ARMS_DOWN + 105) * a, 0))
    add(p, "UpperArm.R", (-20 * a, (ARMS_DOWN + 105) * a, 0))
    add(p, "LowerArm.L", (-20 * a, -10 * a, 0))
    add(p, "LowerArm.R", (-20 * a, 10 * a, 0))
    add(p, "Hips", (0, 0, 0), (0, 0, 0.07 * hop))
    add(p, "Thigh.L", (-14 * hop, 0, 0))
    add(p, "Thigh.R", (-14 * hop, 0, 0))
    add(p, "Shin.L", (26 * hop, 0, 0))
    add(p, "Shin.R", (26 * hop, 0, 0))
    add(p, "Head", (-10 * a, 0, 0))
    return p


def clip_reject(t, T):
    k = t / T
    a = math.sin(k * math.pi)
    p = base_pose()
    add(p, "Head", (3 * a, 0, 16 * a * math.sin(k * 4 * math.pi)))
    add(p, "UpperArm.L", (0, -10 * a, 0))
    add(p, "UpperArm.R", (0, 10 * a, 0))
    add(p, "LowerArm.L", (-30 * a, 0, 0))
    add(p, "LowerArm.R", (-30 * a, 0, 0))
    add(p, "Chest", (0, 0, 0), (0, 0, 0.01 * a))
    return p


def clip_interact(t, T):
    k = t / T
    a = smooth(0.0, 0.45, k) * (1 - smooth(0.65, 1.0, k))
    p = base_pose()
    add(p, "Spine", (10 * a, 0, 0))
    add(p, "UpperArm.R", (-72 * a, 14 * a, 0))
    add(p, "LowerArm.R", (-8 * a, 0, 0))
    add(p, "Hand.R", (-20 * a, 0, 0))
    add(p, "Head", (8 * a, 0, 0))
    return p


CLIPS = [
    # name, seconds, function, loop
    ("idle", 2.0, clip_idle, True),
    ("walk", 0.8, clip_walk, True),
    ("turn", 0.6, clip_turn, True),
    ("push", 1.0, clip_push, True),
    ("pickup", 0.7, clip_pickup, False),
    ("carry", 0.8, clip_carry, True),
    ("carry_idle", 2.0, clip_carry_idle, True),
    ("place", 0.7, _place, False),
    ("stairs_up", 0.8, clip_stairs(True), True),
    ("stairs_down", 0.8, clip_stairs(False), True),
    ("think", 1.6, clip_think, False),
    ("celebrate", 1.3, clip_celebrate, False),
    ("reject", 0.7, clip_reject, False),
    ("interact", 0.5, clip_interact, False),
]


def build_actions(arm):
    arm.animation_data_create()
    for name, seconds, fn, loop in CLIPS:
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        arm.animation_data.action = act
        frames = int(round(seconds * FPS))
        for f in range(frames + 1):
            t = (f % frames) / FPS if loop else f / FPS  # loops end exactly on their first pose
            pose_key(arm, f, fn(t, seconds))
        act.frame_range = (0, frames)
        act.use_frame_range = True
        act.use_cyclic = loop
    arm.animation_data.action = bpy.data.actions["idle"]
    for pb in arm.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()


# --------------------------------------------------------------------------------------

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    arm = build_armature()
    b = Builder()
    build_body(b)
    first = len(b.verts)
    build_head(b)
    build_shemagh(b)
    build_agal(b)
    # Comedic proportions: the whole head (face, beard, turban) is scaled up about
    # the neck, as on the reference sheet.
    pivot = Vector((0.0, -0.02, 0.8))
    for i in range(first, len(b.verts)):
        b.verts[i] = pivot + (b.verts[i] - pivot) * HEAD_SCALE
    body = b.to_object("Hero", make_materials(), arm)
    print("hero: %d verts, %d faces" % (len(body.data.vertices), len(body.data.polygons)))
    build_actions(arm)
    os.makedirs(OUT, exist_ok=True)
    src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../art_source/character")
    os.makedirs(src, exist_ok=True)
    bpy.ops.file.pack_all()  # textures travel inside the editable .blend
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(os.path.join(src, "hero.blend")))
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=os.path.abspath(os.path.join(OUT, "hero.glb")),
        export_format="GLB", use_selection=True, export_yup=True, export_apply=False,
        export_animations=True, export_animation_mode="ACTIONS", export_skins=True,
        export_def_bones=False, export_optimize_animation_size=True, export_image_format="AUTO",
        export_materials="EXPORT", export_texcoords=True, export_normals=True, export_frame_range=False,
    )
    print("exported", os.path.join(OUT, "hero.glb"))


if __name__ == "__main__":
    main()
