"""Renders Party Panic's store thumbnails (1920x1080) and icon (512x512) with Blender (pip `bpy`),
using the game's own meshes and a dump of the real lobby, then adds the title lettering.

    python tools/art/make_art.py --lobby dump.json --out art/            # everything
    python tools/art/make_art.py --lobby dump.json --out art/ --only yeet,icon --samples 16

The lobby dump comes from tools/preview (bundle.py + luau_task.py). Characters are simple
blocky avatars built here; the lettering uses Luckiest Guy (Apache 2.0, see fonts/LICENSE.txt).
"""

from __future__ import annotations

import argparse
import json
import math
import random
import sys
from pathlib import Path

import bpy
import mathutils
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "preview"))
import render as R  # noqa: E402  (the preview renderer: parts, terrain, materials, glb loading)

FONT = str(HERE / "fonts" / "LuckiestGuy-Regular.ttf")
V = mathutils.Vector

SKIN = (245, 205, 60)
OUTFITS = [
    ((40, 120, 255), (60, 190, 80)),  # classic blue shirt, green pants
    ((255, 84, 150), (60, 50, 90)),
    ((255, 150, 40), (40, 70, 140)),
    ((150, 100, 255), (30, 30, 40)),
    ((90, 220, 140), (240, 240, 250)),
    ((255, 220, 70), (200, 60, 80)),
    ((60, 200, 230), (90, 60, 160)),
]


# Scene ------------------------------------------------------------------------------------------


def new_scene(samples, width, height, top=(0.03, 0.22, 0.85), horizon=(0.42, 0.68, 1.0), sun=(0.4, -0.5, 0.75),
              sun_energy=4.0, transparent=False):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    R.MATERIAL_CACHE.clear()
    R.PRIMS.clear()
    R.MESH_CACHE.clear()
    R.GLB_CACHE.clear()
    BOX_MESHES.clear()
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.film_transparent = transparent
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA" if transparent else "RGB"
    # Standard (no filmic roll-off) keeps the toy colors as saturated as they are in Roblox.
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = -0.35

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
    bg.inputs["Strength"].default_value = 1.0

    light = bpy.data.lights.new("sun", "SUN")
    light.energy = sun_energy
    light.angle = math.radians(4)
    light.color = (1.0, 0.97, 0.9)
    obj = bpy.data.objects.new("sun", light)
    obj.rotation_euler = (-V(sun).normalized()).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(obj)
    return scene


def camera(eye, target, fov=50, lens_shift=(0, 0)):
    data = bpy.data.cameras.new("cam")
    data.sensor_fit = "VERTICAL"
    data.angle_y = math.radians(fov)
    data.clip_end = 5000
    data.shift_x, data.shift_y = lens_shift
    cam = bpy.data.objects.new("cam", data)
    cam.location = V(eye)
    cam.rotation_euler = (V(target) - V(eye)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam
    return cam


def mat(color, kind="SmoothPlastic", transparency=0.0, emission=None):
    material = R.material(color, kind, transparency)
    if emission:
        material = material.copy()
        bsdf = material.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Emission Color"].default_value = (*[R.srgb_to_linear(c) for c in color], 1)
        bsdf.inputs["Emission Strength"].default_value = emission
    return material


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
                emission=None):
    obj = mesh_object(name, box_mesh(size), mat(color, kind, emission=emission), location, rotation, (1, 1, 1), parent)
    if bevel > 0:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = min(bevel, min(size) * 0.45)
        mod.segments = 4
        mod.harden_normals = True
    return obj


def ball(name, diameter, color, location, parent=None, scale=(1, 1, 1), kind="SmoothPlastic", emission=None):
    s = [diameter * k for k in scale]
    return mesh_object(name, R.prim_mesh("Ball"), mat(color, kind, emission=emission), location, (0, 0, 0), s, parent)


def cylinder(name, diameter, length, color, location, rotation=(0, 0, 0), parent=None, kind="SmoothPlastic", emission=None):
    # R's cylinder runs along local X.
    return mesh_object(name, R.prim_mesh("Cylinder"), mat(color, kind, emission=emission), location, rotation,
                       (length, diameter, diameter), parent)


