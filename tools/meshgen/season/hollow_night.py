"""Hollow Night, the first crate season (owner: "Hollow night comes first I want you to actually work
on adding it to the game right now ... This will be players first season. I want it to look
insane."): its crate, key, props, crate pile, altars and board, as Blender models. They make the
concept renders and, through export.py, the game's meshes. Blender coordinates, things face -Y."""

import math
import random

import bmesh
import bpy
from mathutils import Vector, noise

import blender_lib as lib
from blender_lib import (TIER, area_light, beam, blob, catmull, col, coin, glow, group, mix, obj, pbr, point_light, rb,
                 rbox, ring_burst, screen, sparks, torus, tube, vmat, vsolid, yaw_to, HERE)

PLUM, EMBER, PUMPKIN, AMBER = "#1c0f2e", "#ff6a1f", "#ff8a2a", "#ffb530"
GOLDLEAF, CRIMSON, WISP, MOON = "#ffd04a", "#c8322a", "#7dffb2", "#ffcf7a"
LEAF_COLORS = ["#c8322a", "#e8521e", "#ff8a2a", "#ffb530", "#ffd04a", "#a8361c"]
FALL_TIER = dict(TIER, title=EMBER)


def wood():
    return pbr("hollow_wood", "#8a5530", rough=0.6, coat=0.25)


def iron():
    return pbr("hollow_iron", "#2f2b3a", rough=0.4, metal=0.9)


def brass():
    return pbr("hollow_brass", "#d4913a", rough=0.28, metal=1.0)


def bark():
    return pbr("bark", "#4a2f1e", rough=0.9)


def leaf_mat(c):
    return pbr(f"leaf{c}", c, rough=0.55, sss=0.25, emit=c, es=0.15)


# ---------------------------------------------------------------------------------------------
# Leaves, pumpkins, lanterns

_LEAF = {}


def leaf_mesh(kind="maple"):
    if kind in _LEAF:
        return _LEAF[kind]
    verts, faces = [(0, 0, 0.02)], []
    n = 64 if lib.EXPORT else 160
    for i in range(n):
        t = 2 * math.pi * i / n
        if kind == "maple":
            # Three broad pointed lobes (top and two sides), two small low ones, a notch for the stem.
            r = 0.5
            for center, amp, width in ((90, 0.5, 0.32), (30, 0.42, 0.3), (150, 0.42, 0.3), (-25, 0.18, 0.3),
                                       (205, 0.18, 0.3)):
                d = math.atan2(math.sin(t - math.radians(center)), math.cos(t - math.radians(center)))
                r += amp * math.exp(-(d / width) ** 2)
            r += 0.06 * max(0, math.cos(20 * t)) ** 3 * min(1, r)
            if abs(math.atan2(math.sin(t + math.pi / 2), math.cos(t + math.pi / 2))) < 0.3:
                r *= 0.75
        elif kind == "oval":  # a broad leaf with a pointed tip
            r = 1.0 / math.sqrt((math.cos(t) / 0.55) ** 2 + (math.sin(t)) ** 2) * (1 + 0.3 * max(0, math.sin(t)) ** 10)
        else:  # a long oval leaf (feathers, wings)
            r = 1.0 / math.sqrt((math.cos(t) / 0.38) ** 2 + (math.sin(t)) ** 2)
        x, y = math.cos(t) * r * 0.5, math.sin(t) * r * 0.5
        verts.append((x, y, 0.12 * (x * x + y * y)))
    for i in range(n):
        faces.append((0, 1 + i, 1 + (i + 1) % n))
    me = bpy.data.meshes.new(f"leaf_{kind}")
    me.from_pydata(verts, [], faces)
    me.shade_smooth()
    me.materials.append(pbr("default", "#888888"))
    _LEAF[kind] = me
    return me


def leaf(loc, size, rot, color=None, parent=None, kind=None, rng=random):
    kind = kind or ("maple" if rng.random() < 0.6 else "oval")
    return obj(leaf_mesh(kind), loc, size, rot, leaf_mat(color or rng.choice(LEAF_COLORS)), parent)


