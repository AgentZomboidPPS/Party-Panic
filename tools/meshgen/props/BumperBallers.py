"""Meshes for Bumper Ballers (see tools/meshgen/props/README.md). Units are studs, +Y up, base on
y = 0, -Z is the front.

    python3 tools/meshgen/generate_meshes.py --only BumperBallGores,BumperBallBands,BumperBallDots,BumperIsland,BumperPalm,BumperIslet

The balls are one sphere split into two pieces along the pattern (Shell takes the rider's color,
Pattern stays white), so the pieces share edges and never overlap. The island's top is a grass
cylinder in the game (it's also the collider); this mesh is the sand ring with a striped warning
lip cut into its top, the rocky cliff into the sea, surf rocks and a foam line.
"""

import math

import numpy as np

from generate_meshes import Mesh, cylinder, extrude, icosphere, lathe, merge, organic_lathe, sphere, taper, torus, tube, weld

BALL_RADIUS = 4.0
GRASS_TOP = 13.85  # island mesh: the grass cylinder's top in mesh coordinates
WATER = GRASS_TOP - 5.0


def split(mesh: Mesh, mask: np.ndarray) -> tuple[Mesh, Mesh]:
    """Two meshes from one: faces where mask is True, and the rest (vertices re-indexed)."""
    out = []
    for keep in (mask, ~mask):
        faces = mesh.f[keep]
        used, inverse = np.unique(faces.reshape(-1), return_inverse=True)
        out.append(Mesh(mesh.v[used], inverse.reshape(-1, 3), mesh.smooth))
    return out[0], out[1]


def face_centers(mesh: Mesh) -> np.ndarray:
    return mesh.v[mesh.f].mean(axis=1)


# ---------------------------------------------------------------------------------------- balls

def ball_sphere() -> Mesh:
    # 36 rings (5 degrees each) and 72 segments, so stripes and gores fall on edges.
    return sphere(BALL_RADIUS, 36, 72)


def ball_gores():
    """A beach ball: eight gores, alternating rider color and white, with white caps."""
    mesh = ball_sphere()
    c = face_centers(mesh)
    lon = np.arctan2(c[:, 2], c[:, 0])
    lat = np.arcsin(np.clip(c[:, 1] / BALL_RADIUS, -1, 1))
    gore = np.floor((lon + math.pi) / (2 * math.pi / 8)).astype(int) % 2 == 0
    cap = np.abs(lat) > math.radians(72)
    pattern, shell = split(mesh, gore | cap)
    return {"Shell": shell.translate(0, BALL_RADIUS, 0), "Pattern": pattern.translate(0, BALL_RADIUS, 0)}


def ball_bands():
    """Two wide white bands and a white cap on each pole."""
    mesh = ball_sphere()
    c = face_centers(mesh)
    lat = np.degrees(np.arcsin(np.clip(c[:, 1] / BALL_RADIUS, -1, 1)))
    band = ((np.abs(lat) > 15) & (np.abs(lat) < 35)) | (np.abs(lat) > 70)
    pattern, shell = split(mesh, band)
    return {"Shell": shell.translate(0, BALL_RADIUS, 0), "Pattern": pattern.translate(0, BALL_RADIUS, 0)}


