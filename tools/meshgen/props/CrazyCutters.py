"""Props for Crazy Cutters: cutting boards, dough, the pastry-wheel cutter, one iced cookie per shape,
and the bake-off arena (a giant chocolate-chip cookie floor, a glass of milk, rolling pins, plates and
giant cookie cutters).

The cookie shapes live here and nowhere else. Each shape is drawn as a 2D mask (unions of circles,
ellipses and polygons), its corners are rounded with distance transforms, and its outline is traced
from the result. That one outline is used three ways, so they always match:
  * the cookie mesh (the outline extruded with a soft baked edge, icing, sprinkles and a face),
  * the giant decorative cutters,
  * the dotted line players trace: building any cookie writes the outlines into the
    GENERATED SHAPES block of src/shared/Logic/CrazyCutters.luau.

Shape coordinates (u, v) are studs on the board: u to the right, v away from the player. In a mesh
that is x = u, z = -v (a prop's front is -Z, and the board's far side is its front).

    python3 tools/meshgen/generate_meshes.py --only StarCookie,HeartCookie,...
"""

from __future__ import annotations

import math
import re
from pathlib import Path

import numpy as np
from scipy import ndimage
from scipy.spatial import Delaunay
from skimage import measure

from generate_meshes import Mesh, capsule, cylinder, icosphere, lathe, merge, taper, torus, tube

ROOT = Path(__file__).resolve().parents[3]
LUAU_MODULE = ROOT / "src" / "shared" / "Logic" / "CrazyCutters.luau"

RES = 0.02  # studs per cell of the 2D shape grids
EXT = 7.0  # shape grids cover [-EXT, EXT] in u and v
OUTLINE_SPACING = 0.3  # spacing of the points the game traces against

# ====================================================================== 2D shape fields


def grid(ext: float = EXT, res: float = RES):
    n = int(round(2 * ext / res)) + 1
    axis = -ext + np.arange(n) * res
    U, V = np.meshgrid(axis, axis)  # rows follow v, columns follow u
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
        # The largest loop is the outside; any loop inside it is a hole.
        is_hole = index > 0 and _inside(found[0], pts.mean(axis=0))
        pts = resample(pts, spacing)
        pts = smooth_loop(pts, 1)
        if (area(pts) > 0) == is_hole:
            pts = pts[::-1].copy()
        result.append(pts)
    return result


def _inside(loop, point):
    u, v = point
    inside = False
    n = len(loop)
    for i in range(n):
        (u1, v1), (u2, v2) = loop[i], loop[(i + 1) % n]
        if (v1 > v) != (v2 > v) and u < (u2 - u1) * (v - v1) / (v2 - v1) + u1:
            inside = not inside
    return inside


def normals(loop):
    """Outward normals of a loop with its material on the left."""
    t = np.roll(loop, -1, 0) - np.roll(loop, 1, 0)
    n = np.stack([t[:, 1], -t[:, 0]], 1)
    return n / (np.linalg.norm(n, axis=1, keepdims=True) + 1e-12)


def smoothstep(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


# ====================================================================== 3D from 2D


def to3d(u, y, v):
    """Board coordinates to mesh coordinates (the board's far side is the mesh's front, -Z)."""
    return np.stack([u, y, -v], -1)


def _orient(mesh: Mesh, outward) -> Mesh:
    """Flips faces whose normals disagree with `outward(face centers) -> directions`."""
    tri = mesh.v[mesh.f]
    n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    wanted = outward(tri.mean(axis=1))
    flip = np.sum(n * wanted, axis=1) < 0
    mesh.f[flip] = mesh.f[flip][:, ::-1]
    return mesh


def sweep(rings_2d, profile, base=None):
    """A soft-edged slab wall: for every loop (material on its left) and every (inset, y) profile
    point, a ring moved `inset` studs into the material at height y (+ base(u, v))."""
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
        # Walls face out of the material: along the loop's outward normal, or up/down on the bevels.
        loop3 = to3d(loop[:, 0], np.zeros(count), loop[:, 1])
        out3 = to3d(n2[:, 0], np.zeros(count), n2[:, 1])
        mid = np.mean([p[1] for p in profile])

        def outward(centers, loop3=loop3, out3=out3, mid=mid, base=base):
            d = np.linalg.norm(centers[:, None, [0, 2]] - loop3[None, :, [0, 2]], axis=2)
            nearest = out3[np.argmin(d, axis=1)]
            lift = mid + (base(centers[:, 0], -centers[:, 2]) if base is not None else 0)
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
         base=None, steps=6, bottom=True, ext=EXT, res=RES, level=0.0):
    """A slab whose outline is the field's `level` contour: soft rounded top edge, optional rounded
    bottom edge, a domed top, optionally standing on base(u, v). Returns (mesh, top(u, v))."""
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
                         cap_spacing, False, ext=ext, res=res))
    return merge(*parts), top


