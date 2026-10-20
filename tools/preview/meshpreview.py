"""Renders generated props side by side with Blender, to check a mesh before uploading it.

    <blender python> tools/preview/meshpreview.py out.png Pump Balloon:0.5 ...   (name[:scale])

Props come from assets/meshes/<name>.glb; the camera looks at their fronts (-Z). Glowing pieces
named Lava, Glow or Spokes are drawn emissive. CAMX / CAMH env vars nudge the camera sideways / up.
Needs the `bpy` package (see tools/preview/render.py).
"""
import math, sys
from pathlib import Path
import bpy, mathutils
ROOT = Path(__file__).resolve().parents[2] / "assets" / "meshes"
out = sys.argv[1]
items = sys.argv[2:]
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 24
scene.cycles.device = "CPU"
scene.render.resolution_x, scene.render.resolution_y = 1280, 720
world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.65, 0.8, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
x = 0.0
extents = []
for item in items:
    name, _, scale = item.partition(":")
    scale = float(scale or 1)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / f"{name}.glb"))
    objs = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    lo = mathutils.Vector((1e9,) * 3); hi = mathutils.Vector((-1e9,) * 3)
    for o in objs:
        o.scale = (scale,) * 3
    bpy.context.view_layer.update()
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ mathutils.Vector(c)
            lo = mathutils.Vector(map(min, lo, w)); hi = mathutils.Vector(map(max, hi, w))
    width = hi.x - lo.x
    for o in objs:
        o.location.x += x - lo.x
        for m in o.data.materials:
            if m and m.name in ("Lava", "Glow", "Spokes"):
                m.use_nodes = True
                bsdf = m.node_tree.nodes.get("Principled BSDF")
                bsdf.inputs["Emission Color"].default_value = bsdf.inputs["Base Color"].default_value
                bsdf.inputs["Emission Strength"].default_value = 3.0
    extents.append((x, x + width, hi.z))
    x += width + 4
total = x - 4
top = max(e[2] for e in extents)
bpy.ops.mesh.primitive_plane_add(size=total * 4, location=(total / 2, 0, 0))
sun = bpy.data.lights.new("sun", "SUN"); sun.energy = 3.5
so = bpy.data.objects.new("sun", sun); so.rotation_euler = (math.radians(50), 0, math.radians(30)); scene.collection.objects.link(so)
cam = bpy.data.cameras.new("cam"); cam.lens = 35
co = bpy.data.objects.new("cam", cam); scene.collection.objects.link(co); scene.camera = co
dist = max(total, top * 1.6) * 1.05
co.location = (total / 2 + float(__import__("os").environ.get("CAMX", "0")), dist, top * float(__import__("os").environ.get("CAMH", "0.75")))
direction = mathutils.Vector((total / 2, 0, top * 0.4)) - co.location
co.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
scene.render.filepath = out
bpy.ops.render.render(write_still=True)
print("wrote", out)
