"""Props for Spleef: a frozen crater with three floors of snow blocks over an icy pool.

    python3 tools/meshgen/generate_meshes.py --only SpleefBlock,SpleefCliff,SpleefPine,SpleefCrystal,SpleefFloe,SpleefPeak

Units are studs, +Y is up, the base sits on y = 0 and -Z is the front:
  * SpleefBlock: one snow block of a floor, exactly 4 x 3 x 4 so the floor is seamless: two courses of
    packed snow bricks (offset joints) under a pillowy cap. One piece ("Snow"): one part per block.
  * SpleefCliff: a 60 degree arc of the crater rim swept around the crater's middle (the origin),
    centered on -Z: faceted ice cliff rising out of the water (mesh y = 6 is the waterline), a snowy
    crest, the outer slope down to the snowfield. The ends match the next arc exactly. Its pivot (the
    bounding box's bottom center) is printed by `python3 tools/meshgen/props/Spleef.py`; see CLIFF_*
    in src/server/MiniGames/Spleef.luau.
  * SpleefPine: a snowy pine, four drooping tiers each with a snow cap.
  * SpleefCrystal: a cluster of hexagonal ice crystals on an icy mound.
  * SpleefFloe: a jagged ice floe with a snow crust.
  * SpleefPeak: a faceted snowy mountain for the horizon.
"""

import math

import numpy as np

from generate_meshes import Mesh, extrude, icosphere, lathe, merge, organic_lathe, rounded_box

CLIFF_ARC = math.radians(60)


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


# ------------------------------------------------------------------ the block

def block():
    # Two courses of bricks with offset joints, under a pillowy cap: exactly 4 x 3 x 4 overall.
    parts = []
    for x in (-1.0, 1.0):  # lower course: joint along Z
        parts.append(rounded_box(1.97, 1.4, 3.94, 0.16, 2).translate(x, 0.7, 0))
    for z in (-1.0, 1.0):  # upper course: joint along X
        parts.append(rounded_box(3.94, 1.2, 1.97, 0.16, 2).translate(0, 2.0, z))
    cap = rounded_box(4.0, 0.5, 4.0, 0.22, 4).translate(0, 2.75, 0)
    # Soft dents in the cap's top, so the snow isn't a flat slab (the top stays at y = 3).
    top = cap.v[:, 1] > 2.95
    x, z = cap.v[top, 0], cap.v[top, 2]
    dent = 0.035 * (1 + np.sin(x * 2.3 + 0.4) * np.cos(z * 1.9 - 0.3))
    cap.v[top, 1] -= dent
    parts.append(cap)
    return {"Snow": merge(*parts)}


# ------------------------------------------------------------------ the crater rim

# The rim's cross-section (distance from the crater's middle, height); y = 6 is the waterline, so the
# cliff comes out of the water 63 out, and the outer slope meets the snowfield (y = 5.4) ~127 out.
RIM_PROFILE = [
    (61.5, 0.0), (62.6, 4.0), (63.4, 8.0), (64.2, 12.5), (64.8, 17.0), (65.6, 21.0), (67.0, 24.5),
    (69.5, 27.0), (73.0, 28.4), (78.0, 29.0), (85.0, 28.8), (92.0, 27.6), (100.0, 24.6), (108.0, 19.6),
    (116.0, 13.0), (123.0, 7.4), (128.0, 3.6), (132.0, 0.0),
]


def cliff():
    rows = 44
    profile = RIM_PROFILE
    count = len(profile)
    verts = []
    for k in range(rows + 1):
        t = k / rows
        a = (t - 0.5) * CLIFF_ARC  # -30 .. 30 degrees around -Z
        window = math.sin(math.pi * t) ** 0.6  # no wobble at the ends: they match the next arc
        for m, (r, y) in enumerate(profile):
            face = 1.0 if r < 70 else 0.35  # the cliff face is craggier than the slope
            wobble = (
                1.1 * math.sin(a * 23 + y * 0.31)
                + 0.7 * math.sin(a * 47 - y * 0.55 + 1.3)
                + 0.45 * math.sin(a * 83 + y * 1.05 + 2.1)
            )
            rr = r + wobble * face * window * (0.4 if m == 0 or m == count - 1 else 1.0)
            yy = y + (0.5 * math.sin(a * 31 + r * 0.2) * window if 0 < m < count - 1 and r > 66 else 0.0)
            verts.append((math.sin(a) * rr, yy, -math.cos(a) * rr))
    faces = []
    for k in range(rows):
        for m in range(count - 1):
            p = k * count + m
            q = p + count
            # Outward: profile runs inner foot -> crest -> outer foot, angle runs +X-ward.
            faces += [(p, p + 1, q), (p + 1, q + 1, q)]
    mesh = Mesh(verts, faces, smooth=False)
    # Make sure the faces point away from the rim's core (up/out of the solid).
    center, normal = face_data(mesh)
    core_r = 96.0
    radial = np.stack([center[:, 0], np.zeros(len(center)), center[:, 2]], 1)
    radial /= np.linalg.norm(radial, axis=1, keepdims=True)
    r_now = np.hypot(center[:, 0], center[:, 2])
    out = radial * np.sign(r_now - core_r)[:, None] + np.array([0, 1.0, 0]) * 0.8
    flip = np.einsum("ij,ij->i", normal, out) < 0
    mesh.f[flip] = mesh.f[flip][:, ::-1]
    center, normal = face_data(mesh)
    r_now = np.hypot(center[:, 0], center[:, 2])
    snow = (center[:, 1] > 25.5) | ((r_now > 76) & (normal[:, 1] > 0.45) & (center[:, 1] > 9))
    rock = (center[:, 1] < 8.5) & (r_now < 70)
    ice = ~snow & ~rock
    return {"Ice": subset(mesh, ice), "Snow": subset(mesh, snow), "Rock": subset(mesh, rock)}


