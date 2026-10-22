"""Renders the GOLD PASS's game pass icon (owner: "Also we do need a paid battle pass too. I like the
current free one. But the paid one should also be insane."): the ROYAL CROWN (the gold lane's level
25 hat, assets/meshes/RoyalCrown.glb) in polished gold with glowing rubies and sapphires, on a gold
and purple sunburst like the experience's icon, with sparkles and a ribbon that says GOLD PASS in the
game's lettering (Luckiest Guy). Everything that matters sits inside the middle circle, since Roblox
shows pass icons round.

    <blender python> tools/art/gold_pass_icon.py [--out assets/store/gold_pass_512.png] [--samples 64]

Needs the `bpy` package (see tools/preview/render.py) and Pillow.
"""

from __future__ import annotations

import argparse
import math
import random
import tempfile
from pathlib import Path

import bpy
import mathutils
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FONT = str(ROOT / "tools" / "art" / "fonts" / "LuckiestGuy-Regular.ttf")
CROWN = ROOT / "assets" / "meshes" / "RoyalCrown.glb"
SIZE = 512
SUPER = 2  # drawn at twice the size, then scaled down (smooth edges)

GOLD_LIGHT = (255, 240, 170)
GOLD = (255, 196, 40)
GOLD_DEEP = (214, 132, 18)
INK = (90, 40, 6)
PURPLE = (88, 34, 160)
PURPLE_DEEP = (44, 16, 92)


