"""Props for Rake It In: the garden rake, the produce (carrot, tomato, broccoli, golden pumpkin and the
bomb), the bushel basket, the turning field, the harvest silo in its middle and farm decorations.

Units are studs, +Y is up, the base sits on y = 0 and -Z is the front. Piece names are unique to this
mode (the game colors pieces by name, see src/server/World/Props/RakeItIn.luau).
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
    lerp,
    merge,
    organic_lathe,
    rounded_box,
    sd_capsule,
    sd_ellipsoid,
    sdf_mesh,
    smin,
    sphere,
    star,
    torus,
    weld,
)
from generate_meshes import taper, tube

TAU = 2 * math.pi


# ---------------------------------------------------------------- helpers


def smooth_profile(points, samples=40):
    """Catmull-Rom through (radius, y) control points, for soft lathe silhouettes."""
    pts = [np.array(p, float) for p in points]
    pts = [pts[0]] + pts + [pts[-1]]
    out = []
    segments = len(pts) - 3
    per = max(2, samples // segments)
    for i in range(segments):
        p0, p1, p2, p3 = pts[i], pts[i + 1], pts[i + 2], pts[i + 3]
        for j in range(per):
            t = j / per
            t2, t3 = t * t, t * t * t
            point = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
            out.append((max(0.0, float(point[0])), float(point[1])))
    out.append(tuple(points[-1]))
    return out


def radial_scale(mesh: Mesh, fn):
    """Scales each vertex's distance from the Y axis by fn(angle, y) (lobes, grooves, ridges)."""
    angle = np.arctan2(mesh.v[:, 2], mesh.v[:, 0])
    factor = fn(angle, mesh.v[:, 1])
    mesh.v[:, 0] *= factor
    mesh.v[:, 2] *= factor
    return mesh


def leaf(length, width, cup=0.25, n=8):
    """A flat pointed leaf lying in the XZ plane along +X, cupped upward along its midrib."""
    verts, faces = [], []
    for i in range(n + 1):
        t = i / n
        half = width / 2 * math.sin(math.pi * t) ** 0.8
        x = t * length
        for side in (-1, 0, 1):
            z = side * half
            y = cup * (abs(side) * half / max(width / 2, 1e-6)) ** 2 * 0.5 + 0.12 * math.sin(math.pi * t) * length * 0.15
            verts.append((x, y, z))
    for i in range(n):
        a = i * 3
        b = a + 3
        faces += [(a, b, a + 1), (a + 1, b, b + 1), (a + 1, b + 1, a + 2), (a + 2, b + 1, b + 2)]
    top = Mesh(verts, faces)
    # Give it a little thickness so it reads from both sides (Roblox meshes are single-sided).
    bottom = Mesh(np.array(verts) - np.array([0, 0.03, 0]), [(a, c, b) for a, b, c in faces])
    return merge(top, bottom)


def aim(mesh: Mesh, direction, roll=0.0):
    """Turns a mesh built along +X so that +X points along `direction` (then rolls it about it)."""
    d = np.array(direction, float)
    d /= np.linalg.norm(d)
    helper = np.array([0.0, 1.0, 0.0]) if abs(d[1]) < 0.95 else np.array([1.0, 0.0, 0.0])
    side = np.cross(d, helper)
    side /= np.linalg.norm(side)
    up = np.cross(side, d)
    c, s = math.cos(roll), math.sin(roll)
    up, side = up * c + side * s, side * c - up * s
    basis = np.stack([d, up, side], 1)  # columns: where local x, y, z go
    mesh.v = mesh.v @ basis.T
    return mesh


