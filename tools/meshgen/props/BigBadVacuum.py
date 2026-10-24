"""Meshes for Big Bad Vacuum (see tools/meshgen/props/README.md): the boss, a squat robot vacuum with a
cyclops eye in a chrome socket, heavy brows, a toothy intake, a clamshell hatch over its glowing core, side
vents, a siren, a handle and two spinning side brushes; its brush arm, dust bag, power cord and plug; the
toy bricks (carried, thrown, piled); the giant toy blocks of the arena wall; and the living room beyond
it (a floor lamp, a TV and a couch).

    python3 tools/meshgen/generate_meshes.py --only BigBadVacuumBody,BigBadVacuumBrush,BigBadVacuumBag,BigBadVacuumCordLink,BigBadVacuumPlug,BigBadVacuumBrick,BigBadVacuumPile,BigBadVacuumDebris,BigBadVacuumBlock,BigBadVacuumLamp,BigBadVacuumTV,BigBadVacuumCouch

Units are studs, +Y up, base on y = 0, -Z is the front. Piece names are the part names the game uses
(src/server/World/Props/BigBadVacuum.luau colours them; src/client/MiniGames/BigBadVacuum.luau moves
some of them), and each prop is as tall as that file's Height, so nothing is rescaled on import:
- the boss: Iris and Pupil slide across the eye (up to 0.6 and 1.1 studs), the brows drop 0.35, FlapL and
  FlapR slide 4.2 out along X (onto the deck), the Orb is resized to 4.2-5.1 studs about its centre, and
  each side brush (SideBrushL + BristlesL, SideBrushR + BristlesR) spins about its own centre;
- the brush arm: the client sets Boom to 3 x 1.8 x (21 x extension) and BoomTop to 1.6 x 0.5 x (19 x
  extension), so those two are boxes of exactly that size; Head and Bristles spin about their centre.
"""

import math

import numpy as np

from generate_meshes import Mesh, cylinder, extrude, icosphere, lathe, merge, organic_lathe, rounded_box, sphere, star, taper, torus


# ------------------------------------------------------------------------------------- helpers

def rbox(sx, sy, sz, r, x=0.0, y=0.0, z=0.0, n=4) -> Mesh:
    """A rounded box centred on (x, y, z)."""
    return rounded_box(sx, sy, sz, r, n).translate(x, y, z)


def post(radius, y0, y1, x=0.0, z=0.0, bevel=0.0, segments=24) -> Mesh:
    """An upright cylinder from y0 to y1."""
    return cylinder(radius, y1 - y0, segments, bevel).translate(x, y0, z)


def zdisc(radius, thickness, front, x=0.0, y=0.0, bevel=0.0, segments=40) -> Mesh:
    """A disc facing -Z whose front face is at z = front."""
    return cylinder(radius, thickness, segments, bevel).rotate("x", 90).translate(x, y, front)


def xbar(radius, length, x=0.0, y=0.0, z=0.0, bevel=0.0, segments=20) -> Mesh:
    """A cylinder along X centred on (x, y, z)."""
    return cylinder(radius, length, segments, bevel).translate(0, -length / 2, 0).rotate("z", 90).translate(x, y, z)


def rrect(r0, r1, y0, y1, c, n=4) -> list:
    """A rounded rectangle in the (radius, y) plane, as a closed convex loop."""
    points = []
    for cx, cy, a0 in ((r1 - c, y0 + c, -90), (r1 - c, y1 - c, 0), (r0 + c, y1 - c, 90), (r0 + c, y0 + c, 180)):
        for k in range(n + 1):
            a = math.radians(a0 + 90 * k / n)
            points.append((cx + c * math.cos(a), cy + c * math.sin(a)))
    return points