def scatter_leaves(center, rx, ry, z0, z1, n, seed=1, size=(0.35, 0.6), parent=None, flat=False):
    rng = random.Random(seed)
    for _ in range(n):
        p = (center[0] + rng.uniform(-rx, rx), center[1] + rng.uniform(-ry, ry), rng.uniform(z0, z1))
        rot = (rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), rng.uniform(0, 6.3)) if flat else \
            (rng.uniform(0, 6.3), rng.uniform(0, 6.3), rng.uniform(0, 6.3))
        leaf(p, rng.uniform(*size), rot, parent=parent, rng=rng)


_PUMPKIN = {}


def pumpkin_mesh(ribs=8, flat=0.78):
    key = (ribs, flat)
    if key in _PUMPKIN:
        return _PUMPKIN[key]
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=64, v_segments=32, radius=1)
    for v in bm.verts:
        a = math.atan2(v.co.y, v.co.x)
        k = 1 - 0.09 * (1 - math.cos(ribs * a)) / 2 * (1 - abs(v.co.z) ** 2)
        v.co = Vector((v.co.x * k, v.co.y * k, v.co.z * flat * (1 - 0.18 * max(0, v.co.z) ** 6)))
    me = bpy.data.meshes.new("pumpkin")
    bm.to_mesh(me)
    bm.free()
    me.shade_smooth()
    me.materials.append(pbr("default", "#888888"))
    _PUMPKIN[key] = me
    return me


def pumpkin(loc, r, color="#ff7a1a", rot=(0, 0, 0), face=False, parent=None, ribs=8):
    g = group(loc, rot, r, parent)
    obj(pumpkin_mesh(ribs), (0, 0, 0), 1, m=pbr(f"pumpkin{color}", color, rough=0.45, coat=0.3), parent=g)
    stem = [Vector((0, 0, 0.62)), Vector((0.03, 0, 0.82)), Vector((0.12, 0.02, 0.95))]
    tube(stem, lambda t: 0.1 - 0.04 * t, lambda t: (1, 1, 1, 0), pbr("stem", "#5d6b2a", 0.8), seg=8, parent=g)
    if face:
        lit = glow("#ffb530", 14)
        for sx in (-1, 1):
            obj("cone6", (sx * 0.32, -0.9, 0.18), (0.14, 0.05, 0.13), (math.pi / 2, 0, 0), lit, g)
        for k in range(5):
            x = -0.36 + k * 0.18
            obj("cube", (x, -0.93 + abs(x) * 0.15, -0.2 + (0.05 if k % 2 else -0.04)), (0.07, 0.03, 0.07),
                (0, math.pi / 4, 0), lit, g)
        point_light((0, -1.3, 0), AMBER, 60, 0.3, g)
    return g


def lantern(loc, s=1.0, color=AMBER, parent=None, power=120):
    g = group(loc, (0, 0, 0), s, parent)
    obj(rbox((0.7, 0.7, 0.12), 0.04), (0, 0, 0.5), 1, m=iron(), parent=g)
    obj(rbox((0.6, 0.6, 0.1), 0.03), (0, 0, -0.45), 1, m=iron(), parent=g)
    obj("cone6", (0, 0, 0.66), (0.42, 0.42, 0.16), m=iron(), parent=g)
    torus((0, 0, 0.9), 0.14, 0.03, iron(), (math.pi / 2, 0, 0), g)
    for sx in (-1, 1):
        for sy in (-1, 1):
            obj("cube", (sx * 0.3, sy * 0.3, 0.02), (0.03, 0.03, 0.46), m=iron(), parent=g)
    obj("cube", (0, 0, 0.02), (0.28, 0.28, 0.44), m=pbr(f"lglass{color}", color, 0.1, trans=0.6, emit=color, es=3),
        parent=g)
    obj("sphere", (0, 0, -0.05), (0.12, 0.12, 0.2), m=glow("#fff1c2", 25), parent=g)
    point_light((0, 0, 0), color, power, 0.2, g)
    return g


def lantern_post(loc, h=6.0, side=1, parent=None):
    g = group(loc, (0, 0, 0), 1, parent)
    obj("cyl", (0, 0, h / 2), (0.14, 0.14, h / 2), m=iron(), parent=g)
    arm = [Vector((0, 0, h - 0.2)), Vector((side * 0.5, 0, h + 0.35)), Vector((side * 1.1, 0, h + 0.3))]
    tube(arm, lambda t: 0.08, lambda t: (1, 1, 1, 0), iron(), seg=8, parent=g)
    lantern((side * 1.1, 0, h - 0.75), 0.9, parent=g)
    return g


