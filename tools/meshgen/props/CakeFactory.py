"""Props for Cake Factory: the cake layers the machines build (plate, sponge, cream, strawberry), the
conveyor belt, the three station machines, the plate stacker, the packing machine, boxes, the bin
and the giant decorations (a tiered cake, a stand mixer and cupcakes).

Units are studs, +Y is up, every prop stands on y = 0 and its front faces -Z. The station machines
straddle a belt that runs along X: their legs stand at z = +-3.1 and their business end (stamp,
nozzle, chute) hangs over the belt's middle. Pieces named Stripe take the team color in game.
"""

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
    sphere,
    star,
    taper,
    torus,
    tube,
    weld,
)

# ------------------------------------------------------------------ shared measurements
# The client stacks layers with these, so keep them in step with Props/CakeFactory.luau.
PLATE_TOP = 0.2  # where a sponge sits on the plate
SPONGE_HEIGHT = 1.25
CREAM_SINK = 0.25  # the cream's rim hangs this far down the sponge's side
CREAM_SEAT = 0.55  # height of the cream's top in the middle (where a strawberry sits)
LEG_Z = 3.1  # station machine legs, either side of the belt


# ------------------------------------------------------------------ helpers

def wavy_lathe(profile, segments, waves, amount, start=0.0):
    """A lathe whose rings bulge in and out `waves` times around (scalloped plates, doilies, wrappers).
    Rings whose radius is under `start` stay round."""
    mesh = lathe(profile, segments)
    angle = np.arctan2(mesh.v[:, 2], mesh.v[:, 0])
    radius = np.hypot(mesh.v[:, 0], mesh.v[:, 2])
    factor = np.where(radius > start, 1 + amount * np.cos(angle * waves), 1.0)
    mesh.v[:, 0] *= factor
    mesh.v[:, 2] *= factor
    return mesh


def rosette(radius, height, points=8, turns=0.9, rings=18, segments=40, depth=0.2):
    """Frosting piped through a star tip: a ridged dollop that narrows and twists to a soft point."""
    verts, faces = [], []
    for i in range(rings + 1):
        t = i / rings
        r = radius * max(0.0, 1 - t ** 1.7) ** 0.7 * (1 + 0.1 * math.sin(math.pi * t))
        y = height * t
        twist = turns * 2 * math.pi * t
        for j in range(segments):
            a = 2 * math.pi * j / segments
            m = 1 + depth * (1 - t) * math.cos(points * a + twist)
            verts.append((math.cos(a) * r * m, y, math.sin(a) * r * m))
    for i in range(rings):
        for j in range(segments):
            a = i * segments + j
            b = i * segments + (j + 1) % segments
            faces += [(a, a + segments, b), (b, a + segments, b + segments)]
    center = len(verts)
    verts.append((0.0, 0.0, 0.0))
    faces += [(center, j, (j + 1) % segments) for j in range(segments)]
    return weld(Mesh(verts, faces))


def coil(radius, height, turns, thickness, points=140, sides=12):
    """Soft-serve frosting: a fat tube spiralling up a cone to a curl on top."""
    path = []
    for i in range(points + 1):
        t = i / points
        a = 2 * math.pi * turns * t
        r = radius * (1 - t) ** 0.9
        path.append((math.cos(a) * r, height * t ** 0.92, math.sin(a) * r))
    mesh = taper(path, thickness, thickness * 0.35, sides)
    mesh.smooth = True
    return mesh


def profile_radius(profile, y):
    """Radius of a (radius, y) lathe profile at height y (profiles here rise monotonically)."""
    for (r0, y0), (r1, y1) in zip(profile, profile[1:]):
        if y0 <= y <= y1 and y1 > y0:
            return r0 + (r1 - r0) * (y - y0) / (y1 - y0)
    return 0.0


def eyes(center_x, y, z, spread, size, look=(0.0, -0.05)):
    """A pair of cartoon eyes on a -Z facing surface: white balls with dark pupils and a glint."""
    whites, pupils = [], []
    for side in (-1, 1):
        x = center_x + side * spread
        whites.append(sphere(size, 12, 18).scale(1.0, 1.15, 0.55).translate(x, y, z))
        px, py = x + look[0] * size, y + look[1] * size
        pupils.append(sphere(size * 0.52, 10, 14).scale(1.0, 1.1, 0.5).translate(px, py, z - size * 0.36))
        pupils.append(sphere(size * 0.15, 6, 8).translate(px + size * 0.18, py + size * 0.22, z - size * 0.58))
    return merge(*whites), merge(*pupils)


