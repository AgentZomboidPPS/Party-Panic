"""Props for Eatsa Pizza: one slice of the giant pizza in four stages of being eaten (whole with its
crust, then bitten back further and further towards the tip), a pepperoni, the pan's rim, and the
pizzeria rooftop (brick oven, stacks of pizza boxes, the big sign, a team flag on a toothpick, an air
conditioner and a giant pizza cutter).

A slice is drawn at radius R0 (20 studs) with its tip at the origin and its crust towards -Z (the
front), spanning SLICE_DEG degrees; the game scales it to the pizza's size. Every stage keeps the
tip at the origin and is no wider than the whole slice, so the game places all stages the same way.
How far each stage reaches (a share of R0) is REACH below; Shared/Logic/EatsaPizza.luau uses the
same numbers to judge where a player stands.

    python3 tools/meshgen/generate_meshes.py --only EatsaPizzaSlice,EatsaPizzaSlice1,...
"""

from __future__ import annotations

import math

import numpy as np

from generate_meshes import Mesh, capsule, cylinder, extrude, icosphere, lathe, merge, rounded_box, torus, tube

R0 = 20.0  # slice radius as drawn
SLICE_DEG = 30.0  # twelve slices make the pizza
GAP_DEG = 0.35  # each side of a slice stops this short of the cut line
REACH = [1.0, 0.8, 0.6, 0.38]  # how far each stage reaches (share of R0); bites go a little deeper
DOUGH_TOP = 0.14
SAUCE_TOP = 0.19
CHEESE_TOP = 0.29  # the cheese's middle height (bubbles go a little over)
CRUST_W = 1.7  # the crust ridge's width
CRUST_H = 0.95  # and height


def _noise(x, z, seed: float = 0.0):
    return (
        np.sin(x * 1.7 + seed) * np.cos(z * 1.3 - seed * 0.7) * 0.5
        + np.sin(x * 3.1 - z * 2.3 + seed * 1.9) * 0.3
        + np.cos(x * 5.3 + z * 4.7 + seed) * 0.2
    )


def _boundary(stage: int):
    """The slice's outer edge for a stage: r = f(theta). Stage 0 is the round crust; later stages are
    bitten back, with two tooth-marked bites in the front."""
    if stage == 0:
        return lambda th: np.full_like(np.asarray(th, dtype=float), R0)
    base = REACH[stage] * R0
    bite = [2.3, 1.9, 1.45][stage - 1]
    rng = np.random.default_rng(stage * 7 + 3)
    half = math.radians(SLICE_DEG / 2)
    centers = [rng.uniform(-0.55, -0.15) * half * base, rng.uniform(0.15, 0.55) * half * base]

    def f(th):
        th = np.asarray(th, dtype=float)
        s = th * base  # arc length along the edge
        r = base + 0.06 * np.sin(th * 41 + stage)
        for c in centers:
            d = np.sqrt(np.maximum(0.0, bite * bite - (s - c) ** 2))
            teeth = np.where(d > 0, 0.07 * np.sin((s - c) * 11.0), 0.0)
            r = np.minimum(r, base + bite * 0.3 - d * 1.0 + teeth)
        return r

    return f


