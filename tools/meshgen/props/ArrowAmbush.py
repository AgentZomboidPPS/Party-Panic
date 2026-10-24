"""Meshes for Arrow Ambush, a storybook castle archery tournament: the archers' stone tower (with its
blue-roofed stair turret, banners and painted shields), the cover boards that roll on rails in the
courtyard, the archer's bow and arrow, and the castle and festival around the courtyard (cobbles,
low crenellated walls, corner turrets, a curtain wall, striped tents, banner poles, hay targets).

    python3 tools/meshgen/generate_meshes.py --only ArcherTower,TargetBoard,ArrowAmbushCobbles

Units are studs, +Y is up, the base sits on y = 0 and -Z is the front:
  * ArcherTower: the door looks along -Z (the game turns it to face the courtyard). The deck the
    archers stand on is at y = 16; the game puts an invisible solid core under it. The stair
    turret stands at the back (+Z).
  * TargetBoard: the painted shield and target look along -Z (towards the tower). The board is
    7.2 wide and centered on x = 0, z = 0; its wheels sit on two rails at z = +-0.9. The client
    paints the Shield and the back (Paint) in the board's points color.
  * AmbushBow: held upright, the string towards the archer (+Z), shooting along -Z.
  * AmbushArrow: lies along Z with its head at -Z.
  * ArrowAmbushCobbles: one 10.6 x 10.7 floor tile (5 x 4 of them pave the courtyard).
  * ArrowAmbushWall: an 8.8 long low wall along X (6 make a long side, 5 a short one, scaled).
  * ArrowAmbushCastleWall: a 16 long curtain wall section along X, its banner on the front (-Z).
"""

import math
import random

import numpy as np

from generate_meshes import Mesh, cylinder, extrude, lathe, merge, rounded_box, sphere, taper, torus, tube

# ---------------------------------------------------------------------------- helpers


def oriented(mesh: Mesh, desired) -> Mesh:
    """Flips faces whose normal points away from `desired(centroids)`."""
    tri = mesh.v[mesh.f]
    normal = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    want = desired(tri.mean(axis=1))
    flip = (normal * want).sum(axis=1) < 0
    mesh.f[flip] = mesh.f[flip][:, ::-1]
    return mesh


def radial(cx: float = 0.0, cz: float = 0.0):
    return lambda c: np.stack([c[:, 0] - cx, np.zeros(len(c)), c[:, 2] - cz], 1)


def downward(c):
    return np.tile([0.0, -1.0, 0.0], (len(c), 1))


def tube_out(points, radius: float, sides: int = 8) -> Mesh:
    """A capped tube along a polyline, its faces pointing away from the line."""
    mesh = taper(points, radius, radius, sides)
    pts = np.array(points, dtype=float)

    def nearest(c):
        best = np.full(len(c), np.inf)
        out = np.zeros_like(c)
        for a, b in zip(pts[:-1], pts[1:]):
            ab = b - a
            t = np.clip(((c - a) @ ab) / max(ab @ ab, 1e-12), 0, 1)
            q = a + t[:, None] * ab
            d = np.linalg.norm(c - q, axis=1)
            take = d < best
            best[take] = d[take]
            out[take] = (c - q)[take]
        return out

    return oriented(mesh, nearest)


def anchor_tris(points, y: float = 0.0) -> list:
    """Tiny triangles at (x, z) points: they stretch a prop's bounding box so its pivot (the game
    puts it at the box's bottom center) stays on the prop's axis."""
    return [Mesh([(x, y, z), (x + 0.03, y, z), (x, y, z + 0.03)], [(0, 2, 1)]) for x, z in points]


def ring_bricks(rnd, radius_at, y0, y1, row_h, count, depth=0.5, skip=None, cx=0.0, cz=0.0):
    """Stone blocks around a round wall (axis at cx, cz), every other row offset by half a block."""
    bricks = []
    rows = int(round((y1 - y0) / row_h))
    for row in range(rows):
        y = y0 + row * row_h + row_h / 2
        radius = radius_at(y)
        for k in range(count):
            angle = 2 * math.pi * (k + (0.5 if row % 2 else 0.0) + rnd.uniform(-0.06, 0.06)) / count
            if skip is not None and skip(angle, y):
                continue
            width = 2 * math.pi * radius / count - 0.22
            d = depth + rnd.uniform(-0.05, 0.08)
            brick = rounded_box(width, row_h - 0.2 + rnd.uniform(-0.05, 0.03), d, min(0.12, d / 2 - 0.01), 2)
            brick.rotate("y", -math.degrees(angle) - 90)
            out = radius - d / 2 + 0.14 + rnd.uniform(-0.02, 0.04)
            bricks.append(brick.translate(cx + math.cos(angle) * out, y, cz + math.sin(angle) * out))
    return bricks


def wall_courses(rnd, length, y0, rows, row_h, face_z, depth, min_w, max_w, gap=0.16, proud=0.16):
    """Stone blocks in running bond along X over [-length/2, length/2] on the wall face at z = face_z
    (standing `proud` out of it). The end blocks stop half a gap short, so sections tile."""
    blocks = []
    sign = 1.0 if face_z > 0 else -1.0
    for row in range(rows):
        y = y0 + (row + 0.5) * row_h
        cuts = [-length / 2]
        x = -length / 2 + rnd.uniform(min_w, max_w) * (0.5 if row % 2 else 1.0)
        while x < length / 2 - min_w * 0.6:
            cuts.append(x)
            x += rnd.uniform(min_w, max_w)
        cuts.append(length / 2)
        for a, b in zip(cuts[:-1], cuts[1:]):
            d = depth + rnd.uniform(-0.04, 0.05)
            block = rounded_box(b - a - gap, row_h - gap + rnd.uniform(-0.04, 0.02), d, min(0.13, d / 2 - 0.01), 2)
            zc = face_z + sign * (proud + rnd.uniform(-0.02, 0.03) - d / 2)
            blocks.append(block.translate((a + b) / 2, y, zc))
    return blocks


def cone_roof(radius: float, y0: float, y1: float, courses: int, segments: int, flare: float = 1.35) -> Mesh:
    """A storybook cone roof, slightly concave, in shingle courses whose lips overhang the course
    below; closed underneath."""
    height = y1 - y0

    def r_at(t):
        return radius * (1 - t) ** flare

    profile = [(0.0, y0), (radius + 0.1, y0)]
    for i in range(courses):
        t0, t1 = i / courses, (i + 1) / courses
        profile.append((r_at(t0) + 0.16, y0 + height * t0 + 0.14))
        if i < courses - 1:
            profile.append((r_at(t1) + 0.03, y0 + height * t1))
    profile.append((0.0, y1))
    return lathe(profile, segments)


