"""Meshes for Slaparazzi (see tools/meshgen/props/README.md). Units are studs, +Y up, base on y = 0,
-Z is the front. Generate with:
python3 tools/meshgen/generate_meshes.py --only SlaparazziCamera,SlaparazziSpotlight,SlaparazziCrowd,SlaparazziFrame,SlaparazziGlove,SlaparazziRope

The frame's ring radii must match Logic/Slaparazzi.luau RINGS (each ring line's outer edge)."""

import math

import numpy as np

from generate_meshes import (
    Mesh,
    capsule,
    cylinder,
    extrude,
    lathe,
    merge,
    rounded_box,
    sd_capsule,
    sd_ellipsoid,
    sdf_mesh,
    smin,
    sphere,
    star,
    taper,
    torus,
    tube,
)

RINGS = (3.6, 7.2, 11.0)  # Logic/Slaparazzi.luau
RING_WIDTH = 0.5
FLAT = 0.12  # the frame's thickness


def about(mesh: Mesh, axis: str, degrees: float, center) -> Mesh:
    """Rotates a mesh about a point."""
    c = np.array(center, dtype=float)
    return mesh.translate(*(-c)).rotate(axis, degrees).translate(*c)


def flat_ring(outer: float, width: float, height: float) -> Mesh:
    """A flat ring lying on y = 0 whose outer edge is at `outer`."""
    inner = outer - width
    profile = [(inner, 0.0), (outer, 0.0), (outer, height), (inner, height), (inner, 0.0)]
    return lathe(profile, 96)


# ---------------------------------------------------------------- the photo frame

def frame():
    """The photo frame on the stage: gold, silver and bronze scoring rings, a gold star in the middle
    and white viewfinder corners around it. Flat (FLAT thick), centred on the origin."""
    gold = flat_ring(RINGS[0], RING_WIDTH, FLAT)
    middle_star = extrude(star(1.5, 0.65), FLAT).rotate("x", -90).translate(0, FLAT / 2, 0)
    silver = flat_ring(RINGS[1], RING_WIDTH, FLAT)
    bronze = flat_ring(RINGS[2], RING_WIDTH, FLAT)
    corners = []
    reach, arm, thick = RINGS[2] + 0.9, 3.2, 0.55
    for sx in (-1, 1):
        for sz in (-1, 1):
            x0, z0 = sx * reach, sz * reach
            along_x = rounded_box(arm, FLAT, thick, 0.05, 2).translate(x0 - sx * (arm / 2 - thick / 2), FLAT / 2, z0)
            along_z = rounded_box(thick, FLAT, arm, 0.05, 2).translate(x0, FLAT / 2, z0 - sz * (arm / 2 - thick / 2))
            corners += [along_x, along_z]
    # Tick marks between the rings point at the middle (a camera's focusing screen).
    ticks = []
    for k in range(8):
        a = math.pi * 2 * k / 8 + math.pi / 8
        for r0, r1 in ((RINGS[0] + 0.5, RINGS[0] + 1.3), (RINGS[1] + 0.5, RINGS[1] + 1.2)):
            mid = (r0 + r1) / 2
            tick = rounded_box(0.22, FLAT * 0.8, r1 - r0, 0.05, 2)
            tick.rotate("y", -math.degrees(a) + 90).translate(math.cos(a) * mid, FLAT * 0.4, math.sin(a) * mid)
            ticks.append(tick)
    return {
        "Gold": merge(gold, middle_star),
        "Silver": silver,
        "Bronze": bronze,
        "Bracket": merge(*corners, *ticks),
    }


# ---------------------------------------------------------------- the photographer and camera

