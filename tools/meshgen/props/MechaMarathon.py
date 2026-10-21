"""Props for Mecha-Marathon: the wind-up flying toy every player winds and launches, its launch pad,
the distance boards along the field, the flag that marks a landing, bunting, the start gantry's
towers and the hot air balloons over the field.

    python3 tools/meshgen/generate_meshes.py --only MechaMarathonStand,MechaMarathonFlyer,MechaMarathonPad,MechaMarathonSign,MechaMarathonFlag,MechaMarathonBunting,MechaMarathonTower,MechaMarathonSkyBalloon

Units are studs, +Y is up, the base sits on y = 0 and -Z is the front:
  * MechaMarathonFlyer: a chubby tin copter-bot (Body in the player's color) with a porthole face, stubby
    wings, a two-blade Rotor on top and a wind-up Key in its back (+Z). The client spins the Rotor about
    the toy's up axis and the Key about its back-to-front axis, through the middle of each piece, so both
    are built symmetric about their axles.
  * MechaMarathonPad: a spring launch pad; its Top (the lane's color) is at y = 1.3, where the toy stands.
  * MechaMarathonSign: a distance board on two posts; its white Board's front face is at z = -0.25 and the
    game puts the number on a panel just in front of it (y 4.65..7.65).
  * MechaMarathonFlag: a little flag on a pole; the client colors the Pennant (it flies toward +X).
  * MechaMarathonBunting: 40 studs of bunting along Z, sagging; its string ends are at the top (y 2.55).
  * MechaMarathonTower: a candy-striped pylon with a gold ball on top (the start gantry).
  * MechaMarathonSkyBalloon: a hot air balloon; StripesA is recolored per balloon.
  * MechaMarathonStand: a grandstand of cheering fans under a striped awning, facing -Z.
"""

import math

import numpy as np

from generate_meshes import (Mesh, capsule, cylinder, extrude, icosphere, lathe, merge, rounded_box, sphere, star, torus,
                             tube)


def ellipsoid(rx: float, ry: float, rz: float, detail: int = 2) -> Mesh:
    return icosphere(1.0, detail).scale(rx, ry, rz)


def along_z(mesh: Mesh) -> Mesh:
    """Turns a mesh built along +Y to run along +Z."""
    return mesh.rotate("x", 90)


def facing(mesh: Mesh, normal: tuple[float, float, float]) -> Mesh:
    """Turns a feature built facing -Z (in the XY plane) to face along `normal`."""
    n = np.array(normal, dtype=float)
    n /= np.linalg.norm(n)
    forward = -n  # the feature's +Z points into the surface
    up = np.array([0.0, 1.0, 0.0])
    right = np.cross(up, forward)
    right /= np.linalg.norm(right)
    up = np.cross(forward, right)
    rotation = np.stack([right, up, forward], axis=1)
    mesh.v = mesh.v @ rotation.T
    return mesh


# ---------------------------------------------------------------------------- the flyer

BODY_BOTTOM, BODY_TOP = 0.28, 2.49
BODY_R = 1.03


def body_profile(rings: int = 24) -> list[tuple[float, float]]:
    """(radius, y) from the bottom to the top: a chubby egg, a little wider low down."""
    points = []
    center, half = (BODY_BOTTOM + BODY_TOP) / 2, (BODY_TOP - BODY_BOTTOM) / 2
    for i in range(rings + 1):
        theta = math.pi * i / rings
        y = center - half * math.cos(theta)
        r = BODY_R * math.sin(theta) ** 0.8 * (1 + 0.07 * math.cos(theta))
        points.append((max(r, 0.0), y))
    points[0] = (0.0, BODY_BOTTOM)
    points[-1] = (0.0, BODY_TOP)
    return points


BODY = body_profile()


def body_radius(y: float) -> float:
    for (r0, y0), (r1, y1) in zip(BODY, BODY[1:]):
        if y0 <= y <= y1:
            return r0 + (r1 - r0) * (y - y0) / max(y1 - y0, 1e-9)
    return 0.0


