"""Meshes for Skate Escape (see tools/meshgen/props/README.md). Units are studs, +Y up, base on y = 0,
-Z is the front (the way the skater rides). Generate with:
    python3 tools/meshgen/generate_meshes.py --only SkateBoard,SkateCrate,SkateBarrier,SkateBoost,SkateDeck,SkateRail,SkateTorch,\
        SkateCanyonWall,SkateButte,SkatePylon,SkateCable,SkateStartGate,SkateFinishArch

The canyon wall's foot stands 2 studs under the lava (48 below the deck); the pylon's foot is 66 below
the deck, buried deeper in the lava."""

import math

import numpy as np

from generate_meshes import Mesh, cylinder, extrude, icosphere, lathe, merge, rounded_box, sphere, taper, torus, tube

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


# ---------------------------------------------------------------------------------------- helpers


def fbox(sx, sy, sz, x=0.0, y=0.0, z=0.0):
    """A plain flat-shaded box (12 triangles), centered on (x, y, z)."""
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    v = [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz), (-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)]
    f = [(0, 2, 1), (0, 3, 2), (4, 5, 6), (4, 6, 7), (0, 1, 5), (0, 5, 4), (3, 6, 2), (3, 7, 6), (0, 4, 7), (0, 7, 3),
         (1, 2, 6), (1, 6, 5)]
    return Mesh(v, f, smooth=False).translate(x, y, z)


def signed_volume(mesh):
    tri = mesh.v[mesh.f]
    return float(np.einsum("ij,ij->i", tri[:, 0], np.cross(tri[:, 1], tri[:, 2])).sum() / 6)


def outward(mesh):
    """Turns a closed mesh we built ourselves so its faces point out (never used on shared helpers)."""
    if signed_volume(mesh) < 0:
        mesh.f = mesh.f[:, ::-1].copy()
    return mesh


def loft_x(xs, sections, smooth=False):
    """A closed solid swept along X: sections[i] is a list of (y, z) points (the same count for every
    column, going round the same way), joined column to column and capped at both ends."""
    k = len(sections[0])
    verts, faces = [], []
    for x, section in zip(xs, sections):
        for y, z in section:
            verts.append((x, y, z))
    n = len(xs)
    for c in range(n - 1):
        for j in range(k):
            a, b = c * k + j, c * k + (j + 1) % k
            a2, b2 = a + k, b + k
            faces += [(a, a2, b), (b, a2, b2)]
    for c, first in ((0, True), (n - 1, False)):
        center = len(verts)
        section = np.array(sections[c])
        verts.append((xs[c], section[:, 0].mean(), section[:, 1].mean()))
        for j in range(k):
            a, b = c * k + j, c * k + (j + 1) % k
            faces.append((center, a, b) if first else (center, b, a))
    return outward(Mesh(verts, faces, smooth))


def prism_xy(poly, z0, z1):
    """A (possibly concave) outline in the XY plane, extruded from z0 to z1 (ear-clipped)."""
    verts, faces, _ = _flat_poly(poly, z0, z1 - z0)  # outline in XZ, extruded along Y ...
    return outward(Mesh(np.asarray(verts)[:, [0, 2, 1]], faces, smooth=False))  # ... swapped to XY along Z


def capped_tube(points, radius, sides=8):
    """A tube along a polyline with both ends closed."""
    mesh = tube(points, radius, sides)
    verts, faces = [tuple(v) for v in mesh.v], [tuple(f) for f in mesh.f]
    pts = [np.array(p, dtype=float) for p in points]
    count = len(pts)
    for ring, outside in ((0, pts[0] - pts[1]), (count - 1, pts[-1] - pts[-2])):
        center = len(verts)
        verts.append(tuple(pts[ring]))
        cap = [(center, ring * sides + j, ring * sides + (j + 1) % sides) for j in range(sides)]
        a, b, c = (np.asarray(verts[i]) for i in cap[0])
        if np.dot(np.cross(b - a, c - a), outside) < 0:
            cap = [(x, z, y) for x, y, z in cap]
        faces += cap
    return Mesh(np.array(verts), faces, mesh.smooth)


def flat_tube(points, widths, thickness, sides=10):
    """A flattened tube (a lava stream): wide along X, thin across the flow, following points in YZ."""
    pts = [np.array(p, dtype=float) for p in points]
    verts, faces = [], []
    lateral = np.array([1.0, 0, 0])
    for i, p in enumerate(pts):
        tangent = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
        tangent /= np.linalg.norm(tangent) + 1e-9
        normal = np.cross(lateral, tangent)
        normal /= np.linalg.norm(normal) + 1e-9
        w = widths[i] / 2
        for j in range(sides):
            a = 2 * math.pi * j / sides
            verts.append(p + lateral * math.cos(a) * w + normal * math.sin(a) * thickness / 2)
    for i in range(len(pts) - 1):
        for j in range(sides):
            a = i * sides + j
            b = i * sides + (j + 1) % sides
            faces += [(a, a + sides, b), (b, a + sides, b + sides)]
    for ring, first in ((0, True), ((len(pts) - 1) * sides, False)):
        center = len(verts)
        verts.append(np.mean(verts[ring:ring + sides], axis=0))
        for j in range(sides):
            a, b = ring + j, ring + (j + 1) % sides
            faces.append((center, b, a) if first else (center, a, b))
    return outward(Mesh(verts, faces))


