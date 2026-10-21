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

from generate_meshes import COLORS as BASE_COLORS, Mesh, capsule, cylinder, icosphere, lathe, merge, rounded_box, sphere, torus, weld
from generate_meshes import tube as _tube

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


def signed_volume(mesh: Mesh) -> float:
    tri = mesh.v[mesh.f]
    return float(np.einsum("ij,ij->i", tri[:, 0], np.cross(tri[:, 1], tri[:, 2])).sum() / 6)


def outward(mesh: Mesh) -> Mesh:
    """Flips a closed mesh's faces if they point inward."""
    if signed_volume(mesh) < 0:
        mesh.f = mesh.f[:, ::-1].copy()
    return mesh


def tube(points, radius: float, sides: int = 8) -> Mesh:
    """The shared tube with its faces turned outward and both ends capped (the shared one is
    inside-out and open, which Roblox would draw hollow)."""
    mesh = _tube(points, radius, sides)
    mesh.f = mesh.f[:, ::-1].copy()
    verts, faces = list(mesh.v), [tuple(f) for f in mesh.f]
    pts = [np.array(p, dtype=float) for p in points]
    for ring, outside in ((0, pts[0] - pts[1]), (len(pts) - 1, pts[-1] - pts[-2])):
        center = len(verts)
        verts.append(pts[ring])
        rim = list(range(len(verts), len(verts) + sides))
        verts.extend(mesh.v[ring * sides:(ring + 1) * sides])
        cap = [(center, rim[j], rim[(j + 1) % sides]) for j in range(sides)]
        a, b, c = (np.asarray(verts[i]) for i in cap[0])
        if np.dot(np.cross(b - a, c - a), outside) < 0:
            cap = [(x, z, y) for x, y, z in cap]
        faces += cap
    return Mesh(np.array(verts), faces, mesh.smooth)


def slab(front: np.ndarray, back: np.ndarray, smooth: bool = True) -> Mesh:
    """A closed slab between two (rows, cols, 3) grids of points: both faces plus the rim."""
    rows, cols = front.shape[:2]
    off = rows * cols
    verts = np.vstack([front.reshape(-1, 3), back.reshape(-1, 3)])

    def idx(i, j):
        return i * cols + j

    faces = []
    for i in range(rows - 1):
        for j in range(cols - 1):
            a, b, c, d = idx(i, j), idx(i, j + 1), idx(i + 1, j), idx(i + 1, j + 1)
            faces += [(a, b, c), (b, d, c), (off + a, off + c, off + b), (off + b, off + c, off + d)]
    loop = ([idx(0, j) for j in range(cols)] + [idx(i, cols - 1) for i in range(1, rows)]
            + [idx(rows - 1, j) for j in range(cols - 2, -1, -1)] + [idx(i, 0) for i in range(rows - 2, 0, -1)])
    for p, q in zip(loop, loop[1:] + loop[:1]):
        faces += [(p, off + p, q), (q, off + p, off + q)]
    return outward(Mesh(verts, faces, smooth))


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


