"""Meshes for Bobsled Run (see tools/meshgen/props/README.md). Units are studs, +Y up, -Z is the front
(the way the sled runs). Generate with:
    python3 tools/meshgen/generate_meshes.py --only BobsledTrack,BobsledKicker,BobsledCurveL,BobsledCurveR,BobsledSled,BobsledPine,BobsledPeak,BobsledGate,BobsledArch,BobsledFlag

The track pieces are swept along the same path as src/shared/Logic/BobsledCourse.luau (keep the
numbers below in step with it): each is authored with its entry point on the centerline at the
origin, heading -Z. `python3 tools/meshgen/props/BobsledRun.py` prints each piece's bounding box
bottom-center (the pivot MeshLibrary gives it), which BobsledCourse.Anchor must match."""

import math

import numpy as np

from generate_meshes import Mesh, cylinder, lathe, merge, organic_lathe, rounded_box, sdf_mesh, sphere, taubin_smooth, weld

# ---- the course's numbers (BobsledCourse.luau)
UNIT = 16.0
RADIUS = 70.0
TURN = math.radians(50)
ARC = RADIUS * TURN
SLOPE = 0.1
BANK = math.radians(30)
FLOOR_HALF = 20.0
KICK = 3.0

# ---- the channel's cross-section
FILLET = 3.0  # floor-to-wall curve
WALL = 5.0  # inner wall height on straights
OUTER_EXTRA = 4.0  # the outer wall grows this much in the middle of a curve
LIP = 2.2  # the rounded wall top
BERM = 13.0  # how far out the snow bank reaches
DEPTH = 14.0  # how far below the centerline it goes (into the snow ground)


def oriented(mesh: Mesh) -> Mesh:
    """Winds a closed mesh's faces outward (positive signed volume)."""
    tri = mesh.v[mesh.f]
    volume = np.einsum("ij,ij->i", tri[:, 0], np.cross(tri[:, 1], tri[:, 2])).sum()
    if volume < 0:
        mesh.f = mesh.f[:, ::-1].copy()
    return mesh


def box(sx, sy, sz, r, x=0.0, y=0.0, z=0.0, n=3):
    return rounded_box(sx, sy, sz, r, n).translate(x, y, z)


def tube_path(points, radius, sides=10, closed=False):
    """A round tube along a polyline, faces outward; open ends are capped."""
    pts = [np.array(p, dtype=float) for p in points]
    count = len(pts)
    verts, faces = [], []
    for i, p in enumerate(pts):
        if closed:
            tangent = pts[(i + 1) % count] - pts[(i - 1) % count]
        else:
            tangent = pts[min(i + 1, count - 1)] - pts[max(i - 1, 0)]
        tangent /= np.linalg.norm(tangent) + 1e-9
        helper = np.array([0, 1.0, 0]) if abs(tangent[1]) < 0.9 else np.array([1.0, 0, 0])
        u = np.cross(tangent, helper)
        u /= np.linalg.norm(u)
        w = np.cross(tangent, u)
        for j in range(sides):
            a = 2 * math.pi * j / sides
            verts.append(p + (u * math.cos(a) + w * math.sin(a)) * radius)
    rings = count if closed else count - 1
    for i in range(rings):
        i2 = (i + 1) % count
        for j in range(sides):
            a, b = i * sides + j, i * sides + (j + 1) % sides
            c, d = i2 * sides + j, i2 * sides + (j + 1) % sides
            faces += [(a, b, c), (b, d, c)]
    if not closed:
        for ring, center in ((0, pts[0]), (count - 1, pts[-1])):
            index = len(verts)
            verts.append(center)
            for j in range(sides):
                faces.append((index, ring * sides + j, ring * sides + (j + 1) % sides))
    mesh = Mesh(verts, faces)
    # Per-face: point away from the nearest path point (works for any path, closed or open).
    tri = mesh.v[mesh.f]
    normal = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    mid = tri.mean(axis=1)
    path = np.array(pts)
    nearest = path[np.argmin(((mid[:, None, :] - path[None, :, :]) ** 2).sum(-1), axis=1)]
    flip = np.einsum("ij,ij->i", normal, mid - nearest) < 0
    mesh.f[flip] = mesh.f[flip][:, ::-1]
    return mesh


# ================================================================== the track


def right(h):
    return np.array([math.cos(h), 0.0, -math.sin(h)])