def legs(height, width=1.0, depth=1.5):
    """The two legs every station machine stands on, either side of the belt, with feet."""
    parts = []
    for side in (-1, 1):
        parts.append(rounded_box(width, height, depth, 0.35).translate(0, height / 2, side * LEG_Z))
        parts.append(rounded_box(width + 0.9, 0.45, depth + 0.7, 0.2).translate(0, 0.225, side * LEG_Z))
    return merge(*parts)


def bolts(points, radius=0.13):
    return merge(*(sphere(radius, 6, 10).scale(1, 1, 0.6).translate(*p) for p in points))


def strawberry_pieces(seed=0, seeds=True):
    """A cartoon strawberry standing point-up on a collar of leaves (about 1.15 tall)."""
    profile = [(0.0, 0.1), (0.3, 0.06), (0.48, 0.16), (0.56, 0.34), (0.54, 0.55), (0.45, 0.78), (0.31, 0.97),
               (0.15, 1.1), (0.0, 1.15)]
    body = lathe(profile, 28)
    rng = np.random.default_rng(seed)
    angle = np.arctan2(body.v[:, 2], body.v[:, 0])
    wobble = 1 + 0.035 * np.sin(angle * 3 + rng.uniform(0, 6)) + 0.02 * np.sin(angle * 5 + 1.3)
    body.v[:, 0] *= wobble
    body.v[:, 2] *= wobble
    dots = []
    if seeds:
        for row in range(6):
            y = 0.3 + row * 0.13
            r = profile_radius(profile, y)
            count = max(4, int(r * 13))
            for k in range(count):
                a = 2 * math.pi * (k + 0.5 * (row % 2)) / count
                normal = np.array([math.cos(a), 0.25, math.sin(a)])
                p = np.array([math.cos(a) * r, y, math.sin(a) * r]) + normal * 0.012
                dots.append(icosphere(0.034, 0).scale(1, 1.5, 1).translate(*p))
    leaf = extrude(star(0.62, 0.2, 6), 0.05).rotate("x", 90)
    leaf.v[:, 1] -= 0.18 * (leaf.v[:, 0] ** 2 + leaf.v[:, 2] ** 2)
    leaf.translate(0, 0.16, 0)
    nub = cylinder(0.08, 0.22, 8).translate(0, 0.05, 0)
    return body, (merge(*dots) if dots else None), merge(leaf, nub)


def berry_at(seed, x, y, z, scale=1.0, tilt=0.0, turn=0.0):
    body, dots, leaves = strawberry_pieces(seed, seeds=False)

    def place(m):
        return m.scale(scale).rotate("z", tilt).rotate("y", turn).translate(x, y, z)

    return place(body), place(leaves)


# ------------------------------------------------------------------ cake layers

def cake_plate():
    """A white plate with a raised rim and a lacy paper doily (4.2 across). Cakes sit at y = 0.2."""
    plate = lathe([(0.0, 0.06), (1.2, 0.06), (1.28, 0.0), (1.45, 0.0), (1.52, 0.07), (1.92, 0.15), (2.08, 0.27),
                   (2.1, 0.34), (2.04, 0.37), (1.98, 0.35), (1.86, 0.2), (1.8, 0.17), (0.0, 0.17)], 48)
    doily = wavy_lathe([(0.0, 0.172), (1.78, 0.172), (1.8, 0.186), (1.78, 0.2), (0.0, 0.2)], 96, 18, 0.045, 1.2)
    holes = []
    for k in range(18):
        a = 2 * math.pi * (k + 0.5) / 18
        holes.append(cylinder(0.075, 0.012, 8).translate(math.cos(a) * 1.58, 0.2, math.sin(a) * 1.58))
    return {"Plate": plate, "Doily": merge(doily, *holes)}


def cake_sponge():
    """A round sponge: two golden halves with a line of cream filling between them."""
    profile = [(0.0, 0.0), (1.42, 0.0), (1.55, 0.05), (1.6, 0.17), (1.6, 0.5), (1.55, 0.58), (1.52, 0.625),
               (1.55, 0.67), (1.6, 0.75), (1.6, 1.07), (1.55, 1.18), (1.42, 1.235), (0.7, 1.25), (0.0, 1.25)]
    body = lathe(profile, 48)
    angle = np.arctan2(body.v[:, 2], body.v[:, 0])
    body.v[:, 0] *= 1 + 0.008 * np.sin(angle * 7)
    body.v[:, 2] *= 1 + 0.008 * np.sin(angle * 7)
    filling = torus(1.53, 0.085, 64, 10).translate(0, 0.625, 0)
    return {"Sponge": body, "Filling": filling}


