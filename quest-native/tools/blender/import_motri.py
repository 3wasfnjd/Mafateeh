"""Props taken from the owner's Motri repository (github.com/3wasfnjd/Motri), which is based on
Folio 2025 by Bruno Simon (MIT licence, see assets/world/props/README.md).

Inputs (not in this repo):
  --camp, --pen, --birds  GLBs exported from Motri's code-built models (CamelCampModel,
                          SheepPenModel, RestHousePoultryModel) by tools/motri/export_models.mjs
  --motri                 path to a Motri checkout (for the crate, lantern and palette)
Outputs to assets/world/props/ (vertex colours, no textures, origin on the ground, Z-up in
Blender = Y-up in Godot): camel_standing, camel_kneeling, camel_calf, tent, sheep, hen,
rooster, crate, lantern.

Usage: python3 tools/blender/import_motri.py -- --camp a.glb --pen b.glb --birds c.glb --motri DIR
"""
import math
import os
import sys

import bpy  # noqa: I001
import bmesh
from mathutils import Matrix, Vector as V

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "world", "props")
A = sys.argv[sys.argv.index("--") + 1:]


def arg(k):
    return A[A.index(k) + 1]


os.makedirs(OUT, exist_ok=True)

# Motri camel placements (three.js metres, relative to the camp centre): x, z, yaw
CAMELS = {"camel_standing": ("Standing", 0, 0, (-5.4, -0.4, 0.5)),
          "camel_calf": ("Standing", 3, 3, (5.0, 4.8, -1.8)),
          "camel_kneeling": ("Kneeling", 0, 4, (-4.2, 4.6, 0.25))}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def vc_material():
    m = bpy.data.materials.get("props_vc")
    if m:
        return m
    m = bpy.data.materials.new("props_vc")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.9
    c = nt.nodes.new("ShaderNodeVertexColor")
    nt.links.new(c.outputs["Color"], b.inputs["Base Color"])
    return m


def load(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def join(objs, name):
    objs = [o for o in objs if o.type == "MESH"]
    for o in objs:  # bake transforms
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
    with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs, selected_objects=objs):
        bpy.ops.object.join()
    o = objs[0]
    o.name = o.data.name = name
    return o


def finish(o, at, yaw=0.0):
    """Move `at` (x, y in Blender) to the origin, undo the yaw, drop to the ground."""
    o.data.transform(Matrix.Rotation(-yaw, 4, "Z") @ Matrix.Translation((-at[0], -at[1], 0)))
    low = min(v.co.z for v in o.data.vertices)
    o.data.transform(Matrix.Translation((0, 0, -low)))
    o.data.materials.clear()
    o.data.materials.append(vc_material())
    for p in o.data.polygons:
        p.use_smooth = False