FALL_ANGLES = (-24.0, 21.0)
LEDGE_ROWS = (range(18, 22), range(6, 8))  # profile rows (95.5, 22.5)-(91, 19.6) and (122, 18)-(115, 24)
CREST_ROW = 12  # (104, 30.5)


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
    verts += center_dir * ((lumps * 3.0 + crags * 1.2) * np.clip(height, 0.15, 1))[:, None]
    verts[:, 1] += (lumps * 1.6 + crags * 0.7) * height
    # A V-shaped notch in the crest where each lava fall pours over.
    vertex_theta = np.arctan2(verts[:, 0], -verts[:, 2])
    for angle in FALL_ANGLES:
        near = np.exp(-((vertex_theta - math.radians(angle)) / math.radians(2.6)) ** 2)
        verts[:, 1] -= 4.5 * near * np.clip((verts[:, 1] - 16) / 10, 0, 1)
    seg = len(thetas)
    faces = []
    for i in range(rows - 1):
        for s in range(seg - 1):
            a = i * seg + s
            b, c, d = a + 1, a + seg, a + seg + 1
            faces += [(a, c, b), (b, c, d)]
    wall = Mesh(verts, faces, smooth=True)
    # Faces must point away from the solid: on the inner foot that is toward the crater center.
    n = face_normals(wall)
    inner = wall.v[wall.f[-1]].mean(axis=0)
    if np.dot(n[-1], inner * np.array([1, 0, 1])) > 0:
        wall.f = wall.f[:, ::-1].copy()
        n = -n
    # Light ledges are whole profile rows, so each band runs unbroken around the arc.
    face_row = np.arange(len(wall.f)) // (2 * (seg - 1))
    ledge = np.isin(face_row, [row for band in LEDGE_ROWS for row in band])
    rock, top = subset(wall, ~ledge), subset(wall, ledge)

    # Vertex normals (pointing out of the rock) to lay the lava falls on the inner face.
    vn = np.zeros_like(verts)
    for k in range(3):
        np.add.at(vn, wall.f[:, k], n)
    vn /= np.linalg.norm(vn, axis=1, keepdims=True) + 1e-12

    def surface(row, theta):
        """The wall point and normal on `row` at angle `theta` (linear between columns)."""
        k = int(np.clip(np.searchsorted(thetas, theta), 1, seg - 1))
        t = (theta - thetas[k - 1]) / (thetas[k] - thetas[k - 1])
        a, b = row * seg + k - 1, row * seg + k
        p = verts[a] * (1 - t) + verts[b] * t
        q = vn[a] * (1 - t) + vn[b] * t
        return p, q / (np.linalg.norm(q) + 1e-12)

    # Lava falls: a ribbon pouring from each notch down the inner face, 4 studs wide at the crest
    # and 8 at the foot, with a pool where it feeds the lake (the lava is 3 studs above the foot).
    falls = []
    thick = 0.8
    for angle in FALL_ANGLES:
        theta = math.radians(angle)
        front, back = [], []
        for row in range(CREST_ROW - 1, rows):
            t = (row - CREST_ROW + 1) / (rows - CREST_ROW)
            width = 4 + 4 * t ** 0.8
            center, _ = surface(row, theta)
            radius = math.hypot(center[0], center[2])
            row_front, row_back = [], []
            for u in np.linspace(-1, 1, 7):
                p, normal = surface(row, theta + u * width / 2 / radius)
                row_back.append(p + normal * 0.3)
                row_front.append(p + normal * (0.3 + thick))
            front.append(row_front)
            back.append(row_back)
        falls.append(slab(np.array(front), np.array(back)))
        foot, _ = surface(rows - 1, theta)
        falls.append(icosphere(5.2, 2, 0.15, seed=int(abs(angle))).scale(1, 0.2, 1.15).translate(foot[0], 3.0, foot[2]))
        lip, _ = surface(CREST_ROW - 1, theta)
        falls.append(icosphere(2.6, 1, 0.15, seed=int(abs(angle)) + 9).scale(1, 0.3, 1).translate(lip[0], lip[1] + 0.1, lip[2]))
    lava = merge(*falls)
    return {"Rock": rock, "Ledge": top, "Lava": lava}


# ---------------------------------------------------------------------------- lava crust

def cross2(a, b) -> float:
    return a[0] * b[1] - a[1] * b[0]


def hull2d(points: np.ndarray) -> np.ndarray:
    """Convex hull of 2D points, counter-clockwise."""
    pts = sorted(map(tuple, points))

    def half(seq):
        out = []
        for p in seq:
            while len(out) >= 2 and cross2(np.subtract(out[-1], out[-2]), np.subtract(p, out[-2])) <= 0:
                out.pop()
            out.append(p)
        return out

    lower, upper = half(pts), half(pts[::-1])
    return np.array(lower[:-1] + upper[:-1])


def clip_half(poly: np.ndarray, normal: np.ndarray, offset: float) -> np.ndarray:
    """The part of a convex polygon where p . normal >= offset."""
    out = []
    for i in range(len(poly)):
        p, q = poly[i], poly[(i + 1) % len(poly)]
        dp, dq = p @ normal - offset, q @ normal - offset
        if dp >= 0:
            out.append(p)
        if (dp >= 0) != (dq >= 0):
            out.append(p + (q - p) * dp / (dp - dq))
    out = np.array(out)
    keep = [i for i in range(len(out)) if np.linalg.norm(out[i] - out[i - 1]) > 0.05]
    return out[keep]


def inset2d(poly: np.ndarray, d: float) -> np.ndarray:
    """A convex counter-clockwise polygon shrunk by d on every side."""
    out = poly
    for i in range(len(poly)):
        p, q = poly[i], poly[(i + 1) % len(poly)]
        edge = (q - p) / np.linalg.norm(q - p)
        inward = np.array([-edge[1], edge[0]])
        out = clip_half(out, inward, p @ inward + d)
        if len(out) < 3:
            break
    return out


