"""The five Hollow Night pets and five hats (owner: "2 is good 3 is good": the title and these, as
designed). Pets are about 3 studs, face -Y, origin in the middle; hats are built round a head whose
middle is the group's origin (head 1.25 studs)."""

import math
import random

import bmesh
import bpy

from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

from hollow_night import (AMBER, EMBER, LEAF_COLORS, PUMPKIN, WISP, bark, brass, iron, leaf, leaf_mat, leaf_mesh,
                         pumpkin_mesh)
from blender_lib import (catmull, col, glow, group, link, mix, obj, pbr, point_light, rbox, sparks, torus, torus_mesh,
                         tube, vmat, vsolid)


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


def _orient(normal, tip):
    """The rotation that lays a leaf (its face +Z, its tip +Y) facing `normal`, pointing toward `tip`."""
    z = Vector(normal).normalized()
    y = (Vector(tip) - z * Vector(tip).dot(z)).normalized()
    x = y.cross(z)
    return Matrix((x, y, z)).transposed().to_euler()


# ---------------------------------------------------------------------------------------------
# Leaf feathers: closed, double-sided and flat-shaded (Roblox draws only a face's front; a closed
# shape needs no back added, and the export never simplifies flat pieces, so every feather keeps
# its outline). A feather's length runs along +Y from -0.5 (base) to 0.5 (tip), its face is +Z.
#   blade          a serrated leaf with a ridge down its middle
#   flameL/flameR  a blade whose tip sweeps to -X / +X, like a tongue of fire
#   scale          a round body feather
_FEATHER = {}


def _outline(shape):
    """(base, right side, tip, left side, ridge line): the ridge's z is its height profile, 0 to 1."""
    m = 5 if shape == "scale" else 7
    bend = {"flameL": -0.34, "flameR": 0.34}.get(shape, 0.0)

    def width(s):
        if shape == "scale":
            return 0.36 * math.sin(math.pi * (0.08 + 0.84 * s)) ** 0.5 * (1 - 0.3 * s ** 4)
        return 0.19 * math.sin(math.pi * s ** 0.85) ** 0.8

    right, left, ridge = [], [], []
    for i in range(m):
        s = (i + 1) / (m + 1)
        tooth = shape != "scale" and i % 2 == 1  # teeth and notches by turns, the teeth toward the tip
        w = width(s) * (1.22 if tooth else 0.94) if shape != "scale" else width(s)
        st = min(0.97, s + (0.04 if tooth else 0.0))
        right.append(Vector((w + bend * st * st, st - 0.5, 0)))
        left.append(Vector((-w + bend * st * st, st - 0.5, 0)))
        ridge.append(Vector((bend * s * s, s - 0.5, math.sin(math.pi * s) ** 0.5)))
    return Vector((0, -0.5, 0)), right, Vector((bend, 0.5, 0)), left, ridge


def _closed_leaf(base, right, tip, left, ridge, height, back):
    """A leaf from an outline: its face ridged (`height`), its back a shallow point (`back` deep)."""
    m = len(right)
    mid = [Vector((v.x, v.y, height * v.z)) for v in ridge]
    centre = (base + tip) / 2
    verts = [base, tip] + right + left + mid + [Vector((centre.x, centre.y, -back))]
    B, T, C = 0, 1, 2 + 3 * m
    R, L, M = (lambda i: 2 + i), (lambda i: 2 + m + i), (lambda i: 2 + 2 * m + i)
    faces = [(B, R(0), M(0)), (B, M(0), L(0)), (M(m - 1), R(m - 1), T), (M(m - 1), T, L(m - 1))]
    for j in range(1, m):
        faces += [(M(j - 1), R(j - 1), R(j)), (M(j - 1), R(j), M(j)), (M(j - 1), L(j), L(j - 1)),
                  (M(j - 1), M(j), L(j))]
    loop = [B] + [R(i) for i in range(m)] + [T] + [L(i) for i in reversed(range(m))]
    faces += [(C, loop[(k + 1) % len(loop)], loop[k]) for k in range(len(loop))]
    return verts, faces


def _maple_loop(n=26):
    """A maple leaf's outline, counter-clockwise from its stem notch: five pointed lobes (the leaf
    spans about -0.5 to 0.5 each way, its tip at +Y)."""
    pts = []
    for i in range(n):
        t = -math.pi / 2 + 2 * math.pi * i / n
        r = 0.5
        for centre, amp, width in ((90, 0.5, 0.26), (30, 0.42, 0.24), (150, 0.42, 0.24), (-25, 0.2, 0.24),
                                   (205, 0.2, 0.24)):
            d = math.atan2(math.sin(t - math.radians(centre)), math.cos(t - math.radians(centre)))
            r += amp * math.exp(-(d / width) ** 2)
        if abs(math.atan2(math.sin(t + math.pi / 2), math.cos(t + math.pi / 2))) < 0.3:
            r *= 0.6
        pts.append(Vector((math.cos(t) * r * 0.5, math.sin(t) * r * 0.5 + 0.02, 0)))
    return pts


def _fan(loop, centre, height, back):
    """A closed leaf from an outline that's star-shaped round `centre`: its face rising to `height`
    there, its back sinking to `back` (flat-shaded, the facets read as veins)."""
    n = len(loop)
    verts = loop + [centre + Vector((0, 0, height)), centre - Vector((0, 0, back))]
    F, B = n, n + 1
    faces = [(F, k, (k + 1) % n) for k in range(n)] + [(B, (k + 1) % n, k) for k in range(n)]
    return verts, faces


def _ring(outer, inner):
    """The band between two outlines (the glowing rim): its face, its back and the wall inside."""
    n = len(outer)
    sunk = [v - Vector((0, 0, 0.004)) for v in inner]
    O, I, S = (lambda k: k % n), (lambda k: n + k % n), (lambda k: 2 * n + k % n)
    faces = []
    for k in range(n):
        faces += [(O(k), O(k + 1), I(k + 1), I(k)), (O(k), S(k), S(k + 1), O(k + 1)), (I(k), I(k + 1), S(k + 1), S(k))]
    return outer + inner + sunk, faces


def feather_mesh(shape="blade", part="leaf"):
    """part: "leaf" (one colour), or a glowing feather's two halves, which meet without overlapping:
    "rim" (the band round its edge, widest at the tip) and "core" (the rest, ridged). shape "maple"
    is a maple leaf (its "base" is the leaf's back edge, half its length behind its middle)."""
    key = (shape, part)
    if key in _FEATHER:
        return _FEATHER[key]
    if shape == "maple":
        loop = _maple_loop()
        centre = Vector((0, -0.02, 0))
        inner = [centre + (v - centre) * 0.76 for v in loop]
        if part == "leaf":
            verts, faces = _fan(loop, centre, 0.05, 0.012)
        elif part == "core":
            verts, faces = _fan(inner, centre, 0.035, 0.01)
        else:
            verts, faces = _ring(loop, inner)
        me = bpy.data.meshes.new(f"feather_{shape}_{part}")
        me.from_pydata([tuple(v) for v in verts], [], faces)
        me.materials.append(pbr("default", "#888888"))
        _FEATHER[key] = me
        return me
    base, right, tip, left, ridge = _outline(shape)
    if part == "leaf":
        verts, faces = _closed_leaf(base, right, tip, left, ridge, 0.03, 0.012)
    else:
        # The core is the outline shrunk toward a point near the base, so the rim is a hair wide at
        # the base and a fifth of the feather at the tip.
        anchor = Vector((0, -0.42, 0))
        shrink = lambda v: anchor + (v - anchor) * 0.8  # noqa: E731
        inner = [shrink(v) for v in [base] + right + [tip] + list(reversed(left))]
        if part == "core":
            m = len(right)
            verts, faces = _closed_leaf(inner[0], inner[1:m + 1], inner[m + 1], list(reversed(inner[m + 2:])),
                                        [shrink(Vector((v.x, v.y, 0))) + Vector((0, 0, v.z)) for v in ridge],
                                        0.012, 0.01)
        else:
            verts, faces = _ring([base] + right + [tip] + list(reversed(left)), inner)
    me = bpy.data.meshes.new(f"feather_{shape}_{part}")
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.materials.append(pbr("default", "#888888"))
    _FEATHER[key] = me
    return me


def feather(shape, base, length, normal, tip, m, parent, lift=0.0, width=1.0, part="leaf"):
    """A feather from `base`, `length` long toward `tip`, its face toward `normal` (lifted off by
    `lift` along it)."""
    n = Vector(normal).normalized()
    d = Vector(tip)
    d = (d - n * d.dot(n)).normalized()
    at = Vector(base) + d * length * 0.5 + n * lift
    return obj(feather_mesh(shape, part), at, (length * width, length, length), _orient(n, d), m, parent)


def fire_feather(shape, base, length, normal, tip, rim, core, parent, lift=0.0, width=1.0):
    """A feather whose edge glows (the owner's picture of the owl): a Neon rim round a solid core."""
    feather(shape, base, length, normal, tip, rim, parent, lift, width, "rim")
    feather(shape, base, length, normal, tip, core, parent, lift, width, "core")


def fire(c):
    return pbr(f"fire{c}", c, rough=0.5, emit=c, es=3.0)


def plume(c):
    return pbr(f"plume{c}", c, rough=0.65, sheen=0.7)


