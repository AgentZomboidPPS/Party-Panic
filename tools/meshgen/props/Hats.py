"""Hats players wear (the Hat cosmetic slot: src/server/World/Hats.luau puts them on as an Accessory).

The PUMPKIN HAT, the HALLOWEEN PARTY's headline reward (owner: "do pumpkin hat now"): a carved
jack-o'-lantern worn on top of the head. A smooth ribbed orange shell; triangle eyes, a nose and a
toothy grin carved into its front, with a warm glow inside that shows through them; a green stem
that curls into a spiral, and a leaf.

Sculpted as signed distance fields (the carving is a subtraction, so the cuts are clean) and meshed
with marching cubes, then simplified (quadric edge collapse, pip `pyfqmr`) to a size phones draw
easily on every head in the lobby. The shell is solid with pockets cut into it; the glow is a cap
inside its front whose surface sits just under the shell's skin, so each pocket shows a carved
orange wall and then light. The shell's normals are split along the carved rims (split_sharp), so the
rims stay crisp and the skin round them smooth.

Units are studs at the size it's worn on a standard 1.2-stud head (World/Hats scales it to each
head); +Y is up, the base sits on y = 0 and -Z is the front (the face). Pieces: HatShell (orange),
HatGlow (the light inside: Neon) and HatStem (green); src/server/World/Props/Hats.luau colours them.
"""

import math

import numpy as np
from generate_meshes import Mesh, sd_capsule, sdf_mesh, smin, weld

# The pumpkin: 1.58 studs wide (1.3 x a 1.2-stud head), a little flatter underneath than on top.
R = 0.79  # radius
HH = 0.555  # half height of the top half
HB = 0.5  # half height of the bottom half
CY = HB  # the middle's height (the bottom sits on y = 0)
TOP = CY + HH
LOBES = 8
WALL = 0.075  # the carved wall's depth before the glow
FLOOR = WALL + 0.05  # how deep the pockets go (their floors hide inside the glow)
FRONT_CUT = -0.3  # the carving and the glow stay in front of this z

# How many triangles each piece keeps.
SHELL_TRIS = 5500
GLOW_TRIS = 420
STEM_TRIS = 1500


def smax(a, b, k):
    return -smin(-a, -b, k)


def sdf_surface(sdf, lo, hi, step, smoothing=0) -> Mesh:
    """Marching cubes over a signed distance field, like generate_meshes.sdf_mesh, with the Taubin
    passes optional: next to sharp carved rims they ripple the skin around them, and a fine grid over
    a smooth field needs none."""
    if smoothing:
        return sdf_mesh(sdf, lo, hi, step)
    from skimage.measure import marching_cubes

    lo, hi = np.array(lo, float), np.array(hi, float)
    axes = [np.arange(lo[i], hi[i] + step, step) for i in range(3)]
    grid = np.stack(np.meshgrid(*axes, indexing="ij"), -1)
    field = sdf(grid.reshape(-1, 3)).reshape(grid.shape[:3])
    verts, faces, _, _ = marching_cubes(field, 0.0, spacing=(step, step, step))
    return Mesh(verts + lo, faces)


def simplify(mesh: Mesh, target: int) -> Mesh:
    """Quadric edge collapse down to about `target` triangles: flat and gently curved areas lose the
    most, the carved edges and the ribs keep theirs."""
    try:
        import pyfqmr
    except ImportError as error:
        raise SystemExit("The hats need pyfqmr to simplify their sculpted meshes: pip install pyfqmr") from error
    simplifier = pyfqmr.Simplify()
    simplifier.setMesh(mesh.v.astype(np.float64), mesh.f.astype(np.int32))
    simplifier.simplify_mesh(target_count=target, aggressiveness=3, preserve_border=True, verbose=False)
    vertices, faces, _ = simplifier.getMesh()
    return weld(Mesh(vertices, faces))


def split_sharp(mesh: Mesh, degrees: float) -> Mesh:
    """Gives the corners either side of a sharp edge (a carved rim) vertices of their own, so smooth
    shading stops at the edge instead of smearing the rim's light over the skin around it. Corners
    of one vertex stay joined across every gentler edge (the ribs stay smooth)."""
    v, f = mesh.v, mesh.f
    normal = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    normal /= np.linalg.norm(normal, axis=1, keepdims=True) + 1e-12
    limit = math.cos(math.radians(degrees))
    parent = list(range(3 * len(f)))  # corner 3 * face + slot

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    users: dict[tuple[int, int], list[tuple[int, int, int]]] = {}
    for face, (a, b, c) in enumerate(f.tolist()):
        for slot, (p, q) in enumerate(((a, b), (b, c), (c, a))):
            users.setdefault((min(p, q), max(p, q)), []).append((face, slot, p))
    for (low, high), shared in users.items():
        if len(shared) != 2 or float(normal[shared[0][0]] @ normal[shared[1][0]]) < limit:
            continue
        (f1, s1, p1), (f2, s2, p2) = shared
        for vertex in (low, high):
            # The corner of this vertex in each face: the edge's start, or the slot after it.
            c1 = 3 * f1 + (s1 if p1 == vertex else (s1 + 1) % 3)
            c2 = 3 * f2 + (s2 if p2 == vertex else (s2 + 1) % 3)
            parent[root(c1)] = root(c2)
    groups = np.array([root(i) for i in range(3 * len(f))])
    unique, index = np.unique(groups, return_inverse=True)
    return Mesh(v[f.reshape(-1)[unique]], index.reshape(-1, 3))