def sector(profile, a0: float, a1: float, steps: int) -> Mesh:
    """Part of a lathe: the (radius, y) profile swept from angle a0 to a1 (radians)."""
    verts, faces = [], []
    n = steps + 1
    for r, y in profile:
        for s in range(n):
            a = a0 + (a1 - a0) * s / steps
            verts.append((math.cos(a) * r, y, math.sin(a) * r))
    for i in range(len(profile) - 1):
        for s in range(steps):
            a = i * n + s
            c = a + n
            faces += [(a, c, a + 1), (a + 1, c, c + 1)]
    return Mesh(verts, faces)


def waved(mesh: Mesh, amount: float, along: int = 0, freq: float = 1.6, grow: float = 0.0) -> Mesh:
    """Ripples a flat cloth (made in the XY plane) along Z, like a flag in a breeze."""
    v = mesh.v
    start = v[:, along].min() if along == 0 else v[:, along].max()
    dist = np.abs(v[:, along] - start)
    v[:, 2] += amount * np.sin(dist * freq) * (1 if grow <= 0 else np.minimum(1.0, dist / grow))
    return mesh


def pennant(length: float, height: float, thickness: float) -> Mesh:
    """A triangular pennant along +X from x = 0, centered on y = 0, rippling."""
    mesh = extrude([(0.0, -height / 2), (length, -height * 0.06), (length * 0.9, 0.0), (length, height * 0.06),
                    (0.0, height / 2)], thickness)
    return waved(mesh, 0.22, 0, 1.7, length * 0.5)


def swallowtail(width: float, length: float, thickness: float, notch: float) -> Mesh:
    """A hanging banner, its top edge on y = 0, hanging down `length` with a V cut in its tail."""
    mesh = extrude([(-width / 2, 0.0), (width / 2, 0.0), (width / 2, -length), (0.0, -length + notch),
                    (-width / 2, -length)], thickness)
    v = mesh.v
    v[:, 2] += 0.07 * np.sin(-v[:, 1] * 1.3) * np.minimum(1.0, -v[:, 1] / 2.0)
    return mesh


def heater_shield(width: float, height: float, thickness: float) -> Mesh:
    """A heater shield facing Z, its point at y = 0 and its top edge at y = height."""
    w = width / 2
    side = [(w * math.cos(t * math.pi / 2), height * 0.5 * (1 - math.sin(t * math.pi / 2))) for t in np.linspace(0, 1, 7)]
    poly = [(-w, height), (w, height)] + side[:-1] + [(0.0, 0.0)] + [(-x, y) for x, y in reversed(side[:-1])]
    return extrude(poly, thickness)


def crossed_arrows(size: float, thickness: float) -> Mesh:
    """Two arrows crossed in an X (an archers' badge), centered on the origin, facing Z."""
    parts = []
    for turn in (-38, 38):
        shaft = extrude([(-0.07 * size, -size), (0.07 * size, -size), (0.07 * size, size * 0.72), (-0.07 * size, size * 0.72)], thickness)
        head = extrude([(-0.24 * size, size * 0.68), (0.24 * size, size * 0.68), (0.0, size * 1.1)], thickness)
        vanes = extrude([(-0.07 * size, -size * 0.62), (-0.26 * size, -size * 0.98), (-0.26 * size, -size * 0.72),
                         (0.26 * size, -size * 0.72), (0.26 * size, -size * 0.98), (0.07 * size, -size * 0.62)], thickness)
        for piece in (shaft, head, vanes):
            parts.append(piece.rotate("z", turn))
    return merge(*parts)


def disc_z(radius: float, thickness: float, segments: int = 40) -> Mesh:
    """A flat disc facing -Z, its back at z = 0 and its front at z = -thickness."""
    return cylinder(radius, thickness, segments).rotate("x", -90)


def ring_z(inner: float, outer: float, thickness: float, segments: int = 48) -> Mesh:
    """A flat ring facing -Z, its back at z = 0 and its front at z = -thickness."""
    return lathe([(inner, 0), (outer, 0), (outer, thickness), (inner, thickness), (inner, 0)], segments).rotate("x", -90)


# ---------------------------------------------------------------------------- the tower

DECK = 16.0
BODY_R = 6.0
TURRET_Z = 6.7  # the stair turret's axis, behind the deck (+Z, away from the courtyard)


def body_radius(y: float) -> float:
    """The tower wall: a slight batter at the foot, straight above."""
    return BODY_R + 0.7 * max(0.0, 1 - y / 2.2) ** 2


