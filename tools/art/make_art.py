"""Renders Party Panic's store art with Blender (pip `bpy`): the experience icon (512x512) and five
thumbnails (1920x1080). The thumbnails are built from snapshots of the real lobby and arenas (a few
seconds of a round played on a test server), with the stand-in players swapped for posed blocky
avatars; the title lettering goes on top.

    python tools/art/make_art.py --dumps art_dumps --fetch               # snapshot the lobby and arenas
    python tools/art/make_art.py --dumps art_dumps --out art             # render everything
    python tools/art/make_art.py --dumps art_dumps --out art --only icon,firerope --samples 16

--fetch runs the lobby builder and a few seconds of each featured mini-game on a test server
(Open Cloud Luau execution, the same way tools/preview/make_preview.py does; it needs the same API
access) and saves the snapshots in --dumps. The icons need no snapshot.

Scenes (--only, comma-separated; default: all of them):
    lobby, firerope, bobsled, hexmeltdown, party    thumb_1_lobby.jpg ... thumb_5_party.jpg
    icon                                            icon_512.png, the chosen concept (ICON below)
    icon_scream, icon_leap, icon_duo                the other concepts, icon_alt_<name>.png
    sheet                                           icon_sheet.png: the icons in --out at 512 and 128 px

Avatars are classic blocky characters (R6 proportions) built here, with decal faces drawn with
Pillow. The lettering uses Luckiest Guy (Apache 2.0, see fonts/LICENSE.txt).
"""

from __future__ import annotations

import argparse
import json
import math
import random
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import bpy
import bmesh  # noqa: I001  (after bpy: the bpy package puts it on the path)
import mathutils
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PREVIEW = ROOT / "tools" / "preview"
sys.path.insert(0, str(PREVIEW))
import render as R  # noqa: E402  (the preview renderer: parts, terrain, materials, glb loading)

FONT = str(HERE / "fonts" / "LuckiestGuy-Regular.ttf")
FACE_DIR = Path(tempfile.gettempdir()) / "pp_art_faces"
V = mathutils.Vector

# The chosen icon concept (icon_512.png); the others are kept as icon_alt_<name>.png.
ICON = "scream"

# Snapshot time (seconds into the round) for each featured mini-game, for --fetch.
FEATURED = {"FireRope": 8, "BobsledRun": 12, "HexMeltdown": 4.6, "HoneyTrap": 12, "RakeItIn": 8, "CrazyCutters": 8}

PARTY = [(255, 84, 150), (64, 196, 255), (255, 214, 64), (156, 108, 255), (110, 226, 140), (255, 140, 70)]


def B(x, y, z):
    """Roblox (x, y, z) -> Blender (x, -z, y)."""
    return V((x, -z, y))


# Scene ------------------------------------------------------------------------------------------


