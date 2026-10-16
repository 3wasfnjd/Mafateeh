"""The Kalashnikov the old men fire for joy at the end of level 10 (the owner's reference
picture: a classic wooden AK). Each part is its outline traced from the picture (pixels,
x along the rifle, y down) and pushed out to its thickness, bevelled a little; the barrel,
gas tube and muzzle are cylinders. Wood and dark worn steel.

Writes assets/world/props/rifle.glb. In it the rifle stands up: muzzle at the top (+y in
Godot), the pistol grip at the origin, where the hand holds it. 0.88 m long.
Usage: python3 tools/blender/build_rifle.py
"""
import os

import bpy  # noqa: I001  (bpy first: it makes bmesh importable)
import bmesh

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "world", "props", "rifle.glb")

PX = 0.88 / 1960.0          # metres per pixel of the reference picture
GRIP = (650.0, 430.0)       # the hand's place in the picture (the origin)


def p2m(x, y):
    """Picture pixel to metres: along the rifle -> blender z (up), picture up -> blender x."""
    return ((GRIP[1] - y) * PX, (x - GRIP[0]) * PX)


def mat(name, rgb, rough, metal):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


def slab(name, pts, thick, material, bevel=0.0025):
    """An outline (picture pixels) pushed out to `thick` metres, centred on the rifle's middle."""
    bm = bmesh.new()
    verts = []
    for x, y in pts:
        u, w = p2m(x, y)
        verts.append(bm.verts.new((u, -thick / 2, w)))
    face = bm.faces.new(verts)
    bmesh.ops.recalc_face_normals(bm, faces=[face])
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    moved = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=moved, vec=(0, thick, 0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(material)
    if bevel > 0:
        mod = ob.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
    return ob


def rod(name, x0, x1, y, r_px, material, segs=12):
    """A cylinder along the rifle from picture x0 to x1 at height y."""
    u, w0 = p2m(x0, y)
    _, w1 = p2m(x1, y)
    bpy.ops.mesh.primitive_cylinder_add(vertices=segs, radius=r_px * PX, depth=w1 - w0, location=(u, 0, (w0 + w1) / 2))
    ob = bpy.context.active_object
    ob.name = name
    ob.data.materials.append(material)
    bpy.ops.object.shade_smooth()
    return ob


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    wood = mat("rifle_wood", (0.3, 0.09, 0.025), 0.5, 0.0)   # (linear: a deep orange-brown)
    steel = mat("rifle_steel", (0.07, 0.07, 0.075), 0.42, 0.75)
    # the stock: a long wedge to the butt plate
    slab("Stock", [(25, 300), (548, 238), (575, 240), (575, 352), (420, 400), (190, 520), (60, 572), (25, 568)], 0.046, wood)
    slab("ButtPlate", [(12, 296), (32, 294), (40, 572), (18, 574)], 0.05, steel)
    # the receiver and its cover, the rear sight block
    slab("Receiver", [(575, 238), (612, 150), (1118, 146), (1180, 228), (1180, 345), (575, 352)], 0.05, steel)
    slab("RearSight", [(1118, 132), (1262, 140), (1268, 232), (1118, 232)], 0.046, steel)
    slab("Lever", [(712, 262), (860, 242), (935, 252), (930, 270), (760, 300), (712, 298)], 0.056, steel, 0.0015)
    # the pistol grip and the trigger guard
    slab("Grip", [(600, 352), (735, 360), (712, 470), (690, 570), (640, 602), (560, 586), (585, 470)], 0.036, wood)
    slab("TriggerGuard", [(745, 352), (760, 432), (890, 432), (905, 355), (890, 355), (878, 418), (772, 418), (760, 352)], 0.012, steel, 0.0)
    # the curved magazine, in three straight-ish sections
    slab("Magazine", [(935, 345), (1085, 352), (1130, 440), (1180, 520), (1250, 578), (1205, 668), (1130, 655), (1060, 570), (1000, 480), (945, 410)], 0.03, steel)
    # the handguards (wood, upper and lower) and their steel bands
    slab("UpperGuard", [(1282, 142), (1528, 146), (1528, 226), (1282, 226)], 0.05, wood)
    slab("LowerGuard", [(1182, 232), (1530, 236), (1522, 330), (1215, 348), (1182, 342)], 0.056, wood)
    slab("Band", [(1528, 150), (1560, 150), (1560, 330), (1528, 330)], 0.06, steel)
    # gas tube, barrel, front sight, muzzle
    rod("GasTube", 1556, 1700, 188, 30, steel)
    rod("Barrel", 1556, 1945, 262, 20, steel)
    rod("Muzzle", 1880, 1975, 262, 27, steel)
    slab("FrontSightBlock", [(1690, 228), (1830, 232), (1838, 296), (1690, 296)], 0.04, steel)
    slab("FrontSight", [(1812, 250), (1846, 118), (1890, 118), (1898, 250)], 0.03, steel)
    # stand it up: along the rifle is blender z already; export
    for o in bpy.context.scene.objects:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True,
                              export_materials="EXPORT", export_apply=True, export_animations=False)
    tris = 0
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            o.data.calc_loop_triangles()
            tris += len(o.data.loop_triangles)
    print("exported rifle", os.path.getsize(OUT) // 1024, "KB", tris, "tris; muzzle at",
          round(p2m(1975, 262)[1], 3), "m up")


main()
