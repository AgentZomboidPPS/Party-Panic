"""Meshes for Shark Bait, a sunny tropical cove: swimmers hop between round log rafts grabbing coins
while cartoon sharks circle, chomping swimmers who fall in and tipping rafts over.

    python3 tools/meshgen/generate_meshes.py --only SharkBaitShark,SharkBaitRaft,SharkBaitCoin

Units are studs, +Y is up, the base sits on y = 0 and -Z is the front. Everything here is built from
numpy and the shared helpers only (no scikit-image), so any checkout can regenerate it.

  * SharkBaitShark: snout at -Z. Its bounding box runs x -3.2..3.2, y 0..6, z -6.2..6.2, so the
    game's pivot (bottom center of the box) is the model origin. Water line at y = 2.6.
      - Jaw + JawTeeth: modelled 12 degrees open; they turn together about the X axis through
        (y = 1.3, z = -2.0) (the mouth's back corners). Opening further moves the chin down.
      - Tail: wags about the vertical axis through (x = 0, z = 3.0), its front end (it starts
        there, tucked inside the body).
  * SharkBaitRaft: round, deck radius 7.0, deck top flat at y = 2.0 (the highest point), water at
    y = 1.0.
  * Backdrop props stand on y = 0 at their deepest point; see each builder for its water line.
"""

import math

import numpy as np

from generate_meshes import Mesh, capsule, cylinder, extrude, icosphere, lathe, merge, organic_lathe, rounded_box, sphere, taper, torus, tube, weld

TAU = 2 * math.pi


# =============================================================================== helpers

