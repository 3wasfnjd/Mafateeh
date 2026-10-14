"""Mafateeh v2 hero: «الشايب» — a slim, graceful elderly Najdi man with a white beard,
a crook walking cane, a red shemagh draped over the head under a black agal, and a
long white thobe. Built from scratch (nothing reused from the v1 pot-bellied hero).

    python build_shaib.py -- <out_dir>          (bpy 5.x module, headless)

Everything is procedural so the asset is reproducible from this file: meshes
(subdivided, then skinned with analytic weights), UVs, textures, shape keys for the
face, rig and animation clips. Units are board units (1 = one floor tile); the
figure is ~1.26 tall. Blender -Y is the character's front (glTF/Godot +Z),
+X is the character's left.
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Quaternion, Vector, noise

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(ARGS[0] if ARGS else os.path.join(HERE, "../../assets/character"))
SRC = os.path.abspath(ARGS[1] if len(ARGS) > 1 else os.path.join(HERE, "../../art_source/character"))
FPS = 30
V = Vector
# "game" (default): the runtime GLB for Quest, one subdivision level less and lighter
# cloth grids. "hero": the review/turntable resolution.
LOD = os.environ.get("SHAIB_LOD", "game")
GAME = LOD == "game"

sys.path.insert(0, HERE)
import shaib_textures  # noqa: E402  (procedural texture painter, NumPy)


def clamp(x, a=0.0, b=1.0):
    return a if x < a else b if x > b else x


def smooth(a, b, x):
    if a == b:
        return 0.0 if x < a else 1.0
    t = clamp((x - a) / (b - a))
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def gauss(d, s):
    return math.exp(-(d * d) / (2 * s * s))


def catmull(pts, t):
    """Uniform Catmull-Rom through pts (list of Vector or float), t in [0, 1]."""
    n = len(pts) - 1
    f = clamp(t) * n
    i = min(int(f), n - 1)
    u = f - i
    p0 = pts[max(i - 1, 0)]
    p1 = pts[i]
    p2 = pts[i + 1]
    p3 = pts[min(i + 2, n)]
    return 0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u + (-p0 + 3 * p1 - 3 * p2 + p3) * u * u * u)


def profile(table, z):
    """Piecewise smooth interpolation of rows (z, a, b, ...) sorted by z."""
    if z <= table[0][0]:
        return table[0][1:]
    for r0, r1 in zip(table, table[1:]):
        if z <= r1[0]:
            t = smooth(r0[0], r1[0], z)
            return tuple(lerp(a, b, t) for a, b in zip(r0[1:], r1[1:]))
    return table[-1][1:]


# --------------------------------------------------------------------------------------
# Skeleton (rest pose)
# --------------------------------------------------------------------------------------
HEAD_C = V((0.0, -0.004, 1.03))   # skull centre
EYE_R = 0.0232
EYE_C = {s: V((s * 0.039, -0.083, 1.047)) for s in (1, -1)}
HAND_GRIP = V((-0.179, -0.026, 0.398))  # inside the curled right fist (rest pose)
# Stylised proportions: the head (face, beard, headwear) is modelled at natural size,
# then scaled about the neck so the figure reads at miniature size (~4 heads tall).
HEAD_K = 1.3
PIVOT = V((0.0, -0.004, 0.905))


def H(p):
    return PIVOT + (V(p) - PIVOT) * HEAD_K


def Hinv(p):
    return PIVOT + (V(p) - PIVOT) / HEAD_K

BONES = [
    # name, head, tail, parent
    ("Root", (0, 0, 0), (0, 0, 0.1), None),
    ("Hips", (0, 0.004, 0.50), (0, 0.004, 0.60), "Root"),
    ("Spine", (0, 0.004, 0.60), (0, 0.0, 0.72), "Hips"),
    ("Chest", (0, 0.0, 0.72), (0, -0.004, 0.85), "Spine"),
    ("Neck", (0, -0.004, 0.85), (0, -0.008, 0.925), "Chest"),
    ("Head", (0, -0.008, 0.925), tuple(H((0, -0.008, 1.18))), "Neck"),
    ("Jaw", tuple(H((0, -0.03, 0.995))), tuple(H((0, -0.095, 0.93))), "Head"),
    ("Eye.L", tuple(H(EYE_C[1])), tuple(H(EYE_C[1] + V((0, -0.03, 0)))), "Head"),
    ("Eye.R", tuple(H(EYE_C[-1])), tuple(H(EYE_C[-1] + V((0, -0.03, 0)))), "Head"),
    ("Shemagh.L", (0.092, -0.07, 0.95), (0.098, -0.092, 0.80), "Head"),
    ("Shemagh.L2", (0.098, -0.092, 0.80), (0.10, -0.098, 0.66), "Shemagh.L"),
    ("Shemagh.R", (-0.092, -0.07, 0.95), (-0.098, -0.092, 0.80), "Head"),
    ("Shemagh.R2", (-0.098, -0.092, 0.80), (-0.10, -0.098, 0.66), "Shemagh.R"),
    ("Shemagh.B", (0.0, 0.10, 0.99), (0.0, 0.118, 0.86), "Head"),
    ("Shemagh.B2", (0.0, 0.118, 0.86), (0.0, 0.122, 0.73), "Shemagh.B"),
    ("Clavicle.L", (0.02, 0.0, 0.825), (0.112, 0.004, 0.83), "Chest"),
    ("UpperArm.L", (0.115, 0.004, 0.828), (0.158, 0.004, 0.626), "Clavicle.L"),
    ("LowerArm.L", (0.158, 0.004, 0.626), (0.193, -0.016, 0.438), "UpperArm.L"),
    ("Hand.L", (0.193, -0.016, 0.438), (0.203, -0.022, 0.392), "LowerArm.L"),
    ("Fingers1.L", (0.198, -0.024, 0.400), (0.198, -0.025, 0.382), "Hand.L"),
    ("Fingers2.L", (0.198, -0.025, 0.382), (0.198, -0.026, 0.362), "Fingers1.L"),
    ("Thumb.L", (0.193, -0.040, 0.431), (0.188, -0.062, 0.400), "Hand.L"),
    ("Clavicle.R", (-0.02, 0.0, 0.825), (-0.112, 0.004, 0.83), "Chest"),
    ("UpperArm.R", (-0.115, 0.004, 0.828), (-0.158, 0.004, 0.626), "Clavicle.R"),
    ("LowerArm.R", (-0.158, 0.004, 0.626), (-0.193, -0.016, 0.438), "UpperArm.R"),
    ("Hand.R", (-0.193, -0.016, 0.438), (-0.203, -0.022, 0.392), "LowerArm.R"),
    ("Fingers1.R", (-0.198, -0.024, 0.400), (-0.198, -0.025, 0.382), "Hand.R"),
    ("Fingers2.R", (-0.198, -0.025, 0.382), (-0.198, -0.026, 0.362), "Fingers1.R"),
    ("Thumb.R", (-0.193, -0.040, 0.431), (-0.188, -0.062, 0.400), "Hand.R"),
    ("Thigh.L", (0.058, 0.004, 0.49), (0.064, 0.004, 0.272), "Hips"),
    ("Shin.L", (0.064, 0.004, 0.272), (0.068, 0.012, 0.062), "Thigh.L"),
    ("Foot.L", (0.068, 0.012, 0.062), (0.070, -0.052, 0.020), "Shin.L"),
    ("Toe.L", (0.070, -0.052, 0.020), (0.071, -0.092, 0.016), "Foot.L"),
    ("Thigh.R", (-0.058, 0.004, 0.49), (-0.064, 0.004, 0.272), "Hips"),
    ("Shin.R", (-0.064, 0.004, 0.272), (-0.068, 0.012, 0.062), "Thigh.R"),
    ("Foot.R", (-0.068, 0.012, 0.062), (-0.070, -0.052, 0.020), "Shin.R"),
    ("Toe.R", (-0.070, -0.052, 0.020), (-0.071, -0.092, 0.016), "Foot.R"),
    # Thobe skirt: secondary motion (baked lag in the clips + runtime spring).
    ("Skirt.F", (0.0, -0.06, 0.50), (0.0, -0.11, 0.08), "Hips"),
    ("Skirt.B", (0.0, 0.07, 0.50), (0.0, 0.12, 0.08), "Hips"),
    ("Skirt.L", (0.08, 0.0, 0.50), (0.13, 0.0, 0.08), "Hips"),
    ("Skirt.R", (-0.08, 0.0, 0.50), (-0.13, 0.0, 0.08), "Hips"),
    # The cane in the right fist, and the same cane hooked over the right forearm
    # (used while both hands push or carry). Clips scale one of them to zero.
    ("Cane", tuple(HAND_GRIP), tuple(HAND_GRIP + V((0, 0, -0.12))), "Hand.R"),
    ("CaneArm", (-0.178, -0.03, 0.52), (-0.178, -0.03, 0.40), "LowerArm.R"),
    # Where carried objects sit, between the hands in the carry pose.
    ("CarrySocket", (0.0, -0.21, 0.66), (0.0, -0.21, 0.72), "Chest"),
    # The falcon perches here (left shoulder).
    ("Perch", (0.172, 0.03, 0.853), (0.172, 0.03, 0.91), "Clavicle.L"),
]
BONE_PARENT = {b[0]: b[3] for b in BONES}


def build_armature():
    arm_data = bpy.data.armatures.new("ShaibRig")
    arm = bpy.data.objects.new("ShaibRig", arm_data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = {}
    for name, h, t, parent in BONES:
        b = arm_data.edit_bones.new(name)
        b.head, b.tail = V(h), V(t)
        b.roll = 0.0
        if parent:
            b.parent = eb[parent]
            b.use_connect = False
        b.use_deform = name not in ("Root", "CarrySocket", "Perch")
        eb[name] = b
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return arm


# --------------------------------------------------------------------------------------
# Mesh building: parts are built as low-res cages, subdivided, then skinned
# --------------------------------------------------------------------------------------
class Part:
    """Quads/tris with per-corner UVs and per-face material slot names."""

    def __init__(self, name):
        self.name = name
        self.v = []
        self.f = []  # (indices, material, uvs)

    def add(self, p):
        self.v.append(V(p))
        return len(self.v) - 1

    def grid(self, rows, mat, closed=False, uvf=None, flip=False, matf=None):
        """rows[i][j]: point at v-index i, u-index j. closed: u wraps (seam duplicated).
        matf(i, j) -> (material, uvf) overrides the material/UVs of single faces."""
        nv, nu = len(rows), len(rows[0])
        cols = nu + 1 if closed else nu
        idx = [[self.add(rows[i][j % nu]) for j in range(cols)] for i in range(nv)]
        for i in range(nv - 1):
            for j in range(cols - 1):
                q = [idx[i][j], idx[i][j + 1], idx[i + 1][j + 1], idx[i + 1][j]]
                uv = [(j / (cols - 1), i / (nv - 1)), ((j + 1) / (cols - 1), i / (nv - 1)),
                      ((j + 1) / (cols - 1), (i + 1) / (nv - 1)), (j / (cols - 1), (i + 1) / (nv - 1))]
                m = mat
                if matf and matf(i, j):
                    m, f2 = matf(i, j)
                    uv = [f2(a, b) for a, b in uv]
                elif uvf:
                    uv = [uvf(a, b) for a, b in uv]
                if flip:
                    q.reverse()
                    uv.reverse()
                self.f.append((q, m, uv))
        return idx

    def fan(self, ring_idx, center, mat, flip=False, uvc=(0.5, 0.5)):
        c = self.add(center)
        n = len(ring_idx)
        for j in range(n - 1):
            q = [c, ring_idx[j + 1], ring_idx[j]]
            if flip:
                q.reverse()
            self.f.append((q, mat, [uvc, uvc, uvc]))

    def sphere(self, fn, mat, nu=24, nv=16, uvf=None):
        """fn(direction) -> point; direction from a lat/long unit sphere (poles fanned)."""
        rows = []
        for i in range(1, nv):
            th = math.pi * i / nv
            rows.append([fn(V((math.sin(th) * math.sin(2 * math.pi * j / nu), -math.sin(th) * math.cos(2 * math.pi * j / nu), math.cos(th)))) for j in range(nu)])
        idx = self.grid(rows, mat, closed=True, uvf=uvf, flip=True)
        top = [r for r in idx[0]]
        bot = [r for r in idx[-1]]
        self.fan(top, fn(V((0, 0, 1))), mat, flip=False, uvc=(0.5, 0.0))
        self.fan(bot, fn(V((0, 0, -1))), mat, flip=True, uvc=(0.5, 1.0))

    def tube(self, path, radius, mat, segs=12, cap0=True, cap1=True, squash=None, uvf=None, twist_ref=V((0, 1, 0))):
        """path: list of points; radius(t, angle) -> r; squash(t) -> (sx, sy) of the cross-section."""
        rows = []
        n = len(path)
        frames = []
        ref = twist_ref
        for i in range(n):
            d = (path[min(i + 1, n - 1)] - path[max(i - 1, 0)]).normalized()
            side = d.cross(ref)
            if side.length < 1e-4:
                side = d.cross(V((1, 0, 0)))
            side.normalize()
            up = side.cross(d).normalized()
            ref = up  # parallel transport
            frames.append((side, up))
        for i in range(n):
            t = i / (n - 1)
            side, up = frames[i]
            sx, sy = squash(t) if squash else (1.0, 1.0)
            row = []
            for j in range(segs):
                a = 2 * math.pi * j / segs
                r = radius(t, a)
                row.append(path[i] + side * (math.cos(a) * r * sx) + up * (math.sin(a) * r * sy))
            rows.append(row)
        idx = self.grid(rows, mat, closed=True, uvf=uvf)
        if cap0:
            self.fan(idx[0], path[0] - (path[1] - path[0]).normalized() * radius(0.0, 0.0) * 0.35, mat, flip=True)
        if cap1:
            self.fan(idx[-1], path[-1] + (path[-1] - path[-2]).normalized() * radius(1.0, 0.0) * 0.35, mat)
        return idx


def part_object(part, materials, subdiv=1, solidify=0.0, solid_offset=-1.0):
    if GAME:
        subdiv = max(0, subdiv - 1)
    me = bpy.data.meshes.new(part.name)
    bm = bmesh.new()
    bv = [bm.verts.new(p) for p in part.v]
    uvl = bm.loops.layers.uv.new("UVMap")
    for q, mat, uvs in part.f:
        if len(set(q)) < len(q):
            continue
        try:
            f = bm.faces.new([bv[i] for i in q])
        except ValueError:
            continue
        f.material_index = materials.index(mat)
        f.smooth = True
        for loop, uv in zip(f.loops, uvs):
            loop[uvl].uv = uv
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces) if part.name.startswith("_recalc") else None
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(part.name, me)
    bpy.context.collection.objects.link(obj)
    for m in materials:
        me.materials.append(bpy.data.materials[m])
    if solidify:
        s = obj.modifiers.new("Solid", "SOLIDIFY")
        s.thickness = solidify
        s.offset = solid_offset
        s.use_even_offset = True
        s.use_quality_normals = True
    if subdiv:
        m = obj.modifiers.new("Sub", "SUBSURF")
        m.levels = subdiv
        m.render_levels = subdiv
        m.uv_smooth = "PRESERVE_BOUNDARIES"
    if obj.modifiers:
        dg = bpy.context.evaluated_depsgraph_get()
        new = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
        obj.modifiers.clear()
        obj.data = new
        bpy.data.meshes.remove(me)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


# --------------------------------------------------------------------------------------
# Body shapes
# --------------------------------------------------------------------------------------
# Thobe: rows (z, half-width x, front depth, back depth, superellipse n). Slim and
# straight, a little flare at the hem; the shoulders slope into the collar.
THOBE = [
    (0.055, 0.150, 0.142, 0.140, 2.0),
    (0.12, 0.142, 0.132, 0.130, 2.0),
    (0.26, 0.131, 0.114, 0.114, 2.0),
    (0.40, 0.122, 0.098, 0.102, 2.05),
    (0.50, 0.116, 0.088, 0.096, 2.1),
    (0.60, 0.108, 0.080, 0.088, 2.15),
    (0.70, 0.112, 0.084, 0.088, 2.3),
    (0.775, 0.120, 0.080, 0.082, 2.5),
    (0.812, 0.121, 0.070, 0.074, 2.6),
    (0.838, 0.108, 0.060, 0.064, 2.4),
    (0.858, 0.082, 0.052, 0.056, 2.2),
    (0.872, 0.058, 0.047, 0.050, 2.0),
    (0.884, 0.050, 0.045, 0.047, 2.0),
]


def superellipse(th, a, bf, bb, n):
    s, c = math.sin(th), math.cos(th)
    x = a * math.copysign(abs(s) ** (2.0 / n), s)
    b = bf if c > 0 else bb
    y = -b * math.copysign(abs(c) ** (2.0 / n), c)
    return x, y


def body_radius(th, z):
    """Distance from the vertical axis to the thobe surface at angle th (0 = front)."""
    a, bf, bb, n = profile(THOBE, z)
    x, y = superellipse(th, a, bf, bb, n)
    return math.hypot(x, y)


def thobe_point(th, z, folds=True):
    a, bf, bb, n = profile(THOBE, z)
    x, y = superellipse(th, a, bf, bb, n)
    p = V((x, y, z))
    if folds:
        out = V((x, y, 0)).normalized()
        low = smooth(0.52, 0.06, z)
        # Long vertical folds that open towards the hem, a soft drape at the back.
        f = (0.0038 * math.sin(7 * th + 0.6) + 0.0026 * math.sin(11 * th + 2.1) + 0.0016 * math.sin(17 * th)) * low
        f += 0.0022 * math.sin(5 * th + 1.3) * smooth(0.82, 0.62, z) * smooth(0.5, 0.62, z)
        # Hem not perfectly level: a gentle wave.
        p += out * f
        p.z += 0.004 * math.sin(3 * th + 0.4) * smooth(0.14, 0.055, z)
    return p


def build_thobe():
    pt = Part("Thobe")
    zs = [0.055, 0.065, 0.08, 0.10, 0.13, 0.17, 0.21, 0.26, 0.31, 0.36, 0.41, 0.46, 0.50, 0.54, 0.58,
          0.62, 0.66, 0.70, 0.735, 0.765, 0.79, 0.81, 0.826, 0.84, 0.852, 0.864, 0.874, 0.884]
    nu = 40 if GAME else 48
    rows = []
    for z in reversed(zs):
        rows.append([thobe_point(2 * math.pi * j / nu, z) for j in range(nu)])
    # UVs at fabric scale (tileable weave texture): u along the girth, v down.
    pt.grid(rows, "thobe", closed=True, uvf=lambda u, v: (u * 2.6, v * 3.4), flip=True)
    # Standing collar (qallaba) and the front placket with two buttons.
    col = []
    for k, (z, r) in enumerate([(0.878, 0.050), (0.894, 0.049), (0.906, 0.047), (0.912, 0.0455)]):
        col.append([V((r * math.sin(2 * math.pi * j / 32), -r * 0.96 * math.cos(2 * math.pi * j / 32) - 0.002, z)) for j in range(32)])
    pt.grid(col[::-1], "thobe_trim", closed=True, uvf=lambda u, v: (u * 2, v * 0.3), flip=True)
    for i, z in enumerate((0.842, 0.80)):
        c = thobe_point(0.0, z, folds=False) + V((0, -0.002, 0))
        pt.sphere(lambda d, c=c: c + V((d.x * 0.0052, d.y * 0.0022, d.z * 0.0052)), "button", nu=8, nv=5)
    return pt


# ---- Wardrobe pieces (hidden unless worn; HeroView shows them) -------------------------
def build_bisht():
    """Bisht: a dark wool cloak worn open over the thobe, gold zari along the front
    edges, loose half-sleeves over the upper arms."""
    pt = Part("Bisht")
    zs = [0.30, 0.34, 0.40, 0.47, 0.54, 0.61, 0.68, 0.735, 0.775, 0.805, 0.828, 0.846, 0.862, 0.876]
    n = 34
    rows = []
    for z in reversed(zs):
        # the front opening narrows toward the neck
        open_half = math.radians(lerp(30, 16, smooth(0.55, 0.87, z)))
        row = []
        for j in range(n + 1):
            th = lerp(open_half, 2 * math.pi - open_half, j / n)
            p = thobe_point(th, z, folds=False)
            out = V((p.x, p.y, 0)).normalized()
            # Under the shemagh (upper back and shoulders) the cloak lies close to the thobe
            # so the shemagh's flap and drape stay on top of it.
            under = smooth(0.66, 0.74, z) * (0.6 + 0.4 * smooth(1.2, 0.4, abs(th - math.pi)))
            flare = lerp(0.012, 0.0035, under) + 0.03 * smooth(0.62, 0.30, z) + 0.004 * math.sin(th * 7) * smooth(0.6, 0.3, z)
            row.append(p + out * flare + V((0, 0, 0.004 * smooth(0.8, 0.88, z))))
        rows.append(row)
    pt.grid(rows, "bisht", uvf=lambda u, v: (u * 3.0, v * 3.0), flip=True)
    # Gold zari trim down both front edges and along the hem.
    for edge in (0, n):
        pt.tube([rows[i][edge] for i in range(len(rows))], lambda t, a: 0.0055, "zari", segs=8, cap0=False, cap1=False)
    pt.tube(rows[-1], lambda t, a: 0.004, "zari", segs=6, cap0=False, cap1=False)
    # Loose half-sleeves over the upper arms.
    for s in (1, -1):
        pts = sleeve_path(s)
        path = [catmull(pts, i / 10 * 0.62) for i in range(11)]
        pt.tube(path, lambda t, a: lerp(0.052, 0.068, t), "bisht", segs=14, cap0=False, cap1=False)
        pt.tube([catmull(pts, 0.62 - 0.002), catmull(pts, 0.62)], lambda t, a: 0.069, "zari", segs=14, cap0=False, cap1=False)
    return pt


def build_glasses():
    """Round reading spectacles, in head space (scaled with the head)."""
    pt = Part("Glasses")
    for s in (1, -1):
        e = EYE_C[s] + V((0, -0.028, -0.002))
        ring = [e + V((0.025 * math.cos(a), 0.003 * math.sin(a) * s, 0.022 * math.sin(a))) for a in [2 * math.pi * i / 24 for i in range(25)]]
        pt.tube(ring, lambda t, a: 0.0022, "glasses", segs=6, cap0=False, cap1=False)
        # temple arm back into the shemagh
        pt.tube([e + V((s * 0.025, 0.0, 0.004)), e + V((s * 0.05, 0.03, 0.006)), e + V((s * 0.07, 0.07, 0.008))], lambda t, a: 0.0018, "glasses", segs=5)
    bridge = [EYE_C[1] + V((-0.014, -0.03, 0.004)), V((0.0, -0.118, EYE_C[1].z + 0.009)), EYE_C[-1] + V((0.014, -0.03, 0.004))]
    pt.tube([catmull(bridge, i / 6) for i in range(7)], lambda t, a: 0.002, "glasses", segs=5)
    return pt


def build_misbaha():
    """Prayer beads looped over the left hand's fingers, with a tassel."""
    pt = Part("Misbaha")
    c = V((0.204, -0.03, 0.352))
    nb = 25
    for i in range(nb):
        a = 2 * math.pi * i / nb
        p = c + V((0.0, 0.03 * math.sin(a), 0.038 * math.cos(a)))
        pt.sphere(lambda d, p=p: p + d * 0.0058, "misbaha", nu=6, nv=5)
    tip = c + V((0, 0, -0.045))
    pt.tube([tip, tip + V((0, 0, -0.03))], lambda t, a: 0.004 * (1 - t) + 0.006 * t, "zari", segs=6)
    return pt


