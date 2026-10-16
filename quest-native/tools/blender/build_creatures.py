"""Creatures for Mafateeh v2: the falcon «شاهين», a courtyard cat and a sparrow.

    python build_creatures.py -- <out_dir> [<blend_dir>]

Same approach as build_shaib.py: procedural cages, subdivided, skinned with analytic
weights, procedural textures, baked clips. Blender -Y is each creature's front.
Outputs falcon.glb, cat.glb and sparrow.glb.
"""
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_shaib as B  # noqa: E402  (mesh builder, helpers)

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(ARGS[0] if ARGS else os.path.join(HERE, "../../assets/creatures"))
SRC = os.path.abspath(ARGS[1] if len(ARGS) > 1 else os.path.join(HERE, "../../art_source/creatures"))
V = Vector
FPS = 30
Part, part_object, catmull, lerp, smooth, clamp = B.Part, B.part_object, B.catmull, B.lerp, B.smooth, B.clamp


# --------------------------------------------------------------------------------------
# Textures (NumPy)
# --------------------------------------------------------------------------------------
def _save(name, arr):
    from PIL import Image
    os.makedirs(os.path.join(SRC, "textures"), exist_ok=True)
    p = os.path.join(SRC, "textures", name)
    Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8)).save(p)
    return p


def _hex(h):
    return np.array([int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)])


def falcon_textures():
    n = 512
    yy, xx = np.mgrid[0:n, 0:n] / n
    # Back/wing feathers: warm brown with pale scalloped edges in rows.
    row = (yy * 14) % 1
    col = (xx * 18 + np.floor(yy * 14) * 0.5) % 1
    scallop = np.clip(1 - np.abs(col - 0.5) * 2.2, 0, 1) * np.clip((row - 0.62) / 0.3, 0, 1)
    base = _hex("#7a5434")[None, None] * (0.85 + 0.25 * np.sin(xx * 40 + yy * 7)[..., None] * 0.2)
    feathers = base * (1 - 0.5 * scallop[..., None]) + _hex("#d9c3a0")[None, None] * 0.5 * scallop[..., None]
    t = {"back": _save("falcon_back.png", feathers)}
    # Chest: cream with dark teardrop streaks.
    streak = np.clip(1 - (np.abs(((xx * 10) % 1) - 0.5) * 6 + np.abs(((yy * 7) % 1) - 0.55) * 2.4), 0, 1)
    chest = _hex("#efe2c8")[None, None] * np.ones((n, n, 3))
    chest = chest * (1 - 0.6 * streak[..., None]) + _hex("#5a3a22")[None, None] * 0.6 * streak[..., None]
    t["chest"] = _save("falcon_chest.png", chest)
    return t


def cat_textures():
    n = 512
    yy, xx = np.mgrid[0:n, 0:n] / n
    # Sandy tabby: soft stripes along v.
    stripes = 0.5 + 0.5 * np.sin(yy * np.pi * 2 * 9 + np.sin(xx * 12) * 0.8)
    fur = _hex("#c99a62")[None, None] * (0.78 + 0.3 * stripes[..., None])
    return {"fur": _save("cat_fur.png", fur)}


def materials():
    def mat(name, color, rough=0.75, image=None, sheen=0.3):
        m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*color, 1)
        bsdf.inputs["Roughness"].default_value = rough
        if "Sheen Weight" in bsdf.inputs:
            bsdf.inputs["Sheen Weight"].default_value = sheen
        if image:
            tnode = m.node_tree.nodes.new("ShaderNodeTexImage")
            tnode.image = bpy.data.images.load(image)
            m.node_tree.links.new(tnode.outputs["Color"], bsdf.inputs["Base Color"])
        return m

    def srgb(h):
        c = [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]
        return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)
    ft = falcon_textures()
    ct = cat_textures()
    mat("f_back", (1, 1, 1), 0.7, image=ft["back"])
    mat("f_chest", (1, 1, 1), 0.75, image=ft["chest"])
    mat("f_dark", srgb("#2c2420"), 0.6)
    mat("f_yellow", srgb("#e8b830"), 0.45)
    mat("f_eye", srgb("#1a1414"), 0.08, sheen=0.0)
    mat("f_hood", srgb("#6e4a2c"), 0.55)
    mat("c_fur", (1, 1, 1), 0.8, image=ct["fur"], sheen=0.5)
    mat("c_light", srgb("#efe0c4"), 0.8, sheen=0.5)
    mat("c_nose", srgb("#c47a72"), 0.5)
    mat("c_eye", srgb("#8fb94a"), 0.1, sheen=0.0)
    mat("c_pupil", srgb("#141210"), 0.1, sheen=0.0)
    mat("s_brown", srgb("#8b6a48"), 0.7)
    mat("s_grey", srgb("#9a948c"), 0.7)
    mat("s_cream", srgb("#e7dcc8"), 0.7)
    mat("s_dark", srgb("#2a2420"), 0.5)


