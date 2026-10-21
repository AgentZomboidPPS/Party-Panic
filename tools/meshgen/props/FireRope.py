"""Fire Rope's arena props: the Dragon Temple of the fire festival.

    python3 tools/meshgen/generate_meshes.py --only DragonTemple,RopeTower,SunWheel,FireBrazier,LavaFall,CraterWall,TempleBridge

Units are studs, +Y up, base on y = 0, -Z is the front. The arena drops the props whose base is
"lake level - 1" on the lava (the bridge floor is 25 studs above that base).
"""

import math

import numpy as np
from generate_meshes import (
    Mesh,
    cylinder,
    extrude,
    icosphere,
    lathe,
    merge,
    organic_lathe,
    rounded_box,
    sd_capsule,
    sd_ellipsoid,
    sdf_mesh,
    smin,
    star,
    taper,
    torus,
    tube,
)


# ---------------------------------------------------------------- helpers

def box(sx, sy, sz):
    """A plain flat-shaded box centered on the origin (12 triangles)."""
    x, y, z = sx / 2, sy / 2, sz / 2
    v = [(-x, -y, -z), (x, -y, -z), (x, y, -z), (-x, y, -z), (-x, -y, z), (x, -y, z), (x, y, z), (-x, y, z)]
    f = [(0, 2, 1), (0, 3, 2), (4, 5, 6), (4, 6, 7), (0, 1, 5), (0, 5, 4), (3, 6, 2), (3, 7, 6), (0, 4, 7), (0, 7, 3),
         (1, 2, 6), (1, 6, 5)]
    return Mesh(v, f, smooth=False)


def tapered(mesh, y0, y1, k0, k1):
    """Scales x and z of every vertex by a factor running from k0 at y0 to k1 at y1."""
    t = np.clip((mesh.v[:, 1] - y0) / (y1 - y0), 0, 1)
    k = k0 + (k1 - k0) * t
    mesh.v[:, 0] *= k
    mesh.v[:, 2] *= k
    return mesh


def flat_tube(points, widths, thickness, sides=12):
    """A flattened tube (lava streams): wide along X, thin across the flow, following points in the YZ plane."""
    pts = [np.array(p, dtype=float) for p in points]
    verts, faces = [], []
    lateral = np.array([1.0, 0, 0])
    for i, p in enumerate(pts):
        tangent = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
        tangent /= np.linalg.norm(tangent) + 1e-9
        normal = np.cross(lateral, tangent)
        normal /= np.linalg.norm(normal) + 1e-9
        w = widths[i] / 2
        for j in range(sides):
            a = 2 * math.pi * j / sides
            verts.append(p + lateral * math.cos(a) * w + normal * math.sin(a) * thickness / 2)
    for i in range(len(pts) - 1):
        for j in range(sides):
            a = i * sides + j
            b = i * sides + (j + 1) % sides
            faces += [(a, a + sides, b), (b, a + sides, b + sides)]
    for ring, flip in ((0, True), ((len(pts) - 1) * sides, False)):
        center = len(verts)
        verts.append(np.mean(verts[ring:ring + sides], axis=0))
        for j in range(sides):
            a, b = ring + j, ring + (j + 1) % sides
            faces.append((center, b, a) if flip else (center, a, b))
    return Mesh(verts, faces)


def crusted_stream(path, widths, x0, phase, offsets, thickness=1.0, wobble=0.45):
    """A lava stream (flat tube) that wobbles side to side as it falls, with darker crust ribbons
    riding a hair in front of its face (never touching it, so no z-fighting). Returns (stream, ribbons)."""
    pts = []
    for i, (_, y, z) in enumerate(path):
        sway = 0.0 if i == 0 else wobble * math.sin(i * 1.3 + phase)
        pts.append((x0 + sway, y, z))
    stream = flat_tube(pts, widths, thickness, 12)
    ribbons = []
    for k, dx in enumerate(offsets):
        ribbon = []
        for i in range(2, len(pts) - 1):
            a, b = np.array(pts[i - 1]), np.array(pts[i + 1])
            tangent = (b - a) / (np.linalg.norm(b - a) + 1e-9)
            normal = np.cross(np.array([1.0, 0, 0]), tangent)
            normal /= np.linalg.norm(normal) + 1e-9
            across = (dx + 0.06 * math.sin(i * 0.9 + phase + k * 2.0)) * widths[i]
            face = thickness / 2 * math.sqrt(max(0.0, 1 - (2 * across / widths[i]) ** 2))  # follow the curved front
            ribbon.append(np.array(pts[i]) + np.array([across, 0, 0]) + normal * (face + 0.08))
        n = len(ribbon)
        ribbons.append(flat_tube(ribbon, [0.4 + 0.5 * math.sin(math.pi * (i + 0.5) / n) for i in range(n)], 0.16, 6))
    return stream, ribbons