def new_scene(samples, width, height, top=(0.03, 0.22, 0.85), horizon=(0.42, 0.68, 1.0), sun=(0.4, -0.5, 0.75),
              sun_energy=4.0, transparent=False, exposure=-0.35, sky_strength=1.0, sun_color=(1.0, 0.97, 0.9)):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for cache in (R.MATERIAL_CACHE, R.PRIMS, R.MESH_CACHE, R.GLB_CACHE, BOX_MESHES, MATERIALS):
        cache.clear()
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 6
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.film_transparent = transparent
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA" if transparent else "RGB"
    # Standard (no filmic roll-off) keeps the toy colors as saturated as they are in Roblox.
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = exposure

    world = bpy.data.worlds.new("sky")
    scene.world = world
    world.use_nodes = True
    nodes, links = world.node_tree.nodes, world.node_tree.links
    bg = nodes["Background"]
    coords = nodes.new("ShaderNodeTexCoord")
    split = nodes.new("ShaderNodeSeparateXYZ")
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (*horizon, 1)
    ramp.color_ramp.elements[1].position = 0.4
    ramp.color_ramp.elements[1].color = (*top, 1)
    links.new(coords.outputs["Generated"], split.inputs[0])
    links.new(split.outputs["Z"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = sky_strength

    if sun_energy:
        sun_light(sun, sun_energy, sun_color)
    return scene


def sun_light(direction, energy, color=(1.0, 0.97, 0.9), angle=4):
    light = bpy.data.lights.new("sun", "SUN")
    light.energy = energy
    light.angle = math.radians(angle)
    light.color = color
    obj = bpy.data.objects.new("sun", light)
    obj.rotation_euler = (-V(direction)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(obj)
    return obj


def lamp(location, energy, color=(1, 1, 1), radius=1.0, kind="POINT"):
    light = bpy.data.lights.new("lamp", kind)
    light.energy = energy
    light.color = color
    light.shadow_soft_size = radius
    obj = bpy.data.objects.new("lamp", light)
    obj.location = V(location)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def camera(eye, target, fov=50, lens_shift=(0, 0), roll=0.0):
    data = bpy.data.cameras.new("cam")
    data.sensor_fit = "VERTICAL"
    data.angle_y = math.radians(fov)
    data.clip_end = 5000
    data.clip_start = 0.05
    data.shift_x, data.shift_y = lens_shift
    cam = bpy.data.objects.new("cam", data)
    cam.location = V(eye)
    direction = V(target) - V(eye)
    quat = direction.to_track_quat("-Z", "Y")
    if roll:
        quat = quat @ mathutils.Quaternion((0, 0, 1), math.radians(roll))
    cam.rotation_euler = quat.to_euler()
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam
    return cam


MATERIALS: dict = {}


def mat(color, kind="SmoothPlastic", transparency=0.0, emission=None):
    material = R.material(color, kind, transparency)
    if emission:
        key = ("emit", tuple(color), kind, transparency, emission)
        if key not in MATERIALS:
            material = material.copy()
            bsdf = material.node_tree.nodes["Principled BSDF"]
            bsdf.inputs["Emission Color"].default_value = (*[R.srgb_to_linear(c) for c in color], 1)
            bsdf.inputs["Emission Strength"].default_value = emission
            MATERIALS[key] = material
        material = MATERIALS[key]
    return material


def glow(color, strength=6.0, alpha=1.0):
    """A pure light material (fire, neon, sparks)."""
    key = ("glow", tuple(color), strength, alpha)
    if key not in MATERIALS:
        material = bpy.data.materials.new("glow")
        material.use_nodes = True
        nodes, links = material.node_tree.nodes, material.node_tree.links
        nodes.remove(nodes["Principled BSDF"])
        emit = nodes.new("ShaderNodeEmission")
        emit.inputs["Color"].default_value = (*[R.srgb_to_linear(c) for c in color], 1)
        emit.inputs["Strength"].default_value = strength
        output = nodes["Material Output"]
        if alpha < 1:
            clear = nodes.new("ShaderNodeBsdfTransparent")
            mix = nodes.new("ShaderNodeMixShader")
            mix.inputs[0].default_value = alpha
            links.new(clear.outputs[0], mix.inputs[1])
            links.new(emit.outputs[0], mix.inputs[2])
            links.new(mix.outputs[0], output.inputs["Surface"])
        else:
            links.new(emit.outputs[0], output.inputs["Surface"])
        MATERIALS[key] = material
    return MATERIALS[key]


def striped(color_a, color_b, frequency=9.0, axis="Z", twist=0.0):
    """Two-color bands along an object axis (party hats, bobsled stripes)."""
    key = ("stripes", tuple(color_a), tuple(color_b), frequency, axis, twist)
    if key not in MATERIALS:
        material = bpy.data.materials.new("stripes")
        material.use_nodes = True
        nodes, links = material.node_tree.nodes, material.node_tree.links
        bsdf = nodes["Principled BSDF"]
        bsdf.inputs["Roughness"].default_value = 0.45
        coords = nodes.new("ShaderNodeTexCoord")
        split = nodes.new("ShaderNodeSeparateXYZ")
        links.new(coords.outputs["Object"], split.inputs[0])
        scaled = nodes.new("ShaderNodeMath")
        scaled.operation = "MULTIPLY_ADD"
        scaled.inputs[1].default_value = frequency
        links.new(split.outputs[axis], scaled.inputs[0])
        # A twist turns the bands into a spiral: add the angle around the axis.
        angle = nodes.new("ShaderNodeMath")
        angle.operation = "ARCTAN2"
        links.new(split.outputs["Y"], angle.inputs[0])
        links.new(split.outputs["X"], angle.inputs[1])
        turns = nodes.new("ShaderNodeMath")
        turns.operation = "MULTIPLY"
        turns.inputs[1].default_value = twist
        links.new(angle.outputs[0], turns.inputs[0])
        links.new(turns.outputs[0], scaled.inputs[2])
        wave = nodes.new("ShaderNodeMath")
        wave.operation = "SINE"
        links.new(scaled.outputs[0], wave.inputs[0])
        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.interpolation = "CONSTANT"
        ramp.color_ramp.elements[0].position = 0.0
        ramp.color_ramp.elements[0].color = (*[R.srgb_to_linear(c) for c in color_a], 1)
        ramp.color_ramp.elements[1].position = 0.35
        ramp.color_ramp.elements[1].color = (*[R.srgb_to_linear(c) for c in color_b], 1)
        links.new(wave.outputs[0], ramp.inputs["Fac"])
        links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
        MATERIALS[key] = material
    return MATERIALS[key]


def two_tone(top, bottom, split):
    """`top` above local height `split` (in a 2-stud-tall box: -1 to 1), `bottom` below it, with a
    crisp line between: a short sleeve and the bare arm below it, in one piece."""
    key = ("two_tone", tuple(top), tuple(bottom), split)
    if key not in MATERIALS:
        material = bpy.data.materials.new("two_tone")
        material.use_nodes = True
        nodes, links = material.node_tree.nodes, material.node_tree.links
        bsdf = nodes["Principled BSDF"]
        bsdf.inputs["Roughness"].default_value = 0.45
        coords = nodes.new("ShaderNodeTexCoord")
        split_xyz = nodes.new("ShaderNodeSeparateXYZ")
        links.new(coords.outputs["Object"], split_xyz.inputs[0])
        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.interpolation = "CONSTANT"
        ramp.color_ramp.elements[0].position = 0.0
        ramp.color_ramp.elements[0].color = (*[R.srgb_to_linear(c) for c in bottom], 1)
        ramp.color_ramp.elements[1].position = (split + 1) / 2
        ramp.color_ramp.elements[1].color = (*[R.srgb_to_linear(c) for c in top], 1)
        remap = nodes.new("ShaderNodeMapRange")
        remap.inputs["From Min"].default_value = -1
        remap.inputs["From Max"].default_value = 1
        links.new(split_xyz.outputs["Z"], remap.inputs["Value"])
        links.new(remap.outputs["Result"], ramp.inputs["Fac"])
        links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
        MATERIALS[key] = material
    return MATERIALS[key]


def link(obj, parent=None):
    bpy.context.scene.collection.objects.link(obj)
    if parent:
        obj.parent = parent
    return obj


def empty(name, location=(0, 0, 0), rotation=(0, 0, 0), parent=None):
    obj = bpy.data.objects.new(name, None)
    obj.location = location
    obj.rotation_euler = rotation
    return link(obj, parent)


def mesh_object(name, mesh, material, location=(0, 0, 0), rotation=(0, 0, 0), scale=(1, 1, 1), parent=None):
    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    obj.rotation_euler = rotation
    obj.scale = scale
    link(obj, parent)
    if len(obj.material_slots):
        obj.material_slots[0].link = "OBJECT"
        obj.material_slots[0].material = material
    return obj


BOX_MESHES: dict = {}


def box_mesh(size):
    """A box mesh with real dimensions (so bevels stay round however the box is proportioned)."""
    key = tuple(round(v, 3) for v in size)
    if key not in BOX_MESHES:
        x, y, z = (v / 2 for v in size)
        verts = [(-x, -y, -z), (x, -y, -z), (x, y, -z), (-x, y, -z), (-x, -y, z), (x, -y, z), (x, y, z), (-x, y, z)]
        faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        mesh = bpy.data.meshes.new("box")
        mesh.from_pydata(verts, [], faces)
        mesh.shade_smooth()
        mesh.materials.append(None)
        BOX_MESHES[key] = mesh
    return BOX_MESHES[key]


def rounded_box(name, size, color, location=(0, 0, 0), rotation=(0, 0, 0), bevel=0.15, parent=None, kind="SmoothPlastic",
                emission=None, material=None):
    obj = mesh_object(name, box_mesh(size), material or mat(color, kind, emission=emission), location, rotation, (1, 1, 1),
                      parent)
    if bevel > 0:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = min(bevel, min(size) * 0.45)
        mod.segments = 4
        mod.harden_normals = True
    return obj


def ball(name, diameter, color, location, parent=None, scale=(1, 1, 1), kind="SmoothPlastic", emission=None, material=None):
    s = [diameter * k for k in scale]
    return mesh_object(name, R.prim_mesh("Ball"), material or mat(color, kind, emission=emission), location, (0, 0, 0), s,
                       parent)


def cylinder(name, diameter, length, color, location, rotation=(0, 0, 0), parent=None, kind="SmoothPlastic", emission=None,
             material=None):
    # R's cylinder runs along local X.
    return mesh_object(name, R.prim_mesh("Cylinder"), material or mat(color, kind, emission=emission), location, rotation,
                       (length, diameter, diameter), parent)


def cone(name, radius, height, material, location, rotation=(0, 0, 0), parent=None, tip=0.0, vertices=40):
    """A cone standing on its base (origin at the base center), tip up along local Z."""
    key = ("cone", round(radius, 3), round(height, 3), round(tip, 3), vertices)
    if key not in BOX_MESHES:
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=vertices, radius1=radius, radius2=tip,
                              depth=height, matrix=mathutils.Matrix.Translation((0, 0, height / 2)))
        mesh = bpy.data.meshes.new("cone")
        bm.to_mesh(mesh)
        bm.free()
        mesh.shade_smooth()
        mesh.materials.append(None)
        BOX_MESHES[key] = mesh
    return mesh_object(name, BOX_MESHES[key], material, location, rotation, (1, 1, 1), parent)


def tube(name, points, radius, material, resolution=6, parent=None):
    """A round tube through `points` (a smooth curve)."""
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = resolution
    curve.use_fill_caps = True
    spline = curve.splines.new("NURBS")
    spline.points.add(len(points) - 1)
    for point, co in zip(spline.points, points):
        point.co = (*co, 1)
    spline.use_endpoint_u = True
    spline.order_u = 3
    spline.resolution_u = 16
    obj = bpy.data.objects.new(name, curve)
    curve.materials.append(material)
    return link(obj, parent)


# Props from the game's own meshes -------------------------------------------------------------------


def prop(name, location, height, yaw=0.0, tilt=(0, 0), colors=None, parent=None, centered=False, emission=None):
    """Places a game prop (assets/meshes/<name>.glb) standing on `location`, `height` studs tall
    (or centered on it). In Blender axes the prop's front (Roblox -Z) points +Y."""
    import struct

    import numpy as np

    pieces = R.glb_pieces(name)
    data = Path(R.MESH_DIR / f"{name}.glb").read_bytes()
    doc = json.loads(data[20:20 + struct.unpack_from("<I", data, 12)[0]])
    base_colors = {}
    for mesh in doc["meshes"]:
        material_index = mesh["primitives"][0].get("material")
        if material_index is not None:
            factor = doc["materials"][material_index].get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])
            base_colors[mesh.get("name")] = [c * 255 for c in factor[:3]]
    all_verts = np.concatenate([v for v, _ in pieces.values()])
    lo, hi = all_verts.min(0), all_verts.max(0)
    k = height / max(hi[1] - lo[1], 1e-3)
    center = np.array([(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2 if centered else lo[1], (lo[2] + hi[2]) / 2])
    root = empty(f"{name}", location, (tilt[0], tilt[1], yaw), parent)
    for piece_name, (verts, faces) in pieces.items():
        v = (verts - center) * k
        blender_verts = np.stack([v[:, 0], -v[:, 2], v[:, 1]], 1)
        mesh = R.mesh_from_arrays(f"{name}:{piece_name}:{height:.2f}", blender_verts, faces)
        color = (colors or {}).get(piece_name) or base_colors.get(piece_name, (200, 200, 200))
        kind = "Metal" if piece_name in ("Cup", "Chassis", "Basket") else "SmoothPlastic"
        mesh_object(f"{name}.{piece_name}", mesh, mat(color, kind, emission=(emission or {}).get(piece_name)), (0, 0, 0),
                    (0, 0, 0), (1, 1, 1), root)
    return root


# Faces ------------------------------------------------------------------------------------------
# Drawn like Roblox's face decals, on the head's surface unrolled: s is the distance around the head
# from the middle of the face (studs, + toward the viewer's right), z the height from its center.

HEAD_R, HEAD_H = 0.62, 1.24
FACE_W = 2048
FACE_H = round(FACE_W * HEAD_H / (math.pi * HEAD_R))
FACE_K = FACE_W / (math.pi * HEAD_R)  # pixels per stud
INK = (28, 20, 38, 255)
WHITE = (255, 255, 255, 255)
MOUTH = (110, 24, 48, 255)
TONGUE = (255, 112, 130, 255)
BLUSH = (255, 110, 140, 105)
SWEAT = (130, 205, 255, 255)


class FaceDrawing:
    SS = 2  # drawn at twice the size, then scaled down (smooth edges)

    def __init__(self):
        self.image = Image.new("RGBA", (FACE_W * self.SS, FACE_H * self.SS), (0, 0, 0, 0))
        self.draw = ImageDraw.Draw(self.image)

    def p(self, s, z):
        return ((FACE_W / 2 + s * FACE_K) * self.SS, (FACE_H / 2 - z * FACE_K) * self.SS)

    def r(self, v):
        return v * FACE_K * self.SS

    def ellipse(self, s, z, w, h, fill, outline=None, width=0.0):
        x, y = self.p(s, z)
        rw, rh = self.r(w / 2), self.r(h / 2)
        if outline:
            o = self.r(width)
            self.draw.ellipse([x - rw - o, y - rh - o, x + rw + o, y + rh + o], fill=outline)
        self.draw.ellipse([x - rw, y - rh, x + rw, y + rh], fill=fill)

    def line(self, points, width, fill=INK):
        pts = [self.p(s, z) for s, z in points]
        w = self.r(width)
        self.draw.line(pts, fill=fill, width=max(1, int(w)), joint="curve")
        for x, y in (pts[0], pts[-1]):
            self.draw.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=fill)

    def curve(self, fn, width, fill=INK, steps=40):
        self.line([fn(i / steps) for i in range(steps + 1)], width, fill)

    def polygon(self, points, fill):
        self.draw.polygon([self.p(s, z) for s, z in points], fill=fill)

    def result(self):
        return self.image.resize((FACE_W, FACE_H), Image.LANCZOS)


def _mouth_outline(cx, cz, w, h, top_curve, steps=48):
    """An open mouth: a top edge (sagging by top_curve * h; negative arches it) over a round bottom."""
    top = [(cx - w / 2 + w * i / steps, cz + h / 2 - top_curve * h * math.sin(math.pi * i / steps)) for i in range(steps + 1)]
    bottom = [(cx + math.cos(math.pi * i / steps) * w / 2, cz + h / 2 - h * math.sin(math.pi * i / steps))
              for i in range(1, steps)]
    return top, top + bottom