def sleeve_path(s):
    return [V((s * 0.060, 0.004, 0.812)), V((s * 0.100, 0.004, 0.826)), V((s * 0.128, 0.004, 0.79)),
            V((s * 0.148, 0.004, 0.70)), V((s * 0.160, 0.003, 0.626)), V((s * 0.172, -0.004, 0.56)),
            V((s * 0.186, -0.012, 0.48)), V((s * 0.193, -0.016, 0.440)), V((s * 0.195, -0.017, 0.428))]


def build_sleeves():
    pt = Part("Sleeves")
    for s in (1, -1):
        pts = sleeve_path(s)
        path = [catmull(pts, i / 26) for i in range(27)]

        def rad(t, a):
            r = lerp(0.046, 0.0335, smooth(0.0, 0.62, t)) + 0.0028 * smooth(0.86, 0.95, t)
            r += 0.0016 * math.sin(3 * a + t * 9) * smooth(0.3, 0.8, t) * smooth(1.0, 0.85, t)
            return r
        pt.tube(path, rad, "thobe", segs=14, cap0=False, cap1=False,
                uvf=lambda u, v: (u * 0.9, v * 1.6))
        # Inner lining so the open cuff has depth.
        inner = [catmull(pts, lerp(0.9, 1.0, i / 4)) for i in range(5)]
        pt.tube(inner, lambda t, a: 0.0305, "thobe_inner", segs=14, cap0=True, cap1=False)
    return pt