def ball_dots():
    """Twelve big polka dots (one at each corner of an icosahedron)."""
    mesh = weld(icosphere(BALL_RADIUS, 4))
    c = face_centers(mesh)
    c = c / np.linalg.norm(c, axis=1, keepdims=True)
    t = (1 + math.sqrt(5)) / 2
    corners = np.array([(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
                        (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)], dtype=float)
    corners /= np.linalg.norm(corners, axis=1, keepdims=True)
    nearest = (c @ corners.T).max(axis=1)
    dot = nearest > math.cos(0.36)
    pattern, shell = split(mesh, dot)
    return {"Shell": shell.translate(0, BALL_RADIUS, 0), "Pattern": pattern.translate(0, BALL_RADIUS, 0)}


# --------------------------------------------------------------------------------------- island

def island():
    segments = 192  # 48 stripes x 4: stripe ends fall on segment edges
    # Sand: from just under the water up over a rounded lip, across the top to an inner edge that
    # tucks under the grass. Listed outside-in so the top faces up.
    sand = organic_lathe([
        (46.6, WATER - 0.8), (46.1, WATER + 1.5), (45.6, GRASS_TOP - 1.4), (45.1, GRASS_TOP - 0.45),
        (44.6, GRASS_TOP + 0.05), (44.1, GRASS_TOP + 0.15), (43.9, GRASS_TOP + 0.15), (40.9, GRASS_TOP + 0.15),
        (38.4, GRASS_TOP + 0.15), (37.9, GRASS_TOP + 0.08), (37.6, GRASS_TOP - 0.4),
    ], segments, 0.012, waves=9, seed=3)
    # The warning lip: a ring of red and white stripes in the sand's own top (no overlapping faces).
    c = face_centers(sand)
    radius = np.hypot(c[:, 0], c[:, 2])
    angle = np.arctan2(c[:, 2], c[:, 0])
    lip = (radius > 40.8) & (radius < 44.2) & (c[:, 1] > GRASS_TOP + 0.14)
    red = lip & (np.floor((angle + math.pi) / (2 * math.pi / 48)).astype(int) % 2 == 0)
    stripe_red, rest = split(sand, red)
    c = face_centers(rest)
    radius = np.hypot(c[:, 0], c[:, 2])
    white = (radius > 40.8) & (radius < 44.2) & (c[:, 1] > GRASS_TOP + 0.14)
    stripe_white, sand = split(rest, white)

    # Cliff: weathered rock from the sea bed up to the sand.
    cliff = organic_lathe([
        (55.0, 0.0), (52.5, 2.2), (50.0, 4.6), (48.4, 6.8), (47.4, WATER - 0.4), (46.8, WATER + 1.0),
        (46.1, WATER + 2.6), (45.7, GRASS_TOP - 1.6), (44.0, GRASS_TOP - 2.0), (30.0, GRASS_TOP - 2.2),
    ], segments, 0.035, waves=13, seed=7)
    # The sea-bed ring stays perfectly round, so the mesh's bounds (and its pivot) are centered.
    base = cliff.v[:, 1] < 1e-6
    angles = np.arctan2(cliff.v[base, 2], cliff.v[base, 0])
    cliff.v[base, 0] = np.cos(angles) * 55.0
    cliff.v[base, 2] = np.sin(angles) * 55.0
    rng = np.random.default_rng(5)
    rocks = []
    for k in range(18):
        a = k / 18 * 2 * math.pi + rng.uniform(-0.12, 0.12)
        r = rng.uniform(46.8, 50.5)
        size = rng.uniform(0.9, 2.1)
        rock = icosphere(size, 1, noise=0.45, seed=int(k + 20)).scale(1.2, 0.8, 1.0)
        rocks.append(rock.translate(math.cos(a) * r, WATER - 0.3 + rng.uniform(-0.2, 0.5), math.sin(a) * r))
    rock_mesh = merge(*rocks)
    rock_mesh.smooth = False
    cliff_rock = merge(cliff, rock_mesh)
    cliff_rock.smooth = False

    # A soft foam line where the surf meets the sand.
    foam = torus(47.0, 0.55, 120, 8).scale(1, 0.25, 1).translate(0, WATER + 0.08, 0)
    return {"Sand": sand, "StripeRed": stripe_red, "StripeWhite": stripe_white, "Rock": cliff_rock, "Foam": foam}


# ---------------------------------------------------------------------------------------- palms

def frond(length: float, droop: float, width: float, yaw: float, pitch: float) -> Mesh:
    """One palm frond: a folded, serrated leaf that arches out and droops, with some thickness."""
    steps = 18
    verts, faces = [], []
    for i in range(steps + 1):
        t = i / steps
        # Arch: rises a little, then droops.
        x = t * length
        y = math.sin(pitch) * x - droop * t * t * length * 0.5
        w = width * math.sin(math.pi * min(1.0, t * 1.15)) * (0.75 if i % 2 else 1.0)
        fold = 0.18 * w
        for side in (-1, 0, 1):
            verts.append((x, y + (fold if side == 0 else 0.0), side * w))
    for i in range(steps):
        a = i * 3
        b = a + 3
        faces += [(a, b, a + 1), (a + 1, b, b + 1), (a + 1, b + 1, a + 2), (a + 2, b + 1, b + 2)]
    # The upper sheet faces up and the lower one down, so each side shows its lit face (the other
    # way round, the top's culled back would still shade the leaf from above).
    top = Mesh(verts, np.array(faces)[:, ::-1])
    bottom = Mesh(np.array(verts) - np.array([0, 0.06, 0]), np.array(faces))
    leaf = merge(top, bottom)
    leaf.rotate("y", yaw)
    return leaf


def palm():
    # A gently curved trunk with bark rings.
    points = []
    for i in range(31):
        t = i / 30
        points.append((2.6 * t * t, 15.0 * t, 0.6 * math.sin(t * 2.0)))
    trunk = taper(points, 0.75, 0.42, 10)
    for i in range(len(points)):
        if i % 3 == 2:
            ring = slice(i * 10, (i + 1) * 10)
            p = np.array(points[i])
            trunk.v[ring] = p + (trunk.v[ring] - p) * 1.13
    crown = np.array(points[-1])
    fronds = []
    for k in range(11):
        yaw = k * (360 / 11) + (8 if k % 2 else -6)
        length = 9.0 if k % 2 else 10.5
        fronds.append(frond(length, 2.3, 1.45, yaw, math.radians(30 if k % 2 else 16)))
    for k in range(5):  # young fronds pointing up
        fronds.append(frond(5.5, 0.5, 0.9, k * 72 + 36, math.radians(58)))
    leaves = merge(*fronds).translate(*crown)
    nuts = merge(*[sphere(0.55, 8, 12).translate(crown[0] + math.cos(a) * 0.65, crown[1] - 0.55, crown[2] + math.sin(a) * 0.65)
                   for a in (0.3, 2.4, 4.4)])
    base = organic_lathe([(1.15, 0.0), (0.95, 0.4), (0.78, 1.0), (0.0, 1.0)], 12, 0.08, seed=2)
    return {"Trunk": merge(trunk, base), "Leaves": leaves, "Coconuts": nuts}


def islet():
    profile = [(10.5, 0.0), (9.5, 0.9), (7.6, 2.1), (5.0, 2.9), (2.4, 3.2), (0.0, 3.25)]
    sand = organic_lathe(profile, 40, 0.08, waves=5, seed=9)
    radii, heights = [p[0] for p in profile][::-1], [p[1] for p in profile][::-1]
    rng = np.random.default_rng(12)
    rocks = []
    for k in range(4):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(6.5, 9.0)
        rocks.append(icosphere(rng.uniform(0.9, 1.7), 1, noise=0.45, seed=40 + k).scale(1.2, 0.85, 1).translate(math.cos(a) * r, 1.6, math.sin(a) * r))
    rock = merge(*rocks)
    rock.smooth = False
    tufts = []
    for k in range(5):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(1.5, 4.5)
        tufts.append(icosphere(rng.uniform(0.5, 0.8), 1, noise=0.3, seed=60 + k).scale(1.3, 0.7, 1.3).translate(math.cos(a) * r, float(np.interp(r, radii, heights)) - 0.15, math.sin(a) * r))
    return {"Sand": sand, "Rock": rock, "Grass": merge(*tufts)}



# -------------------------------------------------------------------------------- party dressing

def face_up(mesh: Mesh) -> Mesh:
    """Turns every face of an open height-field surface to face up (seen from above)."""
    tri = mesh.v[mesh.f]
    n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    down = n[:, 1] < 0
    mesh.f[down] = mesh.f[down][:, ::-1]
    return mesh


def polar_field(height, radius_x: float, radius_z: float, rings, segments: int) -> Mesh:
    """A height-field disc: height(r, angle) with r from 0 (middle) to 1 (rim), faces up. `rings` is a
    ring count (evenly spaced) or the list of ring radii (0 < r <= 1, increasing)."""
    radii = [i / rings for i in range(1, rings + 1)] if isinstance(rings, int) else list(rings)
    rings = len(radii)
    verts = [(0.0, height(0.0, 0.0), 0.0)]
    for i in range(1, rings + 1):
        r = radii[i - 1]
        for s in range(segments):
            a = 2 * math.pi * s / segments
            verts.append((math.cos(a) * r * radius_x, height(r, a), math.sin(a) * r * radius_z))
    faces = [(0, 1 + (s + 1) % segments, 1 + s) for s in range(segments)]
    for i in range(rings - 1):
        a0 = 1 + i * segments
        a1 = a0 + segments
        for s in range(segments):
            t = (s + 1) % segments
            faces += [(a0 + s, a0 + t, a1 + s), (a0 + t, a1 + t, a1 + s)]
    return face_up(Mesh(verts, faces))


def blob(radius: float, seed: int, squash=(1.0, 1.0, 1.0), noise: float = 0.35, subdivisions: int = 1) -> Mesh:
    return icosphere(radius, subdivisions, noise=noise, seed=seed).scale(*squash)


def bar(x0, y0, z0, x1, y1, z1) -> Mesh:
    """A box from (x0, y0, z0) to (x1, y1, z1), flat shaded, faces out."""
    w, h = abs(x1 - x0), abs(y1 - y0)
    box = extrude([(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)], abs(z1 - z0))
    return box.translate((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)


def lagoon():
    """The sea floor around the island: a pale sand shelf with a wavy edge, a turquoise reef slope
    and deep blue beyond, so the water reads shallow-to-deep (Roblox has no depth fog under water).
    Base on y = 0 is the outer rim (15.2 under the water); the shelf is 4.5 under it."""
    rng = np.random.default_rng(31)
    phases = rng.uniform(0, 2 * math.pi, 4)

    def edge(a):
        return 92 + 9 * math.sin(3 * a + phases[0]) + 5 * math.sin(7 * a + phases[1]) + 3 * math.sin(13 * a + phases[2])

    def height(r, a):
        d = r * 150
        e = edge(a)
        if d < e - 14:
            return 10.7 - 0.35 * math.sin(d * 0.25 + 2 * a)  # ripples on the shelf
        if d < e + 14:
            t = (d - (e - 14)) / 28
            return 10.7 - (10.7 - 1.2) * (3 * t * t - 2 * t * t * t)
        return 1.2 * max(0.0, 1 - (d - e - 14) / 30)

    # Rings are dense across the reef slope (where the colors change), sparse under the island.
    distances = [15, 30, 45, 55] + [60 + 1.5 * k for k in range(49)] + [136, 141, 146, 150]
    field = polar_field(height, 150, 150, [d / 150 for d in distances], 240)
    c = face_centers(field)
    deep = c[:, 1] < 3.0
    reef = (c[:, 1] < 8.8) & ~deep
    deep_part, rest = split(field, deep)
    c = face_centers(rest)
    reef_part, shelf = split(rest, (c[:, 1] < 8.8))
    corals = []
    for k in range(16):
        a = k / 16 * 2 * math.pi + rng.uniform(-0.15, 0.15)
        d = rng.uniform(62, edge(a) - 10)
        y = height(d / 150, a)
        corals.append(blob(rng.uniform(1.3, 2.4), 70 + k, (1.3, 0.55, 1.0)).translate(math.cos(a) * d, y + 0.2, math.sin(a) * d))
    coral = merge(*corals)
    coral.smooth = False
    return {"Shelf": shelf, "Reef": reef_part, "Deep": deep_part, "Coral": coral}


def float_line():
    """A ring of lane-rope floats around the island (radius 70): groups of red and white beads
    on a rope. The edge of the play area reads from far away."""
    radius = 70.0
    count = 220
    red, white = [], []
    for k in range(count):
        a = k / count * 2 * math.pi
        bead = sphere(0.45, 5, 8).scale(1.0, 0.95, 1.0)
        bead.v[:, 0] *= 1.45  # long along the rope
        bead.rotate("y", -math.degrees(a) - 90)
        bead.translate(math.cos(a) * radius, 0.45, math.sin(a) * radius)
        (red if (k // 5) % 2 == 0 else white).append(bead)
    rope = torus(radius, 0.08, 220, 4).translate(0, 0.45, 0)
    return {"FloatRed": merge(*red), "FloatWhite": merge(*white), "Rope": rope}


def buoy():
    """A channel buoy: red and white float, a little cage mast and a lamp. Water line at y = 1.4."""
    body = lathe([(0.0, 0.0), (0.7, 0.15), (1.35, 0.9), (1.55, 1.4), (1.6, 2.2), (1.55, 3.0), (1.3, 3.5),
                  (0.6, 3.8), (0.0, 3.85)], 24)
    c = face_centers(body)
    band = (c[:, 1] > 2.05) & (c[:, 1] < 2.95)
    white, red = split(body, band)
    legs = []
    for k in range(3):
        a = k / 3 * 2 * math.pi
        legs.append(tube([(math.cos(a) * 0.55, 3.6, math.sin(a) * 0.55), (math.cos(a) * 0.25, 5.4, math.sin(a) * 0.25)], 0.09, 6))
    ring = torus(0.42, 0.07, 16, 6).translate(0, 4.6, 0)
    cap = cylinder(0.42, 0.18, 12).translate(0, 5.35, 0)
    lamp = lathe([(0.0, 5.5), (0.3, 5.55), (0.32, 5.85), (0.2, 6.1), (0.0, 6.15)], 12)
    return {"Red": red, "White": white, "Metal": merge(*legs, ring, cap), "Lamp": lamp}


def flamingo():
    """A pink flamingo pool float: ring body, S-curved neck, head and a black-tipped beak. Front -Z."""
    ring = torus(1.7, 0.75, 36, 14).translate(0, 0.75, 0)
    neck_pts = []
    for i in range(13):
        t = i / 12
        neck_pts.append((0.0, 1.2 + 3.3 * t, -1.9 + 0.9 * math.sin(t * math.pi * 1.1) - 0.5 * t))
    neck = taper(neck_pts, 0.42, 0.3, 10)
    head = sphere(0.55, 10, 14).scale(0.9, 0.85, 1.15).translate(0, 4.65, -2.2)
    tail = taper([(0, 1.1, 1.9), (0, 1.9, 2.4), (0, 2.3, 2.6)], 0.45, 0.1, 8)
    beak = taper([(0, 4.6, -2.75), (0, 4.4, -3.25), (0, 4.0, -3.4)], 0.22, 0.06, 8)
    eyes = merge(sphere(0.1, 6, 8).translate(0.42, 4.8, -2.4), sphere(0.1, 6, 8).translate(-0.42, 4.8, -2.4))
    return {"Pink": merge(ring, neck, head, tail), "Beak": merge(beak, eyes)}


def donut_float():
    """A frosted donut pool float with sprinkles."""
    dough = torus(1.75, 0.8, 40, 16).translate(0, 0.8, 0)
    c = face_centers(dough)
    angle = np.arctan2(c[:, 2], c[:, 0])
    frosting_mask = c[:, 1] > 0.95 + 0.18 * np.sin(angle * 9)
    frosting, dough_part = split(dough, frosting_mask)
    frosting.v[:, 1] += 0.0
    rng = np.random.default_rng(4)
    sprinkles = []
    for k in range(34):
        a = rng.uniform(0, 2 * math.pi)
        b = rng.uniform(math.radians(35), math.radians(145))
        r = 1.75 + math.cos(b) * 0.82
        y = 0.8 + math.sin(b) * 0.82
        s = bar(-0.22, -0.05, -0.06, 0.22, 0.05, 0.06).rotate("y", rng.uniform(0, 180))
        sprinkles.append(s.translate(math.cos(a) * r, y + 0.02, math.sin(a) * r))
    return {"Dough": dough_part, "Frosting": frosting, "Sprinkles": merge(*sprinkles)}


def lifebuoy():
    """A red and white life ring."""
    ring = torus(1.5, 0.45, 48, 12).translate(0, 0.45, 0)
    c = face_centers(ring)
    angle = np.arctan2(c[:, 2], c[:, 0])
    white = np.floor((angle + math.pi) / (2 * math.pi / 8)).astype(int) % 2 == 0
    white_part, red_part = split(ring, white)
    rope = torus(1.97, 0.06, 48, 5).translate(0, 0.45, 0)
    return {"Red": red_part, "White": white_part, "Rope": rope}


def thatch_tier(half_x: float, half_z: float, y0: float, y1: float, droop: float, seed: int) -> Mesh:
    """A four-sided thatched roof tier with a ragged fringe (a closed shape, faces out)."""
    roof = lathe([(0.0, y0 + 0.25), (1.0, y0), (1.0, y0 + 0.45), (0.0, y1)], 4 * 6)
    # Square it up: push each vertex onto a square of the same angle, then stretch to the footprint.
    angle = np.arctan2(roof.v[:, 2], roof.v[:, 0])
    radius = np.hypot(roof.v[:, 0], roof.v[:, 2])
    square = radius / np.maximum(np.abs(np.cos(angle)), np.abs(np.sin(angle)))
    roof.v[:, 0] = np.cos(angle) * square * half_x
    roof.v[:, 2] = np.sin(angle) * square * half_z
    rng = np.random.default_rng(seed)
    fringe = roof.v[:, 1] < y0 + 0.5
    roof.v[fringe, 1] -= droop * rng.uniform(0.0, 1.0, fringe.sum())
    roof.smooth = False
    return roof


def tiki_bar():
    """A beach bar: a plank deck on stilts, bamboo posts and counter, a two-tier thatched roof,
    a bottle shelf and stools. Front (the counter) faces -Z. Deck top at y = 1.5."""
    deck_top = 1.5
    planks = []
    for k in range(14):
        x0 = -7.0 + k * 1.0
        planks.append(bar(x0 + 0.04, deck_top - 0.35, -6.5, x0 + 0.96, deck_top, 5.0))
    stilts = [cylinder(0.32, deck_top, 8).translate(x, 0, z) for x in (-6.4, 0, 6.4) for z in (-6.0, 4.5)]
    posts = [cylinder(0.32, 8.2, 10).translate(x, deck_top, z) for x in (-5.2, 5.2) for z in (-2.6, 4.0)]
    slats = [cylinder(0.24, 3.0, 8).translate(-4.6 + k * 0.575, deck_top, -3.3) for k in range(17)]
    counter = bar(-5.1, deck_top + 3.0, -4.3, 5.1, deck_top + 3.35, -2.4)
    shelf = bar(-4.5, deck_top + 2.2, 3.3, 4.5, deck_top + 2.4, 4.1)
    shelf2 = bar(-4.5, deck_top + 3.6, 3.3, 4.5, deck_top + 3.8, 4.1)
    back = bar(-5.0, deck_top, 4.15, 5.0, deck_top + 4.6, 4.35)
    bottles = []
    rng = np.random.default_rng(8)
    for row, y in ((0, deck_top + 2.4), (1, deck_top + 3.8)):
        for k in range(9):
            x = -4.0 + k * 1.0 + rng.uniform(-0.15, 0.15)
            h = rng.uniform(0.8, 1.15)
            bottles.append(lathe([(0.0, 0.0), (0.2, 0.0), (0.22, h * 0.6), (0.09, h * 0.8), (0.08, h), (0.0, h)], 8).translate(x, y, 3.7))
    stools = []
    for x in (-3.2, 0.0, 3.2):
        stools.append(cylinder(0.65, 0.3, 12, 0.1).translate(x, deck_top + 2.1, -5.3))
    stool_legs = [cylinder(0.13, 2.1, 6).translate(x, deck_top, -5.3) for x in (-3.2, 0.0, 3.2)]
    cups = []
    for x in (-3.0, 0.2, 3.1):
        cups.append(lathe([(0.0, 0.0), (0.28, 0.02), (0.36, 0.35), (0.3, 0.55), (0.0, 0.55)], 10).translate(x, deck_top + 3.35, -3.4))
    straws = [taper([(x + 0.1, deck_top + 3.8, -3.4), (x + 0.35, deck_top + 4.5, -3.55)], 0.05, 0.05, 5) for x in (-3.0, 0.2, 3.1)]
    roof = merge(thatch_tier(7.4, 6.4, deck_top + 7.9, deck_top + 10.6, 0.5, 1), thatch_tier(4.2, 3.6, deck_top + 9.9, deck_top + 12.4, 0.35, 2))
    sign = bar(-3.6, deck_top + 7.3, -6.75, 3.6, deck_top + 8.6, -6.45)
    sign.smooth = False
    # A pink wave across the teal board, with a dot at each end (no text, nothing to translate).
    mid = deck_top + 7.95
    wave_points = [(-2.9 + k * 0.29, mid + 0.22 * math.sin(k * 0.29 * 2.2), -6.8) for k in range(21)]
    wave = taper(wave_points, 0.13, 0.13, 6)
    dots = [sphere(0.24, 6, 10).translate(x, mid, -6.78) for x in (-3.25, 3.25)]
    sign_posts = [cylinder(0.12, 1.0, 6).translate(x, deck_top + 7.5, -6.3) for x in (-2.8, 2.8)]
    wood = merge(*planks, counter, shelf, shelf2, back, *stools)
    wood.smooth = False
    bamboo = merge(*stilts, *posts, *slats, *stool_legs, *sign_posts)
    return {
        "Wood": wood,
        "Bamboo": bamboo,
        "Thatch": roof,
        "Bottles": merge(*bottles),
        "Cups": merge(*cups, *straws),
        "Sign": sign,
        "SignWave": merge(wave, *dots),
    }


def tiki_totem():
    """A carved tiki statue: a fat column with a big grinning face, crowned with leaves. Front -Z."""
    body = organic_lathe([(0.0, 0.0), (1.25, 0.0), (1.3, 1.5), (1.15, 3.0), (1.35, 4.6), (1.3, 6.0), (1.0, 6.4),
                          (0.0, 6.45)], 20, 0.03, waves=4, seed=11)
    body.smooth = False
    brow = bar(-1.0, 4.7, -1.55, 1.0, 5.05, -1.05)
    eyes = merge(*[lathe([(0.0, 0.0), (0.42, 0.0), (0.42, 0.3), (0.0, 0.3)], 14).rotate("x", -90).translate(x, 4.25, -1.05) for x in (-0.5, 0.5)])
    pupils = merge(*[sphere(0.17, 6, 8).translate(x, 4.25, -1.42) for x in (-0.5, 0.5)])
    nose = taper([(0, 4.2, -1.2), (0, 3.6, -1.45)], 0.18, 0.32, 8)
    mouth = bar(-0.85, 2.6, -1.5, 0.85, 3.2, -1.0)
    teeth = merge(*[bar(-0.7 + k * 0.36, 2.7, -1.56, -0.42 + k * 0.36, 3.05, -1.45) for k in range(5)])
    leaves = []
    for k in range(7):
        leaves.append(frond(2.6, 1.0, 0.6, k * (360 / 7), math.radians(55)))
    crown = merge(*leaves).translate(0, 6.35, 0)
    return {"Wood": merge(body, nose), "Paint": merge(brow, mouth), "Eyes": merge(eyes), "Teeth": merge(pupils, teeth), "Leaves": crown}


def tiki_torch():
    """A bamboo tiki torch with a woven bowl and a flame."""
    pole = cylinder(0.16, 6.0, 8)
    bands = [torus(0.19, 0.05, 10, 5).translate(0, y, 0) for y in (1.4, 2.9, 4.4)]
    bowl = lathe([(0.0, 5.8), (0.3, 5.85), (0.55, 6.3), (0.62, 6.75), (0.0, 6.7)], 12)
    flame = lathe([(0.0, 6.6), (0.45, 6.75), (0.5, 7.2), (0.32, 7.8), (0.12, 8.3), (0.0, 8.55)], 10)
    flame.v[:, 0] += (flame.v[:, 1] - 6.6) ** 2 * 0.04
    return {"Bamboo": merge(pole, *bands), "Bowl": bowl, "Flame": flame}


def parasol():
    """A striped beach umbrella, tilted a little."""
    canopy = lathe([(0.0, 5.7), (1.2, 5.65), (3.4, 5.15), (3.45, 5.3), (1.2, 6.05), (0.0, 6.45)], 32)
    c = face_centers(canopy)
    angle = np.arctan2(c[:, 2], c[:, 0])
    stripe = np.floor((angle + math.pi) / (2 * math.pi / 8)).astype(int) % 2 == 0
    a_part, b_part = split(canopy, stripe)
    pole = merge(cylinder(0.09, 6.7, 8), sphere(0.16, 6, 8).translate(0, 6.6, 0))
    pieces = {"CanopyA": a_part, "CanopyB": b_part, "Pole": pole}
    for mesh in pieces.values():
        mesh.rotate("x", 8)
    return pieces


def far_island(seed: int, peaks):
    """A big tropical island for the horizon: jungle hills, rocky peaks, a beach at the water line
    (y = 6). Faces up; its rim tucks under the sea."""
    rng = np.random.default_rng(seed)
    phases = rng.uniform(0, 2 * math.pi, 6)

    def height(r, a):
        shore = 1 + 0.12 * math.sin(3 * a + phases[0]) + 0.06 * math.sin(7 * a + phases[1])
        x, z = math.cos(a) * r, math.sin(a) * r
        h = 0.0
        for px, pz, ph, pw in peaks:
            h += ph * math.exp(-((x - px) ** 2 + (z - pz) ** 2) / (pw * pw))
        h *= 1 + 0.16 * math.sin(11 * a + phases[4]) + 0.08 * math.sin(23 * a + phases[5])  # ridges and gullies
        h += 2.5 * math.sin(x * 9 + phases[2]) * math.sin(z * 8 + phases[3])
        rim = min(1.0, max(0.0, (shore - r) / 0.18))
        beach = 8.0 * (1 - math.exp(-((shore - r) * 12) ** 2 if r < shore else 1)) if r < shore else 0.0
        return max(0.0, rim * (h + 8.0) * (1 - r ** 6) + beach * (1 - rim) - (0 if r < shore else (r - shore) * 40))

    field = polar_field(height, 100, 70, 40, 96)
    tri = field.v[field.f]
    n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-9
    c = tri.mean(axis=1)
    sand = c[:, 1] < 8.6
    sand_part, rest = split(field, sand)
    tri = rest.v[rest.f]
    n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-9
    c = tri.mean(axis=1)
    rock_part, jungle = split(rest, (n[:, 1] < 0.45) & (c[:, 1] > 40.0) | (c[:, 1] > 82.0))
    rock_part.smooth = False
    return {"Sand": sand_part, "Jungle": jungle, "Rock": rock_part}


def far_island_a():
    return far_island(3, [(-0.2, 0.0, 60.0, 0.35), (0.3, 0.15, 38.0, 0.3), (0.0, -0.3, 22.0, 0.35)])


def far_island_b():
    return far_island(9, [(-0.35, 0.05, 40.0, 0.3), (0.05, -0.05, 46.0, 0.3), (0.42, 0.1, 34.0, 0.28), (-0.1, -0.35, 16.0, 0.3)])


PROPS = {
    "BumperBallGores": ball_gores,
    "BumperBallBands": ball_bands,
    "BumperBallDots": ball_dots,
    "BumperIsland": island,
    "BumperPalm": palm,
    "BumperIslet": islet,
    "BumperLagoon": lagoon,
    "BumperFloatLine": float_line,
    "BumperBuoy": buoy,
    "BumperFlamingo": flamingo,
    "BumperDonutFloat": donut_float,
    "BumperLifebuoy": lifebuoy,
    "BumperTikiBar": tiki_bar,
    "BumperTikiTotem": tiki_totem,
    "BumperTikiTorch": tiki_torch,
    "BumperParasol": parasol,
    "BumperFarIslandA": far_island_a,
    "BumperFarIslandB": far_island_b,
}
COLORS = {
    "Shell": (240, 70, 70),
    "Pattern": (248, 248, 248),
    "Sand": (240, 222, 165),
    "StripeRed": (230, 60, 60),
    "StripeWhite": (250, 250, 250),
    "Rock": (125, 118, 112),
    "Foam": (245, 252, 255),
    "Trunk": (150, 110, 70),
    "Leaves": (70, 170, 70),
    "Coconuts": (110, 75, 40),
    "Grass": (90, 180, 80),
    "Shelf": (170, 235, 215),
    "Reef": (70, 195, 195),
    "Deep": (30, 110, 160),
    "Coral": (255, 120, 140),
    "FloatRed": (235, 60, 60),
    "FloatWhite": (250, 250, 250),
    "Rope": (240, 240, 230),
    "Red": (235, 55, 55),
    "White": (250, 250, 250),
    "Metal": (70, 72, 80),
    "Lamp": (255, 220, 90),
    "Pink": (255, 130, 180),
    "Beak": (40, 40, 45),
    "Dough": (230, 175, 110),
    "Frosting": (255, 140, 200),
    "Sprinkles": (90, 200, 255),
    "Wood": (160, 105, 60),
    "Bamboo": (215, 190, 110),
    "Thatch": (220, 180, 100),
    "Bottles": (60, 190, 160),
    "Cups": (255, 190, 60),
    "Sign": (70, 200, 210),
    "SignWave": (255, 110, 170),
    "Paint": (230, 70, 50),
    "Eyes": (250, 245, 230),
    "Teeth": (40, 30, 30),
    "Bowl": (120, 80, 45),
    "Flame": (255, 150, 40),
    "CanopyA": (255, 90, 120),
    "CanopyB": (255, 245, 225),
    "Pole": (240, 240, 240),
    "Jungle": (60, 150, 75),
}
