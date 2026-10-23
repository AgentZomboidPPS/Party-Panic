"""Makes HOLLOW NIGHT's images for the game (owner: "This has to be sick. This will be players first
season. I want it to look insane."): what src/shared/SeasonArt.luau points at once uploaded.

    python3 tools/meshgen/season/art.py              # everything still missing, then the sheets
    python3 tools/meshgen/season/art.py --redo Pet_HarvestOwl,Key   # render these cells again
    python3 tools/meshgen/season/art.py --force      # render every cell again

Writes to assets/images/season/:
    icons.png   the season's item icons, 5 x 5 cells of 204 px on a transparent sheet (ICONS below
                says which cell is which; SeasonArt.IconCells has the same): the 23 crate items, the
                Hollow Crate and the Lantern Key. Rendered one at a time in Blender with the season's
                own builders (hollow_night.py, hollow_night_pets.py), full quality (not the game
                meshes' low-poly EXPORT shapes), then given a soft glow round their lit parts and a
                dark rim so they read on any card at 64 px.
    leaves.png  a 2 x 2 flipbook of fallen leaves (maple, oak, birch, elm), white with soft shading
                and veins (particles tint them): the falling leaves, the leaf heaps, the bursts
    ember.png   a soft glowing dot (particles)
    moon.png    a crescent moon (either side of THE HARVESTER on name tags)
    packs/      the Robux key packs' product icons (Keys1, Keys5, Keys15, Keys40, Starter: 512 px)
The single renders are kept in tools/meshgen/season/out/art/ and only made again when missing (so a
restarted container picks up where it stopped). Blender is $PP_BPY_PYTHON (default
/home/user/bpyenv/bin/python, a Python with the `bpy` module); the rest needs numpy and Pillow.

    python3 tools/meshgen/season/art.py --upload     # then: upload them and fill SeasonArt.luau

--upload puts icons.png, leaves.png, ember.png and moon.png up as Decals under the game owner's
account (PP_OWNER_USER_ID, default 11690979745), finds each decal's image on a test server, makes
the images Open Use and lets the game use them, and writes their ids (and the icon cells) into
src/shared/SeasonArt.luau. What's uploaded is kept in assets/images/season/uploaded.json: a file
whose picture hasn't changed isn't uploaded again. The pack icons are for the developer products and
aren't uploaded here.
"""

from __future__ import annotations

import math
import os
import random
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / "assets" / "images" / "season"
CELLS = HERE / "out" / "art"
BPY = os.environ.get("PP_BPY_PYTHON", "/home/user/bpyenv/bin/python")
FONTS = HERE / "fonts"

CELL = 204  # px: one icon in the sheet
RENDER = 408  # px: rendered at twice the size, then shrunk (crisper edges)
COLUMNS = 5

# The sheet, row by row (SeasonArt.IconCells: id -> { column, row }).
ICONS = [
    "Pet_HarvestOwl", "Pet_EmberStag", "Pet_Gourdian", "Pet_ToadstoolTot", "Pet_LanternWisp",
    "Hat_LeafCrown", "Hat_Scarecrow", "Hat_AntlerCirclet", "Hat_AcornHelm", "Hat_CrescentMoon",
    "Aura_LeafWhirl", "Aura_Fireflies", "Aura_LanternRing", "Trail_Embers", "Trail_FallingLeaves",
    "Trail_WispSteps", "Elim_CrowScatter", "Elim_LeafPile", "Elim_LanternSnuff", "Victory_Bonfire",
    "Victory_HarvestRain", "Victory_Moonrise", "Title_Harvester", "Crate", "Key",
]
PACKS = {"Keys1": 1, "Keys5": 5, "Keys15": 15, "Keys40": 40, "Starter": 5}


# =================================================================================================
# Blender side (run inside $PP_BPY_PYTHON): one render per call.