def hay(loc, rot=(0, 0, 0), parent=None):
    g = group(loc, rot, 1, parent)
    obj(rbox((2.6, 1.5, 1.3), 0.2), (0, 0, 0.65), 1, m=pbr("straw", "#d9b25a", rough=0.95, sheen=0.6), parent=g)
    for x in (-0.6, 0.6):
        obj("cube", (x, 0, 0.65), (0.05, 0.78, 0.68), m=pbr("twine", "#8a5a2a", 0.9), parent=g)
    return g


def wisp(loc, s=1.0, seed=0, parent=None, color=WISP):
    rng = random.Random(seed)
    g = group(loc, (0, 0, rng.uniform(0, 6.3)), s, parent)
    obj("sphere", (0, 0, 0), 0.32, m=glow(color, 10), parent=g)
    obj("sphere", (0, 0, 0), 0.6, m=pbr(f"wispshell{color}", color, 0.2, alpha=0.25, emit=color, es=1.5), parent=g)
    pts = catmull([(0, 0, 0), (0.2, 0.6, 0.25), (-0.2, 1.3, 0.6), (0.15, 2.0, 1.1)], 8)
    c = col(color)
    tube(pts, lambda t: 0.3 * (1 - t) + 0.02, lambda t: (*c, 0.7 * (1 - t)), vmat(f"wisptail{color}", 5), seg=12,
         parent=g)
    return g


# ---------------------------------------------------------------------------------------------
# The Hollow crate and the Lantern key

def emblem_leaf(loc, rot, size, m, parent):
    g = group(loc, rot, size, parent)
    obj(leaf_mesh("maple"), (0, 0, 0), 1.0, (math.pi / 2, 0, 0), m, g)
    obj("cube", (0, -0.01, -0.34), (0.025, 0.02, 0.2), m=m, parent=g)
    return g


def crate(loc, scale=1.0, rot=(0, 0, 0), lid=0.0, lid_at=None, inner=None, parent=None, seam=PUMPKIN, top=True):
    W, H, LH = 3.0, 2.2, 0.8
    g = group(loc, rot, scale, parent)
    wd, ir, br = wood(), iron(), brass()
    dark = pbr("hollow_wood_dark", "#5a3420", rough=0.7)
    obj(rbox((W, W, H), 0.1), (0, 0, H / 2), 1, m=wd, parent=g)
    for k in range(4):
        a = k * math.pi / 2
        face = group((math.sin(a) * (W / 2 + 0.01), -math.cos(a) * (W / 2 + 0.01), 0), (0, 0, a), 1, g)
        for z in (0.55, 1.15, 1.75):
            obj("cube", (0, 0.0, z), (W / 2 - 0.25, 0.02, 0.012), m=dark, parent=face)
        obj("cyl", (0, -0.02, H / 2 - 0.02), (0.72, 0.72, 0.05), (math.pi / 2, 0, 0), dark, face)
        torus((0, -0.06, H / 2 - 0.02), 0.74, 0.06, br, (math.pi / 2, 0, 0), face)
        emblem_leaf((0, -0.08, H / 2 + 0.02), (0, 0, 0), 1.15, glow(seam, 7), face)
    for sx in (-1, 1):
        for sy in (-1, 1):
            obj(rbox((0.46, 0.46, H + 0.02), 0.06), (sx * (W / 2 - 0.12), sy * (W / 2 - 0.12), H / 2), 1, m=ir,
                parent=g)
            for z in (0.5, 1.7):
                obj("ico", (sx * (W / 2 + 0.06), sy * (W / 2 - 0.12), z), 0.07, m=br, parent=g)
                obj("ico", (sx * (W / 2 - 0.12), sy * (W / 2 + 0.06), z), 0.07, m=br, parent=g)
            obj(rbox((0.6, 0.6, 0.5), 0.12), (sx * (W / 2 - 0.12), sy * (W / 2 - 0.12), 0.24), 1, m=br, parent=g)
    obj(rbox((W + 0.1, W + 0.1, 0.26), 0.06), (0, 0, 0.13), 1, m=ir, parent=g)
    obj(rbox((W + 0.06, W + 0.06, 0.12), 0.03), (0, 0, H - 0.04), 1, m=glow(seam, 9), parent=g)
    if inner:
        obj("cube", (0, 0, H - 0.08), (W / 2 - 0.2, W / 2 - 0.2, 0.02), m=glow(inner, 30), parent=g)
        point_light((0, 0, H + 0.6), inner, 800, 0.8, g)
    if lid_at:
        lg = group(lid_at[0], lid_at[1], 1, g)
        body = group((0, W / 2, 0), (0, 0, 0), 1, lg)
    else:
        lg = group((0, W / 2, H), (-lid, 0, 0), 1, g)
        body = lg
    lg["piece_prefix"] = "Lid"  # (export: the lid's pieces are named Lid..., so the game can open it)
    obj(rbox((W + 0.14, W + 0.14, LH), 0.16), (0, -W / 2, LH / 2), 1, m=wd, parent=body)
    obj(rbox((W + 0.24, W + 0.24, 0.2), 0.06), (0, -W / 2, 0.1), 1, m=ir, parent=body)
    obj(rbox((0.5, 0.18, 0.6), 0.05), (0, -W - 0.1, 0.05), 1, m=br, parent=body)
    obj("cyl", (0, -W - 0.2, 0.0), (0.08, 0.08, 0.03), (math.pi / 2, 0, 0), glow(seam, 10), body)
    if top:
        rng = random.Random(int(loc[0] * 13 + loc[1] * 7 + loc[2] * 3))
        for _ in range(9):
            leaf((rng.uniform(-1.2, 1.2), -W / 2 + rng.uniform(-1.2, 1.2), LH + 0.03), rng.uniform(0.45, 0.8),
                 (rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15), rng.uniform(0, 6.3)), parent=body, rng=rng)
        if rng.random() < 0.5:
            for k in range(3):
                h = 0.22 + 0.1 * k
                x, y = 0.9 + k * 0.18, -W / 2 + 0.9 - k * 0.22
                obj("cyl", (x, y, LH + h / 2), (0.05, 0.05, h / 2), m=pbr("mush_stem", "#f2e6cc", 0.6), parent=body)
                obj("half", (x, y, LH + h), (0.17 - k * 0.02, 0.17 - k * 0.02, 0.1), m=pbr("mush_cap", "#e0482e", 0.5,
                                                                                         emit="#ff6a3a", es=0.4),
                    parent=body)
    return g