def archer_tower():
    rnd = random.Random(7)
    wall = lathe([(0.0, 0.0), (body_radius(0), 0.0)] + [(body_radius(y), y) for y in np.linspace(0.0, 14.6, 16)]
                 + [(BODY_R + 0.1, 14.6), (BODY_R + 1.3, 15.95), (5.4, 15.95), (0.0, 15.95)], 48)

    # Stone blocks over the mortar, leaving room for the door (front, -Z).
    def door_gap(angle, y):
        return y < 0.35 + 4 * 1.25 and abs(math.atan2(math.sin(angle + math.pi / 2), math.cos(angle + math.pi / 2))) < 0.35

    bricks = ring_bricks(rnd, body_radius, 0.35, 0.35 + 11 * 1.25, 1.25, 18, skip=door_gap)

    # The collar under the deck, its corbels, the parapet and the merlons.
    corbels = []
    for k in range(20):
        angle = 2 * math.pi * (k + 0.5) / 20
        corbel = rounded_box(0.7, 1.1, 0.9, 0.15, 2).rotate("y", -math.degrees(angle) - 90)
        corbels.append(corbel.translate(math.cos(angle) * (BODY_R + 0.35), 14.2, math.sin(angle) * (BODY_R + 0.35)))
    parapet = lathe([(6.55, 15.9), (7.35, 15.9), (7.35, 17.2), (6.55, 17.2), (6.55, 15.9)], 48)
    band = lathe([(7.32, 15.75), (7.55, 15.8), (7.6, 16.05), (7.55, 16.3), (7.32, 16.35)], 48)
    tz, tr, ttop = TURRET_Z, 2.5, 22.4
    merlons = []
    for k in range(12):
        angle = 2 * math.pi * k / 12
        mx, mz = math.cos(angle) * 6.95, math.sin(angle) * 6.95
        if math.hypot(mx, mz - tz) < tr + 1.0:
            continue  # the turret stands there
        merlon = rounded_box(1.9, 1.35, 0.85, 0.2, 3).rotate("y", -math.degrees(angle) - 90)
        merlons.append(merlon.translate(mx, 17.75, mz))
    deck = cylinder(6.6, 0.12, 48).translate(0, 15.9, 0)
    planks = []
    for k in range(-5, 6):
        x = k * 1.18
        half = math.sqrt(max(0.0, 6.5 ** 2 - x ** 2)) - 0.1
        if half > 0.4:
            planks.append(rounded_box(1.06, 0.1, half * 2, 0.04, 1).translate(x, 16.0, 0))

    # The door at the foot (-Z): an arched wooden door in a stone frame, iron bands across it.
    door_poly = [(-1.4, 0.0), (1.4, 0.0)] + [(1.4 * math.cos(a), 3.4 + 1.4 * math.sin(a)) for a in np.linspace(0, math.pi, 14)]
    door = extrude(door_poly, 0.5).translate(0, 0.02, -(body_radius(1.5) - 0.05))
    frame = torus(1.65, 0.28, 20, 8, 180).rotate("x", -90).translate(0, 3.4, -(body_radius(3.0) + 0.02))
    jambs = [rounded_box(0.56, 3.4, 0.56, 0.12, 2).translate(sx * 1.65, 1.7, -(body_radius(1.7) + 0.02)) for sx in (-1, 1)]
    irons = [rounded_box(2.6, 0.18, 0.12, 0.05, 1).translate(0, y, -(body_radius(1.5) + 0.25)) for y in (1.0, 2.8)]
    knocker = torus(0.22, 0.05, 14, 6).rotate("x", 90).translate(0.7, 2.0, -(body_radius(2.0) + 0.32))

    # Arrow-slit windows on the sides.
    windows = []
    for angle_deg, y in ((0, 9.0), (180, 9.0), (45, 6.0), (135, 6.0)):
        angle = math.radians(angle_deg)
        slit = rounded_box(0.5, 2.0, 0.4, 0.2, 2).rotate("y", -angle_deg - 90)
        out = BODY_R + 0.12
        windows.append(slit.translate(math.cos(angle) * out, y, math.sin(angle) * out))

    # The stair turret at the back (+Z): it rises well above the deck, with a tall blue cone roof
    # and a big pennant, so the tower reads from anywhere in the courtyard.
    turret = lathe([(0.0, 0.0), (tr - 0.05, 0.0), (tr - 0.05, ttop), (0.0, ttop)], 32).translate(0, 0, tz)

    def hidden(angle, y):
        x, z = math.cos(angle) * tr, tz + math.sin(angle) * tr
        reach = BODY_R + 0.5 if y < 15.6 else (7.5 if y < 18.6 else 0.0)
        return math.hypot(x, z) < reach

    turret_bricks = ring_bricks(rnd, lambda y: tr, 0.35, 0.35 + 17 * 1.25, 1.25, 9, depth=0.42, skip=hidden, cz=tz)
    turret_band = lathe([(tr - 0.1, ttop - 0.55), (tr + 0.32, ttop - 0.5), (tr + 0.4, ttop - 0.2), (tr + 0.32, ttop + 0.1),
                         (tr - 0.1, ttop + 0.1)], 32).translate(0, 0, tz)
    roof_top = 31.0
    roof = cone_roof(tr + 0.8, ttop, roof_top, 7, 40).translate(0, 0, tz)
    finial = merge(sphere(0.42, 8, 14).translate(0, roof_top + 0.25, tz),
                   cylinder(0.13, 3.0, 10).translate(0, roof_top + 0.5, tz),
                   sphere(0.24, 6, 10).translate(0, roof_top + 3.6, tz))
    flag = pennant(5.0, 2.2, 0.1).translate(0.12, roof_top + 2.45, tz)
    turret_slits = []
    for angle_deg, y in ((90, 12.0), (35, 19.0), (145, 19.0), (90, 5.0), (10, 9.0), (170, 9.0)):
        angle = math.radians(angle_deg)
        slit = rounded_box(0.45, 1.7, 0.5, 0.2, 2).rotate("y", -angle_deg - 90)
        turret_slits.append(slit.translate(math.cos(angle) * (tr + 0.12), y, tz + math.sin(angle) * (tr + 0.12)))

    # Two long tournament banners hung under the collar, either side of the door (front, -Z).
    banners, emblems, bars = [], [], []
    for side in (-1, 1):
        angle = -90 + side * 34
        cloth = swallowtail(2.5, 6.6, 0.08, 1.0).translate(0, 13.4, 0)
        badge = crossed_arrows(0.95, 0.14).translate(0, 10.9, 0)
        bar = merge(tube_out([(-1.5, 13.45, 0.0), (1.5, 13.45, 0.0)], 0.08, 8),
                    sphere(0.16, 6, 8).translate(-1.55, 13.45, 0), sphere(0.16, 6, 8).translate(1.55, 13.45, 0))
        for mesh, store in ((cloth, banners), (badge, emblems), (bar, bars)):
            mesh.translate(0, 0, -6.6).rotate("y", -(angle + 90))
            store.append(mesh)

    # Painted shields hung around the front of the parapet.
    shields_a, shields_b, shield_rims = [], [], []
    for k in range(-2, 3):
        angle = -90 + k * 27
        face = heater_shield(1.0, 1.25, 0.1).translate(0, 16.0, -7.82)
        rim = heater_shield(1.18, 1.44, 0.06).translate(0, 15.9, -7.75)
        for mesh in (face, rim):
            mesh.rotate("y", -(angle + 90))
        (shields_a if k % 2 == 0 else shields_b).append(face)
        shield_rims.append(rim)

    # Keep the bounding box centered on the tower's axis (the game pivots the prop on its box).
    reach = 10.2
    anchors = anchor_tris([(0.0, -reach), (0.0, reach), (-reach, 0.0), (reach, 0.0)], 0.0)

    return {
        "Mortar": merge(wall, turret, *anchors),
        "Stone": merge(*bricks, *corbels, *turret_bricks),
        "Trim": merge(parapet, band, *merlons, *jambs, frame, turret_band),
        "Deck": merge(deck, *planks),
        "Wood": door,
        "Iron": merge(*irons, knocker),
        "Window": merge(*windows, *turret_slits),
        "Roof": roof,
        "Pole": merge(finial, *bars, *shield_rims),
        "Flag": flag,
        "Banner": merge(*banners),
        "Emblem": merge(*emblems),
        "ShieldA": merge(*shields_a),
        "ShieldB": merge(*shields_b),
    }