def wall_band(r0, r1, y0, y1, a0, a1, thickness, steps=4):
    """A closed slab on a cone wall between angles a0..a1 (radians) from (r0, y0) up to (r1, y1)."""
    verts, faces = [], []
    for layer, offset in ((0, 0.0), (1, -thickness)):
        for i in range(steps + 1):
            a = lerp(a0, a1, i / steps)
            for (r, y) in ((r0 + offset, y0), (r1 + offset, y1)):
                verts.append((math.cos(a) * r, y, math.sin(a) * r))
    per = (steps + 1) * 2

    def idx(layer, i, top):
        return layer * per + i * 2 + top

    for i in range(steps):
        # outer face, inner face (flipped), plus top and bottom strips
        faces += [(idx(0, i, 0), idx(0, i, 1), idx(0, i + 1, 0)), (idx(0, i + 1, 0), idx(0, i, 1), idx(0, i + 1, 1))]
        faces += [(idx(1, i, 0), idx(1, i + 1, 0), idx(1, i, 1)), (idx(1, i + 1, 0), idx(1, i + 1, 1), idx(1, i, 1))]
        faces += [(idx(0, i, 1), idx(1, i, 1), idx(0, i + 1, 1)), (idx(0, i + 1, 1), idx(1, i, 1), idx(1, i + 1, 1))]
        faces += [(idx(0, i, 0), idx(0, i + 1, 0), idx(1, i, 0)), (idx(0, i + 1, 0), idx(1, i + 1, 0), idx(1, i, 0))]
    for i, flip in ((0, False), (steps, True)):
        quad = [idx(0, i, 0), idx(1, i, 0), idx(1, i, 1), idx(0, i, 1)]
        tri = [(quad[0], quad[1], quad[2]), (quad[0], quad[2], quad[3])]
        faces += [(a, c, b) for a, b, c in tri] if flip else tri
    mesh = Mesh(verts, faces)
    mesh.smooth = False
    return mesh


def oriented(mesh: Mesh):
    """Makes every face wind outward from the mesh's centroid (for hand-built closed shapes)."""
    center = mesh.v.mean(axis=0)
    tri = mesh.v[mesh.f]
    normal = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    outward = np.einsum("ij,ij->i", normal, tri.mean(axis=1) - center) >= 0
    faces = mesh.f.copy()
    faces[~outward] = faces[~outward][:, [0, 2, 1]]
    return Mesh(mesh.v, faces, mesh.smooth)


def on_ground(pieces: dict) -> dict:
    """Moves a prop so its lowest point sits on y = 0."""
    low = min(mesh.v[:, 1].min() for mesh in pieces.values())
    for mesh in pieces.values():
        mesh.translate(0, -low, 0)
    return pieces


# ---------------------------------------------------------------- produce


def veggie_carrot():
    """A fat cartoon carrot lying on its side, root tip toward -X and a bushy top toward +X."""
    control = [(0.0, 0.0), (0.1, 0.12), (0.2, 0.42), (0.3, 0.85), (0.39, 1.3), (0.47, 1.75), (0.52, 2.05), (0.5, 2.25),
               (0.38, 2.38), (0.0, 2.42)]
    root = lathe(smooth_profile(control, 36), 22)
    # Growth rings: shallow grooves around the root.
    rings = (0.45, 0.8, 1.12, 1.45, 1.78)

    def grooves(angle, y):
        dip = np.zeros_like(y)
        for k, yg in enumerate(rings):
            wobble = 0.03 * np.sin(angle * 2 + k)
            dip += 0.08 * np.exp(-(((y - yg - wobble) / 0.05) ** 2)) * (0.6 + 0.4 * np.cos(angle * 3 + k * 1.7) ** 2)
        return 1 - dip

    radial_scale(root, grooves)
    fronds = []
    for yaw, lean, length in ((0, 0.5, 1.55), (72, 0.8, 1.35), (144, 0.7, 1.45), (216, 0.75, 1.35), (288, 0.6, 1.5)):
        a = math.radians(yaw)
        direction = np.array([math.cos(a) * math.sin(lean), math.cos(lean), math.sin(a) * math.sin(lean)])
        base = np.array([0, 2.3, 0])

        def along(t, direction=direction, length=length, base=base):
            return base + direction * length * t + np.array([0, -0.2 * t * t * length, 0])

        fronds.append(taper([tuple(along(t)) for t in (0, 0.35, 0.7, 1.0)], 0.08, 0.04, 6))
        side_axis = np.cross(direction, [0, 1, 0])
        side_axis = side_axis / (np.linalg.norm(side_axis) + 1e-9)
        for j in range(5):
            spot = along(0.3 + j * 0.15)
            for side in (-1, 1):
                out = side_axis * side
                blade = aim(leaf(0.62 - j * 0.07, 0.3 - j * 0.02, 0.1, 6), out + direction * 0.7 + np.array([0, 0.3, 0]), roll=side * 0.35)
                fronds.append(blade.translate(*spot))
        tip = aim(leaf(0.5, 0.3, 0.1, 6), direction + np.array([0, -0.2, 0]))
        fronds.append(tip.translate(*along(1.0)))
    leaves = merge(*fronds)
    # Lie it down along X (top toward +X), tilted up a little so the leaves stay clear of the ground.
    pieces = {"CarrotRoot": root, "CarrotLeaves": leaves}
    for mesh in pieces.values():
        mesh.translate(0, -1.2, 0).rotate("z", -78).rotate("y", 8)
    return on_ground(pieces)


