"""Close portrait of the hero for store icons (Cycles, transparent background).
Without Blender, tools/store/render_portrait.gd renders the same portrait in Godot.
python -m bpy render_icon.py -- <hero.blend> <out.png>"""
import math, sys
import bpy
from mathutils import Vector
args = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=args[0])
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 64
sc.render.resolution_x = sc.render.resolution_y = 1024
sc.render.film_transparent = True
w = bpy.data.worlds.new("W"); sc.world = w
bg = w.node_tree.nodes["Background"]; bg.inputs[0].default_value = (1.0, 0.86, 0.7, 1); bg.inputs[1].default_value = 0.8
key = bpy.data.objects.new("Key", bpy.data.lights.new("Key", "AREA")); key.data.energy = 60; key.data.size = 1.0
key.location = (0.6, -1.0, 1.6); key.rotation_euler = (math.radians(55), 0, math.radians(30)); sc.collection.objects.link(key)
rim = bpy.data.objects.new("Rim", bpy.data.lights.new("Rim", "AREA")); rim.data.energy = 25; rim.data.size = 0.8
rim.location = (-0.7, 0.8, 1.4); rim.rotation_euler = (math.radians(-60), 0, math.radians(200)); sc.collection.objects.link(rim)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.lens = 85
target = Vector((0.0, 0.0, 0.93))
d = Vector((0.32, -1.0, 0.12)).normalized()
cam.location = target + d * 1.55
cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
arm = bpy.data.objects["HeroRig"]
arm.animation_data.action = bpy.data.actions["idle"]
sc.frame_set(0)
sc.render.filepath = args[1]
bpy.ops.render.render(write_still=True)
