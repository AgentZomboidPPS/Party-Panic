"""Meshes for Arrow Ambush: the archers' stone tower, the target boards that roll on rails in the
courtyard, the archer's bow and the arrow.

    python3 tools/meshgen/generate_meshes.py --only ArcherTower,TargetBoard,AmbushBow,AmbushArrow

Units are studs, +Y is up, the base sits on y = 0 and -Z is the front:
  * ArcherTower: the door looks along -Z (the game turns it to face the courtyard). The deck the
    archers stand on is at y = 16; the game puts an invisible solid core under it.
  * TargetBoard: the painted target looks along -Z (towards the tower). The board is 7.2 wide
    and centered on x = 0, z = 0; its wheels sit on two rails at z = +-0.9.
  * AmbushBow: held upright, the string towards the archer (+Z), shooting along -Z.
  * AmbushArrow: lies along Z with its head at -Z.
"""

import math
import random

import numpy as np

from generate_meshes import Mesh, cylinder, extrude, lathe, merge, rounded_box, sphere, taper, torus, tube

# ---------------------------------------------------------------------------- the tower

DECK = 16.0
BODY_R = 6.0


def body_radius(y: float) -> float:
    """The tower wall: a slight batter at the foot, straight above."""
    return BODY_R + 0.7 * max(0.0, 1 - y / 2.2) ** 2


def disc_z(radius: float, thickness: float, segments: int = 40) -> Mesh:
    """A flat disc facing -Z, its back at z = 0 and its front at z = -thickness."""
    return cylinder(radius, thickness, segments).rotate("x", -90)


