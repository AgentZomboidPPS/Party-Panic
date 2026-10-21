"""Arcade props for the lobby's Skee-Ball corner (owner: "Can we also add skiball to the lobby?"): the
machine, its ball, the ticket floor and path, and the TODAY'S BEST board over the machines.
Matching specs: src/server/World/Props/Arcade.luau. The arcade is placed by
src/server/World/Arcade.luau.

    python3 tools/meshgen/generate_meshes.py --only ArcadeSkeeMachine,ArcadeSkeeBall

The machine is built from the numbers in src/shared/Logic/SkeeBall.luau (the ball's path), so the
lane, the hop and the rings the ball follows are the ones you see: change them there.
Units are studs, +Y is up, the base sits on y = 0 and -Z is the front (the player's side). Names
start with "Arcade" so they never clash with another set of props.
"""

import math
import re
from pathlib import Path

import numpy as np
from generate_meshes import Mesh, capsule, cylinder, extrude, icosphere, lathe, merge, rounded_box, star, torus, tube

ROOT = Path(__file__).resolve().parents[3]
TAU = 2 * math.pi


def _logic() -> dict:
    """The numbers in src/shared/Logic/SkeeBall.luau: `SkeeBall.NAME = number` and the rings."""
    text = (ROOT / "src" / "shared" / "Logic" / "SkeeBall.luau").read_text()
    values = {name: float(value) for name, value in re.findall(r"^SkeeBall\.(\w+) = (-?\d+(?:\.\d+)?)\b", text, re.M)}
    values["RINGS"] = [(int(points), float(radius)) for points, radius in re.findall(r"\{ Points = (\d+), R = ([\d.]+) \}", text)]
    return values


K = _logic()
R = K["BALL_R"]
SIN, COS = K["BOARD_SIN"], K["BOARD_COS"]
RADII = {points: radius for points, radius in K["RINGS"]}
LANE_HALF, BOX_HALF = K["LANE_HALF"], K["BOARD_HALF"]
SIDE = K["HALF_WIDTH"] - 0.1  # the cabinet's side faces (the base sticks out a little further)
FRONT = K["FRONT_Z"]
BACK = -FRONT
PLINTH = 0.3  # the base's height


def Z(s: float) -> float:
    """Prop z of a point s along the lane."""
    return K["RELEASE_Z"] + s


def floor_y(s: float) -> float:
    """The lane floor's height (SkeeBall.FloorY)."""
    if s <= K["HOP_S"]:
        return K["LANE_Y"] + s * K["LANE_RISE"]
    length = K["LIP_S"] - K["HOP_S"]
    x = min(max(s - K["HOP_S"], 0.0), length)
    y0 = K["LANE_Y"] + K["HOP_S"] * K["LANE_RISE"]
    curve = (K["LIP_Y"] - y0 - K["LANE_RISE"] * length) / (length * length)
    return y0 + K["LANE_RISE"] * x + curve * x * x


def rail_y(s: float) -> float:
    """The top of the lane's side rails (they climb with the lane)."""
    return K["LANE_Y"] + 0.9 + s * K["LANE_RISE"]


BOARD_TOP_W = K["BOARD_LEN"]
Z_LANE0, Z_HOP, Z_LIP = Z(K["LANE_START"]), Z(K["HOP_S"]), Z(K["LIP_S"])
Z_BOARD = Z(K["BOARD_S"])
Z_BOARD_TOP = Z_BOARD + BOARD_TOP_W * COS
Y_BOARD_TOP = K["BOARD_Y"] + BOARD_TOP_W * SIN
Z_BACKSTOP = Z(K["BACK_S"])
WALL_TOP = 6.0  # the target box's side walls; the cage stands on them


# ====================================================================== helpers

def outward(mesh: Mesh, centers) -> Mesh:
    """Turns each face to point away from its center point (the solid's middle, for convex pieces)."""
    tri = mesh.v[mesh.f]
    normal = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    away = tri.mean(axis=1) - np.asarray(centers, dtype=float)
    flip = np.einsum("ij,ij->i", normal, away) < 0
    mesh.f = mesh.f.copy()
    mesh.f[flip] = mesh.f[flip][:, ::-1]
    return mesh


