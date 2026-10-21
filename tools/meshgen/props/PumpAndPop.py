"""Props for Pump & Pop: the team balloon (with a face that gets nervous as it fills up), the air
tank each balloon is tied to, and the floor pump ("plunger") every player works.

    python3 tools/meshgen/generate_meshes.py --only PumpBalloon,AirTank,Plunger

Units are studs, +Y is up, the base sits on y = 0 and -Z is the front:
  * PumpBalloon: the face looks along -Z (towards the team's players).
  * AirTank: the pressure gauge looks along -Z (towards the players).
  * Plunger: the hose runs along -Z into the tank; the player stands behind it (+Z) and holds the
    T-handle, which the client slides down (Rod, Handle and Grips move together).
"""

import math

import numpy as np

from generate_meshes import (Mesh, capsule, cylinder, extrude, icosphere, lathe, merge, rounded_box, sphere, star, taper, torus,
                             tube)

# ---------------------------------------------------------------------------- the balloon

BALLOON_TOP = 15.0
NECK_Y = 0.95  # where the body meets the knot


def balloon_profile(rings: int = 46) -> list[tuple[float, float]]:
    """(radius, y) from the neck to the top: a round top tapering to the knot like a real balloon."""
    points = []
    for i in range(rings + 1):
        t = i / rings
        a = math.pi * t
        y = NECK_Y + (BALLOON_TOP - NECK_Y) * (1 - math.cos(a)) / 2
        radius = 6.25 * math.sin(a) ** 0.92 * (1 - 0.5 * (1 - t) ** 2.4)
        points.append((max(radius, 0.0), y))
    points[0] = (0.24, NECK_Y)  # open neck, hidden inside the knot
    points[-1] = (0.0, BALLOON_TOP)
    return points


PROFILE = balloon_profile()


def surface_radius(y: float) -> float:
    for (r0, y0), (r1, y1) in zip(PROFILE, PROFILE[1:]):
        if y0 <= y <= y1:
            return r0 + (r1 - r0) * (y - y0) / max(y1 - y0, 1e-9)
    return PROFILE[-1][0]


def surface_frame(x: float, y: float, lift: float = 0.0):
    """A point on the balloon's front (-Z side) at (x, y), pushed `lift` studs out along the
    surface normal, and the rotation that turns a feature's -Z axis onto that normal."""
    radius = surface_radius(y)
    x = max(-radius * 0.95, min(radius * 0.95, x))
    z = -math.sqrt(max(radius * radius - x * x, 1e-6))
    slope = (surface_radius(y + 0.05) - surface_radius(y - 0.05)) / 0.1  # dr/dy
    radial = np.array([x, 0.0, z]) / radius
    normal = radial - np.array([0.0, slope, 0.0])
    normal /= np.linalg.norm(normal)
    point = np.array([x, y, z]) + normal * lift
    forward = -normal  # the feature's +Z points into the balloon
    up = np.array([0.0, 1.0, 0.0])
    right = np.cross(up, forward)
    right /= np.linalg.norm(right)
    up = np.cross(forward, right)
    rotation = np.stack([right, up, forward], axis=1)  # columns: local x, y, z in world
    return point, rotation


def on_surface(mesh: Mesh, x: float, y: float, lift: float = 0.0) -> Mesh:
    point, rotation = surface_frame(x, y, lift)
    mesh.v = mesh.v @ rotation.T + point
    return mesh


def ellipsoid(rx: float, ry: float, rz: float, detail: int = 2) -> Mesh:
    return icosphere(1.0, detail).scale(rx, ry, rz)


def curve_on_surface(points2d: list[tuple[float, float]], lift: float, radius: float, sides: int = 8) -> Mesh:
    path = [tuple(surface_frame(x, y, lift)[0]) for x, y in points2d]
    caps = [sphere(radius, 6, 8).translate(*path[0]), sphere(radius, 6, 8).translate(*path[-1])]
    return merge(tube(path, radius, sides), *caps)


def pump_balloon():
    """The team balloon: a glossy party balloon with a tied knot and a cartoon face. The face has
    spare pieces the client shows as it fills: worried Brows, a round Ooh mouth and a Sweat drop."""
    body = lathe(PROFILE, 48)
    knot = lathe([(0.0, 0.0), (0.2, 0.02), (0.34, 0.1), (0.4, 0.24), (0.34, 0.4), (0.24, 0.5), (0.2, 0.62), (0.3, 0.74),
                  (0.33, 0.86), (0.28, 0.98), (0.0, 1.02)], 20)
    lip = torus(0.33, 0.1, 20, 8).translate(0, 0.42, 0)

    eye_y, eye_x = 9.4, 1.75
    eyes = [on_surface(ellipsoid(0.92, 1.22, 0.32), side * eye_x, eye_y, 0.06) for side in (-1, 1)]
    pupils = [on_surface(ellipsoid(0.5, 0.66, 0.24), side * (eye_x - 0.12), eye_y - 0.12, 0.3) for side in (-1, 1)]
    shine = []
    for side in (-1, 1):
        shine.append(on_surface(sphere(0.17, 6, 10), side * (eye_x - 0.12) + 0.18, eye_y + 0.14, 0.5))
        shine.append(on_surface(sphere(0.08, 5, 8), side * (eye_x - 0.12) - 0.16, eye_y - 0.32, 0.47))

    smile_points = [(u * 1.25, 7.25 - 0.55 * (1 - u * u)) for u in np.linspace(-1, 1, 13)]
    smile = curve_on_surface(smile_points, 0.08, 0.15)

    ooh_ring = torus(1.0, 0.16, 24, 8).rotate("x", 90).scale(0.48, 0.66, 1.0)
    ooh = merge(on_surface(ooh_ring, 0, 7.0, 0.08), on_surface(ellipsoid(0.46, 0.62, 0.12), 0, 7.0, 0.04))

    brows = []
    for side in (-1, 1):
        inner, outer = side * (eye_x - 0.75), side * (eye_x + 0.8)
        points = [(inner + (outer - inner) * u, eye_y + 1.72 - 0.38 * u - 0.12 * math.sin(math.pi * u)) for u in np.linspace(0, 1, 7)]
        brows.append(curve_on_surface(points, 0.08, 0.13))

    blush = [on_surface(ellipsoid(0.78, 0.42, 0.14), side * 3.15, 8.0, 0.02) for side in (-1, 1)]

    drop = lathe([(0.0, -0.42), (0.2, -0.36), (0.3, -0.2), (0.3, 0.0), (0.22, 0.2), (0.11, 0.38), (0.0, 0.52)], 14)
    sweat = on_surface(drop.scale(1.0, 1.0, 0.55), -3.55, 11.2, 0.08)

    # The classic cartoon gleam: a curved white streak high on the players' left (+X).
    gleam_points = [(4.25 - 1.5 * u * u, 10.9 + 2.7 * u) for u in np.linspace(0.0, 1.0, 9)]
    gleam = curve_on_surface(gleam_points, 0.0, 0.2, 8)
    gleam_dot = on_surface(ellipsoid(0.28, 0.32, 0.1), 4.75, 9.75, 0.0)

    return {
        "Skin": merge(body, knot, lip),
        "Eyes": merge(*eyes),
        "Pupils": merge(*pupils),
        "Shine": merge(*shine),
        "Smile": smile,
        "Ooh": ooh,
        "Brows": merge(*brows),
        "Blush": merge(*blush),
        "Sweat": sweat,
        "Gleam": merge(gleam, gleam_dot),
    }