def noise1(x, seed, amps=(1.0, 0.55, 0.3), freqs=(0.045, 0.11, 0.27)):
    rng = np.random.default_rng(seed)
    phases = rng.uniform(0, 2 * math.pi, len(amps))
    return sum(a * math.sin(f * x + p) for a, f, p in zip(amps, freqs, phases))


# ---------------------------------------------------------------------------------------- deck


def deck():
    """One 24-stud piece of the bridge: long planks running down each lane (three a lane, joints
    staggered), the lanes in two alternating tones so all twelve read at speed and their seams make
    speed lines, red and white curbs along both edges, stringers and cross beams underneath."""
    rng = np.random.default_rng(11)
    top = 2.0
    planks, planks_b = [], []
    stringers = [-DECK_WIDTH / 2 + 3, -DECK_WIDTH / 4, 0.0, DECK_WIDTH / 4, DECK_WIDTH / 2 - 3]
    per_lane = 3
    width = (LANE - 0.3) / per_lane
    for lane in range(LANES):
        x0 = -LANES * LANE / 2 + LANE * lane + 0.15
        for k in range(per_lane):
            x = x0 + width * (k + 0.5)
            joint = rng.uniform(-8.0, 8.0)
            for z0, z1 in ((-SEGMENT / 2, joint), (joint, SEGMENT / 2)):
                h = 0.42 + rng.uniform(-0.04, 0.0)
                board = fbox(width - 0.12, h, z1 - z0 - 0.12)
                board.rotate("y", rng.uniform(-0.12, 0.12)).translate(x + rng.uniform(-0.02, 0.02), top - h / 2, (z0 + z1) / 2)
                (planks if lane % 2 == 0 else planks_b).append(board)
    # The outer edge boards carry the curbs.
    edge = []
    for sx in (-1, 1):
        edge.append(fbox(DECK_WIDTH / 2 - LANES * LANE / 2 + 0.2, 0.42, SEGMENT - 0.04, sx * (DECK_WIDTH / 2 - 0.9), top - 0.21, 0))
    red, white = [], []
    curbs = 8
    for sx in (-1, 1):
        for k in range(curbs):
            z = -SEGMENT / 2 + SEGMENT * (k + 0.5) / curbs
            block = fbox(1.25, 0.26, SEGMENT / curbs - 0.12, sx * (DECK_WIDTH / 2 - 1.55), top + 0.13, z)
            (red if k % 2 == 0 else white).append(block)
    beams = []
    for x in stringers:
        beams.append(fbox(1.1, 1.2, SEGMENT, x, top - 0.42 - 0.6, 0))
    for z in (-SEGMENT / 2 + 0.8, SEGMENT / 2 - 0.8):
        beams.append(fbox(DECK_WIDTH - 1, 0.8, 1.0, 0, 0.4, z))
    return {
        "Planks": merge(*planks),
        "PlanksB": merge(*planks_b),
        "Beams": merge(*beams, *edge),
        "CurbRed": merge(*red),
        "CurbWhite": merge(*white),
    }


def rail():
    """The side rail for one deck piece: chunky posts with caps, a timber hand rail and two thick
    sagging ropes."""
    posts, wood, rope = [], [], []
    xs = [-9.0, -3.0, 3.0, 9.0]
    for z in xs:
        posts.append(box(0.8, 3.5, 0.8, 0.14, 0, 1.75, z, n=2))
        posts.append(box(1.05, 0.3, 1.05, 0.12, 0, 3.5, z, n=2))
    wood.append(box(0.55, 0.42, SEGMENT, 0.16, 0, 3.12, 0, n=2))
    for height, sag_depth, radius in ((2.25, 0.45, 0.13), (1.1, 0.3, 0.11)):
        sag = []
        for i in range(25):
            z = -SEGMENT / 2 + SEGMENT * i / 24
            local = ((z + SEGMENT / 2) % 6.0) / 6.0
            sag.append((0.0, height - math.sin(local * math.pi) * sag_depth, z))
        rope.append(tube(sag, radius, 6))
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


# ------------------------------------------------------------------------------------ the canyon