def camera():
    """A vintage press camera on a wooden tripod (lens and flash dish facing -Z) and the photographer
    behind it, bent to the viewfinder."""
    head_y = 4.45
    legs = []
    for angle in (90, 215, 325):
        a = math.radians(angle)
        foot = (math.cos(a) * 1.8, 0.0, math.sin(a) * 1.8)
        knee = (math.cos(a) * 0.95, 2.3, math.sin(a) * 0.95)
        legs.append(taper([(0, head_y - 0.1, 0), knee, foot], 0.13, 0.08, 8))
        legs.append(sphere(0.12, 6, 10).translate(*foot))
    tripod = merge(*legs, cylinder(0.12, 1.2, 12).translate(0, 2.6, 0))
    mount = merge(
        cylinder(0.42, 0.3, 20, 0.08).translate(0, head_y - 0.25, 0),
        cylinder(0.18, 0.25, 12).translate(0, head_y, 0),
    )

    body_y = head_y + 0.95
    body = rounded_box(2.2, 1.6, 1.5, 0.22).translate(0, body_y, 0)
    viewfinder = rounded_box(0.9, 0.45, 0.8, 0.12).translate(0, body_y + 0.95, 0.15)
    grip = rounded_box(0.35, 1.2, 0.6, 0.15).translate(1.25, body_y - 0.05, 0.1)
    # The bellows: a square accordion from the body to the lens board.
    profile = []
    for i in range(7):
        r = 0.95 - i * 0.07 + (0.08 if i % 2 else 0.0)
        profile.append((r, i * 0.17))
    bellows = lathe(profile, 4, cap_bottom=True, cap_top=True).rotate("y", 45).rotate("x", -90)
    bellows.translate(0, body_y, -0.7)
    board = rounded_box(1.35, 1.35, 0.18, 0.08).translate(0, body_y, -1.85)
    barrel = cylinder(0.5, 0.55, 28, 0.06).rotate("x", -90).translate(0, body_y, -1.9)
    rim = torus(0.5, 0.08, 32, 8).rotate("x", 90).translate(0, body_y, -2.45)
    glass = cylinder(0.42, 0.05, 28).rotate("x", -90).translate(0, body_y, -2.43)
    # The flash: an arm up from the body's side to a big dish facing forward, the bulb in it.
    arm = tube([(-1.05, body_y + 0.3, 0.0), (-1.3, body_y + 0.8, 0.0), (-1.3, body_y + 1.5, -0.2)], 0.08, 8)
    dish_profile = [(0.12, 0.0), (0.45, 0.08), (0.8, 0.3), (1.0, 0.6), (0.94, 0.62), (0.74, 0.35), (0.4, 0.14), (0.1, 0.06)]
    dish = lathe(dish_profile, 32, cap_bottom=True).rotate("x", -90).translate(-1.3, body_y + 2.1, -0.15)
    bulb = sphere(0.24, 8, 14).translate(-1.3, body_y + 2.1, -0.55)
    socket = cylinder(0.12, 0.3, 10).rotate("x", -90).translate(-1.3, body_y + 2.1, -0.2)

    # The photographer, bent to the viewfinder at the back of the camera.
    def coat_sdf(p):
        d = sd_capsule(p, (0, 3.0, 2.45), (0, 4.75, 1.95), 0.68)
        d = smin(d, sd_ellipsoid(p, (0, 2.85, 2.5), (0.82, 0.62, 0.66)), 0.3)  # the coat's skirt
        for sx in (-1, 1):
            shoulder = (sx * 0.72, 4.8, 1.95)
            elbow = (sx * 1.25, 4.35, 1.2)
            hand = (sx * 1.2, body_y - 0.05, 0.45)
            d = smin(d, sd_capsule(p, shoulder, elbow, 0.24), 0.18)
            d = smin(d, sd_capsule(p, elbow, hand, 0.21), 0.08)
        return d

    coat = sdf_mesh(coat_sdf, (-1.6, 2.0, 0.1), (1.6, 5.7, 3.3), 0.11)
    collar = torus(0.42, 0.12, 24, 8).rotate("x", 25).translate(0, 5.12, 1.85)
    head = sphere(0.55, 12, 20).translate(0, 5.75, 1.4)
    nose = sphere(0.14, 6, 10).translate(0, 5.6, 0.86)
    hands = merge(*(sphere(0.24, 8, 12).translate(sx * 1.2, body_y - 0.05, 0.4) for sx in (-1, 1)))
    legs_p = merge(*(capsule(2.9, 0.3, 14).translate(sx * 0.36, 1.75, 2.45) for sx in (-1, 1)))
    shoes = merge(*(sphere(1.0, 8, 14).scale(0.32, 0.22, 0.5).translate(sx * 0.38, 0.2, 2.25) for sx in (-1, 1)))
    beret = merge(
        sphere(1.0, 8, 18).scale(0.66, 0.2, 0.66).translate(0.1, 6.22, 1.55),
        cylinder(0.06, 0.18, 8).translate(0.1, 6.36, 1.55),
    )
    beret = about(beret, "z", -12, (0, 6.2, 1.5))

    return {
        "Tripod": tripod,
        "Chrome": merge(mount, rim, arm, socket),
        "Body": merge(body, viewfinder, grip, board),
        "Bellows": bellows,
        "Lens": barrel,
        "Glass": glass,
        "Dish": dish,
        "Bulb": bulb,
        "Coat": merge(coat, collar),
        "Skin": merge(head, nose, hands),
        "Pants": legs_p,
        "Shoes": shoes,
        "Beret": beret,
    }