def polar_slab(f, th0: float, th1: float, y0: float, top, n_th: int, n_r: int) -> Mesh:
    """A closed slab over the region 0 <= r <= f(theta), th0 <= theta <= th1 (theta from -Z towards
    +X): flat bottom at y0, top at top(x, z). Seen from above the tip is at the origin."""
    ths = np.linspace(th0, th1, n_th + 1)
    radii = f(ths)
    verts = []

    def point(i, j):
        r = radii[i] * j / n_r
        return (math.sin(ths[i]) * r, -math.cos(ths[i]) * r)

    # Top: centre vertex 0, then rings.
    grid_top = {}
    grid_bottom = {}
    cx, cz = 0.0, 0.0
    verts.append((cx, float(top(np.array(cx), np.array(cz))), cz))
    top_center = 0
    verts.append((cx, y0, cz))
    bottom_center = 1
    for i in range(n_th + 1):
        for j in range(1, n_r + 1):
            x, z = point(i, j)
            grid_top[(i, j)] = len(verts)
            verts.append((x, float(top(np.array(x), np.array(z))), z))
            grid_bottom[(i, j)] = len(verts)
            verts.append((x, y0, z))
    faces = []
    for grid, center in ((grid_top, top_center), (grid_bottom, bottom_center)):
        for i in range(n_th):
            faces.append((center, grid[(i, 1)], grid[(i + 1, 1)]))
            for j in range(1, n_r):
                a, b = grid[(i, j)], grid[(i + 1, j)]
                c, d = grid[(i, j + 1)], grid[(i + 1, j + 1)]
                faces += [(a, c, b), (b, c, d)]
    # Outer wall.
    for i in range(n_th):
        a, b = grid_top[(i, n_r)], grid_top[(i + 1, n_r)]
        c, d = grid_bottom[(i, n_r)], grid_bottom[(i + 1, n_r)]
        faces += [(a, b, c), (b, d, c)]
    # The two cut sides (from the tip out).
    for i in (0, n_th):
        chain_top = [top_center] + [grid_top[(i, j)] for j in range(1, n_r + 1)]
        chain_bottom = [bottom_center] + [grid_bottom[(i, j)] for j in range(1, n_r + 1)]
        for k in range(n_r):
            a, b = chain_top[k], chain_top[k + 1]
            c, d = chain_bottom[k], chain_bottom[k + 1]
            faces += [(a, b, c), (b, d, c)]
    return Mesh(verts, faces)


def arc_sweep(profile: list[tuple[float, float]], th0: float, th1: float, n: int, wobble=None) -> Mesh:
    """Sweeps a closed 2D profile (radius, y) along the arc th0..th1 around the Y axis, with flat
    caps at both ends (a crust ridge)."""
    m = len(profile)
    verts = []
    for i in range(n + 1):
        th = th0 + (th1 - th0) * i / n
        for (r, y) in profile:
            w = wobble(th, r, y) if wobble else (0.0, 0.0)
            rr, yy = r + w[0], y + w[1]
            verts.append((math.sin(th) * rr, yy, -math.cos(th) * rr))
    faces = []
    for i in range(n):
        for k in range(m):
            a = i * m + k
            b = i * m + (k + 1) % m
            c, d = a + m, b + m
            faces += [(a, b, c), (b, d, c)]
    for ring, flip in ((0, False), (n, True)):
        center = len(verts)
        pts = np.array(verts[ring * m : ring * m + m])
        verts.append(tuple(pts.mean(axis=0)))
        for k in range(m):
            a, b = ring * m + k, ring * m + (k + 1) % m
            faces.append((center, b, a) if flip else (center, a, b))
    return Mesh(verts, faces)


def cheese_height(x, z, f, th_half):
    """The cheese's top: a gentle melt with bubbles, sloping down to its edges."""
    x = np.asarray(x, dtype=float)
    z = np.asarray(z, dtype=float)
    r = np.sqrt(x * x + z * z)
    th = np.arctan2(x, -z)
    edge = np.clip((f(th) - r) / 0.7, 0, 1)
    side = np.clip((th_half - np.abs(th)) * np.maximum(r, 0.5) / 0.25, 0, 1)
    bubble = np.maximum(0, _noise(x * 0.9, z * 0.9, 2.0)) * 0.07
    return SAUCE_TOP - 0.02 + (CHEESE_TOP - SAUCE_TOP + 0.02 + bubble) * np.sqrt(edge) * (0.55 + 0.45 * side)


