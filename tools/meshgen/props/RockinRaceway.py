"""Props for Rockin' Raceway: the hobby horse every rider gallops on, the carrot (dash) and hurdle
(slow) panels on the track, the oval's turns, the finish arch, the white fence and bunting round the
track, a grandstand of fans, the carousel and striped tents of the infield and a Ferris wheel.

    python3 tools/meshgen/generate_meshes.py --only RockinRacewayHorse,RockinRacewayCarrot,RockinRacewayHurdle,RockinRacewayTurn,RockinRacewayArch,RockinRacewayFence,RockinRacewayBunting,RockinRacewayStand,RockinRacewayCarousel,RockinRacewayTent,RockinRacewayWheel

Units are studs, +Y is up, the base sits on y = 0 and -Z is the front:
  * RockinRacewayHorse: a hobby horse, its head at the front (-Z), the stick running down and back
    between the rider's legs to a little wheel at the back. Its bounding box is centred on z = 0 (the
    rider's root stands over that point). Body takes the rider's colour.
  * RockinRacewayCarrot: an orange track panel (3.8 x 4) with a big carrot and forward arrows on it.
  * RockinRacewayHurdle: a blue track panel with a low striped hurdle across it; the bar's top is at
    y = 0.8 (the server's CLEAR height).
  * RockinRacewayTurn: half the oval's turn, x >= 0 around the turn's centre: dirt from radius 31 to
    85 (twelve 4.5-stud lanes), lane lines, red and white curbs either side. The dirt's top is at
    y = 0.4 (the game sinks the mesh 0.4 so it's level with the ground).
  * RockinRacewayArch: the finish arch, its span along X (pillars at x = +-31.5), facing -Z; the game
    hangs the FINISH banner between the pillars (y 14.4..18.8).
  * RockinRacewayFence: 10 studs of white fence along X.
  * RockinRacewayBunting: two striped poles 20 studs apart (x = +-10) with pennants strung between.
  * RockinRacewayStand: a grandstand of fans under a striped awning, facing -Z.
  * RockinRacewayCarousel: a merry-go-round with a striped canopy and horses on gold poles.
  * RockinRacewayTent: a striped fair tent (Stripes is recoloured per tent).
  * RockinRacewayWheel: a Ferris wheel with gondolas, facing -Z.
"""

import math

import numpy as np

from generate_meshes import Mesh, cylinder, extrude, icosphere, lathe, merge, rounded_box, sphere, taper, torus, tube


def ellipsoid(rx: float, ry: float, rz: float, detail: int = 2) -> Mesh:
    return icosphere(1.0, detail).scale(rx, ry, rz)