# ---------------------------------------------------------------- the spotlight

def spotlight():
    """A stage spotlight on a stand, its can tilted down toward -Z (the stage)."""
    legs = []
    for angle in (30, 150, 270):
        a = math.radians(angle)
        foot = (math.cos(a) * 1.4, 0.06, math.sin(a) * 1.4)
        legs.append(taper([(0, 1.3, 0), foot], 0.1, 0.07, 8))
        legs.append(rounded_box(0.36, 0.12, 0.36, 0.05, 2).translate(foot[0], 0.06, foot[2]))
    pole = merge(cylinder(0.13, 6.0, 14).translate(0, 1.1, 0), cylinder(0.2, 0.35, 14, 0.05).translate(0, 4.0, 0))
    lamp_y = 7.6
    yoke = tube([(-1.0, lamp_y, 0), (-1.0, lamp_y - 0.95, 0), (1.0, lamp_y - 0.95, 0), (1.0, lamp_y, 0)], 0.09, 8)
    stem = cylinder(0.1, 0.55, 10).translate(0, lamp_y - 1.45, 0)
    knobs = merge(*(cylinder(0.2, 0.14, 12).rotate("z", 90).translate(sx * 1.12, lamp_y, 0) for sx in (-1, 1)))

    # The can, built along +Y around the origin, then turned to face -Z and tilted down.
    can = lathe([(0.0, -1.0), (0.55, -1.0), (0.7, -0.85), (0.78, 0.6), (0.82, 0.9), (0.0, 0.9)], 28)
    fins = merge(*(torus(0.8, 0.05, 28, 6).translate(0, y, 0) for y in (-0.6, -0.35, -0.1)))
    lens = cylinder(0.66, 0.06, 28).translate(0, 0.88, 0)
    doors = []
    for k in range(4):
        door = rounded_box(1.15, 0.04, 0.5, 0.02, 2).translate(0, 0, 0.25)
        door.rotate("x", 50).translate(0, 0.92, 0.72)
        door.rotate("y", 90 * k)
        doors.append(door)
    tilt = -115

    def place(mesh: Mesh) -> Mesh:
        return mesh.rotate("x", tilt).translate(0, lamp_y, 0)

    return {
        "Stand": merge(*legs, pole, yoke, stem, knobs),
        "Can": merge(place(can), place(fins), *(place(d) for d in doors)),
        "Lens": place(lens),
    }


# ---------------------------------------------------------------- the crowd