def blender_scene(kind: str, out: Path):
    import bpy
    from mathutils import Vector

    sys.path.insert(0, str(HERE))
    import blender_lib as lib
    import hollow_night as H
    import hollow_night_pets as P
    from blender_lib import col, glow, group, mix, obj, pbr, rbox, sparks, torus, tube, vmat

    bpy.ops.wm.read_factory_settings(use_empty=True)
    lib.studio_world("#140a22", "#2a1430", 0.35)
    scene = bpy.context.scene
    scene.render.film_transparent = True
    scene.cycles.transparent_max_bounces = 64
    scene.cycles.max_bounces = 8
    rng = random.Random(7)

    def flame(loc, h, r, seed, colors=("#fff1c2", H.AMBER, H.EMBER), parent=None, strength=7.0):
        c0, c1, c2 = (col(c) for c in colors)
        pts = [Vector(loc) + Vector((0.12 * math.sin(k * 0.9 + seed), 0.12 * math.cos(k * 0.7 + seed), h * k / 12))
               for k in range(13)]
        tube(pts, lambda t: r * math.sin(math.pi * (0.15 + 0.85 * t)) ** 0.8 * (1 - t) ** 0.4 + 0.01,
             lambda t: (*(mix(c0, c1, t * 2) if t < 0.5 else mix(c1, c2, (t - 0.5) * 2)), 0.95 * (1 - t) ** 0.6),
             vmat(f"flame{colors}", strength), seg=16, parent=parent)

    def gradient_text(body, size, extrude, font="GrenzeGotisch"):
        """Blackletter that looks lit from inside: gold at the top to ember at the bottom, glowing."""
        cu = bpy.data.curves.new("t", "FONT")
        cu.body = body
        cu.font = bpy.data.fonts.load(str(FONTS / f"{font}.ttf"))
        cu.size = size
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        cu.extrude = extrude
        cu.bevel_depth = extrude * 0.35
        cu.bevel_resolution = 3
        o = bpy.data.objects.new("title", cu)
        o.rotation_euler = (math.pi / 2, 0, 0)
        m = bpy.data.materials.new("titlegrad")
        m.use_nodes = True
        n, ln = m.node_tree.nodes, m.node_tree.links
        b = n["Principled BSDF"]
        tc = n.new("ShaderNodeTexCoord")
        sep = n.new("ShaderNodeSeparateXYZ")
        mr = n.new("ShaderNodeMapRange")
        mr.inputs["From Min"].default_value = -size * 0.5
        mr.inputs["From Max"].default_value = size * 0.5
        ramp = n.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].color = (*col(H.EMBER), 1)
        ramp.color_ramp.elements[1].color = (*col("#fff0a0"), 1)
        mid = ramp.color_ramp.elements.new(0.55)
        mid.color = (*col(H.GOLDLEAF), 1)
        ln.new(tc.outputs["Object"], sep.inputs[0])
        ln.new(sep.outputs["Y"], mr.inputs["Value"])
        ln.new(mr.outputs["Result"], ramp.inputs["Fac"])
        ln.new(ramp.outputs["Color"], b.inputs["Base Color"])
        ln.new(ramp.outputs["Color"], b.inputs["Emission Color"])
        b.inputs["Emission Strength"].default_value = 0.9
        b.inputs["Metallic"].default_value = 0.6
        b.inputs["Roughness"].default_value = 0.3
        o.data.materials.append(m)
        lib.link(o)
        return o

    def crescent(center, radius, thick, facing, strength=4.0):
        """A crescent moon as a tapering tube arc, opening toward `facing` (+1 right, -1 left)."""
        cx, cz = center
        a0 = 110 if facing < 0 else -70
        pts = [Vector((cx + math.cos(math.radians(a)) * radius, 0, cz + math.sin(math.radians(a)) * radius))
               for a in [a0 + k * (220 / 40) for k in range(41)]]
        if facing > 0:
            pts = [Vector((2 * cx - p.x, 0, p.z)) for p in pts]
        tube(pts, lambda t: 0.02 + thick * math.sin(math.pi * t) ** 0.9, lambda t: (*col("#ffcf7a"), 1.0),
             lib.vsolid("moonicon", strength), seg=20)

    def acorn(loc, s, parent=None):
        g = group(loc, (rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4), rng.uniform(0, 6)), s, parent)
        obj("sphere", (0, 0, 0), (0.09, 0.09, 0.12), m=pbr("acorn", "#a8632e", 0.4, coat=0.5), parent=g)
        obj("half", (0, 0, 0.04), (0.1, 0.1, 0.06), m=pbr("acorn_cap", "#6a4426", 0.9), parent=g)
        return g

    def apple(loc, s):
        g = group(loc, (rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5), rng.uniform(0, 6)), s)
        obj("sphere", (0, 0, 0), (0.2, 0.2, 0.18), m=pbr("apple", "#d0302a", 0.25, coat=1.0), parent=g)
        obj("cyl", (0, 0, 0.2), (0.015, 0.015, 0.06), m=pbr("stem", "#5a3420", 0.8), parent=g)
        H.leaf((0.06, 0, 0.24), 0.18, (0.9, 0, 0.5), "#6aa83a", g)
        return g

    def flier(loc, s, kind, tilt=0.0, mirror=1):
        """A bird in flight seen from the front, wings up in an M: a flat dark silhouette (in the X-Z
        plane) with a faint purple rim. kind "owl" (round head, ear tufts, amber eyes) or "crow" (a
        beak, a fanned tail)."""
        g = group(loc, (0, tilt, 0), s)
        dark = pbr(f"flier{kind}", "#120a18", 0.7, emit="#3a1a5a", es=0.35)
        obj("sphere", (0, 0, 0), (0.2, 0.08, 0.27), m=dark, parent=g)
        obj("sphere", (0, 0, 0.3), (0.16, 0.08, 0.15), m=dark, parent=g)
        for sx in (-1, 1):
            # The wing: an inner part rising from the shoulder, an outer part dipping to the tip.
            obj("sphere", (sx * 0.42, 0, 0.22), (0.4, 0.04, 0.12), (0, -sx * 0.45, 0), dark, g)
            obj("sphere", (sx * 0.95, 0, 0.32), (0.32, 0.035, 0.09), (0, sx * 0.35, 0), dark, g)
            for k in range(3):
                obj("sphere", (sx * (1.12 + 0.06 * k), 0, 0.22 - 0.06 * k), (0.12, 0.03, 0.04),
                    (0, sx * (0.6 + 0.25 * k), 0), dark, g)
            if kind == "owl":
                obj("cone", (sx * 0.1, 0, 0.44), (0.05, 0.03, 0.09), (0, sx * 0.35, 0), dark, g)
                obj("sphere", (sx * 0.065, -0.08, 0.31), 0.035, m=glow(H.AMBER, 12), parent=g)
        if kind == "crow":
            obj("cone", (mirror * 0.2, 0, 0.3), (0.035, 0.03, 0.09), (0, mirror * math.pi / 2, 0),
                pbr("beak", "#e0a030", 0.4), g)
            obj("sphere", (mirror * 0.06, -0.08, 0.33), 0.025, m=glow(H.AMBER, 12), parent=g)
            obj("cone", (0, 0, -0.38), (0.16, 0.03, 0.2), (math.pi, 0, 0), dark, g)
        else:
            obj("cone", (0, 0, -0.36), (0.12, 0.03, 0.14), (math.pi, 0, 0), dark, g)
        return g

    yaw, elev, fov = -0.42, 0.24, 22.0  # the camera: a 3/4 view from a little above
    if kind == "Pet_HarvestOwl":
        P.harvest_owl((0, 0, 0), yaw=0.0)
    elif kind == "Pet_EmberStag":
        P.ember_stag((0, 0, 0), yaw=0.0)
    elif kind == "Pet_Gourdian":
        P.gourdian((0, 0, 0), yaw=0.0)
    elif kind == "Pet_ToadstoolTot":
        P.toadstool_tot((0, 0, 0), yaw=0.0)
    elif kind == "Pet_LanternWisp":
        P.lantern_wisp((0, 0, 0), yaw=0.0)
    elif kind.startswith("Hat_"):
        fn = {"Hat_LeafCrown": P.leaf_crown, "Hat_Scarecrow": P.scarecrow_hat, "Hat_AntlerCirclet": P.antler_circlet,
              "Hat_AcornHelm": P.acorn_helm, "Hat_CrescentMoon": P.crescent_moon}[kind]
        # On a little blocky head, so it reads as a hat at a glance (the hats sit round a head whose
        # middle is the origin).
        skin = pbr("skin", "#ffd0a0", 0.5)
        obj(rbox((1.25, 1.2, 1.2), 0.28), (0, 0, 0), 1, m=skin)
        for sx in (-1, 1):
            obj("sphere", (sx * 0.24, -0.6, 0.08), (0.09, 0.04, 0.15), m=pbr("eye", "#14142a", 0.2))
        smile = [Vector((math.sin(a) * 0.2, -0.61, -0.2 - math.cos(a) * 0.08)) for a in
                 [math.radians(-70 + k * 14) for k in range(11)]]
        tube(smile, lambda t: 0.028, lambda t: (1, 1, 1, 0), pbr("eye", "#14142a", 0.2), seg=8)
        fn(group((0, 0, 0)))
        elev = 0.3
    elif kind == "Crate":
        H.crate((0, 0, 0), 1.0, (0, 0, math.radians(-30)), lid=math.radians(16), inner=H.AMBER)
        sparks((0, 0, 3.0), 1.8, 18, [H.AMBER, "#fff1c2", H.GOLDLEAF], (0.03, 0.07), seed=5, z=(0, 1.6))
        elev = 0.36
    elif kind == "Key":
        H.key((-1.0, 0, 0), (math.radians(20), math.radians(-35), math.radians(25)), 1.0)
        sparks((-1.0, 0, 0), 0.9, 10, [H.AMBER, "#fff1c2"], (0.02, 0.05), seed=4, z=(-0.4, 0.6))
        iron = bpy.data.materials.get("hollow_iron")
        if iron:  # a lighter gunmetal than the game's, so the cage reads on a dark card
            iron.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*col("#7a7290"), 1)
        yaw, elev = -0.3, 0.2
    elif kind == "Title_Harvester":
        gradient_text("H", 3.0, 0.08)
        crescent((-1.62, 0.1), 0.48, 0.13, -1)
        crescent((1.62, 0.1), 0.48, 0.13, 1)
        torus((0, 0.2, 0.05), 2.15, 0.025, glow(H.EMBER, 5), (math.pi / 2, 0, 0))
        sparks((0, -0.2, 0.9), 1.3, 18, [H.AMBER, H.EMBER], (0.025, 0.05), seed=9, z=(-0.4, 1.2))
        yaw, elev = 0.0, 0.0  # straight on: the letter reads as the name tag's
    elif kind == "Aura_LeafWhirl":
        for k in range(46):
            t = k / 46
            a = t * 5 * math.pi
            r = 1.05 + 0.25 * math.sin(t * 7)
            H.leaf((math.cos(a) * r, math.sin(a) * r, t * 2.6), 0.42 + 0.25 * t,
                   (rng.uniform(0, 6), rng.uniform(0, 6), rng.uniform(0, 6)), rng=rng)
        path = [Vector((math.cos(t * 5 * math.pi) * 1.15, math.sin(t * 5 * math.pi) * 1.15, t * 2.6))
                for t in [k / 80 for k in range(81)]]
        tube(path, lambda t: 0.03, lambda t: (*col("#ffd9a0"), 0.35 * math.sin(math.pi * t)), vmat("windstreak", 3), seg=6)
        lib.ring_burst((0, 0, 0.0), 1.3, H.PUMPKIN, 6, None, 0.18)
        elev = 0.3
    elif kind == "Aura_Fireflies":
        for k in range(26):
            p = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
            p = Vector((p.x * 1.2, p.y * 0.8, 0.9 + p.z * 0.9))
            r = rng.uniform(0.05, 0.1)
            obj("sphere", p, r * 1.3, m=glow("#d8ff5a", 9), name="fly")
        for k in range(16):
            x = rng.uniform(-1.3, 1.3)
            obj("cone", (x, rng.uniform(-0.4, 0.4), 0.25), (0.04, 0.04, rng.uniform(0.25, 0.5)),
                (rng.uniform(-0.2, 0.2), rng.uniform(-0.3, 0.3), 0), pbr("grass", "#3a4a1e", 0.8))
        lib.ring_burst((0, 0, 0.02), 1.25, "#c8ff7a", 4, None, 0.12)
        elev = 0.2
    elif kind == "Aura_LanternRing":
        lib.ring_burst((0, 0, 0.9), 1.25, H.AMBER, 4, None, 0.06)
        for k, c in enumerate(["#ff8a2a", "#c8322a", "#ffb530"]):
            a = k * 2 * math.pi / 3 + 0.5
            g = H.paper_lantern(None, c)
            g.location = (math.cos(a) * 1.25, math.sin(a) * 1.25, 0.9 + 0.25 * math.sin(a * 2))
            g.scale = (0.85, 0.85, 0.85)
            lib.point_light(g.location, c, 60, 0.3)
        elev = 0.42
    elif kind == "Trail_Embers":
        path = [Vector((-1.6 + t * 3.2, 0.3 - 0.6 * t, 0.2 + 1.6 * t + 0.45 * math.sin(t * 6))) for t in
                [k / 70 for k in range(71)]]
        lib.ribbon(path, lambda u: 0.15 + 0.6 * u ** 0.8,
                   lambda u, v: (*mix(col(H.CRIMSON), col(H.AMBER), u), 0.92 * u ** 0.9 * (1 - abs(v - 0.5) * 1.5)),
                   vmat("embertrail", 3.5), side=(0, 0, 1))
        sparks((-0.4, 0, 0.9), 1.5, 50, [H.AMBER, H.EMBER, "#fff1c2"], (0.03, 0.07), seed=4, z=(-0.6, 1.2), strength=16)
        obj("sphere", path[-1], 0.22, m=glow("#fff1c2", 18))
        yaw, elev = -0.1, 0.1
    elif kind == "Trail_FallingLeaves":
        for k in range(16):
            t = k / 15
            p = Vector((-1.4 + 2.6 * t, 0.2 * math.sin(t * 5), 1.9 - 1.5 * t + 0.25 * math.sin(t * 9)))
            H.leaf(p, 0.35 + 0.35 * t, (rng.uniform(0.5, 2.5), rng.uniform(0, 6), rng.uniform(0, 6)), rng=rng)
        path = [Vector((-1.6 + 3.0 * t, 0.15, 2.1 - 1.7 * t + 0.25 * math.sin(t * 9))) for t in [k / 60 for k in range(61)]]
        lib.ribbon(path, lambda u: 0.08 + 0.3 * u,
                   lambda u, v: (*col("#ffd9a0"), 0.35 * u * (1 - abs(v - 0.5) * 2)), vmat("leafwind", 2.0),
                   side=(0, 0.3, 1))
        yaw, elev = -0.1, 0.12
    elif kind == "Trail_WispSteps":
        for k in range(4):
            x, y = -1.3 + k * 0.85, (0.25 if k % 2 else -0.25)
            foot = group((x, y, 0), (0, 0, math.radians(90)), 1)
            obj(rbox((0.55, 0.26, 0.04), 0.1), (0, 0, 0.02), 1, m=glow(H.WISP, 3 + k), parent=foot)
            flame((x, y, 0.02), 0.5 + 0.25 * k, 0.16 + 0.03 * k, k, ("#e8fff4", H.WISP, "#1f9a7a"))
            lib.point_light((x, y, 0.4), H.WISP, 40, 0.2)
        sparks((0, 0, 0.6), 1.6, 18, [H.WISP, "#e8fff4"], (0.02, 0.05), seed=6, z=(0, 1.2))
        elev = 0.42
    elif kind == "Elim_CrowScatter":
        # A purple flash where someone was, crows bursting out of it.
        obj("sphere", (0, 1.0, 1.0), 0.75, m=pbr("crowflash", "#000000", 1.0, alpha=0.55, emit="#b07cff", es=18.0))
        obj("sphere", (0, 1.2, 1.0), 1.25, m=pbr("crowhalo", "#000000", 1.0, alpha=0.18, emit="#8a5ad8", es=10.0))
        spots = [(-1.05, 1.75, 0.35, 0.8, -1), (1.1, 1.8, -0.3, 0.75, 1), (-1.35, 0.75, 0.15, 0.7, -1),
                 (1.4, 0.85, -0.2, 0.68, 1), (0.05, 2.1, 0.0, 0.62, 1), (-0.45, 0.15, 0.25, 0.55, -1),
                 (0.6, 0.2, -0.25, 0.55, 1)]
        for x, z, tilt, size, mirror in spots:
            flier((x, -0.2, z), size, "crow", tilt, mirror)
        for k in range(10):
            obj(H.leaf_mesh("long"), (rng.uniform(-1.4, 1.4), -0.1, rng.uniform(0.1, 2.2)), 0.2,
                (rng.uniform(0, 6), rng.uniform(0, 6), rng.uniform(0, 6)), pbr("flier_crow", "#120a18", 0.7))
        sparks((0, 0, 1.0), 1.3, 16, ["#d0b0ff", "#ffffff"], (0.02, 0.045), seed=8, z=(-0.8, 0.9))
        yaw, elev = 0.0, 0.0
    elif kind == "Elim_LeafPile":
        lib.blob((0, 0, 0), (1.5, 1.5, 0.85), pbr("leafpile", "#d2541f", 0.8, sss=0.2), seed=3, amp=0.15, freq=1.8)
        for _ in range(150):
            a, rr = rng.uniform(0, 6.3), 1.5 * math.sqrt(rng.random())
            z = 0.85 * math.sqrt(max(0, 1 - (rr / 1.5) ** 2)) + 0.02
            H.leaf((math.cos(a) * rr, math.sin(a) * rr, z), rng.uniform(0.36, 0.5),
                   (rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5), rng.uniform(0, 6.3)), rng=rng)
        for k in range(26):
            a = rng.uniform(0, 2 * math.pi)
            r = rng.uniform(0.1, 1.2)
            z = 0.95 + rng.uniform(0, 1.5) * (1.25 - r * 0.5)
            H.leaf((math.cos(a) * r, math.sin(a) * r * 0.5, z), rng.uniform(0.3, 0.42),
                   (rng.uniform(0, 6), rng.uniform(0, 6), rng.uniform(0, 6)), rng=rng)
        elev = 0.1
    elif kind == "Elim_LanternSnuff":
        g = group((0, 0, 0.55), (0, 0, 0.35), 1.1)
        ir = H.iron()
        obj(rbox((0.7, 0.7, 0.12), 0.04), (0, 0, 0.5), 1, m=ir, parent=g)
        obj(rbox((0.6, 0.6, 0.1), 0.03), (0, 0, -0.45), 1, m=ir, parent=g)
        obj("cone6", (0, 0, 0.66), (0.42, 0.42, 0.16), m=ir, parent=g)
        torus((0, 0, 0.9), 0.14, 0.03, ir, (math.pi / 2, 0, 0), g)
        for sx in (-1, 1):
            for sy in (-1, 1):
                obj("cube", (sx * 0.3, sy * 0.3, 0.02), (0.03, 0.03, 0.46), m=ir, parent=g)
        obj("cube", (0, 0, 0.02), (0.28, 0.28, 0.44), m=pbr("darkglass", "#3a3046", 0.1, trans=0.7), parent=g)
        obj("cyl", (0, 0, -0.2), (0.03, 0.03, 0.12), m=pbr("wick", "#2a2020", 0.9), parent=g)
        obj("sphere", (0, 0, -0.07), 0.035, m=glow(H.EMBER, 18), parent=g)
        smoke = [Vector((0.35 * math.sin(t * 9) * t, 0.15 * math.cos(t * 7) * t, 1.55 + t * 1.6)) for t in
                 [k / 60 for k in range(61)]]
        tube(smoke, lambda t: 0.05 + 0.16 * t, lambda t: (*col("#b8aec8"), 0.55 * (1 - t) ** 0.8 * min(1, t * 8)),
             vmat("smoke", 0.6), seg=12)
        elev = 0.15
    elif kind == "Victory_Bonfire":
        for k in range(10):
            a = k * 2 * math.pi / 10
            obj("sphere", (math.cos(a) * 1.1, math.sin(a) * 1.1, 0.12), (0.26, 0.22, 0.18), m=pbr("rock", "#5a5466", 0.9))
        for k in range(3):
            obj("cyl", (0, 0, 0.18), (0.08, 0.08, 0.8), (math.pi / 2, 0, k * math.pi / 3), H.bark())
        for k in range(7):
            a = k * 2 * math.pi / 7
            flame((math.cos(a) * 0.45, math.sin(a) * 0.45, 0.15), rng.uniform(1.2, 2.0), 0.3, k)
        flame((0, 0, 0.1), 2.4, 0.42, 9)
        lib.point_light((0, -0.6, 1.0), H.AMBER, 600, 0.5)
        sparks((0, 0, 1.6), 1.2, 40, [H.AMBER, H.EMBER, "#fff1c2", H.GOLDLEAF], (0.025, 0.06), seed=10, z=(0, 1.6),
               strength=16)
        elev = 0.22
    elif kind == "Victory_HarvestRain":
        basket = group((0, 0, 0), (0, 0, 0.3), 1)
        wick = pbr("wicker", "#b07a3a", 0.85, sheen=0.4)
        obj("cyl", (0, 0, 0.35), (0.8, 0.8, 0.35), m=wick, parent=basket)
        torus((0, 0, 0.7), 0.82, 0.07, pbr("wicker2", "#8a5a2a", 0.85), parent=basket)
        obj("cyl", (0, 0, 0.66), (0.74, 0.74, 0.02), m=pbr("fruitbed", "#6a3a1e", 0.9), parent=basket)
        for k in range(5):
            apple((rng.uniform(-0.4, 0.4), rng.uniform(-0.3, 0.3), 0.8), 1.0)
        for k in range(24):
            p = (rng.uniform(-1.3, 1.3), rng.uniform(-0.5, 0.5), rng.uniform(1.1, 2.9))
            pick = k % 3
            if pick == 0:
                H.leaf(p, rng.uniform(0.35, 0.5), (rng.uniform(0, 6), rng.uniform(0, 6), rng.uniform(0, 6)), rng=rng)
            elif pick == 1:
                acorn(p, 1.4)
            else:
                apple(p, 0.9)
        elev = 0.18
    elif kind == "Victory_Moonrise":
        H.moon((0, 0.8, 1.05), 1.05)
        hill = lib.blob((0, -0.2, -1.0), (2.6, 1.0, 1.1), pbr("hill", "#120a1a", 0.9), seed=4, amp=0.08)
        hill.name = "hill"
        for k in range(7):
            obj("ico", (rng.uniform(-1.6, 1.6), 0.9, rng.uniform(1.4, 2.6)), 0.03, m=glow("#ffffff", 20))
        flier((-0.55, -0.6, 1.25), 0.9, "owl", 0.12)
        flier((0.85, -0.7, 1.95), 0.6, "owl", -0.2)
        lib.point_light((0, -1.2, 1.2), "#ffcf7a", 200, 1.0)
        yaw, elev = 0.0, 0.05
    else:
        raise SystemExit(f"art.py: no icon called {kind}")

    bpy.context.view_layer.update()
    # A pet's glowing ring underneath is for the lobby: the icon is the pet alone.
    halo = {"Pet_HarvestOwl": -1.85, "Pet_EmberStag": -1.25, "Pet_Gourdian": -1.05, "Pet_ToadstoolTot": -0.95,
            "Pet_LanternWisp": -1.2}.get(kind)
    if halo is not None:
        for o in list(scene.objects):
            if o.type == "MESH" and o.data.name.startswith("torus") and abs(o.matrix_world.translation.z - halo) < 0.05:
                bpy.data.objects.remove(o)

    def spark(o) -> bool:
        material = o.active_material.name if o.active_material else ""
        return material.startswith("glow") and max(o.dimensions) < 0.25

    # Warm studio light round the subject, framed to fill the square (the sparkles may poke out).
    lo, hi = Vector((1e9, 1e9, 1e9)), Vector((-1e9, -1e9, -1e9))
    for o in scene.objects:
        if o.type in ("MESH", "FONT", "CURVE") and o.name != "hill" and not spark(o):
            # The mesh's own points (a turned object's bounding box is bigger than what's drawn).
            points = [v.co for v in o.data.vertices] if o.type == "MESH" else [Vector(c) for c in o.bound_box]
            for point in points:
                p = o.matrix_world @ point
                lo = Vector((min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)))
                hi = Vector((max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)))
    center = (lo + hi) / 2
    view = Vector((math.sin(yaw) * math.cos(elev), -math.cos(yaw) * math.cos(elev), math.sin(elev)))
    right = view.cross(Vector((0, 0, 1))).normalized() * -1
    up = right.cross(view).normalized() * -1
    half, near = 0.0, 0.0
    for x in (lo.x, hi.x):
        for y in (lo.y, hi.y):
            for z in (lo.z, hi.z):
                d = Vector((x, y, z)) - center
                half = max(half, abs(d.dot(right)), abs(d.dot(up)))
                near = max(near, d.dot(view))
    half *= 1.06
    distance = half / math.tan(math.radians(fov) / 2) + near
    eye = center + view * distance
    lib.cam(tuple(eye), tuple(center), fov)
    size = max(half, 0.5)
    k = (distance / 10) ** 2
    lib.area_light(tuple(center + view * distance * 0.9 + right * -size * 2.2 + up * size * 2.4), tuple(center),
                   "#fff0dc", 1300 * k, size * 3)
    lib.area_light(tuple(center - view * size * 3 + right * size * 3 + up * size), tuple(center), "#ff7a3a",
                   1100 * k, size * 2)
    lib.area_light(tuple(center - view * size * 3 - right * size * 3 + up * size * 0.6), tuple(center), "#9a6aff",
                   900 * k, size * 2)
    lib.area_light(tuple(center + view * distance * 0.8 + right * size * 2 - up * size), tuple(center), "#ffd9b8",
                   300 * k, size * 3)
    standard_view(scene)
    lib.render(out, RENDER, RENDER, 64)