def _open_mouth(f, cx, cz, w, h, top_curve=0.0, teeth=True, tongue=True, outline=0.034):
    top, shape = _mouth_outline(cx, cz, w, h, top_curve)
    f.polygon(shape, MOUTH)
    inside = Image.new("RGBA", f.image.size, (0, 0, 0, 0))
    inner = ImageDraw.Draw(inside)
    if teeth:
        band = top + [(s, z - h * 0.22) for s, z in reversed(top)]
        inner.polygon([f.p(s, z) for s, z in band], fill=WHITE)
    if tongue:
        x, y = f.p(cx + w * 0.06, cz - h * 0.45)
        rw, rh = f.r(w * 0.3), f.r(h * 0.34)
        inner.ellipse([x - rw, y - rh, x + rw, y + rh], fill=TONGUE)
    mask = Image.new("L", f.image.size, 0)
    ImageDraw.Draw(mask).polygon([f.p(s, z) for s, z in shape], fill=255)
    f.image.paste(inside, (0, 0), ImageChops.multiply(inside.getchannel("A"), mask))
    f.line(shape + [shape[0], shape[1]], outline)


def _eye(f, s, z, w, h, pupil=0.0, look=(0.0, 0.0), outline=0.034):
    f.ellipse(s, z, w, h, WHITE, INK, outline)
    if pupil:
        ps, pz = s + look[0], z + look[1]
        f.ellipse(ps, pz, pupil, pupil * 1.15, INK)
        f.ellipse(ps - pupil * 0.2, pz + pupil * 0.25, pupil * 0.36, pupil * 0.36, WHITE)


def _oval_eye(f, s, z, w, h):
    f.ellipse(s, z, w, h, INK)
    f.ellipse(s - w * 0.14, z + h * 0.22, w * 0.4, w * 0.4, WHITE)


def _sweat(f, s, z, size):
    drop = [(s + math.sin(a) * size * 0.42 * math.sin(a / 2) ** 1.5, z + math.cos(a) * size * 0.6)
            for a in (2 * math.pi * i / 48 for i in range(49))]
    f.polygon(drop, INK)
    inner = [(s + (x - s) * 0.8, z - size * 0.06 + (y - z) * 0.8) for x, y in drop]
    f.polygon(inner, SWEAT)
    f.ellipse(s - size * 0.08, z - size * 0.2, size * 0.13, size * 0.19, WHITE)


def draw_face(kind):
    f = FaceDrawing()
    if kind == "panic":
        for side in (-1, 1):
            _eye(f, side * 0.2, 0.12, 0.27, 0.33, pupil=0.09, look=(side * -0.025, -0.035))
            f.line([(side * 0.07, 0.38), (side * 0.32, 0.31)], 0.055)
        _open_mouth(f, 0, -0.26, 0.44, 0.25, top_curve=-0.1)
        _sweat(f, 0.44, 0.3, 0.17)
    elif kind == "scream":
        for side in (-1, 1):
            _eye(f, side * 0.19, 0.15, 0.3, 0.31, pupil=0.065)
            f.curve(lambda t, side=side: (side * (0.06 + 0.27 * t), 0.405 + 0.055 * math.sin(math.pi * t) - 0.06 * t), 0.052)
        _open_mouth(f, 0, -0.27, 0.32, 0.34, top_curve=-0.22, teeth=False)
        _sweat(f, -0.45, 0.3, 0.15)
        _sweat(f, 0.46, 0.22, 0.13)
    elif kind == "happy":
        for side in (-1, 1):
            _oval_eye(f, side * 0.17, 0.12, 0.12, 0.22)
            f.ellipse(side * 0.33, -0.08, 0.15, 0.08, BLUSH)
        f.curve(lambda t: (-0.24 + 0.48 * t, -0.13 - 0.12 * math.sin(math.pi * t)), 0.05)
    elif kind == "grin":
        for side in (-1, 1):
            _oval_eye(f, side * 0.18, 0.14, 0.12, 0.22)
            f.ellipse(side * 0.35, -0.06, 0.14, 0.08, BLUSH)
        _open_mouth(f, 0, -0.2, 0.46, 0.24, top_curve=0.06)
    elif kind == "laugh":
        for side in (-1, 1):
            f.curve(lambda t, side=side: (side * 0.19 - 0.1 + 0.2 * t, 0.12 + 0.08 * math.sin(math.pi * t)), 0.05)
            f.ellipse(side * 0.35, -0.05, 0.15, 0.08, BLUSH)
        _open_mouth(f, 0, -0.2, 0.48, 0.28, top_curve=0.03)
    elif kind == "determined":
        for side in (-1, 1):
            _oval_eye(f, side * 0.17, 0.1, 0.13, 0.2)
            f.line([(side * 0.06, 0.24), (side * 0.3, 0.33)], 0.06)
        _open_mouth(f, 0, -0.2, 0.42, 0.16, tongue=False)
    elif kind == "smug":
        for side in (-1, 1):
            _oval_eye(f, side * 0.17, 0.11, 0.12, 0.2)
        f.line([(-0.28, 0.28), (-0.07, 0.3)], 0.05)
        f.line([(0.07, 0.31), (0.28, 0.37)], 0.05)
        f.curve(lambda t: (-0.2 + 0.42 * t, -0.17 - 0.08 * math.sin(math.pi * t) + 0.08 * t), 0.05)
    elif kind == "shock":
        for side in (-1, 1):
            _eye(f, side * 0.19, 0.12, 0.25, 0.3, pupil=0.07)
            f.line([(side * 0.09, 0.36), (side * 0.3, 0.38)], 0.05)
        f.ellipse(0, -0.24, 0.16, 0.2, MOUTH, INK, 0.034)
    else:
        raise ValueError(f"unknown face {kind}")
    return f.result()


def face_png(kind):
    FACE_DIR.mkdir(parents=True, exist_ok=True)
    path = FACE_DIR / f"face_{kind}.png"
    if not path.exists():
        draw_face(kind).save(path)
    return path


def head_mesh():
    """Roblox's classic head: a cylinder with well-rounded top and bottom edges, UV-mapped around its
    side so a face decal wraps the front."""
    if "head" in BOX_MESHES:
        return BOX_MESHES["head"]
    # The profile (radius, height) from the bottom center to the top center, turned around Z.
    half, corner, segments = HEAD_H / 2, 0.27, 64
    profile = [(0.0, -half)]
    for index in range(9):
        a = math.radians(-90 + index * 90 / 8)
        profile.append((HEAD_R - corner + corner * math.cos(a), -half + corner + corner * math.sin(a)))
    for index in range(1, 6):
        profile.append((HEAD_R, -half + corner + (HEAD_H - 2 * corner) * index / 6))
    for index in range(9):
        a = math.radians(index * 90 / 8)
        profile.append((HEAD_R - corner + corner * math.cos(a), half - corner + corner * math.sin(a)))
    profile.append((0.0, half))
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        if r < 1e-6:
            rings.append([bm.verts.new((0, 0, z))])
            continue
        rings.append([bm.verts.new((math.sin(math.tau * i / segments) * r, -math.cos(math.tau * i / segments) * r, z))
                      for i in range(segments)])
    for lower, upper in zip(rings, rings[1:]):
        for i in range(segments):
            j = (i + 1) % segments
            if len(lower) == 1:
                bm.faces.new((lower[0], upper[j], upper[i]))
            elif len(upper) == 1:
                bm.faces.new((lower[i], lower[j], upper[0]))
            else:
                bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
    bm.normal_update()
    uv = bm.loops.layers.uv.new("UVMap")
    for face in bm.faces:
        center = face.calc_center_median()
        middle = math.atan2(center.x, -center.y)
        for loop in face.loops:
            co = loop.vert.co
            angle = math.atan2(co.x, -co.y) if co.xy.length > 1e-6 else middle
            if angle - middle > math.pi:
                angle -= 2 * math.pi
            elif angle - middle < -math.pi:
                angle += 2 * math.pi
            loop[uv].uv = (0.5 + angle / math.pi, 0.5 + co.z / HEAD_H)
    mesh = bpy.data.meshes.new("head")
    bm.to_mesh(mesh)
    bm.free()
    mesh.shade_smooth()
    mesh.materials.append(None)
    BOX_MESHES["head"] = mesh
    return mesh


def head_material(skin, kind):
    key = ("head", tuple(skin), kind)
    if key not in MATERIALS:
        material = bpy.data.materials.new(f"head_{kind}")
        material.use_nodes = True
        nodes, links = material.node_tree.nodes, material.node_tree.links
        skin_bsdf = nodes["Principled BSDF"]
        skin_bsdf.inputs["Base Color"].default_value = (*[R.srgb_to_linear(c) for c in skin], 1)
        skin_bsdf.inputs["Roughness"].default_value = 0.45
        decal = nodes.new("ShaderNodeBsdfPrincipled")
        decal.inputs["Roughness"].default_value = 0.4
        texture = nodes.new("ShaderNodeTexImage")
        texture.image = bpy.data.images.load(str(face_png(kind)), check_existing=True)
        texture.extension = "CLIP"
        links.new(texture.outputs["Color"], decal.inputs["Base Color"])
        mix = nodes.new("ShaderNodeMixShader")
        links.new(texture.outputs["Alpha"], mix.inputs[0])
        links.new(skin_bsdf.outputs[0], mix.inputs[1])
        links.new(decal.outputs[0], mix.inputs[2])
        links.new(mix.outputs[0], nodes["Material Output"].inputs["Surface"])
        MATERIALS[key] = material
    return MATERIALS[key]


