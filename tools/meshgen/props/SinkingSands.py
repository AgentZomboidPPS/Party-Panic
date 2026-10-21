"""Props for Sinking Sands: the quicksand pit on its desert mesa, the swirl streaks the client turns,
the treasure, the Divers' chests, the Sand Kings' palace, thrones and crowns, and desert scenery.

The funnel's shape must match src/shared/Logic/SandSwirl.luau (RIM, HOLE, DEPTH, CURVE, RINGS):
the game walks players on invisible collision built from the same numbers.
"""

import math

import numpy as np

from generate_meshes import (
    Mesh,
    capsule,
    cylinder,
    extrude,
    icosphere,
    lathe,
    merge,
    organic_lathe,
    rounded_box,
    sd_capsule,
    sd_ellipsoid,
    sdf_mesh,
    smin,
    sphere,
    star,
    taper,
    torus,
    tube,
)

RIM, HOLE, DEPTH, CURVE = 34.0, 5.0, 10.5, 1.6
RINGS = [5.3, 9.0, 14.0, 20.0, 27.0, 33.5]
PLAZA = 78.0  # radius of the flat mesa top
MESA = 40.0  # the mesa's height above the desert floor (the pit's mesh is this tall)
LIP_R = 9.0  # the darker, wetter sand round the hole
THROAT_BOTTOM = -30.0  # floor of the sinkhole, below the rim
WHIRL_BOTTOM = -20.0  # lowest point of the whirl streaks in the throat (sets the swirl model's pivot)


def sand_height(r):
    if r >= RIM:
        return 0.0
    u = max(0.0, (r - HOLE) / (RIM - HOLE))
    return -DEPTH * (1 - u) ** CURVE


# ---------------------------------------------------------------- helpers

def oriented(mesh, desired):
    """Flips faces whose normal points away from `desired(centroids)`."""
    tri = mesh.v[mesh.f]
    normal = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    want = desired(tri.mean(axis=1))
    flip = (normal * want).sum(axis=1) < 0
    mesh.f[flip] = mesh.f[flip][:, ::-1]
    return mesh


def away_from(point):
    p = np.array(point, dtype=float)
    return lambda c: c - p


def radial(cx=0.0, cz=0.0, sign=1.0, lift=0.0):
    return lambda c: np.stack([(c[:, 0] - cx) * sign, np.full(len(c), lift), (c[:, 2] - cz) * sign], 1)


def upward(c):
    return np.tile([0.0, 1.0, 0.0], (len(c), 1))


def tube_out(points, radius, sides=8, closed=True):
    """A tube along a polyline with outward faces (and capped ends unless closed=False)."""
    if closed:
        mesh = taper(points, radius, radius, sides)
    else:
        mesh = tube(points, radius, sides)
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


def tapered(points, r0, r1, sides=8):
    mesh = taper(points, r0, r1, sides)
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


def signed_volume(mesh):
    tri = mesh.v[mesh.f]
    return float(np.einsum("ij,ij->i", tri[:, 0], np.cross(tri[:, 1], tri[:, 2])).sum() / 6)


def outward(mesh):
    """Makes a closed mesh face outward (marching cubes may wind it either way)."""
    if signed_volume(mesh) < 0:
        mesh.f = mesh.f[:, ::-1].copy()
    return mesh


def closed_out(mesh, center=None):
    """Orients a star-shaped closed mesh outward from `center` (default: its centroid)."""
    c = mesh.v.mean(axis=0) if center is None else np.array(center, dtype=float)
    return oriented(mesh, away_from(c))


def solid_lathe(profile, segments, wobble=None, flat=False):
    """A lathe from the bottom center, up the side and back to the top center (outward faces)."""
    mesh = lathe(profile, segments)
    if wobble is not None:
        wobble(mesh)
    mesh = closed_out(mesh, (0.0, (profile[0][1] + profile[-1][1]) / 2, 0.0)) if not flat else mesh
    mesh.smooth = not flat
    return mesh


def flat_star(outer, inner, points, depth):
    mesh = extrude(star(outer, inner, points), depth)
    return closed_out(mesh, (0.0, 0.0, 0.0))


def ring_polygon(radius, count, start=0.0):
    return [(math.cos(start + 2 * math.pi * i / count) * radius, math.sin(start + 2 * math.pi * i / count) * radius) for i in range(count)]


def surface_lathe(profile, segments, desired, noise=None):
    """An open lathe surface (no caps) oriented by `desired`, with optional vertex noise(v) -> dy."""
    mesh = lathe(profile, segments)
    if noise is not None:
        mesh.v[:, 1] += noise(mesh.v)
    return oriented(mesh, desired)


def anchors(mesh, radius, y):
    """Adds four tiny triangles at +-radius on X and Z (hidden under the ground) so the piece's bounding
    box is centered on the funnel's axis: Roblox places a MeshPart by its bounding box, and the game
    turns the swirl rings about that axis."""
    extra = []
    for x, z in ((radius, 0.0), (-radius, 0.0), (0.0, radius), (0.0, -radius)):
        extra.append(Mesh([(x, y, z), (x + 0.04, y, z), (x, y, z + 0.04)], [(0, 2, 1)]))
    smooth = mesh.smooth
    out = merge(mesh, *extra)
    out.smooth = smooth
    return out


# ---------------------------------------------------------------- the pit

def sand_pit():
    """The arena: a flat-topped desert mesa whose middle is a quicksand funnel draining into a dark
    sinkhole. The mesa top is at y = MESA (the rim level); the cliffs fall to the desert floor at 0."""
    top = MESA
    segments = 112

    def ripples(v):
        r = np.sqrt(v[:, 0] ** 2 + v[:, 2] ** 2)
        a = np.arctan2(v[:, 2], v[:, 0])
        inside = np.clip((RIM - r) / 3.0, 0, 1) * np.clip((r - LIP_R) / 3.0, 0, 1)
        outside = np.clip((r - RIM - 3) / 6.0, 0, 1) * np.clip((PLAZA - 3 - r) / 4.0, 0, 1)
        wave = 0.05 * np.sin(r * 2.1 + 1.3 * np.sin(a * 3)) * inside
        dunes = 0.05 * (np.sin(a * 7 + r * 0.4) + np.sin(a * 11 - r * 0.25)) * outside
        return wave + dunes

    # One continuous profile from the mesa edge inward, down the throat, to the throat floor
    # (that order makes every face look up or into the hole). It is split into pieces by color.
    outer = [(PLAZA - 0.1, top - 0.9), (PLAZA - 0.6, top - 0.35), (PLAZA - 1.4, top - 0.08), (PLAZA - 2.6, top)]
    plaza = [(r, top) for r in np.linspace(PLAZA - 6, RIM + 2, 8)]
    funnel = []
    for i in range(31):
        t = i / 30
        r = RIM - (RIM - LIP_R) * (t ** 1.15)
        funnel.append((r, top + sand_height(r)))
    lip = []
    for i in range(1, 15):
        t = i / 14
        r = LIP_R - (LIP_R - HOLE) * t
        lip.append((r, top + sand_height(r)))
    edge = [(HOLE - 0.12, top - DEPTH - 0.18), (HOLE - 0.28, top - DEPTH - 0.6), (HOLE - 0.36, top - DEPTH - 1.25)]
    throat = [(HOLE - 0.38, top - DEPTH - 2.0), (HOLE - 0.45, top - 16), (HOLE - 0.55, top - 23), (HOLE - 0.6, top + THROAT_BOTTOM + 0.6),
              (HOLE - 1.0, top + THROAT_BOTTOM), (2.0, top + THROAT_BOTTOM - 0.1), (0.0, top + THROAT_BOTTOM - 0.1)]

    sand_profile = outer + plaza + funnel
    sand = surface_lathe(sand_profile, segments, upward, ripples)
    lip_profile = [funnel[-1]] + lip + edge
    lip_mesh = surface_lathe(lip_profile, segments, lambda c: np.stack([-c[:, 0] * 0.3, np.ones(len(c)), -c[:, 2] * 0.3], 1))
    throat_profile = [edge[-1]] + throat
    throat_mesh = lathe(throat_profile, 64)
    throat_mesh = oriented(throat_mesh, lambda c: np.stack([-c[:, 0], np.where(c[:, 1] < top + THROAT_BOTTOM + 0.3, 50.0, 0.0), -c[:, 2]], 1))

    # Cliffs: stepped sandstone strata with a rocky wobble, from the desert floor up to the mesa top.
    rng = np.random.default_rng(31)
    phases = rng.uniform(0, 2 * math.pi, 4)

    def cliff_wobble(a, y):
        return 1 + 0.035 * np.sin(a * 5 + phases[0]) + 0.025 * np.sin(a * 13 + y * 0.15 + phases[1]) + 0.015 * np.sin(a * 29 + phases[2])

    cliff_profile = [(PLAZA + 10.5, 0.0), (PLAZA + 9.6, 2.5), (PLAZA + 8.4, 5.0), (PLAZA + 8.0, 9.0), (PLAZA + 6.6, 10.5),
                     (PLAZA + 6.0, 15.5), (PLAZA + 5.2, 18.5), (PLAZA + 3.6, 20.0), (PLAZA + 3.2, 25.0), (PLAZA + 2.2, 28.5),
                     (PLAZA + 1.2, 30.0), (PLAZA + 1.0, 34.0), (PLAZA + 0.5, 37.5), (PLAZA + 0.2, top - 1.6), (PLAZA - 0.1, top - 0.9)]
    cliff = lathe(cliff_profile, 120)
    angle = np.arctan2(cliff.v[:, 2], cliff.v[:, 0])
    cliff.v[:, [0, 2]] *= cliff_wobble(angle, cliff.v[:, 1])[:, None]
    cliff = oriented(cliff, radial(lift=0.0))
    cliff.smooth = False

    def cliff_radius(y):
        ys = [p[1] for p in cliff_profile]
        rs = [p[0] for p in cliff_profile]
        return float(np.interp(y, ys, rs))

    bands = []
    for y0, y1 in ((10.6, 12.2), (20.1, 21.4), (30.1, 31.2)):
        profile = []
        for y in (y0, (y0 + y1) / 2, y1):
            profile.append((cliff_radius(y) + 0.45, y))
        band = lathe([(cliff_radius(y0) - 0.6, y0)] + profile + [(cliff_radius(y1) - 0.6, y1)], 120)
        a = np.arctan2(band.v[:, 2], band.v[:, 0])
        band.v[:, [0, 2]] *= cliff_wobble(a, band.v[:, 1])[:, None]
        mid = (y0 + y1) / 2
        band = oriented(band, lambda c, mid=mid: np.stack([c[:, 0], (c[:, 1] - mid) * 40.0, c[:, 2]], 1))
        band.smooth = False
        bands.append(band)
    cliff = anchors(cliff, PLAZA + 22.0, -0.3)
    return {"Sand": sand, "Lip": lip_mesh, "Throat": throat_mesh, "Cliff": cliff, "Strata": merge(*bands)}


