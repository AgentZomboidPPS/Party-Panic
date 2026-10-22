"""Props for Minecart Mayhem: the mine cart, the rail tiles of the course (rails, ties and wooden
trestles swept along the same shapes as src/shared/Logic/MinecartMayhemTrack.luau: change them
together), the cave's rock rings, the mine's portal, the junction sign and posts, TNT crates, the
buffer stop and rubble of a dead end, the dash crystal on the rails, glowing crystal clusters and
lanterns.

    python3 tools/meshgen/generate_meshes.py --only MinecartMayhemCart,...
    PYTHONPATH=tools/meshgen python3 tools/meshgen/props/MinecartMayhem.py   (prints each rail tile's anchor)

Units are studs, +Y is up and -Z is the front (the way down the mine). Rail tiles are built in tile
axes: the entry at (0, 0, 0), f studs forward is z = -f, x is to the right, the path line at y (the
rails' top is RAIL_TOP above it); their trestles reach down to y = BOTTOM, so every tile is as tall
as the drop from its highest rail to BOTTOM. The cart's wheels sit on y = 0 (the rails' top), its
front is -Z, its wheels WHEELBASE apart on the GAUGE.
"""

import math

import numpy as np

from generate_meshes import Mesh, cylinder, extrude, icosphere, merge, rounded_box, sdf_mesh, sphere, torus

# ------------------------------------------------------------------------------------- shared numbers
LEN = {"Start": 64, "Bend": 110, "Junction": 150, "Gap": 72, "Hill": 90, "Finish": 90}
SPLIT, MERGE = 16, 134
LONG_WIDE, LONG_RISE, SHORT_WIDE, SHORT_DIP = 40, 6, 9, 3
BEND_WIDE, BEND_RUN = 36, 0.7
GAP_FROM, GAP_TO = 38, 46
TAKEOFF_NEAR, TAKEOFF_FAR = 1.2, 5.2
START_LANE = 5.5
START_MERGE = 28
GAUGE = 3.0
RAIL_W = 0.32
RAIL_Y0, RAIL_Y1 = 0.45, 0.75  # rails, above the path line
TIE_Y0, TIE_Y1 = 0.2, 0.45
TIE_W, TIE_D, TIE_STEP = 5.0, 0.6, 1.5
BOTTOM = -92.0  # trestle feet (below the cave floor everywhere)
BENT_STEP = 10.0
POST_X = 2.4


def smooth(t: float) -> float:
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def shape(kind: str, branch: int, f: float, d: int = 1, l: int = 1) -> tuple[float, float]:
    """MinecartMayhemTrack.Shape: (x, y) of a tile's path f studs in."""
    t = min(max(f / LEN[kind], 0.0), 1.0)
    if kind == "Start":
        return 0.0, -5 * smooth((f - 40) / 24)
    if kind == "Bend":
        u = min(t / BEND_RUN, 1.0)
        return d * BEND_WIDE * (1 - math.cos(math.pi * u)) / 2, -4 * smooth(t)
    if kind == "Junction":
        u = min(max((f - SPLIT) / (MERGE - SPLIT), 0.0), 1.0)
        bow = (1 - math.cos(2 * math.pi * u)) / 2
        if branch == 1:
            return l * LONG_WIDE * bow, LONG_RISE * bow
        return -l * SHORT_WIDE * bow, -SHORT_DIP * bow
    if kind == "Hill":
        return 0.0, -10 * t - 8 * math.sin(math.pi * t)
    if kind == "Finish":
        return 0.0, 4 * smooth(t)
    return 0.0, 0.0


# ------------------------------------------------------------------------------------- mesh helpers

