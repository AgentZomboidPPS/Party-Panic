"""Meshes for Dice Dash (see tools/meshgen/props/README.md). Units are studs, +Y up, base on y = 0,
-Z is the front. Generate with: python3 tools/meshgen/generate_meshes.py --only DiceDashDie,...

The board tiles are 9 x 9 chunky slabs (a Base, a coloured Top plate and a low raised Icon whose
top sits at 1.22, a little above the plate's 1.1), the START / FINISH pads are 15-stud discs built
the same way. Everything else is decoration: the giant die (rounded cube with pips: 1 up, 2 at the
front (-Z), 3 on the right (+X); opposite faces add up to 7), arches with flags, a springboard, a
cannon (its barrel points -Z), a turned table leg, and oversized board-game clutter (a spinner, a
rule book, playing cards, a pawn)."""

import math

from generate_meshes import Mesh, cylinder, extrude, lathe, merge, rounded_box, sphere, star, taper, torus

TILE = 9.0
TOP = 1.1  # the coloured plate's top (the walkable surface)


def flat(polygon, depth=0.24, y=TOP):
    """A 2D icon lying on the tile: the polygon's +y points forward (-Z), half sunk into the plate."""
    return extrude(polygon, depth).rotate("x", -90).translate(0, y, 0)


def circle(radius, n=24, cx=0.0, cy=0.0):
    return [(cx + radius * math.cos(2 * math.pi * i / n), cy + radius * math.sin(2 * math.pi * i / n)) for i in range(n)]


def tile_body():
    base = rounded_box(TILE, 0.9, TILE, 0.35).translate(0, 0.45, 0)
    top = rounded_box(TILE - 0.7, 0.4, TILE - 0.7, 0.16).translate(0, TOP - 0.2, 0)
    return base, top


ICON_TOP = 1.24  # every icon's top (so every tile and pad is exactly this tall)


def level(icon):
    """Squashes (or stretches) an icon's relief about the plate so its top is exactly ICON_TOP."""
    high = icon.v[:, 1].max()
    icon.v[:, 1] = TOP + (icon.v[:, 1] - TOP) * (ICON_TOP - TOP) / (high - TOP)
    return icon


def tile(icon):
    base, top = tile_body()
    return {"Base": base, "Top": top, "Icon": level(icon)}


def tile_plain():
    return tile(merge(*[flat(circle(0.55, 16, x, y)) for x, y in ((0, 0), (2.6, 2.6), (-2.6, 2.6), (2.6, -2.6), (-2.6, -2.6))]))


def tile_boost():
    chevron = lambda y0: [(-2.2, y0 - 1.0), (0.0, y0 + 1.1), (2.2, y0 - 1.0), (2.2, y0 - 2.1), (0.0, y0), (-2.2, y0 - 2.1)]
    # (each chevron is two convex halves, so the centroid fan stays inside it)
    parts = []
    for y0 in (0.2, 2.6):
        pts = chevron(y0)
        parts.append(flat([pts[0], pts[1], pts[4], pts[5]]))
        parts.append(flat([pts[1], pts[2], pts[3], pts[4]]))
    parts.append(flat([(-0.9, -3.2), (0.9, -3.2), (0.9, -1.5), (-0.9, -1.5)]))
    return tile(merge(*parts))


def tile_slip():
    peel = flat(star(2.9, 0.9, 3), 0.24)
    middle = cylinder(1.25, 0.34, 20, 0.1).translate(0, TOP - 0.1, 0)
    stem = flat([(-0.35, 0.6), (0.35, 0.6), (0.3, 1.8), (-0.3, 1.8)], 0.3, TOP + 0.02)
    return tile(merge(peel, middle, stem).rotate("y", 20))


def tile_cannon():
    ball = flat(circle(1.5, 24, 0, -1.2))
    barrel = flat([(-0.9, -0.6), (0.9, -0.6), (0.7, 2.8), (-0.7, 2.8)])
    muzzle = flat([(-1.05, 2.6), (1.05, 2.6), (1.05, 3.3), (-1.05, 3.3)])
    return tile(merge(ball, barrel, muzzle))