# --------------------------------------------------------------------------------------
# Generic rig + bake helpers
# --------------------------------------------------------------------------------------
def make_rig(name, bones):
    data = bpy.data.armatures.new(name)
    arm = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = {}
    for bname, h, t, parent in bones:
        b = data.edit_bones.new(bname)
        b.head, b.tail = V(h), V(t)
        if parent:
            b.parent = eb[parent]
        eb[bname] = b
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return arm


def skin_obj(obj, fn, arm):
    groups = {}
    for v in obj.data.vertices:
        w = fn(v.co.copy())
        tot = sum(w.values()) or 1.0
        for bone, val in w.items():
            if val / tot < 1e-3:
                continue
            g = groups.get(bone) or obj.vertex_groups.new(name=bone)
            groups[bone] = g
            g.add([v.index], val / tot, "REPLACE")
    obj.parent = arm
    obj.modifiers.new("Armature", "ARMATURE").object = arm


def pose(arm, rots):
    for pb in arm.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = V()
    for name, r in rots.items():
        rest = arm.data.bones[name].matrix_local.to_quaternion()
        loc = None
        if isinstance(r[0], (tuple, list)):
            r, loc = r
        q = Quaternion(V((1, 0, 0)), math.radians(r[0])) @ Quaternion(V((0, 1, 0)), math.radians(r[1])) @ Quaternion(V((0, 0, 1)), math.radians(r[2]))
        pb = arm.pose.bones[name]
        pb.rotation_quaternion = rest.inverted() @ q @ rest
        if loc:
            pb.location = rest.inverted() @ V(loc)


def bake(arm, clips):
    arm.animation_data_create()
    for name, seconds, fn, loop in clips:
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        arm.animation_data.action = act
        frames = int(round(seconds * FPS))
        prev = {}
        for f in range(frames + 1):
            t = (f % frames) / FPS if loop else f / FPS
            pose(arm, fn(t, seconds))
            for pb in arm.pose.bones:
                q = pb.rotation_quaternion.copy()
                if pb.name in prev and prev[pb.name].dot(q) < 0:
                    q.negate()
                    pb.rotation_quaternion = q
                prev[pb.name] = q
                pb.keyframe_insert("rotation_quaternion", frame=f)
                pb.keyframe_insert("location", frame=f)
        act.frame_range = (0, frames)
        act.use_frame_range = True
        act.use_cyclic = loop
    for pb in arm.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = V()


def export(arm, objs, name):
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=False, export_animations=True, export_animation_mode="ACTIONS",
                              export_skins=True, export_def_bones=False, export_optimize_animation_size=True,
                              export_materials="EXPORT", export_force_sampling=True)
    print("exported", path, os.path.getsize(path) // 1024, "KB",
          sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons), "tris")


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs, selected_objects=objs):
        bpy.ops.object.join()
    objs[0].name = name
    return objs[0]


def clear_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)


