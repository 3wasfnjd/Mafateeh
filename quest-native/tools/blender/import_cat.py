"""Turns the owner's rigged cat (art_source/creatures/cat_rigged.fbx) into the game's cat slot.

The FBX has a 34-bone rig, one 794-triangle mesh with no material, and one run clip.
This script:
  * keeps the mesh, rig and run clip (exported as "walk");
  * paints flat per-face colours (ginger back with stripes, cream belly, dark eyes and nose)
    as vertex colours, so the low-poly facets read clearly without a texture or shadows;
  * adds two looping clips the game needs: "sit" and "sleep";
  * turns the cat to face -Y (Blender forward, +Z in glTF) and exports assets/creatures/cat.glb.

Usage:  python3 tools/blender/import_cat.py [-- path/to/cat.fbx] [--preview out_dir]
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector as V

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "art_source", "creatures", "cat_rigged.fbx")
OUT = os.path.join(ROOT, "assets", "creatures", "cat.glb")
FPS = 24

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEW = ARGS[ARGS.index("--preview") + 1] if "--preview" in ARGS else ""
if ARGS and not ARGS[0].startswith("--"):
    SRC = ARGS[0]

# Colours (sRGB; a byte colour attribute stores sRGB and the exporter converts it).
GINGER = (0.80, 0.50, 0.24)
GINGER_DARK = (0.62, 0.34, 0.14)
CREAM = (0.96, 0.88, 0.74)
PINK = (0.86, 0.56, 0.52)
EYE = (0.10, 0.09, 0.07)


def load():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    bpy.ops.import_scene.fbx(filepath=SRC)
    for o in list(bpy.data.objects):
        if o.type == "EMPTY":
            bpy.data.objects.remove(o)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    mesh = next(o for o in bpy.data.objects if o.type == "MESH")
    arm.name, mesh.name = "Cat", "CatMesh"
    return arm, mesh


def paint(arm, mesh):
    """Flat per-face colours from where each face sits on the body (cat faces +X here)."""
    me = mesh.data
    attr = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    for p in me.polygons:
        c, n = p.center, p.normal
        col = GINGER
        # stripes across the back and tail
        if n.z > -0.2 and math.sin(c.x * 58.0) > 0.45 and c.x < 0.17:
            col = GINGER_DARK
        # belly, chest, inner legs, chin
        if n.z < -0.35 or (c.z < 0.15 and abs(n.y) < 0.55 and c.x > 0.09 and n.x > 0.3):
            col = CREAM
        if c.z < 0.03:  # paws
            col = CREAM
        if c.x < -0.40:  # tail tip
            col = GINGER_DARK
        if c.x > 0.19:  # head (the source cat's snout tip is at x 0.28)
            if c.z < 0.205 or n.z < -0.3:
                col = CREAM  # muzzle and chin
            if 0.232 < c.x < 0.246 and c.z > 0.245 and n.x > 0.8:
                col = PINK  # inner ears
            if c.x > 0.272 and abs(c.y) < 0.012 and c.z > 0.185:
                col = PINK  # nose
        for li in p.loop_indices:
            attr.data[li].color = col + (1.0,)
    # eyes: the forward-facing face nearest each eye spot
    for side in (1, -1):
        spot = V((0.261, side * 0.029, 0.219))
        best = min((p for p in me.polygons if p.normal.x > 0.5),
                   key=lambda p: (p.center - spot).length)
        for li in best.loop_indices:
            attr.data[li].color = EYE + (1.0,)
    me.color_attributes.active_color = attr

    m = bpy.data.materials.new("cat_fur")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    nt.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    me.materials.clear()
    me.materials.append(m)


# --- posing -----------------------------------------------------------------------------
# A pose is {bone: (direction, head)}: each listed bone is turned so it points along
# `direction` (armature space, X forward, Z up); a root bone may also be moved so its head
# sits at `head`. Unlisted bones keep their rest angle relative to their parent.

def aim(arm, targets):
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion()
        pb.location = V()
    bpy.context.view_layer.update()
    order = [b.name for b in arm.data.bones]  # parents come before children
    for name in order:
        if name not in targets:
            continue
        d, head = targets[name]
        pb = arm.pose.bones[name]
        cur = pb.matrix.copy()
        cur_dir = (cur.to_3x3() @ V((0, 1, 0))).normalized()
        q = cur_dir.rotation_difference(V(d).normalized())
        rot = (q.to_matrix() @ cur.to_3x3()).to_4x4()
        rot.translation = V(head) if head is not None else cur.translation
        pb.matrix = rot
        bpy.context.view_layer.update()


def ground(arm, mesh, roots):
    """Lifts the root bones so the lowest point of the posed mesh is on the floor."""
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    ev = mesh.evaluated_get(dg)
    low = min((ev.matrix_world @ v.co).z for v in ev.data.vertices)
    for r in roots:
        pb = arm.pose.bones[r]
        m = pb.matrix.copy()
        m.translation.z -= low
        pb.matrix = m
    bpy.context.view_layer.update()


ROOTS = ["pelvis", "leg_back_left_1", "leg_back_right_1", "tail_1"]


def sit_pose(t, length):
    """Sitting upright, front paws together, tail wrapped round to the front.
    Small loop: breathing, a slow look to the side, the tail tip flicking."""
    breathe = math.sin(t / length * math.tau * 2) * 0.004
    look = math.sin(t / length * math.tau) * 0.35
    flick = math.sin(t / length * math.tau * 3)
    p = {
        "pelvis": ((1, 0, 0.75), (-0.12, 0, 0.055)),
        "body_1": ((1, 0, 1.1 + breathe * 10), None),
        "body_2": ((0.75, 0, 1), None),
        "neck": ((0.35, 0, 1), None),
        "head": ((1, math.sin(look) * 0.6, 0.5), None),
    }
    for s in (1, -1):
        side = "left" if s > 0 else "right"
        p[f"leg_front_{side}_1"] = ((0.12, -s * 0.05, -1), None)
        p[f"leg_front_{side}_2"] = ((0.04, 0, -1), None)
        p[f"leg_front_{side}_3"] = ((1, 0, -0.9), None)
        p[f"leg_front_{side}_4"] = ((1, 0, -0.05), None)
        p[f"leg_back_{side}_1"] = ((1, s * 0.35, -0.45), (-0.10, s * 0.045, 0.06))
        p[f"leg_back_{side}_2"] = ((-1, 0, -0.35), None)
        p[f"leg_back_{side}_3"] = ((1, s * 0.05, -0.05), None)
        p[f"leg_back_{side}_4"] = ((1, 0, 0), None)
    p["tail_1"] = ((-0.6, -0.3, -0.75), (-0.13, 0, 0.055))
    p["tail_2"] = ((-0.15, -1, -0.05), None)
    p["tail_3"] = ((0.8, -0.6, 0), None)
    p["tail_4"] = ((1, 0.2 + flick * 0.5, 0.15 + max(flick, 0) * 0.5), None)
    return p


def sleep_pose(t, length):
    """Curled up asleep on its side of the floor: head resting on the front paws, tail
    wrapped round the nose. Loop: slow breathing and an ear twitch."""
    breathe = math.sin(t / length * math.tau) * 0.006
    twitch = max(0.0, math.sin(t / length * math.tau * 2 - 1.0)) ** 8
    p = {
        "pelvis": ((1, 0.35, -0.05), (-0.11, 0.02, 0.10 + breathe)),
        "body_1": ((1, 0.12, -0.02 - breathe * 3), None),
        "body_2": ((1, -0.35, -0.06), None),
        "neck": ((0.85, -0.85, -0.3), None),
        "head": ((0.3, -1, -0.15), None),
        "ear_left": ((0.5 + twitch, 0.5, 1), None),
    }
    for s in (1, -1):
        side = "left" if s > 0 else "right"
        p[f"leg_front_{side}_1"] = ((-0.2, -0.3, -1), None)
        p[f"leg_front_{side}_2"] = ((0.7, -0.7, -0.1), None)
        p[f"leg_front_{side}_3"] = ((0.6, -0.8, 0), None)
        p[f"leg_front_{side}_4"] = ((0.6, -0.8, 0), None)
        p[f"leg_back_{side}_1"] = ((0.9, 0.2 * s - 0.2, -0.7), (-0.09, s * 0.04 + 0.02, 0.09))
        p[f"leg_back_{side}_2"] = ((-1, -0.1, -0.4), None)
        p[f"leg_back_{side}_3"] = ((0.85, -0.5, 0), None)
        p[f"leg_back_{side}_4"] = ((0.8, -0.6, 0), None)
    p["tail_1"] = ((-0.8, 0.5, -0.6), (-0.11, 0.02, 0.10 + breathe))
    p["tail_2"] = ((-0.2, -1, -0.15), None)
    p["tail_3"] = ((0.8, -0.6, 0), None)
    p["tail_4"] = ((1, 0.15, 0), None)
    return p


def bake(arm, mesh, name, seconds, fn, lift):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data.action = act
    frames = int(round(seconds * FPS))
    lift_z = None
    prev = {}
    for f in range(frames + 1):
        t = (f % frames) / FPS
        aim(arm, fn(t, seconds))
        if lift:
            if lift_z is None:  # one lift for the whole clip so the loop doesn't bob
                ground(arm, mesh, ROOTS)
                lift_z = arm.pose.bones["pelvis"].matrix.translation.z - fn(t, seconds)["pelvis"][1][2]
            else:
                for r in ROOTS:
                    pb = arm.pose.bones[r]
                    m = pb.matrix.copy()
                    m.translation.z += lift_z
                    pb.matrix = m
                bpy.context.view_layer.update()
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
    act.use_cyclic = True
    return act


def main():
    arm, mesh = load()
    paint(arm, mesh)
    arm.animation_data_create()
    run = arm.animation_data.action
    for a in list(bpy.data.actions):
        if a != run:
            bpy.data.actions.remove(a)
    run.name = "walk"
    run.use_fake_user = True
    bake(arm, mesh, "sit", 4.0, sit_pose, True)
    bake(arm, mesh, "sleep", 3.0, sleep_pose, True)
    # clear the pose before turning the rig: re-assigning a clip here (without its slot)
    # leaves the last baked pose on the bones and the exported run clip comes out bent
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = V()
        pb.scale = V((1, 1, 1))

    # face -Y (Blender forward): the source cat looks along +X
    # (rotate the mesh's own data too: a skinned glTF mesh ignores its node transform)
    mesh.parent = None
    for o in (arm, mesh):
        o.rotation_euler = (0, 0, -math.pi / 2)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    mesh.parent = arm
    mesh.matrix_parent_inverse = Matrix.Identity(4)

    if PREVIEW:
        preview(arm, mesh)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=False, export_animations=True, export_animation_mode="ACTIONS",
                              export_skins=True, export_def_bones=False, export_optimize_animation_size=True,
                              export_materials="EXPORT", export_force_sampling=True,
                              export_vertex_color="MATERIAL")
    print("exported", OUT, os.path.getsize(OUT) // 1024, "KB",
          sum(len(p.vertices) - 2 for p in mesh.data.polygons), "tris")


def preview(arm, mesh):
    sc = bpy.context.scene
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.75, 0.75, 0.75, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.2
    cam = bpy.data.cameras.new("c")
    co = bpy.data.objects.new("c", cam)
    sc.collection.objects.link(co)
    sc.camera = co
    cam.lens = 50
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 12
    sc.render.resolution_x, sc.render.resolution_y = 420, 340
    shots = [("walk", 1), ("walk", 19), ("sit", 0), ("sit", 48), ("sleep", 0)]
    for act_name, fr in shots:
        arm.animation_data.action = bpy.data.actions[act_name]
        for view, loc in (("side", (1.3, 0.0, 0.35)), ("front", (0.6, -1.15, 0.4))):
            co.location = loc
            co.rotation_euler = (V((0, 0, 0.12)) - co.location).to_track_quat("-Z", "Y").to_euler()
            sc.frame_set(fr)
            sc.render.filepath = os.path.join(PREVIEW, f"{act_name}_{fr:02d}_{view}.png")
            bpy.ops.render.render(write_still=True)
    arm.animation_data.action = bpy.data.actions["walk"]
    sc.frame_set(1)


main()
