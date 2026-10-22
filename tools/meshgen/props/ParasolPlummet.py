"""Meshes for Parasol Plummet (see tools/meshgen/props/README.md). Units are studs, +Y up, base on y = 0,
-Z is the front. Generate with:

    python3 tools/meshgen/generate_meshes.py --only ParasolPlummetUmbrella,ParasolPlummetUmbrellaShut,ParasolPlummetCoin,ParasolPlummetBag,ParasolPlummetHammer,ParasolPlummetCloud,ParasolPlummetThrower,ParasolPlummetSun,ParasolPlummetBalloon

The umbrellas' sizes are the catch shapes in src/shared/Logic/ParasolPlummetSim.luau (canopy rim 3.9 up,
top 5.4, 3.8 across either way; furled from 1.2 to 5.2; 5.6 tall from the hook to the tip): change them
together. Pieces are coloured by name in src/server/World/Props/ParasolPlummet.luau."""

import math

import numpy as np

from generate_meshes import (
    Mesh,
    cylinder,
    extrude,
    lathe,
    merge,
    rounded_box,
    sd_capsule,
    sd_ellipsoid,
    sdf_mesh,
    smin,
    sphere,
    star,
    taper,
    torus,
    weld,
)

RIBS = 8
CANOPY_R = 3.8
CANOPY_RIM = 3.9
CANOPY_TOP = 5.4
TOP = 5.6


def grid_shell(point, nu: int, nv: int, thickness: float) -> Mesh:
    """A closed slab over a (u, v) patch: point(u, v) -> (x, y, z) on the outer side; the inner side sits
    `thickness` lower (along -Y), and the four edges are joined. face_outward turns it the right way."""
    verts = []
    for side in (0, 1):
        for i in range(nu + 1):
            for j in range(nv + 1):
                x, y, z = point(i / nu, j / nv)
                verts.append((x, y - side * thickness, z))
    def idx(side, i, j):
        return side * (nu + 1) * (nv + 1) + i * (nv + 1) + j
    faces = []
    for i in range(nu):
        for j in range(nv):
            a, b, c, d = idx(0, i, j), idx(0, i + 1, j), idx(0, i, j + 1), idx(0, i + 1, j + 1)
            faces += [(a, c, b), (b, c, d)]
            a, b, c, d = idx(1, i, j), idx(1, i + 1, j), idx(1, i, j + 1), idx(1, i + 1, j + 1)
            faces += [(a, b, c), (b, d, c)]
    # Edges: v = 0 and v = nv (along u), u = 0 and u = nu (along v).
    for i in range(nu):
        for j in (0, nv):
            a, b = idx(0, i, j), idx(0, i + 1, j)
            c, d = idx(1, i, j), idx(1, i + 1, j)
            faces += [(a, b, c), (b, d, c)]
    for j in range(nv):
        for i in (0, nu):
            a, b = idx(0, i, j), idx(0, i, j + 1)
            c, d = idx(1, i, j), idx(1, i, j + 1)
            faces += [(a, b, c), (b, d, c)]
    return Mesh(verts, faces)


def canopy_point(a0: float, a1: float):
    """The open canopy between two ribs: a dome that dips into soft scallops between the ribs."""
    def point(u: float, v: float):
        s = 0.06 + 0.94 * v  # (a hole round the shaft at the top, covered by the tip's cap)
        angle = a0 + (a1 - a0) * u
        between = math.sin(u * math.pi)  # 0 on a rib, 1 halfway between
        r = CANOPY_R * math.sin(s * math.pi / 2) * (1 - 0.06 * between * s * s)
        y = CANOPY_TOP - (CANOPY_TOP - CANOPY_RIM) * (1 - math.cos(s * math.pi / 2)) ** 0.85
        y += 0.32 * between * s ** 3  # the fabric sags up between the rib tips
        return (math.cos(angle) * r, y, math.sin(angle) * r)
    return point


