"""Najdi modular construction kit for Mafateeh (Blender 5.2, fully procedural).

    python -m bpy build_kit.py -- <out_dir>     (or: blender -b -P build_kit.py -- <out_dir>)

Writes <out_dir>/najdi_kit.glb (runtime) and art_source/kit/najdi_kit.blend (editable).
Each piece is a separate object named as the game looks it up (Kit.piece()).
Conventions (Godot axes after export: x right, y up, z toward the viewer):
  normalised pieces (wall_segment, wall_post, corner_tower) are 1 x 1 x 1 and centred,
  so the level builder scales them to any length without moving their origin;
  everything else is modelled at final board-unit size, centred unless noted.
"""
import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = ARGS[0] if ARGS else os.path.join(HERE, "../../assets/kit")
SRC = os.path.join(HERE, "../../art_source/kit")
rng = random.Random(1744)


def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


MAT = {}


def mat(name, hexcol, rough=0.85, metal=0.0, emit=0.0):
    if name in MAT:
        return MAT[name]
    m = bpy.data.materials.new(name)
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    col = (*srgb(hexcol), 1.0)
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit:
        bsdf.inputs["Emission Color"].default_value = col
        bsdf.inputs["Emission Strength"].default_value = emit
    m.diffuse_color = col
    MAT[name] = m
    return m


def materials():
    return {
        "plaster": mat("plaster", "c8935f", 0.95),
        "stone": mat("stone", "d9c29a", 0.9),
        "stone_dark": mat("stone_dark", "b39a72", 0.9),
        "wood": mat("wood", "6e4426", 0.8),
        "wood_dark": mat("wood_dark", "4a2c18", 0.8),
        "paint_ochre": mat("paint_ochre", "c8902f", 0.75),
        "paint_teal": mat("paint_teal", "3f7f7a", 0.75),
        "paint_red": mat("paint_red", "9c3b2a", 0.75),
        "iron": mat("iron", "2a2522", 0.5, 0.5),
        "brass": mat("brass", "d0a24a", 0.35, 0.8),
        "trunk": mat("trunk", "7a5a3a", 0.95),
        "leaf": mat("leaf", "5f7d38", 0.8),
        "leaf_dark": mat("leaf_dark", "4c6a2e", 0.85),
        "dates": mat("dates", "b5612a", 0.6),
        "glass": mat("lantern_glass", "ffcf7a", 0.3, 0.0, 2.5),
    }


# ----------------------------------------------------------------------------------
# Small bmesh helpers
# ----------------------------------------------------------------------------------

def new_obj(name, bm, mats):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = True
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    return obj


def box(bm, size, center=(0, 0, 0), mat_index=0):
    geom = bmesh.ops.create_cube(bm, size=1.0)["verts"]
    bmesh.ops.scale(bm, vec=Vector(size), verts=geom)
    bmesh.ops.translate(bm, vec=Vector(center), verts=geom)
    for f in {f for v in geom for f in v.link_faces}:
        f.material_index = mat_index
    return geom


def cyl(bm, r1, r2, h, segs, center=(0, 0, 0), mat_index=0, rot=None):
    geom = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=h)["verts"]
    if rot is not None:
        bmesh.ops.rotate(bm, verts=geom, cent=Vector(), matrix=rot)
    bmesh.ops.translate(bm, vec=Vector(center), verts=geom)
    for f in {f for v in geom for f in v.link_faces}:
        f.material_index = mat_index
    return geom


def sphere(bm, r, center, mat_index=0, subdiv=2, scale=(1, 1, 1)):
    geom = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=r)["verts"]
    bmesh.ops.scale(bm, vec=Vector(scale), verts=geom)
    bmesh.ops.translate(bm, vec=Vector(center), verts=geom)
    for f in {f for v in geom for f in v.link_faces}:
        f.material_index = mat_index
    return geom


def bevel_edges(bm, edges, offset, segs=2):
    if edges:
        bmesh.ops.bevel(bm, geom=list(edges), offset=offset, segments=segs, profile=0.5, affect="EDGES",
                        clamp_overlap=True)