# ---------------------------------------------------------------------------- the air tank

TANK_RADIUS = 2.45
TANK_TOP = 4.7  # top of the brass neck, where the balloon's knot sits
DIAL_Y = 2.15
DIAL_RADIUS = 0.8
HOSE_Y = 0.95  # where the plungers' hoses enter the tank


def air_tank():
    """A chunky toy air tank on a plinth, with riveted gold bands, a red valve wheel, a brass neck
    on top (the balloon is tied to it) and a big pressure gauge on the front. The client turns the
    Needle."""
    plinth = merge(cylinder(TANK_RADIUS + 0.35, 0.36, 40, 0.12), torus(TANK_RADIUS + 0.3, 0.07, 40, 6).translate(0, 0.36, 0))
    body = cylinder(TANK_RADIUS, 3.2, 40, 0.28).translate(0, 0.34, 0)
    dome = lathe([(TANK_RADIUS - 0.04, 3.4), (2.3, 3.6), (2.0, 3.8), (1.55, 3.97), (1.05, 4.07), (0.6, 4.11), (0.0, 4.12)], 40)
    bands, rivets = [], []
    for y in (0.62, 3.3):
        bands.append(torus(TANK_RADIUS + 0.02, 0.13, 48, 8).translate(0, y, 0))
        for a in np.linspace(0, 2 * math.pi, 16, endpoint=False) + math.pi / 16:
            rivets.append(icosphere(0.075, 1).translate(math.cos(a) * (TANK_RADIUS + 0.14), y, math.sin(a) * (TANK_RADIUS + 0.14)))
    neck = lathe([(0.0, 4.06), (0.66, 4.06), (0.56, 4.18), (0.42, 4.28), (0.36, 4.42), (0.48, 4.47), (0.5, 4.56), (0.46, 4.62),
                  (0.32, 4.66), (0.3, TANK_TOP), (0.0, TANK_TOP)], 24)
    ring = torus(0.7, 0.06, 32, 6).translate(0, 4.1, 0)

    # A red valve wheel on the side, for a bit of toy-machine charm.
    valve_x = TANK_RADIUS + 0.05
    stem = cylinder(0.12, 0.42, 12, 0.03).rotate("z", -90).translate(valve_x - 0.05, 2.15, 0)
    wheel = [torus(0.42, 0.07, 28, 6).rotate("z", 90).translate(valve_x + 0.4, 2.15, 0)]
    for angle in (0, 60, 120):
        wheel.append(capsule(0.84, 0.05, 6).rotate("x", angle).translate(valve_x + 0.4, 2.15, 0))
    wheel.append(sphere(0.1, 6, 8).translate(valve_x + 0.42, 2.15, 0))

    # The gauge: a white face on a brass bezel, ticks, a red "nearly full" arc and the needle.
    gauge_z = -(TANK_RADIUS + 0.05)
    housing = cylinder(DIAL_RADIUS + 0.16, 0.32, 36, 0.08).rotate("x", -90).translate(0, DIAL_Y, gauge_z + 0.12)
    bezel = torus(DIAL_RADIUS + 0.08, 0.1, 40, 8).rotate("x", 90).translate(0, DIAL_Y, gauge_z - 0.2)
    face = cylinder(DIAL_RADIUS, 0.06, 36).rotate("x", -90).translate(0, DIAL_Y, gauge_z - 0.17)
    # Dial angles are measured clockwise from 12 o'clock as the players see it (their right is -X):
    # empty at -120, full at +120. The client turns the Needle (which points at 12) the same way.
    ticks = []
    for index in range(11):
        angle = -120 + 24 * index
        a = math.radians(angle)
        length = 0.22 if index % 5 == 0 else 0.14
        r = DIAL_RADIUS - 0.08 - length / 2
        tick = rounded_box(0.06, length, 0.03, 0.01, 2).rotate("z", angle)
        ticks.append(tick.translate(-math.sin(a) * r, DIAL_Y + math.cos(a) * r, gauge_z - 0.25))
    red_center = math.degrees(math.atan2(math.cos(math.radians(100)), -math.sin(math.radians(100))))
    red_arc = torus(DIAL_RADIUS - 0.13, 0.05, 24, 5, 40).rotate("y", 20).rotate("x", 90).rotate("z", red_center)
    red_arc = red_arc.translate(0, DIAL_Y, gauge_z - 0.24)
    needle = merge(
        lathe([(0.06, 0.0), (0.035, 0.45), (0.0, DIAL_RADIUS - 0.22)], 6),
        cylinder(0.12, 0.08, 16).rotate("x", -90),
    ).translate(0, DIAL_Y, gauge_z - 0.3)
    return {
        "Feet": plinth,
        "Tank": merge(body, dome),
        "TankBands": merge(*bands, *rivets),
        "Brass": merge(neck, ring, housing, bezel, stem),
        "Dial": face,
        "Ticks": merge(*ticks),
        "DialRed": merge(red_arc, *wheel),
        "Needle": needle,
    }


# ---------------------------------------------------------------------------- the plunger pump

PLUNGER_TO_TANK = 7.5  # distance from the plunger's rod to the tank's center (the hose fits it)
HANDLE_Y = 3.9
BARREL_RADIUS = 0.4
BARREL_TOP = 2.72


