"""Meshes for Last Dancer (see tools/meshgen/props/README.md). Units are studs, +Y up, base on y = 0,
-Z is the front. Generate with: python3 tools/meshgen/generate_meshes.py --only LastDancerTrophy"""

from generate_meshes import lathe, merge, rounded_box


def trophy():
    cup = lathe([(0.0, 2.0), (0.6, 2.0), (1.5, 3.2), (1.6, 5.0), (1.75, 6.0), (1.5, 6.0), (1.35, 5.0), (0.0, 3.4)], 32)
    stem = lathe([(0.0, 1.0), (0.5, 1.0), (0.3, 1.6), (0.6, 2.05), (0.0, 2.05)], 24)
    base = rounded_box(3.0, 1.0, 3.0, 0.3).translate(0, 0.5, 0)
    return {"Cup": merge(cup, stem), "Base": base}


PROPS = {"LastDancerTrophy": trophy}
COLORS = {"Cup": (255, 205, 60), "Base": (90, 70, 160)}