def bank_shape(t):
    def smooth(x):
        x = min(max(x, 0.0), 1.0)
        return x * x * (3 - 2 * x)

    return smooth(t / 0.3) * smooth((1 - t) / 0.3)


def path(kind, s):
    """Centerline point, heading, bank angle, bank pivot and curve shape (0..1) at `s` into a piece."""
    if kind in ("L", "R"):
        direction = -1 if kind == "L" else 1
        center = right(0.0) * RADIUS * direction
        h = -direction * s / RADIUS
        point = center - right(h) * RADIUS * direction - np.array([0, SLOPE * s, 0])
        shape = bank_shape(s / ARC)
        return point, h, -direction * BANK * shape, direction * FLOOR_HALF, shape
    return np.array([0.0, -SLOPE * s, -s]), 0.0, 0.0, 0.0, 0.0


def profile(kind, shape):
    """The channel's cross-section as labelled runs of (x, y, banked) points, going round the solid
    counter-clockwise (x right, y up): the right snow bank up, the right lip, the ice inside, the left
    lip, the left snow bank down. Unbanked points (the bank's foot) stay put when the curve tilts."""
    outer = 1 if kind == "L" else (-1 if kind == "R" else 0)  # which side is the outside of the curve
    wall_r = WALL + (OUTER_EXTRA * shape if outer == 1 else 0)
    wall_l = WALL + (OUTER_EXTRA * shape if outer == -1 else 0)

    def side(sign, wall):
        """Fillet and wall for one side, from the floor's edge up (x sign = side)."""
        pts = []
        for i in range(1, 7):
            a = math.pi / 2 * i / 6
            pts.append((sign * (FLOOR_HALF - FILLET + FILLET * math.sin(a)), FILLET - FILLET * math.cos(a)))
        for i in range(1, 4):
            t = i / 3
            pts.append((sign * (FLOOR_HALF + 0.6 * t), FILLET + (wall - FILLET) * t))
        return pts

    def lip(sign, wall):
        pts = []
        for i in range(0, 9):
            a = math.pi * i / 8
            cx = sign * (FLOOR_HALF + 0.6 + LIP / 2)
            pts.append((cx - sign * math.cos(a) * LIP / 2, wall + math.sin(a) * 0.9))
        return pts

    def bank(sign, wall):
        x0 = sign * (FLOOR_HALF + 0.6 + LIP)
        pts = []
        for i in range(0, 7):
            t = i / 6
            # A soft convex snow bank: steep near the lip, flaring out at the foot.
            x = x0 + sign * BERM * (t ** 1.6)
            y = wall - (wall + DEPTH) * (1 - (1 - t) ** 1.8)
            pts.append((x, y, i < 1))
        return pts

    floor = [(x, 0.0) for x in np.linspace(FLOOR_HALF - FILLET, -(FLOOR_HALF - FILLET), 11)]
    right_side = side(1, wall_r)
    left_side = side(-1, wall_l)
    ice = [(x, y, True) for x, y in list(reversed(right_side)) + floor + left_side]
    right_bank = [(x, y, b) for x, y, b in reversed(bank(1, wall_r))]
    right_lip = [(x, y, True) for x, y in reversed(lip(1, wall_r))]
    left_lip = [(x, y, True) for x, y in lip(-1, wall_l)]
    left_bank = bank(-1, wall_l)
    # Neighboring runs share their end points.
    return [("Snow", right_bank), ("Trim", right_lip), ("Ice", ice), ("Trim", left_lip), ("Snow", left_bank)]


