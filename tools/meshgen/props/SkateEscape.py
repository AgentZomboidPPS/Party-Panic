"""Meshes for Skate Escape (see tools/meshgen/props/README.md). Units are studs, +Y up, base on y = 0,
-Z is the front (the way the skater rides). Generate with:
    python3 tools/meshgen/generate_meshes.py --only SkateBoard,SkateCrate,SkateBarrier,SkateBoost,SkateDeck,SkateRail,SkateArch,SkateTorch"""

import math

import numpy as np

from generate_meshes import Mesh, cylinder, extrude, lathe, merge, rounded_box, sphere, taper, torus, tube

LANES = 12
LANE = 8.0
DECK_WIDTH = LANES * LANE + 4  # 100: twelve lanes and a little edge
SEGMENT = 24.0  # deck pieces are authored this long and stretched to fit


def box(sx, sy, sz, r, x=0.0, y=0.0, z=0.0, n=3):
    return rounded_box(sx, sy, sz, r, n).translate(x, y, z)


def strip(points, width, height):
    """A flat bar along a polyline in the XZ plane (painted lines, straps)."""
    pieces = []
    for (x0, z0), (x1, z1) in zip(points, points[1:]):
        length = math.hypot(x1 - x0, z1 - z0)
        angle = math.degrees(math.atan2(x1 - x0, z1 - z0))
        pieces.append(box(width, height, length, min(width, height) * 0.45, n=2).rotate("y", angle).translate((x0 + x1) / 2, 0, (z0 + z1) / 2))
    return merge(*pieces)


# ---------------------------------------------------------------------------------------- board


def board():
    """A popsicle skateboard: kicktails at both ends, grip tape on top, trucks and four wheels."""
    length, width, thick = 3.7, 1.05, 0.11
    deck_y = 0.39  # underside of the flat middle
    n_len, n_wid = 40, 10

    def kick(z):
        flat = 1.15
        over = max(0.0, abs(z) - flat)
        return (over / (length / 2 - flat)) ** 1.6 * 0.3 if over > 0 else 0.0

    def half_width(z):
        end = length / 2
        nose = 0.5
        if abs(z) <= end - nose:
            return width / 2
        t = (abs(z) - (end - nose)) / nose
        return width / 2 * math.sqrt(max(0.0, 1 - t * t)) * 0.98 + 0.01

    rows = []
    for i in range(n_len + 1):
        z = -length / 2 + length * i / n_len
        rows.append((z, half_width(z), deck_y + kick(z)))

    def surface(top: bool):
        verts, faces = [], []
        for z, hw, y in rows:
            for j in range(n_wid + 1):
                x = -hw + 2 * hw * j / n_wid
                # A gentle concave: the edges sit a touch higher.
                concave = 0.025 * (x / (width / 2)) ** 2
                verts.append((x, y + concave + (thick if top else 0.0), z))
        w = n_wid + 1
        for i in range(n_len):
            for j in range(n_wid):
                a, b, c, d = i * w + j, i * w + j + 1, (i + 1) * w + j, (i + 1) * w + j + 1
                faces += [(a, c, b), (b, c, d)] if top else [(a, b, c), (b, d, c)]
        return Mesh(verts, faces)

    grip = surface(True)
    bottom = surface(False)
    # Sides: a strip joining the top and bottom outlines.
    verts, faces = [], []
    outline = [(rows[i][0], rows[i][1], rows[i][2], 1) for i in range(len(rows))] + [
        (rows[i][0], -rows[i][1], rows[i][2], -1) for i in reversed(range(len(rows)))
    ]
    for z, x, y, side in outline:
        concave = 0.025
        verts.append((x, y + concave, z))
        verts.append((x, y + concave + thick, z))
    count = len(outline)
    for k in range(count):
        a, b = 2 * k, 2 * ((k + 1) % count)
        faces += [(a, b, a + 1), (b, b + 1, a + 1)]
    sides = Mesh(verts, faces)
    sides.smooth = False

    trucks, wheels = [], []
    for z in (-1.05, 1.05):
        trucks.append(box(0.42, 0.06, 0.62, 0.02, 0, deck_y - 0.03, z, n=2))  # base plate
        trucks.append(box(0.22, 0.12, 0.3, 0.05, 0, deck_y - 0.12, z, n=2))  # kingpin block
        hanger = tube([(-0.42, 0.2, z), (-0.15, 0.25, z), (0.15, 0.25, z), (0.42, 0.2, z)], 0.07, 10)
        trucks.append(hanger)
        axle = cylinder(0.025, 1.0, 8).rotate("z", 90).translate(0.5, 0.17, z)
        trucks.append(axle)
        for x in (-0.44, 0.44):
            wheel = lathe([(0.0, -0.08), (0.13, -0.08), (0.17, -0.05), (0.17, 0.05), (0.13, 0.08), (0.0, 0.08)], 18)
            wheels.append(wheel.rotate("z", 90).translate(x, 0.17, z))
    return {"Grip": grip, "Deck": merge(bottom, sides), "Trucks": merge(*trucks), "Wheels": merge(*wheels)}