def arc_lathe(loop, a0, a1, segments=48) -> Mesh:
    """Revolves a closed convex (radius, y) loop round the Y axis from angle a0 to a1 (degrees; 0 is +X,
    90 is +Z, the back), capped flat at both ends."""
    n = len(loop)
    angles = np.radians(np.linspace(a0, a1, segments + 1))
    verts, faces = [], []
    for a in angles:
        for r, y in loop:
            verts.append((math.cos(a) * r, y, math.sin(a) * r))
    for i in range(segments):
        for j in range(n):
            a = i * n + j
            b = i * n + (j + 1) % n
            faces += [(a, a + n, b), (b, a + n, b + n)]
    cr = sum(r for r, _ in loop) / n
    cy = sum(y for _, y in loop) / n
    for index in (0, segments):
        a = angles[index]
        base = len(verts)
        verts += [(math.cos(a) * r, y, math.sin(a) * r) for r, y in loop]  # (own corners: a crisp edge)
        verts.append((math.cos(a) * cr, cy, math.sin(a) * cr))
        faces += [(base + n, base + j, base + (j + 1) % n) for j in range(n)]
    return Mesh(verts, faces)


def orient(mesh: Mesh, origin, right, up, back) -> Mesh:
    """Places a mesh built in its own axes (x right, y up, z back) at origin with the given axes."""
    v = mesh.v
    o, r, u, b = (np.asarray(a, float) for a in (origin, right, up, back))
    mesh.v = o + v[:, 0:1] * r + v[:, 1:2] * u + v[:, 2:3] * b
    return mesh


def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


def on_wall(mesh: Mesh, angle_deg, radius, y, tilt_deg=0.0) -> Mesh:
    """Places a mesh built facing -Z onto a round wall: at `angle_deg` round the Y axis, `radius` out, at
    height y, its front facing out, leaned back by tilt_deg (for a sloping shoulder)."""
    a = math.radians(angle_deg)
    out = np.array([math.cos(a), 0.0, math.sin(a)])
    side = np.array([-math.sin(a), 0.0, math.cos(a)])
    t = math.radians(tilt_deg)
    normal = out * math.cos(t) + np.array([0, 1.0, 0]) * math.sin(t)
    up = np.cross(normal, side)
    up = up if up[1] > 0 else -up
    right = np.cross(up, -normal)
    return orient(mesh, out * radius + np.array([0, y, 0]), right, up, -normal)


def faceted(mesh: Mesh) -> Mesh:
    mesh.smooth = False
    return mesh


def ellipse_arc(cx, cy, rx, ry, a0, a1, n):
    return [(cx + rx * math.cos(math.radians(a0 + (a1 - a0) * k / n)), cy + ry * math.sin(math.radians(a0 + (a1 - a0) * k / n))) for k in range(n + 1)]


# ------------------------------------------------------------------------------------- the boss

FRONT_GAP = 38.4  # the bumper and stripe stop this many degrees either side of the front, for the mouth
HULL_PROFILE = [(0, 4.4), (12.0, 4.4), (12.2, 4.9), (12.15, 7.0), (11.9, 9.0), (11.6, 10.4)] + \
    ellipse_arc(8.2, 10.4, 3.4, 3.7, 0, 90, 10)[1:] + [(6.0, 14.1), (0, 14.1)]


def hull_radius(y: float) -> float:
    """The hull's radius at height y (from HULL_PROFILE)."""
    side = HULL_PROFILE[1:-1]
    for (r0, y0), (r1, y1) in zip(side, side[1:]):
        if y0 <= y <= y1 and y1 > y0:
            return r0 + (r1 - r0) * (y - y0) / (y1 - y0)
    return side[-1][0]


EYE_Y = 9.4