# ====================================================================== cookie shapes
# Each shape: a mask (in a ~10.6 stud box), how much to round it, its game data and its icing.

def star_mask():
    pts = []
    for i in range(10):
        r = 5.55 if i % 2 == 0 else 2.45
        a = math.pi / 2 + math.pi * i / 5
        pts.append((math.cos(a) * r, math.sin(a) * r))
    return rounded(polygon(pts), convex=0.5, concave=0.32)


def heart_mask():
    t = np.linspace(0, 2 * math.pi, 400, endpoint=False)
    x = 16 * np.sin(t) ** 3
    y = 13 * np.cos(t) - 5 * np.cos(2 * t) - 2 * np.cos(3 * t) - np.cos(4 * t)
    k = 0.33
    return rounded(polygon(list(zip(x * k, y * k))), convex=0.55, concave=0.6)


def fish_parts():
    body = ellipse(-0.9, 0.0, 3.95, 3.0)
    tail = polygon([(1.6, 0.0), (5.3, 3.0), (4.35, 0.0), (5.3, -3.0)])
    fin = polygon([(-2.6, 2.3), (-0.2, 3.95), (0.9, 2.1)])
    return body, tail, fin


def fish_mask():
    body, tail, fin = fish_parts()
    return rounded(body | tail | fin, convex=0.42, concave=0.45)


def ghost_mask():
    head = circle(0, 0.95, 4.1)
    body = box(-4.1, -3.4, 4.1, 0.95)
    feet = circle(-2.75, -3.45, 1.37) | circle(0, -3.45, 1.37) | circle(2.75, -3.45, 1.37)
    arms = ellipse(-4.1, -0.5, 1.25, 0.85, -0.5) | ellipse(4.1, -0.5, 1.25, 0.85, 0.5)
    return rounded(head | body | feet | arms, convex=0.45, concave=0.5)


def moon_mask():
    return rounded(circle(0.0, 0.0, 5.2) & ~circle(2.45, 1.45, 4.35), convex=0.5, concave=0.3)


def mushroom_parts():
    dome = ellipse(0, 0.2, 5.25, 4.65) & (V >= 0.2)
    lip = ellipse(0, 0.2, 5.25, 1.15)
    stem = polygon([(-1.95, -4.85), (1.95, -4.85), (1.5, 0.8), (-1.5, 0.8)])
    stem = rounded(stem, convex=0.7)
    return dome | lip, stem


def mushroom_mask():
    cap_, stem = mushroom_parts()
    return rounded(cap_ | stem, convex=0.55, concave=0.5)


def flower_parts():
    petals = np.zeros(U.shape, bool)
    for k in range(5):
        a = math.pi / 2 + k * 2 * math.pi / 5
        petals |= circle(math.cos(a) * 3.0, math.sin(a) * 3.0, 2.28)
    center = circle(0, 0, 2.55)
    return petals, center


def flower_mask():
    petals, center = flower_parts()
    return rounded(petals | center, convex=0.3, concave=0.6)


def rgb(r, g, b):
    return (r, g, b)


# Tier 1 is easy, 3 is hard; a game plays one shape of each tier, in that order. Start is where the
# cutter waits (as a direction from the shape's middle) and Turn is the way round to trace it
# (1 = counter-clockwise); Face places the cookie's face (u, v, size).
SHAPES = {
    "Star": {"Mask": star_mask, "Tier": 1, "Start": 90, "Turn": -1, "Face": (0, -0.35, 1.0),
             "Icing": rgb(255, 214, 72), "Sprinkles": (rgb(255, 110, 170), rgb(90, 200, 255))},
    "Heart": {"Mask": heart_mask, "Tier": 1, "Start": 90, "Turn": -1, "Face": (0, 0.35, 1.05),
              "Icing": rgb(255, 120, 170), "Sprinkles": (rgb(255, 255, 255), rgb(255, 70, 100))},
    "Fish": {"Mask": fish_mask, "Tier": 2, "Start": 180, "Turn": -1, "Face": (-2.75, 0.55, 0.95),
             "Icing": rgb(85, 200, 240), "Sprinkles": (rgb(255, 255, 255), rgb(255, 200, 80))},
    "Ghost": {"Mask": ghost_mask, "Tier": 2, "Start": 90, "Turn": -1, "Face": (0, 1.25, 1.25),
              "Icing": rgb(250, 248, 255), "Sprinkles": None},
    "Moon": {"Mask": moon_mask, "Tier": 2, "Start": 200, "Turn": -1, "Face": (-2.55, -1.55, 0.9),
             "Icing": rgb(255, 230, 110), "Sprinkles": (rgb(255, 255, 255), rgb(150, 120, 255))},
    "Mushroom": {"Mask": mushroom_mask, "Tier": 3, "Start": 90, "Turn": -1, "Face": (0, -2.55, 0.75),
                 "Icing": rgb(240, 72, 72), "Sprinkles": None},
    "Flower": {"Mask": flower_mask, "Tier": 3, "Start": 90, "Turn": -1, "Face": (0, 0, 1.0),
               "Icing": rgb(200, 150, 255), "Sprinkles": None},
}