def veggie_tomato():
    """A plump, shiny tomato with soft lobes, a star of leaves draped over its shoulders and a stem."""
    control = [(0.0, 0.08), (0.5, 0.0), (0.88, 0.16), (1.06, 0.48), (1.08, 0.8), (0.92, 1.1), (0.58, 1.27), (0.24, 1.25),
               (0.0, 1.16)]
    body = lathe(smooth_profile(control, 28), 40)

    def lobes(angle, y):
        band = np.clip(np.sin(np.clip(y / 1.27, 0, 1) * math.pi * 0.9 + 0.3), 0, 1)
        return 1 - 0.07 * (0.5 - 0.5 * np.cos(angle * 5)) ** 1.5 * band

    radial_scale(body, lobes)
    sepals = []
    for k in range(6):
        blade = leaf(0.78, 0.3, 0.06, 8)
        # Droop over the shoulder: bend the far half of the leaf down.
        bend = np.clip(blade.v[:, 0] - 0.25, 0, None)
        blade.v[:, 1] -= bend**2 * 0.65
        sepals.append(blade.rotate("y", -(k * 60 + 10)).translate(0, 1.24, 0))
    stem = taper([(0, 1.18, 0), (0.0, 1.45, 0.0), (0.07, 1.62, 0.02), (0.22, 1.7, 0.05)], 0.1, 0.065, 8)
    return {"TomatoBody": body, "TomatoLeaves": merge(*sepals, stem)}


def veggie_broccoli():
    """A broccoli tree: a pale stalk splitting into branches under a bumpy dark-green crown."""
    stalk = lathe(smooth_profile([(0.0, 0.0), (0.4, 0.0), (0.44, 0.06), (0.34, 0.4), (0.32, 0.7), (0.46, 1.0), (0.0, 1.08)], 16), 14)
    branches = []
    rng = np.random.default_rng(31)
    for k in range(5):
        a = k * 2 * math.pi / 5 + 0.3
        tip = (math.cos(a) * 0.62, 1.42, math.sin(a) * 0.62)
        branches.append(taper([(0, 0.8, 0), (math.cos(a) * 0.3, 1.12, math.sin(a) * 0.3), tip], 0.18, 0.11, 6))
    florets = [icosphere(0.64, 2, 0.22, seed=40).scale(1.0, 0.82, 1.0).translate(0, 1.72, 0)]
    for k in range(8):
        a = k * 2 * math.pi / 8 + rng.uniform(-0.2, 0.2)
        ring = 0.64 + rng.uniform(-0.06, 0.06)
        florets.append(icosphere(rng.uniform(0.38, 0.46), 2, 0.3, seed=41 + k).translate(math.cos(a) * ring, 1.55 + rng.uniform(-0.06, 0.1), math.sin(a) * ring))
    for k in range(4):
        a = k * 2 * math.pi / 4 + 0.6
        florets.append(icosphere(0.38, 1, 0.3, seed=60 + k).translate(math.cos(a) * 0.36, 2.02 + rng.uniform(-0.05, 0.05), math.sin(a) * 0.36))
    # Tiny buds all over the crown give it the bumpy broccoli texture.
    for k in range(36):
        theta, phi = rng.uniform(0, 2 * math.pi), rng.uniform(0.05, 1.35)
        direction = np.array([math.cos(theta) * math.sin(phi), math.cos(phi) * 0.85, math.sin(theta) * math.sin(phi)])
        spot = np.array([0, 1.62, 0]) + direction * rng.uniform(0.8, 0.94)
        florets.append(icosphere(rng.uniform(0.13, 0.18), 1, 0.15, seed=100 + k).translate(*spot))
    return {"BroccoliStalk": merge(stalk, *branches), "BroccoliCrown": merge(*florets)}


