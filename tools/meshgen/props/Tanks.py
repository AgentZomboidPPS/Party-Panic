"""Meshes for Tanks! (see tools/meshgen/props/README.md). Units are studs, +Y up, base on y = 0,
-Z is the front. Generate with:
    python3 tools/meshgen/generate_meshes.py --only TanksTank,TanksShell,TanksMine,TanksBlock,TanksBrick,TanksBear,TanksBall,TanksRug,TanksCrayon,TanksWindow

The tank's numbers are the game's (src/shared/Logic/TankField.luau): the hull's footprint is
6.4 x 7.6 studs (tracks outside to outside), the turret turns on the hull's center, the barrel sits
at the shells' height (SHELL_Y 3.1) and ends at the muzzle (MUZZLE 5.4 from the center). The shell is
0.9 thick (SHELL_RADIUS 0.45). Keep them in step."""

import math

import numpy as np

from generate_meshes import (
    Mesh,
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
    torus,
    tube,
)

HALF_W, HALF_L = 3.2, 3.8
SHELL_Y, MUZZLE = 3.1, 5.4


def box(sx, sy, sz, r, x=0.0, y=0.0, z=0.0, n=3):
    return rounded_box(sx, sy, sz, r, n).translate(x, y, z)


def cyl_x(radius, length, x=0.0, y=0.0, z=0.0, segments=20, bevel=0.0):
    """A cylinder along X centered on (x, y, z)."""
    return cylinder(radius, length, segments, bevel).translate(0, -length / 2, 0).rotate("z", 90).translate(x, y, z)


def cyl_z(radius, length, x=0.0, y=0.0, z=0.0, segments=20, bevel=0.0):
    """A cylinder along Z centered on (x, y, z)."""
    return cylinder(radius, length, segments, bevel).translate(0, -length / 2, 0).rotate("x", 90).translate(x, y, z)


def ball(radius, x=0.0, y=0.0, z=0.0, rings=10, segments=16):
    return sphere(radius, rings, segments).translate(x, y, z)


def stadium(half_length, radius, steps=10):
    """A flat-sided loop (z, y) for a track: straight top and bottom, round ends; centered."""
    pts = []
    for i in range(steps + 1):
        a = -math.pi / 2 + math.pi * i / steps
        pts.append((half_length - radius + math.cos(a) * radius, math.sin(a) * radius))
    for i in range(steps + 1):
        a = math.pi / 2 + math.pi * i / steps
        pts.append((-(half_length - radius) + math.cos(a) * radius, math.sin(a) * radius))
    return pts


# ---------------------------------------------------------------- the tank