# --------------------------------------------------------------------------------------
# Falcon «شاهين» (saker): ~0.24 tall perched (board units; the hero is 1.26)
# --------------------------------------------------------------------------------------
FALCON_BONES = [
    ("Root", (0, 0, 0), (0, 0, 0.04), None),
    ("Body", (0, 0.0, 0.07), (0, -0.02, 0.15), "Root"),
    ("Neck", (0, -0.02, 0.15), (0, -0.03, 0.185), "Body"),
    ("Head", (0, -0.03, 0.185), (0, -0.035, 0.24), "Neck"),
    ("Tail", (0, 0.03, 0.08), (0, 0.10, 0.02), "Body"),
    ("Wing1.L", (0.035, -0.005, 0.15), (0.075, 0.02, 0.13), "Body"),
    ("Wing2.L", (0.075, 0.02, 0.13), (0.11, 0.06, 0.10), "Wing1.L"),
    ("Wing1.R", (-0.035, -0.005, 0.15), (-0.075, 0.02, 0.13), "Body"),
    ("Wing2.R", (-0.075, 0.02, 0.13), (-0.11, 0.06, 0.10), "Wing1.R"),
    ("Leg.L", (0.018, -0.005, 0.07), (0.018, -0.01, 0.01), "Body"),
    ("Leg.R", (-0.018, -0.005, 0.07), (-0.018, -0.01, 0.01), "Body"),
]