def box(x0, x1, y0, y1, z0, z1) -> Mesh:
    v = [(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
    f = [(0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5), (0, 4, 5), (0, 5, 1), (2, 3, 7), (2, 7, 6), (0, 2, 6), (0, 6, 4),
         (1, 5, 7), (1, 7, 3)]
    mesh = Mesh(v, f)
    mesh.smooth = False
    return mesh


def oriented_box(center, right, forward, w, h, d, y_up=(0, 1, 0)) -> Mesh:
    """A box of width w (along right), height h (along up) and depth d (along forward)."""
    c, r, fw, up = (np.array(a, float) for a in (center, right, forward, y_up))
    r /= np.linalg.norm(r)
    fw /= np.linalg.norm(fw)
    corners = []
    for sx in (-0.5, 0.5):
        for sy in (-0.5, 0.5):
            for sz in (-0.5, 0.5):
                corners.append(c + r * sx * w + up * sy * h + fw * sz * d)
    f = [(0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5), (0, 4, 5), (0, 5, 1), (2, 3, 7), (2, 7, 6), (0, 2, 6), (0, 6, 4),
         (1, 5, 7), (1, 7, 3)]
    mesh = Mesh(corners, f)
    mesh.smooth = False
    return mesh


def beam(a, b, w, h=None) -> Mesh:
    """A square beam from point a to point b."""
    a, b = np.array(a, float), np.array(b, float)
    axis = b - a
    length = np.linalg.norm(axis)
    fw = axis / length
    helper = np.array([0, 1, 0]) if abs(fw[1]) < 0.9 else np.array([1, 0, 0])
    r = np.cross(fw, helper)
    r /= np.linalg.norm(r)
    up = np.cross(r, fw)
    return oriented_box((a + b) / 2, r, fw, w, h or w, length, up)


def sweep_rect(points, rights, x0, x1, y0, y1) -> Mesh:
    """A closed bar along a polyline: cross-section from x0..x1 (along each point's right vector)
    and y0..y1 (up), capped at both ends."""
    verts, faces = [], []
    for p, r in zip(points, rights):
        p, r = np.array(p, float), np.array(r, float)
        for x, y in ((x0, y0), (x0, y1), (x1, y1), (x1, y0)):
            verts.append(p + r * x + np.array([0, y, 0]))
    n = len(points)
    for i in range(n - 1):
        a, b = i * 4, (i + 1) * 4
        for k in range(4):
            k2 = (k + 1) % 4
            faces += [(a + k, b + k, b + k2), (a + k, b + k2, a + k2)]
    faces += [(0, 2, 1), (0, 3, 2)]
    e = (n - 1) * 4
    faces += [(e, e + 1, e + 2), (e, e + 2, e + 3)]
    mesh = Mesh(verts, faces)
    mesh.smooth = False
    return mesh


def noise3(p: np.ndarray, seed: int, scale: float) -> np.ndarray:
    rs = np.random.RandomState(seed)
    out = np.zeros(p.shape[:-1])
    for octave in range(5):
        k = rs.normal(size=3)
        k = k / np.linalg.norm(k) * (scale * (1.9 ** octave))
        out += np.sin(p @ k + rs.uniform(0, 6.28)) / (1.8 ** octave)
    return out


def faceted(mesh: Mesh) -> Mesh:
    mesh.smooth = False
    return mesh


# ------------------------------------------------------------------------------------- rail tiles

def path_samples(kind, branch, d=1, l=1, f0=0, f1=None):
    f1 = LEN[kind] if f1 is None else f1
    pts = []
    for f in np.arange(f0, f1 + 1e-6, 1.0):
        x, y = shape(kind, branch, f, d, l)
        pts.append((x, y, -f))
    pts = np.array(pts)
    rights = []
    for i in range(len(pts)):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, len(pts) - 1)]
        fw = b - a
        r = np.array([-fw[2], 0.0, fw[0]])
        rights.append(r / np.linalg.norm(r))
    return pts, np.array(rights)


def rails_on(pts, rights, lower=0.0):
    """Both rails along a stretch of path."""
    out = []
    if len(pts) < 2:
        return out
    for side in (-1, 1):
        cx = side * GAUGE / 2
        out.append(sweep_rect(pts, rights, cx - RAIL_W / 2, cx + RAIL_W / 2, RAIL_Y0 - lower, RAIL_Y1 - lower))
    return out


def ties_on(pts, rights, every=TIE_STEP, lower=0.0, widths=None, centers=None):
    out = []
    n = len(pts)
    k = 0.4
    while k < n - 1:
        i = int(k)
        a = k - i
        p = pts[i] * (1 - a) + pts[i + 1] * a
        r = rights[i]
        fw = pts[i + 1] - pts[i]
        w = TIE_W if widths is None else widths(p)
        c = p if centers is None else centers(p)
        out.append(oriented_box(c + np.array([0, (TIE_Y0 + TIE_Y1) / 2 - lower, 0]), r, fw, w, TIE_Y1 - TIE_Y0, TIE_D))
        k += every
    return out


