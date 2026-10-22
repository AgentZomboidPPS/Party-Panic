"""Meshes for Struggle (see tools/meshgen/props/README.md). Units are studs, +Y up, base on y = 0,
-Z is the front. Generate with:
    python3 tools/meshgen/generate_meshes.py --only StruggleBat,StruggleFence,StruggleScoreboard,StruggleTram,StruggleTrack,StruggleBench,StruggleBanner,StruggleReach,StruggleOrbBall,StruggleOrbCube,StruggleOrbPyramid,StruggleOrbDiamond,StruggleOrbStar,StruggleOrbRing,StruggleOrbPlus,StruggleOrbCross,StruggleOrbCone,StruggleOrbFrame,StruggleOrbPill,StruggleOrbKite

Original designs (no Kingdom Hearts branding): a padded foam bat, twelve orb shapes (one per player,
so colour is never the only cue), and a sunset sandlot's fence, scoreboard, tram yard, benches and
banners. The fence panel is 12 studs wide (the server lays whole panels along each side) and carries
its post at its left end. The scoreboard's lit face matches SIGN in src/server/MiniGames/Struggle.luau
(15.5 x 6.2, centred 10.6 up, its front 0.55 in front of the pivot)."""

import math

from generate_meshes import capsule, cylinder, extrude, lathe, merge, rounded_box, sphere, star, torus


def box(sx, sy, sz, r, x=0.0, y=0.0, z=0.0, n=3):
    return rounded_box(sx, sy, sz, r, n).translate(x, y, z)


def cyl_x(radius, length, x=0.0, y=0.0, z=0.0, segments=20, bevel=0.0):
    return cylinder(radius, length, segments, bevel).translate(0, -length / 2, 0).rotate("z", 90).translate(x, y, z)


def cyl_y(radius, length, x=0.0, y=0.0, z=0.0, segments=16, bevel=0.0):
    return cylinder(radius, length, segments, bevel).translate(x, y, z)


def ball(radius, x=0.0, y=0.0, z=0.0, rings=10, segments=16):
    return sphere(radius, rings, segments).translate(x, y, z)


# ------------------------------------------------------------------ the bat

def bat():
    """A padded foam bat along +Y: taped grip and knob below, a fat rounded foam barrel above."""
    knob = lathe([(0.0, 0.0), (0.26, 0.02), (0.3, 0.12), (0.24, 0.24), (0.15, 0.3), (0.0, 0.3)], 20)
    grip = lathe([(0.0, 0.25), (0.16, 0.25), (0.17, 0.7), (0.17, 1.2), (0.19, 1.45), (0.0, 1.45)], 16)
    foam_profile = [(0.0, 1.35), (0.3, 1.36), (0.38, 1.6)]
    for i in range(8):
        y = 1.6 + 2.3 * i / 7
        foam_profile.append((0.38 + 0.08 * math.sin(math.pi * i / 7 * 0.9), y))
    for i in range(1, 7):
        a = math.pi / 2 * i / 6
        foam_profile.append((0.43 * math.cos(a), 3.9 + 0.36 * math.sin(a)))
    foam = lathe(foam_profile, 24)
    band = torus(0.37, 0.08, 24, 8).translate(0, 1.62, 0)
    stripe = torus(0.455, 0.05, 24, 8).translate(0, 3.25, 0)
    return {"Grip": merge(knob, grip), "Foam": foam, "Band": merge(band, stripe)}


# ------------------------------------------------------------------ orbs (about 1.6 studs, face -Z)

def orb_ball():
    return {"Orb": sphere(0.8, 14, 22).translate(0, 0.8, 0)}


def orb_cube():
    return {"Orb": box(1.3, 1.3, 1.3, 0.22, 0, 0.65, 0, 4)}


def faceted(mesh):
    mesh.smooth = False
    return mesh


def orb_pyramid():
    return {"Orb": faceted(lathe([(0.0, 0.0), (0.95, 0.0), (0.0, 1.5)], 4).rotate("y", 45))}


def orb_diamond():
    return {"Orb": faceted(lathe([(0.0, 0.0), (0.75, 0.8), (0.0, 1.6)], 4).rotate("y", 45))}


def orb_star():
    return {"Orb": extrude(star(0.85, 0.38, 5), 0.45).translate(0, 0.8, 0)}


def orb_ring():
    return {"Orb": torus(0.58, 0.2, 28, 10).rotate("x", 90).translate(0, 0.78, 0)}


def plus_outline(arm, half):
    return [(half, half), (half, arm), (-half, arm), (-half, half), (-arm, half), (-arm, -half),
            (-half, -half), (-half, -arm), (half, -arm), (half, -half), (arm, -half), (arm, half)]


def orb_plus():
    return {"Orb": extrude(plus_outline(0.8, 0.26), 0.45).translate(0, 0.8, 0)}


def orb_cross():
    return {"Orb": extrude(plus_outline(0.85, 0.24), 0.45).rotate("z", 45).translate(0, 0.8, 0)}