def jitter(verts, amount, axes=(1, 1, 1)):
    for v in verts:
        v.co += Vector((rng.uniform(-1, 1) * amount * axes[0], rng.uniform(-1, 1) * amount * axes[1],
                        rng.uniform(-1, 1) * amount * axes[2]))


def box_uv(bm, scale=1.0):
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for l in f.loops:
            c = l.vert.co
            u, v = [(c.y, c.z), (c.x, c.z), (c.x, c.y)][ax]
            l[uv].uv = (u * scale, v * scale)


# ----------------------------------------------------------------------------------
# Pieces
# ----------------------------------------------------------------------------------

def floor_tile(M):
    bm = bmesh.new()
    box(bm, (0.975, 0.975, 0.15))
    bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if all(abs(v.co.z - 0.075) < 1e-4 for v in e.verts)],
                              cuts=3, use_grid_fill=True)
    top = [v for v in bm.verts if v.co.z > 0.07]
    for v in top:
        v.co.z += rng.uniform(-0.004, 0.006)
    bevel_edges(bm, [e for e in bm.edges if all(v.co.z > 0.06 for v in e.verts) and e.is_boundary is False
                     and abs(e.verts[0].co.z - e.verts[1].co.z) < 0.02 and
                     (abs(e.verts[0].co.x) > 0.45 or abs(e.verts[0].co.y) > 0.45)], 0.022, 2)
    box_uv(bm, 1.0)
    return new_obj("floor_tile", bm, [M["stone"]])


def wall_segment(M):
    bm = bmesh.new()
    box(bm, (1, 1, 1))
    bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=3, use_grid_fill=True)
    jitter(bm.verts, 0.012)
    bevel_edges(bm, [e for e in bm.edges if all(v.co.z > 0.45 for v in e.verts) and
                     all(abs(v.co.y) > 0.45 for v in e.verts)], 0.16, 3)
    box_uv(bm)
    return new_obj("wall_segment", bm, [M["plaster"]])


def wall_post(M, name="wall_post", r_top=0.5, segs=16):
    bm = bmesh.new()
    cyl(bm, 0.5, r_top, 1.0, segs)
    jitter([v for v in bm.verts if abs(v.co.z) < 0.49], 0.008)
    bevel_edges(bm, [e for e in bm.edges if all(v.co.z > 0.49 for v in e.verts) and
                     abs((e.verts[0].co.xy).length - r_top) < 0.01 and abs((e.verts[1].co.xy).length - r_top) < 0.01],
                0.12, 3)
    box_uv(bm)
    return new_obj(name, bm, [M["plaster"]])


def crenel(M):
    # Stepped triangular merlon (sharafat) of Najdi parapets: 0.22 wide, 0.22 tall.
    bm = bmesh.new()
    steps = [(0.22, -0.11, -0.05), (0.15, -0.05, 0.01), (0.09, 0.01, 0.06)]
    for w, z0, z1 in steps:
        box(bm, (w, 0.16, z1 - z0), (0, 0, (z0 + z1) / 2))
    cyl(bm, 0.045, 0.0, 0.05, 4, (0, 0, 0.085), rot=Matrix.Rotation(math.pi / 4, 3, "Z"))
    box_uv(bm)
    return new_obj("crenel", bm, [M["plaster"]])