def bent(p, r, width_extra=0.0, cap=True):
    """One trestle bent under the path at p: two posts to BOTTOM, a cap beam, cross braces."""
    p = np.array(p, float)
    out = []
    top = p[1] - 0.05
    xs = (-POST_X - width_extra / 2, POST_X + width_extra / 2)
    feet = []
    for x in xs:
        a = p + r * x
        foot_spread = 1.0 + (top - BOTTOM) * 0.06  # (the legs splay out toward the floor)
        b = p + r * (x + math.copysign(foot_spread, x))
        out.append(beam((a[0], top, a[2]), (b[0], BOTTOM, b[2]), 0.7))
        feet.append((a, b))
    if cap:
        mid = p + np.array([0, -0.12, 0])
        fw = np.cross(r, [0, 1, 0])
        out.append(oriented_box(mid, r, fw, 2 * POST_X + width_extra + 1.4, 0.55, 0.75))
    # cross braces every 12 studs down
    y = top - 2.0
    flip = False
    (a0, b0), (a1, b1) = feet
    while y - 14 > top - 56:  # (deeper down it's lost in the dark)
        def leg(a, b, yy):
            t = (top - yy) / (top - BOTTOM)
            return a + (b - a) * t + np.array([0, 0, 0])
        y2 = y - 14
        pa, pb = leg(a0, b0, y), leg(a1, b1, y2)
        if flip:
            pa, pb = leg(a0, b0, y2), leg(a1, b1, y)
        out.append(beam((pa[0], y if not flip else y2, pa[2]), (pb[0], y2 if not flip else y, pb[2]), 0.4))
        pl, pr = leg(a0, b0, y2), leg(a1, b1, y2)
        out.append(beam((pl[0], y2, pl[2]), (pr[0], y2, pr[2]), 0.45))
        flip = not flip
        y = y2
    return out


def stringers(pts, rights):
    """Long beams under the ties along the path (they tie the bents together)."""
    out = []
    for side in (-1, 1):
        out.append(sweep_rect(pts, rights, side * 1.9 - 0.3, side * 1.9 + 0.3, -0.45, 0.2))
    return out


def bents_along(pts, rights, step=BENT_STEP, skip=None, extra=None):
    out = []
    k = 3.0
    while k < len(pts) - 2:
        i = int(k)
        f = -pts[i][2]
        if skip is None or not skip(f):
            out += bent(pts[i], rights[i], 0.0 if extra is None else extra(f))
        k += step
    return out