def hinge(at, parent):
    """An invisible marker where a moving group turns (the game reads its <Prefix>Hinge piece)."""
    o = obj("cube", at, 0.02, m=pbr("hinge", "#000000", alpha=0.0), parent=parent)
    o["piece"] = "Hinge"
    return o


def _along(pts, u):
    f = max(0.0, min(1.0, u)) * (len(pts) - 1)
    i = min(int(f), len(pts) - 2)
    return pts[i].lerp(pts[i + 1], f - i)


def on_ellipsoid(c, r, theta, z):
    """A point on an upright ellipsoid (centre c, radii r) at angle theta round it (0 = straight
    back, pi = the front) and height z, with its outward normal."""
    w = (z - c[2]) / r[2]
    ring = math.sqrt(max(0.0, 1 - w * w))
    x, y = math.sin(theta) * r[0] * ring, math.cos(theta) * r[1] * ring
    n = Vector((x / r[0] ** 2, y / r[1] ** 2, (z - c[2]) / r[2] ** 2)).normalized()
    return Vector((c[0] + x, c[1] + y, z)), n


def gothic_lantern(c, s, parent):
    """A six-sided iron lantern: a hanging ring, a pointed roof, glowing glass with a maple leaf
    on its front and back panes, and a pointed base."""
    ir = iron()
    c = Vector(c)
    P = lambda x, y, z: c + Vector((x, y, z)) * s  # noqa: E731
    torus(P(0, 0, 0.4), 0.055 * s, 0.015 * s, ir, (math.pi / 2, 0, 0), parent)
    obj("sphere", P(0, 0, 0.335), 0.035 * s, m=ir, parent=parent)
    obj("cone6", P(0, 0, 0.245), (0.2 * s, 0.2 * s, 0.1 * s), m=ir, parent=parent)
    obj("hex", P(0, 0, 0.145), (0.215 * s, 0.215 * s, 0.018 * s), m=ir, parent=parent)
    obj("hex", P(0, 0, 0), (0.155 * s, 0.155 * s, 0.13 * s),
        m=pbr("lantern_glass", "#ff9a2e", rough=0.1, emit="#ffb347", es=4.0, alpha=0.8), parent=parent)
    obj("sphere", P(0, 0, -0.01), (0.075 * s, 0.075 * s, 0.1 * s), m=glow("#fff1c2", 25), parent=parent)
    for k in range(6):
        a = k * math.pi / 3
        obj("cube", P(math.cos(a) * 0.165, math.sin(a) * 0.165, 0), (0.016 * s, 0.016 * s, 0.135 * s), (0, 0, a), ir,
            parent)
    obj("hex", P(0, 0, -0.145), (0.2 * s, 0.2 * s, 0.018 * s), m=ir, parent=parent)
    obj("cone6", P(0, 0, -0.21), (0.15 * s, 0.15 * s, 0.055 * s), (math.pi, 0, 0), ir, parent)
    obj("sphere", P(0, 0, -0.285), 0.03 * s, m=ir, parent=parent)
    pane = 0.155 * math.cos(math.pi / 6) + 0.006
    for sy, spin in ((-1, 0.0), (1, math.pi)):
        obj(leaf_mesh("maple"), P(0, sy * pane, -0.01), 0.15 * s, (math.pi / 2, 0, spin),
            pbr("lantern_leaf", "#3a1410", rough=0.7), parent)
    point_light(P(0, 0, 0), AMBER, 90, 0.2, parent)


def chain(top, bottom, links, parent):
    """Iron chain links from `top` down to `bottom`, each turned a quarter from the last."""
    top, bottom = Vector(top), Vector(bottom)
    if "chain_link" not in _FEATHER:
        _FEATHER["chain_link"] = torus_mesh(1.0, 0.24, 10, 5)
    me = _FEATHER["chain_link"]
    for k in range(links):
        at = top.lerp(bottom, (k + 0.5) / links)
        o = obj(me, at, 1.0, (math.pi / 2, 0, (k % 2) * math.pi / 2), iron(), parent)
        o.scale = (0.05, 0.075, 0.05)  # (its ring stands upright, longer than wide)


