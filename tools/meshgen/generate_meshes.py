"""Generates the low-poly, toy-style prop meshes used by Party Panic.

    python3 tools/meshgen/generate_meshes.py                  # every prop
    python3 tools/meshgen/generate_meshes.py --only Bee,Fruit # just these

A mini-game's own props go in tools/meshgen/props/<Game>.py (PROPS = {name: builder}, optional
COLORS), using the helpers here: `from generate_meshes import lathe, tube, rounded_box, ...`.

Writes assets/meshes/<Prop>.obj (for Studio's 3D Importer) and <Prop>.glb (for Open Cloud upload).
Each prop is split into named pieces ("Basket", "Wheels", ...) that match the palette in
src/server/World/MeshLibrary.luau, so colors are applied in-game and one mesh serves every color.
Units are studs, +Y is up, the prop's base sits on y = 0, and -Z is the prop's front.
"""

from __future__ import annotations

import json
import math
import struct
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "meshes"


# ====================================================================== mesh core

class Mesh:
    def __init__(self, vertices=None, faces=None, smooth: bool = True):
        self.v = np.asarray(vertices if vertices is not None else np.zeros((0, 3)), dtype=np.float64).reshape(-1, 3)
        self.f = np.asarray(faces if faces is not None else np.zeros((0, 3)), dtype=np.int64).reshape(-1, 3)
        self.smooth = smooth

    def copy(self) -> "Mesh":
        return Mesh(self.v.copy(), self.f.copy(), self.smooth)

    def translate(self, x=0.0, y=0.0, z=0.0) -> "Mesh":
        self.v = self.v + np.array([x, y, z])
        return self

    def scale(self, x=1.0, y=None, z=None) -> "Mesh":
        self.v = self.v * np.array([x, x if y is None else y, x if z is None else z])
        return self

    def rotate(self, axis: str, degrees: float) -> "Mesh":
        a = math.radians(degrees)
        c, s = math.cos(a), math.sin(a)
        m = {"x": [[1, 0, 0], [0, c, -s], [0, s, c]],
             "y": [[c, 0, s], [0, 1, 0], [-s, 0, c]],
             "z": [[c, -s, 0], [s, c, 0], [0, 0, 1]]}[axis]
        self.v = self.v @ np.array(m).T
        return self

    def normals(self) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
        """Returns (positions, normals, faces) ready to export; flat meshes get split vertices."""
        tri = self.v[self.f]
        face_n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        if not self.smooth:
            positions = tri.reshape(-1, 3)
            n = face_n / (np.linalg.norm(face_n, axis=1, keepdims=True) + 1e-12)
            normals = np.repeat(n, 3, axis=0)
            faces = np.arange(len(positions)).reshape(-1, 3)
            return positions, normals, faces
        vn = np.zeros_like(self.v)
        for i in range(3):
            np.add.at(vn, self.f[:, i], face_n)
        vn /= np.linalg.norm(vn, axis=1, keepdims=True) + 1e-12
        return self.v, vn, self.f


def merge(*meshes: Mesh) -> Mesh:
    v, f, offset = [], [], 0
    for m in meshes:
        v.append(m.v)
        f.append(m.f + offset)
        offset += len(m.v)
    return Mesh(np.vstack(v), np.vstack(f), smooth=all(m.smooth for m in meshes))


def weld(mesh: Mesh, tolerance: float = 1e-5) -> Mesh:
    """Merges duplicate vertices so smooth normals are continuous across seams."""
    keys = np.round(mesh.v / tolerance).astype(np.int64)
    _, index, inverse = np.unique(keys, axis=0, return_index=True, return_inverse=True)
    faces = inverse.reshape(-1)[mesh.f]
    keep = (faces[:, 0] != faces[:, 1]) & (faces[:, 1] != faces[:, 2]) & (faces[:, 0] != faces[:, 2])
    return Mesh(mesh.v[index], faces[keep], mesh.smooth)


# ====================================================================== primitives

def grid_face(n: int):
    faces = []
    for i in range(n):
        for j in range(n):
            a = i * (n + 1) + j
            b, c, d = a + 1, a + n + 1, a + n + 2
            faces += [(a, c, b), (b, c, d)]
    return faces


def rounded_box(sx: float, sy: float, sz: float, r: float, n: int = 8) -> Mesh:
    """A box with every edge rounded: cube grid points pushed onto an offset surface."""
    half = np.array([sx, sy, sz]) / 2
    r = min(r, *(half - 1e-3))
    inner = half - r
    verts, faces = [], []
    axes = [(0, 1, 2), (0, 2, 1), (1, 2, 0)]
    lin = np.linspace(-1, 1, n + 1)
    for u_axis, v_axis, w_axis in axes:
        for sign in (-1, 1):
            base = len(verts)
            for a in lin:
                for b in lin:
                    p = np.zeros(3)
                    p[u_axis], p[v_axis], p[w_axis] = a, b, sign
                    # Place grid points densely near edges so curvature is smooth.
                    q = np.sign(p) * (np.abs(p) ** 0.6) * half
                    core = np.clip(q, -inner, inner)
                    d = q - core
                    length = np.linalg.norm(d)
                    verts.append(core + (d / length * r if length > 1e-9 else 0))
            for (a, b, c) in grid_face(n):
                tri = (base + a, base + b, base + c)
                # Orient outward.
                pa, pb, pc = (np.array(verts[t]) for t in tri)
                if np.dot(np.cross(pb - pa, pc - pa), pa) < 0:
                    tri = (tri[0], tri[2], tri[1])
                faces.append(tri)
    return weld(Mesh(verts, faces))


def lathe(profile: list[tuple[float, float]], segments: int = 32, cap_bottom: bool = False, cap_top: bool = False) -> Mesh:
    """Revolves (radius, y) points around the Y axis."""
    verts, faces = [], []
    rows = len(profile)
    for (radius, y) in profile:
        for s in range(segments):
            a = 2 * math.pi * s / segments
            verts.append((math.cos(a) * radius, y, math.sin(a) * radius))
    for i in range(rows - 1):
        for s in range(segments):
            a = i * segments + s
            b = i * segments + (s + 1) % segments
            c = a + segments
            d = b + segments
            faces += [(a, c, b), (b, c, d)]
    if cap_bottom:
        center = len(verts)
        verts.append((0, profile[0][1], 0))
        faces += [(center, s, (s + 1) % segments) for s in range(segments)]
    if cap_top:
        center = len(verts)
        verts.append((0, profile[-1][1], 0))
        top = (rows - 1) * segments
        faces += [(center, top + (s + 1) % segments, top + s) for s in range(segments)]
    return weld(Mesh(verts, faces))


def cylinder(radius: float, height: float, segments: int = 24, bevel: float = 0.0) -> Mesh:
    if bevel <= 0:
        return lathe([(radius, 0), (radius, height)], segments, True, True)
    profile = [(0, 0), (radius - bevel, 0)]
    for i in range(1, 5):
        a = math.pi / 2 * i / 4
        profile.append((radius - bevel + math.sin(a) * bevel, bevel - math.cos(a) * bevel))
    for i in range(0, 5):
        a = math.pi / 2 * i / 4
        profile.append((radius - bevel + math.cos(a) * bevel, height - bevel + math.sin(a) * bevel))
    profile.append((0, height))
    return lathe(profile, segments)


def sphere(radius: float, rings: int = 14, segments: int = 24) -> Mesh:
    profile = [(math.sin(math.pi * i / rings) * radius, -math.cos(math.pi * i / rings) * radius) for i in range(rings + 1)]
    return lathe(profile, segments)