def rail_tile(kind, d=1, l=1):
    rails, ties, trestle, marker = [], [], [], []
    if kind == "Junction":
        p1, r1 = path_samples(kind, 1, d, l)
        p2, r2 = path_samples(kind, 2, d, l)
        sep = np.abs(p1[:, 0] - p2[:, 0])

        def sep_at(f):
            i = int(min(max(round(f), 0), len(sep) - 1))
            return sep[i]

        # Long way: full rails; ties that span both ways where they're close (the switch and the merge).
        rails += rails_on(p1, r1)
        ties += ties_on(p1, r1, widths=lambda p: TIE_W + (sep_at(-p[2]) if sep_at(-p[2]) < TIE_W + 0.2 else 0),
                        centers=lambda p: p + (np.array([(shape(kind, 2, -p[2], d, l)[0] - p[0]) / 2, 0, 0])
                                               if sep_at(-p[2]) < TIE_W + 0.2 else 0))
        # The other way: rails once they're apart, ties and stringers once clear of the long way's.
        on = sep >= 0.4
        idx = np.where(on)[0]
        if len(idx):
            a, b = idx[0], idx[-1]
            rails += rails_on(p2[a:b + 1], r2[a:b + 1], lower=0.02)
        clear = np.where(sep >= TIE_W + 0.2)[0]
        if len(clear):
            a, b = clear[0], clear[-1]
            ties += ties_on(p2[a:b + 1], r2[a:b + 1], lower=0.04)
            trestle += stringers(p2[a:b + 1], r2[a:b + 1])
        trestle += stringers(p1, r1)
        trestle += bents_along(p1, r1, extra=lambda f: sep_at(f) if sep_at(f) < 6.6 else 0.0)
        trestle += bents_along(p2, r2, skip=lambda f: sep_at(f) < 6.6)
    else:
        f0 = 6 if kind == "Start" else 0
        p, r = path_samples(kind, 1, d, l, f0=f0)
        if kind == "Gap":
            near = p[:, 2] >= -GAP_FROM
            far = p[:, 2] <= -GAP_TO
            for part in (near, far):
                idx = np.where(part)[0]
                seg_p, seg_r = p[idx[0]:idx[-1] + 1], r[idx[0]:idx[-1] + 1]
                rails += rails_on(seg_p, seg_r)
                ties += ties_on(seg_p, seg_r)
                trestle += stringers(seg_p, seg_r)
            # broken stubs bent down over the drop
            for f_edge, sign in ((GAP_FROM, -1), (GAP_TO, 1)):
                for side in (-1, 1):
                    x = side * GAUGE / 2
                    a = (x, RAIL_Y1 - 0.15, -f_edge)
                    b = (x + side * 0.3, RAIL_Y1 - 1.1, -f_edge + sign * 1.6)
                    rails.append(beam(a, b, 0.3))
                trestle.append(beam((-2.2, -0.2, -f_edge), (1.8, -2.4, -f_edge + sign * 2.4), 0.5))
            trestle += bents_along(p, r, skip=lambda f: GAP_FROM - 3 < f < GAP_TO + 3)
            for f_edge in (GAP_FROM - 2.2, GAP_TO + 2.2):
                i = int(round(f_edge - f0))
                trestle += bent(p[i], r[i])
            # the take-off marker: three yellow chevrons on the ties where the front wheels jump
            for k in range(3):
                fc = GAP_FROM - TAKEOFF_FAR + 0.6 + k * (TAKEOFF_FAR - TAKEOFF_NEAR - 1.2) / 2
                tip = 0.7
                chevron = [(-1.1, 0.35), (0.0, -0.35), (1.1, 0.35), (1.1, 0.75), (0.0, 0.05), (-1.1, 0.75)]
                poly = [(x, -(z + tip)) for x, z in chevron]
                m = extrude(poly, 0.06).rotate("x", -90).translate(0, TIE_Y1 + 0.04, -fc)
                marker.append(m)
            marker.append(box(-2.55, 2.55, TIE_Y1 - 0.02, TIE_Y1 + 0.02, -(GAP_FROM - TAKEOFF_NEAR), -(GAP_FROM - TAKEOFF_FAR)))
        else:
            rails += rails_on(p, r)
            ties += ties_on(p, r)
            if kind == "Start":
                trestle += stringers(p[24:], r[24:])
                trestle += bents_along(p[24:], r[24:])
                # the station's stub tracks, one per start lane
                for lane in range(1, 13):
                    x = (lane - 6.5) * START_LANE
                    sp = np.array([(x, 0.0, -f) for f in np.arange(-6, 5, 1.0)])
                    sr = np.array([(1.0, 0.0, 0.0)] * len(sp))
                    ties += ties_on(sp, sr, every=1.6)
                    # the lane's lead-in: rails resting on the deck along Track.StartOffset, until they
                    # meet the main line's (each lane a little lower, so crossing rails never share a top)
                    pts = []
                    for f in np.arange(-6, START_MERGE + 0.01, 1.0):
                        o = x * (1 - smooth(max(f, 0) / START_MERGE))
                        if abs(o) < 0.35:
                            break
                        pts.append((o, 0.0, -f))
                    if len(pts) >= 2:
                        lp, lr = np.array(pts), []
                        for i in range(len(lp)):
                            fw = lp[min(i + 1, len(lp) - 1)] - lp[max(i - 1, 0)]
                            r = np.array([-fw[2], 0.0, fw[0]])
                            lr.append(r / np.linalg.norm(r))
                        drop = 0.02 + 0.015 * abs(lane - 6.5)
                        for side in (-1, 1):
                            cx = side * GAUGE / 2
                            rails.append(sweep_rect(lp, np.array(lr), cx - RAIL_W / 2, cx + RAIL_W / 2, -0.1, RAIL_Y1 - drop))
                    # a buffer beam behind each stub
                    trestle.append(box(x - 2.0, x + 2.0, 0.2, 1.3, 6.2, 6.8))
            else:
                trestle += stringers(p, r)
                trestle += bents_along(p, r)
    pieces = {"Rails": merge(*rails), "Ties": merge(*ties), "Trestle": merge(*trestle)}
    if marker:
        pieces["Marker"] = merge(*marker)
    return pieces


# ------------------------------------------------------------------------------------- the cart