# ---- Hands --------------------------------------------------------------------------
def build_hand(s):
    """Hand hanging down: palm faces the thigh (-s*x), thumb to the front (-y)."""
    pt = Part("Hand")
    w = V((s * 0.199, -0.024, 0.425))  # palm centre
    # Palm: a rounded block (thickness x, width y, length z).
    def palm(d):
        p = V((d.x * 0.0118, d.y * 0.0205, d.z * 0.0235))
        p.x += s * 0.002 * (1 - d.z * d.z)  # back of the hand slightly domed
        return w + p
    pt.sphere(palm, "skin", nu=12, nv=8)
    # Wrist into the cuff.
    pt.tube([w + V((0, 0.002, 0.012)), w + V((-s * 0.002, 0.004, 0.040))], lambda t, a: lerp(0.0125, 0.0138, t), "skin", segs=10)
    # Fingers: index (front) .. little (back). Knuckles at z 0.400 (Fingers1 head),
    # middle joints at 0.382 (Fingers2 head) so curls bend at the joints.
    for k, (dy, length, r) in enumerate(((-0.0135, 0.036, 0.0058), (-0.0045, 0.039, 0.0061), (0.0048, 0.037, 0.0058), (0.0135, 0.031, 0.0051))):
        base = V((s * 0.198, -0.024 + dy, 0.407))
        pts = [base + V((0, dy * 0.10 * t, -(0.007 + length) * t)) for t in [i / 8 for i in range(9)]]
        pt.tube(pts, lambda t, a, r=r: r * lerp(1.0, 0.80, t) * (1 + 0.07 * gauss(t - 0.55, 0.07)), "skin", segs=8)
    # Thumb: from the inner front of the palm, along the front, tip forward-down.
    tb = w + V((-s * 0.006, -0.016, 0.006))
    tpts = [tb, tb + V((-s * 0.004, -0.010, -0.010)), tb + V((-s * 0.006, -0.017, -0.022)), tb + V((-s * 0.006, -0.020, -0.033))]
    tpath = [catmull(tpts, i / 6) for i in range(7)]
    pt.tube(tpath, lambda t, a: 0.0075 * lerp(1.0, 0.82, t), "skin", segs=8)
    # Nails (tiny flattened caps on the finger backs).
    return pt


def build_feet():
    pt = Part("Feet")
    for s in (1, -1):
        a = V((s * 0.068, 0.012, 0.062))
        # Ankle / lower shin (rises into the thobe).
        pt.tube([a + V((0, 0.0, 0.10)), a + V((0, 0.0, 0.02)), a + V((0, -0.004, -0.012))],
                lambda t, ang: lerp(0.0175, 0.0195, t), "skin", segs=12, cap0=False)
        # Foot: a soft wedge from the heel to the toes.
        def foot(d, s=s):
            x = d.x * 0.024
            y = d.y * 0.056
            z = d.z * 0.017
            # flatter sole, toes lower than the instep, wider at the ball.
            z = z * (0.65 if d.z < 0 else 1.0) - 0.008 * smooth(0.0, -0.9, d.y)
            x *= 1.0 + 0.18 * smooth(0.2, -0.6, d.y)
            return V((s * 0.069 + x, -0.040 + y, 0.026 + z))
        pt.sphere(foot, "skin", nu=16, nv=10)
        # Big toe hint.
        pt.sphere(lambda d, s=s: V((s * 0.060, -0.093, 0.018)) + V((d.x * 0.0085, d.y * 0.011, d.z * 0.0078)), "skin", nu=8, nv=6)
        # Sandal (na'al): sole + broad strap + toe loop.
        def sole(d, s=s):
            p = V((d.x * 0.031, d.y * 0.064, d.z * 0.0055))
            p.x *= 1.0 + 0.12 * smooth(0.2, -0.7, d.y)
            return V((s * 0.069, -0.040, 0.0058)) + p
        pt.sphere(sole, "sandal", nu=20, nv=6)
        strap = [V((s * (0.069 + 0.028 * math.cos(a_)), -0.036, 0.012 + 0.024 * math.sin(a_))) for a_ in [math.pi * i / 10 for i in range(11)]]
        pt.tube(strap, lambda t, ang: 0.0045, "sandal", segs=6, squash=lambda t: (2.4, 0.7), twist_ref=V((0, 0, 1)))
    return pt


