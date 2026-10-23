"""The five Hollow Night pets and five hats (owner: "2 is good 3 is good": the title and these, as
designed). Pets are about 3 studs, face -Y, origin in the middle; hats are built round a head whose
middle is the group's origin (head 1.25 studs)."""

import math
import random

from mathutils import Vector

from hollow_night import (AMBER, CRIMSON, EMBER, GOLDLEAF, LEAF_COLORS, PUMPKIN, WISP, bark, brass, iron, lantern, leaf,
                      leaf_mat, leaf_mesh, pumpkin, wisp)
from blender_lib import (catmull, col, glow, group, mix, obj, pbr, point_light, rbox, sparks, torus, tube, vmat, vsolid)


def under_halo(g, z, r, color=PUMPKIN):
    torus((0, 0, z), r, 0.025, glow(color, 6), parent=g)
    torus((0, 0, z), r * 0.7, 0.015, glow(color, 3), parent=g)


def eye_pair(g, x, y, z, r, iris=AMBER, pupil=True):
    dark = pbr("fall_eye", "#140c1c", rough=0.08, coat=1.0)
    for sx in (-1, 1):
        obj("sphere", (sx * x, y, z), (r, r * 0.6, r), m=glow(iris, 9), parent=g)
        if pupil:
            obj("sphere", (sx * x, y - r * 0.45, z), (r * 0.5, r * 0.25, r * 0.62), m=dark, parent=g)
        obj("sphere", (sx * x - r * 0.25, y - r * 0.6, z + r * 0.35), r * 0.18, m=glow("#ffffff", 10), parent=g)