def plunger():
    """A big floor pump: foot stand, team-colored barrel with chrome collars, a rod and a T-handle
    with ribbed rubber grips, and a hose that runs along the floor into the air tank."""
    base = merge(
        rounded_box(1.0, 0.22, 1.0, 0.08, 3).translate(0, 0.11, 0),
        rounded_box(0.72, 0.13, 0.56, 0.05, 2).translate(-0.86, 0.065, 0.04),
        rounded_box(0.72, 0.13, 0.56, 0.05, 2).translate(0.86, 0.065, 0.04),
        cylinder(0.5, 0.12, 24, 0.04).translate(0, 0.2, 0),
    )
    barrel = cylinder(BARREL_RADIUS, BARREL_TOP - 0.3, 28, 0.06).translate(0, 0.3, 0)
    chrome = [
        cylinder(BARREL_RADIUS + 0.07, 0.24, 28, 0.06).translate(0, 0.26, 0),
        cylinder(BARREL_RADIUS + 0.08, 0.26, 28, 0.07).translate(0, BARREL_TOP - 0.12, 0),
        lathe([(0.0, BARREL_TOP + 0.14), (0.22, BARREL_TOP + 0.14), (0.14, BARREL_TOP + 0.26), (0.0, BARREL_TOP + 0.26)], 16),
        torus(BARREL_RADIUS + 0.015, 0.035, 28, 5).translate(0, 1.15, 0),
        torus(BARREL_RADIUS + 0.015, 0.035, 28, 5).translate(0, 1.95, 0),
    ]
    # The hose: out of the barrel's foot, down to the floor, along it and up into the tank.
    tank_z = -(PLUNGER_TO_TANK - TANK_RADIUS)
    path = [(0, 0.38, -0.42), (0, 0.32, -0.72), (0, 0.17, -1.15), (0, 0.15, -1.9), (0, 0.15, -2.8), (0, 0.17, tank_z + 1.1),
            (0, 0.34, tank_z + 0.64), (0, 0.66, tank_z + 0.34), (0, HOSE_Y, tank_z + 0.12)]
    hose = tube(path, 0.13, 10)
    ribs = [torus(0.145, 0.03, 12, 4).rotate("x", 90).translate(0, 0.15, z) for z in np.linspace(-1.5, tank_z + 1.2, 6)]
    couplings = [
        cylinder(0.2, 0.2, 16, 0.04).rotate("x", 90).translate(0, 0.38, -0.56),
        cylinder(0.2, 0.24, 18, 0.05).rotate("x", 90).translate(0, HOSE_Y, tank_z),
    ]
    rod = cylinder(0.085, HANDLE_Y - 1.65, 12).translate(0, 1.65, 0)
    bar = capsule(2.4, 0.11, 14).rotate("z", 90).translate(0, HANDLE_Y, 0)
    hub = merge(cylinder(0.17, 0.3, 16, 0.05).translate(0, HANDLE_Y - 0.15, 0), sphere(0.13, 6, 10).translate(0, HANDLE_Y + 0.15, 0))
    grips = []
    for side in (-1, 1):
        grip = capsule(0.8, 0.19, 14).rotate("z", 90).translate(side * 0.86, HANDLE_Y, 0)
        grips.append(grip)
        for offset in (-0.22, 0.0, 0.22):
            grips.append(torus(0.19, 0.035, 14, 4).rotate("z", 90).translate(side * 0.86 + offset, HANDLE_Y, 0))
    return {
        "PumpBase": base,
        "Barrel": barrel,
        "Chrome": merge(*chrome, *couplings),
        "Hose": merge(hose, *ribs),
        "Rod": rod,
        "Handle": merge(bar, hub),
        "Grips": merge(*grips),
    }


PROPS = {"PumpBalloon": pump_balloon, "AirTank": air_tank, "Plunger": plunger}

COLORS = {
    "Skin": (255, 80, 95), "Eyes": (255, 255, 255), "Pupils": (35, 25, 45), "Shine": (255, 255, 255),
    "Smile": (120, 25, 45), "Ooh": (110, 20, 40), "Brows": (90, 30, 40), "Blush": (255, 150, 170),
    "Sweat": (120, 200, 255), "Gleam": (255, 255, 255), "Feet": (70, 60, 90), "Tank": (250, 245, 255), "TankBands": (255, 200, 60),
    "Brass": (230, 175, 70), "Dial": (255, 255, 250), "Ticks": (40, 35, 60), "DialRed": (255, 70, 70),
    "Needle": (235, 40, 50), "PumpBase": (60, 55, 75), "Barrel": (255, 80, 95), "Chrome": (215, 220, 235),
    "Hose": (60, 55, 75), "Rod": (225, 230, 240), "Handle": (250, 250, 255), "Grips": (45, 40, 55),
}


# ============================================================================ the carnival
# The fairground around the stage: a bandshell with telescoping striped arches and chasing bulbs
# behind the balloons, a round striped stage deck, team grandstands with peg-doll fans, big-top
# tents, game booths, candy-striped light poles strung with bunting and a Ferris wheel on the
# skyline. Bulbs come in two pieces (BulbsA / BulbsB) so the client can chase them.

def sheet(points: np.ndarray, normals: np.ndarray, thickness: float) -> Mesh:
    """A closed slab around a curved grid of points (rows x cols x 3) with outward unit normals:
    front faces along the normals, back faces against them and walls round the edges, all facing
    outward. Walls get their own vertices so the slab keeps crisp edges."""
    rows, cols = points.shape[0], points.shape[1]
    top = (points + normals * thickness / 2).reshape(-1, 3)
    bottom = (points - normals * thickness / 2).reshape(-1, 3)
    allv = np.vstack([top, bottom])
    count = rows * cols
    faces = []

    def oriented(tri, ref):
        a, b, c = allv[tri[0]], allv[tri[1]], allv[tri[2]]
        return tri if np.dot(np.cross(b - a, c - a), ref) >= 0 else (tri[0], tri[2], tri[1])

    for i in range(rows - 1):
        for j in range(cols - 1):
            a, b, c, d = i * cols + j, (i + 1) * cols + j, i * cols + j + 1, (i + 1) * cols + j + 1
            ref = normals[i, j] + normals[i + 1, j + 1] + normals[i + 1, j] + normals[i, j + 1]
            for tri in ((a, b, d), (a, d, c)):
                faces.append(oriented(tri, ref))
                faces.append(oriented(tuple(t + count for t in tri), -ref))
    # The rim: each wall quad faces away from the grid's inside.
    edges = []
    for i in range(rows - 1):
        edges.append(((i, 0), (i + 1, 0), (i, 1)))
        edges.append(((i, cols - 1), (i + 1, cols - 1), (i, cols - 2)))
    for j in range(cols - 1):
        edges.append(((0, j), (0, j + 1), (1, j)))
        edges.append(((rows - 1, j), (rows - 1, j + 1), (rows - 2, j)))
    wall_v = []
    for (p, q, inner) in edges:
        p0, q0 = points[p], points[q]
        ref = (p0 + q0) / 2 - points[inner]
        n0, n1 = normals[p], normals[q]
        quad = np.array([p0 + n0 * thickness / 2, q0 + n1 * thickness / 2, q0 - n1 * thickness / 2, p0 - n0 * thickness / 2])
        base = len(allv) + len(wall_v)
        wall_v.extend(quad)
        for tri in ((0, 1, 2), (0, 2, 3)):
            a, b, c = quad[tri[0]], quad[tri[1]], quad[tri[2]]
            normal = np.cross(b - a, c - a)
            if np.linalg.norm(normal) < 1e-9:
                continue
            t = tri if np.dot(normal, ref) >= 0 else (tri[0], tri[2], tri[1])
            faces.append(tuple(base + k for k in t))
    v = np.vstack([allv, np.array(wall_v)]) if wall_v else allv
    return Mesh(v, faces)