def linear(rgb):
    """sRGB 0-255 to Blender's linear 0-1."""
    def one(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (one(rgb[0]), one(rgb[1]), one(rgb[2]), 1.0)


def material(name, rgb, metallic=0.0, roughness=0.5, emission=0.0, coat=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = linear(rgb)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if coat:
        bsdf.inputs["Coat Weight"].default_value = coat
    if emission:
        bsdf.inputs["Emission Color"].default_value = linear(rgb)
        bsdf.inputs["Emission Strength"].default_value = emission
    return m


def render_crown(path: Path, samples: int):
    """The crown alone on a clear background, three-quarters from the front and a little above."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = samples
    scene.cycles.device = "CPU"
    scene.render.resolution_x = scene.render.resolution_y = SIZE * SUPER
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "Medium High Contrast"
    world = bpy.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes["Background"]
    background.inputs[0].default_value = (1.0, 0.86, 0.62, 1)
    background.inputs[1].default_value = 0.9

    bpy.ops.import_scene.gltf(filepath=str(CROWN))
    looks = {
        "CrownGold": material("gold", (255, 190, 60), metallic=1.0, roughness=0.18),
        "CrownVelvet": material("velvet", (140, 8, 34), roughness=0.85),
        "CrownPearl": material("pearl", (252, 248, 240), roughness=0.15, coat=0.6),
        "CrownRuby": material("ruby", (255, 40, 80), roughness=0.05, emission=2.2),
        "CrownSapphire": material("sapphire", (70, 130, 255), roughness=0.05, emission=2.2),
    }
    crown = [o for o in bpy.data.objects if o.type == "MESH"]
    for obj in crown:
        base = obj.name.split(".")[0]
        obj.data.materials.clear()
        obj.data.materials.append(looks.get(base, looks["CrownGold"]))
        for poly in obj.data.polygons:
            poly.use_smooth = True
    # A little tilt toward the camera for some swagger.
    pivot = bpy.data.objects.new("pivot", None)
    scene.collection.objects.link(pivot)
    for obj in crown:
        if obj.parent is None:
            obj.parent = pivot
    pivot.rotation_euler = (math.radians(8), math.radians(-6), math.radians(-14))
    bpy.context.view_layer.update()

    lo = mathutils.Vector((1e9,) * 3)
    hi = mathutils.Vector((-1e9,) * 3)
    for obj in crown:
        for corner in obj.bound_box:
            w = obj.matrix_world @ mathutils.Vector(corner)
            lo = mathutils.Vector(map(min, lo, w))
            hi = mathutils.Vector(map(max, hi, w))
    center = (lo + hi) / 2
    radius = (hi - lo).length / 2

    def light(name, kind, energy, location, color=(1, 1, 1), size=1.0):
        data = bpy.data.lights.new(name, kind)
        data.energy = energy
        data.color = color
        if kind == "AREA":
            data.size = size
        obj = bpy.data.objects.new(name, data)
        obj.location = center + mathutils.Vector(location)
        direction = center - obj.location
        obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(obj)

    light("key", "AREA", 260, (2.2, 3.4, 3.0), (1.0, 0.95, 0.85), 2.5)
    light("fill", "AREA", 90, (-3.0, 2.0, 1.2), (1.0, 0.85, 0.7), 3.0)
    light("rim", "AREA", 220, (0.0, -3.2, 2.6), (1.0, 0.9, 0.7), 2.0)

    cam = bpy.data.cameras.new("cam")
    cam.lens = 70
    co = bpy.data.objects.new("cam", cam)
    scene.collection.objects.link(co)
    scene.camera = co
    # glTF's front (-Z) comes in as Blender's +Y: the camera looks from +Y, up a little.
    distance = radius / math.tan(math.atan(18 / cam.lens)) * 1.08
    co.location = center + mathutils.Vector((0.0, distance * 0.93, distance * 0.36))
    direction = center - co.location
    co.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def sunburst(size: int) -> Image.Image:
    """Gold light in the middle to deep purple at the edge, with soft rays."""
    image = Image.new("RGB", (size, size))
    pixels = image.load()
    c = size / 2
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c) / (size * 0.72)
            t = min(1.0, d)
            if t < 0.35:
                k = t / 0.35
                rgb = [GOLD_LIGHT[i] + (GOLD[i] - GOLD_LIGHT[i]) * k for i in range(3)]
            elif t < 0.62:
                k = (t - 0.35) / 0.27
                rgb = [GOLD[i] + ((214, 92, 120)[i] - GOLD[i]) * k for i in range(3)]
            else:
                k = (t - 0.62) / 0.38
                rgb = [(214, 92, 120)[i] + (PURPLE_DEEP[i] - (214, 92, 120)[i]) * k for i in range(3)]
            pixels[x, y] = tuple(int(v) for v in rgb)
    rays = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(rays)
    count = 18
    for index in range(count):
        a0 = 2 * math.pi * index / count
        a1 = a0 + math.pi / count
        reach = size
        draw.polygon([(c, c), (c + math.cos(a0) * reach, c + math.sin(a0) * reach), (c + math.cos(a1) * reach, c + math.sin(a1) * reach)], fill=60)
    rays = rays.filter(ImageFilter.GaussianBlur(size / 160))
    light = Image.new("RGB", (size, size), (255, 250, 220))
    return Image.composite(light, image, rays)


def sparkle(draw: ImageDraw.ImageDraw, x: float, y: float, r: float, color=(255, 255, 240, 255)):
    """A four-pointed glint."""
    w = r * 0.22
    draw.polygon([(x, y - r), (x + w, y - w), (x + r, y), (x + w, y + w), (x, y + r), (x - w, y + w), (x - r, y), (x - w, y - w)], fill=color)


def lettering(text: str, size: int, width: int) -> Image.Image:
    """GOLD PASS in Luckiest Guy: a gold gradient with a dark outline and a soft shadow."""
    font = ImageFont.truetype(FONT, size)
    pad = size // 2
    box = font.getbbox(text)
    w, h = box[2] - box[0] + 2 * pad, box[3] - box[1] + 2 * pad
    origin = (pad - box[0], pad - box[1])
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).text(origin, text, font=font, fill=255)
    outline = Image.new("L", (w, h), 0)
    ImageDraw.Draw(outline).text(origin, text, font=font, fill=255, stroke_width=max(4, size // 9), stroke_fill=255)
    fill = Image.new("RGB", (w, h))
    fp = ImageDraw.Draw(fill)
    top, bottom = origin[1] + box[1], origin[1] + box[3]
    for y in range(h):
        t = min(1.0, max(0.0, (y - top) / max(1, bottom - top)))
        if t < 0.5:
            k = t / 0.5
            rgb = [255 + (GOLD[i] - 255) * k * 0.6 + (GOLD_LIGHT[i] - 255) * (1 - k) * 0.4 for i in range(3)]
        else:
            k = (t - 0.5) / 0.5
            rgb = [GOLD[i] + (GOLD_DEEP[i] - GOLD[i]) * k for i in range(3)]
        fp.line([(0, y), (w, y)], fill=tuple(int(max(0, min(255, v))) for v in rgb))
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (w, h), (40, 10, 0, 0))
    shadow.putalpha(outline.filter(ImageFilter.GaussianBlur(size / 14)).point(lambda v: int(v * 0.7)))
    out.alpha_composite(shadow, (0, size // 14))
    ink = Image.new("RGBA", (w, h), INK + (255,))
    ink.putalpha(outline)
    out.alpha_composite(ink)
    face = fill.convert("RGBA")
    face.putalpha(mask)
    out.alpha_composite(face)
    scale = min(1.0, width / w)
    return out.resize((int(w * scale), int(h * scale)), Image.LANCZOS)


def ribbon(size: int) -> Image.Image:
    """A royal ribbon banner across the lower middle, its tails folded back."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    s = size / 512
    y0, y1 = 352 * s, 428 * s
    sag = 10 * s
    # Tails behind.
    for side in (-1, 1):
        cx = size / 2 + side * 176 * s
        tail = [(cx, y0 + 18 * s), (cx + side * 64 * s, y0 + 16 * s), (cx + side * 46 * s, (y0 + y1) / 2 + 22 * s), (cx + side * 64 * s, y1 + 28 * s), (cx, y1 + 26 * s)]
        d.polygon(tail, fill=(150, 18, 44, 255), outline=INK + (255,), width=int(4 * s))
    # The front band, gently curved.
    top = []
    bottom = []
    for i in range(41):
        t = i / 40
        x = size / 2 + (t - 0.5) * 2 * 196 * s
        dy = sag * (1 - (2 * t - 1) ** 2)
        top.append((x, y0 + dy))
        bottom.append((x, y1 + dy))
    d.polygon(top + bottom[::-1], fill=(206, 30, 64, 255), outline=INK + (255,), width=int(5 * s))
    # A gold trim along both edges.
    d.line(top, fill=GOLD + (255,), width=int(5 * s))
    d.line(bottom, fill=GOLD + (255,), width=int(5 * s))
    return layer


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", default=str(ROOT / "assets" / "store" / "gold_pass_512.png"))
    parser.add_argument("--samples", type=int, default=64)
    args = parser.parse_args()
    size = SIZE * SUPER
    work = Path(tempfile.mkdtemp(prefix="pp_goldpass_"))
    crown_path = work / "crown.png"
    render_crown(crown_path, args.samples)

    canvas = sunburst(size).convert("RGBA")
    rng = random.Random(25)
    # Gold confetti and coins drifting behind.
    back = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bd = ImageDraw.Draw(back)
    for _ in range(26):
        x, y = rng.uniform(0, size), rng.uniform(0, size * 0.9)
        if math.hypot(x - size / 2, y - size / 2) < size * 0.18:
            continue
        r = rng.uniform(9, 16) * SUPER
        color = rng.choice([GOLD, GOLD_LIGHT, (255, 150, 200), (160, 220, 255)])
        angle = rng.uniform(0, math.pi)
        dx, dy = math.cos(angle) * r, math.sin(angle) * r * 0.45
        bd.polygon([(x - dx, y - dy), (x + dy, y - dx * 0.4), (x + dx, y + dy), (x - dy, y + dx * 0.4)], fill=color + (230,))
    canvas.alpha_composite(back.filter(ImageFilter.GaussianBlur(1.2)))
    # A glow behind the crown.
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([size * 0.16, size * 0.08, size * 0.84, size * 0.72], fill=(255, 245, 200, 150))
    canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(size / 14)))

    crown = Image.open(crown_path).convert("RGBA")
    box = crown.getbbox()
    crown = crown.crop(box)
    target = int(size * 0.66)
    scale = target / max(crown.size)
    crown = crown.resize((int(crown.size[0] * scale), int(crown.size[1] * scale)), Image.LANCZOS)
    shadow = Image.new("RGBA", crown.size, (60, 16, 0, 0))
    shadow.putalpha(crown.getchannel("A").point(lambda v: int(v * 0.55)))
    cx, cy = (size - crown.size[0]) // 2, int(size * 0.39 - crown.size[1] / 2)
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(10 * SUPER)), (cx + 6 * SUPER, cy + 12 * SUPER))
    canvas.alpha_composite(crown, (cx, cy))

    canvas.alpha_composite(ribbon(size))
    text = lettering("GOLD PASS", 70 * SUPER, int(size * 0.66))
    canvas.alpha_composite(text, ((size - text.size[0]) // 2, int(size * 0.775 - text.size[1] / 2)))

    sparkles = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sparkles)
    for x, y, r in [(0.23, 0.22, 26), (0.79, 0.17, 34), (0.84, 0.47, 20), (0.15, 0.52, 18), (0.62, 0.08, 16), (0.33, 0.06, 12)]:
        sparkle(sd, x * size, y * size, r * SUPER)
    halo = sparkles.filter(ImageFilter.GaussianBlur(6 * SUPER))
    canvas.alpha_composite(halo)
    canvas.alpha_composite(sparkles)

    out = canvas.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    out.save(args.out, optimize=True)
    print("wrote", args.out)


if __name__ == "__main__":
    main()