def standard_view(scene):
    """Standard, not AgX: the glows keep their colour (AgX washes bright embers out to white). The
    builders' glows are made for AgX, so they're turned down to stay orange rather than clip to
    yellow-white here."""
    import bpy

    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        for node in m.node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED":
                strength = node.inputs["Emission Strength"]
                if strength.default_value > 1.0:
                    strength.default_value = 1.0 + (strength.default_value - 1.0) * 0.12
            elif node.type == "EMISSION":
                node.inputs["Strength"].default_value *= 0.3
            elif node.type == "MATH" and node.operation == "MULTIPLY":
                node.inputs[1].default_value = min(node.inputs[1].default_value, 1.6)
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = -0.2


def blender_pack(name: str, out: Path):
    """A pack icon's keys (transparent): one, a fan of three or five, a heap, or keys and a banner."""
    import bpy
    from mathutils import Vector

    sys.path.insert(0, str(HERE))
    import blender_lib as lib
    import hollow_night as H
    from blender_lib import glow, group, obj, pbr, sparks, tube

    bpy.ops.wm.read_factory_settings(use_empty=True)
    lib.studio_world("#140a22", "#2a1430", 0.35)
    scene = bpy.context.scene
    scene.render.film_transparent = True
    # A fan of keys like a hand of cards, their lantern bows spread along the bottom (more for a bigger
    # pack), each in the icon's 3/4 turn.
    count = {"Keys1": 1, "Keys5": 2, "Keys15": 3, "Keys40": 4, "Starter": 2}[name]
    for k in range(count):
        spread = k - (count - 1) / 2
        fan = group((-0.8 + spread * 0.32, -0.12 * k, -0.7 - abs(spread) * 0.06), (0, math.radians(-spread * 24), 0), 1)
        H.key((0, 0, 0), (math.radians(20), math.radians(-42), math.radians(25)), 1.45, fan)
    iron = bpy.data.materials.get("hollow_iron")
    if iron:
        iron.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*lib.col("#7a7290"), 1)
    if name == "Starter":
        pole = [Vector((1.7, 0.3, -1.4)), Vector((1.7, 0.3, 2.1))]
        tube(pole, lambda t: 0.05, lambda t: (1, 1, 1, 0), H.brass(), seg=10)
        flag = group((1.7, 0.3, 2.05), (0, 0, 0), 1.2)
        stripes = ["#c8322a", "#ff8a2a", "#ffd04a"]
        for i, c in enumerate(stripes):
            path = [Vector((-0.02 - t * 1.4, 0, -i * 0.28 + 0.12 * math.sin(t * 5))) for t in [j / 24 for j in range(25)]]
            lib.ribbon(path, lambda u: 0.28 * (1 - 0.35 * u), lambda u, v, c=c: (*lib.col(c), 1.0),
                       lib.vsolid(f"banner{c}", 0.6), side=(0, 0, 1), parent=flag)
        H.emblem_leaf((-0.65, -0.05, -0.28), (0, 0, 0), 0.6, glow(H.GOLDLEAF, 6), flag)
        obj("sphere", (1.7, 0.3, 2.15), 0.1, m=H.brass())
    sparks((0, 0, 0.3), 1.8, 22, [H.AMBER, "#fff1c2", H.GOLDLEAF], (0.025, 0.06), seed=3, z=(-0.8, 1.2))
    bpy.context.view_layer.update()
    lib.cam((0.3, -10.5, 0.9), (0.35 if name == "Starter" else 0.25, 0, 0.35), 30)
    lib.area_light((-3, -6, 5), (0, 0, 0), "#fff0dc", 1300, 4)
    lib.area_light((4, 3, 3), (0, 0, 0), "#ff7a3a", 1000, 3)
    lib.area_light((-4, 3, 2), (0, 0, 0), "#9a6aff", 800, 3)
    standard_view(scene)
    lib.render(out, 512, 512, 64)