def body():
    pieces = {}
    pieces["Hull"] = lathe(HULL_PROFILE, 72)
    # (with struts out to the side brushes, 45 degrees from the front)
    struts = []
    for s in (-1, 1):
        strut = rbox(1.8, 0.8, 4.6, 0.35).rotate("y", s * -45).translate(s * 9.3, 1.0, -9.3)
        struts.append(strut)
    pieces["Skirt"] = merge(post(11.0, 0.0, 1.4, bevel=0.35, segments=64), *struts)
    pieces["Base"] = post(12.6, 1.1, 4.6, bevel=0.6, segments=72)
    bumper_loop = rrect(12.35, 13.7, 1.3, 3.9, 0.55)
    pieces["Bumper"] = arc_lathe(bumper_loop, -90 + FRONT_GAP, 270 - FRONT_GAP, 72)

    # Caution chevrons on the bumper's face.
    hazard = []
    span = 360 - 2 * FRONT_GAP
    count = 18
    for k in range(count):
        angle = -90 + FRONT_GAP + span * (k + 0.5) / count
        tilt = 30 if k % 2 == 0 else -30
        slab = rbox(0.9, 2.3, 0.22, 0.08, n=2).rotate("z", tilt)
        hazard.append(on_wall(slab, angle, 13.78, 2.6))
    pieces["Hazard"] = merge(*hazard)

    # A glowing band round the hull above the base, and a ring round the deck's edge.
    pieces["Stripe"] = merge(
        arc_lathe(rrect(11.95, 12.45, 5.25, 5.85, 0.2, 2), -90 + FRONT_GAP, 270 - FRONT_GAP, 72),
        torus(8.35, 0.22, 64, 8).translate(0, 14.12, 0),
    )

    # Armour plates on each side, riveted at the corners.
    plates, rivets = [], []
    for centre in (0, 180):
        loop = [(hull_radius(6.4) - 0.3, 6.4), (hull_radius(6.4) + 0.32, 6.4), (hull_radius(10.2) + 0.32, 10.2), (hull_radius(10.2) - 0.3, 10.2)]
        plates.append(arc_lathe(loop, centre - 26, centre + 26, 24))
        for da in (-21, 21):
            for y in (7.0, 9.6):
                a = math.radians(centre + da)
                r = hull_radius(y) + 0.38
                rivets.append(sphere(0.32, 4, 8).translate(math.cos(a) * r, y, math.sin(a) * r))
    pieces["Plate"] = merge(*plates)
    # ... and a ring of rivets on the deck round the hatch.
    for k in range(10):
        a = 2 * math.pi * (k + 0.5) / 10
        rivets.append(sphere(0.3, 4, 8).scale(1, 0.6, 1).translate(math.cos(a) * 5.6, 14.12, math.sin(a) * 5.6))
    pieces["Rivet"] = merge(*rivets)

    # The cyclops eye: a chrome socket standing out of the front, the eye, its iris and pupil.
    socket_loop = [(3.55, -8.0), (4.4, -8.0), (4.4, -12.1)] + ellipse_arc(3.975, -12.1, 0.425, 0.7, 0, 180, 8)[1:]
    socket = lathe(socket_loop, 48)  # (built round Y, then Y swapped for Z: the lip faces forward)
    socket.v = np.stack([socket.v[:, 0], socket.v[:, 2], socket.v[:, 1]], axis=1)
    pieces["EyeRing"] = socket.translate(0, EYE_Y, 0)
    pieces["Eye"] = zdisc(3.6, 3.2, -12.5, 0, EYE_Y, bevel=0.15, segments=48)
    pieces["Iris"] = zdisc(2.25, 0.3, -12.78, 0, EYE_Y, bevel=0.08, segments=40)
    pieces["Pupil"] = zdisc(1.1, 0.25, -12.98, 0, EYE_Y, bevel=0.07, segments=32)

    # Heavy brows, angled into a scowl.
    for name, side in (("BrowL", -1), ("BrowR", 1)):
        brow = rbox(5.4, 1.35, 2.2, 0.5).rotate("z", 22 if side > 0 else -22)
        pieces[name] = brow.translate(side * 2.75, 14.55, -12.0)

    # The toothy intake under the eye, cut into the bumper.
    pieces["Mouth"] = rbox(15.6, 4.0, 3.4, 1.1, 0, 3.0, -12.5)
    pieces["Throat"] = rbox(13.6, 2.6, 0.5, 0.22, 0, 3.0, -14.2)
    teeth = []
    for k in range(-3, 4):
        tooth = extrude([(-0.72, 0), (0.72, 0), (0, -1.25)], 0.6)
        teeth.append(tooth.translate(k * 1.9, 4.3, -14.45))
    for k in range(-3, 3):
        tooth = extrude([(-0.6, 0), (0.6, 0), (0, 1.0)], 0.6)
        teeth.append(tooth.translate((k + 0.5) * 1.9, 1.7, -14.45))
    pieces["Teeth"] = merge(*teeth)

    # The hatch: a gold rim on the deck, the dark well, the core, and two half-domes that slide apart.
    pieces["CoreRim"] = arc_lathe(rrect(3.6, 4.65, 13.95, 14.85, 0.3, 3), 0, 360, 48)
    pieces["CoreWell"] = post(3.6, 13.9, 14.4, bevel=0.1, segments=40)
    pieces["Orb"] = sphere(2.1, 16, 28).translate(0, 14.6, 0)
    dome = [(0, 14.85), (4.35, 14.85)] + ellipse_arc(0, 14.85, 4.35, 2.3, 0, 90, 12)[1:]
    pieces["FlapL"] = arc_lathe(dome, 90, 270, 28).translate(-0.06, 0, 0)
    pieces["FlapR"] = arc_lathe(dome, -90, 90, 28).translate(0.06, 0, 0)

    # Vents on the back shoulders (two each side), glowing with its mood.
    vents, glows = [], []
    t_mid = 48
    vent_r = 8.2 + 3.4 * math.cos(math.radians(t_mid)) + 0.05
    vent_y = 10.4 + 3.7 * math.sin(math.radians(t_mid))
    for angle in (38, 54, 126, 142):
        vents.append(on_wall(rbox(2.6, 2.2, 0.5, 0.2, n=3), angle, vent_r, vent_y, tilt_deg=40))
        for k in (-0.6, 0, 0.6):
            glows.append(on_wall(rbox(2.0, 0.28, 0.3, 0.1, 0, k, -0.25, n=2), angle, vent_r, vent_y, tilt_deg=40))
    pieces["Vent"] = merge(*vents)
    pieces["VentGlow"] = merge(*glows)

    # A siren on a post, at the back of the deck (clear of the hatch's open flaps).
    sx, sz = 5.0, 6.2
    pieces["SirenPost"] = merge(
        post(0.95, 13.9, 14.5, sx, sz, bevel=0.15),
        post(0.42, 14.4, 16.2, sx, sz, segments=16),
        post(1.3, 16.1, 16.55, sx, sz, bevel=0.12),
    )
    pieces["Siren"] = lathe([(0, 16.5), (1.15, 16.5), (1.15, 17.4)] + ellipse_arc(0, 17.4, 1.15, 1.35, 0, 90, 8)[1:], 28).translate(sx, 0, sz)

    # The handle the dust bag hangs from: a U of tube up the back, bolted on.
    left = [(-4.2, 9.0, 10.8), (-4.2, 11.0, 11.4), (-4.2, 17.6, 11.4)]
    corner = [(-4.2 + 1.2 * (1 - math.cos(math.radians(a))), 17.6 + 1.8 * math.sin(math.radians(a)), 11.4) for a in (25, 50, 75)]
    top = [(-2.0, 19.4, 11.4), (2.0, 19.4, 11.4)]
    path = left + corner + top + [(-x, y, z) for x, y, z in reversed(corner)] + [(-x, y, z) for x, y, z in reversed(left)]
    handle = taper(path, 0.8, 0.8, 14)
    grips = [xbar(0.86, 0.5, gx, 19.4, 11.4, bevel=0.15) for gx in (-1.4, 1.4)]
    brackets = [rbox(2.2, 1.6, 1.2, 0.3, x, 9.6, 10.9) for x in (-4.2, 4.2)]
    pieces["Handle"] = merge(handle, *grips)
    pieces["Plate"] = merge(pieces["Plate"], *brackets)

    # The side brushes at the front corners: a red hub and a star of bristle tufts each.
    for side, hub_name, tuft_name in ((-1, "SideBrushL", "BristlesL"), (1, "SideBrushR", "BristlesR")):
        cx, cz = side * 10.4, -10.4
        hub = lathe([(0, 0.85), (1.45, 0.85), (1.6, 1.25), (1.35, 1.85), (0.7, 2.25), (0, 2.35)], 28)
        pieces[hub_name] = hub.translate(cx, 0, cz)
        tufts = []
        for k in range(6):
            a = math.radians(k * 60 + 15)
            out = np.array([math.cos(a), 0, math.sin(a)])
            root = np.array([cx, 1.35, cz]) + out * 0.8
            tip = np.array([cx, 0.25, cz]) + out * 4.2
            mid = (root + tip) / 2 + np.array([0, 0.12, 0])
            tufts.append(taper([tuple(root), tuple(mid), tuple(tip)], 0.42, 0.16, 8))
        pieces[tuft_name] = merge(*tufts)
    return pieces


