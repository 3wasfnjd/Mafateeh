"""Contact sheet of the kit pieces for review: python -m bpy render_kit.py -- <kit.blend> <out.png>"""
import math, sys
import bpy
from mathutils import Vector
args = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=args[0])
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 20
sc.render.resolution_x, sc.render.resolution_y = 1400, 760
w = bpy.data.worlds.new("W"); sc.world = w
w.node_tree.nodes["Background"].inputs[0].default_value = (0.75, 0.78, 0.82, 1)
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN")); sun.data.energy = 3.0
sun.rotation_euler = (math.radians(50), 0, math.radians(35)); sc.collection.objects.link(sun)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = "ORTHO"; cam.data.ortho_scale = 19
c = Vector((7.5, 1.6, 0.6)); d = Vector((0.0, -1.0, 0.75)).normalized()
cam.location = c + d * 30
cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
sc.render.filepath = args[1]
bpy.ops.render.render(write_still=True)