# =================================================================================================
# The rest (plain Python): numpy and Pillow.

def build_title(out: Path):
    """THE HARVESTER's icon, drawn flat (a blackletter capital reads best straight on): its "H" in Grenze
    Gotisch, lit from inside (pale gold at the top to ember at the bottom), a crescent moon either side
    the way the name tag has them, and embers rising."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter, ImageFont

    n = RENDER
    font = ImageFont.truetype(str(FONTS / "GrenzeGotisch.ttf"), int(n * 0.72))
    mask = Image.new("L", (n, n), 0)
    draw = ImageDraw.Draw(mask)
    box = draw.textbbox((0, 0), "H", font=font)
    x = (n - (box[2] - box[0])) / 2 - box[0]
    y = (n - (box[3] - box[1])) / 2 - box[1] + n * 0.02
    draw.text((x, y), "H", font=font, fill=255)
    letter = np.asarray(mask).astype(np.float32) / 255
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    top, bottom = (box[1] + y) , (box[3] + y)
    t = np.clip((yy - top) / max(1, bottom - top), 0, 1)[..., None]
    pale, gold, ember = (np.array(c, np.float32) / 255 for c in ((255, 244, 190), (255, 196, 70), (255, 100, 30)))
    fill = np.where(t < 0.5, pale + (gold - pale) * (t / 0.5), gold + (ember - gold) * ((t - 0.5) / 0.5))
    # Its dark outline.
    outline = np.asarray(mask.filter(ImageFilter.MaxFilter(9))).astype(np.float32) / 255
    # The moons: a disc less a shifted disc, either side, opening toward the letter.
    moons = np.zeros((n, n), np.float32)
    for side in (-1, 1):
        cx, cy, r = n / 2 + side * n * 0.36, n * 0.5, n * 0.13
        outer = np.hypot(xx - cx, yy - cy) < r
        inner = np.hypot(xx - (cx - side * r * 0.55), yy - (cy - r * 0.18)) < r * 0.86
        moons = np.maximum(moons, (outer & ~inner).astype(np.float32))
    moons = np.asarray(Image.fromarray((moons * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))).astype(
        np.float32) / 255
    moon_rgb = np.array([255, 214, 120], np.float32) / 255
    # Layers: outline, moons, the letter.
    rgb = np.zeros((n, n, 3), np.float32) + np.array([60, 18, 8], np.float32) / 255
    alpha = outline * 0.9
    for layer_rgb, layer_a in ((np.broadcast_to(moon_rgb, (n, n, 3)), moons), (fill, letter)):
        a = layer_a[..., None]
        new_a = a[..., 0] + alpha * (1 - a[..., 0])
        rgb = (layer_rgb * a + rgb * alpha[..., None] * (1 - a)) / np.maximum(new_a[..., None], 1e-4)
        alpha = new_a
    image = Image.fromarray((np.dstack([np.clip(rgb, 0, 1), np.clip(alpha, 0, 1)]) * 255).astype(np.uint8), "RGBA")
    # Embers rising off it.
    sparks = ImageDraw.Draw(image)
    rng = random.Random(9)
    for _ in range(22):
        ex, ey = rng.uniform(n * 0.2, n * 0.8), rng.uniform(n * 0.05, n * 0.35)
        er = rng.uniform(2, 5)
        color = rng.choice([(255, 200, 90, 255), (255, 140, 50, 255), (255, 240, 200, 255)])
        sparks.ellipse((ex - er, ey - er, ex + er, ey + er), fill=color)
    out.parent.mkdir(parents=True, exist_ok=True)
    image.save(out)
    print(f"drew {out.name}")


def run_blender(mode: str, name: str, out: Path):
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(".part.png")
    result = subprocess.run([BPY, str(Path(__file__).resolve()), "--blender", mode, name, str(tmp)],
                            capture_output=True, text=True)
    if result.returncode != 0 or not tmp.exists():
        sys.stderr.write(result.stdout[-3000:] + result.stderr[-3000:])
        raise SystemExit(f"art.py: Blender failed on {name}")
    tmp.replace(out)
    print(f"rendered {out.relative_to(ROOT)}")


def finish_icon(path: Path):
    """A render made icon-ready: shrunk to its cell, a soft glow round the lit parts, a dark rim."""
    import numpy as np
    from PIL import Image, ImageFilter

    im = Image.open(path).convert("RGBA")
    a = np.asarray(im).astype(np.float32) / 255
    rgb, alpha = a[..., :3], a[..., 3:4]
    lum = (rgb * alpha).max(axis=2)
    bright = np.clip((lum - 0.72) / 0.28, 0, 1)
    glow_src = Image.fromarray((np.dstack([rgb * bright[..., None], bright]) * 255).astype(np.uint8), "RGBA")
    halo = np.asarray(glow_src.filter(ImageFilter.GaussianBlur(RENDER / 40))).astype(np.float32) / 255
    halo_a = np.clip(halo[..., 3:4] * 1.4, 0, 0.75)
    halo_rgb = np.where(halo_a > 0, halo[..., :3] / np.maximum(halo[..., 3:4], 1e-4), 0)
    # The rim: the shape grown a few pixels, in dusk plum, under everything.
    grown = Image.fromarray((alpha[..., 0] * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(7))
    grown = grown.filter(ImageFilter.GaussianBlur(2))
    rim_a = np.asarray(grown).astype(np.float32)[..., None] / 255 * 0.7
    rim_rgb = np.ones_like(rgb) * np.array([28, 15, 46], np.float32) / 255
    # Layers bottom to top: rim, halo, the render.
    out_rgb, out_a = rim_rgb, rim_a
    for layer_rgb, layer_a in ((halo_rgb, halo_a), (rgb, alpha)):
        new_a = layer_a + out_a * (1 - layer_a)
        out_rgb = (layer_rgb * layer_a + out_rgb * out_a * (1 - layer_a)) / np.maximum(new_a, 1e-4)
        out_a = new_a
    merged = Image.fromarray((np.dstack([np.clip(out_rgb, 0, 1), np.clip(out_a, 0, 1)]) * 255).astype(np.uint8), "RGBA")
    cell = np.asarray(merged.resize((CELL, CELL), Image.LANCZOS)).copy()
    # A clear margin all round, so a cell drawn from the sheet never picks up its neighbour's edge.
    margin = 3
    cell[:margin, :, 3] = 0
    cell[-margin:, :, 3] = 0
    cell[:, :margin, 3] = 0
    cell[:, -margin:, 3] = 0
    return Image.fromarray(cell, "RGBA")


def build_sheet():
    from PIL import Image

    sheet = Image.new("RGBA", (CELL * COLUMNS, CELL * COLUMNS), (0, 0, 0, 0))
    for index, name in enumerate(ICONS):
        cell = finish_icon(CELLS / f"{name}.png")
        sheet.alpha_composite(cell, ((index % COLUMNS) * CELL, (index // COLUMNS) * CELL))
    OUT.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT / "icons.png", optimize=True)
    print(f"wrote {(OUT / 'icons.png').relative_to(ROOT)}")


def leaf_outline(kind: str, t: float) -> float:
    """The leaf's radius at angle t (0 at the tip, which points up), about 0 to 1."""
    if kind == "maple":
        r = 0.42
        for center, amp, width in ((0, 0.55, 0.3), (60, 0.45, 0.28), (-60, 0.45, 0.28), (115, 0.2, 0.25),
                                   (-115, 0.2, 0.25)):
            d = math.atan2(math.sin(t - math.radians(center)), math.cos(t - math.radians(center)))
            r += amp * math.exp(-(d / width) ** 2)
        r += 0.05 * max(0, math.cos(18 * t)) ** 3
        if abs(math.atan2(math.sin(t - math.pi), math.cos(t - math.pi))) < 0.25:
            r *= 0.6
        return r
    base = 1.0 / math.sqrt((math.sin(t) / {"oak": 0.5, "birch": 0.62, "elm": 0.42}[kind]) ** 2 + math.cos(t) ** 2)
    if kind == "oak":
        # Rounded lobes down each side, wider at the top.
        base *= 0.86 + 0.16 * math.cos(t) + 0.14 * abs(math.sin(5.5 * t))
    elif kind == "birch":
        base *= 0.92 + 0.08 * math.cos(t) + 0.03 * max(0, math.cos(26 * t))
        base *= 1 - 0.18 * max(0, -math.cos(t)) ** 3
    else:  # elm: narrow, toothed, a pointed tip
        base *= 0.9 + 0.12 * max(0, math.cos(t)) ** 6 + 0.035 * max(0, math.cos(34 * t))
    return base * 0.95