def harvest_owl(loc, yaw=0.0, s=1.0, parent=None):
    """The owner's picture of it ("Can you make the owl pet like this image?"): an owl in flight with
    its wings raised wide, every feather an autumn leaf with a glowing edge, maroon at the shoulder
    through crimson and orange to gold at the tips; flame-like leaf ear tufts; fierce glowing eyes
    under dark brows in a cream face ringed with orange; a cream chest; talons reaching forward; a
    fanned leaf tail; and a gothic lantern hanging on a chain from its beak. Groups the game moves:
    Head... (it cocks its head), WingL... / WingR... (they beat from the shoulder: each has a Hinge
    marker there), Lantern... (it swings from the beak), Tail... (it sways)."""
    g = group(loc, (0, 0, yaw), s, parent)
    brown = pbr("owl_feather", "#8a4426", rough=0.7, sheen=0.8)
    head_mat = pbr("owl_head", "#94502c", rough=0.7, sheen=0.8)
    chest = pbr("owl_chest", "#efd2a2", rough=0.75, sheen=0.8)
    face = pbr("owl_face", "#f4dcae", rough=0.7, sheen=0.5)
    beak = pbr("beak", "#3a3238", rough=0.35, coat=0.6)
    gold, orange, ember = fire("#ffc23a"), fire("#ff8a1e"), fire("#ff5a1a")
    crimson, deep, maroon, dark = plume("#c8322a"), plume("#9a1f1c"), plume("#5e1a14"), plume("#7e1a16")
    rust, umber = plume("#d8501e"), plume("#6e2f1c")

    # The body, leaning into its flight: a cream chest of soft scale feathers, a back of russet ones.
    body = group((0, 0.05, -0.08), (0.32, 0, 0), 1, g)
    obj("sphere", (0, 0, 0), (0.5, 0.46, 0.6), m=brown, parent=body, sub=1)
    obj("sphere", (0, -0.22, -0.06), (0.38, 0.25, 0.47), m=chest, parent=body, sub=1)
    tans = [plume("#f6e2bc"), plume("#dcae74")]
    for row, z in enumerate((0.12, -0.08, -0.28)):
        count = 3 if row % 2 == 0 else 2
        for k in range(count):
            theta = math.pi + (k - (count - 1) / 2) * 0.42
            at, n = on_ellipsoid((0, -0.22, -0.06), (0.38, 0.25, 0.47), theta, z)
            feather("scale", at, 0.24, n, (0, 0, -1), tans[(row + k) % 2], body, lift=0.004)
    backs = [plume("#a0522d"), plume("#7a351e")]
    for row, z in enumerate((0.36, 0.14, -0.08, -0.3)):
        count = 9 if row % 2 == 0 else 8
        for k in range(count):
            theta = (k - (count - 1) / 2) * 0.46
            at, n = on_ellipsoid((0, 0, 0), (0.5, 0.46, 0.6), theta, z)
            feather("scale", at, 0.34, n, (0, 0.15, -1), backs[(row + k) % 2], body, lift=0.004)

    # The head: a hood of feathers, a cream face ringed with orange, big glowing eyes under dark
    # brows, flame tufts, a hooked beak.
    head = group((0, 0, 0), (0, 0, 0), 1, g)
    head["piece_prefix"] = "Head"
    H = Vector((0, -0.16, 0.74))
    hinge(H, head)
    obj("sphere", H, (0.5, 0.45, 0.44), m=head_mat, parent=head, sub=1)
    for row, z in enumerate((0.98, 0.8, 0.6)):
        count = 5 if row % 2 == 0 else 4
        for k in range(count):
            theta = (k - (count - 1) / 2) * 0.5
            at, n = on_ellipsoid(H, (0.5, 0.45, 0.44), theta, z)
            feather("scale", at, 0.3, n, (0, 0.3, -1), backs[(row + k) % 2], head, lift=0.004)
    for sx in (-1, 1):
        obj("sphere", (sx * 0.17, -0.5, 0.74), (0.25, 0.11, 0.26), m=face, parent=head, sub=1)
    obj("sphere", (0, -0.52, 0.56), (0.17, 0.09, 0.11), m=face, parent=head, sub=1)
    eye_pair(head, 0.17, -0.6, 0.77, 0.15, iris="#ff9a1a")
    for sx in (-1, 1):
        # The brows: dark over the eyes' inner corners, sweeping up and out (a fierce V).
        feather("blade", (sx * 0.03, -0.72, 0.89), 0.44, (sx * 0.12, -1, 0.3), (sx, 0.15, 0.68), maroon, head,
                width=1.15)
        # The ear tufts: four tongues of leaf fire, curling outward.
        flame = "flameL" if sx < 0 else "flameR"
        for k, (tip, length, rim, core) in enumerate((((sx * 0.3, 0.0, 1), 0.82, gold, crimson),
                                                      ((sx * 0.6, 0.1, 0.9), 0.74, orange, deep),
                                                      ((sx * 0.9, 0.2, 0.7), 0.62, ember, dark),
                                                      ((sx * 0.15, 0.45, 1), 0.55, orange, maroon))):
            fire_feather(flame, (sx * (0.26 + 0.03 * k), -0.18 + 0.05 * k, 1.0), length, (sx * 0.25, -1, 0.3), tip,
                         rim, core, head, lift=-0.025 * k, width=0.75)
    obj("sphere", (0, -0.62, 0.65), (0.065, 0.055, 0.05), m=beak, parent=head)
    obj("cone", (0, -0.66, 0.58), (0.06, 0.05, 0.11), (math.pi - 0.45, 0, 0), beak, head)

    # The wings, raised wide: a fan of flight feathers, each glowing at its edge (ember low, orange,
    # gold at the tips) round a core going maroon to crimson to rust; coverts over their roots on
    # both sides (crimson, then maroon), marginals along the arm. Each wing beats from its shoulder.
    for sx in (-1, 1):
        wing = group((0, 0, 0), (0, 0, 0), 1, g)
        wing["piece_prefix"] = "WingL" if sx < 0 else "WingR"
        out = Vector((sx, 0.2, 0)).normalized()
        up = Vector((0, 0.12, 1)).normalized()
        N = (out.cross(up) * sx).normalized()  # (toward the front)
        dirn = lambda deg: (out * math.cos(math.radians(deg)) + up * math.sin(math.radians(deg))).normalized()  # noqa: E731
        S = Vector((sx * 0.36, 0.14, 0.28))
        hinge(S, wing)
        arm = catmull([S, S + dirn(35) * 0.45, S + dirn(48) * 0.85, S + dirn(48) * 0.85 + dirn(66) * 0.45], 8)
        tube(arm[:len(arm) * 2 // 3], lambda t: 0.1 - 0.04 * t, lambda t: (1, 1, 1, 0), umber, seg=10, parent=wing)
        reach = lambda u: 1.1 + 0.5 * math.sin(math.pi / 2 * u)  # noqa: E731
        n0 = 10
        for k in range(n0):
            u = k / (n0 - 1)
            band = 0 if u < 0.3 else 1 if u < 0.65 else 2
            fire_feather("blade", _along(arm, 0.06 + 0.94 * u), reach(u) * (1.06 if k % 2 else 0.94), N,
                         dirn(-45 + 117 * u), (ember, orange, gold)[band], (dark, crimson, rust)[band], wing,
                         lift=0.024 * (k - (n0 - 1) / 2))
        for side in (1, -1):
            for layer, (count, frac, lift, colors, shape) in enumerate((
                    (7, 0.6, 0.15, (crimson, rust), "blade"),
                    (6, 0.38, 0.2, (maroon, deep), "blade"),
                    (5, 0.3, 0.25, (dark, maroon), "blade"))):
                for k in range(count):
                    u = k / (count - 1) * (0.8 if layer == 2 else 1.0)
                    feather(shape, _along(arm, 0.04 + 0.92 * u), reach(u) * frac, N * side, dirn(-45 + 117 * u),
                            colors[0] if u < 0.5 else colors[1], wing, lift=lift + 0.008 * k, width=1.1)

    # The tail: a fan of glowing leaf feathers trailing down and back (it sways).
    tail = group((0, 0, 0), (0, 0, 0), 1, g)
    tail["piece_prefix"] = "Tail"
    hinge((0, 0.4, -0.48), tail)
    tail_n = Vector((0, 0.65, 0.75)).normalized()
    for k, a in enumerate((-0.7, -0.35, 0.0, 0.35, 0.7)):
        tip = Vector((math.sin(a), 0.75 * math.cos(a), -0.65 * math.cos(a)))
        fire_feather("blade", (math.sin(a) * 0.08, 0.42, -0.5), 1.05 - 0.15 * abs(a), tail_n, tip,
                     gold if k == 2 else orange, crimson if k % 2 == 0 else deep, tail, lift=0.02 * (2 - abs(k - 2)))

    # Talons reaching forward, either side of the lantern.
    leg = pbr("owl_leg", "#dcae74", rough=0.75, sheen=0.8)
    toe, claw = pbr("talon", "#e0a63a", 0.4), pbr("claw", "#2a2228", 0.3, coat=0.5)
    for sx in (-1, 1):
        foot = Vector((sx * 0.3, -0.5, -0.8))
        tube([Vector((sx * 0.22, -0.1, -0.5)), Vector((sx * 0.27, -0.33, -0.7)), foot], lambda t: 0.09 - 0.03 * t,
             lambda t: (1, 1, 1, 0), leg, seg=10, parent=g)
        for k, d in enumerate(((sx * 0.1 - 0.35, -1, -0.3), (sx * 0.1, -1, -0.45), (sx * 0.1 + 0.35, -1, -0.3),
                               (sx * 0.2, 0.7, -0.5))):
            d = Vector(d).normalized()
            end = foot + d * 0.17
            tube([foot, end], lambda t: 0.032, lambda t: (1, 1, 1, 0), toe, seg=8, parent=g)
            hook = (d + Vector((0, 0, -0.9))).normalized()
            obj("cone", end + hook * 0.04, (0.026, 0.026, 0.06), Vector((0, 0, 1)).rotation_difference(hook).to_euler(),
                claw, g)

    # The lantern on its chain, from the beak (it swings from there).
    lamp = group((0, 0, 0), (0, 0, 0), 1, g)
    lamp["piece_prefix"] = "Lantern"
    chain((0, -0.71, 0.5), (0, -0.8, -0.14), 6, lamp)
    gothic_lantern((0, -0.8, -0.86), 1.45, lamp)
    sparks((0, 0, 0.6), 2.0, 22, [AMBER, "#fff1c2", EMBER], (0.02, 0.05), seed=3, z=(-1.2, 2.4), parent=g)
    return g


def metablob(parts, m, parent, name, resolution=0.035):
    """One smooth shape blended from ellipsoids (a metaball, turned into a mesh): `parts` are
    (centre, (rx, ry, rz)), each the visible radii it would have on its own."""
    mb = bpy.data.metaballs.new(name)
    mb.resolution = resolution
    mb.render_resolution = resolution
    for centre, radii in parts:
        el = mb.elements.new(type="ELLIPSOID")
        big = max(radii)
        el.co = centre
        el.radius = big / 0.575  # (a lone element's surface is at 0.575 of its radius)
        el.size_x, el.size_y, el.size_z = (r / big for r in radii)
    holder = bpy.data.objects.new(name, mb)
    link(holder)
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(holder.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(holder)
    me.shade_smooth()
    me.materials.clear()
    me.materials.append(pbr("default", "#888888"))
    return obj(me, (0, 0, 0), 1.0, m=m, parent=parent)


def surface(blob):
    """A ray-caster for a metablob's surface (in its parent's space): where a ray from outside,
    `at` + `direction` * `back`, first meets it heading back toward `at`, and the normal there."""
    me = blob.data
    tree = BVHTree.FromPolygons([v.co.copy() for v in me.vertices], [tuple(p.vertices) for p in me.polygons])

    def cast(at, direction, back=1.5):
        d = Vector(direction).normalized()
        hit, normal, _, _ = tree.ray_cast(Vector(at) + d * back, -d)
        return (Vector(at), d) if hit is None else (hit, normal)

    return cast


def ember_stag(loc, yaw=0.0, s=1.0, parent=None):
    """The owner's picture of it ("Lets use this for the deer as well."): a white stag, sleek and tall,
    with great branching antlers of dark wood cracked with ember light and crowned with maple
    leaves; a mane of leaf feathers down its neck and chest, cream at the throat to gold and crimson
    at the shoulders; a saddle of red leaves down its back; maple-leaf spots on its flanks; a white
    tail tipped with leaves; dark lower legs cracked with ember light, leaf tufts at the fetlocks;
    glowing amber eyes. Groups the game moves: Head... (the neck, head and antlers, turning at the
    neck's root), EarL... / EarR... (they flick), LegFL... / LegFR... / LegBL... / LegBR... (they swing
    from the hip: it gallops after its owner and kicks when it rears), Tail... (it flicks). Each has a
    Hinge marker where it turns."""
    g = group(loc, (0, 0, yaw), s, parent)

    def part(prefix, at):
        sub = group((0, 0, 0), (0, 0, 0), 1, g)
        sub["piece_prefix"] = prefix
        hinge(at, sub)
        return sub

    head = part("Head", (0, -0.52, 0.5))
    fur = pbr("stag_fur", "#f3e7d9", rough=0.65, sheen=0.9)
    sock = pbr("stag_sock", "#4a2a1a", rough=0.75)
    hoof = pbr("hoof", "#24140c", rough=0.4, coat=0.4)
    wood = pbr("antler_wood", "#6b3f22", rough=0.85)
    crack = glow("#ff8a1e", 6)
    gold, orange, ember = fire("#ffc23a"), fire("#ff8a1e"), fire("#ff5a1a")
    crimson, rust, deep = plume("#c8322a"), plume("#e0581e"), plume("#9a1f1c")
    cream, tan, honey = plume("#f6ead8"), plume("#e8c79a"), plume("#f0a040")
    rng = random.Random(11)

    # Smooth white shapes, each blended from ellipsoids: the body; the neck and head; each leg.
    on_body = surface(metablob([((0, -0.44, 0.25), (0.24, 0.34, 0.36)), ((0, 0.04, 0.27), (0.21, 0.42, 0.27)),
                                ((0, 0.48, 0.3), (0.24, 0.3, 0.3))], fur, g, "stag_body"))
    neck = catmull([(0, -0.5, 0.42), (0, -0.66, 0.9), (0, -0.8, 1.3)], 6)
    head_parts = [((0, -0.86, 1.45), (0.14, 0.17, 0.14)), ((0, -1.06, 1.39), (0.085, 0.16, 0.085)),
                  ((0, -1.2, 1.36), (0.065, 0.08, 0.065))]
    for i, p in enumerate(neck):
        r = 0.19 - 0.07 * i / (len(neck) - 1)
        head_parts.append((tuple(p), (r, r, r)))
    on_head = surface(metablob(head_parts, fur, head, "stag_head"))
    legs = []
    for sx in (-1, 1):
        side = "L" if sx < 0 else "R"
        legs += [(f"LegF{side}", (sx * 0.16, -0.45, 0.05), (sx * 0.16, -0.5, -0.55), (sx * 0.16, -0.46, -1.05),
                  (sx * 0.19, -0.42, 0.1)),
                 (f"LegB{side}", (sx * 0.17, 0.55, 0.0), (sx * 0.17, 0.72, -0.5), (sx * 0.17, 0.56, -1.05),
                  (sx * 0.18, 0.5, 0.1))]
    leg_groups = {}
    for name, top, knee, _, thigh in legs:
        hind = top[1] > 0
        leg_groups[name] = part(name, (thigh[0], thigh[1], thigh[2] + 0.12))
        blob = [(thigh, (0.12, 0.22, 0.28) if hind else (0.1, 0.16, 0.24))]
        top, knee = Vector(top), Vector(knee)
        for k in range(9):
            t = (k + 1) / 9
            r = (0.105 if hind else 0.09) * (1 - 0.38 * t)
            blob.append((tuple(top.lerp(knee, t)), (r, r, r)))
        metablob(blob, fur, leg_groups[name], f"stag_{name}")
    for sx in (-1, 1):
        # Big glowing almond eyes, ears out to the sides (pink inside), a black nose.
        eye, n = on_head((sx * 0.1, -0.97, 1.5), (sx * 0.85, -0.45, 0.15))
        obj("sphere", eye - n * 0.012, (0.032, 0.058, 0.036), (0, 0, sx * 0.35), glow("#ffa020", 9), head)
        root, _ = on_head((sx * 0.1, -0.8, 1.55), (sx * 0.7, 0.1, 0.7))
        ear = group(root, (-0.2, sx * 1.2, 0), 1, head)
        ear["piece_prefix"] = "EarL" if sx < 0 else "EarR"
        hinge((0, 0, 0), ear)
        obj("sphere", (0, 0, 0.12), (0.08, 0.035, 0.17), m=fur, parent=ear, sub=1)
        obj("sphere", (0, -0.024, 0.12), (0.055, 0.02, 0.125), m=pbr("ear_pink", "#f0aeb0", rough=0.6), parent=ear)
    nose, _ = on_head((0, -1.1, 1.38), (0, -1, 0.1))
    obj("sphere", nose, (0.05, 0.035, 0.035), m=pbr("nose", "#1a1214", 0.3, coat=0.6), parent=head)

    # Lower legs: dark with ember cracks, leaf tufts at the fetlocks, blocky dark hooves.
    for name, top, knee, fet, _ in legs:
        sx = 1 if top[0] > 0 else -1
        lg = leg_groups[name]
        knee, fet = Vector(knee), Vector(fet)
        tube([knee + Vector((0, 0, 0.04)), Vector((fet.x, fet.y, -1.16))], lambda t: 0.06 - 0.012 * t,
             lambda t: (1, 1, 1, 0), sock, seg=10, parent=lg)
        obj(rbox((0.12, 0.15, 0.1), 0.025), (fet.x, fet.y - 0.012, -1.198), 1, m=hoof, parent=lg)
        for off, r in ((Vector((sx * 0.052, 0, 0)), 0.009), (Vector((0, -0.05, 0)), 0.008)):
            mid = (knee + fet) / 2
            tube([knee + off * 1.05 + Vector((0, 0, -0.04)), mid + off + Vector((0.012, 0.012, 0)),
                  fet + off * 0.9 + Vector((0, 0, 0.06))], lambda t: r, lambda t: (1, 1, 1, 0), crack, seg=6, parent=lg)
        for k, a in enumerate((sx * 0.5, sx * 2.6)):
            radial = Vector((math.cos(a), math.sin(a), 0))
            at = fet + radial * 0.05 + Vector((0, 0, -0.03))
            if k == 0:
                fire_feather("maple", at, 0.2, radial + Vector((0, 0, 0.3)), Vector((0, 0, 1)) + radial * 0.6, orange,
                             crimson, lg)
            else:
                feather("maple", at, 0.19, radial + Vector((0, 0, 0.3)), Vector((0, 0, 1)) + radial * 0.6, rust, lg)

    # The mane: leaf feathers round the front of the neck and over the chest and shoulders, cream
    # at the throat, then honey, rust and crimson; a crest of red leaves down the back of the neck.
    for i in range(1, len(neck)):
        t = i / (len(neck) - 1)
        T = (neck[min(i + 1, len(neck) - 1)] - neck[i - 1]).normalized()
        F = Vector((0, -1, -0.2))
        F = (F - T * F.dot(T)).normalized()
        side = T.cross(F)
        radius = 0.19 - 0.07 * t
        color = cream if t > 0.7 else tan if t > 0.45 else honey if t > 0.2 else rust
        for a in (-1.3, -0.45, 0.45, 1.3):
            n = (F * math.cos(a) + side * math.sin(a)).normalized()
            at, normal = on_head(neck[i], n)
            feather("blade", at - normal * 0.02, 0.42, normal, -T + normal * 0.6, color, head, width=1.4,
                    lift=0.006 * abs(a))
        at, normal = on_head(neck[i], -F)
        feather("blade", at - normal * 0.02, 0.38, normal, -T + normal * 0.3, [crimson, rust][i % 2], head, width=1.3)
    for row, (z, color, count) in enumerate(((0.5, honey, 5), (0.32, rust, 6), (0.14, crimson, 5), (-0.02, deep, 4))):
        for k in range(count):
            theta = math.pi + (k - (count - 1) / 2) * 0.45
            at, n = on_body((0, -0.44, z), (math.sin(theta), math.cos(theta), 0.1))
            feather("blade", at, 0.4, n, (0, 0, -1), color if k % 2 == 0 else [rust, crimson, deep, crimson][row], g,
                    width=1.3, lift=0.005)
    # A saddle of red leaves down the back, draping over both flanks.
    for k in range(6):
        y = -0.3 + k * 0.17
        for sx in (-1, 1):
            at, n = on_body((sx * 0.07, y, 0.3), (sx * 0.25, 0, 1))
            feather("blade", at - n * 0.01, 0.38, n, (sx * 0.8, 0.55, -0.55),
                    [crimson, rust, honey, deep][(k + (sx > 0)) % 4], g, width=1.35, lift=0.01 * (k % 2))

    # Maple-leaf spots on its flanks and rump.
    for c, r, n_spots in (((0, 0.04, 0.27), (0.22, 0.43, 0.28), 8), ((0, 0.48, 0.3), (0.25, 0.31, 0.31), 6)):
        for k in range(n_spots):
            sx = -1 if k % 2 else 1
            theta = sx * rng.uniform(1.0, 2.0)
            z = rng.uniform(c[2] - 0.12, c[2] + r[2] * 0.4)
            at, n = on_body((0, c[1] + math.cos(theta) * r[1] * 0.5, z), (math.sin(theta), math.cos(theta) * 0.3, 0))
            feather("maple", at, rng.uniform(0.15, 0.24), n, (rng.uniform(-1, 1), rng.uniform(-1, 1), 1),
                    [crimson, rust, deep, honey][k % 4], g, lift=0.006)

    # The tail: white plumes round its root, red leaves over them.
    root, _ = on_body((0, 0.6, 0.42), (0, 1, 0.3))
    tail = part("Tail", root)
    axis = Vector((0, 1, 0.6)).normalized()
    across = axis.cross(Vector((1, 0, 0))).normalized()
    for k in range(6):
        a = k * 2 * math.pi / 6
        n = (Vector((1, 0, 0)) * math.cos(a) + across * math.sin(a)).normalized()
        feather("blade", root + n * 0.04, 0.46, n, axis + n * 0.3, cream, tail, width=1.6)
    for k, (dx, color) in enumerate(((-0.07, crimson), (0.07, rust), (0.0, honey))):
        feather("maple", root + Vector((dx, 0.12 + 0.04 * k, 0.14 + 0.03 * k)), 0.24, (0, -0.4, 1), (dx * 4, 1, 0.3), color, tail,
                lift=0.02)

    # The antlers: a thick main beam of dark wood each side, spreading wide, with six tines, cracked
    # with ember light along the wood and crowned with clusters of maple leaves, some glowing.
    for sx in (-1, 1):
        beam = catmull([(sx * 0.08, -0.84, 1.56), (sx * 0.3, -0.82, 1.8), (sx * 0.6, -0.74, 2.02),
                        (sx * 0.9, -0.62, 2.25), (sx * 1.12, -0.5, 2.52), (sx * 1.22, -0.42, 2.8)], 6)
        radius = lambda t: 0.085 - 0.05 * t  # noqa: E731
        tube(beam, radius, lambda t: (1, 1, 1, 0), wood, seg=10, parent=head)

        def crack_along(pts, rfn, phase, width=0.011):
            out = []
            for i, p in enumerate(pts):
                t = i / (len(pts) - 1)
                T = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
                up = Vector((0, -0.6, 1))
                a = (up - T * up.dot(T)).normalized()
                b = T.cross(a)
                ang = phase + 0.35 * math.sin(i * 2.3)
                out.append(p + (a * math.cos(ang) + b * math.sin(ang)) * rfn(t) * 0.97)
            tube(out, lambda t: width, lambda t: (1, 1, 1, 0), crack, seg=6, parent=head)

        crack_along(beam, radius, 0.0)
        crack_along(beam[: len(beam) * 2 // 3], radius, 2.4, 0.009)
        tips = [beam[-1]]
        for frac, d, length in ((0.12, (sx * 0.2, -1, 0.55), 0.42), (0.3, (sx * 0.1, -0.35, 1), 0.58),
                                (0.48, (sx * 0.25, -0.15, 1), 0.64), (0.64, (sx * 0.5, 0.0, 1), 0.52),
                                (0.8, (-sx * 0.15, -0.2, 1), 0.46), (0.93, (sx * 1, 0.1, 0.65), 0.36)):
            root = _along(beam, frac)
            d = Vector(d).normalized()
            end = root + d * length
            mid = (root + end) / 2 + Vector((sx * 0.03, 0, 0.04))
            r0 = radius(frac) * 0.75
            tine_r = lambda t, r0=r0: r0 * (1 - 0.6 * t)  # noqa: E731
            tine = catmull([root, mid, end], 4)
            tube(tine, tine_r, lambda t: (1, 1, 1, 0), wood, seg=8, parent=head)
            if length > 0.5:
                crack_along(tine, tine_r, 0.3, 0.008)
                fork = _along(tine, 0.6)
                fork_end = fork + (d + Vector((sx * 0.8, 0, 0.2))).normalized() * length * 0.35
                tube([fork, fork_end], lambda t: r0 * 0.5 * (1 - 0.5 * t), lambda t: (1, 1, 1, 0), wood, seg=6,
                     parent=head)
                tips.append(fork_end)
            tips.append(end)
        for k, tip in enumerate(tips):
            for j in range(3):
                n = Vector((rng.uniform(-0.6, 0.6), rng.uniform(-1, -0.2), rng.uniform(0.2, 0.9)))
                tip_dir = Vector((sx * rng.uniform(0.0, 1), rng.uniform(-0.5, 0.5), rng.uniform(-0.3, 0.9)))
                at = tip + Vector((sx * rng.uniform(-0.08, 0.1), rng.uniform(-0.08, 0.08), rng.uniform(-0.14, 0.04)))
                size = rng.uniform(0.26, 0.36)
                if j == 0:
                    rim, core = ((orange, crimson), (gold, rust), (ember, deep))[(k + (sx > 0)) % 3]
                    fire_feather("maple", at, size, n, tip_dir, rim, core, head)
                else:
                    feather("maple", at, size, n, tip_dir, [crimson, rust, honey, deep][(k + j) % 4], head)
    sparks((0, -0.5, 2.3), 1.5, 22, [EMBER, AMBER, "#fff1c2"], (0.02, 0.05), seed=8, z=(-0.6, 0.8), parent=g)
    return g


def _pumpkin_at(alpha, beta, ribs=10, flat=0.8):
    """A point on hollow_night.pumpkin_mesh(ribs, flat) (radius 1), `alpha` round from its front
    (-Y) and `beta` up from its middle."""
    u = Vector((math.sin(alpha) * math.cos(beta), -math.cos(alpha) * math.cos(beta), math.sin(beta)))
    a = math.atan2(u.y, u.x)
    k = 1 - 0.09 * (1 - math.cos(ribs * a)) / 2 * (1 - abs(u.z) ** 2)
    return Vector((u.x * k, u.y * k, u.z * flat * (1 - 0.18 * max(0.0, u.z) ** 6)))


def carving(centre, r, shapes, m, parent, ribs=10, flat=0.8):
    """Glowing cut-outs on a pumpkin's front (a jack-o'-lantern's face), following its surface a hair
    above it. Each shape is a list of (round, up) angle pairs round its outline, or ("strip", upper
    edge, lower edge) for a band between two edges."""
    c, verts, faces = Vector(centre), [], []

    def put(a, b):
        verts.append(c + _pumpkin_at(a, b, ribs, flat) * r * 1.015)
        return len(verts) - 1

    for shape in shapes:
        if shape[0] == "strip":
            up = [put(a, b) for a, b in shape[1]]
            lo = [put(a, b) for a, b in shape[2]]
            for i in range(len(up) - 1):
                faces += [(up[i], lo[i], lo[i + 1]), (up[i], lo[i + 1], up[i + 1])]
            continue
        ring = []
        for i, (a0, b0) in enumerate(shape):
            a1, b1 = shape[(i + 1) % len(shape)]
            ring += [(a0, b0), ((a0 + a1) / 2, (b0 + b1) / 2)]
        mid = put(sum(p[0] for p in shape) / len(shape), sum(p[1] for p in shape) / len(shape))
        idx = [put(a, b) for a, b in ring]
        faces += [(mid, idx[i], idx[(i + 1) % len(idx)]) for i in range(len(idx))]
    out = []
    for f in faces:  # every face toward the outside
        p0, p1, p2 = (verts[i] for i in f)
        out.append(f if (p1 - p0).cross(p2 - p0).dot((p0 + p1 + p2) / 3 - c) >= 0 else (f[0], f[2], f[1]))
    me = bpy.data.meshes.new("carving")
    me.from_pydata([tuple(v) for v in verts], [], out)
    me.materials.append(pbr("default", "#888888"))
    return obj(me, (0, 0, 0), 1.0, m=m, parent=parent)


def jack_face(centre, r, parent, ribs=10, flat=0.8):
    """An angry jack-o'-lantern's face: slanted eyes and a wide jagged grin, lit from inside."""
    lit = glow("#ffb020", 12)
    eyes = [[(sx * 0.15, 0.1), (sx * 0.6, 0.42), (sx * 0.56, 0.04)] for sx in (-1, 1)]
    for eye in eyes:
        if eye[0][0] < 0:
            eye.reverse()
    n = 14
    upper, lower = [], []
    for i in range(n + 1):
        a = -0.8 + 1.6 * i / n
        q = (a / 0.8) ** 2
        top = -0.1 + 0.16 * q - (0.09 if i % 2 == 1 and 0 < i < n else 0.0)
        bottom = -0.48 + 0.34 * q + (0.08 if i % 2 == 0 and 0 < i < n else 0.0)
        if i in (0, n):
            top = bottom = (top + bottom) / 2
        upper.append((a, top))
        lower.append((a, bottom))
    carving(centre, r, eyes + [("strip", upper, lower)], lit, parent, ribs, flat)


def gourdian(loc, yaw=0.0, s=1.0, parent=None):
    """The owner's picture of it ("Lets use this render for the pumpkin pet too."): a pumpkin-headed
    guardian with an angry jack-o'-lantern face lit from inside, a curling vine stem and tendrils, a
    collar of big autumn leaves turning from green to orange, a mustard-green gourd body wrapped in
    vines, twisted vine arms ending in pumpkin fists cracked with light, and roots trailing below
    it (it floats). Groups the game moves: Head... (it bobs and shakes, turning at its neck; its face
    blazes), FistL... / FistR... (it drums them), Roots... (they sway and stream behind it), Seed...
    (the glowing leaves round it spin)."""
    g = group(loc, (0, 0, yaw), s, parent)
    vine, vine2 = pbr("vine", "#556a24", rough=0.75), pbr("vine_dark", "#4a4a1e", rough=0.8)
    root = pbr("gourd_root", "#5a4a22", rough=0.85)
    crack = glow("#ffb020", 10)
    turning = [(plume("#c8702a"), plume("#6f8a2a")), (plume("#d8582a"), plume("#a89a32")),
               (plume("#8a4a1e"), plume("#7a8a2a")), (plume("#e0902a"), plume("#5e7a24"))]
    rng = random.Random(13)

    def curl(at, axis_up, turns, r0, length, color, parent_=g):
        # A curling tendril: a spiral that tightens as it goes.
        pts = []
        for i in range(14):
            t = i / 13
            a = turns * 2 * math.pi * t
            rad = r0 * (1 - 0.7 * t)
            pts.append(Vector(at) + Vector((math.cos(a) * rad - r0, math.sin(a) * rad * 0.4, t * length)) @ axis_up)
        tube(pts, lambda t: 0.022 * (1 - t) + 0.006, lambda t: (1, 1, 1, 0), color, seg=6, parent=parent_)

    # The head: a big ribbed pumpkin with its angry face, a curling stem with a leaf and a tendril.
    head = group((0, 0, 0), (0, 0, 0), 1, g)
    head["piece_prefix"] = "Head"
    hinge((0, 0, 0.62), head)
    head_c, head_r = Vector((0, -0.02, 1.12)), 0.62
    obj(pumpkin_mesh(10, 0.8), head_c, head_r, m=pbr("pumpkin_head", "#e8701e", rough=0.45, coat=0.3), parent=head)
    jack_face(head_c, head_r, head)
    point_light(head_c + Vector((0, -0.2, 0)), AMBER, 80, 0.3, head)
    stem = catmull([(0, 0, 1.55), (0.04, 0, 1.78), (0.18, 0.05, 1.96), (0.32, 0.0, 2.06), (0.3, -0.12, 2.13),
                    (0.18, -0.12, 2.1)], 6)
    tube(stem, lambda t: 0.075 - 0.05 * t, lambda t: (1, 1, 1, 0), vine, seg=10, parent=head)
    fire_feather("maple", (0.06, 0.02, 1.78), 0.5, (0.2, -0.5, 1), (-1, -0.3, 0.4), *turning[0], head)
    fire_feather("maple", (0.1, 0.06, 1.7), 0.4, (-0.2, 0.6, 1), (1, 0.5, 0.2), *turning[3], head)
    curl((-0.05, 0.02, 1.7), Matrix.Rotation(-0.5, 3, "Y"), 1.6, 0.12, 0.35, vine, head)

    # The collar: two tiers of big leaves round its neck, turning from green to orange.
    for tier, (count, z, length, spread, lean) in enumerate(((9, 0.62, 0.78, 0.36, -0.3), (7, 0.7, 0.6, 0.3, -0.05))):
        for k in range(count):
            a = k * 2 * math.pi / count + tier * 0.35 + 0.2
            radial = Vector((math.cos(a), math.sin(a), 0))
            fire_feather("maple", radial * spread + Vector((0, 0, z)), length, Vector((0, 0, 1)) * 0.85 + radial * 0.5,
                         radial + Vector((0, 0, lean)), *turning[(k + tier) % 4], g, lift=0.03 * tier)

    # The body: a mustard-green gourd wrapped in vines.
    body_c, body_r = Vector((0, 0, 0.02)), 0.7
    obj(pumpkin_mesh(12, 0.85), body_c, body_r, m=pbr("gourd_body", "#8f8a34", rough=0.55, coat=0.2), parent=g)
    for j in range(3):
        pts = []
        for i in range(16):
            t = i / 15
            z = 0.5 - 1.0 * t
            ring = math.sqrt(max(0.05, 1 - (z / 0.6) ** 2)) * body_r * 0.97 + 0.03
            a = j * 2 * math.pi / 3 + t * 2.2 * math.pi
            pts.append(body_c + Vector((math.cos(a) * ring, math.sin(a) * ring, z)))
        tube(pts, lambda t: 0.042, lambda t: (1, 1, 1, 0), [vine, vine2, vine][j], seg=8, parent=g)

    # Twisted vine arms, ending in pumpkin fists cracked with light.
    for sx in (-1, 1):
        path = catmull([(sx * 0.55, 0, 0.45), (sx * 0.95, -0.05, 0.58), (sx * 1.2, -0.1, 0.25),
                        (sx * 1.24, -0.16, -0.12)], 6)
        for strand, color in ((0, vine), (math.pi, vine2)):
            pts = []
            for i, p in enumerate(path):
                t = i / (len(path) - 1)
                T = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
                p1 = T.cross(Vector((0, 1, 0))).normalized()
                p2 = T.cross(p1).normalized()
                a = strand + t * 4 * math.pi
                pts.append(p + (p1 * math.cos(a) + p2 * math.sin(a)) * 0.055)
            tube(pts, lambda t: 0.07 - 0.015 * t, lambda t: (1, 1, 1, 0), color, seg=10, parent=g)
        curl((sx * 1.0, -0.06, 0.58), Matrix.Rotation(sx * 0.8, 3, "Y"), 1.4, 0.1, 0.3, vine)
        fist = group((0, 0, 0), (0, 0, 0), 1, g)
        fist["piece_prefix"] = "FistL" if sx < 0 else "FistR"
        fc = Vector((sx * 1.26, -0.18, -0.42))
        obj(pumpkin_mesh(8, 0.8), fc, 0.33, m=pbr("pumpkin_fist", "#f07e22", rough=0.45, coat=0.3), parent=fist)
        for k in range(3):
            a0 = -0.5 + 0.5 * k + rng.uniform(-0.1, 0.1)
            pts = [fc + _pumpkin_at(a0 + rng.uniform(-0.12, 0.12), b, 8, 0.8) * 0.33 * 1.01 for b in (-0.15, -0.4, -0.65)]
            tube(pts, lambda t: 0.014 * (1 - 0.5 * t), lambda t: (1, 1, 1, 0), crack, seg=6, parent=fist)
        fire_feather("maple", fc + Vector((0, 0.02, 0.2)), 0.34, (sx * 0.3, -0.3, 1), (sx, -0.4, 0.3),
                     *turning[(sx > 0) + 1], fist)
        tube([fc + Vector((0, 0, 0.22)), fc + Vector((sx * 0.03, 0.02, 0.32))], lambda t: 0.035,
             lambda t: (1, 1, 1, 0), vine, seg=8, parent=fist)

    # Roots trailing below (it floats), a few glowing at their ends (they sway, and stream behind it
    # at a run).
    roots = group((0, 0, 0), (0, 0, 0), 1, g)
    roots["piece_prefix"] = "Roots"
    hinge(body_c + Vector((0, 0, -0.5)), roots)
    for k in range(12):
        a = k * 2 * math.pi / 12 + rng.uniform(-0.2, 0.2)
        start = body_c + Vector((math.cos(a) * 0.26, math.sin(a) * 0.26, -0.52))
        length = rng.uniform(0.55, 0.95)
        pts = []
        for i in range(8):
            t = i / 7
            wob = Vector((math.cos(a) * 0.25 * t + 0.06 * math.sin(t * 9 + k), math.sin(a) * 0.25 * t
                          + 0.06 * math.cos(t * 7 + k), -length * t))
            pts.append(start + wob)
        tube(pts, lambda t: 0.04 * (1 - t) + 0.006, lambda t: (1, 1, 1, 0), [root, vine2][k % 2], seg=6,
             parent=roots)
        if k % 3 == 0:
            obj("ico", pts[-1], 0.035, m=glow("#ff8a1e", 10), parent=roots)

    # Glowing leaves circling it (the game spins them).
    seeds = group((0, 0, 0), (0, 0, 0), 1, g)
    seeds["piece_prefix"] = "Seed"
    for k in range(8):
        a = k * 2 * math.pi / 8
        radial = Vector((math.cos(a), math.sin(a), 0))
        at = radial * 1.45 + Vector((0, 0, 0.35 + 0.3 * math.sin(a * 3)))
        fire_feather("maple", at, 0.2, radial + Vector((0, 0, 0.6)), Vector((-math.sin(a), math.cos(a), 0.3)),
                     fire("#ff8a1e"), plume("#c8322a"), seeds)
    sparks((0, 0, 0.6), 1.9, 16, [AMBER, EMBER, "#fff1c2"], (0.02, 0.05), seed=13, z=(-1.0, 1.8), parent=g)
    return g


def lathe(profile, m, parent, seg=40, ridges=0, ridge_amp=0.0, ridge_from=0, flat=False, name="lathe"):
    """A closed shape turned round the Z axis from `profile`, (radius, height) pairs from one point on
    the axis to another. Points from `ridge_from` on are pushed up and down `ridge_amp` in
    `ridges` waves round it (a mushroom's gills)."""
    bm = bmesh.new()
    rings = []
    for i, (r, z) in enumerate(profile):
        if r <= 1e-6:
            rings.append([bm.verts.new((0, 0, z))])
            continue
        ring = []
        for k in range(seg):
            a = 2 * math.pi * k / seg
            dz = ridge_amp * math.cos(ridges * a) if ridges and i >= ridge_from else 0.0
            ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, z + dz)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        if len(a) == 1:
            for k in range(seg):
                bm.faces.new((a[0], b[k], b[(k + 1) % seg]))
        elif len(b) == 1:
            for k in range(seg):
                bm.faces.new((a[k], a[(k + 1) % seg], b[0]))
        else:
            for k in range(seg):
                bm.faces.new((a[k], a[(k + 1) % seg], b[(k + 1) % seg], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if not flat:
        me.shade_smooth()
    me.materials.append(pbr("default", "#888888"))
    return obj(me, (0, 0, 0), 1.0, m=m, parent=parent)


def _flower_loop(n=30):
    """A five-petalled flower's outline (the toadstool's spots)."""
    return [Vector((math.cos(2 * math.pi * i / n) * (0.45 + 0.05 * math.cos(5 * 2 * math.pi * i / n)),
                    math.sin(2 * math.pi * i / n) * (0.45 + 0.05 * math.cos(5 * 2 * math.pi * i / n)), 0))
            for i in range(n)]


def toadstool_tot(loc, yaw=0.0, s=1.0, parent=None):
    """The owner's picture of it ("Lets use this one for the mushroom."): a little cream toadstool
    creature under a wide red bell of a cap with cream flower spots, an orange maple leaf and a
    tuft of moss on top, and gills that glow orange-gold underneath, lighting its face; big glossy
    dark eyes, pink blush, a tiny nose; a cape of autumn leaves over its shoulders with a mossy
    collar; a glowing acorn hugged in one hand; little feet and a stub of a tail. Groups the game
    moves: Cap... (it wobbles; a Hinge marker where it sits on the head)."""
    g = group(loc, (0, 0, yaw), s, parent)
    skin = pbr("tot_skin", "#f4e6cc", rough=0.6, sss=0.3)
    dark = pbr("fall_eye", "#140c1c", rough=0.08, coat=1.0)
    moss = [pbr("moss", "#4e6a22", rough=0.9), pbr("moss_light", "#6f8a2a", rough=0.9)]
    crimson, rust, honey, gold_leaf = plume("#c8322a"), plume("#e0581e"), plume("#f0a040"), plume("#f6c040")
    rng = random.Random(17)

    # The body: a big round head on a little pear of a body, feet, a stub of a tail.
    blob = metablob([((0, 0, 0.86), (0.42, 0.38, 0.38)), ((0, 0, 0.36), (0.27, 0.24, 0.3)),
                     ((-0.13, -0.05, 0.07), (0.1, 0.13, 0.07)), ((0.13, -0.05, 0.07), (0.1, 0.13, 0.07)),
                     ((0, 0.28, 0.3), (0.07, 0.07, 0.07))], skin, g, "tot_body")
    on = surface(blob)
    for sx in (-1, 1):
        # Big glossy eyes with two catchlights each, blush, little arms.
        eye, n = on((sx * 0.16, 0, 0.9), (sx * 0.4, -1, 0.05))
        obj("sphere", eye - n * 0.035, (0.1, 0.06, 0.12), (0, 0, -sx * 0.2), dark, g)
        obj("sphere", eye + n * 0.022 + Vector((-sx * 0.03, 0, 0.045)), 0.034, m=glow("#ffffff", 10), parent=g)
        obj("sphere", eye + n * 0.022 + Vector((sx * 0.025, 0, -0.035)), 0.016, m=glow("#ffffff", 10), parent=g)
        cheek, n = on((sx * 0.28, 0, 0.76), (sx * 0.6, -1, -0.1))
        obj("sphere", cheek, (0.06, 0.02, 0.035), n.to_track_quat("Y", "Z").to_euler(),
            pbr("blush", "#ff9aa8", 0.5, emit="#ff9aa8", es=0.5), g)
        foot, _ = on((sx * 0.13, -0.05, 0.06), (0, -1, -0.2))
        for k in (-1, 0, 1):
            obj("sphere", foot + Vector((k * 0.035, -0.01, -0.01)), 0.022, m=skin, parent=g)
    nose, _ = on((0, 0, 0.79), (0, -1, 0))
    obj("sphere", nose, (0.035, 0.02, 0.025), m=pbr("tot_nose", "#3a2420", 0.3, coat=0.5), parent=g)
    mouth = [on((x, 0, 0.73 + (0.012 if abs(x) > 0.03 else 0.0) - (0.01 if abs(x) == 0.02 else 0.0)),
                (0, -1, 0))[0] for x in (-0.045, -0.02, 0.0, 0.02, 0.045)]
    tube(mouth, lambda t: 0.007, lambda t: (1, 1, 1, 0), pbr("tot_nose", "#3a2420", 0.3, coat=0.5), seg=6, parent=g)
    # Its arms: the right hugging the acorn to its side, the left resting on its belly.
    acorn_at = Vector((0.34, -0.2, 0.36))
    obj("sphere", (0.26, -0.13, 0.44), (0.07, 0.075, 0.14), (0.2, -0.5, 0), skin, g, sub=1)
    obj("sphere", (-0.25, -0.1, 0.42), (0.07, 0.075, 0.14), (0.3, 0.5, 0), skin, g, sub=1)
    obj("sphere", acorn_at, (0.13, 0.13, 0.16), m=glow("#f0a040", 4), parent=g)
    obj("sphere", acorn_at + Vector((0, 0, -0.17)), (0.03, 0.03, 0.04), m=glow("#f0a040", 4), parent=g)
    obj("ico2", acorn_at + Vector((0, 0, 0.1)), (0.15, 0.15, 0.09), m=pbr("acorn_cap", "#6a4426", 0.9), parent=g)
    tube([acorn_at + Vector((0, 0, 0.18)), acorn_at + Vector((0.03, 0, 0.26)), acorn_at + Vector((0.07, 0, 0.27))],
         lambda t: 0.018, lambda t: (1, 1, 1, 0), pbr("acorn_cap", "#6a4426", 0.9), seg=6, parent=g)
    point_light(acorn_at + Vector((0, -0.2, 0)), AMBER, 25, 0.1, g)

    # The cape: autumn leaves over its shoulders and back, a mossy collar, a string tie.
    # (a cloak over its shoulders and back, open at the front where it's tied)
    for row, (z, count, length) in enumerate(((0.5, 8, 0.42), (0.38, 7, 0.42), (0.46, 5, 0.34))):
        for k in range(count):
            spread = 115 if row < 2 else 75
            a = math.radians(-spread + 2 * spread * k / (count - 1))
            out = Vector((math.sin(a), math.cos(a), 0))
            at, n = on((0, 0, z), out + Vector((0, 0, 0.35)))
            feather("maple", at + Vector((0, 0, 0.04)), length, n, Vector((0, 0, -1)) + out * 0.45,
                    [crimson, rust, honey, gold_leaf][(k + row) % 4], g, lift=0.012 + 0.016 * row)
    # (its collar: little green leaves and moss round its neck)
    for k in range(16):
        a = 2 * math.pi * k / 16
        out = Vector((math.sin(a), math.cos(a), 0))
        at, n = on((0, 0, 0.52), out + Vector((0, 0, 0.2)))
        feather("blade", at + Vector((0, 0, 0.03)), 0.17, n, out * 0.3 - Vector((0, 0, 1)), moss[k % 2], g, width=1.3,
                lift=0.05)

    # The cap: a wide red bell, cream flower spots, a leaf and moss on top, glowing gills under it.
    cap = group((0, 0, 0), (0, 0, 0), 1, g)
    cap["piece_prefix"] = "Cap"
    hinge((0, 0, 1.3), cap)
    top = [(0, 1.98), (0.2, 1.95), (0.45, 1.8), (0.68, 1.57), (0.84, 1.38), (0.92, 1.27), (0.94, 1.22),
           (0.9, 1.2), (0.5, 1.33), (0, 1.36)]
    lathe(top, pbr("tot_cap", "#cc3a2a", rough=0.45, coat=0.5), cap, seg=40, name="tot_cap")
    lathe([(0, 1.36), (0.88, 1.2), (0.89, 1.17), (0.7, 1.23), (0.5, 1.29), (0.3, 1.33), (0, 1.34)],
          glow("#ffae3a", 4), cap, seg=72, ridges=36, ridge_amp=0.02, ridge_from=3, flat=True, name="tot_gills")
    spot = pbr("tot_spot", "#f6e2c0", rough=0.6)
    if "flower" not in _FEATHER:
        verts, faces = _fan(_flower_loop(), Vector((0, 0, 0)), 0.02, 0.01)
        me = bpy.data.meshes.new("flower")
        me.from_pydata([tuple(v) for v in verts], [], faces)
        me.materials.append(pbr("default", "#888888"))
        _FEATHER["flower"] = me

    def cap_at(r, a):
        # A point on the cap's top at radius r, angle a, and its outward normal.
        for (r0, z0), (r1, z1) in zip(top, top[1:]):
            if r0 <= r <= r1:
                f = (r - r0) / max(1e-6, r1 - r0)
                z = z0 + (z1 - z0) * f
                slope = (z1 - z0) / max(1e-6, r1 - r0)
                n = Vector((-slope * math.cos(a), -slope * math.sin(a), 1)).normalized()
                return Vector((math.cos(a) * r, math.sin(a) * r, z)), n
        return Vector((0, 0, top[0][1])), Vector((0, 0, 1))

    for k in range(14):
        r = [0.25, 0.48, 0.68, 0.82][k % 4] + rng.uniform(-0.04, 0.04)
        a = k * 2.39996
        at, n = cap_at(r, a)
        obj(_FEATHER["flower"], at + n * 0.012, rng.uniform(0.15, 0.21), n.to_track_quat("Z", "Y").to_euler(), spot, cap)
    at, n = cap_at(0.4, math.radians(130))
    fire_feather("maple", at + n * 0.03, 0.45, n + Vector((0.2, 0, 0.3)), (-1, 0.3, 0.2), fire("#ff8a1e"),
                 plume("#e0581e"), cap)
    for k in range(6):
        a = math.radians(105 + rng.uniform(-30, 35))
        at, n = cap_at(0.25 + rng.uniform(0, 0.2), a)
        feather("blade", at, 0.16, n, (math.cos(a + 1.5), math.sin(a + 1.5), 0), moss[k % 2], cap, width=1.4,
                lift=0.012)
    point_light((0, -0.3, 0.95), AMBER, 50, 0.3, g)
    sparks((0, 0, 1.0), 1.5, 22, ["#fff2cc", "#ffe27a", "#ffb347"], (0.02, 0.04), seed=17, z=(-0.4, 1.4), parent=g)
    return g


def flat_shape(loop, m, parent, at, normal, up, size, name="shape"):
    """A flat shape (outline `loop`, (x, y) pairs round it, star-shaped round its middle) on a
    surface at `at`, facing `normal`, its +Y toward `up`."""
    pts = [Vector((x, y, 0)) for x, y in loop]
    centre = sum(pts, Vector()) / len(pts)
    verts, faces = _fan(pts, centre, 0.0, 0.0)
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces[:len(pts)])  # (the face only: the export gives it a back)
    me.materials.append(pbr("default", "#888888"))
    n = Vector(normal).normalized()
    return obj(me, Vector(at) + n * 0.008, size, _orient(n, up), m, parent)


def crescent(m, parent, at, normal, up, size):
    """A crescent moon, its horns toward +X (a band between two arcs)."""
    outer = [(math.cos(math.radians(100 + 160 * i / 12)), math.sin(math.radians(100 + 160 * i / 12))) for i in range(13)]
    inner = [(0.6 + 1.246 * math.cos(math.radians(128 + 104 * i / 12)), 1.246 * math.sin(math.radians(128 + 104 * i / 12)))
             for i in range(13)]
    verts = [Vector((x, y, 0)) for x, y in outer + inner]
    faces = []
    for i in range(12):
        faces += [(i, 13 + i, 13 + i + 1), (i, 13 + i + 1, i + 1)]
    me = bpy.data.meshes.new("crescent")
    me.from_pydata([tuple(v) for v in verts], [], faces)
    if any(p.normal.z < 0 for p in me.polygons):
        me.flip_normals()
    me.materials.append(pbr("default", "#888888"))
    n = Vector(normal).normalized()
    return obj(me, Vector(at) + n * 0.01, size, _orient(n, up), m, parent)


def lantern_wisp(loc, yaw=0.0, s=1.0, parent=None):
    """The owner's picture of it ("Lets use this as the lantern reference."): an ornate iron lantern,
    six-sided, with a flared roof whose faces each hold a glowing crescent moon, curls at its eaves,
    a ring to hang it by, glass panes, a pointed base with a glowing diamond on each face, and vines
    and maple leaves on its frame; inside, a little mint-white ghost with two dark eyes, its smoky
    tail rising out of the roof and curling over like a crescent. Groups the game moves: Ghost...
    (it bobs and turns inside; it spins in its flourish), Tail... (it sways and curls), each with a
    Hinge marker."""
    g = group(loc, (0, 0, yaw), s, parent)
    ir = pbr("wisp_iron", "#33262a", rough=0.45, metal=0.8)
    trim = pbr("wisp_trim", "#a8742e", rough=0.35, metal=0.9)
    gold = glow("#ffc23a", 8)
    vine = pbr("wisp_vine", "#3e3a1c", rough=0.8)
    R, top, bottom = 0.5, 0.6, -0.58

    # The frame: six posts, rims top and bottom, glass between.
    for k in range(6):
        a = k * math.pi / 3
        obj("cube", (math.cos(a) * R, math.sin(a) * R, 0.01), (0.045, 0.045, 0.6), (0, 0, a), ir, g)
    for z in (top, bottom):
        obj("hex", (0, 0, z), (R + 0.07, R + 0.07, 0.04), m=ir, parent=g)
        obj("hex", (0, 0, z + (0.045 if z > 0 else -0.045)), (R + 0.04, R + 0.04, 0.012), m=trim, parent=g)
    obj("hex", (0, 0, 0.01), (R - 0.03, R - 0.03, 0.57), m=pbr("wisp_glass", "#d8f4ff", 0.05, trans=1.0, ior=1.2),
        parent=g)
    # The roof: a flared six-sided cap, a crescent moon on each face, curls at the eaves, the ring.
    obj("cone6", (0, 0, top + 0.25), (0.66, 0.66, 0.22), m=ir, parent=g)
    obj("hex", (0, 0, top + 0.04), (0.66, 0.66, 0.025), m=ir, parent=g)
    rise, run = 0.44, 0.66 * math.cos(math.pi / 6)
    for k in range(6):
        a = (k + 0.5) * math.pi / 3
        n = Vector((math.cos(a) * rise, math.sin(a) * rise, run)).normalized()
        f = 0.45
        at = Vector((math.cos(a) * run * (1 - f), math.sin(a) * run * (1 - f), top + 0.03 + rise * f))
        up = Vector((-math.cos(a) * run, -math.sin(a) * run, rise))
        crescent(gold, g, at, n, up, 0.2)
        c = k * math.pi / 3
        corner = Vector((math.cos(c) * 0.66, math.sin(c) * 0.66, top + 0.03))
        out = Vector((math.cos(c), math.sin(c), 0))
        side = Vector((-math.sin(c), math.cos(c), 0))
        pts = [corner + out * (0.06 + 0.07 * math.cos(u)) + Vector((0, 0, -0.07 + 0.07 * math.sin(u)))
               + side * 0.0 for u in [i * 0.6 for i in range(9)]]
        tube([corner] + pts, lambda t: 0.022 * (1 - 0.6 * t), lambda t: (1, 1, 1, 0), ir, seg=6, parent=g)
    obj("sphere", (0, 0, top + 0.5), 0.06, m=ir, parent=g)
    torus((0, 0, top + 0.64), 0.1, 0.025, ir, (math.pi / 2, 0, 0), g)
    # The base: a pointed six-sided drop with a glowing diamond on each face.
    obj("cone6", (0, 0, bottom - 0.2), (0.56, 0.56, 0.2), (math.pi, 0, 0), ir, g)
    obj("sphere", (0, 0, bottom - 0.42), 0.04, m=ir, parent=g)
    rise, run = 0.4, 0.56 * math.cos(math.pi / 6)
    for k in range(6):
        a = (k + 0.5) * math.pi / 3
        n = Vector((math.cos(a) * rise, math.sin(a) * rise, -run)).normalized()
        f = 0.5
        at = Vector((math.cos(a) * run * (1 - f), math.sin(a) * run * (1 - f), bottom - rise * f))
        flat_shape([(0, 0.5), (0.32, 0), (0, -0.5), (-0.32, 0)], glow("#ffa526", 8), g, at, n, (0, 0, 1), 0.34,
                   "diamond")
    # Vines up two posts, maple leaves on the frame.
    for k, (a0, z0) in enumerate(((0.0, bottom), (math.pi, bottom + 0.1))):
        pts = []
        for i in range(14):
            t = i / 13
            a = a0 + 0.07 * math.sin(t * 11)
            pts.append(Vector((math.cos(a) * (R + 0.06), math.sin(a) * (R + 0.06), z0 + t * 1.15)))
        tube(pts, lambda t: 0.016, lambda t: (1, 1, 1, 0), vine, seg=6, parent=g)
    for k, (a, z, color) in enumerate(((0.0, -0.45, "#e0581e"), (0.0, 0.5, "#f0a040"), (math.pi, 0.2, "#c8322a"),
                                       (math.pi * 2 / 3, top + 0.1, "#ff8a1e"), (math.pi * 5 / 3, bottom, "#e8621e"))):
        out = Vector((math.cos(a), math.sin(a), 0.3))
        feather("maple", Vector((math.cos(a) * (R + 0.06), math.sin(a) * (R + 0.06), z)), 0.22, out,
                Vector((0, 0, 1)) + out * 0.5, plume(color), g)

    # The ghost: a little glowing mint blob with two dark eyes (each with a glint).
    ghost = group((0, 0, 0), (0, 0, 0), 1, g)
    ghost["piece_prefix"] = "Ghost"
    hinge((0, 0, -0.05), ghost)
    obj("sphere", (0, 0, -0.02), (0.34, 0.3, 0.33), m=glow("#d8fff0", 6), parent=ghost, sub=1)
    obj("sphere", (0, 0.06, -0.3), (0.22, 0.2, 0.13), m=glow("#d8fff0", 6), parent=ghost)
    dark = pbr("fall_eye", "#140c1c", rough=0.08, coat=1.0)
    for sx in (-1, 1):
        obj("sphere", (sx * 0.11, -0.285, 0.01), (0.05, 0.028, 0.085), m=dark, parent=ghost)
        obj("sphere", (sx * 0.11 + 0.014, -0.307, 0.045), 0.016, m=glow("#ffc070", 10), parent=ghost)
    point_light((0, 0, 0), WISP, 120, 0.3, g)
    # Its tail: smoke rising from its back out through the roof, curling over at the top.
    tail = group((0, 0, 0), (0, 0, 0), 1, g)
    tail["piece_prefix"] = "Tail"
    hinge((0.1, 0.05, top + 0.45), tail)
    path = catmull([(0.0, 0.14, 0.25), (0.06, 0.1, 0.55), (0.1, 0.05, top + 0.45), (0.2, 0.02, 1.35),
                    (0.12, 0.12, 1.62), (-0.12, 0.18, 1.8), (-0.36, 0.08, 1.92), (-0.46, -0.1, 2.05),
                    (-0.36, -0.24, 2.18), (-0.14, -0.22, 2.2), (0.0, -0.1, 2.12)], 6)
    c1, c2 = col("#f0fff8"), col(WISP)
    tube(path, lambda t: 0.04 + 0.07 * math.sin(math.pi * min(1.0, t * 1.6)) * (1 - t) + 0.01 * (1 - t),
         lambda t: (*mix(c1, c2, t), 0.8 - 0.55 * t), vmat("wisp_tail", 5.0), seg=14, parent=tail)
    sparks((0, 0, 0.3), 1.4, 18, [AMBER, "#d8fff0", "#ffc070"], (0.02, 0.05), seed=19, z=(-0.8, 2.0), parent=g)
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