def box(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> Mesh:
    """An axis-aligned box from corner to corner (the generator turns its faces outward)."""
    v = [(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
    f = [(0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5), (0, 4, 5), (0, 5, 1), (2, 3, 7), (2, 7, 6), (0, 2, 6), (0, 6, 4),
         (1, 5, 7), (1, 7, 3)]
    mesh = Mesh(v, f)
    mesh.smooth = False
    return mesh


def sector(r0: float, r1: float, y0: float, y1: float, a0: float, a1: float, segments: int) -> Mesh:
    """A closed slab of ring between radii r0..r1 and angles a0..a1 (radians, x = r cos a, z = r sin a)."""
    verts, faces = [], []
    for i in range(segments + 1):
        a = a0 + (a1 - a0) * i / segments
        c, s = math.cos(a), math.sin(a)
        for r in (r0, r1):
            for y in (y0, y1):
                verts.append((c * r, y, s * r))
    # per step 4 vertices: (r0,y0), (r0,y1), (r1,y0), (r1,y1)
    for i in range(segments):
        a, b = i * 4, (i + 1) * 4
        faces += [(a + 1, b + 1, b + 3), (a + 1, b + 3, a + 3)]  # top
        faces += [(a + 0, b + 2, b + 0), (a + 0, a + 2, b + 2)]  # bottom
        faces += [(a + 0, b + 0, b + 1), (a + 0, b + 1, a + 1)]  # inner wall
        faces += [(a + 2, b + 3, b + 2), (a + 2, a + 3, b + 3)]  # outer wall
    end = segments * 4
    faces += [(0, 1, 3), (0, 3, 2), (end + 0, end + 3, end + 1), (end + 0, end + 2, end + 3)]
    mesh = Mesh(verts, faces)
    mesh.smooth = False
    return mesh


def flat(polygon: list[tuple[float, float]], y0: float, y1: float) -> Mesh:
    """A 2D outline (x, z) lying flat, from y0 up to y1."""
    mesh = extrude([(x, -z) for x, z in polygon], y1 - y0).rotate("x", -90)
    return mesh.translate(0, (y0 + y1) / 2, 0)


# ------------------------------------------------------------------------------------------ the horse

def horse():
    """A hobby horse: a plush head on a wooden stick with a wheel at the back."""
    # The head: skull, long muzzle, cheeks, a neck that narrows down onto the stick.
    skull = ellipsoid(0.5, 0.56, 0.62).translate(0, 3.78, -1.05)
    muzzle = ellipsoid(0.4, 0.4, 0.62).rotate("x", -18).translate(0, 3.5, -1.62)
    nose = ellipsoid(0.36, 0.33, 0.3).translate(0, 3.36, -2.0)
    neck = taper([(0, 3.62, -0.8), (0, 3.25, -0.62), (0, 2.88, -0.52)], 0.44, 0.24, 16)
    body = merge(skull, muzzle, nose, neck)
    # The mane: soft tufts down the back of the head and neck.
    tufts = []
    for k in range(7):
        t = k / 6
        y = 4.28 - t * 1.25
        z = -1.0 + t * 0.6 + 0.35 * math.sin(t * math.pi) * 0.3
        tufts.append(ellipsoid(0.15, 0.24, 0.2, 1).rotate("x", 25).translate(0, y, z + 0.42))
    forelock = ellipsoid(0.14, 0.2, 0.12, 1).rotate("x", -30).translate(0, 4.28, -1.38)
    mane = merge(*tufts, forelock)
    ears = merge(*[taper([(side * 0.24, 4.18, -0.95), (side * 0.3, 4.62, -0.9)], 0.13, 0.02, 8) for side in (-1, 1)])
    eyes = merge(*[ellipsoid(0.11, 0.13, 0.08, 1).translate(side * 0.42, 3.86, -1.3) for side in (-1, 1)])
    pupils = merge(*[ellipsoid(0.06, 0.08, 0.05, 1).translate(side * 0.47, 3.86, -1.35) for side in (-1, 1)])
    nostrils = merge(*[ellipsoid(0.06, 0.05, 0.03, 1).translate(side * 0.14, 3.36, -2.29) for side in (-1, 1)])
    # The bridle: a noseband and cheek straps, reins looping back to the handle.
    noseband = torus(0.43, 0.045, 24, 6).scale(1.0, 1.0, 0.8).rotate("x", 72).translate(0, 3.5, -1.68)
    straps = [tube([(side * 0.42, 3.55, -1.6), (side * 0.48, 3.9, -1.15), (side * 0.38, 4.2, -0.85)], 0.04, 6)
              for side in (-1, 1)]
    reins = [tube([(side * 0.43, 3.5, -1.62), (side * 0.6, 3.25, -1.2), (side * 0.62, 3.05, -0.7)], 0.035, 6)
             for side in (-1, 1)]
    bridle = merge(noseband, *straps, *reins)
    studs = merge(*[sphere(0.07, 6, 8).translate(side * 0.45, 3.5, -1.6) for side in (-1, 1)])
    # The stick from under the neck down between the legs to the wheel, the handlebar across it.
    stick = taper([(0, 2.95, -0.55), (0, 0.42, 1.75)], 0.12, 0.1, 12)
    handle = taper([(-0.8, 3.02, -0.62), (0.8, 3.02, -0.62)], 0.08, 0.08, 10)
    knobs = merge(*[sphere(0.12, 8, 10).translate(side * 0.84, 3.02, -0.62) for side in (-1, 1)])
    wheel = torus(0.32, 0.1, 20, 8).rotate("z", 90).translate(0, 0.42, 1.75)
    hub = cylinder(0.12, 0.34, 12).rotate("z", 90).translate(0.17, 0.42, 1.75)
    fork = merge(*[tube([(side * 0.08, 0.7, 1.5), (side * 0.15, 0.42, 1.75)], 0.04, 6) for side in (-1, 1)])
    return {
        "Body": body,
        "Mane": mane,
        "Ears": ears,
        "Eyes": eyes,
        "Pupils": merge(pupils, nostrils),
        "Bridle": bridle,
        "Studs": merge(studs, knobs, hub),
        "Stick": merge(stick, handle),
        "Wheel": merge(wheel, fork),
    }


# ------------------------------------------------------------------------------------------ panels

PANEL_W, PANEL_L = 3.8, 4.0


def panel_base():
    pad = rounded_box(PANEL_W, 0.16, PANEL_L, 0.07, 4).translate(0, 0.08, 0)
    rim = merge(
        rounded_box(PANEL_W - 0.3, 0.06, 0.14, 0.03, 2).translate(0, 0.17, -PANEL_L / 2 + 0.25),
        rounded_box(PANEL_W - 0.3, 0.06, 0.14, 0.03, 2).translate(0, 0.17, PANEL_L / 2 - 0.25),
        rounded_box(0.14, 0.06, PANEL_L - 0.36, 0.03, 2).translate(-PANEL_W / 2 + 0.25, 0.17, 0),
        rounded_box(0.14, 0.06, PANEL_L - 0.36, 0.03, 2).translate(PANEL_W / 2 - 0.25, 0.17, 0),
    )
    return pad, rim


def chevron(z: float, width: float, y: float) -> Mesh:
    """A flat arrow pointing forward (-Z)."""
    w, t = width, 0.28
    outline = [(-w, 0.0), (0.0, -w * 0.7), (w, 0.0), (w, t), (0.0, -w * 0.7 + t), (-w, t)]
    pts = [(x, zz + z) for x, zz in outline]
    return flat(pts, 0.16, y)


def carrot_panel():
    """An orange dash panel: a big carrot pointing forward and two arrows."""
    pad, rim = panel_base()
    # The carrot lies flat, its tip forward: a flattened cone with ridges, leaves at the back.
    root = taper([(0, 0.26, 0.55), (0, 0.26, -0.2), (0, 0.26, -0.95)], 0.42, 0.06, 14).scale(1.0, 0.35, 1.0)
    root = root.translate(0, 0.17, 0)
    ridges = merge(*[torus(0.36 - k * 0.09, 0.025, 14, 4).rotate("x", 90).scale(1.0, 0.35, 1.0)
                     .translate(0, 0.27, 0.25 - k * 0.32) for k in range(3)])
    leaves = merge(*[ellipsoid(0.13, 0.06, 0.38, 1).rotate("y", a).translate(math.sin(math.radians(a)) * 0.3, 0.28,
                                                                                0.95 + math.cos(math.radians(a)) * 0.15)
                     for a in (-28, 0, 28)])
    arrows = merge(chevron(-1.15, 0.7, 0.24), chevron(-1.6, 0.7, 0.24))
    return {"Pad": pad, "Trim": merge(rim, arrows), "Carrot": merge(root, ridges), "Leaves": leaves}


def hurdle_panel():
    """A blue slow panel with a low striped hurdle across it (bar top at y = 0.8)."""
    pad, rim = panel_base()
    posts, feet = [], []
    for side in (-1, 1):
        x = side * 1.55
        posts.append(rounded_box(0.18, 0.66, 0.18, 0.05, 3).translate(x, 0.16 + 0.33, 0))
        feet.append(rounded_box(0.22, 0.12, 0.9, 0.05, 3).translate(x, 0.22, 0))
    stripes_a, stripes_b = [], []
    count = 6
    for k in range(count):
        x0 = -1.5 + 3.0 * k / count
        x1 = -1.5 + 3.0 * (k + 1) / count
        piece = box(x0, x1, 0.6, 0.8, -0.1, 0.1)
        (stripes_a if k % 2 == 0 else stripes_b).append(piece)
    ups = merge(*[chevron(z, 0.55, 0.22) for z in (-1.1, 1.45)])
    return {"Pad": pad, "Trim": merge(rim, ups), "Posts": merge(*posts, *feet), "BarA": merge(*stripes_a),
            "BarB": merge(*stripes_b)}


# ------------------------------------------------------------------------------------------ the track

R_IN, R_OUT = 31.0, 85.0
LANE = 4.5
CURB = 1.8


def turn():
    """Half a turn of the oval (x >= 0)."""
    a0, a1 = -math.pi / 2, math.pi / 2
    dirt = sector(R_IN, R_OUT, 0.0, 0.4, a0, a1, 96)
    lines = []
    for k in range(13):
        r = R_IN + k * LANE
        width = 0.5 if k in (0, 12) else 0.3
        lines.append(sector(r - width / 2, r + width / 2, 0.35, 0.5, a0, a1, 96))
    red, white = [], []
    for r0, r1 in ((R_IN - CURB, R_IN), (R_OUT, R_OUT + CURB)):
        middle = (r0 + r1) / 2
        count = max(2, int(round(math.pi * middle / 5)))
        for k in range(count):
            b0 = a0 + (a1 - a0) * k / count
            b1 = a0 + (a1 - a0) * (k + 1) / count
            piece = sector(r0, r1, 0.3, 0.58, b0, b1, 3)
            (red if k % 2 == 0 else white).append(piece)
    return {"Dirt": dirt, "Lines": merge(*lines), "CurbRed": merge(*red), "CurbWhite": merge(*white)}


def arch():
    """The finish arch: checkered pillars, a bulb-lit beam, gold balls on top."""
    dark, light, gold, beam_parts, bulbs = [], [], [], [], []
    for side in (-1, 1):
        x = side * 31.5
        gold.append(rounded_box(3.4, 0.8, 3.4, 0.2, 3).translate(x, 0.4, 0))  # the foot
        size = 2.4
        rows = 8
        height = 20.0
        for row in range(rows):
            y0 = 0.8 + (height - 0.8) * row / rows
            y1 = 0.8 + (height - 0.8) * (row + 1) / rows
            for cx in range(2):
                for cz in range(2):
                    piece = box(x - size / 2 + cx * size / 2, x - size / 2 + (cx + 1) * size / 2, y0, y1,
                                -size / 2 + cz * size / 2, -size / 2 + (cz + 1) * size / 2)
                    (dark if (row + cx + cz) % 2 == 0 else light).append(piece)
        gold.append(rounded_box(2.9, 0.5, 2.9, 0.15, 3).translate(x, height + 0.25, 0))
        gold.append(sphere(1.0, 10, 16).translate(x, height + 1.45, 0))
    # The beam across the top, slightly arched, with bulbs along its front and back.
    points = []
    for k in range(25):
        t = k / 24
        x = -31.5 + 63.0 * t
        y = 20.3 + 1.6 * math.sin(math.pi * t)
        points.append((x, y, 0.0))
    beam = taper(points, 0.7, 0.7, 12)
    beam_parts.append(beam)
    for k in range(1, 24):
        x, y, _ = points[k]
        for zz in (-0.72, 0.72):
            bulbs.append(sphere(0.2, 6, 8).translate(x, y - 0.25, zz))
    # Ropes the banner hangs from (it sits between y 14.4 and 18.8).
    ropes = [tube([(x, 18.8, 0.0), (x, 20.3 + 1.6 * math.sin(math.pi * (x + 31.5) / 63.0) - 0.5, 0.0)], 0.07, 6)
             for x in (-18.5, -9, 0, 9, 18.5)]
    return {"CheckDark": merge(*dark), "CheckLight": merge(*light), "Gold": merge(*gold), "Beam": merge(*beam_parts),
            "Bulbs": merge(*bulbs), "Ropes": merge(*ropes)}


def fence():
    """10 studs of white rail fence with two posts."""
    rails = merge(rounded_box(9.96, 0.24, 0.16, 0.06, 2).translate(0, 1.2, 0),
                  rounded_box(9.96, 0.24, 0.16, 0.06, 2).translate(0, 2.2, 0))
    posts = merge(*[rounded_box(0.34, 2.5, 0.34, 0.08, 2).translate(x, 1.25, 0) for x in (-2.5, 2.5)])
    caps = merge(*[sphere(0.24, 6, 10).translate(x, 2.55, 0) for x in (-2.5, 2.5)])
    return {"Rails": rails, "Posts": posts, "Caps": caps}


def bunting():
    """Two striped poles 20 studs apart with a string of pennants sagging between them."""
    poles, stripes, tops = [], [], []
    for x in (-10, 10):
        poles.append(cylinder(0.2, 8.6, 12).translate(x, 0, 0))
        for k in range(4):
            y = 1.2 + k * 1.9
            stripes.append(cylinder(0.215, 0.6, 12).translate(x, y, 0))
        tops.append(sphere(0.4, 8, 12).translate(x, 8.9, 0))
    string_pts = []
    for k in range(21):
        t = k / 20
        string_pts.append((-10 + 20 * t, 8.4 - 1.4 * math.sin(math.pi * t), 0.0))
    string = tube(string_pts, 0.05, 6)
    flags = [[], [], []]
    for k in range(13):
        t = (k + 0.5) / 13
        x = -10 + 20 * t
        y = 8.4 - 1.4 * math.sin(math.pi * t)
        tri = extrude([(-0.55, 0.0), (0.55, 0.0), (0.0, -1.2)], 0.05).translate(x, y, 0)
        flags[k % 3].append(tri)
    return {"Pole": merge(*poles), "Stripes": merge(*stripes), "Top": merge(*tops), "String": string,
            "FlagA": merge(*flags[0]), "FlagB": merge(*flags[1]), "FlagC": merge(*flags[2])}


# ------------------------------------------------------------------------------------------ fairground

def fan(x: float, y: float, z: float, seed: int) -> tuple[Mesh, Mesh]:
    rng = np.random.default_rng(seed)
    body = ellipsoid(0.55, 0.75, 0.42, 1).translate(x, y + 0.75, z)
    head = sphere(0.42, 6, 10).translate(x, y + 1.85, z)
    arm_up = rng.random() < 0.5
    arms = []
    for side in (-1, 1):
        if arm_up and side == 1:
            arms.append(tube([(x + 0.5, y + 1.2, z), (x + 0.75, y + 2.4, z - 0.1)], 0.14, 6))
        else:
            arms.append(tube([(x + side * 0.5, y + 1.2, z), (x + side * 0.65, y + 0.6, z - 0.2)], 0.14, 6))
    return merge(body, *arms), head


def stand():
    """A grandstand: five tiers of benches full of fans under a striped awning, facing -Z."""
    width = 40.0
    tiers, seats, heads = [], [], []
    fans = [[], [], []]
    for k in range(5):
        z0 = -7 + k * 2.6
        y = 0.4 + k * 1.3
        tiers.append(box(-width / 2, width / 2, 0.0, y, z0, z0 + 2.6))
        seats.append(rounded_box(width - 0.6, 0.35, 0.9, 0.12, 2).translate(0, y + 0.55, z0 + 1.6))
        for i in range(17):
            x = -width / 2 + 1.6 + i * (width - 3.2) / 16 + (0.3 if k % 2 else -0.3)
            if (i * 7 + k * 3) % 11 == 0:
                continue  # an empty seat
            body, head = fan(x, y + 0.7, z0 + 1.6, i * 31 + k)
            fans[(i + k) % 3].append(body)
            heads.append(head)
    # The awning: posts at the back and front, a striped roof sloping down to the front.
    posts = merge(*[cylinder(0.3, h, 10).translate(x, 0, z) for x in (-width / 2 + 0.6, 0, width / 2 - 0.6)
                    for z, h in ((-6.6, 10.5), (6.0, 13.5))])
    stripes_a, stripes_b = [], []
    count = 10
    for k in range(count):
        x0 = -width / 2 - 0.5 + (width + 1) * k / count
        x1 = -width / 2 - 0.5 + (width + 1) * (k + 1) / count
        roof = Mesh([(x0, 10.5, -7.6), (x1, 10.5, -7.6), (x0, 13.8, 7.0), (x1, 13.8, 7.0),
                     (x0, 10.8, -7.6), (x1, 10.8, -7.6), (x0, 14.1, 7.0), (x1, 14.1, 7.0)],
                    [(0, 2, 1), (1, 2, 3), (4, 5, 6), (5, 7, 6), (0, 1, 4), (1, 5, 4), (2, 6, 3), (3, 6, 7), (0, 4, 2),
                     (2, 4, 6), (1, 3, 5), (3, 7, 5)])
        roof.smooth = False
        # A scalloped edge along the front.
        scallop = ellipsoid((x1 - x0) / 2, 0.55, 0.12, 1).translate((x0 + x1) / 2, 10.4, -7.62)
        (stripes_a if k % 2 == 0 else stripes_b).append(merge(roof, scallop))
    return {"Frame": merge(*tiers), "Seats": merge(*seats), "FansA": merge(*fans[0]), "FansB": merge(*fans[1]),
            "FansC": merge(*fans[2]), "Heads": merge(*heads), "Posts": posts, "AwningA": merge(*stripes_a),
            "AwningB": merge(*stripes_b)}


def carousel_horse(angle: float, height: float) -> Mesh:
    """A little carousel horse facing along the ride (tangent), at `height`."""
    r = 8.6
    x, z = math.cos(angle) * r, math.sin(angle) * r
    body = ellipsoid(0.55, 0.6, 1.3)
    neck = taper([(0, 0.3, -0.9), (0, 1.1, -1.35)], 0.36, 0.28, 10)
    head = ellipsoid(0.3, 0.32, 0.62).rotate("x", -30).translate(0, 1.25, -1.7)
    legs = []
    for side in (-1, 1):
        legs.append(taper([(side * 0.3, -0.3, -0.8), (side * 0.32, -0.9, -1.35), (side * 0.3, -1.25, -1.1)], 0.14,
                          0.1, 6))
        legs.append(taper([(side * 0.3, -0.3, 0.8), (side * 0.32, -1.2, 1.0)], 0.15, 0.1, 6))
    tail = taper([(0, 0.2, 1.25), (0, -0.4, 1.7)], 0.16, 0.05, 6)
    horse_mesh = merge(body, neck, head, *legs, tail)
    # Facing along the tangent (counter-clockwise): its -Z along (-sin a, cos a).
    heading = math.degrees(math.atan2(math.sin(angle), math.cos(angle)))
    return horse_mesh.rotate("y", -heading).translate(x, height, z)


def carousel():
    """A merry-go-round: a round deck, horses on gold poles, a striped canopy and a flag on top."""
    deck = cylinder(11.0, 1.0, 48, 0.2)
    skirt = cylinder(11.3, 0.5, 48).translate(0, 0.0, 0)
    center = cylinder(2.2, 9.5, 24).translate(0, 1.0, 0)
    mirrors = merge(*[rounded_box(0.9, 1.6, 0.1, 0.05, 2).rotate("y", -math.degrees(a)).translate(
        math.cos(a) * 2.25, 6.0, math.sin(a) * 2.25) for a in [i * math.pi / 4 for i in range(8)]])
    horses, poles = [], []
    for i in range(10):
        a = i * 2 * math.pi / 10
        h = 3.2 + (0.6 if i % 2 else 0.0)
        horses.append(carousel_horse(a, h))
        poles.append(cylinder(0.12, 9.0, 8).translate(math.cos(a) * 8.6, 1.0, math.sin(a) * 8.6))
    # The canopy: a striped cone over a scalloped valance.
    stripes_a, stripes_b = [], []
    count = 16
    for k in range(count):
        a0 = 2 * math.pi * k / count
        a1 = 2 * math.pi * (k + 1) / count
        verts = [(0, 15.2, 0), (math.cos(a0) * 12.2, 10.6, math.sin(a0) * 12.2),
                 (math.cos(a1) * 12.2, 10.6, math.sin(a1) * 12.2), (0, 14.9, 0),
                 (math.cos(a0) * 11.7, 10.4, math.sin(a0) * 11.7), (math.cos(a1) * 11.7, 10.4, math.sin(a1) * 11.7)]
        faces = [(0, 2, 1), (3, 4, 5), (1, 2, 5), (1, 5, 4), (0, 1, 4), (0, 4, 3), (0, 3, 5), (0, 5, 2)]
        cone = Mesh(verts, faces)
        cone.smooth = False
        am = (a0 + a1) / 2
        scallop = ellipsoid(2.3, 0.75, 0.15, 1).rotate("y", -math.degrees(am) + 90).translate(
            math.cos(am) * 12.0, 10.2, math.sin(am) * 12.0)
        (stripes_a if k % 2 == 0 else stripes_b).append(merge(cone, scallop))
    rim = torus(12.0, 0.25, 64, 6).translate(0, 10.6, 0)
    finial = merge(cylinder(0.15, 2.4, 8).translate(0, 15.0, 0), sphere(0.45, 8, 12).translate(0, 15.2, 0))
    flag = extrude([(0.0, 0.0), (1.8, -0.45), (0.0, -0.9)], 0.06).translate(0.1, 17.3, 0)
    return {"Deck": merge(deck, skirt), "Center": center, "Mirrors": mirrors, "Horses": merge(*horses),
            "Poles": merge(*poles, finial, rim), "CanopyA": merge(*stripes_a), "CanopyB": merge(*stripes_b),
            "Flag": flag}


def tent():
    """A round fair tent: white walls, a striped cone roof, a pennant on top and a dark doorway."""
    walls = cylinder(4.0, 3.6, 32)
    stripes, roof = [], []
    count = 12
    for k in range(count):
        a0 = 2 * math.pi * k / count
        a1 = 2 * math.pi * (k + 1) / count
        verts = [(0, 8.0, 0), (math.cos(a0) * 4.7, 3.4, math.sin(a0) * 4.7), (math.cos(a1) * 4.7, 3.4, math.sin(a1) * 4.7),
                 (0, 7.7, 0), (math.cos(a0) * 4.3, 3.3, math.sin(a0) * 4.3), (math.cos(a1) * 4.3, 3.3, math.sin(a1) * 4.3)]
        faces = [(0, 2, 1), (3, 4, 5), (1, 2, 5), (1, 5, 4), (0, 1, 4), (0, 4, 3), (0, 3, 5), (0, 5, 2)]
        cone = Mesh(verts, faces)
        cone.smooth = False
        (stripes if k % 2 == 0 else roof).append(cone)
    door = rounded_box(2.0, 2.8, 0.4, 0.3, 3).translate(0, 1.4, -3.92)
    pole = cylinder(0.08, 1.8, 8).translate(0, 7.8, 0)
    pennant = extrude([(0.0, 0.0), (1.3, -0.3), (0.0, -0.6)], 0.05).translate(0.08, 9.5, 0)
    return {"Walls": walls, "Stripes": merge(*stripes), "Roof": merge(*roof), "Door": door, "Pole": pole,
            "Pennant": pennant}


def wheel():
    """A Ferris wheel facing -Z: A-frame legs, a double rim with spokes, gondolas hanging level."""
    hub_y = 25.0
    radius = 20.0
    rims, spokes, gondolas_a, gondolas_b, legs = [], [], [], [], []
    for zz in (-1.2, 1.2):
        rims.append(torus(radius, 0.35, 64, 8).rotate("x", 90).translate(0, hub_y, zz))
        rims.append(torus(radius - 2.2, 0.2, 64, 6).rotate("x", 90).translate(0, hub_y, zz))
        for k in range(16):
            a = 2 * math.pi * k / 16
            spokes.append(tube([(0, hub_y, zz), (math.cos(a) * radius, hub_y + math.sin(a) * radius, zz)], 0.14, 6))
        for side in (-1, 1):
            legs.append(taper([(side * 13.0, 0.0, zz * 4.5), (0, hub_y, zz * 1.4)], 0.6, 0.45, 10))
    hub = cylinder(1.4, 4.4, 20).rotate("x", 90).translate(0, hub_y, -2.2)
    gold = []
    for k in range(10):
        a = 2 * math.pi * (k + 0.5) / 10
        cx, cy = math.cos(a) * radius, hub_y + math.sin(a) * radius
        cab = merge(
            rounded_box(2.6, 1.6, 2.2, 0.4, 3).translate(cx, cy - 2.6, 0),
            lathe([(0.0, 0.0), (1.5, 0.0), (0.2, 0.9), (0.0, 0.9)], 16).translate(cx, cy - 1.75, 0),
        )
        gold.append(tube([(cx, cy - 0.2, 0), (cx, cy - 1.8, 0)], 0.1, 6))
        gold.append(cylinder(0.12, 2.8, 8).rotate("x", 90).translate(cx, cy, -1.4))
        (gondolas_a if k % 2 == 0 else gondolas_b).append(cab)
    lights = []
    for k in range(32):
        a = 2 * math.pi * k / 32
        lights.append(sphere(0.28, 6, 8).translate(math.cos(a) * (radius + 0.3), hub_y + math.sin(a) * (radius + 0.3), -1.6))
    base = rounded_box(30.0, 0.8, 9.0, 0.3, 3).translate(0, 0.4, 0)
    return {"Rim": merge(*rims), "Spokes": merge(*spokes, hub), "Legs": merge(*legs, base), "GondolaA": merge(*gondolas_a),
            "GondolaB": merge(*gondolas_b), "Gold": merge(*gold), "Lights": merge(*lights)}


PROPS = {
    "RockinRacewayHorse": horse,
    "RockinRacewayCarrot": carrot_panel,
    "RockinRacewayHurdle": hurdle_panel,
    "RockinRacewayTurn": turn,
    "RockinRacewayArch": arch,
    "RockinRacewayFence": fence,
    "RockinRacewayBunting": bunting,
    "RockinRacewayStand": stand,
    "RockinRacewayCarousel": carousel,
    "RockinRacewayTent": tent,
    "RockinRacewayWheel": wheel,
}
COLORS = {
    "Body": (255, 80, 90), "Mane": (250, 235, 200), "Ears": (255, 80, 90), "Eyes": (255, 255, 255),
    "Pupils": (35, 30, 45), "Bridle": (60, 120, 230), "Studs": (255, 205, 50), "Stick": (190, 135, 80),
    "Wheel": (60, 60, 75),
    "Pad": (255, 140, 40), "Trim": (255, 250, 235), "Carrot": (255, 120, 30), "Leaves": (90, 200, 80),
    "Posts": (250, 250, 250), "BarA": (60, 130, 240), "BarB": (250, 250, 250),
    "Dirt": (214, 160, 104), "Lines": (250, 248, 240), "CurbRed": (235, 60, 60), "CurbWhite": (250, 248, 240),
    "CheckDark": (35, 35, 45), "CheckLight": (250, 250, 250), "Gold": (255, 200, 60), "Beam": (230, 50, 70),
    "Bulbs": (255, 240, 150), "Ropes": (120, 90, 60),
    "Rails": (250, 250, 250), "Caps": (230, 60, 70),
    "Pole": (250, 250, 250), "Stripes": (230, 60, 70), "Top": (255, 200, 60), "String": (90, 80, 70),
    "FlagA": (255, 90, 140), "FlagB": (80, 170, 255), "FlagC": (255, 210, 60),
    "Frame": (225, 220, 210), "Seats": (70, 150, 255), "FansA": (255, 110, 90), "FansB": (90, 200, 120),
    "FansC": (250, 210, 70), "Heads": (240, 200, 160), "AwningA": (230, 60, 70), "AwningB": (250, 250, 250),
    "Deck": (250, 240, 220), "Center": (255, 180, 200), "Mirrors": (200, 230, 255), "Horses": (250, 250, 250),
    "Poles": (255, 200, 60), "CanopyA": (230, 60, 70), "CanopyB": (250, 250, 250), "Flag": (80, 170, 255),
    "Walls": (250, 250, 250), "Roof": (250, 250, 250), "Door": (60, 40, 70), "Pennant": (255, 210, 60),
    "Rim": (250, 250, 250), "Spokes": (220, 220, 230), "Legs": (70, 120, 220), "GondolaA": (255, 90, 120),
    "GondolaB": (80, 190, 255), "Lights": (255, 240, 150),
}