def capsule(length: float, radius: float, segments: int = 20) -> Mesh:
    """Along Y, centered on the origin."""
    body = max(0.0, length - 2 * radius)
    profile = []
    for i in range(7):
        a = -math.pi / 2 + math.pi / 2 * i / 6
        profile.append((math.cos(a) * radius, -body / 2 + math.sin(a) * radius))
    for i in range(7):
        a = math.pi / 2 * i / 6
        profile.append((math.cos(a) * radius, body / 2 + math.sin(a) * radius))
    return lathe(profile, segments)


def torus(major: float, minor: float, segments: int = 32, sides: int = 12, arc: float = 360.0) -> Mesh:
    """In the XZ plane."""
    verts, faces = [], []
    closed = arc >= 360
    rings = segments if closed else segments + 1
    for i in range(rings):
        a = math.radians(arc) * i / segments
        for j in range(sides):
            b = 2 * math.pi * j / sides
            r = major + math.cos(b) * minor
            verts.append((math.cos(a) * r, math.sin(b) * minor, math.sin(a) * r))
    for i in range(segments):
        for j in range(sides):
            a = i * sides + j
            b = i * sides + (j + 1) % sides
            c = ((i + 1) % rings) * sides + j
            d = ((i + 1) % rings) * sides + (j + 1) % sides
            faces += [(a, b, c), (b, d, c)]
    return Mesh(verts, faces)


def icosphere(radius: float, subdivisions: int = 2, noise: float = 0.0, seed: int = 0) -> Mesh:
    t = (1 + math.sqrt(5)) / 2
    verts = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
             (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    faces = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2),
             (10, 7, 6), (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11),
             (6, 2, 10), (8, 6, 7), (9, 8, 1)]
    verts = [np.array(v) / np.linalg.norm(v) for v in verts]
    for _ in range(subdivisions):
        cache, new_faces = {}, []

        def midpoint(a, b):
            key = (min(a, b), max(a, b))
            if key not in cache:
                m = verts[a] + verts[b]
                verts.append(m / np.linalg.norm(m))
                cache[key] = len(verts) - 1
            return cache[key]

        for a, b, c in faces:
            ab, bc, ca = midpoint(a, b), midpoint(b, c), midpoint(c, a)
            new_faces += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        faces = new_faces
    v = np.array(verts)
    if noise > 0:
        rng = np.random.default_rng(seed)
        # Smooth, low-frequency bumps: sum of a few random directional waves.
        bump = np.zeros(len(v))
        for _ in range(6):
            direction = rng.normal(size=3)
            direction /= np.linalg.norm(direction)
            bump += np.sin(v @ direction * rng.uniform(2, 4) + rng.uniform(0, 6)) * rng.uniform(0.4, 1)
        v = v * (1 + noise * bump / 6)[:, None]
    return Mesh(v * radius, faces)


def tube(points: list[tuple[float, float, float]], radius: float, sides: int = 8) -> Mesh:
    """A thin tube along a polyline (strings, wire handles)."""
    pts = [np.array(p, dtype=float) for p in points]
    verts, faces = [], []
    for i, p in enumerate(pts):
        tangent = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
        tangent /= np.linalg.norm(tangent) + 1e-9
        helper = np.array([0, 0, 1.0]) if abs(tangent[2]) < 0.9 else np.array([1.0, 0, 0])
        u = np.cross(tangent, helper)
        u /= np.linalg.norm(u)
        w = np.cross(tangent, u)
        for j in range(sides):
            a = 2 * math.pi * j / sides
            verts.append(p + (u * math.cos(a) + w * math.sin(a)) * radius)
    for i in range(len(pts) - 1):
        for j in range(sides):
            a = i * sides + j
            b = i * sides + (j + 1) % sides
            faces += [(a, b, a + sides), (b, b + sides, a + sides)]  # outward (Roblox culls back faces)
    return Mesh(verts, faces)


def taper(points: list[tuple[float, float, float]], r0: float, r1: float, sides: int = 8) -> Mesh:
    """A tube along a polyline that thins from r0 to r1 and is closed at both ends (roots, branches)."""
    mesh = tube(points, 1.0, sides)
    count = len(points)
    for i, point in enumerate(points):
        radius = lerp(r0, r1, i / (count - 1))
        ring = slice(i * sides, (i + 1) * sides)
        mesh.v[ring] = np.array(point) + (mesh.v[ring] - np.array(point)) * radius
    faces = [tuple(f) for f in mesh.f]
    verts = [tuple(v) for v in mesh.v]
    for end, ring_start, flip in ((points[0], 0, True), (points[-1], (count - 1) * sides, False)):
        center = len(verts)
        verts.append(tuple(end))
        for j in range(sides):
            a, b = ring_start + j, ring_start + (j + 1) % sides
            faces.append((center, b, a) if flip else (center, a, b))
    return Mesh(verts, faces)


def extrude(polygon: list[tuple[float, float]], depth: float) -> Mesh:
    """Extrudes a star-shaped 2D polygon (fan-triangulated from its centroid) along Z. The points may
    go either way round; the faces always point outward."""
    pts = np.array(polygon, dtype=float)
    x, y = pts[:, 0], pts[:, 1]
    if np.dot(x, np.roll(y, -1)) - np.dot(np.roll(x, -1), y) < 0:  # clockwise (star() is): reverse
        pts = pts[::-1].copy()
    center = pts.mean(axis=0)
    n = len(pts)
    verts = [(center[0], center[1], -depth / 2), (center[0], center[1], depth / 2)]
    verts += [(x, y, -depth / 2) for x, y in pts] + [(x, y, depth / 2) for x, y in pts]
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces += [(0, 2 + j, 2 + i), (1, 2 + n + i, 2 + n + j)]
        faces += [(2 + i, 2 + j, 2 + n + i), (2 + j, 2 + n + j, 2 + n + i)]
    mesh = Mesh(verts, faces)
    mesh.smooth = False
    return mesh


def star(outer: float, inner: float, points: int = 5) -> list[tuple[float, float]]:
    return [((outer if i % 2 == 0 else inner) * math.sin(math.pi * i / points), (outer if i % 2 == 0 else inner) * math.cos(math.pi * i / points)) for i in range(points * 2)]


def organic_lathe(profile, segments, amount, waves=5, seed=0):
    """A lathe whose radius wobbles with angle - bark, roots and other natural shapes."""
    mesh = lathe(profile, segments)
    rng = np.random.default_rng(seed)
    angle = np.arctan2(mesh.v[:, 2], mesh.v[:, 0])
    wobble = 1 + amount * (np.sin(angle * waves + rng.uniform(0, 6)) * 0.6 + np.sin(angle * (waves + 3) + mesh.v[:, 1] * 0.8) * 0.4)
    mesh.v[:, 0] *= wobble
    mesh.v[:, 2] *= wobble
    return mesh


def lerp(a, b, t):
    return a + (b - a) * t


# ---------------------------------------------------------------- SDF sculpting
# Organic shapes (gloves, cushions, blobs) are modelled as signed distance fields and smoothly
# blended with `smin`, then meshed with marching cubes - one seamless surface, no stuck-on parts.

def sd_ellipsoid(p, center, radii):
    q = (p - np.array(center)) / np.array(radii)
    k0 = np.linalg.norm(q, axis=-1)
    k1 = np.linalg.norm(q / np.array(radii), axis=-1)
    return k0 * (k0 - 1) / np.maximum(k1, 1e-9)


def sd_capsule(p, a, b, r):
    a, b = np.array(a), np.array(b)
    pa, ba = p - a, b - a
    h = np.clip((pa @ ba) / (ba @ ba), 0, 1)
    return np.linalg.norm(pa - h[..., None] * ba, axis=-1) - r


