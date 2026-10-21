"""Lobby props: the plaza's paving, the fountain, the amusement-park skyline, the toys and the little
details that make the lobby feel alive. Matching specs: src/server/World/Props/Lobby.luau.

    python3 tools/meshgen/generate_meshes.py --only LobbyFountain,LobbyDuck

Units are studs, +Y is up, the base sits on y = 0 and -Z is the front. Names start with "Lobby" so
they never clash with a mini-game's props.
"""

import math

import numpy as np
from generate_meshes import (
    Mesh,
    capsule,
    extrude,
    star,
    cylinder,
    icosphere,
    lathe,
    lerp,
    merge,
    rounded_box,
    sd_capsule,
    sd_ellipsoid,
    smin,
    sphere,
    torus,
    weld,
)
from generate_meshes import sdf_mesh as _sdf_mesh
from generate_meshes import tube as _tube

TAU = 2 * math.pi


# ====================================================================== helpers

# Roblox culls back faces, so every face must point outward. The shared tube() and sdf_mesh() wind
# their faces inward (their signed volume is negative), so the lobby's props flip them.


def tube(points, radius: float, sides: int = 8) -> Mesh:
    mesh = _tube(points, radius, sides)
    mesh.f = mesh.f[:, ::-1].copy()
    return mesh


def sdf_mesh(sdf, lo, hi, step) -> Mesh:
    mesh = _sdf_mesh(sdf, lo, hi, step)
    mesh.f = mesh.f[:, ::-1].copy()
    return mesh


def orient(mesh: Mesh, center) -> Mesh:
    """Flips every face whose normal points toward `center` (for convex-ish closed shapes)."""
    tri = mesh.v[mesh.f]
    normal = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    outward = tri.mean(axis=1) - np.asarray(center, dtype=float)
    flip = np.einsum("ij,ij->i", normal, outward) < 0
    mesh.f[flip] = mesh.f[flip][:, ::-1]
    return mesh


def sector_tile(r0: float, r1: float, a0: float, a1: float, height: float, gap: float = 0.0) -> Mesh:
    """A flat paving tile shaped like a ring sector (angles in radians, measured from +X toward +Z),
    from y = 0 to y = `height`. `gap` trims each radial edge by half a gap, at a constant width."""
    half = gap / 2
    arc = (a1 - a0) * (r0 + r1) / 2
    segs = max(2, math.ceil(arc / 2.5))
    inner = np.linspace(a0 + half / r0, a1 - half / r0, segs + 1)
    outer = np.linspace(a0 + half / r1, a1 - half / r1, segs + 1)
    ring = [(math.cos(a) * r0, math.sin(a) * r0) for a in inner] + [(math.cos(a) * r1, math.sin(a) * r1) for a in outer[::-1]]
    return slab(ring, height)


def slab(polygon, height: float) -> Mesh:
    """A flat slab from a simple polygon in the XZ plane that is star-shaped around its centroid."""
    pts = np.array(polygon, dtype=float)
    n = len(pts)
    cx, cz = pts.mean(axis=0)
    verts = [(cx, height, cz), (cx, 0.0, cz)]
    verts += [(x, height, z) for x, z in pts] + [(x, 0.0, z) for x, z in pts]
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces += [(0, 2 + i, 2 + j), (1, 2 + n + j, 2 + n + i)]
        faces += [(2 + i, 2 + n + i, 2 + j), (2 + j, 2 + n + i, 2 + n + j)]
    mesh = Mesh(verts, faces, smooth=False)
    return orient(mesh, (cx, height / 2, cz))


def flat_ring(r0: float, r1: float, y0: float, y1: float, segments: int = 96) -> Mesh:
    """A flat annulus slab (closed), centered on the Y axis."""
    mesh = lathe([(r0, y0), (r1, y0), (r1, y1), (r0, y1), (r0, y0)], segments)
    mesh.smooth = False
    return mesh


def partial_lathe(profile, a0: float, a1: float, segments: int) -> Mesh:
    """Like `lathe`, but only from angle a0 to a1 (radians), with no seam closing."""
    verts, faces = [], []
    rows = len(profile)
    count = segments + 1
    for radius, y in profile:
        for s in range(count):
            a = lerp(a0, a1, s / segments)
            verts.append((math.cos(a) * radius, y, math.sin(a) * radius))
    for i in range(rows - 1):
        for s in range(segments):
            a = i * count + s
            b = a + 1
            c = a + count
            d = b + count
            faces += [(a, c, b), (b, c, d)]
    return Mesh(verts, faces)


def modulate(mesh: Mesh, fn) -> Mesh:
    """Scales each vertex's distance from the Y axis by fn(angle, y, radius)."""
    angle = np.arctan2(mesh.v[:, 2], mesh.v[:, 0])
    radius = np.hypot(mesh.v[:, 0], mesh.v[:, 2])
    k = fn(angle, mesh.v[:, 1], radius)
    mesh.v[:, 0] *= k
    mesh.v[:, 2] *= k
    return mesh


def ellipsoid(rx: float, ry: float, rz: float, rings: int = 10, segments: int = 16) -> Mesh:
    return sphere(1.0, rings, segments).scale(rx, ry, rz)


# ====================================================================== the plaza floor

GROUT = 0.32  # gap between tiles: the plaza disc shows through as grout lines


def lobby_pavers():
    """The promenade around the central court: four rings of curved tiles in two warm tones with a
    colored band, then a white stripe that edges the lawn. 0.1 thick and flat, so it lies on the
    grout disc without fighting it."""
    h = 0.1
    pieces = {"TileA": [], "TileB": [], "Band": [], "Stripe": []}
    edges = np.linspace(27.6, 44.0, 5)
    for ring in range(4):
        r0, r1 = edges[ring] + GROUT / 2, edges[ring + 1] - GROUT / 2
        count = 2 * round(TAU * (r0 + r1) / 2 / 5.0 / 2)  # even, so the checker pattern closes
        shift = 0.5 * (ring % 2)
        for i in range(count):
            a0, a1 = (i + shift) / count * TAU, (i + 1 + shift) / count * TAU
            key = "Band" if ring == 2 else ("TileA" if (i + ring) % 2 == 0 else "TileB")
            pieces[key].append(sector_tile(r0, r1, a0, a1, h, GROUT))
    pieces["Stripe"].append(flat_ring(44.3, 45.9, 0.0, h, 160))
    return {name: merge(*meshes) for name, meshes in pieces.items()}