# --------------------------------------------------------------------------------------- crate


def crate():
    """A banged-up wooden shipping crate with slats, a frame, cross braces and iron corners."""
    w, h, d = 4.2, 2.6, 3.4
    frame_t = 0.32
    frame = []
    for sx in (-1, 1):
        for sz in (-1, 1):
            frame.append(box(frame_t, h, frame_t, 0.07, sx * (w / 2 - frame_t / 2), h / 2, sz * (d / 2 - frame_t / 2)))
    for sy in (frame_t / 2, h - frame_t / 2):
        for sz in (-1, 1):
            frame.append(box(w, frame_t, frame_t, 0.07, 0, sy, sz * (d / 2 - frame_t / 2)))
        for sx in (-1, 1):
            frame.append(box(frame_t, frame_t, d, 0.07, sx * (w / 2 - frame_t / 2), sy, 0))
    # Cross braces on the front and back faces.
    diag = math.hypot(w - frame_t * 2, h - frame_t * 2)
    angle = math.degrees(math.atan2(h - frame_t * 2, w - frame_t * 2))
    for sz in (-1, 1):
        frame.append(box(diag, 0.28, 0.12, 0.05).rotate("z", angle).translate(0, h / 2, sz * (d / 2 + 0.02)))
    slats = []
    rng = np.random.default_rng(4)
    rows = 4
    for i in range(rows):
        y = frame_t + (h - frame_t * 2) * (i + 0.5) / rows
        sh = (h - frame_t * 2) / rows - 0.08
        for sz in (-1, 1):  # front and back
            slats.append(box(w - 0.1, sh, 0.14, 0.03, 0, y + rng.uniform(-0.02, 0.02), sz * (d / 2 - 0.1), n=2))
        for sx in (-1, 1):  # the sides
            slats.append(box(0.14, sh, d - 0.1, 0.03, sx * (w / 2 - 0.1), y + rng.uniform(-0.02, 0.02), 0, n=2))
    for i in range(3):  # the lid
        z = -d / 2 + d * (i + 0.5) / 3
        slats.append(box(w - 0.2, 0.14, d / 3 - 0.08, 0.03, 0, h - 0.1, z, n=2))
    metal = []
    for sx in (-1, 1):
        for sy in (0.23, h - 0.23):
            for sz in (-1, 1):
                metal.append(box(0.46, 0.46, 0.46, 0.08, sx * (w / 2 - 0.2), sy, sz * (d / 2 - 0.2), n=2))
    # A stencilled arrow plate on the front.
    plate = box(1.1, 0.7, 0.05, 0.03, 0, h * 0.5, -d / 2 - 0.06, n=2)
    return {"Slats": merge(*slats), "Frame": merge(*frame), "Metal": merge(*metal, plate)}


# ------------------------------------------------------------------------------------- barrier