def sand_swirl():
    """Light streaks lying on the funnel in five rings, plus the whirl inside the throat. The client
    turns each ring at its own speed (faster towards the hole), so the sand visibly swirls."""
    lift = 0.14
    rng = np.random.default_rng(77)
    pieces = {}
    for k in range(5):
        r0, r1 = RINGS[k] + 0.25, RINGS[k + 1] - 0.25
        area = math.pi * (r1 ** 2 - r0 ** 2)
        want = int(area * (0.05 if k == 0 else 0.042))
        placed = []  # (polyline points, half width) for spacing checks
        verts, faces = [], []
        tries = 0
        while len(placed) < want and tries < want * 60:
            tries += 1
            width = rng.uniform(0.35, 0.6) if k < 2 else rng.uniform(0.45, 0.85)
            rho = rng.uniform(r0 + width, r1 - width)
            length = rng.uniform(2.2, 4.0) if k < 2 else rng.uniform(3.0, 6.5)
            sweep = length / rho
            start = rng.uniform(0, 2 * math.pi)
            bend = rng.uniform(-0.35, 0.35) * min(1.0, (r1 - r0) / 6)
            steps = 10
            center = []
            for i in range(steps + 1):
                t = i / steps
                a = start + sweep * t
                rr = rho + bend * math.sin(math.pi * t)
                center.append((rr, a, t))
            pts = np.array([[rr * math.cos(a), rr * math.sin(a)] for rr, a, _ in center])
            ok = True
            for other, other_w in placed:
                d = np.min(np.linalg.norm(pts[:, None, :] - other[None, :, :], axis=2))
                if d < width / 2 + other_w + 0.45:
                    ok = False
                    break
            if not ok:
                continue
            placed.append((pts, width / 2))
            base = len(verts)
            for rr, a, t in center:
                half = width / 2 * max(0.08, math.sin(math.pi * t)) ** 0.7
                for side in (-1, 1):
                    rs = min(r1, max(r0, rr + side * half))
                    verts.append((rs * math.cos(a), sand_height(rs) + lift, rs * math.sin(a)))
            for i in range(steps):
                a0, a1 = base + 2 * i, base + 2 * i + 1
                b0, b1 = a0 + 2, a1 + 2
                faces += [(a0, b0, a1), (a1, b0, b1)]
        mesh = oriented(Mesh(verts, faces), upward)
        pieces[f"Swirl{k + 1}"] = mesh

    # The whirl: spiral ribbons on the throat wall pouring down into the dark.
    verts, faces = [], []
    wall = HOLE - 0.55
    for strand in range(9):
        start = strand / 9 * 2 * math.pi + rng.uniform(-0.15, 0.15)
        top_y = -DEPTH - 1.4 - rng.uniform(0, 0.6)
        bottom_y = WHIRL_BOTTOM if strand == 0 else WHIRL_BOTTOM + rng.uniform(0.4, 2.5)
        width = rng.uniform(0.45, 0.75)
        steps = 16
        base = len(verts)
        for i in range(steps + 1):
            t = i / steps
            a = start + t * 2.0
            y = top_y + (bottom_y - top_y) * t
            half = width / 2 * max(0.15, math.sin(math.pi * min(1.0, t * 1.15)) ** 0.5)
            for side in (-1, 1):
                yy = y + side * half
                if strand == 0 and i == steps:
                    yy = max(yy, WHIRL_BOTTOM)
                verts.append((wall * math.cos(a), yy, wall * math.sin(a)))
        for i in range(steps):
            a0, a1 = base + 2 * i, base + 2 * i + 1
            b0, b1 = a0 + 2, a1 + 2
            faces += [(a0, b0, a1), (a1, b0, b1)]
    whirl = Mesh(verts, faces)
    whirl.v[:, 1] = np.maximum(whirl.v[:, 1], WHIRL_BOTTOM)
    pieces["Whirl"] = oriented(whirl, lambda c: np.stack([-c[:, 0], np.zeros(len(c)), -c[:, 2]], 1))

    # Center every piece on the axis, then put the lowest point (the whirl's foot, exactly
    # WHIRL_BOTTOM below the rim) on y = 0.
    for name in pieces:
        pieces[name] = anchors(pieces[name], RIM + 0.5, -1.0)
    for mesh in pieces.values():
        mesh.v[:, 1] -= WHIRL_BOTTOM
    return pieces


# ---------------------------------------------------------------- treasure

def sand_coin():
    """A fat gold coin standing on its edge (faces look along Z), with a raised rim, a reeded edge
    and an embossed star on both faces."""
    radius, half = 1.15, 0.2
    profile = [(0.0, -half + 0.06), (0.86, -half + 0.06), (0.9, -half), (1.05, -half), (radius, -half + 0.07),
               (radius, half - 0.07), (1.05, half), (0.9, half), (0.86, half - 0.06), (0.0, half - 0.06)]
    coin = lathe(profile, 48)
    # Reeded edge: tiny grooves round the rim.
    r = np.sqrt(coin.v[:, 0] ** 2 + coin.v[:, 2] ** 2)
    a = np.arctan2(coin.v[:, 2], coin.v[:, 0])
    edge = r > radius - 0.01
    coin.v[edge, 0] *= 1 + 0.02 * np.sin(a[edge] * 48)
    coin.v[edge, 2] *= 1 + 0.02 * np.sin(a[edge] * 48)
    stars = []
    for side in (-1, 1):
        s = flat_star(0.62, 0.27, 5, 0.1).rotate("x", 90).translate(0, side * (half - 0.03), 0)
        stars.append(s)
    emblem = merge(*stars)
    emblem.smooth = False
    out = {"Coin": coin, "Emblem": emblem}
    for mesh in out.values():
        mesh.rotate("x", 90).translate(0, radius, 0)
    return out


def sand_gem():
    """A cut gem: an octagonal crown with a table on top and a pointed pavilion, flat-shaded so its
    facets sparkle (recolored per gem in-game)."""
    segments = 8
    profile = [(0.0, 0.0), (0.7, 0.55), (1.12, 1.18), (1.12, 1.32), (0.85, 1.72), (0.55, 1.95), (0.0, 1.95)]
    gem = lathe(profile, segments)
    # Twist the crown's upper ring half a facet so the facets read as a real cut.
    top = gem.v[:, 1] > 1.5
    a = np.arctan2(gem.v[top, 2], gem.v[top, 0]) + math.pi / segments
    rr = np.sqrt(gem.v[top, 0] ** 2 + gem.v[top, 2] ** 2)
    gem.v[top, 0] = np.cos(a) * rr
    gem.v[top, 2] = np.sin(a) * rr
    gem.smooth = False
    return {"Gem": gem}


def coin_bag():
    """A plump cloth money sack tied with rope, a gold coin badge on the front and coins peeking
    out of the top."""
    profile = [(0.0, 0.0), (0.85, 0.04), (1.25, 0.35), (1.42, 0.85), (1.38, 1.45), (1.12, 1.9), (0.7, 2.2), (0.46, 2.36),
               (0.44, 2.46), (0.62, 2.56), (0.86, 2.72), (0.74, 2.86), (0.4, 2.8), (0.0, 2.74)]
    sack = organic_lathe(profile, 30, 0.045, waves=7, seed=12)
    rope = torus(0.5, 0.11, 28, 8).translate(0, 2.42, 0)
    knot = merge(tube_out([(0.42, 2.42, -0.2), (0.6, 2.2, -0.42), (0.66, 1.95, -0.5)], 0.08, 6),
                 tube_out([(0.42, 2.42, -0.2), (0.25, 2.15, -0.5), (0.3, 1.9, -0.58)], 0.08, 6))
    badge = cylinder(0.5, 0.12, 24, 0.04).rotate("x", 90).translate(0, 1.15, -1.5)
    badge_star = flat_star(0.3, 0.13, 5, 0.06).translate(0, 1.15, -1.53)
    peek = [cylinder(0.32, 0.08, 18, 0.02).rotate("x", 70).rotate("y", ang).translate(x, 2.86, z)
            for ang, x, z in ((20, 0.18, 0.05), (-35, -0.2, -0.08))]
    emblem = merge(badge, badge_star, *peek)
    return {"Sack": sack, "Rope": merge(rope, knot), "Emblem": emblem}