# ------------------------------------------------------------------------------------- its tools

def brush():
    hub = merge(post(2.5, 0.0, 2.0, bevel=0.35, segments=36), post(1.2, 1.9, 2.4, bevel=0.12, segments=20))
    boom = rbox(3.0, 1.8, 21.0, 0.6, 0, 1.7, -16.5)
    boom_top = rbox(1.6, 0.5, 19.0, 0.22, 0, 2.8, -16.5)
    head = lathe([(0, 1.0), (3.6, 1.0), (4.0, 1.4), (4.0, 2.2), (3.4, 2.75), (1.0, 2.85), (0, 2.85)], 40)
    tufts = []
    for k in range(12):
        a = math.radians(k * 30)
        out = np.array([math.cos(a), 0, math.sin(a)])
        root = out * 2.4 + np.array([0, 1.15, 0])
        tip = out * 4.7 + np.array([0, 0.3, 0])
        tufts.append(taper([tuple(root), tuple(tip)], 0.5, 0.25, 8))
    bristles = merge(*tufts).translate(0, 0, -27)
    return {
        "Boom": boom,
        "Hub": hub,
        "BoomTop": boom_top,
        "Head": head.translate(0, 0, -27),
        "Bristles": bristles,
    }


def bag():
    profile = [(0, 1.4), (3.1, 1.4), (4.4, 2.5), (6.0, 4.4), (6.95, 6.9), (7.0, 8.6), (6.6, 10.6), (5.6, 12.4), (3.9, 13.7), (2.0, 14.2), (0, 14.3)]
    sack = organic_lathe(profile, 48, 0.035, waves=7, seed=4)
    collar = merge(
        arc_lathe(rrect(2.7, 3.75, 0.0, 1.65, 0.3), 0, 360, 40),
        rbox(1.2, 1.1, 0.9, 0.25, 0, 0.82, -3.85),  # the clamp's screw
    )
    return {"Bag": sack, "Collar": collar}