_cache: dict = {}


def shape_field(name):
    """The shape's mask moved so its bounding box is centered, and its signed field."""
    if name in _cache:
        return _cache[name]
    mask = SHAPES[name]["Mask"]()
    rows, cols = np.nonzero(mask)
    du = -(-EXT + (cols.min() + cols.max()) / 2 * RES)
    dv = -(-EXT + (rows.min() + rows.max()) / 2 * RES)
    shift = (int(round(dv / RES)), int(round(du / RES)))
    mask = np.roll(mask, shift, axis=(0, 1))
    _cache[name] = (mask, field(mask), (shift[1] * RES, shift[0] * RES))
    return _cache[name]


def shape_outline(name):
    """The traced outline: evenly spaced points, counter-clockwise from the start, then turned the
    way the shape is meant to be traced."""
    _, f, _ = shape_field(name)
    outline = loops(f, 0.0, OUTLINE_SPACING)[0]
    spec = SHAPES[name]
    a = math.radians(spec["Start"])
    direction = np.array([math.cos(a), math.sin(a)])
    start = int(np.argmax(outline @ direction - 0.02 * np.abs(outline @ np.array([-direction[1], direction[0]]))))
    outline = np.roll(outline, -start, axis=0)
    if spec["Turn"] < 0:
        outline = np.vstack([outline[:1], outline[1:][::-1]])
    return outline


# ====================================================================== cookie meshes

COOKIE = (232, 172, 98)
COOKIE_THICK = 0.72
ICING_THICK = 0.16


def _sprinkle(u, v, y, yaw, length=0.42, radius=0.075):
    mesh = capsule(length, radius, 6)
    # Fewer rings: a capsule's 14 rings are wasted on a 0.4 stud sprinkle.
    mesh = Mesh(mesh.v, mesh.f)
    mesh.rotate("z", 90).rotate("y", math.degrees(yaw))
    p = to3d(np.array([u]), np.array([y + radius * 0.75]), np.array([v]))[0]
    return mesh.translate(*p)


def _blob(u, v, y, rx, ry, rz, subdivisions=2):
    p = to3d(np.array([u]), np.array([y]), np.array([v]))[0]
    return icosphere(1.0, subdivisions).scale(rx, ry, rz).translate(*p)


def _face(kind, fu, fv, size, surface):
    """Eyes with shines, a smile and rosy cheeks, sitting on the surface. Returns face, cheeks, shine."""
    face, cheeks, shine = [], [], []
    s = size
    eyes = [(fu - 0.9 * s, fv + 0.3 * s), (fu + 0.9 * s, fv + 0.3 * s)]
    eye = (0.3 * s, 0.13, 0.42 * s)
    if kind == "Ghost":
        eye = (0.36 * s, 0.13, 0.66 * s)
    if kind == "Fish":
        eyes = [(fu, fv + 0.25 * s)]
        eye = (0.42 * s, 0.14, 0.48 * s)
    for (eu, ev) in eyes:
        y = surface(eu, ev)
        face.append(_blob(eu, ev, y, *eye))
        shine.append(_blob(eu - 0.1 * s, ev + 0.15 * s, y + 0.1, 0.11 * s, 0.06, 0.11 * s, 1))
    if kind == "Ghost":
        # A little "o" of surprise.
        ring = torus(0.32 * s, 0.09 * s, 20, 8).scale(1.0, 1.0, 1.35)
        mu, mv = fu, fv - 1.05 * s
        p = to3d(np.array([mu]), np.array([surface(mu, mv) + 0.04]), np.array([mv]))[0]
        face.append(ring.translate(*p))
    else:
        mouth_u = fu + (-1.05 * s if kind == "Fish" else 0.0)
        mouth_v = fv - (0.45 * s if kind == "Fish" else 0.25 * s)
        r = 0.5 * s if kind != "Fish" else 0.32 * s
        arc = [(mouth_u + math.cos(a) * r, mouth_v + math.sin(a) * r) for a in np.linspace(math.radians(205), math.radians(335), 12)]
        pts = [tuple(to3d(np.array([u]), np.array([surface(u, v) + 0.03]), np.array([v]))[0]) for u, v in arc]
        face.append(tube(pts, 0.085 * s, 8))
    if kind not in ("Fish",):
        for side in (-1, 1):
            cu, cv = fu + side * 1.5 * s, fv - 0.32 * s
            cheeks.append(_blob(cu, cv, surface(cu, cv), 0.32 * s, 0.05, 0.24 * s, 1))
    return face, cheeks, shine