def barrier():
    """A striped hurdle on A-frame legs with a warning lamp on top."""
    w, top = 7.0, 3.6
    legs = []
    for sx in (-1, 1):
        x = sx * (w / 2 - 0.45)
        legs.append(taper([(x, 0.0, -0.75), (x, 3.0, 0.0)], 0.13, 0.1, 10))
        legs.append(taper([(x, 0.0, 0.75), (x, 3.0, 0.0)], 0.13, 0.1, 10))
        legs.append(box(0.3, 0.12, 1.7, 0.05, x, 0.06, 0, n=2))
        legs.append(tube([(x, 1.2, -0.48), (x, 1.2, 0.48)], 0.06, 8))
    board_y0, board_h = 2.2, 1.0
    white, red = [], []
    stripes = 7
    sw = (w - 0.2) / stripes
    for i in range(stripes):
        x0 = -w / 2 + 0.1 + i * sw
        # Slanted stripes: a parallelogram extruded through the board.
        poly = [(x0, board_y0), (x0 + sw, board_y0), (x0 + sw + 0.35, board_y0 + board_h), (x0 + 0.35, board_y0 + board_h)]
        if i == stripes - 1:
            poly[1] = (x0 + sw, board_y0)
            poly[2] = (x0 + sw, board_y0 + board_h)
        if i == 0:
            poly[3] = (x0, board_y0 + board_h)
        piece = extrude(poly, 0.32)
        (red if i % 2 == 0 else white).append(piece)
    frame = box(w, 0.12, 0.38, 0.05, 0, board_y0 - 0.06, 0, n=2)
    frame_top = box(w, 0.12, 0.38, 0.05, 0, board_y0 + board_h + 0.06, 0, n=2)
    lamp_base = box(0.5, 0.18, 0.4, 0.06, 0, top - 0.42, 0, n=2)
    lamp = sphere(0.24, 8, 14).scale(1, 0.9, 1).translate(0, top - 0.22, 0)
    return {
        "Legs": merge(*legs, frame, frame_top, lamp_base),
        "Red": merge(*red),
        "White": merge(*white),
        "Lamp": lamp,
    }


# --------------------------------------------------------------------------------------- boost


def boost():
    """A boost pad: a dark plate with a rim and three glowing chevrons pointing down the course."""
    w, d = 6.4, 7.0
    pad = box(w, 0.2, d, 0.08, 0, 0.1, 0, n=3)
    rim = []
    for sx in (-1, 1):
        rim.append(box(0.3, 0.3, d, 0.1, sx * (w / 2 - 0.15), 0.15, 0, n=2))
    for sz in (-1, 1):
        rim.append(box(w, 0.3, 0.3, 0.1, 0, 0.15, sz * (d / 2 - 0.15), n=2))
    arrows = []
    for i in range(3):
        z = 1.9 - i * 1.9
        # A chevron pointing -Z.
        poly = [(0, z - 0.9), (2.1, z + 0.45), (1.3, z + 0.95), (0, z + 0.05), (-1.3, z + 0.95), (-2.1, z + 0.45)]
        chevron = Mesh(*_flat_poly(poly, 0.2, 0.08))
        arrows.append(chevron)
    return {"Pad": pad, "Rim": merge(*rim), "Arrows": merge(*arrows)}


def _flat_poly(poly, y0, thickness):
    """A polygon in XZ (concave is fine: ear-clipped), extruded upward from y0."""
    pts = list(poly)
    n = len(pts)
    idx = list(range(n))
    tris = []

    def area2(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])

    orient = sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n))
    sign = 1 if orient > 0 else -1
    guard = 0
    while len(idx) > 3 and guard < 200:
        guard += 1
        for k in range(len(idx)):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            a, b, c = pts[i0], pts[i1], pts[i2]
            if area2(a, b, c) * sign <= 0:
                continue
            inside = False
            for j in idx:
                if j in (i0, i1, i2):
                    continue
                p = pts[j]
                if area2(a, b, p) * sign > 0 and area2(b, c, p) * sign > 0 and area2(c, a, p) * sign > 0:
                    inside = True
                    break
            if not inside:
                tris.append((i0, i1, i2))
                idx.pop(k)
                break
    tris.append(tuple(idx))
    verts = [(x, y0, z) for x, z in pts] + [(x, y0 + thickness, z) for x, z in pts]
    faces = []
    for a, b, c in tris:
        # Top faces up (+Y), bottom faces down.
        if sign > 0:
            faces += [(n + a, n + c, n + b), (a, b, c)]
        else:
            faces += [(n + a, n + b, n + c), (a, c, b)]
    for i in range(n):
        j = (i + 1) % n
        # Walls face outward (Roblox culls back faces).
        if sign > 0:
            faces += [(i, n + i, j), (j, n + i, n + j)]
        else:
            faces += [(i, j, n + i), (j, n + j, n + i)]
    return np.array(verts, dtype=float), np.array(faces, dtype=np.int64), False