WALL_LENGTH = 200.0
WALL_BACK = 64.0  # how deep the wall's top runs back from its foot
WALL_RIM = 38.0  # the height its top comes down to at the back (the plateau around the canyon)
WALL_TOP = 42.0  # the skyline's average height: a few studs under the deck, so the bridge is the highest thing
# Rock bands from the lava up: piece, bottom, top, how far the face is set back, bumpiness. The foot
# stands 2 studs under the lava; everything above it is seen.
WALL_BANDS = (
    ("Basalt", 0.0, 7.0, 0.0, 2.6),  # dark crust at the lava line
    ("RockLow", 7.0, 16.0, 4.0, 2.6),
    ("RockMid", 16.0, 22.0, 8.0, 2.4),
    ("Stripe", 22.0, 23.2, 8.8, 1.2),  # thin cream line
    ("RockMid", 23.2, 29.0, 9.3, 2.4),
    ("Stripe", 29.0, 32.5, 11.5, 1.4),  # the wide cream stripe the lava falls start from
    ("RockTop", 32.5, 37.0, 13.0, 2.2),
    ("RockLow", 37.0, 38.2, 13.8, 1.0),  # thin red line
    ("RockTop", 38.2, WALL_TOP, 14.3, 2.2),
)
CAVE_BAND = 5


def strata_wave(x):
    return 1.6 * noise1(x, 303, (1.0, 0.4), (0.025, 0.07))


def band_y(band, top, x):
    """The height of a band's bottom (top=False) or top at x: the strata wave up and down together
    (a little each of their own) and the skyline rises and dips."""
    k = band + 1 if top else band
    if k == 0:
        return 0.0
    if k == len(WALL_BANDS):
        skyline = WALL_TOP + 3.5 * max(-1.0, min(1.0, noise1(x, 400, (1.0, 0.5), (0.03, 0.09)) / 1.2))
        return max(skyline, band_y(k - 1, False, x) + 2.5)
    return WALL_BANDS[k][1] + strata_wave(x) + 0.3 * noise1(x, 300 + k, (1.0,), (0.05,))


def wall_front(x, band, row):
    """Where a band's face is (z) at x: its set-back plus layered bumps; `row` 0..1 up the band."""
    _, _, _, back, bump = WALL_BANDS[band]
    seed = 100 + band * 7
    z = back + bump * noise1(x, seed) + 1.0 * noise1(x, seed + 10 + int(row * 9), (1.0, 0.6), (0.33, 0.71))
    z -= 1.4 * math.sin(row * math.pi) * (0.7 + 0.3 * noise1(x, seed + 5, (1.0,), (0.2,)))  # bulging middle
    return z