def key(loc, rot=(0, 0, 0), scale=1.0, parent=None):
    """The Lantern Key: an iron key whose bow is a little lantern cage with an ember inside."""
    g = group(loc, rot, scale, parent)
    torus((0, 0, 0), 0.55, 0.11, iron(), (math.pi / 2, 0, 0), g)
    torus((0, 0, 0), 0.55, 0.11, iron(), (math.pi / 2, 0, math.pi / 2), g)
    obj("sphere", (0, 0, 0), 0.3, m=glow(AMBER, 14), parent=g)
    obj("cone6", (0, 0, 0.7), (0.18, 0.18, 0.14), m=brass(), parent=g)
    obj("cyl", (1.25, 0, 0), (0.1, 0.1, 0.72), (0, math.pi / 2, 0), iron(), g)
    obj("cube", (0.6, 0, 0), (0.08, 0.16, 0.16), m=brass(), parent=g)
    for x, h in [(1.55, 0.36), (1.85, 0.26)]:
        obj(rbox((0.16, 0.14, h), 0.03), (x, 0, -h / 2), 1, m=brass(), parent=g)
    leaf((0.1, -0.05, -0.75), 0.45, (math.pi / 2, 0.3, 0), "#ff8a2a", g)
    return g


# ---------------------------------------------------------------------------------------------
# The lobby: autumn colors, the moon, the pile, altars and board

def autumn_lobby(data):
    """Recolors the lobby's trees, bushes and grass for fall (in place, before building)."""
    rng = random.Random(10)
    autumn = [(214, 72, 38), (238, 120, 40), (246, 168, 48), (200, 96, 40), (232, 190, 70)]
    for p in data["parts"]:
        if p["n"] == "Leaves":
            p["col"] = list(rng.choice(autumn))
        elif p["n"] == "Plaza":
            p["col"] = [168, 160, 74]
    t = data["terrain"]["colors"]
    t["Grass"] = [0.62, 0.6, 0.27]
    t["LeafyGrass"] = [0.7, 0.52, 0.22]