def slice_stage(stage: int):
    half = math.radians(SLICE_DEG / 2 - GAP_DEG)
    f = _boundary(stage)
    crust_inner = R0 - CRUST_W
    if stage == 0:
        sauce_f = lambda th: np.full_like(np.asarray(th, float), crust_inner + 0.25)  # noqa: E731
        cheese_f = lambda th: np.full_like(np.asarray(th, float), crust_inner + 0.1)  # noqa: E731
    else:
        sauce_f = lambda th: f(th) - 0.1  # noqa: E731
        cheese_f = lambda th: f(th) - 0.22  # noqa: E731
    n_th = 40 if stage else 24
    dough = polar_slab(f, -half, half, 0.0, lambda x, z: DOUGH_TOP, n_th, 3)
    sauce = polar_slab(sauce_f, -half, half, DOUGH_TOP - 0.02, lambda x, z: SAUCE_TOP, n_th, 3)
    cheese = polar_slab(
        cheese_f, -half, half, SAUCE_TOP - 0.03, lambda x, z: cheese_height(x, z, cheese_f, half), n_th, 26
    )
    pieces = {"Dough": dough, "Sauce": sauce, "Cheese": cheese}

    if stage == 0:
        # The crust: a puffy rounded ridge round the outside, a little lumpy.
        prof = []
        for k in range(14):
            a = math.pi * k / 13
            prof.append((R0 - CRUST_W / 2 - math.cos(a) * CRUST_W / 2, 0.05 + math.sin(a) * CRUST_H))
        prof.append((R0 - CRUST_W / 2, 0.05))

        def lump(th, r, y):
            k = (y - 0.05) / CRUST_H
            return (0.0, k * 0.08 * math.sin(th * 60 + r) + k * 0.05 * math.cos(th * 23))

        pieces["Crust"] = arc_sweep(prof, -half, half, 40, lump)

    # Toppings (the same spots on every stage, kept only where the stage still reaches).
    rng = np.random.default_rng(42)
    top_at = lambda x, z: float(cheese_height(np.array(x), np.array(z), cheese_f, half))  # noqa: E731

    def spots(count, min_r, max_r, margin, seed):
        out = []
        local = np.random.default_rng(seed)
        tries = 0
        while len(out) < count and tries < 400:
            tries += 1
            r = local.uniform(min_r, max_r)
            th = local.uniform(-half * 0.8, half * 0.8)
            if abs(th) * r > half * r - margin:
                continue
            x, z = math.sin(th) * r, -math.cos(th) * r
            if any((x - a) ** 2 + (z - b) ** 2 < (margin * 2.2) ** 2 for a, b, _ in out):
                continue
            out.append((x, z, th))
        return out

    def keep(x, z, size):
        r = math.hypot(x, z)
        th = math.atan2(x, -z)
        return r + size < float(cheese_f(np.array(th))) - 0.3

    olives, basil, peppers, toasty = [], [], [], []
    for x, z, _ in spots(8, 3.0, R0 - 3.0, 0.55, 11):
        if keep(x, z, 0.5):
            o = torus(0.3, 0.12, 16, 8).translate(x, top_at(x, z) + 0.05, z)
            olives.append(o)
    for index, (x, z, _) in enumerate(spots(6, 3.5, R0 - 3.0, 0.7, 23)):
        if keep(x, z, 0.7):
            leaf = icosphere(1.0, 2).scale(0.62, 0.05, 0.36).rotate("y", float(rng.uniform(0, 180)))
            leaf.translate(x, top_at(x, z) + 0.04, z)
            basil.append(leaf)
    for x, z, _ in spots(5, 3.0, R0 - 3.2, 0.7, 37):
        if keep(x, z, 0.75):
            a0 = rng.uniform(0, 2 * math.pi)
            pts = [
                (x + math.cos(a0 + t) * 0.55, top_at(x, z) + 0.06, z + math.sin(a0 + t) * 0.55)
                for t in np.linspace(0, 3.6, 9)
            ]
            peppers.append(tube(pts, 0.1, 6))
    for x, z, _ in spots(9, 1.5, R0 - 2.5, 0.4, 51):
        if keep(x, z, 0.5):
            s = rng.uniform(0.3, 0.6)
            blob = icosphere(1.0, 1).scale(s, 0.035, s * rng.uniform(0.6, 1.0)).rotate("y", float(rng.uniform(0, 180)))
            blob.translate(x, top_at(x, z) + 0.005, z)
            toasty.append(blob)
    if olives:
        pieces["Olives"] = merge(*olives)
    if basil:
        pieces["Basil"] = merge(*basil)
    if peppers:
        pieces["Peppers"] = merge(*peppers)
    if toasty:
        pieces["Toasty"] = merge(*toasty)
    return pieces