def cart():
    """A riveted mine cart: a flared steel tub with a coloured rim and bands, rivets, four spoked
    wheels on the gauge, a badge plate on the back."""
    def tub_ring(y, hw, hd, r=0.35, n=6):
        # a rounded rectangle outline at height y (half width hw, half depth hd)
        pts = []
        for cx, cz, a0 in ((hw - r, -(hd - r), 270), (hw - r, hd - r, 0), (-(hw - r), hd - r, 90), (-(hw - r), -(hd - r), 180)):
            for k in range(n + 1):
                a = math.radians(a0 + 90 * k / n)
                pts.append((cx + r * math.cos(a), y, cz + r * math.sin(a)))
        return pts

    rings = [tub_ring(0.95, 1.45, 1.95), tub_ring(3.0, 1.75, 2.3)]
    inner = [tub_ring(1.15, 1.3, 1.8), tub_ring(3.0, 1.6, 2.15)]
    n = len(rings[0])
    verts = rings[0] + rings[1] + inner[1] + inner[0]
    faces = []
    for ring in range(3):
        a, b = ring * n, (ring + 1) * n
        for k in range(n):
            k2 = (k + 1) % n
            faces += [(a + k, b + k2, b + k), (a + k, a + k2, b + k2)]
    # bottoms (outer and inner floor)
    c0 = len(verts)
    verts.append((0, 0.95, 0))
    c1 = len(verts)
    verts.append((0, 1.15, 0))
    for k in range(n):
        k2 = (k + 1) % n
        faces.append((c0, k, k2))
        faces.append((c1, 3 * n + k2, 3 * n + k))
    body = Mesh(verts, faces)
    body.smooth = False
    # the rim and two bands (trim), slightly proud of the tub
    rim = merge(*[beam(a, b, 0.22) for a, b in zip(tub_ring(3.0, 1.8, 2.35), tub_ring(3.0, 1.8, 2.35)[1:] + tub_ring(3.0, 1.8, 2.35)[:1])])
    bands = []
    for y in (1.55, 2.35):
        t = (y - 0.95) / 2.05
        hw, hd = 1.45 + 0.3 * t + 0.06, 1.95 + 0.35 * t + 0.06
        ring = tub_ring(y, hw, hd)
        bands.append(merge(*[beam(a, b, 0.16, 0.3) for a, b in zip(ring, ring[1:] + ring[:1])]))
    trim = merge(rim, *bands)
    rivets = []
    for y in (1.55, 2.35):
        t = (y - 0.95) / 2.05
        hw, hd = 1.45 + 0.3 * t + 0.14, 1.95 + 0.35 * t + 0.14
        for k in range(-3, 4):
            z = k * hd / 3.6
            for side in (-1, 1):
                rivets.append(icosphere(0.08, 0).translate(side * hw, y, z))
        for k in range(-2, 3):
            x = k * hw / 2.6
            for side in (-1, 1):
                rivets.append(icosphere(0.08, 0).translate(x, y, side * hd))
    # chassis, axles and wheels
    chassis = merge(box(-1.25, 1.25, 0.62, 0.95, -2.0, 2.0), box(-1.8, 1.8, 0.75, 0.95, 1.95, 2.25), box(-1.8, 1.8, 0.75, 0.95, -2.25, -1.95))
    wheels = []
    for z in (-1.4, 1.4):
        wheels.append(cylinder(0.12, 3.4, 10).rotate("z", 90).translate(1.7, 0.55, z))
        for side in (-1, 1):
            w = merge(torus(0.45, 0.1, 18, 6).rotate("z", 90),
                      *[box(-0.04, 0.04, -0.42, 0.42, -0.05, 0.05).rotate("x", a) for a in (0, 60, 120)],
                      cylinder(0.14, 0.24, 10).rotate("z", 90).translate(0.12, 0, 0))
            flange = cylinder(0.56, 0.06, 18).rotate("z", 90).translate(-side * 0.1 + 0.03, 0, 0)
            wheels.append(merge(w, flange).translate(side * GAUGE / 2, 0.55, z))
    # the badge plate on the back (+Z), a disc the game prints the rider's lane number on
    badge = cylinder(0.55, 0.06, 20).rotate("x", 90).translate(0, 2.0, 2.24 + 0.17)
    return {"Body": body, "Trim": trim, "Rivets": merge(*rivets), "Chassis": chassis, "Wheels": merge(*wheels),
            "Badge": badge}


# ------------------------------------------------------------------------------------- the cave