def canyon_wall():
    """A 200-stud stretch of the canyon's side: layered toy rock bands (dark basalt at the lava, red,
    orange, a cream stripe, terracotta on top) stepping back as they rise, boulders on the ledges and
    two lava falls pouring down the face. Faces -Z; its foot (z = 0) stands in the lava."""
    xs = list(np.linspace(-WALL_LENGTH / 2, WALL_LENGTH / 2, 30))
    pieces = {}
    for band, (name, _, _, _, _) in enumerate(WALL_BANDS):
        sections = []
        for x in xs:
            y0, y1 = band_y(band, False, x), band_y(band, True, x)
            h = y1 - y0
            # The ends taper back, so neighbouring stretches overlap without a seam.
            end = max(0.0, abs(x) - (WALL_LENGTH / 2 - 14)) / 14
            fade = end * end * 9
            f = [wall_front(x, band, r) + fade for r in (0.0, 0.33, 0.7, 0.96)]
            lip = min(1.4, h * 0.2)
            section = [
                (y0, f[0]),
                (y0 + h * 0.33, f[1]),
                (y0 + h * 0.7, f[2]),
                (y1 - lip * 0.4, f[3] + 0.25),
                (y1, f[3] + lip),
            ]
            if band == len(WALL_BANDS) - 1:
                # The top rolls back down to the plateau (y = WALL_RIM at the back).
                rim = max(WALL_RIM, y0 + 1.5)
                section += [(y1 - 1.5, f[3] + 14.0), (rim + 3.0, WALL_BACK - 14.0), (rim, WALL_BACK)]
            else:
                section.append((y1, WALL_BACK))
            section.append((y0, WALL_BACK))
            sections.append(section)
        pieces.setdefault(name, []).append(loft_x(xs, sections))
    # Boulders resting on the ledges.
    rng = np.random.default_rng(23)
    boulders = []
    for k in range(9):
        band = int(rng.integers(0, 4))
        x = float(rng.uniform(-WALL_LENGTH / 2 + 18, WALL_LENGTH / 2 - 18))
        y1 = band_y(band, True, x)
        ledge = wall_front(x, band, 1.0) + 2.0
        r = float(rng.uniform(1.6, 3.4))
        z = ledge + r * 0.6
        rock = icosphere(r, 1, 0.3, seed=60 + k).scale(1.3, 0.75, 1.1).translate(x, y1 + r * 0.45, z)
        boulders.append(rock)
    # Lava falls: each pours from a cave mouth in the cream stripe, over every ledge into the river.
    falls, crust, caves = [], [], []
    for x0, width, phase in ((-52.0, 9.0, 0.4), (61.0, 7.0, 2.1)):
        stripe = wall_front(x0, CAVE_BAND, 0.5)
        mouth = (band_y(CAVE_BAND, False, x0) + band_y(CAVE_BAND, True, x0)) / 2
        path = [(x0, mouth + 0.5, stripe + 5.0), (x0, mouth, stripe - 1.0)]  # out of the cave in the cream stripe
        for band in range(CAVE_BAND - 1, -1, -1):
            y0, y1 = band_y(band, False, x0), band_y(band, True, x0)
            front_top = wall_front(x0, band, 1.0)
            front_mid = wall_front(x0, band, 0.5)
            front_low = wall_front(x0, band, 0.0)
            path.append((x0, y1 + 0.5, front_top + 0.4))  # across the ledge
            if y1 - y0 > 5:
                path.append((x0, y1 - 1.5, front_top - 1.8))  # over the lip
                path.append((x0, (y0 + y1) / 2, front_mid - 2.2))
            path.append((x0, y0 + 1.0, front_low - 2.4))
        path.append((x0, 0.6, wall_front(x0, 0, 0.0) - 6.0))
        widths = [width * (0.8 + 0.4 * i / (len(path) - 1)) for i in range(len(path))]
        sway = [(p[0] + (0.0 if i == 0 else 0.5 * math.sin(i * 1.3 + phase)), p[1], p[2]) for i, p in enumerate(path)]
        falls.append(flat_tube(sway, widths, 1.3, 10))
        for dx in (-0.22, 0.2):
            ribbon = []
            for i in range(2, len(sway) - 1):
                a, b = np.array(sway[i - 1]), np.array(sway[i + 1])
                tangent = (b - a) / (np.linalg.norm(b - a) + 1e-9)
                normal = np.cross(np.array([1.0, 0, 0]), tangent)
                normal /= np.linalg.norm(normal) + 1e-9
                across = (dx + 0.05 * math.sin(i * 0.9 + phase)) * widths[i]
                face = 0.65 * math.sqrt(max(0.0, 1 - (2 * across / widths[i]) ** 2))
                ribbon.append(np.array(sway[i]) + np.array([across, 0, 0]) + normal * (face + 0.1))
            crust.append(capped_tube([tuple(p) for p in ribbon], 0.28, 6))
        # A dark cave mouth around the source.
        cave = icosphere(1.0, 2).scale(width * 0.75, 2.4, 1.6).translate(x0, mouth + 0.6, stripe + 0.6)
        caves.append(cave)
    pieces["Basalt"] += caves
    pieces["Boulders"] = boulders
    out = {name: merge(*meshes) for name, meshes in pieces.items()}
    for mesh in out.values():
        mesh.smooth = False
    out["Lava"] = merge(*falls)
    out["Crust"] = merge(*crust)
    return out


def frustum(outline, y0, y1, s0, s1):
    """A closed band around a star-shaped outline (points in XZ round the middle), scaled s0 at its
    bottom and s1 at its top, with fan caps."""
    n = len(outline)
    verts = [(x * s0, y0, z * s0) for x, z in outline] + [(x * s1, y1, z * s1) for x, z in outline]
    verts += [(0.0, y0, 0.0), (0.0, y1, 0.0)]
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces += [(i, j, n + i), (j, n + j, n + i), (2 * n, j, i), (2 * n + 1, n + i, n + j)]
    return outward(Mesh(verts, faces, smooth=False))


def butte():
    """A far-off layered mesa for the plateau's skyline (cheap: about 600 triangles): stacked rock
    bands stepping in as they rise, a cream stripe, a flat top and a few boulders at its foot."""
    rng = np.random.default_rng(31)
    sides = 22
    outline = []
    for i in range(sides):
        a = 2 * math.pi * i / sides
        r = 1.0 + 0.12 * noise1(a * 30, 77, (1.0, 0.5), (0.07, 0.19)) + rng.uniform(-0.04, 0.04)
        outline.append((math.cos(a) * 40.0 * r, -math.sin(a) * 26.0 * r))
    bands = (
        ("RockLow", 0.0, 14.0, 1.0, 0.94),
        ("RockMid", 14.0, 24.0, 0.9, 0.84),
        ("Stripe", 24.0, 27.0, 0.83, 0.8),
        ("RockMid", 27.0, 33.0, 0.76, 0.72),
        ("RockTop", 33.0, 40.0, 0.68, 0.62),
    )
    pieces = {}
    for name, y0, y1, s0, s1 in bands:
        pieces.setdefault(name, []).append(frustum(outline, y0, y1, s0, s1))
    boulders = []
    for k in range(4):
        a = rng.uniform(0, 2 * math.pi)
        r = float(rng.uniform(3.5, 6.0))
        boulders.append(icosphere(r, 1, 0.3, seed=90 + k).scale(1.3, 0.8, 1.1).translate(math.cos(a) * 42, r * 0.4, -math.sin(a) * 28))
    out = {name: merge(*meshes) for name, meshes in pieces.items()}
    out["Boulders"] = merge(*boulders)
    for mesh in out.values():
        mesh.smooth = False
    return out


