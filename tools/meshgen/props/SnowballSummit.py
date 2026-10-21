"""Props for Snowball Summit: a snowy mountain-top platform above a sea of clouds.

    python3 tools/meshgen/generate_meshes.py --only SnowballSummitCloud,SnowballSummitPeak,SnowballSummitSnowball,SnowballSummitPine,SnowballSummitFlag,SnowballSummitSpire,SnowballSummitMountain

Units are studs, +Y is up, the base sits on y = 0 and -Z is the front:
  * SnowballSummitPeak: the summit everyone stands on, authored for a platform of radius 32 (the game
    scales it to the round's radius). Its top (y = PEAK_H) is a glassy ice band from r = 29.6 out to
    the rim (the snowfield inside it is a real part in the game, 0.05 lower); the ice rolls over the
    edge into a lip (out to r = 32.5) with icicles under it, then the snowy, rocky mountain narrows
    away beneath (always inside r = 32, so nothing pokes out where people fall past).
  * SnowballSummitSnowball: a lumpy packed snowball, 2 across (radius 1, lumps within 5%), with ice
    flecks so its roll reads.
  * SnowballSummitPine: a snowy pine, four drooping tiers each with a snow cap.
  * SnowballSummitFlag: a summit pennant on a pole, planted in a little snow mound.
  * SnowballSummitSpire: a rock pinnacle rising out of the clouds, flat snowy top at y = SPIRE_H
    (r < 6) for pines and flags.
  * SnowballSummitMountain: a jagged snowy mountain with a shoulder peak, for the horizon.
  * SnowballSummitCloud: a billowing cloud (puffs heaped on a flat base) for the sea of clouds.
"""

import math

import numpy as np

from generate_meshes import Mesh, cylinder, icosphere, lathe, merge, organic_lathe, tube

PEAK_R = 32.0
PEAK_H = 46.0
SPIRE_H = 60.0


def subset(mesh: Mesh, mask) -> Mesh:
    """The faces of `mesh` where mask is true, with unused vertices dropped."""
    faces = mesh.f[mask]
    used, inverse = np.unique(faces.reshape(-1), return_inverse=True)
    return Mesh(mesh.v[used], inverse.reshape(-1, 3), mesh.smooth)


def face_data(mesh: Mesh):
    tri = mesh.v[mesh.f]
    n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    n = n / (np.linalg.norm(n, axis=1, keepdims=True) + 1e-12)
    return tri.mean(axis=1), n


# ------------------------------------------------------------------ the summit

def peak():
    h = PEAK_H
    # The ice band and lip: an open sheet from under the lip, out and over it, then inward on top.
    ice = lathe([(32.0, h - 2.3), (32.42, h - 1.6), (32.5, h - 0.85), (32.32, h - 0.28), (31.9, h), (29.6, h)], 96)
    # Gentle waves along the lip's underside only (the top stays flat at h, the rim radius at most 32.5).
    under = ice.v[:, 1] < h - 0.2
    angle = np.arctan2(ice.v[:, 2], ice.v[:, 0])
    ice.v[under, 1] -= 0.25 * (1 + np.sin(angle[under] * 17)) * (h - 0.2 - ice.v[under, 1]) / 2.1

    # Icicles under the lip, evenly round so the prop stays centred.
    rng = np.random.default_rng(21)
    icicles = []
    count = 84
    for k in range(count):
        a = (k + rng.uniform(-0.3, 0.3)) / count * math.tau
        length = rng.uniform(1.2, 4.6) if k % 3 else rng.uniform(4.0, 6.5)
        radius = 0.28 + length * 0.05
        r = 32.05 - radius * 0.5
        top = h - 1.9
        cone = lathe([(0.0, top - length), (radius * 0.35, top - length * 0.55), (radius, top - 0.05), (radius, top + 0.4)],
                     6, cap_top=True)
        cone.smooth = False
        cone.translate(math.cos(a) * r, 0, math.sin(a) * r)
        icicles.append(cone)

    # The mountain beneath: snowy shoulders, then faceted rock narrowing into the clouds.
    outline = [(5.0, 0.0), (9.0, 4.0), (13.0, 9.0), (17.0, 15.0), (21.0, 22.0), (24.5, 28.5), (27.5, 34.0),
               (29.8, 38.5), (31.2, 41.5), (31.7, h - 2.2)]
    dense = []
    for (r0, y0), (r1, y1) in zip(outline, outline[1:]):
        for k in range(3):
            t = k / 3
            dense.append((r0 + (r1 - r0) * t, y0 + (y1 - y0) * t))
    dense += [outline[-1], (30.6, h - 1.9), (0.0, h - 1.9)]
    body = organic_lathe(dense, 72, 0.035, 7, seed=6)
    # Craggy facets: every ring point in or out a little (not the rim rows, which meet the lip).
    jitter = np.random.default_rng(8).uniform(-0.9, 0.5, len(body.v)) * (body.v[:, 1] < h - 3)
    rr = np.hypot(body.v[:, 0], body.v[:, 2])
    body.v[:, 0] *= 1 + jitter / np.maximum(rr, 1)
    body.v[:, 2] *= 1 + jitter / np.maximum(rr, 1)
    body.v[:, 1] = np.minimum(body.v[:, 1], h - 1.9)
    # Rock strata: the radius steps in and out a little with height.
    steps = 1 - 0.035 * np.abs(np.sin(body.v[:, 1] * 0.55)) * (body.v[:, 1] < 40)
    body.v[:, 0] *= steps
    body.v[:, 2] *= steps
    # Keep every point inside r = 31.8 (people fall past r = 32).
    rr = np.hypot(body.v[:, 0], body.v[:, 2])
    squeeze = np.minimum(1.0, 31.8 / np.maximum(rr, 1e-6))
    body.v[:, 0] *= squeeze
    body.v[:, 2] *= squeeze
    body.smooth = False
    center, normal = face_data(body)
    a = np.arctan2(center[:, 2], center[:, 0])
    line = 37.0 + 3.0 * np.sin(a * 5 + 0.4) + 2.0 * np.sin(a * 11)
    snow = (center[:, 1] > line) | ((center[:, 1] > line - 12) & (normal[:, 1] > 0.55))
    return {
        "Ice": ice,
        "Icicles": merge(*icicles),
        "Snow": subset(body, snow),
        "Rock": subset(body, ~snow),
    }