def pchip(xs, ys, x):
    """Monotone cubic interpolation (no overshoot) of the points (xs, ys) at x."""
    xs = np.asarray(xs, float)
    ys = np.asarray(ys, float)
    x = np.asarray(x, float)
    h = np.diff(xs)
    d = np.diff(ys) / h
    m = np.zeros_like(ys)
    for i in range(1, len(xs) - 1):
        if d[i - 1] * d[i] > 0:
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
    m[0] = d[0] if len(d) == 1 else ((2 * h[0] + h[1]) * d[0] - h[0] * d[1]) / (h[0] + h[1])
    m[-1] = d[-1] if len(d) == 1 else ((2 * h[-1] + h[-2]) * d[-1] - h[-1] * d[-2]) / (h[-1] + h[-2])
    if m[0] * d[0] <= 0:
        m[0] = 0.0
    if m[-1] * d[-1] <= 0:
        m[-1] = 0.0
    i = np.clip(np.searchsorted(xs, x) - 1, 0, len(xs) - 2)
    t = np.clip((x - xs[i]) / h[i], 0.0, 1.0)
    t2, t3 = t * t, t * t * t
    return ((2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h[i] * m[i] + (-2 * t3 + 3 * t2) * ys[i + 1]
            + (t3 - t2) * h[i] * m[i + 1])


def smoothstep(e0, e1, x):
    t = np.clip((np.asarray(x, float) - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def ring_faces(n_rings: int, n: int, closed: bool = True, offset: int = 0) -> list:
    """Quads between consecutive rings of n points (ring i holds points offset + i*n .. +n-1)."""
    faces = []
    for i in range(n_rings - 1):
        for j in range(n if closed else n - 1):
            a = offset + i * n + j
            b = offset + i * n + (j + 1) % n
            c, d = a + n, b + n
            faces += [(a, c, b), (b, c, d)]
    return faces


def loft(rings, start=None, end=None) -> Mesh:
    """A closed surface through rings of points (n_rings, n, 3), each ring closed, capped with a
    fan to the `start` / `end` points (or to the ring's centroid when they are None)."""
    rings = np.asarray(rings, float)
    count, n = rings.shape[:2]
    verts = list(rings.reshape(-1, 3))
    faces = ring_faces(count, n)
    for which, point in ((0, start), (count - 1, end)):
        center = len(verts)
        verts.append(np.asarray(point, float) if point is not None else rings[which].mean(axis=0))
        base = which * n
        for j in range(n):
            a, b = base + j, base + (j + 1) % n
            faces.append((center, b, a) if which == 0 else (center, a, b))
    return orient_closed(Mesh(np.array(verts), faces))


def orient_closed(mesh: Mesh) -> Mesh:
    """Turns a closed, consistently wound mesh outward (positive volume)."""
    tri = mesh.v[mesh.f]
    tri = tri - mesh.v.mean(axis=0)
    if np.einsum("ij,ij->i", tri[:, 0], np.cross(tri[:, 1], tri[:, 2])).sum() < 0:
        mesh.f = mesh.f[:, ::-1].copy()
    return mesh


def chaikin(points, iterations: int = 2, closed: bool = True):
    """Corner-cutting smoothing of a polyline (array (n, d)); the count grows 2x per pass."""
    p = np.asarray(points, float)
    for _ in range(iterations):
        q = np.roll(p, -1, axis=0) if closed else p[1:]
        a = p if closed else p[:-1]
        cut = np.empty((len(a) * 2, p.shape[1]))
        cut[0::2] = 0.75 * a + 0.25 * q
        cut[1::2] = 0.25 * a + 0.75 * q
        p = cut if closed else np.vstack([p[:1], cut, p[-1:]])
    return p


def resample(points, count: int, closed: bool = True):
    """Evenly spaced points along a polyline."""
    p = np.asarray(points, float)
    if closed:
        p = np.vstack([p, p[:1]])
    seg = np.linalg.norm(np.diff(p, axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    targets = np.linspace(0, s[-1], count, endpoint=not closed)
    out = np.empty((count, p.shape[1]))
    for k in range(p.shape[1]):
        out[:, k] = np.interp(targets, s, p[:, k])
    return out


def seg_dist(points, a, b):
    """Distance from points (n, 3) to the segment a-b, and the parameter along it."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    ab = b - a
    t = np.clip(((points - a) @ ab) / max(ab @ ab, 1e-12), 0, 1)
    return np.linalg.norm(points - (a + t[:, None] * ab), axis=1), t


def vertex_normals(mesh: Mesh) -> np.ndarray:
    tri = mesh.v[mesh.f]
    fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    vn = np.zeros_like(mesh.v)
    for i in range(3):
        np.add.at(vn, mesh.f[:, i], fn)
    return vn / (np.linalg.norm(vn, axis=1, keepdims=True) + 1e-12)


def poly_dist(p2, poly):
    """Distance from 2D points (n, 2) to a closed polygon's edges."""
    poly = np.asarray(poly, float)
    a = poly
    b = np.roll(poly, -1, axis=0)
    best = np.full(len(p2), np.inf)
    for pa, pb in zip(a, b):
        ab = pb - pa
        t = np.clip(((p2 - pa) @ ab) / max(ab @ ab, 1e-12), 0, 1)
        d = np.linalg.norm(p2 - (pa + t[:, None] * ab), axis=1)
        best = np.minimum(best, d)
    return best


def star_ok(outline, c) -> bool:
    angles = np.unwrap(np.arctan2(outline[:, 1] - c[1], outline[:, 0] - c[0]))
    step = np.diff(np.append(angles, angles[0] + (TAU if angles[-1] > angles[0] else -TAU)))
    return bool(np.all(step > 1e-6) or np.all(step < -1e-6))


def star_center(outline, hint):
    """A point the whole outline can be seen from (for fan triangulation), as near `hint` as possible."""
    outline = np.asarray(outline, float)
    hint = np.asarray(hint, float)
    if star_ok(outline, hint):
        return hint
    lo, hi = outline.min(axis=0), outline.max(axis=0)
    best, best_d = None, np.inf
    for gx in np.linspace(lo[0], hi[0], 41):
        for gy in np.linspace(lo[1], hi[1], 41):
            c = np.array([gx, gy])
            d = np.linalg.norm(c - hint)
            if d < best_d and star_ok(outline, c):
                best, best_d = c, d
    assert best is not None, "pillow outline is not star-shaped from any point"
    return best


def pillow(outline, center, half_thickness, rings: int = 8, edge: float = 0.12) -> Mesh:
    """A closed, rounded slab over a 2D outline (a fin, a starfish, a leaf...): in the local XY plane,
    thickness along Z. The outline must be star-shaped seen from `center`. `half_thickness(p2)`
    gives the half thickness inside (array of (n, 2) points -> (n,)); near the rim it rounds off
    over the distance `edge` so the edge is a soft bead, not a knife."""
    outline = np.asarray(outline, float)
    c = star_center(outline, center)
    angles = np.unwrap(np.arctan2(outline[:, 1] - c[1], outline[:, 0] - c[0]))
    if angles[-1] < angles[0]:
        outline = outline[::-1]
    n = len(outline)
    # Rings from the center out; denser towards the rim, where the edge rounds.
    s = 1 - (1 - np.linspace(0, 1, rings + 1)[1:]) ** 1.6
    pts = [c[None, :] + s[k] * (outline - c) for k in range(rings)]
    pts = np.vstack([c[None, :]] + pts)  # center, then ring 1..rings (the last is the outline)
    d = poly_dist(pts, outline)
    d[-n:] = 0.0
    h = np.asarray(half_thickness(pts), float)
    round_off = np.sqrt(np.clip(1 - (1 - np.clip(d / edge, 0, 1)) ** 2, 0, 1))
    h = h * round_off
    h[-n:] = 0.0
    top = np.column_stack([pts, h])
    bottom = np.column_stack([pts[:-n], -h[:-n]])  # the rim ring is shared
    verts = np.vstack([top, bottom])
    faces = []
    m = len(pts)
    # top: center fan + ring quads
    for j in range(n):
        faces.append((0, 1 + j, 1 + (j + 1) % n))
    for k in range(rings - 1):
        for j in range(n):
            a = 1 + k * n + j
            b = 1 + k * n + (j + 1) % n
            faces += [(a, a + n, b), (b, a + n, b + n)]
    # bottom: same with reversed winding; the last ring maps to the shared rim
    def bi(index):
        return index if index >= m - n else m + index
    for j in range(n):
        faces.append((bi(0), bi(1 + (j + 1) % n), bi(1 + j)))
    for k in range(rings - 1):
        for j in range(n):
            a = 1 + k * n + j
            b = 1 + k * n + (j + 1) % n
            faces += [(bi(a), bi(b), bi(a + n)), (bi(b), bi(b + n), bi(a + n))]
    return orient_closed(Mesh(verts, faces))


def place(mesh: Mesh, origin, ex, ey, ez) -> Mesh:
    """Maps a mesh's local axes onto the given world directions at `origin`."""
    basis = np.array([ex, ey, ez], float)
    mesh.v = mesh.v @ basis + np.asarray(origin, float)
    if np.linalg.det(basis) < 0:
        mesh.f = mesh.f[:, ::-1].copy()
    return mesh


def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


def ellipsoid(radii, rings: int = 10, segments: int = 16) -> Mesh:
    return sphere(1.0, rings, segments).scale(*radii)


def bulge(mesh: Mesh, a, b, radius: float, height: float, normals=None) -> Mesh:
    """Pushes a mesh's surface out along its normals in a soft capsule-shaped bump around a-b."""
    n = vertex_normals(mesh) if normals is None else normals
    d, _ = seg_dist(mesh.v, a, b)
    w = np.clip(1 - (d / radius) ** 2, 0, 1) ** 2
    mesh.v = mesh.v + n * (height * w)[:, None]
    return mesh


def rotate_about(mesh: Mesh, axis: str, degrees: float, pivot) -> Mesh:
    p = np.asarray(pivot, float)
    return mesh.translate(*(-p)).rotate(axis, degrees).translate(*p)


def tooth(base, tip, half_w: float, half_t: float, along, bend=0.0, sides: int = 8) -> Mesh:
    """A flattened cone from `base` to `tip`: half_w wide along `along`, half_t thick across."""
    base, tip = np.asarray(base, float), np.asarray(tip, float)
    axis = tip - base
    length = np.linalg.norm(axis)
    axis /= length
    u = np.asarray(along, float) - axis * (np.asarray(along, float) @ axis)
    u /= np.linalg.norm(u)
    w = np.cross(axis, u)
    rings = []
    for t, scale in ((0.0, 1.0), (0.35, 0.82), (0.7, 0.45), (0.93, 0.12)):
        center = base + axis * length * t + w * bend * math.sin(math.pi * t)
        ring = [center + (u * math.cos(a) * half_w + w * math.sin(a) * half_t) * scale for a in np.linspace(0, TAU, sides, endpoint=False)]
        rings.append(ring)
    return loft(rings, start=base - axis * 0.02, end=tip + w * bend * 0.1)


def strip_tube(points, radii, sides: int = 8) -> Mesh:
    """A closed tube along a polyline with a radius per point (ends taper to the given radii)."""
    mesh = tube(points, 1.0, sides)
    for i, (p, r) in enumerate(zip(points, radii)):
        ring = slice(i * sides, (i + 1) * sides)
        mesh.v[ring] = np.asarray(p) + (mesh.v[ring] - np.asarray(p)) * r
    count = len(points)
    verts = [tuple(v) for v in mesh.v]
    faces = [tuple(f) for f in mesh.f]
    for end, start, flip in ((points[0], 0, True), (points[-1], (count - 1) * sides, False)):
        center = len(verts)
        verts.append(tuple(end))
        for j in range(sides):
            a, b = start + j, start + (j + 1) % sides
            faces.append((center, b, a) if flip else (center, a, b))
    return orient_closed(Mesh(verts, faces))


def anchor_tris(points, y: float = 0.0) -> list:
    """Tiny triangles that stretch a prop's bounding box (the game pivots on the box's bottom center)."""
    return [Mesh([(x, y, z), (x + 0.02, y, z), (x, y, z + 0.02)], [(0, 2, 1)]) for x, z in points]


def raycast(mesh: Mesh, origin, direction):
    """First hit of a ray on a mesh: (point, unit face normal) or None (Moller-Trumbore, all faces)."""
    o = np.asarray(origin, float)
    d = unit(direction)
    tri = mesh.v[mesh.f]
    e1 = tri[:, 1] - tri[:, 0]
    e2 = tri[:, 2] - tri[:, 0]
    p = np.cross(d, e2)
    det = np.einsum("ij,ij->i", e1, p)
    ok = np.abs(det) > 1e-12
    inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
    s = o - tri[:, 0]
    u = np.einsum("ij,ij->i", s, p) * inv
    q = np.cross(s, e1)
    v = (q @ d) * inv
    t = np.einsum("ij,ij->i", e2, q) * inv
    hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 1e-6)
    if not hit.any():
        return None
    k = np.flatnonzero(hit)[np.argmin(t[hit])]
    n = unit(np.cross(e1[k], e2[k]))
    if n @ d > 0:
        n = -n
    return o + d * t[k], n


def surface_curve(mesh: Mesh, points, direction, sink: float):
    """Projects points onto a mesh along `direction` (cast from outside, i.e. along -direction
    towards the mesh), then sinks them `sink` along the surface normal."""
    out = []
    d = unit(direction)
    for p in points:
        hit = raycast(mesh, np.asarray(p, float) + d * 4.0, -d)
        if hit is None:
            raise ValueError(f"surface_curve: no hit near {p}")
        point, normal = hit
        out.append(point - normal * sink)
    return np.array(out)


# =============================================================================== the shark

HINGE_Y, HINGE_Z = 1.3, -2.0  # the jaw hinge: the mouth's back corners
JAW_REST = 12.0  # degrees open, as modelled
TAIL_Z = 3.0  # the tail wags about the vertical axis through (0, TAIL_Z)
SNOUT_Z, MOUTH_Z = -6.2, -5.3  # the snout tip; the front of the mouth (lower jaw apex)
TIP_Y = 2.3  # the snout tip, a little upturned
REAR_Z, REAR_END = 3.5, 3.85
N_UP, N_LOW = 2.05, 2.3  # superellipse exponents of the upper and lower halves

# The closed head and body (as if the jaw were shut) along Z: half width, top, widest-point height.
_AZ = [-6.2, -6.16, -6.05, -5.85, -5.55, -5.1, -4.5, -3.8, -3.0, -2.2, -1.5, -0.8, 0.0, 0.8, 1.6, 2.3, 2.8, 3.2, 3.5]
_AA = [0.0, 0.17, 0.32, 0.5, 0.72, 0.97, 1.21, 1.42, 1.58, 1.68, 1.71, 1.66, 1.52, 1.3, 1.0, 0.72, 0.55, 0.42, 0.34]
_AT = [2.3, 2.45, 2.57, 2.71, 2.88, 3.06, 3.22, 3.36, 3.45, 3.5, 3.5, 3.47, 3.38, 3.2, 2.98, 2.85, 2.79, 2.74, 2.7]
_AC = [2.3, 2.27, 2.24, 2.2, 2.15, 2.08, 2.0, 1.93, 1.85, 1.79, 1.78, 1.79, 1.85, 1.95, 2.08, 2.2, 2.27, 2.31, 2.33]
# Its underside: the snout in front of the mouth, the lower jaw (shut; high enough that it stays
# above y = 0 when open), then the throat and belly.
_SNZ, _SNY = [-6.2, -6.16, -6.05, -5.85, -5.6, -5.3], [2.3, 2.15, 1.95, 1.68, 1.4, 1.12]
_JWZ, _JWY = [-5.3, -5.24, -5.12, -4.9, -4.5, -3.9, -3.2, -2.6, -2.0], [1.1, 0.88, 0.76, 0.66, 0.56, 0.43, 0.29, 0.22, 0.2]
_BLZ, _BLY = [-2.0, -1.5, -0.8, 0.0, 0.8, 1.6, 2.3, 2.8, 3.2, 3.5], [0.2, 0.2, 0.23, 0.38, 0.68, 1.1, 1.5, 1.76, 1.9, 1.98]


def shark_profile(z: float):
    """(half width, top, widest-point height, underside) of the closed head/body at z."""
    if z > REAR_Z:
        f = math.sqrt(max(0.0, 1 - ((z - REAR_Z) / (REAR_END - REAR_Z)) ** 2))
        a, top, yc, bottom = _AA[-1], _AT[-1], _AC[-1], _BLY[-1]
        return a * f, yc + (top - yc) * f, yc, yc - (yc - bottom) * f
    a, top, yc = (float(pchip(_AZ, s, z)) for s in (_AA, _AT, _AC))
    if z < MOUTH_Z:
        bottom = float(pchip(_SNZ, _SNY, z))
    elif z < HINGE_Z:
        bottom = float(pchip(_JWZ, _JWY, z))
    else:
        bottom = float(pchip(_BLZ, _BLY, z))
    return a, top, yc, bottom


def lip_y(z: float) -> float:
    """The upper lip (palate edge) height; the mouth's corners curl up to the hinge."""
    s = min(1.0, max(0.0, (z - MOUTH_Z) / (HINGE_Z - MOUTH_Z)))
    return 1.12 + 0.18 * s ** 2.2


def se(c, n):
    return np.sign(c) * np.abs(c) ** (2.0 / n)


def half_width_at(z: float, y: float) -> float:
    a, top, yc, bottom = shark_profile(z)
    if y >= yc:
        t = min(1.0, (y - yc) / max(top - yc, 1e-6))
        return a * (1 - t ** N_UP) ** (1 / N_UP)
    t = min(1.0, (yc - y) / max(yc - bottom, 1e-6))
    return a * (1 - t ** N_LOW) ** (1 / N_LOW)


def section_point(a, top, yc, bottom, theta):
    """Point on the closed cross-section; theta from the top (0) towards +X (pi/2), bottom at pi."""
    s, c = np.sin(theta), np.cos(theta)
    upper = c >= 0
    n = np.where(upper, N_UP, N_LOW)
    x = a * se(s, n)
    y = yc + np.where(upper, top - yc, yc - bottom) * se(c, n)
    return x, y


N_ARC, N_PAL = 46, 10
BETA_REF = math.radians(76)


def head_ring(z: float):
    """One ring of the Body: in front of the hinge the bottom is cut flat at the lip (the palate,
    hidden inside the Mouth), behind it the ring goes round the throat and belly."""
    a, top, yc, bottom = shark_profile(z)
    cut = None
    if MOUTH_Z < z <= HINGE_Z - 0.06:
        cut = lip_y(z)
        if cut <= bottom + 1e-4:
            cut = None
    if cut is not None:
        beta = math.acos(min(1.0, ((yc - cut) / (yc - bottom)) ** (N_LOW / 2)))
    elif z <= MOUTH_Z:
        beta = 0.0
    else:
        beta = BETA_REF
    theta = np.linspace(math.pi - beta, -(math.pi - beta), N_ARC)
    x, y = section_point(a, top, yc, bottom, theta)
    arc = np.column_stack([x, y, np.full(N_ARC, z)])
    if cut is not None:
        xc = arc[0, 0]
        xs = np.linspace(-xc, xc, N_PAL + 2)[1:-1]
        ys = cut + 0.05 * (1 - (xs / max(xc, 1e-6)) ** 2)
        low = np.column_stack([xs, ys, np.full(N_PAL, z)])
    else:
        th = np.linspace(math.pi + beta, math.pi - beta, N_PAL + 2)[1:-1]
        bx, by = section_point(a, top, yc, bottom, th)
        low = np.column_stack([bx, by, np.full(N_PAL, z)])
    return np.vstack([arc, low])


def shark_ring_zs():
    zs = [SNOUT_Z + (MOUTH_Z - SNOUT_Z) * (1 - math.cos(math.radians(a))) for a in np.linspace(8, 90, 12)]
    zs += list(np.linspace(MOUTH_Z + 0.04, HINGE_Z - 0.06, 27))
    zs += [HINGE_Z + 0.06]
    zs += list(np.linspace(HINGE_Z + 0.22, REAR_Z, 25))
    zs += [REAR_Z + (REAR_END - REAR_Z) * (1 - math.cos(math.radians(a))) for a in np.linspace(14, 80, 6)]
    return zs


def shark_body_shell() -> Mesh:
    rings = [head_ring(z) for z in shark_ring_zs()]
    return loft(rings, start=(0.0, TIP_Y, SNOUT_Z), end=(0.0, _AC[-1], REAR_END))


def flank_line(z):
    """Height of the wavy line where the grey-blue back meets the white belly."""
    z = np.asarray(z, float)
    base = pchip([-2.0, -1.0, 0.0, 1.0, 2.0, 2.8, 3.3, 3.62], [1.26, 1.16, 1.2, 1.42, 1.74, 1.98, 2.13, 2.24], z)
    wave = 0.12 * np.sin((z + 2.0) * 3.4) + 0.06 * np.sin((z + 2.0) * 7.1 + 1.3)
    return base + wave * smoothstep(-2.0, -1.4, z) * (1 - smoothstep(2.9, 3.5, z))


def belly_ring(z: float, y_edge: float):
    a, top, yc, bottom = shark_profile(z)
    t = min(0.999, max(0.0, (yc - y_edge) / (yc - bottom)))
    beta = math.acos(t ** (N_LOW / 2))
    theta = np.linspace(math.pi - beta, math.pi + beta, 18)
    pts = []
    for offset in (0.04, -0.06):
        x, y = section_point(a + offset, top, yc, bottom - offset, theta)
        pts.append(np.column_stack([x, y, np.full(len(theta), z)]))
    return np.vstack([pts[0], pts[1][::-1]])


def shark_belly() -> Mesh:
    """The white underside, a hair proud of the Body, from the throat back to the tail."""
    zs = np.linspace(HINGE_Z + 0.1, 3.62, 44)
    rings = [belly_ring(z, min(y, shark_profile(z)[2] - 0.05)) for z, y in zip(zs, flank_line(zs))]
    return loft(rings)


def jaw_ring(z: float):
    """Cross-section of the lower jaw (shut): its outer skin under the lip, the lip rim and the
    scooped floor of the mouth."""
    a, top, yc, bottom = shark_profile(z)
    lip = lip_y(min(z, HINGE_Z)) - 0.035
    t = min(1.0, max(0.0, (yc - lip) / (yc - bottom)))
    beta = math.acos(t ** (N_LOW / 2))
    x_lip = a * math.sin(beta) ** (2 / N_LOW)
    inset = 0.07 + 0.04 * float(smoothstep(-3.0, -2.0, z))
    sx = max(0.0, (x_lip - inset) / max(x_lip, 1e-6))
    theta = np.linspace(math.pi - beta, math.pi + beta, 24)
    ox, oy = section_point(a, top, yc, bottom, theta)
    outer = np.column_stack([ox * sx, oy])
    x_out = x_lip * sx
    rim = min(0.24, 0.45 * x_out)
    x_in = x_out - rim
    depth = float(np.clip((lip - bottom) - 0.2, 0.0, 0.45))
    tf = np.linspace(math.pi, 0, 14)[1:-1]
    floor = np.column_stack([x_in * np.cos(tf), lip - 0.03 - depth * np.sin(tf) ** 0.8])
    top_pts = [(-x_out + 0.03, lip), (-x_in - 0.02, lip), (-x_in, lip - 0.03)]
    top_pts += [tuple(p) for p in floor]
    top_pts += [(x_in, lip - 0.03), (x_in + 0.02, lip), (x_out - 0.03, lip)]
    ring = np.vstack([outer, np.array(top_pts)])
    return np.column_stack([ring, np.full(len(ring), z)])


def shark_jaw_closed() -> Mesh:
    zs = [MOUTH_Z + 0.3 * (1 - math.cos(math.radians(a))) for a in np.linspace(16, 90, 7)]
    zs += list(np.linspace(MOUTH_Z + 0.38, HINGE_Z + 0.1, 21))
    rings = [jaw_ring(z) for z in zs]
    return loft(rings, start=(0.0, lip_y(MOUTH_Z) - 0.07, MOUTH_Z - 0.015))


def mouth_inside() -> Mesh:
    """The static inside of the mouth: a D-shaped wedge fanning about the hinge from inside the head
    down past where the jaw's floor is when it's open 35 degrees. It stays inside the jaw when the
    jaw is shut, so it only shows through the open mouth."""
    rings = []
    for psi in np.linspace(-14, 46, 17):
        R = float(pchip([-14, 0, 8, 12.4, 16.5, 24.6, 33, 40, 46], [2.9, 3.0, 3.0, 2.78, 2.4, 1.88, 1.58, 1.38, 1.26], psi))
        W = float(pchip([-14, 0, 20, 46], [1.4, 1.44, 1.34, 1.1], psi))
        rb = -0.25
        t = np.linspace(0, math.pi, 22)
        xs = np.concatenate([W * np.cos(t), np.linspace(-W, W, 6)[1:-1]])
        rs = np.concatenate([rb + (R - rb) * np.sin(t) ** 0.85, np.full(4, rb)])
        p = math.radians(psi)
        rings.append(np.column_stack([xs, HINGE_Y - rs * math.sin(p), HINGE_Z - rs * math.cos(p)]))
    return loft(rings)


def lip_curve(offset: float):
    """The +X half of the mouth's U from its front center back to the corner, `offset` in from the
    upper lip's edge, at the lip height."""
    pts = []
    for z in np.linspace(MOUTH_Z + 0.02, HINGE_Z - 0.12, 140):
        y = lip_y(z)
        x = half_width_at(z, y) - offset
        if x > 0:
            pts.append((x, y, z))
    pts = np.array(pts)
    return np.vstack([[0.0, pts[0, 1], pts[0, 2] - 0.02], pts])


def lerp_(a, b, t):
    return a + (b - a) * t


def smooth_outline(points, count: int = 56, iterations: int = 2):
    return resample(chaikin(np.asarray(points, float), iterations), count)


def teeth_along(curve, count, start, spacing, length, width, pointing, depth: float = 0.06):
    """Flattened-cone teeth along a mouth curve (its +X half, mirrored): pointing -1 hangs them down
    from the upper lip, +1 stands them up on the lower lip. Sizes run front -> back."""
    seg = np.linalg.norm(np.diff(curve, axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    teeth = []
    for k in range(count):
        at = start + k * spacing
        if at > s[-1] - 0.05:
            break
        p = np.array([np.interp(at, s, curve[:, i]) for i in range(3)])
        q = np.array([np.interp(at + 0.04, s, curve[:, i]) for i in range(3)])
        along = unit(q - p)
        inward = unit(np.cross(along, (0.0, 1.0, 0.0)))
        if inward[0] > 0:
            inward = -inward
        f = k / max(1, count - 1)
        L, w = lerp_(length[0], length[1], f), lerp_(width[0], width[1], f)
        for side in (1, -1):
            m = np.array([side, 1.0, 1.0])
            base = p * m - np.array([0, pointing * depth, 0])
            tip = p * m + np.array([0, pointing * L, 0]) + inward * m * 0.06
            teeth.append(tooth(base, tip, w, w * 0.55, along * m))
    return teeth


def mirrored_fin(fin: Mesh, side: int) -> Mesh:
    if side < 0:
        fin.v[:, 0] *= -1
        fin.f = fin.f[:, ::-1].copy()
    return fin


def shark_fins():
    """Dorsal, pectoral and pelvic fins (all in the Body piece)."""
    dorsal_pts = [(-0.8, 3.1), (1.45, 2.95), (1.35, 3.25), (1.2, 3.6), (1.12, 4.0), (1.15, 4.45), (1.27, 4.9),
                  (1.45, 5.35), (1.65, 5.7), (1.82, 5.93), (1.86, 6.03), (1.72, 6.05), (1.4, 5.9), (1.0, 5.55),
                  (0.6, 5.08), (0.22, 4.5), (-0.12, 3.95), (-0.45, 3.5), (-0.72, 3.25)]

    def dorsal_h(p):
        y = p[:, 1]
        h = 0.3 * (1 - 0.66 * np.clip((y - 3.25) / 2.75, 0, 1) ** 0.8)
        return h + 0.14 * np.exp(-(((y - 3.25) / 0.3) ** 2)) * (y < 3.9)

    dorsal = pillow(smooth_outline(dorsal_pts, 60), (0.55, 4.1), dorsal_h, rings=7, edge=0.16)
    dorsal = place(dorsal, (0, 0, 0), (0, 0, 1), (0, 1, 0), (1, 0, 0))
    top = dorsal.v[:, 1].max()
    dorsal.v[:, 1] = 3.3 + (dorsal.v[:, 1] - 3.3) * (6.0 - 3.3) / (top - 3.3)  # tip exactly at y = 6

    pect_pts = [(-0.5, 0.05), (-0.5, 1.3), (0.0, 1.38), (0.5, 1.4), (0.95, 1.5), (1.35, 1.65), (1.7, 1.82), (1.98, 1.98),
                (2.12, 2.02), (2.04, 1.84), (1.76, 1.43), (1.4, 1.0), (1.0, 0.62), (0.55, 0.3), (0.1, 0.08)]
    p_outline = smooth_outline(pect_pts, 50)
    fins = [dorsal]
    pects = []
    for side in (1, -1):
        fin = pillow(p_outline, (0.65, 0.85), lambda p: 0.19 - 0.11 * np.clip(p[:, 0] / 2.1, 0, 1), rings=6, edge=0.1)
        s = unit((1.0, -0.6, 0.1))
        c = unit(np.array([0, 0, 1.0]) - s * s[2])
        pects.append(mirrored_fin(place(fin, (1.42, 1.15, -1.95), s, c, np.cross(s, c)), side))
    low = min(m.v[:, 1].min() for m in pects)
    for m in pects:
        m.translate(0, -low, 0)  # the fin tips are the shark's lowest point: exactly y = 0
    fins += pects
    pelvic_pts = [(-0.3, 0.0), (-0.3, 0.55), (0.2, 0.62), (0.5, 0.78), (0.64, 0.74), (0.5, 0.42), (0.2, 0.08)]
    pv_outline = smooth_outline(pelvic_pts, 28)
    for side in (1, -1):
        fin = pillow(pv_outline, (0.15, 0.36), lambda p: 0.08 - 0.03 * np.clip(p[:, 0] / 0.6, 0, 1), rings=4, edge=0.06)
        s = unit((0.75, -0.65, 0.25))
        c = unit(np.array([0, 0, 1.0]) - s * s[2])
        fins.append(mirrored_fin(place(fin, (0.42, 0.95, 0.85), s, c, np.cross(s, c)), side))
    return fins


def shark_tail():
    """The stalk with its keels and the big crescent tail (upper lobe the larger), a little second
    dorsal and anal fin. Its front end is the wag hinge (z = TAIL_Z), tucked inside the body."""
    zs = np.linspace(TAIL_Z, 4.9, 22)
    cy = 2.32 + 0.06 * (zs - TAIL_Z) / 1.9
    hh = pchip([3.0, 3.5, 4.1, 4.6, 4.9], [0.42, 0.36, 0.31, 0.34, 0.44], zs)
    hw = pchip([3.0, 3.5, 4.1, 4.6, 4.9], [0.36, 0.29, 0.21, 0.18, 0.17], zs)
    theta = np.linspace(0, TAU, 32, endpoint=False)
    rings = []
    for z, y0, h, w in zip(zs, cy, hh, hw):
        keel = 0.13 * smoothstep(3.6, 3.95, z) * (1 - smoothstep(4.5, 4.8, z))
        x = (w + keel * np.abs(np.sin(theta)) ** 16) * se(np.sin(theta), 2.2)
        y = y0 + h * se(np.cos(theta), 2.2)
        rings.append(np.column_stack([x, y, np.full(len(theta), z)]))
    stalk = loft(rings)

    caudal_pts = [(4.3, 2.4), (4.36, 2.05), (4.5, 1.65), (4.72, 1.25), (4.98, 0.9), (5.22, 0.66), (5.42, 0.58),
                  (5.52, 0.9), (5.56, 1.3), (5.5, 1.7), (5.38, 2.1), (5.3, 2.42), (5.42, 2.8), (5.62, 3.2), (5.86, 3.62),
                  (6.1, 4.02), (6.22, 4.22), (6.05, 4.26), (5.65, 4.18), (5.2, 4.0), (4.8, 3.68), (4.5, 3.25), (4.3, 2.8)]
    center = (4.8, 2.4)

    def caudal_h(p):
        d = np.hypot(p[:, 0] - center[0], p[:, 1] - center[1])
        return 0.22 - 0.14 * np.clip(d / 1.9, 0, 1)

    caudal = pillow(smooth_outline(caudal_pts, 76), center, caudal_h, rings=7, edge=0.12)
    caudal = place(caudal, (0, 0, 0), (0, 0, 1), (0, 1, 0), (1, 0, 0))
    # Pin the lobe tips to the brief: upper y = 4.2 (and z = 6.2), lower y = 0.6.
    v = caudal.v
    up = v[:, 1] > 2.4
    v[up, 1] = 2.4 + (v[up, 1] - 2.4) * (4.2 - 2.4) / (v[up, 1].max() - 2.4)
    v[~up, 1] = 2.4 - (2.4 - v[~up, 1]) * (2.4 - 0.6) / (2.4 - v[~up, 1].min())
    back = v[:, 2] > 4.7
    v[back, 2] = 4.7 + (v[back, 2] - 4.7) * (6.2 - 4.7) / (v[back, 2].max() - 4.7)

    small = []
    for pts, cen in (([(3.5, 2.6), (4.08, 2.56), (4.0, 2.8), (3.98, 3.0), (4.06, 3.18), (3.92, 3.21), (3.72, 3.02), (3.56, 2.8)], (3.8, 2.8)),
                     ([(3.55, 2.08), (4.08, 2.12), (4.0, 1.9), (3.98, 1.7), (4.06, 1.53), (3.9, 1.5), (3.7, 1.68), (3.56, 1.88)], (3.8, 1.9))):
        fin = pillow(smooth_outline(pts, 28), cen, lambda p: np.full(len(p), 0.075), rings=4, edge=0.06)
        small.append(place(fin, (0, 0, 0), (0, 0, 1), (0, 1, 0), (1, 0, 0)))
    return merge(stalk, caudal, *small)


def shark(jaw: float = JAW_REST):
    """A cartoon great white, snout to -Z, cruising with its back out of the water (y = 2.6)."""
    body = shark_body_shell()
    normals = vertex_normals(body)

    # Eyes: small, glossy black, set back and high, each under a heavy brow (a cheeky glare).
    eyes, shines, brows = [], [], []
    eye_p, eye_n = raycast(body, (0.0, 2.56, -3.75), (1.0, 0.05, -0.1))
    radii = (0.24, 0.3, 0.18)
    for side in (1, -1):
        m = np.array([side, 1.0, 1.0])
        p, n = eye_p * m, eye_n * m
        look = unit(n * 0.75 + np.array([0, 0.04, -1.0]) * 0.45)
        up = unit(np.array([0, 1.0, 0]) - look * look[1])
        right = np.cross(up, look)
        center = p - n * 0.07
        eyes.append(place(ellipsoid(radii, 12, 18), center, right, up, look))
        for dirn, size in (((0.3 * side, 0.45, 0.84), 0.075), ((-0.36 * side, -0.32, 0.88), 0.04)):
            d = unit(right * dirn[0] + up * dirn[1] + look * dirn[2])
            local = np.array([d @ right, d @ up, d @ look])
            k = 1.0 / math.sqrt(sum((local[i] / radii[i]) ** 2 for i in range(3)))
            shines.append(place(ellipsoid((size, size * 1.15, size * 0.5), 6, 10), center + d * (k - size * 0.2), right, up, d))
        brows.append((p + np.array([-side * 0.16, 0.22, -0.34]), p + np.array([side * 0.06, 0.36, 0.28])))
    for a, b in brows:
        bulge(body, a, b, 0.3, 0.2, normals)

    # Gill slits, nostrils and the smile creases: dark strokes set into the skin.
    marks = []
    for k in range(3):
        z0 = -1.62 + 0.42 * k
        y0, y1 = (1.38, 2.3) if k != 1 else (1.3, 2.4)
        ts = np.linspace(0, 1, 9)
        line = surface_curve(body, [(0.0, y0 + (y1 - y0) * t, z0 + 0.11 * math.sin(math.pi * t)) for t in ts], (1, 0, 0), 0.035)
        radii_g = 0.025 + 0.055 * np.sin(np.pi * ts) ** 0.7
        for side in (1, -1):
            marks.append(strip_tube([tuple(q * np.array([side, 1, 1])) for q in line], radii_g, 8))
    nose = surface_curve(body, [(0.17, 1.85, -5.86), (0.24, 1.78, -5.76), (0.3, 1.71, -5.64)], (0, -1.0, -0.35), 0.025)
    smile = surface_curve(body, [(0.0, 1.32, -2.14), (0.0, 1.42, -2.02), (0.0, 1.55, -1.93), (0.0, 1.66, -1.9)], (1, 0, 0), 0.03)
    for side in (1, -1):
        m = np.array([side, 1, 1])
        marks.append(strip_tube([tuple(q * m) for q in nose], [0.025, 0.042, 0.025], 8))
        marks.append(strip_tube([tuple(q * m) for q in smile], [0.045, 0.05, 0.04, 0.02], 8))

    # The mouth: the static inside and the upper teeth; the jaw and its teeth are built shut and
    # turned open about the hinge.
    teeth = teeth_along(lip_curve(0.12), 8, 0.18, 0.42, (0.4, 0.24), (0.14, 0.09), -1)
    lower_curve = lip_curve(0.21)
    lower_curve[:, 1] -= 0.035
    jaw_teeth = merge(*teeth_along(lower_curve, 7, 0.39, 0.44, (0.3, 0.18), (0.12, 0.08), 1))
    jaw_mesh = shark_jaw_closed()
    for mesh in (jaw_mesh, jaw_teeth):
        rotate_about(mesh, "x", -jaw, (0.0, HINGE_Y, HINGE_Z))

    return {
        "Body": merge(body, *shark_fins()),
        "Belly": shark_belly(),
        "Tail": shark_tail(),
        "Mouth": mouth_inside(),
        "Teeth": merge(*teeth),
        "Jaw": jaw_mesh,
        "JawTeeth": jaw_teeth,
        "Eyes": merge(*eyes),
        "EyeShine": merge(*shines),
        "Gills": merge(*marks),
    }


# =============================================================================== slabs

def ccw(poly):
    poly = np.asarray(poly, float)
    x, z = poly[:, 0], poly[:, 1]
    return poly if np.dot(x, np.roll(z, -1)) - np.dot(np.roll(x, -1), z) > 0 else poly[::-1].copy()


def inset(poly, d: float):
    """A convex polygon (counter-clockwise, (n, 2)) moved in by d (mitred corners)."""
    p = np.asarray(poly, float)
    prev, nxt = np.roll(p, 1, axis=0), np.roll(p, -1, axis=0)

    def normal(a, b):
        e = b - a
        n = np.column_stack([e[:, 1], -e[:, 0]])
        return n / (np.linalg.norm(n, axis=1, keepdims=True) + 1e-12)

    n1, n2 = normal(prev, p), normal(p, nxt)
    miter = (n1 + n2) / np.clip(1 + np.einsum("ij,ij->i", n1, n2), 0.3, None)[:, None]
    return p - miter * d


def slab(poly, y0: float, y1: float, r: float, steps: int = 2, bottom_round: bool = False) -> Mesh:
    """A convex 2D outline (x, z) made solid from y0 to y1 with its top edge rounded by r (and the
    bottom too if asked): planks, boards, signs."""
    poly = ccw(poly)
    rings = []

    def ring(d, y):
        q = inset(poly, d)
        rings.append(np.column_stack([q[:, 0], np.full(len(q), y), q[:, 1]]))

    if bottom_round:
        ring(r + 0.02, y0)
        for k in range(steps + 1):
            a = math.pi / 2 * k / steps
            ring(r * (1 - math.sin(a)), y0 + r * (1 - math.cos(a)))
    else:
        ring(0.0, y0)
    for k in range(steps + 1):
        a = math.pi / 2 * k / steps
        ring(r * (1 - math.cos(a)), y1 - r + r * math.sin(a))
    ring(r + 0.02, y1)
    c = poly.mean(axis=0)
    return loft(rings, start=(c[0], y0, c[1]), end=(c[0], y1, c[1]))


def circle_cut_rect(x0, x1, z0, z1, radius, arc_steps: int = 6):
    """The rectangle [x0, x1] x [z0, z1] cut to a circle about the origin (a plank end), (x, z) points."""
    pts = []
    for z in (z0, z1):
        pass
    zs = np.linspace(z0, z1, arc_steps + 1)
    right = [(min(x1, math.sqrt(max(radius ** 2 - z * z, 0.0))), z) for z in zs]
    left = [(max(x0, -math.sqrt(max(radius ** 2 - z * z, 0.0))), z) for z in zs[::-1]]
    pts = right + left
    out = []
    for p in pts:
        if not out or math.dist(p, out[-1]) > 1e-4:
            out.append(p)
    return np.array(out)


def lathe_x(profile, segments: int) -> Mesh:
    """A lathe about the X axis: profile is (radius, x)."""
    mesh = lathe(profile, segments)
    return mesh.rotate("z", -90)


def tube_ring(radius: float, minor: float, segments: int, sides: int, y: float = 0.0) -> Mesh:
    return torus(radius, minor, segments, sides).translate(0, y, 0)


# =============================================================================== the raft

DECK_TOP = 2.0
DECK_R = 7.0


def raft():
    """A round raft: nine planks cut to the circle, three cross beams, eight barrels lashed under
    it and a twisted rope round the rim (its top and outer edge just inside y = 2, r = 7)."""
    rnd = np.random.default_rng(21)
    thick = 0.35
    gap = 0.07
    rope_r, rope_y, rope_minor = 6.82, DECK_TOP - 0.18, 0.16
    planks = []
    count = 9
    pitch = 2 * 6.72 / count
    edges = [-6.72 + k * pitch + (rnd.uniform(-0.09, 0.09) if 0 < k < count else 0.0) for k in range(count + 1)]
    for k in range(count):
        z0, z1 = edges[k] + gap / 2, edges[k + 1] - gap / 2
        end = 6.7 + rnd.uniform(-0.03, 0.05)
        yaw = rnd.uniform(-0.7, 0.7)  # hand-laid: the gaps aren't quite parallel
        zc = (z0 + z1) / 2
        outline = circle_cut_rect(-9, 9, z0 - zc, z1 - zc, 99, 1)
        corners = np.array([(x * math.cos(math.radians(yaw)) - z * math.sin(math.radians(yaw)),
                             x * math.sin(math.radians(yaw)) + z * math.cos(math.radians(yaw)) + zc) for x, z in outline])
        # clip the turned board to the circle: walk its long edges and cut the ends on the circle
        lo_edge, hi_edge = corners[corners[:, 1].argsort()][:2], None
        zs = np.linspace(-1, 1, 2)
        a_dir = np.array([math.cos(math.radians(yaw)), math.sin(math.radians(yaw))])
        n_dir = np.array([-a_dir[1], a_dir[0]])
        half_w = (z1 - z0) / 2
        pts = []
        for side in (-1, 1):
            o = np.array([0.0, zc]) + n_dir * side * half_w
            # solve |o + t a| = end for the two ends
            b = o @ a_dir
            c = o @ o - end * end
            disc = math.sqrt(max(b * b - c, 0.0))
            pts.append((o + a_dir * (-b - disc), o + a_dir * (-b + disc)))
        (l0, r0), (l1, r1) = pts
        arc = []
        for p0, p1 in ((r0, r1), (l1, l0)):
            a0, a1 = math.atan2(p0[1], p0[0]), math.atan2(p1[1], p1[0])
            if a1 - a0 > math.pi:
                a1 -= TAU
            if a0 - a1 > math.pi:
                a1 += TAU
            steps = 5 if k in (0, count - 1) else 4
            arc += [(end * math.cos(a0 + (a1 - a0) * i / steps), end * math.sin(a0 + (a1 - a0) * i / steps)) for i in range(steps + 1)]
        outline = np.array(arc)
        planks.append(slab(outline, DECK_TOP - thick, DECK_TOP, 0.07, 2))
    deck = merge(*planks)

    beams, lashes = [], []
    for x in (-4.2, 0.0, 4.2):
        half = math.sqrt(6.15 ** 2 - x * x)
        beam = rounded_box(0.52, 0.38, 2 * half, 0.1, 3).translate(x, DECK_TOP - thick - 0.17, 0)
        beams.append(beam)
        for zs in (-1, 1):
            for dz in (-0.16, 0.16):
                loop = torus(0.36, 0.045, 12, 4).scale(1.0, 0.72, 1.0).rotate("x", 90).translate(x, DECK_TOP - thick - 0.15, zs * (half - 0.55) + dz)
                lashes.append(loop)

    barrels, hoops = [], []
    L, end_r, mid_r = 3.0, 0.68, 0.8
    seg = 16
    prof = [(0.0, 0.07), (0.6, 0.07), (0.63, 0.0), (end_r, 0.0)]
    for t in np.linspace(0.06, 0.94, 7):
        prof.append((end_r + (mid_r - end_r) * math.sin(math.pi * t), L * t))
    prof += [(end_r, L), (0.63, L), (0.6, L - 0.07), (0.0, L - 0.07)]
    base = lathe(prof, seg)
    ang = np.arctan2(base.v[:, 2], base.v[:, 0])
    rad = np.hypot(base.v[:, 0], base.v[:, 2])
    groove = np.where(np.isclose(np.mod(np.round(ang / (TAU / seg)), 2), 0), 0.022, 0.0) * (rad > 0.5)
    base.v[:, 0] *= (rad - groove) / np.maximum(rad, 1e-9)
    base.v[:, 2] *= (rad - groove) / np.maximum(rad, 1e-9)
    base.translate(0, -L / 2, 0).rotate("z", 90)  # axis along X, centered
    hoop_shapes = []
    for t in (0.14, 0.86):
        rb = end_r + (mid_r - end_r) * math.sin(math.pi * t) - 0.012
        band = lathe([(rb - 0.03, -0.08), (rb + 0.035, -0.08), (rb + 0.045, 0.0), (rb + 0.035, 0.08), (rb - 0.03, 0.08)], seg)
        hoop_shapes.append(band.translate(0, L * t - L / 2, 0).rotate("z", 90))
    band_shape = torus(mid_r + 0.01, 0.05, seg, 5).rotate("z", 90)  # rope round each barrel's belly
    ring_r, center_y = 5.3, mid_r + 0.055
    for k in range(8):
        phi = k * TAU / 8
        yaw = math.degrees(math.atan2(-math.cos(phi), -math.sin(phi)))
        pos = (ring_r * math.cos(phi), center_y, ring_r * math.sin(phi))
        barrels.append(base.copy().rotate("y", yaw).translate(*pos))
        for h in hoop_shapes:
            hoops.append(h.copy().rotate("y", yaw).translate(*pos))
        lashes.append(band_shape.copy().rotate("y", yaw).translate(*pos))

    # The rim rope: three strands twisting round each other (a lobed tube whose lobes turn).
    seg_n, sides = 180, 9
    verts = []
    for i in range(seg_n):
        a = TAU * i / seg_n
        for j in range(sides):
            b = TAU * j / sides
            twist = 3 * b - a * 3 * 26
            r = rope_minor * (1 + 0.09 * math.cos(twist))
            rr = rope_r + math.cos(b) * r
            verts.append((math.cos(a) * rr, rope_y + math.sin(b) * r, math.sin(a) * rr))
    faces = []
    for i in range(seg_n):
        for j in range(sides):
            a0 = i * sides + j
            b0 = i * sides + (j + 1) % sides
            c0 = ((i + 1) % seg_n) * sides + j
            d0 = ((i + 1) % seg_n) * sides + (j + 1) % sides
            faces += [(a0, b0, c0), (b0, d0, c0)]
    rope = orient_closed(Mesh(verts, faces))

    pieces = {
        "Deck": deck,
        "Beams": merge(*beams),
        "Barrels": merge(*barrels),
        "Hoops": merge(*hoops),
        "Rope": merge(rope, *lashes),
    }
    low = min(m.v[:, 1].min() for m in pieces.values())
    for key in ("Barrels", "Hoops"):
        pieces[key].translate(0, -low, 0)
    # The barrel belly bands are in Rope: lift them with the barrels (the rim rope stays put).
    rope_mesh = pieces["Rope"]
    under = rope_mesh.v[:, 1] < 1.2
    rope_mesh.v[under, 1] -= low
    return pieces


# =============================================================================== small pickups

FIN_EMBLEM = [(-0.44, -0.2), (0.38, -0.2), (0.26, -0.06), (0.17, 0.1), (0.14, 0.27), (0.2, 0.47), (0.08, 0.43),
              (-0.06, 0.32), (-0.2, 0.15), (-0.33, -0.04)]


def fin_badge(size: float, half: float) -> Mesh:
    """A raised shark-fin badge riding a little wave, in the XY plane (thickness along Z)."""
    outline = smooth_outline(np.array(FIN_EMBLEM) * size, 32)
    fin = pillow(outline, (0.0, 0.0), lambda p: np.full(len(p), half), rings=3, edge=half * 1.4)
    xs = np.linspace(-0.62, 0.62, 15) * size
    wave = [(x, -0.3 * size + 0.07 * size * math.sin(x / size * 10.5), 0.0) for x in xs]
    w = strip_tube(wave, [half * 1.25] * len(wave), 6)
    w.v[:, 2] *= 0.75
    return merge(fin, w)


def coin():
    """A gold coin standing up, facing -Z: a raised rim and a shark-fin-on-a-wave badge each side."""
    r, t = 1.0, 0.32
    rim = lathe([(0.8, -0.13), (0.86, -0.158), (0.95, -0.16), (0.995, -0.11), (1.0, 0.0), (0.995, 0.11), (0.95, 0.16),
                 (0.86, 0.158), (0.8, 0.13), (0.8, -0.13)], 40)
    face = lathe([(0.0, -0.125), (0.45, -0.122), (0.83, -0.11), (0.83, 0.11), (0.45, 0.122), (0.0, 0.125)], 40)
    badges = []
    for side in (-1, 1):
        b = fin_badge(1.05, 0.04)
        if side > 0:
            b.v[:, 0] *= -1  # the fin still sweeps back seen from either side
            b.f = b.f[:, ::-1].copy()
        badges.append(b.translate(0, 0.06, side * 0.122))
    pieces = {"Coin": face.rotate("x", 90), "Rim": merge(rim.rotate("x", 90), *badges)}
    for m in pieces.values():
        m.translate(0, r, 0)
    return pieces


def shell_half(length: float, spread: float, bulge: float, ribs: int, thick: float, rows: int = 12, cols: int = 41):
    """One scallop half in its own frame: hinge at the origin, opening towards -Z, the rim in the
    plane y = 0 and the shell bulging down (-Y). Returns (outer, inner) surfaces that share the rim."""
    th = np.linspace(-spread, spread, cols)
    rho = np.linspace(0, 1, rows + 1)[1:]
    outer, inner = [], []
    for p_ in rho:
        row_o, row_i = [], []
        for a in th:
            rib = 0.5 + 0.5 * math.cos(ribs * a * math.pi / spread)
            R = length * (1 + 0.05 * rib * p_) * (1 - 0.08 * (abs(a) / spread) ** 3)
            d = np.array([math.sin(a), 0.0, -math.cos(a)])
            dome = math.sin(math.pi * min(1.0, p_ ** 0.75)) * (1 - 0.35 * (abs(a) / spread) ** 2)
            y_o = -bulge * dome - 0.07 * rib * p_ ** 0.6 * math.sin(math.pi * p_ ** 0.75)
            y_i = y_o + thick * math.sin(math.pi * min(1.0, p_ ** 0.75)) ** 0.5
            row_o.append(d * R * p_ + np.array([0, y_o, 0]))
            row_i.append(d * R * p_ * 0.985 + np.array([0, y_i, 0]))
        outer.append(row_o)
        inner.append(row_i)
    outer, inner = np.array(outer), np.array(inner)
    inner[-1] = outer[-1]  # the rim is shared
    return outer, inner


def grid_sheet(P, flip: bool = False) -> Mesh:
    """An open sheet over a (rows, cols, 3) grid, plus a fan from `apex` if given."""
    rows, cols = P.shape[:2]
    faces = ring_faces(rows, cols, closed=False)
    m = Mesh(P.reshape(-1, 3), faces)
    if flip:
        m.f = m.f[:, ::-1].copy()
    return m


def shell_mesh(length, spread, bulge, ribs, thick):
    """A closed scallop half: (outer surface + hinge fan) and (inner surface + hinge fan), wound so
    together they face out. Returns (outer, inner) meshes in the half's own frame."""
    outer, inner = shell_half(length, spread, bulge, ribs, thick)
    cols = outer.shape[1]
    # Close each sheet at the hinge with a strip to the hinge point (the origin).
    def with_hinge(P):
        apex = np.zeros((1, cols, 3))
        return np.vstack([apex + np.array([0, 0, 0.0]), P])
    o = grid_sheet(with_hinge(outer))
    i = grid_sheet(with_hinge(inner), flip=True)
    # Side edges (the two straight sides of the fan): join outer and inner along the first and last
    # columns so the half is closed.
    both = merge(o, i)
    rows = outer.shape[0] + 1
    n = rows * cols
    faces = []
    for col, flip in ((0, False), (cols - 1, True)):
        for r in range(rows - 1):
            a, b = r * cols + col, (r + 1) * cols + col
            c, d = n + r * cols + col, n + (r + 1) * cols + col
            f = [(a, b, c), (b, d, c)]
            faces += [tuple(reversed(t)) for t in f] if flip else f
    closed = Mesh(both.v, np.vstack([both.f, np.array(faces)]))
    closed = weld(closed, 1e-6)
    tri = closed.v[closed.f]
    vol = np.einsum("ij,ij->i", tri[:, 0], np.cross(tri[:, 1], tri[:, 2])).sum()
    outer_m, inner_m = o, i
    if vol < 0:
        outer_m.f = outer_m.f[:, ::-1].copy()
        inner_m.f = inner_m.f[:, ::-1].copy()
        sides = Mesh(both.v, np.array(faces)[:, ::-1])
    else:
        sides = Mesh(both.v, np.array(faces))
    return outer_m, inner_m, sides


def pearl_clam():
    """An open scallop shell (hinge at the back, +Z; the top half open 70 degrees) with a big pearl."""
    length, spread, bulge = 1.24, math.radians(75), 0.36
    hinge = np.array([0.0, 0.4, 0.64])
    pieces_o, pieces_i = [], []
    for upper in (False, True):
        o, i, sides = shell_mesh(length, spread, bulge, 7, 0.07)
        outer = merge(o, sides)
        for m in (outer, i):
            if upper:
                m.v[:, 1] *= -1
                m.f = m.f[:, ::-1].copy()
                m.rotate("x", 70)
            m.translate(*hinge)
        pieces_o.append(outer)
        pieces_i.append(i)
    # The hinge: a rounded knuckle tucked behind both halves.
    knuckle = capsule(0.5, 0.1, 12).rotate("z", 90).translate(hinge[0], hinge[1] - 0.03, hinge[2] + 0.02)
    pearl = sphere(0.4, 16, 24)
    shell = merge(*pieces_o, knuckle)
    pieces = {"Shell": shell, "ShellInside": merge(*pieces_i), "Pearl": pearl}
    # Seat the pearl on the lower half's inside, a little forward of the middle.
    inner = pieces_i[0]
    near = inner.v[np.argmin(np.hypot(inner.v[:, 0], inner.v[:, 2] - (hinge[2] - 0.66)))]
    pearl.translate(0, near[1] + 0.4 - 0.03, hinge[2] - 0.66)
    low = min(m.v[:, 1].min() for m in pieces.values())
    for m in pieces.values():
        m.translate(0, -low, 0)
    return pieces


def d_shape(radius: float, segs: int = 14):
    """A half disc (flat side down) in the plane, (x, z) points, counter-clockwise."""
    return np.array([(radius * math.cos(a), radius * math.sin(a)) for a in np.linspace(0, math.pi, segs)])


def chest():
    """A little treasure chest, lid propped open on a heap of gold, trimmed in gold bands, a padlock on
    the front (-Z) and a few coins spilled in front of it."""
    W, D, H = 2.5, 1.62, 1.18  # body width (X), depth (Z), height
    R = D / 2  # the lid's dome radius
    wood, trim, gold, lock = [], [], [], []
    # Body: three boards high on each side over a solid core (the grooves read as planks).
    wood.append(rounded_box(W - 0.06, H - 0.04, D - 0.06, 0.05, 2).translate(0, H / 2, 0))
    for k in range(3):
        y0 = k * H / 3
        board = rounded_box(W, H / 3 - 0.035, D, 0.07, 2).translate(0, y0 + H / 6, 0)
        wood.append(board)
    # Trim: corner posts, a band round the top and the bottom, corner caps.
    for sx in (-1, 1):
        for sz in (-1, 1):
            trim.append(rounded_box(0.16, H, 0.16, 0.05, 2).translate(sx * (W / 2 - 0.02), H / 2, sz * (D / 2 - 0.02)))
    for y in (0.08, H - 0.08):
        trim.append(rounded_box(W + 0.08, 0.13, D + 0.08, 0.05, 2).translate(0, y, 0))
    # The lid: a domed half drum along X with two gold straps and a gold front lip; hinged at the back
    # top edge and propped open.
    lid_core = slab(np.array([(z, y) for z, y in d_shape(R, 16)]), -W / 2 + 0.02, W / 2 - 0.02, 0.06, 2, bottom_round=True)
    lid_core.v = lid_core.v[:, [1, 2, 0]]  # (z, y, x) -> axis along X
    lid_core.v[:, [0, 1, 2]] = lid_core.v[:, [0, 1, 2]]
    lid_core = orient_closed(lid_core)
    lid_parts_wood = [lid_core]
    lid_parts_trim = []
    for x in (-W / 2 + 0.38, W / 2 - 0.38):
        strap = lathe([(R - 0.02, -0.09), (R + 0.045, -0.09), (R + 0.06, 0.0), (R + 0.045, 0.09), (R - 0.02, 0.09), (R - 0.02, -0.09)], 28)
        strap.rotate("z", 90).translate(x, 0, 0)
        keep = strap.v[:, 1] >= -0.001  # only the top half of the ring
        lid_parts_trim.append(strap)
    lip = rounded_box(W + 0.04, 0.12, 0.12, 0.04, 2).translate(0, 0.04, -R + 0.04)
    back_lip = rounded_box(W + 0.04, 0.12, 0.12, 0.04, 2).translate(0, 0.04, R - 0.04)
    lid_parts_trim += [lip, back_lip]
    hasp = rounded_box(0.3, 0.42, 0.06, 0.03, 2).translate(0, -0.12, -R - 0.02)
    lid_lock = [hasp]
    lid = {"Wood": merge(*lid_parts_wood), "Trim": merge(*lid_parts_trim), "Lock": merge(*lid_lock)}
    # Clip the straps' lower halves away (they'd hang below the lid's flat underside).
    for key in ("Trim",):
        m = lid[key]
        tri = m.v[m.f]
        low = tri[:, :, 1].max(axis=1) < -0.02
        keepf = ~low | (np.abs(tri[:, :, 2]).max(axis=1) > R + 0.0) & False
        m.f = m.f[keepf]
    # Gold: a heap that bulges out of the open top, coins on it and spilling over the front.
    rnd = np.random.default_rng(5)
    heap = lathe([(0.0, 0.0), (1.0, 0.0), (0.98, 0.25), (0.78, 0.45), (0.45, 0.6), (0.0, 0.66)], 24)
    heap.scale(W / 2 - 0.12, 1.0, D / 2 - 0.12)
    heap.v[:, 1] += 0.05 * np.sin(heap.v[:, 0] * 7) * np.sin(heap.v[:, 2] * 9) * (heap.v[:, 1] > 0.1)
    gold.append(heap.translate(0, H - 0.3, 0))
    coin_shape = lathe([(0.0, 0.0), (0.15, 0.0), (0.17, 0.012), (0.17, 0.033), (0.15, 0.045), (0.0, 0.045)], 10)
    for k in range(34):
        x, z = rnd.uniform(-W / 2 + 0.3, W / 2 - 0.3), rnd.uniform(-D / 2 + 0.25, D / 2 - 0.3)
        u = math.hypot(x / (W / 2 - 0.12), z / (D / 2 - 0.12))
        y = H - 0.3 + 0.66 * max(0.0, 1 - u * u) - 0.03
        c = coin_shape.copy().rotate("x", rnd.uniform(-35, 35)).rotate("z", rnd.uniform(-35, 35)).rotate("y", rnd.uniform(0, 180))
        gold.append(c.translate(x, y, z))
    # A string of coins tumbling over the front edge and three on the ground.
    for k, (x, y, z, rx) in enumerate(((-0.55, H + 0.02, -D / 2 - 0.02, -60), (-0.35, H - 0.2, -D / 2 - 0.1, -80),
                                       (0.6, H + 0.03, -D / 2 - 0.03, -55))):
        gold.append(coin_shape.copy().rotate("x", rx).rotate("y", 15 * k).translate(x, y, z))
    for x, z, ry in ((-0.92, -1.02, 20), (-0.55, -1.12, 70), (0.85, -1.05, 130)):
        gold.append(coin_shape.copy().rotate("y", ry).translate(x, 0.0, z))
    gold.append(coin_shape.copy().rotate("x", -78).rotate("y", -20).translate(-0.72, 0.19, -1.0))
    # Padlock on the front.
    plate = rounded_box(0.42, 0.5, 0.08, 0.04, 2).translate(0, H - 0.32, -D / 2 - 0.04)
    body = rounded_box(0.36, 0.34, 0.16, 0.08, 3).translate(0, H - 0.52, -D / 2 - 0.13)
    shackle = torus(0.11, 0.035, 14, 6).rotate("x", 90).translate(0, H - 0.34, -D / 2 - 0.13)
    keyhole = cylinder(0.035, 0.03, 8).rotate("x", 90).translate(0, H - 0.52, -D / 2 - 0.2)
    lock += [plate, body, shackle]

    pieces = {"Wood": merge(*wood), "Trim": merge(*trim), "Gold": merge(*gold), "Lock": merge(*lock)}
    # Prop the lid open about its back edge so the whole chest is exactly 2.4 tall.
    hinge = np.array([0.0, H, R])

    def opened(angle):
        out = {}
        for key, m in lid.items():
            mm = m.copy().translate(0, 0, 0)
            mm.translate(0, H, 0)
            rotate_about(mm, "x", angle, hinge)
            out[key] = mm
        return out

    lo_a, hi_a = 0.0, 60.0
    for _ in range(40):
        mid = (lo_a + hi_a) / 2
        top = max(m.v[:, 1].max() for m in opened(mid).values())
        if top > 2.4:
            hi_a = mid
        else:
            lo_a = mid
    for key, m in opened(lo_a).items():
        pieces[key] = merge(pieces[key], m)
    return pieces


def torus_e(R: float, rx: float, ry: float, segments: int, sides: int, a0: float = 0.0, a1: float = TAU, closed: bool = True) -> Mesh:
    """A torus with an elliptical tube (rx across, ry up) over the arc a0..a1; capped if partial."""
    full = closed and abs(a1 - a0 - TAU) < 1e-9
    n = segments if full else segments + 1
    rings = []
    for i in range(n):
        a = a0 + (a1 - a0) * i / segments
        ring = [((R + math.cos(b) * rx) * math.cos(a), math.sin(b) * ry, (R + math.cos(b) * rx) * math.sin(a))
                for b in np.linspace(0, TAU, sides, endpoint=False)]
        rings.append(ring)
    rings = np.array(rings)
    if full:
        faces = []
        for i in range(n):
            for j in range(sides):
                p0 = i * sides + j
                p1 = i * sides + (j + 1) % sides
                p2 = ((i + 1) % n) * sides + j
                p3 = ((i + 1) % n) * sides + (j + 1) % sides
                faces += [(p0, p1, p2), (p1, p3, p2)]
        return orient_closed(Mesh(rings.reshape(-1, 3), faces))
    starts = [np.array([R * math.cos(a), 0.0, R * math.sin(a)]) for a in (a0, a1)]
    return loft(rings, start=starts[0], end=starts[1])


def floatie():
    """An inflatable swim ring: orange with four white stripes (a hair proud) and a little valve."""
    R, rx, ry = 1.4, 0.4, 0.484
    ring = torus_e(R, rx, ry, 56, 20).translate(0, 0.5, 0)
    stripes = []
    for k in range(4):
        a = k * TAU / 4 + math.radians(45)
        stripes.append(torus_e(R, rx + 0.016, ry + 0.016, 8, 20, a - math.radians(11), a + math.radians(11), closed=False).translate(0, 0.5, 0))
    # The valve on the upper outer shoulder, between two stripes.
    b = math.radians(38)
    n = np.array([math.cos(b) / rx, math.sin(b) / ry, 0.0])
    n /= np.linalg.norm(n)
    base = np.array([R + math.cos(b) * rx, 0.5 + math.sin(b) * ry, 0.0])
    valve = merge(cylinder(0.11, 0.05, 16, 0.02), cylinder(0.05, 0.07, 10).translate(0, 0.04, 0),
                  cylinder(0.065, 0.035, 12, 0.012).translate(0, 0.1, 0))
    ang = math.degrees(math.atan2(n[0], n[1]))
    valve.translate(0, -0.02, 0).rotate("z", -ang).translate(*base)
    valve.rotate("y", -45 + 22)  # between two stripes, round to the front-right
    pieces = {"Ring": merge(ring, valve), "Stripes": merge(*stripes)}
    return pieces


# =============================================================================== arena edge and markers

def split_faces(mesh: Mesh, mask) -> tuple:
    """Two meshes from one: the faces where mask is True, and the rest."""
    out = []
    for keep in (mask, ~mask):
        faces = mesh.f[keep]
        used, inverse = np.unique(faces.reshape(-1), return_inverse=True)
        out.append(Mesh(mesh.v[used], inverse.reshape(-1, 3), mesh.smooth))
    return out[0], out[1]


def split_level(mesh: Mesh, values, level: float) -> tuple:
    """Cuts a mesh exactly along the contour values == level (values per vertex), returning the
    (above, below) meshes. Cut edges share their new vertices, so each side stays watertight
    along the cut."""
    v = list(map(tuple, mesh.v))
    val = list(np.asarray(values, float) - level)
    cache = {}

    def cut(i, j):
        key = (min(i, j), max(i, j))
        if key not in cache:
            t = val[i] / (val[i] - val[j])
            p = np.array(v[i]) + (np.array(v[j]) - np.array(v[i])) * t
            v.append(tuple(p))
            val.append(0.0)
            cache[key] = len(v) - 1
        return cache[key]

    above, below = [], []
    for f in mesh.f:
        a, b, c = (int(x) for x in f)
        sa, sb, sc = val[a] >= 0, val[b] >= 0, val[c] >= 0
        if sa == sb == sc:
            (above if sa else below).append((a, b, c))
            continue
        # rotate so that `a` is the odd one out
        if sb != sa and sb != sc:
            a, b, c = b, c, a
        elif sc != sa and sc != sb:
            a, b, c = c, a, b
        ab, ac = cut(a, b), cut(a, c)
        lone, pair = (above, below) if val[a] >= 0 else (below, above)
        lone.append((a, ab, ac))
        pair.append((ab, b, c))
        pair.append((ab, c, ac))
    verts = np.array(v)
    out = []
    for faces in (above, below):
        faces = np.array(faces, dtype=np.int64).reshape(-1, 3)
        used, inverse = np.unique(faces.reshape(-1), return_inverse=True)
        out.append(Mesh(verts[used], inverse.reshape(-1, 3), mesh.smooth))
    return out[0], out[1]


def float_line():
    """The arena's edge: 70 lozenge floats, alternating yellow and red, threaded on a rope round a
    circle of radius 44 about the origin. Water line at y = 0.55 (the floats ride half out)."""
    radius, count, L, r = 44.0, 70, 2.2, 0.565
    prof = [(0.0, 0.0), (0.12, 0.02)]
    for t in np.linspace(0.08, 0.92, 5):
        bump = 0.035 if abs(t - 0.5) < 0.12 else 0.0
        prof.append((r * math.sin(math.pi * t) ** 0.55 + bump, L * t))
    prof += [(0.12, L - 0.02), (0.0, L)]
    shape = lathe(prof, 10).translate(0, -L / 2, 0).rotate("z", 90)  # axis along X, centered
    floats = {"FloatsA": [], "FloatsB": []}
    for k in range(count):
        a = k * TAU / count
        f = shape.copy().rotate("y", -math.degrees(a) - 90).translate(radius * math.cos(a), 0.6, radius * math.sin(a))
        floats["FloatsA" if k % 2 == 0 else "FloatsB"].append(f)
    rope = torus(radius, 0.07, 220, 4).translate(0, 0.6, 0)
    return {"FloatsA": merge(*floats["FloatsA"]), "FloatsB": merge(*floats["FloatsB"]), "Rope": rope}


def wave_cloth(mesh: Mesh, x0: float, amount: float, freq: float, grow: float) -> Mesh:
    """Ripples a cloth made in the XY plane along Z, more towards its free end (x > x0)."""
    d = np.clip(mesh.v[:, 0] - x0, 0, None)
    mesh.v[:, 2] += amount * np.sin(d * freq) * np.minimum(1.0, d / grow)
    return mesh


def pennant_with_fin(length: float, height: float, half: float, fin_size: float, x0: float = 0.0):
    """A swallow-less pennant along +X from its hoist at x = x0 (centered on y = 0), with a black fin on
    both faces. Returns (cloth, marks), both rippled the same way."""
    outline = smooth_outline([(0.0, -height / 2), (length * 0.55, -height * 0.25), (length, -height * 0.04), (length, height * 0.04),
                              (length * 0.55, height * 0.25), (0.0, height / 2)], 40, 1)
    cloth = pillow(outline, (length * 0.3, 0.0), lambda p: np.full(len(p), half), rings=3, edge=half * 1.2)
    marks = []
    for side in (-1, 1):
        fin = pillow(smooth_outline(np.array(FIN_EMBLEM) * fin_size, 28), (0.0, 0.0), lambda p: np.full(len(p), half * 0.6),
                     rings=2, edge=half)
        if side < 0:
            fin.v[:, 0] *= -1
            fin.f = fin.f[:, ::-1].copy()
        fin.translate(length * 0.32, -0.02 * fin_size, side * (half + half * 0.35))
        if side > 0:
            pass
        marks.append(fin)
    marks = merge(*marks)
    for m in (cloth, marks):
        m.translate(x0, 0, 0)
        wave_cloth(m, x0, 0.07 * length, 5.0 / length, length * 0.4)
    return cloth, marks


def buoy():
    """A warning buoy: a red float with a white band riding at y = 1.2, a metal cage tower with a
    glowing lamp and a little yellow pennant with a black shark fin on top (y = 7)."""
    prof = [(0.0, 0.0), (0.6, 0.02), (1.05, 0.22), (1.32, 0.6), (1.45, 1.0), (1.48, 1.3), (1.48, 1.55), (1.48, 1.95),
            (1.46, 2.15), (1.3, 2.42), (0.95, 2.6), (0.5, 2.68), (0.0, 2.7)]
    body = lathe(prof, 36)
    c = body.v[body.f].mean(axis=1)
    stripe, red = split_faces(body, (c[:, 1] > 1.55) & (c[:, 1] < 1.95))
    fender = torus(1.5, 0.12, 36, 8).scale(1, 1.2, 1).translate(0, 1.3, 0)
    cage = []
    top_y, deck_y = 2.62, 5.15
    for k in range(4):
        a = k * TAU / 4 + math.pi / 4
        p0 = (0.78 * math.cos(a), top_y, 0.78 * math.sin(a))
        p1 = (0.36 * math.cos(a), deck_y, 0.36 * math.sin(a))
        cage.append(strip_tube([p0, p1], [0.075, 0.065], 8))
        b = a + TAU / 4
        for y0, y1, r0, r1 in ((top_y + 0.2, 3.95, 0.74, 0.52), (3.95, deck_y - 0.1, 0.52, 0.38)):
            q0 = (r0 * math.cos(a), y0, r0 * math.sin(a))
            q1 = (r1 * math.cos(b), y1, r1 * math.sin(b))
            cage.append(strip_tube([q0, q1], [0.04, 0.04], 6))
    for y, rr in ((3.95, 0.57), (deck_y - 0.05, 0.4)):
        cage.append(torus(rr, 0.05, 24, 6).translate(0, y, 0))
    cage.append(cylinder(0.85, 0.14, 24, 0.04).translate(0, top_y - 0.06, 0))
    cage.append(cylinder(0.55, 0.12, 24, 0.04).translate(0, deck_y, 0))
    lamp = lathe([(0.0, deck_y + 0.12), (0.3, deck_y + 0.12), (0.34, deck_y + 0.3), (0.34, deck_y + 0.7), (0.26, deck_y + 0.84),
                  (0.0, deck_y + 0.86)], 18)
    for k in range(4):  # the lamp's guard bars
        a = k * TAU / 4
        cage.append(strip_tube([(0.4 * math.cos(a), deck_y + 0.1, 0.4 * math.sin(a)), (0.4 * math.cos(a), deck_y + 0.86, 0.4 * math.sin(a))], [0.03, 0.03], 6))
    cage.append(lathe([(0.0, deck_y + 0.84), (0.46, deck_y + 0.84), (0.42, deck_y + 0.95), (0.18, deck_y + 1.08), (0.0, deck_y + 1.1)], 18))
    pole_top = 7.0
    cage.append(strip_tube([(0, deck_y + 1.05, 0), (0, pole_top - 0.08, 0)], [0.035, 0.03], 8))
    cage.append(sphere(0.08, 6, 10).translate(0, pole_top - 0.08, 0))
    flag, mark = pennant_with_fin(1.15, 0.62, 0.025, 0.55)
    for m in (flag, mark):
        m.translate(0.04, pole_top - 0.42, 0).rotate("y", 150)
    return {"Float": merge(red, fender), "Stripe": stripe, "Cage": merge(*cage), "Lamp": lamp, "Flag": flag, "FlagMark": mark}


def gull():
    """A seagull gliding on spread, gently bent wings, facing -Z, about 4.2 across."""
    body = loft([np.column_stack([rx * np.sin(np.linspace(0, TAU, 16, endpoint=False)), y + ry * np.cos(np.linspace(0, TAU, 16, endpoint=False)),
                                  np.full(16, z)])
                 for z, rx, ry, y in ((-0.5, 0.17, 0.18, 0.4), (-0.36, 0.23, 0.25, 0.37), (-0.1, 0.29, 0.29, 0.33), (0.2, 0.27, 0.27, 0.33),
                                      (0.5, 0.18, 0.17, 0.38), (0.72, 0.09, 0.07, 0.43))],
                start=(0, 0.42, -0.58), end=(0, 0.45, 0.82))
    head = sphere(0.23, 10, 14).scale(1.0, 0.95, 1.1).translate(0, 0.5, -0.6)
    tail = pillow(smooth_outline([(-0.28, 0.0), (0.28, 0.0), (0.3, 0.38), (0.0, 0.32), (-0.3, 0.38)], 24), (0.0, 0.18),
                  lambda p: np.full(len(p), 0.035), rings=3, edge=0.04)
    tail = place(tail, (0, 0.44, 0.55), (1, 0, 0), (0, 0.05, 1), (0, 1, -0.05))
    wing_pts = [(0.1, -0.28), (0.6, -0.33), (0.95, -0.3), (1.4, -0.13), (1.8, 0.04), (2.1, 0.22), (1.95, 0.32), (1.6, 0.35),
                (1.2, 0.4), (0.9, 0.46), (0.5, 0.42), (0.1, 0.3)]
    wing_out = smooth_outline(wing_pts, 44)
    wings, tips = [], []
    for side in (1, -1):
        w = pillow(wing_out, (0.7, 0.05), lambda p: 0.06 - 0.035 * np.clip(p[:, 0] / 2.1, 0, 1), rings=4, edge=0.05)
        w = place(w, (0, 0, 0), (1, 0, 0), (0, 0, 1), (0, 1, 0))  # (x, chord) -> (x, z), thickness -> y
        x = w.v[:, 0]
        w.v[:, 1] += 0.44 + np.interp(x, [0.0, 0.95, 2.1], [0.0, 0.44, 0.2]) - 0.05 * np.interp(x, [0.0, 0.95, 2.1], [0, 0, 1]) * 0
        w.v[:, 2] += 0.02
        tip_mask = w.v[w.f][:, :, 0].mean(axis=1) > 1.62
        tip, wing = split_faces(w, tip_mask)
        for m in (tip, wing):
            if side < 0:
                m.v[:, 0] *= -1
                m.f = m.f[:, ::-1].copy()
        wings.append(wing)
        tips.append(tip)
    beak = taper([(0, 0.47, -0.78), (0, 0.45, -0.95), (0, 0.41, -1.07)], 0.075, 0.02, 8)
    hook = taper([(0, 0.42, -1.04), (0, 0.38, -1.09)], 0.03, 0.01, 6)
    feet = []
    for side in (-1, 1):
        foot = pillow(smooth_outline([(0.0, 0.0), (0.12, 0.2), (0.0, 0.26), (-0.12, 0.2)], 16), (0.0, 0.12),
                      lambda p: np.full(len(p), 0.02), rings=2, edge=0.02)
        feet.append(place(foot, (side * 0.09, 0.1, 0.3), (1, 0, 0), (0, -0.25, 1), (0, 1, 0.25)))
    eyes = [sphere(0.045, 6, 8).translate(side * 0.19, 0.57, -0.7) for side in (-1, 1)]
    pieces = {"Body": merge(body, head, tail), "Wings": merge(*wings), "WingTips": merge(*tips), "Beak": merge(beak, hook, *feet),
              "Eyes": merge(*eyes)}
    low = min(m.v[:, 1].min() for m in pieces.values())
    for m in pieces.values():
        m.translate(0, -low, 0)
    top = max(m.v[:, 1].max() for m in pieces.values())
    for m in pieces.values():
        m.v[:, 1] *= 1.0 / top  # exactly 1.0 tall
    return pieces


# =============================================================================== the reef

def wobble(points, seed: int, amount: float, scale: float = 1.0):
    """Smooth pseudo-noise (a sum of a few random waves) at points (n, 3)."""
    rng = np.random.default_rng(seed)
    out = np.zeros(len(points))
    for _ in range(6):
        d = unit(rng.normal(size=3))
        out += np.sin(points @ d * rng.uniform(1.5, 3.5) / scale + rng.uniform(0, TAU)) * rng.uniform(0.4, 1.0)
    return out / 4.0 * amount


def lumpy(radius: float, squash, seed: int, amount: float = 0.25, subdiv: int = 2) -> Mesh:
    m = weld(icosphere(1.0, subdiv))
    m.v = m.v * (1 + wobble(m.v, seed, amount))[:, None]
    return m.scale(radius * squash[0], radius * squash[1], radius * squash[2])


def branch(points, r0: float, r1: float, sides: int = 7) -> Mesh:
    """A tapered tube with a rounded tip."""
    pts = [tuple(p) for p in points]
    tube_ = taper(pts, r0, r1 * 0.6, sides)
    tip = sphere(r1, 4, sides).translate(*pts[-1])
    return merge(tube_, tip)


def antler(rng, base, direction, length, radius, depth, out):
    """Staghorn coral: a gently curving branch that forks."""
    pts = [np.asarray(base, float)]
    d = unit(direction)
    steps = 4
    for k in range(steps):
        d = unit(d + rng.normal(size=3) * 0.12 + np.array([0, 0.18, 0]))
        pts.append(pts[-1] + d * length / steps)
    out.append(branch(pts, radius, radius * 0.72, 7))
    if depth > 0:
        forks = 2 if depth > 1 else rng.integers(1, 3)
        for k in range(forks):
            side = unit(np.cross(d, rng.normal(size=3)))
            nd = unit(d * 0.8 + side * rng.uniform(0.45, 0.75))
            antler(rng, pts[-1], nd, length * rng.uniform(0.62, 0.78), radius * 0.74, depth - 1, out)


def brain_coral(radius: float, seed: int) -> Mesh:
    m = weld(icosphere(1.0, 3))
    v = m.v
    warp = np.sin(v[:, 0] * 5.0 + 1.3) * 0.6 + np.sin(v[:, 2] * 4.0) * 0.5
    ridge = np.sin(v[:, 0] * 11 + v[:, 2] * 7 + warp * 3.0) * np.sin(v[:, 2] * 9 - v[:, 1] * 5 + warp * 2.0)
    m.v = v * (1 + 0.045 * np.sign(ridge) * np.abs(ridge) ** 0.5 + wobble(v, seed, 0.12))[:, None]
    m.v[:, 1] = np.maximum(m.v[:, 1], -0.2)  # flat bottom (sits on the rock)
    return m.scale(radius, radius * 0.72, radius)


def sea_fan(width: float, height: float, seed: int) -> Mesh:
    """A gorgonian sea fan: a net of thin branches in the XY plane, rising from a short stalk."""
    rng = np.random.default_rng(seed)
    tubes = []
    spokes = 9
    tips = []
    for k in range(spokes):
        a = math.radians(-62 + 124 * k / (spokes - 1))
        pts = [np.array([0.0, 0.25, 0.0])]
        for t in np.linspace(0.2, 1.0, 5):
            r = height * t * (0.95 + 0.08 * math.sin(k * 2.1))
            pts.append(np.array([math.sin(a) * r * width / height * 0.62, 0.25 + math.cos(a) * r, rng.uniform(-0.04, 0.04)]))
        tips.append(pts)
        tubes.append(strip_tube([tuple(p) for p in pts], np.linspace(0.085, 0.04, len(pts)), 6))
    for level in (2, 3, 4, 5):  # cross links: wavy arcs joining neighbouring spokes
        for k in range(spokes - 1):
            p0, p1 = tips[k][level], tips[k + 1][level]
            mid = (p0 + p1) / 2 + np.array([0, 0.08 * (1 if (k + level) % 2 else -1), 0])
            tubes.append(strip_tube([tuple(p0), tuple(mid), tuple(p1)], [0.035, 0.04, 0.035], 5))
    tubes.append(strip_tube([(0, 0.0, 0), (0, 0.35, 0)], [0.13, 0.09], 8))
    return merge(*tubes)


def coral():
    """A lush coral head on a low rock: a bushy pink staghorn, a big orange brain coral, a clump of
    purple finger coral, orange cups and a red sea fan."""
    rng = np.random.default_rng(8)
    rock = merge(lumpy(1.0, (3.3, 0.85, 2.5), 3, 0.3).translate(0, 0.4, 0),
                 lumpy(1.0, (1.4, 0.65, 1.2), 4, 0.3).translate(2.5, 0.32, 0.9),
                 lumpy(1.0, (1.3, 0.7, 1.1), 5, 0.3).translate(-2.6, 0.35, -0.5))
    rock.smooth = False
    stag = []
    trunks = ((-0.3, 0.6, (0.0, 1, 0.15)), (0.55, 0.4, (0.35, 1, 0.0)), (-1.1, 0.8, (-0.45, 1, 0.2)),
              (0.2, 1.2, (0.1, 1, 0.45)), (-0.6, -0.1, (-0.2, 1, -0.3)))
    for k, (x, z, lean) in enumerate(trunks):
        antler(rng, (x, 0.95, z), lean, 1.55 - 0.12 * k, 0.3, 3, stag)
    brain = brain_coral(1.55, 6).translate(-1.75, 1.0, -0.95)
    fingers = []
    for k in range(15):
        a = k * 2.4
        r = 0.75 * math.sqrt(k / 15)
        x, z = 1.75 + math.cos(a) * r, -0.85 + math.sin(a) * r
        h = 1.0 + 0.7 * math.sin(k * 1.7) ** 2
        fingers.append(branch([(x, 0.6, z), (x + 0.06 * math.cos(a), 0.6 + h * 0.5, z + 0.06 * math.sin(a)),
                               (x + 0.16 * math.cos(a), 0.6 + h, z + 0.16 * math.sin(a))], 0.22, 0.19, 8))
    cups = []
    for k, (x, z) in enumerate(((2.6, 0.2), (-2.8, 0.6), (0.9, -1.7), (-0.4, -1.9), (3.0, -0.9), (-2.2, -1.6))):
        cup = lathe([(0.0, 0.0), (0.22, 0.0), (0.3, 0.2), (0.34, 0.32), (0.26, 0.34), (0.2, 0.18), (0.0, 0.16)], 12)
        cups.append(cup.scale(1.0 + 0.2 * (k % 3)).translate(x, 0.5 + 0.12 * (k % 2), z))
    fan = sea_fan(3.4, 3.6, 9).rotate("y", 25).translate(2.1, 0.6, 1.25)
    fan2 = sea_fan(2.2, 2.3, 11).rotate("y", -35).translate(-2.4, 0.6, 1.0)
    pieces = {"Rock": rock, "CoralA": merge(*stag), "CoralB": merge(brain, *cups), "CoralC": merge(*fingers), "Fan": merge(fan, fan2)}
    top = max(m.v[:, 1].max() for m in pieces.values())
    low = min(m.v[:, 1].min() for m in pieces.values())
    for m in pieces.values():
        m.translate(0, -low, 0).scale(6.0 / (top - low))
    return pieces


def ribbon(curve, widths, thick: float, ruffle: float, seed: int, sides: int = 8, twist: float = 0.0) -> Mesh:
    """A flat, ruffled frond along a 3D curve: a lens-shaped cross-section `widths` wide."""
    curve = np.asarray(curve, float)
    rng = np.random.default_rng(seed)
    rings = []
    n = len(curve)
    phase = rng.uniform(0, TAU)
    for i, p in enumerate(curve):
        t = curve[min(i + 1, n - 1)] - curve[max(i - 1, 0)]
        t = unit(t)
        side0 = unit(np.cross(t, np.array([0.3, 0.0, 1.0])))
        normal0 = np.cross(side0, t)
        tw = twist * i / max(1, n - 1) + phase * 0.3
        side = side0 * math.cos(tw) + normal0 * math.sin(tw)
        normal = np.cross(side, t)
        w = widths[i]
        ring = []
        half = sides // 2
        # Top and bottom each get their own copy of the two rim points, so their smooth normals
        # don't average into each other at the thin edge.
        angles = list(np.linspace(0, math.pi, half + 1)) + list(np.linspace(math.pi, TAU, half + 1))
        for a in angles:
            x = math.cos(a) * w / 2
            y = math.copysign(abs(math.sin(a)) ** 0.5, math.sin(a)) * thick / 2
            edge = float(smoothstep(0.2, 0.75, abs(math.cos(a))))  # the outer part waves as one
            y += ruffle * w * edge * math.sin(i * 1.3 + phase + (0 if math.cos(a) > 0 else 1.7))
            ring.append(p + side * x + normal * y)
        rings.append(ring)
    return loft(rings, start=curve[0] - unit(curve[1] - curve[0]) * 0.02, end=curve[-1] + unit(curve[-1] - curve[-2]) * 0.05)


def kelp():
    """A clump of giant kelp: five tall wavy fronds from a knobbly holdfast, gas bulbs along them."""
    rng = np.random.default_rng(14)
    fronds, bulbs = [], []
    holdfast = merge(*[lumpy(0.55, (1.0, 0.6, 1.0), 20 + k, 0.35, 1).translate(math.cos(k * 1.3) * 0.5, 0.25, math.sin(k * 1.3) * 0.5)
                       for k in range(5)])
    for k in range(6):
        a = k * TAU / 6 + rng.uniform(-0.3, 0.3)
        h = 12.0 - 0.75 * k
        base = np.array([math.cos(a) * 0.35, 0.3, math.sin(a) * 0.35])
        lean = np.array([math.cos(a), 0, math.sin(a)]) * (1.2 + 0.25 * (k % 2))
        ys = np.linspace(0, 1, 46)
        pts = []
        for t in ys:
            sway = np.array([math.sin(t * 4.2 + k) * 0.55, 0, math.cos(t * 3.4 + k * 1.7) * 0.55])
            pts.append(base + np.array([0, h * t, 0]) + lean * t ** 1.4 + sway * t)
        widths = 0.16 + 1.15 * np.sin(np.pi * np.clip(ys * 1.04, 0, 1)) ** 0.5
        widths[0] = 0.14
        fronds.append(ribbon(pts, widths, 0.15, 0.16, 30 + k, 8, twist=1.4 + 0.4 * k))
        for j in range(5, 42, 9):
            p = np.array(pts[j])
            off = np.array([math.cos(a + j), 0, math.sin(a + j)]) * (widths[j] * 0.45)
            bulbs.append(sphere(0.15 + 0.03 * (j % 3), 5, 7).scale(1, 1.3, 1).translate(*(p + off)))
    pieces = {"Kelp": merge(holdfast, *fronds), "Bulbs": merge(*bulbs)}
    top = max(m.v[:, 1].max() for m in pieces.values())
    low = min(m.v[:, 1].min() for m in pieces.values())
    for m in pieces.values():
        m.translate(0, -low, 0)
        m.v[:, 1] *= 12.0 / (top - low)
    return pieces


def starfish():
    """A chunky five-armed starfish lying flat, its back dotted with bumps."""
    outline = []
    for k in range(10 * 6):
        a = TAU * k / 60
        arm = (math.cos(5 * a) + 1) / 2
        r = 0.48 + 0.84 * arm ** 1.6
        outline.append((math.sin(a) * r, math.cos(a) * r))
    outline = np.array(outline)

    def h(p):
        d = np.hypot(p[:, 0], p[:, 1])
        return 0.3 - 0.17 * np.clip(d / 1.3, 0, 1)

    star = pillow(outline, (0.0, 0.0), h, rings=6, edge=0.16)
    star.v[star.v[:, 2] < 0, 2] *= 0.35  # flatter underneath
    star = place(star, (0, 0, 0), (1, 0, 0), (0, 0, -1), (0, 1, 0))
    star.translate(0, -star.v[:, 1].min(), 0)
    dots = []
    for k in range(5):
        a = TAU * k / 5
        for j, r in enumerate((0.42, 0.66, 0.88, 1.08)):
            for side in ((0.0,) if j in (0, 3) else (-1.0, 1.0)):
                aa = a + side * 0.13 / r * 1.4
                x, z = math.sin(aa) * r, -math.cos(aa) * r
                hit = raycast(star, (x, 2.0, z), (0, -1, 0))
                if hit:
                    size = 0.075 - 0.012 * j
                    dots.append(sphere(size, 5, 8).scale(1, 0.65, 1).translate(*(hit[0] - np.array([0, size * 0.2, 0]))))
    hit = raycast(star, (0, 2.0, 0), (0, -1, 0))
    dots.append(sphere(0.1, 6, 8).scale(1, 0.6, 1).translate(*hit[0]))
    pieces = {"Star": star, "Dots": merge(*dots)}
    top = max(m.v[:, 1].max() for m in pieces.values())
    for m in pieces.values():
        m.v[:, 1] *= 0.5 / top
    return pieces


def spiral_shell(length: float, radius: float, turns: float = 3.0) -> Mesh:
    """A little cone shell: a tube coiling round and up its axis (Y), getting smaller."""
    pts = []
    for t in np.linspace(0, 1, 26):
        a = TAU * turns * t
        r = radius * (1 - t) ** 1.1
        pts.append((math.cos(a) * r, length * t ** 0.9, math.sin(a) * r))
    radii = [radius * 0.85 * (1 - t) ** 1.1 + 0.02 for t in np.linspace(0, 1, 26)]
    return strip_tube(pts, radii, 8)


def sand_bar():
    """A low sand bar, 40 x 24, gently mounded with ripples, a darker band of wet sand round the
    water line (y = 2) and a few shells. The base (y = 0) is 2 below the water."""
    rx, rz, top = 20.0, 12.0, 3.0
    rings, segs = 26, 120
    rng = np.random.default_rng(3)
    ph = rng.uniform(0, TAU, 6)

    def height(r, a):
        x, z = math.cos(a) * r * rx, math.sin(a) * r * rz
        edge = 1 + 0.06 * math.sin(3 * a + ph[0]) + 0.04 * math.sin(7 * a + ph[1])
        rr = min(1.0, r / edge)
        mound = (1 - rr ** 2) ** 0.9
        bumps = 0.18 * math.sin(x * 0.35 + ph[2]) * math.sin(z * 0.5 + ph[3]) + 0.1 * math.sin(x * 0.9 + z * 0.4 + ph[4])
        ripple = 0.035 * math.sin(x * 2.2 + 0.6 * math.sin(z * 0.7)) * (rr < 0.8)
        return max(0.0, top * mound + (bumps + ripple) * mound)

    radii = [(i / rings) ** 0.8 for i in range(1, rings + 1)]
    verts = [(0.0, height(0, 0), 0.0)]
    for r in radii:
        for k in range(segs):
            a = TAU * k / segs
            edge = 1 + 0.06 * math.sin(3 * a + ph[0]) + 0.04 * math.sin(7 * a + ph[1])
            verts.append((math.cos(a) * r * rx * edge, height(r * edge, a), math.sin(a) * r * rz * edge))
    verts = np.array(verts)
    verts[-segs:, 1] = 0.0
    verts[:, 1] *= top / verts[:, 1].max()  # exactly 3 tall
    verts[:, 0] -= (verts[:, 0].max() + verts[:, 0].min()) / 2
    verts[:, 2] -= (verts[:, 2].max() + verts[:, 2].min()) / 2
    faces = [(0, 1 + (k + 1) % segs, 1 + k) for k in range(segs)]
    for i in range(rings - 1):
        a0, a1 = 1 + i * segs, 1 + (i + 1) * segs
        for k in range(segs):
            t = (k + 1) % segs
            faces += [(a0 + k, a0 + t, a1 + k), (a0 + t, a1 + t, a1 + k)]
    bottom = len(verts)
    verts = np.vstack([verts, [[0.0, 0.0, 0.0]]])
    rim = 1 + (rings - 1) * segs
    faces += [(bottom, rim + k, rim + (k + 1) % segs) for k in range(segs)]
    mesh = orient_closed(Mesh(verts, faces))
    dry, wet_part = split_level(mesh, mesh.v[:, 1] + 0.12 * np.sin(mesh.v[:, 0] * 0.6) * np.sin(mesh.v[:, 2] * 0.8), 2.3)
    shells = []
    placed = 0
    for k in range(60):
        if placed >= 9:
            break
        a = rng.uniform(0, TAU)
        r = rng.uniform(0.45, 0.85)
        x, z = math.cos(a) * r * rx, math.sin(a) * r * rz
        hit = raycast(mesh, (x, 10, z), (0, -1, 0))
        if not hit or not 2.05 < hit[0][1] < 2.55:  # washed up along the shore
            continue
        placed += 1
        p, n = hit
        if placed % 3 == 0:
            sh = spiral_shell(0.8, 0.32).rotate("z", 75).rotate("y", rng.uniform(0, 360))
            shells.append(sh.translate(*(p + np.array([0, 0.16, 0]))))
        else:
            fan = pillow(smooth_outline([(0, 0), (0.32, 0.3), (0.2, 0.48), (0, 0.52), (-0.2, 0.48), (-0.32, 0.3)], 24),
                         (0, 0.25), lambda q: 0.07 * (1 - np.clip(np.hypot(q[:, 0], q[:, 1] - 0.22) / 0.4, 0, 1)) + 0.02, rings=3, edge=0.04)
            fan = place(fan, (0, 0, 0), (1, 0, 0), (0, 0, -1), (0, 1, 0)).scale(1.9)
            shells.append(fan.rotate("y", rng.uniform(0, 360)).translate(*(p + np.array([0, 0.03, 0]))))
    return {"Sand": dry, "WetSand": wet_part, "Shells": merge(*shells)}


# =============================================================================== backdrop: the lifeguard hut

def bar_between(p0, p1, r: float, sides: int = 8) -> Mesh:
    return strip_tube([tuple(p0), tuple(p1)], [r, r], sides)


def box(x0, y0, z0, x1, y1, z1, r: float = 0.06, n: int = 2) -> Mesh:
    return rounded_box(abs(x1 - x0), abs(y1 - y0), abs(z1 - z0), r, n).translate((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)


def hip_roof(half_x: float, half_z: float, y0: float, thick: float, rise: float, ridge: float) -> Mesh:
    """A hip roof: a rectangular eave (with a fascia `thick` deep) rising to a ridge along X."""
    rings = []
    for hx, hz, y in ((half_x - 0.3, half_z - 0.3, y0), (half_x, half_z, y0), (half_x, half_z, y0 + thick)):
        rings.append([(hx, y, -hz), (hx, y, hz), (-hx, y, hz), (-hx, y, -hz)])
    for t in (0.35, 0.7, 0.92):
        hx = ridge + (half_x - ridge) * (1 - t) ** 1.15
        hz = half_z * (1 - t) ** 1.15 + 0.08
        rings.append([(hx, y0 + thick + rise * t, -hz), (hx, y0 + thick + rise * t, hz), (-hx, y0 + thick + rise * t, hz),
                      (-hx, y0 + thick + rise * t, -hz)])
    rings = [resample(np.array(r_), 24) for r_ in rings]
    return loft(rings, start=(0, y0, 0), end=(0, y0 + thick + rise, 0))


def lifebuoy(radius: float, tube_r: float, stripes: int = 4):
    ring = torus_e(radius, tube_r, tube_r, 40, 12)
    bands = []
    for k in range(stripes):
        a = k * TAU / stripes + TAU / (2 * stripes)
        bands.append(torus_e(radius, tube_r + 0.02, tube_r + 0.02, 6, 12, a - 0.22, a + 0.22, closed=False))
    rope = torus(radius + tube_r + 0.02, 0.035, 40, 5)
    return ring, merge(*bands), rope


def diamond_sign(size: float, depth: float) -> Mesh:
    """A yellow warning diamond (a square on its corner) with rounded corners, facing -Z."""
    h = size / 2
    pts = []
    for k in range(4):
        c = np.array([math.cos(k * math.pi / 2), math.sin(k * math.pi / 2)]) * (h - 0.25)
        for a in np.linspace(k * math.pi / 2 - math.pi / 4, k * math.pi / 2 + math.pi / 4, 5):
            pts.append(c + np.array([math.cos(a), math.sin(a)]) * 0.25)
    m = slab(np.array(pts), -depth / 2, depth / 2, min(0.08, depth / 3), 2, bottom_round=True)
    return m.rotate("x", 90)  # its faces now look along -Z / +Z


def hut():
    """A lifeguard tower on four splayed white stilts: a red cabin with a wide window and a white hip
    roof, a red flag on the roof, a ladder at the back, a lifebuoy on the rail and a big yellow
    shark-warning diamond on the front (-Z). It stands on its stilt feet at y = 0."""
    stilts, cabin, roof, ladder, sign, mark = [], [], [], [], [], []
    deck_y = 8.8
    feet = [(sx * 3.1, sz * 2.7) for sx in (-1, 1) for sz in (-1, 1)]
    tops = [(sx * 2.45, sz * 2.15) for sx in (-1, 1) for sz in (-1, 1)]
    for (fx, fz), (tx, tz) in zip(feet, tops):
        stilts.append(strip_tube([(fx, 0.25, fz), (tx, deck_y, tz)], [0.32, 0.26], 10))
        stilts.append(cylinder(0.48, 0.3, 12, 0.08).translate(fx, 0.0, fz))
    # X braces on all four sides, two storeys.
    def leg_at(i, y):
        (fx, fz), (tx, tz) = feet[i], tops[i]
        t = (y - 0.25) / (deck_y - 0.25)
        return np.array([fx + (tx - fx) * t, y, fz + (tz - fz) * t])
    sides_ = ((0, 1), (2, 3), (0, 2), (1, 3))
    for a, b in sides_:
        for y0, y1 in ((1.0, 4.6), (4.6, 8.2)):
            stilts.append(bar_between(leg_at(a, y0), leg_at(b, y1), 0.12))
            stilts.append(bar_between(leg_at(b, y0), leg_at(a, y1), 0.12))
        stilts.append(bar_between(leg_at(a, 4.6), leg_at(b, 4.6), 0.14))
    # The deck: planks over joists, a porch out front.
    for k in range(9):
        x0 = -3.2 + k * 0.712
        ladder.append(box(x0 + 0.03, deck_y, -3.6, x0 + 0.68, deck_y + 0.28, 2.9, 0.05))
    stilts.append(box(-3.3, deck_y - 0.4, -3.7, 3.3, deck_y, 3.0, 0.08))
    # Railing round the deck (open at the back for the ladder).
    rail_y = deck_y + 1.35
    corners = [(-3.15, -3.5), (3.15, -3.5), (3.15, 2.8), (-3.15, 2.8)]
    for x, z in corners + [(-1.05, -3.5), (1.05, -3.5), (-3.15, -0.35), (3.15, -0.35)]:
        stilts.append(box(x - 0.1, deck_y + 0.25, z - 0.1, x + 0.1, rail_y + 0.12, z + 0.1, 0.05))
    for (x0, z0), (x1, z1) in ((corners[0], corners[1]), (corners[1], corners[2]), (corners[3], corners[0])):
        for y in (rail_y, deck_y + 0.75):
            stilts.append(bar_between((x0, y, z0), (x1, y, z1), 0.085))
    # The cabin: red walls, a wide front window (dark panes in white frames), a side door.
    cy0, cy1 = deck_y + 0.28, deck_y + 4.0
    cabin.append(box(-2.4, cy0, -1.7, 2.4, cy1, 2.2, 0.08))
    for x0, x1 in ((-1.95, -0.05), (0.05, 1.95)):
        mark.append(box(x0, cy0 + 1.55, -1.76, x1, cy1 - 0.45, -1.68, 0.03))
    roof.append(box(-2.15, cy0 + 1.4, -1.85, 2.15, cy0 + 1.55, -1.62, 0.04))
    roof.append(box(-2.15, cy1 - 0.45, -1.85, 2.15, cy1 - 0.3, -1.62, 0.04))
    for x in (-2.07, 0.0, 2.07):
        roof.append(box(x - 0.08, cy0 + 1.4, -1.85, x + 0.08, cy1 - 0.3, -1.62, 0.03))
    wy0, wy1, wz0, wz1 = cy0 + 1.7, cy1 - 0.6, -0.9, 1.4  # a window in each side wall
    for sx in (-1, 1):
        mark.append(box(sx * 2.37, wy0, wz0, sx * 2.45, wy1, wz1, 0.03))
        for y0_, y1_, z0_, z1_ in ((wy0 - 0.15, wy0, wz0 - 0.15, wz1 + 0.15), (wy1, wy1 + 0.15, wz0 - 0.15, wz1 + 0.15),
                                   (wy0, wy1, wz0 - 0.15, wz0), (wy0, wy1, wz1, wz1 + 0.15), (wy0, wy1, 0.18, 0.32)):
            roof.append(box(sx * 2.38, y0_, z0_, sx * 2.52, y1_, z1_, 0.03))
    ladder.append(box(-0.75, cy0, 2.16, 0.75, cy0 + 2.9, 2.3, 0.04))  # back door
    # Roof and flag.
    roof.append(hip_roof(3.05, 2.85, cy1, 0.32, 1.9, 0.6).translate(0, 0, 0.25))
    roof_top = cy1 + 0.32 + 1.9
    pole_top = 18.0
    stilts.append(bar_between((0, roof_top - 0.3, 0.25), (0, pole_top - 0.2, 0.25), 0.1, 10))
    stilts.append(sphere(0.22, 8, 12).translate(0, pole_top - 0.22, 0.25))
    flag_cloth = pillow(smooth_outline([(0, -0.75), (2.4, -0.62), (2.25, 0.0), (2.4, 0.62), (0, 0.75)], 30, 1), (0.9, 0.0),
                        lambda q: np.full(len(q), 0.05), rings=3, edge=0.05)
    wave_cloth(flag_cloth, 0.0, 0.18, 2.3, 1.0)
    flag_cloth.rotate("y", 25).translate(0.12, pole_top - 1.25, 0.25)
    # Ladder up the back, leaning on the deck edge.
    for x in (-0.75, 0.75):
        ladder.append(bar_between((x, 0.13, 5.0), (x, deck_y + 1.2, 2.95), 0.13, 8))
    for k in range(11):
        t = (k + 0.6) / 11.5
        y = t * (deck_y + 1.2)
        z = 5.0 + (2.95 - 5.0) * t
        ladder.append(bar_between((-0.8, y, z), (0.8, y, z), 0.085, 6))
    # The warning sign on the front rail and the lifebuoy hanging beside it.
    sign.append(diamond_sign(3.6, 0.22).translate(0, deck_y + 2.05, -3.72))
    fin = pillow(smooth_outline(np.array(FIN_EMBLEM) * 2.4, 40), (0.0, 0.1), lambda q: np.full(len(q), 0.06), rings=3, edge=0.07)
    fin.v[:, 0] *= -1
    fin.f = fin.f[:, ::-1].copy()
    mark.append(fin.translate(0, deck_y + 2.1, -3.84))
    waves = strip_tube([(x, deck_y + 1.38 + 0.12 * math.sin(x * 6.0), -3.84) for x in np.linspace(-0.85, 0.85, 15)], [0.07] * 15, 6)
    mark.append(waves)
    ring, bands, rope = lifebuoy(0.72, 0.2)
    for m in (ring, bands, rope):
        m.rotate("x", 90).translate(2.35, deck_y + 0.95, -3.72)
    hook = bar_between((2.35, rail_y + 0.05, -3.62), (2.35, rail_y - 0.15, -3.72), 0.05, 6)
    return {"Stilts": merge(*stilts, hook), "Cabin": merge(*cabin), "Roof": merge(*roof), "Ladder": merge(*ladder),
            "Sign": merge(*sign), "SignMark": merge(*mark), "Float": ring, "FloatStripe": merge(bands, rope), "Flag": flag_cloth}


# =============================================================================== backdrop: the lighthouse

def lighthouse():
    """A red-and-white lighthouse on a grassy rock islet: a gallery rail, a glowing lantern room and
    a red cap. The door faces -Z."""
    rng = np.random.default_rng(17)
    # The islet: a craggy rock dome, boulders round its foot, a grass cap.
    base = organic_lathe([(11.0, 0.0), (10.6, 1.2), (9.6, 2.8), (8.6, 4.6), (7.9, 5.9), (7.2, 6.6), (5.0, 7.0), (0.0, 7.1)], 40, 0.07, waves=7, seed=4)
    base.v[:, 1] += wobble(base.v, 9, 0.6, 3.0) * (base.v[:, 1] > 0.3) * (base.v[:, 1] < 6.8)
    rocks = [base]
    for k in range(14):
        a = k * TAU / 14 + rng.uniform(-0.15, 0.15)
        r = rng.uniform(9.0, 10.6)
        rocks.append(lumpy(rng.uniform(1.0, 1.9), (1.2, 0.8, 1.0), 40 + k, 0.35, 1).translate(math.cos(a) * r, 0.7, math.sin(a) * r))
    rock = merge(*rocks)
    rock.v[:, 1] = np.maximum(rock.v[:, 1], 0.0)  # boulders sit flat on the sea bed
    rock.smooth = False
    grass = organic_lathe([(8.1, 6.0), (7.9, 6.6), (6.5, 7.35), (3.5, 7.75), (0.0, 7.85)], 40, 0.05, waves=6, seed=6)
    tufts = [lumpy(rng.uniform(0.6, 1.0), (1.3, 0.6, 1.3), 60 + k, 0.3, 1).translate(math.cos(a) * r, 7.5 - 0.07 * r, math.sin(a) * r)
             for k, (a, r) in enumerate([(rng.uniform(0, TAU), rng.uniform(4.5, 7.0)) for _ in range(8)])]
    # The tower: tapered, in bands; red bands are their own piece (they share the band edges).
    y0, y1, r0, r1 = 7.4, 35.6, 3.4, 2.3
    bands = 8
    prof = [(0.0, y0), (r0 + 0.25, y0), (r0 + 0.25, y0 + 0.5), (r0, y0 + 0.5)]
    for k in range(1, bands + 1):
        y = y0 + 0.5 + (y1 - y0 - 0.5) * k / bands
        prof.append((r0 + (r1 - r0) * (y - y0) / (y1 - y0), y))
    prof += [(0.0, y1)]
    # resample the straight run so each band has a few rows (for smooth shading on the taper)
    tower = lathe(prof, 40)
    c = tower.v[tower.f].mean(axis=1)
    band_index = np.floor((c[:, 1] - (y0 + 0.5)) / ((y1 - y0 - 0.5) / bands)).astype(int)
    red = (band_index % 2 == 0) & (c[:, 1] > y0 + 0.5) & (c[:, 1] < y1 - 0.01)
    stripes, tower_w = split_faces(tower, red)
    # Little windows up the tower and the door at its foot (-Z).
    door = []
    for y in (14.5, 22.0, 29.0):
        r = r0 + (r1 - r0) * (y - y0) / (y1 - y0)
        door.append(box(-0.35, y - 0.6, -r - 0.12, 0.35, y + 0.6, -r + 0.3, 0.12, 2))
    door_poly = [(-0.95, 0.0), (0.95, 0.0)] + [(0.95 * math.cos(a), 1.9 + 0.95 * math.sin(a)) for a in np.linspace(0, math.pi, 10)]
    dm = extrude(door_poly, 0.3).translate(0, y0 + 0.4, -(r0 + 0.02))
    door.append(dm)
    step = box(-1.4, y0 - 0.1, -r0 - 1.0, 1.4, y0 + 0.4, -r0 + 0.2, 0.1)
    # Gallery: a deck with corbels, a rail; the lantern room and its frame; the cap.
    rail = []
    gal_y = y1
    rail.append(cylinder(3.3, 0.45, 40, 0.1).translate(0, gal_y - 0.05, 0))
    for k in range(16):
        a = k * TAU / 16
        rail.append(box(-0.15, -0.9, -0.2, 0.15, 0.0, 0.2, 0.06).rotate("y", -math.degrees(a)).translate(math.cos(a) * 2.6, gal_y, math.sin(a) * 2.6))
    for k in range(24):
        a = k * TAU / 24
        rail.append(bar_between((math.cos(a) * 3.1, gal_y + 0.4, math.sin(a) * 3.1), (math.cos(a) * 3.1, gal_y + 1.7, math.sin(a) * 3.1), 0.06, 6))
    for y in (gal_y + 1.0, gal_y + 1.72):
        rail.append(torus(3.1, 0.08, 48, 6).translate(0, y, 0))
    lan_y0, lan_y1, lan_r = gal_y + 0.4, gal_y + 4.6, 1.75
    rail.append(cylinder(2.0, 0.8, 32, 0.08).translate(0, lan_y0, 0))
    lantern = lathe([(0.0, lan_y0 + 0.8), (lan_r, lan_y0 + 0.8), (lan_r, lan_y1), (0.0, lan_y1)], 24)
    for k in range(8):
        a = k * TAU / 8 + TAU / 16
        rail.append(bar_between((math.cos(a) * (lan_r + 0.04), lan_y0 + 0.8, math.sin(a) * (lan_r + 0.04)),
                                (math.cos(a) * (lan_r + 0.04), lan_y1, math.sin(a) * (lan_r + 0.04)), 0.09, 6))
    rail.append(torus(lan_r + 0.05, 0.12, 32, 6).translate(0, lan_y1, 0))
    cap_top = 46.0
    roof_m = lathe([(0.0, lan_y1), (2.45, lan_y1), (2.5, lan_y1 + 0.25), (2.0, lan_y1 + 1.2), (1.2, lan_y1 + 2.3), (0.55, lan_y1 + 2.85),
                    (0.0, lan_y1 + 3.0)], 32)
    ball = sphere(0.45, 10, 14).translate(0, lan_y1 + 3.3, 0)
    rod = bar_between((0, lan_y1 + 3.5, 0), (0, cap_top - 0.1, 0), 0.08, 6)
    tip = sphere(0.12, 6, 8).translate(0, cap_top - 0.12, 0)
    return {"Rock": merge(rock, step), "Grass": merge(grass, *tufts), "Tower": tower_w, "Stripes": stripes, "Rail": merge(*rail, rod, tip),
            "Lantern": lantern, "Roof": merge(roof_m, ball), "Door": merge(*door)}


PROPS = {
    "SharkBaitShark": shark,
    "SharkBaitRaft": raft,
    "SharkBaitCoin": coin,
    "SharkBaitPearl": pearl_clam,
    "SharkBaitChest": chest,
    "SharkBaitFloatie": floatie,
    "SharkBaitFloatLine": float_line,
    "SharkBaitBuoy": buoy,
    "SharkBaitGull": gull,
    "SharkBaitCoral": coral,
    "SharkBaitKelp": kelp,
    "SharkBaitStarfish": starfish,
    "SharkBaitSandBar": sand_bar,
    "SharkBaitHut": hut,
    "SharkBaitLighthouse": lighthouse,
}

# Preview colors (the game colors pieces by name from the Luau palette).
COLORS = {
    "Belly": (240, 240, 232),
    "Tail": (110, 130, 160),
    "Mouth": (170, 40, 60),
    "Teeth": (255, 255, 250),
    "Jaw": (240, 240, 232),
    "JawTeeth": (255, 255, 250),
    "EyeShine": (255, 255, 255),
    "Gills": (70, 85, 110),
    "Deck": (196, 146, 92),
    "Beams": (130, 88, 55),
    "Barrels": (160, 104, 62),
    "Hoops": (90, 90, 100),
    "Rope": (226, 200, 150),
    "Coin": (255, 205, 50),
    "Rim": (230, 165, 30),
    "Shell": (255, 150, 170),
    "ShellInside": (255, 225, 230),
    "Pearl": (250, 245, 255),
    "Wood": (150, 90, 50),
    "Trim": (255, 200, 60),
    "Gold": (255, 215, 70),
    "Lock": (90, 90, 100),
    "Ring": (255, 120, 60),
    "Stripes": (255, 255, 255),
    "FloatsA": (255, 210, 60),
    "FloatsB": (240, 70, 70),
    "Float": (220, 60, 60),
    "Stripe": (245, 245, 245),
    "Cage": (70, 70, 80),
    "Lamp": (255, 220, 120),
    "Flag": (255, 210, 60),
    "FlagMark": (25, 25, 30),
    "Wings": (235, 238, 245),
    "WingTips": (70, 75, 90),
    "Beak": (255, 170, 40),
    "CoralA": (255, 110, 140),
    "CoralB": (255, 170, 60),
    "CoralC": (150, 110, 255),
    "Fan": (255, 90, 90),
    "Kelp": (60, 160, 90),
    "Bulbs": (150, 190, 70),
    "Star": (255, 130, 60),
    "Dots": (255, 220, 170),
    "Sand": (240, 220, 170),
    "WetSand": (200, 175, 130),
    "Shells": (255, 235, 220),
    "Stilts": (235, 235, 230),
    "Cabin": (230, 70, 60),
    "Roof": (250, 250, 245),
    "Ladder": (200, 150, 90),
    "Sign": (255, 210, 60),
    "SignMark": (25, 25, 30),
    "FloatStripe": (255, 255, 255),
    "Grass": (100, 180, 80),
    "Tower": (245, 245, 240),
    "Rail": (60, 60, 70),
    "Lantern": (255, 230, 140),
    "Door": (110, 70, 45),
}