# ------------------------------------------------------------------------------ the bridge piers

PIER_TOP = 63.8  # the deck's underside sits 66 above the pier's foot (2 studs into the lava)
TOWER_X = 54.0
CABLE_TOP = 87.0


def pylon():
    """A stone viaduct pier under the bridge (an arch between two legs standing in the lava) carrying
    a rope tower on each end above the deck: timber frame on a stone block, a red roof, a lantern and
    a pennant. The swag ropes between towers are SkateCable. Faces -Z."""
    depth = 8.0
    # The pier's outline (with the arch opening), extruded through its depth.
    leg_out, leg_in_low, leg_in_top = 47.0, 33.5, 36.0
    spring, crown = 40.0, 53.0
    radius = (leg_in_top ** 2 + (crown - spring) ** 2) / (2 * (crown - spring))
    cy = crown - radius
    arc = []
    a0 = math.asin(leg_in_top / radius)
    for i in range(25):
        a = -a0 + 2 * a0 * i / 24
        arc.append((math.sin(a) * radius, cy + math.cos(a) * radius))
    # (the arc starts and ends at the springs, on the legs' inner faces)
    outline = [(-leg_out, 0.0), (-leg_in_low, 0.0)] + arc + [(leg_in_low, 0.0), (leg_out, 0.0), (leg_out - 2.0, PIER_TOP - 5.0),
                                                              (-(leg_out - 2.0), PIER_TOP - 5.0)]
    stone = [prism_xy(outline, -depth / 2, depth / 2)]
    trim, soot = [], []
    # Voussoirs standing proud of both faces around the opening.
    blocks = 13
    for i in range(blocks):
        t0, t1 = -a0 + 2 * a0 * (i + 0.06) / blocks, -a0 + 2 * a0 * (i + 0.94) / blocks
        inner = [(math.sin(t) * (radius - 0.3), cy + math.cos(t) * (radius - 0.3)) for t in (t0, t1)]
        outer = [(math.sin(t) * (radius + 3.6), cy + math.cos(t) * (radius + 3.6)) for t in (t1, t0)]
        trim.append(prism_xy(inner + outer, -depth / 2 - 0.45, depth / 2 + 0.45))
    # A cornice the deck rests on, reaching out under the towers, and a string course below it.
    trim.append(fbox(2 * (TOWER_X + 4.0), 5.0, depth + 2.4, 0, PIER_TOP - 2.5, 0))
    trim.append(fbox(2 * (leg_out - 1.4), 1.2, depth + 1.0, 0, PIER_TOP - 6.2, 0))
    # Brackets under the cornice's overhangs.
    for sx in (-1, 1):
        bracket = [(sx * (leg_out - 2.0), PIER_TOP - 5.0), (sx * (TOWER_X + 3.0), PIER_TOP - 5.0), (sx * (leg_out - 1.0), PIER_TOP - 14.0)]
        trim.append(prism_xy(bracket, -depth / 2 + 0.6, depth / 2 - 0.6))
    # Scorched footings where the legs meet the lava.
    for sx in (-1, 1):
        x = sx * (leg_out + leg_in_low) / 2
        soot.append(fbox(leg_out - leg_in_low + 2.4, 9.0, depth + 2.4, x, 4.5, 0))
        soot.append(fbox(leg_out - leg_in_low + 1.4, 1.4, depth + 1.4, x, 9.4, 0))
    # The towers.
    timber, roof, rope, flag, glow, iron = [], [], [], [], [], []
    for sx in (-1, 1):
        x = sx * TOWER_X
        base = PIER_TOP
        stone.append(fbox(6.4, 6.0, 6.4, x, base + 3.0, 0))
        trim.append(fbox(7.2, 0.9, 7.2, x, base + 6.2, 0))
        frame_top = CABLE_TOP + 1.0
        for px in (-1, 1):
            for pz in (-1, 1):
                timber.append(capped_tube([(x + px * 2.3, base + 6.6, pz * 2.3), (x + px * 1.5, frame_top, pz * 1.5)], 0.55, 8))
        for y in (base + 13.0, base + 19.0):
            k = 1 - (y - base - 6.6) / (frame_top - base - 6.6)
            w = 1.5 + 0.8 * k
            for pz in (-1, 1):
                timber.append(fbox(2 * w + 0.6, 0.6, 0.6, x, y, pz * w))
            for px in (-1, 1):
                timber.append(fbox(0.6, 0.6, 2 * w + 0.6, x + px * w, y, 0))
        # X braces on the two faces along the bridge.
        for px in (-1, 1):
            a, b = (x + px * 2.1, base + 7.0), (x + px * 1.75, base + 13.0)
            timber.append(capped_tube([(a[0], a[1], -2.1), (b[0], b[1], 2.0)], 0.22, 6))
            timber.append(capped_tube([(a[0], a[1], 2.1), (b[0], b[1], -2.0)], 0.22, 6))
        # The saddle the swag ropes run over, wrapped in rope.
        timber.append(fbox(4.6, 1.2, 4.6, x, frame_top + 0.4, 0))
        # Coils of spare rope hung on the stone block's faces.
        for pz in (-1, 1):
            rope.append(torus(1.3, 0.3, 16, 6).rotate("x", 90).translate(x, base + 3.4, pz * 3.55))
        # A pointed red roof with a pennant.
        roof.append(lathe([(0.0, 0.0), (3.9, 0.0), (0.0, 5.2)], 4).rotate("y", 45).translate(x, frame_top + 1.0, 0))
        iron.append(cylinder(0.14, 5.5, 8).translate(x, frame_top + 5.6, 0))
        iron.append(sphere(0.35, 6, 8).translate(x, frame_top + 11.2, 0))
        flag.append(extrude([(0.0, 0.0), (3.6, -0.9), (0.0, -1.8)], 0.08).translate(x, frame_top + 10.9, 0))
        # A lantern hanging under the lower cross beam, on the deck side.
        lx = x - sx * 2.6
        iron.append(capped_tube([(x - sx * 1.6, base + 13.0, 0.0), (lx, base + 13.0, 0.0), (lx, base + 11.6, 0.0)], 0.1, 6))
        iron.append(fbox(1.3, 0.25, 1.3, lx, base + 11.4, 0))
        iron.append(fbox(1.3, 0.25, 1.3, lx, base + 9.2, 0))
        glow.append(fbox(1.0, 2.0, 1.0, lx, base + 10.3, 0))
    out = {
        "Stone": merge(*stone),
        "Trim": merge(*trim),
        "Soot": merge(*soot),
        "Timber": merge(*timber),
        "Roof": merge(*roof),
        "Rope": merge(*rope),
        "Iron": merge(*iron),
        "Flag": merge(*flag),
        "Glow": merge(*glow),
    }
    for name in ("Stone", "Trim", "Soot", "Roof"):
        out[name].smooth = False
    return out


