"""Turntable + pose previews of hero.blend for visual review (Cycles, CPU).
python render_previews.py -- <hero.blend> <out_dir> [clip:frame ...]"""
import math, os, sys
import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
blend, out = args[0], args[1]
poses = args[2:] or []
bpy.ops.wm.open_mainfile(filepath=blend)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 24
sc.cycles.use_denoising = False
sc.render.resolution_x = 420
sc.render.resolution_y = 520
sc.render.film_transparent = False
world = bpy.data.worlds.new("W")
sc.world = world
world.use_nodes = True if hasattr(world, "use_nodes") else None
bg = world.node_tree.nodes.get("Background")
bg.inputs[0].default_value = (0.82, 0.83, 0.86, 1)
bg.inputs[1].default_value = 0.9
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
sun.data.energy = 3.5
sun.rotation_euler = (math.radians(50), 0, math.radians(30))
sc.collection.objects.link(sun)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
cam.data.type = "ORTHO"
cam.data.ortho_scale = 1.45
sc.collection.objects.link(cam)
sc.camera = cam
arm = bpy.data.objects["HeroRig"]
target = Vector((0, 0, 0.62))


def shot(name, yaw_deg, pitch_deg=4):
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    d = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
    cam.location = target + d * 4
    cam.rotation_euler = (d * -1).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(out, name + ".png")
    bpy.ops.render.render(write_still=True)


arm.animation_data.action = None
for pb in arm.pose.bones:
    pb.rotation_quaternion = (1, 0, 0, 0)
    pb.location = (0, 0, 0)
bpy.context.view_layer.update()
if not poses:
    for name, yaw in (("front", 0), ("side", 90), ("back", 180), ("three_quarter", 35)):
        shot(name, yaw)
for p in poses:
    clip, frame = p.split(":")
    arm.animation_data.action = bpy.data.actions[clip]
    sc.frame_set(int(frame))
    shot("pose_%s_%s" % (clip, frame), 35, 10)