def build_falcon():
    clear_scene()
    arm = make_rig("FalconRig", FALCON_BONES)
    # Body: teardrop, chest forward, back sloping to the tail.
    body = Part("FBody")

    def bod(d):
        z = d.z
        rx = 0.040 * (1 - 0.35 * max(0, z) ** 2)
        ry = 0.046 * (1 - 0.2 * max(0, z))
        rz = 0.055
        p = V((d.x * rx, d.y * ry, d.z * rz))
        p.y += 0.012 * max(0, -d.y) * (1 - abs(z))  # full chest
        p.y += 0.02 * max(0, d.y) * max(0, -z)      # back tapers toward the tail
        return V((0, 0.0, 0.115)) + p
    body.sphere(bod, "f_back", nu=24, nv=16)
    # Neck: bridges the body into the head.
    body.sphere(lambda d: V((0, -0.022, 0.172)) + V((d.x * 0.026, d.y * 0.026, d.z * 0.03)), "f_back", nu=16, nv=10)
    fb = part_object(body, ["f_back", "f_chest"], subdiv=2)
    # The cream breast is painted onto the front of the same smooth body.
    for poly in fb.data.polygons:
        c = poly.center
        if c.y < -0.012 and c.z < 0.178 and c.z > 0.068 and abs(c.x) < 0.034:
            poly.material_index = 1
    skin_obj(fb, lambda p: {"Body": 1.0 - smooth(0.15, 0.17, p.z), "Neck": smooth(0.15, 0.17, p.z)}, arm)
    # Head: round, with the dark malar ("moustache") stripe, yellow cere and hooked beak.
    head = Part("FHead")
    hc = V((0, -0.033, 0.198))
    head.sphere(lambda d: hc + V((d.x * 0.030, d.y * 0.032, d.z * 0.030)), "f_hood", nu=18, nv=12)
    for s in (1, -1):
        head.sphere(lambda d, s=s: hc + V((s * 0.02, -0.022, -0.006)) + V((d.x * 0.006, d.y * 0.008, d.z * 0.014)), "f_dark", nu=8, nv=6)
        # Eyes: big and dark with a yellow ring (expressive at miniature size).
        head.sphere(lambda d, s=s: hc + V((s * 0.017, -0.024, 0.006)) + d * 0.0085, "f_yellow", nu=10, nv=8)
        head.sphere(lambda d, s=s: hc + V((s * 0.0185, -0.027, 0.0065)) + d * 0.0072, "f_eye", nu=10, nv=8)
        # Pale cheek.
        head.sphere(lambda d, s=s: hc + V((s * 0.018, -0.016, -0.012)) + V((d.x * 0.01, d.y * 0.01, d.z * 0.012)), "f_chest", nu=8, nv=6)
    head.sphere(lambda d: hc + V((0, -0.031, 0.0)) + V((d.x * 0.008, d.y * 0.006, d.z * 0.006)), "f_yellow", nu=8, nv=6)
    beak = [hc + V((0, -0.034, 0.0)), hc + V((0, -0.044, -0.004)), hc + V((0, -0.047, -0.012)), hc + V((0, -0.043, -0.018))]
    head.tube([catmull(beak, i / 6) for i in range(7)], lambda t, a: 0.0065 * (1 - t) + 0.0012, "f_dark", segs=8)
    fh = part_object(head, ["f_hood", "f_dark", "f_yellow", "f_eye", "f_chest"], subdiv=2)
    skin_obj(fh, lambda p: {"Head": 1.0}, arm)
    # Wings: folded along the sides, layered primaries reaching the tail.
    wings = Part("FWings")
    for s in (1, -1):
        # Folded wing: a broad, flattened blade from the shoulder, along the flank,
        # to primaries that cross over the tail.
        pts = [V((s * 0.029, -0.004, 0.158)), V((s * 0.035, 0.016, 0.135)), V((s * 0.034, 0.045, 0.105)),
               V((s * 0.026, 0.078, 0.075)), V((s * 0.013, 0.104, 0.055))]
        path = [catmull(pts, i / 12) for i in range(13)]
        wings.tube(path, lambda t, a: 0.03 * (1 - 0.75 * t ** 1.4) + 0.003, "f_back", segs=12,
                   squash=lambda t: (1.0, 0.3), twist_ref=V((1, 0, 0)), uvf=lambda u, v: (u, v * 2))
    fw = part_object(wings, ["f_back"], subdiv=2)
    side = "L"

    def ww(p):
        sd = "L" if p.x > 0 else "R"
        t = clamp((p.y + 0.012) / 0.117)
        return {"Wing1." + sd: 1 - smooth(0.3, 0.7, t), "Wing2." + sd: smooth(0.3, 0.7, t)}
    skin_obj(fw, ww, arm)
    # Tail: fan of long feathers.
    tail = Part("FTail")
    rows = []
    for i in range(6):
        t = i / 5
        rows.append([V((lerp(-0.022, 0.022, j / 6) * (1 + 0.4 * t), lerp(0.04, 0.115, t), lerp(0.085, 0.02, t))) for j in range(7)])
    tail.grid(rows, "f_back")
    ft = part_object(tail, ["f_back"], subdiv=2, solidify=0.003)
    skin_obj(ft, lambda p: {"Tail": 1.0}, arm)
    # Legs and talons (yellow), with leather jesses.
    legs = Part("FLegs")
    for s in (1, -1):
        legs.tube([V((s * 0.018, -0.006, 0.07)), V((s * 0.018, -0.008, 0.035)), V((s * 0.018, -0.012, 0.008))],
                  lambda t, a: 0.0065 * (1 - 0.3 * t), "f_yellow", segs=8)
        # feathered "trousers" over the upper legs
        legs.sphere(lambda d, s=s: V((s * 0.019, -0.006, 0.062)) + V((d.x * 0.012, d.y * 0.013, d.z * 0.016)), "f_hood", nu=10, nv=6)
        for k in (-1, 0, 1):
            legs.tube([V((s * 0.018, -0.012, 0.006)), V((s * 0.018 + k * 0.006, -0.024, 0.003))], lambda t, a: 0.0025, "f_dark", segs=5)
        legs.tube([V((s * 0.018, -0.006, 0.03)), V((s * 0.012, 0.01, 0.0))], lambda t, a: 0.0018, "f_hood", segs=4)
    fl = part_object(legs, ["f_yellow", "f_dark", "f_hood"], subdiv=1)
    skin_obj(fl, lambda p: {"Leg.L" if p.x > 0 else "Leg.R": 1.0}, arm)
    falcon = join([fb, fh, fw, ft, fl], "Falcon")

    def perch(t, T):
        # Idle: breathing, quick alert head turns, a tail flick.
        ph = t / T
        turn = 35 * math.sin(2 * math.pi * ph) * smooth(0.0, 1.0, abs(math.sin(2 * math.pi * ph * 2)))
        return {"Body": (2 * math.sin(2 * math.pi * ph * 3), 0, 0), "Head": (0, 0, turn), "Neck": (0, 0, turn * 0.3),
                "Tail": (6 * max(0.0, math.sin(2 * math.pi * (ph - 0.3) * 2)) ** 8, 0, 0)}

    def fly(t, T):
        # Wing rotations are in the Body's rest frame (bird standing). Body pitches 72 deg
        # forward into flight, which turns rest +Y (tail side) almost straight up. So the up/down
        # beat is a swing about rest Z (it moves the spread wing towards +-Y). The old clip beat
        # about rest Y, which after the pitch swept the wings fore and aft, like rowing. A fixed
        # turn about rest Y (forward, in flight) holds them out square instead of swept back.
        ph = t / T
        down = math.sin(2 * math.pi * ph)               # +1: wings fully down
        bend = math.sin(2 * math.pi * ph - 0.9)         # wingtips trail the stroke
        return {"Body": (72 + 3 * down, 0, 0), "Head": (-58, 0, 0), "Neck": (-10, 0, 0), "Tail": (-12, 0, 0),
                "Wing1.L": (0, -32, -(78 + 42 * down)), "Wing2.L": (0, 0, -(4 + 22 * bend)),
                "Wing1.R": (0, 32, 78 + 42 * down), "Wing2.R": (0, 0, 4 + 22 * bend),
                "Leg.L": (-55, 0, 0), "Leg.R": (-55, 0, 0)}

    def land(t, T):
        k = smooth(0.0, 1.0, t / T)
        a = fly(t, T)
        b = perch(t, T)
        out = {}
        for key in set(a) | set(b):
            ra = a.get(key, (0, 0, 0))
            rb = b.get(key, (0, 0, 0))
            out[key] = tuple(lerp(x, y, k) for x, y in zip(ra, rb))
        return out
    bake(arm, [("perch", 4.0, perch, True), ("fly", 0.4, fly, True), ("land", 0.6, land, False)])
    export(arm, [falcon], "falcon")