CABLE_SPAN = 96.0


def cable():
    """The rope swag from one tower top to the next (96 studs, stretched to fit) with hangers down to
    the bridge's rail. Its foot (y = 0) is the rail's top; the swag runs 4.6 studs further out."""
    top = CABLE_TOP - 66.0 - 3.6  # tower saddle above the rail's top
    out_x = TOWER_X - (DECK_WIDTH / 2 - 0.6)
    low = 3.2
    main = []
    n = 33
    for i in range(n):
        t = i / (n - 1)
        z = -CABLE_SPAN * t
        y = low + (top - low) * (2 * t - 1) ** 2
        main.append((out_x, y, z))
    rope = [capped_tube(main, 0.32, 8)]
    hangers = []
    count = 13
    for k in range(1, count):
        t = k / count
        z = -CABLE_SPAN * t
        y = low + (top - low) * (2 * t - 1) ** 2
        hangers.append(capped_tube([(out_x, y - 0.2, z), (0.25, 0.15, z)], 0.09, 5))
    return {"Rope": merge(*rope), "Hangers": merge(*hangers)}


# --------------------------------------------------------------------------------- start and finish


def start_gate():
    """The start gate over all twelve lanes: two stone-and-timber towers wrapped in green and white
    stripes, a big beam with a banner board, three start lamps in a black housing and flags."""
    half = DECK_WIDTH / 2 + 7.0
    stone, stripe_g, stripe_w, beam, banner, trim, housing, lamp_r, lamp_y, lamp_g, flag, iron = ([] for _ in range(12))
    height = 30.0
    for sx in (-1, 1):
        x = sx * half
        stone.append(box(9.0, 6.0, 9.0, 0.5, x, 3.0, 0, n=2))
        trim.append(box(9.8, 1.0, 9.8, 0.3, x, 6.3, 0, n=2))
        # A striped column: alternating green and white rings.
        rings = 9
        for k in range(rings):
            y0 = 6.8 + k * (height - 6.8 - 1.0) / rings
            h = (height - 6.8 - 1.0) / rings
            ring = box(6.2, h - 0.08, 6.2, 0.35, x, y0 + h / 2, 0, n=2)
            (stripe_g if k % 2 == 0 else stripe_w).append(ring)
        trim.append(box(7.6, 1.2, 7.6, 0.35, x, height - 0.4, 0, n=2))
        # A crown of four merlons and a flag.
        for mx in (-1, 1):
            for mz in (-1, 1):
                trim.append(box(1.8, 2.0, 1.8, 0.3, x + mx * 2.8, height + 1.0, mz * 2.8, n=2))
        iron.append(cylinder(0.18, 8.0, 8).translate(x, height, 0))
        flag.append(extrude([(0.0, 0.0), (-sx * 5.0, -1.3), (0.0, -2.6)], 0.1).translate(x, height + 7.8, 0))
    # The beam and banner between the towers.
    span = 2 * half - 6.0
    beam.append(box(span, 2.2, 2.6, 0.5, 0, height - 3.2, 0, n=2))
    beam.append(box(span, 1.4, 2.2, 0.4, 0, height - 13.4, 0, n=2))
    banner.append(box(span - 8.0, 8.0, 0.8, 0.3, 0, height - 8.3, 0, n=2))
    trim.append(box(span - 6.0, 0.7, 1.2, 0.2, 0, height - 4.0, 0, n=2))
    trim.append(box(span - 6.0, 0.7, 1.2, 0.2, 0, height - 12.6, 0, n=2))
    # The start lamps on top of the beam.
    housing.append(box(16.0, 6.4, 3.0, 0.8, 0, height + 1.4, 0, n=2))
    for k, bucket in enumerate((lamp_r, lamp_y, lamp_g)):
        x = (1 - k) * 5.0  # red on the left as seen from the front
        bucket.append(sphere(1.9, 10, 16).scale(1, 1, 0.55).translate(x, height + 1.6, -1.6))
        housing.append(box(4.4, 0.5, 1.6, 0.2, x, height + 3.9, -1.9, n=2))
    out = {
        "Stone": stone,
        "StripeA": stripe_g,
        "StripeB": stripe_w,
        "Beam": beam,
        "Banner": banner,
        "Trim": trim,
        "Housing": housing,
        "LampRed": lamp_r,
        "LampAmber": lamp_y,
        "LampGreen": lamp_g,
        "Flag": flag,
        "Iron": iron,
    }
    return {name: merge(*meshes) for name, meshes in out.items()}