def sweep_piece(kind, length, rows):
    pieces = {}
    for i_run in range(5):
        verts, normals_hint = [], []
        label = None
        run_len = None
        for r in range(rows + 1):
            s = length * r / rows
            point, h, bank, pivot, shape = path(kind, s)
            label, run = profile(kind, shape)[i_run]
            run_len = len(run)
            rv = right(h)
            up = np.array([0, 1.0, 0])
            c, sn = math.cos(bank), math.sin(bank)
            for j, (x, y, banked) in enumerate(run):
                if banked:
                    xr = pivot + (x - pivot) * c - y * sn
                    yr = (x - pivot) * sn + y * c
                else:
                    xr, yr = x, y
                verts.append(point + rv * xr + up * yr)
                # The outward normal of this edge in 2D (counter-clockwise loop): (dy, -dx).
                a = run[max(j - 1, 0)]
                b = run[min(j + 1, run_len - 1)]
                dx, dy = b[0] - a[0], b[1] - a[1]
                nx, ny = dy, -dx
                if banked:
                    nx, ny = nx * c - ny * sn, nx * sn + ny * c
                normals_hint.append(rv * nx + up * ny)
        faces = []
        for r in range(rows):
            for j in range(run_len - 1):
                a = r * run_len + j
                b = a + 1
                cc = a + run_len
                d = cc + 1
                faces += [(a, b, cc), (b, d, cc)]
        mesh = Mesh(np.array(verts), np.array(faces))
        hint = np.array(normals_hint)
        tri = mesh.v[mesh.f]
        normal = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        flip = np.einsum("ij,ij->i", normal, hint[mesh.f].mean(axis=1)) < 0
        mesh.f[flip] = mesh.f[flip][:, ::-1]
        pieces.setdefault(label, []).append(mesh)
    return {name: merge(*meshes) for name, meshes in pieces.items()}


def track():
    """A straight: an ice channel with rounded walls, red lips and snow banks either side."""
    return sweep_piece("S", UNIT, 4)


def kicker():
    """A straight with a kicker ramp on the ice: the floor sweeps up KICK studs to a lip at the end."""
    pieces = sweep_piece("S", UNIT, 4)
    half = FLOOR_HALF - 1.5
    rows = 16
    verts = []
    for r in range(rows + 1):
        u = UNIT * r / rows
        lift = KICK * (u / UNIT) ** 2
        y0 = -SLOPE * u
        for x in (-half, half):
            verts.append((x, y0 + lift + 0.04, -u))
            verts.append((x, y0 - 0.2, -u))
    faces = []
    for r in range(rows):
        a = r * 4
        b = a + 4
        # top (left-top a+0, right-top a+2), sides
        faces += [(a + 0, a + 2, b + 0), (a + 2, b + 2, b + 0)]
        faces += [(a + 1, a + 0, b + 1), (a + 0, b + 0, b + 1)]
        faces += [(a + 2, a + 3, b + 2), (a + 3, b + 3, b + 2)]
    end = rows * 4
    faces += [(end + 0, end + 2, end + 1), (end + 2, end + 3, end + 1)]
    ramp = oriented(Mesh(np.array(verts, dtype=float), np.array(faces)))
    ramp.smooth = False
    # A red bar along the lip and chevrons painted up the ramp (separate strips, raised a hair).
    lip_y = -SLOPE * UNIT + KICK
    lip_bar = box(2 * half, 0.5, 0.7, 0.2, 0, lip_y + 0.05, -UNIT + 0.36)
    chevrons = []
    for k, u in enumerate((4.0, 8.0, 12.0)):
        lift = KICK * (u / UNIT) ** 2
        slope = 2 * KICK * u / UNIT**2 - SLOPE
        for sign in (-1, 1):
            bar = box(8.0, 0.16, 1.0, 0.07)
            bar.rotate("y", sign * 28).translate(sign * 3.3, 0, 0)
            bar.rotate("x", math.degrees(math.atan(slope)))
            bar.translate(0, -SLOPE * u + lift + 0.12, -u)
            chevrons.append(bar)
    pieces["Kicker"] = ramp
    pieces["Trim"] = merge(pieces["Trim"], lip_bar, *chevrons)
    return pieces


def curve(kind):
    def build():
        return sweep_piece(kind, ARC, 40)

    return build


# ================================================================== the sled