def door_leaf(M):
    # Painted Najdi door: vertical planks, battens, iron studs, triangle motif band.
    bm = bmesh.new()
    w, h, d = 0.6, 1.3, 0.07
    planks = 4
    for i in range(planks):
        x = -w / 2 + (i + 0.5) * w / planks
        box(bm, (w / planks - 0.008, d, h), (x, 0, 0), 0)
    for z in (-0.45, 0.0, 0.45):
        box(bm, (w * 0.98, 0.02, 0.07), (0, -d / 2 - 0.008, z), 1)
        for i in range(5):
            sphere(bm, 0.012, (-w / 2 + 0.07 + i * (w - 0.14) / 4, -d / 2 - 0.02, z), 3, 1)
    # Painted triangles near the top (ochre/teal alternating).
    for i in range(5):
        x = -w / 2 + 0.06 + i * 0.12
        tri = bmesh.ops.create_cone(bm, cap_ends=True, segments=3, radius1=0.05, radius2=0.05, depth=0.006)["verts"]
        bmesh.ops.rotate(bm, verts=tri, cent=Vector(), matrix=Matrix.Rotation(math.pi / 2, 3, "X"))
        bmesh.ops.rotate(bm, verts=tri, cent=Vector(), matrix=Matrix.Rotation(math.pi / 2 if i % 2 else -math.pi / 2, 3, "Y"))
        bmesh.ops.translate(bm, vec=Vector((x, -d / 2 - 0.004, 0.56)), verts=tri)
        for f in {f for v in tri for f in v.link_faces}:
            f.material_index = 2 if i % 2 else 4
    box(bm, (0.05, 0.03, 0.12), (w / 2 - 0.09, -d / 2 - 0.02, 0.05), 3)  # latch
    box_uv(bm, 2.0)
    return new_obj("door_leaf", bm, [M["wood"], M["wood_dark"], M["paint_ochre"], M["iron"], M["paint_teal"]])


def gate_pillar(M):
    bm = bmesh.new()
    box(bm, (0.36, 0.5, 1.55))
    top = [v for v in bm.verts if v.co.z > 0]
    for v in top:
        v.co.x *= 0.9
        v.co.y *= 0.92
    bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=2, use_grid_fill=True)
    jitter(bm.verts, 0.006)
    box_uv(bm)
    return new_obj("gate_pillar", bm, [M["plaster"]])


def arch(M):
    # Lintel over a passage with a raised triangular crown and beam ends.
    bm = bmesh.new()
    box(bm, (1.7, 0.32, 0.22))
    cyl(bm, 0.2, 0.0, 0.16, 4, (0, 0, 0.19), rot=Matrix.Rotation(math.pi / 4, 3, "Z"))
    for x in (-0.6, -0.2, 0.2, 0.6):
        box(bm, (0.06, 0.42, 0.06), (x, 0, -0.06), 1)
    box_uv(bm)
    return new_obj("arch", bm, [M["plaster"], M["wood"]])


def pool_edge(M):
    bm = bmesh.new()
    box(bm, (0.15, 2.3, 0.19))
    bevel_edges(bm, [e for e in bm.edges if all(v.co.z > 0.09 for v in e.verts)], 0.03, 2)
    box_uv(bm)
    return new_obj("pool_edge", bm, [M["stone_dark"]])


def stepping_stone(M):
    bm = bmesh.new()
    cyl(bm, 0.38, 0.42, 0.12, 12)
    for v in bm.verts:
        a = math.atan2(v.co.y, v.co.x)
        k = 1 + 0.08 * math.sin(a * 3 + 1) + 0.05 * math.sin(a * 5)
        v.co.x *= k
        v.co.y *= k
        if v.co.z > 0:
            v.co.z += rng.uniform(-0.01, 0.01)
    bevel_edges(bm, [e for e in bm.edges if all(v.co.z > 0.05 for v in e.verts) and e.is_manifold], 0.03, 2)
    box_uv(bm)
    return new_obj("stepping_stone", bm, [M["stone"]])


def crate(M):
    bm = bmesh.new()
    box(bm, (0.94, 0.94, 0.94), mat_index=0)
    for a in (-1, 1):
        for b in (-1, 1):
            box(bm, (1.0, 0.08, 0.08), (0, a * 0.48, b * 0.48), 1)
            box(bm, (0.08, 1.0, 0.08), (a * 0.48, 0, b * 0.48), 1)
            box(bm, (0.08, 0.08, 1.0), (a * 0.48, b * 0.48, 0), 1)
    # Diagonal braces on the four sides.
    for side in range(4):
        rot = Matrix.Rotation(side * math.pi / 2, 3, "Z")
        g = box(bm, (1.22, 0.04, 0.08), (0, 0, 0), 1)
        bmesh.ops.rotate(bm, verts=g, cent=Vector(), matrix=Matrix.Rotation(math.pi / 4, 3, "Y"))
        bmesh.ops.translate(bm, vec=Vector((0, -0.48, 0)), verts=g)
        bmesh.ops.rotate(bm, verts=g, cent=Vector(), matrix=rot)
    for a in (-1, 1):
        for b in (-1, 1):
            for c in (-1, 1):
                sphere(bm, 0.025, (a * 0.5, b * 0.5, c * 0.43), 2, 1)
    box_uv(bm, 2.0)
    return new_obj("crate", bm, [M["wood"], M["wood_dark"], M["iron"]])