def cake_cream():
    """The frosting: a soft cap whose rim hangs over the sponge's edge in drips, a ring of piped
    rosettes and sprinkles. It sits CREAM_SINK below the sponge top; its middle is CREAM_SEAT high."""
    cap = lathe([(0.0, 0.25), (1.45, 0.25), (1.58, 0.2), (1.64, 0.08), (1.69, 0.02), (1.73, 0.08), (1.74, 0.3),
                 (1.68, 0.45), (1.52, 0.53), (0.9, 0.55), (0.0, CREAM_SEAT)], 64)
    rng = np.random.default_rng(3)
    drips = []
    for k in range(14):
        a = 2 * math.pi * k / 14 + rng.uniform(-0.12, 0.12)
        length = rng.uniform(0.14, 0.32)
        drips.append(capsule(length + 0.22, 0.11, 10).translate(math.cos(a) * 1.71, 0.12 - length / 2,
                                                                 math.sin(a) * 1.71))
    shift = 0.24  # the longest drip hangs down to about -0.2: lift everything onto y = 0
    rosettes = [rosette(0.3, 0.42, 7, 0.8).rotate("y", k * 31).translate(math.cos(a) * 1.2, CREAM_SEAT - 0.04,
                                                                           math.sin(a) * 1.2)
                for k, a in enumerate(np.linspace(0, 2 * math.pi, 9, endpoint=False))]
    cream = merge(cap, *drips, *rosettes).translate(0, shift, 0)
    sprinkles = {"SprinklesA": [], "SprinklesB": [], "SprinklesC": []}
    names = list(sprinkles)
    for k in range(30):
        r = math.sqrt(rng.uniform(0.05, 0.75)) * 1.05
        a = rng.uniform(0, 2 * math.pi)
        if r < 0.45:
            continue  # the middle is where the strawberry goes
        bit = capsule(0.2, 0.035, 6).rotate("z", 90).rotate("y", rng.uniform(0, 180))
        bit.translate(math.cos(a) * r, CREAM_SEAT + shift + 0.01, math.sin(a) * r)
        sprinkles[names[k % 3]].append(bit)
    pieces = {"Cream": cream}
    for name, bits in sprinkles.items():
        pieces[name] = merge(*bits)
    return pieces


def cake_berry():
    """The strawberry on top."""
    body, dots, leaves = strawberry_pieces(1)
    return {"Berry": body, "Seeds": dots, "BerryLeaves": leaves}


# ------------------------------------------------------------------ line pieces

def cake_box():
    """A pastry box with a window and a ribbon bow: big enough to drop over a finished cake."""
    w, h = 4.5, 4.0
    box = rounded_box(w, h, w, 0.35, 6).translate(0, h / 2, 0)
    lid = rounded_box(w + 0.16, 0.5, w + 0.16, 0.2, 4).translate(0, h - 0.2, 0)
    window = rounded_box(2.4, 1.5, 0.08, 0.2, 4).translate(0, 2.0, -w / 2 - 0.02)
    ribbon = [rounded_box(0.5, h + 0.12, w + 0.24, 0.12, 3).translate(0, h / 2 + 0.03, 0),
              rounded_box(w + 0.24, h + 0.12, 0.5, 0.12, 3).translate(0, h / 2 + 0.03, 0)]
    for side in (-1, 1):
        loop = torus(0.55, 0.16, 24, 8).scale(1.0, 1.0, 0.55).rotate("x", 90).rotate("z", side * 30)
        ribbon.append(loop.translate(side * 0.6, h + 0.55, 0))
    ribbon.append(sphere(0.3, 10, 12).translate(0, h + 0.32, 0))
    for side in (-1, 1):
        ribbon.append(tube([(side * 0.15, h + 0.25, 0), (side * 0.55, h + 0.15, -0.5), (side * 0.75, h + 0.05, -0.9)],
                           0.11, 6))
    return {"Box": merge(box, lid), "Window": window, "Stripe": merge(*ribbon)}


def cake_bin():
    """The bin wonky cakes are knocked into: a round can with its lid flipped open."""
    can = lathe([(0.0, 0.0), (1.55, 0.0), (1.7, 0.12), (1.95, 3.0), (2.0, 3.15), (1.88, 3.15), (1.83, 3.0),
                 (1.6, 0.3), (0.0, 0.3)], 40)
    rim = torus(1.96, 0.13, 40, 8).translate(0, 3.17, 0)
    bands = [torus(1.6 + 0.29 * t, 0.07, 40, 6).translate(0, 0.6 + t * 2.0, 0) for t in (0.2, 0.75)]
    lid = lathe([(0.0, 0.0), (2.05, 0.0), (2.08, 0.1), (1.6, 0.35), (0.0, 0.42)], 40)
    lid = merge(lid, capsule(0.9, 0.16, 8).rotate("z", 90).translate(0, 0.55, 0))
    lid.rotate("x", -75).translate(0, 3.3 + 0.2, 2.05 + 0.25)
    hinge = cylinder(0.14, 0.6, 8).rotate("z", 90).translate(0.3, 3.25, 2.0)
    return {"Bin": can, "Rim": merge(rim, hinge), "Stripe": merge(*bands), "Lid": lid}