def cave_ring():
    """A ring of cave rock around the track: walls from the floor (y = 0) up past the rails (y = 54)
    and an arch over them, 50 studs deep, lumpy and faceted, with crystals growing on its inside."""
    hw, wall, arch, thick, depth = 46.0, 54.0, 30.0, 9.0, 54.0

    def inner_dist(p):
        x, y = p[..., 0], p[..., 1]
        below = np.abs(x) - hw
        yy = np.maximum(y - wall, 0)
        above = np.sqrt((x / hw) ** 2 + (yy / arch) ** 2) * hw - hw
        return np.where(y <= wall, below, above)

    def sdf(p):
        d_in = inner_dist(p)  # < 0 inside the tunnel
        shell = np.abs(d_in - thick / 2) - thick / 2
        shell += noise3(p, 7, 0.06) * 3.2
        z = np.abs(p[..., 2]) - depth / 2
        bottom = -p[..., 1]
        return np.maximum(np.maximum(shell, z), bottom)

    rock = faceted(sdf_mesh(sdf, (-hw - thick - 6, -1, -depth / 2 - 1), (hw + thick + 6, wall + arch + thick + 6, depth / 2 + 1), 4.6))
    rs = np.random.RandomState(3)
    crystals = []
    for k in range(9):
        side = -1 if k % 2 == 0 else 1
        y = rs.uniform(30, 70)
        if y <= wall:
            x = side * (hw - 1.0)
        else:
            yy = y - wall
            x = side * hw * math.sqrt(max(0.0, 1 - (yy / arch) ** 2)) * 0.97
        z = rs.uniform(-depth / 2 + 4, depth / 2 - 4)
        crystals.append(crystal_spike(rs.uniform(0.6, 1.1), rs.uniform(3, 6)).rotate("z", -side * rs.uniform(50, 80))
                        .rotate("y", rs.uniform(0, 360)).translate(x, y, z))
    return {"Rock": rock, "Crystal": merge(*crystals)}


def crystal_spike(r, h, sides=6):
    """A pointed hexagonal crystal standing on y = 0."""
    ring = [(r * math.cos(2 * math.pi * k / sides), r * math.sin(2 * math.pi * k / sides)) for k in range(sides)]
    verts = [(x, 0, z) for x, z in ring] + [(x, h, z) for x, z in ring] + [(0, h + r * 1.6, 0), (0, 0, 0)]
    faces = []
    for k in range(sides):
        k2 = (k + 1) % sides
        faces += [(k, sides + k2, k2), (k, sides + k, sides + k2)]
        faces.append((sides + k, 2 * sides, sides + k2))
        faces.append((k, k2, 2 * sides + 1))
    m = Mesh(verts, faces)
    m.smooth = False
    return m


def cluster():
    """A cluster of big glowing crystals on a rock base."""
    rs = np.random.RandomState(11)
    spikes = [crystal_spike(1.2, 6.5)]
    for k in range(6):
        a = k * 60 + rs.uniform(-15, 15)
        spikes.append(crystal_spike(rs.uniform(0.5, 0.9), rs.uniform(2.0, 4.5)).rotate("z", rs.uniform(20, 40))
                      .rotate("y", a).translate(math.cos(math.radians(a)) * 1.5, 0, -math.sin(math.radians(a)) * 1.5))
    base = faceted(icosphere(2.6, 1, noise=0.25, seed=4).scale(1.0, 0.45, 1.0))
    return {"Crystal": merge(*spikes).translate(0, 0.6, 0), "Rock": base.translate(0, 0.4, 0)}


def rail_crystal():
    """The dash crystal sitting on the ties between the rails: a glowing gem in a little ring of
    stones, low enough for a cart to roll right over it."""
    gem = merge(crystal_spike(0.32, 0.5).translate(0, 0.08, 0),
                crystal_spike(0.2, 0.25).rotate("z", 30).translate(0.35, 0.05, 0.1),
                crystal_spike(0.2, 0.25).rotate("z", -30).translate(-0.35, 0.05, -0.1))
    stones = merge(*[faceted(icosphere(0.18, 0, noise=0.2, seed=k)).translate(0.55 * math.cos(k * 1.05), 0.1, 0.55 * math.sin(k * 1.05))
                     for k in range(6)])
    return {"Crystal": gem, "Stones": stones}