def archer_tower():
    rnd = random.Random(7)
    wall = lathe([(0.0, 0.0), (body_radius(0), 0.0)] + [(body_radius(y), y) for y in np.linspace(0.0, 14.6, 16)]
                 + [(BODY_R + 0.1, 14.6), (BODY_R + 1.3, 15.95), (5.4, 15.95), (0.0, 15.95)], 48)

    # Stone blocks over the mortar, every other row offset by half a block.
    bricks = []
    row_h = 1.25
    rows = int(14.2 / row_h)
    for row in range(rows):
        y = 0.35 + row * row_h + row_h / 2
        radius = body_radius(y)
        count = 18
        for k in range(count):
            angle = 2 * math.pi * (k + (0.5 if row % 2 else 0.0) + rnd.uniform(-0.06, 0.06)) / count
            if row < 4 and abs(math.atan2(math.sin(angle + math.pi / 2), math.cos(angle + math.pi / 2))) < 0.35:
                continue  # leave room for the door (front, -Z)
            width = 2 * math.pi * radius / count - 0.22
            depth = 0.5 + rnd.uniform(-0.05, 0.08)
            brick = rounded_box(width, row_h - 0.2 + rnd.uniform(-0.05, 0.03), depth, 0.12, 2)
            brick.rotate("y", -math.degrees(angle) - 90)
            out = radius - depth / 2 + 0.14 + rnd.uniform(-0.02, 0.04)
            bricks.append(brick.translate(math.cos(angle) * out, y, math.sin(angle) * out))

    # The collar under the deck, its corbels, the parapet and the merlons.
    corbels = []
    for k in range(20):
        angle = 2 * math.pi * (k + 0.5) / 20
        corbel = rounded_box(0.7, 1.1, 0.9, 0.15, 2).rotate("y", -math.degrees(angle) - 90)
        corbels.append(corbel.translate(math.cos(angle) * (BODY_R + 0.35), 14.2, math.sin(angle) * (BODY_R + 0.35)))
    parapet = lathe([(6.55, 15.9), (7.35, 15.9), (7.35, 17.2), (6.55, 17.2), (6.55, 15.9)], 48)
    band = lathe([(7.32, 15.75), (7.55, 15.8), (7.6, 16.05), (7.55, 16.3), (7.32, 16.35)], 48)
    merlons = []
    for k in range(12):
        angle = 2 * math.pi * k / 12
        merlon = rounded_box(1.9, 1.35, 0.85, 0.2, 3).rotate("y", -math.degrees(angle) - 90)
        merlons.append(merlon.translate(math.cos(angle) * 6.95, 17.75, math.sin(angle) * 6.95))
    deck = cylinder(6.6, 0.12, 48).translate(0, 15.9, 0)
    planks = []
    for k in range(-5, 6):
        x = k * 1.18
        half = math.sqrt(max(0.0, 6.5 ** 2 - x ** 2)) - 0.1
        if half > 0.4:
            planks.append(rounded_box(1.06, 0.1, half * 2, 0.04, 1).translate(x, 16.0, 0))

    # The door at the foot (-Z): an arched wooden door in a stone frame, iron bands across it.
    door_poly = [(-1.4, 0.0), (1.4, 0.0)] + [(1.4 * math.cos(a), 3.4 + 1.4 * math.sin(a)) for a in np.linspace(0, math.pi, 14)]
    door = extrude(door_poly, 0.5).translate(0, 0.02, -(body_radius(1.5) - 0.05))
    frame = torus(1.65, 0.28, 20, 8, 180).rotate("x", -90).translate(0, 3.4, -(body_radius(3.0) + 0.02))
    jambs = [rounded_box(0.56, 3.4, 0.56, 0.12, 2).translate(sx * 1.65, 1.7, -(body_radius(1.7) + 0.02)) for sx in (-1, 1)]
    irons = [rounded_box(2.6, 0.18, 0.12, 0.05, 1).translate(0, y, -(body_radius(1.5) + 0.25)) for y in (1.0, 2.8)]
    knocker = torus(0.22, 0.05, 14, 6).rotate("x", 90).translate(0.7, 2.0, -(body_radius(2.0) + 0.32))

    # Arrow-slit windows on the sides and back.
    windows = []
    for angle_deg, y in ((0, 9.0), (180, 9.0), (90, 11.5), (45, 6.0), (135, 6.0)):
        angle = math.radians(angle_deg)
        slit = rounded_box(0.5, 2.0, 0.4, 0.2, 2).rotate("y", -angle_deg - 90)
        out = BODY_R + 0.12
        windows.append(slit.translate(math.cos(angle) * out, y, math.sin(angle) * out))

    # A pennant on a pole at the back corner.
    px, pz = -4.4, 4.4
    pole = merge(cylinder(0.14, 9.2, 12).translate(px, 16.0, pz), sphere(0.32, 8, 12).translate(px, 25.3, pz))
    flag_v, flag_f = [], []
    cols, rows_f = 14, 6
    normal = np.array([0.6, 0.0, -0.75]) / math.hypot(0.6, 0.75)
    for side in (1, -1):  # two sheets a hair apart, each facing out, so both sides shade cleanly
        start = len(flag_v)
        for i in range(cols + 1):
            u = i / cols
            for j in range(rows_f + 1):
                v = j / rows_f
                length = 4.2 * u
                height = 2.4 * (1 - u * 0.75) * (v - 0.5)
                point = np.array([px + length * 0.75, 24.2 + height, pz + length * 0.6 + 0.35 * math.sin(u * 5.0)])
                flag_v.append(tuple(point + normal * 0.03 * side))
        for i in range(cols):
            for j in range(rows_f):
                a = start + i * (rows_f + 1) + j
                b = a + rows_f + 1
                flag_f += [(a, b, a + 1), (a + 1, b, b + 1)] if side < 0 else [(a, a + 1, b), (a + 1, b + 1, b)]
    flag = Mesh(flag_v, flag_f)

    return {
        "Mortar": wall,
        "Stone": merge(*bricks, *corbels),
        "Trim": merge(parapet, band, *merlons, *jambs, frame),
        "Deck": merge(deck, *planks),
        "Wood": door,
        "Iron": merge(*irons, knocker),
        "Window": merge(*windows),
        "Pole": pole,
        "Flag": flag,
    }


# ---------------------------------------------------------------------------- the target board

BOARD_W = 7.2
BOARD_BOTTOM = 1.4
BOARD_TOP = 7.6


