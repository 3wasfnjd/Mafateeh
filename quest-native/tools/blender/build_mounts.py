"""The mounts of the raid (level 10): a riding camel and a horse, each with its four legs as their
own parts so the game can swing them at a gallop.

  camel_ride.glb  Motri's standing camel (props/camel_standing.glb, Folio 2025 by Bruno Simon,
                  MIT) cut at the belly: the legs come away as Leg_FL/FR/BL/BR, pivoted where
                  they meet the body; a riding saddle (شداد) with a red Sadu blanket on the hump.
  horse.glb       an Arabian horse made here in the same low, soft style: arched neck, small
                  head, high tail, a saddle cloth; legs the same way. Coat on its own material
                  (horse_coat) so the game can give each horse its colour.

Both face +Z in Godot (-Y here), origin on the ground under the middle. Each file has a node
"Seat" where the rider's hips go.
Usage: python3 tools/blender/build_mounts.py
"""
import math
import os
import sys

sys.argv = [sys.argv[0]]
import bpy  # noqa: E402,I001  (bpy first: it makes bmesh importable)
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_shaib as S  # noqa: E402

PROPS = os.path.abspath(os.path.join(HERE, "..", "..", "assets", "world", "props"))
V = Vector
LEGS = ("FL", "FR", "BL", "BR")


def reset():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)


def mat(name, rgb, rough=0.85):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    return m