# --------------------------------------------------------------------------------------
# Cat: a sandy courtyard cat, ~0.2 tall sitting
# --------------------------------------------------------------------------------------
CAT_BONES = [
    ("Root", (0, 0, 0), (0, 0, 0.03), None),
    ("Hips", (0, 0.05, 0.07), (0, -0.02, 0.09), "Root"),
    ("Chest", (0, -0.02, 0.09), (0, -0.07, 0.10), "Hips"),
    ("Head", (0, -0.07, 0.12), (0, -0.09, 0.16), "Chest"),
    ("Tail1", (0, 0.07, 0.08), (0, 0.11, 0.09), "Hips"),
    ("Tail2", (0, 0.11, 0.09), (0, 0.15, 0.13), "Tail1"),
    ("LegFL", (0.02, -0.06, 0.08), (0.02, -0.06, 0.0), "Chest"),
    ("LegFR", (-0.02, -0.06, 0.08), (-0.02, -0.06, 0.0), "Chest"),
    ("LegBL", (0.022, 0.05, 0.07), (0.022, 0.05, 0.0), "Hips"),
    ("LegBR", (-0.022, 0.05, 0.07), (-0.022, 0.05, 0.0), "Hips"),
]


def build_cat():
    clear_scene()
    arm = make_rig("CatRig", CAT_BONES)
    p = Part("Cat")
    # Body (horizontal capsule).
    path = [V((0, 0.07, 0.08)), V((0, 0.02, 0.085)), V((0, -0.03, 0.09)), V((0, -0.065, 0.095))]
    p.sphere(lambda d: V((0, 0.0, 0.088)) + V((d.x * 0.031, d.y * 0.078, d.z * 0.034 * (1.0 - 0.15 * d.y))), "c_fur", nu=18, nv=12,
             uvf=lambda u, v: (u, v * 2))
    p.sphere(lambda d: V((0, -0.062, 0.1)) + V((d.x * 0.025, d.y * 0.022, d.z * 0.03)), "c_fur", nu=12, nv=8)
    # Head with ears, muzzle, eyes and nose.
    hc = V((0, -0.085, 0.135))
    p.sphere(lambda d: hc + V((d.x * 0.03, d.y * 0.027, d.z * 0.026)), "c_fur", nu=16, nv=10)
    p.sphere(lambda d: hc + V((0, -0.022, -0.008)) + V((d.x * 0.016, d.y * 0.01, d.z * 0.01)), "c_light", nu=10, nv=6)
    for s in (1, -1):
        ear = [hc + V((s * 0.016, 0.0, 0.02)), hc + V((s * 0.022, 0.003, 0.042))]
        p.tube(ear, lambda t, a: 0.011 * (1 - t) + 0.001, "c_fur", segs=6, squash=lambda t: (1.0, 0.45))
        p.sphere(lambda d, s=s: hc + V((s * 0.012, -0.024, 0.006)) + d * 0.0065, "c_eye", nu=8, nv=6)
        p.sphere(lambda d, s=s: hc + V((s * 0.012, -0.0295, 0.006)) + V((d.x * 0.0018, d.y * 0.0015, d.z * 0.005)), "c_pupil", nu=6, nv=5)
    p.sphere(lambda d: hc + V((0, -0.033, -0.002)) + d * 0.004, "c_nose", nu=6, nv=5)
    # Legs and paws.
    for s in (1, -1):
        for y in (-0.06, 0.05):
            p.tube([V((s * 0.02, y, 0.08)), V((s * 0.02, y, 0.012))], lambda t, a: 0.01, "c_fur", segs=8)
            p.sphere(lambda d, s=s, y=y: V((s * 0.02, y - 0.004, 0.007)) + V((d.x * 0.011, d.y * 0.014, d.z * 0.007)), "c_light", nu=8, nv=5)
    # Tail: a long curl.
    tail = [V((0, 0.07, 0.08)), V((0, 0.11, 0.085)), V((0, 0.14, 0.11)), V((0, 0.15, 0.15)), V((0, 0.135, 0.175))]
    p.tube([catmull(tail, i / 12) for i in range(13)], lambda t, a: 0.009 * (1 - 0.4 * t), "c_fur", segs=8)
    cat = part_object(p, ["c_fur", "c_light", "c_eye", "c_pupil", "c_nose"], subdiv=2)

    def cw(q):
        if q.y < -0.065 and q.z > 0.105:
            return {"Head": 1.0}
        if q.z < 0.075 and abs(q.x) > 0.008:
            leg = ("LegF" if q.y < 0 else "LegB") + ("L" if q.x > 0 else "R")
            return {leg: 1.0}
        if q.y > 0.07:
            return {"Tail2": smooth(0.1, 0.13, q.y + max(0.0, q.z - 0.09)), "Tail1": 1 - smooth(0.1, 0.13, q.y + max(0.0, q.z - 0.09))}
        k = smooth(-0.04, 0.03, q.y)
        return {"Chest": 1 - k, "Hips": k}
    skin_obj(cat, cw, arm)

    def sit(t, T):
        ph = t / T
        return {"Hips": ((-35, 0, 0), (0, 0.0, -0.02)), "Chest": (-20, 0, 0), "Head": (35 + 3 * math.sin(2 * math.pi * ph * 2), 0, 25 * math.sin(2 * math.pi * ph)),
                "LegBL": (60, 0, 0), "LegBR": (60, 0, 0), "LegFL": (25, 0, 0), "LegFR": (25, 0, 0),
                "Tail1": (0, 0, 20 * math.sin(2 * math.pi * ph * 2)), "Tail2": (0, 0, 30 * math.sin(2 * math.pi * (ph * 2 - 0.2)))}

    def walk(t, T):
        ph = t / T
        a = 28 * math.sin(2 * math.pi * ph)
        return {"Chest": (0, 0, 4 * math.sin(2 * math.pi * ph)), "Head": (4 * math.sin(4 * math.pi * ph), 0, 0),
                "LegFL": (a, 0, 0), "LegBR": (a, 0, 0), "LegFR": (-a, 0, 0), "LegBL": (-a, 0, 0),
                "Tail1": (-20, 0, 10 * math.sin(2 * math.pi * ph)), "Tail2": (-15, 0, 15 * math.sin(2 * math.pi * (ph - 0.2)))}

    def sleep(t, T):
        ph = t / T
        return {"Hips": ((0, 0, 0), (0, 0, -0.045)), "Chest": (8 + 1.5 * math.sin(2 * math.pi * ph), 0, 0), "Head": (25, 0, 40),
                "LegFL": (80, 0, 0), "LegFR": (80, 0, 0), "LegBL": (-80, 0, 0), "LegBR": (-80, 0, 0), "Tail1": (0, 0, 70), "Tail2": (0, 0, 60)}
    bake(arm, [("sit", 4.0, sit, True), ("walk", 0.7, walk, True), ("sleep", 3.0, sleep, True)])
    export(arm, [cat], "cat")