def pepperoni():
    meat = lathe(
        [(0.0, 0.0), (0.95, 0.0), (1.1, 0.06), (1.12, 0.13), (1.02, 0.17), (0.6, 0.13), (0.0, 0.11)], 28
    )
    rng = np.random.default_rng(5)
    flecks = []
    for _ in range(9):
        r = math.sqrt(rng.uniform(0, 1)) * 0.75
        a = rng.uniform(0, 2 * math.pi)
        s = rng.uniform(0.06, 0.12)
        y = 0.11 + 0.02 * (r / 0.6) ** 2 if r < 0.6 else 0.13
        flecks.append(icosphere(1.0, 1).scale(s, 0.025, s).translate(math.cos(a) * r, y, math.sin(a) * r))
    return {"Meat": meat, "Fat": merge(*flecks)}


def pan_rim():
    """The pan's rolled lip (the floor is a part in the game); its inside edge is 20.6 from the middle."""
    prof = [(20.55, 0.0), (21.75, 0.0), (21.95, 0.12), (21.98, 0.3), (21.85, 0.4), (21.6, 0.38), (21.45, 0.24), (20.55, 0.06)]
    return {"Rim": lathe(prof, 120)}


def oven():
    """A domed brick pizza oven on a stone base, its mouth glowing (facing -Z)."""
    base = rounded_box(12.0, 4.0, 11.0, 0.4).translate(0, 2.0, 0)
    top_slab = rounded_box(12.6, 0.6, 11.6, 0.2).translate(0, 4.3, 0)
    dome_prof = [(5.0, 4.6)]
    for k in range(1, 13):
        a = math.pi / 2 * k / 12
        dome_prof.append((math.cos(a) * 5.0, 4.6 + math.sin(a) * 4.6))
    dome = lathe(dome_prof, 36, cap_bottom=True)
    # Brick courses: thin bands round the dome.
    bands = []
    for k in (1, 2, 3, 4):
        a = math.pi / 2 * k / 5
        bands.append(torus(math.cos(a) * 5.0 + 0.02, 0.09, 40, 6).translate(0, 4.6 + math.sin(a) * 4.6, 0))
    arch = [(-2.1, 0.0), (2.1, 0.0)]
    for k in range(0, 13):
        a = math.pi * k / 12
        arch.append((2.1 * math.cos(a), 2.0 + 2.1 * math.sin(a)))
    arch_pts = [arch[0], arch[1]] + arch[2:]
    mouth = extrude(arch_pts, 0.5).translate(0, 4.6, -4.65)
    rim_pts = [(-2.8, 0.0), (2.8, 0.0)]
    for k in range(0, 13):
        a = math.pi * k / 12
        rim_pts.append((2.8 * math.cos(a), 2.0 + 2.8 * math.sin(a)))
    rim = extrude(rim_pts, 0.5).translate(0, 4.6, -4.55)
    fire = []
    for k, (x, h) in enumerate(((-1.0, 1.4), (0.0, 2.1), (1.0, 1.3), (-0.4, 1.0), (0.5, 1.2))):
        fire.append(icosphere(1.0, 2).scale(0.45, h / 2, 0.3).translate(x, 4.6 + h / 2, -4.95 - 0.02 * k))
    logs = [capsule(3.6, 0.28, 10).rotate("z", 90).translate(0, 4.85, -5.0)]
    chimney = merge(
        cylinder(0.9, 4.5, 20).translate(0, 8.4, 2.0),
        cylinder(1.15, 0.5, 20).translate(0, 12.8, 2.0),
    )
    return {
        "Base": merge(base, top_slab),
        "Dome": dome,
        "Bricks": merge(*bands),
        "Rim": rim,
        "Mouth": mouth,
        "Fire": merge(*fire),
        "Logs": merge(*logs),
        "Chimney": chimney,
    }