def body_point(x: float, y: float, side: int = -1) -> tuple[np.ndarray, np.ndarray]:
    """A point on the body's front (side -1) or back (+1) at (x, y), and the outward normal there."""
    r = body_radius(y)
    x = max(-r * 0.97, min(r * 0.97, x))
    z = side * math.sqrt(max(r * r - x * x, 1e-6))
    slope = (body_radius(y + 0.04) - body_radius(y - 0.04)) / 0.08
    normal = np.array([x, -slope * r, z])
    normal /= np.linalg.norm(normal)
    return np.array([x, y, z]), normal


def on_body(mesh: Mesh, x: float, y: float, lift: float) -> Mesh:
    point, normal = body_point(x, y)
    facing(mesh, tuple(normal))
    return mesh.translate(*(point + normal * lift))


def flyer():
    """The wind-up copter-bot."""
    body = lathe(BODY, 32)

    # A riveted tin seam around the middle, a collar at the top and boots.
    band_y = 0.98
    band = torus(body_radius(band_y) + 0.01, 0.075, 32, 6).translate(0, band_y, 0)
    rivets = []
    for k in range(10):
        a = 2 * math.pi * (k + 0.5) / 10
        r = body_radius(band_y) + 0.075
        rivets.append(sphere(0.05, 4, 6).translate(math.cos(a) * r, band_y, math.sin(a) * r))
    collar = torus(0.22, 0.06, 16, 6).translate(0, 2.43, 0)
    mast = cylinder(0.08, 0.5, 12).translate(0, 2.35, 0)

    # The face: a domed porthole with a chrome rim and two glowing eyes, rosy cheeks.
    face_x, face_y = 0.0, 1.66
    point, normal = body_point(face_x, face_y)
    rim = facing(torus(0.46, 0.075, 32, 8).rotate("x", 90), tuple(normal)).translate(*(point - normal * 0.02))
    lens = facing(ellipsoid(0.43, 0.43, 0.16), tuple(normal)).translate(*(point - normal * 0.02))
    eyes = []
    for side in (-1, 1):
        eye_point = point - normal * 0.02 + np.array([side * 0.15, 0.03, 0.0])
        bulge = 0.16 * math.sqrt(max(1 - (0.15 ** 2 + 0.03 ** 2) / 0.43 ** 2, 0))
        eyes.append(facing(ellipsoid(0.085, 0.13, 0.05, 1), tuple(normal)).translate(*(eye_point + normal * (bulge - 0.012))))
    cheeks = [on_body(ellipsoid(0.15, 0.1, 0.035, 1), side * 0.62, 1.32, -0.004) for side in (-1, 1)]

    # Stubby swept wings with rounded tips.
    wings = []
    for side in (-1, 1):
        outline = [(0.0, -0.36), (0.55, -0.12), (0.78, 0.08), (0.8, 0.26), (0.62, 0.36), (0.0, 0.34)]
        wing = extrude(outline, 0.14).rotate("x", 90)  # flat, the outline's y running along z
        wing = wing.translate(0.82, 1.28, 0.02)
        if side < 0:
            wing.v[:, 0] *= -1
            wing.f = wing.f[:, ::-1].copy()
        wings.append(wing)
    boots = [ellipsoid(0.3, 0.2, 0.42).translate(side * 0.42, 0.2, -0.08) for side in (-1, 1)]

    # The rotor: a hub and two pitched blades, the second the first turned half a turn.
    blade = rounded_box(1.72, 0.065, 0.36, 0.03).rotate("x", 7).translate(0.17 + 0.86, 2.92, 0)
    blade_tip = ellipsoid(0.2, 0.05, 0.19, 1).rotate("x", 7).translate(1.86, 2.92, 0)
    one = merge(blade, blade_tip)
    two = one.copy().rotate("y", 180)
    hub = sphere(0.17, 6, 10).translate(0, 2.92, 0)
    rotor = merge(hub, one, two)

    # The wind-up key in the back: a shaft along +Z and a butterfly bow, symmetric about the shaft.
    key_y = 1.3
    shaft = along_z(cylinder(0.075, 0.66, 12)).translate(0, key_y, 0.82)
    washer = torus(0.13, 0.045, 12, 5).rotate("x", 90).translate(0, key_y, 1.1)
    lobes = [torus(0.2, 0.07, 18, 6).rotate("z", 90).translate(0, key_y + side * 0.3, 1.66) for side in (-1, 1)]
    web = rounded_box(0.13, 0.42, 0.24, 0.05).translate(0, key_y, 1.58)
    key = merge(shaft, washer, web, *lobes)

    return {
        "Body": body,
        "Trim": merge(band, *rivets, collar, mast, rim),
        "Visor": lens,
        "Eyes": merge(*eyes),
        "Cheeks": merge(*cheeks),
        "Accent": merge(*wings),
        "Dark": merge(*boots),
        "Rotor": rotor,
        "Key": key,
    }