def disc(name, diameter, height, color, location, parent=None, kind="SmoothPlastic", emission=None, bevel=0.0):
    obj = cylinder(name, diameter, height, color, location, (0, math.pi / 2, 0), parent, kind, emission)
    if bevel:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 4
        mod.limit_method = "ANGLE"
    return obj


# Props from the game's own meshes -------------------------------------------------------------------


def prop(name, location, height, yaw=0.0, tilt=(0, 0), colors=None, parent=None, centered=False):
    """Places a game prop (assets/meshes/<name>.glb) standing on `location`, `height` studs tall
    (or centered on it). In Blender axes the prop's front (Roblox -Z) points +Y."""
    import numpy as np

    pieces = R.glb_pieces(name)
    data = Path(R.MESH_DIR / f"{name}.glb").read_bytes()
    import struct

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
        mesh_object(f"{name}.{piece_name}", mesh, mat(color, kind), (0, 0, 0), (0, 0, 0), (1, 1, 1), root)
    return root


# Avatars ----------------------------------------------------------------------------------------

POSES = {
    "stand": {},
    "cheer": {"arm_l": (0, -150, 0), "arm_r": (0, 150, 0)},
    "wave": {"arm_l": (0, -160, 0), "arm_r": (0, 12, 0)},
    "run": {"arm_l": (45, 0, 0), "arm_r": (-45, 0, 0), "leg_l": (-35, 0, 0), "leg_r": (35, 0, 0)},
    "jump": {"arm_l": (0, -140, 0), "arm_r": (0, 140, 0), "leg_l": (20, -12, 0), "leg_r": (-25, 12, 0)},
    "punch": {"arm_l": (-90, 0, 0), "arm_r": (40, 0, 0), "leg_l": (-25, 0, 0), "leg_r": (20, 0, 0)},
    "flail": {"arm_l": (-30, -120, 0), "arm_r": (50, 150, 0), "leg_l": (-40, -20, 0), "leg_r": (30, 25, 0)},
    "drive": {"arm_l": (-70, 0, 0), "arm_r": (-70, 0, 0)},
    "point": {"arm_l": (-95, 0, -10), "arm_r": (0, 160, 0)},
}


def face(head, kind):
    black, white = (25, 20, 35), (255, 255, 255)
    front = -0.63
    if kind == "panic":
        for side in (-1, 1):
            ball("eye", 0.34, white, (side * 0.22, front + 0.02, 0.12), head, (1, 0.35, 1.25))
            ball("pupil", 0.13, black, (side * 0.22, front - 0.03, 0.1), head, (1, 0.4, 1.2))
            # Inner ends raised: a worried look, not an angry one.
            rounded_box("brow", (0.26, 0.06, 0.06), black, (side * 0.24, front + 0.01, 0.4), (0, side * 0.35, 0), 0.02, head)
        ball("mouth", 0.36, black, (0, front + 0.02, -0.24), head, (1, 0.3, 0.8))
        ball("tongue", 0.18, (255, 110, 120), (0, front - 0.015, -0.31), head, (1, 0.3, 0.6))
    elif kind == "grin":
        for side in (-1, 1):
            ball("eye", 0.15, black, (side * 0.22, front + 0.02, 0.14), head, (0.9, 0.4, 1.3))
        ball("mouth", 0.5, black, (0, front + 0.03, -0.18), head, (1, 0.3, 0.55))
        ball("teeth", 0.42, white, (0, front + 0.0, -0.1), head, (1, 0.3, 0.22))
    else:
        for side in (-1, 1):
            ball("eye", 0.15, black, (side * 0.22, front + 0.02, 0.14), head, (0.9, 0.4, 1.3))
        for index in range(7):
            angle = math.radians(-60 + index * 20)
            ball("smile", 0.08, black, (math.sin(angle) * 0.24, front + 0.02, -0.12 - math.cos(angle) * 0.14), head)


