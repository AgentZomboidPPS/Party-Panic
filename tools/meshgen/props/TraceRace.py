"""Props for Trace Race: the giant crayon everyone rides, the clipboard's metal clip and the desk
clutter round the clipboard (a crayon box, a pencil, an eraser, a sharpener and a paper clip).

The crayon lies tilted the way you hold one to draw: its tip touches the paper at the front (-Z) and
its back end rises behind. The tip's lowest point is the prop's lowest point (y = 0), at x = 0 and
z = CRAYON_TIP_Z (printed by the generator; TIP in src/server/MiniGames/TraceRace.luau must match).

    python3 tools/meshgen/generate_meshes.py --only TraceRaceCrayon,TraceRaceClip,...
"""

from __future__ import annotations

import math

import numpy as np

from generate_meshes import Mesh, cylinder, lathe, merge, rounded_box, sphere, taper, torus, tube

CRAYON_TILT = 22.0  # degrees the crayon's axis rises from the paper
CRAYON_LENGTH = 14.0
CRAYON_RADIUS = 1.15


def _lay(mesh: Mesh) -> Mesh:
    """A crayon part built standing on its tip (along +Y) laid along +Z and tilted up behind."""
    return mesh.rotate("x", 90).rotate("x", -CRAYON_TILT)


def _crayon_parts(length=CRAYON_LENGTH, radius=CRAYON_RADIUS, segments=28):
    r = radius
    cone = 3.4
    # Wax: a rounded, slightly worn tip, a cone to the shoulder, the body and a bevelled back end.
    profile = [(0.0, 0.0), (0.16, 0.015), (0.27, 0.07), (0.33, 0.16)]
    for i in range(1, 9):
        t = i / 8
        profile.append((0.33 + (r - 0.33) * t, 0.16 + (cone - 0.16) * t))
    profile += [(r, length - 0.25), (r - 0.08, length - 0.06), (r - 0.25, length), (0.0, length)]
    wax = lathe(profile, segments)
    # The paper wrapper with rolled edges.
    w0, w1 = 4.6, length - 1.3
    rw = r + 0.07
    wrapper = lathe([(0.0, w0), (r + 0.01, w0), (rw, w0 + 0.06), (rw, w1 - 0.06), (r + 0.01, w1), (0.0, w1)], segments)
    # Printed bands: a solid ring near each end and two wavy lines round the middle.
    bands = []
    for y in (w0 + 0.45, w1 - 0.75):
        bands.append(lathe([(0.0, y), (rw + 0.015, y), (rw + 0.015, y + 0.3), (0.0, y + 0.3)], segments))
    for y in ((w0 + w1) / 2 - 0.9, (w0 + w1) / 2 + 0.9):
        pts = []
        for i in range(73):
            a = 2 * math.pi * i / 72
            pts.append((math.cos(a) * (rw + 0.01), y + 0.22 * math.sin(a * 7), math.sin(a) * (rw + 0.01)))
        bands.append(tube(pts, 0.08, 6))
    return wax, wrapper, merge(*bands)


def crayon():
    """The giant crayon a player rides: Wax and Wrapper take the player's colour, Bands are dark."""
    wax, wrapper, bands = (_lay(m) for m in _crayon_parts())
    pieces = {"Wax": wax, "Wrapper": wrapper, "Bands": bands}
    allv = np.vstack([m.v for m in pieces.values()])
    lowest = allv[np.argmin(allv[:, 1])]
    lo, hi = allv.min(axis=0), allv.max(axis=0)
    # Lowest point on y = 0; the box's middle on x = 0, z = 0 (MeshLibrary pivots there).
    shift = np.array([-(lo[0] + hi[0]) / 2, -lo[1], -(lo[2] + hi[2]) / 2])
    for m in pieces.values():
        m.v = m.v + shift
    tip = lowest + shift
    size = hi - lo
    print(f"  CRAYON_TIP_Z = {tip[2]:.3f}  height {size[1]:.3f}  length {size[2]:.3f}")
    # Where a rider's feet go: the top of the crayon 8.6 studs up the axis from the tip.
    a = math.radians(CRAYON_TILT)
    d = 8.6
    top = (0.0, d * math.sin(a) + (CRAYON_RADIUS + 0.07) * math.cos(a), d * math.cos(a) - (CRAYON_RADIUS + 0.07) * math.sin(a))
    print(f"  rider foot (from the tip): y {top[1]:.3f} z {top[2]:.3f}")
    return pieces