# ---------------------------------------------------------------------------- the launch pad

PAD_TOP = 1.3


def helix(radius: float, y0: float, y1: float, turns: float, steps: int = 72) -> list[tuple[float, float, float]]:
    points = []
    for i in range(steps + 1):
        t = i / steps
        a = 2 * math.pi * turns * t
        points.append((math.cos(a) * radius, y0 + (y1 - y0) * t, math.sin(a) * radius))
    return points


def pad():
    """A spring launch pad: a drum base, a chrome coil and a colored top plate with a white ring and
    an arrow pointing down the lane (-Z)."""
    base = lathe([(0.0, 0.0), (2.5, 0.0), (2.62, 0.06), (2.66, 0.2), (2.6, 0.38), (2.45, 0.46), (2.2, 0.48), (0.0, 0.48)], 48)
    core = cylinder(1.15, 0.6, 32).translate(0, 0.44, 0)
    coil_points = helix(1.55, 0.56, 0.92, 2.5)
    coil = merge(tube(coil_points, 0.1, 8), sphere(0.1, 5, 8).translate(*coil_points[0]),
                 sphere(0.1, 5, 8).translate(*coil_points[-1]))
    top = lathe([(0.0, 0.98), (2.15, 0.98), (2.24, 1.02), (2.28, 1.12), (2.24, 1.24), (2.12, PAD_TOP), (0.0, PAD_TOP)], 48)
    ring = torus(1.62, 0.055, 48, 6).scale(1, 0.6, 1).translate(0, PAD_TOP, 0)
    arrow = extrude([(-0.5, 0.25), (0.0, -0.45), (0.5, 0.25)], 0.06).rotate("x", 90).translate(0, PAD_TOP + 0.005, -1.7)
    bolts = [sphere(0.11, 5, 8).scale(1, 0.6, 1).translate(math.cos(a) * 2.32, 0.48, math.sin(a) * 2.32)
             for a in np.linspace(0, 2 * math.pi, 8, endpoint=False) + math.pi / 8]
    feet = []
    for a in np.linspace(0, 2 * math.pi, 4, endpoint=False) + math.pi / 4:
        feet.append(rounded_box(0.7, 0.16, 0.7, 0.06).translate(math.cos(a) * 2.35, 0.08, math.sin(a) * 2.35))
    return {
        "Base": base,
        "Dark": merge(core, *feet),
        "Spring": coil,
        "Top": top,
        "Ring": merge(ring, arrow),
        "Trim": merge(*bolts),
    }


# ---------------------------------------------------------------------------- the distance board

BOARD_Y = 6.15


