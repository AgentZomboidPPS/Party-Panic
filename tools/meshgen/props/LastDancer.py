"""Meshes for Last Dancer (see tools/meshgen/props/README.md). Units are studs, +Y up, base on y = 0,
-Z is the front. Generate with: python3 tools/meshgen/generate_meshes.py --only LastDancerMirrorBall,LastDancerSpeaker

  LastDancerMirrorBall  the faceted disco ball hanging over the stage (its lowest point on y = 0)
  LastDancerSpeaker     a stack of three speaker cabinets, cones facing the stage (-Z)
"""

import math

import numpy as np

from generate_meshes import Mesh, icosphere, lathe, merge, rounded_box, torus


def mirror_ball():
    """A disco ball: 320 flat facets (a twice-divided icosahedron, flat shaded so every facet catches the
    light on its own), with the cap and hanging ring it turns from."""
    ball = icosphere(4.5, 2)
    ball.smooth = False
    ball.translate(0, 4.5, 0)
    cap = lathe([(0.0, 8.7), (1.1, 8.8), (1.3, 9.3), (0.9, 9.6), (0.0, 9.6)], 20)
    ring = torus(0.55, 0.14, 20, 8).rotate("x", 90).translate(0, 10.0, 0)
    return {"Ball": ball, "Cap": merge(cap, ring)}


def speaker():
    """Three speaker cabinets, a little narrower at each level up, each with a cone in a rim and a
    tweeter above it. The cones face -Z."""
    bodies, cones, rims, tweeters = [], [], [], []
    for level in range(3):
        width = 5.0 - 0.6 * level
        y = 2.2 + 4.4 * level
        bodies.append(rounded_box(width, 4.3, 4.4, 0.35, 5).translate(0, y, 0))
        # the woofer: a shallow dish in a raised rim (built along +Y, then turned to face -Z)
        dish = lathe([(0.0, -0.35), (0.55, -0.4), (1.2, -0.05), (1.55, 0.08), (1.55, 0.0), (0.0, -0.3)], 20)
        dish.rotate("x", -90).translate(0, y - 0.35, -2.2)
        cones.append(dish)
        rim = torus(1.68, 0.16, 20, 6).rotate("x", 90).translate(0, y - 0.35, -2.2)
        rims.append(rim)
        tweeter = lathe([(0.0, -0.2), (0.4, -0.18), (0.45, 0.0), (0.0, 0.0)], 16)
        tweeter.rotate("x", -90).translate(0, y + 1.5, -2.2)
        tweeters.append(tweeter)
    return {"Body": merge(*bodies), "Cone": merge(*cones, *tweeters), "Rim": merge(*rims)}


PROPS = {"LastDancerMirrorBall": mirror_ball, "LastDancerSpeaker": speaker}
COLORS = {
    "Ball": (235, 240, 255),
    "Cap": (180, 180, 195),
    "Body": (28, 26, 42),
    "Cone": (70, 70, 92),
    "Rim": (150, 150, 170),
}