# ------------------------------------------------------------------ the snowball

def snowball():
    # Soft lumps (within 5% of radius 1, so what's drawn is what hits) and darker ice flecks that
    # show it rolling.
    ball = icosphere(1.0, 3, noise=0.05, seed=3)
    rng = np.random.default_rng(9)
    flecks = []
    for k in range(9):
        d = rng.normal(size=3)
        d /= np.linalg.norm(d)
        fleck = icosphere(rng.uniform(0.11, 0.16), 0, seed=k)
        fleck.smooth = False
        flecks.append(fleck.translate(*(d * 0.93)))
    ice = merge(*flecks)
    for mesh in (ball, ice):
        mesh.v[:, 1] = np.clip(mesh.v[:, 1], -1.0, 1.0)  # exactly 2 tall
        mesh.translate(0, 1.0, 0)
    return {"Snow": ball, "Ice": ice}


# ------------------------------------------------------------------ pine and flag

def pine():
    trunk = organic_lathe([(0.0, 0.0), (0.75, 0.0), (0.6, 1.5), (0.45, 4.0), (0.0, 4.4)], 10, 0.12, 5, seed=4)
    needles, snow = [], []
    for k in range(4):
        y0 = 2.2 + k * 3.05
        r0 = 4.9 - k * 1.05
        needles.append(organic_lathe(
            [(0.0, y0 + 0.3), (r0 * 0.6, y0 + 0.05), (r0, y0 - 0.25), (r0 * 0.94, y0 + 0.4),
             (r0 * 0.5, y0 + 2.2), (r0 * 0.18, y0 + 3.7), (0.0, y0 + 4.05)],
            14, 0.14, 7, seed=20 + k))
        snow.append(organic_lathe(
            [(r0 * 0.58, y0 + 1.42), (r0 * 0.72, y0 + 1.46), (r0 * 0.67, y0 + 1.76), (r0 * 0.4, y0 + 2.86),
             (r0 * 0.16, y0 + 3.99), (0.0, y0 + 4.27)],
            14, 0.14, 7, seed=20 + k))
    return {"Trunk": trunk, "Needles": merge(*needles), "Snow": merge(*snow)}


def flag():
    mound = organic_lathe([(0.0, 0.0), (1.6, 0.0), (1.3, 0.45), (0.6, 0.85), (0.0, 0.95)], 16, 0.1, 4, seed=2)
    pole = cylinder(0.12, 9.6, 12).translate(0, 0.4, 0)
    knob = icosphere(0.26, 2).translate(0, 10.15, 0)
    # The pennant: a long triangle out to +X, rippling in Z, with a little thickness (a closed slab).
    rows, cols = 10, 6
    verts, faces = [], []
    length, height, thick = 4.6, 2.6, 0.06
    for side in (-1, 1):
        for i in range(rows + 1):
            u = i / rows
            for j in range(cols + 1):
                v = j / cols
                half = height / 2 * (1 - u * 0.95)
                x = 0.1 + u * length
                y = 9.0 + (v * 2 - 1) * half
                z = 0.32 * math.sin(u * 5.5 - 0.6) * u + side * thick / 2
                verts.append((x, y, z))
    n = (rows + 1) * (cols + 1)
    for i in range(rows):
        for j in range(cols):
            a = i * (cols + 1) + j
            b, c, d = a + 1, a + cols + 1, a + cols + 2
            faces += [(a, c, b), (b, c, d)]
            faces += [(n + a, n + b, n + c), (n + b, n + d, n + c)]
    for i in range(rows):  # bottom and top edges
        for j in (0, cols):
            a = i * (cols + 1) + j
            c = a + cols + 1
            faces += [(a, n + a, c), (c, n + a, n + c)]
    for j in range(cols):  # the edge along the pole and the tip
        for i in (0, rows):
            a = i * (cols + 1) + j
            b = a + 1
            faces += [(a, b, n + a), (b, n + b, n + a)]
    cloth = Mesh(verts, faces)
    cloth.smooth = False
    stripe = tube([(0.12, 9.0, 0.0), (0.12, 10.15, 0.0)], 0.15, 8)
    return {"Mound": mound, "Pole": merge(pole, stripe), "Knob": knob, "Cloth": cloth}