def polygon_sdf(points, x, y):
    """Signed distance from (x, y) to a closed polygon (negative inside)."""
    pts = np.asarray(points, dtype=float)
    distance = np.full(x.shape, np.inf)
    inside = np.zeros(x.shape, dtype=bool)
    for (ax, ay), (bx, by) in zip(pts, np.roll(pts, -1, axis=0)):
        ex, ey = bx - ax, by - ay
        if ex * ex + ey * ey < 1e-14:
            continue  # (a corner listed twice, like the grin's two ends)
        wx, wy = x - ax, y - ay
        t = np.clip((wx * ex + wy * ey) / (ex * ex + ey * ey), 0.0, 1.0)
        distance = np.minimum(distance, np.hypot(wx - ex * t, wy - ey * t))
        crosses = (ay > y) != (by > y)
        at = ax + (y - ay) * ex / np.where(ey == 0, 1e-12, ey)
        inside ^= crosses & (x < at)
    return np.where(inside, -distance, distance)


def box_sdf(cx, cy, hw, hh, x, y):
    dx, dy = np.abs(x - cx) - hw, np.abs(y - cy) - hh
    return np.hypot(np.maximum(dx, 0), np.maximum(dy, 0)) + np.minimum(np.maximum(dx, dy), 0)


# ---------------------------------------------------------------- the pumpkin


def pumpkin_sdf(p):
    """The uncarved pumpkin: an oblate, ribbed ball with a dimple on top for the stem."""
    x, y, z = p[:, 0], p[:, 1] - CY, p[:, 2]
    theta = np.arctan2(z, x)
    # Taller on top than underneath, blended across the middle so no crease runs round it.
    blend = np.clip(0.5 + y / 0.5, 0, 1)
    hh = HB + (HH - HB) * blend * blend * (3 - 2 * blend)
    h = np.clip(y / hh, -1.0, 1.0)
    band = np.sqrt(np.clip(1 - h * h, 0, 1))  # the grooves fade out at the top and bottom
    groove = ((1 - np.cos(LOBES * theta)) / 2) ** 1.6  # 0 in a lobe's middle, 1 in a groove
    # The face is carved on the lobe at the front (-Z), so the grooves either side of it are softer.
    from_front = np.angle(np.exp(1j * (theta + math.pi / 2)))
    depth = 0.095 * (1 - 0.75 * np.exp(-((from_front / 0.6) ** 4)))
    radius = R * (1 - depth * groove * band)
    qx, qy, qz = x / radius, y / hh, z / radius
    k0 = np.sqrt(qx * qx + qy * qy + qz * qz)
    k1 = np.sqrt((qx / radius) ** 2 + (qy / hh) ** 2 + (qz / radius) ** 2)
    d = k0 * (k0 - 1) / np.maximum(k1, 1e-9)
    dimple = np.linalg.norm(p - np.array([0.0, TOP + 0.05, 0.0]), axis=1) - 0.16
    d = smax(d, -dimple, 0.07)
    underneath = np.linalg.norm(p - np.array([0.0, -0.07, 0.0]), axis=1) - 0.15
    return smax(d, -underneath, 0.06)


def face_sdf(x, y):
    """The carved face, seen from the front (u across, v up from the pumpkin's middle): negative inside
    a cut. Triangle eyes, a triangle nose, and a wide grin with two teeth on top and one below."""
    u, v = x, y - CY
    eye = min_of(
        polygon_sdf([(-0.37, 0.07), (-0.105, 0.07), (-0.25, 0.305)], u, v),
        polygon_sdf([(0.105, 0.07), (0.37, 0.07), (0.25, 0.305)], u, v),
    )
    nose = polygon_sdf([(-0.062, -0.04), (0.062, -0.04), (0.0, 0.07)], u, v)
    half = 0.43

    def upper(t):
        return -0.12 - 0.06 * (1 - (t / half) ** 2)

    def lower(t):
        return -0.12 - 0.215 * np.clip(1 - (t / half) ** 2, 0, 1) ** 0.8

    edge = np.linspace(-half, half, 41)
    outline = [(t, upper(t)) for t in edge] + [(t, lower(t)) for t in edge[::-1]]
    mouth = polygon_sdf(outline, u, v)
    teeth = min_of(
        box_sdf(-0.15, upper(-0.15) - 0.01, 0.042, 0.075, u, v),
        box_sdf(0.155, upper(0.155) - 0.01, 0.042, 0.075, u, v),
        box_sdf(-0.015, lower(-0.015) + 0.015, 0.046, 0.08, u, v),
    )
    mouth = np.maximum(mouth, -teeth)
    return min_of(eye, nose, mouth)