def unit(v: np.ndarray) -> np.ndarray:
    return v / (np.linalg.norm(v, axis=-1, keepdims=True) + 1e-12)


def revolve_patch(profile: list[tuple[float, float]], a0: float, a1: float, steps: int, thickness: float) -> Mesh:
    """A slab of a surface of revolution between angles a0..a1 (radians, 0 = +X, turning towards
    +Z), from a (radius, y) profile running upward; its front faces point away from the axis."""
    pts, nrm = [], []
    prof = np.array(profile, dtype=float)
    for k in range(steps + 1):
        a = a0 + (a1 - a0) * k / steps
        radial = np.array([math.cos(a), 0.0, math.sin(a)])
        row_p, row_n = [], []
        for i, (r, y) in enumerate(prof):
            lo, hi = prof[max(i - 1, 0)], prof[min(i + 1, len(prof) - 1)]
            dr, dy = hi[0] - lo[0], hi[1] - lo[1]
            row_p.append(radial * r + np.array([0.0, y, 0.0]))
            row_n.append(radial * dy - np.array([0.0, 1.0, 0.0]) * dr)
        pts.append(row_p)
        nrm.append(row_n)
    return sheet(np.array(pts), unit(np.array(nrm)), thickness)


def bulb_ring(points: list[np.ndarray], radius: float) -> tuple[Mesh, Mesh]:
    """Bulbs at the given points, alternating between the A and B pieces."""
    a = [sphere(radius, 5, 8).translate(*p) for p in points[0::2]]
    b = [sphere(radius, 5, 8).translate(*p) for p in points[1::2]]
    return merge(*a), merge(*b)


def pennant(width: float, height: float, depth: float = 0.08) -> Mesh:
    """A triangle flag hanging down from y = 0, in the XY plane."""
    return extrude([(-width / 2, 0.0), (width / 2, 0.0), (0.0, -height)], depth)


# ---------------------------------------------------------------------------- the bandshell

SHELL_AX, SHELL_AY = 50.0, 42.0  # the front arch's half width and height
SHELL_BANDS = 5
SHELL_DEPTH = 4.0  # each band steps this far back


def arch_point(scale: float, z: float, t: float) -> np.ndarray:
    """A point on a half-ellipse arch (t = 0 at +X on the ground, pi at -X)."""
    return np.array([SHELL_AX * scale * math.cos(t), SHELL_AY * scale * math.sin(t), z])


