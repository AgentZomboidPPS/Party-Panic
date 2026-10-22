"""Meshes for Log Jam (see tools/meshgen/props/README.md). Units are studs, +Y up, base on y = 0,
-Z is the front. Generate with: python3 tools/meshgen/generate_meshes.py --only LogJamStump,...

The station pieces fit together (src/server/MiniGames/LogJam.luau places them by these numbers):
- LogJamStump: the chopping block, its top ("Top") at y = 2.45, radius ~1.8.
- LogJamLog: one upright log, 2.2 tall, radius 0.88; it lands on the stump and is split there.
- LogJamHalf: half of that log after the axe, flat side on z = 0 facing +Z, round side to the front.
- LogJamAxe: the big axe lying level (its chop pose): the hinge collar ("Collar") centred on the
  origin with its axle along Z, the handle running along -X to the head, whose middle is 4.6 out and
  whose edge is 1.3 below the hinge.
- LogJamAxeFrame: the post that holds the axe's hinge: the axle ("Bolt") centred at (0, 5.2, 0).
- LogJamRack: the sloped log rack; its stop peg ("Peg") centred at (-0.3, 1.6, 0); the waiting log
  rests at (0.45, 2.45, 0) lying along Z; the pile goes up towards +X.
- Scenery: LogJamChips (sawdust and chips), LogJamPine, LogJamMill (the sawmill shed behind the
  stations), LogJamLumber (a stack of planks and logs).
"""

import math

import numpy as np

from generate_meshes import (
    Mesh,
    cylinder,
    extrude,
    icosphere,
    lathe,
    merge,
    organic_lathe,
    rounded_box,
    star,
    taper,
    torus,
    tube,
)

STUMP_TOP = 2.45
LOG_R = 0.88
LOG_H = 2.2


def flip_axes(mesh: Mesh, order) -> Mesh:
    """Reorders the axes (e.g. (0, 2, 1) swaps Y and Z); the generator turns faces back outward."""
    mesh.v = mesh.v[:, list(order)]
    return mesh


def along_z(mesh: Mesh) -> Mesh:
    """A Y-axis shape (lathe, cylinder) turned to lie along Z, centred on its old middle height."""
    return mesh.rotate("x", 90)


def ring_lines(radii, y, minor=0.035, segments=40):
    return merge(*[torus(r, minor, segments, 6).translate(0, y, 0) for r in radii])


def stump():
    bark = organic_lathe(
        [(0.0, 0.0), (2.55, 0.0), (2.35, 0.18), (2.05, 0.55), (1.92, 1.1), (1.9, 1.9), (1.86, 2.32), (1.7, 2.4), (0.0, 2.4)],
        36,
        0.05,
        7,
        seed=3,
    )
    top = cylinder(1.74, 0.12, 36, 0.04).translate(0, 2.33, 0)
    lines = ring_lines([0.45, 0.85, 1.22, 1.55], STUMP_TOP, 0.03)
    roots = []
    for i in range(5):
        a = i * 2 * math.pi / 5 + 0.4
        d = (math.cos(a), math.sin(a))
        roots.append(taper([(d[0] * 1.6, 0.9, d[1] * 1.6), (d[0] * 2.4, 0.35, d[1] * 2.4), (d[0] * 3.0, 0.05, d[1] * 3.0)], 0.42, 0.12, 8))
    # Old axe cuts on the top: thin dark slivers sunk into the rings.
    cuts = []
    for angle, off in ((20, 0.3), (-35, -0.5), (70, 0.9)):
        cut = rounded_box(1.3, 0.06, 0.07, 0.02, 2).rotate("y", angle).translate(off * 0.5, STUMP_TOP - 0.01, off)
        cuts.append(cut)
    return {"Bark": merge(bark, *roots), "Top": top, "Rings": lines, "Cuts": merge(*cuts)}


