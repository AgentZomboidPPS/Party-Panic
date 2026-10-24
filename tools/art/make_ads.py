"""Click-bait ads for Party Panic: 1920x1080 pictures built to be clicked in a crowded Discover feed.

The store art in make_art.py shows the game honestly and calmly. These are the loud versions of the
same real renders (snapshots of the lobby and arenas, the posed blocky avatars, the game's own props):
one giant screaming face, one obvious threat, three words of headline, and a punch of grade, bloom and
speed. Nothing in them is a thing the game doesn't have.

    python tools/art/make_ads.py --dumps art_dumps --out ads                   # all the ads
    python tools/art/make_ads.py --dumps art_dumps --out ads --only firerope   # one
    python tools/art/make_ads.py --dumps art_dumps --out ads --preview         # small and quick, to look at

It reads the same snapshots as make_art.py (`make_art.py --fetch` makes them); the Halloween ad also
wants lobby_halloween.json, the lobby built with the event's decorations on (the same dump script plus
`EventDecor.Show("Halloween")`, with World/Props/RakeItIn bundled in for its golden pumpkin mesh).
`--sheet` puts every ad side by side at 1920 and at the 320 px a feed shows them.
"""

from __future__ import annotations

import argparse
import math
import random
from pathlib import Path
from types import SimpleNamespace

import bpy
import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont

import make_art as M
from make_art import B, V

W, H = 1920, 1080

# Toolkit -------------------------------------------------------------------------------------------


