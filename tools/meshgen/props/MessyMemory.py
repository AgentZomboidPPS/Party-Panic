"""Props for Messy Memory: the toy shop's booth (side walls, a striped scalloped awning, a counter,
a curtain rod), the cubby shelf (4 x 3 slots), a pleated curtain half, a smoke puff, eight toys
(teddy, rubber duck, rocket, robot, beach ball, spinning top, star block, sailboat) and the open
toy chest in the middle of the shop.

Units are studs, +Y up, base on y = 0, -Z is the front. The shelf's slots and the counter's height
match src/shared/Logic/MessyMemory.luau (COL_X0, COL_PITCH, ROW_FLOORS, COUNTER_TOP), so a toy put
in a slot by the game stands on that cubby's floor. Every mesh is centred on x = 0, z = 0 (the game
pivots a prop at the bottom middle of its bounding box).

    python3 tools/meshgen/generate_meshes.py --only MessyMemoryShelf,MessyMemoryBooth,...
"""

from __future__ import annotations

import math

import numpy as np

from generate_meshes import (
    Mesh,
    capsule,
    cylinder,
    extrude,
    icosphere,
    lathe,
    merge,
    rounded_box,
    sd_capsule,
    sd_ellipsoid,
    sdf_mesh,
    smin,
    sphere,
    star,
    torus,
    tube,
    weld,
)