def _scatter(f, level, count, spacing, avoid, seed):
    """Random points inside the field's `level` region, at least `spacing` apart, away from `avoid`
    circles [(u, v, radius)]."""
    rng = np.random.default_rng(seed)
    chosen = []
    tries = 0
    while len(chosen) < count and tries < count * 200:
        tries += 1
        u, v = rng.uniform(-5.6, 5.6, 2)
        if sample(f, u, v)[0] > level:
            continue
        if any((u - a) ** 2 + (v - b) ** 2 < r * r for a, b, r in avoid):
            continue
        if any((u - a) ** 2 + (v - b) ** 2 < spacing * spacing for a, b in chosen):
            continue
        chosen.append((u, v))
    return chosen


def cookie(name):
    """An iced cookie in the shape's exact outline: soft baked edge and domed top, icing piped a
    little in from the edge, sprinkles or spots, and a happy face."""
    write_luau_shapes()
    spec = SHAPES[name]
    mask, f, offset = shape_field(name)
    body, body_top = slab(f, COOKIE_THICK, 0.3, 0.12, spacing=0.13, cap_spacing=0.32, dome=0.14, dome_depth=2.2)
    pieces = {"Cookie": body}

    def shifted(mask_):
        return np.roll(mask_, (int(round(offset[1] / RES)), int(round(offset[0] / RES))), axis=(0, 1))

    # Icing regions (an inset of the cookie, or of one of its parts).
    inset = 0.42
    icing2 = None
    if name == "Mushroom":
        cap_mask, stem_mask = (shifted(m) for m in mushroom_parts())
        cap_region = cap_mask & (field(mask) < -inset)
        stem_region = stem_mask & ~(field(cap_mask) < 0.32) & (field(mask) < -inset)
        icing_mask = rounded(cap_region, convex=0.3)
        icing2 = rounded(stem_region, convex=0.3)
    elif name == "Flower":
        _, center = (shifted(m) for m in flower_parts())
        icing_mask = rounded(field(mask) < -inset, convex=0.2)
        icing2 = rounded(field(center) < -0.55, convex=0.2)
    else:
        icing_mask = field(mask) < -inset

    f_icing = field(icing_mask)

    def on_cookie(u, v):
        return body_top(u, v) - 0.03

    icing, icing_top = slab(f_icing, ICING_THICK, 0.12, 0.0, spacing=0.13, cap_spacing=0.34, dome=0.04,
                            dome_depth=1.0, base=on_cookie, bottom=False)
    pieces["Icing"] = icing
    surface = icing_top
    if icing2 is not None:
        f2 = field(icing2)
        if name == "Flower":
            second, second_top = slab(f2, 0.2, 0.15, 0.0, spacing=0.13, cap_spacing=0.3, dome=0.12, dome_depth=1.2,
                                      base=lambda u, v: icing_top(u, v) - 0.03, bottom=False)
        else:
            second, second_top = slab(f2, ICING_THICK, 0.12, 0.0, spacing=0.13, cap_spacing=0.3, dome=0.04,
                                      dome_depth=1.0, base=on_cookie, bottom=False)
        pieces["Icing2"] = second
        inside2 = f2

        def surface(u, v, icing_top=icing_top, second_top=second_top, inside2=inside2):
            return np.where(sample(inside2, u, v) < 0, second_top(u, v), icing_top(u, v))

    def at(u, v):
        return float(np.atleast_1d(surface(np.atleast_1d(u), np.atleast_1d(v)))[0])

    fu, fv, size = spec["Face"]
    fu, fv = fu + offset[0], fv + offset[1]
    face, cheeks, shine = _face(name, fu, fv, size, at)
    pieces["Face"] = merge(*face)
    pieces["Shine"] = merge(*shine)
    if cheeks:
        pieces["Cheeks"] = merge(*cheeks)

    seed = sum(map(ord, name))
    if name == "Mushroom":
        spots = []
        f_cap = field(icing_mask)
        for (u, v) in _scatter(f_cap, -0.75, 7, 1.9, [], seed):
            r = np.random.default_rng(int(abs(u * 100 + v * 10))).uniform(0.55, 0.85)
            spots.append(_blob(u, v, at(u, v) - 0.04, r, 0.09, r, 2))
        pieces["Dots"] = merge(*spots)
    elif name == "Fish":
        scales = []
        for k in range(3):
            cu = fu + 2.2 + k * 1.15
            pts = []
            for a in np.linspace(math.radians(120), math.radians(240), 9):
                u, v = cu + math.cos(a) * 0.75, fv - 0.55 + math.sin(a) * 0.95
                pts.append(tuple(to3d(np.array([u]), np.array([at(u, v) + 0.02]), np.array([v]))[0]))
            scales.append(tube(pts, 0.07, 6))
        pieces["Dots"] = merge(*scales)
    elif name == "Flower":
        dots = []
        for k in range(5):
            a = math.pi / 2 + k * 2 * math.pi / 5
            u, v = math.cos(a) * 3.2 + offset[0], math.sin(a) * 3.2 + offset[1]
            dots.append(_blob(u, v, at(u, v) - 0.02, 0.42, 0.08, 0.42, 2))
        pieces["Dots"] = merge(*dots)
    if spec["Sprinkles"]:
        avoid = [(fu, fv, 2.3 * size)]
        spots = _scatter(f_icing, -0.28, 34, 0.62, avoid, seed)
        rng = np.random.default_rng(seed + 1)
        groups = ([], [])
        for index, (u, v) in enumerate(spots):
            groups[index % 2].append(_sprinkle(u, v, at(u, v) - 0.03, rng.uniform(0, 2 * math.pi)))
        pieces["Sprinkles"] = merge(*groups[0])
        pieces["Sprinkles2"] = merge(*groups[1])
    return pieces