def glyph(kind, size):
    """A rune shape (polygon in XY, centered) for glowing inlays."""
    if kind == 0:  # diamond
        return [(0, size), (size * 0.6, 0), (0, -size), (-size * 0.6, 0)]
    if kind == 1:  # sun
        return star(size, size * 0.5, 6)
    if kind == 2:  # flame
        pts = []
        for i in range(14):
            a = 2 * math.pi * i / 14
            r = size * (0.62 + 0.38 * max(0.0, math.sin(a)) ** 3)
            pts.append((math.cos(a) * r * 0.7, math.sin(a) * r * 1.15 - size * 0.15))
        return pts
    return [(-size * 0.25, size), (size * 0.25, size), (size * 0.25, -size), (-size * 0.25, -size)]  # bar


def rune(kind, size, depth=0.3):
    return extrude(glyph(kind, size), depth)


def banner(width, height, depth=0.3):
    """A hanging banner (polygon in XY, top edge at y = 0) with a swallowtail bottom."""
    w = width / 2
    notch = height * 0.16
    pts = [(-w, 0), (-w, -height), (0, -height + notch), (w, -height), (w, 0)]
    # Extrude fans from the centroid; insert extra points so the fan stays inside the shape.
    dense = []
    for i in range(len(pts)):
        a, b = np.array(pts[i]), np.array(pts[(i + 1) % len(pts)])
        for t in np.linspace(0, 1, 4, endpoint=False):
            dense.append(tuple(a + (b - a) * t))
    mesh = extrude(dense, depth)
    # A gentle ripple, so it reads as cloth.
    mesh.v[:, 2] += np.sin(mesh.v[:, 0] * 1.3 + mesh.v[:, 1] * 0.35) * 0.18
    return mesh


def fan(pivot, rim, depth):
    """A thin webbed fan (frills): a triangle fan from `pivot` through the `rim` points, `depth` thick along Z."""
    verts, faces = [], []
    half = np.array([0, 0, depth / 2])
    for p in [pivot] + rim:
        verts += [np.array(p) - half, np.array(p) + half]
    n = len(rim)
    for i in range(n - 1):
        a, b = 2 + 2 * i, 2 + 2 * (i + 1)
        faces += [(0, a, b), (1, b + 1, a + 1)]  # front (-Z), back (+Z)
        faces += [(a, a + 1, b + 1), (a, b + 1, b)]  # outer edge
    for a in (2, 2 * n):  # the two edges back to the pivot
        faces += [(0, 1, a + 1), (0, a + 1, a)]
    mesh = Mesh(verts, faces, smooth=False)
    if np.mean(mesh.v[[2 + 2 * i for i in range(n)], 0]) - pivot[0] < 0:  # mirrored side: flip winding
        mesh.f = mesh.f[:, ::-1]
    return mesh


def flame_emblem(size, depth=0.25):
    return extrude(glyph(2, size), depth)


# ---------------------------------------------------------------- dragon head