def tank():
    """A chunky toy tank: rubber tracks with silver road wheels, a rounded hull and deck in the
    tank's colour, a dome turret with a white stripe, an open hatch ring, a stubby barrel with a
    muzzle brake, headlights and a star on the engine deck."""
    track_h = 2.1
    tracks, wheels = [], []
    for side in (-1, 1):
        loop = extrude(stadium(HALF_L, track_h / 2), 1.5).rotate("y", -90).translate(side * 2.45, track_h / 2, 0)
        tracks.append(loop)
        # Tread cleats on the round ends and the bottom run (they show at the front and back).
        for i in range(7):
            a = -math.pi / 2 + math.pi * (i + 0.5) / 7
            for end in (-1, 1):
                cz = end * (HALF_L - track_h / 2 + math.cos(a) * (track_h / 2 + 0.02))
                cy = track_h / 2 + math.sin(a) * (track_h / 2 + 0.02)
                cleat = box(1.52, 0.16, 0.34, 0.06, n=1).rotate("x", -math.degrees(a) * end).translate(side * 2.45, cy, cz)
                if cy > 0.12:
                    tracks.append(cleat)
        for z in (-2.45, -0.82, 0.82, 2.45):
            wheels.append(cyl_x(0.72, 0.16, side * 3.14, 1.05, z, 16, 0.04))
            wheels.append(cyl_x(0.3, 0.24, side * 3.12, 1.05, z, 10))
        # Drive sprocket and idler at the ends (a little smaller, toothy rims read as gears).
        for z in (-3.05, 3.05):
            wheels.append(cyl_x(0.55, 0.14, side * 3.13, 1.05, z, 10))

    # Hull: a body between the tracks, a deck over them with a sloped glacis at the front and a
    # raised engine deck at the back.
    body = [
        box(3.7, 1.5, 7.0, 0.45, 0, 1.45, 0),
        box(HALF_W * 2, 0.55, 6.5, 0.24, 0, 2.33, 0.25),
        box(5.6, 0.5, 1.55, 0.22).rotate("x", -24).translate(0, 2.36, -3.2),
        box(4.4, 0.36, 2.0, 0.16, 0, 2.7, 2.4),
    ]
    trim = [
        ball(0.3, -2.25, 2.35, -3.62, 8, 12),
        ball(0.3, 2.25, 2.35, -3.62, 8, 12),
        extrude(star(0.62, 0.26), 0.06).rotate("x", -90).translate(0, 2.88, 2.4),
        # Exhaust stubs at the back.
        cyl_z(0.16, 0.5, -1.5, 2.45, 3.35, 10),
        cyl_z(0.16, 0.5, 1.5, 2.45, 3.35, 10),
    ]

    # Turret: a dome on the hull's center (it turns about the origin).
    dome = lathe(
        [
            (0.0, 2.55),
            (2.0, 2.55),
            (2.08, 2.72),
            (2.1, 3.05),
            (2.03, 3.42),
            (1.82, 3.78),
            (1.45, 4.06),
            (0.98, 4.2),
            (0.0, 4.24),
        ],
        32,
    )
    stripe = torus(2.06, 0.1, 32, 6).translate(0, 2.92, 0)
    # The barrel: a mantlet, the tube at the shells' height and a muzzle brake ending at the muzzle.
    barrel = [
        box(1.5, 1.05, 0.75, 0.28, 0, SHELL_Y, -1.85),
        cyl_z(0.3, MUZZLE - 2.0, 0, SHELL_Y, -(2.0 + MUZZLE) / 2, 16),
        cyl_z(0.42, 0.55, 0, SHELL_Y, -(MUZZLE - 0.275), 16, 0.08),
    ]
    # Hatch: the ring the driver stands in, its lid flipped open behind, and a whip antenna.
    hatch = [
        torus(0.98, 0.13, 28, 8).translate(0, 4.22, 0),
        cylinder(0.8, 0.14, 18, 0.04).rotate("x", 150).translate(0, 4.32, 1.55),
        tube([(-1.25, 3.7, 1.15), (-1.3, 4.6, 1.25), (-1.38, 5.55, 1.4)], 0.06, 6),
        ball(0.16, -1.38, 5.6, 1.4, 6, 10),
    ]
    return {
        "Tracks": merge(*tracks),
        "Wheels": merge(*wheels),
        "Body": merge(*body),
        "Trim": merge(*trim),
        "Turret": dome,
        "Badge": stripe,
        "Barrel": merge(*barrel),
        "Hatch": merge(*hatch),
    }


def shell():
    """A stubby toy shell, nose to -Z, 0.9 thick."""
    profile = [(0.0, 0.0), (0.4, 0.0), (0.45, 0.08), (0.45, 0.95), (0.4, 1.3), (0.26, 1.58), (0.0, 1.75)]
    return {"Shell": lathe(profile, 18).rotate("x", -90).translate(0, 0.45, 0.875)}


def mine():
    """A squat dome mine with a coloured band and a light on top."""
    body = lathe([(0.0, 0.0), (1.3, 0.0), (1.32, 0.2), (1.18, 0.42), (0.86, 0.6), (0.45, 0.68), (0.0, 0.7)], 28)
    bolts = [ball(0.11, math.cos(a) * 0.98, 0.5, math.sin(a) * 0.98, 6, 8) for a in np.linspace(0, 2 * math.pi, 7)[:-1]]
    band = torus(1.27, 0.11, 32, 8).translate(0, 0.2, 0)
    light = merge(cylinder(0.24, 0.12, 12).translate(0, 0.64, 0), ball(0.24, 0, 0.8, 0, 8, 12))
    return {"Body": merge(body, *bolts), "Band": band, "Light": light}