def harvest_sky(scene):
    world = scene.world
    ramp = [n for n in world.node_tree.nodes if n.type == "VALTORGB"][0]
    els = ramp.color_ramp.elements
    els[0].color = (*col("#ff9a4a"), 1)
    els[1].position = 0.5
    els[1].color = (*col("#1a0f36"), 1)
    mid = els.new(0.15)
    mid.color = (*col("#8a3a6a"), 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    sun = [o for o in scene.objects if o.type == "LIGHT" and o.data.type == "SUN"][0]
    sun.data.energy = 1.6
    sun.data.color = (1.0, 0.62, 0.38)
    d = rb(-0.85, 0.22, 0.45).normalized()
    sun.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    area_light(rb(0, 120, 60), rb(0, 0, 0), "#9a8aff", 50000, 120)


def moon(pos, r):
    obj("sphere", pos, r, m=pbr("moon", "#ffcf7a", 0.8, emit="#ffb256", es=1.3))
    rng = random.Random(2)
    for _ in range(9):
        d = Vector((rng.uniform(-1, 1), -1, rng.uniform(-1, 1))).normalized()
        obj("sphere", Vector(pos) + d * r * 0.93, r * rng.uniform(0.08, 0.2),
            m=pbr("crater", "#f3a650", 0.9, emit="#e8923e", es=1.0))


def crate_pile(spin=0.4, game=False):
    """The pile on its tree stump. game: only the still parts (the game turns the big crate on top,
    flies the keys round it and draws the wisps and the leaf swirl itself)."""
    st = group((0, 0, 0))
    obj("cyl", (0, 0, 0.75), (12.5, 12.5, 0.75), m=bark(), parent=st)
    obj("cyl", (0, 0, 1.52), (12.2, 12.2, 0.03), m=pbr("stump_top", "#c08a55", 0.8), parent=st)
    for k in range(1, 9):
        torus((0, 0, 1.56), 12.2 * k / 9, 0.05, pbr("ring", "#8a5a34", 0.8), parent=st)
    torus((0, 0, 1.6), 12.4, 0.12, glow(PUMPKIN, 6), parent=st)
    rng = random.Random(7)
    for k in range(9):
        a = k * 2 * math.pi / 9 + rng.uniform(-0.2, 0.2)
        pts = [Vector((math.cos(a) * r, math.sin(a) * r, z)) for r, z in [(11.5, 1.0), (13.5, 0.6), (15.5, 0.25),
                                                                             (17.0, 0.05)]]
        tube(catmull(pts, 6), lambda t: 1.0 * (1 - t) + 0.15, lambda t: (1, 1, 1, 0), bark(), seg=12, parent=st)
    blob((0, 0, 1.4), (10.0, 10.0, 2.2), pbr("leafpile", "#d2541f", 0.7, sss=0.2), seed=3, amp=0.09, freq=1.4,
         res=96)
    for _ in range(260):
        a, r = rng.uniform(0, 6.3), 10.2 * math.sqrt(rng.random())
        z = 1.4 + 2.2 * math.sqrt(max(0, 1 - (r / 10.0) ** 2)) + 0.05
        leaf((math.cos(a) * r, math.sin(a) * r, z), rng.uniform(0.5, 0.9),
             (rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4), rng.uniform(0, 6.3)), rng=rng)
    rings = [(11, 7.6, 2.55, 1.0), (8, 5.0, 4.6, 1.0), (5, 2.6, 6.9, 0.95)]
    for n, r, z, s in rings:
        for k in range(n):
            a = k * 2 * math.pi / n + rng.uniform(-0.1, 0.1) + r
            tilt = (rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12) + 0.08, a + rng.uniform(-0.5, 0.5))
            crate((math.cos(a) * r, math.sin(a) * r, z + rng.uniform(-0.25, 0.1)), s, tilt)
    if game:
        for k, (a, r) in enumerate([(0.3, 10.8), (1.2, 11.0), (2.4, 10.6), (3.4, 10.9), (4.4, 10.7), (5.4, 11.0)]):
            p = (math.cos(a) * r, math.sin(a) * r, 1.5)
            pumpkin((p[0], p[1], p[2] + 0.8), rng.uniform(0.8, 1.3), rot=(0, 0, rng.uniform(0, 6)), ribs=8)
            pumpkin((p[0] + 1.4, p[1] + 0.6, p[2] + 0.5), 0.55, "#f2e4c4", rot=(0, 0, rng.uniform(0, 6)), ribs=10)
        return
    crate((0, 0, 9.5), 2.0, (0, 0, spin))
    for k in range(3):
        a = k * 2 * math.pi / 3 + 0.5
        key((math.cos(a) * 4.8, math.sin(a) * 4.8, 13.0), (math.radians(20), math.radians(10), a + math.pi / 2), 0.9)
    for k in range(70):
        t = k / 70
        a = t * 4 * math.pi
        r = 5.5 + 1.2 * math.sin(t * 9)
        leaf((math.cos(a) * r, math.sin(a) * r, 11 + t * 6), 0.55,
             (rng.uniform(0, 6), rng.uniform(0, 6), rng.uniform(0, 6)), rng=rng)
    point_light((0, 0, 17), AMBER, 8000, 3)
    for k, (a, r) in enumerate([(0.3, 10.8), (1.2, 11.0), (2.4, 10.6), (3.4, 10.9), (4.4, 10.7), (5.4, 11.0)]):
        p = (math.cos(a) * r, math.sin(a) * r, 1.5)
        pumpkin((p[0], p[1], p[2] + 0.8), rng.uniform(0.8, 1.3), rot=(0, 0, rng.uniform(0, 6)), face=(k % 2 == 0),
                ribs=8)
        pumpkin((p[0] + 1.4, p[1] + 0.6, p[2] + 0.5), 0.55, "#f2e4c4", rot=(0, 0, rng.uniform(0, 6)), ribs=10)
    for k in range(8):
        a = k * 2 * math.pi / 8 + 0.2
        wisp((math.cos(a) * 9, math.sin(a) * 9, 12 + 3 * math.sin(k * 1.7)), 1.0, seed=k)


