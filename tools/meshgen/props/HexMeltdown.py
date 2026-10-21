"""Props for Hex Meltdown: a toy volcano crater with a game-show referee.

    python3 tools/meshgen/generate_meshes.py --only HexColumn,CraterWall,LavaCrust,RefereeStand,RefereeBot,CallMarquee,LavaTorch

Units are studs, +Y is up, the base sits on y = 0 and -Z is the front:
  * HexColumn: one hex pillar of the grid (flat-top hexagon, corners on +-X like the game's hex
    prism, circumradius 7). Rock = carved basalt drums, Top = the colored tile and the colored band
    under the rim (one piece, so both light up together), Rim = the cream outline, Glow = lava-hot
    cracks around the lava line. The tile's top is at 30.95, just under the invisible collider.
  * CraterWall: a 100 degree arc of the crater wall around a center 0..142 studs along -Z (four turned
    copies close the ring). The pivot is NOT the crater center: see WALL_* printed by --only.
  * LavaCrust: a raft of crusted basalt plates with hot glowing edges, floating on the lava.
  * RefereeStand: a basalt plinth rising from the lava with a striped referee stage on top.
  * RefereeBot: the referee robot (striped shirt, screen face, whistle) holding up the call flag on
    its right (+X). Flag is its own piece: the server colors it with the call.
  * CallMarquee: a light-bulb marquee frame on two legs; the call board part sits in its opening.
  * LavaTorch: a basalt torch column with a gold bowl and a big stylized flame.
"""

import math

import numpy as np

from generate_meshes import COLORS as BASE_COLORS, Mesh, capsule, cylinder, icosphere, lathe, merge, rounded_box, sphere, torus, tube, weld

COS30 = math.cos(math.radians(30))


def subset(mesh: Mesh, mask) -> Mesh:
    """The faces of `mesh` where mask is true, with unused vertices dropped."""
    faces = mesh.f[mask]
    used, inverse = np.unique(faces.reshape(-1), return_inverse=True)
    return Mesh(mesh.v[used], inverse.reshape(-1, 3), mesh.smooth)


def face_normals(mesh: Mesh) -> np.ndarray:
    tri = mesh.v[mesh.f]
    n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    return n / (np.linalg.norm(n, axis=1, keepdims=True) + 1e-12)


def waves(points: np.ndarray, seed: int, count: int = 7, low: float = 0.08, high: float = 0.22) -> np.ndarray:
    """Smooth 3D value in about -1..1: a sum of random plane waves (rock lumps, crags)."""
    rng = np.random.default_rng(seed)
    directions = rng.normal(size=(count, 3))
    directions /= np.linalg.norm(directions, axis=1, keepdims=True)
    frequencies = rng.uniform(low, high, count)
    offsets = rng.uniform(0, 2 * math.pi, count)
    return np.mean(np.sin(points @ directions.T * frequencies + offsets), axis=1) * 1.6


def hex_lathe(profile, bulge: float = 1.0) -> Mesh:
    """A lathe with hexagonal cross-section (corners at 0, 60, ... degrees, like the game's hex
    prism). Mid-face points sit at the apothem times `bulge`, so >1 gives softly bulging faces."""
    mesh = lathe(profile, 12)
    angle = np.degrees(np.arctan2(mesh.v[:, 2], mesh.v[:, 0]))
    odd = (np.round(angle / 30).astype(int) % 2) == 1
    mesh.v[odd, 0] *= COS30 * bulge
    mesh.v[odd, 2] *= COS30 * bulge
    return mesh


def hex_band(r_in: float, r_out: float, y0: float, y1: float, bevel: float) -> Mesh:
    return hex_lathe([(r_in, y0), (r_out - bevel, y0), (r_out, y0 + bevel), (r_out, y1 - bevel), (r_out - bevel, y1), (r_in, y1)])


# ---------------------------------------------------------------------------- hex column

