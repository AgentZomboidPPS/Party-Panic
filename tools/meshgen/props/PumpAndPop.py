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

from generate_meshes import Mesh, capsule, cylinder, icosphere, lathe, merge, rounded_box, sphere, torus, tube

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