def golden_pumpkin():
    """The prize: a big ribbed pumpkin with a curly stem, a leaf and a corkscrew tendril."""
    control = [(0.0, 0.2), (0.55, 0.03), (1.05, 0.13), (1.42, 0.48), (1.58, 0.98), (1.5, 1.45), (1.2, 1.78), (0.72, 1.9),
               (0.34, 1.82), (0.0, 1.62)]
    body = lathe(smooth_profile(control, 30), 63)

    def ribs(angle, y):
        band = np.clip(np.sin(np.clip(y / 1.9, 0, 1) * math.pi), 0, 1) ** 0.5
        groove = (0.5 - 0.5 * np.cos(angle * 9)) ** 2.4
        return 1 - 0.15 * groove * band

    radial_scale(body, ribs)
    # Lobes bulge a little higher than the grooves between them.
    angle = np.arctan2(body.v[:, 2], body.v[:, 0])
    top_band = np.clip((body.v[:, 1] - 1.2) / 0.7, 0, 1)
    body.v[:, 1] += 0.08 * (0.5 + 0.5 * np.cos(angle * 9)) * top_band
    stem = taper([(0, 1.55, 0), (0.02, 1.95, 0.0), (0.12, 2.24, 0.04), (0.34, 2.38, 0.06)], 0.24, 0.14, 9)
    flare = lathe([(0.0, 1.6), (0.38, 1.62), (0.26, 1.8), (0.0, 1.82)], 12)
    blade = leaf(1.35, 1.0, 0.22, 10)
    blade.v[:, 1] -= np.clip(blade.v[:, 0] - 0.5, 0, None) ** 2 * 0.35
    blade.rotate("y", 35).translate(0.15, 1.86, 0.1)
    curl = []
    for i in range(40):
        t = i / 39
        a = t * 4.2 * math.pi
        curl.append((-0.2 - t * 0.75, 1.86 + 0.2 * math.sin(a) + t * 0.2, -0.15 + 0.2 * math.cos(a)))
    tendril = tube(curl, 0.04, 6)
    return {"PumpkinBody": body, "PumpkinStem": merge(stem, flare, blade, tendril)}


def veggie_bomb():
    """A cartoon bomb that sneaked into the harvest: a round body, a metal cap and a curly fuse."""
    body = sphere(0.95, 16, 28).translate(0, 0.95, 0)
    cap = merge(cylinder(0.4, 0.34, 20, 0.08).translate(0, 1.72, 0), torus(0.39, 0.07, 20, 6).translate(0, 1.76, 0))
    fuse_points = [(0, 1.98, 0), (0.02, 2.2, 0.0), (0.14, 2.38, 0.02), (0.32, 2.42, 0.04), (0.46, 2.36, 0.02), (0.54, 2.46, 0.0),
                   (0.52, 2.66, -0.02)]
    fuse = taper(fuse_points, 0.095, 0.08, 8)
    shine = icosphere(1.0, 2).scale(0.22, 0.13, 0.06).rotate("z", 35).rotate("y", 25)
    # Sits on the body's surface, up and to the left of the front.
    direction = np.array([-0.45, 0.55, -0.7])
    direction /= np.linalg.norm(direction)
    shine.translate(*(np.array([0, 0.95, 0]) + direction * 0.93))
    return {"BombBody": body, "BombCap": cap, "BombFuse": fuse, "BombShine": shine}


# ---------------------------------------------------------------- tools and containers