def sled():
    """A two-to-four-seat bobsled: a sleek fiberglass shell with a closed nose cowl over the pilot's
    legs, an open cockpit, push bars at the back and four steel runners with curled tips."""

    def hull(p):
        x, y, z = p[..., 0], p[..., 1], p[..., 2]
        nose = np.clip((-z - 3.0) / 4.0, 0, 1)  # 0 behind the cowl, 1 at the tip
        tail = np.clip((z - 5.2) / 1.8, 0, 1)
        half_w = 1.95 * (1 - 0.42 * nose**2) - 0.15 * tail
        top = 2.25 - 0.55 * nose**1.5 + 0.25 * np.clip((-z - 2.0) / 1.5, 0, 1) * (1 - nose)
        bottom = 0.55 + 0.35 * nose**2
        cy = (top + bottom) / 2
        hy = (top - bottom) / 2
        q = np.stack([np.abs(x) / half_w, np.abs(y - cy) / hy, np.abs(z - 0.0) / 7.0], -1)
        # A rounded superellipsoid-ish box, in units of its own half sizes.
        k = 4.0
        d = (q[..., 0] ** k + q[..., 1] ** k) ** (1 / k)
        d = np.maximum(d, q[..., 2] * 1.0)
        return (d - 1.0) * np.minimum(half_w, hy)

    def cockpit(p):
        x, y, z = p[..., 0], p[..., 1], p[..., 2]
        open_z = np.maximum(-3.0 - z, z - 6.4)
        open_x = np.abs(x) - 1.55
        open_y = 0.95 - y
        return np.maximum(np.maximum(open_z, open_x), open_y)

    def shell(p):
        return np.maximum(hull(p), -cockpit(p) - 0.0)

    body = oriented(sdf_mesh(shell, (-2.3, 0.3, -7.3), (2.3, 2.7, 7.3), 0.19))
    body = taubin_smooth(body, 4)

    # The rim round the cockpit (a white coaming).
    rim_pts = []
    for i in range(48):
        a = 2 * math.pi * i / 48
        # A stadium shape: straight sides, rounded ends.
        x = 1.62 * math.cos(a)
        zc = 1.7 + 4.75 * math.sin(a) * (1 if abs(math.sin(a)) < 0.98 else 1)
        rim_pts.append((x, 2.05 - 0.12 * (1 if math.sin(a) < 0 else 0) * abs(math.sin(a)), zc))
    rim = tube_path(rim_pts, 0.16, 8, closed=True)

    # Runners: two skis per side under the front and back, curled up at the front.
    runners = []
    for sx in (-1.25, 1.25):
        for z0, z1 in ((-6.2, -1.6), (1.4, 6.0)):
            pts = []
            for i in range(10):
                t = i / 9
                z = z0 + (z1 - z0) * t
                curl = max(0.0, 1 - t / 0.22)
                pts.append((sx, 0.12 + 0.55 * curl**2, z + 0.25 * curl))
            runners.append(tube_path(pts, 0.12, 8))
            for zs in (z0 + 1.0, z1 - 0.6):
                runners.append(tube_path([(sx, 0.14, zs), (sx * 0.9, 0.75, zs)], 0.09, 6))
    # Push bars at the back (the brakeman's handles) and a bumper on the nose.
    bars = []
    for sx in (-1, 1):
        bars.append(tube_path([(sx * 2.0, 1.5, 6.6), (sx * 2.15, 1.55, 5.2), (sx * 2.1, 1.5, 3.9)], 0.13, 8))
    bumper = oriented(sphere(1.0, 10, 16)).scale(1.15, 0.5, 0.45).translate(0, 1.0, -7.0)
    plate = box(1.5, 0.08, 1.2, 0.04, 0, 0, 0)
    plate.rotate("x", -24).translate(0, 1.92, -4.6)
    return {
        "Body": body,
        "Rim": rim,
        "Runner": merge(*runners, *bars),
        "Nose": merge(bumper, plate),
    }


# ================================================================== scenery


def pine():
    """A snowy pine: five drooping tiers of needles, each capped with snow, on a short trunk."""
    tiers = []
    snows = []
    rng = np.random.default_rng(7)
    levels = [(2.0, 4.8), (4.6, 3.9), (7.0, 3.1), (9.2, 2.3), (11.2, 1.5)]
    for k, (y, r) in enumerate(levels):
        h = 3.6 - k * 0.3
        # Needles: the skirt (underside up to the snow line), drooping tips.
        skirt = [(0.0, y - 0.2), (r * 0.55, y - 0.35), (r, y - 0.7), (r * 1.02, y - 0.45), (r * 0.82, y + h * 0.18)]
        tiers.append(organic_lathe(skirt, 20, 0.09, waves=7, seed=int(rng.integers(100))))
        cap = [(r * 0.82, y + h * 0.18), (r * 0.55, y + h * 0.45), (r * 0.22, y + h * 0.8), (0.0, y + h)]
        snows.append(organic_lathe(cap, 20, 0.06, waves=7, seed=int(rng.integers(100))))
    trunk = cylinder(0.55, 2.6, 10, 0.1)
    top = sphere(0.45, 6, 10).translate(0, levels[-1][0] + 3.6 - 4 * 0.3, 0)
    return {"Needles": merge(*tiers), "Snow": merge(*snows, top), "Trunk": trunk}


