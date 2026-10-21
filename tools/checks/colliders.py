"""Finds what characters can stand on, land on or cling to without seeing it, from the collider
snapshots of tools/checks/colliders.luau (round_harness.py --colliders-at, or LOBBY --colliders).

Owner: "Theres invisible stuff you can jump on and hang on in several games."

    python3 tools/checks/round_harness.py HoneyTrap --client --colliders-at 0,5,120 > run.luau
    python3 tools/preview/luau_task.py run.luau - run.json
    python3 tools/checks/colliders.py run.json --out report_dir

For each snapshot it:
  1. rebuilds the collision-top map (layered downward raycasts from the server) and floods it from
     where the characters stand: walking, stepping and jumping (7.2 studs up, about 9 across), never
     through spots too low to stand in;
  2. redraws everything visible (primitives, unions from their recorded pieces, mesh props from
     assets/meshes) into the same map;
  3. flags every reachable spot whose solid top has nothing drawn near it ("standing on air"),
     every invisible collider whose top a character can jump onto, and every collidable mesh or
     union whose collision (measured by raycasts in its own frame) sticks out of its drawn shape.
Prints a report and writes a top-down PNG per snapshot (green: reachable and drawn, red: reachable
and invisible, orange: reachable mesh or union collision above its drawing, blue: invisible
colliders, grey: unreachable).
"""

from __future__ import annotations

import argparse
import base64
import json
import math
import re
import struct
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
MESH_DIR = ROOT / "assets" / "meshes"

JUMP = 7.2  # StarterPlayer.CharacterJumpHeight
WALK = 16.0
GRAVITY = 196.2
HEADROOM = 4.6  # space a character needs to stand
INVISIBLE = 0.9  # transparency from which a part counts as unseen
TOLERANCE = 0.75  # how far a drawn surface may be from the solid top (studs)


def max_rise(distance: float) -> float:
    """How much higher a spot `distance` studs away can be and still be jumped onto."""
    v0 = math.sqrt(2 * GRAVITY * JUMP)
    apex_t = v0 / GRAVITY
    t = distance / WALK
    if t <= apex_t:
        return JUMP
    return v0 * t - 0.5 * GRAVITY * t * t


# --- geometry -------------------------------------------------------------------------------------


def unit_box():
    v = np.array([[x, y, z] for x in (-0.5, 0.5) for y in (-0.5, 0.5) for z in (-0.5, 0.5)], float)
    idx = lambda x, y, z: (x > 0) * 4 + (y > 0) * 2 + (z > 0)  # noqa: E731
    quads = [
        (idx(0, 1, 0), idx(1, 1, 0), idx(1, 1, 1), idx(0, 1, 1)),  # top
        (idx(0, 0, 0), idx(0, 0, 1), idx(1, 0, 1), idx(1, 0, 0)),  # bottom
        (idx(0, 0, 0), idx(1, 0, 0), idx(1, 1, 0), idx(0, 1, 0)),
        (idx(0, 0, 1), idx(0, 1, 1), idx(1, 1, 1), idx(1, 0, 1)),
        (idx(0, 0, 0), idx(0, 1, 0), idx(0, 1, 1), idx(0, 0, 1)),
        (idx(1, 0, 0), idx(1, 0, 1), idx(1, 1, 1), idx(1, 1, 0)),
    ]
    f = []
    for a, b, c, d in quads:
        f += [(a, b, c), (a, c, d)]
    return v, np.array(f)


def unit_wedge():
    # Roblox WedgePart: full bottom, full back face (+Z), the slope from front-bottom to back-top.
    v = np.array(
        [[-0.5, -0.5, -0.5], [0.5, -0.5, -0.5], [-0.5, -0.5, 0.5], [0.5, -0.5, 0.5], [-0.5, 0.5, 0.5], [0.5, 0.5, 0.5]],
        float,
    )
    f = np.array([[0, 2, 3], [0, 3, 1], [2, 4, 5], [2, 5, 3], [0, 1, 5], [0, 5, 4], [0, 4, 2], [1, 3, 5]])
    return v, f


def unit_cylinder(segments=24):
    # Along X, radius 0.5.
    ang = np.linspace(0, 2 * math.pi, segments, endpoint=False)
    ring = np.stack([np.cos(ang) * 0.5, np.sin(ang) * 0.5], 1)
    verts = [[-0.5, 0, 0], [0.5, 0, 0]]
    for x in (-0.5, 0.5):
        for y, z in ring:
            verts.append([x, y, z])
    verts = np.array(verts, float)
    f = []
    for i in range(segments):
        j = (i + 1) % segments
        a0, a1 = 2 + i, 2 + j
        b0, b1 = 2 + segments + i, 2 + segments + j
        f += [(0, a1, a0), (1, b0, b1), (a0, a1, b1), (a0, b1, b0)]
    return verts, np.array(f)


def unit_sphere(rings=12, segments=24):
    verts = []
    for i in range(rings + 1):
        phi = math.pi * i / rings
        for j in range(segments):
            th = 2 * math.pi * j / segments
            verts.append([0.5 * math.sin(phi) * math.cos(th), 0.5 * math.cos(phi), 0.5 * math.sin(phi) * math.sin(th)])
    f = []
    for i in range(rings):
        for j in range(segments):
            a = i * segments + j
            b = i * segments + (j + 1) % segments
            c = (i + 1) * segments + j
            d = (i + 1) * segments + (j + 1) % segments
            f += [(a, b, d), (a, d, c)]
    return np.array(verts, float), np.array(f)