def garden_rake():
    """A chunky toy garden rake standing up: a wooden handle with a rubber grip at the bottom, a red
    bow-rake head on top and silver tines pointing forward (-Z). The handle is a plain cylinder so the
    game can stretch it when the rake reaches across the field."""
    handle = cylinder(0.17, 5.9, 16).translate(0, 0.55, 0)
    grip = merge(capsule(1.1, 0.22, 14).translate(0, 0.55, 0), torus(0.2, 0.05, 14, 6).translate(0, 1.08, 0))
    socket = lathe([(0.0, 6.2), (0.22, 6.2), (0.27, 6.35), (0.25, 6.75), (0.3, 6.82), (0.0, 6.86)], 16)
    bar = rounded_box(4.3, 0.34, 0.46, 0.15, 6).translate(0, 7.02, -0.05)
    braces = [tube([(0, 6.55, 0.0), (side * 0.8, 6.78, 0.0), (side * 1.75, 6.95, -0.02)], 0.09, 7) for side in (-1, 1)]
    knobs = [icosphere(0.2, 2).translate(side * 2.15, 7.02, -0.05) for side in (-1, 1)]
    tines = []
    count = 10
    for i in range(count):
        x = lerp(-1.9, 1.9, i / (count - 1))
        # Each tine leaves the bar forward and curls slightly down at its tip.
        points = [(x, 7.0, -0.2), (x, 6.97, -0.55), (x, 6.88, -0.95), (x, 6.7, -1.25)]
        tines.append(taper(points, 0.075, 0.05, 6))
        tines.append(icosphere(0.055, 1).translate(x, 6.7, -1.25))
    return {"RakeHandle": handle, "RakeGrip": grip, "RakeHead": merge(socket, bar, *braces, *knobs), "RakeTines": merge(*tines)}


def bushel_basket():
    """A big wooden bushel basket: tapered slats with gaps, a bottom, two metal hoops, a rolled rim
    and side handles. Open at the top: the game piles the raked produce inside."""
    staves = []
    count = 20
    r_bottom, r_top, y0, y1 = 1.55, 2.0, 0.18, 2.9
    gap = 0.035
    for k in range(count):
        a0 = 2 * math.pi * k / count + gap
        a1 = 2 * math.pi * (k + 1) / count - gap
        staves.append(wall_band(r_bottom, r_top, y0, y1, a0, a1, 0.12, 3))
    floor = cylinder(r_bottom - 0.05, 0.22, 32, 0.04)
    bands = [torus(lerp(r_bottom, r_top, (y - y0) / (y1 - y0)) + 0.03, 0.07, 48, 6).translate(0, y, 0) for y in (0.55, 2.2)]
    rim = torus(r_top - 0.04, 0.12, 48, 8).translate(0, y1 + 0.02, 0)
    handles = []
    for side in (-1, 1):
        hoop = torus(0.55, 0.07, 16, 6, 180).rotate("x", 90).rotate("y", 90)
        handles.append(hoop.translate(side * (r_top + 0.04), 2.25, 0))
        handles.append(capsule(0.85, 0.14, 10).rotate("x", 90).translate(side * (r_top + 0.04), 2.8, 0))
    return {"BushelWood": merge(*staves, floor), "BushelBands": merge(*bands, rim), "BushelHandles": merge(*handles)}


# ---------------------------------------------------------------- the field and the silo

FIELD_OUTER = 20.0  # the soil ends just inside the rim at this radius
FIELD_INNER = 8.0  # the hole in the middle where the silo stands
SOIL_Y = 1.1  # soil height above the field's base
ROWS = 20  # planting rows (ridges) running out from the middle


def ring(r_in, r_out, y0, y1, segments, lip=0.15):
    """A closed wooden ring (rounded top) between two radii, for rims."""
    profile = [(r_in, y0), (r_out, y0), (r_out + 0.06, y1 - lip), (r_out - lip, y1), (r_in + lip, y1), (r_in - 0.04, y1 - lip),
               (r_in, y0)]
    return lathe(profile, segments)


def ridge_height(angle, r):
    """Soil height: ridges along the planting rows, flattening toward the rims."""
    row = (0.5 + 0.5 * np.cos(angle * ROWS)) ** 1.6
    fade = np.clip((r - FIELD_INNER) / 1.2, 0, 1) * np.clip((FIELD_OUTER - 0.3 - r) / 1.2, 0, 1)
    return SOIL_Y + 0.05 + 0.28 * row * fade