def hex_column():
    rng = np.random.default_rng(7)
    # Carved basalt drums with V-grooves between them, each a touch wider or narrower.
    edges = [0.0, 6.0, 11.6, 16.8, 21.6, 26.0, 29.4]
    profile = []
    for i in range(len(edges) - 1):
        a, b = edges[i], edges[i + 1]
        radius = 6.3 + rng.uniform(-0.12, 0.1)
        groove = 0.32 if i > 0 else 0.0
        top = 0.32 if i < len(edges) - 2 else 0.0
        profile += [(radius - groove, a), (radius, a + max(groove, 0.01)), (radius, b - max(top, 0.01)), (radius - top, b)]
    rock = hex_lathe(profile, 1.04)
    lumps = waves(rock.v, 3, low=0.25, high=0.6)
    radial = np.linalg.norm(rock.v[:, [0, 2]], axis=1, keepdims=True) + 1e-9
    rock.v[:, [0, 2]] += rock.v[:, [0, 2]] / radial * (lumps[:, None] * 0.12)
    rock.smooth = False

    # The colored band under the rim and the tile on top (one piece: they glow together).
    band = hex_band(6.0, 6.62, 26.5, 29.5, 0.18)
    tile = hex_lathe([(0.0, 30.15), (6.55, 30.15), (6.95, 30.45), (6.95, 30.7), (6.7, 30.95), (0.0, 30.95)])
    top = merge(band, tile)
    top.smooth = False

    rim = hex_lathe([(6.2, 29.3), (7.18, 29.3), (7.45, 29.57), (7.45, 30.05), (7.2, 30.35), (6.2, 30.35)])
    rim.smooth = False

    # Lava-hot cracks running up from the lava line on every face.
    cracks = []
    for face in range(6):
        normal_angle = math.radians(30 + 60 * face)
        n = np.array([math.cos(normal_angle), 0.0, math.sin(normal_angle)])
        t = np.array([-n[2], 0.0, n[0]])
        apothem = 6.3 * COS30 * 1.04 + 0.05
        start = rng.uniform(-1.6, 1.6)
        points = []
        for k, y in enumerate(np.linspace(6.5, 13.0 + rng.uniform(0, 3.5), 5)):
            side = start + (k % 2 * 2 - 1) * rng.uniform(0.3, 0.8)
            points.append(tuple(n * apothem + t * side + np.array([0, y, 0])))
        cracks.append(tube(points, 0.2, 6))
        # A short branch off the middle.
        mid = np.array(points[2])
        branch = [tuple(mid), tuple(mid + t * rng.choice([-1.3, 1.3]) + np.array([0, 1.4, 0]))]
        cracks.append(tube(branch, 0.15, 6))
    glow = merge(*cracks)
    return {"Rock": rock, "Top": top, "Rim": rim, "Glow": glow}


# ---------------------------------------------------------------------------- crater wall

WALL_ARC = 100.0  # degrees; four copies 90 degrees apart overlap a little
WALL_PROFILE = [  # (radius, y) from the outer foot over the crest to the inner foot
    (146, 0), (138, 5), (130, 11), (122, 18), (115, 24), (109, 28.5), (104, 30.5), (99.5, 29.5),
    (97, 26), (95.5, 22.5), (93.5, 20.4), (91, 19.6), (89, 17.5), (87.8, 13), (86.8, 8), (86, 3.5), (85.5, 0),
]