def cube(sx: float, sy: float, sz: float) -> Mesh:
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    verts = [(x * hx, y * hy, z * hz) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
    faces = [(0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5), (0, 4, 5), (0, 5, 1),
             (2, 3, 7), (2, 7, 6), (0, 2, 6), (0, 6, 4), (1, 5, 7), (1, 7, 3)]
    return outward(Mesh(verts, faces, smooth=False), (0.0, 0.0, 0.0))


def box(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, r: float = 0.0, n: int = 3) -> Mesh:
    """A box from its bounds, its edges rounded by r."""
    sx, sy, sz = x1 - x0, y1 - y0, z1 - z0
    mesh = rounded_box(sx, sy, sz, r, n) if r > 0 else cube(sx, sy, sz)
    return mesh.translate((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)


def prism_x(points, x0: float, x1: float) -> Mesh:
    """A solid from a convex outline in the side view (z, y), filling x0..x1."""
    n = len(points)
    cz = sum(p[0] for p in points) / n
    cy = sum(p[1] for p in points) / n
    verts = [(x0, cy, cz), (x1, cy, cz)] + [(x0, y, z) for z, y in points] + [(x1, y, z) for z, y in points]
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces += [(0, 2 + j, 2 + i), (1, 2 + n + i, 2 + n + j), (2 + i, 2 + j, 2 + n + j), (2 + i, 2 + n + j, 2 + n + i)]
    return outward(Mesh(verts, faces, smooth=False), ((x0 + x1) / 2, cy, cz))


def sweep(sections) -> Mesh:
    """A solid through cross-sections (closed convex loops of 3D points, all the same length), capped."""
    rows, n = len(sections), len(sections[0])
    middles = [np.mean(np.array(section, dtype=float), axis=0) for section in sections]
    verts = [tuple(p) for section in sections for p in section]
    faces, centers = [], []
    for r in range(rows - 1):
        middle = (middles[r] + middles[r + 1]) / 2
        for i in range(n):
            j = (i + 1) % n
            a, b = r * n + i, r * n + j
            faces += [(a, b, b + n), (a, b + n, a + n)]
            centers += [middle, middle]
    for r in (0, rows - 1):
        center = len(verts)
        verts.append(tuple(middles[r]))
        # Each cap looks away from the next section in.
        inside = middles[1] if r == 0 else middles[rows - 2]
        for i in range(n):
            j = (i + 1) % n
            faces.append((center, r * n + i, r * n + j))
            centers.append(inside)
    return outward(Mesh(verts, faces, smooth=False), np.array(centers))


def on_board(mesh: Mesh) -> Mesh:
    """Lays a mesh built in the ring board's own frame (x across, y out of the board, z up its slope
    from the bottom edge) onto the tilted board."""
    x, ly, lw = mesh.v[:, 0].copy(), mesh.v[:, 1].copy(), mesh.v[:, 2].copy()
    mesh.v = np.stack([x, K["BOARD_Y"] + lw * SIN + ly * COS, Z_BOARD + lw * COS - ly * SIN], axis=1)
    return mesh


def flat_ring(r0: float, r1: float, y0: float, y1: float, segments: int = 64) -> Mesh:
    """A flat ring (closed), round the Y axis."""
    mesh = lathe([(r0, y0), (r1, y0), (r1, y1), (r0, y1), (r0, y0)], segments)
    mesh.smooth = False
    return mesh


def disc(radius: float, y0: float, y1: float, segments: int = 32) -> Mesh:
    return cylinder(radius, y1 - y0, segments).translate(0, y0, 0)


def surround(r_in: float, half: float, length: float, center_w: float, y0: float, y1: float, n: int = 96) -> Mesh:
    """In the board frame: the board's slab from its edges in to a round hole of r_in centered at
    w = center_w (a closed solid; rays from the hole's center meet each edge once)."""
    corners = [math.atan2(w - center_w, x) for x in (-half, half) for w in (0.0, length)]
    angles = sorted(set([round(a, 9) for a in np.linspace(-math.pi, math.pi, n, endpoint=False)] + [round(a, 9) for a in corners]))
    verts, faces = [], []
    for a in angles:
        dx, dw = math.cos(a), math.sin(a)
        hits = []
        if abs(dx) > 1e-9:
            hits.append(half / abs(dx))
        if dw > 1e-9:
            hits.append((length - center_w) / dw)
        elif dw < -1e-9:
            hits.append(-center_w / dw)
        t = min(hits)
        inner = (r_in * dx, r_in * dw + center_w)
        outer = (t * dx, t * dw + center_w)
        verts += [(inner[0], y1, inner[1]), (outer[0], y1, outer[1]), (inner[0], y0, inner[1]), (outer[0], y0, outer[1])]
    m = len(angles)
    for i in range(m):
        j = (i + 1) % m
        a, b = 4 * i, 4 * j
        faces += [(a, b, b + 1), (a, b + 1, a + 1)]  # top
        faces += [(a + 2, a + 3, b + 3), (a + 2, b + 3, b + 2)]  # bottom
        faces += [(a, a + 2, b + 2), (a, b + 2, b)]  # the hole's wall
        faces += [(a + 1, b + 1, b + 3), (a + 1, b + 3, a + 3)]  # the outer edge
    return Mesh(verts, faces, smooth=False)


def bulb(x: float, y: float, z: float, radius: float = 0.13) -> Mesh:
    return icosphere(radius, 1).translate(x, y, z)


def star_plate(radius: float, depth: float) -> Mesh:
    """A five-pointed star in the XY plane, centered on z = 0."""
    return extrude(star(radius, radius * 0.45), depth)


def mirror_x(mesh: Mesh) -> Mesh:
    """The same mesh on the other side (x -> -x); its faces are turned back outward later."""
    copy = mesh.copy()
    copy.v = copy.v * np.array([-1.0, 1.0, 1.0])
    copy.f = copy.f[:, ::-1].copy()
    return copy


def recenter(pieces: dict, name: str) -> dict:
    """Prints how far the bounding box's center is from the local origin, and its size (the game
    places a prop by the bottom center of its box)."""
    allv = np.vstack([m.v for m in pieces.values()])
    lo, hi = allv.min(axis=0), allv.max(axis=0)
    print(f"  {name}: box center x {(lo[0] + hi[0]) / 2:+.3f} z {(lo[2] + hi[2]) / 2:+.3f}, "
          f"y {lo[1]:.3f}..{hi[1]:.3f}, size {hi[0] - lo[0]:.2f} x {hi[1] - lo[1]:.2f} x {hi[2] - lo[2]:.2f}")
    return pieces


# ====================================================================== the machine

def machine_cabinet():
    """The body (side cabinets along the lane, the target box's walls, front and back panels), its
    gold trim, the chute the balls wait in, and the stripes and stars on its sides."""
    body, trim, stripes, stars, chute, dark, glow = [], [], [], [], [], [], []
    s_front, s_lip = K["LANE_START"], K["LIP_S"]
    z0 = FRONT + 0.1
    for side in (-1, 1):
        # Neon strips along the inside edges of the rails and the box's walls.
        x = side * (LANE_HALF + 0.02)
        glow.append(tube([(x, rail_y(s_front - 0.7) + 0.19, z0 + 0.25), (x, rail_y(s_lip) + 0.19, Z_LIP)], 0.055, 8))
        xb = side * (BOX_HALF + 0.02)
        glow.append(tube([(xb, rail_y(s_lip) + 0.19, Z_LIP + 0.05), (xb, WALL_TOP + 0.19, Z_LIP + 1.12),
                          (xb, WALL_TOP + 0.19, BACK - 0.35)], 0.055, 8))
        # Along the lane: from the front panel to the hop's lip, as tall as the rails.
        rail = [(z0, PLINTH), (Z_LIP, PLINTH), (Z_LIP, rail_y(s_lip)), (z0, rail_y(s_front - 0.7))]
        lane_side = prism_x(rail, LANE_HALF + 0.02, SIDE)
        # The target box's wall, with a sloped front edge up from the rail.
        wall = [(Z_LIP, PLINTH), (BACK - 0.1, PLINTH), (BACK - 0.1, WALL_TOP), (Z_LIP + 1.1, WALL_TOP), (Z_LIP, rail_y(s_lip))]
        box_side = prism_x(wall, BOX_HALF + 0.02, SIDE)
        cap = prism_x([(z0 - 0.05, rail_y(s_front - 0.7)), (Z_LIP + 0.02, rail_y(s_lip)),
                       (Z_LIP + 0.02, rail_y(s_lip) + 0.14), (z0 - 0.05, rail_y(s_front - 0.7) + 0.14)],
                      LANE_HALF - 0.08, SIDE + 0.08)
        wall_cap = box(BOX_HALF - 0.06, SIDE + 0.08, WALL_TOP, WALL_TOP + 0.14, Z_LIP + 1.05, BACK - 0.05)
        slope_cap = prism_x([(Z_LIP - 0.02, rail_y(s_lip)), (Z_LIP + 1.1, WALL_TOP), (Z_LIP + 1.1, WALL_TOP + 0.14),
                             (Z_LIP - 0.02, rail_y(s_lip) + 0.14)], BOX_HALF - 0.06, SIDE + 0.08)
        if side < 0:
            lane_side, box_side, cap, wall_cap, slope_cap = (mirror_x(m) for m in (lane_side, box_side, cap, wall_cap, slope_cap))
        body += [lane_side, box_side]
        trim += [cap, wall_cap, slope_cap]
        # A racing stripe down each side along the rail, and stars on the box's walls.
        x = side * (SIDE + 0.02)
        band = prism_x([(z0 + 0.4, rail_y(s_front) - 0.75), (Z_LIP + 0.6, rail_y(s_lip) - 0.75),
                        (Z_LIP + 0.6, rail_y(s_lip) - 0.4), (z0 + 0.4, rail_y(s_front) - 0.4)], -0.03, 0.03)
        stripes.append(band.translate(x, 0, 0))
        for z, y, size in ((3.6, 3.7, 0.7), (5.4, 4.7, 0.5), (6.4, 3.3, 0.38)):
            stars.append(star_plate(size, 0.06).rotate("y", 90).translate(x, y, z))
    # The front panel, its bumper and a coin door with a big star (nothing sticks out past FRONT).
    body.append(box(-SIDE, SIDE, PLINTH, 2.62, FRONT + 0.2, Z_LANE0 + 0.02, 0.12))
    trim.append(capsule(2 * SIDE + 0.1, 0.17, 16).rotate("z", 90).translate(0, 2.66, FRONT + 0.4))
    trim.append(box(-0.75, 0.75, 0.75, 1.75, FRONT + 0.08, FRONT + 0.24, 0.07))
    dark.append(box(-0.32, 0.32, 1.32, 1.48, FRONT + 0.02, FRONT + 0.12, 0.04))
    stars.append(star_plate(0.36, 0.06).translate(0, 1.04, FRONT + 0.06))
    stripes.append(box(-SIDE + 0.25, SIDE - 0.25, 2.12, 2.36, FRONT + 0.12, FRONT + 0.22))
    # The back panel behind the backstop, up to the screen.
    body.append(box(-SIDE, SIDE, PLINTH, 9.15, Z_BACKSTOP, BACK - 0.1, 0.1))
    # The chute along the right-hand rail (x < 0) where the balls wait, the next one at the front.
    cx = K["CHUTE_X"]
    z_first = K["CHUTE_Z"]
    z_last = z_first + 8 * K["CHUTE_STEP"] + 0.55

    def chute_y(z: float) -> float:
        return K["CHUTE_Y"] + (z - z_first) * K["CHUTE_RISE"]

    for dx in (-0.4, 0.4):
        chute.append(tube([(cx + dx, chute_y(z) - 0.1, z) for z in (z0 - 0.02, z_last)], 0.075, 8))
    for z in np.linspace(z0 + 0.25, z_last - 0.2, 6):
        chute.append(tube([(cx - 0.4, chute_y(z) - 0.1, z), (cx - 0.4, chute_y(z) - R - 0.05, z),
                           (cx + 0.4, chute_y(z) - R - 0.05, z), (cx + 0.4, chute_y(z) - 0.1, z)], 0.045, 6))
    dark.append(prism_x([(z0, chute_y(z0) - R - 0.04), (z_last, chute_y(z_last) - R - 0.04),
                         (z_last, chute_y(z_last) - R + 0.02), (z0, chute_y(z0) - R + 0.02)], cx - 0.36, cx + 0.36))
    trim.append(box(cx - 0.5, cx + 0.5, chute_y(z0) - 0.45, chute_y(z0) + 0.15, z0 - 0.1, z0 + 0.1, 0.05))
    base = box(-K["HALF_WIDTH"], K["HALF_WIDTH"], 0.0, PLINTH + 0.02, FRONT, BACK, 0.1)
    return body, trim, stripes, stars, chute, dark, base, glow


def machine_lane():
    """The maple lane up to the hop, the red hop itself, and the aiming arrows on the lane."""
    half = LANE_HALF + 0.04

    def section(s: float, top: float):
        z = Z(s)
        return [(-half, 1.6, z), (half, 1.6, z), (half, top, z), (-half, top, z)]

    lane = sweep([section(s, floor_y(s)) for s in np.linspace(K["LANE_START"], K["HOP_S"], 4)])
    hop = sweep([section(s, floor_y(s)) for s in np.linspace(K["HOP_S"], K["LIP_S"], 8)])
    arrows = []
    slope = math.degrees(math.atan(K["LANE_RISE"]))
    for u, s in ((0.0, 3.6), (-0.55, 3.25), (0.55, 3.25), (-1.1, 2.9), (1.1, 2.9)):
        arrow = extrude([(0.0, 0.32), (0.2, -0.2), (0.0, -0.08), (-0.2, -0.2)], 0.05)
        arrow = arrow.rotate("x", 90)  # lie flat, pointing up the lane (+z)
        arrows.append(arrow.rotate("x", -slope).translate(-u, floor_y(s) + 0.02, Z(s)))
    for u in (-0.9, -0.45, 0.0, 0.45, 0.9):
        arrows.append(cylinder(0.07, 0.05, 10).translate(-u, floor_y(1.2) + 0.0, Z(1.2)))
    return lane, hop, arrows


def machine_target():
    """The ring board (bands round the middle, white lips, holes), the 100 cups, the gutters, the
    backstop and the cage over it all."""
    pieces = {}
    rings = K["RINGS"]
    center = K["RING_W"]
    radii = [radius for _, radius in rings]
    # The board's slab and its top outside the 10 ring (the bands fill the rest, no overlaps).
    slab = on_board(box(-BOX_HALF - 0.02, BOX_HALF + 0.02, -0.5, -0.12, -0.25, BOARD_TOP_W))
    top = on_board(surround(radii[-1], BOX_HALF, BOARD_TOP_W, center, -0.12, 0.0))
    pieces["Board"] = merge(slab, top)
    inner = 0.0
    for points, radius in rings:
        band = flat_ring(inner, radius, -0.12, 0.0, 72) if inner > 0 else disc(radius, -0.12, 0.0, 40)
        pieces[f"Band{points}"] = on_board(band.translate(0, 0, center))
        inner = radius
    lips = [on_board(torus(radius, 0.055, 72, 8).translate(0, 0.03, center)) for radius in radii]
    # Holes: each ring's drain at the bottom of its channel (one above the other up the middle).
    holes = []
    inner = 0.0
    for index, radius in enumerate(radii):
        w = center if index == 0 else center - (inner + radius) / 2
        holes.append(on_board(disc(0.15 if index > 0 else 0.2, 0.0, 0.05, 20).translate(0, 0, w)))
        inner = radius
    # The 100 cups in the top corners: a gold rim, a gold dish and a dark hole.
    cup_rims = []
    for name, x in (("Cup100L", K["CUP_U"]), ("Cup100R", -K["CUP_U"])):  # x = -u: the player's left is +x
        dish = disc(K["CUP_R"] + 0.08, 0.0, 0.05, 32).translate(x, 0, K["CUP_W"])
        pieces[name] = on_board(dish)
        cup_rims.append(on_board(torus(K["CUP_R"] + 0.09, 0.07, 32, 8).translate(x, 0.06, K["CUP_W"])))
        holes.append(on_board(disc(0.17, 0.05, 0.1, 20).translate(x, 0, K["CUP_W"])))
    # The gutters: the trough between the hop and the board, and the slot behind the board.
    gutter = [
        box(-BOX_HALF - 0.02, BOX_HALF + 0.02, 1.6, K["TROUGH_Y"], Z_LIP - 0.05, Z_BOARD + 0.3),
        box(-BOX_HALF - 0.02, BOX_HALF + 0.02, K["BACK_TROUGH_Y"] - 1.0, K["BACK_TROUGH_Y"], Z_BOARD_TOP - 0.2, Z_BACKSTOP + 0.02),
        box(-BOX_HALF - 0.02, BOX_HALF + 0.02, PLINTH, K["BACK_TROUGH_Y"] - 1.0, Z_BOARD_TOP - 0.2, Z_BOARD_TOP + 0.6),
    ]
    holes.append(box(-0.5, 0.5, K["TROUGH_Y"] - 0.02, K["TROUGH_Y"] + 0.03, (Z_LIP + Z_BOARD) / 2 - 0.15, (Z_LIP + Z_BOARD) / 2 + 0.15, 0.04))
    holes.append(box(-0.5, 0.5, K["BACK_TROUGH_Y"] - 0.02, K["BACK_TROUGH_Y"] + 0.03, (Z_BOARD_TOP + Z_BACKSTOP) / 2 - 0.15,
                     (Z_BOARD_TOP + Z_BACKSTOP) / 2 + 0.15, 0.04))
    # The padded backstop (the board's top edge to the cage roof).
    backstop = box(-BOX_HALF - 0.02, BOX_HALF + 0.02, K["BACK_TROUGH_Y"] - 0.05, K["TOP_Y"] + 0.05, Z_BACKSTOP - 0.0, Z_BACKSTOP + 0.3, 0.06)
    tufts = [icosphere(0.09, 1).scale(1, 1, 0.5).translate(x, y, Z_BACKSTOP - 0.01)
             for x in (-1.2, -0.4, 0.4, 1.2) for y in (5.3, 6.1, 6.9)]
    # The cage: bars up from the box walls, rails along their tops and a few across the roof.
    cage = []
    top_y = K["TOP_Y"] + 0.05
    for side in (-1, 1):
        x = side * (BOX_HALF + 0.38)
        cage.append(tube([(x, top_y, Z_LIP + 1.2), (x, top_y, Z_BACKSTOP + 0.1)], 0.07, 8))
        for z in np.linspace(Z_LIP + 1.2, Z_BACKSTOP - 0.05, 5):
            cage.append(tube([(x, WALL_TOP + 0.1, z), (x, top_y, z)], 0.05, 6))
    for z in np.linspace(Z_LIP + 1.2, Z_BACKSTOP - 0.05, 4):
        cage.append(tube([(-BOX_HALF - 0.38, top_y, z), (BOX_HALF + 0.38, top_y, z)], 0.045, 6))
    pieces.update({
        "Lips": merge(*lips),
        "Holes": merge(*holes),
        "Gutter": merge(*gutter),
        "Back": merge(backstop),
        "Tufts": merge(*tufts),
        "Cage": merge(*cage),
        "CupRims": merge(*cup_rims),
    })
    return pieces


def machine_crown():
    """The score screen's bezel above the cage, and the marquee on top: an arched sign with bulbs
    round it (two alternating sets, so the game can chase them)."""
    sy, sz, sw, sh = K["SCREEN_Y"], K["SCREEN_Z"], K["SCREEN_W"], K["SCREEN_H"]
    bezel = box(-sw / 2 - 0.25, sw / 2 + 0.25, sy - sh / 2 - 0.22, sy + sh / 2 + 0.22, sz + 0.05, BACK - 0.1, 0.12)
    x0, x1 = -sw / 2 - 0.27, sw / 2 + 0.27
    y0, y1 = sy - sh / 2 - 0.24, sy + sh / 2 + 0.24
    frame = [tube([(x0, y0, sz + 0.02), (x1, y0, sz + 0.02), (x1, y1, sz + 0.02), (x0, y1, sz + 0.02), (x0, y0, sz + 0.02)], 0.06, 6)]
    # The marquee: an arched panel whose face holds the sign, on a gold frame.
    gy, gz, gw, gh = K["SIGN_Y"], K["SIGN_Z"], K["SIGN_W"], K["SIGN_H"]
    base_y = y1 + 0.05
    half = SIDE + 0.05
    rise = 1.0
    shoulder = gy + gh / 2 - 0.15
    outline = [(-half, base_y), (half, base_y), (half, shoulder)]
    for k in range(1, 16):
        a = math.pi * k / 16
        outline.append((math.cos(a) * half, shoulder + math.sin(a) * rise))
    outline.append((-half, shoulder))
    panel = extrude([(x, y) for x, y in outline], BACK - 0.1 - gz)
    panel = panel.translate(0, 0, (BACK - 0.1 + gz) / 2)
    face = box(-gw / 2 - 0.08, gw / 2 + 0.08, gy - gh / 2 - 0.08, gy + gh / 2 + 0.08, gz - 0.06, gz + 0.02, 0.06)
    arch = [(math.cos(math.pi * k / 24) * (half + 0.02), shoulder + math.sin(math.pi * k / 24) * (rise + 0.02), gz - 0.04) for k in range(25)]
    frame.append(tube([(half + 0.02, base_y, gz - 0.04)] + arch + [(-half - 0.02, base_y, gz - 0.04)], 0.09, 8))
    frame.append(icosphere(0.24, 2).translate(0, shoulder + rise + 0.3, gz + 0.1))
    bulbs = {"BulbsA": [], "BulbsB": []}
    for k in range(13):
        a = math.pi * (k + 0.5) / 13
        x, y = math.cos(a) * (half - 0.22), shoulder + math.sin(a) * (rise - 0.2)
        bulbs["BulbsA" if k % 2 == 0 else "BulbsB"].append(bulb(x, y, gz - 0.12))
    for k, y in enumerate(np.linspace(base_y + 0.25, shoulder - 0.05, 3)):
        for side in (-1, 1):
            bulbs["BulbsB" if (k + (side > 0)) % 2 == 0 else "BulbsA"].append(bulb(side * (half - 0.22), y, gz - 0.12))
    # Bulbs along the tops of the target box's walls too.
    for side in (-1, 1):
        for k, z in enumerate(np.linspace(Z_LIP + 1.4, BACK - 0.4, 6)):
            bulbs["BulbsA" if (k + (side > 0)) % 2 == 0 else "BulbsB"].append(bulb(side * (SIDE - 0.25), WALL_TOP + 0.26, z, 0.12))
    return {
        "Display": bezel,
        "Marquee": panel,
        "Sign": face,
        "Frame": merge(*frame),
        "BulbsA": merge(*bulbs["BulbsA"]),
        "BulbsB": merge(*bulbs["BulbsB"]),
    }


def arcade_skee_machine():
    """A Skee-Ball machine, its player's side at -Z: a maple lane up to a red hop, the ring board in
    a caged target box (10 to 50 round the middle, 100 cups in the top corners), a score screen and
    a lit SKEE-BALL marquee on top, and the balls' chute along the right-hand rail. Its box is
    centered: the lane, hop and rings sit where Shared/Logic/SkeeBall says."""
    body, trim, stripes, stars, chute, dark, base, glow = machine_cabinet()
    lane, hop, arrows = machine_lane()
    target = machine_target()
    crown = machine_crown()
    pieces = {
        "Cabinet": merge(*body),
        "Base": base,
        "Glow": merge(*glow),
        "Trim": merge(*trim, target.pop("CupRims"), crown.pop("Frame")),
        "Stripes": merge(*stripes),
        "Stars": merge(*stars),
        "Chute": merge(*chute),
        "Lane": lane,
        "Hop": hop,
        "Arrows": merge(*arrows),
    }
    target["Holes"] = merge(target["Holes"], *dark)
    pieces.update(target)
    pieces.update(crown)
    return recenter(pieces, "ArcadeSkeeMachine")


def arcade_skee_ball():
    """A Skee-Ball ball with a band round it (so you can see it roll)."""
    radius = R
    ball = icosphere(radius, 3).translate(0, radius, 0)
    band = torus(radius * 0.96, radius * 0.12, 32, 8).rotate("z", 90).translate(0, radius, 0)
    return {"Ball": ball, "Band": band}


# ====================================================================== the floor and the board

# The arcade's own frame (World/Arcade.luau): the ground under the middle of the line the machines'
# fronts stand on, -Z toward the plaza. The machines stand on the tickets (y 0.4).
PATIO_W, PATIO_FRONT, PATIO_BACK = 26.0, -4.5, 16.0
WALK_HALF, WALK_START = 3.6, -27.0  # the ticket path, from the promenade's edge to the patio


def slab_xz(points, y0: float, y1: float) -> Mesh:
    """A flat solid from an outline in plan (x, z) that's star-shaped round its middle, y0..y1."""
    pts = np.array(points, dtype=float)
    n = len(pts)
    cx, cz = pts.mean(axis=0)
    verts = [(cx, y1, cz), (cx, y0, cz)] + [(x, y1, z) for x, z in pts] + [(x, y0, z) for x, z in pts]
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces += [(0, 2 + i, 2 + j), (1, 2 + n + j, 2 + n + i), (2 + i, 2 + n + i, 2 + j), (2 + j, 2 + n + i, 2 + n + j)]
    return outward(Mesh(verts, faces, smooth=False), (cx, (y0 + y1) / 2, cz))


def rounded_rect(w: float, d: float, r: float, seg: int = 6):
    """A rounded rectangle's outline in plan, centered on the origin."""
    pts = []
    for cx, cz, a0 in ((w / 2 - r, d / 2 - r, 0), (-w / 2 + r, d / 2 - r, 90), (-w / 2 + r, -d / 2 + r, 180), (w / 2 - r, -d / 2 + r, 270)):
        for k in range(seg + 1):
            a = math.radians(a0 + 90 * k / seg)
            pts.append((cx + math.cos(a) * r, cz + math.sin(a) * r))
    return pts


def ticket_outline(w: float, d: float, notch: float = 0.3, steps: int = 4):
    """An arcade ticket in plan: a rectangle with a round bite out of each corner."""
    pts = []
    for cx, cz, a0 in ((w / 2, -d / 2, 180), (w / 2, d / 2, 270), (-w / 2, d / 2, 360), (-w / 2, -d / 2, 90)):
        for k in range(steps + 1):
            a = math.radians(a0 - 90 * k / steps)
            pts.append((cx + math.cos(a) * notch, cz + math.sin(a) * notch))
    return pts


def star_xz(radius: float, y0: float, y1: float) -> Mesh:
    """A five-pointed star lying flat."""
    return slab_xz(star(radius, radius * 0.45), y0, y1)


def arcade_ticket_floor():
    """The arcade's floor: a patio paved with giant arcade tickets in three colors (white rim, blue
    band, cream grout, like the lobby's patios), and a path of tickets, each with a gold star, from
    the plaza's promenade to it. Its own frame: the ground under the middle of the machines' front
    line, -Z toward the plaza; the machines stand on the tickets (y 0.4). The rim reaches down to
    y -0.6, so it covers the lawn past the plaza's edge too."""
    pieces = {name: [] for name in ("Rim", "Band", "Grout", "TicketA", "TicketB", "TicketC", "Stars")}
    depth = PATIO_BACK - PATIO_FRONT
    mid = (PATIO_BACK + PATIO_FRONT) / 2
    pieces["Rim"].append(slab_xz(rounded_rect(PATIO_W, depth, 2.6), -0.6, 0.1).translate(0, 0, mid))
    pieces["Band"].append(slab_xz(rounded_rect(PATIO_W - 1.2, depth - 1.2, 2.2), 0.1, 0.2).translate(0, 0, mid))
    grout_w, grout_d = PATIO_W - 3.0, depth - 3.0
    pieces["Grout"].append(slab_xz(rounded_rect(grout_w, grout_d, 1.4), 0.2, 0.3).translate(0, 0, mid))
    keys = ("TicketA", "TicketB", "TicketC")
    tw, td, gap = 3.0, 1.5, 0.28
    rows = int((grout_d - 0.4) // (td + gap))
    for row in range(rows):
        z = mid - (rows - 1) * (td + gap) / 2 + row * (td + gap)
        shift = (tw + gap) / 2 * (row % 2)
        for col in range(-5, 6):
            x = col * (tw + gap) + shift
            # Only whole tickets inside the grout (its corners are rounded).
            if abs(x) + tw / 2 > grout_w / 2 - 0.25 or abs(z - mid) + td / 2 > grout_d / 2 - 0.2:
                continue
            pieces[keys[(col + row) % 3]].append(slab_xz(ticket_outline(tw, td, 0.24), 0.3, 0.4).translate(x, 0, z))
    # The ticket path, abutting the patio's rim (every layer meets its match, nothing overlaps).
    walk_len = PATIO_FRONT - WALK_START
    walk_mid = (PATIO_FRONT + WALK_START) / 2
    pieces["Rim"].append(slab_xz(rounded_rect(2 * WALK_HALF, walk_len, 0.6), 0.0, 0.3).translate(0, 0, walk_mid - 0.0))
    count = 8
    length = (walk_len - 0.6 - gap * (count - 1)) / count
    for k in range(count):
        z = WALK_START + 0.3 + length / 2 + k * (length + gap)
        pieces[keys[k % 3]].append(slab_xz(ticket_outline(2 * WALK_HALF - 1.0, length, 0.45, 5), 0.3, 0.4).translate(0, 0, z))
        pieces["Stars"].append(star_xz(0.55, 0.4, 0.45).translate(0, 0, z))
        for side in (-1, 1):  # the ticket's punched holes
            pieces["Stars"].append(cylinder(0.12, 0.05, 10).translate(side * (WALK_HALF - 1.05), 0.4, z))
    return recenter({name: merge(*meshes) for name, meshes in pieces.items()}, "ArcadeTicketFloor")


def candy_post(radius: float, height: float, turns: float):
    """A post with two stripes spiraling up it."""
    post = cylinder(radius, height, 20)
    stripes = []
    for start in (0.0, math.pi):
        helix = [(math.cos(start + turns * TAU * t) * radius, height * t, math.sin(start + turns * TAU * t) * radius)
                 for t in np.linspace(0.02, 0.98, int(turns * 24) + 2)]
        stripes.append(tube(helix, radius * 0.28, 6))
    return post, merge(*stripes)


BOARD_Y, BOARD_H, BOARD_W, POST_X = 16.0, 6.4, 24.0, 12.6


def arcade_best_board():
    """The TODAY'S BEST board over the row of machines, facing -Z: two candy-striped posts, a panel
    in a gold frame with bulbs round it and a star crest on top. The game's screen part covers the
    panel's face (BOARD_W - 1 by BOARD_H - 0.8, centered BOARD_Y up, just in front of z = 0)."""
    posts, post_stripes, trim, panel, bulbs_a, bulbs_b, stars = [], [], [], [], [], [], []
    for x in (-POST_X, POST_X):
        post, stripes = candy_post(0.55, BOARD_Y + BOARD_H / 2 + 0.6, 4.5)
        posts.append(post.translate(x, 0, 0.6))
        post_stripes.append(stripes.translate(x, 0, 0.6))
        trim.append(lathe([(0.0, 0.0), (1.0, 0.0), (1.05, 0.3), (0.75, 0.7), (0.0, 0.7)], 20).translate(x, 0, 0.6))
        trim.append(icosphere(0.8, 2).translate(x, BOARD_Y + BOARD_H / 2 + 1.25, 0.6))
    panel.append(box(-BOARD_W / 2, BOARD_W / 2, BOARD_Y - BOARD_H / 2, BOARD_Y + BOARD_H / 2, 0.05, 1.0, 0.3))
    edge = [(-BOARD_W / 2, BOARD_Y - BOARD_H / 2), (BOARD_W / 2, BOARD_Y - BOARD_H / 2),
            (BOARD_W / 2, BOARD_Y + BOARD_H / 2), (-BOARD_W / 2, BOARD_Y + BOARD_H / 2), (-BOARD_W / 2, BOARD_Y - BOARD_H / 2)]
    trim.append(tube([(x, y, -0.02) for x, y in edge], 0.24, 8))
    # Bulbs all round the frame, every other one in the second set (the game chases them).
    k = 0
    for (x0, y0), (x1, y1) in zip(edge, edge[1:]):
        steps = max(1, round(math.hypot(x1 - x0, y1 - y0) / 1.2))
        for i in range(steps):
            t = (i + 0.5) / steps
            (bulbs_a if k % 2 == 0 else bulbs_b).append(bulb(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, -0.25, 0.2))
            k += 1
    # Arms from the posts to the panel, and the crest.
    for x in (-POST_X, POST_X):
        trim.append(tube([(x, BOARD_Y, 0.6), (x * 0.95, BOARD_Y, 0.5)], 0.2, 8))
    crest_y = BOARD_Y + BOARD_H / 2 + 1.5
    stars.append(star_plate(1.6, 0.35).translate(0, crest_y, 0.3))
    for x in (-3.2, 3.2):
        stars.append(star_plate(0.8, 0.3).translate(x, crest_y - 0.75, 0.35))
    return recenter({
        "Posts": merge(*posts),
        "PostStripes": merge(*post_stripes),
        "Trim": merge(*trim),
        "Panel": merge(*panel),
        "BulbsA": merge(*bulbs_a),
        "BulbsB": merge(*bulbs_b),
        "Stars": merge(*stars),
    }, "ArcadeBestBoard")


PROPS = {
    "ArcadeSkeeMachine": arcade_skee_machine,
    "ArcadeSkeeBall": arcade_skee_ball,
    "ArcadeTicketFloor": arcade_ticket_floor,
    "ArcadeBestBoard": arcade_best_board,
}

# Preview colors only; the game colors pieces by name (Props/Arcade.luau).
COLORS = {
    "Cabinet": (255, 84, 150), "Base": (52, 36, 104), "Trim": (255, 204, 64), "Stripes": (255, 255, 255),
    "Stars": (255, 220, 90), "Chute": (210, 220, 235), "Lane": (236, 196, 140), "Hop": (240, 70, 80),
    "Arrows": (255, 255, 255), "Board": (44, 40, 120), "Band10": (156, 108, 255), "Band20": (64, 196, 255),
    "Band30": (110, 226, 140), "Band40": (255, 204, 64), "Band50": (255, 84, 150), "Lips": (255, 255, 255),
    "Holes": (24, 18, 40), "Cup100L": (255, 170, 40), "Cup100R": (255, 170, 40), "Gutter": (40, 34, 70),
    "Back": (60, 50, 140), "Tufts": (90, 80, 170), "Cage": (220, 228, 240), "Display": (24, 20, 40),
    "Marquee": (64, 196, 255), "Sign": (36, 24, 80), "BulbsA": (255, 240, 170), "BulbsB": (255, 160, 220),
    "Ball": (255, 92, 150), "Glow": (255, 120, 220), "Rim": (255, 255, 255), "Grout": (250, 240, 225),
    "TicketA": (255, 140, 70), "TicketB": (255, 92, 150), "TicketC": (255, 204, 64), "Posts": (255, 255, 255),
    "PostStripes": (255, 84, 150), "Panel": (40, 28, 90),
}