def build_leaves():
    """Four leaves, white: soft light from the top left, a darker middle rib and side veins."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter

    size = 256 * 4  # drawn big, then shrunk
    sheet = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    for index, kind in enumerate(["maple", "oak", "birch", "elm"]):
        mask = Image.new("L", (size, size), 0)
        draw = ImageDraw.Draw(mask)
        cx, cy, scale = size / 2, size * 0.47, size * 0.4
        points = []
        for i in range(720):
            t = 2 * math.pi * i / 720
            r = leaf_outline(kind, t) * scale
            points.append((cx + math.sin(t) * r, cy - math.cos(t) * r))
        draw.polygon(points, fill=255)
        # The stem.
        draw.line([(cx, cy + scale * 0.35), (cx + scale * 0.06, cy + scale * 0.95)], fill=255, width=int(size * 0.025))
        m = np.asarray(mask).astype(np.float32) / 255
        yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
        # Soft shading: a gentle dome lit from the top left, darker toward the edges.
        edge = np.asarray(mask.filter(ImageFilter.GaussianBlur(size * 0.03))).astype(np.float32) / 255
        light = 0.82 + 0.18 * np.clip(((cx - xx) * 0.6 + (cy - yy) * 0.8) / scale, -1, 1)
        shade = np.clip(light * (0.7 + 0.3 * edge), 0, 1)
        # Veins: the midrib and side veins, a little darker.
        veins = Image.new("L", (size, size), 0)
        vd = ImageDraw.Draw(veins)
        tip = (cx, cy - scale * (0.95 if kind != "maple" else 0.9))
        vd.line([(cx, cy + scale * 0.35), tip], fill=255, width=int(size * 0.012))
        count = 5 if kind == "maple" else 6
        for k in range(1, count + 1):
            f = k / (count + 1)
            y0 = cy + scale * 0.3 - f * scale * 1.15
            for side in (-1, 1):
                if kind == "maple":
                    a = math.radians(side * (25 + 30 * (k % 3)))
                    length = scale * (0.75 - 0.08 * k)
                    end = (cx + math.sin(a) * length, cy + scale * 0.2 - math.cos(a) * length)
                    vd.line([(cx, cy + scale * 0.2), end], fill=200, width=int(size * 0.008))
                else:
                    end = (cx + side * scale * 0.48 * (1 - abs(f - 0.45)), y0 - scale * 0.18)
                    vd.line([(cx, y0), end], fill=170, width=int(size * 0.006))
        v = np.asarray(veins.filter(ImageFilter.GaussianBlur(size * 0.003))).astype(np.float32) / 255
        value = np.clip(shade - v * 0.28, 0, 1)
        rgba = np.dstack([value, value, value, m])
        leaf = Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").resize((256, 256), Image.LANCZOS)
        sheet.alpha_composite(leaf, ((index % 2) * 256, (index // 2) * 256))
    sheet.save(OUT / "leaves.png", optimize=True)
    print(f"wrote {(OUT / 'leaves.png').relative_to(ROOT)}")


def build_ember():
    import numpy as np
    from PIL import Image

    n = 128
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    r = np.hypot(xx - (n - 1) / 2, yy - (n - 1) / 2) / (n / 2)
    alpha = np.clip(np.exp(-(r / 0.42) ** 2) * 1.15 + np.exp(-(r / 0.16) ** 2) * 0.6, 0, 1) * (r < 1)
    rgba = np.dstack([np.ones_like(r), np.ones_like(r), np.ones_like(r), alpha])
    Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(OUT / "ember.png", optimize=True)
    print(f"wrote {(OUT / 'ember.png').relative_to(ROOT)}")


def build_moon():
    """A crescent moon, warm gold, lit from inside, a faint glow round it, opening to the right."""
    import numpy as np
    from PIL import Image, ImageFilter

    n = 256 * 3
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    c = n / 2
    outer = np.hypot(xx - c, yy - c) < n * 0.4
    inner = np.hypot(xx - (c + n * 0.17), yy - (c - n * 0.06)) < n * 0.33
    shape = (outer & ~inner).astype(np.float32)
    mask = Image.fromarray((shape * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5))
    m = np.asarray(mask).astype(np.float32) / 255
    # Gold toward the outer edge, a paler glow inside, a few soft craters.
    d = np.hypot(xx - c, yy - c) / (n * 0.4)
    gold = np.array([255, 196, 92], np.float32) / 255
    pale = np.array([255, 240, 196], np.float32) / 255
    k = np.clip((d - 0.55) / 0.45, 0, 1)[..., None]
    rgb = pale * (1 - k) + gold * k
    rng = np.random.default_rng(3)
    for _ in range(6):
        px, py, pr = c + rng.uniform(-0.35, -0.05) * n, c + rng.uniform(-0.3, 0.3) * n, rng.uniform(0.02, 0.05) * n
        crater = np.exp(-((np.hypot(xx - px, yy - py) / pr) ** 2))[..., None]
        rgb = rgb + (np.array([236, 150, 64], np.float32) / 255 - rgb) * 0.35 * crater
    glow = np.asarray(mask.filter(ImageFilter.GaussianBlur(n * 0.04))).astype(np.float32) / 255 * 0.55
    alpha = np.maximum(m, glow)
    glow_rgb = np.array([255, 170, 70], np.float32) / 255
    blend = (m / np.maximum(alpha, 1e-4))[..., None]
    out = rgb * blend + glow_rgb * (1 - blend)
    rgba = np.dstack([np.clip(out, 0, 1), alpha])
    Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").resize((256, 256), Image.LANCZOS).save(
        OUT / "moon.png", optimize=True)
    print(f"wrote {(OUT / 'moon.png').relative_to(ROOT)}")


def build_pack(name: str):
    """A key pack's product icon: dusk plum, an ember glow, the keys, and the count."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter, ImageFont

    n = 512
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    r = np.hypot(xx - n * 0.45, yy - n * 0.42) / n
    deep = np.array([28, 15, 46], np.float32) / 255
    panel = np.array([84, 34, 66], np.float32) / 255
    ember = np.array([255, 120, 40], np.float32) / 255
    base = deep + (panel - deep) * np.clip(1 - r * 1.6, 0, 1)[..., None]
    base = base + ember * (np.exp(-(r / 0.28) ** 2) * 0.45)[..., None]
    bg = Image.fromarray((np.clip(base, 0, 1) * 255).astype(np.uint8), "RGB").convert("RGBA")
    keys = Image.open(CELLS / f"pack_{name}.png").convert("RGBA")
    bg.alpha_composite(keys.resize((n, n), Image.LANCZOS))
    draw = ImageDraw.Draw(bg)
    label = "STARTER" if name == "Starter" else f"x{PACKS[name]}"
    font = ImageFont.truetype(str(FONTS / "LuckiestGuy.ttf"), 92 if name == "Starter" else 150)
    box = draw.textbbox((0, 0), label, font=font, stroke_width=10)
    x = n - (box[2] - box[0]) - 28 if name != "Starter" else (n - (box[2] - box[0])) / 2
    y = n - (box[3] - box[1]) - 30
    shadow = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text((x + 6, y + 8), label, font=font, fill=(10, 4, 16, 200), stroke_width=10,
                                stroke_fill=(10, 4, 16, 200))
    bg.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(6)))
    draw.text((x, y), label, font=font, fill=(255, 214, 92), stroke_width=10, stroke_fill=(70, 20, 10))
    (OUT / "packs").mkdir(parents=True, exist_ok=True)
    bg.convert("RGB").save(OUT / "packs" / f"{name}.png", optimize=True)
    print(f"wrote {(OUT / 'packs' / f'{name}.png').relative_to(ROOT)}")


