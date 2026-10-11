"""Builds the Mafateeh hero: a miniature elderly Saudi man in a thobe, red-and-white
shemagh and black agal (see the character reference sheet). Run with Blender 5.2:

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
    material("Skin", srgb("c99670"), 0.7),                                     # 1
    material("Shemagh", srgb("c4343c"), 0.92, "shemagh_albedo.png", 0.3),      # 2
    material("Agal", srgb("161414"), 0.6),                                     # 3
    material("Hair", srgb("d4d2cc"), 0.85),                                    # 4 beard, brows
    material("Shoe", srgb("3b2a20"), 0.65),                                    # 5
    material("EyeWhite", srgb("f6f3ee"), 0.35),                                # 6
    material("Iris", srgb("5a3820"), 0.3),                                     # 7
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
HEAD_C = Vector((0.0, 0.0, 0.95))
HEAD_R = (0.17, 0.165, 0.19)


def build_body(b):
    # Thobe: lathe with soft vertical folds toward the hem.
    profile = [(0.05, 0.068), (0.234, 0.068), (0.228, 0.15), (0.212, 0.28), (0.196, 0.42), (0.198, 0.55),
               (0.193, 0.64), (0.176, 0.7), (0.14, 0.745), (0.09, 0.775), (0.066, 0.795)]

    def folds(th, z):
        k = smooth(0.5, 0.12, z)
        return k * (0.011 * math.sin(th * 7 + 0.6) + 0.006 * math.sin(th * 13))

    b.lathe(profile, THOBE, w_body, segs=32, squash=0.86, disp=folds, uv_scale=(2.0, 2.0))
    # Collar band and front placket with buttons.
    b.lathe([(0.066, 0.79), (0.07, 0.8), (0.069, 0.84), (0.06, 0.848)], THOBE, w_body, segs=20, squash=0.92,
            cap_bottom=False, uv_scale=(1, 1))
    for i, z in enumerate((0.585, 0.64, 0.695, 0.745)):
        y = -0.86 * {0.585: 0.197, 0.64: 0.194, 0.695: 0.178, 0.745: 0.14}[z] - 0.004
        b.ellipsoid((0.0, y, z), (0.008, 0.004, 0.008), THOBE, w_body, segs=8, rings=4)
    b.lathe([(0.0, 0.55), (0.012, 0.55), (0.012, 0.8)], THOBE, lambda p: w_body(p), segs=6, squash=0.4,
            cap_bottom=False)
    # Sleeves (thobe) and hands (skin).
    for side in (1, -1):
        s = "L" if side > 0 else "R"
        path = [(side * 0.13, 0.0, 0.725), (side * 0.2, -0.003, 0.66), (side * 0.245, -0.005, 0.6),
                (side * 0.29, -0.01, 0.535), (side * 0.322, -0.015, 0.49)]
        b.tube(path, [0.075, 0.07, 0.062, 0.06, 0.066], THOBE, w_arm(side), segs=14, uv_scale=(1, 1))
        # Cuff closes the sleeve end.
        b.ellipsoid((side * 0.322, -0.015, 0.49), (0.06, 0.06, 0.02), THOBE, {"LowerArm." + s: 1.0}, segs=12, rings=6)
        hw = {"Hand." + s: 1.0}
        b.ellipsoid((side * 0.338, -0.02, 0.445), (0.038, 0.032, 0.048), SKIN, hw, segs=12, rings=8)
        b.ellipsoid((side * 0.322, -0.048, 0.462), (0.014, 0.016, 0.022), SKIN, hw, segs=8, rings=6)
        # Shoes peek out under the hem.
        fw = {"Foot." + s: 1.0}
        b.ellipsoid((side * 0.078, -0.07, 0.036), (0.054, 0.1, 0.038), SHOE, fw, segs=14, rings=8)
    # Neck.
    b.lathe([(0.055, 0.78), (0.055, 0.88)], SKIN, lambda p: {"Neck": 1.0}, segs=12, cap_bottom=False)


def build_head(b):
    b.ellipsoid(HEAD_C, HEAD_R, SKIN, w_head, segs=28, rings=18)
    # Large, kind eyes.
    for side in (1, -1):
        x = side * 0.062
        b.ellipsoid((x, -0.151, 0.962), (0.034, 0.016, 0.04), WHITE, w_head, segs=12, rings=8)
        b.ellipsoid((x, -0.163, 0.959), (0.022, 0.008, 0.026), IRIS, w_head, segs=12, rings=8)
        b.ellipsoid((x, -0.169, 0.958), (0.011, 0.004, 0.013), DARK, w_head, segs=8, rings=6)
        b.ellipsoid((x - side * 0.008, -0.172, 0.972), (0.006, 0.003, 0.006), WHITE, w_head, segs=6, rings=4)
        # Grey eyebrows, gently sloping down outward.
        for k in range(3):
            bx = x + side * (k - 1) * 0.022
            bz = 1.022 - (0.004 * k if side > 0 else 0.004 * (2 - k)) * 1.0
            b.ellipsoid((bx, -0.148 + abs(k - 1) * 0.004, bz), (0.016, 0.01, 0.009), HAIR, w_head, segs=8, rings=4)
        # Ears (mostly under the shemagh).
        b.ellipsoid((side * 0.168, 0.0, 0.945), (0.018, 0.028, 0.038), SKIN, w_head, segs=8, rings=6)
    b.ellipsoid((0.0, -0.17, 0.923), (0.022, 0.028, 0.03), SKIN, w_head, segs=12, rings=8)  # nose
    b.ellipsoid((0.0, -0.163, 0.874), (0.02, 0.008, 0.006), DARK, w_head, segs=8, rings=4)  # mouth
    # Moustache.
    for side in (1, -1):
        b.ellipsoid((side * 0.024, -0.162, 0.893), (0.032, 0.016, 0.013), HAIR, w_head, segs=10, rings=6)
    # Short grey beard: a shell that follows the jaw from ear to ear.
    rows = []
    n_th, n_z = 22, 8
    for i in range(n_z + 1):
        z = 0.905 - 0.15 * i / n_z
        row = []
        for j in range(n_th + 1):
            th = -1.85 + 3.7 * j / n_th
            zz = (z - HEAD_C.z) / HEAD_R[2]
            ring = math.sqrt(max(0.0, 1 - zz * zz))
            grow = 0.016 + 0.018 * smooth(0.9, 0.78, z) * math.cos(th) ** 2
            rx = HEAD_R[0] * ring + grow
            ry = HEAD_R[1] * ring + grow
            p = HEAD_C.copy()
            p.x = rx * math.sin(th)
            p.y = -ry * math.cos(th)
            p.z = z - 0.012 * smooth(0.8, 0.76, z) * math.cos(th) ** 2
            if i == n_z:
                p = HEAD_C + (p - HEAD_C) * 0.6
                p.z = z - 0.01
            row.append((b.vert(p, w_head(p)), (j / n_th, i / n_z)))
        rows.append(row)
    b.grid(rows, HAIR, closed_u=False)


def shemagh_point(th, z, offset=0.0):
    """Outer surface of the head-dress at azimuth th (0 = front) and height z."""
    zc, R, Rz = 0.955, 0.188, 0.225
    if z >= zc:
        r = R * math.sqrt(max(0.0, 1 - ((z - zc) / Rz) ** 2))
    else:
        a = abs(th)
        flare = 0.28 + 0.2 * smooth(1.4, math.pi, a)
        r = R + (zc - z) * flare
    # Draped folds grow toward the hem; a soft crease runs over the crown.
    below = smooth(zc, 0.65, z)
    r += below * (0.012 * math.sin(th * 9 + 0.4) + 0.006 * math.sin(th * 17))
    r += offset
    p = Vector((r * math.sin(th), -r * math.cos(th) + 0.006, z))
    # The forward peak above the brow that gives the shemagh its silhouette.
    peak = 0.04 * math.exp(-(th / 0.33) ** 2) * math.exp(-((z - 1.1) / 0.06) ** 2)
    p.y -= peak
    p.z += 0.6 * peak
    return p


def shemagh_hem(th):
    a = abs(th)
    if a < 0.78:
        return 1.012  # forehead line leaves the face open
    if a < 1.4:
        return 1.012 + (0.735 - 1.012) * smooth(0.78, 1.4, a)
    return 0.735 + (0.6 - 0.735) * smooth(1.3, math.pi, a)


def build_shemagh(b):
    n_th, n_v = 56, 18
    top = 1.178
    outer, inner = [], []
    for i in range(n_v + 1):
        s = i / n_v
        ro, ri = [], []
        for j in range(n_th):
            th = -math.pi + 2 * math.pi * j / n_th
            hem = shemagh_hem(th)
            # Dense rows near the crown keep the pole round.
            z = top + (hem - top) * (s ** 1.45)
            po = shemagh_point(th, z, 0.022)
            pi_ = shemagh_point(th, z, 0.008)
            if i == 0:
                po = Vector((0, 0.006, top + 0.012))
                pi_ = Vector((0, 0.006, top - 0.002))
            u = (th + math.pi) / (2 * math.pi) * 1.0
            v = (top - z) * 0.85
            ro.append((b.vert(po, w_shemagh(po)), (u, v)))
            ri.append((b.vert(pi_, w_shemagh(pi_)), (u, v)))
        outer.append(ro)
        inner.append(ri)
    b.grid(outer, SHEM)
    b.grid(inner, SHEM, flip=True)
    # Stitch the hem so the cloth has visible thickness.
    last_o, last_i = outer[-1], inner[-1]
    for j in range(n_th):
        k = (j + 1) % n_th
        b.face([last_o[j][0], last_o[k][0], last_i[k][0], last_i[j][0]], SHEM,
               [last_o[j][1], last_o[k][1], last_i[k][1], last_i[j][1]])


def build_agal(b):
    # Two black cord rings, tilted slightly so they sit lower at the back.
    tilt = Matrix.Rotation(math.radians(-9), 4, "X")
    for z0, extra in ((1.07, 0.0), (1.096, -0.012)):
        zc, R, Rz = 0.955, 0.188, 0.225
        r_major = R * math.sqrt(1 - ((z0 - zc) / Rz) ** 2) + 0.022 + 0.012 + extra
        rows = []
        n, m = 40, 8
        for i in range(n + 1):
            a = 2 * math.pi * i / n
            ring = []
            for j in range(m):
                c = 2 * math.pi * j / m
                rr = r_major + 0.013 * math.cos(c)
                p = Vector((rr * math.sin(a), -rr * math.cos(a), 0.013 * math.sin(c)))
                p = tilt @ p + Vector((0, 0.008, z0))
                ring.append((b.vert(p, w_head(p)), (i / n, j / m)))
            rows.append(ring)
        for r in range(n):
            for j in range(m):
                k = (j + 1) % m
                b.face([rows[r][j][0], rows[r][k][0], rows[r + 1][k][0], rows[r + 1][j][0]], AGAL,
                       [rows[r][j][1], rows[r][k][1], rows[r + 1][k][1], rows[r + 1][j][1]])


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
    build_head(b)
    build_shemagh(b)
    build_agal(b)
    body = b.to_object("Hero", make_materials(), arm)
    print("hero: %d verts, %d faces" % (len(body.data.vertices), len(body.data.polygons)))
    build_actions(arm)
    os.makedirs(OUT, exist_ok=True)
    src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../art_source/character")
    os.makedirs(src, exist_ok=True)
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