def cord_link():
    cord = cylinder(0.9, 2.6, 18, 0.45).translate(0, -1.3, 0).rotate("z", 90).translate(0, 1.1, 0)
    band = xbar(1.1, 0.5, 0, 1.1, 0, bevel=0.12)
    return {"Cord": cord, "Band": band}


def plug():
    body = merge(
        rbox(6.0, 4.1, 4.6, 1.1, 0, 2.85, 0),
        *[rbox(0.5, 3.3, 3.8, 0.22, s * 3.0, 2.95, 0) for s in (-1, 1)],  # grip pads
        lathe([(0, 0), (1.5, 0), (1.6, 0.4), (2.0, 0.85), (0, 0.85)], 24),  # where the cord goes in
    )
    ridges = [rbox(6.2, 0.35, 4.8, 0.15, 0, y, 0) for y in (1.6, 2.3, 3.0)]
    prongs = []
    for x in (-1.5, 1.5):
        blade = rbox(0.42, 1.9, 1.5, 0.12, x, 5.5, 0)
        prongs.append(blade)
    glow = rbox(3.6, 0.22, 2.8, 0.1, 0, 4.92, 0)
    return {"Plug": merge(body, *ridges), "Prong": merge(*prongs), "Glow": glow}


# ------------------------------------------------------------------------------------- toy bricks