def target_board():
    # The cart: a plank platform on four wheels that run on the rails.
    cart = rounded_box(6.2, 0.45, 2.5, 0.12, 3).translate(0, 0.95, 0)
    wheels = []
    for x in (-2.3, 2.3):
        for z in (-0.9, 0.9):
            wheel = cylinder(0.5, 0.26, 18, 0.06).rotate("x", 90).translate(x, 0.55, z - 0.13 if z > 0 else z + 0.13)
            wheels.append(wheel.translate(0, 0, 0))
    hubs = [cylinder(0.16, 0.34, 10).rotate("x", 90).translate(x, 0.55, z - 0.17 if z > 0 else z + 0.17)
            for x in (-2.3, 2.3) for z in (-0.9, 0.9)]
    axles = [cylinder(0.08, 1.9, 8).rotate("x", 90).translate(x, 0.55, -0.95) for x in (-2.3, 2.3)]

    # Posts and braces holding the board up.
    posts = [rounded_box(0.42, BOARD_BOTTOM + 0.6, 0.42, 0.1, 2).translate(x, 1.1 + (BOARD_BOTTOM + 0.6) / 2 - 0.3, 0.45)
             for x in (-2.4, 2.4)]
    braces = [tube([(x, 1.15, 1.1), (x, 2.4, 0.42)], 0.12, 8) for x in (-2.4, 2.4)]

    # The board: three planks with a frame, iron corner caps.
    height = BOARD_TOP - BOARD_BOTTOM
    planks = [rounded_box(BOARD_W / 3 - 0.08, height - 0.2, 0.42, 0.08, 2).translate(x, BOARD_BOTTOM + height / 2, 0.05)
              for x in (-BOARD_W / 3, 0.0, BOARD_W / 3)]
    frame = [
        rounded_box(BOARD_W + 0.2, 0.36, 0.56, 0.1, 2).translate(0, BOARD_TOP - 0.1, 0.05),
        rounded_box(BOARD_W + 0.2, 0.36, 0.56, 0.1, 2).translate(0, BOARD_BOTTOM + 0.1, 0.05),
        rounded_box(0.36, height, 0.56, 0.1, 2).translate(-BOARD_W / 2, BOARD_BOTTOM + height / 2, 0.05),
        rounded_box(0.36, height, 0.56, 0.1, 2).translate(BOARD_W / 2, BOARD_BOTTOM + height / 2, 0.05),
    ]
    caps = [rounded_box(0.7, 0.7, 0.66, 0.12, 2).translate(sx * BOARD_W / 2, y, 0.05)
            for sx in (-1, 1) for y in (BOARD_BOTTOM + 0.1, BOARD_TOP - 0.1)]
    studs = [sphere(0.1, 5, 8).translate(sx * BOARD_W / 2, y, -0.28) for sx in (-1, 1) for y in (BOARD_BOTTOM + 0.1, BOARD_TOP - 0.1)]

    # The painted target, each ring a touch further out than the one behind it (never coplanar).
    cy = BOARD_BOTTOM + height / 2
    front = -0.17
    face = disc_z(2.85, 0.06, 48).translate(0, cy, front)
    ring_red = merge(
        lathe([(2.3, 0), (2.85, 0), (2.85, 0.03), (2.3, 0.03)], 48).rotate("x", -90).translate(0, cy, front - 0.06),
        lathe([(1.2, 0), (1.75, 0), (1.75, 0.03), (1.2, 0.03)], 48).rotate("x", -90).translate(0, cy, front - 0.06),
    )
    bull = disc_z(0.62, 0.1, 32).translate(0, cy, front - 0.04)
    rim = torus(2.9, 0.09, 48, 8).rotate("x", 90).translate(0, cy, front - 0.03)
    return {
        "Wood": merge(cart, *posts, *braces, *planks),
        "Frame": merge(*frame),
        "Iron": merge(*caps, *studs, *hubs, *axles),
        "Wheels": merge(*wheels),
        "Face": face,
        "Rings": ring_red,
        "Bull": bull,
        "Rim": rim,
    }


# ---------------------------------------------------------------------------- the bow and the arrow