def orb_cone():
    """A cone standing on its point."""
    return {"Orb": lathe([(0.0, 0.0), (0.82, 1.35), (0.7, 1.5), (0.0, 1.5)], 24)}


def square_frame(outer, bar, depth):
    half = outer / 2
    inner = half - bar / 2
    return merge(
        box(outer, bar, depth, 0.08, 0, inner, 0, 2),
        box(outer, bar, depth, 0.08, 0, -inner, 0, 2),
        box(bar, outer - 2 * bar + 0.02, depth, 0.08, inner, 0, 0, 2),
        box(bar, outer - 2 * bar + 0.02, depth, 0.08, -inner, 0, 0, 2),
    )


def orb_frame():
    return {"Orb": square_frame(1.35, 0.34, 0.45).translate(0, 0.68, 0)}


def orb_pill():
    return {"Orb": capsule(1.8, 0.42, 20).rotate("z", 90).translate(0, 0.42, 0)}


def orb_kite():
    return {"Orb": square_frame(1.1, 0.3, 0.45).rotate("z", 45).translate(0, 0.78, 0)}


# ------------------------------------------------------------------ the sandlot

def fence():
    """One 12-stud panel of a plank fence, too tall to jump (about 10 studs; a jump reaches 7.2):
    pointed boards in front, three rails behind, the post at the left end (x = -6)."""
    boards = []
    count = 13
    width = 12.0 / count
    for i in range(count):
        x = -6 + width * (i + 0.5)
        w = width - 0.1
        top = 9.8 + 0.12 * ((i * 7) % 3)
        outline = [(-w / 2, 0.25), (w / 2, 0.25), (w / 2, top - 0.4), (0, top), (-w / 2, top - 0.4)]
        boards.append(extrude(outline, 0.26).translate(x, 0, -0.05))
    rails = merge(*[box(12.0, 0.45, 0.36, 0.08, 0, y, 0.3) for y in (1.6, 5.0, 8.4)])
    post = merge(box(0.8, 10.3, 0.8, 0.12, -6, 5.15, 0.15), box(1.0, 0.25, 1.0, 0.08, -6, 10.38, 0.15))
    return {"Boards": merge(*boards), "Rails": rails, "Post": post}


def reach():
    """The swing's reach on the sand: a flat fan of radius 1 spanning 80 degrees each side of -Z (the
    rule's ARC), its point at the swinger. The client scales it to the swing's RANGE."""
    points = [(0.0, 0.0)]
    for i in range(25):
        a = math.radians(-80 + 160 * i / 24)
        points.append((math.sin(a), math.cos(a)))
    return {"Fan": extrude(points, 0.02).rotate("x", -90).translate(0, 0.01, 0)}


def scoreboard():
    """A wooden scoreboard on two legs, its dark face toward -Z (the field), little bulbs on top."""
    legs = merge(box(0.9, 14.0, 0.9, 0.15, -8.2, 7.0, 0.3), box(0.9, 14.0, 0.9, 0.15, 8.2, 7.0, 0.3))
    frame = merge(
        box(18.4, 8.4, 0.8, 0.25, 0, 10.6, 0.15),
        box(19.2, 0.5, 1.3, 0.12, 0, 15.0, 0.15),
        box(7.0, 1.6, 0.6, 0.2, 0, 16.1, 0.15),
    )
    face = box(15.5, 6.2, 0.1, 0.03, 0, 10.6, -0.3)
    plaque = box(6.2, 1.1, 0.12, 0.05, 0, 16.1, -0.2)
    bulbs = merge(*[ball(0.22, -8.4 + 1.4 * i, 15.45, -0.2, 6, 10) for i in range(13)])
    return {"Legs": legs, "Frame": frame, "Face": face, "Plaque": plaque, "Bulbs": bulbs}


def tram():
    """A little two-ended tram, 22 long (along Z), on two bogies, a pantograph on the roof."""
    body = box(6.2, 6.4, 20.0, 0.9, 0, 5.4, 0, 4)
    stripe = merge(box(6.32, 0.5, 19.6, 0.2, 0, 3.6, 0), box(6.32, 0.3, 19.6, 0.12, 0, 8.25, 0))
    windows = []
    for side in (-1, 1):
        for i in range(6):
            z = -7.5 + 3.0 * i
            windows.append(box(0.12, 2.3, 2.3, 0.25, side * 3.11, 6.3, z, 2))
    for end in (-1, 1):
        windows.append(box(4.4, 2.4, 0.12, 0.3, 0, 6.4, end * 10.02, 2))
    roof = merge(box(5.4, 0.6, 19.0, 0.3, 0, 8.75, 0), box(2.4, 0.5, 4.0, 0.2, 0, 9.3, 0))
    bogies = []
    for z in (-6.5, 6.5):
        bogies.append(box(4.6, 1.0, 4.6, 0.2, 0, 1.55, z))
        for wz in (-1.4, 1.4):
            bogies.append(cyl_x(0.85, 5.0, 0, 0.95, z + wz, 20))
    panto = merge(
        cyl_x(0.08, 3.6, 0, 11.1, 0, 8),
        box(0.12, 1.8, 0.12, 0.04, 0, 10.2, -0.6),
        box(0.12, 1.8, 0.12, 0.04, 0, 10.2, 0.6),
    )
    lamps = merge(*[ball(0.35, x, 3.0, end * 10.05, 6, 10) for x in (-2.1, 2.1) for end in (-1, 1)])
    return {
        "Body": body,
        "Stripe": stripe,
        "Windows": merge(*windows),
        "Roof": roof,
        "Bogies": merge(*bogies),
        "Pantograph": panto,
        "Lamps": lamps,
    }


