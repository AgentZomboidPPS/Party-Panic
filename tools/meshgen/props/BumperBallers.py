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

from generate_meshes import Mesh, icosphere, lathe, merge, organic_lathe, sphere, taper, torus, weld

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
    top = Mesh(verts, faces)
    bottom = Mesh(np.array(verts) - np.array([0, 0.06, 0]), np.array(faces)[:, ::-1])
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


PROPS = {
    "BumperBallGores": ball_gores,
    "BumperBallBands": ball_bands,
    "BumperBallDots": ball_dots,
    "BumperIsland": island,
    "BumperPalm": palm,
    "BumperIslet": islet,
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
}