# ---- Head ---------------------------------------------------------------------------
def head_surface(d):
    """Skull/face surface along unit direction d from HEAD_C."""
    rx = 0.099
    ry = 0.103 if d.y < 0 else 0.112
    rz = 0.121 if d.z > 0 else 0.116
    p = V((d.x * rx, d.y * ry, d.z * rz))
    # Narrower jaw, softer chin.
    if d.z < 0:
        p.x *= 1.0 - 0.22 * (-d.z) ** 1.4
        p.y *= 1.0 - 0.06 * (-d.z) * smooth(0.0, -0.6, d.y)
    q = HEAD_C + p
    nrm = p.normalized()
    for s in (1, -1):
        e = EYE_C[s]
        de = (q - (e + V((0, 0.006, 0)))).length
        q -= nrm * 0.0105 * gauss(de, 0.016)          # eye socket
        q += nrm * 0.0055 * gauss((q - V((s * 0.040, -0.096, 1.073))).length, 0.016)  # brow ridge
        q += nrm * 0.0075 * gauss((q - V((s * 0.052, -0.088, 1.002))).length, 0.020)  # cheekbone
    return q


def nose_point(d):
    c = V((0.0, -0.106, 1.016))
    p = V((d.x * 0.0185, d.y * 0.020, d.z * 0.030))
    # Bulbous tip low and forward; bridge narrower.
    up = smooth(-0.2, 0.9, d.z)
    p.x *= 1.0 - 0.38 * up
    p.y *= 1.0 - 0.25 * up
    p.y -= 0.011 * gauss(d.z + 0.35, 0.35) * smooth(0.2, -0.8, d.y)
    p.z -= 0.004 * (1 - d.z * d.z)
    return c + p


def build_face():
    """Head skin, nose, ears hidden, eyes, lids, brows, mustache, mouth, beard."""
    pt = Part("Face")
    pt.sphere(head_surface, "face", nu=40, nv=28, uvf=lambda u, v: (u, v))
    pt.sphere(nose_point, "skin", nu=16, nv=12)
    for s in (1, -1):
        # Nostril wings.
        pt.sphere(lambda d, s=s: V((s * 0.0135, -0.110, 1.002)) + V((d.x * 0.0085, d.y * 0.009, d.z * 0.0075)), "skin", nu=10, nv=6)
        # Soft under-eye bags (age).
        e = EYE_C[s]
        pt.sphere(lambda d, e=e, s=s: e + V((s * 0.003, -0.002, -0.0225)) + V((d.x * 0.017, d.y * 0.0075, d.z * 0.006)), "skin", nu=12, nv=8)
    return pt


def build_eyes():
    pt = Part("Eyes")
    for s in (1, -1):
        e = EYE_C[s]
        # UV: front-facing azimuthal projection so the iris sits at the texture centre.
        def eye(d, e=e):
            return e + d * EYE_R

        def uvf(u, v, s=s):
            th = v * math.pi
            ph = u * 2 * math.pi
            d = V((math.sin(th) * math.sin(ph), -math.sin(th) * math.cos(ph), math.cos(th)))
            ang = math.acos(clamp(-d.y, -1, 1)) / math.pi  # 0 at the front pole
            az = math.atan2(d.z, d.x)
            return (0.5 + ang * math.cos(az), 0.5 + ang * math.sin(az))
        pt.sphere(eye, "eye", nu=20, nv=14, uvf=uvf)
    return pt


LID_R = EYE_R * 1.10
LID_UP = 0.46    # rest height of the upper lid edge (radians above the eye's front)
LID_LO = 0.52    # rest depth of the lower lid edge (radians below)


def lid_shell(s, upper):
    """Eyelid: a thin spherical band over the eye, rotated about the eye's x axis.
    The band reaches far behind the lid line so blinking never uncovers the eyeball."""
    e = EYE_C[s]
    rows = []
    nlat, nlon = 9, 16
    for i in range(nlat + 1):
        t = i / nlat
        row = []
        for j in range(nlon + 1):
            b = lerp(-1.65, 1.65, j / nlon)
            c = (b / 1.65) ** 2
            if upper:
                al = lerp(LID_UP + 2.3, LID_UP - 0.10 * c, t)   # from far behind to the edge
            else:
                al = lerp(-LID_LO - 2.0, -LID_LO + 0.12 * c, t)
            d = Quaternion(V((1, 0, 0)), -al) @ V((math.sin(b), -math.cos(b), 0))
            row.append(e + d * LID_R)
        rows.append(row)
    return rows


def build_lids():
    pt = Part("Lids")
    for s in (1, -1):
        for upper in (True, False):
            rows = lid_shell(s, upper)
            pt.grid(rows, "skin", flip=upper)
            edge = rows[-1]
            path = [p + (p - EYE_C[s]).normalized() * 0.0010 for p in edge[2:-2]]
            if upper:
                pt.tube(path, lambda t, a: 0.0019 * (0.5 + 0.5 * math.sin(math.pi * t)), "lash", segs=6)
            else:
                pt.tube(path, lambda t, a: 0.0013 * (0.5 + 0.5 * math.sin(math.pi * t)), "skin", segs=6)
    return pt


def brow_path(s):
    return [V((s * 0.016, -0.106, 1.071)), V((s * 0.034, -0.106, 1.079)), V((s * 0.052, -0.099, 1.078)),
            V((s * 0.068, -0.087, 1.068)), V((s * 0.078, -0.076, 1.054))]


def build_brows():
    """Bushy white brows: overlapping soft clumps along the brow line (reads as fluffy
    hair rather than a tube), the outer clumps drooping and flicking out with age."""
    pt = Part("Brows")
    for s_ in (1, -1):
        pts = brow_path(s_)
        n = 9
        for k in range(n):
            t = k / (n - 1)
            c = catmull(pts, t)
            tan = (catmull(pts, min(t + 0.05, 1)) - catmull(pts, max(t - 0.05, 0))).normalized()
            size = 0.0068 * (0.62 + 0.55 * math.sin(math.pi * clamp(t * 0.9 + 0.06)))
            lift = 0.0016 * math.sin(k * 2.3)
            c = c + V((0, -0.0015, lift))

            def clump(d, c=c, tan=tan, size=size, k=k):
                # elongated along the brow, flattened against the forehead
                side = tan.cross(V((0, 1, 0))).normalized()
                up = side.cross(tan).normalized() if side.length else V((0, 0, 1))
                q = tan * (d.x * size * 1.55) + V((0, d.y * size * 0.55, 0)) + V((0, 0, d.z * size * 0.75))
                q += tan * (0.0025 * max(d.x, 0) ** 3)  # pointed tips
                return c + q
            pt.sphere(clump, "hair", nu=10, nv=7)
        # Outer flick: a couple of longer wisps.
        for k in range(2):
            p0 = catmull(pts, 0.82 + 0.1 * k)
            tip = p0 + V((s_ * 0.010, 0.002, -0.004 - 0.003 * k))
            pt.tube([p0, p0.lerp(tip, 0.5) + V((0, -0.001, 0.0015)), tip],
                    lambda t, a: 0.0030 * (1 - t) ** 0.8 + 0.0004, "hair", segs=6, squash=lambda t: (1, 0.7))
    return pt


def build_mustache():
    pt = Part("Mustache")
    for s in (1, -1):
        pts = [V((s * 0.002, -0.118, 0.989)), V((s * 0.018, -0.120, 0.985)), V((s * 0.036, -0.113, 0.975)),
               V((s * 0.052, -0.100, 0.960)), V((s * 0.060, -0.090, 0.945))]
        path = [catmull(pts, i / 16) for i in range(17)]
        pt.tube(path, lambda t, a: 0.0115 * (0.55 + 0.55 * math.sin(math.pi * clamp(0.12 + t * 0.8))) * (1 + 0.1 * math.sin(a * 4 + t * 25)),
                "hair", segs=12, squash=lambda t: (1.0, 0.78))
    return pt


def build_mouth():
    pt = Part("Mouth")
    # Dark mouth interior and upper teeth sit behind the mustache; the jaw opens them.
    pt.sphere(lambda d: V((0.0, -0.080, 0.968)) + V((d.x * 0.020, d.y * 0.008, d.z * 0.008)), "mouth", nu=14, nv=8)
    pt.tube([V((x, -0.1040, 0.9765)) for x in (-0.014, -0.007, 0.0, 0.007, 0.014)], lambda t, a: 0.0030, "teeth", segs=8,
            squash=lambda t: (1.0, 0.7))
    lip = [V((x, -0.1075 + 0.011 * (x / 0.018) ** 2, 0.9625 + 0.0035 * (x / 0.018) ** 2)) for x in (-0.018, -0.009, 0.0, 0.009, 0.018)]
    pt.tube([catmull(lip, i / 10) for i in range(11)], lambda t, a: 0.0032 * (0.45 + 0.55 * math.sin(math.pi * t)), "lip", segs=8,
            squash=lambda t: (1.0, 0.8))
    return pt


# Beard side profile at the front (distance from the head axis, z), from where it
# leaves the skin under the lower lip, round the outside to the tip, then back under
# the jaw into the neck (hidden). Other azimuths scale and lift this profile.
BEARD_FRONT = [(0.084, 0.953), (0.100, 0.948), (0.111, 0.930), (0.113, 0.905), (0.104, 0.876),
               (0.084, 0.851), (0.058, 0.838), (0.040, 0.845), (0.034, 0.868), (0.036, 0.900), (0.040, 0.930)]


def beard_section(phi, n=15):
    f = abs(phi) / math.radians(100)  # 0 front .. 1 at the sideburns
    dirx, diry = math.sin(phi), -math.cos(phi)
    # Horizontal footprint: the jaw ellipse (narrower than deep).
    a, b = 0.098, 0.112
    scale = (a * b / math.hypot(b * math.sin(phi), a * math.cos(phi))) / b
    z_top = lerp(0.953, 1.040, smooth(0.15, 1.0, f) ** 0.9)
    z_tip = lerp(0.838, 0.950, smooth(0.0, 1.0, f) ** 1.3)
    z_tip += 0.005 * math.cos(phi * 10.0) * (1 - f)  # locks scallop the lower edge
    z0, z1 = BEARD_FRONT[0][1], BEARD_FRONT[6][1]
    pts = []
    for k, (sr, z) in enumerate(BEARD_FRONT):
        t = (z - z0) / (z1 - z0)
        zz = lerp(z_top, z_tip, t)
        sr = sr * scale * lerp(1.0, 0.94, f)
        if k == 0:
            sr = beard_skin(phi, zz) - 0.003
        pts.append(V((HEAD_C.x + dirx * sr, HEAD_C.y + diry * sr, zz)))
    return [catmull(pts, i / (n - 1)) for i in range(n)]