def pump_bandshell():
    """The stage's backdrop: a concert bandshell of telescoping half-arches, violet and cream, each
    step trimmed in gold with chasing bulbs, a sunburst back wall, a crest star on top, a cream
    outer shell and four stage spotlights. Open side faces -Z (towards the players)."""
    ts = np.linspace(0.0, math.pi, 41)
    facing = np.array([0.0, 0.0, -1.0])
    bands_a, bands_b, steps, bulbs = [], [], [], []
    scale = 1.0
    for k in range(SHELL_BANDS):
        z0, z1 = k * SHELL_DEPTH, (k + 1) * SHELL_DEPTH
        s0, s1 = scale, scale - 0.035
        pts = np.array([[arch_point(s0, z0, t), arch_point(s1, z1, t)] for t in ts])
        # The inner face (towards the stage) points at the arch's middle and forward (-Z).
        nrm = []
        for t in ts:
            inward = unit(-np.array([math.cos(t) / SHELL_AX, math.sin(t) / SHELL_AY, 0.0]))
            n = unit(inward * SHELL_DEPTH + facing * (0.035 * (SHELL_AX + SHELL_AY) / 2))
            nrm.append([n, n])
        band = sheet(pts, np.array(nrm), 0.6)
        (bands_a if k % 2 == 0 else bands_b).append(band)
        # The step to the next (smaller) arch: a flat half-ring facing -Z, gold, with bulbs.
        s2 = s1 - 0.065
        step_pts = np.array([[arch_point(s1, z1, t), arch_point(s2, z1, t)] for t in ts])
        steps.append(sheet(step_pts, np.tile(facing, (len(ts), 2, 1)), 0.5))
        mid = (s1 + s2) / 2
        count = max(8, int(math.pi * (SHELL_AX + SHELL_AY) / 2 * mid / 3.2))
        bulbs += [arch_point(mid, z1 - 0.45, t) for t in np.linspace(0.04, math.pi - 0.04, count)]
        scale = s2
    back_scale = scale
    back_z = SHELL_BANDS * SHELL_DEPTH

    # Sunburst back wall: rays from the floor's middle, alternating colors, and a gold hub.
    rays_a, rays_b = [], []
    rays = 14
    for i in range(rays):
        t0, t1 = math.pi * i / rays, math.pi * (i + 1) / rays
        poly = [(0.0, 0.0)] + [tuple(arch_point(back_scale + 0.01, 0, t)[:2]) for t in np.linspace(t0, t1, 4)]
        ray = extrude(poly, 0.6).translate(0, 0, back_z + 0.2)
        (rays_a if i % 2 == 0 else rays_b).append(ray)
    hub = extrude([(math.cos(a) * 4.5, math.sin(a) * 4.5) for a in np.linspace(0, math.pi, 17)], 0.4).translate(0, 0, back_z - 0.3)

    # The front frame: a thick violet arch around the outermost band, gold-edged, with big bulbs.
    frame_pts = np.array([[arch_point(1.075, -0.5, t), arch_point(1.0, -0.5, t)] for t in ts])
    frame = sheet(frame_pts, np.tile(facing, (len(ts), 2, 1)), 1.6)
    edge = [tube([tuple(arch_point(s, -1.35, t)) for t in ts], 0.32, 8) for s in (1.075, 1.0)]
    bulbs_front = [arch_point(1.0375, -1.5, t) for t in np.linspace(0.03, math.pi - 0.03, 46)]

    # Outer shell (seen from the sides and above): one cream surface over the whole funnel.
    outer = np.array([[arch_point(1.075, 0.3, t), arch_point(back_scale + 0.06, back_z + 0.9, t)] for t in ts])
    outer_n = []
    for t in ts:
        out = unit(np.array([math.cos(t) / SHELL_AX, math.sin(t) / SHELL_AY, 0.0]))
        n = unit(out * back_z + np.array([0.0, 0.0, 1.0]) * ((1.075 - back_scale) * (SHELL_AX + SHELL_AY) / 2))
        outer_n.append([n, n])
    facade = sheet(outer, np.array(outer_n), 0.8)
    back = extrude([(0.0, 0.0)] + [tuple(arch_point(back_scale + 0.07, 0, t)[:2]) for t in ts], 0.6).translate(0, 0, back_z + 1.1)

    # Crest: a big gold star on the top with two small ones.
    crest = [extrude(star(6.5, 3.0), 1.4).translate(0, SHELL_AY * 1.075 + 5.0, -0.5)]
    for side in (-1, 1):
        crest.append(extrude(star(3.0, 1.4), 1.0).rotate("z", side * 12).translate(side * 13.5, SHELL_AY * 1.04 + 2.4, -0.4))
    crest_bulb = sphere(0.75, 6, 10).translate(0.0, SHELL_AY * 1.075 + 5.0, -1.4)

    # Stage spotlights on short stands either side of the arch, aimed at the middle of the stage.
    cans, lenses = [], []
    for side in (-1, 1):
        for (x, z) in ((44.0, -5.0), (36.0, -9.0)):
            stand = merge(cylinder(1.3, 0.4, 16, 0.1), cylinder(0.22, 3.6, 10))
            body = merge(cylinder(1.25, 3.2, 18, 0.25).translate(0, -1.6, 0), torus(1.2, 0.18, 18, 6).translate(0, -1.6, 0))
            lens = cylinder(1.0, 0.2, 18).translate(0, -1.75, 0)
            for m in (body, lens):
                m.rotate("x", -70).rotate("y", side * -40).translate(0, 4.6, 0)
            yoke = torus(1.45, 0.16, 18, 6, 180).rotate("x", 90).rotate("y", side * -40 + 90).translate(0, 4.6, 0)
            cans.append(merge(stand, body, yoke).translate(side * x, 0, z))
            lenses.append(lens.translate(side * x, 0, z))

    bulbs_a, bulbs_b = bulb_ring(bulbs + bulbs_front, 0.45)
    return {
        "ShellA": merge(*bands_a, *rays_a),
        "ShellB": merge(*bands_b, *rays_b),
        "Steps": merge(*steps, *edge, hub),
        "Frame": frame,
        "Facade": merge(facade, back),
        "Crest": merge(*crest),
        "BulbsA": merge(bulbs_a, crest_bulb),
        "BulbsB": bulbs_b,
        "Cans": merge(*cans),
        "Lens": merge(*lenses),
    }


# ---------------------------------------------------------------------------- the stage deck

DECK_RADIUS = 40.0
DECK_TOP = 1.2


def pump_stage_deck():
    """The round stage floor (top at y = 1.2, radius 40; the server scales it to the stage): a soft
    sunburst of cream and butter wedges, a gold lip, a striped skirt and a ring of bulbs."""
    wedges_a, wedges_b = [], []
    count = 20
    for i in range(count):
        a0, a1 = 2 * math.pi * i / count, 2 * math.pi * (i + 1) / count
        poly = [(0.0, 0.0)] + [(math.cos(a) * (DECK_RADIUS - 1.6), math.sin(a) * (DECK_RADIUS - 1.6)) for a in np.linspace(a0, a1, 5)]
        wedge = extrude(poly, 0.5).rotate("x", -90).translate(0, DECK_TOP - 0.25, 0)
        (wedges_a if i % 2 == 0 else wedges_b).append(wedge)
    lip = lathe([(DECK_RADIUS - 1.9, DECK_TOP - 0.4), (DECK_RADIUS + 0.05, DECK_TOP - 0.35), (DECK_RADIUS + 0.05, DECK_TOP - 0.1),
                 (DECK_RADIUS - 0.25, DECK_TOP + 0.16), (DECK_RADIUS - 1.6, DECK_TOP + 0.16), (DECK_RADIUS - 1.9, DECK_TOP + 0.08),
                 (DECK_RADIUS - 1.9, DECK_TOP - 0.4)], 96)
    skirt_a, skirt_b = [], []
    panels = 48
    for i in range(panels):
        a0, a1 = 2 * math.pi * i / panels, 2 * math.pi * (i + 1) / panels
        panel = revolve_patch([(DECK_RADIUS - 0.2, 0.0), (DECK_RADIUS - 0.2, DECK_TOP - 0.3)], a0, a1, 2, 0.3)
        (skirt_a if i % 2 == 0 else skirt_b).append(panel)
    ring = [np.array([math.cos(a) * (DECK_RADIUS - 0.95), DECK_TOP + 0.36, math.sin(a) * (DECK_RADIUS - 0.95)])
            for a in np.linspace(0, 2 * math.pi, 72, endpoint=False)]
    bulbs_a, bulbs_b = bulb_ring(ring, 0.3)
    return {
        "DeckA": merge(*wedges_a),
        "DeckB": merge(*wedges_b),
        "Lip": lip,
        "SkirtA": merge(*skirt_a),
        "SkirtB": merge(*skirt_b),
        "BulbsA": bulbs_a,
        "BulbsB": bulbs_b,
    }


# ---------------------------------------------------------------------------- team grandstand