def cake_belt():
    """The conveyor: 44 long (x 0..44), a dark rubber belt on rollers between team-colored side
    rails on legs. "Cleats" (ribs on the belt, one spare rib-spacing long) slide to show it moving."""
    length, width, top = 44.0, 4.6, 3.2
    belt = rounded_box(length, 0.32, width - 0.2, 0.15, 4).translate(length / 2, top - 0.16, 0)
    drums = [cylinder(0.34, width - 0.3, 20).rotate("x", 90).translate(x, top - 0.3, (width - 0.3) / 2)
             for x in (0.25, length - 0.25)]
    rails = []
    for side in (-1, 1):
        z = side * (width / 2 + 0.18)
        rails.append(rounded_box(length + 0.4, 0.75, 0.42, 0.18, 4).translate(length / 2, top - 0.02, z))
    frame = []
    for x in np.linspace(2.0, length - 2.0, 6):
        for side in (-1, 1):
            z = side * (width / 2 - 0.1)
            frame.append(rounded_box(0.55, top - 0.5, 0.55, 0.2, 3).translate(x, (top - 0.5) / 2, z))
            frame.append(cylinder(0.5, 0.22, 16, 0.06).translate(x, 0, z))
        frame.append(rounded_box(0.35, 0.35, width - 0.4, 0.12, 3).translate(x, 1.0, 0))
    frame.append(rounded_box(length - 3.0, 0.35, 0.35, 0.12, 3).translate(length / 2, 1.0, 0))
    under = rounded_box(length - 0.8, 0.5, width - 0.6, 0.2, 3).translate(length / 2, top - 0.75, 0)
    cleats = [rounded_box(0.28, 0.1, width - 0.6, 0.04, 2).translate(0.6 + k * 2.0, top + 0.03, 0)
              for k in range(22)]
    return {"Belt": merge(belt, *drums), "Stripe": merge(*rails), "Frame": merge(*frame, under),
            "Cleats": merge(*cleats)}


def machine_body(width, height, depth, bottom, radius=0.9):
    return rounded_box(width, height, depth, radius, 7).translate(0, bottom + height / 2, 0)


def cake_press():
    """Station 1, the SPONGE oven: a chubby oven on legs with a porthole window, dials, a chimney and
    a chef's hat. Its stamp ("Stamp") presses a sponge onto the plate below."""
    bottom, height, depth = 7.6, 4.3, 7.6
    body = machine_body(6.2, height, depth, bottom)
    front = -depth / 2
    window = cylinder(1.2, 0.2, 40).rotate("x", 90).translate(0, 9.55, front + 0.05)
    window_ring = torus(1.28, 0.2, 40, 10).rotate("x", 90).translate(0, 9.55, front - 0.02)
    dials = []
    for x in (-2.2, 2.2):
        dials.append(cylinder(0.38, 0.25, 20, 0.08).rotate("x", 90).translate(x, 8.45, front + 0.02))
        dials.append(rounded_box(0.1, 0.42, 0.1, 0.04, 2).translate(x, 8.55, front - 0.25))
    chimney = merge(cylinder(0.5, 2.0, 20).translate(2.0, bottom + height - 0.3, 1.6),
                    torus(0.55, 0.14, 20, 8).translate(2.0, bottom + height + 1.7, 1.6))
    hat_band = cylinder(1.25, 0.75, 32, 0.1).translate(-0.9, bottom + height - 0.15, 0.6)
    puffs = [sphere(0.95, 12, 16).translate(-0.9 + dx, bottom + height + 1.2 + dy, 0.6 + dz)
             for dx, dy, dz in ((0, 0.35, 0), (-0.7, 0, 0.3), (0.7, 0.05, -0.2), (0.1, 0, -0.75), (-0.2, 0.05, 0.8))]
    stripe = rounded_box(6.34, 0.55, depth + 0.14, 0.25, 4).translate(0, bottom + 0.75, 0)
    whites, pupils = eyes(0, 11.0, front - 0.02, 1.15, 0.55)
    rod = cylinder(0.24, 1.4, 16).translate(0, 6.4, 0)
    plate = cylinder(1.5, 0.32, 40, 0.1).translate(0, 6.1, 0)
    trim = merge(window_ring, *dials, chimney,
                 bolts([(x, y, front - 0.02) for x in (-2.6, 2.6) for y in (bottom + 0.5, bottom + height - 0.5)]))
    return {"Body": body, "Frame": legs(bottom + 0.4), "Window": window, "Trim": trim, "Hat": merge(hat_band, *puffs),
            "Stripe": stripe, "Eyes": whites, "Pupils": pupils, "Stamp": merge(rod, plate)}


