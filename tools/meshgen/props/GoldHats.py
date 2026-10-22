"""The GOLD PASS's hats (owner: "Also we do need a paid battle pass too. I like the current free one.
But the paid one should also be insane."): five hats on the gold lane of the Rewards Road
(src/shared/GoldPass.luau), worn like the PUMPKIN HAT (src/server/World/Hats.luau puts each on as an
Accessory; src/server/World/Props/GoldHats.luau colours the pieces).

  * GoldPartyHat (level 10): a gold party cone wound with two pink spiral stripes, a white rolled
    trim round its base and a fluffy white pompom on its tip.
  * RoyalCrown (level 25, a showstopper): a gold band rising into eight points (tall and short in
    turn) with a pearl on each, rubies and sapphires set round the band, a puffed red velvet cap
    inside, and a gold orb and cross on top.
  * GoldenHalo (level 40): a glowing gold ring that floats above the head.
  * GildedTopHat (level 60): a black silk top hat with a curled brim, a gold band and a gold buckle.
  * SunKingCrown (level 100, the last showstopper): a gold circlet with twelve sun rays fanning up and
    out, long and short in turn, a big glowing gem in front and a glowing bead on each long ray.

Built from the shared primitives (lathe, torus, taper, extrude...), not sculpted, so they need no
simplifying and stay a few thousand triangles each. A wall with corners (a band's rim) is made of
strips that meet without sharing vertices, so it shades smooth along the ring and crisp at the edge.

Units are studs at the size each is worn on a standard 1.2-stud head (World/Hats scales it to each
head); +Y is up, the base sits on y = 0 and -Z is the front.
"""

import math

import numpy as np
from generate_meshes import Mesh, extrude, icosphere, lathe, merge, rounded_box, sphere, taper, torus

TAU = 2 * math.pi


def ring_strips(segments, rows):
    """A closed band of quads round the Y axis, one strip per pair of neighbouring rows. `rows` lists
    (radius, height) functions of the angle; each strip has vertices of its own, so the shading is
    smooth round the ring and sharp where two strips meet."""
    pieces = []
    for (ra, ya), (rb, yb) in zip(rows, rows[1:]):
        verts, faces = [], []
        for i in range(segments):
            a = TAU * i / segments
            verts.append((math.cos(a) * ra(a), ya(a), math.sin(a) * ra(a)))
            verts.append((math.cos(a) * rb(a), yb(a), math.sin(a) * rb(a)))
        for i in range(segments):
            j = (i + 1) % segments
            a0, b0, a1, b1 = 2 * i, 2 * i + 1, 2 * j, 2 * j + 1
            faces += [(a0, b0, a1), (a1, b0, b1)]
        pieces.append(Mesh(verts, faces))
    return merge(*pieces)


def const(value):
    return lambda _a: value


def shell(r_in, r_out, y0, top, segments=128):
    """A closed ring wall from y0 up to top(angle): bottom, outside, top edge and inside."""
    return ring_strips(
        segments,
        [(const(r_in), const(y0)), (const(r_out), const(y0)), (const(r_out), top), (const(r_in), top), (const(r_in), const(y0))],
    )


def facing(mesh, angle, radius, y):
    """Turns a piece made facing -Z (at the origin) to face out from the Y axis at `angle`, `radius`
    out and `y` up."""
    mesh.translate(0, y, -radius)
    # Mesh.rotate("y", d) takes (0, 0, -r) to (-r sin d, 0, -r cos d): d = -(angle + 90 degrees) puts
    # it at (r cos, r sin) of the ring's angle, facing out.
    return mesh.rotate("y", -(math.degrees(angle) + 90))


def ellipsoid(radii, rings=10, segments=16):
    mesh = sphere(1.0, rings, segments)
    return mesh.scale(*radii)


# ---------------------------------------------------------------- the party hat

PARTY_R, PARTY_H = 0.4, 1.0


