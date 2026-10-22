"""Meshes for Hot Potato (see tools/meshgen/props/README.md). Units are studs, +Y up, base on y = 0,
-Z is the front. Generate with:
    python3 tools/meshgen/generate_meshes.py --only HotPotatoSpud,HotPotatoPuff,HotPotatoFence,HotPotatoLights,HotPotatoGrill,HotPotatoTable,HotPotatoHay

The potato bomb is a lumpy baked spud with a metal cap and a curling fuse; the backyard has picket fence
panels (13.5 studs: a jump from a table top still falls 2.7 short), string lights for the fence top, a giant kettle grill with
foil-wrapped potatoes on it, picnic tables and hay bales, and a cartoon blast puff."""

import math

import numpy as np

from generate_meshes import Mesh, extrude, icosphere, lathe, merge, rounded_box, taper, torus, tube


def _base(mesh_pieces):
    """Moves every piece so the whole prop sits on y = 0."""
    low = min(m.v[:, 1].min() for m in mesh_pieces.values())
    for m in mesh_pieces.values():
        m.translate(0, -low, 0)
    return mesh_pieces


def spud():
    body = icosphere(1.0, 3, noise=0.12, seed=7).scale(1.2, 0.86, 0.82)
    body.translate(0, 0.9, 0)
    rng = np.random.default_rng(3)
    eyes = []
    for _ in range(7):
        theta = rng.uniform(0, 2 * math.pi)
        phi = rng.uniform(-0.7, 0.7)
        d = np.array([math.cos(theta) * math.cos(phi), math.sin(phi), math.sin(theta) * math.cos(phi)])
        p = d * np.array([1.18, 0.84, 0.8]) + np.array([0, 0.9, 0])
        eyes.append(icosphere(0.09, 1).scale(1.6, 0.7, 1.0).translate(*p))
    cap = lathe([(0.0, 1.55), (0.46, 1.55), (0.5, 1.7), (0.44, 1.9), (0.22, 1.98), (0.0, 1.98)], 20)
    fuse_pts = [(0.0, 1.9, 0.0), (0.05, 2.1, 0.0), (0.18, 2.3, 0.05), (0.32, 2.4, 0.08)]
    fuse = taper(fuse_pts, 0.1, 0.07, 8)
    spark = icosphere(0.2, 1, noise=0.5, seed=2).translate(0.38, 2.45, 0.08)
    return _base({"Spud": body, "Eyes": merge(*eyes), "Cap": cap, "Fuse": fuse, "Spark": spark})


def puff():
    blobs = []
    for i, (x, y, z, r) in enumerate([(0, 1.6, 0, 1.6), (1.3, 1.3, 0.3, 1.1), (-1.2, 1.4, -0.2, 1.2), (0.3, 2.6, -0.4, 1.1),
                                      (-0.4, 1.2, 1.1, 1.0), (0.5, 1.0, -1.1, 1.0)]):
        blobs.append(icosphere(r, 2, noise=0.15, seed=i).translate(x, y, z))
    return _base({"Puff": merge(*blobs)})


def fence():
    width, height = 8.4, 13.5
    pickets = []
    count = 13
    step = width / count
    w = step + 0.02  # planks butt together: no gaps to see (or rays) through
    for i in range(count):
        x = -width / 2 + step * (i + 0.5)
        outline = [(x - w / 2, 0.0), (x + w / 2, 0.0), (x + w / 2, height - 0.45), (x, height), (x - w / 2, height - 0.45)]
        pickets.append(extrude(outline, 0.8))
    rails = merge(rounded_box(width, 0.6, 0.65, 0.08, 3).translate(0, 2.0, 0.68),
                  rounded_box(width, 0.6, 0.65, 0.08, 3).translate(0, 11.2, 0.68))
    posts = merge(rounded_box(0.9, 13.0, 1.0, 0.1, 3).translate(-width / 2, 6.5, 0.5),
                  rounded_box(0.9, 13.0, 1.0, 0.1, 3).translate(width / 2, 6.5, 0.5))
    return {"Pickets": merge(*pickets), "Rails": rails, "Posts": posts}


def lights():
    span, top, sag = 8.0, 1.3, 0.55
    pts = []
    for i in range(17):
        t = i / 16
        x = -span / 2 + span * t
        pts.append((x, top - sag * 4 * t * (1 - t), 0.0))
    wire = tube(pts, 0.04, 6)
    bulbs = {"BulbA": [], "BulbB": [], "BulbC": []}
    names = ["BulbA", "BulbB", "BulbC"]
    for i in range(7):
        t = (i + 0.5) / 7
        x = -span / 2 + span * t
        y = top - sag * 4 * t * (1 - t)
        bulb = lathe([(0.0, -0.42), (0.12, -0.38), (0.17, -0.28), (0.14, -0.16), (0.07, -0.08), (0.0, -0.06)], 12)
        bulbs[names[i % 3]].append(bulb.translate(x, y, 0))
    out = {"Wire": wire}
    for name, parts in bulbs.items():
        out[name] = merge(*parts)
    return _base(out)