# ------------------------------------------------------------------ pine, crystal, floe, peak

def pine():
    trunk = organic_lathe([(0.0, 0.0), (0.75, 0.0), (0.6, 1.5), (0.45, 4.0), (0.0, 4.4)], 10, 0.12, 5, seed=3)
    needles, snow = [], []
    for k in range(4):
        y0 = 2.2 + k * 3.05
        r0 = 4.9 - k * 1.05
        needles.append(organic_lathe(
            [(0.0, y0 + 0.3), (r0 * 0.6, y0 + 0.05), (r0, y0 - 0.25), (r0 * 0.94, y0 + 0.4),
             (r0 * 0.5, y0 + 2.2), (r0 * 0.18, y0 + 3.7), (0.0, y0 + 4.05)],
            14, 0.13, 7, seed=10 + k))
        snow.append(organic_lathe(
            [(r0 * 0.58, y0 + 1.42), (r0 * 0.71, y0 + 1.46), (r0 * 0.67, y0 + 1.74), (r0 * 0.4, y0 + 2.84),
             (r0 * 0.16, y0 + 3.98), (0.0, y0 + 4.26)],
            14, 0.13, 7, seed=10 + k))
    return {"Trunk": trunk, "Needles": merge(*needles), "Snow": merge(*snow)}


def crystal():
    rng = np.random.default_rng(5)
    shards = []
    for index, (height, radius, tilt, turn, x, z) in enumerate([
        (6.3, 0.72, 0, 0, 0.0, 0.0), (4.4, 0.55, 24, 40, 1.2, 0.5), (3.6, 0.5, -28, 160, -1.1, 0.4),
        (3.0, 0.42, 30, 260, -0.3, -1.2), (2.4, 0.36, -20, 320, 1.0, -0.9),
    ]):
        shard = lathe([(0.0, 0.0), (radius, 0.1), (radius * 1.05, height * 0.72), (radius * 0.55, height * 0.86), (0.0, height)], 6)
        shard.smooth = False
        shard.rotate("y", rng.uniform(0, 60)).rotate("z", tilt).rotate("y", turn).translate(x, 0.5, z)
        shards.append(shard)
    base = icosphere(1.0, 1, noise=0.25, seed=2).scale(2.6, 0.75, 2.4).translate(0, 0.3, 0)
    base.smooth = False
    base.v[:, 1] = np.maximum(base.v[:, 1], 0.0)
    return {"Crystal": merge(*shards), "Base": base}


def floe():
    rng = np.random.default_rng(8)
    points = []
    for index in range(11):
        a = index / 11 * math.tau
        r = rng.uniform(3.2, 4.6)
        points.append((math.cos(a) * r * 1.15, math.sin(a) * r * 0.85))
    ice = extrude(points, 0.9).rotate("x", -90).translate(0, 0.45, 0)
    crust = extrude([(x * 0.8 + 0.2, y * 0.78 - 0.1) for x, y in points], 0.55).rotate("x", -90).translate(0, 1.1, 0)
    return {"Ice": ice, "Snow": crust}


def peak():
    rng = np.random.default_rng(13)
    profile = [(62.0, 0.0), (55.0, 12.0), (44.0, 28.0), (32.0, 46.0), (21.0, 62.0), (11.0, 77.0), (4.0, 86.0), (0.0, 90.0)]
    mesh = organic_lathe(profile, 22, 0.16, 5, seed=4)
    # Ridges: the slope bulges along a few random directions.
    angle = np.arctan2(mesh.v[:, 2], mesh.v[:, 0])
    ridges = np.zeros(len(mesh.v))
    for _ in range(4):
        ridges += np.maximum(0, np.cos(angle - rng.uniform(0, math.tau))) ** 6 * rng.uniform(0.08, 0.16)
    scale = 1 + ridges * (1 - mesh.v[:, 1] / 95)
    mesh.v[:, 0] *= scale
    mesh.v[:, 2] *= scale
    mesh.smooth = False
    center, normal = face_data(mesh)
    line = 54 + 6 * np.sin(np.arctan2(center[:, 2], center[:, 0]) * 3 + 0.7)
    snow = (center[:, 1] > line) | ((center[:, 1] > line - 14) & (normal[:, 1] > 0.75))
    return {"Rock": subset(mesh, ~snow), "Snow": subset(mesh, snow)}


PROPS = {
    "SpleefBlock": block,
    "SpleefCliff": cliff,
    "SpleefPine": pine,
    "SpleefCrystal": crystal,
    "SpleefFloe": floe,
    "SpleefPeak": peak,
}
COLORS = {
    "Snow": (244, 249, 255),
    "Ice": (150, 206, 242),
    "Rock": (104, 118, 146),
    "Trunk": (112, 76, 52),
    "Needles": (38, 98, 80),
    "Crystal": (170, 226, 255),
    "Base": (150, 206, 242),
}


if __name__ == "__main__":
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    pieces = cliff()
    allv = np.vstack([m.v for m in pieces.values()])
    lo, hi = allv.min(axis=0), allv.max(axis=0)
    print(f"SpleefCliff bounds {lo.round(2)} .. {hi.round(2)}; pivot (bottom center) "
          f"{((lo[0] + hi[0]) / 2):.2f}, {lo[1]:.2f}, {((lo[2] + hi[2]) / 2):.2f}; height {hi[1] - lo[1]:.2f}")