def portal():
    """The mine's portal: a cliff of rock with the tunnel through it and a timber frame round the
    opening. Rails pass through at y = 46 (the game sets the portal 46 below them)."""
    rail_y = 46.0
    hw, top = 80.0, 112.0

    def sdf(p):
        x, y, z = p[..., 0], p[..., 1], p[..., 2]
        face = np.maximum.reduce([np.abs(x) - hw, -y, y - top, np.abs(z) - 9])
        face += noise3(p, 21, 0.045) * 3.5
        hole = np.maximum.reduce([np.abs(x) - 7.2, rail_y - 1 - y, y - (rail_y + 13.5), np.abs(z) - 30])
        return np.maximum(face, -hole)

    rock = faceted(sdf_mesh(sdf, (-hw - 6, -1, -15), (hw + 6, top + 6, 15), 4.2))
    frame = []
    for side in (-1, 1):
        frame.append(box(side * 7.3 - 0.6, side * 7.3 + 0.6, rail_y - 1, rail_y + 13.6, -10.5, -8.8))
    frame.append(box(-8.6, 8.6, rail_y + 12.6, rail_y + 14.2, -10.7, -8.6))
    frame.append(box(-6.5, 6.5, rail_y + 14.2, rail_y + 16.8, -10.2, -9.6))  # (the name board)
    for side in (-1, 1):
        frame.append(beam((side * 7.3, rail_y + 7, -10.6), (side * 3.6, rail_y + 13.3, -10.6), 0.6))
    lamps = [sphere(0.5, 8, 10).translate(side * 9.2, rail_y + 9.5, -10.4) for side in (-1, 1)]
    return {"Rock": rock, "Timber": merge(*frame), "Glow": merge(*lamps)}


# ------------------------------------------------------------------------------------- props

def sign():
    """The gantry over the track before a switch: two posts and a beam; the game hangs a board on
    each side (y 6.9..9.5) saying what's down that way."""
    parts = []
    for side in (-1, 1):
        parts.append(box(side * 7.2 - 0.35, side * 7.2 + 0.35, -24.0, 11.0, -0.35, 0.35))  # (down into the dark)
        parts.append(beam((side * 7.2, 7.0, 0), (side * 5.2, 10.3, 0), 0.35))
    parts.append(box(-7.8, 7.8, 10.3, 11.0, -0.4, 0.4))
    for side in (-1, 1):
        for x in (side * 1.5, side * 5.7):
            parts.append(box(x - 0.06, x + 0.06, 9.5, 10.3, -0.06, 0.06))
    lamp = merge(sphere(0.35, 8, 10).translate(0, 10.0, -0.5))
    return {"Timber": merge(*parts), "Chains": merge(*[box(-0.05, 0.05, 9.5, 10.3, -0.05, 0.05)]), "Glow": lamp}


def post():
    return {"Timber": merge(box(-0.25, 0.25, -24.0, 5.0, -0.25, 0.25), box(-0.45, 0.45, -0.3, 0.0, -0.45, 0.45))}


def tnt():
    """A wooden crate of red dynamite with a fuse."""
    crate = merge(box(-0.85, 0.85, 0.0, 1.3, -0.65, 0.65))
    slats = merge(*[box(-0.9, 0.9, y, y + 0.16, -0.7, 0.7) for y in (0.1, 1.05)],
                  *[box(x, x + 0.16, 0.0, 1.3, -0.7, 0.7) for x in (-0.9, 0.74)])
    sticks = merge(*[cylinder(0.17, 1.0, 10).translate(x, 1.3, z) for x in (-0.4, 0.0, 0.4) for z in (-0.2, 0.2)])
    band = merge(torus(0.0, 0.0, 3, 3)) if False else box(-0.62, 0.62, 1.65, 1.8, -0.42, 0.42)
    fuse = merge(cylinder(0.04, 0.5, 6).rotate("z", 20).translate(0.0, 2.3, 0.0), sphere(0.09, 6, 8).translate(-0.17, 2.78, 0))
    return {"Crate": crate, "Slats": slats, "Sticks": sticks, "Band": band, "Fuse": fuse}


def buffer():
    """A buffer stop at the end of a dead end: timber bracing and a red and white striped beam."""
    posts = merge(*[box(x - 0.3, x + 0.3, 0.0, 2.6, -0.3, 0.3) for x in (-1.5, 1.5)],
                  *[beam((x, 0.1, 2.2), (x, 2.2, 0.0), 0.35) for x in (-1.5, 1.5)])
    stripes_a, stripes_b = [], []
    for k in range(6):
        x0 = -2.4 + k * 0.8
        (stripes_a if k % 2 == 0 else stripes_b).append(box(x0, x0 + 0.8, 1.4, 2.3, -0.75, -0.3))
    pads = merge(*[cylinder(0.3, 0.35, 12).rotate("x", 90).translate(x, 1.85, -0.75) for x in (-1.5, 1.5)])
    return {"Timber": posts, "StripeA": merge(*stripes_a), "StripeB": merge(*stripes_b), "Pads": pads}