def cake_nozzle():
    """Station 2, the CREAM machine: a glass tank of swirly cream on a gantry, piping through a
    star nozzle ("Nozzle") that dips down to frost the cake."""
    beam_y = 7.8
    beam = rounded_box(2.3, 1.5, 2 * LEG_Z + 1.6, 0.5, 5).translate(0, beam_y + 0.75, 0)
    tank = lathe([(0.0, 0.0), (1.9, 0.0), (2.15, 0.25), (2.25, 0.8), (2.25, 3.0), (2.1, 3.5), (1.8, 3.7),
                  (1.75, 3.75), (0.0, 3.75)], 48).translate(0, beam_y + 1.5, 0)
    fill = lathe([(0.0, 0.0), (1.95, 0.0), (2.1, 0.25), (2.13, 2.1), (0.0, 2.1)], 48).translate(0, beam_y + 1.6, 0)
    swirl = rosette(1.6, 1.0, 8, 1.2, 22, 56, 0.16).translate(0, beam_y + 3.65, 0)
    lid = merge(cylinder(1.95, 0.4, 48, 0.12).translate(0, beam_y + 5.2, 0),
                cylinder(0.25, 0.9, 12).translate(0, beam_y + 5.55, 0),
                capsule(1.4, 0.2, 10).rotate("z", 90).translate(0.6, beam_y + 6.45, 0),
                sphere(0.32, 10, 12).translate(1.3, beam_y + 6.45, 0))
    collar = cylinder(1.15, 0.5, 32, 0.15).translate(0, beam_y - 0.4, 0)
    cone = lathe([(0.0, 0.0), (0.38, 0.0), (0.46, 0.2), (0.95, 1.2), (0.0, 1.2)], 32).translate(0, beam_y - 1.55, 0)
    tip = extrude(star(0.5, 0.3, 8), 0.5).rotate("x", 90).translate(0, beam_y - 1.75, 0)
    stripe = rounded_box(2.42, 0.45, 2 * LEG_Z + 1.72, 0.2, 4).translate(0, beam_y + 0.35, 0)
    whites, pupils = eyes(0, beam_y + 0.85, -(LEG_Z + 0.8) - 0.02, 0.62, 0.4)
    pipes = [tube([(0, beam_y + 1.0, z * 1.6), (0, beam_y + 1.0, z * 2.6), (0, beam_y + 2.6, z * 2.6),
                   (0, beam_y + 3.3, z * 2.0)], 0.2, 10) for z in (-1, 1)]
    return {"Frame": merge(legs(beam_y + 0.2), beam, *pipes), "Tank": tank, "CreamFill": merge(fill, swirl),
            "Trim": merge(lid, collar), "Nozzle": merge(cone, tip), "Stripe": stripe, "Eyes": whites,
            "Pupils": pupils}


