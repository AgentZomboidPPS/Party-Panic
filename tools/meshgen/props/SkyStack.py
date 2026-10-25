"""Props for Sky Stack: a tower's stone base, the golden star waiting at the cloud line, the clouds and
the tower cranes at both ends of the row.

    python3 tools/meshgen/generate_meshes.py --only SkyStackBase,SkyStackStar,SkyStackCloud,SkyStackCrane

Units are studs, +Y is up, the base sits on y = 0 and -Z is the front:
  * SkyStackBase: a two-step stone plinth with carved blocks, a band in the lane's color (Trim) and a
    pale Top plate. The plate's top face is at y = 3.0 (the mode's BASE_TOP) and 8 x 8 studs inside its
    lip: floor 1 (Logic/SkyStack.FULL) sits right on it. Nothing rises above y = 3.
  * SkyStackStar: a puffy smiling star facing -Z with a ring in the lane's color (Ribbon) round its
    feet; its top point is the prop's top (3.4).
  * SkyStackCloud: soft puffs on a flat, slightly blue underside (Shade), 4 studs tall.
  * SkyStackCrane: a tower crane: a lattice mast on a concrete footing, the cab, a lattice jib reaching
    40 studs toward -Z with the hook hanging from its trolley, the counter-jib and its weights, and an
    apex with tie cables. 64 studs tall.
"""

import math

import numpy as np

from generate_meshes import Mesh, icosphere, merge, rounded_box, sphere, star, torus, tube


def box(cx: float, cy: float, cz: float, sx: float, sy: float, sz: float, r: float = 0.08) -> Mesh:
    """A rounded box centered at (cx, cy, cz)."""
    return rounded_box(sx, sy, sz, r, 4).translate(cx, cy, cz)


# ---------------------------------------------------------------------------- the tower base

BASE_TOP = 3.0


def base():
    foot = box(0, 0.3, 0, 10.4, 0.6, 10.4, 0.18)
    body = box(0, 1.45, 0, 9.5, 1.8, 9.5, 0.2)
    # Carved stone blocks proud of the body on every side, two courses with staggered joints.
    blocks = []
    for y, offset in ((0.95, 0.0), (1.95, 1.05)):
        for side in range(4):
            for i in range(-2, 3):
                along = i * 2.1 + offset
                if abs(along) > 3.7:
                    continue
                width = 1.95
                if side % 2 == 0:
                    blocks.append(box(along, y, (1 if side == 0 else -1) * 4.8, width, 0.86, 0.22, 0.07))
                else:
                    blocks.append(box((1 if side == 1 else -1) * 4.8, y, along, 0.22, 0.86, width, 0.07))
    # Corner posts under the plate.
    posts = []
    for sx in (-1, 1):
        for sz in (-1, 1):
            posts.append(box(sx * 4.75, 1.45, sz * 4.75, 0.8, 1.9, 0.8, 0.12))
    trim = merge(
        box(0, 1.45, 0, 9.85, 0.32, 9.85, 0.1),
        *[sphere(0.22, 6, 10).scale(1, 0.7, 1).translate(sx * 4.75, 1.45, sz * 4.75 + sz * 0.42)
          for sx in (-1, 1) for sz in (-1, 1)],
    )
    plate = box(0, BASE_TOP - 0.28, 0, 8.5, 0.56, 8.5, 0.12)
    lip = box(0, BASE_TOP - 0.62, 0, 9.0, 0.16, 9.0, 0.06)
    return {
        "Dark": merge(foot, lip),
        "Stone": merge(body, *blocks, *posts),
        "Trim": trim,
        "Top": plate,
    }


# ---------------------------------------------------------------------------- the star at the cloud line

STAR_CENTER = 1.95
STAR_OUTER = 1.45


STAR_DEPTH = 0.5  # half its thickness at the middle


def puffy_star() -> Mesh:
    """A soft, pillowy five-point star in the XY plane, facing -Z: its outline (each edge split into
    steps) shrinks toward the middle in rings that bulge out front and back, like a stuffed cushion."""
    corners = star(STAR_OUTER, STAR_OUTER * 0.5, 5)
    outline = []
    steps = 4
    for i, (x0, y0) in enumerate(corners):
        x1, y1 = corners[(i + 1) % len(corners)]
        for k in range(steps):
            t = k / steps
            outline.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t))
    n = len(outline)
    rings = 7
    verts = []
    # Ring 0 is the rim; rings 1..rings-1 go toward the front middle (z < 0), then the back middle.
    for side in (-1, 1):
        for r in range(1, rings):
            angle = math.pi / 2 * r / rings
            shrink = math.cos(angle) ** 0.7
            z = side * STAR_DEPTH * math.sin(angle)
            for x, y in outline:
                verts.append((x * shrink, y * shrink + STAR_CENTER, z))
    rim = len(verts)
    for x, y in outline:
        verts.append((x, y + STAR_CENTER, 0.0))
    front_tip, back_tip = len(verts), len(verts) + 1
    verts.append((0.0, STAR_CENTER, -STAR_DEPTH))
    verts.append((0.0, STAR_CENTER, STAR_DEPTH))

    def ring(side: int, r: int) -> int:
        if r == 0:
            return rim
        return (0 if side < 0 else (rings - 1) * n) + (r - 1) * n

    faces = []
    for side, tip in ((-1, front_tip), (1, back_tip)):
        for r in range(rings - 1):
            a, b = ring(side, r), ring(side, r + 1)
            for i in range(n):
                j = (i + 1) % n
                faces += [(a + i, a + j, b + i), (a + j, b + j, b + i)]
        last = ring(side, rings - 1)
        for i in range(n):
            faces.append((last + i, last + (i + 1) % n, tip))
    return Mesh(verts, faces)