def hook_handle() -> Mesh:
    """The J-shaped wooden handle at the bottom of the shaft."""
    points = [(0, 1.15, 0), (0, 0.6, 0)]
    for k in range(1, 8):
        a = math.pi * k / 7
        points.append((0.36 - math.cos(a) * 0.36, 0.6 - math.sin(a) * 0.42, 0))
    points.append((0.72, 0.75, 0))
    mesh = taper(points, 0.17, 0.15, 10)
    return mesh.translate(0, 0.0, 0)


def shaft_and_tip():
    shaft = cylinder(0.085, TOP - 1.0 - 0.15, 12).translate(0, 1.0, 0)
    tip = lathe([(0.0, 5.15), (0.44, 5.3), (0.38, 5.44), (0.1, 5.5), (0.02, TOP), (0.0, TOP)], 16)
    return shaft, tip


def umbrella():
    panels_a, panels_b = [], []
    for k in range(RIBS):
        a0 = 2 * math.pi * k / RIBS
        a1 = 2 * math.pi * (k + 1) / RIBS
        panel = grid_shell(canopy_point(a0, a1), 6, 10, 0.1)
        (panels_a if k % 2 == 0 else panels_b).append(panel)
    shaft, tip = shaft_and_tip()
    # Gold beads on the rib tips and spokes under the canopy.
    beads, spokes = [], []
    for k in range(RIBS):
        a = 2 * math.pi * k / RIBS
        x, z = math.cos(a) * (CANOPY_R + 0.05), math.sin(a) * (CANOPY_R + 0.05)
        beads.append(sphere(0.13, 6, 10).translate(x, CANOPY_RIM - 0.02, z))
        spokes.append(taper([(0, 3.7, 0), (math.cos(a) * 2.2, CANOPY_RIM + 0.75, math.sin(a) * 2.2)], 0.05, 0.04, 6))
    handle = hook_handle()
    lift = -(0.6 - 0.42 - 0.17)  # the hook's lowest point onto y = 0
    pieces = {
        "Canopy": merge(*panels_a),
        "Stripe": merge(*panels_b),
        "Shaft": merge(shaft, *spokes),
        "Handle": handle,
        "Tip": merge(tip, *beads),
    }
    for mesh in pieces.values():
        mesh.translate(0, lift, 0)
    return pieces


def umbrella_shut():
    # Furled fabric: thickest in the middle, folds twisting round the shaft.
    profile = [(0.09, 1.2), (0.3, 1.55), (0.47, 2.3), (0.52, 3.1), (0.46, 3.9), (0.32, 4.6), (0.16, 5.12), (0.08, 5.2)]
    furl = lathe(profile, 32, cap_bottom=True, cap_top=True)
    angle = np.arctan2(furl.v[:, 2], furl.v[:, 0])
    radial = np.linalg.norm(furl.v[:, [0, 2]], axis=1)
    folds = 1 + 0.12 * np.cos(angle * RIBS + furl.v[:, 1] * 1.6)
    scale = np.where(radial > 1e-6, folds, 1.0)
    furl.v[:, 0] *= scale
    furl.v[:, 2] *= scale
    strap = torus(0.5, 0.07, 24, 8).translate(0, 3.0, 0)
    button = sphere(0.09, 6, 8).translate(0, 3.0, -0.57)
    shaft, tip = shaft_and_tip()
    handle = hook_handle()
    lift = -(0.6 - 0.42 - 0.17)
    pieces = {
        "Canopy": furl,
        "Stripe": merge(strap, button),
        "Shaft": shaft,
        "Handle": handle,
        "Tip": tip,
    }
    for mesh in pieces.values():
        mesh.translate(0, lift, 0)
    return pieces


def coin():
    # A disc facing -Z with a raised rim and a star on both faces.
    profile = [(0.0, -0.11), (0.82, -0.11), (0.88, -0.17), (1.04, -0.17), (1.1, -0.09), (1.1, 0.09), (1.04, 0.17), (0.88, 0.17), (0.82, 0.11), (0.0, 0.11)]
    disc = lathe(profile, 40).rotate("x", 90).translate(0, 1.1, 0)
    emblem = extrude(star(0.6, 0.26), 0.3).translate(0, 1.1, 0)
    return {"Coin": disc, "Emblem": emblem}