def outward(mesh):
    """Every face wound so its normal points out of the solid (the top faces face up)."""
    v, f = mesh
    a, b, c = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    volume = np.einsum("ij,ij->i", a, np.cross(b, c)).sum()
    return (v, f[:, ::-1].copy()) if volume < 0 else mesh


PRIMS = {
    "Block": outward(unit_box()),
    "Wedge": outward(unit_wedge()),
    "Cylinder": outward(unit_cylinder()),
    "Ball": outward(unit_sphere()),
}
SHAPE_BY_VALUE = {0: "Ball", 1: "Block", 2: "Cylinder", 3: "Wedge"}


def inside_unit(kind: str, p: np.ndarray) -> np.ndarray:
    """Points (N,3) in a unit primitive's frame inside it."""
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    if kind == "Ball":
        return x * x + y * y + z * z <= 0.25
    if kind == "Cylinder":
        return (np.abs(x) <= 0.5) & (y * y + z * z <= 0.25)
    if kind == "Wedge":
        return (np.abs(x) <= 0.5) & (np.abs(y) <= 0.5) & (np.abs(z) <= 0.5) & (y <= z)
    return (np.abs(x) <= 0.5) & (np.abs(y) <= 0.5) & (np.abs(z) <= 0.5)


GLB_CACHE: dict = {}


def glb_pieces(prop: str) -> dict:
    """{piece name: (verts Nx3, faces)} of a prop's .glb (Roblox axes, as authored)."""
    if prop in GLB_CACHE:
        return GLB_CACHE[prop]
    path = MESH_DIR / f"{prop}.glb"
    result = {}
    if path.exists():
        data = path.read_bytes()
        json_len = struct.unpack_from("<I", data, 12)[0]
        doc = json.loads(data[20 : 20 + json_len])
        blob = data[20 + json_len + 8 :]

        def accessor(index):
            acc = doc["accessors"][index]
            view = doc["bufferViews"][acc["bufferView"]]
            comps = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
            dtype = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}[acc["componentType"]]
            offset = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
            arr = np.frombuffer(blob, dtype=dtype, count=acc["count"] * comps, offset=offset)
            return arr.reshape(acc["count"], comps) if comps > 1 else arr

        for node in doc.get("nodes", []):
            if "mesh" not in node:
                continue
            mesh = doc["meshes"][node["mesh"]]
            verts_all, faces_all, base = [], [], 0
            for prim in mesh["primitives"]:
                v = accessor(prim["attributes"]["POSITION"]).astype(np.float64)
                f = accessor(prim["indices"]).astype(np.int64).reshape(-1, 3)
                verts_all.append(v)
                faces_all.append(f + base)
                base += len(v)
            name = node.get("name") or mesh.get("name")
            result[name] = (np.concatenate(verts_all), np.concatenate(faces_all))
    GLB_CACHE[prop] = result
    return result


def cframe(components):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = components
    return np.array([x, y, z], float), np.array([[r00, r01, r02], [r10, r11, r12], [r20, r21, r22]], float)


def mesh_local(part):
    """The drawn shape of a part in its own frame (scaled to its size): (verts, faces), or None."""
    size = np.array(part["s"], float)
    if part["c"] == "MeshPart":
        prop = part.get("prop")
        if not prop:
            return None
        piece = glb_pieces(prop).get(part["n"])
        if piece is None:
            return None
        verts, faces = piece
        vmin, vmax = verts.min(0), verts.max(0)
        center = (vmin + vmax) / 2
        ext = np.maximum(vmax - vmin, 1e-6)
        unit = (verts - center) / ext
        # Roblox's glTF import turns each mesh half a turn inside its MeshPart (x -> -x, z -> -z).
        unit = unit * np.array([-1.0, 1.0, -1.0])
        return unit * size, faces[:, ::-1] if False else faces
    if part["c"] in ("UnionOperation", "PartOperation", "IntersectOperation"):
        info = part.get("pieces")
        if not info:
            return None
        return union_local(part, info)
    special = part.get("sm")
    kind = "Block"
    if part["c"] == "WedgePart":
        kind = "Wedge"
    elif part.get("shape") in ("Ball", "Cylinder"):
        kind = part["shape"]
    if special and special[0] == "Sphere":
        kind = "Ball"
        scale = np.array(special[1:4], float)
        v, f = PRIMS["Ball"]
        return v * size * scale, f
    if special and special[0] == "FileMesh":
        return None  # drawn by a file mesh: unknown here
    v, f = PRIMS[kind]
    s = size.copy()
    if kind == "Ball":
        s = np.full(3, size.min())
    elif kind == "Cylinder":
        d = min(size[1], size[2])
        s = np.array([size[0], d, d])
    return v * s, f