def log():
    bark = organic_lathe(
        [(0.0, 0.04), (0.76, 0.04), (0.86, 0.12), (LOG_R, 1.1), (0.86, LOG_H - 0.12), (0.76, LOG_H - 0.04), (0.0, LOG_H - 0.04)],
        28,
        0.04,
        6,
        seed=5,
    )
    ends = merge(cylinder(0.78, 0.06, 28).translate(0, 0.0, 0), cylinder(0.78, 0.06, 28).translate(0, LOG_H - 0.06, 0))
    rings = merge(ring_lines([0.3, 0.55], LOG_H, 0.025, 28), ring_lines([0.3, 0.55], 0.0, 0.025, 28))
    knot = taper([(0.8, 1.4, 0.2), (1.05, 1.52, 0.28)], 0.16, 0.12, 8)
    return {"Bark": merge(bark, knot), "Wood": ends, "Rings": rings}


def half_log():
    def half_prism(radius, length, gap):
        pts = [(math.cos(math.pi * i / 16) * radius, -math.sin(math.pi * i / 16) * radius - gap) for i in range(17)]
        prism = extrude(pts, length)  # along Z, centred
        # (x, y, z) -> (x, z, y): the length runs up Y, the flat side faces +Z
        return flip_axes(prism, (0, 2, 1)).translate(0, LOG_H / 2, 0)

    bark = half_prism(LOG_R, LOG_H - 0.08, 0.03)
    wood = half_prism(0.8, LOG_H, 0.0)
    return {"Bark": bark, "Wood": wood}


def axe():
    handle = taper([(0.35, 0.0, 0.0), (-1.5, 0.06, 0.0), (-3.2, 0.02, 0.0), (-5.05, -0.08, 0.0)], 0.2, 0.17, 10)
    grip = taper([(-1.2, 0.05, 0.0), (-2.6, 0.04, 0.0)], 0.235, 0.235, 10)
    collar = along_z(cylinder(0.42, 0.6, 20, 0.06).translate(0, -0.3, 0))
    bands = merge(*[cylinder(0.24, 0.16, 12).translate(0, -0.08, 0).rotate("z", 90).translate(x, 0, 0) for x in (-0.55, -3.95)])
    head_pts = [
        (-4.95, 0.55), (-4.25, 0.55), (-4.22, -0.2), (-3.82, -0.98), (-3.84, -1.2),
        (-4.6, -1.3), (-5.36, -1.2), (-5.38, -0.98), (-4.98, -0.2),
    ]
    head = extrude(head_pts, 0.42)
    # The blade thins towards its edge.
    t = np.clip((-head.v[:, 1] - 0.15) / 1.1, 0, 1)
    head.v[:, 2] *= 1 - 0.72 * t
    edge = extrude([(-3.8, -1.0), (-3.84, -1.22), (-4.6, -1.33), (-5.36, -1.22), (-5.4, -1.0), (-4.6, -1.1)], 0.14)
    return {"Handle": handle, "Grip": grip, "Collar": collar, "Bands": bands, "Head": head, "Edge": edge}


def axe_frame():
    hinge = 5.2
    base = rounded_box(1.9, 0.6, 1.9, 0.15).translate(0, 0.3, 0.8)
    post = rounded_box(0.8, hinge + 0.4, 0.8, 0.12).translate(0, 0.6 + (hinge + 0.4) / 2 - 0.1, 0.85)
    braces = merge(
        taper([(-0.85, 0.55, 0.85), (-0.2, 2.2, 0.85)], 0.16, 0.16, 8),
        taper([(0.85, 0.55, 0.85), (0.2, 2.2, 0.85)], 0.16, 0.16, 8),
        taper([(0.0, 0.55, 1.75), (0.0, 2.2, 1.1)], 0.16, 0.16, 8),
    )
    bolt = along_z(cylinder(0.16, 1.0, 12).translate(0, -0.5, 0)).translate(0, hinge, 0)
    plates = merge(
        rounded_box(1.1, 1.1, 0.12, 0.05).translate(0, hinge, 0.42),
        rounded_box(1.0, 0.18, 0.86, 0.05).translate(0, hinge + 0.62, 0.85),
    )
    nut = along_z(cylinder(0.26, 0.14, 6).translate(0, -0.07, 0)).translate(0, hinge, -0.55)
    spring = []
    pts = []
    for i in range(64):
        a = i / 63 * 7 * 2 * math.pi
        pts.append((math.cos(a) * 0.22, 1.2 + i / 63 * 2.6, 0.85 - 0.62 + math.sin(a) * 0.22))
    spring.append(tube(pts, 0.05, 6))
    return {"Base": base, "Post": merge(post, braces), "Bolt": bolt, "Plates": merge(plates, nut), "Spring": merge(*spring)}