def toy_brick(x, y, z, turn, sx=3.4, sy=1.9, sz=2.0, stud=0.5, stud_h=0.5) -> Mesh:
    brick = rbox(sx, sy, sz, 0.18, 0, sy / 2, 0, n=3)
    studs = [post(stud, sy - 0.02, sy + stud_h, dx, 0, bevel=0.1, segments=18) for dx in (-0.8, 0.8)]
    return merge(brick, *studs).rotate("y", turn).translate(x, y, z)


def brick():
    body = rbox(3.4, 1.9, 2.0, 0.2, 0, 0.95, 0)
    studs = merge(*[post(0.5, 1.88, 2.4, dx, 0, bevel=0.1, segments=18) for dx in (-0.8, 0.8)])
    return {"Body": body, "Stud": studs}


def pile():
    h = 1.75
    layout = [
        ("Red", -1.6, 0, 0.4, 14), ("Blue", 1.9, 0, -0.6, -20), ("Yellow", 0.2, 0, -2.6, 70), ("Green", -0.2, 0, 2.6, -80),
        ("Orange", -0.6, h, 0.2, 30), ("Purple", 1.2, h, -0.8, -50), ("Blue", 0.1, 2 * h, -0.2, 8),
    ]
    pieces = {}
    for name, x, y, z, turn in layout:
        mesh = toy_brick(x, y, z, turn, sy=h, stud_h=0.45)
        pieces[name] = merge(pieces[name], mesh) if name in pieces else mesh
    return pieces


def debris():
    chunk = faceted(icosphere(1.0, 1, noise=0.3, seed=9).scale(1.15, 0.72, 0.85).translate(0, 0.72, 0))
    spark = faceted(icosphere(0.45, 0, noise=0.2, seed=2).translate(0.5, 1.45, 0.2))
    return {"Chunk": chunk, "Spark": spark}


# ------------------------------------------------------------------------------------- the room

def block():
    body = rbox(15.0, 15.2, 14.0, 0.9, 0, 7.6, 0, n=8)
    studs = [post(1.7, 15.1, 15.8, x, z, bevel=0.2, segments=28) for x in (-3.4, 3.4) for z in (-3.0, 3.0)]
    panel = rbox(10.6, 10.6, 0.9, 0.45, 0, 7.6, -7.0, n=7)
    emblem = extrude(star(3.6, 1.55, 5), 0.6).translate(0, 7.4, -7.55)
    # (the star is a piece of its own, tinted lighter than the panel: one the panel's colour only showed
    # by its shading, and from below, as the stacked row is seen, it read as a squinting face)
    return {"Body": merge(body, *studs), "Face": panel, "Emblem": emblem}


def lamp():
    foot = lathe([(0, 0), (6.0, 0), (6.1, 0.5), (5.4, 1.3), (2.0, 1.75), (1.2, 2.4), (0, 2.5)], 48)
    pole = merge(
        post(0.85, 2.3, 33.4, segments=20),
        sphere(1.35, 10, 18).translate(0, 18.0, 0),
        post(1.3, 31.8, 33.6, bevel=0.3, segments=24),
    )
    shade = lathe([(0, 33.2), (10.6, 33.2), (10.8, 33.8), (7.6, 46.4), (7.3, 47.0), (0, 47.0)], 56)
    return {"Foot": foot, "Pole": pole, "Shade": shade}


def tv():
    stand = merge(
        rbox(24.0, 1.2, 10.0, 0.5, 0, 0.6, 0.5),
        rbox(4.2, 4.6, 2.2, 0.6, 0, 3.0, 1.4),
    )
    frame = merge(
        rbox(56.0, 31.0, 2.6, 1.1, 0, 20.5, 0),
        rbox(40.0, 19.0, 2.4, 2.0, 0, 21.0, 2.0),  # the back
    )
    screen = rbox(52.4, 27.4, 0.3, 0.12, 0, 20.8, -1.4)
    return {"Stand": stand, "Frame": frame, "Screen": screen}