# ------------------------------------------------------------------ spire and mountain

def spire():
    h = SPIRE_H
    body = organic_lathe(
        [(12.0, 0.0), (11.0, 12.0), (9.5, 26.0), (8.8, 38.0), (8.2, 48.0), (7.9, 54.0), (7.7, h - 2.6), (0.0, h - 2.6)],
        22, 0.12, 5, seed=11)
    body.smooth = False
    cap = lathe([(7.5, h - 3.2), (8.15, h - 2.4), (8.0, h - 1.2), (7.0, h - 0.3), (6.0, h), (0.0, h)], 28)
    under = cap.v[:, 1] < h - 2.0
    angle = np.arctan2(cap.v[:, 2], cap.v[:, 0])
    cap.v[under, 1] -= 0.8 * (1 + np.sin(angle[under] * 7))
    return {"Rock": body, "Snow": cap}


def mountain():
    rng = np.random.default_rng(17)
    main = organic_lathe([(70.0, 0.0), (62.0, 18.0), (50.0, 42.0), (36.0, 70.0), (24.0, 98.0), (13.0, 124.0),
                          (5.0, 144.0), (0.0, 152.0)], 44, 0.16, 5, seed=5)
    shoulder = organic_lathe([(40.0, 0.0), (33.0, 24.0), (23.0, 52.0), (12.0, 80.0), (4.0, 96.0), (0.0, 102.0)],
                             32, 0.18, 4, seed=8)
    parts = []
    for mesh, offset in ((main, (0, 0)), (shoulder, (46, 18))):
        angle = np.arctan2(mesh.v[:, 2], mesh.v[:, 0])
        ridges = np.zeros(len(mesh.v))
        for _ in range(4):
            ridges += np.maximum(0, np.cos(angle - rng.uniform(0, math.tau))) ** 6 * rng.uniform(0.08, 0.16)
        mesh.v[:, 0] *= 1 + ridges * 0.6
        mesh.v[:, 2] *= 1 + ridges * 0.6
        mesh.translate(offset[0], 0, offset[1])
        mesh.smooth = False
        parts.append(mesh)
    whole = merge(*parts)
    center, normal = face_data(whole)
    line = 88 + 8 * np.sin(np.arctan2(center[:, 2], center[:, 0]) * 3 + 0.7)
    line = np.where(np.hypot(center[:, 0] - 46, center[:, 2] - 18) < 42, line - 30, line)
    snow = (center[:, 1] > line) | ((center[:, 1] > line - 18) & (normal[:, 1] > 0.7))
    return {"Rock": subset(whole, ~snow), "Snow": subset(whole, snow)}


def cloud():
    # A billowing cloud: a flat base puff with smaller puffs heaped on it (flat underneath).
    puffs = []
    for k, (x, y, z, r) in enumerate([(0, 0, 0, 10.0), (8, 1.5, 2, 7.5), (-8, 1.0, -1, 7.0), (2, 3.5, -4, 6.5),
                                      (-3, 4.0, 4, 6.0), (13, 0, -3, 5.0), (-13, -0.5, 3, 5.0)]):
        puff = icosphere(r, 2, noise=0.08, seed=30 + k)
        puff.v[:, 1] *= 0.62
        puffs.append(puff.translate(x, y, z))
    mesh = merge(*puffs)
    mesh.v[:, 1] = np.maximum(mesh.v[:, 1], -2.0)
    mesh.translate(0, 2.0, 0)
    return {"Cloud": mesh}


PROPS = {
    "SnowballSummitCloud": cloud,
    "SnowballSummitPeak": peak,
    "SnowballSummitSnowball": snowball,
    "SnowballSummitPine": pine,
    "SnowballSummitFlag": flag,
    "SnowballSummitSpire": spire,
    "SnowballSummitMountain": mountain,
}
COLORS = {
    "Cloud": (250, 252, 255),
    "Snow": (244, 249, 255),
    "Ice": (160, 214, 246),
    "Icicles": (196, 234, 255),
    "Rock": (98, 108, 134),
    "Trunk": (112, 76, 52),
    "Needles": (36, 96, 82),
    "Mound": (244, 249, 255),
    "Pole": (200, 206, 220),
    "Knob": (255, 200, 60),
    "Cloth": (232, 60, 80),
}


if __name__ == "__main__":
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    for name, build in PROPS.items():
        pieces = build()
        allv = np.vstack([m.v for m in pieces.values()])
        print(name, "bounds", allv.min(axis=0).round(3), allv.max(axis=0).round(3))