def _slab_along(curve: list[tuple[float, float]], width: float, thickness: float) -> Mesh:
    """A strip of `thickness` swept along a curve in the YZ plane (points are (z, y)), `width` wide
    in X: a bent sheet of metal. Closed (the generator turns it outward)."""
    pts = np.array(curve, dtype=float)
    n = len(pts)
    verts = []
    for i in range(n):
        p = pts[i]
        t = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]
        t /= np.linalg.norm(t)
        normal = np.array([-t[1], t[0]])  # (z, y) rotated a quarter turn
        for side in (-1, 1):
            q = p + normal * thickness / 2 * side
            for x in (-width / 2, width / 2):
                verts.append((x, q[1], q[0]))
    faces = []
    for i in range(n - 1):
        a = i * 4
        b = a + 4
        # corners per ring: 0 (-n, -x), 1 (-n, +x), 2 (+n, -x), 3 (+n, +x)
        for p, q in ((0, 1), (1, 3), (3, 2), (2, 0)):
            faces += [(a + p, b + p, a + q), (a + q, b + p, b + q)]
    for ring, flip in ((0, False), ((n - 1) * 4, True)):
        quad = [(ring + 0, ring + 1, ring + 3), (ring + 0, ring + 3, ring + 2)]
        faces += [(f[0], f[2], f[1]) if flip else f for f in quad]
    mesh = Mesh(verts, faces)
    mesh.smooth = False
    return mesh


def clip():
    """A clipboard clip: a base plate riveted to the board, a curled spring lever and a hanging ring."""
    plate = rounded_box(22.0, 0.7, 7.0, 0.3).translate(0, 0.35, 0)
    curve = []
    for i in range(25):
        t = i / 24
        z = -3.3 + 6.6 * t
        y = 0.9 + 2.6 * math.sin(math.pi * min(t * 1.25, 1.0)) ** 0.8 + 1.2 * t
        curve.append((z, y))
    # The curl at the back: the lever rolls over into a lip.
    cz, cy = curve[-1]
    for i in range(1, 9):
        a = math.pi * i / 8
        curve.append((cz + 0.9 * math.sin(a), cy + 0.9 - 0.9 * math.cos(a)))
    lever = _slab_along(curve, 19.0, 0.45)
    side_l = rounded_box(0.5, 2.6, 4.0, 0.2).translate(-9.0, 1.9, 0.6)
    side_r = rounded_box(0.5, 2.6, 4.0, 0.2).translate(9.0, 1.9, 0.6)
    hinge = cylinder(0.55, 19.4, 20).rotate("z", 90).translate(9.7, 2.3, 0.6)
    ring = torus(2.1, 0.45, 32, 10).rotate("x", 90).translate(0, 4.6, 2.6)
    rivets = merge(*(sphere(0.55, 6, 12).scale(1, 0.5, 1).translate(x, 0.7, -2.2) for x in (-8.0, -3.0, 3.0, 8.0)))
    return {"Metal": merge(plate, lever, side_l, side_r, ring), "Hinge": hinge, "Rivets": rivets}


def _small_crayon(length: float, radius: float) -> Mesh:
    wax, wrapper, bands = _crayon_parts(length, radius, 16)
    return wax, wrapper


def crayon_box():
    """An open box of crayons: a green-and-yellow box with chevrons and six crayons poking out."""
    box = rounded_box(16.0, 18.0, 6.0, 0.5).translate(0, 9.0, 0)
    flap = rounded_box(16.0, 5.0, 0.4, 0.15).rotate("x", -28).translate(0, 19.5, 3.6)
    chev = []
    for i in range(-2, 3):
        x = i * 3.0
        chev.append(rounded_box(1.9, 0.45, 0.3, 0.12).rotate("z", 40).translate(x - 0.7, 6.0, -3.05))
        chev.append(rounded_box(1.9, 0.45, 0.3, 0.12).rotate("z", -40).translate(x + 0.7, 6.0, -3.05))
    band = rounded_box(16.2, 3.0, 6.2, 0.3).translate(0, 13.5, 0)
    pieces = {"Box": merge(box, flap), "Band": band, "Chevrons": merge(*chev)}
    names = ["CrayonA", "CrayonB", "CrayonC", "CrayonD", "CrayonE", "CrayonF"]
    for i, name in enumerate(names):
        wax, wrapper = _small_crayon(14.0 + (i % 3) * 1.2, 1.15)
        lift = 7.0 + (i % 3) * 1.6
        x = -6.25 + i * 2.5
        tilt = (i - 2.5) * 3.0
        for m in (wax, wrapper):
            # Standing tip-up in the box.
            m.rotate("x", 180).translate(0, 14.0 + (i % 3) * 1.2, 0).rotate("z", tilt).translate(x, lift, 0)
        pieces[name] = merge(wax, wrapper)
    return pieces