def golden_idol():
    """The Golden Idol: a chubby sitting cat statue on a stepped plinth, with gem eyes."""
    def sdf(p):
        body = sd_ellipsoid(p, (0, 1.45, 0.15), (0.78, 0.95, 0.7))
        chest = sd_ellipsoid(p, (0, 1.75, -0.22), (0.55, 0.65, 0.45))
        head = sd_ellipsoid(p, (0, 2.62, -0.2), (0.62, 0.55, 0.55))
        muzzle = sd_ellipsoid(p, (0, 2.48, -0.66), (0.26, 0.18, 0.16))
        d = smin(body, chest, 0.25)
        d = smin(d, head, 0.18)
        d = smin(d, muzzle, 0.08)
        for side in (-1, 1):
            ear = sd_capsule(p, (side * 0.32, 2.95, -0.18), (side * 0.48, 3.38, -0.12), 0.12)
            d = smin(d, ear, 0.1)
            paw = sd_ellipsoid(p, (side * 0.3, 0.72, -0.48), (0.22, 0.2, 0.3))
            d = smin(d, paw, 0.12)
            haunch = sd_ellipsoid(p, (side * 0.55, 0.95, 0.3), (0.35, 0.45, 0.5))
            d = smin(d, haunch, 0.2)
        tail = np.minimum(sd_capsule(p, (0.5, 0.62, 0.68), (0.85, 0.66, 0.0), 0.13), sd_capsule(p, (0.85, 0.66, 0.0), (0.62, 0.62, -0.55), 0.12))
        d = smin(d, tail, 0.1)
        return d

    cat = sdf_mesh(sdf, (-1.2, 0.45, -1.1), (1.2, 3.6, 1.1), 0.07)
    outward(cat)
    cat.translate(0, 0.4, 0)
    plinth = merge(rounded_box(2.4, 0.42, 2.2, 0.12, 4).translate(0, 0.21, 0), rounded_box(2.0, 0.42, 1.85, 0.12, 4).translate(0, 0.58, 0))
    collar = torus(0.5, 0.07, 24, 6).scale(1.0, 1.0, 0.85).translate(0, 2.5, -0.25)
    eyes = merge(*(icosphere(0.1, 1).scale(1.0, 1.25, 0.6).translate(side * 0.22, 3.12, -0.7) for side in (-1, 1)))
    gem = icosphere(0.13, 1).translate(0, 2.48, -0.68)
    return {"Gold": merge(cat, plinth, collar), "Eyes": merge(eyes, gem)}


# ---------------------------------------------------------------- the Sand Kings and the desert

def sand_throne():
    """A Sand King's royal throne on a gold-rimmed dais (faces -Z): a back with a turquoise cap and a
    golden sunburst with a glowing gem leaning back over it (kept low, so a seated King's camera
    still sees over it into the funnel), cat-head armrests, a cushion and back pad (colored per
    team in-game) and two gold posts topped with glowing orbs. The seat stays where the game's Seat
    is (cushion top at 3.45, z = 0.5), and the footprint is centered so the pivot doesn't move."""
    stone = [box(9.6, 0.7, 7.4, y=0.35, bevel=0.15), box(8.0, 0.7, 6.0, y=1.05, z=0.5, bevel=0.15),
             box(4.2, 1.6, 3.4, y=2.2, z=0.5, bevel=0.15), box(4.4, 6.8, 1.0, y=4.8, z=2.6, bevel=0.2)]
    gold = [box(9.8, 0.2, 7.6, y=0.42, bevel=0.06), box(8.2, 0.2, 6.2, y=1.12, z=0.5, bevel=0.06)]
    paint = [box(4.7, 0.6, 1.3, y=8.5, z=2.6, bevel=0.15)]
    for side in (-1, 1):
        stone.append(box(1.0, 1.5, 3.6, x=side * 2.6, y=3.0, z=0.4, bevel=0.2))
        paint.append(box(0.5, 6.7, 1.15, x=side * 2.05, y=4.8, z=2.6, bevel=0.1))
        gold.append(box(1.1, 0.25, 3.7, x=side * 2.6, y=3.7, z=0.4, bevel=0.06))
        # A little gold cat head on the front of each armrest.
        head = solid(sphere(0.62, 8, 14), True).scale(1.0, 0.9, 0.9).translate(side * 2.6, 4.05, -1.35)
        ears = [solid(lathe([(0.0, 0.0), (0.22, 0.0), (0.0, 0.45)], 8)).translate(side * 2.6 + e * 0.32, 4.45, -1.3) for e in (-1, 1)]
        gold += [head, *ears]
        # Posts with glowing orbs.
        gold.append(solid(cylinder(0.3, 7.8, 12)).translate(side * 4.2, 0.7, 1.9))
        gold.append(solid(lathe([(0.0, 8.3), (0.55, 8.3), (0.75, 8.8), (0.0, 8.8)], 14)).translate(side * 4.2, 0, 1.9))
    glow = [solid(icosphere(0.62, 2), True).translate(side * 4.2, 9.35, 1.9) for side in (-1, 1)]
    sun = sun_disc(1.15, 0.45, rays=12, segments=24).rotate("x", 20).translate(0, 9.55, 2.75)
    gold.append(sun)
    glow.append(solid(icosphere(0.5, 2), True).scale(1, 1, 0.6).rotate("x", 20).translate(0, 9.6, 2.5))
    cushion = rounded_box(3.6, 0.5, 3.0, 0.24, 6).translate(0, 3.2, 0.5)
    back_pad = rounded_box(3.2, 4.0, 0.4, 0.18, 6).translate(0, 5.6, 1.95)
    return {"Stone": merge(*stone), "Gold": merge(*gold), "Paint": merge(*paint), "Cushion": merge(cushion, back_pad), "Glow": merge(*glow)}


def sand_crown():
    """A chunky gold crown with five points tipped with balls and gems round the band."""
    points = 5
    segments = 60
    verts, faces = [], []
    radius, thick = 0.62, 0.12
    rows = []
    for rr, y_kind in ((radius + thick, "base"), (radius + thick, "top"), (radius, "top"), (radius, "base")):
        row = []
        for s in range(segments):
            a = 2 * math.pi * s / segments
            if y_kind == "base":
                y = 0.0
            else:
                phase = (s / segments * points) % 1.0
                y = 0.42 + 0.5 * (1 - abs(phase - 0.5) * 2) ** 1.6
            row.append(len(verts))
            verts.append((math.cos(a) * rr, y, math.sin(a) * rr))
        rows.append(row)
    for i in range(4):
        r0, r1 = rows[i], rows[(i + 1) % 4]
        for s in range(segments):
            a, b = r0[s], r0[(s + 1) % segments]
            c, d = r1[s], r1[(s + 1) % segments]
            faces += [(a, c, b), (b, c, d)]  # outward (Roblox culls back faces)
    band = Mesh(verts, faces)
    band.smooth = False
    tips = [sphere(0.1, 6, 10).translate(math.cos(2 * math.pi * (k + 0.5) / points) * (radius + 0.06), 0.95,
                                         math.sin(2 * math.pi * (k + 0.5) / points) * (radius + 0.06)) for k in range(points)]
    gold = merge(band, *tips)
    gems = []
    for k in range(points):
        a = 2 * math.pi * (k + 0.5) / points
        gems.append(icosphere(0.11, 1).scale(1.0, 1.0, 0.55).rotate("y", -math.degrees(a) + 90)
                    .translate(math.cos(a) * (radius + thick + 0.02), 0.22, math.sin(a) * (radius + thick + 0.02)))
    gem = merge(*gems)
    gem.smooth = False
    return {"Gold": gold, "Gems": gem}


def cactus():
    """A saguaro: a ribbed trunk with two upturned arms and pink flowers on top."""
    trunk_profile = [(0.0, 0.0), (0.95, 0.0), (1.0, 0.6), (0.98, 4.0), (0.95, 7.0), (0.85, 8.6), (0.6, 9.4), (0.3, 9.75), (0.0, 9.85)]
    trunk = lathe(trunk_profile, 36)
    angle = np.arctan2(trunk.v[:, 2], trunk.v[:, 0])
    rib = 1 + 0.07 * np.cos(angle * 12)
    trunk.v[:, 0] *= rib
    trunk.v[:, 2] *= rib
    trunk = closed_out(trunk, (0.0, 4.9, 0.0))

    def arm(side, y0, out, up):
        pts = []
        for i in range(9):
            t = i / 8
            ang = t * math.pi / 2
            x = side * (0.6 + out * math.sin(ang))
            y = y0 + out * (1 - math.cos(ang)) * 0.6
            pts.append((x, y, 0.0))
        for i in range(1, 5):
            pts.append((side * (0.6 + out), y0 + out * 0.6 + up * i / 4, 0.0))
        body = tapered(pts, 0.62, 0.52, 14)
        cap = sphere(0.52, 8, 14).translate(side * (0.6 + out), y0 + out * 0.6 + up, 0.0)
        return merge(body, cap)

    left = arm(-1, 3.4, 1.6, 2.6).rotate("y", 12)
    right = arm(1, 5.0, 1.3, 2.0).rotate("y", -20)
    body = merge(trunk, left, right)
    flowers = []
    for i, (x, z) in enumerate(((0.25, -0.2), (-0.3, 0.1), (0.05, 0.35))):
        f = flat_star(0.32, 0.14, 5, 0.1).rotate("x", 90).translate(x, 9.62 - 0.08 * i, z)
        flowers.append(f)
        flowers.append(sphere(0.1, 4, 8).translate(x, 9.7 - 0.08 * i, z))
    return {"Cactus": body, "Flower": merge(*flowers)}