def export(o, name):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_materials="EXPORT", export_vertex_color="MATERIAL", export_apply=True)
    o.data.calc_loop_triangles()
    print("exported", name, os.path.getsize(path) // 1024, "KB", len(o.data.loop_triangles), "tris")


def by_name(objs, prefix):
    return {o.name: o for o in objs if o.name.startswith(prefix)}


def near(objs, c, r):
    out = []
    for o in objs:
        if o.type != "MESH":
            continue
        cen = sum((o.matrix_world @ v.co for v in o.data.vertices), V()) / max(1, len(o.data.vertices))
        if (V((cen.x, cen.y)) - V((c.x, c.y))).length < r:
            out.append(o)
    return out


def centre(o):
    return sum((o.matrix_world @ v.co for v in o.data.vertices), V()) / len(o.data.vertices)


def camels():
    for name, (kind, body_i, head_i, (x, z, yaw)) in CAMELS.items():
        reset()
        objs = load(arg("--camp"))
        body = next(o for o in objs if o.name.startswith("CamelCamp_%sBodies_%d" % (kind, body_i)))
        head = next(o for o in objs if o.name.startswith("CamelCamp_AnimatedNecksHeads_%d" % head_i))
        o = join([body, head], name)
        finish(o, (x, -z), yaw)
        if name == "camel_calf":  # Motri scales the calf per instance at run time
            o.data.transform(Matrix.Scale(0.68, 4))
        export(o, name)


def tent():
    reset()
    objs = load(arg("--camp"))
    props = next(o for o in objs if o.name.startswith("CamelCamp_Tent_Tanker_Trough"))
    props.data.transform(props.matrix_world)
    props.matrix_world = Matrix.Identity(4)
    tx, ty = -1.3, 5.1  # tent centre in Blender coords (three.js z = -5.1)
    bm = bmesh.new()
    bm.from_mesh(props.data)
    dead = [f for f in bm.faces if not (abs(f.calc_center_median().x - tx) < 3.45 and abs(f.calc_center_median().y - ty) < 2.6)]
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    bm.to_mesh(props.data)
    bm.free()
    props.name = props.data.name = "tent"
    finish(props, (tx, ty))
    export(props, "tent")


def flock(path, body_prefix, head_prefix, leg_prefix, out_name, index=0, reach=0.45):
    reset()
    objs = load(path)
    bodies = sorted([o for o in objs if o.name.startswith(body_prefix)], key=lambda o: o.name)
    body = bodies[index]
    c = centre(body)
    heads = [o for o in objs if o.name.startswith(head_prefix)]
    head = min(heads, key=lambda o: (centre(o) - c).length)
    legs = [o for o in near([o for o in objs if o.name.startswith(leg_prefix)], c, reach)]
    o = join([body, head] + legs, out_name)
    finish(o, (c.x, c.y))
    export(o, out_name)


def palette_baked(path, child_index, out_name, remap, size=None):
    """Motri's palette-textured props: colour each face from the palette texture, then map
    the cartoon colours to ours."""
    reset()
    objs = load(path)
    roots = [o for o in objs if o.parent is None]
    root = roots[child_index]
    parts = [root] + list(root.children_recursive)
    pal = bpy.data.images.load(os.path.join(arg("--motri"), "static", "palette.png"))
    W, H = pal.size
    px = list(pal.pixels)
    o = join([p for p in parts if p.type == "MESH"], out_name)
    me = o.data
    uv = me.uv_layers.active
    col = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    mats = [m.name if m else "" for m in me.materials]
    for p in me.polygons:
        if p.material_index < len(mats) and "emissive" in mats[p.material_index].lower():
            for li in p.loop_indices:  # lamp glass: warm glow
                col.data[li].color_srgb = (1.0, 0.84, 0.5, 1.0)
            continue
        if uv:
            u = sum(uv.data[li].uv.x for li in p.loop_indices) / p.loop_total
            v = sum(uv.data[li].uv.y for li in p.loop_indices) / p.loop_total
            i = (min(H - 1, max(0, int(v * H))) * W + min(W - 1, max(0, int(u * W)))) * 4
            c = px[i:i + 3]
        else:
            c = (0.6, 0.45, 0.3)
        c = remap(c)
        for li in p.loop_indices:
            col.data[li].color_srgb = (*c, 1.0)
    c = centre(o)
    finish(o, (c.x, c.y))
    if size:
        dims = [max(v.co[i] for v in me.vertices) - min(v.co[i] for v in me.vertices) for i in range(3)]
        k = size / max(dims)
        me.transform(Matrix.Scale(k, 4))
    export(o, out_name)


def lin2srgb(c):
    return [((x ** (1 / 2.4)) * 1.055 - 0.055) if x > 0.0031308 else x * 12.92 for x in c]


def wood_remap(c):
    """Cartoon palette (linear) -> wood browns and a warm lamp glow (sRGB)."""
    r, g, b = lin2srgb(c)
    if r > 0.85 and g > 0.75 and b < 0.45:      # yellow glass / glow
        return (1.0, 0.84, 0.5)
    if b > r * 0.9:                              # purple-grey metal -> dark wood
        return (0.30, 0.21, 0.14)
    if r > 0.7 and g < 0.4:                      # red panels -> mid wood
        return (0.52, 0.35, 0.21)
    lum = 0.3 * r + 0.59 * g + 0.11 * b
    return (0.34 + 0.30 * lum, 0.22 + 0.20 * lum, 0.12 + 0.10 * lum)


def main():
    camels()
    tent()
    flock(arg("--pen"), "SheepPen_Bodies", "SheepPen_Heads", "SheepPen_Legs", "sheep", 0, reach=0.7)
    flock(arg("--birds"), "hen_Body", "hen_Head", "Poultry_Legs", "hen", 0)
    flock(arg("--birds"), "rooster_Body", "rooster_Head", "Poultry_Legs", "rooster", 0)
    m = arg("--motri")
    palette_baked(os.path.join(m, "static", "explosiveCrates", "explosiveCrates.glb"), 0, "crate", wood_remap, size=0.8)
    palette_baked(os.path.join(m, "static", "lanterns", "lanterns.glb"), 0, "lantern", wood_remap, size=0.6)


main()
