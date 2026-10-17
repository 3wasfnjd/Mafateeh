"""The gold-threaded agal («العقال المقصّب») the old man wears from the wardrobe, after the
owner's reference picture: a squared ring of four gold cords lying one above the other,
bound at each corner and at the back by a fluffy knot of black silk, and a black twisted
cord down the back ending in a black tassel under a gold band.

It sits where the plain black agal of shaib.glb sits (the same head envelope from
build_shaib.py) and is written in the model's own space (Godot: x, z, -y of Blender), as a
plain mesh: the game hangs it on the Head bone and hides the black one while it is worn.
Writes assets/character/agal_muqassab.glb (its two small textures inside it).
Usage: python3 tools/blender/build_agal_muqassab.py
"""
import math
import os
import sys
import tempfile

sys.argv = [sys.argv[0]]
import bpy  # noqa: E402,I001  (bpy first: it makes bmesh importable)
import numpy as np  # noqa: E402
from mathutils import Vector, noise  # noqa: E402

import build_shaib as S  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "..", "..", "assets", "character"))
V = Vector

CORDS = 4                 # gold cords, one above the other
CORD_R = 0.0062
CORD_GAP = 0.0112         # between their centres
SQUARE = 3.4              # superellipse power of the ring (2 = round; higher = squarer)
KNOTS = (45, 135, 180, 225, 315)   # degrees round the head (0 = the front)


def ring_point(deg, dz, out=0.0):
    """A point of the ring at `deg` round the head, `dz` above its middle, `out` further out."""
    a = math.radians(deg)
    cz = S.H(V((0, 0, 1.112))).z
    zz = cz + dz + 0.010 * math.cos(a)            # a little higher at the front, as the black one
    th = math.copysign(math.pi - abs(math.atan2(math.sin(a), math.cos(a))), math.sin(a))
    base = S.env_radius(th, zz) + S.SHEMAGH_OFF + 0.009
    sq = 1.0 / (abs(math.cos(a)) ** SQUARE + abs(math.sin(a)) ** SQUARE) ** (1.0 / SQUARE)
    r = base * sq + out
    return V((math.sin(a) * r, S.PIVOT.y - math.cos(a) * r, zz))


def paint(path, kind):
    n = 256
    yy, xx = np.mgrid[0:n, 0:n] / n
    if kind == "gold":
        # twisted gold thread: diagonal plies with dark seams
        ply = (xx * 1 + yy * 6) % 1.0
        shade = 0.55 + 0.45 * np.sin(ply * math.pi) ** 0.6
        seam = np.abs(ply - 0.0) < 0.06
        c = np.array([1.0, 0.8, 0.4])[None, None] * shade[..., None]
        c = np.where(seam[..., None], c * 0.45, c)
    else:
        # black silk floss: fine lustrous strands
        strand = 0.5 + 0.5 * np.sin(xx * math.pi * 2 * 40 + np.sin(yy * 9) * 2)
        c = np.array([0.075, 0.068, 0.08])[None, None] * (0.7 + 0.9 * strand[..., None] ** 3)
    img = bpy.data.images.new(os.path.basename(path), n, n)
    px = np.concatenate([np.clip(c, 0, 1), np.ones((n, n, 1))], axis=2)[::-1].astype(np.float32)
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    return img


def material(name, img, rough, metal, sheen=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if sheen and "Sheen Weight" in b.inputs:
        b.inputs["Sheen Weight"].default_value = sheen
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = img
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    return m


def build():
    pt = S.Part("AgalGold")
    # the gold cords, each a closed squared ring (the knots cover the joins)
    steps = 80
    for k in range(CORDS):
        dz = (k - (CORDS - 1) / 2.0) * CORD_GAP
        path = [ring_point(360.0 * j / steps, dz) for j in range(steps)]
        path.append(path[0])
        pt.tube(path, lambda t, a: CORD_R, "agal_zari", segs=8, cap0=False, cap1=False,
                uvf=lambda u, v: (u, v * 40), twist_ref=V((0, 0, 1)))
    half_h = (CORDS - 1) / 2.0 * CORD_GAP + CORD_R
    for deg in KNOTS:
        # the knot: a lumpy ball of black floss wrapped round the cords
        path = [ring_point(deg + s, 0, 0.002) for s in np.linspace(-7.0, 7.0, 11)]
        seed = deg * 0.37

        def lump(t, a, seed=seed):
            bulge = math.sin(math.pi * t) ** 0.7
            fluff = (1.0 + 0.22 * noise.noise(V((math.cos(a) * 2.2 + seed, math.sin(a) * 2.2, t * 3.0)))
                     + 0.08 * noise.noise(V((math.cos(a) * 9.0, math.sin(a) * 9.0 + seed, t * 11.0))))
            wraps = 1.0 + 0.06 * math.sin(t * math.pi * 7 + a)
            return (half_h + 0.011) * (0.4 + 0.75 * bulge) * fluff * wraps

        pt.tube(path, lump, "agal_silk", segs=16, squash=lambda t: (0.021 / (half_h + 0.011), 1.0),
                uvf=lambda u, v: (u * 2, v), twist_ref=V((0, 0, 1)))
    # the cord down the back from the back knot, and its tassel under a gold band
    top = ring_point(180, -half_h + 0.004, 0.006)
    cord = [top + V((0.002 * i, 0.007 * min(i, 3), -0.021 * i)) for i in range(8)]
    pt.tube(cord, lambda t, a: 0.0028 * (1.0 + 0.18 * math.sin(a * 2 + t * 60)), "agal_silk", segs=8,
            uvf=lambda u, v: (u, v * 6))
    end = cord[-1]
    band = [end + V((0, 0, -0.002)), end + V((0, 0, -0.011))]
    pt.tube(band, lambda t, a: 0.0055, "agal_zari", segs=10, uvf=lambda u, v: (u, v * 2))
    tassel = [end + V((0, 0, -0.010 - 0.013 * i)) for i in range(5)]
    pt.tube(tassel, lambda t, a: (0.0055 + 0.011 * t ** 0.8) * (1.0 + 0.1 * math.sin(a * 9)), "agal_silk",
            segs=14, cap0=False, uvf=lambda u, v: (u * 3, v))
    return pt


def main():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    tmp = tempfile.mkdtemp()
    gold = paint(os.path.join(tmp, "agal_zari.png"), "gold")
    silk = paint(os.path.join(tmp, "agal_silk.png"), "silk")
    material("agal_zari", gold, 0.38, 0.35)
    material("agal_silk", silk, 0.75, 0.0, sheen=0.3)
    obj = S.part_object(build(), ["agal_zari", "agal_silk"], subdiv=1)
    obj.name = "AgalGold"
    for m in list(obj.modifiers):
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=m.name)
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print("AgalGold: %d verts, %d tris" % (len(obj.data.vertices), tris))
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    path = os.path.join(OUT, "agal_muqassab.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_materials="EXPORT", export_image_format="AUTO")
    print("exported", path, os.path.getsize(path) // 1024, "KB")


if __name__ == "__main__":
    main()