def pencil():
    """A yellow hexagonal pencil lying on its side along Z: sharpened wood, graphite, a metal ferrule
    and a pink eraser."""
    body = lathe([(0.0, 6.0), (2.0, 6.0), (2.0, 52.0), (0.0, 52.0)], 6)
    wood = lathe([(0.0, 1.6), (0.55, 1.6), (1.97, 6.02), (0.0, 6.02)], 24)
    lead = lathe([(0.0, 0.0), (0.18, 0.05), (0.56, 1.62), (0.0, 1.62)], 16)
    ferrule = lathe([(0.0, 51.8), (2.1, 51.8), (2.15, 52.3), (2.08, 52.8), (2.15, 53.3), (2.08, 53.8),
                     (2.15, 54.3), (2.1, 55.0), (0.0, 55.0)], 24)
    eraser = lathe([(0.0, 54.9), (1.95, 54.9), (1.95, 57.6), (1.75, 58.2), (1.2, 58.5), (0.0, 58.55)], 24)
    pieces = {"Body": body, "Wood": wood, "Lead": lead, "Ferrule": ferrule, "Eraser": eraser}
    for m in pieces.values():
        m.rotate("x", -90).translate(0, 2.0, 29.0)  # lying along Z, point at the front (-Z)
    return pieces


def eraser():
    """A chunky pink eraser with a blue paper sleeve round its middle, one corner worn round."""
    rubber = rounded_box(10.0, 4.0, 18.0, 1.4).translate(0, 2.0, 0)
    sleeve = rounded_box(10.5, 4.5, 9.0, 0.35).translate(0, 2.0, 2.0)
    stripe = rounded_box(10.7, 1.0, 9.2, 0.3).translate(0, 2.3, 2.0)
    return {"Rubber": rubber, "Sleeve": sleeve, "Stripe": stripe}


def sharpener():
    """A metal pencil sharpener: a grooved block, the cone hole, the blade and its screw."""
    body = rounded_box(10.0, 7.0, 12.0, 0.6).translate(0, 3.5, 0)
    grips = merge(*(rounded_box(0.5, 6.0, 1.0, 0.2).translate(sx * 5.1, 3.5, z) for sx in (-1, 1) for z in (-3, -1, 1, 3)))
    hole = lathe([(0.0, 0.0), (3.2, 0.0), (2.8, 0.4), (0.8, 3.0), (0.0, 3.0)], 24).rotate("x", 90).translate(0, 3.8, -6.05)
    blade = rounded_box(6.0, 0.35, 4.6, 0.12).translate(0.6, 7.1, -2.0)
    screw = cylinder(0.7, 0.5, 16, 0.15).translate(0.6, 7.2, -2.6)
    return {"Body": merge(body, grips), "Hole": hole, "Blade": blade, "Screw": screw}


def paper_clip():
    """A paper clip lying flat: one wire bent into the familiar double loop."""
    pts = []

    def arc(cx, cz, r, a0, a1, steps=14):
        for i in range(steps + 1):
            a = math.radians(a0 + (a1 - a0) * i / steps)
            pts.append((cx + r * math.cos(a), 0.5, cz + r * math.sin(a)))

    k = 1.6
    pts.append((-1.0 * k, 0.5, 3.0 * k))
    arc(0.0, -6.0 * k, 1.0 * k, 180, 360)
    arc(-0.5 * k, 8.0 * k, 1.5 * k, 0, 180)
    arc(0.0, -8.0 * k, 2.0 * k, 180, 360)
    pts.append((2.0 * k, 0.5, 5.0 * k))
    return {"Wire": tube(pts, 0.5, 10)}


PROPS = {
    "TraceRaceCrayon": crayon,
    "TraceRaceClip": clip,
    "TraceRaceCrayonBox": crayon_box,
    "TraceRacePencil": pencil,
    "TraceRaceEraser": eraser,
    "TraceRaceSharpener": sharpener,
    "TraceRacePaperClip": paper_clip,
}
COLORS = {
    "Wax": (235, 55, 60),
    "Wrapper": (200, 40, 50),
    "Bands": (40, 30, 35),
    "Metal": (200, 205, 215),
    "Hinge": (170, 175, 185),
    "Rivets": (150, 155, 165),
    "Box": (250, 210, 40),
    "Band": (40, 150, 70),
    "Chevrons": (40, 150, 70),
    "CrayonA": (235, 55, 60),
    "CrayonB": (45, 120, 235),
    "CrayonC": (50, 185, 80),
    "CrayonD": (255, 145, 30),
    "CrayonE": (150, 80, 220),
    "CrayonF": (255, 105, 180),
    "Body": (250, 200, 40),
    "Wood": (235, 200, 150),
    "Lead": (60, 60, 70),
    "Ferrule": (200, 200, 210),
    "Eraser": (255, 140, 160),
    "Rubber": (255, 150, 170),
    "Sleeve": (60, 110, 220),
    "Stripe": (255, 255, 255),
    "Hole": (60, 60, 70),
    "Blade": (220, 225, 235),
    "Screw": (120, 125, 135),
    "Wire": (190, 195, 205),
}