# ---------------------------------------------------------------------------- the target board

BOARD_W = 7.2
BOARD_BOTTOM = 1.4
BOARD_TOP = 7.6


def target_board():
    # The cart: a plank platform on four wheels that run on the rails.
    cart = rounded_box(6.2, 0.45, 2.5, 0.12, 3).translate(0, 0.95, 0)
    wheels = []
    for x in (-2.3, 2.3):
        for z in (-0.9, 0.9):
            wheels.append(cylinder(0.5, 0.26, 18, 0.06).rotate("x", 90).translate(x, 0.55, z - 0.13 if z > 0 else z + 0.13))
    hubs = [cylinder(0.16, 0.34, 10).rotate("x", 90).translate(x, 0.55, z - 0.17 if z > 0 else z + 0.17)
            for x in (-2.3, 2.3) for z in (-0.9, 0.9)]
    axles = [cylinder(0.08, 1.9, 8).rotate("x", 90).translate(x, 0.55, -0.95) for x in (-2.3, 2.3)]

    # Posts and braces holding the board up.
    posts = [rounded_box(0.42, BOARD_BOTTOM + 0.6, 0.42, 0.1, 2).translate(x, 1.1 + (BOARD_BOTTOM + 0.6) / 2 - 0.3, 0.45)
             for x in (-2.4, 2.4)]
    braces = [tube_out([(x, 1.15, 1.1), (x, 2.4, 0.42)], 0.12, 8) for x in (-2.4, 2.4)]

    # The board: three planks with a frame, iron corner caps.
    height = BOARD_TOP - BOARD_BOTTOM
    planks = [rounded_box(BOARD_W / 3 - 0.08, height - 0.2, 0.42, 0.08, 2).translate(x, BOARD_BOTTOM + height / 2, 0.05)
              for x in (-BOARD_W / 3, 0.0, BOARD_W / 3)]
    frame = [
        rounded_box(BOARD_W + 0.2, 0.36, 0.56, 0.1, 2).translate(0, BOARD_TOP - 0.1, 0.05),
        rounded_box(BOARD_W + 0.2, 0.36, 0.56, 0.1, 2).translate(0, BOARD_BOTTOM + 0.1, 0.05),
        rounded_box(0.36, height, 0.56, 0.1, 2).translate(-BOARD_W / 2, BOARD_BOTTOM + height / 2, 0.05),
        rounded_box(0.36, height, 0.56, 0.1, 2).translate(BOARD_W / 2, BOARD_BOTTOM + height / 2, 0.05),
    ]
    # The back (what the runners hiding behind it see): painted in the board's colors, with a
    # Z-brace like a barn door over the paint.
    paint = rounded_box(BOARD_W - 0.5, height - 0.5, 0.05, 0.02, 1).translate(0, BOARD_BOTTOM + height / 2, 0.285)
    batten_y = (BOARD_BOTTOM + 1.0, BOARD_TOP - 1.0)
    braces_back = [rounded_box(BOARD_W - 0.5, 0.55, 0.22, 0.08, 2).translate(0, y, 0.36) for y in batten_y]
    dx, dy = BOARD_W - 1.4, batten_y[1] - batten_y[0]
    diagonal = rounded_box(math.hypot(dx, dy), 0.5, 0.2, 0.08, 2).rotate("z", math.degrees(math.atan2(dy, dx)))
    braces_back.append(diagonal.translate(0, (batten_y[0] + batten_y[1]) / 2, 0.34))
    # A gold crest with crossed iron arrows in each of the Z-brace's two empty triangles (at their
    # incenters, which the brace is point-symmetric about), so the runners' side isn't a bare panel.
    # The crest stands just out from the paint (0.31) and the arrows just out from the crest.
    crests, crest_arrows = [], []
    for sx in (-1, 1):
        cx, cy_crest = -sx * 2.02, (batten_y[0] + batten_y[1]) / 2 + sx * 0.5
        crests.append(heater_shield(1.5, 1.8, 0.05).translate(cx, cy_crest - 0.9, 0.345))
        crest_arrows.append(crossed_arrows(0.52, 0.04).translate(cx, cy_crest + 0.05, 0.385))
    caps = [rounded_box(0.7, 0.7, 0.66, 0.12, 2).translate(sx * BOARD_W / 2, y, 0.05)
            for sx in (-1, 1) for y in (BOARD_BOTTOM + 0.1, BOARD_TOP - 0.1)]
    studs = [sphere(0.1, 5, 8).translate(sx * BOARD_W / 2, y, -0.28) for sx in (-1, 1) for y in (BOARD_BOTTOM + 0.1, BOARD_TOP - 0.1)]

    # The front: a painted heater shield with a gold rim, the target on it. Every layer stands a
    # little further out than the one behind it (never coplanar).
    shield_bottom = BOARD_BOTTOM + 0.3
    shield = heater_shield(5.8, 5.4, 0.1).translate(0, shield_bottom, -0.21)
    rim = heater_shield(6.1, 5.62, 0.06).translate(0, shield_bottom - 0.14, -0.19)
    cy = shield_bottom + 5.4 * 0.58
    front = -0.26
    face = disc_z(2.05, 0.05, 48).translate(0, cy, front)
    ring_red = merge(ring_z(1.62, 2.05, 0.03).translate(0, cy, front - 0.05), ring_z(0.86, 1.26, 0.03).translate(0, cy, front - 0.05))
    bull = disc_z(0.45, 0.1, 32).translate(0, cy, front - 0.03)
    target_rim = torus(2.08, 0.07, 48, 8).rotate("x", 90).translate(0, cy, front - 0.03)
    return {
        "Wood": merge(cart, *posts, *braces, *planks),
        "Frame": merge(*frame, *braces_back),
        "Iron": merge(*caps, *studs, *hubs, *axles, *crest_arrows),
        "Wheels": merge(*wheels),
        "Paint": merge(shield, paint),  # the client paints both in the board's color
        "ShieldRim": merge(rim, target_rim),
        "Crest": merge(*crests),
        "Face": face,
        "Rings": ring_red,
        "Bull": bull,
    }


# ---------------------------------------------------------------------------- the bow and the arrow