def avatar(location, yaw=0.0, pose="stand", outfit=0, face_kind="happy", tilt=(0, 0), scale=1.0, hat=None):
    shirt, pants = OUTFITS[outfit % len(OUTFITS)]
    p = POSES[pose] if isinstance(pose, str) else pose
    root = empty("avatar", location, (tilt[0], tilt[1], yaw))
    root.scale = (scale, scale, scale)
    rounded_box("torso", (2, 1, 2), shirt, (0, 0, 3), parent=root, bevel=0.18)
    head = empty("headjoint", (0, 0, 4.6), (0, 0, 0), root)
    cylinder("head", 1.26, 1.18, SKIN, (0, 0, 0.05), (0, math.pi / 2, 0), head)
    cylinder("neck", 0.6, 0.4, SKIN, (0, 0, -0.55), (0, math.pi / 2, 0), head)
    face(head, face_kind)
    if hat == "party":
        bpy.ops.mesh.primitive_cone_add(radius1=0.55, depth=1.3, vertices=32)
        hat_obj = bpy.context.active_object
        hat_obj.location = (0.1, 0, 1.25)
        hat_obj.rotation_euler = (0, 0.2, 0)
        hat_obj.parent = head
        hat_obj.data.materials.append(mat((255, 84, 150)))
        ball("pompom", 0.35, (255, 230, 80), (0.24, 0, 1.92), head)
    for side, key in ((1, "arm_l"), (-1, "arm_r")):
        shoulder = empty("shoulder", (side * 1.5, 0, 3.85), [math.radians(a) for a in p.get(key, (0, 0, 0))], root)
        rounded_box("arm", (0.95, 0.95, 2), SKIN, (0, 0, -0.9), parent=shoulder, bevel=0.15)
    for side, key in ((1, "leg_l"), (-1, "leg_r")):
        hip = empty("hip", (side * 0.5, 0, 2.0), [math.radians(a) for a in p.get(key, (0, 0, 0))], root)
        rounded_box("leg", (0.98, 0.98, 2), pants, (0, 0, -1), parent=hip, bevel=0.15)
    return root


def face_to(position, target):
    """Yaw that turns an avatar (front = -Y) toward `target` (x, y)."""
    return math.atan2(target[0] - position[0], -(target[1] - position[1]))


def hand_point(root, side=1):
    """World position of an avatar's hand (side 1 = arm_l, -1 = arm_r)."""
    bpy.context.view_layer.update()
    for child in root.children:
        if child.name.startswith("shoulder") and abs(child.location.x - side * 1.5) < 0.01:
            return child.matrix_world @ V((0, 0, -2.1))
    return root.matrix_world.translation


# Effects ----------------------------------------------------------------------------------------

PARTY = [(255, 84, 150), (64, 196, 255), (255, 214, 64), (156, 108, 255), (110, 226, 140), (255, 140, 70)]


def confetti(count, center, spread, seed=1, size=0.5):
    rng = random.Random(seed)
    for index in range(count):
        offset = V((rng.uniform(-1, 1) * spread[0], rng.uniform(-1, 1) * spread[1], rng.uniform(-1, 1) * spread[2]))
        color = PARTY[index % len(PARTY)]
        rounded_box("confetti", (size, size * 0.6, 0.04), color, V(center) + offset,
                    (rng.uniform(0, 6.3), rng.uniform(0, 6.3), rng.uniform(0, 6.3)), 0, emission=0.4)


def streaks(start, direction, count=5, length=6, seed=3):
    rng = random.Random(seed)
    direction = V(direction).normalized()
    side = direction.cross(V((0, 0, 1))).normalized()
    up = side.cross(direction).normalized()
    for index in range(count):
        offset = side * rng.uniform(-1.6, 1.6) + up * rng.uniform(-1.6, 1.6)
        middle = V(start) + offset - direction * (length / 2 + rng.uniform(0, 2))
        obj = cylinder("streak", 0.12, length * rng.uniform(0.6, 1.0), (255, 255, 255), middle, (0, 0, 0), None,
                       emission=2.0)
        obj.rotation_euler = direction.to_track_quat("X", "Z").to_euler()


def cloud(center, radius, seed=0):
    rng = random.Random(seed)
    for index in range(7):
        offset = V((rng.uniform(-1.6, 1.6) * radius, rng.uniform(-0.6, 0.6) * radius, rng.uniform(-0.2, 0.5) * radius))
        ball("cloud", radius * rng.uniform(1.1, 1.8), (255, 255, 255), V(center) + offset, scale=(1, 1, 0.7),
             emission=0.25)