def lying_log(x, y, length=LOG_H, radius=LOG_R, seed=0):
    bark = organic_lathe([(0.0, -length / 2 + 0.04), (radius * 0.86, -length / 2 + 0.04), (radius, -length / 2 + 0.14),
                          (radius, length / 2 - 0.14), (radius * 0.86, length / 2 - 0.04), (0.0, length / 2 - 0.04)], 20, 0.04, 6, seed)
    ends = merge(cylinder(radius * 0.88, 0.05, 20).translate(0, -length / 2, 0), cylinder(radius * 0.88, 0.05, 20).translate(0, length / 2 - 0.05, 0))
    return along_z(bark).translate(x, y, 0), along_z(ends).translate(x, y, 0)


def rack():
    def rail_y(x):
        return 1.5 + x / 4.4 * 1.2

    frame = []
    for z in (-0.85, 0.85):
        frame.append(taper([(-0.1, rail_y(-0.1) - 0.12, z), (4.6, rail_y(4.6) - 0.12, z)], 0.2, 0.2, 8))
        frame.append(rounded_box(0.32, rail_y(0.1), 0.32, 0.06).translate(0.1, rail_y(0.1) / 2, z))
        frame.append(rounded_box(0.32, rail_y(4.3), 0.32, 0.06).translate(4.3, rail_y(4.3) / 2, z))
        frame.append(taper([(0.2, 0.25, z), (4.2, rail_y(4.2) - 0.4, z)], 0.11, 0.11, 6))
        frame.append(rounded_box(0.36, 2.1, 0.36, 0.08).translate(4.75, rail_y(4.75) + 0.2, z))
    frame.append(rounded_box(0.3, 0.3, 2.0, 0.06).translate(0.1, 0.45, 0))
    frame.append(rounded_box(0.3, 0.3, 2.0, 0.06).translate(4.3, 0.45, 0))
    peg = rounded_box(0.3, 0.6, 1.6, 0.08).translate(-0.3, 1.6, 0)
    barks, ends = [], []
    spots = [(2.2, rail_y(2.2) + LOG_R + 0.05), (3.95, rail_y(3.95) + LOG_R + 0.05), (3.08, rail_y(3.08) + LOG_R + 1.55)]
    for i, (x, y) in enumerate(spots):
        b, e = lying_log(x, y, seed=11 + i)
        barks.append(b)
        ends.append(e)
    return {"Frame": merge(*frame), "Peg": peg, "Logs": merge(*barks), "LogEnds": merge(*ends)}


def chips():
    mound = icosphere(1.0, 2, 0.25, seed=4).scale(1.7, 0.32, 1.4)
    mound.v[:, 1] = np.maximum(mound.v[:, 1], -0.02)
    rng = np.random.default_rng(9)
    bits = []
    for _ in range(14):
        a = rng.uniform(0, 2 * math.pi)
        d = rng.uniform(0.6, 2.4)
        chip = rounded_box(rng.uniform(0.3, 0.55), 0.08, rng.uniform(0.15, 0.3), 0.03, 2)
        chip.rotate("x", rng.uniform(-25, 25)).rotate("y", rng.uniform(0, 360))
        bits.append(chip.translate(math.cos(a) * d, 0.08 + max(0, 0.3 - d * 0.1), math.sin(a) * d * 0.85))
    return {"Sawdust": mound, "Chips": merge(*bits)}


def pine():
    trunk = taper([(0, 0, 0), (0, 4, 0), (0, 18, 0)], 0.9, 0.25, 10)
    roots = merge(*[taper([(math.cos(a) * 0.5, 0.8, math.sin(a) * 0.5), (math.cos(a) * 1.5, 0.05, math.sin(a) * 1.5)], 0.35, 0.12, 6)
                    for a in np.linspace(0, 2 * math.pi, 5, endpoint=False)])
    layers = []
    for i, (y, r, h) in enumerate(((3.2, 5.2, 6.0), (6.6, 4.3, 5.6), (9.8, 3.4, 5.0), (12.8, 2.5, 4.4), (15.6, 1.5, 3.8))):
        layers.append(organic_lathe([(0.0, y), (r * 0.8, y), (r, y + 0.35), (r * 0.55, y + h * 0.45), (0.0, y + h)], 24, 0.08, 8, seed=i))
    return {"Trunk": merge(trunk, roots), "Needles": merge(*layers)}