def stripe_roof(x0: float, x1: float, stripes: int, front: tuple[float, float], back: tuple[float, float], thickness: float):
    """A flat sloped roof of stripes along X, from front (z, y) to back (z, y). Returns (A, B)."""
    a, b = [], []
    slope = np.array([0.0, back[1] - front[1], back[0] - front[0]])
    n = unit(np.cross(np.array([1.0, 0.0, 0.0]), slope))
    if n[1] < 0:
        n = -n
    for i in range(stripes):
        xa, xb = x0 + (x1 - x0) * i / stripes, x0 + (x1 - x0) * (i + 1) / stripes
        pts = np.array([[[xa, front[1], front[0]], [xa, back[1], back[0]]], [[xb, front[1], front[0]], [xb, back[1], back[0]]]])
        (a if i % 2 == 0 else b).append(sheet(pts, np.tile(n, (2, 2, 1)), thickness))
    return a, b


def scallops(x0: float, x1: float, count: int, y: float, z: float, radius: float) -> tuple[list[Mesh], list[Mesh]]:
    """A valance of half-round flaps hanging from y along X, alternating (A, B)."""
    a, b = [], []
    width = (x1 - x0) / count
    for i in range(count):
        cx = x0 + width * (i + 0.5)
        arc = [(cx + math.cos(t) * width / 2, y - math.sin(t) * radius) for t in np.linspace(math.pi, 0, 9)[1:-1]]
        flap = extrude([(cx - width / 2, y)] + arc + [(cx + width / 2, y)], 0.2).translate(0, 0, z)
        (a if i % 2 == 0 else b).append(flap)
    return a, b


def peg_fan(x: float, y: float, z: float, seed: int):
    """A peg-doll fan: a capsule body and a ball head, some cheering with both arms up."""
    rng = np.random.default_rng(seed)
    body = capsule(1.7, 0.55, 10).translate(x, y + 0.85, z)
    head = sphere(0.5, 6, 10).translate(x, y + 2.15, z)
    arms = []
    if rng.random() < 0.6:
        for side in (-1, 1):
            arms.append(taper([(x + side * 0.4, y + 1.3, z), (x + side * 0.8, y + 2.1, z - 0.1), (x + side * 0.9, y + 2.6, z - 0.15)], 0.16, 0.13, 6))
    return body, head, arms


def pump_grandstand():
    """A team's grandstand facing -Z: four tiers of team-colored benches on a white frame, a
    striped canopy with a scalloped valance and pennants, and a crowd of peg-doll fans."""
    width = 24.0
    frame, seats, heads = [], [], []
    fans = [[], [], []]
    tiers = 4
    fan = 0
    for i in range(tiers):
        y = 0.9 + 1.6 * i
        z = -4.2 + 2.5 * i
        frame.append(rounded_box(width - 1.0, y, 2.5, 0.12, 2).translate(0, y / 2, z + 0.1))
        seats.append(rounded_box(width - 1.4, 0.45, 1.3, 0.18, 3).translate(0, y + 0.22, z - 0.2))
        for j, x in enumerate(np.linspace(-width / 2 + 2.2, width / 2 - 2.2, 7)):
            if (i * 7 + j) % 5 == 3:
                continue  # a few empty seats
            body, head, arms = peg_fan(x + (0.4 if i % 2 else -0.4), y + 0.45, z + 0.35, i * 13 + j)
            fans[fan % 3].extend([body, *arms])
            heads.append(head)
            fan += 1
    top = 0.9 + 1.6 * tiers
    for side in (-1, 1):  # stepped side walls
        wall = extrude([(-5.8, 0.0), (5.6, 0.0), (5.6, top + 0.3), (3.2, top + 0.3), (-5.8, 1.4)], 0.6)
        frame.append(wall.rotate("y", -90).translate(side * (width / 2 - 0.2), 0, 0))
    frame.append(rounded_box(width, top + 0.4, 0.6, 0.15, 2).translate(0, (top + 0.4) / 2, 5.7))
    posts = []
    for x in (-width / 2 + 0.4, 0.0, width / 2 - 0.4):
        posts.append(cylinder(0.28, 15.2, 10, 0.05).translate(x, 0, -6.2))
        posts.append(cylinder(0.28, 16.6, 10, 0.05).translate(x, 0, 5.8))
    roof_a, roof_b = stripe_roof(-width / 2 - 0.8, width / 2 + 0.8, 10, (-7.2, 15.0), (6.4, 16.8), 0.35)
    val_a, val_b = scallops(-width / 2 - 0.8, width / 2 + 0.8, 14, 15.0, -7.25, 1.1)
    flags, poles = [], []
    for x in (-width / 2 + 0.4, 0.0, width / 2 - 0.4):
        poles.append(cylinder(0.12, 3.6, 8).translate(x, 16.6, 5.8))
        poles.append(sphere(0.26, 5, 8).translate(x, 20.3, 5.8))
        flags.append(extrude([(0.0, 0.0), (2.6, -0.65), (0.0, -1.3)], 0.08).translate(x + 0.1, 20.0, 5.8))
    return {
        "Frame": merge(*frame, *posts, *poles),
        "Seats": merge(*seats),
        "CanopyA": merge(*roof_a, *val_a),
        "CanopyB": merge(*roof_b, *val_b),
        "Flags": merge(*flags),
        "FansA": merge(*fans[0]),
        "FansB": merge(*fans[1]),
        "FansC": merge(*fans[2]),
        "Heads": merge(*heads),
    }


# ---------------------------------------------------------------------------- big top tent