def sd_round_cylinder_z(p, center, radius, half_length, rounding):
    q = p - np.array(center)
    d = np.stack([np.linalg.norm(q[..., :2], axis=-1) - radius + rounding, np.abs(q[..., 2]) - half_length + rounding], -1)
    return np.minimum(np.maximum(d[..., 0], d[..., 1]), 0) + np.linalg.norm(np.maximum(d, 0), axis=-1) - rounding


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)


def sdf_mesh(sdf, lo, hi, step):
    try:
        from skimage.measure import marching_cubes
    except ImportError as error:
        raise SystemExit("SDF props need scikit-image: pip install scikit-image") from error
    lo, hi = np.array(lo, float), np.array(hi, float)
    axes = [np.arange(lo[i], hi[i] + step, step) for i in range(3)]
    grid = np.stack(np.meshgrid(*axes, indexing="ij"), -1)
    field = sdf(grid.reshape(-1, 3)).reshape(grid.shape[:3])
    # marching_cubes' faces point toward lower values, which for a signed distance field is outward.
    verts, faces, _, _ = marching_cubes(field, 0.0, spacing=(step, step, step))
    return taubin_smooth(Mesh(verts + lo, faces), 6)


def taubin_smooth(mesh: Mesh, iterations: int, lam: float = 0.5, mu: float = -0.53) -> Mesh:
    """Removes marching-cubes stair-stepping without shrinking the shape."""
    from scipy.sparse import coo_matrix, diags

    n = len(mesh.v)
    f = mesh.f
    rows = np.concatenate([f[:, 0], f[:, 1], f[:, 2], f[:, 1], f[:, 2], f[:, 0]])
    cols = np.concatenate([f[:, 1], f[:, 2], f[:, 0], f[:, 0], f[:, 1], f[:, 2]])
    adjacency = coo_matrix((np.ones(len(rows)), (rows, cols)), shape=(n, n)).tocsr()
    adjacency.data[:] = 1.0
    degree = np.asarray(adjacency.sum(axis=1)).ravel()
    average = diags(1.0 / np.maximum(degree, 1)) @ adjacency
    v = mesh.v.copy()
    for _ in range(iterations):
        v = v + lam * (average @ v - v)
        v = v + mu * (average @ v - v)
    return Mesh(v, mesh.f.copy(), mesh.smooth)


# ====================================================================== props
# Each returns {piece_name: Mesh}. Piece names match MeshLibrary palettes.

def shopping_cart():
    """A proper supermarket cart: tapered wire basket, fold-down child seat, handle grip,
    bottom rack, angled chassis and swivel casters."""
    w_top, w_bot = 1.95, 1.62  # basket half-widths
    y_bot, y_top = 1.95, 3.75
    z_front_top, z_front_bot, z_back = -3.1, -2.4, 1.9
    wire, rim = 0.035, 0.075

    def corner(side: int, front: bool, level: float):
        w = lerp(w_bot, w_top, level)
        z = lerp(z_front_bot, z_front_top, level) if front else z_back
        return (side * w, lerp(y_bot, y_top, level), z)

    basket = []
    for level in (0.0, 0.2, 0.4, 0.6, 0.8, 1.0):
        loop = [corner(-1, True, level), corner(1, True, level), corner(1, False, level), corner(-1, False, level), corner(-1, True, level)]
        basket.append(tube(loop, rim if level in (0.0, 1.0) else wire, 6))
    for i in range(13):  # side walls follow the sloped front
        u = i / 12
        for side in (-1, 1):
            basket.append(tube([(side * w_bot, y_bot, lerp(z_front_bot, z_back, u)), (side * w_top, y_top, lerp(z_front_top, z_back, u))], wire, 5))
    for i in range(11):  # front wall and back gate
        u = i / 10 * 2 - 1
        basket.append(tube([(u * w_bot, y_bot, z_front_bot), (u * w_top, y_top, z_front_top)], wire, 5))
        basket.append(tube([(u * w_bot, y_bot, z_back), (u * w_top, y_top, z_back)], wire, 5))
    for i in range(1, 8):  # basket floor grid
        x = lerp(-w_bot, w_bot, i / 8)
        basket.append(tube([(x, y_bot, z_front_bot), (x, y_bot, z_back)], wire, 5))
    for i in range(1, 10):
        z = lerp(z_front_bot, z_back, i / 10)
        basket.append(tube([(-w_bot, y_bot, z), (w_bot, y_bot, z)], wire, 5))

    chassis = []
    rail_y, rail_x, rail_front, rail_back = 0.8, 1.4, -2.45, 1.7
    chassis.append(tube([(-rail_x, rail_y, rail_front), (rail_x, rail_y, rail_front), (rail_x, rail_y, rail_back), (-rail_x, rail_y, rail_back), (-rail_x, rail_y, rail_front)], 0.085, 8))
    for side in (-1, 1):
        # Rear upright: from the base, past the basket, up to the handle.
        chassis.append(tube([(side * rail_x, rail_y, rail_back), (side * 1.6, y_bot, 1.95), (side * 1.85, y_top, 2.2), (side * 1.92, 4.0, 2.5)], 0.085, 8))
        chassis.append(tube([(side * rail_x, rail_y, rail_front), (side * 1.58, y_bot, -2.35)], 0.075, 8))
        chassis.append(tube([(side * rail_x, rail_y, -0.3), (side * 1.6, y_bot, -0.1)], 0.06, 6))
    for i in range(6):  # lower rack tray
        x = lerp(-1.25, 1.25, i / 5)
        chassis.append(tube([(x, 0.95, -2.3), (x, 0.95, 1.5)], 0.03, 5))
    for z in (-2.3, -0.4, 1.5):
        chassis.append(tube([(-1.3, 0.95, z), (1.3, 0.95, z)], 0.04, 5))

    wheels = []
    for x in (-rail_x, rail_x):
        for z in (rail_front + 0.1, rail_back - 0.1):
            chassis.append(rounded_box(0.5, 0.08, 0.5, 0.03, 2).translate(x, 0.74, z))
            for fork in (-0.15, 0.15):
                chassis.append(rounded_box(0.05, 0.42, 0.26, 0.02, 2).translate(x + fork, 0.5, z + 0.1))
            chassis.append(cylinder(0.09, 0.4, 10).rotate("z", 90).translate(x + 0.2, 0.32, z + 0.12))
            tire = merge(torus(0.24, 0.1, 20, 8).rotate("z", 90), cylinder(0.24, 0.2, 16).translate(0, -0.1, 0).rotate("z", 90))
            wheels.append(tire.translate(x, 0.34, z + 0.12))

    plastic = [capsule(3.95, 0.15, 16).rotate("z", 90).translate(0, 4.02, 2.5)]  # handle grip
    plastic += [rounded_box(0.3, 0.32, 0.3, 0.12, 3).translate(*corner(side, front, 1.0)) for side in (-1, 1) for front in (True, False)]
    plate = rounded_box(1.7, 0.55, 0.1, 0.05, 3).rotate("x", 21).translate(0, 3.0, -2.86)
    seat = rounded_box(2.4, 0.85, 0.07, 0.03, 3).translate(0, 3.05, z_back + 0.07)  # child-seat back panel, flush on the gate
    bumper = capsule(2.9, 0.12, 12).rotate("z", 90).translate(0, 0.8, -2.62)
    plastic += [plate, seat, bumper]
    return {"Basket": merge(*basket), "Chassis": merge(*chassis), "Frame": merge(*plastic), "Wheels": merge(*wheels)}