def crater_wall():
    rng = np.random.default_rng(31)
    thetas = np.radians(np.linspace(-WALL_ARC / 2, WALL_ARC / 2, 67))
    profile = []
    # Subdivide the profile so crags have vertices to move.
    for (r0, y0), (r1, y1) in zip(WALL_PROFILE, WALL_PROFILE[1:]):
        for t in (0.0, 0.5):
            profile.append((r0 + (r1 - r0) * t, y0 + (y1 - y0) * t))
    profile.append(WALL_PROFILE[-1])
    rows = len(profile)
    phase = rng.uniform(0, 2 * math.pi, 3)

    def crest(theta):
        return 1 + 0.16 * np.sin(4.5 * theta + phase[0]) + 0.09 * np.sin(11 * theta + phase[1]) + 0.05 * np.sin(23 * theta + phase[2])

    def taper(theta):
        # The last 6 degrees at each end tuck down inside the neighboring copy.
        edge = math.radians(WALL_ARC / 2) - abs(theta)
        return 0.45 + 0.55 * min(1.0, edge / math.radians(6))

    def point(theta, r, y):
        s = taper(theta)
        r = 116 + (r - 116) * s
        y = y * crest(theta) * s
        return np.array([math.sin(theta) * r, y, -math.cos(theta) * r])

    verts = np.array([point(theta, r, y) for (r, y) in profile for theta in thetas])
    lumps = waves(verts, 5, count=9, low=0.05, high=0.16)
    crags = waves(verts, 6, count=9, low=0.22, high=0.45)
    center_dir = verts * np.array([1, 0, 1])
    center_dir /= np.linalg.norm(center_dir, axis=1, keepdims=True)
    height = np.clip(verts[:, 1] / 34, 0, 1)
    verts += center_dir * ((lumps * 3.6 + crags * 2.2) * np.clip(height, 0.15, 1))[:, None]
    verts[:, 1] += (lumps * 1.8 + crags * 1.2) * height
    seg = len(thetas)
    faces = []
    for i in range(rows - 1):
        for s in range(seg - 1):
            a = i * seg + s
            b, c, d = a + 1, a + seg, a + seg + 1
            faces += [(a, c, b), (b, c, d)]
    wall = Mesh(verts, faces, smooth=False)
    # Faces must point away from the solid: on the inner foot that is toward the crater center.
    n = face_normals(wall)
    inner = wall.v[wall.f[-1]].mean(axis=0)
    if np.dot(n[-1], inner * np.array([1, 0, 1])) > 0:
        wall.f = wall.f[:, ::-1].copy()
        n = -n
    ledge = n[:, 1] > 0.9
    rock, top = subset(wall, ~ledge), subset(wall, ledge)

    # Lava falls pouring from notches in the crest down the inner face into the lake.
    falls = []
    crest_row = 12  # (104, 30.5)
    for angle in (-24.0, 21.0):
        theta = math.radians(angle)
        idx = int(np.argmin(np.abs(thetas - theta)))
        path = []
        for row in range(crest_row, rows):
            p = verts[row * seg + idx].copy()
            inward = -p * np.array([1, 0, 1]) / np.linalg.norm(p * np.array([1, 0, 1]))
            path.append(tuple(p + inward * 0.9 + np.array([0, 0.5, 0])))
        falls.append(tube(path, 1.5, 8))
        foot = np.array(path[-1])
        falls.append(icosphere(3.4, 1, 0.25, seed=int(abs(angle))).scale(1, 0.32, 1).translate(foot[0], 3.0, foot[2]))
        top_p = np.array(path[0])
        falls.append(icosphere(2.2, 1, 0.2, seed=int(abs(angle)) + 9).scale(1, 0.35, 1).translate(top_p[0], top_p[1] - 0.2, top_p[2]))
    lava = merge(*falls)
    return {"Rock": rock, "Ledge": top, "Lava": lava}


# ---------------------------------------------------------------------------- lava crust

def lava_crust():
    """An island of crust: lumpy flattened rocks run together, a hot glowing edge under them and a
    few lava bubbles around."""
    rocks, glows, bubbles = [], [], []
    for i, (x, z, radius) in enumerate(((0, 0, 6.0), (6.5, 2.5, 4.6), (-5.5, 3.2, 4.4), (2.5, -5.2, 4.0), (-3.5, -4.0, 3.2), (10.5, -2.0, 2.8))):
        rock = icosphere(radius, 2, 0.45, seed=60 + i).scale(1, 0.24, 1)
        rock.v[:, 1] = np.maximum(rock.v[:, 1], -0.2)  # flat underside, just under the lava
        rocks.append(rock.translate(x, 0.2, z))
        halo = icosphere(radius * 1.14, 1, 0.35, seed=80 + i).scale(1, 0.1, 1)
        glows.append(halo.translate(x, 0.15, z))
    for x, z, radius in ((-10, -1, 1.2), (5, 8.5, 0.9), (-2, 8.0, 1.0), (13.5, 3, 0.8)):
        bubbles.append(sphere(radius, 6, 10).scale(1, 0.7, 1).translate(x, 0.3, z))
    crust = merge(*rocks)
    crust.smooth = False
    return {"Crust": crust, "Glow": merge(*glows, *bubbles)}