# ---------------------------------------------------------------------------------------- deck


def deck():
    """One 24-stud piece of the bridge: weathered planks across twelve painted lanes, stringers and
    cross beams underneath, bolts where the planks sit on the stringers."""
    rng = np.random.default_rng(11)
    top = 2.0
    planks, bolts, paint = [], [], []
    count = 16
    pitch = SEGMENT / count
    stringers = [-DECK_WIDTH / 2 + 3, -DECK_WIDTH / 4, 0.0, DECK_WIDTH / 4, DECK_WIDTH / 2 - 3]
    for i in range(count):
        z = -SEGMENT / 2 + pitch * (i + 0.5)
        width_jitter = rng.uniform(-0.6, 0.6)
        plank = box(DECK_WIDTH + width_jitter, 0.42, pitch - 0.14, 0.08, 0, top - 0.21 - rng.uniform(0, 0.03), z, n=2)
        plank.rotate("y", rng.uniform(-0.25, 0.25))
        planks.append(plank)
        for x in stringers:
            for dz in (-0.35, 0.35):
                bolts.append(cylinder(0.11, 0.06, 8).translate(x + rng.uniform(-0.1, 0.1), top - 0.02, z + dz))
    # Lane lines: dashed between lanes, solid at the edges.
    for k in range(LANES + 1):
        x = -LANES * LANE / 2 + k * LANE
        if k in (0, LANES):
            paint.append(box(0.36, 0.05, SEGMENT - 0.1, 0.02, x, top + 0.02, 0, n=1))
        else:
            for dash in range(3):
                z = -SEGMENT / 2 + SEGMENT * (dash + 0.5) / 3
                paint.append(box(0.24, 0.05, 4.2, 0.02, x, top + 0.02, z, n=1))
    beams = []
    for x in stringers:
        beams.append(box(1.1, 1.3, SEGMENT, 0.12, x, top - 0.42 - 0.65, 0, n=2))
    for z in (-SEGMENT / 2 + 0.8, SEGMENT / 2 - 0.8):
        beams.append(box(DECK_WIDTH - 1, 0.9, 1.0, 0.12, 0, 0.45, z, n=2))
    return {"Planks": merge(*planks), "Beams": merge(*beams), "Bolts": merge(*bolts), "Paint": merge(*paint)}


def rail():
    """The side rail for one deck piece: posts with caps, a hand rail and a sagging rope."""
    posts, wood, rope = [], [], []
    xs = [-9.0, -3.0, 3.0, 9.0]
    for z in xs:
        posts.append(box(0.7, 3.6, 0.7, 0.12, 0, 1.8, z, n=2))
        posts.append(box(0.9, 0.25, 0.9, 0.1, 0, 3.55, z, n=2))
    wood.append(box(0.5, 0.4, SEGMENT, 0.14, 0, 3.15, 0, n=2))
    sag = []
    for i in range(25):
        z = -SEGMENT / 2 + SEGMENT * i / 24
        local = ((z + SEGMENT / 2) % 6.0) / 6.0
        sag.append((0.0, 1.75 - math.sin(local * math.pi) * 0.35, z))
    rope.append(tube(sag, 0.09, 6))
    return {"Posts": merge(*posts), "Rail": merge(*wood), "Rope": merge(*rope)}


def torch():
    """An iron fire basket on a pole (the flame itself is a glowing part and particles in game)."""
    pole = cylinder(0.16, 3.2, 12, 0.04)
    ring_low = torus(0.55, 0.06, 18, 6).translate(0, 3.25, 0)
    ring_high = torus(0.75, 0.06, 18, 6).translate(0, 3.95, 0)
    bars = []
    for i in range(6):
        a = 2 * math.pi * i / 6
        bars.append(tube([(math.cos(a) * 0.55, 3.25, math.sin(a) * 0.55), (math.cos(a) * 0.75, 3.95, math.sin(a) * 0.75)], 0.05, 6))
    coals = sphere(0.5, 8, 12).scale(1, 0.5, 1).translate(0, 3.45, 0)
    return {"Iron": merge(pole, ring_low, ring_high, *bars), "Coals": coals}


