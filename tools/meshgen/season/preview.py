"""Renders exported season meshes (out/<Name>.npz + .json) side by side, coloured the way the game
colours them (Neon pieces glow, Glass and transparent pieces see-through), facing the camera: to
check an export before uploading it.

    $PP_BPY_PYTHON tools/meshgen/season/preview.py out.png HarvestOwl EmberStag ...
"""

import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

HERE = Path(__file__).resolve().parent
OUT = HERE / "out"


def lin(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def material(info):
    m = bpy.data.materials.new("m")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    rgb = [lin(c) for c in info["color"]]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = 0.45
    if info["material"] == "Neon":
        b.inputs["Emission Color"].default_value = (*rgb, 1)
        b.inputs["Emission Strength"].default_value = 4
    if info["material"] == "Glass":
        b.inputs["Transmission Weight"].default_value = 1
        b.inputs["Roughness"].default_value = 0.05
    if info["transparency"] > 0:
        b.inputs["Alpha"].default_value = 1 - info["transparency"]
    return m


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    out, names = argv[0], argv[1:]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 24
    scene.cycles.device = "CPU"
    scene.cycles.use_denoising = True
    world = bpy.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.08, 0.06, 0.12, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    x, top = 0.0, 0.0
    for name in names:
        data = np.load(OUT / f"{name}.npz")
        meta = json.loads((OUT / f"{name}.json").read_text())
        width = meta["size"][0]
        x += width / 2
        for piece, info in meta["pieces"].items():
            v = data[f"{piece}__v"].astype(float)
            f = data[f"{piece}__f"].astype(int)
            bv = [(x + p[0], -p[2], p[1]) for p in v]  # Roblox (x, y, z) -> Blender (x, -z, y)
            me = bpy.data.meshes.new(piece)
            me.from_pydata(bv, [], f.tolist())
            me.shade_smooth()
            me.materials.append(material(info))
            ob = bpy.data.objects.new(piece, me)
            scene.collection.objects.link(ob)
        x += width / 2 + 0.6
        top = max(top, meta["size"][1])
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3
    sun.rotation_euler = (math.radians(50), 0, math.radians(200))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    span = max(x, top * 1.8)
    target = Vector((x / 2, 0, top / 2))
    cam.location = target + Vector((0, span * 1.25, top * 0.35))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 50
    scene.render.resolution_x, scene.render.resolution_y = 1400, 560
    scene.render.filepath = str(Path(out).resolve())
    bpy.ops.render.render(write_still=True)


main()