def union_local(part, info):
    """Triangles of a union's visible surface (positives minus cutters), in its frame."""
    size = np.array(part["s"], float)
    orig = np.array(info["size"], float)
    k = np.where(orig > 0, size / np.where(orig > 0, orig, 1), 1)
    pieces = []
    for piece in info["pieces"]:
        kind = SHAPE_BY_VALUE.get(int(piece[0]), "Block")
        psize = np.array(piece[1:4], float)
        pos, rot = cframe(piece[4:16])
        pos = pos * k
        if kind == "Ball":
            psize = np.full(3, psize.min())
        if kind == "Cylinder":
            d = min(psize[1], psize[2])
            psize = np.array([psize[0], d, d])
        psize = psize * k
        cutter = len(piece) > 16 and piece[16] == 1
        pieces.append((kind, psize, pos, rot, cutter))

    def inside(points, which):
        hit = np.zeros(len(points), bool)
        for kind, psize, pos, rot, cutter in pieces:
            if cutter != which:
                continue
            local = (points - pos) @ rot / psize
            hit |= inside_unit(kind, local)
        return hit

    all_v, all_f, base = [], [], 0
    for kind, psize, pos, rot, cutter in pieces:
        v, f = PRIMS[kind]
        world = (v * psize) @ rot.T + pos
        # Keep a piece's triangles whose middles are on the union's surface.
        mids = world[f].mean(1)
        normals = np.cross(world[f[:, 1]] - world[f[:, 0]], world[f[:, 2]] - world[f[:, 0]])
        length = np.linalg.norm(normals, axis=1, keepdims=True)
        normals = normals / np.maximum(length, 1e-9)
        # A face is on the union's surface when the solid (positives minus cutters) is on one side of
        # it and not the other; a cutter's face shows where it bites into the solid.
        side_a = inside(mids + normals * 0.02, False) & ~inside(mids + normals * 0.02, True)
        side_b = inside(mids - normals * 0.02, False) & ~inside(mids - normals * 0.02, True)
        keep = side_a != side_b
        if cutter:
            f = f[:, ::-1]  # its faces look into the hole, out of the solid
        all_v.append(world)
        all_f.append(f[keep] + base)
        base += len(world)
    if not all_v:
        return None
    return np.concatenate(all_v), np.concatenate(all_f)


def world_tris(part, local):
    verts, faces = local
    pos, rot = cframe(part["cf"])
    world = verts @ rot.T + pos
    return world[faces]


# --- rasterising onto the map ---------------------------------------------------------------------


def raster_vertical(tris: np.ndarray, x0: float, z0: float, step: float, nx: int, nz: int):
    """For triangles (T,3,3), the heights where vertical lines through map columns cross them.
    Returns (column indices, heights, upward-facing flags)."""
    if len(tris) == 0:
        return np.zeros(0, int), np.zeros(0), np.zeros(0, bool)
    a, b, c = tris[:, 0], tris[:, 1], tris[:, 2]
    n = np.cross(b - a, c - a)
    keep = np.abs(n[:, 1]) > 1e-9
    a, b, c, n = a[keep], b[keep], c[keep], n[keep]
    xs = np.stack([a[:, 0], b[:, 0], c[:, 0]], 1)
    zs = np.stack([a[:, 2], b[:, 2], c[:, 2]], 1)
    i0 = np.clip(np.ceil((xs.min(1) - x0) / step - 1e-9).astype(int), 0, nx)
    i1 = np.clip(np.floor((xs.max(1) - x0) / step + 1e-9).astype(int), -1, nx - 1)
    j0 = np.clip(np.ceil((zs.min(1) - z0) / step - 1e-9).astype(int), 0, nz)
    j1 = np.clip(np.floor((zs.max(1) - z0) / step + 1e-9).astype(int), -1, nz - 1)
    ni = np.maximum(i1 - i0 + 1, 0)
    nj = np.maximum(j1 - j0 + 1, 0)
    counts = ni * nj
    total = int(counts.sum())
    if total == 0:
        return np.zeros(0, int), np.zeros(0), np.zeros(0, bool)
    tri = np.repeat(np.arange(len(a)), counts)
    start = np.repeat(np.cumsum(counts) - counts, counts)
    local = np.arange(total) - start
    ii = i0[tri] + local % np.maximum(ni[tri], 1)
    jj = j0[tri] + local // np.maximum(ni[tri], 1)
    px = x0 + ii * step
    pz = z0 + jj * step
    A, B, C = a[tri], b[tri], c[tri]
    # Barycentric in XZ.
    v0x, v0z = B[:, 0] - A[:, 0], B[:, 2] - A[:, 2]
    v1x, v1z = C[:, 0] - A[:, 0], C[:, 2] - A[:, 2]
    v2x, v2z = px - A[:, 0], pz - A[:, 2]
    den = v0x * v1z - v1x * v0z
    ok = np.abs(den) > 1e-12
    den = np.where(ok, den, 1)
    u = (v2x * v1z - v1x * v2z) / den
    v = (v0x * v2z - v2x * v0z) / den
    eps = 1e-6
    inside = ok & (u >= -eps) & (v >= -eps) & (u + v <= 1 + eps)
    y = A[:, 1] + u * (B[:, 1] - A[:, 1]) + v * (C[:, 1] - A[:, 1])
    up = n[tri][:, 1] > 0
    col = jj * nx + ii
    return col[inside], y[inside], up[inside]


# --- the map --------------------------------------------------------------------------------------


def decode_grid(grid):
    raw = base64.b64decode(grid["data"])
    nx, nz = grid["nx"], grid["nz"]
    L = 6
    Y = np.full((L, nz * nx), np.nan)
    P = np.zeros((L, nz * nx), int)
    H = np.zeros((L, nz * nx))
    off = 0
    for col in range(nz * nx):
        count = raw[off]
        off += 1
        for layer in range(count):
            y20, idx, h20 = struct.unpack_from("<hHh", raw, off)
            off += 6
            Y[layer, col] = y20 / 20
            P[layer, col] = idx
            H[layer, col] = h20 / 20
    return Y, P, H