# ====================================================================== the game's outlines (Luau)


def write_luau_shapes():
    """Writes every shape's outline into the server module's GENERATED SHAPES block."""
    if not LUAU_MODULE.exists():
        return
    lines = ["CrazyCutters.Shapes = {"]
    for name, spec in SHAPES.items():
        outline = shape_outline(name)
        closed = np.vstack([outline, outline[:1]])
        length = float(np.sum(np.linalg.norm(np.diff(closed, axis=0), axis=1)))
        points = " ".join(f"{u:.2f} {v:.2f}" for u, v in outline)
        lines.append(f'\t{{ Id = "{name}", Tier = {spec["Tier"]}, Length = {length:.1f}, Points = "{points}" }},')
    lines.append("}")
    block = "\n".join(lines)
    text = LUAU_MODULE.read_text()
    pattern = re.compile(r"(-- BEGIN GENERATED SHAPES[^\n]*\n).*?(\n-- END GENERATED SHAPES)", re.S)
    if not pattern.search(text):
        raise SystemExit(f"{LUAU_MODULE} has no GENERATED SHAPES block")
    updated = pattern.sub(lambda m: m.group(1) + block + m.group(2), text)
    if updated != text:
        LUAU_MODULE.write_text(updated)


# ====================================================================== station props


BOARD_EXT = 10.0
BOARD_RES = 0.03


def cutting_board():
    Ub, Vb = grid(BOARD_EXT, BOARD_RES)
    # Symmetric about the middle (MeshLibrary pivots a prop at its bounding box's center), with the
    # hanging slot at the far end.
    plate = (Ub >= -7.4) & (Ub <= 7.4) & (Vb >= -8.6) & (Vb <= 8.6)
    sv = 7.75
    slot = ((np.abs(Ub) <= 1.15) & (np.abs(Vb - sv) <= 0.5)) | ((Ub - 1.15) ** 2 + (Vb - sv) ** 2 <= 0.5 ** 2) | (
        (Ub + 1.15) ** 2 + (Vb - sv) ** 2 <= 0.5 ** 2)
    mask = rounded(plate, convex=1.8, res=BOARD_RES) & ~slot
    f = field(mask, BOARD_RES)
    board, _ = slab(f, 0.8, 0.3, 0.2, spacing=0.2, cap_spacing=0.9, ext=BOARD_EXT, res=BOARD_RES)
    # The juice groove: a rounded square ring between the dough and the edge.
    half, r = 6.95, 1.6
    pts = []
    for cu, cv, a0 in ((half - r, half - r, 0), (-half + r, half - r, 90), (-half + r, -half + r, 180), (half - r, -half + r, 270)):
        for a in np.linspace(math.radians(a0), math.radians(a0 + 90), 9):
            pts.append((cu + math.cos(a) * r, cv + math.sin(a) * r))
    pts.append(pts[0])
    groove = tube([tuple(to3d(np.array([u]), np.array([0.79]), np.array([v]))[0]) for u, v in pts], 0.12, 8)
    return {"Board": board, "Groove": groove}


DOUGH_EXT = 7.0


def dough_sheet():
    """Rolled-out dough with a soft, uneven edge, and flour dusted on the board around it."""
    theta = np.arctan2(V, U)
    half, r = 6.25, 2.0
    q = np.maximum(np.abs(np.stack([U, V])) - (half - r), 0)
    outside = np.sqrt(q[0] ** 2 + q[1] ** 2) + np.minimum(np.maximum(np.abs(U), np.abs(V)) - (half - r), 0) - r
    wobble = 0.1 * np.sin(5 * theta + 0.3) + 0.07 * np.sin(9 * theta + 1.1) + 0.04 * np.sin(17 * theta + 2.0)
    mask = outside + wobble < 0
    f = field(mask)
    dough, _ = slab(f, 0.42, 0.24, 0.0, spacing=0.14, cap_spacing=0.8, bottom=False)
    rng = np.random.default_rng(4)
    flour = []
    for _ in range(46):
        a = rng.uniform(0, 2 * math.pi)
        d = rng.uniform(6.7, 7.25)
        u, v = math.cos(a) * d, math.sin(a) * d
        u, v = np.clip(u, -7.05, 7.05), np.clip(v, -7.05, 7.05)
        rad = rng.uniform(0.12, 0.3)
        flour.append(_blob(u, v, 0.03, rad, 0.03, rad * rng.uniform(0.6, 1.0), 1))
    return {"Dough": dough, "Flour": merge(*flour)}


