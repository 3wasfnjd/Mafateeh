"""The desert camp's vehicles and sheep pen, from the owner's Motri repository (Folio 2025 by
Bruno Simon, MIT; see assets/world/props/README.md). Level 4 uses them.

Inputs (exported from Motri's own model code by tools/motri/export_models.mjs and
tools/motri/export_vehicles.mjs; not in this repo):
  --camp camel_camp.glb   the camel camp: its six-wheel water tanker becomes wayit, and its
                          drinking trough trough
  --pen sheep_pen.glb     the sheep pen: fence, shade, feeders and flock become sheep_pen;
                          its parked Datsun feed pickup (hay and alfalfa in the bed) becomes datsun
  --shas shas.glb         the parked 2026 Land Cruiser single cab beside the camp
Outputs to assets/world/props/: shas, datsun, wayit, trough, sheep_pen (vertex colours, origin at the
middle of the footprint on the ground, vehicles facing +Z in Godot). Faces in a vehicle's body
colour get their own material, paint_<name>, so the game can repaint each parked car.

Usage: python3 tools/blender/import_motri_camp.py -- --camp a.glb --pen b.glb --shas c.glb
"""
import os
import sys

import bpy  # noqa: I001
import bmesh
from mathutils import Matrix, Vector as V

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
A = sys.argv[sys.argv.index("--") + 1:]


def arg(k):
    return A[A.index(k) + 1]


ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "world", "props")


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def load(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def vc_material(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.9
    c = nt.nodes.new("ShaderNodeVertexColor")
    nt.links.new(c.outputs["Color"], b.inputs["Base Color"])
    return m


def join(objs, name):
    objs = [o for o in objs if o.type == "MESH"]
    for o in objs:
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
    with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs, selected_objects=objs):
        bpy.ops.object.join()
    o = objs[0]
    o.name = o.data.name = name
    return o


def srgb_to_lin(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return V([x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c])


def keep_box(o, cx, cy, hx, hy):
    """Deletes the faces whose centre lies outside the box (Blender x, y)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    dead = [f for f in bm.faces if not (abs(f.calc_center_median().x - cx) < hx and abs(f.calc_center_median().y - cy) < hy)]
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    bm.to_mesh(o.data)
    bm.free()


def finish(o, name, paint=None, yaw=0.0):
    """Centre the footprint on the origin, ground it, one vertex-colour material, and the
    faces in `paint` (hex) on a second material paint_<name>."""
    me = o.data
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    me.transform(Matrix.Rotation(yaw, 4, "Z") @ Matrix.Translation((-(min(xs) + max(xs)) / 2, -(min(ys) + max(ys)) / 2, 0)))
    low = min(v.co.z for v in me.vertices)
    me.transform(Matrix.Translation((0, 0, -low)))
    me.materials.clear()
    me.materials.append(vc_material("motri_" + name))
    if paint:
        me.materials.append(vc_material("paint_" + name))
        col = me.color_attributes[0]
        want = srgb_to_lin(paint)
        for p in me.polygons:
            if col.domain == "POINT":
                c = sum((V(col.data[i].color[:3]) for i in p.vertices), V()) / len(p.vertices)
            else:
                c = sum((V(col.data[i].color[:3]) for i in p.loop_indices), V()) / len(p.loop_indices)
            p.material_index = 1 if (c - want).length < 0.03 else 0
    for p in me.polygons:
        p.use_smooth = False
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_materials="EXPORT", export_vertex_color="MATERIAL", export_apply=True)
    me.calc_loop_triangles()
    print("exported", name, os.path.getsize(path) // 1024, "KB", len(me.loop_triangles), "tris",
          "size %.2f x %.2f x %.2f" % tuple(o.dimensions))


def shas():
    reset()
    o = join(load(arg("--shas")), "shas")
    finish(o, "shas", paint="#c9b58d")


def datsun_and_pen():
    reset()
    objs = load(arg("--pen"))
    pickup = next(o for o in objs if o.name.startswith("SheepPen_FeedPickup"))
    rest = [o for o in objs if o.type == "MESH" and o is not pickup]
    o = join([pickup], "datsun")
    finish(o, "datsun", paint="#eeeadd")
    pen = join(rest, "sheep_pen")
    # drop the flat sand pad and parking bay under it: the diorama has its own ground
    bm = bmesh.new()
    bm.from_mesh(pen.data)
    dead = [f for f in bm.faces if max(v.co.z for v in f.verts) < 0.06]
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    bm.to_mesh(pen.data)
    bm.free()
    finish(pen, "sheep_pen")


def wayit_and_trough():
    for name, box in (("wayit", (5.2, 2.5, 1.25, 3.2)),     # the tanker (three.js x 5.2, z -2.5)
                      ("trough", (2.97, 2.2, 0.62, 1.3))):  # the camels' drinking trough
        reset()
        objs = load(arg("--camp"))
        props = next(o for o in objs if o.name.startswith("CamelCamp_Tent_Tanker_Trough"))
        props = join([props], name)
        keep_box(props, *box)
        finish(props, name)


shas()
datsun_and_pen()
wayit_and_trough()