# ---------------------------------------------------------------- the play room


def block():
    """A wooden toy block, 8 studs a side, with rounded edges and tree rings on top."""
    wood = box(8, 8, 8, 0.6, 0, 4, 0, 5)
    grain = []
    for radius in (0.8, 1.7, 2.5):
        grain.append(torus(radius, 0.08, 36, 6).scale(1, 0.45, 1).translate(0.7, 8.0, -0.5))
    for side in range(4):
        for k, offset in enumerate((-2.2, -0.4, 1.9)):
            strip = box(0.14, 6.2 - k * 0.8, 0.06, 0.03, offset, 4 + (k - 1) * 0.3, -4.0)
            grain.append(strip.rotate("y", 90 * side))
    return {"Wood": wood, "Grain": merge(*grain)}


def brick():
    """A chunky toy brick with four studs on top (low cover)."""
    body = box(7.8, 3.6, 7.8, 0.3, 0, 1.8, 0, 4)
    studs = [cylinder(1.1, 0.75, 24, 0.12).translate(x, 3.55, z) for x in (-1.95, 1.95) for z in (-1.95, 1.95)]
    return {"Plastic": merge(body, *studs)}


def bear():
    """A giant teddy bear sitting on the floor, facing -Z."""

    def fur(p):
        body = sd_ellipsoid(p, (0, 10.5, 0), (8.6, 10.5, 7.6))
        head = sd_ellipsoid(p, (0, 25.5, -0.8), (7.6, 7.0, 7.0))
        d = smin(body, head, 2.5)
        for side in (-1, 1):
            ear = sd_ellipsoid(p, (side * 5.6, 31.0, -0.2), (2.8, 2.8, 1.6))
            arm = sd_capsule(p, (side * 6.6, 17.0, -1.0), (side * 9.6, 9.0, -5.0), 2.6)
            leg = sd_capsule(p, (side * 4.6, 4.6, -2.0), (side * 6.0, 3.6, -10.5), 3.3)
            foot = sd_ellipsoid(p, (side * 6.0, 3.8, -11.4), (3.2, 3.6, 2.0))
            d = smin(d, ear, 1.2)
            d = smin(d, arm, 1.8)
            d = smin(d, leg, 2.0)
            d = smin(d, foot, 1.2)
        return np.maximum(d, -p[..., 1])  # flat on the floor

    def muzzle(p):
        snout = sd_ellipsoid(p, (0, 23.4, -7.0), (3.4, 2.5, 2.3))
        belly = sd_ellipsoid(p, (0, 10.5, -6.5), (5.4, 6.6, 1.7))
        d = np.minimum(snout, belly)
        for side in (-1, 1):
            pad = sd_ellipsoid(p, (side * 6.0, 3.8, -13.2), (2.2, 2.6, 0.6))
            inner = sd_ellipsoid(p, (side * 5.6, 31.0, -1.5), (1.6, 1.6, 0.5))
            d = np.minimum(d, np.minimum(pad, inner))
        return d

    def bow(p):
        knot = sd_ellipsoid(p, (0, 19.2, -6.6), (1.2, 1.1, 0.9))
        d = knot
        for side in (-1, 1):
            lobe = sd_ellipsoid(p, (side * 2.6, 19.4, -6.2), (2.4, 1.6, 0.8))
            d = smin(d, lobe, 0.5)
        return d

    pieces = {
        "Fur": sdf_mesh(fur, (-14, 0, -16), (14, 35, 10), 0.85),
        "Muzzle": sdf_mesh(muzzle, (-9, 0, -15), (9, 34, -3), 0.5),
        "Bow": sdf_mesh(bow, (-6, 16, -9), (6, 22, -4), 0.3),
    }
    eyes = [ball(0.95, side * 2.7, 27.0, -6.75, 8, 12) for side in (-1, 1)]
    nose = sphere(1.0, 8, 12).scale(1.3, 0.9, 0.8).translate(0, 24.6, -9.25)
    pieces["Eyes"] = merge(*eyes, nose)
    return pieces