def beard_skin(phi, z):
    dz = clamp((z - HEAD_C.z) / 0.116, -0.95, 0.95)
    c = math.sqrt(1 - dz * dz)
    d = V((math.sin(phi) * c, -math.cos(phi) * c, dz))
    return (head_surface(d) - HEAD_C).xy.length


def build_beard():
    pt = Part("Beard")
    n = 33
    phis = [math.radians(lerp(-102, 102, j / (n - 1))) for j in range(n)]
    cols = [beard_section(ph) for ph in phis]
    rows = []
    for i in range(len(cols[0])):
        row = []
        for j, ph in enumerate(phis):
            p = cols[j][i]
            out = V((math.sin(ph), -math.cos(ph), 0))
            # Locks: soft grooves along the hair direction on the visible outside.
            g = 0.0032 * (abs(math.sin(ph * 12.0 + i * 0.10)) - 0.55) * smooth(1, 3, i) * smooth(10, 7, i)
            row.append(p + out * g)
        rows.append(row)
    pt.grid(rows, "hair", uvf=lambda u, v: (u * 3, v))
    return pt


# ---- Shemagh + agal -------------------------------------------------------------------
def env_radius(th, z):
    """Collision envelope the shemagh drapes over (scaled head, beard, neck, shoulders,
    chest). th: azimuth from the back (0 = back, +-pi = front); radius from the axis."""
    phi = math.copysign(math.pi - abs(th), th)  # 0 front
    dirx, diry = math.sin(phi), -math.cos(phi)
    r = 0.0
    zh = PIVOT.z + (z - PIVOT.z) / HEAD_K  # height in the unscaled head model
    dz = (zh - HEAD_C.z) / 0.121
    if abs(dz) < 1:
        d = V((dirx * math.sqrt(1 - dz * dz), diry * math.sqrt(1 - dz * dz), dz))
        r = max(r, (head_surface(d) - HEAD_C).xy.length * HEAD_K)
    if abs(phi) < math.radians(108) and 0.83 < zh < 1.045:
        best = 0.0
        for q in beard_section(phi, n=25)[:16]:
            if abs(q.z - zh) < 0.012:
                best = max(best, (q - HEAD_C).xy.length)
        r = max(r, best * HEAD_K)
    if 0.84 < z < 0.99:
        r = max(r, 0.05)
    if z < 0.89:
        r = max(r, body_radius(phi, z) + (0.005 if z < 0.86 else 0.0))
    return r


SHEMAGH_EDGE = [  # azimuth from the back (deg) -> height of the cloth's hem
    (0, 0.715), (30, 0.765), (62, 0.815), (88, 0.83), (104, 0.78), (114, 0.68), (122, 0.635),
    (127, 0.66), (131, 0.86), (134, 1.00), (138, 1.10), (148, 1.14), (166, 1.152), (180, 1.157)]


def shemagh_edge(deg):
    deg = abs(deg)
    for (a0, z0), (a1, z1) in zip(SHEMAGH_EDGE, SHEMAGH_EDGE[1:]):
        if deg <= a1:
            t = (deg - a0) / (a1 - a0)
            return lerp(z0, z1, 0.5 * t + 0.5 * smooth(0, 1, t))
    return SHEMAGH_EDGE[-1][1]


SHEMAGH_OFF = 0.016


def shemagh_polyline(deg):
    """Dense polyline of the cloth from the crown to the hem at azimuth deg."""
    th = math.radians(deg)
    phi = math.copysign(math.pi - abs(th), th)
    dirx, diry = math.sin(phi), -math.cos(phi)
    z_end = shemagh_edge(deg)
    pts = []
    # Over the skull: follow the head (scaled) by polar angle.
    for k in range(60):
        al = math.radians(1.5 * k)
        d = V((math.sin(al) * dirx, math.sin(al) * diry, math.cos(al)))
        q = head_surface(d)
        q = H(q) + (q - HEAD_C).normalized() * (SHEMAGH_OFF + 0.004 * smooth(0.5, 1.3, al))
        # Front: the folded edge stands off the forehead a little (crisp peak).
        q += (q - H(HEAD_C)).normalized() * 0.006 * smooth(152, 178, abs(deg)) * smooth(0.4, 0.9, al)
        if q.z < z_end or q.z < 1.03:
            break
        pts.append(q)
    # Below the ears: hang, resting on beard, neck and shoulders.
    z = pts[-1].z
    sr = (pts[-1] - H(HEAD_C)).xy.length
    while z > z_end + 1e-4:
        z = max(z - 0.006, z_end)
        loose = 0.010 * smooth(95, 120, abs(deg)) * smooth(0.80, 0.95, z) * smooth(1.08, 0.98, z)
        need = env_radius(th, z) + SHEMAGH_OFF + 0.004 + loose
        sr = max(need, sr - 0.45 * 0.006)  # falls in under its weight onto the body
        pts.append(V((dirx * sr, PIVOT.y + diry * sr, z)))
    return pts


def resample(pts, n):
    L = [0.0]
    for a, b in zip(pts, pts[1:]):
        L.append(L[-1] + (b - a).length)
    tot = L[-1]
    out = []
    k = 0
    for i in range(n):
        s = tot * i / (n - 1)
        while k < len(L) - 2 and L[k + 1] < s:
            k += 1
        t = (s - L[k]) / max(L[k + 1] - L[k], 1e-9)
        out.append(pts[k].lerp(pts[k + 1], clamp(t)))
    return out, tot


SHEMAGH_TILE = 0.23  # world size of one texture tile (10 motifs)


BAND = 0.032  # width of the patterned border at the hanging edges


def build_shemagh():
    pt = Part("Shemagh")
    nd_ = 64 if GAME else 80
    degs = [lerp(-180, 180, k / nd_) for k in range(nd_ + 1)]
    nv, nb = (22, 2) if GAME else (28, 3)
    cols, lens = [], []
    for d in degs:
        poly = shemagh_polyline(d)
        full, L = resample(poly, 200)
        main_L = max(L - BAND, L * 0.6)
        # main rows evenly up to the band, then nb band rows to the hem
        pts = []
        for i in range(nv):
            pts.append(arc_point(full, L, main_L * i / (nv - 1)))
        for i in range(1, nb + 1):
            pts.append(arc_point(full, L, lerp(main_L, L, i / nb)))
        cols.append(pts)
        lens.append(L)
    nr = nv + nb
    rows = [[cols[j][i] for j in range(len(degs))] for i in range(nr)]
    for i in range(nr):
        for j, d in enumerate(degs):
            p = rows[i][j]
            th = math.radians(d)
            low = smooth(1.02, 0.80, p.z)
            out = V((p.x, p.y - PIVOT.y, 0))
            if out.length > 1e-5:
                f = 0.0065 * math.sin(th * 7 + 0.5) + 0.0025 * math.sin(th * 17 + 1.0) + 0.0015 * math.sin(th * 31)
                rows[i][j] = p + out.normalized() * f * low
    girth = 2 * math.pi * 0.13
    nd = len(degs)

    def uvf(u, v):
        j = int(round(u * (nd - 1)))
        return (u * girth / SHEMAGH_TILE, v * lens[j] / SHEMAGH_TILE)

    def matf(i, j):
        # Border band only on the hanging edges (the fold over the forehead has none).
        if i >= nv - 1 and abs(degs[j]) <= 133 and abs(degs[j + 1]) <= 133:
            k = i - (nv - 1)
            return ("shemagh_border", lambda u, v, k=k: (u * girth / 0.06, (k + (v * (nr - 1) - i)) / nb))
        return None
    pt.grid(rows, "shemagh", uvf=uvf, matf=matf)
    hang = [j for j in range(nd) if abs(degs[j]) <= 133]
    pt.tube([rows[-1][j] for j in hang], lambda t, a: 0.0038, "shemagh_edge", segs=8, cap0=False, cap1=False)
    # Fringe: short twisted tassels along the hanging hem.
    hem = rows[-1]
    for j in range(0, nd - 1):
        if abs(degs[j]) > 131:
            continue
        for k in range(2):
            p0 = hem[j].lerp(hem[j + 1], 0.25 + 0.5 * k)
            tip = p0 + V((0, 0, -0.016))
            pt.tube([p0, p0.lerp(tip, 0.5), tip], lambda t, a: 0.0018 * (1 - 0.5 * t), "shemagh_edge", segs=5, cap0=False)
    return pt


def arc_point(pts, L, s):
    n = len(pts) - 1
    f = clamp(s / L) * n
    i = min(int(f), n - 1)
    return pts[i].lerp(pts[i + 1], f - i)


def build_agal():
    pt = Part("Agal")
    cz = H(V((0, 0, 1.112))).z
    for k, dz in enumerate((-0.0112, 0.0112)):
        ring = []
        for j in range(48):
            a = math.pi + 2 * math.pi * j / 48
            zz = cz + dz + 0.010 * math.cos(a)   # slightly higher at the front
            th = math.copysign(math.pi - abs(math.atan2(math.sin(a), math.cos(a))), math.sin(a))
            r = env_radius(th, zz) + SHEMAGH_OFF + 0.0145
            ring.append(V((math.sin(a) * r, PIVOT.y - math.cos(a) * r, zz)))
        ring.append(ring[0])
        pt.tube(ring, lambda t, a: 0.0124, "agal", segs=10, cap0=False, cap1=False, uvf=lambda u, v: (u, v * 14))
    for s in (1, -1):
        top = V((s * 0.016, 0.0, cz - 0.004))
        top.y = PIVOT.y + env_radius(0.0, top.z) + SHEMAGH_OFF + 0.008
        cord = [top + V((s * 0.003 * i, 0.006 * min(i, 2), -0.02 * i)) for i in range(7)]
        pt.tube(cord, lambda t, a: 0.0026, "agal", segs=6)
        tip = cord[-1]
        pt.sphere(lambda d, tip=tip: tip + V((d.x * 0.007, d.y * 0.007, d.z * 0.014 - 0.01)), "agal", nu=8, nv=6)
    return pt


