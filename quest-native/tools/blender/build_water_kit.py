"""Water pieces for the Diriyah kit, made from the owner's reference renders
(art_source/world/kit_refs/w1_basin, w2_channel, w3_well): textures are cut from those images.

  water_basin    2.2 x 2.2 m stone basin with an inlet notch on its -Y side
  water_channel  2 m straight stone channel (falaj) along Y; chains with the basin inlet
  well           stone well, two wooden posts, beam, pulley, rope and bucket

Metres, origin on the ground, front = -Y in Blender (+Z in Godot). Writes assets/world/kit/.
Usage: python3 tools/blender/build_water_kit.py
"""
import math
import os

import bpy  # noqa: I001
import bmesh
import numpy as np
from mathutils import Matrix, Vector as V
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
REFS = os.path.join(ROOT, "art_source", "world", "kit_refs")
TEX = os.path.join(ROOT, "art_source", "world", "textures")
OUT = os.path.join(ROOT, "assets", "world", "kit")
os.makedirs(TEX, exist_ok=True)


def tileable(img, n):
    a = np.asarray(img.convert("RGB").resize((n, n)), float)
    b = np.roll(np.roll(a, n // 2, 0), n // 2, 1)
    y, x = np.mgrid[0:n, 0:n]
    d = np.minimum(np.minimum(x, n - 1 - x), np.minimum(y, n - 1 - y)) / (n / 2)
    w = np.clip((d - 0.05) / 0.35, 0, 1)[..., None]
    return Image.fromarray((a * w + b * (1 - w)).clip(0, 255).astype(np.uint8))


def sandstone(n=256, seed=4):
    """Fine porous sandstone in the basin render's colour, lighter towards the middle."""
    import sys
    sys.path.insert(0, HERE)
    import house_textures as HT
    big = HT.tile_noise(n, seed, (4, 8, 16), 1.5)
    fine = HT.tile_noise(n, seed + 1, (64, 128, 256), 1.15)
    base = np.array([210, 170, 127], float)
    a = base * (0.9 + 0.14 * big[..., None]) * (0.93 + 0.12 * fine[..., None])
    rng = np.random.default_rng(seed)
    pores = rng.random((n, n)) > 0.996
    a[pores] *= 0.55
    y, x = np.mgrid[0:n, 0:n] / (n - 1)
    edge = np.minimum(np.minimum(x, 1 - x), np.minimum(y, 1 - y))
    a *= (0.86 + 0.14 * np.clip(edge / 0.12, 0, 1))[..., None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def textures():
    basin = Image.open(os.path.join(REFS, "w1_basin.png")).convert("RGB")
    well = Image.open(os.path.join(REFS, "w3_well.png")).convert("RGB")
    out = {}

    def save(name, im):
        p = os.path.join(TEX, "water_%s.jpg" % name)
        im.save(p, quality=88)
        out[name] = p
    save("block", sandstone())  # dressed sandstone, the basin's colour (sampled: 210, 170, 127)
    save("water", tileable(basin.crop((450, 450, 850, 650)), 256))       # clear water over sand
    save("ring", well.crop((300, 830, 900, 1050)).resize((512, 188)))    # coursed well stones
    save("beam", well.crop((340, 105, 930, 160)).resize((512, 48)))
    save("post", well.crop((262, 70, 350, 530)).resize((48, 256)))
    save("bucket", well.crop((600, 578, 740, 758)).resize((128, 160)))
    return out


bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
_m = {}


def mat(name, path=None, color=None, rough=0.95):
    if name in _m:
        return _m[name]
    m = bpy.data.materials.new("water_" + name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = rough
    if path:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(path)
        nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    if color:
        b.inputs["Base Color"].default_value = (*color, 1)
    _m[name] = m
    return m


def link(bm, name, mats):
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    sc.collection.objects.link(o)
    for m in mats:
        me.materials.append(m)
    return o


def stone_block(bm, uv, size, at, rot=0.0, bevel=0.025):
    """A dressed stone: bevelled box, each face showing the whole stone texture.
    Built in its own bmesh (bevel replaces faces), then appended to `bm`."""
    b = bmesh.new()
    u = b.loops.layers.uv.new("UVMap")
    bmesh.ops.create_cube(b, size=1)
    bmesh.ops.scale(b, vec=size, verts=b.verts)
    bmesh.ops.bevel(b, geom=list(b.edges), offset=bevel, segments=1, affect="EDGES")
    b.normal_update()
    for f in b.faces:
        n = f.normal
        ax = max(range(3), key=lambda k: abs(n[k]))
        i0, i1 = [k for k in range(3) if k != ax]
        cs = [lp.vert.co for lp in f.loops]
        lo0, lo1 = -size[i0] / 2, -size[i1] / 2
        for lp in f.loops:
            c = lp.vert.co
            lp[u].uv = ((c[i0] - lo0) / size[i0], (c[i1] - lo1) / size[i1])
    bmesh.ops.rotate(b, verts=b.verts, matrix=Matrix.Rotation(rot, 3, "Z"))
    bmesh.ops.translate(b, verts=b.verts, vec=at)
    me = bpy.data.meshes.new("_tmp")
    b.to_mesh(me)
    b.free()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)


def water_plane(name, x0, x1, y0, y1, z, m):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.verify()
    f = bm.faces.new([bm.verts.new(p) for p in ((x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z))])
    for lp in f.loops:
        lp[uv].uv = (lp.vert.co.x / 0.9, lp.vert.co.y / 0.9)
    return link(bm, name, [m])


def basin(T):
    stone = mat("block", T["block"])
    water = mat("water", T["water"], rough=0.2)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    S, w, h = 2.2, 0.24, 0.32           # outer size, rim stone width, rim height
    half = S / 2
    # four sides of stones ~0.7 m long; the -Y side keeps a 0.32 m inlet in the middle
    for side in range(4):
        a = side * math.pi / 2
        d = V((math.cos(a), math.sin(a), 0))   # outward normal of this side
        t = V((-d.y, d.x, 0))
        L = S - 2 * w  # the corner stones fill the last w at each end
        n = 3
        for i in range(n):
            u0 = -L / 2 + i * L / n
            u1 = u0 + L / n
            if side == 3 and i == 1:          # -Y side: two short stones either side of the inlet
                for a0, a1 in ((u0, -0.2), (0.2, u1)):
                    c = d * (half - w / 2) + t * ((a0 + a1) / 2) + V((0, 0, h / 2))
                    stone_block(bm, uv, (a1 - a0 - 0.02, w, h), c, a + math.pi / 2)
                continue
            c = d * (half - w / 2) + t * ((u0 + u1) / 2 + w / 2 * (1 if side % 2 else -1) * 0) + V((0, 0, h / 2))
            stone_block(bm, uv, (L / n - 0.02, w, h), c, a + math.pi / 2)
        # corner stone
        c = (d + t) * (half - w / 2) + V((0, 0, h / 2))
        stone_block(bm, uv, (w, w, h), c, a)
    # floor slab under the water
    stone_block(bm, uv, (S - 0.1, S - 0.1, 0.08), V((0, 0, 0.04)), 0, bevel=0.01)
    o = link(bm, "WaterBasin", [stone])
    wp = water_plane("BasinWater", -half + w, half - w, -half + w, half - w, h * 0.72, water)
    wp.parent = o
    return o


def channel(T, length=2.0):
    stone = mat("block", T["block"])
    water = mat("water", T["water"], rough=0.2)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    inner, w, h = 0.36, 0.2, 0.3
    n = 3
    for s in (-1, 1):
        for i in range(n):
            y0 = -length / 2 + i * length / n
            c = V((s * (inner / 2 + w / 2), y0 + length / n / 2, h / 2))
            stone_block(bm, uv, (w, length / n - 0.02, h), c)
    stone_block(bm, uv, (inner + 0.02, length, 0.07), V((0, 0, 0.035)), 0, bevel=0.01)  # bed
    o = link(bm, "WaterChannel", [stone])
    wp = water_plane("ChannelWater", -inner / 2, inner / 2, -length / 2, length / 2, h * 0.6, water)
    wp.parent = o
    return o


def ring(bm, uv, r0, r1, z0, z1, a0, a1, seg=4):
    """A curved stone between angles a0..a1 (radians), radii r0..r1, heights z0..z1."""
    rows = []
    for k in range(seg + 1):
        a = a0 + (a1 - a0) * k / seg
        c, s = math.cos(a), math.sin(a)
        rows.append([bm.verts.new((r * c, r * s, z)) for r, z in ((r1, z0), (r1, z1), (r0, z1), (r0, z0))])
    faces = []
    for k in range(seg):
        A, B = rows[k], rows[k + 1]
        for q in range(4):
            faces.append((bm.faces.new([A[q], B[q], B[(q + 1) % 4], A[(q + 1) % 4]]), q, k))
    for end, flip in ((rows[0], True), (rows[-1], False)):
        f = bm.faces.new(end[::-1] if flip else end)
        faces.append((f, 4, 0))
    for f, q, k in faces:
        for lp in f.loops:
            co = lp.vert.co
            ang = (math.atan2(co.y, co.x) - a0) / max(a1 - a0, 1e-4)
            if q in (0, 2):        # outer / inner face: around x up
                lp[uv].uv = (ang, (co.z - z0) / (z1 - z0))
            else:                  # top / bottom / ends: around x across
                lp[uv].uv = (ang, (math.hypot(co.x, co.y) - r0) / (r1 - r0))


def well(T):
    stone = mat("block", T["block"])
    beam = mat("beam", T["beam"], rough=0.85)
    post = mat("post", T["post"], rough=0.85)
    bucket = mat("bucket", T["bucket"], rough=0.8)
    rope = mat("rope", None, (0.55, 0.43, 0.27))
    dark = mat("deep", None, (0.04, 0.035, 0.03))
    bm = bmesh.new()
    uv = bm.loops.layers.uv.verify()
    r0, r1, course = 0.44, 0.68, 0.25
    for c in range(3):
        n = 10
        off = (c % 2) * 0.5
        for i in range(n):
            a0 = (i + off) / n * math.tau + 0.012
            a1 = (i + 1 + off) / n * math.tau - 0.012
            ring(bm, uv, r0, r1, c * course + 0.006, (c + 1) * course - 0.006, a0, a1)
    o = link(bm, "Well", [stone])
    # the dark shaft, a little below the rim
    bm = bmesh.new()
    g = bmesh.ops.create_circle(bm, cap_ends=True, segments=20, radius=r0 + 0.01)
    bmesh.ops.translate(bm, verts=g["verts"], vec=(0, 0, 0.35))
    shaft = link(bm, "Shaft", [dark])
    shaft.parent = o
    # posts, beam, pulley, rope, bucket
    parts = []
    for s in (-1, 1):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1)
        bmesh.ops.scale(bm, vec=(0.13, 0.13, 1.75), verts=bm.verts)
        bmesh.ops.translate(bm, verts=bm.verts, vec=(s * (r0 + 0.14), 0, 0.875))
        u = bm.loops.layers.uv.verify()
        for f in bm.faces:
            for lp in f.loops:
                lp[u].uv = (0.5 + (lp.vert.co.x + lp.vert.co.y) * 3, lp.vert.co.z / 1.75)
        parts.append(link(bm, "Post", [post]))
    bm = bmesh.new()
    g = bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.075, radius2=0.075, depth=1.6)
    bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, 1.62))
    u = bm.loops.layers.uv.verify()
    for f in bm.faces:
        for lp in f.loops:
            c = lp.vert.co
            lp[u].uv = ((c.x + 0.8) / 1.6, 0.5 + math.atan2(c.z - 1.62, c.y) / math.tau)
    parts.append(link(bm, "Beam", [beam]))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.11, radius2=0.11, depth=0.05)
    bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, 1.48))
    parts.append(link(bm, "Pulley", [beam]))
    for x in (-0.1, 0.1):  # the rope, down both sides of the pulley
        bm = bmesh.new()
        L = 1.48 - 0.78 if x < 0 else 1.48 - 0.95
        bmesh.ops.create_cone(bm, cap_ends=False, segments=5, radius1=0.012, radius2=0.012, depth=L)
        bmesh.ops.translate(bm, verts=bm.verts, vec=(x, 0, 1.48 - L / 2))
        parts.append(link(bm, "Rope", [rope]))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=0.12, radius2=0.14, depth=0.22)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(-0.1, 0, 0.67))
    u = bm.loops.layers.uv.verify()
    for f in bm.faces:
        for lp in f.loops:
            c = lp.vert.co
            lp[u].uv = (0.5 + math.atan2(c.y, c.x + 0.1) / math.tau, (c.z - 0.56) / 0.22)
    parts.append(link(bm, "Bucket", [bucket]))
    for p in parts:
        p.parent = o
    return o


def export(o, name):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    for c in o.children_recursive:
        c.select_set(True)
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_materials="EXPORT", export_apply=True)
    tris = 0
    for ob in [o] + list(o.children_recursive):
        if ob.type == "MESH":
            ob.data.calc_loop_triangles()
            tris += len(ob.data.loop_triangles)
    print("exported", name, os.path.getsize(path) // 1024, "KB", tris, "tris")


def main():
    T = textures()
    export(basin(T), "water_basin")
    export(channel(T), "water_channel")
    export(well(T), "well")


main()