def box(x0, x1, y0, y1, z0, z1, r=0.06):
    """A rounded box from its extents."""
    sx, sy, sz = x1 - x0, y1 - y0, z1 - z0
    return rounded_box(sx, sy, sz, min(r, sx / 2.2, sy / 2.2, sz / 2.2), 4).translate(
        (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2
    )


def ball(r, x, y, z, rings=10, segments=16):
    return sphere(r, rings, segments).translate(x, y, z)


# ====================================================================== shelf

SHELF_W = 10.45
COL_X0 = -3.825
COL_PITCH = 2.55
ROW_FLOORS = (9.15, 6.4, 3.65)
BOARD = 0.25


def shelf():
    half = SHELF_W / 2
    front, back = -1.2, 1.2
    wood = []
    # Sides.
    for side in (-1, 1):
        wood.append(box(side * half - (BOARD if side > 0 else 0), side * half + (0 if side > 0 else BOARD), 2.9, 11.9, front, back))
    # Boards: under each row, and the top.
    for floor in ROW_FLOORS:
        wood.append(box(-half + BOARD, half - BOARD, floor - BOARD, floor, front, back - BOARD))
    wood.append(box(-half + BOARD, half - BOARD, 11.65, 11.9, front, back - BOARD))
    # Dividers between the columns.
    for k in range(1, 4):
        x = COL_X0 + (k - 0.5) * COL_PITCH
        wood.append(box(x - BOARD / 2, x + BOARD / 2, 3.4, 11.65, front + 0.02, back - BOARD))
    # Apron and legs.
    apron = box(-half, half, 2.75, 3.4, front - 0.02, back)
    legs = []
    for sx in (-1, 1):
        for sz in (-1, 1):
            legs.append(
                lathe([(0.0, 0.0), (0.28, 0.0), (0.34, 0.25), (0.22, 0.9), (0.26, 2.2), (0.36, 2.8), (0.0, 2.8)], 14).translate(
                    sx * (half - 0.4), 0, sz * 0.8
                )
            )
    back_panel = box(-half + 0.05, half - 0.05, 3.4, 11.9, back - BOARD, back - 0.02, 0.03)
    crown = merge(
        box(-half - 0.2, half + 0.2, 11.9, 12.25, -1.3, 1.3, 0.12),
        box(-half - 0.05, half + 0.05, 12.25, 12.7, -1.1, 1.1, 0.15),
    )
    # Round knobs on the front edge of each board (cute), one per column.
    knobs = []
    for floor in ROW_FLOORS:
        for col in range(4):
            knobs.append(ball(0.09, COL_X0 + col * COL_PITCH, floor - BOARD / 2, front - 0.02, 6, 10))
    return {
        "Wood": merge(*wood),
        "Back": back_panel,
        "Trim": merge(apron, crown),
        "Legs": merge(*legs),
        "Knobs": merge(*knobs),
    }


# ====================================================================== booth
# Booth frame (src/shared/Logic/MessyMemory.luau) -> mesh: the game places the booth at local
# z = -3.5 turned half round, so mesh z = -(local z + 3.5) and the booth's open front is -Z here.


def scallop_stripe(x0, x1, y_top, y_bottom, depth):
    """One awning stripe: a rectangle with a round bottom, as an extruded outline."""
    w = x1 - x0
    r = w / 2
    pts = [(x0, y_top), (x1, y_top), (x1, y_bottom + r)]
    for i in range(1, 12):
        a = math.pi * i / 12
        pts.append((x0 + r + math.cos(a) * r, y_bottom + r - math.sin(a) * r))
    pts.append((x0, y_bottom + r))
    return extrude(pts, depth)


def booth():
    wall = []
    for side in (-1, 1):
        x0, x1 = (6.4, 6.8) if side > 0 else (-6.8, -6.4)
        wall.append(box(x0, x1, 0.0, 14.4, -3.5, 4.3, 0.08))
    wall.append(box(-6.8, 6.8, 0.0, 14.4, 3.9, 4.3, 0.08))
    roof = merge(
        box(-6.75, 6.75, 14.4, 14.75, -4.3, 4.3, 0.12),
        box(-6.6, 6.6, 14.75, 14.9, -3.9, 3.9, 0.06),
    )
    # The awning: 12 stripes across the front, alternating colors, scalloped bottoms.
    awning, awning2 = [], []
    stripes = 12
    width = 13.6 / stripes
    for i in range(stripes):
        x0 = -6.8 + i * width
        stripe = scallop_stripe(x0, x0 + width, 14.4, 11.8, 0.36).translate(0, 0, -4.12)
        (awning if i % 2 == 0 else awning2).append(stripe)
    posts = []
    for side in (-1, 1):
        posts.append(cylinder(0.32, 12.2, 16, 0.08).translate(side * 6.6, 0, -3.72))
        posts.append(ball(0.42, side * 6.6, 12.3, -3.72))
    # Counter: body, top slab, round badges on its front.
    counter = box(-5.6, 5.6, 0.0, 2.35, -2.8, 0.8, 0.1)
    top = box(-5.85, 5.85, 2.35, 2.6, -3.05, 1.0, 0.1)
    badges = []
    for i, x in enumerate((-3.9, -1.3, 1.3, 3.9)):
        disc = cylinder(0.55, 0.08, 20, 0.03).rotate("x", 90).translate(x, 1.25, -2.8)
        badges.append(disc)
    rod = merge(
        tube([(-6.5, 12.55, -3.72), (6.5, 12.55, -3.72)], 0.09, 10),
        ball(0.16, -6.5, 12.55, -3.72, 8, 12),
        ball(0.16, 6.5, 12.55, -3.72, 8, 12),
    )
    return {
        "Wall": merge(*wall),
        "Roof": roof,
        "Awning": merge(*awning),
        "Awning2": merge(*awning2),
        "Post": merge(*posts),
        "Counter": counter,
        "CounterTop": top,
        "Badges": merge(*badges),
        "Rod": rod,
    }


# ====================================================================== curtain


def pleated_slab(width, y0, y1, thickness, amplitude, pleats, steps=96):
    """A thin closed slab whose middle surface waves in z along x (pleats); centred on x = 0."""
    xs = np.linspace(-width / 2, width / 2, steps + 1)
    zs = amplitude * np.sin(xs / width * pleats * 2 * math.pi)
    verts = []
    for y in (y0, y1):
        for side in (-1, 1):
            for x, z in zip(xs, zs):
                verts.append((x, y, z + side * thickness / 2))
    n = steps + 1

    def idx(level, side, i):
        return level * 2 * n + (0 if side < 0 else n) + i

    faces = []
    for i in range(steps):
        for side in (-1, 1):
            a, b = idx(0, side, i), idx(0, side, i + 1)
            c, d = idx(1, side, i), idx(1, side, i + 1)
            faces += [(a, b, c), (b, d, c)] if side > 0 else [(a, c, b), (b, c, d)]
        for level in (0, 1):
            a, b = idx(level, -1, i), idx(level, -1, i + 1)
            c, d = idx(level, 1, i), idx(level, 1, i + 1)
            faces += [(a, b, c), (b, d, c)] if level == 0 else [(a, c, b), (b, c, d)]
    for i, sgn in ((0, 1), (steps, -1)):
        a, b = idx(0, -1, i), idx(0, 1, i)
        c, d = idx(1, -1, i), idx(1, 1, i)
        faces += [(a, b, c), (b, d, c)] if sgn > 0 else [(a, c, b), (b, c, d)]
    return Mesh(verts, faces)


def curtain():
    cloth = pleated_slab(6.6, 0.0, 12.5, 0.12, 0.14, 7)
    trim = pleated_slab(6.64, 0.0, 0.45, 0.24, 0.14, 7)
    top = pleated_slab(6.64, 12.1, 12.5, 0.22, 0.14, 7)
    return {"Cloth": cloth, "Trim": merge(trim, top)}


# ====================================================================== smoke


def smoke():
    puffs = []
    spots = [(0, 1.6, 0, 1.5), (1.3, 1.2, 0.3, 1.1), (-1.3, 1.3, -0.2, 1.15), (0.5, 2.6, -0.4, 1.0),
             (-0.6, 2.5, 0.5, 0.95), (0.2, 1.0, 1.0, 0.9), (-0.2, 1.1, -1.0, 0.95)]
    for i, (x, y, z, r) in enumerate(spots):
        puffs.append(icosphere(r, 2, 0.18, seed=i).translate(x, y, z))
    return {"Puff": merge(*puffs)}


# ====================================================================== toys (each about 1.6-1.9 tall)


def eyes(y, z, spread, r=0.07):
    return merge(ball(r, -spread, y, z, 8, 12), ball(r, spread, y, z, 8, 12))


def teddy():
    def sdf(p):
        d = sd_ellipsoid(p, (0, 0.62, 0), (0.48, 0.55, 0.42))
        d = smin(d, sd_ellipsoid(p, (0, 1.32, 0), (0.42, 0.38, 0.38)), 0.12)
        for s in (-1, 1):
            d = smin(d, sd_ellipsoid(p, (s * 0.3, 1.64, 0.02), (0.15, 0.15, 0.1)), 0.05)  # ears
            d = smin(d, sd_capsule(p, (s * 0.38, 0.85, -0.05), (s * 0.58, 0.48, -0.18), 0.14), 0.08)  # arms
            d = smin(d, sd_capsule(p, (s * 0.22, 0.25, -0.05), (s * 0.28, 0.16, -0.38), 0.16), 0.08)  # legs
        return d

    fur = sdf_mesh(sdf, (-0.85, -0.05, -0.75), (0.85, 1.85, 0.6), 0.055)
    fur.v[:, 1] -= fur.v[:, 1].min()
    snout = sphere(1.0, 10, 16).scale(0.17, 0.13, 0.12).translate(0, 1.24, -0.33)
    belly = sphere(1.0, 10, 16).scale(0.28, 0.32, 0.12).translate(0, 0.62, -0.33)
    inner = merge(*(sphere(1.0, 8, 12).scale(0.08, 0.08, 0.05).translate(s * 0.3, 1.63, -0.07) for s in (-1, 1)))
    face = merge(eyes(1.4, -0.33, 0.14, 0.055), ball(0.05, 0, 1.3, -0.44, 8, 12))
    bow = merge(
        sphere(1.0, 8, 12).scale(0.13, 0.09, 0.06).translate(-0.12, 1.0, -0.33),
        sphere(1.0, 8, 12).scale(0.13, 0.09, 0.06).translate(0.12, 1.0, -0.33),
        ball(0.06, 0, 1.0, -0.37, 8, 12),
    )
    return {"Fur": fur, "Snout": merge(snout, belly, inner), "Face": face, "Bow": bow}


def duck():
    def sdf(p):
        d = sd_ellipsoid(p, (0, 0.48, 0.05), (0.62, 0.45, 0.72))
        d = smin(d, sd_ellipsoid(p, (0, 1.12, -0.28), (0.34, 0.34, 0.33)), 0.14)
        d = smin(d, sd_ellipsoid(p, (0, 0.78, 0.68), (0.18, 0.16, 0.2)), 0.12)  # tail
        for s in (-1, 1):
            d = smin(d, sd_ellipsoid(p, (s * 0.55, 0.55, 0.1), (0.12, 0.22, 0.4)), 0.06)  # wings
        return d

    body = sdf_mesh(sdf, (-0.8, -0.05, -0.75), (0.8, 1.55, 0.95), 0.055)
    body.v[:, 1] -= body.v[:, 1].min()
    beak = merge(
        sphere(1.0, 8, 14).scale(0.2, 0.07, 0.2).translate(0, 1.06, -0.6),
        sphere(1.0, 8, 14).scale(0.17, 0.05, 0.16).translate(0, 0.98, -0.56),
    )
    face = eyes(1.22, -0.55, 0.15, 0.06)
    return {"Body": body, "Beak": beak, "Face": face}


def rocket():
    body = lathe([(0.0, 0.25), (0.3, 0.25), (0.36, 0.5), (0.38, 1.05), (0.33, 1.3), (0.0, 1.3)], 28)
    nose = lathe([(0.0, 1.28), (0.335, 1.28), (0.3, 1.45), (0.2, 1.65), (0.08, 1.78), (0.0, 1.82)], 28)
    nozzle = lathe([(0.0, 0.05), (0.24, 0.05), (0.2, 0.18), (0.26, 0.28), (0.0, 0.28)], 20)
    fins = []
    for k in range(3):
        fin = extrude([(0.25, 0.0), (0.66, 0.0), (0.62, 0.22), (0.3, 0.75)], 0.08)
        fin.v[:, 2] = fin.v[:, 2]
        fin.rotate("y", -90 + k * 120 + 30)
        fins.append(fin)
    window_rim = torus(0.15, 0.04, 20, 8).rotate("x", 90).translate(0, 0.95, -0.37)
    window = sphere(1.0, 8, 16).scale(0.13, 0.13, 0.05).translate(0, 0.95, -0.36)
    band = torus(0.375, 0.035, 28, 6).translate(0, 0.62, 0)
    return {
        "Body": merge(body),
        "Nose": merge(nose, *fins, band),
        "Window": window,
        "Rim": merge(window_rim, nozzle),
    }


def robot():
    body = merge(box(-0.42, 0.42, 0.42, 1.05, -0.3, 0.3, 0.1))
    head = box(-0.36, 0.36, 1.1, 1.6, -0.3, 0.3, 0.12)
    legs = merge(box(-0.32, -0.08, 0.0, 0.45, -0.22, 0.2, 0.06), box(0.08, 0.32, 0.0, 0.45, -0.22, 0.2, 0.06))
    arms = merge(
        capsule(0.55, 0.11, 12).translate(-0.53, 0.72, 0),
        capsule(0.55, 0.11, 12).translate(0.53, 0.72, 0),
    )
    screen = box(-0.27, 0.27, 1.2, 1.5, -0.33, -0.27, 0.04)
    chest = box(-0.22, 0.22, 0.58, 0.88, -0.33, -0.28, 0.04)
    antenna = tube([(0, 1.6, 0), (0, 1.78, 0)], 0.03, 8)
    light = ball(0.08, 0, 1.84, 0)
    eyes_ = eyes(1.36, -0.34, 0.11, 0.055)
    buttons = merge(ball(0.045, -0.08, 0.73, -0.34, 6, 10), ball(0.045, 0.08, 0.73, -0.34, 6, 10))
    ears = merge(
        cylinder(0.08, 0.08, 12).rotate("z", 90).translate(-0.36, 1.35, 0),
        cylinder(0.08, 0.08, 12).rotate("z", 90).translate(0.44, 1.35, 0),
    )
    return {
        "Metal": merge(body, head, legs, arms),
        "Screen": merge(screen, chest),
        "Light": merge(light, buttons),
        "Eyes": eyes_,
        "Bolts": merge(antenna, ears),
    }


def gore(r, a0, a1, rings=14, segs=6):
    """A closed slice of a sphere between two longitudes (an orange segment)."""
    verts = []
    for i in range(rings + 1):
        lat = math.pi * i / rings
        for j in range(segs + 1):
            a = a0 + (a1 - a0) * j / segs
            verts.append((math.sin(lat) * math.cos(a) * r, -math.cos(lat) * r, math.sin(lat) * math.sin(a) * r))
    faces = []
    w = segs + 1
    for i in range(rings):
        for j in range(segs):
            a, b, c, d = i * w + j, i * w + j + 1, (i + 1) * w + j, (i + 1) * w + j + 1
            faces += [(a, c, b), (b, c, d)]
    # The two flat sides, fanned from the axis.
    base = len(verts)
    for i in range(rings + 1):
        verts.append((0.0, -math.cos(math.pi * i / rings) * r, 0.0))
    for i in range(rings):
        for j, flip in ((0, False), (segs, True)):
            p, q = i * w + j, (i + 1) * w + j
            ax0, ax1 = base + i, base + i + 1
            faces += [(ax0, p, q), (ax0, q, ax1)] if flip else [(ax0, q, p), (ax0, ax1, q)]
    return weld(Mesh(verts, faces))


def beach_ball():
    r = 0.8
    colors = {"Red": [], "White": [], "Blue": [], "Yellow": []}
    names = ["Red", "White", "Blue", "White", "Yellow", "White"]
    for k in range(6):
        a0 = k * math.pi / 3
        colors[names[k]].append(gore(r, a0, a0 + math.pi / 3).translate(0, r, 0))
    cap = lathe([(0.0, 0.0), (0.17, 0.0), (0.17, 0.04), (0.0, 0.04)], 16)
    caps = merge(cap.copy().translate(0, 2 * r - 0.015, 0), cap.copy().translate(0, -0.025, 0))
    out = {name: merge(*parts) for name, parts in colors.items()}
    out["White"] = merge(out["White"], caps)
    return out


def spinning_top():
    body = lathe(
        [(0.0, 0.0), (0.06, 0.02), (0.2, 0.18), (0.45, 0.45), (0.66, 0.72), (0.7, 0.84), (0.6, 0.98), (0.3, 1.1), (0.0, 1.12)], 32
    )
    band = torus(0.69, 0.06, 32, 8).translate(0, 0.8, 0)
    band2 = torus(0.47, 0.045, 32, 8).translate(0, 0.47, 0)
    handle = merge(cylinder(0.09, 0.45, 14, 0.03).translate(0, 1.08, 0), ball(0.14, 0, 1.58, 0))
    return {"Body": body, "Band": merge(band, band2), "Handle": handle}


def star_block():
    block = rounded_box(1.45, 1.45, 1.45, 0.16, 6).translate(0, 0.725, 0)
    stars = []
    shape = star(0.5, 0.22, 5)
    for k in range(4):
        s = extrude(shape, 0.1).translate(0, 0, -0.75).rotate("y", k * 90).translate(0, 0.725, 0)
        stars.append(s)
    top = extrude(shape, 0.1).rotate("x", 90).translate(0, 1.45 + 0.02, 0)
    return {"Block": block, "Star": merge(*stars, top)}


def sailboat():
    # Long axis along X (seen side-on from the front).
    def sdf(p):
        hull = sd_ellipsoid(p, (0, 0.42, 0), (0.85, 0.4, 0.36))
        cut = p[..., 1] - 0.5  # flat deck
        return np.maximum(hull, cut)

    hull = sdf_mesh(sdf, (-0.95, -0.02, -0.45), (0.95, 0.6, 0.45), 0.05)
    hull.v[:, 1] -= hull.v[:, 1].min()
    stripe = torus(1.0, 0.045, 40, 6).scale(0.8, 1.0, 0.34).translate(0, 0.32, 0)
    mast = tube([(0.05, 0.45, 0), (0.05, 1.8, 0)], 0.04, 8)
    sail = extrude([(0.1, 0.55), (0.1, 1.72), (0.72, 0.6)], 0.05)
    jib = extrude([(0.0, 0.62), (0.0, 1.5), (-0.55, 0.62)], 0.05)
    flag = extrude([(0.08, 1.7), (0.08, 1.88), (0.36, 1.79)], 0.04)
    return {"Hull": hull, "Stripe": stripe, "Mast": mast, "Sail": merge(sail, jib), "Flag": flag}


# ====================================================================== toy chest (the shop's centrepiece)


def toy_box():
    box_body = box(-2.6, 2.6, 0.0, 2.9, -1.8, 1.8, 0.2)
    trim = merge(
        box(-2.7, 2.7, 2.75, 3.05, -1.9, 1.9, 0.1),
        box(-2.7, 2.7, 0.0, 0.3, -1.9, 1.9, 0.1),
        box(-0.35, 0.35, 0.3, 2.75, -1.88, -1.75, 0.06),
    )
    lid = box(-2.65, 2.65, 0.0, 0.35, -3.7, 0.0, 0.15).rotate("x", 105).translate(0, 3.0, 1.85)
    # The pile of toys poking out of the top.
    red = [ball(0.75, -1.2, 3.1, -0.2), rounded_box(0.9, 0.9, 0.9, 0.12, 4).rotate("y", 30).rotate("x", 20).translate(1.4, 3.15, 0.5)]
    blue = [ball(0.6, 0.5, 3.25, -0.7), rounded_box(0.8, 0.8, 0.8, 0.1, 4).rotate("z", 25).translate(-0.2, 3.2, 0.8)]
    yellow = [ball(0.5, 1.6, 3.1, -0.9), extrude(star(0.7, 0.3, 5), 0.25).rotate("x", -30).translate(-1.7, 3.6, 0.6)]
    hearts = [ball(0.55, 0.1, 3.5, 0.0), ball(0.4, -0.7, 3.05, -1.1)]
    return {
        "Chest": box_body,
        "Trim": trim,
        "Lid": lid,
        "PileRed": merge(*red),
        "PileBlue": merge(*blue),
        "PileYellow": merge(*yellow),
        "PilePink": merge(*hearts),
    }


PROPS = {
    "MessyMemoryShelf": shelf,
    "MessyMemoryBooth": booth,
    "MessyMemoryCurtain": curtain,
    "MessyMemorySmoke": smoke,
    "MessyMemoryTeddy": teddy,
    "MessyMemoryDuck": duck,
    "MessyMemoryRocket": rocket,
    "MessyMemoryRobot": robot,
    "MessyMemoryBall": beach_ball,
    "MessyMemoryTop": spinning_top,
    "MessyMemoryBlock": star_block,
    "MessyMemoryBoat": sailboat,
    "MessyMemoryToyBox": toy_box,
}

COLORS = {
    "Wood": (232, 182, 120),
    "Back": (255, 236, 205),
    "Trim": (170, 120, 210),
    "Legs": (200, 140, 90),
    "Knobs": (255, 215, 90),
    "Wall": (255, 238, 225),
    "Roof": (170, 120, 210),
    "Awning": (255, 120, 170),
    "Awning2": (255, 255, 255),
    "Post": (255, 120, 170),
    "Counter": (120, 200, 235),
    "CounterTop": (250, 245, 235),
    "Badges": (255, 215, 90),
    "Rod": (255, 205, 80),
    "Cloth": (210, 40, 70),
    "Puff": (240, 240, 245),
    "Fur": (190, 125, 70),
    "Snout": (240, 205, 160),
    "Face": (40, 30, 30),
    "Bow": (230, 50, 80),
    "Body": (255, 215, 50),
    "Beak": (255, 140, 30),
    "Nose": (230, 50, 60),
    "Window": (110, 200, 255),
    "Rim": (190, 195, 210),
    "Metal": (150, 185, 220),
    "Screen": (40, 50, 70),
    "Light": (255, 70, 70),
    "Eyes": (90, 240, 255),
    "Bolts": (255, 200, 60),
    "Red": (235, 60, 60),
    "White": (250, 250, 250),
    "Blue": (60, 130, 240),
    "Yellow": (255, 215, 50),
    "Band": (255, 120, 190),
    "Handle": (255, 205, 80),
    "Block": (90, 200, 110),
    "Star": (255, 225, 80),
    "Hull": (60, 120, 220),
    "Stripe": (255, 255, 255),
    "Mast": (190, 130, 80),
    "Sail": (255, 255, 250),
    "Flag": (235, 60, 60),
    "Chest": (255, 150, 190),
    "Lid": (255, 150, 190),
    "PileRed": (235, 70, 70),
    "PileBlue": (80, 150, 240),
    "PileYellow": (255, 215, 60),
    "PilePink": (190, 120, 240),
}