def crowd():
    """A section of cheering fans on a three-tier riser, facing -Z: arms up, phones out, signs."""
    rng = np.random.default_rng(24)
    tiers = []
    for i in range(3):
        top = 0.8 * (i + 1)
        tiers.append(rounded_box(16.0, top, 6.0 - 2.0 * i, 0.12, 3).translate(0, top / 2, -3.0 + 2.0 * i + (6.0 - 2.0 * i) / 2))
    rail = merge(
        *(cylinder(0.08, 1.1, 8).translate(x, 2.4, 2.8) for x in (-7.8, -3.9, 0, 3.9, 7.8)),
        tube([(-7.8, 3.5, 2.8), (7.8, 3.5, 2.8)], 0.08, 8),
    )
    shirts = {"ShirtA": [], "ShirtB": [], "ShirtC": []}
    skins = {"SkinA": [], "SkinB": []}
    hair, phones, screens, signs, stars = [], [], [], [], []
    names = list(shirts)
    for row in range(3):
        floor = 0.8 * (row + 1)
        z = -2.0 + 2.0 * row
        count = 6
        for k in range(count):
            x = -6.6 + k * 2.64 + rng.uniform(-0.3, 0.3) + (0.6 if row % 2 else 0.0)
            if abs(x) > 7.4:
                continue
            h = rng.uniform(0.9, 1.1)
            shirt = names[(row * 2 + k) % 3]
            skin = "SkinA" if rng.uniform() < 0.55 else "SkinB"
            body = capsule(1.9 * h, 0.5, 14).translate(x, floor + 0.95 * h, z)
            legs = capsule(1.0, 0.22, 10).scale(1.9, 1, 1).translate(x, floor + 0.35, z)
            head_y = floor + 1.95 * h + 0.42
            head = sphere(0.42, 10, 16).translate(x, head_y, z)
            cap = sphere(0.44, 8, 14).scale(1, 0.75, 1).translate(x, head_y + 0.12, z + 0.06)
            shirts[shirt] += [body, legs]
            skins[skin].append(head)
            hair.append(cap)
            shoulder_y = floor + 1.55 * h
            pose = (row * 7 + k * 3) % 4
            for sx in (-1, 1):
                shoulder = (x + sx * 0.45, shoulder_y, z)
                if pose == 0 or (pose == 3 and sx == 1):  # cheering: arm up and out
                    hand = (x + sx * 0.95, shoulder_y + 1.2, z - 0.15)
                elif pose == 1 and sx == 1:  # filming the stage on a phone
                    hand = (x + 0.2, shoulder_y + 0.55, z - 0.75)
                    phones.append(rounded_box(0.42, 0.7, 0.1, 0.05, 2).translate(hand[0], hand[1] + 0.3, hand[2] - 0.1))
                    screens.append(rounded_box(0.34, 0.58, 0.04, 0.02, 2).translate(hand[0], hand[1] + 0.3, hand[2] - 0.16))
                elif pose == 2:  # holding a sign up with both hands
                    hand = (x + sx * 0.5, shoulder_y + 1.15, z - 0.25)
                else:  # waving low
                    hand = (x + sx * 0.75, shoulder_y - 0.4, z - 0.3)
                shirts[shirt].append(tube([shoulder, hand], 0.16, 8))
                skins[skin].append(sphere(0.19, 6, 10).translate(*hand))
            if pose == 2:
                sign_y = shoulder_y + 1.6
                signs.append(rounded_box(1.7, 1.0, 0.08, 0.06, 2).translate(x, sign_y, z - 0.35))
                stars.append(extrude(star(0.38, 0.16), 0.06).translate(x, sign_y, z - 0.42))
    pieces = {
        "Riser": merge(*tiers),
        "Rail": rail,
        "Hair": merge(*hair),
        "Phone": merge(*phones),
        "Screen": merge(*screens),
        "Sign": merge(*signs),
        "SignStar": merge(*stars),
    }
    for name, parts in {**shirts, **skins}.items():
        pieces[name] = merge(*parts)
    return pieces


# ---------------------------------------------------------------- the slap glove and the ropes

