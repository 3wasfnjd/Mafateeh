"""Review renders of shaib.blend (Cycles, CPU).

    python render_shaib.py -- <shaib.blend> <out_dir> [turnaround] [faces] [clip:frame ...]
"""
import math
import os
import sys

import bpy
from mathutils import Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

args = sys.argv[sys.argv.index("--") + 1:]
blend, out = args[0], args[1]
jobs = args[2:] or ["turnaround", "faces"]
bpy.ops.wm.open_mainfile(filepath=blend)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = int(os.environ.get("SAMPLES", 48))
sc.cycles.use_denoising = True
try:
    sc.cycles.denoiser = "OPENIMAGEDENOISE"
except Exception:
    pass
sc.render.resolution_x = 640
sc.render.resolution_y = 860
sc.view_settings.view_transform = "AgX"
sc.view_settings.look = "AgX - Medium High Contrast" if "AgX - Medium High Contrast" in [i.name for i in []] else "None"

world = bpy.data.worlds.new("W")
sc.world = world
world.use_nodes = True
bg = world.node_tree.nodes.get("Background")
bg.inputs[0].default_value = (0.62, 0.52, 0.42, 1)
bg.inputs[1].default_value = 0.55


def light(name, kind, energy, loc, rot, size=1.0, color=(1, 1, 1)):
    ld = bpy.data.lights.new(name, kind)
    ld.energy = energy
    ld.color = color
    if kind == "AREA":
        ld.size = size
    o = bpy.data.objects.new(name, ld)
    o.location = loc
    o.rotation_euler = rot
    sc.collection.objects.link(o)
    return o


# Golden-hour key, cool sky fill, warm rim.
light("Key", "AREA", 260, (1.6, -2.2, 2.4), (math.radians(55), 0, math.radians(35)), 2.0, (1.0, 0.88, 0.72))
light("Fill", "AREA", 90, (-2.4, -1.4, 1.2), (math.radians(70), 0, math.radians(-60)), 3.0, (0.75, 0.82, 1.0))
light("Rim", "AREA", 160, (-0.6, 2.2, 2.0), (math.radians(-55), 0, math.radians(180 - 15)), 1.5, (1.0, 0.85, 0.65))

# Ground: warm plaster disc that catches the shadow.
bpy.ops.mesh.primitive_circle_add(vertices=64, radius=3, fill_type="NGON")
g = bpy.context.active_object
gm = bpy.data.materials.new("ground")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.55, 0.42, 0.30, 1)
gm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.95
g.data.materials.append(gm)

cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
sc.collection.objects.link(cam)
sc.camera = cam
arm = bpy.data.objects["ShaibRig"]
body = bpy.data.objects["Body"]


def shot(name, yaw_deg, pitch_deg=6, target=(0, 0, 0.64), dist=4.2, lens=85, res=(640, 860)):
    sc.render.resolution_x, sc.render.resolution_y = res
    cam.data.lens = lens
    t = Vector(target)
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    d = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
    cam.location = t + d * dist
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(out, name + ".png")
    bpy.ops.render.render(write_still=True)


def keys(**vals):
    kb = body.data.shape_keys.key_blocks
    for k in kb:
        if k.name != "Basis":
            k.value = vals.get(k.name, 0.0)


def pose_stand():
    import build_shaib as B
    B.set_pose(arm, B.STAND if hasattr(B, "STAND") else {})


def apply_pose(fn_name):
    import build_shaib as B
    pose = getattr(B, fn_name)()
    B.set_pose(arm, pose)
    bpy.context.view_layer.update()


if arm.animation_data:
    arm.animation_data.action = None
for job in jobs:
    if job == "turnaround":
        apply_pose("pose_stand")
        keys()
        for name, yaw in (("front", 0), ("three_quarter", 35), ("side", 90), ("back", 180), ("three_quarter_back", 215)):
            shot(name, yaw)
    elif job == "faces":
        apply_pose("pose_stand")
        exprs = [
            ("neutral", {}),
            ("happy", {"smile": 1.0, "eyes_happy": 0.8, "brows_up": 0.4}),
            ("cheer", {"smile": 1.0, "eyes_happy": 1.0, "brows_up": 0.6, "mouth_open": 1.0}),
            ("surprised", {"eyes_wide": 1.0, "brows_up": 1.0, "mouth_oo": 1.0, "mouth_open": 0.7}),
            ("thinking", {"brow_raise_L": 1.0, "brows_angry": 0.35, "frown": 0.4}),
            ("worried", {"brows_sad": 1.0, "frown": 0.8}),
            ("blink", {"blink": 1.0, "smile": 0.3}),
        ]
        for name, v in exprs:
            keys(**v)
            shot("face_" + name, 18, 4, target=(0, -0.03, 1.06), dist=4.2, lens=330, res=(560, 600))
        keys()
    elif job == "hand":
        apply_pose("pose_stand")
        hb = arm.pose.bones["Hand.R"]
        c = arm.matrix_world @ hb.tail
        for name, yaw in (("hand_front", -40), ("hand_side", -100)):
            shot(name, yaw, 5, target=tuple(c), dist=4.2, lens=900, res=(500, 500))
    elif job.startswith("pose="):
        fn = job[5:]
        apply_pose(fn)
        keys(**{"pose_think": {"brow_raise_L": 1.0, "brows_angry": 0.3, "frown": 0.3},
                "pose_ardah": {"smile": 1.0, "eyes_happy": 0.9, "mouth_open": 0.8, "brows_up": 0.5},
                "pose_walk": {"smile": 0.35}}.get(fn, {}))
        for name, yaw in (("front", 0), ("three_quarter", 35), ("side", 90)):
            shot(fn + "_" + name, yaw)
    elif job == "wardrobe":
        apply_pose("pose_stand")
        keys(smile=0.4)
        for name in ("Bisht", "Glasses", "Misbaha"):
            if name in bpy.data.objects:
                bpy.data.objects[name].hide_render = False
        for name, yaw in (("wardrobe_front", 10), ("wardrobe_three_quarter", 40), ("wardrobe_back", 160)):
            shot(name, yaw)
        shot("wardrobe_face", 18, 4, target=(0, -0.03, 1.06), dist=4.2, lens=330, res=(560, 600))
        for name in ("Bisht", "Glasses", "Misbaha"):
            if name in bpy.data.objects:
                bpy.data.objects[name].hide_render = True
    elif job.startswith("strip="):
        clip, n, yaw = job[6:].split(":")
        act = bpy.data.actions[clip]
        arm.animation_data_create()
        arm.animation_data.action = act
        f0, f1 = act.frame_range
        keys(**{"ardah": {"smile": 1, "eyes_happy": 0.8, "mouth_open": 0.6}, "celebrate": {"smile": 1, "mouth_open": 0.8, "eyes_happy": 0.7},
                "think": {"brow_raise_L": 1, "frown": 0.3}, "reject": {"brows_sad": 0.8, "frown": 0.6}}.get(clip, {}))
        for i in range(int(n)):
            f = f0 + (f1 - f0) * i / int(n)
            sc.frame_set(int(f), subframe=f - int(f))
            shot("strip_%s_%02d" % (clip, i), float(yaw), 6, res=(300, 420), lens=85)
    elif ":" in job:
        clip, frame = job.split(":")
        arm.animation_data_create()
        arm.animation_data.action = bpy.data.actions[clip]
        sc.frame_set(int(frame))
        shot("pose_%s_%s" % (clip, frame), float(os.environ.get("POSE_YAW", 35)), 8)