def bow_curve(y: float) -> float:
    """z of the bow's limb at height y (y in -1..1): the back bulges forward (-Z), the tips recurve."""
    a = abs(y)
    bulge = -0.62 * (1 - a ** 2)
    recurve = 0.3 * max(0.0, (a - 0.78) / 0.22) ** 2
    return bulge + recurve


def ambush_bow():
    half = 2.3
    ys = np.linspace(-1.0, 1.0, 29)
    upper = [(0.0, half + y * half, bow_curve(y)) for y in ys if y >= 0]
    lower = [(0.0, half + y * half, bow_curve(y)) for y in ys if y <= 0][::-1]
    limbs = merge(taper(upper, 0.17, 0.065, 10), taper(lower, 0.17, 0.065, 10))
    grip = merge(
        rounded_box(0.38, 1.1, 0.46, 0.17, 3).translate(0, half, bow_curve(0.0) + 0.02),
        torus(0.21, 0.05, 16, 6).translate(0, half + 0.55, bow_curve(0.0)),
        torus(0.21, 0.05, 16, 6).translate(0, half - 0.55, bow_curve(0.0)),
    )
    tip_top = (0.0, half * 2, bow_curve(1.0))
    tip_bottom = (0.0, 0.0, bow_curve(-1.0))
    string = tube([tip_bottom, (0.0, half, 0.16), tip_top], 0.028, 6)
    tips = merge(sphere(0.12, 6, 10).translate(*tip_top), sphere(0.12, 6, 10).translate(*tip_bottom))
    mesh = {"Limbs": limbs, "Grip": grip, "String": string, "Tips": tips}
    lowest = min(float(m.v[:, 1].min()) for m in mesh.values())
    for m in mesh.values():
        m.translate(0, -lowest, 0)
    return mesh


def ambush_arrow():
    shaft = cylinder(0.075, 3.6, 10).rotate("x", 90).translate(0, 0, -1.6)  # z from -1.6 to 2.0
    head = lathe([(0.0, 0.0), (0.08, 0.02), (0.27, 0.2), (0.12, 0.5), (0.0, 0.78)], 4).rotate("x", -90).translate(0, 0, -1.55)
    collar = cylinder(0.1, 0.12, 10).rotate("x", 90).translate(0, 0, -1.62)
    vanes = []
    for k in range(3):
        poly = [(0.0, 0.0), (0.0, 1.0), (0.3, 0.75), (0.3, 0.15)]
        vane = extrude([(y, x) for x, y in poly], 0.03)  # x = along shaft, y = out from it
        vane.rotate("y", -90)  # extrude's thickness onto x, the vane in the YZ plane
        vane.translate(0, 0.06, 0.95)
        vane.rotate("z", 120 * k)
        vanes.append(vane)
    nock = sphere(0.1, 6, 8).translate(0, 0, 2.02)
    mesh = {"Shaft": shaft, "Head": merge(head, collar), "Fletching": merge(*vanes), "Nock": nock}
    lowest = min(float(m.v[:, 1].min()) for m in mesh.values())
    for m in mesh.values():
        m.translate(0, -lowest, 0)
    return mesh


# ---------------------------------------------------------------------------- courtyard dressing

def hay_bale():
    """A straw bale with two twine bands and loose straws poking out."""
    rnd = random.Random(3)
    bale = rounded_box(4.0, 2.4, 2.6, 0.45, 6).translate(0, 1.2, 0)
    bale.v += np.array([[rnd.uniform(-0.04, 0.04) for _ in range(3)] for _ in range(len(bale.v))])
    bands = [rounded_box(0.22, 2.52, 2.72, 0.5, 4).translate(x, 1.2, 0) for x in (-1.1, 1.1)]
    straws = []
    for _ in range(40):
        x, y = rnd.uniform(-1.8, 1.8), rnd.uniform(0.4, 2.2)
        side = rnd.choice((-1, 1))
        z0 = side * 1.22
        tip = (x + rnd.uniform(-0.3, 0.3), y + rnd.uniform(-0.2, 0.3), z0 + side * rnd.uniform(0.2, 0.5))
        straws.append(tube([(x, y, z0), tip], 0.03, 4))
    return {"Straw": merge(bale, *straws), "Twine": merge(*bands)}


def arrow_barrel():
    """A wooden barrel full of arrows."""
    rnd = random.Random(5)
    profile = [(0.0, 0.0), (1.05, 0.0)] + [(1.05 + 0.22 * math.sin(math.pi * t), 2.6 * t) for t in np.linspace(0, 1, 12)] + [(1.0, 2.6), (0.9, 2.45), (0.0, 2.45)]
    barrel = lathe(profile, 32)
    hoops = [torus(1.05 + 0.22 * math.sin(math.pi * t) + 0.03, 0.06, 32, 6).translate(0, 2.6 * t, 0) for t in (0.12, 0.3, 0.7, 0.88)]
    shafts, heads, feathers = [], [], []
    for _ in range(9):
        a, r = rnd.uniform(0, 2 * math.pi), rnd.uniform(0.0, 0.7)
        base = np.array([math.cos(a) * r, 1.4, math.sin(a) * r])
        lean = np.array([math.cos(a) * 0.25 + rnd.uniform(-0.1, 0.1), 1.0, math.sin(a) * 0.25 + rnd.uniform(-0.1, 0.1)])
        lean /= np.linalg.norm(lean)
        top = base + lean * rnd.uniform(2.3, 2.8)
        shafts.append(tube([tuple(base), tuple(top)], 0.05, 6))
        side = np.cross(lean, np.array([0.0, 0.0, 1.0]))
        side /= np.linalg.norm(side) + 1e-9
        # (turned 30 degrees round the shaft: square on, a vane lay level with one of the six-sided
        # shaft's faces, 0.04 off it, and the two flickered)
        side = side * math.cos(math.radians(30)) + np.cross(lean, side) * math.sin(math.radians(30))
        for k in (-1, 1):
            p0 = top - lean * 0.75
            vane = [tuple(top - lean * 0.05), tuple(p0 + side * k * 0.22), tuple(p0 - lean * 0.15)]
            feathers.append(Mesh(vane, [(0, 1, 2), (0, 2, 1)]))
    return {"Barrel": barrel, "Hoops": merge(*hoops), "Shafts": merge(*shafts), "Feathers": merge(*feathers)}