def flood(grid, Y, H, seeds, kill_y, want_graph=False):
    """Reachable (layer, column) spots from the seeds, as a boolean (L, columns) array (with the
    move graph and the start nodes too when `want_graph`: tools trace how a spot is reached)."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import breadth_first_order

    nx, nz, step = grid["nx"], grid["nz"], grid["step"]
    L, N = Y.shape
    valid = ~np.isnan(Y) & (H >= HEADROOM)
    if kill_y is not None:
        valid &= Y > kill_y + 0.5
    Yg = Y.reshape(L, nz, nx)
    Hg = H.reshape(L, nz, nx)
    Vg = valid.reshape(L, nz, nx)
    ids = np.arange(L * N, dtype=np.int32).reshape(L, nz, nx)
    offsets = set()
    for dx in (-1, 0, 1):
        for dz in (-1, 0, 1):
            if dx or dz:
                offsets.add((dx, dz))
    for k in range(16):
        ang = k / 16 * 2 * math.pi
        r = 1.5
        while r <= 11:
            dx = int(round(r * math.cos(ang) / step))
            dz = int(round(r * math.sin(ang) / step))
            if dx or dz:
                offsets.add((dx, dz))
            r += step
    rows, cols = [], []
    for dx, dz in offsets:
        d = step * math.hypot(dx, dz)
        rise = max_rise(d)
        if rise < -40:
            continue
        sz0, sz1 = max(0, -dz), nz - max(0, dz)
        sx0, sx1 = max(0, -dx), nx - max(0, dx)
        if sz1 <= sz0 or sx1 <= sx0:
            continue
        for l1 in range(L):
            src_v = Vg[l1, sz0:sz1, sx0:sx1]
            if not src_v.any():
                continue
            y1 = Yg[l1, sz0:sz1, sx0:sx1]
            h1 = Hg[l1, sz0:sz1, sx0:sx1]
            for l2 in range(L):
                dst_v = Vg[l2, sz0 + dz : sz1 + dz, sx0 + dx : sx1 + dx]
                both = src_v & dst_v
                if not both.any():
                    continue
                y2 = Yg[l2, sz0 + dz : sz1 + dz, sx0 + dx : sx1 + dx]
                h2 = Hg[l2, sz0 + dz : sz1 + dz, sx0 + dx : sx1 + dx]
                with np.errstate(invalid="ignore"):
                    ok = both & (y2 - y1 <= rise + 0.2)
                    # Room at the higher of the two levels on both sides.
                    ok &= y2 + h2 >= np.maximum(y1, y2) + HEADROOM - 0.3
                    ok &= y1 + h1 >= np.maximum(y1, y2) + HEADROOM - 0.3
                if not ok.any():
                    continue
                if max(abs(dx), abs(dz)) > 1:
                    # Nothing solid in the way: the body fits through the columns in between, on a
                    # jump's arc or on the straight line between the two spots.
                    arc_ok = np.ones_like(ok)
                    line_ok = np.ones_like(ok)
                    cells = 2 * max(abs(dx), abs(dz))  # every half cell: thin walls can't slip between
                    seen_cells = set()
                    for t in (k / cells for k in range(1, cells)):
                        mx, mz = int(round(dx * t)), int(round(dz * t))
                        if (mx, mz) in ((0, 0), (dx, dz)) or (mx, mz) in seen_cells:
                            continue
                        seen_cells.add((mx, mz))
                        ym = Yg[:, sz0 + mz : sz1 + mz, sx0 + mx : sx1 + mx]
                        hm = Hg[:, sz0 + mz : sz1 + mz, sx0 + mx : sx1 + mx]
                        empty = np.isnan(ym).all(0)
                        travel = t * d / WALK
                        lift = min(JUMP, math.sqrt(2 * GRAVITY * JUMP) * travel - 0.5 * GRAVITY * travel * travel)
                        for body, good in ((y1 + max(lift, 0), arc_ok), (y1 + (y2 - y1) * t, line_ok)):
                            with np.errstate(invalid="ignore"):
                                fits = ((ym <= body + 0.6) & (ym + hm >= body + HEADROOM - 0.3)).any(0)
                            good &= fits | empty
                    ok &= arc_ok | line_ok
                    if not ok.any():
                        continue
                src_ids = ids[l1, sz0:sz1, sx0:sx1][ok]
                dst_ids = ids[l2, sz0 + dz : sz1 + dz, sx0 + dx : sx1 + dx][ok]
                rows.append(src_ids)
                cols.append(dst_ids)
    reach = np.zeros(L * N, bool)
    if not rows:
        return (reach.reshape(L, N), None, []) if want_graph else reach.reshape(L, N)
    rows = np.concatenate(rows)
    cols = np.concatenate(cols)
    graph = coo_matrix((np.ones(len(rows), np.int8), (rows, cols)), shape=(L * N, L * N)).tocsr()
    x0, z0 = grid["x0"], grid["z0"]
    starts = []
    for seed in seeds:
        sx, sy, sz = seed[1], seed[2], seed[3]
        ix = int(round((sx - x0) / step))
        iz = int(round((sz - z0) / step))
        if not (0 <= ix < nx and 0 <= iz < nz):
            continue
        col = iz * nx + ix
        best = None
        for layer in range(L):
            if valid[layer, col] and Y[layer, col] <= sy + 0.5:
                best = layer
                break
        if best is None:
            continue
        start = best * N + col
        starts.append(start)
        if reach[start]:
            continue
        order = breadth_first_order(graph, start, directed=True, return_predecessors=False)
        reach[order] = True
    return (reach.reshape(L, N), graph, starts) if want_graph else reach.reshape(L, N)


def visible_layers(parts, grid, skip=lambda p: False):
    """Every drawn surface crossing each map column: sorted (column, height) arrays and the part."""
    nx, nz, step, x0, z0 = grid["nx"], grid["nz"], grid["step"], grid["x0"], grid["z0"]
    cols, ys, owners = [], [], []
    unknown = set()
    for part in parts.values():
        if part["t"] >= INVISIBLE or skip(part):
            continue
        local = mesh_local(part)
        if local is None:
            unknown.add((part.get("prop"), part["n"], part["c"]))
            continue
        tris = world_tris(part, local)
        c, y, _ = raster_vertical(tris, x0, z0, step, nx, nz)
        cols.append(c)
        ys.append(y)
        owners.append(np.full(len(c), part["i"]))
    if not cols:
        return np.zeros(0, int), np.zeros(0), np.zeros(0, int), unknown
    cols = np.concatenate(cols)
    ys = np.concatenate(ys)
    owners = np.concatenate(owners)
    order = np.lexsort((ys, cols))
    return cols[order], ys[order], owners[order], unknown


def nearest_visible(vcols, vys, query_cols, query_ys):
    """For each query (column, height): the smallest |drawn height - height| in that column (inf if none),
    and the signed gap to the nearest drawn surface at or below (height - drawn)."""
    if len(vcols) == 0:
        return np.full(len(query_cols), np.inf), np.full(len(query_cols), np.inf)
    key = vcols.astype(np.float64) * 1e5 + (vys + 5000)
    qkey = query_cols.astype(np.float64) * 1e5 + (query_ys + 5000)
    pos = np.searchsorted(key, qkey)
    best = np.full(len(query_cols), np.inf)
    below = np.full(len(query_cols), np.inf)
    for shift in (-1, 0):
        idx = pos + shift
        ok = (idx >= 0) & (idx < len(key))
        idx2 = np.clip(idx, 0, len(key) - 1)
        same = ok & (vcols[idx2] == query_cols)
        d = np.where(same, np.abs(vys[idx2] - query_ys), np.inf)
        best = np.minimum(best, d)
        gap = np.where(same & (vys[idx2] <= query_ys + 1e-6), query_ys - vys[idx2], np.inf)
        below = np.minimum(below, gap)
    return best, below


# --- probes: each collidable mesh/union's collision compared with its drawing ----------------------


def probe_compare(probe, part):
    """Collision top/bottom (raycasts) against the drawn top/bottom over the part's local grid."""
    n = probe["n"]
    margin = probe["margin"]
    raw = np.frombuffer(base64.b64decode(probe["data"]), dtype="<i2").astype(float)
    down = raw[: n * n].reshape(n, n)
    up = raw[n * n : 2 * n * n].reshape(n, n)
    size = np.array(part["s"], float)
    hx, hy, hz = size[0] / 2 + margin, size[1] / 2 + margin, size[2] / 2 + margin
    u = ((np.arange(n) + 0.5) / n * 2 - 1)
    # down[a, b]: origin (u[a] * hx, hy, u[b] * hz)
    coll_top = np.where(down < -32000, np.nan, hy - down / 100)
    coll_bottom = np.where(up < -32000, np.nan, -hy + up / 100)
    local = mesh_local(part)
    if local is None:
        return None
    verts, faces = local
    tris = verts[faces]
    # Rasterise on the probe grid: x = u[a]*hx -> index a; z = u[b]*hz -> index b.
    step_x = 2 * hx / n
    step_z = 2 * hz / n
    # Use a common grid by scaling z into x units.
    scale = step_x / step_z
    scaled = tris.copy()
    scaled[:, :, 2] = (tris[:, :, 2] + hz) * scale - hx
    x0 = -hx + step_x / 2
    col, y, _ = raster_vertical(scaled, x0, x0, step_x, n, n)
    vis_top = np.full(n * n, np.nan)
    vis_bottom = np.full(n * n, np.nan)
    if len(col):
        order = np.lexsort((y, col))
        col, y = col[order], y[order]
        first = np.r_[True, col[1:] != col[:-1]]
        last = np.r_[col[1:] != col[:-1], True]
        vis_bottom[col[first]] = y[first]
        vis_top[col[last]] = y[last]
    # raster columns are jj * n + ii with ii along x (a) and jj along z (b)
    vis_top = vis_top.reshape(n, n).T  # -> [a, b]
    vis_bottom = vis_bottom.reshape(n, n).T
    cell_area = step_x * step_z
    with np.errstate(invalid="ignore"):
        top_excess = np.where(np.isnan(vis_top), np.where(np.isnan(coll_top), 0, np.inf), coll_top - vis_top)
        top_excess = np.where(np.isnan(coll_top), 0, top_excess)
        bottom_excess = np.where(
            np.isnan(vis_bottom), np.where(np.isnan(coll_bottom), 0, np.inf), vis_bottom - coll_bottom
        )
        bottom_excess = np.where(np.isnan(coll_bottom), 0, bottom_excess)
    # Collision where nothing is drawn: how far it reaches past the drawing (in the map plane).
    outside = ~np.isnan(coll_top) & np.isnan(vis_top)
    finite_top = np.where(np.isfinite(top_excess), top_excess, 0)
    return {
        "maxTopExcess": float(np.nanmax(np.where(np.isfinite(top_excess), top_excess, -1))) if top_excess.size else 0,
        "topAbove1Area": float(((top_excess > 1.0)).sum() * cell_area),
        "topAbove2Area": float(((top_excess > 2.0)).sum() * cell_area),
        "outsideArea": float(outside.sum() * cell_area),
        "bottomBelow1Area": float((bottom_excess > 1.0).sum() * cell_area),
        "maxBottomExcess": float(np.nanmax(np.where(np.isfinite(bottom_excess), bottom_excess, -1))),
        "collArea": float((~np.isnan(coll_top)).sum() * cell_area),
        "visArea": float((~np.isnan(vis_top)).sum() * cell_area),
        "grids": (coll_top, vis_top, coll_bottom, vis_bottom, finite_top),
    }