def grill():
    bowl = lathe([(0.0, 3.8), (1.5, 3.85), (2.8, 4.3), (3.6, 5.3), (3.9, 6.4), (3.95, 7.0), (3.72, 7.0), (3.66, 6.4),
                  (3.36, 5.4), (2.6, 4.5), (1.4, 4.05), (0.0, 4.0)], 40)
    rim = torus(3.85, 0.14, 48, 10).translate(0, 7.0, 0)
    bars = []
    for i in range(-6, 7):
        x = i * 0.52
        half = math.sqrt(max(3.6 ** 2 - x * x, 0.1))
        bars.append(rounded_box(0.12, 0.12, half * 2, 0.04, 2).translate(x, 6.75, 0))
    bars.append(torus(3.6, 0.08, 48, 8).translate(0, 6.75, 0))
    coals = []
    rng = np.random.default_rng(5)
    for i in range(16):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0, 2.4)
        coals.append(icosphere(rng.uniform(0.35, 0.55), 1, noise=0.3, seed=i).scale(1, 0.7, 1)
                     .translate(math.cos(a) * r, 4.6 + rng.uniform(0, 0.4), math.sin(a) * r))
    legs = []
    wheels = []
    for k in range(3):
        a = 2 * math.pi * k / 3 + math.pi / 2
        top = (math.cos(a) * 2.4, 4.4, math.sin(a) * 2.4)
        foot = (math.cos(a) * 3.6, 0.45, math.sin(a) * 3.6)
        legs.append(taper([top, foot], 0.22, 0.18, 10))
        if k > 0:
            wheel = lathe([(0.0, -0.2), (0.45, -0.2), (0.5, -0.1), (0.5, 0.1), (0.45, 0.2), (0.0, 0.2)], 20)
            wheel.rotate("z", 90).rotate("y", -math.degrees(a)).translate(foot[0], 0.5, foot[2])
            wheels.append(wheel)
        else:
            legs.append(lathe([(0.0, 0.0), (0.4, 0.0), (0.3, 0.5), (0.0, 0.5)], 12).translate(foot[0], 0, foot[2]))
    shelf = torus(3.0, 0.1, 40, 8).translate(0, 1.6, 0)
    spuds = []
    foil = []
    for i, (x, z, turn) in enumerate([(-1.4, -0.6, 20), (1.2, -1.0, -35), (0.1, 1.4, 70)]):
        s = icosphere(1.0, 2, noise=0.12, seed=10 + i).scale(1.05, 0.62, 0.7).rotate("y", turn).translate(x, 7.35, z)
        f = icosphere(1.0, 2, noise=0.25, seed=20 + i).scale(1.08, 0.5, 0.75).rotate("y", turn).translate(x, 7.12, z)
        spuds.append(s)
        foil.append(f)
    return _base({"Bowl": merge(bowl, rim), "Grate": merge(*bars), "Coals": merge(*coals), "Legs": merge(*legs, shelf),
                  "Wheels": merge(*wheels), "Spuds": merge(*spuds), "Foil": merge(*foil)})


def table():
    planks = [rounded_box(7.0, 0.3, 0.58, 0.06, 3).translate(0, 3.4, -1.24 + 0.62 * i) for i in range(5)]
    benches = []
    for z in (-2.45, 2.45):
        benches += [rounded_box(7.0, 0.28, 0.5, 0.06, 3).translate(0, 1.75, z - 0.28),
                    rounded_box(7.0, 0.28, 0.5, 0.06, 3).translate(0, 1.75, z + 0.28)]
    legs = []
    for x in (-2.7, 2.7):
        for s in (-1, 1):
            leg = rounded_box(0.32, 3.9, 0.45, 0.06, 3).rotate("x", s * 40).translate(x, 1.62, s * 1.25)
            legs.append(leg)
        legs.append(rounded_box(0.3, 0.3, 6.0, 0.06, 3).translate(x, 1.5, 0))
        legs.append(rounded_box(0.3, 0.3, 2.9, 0.06, 3).translate(x, 3.12, 0))
    cloth = rounded_box(7.15, 0.06, 1.7, 0.02, 3).translate(0, 3.58, 0)
    return _base({"Top": merge(*planks), "Benches": merge(*benches), "Legs": merge(*legs), "Cloth": cloth})


def hay():
    bale = rounded_box(5.0, 2.8, 2.8, 0.25, 8)
    rng = np.random.default_rng(9)
    bale.v = bale.v + rng.normal(0, 0.015, bale.v.shape)
    bale.translate(0, 1.4, 0)
    twine = []
    for x in (-1.3, 1.3):
        loop = []
        for i in range(33):
            a = 2 * math.pi * i / 32
            y = math.sin(a) * 1.44
            z = math.cos(a) * 1.44
            loop.append((x, 1.4 + max(min(y, 1.3), -1.3) * 1.08, max(min(z, 1.3), -1.3) * 1.08))
        twine.append(tube(loop, 0.06, 6))
    return _base({"Hay": bale, "Twine": merge(*twine)})


PROPS = {
    "HotPotatoSpud": spud,
    "HotPotatoPuff": puff,
    "HotPotatoFence": fence,
    "HotPotatoLights": lights,
    "HotPotatoGrill": grill,
    "HotPotatoTable": table,
    "HotPotatoHay": hay,
}
COLORS = {
    "Spud": (196, 140, 78), "Eyes": (120, 78, 40), "Cap": (150, 156, 168), "Fuse": (70, 52, 40), "Spark": (255, 200, 60),
    "Puff": (255, 250, 240), "Pickets": (250, 246, 236), "Rails": (232, 224, 208), "Posts": (240, 234, 220),
    "Wire": (40, 40, 46), "BulbA": (255, 214, 110), "BulbB": (255, 140, 90), "BulbC": (140, 220, 255),
    "Bowl": (200, 50, 45), "Grate": (70, 70, 76), "Coals": (255, 110, 40), "Legs": (60, 60, 66), "Wheels": (30, 30, 34),
    "Spuds": (196, 140, 78), "Foil": (210, 214, 222), "Top": (176, 112, 64), "Benches": (160, 100, 58),
    "Cloth": (230, 70, 70), "Hay": (226, 190, 96), "Twine": (150, 100, 60),
}