def bunting():
    """A sagging rope 20 studs long (along X, ends at the top) with pennants in three colors."""
    span, sag = 20.0, 1.0

    def rope_y(x):
        return 2.4 - sag * (1 - (2 * x / span) ** 2)

    rope = tube([(x, rope_y(x), 0.0) for x in np.linspace(-span / 2, span / 2, 33)], 0.05, 6)
    pennants = {"PennantA": [], "PennantB": [], "PennantC": []}
    keys = list(pennants)
    count = 9
    for i in range(count):
        x = -span / 2 + span * (i + 1) / (count + 1)
        y = rope_y(x)
        tri = extrude([(-0.55, 0.0), (0.55, 0.0), (0.0, -1.2)], 0.04).translate(x, y - 0.03, 0)
        pennants[keys[i % 3]].append(tri)
    pieces = {"Rope": rope}
    for key, meshes in pennants.items():
        pieces[key] = merge(*meshes)
    lowest = min(float(m.v[:, 1].min()) for m in pieces.values())
    for m in pieces.values():
        m.translate(0, -lowest, 0)
    return pieces


# ---------------------------------------------------------------------------- the castle grounds

COBBLE_X, COBBLE_Z = 10.6, 10.7


def arrow_ambush_cobbles():
    """One tile of hand-laid cobbles in rows (running bond): mostly cream, some honey and a few blue
    stones. The gaps show the courtyard floor underneath as grout. Edges stop half a gap short, so
    tiles meet seamlessly."""
    rnd = random.Random(11)
    pieces = {"Cobble": [], "CobbleWarm": [], "CobbleCool": []}
    rows = 11
    depth = COBBLE_Z / rows
    gap = 0.16
    for row in range(rows):
        z = -COBBLE_Z / 2 + (row + 0.5) * depth
        cuts = [-COBBLE_X / 2]
        x = -COBBLE_X / 2 + rnd.uniform(0.9, 1.5) * (0.5 if row % 2 else 1.0)
        while x < COBBLE_X / 2 - 0.55:
            cuts.append(x)
            x += rnd.uniform(0.95, 1.55)
        cuts.append(COBBLE_X / 2)
        for a, b in zip(cuts[:-1], cuts[1:]):
            h = 0.36 + rnd.uniform(-0.04, 0.04)
            stone = rounded_box(b - a - gap, h, depth - gap - rnd.uniform(0.0, 0.06), 0.16, 2)
            stone.rotate("y", rnd.uniform(-2.5, 2.5)).translate((a + b) / 2, h / 2, z + rnd.uniform(-0.02, 0.02))
            roll = rnd.random()
            key = "Cobble" if roll < 0.66 else ("CobbleWarm" if roll < 0.9 else "CobbleCool")
            pieces[key].append(stone)
    corners = anchor_tris([(sx * COBBLE_X / 2, sz * COBBLE_Z / 2) for sx in (-1, 1) for sz in (-1, 1)], 0.0)
    return {
        "Cobble": merge(*pieces["Cobble"], *corners),
        "CobbleWarm": merge(*pieces["CobbleWarm"]),
        "CobbleCool": merge(*pieces["CobbleCool"]),
    }


WALL_L = 8.8
WALL_H = 2.4


def arrow_ambush_wall():
    """A low courtyard wall along X: stone courses on a mortar core, coping stones and little merlons
    (spaced so sections tile)."""
    rnd = random.Random(13)
    core = rounded_box(WALL_L, WALL_H, 1.24, 0.04, 3).translate(0, WALL_H / 2, 0)
    stones = []
    for face in (-0.62, 0.62):
        stones += wall_courses(rnd, WALL_L, 0.0, 3, WALL_H / 3, face, 0.36, 1.0, 1.7, proud=0.16)
    coping = []
    x = -WALL_L / 2
    cuts = [x]
    while x < WALL_L / 2 - 1.2:
        x += rnd.uniform(1.6, 2.3)
        cuts.append(min(x, WALL_L / 2))
    cuts[-1] = WALL_L / 2
    for a, b in zip(cuts[:-1], cuts[1:]):
        coping.append(rounded_box(b - a - 0.1, 0.36, 1.86, 0.12, 2).translate((a + b) / 2, WALL_H + 0.16, rnd.uniform(-0.02, 0.02)))
    merlons = [rounded_box(1.3, 0.62, 1.4, 0.2, 2).translate(-WALL_L / 2 + 1.1 + k * 2.2, WALL_H + 0.6, 0) for k in range(4)]
    return {"Mortar": core, "Stone": merge(*stones), "Cap": merge(*coping, *merlons)}


def arrow_ambush_turret():
    """A round corner turret with stone courses, a gold-trimmed band and a storybook cone roof with a
    pennant."""
    rnd = random.Random(17)
    radius = 1.8

    def r_at(y):
        return radius + 0.3 * max(0.0, 1 - y / 1.2) ** 2

    top = 5.2
    body = lathe([(0.0, 0.0), (r_at(0) - 0.08, 0.0)] + [(r_at(y) - 0.08, y) for y in np.linspace(0, top, 8)] + [(0.0, top)], 28)
    bricks = ring_bricks(rnd, r_at, 0.0, 4.8, 0.8, 10, depth=0.4)
    band = lathe([(radius - 0.1, top - 0.2), (radius + 0.35, top - 0.15), (radius + 0.42, top + 0.15), (radius + 0.32, top + 0.4),
                  (radius - 0.1, top + 0.4)], 28)
    roof_top = 10.4
    roof = cone_roof(radius + 0.6, top + 0.3, roof_top, 5, 28)
    gold = merge(torus(radius + 0.62, 0.08, 28, 6).translate(0, top + 0.36, 0),
                 sphere(0.3, 8, 12).translate(0, roof_top + 0.15, 0),
                 cylinder(0.07, 1.8, 8).translate(0, roof_top + 0.3, 0),
                 sphere(0.14, 6, 8).translate(0, roof_top + 2.15, 0))
    flag = pennant(2.2, 1.0, 0.07).translate(0.06, roof_top + 1.6, 0)
    slits = []
    for angle_deg in (-90, 30, 150):
        angle = math.radians(angle_deg)
        slit = rounded_box(0.36, 1.2, 0.4, 0.16, 2).rotate("y", -angle_deg - 90)
        slits.append(slit.translate(math.cos(angle) * (radius + 0.12), 3.0, math.sin(angle) * (radius + 0.12)))
    reach = 2.3
    anchors = anchor_tris([(-reach, 0.0), (0.0, -reach), (0.0, reach)], 0.0)
    return {"Mortar": merge(body, *anchors), "Stone": merge(*bricks), "Trim": band, "Roof": roof, "Gold": gold,
            "Flag": flag, "Window": merge(*slits)}


