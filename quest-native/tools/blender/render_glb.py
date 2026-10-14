"""Quick review render of a GLB (Cycles):  python render_glb.py -- <in.glb> <out.png> [clip] [frame] [yaw]"""
import math
import sys

import bpy
from mathutils import Vector

a = sys.argv[sys.argv.index("--") + 1:]
src, out = a[0], a[1]
clip = a[2] if len(a) > 2 else ""
frame = int(a[3]) if len(a) > 3 else 0
yaw = math.radians(float(a[4])) if len(a) > 4 else math.radians(35)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 32
sc.render.resolution_x, sc.render.resolution_y = 640, 640
world = bpy.data.worlds.new("W")
sc.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.62, 0.52, 0.42, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.7
for o in sc.objects:
    if o.type == "ARMATURE" and o.animation_data and clip and clip in bpy.data.actions:
        o.animation_data.action = bpy.data.actions[clip]
sc.frame_set(frame)
bpy.context.view_layer.update()
lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
for o in list(sc.objects):
    if o.type == "MESH" and o.name.startswith("Icosphere"):
        bpy.data.objects.remove(o, do_unlink=True)  # importer's bone display shape
for o in sc.objects:
    if o.type == "MESH":
        dg = bpy.context.evaluated_depsgraph_get()
        me = o.evaluated_get(dg).to_mesh()
        for v in me.vertices:
            p = o.matrix_world @ v.co
            lo = Vector(map(min, lo, p))
            hi = Vector(map(max, hi, p))
c = (lo + hi) / 2
size = max(hi - lo)
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
sun.data.energy = 3.5
sun.rotation_euler = (math.radians(50), 0, math.radians(30))
sc.collection.objects.link(sun)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
cam.data.lens = 85
sc.collection.objects.link(cam)
sc.camera = cam
d = Vector((math.sin(yaw), -math.cos(yaw), 0.25)).normalized()
cam.location = c + d * size * 4.2
cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