def sign():
    """A distance board on two posts: a white board in a colored frame, with a star on top. The
    number goes on a panel the game places just in front of the board (front face at z = -0.25)."""
    posts = [cylinder(0.17, 8.3, 14, 0.04).translate(side * 2.35, 0, 0.0) for side in (-1, 1)]
    feet = [cylinder(0.32, 0.25, 14, 0.06).translate(side * 2.35, 0, 0.0) for side in (-1, 1)]
    caps = [sphere(0.22, 7, 12).translate(side * 2.35, 8.32, 0) for side in (-1, 1)]
    board = rounded_box(6.2, 3.0, 0.5, 0.08).translate(0, BOARD_Y, 0)
    frame = merge(
        rounded_box(6.7, 0.32, 0.62, 0.12).translate(0, BOARD_Y + 1.6, 0),
        rounded_box(6.7, 0.32, 0.62, 0.12).translate(0, BOARD_Y - 1.6, 0),
        rounded_box(0.32, 3.5, 0.62, 0.12).translate(-3.2, BOARD_Y, 0),
        rounded_box(0.32, 3.5, 0.62, 0.12).translate(3.2, BOARD_Y, 0),
    )
    topper = extrude(star(0.62, 0.28, 5), 0.22)
    topper.smooth = False
    topper = topper.translate(0, BOARD_Y + 2.45, 0)
    stem = cylinder(0.07, 0.6, 8).translate(0, BOARD_Y + 1.7, 0)
    return {
        "Post": merge(*posts, *caps, stem),
        "Dark": merge(*feet),
        "Board": board,
        "Frame": merge(frame, topper),
    }


# ---------------------------------------------------------------------------- the landing flag

def flag():
    """A flag on a pole with a gold ball on top; the Pennant flies toward +X with a little wave."""
    base = lathe([(0.0, 0.0), (0.45, 0.0), (0.48, 0.05), (0.42, 0.14), (0.2, 0.22), (0.12, 0.3), (0.0, 0.3)], 20)
    pole = cylinder(0.065, 4.2, 10).translate(0, 0.2, 0)
    finial = sphere(0.15, 8, 12).translate(0, 4.47, 0)
    # The pennant: a long triangle, waving, thin.
    rows = []
    length, top, bottom = 1.9, 4.25, 3.15
    columns = 12
    for i in range(columns + 1):
        u = i / columns
        x = 0.05 + length * u
        wave = math.sin(u * math.pi * 1.6) * 0.16 * u
        half = (top - bottom) / 2 * (1 - u * 0.92)
        mid = (top + bottom) / 2 - 0.08 * u
        rows.append((x, mid - half, mid + half, wave))
    verts, faces = [], []
    for x, y0, y1, wave in rows:
        for z_side in (-0.03, 0.03):
            verts.append((x, y0, wave + z_side))
            verts.append((x, y1, wave + z_side))
    # vertex index: column*4 + side*2 + (0 bottom, 1 top)
    for i in range(columns):
        a, b = i * 4, (i + 1) * 4
        # front (-z) side, back (+z) side, top and bottom edges
        faces += [(a + 0, b + 0, a + 1), (b + 0, b + 1, a + 1)]
        faces += [(a + 2, a + 3, b + 2), (b + 2, a + 3, b + 3)]
        faces += [(a + 1, b + 1, a + 3), (b + 1, b + 3, a + 3)]
        faces += [(a + 0, a + 2, b + 0), (b + 0, a + 2, b + 2)]
    last = columns * 4
    faces += [(0, 1, 2), (1, 3, 2), (last, last + 2, last + 1), (last + 1, last + 2, last + 3)]
    pennant = Mesh(verts, faces)
    return {"Base": base, "Pole": pole, "Finial": finial, "Pennant": pennant}


# ---------------------------------------------------------------------------- bunting

BUNTING_LENGTH = 40.0
BUNTING_TOP = 2.55
BUNTING_SAG = 1.5