def party_hat():
    cone = lathe([(0.0, 0.0), (PARTY_R, 0.0), (0.0, PARTY_H)], 40)
    stripes = []
    for phase in (0.0, math.pi):
        points = []
        for k in range(73):
            t = k / 72
            y = 0.06 + t * 0.82
            r = PARTY_R * (1 - y / PARTY_H) + 0.012
            a = phase + 2.6 * TAU * t
            points.append((math.cos(a) * r, y, math.sin(a) * r))
        stripes.append(taper(points, 0.034, 0.016, 8))
    trim = torus(PARTY_R + 0.005, 0.048, 40, 10).translate(0, 0.048, 0)
    pom = icosphere(0.115, 2, noise=0.28, seed=7).translate(0, PARTY_H + 0.06, 0)
    return {"PartyGold": cone, "PartyStripe": merge(*stripes), "PartyTrim": merge(trim, pom)}


# ---------------------------------------------------------------- the royal crown

CROWN_IN, CROWN_OUT = 0.455, 0.5
CROWN_BAND = 0.22
CROWN_POINTS = 8
FRONT = -math.pi / 2  # the angle of the front (-Z)


def crown_point(a):
    """Which point of the crown's rim angle `a` is under (0 is the tall one at the front), and how
    far across it (0.5 is its tip)."""
    t = (a - FRONT) / TAU * CROWN_POINTS + 0.5
    return math.floor(t) % CROWN_POINTS, t % 1.0


def crown_top(a):
    """The band's top edge: eight points with curved sides, tall and short in turn."""
    k, u = crown_point(a)
    tall = 0.32 if k % 2 == 0 else 0.22
    peak = (1 - abs(2 * u - 1)) ** 2.2
    return CROWN_BAND + tall * peak


def royal_crown():
    band = shell(CROWN_IN, CROWN_OUT, 0.0, crown_top, 192)
    rim = torus(CROWN_OUT + 0.004, 0.03, 64, 10).translate(0, 0.03, 0)
    velvet = lathe(
        [(0.0, 0.08), (0.452, 0.08), (0.45, 0.2), (0.43, 0.33), (0.37, 0.46), (0.27, 0.56), (0.14, 0.62), (0.0, 0.64)],
        40,
    )
    orb = sphere(0.075, 12, 18).translate(0, 0.7, 0)
    cross = merge(
        rounded_box(0.05, 0.2, 0.05, 0.018, 3).translate(0, 0.86, 0),
        rounded_box(0.15, 0.05, 0.05, 0.018, 3).translate(0, 0.89, 0),
    )
    pearls, rubies, sapphires = [], [], []
    for k in range(CROWN_POINTS):
        a = FRONT + TAU * k / CROWN_POINTS  # point k's tip
        mid = (CROWN_IN + CROWN_OUT) / 2
        tip = crown_top(a)
        pearls.append(sphere(0.045, 8, 12).translate(math.cos(a) * mid, tip + 0.03, math.sin(a) * mid))
        gem = ellipsoid((0.05, 0.062, 0.03), 8, 12)
        (rubies if k % 2 == 0 else sapphires).append(facing(gem, a, CROWN_OUT + 0.012, 0.13))
    return {
        "CrownGold": merge(band, rim, orb, cross),
        "CrownVelvet": velvet,
        "CrownPearl": merge(*pearls),
        "CrownRuby": merge(*rubies),
        "CrownSapphire": merge(*sapphires),
    }


# ---------------------------------------------------------------- the halo

def golden_halo():
    ring = torus(0.42, 0.066, 56, 14).translate(0, 0.066, 0)
    return {"HaloRing": ring}


# ---------------------------------------------------------------- the top hat