def bag():
    profile = [(0.0, 0.0), (0.7, 0.03), (1.22, 0.32), (1.45, 0.9), (1.42, 1.45), (1.15, 1.95), (0.7, 2.3), (0.42, 2.42), (0.4, 2.5), (0.62, 2.68), (0.82, 2.92), (0.62, 3.0), (0.3, 2.86), (0.0, 2.8)]
    sack = lathe(profile, 36)
    angle = np.arctan2(sack.v[:, 2], sack.v[:, 0])
    wobble = 1 + 0.045 * np.sin(angle * 5 + 0.7) + 0.05 * np.sin(angle * 9) * np.clip((sack.v[:, 1] - 2.45) * 3, 0, 1)
    sack.v[:, 0] *= wobble
    sack.v[:, 2] *= wobble
    tie = torus(0.44, 0.1, 24, 8).translate(0, 2.44, 0)
    knot = sphere(0.16, 6, 10).translate(0, 2.44, -0.48)
    # A big coin badge sewn on the front.
    badge = lathe([(0.0, -0.06), (0.52, -0.06), (0.58, 0.0), (0.52, 0.06), (0.0, 0.06)], 28).rotate("x", 90)
    badge.translate(0, 1.25, -1.47)
    mark = extrude(star(0.32, 0.14), 0.16).translate(0, 1.25, -1.5)
    return {"Sack": sack, "Tie": merge(tie, knot), "Emblem": merge(badge, mark)}


def hammer():
    handle = cylinder(0.2, 2.5, 14, 0.06)
    grip = cylinder(0.25, 0.7, 14, 0.06).translate(0, 0.08, 0)
    head = cylinder(0.58, 2.4, 24, 0.14).rotate("z", 90).translate(1.2, 3.0, 0)
    bands = merge(
        cylinder(0.63, 0.16, 24).rotate("z", 90).translate(0.95, 3.0, 0),
        cylinder(0.63, 0.16, 24).rotate("z", 90).translate(-0.79, 3.0, 0),
    )
    return {"Handle": merge(handle, grip), "Head": head, "Band": bands}


def cloud():
    puffs = [
        ((0.0, 2.6, 0.0), (2.7, 2.5, 2.5)),
        ((-2.9, 2.0, 0.2), (2.1, 2.0, 2.0)),
        ((2.9, 2.0, -0.2), (2.1, 2.0, 2.0)),
        ((-5.1, 1.6, 0.0), (1.6, 1.5, 1.6)),
        ((5.1, 1.6, 0.1), (1.6, 1.5, 1.6)),
        ((-1.4, 3.7, 0.3), (1.6, 1.5, 1.5)),
        ((1.5, 3.5, -0.3), (1.7, 1.5, 1.6)),
        ((0.8, 2.0, -1.8), (1.7, 1.6, 1.5)),
        ((-1.2, 2.0, 1.7), (1.8, 1.6, 1.5)),
        ((3.4, 1.8, -1.3), (1.4, 1.3, 1.3)),
        ((-3.6, 1.8, 1.2), (1.4, 1.3, 1.3)),
        ((-3.3, 1.8, -1.3), (1.3, 1.2, 1.2)),
    ]

    def top(p):
        d = None
        for center, radii in puffs:
            e = sd_ellipsoid(p, center, radii)
            d = e if d is None else smin(d, e, 0.3)
        return np.maximum(d, 1.25 - p[:, 1])  # a flat underside, where the shade layer sits

    def bottom(p):
        d = sd_ellipsoid(p, (0.0, 1.3, 0.0), (6.6, 1.1, 3.3))
        d = smin(d, sd_ellipsoid(p, (-3.8, 1.3, 0.2), (3.0, 1.0, 2.4)), 0.8)
        d = smin(d, sd_ellipsoid(p, (3.9, 1.3, -0.2), (3.0, 1.0, 2.4)), 0.8)
        return d

    fluff = sdf_mesh(top, (-7.5, 0.6, -4.2), (7.5, 5.6, 4.2), 0.25)
    shade = sdf_mesh(bottom, (-8.0, 0.0, -4.5), (8.0, 2.6, 4.5), 0.3)
    low = min(fluff.v[:, 1].min(), shade.v[:, 1].min())
    fluff.translate(0, -low, 0)
    shade.translate(0, -low, 0)
    return {"Cloud": fluff, "Shade": shade}