def bunting():
    """Pennants on a sagging string, 40 studs along Z; three sets of colors."""
    def string_y(z: float) -> float:
        return BUNTING_TOP - 0.05 - BUNTING_SAG * (1 - (2 * z / BUNTING_LENGTH) ** 2)

    zs = np.linspace(-BUNTING_LENGTH / 2, BUNTING_LENGTH / 2, 41)
    string = tube([(0.0, string_y(z), z) for z in zs], 0.05, 6)
    sets = {"FlagsA": [], "FlagsB": [], "FlagsC": []}
    names = list(sets)
    count = 19
    for k in range(count):
        z = -BUNTING_LENGTH / 2 + (k + 1) * BUNTING_LENGTH / (count + 1)
        y = string_y(z)
        tri = extrude([(-0.42, 0.0), (0.42, 0.0), (0.0, -0.92)], 0.05)  # in XY, hanging down
        tri.smooth = False
        tri = tri.rotate("y", 90).translate(0.0, y, z)  # the flat side faces the field's sides (X)
        sets[names[k % 3]].append(tri)
    pieces = {"String": string}
    for name, flags in sets.items():
        pieces[name] = merge(*flags)
    return pieces


# ---------------------------------------------------------------------------- the start towers

def tower():
    """A candy-striped pylon on a round footing, with a gold ball and a star on top."""
    footing = lathe([(0.0, 0.0), (1.25, 0.0), (1.3, 0.1), (1.2, 0.5), (0.85, 0.7), (0.6, 0.78), (0.0, 0.78)], 32)
    white, red = [], []
    height, bands = 17.4, 12
    for i in range(bands):
        y0 = 0.7 + height * i / bands
        y1 = 0.7 + height * (i + 1) / bands
        r0 = 0.58 - 0.16 * i / bands
        r1 = 0.58 - 0.16 * (i + 1) / bands
        piece = lathe([(0.0, y0), (r0, y0), (r1, y1), (0.0, y1)], 24)
        (white if i % 2 == 0 else red).append(piece)
    collar = torus(0.5, 0.12, 24, 8).translate(0, 18.1, 0)
    ball = sphere(0.95, 14, 20).translate(0, 19.05, 0)
    topper = extrude(star(0.75, 0.33, 5), 0.25)
    topper.smooth = False
    topper = topper.translate(0, 20.55, 0)
    return {
        "Base": footing,
        "Pole": merge(*white),
        "Stripes": merge(*red, collar),
        "Gold": merge(ball, topper),
    }


# ---------------------------------------------------------------------------- hot air balloons

def balloon_radius(t: float) -> float:
    """The envelope's radius from its mouth (t = 0) to its crown (t = 1)."""
    a = math.pi * t
    return 8.0 * math.sin(a) ** 0.75 * (1 - 0.55 * (1 - t) ** 2.2) + 1.4 * (1 - t) ** 3


