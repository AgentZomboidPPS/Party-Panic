"""Props for Prime Cut: six grilled steaks (each a different shape, with grill marks and a fat cap), the
giant chef's knife each team steers, the team grill, and the backyard (picket fence, string lights,
picnic table, cooler, sauce bottles).

The steak shapes live here and nowhere else. Each is drawn as a 2D mask (unions of circles, ellipses
and polygons), its corners are rounded with distance transforms and its outline is traced from the
result. That one outline is used twice, so they always match:
  * the steak mesh (the outline extruded with soft seared edges, a domed top, grill marks),
  * the shape the server splits: building any steak writes the outlines into the GENERATED STEAKS
    block of src/shared/Logic/PrimeCut.luau.

Steak coordinates (x, z) are the mesh's own (studs, +Y up, base on y = 0); the middle of the outline's
bounding box is 0, 0, which is where MeshLibrary puts the prop's pivot.

    python3 tools/meshgen/generate_meshes.py --only PrimeCutRibeye,PrimeCutKnife,PrimeCutGrill,...
"""

from __future__ import annotations

import math
import re
from pathlib import Path

import numpy as np
from scipy import ndimage
from scipy.spatial import Delaunay
from skimage import measure

from generate_meshes import Mesh, cylinder, extrude, icosphere, lathe, merge, rounded_box, sphere, tube

ROOT = Path(__file__).resolve().parents[3]
LUAU_MODULE = ROOT / "src" / "shared" / "Logic" / "PrimeCut.luau"

RES = 0.03  # studs per cell of the 2D shape grids
EXT = 9.6  # shape grids cover [-EXT, EXT]
OUTLINE_SPACING = 0.3  # spacing of the outline the server splits

# ====================================================================== 2D shape fields


def grid(ext: float = EXT, res: float = RES):
    n = int(round(2 * ext / res)) + 1
    axis = -ext + np.arange(n) * res
    U, V = np.meshgrid(axis, axis)  # rows follow v (= z), columns follow u (= x)
    return U, V


U, V = grid()


def circle(cu, cv, r):
    return (U - cu) ** 2 + (V - cv) ** 2 <= r * r


def ellipse(cu, cv, a, b, angle=0.0):
    c, s = math.cos(angle), math.sin(angle)
    du, dv = U - cu, V - cv
    x, y = du * c + dv * s, -du * s + dv * c
    return (x / a) ** 2 + (y / b) ** 2 <= 1


def box(u0, v0, u1, v1):
    return (U >= u0) & (U <= u1) & (V >= v0) & (V <= v1)


def polygon(points):
    inside = np.zeros(U.shape, bool)
    n = len(points)
    for i in range(n):
        (u1, v1), (u2, v2) = points[i], points[(i + 1) % n]
        if v1 == v2:
            continue
        crosses = (v1 > V) != (v2 > V)
        at = (u2 - u1) * (V - v1) / (v2 - v1) + u1
        inside ^= crosses & (U < at)
    return inside


def _edt(mask, res=RES):
    """Distance (studs) from every True cell to the nearest False cell."""
    return ndimage.distance_transform_edt(mask) * res


def rounded(mask, convex=0.0, concave=0.0, res=RES):
    """Rounds convex corners (an opening) and concave corners (a closing) with these radii."""
    if concave > 0:
        grown = _edt(~mask, res) <= concave
        mask = _edt(grown, res) > concave
    if convex > 0:
        core = _edt(mask, res) > convex
        mask = _edt(~core, res) <= convex
    return mask


def field(mask, res=RES):
    """Signed distance to the mask's edge: negative inside."""
    return _edt(~mask, res) - _edt(mask, res)


def sample(f, u, v, ext=EXT, res=RES):
    """Bilinear lookup of a field at arbitrary (u, v)."""
    rows = (np.asarray(v, float) + ext) / res
    cols = (np.asarray(u, float) + ext) / res
    return ndimage.map_coordinates(f, [np.atleast_1d(rows), np.atleast_1d(cols)], order=1, mode="nearest")


def area(loop):
    u, v = loop[:, 0], loop[:, 1]
    return 0.5 * float(np.sum(u * np.roll(v, -1) - np.roll(u, -1) * v))


def resample(loop, spacing):
    closed = np.vstack([loop, loop[:1]])
    seg = np.linalg.norm(np.diff(closed, axis=0), axis=1)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    n = max(12, int(round(s[-1] / spacing)))
    t = np.linspace(0, s[-1], n, endpoint=False)
    return np.stack([np.interp(t, s, closed[:, 0]), np.interp(t, s, closed[:, 1])], 1)