def soil_surface():
    """The turning soil: a polar grid between the rims, ridged along the rows (faces point up)."""
    radii = np.linspace(FIELD_INNER - 0.3, FIELD_OUTER - 0.1, 16)
    segments = ROWS * 10
    verts, faces = [], []
    for r in radii:
        for k in range(segments):
            a = TAU * k / segments
            verts.append((math.cos(a) * r, float(ridge_height(np.array(a), np.array(r))), math.sin(a) * r))
    for i in range(len(radii) - 1):
        for k in range(segments):
            a = i * segments + k
            b = i * segments + (k + 1) % segments
            c, d = a + segments, b + segments
            faces += [(a, b, c), (b, d, c)]
    mesh = Mesh(verts, faces)
    tri = mesh.v[mesh.f]
    normal = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    if normal[:, 1].mean() < 0:
        mesh.f = mesh.f[:, ::-1].copy()
    return mesh


def sprout(rng):
    """Two or three little leaves rising from the soil."""
    blades = []
    count = int(rng.integers(2, 4))
    for k in range(count):
        blade = leaf(rng.uniform(0.45, 0.6), rng.uniform(0.22, 0.28), 0.08, 4)
        blade.rotate("z", rng.uniform(35, 55)).rotate("y", k * 360 / count + rng.uniform(-20, 20))
        blades.append(blade)
    stem = cylinder(0.04, 0.22, 5)
    return merge(stem, *blades)


def turning_field():
    """The big round lazy-susan field that turns in the middle of the farm: a wooden drum with a red
    lip, ridged soil in planting rows with sprouts on them, and an inner rim around the silo hole."""
    rim = ring(FIELD_OUTER - 0.35, FIELD_OUTER + 0.5, 0.0, 1.45, 144)

    def planks(angle, y):
        return 1 - 0.012 * (0.5 + 0.5 * np.cos(angle * 72)) ** 8

    radial_scale(rim, planks)
    lip = ring(FIELD_OUTER - 0.45, FIELD_OUTER + 0.62, 1.45, 1.75, 144, 0.12)
    hub = ring(FIELD_INNER - 1.0, FIELD_INNER - 0.25, 0.0, 1.6, 64)
    hub_lip = ring(FIELD_INNER - 1.1, FIELD_INNER - 0.15, 1.6, 1.85, 64, 0.1)
    base = lathe([(FIELD_INNER - 0.3, 0.0), (FIELD_OUTER - 0.3, 0.0), (FIELD_OUTER - 0.3, SOIL_Y - 0.05),
                  (FIELD_INNER - 0.3, SOIL_Y - 0.05), (FIELD_INNER - 0.3, 0.0)], 96)
    rng = np.random.default_rng(7)
    sprouts = []
    for row in range(ROWS):
        a = TAU * row / ROWS
        for r in np.arange(FIELD_INNER + 1.4, FIELD_OUTER - 1.0, 2.1):
            if rng.random() < 0.18:
                continue
            jitter_a = a + rng.uniform(-0.02, 0.02)
            rr = r + rng.uniform(-0.4, 0.4)
            y = float(ridge_height(np.array(jitter_a), np.array(rr)))
            sprouts.append(sprout(rng).translate(math.cos(jitter_a) * rr, y - 0.04, math.sin(jitter_a) * rr))
    # Painted marks on the outside of the rim so the turning reads from anywhere: one every 45 degrees.
    marks = []
    for k in range(8):
        a = TAU * k / 8
        marks.append(wall_band(FIELD_OUTER + 0.62, FIELD_OUTER + 0.62, 0.3, 1.3, a - 0.06, a + 0.06, 0.1, 2))
    return {
        "FieldWood": merge(rim, hub),
        "FieldLip": merge(lip, hub_lip),
        "FieldMarks": merge(*marks),
        "FieldSoil": merge(soil_surface(), base),
        "FieldSprouts": merge(*sprouts),
    }


