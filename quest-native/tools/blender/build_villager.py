"""Light background villager (assets/character/villager.glb) from the old man's source.
Usage: python3 tools/blender/build_villager.py [-- out_dir [blend]]

Opens art_source/character/shaib.blend (written by build_shaib.py), drops the face
shape keys, the wardrobe pieces and the falcon perch use, decimates the meshes and
keeps only the clips villagers play (idle, walk, ardah). Same skeleton and materials,
so the game dresses villagers the same way (white ghutra, thobe tints).
"""
import os
import sys

import bpy

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(ARGS[0] if ARGS else os.path.join(HERE, "../../assets/character"))
BLEND = os.path.abspath(ARGS[1] if len(ARGS) > 1 else os.path.join(HERE, "../../art_source/character/shaib.blend"))
KEEP_CLIPS = {"idle", "walk", "ardah"}
DROP = ("Bisht", "Glasses", "Misbaha", "CaneArm")
# Triangle share kept per mesh: the head and hands are seen least from a distance.
RATIO = {"Body": 0.3, "Shemagh": 0.25, "Thobe": 0.4, "Cane": 0.6}

bpy.ops.wm.open_mainfile(filepath=BLEND)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
meshes = []
for o in list(bpy.data.objects):
    if o.type != "MESH":
        continue
    if o.name.startswith(DROP):
        bpy.data.objects.remove(o, do_unlink=True)
        continue
    bpy.context.view_layer.objects.active = o
    if o.data.shape_keys:
        o.shape_key_clear()
    for m in list(o.modifiers):
        if m.type != "ARMATURE":
            o.modifiers.remove(m)
    d = o.modifiers.new("Decimate", "DECIMATE")
    d.decimate_type = "COLLAPSE"
    d.ratio = RATIO.get(o.name, 0.35)
    d.use_collapse_triangulate = True
    # Decimate before the armature so the bind pose is what gets simplified.
    while o.modifiers.find("Decimate") > 0:
        bpy.ops.object.modifier_move_up(modifier="Decimate")
    bpy.ops.object.modifier_apply(modifier="Decimate")
    meshes.append(o)
for act in list(bpy.data.actions):
    if act.name not in KEEP_CLIPS:
        bpy.data.actions.remove(act)
arm.animation_data_create()
arm.animation_data.action = bpy.data.actions.get("idle")

os.makedirs(OUT, exist_ok=True)
path = os.path.join(OUT, "villager.glb")
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(
    filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=False,
    export_animations=True, export_animation_mode="ACTIONS", export_skins=True,
    export_def_bones=False, export_optimize_animation_size=True, export_image_format="AUTO",
    export_materials="EXPORT", export_texcoords=True, export_normals=True, export_frame_range=False,
    export_morph=False, export_force_sampling=True,
)
tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
print("exported", path, os.path.getsize(path) // 1024, "KB,", tris, "tris")