def hills(seed=4, distance=180, count=14, color=(110, 200, 95)):
    rng = random.Random(seed)
    for index in range(count):
        angle = rng.uniform(math.radians(20), math.radians(160))
        r = distance * rng.uniform(0.8, 1.2)
        size = rng.uniform(60, 110)
        ball("hill", size, color, (math.cos(angle) * r, math.sin(angle) * r, -size * 0.3), scale=(1.3, 1, 0.6))


# Lettering --------------------------------------------------------------------------------------


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
    from PIL import ImageChops

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


def render_to(path):
    bpy.context.scene.render.filepath = str(Path(path).resolve())
    bpy.ops.render.render(write_still=True)


# Scenes -----------------------------------------------------------------------------------------


def scene_lobby(args, out):
    """Key art: friends partying in front of the vote stage's portals."""
    new_scene(args.samples, args.width, args.height, sun=(0.35, -0.55, 0.75))
    data = json.loads(Path(args.lobby).read_text())
    data = data[0] if isinstance(data, list) else data
    data = json.loads(data) if isinstance(data, str) else data
    R.build_parts(data["parts"])
    R.build_terrain(data["terrain"])
    # Roblox (x, y, z) -> Blender (x, -z, y). The stage is at Roblox z = -53 (Blender y = +53).
    eye = (0, 8, 6)
    crowd = [
        ((-9, 28, 0.3), 0.3, "cheer", 0, "grin", None),
        ((-3.5, 24, 3.5), -0.2, "jump", 1, "happy", "party"),
        ((3, 26.5, 0.3), 0.1, "wave", 2, "grin", None),
        ((9, 29, 0.3), -0.25, "cheer", 3, "happy", "party"),
        ((14.5, 25, 0.3), -0.4, "point", 4, "grin", None),
        ((-15, 25, 0.3), 0.5, "run", 5, "happy", None),
        ((0.5, 47, 2.6), 0.0, "cheer", 6, "grin", None),
    ]
    for position, jitter, pose, outfit, kind, hat in crowd:
        avatar(position, face_to(position, eye) + jitter, pose, outfit, kind, hat=hat)
    confetti(160, (0, 30, 14), (22, 10, 9), seed=5, size=0.55)
    camera(eye, (0, 52, 17), fov=52)
    render_to(out / "raw_lobby.png")
    image = grade(out / "raw_lobby.png")
    lettering(image, "PARTY PANIC", (args.width / 2, args.height * 0.15), int(args.height * 0.2), angle=2)
    lettering(image, "VOTE  •  PLAY  •  PANIC!", (args.width / 2, args.height * 0.9), int(args.height * 0.075),
              top=(255, 255, 255), bottom=(200, 235, 255), outline=(220, 40, 120))
    image.convert("RGB").save(out / "thumb_1_lobby.png")


def platform(diameter, color, rim, location=(0, 0, 0)):
    x, y, z = location
    disc("platform", diameter, 2, color, (x, y, z - 1), bevel=0.5)
    disc("rim", diameter + 0.8, 1.2, rim, (x, y, z - 1.4), bevel=0.4)
    cone = bpy.ops.mesh.primitive_cone_add(radius1=diameter * 0.45, radius2=1, depth=diameter * 0.6, vertices=48,
                                           location=(x, y, z - 2 - diameter * 0.3), rotation=(math.pi, 0, 0))
    obj = bpy.context.active_object
    obj.data.materials.append(mat((140, 110, 90)))
    obj.data.shade_smooth()
    disc("grass", diameter * 0.92, 1.0, (110, 210, 100), (x, y, z - 2.3), bevel=0.3)
    return cone