def smooth_loop(loop, iterations=2):
    for _ in range(iterations):
        loop = (np.roll(loop, 1, 0) + 2 * loop + np.roll(loop, -1, 0)) / 4
    return loop


def _inside(loop, point):
    u, v = point
    inside = False
    n = len(loop)
    for i in range(n):
        (u1, v1), (u2, v2) = loop[i], loop[(i + 1) % n]
        if (v1 > v) != (v2 > v) and u < (u2 - u1) * (v - v1) / (v2 - v1) + u1:
            inside = not inside
    return inside


def loops(f, level=0.0, spacing=0.12, ext=EXT, res=RES):
    """Closed contours of a field at `level`: the outer ones counter-clockwise, holes clockwise
    (material always on the left), resampled evenly."""
    found = []
    for contour in measure.find_contours(f, level):
        if len(contour) < 8 or np.linalg.norm(contour[0] - contour[-1]) > 2:
            continue
        pts = np.stack([-ext + contour[:, 1] * res, -ext + contour[:, 0] * res], 1)[:-1]
        if abs(area(pts)) < 0.05:
            continue
        found.append(pts)
    found.sort(key=lambda pts: -abs(area(pts)))
    result = []
    for index, pts in enumerate(found):
        is_hole = index > 0 and _inside(found[0], pts.mean(axis=0))
        pts = resample(pts, spacing)
        pts = smooth_loop(pts, 1)
        if (area(pts) > 0) == is_hole:
            pts = pts[::-1].copy()
        result.append(pts)
    return result


def normals(loop):
    """Outward normals of a loop with its material on the left."""
    t = np.roll(loop, -1, 0) - np.roll(loop, 1, 0)
    n = np.stack([t[:, 1], -t[:, 0]], 1)
    return n / (np.linalg.norm(n, axis=1, keepdims=True) + 1e-12)