def beach_ball():
    """A beach ball: six coloured gores and white caps."""
    radius = 8.0
    colors = ["Red", "White", "Yellow", "White", "Blue", "White"]
    pieces = {}
    rings, per_gore = 16, 8
    top = math.radians(72)
    for g, name in enumerate(colors):
        verts, faces = [], []
        a0 = 2 * math.pi * g / 6
        for i in range(rings + 1):
            lat = -top + 2 * top * i / rings
            for j in range(per_gore + 1):
                lon = a0 + 2 * math.pi / 6 * j / per_gore
                verts.append((math.cos(lat) * math.cos(lon) * radius, radius + math.sin(lat) * radius, math.cos(lat) * math.sin(lon) * radius))
        for i in range(rings):
            for j in range(per_gore):
                a = i * (per_gore + 1) + j
                b, c, d = a + 1, a + per_gore + 1, a + per_gore + 2
                for tri in ((a, c, b), (b, c, d)):
                    pa, pb, pc = (np.array(verts[t]) - np.array((0, radius, 0)) for t in tri)
                    if np.dot(np.cross(pb - pa, pc - pa), pa) < 0:
                        tri = (tri[0], tri[2], tri[1])
                    faces.append(tri)
        mesh = Mesh(verts, faces)
        pieces[name] = merge(pieces[name], mesh) if name in pieces else mesh
    cap_profile = [(math.cos(math.radians(a)) * 8.03, math.sin(math.radians(a)) * 8.03) for a in range(66, 91, 4)]
    cap = lathe([(r, y) for r, y in cap_profile] + [(0.0, 8.03)], 36)
    caps = merge(cap.copy().translate(0, radius, 0), cap.copy().scale(1, -1, 1).translate(0, radius, 0))
    caps.f = caps.f.copy()
    valve = cylinder(0.45, 0.5, 12, 0.1).rotate("z", 90).translate(8.0, radius, 0)
    pieces["White"] = merge(pieces["White"], caps, valve)
    return pieces


def rug():
    """A round braided rug: rings of three colours with a braided (bumpy) top."""
    names = ["Outer", "Middle", "Inner"]
    bands = {name: [] for name in names}
    width = 2.2
    count = 10
    for k in range(count):
        r0, r1 = 0.6 + k * width, 0.6 + (k + 1) * width
        profile = [(r0, 0.0), (r1, 0.0), (r1, 0.22)]
        for b in range(1, 6):
            t = b / 6
            r = r1 + (r0 - r1) * t
            profile.append((r, 0.22 + 0.2 * math.sin(math.pi * t * 3) ** 2))
        profile += [(r0, 0.22), (r0, 0.0)]
        bands[names[(count - 1 - k) % 3]].append(lathe(profile, max(20, int(2 * math.pi * r1 / 1.8))))
    hub = cylinder(0.65, 0.4, 16)
    bands["Inner"].append(hub)
    return {name: merge(*meshes) for name, meshes in bands.items()}


def crayon():
    """A giant wax crayon lying on the floor, tip to -Z."""
    wax = lathe([(0.0, 0.0), (0.88, 0.0), (0.88, 13.0), (0.7, 13.6), (0.3, 15.6), (0.16, 15.9), (0.0, 15.95)], 20)
    wrapper = merge(
        lathe([(0.93, 1.2), (0.93, 11.2)], 20),
        lathe([(0.0, 1.2), (0.93, 1.2)], 20),
    )
    wrapper = lathe([(0.0, 1.2), (0.95, 1.2), (0.95, 11.2), (0.0, 11.2)], 20)
    lay = 0.95
    return {
        "Wax": wax.rotate("x", -90).translate(0, lay, 8.0),
        "Wrapper": wrapper.rotate("x", -90).translate(0, lay, 8.0),
    }