ALTARS = [50, 90, 130]


def altar_pos(deg, r=18.5):
    a = math.radians(deg)
    return rb(math.cos(a) * r, 0, math.sin(a) * r)


def altar_base(parent=None):
    """An opening altar without its crate (the game's own crate sits on it): two stone steps, the
    glowing ring round the top (its own piece, Ring, so the game can colour it by tier), two lantern
    posts behind and two pumpkins in front."""
    g = group((0, 0, 0), (0, 0, 0), 1, parent)
    stone = pbr("hollow_stone", "#4a4458", rough=0.7)
    obj("hex", (0, 0, 0.3), (3.0, 3.0, 0.3), (0, 0, math.pi / 6), pbr("hollow_stone2", "#3a3446", 0.75), g)
    obj("hex", (0, 0, 0.95), (2.4, 2.4, 0.4), (0, 0, math.pi / 6), stone, g)
    torus((0, 0, 1.38), 2.2, 0.07, glow("#ff8a2a", 10), parent=g)["piece"] = "Ring"
    for sx in (-1, 1):
        lantern_post((sx * 2.4, 1.6, 0), 5.0, -sx, g)
        pumpkin((sx * 2.6, -1.4, 0.75), 0.7, rot=(0, 0, sx), parent=g)
    scatter_leaves((0, 0), 3.2, 3.2, 0.62, 0.65, 18, seed=3, parent=g, flat=True)
    return g