# --------------------------------------------------------------------------------------
# Sparrow: tiny, hops and pecks in small flocks
# --------------------------------------------------------------------------------------
SPARROW_BONES = [
    ("Root", (0, 0, 0), (0, 0, 0.01), None),
    ("Body", (0, 0.0, 0.02), (0, -0.01, 0.04), "Root"),
    ("Head", (0, -0.012, 0.04), (0, -0.016, 0.055), "Body"),
    ("Wing.L", (0.01, 0, 0.035), (0.03, 0.01, 0.03), "Body"),
    ("Wing.R", (-0.01, 0, 0.035), (-0.03, 0.01, 0.03), "Body"),
]


def build_sparrow():
    clear_scene()
    arm = make_rig("SparrowRig", SPARROW_BONES)
    p = Part("Sparrow")
    p.sphere(lambda d: V((0, 0.0, 0.03)) + V((d.x * 0.012, d.y * 0.016, d.z * 0.012)), "s_brown", nu=12, nv=8)
    p.sphere(lambda d: V((0, -0.006, 0.026)) + V((d.x * 0.009, d.y * 0.009, d.z * 0.009)), "s_cream", nu=10, nv=6)
    p.sphere(lambda d: V((0, -0.014, 0.046)) + d * 0.008, "s_grey", nu=10, nv=8)
    p.tube([V((0, -0.021, 0.046)), V((0, -0.027, 0.045))], lambda t, a: 0.002 * (1 - t) + 0.0004, "s_dark", segs=5)
    for s in (1, -1):
        p.sphere(lambda d, s=s: V((s * 0.006, -0.019, 0.048)) + d * 0.0016, "s_dark", nu=6, nv=4)
        p.tube([V((s * 0.009, 0.0, 0.034)), V((s * 0.011, 0.016, 0.028))], lambda t, a: 0.006 * (1 - 0.5 * t), "s_brown", segs=6,
               squash=lambda t: (0.4, 1.0))
    p.tube([V((0, 0.012, 0.028)), V((0, 0.028, 0.03))], lambda t, a: 0.004, "s_brown", segs=6, squash=lambda t: (1.6, 0.4))
    bird = part_object(p, ["s_brown", "s_cream", "s_grey", "s_dark"], subdiv=2)

    def bw(q):
        if q.z > 0.04 and q.y < -0.006:
            return {"Head": 1.0}
        if abs(q.x) > 0.008 and q.z > 0.026:
            return {"Wing.L" if q.x > 0 else "Wing.R": 1.0}
        return {"Body": 1.0}
    skin_obj(bird, bw, arm)

    def peck(t, T):
        ph = t / T
        k = max(0.0, math.sin(2 * math.pi * ph * 2)) ** 6
        hop = 0.008 * max(0.0, math.sin(2 * math.pi * (ph - 0.5))) ** 4
        return {"Root": ((0, 0, 0), (0, 0, hop)), "Body": (25 * k, 0, 0), "Head": (35 * k, 0, 20 * math.sin(2 * math.pi * ph))}

    def fly(t, T):
        f = math.sin(2 * math.pi * t / T)
        return {"Body": (-20, 0, 0), "Wing.L": (0, -70 * f, -30), "Wing.R": (0, 70 * f, 30)}
    bake(arm, [("peck", 2.0, peck, True), ("fly", 0.2, fly, True)])
    export(arm, [bird], "sparrow")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    materials()
    build_falcon()
    if "--placeholder-cat" in sys.argv:  # cat.glb now comes from tools/blender/import_cat.py
        build_cat()
    build_sparrow()
    os.makedirs(SRC, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "creatures_last.blend"))


if __name__ == "__main__":
    main()