def tile_swap():
    parts = []
    for turn in (0, 180):
        arc = [(2.2 * math.cos(math.radians(a)), TOP + 0.02, 2.2 * math.sin(math.radians(a))) for a in range(20, 161, 10)]
        tube = taper(arc, 0.32, 0.32, 8)
        tip = flat([(-0.2, -1.1), (1.2, 0.0), (-0.2, 1.1)]).translate(2.15, 0, 0.5)
        parts.append(merge(tube, tip).rotate("y", turn))
    return tile(merge(*parts))


def tile_event():
    hook = [(-1.4, 1.2), (-1.2, 2.0), (-0.5, 2.5), (0.4, 2.5), (1.2, 2.0), (1.4, 1.2), (1.0, 0.5), (0.2, 0.0), (0.0, -0.6), (0.0, -1.1)]
    tube = taper([(x, TOP + 0.03, -y) for x, y in hook], 0.42, 0.42, 8)
    dot = flat(circle(0.55, 16, 0, -2.2), 0.26)
    return tile(merge(tube, dot))


def tile_trap():
    doors = merge(
        rounded_box(2.75, 0.24, 5.8, 0.08).translate(-1.5, TOP, 0),
        rounded_box(2.75, 0.24, 5.8, 0.08).translate(1.5, TOP, 0),
    )
    rim = torus(3.55, 0.2, 40, 8).translate(0, TOP + 0.02, 0)
    hinges = merge(*[rounded_box(0.5, 0.3, 0.9, 0.1).translate(x, TOP + 0.02, z) for x in (-2.7, 2.7) for z in (-1.8, 1.8)])
    return tile(merge(doors, rim, hinges))


def pad(icon_fn):
    base = cylinder(7.5, 0.9, 48, 0.3)
    top = cylinder(7.0, 0.4, 48, 0.15).translate(0, TOP - 0.4, 0)
    return {"Base": base, "Top": top, "Icon": level(icon_fn())}


def pad_start():
    return pad(lambda: merge(flat(star(3.4, 1.5, 5)), torus(5.6, 0.22, 48, 8).translate(0, TOP + 0.02, 0)))


def pad_finish():
    squares = []
    for i in range(16):
        if i % 2:
            continue
        a = 2 * math.pi * i / 16
        squares.append(rounded_box(1.7, 0.24, 1.7, 0.08).rotate("y", -math.degrees(a)).translate(5.4 * math.cos(a), TOP, 5.4 * math.sin(a)))
    inner = []
    for i in range(8):
        if i % 2:
            continue
        a = 2 * math.pi * i / 8 + 0.4
        inner.append(rounded_box(1.5, 0.24, 1.5, 0.08).rotate("y", -math.degrees(a)).translate(2.6 * math.cos(a), TOP, 2.6 * math.sin(a)))
    return pad(lambda: merge(*squares, *inner))


def arch(finish):
    span = 8.8
    posts = merge(*[merge(rounded_box(1.5, 12.0, 1.5, 0.45).translate(x, 6.0, 0), rounded_box(2.4, 1.0, 2.4, 0.3).translate(x, 0.5, 0)) for x in (-span, span)])
    beam_pts = [(span * math.sin(math.radians(a)), 11.6 + 2.0 * math.cos(math.radians(a)), 0.0) for a in range(-90, 91, 10)]
    beam = taper(beam_pts, 0.75, 0.75, 10)
    banner = rounded_box(12.0, 3.0, 0.6, 0.25).translate(0, 12.6, 0)
    poles = merge(*[taper([(x, 11.8, 0), (x, 17.0, 0)], 0.16, 0.12, 8) for x in (-span, span)])
    flags = merge(*[extrude([(0, 0), (2.6 * side, 0.7), (0, 1.5)], 0.12).translate(span * side, 15.3, 0) for side in (-1, 1)])
    pieces = {"Posts": posts, "Beam": beam, "Banner": banner, "Poles": poles, "Flags": flags}
    if finish:
        checks = []
        for row in range(2):
            for col in range(10):
                if (row + col) % 2 == 0:
                    for z in (-0.33, 0.33):
                        checks.append(rounded_box(1.05, 1.2, 0.08, 0.03).translate(-5.25 + col * 1.17 + 0.0, 12.0 + row * 1.2, z))
        pieces["Checks"] = merge(*checks)
    return pieces