def sky_balloon():
    """A hot air balloon: an envelope of alternating gores, a wicker basket on ropes, a burner."""
    mouth, crown = 6.0, 23.0
    gores, rings = 16, 26
    a_pieces = {"StripesA": [], "StripesB": []}
    for g in range(gores):
        a0 = 2 * math.pi * g / gores
        a1 = 2 * math.pi * (g + 1) / gores
        verts, faces = [], []
        steps = 4
        for i in range(rings + 1):
            t = i / rings
            y = mouth + (crown - mouth) * t
            r = balloon_radius(t) if t < 1 else 0.0
            for s in range(steps + 1):
                a = a0 + (a1 - a0) * s / steps
                bulge = 1 + 0.03 * math.sin(math.pi * s / steps)
                verts.append((math.cos(a) * r * bulge, y, math.sin(a) * r * bulge))
        for i in range(rings):
            for s in range(steps):
                p = i * (steps + 1) + s
                q = p + steps + 1
                faces += [(p, q, p + 1), (p + 1, q, q + 1)]
        a_pieces["StripesA" if g % 2 == 0 else "StripesB"].append(Mesh(verts, faces))
    skirt = lathe([(1.45, mouth - 0.9), (1.75, mouth - 0.2), (1.8, mouth + 0.05), (1.55, mouth + 0.05)], 24)
    basket = rounded_box(2.6, 1.9, 2.6, 0.25).translate(0, 0.95, 0)
    rim = torus(1.45, 0.14, 4, 6).rotate("y", 45).translate(0, 1.92, 0)
    burner = cylinder(0.45, 0.6, 14).translate(0, 3.2, 0)
    ropes = []
    for sx in (-1, 1):
        for sz in (-1, 1):
            ropes.append(tube([(sx * 1.15, 1.9, sz * 1.15), (sx * 1.25, mouth - 0.85, sz * 1.25)], 0.06, 5))
    return {
        "StripesA": merge(*a_pieces["StripesA"]),
        "StripesB": merge(*a_pieces["StripesB"]),
        "Skirt": skirt,
        "Basket": merge(basket, rim),
        "Rope": merge(*ropes),
        "Burner": burner,
    }


# ---------------------------------------------------------------------------- the grandstands

STAND_WIDTH = 24.0


def fan(x: float, seat_y: float, z: float, cheering: bool, seed: int) -> tuple[Mesh, Mesh]:
    """A seated peg-doll fan facing -Z: (shirt, head). Cheering fans have both arms up."""
    rng = np.random.default_rng(seed)
    lean = rng.uniform(-6, 6)
    body = capsule(1.25, 0.4, 8).rotate("z", lean).translate(x, seat_y + 0.62, z)
    head = sphere(0.36, 5, 9).translate(x + math.sin(math.radians(-lean)) * 0.95, seat_y + 1.62, z - 0.05)
    arms = []
    for side in (-1, 1):
        if cheering:
            tip = (x + side * 0.75, seat_y + 2.15, z - 0.15)
        else:
            tip = (x + side * 0.5, seat_y + 0.5, z - 0.45)
        arms.append(tube([(x + side * 0.32, seat_y + 1.0, z), tip], 0.11, 5))
        arms.append(sphere(0.13, 4, 6).translate(*tip))
    return merge(body, *arms), head


