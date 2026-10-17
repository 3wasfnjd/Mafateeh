"""Takes the makers' names off the camp's cars (assets/world/props): the TOYOTA on the Land
Cruiser's grille and tailgate and the NISSAN on the Datsun's tailgate are removed, so no
trademark shows. The letters are thin raised faces of their own colour lying on the panel;
each region below is a box (Blender axes: -y is the car's front) and the letter colour in it.
Their faces are deleted (the panel behind them stays whole), and as a second guard any face
of that colour left in the box is painted the panel's colour.

Usage: python3 tools/blender/debadge_cars.py
"""
import os

import bpy  # noqa: I001  (bpy first: it makes bmesh importable)
import bmesh

HERE = os.path.dirname(os.path.abspath(__file__))
PROPS = os.path.abspath(os.path.join(HERE, "..", "..", "assets", "world", "props"))

# car: [(x0, x1, y0, y1, z0, z1), letter colour, panel colour, (largest face size, optional)]
# (the size keeps a badge's small faces apart from long grille bars of the same colour)
REGIONS = {
    "shas": [
        ((-0.5, 0.45, 2.6, 2.72, 1.0, 1.26), (0.92, 0.85, 0.62), (0.74, 0.62, 0.40)),    # tailgate
        ((-0.45, 0.45, -2.85, -2.5, 0.95, 1.3), (0.40, 0.46, 0.38), (0.05, 0.06, 0.05)),  # grille
    ],
    "datsun": [
        ((-0.5, 0.42, 2.0, 2.6, 0.74, 0.98), (0.30, 0.07, 0.05), (0.85, 0.82, 0.72)),    # tailgate
        ((-0.16, 0.16, -2.6, -2.0, 0.74, 0.95), (0.45, 0.48, 0.40), (0.06, 0.09, 0.09), 0.12),  # round badge
    ],
}


def near(a, b, tol=0.02):
    return all(abs(a[i] - b[i]) < tol for i in range(3))


def main():
    for car, regions in REGIONS.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        path = os.path.join(PROPS, car + ".glb")
        bpy.ops.import_scene.gltf(filepath=path)
        o = [o for o in bpy.data.objects if o.type == "MESH"][0]
        me = o.data
        col = me.color_attributes.active_color
        # the panel colour exactly as stored (sampled from a face of that colour)
        stored = {}
        for p in me.polygons:
            c = col.data[p.loop_start].color
            for r in regions:
                panel = r[2]
                if panel not in stored and near(c[:3], panel):
                    stored[panel] = tuple(c)
        n = 0
        doomed = []
        for p in me.polygons:
            c = p.center
            for r in regions:
                box, letter, panel = r[0], r[1], r[2]
                if len(r) > 3 and max((me.vertices[i].co - me.vertices[j].co).length for i in p.vertices for j in p.vertices) > r[3]:
                    continue
                if not (box[0] <= c.x <= box[1] and box[2] <= c.y <= box[3] and box[4] <= c.z <= box[5]):
                    continue
                if near(col.data[p.loop_start].color[:3], letter):
                    for li in p.loop_indices:
                        col.data[li].color = stored.get(panel, (*panel, 1.0))
                    doomed.append(p.index)
                    n += 1
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[bm.faces[i] for i in doomed], context="FACES_ONLY")
        bm.to_mesh(me)
        bm.free()
        print(car, "letter faces removed:", n)
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                                  export_materials="EXPORT", export_vertex_color="ACTIVE", export_all_vertex_colors=False)


if __name__ == "__main__":
    main()