def lobby_court():
    """The round court around the fountain: a sunburst of 16 rays in two colors, a ring of accent
    tiles hugging the fountain and a gold border. Flat, 0.1 thick. (Loose accent diamonds between the
    ray tips were tried and read as litter.)"""
    h = 0.1
    pieces = {"RayA": [], "RayB": [], "Accent": [], "Ring": []}
    for i in range(24):
        a0, a1 = i / 24 * TAU, (i + 1) / 24 * TAU
        pieces["Accent"].append(sector_tile(13.3, 14.6, a0, a1, h, GROUT))
    rays = 16
    for i in range(rays):
        a0, a1 = (i - 0.5) / rays * TAU, (i + 0.5) / rays * TAU
        # Each ray is a sector whose outer edge comes to a soft point, like a sunburst.
        half = GROUT / 2
        inner = np.linspace(a0 + half / 14.9, a1 - half / 14.9, 4)
        tip = (a0 + a1) / 2
        outline = [(math.cos(a) * 14.9, math.sin(a) * 14.9) for a in inner]
        for t in np.linspace(0, 1, 5)[1:-1]:
            a = lerp(a1 - half / 24.0, tip, t)
            r = lerp(23.0, 24.9, math.sin(t * math.pi / 2))
            outline.append((math.cos(a) * r, math.sin(a) * r))
        outline.append((math.cos(tip) * 24.9, math.sin(tip) * 24.9))
        for t in np.linspace(0, 1, 5)[1:-1][::-1]:
            a = lerp(a0 + half / 24.0, tip, t)
            r = lerp(23.0, 24.9, math.sin(t * math.pi / 2))
            outline.append((math.cos(a) * r, math.sin(a) * r))
        pieces["RayA" if i % 2 == 0 else "RayB"].append(slab(outline, h))
    pieces["Ring"].append(flat_ring(25.4, 27.5, 0.0, h, 128))
    return {name: merge(*meshes) for name, meshes in pieces.items()}


# ====================================================================== fountain

def lobby_fountain():
    """A scalloped stone basin with a fluted column and a gadrooned bowl; gold trims, pink medallions
    and a tiled pool floor. The water surfaces are separate glass parts (added in the game)."""
    lobes = 12

    def scallop(angle, y, radius):
        return np.where(radius > 10.5, 1 + 0.036 * np.cos(lobes * angle), 1.0)

    basin = lathe([(12.3, 0.0), (12.4, 0.25), (12.4, 1.9), (12.55, 2.05), (12.65, 2.3), (12.6, 2.55), (12.35, 2.75),
                   (11.6, 2.78), (11.35, 2.6), (11.25, 1.7), (11.1, 0.6), (10.65, 0.35)], 96)
    modulate(basin, scallop)

    column = lathe([(2.7, 0.3), (2.7, 0.85), (2.45, 1.05), (1.95, 1.2), (1.6, 1.45), (1.5, 1.7), (1.5, 5.3), (1.62, 5.5),
                    (1.85, 5.75), (1.95, 6.0)], 72)
    modulate(column, lambda a, y, r: np.where((y > 1.6) & (y < 5.4), 1 - 0.055 * (0.5 + 0.5 * np.cos(12 * a)), 1.0))

    bowl = lathe([(1.9, 6.0), (2.6, 6.25), (3.6, 6.6), (4.6, 7.1), (5.35, 7.6), (5.7, 7.95), (5.8, 8.2), (5.75, 8.4),
                  (5.5, 8.5), (5.25, 8.4), (5.1, 8.2), (4.6, 8.05)], 72)
    modulate(bowl, lambda a, y, r: np.where(y < 7.8, 1 + 0.045 * np.cos(16 * a) * np.clip((y - 6.1) / 1.2, 0, 1), 1.0))
    stone = merge(basin, column, bowl)

    lip = lathe([(12.56, 2.1), (12.74, 2.18), (12.74, 2.44), (12.56, 2.52)], 96)
    modulate(lip, scallop)
    band = lathe([(12.38, 0.3), (12.52, 0.36), (12.52, 0.62), (12.38, 0.68)], 96)
    modulate(band, scallop)
    trim = [lip, band, torus(2.62, 0.16, 48, 8).translate(0, 0.95, 0), torus(1.6, 0.12, 40, 8).translate(0, 5.45, 0),
            torus(5.72, 0.12, 64, 8).translate(0, 8.25, 0)]

    accents = []
    for i in range(lobes):
        a = i / lobes * TAU
        r = 12.4 * (1 + 0.036) - 0.03
        medallion = merge(cylinder(0.55, 0.16, 14).rotate("x", 90), torus(0.55, 0.07, 14, 5).rotate("x", 90).translate(0, 0, 0.1))
        accents.append(medallion.rotate("y", 90 - math.degrees(a)).translate(math.cos(a) * r, 1.25, math.sin(a) * r))
    # The pool floors: a little lower than the walls' inner edges so nothing is coplanar.
    pool = merge(cylinder(10.7, 0.05, 72).translate(0, 0.3, 0), cylinder(4.7, 0.05, 48).translate(0, 7.95, 0))
    return {"Stone": stone, "Trim": merge(*trim), "Accent": merge(*accents), "Pool": pool}


def lobby_duck():
    """A rubber duck, facing -Z, that floats in the fountain."""

    def body_sdf(p):
        d = sd_ellipsoid(p, (0, 0.62, 0.15), (0.78, 0.55, 0.95))
        d = smin(d, sd_ellipsoid(p, (0, 0.95, 0.85), (0.3, 0.35, 0.3)), 0.25)  # tail
        d = smin(d, sd_ellipsoid(p, (0, 1.45, -0.45), (0.48, 0.46, 0.46)), 0.28)  # head
        return d

    body = sdf_mesh(body_sdf, (-1.0, 0.0, -1.1), (1.0, 2.05, 1.35), 0.19)
    beak = merge(ellipsoid(0.26, 0.09, 0.3).translate(0, 1.38, -0.88), ellipsoid(0.22, 0.06, 0.24).translate(0, 1.27, -0.84))
    eyes = [icosphere(0.085, 1).translate(side * 0.22, 1.58, -0.83) for side in (-1, 1)]
    return {"Body": body, "Beak": beak, "Eyes": merge(*eyes)}


# ====================================================================== skyline: Ferris wheel

WHEEL_RADIUS = 32.0  # where the cabins hang
WHEEL_NODES = 36
WHEEL_CABINS = 12
WHEEL_HALF_DEPTH = 2.3
WHEEL_HUB_Y = 43.0  # axle height above the stand's base


def _wheel_point(angle: float, radius: float, z: float):
    return (math.cos(angle) * radius, math.sin(angle) * radius, z)


def lobby_ferris_wheel():
    """The turning part of the Ferris wheel, standing in the XY plane (axle along Z): twin lattice
    rims, spokes, a gold hub and rows of light bulbs. Its center is WHEEL_RADIUS + 0.5 above the
    base; cabins hang from every third rim node."""
    r_out, r_in, z = WHEEL_RADIUS, WHEEL_RADIUS - 4.5, WHEEL_HALF_DEPTH
    frame = []
    for side in (-1, 1):
        frame.append(torus(r_out, 0.42, 96, 8).rotate("x", 90).translate(0, 0, side * z))
        frame.append(torus(r_in, 0.3, 96, 6).rotate("x", 90).translate(0, 0, side * z))
        for k in range(WHEEL_NODES):
            a0 = k / WHEEL_NODES * TAU
            a1 = (k + 0.5) / WHEEL_NODES * TAU
            a2 = (k + 1) / WHEEL_NODES * TAU
            frame.append(tube([_wheel_point(a0, r_out, side * z), _wheel_point(a1, r_in, side * z), _wheel_point(a2, r_out, side * z)], 0.16, 5))
        for k in range(16):
            a = (k + 0.25) / 16 * TAU
            frame.append(tube([_wheel_point(a, 2.2, side * 1.6), _wheel_point(a, r_in, side * z)], 0.22, 6))
    for k in range(WHEEL_NODES):
        a = k / WHEEL_NODES * TAU
        frame.append(tube([_wheel_point(a, r_out, -z), _wheel_point(a, r_out, z)], 0.2 if k % 3 == 0 else 0.13, 6))
    hub = merge(
        cylinder(2.4, 4.2, 32, 0.4).translate(0, -2.1, 0).rotate("x", 90),
        cylinder(1.0, 7.4, 20, 0.2).translate(0, -3.7, 0).rotate("x", 90),
        *[cylinder(3.0, 0.5, 32, 0.15).translate(0, -0.25, 0).rotate("x", 90).translate(0, 0, side * 1.9) for side in (-1, 1)],
    )
    lights = []
    for side in (-1, 1):
        for k in range(72):
            a = (k + 0.5) / 72 * TAU
            lights.append(icosphere(0.34, 0).translate(*_wheel_point(a, r_out + 0.55, side * z)))
        for k in range(16):
            a = (k + 0.25) / 16 * TAU
            for t in (0.3, 0.5, 0.7, 0.9):
                lights.append(icosphere(0.26, 0).translate(*_wheel_point(a, lerp(2.2, r_in, t), side * lerp(1.6, z, t) + side * 0.3)))
    lift = r_out + 0.95
    pieces = {"Frame": merge(*frame), "Hub": hub, "Lights": merge(*lights)}
    return {name: mesh.translate(0, lift, 0) for name, mesh in pieces.items()}