def top_hat():
    body = lathe(
        [
            (0.0, 0.0),
            (0.58, 0.0),
            (0.63, 0.012),
            (0.655, 0.04),
            (0.645, 0.066),
            (0.6, 0.06),
            (0.42, 0.052),
            (0.355, 0.06),
            (0.35, 0.3),
            (0.358, 0.62),
            (0.372, 0.8),
            (0.366, 0.82),
            (0.0, 0.825),
        ],
        48,
    )
    band = shell(0.352, 0.37, 0.062, const(0.2), 96)
    # The buckle: a rounded square frame on the front of the band.
    frame = merge(
        rounded_box(0.17, 0.035, 0.03, 0.012, 3).translate(0, 0.205, 0),
        rounded_box(0.17, 0.035, 0.03, 0.012, 3).translate(0, 0.055, 0),
        rounded_box(0.035, 0.18, 0.03, 0.012, 3).translate(-0.0675, 0.13, 0),
        rounded_box(0.035, 0.18, 0.03, 0.012, 3).translate(0.0675, 0.13, 0),
        rounded_box(0.02, 0.12, 0.022, 0.008, 3).translate(0, 0.13, -0.006),
    )
    buckle = facing(frame, -math.pi / 2, 0.385, 0.0)
    return {"TopHatBody": body, "TopHatBand": band, "TopHatBuckle": buckle}


# ---------------------------------------------------------------- the sun king's crown

SUN_IN, SUN_OUT = 0.455, 0.5
SUN_BAND = 0.2
SUN_RAYS = 12


def ray(length, width):
    """A flat, pointed sun ray standing up from the band, made facing -Z (at the origin)."""
    outline = [(-width / 2, 0.0), (width / 2, 0.0), (width * 0.22, length * 0.62), (0.0, length), (-width * 0.22, length * 0.62)]
    blade = extrude(outline, 0.05)
    blade.smooth = False
    return blade


def sun_king_crown():
    band = shell(SUN_IN, SUN_OUT, 0.0, const(SUN_BAND), 128)
    rays, beads = [], []
    for k in range(SUN_RAYS):
        a = TAU * k / SUN_RAYS - math.pi / 2  # the first long ray is at the front
        long = k % 2 == 0
        length = 0.56 if long else 0.34
        blade = ray(length, 0.2 if long else 0.15)
        blade.rotate("x", -24 if long else -30)  # leaning out
        blade.translate(0, SUN_BAND - 0.08, 0)
        rays.append(facing(blade, a, SUN_OUT - 0.035, 0.0))
        if long:
            lean = math.radians(24)
            tip_r = SUN_OUT - 0.035 + math.sin(lean) * length
            tip_y = SUN_BAND - 0.08 + math.cos(lean) * length
            beads.append(sphere(0.042, 8, 12).translate(math.cos(a) * tip_r, tip_y + 0.02, math.sin(a) * tip_r))
    rims = merge(
        torus(SUN_OUT + 0.004, 0.028, 64, 10).translate(0, 0.028, 0),
        torus(SUN_OUT - 0.004, 0.024, 64, 10).translate(0, SUN_BAND - 0.01, 0),
    )
    gem = icosphere(1.0, 1)
    gem.scale(0.1, 0.13, 0.055)
    gem = facing(gem, -math.pi / 2, SUN_OUT + 0.03, 0.13)
    return {"SunGold": merge(band, *rays), "SunRim": rims, "SunGem": merge(gem, *beads)}


PROPS = {
    "GoldPartyHat": party_hat,
    "RoyalCrown": royal_crown,
    "GoldenHalo": golden_halo,
    "GildedTopHat": top_hat,
    "SunKingCrown": sun_king_crown,
}

# Preview colours only; the game colours pieces by name (src/server/World/Props/GoldHats.luau).
COLORS = {
    "PartyGold": (255, 200, 50),
    "PartyStripe": (255, 92, 170),
    "PartyTrim": (255, 252, 240),
    "CrownGold": (255, 196, 40),
    "CrownVelvet": (190, 24, 52),
    "CrownPearl": (250, 246, 236),
    "CrownRuby": (255, 40, 80),
    "CrownSapphire": (60, 120, 255),
    "HaloRing": (255, 214, 90),
    "TopHatBody": (30, 26, 36),
    "TopHatBand": (255, 196, 40),
    "TopHatBuckle": (255, 236, 150),
    "SunGold": (255, 200, 40),
    "SunRim": (214, 128, 18),
    "SunGem": (255, 246, 190),
}