def thrower():
    """A chubby little sky critter in a cap (it's the one tossing the coins), facing -Z, throwing arm up."""

    def body(p):
        d = sd_ellipsoid(p, (0.0, 2.3, 0.0), (1.55, 1.85, 1.4))
        d = smin(d, sd_capsule(p, (-1.3, 2.4, 0.0), (-1.95, 1.4, -0.35), 0.34), 0.25)  # resting arm
        d = smin(d, sd_capsule(p, (1.3, 2.7, 0.0), (1.95, 4.1, 0.25), 0.34), 0.25)  # throwing arm
        d = smin(d, sd_ellipsoid(p, (-1.98, 1.32, -0.38), (0.42, 0.42, 0.42)), 0.12)  # hands
        d = smin(d, sd_ellipsoid(p, (1.98, 4.2, 0.26), (0.42, 0.42, 0.42)), 0.12)
        d = smin(d, sd_ellipsoid(p, (-1.45, 2.95, 0.05), (0.32, 0.4, 0.2)), 0.2)  # little ears under the cap
        d = smin(d, sd_ellipsoid(p, (1.45, 2.95, 0.05), (0.32, 0.4, 0.2)), 0.2)
        return d

    def boots(p):
        left = sd_ellipsoid(p, (-0.68, 0.36, -0.28), (0.55, 0.38, 0.8))
        right = sd_ellipsoid(p, (0.68, 0.36, -0.28), (0.55, 0.38, 0.8))
        return np.maximum(np.minimum(left, right), -p[:, 1])

    skin = sdf_mesh(body, (-2.6, 0.2, -2.0), (2.6, 4.9, 1.8), 0.13)
    feet = sdf_mesh(boots, (-1.5, -0.2, -1.4), (1.5, 0.9, 0.8), 0.1)
    belly = sphere(1.0, 12, 20).scale(1.05, 1.15, 0.5).translate(0, 1.95, -0.98)
    cap = lathe([(1.5, 3.55), (1.48, 3.9), (1.3, 4.45), (0.9, 4.85), (0.35, 5.05), (0.0, 5.08)], 32, cap_bottom=True)
    brim = sphere(1.0, 8, 20).scale(1.05, 0.14, 0.9).translate(0, 3.62, -1.2)
    pom = sphere(0.24, 8, 12).translate(0, 5.12, 0)
    eyes = merge(
        sphere(1.0, 10, 14).scale(0.36, 0.46, 0.22).translate(-0.48, 3.08, -1.24),
        sphere(1.0, 10, 14).scale(0.36, 0.46, 0.22).translate(0.48, 3.08, -1.24),
    )
    pupils = merge(
        sphere(0.17, 8, 10).translate(-0.45, 3.02, -1.43),
        sphere(0.17, 8, 10).translate(0.45, 3.02, -1.43),
    )
    smile_pts = [(math.cos(a) * 0.42, 2.62 - math.sin(a) * 0.16 + 0.16, -1.33 - 0.04 * math.sin(a)) for a in np.linspace(math.pi * 1.1, math.pi * 1.9, 8)]
    smile = taper([(x, y, z) for x, y, z in smile_pts], 0.055, 0.055, 6)
    return {
        "Body": skin,
        "Belly": belly,
        "Cap": merge(cap, brim, pom),
        "Eyes": eyes,
        "Pupils": merge(pupils, smile),
        "Boots": feet,
    }