CASTLE_L = 16.0


def arrow_ambush_castle_wall():
    """A tall curtain wall section along X: a plinth, big stone courses on the front (-Z), a corbelled
    walk with merlons on both sides, arrow slits, and a long banner with a gold star in the middle."""
    rnd = random.Random(19)
    height = 10.4
    core = rounded_box(CASTLE_L, height, 2.6, 0.05, 1).translate(0, height / 2, 0)
    plinth = rounded_box(CASTLE_L, 1.0, 3.4, 0.14, 2).translate(0, 0.5, 0)
    stones = wall_courses(rnd, CASTLE_L, 1.0, 7, 1.2, -1.3, 0.55, 1.5, 2.6, gap=0.2, proud=0.22)
    walk = rounded_box(CASTLE_L, 0.8, 3.5, 0.16, 2).translate(0, height - 0.4 + 0.2, 0)
    corbels = [rounded_box(0.8, 0.9, 0.5, 0.14, 2).translate(-CASTLE_L / 2 + 1.0 + k * 2.0, height - 1.1, -1.55) for k in range(8)]
    merlons = []
    for k in range(6):
        x = -CASTLE_L / 2 + CASTLE_L / 12 + k * CASTLE_L / 6
        for z in (-1.25, 1.25):
            merlons.append(rounded_box(1.7, 1.6, 0.9, 0.22, 2).translate(x, height + 0.6 + 0.8, z))
    slits = [rounded_box(0.5, 1.9, 0.7, 0.2, 2).translate(x, 6.0, -1.32) for x in (-5.4, 5.4)]
    cloth = swallowtail(3.2, 7.0, 0.1, 1.2).translate(0, height - 1.25, -1.86)
    star = extrude([((0.95 if i % 2 == 0 else 0.42) * math.sin(math.pi * i / 5), (0.95 if i % 2 == 0 else 0.42) * math.cos(math.pi * i / 5))
                    for i in range(10)], 0.16).translate(0, height - 4.1, -1.86)
    bar = merge(tube_out([(-1.75, height - 1.2, -1.85), (1.75, height - 1.2, -1.85)], 0.09, 8),
                sphere(0.18, 6, 8).translate(-1.8, height - 1.2, -1.85), sphere(0.18, 6, 8).translate(1.8, height - 1.2, -1.85))
    return {"Mortar": core, "Stone": merge(*stones), "Trim": merge(plinth, walk, *corbels, *merlons), "Window": merge(*slits),
            "Banner": cloth, "Emblem": star, "Gold": bar}


def arrow_ambush_tent():
    """A round festival pavilion in two-color stripes: striped walls and a concave cone roof, a
    scalloped valance, a dark doorway on the front (-Z) with a gold trim, and a pennant on top."""
    radius, wall_top, eave, apex = 3.4, 3.3, 3.85, 7.6
    stripes = 16
    a_parts, b_parts = [], []
    roof_profile = [(eave, wall_top + 0.05)] + [(eave * (1 - t) ** 1.5, wall_top + 0.05 + (apex - wall_top) * t) for t in np.linspace(0.12, 1, 7)]
    for k in range(stripes):
        a0, a1 = 2 * math.pi * k / stripes, 2 * math.pi * (k + 1) / stripes
        wall = oriented(sector([(radius, 0.0), (radius, wall_top + 0.1)], a0, a1, 3), radial())
        roof = oriented(sector(roof_profile, a0, a1, 3), radial())
        under = oriented(sector([(0.0, wall_top + 0.05), (eave, wall_top + 0.05)], a0, a1, 3), downward)
        # The valance tab under this stripe is the other color, its bottom edge scalloped.
        verts, faces = [], []
        steps = 6
        for s in range(steps + 1):
            u = s / steps
            a = a0 + (a1 - a0) * u
            r = eave + 0.06
            verts.append((math.cos(a) * r, wall_top + 0.12, math.sin(a) * r))
            verts.append((math.cos(a) * r, wall_top - 0.32 - 0.28 * math.sin(math.pi * u), math.sin(a) * r))
        for s in range(steps):
            i = 2 * s
            faces += [(i, i + 2, i + 1), (i + 1, i + 2, i + 3)]
        tab = oriented(Mesh(verts, faces), radial())
        (a_parts if k % 2 == 0 else b_parts).extend([wall, roof, under])
        (b_parts if k % 2 == 0 else a_parts).append(tab)
    door_poly = [(-0.85, 0.0), (0.85, 0.0)] + [(0.85 * math.cos(a), 1.75 + 0.85 * math.sin(a)) for a in np.linspace(0, math.pi, 10)]
    door = extrude(door_poly, 0.1).translate(0, 0.0, -(radius + 0.06))
    door_trim = tube_out([(x, y, -(radius + 0.13)) for x, y in [(-0.85, 0.0)] + door_poly[2:] + [(0.85, 0.0)]][::-1], 0.07, 6)
    gold = merge(torus(eave + 0.08, 0.07, 40, 6).translate(0, wall_top + 0.12, 0),
                 sphere(0.26, 8, 12).translate(0, apex - 0.05, 0),
                 cylinder(0.06, 1.7, 8).translate(0, apex + 0.1, 0),
                 sphere(0.12, 6, 8).translate(0, apex + 1.85, 0), door_trim)
    flag = pennant(1.9, 0.85, 0.06).translate(0.05, apex + 1.4, 0)
    return {"StripeA": merge(*a_parts), "StripeB": merge(*b_parts), "Inside": door, "Trim": gold, "Flag": flag}


def arrow_ambush_banner():
    """A tall banner pole on a stone foot: a gold finial, a crossbar and a long swallowtail banner
    with a gold crossed-arrows badge, hanging in front (-Z)."""
    foot = rounded_box(1.0, 0.5, 1.0, 0.14, 2).translate(0, 0.25, 0)
    pole = tube_out([(0.0, 0.3, 0.0), (0.0, 11.0, 0.0)], 0.15, 10)
    gold = merge(sphere(0.32, 8, 12).translate(0, 11.2, 0),
                 tube_out([(-1.7, 10.3, -0.24), (1.7, 10.3, -0.24)], 0.08, 8),
                 sphere(0.15, 6, 8).translate(-1.75, 10.3, -0.24), sphere(0.15, 6, 8).translate(1.75, 10.3, -0.24))
    cloth = swallowtail(2.9, 6.4, 0.08, 1.1).translate(0, 10.22, -0.36)
    badge = crossed_arrows(1.0, 0.14).translate(0, 7.9, -0.36)
    tassels = merge(*[sphere(0.14, 5, 8).translate(x, 10.22 - 6.4 + 0.02, -0.36) for x in (-1.45, 1.45)])
    return {"Foot": foot, "Pole": pole, "Gold": merge(gold, tassels), "Cloth": cloth, "Emblem": badge}