def track():
    """40 studs of track along Z: a gravel bed, sleepers, two rails."""
    ballast = extrude([(-4.2, 0.0), (4.2, 0.0), (3.4, 0.45), (-3.4, 0.45)], 40.0)
    sleepers = merge(*[box(6.4, 0.3, 0.8, 0.06, 0, 0.6, -19 + 2.0 * i, 2) for i in range(20)])
    rails = merge(box(0.3, 0.4, 40.0, 0.06, -2.4, 0.95, 0, 2), box(0.3, 0.4, 40.0, 0.06, 2.4, 0.95, 0, 2))
    return {"Ballast": ballast, "Sleepers": sleepers, "Rails": rails}


def bench():
    """A slatted wooden bench with a back rest on iron legs, seat toward -Z."""
    seat = merge(*[box(8.0, 0.25, 0.5, 0.08, 0, 1.75, -0.6 + 0.6 * i, 2) for i in range(3)])
    back = merge(*[box(8.0, 0.5, 0.2, 0.08, 0, 2.6 + 0.65 * i, 0.95, 2) for i in range(2)])
    legs = []
    for x in (-3.5, 3.5):
        legs += [
            box(0.25, 1.7, 0.25, 0.06, x, 0.85, -0.6),
            box(0.25, 3.7, 0.25, 0.06, x, 1.85, 1.1),
            box(0.25, 0.25, 1.9, 0.06, x, 1.55, 0.25),
        ]
    return {"Seat": seat, "Back": back, "Legs": merge(*legs)}


def banner():
    """A pole with a swallowtail banner hanging from a crossbar, a star emblem on the cloth."""
    pole = merge(cyl_y(0.18, 12.0), cyl_x(0.1, 4.2, 0, 11.3, -0.05, 10))
    finial = ball(0.32, 0, 12.25, 0, 8, 12)
    cloth = extrude([(-1.9, 0.0), (1.9, 0.0), (1.9, -6.4), (0.0, -5.0), (-1.9, -6.4)], 0.12).translate(0, 11.2, -0.2)
    emblem = extrude(star(1.05, 0.45, 5), 0.06).translate(0, 8.4, -0.29)
    return {"Pole": pole, "Finial": finial, "Cloth": cloth, "Emblem": emblem}


PROPS = {
    "StruggleBat": bat,
    "StruggleOrbBall": orb_ball,
    "StruggleOrbCube": orb_cube,
    "StruggleOrbPyramid": orb_pyramid,
    "StruggleOrbDiamond": orb_diamond,
    "StruggleOrbStar": orb_star,
    "StruggleOrbRing": orb_ring,
    "StruggleOrbPlus": orb_plus,
    "StruggleOrbCross": orb_cross,
    "StruggleOrbCone": orb_cone,
    "StruggleOrbFrame": orb_frame,
    "StruggleOrbPill": orb_pill,
    "StruggleOrbKite": orb_kite,
    "StruggleFence": fence,
    "StruggleReach": reach,
    "StruggleScoreboard": scoreboard,
    "StruggleTram": tram,
    "StruggleTrack": track,
    "StruggleBench": bench,
    "StruggleBanner": banner,
}
COLORS = {
    "Grip": (40, 40, 48),
    "Foam": (255, 120, 60),
    "Band": (250, 250, 250),
    "Orb": (120, 220, 255),
    "Fan": (255, 255, 255),
    "Boards": (196, 146, 96),
    "Rails": (150, 104, 66),
    "Post": (120, 84, 56),
    "Legs": (110, 78, 52),
    "Frame": (130, 92, 60),
    "Face": (34, 60, 48),
    "Plaque": (240, 200, 90),
    "Bulbs": (255, 235, 150),
    "Body": (210, 80, 60),
    "Stripe": (245, 230, 200),
    "Windows": (40, 60, 80),
    "Roof": (170, 170, 175),
    "Bogies": (50, 50, 55),
    "Pantograph": (60, 60, 64),
    "Lamps": (255, 240, 180),
    "Ballast": (120, 110, 100),
    "Sleepers": (100, 72, 50),
    "Seat": (190, 130, 80),
    "Back": (190, 130, 80),
    "Pole": (230, 230, 230),
    "Finial": (240, 200, 80),
    "Cloth": (240, 160, 50),
    "Emblem": (255, 250, 235),
}