def sand_ruin():
    """A broken fluted sandstone column on a stepped plinth, with a fallen drum beside it."""
    rng = np.random.default_rng(5)
    plinth = merge(rounded_box(4.6, 0.7, 4.6, 0.15, 3).translate(0, 0.35, 0), rounded_box(3.6, 0.6, 3.6, 0.15, 3).translate(0, 1.0, 0))
    col_profile = [(0.0, 1.3), (1.25, 1.3), (1.2, 1.8), (1.1, 2.0)] + [(1.05 - 0.01 * i, 2.0 + i * 0.6) for i in range(1, 12)] + [(0.0, 8.6)]
    col = lathe(col_profile, 40)
    angle = np.arctan2(col.v[:, 2], col.v[:, 0])
    flute = 1 + 0.05 * np.cos(angle * 16)
    mask = col.v[:, 1] > 2.0
    col.v[mask, 0] *= flute[mask]
    col.v[mask, 2] *= flute[mask]
    # Jagged broken top: the upper rings drop by a ragged amount.
    top = col.v[:, 1] > 7.0
    drop = np.sin(angle * 3 + 1.1) * 0.7 + np.sin(angle * 7) * 0.35 + 0.9
    col.v[top, 1] -= np.clip(drop[top], 0, None) * (col.v[top, 1] - 7.0) / 1.6
    col = closed_out(col, (0.0, 5.0, 0.0))
    col.smooth = False
    drum = cylinder(1.05, 1.5, 32, 0.12).translate(0, -0.75, 0).rotate("z", 90).rotate("y", 25).translate(2.6, 1.05, -2.4)
    chips = [icosphere(0.35 + rng.uniform(0, 0.25), 1, 0.4, int(rng.integers(0, 99))).translate(rng.uniform(-2.5, 2.5), 0.15, rng.uniform(1.6, 3.0)) for _ in range(4)]
    stone = merge(col, drum)
    base = merge(plinth, *chips)
    base.smooth = False
    return {"Stone": stone, "Base": base}



# ---------------------------------------------------------------- the desert temple (art pass)
# The mesa top becomes the courtyard of a ruined sun temple: a sun-ray mosaic round the funnel, a
# ring of painted columns and four gateways framing it, palms and treasure, and beyond the cliffs a
# golden step-temple with a giant cat sphinx, far pyramids and rolling dunes.

def solid(mesh, smooth=False):
    """Makes a closed, consistently wound part face outward and sets its shading."""
    mesh = outward(mesh)
    mesh.smooth = smooth
    return mesh


def box(sx, sy, sz, x=0.0, y=0.0, z=0.0, bevel=0.06):
    """A crisp box (a hair of bevel) centered on (x, y, z)."""
    return solid(rounded_box(sx, sy, sz, min(bevel, sx / 3, sy / 3, sz / 3), 1)).translate(x, y, z)


def sd_box(p, center, half):
    q = np.abs(p - np.array(center)) - np.array(half)
    return np.linalg.norm(np.maximum(q, 0), axis=-1) + np.minimum(np.max(q, axis=-1), 0)


def components(mesh):
    """Splits a mesh into its connected parts (by shared vertex positions)."""
    _, corner = np.unique(np.round(mesh.v / 1e-5).astype(np.int64), axis=0, return_inverse=True)
    faces = corner.reshape(-1)[mesh.f]
    parent = np.arange(faces.max() + 1)

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for a, b, c in faces:
        ra, rb, rc = root(a), root(b), root(c)
        parent[rb] = ra
        parent[root(rc)] = ra
    labels = np.array([root(f[0]) for f in faces])
    return labels


def outward_parts(mesh):
    """Turns every closed part of a merged mesh outward (each part on its own)."""
    labels = components(mesh)
    tri = mesh.v[mesh.f]
    vol = np.einsum("ij,ij->i", tri[:, 0], np.cross(tri[:, 1], tri[:, 2]))
    for label in np.unique(labels):
        mask = labels == label
        if vol[mask].sum() < 0:
            mesh.f[mask] = mesh.f[mask][:, ::-1]
    return mesh


def split_faces(mesh, keep):
    """The faces of `mesh` where keep[face] is true, as a new mesh (vertices shared)."""
    out = Mesh(mesh.v.copy(), mesh.f[keep].copy(), mesh.smooth)
    return out


def sweep(points, sections):
    """A closed tube along `points` whose cross-section i is a list of (side, normal) offsets in the
    path's local frame (same count for every section); both ends are capped. Faces point outward."""
    pts = np.array(points, dtype=float)
    n = len(pts)
    k = len(sections[0])
    up = np.array([0.0, 1.0, 0.0])
    verts = []
    for i in range(n):
        t = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]
        t /= np.linalg.norm(t) + 1e-9
        ref = up if abs(t @ up) < 0.95 else np.array([1.0, 0, 0])
        side = np.cross(t, ref)
        side /= np.linalg.norm(side)
        normal = np.cross(side, t)
        for s, m in sections[i]:
            verts.append(pts[i] + side * s + normal * m)
    faces = []
    for i in range(n - 1):
        for j in range(k):
            a, b = i * k + j, i * k + (j + 1) % k
            faces += [(a, b, a + k), (b, b + k, a + k)]
    for ring, flip in ((0, True), (n - 1, False)):
        center = len(verts)
        verts.append(np.mean([verts[ring * k + j] for j in range(k)], axis=0))
        for j in range(k):
            a, b = ring * k + j, ring * k + (j + 1) % k
            faces.append((center, b, a) if flip else (center, a, b))
    return outward(Mesh(verts, faces))


def arc_slab(r0, r1, a0, a1, y0, y1, segs=3):
    """An annular-sector slab (a curved paving stone) round the Y axis."""
    verts, faces = [], []
    corners = ((r0, y0), (r1, y0), (r1, y1), (r0, y1))
    for i in range(segs + 1):
        a = a0 + (a1 - a0) * i / segs
        for r, y in corners:
            verts.append((math.cos(a) * r, y, math.sin(a) * r))
    for i in range(segs):
        for j in range(4):
            a, b = i * 4 + j, i * 4 + (j + 1) % 4
            faces += [(a, b, a + 4), (b, b + 4, a + 4)]
    last = segs * 4
    faces += [(0, 2, 1), (0, 3, 2), (last, last + 1, last + 2), (last, last + 2, last + 3)]
    return solid(Mesh(verts, faces))


def cloth(width, height, thick=0.25, notch=0.0, wave=0.0, seed=0):
    """A hanging banner (top edge at y = 0, hanging down, facing -Z) with a swallowtail and a ripple."""
    mesh = rounded_box(width, height, thick, thick * 0.45, 7)
    v = mesh.v
    v[:, 1] -= height / 2
    if notch > 0:
        f = 1 - np.abs(v[:, 0]) / (width / 2)
        s = np.clip(((-height + notch) - v[:, 1]) / notch, 0, 1)
        v[:, 1] += 0.9 * notch * f * s
    if wave > 0:
        v[:, 2] += wave * np.sin(v[:, 1] * 0.55 + seed) * np.clip(-v[:, 1] / 3, 0, 1) + wave * 0.4 * np.sin(v[:, 0] * 1.3 + seed)
    return solid(mesh, smooth=True)


def sun_disc(radius, depth, rays=0, segments=32):
    """A gold sun disc facing -Z (centered on the origin), optionally with rays round it."""
    disc = solid(cylinder(radius, depth, segments, depth * 0.3).translate(0, -depth / 2, 0).rotate("x", 90))
    parts = [disc]
    for i in range(rays):
        a = 360.0 * i / rays
        ray = solid(rounded_box(radius * 0.18, radius * 0.5, depth * 0.8, depth * 0.2, 1)).translate(0, radius * 1.32, 0).rotate("z", a)
        parts.append(ray)
    return merge(*parts)