def boxes():
    """A leaning stack of five pizza boxes, a printed slice on the top one."""
    rng = np.random.default_rng(9)
    parts, y = [], 0.0
    for k in range(5):
        box = rounded_box(6.0, 0.62, 6.0, 0.12, 4)
        box.rotate("y", float(rng.uniform(-9, 9))).translate(float(rng.uniform(-0.25, 0.25)), y + 0.31, float(rng.uniform(-0.25, 0.25)))
        parts.append(box)
        y += 0.64
    angle = float(rng.uniform(-9, 9))
    tri = [(0.0, 1.5), (-1.25, -1.2), (1.25, -1.2)]
    slice_mark = extrude(tri, 0.06).rotate("x", 90).rotate("y", angle).translate(0, y + 0.0, 0)
    ring = torus(2.2, 0.08, 40, 6).rotate("y", angle).translate(0, y + 0.01, 0)
    dots = [cylinder(0.25, 0.06, 12).translate(dx, y - 0.02, dz) for dx, dz in ((-0.3, 0.2), (0.35, -0.3), (0.0, -0.75))]
    return {"Box": merge(*parts), "Print": merge(slice_mark, ring), "Dots": merge(*dots)}


def sign():
    """The rooftop sign: a board on two steel legs with a neon border (text is added in the game)."""
    legs = merge(
        cylinder(0.45, 9.0, 12).translate(-10.0, 0, 0.6),
        cylinder(0.45, 9.0, 12).translate(10.0, 0, 0.6),
        tube([(-10.0, 3.0, 0.6), (10.0, 3.0, 0.6)], 0.22, 8),
    )
    board = rounded_box(30.0, 9.0, 0.8, 0.35).translate(0, 12.5, 0)
    w, h = 14.4, 4.0
    border = tube([(-w, 12.5 - h, -0.5), (w, 12.5 - h, -0.5), (w, 12.5 + h, -0.5), (-w, 12.5 + h, -0.5), (-w, 12.5 - h, -0.5)], 0.18, 8)
    bulbs = [icosphere(0.32, 1).translate(x, 17.25, -0.2) for x in np.linspace(-14, 14, 15)]
    return {"Legs": legs, "Board": board, "Neon": border, "Bulbs": merge(*bulbs)}


def flag():
    """A toothpick with a little wavy flag (recolored per team)."""
    pick = merge(
        cylinder(0.12, 7.6, 10),
        icosphere(0.18, 1).translate(0, 7.65, 0),
    )
    pts = []
    for k in range(13):
        t = k / 12
        pts.append((0.1 + t * 3.4, 0.15 * math.sin(t * 6.0)))
    # A thin wavy slab, built directly (closed: front, back, top, bottom and both ends).
    verts, faces = [], []
    for k, (x, wz) in enumerate(pts):
        for y in (5.0, 7.3):
            verts.append((x, y, wz - 0.05))
            verts.append((x, y, wz + 0.05))
    n = len(pts)
    for k in range(n - 1):
        a = k * 4
        b = a + 4
        # (bottom-front, bottom-back, top-front, top-back) per column
        faces += [(a + 0, b + 0, a + 2), (b + 0, b + 2, a + 2)]  # front (-Z)
        faces += [(a + 1, a + 3, b + 1), (b + 1, a + 3, b + 3)]  # back
        faces += [(a + 2, b + 2, a + 3), (b + 2, b + 3, a + 3)]  # top
        faces += [(a + 0, a + 1, b + 0), (b + 0, a + 1, b + 1)]  # bottom
    last = (n - 1) * 4
    faces += [(0, 2, 1), (1, 2, 3), (last + 0, last + 1, last + 2), (last + 1, last + 3, last + 2)]
    cloth = Mesh(verts, faces)
    cloth.smooth = False
    return {"Pick": pick, "Flag": cloth}