def die():
    s = 3.4
    h = s / 2
    body = rounded_box(s, s, s, 0.62).translate(0, h, 0)
    g = 0.82
    layouts = {
        1: [(0, 0)],
        2: [(-g, -g), (g, g)],
        3: [(-g, -g), (0, 0), (g, g)],
        4: [(-g, -g), (g, -g), (-g, g), (g, g)],
        5: [(-g, -g), (g, -g), (0, 0), (-g, g), (g, g)],
        6: [(-g, -g), (g, -g), (-g, 0), (g, 0), (-g, g), (g, g)],
    }
    # face: (value, axis, sign)
    faces = [(1, "y", 1), (6, "y", -1), (2, "z", -1), (5, "z", 1), (3, "x", 1), (4, "x", -1)]
    pips = []
    for value, axis, sign in faces:
        for u, v in layouts[value]:
            pip = sphere(0.34, 8, 12)
            if axis == "y":
                pip.scale(1, 0.4, 1).translate(u, h + sign * h, v)
            elif axis == "z":
                pip.scale(1, 1, 0.4).translate(u, h + v, sign * h)
            else:
                pip.scale(0.4, 1, 1).translate(sign * h, h + v, u)
            pips.append(pip)
    return {"Body": body, "Pips": merge(*pips)}


def spring():
    base = rounded_box(3.4, 0.4, 3.4, 0.15).translate(0, 0.2, 0)
    coil_pts = [(1.0 * math.cos(t / 8 * math.pi), 0.45 + 1.6 * t / 40, 1.0 * math.sin(t / 8 * math.pi)) for t in range(41)]
    coil = taper(coil_pts, 0.17, 0.17, 8)
    plate = rounded_box(3.6, 0.35, 3.6, 0.15).rotate("x", -10).translate(0, 2.25, 0)
    return {"Base": base, "Coil": coil, "Plate": plate}


def cannon():
    barrel = lathe([(0.0, 0.0), (0.85, 0.0), (1.0, 0.35), (0.85, 0.7), (0.62, 3.5), (0.82, 3.7), (0.82, 4.1), (0.48, 4.1), (0.48, 3.6), (0.0, 3.6)], 24)
    barrel.rotate("x", -72).translate(0, 2.0, 1.2)
    carriage = rounded_box(2.0, 1.3, 3.2, 0.3).translate(0, 1.35, 0.6)
    wheels = merge(*[cylinder(1.15, 0.45, 20, 0.12).rotate("z", 90).translate(x, 1.15, 0.6) for x in (-1.0, 1.45)])
    # (cylinder grows along +Y; turned onto X it runs from x to x - 0.45)
    return {"Barrel": barrel, "Carriage": carriage, "Wheels": wheels}


def table_leg():
    profile = [(0.0, 0.0), (2.3, 0.0), (2.5, 0.6), (1.7, 1.7), (1.45, 8.0), (2.1, 10.0), (1.35, 12.0), (1.25, 21.5), (2.0, 23.5), (2.7, 26.5), (3.1, 29.7), (0.0, 29.7)]
    return {"Leg": lathe(profile, 28)}


def spinner():
    card = rounded_box(20.0, 0.6, 20.0, 0.5).translate(0, 0.3, 0)
    pieces = {"Card": card}
    for index, name in enumerate(("SegA", "SegB", "SegC", "SegD")):
        a0 = index * 90
        pts = [(0.0, 0.0)] + [(8.0 * math.cos(math.radians(a)), 8.0 * math.sin(math.radians(a))) for a in range(a0, a0 + 91, 6)]
        pieces[name] = flat(pts, 0.3, 0.72)
    pieces["Rim"] = torus(8.2, 0.32, 64, 8).translate(0, 0.78, 0)
    pin = cylinder(0.6, 1.3, 16, 0.15).translate(0, 0.6, 0)
    arrow = flat([(-0.5, -3.0), (0.5, -3.0), (0.5, 4.2), (1.3, 4.2), (0.0, 6.6), (-1.3, 4.2), (-0.5, 4.2)], 0.35, 1.55).rotate("y", 35)
    pieces["Arrow"] = merge(arrow, pin)
    return pieces