def lobby_ferris_cabin():
    """A gondola that hangs from the wheel: the hang point is the top center (its pivot is the
    bottom center, 7.4 below). Faces -Z."""
    body = merge(
        rounded_box(4.4, 2.4, 3.4, 0.7, 5).translate(0, 1.2, 0),
        lathe([(0.0, 0.0), (1.2, 0.0), (1.5, 0.15), (0.0, 0.35)], 24).scale(1.5, 1, 1.1).translate(0, -0.05, 0),
    )
    rim = rounded_box(4.6, 0.32, 3.6, 0.14, 3).translate(0, 2.42, 0)
    posts = [tube([(x, 2.5, zz), (x * 0.92, 5.2, zz * 0.92)], 0.11, 6) for x in (-2.0, 2.0) for zz in (-1.5, 1.5)]
    # Profiles run counter-clockwise (bottom, outside, top) so faces point outward: Roblox culls back faces.
    roof = lathe([(0.0, 5.35), (2.6, 5.15), (2.8, 5.3), (2.65, 5.6), (2.0, 5.95), (0.0, 6.0)], 32).scale(1.0, 1.0, 0.8)
    roof_top = icosphere(0.32, 1).translate(0, 6.15, 0)
    hanger = merge(tube([(0, 6.2, 0), (0, 7.1, 0)], 0.16, 8), torus(0.28, 0.09, 16, 6).rotate("x", 90).translate(0, 7.15, 0))
    seat = rounded_box(3.6, 0.5, 1.1, 0.2, 3).translate(0, 1.95, 0.9)
    return {"Body": merge(body, seat), "Roof": merge(roof, roof_top), "Frame": merge(rim, *posts, hanger)}


def lobby_ferris_stand():
    """The Ferris wheel's two A-frames, a boarding platform and steps. The axle sits WHEEL_HUB_Y above
    the base, so the lowest cabin clears the boarding deck; the A-frames stand at z = +-4.6."""
    hub_y = WHEEL_HUB_Y
    legs = []
    for side in (-1, 1):
        top_z, foot_z = side * 4.6, side * 8.6

        def leg_point(x_sign: int, t: float):
            return (x_sign * lerp(16.0, 1.2, t), lerp(1.2, hub_y - 0.6, t), lerp(foot_z, top_z, t))

        for x in (-1, 1):
            legs.append(tube([leg_point(x, 0.0), leg_point(x, 1.0)], 0.6, 10))
        for t in (0.25, 0.5):
            legs.append(tube([leg_point(-1, t), leg_point(1, t)], 0.32, 8))
        legs.append(tube([leg_point(-1, 0.25), leg_point(1, 0.5)], 0.22, 6))
        legs.append(tube([leg_point(1, 0.25), leg_point(-1, 0.5)], 0.22, 6))
        legs.append(cylinder(1.7, 1.2, 24, 0.25).translate(0, -0.6, 0).rotate("x", 90).translate(0, hub_y, top_z + side * 0.3))
    legs.append(tube([(0, hub_y, -4.4), (0, hub_y, 4.4)], 0.75, 12))
    base = merge(
        rounded_box(40.0, 1.2, 20.0, 0.5).translate(0, 0.6, 0),
        rounded_box(12.0, 1.0, 8.0, 0.4).translate(0, 1.7, -4.0),
        *[rounded_box(10.0, 0.5, 2.0, 0.15).translate(0, 1.45 - i * 0.5, -8.9 - i * 1.6) for i in range(2)],
    )
    trim = [cylinder(1.2, 0.5, 20, 0.15).translate(x * 16.0, 1.2, side * 8.6) for x in (-1, 1) for side in (-1, 1)]
    trim.append(rounded_box(40.5, 0.35, 20.5, 0.16).translate(0, 0.95, 0))
    return {"Legs": merge(*legs), "Base": base, "Trim": merge(*trim)}


# ====================================================================== skyline: hot-air balloon

def lobby_hot_air_balloon():
    """A hot-air balloon with twelve striped gores, a gold band, ropes and a wicker basket."""
    profile = [(2.2, 6.2), (3.4, 7.4), (5.4, 9.6), (7.4, 12.4), (8.7, 15.2), (9.2, 18.0), (8.9, 20.6), (7.8, 23.0),
               (5.8, 25.0), (3.2, 26.3), (0.0, 26.7)]
    gores = 12
    envelope, stripes = [], []
    for g in range(gores):
        piece = partial_lathe(profile, g / gores * TAU, (g + 1) / gores * TAU, 6)
        (envelope if g % 2 == 0 else stripes).append(piece)
    band = merge(torus(3.0, 0.22, 32, 6).translate(0, 7.0, 0), torus(8.15, 0.18, 64, 6).translate(0, 13.2, 0))
    basket = merge(
        lathe([(0.0, 0.0), (1.35, 0.0), (1.55, 0.2), (1.62, 2.1), (1.45, 2.1), (1.4, 0.4), (0.0, 0.4)], 4).rotate("y", 45),
        torus(1.65, 0.16, 4, 6).rotate("y", 45).translate(0, 2.15, 0),
    )
    ropes = []
    for k in range(4):
        a = (k + 0.5) / 4 * TAU
        ropes.append(tube([(math.cos(a) * 1.5, 2.1, math.sin(a) * 1.5), (math.cos(a) * 2.25, 6.3, math.sin(a) * 2.25)], 0.06, 4))
    burner = merge(cylinder(0.5, 0.7, 12).translate(0, 3.2, 0), tube([(0, 2.1, 0), (0, 3.2, 0)], 0.08, 4),
                   cylinder(2.3, 0.12, 24).translate(0, 6.3, 0))  # closes the envelope's mouth
    return {"Envelope": merge(*envelope), "Stripes": merge(*stripes), "Band": band, "Basket": basket,
            "Ropes": merge(*ropes, burner)}


# ====================================================================== garden