def harvest_owl(loc, yaw=0.0, s=1.0, parent=None):
    g = group(loc, (0, 0, yaw), s, parent)
    feather = pbr("owl_feather", "#a0622c", rough=0.7, sheen=0.8)
    chest = pbr("owl_chest", "#e9c48a", rough=0.75, sheen=0.8)
    face = pbr("owl_face", "#f5e2bd", rough=0.7, sheen=0.5)
    obj("sphere", (0, 0, 0.05), (0.66, 0.58, 0.8), m=feather, parent=g)
    obj("sphere", (0, -0.3, -0.05), (0.5, 0.36, 0.6), m=chest, parent=g)
    for k in range(9):
        r, z = (0.14, -0.35 + (k // 3) * 0.25)
        x = ((k % 3) - 1) * 0.2
        obj("cone", (x, -0.62 + abs(x) * 0.15, z), (0.06, 0.03, 0.05), (math.pi, 0, 0), feather, g)
    for sx in (-1, 1):
        obj("sphere", (sx * 0.22, -0.42, 0.55), (0.3, 0.16, 0.3), m=face, parent=g)
        obj("cone", (sx * 0.4, -0.15, 1.02), (0.13, 0.08, 0.28), (0, sx * 0.45, 0), leaf_mat(CRIMSON), g)
    eye_pair(g, 0.22, -0.58, 0.56, 0.15)
    obj("cone", (0, -0.62, 0.38), (0.07, 0.06, 0.13), (math.pi - 0.3, 0, 0), pbr("beak", "#e0a030", 0.4), g)
    # Leaf-feather wings, half open (pieces WingL... / WingR..., so the game can flap them).
    for sx in (-1, 1):
        wing = group((0, 0, 0), (0, 0, 0), 1, g)
        wing["piece_prefix"] = "WingL" if sx < 0 else "WingR"
        for k in range(6):
            t = k / 5
            c = mix(col(CRIMSON), col(GOLDLEAF), t)
            hexc = "#%02x%02x%02x" % tuple(int(255 * (v ** (1 / 2.2))) for v in c)
            ang = math.radians(-30 + k * 22)
            pos = (sx * (0.62 + 0.35 * math.cos(ang)), 0.1 + 0.1 * t, 0.15 + 0.45 * math.sin(ang))
            obj(leaf_mesh("long"), pos, 0.95 - 0.08 * k, (math.pi / 2, sx * (ang + 0.4), sx * 0.25), leaf_mat(hexc), wing)
    for k in range(5):
        a = math.radians(-40 + k * 20)
        obj(leaf_mesh("long"), (math.sin(a) * 0.25, 0.55, -0.55), 0.8,
            (math.radians(60), a, 0), leaf_mat(LEAF_COLORS[k % len(LEAF_COLORS)]), g)
    for sx in (-1, 1):
        obj("sphere", (sx * 0.18, -0.25, -0.8), (0.1, 0.12, 0.07), m=pbr("talon", "#e0a030", 0.4), parent=g)
    tube([Vector((0, -0.3, -0.85)), Vector((0, -0.35, -1.05))], lambda t: 0.02, lambda t: (1, 1, 1, 0), iron(), seg=6,
         parent=g)
    lantern((0, -0.35, -1.38), 0.42, parent=g, power=60)
    under_halo(g, -1.85, 0.8)
    sparks((0, 0, 0.3), 1.7, 14, [AMBER, "#fff1c2", GOLDLEAF], (0.02, 0.05), seed=3, z=(-1.2, 1.6), parent=g)
    return g


def ember_stag(loc, yaw=0.0, s=1.0, parent=None):
    g = group(loc, (0, 0, yaw), s, parent)
    fur = pbr("stag_fur", "#b8703c", rough=0.6, sheen=0.9)
    light = pbr("stag_light", "#f4dcc0", rough=0.6, sheen=0.8)
    obj("sphere", (0, 0.15, 0), (0.42, 0.82, 0.45), m=fur, parent=g)
    obj("sphere", (0, -0.4, -0.12), (0.34, 0.38, 0.36), m=light, parent=g)
    rng = random.Random(5)
    for _ in range(9):
        obj("sphere", (rng.uniform(-0.25, 0.25), rng.uniform(-0.1, 0.8), 0.4), (0.07, 0.07, 0.03), m=light, parent=g)
    neck = catmull([(0, -0.45, 0.2), (0, -0.62, 0.6), (0, -0.66, 0.92)], 8)
    tube(neck, lambda t: 0.22 - 0.06 * t, lambda t: (1, 1, 1, 0), fur, parent=g)
    obj("sphere", (0, -0.75, 1.05), (0.28, 0.36, 0.27), m=fur, parent=g)
    obj("sphere", (0, -1.04, 0.98), (0.17, 0.22, 0.15), m=light, parent=g)
    obj("sphere", (0, -1.24, 1.0), (0.07, 0.05, 0.05), m=pbr("nose", "#1a1d33", 0.3), parent=g)
    dark = pbr("fall_eye", "#140c1c", rough=0.08, coat=1.0)
    for sx in (-1, 1):
        obj("sphere", (sx * 0.17, -0.92, 1.12), (0.08, 0.06, 0.1), m=dark, parent=g)
        obj("sphere", (sx * 0.15, -0.97, 1.16), 0.025, m=glow("#ffffff", 10), parent=g)
        obj("sphere", (sx * 0.3, -0.62, 1.22), (0.1, 0.05, 0.2), (0, sx * 0.9, 0), fur, g)
        # Antlers: glowing ember wood, leaves and fireflies.
        main = catmull([(sx * 0.12, -0.7, 1.28), (sx * 0.3, -0.62, 1.65), (sx * 0.55, -0.5, 1.95), (sx * 0.65, -0.35,
                                                                                                    2.35)], 8)
        ant = vsolid("antler", 8.0, 0.6, 0.0)
        ember = lambda t: (*mix(col("#5a3420"), col(AMBER), min(1, t * 1.3)), max(0, t - 0.25) * 1.3)
        tube(main, lambda t: 0.07 * (1 - t) + 0.02, ember, ant, seg=10, parent=g)
        for j, (a0, l) in enumerate([(0.35, 0.45), (0.6, 0.38), (0.85, 0.3)]):
            base = main[int(a0 * (len(main) - 1))]
            tip = base + Vector((sx * 0.35 * l / 0.45, 0.1 - 0.2 * j, 0.32))
            tube([base, (base + tip) / 2 + Vector((0, 0, 0.06)), tip], lambda t: 0.04 * (1 - t) + 0.012,
                 lambda t: ember(0.4 + 0.6 * t), ant, seg=8, parent=g)
            leaf(tip + Vector((0, 0, 0.05)), 0.32, (1.2, 0.3 * sx, j), LEAF_COLORS[(j + (sx > 0) * 2) % 6], g)
        leaf(main[-1] + Vector((0, 0, 0.1)), 0.38, (1.0, -0.3 * sx, 0.5), GOLDLEAF, g)
    for k in range(12):
        a = k * 2 * math.pi / 12
        obj("ico", (math.cos(a) * 0.9, -0.5 + math.sin(a) * 0.4, 2.0 + 0.35 * math.sin(k * 2.3)), 0.035,
            m=glow("#ffe27a", 25), parent=g)
    for sx in (-1, 1):
        for y in (-0.35, 0.6):
            leg = [Vector((sx * 0.22, y, -0.25)), Vector((sx * 0.24, y - 0.05, -0.65)), Vector((sx * 0.22, y + 0.05, -1.0))]
            tube(leg, lambda t: 0.09 - 0.03 * t, lambda t: (1, 1, 1, 0), fur, seg=10, parent=g)
            obj("sphere", (sx * 0.22, y + 0.05, -1.05), (0.08, 0.09, 0.07), m=glow(EMBER, 8), parent=g)
    obj("sphere", (0, 0.98, 0.25), (0.12, 0.1, 0.16), m=light, parent=g)
    under_halo(g, -1.25, 0.85)
    sparks((0, 0, 0), 1.6, 18, [EMBER, AMBER, "#fff1c2"], (0.02, 0.05), seed=8, z=(-1.2, 1.2), parent=g)
    return g


def gourdian(loc, yaw=0.0, s=1.0, parent=None):
    g = group(loc, (0, 0, yaw), s, parent)
    pumpkin((0, -0.05, 1.05), 0.62, "#ff7a1a", face=True, parent=g)
    vine = catmull([(0.05, -0.05, 1.62), (0.3, 0.05, 1.8), (0.45, -0.1, 1.95), (0.35, -0.2, 2.1), (0.2, -0.05, 2.15)],
                   6)
    tube(vine, lambda t: 0.035, lambda t: (1, 1, 1, 0), pbr("vine", "#4f6b24", 0.7), seg=8, parent=g)
    leaf((0.42, -0.12, 1.8), 0.45, (1.1, 0.2, 0.6), "#6f9e3a", g)
    body = pbr("gourd_body", "#cf9b3a", rough=0.5, coat=0.3)
    stripe = pbr("gourd_stripe", "#4f6b24", rough=0.6)
    obj("sphere", (0, 0, 0.05), (0.7, 0.6, 0.62), m=body, parent=g)
    for k in range(6):
        a = k * math.pi / 3
        obj("sphere", (math.cos(a) * 0.5, math.sin(a) * 0.43, 0.05), (0.08, 0.08, 0.5), (0, 0, a), stripe, g)
    obj("sphere", (0, 0.02, -0.62), (0.48, 0.42, 0.32), m=pbr("gourd_low", "#e8d8a8", 0.5), parent=g)
    for sx in (-1, 1):
        arm = catmull([(sx * 0.6, 0, 0.4), (sx * 0.95, -0.05, 0.55), (sx * 1.15, -0.15, 0.15), (sx * 1.2, -0.2, -0.2)], 6)
        tube(arm, lambda t: 0.09, lambda t: (1, 1, 1, 0), pbr("vine", "#4f6b24", 0.7), seg=10, parent=g)
        fist = group((0, 0, 0), (0, 0, 0), 1, g)
        fist["piece_prefix"] = "FistL" if sx < 0 else "FistR"
        pumpkin((sx * 1.25, -0.25, -0.42), 0.32, "#ff9a3a", rot=(0.3, 0, sx), parent=fist)
        for k in range(3):
            leaf((sx * (0.55 + 0.1 * k), 0.35, 0.7 - 0.25 * k), 0.75, (1.9, sx * 0.6, sx * 0.3),
                 [CRIMSON, "#e8521e", AMBER][k], g)
    for k in range(10):
        a = k * 2 * math.pi / 10
        obj("sphere", (math.cos(a) * 1.5, math.sin(a) * 1.5, 0.3 + 0.3 * math.sin(a * 3)), (0.06, 0.04, 0.03),
            (0, 0, a), pbr("seed", "#f6e7b0", 0.4, emit="#ffd27a", es=2), g)
    under_halo(g, -1.05, 1.0)
    sparks((0, 0, 0.5), 1.8, 14, [AMBER, EMBER, "#fff1c2"], (0.02, 0.05), seed=13, z=(-1.0, 1.8), parent=g)
    return g


def toadstool_tot(loc, yaw=0.0, s=1.0, parent=None):
    g = group(loc, (0, 0, yaw), s, parent)
    cap = pbr("tot_cap", "#e0482e", rough=0.45, coat=0.6)
    obj("half", (0, 0, 0.55), (1.05, 1.05, 0.7), m=cap, parent=g)
    obj("cyl", (0, 0, 0.53), (0.95, 0.95, 0.05), m=pbr("tot_gills", "#f2dcb4", 0.8), parent=g)
    rng = random.Random(4)
    for k in range(11):
        u = rng.uniform(0, 2 * math.pi)
        v = rng.uniform(0.25, 1.25)
        n = Vector((math.cos(u) * math.sin(v), math.sin(u) * math.sin(v), math.cos(v)))
        p = Vector((n.x * 1.05, n.y * 1.05, 0.55 + n.z * 0.7))
        obj("sphere", p, (0.14, 0.14, 0.04), m=pbr("tot_spot", "#fff2cc", 0.5, emit="#ffe9b0", es=2.5), parent=g,
            rot=n.to_track_quat("Z", "Y").to_euler())
    skin = pbr("tot_skin", "#f4e8d0", rough=0.6, sss=0.3)
    obj("sphere", (0, 0, 0.0), (0.55, 0.5, 0.6), m=skin, parent=g)
    dark = pbr("fall_eye", "#140c1c", rough=0.08, coat=1.0)
    for sx in (-1, 1):
        obj("sphere", (sx * 0.19, -0.46, 0.12), (0.09, 0.06, 0.12), m=dark, parent=g)
        obj("sphere", (sx * 0.17, -0.51, 0.17), 0.03, m=glow("#ffffff", 10), parent=g)
        obj("sphere", (sx * 0.32, -0.42, -0.02), (0.08, 0.02, 0.05), m=pbr("blush", "#ff8fc8", 0.5, emit="#ff8fc8",
                                                                            es=0.6), parent=g)
        obj("sphere", (sx * 0.5, -0.2, -0.15), (0.13, 0.13, 0.16), m=skin, parent=g)
    obj("sphere", (0, -0.5, -0.06), (0.07, 0.02, 0.035), m=dark, parent=g)
    acorn = group((0.05, -0.62, -0.25), (0.3, 0.2, 0), 1, g)
    obj("sphere", (0, 0, 0), (0.15, 0.15, 0.2), m=pbr("acorn", "#a8632e", 0.4, coat=0.5), parent=acorn)
    obj("half", (0, 0, 0.06), (0.17, 0.17, 0.1), m=pbr("acorn_cap", "#6a4426", 0.9), parent=acorn)
    for sx in (-1, 1):
        obj("sphere", (sx * 0.25, -0.1, -0.6), (0.14, 0.18, 0.09), m=skin, parent=g)
    obj(leaf_mesh("maple"), (0, 0.05, -0.75), 2.6, (0, 0, math.radians(180)), leaf_mat("#ff8a2a"), g)
    sparks((0, 0, 0.5), 1.5, 26, ["#fff2cc", "#ffe27a", "#ffd0a0"], (0.02, 0.04), seed=17, z=(-0.4, 1.6), parent=g)
    under_halo(g, -0.95, 0.9)
    return g


def lantern_wisp(loc, yaw=0.0, s=1.0, parent=None):
    g = group(loc, (0, 0, yaw), s, parent)
    ir, br = iron(), brass()
    torus((0, 0, 0.9), 0.62, 0.06, ir, parent=g)
    torus((0, 0, -0.75), 0.62, 0.06, ir, parent=g)
    obj("cone6", (0, 0, 1.18), (0.66, 0.66, 0.3), (0, 0, math.pi / 6), ir, g)
    obj("cyl", (0, 0, -0.85), (0.6, 0.6, 0.08), m=ir, parent=g)
    torus((0, 0, 1.62), 0.18, 0.04, br, (math.pi / 2, 0, 0), g)
    for k in range(6):
        a = k * math.pi / 3 + math.pi / 6
        obj("cube", (math.cos(a) * 0.6, math.sin(a) * 0.6, 0.08), (0.035, 0.035, 0.84), (0, 0, a), ir, g)
    obj("cyl", (0, 0, 0.08), (0.56, 0.56, 0.8), m=pbr("wisp_glass", "#bfffe0", 0.05, trans=1.0, ior=1.2), parent=g)
    flame = vmat("wisp_flame", 6.0)
    c1, c2 = col(WISP), col("#d8fff0")
    fl = group((0, 0, 0), (0, 0, 0), 1, g)
    fl["piece_prefix"] = "Flame"  # (the game flickers it)
    pts = [Vector((0, 0, -0.55 + k * 0.07)) for k in range(14)]
    tube(pts, lambda t: 0.36 * math.sin(math.pi * min(1, t * 1.05)) ** 0.7 + 0.01,
         lambda t: (*mix(c2, c1, t), 0.95 - 0.5 * t), flame, seg=20, parent=fl)
    dark = pbr("fall_eye", "#140c1c", rough=0.08, coat=1.0)
    for sx in (-1, 1):
        obj("sphere", (sx * 0.12, -0.3, -0.05), (0.06, 0.03, 0.09), m=dark, parent=g)
    obj("sphere", (0, -0.31, -0.2), (0.05, 0.02, 0.025), m=dark, parent=g)
    point_light((0, 0, 0), WISP, 120, 0.3, g)
    tail = catmull([(0, 0, 1.3), (0.1, 0.4, 1.9), (-0.3, 1.0, 2.2), (0.2, 1.7, 2.6), (-0.1, 2.4, 2.8)], 10)
    tube(tail, lambda t: 0.25 * (1 - t) + 0.03, lambda t: (*mix(c1, col("#7ad8ff"), t), 0.75 * (1 - t) ** 0.8),
         vmat("wisp_tail", 5.0), seg=14, parent=g)
    for k in range(7):
        a = k * 2 * math.pi / 7
        obj("ico", (math.cos(a) * 1.15, math.sin(a) * 1.15, 0.1 + 0.4 * math.sin(a * 2)), 0.06, m=glow(AMBER, 14),
            parent=g)
    under_halo(g, -1.2, 0.9, WISP)
    sparks((0, 0, 0.3), 1.6, 16, [WISP, "#d8fff0", AMBER], (0.02, 0.05), seed=19, z=(-1.0, 2.2), parent=g)
    return g


PETS = [
    ("HARVEST OWL", harvest_owl),
    ("EMBER STAG", ember_stag),
    ("GOURDIAN", gourdian),
    ("TOADSTOOL TOT", toadstool_tot),
    ("LANTERN WISP", lantern_wisp),
]


# ---------------------------------------------------------------------------------------------
# Hats, built around a head whose center is the group's origin (head 1.25 studs).

def leaf_crown(g):
    rng = random.Random(6)
    torus((0, 0, 0.62), 0.66, 0.07, bark(), parent=g)
    for k in range(22):
        a = k * 2 * math.pi / 22
        obj(leaf_mesh("maple" if k % 2 else "oval"), (math.cos(a) * 0.66, math.sin(a) * 0.66, 0.72), 0.55 if k % 2 else 0.45,
            (math.radians(70), 0, a + math.pi / 2), leaf_mat(LEAF_COLORS[k % 6]), g)
    for k in range(5):
        a = k * 2 * math.pi / 5 + 0.3
        acorn = group((math.cos(a) * 0.7, math.sin(a) * 0.7, 0.6), (0, 0.3, a), 1, g)
        obj("sphere", (0, 0, 0), (0.09, 0.09, 0.12), m=pbr("acorn", "#a8632e", 0.4, coat=0.5), parent=acorn)
        obj("half", (0, 0, 0.04), (0.1, 0.1, 0.06), m=pbr("acorn_cap", "#6a4426", 0.9), parent=acorn)
    for k in range(4):
        a = k * math.pi / 2 + 0.8
        obj("sphere", (math.cos(a) * 0.72, math.sin(a) * 0.72, 0.8), 0.06, m=pbr("berry", "#c8202a", 0.2, coat=1.0),
            parent=g)


def scarecrow_hat(g):
    straw = pbr("straw", "#d9b25a", rough=0.95, sheen=0.6)
    obj("cyl", (0, 0, 0.66), (1.25, 1.25, 0.05), (0.05, 0.08, 0), straw, g)
    obj("cone", (0, 0, 1.15), (0.6, 0.6, 0.5), m=straw, parent=g)
    obj("cyl", (0, 0, 0.82), (0.62, 0.62, 0.1), m=pbr("hatband", "#7a2a1a", 0.7), parent=g)
    obj(rbox((0.35, 0.05, 0.3), 0.04), (0.2, -0.55, 1.05), 1, (0.25, 0, 0.3), pbr("patch", "#6a4fb8", 0.8), g)
    rng = random.Random(2)
    for k in range(22):
        a = rng.uniform(0, 2 * math.pi)
        obj("cyl", (math.cos(a) * 1.28, math.sin(a) * 1.28, 0.62), (0.015, 0.015, 0.12),
            (rng.uniform(1.2, 1.9), 0, a + math.pi / 2), straw, g)
    crow = group((0.8, 0.4, 0.74), (0, 0, 2.4), 1.35, g)
    black = pbr("crow", "#1a1622", rough=0.35, coat=0.5)
    obj("sphere", (0, 0, 0.18), (0.16, 0.24, 0.16), m=black, parent=crow)
    obj("sphere", (0, -0.22, 0.32), 0.11, m=black, parent=crow)
    obj("cone", (0, -0.36, 0.31), (0.035, 0.03, 0.07), (math.pi / 2, 0, 0), pbr("beak", "#e0a030", 0.4), crow)
    obj("sphere", (0.06, -0.3, 0.36), 0.02, m=glow(AMBER, 12), parent=crow)
    obj("sphere", (-0.06, -0.3, 0.36), 0.02, m=glow(AMBER, 12), parent=crow)
    obj("cube", (0, 0.25, 0.14), (0.06, 0.14, 0.02), (0.4, 0, 0), black, crow)


def antler_circlet(g):
    torus((0, 0, 0.55), 0.66, 0.05, brass(), parent=g)
    ant = vsolid("antler", 8.0, 0.6, 0.0)
    ember = lambda t: (*mix(col("#5a3420"), col(AMBER), min(1, t * 1.3)), max(0, t - 0.2) * 1.3)
    for sx in (-1, 1):
        main = catmull([(sx * 0.45, 0.0, 0.6), (sx * 0.75, -0.05, 1.0), (sx * 0.95, 0.05, 1.5), (sx * 0.9, 0.15, 1.9)], 8)
        tube(main, lambda t: 0.08 * (1 - t) + 0.02, ember, ant, seg=10, parent=g)
        for j, a0 in enumerate([0.3, 0.55, 0.8]):
            base = main[int(a0 * (len(main) - 1))]
            tip = base + Vector((sx * 0.3, -0.15 + 0.1 * j, 0.32))
            tube([base, tip], lambda t: 0.045 * (1 - t) + 0.012, lambda t: ember(0.4 + 0.6 * t), ant, seg=8, parent=g)
            leaf(tip, 0.3, (1.2, 0.3 * sx, j), LEAF_COLORS[(j * 2 + (sx > 0)) % 6], g)
    for k in range(8):
        a = k * 2 * math.pi / 8
        obj("ico", (math.cos(a) * 1.1, math.sin(a) * 0.6, 1.4 + 0.3 * math.sin(k * 2.1)), 0.035, m=glow("#ffe27a", 25),
            parent=g)


def acorn_helm(g):
    cap = pbr("acorn_cap", "#6a4426", 0.9)
    obj("half", (0, 0, 0.3), (0.82, 0.8, 0.62), m=cap, parent=g)
    for k in range(5):
        torus((0, 0, 0.36 + k * 0.1), 0.82 * math.cos(math.asin(min(0.95, k * 0.18))), 0.035,
              pbr("acorn_ridge", "#55361e", 0.9), parent=g)
    obj("cyl", (0.04, 0, 1.02), (0.09, 0.09, 0.22), (0.25, 0, 0), cap, g)
    obj("sphere", (0.22, -0.66, 0.42), 0.07, m=glow(AMBER, 10), parent=g)
    leaf((-0.4, -0.3, 0.92), 0.5, (0.6, -0.4, 0.4), "#ff8a2a", g)


def crescent_moon(g):
    pts = [Vector((math.cos(a) * 0.55, 0, 1.45 + math.sin(a) * 0.55))
           for a in [math.radians(110 + k * (220 / 40)) for k in range(41)]]
    tube(pts, lambda t: 0.04 + 0.16 * math.sin(math.pi * t), lambda t: (*col("#ffcf7a"), 1.0), vsolid("moonhat", 4.0),
         seg=16, parent=g)
    for k in range(5):
        a = k * 2 * math.pi / 5
        obj("ico", (math.cos(a) * 0.95, math.sin(a) * 0.5, 1.6 + 0.25 * math.sin(a * 2)), 0.05, m=glow("#ffffff", 20),
            parent=g)
    for k in range(2):
        bat = group((0.85 - 1.7 * k, 0.2, 2.0 - 0.2 * k), (0, 0, 0.4 - 0.8 * k), 0.5, g)
        black = pbr("crow", "#1a1622", rough=0.35, coat=0.5)
        obj("sphere", (0, 0, 0), (0.12, 0.1, 0.12), m=black, parent=bat)
        for sx in (-1, 1):
            obj("cone6", (sx * 0.3, 0, 0.02), (0.12, 0.02, 0.28), (0, sx * 1.4, 0), black, bat)


HATS = [
    ("LEAF CROWN", leaf_crown),
    ("SCARECROW HAT", scarecrow_hat),
    ("ANTLER CIRCLET", antler_circlet),
    ("ACORN HELM", acorn_helm),
    ("CRESCENT MOON", crescent_moon),
]
