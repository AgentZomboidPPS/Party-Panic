"""Party Panic's own UI art (owner, with a guide to the tells of an AI-made game: "Can we fix these
issues? ... I want you to read it and solve the issues"): the icons that stand in for emoji on the
HUD, the menus and the windows, and the textures the windows and buttons wear. What
src/shared/UiArt.luau points at once uploaded.

    python3 tools/art/ui_art.py                     # every icon still missing, then the sheets
    python3 tools/art/ui_art.py --redo Shop,Coin    # render these icons again
    python3 tools/art/ui_art.py --force             # render every icon again
    python3 tools/art/ui_art.py --upload            # upload what changed and fill UiArt.luau

Writes to assets/images/ui/:
    icons.png    64 icons, 8 x 8 cells of 128 px on a transparent sheet (ICONS below says which cell
                 is which; UiArt.Cells has the same). Each is a little toy modelled and lit in Blender
                 (glossy plastic, gold, glass), shrunk from 256 px, then outlined in the game's dark
                 ink with a soft shadow under it, so it reads like a sticker on any colour at 20 px.
    gloss.png    a button's shine (stretched over it, its corners rounded like the button): a soft
                 light band along the top and a shade along the bottom edge
    pattern.png  a tiling scatter of confetti (white: the window tints it with its transparency)
    bunting.png  a string of party flags that tiles along the bottom of a window's title band
The renders are kept in tools/art/out/ and only made again when missing. Blender is
$PP_BPY_PYTHON (default /home/user/bpyenv/bin/python, a Python with the `bpy` module, run once for
every icon still to render); the rest needs numpy, scipy and Pillow.

--upload puts each sheet up as a Decal under the game owner's account (PP_OWNER_USER_ID, default
11690979745), finds the decal's image on a test server, makes it Open Use and lets the game use it,
and writes the ids into src/shared/UiArt.luau. assets/images/ui/uploaded.json keeps what's up: a file
whose picture hasn't changed isn't uploaded again.
"""

from __future__ import annotations

import math
import os
import random
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OUT = ROOT / "assets" / "images" / "ui"
RENDERS = HERE / "out"
BPY = os.environ.get("PP_BPY_PYTHON", "/home/user/bpyenv/bin/python")
SEASON = ROOT / "tools" / "meshgen" / "season"
UI_ART = ROOT / "src" / "shared" / "UiArt.luau"

CELL = 128  # px: one icon in the sheet
RENDER = 256  # px: rendered at twice the size, then shrunk
COLUMNS = 8

# The sheet, row by row, and the emoji each one stands in for (UiArt.Emoji: the text a label starts
# with that UI/Icons swaps for the picture).
ICONS = [
    ("Shop", "🛍 🛒"), ("Season", "🎃"), ("Emotes", "🕺 💃"), ("Settings", "⚙"),
    ("Close", "✕"), ("Menu", "☰"), ("Coin", "💰 🪙"), ("Key", "🔑 🗝"),
    ("Crate", "📦"), ("Trophy", "🏆"), ("Crown", "👑"), ("Star", "⭐ 🌟"),
    ("Check", "✓ ✅ ✔ ☑"), ("Lock", "🔒 🔐"), ("Unlock", "🔓"), ("Gift", "🎁"),
    ("Medal", "🏅 🎖"), ("First", "🥇"), ("Second", "🥈"), ("Third", "🥉"),
    ("Party", "👥"), ("Person", "👤"), ("Eyes", "👀 👁"), ("Gamepad", "🎮 🕹"),
    ("Bulb", "💡"), ("Letter", "💌 ✉ 📩"), ("Music", "🎵 🎶 🎼"), ("Sparkle", "✨ 💫"),
    ("Phone", "📳 📱"), ("Timer", "⏱ ⏰ ⏲"), ("Hourglass", "⏳ ⌛"), ("Heart", "❤ 💖 💜 💛 💗"),
    ("Flag", "🏁"), ("Ballot", "🗳"), ("Warning", "⚠ ❗"), ("Chat", "💬 🗨"),
    ("Bug", "🐛"), ("Candy", "🍬 🍭"), ("Sleep", "💤"), ("Fire", "🔥"),
    ("Bolt", "⚡"), ("Chart", "📈 📊"), ("Dice", "🎲"), ("Target", "🎯"),
    ("ThumbUp", "👍"), ("ThumbDown", "👎"), ("Gem", "💎 💠"), ("Popper", "🎉 🎊"),
    ("Scroll", "📜 📋"), ("Book", "📖 📚"), ("Lantern", "🏮"), ("Repeat", "🔁 🔄"),
    ("Speaker", "🔊 🔉 🔈"), ("Mute", "🔇"), ("Balloon", "🎈"), ("Cross", "❌ ✖ ✗"),
    ("Leaf", "🍂 🍁"), ("Calendar", "📅 📆"), ("Home", "🏠 🏡"), ("Rocket", "🚀"),
    ("Boom", "💥"), ("Hat", "🎩"), ("Question", "❔ ❓"), ("Camera", "📸 📷"),
]

INK = (34, 16, 58)  # the outline round every icon (Theme.Colors.Ink)


# =================================================================================================
# Blender side (run inside $PP_BPY_PYTHON): one icon per call.