def lobby_flower_bed():
    """An oval raised bed, 10 x 5: a stone curb, dark soil, leafy mounds and flowers in three colors
    with yellow hearts. Long axis along X."""
    rx, rz = 5.0, 2.5
    rng = np.random.default_rng(11)
    curb = lathe([(0.9, 0.0), (1.0, 0.0), (1.03, 0.55), (1.0, 0.72), (0.93, 0.72), (0.9, 0.6)], 48).scale(rx, 1, rz)
    soil = cylinder(0.92, 0.6, 40).scale(rx, 1, rz)
    leaves = []
    for k in range(9):
        t_ = (k + 0.5) / 9
        x = lerp(-0.78, 0.78, t_) * rx
        z = rng.uniform(-0.25, 0.25) * rz
        r = rng.uniform(1.05, 1.35)
        leaves.append(icosphere(r, 1, noise=0.08, seed=k).scale(1.0, 0.62, 1.0).translate(x, 0.75, z))
    flowers = {"FlowerA": [], "FlowerB": [], "FlowerC": []}
    hearts = []
    keys = list(flowers)
    count = 0
    while count < 30:
        x, z = rng.uniform(-1, 1, 2)
        if x * x + z * z > 0.62:
            continue
        px, pz = x * rx * 0.95, z * rz * 0.95
        y = 1.2 + 0.45 * (1 - (x * x + z * z) / 0.62) + rng.uniform(0, 0.15)
        size = rng.uniform(0.3, 0.42)
        petals = ellipsoid(size, size * 0.42, size, 3, 7).translate(px, y, pz)
        flowers[keys[count % 3]].append(petals)
        hearts.append(icosphere(size * 0.42, 0).translate(px, y + size * 0.3, pz))
        count += 1
    pieces = {"Curb": curb, "Soil": soil, "Leaves": merge(*leaves), "Hearts": merge(*hearts)}
    pieces.update({name: merge(*meshes) for name, meshes in flowers.items()})
    return pieces


# ====================================================================== carnival turret

def striped_lathe(profile, segments: int, stripes: int, twist: float):
    """A surface of revolution split into two meshes in a candy-cane spiral: `stripes` pairs of
    stripes, turning `twist` full turns per stud of height."""
    a_mesh, b_mesh = [], []
    rows = len(profile)
    for i in range(rows - 1):
        (r0, y0), (r1, y1) = profile[i], profile[i + 1]
        for s in range(segments):
            a0, a1 = s / segments * TAU, (s + 1) / segments * TAU
            quad = [
                (math.cos(a0) * r0, y0, math.sin(a0) * r0),
                (math.cos(a1) * r0, y0, math.sin(a1) * r0),
                (math.cos(a1) * r1, y1, math.sin(a1) * r1),
                (math.cos(a0) * r1, y1, math.sin(a0) * r1),
            ]
            mid_a, mid_y = (a0 + a1) / 2, (y0 + y1) / 2
            band = math.floor((mid_a / TAU + mid_y * twist) * stripes * 2) % 2
            (a_mesh if band == 0 else b_mesh).append(quad)

    def build(quads):
        verts, faces = [], []
        for q in quads:
            n = len(verts)
            verts += q
            faces += [(n, n + 2, n + 1), (n, n + 3, n + 2)]
        return weld(Mesh(verts, faces))

    return build(a_mesh), build(b_mesh)


def lobby_tower():
    """A carnival turret about 36 tall: a candy-striped body on a round plinth, a gold balcony with
    a ring of bulbs, a tall flared roof and a pennant on top."""
    # Rows 1 / (twist * segments) apart, so each stripe steps one segment per row (clean diagonals).
    profile = [(3.3, 1.2 + k * 18.5 / 44) for k in range(45)]  # y 1.2 .. 19.7
    body, stripes = striped_lathe(profile, 40, 3, 0.06)
    plinth = lathe([(0.0, 0.0), (4.4, 0.0), (4.5, 0.3), (4.4, 0.9), (3.9, 1.3), (0.0, 1.3)], 40)
    windows = []
    for k in range(4):
        a = (k + 0.5) / 4 * TAU
        window = rounded_box(1.3, 2.6, 0.5, 0.5, 3).translate(0, 0, -3.3)
        windows.append(window.rotate("y", -math.degrees(a)).translate(0, 13.5, 0))
    balcony = merge(
        lathe([(3.2, 19.6), (4.6, 19.9), (4.9, 20.4), (4.8, 20.9), (3.2, 20.9)], 48),
        torus(4.75, 0.18, 48, 6).translate(0, 21.8, 0),
        *[cylinder(0.12, 1.0, 6).translate(math.cos(k / 16 * TAU) * 4.75, 20.9, math.sin(k / 16 * TAU) * 4.75) for k in range(16)],
    )
    lights = [icosphere(0.32, 0).translate(math.cos((k + 0.5) / 20 * TAU) * 4.9, 20.15, math.sin((k + 0.5) / 20 * TAU) * 4.9) for k in range(20)]
    roof_profile = [(4.9, 21.6), (4.6, 22.4), (3.6, 24.6), (2.4, 27.6), (1.3, 30.6), (0.45, 33.0), (0.0, 33.8)]
    roof, roof_b = striped_lathe(roof_profile, 32, 4, 0.0)
    eave = lathe([(3.2, 21.0), (5.2, 21.3), (5.3, 21.6), (4.9, 21.8), (3.2, 21.8)], 48)
    pole = merge(cylinder(0.12, 3.2, 8).translate(0, 33.6, 0), icosphere(0.3, 1).translate(0, 36.85, 0))
    flag = extrude_xy([(0.1, 36.6), (2.9, 35.8), (0.1, 35.0)], 0.08)
    return {
        "Body": merge(body, plinth),
        "Stripes": stripes,
        "Trim": merge(balcony, eave, pole),
        "Roof": roof,
        "RoofStripes": roof_b,
        "Windows": merge(*windows),
        "Lights": merge(*lights),
        "Flag": flag,
    }


# ====================================================================== bunting

BUNTING_LENGTH = 24.0
BUNTING_SAG = 2.4


def lobby_bunting():
    """A string of triangle pennants BUNTING_LENGTH long along X, ends at the top (y = 4.2) and the
    middle BUNTING_SAG lower; pennants in three colors."""
    top = 4.2

    def rope_y(x):
        t_ = (x + BUNTING_LENGTH / 2) / BUNTING_LENGTH
        return top - BUNTING_SAG * 4 * t_ * (1 - t_)

    xs = np.linspace(-BUNTING_LENGTH / 2, BUNTING_LENGTH / 2, 25)
    rope = tube([(x, rope_y(x), 0.0) for x in xs], 0.07, 5)
    flags = {"FlagA": [], "FlagB": [], "FlagC": []}
    keys = list(flags)
    count = 11
    for k in range(count):
        x = lerp(-BUNTING_LENGTH / 2, BUNTING_LENGTH / 2, (k + 1) / (count + 1))
        y = rope_y(x)
        w, d = 0.75, 1.6
        tri = [(x - w, y), (x + w, y), (x, y - d)]
        piece = extrude_xy(tri, 0.06)
        flags[keys[k % 3]].append(piece)
    pieces = {"Rope": rope}
    pieces.update({name: merge(*meshes) for name, meshes in flags.items()})
    return pieces