def column(height=28.0, radius=2.0, broken=0.0, seed=0):
    """A painted temple column: square plinth, fluted shaft, lotus capital and abacus. `broken`
    snaps the shaft off at that height (no capital). Returns pieces Stone, Paint, Gold."""
    plinth = merge(box(radius * 3.1, 0.9, radius * 3.1, y=0.45, bevel=0.15), box(radius * 2.7, 0.7, radius * 2.7, y=1.25, bevel=0.15))
    shaft_top = height - 4.6 if not broken else broken
    base_ring = solid(lathe([(0.0, 1.6), (radius * 1.22, 1.6), (radius * 1.25, 2.0), (radius * 1.12, 2.4), (0.0, 2.4)], 32))
    rows = 10 if broken else 5  # (a broken top needs the rows for its jagged edge)
    profile = [(0.0, 2.3)] + [(radius * (1.02 - 0.12 * (i / rows) ** 1.4), 2.3 + (shaft_top - 2.3) * i / rows) for i in range(rows + 1)] + [(0.0, shaft_top)]
    shaft = lathe(profile, 48)
    a = np.arctan2(shaft.v[:, 2], shaft.v[:, 0])
    flute = 1 - 0.05 * np.abs(np.cos(a * 8)) ** 0.5
    shaft.v[:, 0] *= flute
    shaft.v[:, 2] *= flute
    if broken:
        rng = np.random.default_rng(seed)
        ph = rng.uniform(0, 6, 3)
        top = shaft.v[:, 1] > shaft_top - 2.2
        drop = 1.1 + np.sin(a * 3 + ph[0]) * 0.9 + np.sin(a * 7 + ph[1]) * 0.4
        w = (shaft.v[top, 1] - (shaft_top - 2.2)) / 2.2
        shaft.v[top, 1] -= np.clip(drop[top], 0, None) * w
    shaft = solid(shaft)
    stone = [plinth, base_ring, shaft]
    gold, paint = [], []
    gold.append(solid(lathe([(0.0, 2.9), (radius * 1.04, 2.9), (radius * 1.04, 3.4), (0.0, 3.4)], 32)))
    if not broken:
        y0 = shaft_top
        gold.append(solid(lathe([(0.0, y0 - 1.6), (radius * 0.97, y0 - 1.6), (radius * 0.97, y0 - 0.9), (0.0, y0 - 0.9)], 32)))
        # Lotus capital: a flaring bell with eight petal lobes.
        cap = lathe([(0.0, y0 - 0.2)] + [(radius * (0.92 + 0.62 * (i / 6) ** 1.6), y0 - 0.2 + 3.0 * i / 6) for i in range(7)] + [(0.0, y0 + 2.8)], 48)
        ca = np.arctan2(cap.v[:, 2], cap.v[:, 0])
        lobe = 1 + 0.07 * np.cos(ca * 8) * np.clip((cap.v[:, 1] - y0) / 2.6, 0, 1)
        cap.v[:, 0] *= lobe
        cap.v[:, 2] *= lobe
        paint.append(solid(cap))
        stone.append(box(radius * 3.3, 1.0, radius * 3.3, y=height - 1.3, bevel=0.12))
        gold.append(box(radius * 3.45, 0.32, radius * 3.45, y=height - 1.86, bevel=0.08))
        stone.append(box(radius * 3.0, 0.6, radius * 3.0, y=height - 0.3, bevel=0.1))
    else:
        rng = np.random.default_rng(seed + 9)
        drum = solid(cylinder(radius * 0.95, 2.6, 24, 0.15)).translate(0, -1.3, 0).rotate("z", 90).rotate("y", rng.uniform(10, 50)).translate(radius * 2.4, radius * 0.95, radius * 1.6)
        chips = [solid(icosphere(0.5 + rng.uniform(0, 0.5), 1, 0.4, int(rng.integers(0, 99)))).translate(rng.uniform(-3.5, 3.5), 0.25, rng.uniform(-3.2, -1.8)) for _ in range(3)]
        stone += [drum] + chips
    return {"Stone": merge(*stone), "Paint": merge(*paint) if paint else None, "Gold": merge(*gold)}


def _clean(pieces):
    return {k: v for k, v in pieces.items() if v is not None and len(v.f)}


def sand_column():
    """A tall painted temple column with a long royal banner hanging down its front (-Z) face."""
    pieces = column(28.0, 2.0)
    rod = solid(cylinder(0.22, 5.6, 12)).translate(0, -2.8, 0).rotate("z", 90).translate(0, 21.4, -2.55)
    knobs = [solid(sphere(0.38, 6, 10)).translate(side * 2.9, 21.4, -2.55) for side in (-1, 1)]
    pieces["Gold"] = merge(pieces["Gold"], rod, *knobs)
    banner = cloth(4.2, 13.5, 0.22, notch=1.8, wave=0.18, seed=1.2).translate(0, 21.2, -2.75)
    trim = box(4.5, 0.7, 0.3, y=20.9, z=-2.8, bevel=0.08)
    sun = sun_disc(1.0, 0.2, rays=10, segments=16).translate(0, 16.4, -2.98)
    pieces["Cloth"] = banner
    pieces["Gold"] = merge(pieces["Gold"], trim, sun)
    return _clean(pieces)


def sand_column_broken():
    """A temple column snapped off half way, with its fallen drum and chips beside it (centered on
    the column's foot)."""
    pieces = _clean(column(28.0, 2.0, broken=13.5, seed=3))
    pieces["Stone"] = anchors(pieces["Stone"], 7.5, 0.1)
    return pieces


def sand_arch():
    """A temple gateway facing -Z: two painted columns under a lintel with a turquoise cornice and a
    gold winged sun, open for players to walk through (about 14 studs wide)."""
    left = column(26.0, 2.1)
    right = column(26.0, 2.1)
    for piece in left.values():
        if piece is not None:
            piece.translate(-9.0, 0, 0)
    for piece in right.values():
        if piece is not None:
            piece.translate(9.0, 0, 0)
    stone = [left["Stone"], right["Stone"],
             box(25.6, 3.6, 6.4, y=27.8, bevel=0.15),
             box(28.2, 0.9, 8.4, y=32.65, bevel=0.15)]
    # Cavetto cornice: a flared band (wider at the top).
    cornice = []
    for i in range(3):
        cornice.append(box(26.2 + i * 0.7, 0.6, 7.0 + i * 0.5, y=29.9 + i * 0.6, bevel=0.08))
    paint = [left["Paint"], right["Paint"], *cornice]
    gold = [left["Gold"], right["Gold"], box(26.0, 0.5, 6.8, y=26.2, bevel=0.1)]
    # Winged sun on the lintel's front.
    disc = sun_disc(1.7, 0.6, segments=24).translate(0, 27.9, -3.4)
    wing_pts = []
    for i in range(13):
        t = i / 12
        wing_pts.append((2.0 + 8.0 * t, 1.3 - 0.25 * t + 0.5 * math.sin(t * math.pi) ))
    for i in range(13):
        t = 1 - i / 12
        wing_pts.append((2.0 + 8.0 * t, -0.2 - 1.0 * (1 - t) * 0.2 - 0.9 * math.sin(t * math.pi) * (1 - 0.4 * t)))
    wings = []
    for side in (-1, 1):
        pts = [(side * x, y) for x, y in wing_pts]
        wing = solid(extrude(pts, 0.45)).translate(0, 27.9, -3.35)
        wings.append(wing)
        # feather grooves: thin raised strips
        for k in range(4):
            x0 = 3.4 + k * 1.7
            wings.append(box(0.22, 1.4 - k * 0.15, 0.2, x=side * x0, y=27.6, z=-3.62, bevel=0.05))
    gold += [disc, *wings]
    glow = solid(icosphere(0.75, 2)).scale(1, 1, 0.6).translate(0, 27.9, -3.8)
    return _clean({"Stone": merge(*stone), "Paint": merge(*paint), "Gold": merge(*gold), "Glow": glow})


def sand_temple():
    """The golden step-temple behind the arena (faces -Z): five tiers with gold rims and turquoise
    friezes studded with sun discs, a grand stair up the front, a shrine with a dark doorway and a
    glowing golden capstone, tall banner poles and obelisks either side of the stair."""
    stone, steps, gold, paint, dark, cloth_parts = [], [], [], [], [], []
    tiers = [(150, 0, 6), (128, 6, 19), (104, 19, 32), (80, 32, 45), (56, 45, 58)]
    for w, y0, y1 in tiers:
        h = y1 - y0
        stone.append(box(w, h, w * 0.86, y=(y0 + y1) / 2, bevel=0.6))
        gold.append(box(w + 0.8, 1.1, w * 0.86 + 0.8, y=y1 - 0.75, bevel=0.2))
        if h > 8:
            paint.append(box(w + 0.5, 2.4, w * 0.86 + 0.5, y=y1 - 4.4, bevel=0.2))
            count = int(w / 13)
            for i in range(count):
                x = -w / 2 + w * (i + 0.5) / count
                if abs(x) < 12:
                    continue
                gold.append(sun_disc(0.95, 0.45, segments=16).translate(x, y1 - 4.4, -(w * 0.86 / 2 + 0.45)))
    # Shrine and capstone.
    stone.append(box(34, 10, 30, y=63, bevel=0.5))
    gold.append(box(35, 1.0, 31, y=67.6, bevel=0.2))
    paint.append(box(34.6, 2.0, 30.6, y=65.6, bevel=0.2))
    dark.append(box(9.0, 7.0, 0.6, y=61.5, z=-15.1, bevel=0.1))
    gold.append(box(11.0, 1.0, 0.8, y=65.4, z=-15.2, bevel=0.1))
    for side in (-1, 1):
        gold.append(box(1.0, 8.0, 0.8, x=side * 5.0, y=62, z=-15.2, bevel=0.1))
    cap = lathe([(0.0, 68.0), (13.0, 68.0), (0.0, 86.0)], 4)
    cap.rotate("y", 45)
    gold.append(solid(cap))
    glow = [solid(icosphere(2.2, 2)).translate(0, 86.0, 0)]
    # The grand stair, from the front of the base up to the fourth tier.
    front, top_z, rise = -64.5 - 22, -56 * 0.43, 58.0
    count = 29
    for i in range(count):
        y = (i + 1) * rise / count
        z0 = front + (top_z - front) * i / count
        steps.append(box(18.0, rise / count, top_z - z0 + 1, y=y - rise / count / 2, z=(z0 + top_z + 1) / 2, bevel=0.05))
    run = top_z - front
    slope = math.degrees(math.atan2(rise, run))
    length = math.hypot(rise, run)
    for side in (-1, 1):
        rail = box(2.6, 2.4, length + 2, bevel=0.3).rotate("x", -slope).translate(side * 10.2, rise / 2 + 1.0, (front + top_z) / 2)
        paint.append(rail)
        gold.append(box(3.0, 0.6, 3.0, x=side * 10.2, y=2.6, z=front - 0.5, bevel=0.1))
        # Obelisks.
        ob_x, ob_z = side * 52, -82.0
        stone.append(box(8.0, 3.0, 8.0, x=ob_x, y=1.5, z=ob_z, bevel=0.3))
        shaft = lathe([(0.0, 3.0), (3.0, 3.0), (2.1, 44.0), (0.0, 44.0)], 4)
        shaft.rotate("y", 45)
        stone.append(solid(shaft).translate(ob_x, 0, ob_z))
        tip = lathe([(0.0, 44.0), (2.15, 44.0), (0.0, 49.0)], 4)
        tip.rotate("y", 45)
        gold.append(solid(tip).translate(ob_x, 0, ob_z))
        for k in range(4):
            gy = 34 - k * 6
            half = 0.7071 * (3.0 - 0.9 * (gy - 3) / 41)
            gold.append(box(half * 1.3, 0.5, 0.3, x=ob_x, y=gy, z=ob_z - half - 0.05, bevel=0.08))
        # Banner poles flanking the stair foot.
        px, pz = side * 17.0, front - 2.0
        stone.append(box(3.6, 1.6, 3.6, x=px, y=0.8, z=pz, bevel=0.2))
        gold.append(solid(cylinder(0.45, 40.0, 12)).translate(px, 1.6, pz))
        gold.append(solid(sphere(1.1, 8, 12)).translate(px, 42.0, pz))
        gold.append(solid(cylinder(0.3, 9.0, 10)).translate(0, -4.5, 0).rotate("z", 90).translate(px, 39.0, pz - 0.6))
        cloth_parts.append(cloth(8.0, 26.0, 0.4, notch=3.5, wave=0.5, seed=side).translate(px, 38.8, pz - 1.0))
        gold.append(sun_disc(1.9, 0.3, rays=12).translate(px, 30.0, pz - 1.5))
    # The obelisk glyph strips are drawn as gold inlays on their front faces.
    pieces = {"Stone": merge(*stone), "Steps": merge(*steps), "Gold": merge(*gold), "Paint": merge(*paint),
              "Dark": merge(*dark), "Cloth": merge(*cloth_parts), "Glow": merge(*glow)}
    return _clean(pieces)


