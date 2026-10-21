"""Meshes for Stamp Out (see tools/meshgen/props/README.md). Units are studs, +Y up, base on y = 0,
-Z is the front.

    python3 tools/meshgen/generate_meshes.py --only StampOutRider,StampOutBigStamp,StampOutInkPad,StampOutPencil,StampOutClip

- StampOutRider: the rubber stamp every player stands in (ink-coloured rubber, wooden block, ink band and
  two little grip knobs); recoloured per player by the game.
- StampOutBigStamp: a giant desk stamp (rubber, wooden block, turned neck, round knob).
- StampOutInkPad: an open ink-pad tin (tray, felt, lid standing up behind).
- StampOutPencil: a giant hexagonal pencil lying along X (paint, sharpened wood, lead, ferrule, eraser).
- StampOutClip: a giant paper clip lying flat (decoration: nothing collides with it).
"""

import math

from generate_meshes import lathe, merge, rounded_box, sphere, taper


def rider():
    rubber = rounded_box(3.4, 0.36, 2.8, 0.12).translate(0, 0.18, 0)
    block = rounded_box(3.7, 1.0, 3.1, 0.28).translate(0, 0.36 + 0.5, 0)
    band = rounded_box(3.8, 0.24, 3.2, 0.1).translate(0, 1.3, 0)
    knobs = []
    for side in (-1, 1):
        stem = lathe([(0.0, 0.0), (0.16, 0.0), (0.16, 0.35), (0.0, 0.35)], 12).rotate("z", -90 * side)
        knob = sphere(0.3, 8, 12).translate(0, 0.42, 0).rotate("z", -90 * side)
        knobs.append(merge(stem, knob).translate(1.85 * side, 0.85, 0))
    return {"Rubber": rubber, "Block": block, "Band": merge(band, *knobs)}


def big_stamp():
    rubber = rounded_box(16.0, 1.6, 12.0, 0.4).translate(0, 0.8, 0)
    block = rounded_box(17.0, 5.0, 13.0, 1.0).translate(0, 1.6 + 2.5, 0)
    neck = lathe(
        [(0.0, 6.4), (3.4, 6.4), (3.3, 7.2), (2.3, 8.2), (1.8, 10.0), (1.9, 12.0), (2.6, 13.4), (2.4, 14.2), (0.0, 14.2)],
        28,
    )
    knob = lathe(
        [(0.0, 13.6)]
        + [(math.sin(math.pi * i / 14) * 4.2, 17.6 - math.cos(math.pi * i / 14) * 4.0) for i in range(1, 14)]
        + [(0.0, 21.6)],
        28,
    )
    return {"Rubber": rubber, "Block": block, "Handle": neck, "Knob": knob}


def ink_pad():
    tray = rounded_box(30.0, 2.4, 20.0, 0.6).translate(0, 1.2, 0)
    felt = rounded_box(27.0, 0.6, 17.0, 0.25).translate(0, 2.35, 0)
    lid = rounded_box(30.0, 1.0, 20.0, 0.5).translate(0, 0.5, -10.0).rotate("x", 100).translate(0, 2.2, 10.0)
    hinge = lathe([(0.0, -14.5), (0.5, -14.5), (0.5, 14.5), (0.0, 14.5)], 12).rotate("z", 90).translate(0, 2.3, 10.2)
    # Separate pieces, so each one's collision hull hugs it (one hull round tray + lid would fill the corner).
    return {"Tin": tray, "Lid": lid, "Hinge": hinge, "Felt": felt}


def pencil():
    def lying(mesh):
        return mesh.rotate("y", 30).rotate("z", -90)  # a flat side of the hexagon down

    paint = lathe([(0.0, 0.0), (2.6, 0.0), (2.6, 70.0), (0.0, 70.0)], 6)
    paint.smooth = False
    wood = lathe([(0.0, 70.0), (2.5, 70.0), (0.75, 79.0), (0.0, 79.0)], 6)
    wood.smooth = False
    lead = lathe([(0.0, 78.9), (0.78, 78.9), (0.12, 81.6), (0.0, 81.7)], 12)
    ferrule = lathe(
        [(0.0, -5.0), (2.75, -5.0), (2.85, -4.4), (2.75, -3.8), (2.85, -1.6), (2.75, -1.0), (2.75, 0.2), (0.0, 0.2)],
        24,
    )
    eraser = lathe(
        [(0.0, -11.0), (1.9, -11.0), (2.4, -10.6), (2.6, -9.8), (2.6, -4.9), (0.0, -4.9)],
        24,
    )
    pieces = {"Body": paint, "Wood": wood, "Lead": lead, "Ferrule": ferrule, "Eraser": eraser}
    for name, mesh in pieces.items():
        pieces[name] = lying(mesh).translate(-35.0, 2.6, 0)
    return pieces


def clip():
    def arc(cx, cz, r, a0, a1, steps=10):
        return [(cx + math.cos(math.radians(a0 + (a1 - a0) * i / steps)) * r, cz + math.sin(math.radians(a0 + (a1 - a0) * i / steps)) * r) for i in range(steps + 1)]

    path = [(4.0, 0.0)]
    path += arc(-12.0, 1.75, 1.75, -90, -270)
    path += arc(13.0, 0.25, 3.25, 90, -90)
    path += arc(-15.0, 1.0, 4.0, -90, -270)
    path += [(8.0, 5.0)]
    points = [(x, 0.5, z - 1.0) for x, z in path]
    return {"Wire": taper(points, 0.5, 0.5, 10)}


PROPS = {
    "StampOutRider": rider,
    "StampOutBigStamp": big_stamp,
    "StampOutInkPad": ink_pad,
    "StampOutPencil": pencil,
    "StampOutClip": clip,
}
COLORS = {
    "Rubber": (226, 40, 52),
    "Block": (196, 150, 98),
    "Band": (226, 40, 52),
    "Handle": (176, 120, 70),
    "Knob": (226, 40, 52),
    "Tin": (200, 50, 60),
    "Lid": (200, 50, 60),
    "Hinge": (200, 200, 210),
    "Felt": (70, 40, 120),
    "Body": (250, 196, 40),
    "Wood": (232, 196, 150),
    "Lead": (50, 50, 56),
    "Ferrule": (200, 200, 210),
    "Eraser": (246, 140, 160),
    "Wire": (200, 205, 215),
}