def ad_text(image, text, center, size, top=(255, 244, 110), bottom=(255, 150, 20), edge=(70, 14, 110),
            outer=(255, 255, 255), angle=0.0, depth=0.075, glow=None, shine=True):
    """Loud lettering: gradient fill, a dark edge, a thick white sticker border, a 3D extrusion and a
    drop shadow (the border is what keeps it readable over any picture at 300 px wide)."""
    font = ImageFont.truetype(M.FONT, size)
    inner = max(4, int(size * 0.06))
    border = inner + max(5, int(size * 0.075))
    drop = int(size * depth)
    left, upper, right, lower = font.getbbox(text, stroke_width=border)
    pad = border * 2 + drop + int(size * 0.2)
    w, h = right - left + pad * 2, lower - upper + pad * 2
    origin = (pad - left, pad - upper)
    canvas = (w, h)

    def stamp(stroke, fill, dy=0):
        layer = Image.new("RGBA", canvas, (0, 0, 0, 0))
        ImageDraw.Draw(layer).text((origin[0], origin[1] + dy), text, font=font, fill=fill, stroke_width=stroke,
                                   stroke_fill=fill)
        return layer

    layer = Image.new("RGBA", canvas, (0, 0, 0, 0))
    shadow = stamp(border, (10, 0, 30, 235), drop + int(size * 0.07)).filter(ImageFilter.GaussianBlur(size * 0.035))
    layer.alpha_composite(shadow)
    if glow:
        halo = stamp(border + int(size * 0.05), (*glow, 255)).filter(ImageFilter.GaussianBlur(size * 0.09))
        layer.alpha_composite(halo)
    for step in range(drop, 0, -1):  # the extrusion: the white border and the edge, stepped down
        layer.alpha_composite(stamp(border, (*[int(c * 0.55) for c in edge], 255), step))
    layer.alpha_composite(stamp(border, (*outer, 255)))
    layer.alpha_composite(stamp(inner, (*edge, 255)))
    mask = Image.new("L", canvas, 0)
    ImageDraw.Draw(mask).text(origin, text, font=font, fill=255)
    gradient = Image.new("RGBA", canvas)
    gdraw = ImageDraw.Draw(gradient)
    for y in range(h):
        t = min(1, max(0, (y - origin[1] - size * 0.12) / (size * 0.78)))
        gdraw.line([(0, y), (w, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
    layer.paste(gradient, (0, 0), mask)
    if shine:
        cut = Image.new("L", canvas, 0)
        ImageDraw.Draw(cut).rectangle([0, 0, w, origin[1] + int(size * 0.44)], fill=95)
        layer.paste(Image.new("RGBA", canvas, (255, 255, 255, 255)), (0, 0), ImageChops.multiply(mask, cut))
    if angle:
        layer = layer.rotate(angle, resample=Image.BICUBIC, expand=True)
    image.alpha_composite(layer, (int(center[0] - layer.size[0] / 2), int(center[1] - layer.size[1] / 2)))
    return image


def starburst(image, center, radius, text_lines, points=16, top=(255, 238, 90), bottom=(255, 140, 20),
              edge=(150, 20, 40), text_color=(150, 14, 40), angle=-8, text_size=None, spin=0.0):
    """A jagged "sticker" badge ("30 GAMES!", "NEW!") with its lines of text inside."""
    pad = int(radius * 0.35)
    size = int(radius * 2 + pad * 2)
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mid = size / 2

    def ring(scale, dip=0.83):
        pts = []
        for k in range(points * 2):
            r = radius * scale * (1 if k % 2 == 0 else dip)
            a = spin + math.pi * k / points
            pts.append((mid + math.cos(a) * r, mid + math.sin(a) * r))
        return pts

    shadow = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon([(x + radius * 0.05, y + radius * 0.09) for x, y in ring(1.07)], fill=(10, 0, 30, 230))
    layer.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(radius * 0.04)))
    draw = ImageDraw.Draw(layer)
    draw.polygon(ring(1.08), fill=(255, 255, 255, 255))
    draw.polygon(ring(1.0), fill=(*edge, 255))
    face = Image.new("RGBA", layer.size)
    fdraw = ImageDraw.Draw(face)
    for y in range(size):
        t = min(1, max(0, (y - (mid - radius)) / (radius * 2)))
        fdraw.line([(0, y), (size, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
    mask = Image.new("L", layer.size, 0)
    ImageDraw.Draw(mask).polygon(ring(0.9, 0.86), fill=255)
    layer.paste(face, (0, 0), mask)
    count = len(text_lines)
    unit = text_size or int(radius * (0.62 if count == 1 else 0.5 if count == 2 else 0.4))
    for index, line in enumerate(text_lines):
        font = ImageFont.truetype(M.FONT, unit)
        while ImageDraw.Draw(layer).textlength(line, font=font) > radius * 1.45 and unit > 12:
            unit = int(unit * 0.94)
            font = ImageFont.truetype(M.FONT, unit)
        y = mid + (index - (count - 1) / 2) * unit * 1.02
        draw.text((mid + 3, y + 5), line, font=font, fill=(90, 10, 20, 120), anchor="mm")
        draw.text((mid, y), line, font=font, fill=text_color, anchor="mm", stroke_width=max(2, unit // 22),
                  stroke_fill=(255, 250, 220))
    layer = layer.rotate(angle, resample=Image.BICUBIC, expand=True)
    image.alpha_composite(layer, (int(center[0] - layer.size[0] / 2), int(center[1] - layer.size[1] / 2)))
    return image


def arrow(image, tail, head, color=(255, 40, 70), width=70, outline=(255, 255, 255)):
    """A fat, chunky pointing arrow with a white border and a shadow."""
    length = math.dist(tail, head)
    pad = int(width * 1.2)
    layer = Image.new("RGBA", (int(length + pad * 2), int(width * 3 + pad * 2)), (0, 0, 0, 0))
    cy = layer.size[1] / 2
    shaft_end = length - width * 1.5
    shape = [(pad, cy - width / 2), (pad + shaft_end, cy - width / 2), (pad + shaft_end, cy - width * 1.25),
             (pad + length, cy), (pad + shaft_end, cy + width * 1.25), (pad + shaft_end, cy + width / 2),
             (pad, cy + width / 2)]
    shadow = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon([(x + width * 0.08, y + width * 0.14) for x, y in shape], fill=(10, 0, 30, 220))
    layer.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(width * 0.07)))
    body = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    ImageDraw.Draw(body).polygon(shape, fill=(*color, 255))
    border = M.sticker_outline(body, int(width * 0.2), outline, soften=1.2)
    gloss = Image.new("L", layer.size, 0)
    ImageDraw.Draw(gloss).rectangle([0, 0, layer.size[0], cy - width * 0.05], fill=70)
    alpha = body.getchannel("A")
    border.paste(Image.new("RGBA", layer.size, (255, 255, 255, 255)), (0, 0), ImageChops.multiply(gloss, alpha))
    layer.alpha_composite(border)
    angle = math.degrees(math.atan2(-(head[1] - tail[1]), head[0] - tail[0]))
    layer = layer.rotate(angle, resample=Image.BICUBIC, expand=True)
    mid = ((tail[0] + head[0]) / 2, (tail[1] + head[1]) / 2)
    image.alpha_composite(layer, (int(mid[0] - layer.size[0] / 2), int(mid[1] - layer.size[1] / 2)))
    return image


def zoom_blur(image, center, strength=0.07, steps=12, inner=0.42):
    """Speed: a radial blur that leaves the middle sharp and streaks the edges toward `center`."""
    w, h = image.size
    base = image.convert("RGB")
    acc = np.zeros((h, w, 3), np.float32)
    for step in range(steps):
        s = 1 + strength * step / (steps - 1)
        a = 1 / s
        shifted = base.transform((w, h), Image.AFFINE, (a, 0, center[0] - center[0] * a, 0, a, center[1] - center[1] * a),
                                 resample=Image.BICUBIC)
        acc += np.asarray(shifted, np.float32)
    blurred = acc / steps
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.hypot((xx - center[0]) / (w / 2), (yy - center[1]) / (h / 2))
    m = (np.clip((d - inner) / (1.25 - inner), 0, 1) ** 1.4)[..., None]
    out = np.asarray(base, np.float32) * (1 - m) + blurred * m
    result = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).convert("RGBA")
    result.putalpha(image.getchannel("A"))
    return result


def bloom(image, threshold=205, radius=0.012, strength=0.55):
    """The brightest things bleed light: threshold, blur wide, screen back on."""
    rgb = image.convert("RGB")
    bright = rgb.point(lambda v: max(0, v - threshold) * 255 // (255 - threshold))
    halo = Image.new("RGB", rgb.size)
    for k, weight in ((1, 0.5), (3, 0.3), (9, 0.2)):
        blurred = bright.filter(ImageFilter.GaussianBlur(max(image.size) * radius * k))
        halo = ImageChops.add(halo, blurred.point(lambda v, w=weight: min(255, int(v * w * strength * 3))))
    out = ImageChops.screen(rgb, halo).convert("RGBA")
    out.putalpha(image.getchannel("A"))
    return out


def punch(image, saturation=1.22, contrast=1.1, clarity=0.5, vignette=0.34, tint=(20, 4, 40)):
    """The click-bait grade: saturated, contrasty, with local contrast ("clarity") and dark corners."""
    rgb = image.convert("RGB")
    rgb = ImageEnhance.Color(rgb).enhance(saturation)
    rgb = ImageEnhance.Contrast(rgb).enhance(contrast)
    if clarity:
        rgb = rgb.filter(ImageFilter.UnsharpMask(radius=max(image.size) * 0.012, percent=int(clarity * 100), threshold=2))
    out = rgb.convert("RGBA")
    out.putalpha(image.getchannel("A"))
    return M.vignette(out, vignette, tint) if vignette else out


def light_rays(image, center, count=14, strength=60, color=(255, 255, 255), spin=0.0):
    """Soft rays fanning out of `center`, screened over the picture."""
    w, h = image.size
    reach = math.hypot(w, h)
    beams = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(beams)
    for index in range(count):
        a0 = spin + index * math.tau / count
        a1 = a0 + math.tau / count * 0.42
        draw.polygon([center, (center[0] + math.cos(a0) * reach, center[1] + math.sin(a0) * reach),
                      (center[0] + math.cos(a1) * reach, center[1] + math.sin(a1) * reach)], fill=strength)
    beams = beams.filter(ImageFilter.GaussianBlur(6))
    fade = Image.radial_gradient("L").resize((w * 2, h * 2)).crop((int(w - center[0]), int(h - center[1]),
                                                                     int(2 * w - center[0]), int(2 * h - center[1])))
    beams = ImageChops.multiply(beams, ImageChops.invert(fade).point(lambda v: min(255, int(v * 1.1))))
    glow = Image.new("RGB", (w, h), color)
    out = image.convert("RGB")
    out.paste(ImageChops.screen(out, glow), (0, 0), beams)
    result = out.convert("RGBA")
    result.putalpha(image.getchannel("A"))
    return result


def logo(image, center, size, angle=-3):
    """The game's name, small, so an ad still says whose it is."""
    return ad_text(image, "PARTY PANIC", center, size, angle=angle, depth=0.06)


def params(args, defaults):
    """A scene's tunables: its defaults, overridden by --set key=value."""
    values = dict(defaults)
    values.update(args.set)
    return SimpleNamespace(**values)


def save(image, path, name):
    path = Path(path) / name
    M.save_jpg(image, path)
    return path


# Fire Rope -------------------------------------------------------------------------------------------


def scene_firerope(args, out):
    """A giant screaming jumper over the burning rope, shot from the ground: the rope's flames at the
    lens, the Dragon Temple and a volcano behind, friends leaping beyond."""
    v = params(args, {"rope_angle": 13.0, "fov": 60.0})
    data = M.load_dump(args, "FireRope")
    parts, rigs = M.split_rigs(data["parts"])
    eye = M.part_named(parts, "Eye", "SunWheel")["cf"]
    M.swing_parts(parts, {"Core", "Halo", "Fireball"}, eye[1], eye[2], math.radians(v.rope_angle))
    M.new_scene(args.samples, args.width, args.height, top=(0.1, 0.1, 0.45), horizon=(1.0, 0.45, 0.2),
                sun=(0.5, -0.4, 0.45), sun_energy=3.4, sun_color=(1.0, 0.82, 0.62), exposure=-0.2)
    M.build_arena(data, parts)
    M.dim_neon({"Fireball": 0.9, "Core": 1.3, "Halo": 0.8})
    rng = random.Random(7)
    hot = M.fire_material(strength=2.4)
    for ball_part in [p for p in parts if p["n"] == "Fireball"][::2]:
        x, y, z = ball_part["cf"][:3]
        M.flame(B(x, y, z), rng.uniform(1.5, 2.8), (rng.uniform(-0.25, 0.25), -0.5, 1), material=hot, seed=int(x * 10))
    cam_eye = B(-2.4, 252.5, 1409.2)
    # The hero: mid-leap, knees up, a party hat and the loudest face there is.
    hero_look = {"skin": 0, "shirt": (255, 84, 150), "pants": (40, 52, 110), "shoes": (250, 250, 250), "hat": "party",
                 "hat_colors": ((64, 196, 255), (255, 230, 90)), "sleeve": -0.55}
    spot = B(-0.4, 253.4, 1400.2)
    M.avatar(spot, M.face_to(spot, cam_eye) + 0.12, "jump", hero_look, "scream", head_scale=1.85, shoulders="top",
             tilt=(math.radians(-4), math.radians(5)),
             pose_extra={"leg_l": (50, 14), "leg_r": (24, 14), "arm_l": (15, 142), "arm_r": (15, 148), "head": (-6, -4, 0)})
    # Friends leaping behind, all panicking.
    others = [(-12.5, "tuck", "scream", 3.4), (13.8, "jump", "panic", 3.8), (-6.0, "flail", "shock", 5.6),
              (8.0, "tuck", "scream", 5.2), (19.2, "jump", "panic", 3.0)]
    for index, (x, pose, face, lift) in enumerate(others):
        spot = B(x, 250.0 + lift, 1397.0 - abs(x) * 0.12)
        M.avatar(spot, M.face_to(spot, cam_eye) + math.radians(rng.uniform(-14, 14)), pose, index + 2, face)
    M.confetti(70, B(2, 259, 1403), (13, 5, 5), seed=4, size=0.5,
               avoid=[(B(-0.4, 257.0, 1400.2), 3.6)])
    M.embers(120, B(0, 256, 1405), (22, 7, 6), seed=5, size=(0.07, 0.24))
    M.lamp(B(-2, 251.6, 1407), 260, (1.0, 0.5, 0.15), 2.0)
    M.lamp(B(6, 262, 1412), 380, (0.7, 0.85, 1.0), 4.0)
    M.camera(cam_eye, B(0.2, 256.4, 1400), fov=v.fov, roll=-6, lens_shift=(0.2, -0.04))
    M.render_to(out / "raw_ad_firerope.png")
    M.render_glow(out / "raw_ad_firerope_glow.png")
    image = M.grade(out / "raw_ad_firerope.png", 1.0, 1.0)
    image = M.add_glow(image, out / "raw_ad_firerope_glow.png", radius=0.014, strength=0.45)
    image = zoom_blur(image, (args.width * 0.44, args.height * 0.42), strength=0.04, inner=0.58)
    image = punch(image, saturation=1.28, contrast=1.12)
    image = bloom(image, threshold=238, strength=0.35)
    s = args.height / 1080
    ad_text(image, "JUMP OR", (args.width * 0.73, args.height * 0.15), int(170 * s), top=(255, 255, 255),
            bottom=(255, 226, 190), edge=(150, 14, 20), angle=4, glow=(255, 90, 20))
    ad_text(image, "BURN!", (args.width * 0.73, args.height * 0.36), int(255 * s), top=(255, 240, 80),
            bottom=(255, 70, 10), edge=(130, 8, 12), angle=4, glow=(255, 60, 10))
    logo(image, (args.width * 0.8, args.height * 0.9), int(104 * s))
    return save(image, out, "ad_1_firerope.jpg")


# Hex Meltdown ----------------------------------------------------------------------------------------

# How far each hex has sunk in the picture (studs below the safe ones): deep chasms with a few still going.
HEX_DROPS = {(0.0, 1413.6): 11.5, (0.0, 1400.0): 14, (-11.8, 1406.8): 13, (11.8, 1406.8): 15, (-11.8, 1393.2): 9,
             (-23.5, 1413.6): 12, (-23.5, 1400.0): 16, (0.0, 1427.2): 17, (-11.8, 1420.4): 15, (11.8, 1420.4): 10,
             (-23.5, 1386.4): 13, (-11.8, 1379.6): 14, (11.8, 1379.6): 16, (23.5, 1386.4): 12, (23.5, 1400.0): 15,
             (0.0, 1386.4): 13}


HEX_GONE = [(0.0, 1427.2), (-11.8, 1420.4), (11.8, 1420.4)]


def scene_hexmeltdown(args, out):
    """The referee calls YELLOW and the floor goes: hexes sink into the lava with people still on them. A
    giant screaming player rides one down, the safe yellow hexes (and their laughing winners) above."""
    v = params(args, {"cam_x": -3.0, "cam_y": 250.5, "cam_z": 1425.0, "aim_x": 0.0, "aim_y": 243.5, "aim_z": 1408.0,
                      "shift_x": 0.2, "shift_y": 0.0, "fov": 66.0, "hero_scale": 1.3})
    data = M.load_dump(args, "HexMeltdown")
    parts, _ = M.split_rigs(data["parts"])
    tops = {(round(p["cf"][0], 1), round(p["cf"][2], 1)): p for p in parts if p.get("prop") == "HexColumn" and p["n"] == "Top"}
    columns = {key: [] for key in tops}
    for part in parts:
        if part.get("prop") == "HexColumn":
            key = min(tops, key=lambda k: math.dist(k, (part["cf"][0], part["cf"][2])))
            columns[key].append(part)
    high = max(top["cf"][1] for top in tops.values())
    safe = [key for key, top in tops.items() if top["cf"][1] > high - 1]
    rng = random.Random(11)
    surface = {}
    for key, group in columns.items():
        drop = 0 if key in safe else HEX_DROPS.get(key, rng.uniform(5, 12))
        dy = high - drop - tops[key]["cf"][1]
        for part in group:
            part["cf"][1] += dy
        surface[key] = tops[key]["cf"][1] + 2.25
    # The front row has already melted away: lava all around the hero's hex.
    for key in HEX_GONE:
        for part in columns[key]:
            parts.remove(part)
    M.new_scene(args.samples, args.width, args.height, top=(0.2, 0.08, 0.35), horizon=(1.0, 0.42, 0.25),
                sun=(0.4, -0.5, 0.6), sun_energy=3.8, sun_color=(1.0, 0.88, 0.75), exposure=-0.15)
    M.build_arena(data, parts, two_sided={"RefereeBot:Flag"})
    board = M.part_named(parts, "CallBoard")
    bw, bh = board["s"][0], board["s"][1]
    M.screen(board, M.text_card((int(bw * 40), int(bh * 40)), "YELLOW", (255, 210, 50), font_size=int(bh * 40 * 0.45),
                                star=(255, 210, 50)), "Front", 1.8)
    cam_eye = B(v.cam_x, v.cam_y, v.cam_z)
    # Winners up on the yellow hexes, laughing at everyone else.
    winners = [((11.8, 1393.2), (-2.0, 1.0), "cheer", "laugh"), ((11.8, 1393.2), (2.2, -1.2), "wave", "grin"),
               ((0.0, 1372.8), (-1.8, 1.0), "cheer", "grin"), ((0.0, 1372.8), (2.0, -0.6), "jump", "laugh"),
               ((23.5, 1413.6), (0.0, 0.0), "cheer", "laugh")]
    for index, (key, (dx, dz), pose, face) in enumerate(winners):
        spot = B(key[0] + dx, surface[key] + (1.4 if pose == "jump" else 0), key[1] + dz)
        M.avatar(spot, M.face_to(spot, cam_eye) + math.radians(rng.uniform(-15, 15)), pose, index + 3, face)
    # Others going down with their hexes.
    sinking = [((-11.8, 1406.8), (0, 0), "panic", "panic"), ((-11.8, 1393.2), (0, 0), "run", "shock"),
               ((-23.5, 1413.6), (0, 0), "flail", "scream"), ((23.5, 1400.0), (0, 0), "panic", "shock")]
    for index, (key, (dx, dz), pose, face) in enumerate(sinking):
        spot = B(key[0] + dx, surface[key], key[1] + dz)
        M.avatar(spot, M.face_to(spot, cam_eye) + math.radians(rng.uniform(-15, 15)), pose, index + 8, face)
    # The hero rides a sinking hex down, the loudest face there is.
    hero_look = {"skin": 0, "shirt": (64, 196, 255), "pants": (255, 214, 64), "shoes": (250, 250, 250), "hat": "party",
                 "hat_colors": ((255, 84, 150), (255, 230, 90)), "sleeve": -0.55}
    key = (0.0, 1413.6)
    spot = B(key[0] - 0.4, surface[key] + 0.6, key[1] + 0.6)
    M.avatar(spot, M.face_to(spot, cam_eye) + 0.15, "panic", hero_look, "scream", head_scale=1.85, shoulders="top", scale=v.hero_scale,
             tilt=(math.radians(-5), math.radians(4)),
             pose_extra={"leg_l": (12, 12), "leg_r": (-8, 12), "arm_l": (-6, 150), "arm_r": (-6, 154), "head": (-5, 4, 0)})
    M.embers(220, B(0, 236, 1405), (34, 16, 30), seed=6, size=(0.1, 0.34))
    M.confetti(50, B(0, 255, 1410), (14, 6, 9), seed=8, size=0.5, avoid=[(B(key[0], surface[key] + 6.0, key[1] + 0.6), 3.6)])
    M.lamp(B(0, 236, 1408), 900, (1.0, 0.45, 0.12), 3.0)
    M.lamp(B(-10, 258, 1432), 320, (0.8, 0.88, 1.0), 4.0)
    M.camera(cam_eye, B(v.aim_x, v.aim_y, v.aim_z), fov=v.fov, roll=-4, lens_shift=(v.shift_x, v.shift_y))
    M.render_to(out / "raw_ad_hex.png")
    M.render_glow(out / "raw_ad_hex_glow.png")
    image = M.grade(out / "raw_ad_hex.png", 1.0, 1.0)
    image = M.add_glow(image, out / "raw_ad_hex_glow.png", radius=0.016, strength=0.85)
    image = punch(image, saturation=1.25, contrast=1.12)
    image = bloom(image, threshold=236, strength=0.35)
    s = args.height / 1080
    ad_text(image, "THE FLOOR IS", (args.width * 0.715, args.height * 0.12), int(130 * s), top=(255, 255, 255),
            bottom=(255, 232, 205), edge=(140, 14, 40), angle=3, glow=(255, 70, 30))
    ad_text(image, "MELTING!", (args.width * 0.713, args.height * 0.29), int(222 * s), top=(255, 240, 80),
            bottom=(255, 70, 10), edge=(120, 8, 30), angle=3, glow=(255, 60, 10))
    logo(image, (args.width * 0.82, args.height * 0.92), int(104 * s))
    return save(image, out, "ad_2_hexmeltdown.jpg")


# Main poster -----------------------------------------------------------------------------------------


def scene_poster(args, out):
    """The brand ad: three big faces (one screaming, one howling with laughter, one in shock) on a
    sunburst, the fire rope sweeping across the bottom, confetti and streamers, "30 GAMES!"."""
    w, h = args.width, args.height
    M.new_scene(args.samples, w, h, transparent=True, sun=(0.45, -0.8, 0.5), sun_energy=4.2, exposure=-0.15,
                top=(0.2, 0.25, 0.6), horizon=(0.9, 0.7, 0.9), sky_strength=0.8)
    hero = {"skin": 0, "shirt": (40, 120, 255), "pants": (40, 52, 110), "shoes": (250, 250, 250), "hat": None, "sleeve": -0.55}
    party = {"skin": 3, "shirt": (255, 84, 150), "pants": (60, 60, 70), "shoes": (250, 250, 250), "hat": "party",
             "hat_colors": ((255, 214, 64), (64, 196, 255)), "sleeve": -0.55}
    third = {"skin": 1, "shirt": (255, 150, 40), "pants": (40, 70, 140), "shoes": (250, 250, 250), "hat": "cap",
             "hat_color": (156, 108, 255), "sleeve": -0.55}
    M.avatar((-0.2, 0.0, 0), math.radians(-12), "panic", hero, "scream", head_scale=1.7, shoulders="top",
             pose_extra={"arm_l": (-4, 146), "arm_r": (-4, 150), "head": (-5, 5, -4)})
    M.avatar((-4.5, 1.2, 0), math.radians(20), "cheer", party, "laugh", head_scale=1.5, shoulders="top",
             pose_extra={"arm_l": (10, 132), "arm_r": (10, 142), "head": (-6, -8, 0)})
    M.avatar((4.5, 1.0, 0), math.radians(-20), "flail", third, "shock", head_scale=1.5, shoulders="top",
             pose_extra={"arm_l": (-6, 150), "arm_r": (-6, 148), "head": (-4, 8, 0)})
    # The fire rope sweeping through in front of their feet, across the whole width.
    rope = [V((-12 + 24 * t, -3.0 + 1.0 * math.sin(math.pi * t), 1.1 + 0.55 * math.sin(math.pi * t))) for t in
            (i / 26 for i in range(27))]
    M.fire_rope(rope, radius=0.13, seed=3, trail=(-0.2, 0.4, 1), flames=1.15)
    M.lamp((0.5, -2.6, 1.5), 140, (1.0, 0.5, 0.15), 1.4)
    M.lamp((-3, -5, 7), 90, (0.7, 0.85, 1.0), 2.0)
    M.lamp((-6.5, 3.0, 7.0), 320, (0.45, 0.8, 1.0), 1.2)
    M.lamp((7.0, 2.8, 6.4), 320, (1.0, 0.62, 0.3), 1.2)
    M.lamp((0, 3.0, 8.0), 260, (1.0, 0.9, 0.9), 1.5)
    faces = [((-0.2, -1.0, 5.3), 2.1), ((-4.5, 0.0, 5.0), 1.7), ((4.5, -0.2, 5.0), 1.7), ((0, -4, 5.0), 2.6)]
    M.confetti(160, (0, 0, 5.0), (9.5, 3.2, 4.2), seed=21, size=0.34, emission=0.5, avoid=faces)
    for index, color in enumerate(M.PARTY):
        M.streamer((-8.4 + index * 3.4, 0.5, 9.2), (0.12 * (index - 2.5), 0, -1), 3.2, color, seed=index, width=0.22,
                   turns=4.5, radius=0.18)
    M.camera((0, -10.0, 4.3), (0.0, 0, 4.1), fov=48)
    M.render_to(out / "raw_ad_poster.png")
    M.render_glow(out / "raw_ad_poster_glow.png")
    background = M.sunburst((w, h), (w * 0.5, h * 0.52), (255, 125, 205), (80, 22, 150), rays=22, ray_light=38)
    background = light_rays(background, (w * 0.5, h * 0.52), count=11, strength=34, color=(255, 200, 240), spin=0.2)
    layer = M.grade(out / "raw_ad_poster.png", saturation=1.15, contrast=1.06)
    art = M.sticker_outline(layer, max(6, int(14 * h / 1080)), (40, 14, 70))
    image = background.copy()
    image.alpha_composite(art)
    image = M.add_glow(image, out / "raw_ad_poster_glow.png", radius=0.012, strength=0.6)
    image = punch(image, saturation=1.12, contrast=1.06, clarity=0.35, vignette=0.32)
    s = h / 1080
    ad_text(image, "PARTY PANIC", (w * 0.5, h * 0.145), int(262 * s), angle=-2, glow=(255, 80, 200))
    starburst(image, (w * 0.912, h * 0.5), int(176 * s), ["30", "GAMES!"], angle=-9, text_size=int(132 * s))
    starburst(image, (w * 0.082, h * 0.5), int(128 * s), ["12", "PLAYERS"], angle=8, text_size=int(88 * s), top=(150, 235, 255),
              bottom=(40, 130, 255), edge=(20, 40, 150), text_color=(20, 40, 150), spin=0.1)
    return save(image, out, "ad_3_poster.jpg")


# Halloween --------------------------------------------------------------------------------------------


def pumpkin_hat(avatar_root, glow=7.0, tilt=0.0):
    """The game's PumpkinHat (assets/meshes/PumpkinHat.glb), glowing, on an avatar's head."""
    neck = next(child for child in avatar_root.children if child.name.startswith("neck"))
    top = 0.6 + M.HEAD_H / 2
    return M.prop("PumpkinHat", (0, 0.02, top - 0.2), 1.45, yaw=math.pi, tilt=(0, tilt), parent=neck,
                  emission={"HatGlow": glow})


def screen_point(cam, fov, aspect, u, v, depth):
    """Where (u, v) on the picture (0-1, from the top left) is `depth` studs in front of the camera, as a Roblox position."""
    ty = math.tan(math.radians(fov) / 2)
    world = cam.matrix_world @ V(((u - 0.5) * 2 * ty * aspect * depth, (0.5 - v) * 2 * ty * depth, -depth))
    return (world.x, world.z, -world.y)


def bring_bats(parts, spots):
    """The lobby's bats circle too high to be in the picture: move the ones over the emote stage to `spots`
    (Roblox positions), wings and all."""
    bodies = sorted((p for p in parts if p["n"] == "Body" and p["cf"][1] > 30 and p["cf"][2] > 40), key=lambda p: p["cf"][0])
    for body, spot in zip(bodies, spots):
        here = body["cf"][:3]
        for part in parts:
            if part["n"] in ("Wing", "Body", "Head") and part["cf"][1] > 30 and math.dist(part["cf"][:3], here) < 4.5:
                for axis in range(3):
                    part["cf"][axis] += spot[axis] - here[axis]


def scene_halloween(args, out):
    """The HALLOWEEN PARTY at dusk: a screaming player in the glowing PumpkinHat, a ghost floating up
    behind them, jack-o'-lanterns burning on the lawn."""
    v = params(args, {"cam_x": 1.5, "cam_y": 4.2, "cam_z": 27.0, "aim_x": -8.0, "aim_y": 9.0, "aim_z": 52.0,
                      "shift_x": 0.0, "shift_y": 0.0, "fov": 62.0, "hero_scale": 1.2, "hero_x": 1.5, "hero_z": 37.0})
    data = M.load_dump(args, "lobby_halloween")
    parts = [p for p in data["parts"] if p["n"] != "PortalFilm"]
    w, h = args.width, args.height
    M.new_scene(args.samples, w, h, top=(0.05, 0.03, 0.26), horizon=(1.0, 0.36, 0.2), sun=(0.75, -0.25, 0.28),
                sun_energy=1.9, sun_color=(1.0, 0.62, 0.36), exposure=-0.42, sky_strength=0.75)
    cam_eye = B(v.cam_x, v.cam_y, v.cam_z)
    cam = M.camera(cam_eye, B(v.aim_x, v.aim_y, v.aim_z), fov=v.fov, roll=-3, lens_shift=(v.shift_x, v.shift_y))
    bpy.context.view_layer.update()
    bring_bats(parts, [screen_point(cam, v.fov, w / h, u, vv, d) for u, vv, d in
                       ((0.08, 0.14, 26), (0.3, 0.07, 34), (0.17, 0.3, 22))])
    M.build_arena(data, parts)
    hero_look = {"skin": 0, "shirt": (156, 108, 255), "pants": (40, 34, 60), "shoes": (255, 150, 40), "hat": None,
                 "sleeve": -0.55}
    spot = B(v.hero_x, 0.2, v.hero_z)
    hero = M.avatar(spot, M.face_to(spot, cam_eye) + 0.1, "panic", hero_look, "scream", head_scale=1.85, shoulders="top",
                    scale=v.hero_scale, tilt=(math.radians(-4), math.radians(4)),
                    pose_extra={"arm_l": (-6, 150), "arm_r": (-6, 154), "head": (-5, 4, 0)})
    pumpkin_hat(hero)
    friends = [(v.hero_x - 7.0, v.hero_z + 3.0, "flail", "scream", 3), (v.hero_x - 16.0, v.hero_z + 9.0, "run", "shock", 6),
               (v.hero_x + 6.0, v.hero_z + 8.0, "panic", "panic", 9)]
    rng = random.Random(4)
    for x, z, pose, face, look in friends:
        spot = B(x, 0.2, z)
        M.avatar(spot, M.face_to(spot, cam_eye) + math.radians(rng.uniform(-14, 14)), pose, look, face)
    M.embers(90, B(v.hero_x, 6, v.hero_z + 10), (22, 8, 18), seed=3, size=(0.06, 0.18), color=(255, 160, 50), strength=8)
    # Warm candlelight from the lanterns and a cold purple rim from behind.
    M.lamp(B(v.hero_x - 3, 4.5, v.hero_z - 3), 900, (1.0, 0.5, 0.15), 2.0)
    M.lamp(B(v.hero_x + 4, 9, v.hero_z + 6), 1300, (0.55, 0.45, 1.0), 3.0)
    M.render_to(out / "raw_ad_halloween.png")
    M.render_glow(out / "raw_ad_halloween_glow.png")
    image = M.grade(out / "raw_ad_halloween.png", 1.0, 1.0)
    image = M.add_glow(image, out / "raw_ad_halloween_glow.png", radius=0.016, strength=0.9)
    image = punch(image, saturation=1.2, contrast=1.1, vignette=0.4, tint=(14, 2, 30))
    image = bloom(image, threshold=225, strength=0.4)
    s = h / 1080
    ad_text(image, "HALLOWEEN", (w * 0.7, h * 0.14), int(190 * s), top=(255, 200, 60), bottom=(255, 100, 10),
            edge=(70, 14, 110), angle=3, glow=(160, 60, 255))
    ad_text(image, "PARTY!", (w * 0.72, h * 0.335), int(225 * s), top=(255, 255, 255), bottom=(235, 215, 255),
            edge=(90, 24, 160), angle=3, glow=(160, 60, 255))
    starburst(image, (w * 0.87, h * 0.78), int(170 * s), ["2X", "COINS"], angle=-8, text_size=int(120 * s), top=(255, 238, 90),
              bottom=(255, 140, 20), edge=(110, 30, 150), text_color=(110, 20, 140))
    logo(image, (w * 0.22, h * 0.93), int(100 * s), angle=-3)
    return save(image, out, "ad_4_halloween.jpg")


# Bobsled Run -----------------------------------------------------------------------------------------


def scene_bobsled(args, out):
    """A crew hurtling down the ice straight at the lens, the front rider's face the biggest thing in the
    picture, ice spraying off the runners and the other sleds chasing behind."""
    v = params(args, {"ahead": 11.0, "side": 7.0, "height": 2.8, "fov": 50.0, "roll": -7.0, "aim_up": 2.2, "aim_side": 0.0,
                      "shift_x": 0.16, "shift_y": 0.0})
    data = M.load_dump(args, "BobsledRun")
    parts, _ = M.split_rigs(data["parts"])
    M.new_scene(args.samples, args.width, args.height, top=(0.08, 0.3, 0.85), horizon=(0.75, 0.88, 1.0),
                sun=(0.4, -0.5, 0.6), sun_energy=4.4)
    M.build_arena(data, parts)
    sleds = [p for p in parts if p.get("prop") == "BobsledSled" and p["n"] == "Body"]
    leader = min(sleds, key=lambda p: p["cf"][1])
    for body in sleds:
        if body is leader:
            continue
        M.sled_crew(body, [(1.6, "lean_right", 4, "determined"), (-1.2, "cheer", 9, "grin")])
    cf = leader["cf"]
    forward = V((cf[5], cf[8], cf[11]))  # down the run
    left = V((cf[3], cf[6], cf[9]))
    center = V(cf[:3])
    frame = M.empty("sled", (0, 0, 0))
    frame.matrix_world = M.R.cframe_matrix(leader["cf"])
    bpy.context.view_layer.update()
    crew = [(3.0, "lean_left", 2, "scream", 1.9, {"head": (-8, 4, 0), "arm_l": (70, 40), "arm_r": (70, 40)}),
            (0.2, "lean_left", 7, "laugh", 1.35, {"head": (-6, 0, 0)}),
            (-2.7, "lean_left", 5, "shock", 1.35, {"head": (-6, 0, 0)})]
    for forward_at, pose, look, face, head_scale, extra in crew:
        rider = M.avatar((0, -forward_at, 0.35 - 2.0), 0.0, pose, look, face, tilt=(0, math.radians(8)), pose_extra=extra,
                         head_scale=head_scale)
        rider.parent = frame
    for runner in (-1, 1):
        M.snow_spray(B(*(center - forward * 5.5 + left * runner * 1.6)), B(*(-forward + left * runner * 0.5)), count=110,
                     spread=0.7, length=8, seed=runner + 5)
    M.streaks(B(*(center - forward * 6 + V((0, 2.0, 0)))), B(*forward), count=10, length=8, seed=2, spread=2.2, width=0.1)
    M.lamp(B(*(center + forward * 7 + V((0, 6, 0)))), 700, (1.0, 0.9, 0.8), 3.0)
    eye = center + forward * v.ahead + left * v.side + V((0, v.height, 0))
    M.camera(B(*eye), B(*(center + V((0, v.aim_up, 0)) + left * v.aim_side)), fov=v.fov, roll=v.roll,
             lens_shift=(v.shift_x, v.shift_y))
    M.render_to(out / "raw_ad_bobsled.png")
    image = M.grade(out / "raw_ad_bobsled.png", 1.0, 1.0)
    image = zoom_blur(image, (args.width * 0.4, args.height * 0.55), strength=0.045, inner=0.5)
    image = punch(image, saturation=1.25, contrast=1.1, vignette=0.3, tint=(10, 20, 70))
    image = bloom(image, threshold=235, strength=0.3)
    s = args.height / 1080
    ad_text(image, "HOLD ON!", (args.width * 0.745, args.height * 0.15), int(220 * s), top=(255, 255, 255), bottom=(200, 235, 255),
            edge=(20, 50, 150), angle=4, glow=(60, 150, 255))
    ad_text(image, "BOBSLED RUN", (args.width * 0.745, args.height * 0.315), int(100 * s), top=(255, 244, 110), bottom=(255, 150, 20),
            edge=(70, 14, 110), angle=4)
    logo(image, (args.width * 0.8, args.height * 0.92), int(100 * s))
    return save(image, out, "ad_5_bobsled.jpg")


# Contact sheet ---------------------------------------------------------------------------------------


def make_sheet(out):
    """Every ad in `out` at 640 px and at the ~320 px a feed shows them: if it can't be read here, it
    won't be clicked."""
    ads = sorted(out.glob("ad_*.jpg"))
    if not ads:
        raise SystemExit(f"no ads in {out}: render them first")
    pad, big, small = 24, (640, 360), (320, 180)
    columns = min(3, len(ads))
    rows = math.ceil(len(ads) / columns)
    width = pad + columns * (big[0] + pad)
    strip = pad + len(ads) * (small[0] + pad)
    width = max(width, strip)
    sheet = Image.new("RGB", (width, pad + rows * (big[1] + pad) + small[1] + pad * 2), (24, 24, 32))
    for index, path in enumerate(ads):
        picture = Image.open(path).convert("RGB")
        x, y = pad + (index % columns) * (big[0] + pad), pad + (index // columns) * (big[1] + pad)
        sheet.paste(picture.resize(big, Image.LANCZOS), (x, y))
        sheet.paste(picture.resize(small, Image.LANCZOS), (pad + index * (small[0] + pad), pad + rows * (big[1] + pad) + pad))
    path = out / "ads_sheet.jpg"
    sheet.save(path, quality=90)
    print("wrote", path, flush=True)
    return path


# Run -------------------------------------------------------------------------------------------------

SCENES = {"firerope": scene_firerope, "hexmeltdown": scene_hexmeltdown, "poster": scene_poster, "halloween": scene_halloween, "bobsled": scene_bobsled}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dumps", default="art_dumps", help="folder of snapshots (lobby.json, FireRope.json, ...)")
    parser.add_argument("--out", default="ads")
    parser.add_argument("--only", help="comma-separated ads (default: all)")
    parser.add_argument("--samples", type=int, default=48)
    parser.add_argument("--preview", action="store_true", help="960x540 at 8 samples, to look at")
    parser.add_argument("--sheet", action="store_true", help="only make ads_sheet.jpg from the ads already in --out")
    parser.add_argument("--set", action="append", default=[], metavar="KEY=VALUE",
                        help="override a scene's setting while trying framings (cam_x, aim_y, fov, rope_angle, ...)")
    args = parser.parse_args()
    args.set = {key: float(value) for key, value in (item.split("=") for item in args.set)}
    args.width, args.height = (W // 2, H // 2) if args.preview else (W, H)
    if args.preview:
        args.samples = 8
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    if args.sheet:
        make_sheet(out)
        return
    for name in args.only.split(",") if args.only else list(SCENES):
        print("rendering", name, flush=True)
        SCENES[name](args, out)


if __name__ == "__main__":
    main()