def yeet_glove():
    """Boxing glove sculpted as one smooth surface: padded mitt, curled fist, blended thumb,
    plus a laced cuff and a star badge."""

    def glove_sdf(p):
        d = sd_ellipsoid(p, (0, 1.3, -0.55), (1.05, 0.95, 1.25))
        d = smin(d, sd_ellipsoid(p, (0, 1.58, -0.3), (0.95, 0.78, 1.0)), 0.3)  # padded top
        d = smin(d, sd_ellipsoid(p, (0, 1.05, -1.22), (0.95, 0.78, 0.62)), 0.35)  # curled fist
        d = smin(d, sd_ellipsoid(p, (0, 1.22, 0.3), (0.8, 0.8, 0.55)), 0.3)  # wrist
        # The thumb is blended tightly so it reads as its own padded roll along the side.
        thumb = sd_capsule(p, (-1.02, 0.98, -0.05), (-1.16, 1.13, -0.7), 0.34)
        thumb = smin(thumb, sd_capsule(p, (-1.16, 1.13, -0.7), (-0.88, 1.33, -1.12), 0.31), 0.12)
        return smin(d, thumb, 0.1)

    def cuff_sdf(p):
        return sd_round_cylinder_z(p, (0, 1.22, 0.92), 0.8, 0.45, 0.12)

    mitt = sdf_mesh(glove_sdf, (-1.65, 0.1, -2.05), (1.25, 2.55, 0.95), 0.085)
    cuff = sdf_mesh(cuff_sdf, (-0.95, 0.3, 0.35), (0.95, 2.15, 1.5), 0.075)
    stripe = torus(0.81, 0.055, 32, 6).rotate("x", 90).translate(0, 1.22, 1.18)
    laces = tube([(-0.2, 2.06, 0.55), (0.2, 2.08, 0.72), (-0.2, 2.09, 0.89), (0.2, 2.09, 1.06), (-0.2, 2.07, 1.2)], 0.05, 6)
    badge = extrude(star(0.36, 0.16), 0.1).rotate("x", -90).rotate("x", -12).translate(0, 2.38, -0.5)
    return {"Glove": mitt, "Cuff": merge(cuff, stripe, laces, badge)}


def anvil():
    feet = [rounded_box(1.1, 0.35, 2.9, 0.12, 3).translate(x, 0.18, 0) for x in (-1.35, 1.35)]
    base = rounded_box(3.4, 0.85, 2.5, 0.28).translate(0, 0.75, 0)
    waist = lathe([(1.05, 0.0), (0.8, 0.5), (0.7, 1.0), (0.85, 1.45), (1.1, 1.6)], 4).rotate("y", 45).scale(1.0, 1.0, 0.75).translate(0, 1.15, 0)
    top = rounded_box(4.2, 1.15, 2.3, 0.25).translate(0.35, 3.3, 0)
    heel = rounded_box(0.9, 0.6, 1.6, 0.15).translate(2.75, 3.45, 0)
    horn = lathe([(0.8, 0), (0.66, 0.6), (0.48, 1.2), (0.28, 1.8), (0.1, 2.25), (0.0, 2.35)], 18).rotate("z", 90).translate(-1.75, 3.45, 0)
    rivets = [icosphere(0.09, 1).translate(x, 3.3, 1.16) for x in (-1.2, -0.4, 0.4, 1.2, 2.0)]
    return {"Anvil": merge(*feet, base, waist, top, heel, horn, *rivets)}


def boulder():
    # Faceted low-poly rock with a couple of pebbles: flat shading reads as "stylized stone".
    rock = icosphere(4.0, 2, noise=0.55, seed=11).scale(1.1, 0.85, 1.0).translate(0, 3.6, 0)
    chips = [icosphere(0.7, 1, noise=0.4, seed=s_).translate(x, 0.5, z) for s_, (x, z) in enumerate(((3.6, 1.8), (-3.2, -2.0), (1.0, -3.4)))]
    mesh = merge(rock, *chips)
    mesh.smooth = False
    return {"Rock": mesh}


def mallet_head():
    profile = [(0, 0)]
    for i in range(1, 7):
        a = math.pi / 2 * i / 6
        profile.append((math.sin(a) * 2.25, 0.45 - math.cos(a) * 0.45))
    profile += [(2.25, 3.75), (2.3, 3.75), (2.3, 3.9), (2.25, 3.9), (2.25, 7.1)]
    for i in range(1, 7):
        a = math.pi / 2 * i / 6
        profile.append((math.cos(a) * 2.25, 7.1 + math.sin(a) * 0.45))
    head = lathe(profile, 36).translate(0, -3.775, 0).rotate("z", 90).translate(0, 2.25, 0)
    bands = [torus(2.3, 0.3, 36, 10).rotate("z", 90).translate(x, 2.25, 0) for x in (-2.55, 2.55)]
    faces = [cylinder(1.6, 0.18, 32, 0.06).rotate("z", 90).translate(x, 2.25, 0) for x in (-3.77, 3.95)]
    collar = cylinder(0.75, 0.6, 24, 0.12).translate(0, 4.35, 0)
    return {"Head": head, "Bands": merge(*bands, *faces, collar)}


def treasure():
    gem = lathe([(0.0, 0.0), (1.05, 1.25), (1.08, 1.4), (0.62, 1.95), (0.0, 1.95)], 10)
    gem.smooth = False  # crisp facets catch the light
    return {"Gold": gem}


def chest():
    planks = []
    for i in range(5):  # body planks with grooves between them
        inset = 0.0 if i % 2 == 0 else 0.03
        planks.append(rounded_box(4.9 - inset, 0.5, 3.3 - inset, 0.08, 3).translate(0, 0.27 + i * 0.53, 0))
    lid = []
    for i in range(6):  # curved lid built from plank strips
        a0, a1 = math.pi * i / 6, math.pi * (i + 1) / 6
        mid = (a0 + a1) / 2
        chord = 2 * 1.7 * math.sin((a1 - a0) / 2) + 0.05
        strip = rounded_box(4.9, 0.28, chord, 0.06, 3).rotate("x", -math.degrees(mid) + 90)
        lid.append(strip.translate(0, 2.68 + math.sin(mid) * 1.58, math.cos(mid) * 1.58))
    # Close the lid's curved ends with half-disc panels.
    half_disc = [(math.cos(a) * 1.68, math.sin(a) * 1.68) for a in np.linspace(0, math.pi, 17)]
    for x in (-2.38, 2.38):
        lid.append(extrude(half_disc, 0.14).rotate("y", 90).rotate("x", 0).translate(x, 2.68, 0))
    trim = []
    for x in (-2.0, 2.0):
        trim.append(torus(1.74, 0.1, 24, 6, 180).rotate("x", -90).rotate("y", 90).translate(x, 2.68, 0))
        trim.append(rounded_box(0.34, 2.7, 3.45, 0.08, 2).translate(x, 1.35, 0))
    for x in (-2.45, 2.45):
        for z in (-1.65, 1.65):
            trim.append(rounded_box(0.25, 2.75, 0.25, 0.08, 2).translate(x, 1.37, z))
    trim.append(rounded_box(0.9, 1.1, 0.18, 0.08, 3).translate(0, 2.55, -1.72))
    trim.append(cylinder(0.12, 0.1, 12).rotate("x", 90).translate(0, 2.65, -1.82))
    for x in (-2.55, 2.55):
        trim.append(torus(0.35, 0.07, 16, 6, 180).rotate("x", 90).rotate("y", 90).translate(x, 1.75, 0))
    return {"Body": merge(*planks), "Lid": merge(*lid), "Trim": merge(*trim)}