def glove():
    """A big open cartoon glove, palm facing -Z, fingers up, a rolled cuff at the wrist."""

    def hand_sdf(p):
        d = sd_ellipsoid(p, (0, 1.45, 0), (0.82, 0.85, 0.34))
        for x, top in ((-0.54, 2.75), (-0.18, 2.98), (0.18, 2.92), (0.54, 2.6)):
            d = smin(d, sd_capsule(p, (x * 0.9, 1.9, 0.0), (x * 1.15, top, -0.06), 0.2), 0.12)
        d = smin(d, sd_capsule(p, (0.62, 1.15, -0.02), (1.25, 1.85, -0.12), 0.21), 0.14)
        d = smin(d, sd_ellipsoid(p, (0, 0.75, 0), (0.6, 0.5, 0.3)), 0.2)  # the wrist
        return d

    hand = sdf_mesh(hand_sdf, (-1.05, 0.2, -0.55), (1.6, 3.35, 0.5), 0.08)
    cuff = merge(
        torus(0.6, 0.2, 32, 10).translate(0, 0.42, 0),
        lathe([(0.0, 0.0), (0.68, 0.0), (0.72, 0.25), (0.62, 0.5), (0.0, 0.5)], 32).translate(0, 0.02, 0),
    )
    stitches = merge(*(tube([(x, 1.15, 0.3), (x * 1.05, 1.85, 0.27)], 0.04, 6) for x in (-0.3, 0.0, 0.3)))
    return {"Glove": hand, "Cuff": cuff, "Stitch": stitches}


def rope():
    """Two brass stanchions six studs apart along X with a velvet rope drooping between them."""
    posts = []
    for x in (-3.0, 3.0):
        posts.append(lathe([(0.0, 0.0), (0.55, 0.0), (0.58, 0.1), (0.4, 0.22), (0.14, 0.32), (0.0, 0.32)], 24).translate(x, 0, 0))
        posts.append(cylinder(0.09, 2.6, 12).translate(x, 0.3, 0))
        posts.append(sphere(0.2, 8, 14).translate(x, 3.0, 0))
        posts.append(torus(0.13, 0.04, 14, 6).translate(x, 2.72, 0))
    points = []
    for i in range(17):
        t = i / 16
        x = -2.85 + 5.7 * t
        points.append((x, 2.7 - 0.75 * math.sin(math.pi * t), 0.0))
    velvet = tube(points, 0.11, 10)
    return {"Brass": merge(*posts), "Rope": velvet}


PROPS = {
    "SlaparazziFrame": frame,
    "SlaparazziCamera": camera,
    "SlaparazziSpotlight": spotlight,
    "SlaparazziCrowd": crowd,
    "SlaparazziGlove": glove,
    "SlaparazziRope": rope,
}
COLORS = {
    "Gold": (255, 200, 60),
    "Silver": (210, 220, 235),
    "Bronze": (205, 125, 70),
    "Bracket": (255, 255, 255),
    "Tripod": (150, 100, 60),
    "Chrome": (190, 195, 205),
    "Body": (40, 38, 44),
    "Bellows": (120, 40, 45),
    "Lens": (60, 60, 66),
    "Glass": (70, 110, 170),
    "Dish": (225, 228, 235),
    "Bulb": (255, 250, 220),
    "Coat": (40, 120, 130),
    "Skin": (240, 190, 150),
    "Pants": (50, 50, 70),
    "Shoes": (70, 45, 35),
    "Beret": (210, 40, 60),
    "Stand": (60, 60, 66),
    "Can": (30, 30, 34),
    "Riser": (90, 50, 120),
    "Rail": (200, 170, 70),
    "Hair": (70, 45, 30),
    "Phone": (30, 30, 34),
    "Screen": (200, 230, 255),
    "Sign": (250, 250, 250),
    "SignStar": (255, 90, 170),
    "ShirtA": (255, 90, 120),
    "ShirtB": (80, 170, 255),
    "ShirtC": (255, 205, 60),
    "SkinA": (240, 190, 150),
    "SkinB": (150, 100, 70),
    "Glove": (250, 250, 250),
    "Cuff": (255, 120, 180),
    "Stitch": (40, 40, 50),
    "Brass": (215, 175, 70),
    "Rope": (170, 20, 40),
}