# Avatars ----------------------------------------------------------------------------------------
# Classic blocky (R6) proportions: legs and arms 1 x 1 x 2, torso 2 x 1 x 2, the classic head. The
# root sits between the feet; the avatar faces -Y (toward a camera on the -Y side).

SKINS = [(245, 205, 60), (255, 206, 166), (232, 178, 138), (190, 132, 96), (128, 86, 60)]
LOOKS = [
    # skin, shirt, pants, shoes, hat (None, party, cap, puff, spiky), hat colors
    {"skin": 0, "shirt": (40, 120, 255), "pants": (70, 180, 80), "shoes": (40, 40, 48), "hat": None},
    {"skin": 1, "shirt": (255, 84, 150), "pants": (50, 46, 90), "shoes": (250, 250, 250), "hat": "puff", "hair": (70, 44, 30)},
    {"skin": 3, "shirt": (255, 160, 40), "pants": (40, 70, 140), "shoes": (250, 250, 250), "hat": "cap", "hair": (230, 50, 60)},
    {"skin": 0, "shirt": (156, 108, 255), "pants": (30, 30, 40), "shoes": (255, 214, 64), "hat": "party"},
    {"skin": 2, "shirt": (90, 220, 140), "pants": (245, 245, 250), "shoes": (40, 40, 48), "hat": "spiky", "hair": (250, 210, 90)},
    {"skin": 4, "shirt": (255, 214, 64), "pants": (200, 60, 80), "shoes": (250, 250, 250), "hat": "puff", "hair": (30, 24, 26)},
    {"skin": 1, "shirt": (60, 200, 230), "pants": (90, 60, 160), "shoes": (40, 40, 48), "hat": "cap", "hair": (64, 196, 255)},
    {"skin": 0, "shirt": (255, 70, 70), "pants": (40, 52, 110), "shoes": (250, 250, 250), "hat": "spiky", "hair": (60, 40, 30)},
    {"skin": 3, "shirt": (250, 250, 250), "pants": (64, 120, 255), "shoes": (255, 84, 150), "hat": "party"},
    {"skin": 2, "shirt": (140, 90, 255), "pants": (60, 60, 70), "shoes": (250, 250, 250), "hat": "puff", "hair": (200, 90, 40)},
    {"skin": 0, "shirt": (255, 120, 190), "pants": (40, 40, 48), "shoes": (64, 196, 255), "hat": None},
    {"skin": 1, "shirt": (64, 160, 90), "pants": (110, 70, 40), "shoes": (40, 40, 48), "hat": "spiky", "hair": (30, 24, 26)},
]

# Joint angles in degrees: arms and legs are (swing forward, spread outward), the head is (nod down,
# roll toward the avatar's left, turn toward its left).
POSES = {
    "stand": {"arm_l": (0, 4), "arm_r": (0, 4)},
    "cheer": {"arm_l": (10, 140), "arm_r": (10, 140), "head": (-8, 0, 0)},
    "wave": {"arm_l": (5, 150), "arm_r": (0, 8)},
    "run": {"arm_l": (55, 6), "arm_r": (-45, 6), "leg_l": (-40, 0), "leg_r": (40, 0)},
    "sprint": {"arm_l": (-60, 10), "arm_r": (70, 10), "leg_l": (55, 0), "leg_r": (-45, 0), "head": (-5, 0, 0)},
    "jump": {"arm_l": (20, 150), "arm_r": (20, 150), "leg_l": (55, 6), "leg_r": (25, 6), "head": (-10, 0, 0)},
    "tuck": {"arm_l": (40, 135), "arm_r": (35, 145), "leg_l": (85, 4), "leg_r": (70, 4), "head": (-12, 0, 0)},
    "panic": {"arm_l": (35, 150), "arm_r": (35, 150), "head": (-6, 0, 0)},
    "flail": {"arm_l": (40, 120), "arm_r": (-30, 160), "leg_l": (30, 10), "leg_r": (-25, 14)},
    "point": {"arm_l": (85, 15), "arm_r": (0, 8), "head": (0, 0, 10)},
    "sit": {"arm_l": (40, 10), "arm_r": (40, 10), "leg_l": (90, 6), "leg_r": (90, 6)},
    "lean_left": {"arm_l": (60, 60), "arm_r": (80, 20), "leg_l": (90, 6), "leg_r": (90, 6), "head": (0, 12, 0)},
    "lean_right": {"arm_l": (80, 20), "arm_r": (60, 60), "leg_l": (90, 6), "leg_r": (90, 6), "head": (0, -12, 0)},
    "dance": {"arm_l": (0, 120), "arm_r": (-10, 30), "leg_l": (0, 18), "leg_r": (20, 0), "head": (0, -10, 0)},
}


def look_of(look):
    if isinstance(look, dict):
        return look
    return LOOKS[look % len(LOOKS)]


def avatar(location, yaw=0.0, pose="stand", look=0, face="happy", tilt=(0, 0), scale=1.0, hat="default", pose_extra=None,
           head_scale=1.0):
    lk = look_of(look)
    skin = SKINS[lk["skin"]] if isinstance(lk["skin"], int) else lk["skin"]
    p = dict(POSES[pose]) if isinstance(pose, str) else dict(pose)
    p.update(pose_extra or {})
    root = empty("avatar", location, (tilt[0], tilt[1], yaw))
    root.scale = (scale, scale, scale)
    rounded_box("torso", (2, 1, 2), lk["shirt"], (0, 0, 3), parent=root, bevel=0.14)
    for side, key in ((1, "leg_l"), (-1, "leg_r")):
        swing, spread = p.get(key, (0, 0))
        hip = empty("hip", (side * 0.5, 0, 2.0), (math.radians(-swing), math.radians(-side * spread), 0), root)
        rounded_box("leg", (1, 1, 2), lk["pants"], (0, 0, -1), parent=hip, bevel=0.1)
        rounded_box("shoe", (1.05, 1.08, 0.42), lk["shoes"], (0, -0.03, -1.8), parent=hip, bevel=0.1)
    for side, key in ((1, "arm_l"), (-1, "arm_r")):
        swing, spread = p.get(key, (0, 4))
        shoulder = empty("shoulder", (side * 1.0, 0, 3.5), (math.radians(-swing), math.radians(-side * spread), 0), root)
        sleeve = two_tone(lk["shirt"], skin, lk.get("sleeve", 0.25))
        # A hair thinner than the torso, so a raised arm's top hides inside it instead of flickering.
        rounded_box("arm", (1, 0.97, 2), skin, (side * 0.5, 0, -0.5), parent=shoulder, bevel=0.1, material=sleeve)
    nod, roll, turn = p.get("head", (0, 0, 0))
    neck = empty("neck", (0, 0, 4.0), (math.radians(nod), math.radians(roll), math.radians(turn)), root)
    neck.scale = (head_scale, head_scale, head_scale)
    mesh_object("head", head_mesh(), head_material(skin, face), (0, 0, 0.6), (0, 0, 0), (1, 1, 1), neck)
    hat = lk.get("hat") if hat == "default" else hat
    if hat:
        headwear(neck, hat, lk)
    return root


def headwear(neck, kind, lk):
    top = 0.6 + HEAD_H / 2
    hair = lk.get("hair", (60, 40, 30))
    if kind == "party":
        colors = lk.get("hat_colors", ((255, 84, 150), (255, 230, 90)))
        holder = empty("hat", (0.12, 0.05, top - 0.12), (0.05, 0.28, 0), neck)
        cone("hat", 0.52, 1.35, striped(*colors, frequency=10, twist=1.0), (0, 0, 0), parent=holder)
        ball("pompom", 0.38, colors[1], (0, 0, 1.38), holder)
    elif kind == "cap":
        color = lk.get("hat_color", hair)
        ball("cap", 1.0, color, (0, 0, top - 0.3), neck, scale=(1.36, 1.36, 0.92))
        rounded_box("brim", (1.0, 0.75, 0.1), color, (0, -0.78, top - 0.3), (math.radians(-8), 0, 0), 0.05, neck)
    elif kind == "puff":
        ball("hair", 1.0, hair, (0, 0.06, top - 0.24), neck, scale=(1.42, 1.42, 0.98))
        ball("bun", 0.62, hair, (0, 0.38, top + 0.12), neck)
    elif kind == "spiky":
        ball("hair", 1.0, hair, (0, 0.05, top - 0.26), neck, scale=(1.38, 1.38, 0.9))
        for index in range(7):
            angle = math.radians(-80 + index * 26)
            base = V((math.sin(angle) * 0.38, math.cos(angle) * 0.28 + 0.05, top + 0.02))
            cone("spike", 0.24, 0.62, mat(hair), base, (math.radians(-14) * math.cos(angle) - 0.25,
                                                        math.radians(22) * math.sin(angle), 0), neck, vertices=16)


def face_to(position, target):
    """Yaw that turns an avatar (front = -Y) toward `target` (x, y)."""
    return math.atan2(target[0] - position[0], -(target[1] - position[1]))


def hand_point(root, side=1):
    """World position of an avatar's hand (side 1 = arm_l, -1 = arm_r)."""
    bpy.context.view_layer.update()
    for child in root.children:
        if child.name.startswith("shoulder") and abs(child.location.x - side * 1.0) < 0.01:
            return child.matrix_world @ V((side * 0.5, 0, -1.5))
    return root.matrix_world.translation


# Effects ----------------------------------------------------------------------------------------