def plate(poly: np.ndarray, y0: float, y1: float, bevel: float, tilt: np.ndarray) -> Mesh:
    """A flat-shaded slab of crust: polygon (x, z) from y0 up to y1 with a bevelled top edge."""
    center = poly.mean(axis=0)
    top = center + (poly - center) * np.clip(1 - bevel / (np.linalg.norm(poly - center, axis=1) + 1e-9), 0.5, 1)[:, None]
    rings = [(poly, y0), (poly, y1 - bevel), (top, y1)]
    n = len(poly)
    verts = [(x, y, z) for ring, y in rings for x, z in ring] + [(center[0], y1, center[1]), (center[0], y0, center[1])]
    faces = []
    for r in range(2):
        for i in range(n):
            j = (i + 1) % n
            a, b, c, d = r * n + i, r * n + j, (r + 1) * n + i, (r + 1) * n + j
            faces += [(a, c, b), (b, c, d)]
    top_c, bottom_c = 3 * n, 3 * n + 1
    for i in range(n):
        j = (i + 1) % n
        faces += [(2 * n + i, top_c, 2 * n + j), (i, j, bottom_c)]
    mesh = outward(Mesh(verts, faces, smooth=False))
    # Tip the plate a little about its own center (rafts are never quite level).
    lift = (mesh.v[:, 0] - center[0]) * tilt[0] + (mesh.v[:, 2] - center[1]) * tilt[1]
    mesh.v[:, 1] += np.where(mesh.v[:, 1] > y0 + 0.01, lift, 0)
    return mesh


def grow2d(poly: np.ndarray, d: float) -> np.ndarray:
    """A convex counter-clockwise polygon pushed out by d on every side."""
    out = []
    for i in range(len(poly)):
        normals = []
        for p, q in ((poly[i - 1], poly[i]), (poly[i], poly[(i + 1) % len(poly)])):
            edge = (q - p) / np.linalg.norm(q - p)
            normals.append(np.array([edge[1], -edge[0]]))
        n1, n2 = normals
        out.append(poly[i] + d * (n1 + n2) / max(1 + n1 @ n2, 0.3))
    return np.array(out)


def lava_crust():
    """A raft of cooled crust: an irregular slab split by straight cracks into angular plates. The
    plates are shrunk apart and drift a little, so the hot Glow slabs under them show in the cracks
    and as a thin rim; one outer plate has broken off, so the outline is never a neat polygon."""
    rng = np.random.default_rng(64)
    sides = 8
    step = 2 * math.pi / sides
    angles = np.linspace(0, 2 * math.pi, sides, endpoint=False) + rng.uniform(-0.3, 0.3, sides) * step
    radii = 5.2 * rng.uniform(0.75, 1.25, sides)
    outline = hull2d(np.stack([np.cos(angles) * radii, np.sin(angles) * radii], axis=1))
    def area(poly):
        return 0.5 * abs(sum(cross2(poly[i - 1], poly[i]) for i in range(len(poly))))

    # Split into plates with straight cracks: each cut goes across the biggest plate's long side,
    # a little off-center, and never leaves a sliver.
    cells = [outline]
    for _ in range(5):
        cells.sort(key=area)
        poly = cells.pop()
        spread = poly - poly.mean(axis=0)
        long_axis = np.linalg.eigh(spread.T @ spread)[1][:, -1]
        for _ in range(20):
            direction = math.atan2(long_axis[1], long_axis[0]) + rng.uniform(-0.5, 0.5)
            normal = np.array([math.cos(direction), math.sin(direction)])
            offset = poly.mean(axis=0) @ normal + rng.uniform(-0.6, 0.6)
            halves = [clip_half(poly, normal, offset), clip_half(poly, -normal, -offset)]
            if all(len(half) >= 3 and area(half) > 0.3 * area(poly) for half in halves):
                break
        cells += halves
    # Break off the smallest plate on the rim.
    cells.sort(key=area)
    cells = cells[1:]
    middle = outline.mean(axis=0)
    plates, glows = [], []
    for k, cell in enumerate(cells):
        away = cell.mean(axis=0) - middle
        drift = away / (np.linalg.norm(away) + 1e-9) * rng.uniform(0.05, 0.35)
        turn = rng.uniform(-0.05, 0.05)
        c, s_ = math.cos(turn), math.sin(turn)
        center = cell.mean(axis=0)
        moved = (cell - center) @ np.array([[c, s_], [-s_, c]]) + center + drift
        shrunk = inset2d(moved, 0.32)
        if len(shrunk) >= 3:
            plates.append(plate(shrunk, 0.3, rng.uniform(2.3, 2.9), 0.35, rng.uniform(-0.05, 0.05, 2)))
        # Each plate's own glow, a touch bigger than its cell, at its own height (no shared faces).
        glows.append(plate(grow2d(moved, 0.06), 0.0, 1.45 + 0.07 * k, 0.2, np.zeros(2)))
    return {"Crust": merge(*plates), "Glow": merge(*glows)}


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