UPLOADS = {"Icons": "icons.png", "Leaves": "leaves.png", "Ember": "ember.png", "Moon": "moon.png"}
SEASON_ART = ROOT / "src" / "shared" / "SeasonArt.luau"


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
        decal = upload(path, "Decal", f"Party Panic Hollow Night {key}"[:50],
                       f"Party Panic: Hollow Night's {key.lower()} image (the first crate season).",
                       {"userId": user}, "image/png")
        image = image_in(decal)
        opened, errors = open_use([image])
        granted, grant_errors = grant([image, decal])
        print(f"{file}: decal {decal}, image {image}; Open Use {image in opened}, game use {image in granted}")
        if errors or grant_errors:
            print(f"  permission errors: {json.dumps(errors + grant_errors)[:600]}")
        record[key] = {"sha": digest, "decal": decal, "image": image}
        record_path.write_text(json.dumps(record, indent=2) + "\n")
    write_season_art(record)


def write_season_art(record: dict):
    """Fills SeasonArt.luau's ids and icon cells (the rest of the file stays as it is)."""
    import re

    text = SEASON_ART.read_text()
    for key in UPLOADS:
        image = record.get(key, {}).get("image")
        if image:
            text = re.sub(rf'(\n\t{key} = )"[^"]*"', rf'\g<1>"rbxassetid://{image}"', text)
    text = re.sub(r"(\n\tIconSize = )\d+", rf"\g<1>{CELL}", text)
    cells = "\n".join(f"\t\t{name} = {{ {i % COLUMNS}, {i // COLUMNS} }}," for i, name in enumerate(ICONS))
    text = re.sub(r"\n\tIconCells = \{.*?\} :: \{ \[string\]: \{ number \} \},[^\n]*",
                  "\n\tIconCells = {\n" + cells.replace("\\", "\\\\") + "\n\t} :: { [string]: { number } }, -- id -> { column, row } (from 0)",
                  text, flags=re.S)
    SEASON_ART.write_text(text)
    print(f"wrote {SEASON_ART.relative_to(ROOT)}")


def main():
    if "--upload" in sys.argv:
        upload_all()
        return
    if "--blender" in sys.argv:
        i = sys.argv.index("--blender")
        mode, name, out = sys.argv[i + 1], sys.argv[i + 2], Path(sys.argv[i + 3])
        if mode == "icon":
            blender_scene(name, out)
        else:
            blender_pack(name, out)
        return
    redo = set()
    if "--redo" in sys.argv:
        redo = set(sys.argv[sys.argv.index("--redo") + 1].split(","))
    force = "--force" in sys.argv
    CELLS.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    for name in ICONS:
        path = CELLS / f"{name}.png"
        if name == "Title_Harvester":
            build_title(path)  # (drawn, not rendered: quick, so always)
        elif force or name in redo or not path.exists():
            run_blender("icon", name, path)
    for name in PACKS:
        path = CELLS / f"pack_{name}.png"
        if force or name in redo or not path.exists():
            run_blender("pack", name, path)
    build_sheet()
    build_leaves()
    build_ember()
    build_moon()
    for name in PACKS:
        build_pack(name)


if __name__ == "__main__":
    main()