# ---- Cane -----------------------------------------------------------------------------
def cane_points(grip):
    """Crook cane: shaft from the floor to just under the fist, a horizontal handle through
    the fist (front-back), then a hook that curls down at the front."""
    pts = []
    base = V((grip.x, grip.y + 0.012, 0.004))
    top = V((grip.x, grip.y + 0.012, grip.z - 0.004))
    for i in range(14):
        pts.append(base.lerp(top, i / 13))
    c = V((grip.x, grip.y - 0.006, grip.z + 0.002))
    for i in range(1, 15):
        a = math.pi * i / 14
        pts.append(c + V((0, 0.018 * math.cos(a), 0.017 * math.sin(a) * 1.15)))
    pts.append(pts[-1] + V((0, 0.0, -0.012)))
    return pts


def build_cane(name, grip, xform=None):
    pt = Part(name)
    pts = cane_points(grip)
    if xform:
        pts = [xform @ p for p in pts]
    n = len(pts)
    pt.tube(pts, lambda t, a: (0.0086 if t < 0.48 else 0.0068) * (1 + 0.03 * math.sin(t * 60)), "wood", segs=10,
            uvf=lambda u, v: (u, v * 8))
    # Brass ferrule at the foot.
    p0, p1 = pts[0], pts[1]
    pt.tube([p0 - (p1 - p0).normalized() * 0.002, p0 + (p1 - p0).normalized() * 0.018], lambda t, a: 0.0091, "brass", segs=10)
    return pt


# --------------------------------------------------------------------------------------
# Materials (preview + export). Godot reassigns tints for the wardrobe by name.
# --------------------------------------------------------------------------------------
def make_materials(tex):
    def mat(name, color, rough=0.8, image=None, sheen=0.0, sss=0.0, spec=0.35, normal=None, emit=None):
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        nt = m.node_tree
        bsdf = nt.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*color, 1)
        bsdf.inputs["Roughness"].default_value = rough
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = spec
        if sheen and "Sheen Weight" in bsdf.inputs:
            bsdf.inputs["Sheen Weight"].default_value = sheen
        if sss and "Subsurface Weight" in bsdf.inputs:
            bsdf.inputs["Subsurface Weight"].default_value = sss
            bsdf.inputs["Subsurface Radius"].default_value = (0.012, 0.004, 0.002)
            if "Subsurface Scale" in bsdf.inputs:
                bsdf.inputs["Subsurface Scale"].default_value = 0.6
        if image:
            t = nt.nodes.new("ShaderNodeTexImage")
            t.image = bpy.data.images.load(image)
            t.interpolation = "Cubic"
            nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
        if normal:
            t = nt.nodes.new("ShaderNodeTexImage")
            t.image = bpy.data.images.load(normal)
            t.image.colorspace_settings.name = "Non-Color"
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nm.inputs["Strength"].default_value = 0.8
            nt.links.new(t.outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
        return m

    def srgb(h):
        c = [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]
        return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)

    mat("skin", srgb("#c08a62"), 0.55, image=tex["skin"], sss=0.15, spec=0.4)
    mat("face", srgb("#c08a62"), 0.55, image=tex["face"], sss=0.15, spec=0.4, normal=tex["face_n"])
    mat("lip", srgb("#9c5e4c"), 0.5, sss=0.1)
    mat("eye", (1, 1, 1), 0.12, image=tex["eye"], spec=0.6)
    mat("lash", srgb("#5b4a40"), 0.8)
    mat("mouth", srgb("#3a1a16"), 0.7)
    mat("teeth", srgb("#efe6d6"), 0.35)
    mat("hair", srgb("#f1eee8"), 0.7, image=tex["hair"], sheen=0.4, normal=tex["hair_n"])
    mat("thobe", srgb("#f4f1ea"), 0.85, image=tex["thobe"], sheen=0.3, normal=tex["thobe_n"])
    mat("thobe_trim", srgb("#ece7dc"), 0.8, image=tex["thobe"], normal=tex["thobe_n"])
    mat("thobe_inner", srgb("#cfc8bb"), 0.9)
    mat("button", srgb("#d9cfb8"), 0.35, spec=0.5)
    mat("shemagh", (1, 1, 1), 0.8, image=tex["shemagh"], sheen=0.35, normal=tex["shemagh_n"])
    mat("shemagh_border", (1, 1, 1), 0.8, image=tex["shemagh_border"], sheen=0.3)
    mat("shemagh_edge", srgb("#efe8dc"), 0.85, sheen=0.3)
    mat("agal", srgb("#18161a"), 0.55, image=tex["agal"], sheen=0.25)
    mat("wood", (1, 1, 1), 0.5, image=tex["wood"], spec=0.45)
    mat("brass", srgb("#b8893c"), 0.3, spec=0.9)
    mat("sandal", srgb("#5a3622"), 0.6, image=tex["leather"])
    mat("bisht", srgb("#2a2018"), 0.85, sheen=0.5)
    mat("zari", srgb("#c9a04a"), 0.35, spec=0.8)
    mat("glasses", srgb("#3a2f28"), 0.3, spec=0.7)
    mat("misbaha", srgb("#7a2d22"), 0.25, spec=0.6)


# --------------------------------------------------------------------------------------
# Skin weights (analytic, evaluated on the final subdivided vertices)
# --------------------------------------------------------------------------------------
def seg_t(p, a, b):
    d = b - a
    return clamp((p - a).dot(d) / d.length_squared)


def bone_pts(name):
    for n, h, t, _ in BONES:
        if n == name:
            return V(h), V(t)


def w_torso(p):
    w = {}
    hips = smooth(0.64, 0.56, p.z)
    chest = smooth(0.66, 0.76, p.z)
    spine = max(0.0, 1.0 - hips - chest)
    w["Hips"], w["Spine"], w["Chest"] = hips, spine, chest
    # Neck/collar region
    neck = smooth(0.855, 0.89, p.z)
    if neck:
        for k in w:
            w[k] *= 1 - neck
        w["Neck"] = neck
    # Shoulders follow the arms a little.
    for s, side in ((1, "L"), (-1, "R")):
        sh = smooth(0.075, 0.122, s * p.x) * smooth(0.70, 0.80, p.z)
        if sh > 0:
            for k in list(w):
                w[k] *= 1 - sh * 0.65
            w["Clavicle." + side] = w.get("Clavicle." + side, 0) + sh * 0.35
            w["UpperArm." + side] = w.get("UpperArm." + side, 0) + sh * 0.30
    # Skirt follows the thighs and the flutter bones.
    leg = smooth(0.50, 0.20, p.z)
    if leg > 0:
        side = smooth(-0.05, 0.05, p.x)
        share = 0.46 * leg
        for k in list(w):
            w[k] *= 1 - share - 0.3 * leg
        w["Thigh.L"] = share * side
        w["Thigh.R"] = share * (1 - side)
        fl = 0.3 * leg
        ang = math.atan2(p.x, -p.y)  # 0 front
        cf = max(0.0, math.cos(ang)) ** 2
        cb = max(0.0, -math.cos(ang)) ** 2
        cl = max(0.0, math.sin(ang)) ** 2
        cr = max(0.0, -math.sin(ang)) ** 2
        tot = cf + cb + cl + cr
        w["Skirt.F"], w["Skirt.B"], w["Skirt.L"], w["Skirt.R"] = (fl * c / tot for c in (cf, cb, cl, cr))
    return w


def w_sleeve(p):
    s = 1 if p.x > 0 else -1
    side = "L" if s > 0 else "R"
    sh, el = bone_pts("UpperArm." + side)
    _, wr = bone_pts("LowerArm." + side)
    tu = seg_t(p, sh, el)
    tl = seg_t(p, el, wr)
    du = (p - sh.lerp(el, tu)).length
    dl = (p - el.lerp(wr, tl)).length
    w = {}
    # Root of the sleeve blends into the chest.
    root = smooth(0.12, 0.0, tu) * (1.0 if du <= dl else 0.0)
    elbow = gauss((p - el).length, 0.022)
    lower = 1.0 if dl < du else 0.0
    if lower:
        w["LowerArm." + side] = 1.0
        w["UpperArm." + side] = 0.5 * elbow
        hand = smooth(0.93, 1.0, tl) * 0.15
        w["Hand." + side] = hand
    else:
        w["UpperArm." + side] = 1.0 - root * 0.7
        w["LowerArm." + side] = 0.5 * elbow
        w["Chest"] = root * 0.45
        w["Clavicle." + side] = root * 0.25
    return w


def w_hand(p):
    s = 1 if p.x > 0 else -1
    side = "L" if s > 0 else "R"
    # Thumb region: front of the palm.
    th_h, th_t = bone_pts("Thumb." + side)
    f1h, f1t = bone_pts("Fingers1." + side)
    _, f2t = bone_pts("Fingers2." + side)
    w = {}
    tt = seg_t(p, th_h, th_t)
    d_th = (p - th_h.lerp(th_t, tt)).length
    d_f = math.hypot(p.x - th_h.x * 0.198 / 0.193, p.y + 0.0375) if p.z < 0.409 else 1.0
    if d_th < 0.011 and d_th < d_f and tt > 0.0:
        t = smooth(0.0, 0.5, seg_t(p, th_h, th_t))
        w["Thumb." + side] = t
        w["Hand." + side] = 1 - t
        return w
    z = p.z
    if z > f1h.z + 0.003:
        w["Hand." + side] = 1.0
        if z > 0.43:
            w["LowerArm." + side] = smooth(0.43, 0.45, z)
    else:
        a = smooth(f1h.z + 0.003, f1h.z - 0.003, z)
        b = smooth(f1t.z + 0.003, f1t.z - 0.003, z)
        w["Hand." + side] = 1 - a
        w["Fingers1." + side] = a * (1 - b)
        w["Fingers2." + side] = a * b
    return w