def stand():
    """A three-tier grandstand facing -Z under a striped awning, full of cheering fans in three
    shirt colors (FansA, FansB, FansC: the client bounces them when the toys fly)."""
    half = STAND_WIDTH / 2
    tiers = []
    seats = []
    fans = {"FansA": [], "FansB": [], "FansC": []}
    heads = []
    names = list(fans)
    seed = 0
    for k in range(3):
        top = 1.0 + k * 1.1
        front = -4.5 + k * 2.6
        depth = 4.5 - front
        tiers.append(rounded_box(STAND_WIDTH, top, depth, 0.1, 3).translate(0, top / 2, front + depth / 2))
        seats.append(rounded_box(STAND_WIDTH - 0.8, 0.2, 1.0, 0.06, 3).translate(0, top + 0.1, front + 1.0))
        for i in range(7):
            x = -half + 1.9 + i * (STAND_WIDTH - 3.8) / 6 + (0.45 if k % 2 else -0.45)
            shirt, head = fan(x, top + 0.2, front + 1.05, (i + k) % 3 != 1, seed)
            seed += 1
            fans[names[(i * 2 + k) % 3]].append(shirt)
            heads.append(head)
    back = rounded_box(STAND_WIDTH, 5.8, 0.3, 0.08, 3).translate(0, 2.9, 4.45)
    # The awning: striped panels sloping from the back wall down toward the front, on four posts.
    back_y, front_y, back_z, front_z = 6.7, 5.3, 4.6, -3.2
    slope = math.degrees(math.atan2(back_y - front_y, back_z - front_z))
    length = math.hypot(back_y - front_y, back_z - front_z)
    stripes = {"AwningA": [], "AwningB": []}
    panels = 8
    for i in range(panels):
        width = STAND_WIDTH / panels
        x = -half + width * (i + 0.5)
        panel = rounded_box(width + 0.02, 0.16, length, 0.05, 3).rotate("x", slope)
        panel = panel.translate(x, (back_y + front_y) / 2, (back_z + front_z) / 2)
        stripes["AwningA" if i % 2 == 0 else "AwningB"].append(panel)
        # A scalloped valance along the front edge.
        scallop = [(math.cos(a) * width / 2, -math.sin(a) * width * 0.3) for a in np.linspace(0, math.pi, 12)]
        flap = extrude(scallop, 0.12).translate(x, front_y - 0.02, front_z - 0.04)
        stripes["AwningB" if i % 2 == 0 else "AwningA"].append(flap)
    posts = []
    for x in (-half + 0.4, -4.0, 4.0, half - 0.4):
        posts.append(cylinder(0.14, front_y - 1.0, 10).translate(x, 1.0, front_z))
    rail = tube([(-half + 0.3, 1.85, -4.3), (half - 0.3, 1.85, -4.3)], 0.08, 6)
    rail_posts = [cylinder(0.07, 0.85, 6).translate(x, 1.0, -4.3) for x in np.linspace(-half + 0.3, half - 0.3, 9)]
    return {
        "Frame": merge(*tiers, back),
        "Seats": merge(*seats),
        "AwningA": merge(*stripes["AwningA"]),
        "AwningB": merge(*stripes["AwningB"]),
        "Rail": merge(*posts, rail, *rail_posts),
        "Heads": merge(*heads),
        "FansA": merge(*fans["FansA"]),
        "FansB": merge(*fans["FansB"]),
        "FansC": merge(*fans["FansC"]),
    }


PROPS = {
    "MechaMarathonStand": stand,
    "MechaMarathonFlyer": flyer,
    "MechaMarathonPad": pad,
    "MechaMarathonSign": sign,
    "MechaMarathonFlag": flag,
    "MechaMarathonBunting": bunting,
    "MechaMarathonTower": tower,
    "MechaMarathonSkyBalloon": sky_balloon,
}
COLORS = {
    # preview colors only; the game colors pieces by name (World/Props/MechaMarathon.luau)
    "Body": (255, 80, 90),
    "Trim": (205, 210, 222),
    "Visor": (40, 60, 105),
    "Eyes": (150, 240, 255),
    "Cheeks": (255, 150, 170),
    "Accent": (255, 248, 230),
    "Dark": (60, 62, 80),
    "Rotor": (255, 205, 50),
    "Key": (230, 175, 70),
    "Base": (245, 245, 250),
    "Spring": (200, 205, 215),
    "Top": (70, 150, 255),
    "Ring": (255, 255, 255),
    "Post": (250, 250, 250),
    "Board": (255, 255, 255),
    "Frame": (255, 190, 40),
    "Pole": (240, 240, 245),
    "Finial": (255, 205, 60),
    "Pennant": (255, 80, 90),
    "String": (250, 250, 250),
    "FlagsA": (255, 85, 90),
    "FlagsB": (255, 210, 60),
    "FlagsC": (70, 160, 255),
    "Stripes": (240, 60, 70),
    "Gold": (255, 200, 60),
    "StripesA": (255, 90, 90),
    "StripesB": (255, 245, 225),
    "Skirt": (120, 80, 50),
    "Basket": (170, 120, 70),
    "Rope": (150, 120, 90),
    "Burner": (90, 90, 100),
    "Seats": (70, 150, 255),
    "AwningA": (255, 80, 90),
    "AwningB": (255, 250, 240),
    "Rail": (250, 250, 250),
    "Heads": (240, 200, 160),
    "FansA": (255, 205, 50),
    "FansB": (90, 210, 120),
    "FansC": (190, 110, 255),
}