def vent():
    """A rooftop air conditioner with a fan grille on top."""
    body = rounded_box(6.0, 3.4, 5.0, 0.3).translate(0, 1.7 + 0.4, 0)
    feet = merge(*[rounded_box(0.6, 0.4, 4.6, 0.1, 3).translate(x, 0.2, 0) for x in (-2.4, 2.4)])
    ring = torus(1.7, 0.15, 32, 8).translate(0, 3.8, -0.1)
    hub = cylinder(0.35, 0.25, 16).translate(0, 3.7, -0.1)
    blades = []
    for k in range(4):
        blade = rounded_box(1.4, 0.06, 0.5, 0.03, 3).translate(0.85, 3.85, 0).rotate("y", 90 * k + 20)
        blades.append(blade.translate(0, 0, -0.1))
    grille = [tube([(-1.65, 3.92, z - 0.1), (1.65, 3.92, z - 0.1)], 0.04, 5) for z in np.linspace(-1.4, 1.4, 8)]
    slats = [rounded_box(5.0, 0.12, 0.08, 0.03, 2).translate(0, y, -2.52) for y in np.linspace(1.0, 3.2, 7)]
    return {
        "Body": body,
        "Feet": feet,
        "Fan": merge(ring, hub, *blades),
        "Grille": merge(*grille),
        "Slats": merge(*slats),
    }


def cutter():
    """A giant pizza cutter standing on its wheel (the handle up and back)."""
    wheel_prof = [(0.0, -0.08), (3.4, -0.08), (3.6, 0.0), (3.4, 0.08), (0.0, 0.08)]
    wheel = lathe(wheel_prof, 48).rotate("z", 90).translate(0, 3.6, 0)
    hub = cylinder(0.75, 0.6, 20).translate(0, -0.3, 0).rotate("z", 90).translate(0, 3.6, 0)
    fork = merge(
        tube([(0.35, 3.6, 0.0), (0.35, 4.6, 1.6), (0.0, 5.6, 2.6)], 0.22, 8),
        tube([(-0.35, 3.6, 0.0), (-0.35, 4.6, 1.6), (0.0, 5.6, 2.6)], 0.22, 8),
    )
    handle = capsule(5.0, 0.55, 18).translate(0, 2.5, 0).rotate("x", 50).translate(0, 5.6, 2.6)
    return {"Wheel": wheel, "Hub": hub, "Fork": fork, "Handle": handle}


PROPS = {
    "EatsaPizzaSlice": lambda: slice_stage(0),
    "EatsaPizzaSlice1": lambda: slice_stage(1),
    "EatsaPizzaSlice2": lambda: slice_stage(2),
    "EatsaPizzaSlice3": lambda: slice_stage(3),
    "EatsaPizzaPepperoni": pepperoni,
    "EatsaPizzaPan": pan_rim,
    "EatsaPizzaOven": oven,
    "EatsaPizzaBoxes": boxes,
    "EatsaPizzaSign": sign,
    "EatsaPizzaFlag": flag,
    "EatsaPizzaVent": vent,
    "EatsaPizzaCutter": cutter,
}
COLORS = {
    "Dough": (226, 178, 110),
    "Sauce": (196, 46, 30),
    "Cheese": (255, 214, 102),
    "Crust": (214, 150, 76),
    "Olives": (40, 36, 40),
    "Basil": (60, 150, 60),
    "Peppers": (90, 180, 70),
    "Toasty": (226, 150, 70),
    "Meat": (186, 48, 40),
    "Fat": (238, 150, 120),
    "Rim": (190, 194, 204),
    "Base": (150, 146, 140),
    "Dome": (196, 98, 64),
    "Bricks": (150, 70, 46),
    "Mouth": (34, 22, 20),
    "Fire": (255, 150, 40),
    "Logs": (110, 70, 40),
    "Chimney": (160, 80, 56),
    "Box": (214, 176, 120),
    "Print": (210, 40, 40),
    "Dots": (210, 40, 40),
    "Legs": (120, 126, 136),
    "Board": (200, 40, 40),
    "Neon": (255, 220, 90),
    "Bulbs": (255, 236, 170),
    "Pick": (220, 190, 140),
    "Flag": (255, 80, 90),
    "Body": (210, 214, 220),
    "Feet": (90, 94, 100),
    "Fan": (60, 64, 70),
    "Grille": (140, 144, 150),
    "Slats": (170, 174, 180),
    "Wheel": (200, 206, 216),
    "Hub": (90, 94, 100),
    "Fork": (160, 166, 176),
    "Handle": (210, 50, 50),
}