def smoothstep(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


# ====================================================================== 3D from 2D (x = u, z = v)


def to3d(u, y, v):
    return np.stack([u, y, v], -1)


def _orient(mesh: Mesh, outward) -> Mesh:
    """Flips faces whose normals disagree with `outward(face centers) -> directions`."""
    tri = mesh.v[mesh.f]
    n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    wanted = outward(tri.mean(axis=1))
    flip = np.sum(n * wanted, axis=1) < 0
    mesh.f[flip] = mesh.f[flip][:, ::-1]
    return mesh


def sweep(rings_2d, profile, base=None):
    """A soft-edged slab wall: for every loop and every (inset, y) profile point, a ring moved
    `inset` studs into the material at height y (+ base(u, v))."""
    meshes = []
    for loop in rings_2d:
        n2 = normals(loop)
        verts = []
        for inset, y in profile:
            ring = loop - n2 * inset
            height = np.full(len(ring), float(y))
            if base is not None:
                height = height + base(ring[:, 0], ring[:, 1])
            verts.append(to3d(ring[:, 0], height, ring[:, 1]))
        verts = np.vstack(verts)
        count = len(loop)
        faces = []
        for j in range(len(profile) - 1):
            for i in range(count):
                a = j * count + i
                b = j * count + (i + 1) % count
                c = a + count
                d = b + count
                faces += [(a, b, c), (b, d, c)]
        mesh = Mesh(verts, faces)
        loop3 = to3d(loop[:, 0], np.zeros(count), loop[:, 1])
        out3 = to3d(n2[:, 0], np.zeros(count), n2[:, 1])
        mid = np.mean([p[1] for p in profile])

        def outward(centers, loop3=loop3, out3=out3, mid=mid, base=base):
            d = np.linalg.norm(centers[:, None, [0, 2]] - loop3[None, :, [0, 2]], axis=2)
            nearest = out3[np.argmin(d, axis=1)]
            lift = mid + (base(centers[:, 0], centers[:, 2]) if base is not None else 0)
            up = (centers[:, 1] - lift)[:, None] * np.array([0, 1.0, 0])
            return nearest + up * 2.5

        meshes.append(_orient(mesh, outward))
    return merge(*meshes)


def cap(rings_2d, f, level, height, spacing, up=True, jitter_seed=1, ext=EXT, res=RES):
    """Fills the region inside `rings_2d` (the field `f` is below `level` there) with triangles at
    height(u, v). Interior points on a jittered grid let the surface bulge."""
    boundary = np.vstack(rings_2d)
    lo, hi = boundary.min(axis=0), boundary.max(axis=0)
    rng = np.random.default_rng(jitter_seed)
    gu, gv = np.meshgrid(np.arange(lo[0], hi[0], spacing), np.arange(lo[1], hi[1], spacing))
    pts = np.stack([gu.ravel(), gv.ravel()], 1) + rng.uniform(-0.12, 0.12, (gu.size, 2)) * spacing
    keep = sample(f, pts[:, 0], pts[:, 1], ext, res) < level - spacing * 0.45
    points = np.vstack([boundary, pts[keep]])
    tri = Delaunay(points).simplices
    centers = points[tri].mean(axis=1)
    tri = tri[sample(f, centers[:, 0], centers[:, 1], ext, res) < level + 0.01]
    y = height(points[:, 0], points[:, 1])
    mesh = Mesh(to3d(points[:, 0], y, points[:, 1]), tri)
    sign = 1.0 if up else -1.0
    return _orient(mesh, lambda c: np.tile([0, sign, 0], (len(c), 1)))


def slab(f, thickness, top_radius, bottom_radius=0.0, spacing=0.12, cap_spacing=0.3, dome=0.0, dome_depth=1.5,
         base=None, steps=6, bottom=True, bottom_spacing=None, level=0.0, ext=EXT, res=RES):
    """A slab whose outline is the field's `level` contour: soft rounded top edge, optional rounded
    bottom edge, a domed top, optionally standing on base(u, v). Returns (mesh, top(u, v), outline)."""
    outline = loops(f, level, spacing, ext, res)
    profile = []
    if bottom_radius > 0:
        for k in range(steps + 1):
            a = math.pi / 2 * k / steps
            profile.append((bottom_radius - bottom_radius * math.sin(a), bottom_radius - bottom_radius * math.cos(a)))
    else:
        profile.append((0.0, 0.0))
    for k in range(steps + 1):
        a = math.pi / 2 * k / steps
        profile.append((top_radius - top_radius * math.cos(a), thickness - top_radius + top_radius * math.sin(a)))
    base_fn = base if base is not None else (lambda u, v: np.zeros(np.shape(u)))
    inner = top_radius

    def top(u, v):
        depth = -sample(f, u, v, ext, res) + level - inner
        return base_fn(u, v) + thickness + dome * smoothstep(depth / dome_depth)

    walls = sweep(outline, profile, base)
    inner_rings = [loop - normals(loop) * inner for loop in outline]
    lid = cap(inner_rings, f, level - inner, top, cap_spacing, True, ext=ext, res=res)
    parts = [walls, lid]
    if bottom:
        bottom_rings = [loop - normals(loop) * profile[0][0] for loop in outline]
        parts.append(cap(bottom_rings, f, level - profile[0][0], lambda u, v: base_fn(u, v) + profile[0][1],
                         bottom_spacing or cap_spacing * 2, False, ext=ext, res=res))
    return merge(*parts), top, outline


# ====================================================================== steaks
# Each steak: its mask (about 15 x 12 studs before centring), how much to round it, and where its fat
# cap runs (a direction from the middle: the rim facing that way, `spread` radians either side).

STEAK_THICKNESS = 1.45
STEAK_DOME = 0.28


def ribeye():
    m = ellipse(0.4, 0.0, 6.4, 5.0, 0.12) | ellipse(-4.2, 2.6, 3.4, 2.9, 0.4) | ellipse(3.6, -2.8, 3.0, 2.4, -0.3)
    m &= ~circle(2.2, 6.3, 2.2)
    return rounded(m, convex=1.0, concave=1.6), (-0.75, 2.0, 1.0)


def strip():
    m = polygon([(-7.2, -4.4), (5.6, -5.2), (7.5, -1.6), (6.4, 3.0), (2.0, 5.4), (-5.2, 4.9), (-7.6, 1.4)])
    return rounded(m, convex=2.0, concave=1.0), (-1.62, 2.0, 0.9)


def tritip():
    m = ellipse(-2.8, 0.9, 5.6, 2.9, 0.62) | ellipse(3.0, -1.5, 5.4, 2.7, -0.38) | circle(0.0, -0.4, 2.6)
    return rounded(m, convex=1.1, concave=1.4), (1.1, 2.0, 0.75)


def kidney():
    m = ellipse(0.0, 0.0, 7.2, 5.0) & ~ellipse(0.6, 6.1, 3.6, 3.1) | circle(-5.6, 1.6, 2.4)
    return rounded(m, convex=1.0, concave=1.5), None


def heart():
    m = circle(-3.2, -1.6, 3.9) | circle(3.2, -1.6, 3.9) | polygon([(-6.8, -0.6), (6.8, -0.6), (0.0, 6.8)])
    return rounded(m, convex=1.3, concave=1.3), None


def chuck():
    m = box(-6.8, -5.0, 1.2, 5.2) | box(-6.8, -5.0, 7.2, -0.6) | circle(5.0, -2.9, 2.5) | circle(-4.0, 3.6, 2.6)
    return rounded(m, convex=2.2, concave=1.9), (-2.6, 2.0, 0.9)


STEAKS = {
    "Ribeye": ribeye,
    "Strip": strip,
    "TriTip": tritip,
    "Kidney": kidney,
    "Heart": heart,
    "Chuck": chuck,
}

_steak_cache: dict[str, tuple] = {}


def _centred(mask):
    """Shifts a mask so the middle of its bounding box is at 0, 0 (to the grid cell)."""
    rows, cols = np.nonzero(mask)
    du = (U[0, cols.min()] + U[0, cols.max()]) / 2
    dv = (V[rows.min(), 0] + V[rows.max(), 0]) / 2
    shift_cols = int(round(du / RES))
    shift_rows = int(round(dv / RES))
    return np.roll(np.roll(mask, -shift_rows, axis=0), -shift_cols, axis=1)


def steak_shape(name):
    """(mask, field, outline, fat sector) for a steak, with its outline centred on its bounding box."""
    if name in _steak_cache:
        return _steak_cache[name]
    mask, fat = STEAKS[name]()
    mask = _centred(mask)
    f = field(mask)
    outline = loops(f, 0.0, OUTLINE_SPACING)[0]
    # The traced outline's bounding box is a hair off the mask's: centre it exactly on 0, 0 and
    # build everything from the shifted field, so the mesh and the outline share one frame.
    lo, hi = outline.min(axis=0), outline.max(axis=0)
    shift = (lo + hi) / 2
    outline = outline - shift
    f = ndimage.shift(f, (-shift[1] / RES, -shift[0] / RES), order=1, mode="nearest")
    _steak_cache[name] = (mask, f, outline, fat)
    return _steak_cache[name]


def steak_slab(f):
    """A steak's slab split into (walls + bottom, top(u, v), lid)."""
    thickness, top_radius, bottom_radius, steps = STEAK_THICKNESS, 0.5, 0.28, 4
    outline = loops(f, 0.0, 0.2)
    profile = []
    for k in range(steps + 1):
        a = math.pi / 2 * k / steps
        profile.append((bottom_radius - bottom_radius * math.sin(a), bottom_radius - bottom_radius * math.cos(a)))
    for k in range(steps + 1):
        a = math.pi / 2 * k / steps
        profile.append((top_radius - top_radius * math.cos(a), thickness - top_radius + top_radius * math.sin(a)))

    def top(u, v):
        depth = -sample(f, u, v) - top_radius
        return thickness + STEAK_DOME * smoothstep(depth / 2.4)

    walls = sweep(outline, profile)
    lid = cap([loop - normals(loop) * top_radius for loop in outline], f, -top_radius, top, 0.42, True)
    bottom = cap([loop - normals(loop) * bottom_radius for loop in outline], f, -bottom_radius,
                 lambda u, v: np.zeros(np.shape(u)), 0.9, False)
    return merge(walls, bottom), top, lid


def steak(name):
    write_luau_steaks()
    _, f, outline, fat = steak_shape(name)
    inside = f < 0
    # The fat cap: the rim facing one way, about a stud wide, its ends tapering into the meat.
    if fat is not None:
        direction, reach, spread = fat
        angle = np.arctan2(V, U)
        gap = np.abs((angle - direction + np.pi) % (2 * np.pi) - np.pi)
        width = 1.0 * smoothstep((spread - gap) / 0.4 + 0.25)
        fat_mask = inside & (-f < width) & (gap < spread + 0.2) & (np.hypot(U, V) > reach)
        fat_mask = rounded(fat_mask, convex=0.25)
    else:
        fat_mask = np.zeros(U.shape, bool)
    meat_mask = inside & ~fat_mask
    meat_f = field(rounded(meat_mask, convex=0.2))
    pieces = {}
    # The seared sides and bevel (Crust) and the top (Meat) are separate pieces, so they can differ.
    crust, top, meat = steak_slab(meat_f)
    pieces["Crust"] = crust
    pieces["Meat"] = meat
    if fat_mask.any():
        fat_f = field(fat_mask)
        fat_mesh, _, _ = slab(fat_f, STEAK_THICKNESS - 0.04, 0.42, 0.26, spacing=0.2, cap_spacing=0.3, steps=4)
        pieces["Fat"] = fat_mesh

    # Grill marks: diagonal bars seared into the top, hugging its dome.
    diag = (U + V) / math.sqrt(2)
    phase = np.abs((diag + 0.6) % 2.3 - 1.15)
    bars = (phase < 0.24) & (f < -0.95) & ~fat_mask
    if bars.any():
        bar_f = field(rounded(bars, convex=0.12))
        marks, _, _ = slab(bar_f, 0.07, 0.035, 0.0, spacing=0.16, cap_spacing=0.3, steps=2, bottom=False,
                           base=lambda u, v: top(u, v) - 0.03)
        pieces["Marks"] = marks
    return pieces


def write_luau_steaks():
    """Writes every steak's outline into the GENERATED STEAKS block of the shared Luau module."""
    entries = []
    for name in STEAKS:
        _, _, outline, _ = steak_shape(name)
        points = " ".join(f"{u:.2f} {v:.2f}" for u, v in outline)
        entries.append(
            "\t{\n"
            f'\t\tId = "{name}",\n'
            f'\t\tProp = "PrimeCut{name}",\n'
            f"\t\tPoints = \"{points}\",\n"
            "\t},"
        )
    block = "PrimeCut.Steaks = {\n" + "\n".join(entries) + "\n}"
    source = LUAU_MODULE.read_text()
    updated = re.sub(
        r"(-- BEGIN GENERATED STEAKS[^\n]*\n).*?(\n-- END GENERATED STEAKS)",
        lambda m: m.group(1) + block + m.group(2),
        source,
        flags=re.S,
    )
    if updated != source:
        LUAU_MODULE.write_text(updated)


# ====================================================================== the knife
# A giant chef's knife lying on its edge: the blade's middle plane is x = 0 (the cut), the edge runs
# along y = 0 from the heel (z = 7) to the tip (z = -10.5), the handle points +Z (at the players).

def _blade_mask():
    # Side view in (u, v) = (z, y): straight edge, a curve up to the tip, a straight spine sloping down.
    pts = []
    for k in range(13):
        t = k / 12
        pts.append((-4.0 - 6.5 * t, 2.35 * (t ** 1.9)))  # the edge curving up to the tip
    pts.append((-10.55, 2.45))
    for k in range(9):
        t = k / 8
        pts.append((-10.2 + 6.0 * t, 2.55 + 0.75 * (1 - (1 - t) ** 2)))  # spine rising from the tip
    pts += [(-4.0, 3.3), (7.0, 3.3), (7.0, 0.0)]
    return pts


BLADE_MID = -1.775  # the edge's middle (z): the grid is centred on it while the blade is drawn


def knife():
    pieces = {}
    # Work on the shared grid with u = z and v = y (side view, centred on the grid), then stand the
    # slabs up: (u, height, v) -> (x = height - thickness / 2, y = v + 1.65, z = u + BLADE_MID), an
    # even swap of axes, so the faces stay outward.
    side = polygon([(z - BLADE_MID, y - 1.65) for z, y in _blade_mask()])
    side = rounded(side, convex=0.18)
    edge_band = side & (V < -1.65 + 0.42)
    blade_f = field(side & ~edge_band)
    edge_f = field(side & (V < -1.65 + 0.5))
    blade, _, _ = slab(blade_f, 0.34, 0.15, 0.15, spacing=0.2, cap_spacing=0.6, steps=3)
    edge, _, _ = slab(edge_f, 0.18, 0.08, 0.08, spacing=0.2, cap_spacing=0.6, steps=2)

    def stand(mesh: Mesh, thickness: float) -> Mesh:
        v = mesh.v.copy()
        mesh.v = np.stack([v[:, 1] - thickness / 2, v[:, 2] + 1.65, v[:, 0] + BLADE_MID], 1)
        return mesh

    pieces["Blade"] = stand(blade, 0.34)
    pieces["Edge"] = stand(edge, 0.18)
    # Bolster, handle and rivets.
    bolster = rounded_box(0.9, 2.9, 0.9, 0.3).translate(0, 1.75, 7.35)
    handle_core = rounded_box(1.25, 2.2, 6.6, 0.55)
    handle_core.v[:, 1] += 0.18 * np.cos((handle_core.v[:, 2]) / 3.3 * math.pi / 2)  # a slight belly
    handle = handle_core.translate(0, 1.55, 11.1)
    pieces["Metal"] = bolster
    pieces["Handle"] = handle
    rivets = []
    for z in (9.0, 11.1, 13.2):
        for side_x in (-1, 1):
            rivet = cylinder(0.28, 0.14, 14).rotate("z", 90).translate(0.07 + side_x * 0.6, 1.6, z)
            rivets.append(rivet)
    pieces["Rivets"] = merge(*rivets)
    return pieces


def rbox(sx, sy, sz, r, n=3):
    """A rounded box with few segments (the backyard has many of them)."""
    return rounded_box(sx, sy, sz, r, n)


# ====================================================================== the grill
# A giant enamelled barrel grill (the team's color) on a cart: the grate's top is at y = GRATE_TOP and
# its middle at x = z = 0, where the steak lies. The front (-Z) has the knobs; the hood stands open at
# the back.

GRATE_TOP = 4.5
TUB_X, TUB_Z = 25.6, 18.6  # outer size of the firebox
TUB_TOP = 4.85


def crescent_shell(outer, inner, x0, x1):
    """A closed shell along X between two arcs (lists of (z, y), same count): the outer surface, the
    inner one, both end strips and both caps."""
    n = len(outer)
    verts = []
    for x in (x0, x1):
        verts += [(x, y, z) for z, y in outer]
        verts += [(x, y, z) for z, y in inner]

    def o(side, i):
        return side * 2 * n + i

    def k(side, i):
        return side * 2 * n + n + i

    faces = []
    for i in range(n - 1):
        faces += [(o(0, i), o(1, i), o(0, i + 1)), (o(0, i + 1), o(1, i), o(1, i + 1))]
        faces += [(k(0, i), k(0, i + 1), k(1, i)), (k(0, i + 1), k(1, i + 1), k(1, i))]
        faces += [(o(0, i), o(0, i + 1), k(0, i)), (o(0, i + 1), k(0, i + 1), k(0, i))]
        faces += [(o(1, i), k(1, i), o(1, i + 1)), (o(1, i + 1), k(1, i), k(1, i + 1))]
    for i in (0, n - 1):
        faces += [(o(0, i), k(0, i), o(1, i)), (k(0, i), k(1, i), o(1, i))]
    return Mesh(verts, faces)


def grill():
    pieces = {}
    wall = 0.45
    half_x, half_z = TUB_X / 2, TUB_Z / 2
    tub_bottom = 1.95
    height = TUB_TOP - tub_bottom
    mid_y = tub_bottom + height / 2
    enamel = [
        rbox(TUB_X, height, wall, 0.2).translate(0, mid_y, -half_z + wall / 2),
        rbox(TUB_X, height, wall, 0.2).translate(0, mid_y, half_z - wall / 2),
        rbox(wall, height, TUB_Z, 0.2).translate(-half_x + wall / 2, mid_y, 0),
        rbox(wall, height, TUB_Z, 0.2).translate(half_x - wall / 2, mid_y, 0),
        rbox(TUB_X - 0.2, 0.45, TUB_Z - 0.2, 0.2).translate(0, tub_bottom + 0.22, 0),
    ]
    # The hood: a barrel lid hinged at the back edge, swung open 110 degrees so it stands behind.
    hinge_z, hinge_y = half_z - 0.1, TUB_TOP + 0.05
    swing = math.radians(110)
    outer, inner = [], []
    for k in range(25):
        theta = math.pi * k / 24
        for radius_z, radius_y, ring in ((half_z, 4.6, outer), (half_z - 0.4, 4.2, inner)):
            z = radius_z * math.cos(theta)
            y = radius_y * math.sin(theta)
            dz, dy = z - hinge_z, y + TUB_TOP - hinge_y
            ring.append((hinge_z + dz * math.cos(swing) + dy * math.sin(swing),
                         hinge_y - dz * math.sin(swing) + dy * math.cos(swing)))
    hood = crescent_shell(outer, inner, -half_x + 0.1, half_x - 0.1)
    enamel.append(hood)
    pieces["Enamel"] = merge(*enamel)

    # Steel: the lip round the firebox, the hood's handle, side shelves, the front panel.
    steel = [
        rbox(TUB_X + 0.5, 0.28, 0.85, 0.12).translate(0, TUB_TOP + 0.1, -half_z + 0.3),
        rbox(TUB_X + 0.5, 0.28, 0.85, 0.12).translate(0, TUB_TOP + 0.1, half_z - 0.3),
        rbox(0.85, 0.28, TUB_Z + 0.5, 0.12).translate(-half_x + 0.3, TUB_TOP + 0.1, 0),
        rbox(0.85, 0.28, TUB_Z + 0.5, 0.12).translate(half_x - 0.3, TUB_TOP + 0.1, 0),
    ]
    top_edge = outer[-1]  # the hood's free edge (theta = pi: the old front edge, now high at the back)
    steel.append(tube([(x, top_edge[1] + 0.9, top_edge[0] + 0.25) for x in (-7.0, 7.0)], 0.32, 10))
    for x in (-7.0, 7.0):
        steel.append(tube([(x, top_edge[1] - 0.05, top_edge[0] + 0.05), (x, top_edge[1] + 0.9, top_edge[0] + 0.25)],
                          0.22, 8))
    for side in (-1, 1):
        shelf_x = side * (half_x + 2.45)
        steel.append(rbox(4.7, 0.36, 14.0, 0.15).translate(shelf_x, TUB_TOP - 0.25, 0))
        steel.append(rbox(0.3, 1.4, 0.3, 0.1).translate(side * (half_x + 0.45), TUB_TOP - 1.0, -5.5))
        steel.append(rbox(0.3, 1.4, 0.3, 0.1).translate(side * (half_x + 0.45), TUB_TOP - 1.0, 5.5))
        steel.append(tube([(shelf_x - 1.6, TUB_TOP - 0.55, -7.35), (shelf_x + 1.6, TUB_TOP - 0.55, -7.35)], 0.12, 8))
    panel = rbox(TUB_X - 1.0, 2.2, 0.32, 0.14).rotate("x", 14).translate(0, 3.25, -half_z - 0.35)
    steel.append(panel)
    steel.append(rbox(TUB_X - 1.4, 0.32, TUB_Z - 2.0, 0.14).translate(0, 0.75, 0))  # bottom shelf
    pieces["Steel"] = merge(*steel)

    # The grate: bars running left-right on four rails, over glowing coals.
    bars = []
    count = 21
    for i in range(count):
        z = -half_z + 1.2 + i * (TUB_Z - 2.4) / (count - 1)
        bars.append(tube([(-half_x + 0.55, GRATE_TOP - 0.17, z), (half_x - 0.55, GRATE_TOP - 0.17, z)], 0.17, 8))
    for x in (-half_x + 1.4, -4.3, 4.3, half_x - 1.4):
        bars.append(tube([(x, GRATE_TOP - 0.52, -half_z + 0.6), (x, GRATE_TOP - 0.52, half_z - 0.6)], 0.17, 8))
    pieces["Grate"] = merge(*bars)

    rng = np.random.default_rng(7)
    coals, black = [], []
    for i in range(70):
        x = rng.uniform(-half_x + 1.6, half_x - 1.6)
        z = rng.uniform(-half_z + 1.4, half_z - 1.4)
        r = rng.uniform(0.55, 0.95)
        lump = icosphere(r, 1, 0.18, seed=i).scale(1.0, 0.65, 1.0).translate(x, tub_bottom + 0.45 + r * 0.4, z)
        (coals if i % 3 else black).append(lump)
    pieces["Coals"] = merge(*coals)

    # Legs, wheels, knobs.
    for sx in (-1, 1):
        for sz in (-1, 1):
            x, z = sx * (half_x - 1.0), sz * (half_z - 1.0)
            bottom = 0.0 if sz < 0 else 0.85
            black.append(rbox(0.75, tub_bottom - bottom + 0.3, 0.75, 0.25)
                         .translate(x, bottom + (tub_bottom - bottom + 0.3) / 2, z))
            if sz > 0:
                wheel = cylinder(0.85, 0.5, 20, 0.12).rotate("z", 90).translate(x + sx * 0.75, 0.85, z)
                black.append(wheel)
    ticks = []
    for x in (-8.4, -2.8, 2.8, 8.4):
        knob = cylinder(0.62, 0.55, 20, 0.15).rotate("x", -90 - 14).translate(x, 3.25, -half_z - 0.45)
        black.append(knob)
        tick = rbox(0.14, 0.6, 0.08, 0.03).rotate("x", -14).translate(x, 3.35, -half_z - 1.02)
        ticks.append(tick)
    pieces["Black"] = merge(*black)
    pieces["Tick"] = merge(*ticks)
    return pieces


# ====================================================================== the backyard

def fence():
    """An 8 stud run of white picket fence (posts at both ends)."""
    boards = []
    for i in range(8):
        x = -3.5 + i
        picket = [(-0.36, 0.25), (0.36, 0.25), (0.36, 3.55), (0.0, 4.0), (-0.36, 3.55)]
        boards.append(extrude(picket, 0.16).translate(x, 0, -0.05))
    for y in (1.05, 2.95):
        boards.append(rbox(8.0, 0.42, 0.18, 0.08).translate(0, y, 0.14))
    for x in (-4.0, 4.0):
        boards.append(rbox(0.55, 4.25, 0.55, 0.12).translate(x, 2.125, 0.1))
        boards.append(rbox(0.72, 0.18, 0.72, 0.07).translate(x, 4.3, 0.1))
    return {"Paint": merge(*boards)}


def lights():
    """A string of party lights, 40 studs end to end, sagging in the middle (base: the lowest bulb)."""
    xs = np.linspace(-20, 20, 41)
    wire = [(x, 0.95 + 2.6 * (x / 20) ** 2, 0.0) for x in xs]
    parts = [tube(wire, 0.06, 6)]
    bulbs = []
    for i in range(17):
        x = -18 + i * 2.25
        y = 0.95 + 2.6 * (x / 20) ** 2
        parts.append(cylinder(0.13, 0.3, 10).translate(x, y - 0.3, 0))
        bulbs.append(sphere(0.24, 6, 8).scale(1.0, 1.35, 1.0).translate(x, y - 0.62, 0))
    return {"Wire": merge(*parts), "Bulbs": merge(*bulbs)}


def post():
    """A wooden post for the lights: 12 studs, a cap and a hook."""
    wood = merge(rbox(0.8, 12.0, 0.8, 0.12).translate(0, 6.0, 0),
                 rbox(1.1, 0.3, 1.1, 0.1).translate(0, 12.1, 0))
    hook = tube([(0, 11.2, 0.4), (0, 11.2, 0.8), (0, 11.6, 0.9)], 0.07, 6)
    return {"Wood": wood, "Wire": hook}


def picnic_table():
    wood = []
    for i in range(4):
        wood.append(rbox(12.0, 0.36, 1.05, 0.1).translate(0, 3.1, -1.65 + i * 1.1))
    for side in (-1, 1):
        wood.append(rbox(12.0, 0.34, 1.3, 0.1).translate(0, 1.85, side * 3.45))
    for x in (-4.6, 4.6):
        for lean in (-1, 1):
            # An A: each pair meets under the top and stands out under the benches (the tilt was the other way,
            # a V on its point, like Hot Potato's table the owner caught).
            wood.append(rbox(0.42, 3.9, 0.42, 0.1).rotate("x", -lean * 40).translate(x, 1.63, lean * 1.75))
        wood.append(rbox(0.36, 0.36, 8.0, 0.1).translate(x, 1.6, 0))
    return {"Wood": merge(*wood)}


def cooler():
    body = rbox(4.8, 2.6, 3.0, 0.4).translate(0, 1.35, 0)
    lid = rbox(5.0, 0.62, 3.2, 0.25).translate(0, 2.9, 0)
    handle = merge(*[tube([(side * 2.4, 2.0, -0.7), (side * 2.75, 2.0, -0.7), (side * 2.75, 2.0, 0.7),
                           (side * 2.4, 2.0, 0.7)], 0.12, 6) for side in (-1, 1)])
    return {"Body": body, "Lid": lid, "Steel": handle}


def sauces():
    """A ketchup and a mustard squeeze bottle."""
    pieces = {}
    caps = []
    for name, x in (("Ketchup", -0.85), ("Mustard", 0.85)):
        body = lathe([(0.0, 0.0), (0.62, 0.0), (0.7, 0.12), (0.72, 1.9), (0.62, 2.25), (0.4, 2.42), (0.0, 2.42)], 24)
        pieces[name] = body.translate(x, 0, 0)
        cap_mesh = lathe([(0.0, 2.38), (0.44, 2.38), (0.44, 2.75), (0.16, 3.05), (0.07, 3.5), (0.0, 3.5)], 20)
        caps.append(cap_mesh.translate(x, 0, 0))
    pieces["Caps"] = merge(*caps)
    return pieces


PROPS = {f"PrimeCut{name}": (lambda name=name: steak(name)) for name in STEAKS}
PROPS["PrimeCutKnife"] = knife
PROPS["PrimeCutGrill"] = grill
PROPS["PrimeCutFence"] = fence
PROPS["PrimeCutLights"] = lights
PROPS["PrimeCutPost"] = post
PROPS["PrimeCutTable"] = picnic_table
PROPS["PrimeCutCooler"] = cooler
PROPS["PrimeCutSauces"] = sauces

COLORS = {
    "Meat": (150, 84, 52),
    "Crust": (104, 54, 32),
    "Fat": (240, 214, 170),
    "Marks": (58, 30, 20),
    "Blade": (205, 212, 222),
    "Edge": (240, 244, 250),
    "Metal": (180, 186, 196),
    "Handle": (46, 36, 34),
    "Rivets": (225, 228, 235),
    "Enamel": (220, 50, 60),
    "Steel": (170, 176, 186),
    "Grate": (40, 40, 44),
    "Coals": (255, 120, 40),
    "Black": (30, 30, 34),
    "Tick": (250, 250, 250),
    "Paint": (245, 245, 240),
    "Wire": (30, 30, 30),
    "Bulbs": (255, 220, 140),
    "Wood": (160, 104, 62),
    "Body": (40, 120, 220),
    "Lid": (245, 245, 245),
    "Ketchup": (210, 30, 30),
    "Mustard": (245, 190, 30),
    "Caps": (245, 245, 245),
}