def pastry_cutter():
    """A toy pastry wheel on a swivel: a fluted steel wheel in a fork that turns to follow the cut,
    under a chunky candy-striped handle that leans back towards whoever holds it. "Tip" marks the
    point where the wheel touches the dough (the pivot the game moves it by)."""
    R = 0.85
    m, sections = 96, []
    section = [(-0.14, 0.24), (-0.13, 0.36), (-0.055, 0.6 * R), (-0.02, 1.0), (0.02, 1.0), (0.055, 0.6 * R), (0.13, 0.36), (0.14, 0.24)]
    verts = []
    for k in range(m):
        th = 2 * math.pi * k / m
        rim = R * (0.95 + 0.05 * math.cos(18 * th))
        for x, rho in section:
            radius = rim if rho == 1.0 else rho
            verts.append((x, R - radius * math.cos(th), radius * math.sin(th)))
    count = len(section)
    faces = []
    for k in range(m):
        for j in range(count):
            a = k * count + j
            b = k * count + (j + 1) % count
            c = ((k + 1) % m) * count + j
            d = ((k + 1) % m) * count + (j + 1) % count
            faces += [(a, c, b), (b, c, d)]
    wheel = Mesh(verts, faces)
    wheel = _orient(wheel, lambda c: np.stack([c[:, 0] * 4, c[:, 1] - R, c[:, 2]], 1))
    hub = cylinder(0.27, 0.5, 20, 0.08).rotate("z", 90).translate(0.25, R, 0)
    bolts = [icosphere(0.13, 1).scale(0.6, 1, 1).translate(side * 0.27, R, 0) for side in (-1, 1)]
    fork = []
    for side in (-1, 1):
        fork.append(taper([(side * 0.31, R, 0), (side * 0.31, R + 0.55, 0.0), (side * 0.22, R + 0.98, 0), (side * 0.06, R + 1.18, 0)], 0.09, 0.07, 8))
    collar = cylinder(0.24, 0.36, 20, 0.07).translate(0, R + 1.12, 0)
    lean = math.radians(22)

    def along(mesh):
        return mesh.rotate("x", math.degrees(lean)).translate(0, R + 1.44, 0)

    handle = along(lathe([(0.0, 0.0), (0.19, 0.0), (0.24, 0.12), (0.27, 0.45), (0.25, 1.15), (0.29, 1.6), (0.36, 1.95), (0.37, 2.2),
                          (0.31, 2.42), (0.18, 2.56), (0.0, 2.6)], 24))
    bands = [along(torus(r, 0.06, 24, 8).translate(0, y, 0)) for y, r in ((0.55, 0.265), (0.9, 0.26), (1.25, 0.26))]
    tip = icosphere(0.04, 0)
    return {"Wheel": merge(wheel, hub, *bolts), "Fork": merge(*fork, collar), "Handle": handle, "Bands": merge(*bands), "Tip": tip}


def cookie_plate():
    """A little cake plate on a stem, for the cookies a player has cut."""
    plate = lathe([(0.0, 1.9), (1.2, 1.9), (2.3, 2.02), (2.85, 2.25), (3.0, 2.38), (2.95, 2.46), (2.75, 2.4), (2.25, 2.2),
                   (1.2, 2.12), (0.0, 2.12)], 40)
    stem = lathe([(0.0, 0.0), (1.25, 0.0), (1.3, 0.12), (1.0, 0.3), (0.4, 0.6), (0.3, 1.2), (0.42, 1.75), (0.7, 1.95), (0.0, 1.95)], 28)
    rim = torus(2.92, 0.08, 48, 8).translate(0, 2.37, 0)
    return {"Plate": merge(plate, stem), "Rim": rim}


# ====================================================================== arena props