def cake_hopper():
    """Station 3, the BERRY dropper: a striped funnel heaped with strawberries; one pops out of
    the chute onto each cake."""
    beam_y = 7.6
    beam = rounded_box(2.2, 1.3, 2 * LEG_Z + 1.6, 0.5, 5).translate(0, beam_y + 0.65, 0)
    funnel_profile = [(0.0, 0.0), (0.7, 0.0), (0.75, 0.3), (2.7, 3.0), (2.8, 3.2), (2.65, 3.25), (2.5, 3.0),
                      (0.55, 0.35), (0.0, 0.35)]
    funnel = lathe(funnel_profile, 48).translate(0, beam_y + 1.2, 0)
    bands = [torus(0.75 + 1.95 * t / 3.0 + 0.06, 0.1, 48, 6).translate(0, beam_y + 1.2 + t, 0)
             for t in (0.9, 1.7, 2.45)]
    rim = torus(2.78, 0.16, 48, 8).translate(0, beam_y + 4.43, 0)
    chute = merge(cylinder(0.62, 1.0, 24).translate(0, beam_y - 0.7, 0),
                  torus(0.62, 0.12, 24, 6).translate(0, beam_y - 0.7, 0))
    berries, leaves = [], []
    rng = np.random.default_rng(11)
    spots = [(0, 0), (0.9, 0.3), (-0.8, 0.5), (0.3, -0.9), (-0.5, -0.7), (1.4, -0.6), (-1.5, -0.2), (0.7, 1.3),
             (-0.6, 1.4), (1.6, 0.9), (-1.7, 0.9), (0.1, 0.7)]
    for k, (x, z) in enumerate(spots):
        lift = 0.55 if k < 6 else 0.0
        b, l = berry_at(k, x, beam_y + 3.75 + lift + 0.25 * (1 - (x * x + z * z) / 4), z, 1.05,
                        rng.uniform(-40, 40), rng.uniform(0, 360))
        berries.append(b)
        leaves.append(l)
    whites, pupils = eyes(0, beam_y + 2.6, -1.95, 0.6, 0.42)
    stripe = rounded_box(2.32, 0.42, 2 * LEG_Z + 1.72, 0.18, 4).translate(0, beam_y + 0.3, 0)
    return {"Frame": merge(legs(beam_y + 0.2), beam, chute), "Hopper": funnel, "Rim": merge(rim, *bands),
            "Berries": merge(*berries), "BerryLeaves": merge(*leaves), "Eyes": whites, "Pupils": pupils,
            "Stripe": stripe}


def cake_stacker():
    """The plate tower at the start of the line: a glass column of plates that drops one onto the
    belt for every cake, with a beacon on top."""
    base_y = 4.0
    tube_mesh = lathe([(0.0, 0.0), (2.35, 0.0), (2.4, 0.1), (2.4, 6.0), (2.3, 6.1), (2.25, 6.0), (2.25, 0.2),
                       (0.0, 0.2)], 48).translate(0, base_y, 0)
    plates = []
    for k in range(11):
        plates.append(cylinder(2.08, 0.32, 40, 0.1).translate(0, base_y + 0.3 + k * 0.5, 0))
    collar = merge(cylinder(2.7, 0.6, 48, 0.2).translate(0, base_y - 0.4, 0),
                   cylinder(2.7, 0.6, 48, 0.2).translate(0, base_y + 6.0, 0))
    dome = lathe([(0.0, 0.0), (2.2, 0.0), (2.0, 0.6), (1.4, 1.2), (0.6, 1.5), (0.0, 1.55)], 40).translate(0, base_y + 6.6, 0)
    beacon = merge(sphere(0.55, 12, 16).translate(0, base_y + 8.4, 0))
    arms = [rounded_box(1.0, 1.0, 2 * LEG_Z + 1.4, 0.35, 4).translate(0, base_y - 0.7, 0)]
    whites, pupils = eyes(0, base_y + 7.3, -1.95, 0.6, 0.38)
    stripe = merge(torus(2.42, 0.14, 48, 8).translate(0, base_y + 3.1, 0))
    return {"Frame": merge(legs(base_y - 0.2), *arms, collar), "Glass": tube_mesh, "Plates": merge(*plates),
            "Dome": dome, "Beacon": beacon, "Eyes": whites, "Pupils": pupils, "Stripe": stripe}


def cake_boxer():
    """The packing machine over the end of the belt: a finished cake gets a box dropped over it
    here. Its lamp ("Lamp") flashes as each cake passes."""
    bottom, height, depth = 8.4, 3.6, 7.6
    body = machine_body(6.4, height, depth, bottom, 0.8)
    front = -depth / 2
    lamp = merge(sphere(0.75, 14, 18).scale(1, 1, 0.7).translate(0, bottom + height + 0.55, -1.2))
    lamp_base = cylinder(0.85, 0.35, 24, 0.1).translate(0, bottom + height - 0.05, -1.2)
    mouth = rounded_box(4.6, 0.6, depth + 0.1, 0.25, 4).translate(0, bottom + 0.2, 0)
    sign = rounded_box(3.6, 1.5, 0.25, 0.3, 4).translate(0, bottom + 1.9, front - 0.05)
    box_icon = merge(rounded_box(1.1, 0.8, 0.12, 0.08, 2).translate(0, bottom + 1.75, front - 0.22),
                     rounded_box(1.25, 0.25, 0.12, 0.08, 2).translate(0, bottom + 2.25, front - 0.22))
    whites, pupils = eyes(0, bottom + height - 0.75, front - 0.02, 1.9, 0.42, (0.3, -0.1))
    stripe = rounded_box(6.54, 0.5, depth + 0.14, 0.22, 4).translate(0, bottom + height - 0.2, 0)
    trim = merge(lamp_base, mouth, sign,
                 bolts([(x, bottom + 0.9, front - 0.02) for x in (-2.7, 2.7)]))
    return {"Body": body, "Frame": legs(bottom + 0.4), "Trim": trim, "Lamp": lamp, "Icon": box_icon,
            "Eyes": whites, "Pupils": pupils, "Stripe": stripe}