def dragon_head():
    """A horned dragon head, snout to -Z, jaws open. Returns pieces in head-local units (about 24 x 22 x 34)."""

    def jaw(p):
        q = p * np.array([0.55, 1.0, 1.0])
        return sd_capsule(q, (0, -3.0, 2.0), (0, -7.4, -13.0), 1.3) * 1.5

    def field(p):
        d = sd_ellipsoid(p, (0, 4.2, 3.5), (7.2, 6.8, 7.8))  # skull
        d = smin(d, sd_ellipsoid(p, (0, 3.0, -8.5), (4.6, 3.0, 11.0)), 2.6)  # long upper snout
        d = smin(d, jaw(p), 2.0)  # lower jaw, hanging wide open
        for side in (-1, 1):
            d = smin(d, sd_capsule(p, (side * 2.0, 6.6, -8.0), (side * 5.6, 9.4, 0.5), 1.7), 1.2)  # angry brow
            d = smin(d, sd_ellipsoid(p, (side * 6.2, 0.6, 2.5), (2.8, 4.4, 5.6)), 2.0)  # cheek
            d = smin(d, sd_ellipsoid(p, (side * 1.9, 5.0, -17.6), (1.4, 1.2, 1.9)), 1.0)  # nostril
        d = smin(d, sd_capsule(p, (0, 6.0, -15.0), (0, 8.6, -2.0), 1.0), 1.4)  # ridge along the snout
        cavity = sd_ellipsoid(p, (0, -2.6, -10.5), (3.6, 2.0, 9.5))
        return np.maximum(d, -cavity)

    skin = sdf_mesh(field, (-12, -12, -22), (12, 13, 13), 0.62)
    skin.smooth = True

    horns = []
    for side in (-1, 1):
        path = [(side * 4.6, 9.4, 3.0), (side * 6.8, 12.4, 8.0), (side * 8.2, 14.0, 13.0), (side * 8.8, 14.4, 17.0),
                (side * 8.2, 16.4, 20.5)]
        horns.append(taper(path, 2.0, 0.08, 10))
        frill = [(side * 7.0, 0.5, 4.0), (side * 9.6, 0.0, 8.0), (side * 12.0, -1.0, 12.0)]  # cheek spikes
        horns.append(taper(frill, 1.3, 0.06, 8))
        horns.append(taper([(side * 6.4, -3.0, 2.0), (side * 8.6, -5.0, 6.0), (side * 10.4, -6.6, 9.5)], 0.9, 0.05, 8))
    for i, z in enumerate((6.0, 10.0, 13.5)):  # crest spikes down the back of the head
        base_y = 10.2 - i * 1.6
        horns.append(taper([(0, base_y, z), (0, base_y + 3.6 - i * 0.6, z + 2.6)], 1.2 - i * 0.15, 0.06, 8))

    teeth = []
    for side in (-1, 1):
        for x, z in ((3.2, -16.0), (3.0, -12.0), (3.3, -8.0)):
            teeth.append(taper([(side * x, -0.2, z), (side * x, -2.2, z - 0.2)], 0.6, 0.05, 6))  # upper fangs
        for x, z in ((2.6, -13.4), (2.9, -9.0)):
            teeth.append(taper([(side * x, -5.6, z), (side * x, -3.8, z + 0.2)], 0.5, 0.05, 6))  # lower fangs

    eyes = []
    for side in (-1, 1):
        # Seat each eye on the surface: march from inside the head towards the eye spot.
        direction = np.array([side * 0.6, 0.18, -0.78])
        direction /= np.linalg.norm(direction)
        start = np.array([0, 5.0, 0.0])
        t = 0.0
        while field((start + direction * t)[None])[0] < 0 and t < 20:
            t += 0.1
        spot = start + direction * (t - 0.55)
        eyes.append(icosphere(1.0, 2).scale(1.35, 0.85, 1.25).translate(*spot))

    # Webbed frills fanning out behind the cheeks (facing forward): the dragon's silhouette at phone size.
    frills = []
    for side in (-1, 1):
        pivot = np.array([side * 6.0, 2.6, 5.5])
        rim = []
        angles = np.linspace(-45, 75, 9)
        for k, a in enumerate(angles):
            r = 11.5 - abs(a - 15) * 0.03 if k % 2 == 0 else 7.2
            d = np.array([side * math.cos(math.radians(a)), math.sin(math.radians(a)), 0.0])
            rim.append(pivot + d * r + np.array([0, 0, 0.12 * r]))  # swept back a little
            if k % 2 == 0:  # a gold spike along each rib, poking out past the web
                horns.append(taper([tuple(pivot + d * 3.0 + np.array([0, 0, 0.36])), tuple(pivot + d * (r + 2.2) + np.array([0, 0, 0.12 * (r + 2.2)]))],
                                   0.55, 0.06, 6))
        frills.append(fan(pivot, rim, 0.5))
    mouth_lava = icosphere(1.0, 2).scale(3.0, 1.0, 6.5).translate(0, -3.4, -9.0)
    return {"Skin": skin, "Horns": merge(*horns), "Teeth": merge(*teeth), "Eyes": merge(*eyes), "MouthLava": mouth_lava,
            "Frills": merge(*frills)}


def place(mesh, scale, offset):
    return mesh.copy().scale(scale).translate(*offset)


# ---------------------------------------------------------------- props