# ---------------------------------------------------------------------------- referee stand

STAGE_TOP = 19.3


def referee_stand():
    profile = [(9.6, 0.0), (8.6, 4.0), (7.4, 8.5), (7.0, 12.5), (7.6, 15.5), (9.4, 17.2), (10.3, 18.2), (0.0, 18.2)]
    rock = lathe(profile, 11)
    lumps = waves(rock.v, 9, low=0.3, high=0.7)
    radial = np.linalg.norm(rock.v[:, [0, 2]], axis=1)
    keep = radial > 0.1
    rock.v[keep, 0] *= 1 + 0.08 * lumps[keep]
    rock.v[keep, 2] *= 1 + 0.08 * lumps[keep]
    rock.smooth = False

    # The stage: a disc whose top is cut into 16 alternating referee-stripe sectors.
    side = lathe([(10.4, 17.9), (10.8, 18.2), (11.0, 18.6), (11.0, 19.0), (10.7, STAGE_TOP)], 48)
    sectors = 16
    fan_a, fan_b = [], []
    for k in range(sectors):
        steps = 3
        for j in range(steps):
            a0 = 2 * math.pi * (k * steps + j) / (sectors * steps)
            a1 = 2 * math.pi * (k * steps + j + 1) / (sectors * steps)
            tri = [(0.0, STAGE_TOP, 0.0), (math.cos(a1) * 10.7, STAGE_TOP, math.sin(a1) * 10.7), (math.cos(a0) * 10.7, STAGE_TOP, math.sin(a0) * 10.7)]
            (fan_a if k % 2 == 0 else fan_b).append(tri)

    def fan(tris):
        verts = [p for tri in tris for p in tri]
        return Mesh(verts, [(i * 3, i * 3 + 1, i * 3 + 2) for i in range(len(tris))], smooth=False)

    stage = merge(side, fan(fan_a))
    stage.smooth = False
    alt = fan(fan_b)
    under = cylinder(10.6, 0.4, 32).translate(0, 17.8, 0)  # closes the stage from below
    trim = merge(torus(11.05, 0.32, 64, 8).translate(0, 18.62, 0), under)
    bulbs = merge(*(sphere(0.42, 6, 10).translate(math.cos(a) * 11.32, 18.62, math.sin(a) * 11.32)
                    for a in np.linspace(0, 2 * math.pi, 20, endpoint=False)))
    return {"Rock": rock, "Stage": stage, "StageAlt": alt, "Trim": trim, "Bulbs": bulbs}


# ---------------------------------------------------------------------------- referee robot

def rounded_rect(hy: float, hz: float, r: float, per_corner: int = 6):
    points = []
    for cy, cz, start in ((hy - r, hz - r, 0), (-(hy - r), hz - r, 90), (-(hy - r), -(hz - r), 180), (hy - r, -(hz - r), 270)):
        for i in range(per_corner + 1):
            a = math.radians(start + 90 * i / per_corner)
            points.append((cy + math.cos(a) * r, cz + math.sin(a) * r))
    return points


def stripe_band(x0: float, x1: float, hy: float, hz: float, r: float, cy: float, out: float) -> Mesh:
    """A ring around a rounded box (its flat middle, along X) - one stripe of the referee shirt."""
    outer = rounded_rect(hy + out, hz + out, r + out)
    inner = rounded_rect(hy - 0.1, hz - 0.1, r - 0.1)
    n = len(outer)
    verts = []
    for x in (x0, x1):
        verts += [(x, cy + y, z) for y, z in outer]
    for x in (x0, x1):
        verts += [(x, cy + y, z) for y, z in inner]
    faces = []
    for i in range(n):
        j = (i + 1) % n
        o0, o1, i0, i1 = 0, n, 2 * n, 3 * n
        faces += [(o0 + i, o0 + j, o1 + i), (o0 + j, o1 + j, o1 + i)]  # outside
        faces += [(o0 + i, i0 + i, o0 + j), (o0 + j, i0 + i, i0 + j)]  # side at x0
        faces += [(o1 + i, o1 + j, i1 + i), (o1 + j, i1 + j, i1 + i)]  # side at x1
    mesh = Mesh(verts, faces, smooth=False)
    # Orient the outside faces outward (checked on the first one).
    tri = mesh.v[mesh.f[0]]
    normal = np.cross(tri[1] - tri[0], tri[2] - tri[0])
    if np.dot(normal, tri.mean(axis=0) - np.array([tri.mean(axis=0)[0], cy, 0])) < 0:
        mesh.f = mesh.f[:, ::-1].copy()
    return mesh