def pump_big_top():
    """A circus big top: striped walls and a drooping striped roof, a scalloped valance, a dark
    doorway on the front (-Z), a gold-tipped king pole and a pennant."""
    radius, wall = 14.0, 7.0
    stripes = 18
    tent_a, tent_b = [], []
    roof_profile = [(radius + 0.9 - (radius - 0.3) * t, wall + 0.4 + 15.5 * (t ** 1.45)) for t in np.linspace(0, 1, 12)]
    for i in range(stripes):
        a0, a1 = 2 * math.pi * i / stripes, 2 * math.pi * (i + 1) / stripes
        side = revolve_patch([(radius, 0.0), (radius, wall + 0.6)], a0, a1, 3, 0.3)
        roof = revolve_patch(roof_profile, a0, a1, 3, 0.3)
        (tent_a if i % 2 == 0 else tent_b).extend([side, roof])
    flaps_a, flaps_b = [], []
    flaps = 36
    for i in range(flaps):
        a = 2 * math.pi * (i + 0.5) / flaps
        w = 2 * math.pi * (radius + 1.0) / flaps
        arc = [(math.cos(t) * w / 2, -math.sin(t) * 1.1) for t in np.linspace(math.pi, 0, 9)[1:-1]]
        flap = extrude([(-w / 2, 0.0)] + arc + [(w / 2, 0.0)], 0.15).rotate("y", -math.degrees(a) - 90)
        flap = flap.translate(math.cos(a) * (radius + 1.0), wall + 0.45, math.sin(a) * (radius + 1.0))
        (flaps_a if i % 2 == 0 else flaps_b).append(flap)
    trim = [torus(radius + 0.95, 0.18, 72, 6).translate(0, wall + 0.42, 0), torus(radius + 0.05, 0.2, 72, 6).translate(0, 0.15, 0)]
    arch = [(math.cos(t) * 2.6, 4.2 + math.sin(t) * 2.0) for t in np.linspace(0, math.pi, 9)[1:-1]]
    door = extrude([(-2.6, 0.0), (2.6, 0.0), (2.6, 4.2)] + arch + [(-2.6, 4.2)], 0.8).translate(0, 0, -radius + 0.15)
    door_trim = tube([(2.75, 0.0, -radius - 0.3)] + [(math.cos(t) * 2.75, 4.2 + math.sin(t) * 2.15, -radius - 0.3) for t in np.linspace(0, math.pi, 13)]
                     + [(-2.75, 0.0, -radius - 0.3)], 0.2, 6)
    pole = merge(cylinder(0.35, 5.5, 10).translate(0, wall + 15.0, 0), sphere(0.7, 6, 10).translate(0, wall + 20.7, 0))
    flag = extrude([(0.0, 0.0), (4.0, -1.0), (0.0, -2.0)], 0.1).translate(0.2, wall + 20.4, 0)
    return {
        "TentA": merge(*tent_a, *flaps_a),
        "TentB": merge(*tent_b, *flaps_b),
        "Trim": merge(*trim, pole, door_trim),
        "Door": door,
        "Flag": flag,
    }


# ---------------------------------------------------------------------------- game booth

def pump_game_booth():
    """A carnival game booth facing -Z: a striped counter, a striped awning with a scalloped
    valance, a sign star and two shelves of round plush prizes."""
    width, depth = 10.0, 6.0
    counter_a, counter_b = [], []
    panels = 6
    for i in range(panels):
        x0 = -width / 2 + width * i / panels
        panel = rounded_box(width / panels, 3.4, 0.5, 0.08, 2).translate(x0 + width / panels / 2, 1.7, -depth / 2)
        (counter_a if i % 2 == 0 else counter_b).append(panel)
    frame = [rounded_box(width + 0.6, 0.35, 1.6, 0.12, 2).translate(0, 3.55, -depth / 2 + 0.2),
             rounded_box(width, 8.0, 0.4, 0.1, 2).translate(0, 4.0, depth / 2)]
    for side in (-1, 1):
        frame.append(rounded_box(0.4, 3.4, depth, 0.1, 2).translate(side * (width / 2 - 0.2), 1.7, 0))
        frame.append(cylinder(0.25, 8.2, 10).translate(side * (width / 2 - 0.1), 0, -depth / 2 + 0.1))
    shelves = [rounded_box(width - 1.0, 0.25, 1.2, 0.08, 2).translate(0, y, depth / 2 - 0.8) for y in (3.4, 5.4)]
    prizes_a, prizes_b = [], []
    for row, y in enumerate((3.55, 5.55)):
        for i, x in enumerate(np.linspace(-width / 2 + 1.4, width / 2 - 1.4, 6)):
            z = depth / 2 - 0.8
            plush = merge(sphere(0.7, 6, 10).translate(x, y + 0.7, z), sphere(0.25, 4, 8).translate(x - 0.45, y + 1.35, z),
                          sphere(0.25, 4, 8).translate(x + 0.45, y + 1.35, z))
            (prizes_a if (i + row) % 2 == 0 else prizes_b).append(plush)
    roof_a, roof_b = stripe_roof(-width / 2 - 0.6, width / 2 + 0.6, 7, (-depth / 2 - 1.4, 8.2), (depth / 2 + 0.2, 9.4), 0.25)
    val_a, val_b = scallops(-width / 2 - 0.6, width / 2 + 0.6, 9, 8.2, -depth / 2 - 1.45, 0.8)
    sign = extrude(star(1.5, 0.7), 0.4).translate(0, 10.6, -depth / 2 - 0.2)
    return {
        "BoothA": merge(*counter_a, *roof_a, *val_a),
        "BoothB": merge(*counter_b, *roof_b, *val_b),
        "Frame": merge(*frame, *shelves),
        "PrizesA": merge(*prizes_a),
        "PrizesB": merge(*prizes_b),
        "Sign": sign,
    }


# ---------------------------------------------------------------------------- light pole + bunting

POLE_HEIGHT = 15.0
POLE_HOOK = 13.6  # where bunting ties on


def pump_light_pole():
    """A candy-striped lamp pole: a gold foot, red and cream bands, a crown of bulbs and a star."""
    foot = merge(cylinder(0.9, 0.35, 16, 0.1), cylinder(0.55, 0.9, 14, 0.1).translate(0, 0.3, 0))
    bands_a, bands_b = [], []
    bands = 9
    for i in range(bands):
        y0 = 1.1 + (POLE_HOOK - 1.1) * i / bands
        y1 = 1.1 + (POLE_HOOK - 1.1) * (i + 1) / bands
        (bands_a if i % 2 == 0 else bands_b).append(cylinder(0.3, y1 - y0, 12).translate(0, y0, 0))
    crown = merge(torus(1.1, 0.13, 24, 6).translate(0, POLE_HOOK + 0.2, 0), cylinder(0.4, 0.4, 12, 0.08).translate(0, POLE_HOOK, 0),
                  cylinder(0.12, 0.8, 8).translate(0, POLE_HOOK + 0.4, 0))
    ring = [np.array([math.cos(a) * 1.1, POLE_HOOK + 0.55, math.sin(a) * 1.1]) for a in np.linspace(0, 2 * math.pi, 8, endpoint=False)]
    bulbs_a, bulbs_b = bulb_ring(ring, 0.3)
    top = extrude(star(0.9, 0.42), 0.3).translate(0, POLE_HEIGHT - 0.9, 0)
    return {
        "Foot": merge(foot, crown, top),
        "PoleA": merge(*bands_a),
        "PoleB": merge(*bands_b),
        "BulbsA": bulbs_a,
        "BulbsB": bulbs_b,
    }