def giant_cookie():
    """The arena floor: a huge chocolate-chip cookie with a lumpy rim and a puffy baked top."""
    radius = 58.0
    ext, res = 60.0, 0.12
    Ug, Vg = grid(ext, res)
    theta = np.arctan2(Vg, Ug)
    r = np.sqrt(Ug ** 2 + Vg ** 2)
    edge = radius * (1 + 0.011 * np.sin(6 * theta + 0.4) + 0.007 * np.sin(11 * theta + 1.3) + 0.004 * np.sin(23 * theta + 0.2))
    f = r - edge
    rng = np.random.default_rng(12)
    bumps = [(rng.uniform(-48, 48), rng.uniform(-48, 48), rng.uniform(5, 11), rng.uniform(0.08, 0.2)) for _ in range(26)]

    def lumps(u, v):
        h = np.zeros(np.shape(u))
        for bu, bv, br, bh in bumps:
            h = h + bh * np.exp(-((u - bu) ** 2 + (v - bv) ** 2) / (br * br))
        return h

    thickness = 3.2
    top_r = 1.5
    outline = loops(f, 0.0, 0.9, ext, res)
    profile = []
    for k in range(3):
        a = math.pi / 2 * k / 2
        profile.append((0.4 - 0.4 * math.sin(a), 0.4 - 0.4 * math.cos(a)))
    for k in range(9):
        a = math.pi / 2 * k / 8
        profile.append((top_r - top_r * math.cos(a), thickness - top_r + top_r * math.sin(a)))
    walls = sweep(outline, profile)

    def top(u, v):
        depth = -sample(f, u, v, ext, res) - top_r
        return thickness + 0.5 * smoothstep(depth / 10) + lumps(u, v) * smoothstep(depth / 6)

    inner = [loop - normals(loop) * top_r for loop in outline]
    lid = cap(inner, f, -top_r, top, 2.2, True, ext=ext, res=res)
    chips = []
    for _ in range(90):
        a = rng.uniform(0, 2 * math.pi)
        d = math.sqrt(rng.uniform(0.02, 1)) * (radius - 4)
        u, v = math.cos(a) * d, math.sin(a) * d
        size = rng.uniform(0.9, 1.7)
        y = float(top(np.array([u]), np.array([v]))[0])
        chip = icosphere(1.0, 1, 0.3, int(rng.integers(1000))).scale(size, size * 0.62, size * rng.uniform(0.8, 1.1))
        chips.append(chip.rotate("y", rng.uniform(0, 360)).translate(*to3d(np.array([u]), np.array([y - size * 0.18]), np.array([v]))[0]))
    return {"Cookie": merge(walls, lid), "Chips": merge(*chips)}


def milk_glass():
    """A giant glass of milk with a bendy straw: the bake-off's centerpiece."""
    glass = lathe([(0.0, 0.0), (4.3, 0.0), (4.55, 0.25), (5.45, 20.6), (5.52, 20.82), (5.42, 20.9), (5.18, 20.78), (4.35, 1.75),
                   (4.1, 1.55), (0.0, 1.5)], 48)
    milk = lathe([(0.0, 1.52), (4.12, 1.57), (4.36, 1.8), (4.95, 13.9), (4.85, 14.05), (2.5, 14.12), (0.0, 14.1)], 48)
    path = [(1.7, 4.0, 0.6), (1.95, 12.0, 0.8), (2.15, 20.0, 0.95), (2.25, 23.4, 1.0)]
    for k in range(1, 9):
        a = math.radians(11.25 * k)
        path.append((2.25 + (1 - math.cos(a)) * 1.6, 23.4 + math.sin(a) * 1.6, 1.0 + (1 - math.cos(a)) * 0.6))
    path += [(5.2, 26.2, 2.1), (6.4, 26.6, 2.55)]
    straw = tube(path, 0.48, 14)
    bands = []
    for i in range(len(path) - 1):
        if i % 2 == 0:
            continue
        a, b = np.array(path[i]), np.array(path[i + 1])
        for t in (0.0, 0.5):
            p = a + (b - a) * t
            d = (b - a) / (np.linalg.norm(b - a) + 1e-9)
            ring = torus(0.5, 0.07, 16, 6)
            # Turn the ring's axis (y) onto the straw's direction.
            axis = np.cross([0, 1.0, 0], d)
            angle = math.degrees(math.acos(np.clip(d[1], -1, 1)))
            if np.linalg.norm(axis) > 1e-6 and angle > 0.1:
                ax = axis / np.linalg.norm(axis)
                ring = _rotate_axis(ring, ax, angle)
            bands.append(ring.translate(*p))
    return {"Glass": glass, "Milk": milk, "Straw": straw, "Stripes": merge(*bands)}


def _rotate_axis(mesh, axis, degrees):
    a = math.radians(degrees)
    x, y, z = axis
    c, s, t = math.cos(a), math.sin(a), 1 - math.cos(a)
    m = np.array([[t * x * x + c, t * x * y - s * z, t * x * z + s * y],
                  [t * x * y + s * z, t * y * y + c, t * y * z - s * x],
                  [t * x * z - s * y, t * y * z + s * x, t * z * z + c]])
    mesh.v = mesh.v @ m.T
    return mesh