def confetti(count, center, spread, seed=1, size=0.5, emission=0.4, colors=PARTY, avoid=()):
    """Confetti pieces scattered in a box around `center`, none inside the `avoid` spheres
    ((center, radius) pairs: keep faces clear)."""
    rng = random.Random(seed)
    for index in range(count):
        offset = V((rng.uniform(-1, 1) * spread[0], rng.uniform(-1, 1) * spread[1], rng.uniform(-1, 1) * spread[2]))
        if any((V(center) + offset - V(c)).length < r for c, r in avoid):
            continue
        color = colors[index % len(colors)]
        s = size * rng.uniform(0.7, 1.25)
        rounded_box("confetti", (s, s * 0.6, s * 0.08), color, V(center) + offset,
                    (rng.uniform(0, 6.3), rng.uniform(0, 6.3), rng.uniform(0, 6.3)), 0, emission=emission)


def streamer(start, direction, length, color, seed=0, width=0.35, turns=2.5, radius=0.5):
    """A curly paper streamer: a flat ribbon on a loose spiral."""
    rng = random.Random(seed)
    direction = V(direction).normalized()
    side = direction.cross(V((0, 0, 1)))
    side = side.normalized() if side.length > 1e-3 else V((1, 0, 0))
    up = side.cross(direction).normalized()
    points = []
    for index in range(40):
        t = index / 39
        angle = t * turns * math.tau + rng.uniform(0, 0.3)
        r = radius * (0.6 + 0.4 * t)
        points.append(V(start) + direction * (t * length) + side * math.cos(angle) * r + up * math.sin(angle) * r)
    curve = bpy.data.curves.new("streamer", "CURVE")
    curve.dimensions = "3D"
    curve.extrude = width / 2
    curve.twist_mode = "MINIMUM"
    spline = curve.splines.new("NURBS")
    spline.points.add(len(points) - 1)
    for point, co in zip(spline.points, points):
        point.co = (*co, 1)
    spline.use_endpoint_u = True
    spline.order_u = 3
    curve.materials.append(mat(color, emission=0.35))
    return link(bpy.data.objects.new("streamer", curve))


def streaks(start, direction, count=5, length=6, seed=3, color=(255, 255, 255), spread=1.6, width=0.12):
    rng = random.Random(seed)
    direction = V(direction).normalized()
    side = direction.cross(V((0, 0, 1))).normalized()
    up = side.cross(direction).normalized()
    for index in range(count):
        offset = side * rng.uniform(-spread, spread) + up * rng.uniform(-spread, spread)
        middle = V(start) + offset - direction * (length / 2 + rng.uniform(0, 2))
        obj = cylinder("streak", width, length * rng.uniform(0.6, 1.0), color, middle, material=glow(color, 3.0, 0.85))
        obj.rotation_euler = direction.to_track_quat("X", "Z").to_euler()


def fire_material(core=(255, 236, 140), middle=(255, 140, 30), tip=(235, 40, 20), strength=3.0):
    """Cartoon fire: yellow-white at the root of a flame, orange, then red at its tip, with soft
    edges (for flame_mesh, whose local height runs from about 0 to 1)."""
    key = ("fire", tuple(core), tuple(middle), tuple(tip), strength)
    if key not in MATERIALS:
        material = bpy.data.materials.new("fire")
        material.use_nodes = True
        nodes, links = material.node_tree.nodes, material.node_tree.links
        nodes.remove(nodes["Principled BSDF"])
        coords = nodes.new("ShaderNodeTexCoord")
        split = nodes.new("ShaderNodeSeparateXYZ")
        links.new(coords.outputs["Object"], split.inputs[0])
        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.12
        ramp.color_ramp.elements[0].color = (*[R.srgb_to_linear(c) for c in core], 1)
        ramp.color_ramp.elements[1].position = 0.9
        ramp.color_ramp.elements[1].color = (*[R.srgb_to_linear(c) for c in tip], 1)
        stop = ramp.color_ramp.elements.new(0.45)
        stop.color = (*[R.srgb_to_linear(c) for c in middle], 1)
        links.new(split.outputs["Z"], ramp.inputs["Fac"])
        emit = nodes.new("ShaderNodeEmission")
        emit.inputs["Strength"].default_value = strength
        links.new(ramp.outputs["Color"], emit.inputs["Color"])
        facing = nodes.new("ShaderNodeLayerWeight")
        facing.inputs["Blend"].default_value = 0.5
        fade = nodes.new("ShaderNodeMath")
        fade.operation = "SUBTRACT"
        fade.inputs[0].default_value = 1.25
        fade.use_clamp = True
        links.new(facing.outputs["Facing"], fade.inputs[1])
        clear = nodes.new("ShaderNodeBsdfTransparent")
        mix = nodes.new("ShaderNodeMixShader")
        links.new(fade.outputs[0], mix.inputs[0])
        links.new(clear.outputs[0], mix.inputs[1])
        links.new(emit.outputs[0], mix.inputs[2])
        links.new(mix.outputs[0], nodes["Material Output"].inputs["Surface"])
        MATERIALS[key] = material
    return MATERIALS[key]


def flame_mesh():
    """A cartoon flame: a round bottom drawn up into a point (height 1 above its round bottom)."""
    if "flame" in BOX_MESHES:
        return BOX_MESHES["flame"]
    profile = [(0.0, -0.42)]
    for index in range(1, 7):
        a = math.radians(-90 + index * 90 / 6)
        profile.append((0.42 * math.cos(a), 0.42 * math.sin(a)))
    for index in range(1, 12):
        t = index / 12
        profile.append((0.42 * (1 - t) ** 1.7 * (1 + 0.6 * t), t))
    profile.append((0.0, 1.0))
    segments = 20
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        if r < 1e-6:
            rings.append([bm.verts.new((0, 0, z))])
        else:
            rings.append([bm.verts.new((math.cos(math.tau * i / segments) * r, math.sin(math.tau * i / segments) * r, z))
                          for i in range(segments)])
    for lower, upper in zip(rings, rings[1:]):
        for i in range(segments):
            j = (i + 1) % segments
            if len(lower) == 1:
                bm.faces.new((lower[0], upper[i], upper[j]))
            elif len(upper) == 1:
                bm.faces.new((lower[i], lower[j], upper[0]))
            else:
                bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
    bm.normal_update()
    mesh = bpy.data.meshes.new("flame")
    bm.to_mesh(mesh)
    bm.free()
    mesh.shade_smooth()
    mesh.materials.append(None)
    BOX_MESHES["flame"] = mesh
    return mesh


def flame(location, height, direction=(0, 0, 1), width=1.0, material=None, seed=0):
    """A cartoon flame: a tall tongue with two shorter ones leaning out of its sides."""
    rng = random.Random(seed)
    root = empty("flame", location)
    root.rotation_euler = V(direction).normalized().to_track_quat("Z", "Y").to_euler()
    material = material or fire_material()
    for lean, size, side in ((0, 1.0, 0), (-24, rng.uniform(0.5, 0.7), -1), (26, rng.uniform(0.45, 0.65), 1)):
        tongue = mesh_object("tongue", flame_mesh(), material, (side * 0.16 * height * width, 0, 0),
                             (0, math.radians(lean + rng.uniform(-6, 6)), 0),
                             (height * width * size, height * width * size, height * size), root)
        tongue.visible_shadow = False
    return root


def embers(count, center, spread, seed=2, size=(0.15, 0.4), color=(255, 200, 90), strength=10):
    rng = random.Random(seed)
    for _ in range(count):
        offset = V((rng.uniform(-1, 1) * spread[0], rng.uniform(-1, 1) * spread[1], rng.uniform(-1, 1) * spread[2]))
        ball("ember", rng.uniform(*size), color, V(center) + offset, material=glow(color, strength))


def fire_rope(points, radius=0.42, flames=1.0, seed=5, trail=(0, 0, 1), heat=1.0):
    """The Fire Rope as the game draws it: white-gold fireballs threaded on a white-hot core inside a
    deep-red rim, licked by flames (which stream toward `trail`)."""
    rng = random.Random(seed)
    tube("rope_core", points, radius, glow((255, 226, 150), 3.2 * heat))
    tube("rope_rim", points, radius * 1.9, glow((230, 40, 25), 2.0 * heat, alpha=0.65))
    curve_points = [V(p) for p in points]
    samples = []
    for a, b in zip(curve_points, curve_points[1:]):
        steps = max(1, int((b - a).length / (radius * 2.6)))
        samples += [a.lerp(b, i / steps) for i in range(steps)]
    hot = fire_material(strength=2.2 * heat)
    for index, point in enumerate(samples):
        big = index % 2 == 0
        ball("fireball", radius * (2.2 if big else 1.8), (255, 222, 140), point,
             material=glow((255, 200, 100) if big else (255, 160, 50), 1.8 * heat))
        if flames and index % 2 == 0:
            direction = V(trail).normalized() + V((rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), rng.uniform(-0.2, 0.2)))
            flame(point, radius * rng.uniform(4.5, 7.5) * flames, direction, width=rng.uniform(0.9, 1.15), material=hot,
                  seed=index + seed)


# Snapshots of the real game -----------------------------------------------------------------------

R15 = {
    "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm",
    "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg",
    "RightLowerLeg", "RightFoot",
}


def load_dump(args, name):
    path = Path(args.dumps) / f"{name}.json"
    if not path.exists():
        raise SystemExit(f"No snapshot {path}: make the snapshots first (--fetch)")
    data = json.loads(path.read_text())
    data = data[0] if isinstance(data, list) else data
    return json.loads(data) if isinstance(data, str) else data