# --- report ---------------------------------------------------------------------------------------


def where(part):
    pos, _ = cframe(part["cf"])
    return f"({pos[0]:.1f}, {pos[1]:.1f}, {pos[2]:.1f})"


def analyse(snapshot, out_dir: Path | None, name: str, kill_y=None, verbose=False):
    parts = {p["i"]: p for p in snapshot["parts"]}
    grid = snapshot.get("grid")
    lines = []
    flags = []
    if not grid:
        lines.append("  (no map)")
        return lines, flags
    Y, P, H = decode_grid(grid)
    L, N = Y.shape
    nx, nz, step = grid["nx"], grid["nz"], grid["step"]
    if kill_y is None:
        kill_y = snapshot.get("killY")
    reach = flood(grid, Y, H, snapshot.get("seeds", []), kill_y)
    lines.append(
        f"  map {nx}x{nz} step {step} ({grid['rays']} rays, {snapshot.get('gridSeconds')}s), "
        f"reachable spots {int(reach.sum())} of {int((~np.isnan(Y)).sum())}"
    )

    vcols, vys, vowners, unknown = visible_layers(parts, grid)
    if unknown:
        lines.append(f"  drawn parts I can't redraw (left out): {sorted(map(str, unknown))[:12]}")

    # Reachable spots: what they stand on and whether anything is drawn there.
    layer_idx, col_idx = np.nonzero(reach)
    ys = Y[layer_idx, col_idx]
    owner = P[layer_idx, col_idx]
    best, below = nearest_visible(vcols, vys, col_idx, ys)
    # Also accept a drawn surface in a neighbouring column (edges of drawn floors).
    for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ix = col_idx % nx + dx
        iz = col_idx // nx + dz
        ok = (ix >= 0) & (ix < nx) & (iz >= 0) & (iz < nz)
        nb = np.where(ok, iz * nx + ix, col_idx)
        b2, _ = nearest_visible(vcols, vys, nb, ys)
        # (a drawn surface a little higher next door: the rounded edge of what you stand on)
        best = np.minimum(best, np.where(ok, np.maximum(b2 - 0.25 * step, 0), np.inf))
    unseen = best > TOLERANCE
    by_part = defaultdict(list)
    for k in np.nonzero(unseen)[0]:
        if owner[k] != 65535:  # terrain: drawn by the engine, as it collides
            by_part[int(owner[k])].append(k)
    status = np.zeros((nz, nx), np.uint8)  # 0 nothing, 1 unreachable, 2 ok, 3 invisible, 4 mesh above
    status[(~np.isnan(Y)).any(0).reshape(nz, nx)] = 1
    top_reach = reach.any(0).reshape(nz, nx)
    status[top_reach] = 2
    for index, ks in by_part.items():
        part = parts.get(index)
        if part is None:
            label = "terrain" if index == 65535 else f"part #{index} (not listed)"
            invisible = False
        else:
            label = part["p"]
            invisible = part["t"] >= INVISIBLE
        ks = np.array(ks)
        gap = below[ks]
        gap_text = "nothing drawn below" if not np.isfinite(gap).any() else f"drawn surface {np.nanmin(np.where(np.isfinite(gap), gap, np.nan)):.1f}-{np.nanmax(np.where(np.isfinite(gap), gap, np.nan)):.1f} below"
        xs = grid["x0"] + (col_idx[ks] % nx) * step
        zs = grid["z0"] + (col_idx[ks] // nx) * step
        kind = "INVISIBLE" if invisible else "UNDRAWN-TOP"
        area = len(ks) * step * step
        flags.append(
            {
                "kind": kind,
                "part": label,
                "class": part["c"] if part else "?",
                "size": part["s"] if part else None,
                "at": where(part) if part else "",
                "t": part["t"] if part else None,
                "area": area,
                "x": [float(xs.min()), float(xs.max())],
                "z": [float(zs.min()), float(zs.max())],
                "y": [float(ys[ks].min()), float(ys[ks].max())],
                "gap": gap_text,
                "fid": part.get("fid") if part else None,
            }
        )
        for k in ks:
            status[col_idx[k] // nx, col_idx[k] % nx] = 3 if invisible else 4

    # Invisible colliders whose top can be jumped onto (also thin ones the map may step over). The
    # highest a jump reaches over each map column, from any reachable spot within 11 studs.
    reach_cols = col_idx
    reach_y = ys
    rx = grid["x0"] + (reach_cols % nx) * step
    rz = grid["z0"] + (reach_cols // nx) * step
    top_reach = np.full(nz * nx, -np.inf)
    np.maximum.at(top_reach, reach_cols, reach_y)
    top_reach = top_reach.reshape(nz, nx)
    jump_to = np.full((nz, nx), -np.inf)
    span = int(11 / step)
    for dz in range(-span, span + 1):
        for dx in range(-span, span + 1):
            d = step * math.hypot(dx, dz)
            if d > 11:
                continue
            rise = max_rise(d)
            src = top_reach[max(0, dz) : nz + min(0, dz), max(0, dx) : nx + min(0, dx)]
            dst = jump_to[max(0, -dz) : nz + min(0, -dz), max(0, -dx) : nx + min(0, -dx)]
            np.maximum(dst, src + rise, out=dst)
    jump_to = jump_to.ravel()
    for part in parts.values():
        if not part["cc"] or part["t"] < INVISIBLE:
            continue
        local = mesh_local(part) if part["c"] != "MeshPart" else None
        if local is None:
            continue
        tris = world_tris(part, local)
        normals = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
        upward = normals[:, 1] / np.maximum(np.linalg.norm(normals, axis=1), 1e-9) > 0.6
        tris = tris[upward]
        if len(tris) == 0:
            continue
        # Sample the top every half stud (coarser on big floors).
        lo = tris.reshape(-1, 3).min(0)
        hi = tris.reshape(-1, 3).max(0)
        fine = max(0.5, math.sqrt((hi[0] - lo[0] + 1) * (hi[2] - lo[2] + 1) / 60000))
        fnx = int((hi[0] - lo[0]) / fine) + 2
        fnz = int((hi[2] - lo[2]) / fine) + 2
        c, ty, _ = raster_vertical(tris, lo[0], lo[2], fine, fnx, fnz)
        if len(c) == 0:
            continue
        tx = lo[0] + (c % fnx) * fine
        tz = lo[2] + (c // fnx) * fine
        gx = np.round((tx - grid["x0"]) / step).astype(int)
        gz = np.round((tz - grid["z0"]) / step).astype(int)
        inside_map = (gx >= 0) & (gx < nx) & (gz >= 0) & (gz < nz)
        tx, ty, tz, gx, gz = tx[inside_map], ty[inside_map], tz[inside_map], gx[inside_map], gz[inside_map]
        gcol = gz * nx + gx
        # Something else solid sitting right on it hides it (its top isn't a place to stand).
        covered = np.zeros(len(gcol), bool)
        for layer in range(L):
            yl = Y[layer, gcol]
            with np.errstate(invalid="ignore"):
                covered |= (yl > ty + 0.3) & (yl < ty + HEADROOM) & (P[layer, gcol] != part["i"])
        # A drawn surface right at the top (a mesh floor over its invisible collider) is what you see
        # standing there: not invisible.
        drawn, _ = nearest_visible(vcols, vys, gcol, ty)
        covered |= drawn <= TOLERANCE
        hit = ~covered & (ty <= jump_to[gcol] + 0.2)
        if not hit.any():
            continue
        k = int(np.argmax(hit))
        need = ty[hit] - (jump_to[gcol][hit] - JUMP)
        flags.append(
            {
                "kind": "JUMPABLE-INVISIBLE",
                "part": part["p"],
                "class": part["c"],
                "size": part["s"],
                "at": where(part),
                "t": part["t"],
                "area": int(hit.sum()) * fine * fine,
                "sample": (float(tx[k]), float(ty[k]), float(tz[k])),
                "gap": f"top up to {float(need.max()):+.1f} studs above the floor it's jumped from",
            }
        )

    # Collidable meshes and unions: collision vs drawing in their own frame.
    probe_rows = []
    by_key = defaultdict(list)
    for part in parts.values():
        if part.get("key"):
            by_key[part["key"]].append(part)
    reach_pts = np.stack([rx, reach_y, rz], 1) if len(rx) else np.zeros((0, 3))
    for probe in snapshot.get("probes", []):
        rep = parts.get(probe["part"])
        if rep is None or rep["t"] >= INVISIBLE:
            continue
        result = probe_compare(probe, rep)
        instances = by_key.get(probe["key"], [rep])
        near = 0
        for inst in instances:
            pos, rot = cframe(inst["cf"])
            half = np.abs(rot) @ (np.array(inst["s"]) / 2)
            if len(reach_pts) == 0:
                continue
            lo = pos - half - np.array([10, 12, 10])
            hi = pos + half + np.array([10, 2, 10])
            inside = np.all((reach_pts >= lo) & (reach_pts <= hi), axis=1)
            if inside.any():
                near += 1
        name_ = f"{rep.get('prop') or ''}:{rep['n']}" if rep.get("prop") else rep["p"]
        if result is None:
            probe_rows.append((name_, rep["c"], rep.get("fid"), len(instances), near, None))
            continue
        probe_rows.append((name_, rep["c"], rep.get("fid"), len(instances), near, result))
        if near and (result["topAbove1Area"] > 1.0 or result["outsideArea"] > 2.0 or result["bottomBelow1Area"] > 2.0):
            flags.append(
                {
                    "kind": "HULL-BIGGER",
                    "part": name_,
                    "class": rep["c"],
                    "size": rep["s"],
                    "at": where(rep),
                    "t": rep["t"],
                    "fid": rep.get("fid"),
                    "instances": len(instances),
                    "near": near,
                    "area": result["topAbove1Area"],
                    "gap": f"collision above drawing >1 stud over {result['topAbove1Area']:.0f} sq studs (max {result['maxTopExcess']:.1f}), "
                    f"outside drawing {result['outsideArea']:.0f}, below drawing {result['bottomBelow1Area']:.0f} (max {result['maxBottomExcess']:.1f})",
                }
            )

    # Print: one line per kind of thing (a prop's piece, or a part's path without its number), the
    # worst case first; every instance with --verbose.
    order = {"INVISIBLE": 0, "JUMPABLE-INVISIBLE": 1, "UNDRAWN-TOP": 2, "HULL-BIGGER": 3}
    flags.sort(key=lambda f: (order.get(f["kind"], 9), -f.get("area", 0)))
    groups: dict = {}
    for f in flags:
        key = (f["kind"], re.sub(r"\d+", "#", f["part"]))
        groups.setdefault(key, []).append(f)
    for (kind, label), items in groups.items():
        worst = items[0]
        lines.append(
            f"  {kind:18s} {label}  x{len(items)}, area {sum(i.get('area', 0) for i in items):.0f} sq studs; worst: "
            f"[{worst['class']} {worst.get('size')} at {worst.get('at')} t={worst.get('t')} fid={worst.get('fid')}] "
            f"{worst.get('gap', '')}"
            + (f"  y {worst['y'][0]:.1f}..{worst['y'][1]:.1f}" if "y" in worst else "")
            + (f"  e.g. {tuple(round(v, 1) for v in worst['sample'])}" if worst.get("sample") else "")
        )
    for f in flags if verbose else []:
        lines.append(
            f"  {f['kind']:18s} {f['part']}  [{f['class']} {f.get('size')} at {f.get('at')} t={f.get('t')} "
            f"fid={f.get('fid')}]  area {f.get('area', 0):.1f}  {f.get('gap', '')}"
            + (f"  y {f['y'][0]:.1f}..{f['y'][1]:.1f} x {f['x'][0]:.0f}..{f['x'][1]:.0f} z {f['z'][0]:.0f}..{f['z'][1]:.0f}" if "y" in f else "")
            + (f"  e.g. {tuple(round(v, 1) for v in f['sample'])}" if f.get("sample") else "")
            + (f"  {f['near']}/{f['instances']} near reachable" if "near" in f else "")
        )
    if verbose:
        lines.append("  collidable meshes/unions (collision vs drawing):")
        for row in sorted(probe_rows, key=lambda r: -(r[5]["topAbove1Area"] if r[5] else -1)):
            name_, cls, fid, count, near, result = row
            if result is None:
                lines.append(f"    {name_:40s} {cls:15s} {fid}  x{count} near {near}: can't redraw")
            else:
                lines.append(
                    f"    {name_:40s} {cls:15s} {fid}  x{count} near {near}: top>1 {result['topAbove1Area']:.1f} "
                    f"(max {result['maxTopExcess']:.1f}) outside {result['outsideArea']:.1f} below>1 {result['bottomBelow1Area']:.1f} "
                    f"coll {result['collArea']:.0f} vis {result['visArea']:.0f}"
                )

    if out_dir is not None:
        try:
            from PIL import Image

            colors = np.array(
                [[20, 20, 24], [70, 70, 78], [70, 170, 80], [235, 40, 40], [255, 150, 30], [60, 120, 255]], np.uint8
            )
            img = colors[status]
            # Invisible colliders in blue where nothing else is drawn on the map.
            for part in parts.values():
                if not part["cc"] or part["t"] < INVISIBLE:
                    continue
                pos, rot = cframe(part["cf"])
                half = np.abs(rot) @ (np.array(part["s"]) / 2)
                i0 = int(max(0, (pos[0] - half[0] - grid["x0"]) / step))
                i1 = int(min(nx - 1, (pos[0] + half[0] - grid["x0"]) / step))
                j0 = int(max(0, (pos[2] - half[2] - grid["z0"]) / step))
                j1 = int(min(nz - 1, (pos[2] + half[2] - grid["z0"]) / step))
                if i1 >= i0 and j1 >= j0 and (i1 - i0) * (j1 - j0) < 0.5 * nx * nz:
                    region = status[j0 : j1 + 1, i0 : i1 + 1]
                    sub = img[j0 : j1 + 1, i0 : i1 + 1]
                    sub[(region == 1) | (region == 0)] = colors[5]
            scale = max(1, int(900 / max(nx, nz)))
            image = Image.fromarray(img[::-1, ::-1]).resize((nx * scale, nz * scale), Image.NEAREST)
            out_dir.mkdir(parents=True, exist_ok=True)
            image.save(out_dir / f"{name}.png")
            lines.append(f"  map: {out_dir / (name + '.png')} (north up = -Z; 1 px = {step / scale:.2f} studs)")
        except Exception as error:  # noqa: BLE001
            lines.append(f"  (no map image: {error})")
    return lines, flags


def load(path: Path):
    data = json.loads(path.read_text())
    data = data[0] if isinstance(data, list) else data
    data = json.loads(data) if isinstance(data, str) else data
    return data


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("results", nargs="+", help="luau_task.py result files")
    parser.add_argument("--out", help="folder for map images and flags.json")
    parser.add_argument("--kill-y", type=float, default=None, help="spots below this height are deadly")
    parser.add_argument("--verbose", action="store_true", help="list every collidable mesh/union comparison")
    args = parser.parse_args()
    out_dir = Path(args.out) if args.out else None
    everything = {}
    for path in args.results:
        data = load(Path(path))
        stem = Path(path).stem
        print(f"== {stem}")
        for key in ("prepare", "start", "endReason", "lobby"):
            if key in data:
                print(f"  {key}: {data[key]}")
        for snapshot in data.get("colliders", []) or []:
            label = snapshot.get("label")
            if snapshot.get("failed"):
                print(f"  -- {label}: FAILED {snapshot['failed']}")
                continue
            print(f"  -- {label}: {len(snapshot['parts'])} parts, groups people {snapshot.get('people')} bots {snapshot.get('bots')}")
            lines, flags = analyse(snapshot, out_dir, f"{stem}_{label}", args.kill_y, args.verbose)
            print("\n".join(lines))
            everything[f"{stem}:{label}"] = flags
        left = data.get("colliderLeftovers")
        if left is not None:
            print(f"  -- after cleanup: {len(left)} colliding parts left" + (f": {left[:8]}" if left else ""))
            everything[f"{stem}:leftovers"] = left
        if data.get("errors"):
            print(f"  errors: {len(data['errors'])}: {data['errors'][:3]}")
    if out_dir is not None:
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / "flags.json").write_text(json.dumps(everything, indent=1, default=str))


if __name__ == "__main__":
    sys.exit(main())