def rolling_pin():
    """A wooden rolling pin lying along X, red handles."""
    pin = lathe([(0.0, -8.0), (1.25, -8.0), (1.62, -7.6), (1.75, -6.8), (1.78, 0.0), (1.75, 6.8), (1.62, 7.6), (1.25, 8.0), (0.0, 8.0)], 36)
    handles = []
    for side in (-1, 1):
        h = lathe([(0.0, 0.0), (0.42, 0.0), (0.5, 0.4), (0.55, 2.4), (0.75, 2.9), (0.8, 3.3), (0.6, 3.6), (0.0, 3.62)], 20)
        if side < 0:
            h.v[:, 1] = -h.v[:, 1]
            h.f = h.f[:, ::-1].copy()
        handles.append(h.translate(0, side * 7.9, 0))
    lift = 1.78
    return {"Pin": pin.rotate("z", 90).translate(0, lift, 0), "Handles": merge(*handles).rotate("z", 90).translate(0, lift, 0)}


def big_cutter(name):
    """A giant metal cookie cutter in a shape's outline (a thin wall with a rolled rim)."""
    outline = shape_outline(name)
    outline = resample(outline, 0.12)
    n2 = normals(outline)
    height = 1.6
    profile = [(-0.07, 0.0), (-0.07, height), (0.07, height), (0.07, 0.0)]
    rings = []
    for off, y in profile:
        ring = outline - n2 * off
        rings.append(to3d(ring[:, 0], np.full(len(ring), y), ring[:, 1]))
    verts = np.vstack(rings)
    count = len(outline)
    faces = []
    for j in range(4):
        for i in range(count):
            a = j * count + i
            b = j * count + (i + 1) % count
            c = ((j + 1) % 4) * count + i
            d = ((j + 1) % 4) * count + (i + 1) % count
            faces += [(a, b, c), (b, d, c)]
    wall = Mesh(verts, faces)
    centers = outline.mean(axis=0)
    wall = _orient(wall, lambda c: np.stack([c[:, 0] - centers[0], (c[:, 1] - height / 2) * 0.01, c[:, 2] + centers[1]], 1) * 0 + _wall_out(c, outline, n2, height))
    rim_pts = [tuple(p) for p in to3d(outline[:, 0], np.full(len(outline), height), outline[:, 1])]
    rim_pts.append(rim_pts[0])
    rim = tube(rim_pts, 0.13, 8)
    return {"Steel": wall, "Rim": rim}


def _wall_out(centers, outline, n2, height):
    loop3 = to3d(outline[:, 0], np.zeros(len(outline)), outline[:, 1])
    out3 = to3d(n2[:, 0], np.zeros(len(outline)), n2[:, 1])
    d = np.linalg.norm(centers[:, None, [0, 2]] - loop3[None, :, [0, 2]], axis=2)
    index = np.argmin(d, axis=1)
    side = np.sum((centers[:, [0, 2]] - loop3[index][:, [0, 2]]) * out3[index][:, [0, 2]], axis=1)
    # Faces outside the outline face out, inside ones face in; top and bottom faces face up / down.
    direction = out3[index] * np.sign(side + 1e-9)[:, None]
    vertical = np.where(centers[:, 1] > height - 1e-3, 1.0, np.where(centers[:, 1] < 1e-3, -1.0, 0.0))
    return direction + vertical[:, None] * np.array([0, 1.0, 0])


PROPS = {
    "CuttingBoard": cutting_board,
    "DoughSheet": dough_sheet,
    "PastryCutter": pastry_cutter,
    "CookiePlate": cookie_plate,
    "GiantCookie": giant_cookie,
    "MilkGlass": milk_glass,
    "RollingPin": rolling_pin,
    "StarCutter": lambda: big_cutter("Star"),
    "HeartCutter": lambda: big_cutter("Heart"),
}
for _shape in SHAPES:
    PROPS[f"{_shape}Cookie"] = (lambda name: (lambda: cookie(name)))(_shape)

COLORS = {
    "Cookie": COOKIE, "Icing": (255, 214, 72), "Icing2": (255, 240, 215), "Dots": (255, 255, 255), "Sprinkles": (255, 110, 170),
    "Sprinkles2": (90, 200, 255), "Face": (70, 40, 30), "Cheeks": (255, 140, 160), "Shine": (255, 255, 255),
    "Board": (90, 190, 255), "Groove": (60, 150, 220), "Dough": (250, 232, 200), "Flour": (255, 255, 255),
    "Wheel": (215, 220, 230), "Fork": (240, 200, 90), "Handle": (255, 90, 140), "Bands": (255, 255, 255), "Tip": (255, 0, 0),
    "Plate": (255, 255, 255), "Rim": (255, 150, 190), "Chips": (90, 50, 35), "Glass": (220, 240, 255), "Milk": (255, 255, 250),
    "Straw": (255, 90, 120), "Stripes": (255, 255, 255), "Pin": (225, 180, 120), "Handles": (230, 70, 70), "Steel": (200, 205, 215),
}