def couch():
    legs = []
    for x in (-38, 38):
        for z in (-10, 10):
            legs.append(lathe([(0, 0), (1.1, 0), (1.5, 2.6), (0, 2.6)], 16).translate(x, 0, z))
    seat = rbox(72.0, 9.0, 26.0, 2.2, 0, 7.0, 0)
    back = rbox(72.0, 22.0, 8.0, 3.2, 0, 20.0, 9.0)
    arms = []
    for s in (-1, 1):
        arms.append(rbox(9.0, 15.5, 26.0, 3.0, s * 40, 10.25, 0))
        roll = cylinder(4.8, 26.0, 28, 2.0).rotate("x", 90).translate(s * 40.4, 18.0, -13.0)
        arms.append(roll)
    cushions = []
    for x in (-17.8, 17.8):
        cushions.append(rbox(35.0, 5.6, 21.5, 2.6, x, 14.0, -2.6))
        back_cushion = rbox(34.5, 15.0, 6.0, 2.6).rotate("x", -10).translate(x, 22.6, 3.6)
        cushions.append(back_cushion)
    return {"Leg": merge(*legs), "Seat": seat, "Back": back, "Arm": merge(*arms), "Cushion": merge(*cushions)}


PROPS = {
    "BigBadVacuumBody": body,
    "BigBadVacuumBrush": brush,
    "BigBadVacuumBag": bag,
    "BigBadVacuumCordLink": cord_link,
    "BigBadVacuumPlug": plug,
    "BigBadVacuumBrick": brick,
    "BigBadVacuumPile": pile,
    "BigBadVacuumDebris": debris,
    "BigBadVacuumBlock": block,
    "BigBadVacuumLamp": lamp,
    "BigBadVacuumTV": tv,
    "BigBadVacuumCouch": couch,
}

COLORS = {  # preview colours only (the game colours pieces by name: Props/BigBadVacuum.luau)
    "Skirt": (24, 24, 30), "Base": (40, 42, 54), "Bumper": (26, 26, 32), "Hazard": (255, 204, 40),
    "Hull": (78, 84, 110), "Stripe": (60, 220, 255), "Plate": (58, 62, 84), "Rivet": (170, 176, 196),
    "EyeRing": (30, 30, 38), "Eye": (255, 70, 60), "Iris": (255, 190, 80), "Pupil": (12, 12, 16),
    "BrowL": (30, 30, 38), "BrowR": (30, 30, 38), "Mouth": (22, 20, 28), "Throat": (8, 6, 12),
    "Teeth": (240, 240, 248), "CoreRim": (255, 196, 60), "CoreWell": (14, 12, 20), "FlapL": (96, 102, 130),
    "FlapR": (96, 102, 130), "Orb": (70, 255, 220), "VentGlow": (255, 120, 40), "Vent": (24, 24, 30),
    "SirenPost": (170, 176, 196), "Siren": (255, 60, 60), "Handle": (255, 90, 90),
    "SideBrushL": (255, 90, 90), "SideBrushR": (255, 90, 90), "BristlesL": (250, 230, 120), "BristlesR": (250, 230, 120),
    "Hub": (255, 196, 60), "Boom": (72, 78, 100), "BoomTop": (255, 90, 90), "Head": (255, 90, 90), "Bristles": (250, 230, 120),
    "Bag": (236, 236, 250), "Collar": (255, 90, 90), "Cord": (250, 250, 244), "Band": (255, 90, 90),
    "Plug": (250, 250, 244), "Prong": (210, 214, 224), "Glow": (255, 230, 90), "Body": (250, 90, 80), "Stud": (250, 120, 110),
    "Red": (232, 76, 84), "Blue": (70, 140, 235), "Yellow": (250, 200, 60), "Green": (86, 200, 120), "Orange": (250, 140, 60),
    "Purple": (160, 110, 230), "Chunk": (78, 84, 110), "Spark": (255, 160, 60), "Face": (240, 130, 136), "Emblem": (250, 206, 208),
    "Pole": (50, 48, 58), "Foot": (36, 34, 44), "Shade": (255, 214, 140), "Frame": (24, 24, 30), "Screen": (70, 130, 255),
    "Stand": (40, 40, 50), "Seat": (120, 40, 60), "Back": (104, 34, 52), "Arm": (96, 30, 48), "Cushion": (140, 52, 72),
    "Leg": (92, 62, 40),
}