def peak():
    """A far mountain: craggy rock flanks under a snow cap with ridges running down."""
    segments = 36
    rows = 26
    rng = np.random.default_rng(3)
    phase = rng.uniform(0, 6, 4)

    def radius(theta, y):
        t = y / 100.0
        base = 70 * (1 - t) ** 1.25 + 1.5
        ridge = 1 + 0.16 * math.sin(theta * 5 + phase[0]) + 0.08 * math.sin(theta * 9 + phase[1] + t * 4)
        crag = 1 + 0.05 * math.sin(theta * 17 + y * 0.3 + phase[2])
        return base * ridge * crag

    def snow_line(theta):
        return 52 + 9 * math.sin(theta * 4 + phase[3]) + 5 * math.sin(theta * 11)

    def ring(y_of_theta):
        out = []
        for s in range(segments):
            theta = 2 * math.pi * s / segments
            y = y_of_theta(theta)
            r = radius(theta, y)
            out.append((math.cos(theta) * r, y, math.sin(theta) * r))
        return out

    def band(y0_fn, y1_fn, count):
        verts = []
        for i in range(count + 1):
            t = i / count
            verts += ring(lambda th, t=t: y0_fn(th) + (y1_fn(th) - y0_fn(th)) * t)
        faces = []
        for i in range(count):
            for s in range(segments):
                a = i * segments + s
                b = i * segments + (s + 1) % segments
                c, d = a + segments, b + segments
                faces += [(a, c, b), (b, c, d)]
        return Mesh(np.array(verts), np.array(faces))

    rock = band(lambda th: 0.0, snow_line, rows // 2)
    snow = band(snow_line, lambda th: 99.0, rows // 2)
    tip = len(snow.v)
    snow.v = np.vstack([snow.v, [[0.0, 100.0, 0.0]]])
    top = (rows // 2) * segments
    snow.f = np.vstack([snow.f, [(tip, top + (s + 1) % segments, top + s) for s in range(segments)]])
    for mesh in (rock, snow):
        tri = mesh.v[mesh.f]
        normal = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        outward = tri.mean(axis=1) * np.array([1, 0, 1]) + np.array([0, 1e-3, 0])
        flip = np.einsum("ij,ij->i", normal, outward) < 0
        mesh.f[flip] = mesh.f[flip][:, ::-1]
    return {"Rock": rock, "Snow": snow}


def gate():
    """The start house: two timber towers, a roof beam with a banner and a start bar across the run.
    It spans the channel (towers stand on the snow banks)."""
    span = 2 * (FLOOR_HALF + 0.6 + LIP + 3)
    frame = []
    for sx in (-1, 1):
        x = sx * span / 2
        frame.append(box(2.6, 24, 2.6, 0.35, x, 4, 0))  # down to the snow bank's foot
        frame.append(box(3.6, 1.0, 3.6, 0.3, x, 16.5, 0))
        for y in (4.0, 10.0):
            frame.append(box(3.0, 0.6, 3.0, 0.2, x, y, 0))
    frame.append(box(span + 3.0, 1.6, 2.2, 0.4, 0, 14.6, 0))
    roof = []
    for sx in (-1, 1):
        roof.append(box(4.2, 0.7, 4.2, 0.3, sx * span / 2, 17.35, 0))
        roof.append(lathe([(1.9, 17.7), (0.05, 20.2), (0.0, 20.2)], 4).rotate("y", 45).translate(sx * span / 2, 0, 0))
    banner = box(span - 6.0, 4.2, 0.5, 0.2, 0, 11.7, 0)
    bar = box(2 * FLOOR_HALF - 1, 0.55, 0.55, 0.25, 0, 1.6, -1.6)
    lights = []
    for k in range(5):
        lights.append(sphere(0.55, 8, 12).translate(-5 + k * 2.5, 15.0, -1.25))
    return {"Frame": merge(*frame, *roof), "Banner": banner, "Bar": bar, "Lights": merge(*lights)}


def arch():
    """The finish arch: a big rounded arch over the run with a checkered banner."""
    span = 2 * (FLOOR_HALF + 0.6 + LIP + 3)
    half = span / 2
    pts = []
    for i in range(33):
        a = math.pi * i / 32
        pts.append((-math.cos(a) * half, 3 + math.sin(a) * 18, 0.0))
    pts = [(pts[0][0], -8.0, 0.0)] + pts + [(pts[-1][0], -8.0, 0.0)]  # feet down on the snow banks
    body = tube_path(pts, 1.6, 14)
    feet = merge(*(box(4.4, 1.2, 4.4, 0.4, sx * half, -7.4, 0) for sx in (-1, 1)))
    # The banner: a strip of squares hanging under the top of the arch, black and white alternating.
    dark, light = [], []
    cols, size = 12, 2.0
    for row in range(2):
        for col in range(cols):
            x = (col - (cols - 1) / 2) * size
            y = 16.2 - row * size
            tile = box(size, size, 0.4, 0.05, x, y, 0)
            (dark if (row + col) % 2 == 0 else light).append(tile)
    return {"Arch": merge(body, feet), "Dark": merge(*dark), "Light": merge(*light)}


def flag():
    """A course flag: a pole with a ball on top and a waving pennant."""
    pole = cylinder(0.14, 9.0, 10, 0.03)
    ball = sphere(0.3, 8, 12).translate(0, 9.15, 0)
    verts, faces = [], []
    cols, rows = 12, 4
    for i in range(cols + 1):
        t = i / cols
        x = 0.15 + 3.6 * t
        wave = math.sin(t * math.pi * 1.6) * 0.35 * t
        height = 2.2 * (1 - 0.45 * t)
        for j in range(rows + 1):
            y = 8.8 - height * j / rows
            verts.append((x, y, wave))
    for i in range(cols):
        for j in range(rows):
            a = i * (rows + 1) + j
            b, c, d = a + 1, a + rows + 1, a + rows + 2
            faces += [(a, b, c), (b, d, c)]
    front = Mesh(np.array(verts), np.array(faces))
    back = Mesh(np.array(verts) + np.array([0, 0, 0.04]), np.array(faces)[:, ::-1])
    # front faces -Z, back faces +Z
    tri = front.v[front.f]
    if np.cross(tri[0, 1] - tri[0, 0], tri[0, 2] - tri[0, 0])[2] > 0:
        front.f = front.f[:, ::-1].copy()
        back.f = back.f[:, ::-1].copy()
    return {"Pole": merge(pole, ball), "Cloth": merge(front, back)}


PROPS = {
    "BobsledTrack": track,
    "BobsledKicker": kicker,
    "BobsledCurveL": curve("L"),
    "BobsledCurveR": curve("R"),
    "BobsledSled": sled,
    "BobsledPine": pine,
    "BobsledPeak": peak,
    "BobsledGate": gate,
    "BobsledArch": arch,
    "BobsledFlag": flag,
}
COLORS = {
    "Ice": (200, 232, 250),
    "Snow": (245, 248, 255),
    "Trim": (225, 50, 60),
    "Kicker": (170, 215, 245),
    "Body": (220, 60, 70),
    "Rim": (250, 250, 250),
    "Runner": (60, 64, 76),
    "Nose": (40, 40, 48),
    "Needles": (40, 96, 70),
    "Trunk": (96, 64, 44),
    "Rock": (104, 108, 124),
    "Frame": (120, 80, 52),
    "Banner": (225, 50, 60),
    "Bar": (250, 210, 60),
    "Lights": (255, 80, 70),
    "Arch": (40, 120, 220),
    "Dark": (30, 30, 36),
    "Light": (250, 250, 250),
    "Pole": (230, 230, 236),
    "Cloth": (255, 90, 90),
}


if __name__ == "__main__":
    # Each track piece's pivot (its bounding box's bottom center) relative to its entry point.
    for name in ("BobsledTrack", "BobsledKicker", "BobsledCurveL", "BobsledCurveR"):
        pieces = PROPS[name]()
        allv = np.vstack([m.v for m in pieces.values()])
        lo, hi = allv.min(axis=0), allv.max(axis=0)
        print(f"{name}: anchor ({(lo[0] + hi[0]) / 2:.4f}, {lo[1]:.4f}, {(lo[2] + hi[2]) / 2:.4f}) size ({hi[0] - lo[0]:.4f}, {hi[1] - lo[1]:.4f}, {hi[2] - lo[2]:.4f})")