def extrude_xy(polygon, depth: float) -> Mesh:
    """A thin plate from a convex polygon in the XY plane, centered on z = 0."""
    n = len(polygon)
    verts = [(x, y, -depth / 2) for x, y in polygon] + [(x, y, depth / 2) for x, y in polygon]
    faces = []
    for i in range(1, n - 1):
        faces += [(0, i, i + 1), (n, n + i + 1, n + i)]
    for i in range(n):
        j = (i + 1) % n
        faces += [(i, j, n + j), (i, n + j, n + i)]
    mesh = Mesh(verts, faces, smooth=False)
    cx = sum(x for x, _ in polygon) / n
    cy = sum(y for _, y in polygon) / n
    return orient(mesh, (cx, cy, 0.0))


# ====================================================================== beach ball

def lobby_beach_ball():
    """A beach ball 5 across: six gores (three colors between white ones) and white caps."""
    radius = 2.5
    rings = 16
    profile = [(math.sin(k / rings * math.pi) * radius, radius - math.cos(k / rings * math.pi) * radius) for k in range(rings + 1)]
    gores = {"White": [], "GoreA": [], "GoreB": [], "GoreC": []}
    colors = ["GoreA", "White", "GoreB", "White", "GoreC", "White"]
    for g in range(6):
        gores[colors[g]].append(partial_lathe(profile[1:-1], g / 6 * TAU, (g + 1) / 6 * TAU, 8))
    caps = [lathe([(0.6, radius * 2 - 0.12), (0.55, radius * 2 - 0.04), (0.0, radius * 2 + 0.02)], 16),
            lathe([(0.0, -0.02), (0.55, 0.04), (0.6, 0.12)], 16)]
    pieces = {name: merge(*meshes) for name, meshes in gores.items()}
    pieces["Cap"] = merge(*caps)
    return pieces


# ====================================================================== zone set pieces: shared bits

def plate(corners, thickness: float) -> Mesh:
    """A thin closed plate from four coplanar corners (in order), thickened along its normal."""
    c = np.array(corners, dtype=float)
    normal = np.cross(c[1] - c[0], c[3] - c[0])
    normal = normal / np.linalg.norm(normal) * thickness / 2
    verts = list(c - normal) + list(c + normal)
    faces = [(0, 1, 2), (0, 2, 3), (4, 6, 5), (4, 7, 6)]
    for i in range(4):
        j = (i + 1) % 4
        faces += [(i, j, 4 + j), (i, 4 + j, 4 + i)]
    return orient(Mesh(verts, faces, smooth=False), c.mean(axis=0))


def extrude_star(polygon, depth: float) -> Mesh:
    """A plate from a star-shaped polygon in the XY plane (fanned from its centroid), centered on z = 0."""
    mesh = extrude(polygon, depth)
    pts = np.array(polygon, dtype=float)
    return orient(mesh, (pts[:, 0].mean(), pts[:, 1].mean(), 0.0))


def star_plate(radius: float, depth: float, x: float, y: float, z: float) -> Mesh:
    return extrude_star(star(radius, radius * 0.45), depth).translate(x, y, z)


def bulb(x: float, y: float, z: float, radius: float = 0.3) -> Mesh:
    return icosphere(radius, 1).translate(x, y, z)


def half_disc(cx: float, cy: float, radius: float, depth: float, z: float, down: bool = True, steps: int = 8) -> Mesh:
    """A scallop: a half disc in the XY plane hanging below (or standing above) y = cy."""
    sign = -1 if down else 1
    pts = [(cx + math.cos(math.pi * k / steps) * radius, cy + sign * math.sin(math.pi * k / steps) * radius) for k in range(steps + 1)]
    return extrude_xy(pts if not down else pts[::-1], depth).translate(0, 0, z)


def rounded_rect(w: float, d: float, r: float, seg: int = 5):
    """A rounded rectangle outline in the XZ plane, centered on the origin."""
    pts = []
    for cx, cz, a0 in ((w / 2 - r, d / 2 - r, 0), (-w / 2 + r, d / 2 - r, 90), (-w / 2 + r, -d / 2 + r, 180), (w / 2 - r, -d / 2 + r, 270)):
        for k in range(seg + 1):
            a = math.radians(a0 + 90 * k / seg)
            pts.append((cx + math.cos(a) * r, cz + math.sin(a) * r))
    return pts


def candy_column(radius: float, y0: float, y1: float, segments: int = 24, twist: float = 0.08):
    """A candy-striped round column from y0 to y1 (two meshes: base color, stripes). The row height
    matches the twist so each stripe steps exactly one segment per row (clean diagonals)."""
    step = 1 / (twist * segments)
    rows = max(2, round((y1 - y0) / step))
    profile = [(radius, lerp(y0, y1, k / rows)) for k in range(rows + 1)]
    return striped_lathe(profile, segments, 2, twist)


def ellipse_arc(half_width: float, rise: float, base_y: float, z: float, count: int):
    return [(-math.cos(math.pi * k / count) * half_width, base_y + math.sin(math.pi * k / count) * rise, z) for k in range(count + 1)]


def recenter(pieces: dict, name: str) -> dict:
    """Prints how far the bounding box center sits from the local origin (LobbyBuilder places the
    prop's pivot, the bottom center of its box, with that offset)."""
    allv = np.vstack([m.v for m in pieces.values()])
    lo, hi = allv.min(axis=0), allv.max(axis=0)
    print(f"  {name}: box center x {(lo[0] + hi[0]) / 2:+.3f} z {(lo[2] + hi[2]) / 2:+.3f}, y {lo[1]:.3f}..{hi[1]:.3f}")
    return pieces


# ====================================================================== zone floors

def lobby_patio():
    """A paved pad (32 x 24) for a zone on the lawn: a white edge, a blue band, cream grout and
    chamfered tiles in the promenade's two warm tones. Stepped 0.1 per layer, 0.4 tall."""
    stripe = slab(rounded_rect(32, 24, 3.0), 0.1)
    band = slab(rounded_rect(31, 23, 2.6), 0.1).translate(0, 0.1, 0)
    grout = slab(rounded_rect(28.4, 20.4, 1.2), 0.1).translate(0, 0.2, 0)
    tiles = {"TileA": [], "TileB": []}
    nx, nz, gap = 10, 7, 0.3
    tw, td = (27.6 - (nx - 1) * gap) / nx, (19.6 - (nz - 1) * gap) / nz
    c = 0.22
    for i in range(nx):
        for j in range(nz):
            x0 = -13.8 + i * (tw + gap)
            z0 = -9.8 + j * (td + gap)
            x1, z1 = x0 + tw, z0 + td
            outline = [(x0 + c, z0), (x1 - c, z0), (x1, z0 + c), (x1, z1 - c), (x1 - c, z1), (x0 + c, z1), (x0, z1 - c), (x0, z0 + c)]
            tiles["TileA" if (i + j) % 2 == 0 else "TileB"].append(slab(outline, 0.1).translate(0, 0.3, 0))
    pieces = {"Stripe": stripe, "Band": band, "Grout": grout}
    pieces.update({name: merge(*meshes) for name, meshes in tiles.items()})
    return pieces


# ====================================================================== arcade: shooting gallery