def finish_arch():
    """The finish: a giant round stone arch over the goal with a checkered band round its face,
    a golden trophy on the keystone, fire bowls on its feet and pennants. Faces -Z."""
    inner, outer, depth = 54.0, 61.5, 8.0
    stone, stone_b, dark, light, gold, trim, bowl, coals, flag, iron = ([] for _ in range(10))
    blocks = 21
    for i in range(blocks):
        t0 = math.pi * (i + 0.04) / blocks
        t1 = math.pi * (i + 0.96) / blocks
        pts = [(math.cos(t) * inner, math.sin(t) * inner) for t in (t0, t1)]
        pts += [(math.cos(t) * outer, math.sin(t) * outer) for t in (t1, t0)]
        (stone if i % 2 == 0 else stone_b).append(prism_xy(pts, -depth / 2, depth / 2))
    # Mortar core behind the blocks' gaps, so the arch is never see-through.
    core = []
    for i in range(48):
        t0, t1 = math.pi * i / 48, math.pi * (i + 1) / 48
        pts = [(math.cos(t) * (inner + 0.5), math.sin(t) * (inner + 0.5)) for t in (t0, t1)]
        pts += [(math.cos(t) * (outer - 0.5), math.sin(t) * (outer - 0.5)) for t in (t1, t0)]
        core.append(prism_xy(pts, -depth / 2 + 0.5, depth / 2 - 0.5))
    trim += core
    # The checkered band on the front face: two rows of cells.
    cells = 36
    for row, (r0, r1) in enumerate(((inner + 1.0, inner + 3.7), (inner + 3.7, inner + 6.4))):
        for i in range(cells):
            t0, t1 = math.pi * (i + 0.02) / cells, math.pi * (i + 0.98) / cells
            pts = [(math.cos(t) * r0, math.sin(t) * r0) for t in (t0, t1)]
            pts += [(math.cos(t) * r1, math.sin(t) * r1) for t in (t1, t0)]
            cell = prism_xy(pts, -depth / 2 - 0.35, -depth / 2 + 0.2)
            (dark if (i + row) % 2 == 0 else light).append(cell)
    # Feet: stepped plinths with fire bowls.
    for sx in (-1, 1):
        x = sx * (inner + outer) / 2
        trim.append(box(outer - inner + 4.0, 3.0, depth + 4.0, 0.4, x, 1.5, 0, n=2))
        trim.append(box(outer - inner + 2.0, 1.4, depth + 2.0, 0.3, x, 3.7, 0, n=2))
        bx = x + sx * 0.0
        bowl.append(lathe([(0.0, 0.0), (1.4, 0.0), (1.6, 1.2), (3.2, 2.6), (3.4, 3.4), (2.9, 3.4), (2.7, 2.9), (0.0, 2.9)], 18).translate(bx, 4.4 + 6.0, -depth / 2 - 3.2))
        iron.append(cylinder(0.5, 6.0, 10).translate(bx, 4.4, -depth / 2 - 3.2))
        coals.append(sphere(2.6, 6, 12).scale(1, 0.35, 1).translate(bx, 4.4 + 6.0 + 3.1, -depth / 2 - 3.2))
    # The keystone with a golden trophy on top.
    trim.append(box(10.0, 9.0, depth + 1.6, 0.6, 0, outer + 2.0, 0, n=2))
    top = outer + 6.5
    gold.append(lathe([(0.0, 0.0), (3.6, 0.0), (3.6, 1.2), (2.4, 1.6), (1.0, 2.6), (0.8, 5.0), (1.4, 5.6), (4.4, 8.0), (5.4, 12.6),
                       (5.6, 13.6), (5.1, 13.6), (4.6, 12.6), (3.6, 9.0), (0.0, 8.4)], 24).translate(0, top, 0))
    for sx in (-1, 1):
        gold.append(torus(2.2, 0.45, 16, 8, 200).rotate("x", 90).rotate("z", -90 * sx + 90).translate(sx * 5.4, top + 10.4, 0))
    gold.append(sphere(1.2, 8, 12).translate(0, top + 15.0, 0))
    # Pennants along the arch's top.
    for i in (3, 6, 15, 18):
        t = math.pi * (i + 0.5) / blocks
        px, py = math.cos(t) * outer, math.sin(t) * outer
        iron.append(cylinder(0.16, 6.0, 8).translate(px, py - 0.5, 0))
        side = 1 if px < 0 else -1
        flag.append(extrude([(0.0, 0.0), (side * 3.4, -0.9), (0.0, -1.8)], 0.08).translate(px, py + 5.2, 0))
    out = {
        "Stone": stone,
        "StoneB": stone_b,
        "Trim": trim,
        "Dark": dark,
        "Light": light,
        "Gold": gold,
        "Bowl": bowl,
        "Coals": coals,
        "Flag": flag,
        "Iron": iron,
    }
    merged = {name: merge(*meshes) for name, meshes in out.items()}
    for name in ("Stone", "StoneB", "Trim", "Dark", "Light"):
        merged[name].smooth = False
    return merged