def altar(pos, state="idle", tier="pet", item=None, item_scale=1.5):
    yaw = yaw_to((0, 0, 0), pos) + math.pi
    g = group(pos, (0, 0, yaw))
    stone = pbr("hollow_stone", "#4a4458", rough=0.7)
    obj("hex", (0, 0, 0.3), (3.0, 3.0, 0.3), (0, 0, math.pi / 6), pbr("hollow_stone2", "#3a3446", 0.75), g)
    obj("hex", (0, 0, 0.95), (2.4, 2.4, 0.4), (0, 0, math.pi / 6), stone, g)
    tc = FALL_TIER[tier]
    torus((0, 0, 1.38), 2.2, 0.07, glow(PUMPKIN if state == "idle" else tc, 10), parent=g)
    for sx in (-1, 1):
        lantern_post((sx * 2.4, 1.6, 0), 5.0, -sx, g)
        pumpkin((sx * 2.6, -1.4, 0.75), 0.7, rot=(0, 0, sx), face=(sx > 0), parent=g)
    scatter_leaves((0, 0), 3.2, 3.2, 0.62, 0.65, 18, seed=int(pos.x * 10), parent=g, flat=True)
    if state == "idle":
        crate((0, 0, 1.35), 1.0, (0, 0, 0), parent=g)
        key((-0.95, 0, 5.4), (0, math.radians(-20), 0), 0.75, g)
        return g
    if state == "burst":
        crate((0, 0, 1.35), 1.0, (0, 0, 0), lid_at=((0, 0.6, 6.5), (math.radians(-55), math.radians(18), 0.3)),
              inner="#fff1c2", parent=g)
        beam((0, 0, 3.4), 42, 1.2, 2.6, "#ffd9a0", 1.6, parent=g)
        ring_burst((0, 0, 1.5), 4.5, "#ffd9a0", 10, g, 0.5)
        ring_burst((0, 0, 1.5), 7.0, "#ffd9a0", 4, g, 0.3)
        scatter_leaves((0, 0), 3.5, 3.5, 3, 7.5, 40, seed=5, parent=g)
        sparks((0, 0, 5), 4.5, 40, ["#ffffff", AMBER, EMBER], (0.05, 0.12), seed=9, z=(0, 6), parent=g)
        point_light((0, 0, 5), "#ffd9a0", 6000, 1.5, g)
        return g
    crate((0, 0, 1.35), 1.0, (0, 0, 0), lid=math.radians(105), inner=tc, parent=g)
    beam((0, 0, 3.4), 42, 1.3, 2.8, tc, 1.3, parent=g)
    point_light((0, 0, 6), tc, 5000, 1.5, g)
    if state == "reel":
        coin((0, 2.0, 6.6), (math.radians(80), 0, 0), 1.5, g)
        coin((0.7, 2.1, 6.2), (math.radians(70), 0.3, 0), 1.2, g)
        key((-0.9, 1.8, 10.6), (0.2, 0.3, 0.4), 0.9, g)
        from hollow_night_pets import leaf_crown
        hg = group((0, 2.0, 8.4), (0, 0, 0.5), 1.3, g)
        leaf_crown(hg)
        for k in range(14):
            rng = random.Random(40 + k)
            a = rng.uniform(0, 2 * math.pi)
            obj("cube", (math.cos(a) * 1.6, math.sin(a) * 1.6, 7.5), (0.04, 0.04, rng.uniform(1.5, 3.5)), m=glow(
                rng.choice(["#ffffff", "#ffd24a", "#b26bff", "#4aa8ff", "#ff4fd8"]), 12), parent=g)
        return g
    ring_burst((0, 0, 1.5), 5.0, tc, 10, g, 0.45)
    ring_burst((0, 0, 8.0), 3.4, tc, 8, g, 0.25)
    sparks((0, 0, 7), 4.0, 50, [tc, "#ffffff", AMBER, "#ffd24a"], (0.05, 0.12), seed=12, z=(-3, 5), parent=g)
    if item:
        item((0, 2.2, 8.4), yaw=math.pi, s=item_scale, parent=g)
    return g


def board_frame(parent=None):
    """The Top Unboxers board's frame (the game puts the screen in it): wood, an iron cap, stump
    legs, a lantern each side, pumpkins and leaves on top. Faces -Y; 11 wide, 16.5 tall."""
    g = group((0, 0, 0), (0, 0, 0), 1, parent)
    obj(rbox((11.0, 0.9, 14.0), 0.35), (0, 0, 9.0), 1, m=wood(), parent=g)
    obj(rbox((11.6, 1.1, 0.5), 0.15), (0, 0, 16.1), 1, m=iron(), parent=g)
    for sx in (-1, 1):
        obj("cyl", (sx * 4.6, 0, 1.2), (0.55, 0.55, 1.2), m=bark(), parent=g)
        lantern((sx * 6.1, 0, 15.0), 1.0, parent=g)
        pumpkin((sx * 4.4, -1.2, 0.7), 0.75, parent=g)
    scatter_leaves((0, 0), 5.6, 0.5, 16.4, 16.5, 22, seed=4, parent=g, flat=True)
    return g


def leaf_heap(parent=None, r=3.0, seed=2):
    """A heap of fallen leaves to jump into (about 6 studs across, 1.3 tall)."""
    g = group((0, 0, 0), (0, 0, 0), 1, parent)
    blob((0, 0, 0), (r, r, 1.2), pbr("leafpile", "#d2541f", 0.7, sss=0.2), seed=seed, amp=0.12, freq=1.5, parent=g,
         res=40)
    rng = random.Random(seed)
    for _ in range(int(26 * r)):
        a, rr = rng.uniform(0, 6.3), r * math.sqrt(rng.random())
        z = 1.2 * math.sqrt(max(0, 1 - (rr / r) ** 2)) + 0.03
        leaf((math.cos(a) * rr, math.sin(a) * rr, z), rng.uniform(0.5, 0.85),
             (rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5), rng.uniform(0, 6.3)), parent=g, rng=rng)
    return g