def lobby_gallery_booth():
    """A carnival shooting-gallery booth around the arcade's target wall. Local origin: the ground
    under the target wall's center line; the open front faces -Z. The back panel (32 x 17) is
    where the game's six clickable targets sit (in front of z = -0.85); tin ducks march along its
    top; a striped, scalloped awning with bulbs covers it and a counter stands at z = -7.5."""
    back = rounded_box(32, 17, 2.5, 0.6, 5).translate(0, 8.5, 0.4)
    frame = [tube([(-16.1, 0.4, -0.95), (16.1, 0.4, -0.95)], 0.22, 6), tube([(-16.1, 16.6, -0.95), (16.1, 16.6, -0.95)], 0.22, 6)]
    frame += [tube([(x, 0.4, -0.95), (x, 16.6, -0.95)], 0.22, 6) for x in (-16.1, 16.1)]
    stars = [star_plate(1.15 * k, 0.24, x, y, -0.92) for x, y, k in
             ((-4.75, 8.5, 1), (4.75, 8.5, 1), (-14.1, 4, 0.9), (14.1, 4, 0.9), (-14.1, 13, 0.9), (14.1, 13, 0.9))]

    # Tin ducks on a rail along the top of the back panel.
    ducks, beaks = [], []
    for k in range(8):
        x = -12.25 + k * 3.5
        body = extrude_xy([(x + math.cos(a) * 0.8, 17.55 + math.sin(a) * 0.45) for a in np.linspace(0, TAU, 14, endpoint=False)], 0.18)
        head = extrude_xy([(x + 0.5 + math.cos(a) * 0.34, 18.2 + math.sin(a) * 0.34) for a in np.linspace(0, TAU, 12, endpoint=False)], 0.18)
        ducks += [body.translate(0, 0, 0.4), head.translate(0, 0, 0.4)]
        beaks.append(extrude_xy([(x + 0.78, 18.27), (x + 1.25, 18.15), (x + 0.78, 18.03)], 0.14).translate(0, 0, 0.4))
    rail = tube([(-16, 17.1, 0.4), (16, 17.1, 0.4)], 0.12, 6)

    # Posts: candy-striped at the front, plain at the back, gold balls on top.
    post, post_stripes = candy_column(0.9, 0.0, 19.3)
    posts = [post.copy().translate(x, 0, -9) for x in (-17.2, 17.2)]
    stripes = [post_stripes.copy().translate(x, 0, -9) for x in (-17.2, 17.2)]
    back_posts = [cylinder(0.7, 21.1, 16).translate(x, 0, 0.4) for x in (-17.2, 17.2)]
    plinths = [lathe([(0.0, 0.0), (1.35, 0.0), (1.4, 0.35), (1.15, 0.7), (0.0, 0.7)], 20).translate(x, 0, -9) for x in (-17.2, 17.2)]
    finials = [icosphere(0.6, 2).translate(x, 20.25, -9) for x in (-17.2, 17.2)]

    # Awning: twelve stripes from the back (y 21.2) down to the front edge (y 19.0), scalloped.
    zb, yb, zf, yf = 1.9, 21.2, -10.0, 19.0
    awn = {"AwningA": [], "AwningB": []}
    lights = []
    for k in range(12):
        x0, x1 = -18 + k * 3, -15 + k * 3
        key = "AwningA" if k % 2 == 0 else "AwningB"
        awn[key].append(plate([(x0, yb, zb), (x1, yb, zb), (x1, yf, zf), (x0, yf, zf)], 0.2))
        awn[key].append(half_disc((x0 + x1) / 2, yf + 0.05, 1.5, 0.16, zf - 0.02))
        lights.append(bulb((x0 + x1) / 2, yf - 1.45, zf - 0.2))
    edge = tube([(-18.1, yf + 0.05, zf - 0.12), (18.1, yf + 0.05, zf - 0.12)], 0.22, 8)
    for x in (-17.2, 17.2):
        lights += [bulb(x, 2.4 + 1.5 * k, -9 - 1.1) for k in range(11)]

    # The counter.
    counter = rounded_box(32.6, 3.4, 2.0, 0.3, 4).translate(0, 1.7, -7.5)
    top = rounded_box(33.4, 0.4, 2.6, 0.15, 3).translate(0, 3.6, -7.5)
    panels = [rounded_box(1.3, 2.4, 0.24, 0.1, 2).translate(-14.85 + k * 3.3, 1.75, -8.56) for k in range(10)]
    counter_stars = [star_plate(0.55, 0.16, -13.2 + k * 3.3, 1.75, -8.56) for k in range(9)]

    pieces = {
        "Back": back,
        "Frame": merge(*posts, *back_posts),
        "Stripes": merge(*stripes),
        "Trim": merge(*frame, rail, *finials, edge, top, *plinths),
        "Stars": merge(*stars, *counter_stars),
        "Ducks": merge(*ducks),
        "Beaks": merge(*beaks),
        "Counter": counter,
        "Panels": merge(*panels),
        "Bulbs": merge(*lights),
    }
    pieces.update({name: merge(*meshes) for name, meshes in awn.items()})
    return recenter(pieces, "LobbyGalleryBooth")


# ====================================================================== podium: tiers under a bulb arch

PODIUM_STEPS = ((0.0, 6.5, "Gold"), (9.5, 4.6, "Silver"), (-9.5, 3.0, "Bronze"))  # local x, height, trim


def lobby_podium():
    """The winners' podium, facing -Z: a stage (36 x 24, centered at z = 2), three rounded tiers
    with gold, silver and bronze bands and stars (1st at x 0, 2nd at x 9.5, 3rd at x -9.5), and a
    candy-striped arch with bulbs and a star on top, standing around the champion board (z 9.6)."""
    base = rounded_box(36, 0.8, 24, 0.35, 4).translate(0, 0.4, 2)
    lip = rounded_box(36.6, 0.3, 24.6, 0.14, 3).translate(0, 0.5, 2)
    bodies = []
    metal = {"Gold": [], "Silver": [], "Bronze": []}
    for x, h, trim in PODIUM_STEPS:
        bodies.append(rounded_box(9, h, 9, 0.9, 5).translate(x, 0.8 + h / 2, 0))
        metal[trim].append(rounded_box(9.4, 0.7, 9.4, 0.3, 3).translate(x, 0.8 + h - 0.6, 0))
        metal[trim].append(rounded_box(9.3, 0.4, 9.3, 0.18, 3).translate(x, 1.0, 0))
        metal[trim].append(star_plate(min(1.7, h * 0.3), 0.3, x, 0.8 + h * 0.48, -4.58))

    arch_z, half, spring, rise = 9.6, 18.5, 19.5, 10.5
    column, column_stripes = candy_column(1.0, 0.8, spring)
    columns = [column.copy().translate(x, 0, arch_z) for x in (-half, half)]
    stripes = [column_stripes.copy().translate(x, 0, arch_z) for x in (-half, half)]
    plinths = [lathe([(0.0, 0.8), (1.6, 0.8), (1.65, 1.2), (1.3, 1.6), (0.0, 1.6)], 20).translate(x, 0, arch_z) for x in (-half, half)]
    arch = tube(ellipse_arc(half, rise, spring, arch_z, 40), 0.9, 10)
    gold_arc = tube(ellipse_arc(half, rise, spring, arch_z - 0.75, 40), 0.3, 6)
    lights = [bulb(x, y, arch_z - 1.15) for x, y, _ in ellipse_arc(half, rise, spring, 0, 18)[1:-1]]
    for x in (-half, half):
        lights += [bulb(x, 2.6 + 1.6 * k, arch_z - 1.2) for k in range(11)]
    crown = star_plate(2.3, 0.6, 0, spring + rise + 2.6, arch_z)
    return recenter({
        "Base": base,
        "Trim": merge(lip, gold_arc, *plinths),
        "Body": merge(*bodies),
        "Gold": merge(*metal["Gold"], crown),
        "Silver": merge(*metal["Silver"]),
        "Bronze": merge(*metal["Bronze"]),
        "Frame": merge(*columns, arch),
        "Stripes": merge(*stripes),
        "Bulbs": merge(*lights),
    }, "LobbyPodium")