def bow_curve(y: float) -> float:
    """z of the bow's limb at height y (y in -1..1): the back bulges forward (-Z), the tips recurve."""
    a = abs(y)
    bulge = -0.62 * (1 - a ** 2)
    recurve = 0.3 * max(0.0, (a - 0.78) / 0.22) ** 2
    return bulge + recurve


def ambush_bow():
    half = 2.3
    ys = np.linspace(-1.0, 1.0, 29)
    upper = [(0.0, half + y * half, bow_curve(y)) for y in ys if y >= 0]
    lower = [(0.0, half + y * half, bow_curve(y)) for y in ys if y <= 0][::-1]
    limbs = merge(taper(upper, 0.17, 0.065, 10), taper(lower, 0.17, 0.065, 10))
    grip = merge(
        rounded_box(0.38, 1.1, 0.46, 0.17, 3).translate(0, half, bow_curve(0.0) + 0.02),
        torus(0.21, 0.05, 16, 6).translate(0, half + 0.55, bow_curve(0.0)),
        torus(0.21, 0.05, 16, 6).translate(0, half - 0.55, bow_curve(0.0)),
    )
    tip_top = (0.0, half * 2, bow_curve(1.0))
    tip_bottom = (0.0, 0.0, bow_curve(-1.0))
    string = tube([tip_bottom, (0.0, half, 0.16), tip_top], 0.028, 6)
    tips = merge(sphere(0.12, 6, 10).translate(*tip_top), sphere(0.12, 6, 10).translate(*tip_bottom))
    mesh = {"Limbs": limbs, "Grip": grip, "String": string, "Tips": tips}
    lowest = min(float(m.v[:, 1].min()) for m in mesh.values())
    for m in mesh.values():
        m.translate(0, -lowest, 0)
    return mesh


def ambush_arrow():
    shaft = cylinder(0.075, 3.6, 10).rotate("x", 90).translate(0, 0, -1.6)  # z from -1.6 to 2.0
    head = lathe([(0.0, 0.0), (0.08, 0.02), (0.27, 0.2), (0.12, 0.5), (0.0, 0.78)], 4).rotate("x", -90).translate(0, 0, -1.55)
    collar = cylinder(0.1, 0.12, 10).rotate("x", 90).translate(0, 0, -1.62)
    vanes = []
    for k in range(3):
        poly = [(0.0, 0.0), (0.0, 1.0), (0.3, 0.75), (0.3, 0.15)]
        vane = extrude([(y, x) for x, y in poly], 0.03)  # x = along shaft, y = out from it
        vane.rotate("y", -90)  # extrude's thickness onto x, the vane in the YZ plane
        vane.translate(0, 0.06, 0.95)
        vane.rotate("z", 120 * k)
        vanes.append(vane)
    nock = sphere(0.1, 6, 8).translate(0, 0, 2.02)
    mesh = {"Shaft": shaft, "Head": merge(head, collar), "Fletching": merge(*vanes), "Nock": nock}
    lowest = min(float(m.v[:, 1].min()) for m in mesh.values())
    for m in mesh.values():
        m.translate(0, -lowest, 0)
    return mesh


PROPS = {
    "ArcherTower": archer_tower,
    "TargetBoard": target_board,
    "AmbushBow": ambush_bow,
    "AmbushArrow": ambush_arrow,
}
COLORS = {
    "Mortar": (150, 140, 132),
    "Stone": (206, 196, 182),
    "Trim": (226, 216, 200),
    "Deck": (170, 120, 80),
    "Wood": (150, 100, 62),
    "Iron": (70, 70, 80),
    "Window": (40, 34, 40),
    "Pole": (255, 205, 80),
    "Flag": (255, 120, 60),
    "Frame": (120, 80, 50),
    "Wheels": (90, 64, 44),
    "Face": (250, 246, 236),
    "Rings": (230, 60, 60),
    "Bull": (255, 205, 60),
    "Rim": (60, 60, 70),
    "Limbs": (150, 95, 55),
    "Grip": (90, 50, 40),
    "String": (245, 240, 225),
    "Tips": (255, 205, 80),
    "Shaft": (205, 160, 110),
    "Head": (170, 180, 195),
    "Fletching": (255, 110, 60),
    "Nock": (255, 205, 80),
}