def mud_brick(M):
    bm = bmesh.new()
    box(bm, (0.92, 0.56, 0.4))
    bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=2, use_grid_fill=True)
    jitter(bm.verts, 0.012)
    box_uv(bm)
    obj = new_obj("mud_brick", bm, [M["plaster"]])
    mod = obj.modifiers.new("Soft", "BEVEL")
    mod.width = 0.04
    mod.segments = 2
    mod.limit_method = "ANGLE"
    return obj


def key(M):
    # Ornate brass key standing upright: bow ring on top, shaft, two-tooth bit.
    bm = bmesh.new()
    n, m = 24, 8
    R, r = 0.12, 0.035
    rows = []
    for i in range(n):
        a = 2 * math.pi * i / n
        row = []
        for j in range(m):
            c = 2 * math.pi * j / m
            p = Vector(((R + r * math.cos(c)) * math.cos(a), r * math.sin(c), (R + r * math.cos(c)) * math.sin(a) + 0.16))
            row.append(bm.verts.new(p))
        rows.append(row)
    for i in range(n):
        for j in range(m):
            bm.faces.new([rows[i][j], rows[(i + 1) % n][j], rows[(i + 1) % n][(j + 1) % m], rows[i][(j + 1) % m]])
    cyl(bm, 0.03, 0.03, 0.42, 10, (0, 0, -0.1))
    sphere(bm, 0.045, (0, 0, 0.03), 0, 1)
    box(bm, (0.13, 0.05, 0.05), (0.06, 0, -0.26))
    box(bm, (0.1, 0.05, 0.04), (0.05, 0, -0.17))
    box_uv(bm)
    return new_obj("key", bm, [M["brass"]])


def palm(M, name="palm", height=2.7, fronds=13, seed=3):
    r = random.Random(seed)
    bm = bmesh.new()
    # Trunk: stacked, slightly offset rings give the date palm's rough bark.
    rings = 14
    lean = Vector((r.uniform(-0.12, 0.12), r.uniform(-0.12, 0.12), 0))
    for i in range(rings):
        t = i / rings
        z = t * height
        c = lean * t * t + Vector((0, 0, z + height / rings / 2))
        rad = 0.11 - 0.025 * t
        cyl(bm, rad * 1.12, rad, height / rings * 1.02, 9, c, 0, rot=Matrix.Rotation(r.uniform(0, 1), 3, "Z"))
    top = lean + Vector((0, 0, height))
    # Fronds: arched midribs with leaflet blades.
    for k in range(fronds):
        az = 2 * math.pi * k / fronds + r.uniform(-0.15, 0.15)
        up = r.uniform(0.25, 0.75)
        length = r.uniform(1.0, 1.35)
        pts = []
        for s in range(9):
            u = s / 8
            ang = up - u * u * 1.6
            pts.append(top + Vector((math.cos(az) * math.cos(ang) * u * length,
                                     math.sin(az) * math.cos(ang) * u * length,
                                     math.sin(ang) * u * length * 0.8)))
        side = Vector((-math.sin(az), math.cos(az), 0))
        prev = None
        for s in range(8):
            a, b = pts[s], pts[s + 1]
            w = 0.16 * math.sin(math.pi * (s + 0.5) / 8) + 0.02
            droop = Vector((0, 0, -0.06 * (s / 8)))
            v = [bm.verts.new(a + side * w + droop), bm.verts.new(a - side * w + droop),
                 bm.verts.new(b - side * w * 0.9 + droop), bm.verts.new(b + side * w * 0.9 + droop),
                 bm.verts.new(a), bm.verts.new(b)]
            f1 = bm.faces.new([v[4], v[0], v[3], v[5]])
            f2 = bm.faces.new([v[4], v[5], v[2], v[1]])
            for f in (f1, f2):
                f.material_index = 1 if k % 3 else 2
    # Date clusters under the crown.
    for k in range(4):
        az = k * math.pi / 2 + 0.4
        sphere(bm, 0.09, top + Vector((math.cos(az) * 0.14, math.sin(az) * 0.14, -0.18)), 3, 1, (1, 1, 1.4))
    box_uv(bm)
    return new_obj(name, bm, [M["trunk"], M["leaf"], M["leaf_dark"], M["dates"]])