ROBOT_POLE_X = 5.0


def referee_bot():
    # Hover base with a glowing thruster ring.
    base = lathe([(1.6, 0.3), (2.6, 0.5), (3.0, 1.2), (2.7, 1.9), (1.8, 2.2), (0.0, 2.25)], 24, cap_bottom=True)
    thruster = torus(1.9, 0.28, 24, 8).translate(0, 0.32, 0)
    # Torso: a rounded box with the referee's black stripes wrapped around it.
    torso = rounded_box(6.2, 5.4, 4.4, 1.4, 8).translate(0, 4.6, 0)
    stripes = merge(*(stripe_band(c - 0.3, c + 0.3, 2.7, 2.2, 1.4, 4.6, 0.06) for c in (-1.2, 0.0, 1.2)))
    neck = cylinder(1.0, 1.3, 16).translate(0, 7.0, 0)
    head = rounded_box(5.4, 4.2, 4.4, 1.5, 8).translate(0, 10.1, 0)
    screen = rounded_box(4.0, 2.7, 0.8, 0.3, 4).translate(0, 10.2, -1.95)
    eyes = []
    for side in (-1, 1):
        arc = torus(0.55, 0.17, 10, 6, arc=180).rotate("x", -90).translate(side * 0.95, 10.25, -2.42)
        eyes.append(arc)
    mouth = torus(0.45, 0.13, 10, 6, arc=180).rotate("x", 90).translate(0, 9.35, -2.42)
    antenna = tube([(0, 12.0, 0), (0, 13.2, 0.1)], 0.16, 6)
    bulb = sphere(0.45, 8, 12).translate(0, 13.45, 0.1)
    ears = merge(*(cylinder(0.85, 0.5, 16).rotate("z", 90).translate(side * 2.95, 10.1, 0) for side in (-1, 1)))
    whistle = merge(capsule(1.2, 0.32, 10).rotate("x", 90).translate(-1.5, 8.7, -2.5), torus(0.18, 0.06, 8, 4).translate(-1.5, 9.0, -2.0))
    lanyard = tube([(-1.5, 8.85, -2.0), (-1.2, 8.3, -2.35), (0.0, 8.1, -2.45), (1.2, 8.3, -2.35), (1.6, 8.9, -2.0)], 0.1, 5)

    # Arms: right (+X) raised holding the flag pole, left (-X) on the hip.
    shoulders = merge(*(sphere(0.95, 8, 12).translate(side * 3.15, 6.3, 0) for side in (-1, 1)))
    right_arm = tube([(3.2, 6.3, 0), (4.3, 7.6, -0.4), (ROBOT_POLE_X, 9.4, -0.6)], 0.6, 10)
    left_arm = tube([(-3.2, 6.3, 0), (-4.4, 4.9, -0.3), (-3.7, 3.4, -1.3)], 0.6, 10)
    hands = merge(sphere(0.85, 8, 12).translate(ROBOT_POLE_X, 9.5, -0.6), sphere(0.85, 8, 12).translate(-3.6, 3.3, -1.4))
    pole = merge(tube([(ROBOT_POLE_X, 7.6, -0.6), (ROBOT_POLE_X, 16.2, -0.6)], 0.22, 8), sphere(0.42, 6, 10).translate(ROBOT_POLE_X, 16.4, -0.6))

    # The flag: a waving cloth slab off the top of the pole (closed, so it shows from both sides).
    nx, ny, width, high, thick = 14, 6, 6.6, 4.8, 0.14
    grid = []
    for side in (-1, 1):
        for j in range(ny + 1):
            for i in range(nx + 1):
                u, v = i / nx, j / ny
                x = ROBOT_POLE_X + 0.15 + u * width
                y = 15.9 - high + v * high - 0.25 * u * u
                z = -0.6 + 0.55 * math.sin(u * 5.0) * u + 0.1 * math.sin(v * 3 + u * 4)
                grid.append((x, y, z + side * thick))
    faces = []
    count = (nx + 1) * (ny + 1)
    for j in range(ny):
        for i in range(nx):
            a = j * (nx + 1) + i
            b, c, d = a + 1, a + nx + 1, a + nx + 2
            faces += [(a, b, c), (b, d, c)]  # back (-1 side) ... flipped below for the front
            faces += [(count + a, count + c, count + b), (count + b, count + c, count + d)]
    # Close the four edges.
    def edge(indices):
        for p, q in zip(indices, indices[1:]):
            faces.append((p, q, count + p))
            faces.append((q, count + q, count + p))
    edge([j * (nx + 1) for j in range(ny + 1)][::-1])
    edge([j * (nx + 1) + nx for j in range(ny + 1)])
    edge([i for i in range(nx + 1)])
    edge([ny * (nx + 1) + i for i in range(nx + 1)][::-1])
    flag = Mesh(grid, faces, smooth=False)

    white = merge(torso, head, right_arm, left_arm)
    dark = merge(base, stripes, neck, shoulders, hands, ears, screen)
    dark.smooth = False
    return {
        "Body": white,
        "Dark": dark,
        "Eyes": merge(*eyes, mouth, thruster),
        "Bulb": bulb,
        "Gold": merge(whistle, pole, antenna),
        "Lanyard": lanyard,
        "Flag": flag,
    }