def trophy():
    cup = lathe([(0.0, 3.0), (0.35, 3.0), (0.45, 3.4), (1.2, 4.0), (1.55, 4.8), (1.65, 5.7), (1.78, 6.25), (1.85, 6.35),
                 (1.6, 6.35), (1.5, 5.8), (0.2, 4.4), (0.0, 4.4)], 36)
    stem = lathe([(0.0, 1.45), (0.8, 1.45), (0.45, 1.85), (0.28, 2.3), (0.45, 2.55), (0.3, 2.75), (0.6, 3.05), (0.0, 3.05)], 28)
    handles = [torus(0.75, 0.14, 22, 8, 200).rotate("x", 90).rotate("y", 90 if side > 0 else -90).translate(side * 1.55, 5.15, 0) for side in (-1, 1)]
    topper = extrude(star(0.62, 0.27), 0.22).translate(0, 7.0, 0)
    tier1 = rounded_box(3.0, 0.75, 3.0, 0.22).translate(0, 0.375, 0)
    tier2 = rounded_box(2.3, 0.7, 2.3, 0.2).translate(0, 1.1, 0)
    plate = rounded_box(1.4, 0.45, 0.06, 0.03, 2).translate(0, 0.4, -1.52)
    return {"Cup": merge(cup, stem, *handles, topper, plate), "Base": merge(tier1, tier2)}


def tree():
    trunk = organic_lathe([(1.15, 0.0), (0.85, 0.5), (0.68, 2.0), (0.6, 5.0), (0.5, 8.0), (0.3, 9.5), (0.0, 9.7)], 14, 0.12, seed=3)
    branches = [tube([(0, 5.5, 0), (1.4, 7.0, 0.6), (2.6, 8.3, 1.1)], 0.22, 7), tube([(0, 6.2, 0), (-1.3, 7.6, -0.8), (-2.4, 8.7, -1.3)], 0.2, 7)]
    canopy = merge(
        icosphere(3.9, 2, 0.14, 1).translate(0, 11.0, 0),
        icosphere(2.9, 2, 0.16, 2).translate(2.8, 9.4, 1.3),
        icosphere(2.9, 2, 0.16, 3).translate(-2.6, 9.7, -1.5),
        icosphere(2.6, 2, 0.16, 4).translate(0.6, 13.4, 0.3),
        icosphere(2.4, 2, 0.18, 5).translate(-1.4, 10.8, 2.2),
        icosphere(2.3, 2, 0.18, 6).translate(1.6, 11.6, -2.0),
    )
    return {"Trunk": merge(trunk, *branches), "Leaves": canopy}


def bush():
    leaves = merge(icosphere(2.2, 2, 0.15, 5).translate(0, 1.9, 0),
                   icosphere(1.7, 2, 0.18, 6).translate(1.7, 1.5, 0.4),
                   icosphere(1.65, 2, 0.18, 8).translate(-1.6, 1.45, -0.3),
                   icosphere(1.3, 2, 0.2, 9).translate(0.4, 1.2, 1.6))
    rng = np.random.default_rng(4)
    flowers = []
    for _ in range(9):
        theta, phi = rng.uniform(0, 2 * math.pi), rng.uniform(0.2, 1.2)
        position = np.array([math.cos(theta) * math.sin(phi), math.cos(phi), math.sin(theta) * math.sin(phi)]) * 2.3 + np.array([0, 1.9, 0])
        petals = [icosphere(0.22, 1).translate(*(position + np.array([math.cos(a) * 0.24, 0, math.sin(a) * 0.24]))) for a in np.linspace(0, 2 * math.pi, 5, endpoint=False)]
        flowers.append(merge(*petals))
    return {"Leaves": leaves, "Flowers": merge(*flowers)}


def balloon():
    profile = [(0.0, 4.0)]
    for i in range(1, 15):
        t = i / 14
        a = math.pi * t
        profile.append((math.sin(a) * 1.3 * (1 - 0.18 * t), 5.6 - math.cos(a) * 1.6))
    profile.append((0.0, 7.2))
    body = lathe(profile, 30)
    knot = lathe([(0.0, 3.82), (0.2, 3.88), (0.27, 4.02), (0.0, 4.2)], 12)
    string = tube([(0, 0, 0), (0.18, 0.7, 0.05), (-0.12, 1.4, 0.0), (0.15, 2.1, -0.05), (-0.1, 2.8, 0.05), (0.08, 3.4, 0), (0, 3.85, 0)], 0.04, 5)
    return {"Balloon": merge(body, knot), "String": string}


def bench():
    slats = [rounded_box(8.0, 0.3, 0.65, 0.12).translate(0, 1.72, z) for z in (-0.88, -0.1, 0.68)]
    back = [rounded_box(8.0, 0.5, 0.25, 0.1).rotate("x", -12).translate(0, y, 1.22) for y in (2.45, 3.05)]
    legs = []
    for x in (-3.3, 3.3):
        legs.append(tube([(x, 0.0, -1.0), (x, 1.55, -0.9), (x, 1.6, 0.9), (x, 3.3, 1.35)], 0.13, 8))
        legs.append(tube([(x, 0.0, 0.95), (x, 1.55, 0.9)], 0.12, 8))
        legs.append(tube([(x, 2.25, 1.0), (x, 2.35, -0.6), (x, 1.95, -0.9)], 0.1, 8))  # armrest
        legs.append(rounded_box(0.5, 0.12, 0.5, 0.05, 2).translate(x, 0.06, -1.0))
        legs.append(rounded_box(0.5, 0.12, 0.5, 0.05, 2).translate(x, 0.06, 0.95))
    return {"Bench": merge(*slats, *back), "Legs": merge(*legs)}


def lamp_post():
    pole = lathe([(0.0, 0.0), (0.9, 0.0), (0.9, 0.3), (0.7, 0.45), (0.7, 0.6), (0.42, 0.9), (0.3, 1.4), (0.36, 1.5), (0.26, 1.6),
                  (0.22, 9.4), (0.32, 9.5), (0.22, 9.6), (0.22, 10.1), (0.0, 10.1)], 20)
    frame = [rounded_box(1.4, 0.14, 1.4, 0.05, 2).translate(0, 10.15, 0)]
    frame += [tube([(x, 10.2, z), (x * 1.15, 11.6, z * 1.15)], 0.05, 5) for x in (-0.6, 0.6) for z in (-0.6, 0.6)]
    roof = lathe([(1.05, 0.0), (0.9, 0.1), (0.15, 0.75), (0.0, 0.8)], 4).rotate("y", 45).translate(0, 11.6, 0)
    finial = merge(lathe([(0.12, 0.0), (0.06, 0.3), (0.0, 0.32)], 8).translate(0, 12.35, 0), icosphere(0.14, 1).translate(0, 12.72, 0))
    globe = icosphere(0.5, 2).translate(0, 10.85, 0)
    return {"Pole": merge(pole, *frame, roof, finial), "Lamp": globe}


def gift_box():
    box = rounded_box(4.0, 4.0, 4.0, 0.35).translate(0, 2.0, 0)
    ribbon = [rounded_box(4.3, 4.3, 0.8, 0.3).translate(0, 2.0, 0), rounded_box(0.8, 4.3, 4.3, 0.3).translate(0, 2.0, 0)]
    for angle in (35, -35):
        loop = torus(0.62, 0.22, 22, 8).scale(1.0, 1.0, 0.7).rotate("x", 90).rotate("y", angle)
        ribbon.append(loop.translate(-0.6 if angle > 0 else 0.6, 4.55, 0))
    ribbon.append(icosphere(0.32, 2).translate(0, 4.4, 0))
    for side in (-1, 1):
        ribbon.append(tube([(0, 4.3, 0), (side * 0.6, 4.25, -0.4), (side * 1.0, 4.25, -1.1)], 0.12, 6))
    return {"Box": box, "Ribbon": merge(*ribbon)}