# ---------------------------------------------------------------------------------------- arch


def arch():
    """The finish arch across all twelve lanes: stone towers with bands, a timber beam carrying a
    checkered banner, pennants on top. Also used (recolored) as the start gate."""
    span = DECK_WIDTH + 6
    tower_w, height = 6.0, 24.0
    rng = np.random.default_rng(3)
    stone, trim = [], []
    for sx in (-1, 1):
        x = sx * (span / 2 + tower_w / 2 - 1)
        y = 0.0
        layer = 0
        while y < height - 0.1:
            h = rng.uniform(2.6, 3.4)
            h = min(h, height - y)
            taper_w = tower_w - y / height * 0.9
            inset = 0.0 if layer % 2 == 0 else 0.18
            stone.append(box(taper_w - inset, h - 0.1, taper_w - inset, 0.14, x, y + h / 2, 0, n=2))
            y += h
            layer += 1
        for band_y in (0.3, height * 0.55, height - 0.2):
            trim.append(box(tower_w + 0.6, 0.6, tower_w + 0.6, 0.15, x, band_y, 0, n=2))
        # A pointed cap with a pennant pole.
        cap = lathe([(0.0, 0.0), (tower_w * 0.62, 0.0), (0.0, 3.2)], 4).rotate("y", 45).translate(x, height, 0)
        trim.append(cap)
        trim.append(cylinder(0.12, 4.0, 8).translate(x, height + 2.8, 0))
    beam_y = height - 7.6
    wood = [box(span + 2, 1.4, 1.6, 0.25, 0, beam_y + 6.2, 0, n=2), box(span + 2, 1.0, 1.4, 0.25, 0, beam_y - 0.5, 0, n=2)]
    dark, light = [], []
    cols, rows = 30, 3
    cell_w = (span - 4) / cols
    cell_h = 1.75
    for r in range(rows):
        for c in range(cols):
            x = -(span - 4) / 2 + cell_w * (c + 0.5)
            y = beam_y + 0.3 + cell_h * (r + 0.5)
            piece = box(cell_w, cell_h, 0.3, 0.02, x, y, -0.2, n=1)
            (dark if (r + c) % 2 == 0 else light).append(piece)
    pennants = []
    for sx in (-1, 1):
        x = sx * (span / 2 + tower_w / 2 - 1)
        flag = extrude([(0.0, 0.0), (2.6, -0.6), (0.0, -1.2)], 0.06).translate(x + 0.1, height + 6.6, 0)
        pennants.append(flag)
    return {"Stone": merge(*stone), "Trim": merge(*trim), "Beam": merge(*wood), "Dark": merge(*dark), "Light": merge(*light), "Pennant": merge(*pennants)}


PROPS = {
    "SkateBoard": board,
    "SkateCrate": crate,
    "SkateBarrier": barrier,
    "SkateBoost": boost,
    "SkateDeck": deck,
    "SkateRail": rail,
    "SkateTorch": torch,
    "SkateArch": arch,
}
COLORS = {
    "Grip": (40, 40, 48),
    "Deck": (255, 120, 60),
    "Trucks": (190, 195, 205),
    "Wheels": (255, 230, 90),
    "Slats": (196, 140, 82),
    "Frame": (140, 92, 52),
    "Metal": (90, 92, 100),
    "Legs": (70, 70, 80),
    "Red": (235, 60, 60),
    "White": (250, 250, 250),
    "Lamp": (255, 170, 40),
    "Pad": (40, 36, 60),
    "Rim": (90, 80, 120),
    "Arrows": (255, 220, 60),
    "Planks": (150, 102, 66),
    "Beams": (96, 64, 44),
    "Bolts": (70, 70, 76),
    "Paint": (245, 240, 225),
    "Posts": (110, 74, 48),
    "Rail": (130, 88, 56),
    "Rope": (210, 180, 130),
    "Iron": (60, 58, 62),
    "Coals": (255, 120, 40),
    "Stone": (120, 110, 115),
    "Trim": (80, 64, 60),
    "Beam": (110, 74, 48),
    "Dark": (30, 30, 36),
    "Light": (250, 250, 250),
    "Pennant": (255, 90, 90),
}