def blender_icon(name: str, out: Path):
    import bpy
    from mathutils import Vector

    sys.path.insert(0, str(SEASON))
    import blender_lib as lib
    from blender_lib import col, group, obj, pbr, rbox, torus, tube

    bpy.ops.wm.read_factory_settings(use_empty=True)
    lib.studio_world("#d8d0ff", "#6a5a9a", 0.55)
    scene = bpy.context.scene
    scene.render.film_transparent = True
    scene.cycles.max_bounces = 6

    # ---- materials: bright toy plastic, metals, glow
    def toy(color, rough=0.3, coat=0.6):
        return pbr(f"toy{color}{rough}", color, rough=rough, coat=coat)

    def metal(color, rough=0.22):
        return pbr(f"metal{color}{rough}", color, rough=rough, metal=1.0)

    def lit(color, strength=2.5, base=None):
        return pbr(f"lit{color}{strength}", base or color, rough=0.4, emit=color, es=strength)

    GOLD, SILVER, BRONZE = "#ffc21a", "#d4dcec", "#e08a48"
    PINK, HOT, PURPLE, VIOLET = "#ff5cab", "#ff2f86", "#7a4cf0", "#b08cff"
    CYAN, BLUE, YELLOW, ORANGE = "#3fc6ff", "#3a6dff", "#ffd23f", "#ff8a2a"
    RED, GREEN, LIME, WHITE, DARK = "#ff4255", "#3ed46e", "#9be15d", "#fffaf2", "#2a1844"
    SKIN = "#ffd29a"

    # ---- shapes
    def rounded(points, r, steps=6):
        """A closed polygon with every corner filleted by r (corners too tight get what fits)."""
        out = []
        n = len(points)
        for i in range(n):
            p0, p1, p2 = Vector(points[i - 1]), Vector(points[i]), Vector(points[(i + 1) % n])
            a, b = (p0 - p1), (p2 - p1)
            la, lb = a.length, b.length
            if la < 1e-6 or lb < 1e-6:
                continue
            a, b = a / la, b / lb
            angle = a.angle(b)
            if angle < 1e-3 or abs(angle - math.pi) < 1e-3:
                out.append(tuple(p1))
                continue
            d = min(r / math.tan(angle / 2), la * 0.45, lb * 0.45)
            rr = d * math.tan(angle / 2)
            s, e = p1 + a * d, p1 + b * d
            bis = (a + b).normalized()
            c = p1 + bis * (rr / math.sin(angle / 2))
            a0 = math.atan2(s.y - c.y, s.x - c.x)
            a1 = math.atan2(e.y - c.y, e.x - c.x)
            da = (a1 - a0 + math.pi) % (2 * math.pi) - math.pi
            for k in range(steps + 1):
                t = a0 + da * k / steps
                out.append((c.x + rr * math.cos(t), c.y + rr * math.sin(t)))
        return out

    def puff(shapes, m, depth=0.3, bevel=0.08, loc=(0, 0, 0), rot=(0, 0, 0), scale=1.0, parent=None):
        """Flat outlines (x right, y up; more than one cuts holes) made into a puffy slab facing the
        camera (-Y)."""
        if shapes and isinstance(shapes[0][0], (int, float)):
            shapes = [shapes]
        cu = bpy.data.curves.new("puff", "CURVE")
        cu.dimensions = "2D"
        cu.fill_mode = "BOTH"
        cu.extrude = depth / 2
        cu.bevel_depth = bevel
        cu.bevel_resolution = 5
        cu.resolution_u = 12
        for pts in shapes:
            sp = cu.splines.new("POLY")
            sp.points.add(len(pts) - 1)
            for i, (x, y) in enumerate(pts):
                sp.points[i].co = (x, y, 0, 1)
            sp.use_cyclic_u = True
            sp.use_smooth = True
        o = bpy.data.objects.new("puff", cu)
        o.data.materials.append(m)
        g = group(loc, rot, scale, parent)
        o.parent = g
        o.rotation_euler = (math.pi / 2, 0, 0)
        lib.link(o)
        return o

    def glyph(body, m, size=1.0, loc=(0, 0, 0), depth=0.25, bevel=0.06, rot=(math.pi / 2, 0, 0), parent=None):
        o = lib.text(body, loc, size, m, "LuckiestGuy", rot, depth / 2, parent)
        o.data.bevel_depth = bevel
        o.data.bevel_resolution = 4
        return o

    def circle(r, n=48, cx=0.0, cy=0.0, start=0.0):
        return [(cx + r * math.cos(start + 2 * math.pi * i / n), cy + r * math.sin(start + 2 * math.pi * i / n)) for i in range(n)]

    def star(outer, inner, n=5, turn=math.pi / 2):
        return [((outer if i % 2 == 0 else inner) * math.cos(turn + math.pi * i / n),
                 (outer if i % 2 == 0 else inner) * math.sin(turn + math.pi * i / n)) for i in range(2 * n)]

    def heart_shape():
        """Two round lobes meeting in a soft point at the bottom."""
        pts = []
        r, cx, cy = 0.55, 0.5, 0.3
        for i in range(25):  # the right lobe, from its inner top round to the outside
            a = math.radians(145 - i * (190 / 24))
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
        pts.append((0.0, -1.0))
        for i in range(25):  # the left lobe, mirrored
            a = math.radians(145 - (24 - i) * (190 / 24))
            pts.append((-(cx + r * math.cos(a)), cy + r * math.sin(a)))
        pts.append((0.0, 0.5))
        return rounded(pts, 0.1, 4)

    def lathe(profile, m, seg=48, loc=(0, 0, 0), rot=(0, 0, 0), parent=None):
        """A turned shape: profile is (radius, height) points from the bottom up."""
        verts, faces = [], []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            for r, z in profile:
                verts.append((r * math.cos(a), r * math.sin(a), z))
        n = len(profile)
        for i in range(seg):
            for j in range(n - 1):
                a0, a1 = i * n + j, ((i + 1) % seg) * n + j
                faces.append((a0, a1, a1 + 1, a0 + 1))
        me = bpy.data.meshes.new("lathe")
        me.from_pydata(verts, [], faces)
        me.shade_smooth()
        me.materials.append(m)
        o = bpy.data.objects.new("lathe", me)
        o.location, o.rotation_euler = loc, rot
        if parent is not None:
            o.parent = parent
        lib.link(o)
        return o

    def arc(center, radius, a0, a1, r, m, plane="XZ", n=32, parent=None):
        c = Vector(center)
        pts = []
        for k in range(n + 1):
            a = a0 + (a1 - a0) * k / n
            if plane == "XZ":
                pts.append(c + Vector((radius * math.cos(a), 0, radius * math.sin(a))))
            else:
                pts.append(c + Vector((radius * math.cos(a), radius * math.sin(a), 0)))
        return tube(pts, lambda t: r, lambda t: (1, 1, 1, 0), m, seg=16, parent=parent)

    def capsule(a, b, r, m, parent=None):
        a, b = Vector(a), Vector(b)
        pts = [a + (b - a) * (k / 8) for k in range(9)]
        tube(pts, lambda t: r, lambda t: (1, 1, 1, 0), m, seg=20, parent=parent)
        obj("sphere", tuple(a), r, m=m, parent=parent)
        obj("sphere", tuple(b), r, m=m, parent=parent)

    def head(loc, shirt, skin=SKIN, scale=1.0, parent=None):
        g = group(loc, (0, 0, 0), scale, parent)
        obj(rbox((1.25, 1.2, 1.2), 0.3), (0, 0, 1.55), 1, m=toy(skin), parent=g)
        for sx in (-1, 1):
            obj("sphere", (sx * 0.24, -0.6, 1.65), (0.1, 0.05, 0.16), m=toy(DARK, 0.2), parent=g)
        puff(rounded([(-0.28, 0.06), (0.28, 0.06), (0, -0.12)], 0.06), toy(DARK, 0.3), 0.04, 0.02,
             loc=(0, -0.61, 1.33), parent=g)
        obj(rbox((2.0, 1.0, 1.1), 0.3), (0, 0, 0.4), 1, m=toy(shirt), parent=g)
        return g

    yaw, elev = -18.0, 14.0  # the view: degrees round from the front, and up

    if name == "Shop":
        obj(rbox((1.7, 0.8, 1.75), 0.14), (0, 0, 0.88), 1, m=toy(PINK))
        obj(rbox((1.74, 0.84, 0.28), 0.1), (0, 0, 1.66), 1, m=toy(HOT))
        for y in (-0.22, 0.22):
            torus((0, y, 1.78), 0.42, 0.075, toy(WHITE), rot=(math.pi / 2, 0, 0))
        puff(rounded(star(0.42, 0.19), 0.05), toy(YELLOW), 0.12, 0.04, loc=(0, -0.43, 0.82))
    elif name == "Season":
        orange = toy("#ff8418", 0.42, 0.35)
        for k in range(8):
            a = 2 * math.pi * k / 8
            obj("sphere", (0.42 * math.cos(a), 0.42 * math.sin(a), 0), (0.62, 0.62, 0.86), m=orange)
        obj("sphere", (0, 0, 0), (0.95, 0.95, 0.88), m=orange)
        tube([Vector((0, 0, 0.7)), Vector((0.02, 0, 1.0)), Vector((0.12, 0, 1.18)), Vector((0.26, 0, 1.24))],
             lambda t: 0.13 - 0.04 * t, lambda t: (1, 1, 1, 0), toy("#5a9a2a", 0.5), seg=12)
        face = lit("#ffc23a", 3.0, "#3a1500")
        for sx in (-1, 1):
            puff(rounded([(-0.2, -0.13), (0.2, -0.13), (0, 0.2)], 0.03), face, 0.1, 0.02,
                 loc=(sx * 0.36, -1.0, 0.22))
        mouth = [(-0.55, 0.05), (-0.3, -0.05), (-0.18, 0.08), (0, -0.06), (0.18, 0.08), (0.3, -0.05),
                 (0.55, 0.05), (0.3, -0.32), (-0.3, -0.32)]
        puff(rounded(mouth, 0.03), face, 0.1, 0.02, loc=(0, -1.0, -0.2))
        yaw, elev = -12, 10
    elif name == "Emotes":
        lib.avatar((0, 0, 0), yaw=math.radians(-15), shirt=PINK, pants=PURPLE, skin=SKIN, arms=2.5, run=0.35)
        for (x, z, s, tilt), c in zip(((2.5, 2.4, 0.85, -12), (-2.5, 3.1, 0.7, 10)), (CYAN, YELLOW)):
            note = toy(c)
            g = group((x, -1.2, z), (0, math.radians(tilt), 0), s)
            obj("sphere", (0, 0, 0), (0.42, 0.3, 0.32), (0, math.radians(-25), 0), note, parent=g)
            obj(rbox((0.14, 0.14, 1.5), 0.05), (0.33, 0, 0.72), 1, m=note, parent=g)
            puff(rounded([(0, 0), (0.6, -0.28), (0.6, -0.6), (0, -0.32)], 0.08), note, 0.14, 0.04,
                 loc=(0.36, 0, 1.45), parent=g)
        yaw, elev = -8, 6
    elif name == "Settings":
        teeth = []
        n = 8
        for i in range(n):
            for a, r in ((-0.30, 0.78), (-0.18, 1.0), (0.18, 1.0), (0.30, 0.78)):
                t = 2 * math.pi * i / n + a * (2 * math.pi / n) * 1.0
                teeth.append((r * math.cos(t), r * math.sin(t)))
        puff([rounded(teeth, 0.05, 3), circle(0.3)], metal("#c9d2ea", 0.28), 0.42, 0.07)
        obj("cyl", (0, 0.02, 0), (0.42, 0.42, 0.18), (math.pi / 2, 0, 0), toy(VIOLET))
        yaw, elev = -16, 12
    elif name == "Close" or name == "Cross":
        w, l = 0.36, 1.0
        x = [(-w, 0), (-l, l - w * 0.4), (-l + w * 0.6, l + w * 0.0), (0, w), (l - w * 0.6, l), (l, l - w * 0.4),
             (w, 0), (l, -l + w * 0.4), (l - w * 0.6, -l), (0, -w), (-l + w * 0.6, -l), (-l, -l + w * 0.4)]
        puff(rounded(x, 0.12), toy(WHITE if name == "Close" else RED, 0.28), 0.4, 0.1)
        yaw, elev = -10, 8
    elif name == "Menu":
        for z in (-0.62, 0, 0.62):
            obj(rbox((1.9, 0.42, 0.4), 0.17), (0, 0, z), 1, m=toy(WHITE))
        yaw, elev = -10, 8
    elif name == "Coin":
        g = group((0, 0, 0), (math.radians(90 - 12), 0, math.radians(-14)), 1)
        gold = metal(GOLD, 0.2)
        obj("cyl", (0, 0, 0), (1, 1, 0.14), m=gold, parent=g)
        torus((0, 0, 0.12), 0.84, 0.07, metal("#ffd95a", 0.18), parent=g)
        torus((0, 0, -0.12), 0.84, 0.07, metal("#ffd95a", 0.18), parent=g)
        s = puff(rounded(star(0.5, 0.22), 0.05), metal("#ffe27a", 0.16), 0.08, 0.04)
        s.parent.parent = g
        s.parent.location = (0, 0, 0.17)
        s.parent.rotation_euler = (-math.pi / 2, 0, 0)
        yaw, elev = 0, 0
    elif name == "Key":
        g = group((0, 0, 0), (0, math.radians(38), 0), 1)
        gold = metal(GOLD, 0.2)
        torus((-0.9, 0, 0), 0.5, 0.16, gold, rot=(math.pi / 2, 0, 0), parent=g)
        obj("sphere", (-0.9, -0.02, 0), 0.24, m=toy(CYAN, 0.1), parent=g)
        obj("cyl", (0.35, 0, 0), (0.13, 0.13, 0.8), (0, math.pi / 2, 0), gold, parent=g)
        for x, h in ((0.75, 0.42), (1.05, 0.3)):
            obj(rbox((0.2, 0.18, h), 0.04), (x, 0, -h / 2 - 0.05), 1, m=gold, parent=g)
        yaw, elev = -10, 8
    elif name == "Crate":
        body = toy(PURPLE, 0.35)
        obj(rbox((1.7, 1.7, 1.5), 0.1), (0, 0, 0.75), 1, m=body)
        trim = metal(GOLD, 0.25)
        for x in (-0.82, 0.82):
            for y in (-0.82, 0.82):
                obj(rbox((0.16, 0.16, 1.56), 0.05), (x, y, 0.75), 1, m=trim)
        for z in (0.04, 1.46):
            for y in (-0.82, 0.82):
                obj(rbox((1.72, 0.16, 0.16), 0.05), (0, y, z), 1, m=trim)
            for x in (-0.82, 0.82):
                obj(rbox((0.16, 1.72, 0.16), 0.05), (x, 0, z), 1, m=trim)
        glyph("?", lit(YELLOW, 1.2, YELLOW), 1.2, (0, -0.88, 0.72), 0.12, 0.04)
        yaw, elev = -28, 20
    elif name == "Trophy":
        gold = metal(GOLD, 0.2)
        lathe([(0.0, 0.0), (0.62, 0.0), (0.62, 0.22), (0.3, 0.3), (0.14, 0.45), (0.12, 0.8), (0.3, 0.95),
               (0.72, 1.3), (0.85, 1.95), (0.9, 2.05), (0.8, 2.05), (0.7, 1.4), (0.0, 1.2)], gold)
        for sx in (-1, 1):
            arc((sx * 0.82, 0, 1.6), 0.32, -math.pi / 2, math.pi / 2, 0.08, gold) if sx > 0 else \
                arc((sx * 0.82, 0, 1.6), 0.32, math.pi / 2, 3 * math.pi / 2, 0.08, gold)
        obj(rbox((1.5, 1.1, 0.4), 0.08), (0, 0, -0.2), 1, m=toy(PURPLE))
        puff(rounded(star(0.28, 0.12), 0.03), toy(WHITE), 0.06, 0.02, loc=(0, -0.79, 1.62))
        yaw, elev = -12, 12
    elif name == "Crown":
        gold = metal(GOLD, 0.2)
        outline = [(-1.0, -0.5), (1.0, -0.5), (1.05, 0.55), (0.55, 0.05), (0, 0.75), (-0.55, 0.05), (-1.05, 0.55)]
        puff(rounded(outline, 0.08), gold, 0.5, 0.08)
        for x, z in ((-1.05, 0.62), (0, 0.84), (1.05, 0.62)):
            obj("sphere", (x, 0, z), 0.15, m=metal("#ffe27a", 0.15))
        obj(rbox((2.1, 0.62, 0.3), 0.1), (0, 0, -0.42), 1, m=metal("#f0a810", 0.25))
        for x, c in ((-0.55, RED), (0, CYAN), (0.55, GREEN)):
            obj("sphere", (x, -0.33, -0.42), (0.14, 0.08, 0.14), m=toy(c, 0.08))
        yaw, elev = -10, 14
    elif name == "Star":
        puff(rounded(star(1.0, 0.46), 0.1), toy(YELLOW, 0.25), 0.42, 0.12)
        yaw, elev = -14, 10
    elif name == "Check":
        pts = [(-1.0, 0.1), (-0.62, 0.48), (-0.28, 0.12), (0.62, 1.02), (1.0, 0.64), (-0.28, -0.64)]
        puff(rounded(pts, 0.12), toy(GREEN, 0.28), 0.42, 0.1)
        yaw, elev = -10, 8
    elif name in ("Lock", "Unlock"):
        body = metal(GOLD, 0.25)
        obj(rbox((1.4, 0.7, 1.15), 0.14), (0, 0, 0.58), 1, m=body)
        silver = metal(SILVER, 0.2)
        if name == "Lock":
            arc((0, 0, 1.15), 0.45, 0, math.pi, 0.12, silver)
            for sx in (-1, 1):
                obj("cyl", (sx * 0.45, 0, 1.08), (0.12, 0.12, 0.12), m=silver)
        else:
            arc((-0.9, 0, 1.55), 0.45, 0, math.pi, 0.12, silver)
            obj("cyl", (-0.45, 0, 1.33), (0.12, 0.12, 0.22), m=silver)
            obj("cyl", (-1.35, 0, 1.45), (0.12, 0.12, 0.12), m=silver)
        puff(circle(0.17, 24, 0, 0.1), toy(DARK), 0.06, 0.02, loc=(0, -0.37, 0.62))
        puff(rounded([(-0.08, 0.05), (0.08, 0.05), (0.12, -0.3), (-0.12, -0.3)], 0.03), toy(DARK), 0.06, 0.02,
             loc=(0, -0.37, 0.62))
        yaw, elev = -16, 12
    elif name == "Gift":
        obj(rbox((1.5, 1.5, 1.15), 0.08), (0, 0, 0.58), 1, m=toy(PINK))
        obj(rbox((1.64, 1.64, 0.34), 0.08), (0, 0, 1.25), 1, m=toy(HOT))
        ribbon = toy(YELLOW, 0.25)
        obj(rbox((0.3, 1.68, 1.5), 0.04), (0, 0, 0.76), 1, m=ribbon)
        obj(rbox((1.68, 0.3, 1.5), 0.04), (0, 0, 0.76), 1, m=ribbon)
        for sx in (-1, 1):
            torus((sx * 0.3, 0, 1.62), 0.3, 0.09, ribbon, rot=(math.pi / 2, sx * 0.5, 0))
        obj("sphere", (0, 0, 1.5), 0.17, m=ribbon)
        yaw, elev = -24, 20
    elif name in ("Medal", "First", "Second", "Third"):
        disk = {"Medal": GOLD, "First": GOLD, "Second": SILVER, "Third": BRONZE}[name]
        for sx, c in ((-1, CYAN if name == "Medal" else BLUE), (1, PINK if name == "Medal" else RED)):
            obj(rbox((0.42, 0.06, 1.35), 0.03), (sx * 0.3, 0.12, 0.82), 1, (0, sx * math.radians(22), 0),
                toy(c, 0.45))
        g = group((0, 0, 0), (math.pi / 2, 0, 0), 1)
        obj("cyl", (0, 0, 0), (0.78, 0.78, 0.12), m=metal(disk, 0.2), parent=g)
        torus((0, 0, 0.12), 0.64, 0.06, metal(disk, 0.14), parent=g)
        if name == "Medal":
            puff(rounded(star(0.42, 0.19), 0.04), toy(WHITE, 0.25), 0.1, 0.03, loc=(0, -0.18, 0))
        else:
            glyph({"First": "1", "Second": "2", "Third": "3"}[name], toy(WHITE, 0.25), 0.95, (0, -0.2, -0.05),
                  0.1, 0.03)
        yaw, elev = -8, 6
    elif name == "Party":
        head((0.85, 0.6, 0.15), PINK, scale=0.95)
        head((-0.55, -0.3, 0), CYAN)
        yaw, elev = -10, 8
    elif name == "Person":
        head((0, 0, 0), PURPLE)
        yaw, elev = -12, 8
    elif name == "Eyes":
        for sx in (-1, 1):
            obj("sphere", (sx * 0.58, 0, 0), (0.52, 0.4, 0.72), m=toy(WHITE, 0.25))
            obj("sphere", (sx * 0.58 + 0.12, -0.36, -0.05), (0.24, 0.1, 0.3), m=toy(DARK, 0.15))
            obj("sphere", (sx * 0.58 + 0.2, -0.44, 0.08), 0.07, m=toy(WHITE, 0.1))
        yaw, elev = -6, 4
    elif name == "Gamepad":
        shape = [(-1.25, 0.45), (1.25, 0.45), (1.45, -0.2), (1.35, -0.6), (0.95, -0.7), (0.55, -0.25),
                 (-0.55, -0.25), (-0.95, -0.7), (-1.35, -0.6), (-1.45, -0.2)]
        puff(rounded(shape, 0.32), toy("#e9e4ff", 0.3), 0.45, 0.1)
        dark = toy(DARK, 0.3)
        for dims in ((0.5, 0.12, 0.16), (0.16, 0.12, 0.5)):
            obj(rbox(dims, 0.04), (-0.78, -0.3, 0.05), 1, m=dark)
        for (x, z), c in zip(((0.78, 0.25), (1.02, 0.03), (0.78, -0.19), (0.54, 0.03)), (GREEN, RED, CYAN, YELLOW)):
            obj("sphere", (x, -0.3, z), 0.11, m=toy(c, 0.2))
        yaw, elev = -10, 18
    elif name == "Bulb":
        lathe([(0.0, 0.0), (0.32, 0.0), (0.34, 0.1), (0.36, 0.45), (0.55, 0.75), (0.8, 1.15), (0.85, 1.5),
               (0.72, 1.9), (0.42, 2.12), (0.0, 2.18)], lit(YELLOW, 1.4, YELLOW))
        for k in range(4):
            torus((0, 0, -0.08 - k * 0.16), 0.34, 0.07, metal(SILVER, 0.3))
        obj("sphere", (0, 0, -0.62), (0.18, 0.18, 0.1), m=toy(DARK))
        yaw, elev = -10, 8
    elif name == "Letter":
        obj(rbox((2.0, 0.14, 1.34), 0.06), (0, 0, 0), 1, m=toy(WHITE, 0.4))
        puff(rounded([(-0.98, 0.64), (0.98, 0.64), (0, -0.12)], 0.06), toy("#f2e6ff", 0.4), 0.04, 0.02,
             loc=(0, -0.09, 0))
        puff(heart_shape(), toy(RED, 0.25), 0.14, 0.05, loc=(0, -0.14, -0.08), scale=0.32)
        yaw, elev = -14, 10
    elif name == "Music":
        note = toy(VIOLET, 0.28)
        for x in (-0.55, 0.55):
            obj("sphere", (x, 0, -0.55), (0.38, 0.27, 0.28), (0, math.radians(-25), 0), note)
            obj(rbox((0.14, 0.14, 1.5), 0.05), (x + 0.3, 0, 0.18), 1, m=note)
        obj(rbox((1.26, 0.16, 0.26), 0.06), (0.3, 0, 0.92), 1, (0, math.radians(-8), 0), note)
        yaw, elev = -10, 8
    elif name == "Sparkle":
        diamond = lambda s: rounded([(0, s), (0.22 * s, 0.22 * s), (s, 0), (0.22 * s, -0.22 * s), (0, -s),
                                     (-0.22 * s, -0.22 * s), (-s, 0), (-0.22 * s, 0.22 * s)], 0.04 * s)
        puff(diamond(1.0), toy(YELLOW, 0.25), 0.3, 0.08, loc=(-0.25, 0, -0.15))
        puff(diamond(0.48), toy("#fff3a8", 0.25), 0.2, 0.06, loc=(0.85, -0.05, 0.75))
        puff(diamond(0.34), toy(CYAN, 0.25), 0.16, 0.05, loc=(0.8, -0.05, -0.75))
        yaw, elev = -8, 6
    elif name == "Phone":
        obj(rbox((1.0, 0.18, 1.8), 0.16), (0, 0, 0), 1, m=toy(PURPLE, 0.3))
        obj(rbox((0.82, 0.04, 1.44), 0.06), (0, -0.1, 0.04), 1, m=lit(CYAN, 0.8, CYAN))
        wave = toy(WHITE)
        for sx in (-1, 1):
            for k, rr in enumerate((0.85, 1.15)):
                a = math.radians(30)
                c = (0, -0.05, 0)
                if sx > 0:
                    arc(c, rr, -a, a, 0.06, wave)
                else:
                    arc(c, rr, math.pi - a, math.pi + a, 0.06, wave)
        yaw, elev = -8, 6
    elif name == "Timer":
        g = group((0, 0, 0), (math.pi / 2, 0, 0), 1)
        obj("cyl", (0, 0, 0), (1, 1, 0.22), m=toy(RED, 0.3), parent=g)
        obj("cyl", (0, 0, 0.06), (0.82, 0.82, 0.2), m=toy(WHITE, 0.35), parent=g)
        obj("cyl", (0, 1.12, 0), (0.18, 0.18, 0.16), (math.pi / 2, 0, 0), toy(RED, 0.3), parent=g)
        obj(rbox((0.42, 0.24, 0.24), 0.06), (0, 0, 1.3), 1, m=toy(RED, 0.3))
        obj(rbox((0.1, 0.06, 0.6), 0.03), (0, -0.3, 0.28), 1, m=toy(DARK))
        obj(rbox((0.1, 0.06, 0.42), 0.03), (0.16, -0.3, -0.1), 1, (0, math.radians(-50), 0), toy(DARK))
        obj("sphere", (0, -0.32, 0), 0.08, m=toy(DARK))
        yaw, elev = -10, 8
    elif name == "Hourglass":
        wood = toy("#c07a3a", 0.45)
        for z in (-1.05, 1.05):
            obj("cyl", (0, 0, z), (0.85, 0.85, 0.12), m=wood)
        for k in range(3):
            a = 2 * math.pi * k / 3 + 0.4
            obj("cyl", (0.72 * math.cos(a), 0.72 * math.sin(a), 0), (0.07, 0.07, 1.0), m=wood)
        glass = pbr("glass", "#d8f4ff", rough=0.05, trans=0.9, ior=1.3, coat=0.5)
        lathe([(0.05, -0.95), (0.6, -0.9), (0.62, -0.55), (0.12, -0.05), (0.12, 0.05), (0.62, 0.55), (0.6, 0.9), (0.05, 0.95)], glass)
        sand = toy(YELLOW, 0.6)
        lathe([(0.0, -0.95), (0.55, -0.92), (0.3, -0.62), (0.0, -0.5)], sand)
        lathe([(0.0, 0.25), (0.3, 0.42), (0.5, 0.75), (0.0, 0.8)], sand)
        yaw, elev = -10, 10
    elif name == "Heart":
        puff(heart_shape(), toy(RED, 0.25), 0.5, 0.12)
        yaw, elev = -10, 8
    elif name == "Flag":
        obj("cyl", (-1.1, 0, 0), (0.08, 0.08, 1.6), m=metal(SILVER))
        obj("sphere", (-1.1, 0, 1.62), 0.13, m=metal(GOLD))
        cloth = lib.vsolid("checker", 0.0, 0.45, 0.2)
        path = [Vector((-1.05 + 2.0 * u, 0.12 * math.sin(u * 6.0), 0.2 + 0.1 * math.sin(u * 4.0)))
                for u in [k / 40 for k in range(41)]]
        light, dark = col(WHITE), col("#241838")
        lib.sheet(path, lambda u: 1.3, lambda u, v: (*(light if (int(u * 5) + int(v * 3.999)) % 2 == 0 else dark), 0),
                  cloth, nv=24)
        yaw, elev = -18, 10
    elif name == "Ballot":
        obj(rbox((1.8, 1.2, 1.25), 0.1), (0, 0, 0), 1, m=toy(BLUE, 0.35))
        obj(rbox((1.0, 0.16, 0.1), 0.03), (0, 0, 0.63), 1, m=toy(DARK))
        obj(rbox((0.85, 0.06, 1.0), 0.03), (0, 0, 1.05), 1, (0, math.radians(6), 0), toy(WHITE, 0.45))
        pts = [(-1.0, 0.1), (-0.62, 0.48), (-0.28, 0.12), (0.62, 1.02), (1.0, 0.64), (-0.28, -0.64)]
        puff(rounded(pts, 0.12), toy(GREEN, 0.3), 0.06, 0.03, loc=(0, -0.06, 1.1), scale=0.28)
        puff(rounded(star(0.3, 0.14), 0.03), toy(YELLOW), 0.06, 0.02, loc=(0, -0.62, -0.05))
        yaw, elev = -20, 14
    elif name == "Warning":
        tri = [(-1.15, -0.9), (1.15, -0.9), (0, 1.1)]
        puff(rounded(tri, 0.22), toy(YELLOW, 0.28), 0.42, 0.1)
        glyph("!", toy(DARK, 0.3), 1.35, (0, -0.32, -0.12), 0.12, 0.03)
        yaw, elev = -8, 6
    elif name == "Chat":
        bubble = rounded([(-1.15, -0.55), (-0.5, -0.55), (-0.7, -1.0), (0.0, -0.55), (1.15, -0.55), (1.15, 0.85),
                          (-1.15, 0.85)], 0.3)
        puff(bubble, toy(WHITE, 0.3), 0.4, 0.1)
        for x in (-0.48, 0, 0.48):
            obj("sphere", (x, -0.32, 0.15), 0.15, m=toy(VIOLET, 0.25))
        yaw, elev = -10, 8
    elif name == "Bug":
        green = toy(LIME, 0.3)
        for k, (x, z, r) in enumerate(((-1.1, -0.15, 0.36), (-0.55, 0.0, 0.42), (0.02, 0.0, 0.45))):
            obj("sphere", (x, 0, z), r, m=green if k % 2 == 0 else toy("#7ed04a", 0.3))
        obj("sphere", (0.62, 0, 0.35), 0.52, m=toy(GREEN, 0.3))
        for sx in (-1, 1):
            obj("sphere", (0.55 + sx * 0.2, -0.42, 0.5), (0.12, 0.08, 0.14), m=toy(WHITE, 0.2))
            obj("sphere", (0.58 + sx * 0.2, -0.5, 0.5), 0.06, m=toy(DARK))
            capsule((0.62 + sx * 0.2, 0, 0.8), (0.75 + sx * 0.35, 0, 1.25), 0.04, toy(DARK))
            obj("sphere", (0.75 + sx * 0.35, 0, 1.27), 0.09, m=toy(PINK))
        yaw, elev = -12, 8
    elif name == "Candy":
        obj("sphere", (0, 0, 0), (0.75, 0.6, 0.6), m=toy(PINK, 0.2))
        for k in range(3):
            torus((-0.3 + k * 0.3, 0, 0), 0.6 - abs(k - 1) * 0.06, 0.06, toy(WHITE, 0.2), rot=(0, math.pi / 2, 0))
        wrap = toy("#ffd0ea", 0.3)
        for sx in (-1, 1):
            g = group((sx * 0.72, 0, 0), (0, sx * math.pi / 2, 0), 1)
            obj("cone", (0, 0, 0.32), (0.42, 0.42, 0.34), (math.pi, 0, 0), wrap, parent=g)
        yaw, elev = -10, 10
    elif name == "Sleep":
        for (x, z, s), c in zip(((-0.42, -0.4, 1.3), (0.42, 0.3, 0.95), (0.92, 0.82, 0.65)), (VIOLET, CYAN, WHITE)):
            glyph("Z", toy(c, 0.3), s, (x, 0, z), 0.3, 0.05)
        yaw, elev = -10, 6
    elif name == "Fire":
        def flame(s, lean=0.0):
            pts = []
            for i in range(40):
                t = 2 * math.pi * i / 40
                r = 1 - 0.55 * max(0.0, math.sin(t)) ** 0.6
                x, y = math.cos(t) * 0.8 * r, math.sin(t)
                y = y * (1.6 if y > 0 else 0.85)
                x += lean * max(0.0, y) ** 2 * 0.25
                pts.append((x * s, y * s))
            return pts
        puff(flame(1.0, 0.6), lit("#ff3a1a", 0.6, "#ff3a1a"), 0.4, 0.1)
        puff(flame(0.68, -0.4), lit(ORANGE, 0.8, ORANGE), 0.3, 0.08, loc=(0, -0.2, -0.2))
        puff(flame(0.38, 0.3), lit(YELLOW, 1.0, YELLOW), 0.2, 0.06, loc=(0, -0.36, -0.36))
        yaw, elev = -6, 4
    elif name == "Bolt":
        pts = [(0.15, 1.3), (-0.75, -0.1), (-0.05, -0.1), (-0.35, -1.3), (0.75, 0.25), (0.05, 0.25), (0.45, 1.3)]
        puff(rounded(pts, 0.06), toy(YELLOW, 0.25), 0.4, 0.1)
        yaw, elev = -10, 6
    elif name == "Chart":
        for x, h, c in ((-0.7, 0.7, PINK), (0.0, 1.15, YELLOW), (0.7, 1.7, GREEN)):
            obj(rbox((0.52, 0.52, h), 0.08), (x, 0, h / 2 - 0.85), 1, m=toy(c, 0.3))
        path = [Vector((-1.0, -0.35, -0.1)), Vector((-0.35, -0.35, 0.3)), Vector((0.2, -0.35, 0.1)),
                Vector((0.85, -0.35, 0.95))]
        tube(lib.catmull(path, 6), lambda t: 0.08, lambda t: (1, 1, 1, 0), toy(RED, 0.3), seg=12)
        obj("cone", (0.98, -0.35, 1.12), (0.2, 0.2, 0.26), (0, math.radians(38), 0), toy(RED, 0.3))
        yaw, elev = -14, 10
    elif name == "Dice":
        obj(rbox((1.6, 1.6, 1.6), 0.28), (0, 0, 0), 1, m=toy(WHITE, 0.3))
        pip = toy(PURPLE, 0.25)
        for x, z in ((-0.4, 0.4), (0.4, -0.4), (0, 0), (-0.4, -0.4), (0.4, 0.4)):
            obj("sphere", (x, -0.8, z), (0.15, 0.06, 0.15), m=pip)
        for x, y in ((0, 0),):
            obj("sphere", (x, y, 0.8), (0.18, 0.18, 0.06), m=toy(RED, 0.25))
        for y, z in ((-0.4, 0.4), (0.4, -0.4)):
            obj("sphere", (0.8, y, z), (0.06, 0.15, 0.15), m=pip)
        yaw, elev = -32, 24
    elif name == "Target":
        g = group((0, 0, 0), (math.pi / 2, 0, 0), 1)
        for k, (r, c) in enumerate(((1.0, RED), (0.76, WHITE), (0.52, RED), (0.28, WHITE))):
            obj("cyl", (0, 0, 0.04 * k), (r, r, 0.16), m=toy(c, 0.35), parent=g)
        obj("cyl", (0.55, -0.6, 0.55), (0.05, 0.05, 0.8), (math.radians(-55), 0, math.radians(-45)), toy("#8a5a2a", 0.5))
        obj("cone", (1.0, -1.1, 1.0), (0.14, 0.14, 0.2), (math.radians(-55), 0, math.radians(-45)), toy(CYAN, 0.3))
        yaw, elev = -14, 10
    elif name in ("ThumbUp", "ThumbDown"):
        # A round badge (green up, red down) with a soft cartoon hand on it: the fingers curled into a
        # stack of rounded knuckles, the thumb up (or, turned over, down), a cuff at the wrist.
        down = name == "ThumbDown"
        disk, rim, cuff = ((RED, "#ff8a96", "#c42a3c") if down else (GREEN, "#8af0a8", "#1f9a4a"))
        badge = group((0, 0, 0), (math.pi / 2, 0, 0), 1)
        obj("cyl", (0, 0, 0), (1.15, 1.15, 0.14), m=toy(disk, 0.3), parent=badge)
        torus((0, 0, 0.13), 1.02, 0.06, toy(rim, 0.3), parent=badge)
        turn = math.pi if down else 0
        hand = group((0.1 if not down else -0.1, -0.4, -0.12 if not down else 0.12), (0, turn, 0), 0.9)
        skin = toy("#fff6ea", 0.35)
        obj(rbox((0.95, 0.6, 1.15), 0.26), (0.1, 0, -0.2), 1, m=skin, parent=hand)
        for k in range(4):
            z = 0.2 - k * 0.3
            capsule((-0.15, -0.07, z), (0.66 - k * 0.06, -0.07, z), 0.17, skin, parent=hand)
        capsule((-0.24, -0.05, 0.26), (-0.12, -0.05, 1.02), 0.2, skin, parent=hand)
        obj(rbox((0.42, 0.68, 1.34), 0.13), (-0.66, 0, -0.24), 1, m=toy(cuff, 0.35), parent=hand)
        yaw, elev = -8, 6
    elif name == "Gem":
        verts = [(0, 0, -1.0)]
        n = 8
        for i in range(n):
            a = 2 * math.pi * i / n
            verts.append((math.cos(a), math.sin(a), 0.0))
        for i in range(n):
            a = 2 * math.pi * (i + 0.5) / n
            verts.append((0.6 * math.cos(a), 0.6 * math.sin(a), 0.45))
        faces = []
        for i in range(n):
            faces.append((0, 1 + (i + 1) % n, 1 + i))
            faces.append((1 + i, 1 + (i + 1) % n, 1 + n + i))
            faces.append((1 + n + i, 1 + (i + 1) % n, 1 + n + (i + 1) % n))
        faces.append(tuple(1 + n + i for i in range(n)))
        me = bpy.data.meshes.new("gem")
        me.from_pydata(verts, [], faces)
        me.materials.append(pbr("gem", "#4ad8ff", rough=0.05, coat=1.0, emit="#2a9aff", es=0.3))
        o = bpy.data.objects.new("gem", me)
        o.scale = (1.0, 1.0, 1.1)
        lib.link(o)
        yaw, elev = -10, 16
    elif name == "Popper":
        g = group((0.3, 0, -0.35), (0, math.radians(-40), 0), 1)
        obj("cone", (0, 0, 0), (0.55, 0.55, 0.9), (math.pi, 0, 0), toy(PINK, 0.3), parent=g)
        for k in range(3):
            torus((0, 0, -0.55 + k * 0.38), 0.17 + k * 0.17, 0.05, toy(YELLOW, 0.3), parent=g)
        rng = random.Random(4)
        for k in range(14):
            a = rng.uniform(math.radians(100), math.radians(200))
            r = rng.uniform(0.7, 1.5)
            c = rng.choice([CYAN, YELLOW, GREEN, PINK, VIOLET, ORANGE])
            obj(rbox((0.18, 0.05, 0.1), 0.02), (0.1 + r * math.cos(a) * 0.9, -0.2, 0.25 + r * math.sin(a) * 0.9 + 0.5), 1,
                (rng.random() * 3, rng.random() * 3, rng.random() * 3), toy(c, 0.3))
        for k, c in enumerate((CYAN, YELLOW)):
            pts = [Vector((-0.2 - t * 1.0, -0.1, 0.5 + t * 0.9 + 0.2 * math.sin(t * 9 + k * 2))) for t in [j / 16 for j in range(17)]]
            tube(pts, lambda t: 0.05, lambda t: (1, 1, 1, 0), toy(c, 0.3), seg=10)
        yaw, elev = -8, 6
    elif name == "Scroll":
        paper = toy("#fff1d0", 0.55)
        obj(rbox((1.5, 0.08, 1.6), 0.03), (0, 0, 0), 1, m=paper)
        for z in (-0.85, 0.85):
            obj("cyl", (0, 0, z), (0.2, 0.2, 0.86), (0, math.pi / 2, 0), toy("#f0d9a8", 0.5))
            for sx in (-1, 1):
                obj("sphere", (sx * 0.9, 0, z), 0.16, m=toy("#a0602a", 0.4))
        for k in range(4):
            obj(rbox((1.0 - (k % 2) * 0.3, 0.04, 0.08), 0.02), (-0.08 * (k % 2), -0.06, 0.45 - k * 0.3), 1,
                m=toy("#c09a70", 0.6))
        yaw, elev = -12, 8
    elif name == "Book":
        obj(rbox((2.2, 1.2, 0.16), 0.05), (0, 0, -0.1), 1, m=toy(PURPLE, 0.35))
        for sx in (-1, 1):
            obj(rbox((1.0, 1.06, 0.2), 0.05), (sx * 0.52, 0, 0.1), 1, (0, sx * math.radians(-8), 0), toy(WHITE, 0.5))
        for sx in (-1, 1):
            for k in range(3):
                obj(rbox((0.6, 0.06, 0.03), 0.01), (sx * 0.52, -0.2 + k * 0.25, 0.24 + 0.02), 1,
                    (0, sx * math.radians(-8), math.pi / 2 * 0), toy(VIOLET, 0.5))
        yaw, elev = -10, 48
    elif name == "Lantern":
        obj("sphere", (0, 0, 0), (0.95, 0.95, 0.82), m=lit("#ff5a3a", 0.5, "#ff3a2a"))
        for k in range(6):
            a = math.pi * k / 6
            g = group((0, 0, 0), (0, 0, a), 1)
            obj("sphere", (0, 0, 0), (0.96, 0.08, 0.83), m=toy("#c4202a", 0.4), parent=g)
        for z in (-0.82, 0.82):
            obj("cyl", (0, 0, z), (0.42, 0.42, 0.1), m=metal(GOLD))
        obj("cone", (0, 0, -1.2), (0.12, 0.12, 0.3), m=toy(YELLOW, 0.5))
        yaw, elev = -10, 8
    elif name == "Repeat":
        green = toy(GREEN, 0.3)
        arc((0, 0, 0), 0.85, math.radians(20), math.radians(160), 0.16, green)
        arc((0, 0, 0), 0.85, math.radians(200), math.radians(340), 0.16, green)
        obj("cone", (-0.8, 0, 0.1), (0.32, 0.32, 0.36), (0, 0, 0), green)
        obj("cone", (0.8, 0, -0.1), (0.32, 0.32, 0.36), (math.pi, 0, 0), green)
        yaw, elev = -6, 4
    elif name in ("Speaker", "Mute"):
        body = toy(VIOLET, 0.3)
        obj(rbox((0.5, 0.5, 0.7), 0.08), (-0.8, 0, 0), 1, m=body)
        obj("cone", (-0.3, 0, 0), (0.75, 0.75, 0.5), (0, -math.pi / 2, 0), body)
        if name == "Speaker":
            for rr in (0.55, 0.9):
                arc((0.15, 0, 0), rr, -math.radians(40), math.radians(40), 0.08, toy(CYAN, 0.3))
        else:
            w, l = 0.36, 1.0
            x = [(-w, 0), (-l, l - w * 0.4), (-l + w * 0.6, l), (0, w), (l - w * 0.6, l), (l, l - w * 0.4),
                 (w, 0), (l, -l + w * 0.4), (l - w * 0.6, -l), (0, -w), (-l + w * 0.6, -l), (-l, -l + w * 0.4)]
            puff(rounded(x, 0.12), toy(RED, 0.3), 0.3, 0.08, loc=(0.75, -0.1, 0), scale=0.42)
        yaw, elev = -12, 6
    elif name == "Balloon":
        obj("sphere", (0, 0, 0.3), (0.85, 0.85, 1.05), m=toy(RED, 0.18))
        obj("cone", (0, 0, -0.82), (0.16, 0.16, 0.14), (math.pi, 0, 0), toy(RED, 0.3))
        pts = [Vector((0.08 * math.sin(t * 9), 0, -0.95 - t * 1.0)) for t in [k / 20 for k in range(21)]]
        tube(pts, lambda t: 0.035, lambda t: (1, 1, 1, 0), toy(WHITE, 0.5), seg=8)
        obj("sphere", (-0.32, -0.62, 0.72), (0.14, 0.08, 0.22), (0, math.radians(30), 0), toy("#ffd0d6", 0.1))
        yaw, elev = -8, 6
    elif name == "Leaf":
        pts = []
        for i in range(120):
            t = 2 * math.pi * i / 120
            lobes = 0.78 + 0.22 * math.cos(5 * (t - math.pi / 2)) + 0.1 * math.cos(10 * (t - math.pi / 2))
            r = lobes * (0.65 if math.sin(t) < -0.6 else 1.0)
            pts.append((r * math.cos(t), r * math.sin(t) + 0.1))
        puff(pts, toy(ORANGE, 0.4), 0.18, 0.06)
        tube([Vector((0, -0.12, -0.2)), Vector((0.05, -0.12, -0.9)), Vector((0.15, -0.12, -1.2))],
             lambda t: 0.07, lambda t: (1, 1, 1, 0), toy("#a0502a", 0.5), seg=10)
        yaw, elev = -10, 8
    elif name == "Calendar":
        obj(rbox((1.8, 0.2, 1.7), 0.12), (0, 0, 0), 1, m=toy(WHITE, 0.4))
        obj(rbox((1.84, 0.24, 0.5), 0.1), (0, 0, 0.66), 1, m=toy(RED, 0.3))
        for sx in (-1, 1):
            torus((sx * 0.5, 0, 0.98), 0.17, 0.05, metal(SILVER), rot=(0, math.pi / 2, 0))
        for k in range(6):
            c = [PINK, CYAN, YELLOW, GREEN, VIOLET, ORANGE][k]
            obj(rbox((0.36, 0.06, 0.3), 0.05), (-0.5 + (k % 3) * 0.5, -0.12, 0.05 - (k // 3) * 0.48), 1, m=toy(c, 0.35))
        yaw, elev = -14, 8
    elif name == "Home":
        obj(rbox((1.6, 1.3, 1.15), 0.06), (0, 0, 0), 1, m=toy("#fff1d6", 0.45))
        roof = rounded([(-1.15, 0.0), (1.15, 0.0), (0, 0.95)], 0.08)
        puff(roof, toy(RED, 0.3), 1.55, 0.06, loc=(0, 0, 0.5))
        obj(rbox((0.42, 0.08, 0.7), 0.06), (-0.3, -0.64, -0.22), 1, m=toy(PURPLE, 0.3))
        obj(rbox((0.38, 0.08, 0.38), 0.05), (0.38, -0.64, 0.05), 1, m=lit(CYAN, 0.8, CYAN))
        yaw, elev = -26, 14
    elif name == "Rocket":
        g = group((0, 0, 0), (0, math.radians(40), 0), 1)
        lathe([(0.0, -0.9), (0.42, -0.85), (0.52, -0.3), (0.52, 0.4), (0.4, 0.85), (0.0, 1.35)],
              toy(WHITE, 0.3), parent=g)
        lathe([(0.0, 0.85), (0.405, 0.85), (0.3, 1.1), (0.0, 1.36)], toy(RED, 0.3), parent=g)
        torus((0, -0.5, 0.2), 0.2, 0.05, metal(SILVER), rot=(math.pi / 2, 0, 0), parent=g)
        obj("sphere", (0, -0.48, 0.2), (0.17, 0.06, 0.17), m=lit(CYAN, 0.8, CYAN), parent=g)
        for k in range(3):
            a = 2 * math.pi * k / 3 + math.pi / 2
            f = group((0, 0, 0), (0, 0, a), 1, g)
            puff(rounded([(0.0, -0.95), (0.55, -0.95), (0.0, -0.1)], 0.05), toy(RED, 0.3), 0.08, 0.03,
                 loc=(0.4, 0, 0), rot=(0, 0, math.pi / 2), parent=f)
        lathe([(0.0, -0.9), (0.3, -0.95), (0.2, -1.3), (0.0, -1.55)], lit(ORANGE, 1.5, ORANGE), parent=g)
        yaw, elev = -6, 6
    elif name == "Boom":
        rng = random.Random(9)
        outer = [((1.0 if i % 2 == 0 else 0.55 + rng.uniform(-0.05, 0.05)) * (1 + rng.uniform(-0.1, 0.08)) * math.cos(2 * math.pi * i / 22),
                  (1.0 if i % 2 == 0 else 0.55) * math.sin(2 * math.pi * i / 22)) for i in range(22)]
        puff(rounded(outer, 0.04), toy(ORANGE, 0.3), 0.32, 0.08)
        puff(rounded(star(0.62, 0.36, 9, 0.3), 0.04), lit(YELLOW, 0.8, YELLOW), 0.3, 0.06, loc=(0, -0.2, 0))
        yaw, elev = -6, 4
    elif name == "Hat":
        black = toy("#3a2a5a", 0.35)
        obj("cyl", (0, 0, 0), (1.15, 1.15, 0.08), m=black)
        obj("cyl", (0, 0, 0.75), (0.68, 0.68, 0.72), m=black)
        obj("cyl", (0, 0, 0.32), (0.7, 0.7, 0.16), m=toy(PINK, 0.3))
        yaw, elev = -10, 18
    elif name == "Question":
        glyph("?", toy(VIOLET, 0.28), 2.2, (0, 0, 0), 0.42, 0.08)
        yaw, elev = -10, 6
    elif name == "Camera":
        obj(rbox((1.9, 0.8, 1.25), 0.2), (0, 0, 0), 1, m=toy(DARK, 0.3))
        obj(rbox((0.6, 0.7, 0.3), 0.08), (-0.45, 0, 0.7), 1, m=toy(DARK, 0.3))
        g = group((0.1, -0.4, -0.02), (math.pi / 2, 0, 0), 1)
        obj("cyl", (0, 0, 0.1), (0.52, 0.52, 0.16), m=metal(SILVER), parent=g)
        obj("cyl", (0, 0, 0.18), (0.38, 0.38, 0.12), m=pbr("lens", "#3a6aff", rough=0.05, coat=1.0, emit="#2a4aff", es=0.4), parent=g)
        obj("sphere", (0.62, -0.42, 0.42), (0.12, 0.05, 0.08), m=lit(YELLOW, 1.0, YELLOW))
        obj("cyl", (0.6, 0, 0.66), (0.14, 0.14, 0.06), m=toy(RED, 0.3))
        yaw, elev = -16, 10
    else:
        raise SystemExit(f"ui_art.py: no icon called {name}")

    # ---- frame it: an orthographic camera fitted to everything, from (yaw, elev)
    bpy.context.view_layer.update()
    y, e = math.radians(yaw), math.radians(elev)
    view = Vector((math.sin(y) * math.cos(e), -math.cos(y) * math.cos(e), math.sin(e)))  # from the subject to the eye
    right = Vector((math.cos(y), math.sin(y), 0))
    up = view.cross(right).normalized()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    points = []
    for o in scene.objects:
        if o.type not in ("MESH", "CURVE", "FONT"):
            continue
        ev = o.evaluated_get(depsgraph)
        mesh = ev.to_mesh()
        points += [o.matrix_world @ v.co for v in mesh.vertices]
        ev.to_mesh_clear()
    xs = [p.dot(right) for p in points]
    ys = [p.dot(up) for p in points]
    zs = [p.dot(view) for p in points]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    span = max(max(xs) - min(xs), max(ys) - min(ys)) * 1.04
    center = right * cx + up * cy + view * ((min(zs) + max(zs)) / 2)
    distance = (max(zs) - min(zs)) + 10
    cd = bpy.data.cameras.new("cam")
    cd.type = "ORTHO"
    cd.ortho_scale = span
    cd.clip_end = 500
    cam = bpy.data.objects.new("cam", cd)
    cam.location = center + view * distance
    cam.rotation_euler = (-view).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(cam)
    scene.camera = cam
    size = span
    # Light: a big warm key from the top left, a cool rim from behind on the right, a soft fill below.
    lib.area_light(tuple(center + view * size * 2 - right * size * 1.6 + up * size * 2.0), tuple(center), "#fff4e6", 260 * size * size, size * 2.2)
    lib.area_light(tuple(center - view * size * 1.5 + right * size * 2.0 + up * size * 1.2), tuple(center), "#bfe6ff", 200 * size * size, size * 1.6)
    lib.area_light(tuple(center + view * size * 1.5 + right * size * 1.2 - up * size * 1.6), tuple(center), "#ffd6f0", 70 * size * size, size * 2.0)
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    lib.render(out, RENDER, RENDER, 48)


# =================================================================================================
# Python side: the sheets.

def run_blender(name: str, out: Path):
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(".part.png")
    result = subprocess.run([BPY, str(Path(__file__).resolve()), "--blender", name, str(tmp)],
                            capture_output=True, text=True)
    if result.returncode != 0 or not tmp.exists():
        sys.stderr.write(result.stdout[-3000:] + result.stderr[-3000:])
        raise SystemExit(f"ui_art.py: Blender failed on {name}")
    tmp.replace(out)
    print(f"rendered {out.relative_to(ROOT)}")


def finish_icon(path: Path, cell: int = CELL):
    """A render made into a sticker: the dark ink outline round it, a soft shadow under it, shrunk to
    `cell` with a clear margin."""
    import numpy as np
    from PIL import Image, ImageFilter

    im = Image.open(path).convert("RGBA")
    size = im.size[0]
    # Fit the shape into the cell with room for the outline and the shadow.
    bbox = im.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox() or (0, 0, size, size)
    inner = int(size * 0.80)
    shape = im.crop(bbox)
    k = inner / max(shape.width, shape.height)
    shape = shape.resize((max(1, int(shape.width * k)), max(1, int(shape.height * k))), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(shape, ((size - shape.width) // 2, (size - shape.height) // 2 - int(size * 0.015)))
    a = np.asarray(canvas).astype(np.float32) / 255
    alpha = a[..., 3]
    solid = Image.fromarray((np.clip(alpha * 1.6, 0, 1) * 255).astype(np.uint8))
    ring = solid.filter(ImageFilter.MaxFilter(13)).filter(ImageFilter.GaussianBlur(1.2))
    ring_a = np.asarray(ring).astype(np.float32) / 255
    shadow = Image.fromarray((ring_a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(4))
    shadow_a = np.roll(np.asarray(shadow).astype(np.float32) / 255, int(size * 0.03), axis=0) * 0.45
    ink = np.array(INK, np.float32) / 255
    out_rgb = np.zeros_like(a[..., :3])
    out_a = np.zeros_like(alpha)
    for layer_rgb, layer_a in ((np.broadcast_to(ink, out_rgb.shape) * 0.6, shadow_a),
                               (np.broadcast_to(ink, out_rgb.shape), ring_a), (a[..., :3], alpha)):
        new_a = layer_a + out_a * (1 - layer_a)
        out_rgb = (layer_rgb * layer_a[..., None] + out_rgb * out_a[..., None] * (1 - layer_a[..., None])) / \
            np.maximum(new_a[..., None], 1e-4)
        out_a = new_a
    merged = Image.fromarray((np.dstack([np.clip(out_rgb, 0, 1), np.clip(out_a, 0, 1)]) * 255).astype(np.uint8), "RGBA")
    result = np.asarray(merged.resize((cell, cell), Image.LANCZOS)).copy()
    margin = 2
    result[:margin, :, 3] = 0
    result[-margin:, :, 3] = 0
    result[:, :margin, 3] = 0
    result[:, -margin:, 3] = 0
    return Image.fromarray(result, "RGBA")


def build_icons():
    from PIL import Image

    rows = math.ceil(len(ICONS) / COLUMNS)
    sheet = Image.new("RGBA", (CELL * COLUMNS, CELL * rows), (0, 0, 0, 0))
    for index, (name, _) in enumerate(ICONS):
        path = RENDERS / f"{name}.png"
        if not path.exists():
            continue
        sheet.alpha_composite(finish_icon(path), ((index % COLUMNS) * CELL, (index // COLUMNS) * CELL))
    OUT.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT / "icons.png", optimize=True)
    print(f"wrote {(OUT / 'icons.png').relative_to(ROOT)}")


def build_gloss():
    """A button's shine, stretched over it: a soft light band inset along the top, and a shade along
    the bottom edge that reads as the button's thickness."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter

    w, h = 128, 128
    light = Image.new("L", (w * 2, h * 2), 0)
    ImageDraw.Draw(light).rounded_rectangle([w * 0.16, h * 0.1, w * 1.84, h * 0.82], radius=h * 0.3, fill=255)
    light = np.asarray(light.filter(ImageFilter.GaussianBlur(10)).resize((w, h), Image.LANCZOS)).astype(np.float32) / 255
    rows = np.linspace(0, 1, h)[:, None]
    light *= np.clip(1.1 - rows * 2.4, 0, 1) * 0.6  # brightest at the top, gone by the middle
    shade = np.clip((rows - 0.7) / 0.3, 0, 1) ** 1.4 * 0.34 * np.ones((h, w))
    rgb = np.where(light[..., None] >= shade[..., None], 1.0, 0.0) * np.ones((h, w, 3))
    rgb = np.where(shade[..., None] > light[..., None], np.array(INK, np.float32) / 255 * 0.5, rgb)
    alpha = np.maximum(light, shade)
    Image.fromarray((np.dstack([rgb, alpha]) * 255).astype(np.uint8), "RGBA").save(OUT / "gloss.png", optimize=True)
    print(f"wrote {(OUT / 'gloss.png').relative_to(ROOT)}")


def build_pattern():
    """Confetti scattered so the picture tiles without a seam: dots, little strips, stars and squiggles
    in white (a window shows it faintly over its colour)."""
    from PIL import Image, ImageDraw

    size, k = 256, 4
    big = Image.new("L", (size * k, size * k), 0)
    d = ImageDraw.Draw(big)
    rng = random.Random(11)

    def shape(x, y, kind, s, turn):
        if kind == "dot":
            d.ellipse([x - s, y - s, x + s, y + s], fill=255)
        elif kind == "ring":
            d.ellipse([x - s, y - s, x + s, y + s], outline=255, width=int(s * 0.45))
        elif kind == "strip":
            c, si = math.cos(turn), math.sin(turn)
            pts = [(x + c * dx - si * dy, y + si * dx + c * dy) for dx, dy in
                   ((-s * 1.4, -s * 0.45), (s * 1.4, -s * 0.45), (s * 1.4, s * 0.45), (-s * 1.4, s * 0.45))]
            d.polygon(pts, fill=255)
        elif kind == "star":
            pts = []
            for i in range(10):
                r = s * (1.2 if i % 2 == 0 else 0.5)
                a = turn + math.pi * i / 5
                pts.append((x + r * math.cos(a), y + r * math.sin(a)))
            d.polygon(pts, fill=255)
        else:  # squiggle
            pts = []
            for i in range(13):
                t = i / 12
                pts.append((x + (t - 0.5) * s * 4 * math.cos(turn) - math.sin(t * math.pi * 3) * s * 0.7 * math.sin(turn),
                            y + (t - 0.5) * s * 4 * math.sin(turn) + math.sin(t * math.pi * 3) * s * 0.7 * math.cos(turn)))
            d.line(pts, fill=255, width=int(s * 0.6), joint="curve")

    placed = []
    for _ in range(400):
        if len(placed) >= 22:
            break
        x, y = rng.uniform(0, size), rng.uniform(0, size)
        if any(min(abs(x - px), size - abs(x - px)) ** 2 + min(abs(y - py), size - abs(y - py)) ** 2 < 46 ** 2
               for px, py in placed):
            continue
        placed.append((x, y))
        kind = rng.choice(["dot", "dot", "ring", "strip", "strip", "star", "squiggle"])
        s, turn = rng.uniform(5, 8) * k, rng.uniform(0, math.pi)
        for ox in (-size, 0, size):
            for oy in (-size, 0, size):
                shape((x + ox) * k, (y + oy) * k, kind, s, turn)
    alpha = big.resize((size, size), Image.LANCZOS)
    out = Image.merge("RGBA", (alpha.point(lambda v: 255),) * 3 + (alpha,))
    out.save(OUT / "pattern.png", optimize=True)
    print(f"wrote {(OUT / 'pattern.png').relative_to(ROOT)}")


BUNTING = ["#ff5cab", "#ffd23f", "#3fc6ff", "#3ed46e", "#ff8a2a", "#b08cff"]


def build_bunting():
    """A string of party flags that tiles sideways: two swags of string per picture, flags in the
    game's colours hanging from it, each outlined in ink with a light edge."""
    from PIL import Image, ImageDraw

    w, h, k = 384, 64, 4
    big = Image.new("RGBA", (w * k, h * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    swag = w / 2

    def string_y(x):
        return (5 + 9 * math.sin(math.pi * ((x % swag) / swag))) * k

    ink = (*INK, 255)
    flags = 8
    for i in range(flags):
        x = (i + 0.5) * w / flags
        top = string_y(x * k / k * 1.0) / k
        c = BUNTING[i % len(BUNTING)]
        rgb = tuple(int(c[j:j + 2], 16) for j in (1, 3, 5))
        half = 15
        left, right = x - half, x + half
        lt, rt = string_y(left) / k, string_y(right) / k
        tip = (x, top + 36)
        pts = [(left * k, lt * k), (right * k, rt * k), (tip[0] * k, tip[1] * k)]
        d.polygon(pts, fill=ink)
        inset = [(left + 3.2, lt + 1.6), (right - 3.2, rt + 1.6), (tip[0], tip[1] - 5)]
        d.polygon([(px * k, py * k) for px, py in inset], fill=(*rgb, 255))
        lighter = tuple(min(255, int(v + (255 - v) * 0.45)) for v in rgb)
        d.polygon([(px * k, py * k) for px, py in [inset[0], ((inset[0][0] + inset[1][0]) / 2, (inset[0][1] + inset[1][1]) / 2 + 0.5),
                                                   (tip[0] - 2, tip[1] - 12)]], fill=(*lighter, 255))
    pts = [(x * k, string_y(x)) for x in [j * 0.5 for j in range(int(w * 2) + 1)]]
    d.line(pts, fill=ink, width=int(3.2 * k))
    d.line(pts, fill=(255, 244, 220, 255), width=int(1.4 * k))
    big.resize((w, h), Image.LANCZOS).save(OUT / "bunting.png", optimize=True)
    print(f"wrote {(OUT / 'bunting.png').relative_to(ROOT)}")


UPLOADS = {"Icons": "icons.png", "Gloss": "gloss.png", "Pattern": "pattern.png", "Bunting": "bunting.png"}


def upload_all():
    import hashlib
    import json

    sys.path.insert(0, str(ROOT / "tools"))
    sys.path.insert(0, str(ROOT / "tools" / "preview"))
    from asset_permissions import grant, open_use
    from make_preview import image_in
    from upload_assets import upload

    user = os.environ.get("PP_OWNER_USER_ID", "11690979745")
    record_path = OUT / "uploaded.json"
    record = json.loads(record_path.read_text()) if record_path.exists() else {}
    for key, file in UPLOADS.items():
        path = OUT / file
        digest = hashlib.sha256(path.read_bytes()).hexdigest()[:16]
        entry = record.get(key)
        if entry and entry.get("sha") == digest:
            print(f"{file}: already up (image {entry['image']})")
            continue
        decal = upload(path, "Decal", f"Party Panic UI {key}"[:50],
                       f"Party Panic: the game's own {key.lower()} art for its menus and buttons.",
                       {"userId": user}, "image/png")
        image = image_in(decal)
        opened, errors = open_use([image])
        granted, grant_errors = grant([image, decal])
        print(f"{file}: decal {decal}, image {image}; Open Use {image in opened}, game use {image in granted}")
        if errors or grant_errors:
            print(f"  permission errors: {json.dumps(errors + grant_errors)[:600]}")
        record[key] = {"sha": digest, "decal": decal, "image": image, "file": file}
        record_path.write_text(json.dumps(record, indent=2) + "\n")
    write_ui_art(record)


def write_ui_art(record: dict):
    """Writes src/shared/UiArt.luau: the pictures' ids, the icon cells and the emoji they replace."""
    from PIL import Image

    def asset(key):
        image = record.get(key, {}).get("image")
        return f"rbxassetid://{image}" if image else ""

    bunting = Image.open(OUT / "bunting.png").size
    lines = [
        "-- Party Panic's own UI art (tools/art/ui_art.py makes and uploads it, and writes this file: don't",
        "-- edit it by hand). UI/Icons draws the icons; UI/UIKit and UI/Modal wear the textures.",
        "--   Icons    the icon sheet: Cell px squares, Cells[name] = { column, row } (from 0)",
        "--   Emoji    the emoji each icon stands in for: a label or button whose text starts with one",
        "--            shows the icon instead (UI/Icons.Split)",
        "--   Gloss    a button's shine, stretched over it",
        "--   Pattern  confetti that tiles (white: shown faintly)",
        "--   Bunting  party flags that tile sideways along a window's title band (BuntingSize px)",
        "return {",
        f'\tIcons = "{asset("Icons")}",',
        f'\tGloss = "{asset("Gloss")}",',
        f'\tPattern = "{asset("Pattern")}",',
        f'\tBunting = "{asset("Bunting")}",',
        f"\tBuntingSize = Vector2.new({bunting[0]}, {bunting[1]}),",
        f"\tCell = {CELL},",
        "\tCells = {",
    ]
    for index, (name, _) in enumerate(ICONS):
        lines.append(f"\t\t{name} = {{ {index % COLUMNS}, {index // COLUMNS} }},")
    lines += ["\t} :: { [string]: { number } },", "\tEmoji = {"]
    for name, emoji in ICONS:
        for e in emoji.split():
            lines.append(f'\t\t["{e}"] = "{name}",')
    lines += ["\t} :: { [string]: string },", "}", ""]
    UI_ART.write_text("\n".join(lines))
    print(f"wrote {UI_ART.relative_to(ROOT)}")


def main():
    if "--upload" in sys.argv:
        upload_all()
        return
    if "--blender" in sys.argv:
        i = sys.argv.index("--blender")
        blender_icon(sys.argv[i + 1], Path(sys.argv[i + 2]))
        return
    redo = set()
    if "--redo" in sys.argv:
        redo = set(sys.argv[sys.argv.index("--redo") + 1].split(","))
    only = None
    if "--only" in sys.argv:
        only = set(sys.argv[sys.argv.index("--only") + 1].split(","))
    force = "--force" in sys.argv
    for name, _ in ICONS:
        if only and name not in only:
            continue
        path = RENDERS / f"{name}.png"
        if force or name in redo or not path.exists():
            run_blender(name, path)
    build_icons()
    build_gloss()
    build_pattern()
    build_bunting()


if __name__ == "__main__":
    main()