def traffic_cone():
    base = merge(rounded_box(2.4, 0.22, 2.4, 0.15, 3).translate(0, 0.11, 0), lathe([(0.95, 0.22), (0.85, 0.36), (0.0, 0.36)], 24))
    cone_profile = [(0.82, 0.3), (0.7, 0.8), (0.55, 1.4), (0.42, 1.9), (0.29, 2.45), (0.16, 2.92)]
    cone = lathe(cone_profile + [(0.17, 2.97), (0.0, 3.0)], 28)

    def cone_radius(y: float) -> float:
        for (r0, y0), (r1, y1) in zip(cone_profile, cone_profile[1:]):
            if y0 <= y <= y1:
                return lerp(r0, r1, (y - y0) / (y1 - y0))
        return cone_profile[-1][0]

    def band(y0: float, y1: float) -> Mesh:
        out = 0.03
        return lathe([(cone_radius(y0) - 0.01, y0), (cone_radius(y0) + out, y0 + 0.02), (cone_radius(y1) + out, y1 - 0.02), (cone_radius(y1) - 0.01, y1)], 28)

    stripes = [band(1.15, 1.6), band(2.0, 2.35)]
    return {"Cone": merge(base, cone), "Stripe": merge(*stripes)}


def volcano():
    """Backdrop volcano: a craggy faceted cone with gullies, a crater lip, a lava pool in the crater
    and lava runs pouring down the gullies on the front (-Z) side."""
    rng = np.random.default_rng(21)
    phases = rng.uniform(0, 2 * math.pi, 3)
    directions = rng.normal(size=(9, 3))
    directions /= np.linalg.norm(directions, axis=1, keepdims=True)
    frequencies = rng.uniform(0.05, 0.12, 9)
    offsets = rng.uniform(0, 2 * math.pi, 9)
    top = 60.0

    def slope_radius(y):
        return 12.5 + 40.0 * (1 - np.minimum(y, top) / top) ** 1.35

    def gullies(theta, y):
        return 1 + 0.06 * np.sin(5 * theta + phases[0]) + 0.03 * np.sin(11 * theta + 0.06 * y + phases[1])

    def crags(points):
        # Lumpy rock: a few low-frequency waves in 3D, so ledges run every which way (not just down).
        return 1 + 0.11 * np.mean(np.sin(points @ directions.T * frequencies + offsets), axis=1)

    def surface(theta, y, extra=0.0):
        r = slope_radius(y) * gullies(theta, y)
        point = np.array([[np.cos(theta) * r, y, np.sin(theta) * r]])
        r = r * crags(point)[0] + extra
        return (math.cos(theta) * r, y, math.sin(theta) * r)

    profile = [(slope_radius(y), y) for y in np.linspace(0, top, 13)]
    profile += [(11.8, top + 0.8), (10.4, top + 0.3), (8.4, top - 1.8), (6.6, top - 3.4), (0.0, top - 4.0)]
    rock = lathe(profile, 40)
    angle = np.arctan2(rock.v[:, 2], rock.v[:, 0])
    rock.v[:, [0, 2]] *= gullies(angle, rock.v[:, 1])[:, None]
    rock.v[:, [0, 2]] *= crags(rock.v)[:, None]
    rock.smooth = False

    pool = cylinder(9.6, 0.6, 32).translate(0, top - 3.0, 0)
    runs = []
    for start in (205, 248, 292, 335):
        # Snap each run into the nearest gully (where the slope dips inward).
        candidates = np.radians(np.linspace(start - 8, start + 8, 33))
        theta0 = candidates[np.argmin(gullies(candidates, top - 6))]
        end = rng.uniform(4, 24)
        lip = 11.0 * gullies(theta0, top) * crags(np.array([[math.cos(theta0) * 11.0, top, math.sin(theta0) * 11.0]]))[0]
        points = [(math.cos(theta0) * lip, top + 1.1, math.sin(theta0) * lip)]  # spilling over the crater lip
        for y in np.linspace(top - 0.4, end, 18):
            points.append(surface(theta0 + 0.035 * math.sin(0.18 * y), y, 0.5))
        runs.append(tube(points, 1.05, 8))
    return {"Rock": rock, "Lava": merge(pool, *runs)}


def spire():
    """A cluster of jagged volcanic rock spikes for crater rims, faceted like the boulder, with a few
    glowing lava blobs at the foot."""
    spikes = []
    for x, z, height, radius, lean_x, lean_z, seed in (
        (0.0, 0.0, 20.0, 4.6, 0.10, -0.05, 1),
        (4.3, 1.6, 12.5, 3.0, 0.24, 0.10, 2),
        (-3.7, -1.3, 9.5, 2.7, -0.28, -0.12, 3),
        (1.1, -3.8, 6.5, 2.1, 0.05, -0.30, 4),
    ):
        profile = [(radius, 0.0), (radius * 0.86, height * 0.18), (radius * 0.62, height * 0.42), (radius * 0.38, height * 0.68),
                   (radius * 0.15, height * 0.9), (0.0, height)]
        spike = organic_lathe(profile, 7, 0.2, waves=3, seed=seed)
        bend = (spike.v[:, 1] / height) ** 2 * height
        spike.v[:, 0] += lean_x * bend
        spike.v[:, 2] += lean_z * bend
        spikes.append(spike.translate(x, 0, z))
    rock = merge(*spikes)
    rock.smooth = False
    blobs = merge(*(icosphere(r, 1, 0.3, seed=s).scale(1.0, 0.55, 1.0).translate(x, 0.2, z)
                    for s, (x, z, r) in enumerate(((3.2, -2.6, 1.1), (-2.8, 2.4, 0.9), (5.6, -0.6, 0.7)))))
    return {"Rock": rock, "Glow": blobs}


def fire_wheel():
    """The wheel that turns the fire rope: a studded iron rim, eight glowing spokes and a gold hub.
    It stands in the YZ plane with its axle along X; the rope hangs off the rim's inner edge."""
    major = 10.2
    rim = [torus(major, 0.9, 64, 12), torus(major - 1.35, 0.32, 64, 8)]
    rim += [icosphere(0.55, 1).translate(math.cos(a) * (major + 0.62), 0, math.sin(a) * (major + 0.62))
            for a in np.linspace(0, 2 * math.pi, 16, endpoint=False)]
    spokes = [tube([(math.cos(a) * 1.5, 0, math.sin(a) * 1.5), (math.cos(a) * (major - 0.7), 0, math.sin(a) * (major - 0.7))], 0.34, 8)
              for a in np.linspace(0, 2 * math.pi, 8, endpoint=False) + math.pi / 8]
    hub = merge(cylinder(1.7, 2.6, 28, 0.35).translate(0, -1.3, 0), cylinder(0.8, 3.6, 16, 0.2).translate(0, -1.8, 0))
    lift = major + 1.17

    def place(mesh: Mesh) -> Mesh:
        return mesh.rotate("z", 90).translate(0, lift, 0)

    return {"Rim": place(merge(*rim)), "Spokes": place(merge(*spokes)), "Hub": place(hub)}