# ====================================================================== emote stage: arch, fan, speakers

def speaker_stack(x: float, z: float):
    boxes = [rounded_box(3.6, 4.2, 3.0, 0.4, 4).translate(x, 2.1, z), rounded_box(3.0, 3.2, 2.6, 0.35, 4).translate(x, 5.8, z)]
    cones, trims = [], []
    for y, r, front in ((2.3, 1.25, z - 1.5), (5.8, 0.8, z - 1.3)):
        cones.append(cylinder(r, 0.2, 20).rotate("x", -90).translate(x, y, front + 0.05))
        trims.append(icosphere(r * 0.34, 1).scale(1, 1, 0.5).translate(x, y, front - 0.15))
        trims.append(torus(r + 0.05, 0.1, 24, 6).rotate("x", 90).translate(x, y, front - 0.12))
    return boxes, cones, trims


def lobby_emote_arch():
    """The emote stage's back arch, facing -Z, local origin under its center line: candy columns at
    x +-14, a header beam (y 17.5 to 19.7), a scalloped fan crown behind the sign (radius 12.5),
    bulbs everywhere and a speaker stack on each side (x +-18.5)."""
    column, column_stripes = candy_column(1.1, 0.0, 17.6)
    columns = [column.copy().translate(x, 0, 0) for x in (-14, 14)]
    stripes = [column_stripes.copy().translate(x, 0, 0) for x in (-14, 14)]
    plinths = [lathe([(0.0, 0.0), (1.8, 0.0), (1.85, 0.4), (1.45, 1.0), (0.0, 1.0)], 20).translate(x, 0, 0) for x in (-14, 14)]
    beam = rounded_box(31, 2.2, 2.4, 0.5, 4).translate(0, 18.6, 0)

    fan = {"FanA": [], "FanB": []}
    center_y, radius, slices = 19.7, 12.5, 9
    for k in range(slices):
        a0, a1 = math.pi * k / slices, math.pi * (k + 1) / slices
        arc = [(math.cos(a) * radius, center_y + math.sin(a) * radius) for a in np.linspace(a0, a1, 5)]
        wedge = extrude_xy([(0.0, center_y)] + arc, 0.6).translate(0, 0, 1.2)
        fan["FanA" if k % 2 == 0 else "FanB"].append(wedge)
        mid = (a0 + a1) / 2
        # A scallop bulge on each slice's outer edge.
        bump = extrude_xy([(math.cos(a) * radius, center_y + math.sin(a) * radius) for a in np.linspace(a0, a1, 5)]
                          + [(math.cos(mid) * (radius + 1.3), center_y + math.sin(mid) * (radius + 1.3))], 0.6)
        fan["FanB" if k % 2 == 0 else "FanA"].append(bump.translate(0, 0, 1.2))
    rim = tube([(math.cos(a) * (radius + 0.05), center_y + math.sin(a) * (radius + 0.05), 0.85) for a in np.linspace(0, math.pi, 37)], 0.3, 6)
    lights = [bulb(math.cos(a) * (radius + 1.3), center_y + math.sin(a) * (radius + 1.3), 0.7) for a in np.linspace(0, math.pi, slices * 2 + 1)[1::2]]
    lights += [bulb(x, 18.6, -1.4) for x in np.linspace(-14, 14, 15)]
    for x in (-14, 14):
        lights += [bulb(x, 2.0 + 1.6 * k, -1.35) for k in range(10)]
    caps = [icosphere(0.75, 2).translate(x, 20.4, 0) for x in (-14.8, 14.8)]

    boxes, cones, trims = [], [], []
    for x in (-18.5, 18.5):
        b, c, t = speaker_stack(x, -0.4)
        boxes += b
        cones += c
        trims += t
    pieces = {
        "Frame": merge(*columns, beam),
        "Stripes": merge(*stripes),
        "Trim": merge(*plinths, rim, *caps, *trims),
        "Bulbs": merge(*lights),
        "Speakers": merge(*boxes),
        "Cones": merge(*cones),
    }
    pieces.update({name: merge(*meshes) for name, meshes in fan.items()})
    return recenter(pieces, "LobbyEmoteArch")


# ====================================================================== quest kiosk

def lobby_quest_kiosk():
    """A little wooden kiosk around the quest board, facing -Z. Local origin: the ground under the
    board's center (the board, 16 x 11, centered at y 8, is a game part; this is its frame). Turned
    posts, a gabled roof with a scalloped front edge and bulbs, flower boxes at the feet."""
    back = rounded_box(17.4, 12.4, 0.6, 0.2, 3).translate(0, 8, 0.65)
    bars = [rounded_box(18.4, 1.2, 1.6, 0.35, 3).translate(0, y, 0.3) for y in (14.1, 1.9)]
    bars += [rounded_box(1.2, 13.2, 1.6, 0.35, 3).translate(x, 8, 0.3) for x in (-8.6, 8.6)]
    brackets = [rounded_box(1.4, 0.6, 0.6, 0.2, 2).translate(x * 9.6, y, 0.3) for x in (-1, 1) for y in (4, 12)]
    post_profile = [(0.85, 0.0), (0.85, 0.6), (0.6, 0.8), (0.5, 1.0), (0.5, 7.4), (0.68, 7.7), (0.5, 8.0), (0.5, 15.0),
                    (0.72, 15.4), (0.72, 16.4), (0.0, 16.4)]
    posts = [lathe(post_profile, 16, cap_bottom=True).translate(x, 0, 0.3) for x in (-10.3, 10.3)]

    ridge_y, eave_y, z0, depth, half = 20.0, 16.4, 0.3, 5.0, 12.4
    roof = {"Roof": [], "RoofB": []}
    for side in (-1, 1):
        for band in range(3):
            t0, t1 = band / 3, (band + 1) / 3
            ya, yb = lerp(ridge_y, eave_y, t0), lerp(ridge_y, eave_y, t1)
            za, zb = z0 + side * depth * t0, z0 + side * depth * t1
            roof["Roof" if band % 2 == 0 else "RoofB"].append(plate([(-half, ya, za), (half, ya, za), (half, yb, zb), (-half, yb, zb)], 0.3))
    flaps, lights = [], []
    for k in range(10):
        x = -11.25 + k * 2.5
        flaps.append(half_disc(x, eave_y - 0.1, 1.25, 0.16, z0 - depth - 0.05))
        lights.append(bulb(x, eave_y - 1.45, z0 - depth - 0.25, 0.26))
    gables = [extrude_xy([(z0 - depth, eave_y), (z0 + depth, eave_y), (z0, ridge_y)], 0.3).rotate("y", -90).translate(x, 0, 0) for x in (-11.0, 11.0)]
    ridge = tube([(-half - 0.2, ridge_y + 0.2, z0), (half + 0.2, ridge_y + 0.2, z0)], 0.35, 8)
    ends = [icosphere(0.55, 2).translate(x, ridge_y + 0.3, z0) for x in (-half - 0.4, half + 0.4)]

    planters, leaves, flowers = [], [], []
    rng = np.random.default_rng(4)
    for x in (-10.3, 10.3):
        planters.append(rounded_box(2.8, 1.3, 2.8, 0.3, 3).translate(x, 0.65, 0.3))
        leaves.append(icosphere(1.0, 1, noise=0.1, seed=int(abs(x)) + (x > 0)).scale(1.25, 0.55, 1.25).translate(x, 1.5, 0.3))
        for k in range(6):
            a = k / 6 * TAU + rng.uniform(-0.3, 0.3)
            flowers.append(icosphere(0.32, 1).scale(1, 0.6, 1).translate(x + math.cos(a) * 0.95, 1.85 + rng.uniform(0, 0.25), 0.3 + math.sin(a) * 0.95))
    return recenter({
        "Wood": merge(back, *bars, *brackets, *posts),
        "Roof": merge(*roof["Roof"], *flaps),
        "RoofB": merge(*roof["RoofB"]),
        "Trim": merge(*gables, ridge, *ends),
        "Bulbs": merge(*lights),
        "Planter": merge(*planters),
        "Leaves": merge(*leaves),
        "Flowers": merge(*flowers),
    }, "LobbyQuestKiosk")