def shrub(M):
    bm = bmesh.new()
    for i in range(7):
        a = i * 2.4
        rr = 0.12 if i else 0.0
        sphere(bm, rng.uniform(0.11, 0.16), (math.cos(a) * rr, math.sin(a) * rr, 0.13 + rng.uniform(0, 0.08)),
               i % 2, 1, (1, 1, 0.8))
    jitter(bm.verts, 0.02)
    box_uv(bm)
    return new_obj("shrub", bm, [M["leaf"], M["leaf_dark"]])


def tree(M):
    # Small lote (sidr) tree: short trunk and a rounded, clumped canopy.
    bm = bmesh.new()
    cyl(bm, 0.07, 0.05, 0.8, 8, (0, 0, 0.4), 0)
    for i in range(9):
        a = i * 2.2
        rr = 0.0 if i == 0 else rng.uniform(0.18, 0.32)
        sphere(bm, rng.uniform(0.2, 0.3), (math.cos(a) * rr, math.sin(a) * rr, 0.95 + rng.uniform(-0.1, 0.15)),
               1 + i % 2, 1, (1, 1, 0.85))
    jitter([v for v in bm.verts if v.co.z > 0.7], 0.03)
    box_uv(bm)
    return new_obj("tree", bm, [M["trunk"], M["leaf"], M["leaf_dark"]])


def lantern(M):
    bm = bmesh.new()
    box(bm, (0.12, 0.12, 0.02), (0, 0, 0.01), 0)
    box(bm, (0.09, 0.09, 0.14), (0, 0, 0.1), 1)
    for a in (-1, 1):
        for b in (-1, 1):
            box(bm, (0.015, 0.015, 0.16), (a * 0.05, b * 0.05, 0.1), 0)
    cyl(bm, 0.085, 0.01, 0.07, 4, (0, 0, 0.215), 0, rot=Matrix.Rotation(math.pi / 4, 3, "Z"))
    cyl(bm, 0.012, 0.012, 0.06, 8, (0, 0, 0.27), 0)
    box_uv(bm)
    return new_obj("lantern", bm, [M["brass"], M["glass"]])


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    M = materials()
    objs = [floor_tile(M), wall_segment(M), wall_post(M), wall_post(M, "corner_tower", 0.45, 18), crenel(M),
            door_leaf(M), gate_pillar(M), arch(M), pool_edge(M), stepping_stone(M), crate(M), mud_brick(M), key(M),
            palm(M), palm(M, "palm_small", 1.9, 11, 9), shrub(M), tree(M), lantern(M)]
    # Lay pieces out in a row in the .blend for editing; export each at the origin.
    for i, o in enumerate(objs):
        o["kit_piece"] = True
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(SRC, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(os.path.join(OUT, "najdi_kit.glb")), export_format="GLB",
                              use_selection=True, export_yup=True, export_apply=True, export_materials="EXPORT",
                              export_animations=False)
    for i, o in enumerate(objs):
        o.location.x = (i % 6) * 3.0
        o.location.y = (i // 6) * 3.0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(os.path.join(SRC, "najdi_kit.blend")))
    for o in objs:
        print("%-16s %6d verts" % (o.name, len(o.data.vertices)))


if __name__ == "__main__":
    main()