def w_feet(p):
    side = "L" if p.x > 0 else "R"
    if p.z > 0.075:
        return {"Shin." + side: 1.0}
    toe = smooth(-0.045, -0.06, p.y)
    ank = smooth(0.06, 0.075, p.z)
    return {"Foot." + side: (1 - toe) * (1 - ank), "Toe." + side: toe * (1 - ank), "Shin." + side: ank}


def w_head(p):
    return {"Head": 1.0}


def w_beard(p):
    p = Hinv(p)
    # Lower beard rides on the jaw.
    j = smooth(0.968, 0.935, p.z) * smooth(0.10, 0.0, abs(p.x)) * 0.85
    return {"Head": 1 - j, "Jaw": j}


def w_mouth(p):
    p = Hinv(p)
    j = 1.0 if p.z < 0.966 else 0.0
    return {"Head": 1 - j, "Jaw": j}


def w_eye(p):
    return {"Eye.L" if p.x > 0 else "Eye.R": 1.0}


def w_shemagh(p):
    th = math.atan2(p.x, p.y - PIVOT.y)  # 0 back, +-pi front
    deg = abs(math.degrees(th))
    head = smooth(0.95, 1.06, p.z)
    w = {"Head": head}
    rest = 1 - head
    if rest <= 0:
        return w
    # Over the shoulders the cloth lies on the chest/clavicles.
    side = "L" if p.x > 0 else "R"
    tail = smooth(100, 122, deg)
    back = smooth(70, 30, deg)
    mid = max(0.0, 1 - tail - back)
    if tail:
        lower = smooth(0.84, 0.74, p.z)
        w["Shemagh." + side] = rest * tail * (1 - lower)
        w["Shemagh.%s2" % side] = rest * tail * lower
    if back:
        lower = smooth(0.88, 0.78, p.z)
        w["Shemagh.B"] = rest * back * (1 - lower)
        w["Shemagh.B2"] = rest * back * lower
    if mid:
        w["Neck"] = rest * mid * 0.4
        w["Clavicle." + side] = rest * mid * 0.6
    return w


def w_cane(p):
    return {"Cane": 1.0}


def w_cane_arm(p):
    return {"CaneArm": 1.0}


def skin(obj, fn, arm):
    groups = {}
    for v in obj.data.vertices:
        w = fn(v.co.copy())
        tot = sum(w.values())
        if tot <= 0:
            continue
        for bone, val in w.items():
            if val / tot < 1e-3:
                continue
            g = groups.get(bone) or obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
            groups[bone] = g
            g.add([v.index], val / tot, "REPLACE")
    obj.parent = arm
    m = obj.modifiers.new("Armature", "ARMATURE")
    m.object = arm


def tag(obj, value):
    a = obj.data.attributes.new("part", "INT", "POINT")
    a.data.foreach_set("value", [value] * len(obj.data.vertices))


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs, selected_objects=objs):
        bpy.ops.object.join()
    o = objs[0]
    o.name = name
    o.data.name = name
    return o


# --------------------------------------------------------------------------------------
# Face shape keys (blend shapes): eyes, brows, mouth
# --------------------------------------------------------------------------------------
PART_IDS = {"skin": 1, "nose": 2, "lid_up": 3, "lid_lo": 4, "brow": 5, "mustache": 6, "mouth": 7, "beard": 8, "eye": 9}


def rot_about(p, c, axis, ang):
    return c + Quaternion(axis, ang) @ (p - c)


def face_keys(obj):
    me = obj.data
    part = [0] * len(me.vertices)
    me.attributes["part"].data.foreach_get("value", part)
    base = [v.co.copy() for v in me.vertices]
    obj.shape_key_add(name="Basis", from_mix=False)

    def key(name, fn):
        k = obj.shape_key_add(name=name, from_mix=False)
        for i, p in enumerate(base):
            q = fn(Hinv(p), part[i]) if part[i] else None
            if q is not None:
                k.data[i].co = H(q)
        return k

    def side(p):
        return 1 if p.x > 0 else -1

    def lid_rot(p, pid, up_ang, lo_ang, tilt=0.0):
        s = side(p)
        e = EYE_C[s]
        if pid == PART_IDS["lid_up"]:
            q = rot_about(p, e, V((1, 0, 0)), up_ang)
            if tilt:
                q = rot_about(q, e, V((0, 1, 0)), tilt * s)
            return q
        if pid == PART_IDS["lid_lo"]:
            return rot_about(p, e, V((1, 0, 0)), lo_ang)
        return None

    # Upper lid rest covers the top of the iris; positive x-rotation drops it to the front.
    key("blink", lambda p, pid: lid_rot(p, pid, 0.92, -0.06))
    key("eyes_wide", lambda p, pid: lid_rot(p, pid, -0.26, 0.10))
    # Happy squint: lower lids push up, upper lids drop a little (crescent eyes).
    def happy(p, pid):
        q = lid_rot(p, pid, 0.10, -0.66)
        if q is not None:
            return q
        if pid == PART_IDS["skin"]:
            s = side(p)
            g = gauss((p - V((s * 0.050, -0.09, 1.0))).length, 0.022)
            return p + V((0, -0.002, 0.007)) * g
        return None
    key("eyes_happy", happy)

    def brow(p, pid, up, inner, outer):
        if pid != PART_IDS["brow"]:
            # forehead skin follows a little
            if pid == PART_IDS["skin"] and p.z > 1.06 and p.y < -0.06:
                s = side(p)
                g = gauss(abs(p.x) - 0.045, 0.03) * smooth(1.06, 1.08, p.z)
                return p + V((0, 0, up * 0.35 * g))
            return None
        s = side(p)
        t = smooth(0.012, 0.08, abs(p.x))  # 0 inner .. 1 outer
        return p + V((0, 0, up + lerp(inner, outer, t)))
    key("brows_up", lambda p, pid: brow(p, pid, 0.0085, 0.0, 0.0))
    key("brows_angry", lambda p, pid: brow(p, pid, -0.002, -0.0065, 0.004))
    key("brows_sad", lambda p, pid: brow(p, pid, 0.002, 0.0065, -0.0045))
    key("brow_raise_L", lambda p, pid: brow(p, pid, 0.009, 0.0, 0.002) if p.x > 0 else None)

    def smile(p, pid):
        s = side(p)
        if pid == PART_IDS["mustache"]:
            t = smooth(0.0, 0.06, abs(p.x))
            return p + V((s * 0.004 * t, 0.001 * t, 0.009 * t * t))
        if pid == PART_IDS["mouth"]:
            t = smooth(0.0, 0.022, abs(p.x))
            return p + V((s * 0.003 * t, 0.0, 0.0055 * t * t))
        if pid == PART_IDS["skin"]:
            g = gauss((p - V((s * 0.050, -0.09, 0.985))).length, 0.022)
            return p + V((s * 0.002, -0.002, 0.006)) * g
        if pid == PART_IDS["beard"]:
            g = gauss((p - V((s * 0.05, -0.1, 0.955))).length, 0.03)
            return p + V((s * 0.002, -0.001, 0.005)) * g
        return None
    key("smile", smile)

    def frown(p, pid):
        s = side(p)
        if pid == PART_IDS["mustache"]:
            t = smooth(0.0, 0.06, abs(p.x))
            return p + V((0, 0, -0.006 * t * t))
        if pid == PART_IDS["mouth"]:
            t = smooth(0.0, 0.022, abs(p.x))
            return p + V((0, 0, -0.004 * t))
        return None
    key("frown", frown)

    def ooh(p, pid):
        if pid == PART_IDS["mouth"] and p.z > 0.966:
            return p + V((-p.x * 0.35, 0, 0.0))
        if pid == PART_IDS["mustache"]:
            return p + V((-p.x * 0.10, -0.002, 0.002))
        return None
    key("mouth_oo", ooh)

    def mouth_open(p, pid):
        # Lower lip and the lower beard drop; the dark interior swells forward into the gap.
        if pid == PART_IDS["mouth"]:
            if p.z < 0.966 and abs(p.x) < 0.03 and p.y < -0.1:
                return p + V((0, -0.002, -0.013))
            if p.y > -0.09:  # interior
                c = V((0.0, -0.080, 0.968))
                q = p - c
                return c + V((q.x * 1.05, q.y * 1.6 - 0.017, q.z * 1.9 - 0.004))
            return p + V((0, 0, 0.002))
        if pid == PART_IDS["beard"]:
            j = smooth(0.966, 0.93, p.z) * smooth(0.08, 0.0, abs(p.x))
            return p + V((0, -0.003, -0.013)) * j
        if pid == PART_IDS["mustache"]:
            return p + V((0, 0, 0.002)) * smooth(0.04, 0.0, abs(p.x))
        return None
    key("mouth_open", mouth_open)

    for kb in me.shape_keys.key_blocks:
        kb.slider_min = 0.0
        kb.slider_max = 1.0


# --------------------------------------------------------------------------------------
# Posing helpers (rotations about the parent's rest axes, in degrees)
# --------------------------------------------------------------------------------------
def rest_rot(arm, name):
    return arm.data.bones[name].matrix_local.to_quaternion()


def set_pose(arm, pose):
    """pose: {bone: (rx, ry, rz) degrees about armature axes, optional loc}."""
    for pb in arm.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = V()
        pb.scale = V((1, 1, 1))
    for name in pose.get("_hide", ()):
        arm.pose.bones[name].scale = V((0, 0, 0))
    for name, val in pose.items():
        if name.startswith("_"):
            continue
        rot = val[0] if isinstance(val[0], (tuple, list)) else val
        loc = val[1] if isinstance(val[0], (tuple, list)) and len(val) > 1 else None
        r = rest_rot(arm, name)
        q = Quaternion(V((1, 0, 0)), math.radians(rot[0])) @ Quaternion(V((0, 1, 0)), math.radians(rot[1])) @ Quaternion(V((0, 0, 1)), math.radians(rot[2]))
        pb = arm.pose.bones[name]
        pb.rotation_quaternion = r.inverted() @ q @ r
        if loc:
            pb.location = r.inverted() @ V(loc)


