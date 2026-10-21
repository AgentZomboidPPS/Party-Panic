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
    """A Sand King's sandstone throne on a stepped dais: a tall back crowned with a sun disc,
    sphinx-paw armrests and a cushion (colored per team in-game). Faces -Z."""
    dais = merge(rounded_box(7.0, 0.8, 7.0, 0.2, 4).translate(0, 0.4, 0),
                 rounded_box(5.6, 0.8, 5.6, 0.2, 4).translate(0, 1.2, 0.3))
    seat = rounded_box(3.6, 1.4, 3.0, 0.25, 4).translate(0, 2.3, 0.6)
    back = rounded_box(3.8, 5.6, 0.9, 0.3, 4).translate(0, 4.6, 2.2)
    crest = cylinder(1.9, 0.9, 32, 0.2).rotate("x", 90).translate(0, 7.4, 2.65)
    arms = []
    paws = []
    for side in (-1, 1):
        arms.append(rounded_box(0.9, 1.3, 3.4, 0.3, 4).translate(side * 2.2, 3.15, 0.55))
        paws.append(sphere(0.62, 10, 16).scale(1.0, 0.8, 1.2).translate(side * 2.2, 3.55, -1.15))
        arms.append(cylinder(0.32, 2.4, 12, 0.08).translate(side * 1.75, 6.5, 2.2))
    stone = merge(dais, seat, back, crest, *arms, *paws)
    stone.smooth = False
    sun = cylinder(1.35, 0.25, 32, 0.08).rotate("x", 90).translate(0, 7.4, 2.08)
    rays = []
    for i in range(12):
        a = 360.0 * i / 12
        rays.append(rounded_box(0.22, 0.75, 0.2, 0.06, 2).translate(0, 1.95, 0).rotate("z", a).translate(0, 7.4, 2.12))
    bands = merge(*[rounded_box(0.98, 0.18, 3.5, 0.06, 2).translate(side * 2.2, 3.85, 0.55) for side in (-1, 1)],
                  rounded_box(7.08, 0.14, 7.08, 0.05, 2).translate(0, 0.8, 0))
    gold = merge(sun, *rays, bands)
    cushion = rounded_box(3.2, 0.5, 2.6, 0.24, 6).translate(0, 3.2, 0.5)
    back_pad = rounded_box(2.8, 3.2, 0.4, 0.18, 6).translate(0, 4.9, 1.6)
    return {"Stone": stone, "Gold": gold, "Cushion": merge(cushion, back_pad)}


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
}

COLORS = {
    "Sand": (238, 196, 122), "Lip": (196, 142, 84), "Throat": (70, 44, 34), "Cliff": (214, 122, 74), "Strata": (240, 184, 128),
    "Swirl1": (222, 170, 110), "Swirl2": (252, 226, 168), "Swirl3": (252, 226, 168), "Swirl4": (252, 226, 168),
    "Swirl5": (252, 226, 168), "Whirl": (176, 124, 80),
    "Coin": (255, 200, 40), "Emblem": (255, 236, 130), "Gem": (80, 200, 255), "Sack": (196, 140, 86),
    "Rope": (120, 80, 50), "Eyes": (60, 230, 160), "Stone": (222, 178, 120),
    "Cushion": (200, 60, 60), "Gems": (230, 50, 90), "Cactus": (86, 150, 80), "Flower": (255, 120, 170), "Base": (196, 150, 100),
}