def sun():
    disc = cylinder(18.0, 1.2, 64, 0.4).rotate("x", 90).translate(0, 30, 0)
    rays = []
    for k in range(16):
        a = 2 * math.pi * k / 16
        long = 29.5 if k % 2 == 0 else 25.0
        tri = [(-2.3, 0.0), (2.3, 0.0), (0.0, long - 19.5)]
        ray = extrude(tri, 0.6)
        ray.translate(0, 19.5, 0).rotate("z", math.degrees(a)).translate(0, 30, 0.2)
        rays.append(ray)
    return {"Sun": disc, "Rays": merge(*rays)}


def lathe_sector(profile, a0: float, a1: float, steps: int) -> Mesh:
    """Part of a lathe between two angles (bottom-outside-top profile: faces point out, like lathe)."""
    verts, faces = [], []
    rows = len(profile)
    for radius, y in profile:
        for s in range(steps + 1):
            a = a0 + (a1 - a0) * s / steps
            verts.append((math.cos(a) * radius, y, math.sin(a) * radius))
    n = steps + 1
    for i in range(rows - 1):
        for s in range(steps):
            a = i * n + s
            b = a + 1
            c = a + n
            d = b + n
            faces += [(a, c, b), (b, c, d)]
    return Mesh(verts, faces)


def balloon():
    profile = []
    for k in range(25):
        t = k / 24
        # A teardrop: narrow throat at the bottom, round crown at the top.
        theta = -math.pi * 0.42 + t * math.pi * 0.92
        r = 7.0 * math.cos(theta)
        y = 14.6 + 7.0 * math.sin(theta)
        if t < 0.18:
            r = 1.6 + (r - 1.6) * (t / 0.18) ** 0.8
        profile.append((max(r, 0.0), y))
    profile[-1] = (0.0, 21.6)
    gores_a, gores_b = [], []
    for k in range(12):
        a0 = 2 * math.pi * k / 12
        a1 = 2 * math.pi * (k + 1) / 12
        (gores_a if k % 2 == 0 else gores_b).append(lathe_sector(profile, a0, a1, 4))
    envelope = weld(merge(*gores_a))
    stripe = weld(merge(*gores_b))
    skirt = lathe([(1.35, 8.0), (1.55, 8.65), (1.45, 8.65), (1.25, 8.05)], 20)
    basket = rounded_box(2.8, 2.0, 2.8, 0.25).translate(0, 1.0, 0)
    rim = torus(1.5, 0.16, 24, 8).translate(0, 2.0, 0)
    ropes = []
    for sx, sz in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        ropes.append(taper([(sx * 1.25, 1.9, sz * 1.25), (sx * 1.05, 8.1, sz * 1.05)], 0.06, 0.06, 6))
    return {"Envelope": envelope, "Stripe": merge(stripe, skirt), "Basket": merge(basket, rim), "Rope": merge(*ropes)}


PROPS = {
    "ParasolPlummetUmbrella": umbrella,
    "ParasolPlummetUmbrellaShut": umbrella_shut,
    "ParasolPlummetCoin": coin,
    "ParasolPlummetBag": bag,
    "ParasolPlummetHammer": hammer,
    "ParasolPlummetCloud": cloud,
    "ParasolPlummetThrower": thrower,
    "ParasolPlummetSun": sun,
    "ParasolPlummetBalloon": balloon,
}
COLORS = {
    "Canopy": (235, 70, 80),
    "Stripe": (255, 250, 245),
    "Shaft": (200, 204, 214),
    "Handle": (120, 72, 44),
    "Tip": (255, 200, 40),
    "Coin": (255, 200, 40),
    "Emblem": (255, 238, 140),
    "Sack": (196, 140, 84),
    "Tie": (120, 70, 40),
    "Head": (120, 126, 140),
    "Band": (255, 200, 40),
    "Cloud": (250, 252, 255),
    "Shade": (214, 228, 248),
    "Belly": (255, 238, 200),
    "Cap": (70, 110, 230),
    "Eyes": (255, 255, 255),
    "Pupils": (30, 30, 40),
    "Boots": (130, 80, 50),
    "Sun": (255, 236, 140),
    "Rays": (255, 205, 90),
    "Envelope": (255, 120, 90),
    "Basket": (150, 100, 60),
    "Rope": (90, 70, 50),
}