def split_rigs(parts):
    """Takes the stand-in players' rigs out of a snapshot. Returns the other parts and, for each rig,
    where it stands (Roblox: the point between its feet) and which way it faces (a Roblox yaw)."""
    rest, groups = [], []
    for part in parts:
        if part["c"] == "MeshPart" and part["n"] in R15 and not part.get("prop"):
            if not groups or part["n"] in groups[-1]:
                groups.append({})
            groups[-1][part["n"]] = part
        else:
            rest.append(part)
    rigs = []
    for group in groups:
        torso = group.get("UpperTorso") or next(iter(group.values()))
        cf = torso["cf"]
        feet = min((group[n]["cf"][1] - group[n]["s"][1] / 2 for n in ("LeftFoot", "RightFoot") if n in group),
                   default=cf[1] - 3)
        look = (-cf[5], -cf[11])  # the torso's -Z column (x, z)
        rigs.append({"x": cf[0], "y": feet, "z": cf[2], "yaw": math.atan2(-look[0], -look[1])})
    return rest, rigs


def build_arena(data, parts=None, drop=()):
    parts = data["parts"] if parts is None else parts
    R.build_parts([p for p in parts if p["n"] not in drop])
    R.build_terrain(data["terrain"])


def fetch(dumps: Path):
    """Snapshots of the lobby and the featured arenas, made on a test server."""
    from make_preview import dump_round  # tools/preview

    dumps.mkdir(parents=True, exist_ok=True)
    task = Path(tempfile.gettempdir()) / "pp_art_lobby.luau"
    task.write_text(subprocess.run([sys.executable, str(PREVIEW / "bundle.py")], cwd=ROOT, check=True,
                                   capture_output=True, text=True).stdout)
    subprocess.run([sys.executable, str(PREVIEW / "luau_task.py"), str(task), "-", str(dumps / "lobby.json")], cwd=ROOT,
                   check=True)
    for game, at in FEATURED.items():
        shutil.copy(dump_round(game, at, 8), dumps / f"{game}.json")
    print("snapshots in", dumps)


# Lettering and finishing --------------------------------------------------------------------------