# ---------------------------------------------------------------------------- call marquee

MARQUEE = {"width": 30.0, "height": 13.0, "bar": 2.2, "depth": 2.2, "center_y": 23.5, "legs_x": 8.5}


def call_marquee():
    w, h, bar, depth, cy = MARQUEE["width"], MARQUEE["height"], MARQUEE["bar"], MARQUEE["depth"], MARQUEE["center_y"]
    frame = merge(
        rounded_box(w, bar, depth, 0.6, 6).translate(0, cy + h / 2 - bar / 2, 0),
        rounded_box(w, bar, depth, 0.6, 6).translate(0, cy - h / 2 + bar / 2, 0),
        rounded_box(bar, h, depth, 0.6, 6).translate(-w / 2 + bar / 2, cy, 0),
        rounded_box(bar, h, depth, 0.6, 6).translate(w / 2 - bar / 2, cy, 0),
    )
    legs = merge(*(rounded_box(2.3, cy - h / 2 + 0.6, 2.3, 0.7, 4).translate(x, (cy - h / 2 + 0.6) / 2, 0.0) for x in (-MARQUEE["legs_x"], MARQUEE["legs_x"])))
    feet = merge(*(cylinder(2.0, 0.7, 16, 0.2).translate(x, 0, 0) for x in (-MARQUEE["legs_x"], MARQUEE["legs_x"])))
    # Gold trim around the opening.
    ix, iy = w / 2 - bar, h / 2 - bar
    z = -depth / 2
    loop = [(-ix, cy - iy, z), (ix, cy - iy, z), (ix, cy + iy, z), (-ix, cy + iy, z), (-ix, cy - iy, z)]
    trim = merge(*(tube([a, b], 0.32, 8) for a, b in zip(loop, loop[1:])),
                 *(sphere(0.32, 6, 8).translate(*p) for p in loop[:4]))
    # Bulbs along the middle of every bar.
    bulbs = []
    mx, my = w / 2 - bar / 2, h / 2 - bar / 2
    for x in np.linspace(-mx, mx, 13):
        for y in (cy - my, cy + my):
            bulbs.append(sphere(0.42, 6, 10).translate(x, y, z - 0.05))
    for y in np.linspace(cy - my, cy + my, 6)[1:-1]:
        for x in (-mx, mx):
            bulbs.append(sphere(0.42, 6, 10).translate(x, y, z - 0.05))
    # A hexagon badge with a flame on top.
    top_y = cy + h / 2
    badge = hex_lathe([(0.0, -0.8), (3.4, -0.8), (3.6, -0.6), (3.6, 0.6), (3.4, 0.8), (0.0, 0.8)]).rotate("x", 90).rotate("z", 30)
    badge.translate(0, top_y + 2.6, 0)
    flame = flame_shape(1.5, 3.3, 5)
    flame.v[:, 2] *= 0.35
    flame.translate(0, top_y + 0.95, -0.95)
    frame_piece = merge(frame, legs, feet)
    return {"Frame": frame_piece, "Trim": trim, "Bulbs": merge(*bulbs), "Badge": badge, "Flame": flame}