def dragon_temple():
    """Backdrop centerpiece: a stepped temple rising from the lava, a dragon head on top pouring lava
    down a cascade between twin stairs, gold cornices, rune inlays, obelisks and banners. Faces -Z."""
    stone, trim, glow, lava, cloth, emblem, dark, crust = [], [], [], [], [], [], [], []
    tiers = [  # width, height, depth, z center, y bottom
        (100, 14, 70, 0.0, 0.0),
        (82, 13, 56, 3.0, 14.0),
        (64, 12, 44, 6.0, 27.0),
        (46, 11, 32, 9.0, 39.0),
    ]
    for width, height, depth, zc, y0 in tiers:
        stone.append(rounded_box(width, height, depth, 0.8, 3).translate(0, y0 + height / 2, zc))
        trim.append(rounded_box(width + 1.6, 1.2, depth + 1.6, 0.5, 2).translate(0, y0 + height - 0.3, zc))
        # Runes in a row across the tier front, either side of the stairs.
        front = zc - depth / 2
        count = int((width / 2 - 20) // 7)
        for side in (-1, 1):
            for k in range(count):
                x = side * (20 + 3.5 + k * 7)
                glow.append(rune((k + int(y0)) % 4, 1.5).translate(x, y0 + height * 0.45, front - 0.1))
    # Shrine on top, behind the head.
    stone.append(rounded_box(30, 14, 20, 1.0, 3).translate(0, 57, 14))
    trim.append(rounded_box(32, 1.4, 22, 0.5, 2).translate(0, 64.2, 14))
    stone.append(rounded_box(22, 3, 14, 0.8, 3).translate(0, 66.2, 15))

    # Twin stairs from the lava up to the top tier, the lava cascade between them.
    rise, run, steps = 2.0, 1.6, 25
    for side in (-1, 1):
        for k in range(steps):
            h = rise * (k + 1)
            stone.append(box(9, h, run).translate(side * 10.5, h / 2, -47 + run * (k + 0.5)))
        # Cheek walls along the outer and inner edges of each stair.
        for x in (side * 5.4, side * 15.6):
            length = math.hypot(40, 50)
            wall = box(1.4, 2.6, length + 2).rotate("x", -math.degrees(math.atan2(50, 40))).translate(x, 26.2, -27.4)
            dark.append(wall)
    # Lava cascade from the dragon's mouth: falls, tier tops, falls, into the lake, crusted and wobbling
    # like the cliffs' lava falls. The arena sinks the temple so the lake meets it at about y = 10.7
    # (see TEMPLE_SINK); a churning splash mound rises out of the lake at the cascade's foot.
    path = [(0, 54.5, -19.5), (0, 52.0, -21.0), (0, 46.0, -21.6), (0, 36.0, -21.8), (0, 28.6, -21.8), (0, 27.6, -23.0),
            (0, 27.5, -25.0), (0, 26.0, -26.3), (0, 20.0, -26.9), (0, 15.2, -27.2), (0, 14.65, -29.0), (0, 14.6, -34.4),
            (0, 13.2, -35.9), (0, 7.0, -36.7), (0, 2.2, -37.6), (0, 1.5, -40.0)]
    widths = [4.6, 5.0, 5.4, 5.8, 6.2, 6.6, 7.0, 7.2, 7.4, 7.6, 8.0, 8.4, 8.6, 8.8, 9.0, 9.4]
    stream, ribbons = crusted_stream(path, widths, 0.0, 0.6, (-0.22, 0.2), thickness=0.9, wobble=0.35)
    lava.append(stream)
    crust += ribbons
    for k, (x, y, z, rx, ry, rz) in enumerate(((0, 9.0, -40.0, 5.6, 4.6, 4.4), (-3.8, 8.2, -42.4, 3.6, 4.2, 3.2),
                                               (3.8, 8.0, -42.0, 3.4, 4.2, 3.2), (0, 7.4, -45.0, 5.0, 4.0, 3.4))):
        lava.append(icosphere(1.0, 2, 0.12, seed=21 + k).scale(rx, ry, rz).translate(x, y, z))
    for k in range(7):  # droplets thrown up by the splash
        a = k / 7 * 2 * math.pi
        lava.append(icosphere(0.55 + 0.2 * (k % 3), 1).translate(math.cos(a) * 6.5, 13.5 + 1.6 * ((k * 5) % 3), -42 + math.sin(a) * 4.5))

    # Obelisks on the first tier's front corners, gold tips and a rune stripe.
    for side in (-1, 1):
        x, z = side * 42, -28
        shaft = lathe([(2.9, 0), (2.9, 1.2), (2.3, 1.6), (1.9, 18), (0, 18.01)], 4).rotate("y", 45)
        shaft.smooth = False
        stone.append(shaft.translate(x, 14, z))
        trim.append(lathe([(1.95, 0), (0, 3.2)], 4).rotate("y", 45).translate(x, 31.6, z))
        for k in range(4):
            glow.append(rune(k % 3, 0.55, 0.2).translate(x, 18 + k * 3.2, z - 2.1 + k * 0.07))

    # Banners hanging from the top tier front, either side of the head.
    for side in (-1, 1):
        cloth.append(banner(6.5, 13).translate(side * 14.5, 49.6, -7.45))
        emblem.append(flame_emblem(1.9).translate(side * 14.5, 44.4, -7.85))
        trim.append(cylinder(0.35, 8.0, 10).rotate("z", 90).translate(side * 14.5 + 4.0, 49.8, -7.6))

    head = dragon_head()
    s, at = 1.89, (0, 66.0, 6.0)  # the head is big for the tiers on purpose: it has to read from the bridge
    return {
        "Stone": merge(*stone),
        "Trim": merge(*trim, place(head["Horns"], s, at)),
        "Cloth": merge(*cloth, place(head["Frills"], s, at)),
        "Crust": merge(*crust),
        "Dark": merge(*dark, place(head["Skin"], s, at)),
        "Glow": merge(*glow),
        "Eyes": place(head["Eyes"], s, at),
        "Teeth": place(head["Teeth"], s, at),
        "Lava": merge(*lava, place(head["MouthLava"], s, at)),
        "Emblem": merge(*emblem),
    }


def rope_tower():
    """Stone tower that holds a fire wheel's axle: plinth, tapering rune shaft, gold bands, a sun
    medallion at axle height on the front (-Z), banners on the sides and a fire bowl on top."""
    stone, trim, glow, cloth, emblem, metal = [], [], [], [], [], []
    stone.append(rounded_box(9.5, 4.0, 9.5, 0.6, 3).translate(0, 2.0, 0))
    trim.append(rounded_box(10.1, 0.8, 10.1, 0.3, 2).translate(0, 4.0, 0))
    shaft = rounded_box(6.4, 34.2, 6.4, 0.5, 4).translate(0, 4.2 + 17.1, 0)
    stone.append(tapered(shaft, 4.2, 38.4, 1.0, 0.86))
    for y in (9.0, 21.0):
        trim.append(tapered(rounded_box(7.0, 0.9, 7.0, 0.35, 2).translate(0, y, 0), 4.2, 38.4, 1.0, 0.86))
    stone.append(rounded_box(8.2, 1.6, 8.2, 0.5, 3).translate(0, 38.6, 0))
    trim.append(rounded_box(8.8, 0.7, 8.8, 0.3, 2).translate(0, 39.6, 0))
    # Runes down the front and both sides.
    for k, y in enumerate((12.0, 15.2, 18.4, 24.4, 27.6, 30.8)):
        half = 3.2 * (1.0 - 0.14 * (y - 4.2) / 34.2)
        glow.append(rune(k % 4, 0.9, 0.24).translate(0, y, -half - 0.08))
        for side in (-1, 1):
            glow.append(rune((k + 2) % 4, 0.9, 0.24).rotate("y", 90).translate(side * (half + 0.08), y, 0))
    # Sun medallion where the wheel's axle meets the tower (35.4 above the base).
    half = 3.2 * (1.0 - 0.14 * (35.4 - 4.2) / 34.2)
    trim.append(torus(2.3, 0.42, 28, 8).rotate("x", 90).translate(0, 35.4, -half - 0.1))
    trim.append(extrude(star(3.4, 2.5, 12), 0.35).translate(0, 35.4, -half + 0.05))
    metal.append(cylinder(1.6, 0.6, 20).rotate("x", 90).translate(0, 35.4, -half - 0.05))
    # Banners on the sides (they face the players).
    for side in (-1, 1):
        b = banner(4.2, 11.0, 0.25).rotate("y", 90).translate(side * (3.0 + 0.45), 37.6, 0)
        cloth.append(b)
        emblem.append(flame_emblem(1.25, 0.2).rotate("y", 90).translate(side * (3.0 + 0.72), 33.4, 0))
    # Fire bowl.
    metal.append(lathe([(1.4, 39.9), (2.4, 40.4), (3.3, 41.6), (3.7, 43.0), (3.4, 43.1), (2.6, 42.3), (0.0, 42.3)], 24))
    trim.append(torus(3.55, 0.28, 32, 8).translate(0, 43.05, 0))
    coals = icosphere(1.0, 2, 0.15, seed=3).scale(2.9, 0.75, 2.9).translate(0, 42.4, 0)
    return {"Stone": merge(*stone), "Trim": merge(*trim), "Glow": merge(*glow), "Cloth": merge(*cloth),
            "Emblem": merge(*emblem), "Metal": merge(*metal), "Coals": coals}


def sun_wheel():
    """The wheel that turns the fire rope: an iron rim ringed with curved flame blades, glowing
    spokes and a gold hub. Stands in the YZ plane with its axle along X; the rope hangs at radius
    9.5 from the axle."""
    major = 10.2
    rim = [torus(major, 0.95, 72, 12), torus(major - 1.3, 0.34, 72, 8), cylinder(0.8, 6.4, 16, 0.2).translate(0, -3.2, 0)]
    trim = [icosphere(0.5, 1).translate(math.cos(a) * major, s * 0.8, math.sin(a) * major)
            for a in np.linspace(0, 2 * math.pi, 12, endpoint=False) for s in (-1, 1)]
    trim.append(cylinder(2.1, 3.0, 28, 0.4).translate(0, -1.5, 0))
    flames = []
    for a in np.linspace(0, 2 * math.pi, 12, endpoint=False):
        path = []
        for t in np.linspace(0, 1, 6):
            r = major + 0.4 + 4.4 * t
            b = a + 0.3 * t ** 1.5
            path.append((math.cos(b) * r, 0, math.sin(b) * r))
        blade = taper(path, 1.9, 0.08, 8)
        blade.v[:, 1] *= 0.36
        flames.append(blade)
    spokes = [tube([(math.cos(a) * 2.0, 0, math.sin(a) * 2.0), (math.cos(a) * (major - 0.8), 0, math.sin(a) * (major - 0.8))], 0.36, 8)
              for a in np.linspace(0, 2 * math.pi, 8, endpoint=False) + math.pi / 8]
    eye = merge(icosphere(1.0, 2).scale(1.2, 0.5, 1.2).translate(0, 1.55, 0), icosphere(1.0, 2).scale(1.2, 0.5, 1.2).translate(0, -1.55, 0))
    lift = major + 0.4 + 4.4

    def stand(mesh):
        return mesh.rotate("z", 90).translate(0, lift, 0)

    return {"Rim": stand(merge(*rim)), "Trim": stand(merge(*trim)), "Flames": stand(merge(*flames)),
            "Spokes": stand(merge(*spokes)), "Eye": stand(eye)}


def fire_brazier():
    """A fluted stone column rising out of the lava with gold rings, a rune band and an iron fire bowl."""
    column = organic_lathe([(3.7, 0), (3.7, 1.6), (3.0, 2.4), (2.3, 3.4), (2.1, 19.4), (2.5, 20.4), (2.9, 21.0), (2.9, 22.0)], 24, 0.05,
                           waves=12, seed=5)
    trim = [torus(2.35, 0.32, 28, 8).translate(0, 3.3, 0), torus(2.25, 0.3, 28, 8).translate(0, 12.5, 0),
            torus(2.95, 0.3, 28, 8).translate(0, 21.9, 0), torus(4.55, 0.32, 36, 8).translate(0, 27.75, 0)]
    glow = [rune(k % 3, 0.6, 0.2).translate(0, 0, -2.18).rotate("y", k * 60).translate(0, 16.4, 0) for k in range(6)]
    bowl = lathe([(1.6, 21.9), (2.6, 22.6), (3.8, 24.4), (4.5, 26.6), (4.6, 27.7), (4.2, 27.8), (3.7, 26.9), (0.0, 26.9)], 28)
    claws = [taper([(math.cos(a) * 4.0, 25.4, math.sin(a) * 4.0), (math.cos(a) * 5.1, 27.4, math.sin(a) * 5.1),
                    (math.cos(a) * 4.9, 28.9, math.sin(a) * 4.9)], 0.42, 0.05, 6) for a in np.linspace(0, 2 * math.pi, 6, endpoint=False)]
    coals = icosphere(1.0, 2, 0.18, seed=9).scale(3.9, 0.9, 3.9).translate(0, 27.0, 0)
    return {"Stone": column, "Trim": merge(*trim, *claws), "Glow": merge(*glow), "Metal": bowl, "Coals": coals}


def lava_fall():
    """A cliff of basalt columns with lava pouring over its middle into a pool at its foot. Faces -Z."""
    rng = np.random.default_rng(17)
    columns = []
    rows = (  # z, half width, height range, radius
        (9.0, 15.0, (44.0, 52.0), 3.4),
        (2.5, 13.0, (32.0, 42.0), 3.2),
        (-4.0, 19.0, (12.0, 26.0), 3.0),
        (-10.0, 22.0, (3.0, 9.0), 2.6),
    )
    for row, (z, half, (low, high), radius) in enumerate(rows):
        x = -half
        while x <= half:
            if row >= 2 and abs(x) < 7.5:
                x += radius * 1.7
                continue  # the fall runs here
            h = rng.uniform(low, high)
            if row == 1 and abs(x) < 4.5:
                h = 41.0  # the lip the lava pours over
            r = radius * rng.uniform(0.85, 1.1)
            col = lathe([(r, 0.0), (r, h), (r * 0.82, h + 0.7), (0.0, h + 0.9)], 6).rotate("y", rng.uniform(0, 60))
            col.translate(x + rng.uniform(-0.4, 0.4), 0, z + rng.uniform(-0.8, 0.8))
            columns.append(col)
            x += r * 1.75
    rubble = [icosphere(r, 1, 0.3, seed=s).scale(1.2, 0.7, 1.1).translate(x, 0.6, z)
              for s, (x, z, r) in enumerate(((-9.5, -15.0, 2.6), (10.0, -16.0, 2.9), (-15.0, -13.0, 2.2), (15.5, -12.5, 2.0)))]
    rock = merge(*columns, *rubble)
    rock.smooth = False
    # Three streams (a wide one down the middle, two thin ones off the lip) that wobble as they fall,
    # with darker crust ribbons riding on their fronts so they read as flowing lava.
    path = [(0, 44.5, 10.0), (0, 43.0, 4.0), (0, 42.6, 0.5), (0, 41.6, -1.8), (0, 38.0, -3.6), (0, 28.0, -4.6),
            (0, 16.0, -5.4), (0, 6.0, -6.6), (0, 2.0, -9.0), (0, 1.5, -13.0)]
    streams = (  # x, widths along the path, first path point, wobble phase
        (0.0, [3.6, 3.8, 4.0, 4.4, 4.8, 5.2, 5.5, 5.8, 6.0, 6.0], 0, 0.0),
        (-5.0, [2.4, 2.5, 2.6, 2.8, 3.0, 3.2, 3.4, 3.4], 2, 1.7),
        (5.0, [2.4, 2.5, 2.6, 2.8, 3.0, 3.2, 3.4, 3.4], 2, 3.1),
    )
    falls, crust = [], []
    for x0, widths, first, phase in streams:
        offsets = (-0.2, 0.18) if x0 == 0.0 else (0.04,)  # fractions of the stream's width
        stream, ribbons = crusted_stream(path[first:], widths, x0, phase, offsets)
        falls.append(stream)
        crust += ribbons
    pool = icosphere(1.0, 2).scale(11.0, 0.6, 7.5).translate(0, 1.2, -14.0)
    return {"Rock": rock, "Lava": merge(*falls, pool), "Crust": merge(*crust)}


def crater_wall():
    """A stretch of the crater's basalt wall (about 92 wide, curving towards the lake's center 172
    studs in front of it), with a thin crusted lava trickle down its middle. Faces -Z."""
    rng = np.random.default_rng(29)
    bend = 172.0
    columns = []
    rows = ((7.0, (40.0, 62.0), 3.8), (0.5, (24.0, 42.0), 3.5), (-6.0, (6.0, 20.0), 3.0))  # z, heights, radius
    for row, (z, (low, high), radius) in enumerate(rows):
        x = -46.0 + rng.uniform(0, 2)
        while x <= 46.0:
            h = rng.uniform(low, high) * (1.0 - 0.25 * (abs(x) / 46.0) ** 2)  # lower towards the ends
            r = radius * rng.uniform(0.85, 1.15)
            if row == 2 and abs(x) < 4.0:
                x += r * 1.7
                continue  # the trickle runs here
            if row == 1 and abs(x) < 3.5:
                h = 33.6  # the lip it pours over
            col = lathe([(r, 0.0), (r, h), (r * 0.8, h + 0.8), (0.0, h + 1.0)], 6).rotate("y", rng.uniform(0, 60))
            col.translate(x + rng.uniform(-0.5, 0.5), 0, z + rng.uniform(-1.0, 1.0) - x * x / (2 * bend))
            columns.append(col)
            x += r * 1.7
    rubble = [icosphere(r, 1, 0.3, seed=40 + k).scale(1.2, 0.7, 1.1).translate(x, 0.5, -10.5 - x * x / (2 * bend))
              for k, (x, r) in enumerate(((-30.0, 2.6), (-12.0, 2.2), (9.0, 2.8), (27.0, 2.3)))]
    rock = merge(*columns, *rubble)
    rock.smooth = False
    # The trickle pours from a notch in the middle row and runs down the front row.
    path = [(0, 35.2, 2.0), (0, 34.6, -1.0), (0, 33.6, -3.0), (0, 26.0, -4.4), (0, 16.0, -5.6), (0, 8.0, -7.0),
            (0, 2.4, -9.0), (0, 0.6, -12.0)]
    stream, ribbons = crusted_stream(path, [2.8, 3.0, 3.2, 3.5, 3.8, 4.0, 4.2, 4.4], 0.0, 2.2, (0.0,), thickness=0.8)
    return {"Rock": rock, "Lava": stream, "Crust": merge(*ribbons)}


def temple_bridge():
    """What holds up the bridge deck (the deck itself is the arena's own part): three round arches on
    piers with pointed cutwaters, gold pier caps, and a fascia band with glowing runes just below the
    deck. Base on the lava, the deck's underside at y = 22, spans x = -37..37."""
    stone, trim, glow, dark = [], [], [], []
    spring, depth = 9.0, 7.0
    piers = (-35.5, -12.0, 12.0, 35.5)
    for x in piers:
        stone.append(box(5.0, spring + 0.6, 9.0).translate(x, (spring + 0.6) / 2, 0))
        for side in (-1, 1):  # cutwaters
            prism = extrude([(0, -2.25), (2.0, 0), (0, 2.25)], spring - 1.0).rotate("x", 90).rotate("y", -90 * side)
            prism.v[:, 1] += (spring - 1.0) / 2
            stone.append(prism.translate(x, 0, side * 4.5))
        trim.append(rounded_box(6.0, 0.9, 10.0, 0.3, 2).translate(x, spring + 0.3, 0))
    # Spandrel walls with round openings, built as fans from each arch's center.
    for x0, x1 in zip(piers[:-1], piers[1:]):
        left, right = x0 + 2.5, x1 - 2.5
        xc, radius = (left + right) / 2, (right - left) / 2
        top = 20.6
        verts, faces = [], []
        corner = math.atan2(top - spring, right - xc)  # the rays through the top corners
        thetas = sorted(set(np.linspace(math.pi, 0, 25).tolist() + [math.pi - corner, corner]), reverse=True)
        n = len(thetas) - 1
        for th in thetas:
            c, s = math.cos(th), math.sin(th)
            inner = (xc + c * radius, spring + s * radius)
            # Where the ray from the center leaves the box [left, right] x [spring, top].
            ts = []
            if c < -1e-6:
                ts.append((left - xc) / c)
            if c > 1e-6:
                ts.append((right - xc) / c)
            if s > 1e-6:
                ts.append((top - spring) / s)
            t = min(ts)
            outer = (xc + c * t, spring + s * t)
            for zz in (-depth / 2, depth / 2):
                verts.append((inner[0], inner[1], zz))
                verts.append((outer[0], outer[1], zz))
        for i in range(n):
            a = i * 4
            b = a + 4
            # front (z-), back (z+), intrados
            faces += [(a, a + 1, b + 1), (a, b + 1, b)]
            faces += [(a + 2, b + 3, a + 3), (a + 2, b + 2, b + 3)]
            faces += [(a, b, b + 2), (a, b + 2, a + 2)]
        stone.append(Mesh(verts, faces, smooth=False))
        # Arch ring (voussoirs), standing proud of the wall.
        ring_v, ring_f = [], []
        for i in range(n + 1):
            th = math.pi * (1 - i / n)
            c, s = math.cos(th), math.sin(th)
            for r in (radius - 0.15, radius + 1.3):
                for zz in (-depth / 2 - 0.3, depth / 2 + 0.3):
                    ring_v.append((xc + c * r, spring + s * r, zz))
        for i in range(n):
            a, b = i * 4, i * 4 + 4
            # vertices per step: 0 inner-front, 1 inner-back, 2 outer-front, 3 outer-back
            ring_f += [(a, b, b + 2), (a, b + 2, a + 2)]  # front face
            ring_f += [(a + 1, a + 3, b + 3), (a + 1, b + 3, b + 1)]  # back face
            ring_f += [(a, a + 1, b + 1), (a, b + 1, b)]  # inner
            ring_f += [(a + 2, b + 2, b + 3), (a + 2, b + 3, a + 3)]  # outer
        trim.append(Mesh(ring_v, ring_f, smooth=False))
    # Wall over each pier, between the arches.
    stone += [box(5.0, 20.6 - spring - 0.6, depth).translate(x, (20.6 + spring + 0.6) / 2, 0) for x in piers]
    # Fascia band under the deck, gold cornice, rune inlays.
    dark.append(rounded_box(74.6, 2.0, 9.2, 0.4, 2).translate(0, 21.2, 0))
    trim.append(rounded_box(75.2, 0.6, 9.8, 0.25, 2).translate(0, 22.3, 0))
    for k in range(18):
        x = -34 + k * 4
        for side in (-1, 1):
            glow.append(rune(k % 4, 0.55, 0.2).translate(x, 21.2, side * 4.66))
    return {"Stone": merge(*stone), "Trim": merge(*trim), "Glow": merge(*glow), "Dark": merge(*dark)}


PROPS = {
    "DragonTemple": dragon_temple,
    "RopeTower": rope_tower,
    "SunWheel": sun_wheel,
    "FireBrazier": fire_brazier,
    "LavaFall": lava_fall,
    "CraterWall": crater_wall,
    "TempleBridge": temple_bridge,
}
COLORS = {
    "Stone": (196, 120, 92),
    "Trim": (255, 196, 64),
    "Dark": (58, 40, 54),
    "Eyes": (255, 240, 120),
    "Teeth": (250, 240, 215),
    "Cloth": (220, 40, 60),
    "Emblem": (255, 210, 70),
    "Metal": (60, 48, 56),
    "Coals": (255, 150, 50),
    "Flames": (255, 130, 40),
    "Eye": (255, 230, 90),
    "Rim": (60, 48, 56),
    "Rock": (70, 52, 60),
    "Crust": (200, 64, 30),
}