def rule_book():
    covers = merge(
        rounded_box(16.0, 0.5, 22.0, 0.18).translate(0, 0.25, 0),
        rounded_box(16.0, 0.5, 22.0, 0.18).translate(0, 3.25, 0),
        rounded_box(0.8, 3.5, 22.0, 0.3).translate(-7.8, 1.75, 0),
    )
    pages = rounded_box(15.2, 2.6, 21.2, 0.1).translate(0.3, 1.75, 0)
    band = merge(rounded_box(11.0, 0.2, 2.6, 0.08).translate(0.4, 3.55, -5.5), flat(star(2.6, 1.15, 5), 0.24, 3.55).translate(0.4, 0, 2.0))
    return {"Cover": covers, "Pages": pages, "Band": band}


def cards():
    faces, marks = [], []
    for index, angle in enumerate((-28, -10, 8, 26)):
        y = 0.1 + index * 0.2
        card = rounded_box(8.0, 0.18, 12.0, 0.08).translate(0, y, -4.6).rotate("y", angle)
        faces.append(card)
        mark = flat([(0, 1.6), (1.1, 0), (0, -1.6), (-1.1, 0)], 0.12, y + 0.1).translate(0, 0, -4.6).rotate("y", angle)
        marks.append(mark)
    deck = rounded_box(8.0, 1.6, 12.0, 0.12).translate(8.5, 0.8, 1.5)
    return {"Face": merge(*faces), "Mark": merge(*marks), "Back": deck}


def pawn():
    profile = [(0.0, 0.0), (3.0, 0.0), (3.1, 0.4), (2.9, 0.9), (2.2, 1.2), (1.6, 2.0), (1.2, 4.5), (1.0, 6.0), (1.8, 6.4), (1.9, 6.7), (1.1, 7.0), (1.5, 7.6), (1.9, 8.6), (1.65, 9.6), (0.9, 10.2), (0.0, 10.4)]
    return {"Body": lathe(profile, 32)}


PROPS = {
    "DiceDashDie": die,
    "DiceDashTile": tile_plain,
    "DiceDashTileBoost": tile_boost,
    "DiceDashTileSlip": tile_slip,
    "DiceDashTileCannon": tile_cannon,
    "DiceDashTileSwap": tile_swap,
    "DiceDashTileEvent": tile_event,
    "DiceDashTileTrap": tile_trap,
    "DiceDashPadStart": pad_start,
    "DiceDashPadFinish": pad_finish,
    "DiceDashArchStart": lambda: arch(False),
    "DiceDashArchFinish": lambda: arch(True),
    "DiceDashSpring": spring,
    "DiceDashCannon": cannon,
    "DiceDashTableLeg": table_leg,
    "DiceDashSpinner": spinner,
    "DiceDashRuleBook": rule_book,
    "DiceDashCards": cards,
    "DiceDashPawn": pawn,
}
COLORS = {
    "Base": (120, 80, 60), "Top": (245, 235, 210), "Icon": (90, 200, 110), "Body": (250, 248, 240), "Pips": (40, 36, 60),
    "Posts": (240, 240, 245), "Beam": (255, 90, 100), "Banner": (70, 150, 255), "Poles": (230, 230, 230), "Flags": (255, 210, 60),
    "Checks": (30, 30, 36), "Coil": (190, 195, 210), "Plate": (90, 210, 110), "Barrel": (60, 62, 74), "Carriage": (150, 95, 55),
    "Wheels": (110, 70, 45), "Leg": (150, 100, 60), "Card": (250, 245, 230), "SegA": (255, 90, 100), "SegB": (70, 150, 255),
    "SegC": (255, 205, 60), "SegD": (90, 210, 110), "Rim": (250, 250, 250), "Arrow": (40, 36, 60), "Cover": (200, 50, 70),
    "Pages": (250, 245, 230), "Band": (255, 205, 60), "Face": (252, 250, 245), "Mark": (230, 50, 70), "Back": (60, 90, 200),
}