def star_prop():
    body = puffy_star()
    front = -STAR_DEPTH  # the cushion's front, at its middle (it falls away a little from there)
    eyes = [sphere(0.13, 6, 10).scale(0.8, 1.25, 1.0).translate(side * 0.3, STAR_CENTER + 0.18, front + 0.02)
            for side in (-1, 1)]
    smile = torus(0.24, 0.055, 16, 6, 160).rotate("x", 90).rotate("z", -10).translate(0, STAR_CENTER - 0.1, front - 0.03)
    cheeks = [sphere(0.12, 6, 10).scale(1.2, 0.8, 0.9).translate(side * 0.5, STAR_CENTER - 0.06, front + 0.05)
              for side in (-1, 1)]
    ring = torus(0.95, 0.11, 32, 8).scale(1, 0.7, 1).translate(0, 0.32, 0)
    bow = [sphere(0.22, 6, 10).scale(1.3, 0.8, 0.6).translate(side * 0.3, 0.32, -0.95) for side in (-1, 1)]
    return {
        "Star": body,
        "Face": merge(*eyes, smile),
        "Cheeks": merge(*cheeks),
        "Ribbon": merge(ring, *bow),
    }


# ---------------------------------------------------------------------------- clouds

def cloud():
    rng = np.random.default_rng(7)
    puffs = []
    spots = [(-3.2, 1.6, 0.2, 1.7), (-1.2, 2.2, -0.3, 2.1), (1.1, 2.4, 0.4, 2.2), (3.1, 1.8, -0.2, 1.7),
             (0.0, 1.4, 1.2, 1.6), (-0.4, 1.4, -1.4, 1.5), (2.2, 1.3, 1.3, 1.3), (-2.4, 1.2, -1.2, 1.3)]
    for i, (x, y, z, r) in enumerate(spots):
        puff = icosphere(r, 2, noise=0.05, seed=int(rng.integers(0, 1000)) + i)
        puffs.append(puff.translate(x, y, z))
    body = merge(*puffs)
    # Flatten everything under the cloud's belly onto it.
    body.v[:, 1] = np.maximum(body.v[:, 1], 0.55)
    belly = icosphere(1.0, 2).scale(4.6, 0.55, 2.3).translate(0, 0.55, 0)
    belly.v[:, 1] = np.maximum(belly.v[:, 1], 0.0)
    return {"Cloud": body, "Shade": belly}


# ---------------------------------------------------------------------------- the tower crane

MAST_TOP = 56.0
MAST_HALF = 1.1
JIB_Y = 59.2
JIB_LENGTH = 40.0
COUNTER_LENGTH = 12.0
TOTAL = 64.0
R = 0.11  # lattice tube radius


def rod(a, b, radius: float = R) -> Mesh:
    return tube([a, b], radius, 6)


def mast() -> Mesh:
    rods = []
    corners = [(-MAST_HALF, -MAST_HALF), (MAST_HALF, -MAST_HALF), (MAST_HALF, MAST_HALF), (-MAST_HALF, MAST_HALF)]
    for x, z in corners:
        rods.append(rod((x, 1.0, z), (x, MAST_TOP, z), 0.16))
    step = 2.2
    y = 1.0
    flip = 1
    while y + step <= MAST_TOP + 1e-6:
        for i in range(4):
            (x0, z0), (x1, z1) = corners[i], corners[(i + 1) % 4]
            low, high = (x0, y, z0), (x1, y + step, z1)
            if flip < 0:
                low, high = (x1, y, z1), (x0, y + step, z0)
            rods.append(rod(low, high))
            rods.append(rod((x0, y, z0), (x1, y, z1)))
        flip = -flip
        y += step
    for i in range(4):
        (x0, z0), (x1, z1) = corners[i], corners[(i + 1) % 4]
        rods.append(rod((x0, MAST_TOP, z0), (x1, MAST_TOP, z1)))
    return merge(*rods)