def honey_tree():
    """Honey Trap's giant tree: flared roots, a gnarled trunk, a leafy crown, a beehive, and a branch
    reaching forward (-Z) whose tip ("Anchor") is where the fruit vine hangs from."""
    trunk = organic_lathe([(9.5, 0.0), (7.2, 1.2), (6.0, 3.0), (5.3, 7.0), (4.9, 14.0), (4.5, 22.0), (3.9, 30.0),
                           (3.1, 36.0), (0.0, 38.5)], 20, 0.12, waves=5, seed=8)
    roots = []
    for index in range(7):
        a = 2 * math.pi * index / 7 + 0.3
        bend = a + 0.15
        roots.append(taper([(math.cos(a) * 3.5, 3.2, math.sin(a) * 3.5), (math.cos(a) * 7.0, 1.2, math.sin(a) * 7.0),
                            (math.cos(bend) * 10.5, 0.3, math.sin(bend) * 10.5), (math.cos(bend) * 12.5, -0.2, math.sin(bend) * 12.5)],
                           1.6, 0.25, 9))
    branches = [
        taper([(0, 25, -2.0), (0, 29.0, -7.0), (0, 31.0, -11.5), (0, 30.6, -14.5)], 1.7, 0.75, 10),  # holds the vine
        taper([(2.0, 28, 0.5), (7.0, 33.5, 1.5), (12.0, 37.5, 2.5)], 1.8, 0.6, 10),
        taper([(-2.0, 29, 0.0), (-7.0, 34.5, -1.0), (-12.5, 38.5, -2.0)], 1.8, 0.6, 10),
        taper([(0, 30, 2.0), (0.5, 35.0, 7.0), (0.5, 39.0, 11.0)], 1.6, 0.6, 10),
        tube([(9.6, 35.0, 2.0), (9.8, 31.8, 2.2)], 0.25, 6),  # hive hanger
    ]
    leaves = merge(
        icosphere(13.0, 3, 0.12, 21).translate(0, 45.0, 0),
        icosphere(9.5, 2, 0.15, 22).translate(-11.5, 41.0, -2.0),
        icosphere(9.5, 2, 0.15, 23).translate(11.5, 41.0, 2.0),
        icosphere(9.0, 2, 0.15, 24).translate(0.5, 41.5, 11.0),
        icosphere(8.5, 2, 0.15, 25).translate(0.0, 40.5, -10.5),
        icosphere(7.0, 2, 0.18, 26).translate(-7.0, 49.0, 6.0),
        icosphere(7.0, 2, 0.18, 27).translate(7.0, 50.0, -5.0),
    )
    hive_profile = [(0.0, 0.0)]
    for i in range(1, 15):
        t = i / 14
        bulge = math.sin(math.pi * t) * 2.9 + 0.3
        ridge = 0.16 if i % 2 == 0 else 0.0  # stacked rings
        hive_profile.append((bulge + ridge, -t * 6.2))
    hive_profile.append((0.0, -6.4))
    hive = lathe(hive_profile[::-1], 22).translate(9.8, 32.2, 2.2)
    anchor = icosphere(0.3, 0).translate(0, 29.6, -14.5)
    return {"Trunk": merge(trunk, *roots, *branches), "Leaves": leaves, "Hive": hive, "Anchor": anchor}


def fruit():
    """A round fruit with a dimpled top, a stem and a leaf (recolored per fruit in-game)."""
    body = lathe([(0.0, 0.15), (0.45, 0.04), (0.85, 0.22), (1.05, 0.62), (1.1, 1.02), (1.0, 1.44), (0.75, 1.74),
                  (0.38, 1.8), (0.0, 1.6)], 24)
    stem = tube([(0, 1.55, 0), (0.05, 1.95, 0.02), (0.14, 2.25, 0.05)], 0.07, 6)
    leaf = icosphere(1.0, 1).scale(0.5, 0.07, 0.24).rotate("z", -25).translate(0.42, 2.08, 0.05)
    return {"Fruit": body, "Stem": merge(stem, leaf)}


def honeycomb():
    """A chunk of honeycomb: seven hexagonal cells with dripping honey; it faces -Z."""
    cells = []
    rng = np.random.default_rng(5)
    radius = 0.56
    centers = [(0.0, 0.0)] + [(math.cos(math.pi / 3 * i + math.pi / 6) * radius * math.sqrt(3),
                                math.sin(math.pi / 3 * i + math.pi / 6) * radius * math.sqrt(3)) for i in range(6)]
    for x, y in centers:
        depth = 0.9 + rng.uniform(-0.12, 0.12)
        cell = lathe([(radius * 0.98, 0.0), (radius * 0.98, depth)], 6, True, True).rotate("y", 30)
        cells.append(cell.translate(0, -depth / 2, 0).rotate("x", 90).translate(x, y + 1.25, 0))
    comb = merge(*cells)
    comb.smooth = False
    # Drips hang from the comb's zigzag bottom edge.
    drips = [capsule(0.55, 0.13, 10).translate(x, y, -0.15) for x, y in ((0.0, -0.5), (-0.84, -0.02), (0.5, -0.22))]
    drips += [icosphere(0.13, 1).translate(x, y, -0.15) for x, y in ((0.0, -0.95), (0.5, -0.66))]
    return {"Comb": comb, "Honey": merge(*drips)}


def bee():
    """A chubby cartoon bee, facing -Z."""
    body = sphere(1.0, 12, 18).scale(0.55, 0.5, 0.72).translate(0, 0.62, 0.05)
    stripes = [torus(0.53, 0.07, 22, 6).rotate("x", 90).scale(1.0, 0.92, 1.0).translate(0, 0.62, z) for z in (-0.12, 0.26)]
    head = sphere(0.36, 10, 14).translate(0, 0.72, -0.72)
    stinger = lathe([(0.12, 0.0), (0.0, 0.32)], 8).rotate("x", 90).translate(0, 0.6, 0.72)
    antennae = [tube([(side * 0.12, 0.98, -0.85), (side * 0.22, 1.25, -1.0)], 0.035, 5) for side in (-1, 1)]
    wings = [icosphere(1.0, 2).scale(0.42, 0.04, 0.26).rotate("z", side * 25).translate(side * 0.42, 1.12, 0.0)
             for side in (-1, 1)]
    return {"Body": body, "Stripes": merge(*stripes, head, stinger, *antennae), "Wings": merge(*wings)}


def basket():
    """A woven fruit basket with a rolled rim and two weave bands."""
    bowl = lathe([(0.0, 0.0), (1.25, 0.0), (1.55, 0.25), (1.8, 1.3), (1.86, 1.45), (1.72, 1.45), (1.66, 1.32),
                  (1.43, 0.35), (1.15, 0.16), (0.0, 0.16)], 28)
    rim = torus(1.8, 0.13, 32, 8).translate(0, 1.46, 0)
    bands = [torus(1.62 + 0.18 * y, 0.06, 32, 6).translate(0, y, 0) for y in (0.5, 0.95)]
    return {"Basket": bowl, "Rim": merge(rim, *bands)}


def dice_block():
    """The 1-or-2 block that floats over the player whose turn it is (numbers are added in-game)."""
    return {"Block": rounded_box(4.0, 4.0, 4.0, 0.7)}


PROPS = {
    "ShoppingCart": shopping_cart,
    "YeetGlove": yeet_glove,
    "Anvil": anvil,
    "Boulder": boulder,
    "MalletHead": mallet_head,
    "Treasure": treasure,
    "Chest": chest,
    "Trophy": trophy,
    "Tree": tree,
    "Bush": bush,
    "Balloon": balloon,
    "Bench": bench,
    "LampPost": lamp_post,
    "GiftBox": gift_box,
    "Cone": traffic_cone,
    "Volcano": volcano,
    "Spire": spire,
    "FireWheel": fire_wheel,
    "HoneyTree": honey_tree,
    "Fruit": fruit,
    "Honeycomb": honeycomb,
    "Bee": bee,
    "Basket": basket,
    "DiceBlock": dice_block,
}