def collar_band(r0, r1, a0, a1, depth, n=16):
    """A flat crescent band (a slice of a ring between radii r0 and r1, angles a0..a1 in degrees, in
    the XY plane, `depth` thick along Z), closed and facing outward: one row of a broad collar."""
    angles = np.radians(np.linspace(a0, a1, n + 1))
    verts = []
    for z in (-depth / 2, depth / 2):
        for r in (r0, r1):
            verts += [(r * math.cos(a), r * math.sin(a), z) for a in angles]
    m = n + 1
    fi, fo, bi, bo = 0, m, 2 * m, 3 * m  # front inner/outer, back inner/outer rows
    groups = []

    def quads(a, b, want):
        faces = []
        for i in range(n):
            faces += [(a + i, b + i, b + i + 1), (a + i, b + i + 1, a + i + 1)]
        groups.append((faces, want))

    quads(fi, fo, lambda c: np.tile([0.0, 0.0, -1.0], (len(c), 1)))
    quads(bi, bo, lambda c: np.tile([0.0, 0.0, 1.0], (len(c), 1)))
    quads(fo, bo, lambda c: c * np.array([1.0, 1.0, 0.0]))
    quads(fi, bi, lambda c: -c * np.array([1.0, 1.0, 0.0]))
    pieces = []
    for faces, want in groups:
        pieces.append(oriented(Mesh(verts, faces), want))
    for k, sign in ((0, -1), (n, 1)):  # the two ends
        a = angles[k]
        tangent = np.array([-math.sin(a), math.cos(a), 0.0]) * sign
        end = Mesh(verts, [(fi + k, fo + k, bo + k), (fi + k, bo + k, bi + k)])
        pieces.append(oriented(end, lambda c, t=tangent: np.tile(t, (len(c), 1))))
    mesh = merge(*pieces)
    mesh.smooth = False
    return mesh


def sand_sphinx():
    """A giant cat sphinx lying with its paws forward (-Z): a striped royal nemes headdress that frames
    the face (gold brow band and cobra, flaring wings, lappets on the chest and a braided beard), a
    broad usekh collar of gold and blue rows with a gem, almond eyes that glow and a cat's muzzle: the Sand Kings'
    guardian behind the arena."""
    def torso_sdf(p):
        d = sd_ellipsoid(p, (0, 2.0, 1.6), (2.2, 1.7, 4.0))
        d = smin(d, sd_ellipsoid(p, (0, 2.7, -1.5), (1.85, 2.0, 1.8)), 0.6)
        for s in (-1, 1):
            d = smin(d, sd_ellipsoid(p, (s * 1.55, 1.6, 4.0), (1.15, 1.45, 1.9)), 0.5)
            d = smin(d, sd_capsule(p, (s * 1.25, 1.2, -1.2), (s * 1.25, 0.62, -4.9), 0.62), 0.45)
            d = smin(d, sd_ellipsoid(p, (s * 1.25, 0.55, -5.2), (0.78, 0.52, 0.95)), 0.25)
        d = smin(d, sd_capsule(p, (0, 4.0, -2.2), (0, 2.8, -1.6), 1.05), 0.5)
        tail = np.minimum(sd_capsule(p, (1.6, 0.45, 5.4), (2.35, 0.45, 3.4), 0.36), sd_capsule(p, (2.35, 0.45, 3.4), (2.3, 0.45, 0.6), 0.34))
        return smin(d, tail, 0.2)

    def head_sdf(p):
        d = sd_ellipsoid(p, (0, 5.3, -2.55), (1.45, 1.32, 1.3))
        for s in (-1, 1):  # a cat's whisker pads
            d = smin(d, sd_ellipsoid(p, (s * 0.34, 4.72, -3.6), (0.46, 0.4, 0.46)), 0.2)
        return d

    def body_sdf(p):
        return np.maximum(smin(torso_sdf(p), head_sdf(p), 0.35), -p[..., 1])  # flat underside

    def cap_sdf(p):
        return sd_ellipsoid(p, (0, 5.6, -2.35), (1.78, 1.55, 1.62))

    def nemes_sdf(p):
        x, y, z = p[..., 0], p[..., 1], p[..., 2]
        cap = cap_sdf(p)
        # The wings: a trapezoid behind the face flaring out toward the shoulders, open under the chin.
        t = np.clip((5.6 - y) / 2.2, 0.0, 1.0)
        wing = np.maximum(np.abs(x) - (1.7 + 0.8 * t), np.maximum(np.abs(y - 4.5) - 1.15, np.abs(z + 2.4) - 0.8)) - 0.08
        wing = np.maximum(wing, -np.maximum(np.abs(x) - 1.15, y - 4.75))
        hood = smin(cap, wing, 0.35)
        hood = np.minimum(np.maximum(hood, -(z + 3.28)),  # open round the face...
                          np.maximum(np.maximum(cap, -(z + 3.8)), 5.85 - y))  # ...but covering the forehead
        d = hood
        for s in (-1, 1):  # lappets hanging down the chest, widening a little toward the bottom
            w = 0.42 + 0.12 * np.clip((4.0 - y) / 1.7, 0.0, 1.0)
            lappet = np.maximum(np.abs(x - s * 1.62) - w, np.maximum(np.abs(y - 3.15) - 0.95, np.abs(z + 2.78) - 0.36)) - 0.08
            d = np.minimum(d, lappet)
        d = smin(d, sd_box(p, (0, 4.3, -0.95), (0.85, 1.25, 0.4)) - 0.2, 0.3)  # the tail of cloth behind
        beard = sd_capsule(p, (0, 4.3, -3.5), (0, 3.25, -3.85), 0.24)
        return np.minimum(d, beard)

    def band_sdf(p):
        # The gold brow band across the front of the headdress, and a little cobra rising from it.
        band = np.maximum(np.maximum(cap_sdf(p) - 0.12, np.abs(p[..., 1] - 5.98) - 0.16), p[..., 2] + 2.6)
        cobra = smin(sd_capsule(p, (0, 6.0, -4.02), (0, 6.55, -3.98), 0.12), sd_ellipsoid(p, (0, 6.62, -3.98), (0.24, 0.2, 0.1)), 0.08)
        return np.minimum(band, cobra)

    def sdf(p):
        return np.minimum(np.minimum(body_sdf(p), nemes_sdf(p)), band_sdf(p))

    mesh = sdf_mesh(sdf, (-3.2, -0.2, -6.6), (3.4, 7.6, 6.2), 0.18)
    outward(mesh)
    tri = mesh.v[mesh.f].mean(axis=1)
    label = np.argmin(np.stack([body_sdf(tri), nemes_sdf(tri), band_sdf(tri)]), axis=0)
    stripe = (np.floor((tri[:, 1] + 0.1 * tri[:, 2]) / 0.4) % 2) == 0  # level bands on the headdress
    body = split_faces(mesh, label == 0)
    gold = split_faces(mesh, ((label == 1) & stripe) | (label == 2))
    blue = split_faces(mesh, (label == 1) & ~stripe)
    # The usekh collar: crescent rows of gold and blue round the throat, bent to lie on the chest.
    rows = [(0.36, 0.7), (0.7, 0.95), (0.95, 1.18), (1.18, 1.38), (1.38, 1.5)]
    collar_rows = []
    for k, (r0, r1) in enumerate(rows):
        band = collar_band(r0, r1, 196, 344, 0.3 + 0.02 * k, 20)
        band.v[:, 2] += 0.26 * band.v[:, 0] ** 2  # wrap round the chest
        collar_rows.append(band.translate(0, 4.32, -3.36 - 0.01 * k))
    gold = merge(gold, *collar_rows[0::2])
    blue = merge(blue, *collar_rows[1::2])
    eyes = merge(*(solid(icosphere(0.27, 2), True).scale(1.45, 0.75, 0.55).rotate("z", s * -10).translate(s * 0.6, 5.45, -3.74) for s in (-1, 1)))
    nose = solid(lathe([(0.0, 0.0), (0.24, 0.0), (0.0, -0.22)], 3), True).scale(1.0, 1.0, 0.6).rotate("y", 30).translate(0, 5.14, -4.02)
    gem = merge(solid(icosphere(0.32, 1)).scale(1, 1.2, 0.7).translate(0, 2.9, -3.6), solid(icosphere(0.16, 1)).translate(0, 6.62, -4.1))
    plinth = merge(box(7.2, 0.5, 13.6, y=-0.25, bevel=0.1), box(7.8, 0.3, 14.2, y=-0.6, bevel=0.08))
    for piece in (body, gold, blue, eyes, nose, gem, plinth):
        piece.translate(0, 0.75, 0)
    k = 4.6
    pieces = {"Body": body, "Nemes": gold, "NemesBlue": blue, "Eyes": eyes, "Nose": nose, "Gem": gem, "Plinth": plinth}
    for piece in pieces.values():
        piece.scale(k)
    return pieces