PROPS = {
    "SkateBoard": board,
    "SkateCrate": crate,
    "SkateBarrier": barrier,
    "SkateBoost": boost,
    "SkateDeck": deck,
    "SkateRail": rail,
    "SkateTorch": torch,
    "SkateCanyonWall": canyon_wall,
    "SkateButte": butte,
    "SkatePylon": pylon,
    "SkateCable": cable,
    "SkateStartGate": start_gate,
    "SkateFinishArch": finish_arch,
}
COLORS = {
    "Grip": (40, 40, 48),
    "Deck": (255, 120, 60),
    "Trucks": (190, 195, 205),
    "Wheels": (255, 230, 90),
    "Slats": (244, 192, 92),
    "Frame": (222, 62, 50),
    "Metal": (90, 92, 100),
    "Legs": (70, 70, 80),
    "Red": (235, 60, 60),
    "White": (250, 250, 250),
    "Lamp": (255, 170, 40),
    "Pad": (40, 36, 60),
    "Rim": (90, 80, 120),
    "Arrows": (255, 220, 60),
    "Planks": (158, 104, 68),
    "PlanksB": (124, 82, 56),
    "Beams": (96, 64, 44),
    "Bolts": (70, 70, 76),
    "CurbRed": (232, 64, 52),
    "CurbWhite": (250, 246, 236),
    "Posts": (110, 74, 48),
    "Rail": (130, 88, 56),
    "Rope": (222, 190, 132),
    "Hangers": (200, 168, 116),
    "Iron": (60, 58, 62),
    "Coals": (255, 120, 40),
    "Basalt": (66, 46, 54),
    "RockLow": (118, 50, 52),
    "RockMid": (176, 84, 72),
    "Stripe": (222, 150, 118),
    "RockTop": (150, 70, 64),
    "Boulders": (100, 56, 52),
    "Lava": (255, 140, 40),
    "Crust": (90, 40, 34),
    "Stone": (176, 160, 150),
    "Trim": (132, 116, 112),
    "Soot": (58, 46, 50),
    "Timber": (126, 82, 50),
    "Roof": (214, 64, 50),
    "Flag": (255, 210, 60),
    "Glow": (255, 200, 90),
    "StripeA": (60, 190, 100),
    "StripeB": (250, 250, 245),
    "Beam": (120, 78, 48),
    "Banner": (40, 150, 80),
    "Housing": (34, 32, 40),
    "LampRed": (255, 70, 60),
    "LampAmber": (255, 190, 50),
    "LampGreen": (80, 255, 120),
    "StoneB": (196, 180, 166),
    "Dark": (30, 30, 36),
    "Light": (250, 250, 250),
    "Gold": (255, 200, 60),
    "Bowl": (70, 66, 72),
}