def paper_lantern(parent=None, color="#ff8a2a"):
    """A round paper lantern about 1 stud tall (the Lantern Ring aura)."""
    g = group((0, 0, 0), (0, 0, 0), 1, parent)
    obj("sphere", (0, 0, 0), (0.42, 0.42, 0.5), m=pbr(f"paper{color}", color, 0.6, emit=color, es=2.5), parent=g)
    for z in (-0.3, 0.0, 0.3):
        torus((0, 0, z), 0.42 * math.sqrt(1 - (z / 0.5) ** 2) + 0.01, 0.015, pbr("rib", "#5a3420", 0.7), parent=g)
    obj("cyl", (0, 0, 0.52), (0.18, 0.18, 0.05), m=pbr("rib", "#5a3420", 0.7), parent=g)
    obj("cyl", (0, 0, -0.52), (0.18, 0.18, 0.05), m=pbr("rib", "#5a3420", 0.7), parent=g)
    return g


def crow(parent=None):
    """A crow about 1 stud long, wings spread (Wing pieces, so the game can flap them)."""
    g = group((0, 0, 0), (0, 0, 0), 1, parent)
    black = pbr("crow", "#1a1622", rough=0.35, coat=0.5)
    obj("sphere", (0, 0, 0), (0.18, 0.32, 0.16), m=black, parent=g)
    obj("sphere", (0, -0.3, 0.08), 0.12, m=black, parent=g)
    obj("cone", (0, -0.45, 0.07), (0.035, 0.03, 0.08), (math.pi / 2, 0, 0), pbr("beak", "#e0a030", 0.4), g)
    for sx in (-1, 1):
        w = group((sx * 0.12, 0, 0.06), (0, 0, 0), 1, g)
        w["piece_prefix"] = "WingL" if sx < 0 else "WingR"
        obj("cone6", (sx * 0.32, 0, 0.0), (0.14, 0.02, 0.36), (0, sx * 1.35, 0), black, w)
    obj("cone6", (0, 0.4, 0), (0.12, 0.02, 0.25), (math.pi / 2 + 0.2, 0, 0), black, g)
    for sx in (-1, 1):
        obj("sphere", (sx * 0.07, -0.38, 0.13), 0.025, m=glow("#ffb530", 10), parent=g)
    return g


def leaderboard(pos):
    g = group(pos, (0, 0, yaw_to(pos, (0, 0, 0)) + math.pi))
    obj(rbox((11.0, 0.9, 14.0), 0.35), (0, 0, 9.0), 1, m=wood(), parent=g)
    obj(rbox((11.6, 1.1, 0.5), 0.15), (0, 0, 16.1), 1, m=iron(), parent=g)
    for sx in (-1, 1):
        obj("cyl", (sx * 4.6, 0, 1.2), (0.55, 0.55, 1.2), m=bark(), parent=g)
        lantern((sx * 6.1, 0, 15.0), 1.0, parent=g)
        pumpkin((sx * 4.4, -1.2, 0.7), 0.75, face=True, parent=g)
    for side in (-1, 1):
        rot = (math.pi / 2, 0, 0) if side < 0 else (math.pi / 2, 0, math.pi)
        screen(HERE / "tex" / "board_fall.png", (0, side * 0.47, 9.0), 10.0, 13.0, rot, 1.4, parent=g)
    scatter_leaves((0, 0), 5.6, 0.5, 16.4, 16.5, 22, seed=4, parent=g, flat=True)
    return g


def falling_leaves(n, radius, z0, z1, seed=1, center=(0, 0), ymin=-1e9):
    rng = random.Random(seed)
    for _ in range(n):
        a = rng.uniform(0, 2 * math.pi)
        r = radius * math.sqrt(rng.random())
        if center[1] + math.sin(a) * r < ymin:
            continue
        leaf((center[0] + math.cos(a) * r, center[1] + math.sin(a) * r, rng.uniform(z0, z1)), rng.uniform(0.35, 0.6),
             (rng.uniform(0, 6.3), rng.uniform(0, 6.3), rng.uniform(0, 6.3)), rng=rng)