def srgb(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def pivot_at(o, p):
    """Moves the object's origin to p (world), keeping the mesh where it is."""
    o.data.transform(Matrix.Translation(-(p - o.location)))
    o.location = p


def empty(name, at):
    e = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(e)
    e.location = at
    return e


def export(path, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_materials="EXPORT", export_vertex_color="ACTIVE")
    print("exported", path, os.path.getsize(path) // 1024, "KB")


def sadu_blanket(pt, centre, w, d, h, drop):
    """A saddle cloth: a soft slab over the back that hangs down both sides, red with bands."""
    rows = []
    for i in range(9):
        v = i / 8
        row = []
        for j in range(13):
            u = j / 12
            a = (u - 0.5) * math.pi * 1.15      # round over the back and down the sides
            x = math.sin(a) * w
            z = centre.z + math.cos(a) * h - max(0.0, abs(math.sin(a)) - 0.55) * drop
            row.append(V((x, centre.y - d / 2 + d * v, z)))
        rows.append(row)
    pt.grid(rows, "sadu", uvf=lambda u, v: (u, v), flip=True)


# --- the camel ----------------------------------------------------------------------------------

BELLY = 1.25


def camel():
    reset()
    bpy.ops.import_scene.gltf(filepath=os.path.join(PROPS, "camel_standing.glb"))
    body = [o for o in bpy.data.objects if o.type == "MESH"][0]
    body.name = "Body"
    me = body.data
    bm = bmesh.new()
    bm.from_mesh(me)
    groups = {k: [] for k in LEGS}
    for f in bm.faces:
        c = f.calc_center_median()
        if c.z < BELLY:
            key = ("F" if c.y < -0.1 else "B") + ("L" if c.x > 0 else "R")
            groups[key].append(f)
    legs = []
    for key, faces in groups.items():
        nb = bmesh.new()
        vmap = {}
        flt = bm.loops.layers.float_color.active is not None
        lay = bm.loops.layers.float_color.active if flt else bm.loops.layers.color.active
        nlay = (nb.loops.layers.float_color if flt else nb.loops.layers.color).new("Color") if lay else None
        for f in faces:
            vs = []
            for v in f.verts:
                if v not in vmap:
                    vmap[v] = nb.verts.new(v.co)
                vs.append(vmap[v])
            try:
                nf = nb.faces.new(vs)
            except ValueError:
                continue
            if lay:
                for l0, l1 in zip(f.loops, nf.loops):
                    l1[nlay] = l0[lay]
        nme = bpy.data.meshes.new("Leg_" + key)
        nb.to_mesh(nme)
        nb.free()
        if nme.color_attributes:
            nme.color_attributes.active_color_index = 0
            nme.color_attributes.render_color_index = 0
        nme.materials.append(me.materials[0])
        o = bpy.data.objects.new("Leg_" + key, nme)
        bpy.context.collection.objects.link(o)
        xs = [v.co.x for v in nme.vertices]
        ys = [v.co.y for v in nme.vertices]
        pivot_at(o, V(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, BELLY)))
        legs.append(o)
    bmesh.ops.delete(bm, geom=[f for fs in groups.values() for f in fs], context="FACES_ONLY")
    bm.to_mesh(me)
    bm.free()
    # the riding saddle on the hump: a wooden frame of two arches and a red blanket under it
    mat("sadu", srgb("#a3271d"))
    mat("saddle_wood", srgb("#6b4123"), 0.7)
    pt = S.Part("Saddle")
    sadu_blanket(pt, V((0, 0.05, 2.28)), 0.5, 1.15, 0.16, 0.55)
    for y in (-0.38, 0.42):
        arch = [V((math.sin(a) * 0.36, y, 2.32 + math.cos(a) * 0.16)) for a in [(-1 + 2 * i / 10) * 1.2 for i in range(11)]]
        pt.tube(arch, lambda t, a: 0.035, "saddle_wood", segs=6)
        pt.tube([V((0, y, 2.46)), V((0, y, 2.62))], lambda t, a: 0.03, "saddle_wood", segs=6)   # the horn
    saddle = S.part_object(pt, ["sadu", "saddle_wood"], subdiv=1)
    seat = empty("Seat", V((0, 0.02, 2.4)))
    export(os.path.join(PROPS, "camel_ride.glb"), [body, saddle, seat] + legs)


# --- the horse -----------------------------------------------------------------------------------

HORSE_K = 1.3   # built at a pony's size, then grown to a horse beside the old man


def horse():
    reset()
    mat("horse_coat", srgb("#8a5a35"), 0.7)
    mat("horse_hair", srgb("#2b1d15"), 0.8)
    mat("hoof", srgb("#3a3330"), 0.6)
    mat("sadu", srgb("#a3271d"))
    pt = S.Part("Body")
    # the barrel: an egg, deeper at the chest
    def barrel(d):
        y = d.y * 0.62
        k = 1.0 + 0.12 * max(0.0, -d.y)
        return V((d.x * 0.28 * k, y, 1.06 + d.z * 0.29 * k))
    pt.sphere(lambda d: barrel(V((d.x, d.y, d.z))), "horse_coat", nu=16, nv=10)
    # neck, arched, up and forward from the withers; the head below it
    neck = [V((0, -0.42 + 0.0, 1.18)), V((0, -0.62, 1.38)), V((0, -0.76, 1.58)), V((0, -0.84, 1.74))]
    pt.tube(neck, lambda t, a: 0.19 - 0.07 * t, "horse_coat", segs=12, squash=lambda t: (0.75, 1.0))
    head = [V((0, -0.84, 1.76)), V((0, -0.98, 1.68)), V((0, -1.12, 1.55)), V((0, -1.2, 1.46))]
    pt.tube(head, lambda t, a: 0.1 - 0.035 * t, "horse_coat", segs=12, squash=lambda t: (0.7, 1.0))
    for s in (1, -1):   # ears
        pt.tube([V((s * 0.05, -0.83, 1.83)), V((s * 0.06, -0.8, 1.95))], lambda t, a: 0.025 * (1 - t), "horse_coat", segs=5, cap1=False)
    # the mane along the top of the neck, the forelock, and the tail carried high
    mane = [p + V((0, 0.05, 0.1)) for p in neck]
    pt.tube(mane, lambda t, a: 0.06, "horse_hair", segs=6, squash=lambda t: (0.35, 1.0))
    tail = [V((0, 0.6, 1.2)), V((0, 0.76, 1.24)), V((0, 0.88, 1.08)), V((0, 0.94, 0.82)), V((0, 0.95, 0.62))]
    pt.tube(tail, lambda t, a: 0.07 - 0.03 * t, "horse_hair", segs=8)
    sadu_blanket(pt, V((0, -0.08, 1.27)), 0.3, 0.55, 0.06, 0.32)
    body = S.part_object(pt, ["horse_coat", "horse_hair", "sadu"], subdiv=1)
    legs = []
    for key in LEGS:
        x = 0.14 if key[1] == "L" else -0.14
        y = -0.4 if key[0] == "F" else 0.42
        top = V((x, y, 1.0))
        bend = -0.05 if key[0] == "F" else 0.07   # knees forward in front, hocks back behind
        path = [top, V((x, y + bend * 0.4, 0.62)), V((x, y + bend, 0.4)), V((x, y + bend * 0.6, 0.1))]
        lp = S.Part("Leg_" + key)
        lp.tube(path, lambda t, a: 0.075 - 0.04 * t, "horse_coat", segs=8)
        lp.tube([path[-1], path[-1] + V((0, -0.02, -0.1))], lambda t, a: 0.045, "hoof", segs=8)
        o = S.part_object(lp, ["horse_coat", "hoof"], subdiv=1)
        o.name = "Leg_" + key
        pivot_at(o, top)
        legs.append(o)
    seat = empty("Seat", V((0, -0.08, 1.3)))
    for o in [body, seat] + legs:
        o.location *= HORSE_K
        o.scale = (HORSE_K,) * 3
    export(os.path.join(PROPS, "horse.glb"), [body, seat] + legs)


if __name__ == "__main__":
    camel()
    horse()