# ------------------------------------------------------------------ decorations

def cake_tiered():
    """A giant three-tier party cake with dripping icing, rosettes, strawberries and candles."""
    tiers = [(7.5, 4.6), (5.6, 4.0), (3.8, 3.6)]
    y = 0.0
    sponge, cream, berries, leaves, candles, flames = [], [], [], [], [], []
    rng = np.random.default_rng(7)
    board = cylinder(8.6, 0.6, 64, 0.2)
    y = 0.6
    for index, (radius, height) in enumerate(tiers):
        sponge.append(cylinder(radius, height, 64, 0.5).translate(0, y, 0))
        top = y + height
        cream.append(lathe([(0.0, top - 0.3), (radius - 0.2, top - 0.3), (radius + 0.12, top - 0.55),
                            (radius + 0.22, top - 0.2), (radius + 0.1, top + 0.15), (radius - 0.3, top + 0.28),
                            (0.0, top + 0.3)], 64))
        count = int(radius * 3.2)
        for k in range(count):
            a = 2 * math.pi * k / count + rng.uniform(-0.1, 0.1)
            length = rng.uniform(0.6, 1.9)
            cream.append(capsule(length + 0.6, 0.3, 10).translate(math.cos(a) * (radius + 0.12), top - 0.45 - length / 2,
                                                                     math.sin(a) * (radius + 0.12)))
        ring = int(radius * 2.0)
        for k in range(ring):
            a = 2 * math.pi * k / ring
            cream.append(rosette(0.55, 0.75, 7, 0.8, 14, 28).translate(math.cos(a) * (radius - 0.6), top + 0.2,
                                                                         math.sin(a) * (radius - 0.6)))
        cream.append(torus(radius + 0.05, 0.32, 64, 8).translate(0, y + 0.3, 0))
        y = top + 0.3
        if index < 2:
            for k in range(6):
                a = 2 * math.pi * (k + 0.5) / 6
                r = tiers[index + 1][0] + (radius - tiers[index + 1][0]) * 0.55
                b, l = berry_at(20 + k + index * 6, math.cos(a) * r, top + 0.2, math.sin(a) * r, 1.4, 0, k * 40)
                berries.append(b)
                leaves.append(l)
    b, l = berry_at(40, 0, y, 0, 3.0, 0, 20)
    berries.append(b)
    leaves.append(l)
    for k in range(5):
        a = 2 * math.pi * k / 5 + 0.3
        x, z = math.cos(a) * 2.6, math.sin(a) * 2.6
        candles.append(cylinder(0.22, 1.9, 12).translate(x, y - 0.1, z))
        flames.append(sphere(0.3, 8, 10).scale(1, 1.6, 1).translate(x, y + 2.15, z))
    stripes = [torus(0.235, 0.05, 12, 6).translate(c, 0, 0) for c in ()]
    return {"Board": board, "Sponge": merge(*sponge), "Cream": merge(*cream), "Berries": merge(*berries),
            "BerryLeaves": merge(*leaves), "Candles": merge(*candles, *stripes), "Flames": merge(*flames)}


def cake_mixer():
    """A giant stand mixer: a rounded base and arm, a steel bowl of pink batter and a wire whisk."""
    s = 1.0
    base = rounded_box(9.0, 2.2, 13.0, 1.0, 6).translate(0, 1.1, 1.0)
    column = rounded_box(4.6, 13.0, 4.4, 1.6, 6).translate(0, 7.5, 5.5)
    head = merge(capsule(13.0, 2.8, 32).rotate("x", 90).translate(0, 15.2, 1.5),
                 sphere(2.85, 18, 28).scale(1.0, 1.0, 0.9).translate(0, 15.2, 6.2))
    band = torus(2.85, 0.28, 48, 10).rotate("x", 90).translate(0, 15.2, -1.6)
    hub = cylinder(1.2, 0.8, 32, 0.2).translate(0, 11.9, -1.9)
    knob = merge(cylinder(0.7, 0.6, 20, 0.15).rotate("x", 90).translate(2.3, 13.8, 5.0),
                 rounded_box(0.25, 1.3, 0.3, 0.1, 2).translate(2.62, 13.8, 5.0))
    bowl = lathe([(0.0, 0.0), (1.8, 0.0), (2.2, 0.2), (3.6, 1.8), (4.4, 4.6), (4.6, 6.0), (4.75, 6.15), (4.6, 6.2),
                  (4.4, 6.0), (4.2, 4.6), (3.4, 1.9), (2.0, 0.45), (0.0, 0.4)], 64).translate(0, 2.2, -2.0)
    batter = lathe([(0.0, 0.0), (3.7, 0.0), (4.1, 0.3), (0.0, 0.9)], 64).translate(0, 6.4, -2.0)
    whisk = []
    for k in range(6):
        a = math.pi * k / 6
        loop = []
        for i in range(17):
            t = math.pi * i / 16
            loop.append((math.cos(a) * math.sin(t) * 1.6, 11.5 - 4.6 * math.sin(t / 2) ** 0.8 - 0.4 * math.sin(t),
                         -2.0 + math.sin(a) * math.sin(t) * 1.6))
        whisk.append(tube(loop, 0.09, 6))
    whisk.append(cylinder(0.35, 1.2, 16).translate(0, 10.9, -2.0))
    return {"Body": merge(base, column, head, knob), "Trim": merge(band, hub), "Bowl": bowl, "Batter": batter,
            "Whisk": merge(*whisk)}