def sand_pyramid():
    """A far pyramid (base 90, height 60) built in shallow steps, with a gold capstone."""
    tiers = 12
    stone = []
    for i in range(tiers):
        w0 = 90 * (1 - i / tiers)
        h = 52 / tiers
        stone.append(box(w0, h, w0, y=h * (i + 0.5), bevel=0.5))
    cap = lathe([(0.0, 51.5), (90 / tiers * 0.72 * 1.2, 51.5), (0.0, 60.0)], 4)
    cap.rotate("y", 45)
    return {"Stone": merge(*stone), "Gold": solid(cap)}


def sand_dune():
    """A big crescent dune (200 x 110, 26 tall): a gentle windward back (+Z), a steep lee face and a
    sharp curved crest. Its skirt sits 3 studs down: placed that far below the desert floor, it meets the
    floor at a clear angle and the hidden part stays buried."""
    nx, nz = 28, 20
    xs = np.linspace(-1, 1, nx)
    zs = np.linspace(-1, 1, nz)
    verts = []
    for z in zs:
        for x in xs:
            crest = 0.28 * math.sin(1.6 * x) - 0.18 * x * x
            d = z - crest
            prof = math.exp(-(d / 0.62) ** 2) if d > 0 else math.exp(-(d / 0.34) ** 2)
            spread = math.exp(-(x / 0.78) ** 4)
            y = 26.0 * prof * spread - 3.0
            verts.append((x * 100, y, z * 55))
    faces = []
    for j in range(nz - 1):
        for i in range(nx - 1):
            a = j * nx + i
            faces += [(a, a + nx, a + 1), (a + 1, a + nx, a + nx + 1)]
    mesh = oriented(Mesh(verts, faces), upward)
    mesh.smooth = True
    return {"Dune": mesh}


