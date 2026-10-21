"""Meshes for Honey Trap's storybook meadow (see tools/meshgen/props/README.md). Units are studs, +Y up,
base on y = 0, -Z is the front (the side that faces the players). Generate with:
    python3 tools/meshgen/generate_meshes.py --only HoneyOak,HoneyVine,HoneyDaisyPad,HoneyBasket,HoneyGlade,HoneySunflower,HoneySkep,HoneyDice

The pieces are colored by name in src/server/World/Props/HoneyTrap.luau."""

import math

import numpy as np

from generate_meshes import (
    Mesh,
    extrude,
    icosphere,
    lathe,
    merge,
    rounded_box,
    sdf_mesh,
    smin,
    sphere,
    torus,
)
from generate_meshes import taper as _taper
from generate_meshes import tube as _tube

# The vine hangs from here (the tip of the oak's front branch). Honey Trap's server reads the
# "Anchor" piece, so the vine, the items and the falling fruit all line up with the branch.
ANCHOR = (0.0, 29.6, -14.5)


# ------------------------------------------------------------------------------------- helpers


def sd_round_cone(p, a, b, r1, r2):
    """Distance to a capsule whose radius goes from r1 at a to r2 at b (iq's round cone)."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    ba = b - a
    l2 = ba @ ba
    rr = r1 - r2
    a2 = l2 - rr * rr
    il2 = 1.0 / l2
    pa = p - a
    y = pa @ ba
    z = y - l2
    x2v = pa * l2 - y[:, None] * ba
    x2 = np.einsum("ij,ij->i", x2v, x2v)
    y2 = y * y * l2
    z2 = z * z * l2
    k = np.sign(rr) * rr * rr * x2
    out = (np.sqrt(np.maximum(x2 * a2 * il2, 0)) + y * rr) * il2 - r1
    top = np.sign(z) * a2 * z2 > k
    out = np.where(top, np.sqrt(x2 + z2) * il2 - r2, out)
    bottom = np.sign(y) * a2 * y2 < k
    return np.where(bottom & ~top, np.sqrt(x2 + y2) * il2 - r1, out)


def outward(mesh: Mesh) -> Mesh:
    """Makes a closed mesh face outwards (sdf_mesh's triangles can come out inside-out, and Roblox
    culls back faces): flips it if its signed volume is negative."""
    tri = mesh.v[mesh.f]
    volume = np.einsum("ij,ij->i", tri[:, 0], np.cross(tri[:, 1], tri[:, 2])).sum()
    if volume < 0:
        mesh.f = mesh.f[:, ::-1].copy()
    return mesh


def _sides_outward(mesh: Mesh, points, sides: int) -> Mesh:
    """Turns each side triangle of a tube so it faces away from its stretch of the polyline."""
    pts = np.asarray(points, float)
    count = (len(pts) - 1) * sides * 2
    faces = mesh.f[:count]
    tri = mesh.v[faces]
    normal = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    segment = np.repeat(np.arange(len(pts) - 1), sides * 2)
    middle = (pts[segment] + pts[segment + 1]) / 2
    inward = np.einsum("ij,ij->i", tri.mean(axis=1) - middle, normal) < 0
    faces[inward] = faces[inward][:, ::-1]
    mesh.f[:count] = faces
    return mesh


def tube(points, radius, sides=8):
    return _sides_outward(_tube(points, radius, sides), points, sides)


def taper(points, r0, r1, sides=8):
    return _sides_outward(_taper(points, r0, r1, sides), points, sides)


def limb(p, points, radii):
    """A smooth bent limb through `points` with radius going through `radii`."""
    d = None
    for i in range(len(points) - 1):
        seg = sd_round_cone(p, points[i], points[i + 1], radii[i], radii[i + 1])
        d = seg if d is None else np.minimum(d, seg)
    return d


def blob_union(p, spheres, k):
    d = None
    for x, y, z, r in spheres:
        s = np.linalg.norm(p - np.array([x, y, z]), axis=1) - r
        d = s if d is None else smin(d, s, k)
    return d


def wavy_disc(radius, y_top, y_bottom, wobble, waves, segments=96, rings=6, bevel=0.6, seed=0):
    """A flat disc with a wavy outline, a rounded edge and a skirt that dips below the ground."""
    rng = np.random.default_rng(seed)
    phases = rng.uniform(0, 2 * math.pi, 3)
    verts, faces = [(0.0, y_top, 0.0)], []

    def edge(theta):
        return radius * (1 + wobble * (0.6 * math.sin(waves * theta + phases[0]) + 0.4 * math.sin((waves + 3) * theta + phases[1])))

    # Rings from the middle out, then the bevel and the skirt.
    profile = [(t, y_top) for t in np.linspace(0, 1, rings + 1)[1:]]
    for i in range(1, 4):
        a = math.pi / 2 * i / 3
        profile.append((1 + bevel * math.sin(a) / radius, y_top - bevel * (1 - math.cos(a))))
    profile.append((1 + (bevel + 0.2) / radius, y_bottom))
    for ring, (t, y) in enumerate(profile):
        for s in range(segments):
            theta = 2 * math.pi * s / segments
            if ring < rings:
                r = edge(theta) * t
            else:
                r = edge(theta) + (t - 1) * radius
            verts.append((math.cos(theta) * r, y, math.sin(theta) * r))
    for s in range(segments):
        faces.append((0, 1 + (s + 1) % segments, 1 + s))
    for ring in range(len(profile) - 1):
        for s in range(segments):
            a = 1 + ring * segments + s
            b = 1 + ring * segments + (s + 1) % segments
            c = a + segments
            d = b + segments
            faces += [(a, b, c), (b, d, c)]
    return Mesh(verts, faces), edge


def orient(mesh: Mesh, normal) -> Mesh:
    """Turns a mesh authored facing +Y so it faces `normal`."""
    n = np.asarray(normal, float)
    n /= np.linalg.norm(n)
    up = np.array([0.0, 1.0, 0.0])
    axis = np.cross(up, n)
    s = np.linalg.norm(axis)
    c = up @ n
    if s < 1e-6:
        if c < 0:
            mesh.v = mesh.v * np.array([1, -1, -1])
        return mesh
    axis /= s
    kx = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
    rot = np.eye(3) + kx * s + kx @ kx * (1 - c)
    mesh.v = mesh.v @ rot.T
    return mesh


def flower_head(radius, lobes, thickness, cup=0.0, seed=0):
    """A flat flower: a lobed outline (petals) extruded thin and cupped upward, facing +Y."""
    rng = np.random.default_rng(seed)
    turn = rng.uniform(0, 2 * math.pi)
    points = []
    count = lobes * 6
    for i in range(count):
        theta = 2 * math.pi * i / count + turn
        r = radius * (0.55 + 0.45 * abs(math.cos(lobes * (theta - turn) / 2)) ** 0.7)
        points.append((math.cos(theta) * r, math.sin(theta) * r))
    mesh = extrude(points, thickness).rotate("x", -90)
    mesh.smooth = True
    r = np.linalg.norm(mesh.v[:, [0, 2]], axis=1)
    mesh.v[:, 1] += cup * (r / radius) ** 2
    return mesh


def leaf(length, width, bend=0.3, segments=8):
    """A pointed leaf lying along +Z from the origin, curling up at the tip, with a midrib crease."""
    verts, faces = [], []
    for i in range(segments + 1):
        t = i / segments
        half = width / 2 * math.sin(math.pi * t) ** 0.8
        z = length * t
        y = bend * t * t
        for side in (-1, 0, 1):
            verts.append((side * half, y + (0.06 if side == 0 else 0.0) - abs(side) * half * 0.15, z))
    for i in range(segments):
        a = i * 3
        for j in range(2):
            p, q, r, s = a + j, a + j + 1, a + 3 + j, a + 4 + j
            faces += [(p, r, q), (q, r, s)]
    top = Mesh(verts, faces)
    bottom = Mesh(np.array(verts) - np.array([0, 0.05, 0]), [(f[0], f[2], f[1]) for f in faces])
    return merge(top, bottom)


# ---------------------------------------------------------------------------------- the oak


def honey_oak():
    """The giant honey oak: a gnarled, grooved trunk with flared roots, a round storybook door and
    window, a puffy two-tone canopy dotted with blossoms, a hanging beehive, honey oozing from a
    knothole, a rope swing and paper lanterns. The front branch holds the vine at ANCHOR."""
    rng = np.random.default_rng(11)
    spine = [(0.0, -1.0, 0.0), (0.8, 7.0, 0.4), (-0.6, 14.0, -0.3), (0.6, 21.0, -0.4), (0.0, 28.0, 0.0), (0.0, 33.0, 0.2)]
    spine_r = [6.8, 5.5, 4.8, 4.3, 3.7, 2.9]
    root_angles = [a for a in np.radians([-150, -30, 10, 55, 100, 140, 180, 215, 250])]
    root_paths = []
    for index, a in enumerate(root_angles):
        bend = a + rng.uniform(-0.15, 0.15)
        reach = rng.uniform(11.0, 13.5)
        root_paths.append((
            [(math.cos(a) * 2.5, 5.0, math.sin(a) * 2.5), (math.cos(a) * 6.5, 1.6, math.sin(a) * 6.5),
             (math.cos(bend) * reach * 0.8, 0.4, math.sin(bend) * reach * 0.8), (math.cos(bend) * reach, -0.6, math.sin(bend) * reach)],
            [2.9, 2.0, 1.1, 0.5],
        ))
    branches = [
        # The vine branch, reaching out over the players' side; its tip is just above ANCHOR.
        ([(0.0, 23.0, -1.5), (0.0, 27.6, -6.5), (0.0, 30.4, -11.0), (0.0, 30.9, -14.4), (0.0, 30.6, -15.6)],
         [2.1, 1.55, 1.05, 0.75, 0.55]),
        ([(1.5, 26.0, 0.5), (6.5, 31.5, 1.5), (11.5, 34.0, 2.4), (14.0, 36.5, 2.8)], [2.0, 1.4, 0.95, 0.6]),  # hive branch
        ([(-1.5, 27.0, 0.0), (-6.5, 31.0, -1.0), (-11.5, 33.6, -1.6), (-14.5, 36.6, -2.0)], [2.0, 1.4, 0.95, 0.6]),  # swing branch
        ([(0.0, 29.0, 1.5), (0.5, 34.0, 7.0), (0.8, 38.0, 11.0)], [1.8, 1.2, 0.7]),
        ([(0.5, 31.0, -0.5), (4.5, 37.0, -5.0), (6.5, 40.0, -7.0)], [1.4, 0.9, 0.55]),
        ([(-0.5, 31.0, 0.5), (-4.5, 38.0, 4.5), (-6.0, 41.0, 6.5)], [1.4, 0.9, 0.55]),
    ]

    def trunk_sdf(p):
        d = limb(p, spine, spine_r)
        # Bark: twisting vertical grooves on the trunk.
        theta = np.arctan2(p[:, 2], p[:, 0])
        radial = np.linalg.norm(p[:, [0, 2]], axis=1)
        groove = (0.28 * np.sin(theta * 9 + p[:, 1] * 0.13) + 0.1 * np.sin(theta * 23 - p[:, 1] * 0.31))
        d = d + groove * np.clip(7.5 - radial, 0, 1) * np.clip((33 - p[:, 1]) / 3, 0, 1)
        for points, radii in root_paths:
            d = smin(d, limb(p, points, radii), 1.8)
        for points, radii in branches:
            d = smin(d, limb(p, points, radii), 1.2)
        return np.maximum(d, -p[:, 1])  # flat underneath, sitting on the ground

    trunk = outward(sdf_mesh(trunk_sdf, (-16.0, -0.5, -17.5), (17.5, 42.5, 15.5), 0.62))
    trunk.v[:, 1] = np.maximum(trunk.v[:, 1], 0.0)

    # Canopy: big soft puffs (a little crease between them), front kept clear above the vine.
    puffs = [
        (0, 47, 1, 12.0), (-11, 43, -1, 9.5), (11, 43.5, 2, 9.5), (0, 43, 10, 9.5), (-1, 43.5, -8, 8.0),
        (-15, 38.5, 3, 6.5), (15, 38.5, -1, 6.5), (6, 38, 11, 6.5), (-7, 38.5, 10, 6.5),
        (-6, 52, 4, 8.0), (6, 53, -3, 8.0), (0, 57, 1, 7.0),
        (-9, 48, -8, 6.5), (9, 47, -8, 6.5), (8, 48, 9, 7.0), (-9, 49, 9, 7.0),
    ]
    noise_dirs = rng.normal(size=(6, 3))
    noise_dirs /= np.linalg.norm(noise_dirs, axis=1, keepdims=True)
    noise_off = rng.uniform(0, 6, 6)

    def canopy_sdf(p):
        d = blob_union(p, puffs, 1.6)
        return d + 0.35 * np.mean(np.sin(p @ noise_dirs.T * 0.55 + noise_off), axis=1)

    leaves = outward(sdf_mesh(canopy_sdf, (-24, 29, -20), (24, 66, 20), 1.0))

    # Lighter highlight puffs where the sun hits: on the upper surface, half poking out.
    normals_v = leaves.normals()[1]
    upper = [i for i in range(len(leaves.v)) if normals_v[i][1] > 0.35]
    chosen = []
    for i in rng.permutation(upper):
        if all(np.linalg.norm(leaves.v[i] - leaves.v[j]) > 7.0 for j in chosen):
            chosen.append(i)
        if len(chosen) >= 16:
            break
    light = []
    for n, i in enumerate(chosen):
        r = rng.uniform(2.8, 3.8)
        center = leaves.v[i] - normals_v[i] * r * 0.4
        light.append(icosphere(r, 2, 0.12, 50 + n).scale(1.0, 0.8, 1.0).translate(*center))
    leaves_light = merge(*light)

    # Blossoms: little five-petal flowers on the canopy surface, facing out.
    candidates = [i for i in range(len(leaves.v)) if normals_v[i][1] > -0.2 and leaves.v[i][1] > 40]
    picks = rng.choice(candidates, 90, replace=False)
    blossoms, pollen = [], []
    for n, i in enumerate(picks):
        position = leaves.v[i] + normals_v[i] * 0.15
        size = rng.uniform(0.9, 1.3)
        head = flower_head(size, 5, 0.18, 0.18, seed=n)
        blossoms.append(orient(head, normals_v[i]).translate(*position))
        pollen.append(icosphere(size * 0.28, 0).translate(*(position + normals_v[i] * 0.2)))

    # The beehive hanging off the hive branch: a stacked skep shape with a dark entrance.
    hive_profile = [(0.0, 0.0)]
    for i in range(1, 17):
        t = i / 16
        bulge = math.sin(math.pi * (0.12 + 0.88 * t)) * 3.0 + 0.35
        hive_profile.append((bulge + (0.18 if i % 2 == 0 else 0.0), -t * 6.6))
    hive_profile.append((0.0, -6.8))
    hive_x, hive_top, hive_z = 10.2, 33.0, 2.3
    hive = lathe(hive_profile[::-1], 28).translate(hive_x, hive_top, hive_z)
    hive_hole = icosphere(0.75, 2).scale(1.0, 0.8, 0.45).translate(hive_x, hive_top - 4.3, hive_z - 3.15)
    stalk = taper([(hive_x, hive_top + 1.5, hive_z), (hive_x, hive_top - 0.2, hive_z)], 0.5, 0.35, 8)

    # Honey: drips under the hive, a knothole on the front of the trunk oozing down the bark.
    drips = []
    for dx, dz, length in ((0.0, 0.0, 1.6), (0.9, -0.6, 1.0), (-0.8, 0.5, 1.2)):
        x, z = hive_x + dx, hive_z + dz
        drips.append(taper([(x, hive_top - 6.4, z), (x, hive_top - 6.6 - length, z)], 0.35, 0.18, 8))
        drips.append(icosphere(0.32, 1).translate(x, hive_top - 6.7 - length, z))
    knot_y = 15.5

    def surface_z(y):
        """Front of the trunk (most negative z on the x=0 line) at height y."""
        samples = np.array([[0.0, y, z] for z in np.linspace(-8, 0, 161)])
        values = trunk_sdf(samples)
        inside = np.where(values < 0)[0]
        return samples[inside[0]][2] if len(inside) else -4.0

    knot_z = surface_z(knot_y)
    knot_rim = torus(0.95, 0.38, 20, 8).rotate("x", 90).scale(1.0, 1.3, 1.0).translate(0.3, knot_y, knot_z - 0.1)
    knot_hole = icosphere(0.9, 2).scale(0.9, 1.2, 0.35).translate(0.3, knot_y, knot_z + 0.05)
    ooze_points = []
    for y in np.linspace(knot_y - 0.6, knot_y - 7.5, 12):
        ooze_points.append((0.3 + 0.25 * math.sin(y * 0.8), y, surface_z(y) - 0.12))
    ooze = taper(ooze_points, 0.55, 0.3, 10)
    ooze_end = icosphere(0.42, 2).translate(*ooze_points[-1])
    honey_pool = icosphere(1.0, 2).scale(1.0, 0.25, 0.8).translate(0.3, knot_y - 0.9, knot_z - 0.25)

    # The front door: an arched plank door, a stone frame, a knob and a round lit window.
    door_y0 = 0.0
    door_z = surface_z(2.4) - 0.05
    arch = []
    for i in range(25):
        a = math.pi * i / 24
        arch.append((math.cos(a) * 1.45, 2.6 + math.sin(a) * 1.45))
    arch += [(-1.45, 0.0), (1.45, 0.0)]
    door = extrude(arch, 0.5).translate(0, door_y0, door_z - 0.1)
    door.smooth = False
    planks = [rounded_box(0.08, 3.6, 0.1, 0.03, 2).translate(x, 1.8, door_z - 0.38) for x in (-0.72, 0.0, 0.72)]
    frame_stones = []
    for i in range(11):
        a = math.pi * i / 10
        frame_stones.append(rounded_box(0.75, 0.55, 0.7, 0.2, 3).rotate("z", math.degrees(a) - 90)
                            .translate(math.cos(a) * 1.85, 2.6 + math.sin(a) * 1.85, door_z - 0.15))
    for side in (-1, 1):
        for y in (0.35, 1.1, 1.85):
            frame_stones.append(rounded_box(0.7, 0.6, 0.7, 0.2, 3).translate(side * 1.85, y, door_z - 0.15))
    knob = icosphere(0.18, 1).translate(0.85, 1.9, door_z - 0.45)
    win_y = 7.6
    win_z = surface_z(win_y)
    window = icosphere(1.0, 2).scale(1.0, 1.0, 0.3).translate(0.0, win_y, win_z - 0.02)
    window_frame = torus(1.05, 0.26, 24, 8).rotate("x", 90).translate(0.0, win_y, win_z - 0.18)
    window_bars = [rounded_box(0.12, 2.0, 0.12, 0.05, 2).translate(0, win_y, win_z - 0.28),
                   rounded_box(2.0, 0.12, 0.12, 0.05, 2).translate(0, win_y, win_z - 0.28)]

    # A rope swing off the left branch, and paper lanterns hanging around the canopy.
    swing_x, swing_top, swing_bottom = -10.0, 32.6, 9.5
    ropes = [tube([(swing_x + dx, swing_top, -1.3), (swing_x + dx, swing_bottom + 0.15, -1.3)], 0.12, 6) for dx in (-1.1, 1.1)]
    seat = rounded_box(3.0, 0.3, 1.1, 0.12, 3).translate(swing_x, swing_bottom, -1.3)
    lanterns, strings = [], []
    for x, top, z, drop in ((-14.0, 36.0, -2.0, 3.5), (13.5, 35.5, 2.7, 3.0), (6.0, 39.0, -7.0, 2.6), (-6.0, 40.5, 6.5, 3.0),
                            (0.6, 37.5, 10.8, 2.6), (0.0, 30.8, -9.5, 1.6)):
        strings.append(tube([(x, top, z), (x, top - drop + 0.6, z)], 0.05, 5))
        body = lathe([(0.0, -0.75), (0.45, -0.68), (0.72, -0.3), (0.76, 0.0), (0.72, 0.3), (0.45, 0.68), (0.0, 0.75)], 16)
        lanterns.append(body.translate(x, top - drop, z))
        strings.append(torus(0.32, 0.07, 14, 5).translate(x, top - drop + 0.7, z))
        strings.append(torus(0.32, 0.07, 14, 5).translate(x, top - drop - 0.7, z))

    anchor = icosphere(0.3, 0).translate(*ANCHOR)
    return {
        "Trunk": merge(trunk, stalk, seat),
        "Leaves": leaves,
        "LeavesLight": leaves_light,
        "Blossoms": merge(*blossoms),
        "Pollen": merge(*pollen, knob),
        "Hive": hive,
        "Honey": merge(*drips, ooze, ooze_end, honey_pool),
        "Hole": merge(hive_hole, knot_hole),
        "Bark": merge(knot_rim),
        "Door": merge(door, *planks),
        "Stone": merge(*frame_stones, window_frame, *window_bars),
        "Window": window,
        "Rope": merge(*ropes, *strings),
        "Glow": merge(*lanterns),
        "Anchor": anchor,
    }


# --------------------------------------------------------------------------------- the vine


def honey_vine():
    """The vine the fruit hangs on: two strands twisting round each other with leaves and curly
    tendrils, 25.5 studs long (the top 1.2 studs tuck into the branch)."""
    length = 25.5
    rng = np.random.default_rng(3)
    strands = []
    for phase in (0.0, math.pi):
        points = []
        for y in np.linspace(0, length, 70):
            a = y * 0.9 + phase
            points.append((math.cos(a) * 0.17, y, math.sin(a) * 0.17 + 0.22))
        strands.append(tube(points, 0.15, 7))
    leaves, tendrils = [], []
    for i, y in enumerate(np.arange(1.2, length - 1.0, 1.3)):
        # Leaves sprout to the sides and the back, out of the way of the hanging fruit (+Z is front here).
        side = 1 if i % 2 == 0 else -1
        yaw = side * rng.uniform(55, 120) + 180
        size = rng.uniform(0.75, 1.05)
        leaves.append(leaf(1.3 * size, 0.75 * size, 0.25).rotate("x", -20).rotate("y", yaw).translate(0, y, 0.22))
        if i % 3 == 1:
            curl = [(side * (0.3 + 0.35 * math.cos(t)), y - 0.2 + t * 0.08, 0.22 - 0.35 * math.sin(t)) for t in np.linspace(0, 4 * math.pi, 26)]
            tendrils.append(tube(curl, 0.05, 5))
    return {"Vine": merge(*strands, *tendrils), "VineLeaves": merge(*leaves)}


# ------------------------------------------------------------------------------- daisy pads


def daisy_pad():
    """A giant flat flower the player stands on: two rings of cupped petals, a low seed dome (0.3
    high, so it sits on the sand and the player's feet rest on it) and three leaves underneath.
    4.8 studs across. "Mark" is the middle at ground level (the prop's own pivot is off-center)."""
    rng = np.random.default_rng(7)
    petals = []
    for ring, (count, length, width, y, turn) in enumerate(((12, 1.45, 0.78, 0.08, 0.0), (12, 1.2, 0.7, 0.13, 15.0))):
        for i in range(count):
            angle = 360 * i / count + turn
            petal = sphere(1.0, 6, 12).scale(width / 2, 0.11, length / 2)
            # Cup the petal: tip curls up a touch.
            petal.v[:, 1] += 0.12 * (petal.v[:, 2] / (length / 2) + 1) ** 2 * 0.25
            petals.append(petal.translate(0, y, 0.95 + length / 2 - 0.15 * ring).rotate("y", angle))
    center_profile = [(1.3, 0.06), (1.32, 0.17), (1.22, 0.25), (0.95, 0.29), (0.5, 0.3), (0.0, 0.3)]
    center = lathe(center_profile, 32, cap_bottom=True)
    seeds = []
    for ring_r, count in ((0.45, 7), (0.85, 12)):
        for i in range(count):
            a = 2 * math.pi * i / count + ring_r
            seeds.append(icosphere(0.12, 0).scale(1, 0.5, 1).translate(math.cos(a) * ring_r, 0.3, math.sin(a) * ring_r))
    leaves = []
    # They point backwards (+Z, away from the vine) so neighbouring pads' leaves never overlap.
    for yaw in (-48.0, 0.0, 48.0):
        size = rng.uniform(0.95, 1.05)
        leaves.append(leaf(2.2 * size, 1.4 * size, 0.1).rotate("x", 6).translate(0, 0.2, 1.1).rotate("y", yaw))
    mark = icosphere(0.05, 0)
    return {"Petals": merge(*petals), "Center": center, "Seeds": merge(*seeds), "Leaves": merge(*leaves), "Mark": mark}


# ---------------------------------------------------------------------------------- baskets


def honey_basket():
    """A woven picnic basket: over-and-under wicker, a rolled rim, two side loops and a gingham
    cloth tucked over one side. Fruit lands inside (its floor is 0.25 up)."""
    rows = 6
    segments = 40
    stakes = 16
    weave = []

    def wall_r(y):
        return 1.3 + 0.5 * (y / 1.45)

    for row in range(rows):
        y0 = 0.2 + row * 0.2
        points = []
        for s in range(segments + 1):
            a = 2 * math.pi * s / segments
            over = math.sin(a * stakes / 2 + row * math.pi) * 0.05
            r = wall_r(y0) + 0.04 + over
            points.append((math.cos(a) * r, y0 + 0.1, math.sin(a) * r))
        weave.append(tube(points, 0.1, 6))
    bowl = lathe([(0.0, 0.05), (1.2, 0.0), (1.32, 0.12), (wall_r(1.4), 1.4), (wall_r(1.4) - 0.12, 1.4),
                  (1.22, 0.25), (0.0, 0.25)], 40)
    uprights = []
    for s in range(stakes):
        a = 2 * math.pi * s / stakes
        uprights.append(tube([(math.cos(a) * (wall_r(y) + 0.02), y, math.sin(a) * (wall_r(y) + 0.02)) for y in (0.1, 0.8, 1.4)], 0.05, 4))
    rim = torus(wall_r(1.45) + 0.02, 0.14, 40, 8).translate(0, 1.45, 0)
    loops = [torus(0.32, 0.07, 14, 6, 200).rotate("x", 90).rotate("z", 10 * side).rotate("y", 90)
             .translate(side * (wall_r(1.45) + 0.12), 1.5, 0) for side in (-1, 1)]
    for loop, side in zip(loops, (-1, 1)):
        loop.v[:, 0] = side * np.abs(loop.v[:, 0])
    cloth_v, cloth_f = [], []
    n = 10
    for i in range(n + 1):
        for j in range(n + 1):
            u, w = i / n, j / n
            a = math.radians(-60 + 120 * u)
            r = wall_r(1.45) + 0.12
            over = 0.55 * w
            x = math.cos(a) * (r - 0.1 + over * 0.6)
            z = math.sin(a) * (r - 0.1 + over * 0.6)
            y = 1.55 - over * 1.25 + 0.06 * math.sin(u * math.pi * 3)
            cloth_v.append((x, y, z))
    for i in range(n):
        for j in range(n):
            a = i * (n + 1) + j
            cloth_f += [(a, a + n + 1, a + 1), (a + 1, a + n + 1, a + n + 2)]
    cloth_top = Mesh(cloth_v, cloth_f)
    cloth_back = Mesh(np.array(cloth_v) * np.array([0.985, 1, 0.985]) - np.array([0, 0.04, 0]), [(f[0], f[2], f[1]) for f in cloth_f])
    cloth = merge(cloth_top, cloth_back).rotate("y", 200)
    return {"Basket": merge(bowl, *uprights), "Weave": merge(*weave), "Rim": merge(rim, *loops), "Cloth": cloth}


# ------------------------------------------------------------------------------------ glade


GLADE_RADIUS = 34.0
PATH_INNER, PATH_OUTER = 14.0, 23.0
TRUNK_Z = -14.5  # the oak's trunk sits this far behind the vine (the glade's middle)


def honey_glade():
    """The clearing around the oak: a soft lawn with a wavy edge, a golden sand crescent under the
    players' flowers, stepping stones, clusters of little flowers, toadstools by the roots and
    grass tufts. The players stand on the +Z side; the oak is at (0, TRUNK_Z). "Mark" is the origin
    (the vine spot on the ground), since the prop's own pivot is off-center."""
    rng = np.random.default_rng(42)
    lawn, edge = wavy_disc(GLADE_RADIUS, 0.2, -0.35, 0.05, 7, 120, 6, 0.5, seed=4)
    lawn.translate(0, 0, -4.0)

    # The sand crescent: a band around the vine spot on the players' side.
    path_v, path_f = [], []
    arc0, arc1, steps = math.radians(-112), math.radians(112), 72
    across = 9
    for i in range(steps + 1):
        a = arc0 + (arc1 - arc0) * i / steps
        fade = min(1.0, min(i, steps - i) / 8)  # ends taper in
        mid = (PATH_INNER + PATH_OUTER) / 2 + 0.6 * math.sin(a * 5)
        half = (PATH_OUTER - PATH_INNER) / 2 * (0.35 + 0.65 * fade ** 0.6)
        for j in range(across + 1):
            t = j / across * 2 - 1
            r = mid + t * half
            y = 0.32 - 0.25 * abs(t) ** 4
            path_v.append((math.sin(a) * r, y, math.cos(a) * r))
    for i in range(steps):
        for j in range(across):
            a = i * (across + 1) + j
            path_f += [(a, a + 1, a + across + 1), (a + 1, a + across + 2, a + across + 1)]
    path = Mesh(path_v, path_f)

    # Stepping stones: a little trail from the crescent out to the meadow (straight back, +Z) and two
    # leading round to the oak.
    stones = []
    trail = [(0.4, 25.0), (-0.8, 27.4), (0.6, 29.8), (-0.3, 32.2)]
    trail += [(-24.5, 4.0), (-25.0, 0.0), (-23.5, -4.0), (-20.5, -7.5), (24.5, 4.5), (24.8, 0.5), (23.0, -3.5), (20.0, -7.0)]
    for n, (x, z) in enumerate(trail):
        stone = icosphere(1.0, 2, 0.1, 100 + n).scale(rng.uniform(0.9, 1.25), 0.22, rng.uniform(0.7, 0.95))
        stones.append(stone.rotate("y", rng.uniform(0, 180)).translate(x, 0.2, z))

    def clear_of_game(x, z, margin=0.0):
        r = math.hypot(x, z)
        a = math.atan2(x, z)
        on_path = PATH_INNER - 1.5 - margin < r < PATH_OUTER + 1.5 + margin and abs(a) < math.radians(116)
        near_trunk = math.hypot(x, z - TRUNK_Z) < 12.5 + margin
        near_vine = r < 4.0
        near_trail = abs(x) < 2.5 and z > 22
        return not (on_path or near_trunk or near_vine or near_trail)

    # Flower beds: dense clumps of chunky flowers (three petal colors, yellow middles) on a rosette
    # of leaves.
    petals = {"FlowerPink": [], "FlowerWhite": [], "FlowerLilac": []}
    centers, stems, tufts = [], [], []
    clusters = 0
    tries = 0
    while clusters < 24 and tries < 4000:
        tries += 1
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(5, GLADE_RADIUS - 2)
        cx, cz = math.sin(a) * r, math.cos(a) * r - 4.0
        if not clear_of_game(cx, cz, 1.5) or r > edge(a) - 2.5:
            continue
        clusters += 1
        kind = list(petals)[clusters % 3]
        for k in range(5):
            yaw = 72 * k + rng.uniform(0, 40)
            stems.append(leaf(1.3, 0.75, 0.25).rotate("x", -12).rotate("y", yaw).translate(cx, 0.24, cz))
        for _ in range(rng.integers(8, 13)):
            x, z = cx + rng.normal(0, 0.75), cz + rng.normal(0, 0.75)
            if not clear_of_game(x, z):
                continue
            h = rng.uniform(0.45, 1.0)
            size = rng.uniform(0.45, 0.65)
            tilt = (rng.normal(0, 0.15), 1.0, rng.normal(0, 0.15))
            head = flower_head(size, 5, 0.12, 0.1, seed=int(rng.integers(0, 1 << 30)))
            top = np.array([x, 0.2 + h, z]) + np.array(tilt) * 0.05
            petals[kind].append(orient(head, tilt).translate(*top))
            centers.append(icosphere(size * 0.3, 0).scale(1, 0.7, 1).translate(top[0], top[1] + 0.08, top[2]))
            stems.append(tube([(x, 0.0, z), (x + tilt[0] * h * 0.5, 0.05 + h * 0.6, z + tilt[2] * h * 0.5), tuple(top)], 0.07, 4))
    # Grass tufts: around the lawn edge (softening it into the meadow) and dotted inside.
    for n in range(170):
        a = rng.uniform(0, 2 * math.pi)
        if n < 110:
            r = edge(a) - rng.uniform(-0.4, 1.2)
        else:
            r = rng.uniform(5, GLADE_RADIUS - 3)
        x, z = math.sin(a) * r, math.cos(a) * r - 4.0
        if not clear_of_game(x, z):
            continue
        blades = []
        for b in range(8):
            yaw = 2 * math.pi * b / 8 + rng.uniform(-0.3, 0.3)
            h = rng.uniform(0.5, 1.0)
            lean = rng.uniform(0.2, 0.45)
            base = np.array([x + math.cos(yaw) * 0.15, -0.05, z + math.sin(yaw) * 0.15])
            tip = base + np.array([math.cos(yaw) * lean, h, math.sin(yaw) * lean])
            side = np.array([-math.sin(yaw), 0, math.cos(yaw)]) * 0.16
            blades.append(Mesh([base - side, base + side, tip], [(0, 1, 2), (0, 2, 1)]))
        tufts.append(merge(*blades))

    # Toadstools around the oak's roots (front and sides).
    caps, spots, stalks = [], [], []
    for n, (angle, dist, scale) in enumerate(((60, 12.5, 1.3), (42, 13.6, 0.8), (122, 12.8, 1.15), (140, 13.8, 0.75),
                                             (-30, 13.0, 0.9), (205, 12.5, 1.0), (25, 12.8, 1.0), (158, 13.2, 0.7))):
        a = math.radians(angle)
        x, z = math.cos(a) * dist, TRUNK_Z + math.sin(a) * dist
        h = 0.9 * scale
        stalks.append(lathe([(0.0, 0.0), (0.32 * scale, 0.0), (0.26 * scale, h * 0.6), (0.3 * scale, h), (0.0, h)], 12).translate(x, 0, z))
        cap = lathe([(0.0, h + 0.1 * scale), (0.6 * scale, h + 0.05 * scale), (0.95 * scale, h + 0.1 * scale), (0.85 * scale, h + 0.4 * scale),
                     (0.5 * scale, h + 0.68 * scale), (0.0, h + 0.75 * scale)], 18)
        tilt = rng.uniform(-8, 8)
        caps.append(cap.rotate("z", tilt).translate(x, 0, z))
        for k in range(5):
            sa = 2 * math.pi * k / 5 + n
            sr = 0.55 * scale
            spot = icosphere(0.13 * scale, 1).scale(1, 0.4, 1)
            spot = orient(spot, (math.cos(sa) * 0.6, 1.0, math.sin(sa) * 0.6))
            spots.append(spot.translate(math.cos(sa) * sr, h + 0.58 * scale, math.sin(sa) * sr).rotate("z", tilt).translate(x, 0, z))
    return {
        "Lawn": lawn,
        "Sand": path,
        "Stones": merge(*stones),
        **{name: merge(*items) for name, items in petals.items()},
        "FlowerMiddles": merge(*centers),
        "Stems": merge(*stems, *tufts),
        "Caps": merge(*caps),
        "Spots": merge(*spots),
        "Stalks": merge(*stalks),
        "Mark": icosphere(0.05, 0),  # the glade's middle (the vine spot) at ground level
    }


# ------------------------------------------------------------------------------- sunflowers


def sunflower():
    """A tall storybook sunflower, its face turned to the front (-Z): a curving stem, big leaves,
    two rings of petals and a seed head. About 13 studs tall."""
    rng = np.random.default_rng(5)
    stem_points = [(0.0, 0.0, 0.0), (0.25, 3.0, 0.1), (-0.15, 6.5, -0.1), (0.1, 9.5, -0.4), (0.0, 11.2, -1.0)]
    stem = taper(stem_points, 0.32, 0.22, 10)
    leaves = []
    for y, yaw, size in ((2.4, 70, 1.0), (4.6, 250, 1.1), (7.0, 110, 0.9), (8.8, 300, 0.75)):
        leaves.append(leaf(2.8 * size, 1.9 * size, 0.6).rotate("x", -15).rotate("y", yaw).translate(0, y, 0))
    head_center = np.array([0.0, 11.4, -1.25])
    facing = np.array([0.0, 0.25, -1.0])
    petals = []
    for ring, (count, length, width, back) in enumerate(((16, 1.6, 0.62, 0.12), (16, 1.35, 0.55, 0.02))):
        for i in range(count):
            petal = icosphere(1.0, 1).scale(width / 2, 0.09, length / 2)
            petal.v[:, 1] += 0.1 * (petal.v[:, 2] / (length / 2) + 1) ** 2 * 0.3
            petal.translate(0, -back, 1.15 + length / 2).rotate("y", 360 * i / count + ring * 11.25 + rng.uniform(-3, 3))
            petals.append(petal)
    head = lathe([(1.25, 0.0), (1.28, 0.12), (1.1, 0.3), (0.6, 0.42), (0.0, 0.45)], 28, cap_bottom=True)
    seeds = []
    for k in range(70):
        # Golden-angle spiral of seeds on the face.
        r = 1.05 * math.sqrt((k + 0.5) / 70)
        a = k * 2.39996
        y = 0.45 - 0.18 * (r / 1.25) ** 2
        seeds.append(icosphere(0.09, 0).translate(math.cos(a) * r, y + 0.02, math.sin(a) * r))
    back = lathe([(0.0, -0.25), (0.9, -0.2), (1.25, 0.0)], 20)

    def place(mesh):
        return orient(mesh, facing).translate(*head_center)

    return {
        "Stem": merge(stem, place(back)),
        "SunLeaves": merge(*leaves),
        "SunPetals": place(merge(*petals)),
        "SeedHead": place(merge(head, *seeds)),
    }


# ------------------------------------------------------------------------------------ skeps


def skep():
    """A straw beehive (skep) on a little wooden stool: coiled straw rings, binding bands and a dark
    entrance at the front (-Z)."""
    profile = [(1.75, 1.4)]
    coils = []
    for i in range(9):
        t = i / 8
        r = 1.75 * math.cos(t * math.pi / 2 * 0.92) + 0.1
        y = 1.55 + i * 0.36
        profile.append((r, y))
        coils.append(torus(r, 0.2, 32, 7).translate(0, y, 0))
    profile.append((0.0, 1.55 + 9 * 0.36))
    body = lathe(profile, 32, cap_bottom=True)
    knob = icosphere(0.35, 2).translate(0, 1.55 + 8.6 * 0.36, 0)
    bands = []
    for k in range(4):
        a = 2 * math.pi * k / 4 + math.pi / 4
        pts = []
        for i in range(9):
            t = i / 8
            r = 1.75 * math.cos(t * math.pi / 2 * 0.92) + 0.3
            pts.append((math.cos(a) * r, 1.55 + i * 0.36, math.sin(a) * r))
        bands.append(tube(pts, 0.07, 5))
    hole = icosphere(0.45, 2).scale(1.2, 0.7, 0.6).translate(0, 1.85, -1.85)
    seat = lathe([(0.0, 1.15), (2.0, 1.15), (2.1, 1.3), (2.0, 1.45), (0.0, 1.45)], 28)
    legs = [taper([(math.cos(a) * 1.3, 1.2, math.sin(a) * 1.3), (math.cos(a) * 1.6, 0.0, math.sin(a) * 1.6)], 0.2, 0.17, 8)
            for a in (math.radians(d) for d in (30, 150, 270))]
    return {"Straw": merge(body, *coils, knob), "Bands": merge(*bands), "Entrance": hole, "Stool": merge(seat, *legs)}


# -------------------------------------------------------------------------------- the block


def honey_dice():
    """The 1-or-2 block: a soft cube (the client colors it and writes the number on its sides)
    with a cream piping along its rounded edges, bobbles on the corners and little bee wings."""
    block = rounded_box(4.0, 4.0, 4.0, 0.75, 8)
    trim = []
    e = 1.25 + 0.75 * math.sqrt(0.5) - 0.1  # on the rounded edge
    for s1 in (-1, 1):
        for s2 in (-1, 1):
            trim.append(rounded_box(2.6, 0.46, 0.46, 0.22, 3).translate(0, s1 * e, s2 * e))
            trim.append(rounded_box(0.46, 2.6, 0.46, 0.22, 3).translate(s1 * e, 0, s2 * e))
            trim.append(rounded_box(0.46, 0.46, 2.6, 0.22, 3).translate(s1 * e, s2 * e, 0))
    c = 1.25 + 0.75 / math.sqrt(3) - 0.08
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                trim.append(icosphere(0.42, 2).translate(sx * c, sy * c, sz * c))
    wings = []
    for side in (-1, 1):
        wings.append(icosphere(1.0, 2).scale(1.3, 0.08, 0.75).rotate("z", side * -28).translate(side * 1.25, 2.55, 0.3))
    return {
        "Block": block.translate(0, 2.0, 0),
        "Trim": merge(*trim).translate(0, 2.0, 0),
        "Wings": merge(*wings).translate(0, 2.0, 0),
    }


PROPS = {
    "HoneyOak": honey_oak,
    "HoneyVine": honey_vine,
    "HoneyDaisyPad": daisy_pad,
    "HoneyBasket": honey_basket,
    "HoneyGlade": honey_glade,
    "HoneySunflower": sunflower,
    "HoneySkep": skep,
    "HoneyDice": honey_dice,
}

# Preview colors only (the game colors pieces by name); names other modes already color are left out.
COLORS = {
    "LeavesLight": (150, 214, 92),
    "Blossoms": (255, 196, 220),
    "Pollen": (255, 214, 80),
    "Hole": (60, 36, 24),
    "Bark": (110, 74, 48),
    "Door": (215, 95, 70),
    "Vine": (78, 140, 52),
    "VineLeaves": (120, 196, 80),
    "Petals": (255, 170, 200),
    "Center": (255, 196, 50),
    "Seeds": (210, 140, 40),
    "Weave": (212, 160, 96),
    "Cloth": (235, 84, 84),
    "Lawn": (140, 210, 96),
    "Stones": (214, 208, 196),
    "FlowerPink": (255, 150, 190),
    "FlowerWhite": (255, 255, 250),
    "FlowerLilac": (190, 160, 255),
    "FlowerMiddles": (255, 210, 60),
    "Stems": (88, 160, 70),
    "Caps": (230, 64, 60),
    "Spots": (255, 250, 240),
    "Stalks": (250, 236, 210),
    "SunLeaves": (104, 176, 72),
    "SunPetals": (255, 204, 40),
    "SeedHead": (120, 72, 36),
    "Entrance": (50, 32, 22),
    "Stool": (150, 100, 62),
}