def mill():
    w, d, wall_h = 30.0, 16.0, 11.0
    walls = []
    trim = []
    # Plank walls: rows of slightly uneven boards on the back and both sides, the front left open
    # round a big doorway.
    for row in range(10):
        y = 0.55 + row * 1.1
        jitter = (row % 3) * 0.05
        walls.append(rounded_box(w, 1.0, 0.5, 0.12, 3).translate(0, y + 0.5, d / 2 - 0.25 + jitter))
        for side in (-1, 1):
            walls.append(rounded_box(0.5, 1.0, d, 0.12, 3).translate(side * (w / 2 - 0.25 - jitter), y + 0.5, 0))
            walls.append(rounded_box(9.0, 1.0, 0.5, 0.12, 3).translate(side * (w / 2 - 4.5), y + 0.5, -d / 2 + 0.25 - jitter))
        walls.append(rounded_box(w - 18.0, 1.0, 0.5, 0.12, 3).translate(0, y + 0.5, -d / 2 + 0.25)) if row >= 7 else None
    walls = [m for m in walls if m is not None]
    for x in (-w / 2, -w / 2 + 9, w / 2 - 9, w / 2):
        trim.append(rounded_box(0.9, wall_h + 0.6, 0.9, 0.15).translate(x, (wall_h + 0.6) / 2, -d / 2))
        trim.append(rounded_box(0.9, wall_h + 0.6, 0.9, 0.15).translate(x, (wall_h + 0.6) / 2, d / 2))
    trim.append(rounded_box(w + 1.0, 0.8, 0.9, 0.15).translate(0, wall_h + 0.3, -d / 2))
    trim.append(rounded_box(w - 17.0, 0.7, 0.9, 0.15).translate(0, 8.25, -d / 2))
    # Gable ends and the roof: two big slabs at 30 degrees.
    rise = d / 2 * math.tan(math.radians(30))
    gable = extrude([(-d / 2, 0), (d / 2, 0), (0, rise)], 0.5)
    gables = merge(flip_axes(gable.copy(), (2, 1, 0)).translate(-w / 2 + 0.25, wall_h + 0.6, 0),
                   flip_axes(gable.copy(), (2, 1, 0)).translate(w / 2 - 0.25, wall_h + 0.6, 0))
    slope = math.hypot(d / 2, rise) + 1.2
    roof = []
    for side in (-1, 1):
        slab = rounded_box(w + 2.4, 0.6, slope, 0.2)
        slab.rotate("x", side * 30).translate(0, wall_h + 0.6 + rise / 2 + 0.2, side * d / 4)
        roof.append(slab)
    ridge = along_z(cylinder(0.45, w + 2.6, 12).translate(0, -(w + 2.6) / 2, 0)).rotate("y", 90).translate(0, wall_h + 0.6 + rise + 0.35, 0)
    # The inside you see through the door: dark.
    inside = rounded_box(11.6, 8.0, 0.4, 0.1).translate(0, 4.0, d / 2 - 1.0)
    # A big saw blade on the front gable.
    saw = extrude(star(3.0, 2.55, 20), 0.3).translate(0, wall_h + 3.0, -d / 2 - 0.2)
    hub = along_z(cylinder(0.8, 0.5, 16).translate(0, -0.25, 0)).translate(0, wall_h + 3.0, -d / 2 - 0.4)
    chimney = merge(rounded_box(2.2, 7.0, 2.2, 0.2).translate(w / 2 - 6, wall_h + 6.0, 3.0),
                    rounded_box(2.7, 0.6, 2.7, 0.15).translate(w / 2 - 6, wall_h + 9.6, 3.0))
    # The water wheel on the left side.
    wheel_x = -w / 2 - 1.6
    rim = merge(torus(5.0, 0.3, 40, 8), torus(3.6, 0.22, 40, 8))
    spokes = merge(*[tube([(math.cos(a) * 0.4, 0, math.sin(a) * 0.4), (math.cos(a) * 5.0, 0, math.sin(a) * 5.0)], 0.18, 6)
                     for a in np.linspace(0, 2 * math.pi, 8, endpoint=False)])
    paddles = merge(*[rounded_box(1.6, 0.18, 1.3, 0.05, 2).rotate("y", -math.degrees(a)).translate(math.cos(a) * 4.4, 0, math.sin(a) * 4.4)
                      for a in np.linspace(0, 2 * math.pi, 16, endpoint=False)])
    wheel = merge(rim, spokes, paddles).rotate("z", 90).translate(wheel_x, 5.4, 1.0)
    axle = along_z(cylinder(0.5, 2.6, 12)).rotate("y", 90).translate(-w / 2 - 2.2, 5.4, 1.0)
    return {
        "Walls": merge(*walls, *[gables]),
        "Trim": merge(*trim, ridge),
        "Roof": merge(*roof),
        "Inside": inside,
        "Saw": saw,
        "Hub": hub,
        "Chimney": chimney,
        "Wheel": merge(wheel, axle),
    }