def sand_palm():
    """A curvy palm: ringed trunk leaning over, thirteen arching fronds and coconuts. About 22 tall."""
    rng = np.random.default_rng(12)
    path = []
    n = 9
    for i in range(n + 1):
        t = i / n
        path.append((3.2 * t ** 1.8, 18.0 * t, 0.6 * math.sin(t * 2.5)))
    trunk_pts, sections = [], []
    for i in range(n):
        p0, p1 = np.array(path[i]), np.array(path[i + 1])
        r = 0.95 - 0.4 * i / n
        for t, scale in ((0.0, 1.14), (0.15, 1.0), (1.0, 0.86)):
            trunk_pts.append(tuple(p0 + (p1 - p0) * t))
            sections.append([(math.cos(2 * math.pi * j / 8) * r * scale, math.sin(2 * math.pi * j / 8) * r * scale) for j in range(8)])
    # drop duplicate consecutive points (keep the step by nudging them)
    pts = []
    for i, q in enumerate(trunk_pts):
        q = np.array(q)
        if pts and np.linalg.norm(q - pts[-1]) < 1e-6:
            q = q + (np.array(path[min(len(path) - 1, i // 3 + 1)]) - q) * 0.02
        pts.append(q)
    trunk = sweep(pts, sections)
    trunk.smooth = False
    top = np.array(path[-1])
    leaves = []
    for k in range(13):
        low = k >= 8  # a lower ring of older, droopier fronds
        yaw = 2 * math.pi * (k / 8 if not low else (k - 8 + 0.5) / 5) + rng.uniform(-0.12, 0.12)
        length = rng.uniform(8.5, 10.0) if not low else rng.uniform(7.0, 8.0)
        rise = rng.uniform(2.6, 3.6) if not low else 0.6
        droop = rng.uniform(3.4, 4.6) if not low else rng.uniform(5.5, 6.5)
        width = rng.uniform(1.9, 2.2) if not low else 1.6
        lp, ls = [], []
        steps = 10
        for i in range(steps + 1):
            t = i / steps
            dist = length * t
            y = rise * 4 * t * (1 - t) * 0.9 - droop * t ** 2.2
            lp.append(top + np.array([math.cos(yaw) * dist, y + 0.4, math.sin(yaw) * dist]))
            w = max(0.06, width * math.sin(math.pi * min(1, t * 1.15) ** 0.7) * (1 - 0.35 * t))
            w *= 1 - 0.3 * (i % 2) * (0.1 < t < 0.95)  # leaflet notches along the edge
            if i == 0:
                w = 0.3
            ls.append([(w, -w * 0.35), (0.0, 0.09), (-w, -w * 0.35), (0.0, -0.07)])
        leaves.append(sweep(lp, ls))
    leaf = merge(*leaves)
    leaf.smooth = False
    nuts = merge(*(solid(sphere(0.55, 6, 8), True).translate(top[0] + math.cos(a) * 0.8, top[1] - 0.5, top[2] + math.sin(a) * 0.8)
                   for a in (0.4, 2.4, 4.3)))
    crown = solid(sphere(0.9, 6, 8), True).translate(*top)
    # Centered on the trunk's foot, so placing the palm puts its trunk on the spot.
    return {"Trunk": anchors(merge(trunk), 14.0, 0.0), "Frond": leaf, "Nut": merge(nuts, crown)}


def sand_oasis():
    """An oasis pond (about 46 across): turquoise water in a damp sand bank, ringed with rocks, grass
    tufts and reeds, with lily pads and pink flowers."""
    rng = np.random.default_rng(21)
    seg = 64
    ph = rng.uniform(0, 6, 3)

    def radius(a):
        return 20.0 * (1 + 0.08 * np.sin(a * 3 + ph[0]) + 0.05 * np.sin(a * 5 + ph[1]))

    verts = [(0.0, 0.6, 0.0)]
    for i in range(seg):
        a = 2 * math.pi * i / seg
        r = radius(a)
        verts.append((math.cos(a) * r, 0.6, math.sin(a) * r))
    faces = [(0, 1 + (i + 1) % seg, 1 + i) for i in range(seg)]
    water = oriented(Mesh(verts, faces), upward)
    water.smooth = True
    # The bank: a low ring mound from under the water's edge out onto the desert.
    bank_v, bank_f = [], []
    ring = [(-0.4, 0.7), (0.0, 0.95), (2.5, 1.3), (6.0, 0.6), (9.0, -0.3)]
    for i in range(seg):
        a = 2 * math.pi * i / seg
        r = radius(a)
        for dr, y in ring:
            bank_v.append((math.cos(a) * (r + dr), y, math.sin(a) * (r + dr)))
    m = len(ring)
    for i in range(seg):
        for j in range(m - 1):
            a0 = i * m + j
            b0 = ((i + 1) % seg) * m + j
            bank_f += [(a0, a0 + 1, b0), (b0, a0 + 1, b0 + 1)]
    bank = oriented(Mesh(bank_v, bank_f), upward)
    bank.smooth = True
    rocks, grass, reeds, pads, flowers = [], [], [], [], []
    for i in range(16):
        a = 2 * math.pi * i / 16 + rng.uniform(-0.12, 0.12)
        r = radius(a) + rng.uniform(1.0, 4.0)
        s = rng.uniform(0.9, 2.2)
        rocks.append(solid(icosphere(s, 1, 0.35, int(rng.integers(0, 999)))).scale(1.0, 0.65, 1.0).translate(math.cos(a) * r, 1.0, math.sin(a) * r))
    for i in range(22):
        a = rng.uniform(0, 2 * math.pi)
        r = radius(a) + rng.uniform(1.5, 6.5)
        cx, cz = math.cos(a) * r, math.sin(a) * r
        for b in range(6):
            ang = rng.uniform(0, 2 * math.pi)
            lean = rng.uniform(0.6, 1.4)
            hgt = rng.uniform(1.6, 3.0)
            grass.append(taper([(cx, 0.8, cz), (cx + math.cos(ang) * lean * 0.5, 0.8 + hgt * 0.6, cz + math.sin(ang) * lean * 0.5),
                                (cx + math.cos(ang) * lean, 0.8 + hgt, cz + math.sin(ang) * lean)], 0.22, 0.03, 5))
    for i in range(9):
        a = rng.uniform(0, 2 * math.pi)
        r = radius(a) - rng.uniform(0.5, 2.0)
        cx, cz = math.cos(a) * r, math.sin(a) * r
        for b in range(4):
            ox, oz = rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6)
            hgt = rng.uniform(3.5, 5.5)
            reeds.append(taper([(cx + ox, 0.3, cz + oz), (cx + ox * 1.4, 0.3 + hgt, cz + oz * 1.4)], 0.13, 0.05, 5))
            reeds.append(solid(capsule(1.0, 0.24, 8), True).translate(cx + ox * 1.4, 0.3 + hgt - 0.6, cz + oz * 1.4))
    for i in range(10):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(5.0, 16.0)
        cx, cz = math.cos(a) * r, math.sin(a) * r
        rp = rng.uniform(1.0, 1.6)
        pad = solid(cylinder(rp, 0.14, 18)).translate(cx, 0.62, cz)
        pads.append(pad)
        if i % 2 == 0:
            flowers.append(flat_star(0.75, 0.3, 6, 0.25).rotate("x", 90).translate(cx + 0.3, 0.95, cz))
            flowers.append(solid(sphere(0.25, 5, 8), True).translate(cx + 0.3, 1.1, cz))
    grass_mesh = outward_parts(merge(*grass, *pads))
    grass_mesh.smooth = False
    reed_mesh = outward_parts(merge(*reeds))
    rock_mesh = merge(*rocks)
    return {"Water": water, "Bank": bank, "Rock": rock_mesh, "Grass": grass_mesh, "Reed": reed_mesh, "Lily": merge(*flowers)}


def sand_hoard():
    """A heap of treasure: a coin mound with spilled coins, an open chest brimming with gold and
    big gems. About 9 wide and 5 tall."""
    rng = np.random.default_rng(8)
    mound = organic_lathe([(0.0, 0.0), (4.6, 0.0), (4.0, 0.6), (2.8, 1.6), (1.4, 2.4), (0.0, 2.7)], 40, 0.08, 5, 3)
    mound = solid(mound, True)
    coins = []
    for i in range(36):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.2, 5.6)
        h = float(np.interp(r, [0, 1.4, 2.8, 4.0, 4.6, 6], [2.7, 2.4, 1.6, 0.6, 0.0, 0.0]))
        coin = solid(cylinder(0.46, 0.12, 10)).rotate("x", rng.uniform(-35, 35)).rotate("z", rng.uniform(-35, 35))
        coins.append(coin.translate(math.cos(a) * r, h + 0.02, math.sin(a) * r))
    gold = merge(mound, *coins)
    # Chest behind the mound, lid open.
    cx, cz = 1.4, 2.4
    wood = [box(3.6, 2.0, 2.4, x=cx, y=1.0, z=cz, bevel=0.12)]
    lid = box(3.7, 0.5, 2.5, bevel=0.15).translate(0, 0, 1.25).rotate("x", -70).translate(cx, 2.2, cz + 1.2)
    wood.append(lid)
    trim = [box(3.8, 0.3, 2.6, x=cx, y=0.4, z=cz, bevel=0.08), box(3.8, 0.3, 2.6, x=cx, y=1.9, z=cz, bevel=0.08),
            box(0.5, 0.7, 0.2, x=cx, y=1.5, z=cz - 1.25, bevel=0.06)]
    fill = solid(organic_lathe([(0.0, 1.8), (1.3, 1.8), (1.0, 2.4), (0.0, 2.7)], 20, 0.1, 4, 1), True).scale(1.25, 1.0, 0.85).translate(cx, 0, cz)
    gems = []
    for i, (gx, gz, s) in enumerate(((-1.6, -1.6, 0.7), (2.4, -1.0, 0.55), (-2.8, 1.0, 0.6), (0.2, 0.0, 0.8))):
        h = float(np.interp(math.hypot(gx, gz), [0, 1.4, 2.8, 4.0, 4.6], [2.7, 2.4, 1.6, 0.6, 0.0]))
        gems.append(solid(icosphere(s, 0)).scale(1, 1.3, 1).translate(gx, h + s * 0.6, gz))
    return {"Gold": merge(gold, fill, *trim), "Wood": merge(*wood), "Gem": merge(*gems)}


def sand_mosaic():
    """The courtyard paving round the funnel (lies flat, 0.4 thick, centered on the funnel's axis): a
    curb of carved stones on the rim, a gold inlay ring, a sun-ray mosaic of cream and terracotta
    stones (some sunk under the sand), turquoise inlays and four paved paths out to the gateways."""
    rng = np.random.default_rng(4)
    h = 0.4
    curb, tile, dark, inlay, accent = [], [], [], [], []
    count = 48
    gap = 0.012
    for i in range(count):
        a0 = 2 * math.pi * i / count + gap
        a1 = 2 * math.pi * (i + 1) / count - gap
        curb.append(arc_slab(34.5, 36.3, a0, a1, 0.0, h + 0.05, 3))
    inlay.append(arc_slab(36.55, 37.0, 0.0, math.pi, 0.0, h - 0.05, 48))
    inlay.append(arc_slab(36.55, 37.0, math.pi, 2 * math.pi, 0.0, h - 0.05, 48))
    rays = 32
    for i in range(rays):
        a0 = 2 * math.pi * i / rays + 0.01
        a1 = 2 * math.pi * (i + 1) / rays - 0.01
        for k, (r0, r1) in enumerate(((37.3, 41.0), (41.2, 45.0), (45.2, 49.0))):
            if rng.uniform() < 0.12 and k > 0:
                continue  # a stone lost under the sand
            sink = rng.uniform(0.0, 0.08)
            slab = arc_slab(r0, r1, a0, a1, 0.0, h - sink, 2)
            (dark if i % 2 == 0 else tile).append(slab)
    for i in range(rays):
        a = 2 * math.pi * (i + 0.5) / rays
        x, z = math.cos(a) * 50.2, math.sin(a) * 50.2
        accent.append(box(1.6, h - 0.04, 1.6, x=x, y=(h - 0.04) / 2, z=z, bevel=0.1).rotate("y", 0))
    inlay.append(arc_slab(51.4, 51.9, 0.0, math.pi, 0.0, h - 0.05, 48))
    inlay.append(arc_slab(51.4, 51.9, math.pi, 2 * math.pi, 0.0, h - 0.05, 48))
    # Paths to the four gateways (north, south, east and west).
    for q in range(4):
        a = q * math.pi / 2
        for k in range(7):
            r0 = 52.4 + k * 2.3
            for side in (-1, 0, 1):
                if rng.uniform() < 0.1:
                    continue
                w = 3.0
                stone = box(w - 0.15, h - rng.uniform(0, 0.06), 2.15, bevel=0.08)
                stone.translate(side * w, (h) / 2, 0).rotate("y", 90).translate(r0 + 1.1, 0, 0)
                stone.rotate("y", -math.degrees(a))
                (tile if (k + side) % 2 == 0 else dark).append(stone)
    pieces = {"Curb": merge(*curb), "Tile": merge(*tile), "TileDark": merge(*dark), "Inlay": merge(*inlay), "Accent": merge(*accent)}
    pieces["Curb"] = anchors(pieces["Curb"], 70.0, 0.0)
    return pieces

PROPS = {
    "SandPit": sand_pit,
    "SandSwirl": sand_swirl,
    "SandCoin": sand_coin,
    "SandGem": sand_gem,
    "CoinBag": coin_bag,
    "GoldenIdol": golden_idol,
    "SandThrone": sand_throne,
    "SandCrown": sand_crown,
    "Cactus": cactus,
    "SandRuin": sand_ruin,
    "SandColumn": sand_column,
    "SandColumnBroken": sand_column_broken,
    "SandArch": sand_arch,
    "SandTemple": sand_temple,
    "SandSphinx": sand_sphinx,
    "SandPyramid": sand_pyramid,
    "SandDune": sand_dune,
    "SandPalm": sand_palm,
    "SandOasis": sand_oasis,
    "SandHoard": sand_hoard,
    "SandMosaic": sand_mosaic,
}

COLORS = {
    "Sand": (238, 196, 122), "Lip": (196, 142, 84), "Throat": (70, 44, 34), "Cliff": (214, 122, 74), "Strata": (240, 184, 128),
    "Swirl1": (222, 170, 110), "Swirl2": (252, 226, 168), "Swirl3": (252, 226, 168), "Swirl4": (252, 226, 168),
    "Swirl5": (252, 226, 168), "Whirl": (176, 124, 80),
    "Coin": (255, 200, 40), "Emblem": (255, 236, 130), "Gem": (80, 200, 255), "Sack": (196, 140, 86),
    "Rope": (120, 80, 50), "Eyes": (60, 230, 160), "Stone": (222, 178, 120),
    "Cushion": (200, 60, 60), "Gems": (230, 50, 90), "Cactus": (86, 150, 80), "Flower": (255, 120, 170), "Base": (196, 150, 100),
    "Paint": (48, 178, 190), "Gold": (255, 196, 48), "Cloth": (206, 40, 60), "Glow": (120, 255, 230), "Steps": (236, 200, 146),
    "Dark": (60, 36, 40), "Body": (234, 188, 112), "Nemes": (255, 200, 60), "NemesBlue": (40, 90, 200), "Nose": (90, 50, 50),
    "Collar": (255, 200, 60), "Plinth": (214, 170, 110), "Dune": (236, 184, 110), "Trunk": (150, 100, 60), "Frond": (70, 170, 70),
    "Nut": (120, 80, 40), "Water": (40, 200, 220), "Bank": (190, 150, 96), "Rock": (190, 140, 100), "Grass": (110, 190, 80),
    "Reed": (120, 150, 60), "Lily": (255, 130, 190), "Wood": (140, 84, 44), "Curb": (232, 200, 150), "Tile": (246, 222, 176),
    "TileDark": (232, 184, 112), "Inlay": (255, 200, 60), "Accent": (48, 190, 200),
}