# Preview colors baked into the files' materials (the game recolors pieces by name anyway).
COLORS = {
    "Basket": (205, 215, 225), "Chassis": (150, 155, 170), "Frame": (230, 60, 70), "Wheels": (40, 40, 50), "Flowers": (255, 130, 190), "Glove": (235, 50, 70),
    "Cuff": (250, 250, 250), "Anvil": (70, 72, 82), "Rock": (140, 120, 105), "Head": (255, 90, 80),
    "Bands": (255, 235, 200), "Gold": (255, 205, 50), "Body": (150, 95, 55), "Lid": (120, 75, 45),
    "Trim": (255, 205, 60), "Cup": (255, 200, 50), "Base": (60, 50, 80), "Trunk": (120, 80, 50),
    "Leaves": (80, 190, 90), "Balloon": (255, 90, 140), "String": (240, 240, 240), "Bench": (190, 130, 80),
    "Legs": (70, 70, 80), "Pole": (60, 60, 75), "Lamp": (255, 235, 180), "Box": (120, 90, 255),
    "Ribbon": (255, 220, 70), "Cone": (255, 130, 40), "Stripe": (250, 250, 250),
    "Lava": (255, 120, 40), "Glow": (255, 130, 40), "Rim": (70, 55, 62), "Spokes": (255, 140, 50), "Hub": (255, 200, 60),
    "Hive": (240, 175, 60), "Anchor": (120, 80, 50), "Fruit": (235, 60, 60), "Stem": (90, 140, 50), "Comb": (240, 170, 40),
    "Honey": (255, 200, 60), "Stripes": (40, 30, 30), "Wings": (240, 250, 255), "Block": (255, 210, 60),
}


# ====================================================================== export

def write_obj(path: Path, pieces: dict[str, Mesh]):
    lines = [f"# Party Panic prop: {path.stem} (generated by tools/meshgen/generate_meshes.py)", f"mtllib {path.stem}.mtl"]
    mtl = []
    v_offset = 1
    for name, mesh in pieces.items():
        positions, normals, faces = mesh.normals()
        lines.append(f"o {name}")
        lines.append(f"g {name}")
        lines.append(f"usemtl {name}")
        lines += [f"v {x:.4f} {y:.4f} {z:.4f}" for x, y, z in positions]
        lines += [f"vn {x:.4f} {y:.4f} {z:.4f}" for x, y, z in normals]
        lines += [f"f {a + v_offset}//{a + v_offset} {b + v_offset}//{b + v_offset} {c + v_offset}//{c + v_offset}" for a, b, c in faces]
        v_offset += len(positions)
        r, g, b = (c / 255 for c in COLORS.get(name, (200, 200, 200)))
        mtl += [f"newmtl {name}", f"Kd {r:.3f} {g:.3f} {b:.3f}", "Ka 0 0 0", "Ks 0.1 0.1 0.1", "d 1", ""]
    path.write_text("\n".join(lines) + "\n")
    path.with_suffix(".mtl").write_text("\n".join(mtl))


def write_glb(path: Path, pieces: dict[str, Mesh]):
    binary = bytearray()
    buffer_views, accessors, meshes, nodes, materials = [], [], [], [], []

    def add_view(data: bytes, target: int) -> int:
        while len(binary) % 4:
            binary.append(0)
        buffer_views.append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(data), "target": target})
        binary.extend(data)
        return len(buffer_views) - 1

    for index, (name, mesh) in enumerate(pieces.items()):
        positions, normals, faces = mesh.normals()
        pos = positions.astype("<f4")
        nrm = normals.astype("<f4")
        idx = faces.astype("<u4").reshape(-1)
        pos_view = add_view(pos.tobytes(), 34962)
        nrm_view = add_view(nrm.tobytes(), 34962)
        idx_view = add_view(idx.tobytes(), 34963)
        accessors += [
            {"bufferView": pos_view, "componentType": 5126, "count": len(pos), "type": "VEC3", "min": pos.min(axis=0).tolist(), "max": pos.max(axis=0).tolist()},
            {"bufferView": nrm_view, "componentType": 5126, "count": len(nrm), "type": "VEC3"},
            {"bufferView": idx_view, "componentType": 5125, "count": len(idx), "type": "SCALAR"},
        ]
        r, g, b = (c / 255 for c in COLORS.get(name, (200, 200, 200)))
        materials.append({"name": name, "pbrMetallicRoughness": {"baseColorFactor": [r, g, b, 1], "metallicFactor": 0, "roughnessFactor": 0.6}})
        base = index * 3
        meshes.append({"name": name, "primitives": [{"attributes": {"POSITION": base, "NORMAL": base + 1}, "indices": base + 2, "material": index}]})
        nodes.append({"name": name, "mesh": index})

    while len(binary) % 4:
        binary.append(0)
    gltf = {
        "asset": {"version": "2.0", "generator": "Party Panic meshgen"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": meshes,
        "materials": materials,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(binary)}],
    }
    json_bytes = json.dumps(gltf, separators=(",", ":")).encode()
    while len(json_bytes) % 4:
        json_bytes += b" "
    total = 12 + 8 + len(json_bytes) + 8 + len(binary)
    with open(path, "wb") as handle:
        handle.write(struct.pack("<III", 0x46546C67, 2, total))
        handle.write(struct.pack("<II", len(json_bytes), 0x4E4F534A))
        handle.write(json_bytes)
        handle.write(struct.pack("<II", len(binary), 0x004E4942))
        handle.write(binary)


def load_mode_props() -> None:
    """Adds the props in tools/meshgen/props/*.py (one file per mini-game, so modes built side by
    side never edit the same file). Each defines PROPS = {name: builder} and may define COLORS."""
    import importlib.util

    for path in sorted((Path(__file__).resolve().parent / "props").glob("*.py")):
        spec = importlib.util.spec_from_file_location(f"mode_props_{path.stem}", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        for name, build in getattr(module, "PROPS", {}).items():
            if name in PROPS:
                raise SystemExit(f"{path.name} redefines prop {name}")
            PROPS[name] = build
        COLORS.update(getattr(module, "COLORS", {}))


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Generate prop meshes into assets/meshes.")
    parser.add_argument("--only", help="comma-separated prop names (default: all)")
    args = parser.parse_args()
    load_mode_props()
    wanted = set(args.only.split(",")) if args.only else None
    if wanted and wanted - set(PROPS):
        raise SystemExit(f"Unknown props: {', '.join(sorted(wanted - set(PROPS)))}")
    OUT.mkdir(parents=True, exist_ok=True)
    sys.path.insert(0, str(ROOT / "tools" / "checks"))
    from mesh_orientation import inside_out_parts

    for name, build in PROPS.items():
        if wanted and name not in wanted:
            continue
        pieces = build()
        write_obj(OUT / f"{name}.obj", pieces)
        write_glb(OUT / f"{name}.glb", pieces)
        for piece, mesh in pieces.items():
            positions, _, faces = mesh.normals()
            bad, closed = inside_out_parts(positions, faces)
            if bad:
                print(f"WARNING {name}.{piece}: {bad} of {closed} closed parts are inside-out (faces point inward)")
        tris = sum(len(m.f) for m in pieces.values())
        bounds = np.vstack([m.v for m in pieces.values()])
        size = bounds.max(axis=0) - bounds.min(axis=0)
        print(f"{name:13s} {tris:6d} tris  size {size[0]:.1f} x {size[1]:.1f} x {size[2]:.1f}  pieces: {', '.join(pieces)}")


if __name__ == "__main__":
    main()