def rubble():
    """Fallen rock over the rails past a dead end's buffer stop."""
    def sdf(p):
        d = np.full(p.shape[:-1], 1e9)
        rs = np.random.RandomState(5)
        for _ in range(9):
            c = np.array([rs.uniform(-3.5, 3.5), rs.uniform(0.5, 2.5), rs.uniform(-4, 4)])
            r = rs.uniform(1.4, 2.6)
            d = np.minimum(d, np.linalg.norm(p - c, axis=-1) - r)
        d += noise3(p, 9, 0.5) * 0.35
        return np.maximum(d, -p[..., 1])

    return {"Rock": faceted(sdf_mesh(sdf, (-7, -0.5, -7.5), (7, 6, 7.5), 0.75))}


def lantern():
    """A miner's lantern hanging from a bracket on a post (the bracket reaches over -X... the game
    turns it to hang toward the track)."""
    pole = box(-0.2, 0.2, -24.0, 6.2, -0.2, 0.2)  # (down into the dark)
    arm = merge(box(-1.4, 0.2, 5.8, 6.1, -0.12, 0.12), beam((0, 5.0, 0), (-0.9, 5.9, 0), 0.15))
    cage = merge(box(-1.6, -1.0, 5.15, 5.25, -0.3, 0.3), box(-1.6, -1.0, 4.0, 4.1, -0.3, 0.3),
                 *[box(x - 0.04, x + 0.04, 4.1, 5.15, z - 0.04, z + 0.04) for x in (-1.55, -1.05) for z in (-0.25, 0.25)],
                 box(-1.34, -1.26, 5.25, 5.75, -0.04, 0.04))
    glow = cylinder(0.24, 1.0, 10).translate(-1.3, 4.12, 0)
    return {"Timber": merge(pole, arm), "Iron": cage, "Glow": glow}


PROPS = {
    "MinecartMayhemCart": cart,
    "MinecartMayhemRailStart": lambda: rail_tile("Start"),
    "MinecartMayhemRailBendL": lambda: rail_tile("Bend", d=-1),
    "MinecartMayhemRailBendR": lambda: rail_tile("Bend", d=1),
    "MinecartMayhemRailJunctionL": lambda: rail_tile("Junction", l=-1),
    "MinecartMayhemRailJunctionR": lambda: rail_tile("Junction", l=1),
    "MinecartMayhemRailGap": lambda: rail_tile("Gap"),
    "MinecartMayhemRailHill": lambda: rail_tile("Hill"),
    "MinecartMayhemRailFinish": lambda: rail_tile("Finish"),
    "MinecartMayhemCave": cave_ring,
    "MinecartMayhemPortal": portal,
    "MinecartMayhemSign": sign,
    "MinecartMayhemPost": post,
    "MinecartMayhemTNT": tnt,
    "MinecartMayhemBuffer": buffer,
    "MinecartMayhemRubble": rubble,
    "MinecartMayhemCrystal": rail_crystal,
    "MinecartMayhemCluster": cluster,
    "MinecartMayhemLantern": lantern,
}
COLORS = {
    "Rails": (120, 120, 130), "Ties": (120, 82, 50), "Trestle": (92, 62, 38), "Marker": (255, 205, 40),
    "Body": (96, 100, 110), "Trim": (255, 80, 90), "Rivets": (220, 180, 90), "Chassis": (60, 55, 60),
    "Wheels": (45, 45, 52), "Badge": (250, 250, 245),
    "Rock": (82, 70, 96), "Crystal": (120, 220, 255), "Timber": (110, 76, 46), "Glow": (255, 200, 120),
    "Chains": (70, 70, 75), "Crate": (170, 120, 70), "Slats": (125, 85, 50), "Sticks": (220, 50, 45),
    "Band": (40, 35, 35), "Fuse": (230, 200, 150), "StripeA": (230, 50, 50), "StripeB": (245, 245, 240),
    "Pads": (40, 40, 45), "Stones": (90, 80, 100), "Iron": (50, 50, 55),
}


if __name__ == "__main__":
    for name in PROPS:
        if "Rail" not in name:
            continue
        pieces = PROPS[name]()
        allv = np.vstack([m.v for m in pieces.values()])
        lo, hi = allv.min(axis=0), allv.max(axis=0)
        c = ((lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2)
        size = hi - lo
        print(f"\t{name} = {{ {c[0]:.4f}, {c[1]:.4f}, {c[2]:.4f}, {size[0]:.4f}, {size[1]:.4f}, {size[2]:.4f} }},")