POLE_BOTTOM, POLE_TOP = (4.2, 7.0), (9.5, 17.8)  # (x, y): the pole leans out to the robot's right
FLAG = {"top": 17.2, "high": 6.6, "width": 9.6, "z": -0.6}


def pole_x(y: float) -> float:
    (x0, y0), (x1, y1) = POLE_BOTTOM, POLE_TOP
    return x0 + (x1 - x0) * (y - y0) / (y1 - y0)


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
    hand_x = pole_x(9.4)
    right_arm = tube([(3.2, 6.3, 0), (4.4, 7.7, -0.4), (hand_x, 9.4, -0.6)], 0.6, 10)
    left_arm = tube([(-3.2, 6.3, 0), (-4.4, 4.9, -0.3), (-3.7, 3.4, -1.3)], 0.6, 10)
    hands = merge(sphere(0.85, 8, 12).translate(hand_x, 9.5, -0.6), sphere(0.85, 8, 12).translate(-3.6, 3.3, -1.4))
    pole = merge(tube([(*POLE_BOTTOM, -0.6), (*POLE_TOP, -0.6)], 0.24, 8), sphere(0.45, 6, 10).translate(*POLE_TOP, -0.6).translate(0, 0.2, 0))

    # The flag: a waving cloth slab off the leaning pole (closed, so it shows from both sides), its
    # inner edge along the pole, out clear of the marquee legs behind it.
    nx, ny, width, high, thick = 16, 7, FLAG["width"], FLAG["high"], 0.14

    def cloth(u, v, side):
        y = FLAG["top"] - high + v * high - 0.3 * u * u
        x = pole_x(y) + 0.3 + u * width
        z = FLAG["z"] + 0.55 * math.sin(u * 5.0) * u + 0.1 * math.sin(v * 3 + u * 4)
        return (x, y, z + side * thick)

    grid = []
    for side in (-1, 1):
        for j in range(ny + 1):
            for i in range(nx + 1):
                grid.append(cloth(i / nx, j / ny, side))
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
    # A dark hem all round, so any call color stands out against the wall, sky or marquee.
    hem_loop = ([cloth(i / nx, 0, 0) for i in range(nx + 1)] + [cloth(1, j / ny, 0) for j in range(1, ny + 1)]
                + [cloth(i / nx, 1, 0) for i in range(nx - 1, -1, -1)] + [cloth(0, j / ny, 0) for j in range(ny - 1, -1, -1)])
    hem = merge(tube(hem_loop, 0.3, 6), *(sphere(0.3, 5, 8).translate(*cloth(u, v, 0)) for u, v in ((0, 0), (1, 0), (1, 1), (0, 1))))

    white = merge(torso, head, right_arm, left_arm)
    dark = merge(base, stripes, neck, shoulders, hands, ears, screen, hem)
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

MARQUEE = {"width": 30.0, "height": 13.0, "bar": 2.2, "depth": 2.2, "center_y": 27.0, "legs_x": 4.0}


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
    # A flame of several tongues, each leaning out and twisting, so the outline flickers.
    tongues = [flame_shape(2.7, 8.5, 1).translate(0, 22.4, 0)]
    for k, (radius, high, lean, direction) in enumerate(((2.0, 6.5, 14, 20), (1.8, 5.0, 18, 140), (1.6, 4.0, 16, 250), (1.7, 5.6, 12, 320))):
        tongue = flame_shape(radius, high, 11 + k * 7).rotate("z", -lean).translate(1.4, 0, 0).rotate("y", direction)
        tongues.append(tongue.translate(0, 22.3, 0))
    flame = merge(*tongues)
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