def scene_yeet(args, out):
    new_scene(args.samples, args.width, args.height, sun=(0.5, -0.4, 0.8))
    platform(30, (255, 150, 205), (255, 255, 255))
    for x, y, z, r in ((-40, 60, -18, 9), (35, 70, -10, 11), (-10, 90, -30, 14), (60, 30, -25, 8), (-55, 20, -30, 7)):
        cloud((x, y, z), r, seed=x)
    eye = (-3, -24, 4.5)
    puncher_position = (-4, 1, 0)
    punch = V((1, -0.6, 0)).normalized()
    puncher = avatar(puncher_position, face_to(puncher_position, (puncher_position[0] + punch.x, puncher_position[1] + punch.y)),
                     "punch", 0, "grin")
    glove = prop("YeetGlove", hand_point(puncher, 1) + punch * 1.1, 3.8, centered=True)
    glove.rotation_euler = punch.to_track_quat("Y", "Z").to_euler()
    victim = (5.5, 0, 5.5)
    avatar(victim, face_to(victim, eye) + 0.4, "flail", 1, "panic", tilt=(math.radians(-20), math.radians(35)))
    streaks(V(victim) + V((0, 0, 3)), V((1, 0.1, 0.45)), count=7, length=7)
    for position, pose, outfit, kind in (((-11, 7, 0), "cheer", 3, "grin"), ((4, 9, 0), "run", 2, "panic"),
                                         ((-13, -3, 0), "point", 5, "grin")):
        avatar(position, face_to(position, eye) + 0.2, pose, outfit, kind)
    confetti(50, (7, 2, 7), (5, 4, 4), seed=9, size=0.45)
    camera(eye, (2, 2, 4), fov=48)
    render_to(out / "raw_yeet.png")
    image = grade(out / "raw_yeet.png")
    lettering(image, "YEET ARENA", (args.width * 0.3, args.height * 0.16), int(args.height * 0.15), angle=4,
              top=(255, 255, 255), bottom=(255, 220, 120), outline=(220, 40, 90))
    lettering(image, "PUNCH 'EM OFF!", (args.width * 0.72, args.height * 0.88), int(args.height * 0.09), angle=-3)
    image.convert("RGB").save(out / "thumb_2_yeet.png")


def scene_carts(args, out):
    new_scene(args.samples, args.width, args.height, sun=(-0.4, -0.6, 0.7))
    # Ground and a purple track running away from the camera, with a ramp.
    rounded_box("ground", (400, 400, 2), (110, 200, 95), (0, 120, -1.2), bevel=0)
    rounded_box("track", (22, 200, 1), (120, 90, 200), (0, 90, 0), bevel=0.4)
    for side in (-1, 1):
        rounded_box("edge", (1.4, 200, 1.6), (255, 214, 64), (side * 11.5, 90, 0.4), bevel=0.4)
    for row in range(2):
        for col in range(11):
            color = (255, 255, 255) if (row + col) % 2 == 0 else (30, 30, 40)
            rounded_box("check", (2, 2, 0.1), color, (-10 + col * 2, -2 + row * 2, 0.55), bevel=0)
    for x, y in ((5, 14), (-5, 34)):
        rounded_box("boost", (6, 4, 0.12), (64, 196, 255), (x, y, 0.56), bevel=0.2, kind="Neon")
    rounded_box("ramp", (10, 8, 3), (255, 140, 70), (-3, 46, 1.2), (math.radians(-18), 0, 0), bevel=0.4)
    for x, y in ((-14, 20), (14, 28), (-14, 50), (14, 60)):
        prop("Cone", (x, y, 0.5), 2.6)
    for x, y, h in ((-30, 60, 16), (32, 70, 18), (-45, 100, 20), (40, 110, 17), (-25, 130, 22), (20, 140, 20)):
        prop("Tree", (x, y, 0), h)
    hills(seed=7, distance=200)
    eye = (7, -12, 3.2)
    carts = [((-5.5, 6, 0.5), 0.12, 0, "cheer", "grin"), ((5, 12, 0.5), -0.05, 1, "drive", "panic"),
             ((-2, 40, 6), 0.2, 2, "jump", "grin")]
    for (x, y, z), yaw, outfit, pose, kind in carts:
        tilt = (math.radians(14), 0) if z > 3 else (0, 0)
        prop("ShoppingCart", (x, y, z), 5.2, yaw=math.pi + yaw, tilt=tilt)
        rider = avatar((x, y, z + 2.1), face_to((x, y), eye) + yaw, pose, outfit, kind, tilt=tilt)
        rider.scale = (0.85, 0.85, 0.85)
    confetti(40, (0, 30, 10), (14, 14, 6), seed=12, size=0.5)
    camera(eye, (-1, 20, 3.5), fov=46)
    render_to(out / "raw_carts.png")
    image = grade(out / "raw_carts.png")
    lettering(image, "SHOPPING CART", (args.width * 0.5, args.height * 0.12), int(args.height * 0.13), angle=-2,
              top=(255, 255, 255), bottom=(190, 230, 255), outline=(40, 60, 160))
    lettering(image, "GRAND PRIX!", (args.width * 0.5, args.height * 0.27), int(args.height * 0.15), angle=-2)
    image.convert("RGB").save(out / "thumb_3_carts.png")