def harvest_silo():
    """The red harvest silo in the middle of the field: a stone footing, a corrugated red drum with
    white bands, a silver dome with a vent cap the produce pops out of, a barn door (front, -Z) and
    a ladder."""
    footing = organic_lathe([(0.0, 0.0), (6.9, 0.0), (7.0, 0.9), (6.5, 1.7), (0.0, 1.75)], 48, 0.08, 7, seed=3)
    body = lathe([(0.0, 1.5), (5.3, 1.5), (5.3, 13.4), (0.0, 13.4)], 96)

    def corrugate(angle, y):
        return 1 + 0.012 * np.cos(angle * 48)

    radial_scale(body, corrugate)
    bands = merge(*[torus(5.36, 0.16, 96, 8).translate(0, y, 0) for y in (1.8, 5.6, 9.4, 13.2)])
    dome = lathe(smooth_profile([(0.0, 13.2), (5.75, 13.2), (5.6, 14.3), (4.7, 15.9), (3.0, 17.0), (1.2, 17.45), (0.0, 17.5)], 24), 64)
    vent = merge(
        cylinder(1.25, 1.2, 24).translate(0, 17.2, 0),
        lathe([(0.0, 18.3), (1.95, 18.3), (1.85, 18.55), (0.6, 19.4), (0.0, 19.5)], 24),
        torus(1.27, 0.1, 24, 6).translate(0, 18.2, 0),
    )
    # The barn door on the front: white frame with an X brace, a dark wood panel behind it.
    door_z = -5.32
    panel = rounded_box(3.4, 4.6, 0.3, 0.1, 4).translate(0, 4.0, door_z + 0.05)
    frame = [rounded_box(3.9, 0.35, 0.3, 0.1, 3).translate(0, y, door_z - 0.18) for y in (1.75, 6.25)]
    frame += [rounded_box(0.35, 4.85, 0.3, 0.1, 3).translate(x, 4.0, door_z - 0.18) for x in (-1.8, 1.8)]
    for sign in (-1, 1):
        brace = rounded_box(0.32, 5.2, 0.24, 0.08, 3).rotate("z", sign * 36).translate(0, 4.0, door_z - 0.22)
        frame.append(brace)
    # A ladder up the right side (+X).
    rails = [tube([(5.62, 1.6, z), (5.62, 13.0, z)], 0.09, 8) for z in (-0.55, 0.55)]
    rungs = [cylinder(0.07, 1.1, 8).rotate("x", 90).translate(5.62, y, 0.55) for y in np.arange(2.4, 13.0, 0.9)]
    ladder = merge(*rails, *rungs)
    return {
        "SiloStone": footing,
        "SiloBody": body,
        "SiloTrim": merge(bands, *frame),
        "SiloDoor": panel,
        "SiloRoof": merge(dome, vent),
        "SiloLadder": ladder,
    }


PROPS = {
    "VeggieCarrot": veggie_carrot,
    "VeggieTomato": veggie_tomato,
    "VeggieBroccoli": veggie_broccoli,
    "GoldenPumpkin": golden_pumpkin,
    "VeggieBomb": veggie_bomb,
    "GardenRake": garden_rake,
    "BushelBasket": bushel_basket,
    "TurningField": turning_field,
    "HarvestSilo": harvest_silo,
}

# Preview colors only; the game colors pieces by name.
COLORS = {
    "CarrotRoot": (255, 132, 30),
    "CarrotLeaves": (70, 180, 60),
    "TomatoBody": (235, 45, 40),
    "TomatoLeaves": (60, 150, 50),
    "BroccoliStalk": (165, 210, 110),
    "BroccoliCrown": (50, 140, 55),
    "PumpkinBody": (255, 196, 40),
    "PumpkinStem": (95, 150, 55),
    "BombBody": (40, 38, 52),
    "BombCap": (150, 155, 170),
    "BombFuse": (215, 180, 120),
    "BombShine": (240, 240, 255),
    "RakeHandle": (196, 140, 86),
    "RakeGrip": (255, 205, 50),
    "RakeHead": (230, 55, 60),
    "RakeTines": (200, 205, 215),
    "BushelWood": (226, 184, 120),
    "BushelBands": (90, 80, 90),
    "BushelHandles": (170, 115, 65),
    "FieldWood": (170, 110, 60),
    "FieldLip": (215, 60, 50),
    "FieldMarks": (255, 240, 200),
    "FieldSoil": (120, 78, 48),
    "FieldSprouts": (110, 200, 70),
    "SiloStone": (150, 145, 140),
    "SiloBody": (200, 50, 45),
    "SiloTrim": (250, 245, 235),
    "SiloDoor": (110, 60, 40),
    "SiloRoof": (190, 195, 205),
    "SiloLadder": (90, 90, 100),
}