def lettering(image, text, center, size, top=(255, 240, 90), bottom=(255, 150, 30), outline=(60, 20, 110),
              stroke=None, angle=0.0, shadow=True):
    font = ImageFont.truetype(FONT, size)
    stroke = stroke if stroke is not None else max(4, size // 9)
    left, upper, right, lower = font.getbbox(text, stroke_width=stroke)
    pad = stroke * 3
    w, h = right - left + pad * 2, lower - upper + pad * 2
    origin = (pad - left, pad - upper)
    layer = Image.new("RGBA", (w, h + size // 6), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    if shadow:
        shadow_layer = Image.new("RGBA", layer.size, (0, 0, 0, 0))
        ImageDraw.Draw(shadow_layer).text((origin[0], origin[1] + size // 10), text, font=font, fill=(30, 10, 60, 200),
                                          stroke_width=stroke, stroke_fill=(30, 10, 60, 200))
        layer = Image.alpha_composite(layer, shadow_layer.filter(ImageFilter.GaussianBlur(size / 40)))
        draw = ImageDraw.Draw(layer)
    draw.text(origin, text, font=font, fill=(*outline, 255), stroke_width=stroke, stroke_fill=(*outline, 255))
    mask = Image.new("L", layer.size, 0)
    ImageDraw.Draw(mask).text(origin, text, font=font, fill=255)
    gradient = Image.new("RGBA", layer.size)
    gdraw = ImageDraw.Draw(gradient)
    for y in range(layer.size[1]):
        t = min(1, max(0, (y - origin[1] - size * 0.1) / (size * 0.8)))
        gdraw.line([(0, y), (layer.size[0], y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
    layer.paste(gradient, (0, 0), mask)
    # A soft shine on the upper half of the letters.
    shine = Image.new("L", layer.size, 0)
    ImageDraw.Draw(shine).text((origin[0], origin[1] - size // 30), text, font=font, fill=70)
    shine_cut = Image.new("L", layer.size, 0)
    ImageDraw.Draw(shine_cut).rectangle([0, 0, layer.size[0], origin[1] + int(size * 0.42)], fill=255)
    shine = ImageChops.multiply(ImageChops.multiply(shine, shine_cut), mask)
    white = Image.new("RGBA", layer.size, (255, 255, 255, 255))
    layer.paste(white, (0, 0), shine)
    if angle:
        layer = layer.rotate(angle, resample=Image.BICUBIC, expand=True)
    x = int(center[0] - layer.size[0] / 2)
    y = int(center[1] - layer.size[1] / 2)
    image.alpha_composite(layer, (x, y))
    return image


def grade(path, saturation=1.12, contrast=1.06):
    image = Image.open(path).convert("RGBA")
    rgb = ImageEnhance.Contrast(ImageEnhance.Color(image.convert("RGB")).enhance(saturation)).enhance(contrast)
    out = rgb.convert("RGBA")
    out.putalpha(image.getchannel("A"))
    return out


def bloom(image, threshold=215, radius=0.02, strength=0.9):
    """Lets the brightest parts (fire, neon, sparks) glow into their surroundings."""
    rgb = image.convert("RGB")
    bright = rgb.point(lambda v: max(0, v - threshold) * 255 // max(1, 255 - threshold))
    size = max(image.size)
    halo = Image.new("RGB", image.size)
    for k, weight in ((1, 0.6), (3, 0.4)):
        blurred = bright.filter(ImageFilter.GaussianBlur(size * radius * k))
        halo = ImageChops.add(halo, blurred.point(lambda v, w=weight: int(v * w * strength)))
    lit = ImageChops.screen(rgb, halo).convert("RGBA")
    lit.putalpha(image.getchannel("A"))
    return lit


def vignette(image, strength=0.35, color=(20, 6, 40)):
    w, h = image.size
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).ellipse([-w * 0.25, -h * 0.25, w * 1.25, h * 1.25], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(min(w, h) * 0.18))
    dark = Image.new("RGBA", (w, h), (*color, 255))
    shade = ImageChops.invert(mask).point(lambda v: int(v * strength))
    out = image.copy()
    out.paste(dark, (0, 0), shade)
    return out


def sticker_outline(layer, width, color=(40, 14, 70), soften=1.5):
    """A solid outline around everything opaque in `layer` (the character pops off the background)."""
    alpha = layer.getchannel("A").point(lambda v: 255 if v > 90 else 0)
    grown = alpha.filter(ImageFilter.MaxFilter(2 * (width // 2) + 1))
    if width > 2 * (width // 2) + 1:
        grown = grown.filter(ImageFilter.MaxFilter(3))
    grown = grown.filter(ImageFilter.GaussianBlur(soften)).point(lambda v: 255 if v > 110 else int(v * 2.2))
    out = Image.new("RGBA", layer.size, (*color, 0))
    out.putalpha(grown)
    out.alpha_composite(layer)
    return out


def sunburst(size, center, inner, outer, rays=16, ray_light=46, spin=0.0):
    """A radial gradient with alternating lighter rays."""
    w, h = size
    background = Image.new("RGBA", size)
    draw = ImageDraw.Draw(background)
    reach = math.hypot(max(center[0], w - center[0]), max(center[1], h - center[1]))
    for r in range(int(reach), 0, -3):
        t = (r / reach) ** 0.9
        color = tuple(int(a + (b - a) * t) for a, b in zip(inner, outer))
        draw.ellipse([center[0] - r, center[1] - r, center[0] + r, center[1] + r], fill=color + (255,))
    beams = Image.new("L", size, 0)
    bdraw = ImageDraw.Draw(beams)
    for index in range(rays):
        a0 = spin + index * math.tau / rays
        a1 = a0 + math.tau / rays / 2
        bdraw.polygon([center, (center[0] + math.cos(a0) * reach * 1.5, center[1] + math.sin(a0) * reach * 1.5),
                       (center[0] + math.cos(a1) * reach * 1.5, center[1] + math.sin(a1) * reach * 1.5)], fill=ray_light)
    background.paste(Image.new("RGBA", size, (255, 255, 255, 255)), (0, 0), beams.filter(ImageFilter.GaussianBlur(2)))
    return background


def render_to(path):
    bpy.context.scene.render.filepath = str(Path(path).resolve())
    bpy.ops.render.render(write_still=True)


def save_jpg(image, path):
    image.convert("RGB").save(path, quality=92, optimize=True)
    print("wrote", path, flush=True)


def render_glow(path, scale=0.25, samples=8):
    """Renders what glows on its own (fire, lava, neon) with the sun and sky off, small: blurred and
    added on top of the picture it becomes the glow around those things."""
    scene = bpy.context.scene
    lights = [obj for obj in scene.objects if obj.type == "LIGHT" and not obj.hide_render]
    strength = scene.world.node_tree.nodes["Background"].inputs["Strength"]
    saved = (strength.default_value, scene.render.resolution_percentage, scene.cycles.samples)
    for obj in lights:
        obj.hide_render = True
    strength.default_value = 0
    scene.render.resolution_percentage = int(100 * scale)
    scene.cycles.samples = samples
    render_to(path)
    for obj in lights:
        obj.hide_render = False
    strength.default_value, scene.render.resolution_percentage, scene.cycles.samples = saved


def add_glow(image, glow_path, radius=0.02, strength=1.0):
    """Screens the blurred glow render over `image`."""
    light = Image.open(glow_path).convert("RGB").resize(image.size, Image.BILINEAR)
    size = max(image.size)
    halo = Image.new("RGB", image.size)
    for k, weight in ((1, 0.5), (3, 0.3), (8, 0.2)):
        blurred = light.filter(ImageFilter.GaussianBlur(size * radius * k))
        halo = ImageChops.add(halo, blurred.point(lambda v, w=weight: min(255, int(v * w * strength))))
    lit = ImageChops.screen(image.convert("RGB"), halo).convert("RGBA")
    lit.putalpha(image.getchannel("A"))
    return lit


# Icons ------------------------------------------------------------------------------------------
# One big, instantly readable character with a loud expression, bold colors, a clean silhouette
# (outlined, so it reads at 150 px in the Discover grid) and a hint of the chaos around it.

ICON_SIZE = 1024


def icon_scene(args, sun=(0.35, -0.8, 0.55), sun_energy=4.2):
    scene = new_scene(args.samples, ICON_SIZE, ICON_SIZE, transparent=True, sun=sun, sun_energy=sun_energy, exposure=-0.15,
                      top=(0.2, 0.25, 0.6), horizon=(0.9, 0.7, 0.9), sky_strength=0.8)
    return scene


def save_icon(image, out, name):
    image = image.convert("RGB")
    path = out / ("icon_512.png" if name == ICON else f"icon_alt_{name}.png")
    image.resize((512, 512), Image.LANCZOS).save(path)
    print("wrote", path, flush=True)
    return path


def icon_compose(out, name, background, outline=16, outline_color=(40, 14, 70), glow_strength=0.75, saturation=1.12):
    layer = grade(out / f"raw_icon_{name}.png", saturation=saturation, contrast=1.05)
    art = sticker_outline(layer, outline, outline_color) if outline else layer
    image = background.copy()
    image.alpha_composite(art)
    image = add_glow(image, out / f"raw_icon_{name}_glow.png", strength=glow_strength)
    return vignette(image, 0.3)


def icon_scream(args, out):
    """A big screaming face, hands up beside it, party hat flying off, the fire rope swinging over
    its head and confetti everywhere."""
    icon_scene(args, sun=(0.45, -0.8, 0.5))
    look = {"skin": 0, "shirt": (90, 215, 70), "pants": (40, 52, 110), "shoes": (250, 250, 250), "hat": None, "sleeve": 0.45}
    avatar((0, 0, 0), math.radians(-10), "panic", look, "scream", head_scale=1.5,
           pose_extra={"arm_l": (-6, 150), "arm_r": (-6, 152), "head": (-5, 5, -4)})
    # The party hat, knocked off and flying.
    holder = empty("hat", (1.45, -0.9, 5.3), (math.radians(18), math.radians(52), 0))
    cone("hat", 0.48, 1.25, striped((110, 226, 140), (255, 230, 90), frequency=9, twist=1.0), (0, 0, 0), parent=holder)
    ball("pompom", 0.36, (255, 84, 150), (0, 0, 1.3), holder)
    # The fire rope sweeping in across the bottom.
    rope = [V((-3.2 + 6.4 * t, -2.5 + 1.0 * t, 2.3 + 0.75 * t + 0.2 * math.sin(math.pi * t))) for t in
            (i / 10 for i in range(11))]
    fire_rope(rope, radius=0.1, seed=3, trail=(-0.2, 0.5, 1), flames=1.3)
    lamp((0.5, -2.2, 1.6), 90, (1.0, 0.5, 0.15), 1.0)
    lamp((-3, -4, 6.5), 50, (0.7, 0.85, 1.0), 2.0)
    face_line = [((0, -0.6 - k, 4.9 - k * 0.05), 1.4 + k * 0.1) for k in (0, 1, 2, 3, 4)]
    confetti(90, (0, 0, 4.8), (4.0, 2.5, 2.6), seed=21, size=0.3, emission=0.5, avoid=face_line)
    cam = camera((0.7, -6.0, 4.3), (0.0, 0, 4.55), fov=46)
    cam.data.dof.use_dof = True
    cam.data.dof.focus_distance = 5.4
    cam.data.dof.aperture_fstop = 9
    render_to(out / "raw_icon_scream.png")
    render_glow(out / "raw_icon_scream_glow.png")
    background = sunburst((ICON_SIZE, ICON_SIZE), (ICON_SIZE * 0.5, ICON_SIZE * 0.45), (255, 120, 210), (88, 26, 160),
                          rays=18, ray_light=40)
    image = icon_compose(out, "scream", background)
    return save_icon(image, out, "scream")


def icon_leap(args, out):
    """Mid-jump over the fire rope, lava glowing below."""
    icon_scene(args, sun=(0.3, -0.7, 0.65), sun_energy=3.6)
    look = {"skin": 0, "shirt": (255, 84, 150), "pants": (40, 52, 110), "shoes": (250, 250, 250), "hat": "party",
            "hat_colors": ((64, 196, 255), (255, 230, 90))}
    avatar((0, 0, 2.0), math.radians(-14), "jump", look, "panic", head_scale=1.35, tilt=(math.radians(-4), math.radians(4)),
           pose_extra={"leg_l": (14, 24), "leg_r": (-6, 24), "arm_l": (15, 140), "arm_r": (15, 146), "head": (6, -4, 0)})
    rope = [V((-8 + 16 * t, 0.3 - 0.9 * math.sin(math.pi * t), 0.9 + 0.2 * math.sin(math.pi * t))) for t in
            (i / 16 for i in range(17))]
    fire_rope(rope, radius=0.14, seed=8, trail=(0, 0.6, 1), flames=1.2)
    lava = rounded_box("lava", (200, 200, 1), (255, 105, 30), (0, 60, -9), bevel=0, kind="CrackedLava")
    lava.visible_shadow = False
    embers(60, (0, 6, -1), (10, 8, 5), seed=4, size=(0.08, 0.2))
    lamp((0, -0.6, 0.6), 90, (1.0, 0.5, 0.15), 1.5)
    lamp((-3, -6, 8), 60, (0.75, 0.85, 1.0), 2.0)
    confetti(36, (0, 0, 6.5), (5.5, 3, 2.2), seed=4, size=0.3, avoid=[((0, -1, 6.3), 1.8)])
    camera((1.4, -9.6, 4.6), (0, 0, 4.3), fov=44)
    render_to(out / "raw_icon_leap.png")
    render_glow(out / "raw_icon_leap_glow.png")
    background = sunburst((ICON_SIZE, ICON_SIZE), (ICON_SIZE * 0.5, ICON_SIZE * 0.42), (255, 200, 90), (200, 40, 110),
                          rays=18, ray_light=40)
    image = icon_compose(out, "leap", background)
    return save_icon(image, out, "leap")


def icon_duo(args, out):
    """PARTY and PANIC side by side: one friend cheering in a party hat, one screaming."""
    icon_scene(args, sun=(0.3, -0.8, 0.55))
    party = {"skin": 3, "shirt": (255, 84, 150), "pants": (60, 60, 70), "shoes": (250, 250, 250), "hat": "party",
             "hat_colors": ((255, 214, 64), (64, 196, 255))}
    panic = {"skin": 0, "shirt": (255, 140, 40), "pants": (40, 52, 110), "shoes": (250, 250, 250), "hat": None}
    avatar((-1.45, 0.7, 0), math.radians(22), "cheer", party, "laugh", head_scale=1.4,
           pose_extra={"arm_l": (10, 130), "arm_r": (10, 140), "head": (-6, -8, 0)})
    avatar((1.45, -0.5, 0), math.radians(-22), "panic", panic, "scream", head_scale=1.4,
           pose_extra={"arm_l": (-5, 150), "arm_r": (-5, 150), "head": (-4, 8, 0)})
    faces = [((-1.45, 0.0, 4.9), 1.3), ((1.45, -1.2, 4.9), 1.3), ((0, -3, 4.9), 2.0)]
    confetti(90, (0, -0.5, 5.2), (5, 2.5, 2.8), seed=13, size=0.28, emission=0.5, avoid=faces)
    for index, color in enumerate(PARTY[:5]):
        streamer((-4.2 + index * 2.1, 0.5 - index * 0.3, 8.2), (0.15 * (index - 2), 0, -1), 3.4, color, seed=index,
                 width=0.22, turns=4.5, radius=0.16)
    lamp((0, 2, 6), 80, (1.0, 0.8, 0.6), 2.0)
    camera((0, -8.0, 4.6), (0, 0, 4.75), fov=44)
    render_to(out / "raw_icon_duo.png")
    render_glow(out / "raw_icon_duo_glow.png")
    background = sunburst((ICON_SIZE, ICON_SIZE), (ICON_SIZE * 0.5, ICON_SIZE * 0.45), (120, 230, 255), (40, 70, 200),
                          rays=18, ray_light=40)
    image = icon_compose(out, "duo", background)
    return save_icon(image, out, "duo")


ICONS = {"scream": icon_scream, "leap": icon_leap, "duo": icon_duo}


# Thumbnails -------------------------------------------------------------------------------------


def part_named(parts, name, prop=None):
    for part in parts:
        if part["n"] == name and (prop is None or part.get("prop") == prop):
            return part
    raise SystemExit(f"no part {name} ({prop}) in the snapshot")


def swing_parts(parts, names, axis_y, axis_z, angle):
    """Turns the named parts about the Roblox X axis through (axis_y, axis_z) to `angle` (radians
    from straight down, toward +Z): the fire rope at the moment we want."""
    for part in parts:
        if part["n"] not in names:
            continue
        cf = part["cf"]
        dy, dz = cf[1] - axis_y, cf[2] - axis_z
        turn = angle - math.atan2(dz, -dy)
        c, s = math.cos(turn), math.sin(turn)
        cf[1], cf[2] = axis_y + dy * c + dz * s, axis_z - dy * s + dz * c
        rows = [cf[3:6], cf[6:9], cf[9:12]]
        rows[1], rows[2] = ([rows[1][i] * c + rows[2][i] * s for i in range(3)],
                            [-rows[1][i] * s + rows[2][i] * c for i in range(3)])
        cf[3:12] = rows[0] + rows[1] + rows[2]


def thumb_finish(out, name, glow_strength=0.5, saturation=1.12, contrast=1.06, vignette_strength=0.28):
    image = grade(out / f"raw_{name}.png", saturation, contrast)
    glow_path = out / f"raw_{name}_glow.png"
    if glow_path.exists():
        image = add_glow(image, glow_path, radius=0.012, strength=glow_strength)
    return vignette(image, vignette_strength)


def scene_firerope(args, out):
    """Jumpers in mid-air over the burning rope, the Dragon Temple pouring lava behind them."""
    data = load_dump(args, "FireRope")
    parts, rigs = split_rigs(data["parts"])
    eye = part_named(parts, "Eye", "SunWheel")["cf"]
    swing_parts(parts, {"Core", "Halo", "Fireball"}, eye[1], eye[2], math.radians(6))
    new_scene(args.samples, args.width, args.height, top=(0.16, 0.22, 0.62), horizon=(1.0, 0.62, 0.36),
              sun=(0.55, -0.35, 0.55), sun_energy=3.6, sun_color=(1.0, 0.9, 0.75))
    build_arena(data, parts)
    rope = [p for p in parts if p["n"] == "Fireball"]
    rng = random.Random(7)
    hot = fire_material(strength=2.2)
    for ball_part in rope[::2]:
        x, y, z = ball_part["cf"][:3]
        flame(B(x, y, z), rng.uniform(1.8, 3.0), (rng.uniform(-0.2, 0.2), -0.5, 1), material=hot, seed=int(x * 10))
    cast = [
        ("tuck", "scream", 2.6), ("jump", "panic", 3.2), ("flail", "shock", 2.2), ("jump", "laugh", 3.4),
        ("tuck", "determined", 2.8), ("jump", "grin", 3.0), ("cheer", "laugh", 2.4), ("flail", "panic", 2.0),
    ]
    eye_at = B(6, 253, 1414)
    rigs.sort(key=lambda rig: rig["x"])
    for index, rig in enumerate(rigs):
        pose, face, lift = cast[index % len(cast)]
        spot = B(rig["x"], 250.0 + lift, rig["z"])
        avatar(spot, face_to(spot, eye_at) + math.radians(rng.uniform(-10, 10)), pose, index + 1, face)
    confetti(60, B(4, 263, 1404), (22, 4, 6), seed=4, size=0.55)
    embers(50, B(0, 258, 1395), (40, 10, 8), seed=5, size=(0.15, 0.35))
    camera(eye_at, B(-3, 258.5, 1385), fov=54)
    render_to(out / "raw_firerope.png")
    render_glow(out / "raw_firerope_glow.png")
    image = thumb_finish(out, "firerope", glow_strength=0.45)
    lettering(image, "JUMP THE", (args.width * 0.27, args.height * 0.1), int(args.height * 0.1), angle=-3,
              top=(255, 255, 255), bottom=(255, 225, 200), outline=(140, 20, 20))
    lettering(image, "FIRE ROPE!", (args.width * 0.27, args.height * 0.235), int(args.height * 0.16), angle=-3,
              top=(255, 230, 80), bottom=(255, 90, 20), outline=(110, 10, 10))
    save_jpg(image, out / "thumb_2_firerope.jpg")


def snow_spray(origin, direction, count=60, seed=3, spread=1.0, length=6.0):
    """Ice spraying off a sled's runners: white puffs fanning out along `direction`."""
    rng = random.Random(seed)
    direction = V(direction).normalized()
    side = direction.cross(V((0, 0, 1))).normalized()
    for _ in range(count):
        t = rng.random() ** 0.7
        point = V(origin) + direction * (t * length) + side * rng.gauss(0, spread * (0.3 + t)) + V((0, 0, abs(rng.gauss(0, 0.5 + t))))
        ball("spray", rng.uniform(0.12, 0.45) * (1.2 - t * 0.6), (255, 255, 255), point, emission=0.6)


def sled_crew(body, riders, lean=0.0):
    """Riders seated in a snapshot sled (its Body part), facing down the run. `riders` is a list of
    (distance forward from the sled's middle, pose, look, face). `lean` tips them (radians, + to
    the sled's left)."""
    frame = empty("sled", (0, 0, 0))
    frame.matrix_world = R.cframe_matrix(body["cf"])
    bpy.context.view_layer.update()
    for forward, pose, look, face, *extra in riders:
        # The seat is a little above the body's middle; the hips sit on it (2 studs above the feet).
        rider = avatar((0, -forward, 0.35 - 2.0), 0.0, pose, look, face, tilt=(0, lean),
                       pose_extra=extra[0] if extra else None)
        rider.parent = frame
    return frame


def scene_bobsled(args, out):
    """A crew leaning hard through a banked curve, ice spraying, the run and the peaks behind."""
    data = load_dump(args, "BobsledRun")
    parts, rigs = split_rigs(data["parts"])
    new_scene(args.samples, args.width, args.height, top=(0.1, 0.32, 0.85), horizon=(0.7, 0.86, 1.0),
              sun=(0.35, -0.55, 0.7), sun_energy=4.2)
    build_arena(data, parts)
    sleds = [p for p in parts if p.get("prop") == "BobsledSled" and p["n"] == "Body"]
    # The leader (lowest down the run) comes at the camera; the others chase it down the curves.
    leader = min(sleds, key=lambda p: p["cf"][1])
    look_left = {"head": (-6, 0, 68)}
    for body in sleds:
        if body is leader:
            crew = [(3.2, "lean_left", 2, "scream", {"head": (-8, 4, 62)}),
                    (0.3, "sit", 7, "laugh", {"arm_l": (40, 12), "arm_r": (5, 150), "head": (-6, 0, 68)}),
                    (-2.6, "lean_left", 5, "determined", look_left)]
        else:
            crew = [(1.6, "lean_right", 4, "determined"), (-1.2, "cheer", 9, "grin")]
        sled_crew(body, crew, lean=math.radians(12) if body is leader else 0.0)
    cf = leader["cf"]
    forward = V((cf[5], cf[8], cf[11]))  # down the run (the mesh is turned around in its part)
    left = V((cf[3], cf[6], cf[9]))  # the riders' left
    center = V(cf[:3])
    for runner in (-1, 1):
        snow_spray(B(*(center - forward * 6 + left * runner * 1.6)), B(*(-forward + left * runner * 0.4)), count=45,
                   spread=0.5, length=7, seed=runner + 5)
    streaks(B(*(center - forward * 8 + V((0, 2.0, 0)))), B(*forward), count=7, length=7, seed=2, spread=1.8, width=0.1)
    eye_r = center + left * 12.5 + forward * 6 + V((0, 4.4, 0))
    camera(B(*eye_r), B(*(center + V((0, 2.6, 0)) + forward * 0.5)), fov=46, roll=-6)
    render_to(out / "raw_bobsled.png")
    image = thumb_finish(out, "bobsled", saturation=1.15)
    lettering(image, "LEAN TO WIN THE", (args.width * 0.5, args.height * 0.1), int(args.height * 0.085), angle=-2,
              top=(255, 255, 255), bottom=(210, 235, 255), outline=(30, 60, 150))
    lettering(image, "BOBSLED RUN!", (args.width * 0.5, args.height * 0.225), int(args.height * 0.16), angle=-2,
              top=(255, 255, 255), bottom=(120, 200, 255), outline=(20, 40, 120))
    save_jpg(image, out / "thumb_3_bobsled.jpg")


def scene_icon(args, out):
    return ICONS[ICON](args, out)


def scene_sheet(args, out):
    """The icons side by side at 512 and at 128 px (about how big the Discover grid shows them)."""
    paths = [out / "icon_512.png"] + sorted(out.glob("icon_alt_*.png"))
    paths = [path for path in paths if path.exists()]
    pad, small = 24, 128
    sheet = Image.new("RGB", (pad + len(paths) * (512 + pad), 512 + small + pad * 4 + 40), (24, 24, 32))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype(FONT, 28)
    for index, path in enumerate(paths):
        icon = Image.open(path).convert("RGB")
        x = pad + index * (512 + pad)
        sheet.paste(icon, (x, pad))
        sheet.paste(icon.resize((small, small), Image.LANCZOS), (x, 512 + pad * 2))
        sheet.paste(icon.resize((small // 2, small // 2), Image.LANCZOS), (x + small + pad, 512 + pad * 2 + small // 2))
        draw.text((x + small * 1.5 + pad * 2, 512 + pad * 2 + small // 2 - 4), path.stem, font=font, fill=(230, 230, 240))
    sheet.save(out / "icon_sheet.png")
    print("wrote", out / "icon_sheet.png", flush=True)


SCENES = {"firerope": scene_firerope, "bobsled": scene_bobsled, "icon": scene_icon,
          **{f"icon_{name}": fn for name, fn in ICONS.items()}, "sheet": scene_sheet}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dumps", default="art_dumps", help="folder of snapshots (lobby.json, FireRope.json, ...)")
    parser.add_argument("--fetch", action="store_true", help="make the snapshots on a test server, then stop")
    parser.add_argument("--out", default="art")
    parser.add_argument("--only", help="comma-separated scenes (default: all)")
    parser.add_argument("--samples", type=int, default=40)
    parser.add_argument("--width", type=int, default=1920)
    parser.add_argument("--height", type=int, default=1080)
    args = parser.parse_args()
    if args.fetch:
        fetch(Path(args.dumps))
        return
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    names = args.only.split(",") if args.only else [name for name in SCENES if name != f"icon_{ICON}"]
    for name in names:
        print("rendering", name, flush=True)
        SCENES[name](args, out)


if __name__ == "__main__":
    main()