def scene_lava(args, out):
    new_scene(args.samples, args.width, args.height, top=(0.3, 0.12, 0.45), horizon=(1.0, 0.55, 0.3),
              sun=(0.2, -0.3, 0.9), sun_energy=3.0)
    rounded_box("lava", (300, 300, 1), (255, 70, 0), (0, 60, -4), bevel=0, emission=1.6)
    rng = random.Random(4)
    tile = 6.4
    colors = [(255, 120, 175), (120, 200, 255), (255, 214, 64), (160, 120, 255), (120, 226, 150)]
    for ix in range(-4, 5):
        for iy in range(0, 7):
            if rng.random() < 0.15 or (ix, iy) == (2, 0):
                continue
            sink = rng.random() < 0.22
            z = -2.2 if sink else 0
            rot = (rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15), 0) if sink else (0, 0, 0)
            color = (255, 90, 60) if sink else colors[(ix + iy) % len(colors)]
            rounded_box("tile", (tile - 0.5, tile - 0.5, 2), color, (ix * tile, iy * tile, z - 1), rot, bevel=0.5,
                        emission=1.5 if sink else None)
    eye = (2, -20, 15)
    cast = [((-6.4, 6.4, 0), "run", 0, "panic", (0, 0)), ((3.2, 10, 4.5), "jump", 1, "grin", (0, 0)),
            ((6.4, 19.2, 0), "cheer", 2, "happy", (0, 0)), ((-12.8, 19.2, 0), "point", 4, "grin", (0, 0)),
            ((12.8, 1, -3.4), "flail", 3, "panic", (math.radians(-20), math.radians(25)))]
    for position, pose, outfit, kind, tilt in cast:
        avatar(position, face_to(position, eye), pose, outfit, kind, tilt=tilt)
    for index in range(30):
        ball("ember", rng.uniform(0.2, 0.5), (255, 200, 80), (rng.uniform(-25, 25), rng.uniform(-5, 45), rng.uniform(-2, 14)),
             emission=8)
    camera(eye, (0, 12, 0), fov=50)
    render_to(out / "raw_lava.png")
    image = grade(out / "raw_lava.png", saturation=1.05)
    lettering(image, "THE FLOOR IS", (args.width * 0.5, args.height * 0.11), int(args.height * 0.11),
              top=(255, 255, 255), bottom=(255, 230, 200), outline=(140, 20, 20))
    lettering(image, "LAVA!", (args.width * 0.5, args.height * 0.27), int(args.height * 0.2), angle=-3,
              top=(255, 230, 80), bottom=(255, 80, 20), outline=(110, 10, 10))
    image.convert("RGB").save(out / "thumb_4_lava.png")