def min_of(*fields):
    out = fields[0]
    for field in fields[1:]:
        out = np.minimum(out, field)
    return out


def shell_sdf(p):
    outer = pumpkin_sdf(p)
    carve = np.maximum(np.maximum(face_sdf(p[:, 0], p[:, 1]), -(outer + FLOOR)), p[:, 2] - FRONT_CUT)
    return np.maximum(outer, -carve)


def glow_sdf(p):
    """A cap filling the front of the inside, its surface WALL under the shell's skin."""
    return np.maximum(pumpkin_sdf(p) + WALL, p[:, 2] - FRONT_CUT)


# ---------------------------------------------------------------- the stem and its leaf

# The stem rises from the dimple, leaning back a little, then rolls over to the wearer's right into a
# spiral curl that faces the front (so it reads in the silhouette from any side).


def stem_path():
    points = [(0.0, TOP - 0.11, 0.0), (0.002, TOP - 0.03, 0.004), (0.008, TOP + 0.05, 0.012), (0.02, TOP + 0.11, 0.018)]
    center = np.array([0.125, TOP + 0.155, 0.02])
    start = math.atan2(points[-1][1] - center[1], points[-1][0] - center[0])
    for i in range(1, 29):
        t = i / 28
        angle = start - t * 1.3 * 2 * math.pi  # clockwise seen from the front: over the top, down, in
        radius = 0.112 * (1 - 0.68 * t)
        points.append((center[0] + radius * math.cos(angle), center[1] + radius * math.sin(angle), center[2] - 0.035 * t))
    return points


STEM_PATH = stem_path()
STEM_R0, STEM_R1 = 0.074, 0.026


def stem_sdf(p):
    d = None
    count = len(STEM_PATH)
    for i in range(count - 1):
        r = STEM_R0 + (STEM_R1 - STEM_R0) * (i + 0.5) / (count - 1)
        segment = sd_capsule(p, STEM_PATH[i], STEM_PATH[i + 1], r)
        d = segment if d is None else smin(d, segment, 0.02)
    # A flared foot where it grows out of the pumpkin.
    foot = np.linalg.norm((p - np.array([0.0, TOP - 0.035, 0.0])) / np.array([0.13, 0.05, 0.13]), axis=1) - 1.0
    d = smin(d, foot * 0.05, 0.045)
    return smin(d, leaf_sdf(p), 0.018)


# The leaf lies over the pumpkin's top toward the wearer's back left, drooping with its curve, cupped.
LEAF_BASE = np.array([-0.05, TOP - 0.005, 0.045])
LEAF_DIR = np.array([-0.78, 0.0, 0.62]) / np.linalg.norm([-0.78, 0.0, 0.62])
LEAF_SIDE = np.cross(np.array([0.0, 1.0, 0.0]), LEAF_DIR)
LEAF_LENGTH, LEAF_WIDTH, LEAF_THICK = 0.47, 0.3, 0.034


def leaf_sdf(p):
    rel = p - LEAF_BASE
    a = rel @ LEAF_DIR  # along the leaf
    c = rel @ LEAF_SIDE  # across it
    b = rel[:, 1]  # up
    t = np.clip(a / LEAF_LENGTH, 0, 1)
    half = LEAF_WIDTH / 2 * np.sin(math.pi * (0.06 + 0.94 * t)) ** 0.7
    middle = -0.2 * (t**1.6) * LEAF_LENGTH + 0.07 * (c / (LEAF_WIDTH / 2)) ** 2  # droops, edges curl up
    across = np.abs(c) - half
    thick = np.abs(b - middle) - LEAF_THICK / 2 * np.clip(1 - (c / np.maximum(half, 1e-3)) ** 2, 0.15, 1) ** 0.5
    ends = np.maximum(-a, a - LEAF_LENGTH)
    return np.maximum(np.maximum(across, thick), ends)


# ---------------------------------------------------------------- the prop


def pumpkin_hat():
    shell = sdf_surface(shell_sdf, (-0.86, -0.06, -0.86), (0.86, TOP + 0.05, 0.86), 0.0095)
    glow = sdf_mesh(glow_sdf, (-0.8, 0.0, -0.8), (0.8, TOP, FRONT_CUT + 0.05), 0.02)
    stem = sdf_mesh(stem_sdf, (-0.48, TOP - 0.2, -0.12), (0.35, TOP + 0.37, 0.4), 0.0055)
    return {
        "HatShell": split_sharp(simplify(shell, SHELL_TRIS), 36),
        "HatGlow": simplify(glow, GLOW_TRIS),
        "HatStem": simplify(stem, STEM_TRIS),
    }


PROPS = {"PumpkinHat": pumpkin_hat}

# Preview colours only; the game colours pieces by name (World/Props/Hats.luau).
COLORS = {"HatShell": (255, 128, 24), "HatGlow": (255, 196, 70), "HatStem": (86, 142, 52)}