# ====================================================================== confetti cannon

def lobby_confetti_cannon():
    """A circus cannon on a wheeled cart, its striped barrel aimed up and forward (-Z)."""
    cart = rounded_box(3.2, 1.4, 4.4, 0.4, 4).translate(0, 1.9, 0.2)
    wheels, spokes = [], []
    for x in (-2.0, 2.0):
        wheels.append(torus(1.25, 0.24, 28, 8).rotate("z", 90).translate(x, 1.5, 0.2))
        for k in range(6):
            a = k / 6 * TAU
            spokes.append(tube([(x, 1.5, 0.2), (x, 1.5 + math.sin(a) * 1.15, 0.2 + math.cos(a) * 1.15)], 0.1, 5))
        spokes.append(cylinder(0.32, 0.5, 12).rotate("z", 90).translate(x + 0.25, 1.5, 0.2))
    profile = [(0.0, -0.9), (0.75, -0.75), (1.05, -0.3), (1.1, 0.4), (0.98, 1.0), (0.9, 3.6), (1.0, 4.0), (1.12, 4.3), (1.12, 4.6), (0.75, 4.6), (0.75, 4.5)]
    barrel, barrel_stripes = striped_lathe(profile, 28, 4, 0.0)
    muzzle = torus(1.1, 0.18, 28, 6).translate(0, 4.15, 0)
    band = torus(1.06, 0.14, 28, 6).translate(0, 1.0, 0)
    tilt = lambda m: m.rotate("x", -40).translate(0, 3.1, 0.6)  # noqa: E731
    stars = [star_plate(0.6, 0.12, 0, 1.9, -2.06), star_plate(0.6, 0.12, 0, 1.9, 2.46).rotate("y", 180).translate(0, 0, 0.4)]
    return recenter({
        "Cart": cart,
        "Wheels": merge(*wheels),
        "Trim": merge(*spokes, tilt(muzzle), tilt(band), *stars),
        "Barrel": tilt(barrel),
        "BarrelStripes": tilt(barrel_stripes),
    }, "LobbyConfettiCannon")


PROPS = {
    "LobbyPavers": lobby_pavers,
    "LobbyCourt": lobby_court,
    "LobbyFountain": lobby_fountain,
    "LobbyDuck": lobby_duck,
    "LobbyFerrisWheel": lobby_ferris_wheel,
    "LobbyFerrisCabin": lobby_ferris_cabin,
    "LobbyFerrisStand": lobby_ferris_stand,
    "LobbyHotAirBalloon": lobby_hot_air_balloon,
    "LobbyFlowerBed": lobby_flower_bed,
    "LobbyTower": lobby_tower,
    "LobbyBunting": lobby_bunting,
    "LobbyBeachBall": lobby_beach_ball,
    "LobbyPatio": lobby_patio,
    "LobbyGalleryBooth": lobby_gallery_booth,
    "LobbyPodium": lobby_podium,
    "LobbyEmoteArch": lobby_emote_arch,
    "LobbyQuestKiosk": lobby_quest_kiosk,
    "LobbyConfettiCannon": lobby_confetti_cannon,
}

# Preview colors only; the game colors pieces by name (Props/Lobby.luau).
COLORS = {
    "TileA": (255, 240, 226), "TileB": (250, 226, 216), "Band": (226, 214, 255), "Stripe": (255, 255, 255),
    "OuterA": (226, 214, 255), "OuterB": (214, 202, 250), "RayA": (240, 246, 255), "RayB": (160, 205, 255),
    "Accent": (255, 120, 175), "Ring": (255, 204, 64), "Stone": (250, 250, 255), "Pool": (90, 200, 245),
    "Eyes": (30, 30, 40), "Beak": (255, 150, 40), "Lights": (255, 236, 150), "Roof": (255, 255, 255),
    "Legs": (156, 108, 255), "Envelope": (255, 84, 150), "Ropes": (90, 70, 60),
    "Curb": (245, 240, 235), "Soil": (110, 75, 55), "Leaves": (70, 170, 80), "Hearts": (255, 220, 70),
    "FlowerA": (255, 90, 150), "FlowerB": (255, 255, 255), "FlowerC": (170, 120, 255),
    "Body": (255, 255, 255), "Stripes": (255, 84, 150), "Trim": (255, 204, 64), "RoofStripes": (255, 255, 255),
    "Windows": (60, 40, 110), "Flag": (255, 204, 64), "Rope": (250, 250, 250),
    "FlagA": (255, 84, 150), "FlagB": (64, 196, 255), "FlagC": (255, 204, 64),
    "White": (255, 255, 255), "GoreA": (255, 70, 80), "GoreB": (60, 150, 255), "GoreC": (255, 210, 50), "Cap": (255, 70, 80),
    "Grout": (250, 240, 225), "Back": (45, 65, 130), "Frame": (120, 84, 230), "Stars": (255, 214, 92), "Ducks": (255, 214, 60),
    "Beaks": (255, 140, 40), "Counter": (220, 60, 90), "Panels": (255, 255, 255), "Bulbs": (255, 240, 170),
    "AwningA": (255, 70, 110), "AwningB": (255, 255, 255), "Base": (60, 40, 110), "Gold": (255, 200, 50),
    "Silver": (200, 210, 230), "Bronze": (220, 140, 80), "FanA": (255, 204, 64), "FanB": (255, 92, 150),
    "Speakers": (50, 40, 80), "Cones": (30, 30, 40), "Wood": (180, 120, 80), "RoofB": (255, 255, 255),
    "Planter": (230, 110, 150), "Flowers": (255, 240, 120), "Cart": (90, 150, 255), "Wheels": (255, 70, 100),
    "Barrel": (255, 92, 150), "BarrelStripes": (255, 255, 255),
}