def window():
    """A big window with a white frame, sky-blue panes with painted clouds, a sill and pleated
    curtains on a rod. Faces -Z (into the room)."""
    w, h, bottom = 44.0, 36.0, 4.0
    cy = bottom + h / 2
    frame = [
        box(w, 2.2, 1.6, 0.4, 0, bottom + 1.1, 0),
        box(w, 2.2, 1.6, 0.4, 0, bottom + h - 1.1, 0),
        box(2.2, h, 1.6, 0.4, -w / 2 + 1.1, cy, 0),
        box(2.2, h, 1.6, 0.4, w / 2 - 1.1, cy, 0),
        box(1.2, h - 2, 1.2, 0.25, 0, cy, 0),
        box(w - 2, 1.2, 1.2, 0.25, 0, cy, 0),
        box(w + 4, 1.2, 3.4, 0.4, 0, bottom - 0.4, -0.9),
    ]
    glass = box(w - 2.6, h - 2.6, 0.3, 0.1, 0, cy, 0.2)
    clouds = []
    for cx, cyy, s in ((-12, cy + 8, 1.0), (10, cy + 10, 0.8), (6, cy - 7, 0.9), (-9, cy - 9, 0.7)):
        for dx, dy, r in ((-2.2, 0, 1.8), (0, 0.9, 2.4), (2.3, 0.1, 1.9), (0.4, -0.6, 1.9)):
            clouds.append(sphere(r * s, 8, 12).scale(1, 0.8, 0.18).translate(cx + dx * s, cyy + dy * s, 0.0))
    curtains = []
    for side in (-1, 1):
        for k in range(5):
            x = side * (w / 2 + 1.0 - k * 1.9)
            curtains.append(cylinder(1.25, h + 7.0, 12).translate(x, bottom - 3.0, -2.2 - (k % 2) * 0.5))
    rod = [cyl_x(0.45, w + 16, 0, bottom + h + 4.5, -2.4, 12), ball(0.9, -(w / 2 + 8.5), bottom + h + 4.5, -2.4), ball(0.9, w / 2 + 8.5, bottom + h + 4.5, -2.4)]
    return {"Frame": merge(*frame, *rod), "Glass": glass, "Cloud": merge(*clouds), "Curtain": merge(*curtains)}


PROPS = {
    "TanksTank": tank,
    "TanksShell": shell,
    "TanksMine": mine,
    "TanksBlock": block,
    "TanksBrick": brick,
    "TanksBear": bear,
    "TanksBall": beach_ball,
    "TanksRug": rug,
    "TanksCrayon": crayon,
    "TanksWindow": window,
}
COLORS = {
    "Tracks": (52, 50, 56),
    "Wheels": (190, 192, 200),
    "Body": (232, 64, 58),
    "Trim": (250, 238, 205),
    "Turret": (232, 64, 58),
    "Badge": (250, 250, 245),
    "Barrel": (88, 92, 104),
    "Hatch": (70, 72, 80),
    "Shell": (70, 72, 84),
    "Band": (250, 205, 50),
    "Light": (230, 40, 40),
    "Wood": (232, 196, 140),
    "Grain": (196, 150, 96),
    "Plastic": (225, 60, 55),
    "Fur": (176, 112, 62),
    "Muzzle": (240, 214, 170),
    "Bow": (220, 50, 70),
    "Eyes": (30, 24, 22),
    "Red": (235, 60, 60),
    "White": (250, 250, 245),
    "Yellow": (250, 210, 60),
    "Blue": (60, 130, 235),
    "Outer": (120, 170, 220),
    "Middle": (250, 235, 200),
    "Inner": (240, 130, 120),
    "Wax": (235, 70, 60),
    "Wrapper": (245, 140, 130),
    "Frame": (250, 250, 245),
    "Glass": (170, 220, 255),
    "Cloud": (255, 255, 255),
    "Curtain": (255, 214, 120),
}