def scene_flatten(args, out):
    new_scene(args.samples, args.width, args.height, sun=(0.5, -0.5, 0.7))
    disc("arena", 70, 2, (255, 236, 214), (0, 10, -1), bevel=0.5)
    disc("arenaRim", 71.5, 1.6, (255, 204, 64), (0, 10, -1.3), bevel=0.4)
    hills(seed=3, distance=160)
    eye = (4, -16, 6)
    # A giant mallet mid-slam over a panicking player, a red warning circle under it.
    disc("warn", 9, 0.1, (255, 60, 60), (-2, 8, 0.06), emission=1.5)
    mallet = empty("mallet", (-2, 8, 13.5), (0, math.radians(-22), 0))
    head = prop("MalletHead", (0, 0, -2.5), 7, parent=mallet, centered=True)
    head.rotation_euler = (0, math.pi / 2, 0)
    cylinder("handle", 1.2, 22, (205, 150, 100), (11, 0, 0), (0, 0, 0), mallet)
    for position, pose, outfit, kind, tilt in (((-2, 8, 0), "flail", 1, "panic", (math.radians(8), 0)),
                                               ((6, 2, 0), "run", 0, "panic", (0, 0)),
                                               ((-9, 12, 0), "run", 2, "grin", (0, 0))):
        avatar(position, face_to(position, eye) + 0.2, pose, outfit, kind, tilt=tilt)
    prop("Boulder", (12, 18, 0), 7)
    streaks(V((15, 20, 3.5)), V((-1, -0.6, 0)), count=5, length=6, seed=5)
    prop("Anvil", (-12, 22, 10), 3.5, tilt=(0.2, 0.1))
    disc("warn2", 6, 0.1, (255, 60, 60), (-12, 22, 0.06), emission=1.5)
    camera(eye, (-1, 12, 4), fov=50)
    render_to(out / "raw_flatten.png")
    image = grade(out / "raw_flatten.png")
    lettering(image, "DON'T GET", (args.width * 0.74, args.height * 0.12), int(args.height * 0.11), angle=3,
              top=(255, 255, 255), bottom=(255, 220, 220), outline=(170, 30, 50))
    lettering(image, "FLATTENED!", (args.width * 0.72, args.height * 0.27), int(args.height * 0.15), angle=3,
              top=(255, 120, 120), bottom=(220, 30, 50), outline=(80, 10, 30))
    image.convert("RGB").save(out / "thumb_5_flatten.png")


def scene_icon(args, out):
    size = 1024
    new_scene(args.samples, size, size, transparent=True, sun=(0.3, -0.7, 0.6), sun_energy=4.5)
    avatar((0, 0, -3.1), math.radians(-12), "flail", 1, "panic", hat="party")
    confetti(60, (0, 1, 2.5), (5, 2, 4), seed=21, size=0.35)
    camera((0, -7, 2.2), (0, 0, 0.9), fov=40)
    render_to(out / "raw_icon.png")
    render = Image.open(out / "raw_icon.png").convert("RGBA")
    # Radial pink-to-purple burst behind the character.
    background = Image.new("RGBA", (size, size))
    draw = ImageDraw.Draw(background)
    for r in range(size, 0, -4):
        t = r / size
        color = tuple(int(a + (b - a) * t) for a, b in zip((255, 120, 200), (90, 30, 170)))
        draw.ellipse([size / 2 - r, size * 0.42 - r, size / 2 + r, size * 0.42 + r], fill=color + (255,))
    rays = Image.new("L", (size, size), 0)
    rdraw = ImageDraw.Draw(rays)
    for index in range(16):
        a0 = index * math.tau / 16
        a1 = a0 + math.tau / 32
        cx, cy = size / 2, size * 0.42
        rdraw.polygon([(cx, cy), (cx + math.cos(a0) * size * 1.5, cy + math.sin(a0) * size * 1.5),
                       (cx + math.cos(a1) * size * 1.5, cy + math.sin(a1) * size * 1.5)], fill=40)
    background.paste(Image.new("RGBA", (size, size), (255, 255, 255, 255)), (0, 0), rays)
    background.alpha_composite(render)
    lettering(background, "PARTY", (size / 2, size * 0.73), int(size * 0.2), angle=-4)
    lettering(background, "PANIC!", (size / 2, size * 0.89), int(size * 0.21), angle=-4,
              top=(255, 255, 255), bottom=(255, 200, 230), outline=(200, 20, 100))
    icon = ImageEnhance.Color(background.convert("RGB")).enhance(1.1)
    icon.resize((512, 512), Image.LANCZOS).save(out / "icon_512.png")
    icon.save(out / "icon_1024.png")


SCENES = {"lobby": scene_lobby, "yeet": scene_yeet, "carts": scene_carts, "lava": scene_lava,
          "flatten": scene_flatten, "icon": scene_icon}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lobby", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--only", default=",".join(SCENES))
    parser.add_argument("--samples", type=int, default=64)
    parser.add_argument("--width", type=int, default=1920)
    parser.add_argument("--height", type=int, default=1080)
    args = parser.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for name in args.only.split(","):
        print("rendering", name, flush=True)
        SCENES[name](args, out)


if __name__ == "__main__":
    main()