def jib() -> Mesh:
    """A triangular lattice along -Z (two bottom chords and a top chord) plus the counter-jib along +Z."""
    rods = []
    half = 0.8
    top = 1.3
    z_end = -JIB_LENGTH
    bottoms = [(-half, JIB_Y), (half, JIB_Y)]
    for x, y in bottoms:
        rods.append(rod((x, y, 1.2), (x, y, z_end), 0.13))
    rods.append(rod((0, JIB_Y + top, 1.2), (0, JIB_Y + top, z_end + 1), 0.13))
    z = 1.2
    step = 2.0
    while z - step >= z_end - 1e-6:
        for x, y in bottoms:
            rods.append(rod((x, y, z), (0, JIB_Y + top, z - step / 2)))
            rods.append(rod((0, JIB_Y + top, z - step / 2), (x, y, z - step)))
        rods.append(rod((-half, JIB_Y, z), (half, JIB_Y, z)))
        z -= step
    rods.append(rod((-half, JIB_Y, z_end), (half, JIB_Y, z_end)))
    # The counter-jib: a flat walkway frame along +Z.
    for x in (-half, half):
        rods.append(rod((x, JIB_Y, 1.2), (x, JIB_Y, COUNTER_LENGTH), 0.13))
    zz = 1.2
    while zz < COUNTER_LENGTH:
        rods.append(rod((-half, JIB_Y, zz), (half, JIB_Y, zz)))
        zz += 1.8
    # The slewing deck on top of the mast.
    deck = box(0, MAST_TOP + 0.5, 0, 3.2, 0.8, 3.2, 0.12)
    return merge(*rods, deck)


def apex() -> Mesh:
    """An A-frame over the mast that the tie cables hang from."""
    tip = (0, TOTAL - 0.35, 0)
    legs = [rod((x, JIB_Y, z), tip, 0.15) for x in (-0.9, 0.9) for z in (-0.9, 0.9)]
    knob = sphere(0.35, 8, 12).translate(0, TOTAL - 0.35, 0)
    return merge(*legs, knob)


def hook(z: float):
    trolley = box(0, JIB_Y - 0.35, z, 1.9, 0.5, 1.4, 0.1)
    cable_top = JIB_Y - 0.6
    cable_bottom = 44.6
    cables = [rod((side * 0.25, cable_top, z), (side * 0.25, cable_bottom + 0.6, z), 0.05) for side in (-1, 1)]
    block = box(0, cable_bottom, z, 0.9, 1.3, 0.55, 0.15)
    curl = torus(0.42, 0.13, 20, 8, 270).rotate("x", 90).rotate("z", 45).translate(0, cable_bottom - 1.15, z)
    return trolley, merge(*cables), merge(block, curl)


def crane():
    footing = merge(box(0, 0.5, 0, 6.0, 1.0, 6.0, 0.2), *[box(sx * 2.6, 1.15, sz * 2.6, 0.7, 0.3, 0.7, 0.08)
                                                          for sx in (-1, 1) for sz in (-1, 1)])
    cab = box(1.6, MAST_TOP + 2.2, -1.3, 2.4, 2.6, 2.4, 0.25)
    glass = merge(box(1.6, MAST_TOP + 2.5, -2.52, 2.0, 1.4, 0.08, 0.03),
                  box(2.82, MAST_TOP + 2.5, -1.3, 0.08, 1.4, 1.8, 0.03))
    counter = merge(*[box(0, JIB_Y - 1.1, COUNTER_LENGTH - 1.0 - i * 1.25, 2.2, 2.0, 1.1, 0.12) for i in range(3)])
    trolley, cable, hook_part = hook(-30.0)
    ties = merge(
        rod((0, TOTAL - 0.4, 0), (0, JIB_Y + 1.3, -JIB_LENGTH * 0.62), 0.06),
        rod((0, TOTAL - 0.4, 0), (0, JIB_Y + 0.1, COUNTER_LENGTH - 0.6), 0.06),
    )
    return {
        "Footing": footing,
        "Mast": merge(mast(), apex()),
        "Jib": merge(jib(), trolley),
        "Cab": cab,
        "Glass": glass,
        "Counter": counter,
        "Cable": merge(cable, ties),
        "Hook": hook_part,
    }


PROPS = {
    "SkyStackBase": base,
    "SkyStackStar": star_prop,
    "SkyStackCloud": cloud,
    "SkyStackCrane": crane,
}
COLORS = {
    "Stone": (214, 204, 186),
    "Dark": (150, 140, 126),
    "Trim": (70, 150, 255),
    "Top": (246, 242, 232),
    "Star": (255, 212, 70),
    "Face": (70, 50, 40),
    "Cheeks": (255, 150, 120),
    "Ribbon": (70, 150, 255),
    "Cloud": (255, 255, 255),
    "Shade": (220, 232, 250),
    "Mast": (255, 196, 40),
    "Jib": (255, 196, 40),
    "Cab": (245, 245, 240),
    "Glass": (110, 170, 220),
    "Counter": (150, 150, 150),
    "Cable": (60, 62, 70),
    "Hook": (230, 70, 60),
    "Footing": (120, 120, 126),
}