def lumber():
    planks = []
    for layer in range(5):
        y = 0.35 + layer * 0.5
        for i in range(5):
            if layer % 2 == 0:
                planks.append(rounded_box(7.0, 0.42, 0.95, 0.06, 3).translate(0, y, -2.0 + i * 1.0))
            else:
                planks.append(rounded_box(0.95, 0.42, 4.6, 0.06, 3).translate(-3.0 + i * 1.5, y, 0))
    straps = merge(*[rounded_box(0.25, 2.65, 5.0, 0.05).translate(x, 1.35, 0) for x in (-2.2, 2.2)])
    barks, ends = [], []
    for row, count in enumerate((4, 3, 2)):
        for i in range(count):
            x = 6.4 + (i - (count - 1) / 2) * 1.8
            b, e = lying_log(x, 0.9 + row * 1.5, 4.8, 0.9, seed=row * 5 + i)
            barks.append(b)
            ends.append(e)
    chocks = merge(rounded_box(0.5, 0.5, 0.6, 0.1).translate(3.3, 0.25, -1.8), rounded_box(0.5, 0.5, 0.6, 0.1).translate(9.5, 0.25, 1.8))
    return {"Planks": merge(*planks), "Straps": straps, "Logs": merge(*barks), "LogEnds": merge(*ends), "Chocks": chocks}


PROPS = {
    "LogJamStump": stump,
    "LogJamLog": log,
    "LogJamHalf": half_log,
    "LogJamAxe": axe,
    "LogJamAxeFrame": axe_frame,
    "LogJamRack": rack,
    "LogJamChips": chips,
    "LogJamPine": pine,
    "LogJamMill": mill,
    "LogJamLumber": lumber,
}
COLORS = {
    "Bark": (122, 84, 52),
    "Top": (226, 186, 128),
    "Rings": (176, 128, 80),
    "Cuts": (90, 60, 40),
    "Ends": (232, 196, 140),
    "Wood": (236, 200, 146),
    "Handle": (196, 140, 84),
    "Grip": (150, 60, 50),
    "Collar": (90, 94, 104),
    "Bands": (90, 94, 104),
    "Head": (120, 128, 140),
    "Edge": (230, 236, 244),
    "Base": (130, 130, 136),
    "Post": (150, 100, 60),
    "Bolt": (70, 72, 80),
    "Plates": (90, 94, 104),
    "Spring": (200, 170, 70),
    "Frame": (140, 94, 56),
    "Peg": (110, 74, 44),
    "Logs": (122, 84, 52),
    "LogEnds": (232, 196, 140),
    "Sawdust": (236, 206, 150),
    "Chips": (214, 170, 110),
    "Trunk": (110, 74, 48),
    "Needles": (56, 130, 80),
    "Walls": (196, 140, 88),
    "Trim": (120, 78, 46),
    "Roof": (170, 70, 56),
    "Inside": (40, 30, 24),
    "Saw": (200, 206, 214),
    "Hub": (200, 60, 50),
    "Chimney": (140, 136, 130),
    "Wheel": (130, 88, 54),
    "Planks": (226, 184, 124),
    "Straps": (60, 64, 72),
    "Chocks": (110, 74, 44),
}