def arrow_ambush_hay_target():
    """A round straw archery butt (coiled straw rings) on a wooden easel, its painted target facing
    -Z, three arrows stuck in it."""
    rnd = random.Random(23)
    radius, half = 2.0, 0.5

    def coil(r):
        return 0.04 * math.sin(r * 9.0) ** 2

    rs = np.linspace(0.0, radius - 0.25, 16)
    profile = [(r, -half - coil(r)) for r in rs]
    profile += [(radius - 0.25 + 0.25 * math.sin(a), -0.25 * math.cos(a) * 2.0) for a in np.linspace(0.3, math.pi - 0.3, 6)]
    profile += [(r, half + coil(r)) for r in rs[::-1]]
    straw = lathe(profile, 32)
    face = cylinder(1.5, 0.05, 40).translate(0, half + 0.04, 0)
    rings = merge(lathe([(1.12, 0), (1.5, 0), (1.5, 0.03), (1.12, 0.03), (1.12, 0)], 40).translate(0, half + 0.09, 0),
                  lathe([(0.48, 0), (0.8, 0), (0.8, 0.03), (0.48, 0.03), (0.48, 0)], 40).translate(0, half + 0.09, 0))
    bull = cylinder(0.32, 0.1, 24).translate(0, half + 0.06, 0)
    shafts, vanes = [], []
    for _ in range(3):
        a, r = rnd.uniform(0, 2 * math.pi), rnd.uniform(0.3, 1.3)
        base = np.array([math.cos(a) * r, half - 0.2, math.sin(a) * r])
        tip = base + np.array([rnd.uniform(-0.25, 0.25), 1.7, rnd.uniform(-0.25, 0.25)])
        shafts.append(tube_out([tuple(base), tuple(tip)], 0.05, 6))
        for turn in (0, 90):
            vane = extrude([(-0.2, 0.0), (0.2, 0.0), (0.0, 0.55)], 0.03).rotate("x", -90).rotate("y", turn)
            vanes.append(vane.translate(*(tip - np.array([0, 0.62, 0]))))
    center_y = 3.1

    def place(mesh):
        return mesh.rotate("x", -90).rotate("x", -12).translate(0, center_y, 0)

    pieces = {key: place(mesh) for key, mesh in (("Straw", straw), ("Face", face), ("Rings", rings), ("Bull", bull),
                                                 ("Shafts", merge(*shafts)), ("Fletching", merge(*vanes)))}
    legs = [tube_out([(sx * 1.35, 0.0, -0.75), (sx * 0.55, 5.4, 0.3)], 0.13, 8) for sx in (-1, 1)]
    legs.append(tube_out([(0.0, 0.0, 2.1), (0.0, 5.0, 0.45)], 0.13, 8))
    shelf = rounded_box(2.6, 0.22, 0.6, 0.08, 2).translate(0, center_y - radius * 0.98 - 0.12, -0.32)
    pieces["Wood"] = merge(*legs, shelf)
    return pieces


PROPS = {
    "ArcherTower": archer_tower,
    "TargetBoard": target_board,
    "AmbushBow": ambush_bow,
    "AmbushArrow": ambush_arrow,
    "HayBale": hay_bale,
    "ArrowBarrel": arrow_barrel,
    "Bunting": bunting,
    "ArrowAmbushCobbles": arrow_ambush_cobbles,
    "ArrowAmbushWall": arrow_ambush_wall,
    "ArrowAmbushTurret": arrow_ambush_turret,
    "ArrowAmbushCastleWall": arrow_ambush_castle_wall,
    "ArrowAmbushTent": arrow_ambush_tent,
    "ArrowAmbushBanner": arrow_ambush_banner,
    "ArrowAmbushHayTarget": arrow_ambush_hay_target,
}
COLORS = {
    "Mortar": (150, 140, 132),
    "Stone": (206, 196, 182),
    "Trim": (226, 216, 200),
    "Deck": (170, 120, 80),
    "Wood": (150, 100, 62),
    "Iron": (70, 70, 80),
    "Window": (40, 34, 40),
    "Pole": (255, 205, 80),
    "Flag": (255, 120, 60),
    "Roof": (70, 110, 210),
    "Banner": (210, 50, 60),
    "Emblem": (255, 205, 80),
    "ShieldA": (60, 120, 220),
    "ShieldB": (220, 60, 70),
    "Frame": (120, 80, 50),
    "Wheels": (90, 64, 44),
    "Shield": (60, 130, 230),
    "ShieldRim": (255, 205, 80),
    "Crest": (255, 205, 80),
    "Paint": (60, 130, 230),
    "Face": (250, 246, 236),
    "Rings": (230, 60, 60),
    "Bull": (255, 205, 60),
    "Limbs": (150, 95, 55),
    "Grip": (90, 50, 40),
    "String": (245, 240, 225),
    "Tips": (255, 205, 80),
    "Shaft": (205, 160, 110),
    "Head": (170, 180, 195),
    "Fletching": (255, 110, 60),
    "Nock": (255, 205, 80),
    "Straw": (232, 200, 110),
    "Twine": (150, 100, 60),
    "Barrel": (160, 105, 62),
    "Hoops": (80, 80, 92),
    "Shafts": (210, 166, 112),
    "Feathers": (255, 110, 60),
    "Rope": (240, 235, 220),
    "PennantA": (255, 90, 80),
    "PennantB": (255, 205, 60),
    "PennantC": (80, 170, 255),
    "Cobble": (234, 222, 200),
    "CobbleWarm": (230, 190, 136),
    "CobbleCool": (168, 184, 204),
    "Cap": (236, 226, 208),
    "Gold": (255, 200, 70),
    "StripeA": (220, 60, 70),
    "StripeB": (250, 244, 228),
    "Inside": (60, 40, 50),
    "Foot": (200, 190, 176),
    "Cloth": (60, 110, 210),
}