BUNTING_SPAN = 24.0
BUNTING_SAG = 3.0


def pump_bunting():
    """A string of pennants spanning 24 studs along X (both ends at the top of the mesh), sagging
    3 studs; four flag pieces in turn, so each string can take any colors."""
    def at(x: float) -> float:
        u = x / (BUNTING_SPAN / 2)
        return -BUNTING_SAG * (1 - u * u)

    xs = np.linspace(-BUNTING_SPAN / 2, BUNTING_SPAN / 2, 25)
    string = tube([(x, at(x), 0.0) for x in xs], 0.07, 6)
    flags = [[], [], [], []]
    count = 12
    for i in range(count):
        x = -BUNTING_SPAN / 2 + BUNTING_SPAN * (i + 0.5) / count
        slope = math.degrees(math.atan((at(x + 0.1) - at(x - 0.1)) / 0.2))
        flags[i % 4].append(pennant(1.55, 2.0).rotate("z", slope).translate(x, at(x) + 0.02, 0))
    return {
        "String": string,
        "FlagA": merge(*flags[0]),
        "FlagB": merge(*flags[1]),
        "FlagC": merge(*flags[2]),
        "FlagD": merge(*flags[3]),
    }


# ---------------------------------------------------------------------------- Ferris wheel

def pump_ferris_wheel():
    """A Ferris wheel for the skyline, facing -Z: white A-frame legs, a double rim with spokes and
    bulbs, a gold hub and twelve gondolas in three colors."""
    hub_y, rim = 34.0, 28.0
    legs = []
    for z in (-3.2, 3.2):
        for side in (-1, 1):
            legs.append(taper([(side * 17.0, 0.0, z * 1.6), (side * 0.6, hub_y, z)], 0.9, 0.55, 10))
        legs.append(tube([(-11.0, 11.0, z * 1.4), (11.0, 11.0, z * 1.4)], 0.35, 8))
    legs.append(tube([(0, hub_y, -3.6), (0, hub_y, 3.6)], 0.6, 12))
    feet = [rounded_box(5.0, 0.8, 13.0, 0.2, 2).translate(side * 17.0, 0.4, 0) for side in (-1, 1)]
    wheel = []
    for z in (-2.0, 2.0):
        wheel.append(torus(rim, 0.35, 96, 8).rotate("x", 90).translate(0, hub_y, z))
        wheel.append(torus(rim * 0.62, 0.22, 64, 6).rotate("x", 90).translate(0, hub_y, z))
        for i in range(24):
            a = 2 * math.pi * i / 24
            wheel.append(tube([(0, hub_y, z), (math.cos(a) * rim, hub_y + math.sin(a) * rim, z)], 0.16, 5))
    hub = merge(cylinder(2.0, 5.6, 24, 0.4).rotate("x", 90).translate(0, hub_y, 2.8), extrude(star(2.6, 1.3), 0.5).translate(0, hub_y, -3.0))
    cars = [[], [], []]
    for i in range(12):
        a = 2 * math.pi * i / 12 + math.pi / 12
        px, py = math.cos(a) * rim, hub_y + math.sin(a) * rim
        car = merge(
            rounded_box(3.2, 2.0, 3.4, 0.5, 3).translate(px, py - 3.4, 0),
            lathe([(0.0, -1.6), (1.9, -1.6), (1.7, -1.2), (1.0, -0.8), (0.0, -0.7)], 16).translate(px, py, 0),
            cylinder(0.12, 1.2, 6).translate(px, py - 2.4, 0),
            tube([(px, py - 0.8, -2.0), (px, py, -2.0), (px, py, 2.0), (px, py - 0.8, 2.0)], 0.14, 6),
        )
        cars[i % 3].append(car)
    ring = [np.array([math.cos(a) * (rim + 0.55), hub_y + math.sin(a) * (rim + 0.55), -2.0]) for a in np.linspace(0, 2 * math.pi, 48, endpoint=False)]
    bulbs_a, bulbs_b = bulb_ring(ring, 0.42)
    return {
        "Frame": merge(*legs, *feet),
        "Wheel": merge(*wheel),
        "Hub": hub,
        "CarsA": merge(*cars[0]),
        "CarsB": merge(*cars[1]),
        "CarsC": merge(*cars[2]),
        "BulbsA": bulbs_a,
        "BulbsB": bulbs_b,
    }


PROPS.update({
    "PumpBandshell": pump_bandshell,
    "PumpStageDeck": pump_stage_deck,
    "PumpGrandstand": pump_grandstand,
    "PumpBigTop": pump_big_top,
    "PumpGameBooth": pump_game_booth,
    "PumpLightPole": pump_light_pole,
    "PumpBunting": pump_bunting,
    "PumpFerrisWheel": pump_ferris_wheel,
})

COLORS.update({
    "ShellA": (128, 82, 214), "ShellB": (255, 240, 214), "Steps": (255, 196, 64), "Frame": (250, 248, 255),
    "Facade": (255, 244, 226), "Crest": (255, 200, 60), "BulbsA": (255, 246, 190), "BulbsB": (255, 214, 120),
    "Cans": (60, 52, 80), "Lens": (255, 250, 210), "DeckA": (255, 244, 222), "DeckB": (255, 226, 170), "Lip": (255, 196, 64),
    "SkirtA": (128, 82, 214), "SkirtB": (255, 240, 214), "Seats": (255, 80, 95), "CanopyA": (255, 80, 95),
    "CanopyB": (255, 250, 245), "Flags": (255, 80, 95), "FansA": (255, 170, 80), "FansB": (120, 200, 255),
    "FansC": (190, 140, 255), "Heads": (255, 214, 180), "TentA": (235, 60, 75), "TentB": (255, 246, 230), "Trim": (255, 196, 64),
    "Door": (70, 40, 90), "Flag": (255, 200, 60), "BoothA": (60, 170, 230), "BoothB": (255, 250, 240), "PrizesA": (255, 140, 190),
    "PrizesB": (120, 220, 160), "Sign": (255, 200, 60), "Foot": (255, 196, 64), "PoleA": (235, 60, 75), "PoleB": (255, 246, 230),
    "String": (250, 250, 250), "FlagA": (235, 60, 75), "FlagB": (255, 200, 60), "FlagC": (60, 170, 230), "FlagD": (90, 200, 120),
    "Wheel": (250, 248, 255), "Hub": (255, 196, 64), "CarsA": (235, 60, 75), "CarsB": (60, 170, 230), "CarsC": (255, 200, 60),
})