def cake_cupcake():
    """A cupcake: a pleated wrapper, a swirl of frosting and a cherry on top."""
    wrapper = wavy_lathe([(0.0, 0.0), (1.25, 0.0), (1.32, 0.05), (1.62, 1.5), (1.66, 1.62), (1.5, 1.6), (0.0, 1.6)],
                         72, 20, 0.04, 0.5)
    cake = lathe([(0.0, 1.5), (1.62, 1.5), (1.72, 1.85), (1.5, 2.15), (0.0, 2.2)], 48)
    frosting = coil(1.55, 1.9, 2.6, 0.55).translate(0, 2.0, 0)
    cherry = merge(sphere(0.42, 14, 18).translate(0.05, 4.15, 0))
    stem = tube([(0.05, 4.45, 0), (0.15, 4.8, 0.05), (0.4, 5.05, 0.1)], 0.05, 6)
    return {"Wrapper": wrapper, "Sponge": cake, "Frosting": frosting, "Cherry": cherry, "Stem": stem}


PROPS = {
    "CakePlate": cake_plate,
    "CakeSponge": cake_sponge,
    "CakeCream": cake_cream,
    "CakeBerry": cake_berry,
    "CakeBox": cake_box,
    "CakeBin": cake_bin,
    "CakeBelt": cake_belt,
    "CakePress": cake_press,
    "CakeNozzle": cake_nozzle,
    "CakeHopper": cake_hopper,
    "CakeStacker": cake_stacker,
    "CakeBoxer": cake_boxer,
    "CakeTiered": cake_tiered,
    "CakeMixer": cake_mixer,
    "CakeCupcake": cake_cupcake,
}

# Preview colors (the game colors pieces by name from Props/CakeFactory.luau).
COLORS = {
    "Plate": (250, 250, 252), "Doily": (255, 214, 228), "Sponge": (246, 196, 112), "Filling": (255, 244, 232),
    "Cream": (255, 246, 240), "SprinklesA": (255, 120, 170), "SprinklesB": (120, 200, 255), "SprinklesC": (255, 215, 80),
    "Berry": (232, 40, 60), "Seeds": (255, 226, 120), "BerryLeaves": (80, 190, 80), "Window": (180, 225, 255),
    "Stripe": (255, 80, 90), "Bin": (120, 210, 200), "Lid": (120, 210, 200), "Belt": (70, 64, 86),
    "Frame": (236, 236, 246), "Cleats": (52, 48, 66), "Body": (255, 196, 160), "Trim": (255, 205, 80),
    "Hat": (255, 255, 255), "Eyes": (255, 255, 255), "Pupils": (30, 26, 40), "Stamp": (200, 205, 220),
    "Tank": (210, 235, 255), "CreamFill": (255, 214, 226), "Nozzle": (205, 210, 225), "Hopper": (255, 110, 120),
    "Berries": (232, 40, 60), "Glass": (210, 235, 255), "Plates": (250, 250, 252), "Dome": (255, 196, 160),
    "Beacon": (255, 230, 120), "Lamp": (140, 255, 160), "Icon": (255, 255, 255), "Board": (255, 225, 140),
    "Candles": (150, 210, 255), "Flames": (255, 200, 80), "Bowl": (215, 220, 232), "Batter": (255, 190, 210),
    "Whisk": (215, 220, 232), "Wrapper": (140, 200, 255), "Frosting": (255, 170, 210), "Cherry": (225, 30, 60),
    "Stem": (110, 160, 60),
}
