"""Low-poly vehicles for the desert camp (level 4): the shas, the datsun and the water truck.

  shas.glb    Toyota Land Cruiser 79 single-cab pickup (الشاص): boxy cab, long bonnet, flat
              bed, black bumpers and wheel arches, round lamps, a snorkel
  datsun.glb  the old Datsun pickup (الددسن): lower and lighter, chrome bumpers
  wayit.glb   a small water tanker (الوايت): cab-over cab and a round tank with a blue band

Sized for the camp's grid (2.2 m cells): the pickups are about 4.2 m long, two cells; the
truck too. Each faces +Z in Godot (-Y in Blender), origin at the middle of its footprint on
the ground. The body colour is the material named "paint_<car>": the game recolours it per car.
Usage: python3 tools/blender/build_vehicles.py   (writes assets/world/props/)
"""
import math
import os

import bpy
import bmesh
from mathutils import Matrix, Vector as V

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "world", "props")

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
_mats = {}


def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c) + (1.0,)


def mat(name, hexc, rough=0.7, metal=0.0):
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = srgb(hexc)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    _mats[name] = m
    return m


class Car:
    """Collects boxes and cylinders, each with a material, into one mesh."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.slots = []

    def _slot(self, m):
        if m not in self.slots:
            self.slots.append(m)
        return self.slots.index(m)

    def box(self, m, x0, x1, y0, y1, z0, z1, taper=0.0):
        """Axis box; taper pulls the top face in (x) by that much each side."""
        r = bmesh.ops.create_cube(self.bm, size=1)
        vs = r["verts"]
        for v in vs:
            top = v.co.z > 0
            v.co.x = (x0 + x1) / 2 + v.co.x * (x1 - x0 - (2 * taper if top else 0))
            v.co.y = (y0 + y1) / 2 + v.co.y * (y1 - y0)
            v.co.z = (z0 + z1) / 2 + v.co.z * (z1 - z0)
        idx = self._slot(m)
        for f in {f for v in vs for f in v.link_faces}:
            f.material_index = idx

    def cyl(self, m, centre, r, depth, axis="x", segs=12):
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=depth)
        rot = {"x": Matrix.Rotation(math.pi / 2, 4, "Y"), "y": Matrix.Rotation(math.pi / 2, 4, "X"), "z": Matrix.Identity(4)}[axis]
        bmesh.ops.transform(self.bm, matrix=Matrix.Translation(centre) @ rot, verts=res["verts"])
        idx = self._slot(m)
        for f in {f for v in res["verts"] for f in v.link_faces}:
            f.material_index = idx

    def wheel(self, x, y, r=0.38, w=0.26):
        self.cyl(mat("tyre", "#1f1c1a", 0.95), V((x, y, r)), r, w, "x", 14)
        side = 1 if x > 0 else -1
        self.cyl(mat("rim", "#c9c4bb", 0.4, 0.6), V((x + side * (w / 2 + 0.005), y, r)), r * 0.55, 0.02, "x", 10)

    def done(self):
        me = bpy.data.meshes.new(self.name)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.slots:
            me.materials.append(m)
        o = bpy.data.objects.new(self.name, me)
        sc.collection.objects.link(o)
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        path = os.path.join(OUT, self.name + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                                  export_materials="EXPORT")
        me.calc_loop_triangles()
        print("exported", self.name, os.path.getsize(path) // 1024, "KB", len(me.loop_triangles), "tris")
        bpy.data.objects.remove(o)


GLASS = ("glass", "#2b3640", 0.15)
BLACK = ("black", "#262422", 0.8)
LAMP = ("lamp", "#f4e7b8", 0.3)
CHROME = ("chrome", "#d8d6d0", 0.25, 0.8)


def m(spec):
    return mat(*spec)


def shas():
    """Land Cruiser 79 single cab: front at -Y. Length 4.2, width 1.76."""
    c = Car("shas")
    paint = mat("paint_shas", "#f1f0ea", 0.55)
    W = 0.88
    c.box(paint, -W, W, -2.1, 2.1, 0.42, 0.98)                    # body sides, full length
    c.box(paint, -W + 0.06, W - 0.06, -2.1, -0.65, 0.98, 1.16)    # bonnet
    c.box(paint, -W + 0.04, W - 0.04, -0.65, 0.5, 0.98, 1.88, taper=0.06)   # cab
    c.box(m(GLASS), -W + 0.1, W - 0.1, -0.67, -0.62, 1.2, 1.78)   # windscreen
    c.box(m(GLASS), -W + 0.035, W - 0.035, -0.5, 0.25, 1.24, 1.76)  # side windows
    c.box(m(GLASS), -W + 0.2, W - 0.2, 0.47, 0.52, 1.3, 1.75)     # back window
    # the bed: floor and walls
    c.box(paint, -W, W, 0.55, 2.1, 0.98, 1.0)
    for x0, x1 in ((-W, -W + 0.06), (W - 0.06, W)):
        c.box(paint, x0, x1, 0.55, 2.1, 1.0, 1.3)
    c.box(paint, -W, W, 2.04, 2.1, 1.0, 1.3)
    c.box(paint, -W, W, 0.55, 0.61, 1.0, 1.3)
    # face: black grille, round lamps, black bumper
    c.box(m(BLACK), -W + 0.18, W - 0.18, -2.13, -2.09, 0.66, 1.08)
    for x in (-0.66, 0.66):
        c.cyl(m(LAMP), V((x, -2.12, 0.88)), 0.12, 0.05, "y", 10)
    c.box(m(BLACK), -W - 0.04, W + 0.04, -2.22, -2.05, 0.32, 0.56)
    c.box(m(BLACK), -W, W, 2.08, 2.2, 0.36, 0.56)
    # wheel arches, snorkel, mirrors
    for y in (-1.3, 1.3):
        for x in (-W - 0.02, W + 0.02):
            c.box(m(BLACK), x - 0.05, x + 0.05, y - 0.52, y + 0.52, 0.72, 0.8)
    c.cyl(m(BLACK), V((W + 0.06, -0.72, 1.45)), 0.05, 1.0, "z", 8)
    c.box(m(BLACK), W + 0.02, W + 0.14, -0.78, -0.62, 1.86, 1.96)
    for x in (-W - 0.14, W + 0.14):
        c.box(m(BLACK), x - 0.06, x + 0.06, -0.62, -0.52, 1.36, 1.5)
    for x in (-0.78, 0.78):
        for y in (-1.3, 1.3):
            c.wheel(x, y)
    c.done()


def datsun():
    """Datsun pickup: lower and slimmer, chrome bumpers. Front at -Y. Length 4.2, width 1.6."""
    c = Car("datsun")
    paint = mat("paint_datsun", "#3f6fa8", 0.5)
    W = 0.8
    c.box(paint, -W, W, -2.1, 2.1, 0.36, 0.86)
    c.box(paint, -W + 0.04, W - 0.04, -2.1, -0.55, 0.86, 0.96)       # long low bonnet
    c.box(paint, -W + 0.06, W - 0.06, -0.55, 0.45, 0.86, 1.5, taper=0.1)  # small cab
    c.box(m(GLASS), -W + 0.16, W - 0.16, -0.57, -0.52, 1.0, 1.42)
    c.box(m(GLASS), -W + 0.05, W - 0.05, -0.42, 0.25, 1.02, 1.42)
    c.box(m(GLASS), -W + 0.22, W - 0.22, 0.42, 0.47, 1.05, 1.42)
    c.box(paint, -W, W, 0.5, 2.1, 0.86, 0.88)
    for x0, x1 in ((-W, -W + 0.05), (W - 0.05, W)):
        c.box(paint, x0, x1, 0.5, 2.1, 0.88, 1.12)
    c.box(paint, -W, W, 2.05, 2.1, 0.88, 1.12)
    c.box(paint, -W, W, 0.5, 0.55, 0.88, 1.12)
    c.box(m(CHROME), -W + 0.15, W - 0.15, -2.12, -2.08, 0.6, 0.86)  # grille
    for x in (-0.6, 0.6):
        c.cyl(m(LAMP), V((x, -2.11, 0.74)), 0.1, 0.05, "y", 10)
    c.box(m(CHROME), -W - 0.03, W + 0.03, -2.2, -2.06, 0.34, 0.46)
    c.box(m(CHROME), -W, W, 2.08, 2.18, 0.36, 0.46)
    for x in (-W - 0.12, W + 0.12):
        c.box(m(CHROME), x - 0.05, x + 0.05, -0.52, -0.44, 1.12, 1.22)
    for x in (-0.72, 0.72):
        for y in (-1.3, 1.3):
            c.wheel(x, y, 0.33, 0.22)
    c.done()


def wayit():
    """Small water tanker: cab-over cab at -Y, round tank behind. Length 4.3, width 1.9."""
    c = Car("wayit")
    paint = mat("paint_wayit", "#e8e4da", 0.5)  # the cab
    tank = mat("tank", "#dfe3e6", 0.35, 0.5)
    band = mat("band", "#3a6ea8", 0.5)
    W = 0.95
    c.box(m(BLACK), -0.5, 0.5, -2.0, 2.1, 0.45, 0.7)                 # chassis
    c.box(paint, -W, W, -2.15, -0.95, 0.55, 2.2, taper=0.05)          # cab
    c.box(m(GLASS), -W + 0.1, W - 0.1, -2.17, -2.12, 1.35, 2.05)      # windscreen
    c.box(m(GLASS), -W + 0.03, W - 0.03, -1.95, -1.3, 1.4, 2.0)       # door windows
    c.box(m(BLACK), -W + 0.15, W - 0.15, -2.18, -2.13, 0.7, 1.15)     # grille
    for x in (-0.72, 0.72):
        c.cyl(m(LAMP), V((x, -2.17, 0.92)), 0.1, 0.05, "y", 10)
    c.box(m(BLACK), -W - 0.03, W + 0.03, -2.25, -2.1, 0.35, 0.58)     # bumper
    c.box(m(BLACK), -W, W, -0.95, -0.85, 0.7, 1.2)                    # cab back wall
    # the tank: a round cylinder lying along the truck, end caps, a blue band and a hatch
    c.cyl(tank, V((0, 0.62, 1.48)), 0.88, 2.86, "y", 18)
    c.cyl(band, V((0, 0.62, 1.48)), 0.895, 0.5, "y", 18)
    c.cyl(m(BLACK), V((0, 0.2, 2.36)), 0.22, 0.12, "z", 10)
    c.cyl(m(CHROME), V((0, 2.08, 1.0)), 0.07, 0.25, "y", 8)          # the tap at the back
    c.box(m(BLACK), -W, W, 2.0, 2.15, 0.36, 0.56)
    for y in (-1.45,):
        for x in (-0.82, 0.82):
            c.wheel(x, y, 0.42, 0.28)
    for y in (0.95, 1.55):  # rear axles, doubled tyres
        for x in (-0.78, 0.78):
            c.wheel(x, y, 0.42, 0.34)
    c.done()


os.makedirs(OUT, exist_ok=True)
shas()
datsun()
wayit()