# ---------------------------------------------------------------------------- lava torch

def flame_shape(radius: float, height: float, seed: int) -> Mesh:
    """A teardrop flame along +Y from y = 0 with a curling tip."""
    profile = [(0.0, 0.0)]
    for i in range(1, 13):
        t = i / 12
        r = radius * math.sin(math.pi * min(1, t * 1.25)) ** 0.8 * (1 - t) ** 0.45 if t < 1 else 0
        profile.append((max(r, 0.02), t * height))
    profile.append((0.0, height))
    flame = lathe(profile, 14)
    twist = flame.v[:, 1] / height
    angle = np.arctan2(flame.v[:, 2], flame.v[:, 0])
    wobble = 1 + 0.18 * np.sin(angle * 3 + twist * 6 + seed)
    flame.v[:, 0] *= wobble
    flame.v[:, 2] *= wobble
    flame.v[:, 0] += 0.25 * radius * np.sin(twist * 4.0 + seed) * twist
    return flame


def lava_torch():
    column = lathe([(3.4, 0.0), (3.0, 6.0), (2.6, 12.0), (2.5, 17.0), (2.9, 20.0), (3.4, 21.2), (0.0, 21.2)], 7)
    lumps = waves(column.v, 14, low=0.3, high=0.8)
    keep = np.linalg.norm(column.v[:, [0, 2]], axis=1) > 0.1
    column.v[keep, 0] *= 1 + 0.1 * lumps[keep]
    column.v[keep, 2] *= 1 + 0.1 * lumps[keep]
    column.smooth = False
    bowl = lathe([(1.0, 20.6), (3.0, 21.0), (4.4, 22.4), (4.9, 23.6), (4.6, 23.9), (3.9, 23.0), (0.0, 22.6)], 24)
    band = torus(4.85, 0.28, 32, 6).translate(0, 23.6, 0)
    flame = flame_shape(3.6, 8.5, 1).translate(0, 22.4, 0)
    core = flame_shape(2.0, 5.0, 3).translate(0, 22.5, -0.6)
    return {"Rock": column, "Gold": merge(bowl, band), "Flame": flame, "Core": core}


PROPS = {
    "HexColumn": hex_column,
    "CraterWall": crater_wall,
    "LavaCrust": lava_crust,
    "RefereeStand": referee_stand,
    "RefereeBot": referee_bot,
    "CallMarquee": call_marquee,
    "LavaTorch": lava_torch,
}
_COLORS = {  # preview colors only; the game colors pieces by name
    "Top": (60, 140, 255), "Ledge": (150, 104, 118), "Crust": (60, 42, 54), "Stage": (250, 246, 240),
    "StageAlt": (45, 40, 55), "Bulbs": (255, 240, 200), "Body": (245, 245, 255), "Dark": (45, 40, 55),
    "Eyes": (60, 230, 255), "Bulb": (255, 70, 70), "Gold": (255, 196, 60), "Lanyard": (255, 70, 90),
    "Flag": (255, 210, 50), "Frame": (130, 60, 210), "Badge": (255, 120, 40), "Flame": (255, 150, 40),
    "Core": (255, 240, 120),
}
COLORS = {name: color for name, color in _COLORS.items() if name not in BASE_COLORS}