def pose_stand():
    """Relaxed standing pose with the cane: slight stoop, right fist on the crook."""
    return {
        "Hips": ((0, 2, 0), (-0.004, 0, -0.004)), "Spine": (4, -1.5, 0), "Chest": (3, -1.5, 2), "Neck": (-4, 0, 0), "Head": (-3, 2, -3),
        "Thigh.L": (-3, -2, 0), "Shin.L": (6, 0, 0), "Foot.L": (-3, 0, 6), "Thigh.R": (1, 2, 0), "Foot.R": (0, 0, -4),
        "UpperArm.L": (-4, 0, 6), "LowerArm.L": (-20, 0, 0), "Hand.L": (-6, 0, 4),
        "Fingers1.L": (0, 22, 0), "Fingers2.L": (0, 25, 0), "Thumb.L": (0, 10, 0),
        "UpperArm.R": (-10, 0, -2), "LowerArm.R": (-12, 0, 0), "Hand.R": (0, 0, 0),
        "Fingers1.R": (0, -62, 0), "Fingers2.R": (0, -80, 0), "Thumb.R": (0, -35, 10),
        "Cane": (22, 0, 0),
        "_hide": ["CaneArm"],
    }


def pose_walk():
    """Mid-stride: left foot forward, cane planted ahead with the right hand."""
    return {
        "Hips": ((0, 0, 6), (0, 0, -0.012)), "Spine": (5, 0, -4), "Chest": (3, 0, -5), "Neck": (-4, 0, 3), "Head": (-3, 0, 3),
        "Thigh.L": (-24, 0, 0), "Shin.L": (8, 0, 0), "Foot.L": (14, 0, 0),
        "Thigh.R": (16, 0, 0), "Shin.R": (24, 0, 0), "Foot.R": (-12, 0, 0), "Toe.R": (18, 0, 0),
        "Skirt.F": (-8, 0, 0), "Skirt.B": (6, 0, 0),
        "UpperArm.L": (14, 0, 3), "LowerArm.L": (-10, 0, 0), "Fingers1.L": (0, 22, 0), "Fingers2.L": (0, 25, 0),
        "UpperArm.R": (-26, 0, -3), "LowerArm.R": (-14, 0, 0),
        "Fingers1.R": (0, -62, 0), "Fingers2.R": (0, -80, 0), "Thumb.R": (0, -35, 10),
        "Cane": (30, 0, 0),
        "_hide": ["CaneArm"],
    }


def pose_think():
    """Stroking the beard, head tilted, weight on the cane."""
    return {
        "Spine": (5, 0, 0), "Chest": (2, 0, 4), "Neck": (-2, 0, 4), "Head": (-6, 4, 8),
        "Clavicle.L": (0, 0, 6),
        "UpperArm.L": (-38, -6, -28), "LowerArm.L": (-118, 0, -10), "Hand.L": (-10, 0, 18),
        "Fingers1.L": (0, 35, 0), "Fingers2.L": (0, 40, 0), "Thumb.L": (0, 20, 0),
        "UpperArm.R": (-12, 0, -2), "LowerArm.R": (-14, 0, 0),
        "Fingers1.R": (0, -62, 0), "Fingers2.R": (0, -80, 0), "Thumb.R": (0, -35, 10),
        "Cane": (26, 0, 0),
        "_hide": ["CaneArm"],
    }


def pose_ardah():
    """Ardah: the cane raised high in the right hand, chest proud, left arm out."""
    return {
        "Hips": ((0, 0, -4), (0, 0, -0.006)), "Spine": (-3, 3, 0), "Chest": (-4, 3, 0), "Neck": (2, 0, 0), "Head": (-6, -5, -4),
        "Thigh.L": (-6, 0, 0), "Shin.L": (10, 0, 0), "Foot.L": (-4, 0, 0),
        "Thigh.R": (4, 0, 0), "Shin.R": (6, 0, 0),
        "Clavicle.R": (0, 0, 0), "UpperArm.R": (-150, 0, 18), "LowerArm.R": (-22, 0, 0), "Hand.R": (-10, 0, 0),
        "Fingers1.R": (0, -62, 0), "Fingers2.R": (0, -80, 0), "Thumb.R": (0, -35, 10),
        "UpperArm.L": (-30, -42, 0), "LowerArm.L": (-40, 0, 0), "Hand.L": (0, -10, 0),
        "Fingers1.L": (0, 15, 0), "Fingers2.L": (0, 15, 0),
        "Skirt.L": (0, -6, 0), "Skirt.R": (0, -4, 0),
        "_hide": ["CaneArm"],
    }


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    tex = shaib_textures.paint_all(os.path.join(SRC, "textures"))
    make_materials(tex)
    arm = build_armature()

    objs = []

    def mk(part, mats, fn, sub=1, pid=0, solid=0.0, head=False):
        if head:
            part.v = [H(p) for p in part.v]
        o = part_object(part, mats, subdiv=sub, solidify=solid)
        tag(o, pid)
        skin(o, fn, arm)
        objs.append(o)
        return o

    # Body (skin, eyes, face hair, sandals): one mesh, several materials.
    body = []
    body.append(mk(build_face(), ["face", "skin"], w_head, sub=1, pid=PART_IDS["skin"], head=True))
    body.append(mk(build_eyes(), ["eye"], w_eye, sub=1, pid=PART_IDS["eye"], head=True))
    lids = build_lids()
    lids.v = [H(p) for p in lids.v]
    lo = part_object(lids, ["skin", "lash"], subdiv=1, solidify=0.0012)
    # tag upper vs lower lid by height relative to the eye centre
    vals = [PART_IDS["lid_up"] if Hinv(v.co).z > EYE_C[1].z - 0.002 else PART_IDS["lid_lo"] for v in lo.data.vertices]
    a = lo.data.attributes.new("part", "INT", "POINT")
    a.data.foreach_set("value", vals)
    skin(lo, w_head, arm)
    body.append(lo)
    body.append(mk(build_brows(), ["hair"], w_head, sub=1, pid=PART_IDS["brow"], head=True))
    body.append(mk(build_mustache(), ["hair"], w_head, sub=1, pid=PART_IDS["mustache"], head=True))
    body.append(mk(build_mouth(), ["mouth", "teeth", "lip"], w_mouth, sub=1, pid=PART_IDS["mouth"], head=True))
    body.append(mk(build_beard(), ["hair"], w_beard, sub=2, pid=PART_IDS["beard"], head=True))
    for s in (1, -1):
        h = build_hand(s)
        h.name = "Hand" + ("L" if s > 0 else "R")
        body.append(mk(h, ["skin"], w_hand, sub=1))
    body.append(mk(build_feet(), ["skin", "sandal"], w_feet, sub=1))
    body_obj = join(body, "Body")
    face_keys(body_obj)

    thobe = join([mk(build_thobe(), ["thobe", "thobe_trim", "button"], w_torso, sub=1, solid=0.004),
                  mk(build_sleeves(), ["thobe", "thobe_inner"], w_sleeve, sub=1, solid=0.003)], "Thobe")
    shemagh = join([mk(build_shemagh(), ["shemagh", "shemagh_border", "shemagh_edge"], w_shemagh, sub=1, solid=0.003),
                    mk(build_agal(), ["agal"], w_head, sub=1)], "Shemagh")
    cane = mk(build_cane("Cane", HAND_GRIP), ["wood", "brass"], w_cane, sub=1)
    # Forearm copy: crook over the forearm, hanging straight down.
    ch, _ = bone_pts("CaneArm")
    xf = Matrix.Translation(ch + V((0.0, 0.0, -0.0)) - HAND_GRIP + V((0, 0.006, -0.002)))
    cane_arm = mk(build_cane("CaneArm", HAND_GRIP, xform=xf), ["wood", "brass"], w_cane_arm, sub=1)
    bisht = join([mk(build_bisht(), ["bisht", "zari"], lambda q: w_sleeve(q) if abs(q.x) > 0.105 and q.z > 0.6 and q.z < 0.84 else w_torso(q), sub=1, solid=0.004)], "Bisht")
    glasses = mk(build_glasses(), ["glasses"], w_head, sub=0, head=True)
    glasses.name = "Glasses"
    misbaha = mk(build_misbaha(), ["misbaha", "zari"], lambda q: {"Hand.L": 1.0}, sub=0)
    misbaha.name = "Misbaha"
    wardrobe = [bisht, glasses, misbaha]
    for o in wardrobe:
        o.hide_render = True  # worn only when chosen in the wardrobe
    for o in (body_obj, thobe, shemagh, cane, cane_arm):
        print("%s: %d verts, %d tris" % (o.name, len(o.data.vertices), sum(len(p.vertices) - 2 for p in o.data.polygons)))
    os.makedirs(SRC, exist_ok=True)
    import shaib_anim
    shaib_anim.build_actions(arm, set_pose, only=os.environ.get("SHAIB_CLIPS", "").split(",") if os.environ.get("SHAIB_CLIPS") else None)
    for pb in arm.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = V()
        pb.scale = V((1, 1, 1))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "shaib.blend"))
    print("saved", os.path.join(SRC, "shaib.blend"))
    if GAME:
        export_glb(arm, [body_obj, thobe, shemagh, cane, cane_arm] + wardrobe)


def export_glb(arm, meshes):
    path = os.path.join(OUT, "shaib.glb")
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    for o in meshes:
        # the part tag is a build-time helper only
        if "part" in o.data.attributes:
            o.data.attributes.remove(o.data.attributes["part"])
        o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=False,
        export_animations=True, export_animation_mode="ACTIONS", export_skins=True,
        export_def_bones=False, export_optimize_animation_size=True, export_image_format="AUTO",
        export_materials="EXPORT", export_texcoords=True, export_normals=True, export_frame_range=False,
        export_morph=True, export_morph_normal=False, export_force_sampling=True,
    )
    print("exported", path, os.path.getsize(path) // 1024, "KB")


if __name__ == "__main__":
    main()
