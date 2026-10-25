"""Finds surfaces that will flicker in Roblox (z-fighting): two opaque parts with a face in the same
plane (within --eps studs) whose footprints overlap. Works on a world dump from dump_world.luau, or a
round_harness.py --dump-at result (its "dump").

    python3 tools/preview/zfight.py dump.json [--eps 0.025] [--all] [--no-meshes]

--eps: faces closer than this flicker (0.025 studs). It was 0.08 ("the game keeps faces 0.1 apart"),
but a depth buffer tells faces 0.03 apart at 100 studs, and pushing a mesh's own faces 0.1 apart
swelled 51 props in version 57 (tools/meshgen/unfight.py): 0.03 is the game's gap now.

Owner, on telling AI-built games apart: "Z Fighting. An AI built map will have overlapping parts that
look like they flicker when you move the camera." So every pair found is checked against what's
drawn, not just the parts' boxes:
  * a spot only counts where it's on both parts' real, flat surfaces: a cylinder's round side, a
    ball, a wedge's slope or a union's rounded edge isn't where its box says (unions are redrawn
    from the pieces Shapes.RecordPieces kept);
  * nothing solid may be pressed against it (within 0.1 stud in front): a floor's underside on the
    lawn or the terrain, a back face flat on a wall. No camera sees those;
  * two faces of the same colour and material (SmoothPlastic, Neon...) look the same whichever wins,
    so they can't be seen to flicker either.
Mesh props are checked too, triangle by triangle from their .glb in assets/meshes (as render.py
draws them), against each other and against parts. Two pieces of one prop as it was modelled are
counted apart: that fight is in the mesh (its tools/meshgen script), and only a rebuilt, re-uploaded
mesh fixes it. --all also lists the false alarms, with why.

What it can't tell yet: a face buried inside a mesh prop (not pressed on its surface) still counts,
as between two mesh blocks built into a wall; and round_harness dumps carry no terrain, so a face
resting on an arena's terrain counts too. Check those names before moving anything.
"""

import argparse
import json
import struct
from collections import defaultdict
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
MESH_DIR = ROOT / "assets" / "meshes"

COVER_GAP = 0.1  # a face with something opaque this close in front of it can't be seen
FLAT_STEP, FLAT_TOLERANCE = 0.03, 0.0005  # a surface curving away more than this over that isn't flat
# Materials with no texture: two faces of one colour in one of these render the same either way.
PLAIN = {"SmoothPlastic", "Neon", "Plastic", "Glass", "ForceField"}


def load(path):
    data = json.load(open(path))
    data = data[0] if isinstance(data, list) else data
    data = json.loads(data) if isinstance(data, str) else data
    if "parts" not in data and "dump" in data:  # a round_harness.py result
        data = data["dump"]
        data = json.loads(data) if isinstance(data, str) else data
    return data


def faces(part):
    x, y, z, *r = part["cf"]
    rot = [[r[0], r[1], r[2]], [r[3], r[4], r[5]], [r[6], r[7], r[8]]]
    axes = [(rot[0][i], rot[1][i], rot[2][i]) for i in range(3)]  # local X, Y, Z in world space
    size = part["s"]
    if part.get("shape") == "Cylinder":
        d = min(size[1], size[2])
        size = [size[0], d, d]
    for i in range(3):
        for sign in (-1, 1):
            n = tuple(sign * c for c in axes[i])
            center = (x + n[0] * size[i] / 2, y + n[1] * size[i] / 2, z + n[2] * size[i] / 2)
            others = [j for j in range(3) if j != i]
            yield n, center, [(axes[j], size[j] / 2) for j in others]


def dot(a, b):
    return sum(p * q for p, q in zip(a, b))


def overlap(face_a, face_b):
    """Separating-axis test for two coplanar rectangles."""
    (_, ca, ea), (_, cb, eb) = face_a, face_b
    delta = tuple(q - p for p, q in zip(ca, cb))
    for axis, _ in ea + eb:
        ra = sum(abs(dot(axis, ax)) * h for ax, h in ea)
        rb = sum(abs(dot(axis, ax)) * h for ax, h in eb)
        if abs(dot(delta, axis)) >= ra + rb - 0.05:
            return False
    return True


def label(part):
    return f"{part['n']}@{[round(v, 1) for v in part['cf'][:3]]}"


# What each part really fills ---------------------------------------------------------------------

KINDS = {0: "Ball", 1: "Block", 2: "Cylinder", 3: "Wedge"}  # Enum.PartType values (CornerWedge: its box)


def frame(components):
    x, y, z, *r = components
    return np.array(r, dtype=float).reshape(3, 3), np.array([x, y, z], dtype=float)


def primitive_inside(kind, half, local):
    """Points (N x 3, in the shape's own frame) inside a primitive of half-size `half`."""
    ax, ay, az = np.abs(local[:, 0]), np.abs(local[:, 1]), np.abs(local[:, 2])
    if kind == "Ball":
        radius = min(half)
        return (local**2).sum(axis=1) <= radius * radius
    if kind == "Cylinder":  # along X
        radius = min(half[1], half[2])
        return (ax <= half[0]) & (local[:, 1] ** 2 + local[:, 2] ** 2 <= radius * radius)
    box = (ax <= half[0]) & (ay <= half[1]) & (az <= half[2])
    if kind == "Wedge":  # the slope rises from the front (-Z) bottom to the back (+Z) top
        box &= local[:, 1] / max(half[1], 1e-6) <= local[:, 2] / max(half[2], 1e-6)
    return box


class Solid:
    def __init__(self, part):
        self.part = part
        self.rot, self.pos = frame(part["cf"])
        self.half = np.array(part["s"], dtype=float) / 2
        self.kind = "Wedge" if part["c"] == "WedgePart" else part.get("shape", "Block")
        if self.kind not in ("Ball", "Block", "Cylinder", "Wedge"):
            self.kind = "Block"
        self.pieces = None
        info = part.get("pieces")
        if info:  # a union redrawn from the pieces it was made of (Shapes.RecordPieces)
            orig = info["size"]
            k = np.array([part["s"][i] / orig[i] if orig[i] else 1 for i in range(3)])
            self.pieces = []
            for piece in info["pieces"]:
                rot, pos = frame(piece[4:16])
                cutter = len(piece) > 16 and piece[16] == 1
                self.pieces.append((KINDS.get(piece[0], "Block"), np.array(piece[1:4]) * k / 2, rot, pos * k, cutter))
        elif part["c"] in ("UnionOperation", "PartOperation", "MeshPart"):
            self.kind = None  # shape unknown: only its box is known
        corner = np.abs(self.rot) @ self.half
        self.lo, self.hi = self.pos - corner, self.pos + corner

    def inside(self, points, box_if_unknown=True):
        local = (points - self.pos) @ self.rot
        if self.pieces is not None:
            solid = np.zeros(len(points), dtype=bool)
            cut = np.zeros(len(points), dtype=bool)
            for kind, half, rot, pos, cutter in self.pieces:
                hit = primitive_inside(kind, half, (local - pos) @ rot)
                if cutter:
                    cut |= hit
                else:
                    solid |= hit
            return solid & ~cut
        if self.kind is None:
            if not box_if_unknown:
                return np.zeros(len(points), dtype=bool)
            return primitive_inside("Block", self.half, local)
        return primitive_inside(self.kind, self.half, local)

    def depth(self, points, n):
        """Where the surface really is under points on one of the box's faces (normal n): its offset
        along n (0 = on the box face, negative = further in), or nan if it isn't within reach."""
        reach = min(0.04, 0.45 * float(self.half.min() * 2))
        ok = ~self.inside(points + n * 0.002) & self.inside(points - n * reach)
        lo = np.full(len(points), -reach)
        hi = np.full(len(points), 0.002)
        if self.kind not in ("Block", None) or self.pieces is not None:
            for _ in range(10):
                mid = (lo + hi) / 2
                hit = self.inside(points + n * mid[:, None])
                lo, hi = np.where(hit, mid, lo), np.where(hit, hi, mid)
        else:
            lo[:] = 0
            hi[:] = 0
        result = (lo + hi) / 2
        result[~ok] = np.nan
        return result

    def flat_surface(self, points, n, u, v):
        """Offsets (as depth) of the surface under each point, nan where it's missing or curved."""
        base = self.depth(points, n)
        if self.kind == "Block" and self.pieces is None:
            return base
        for direction in (u, -u, v, -v):
            beside = points + direction * FLAT_STEP
            near = self.depth(beside, n)
            curved = np.abs(near - base) > FLAT_TOLERANCE
            # Nothing within reach beside a spot: past the face's edge is fine, but still over the
            # box means the surface fell away (a slope, a curve).
            fell = np.isnan(near) & primitive_inside("Block", self.half, (beside - n * 0.001 - self.pos) @ self.rot)
            base = np.where(curved | fell, np.nan, base)
        return base


class Covers:
    """What can hide a face: opaque parts and unions (by what they fill), mesh triangles (a face
    pressed against one facing back at it) and the terrain."""

    CELL = 8.0

    def __init__(self, solids, meshes, terrain):
        self.solids = solids
        self.cells = defaultdict(list)
        for index, solid in enumerate(solids):
            lo = np.floor(solid.lo / self.CELL).astype(int)
            hi = np.floor(solid.hi / self.CELL).astype(int)
            if np.prod(hi - lo + 1) > 200000:
                continue
            for cx in range(lo[0], hi[0] + 1):
                for cy in range(lo[1], hi[1] + 1):
                    for cz in range(lo[2], hi[2] + 1):
                        self.cells[(cx, cy, cz)].append(index)
        self.meshes = meshes  # [(part id, triangles T x 3 x 3, their normals, their lows, their highs)]
        self.mesh_cells = defaultdict(list)
        for index, (_, tris, _, _, _) in enumerate(meshes):
            lo, hi = tris.reshape(-1, 3).min(0), tris.reshape(-1, 3).max(0)
            lo = np.floor(lo / self.CELL).astype(int)
            hi = np.floor(hi / self.CELL).astype(int)
            for cx in range(lo[0], hi[0] + 1):
                for cy in range(lo[1], hi[1] + 1):
                    for cz in range(lo[2], hi[2] + 1):
                        self.mesh_cells[(cx, cy, cz)].append(index)
        self.terrain = terrain

    def _near(self, cells, points):
        keys = {tuple(k) for k in np.floor(points / self.CELL).astype(int)}
        found = set()
        for key in keys:
            found.update(cells.get(key, ()))
        return found

    def solid_at(self, points, skip):
        result = np.zeros(len(points), dtype=bool)
        for index in self._near(self.cells, points):
            if self.solids[index].part["_id"] in skip:
                continue
            todo = ~result
            if not todo.any():
                break
            result[todo] |= self.solids[index].inside(points[todo], box_if_unknown=False)
        return result

    def mesh_in_front(self, points, n, skip):
        """Points with a mesh triangle facing back at them within COVER_GAP along n."""
        result = np.zeros(len(points), dtype=bool)
        ends = np.concatenate([points, points + n * COVER_GAP])
        lo, hi = ends.min(axis=0) - 0.01, ends.max(axis=0) + 0.01
        for index in self._near(self.mesh_cells, ends):
            part_id, tris, normals, tri_lo, tri_hi = self.meshes[index]
            if part_id in skip:
                continue
            # (only the triangles facing back at the points, near them)
            near = (normals @ n < -0.5) & (tri_lo <= hi).all(axis=1) & (tri_hi >= lo).all(axis=1)
            if not near.any():
                continue
            hit = ray_hits(points[~result], n, tris[near], COVER_GAP)
            result[np.flatnonzero(~result)[hit]] = True
            if result.all():
                break
        return result

    def under_terrain(self, points):
        t = self.terrain
        count = int(round(2 * t["half"] / t["step"])) + 1 if t and t.get("step") else 0
        if not t or count < 2 or len(t["heights"]) != count * count:
            return np.zeros(len(points), dtype=bool)
        half, step = t["half"], t["step"]
        if "_grid" not in t:
            t["_grid"] = np.array(t["heights"], dtype=float).reshape(count, count)  # [z][x]
        heights = t["_grid"]
        fx = (points[:, 0] + half) / step
        fz = (points[:, 2] + half) / step
        ix, iz = np.floor(fx).astype(int), np.floor(fz).astype(int)
        inside = (ix >= 0) & (iz >= 0) & (ix < count - 1) & (iz < count - 1)
        result = np.zeros(len(points), dtype=bool)
        if inside.any():
            ix, iz, fx, fz = ix[inside], iz[inside], fx[inside] - ix[inside], fz[inside] - iz[inside]
            corners = np.stack([heights[iz, ix], heights[iz, ix + 1], heights[iz + 1, ix], heights[iz + 1, ix + 1]])
            # (the lowest of the four corners: a slope never hides what's above its low side)
            ground = np.where((corners > -900).all(axis=0), corners.min(axis=0), -np.inf)
            result[inside] = points[inside, 1] < ground - 0.02
        return result

    def hidden(self, points, n, skip):
        near = points + n * 0.02
        far = points + n * COVER_GAP
        result = self.solid_at(near, skip) | self.solid_at(far, skip)
        result |= self.under_terrain(near) | self.under_terrain(far)
        todo = ~result
        if todo.any():
            result[todo] |= self.mesh_in_front(points[todo], n, skip)
        return result


def ray_hits(origins, direction, tris, length):
    """Which origins' rays (origin + t * direction, 0 <= t <= length) hit any of the triangles."""
    if len(origins) == 0 or len(tris) == 0:
        return np.zeros(len(origins), dtype=bool)
    v0, e1, e2 = tris[:, 0], tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0]
    p = np.cross(direction, e2)
    det = (e1 * p).sum(axis=1)
    usable = np.abs(det) > 1e-9
    v0, e1, e2, p, det = v0[usable], e1[usable], e2[usable], p[usable], det[usable]
    hit = np.zeros(len(origins), dtype=bool)
    for start in range(0, len(origins), 64):
        o = origins[start : start + 64, None, :]
        s = o - v0[None]
        a = (s * p[None]).sum(axis=2) / det
        q = np.cross(s, e1[None])
        b = (q * direction).sum(axis=2) / det
        t = (q * e2[None]).sum(axis=2) / det
        ok = (a >= -1e-6) & (b >= -1e-6) & (a + b <= 1 + 1e-6) & (t >= -0.01) & (t <= length)
        hit[start : start + 64] = ok.any(axis=1)
    return hit


# Mesh props, from their .glb (as render.py draws them) ------------------------------------------

GLB_CACHE: dict = {}


def glb_pieces(prop):
    """{piece name: (verts N x 3, triangles T x 3)} from assets/meshes/<prop>.glb."""
    if prop in GLB_CACHE:
        return GLB_CACHE[prop]
    result = {}
    path = MESH_DIR / f"{prop}.glb"
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
            verts, tris, base = [], [], 0
            for prim in mesh["primitives"]:
                v = accessor(prim["attributes"]["POSITION"]).astype(np.float64)
                verts.append(v)
                tris.append(accessor(prim["indices"]).astype(np.int64).reshape(-1, 3) + base)
                base += len(v)
            result[node.get("name") or mesh.get("name")] = (np.concatenate(verts), np.concatenate(tris))
    GLB_CACHE[prop] = result
    return result


def mesh_triangles(part):
    """World-space triangles of a mesh prop's piece, or None if its mesh isn't in assets/meshes."""
    if not part.get("prop"):
        return None
    piece = glb_pieces(part["prop"]).get(part["n"])
    if piece is None:
        return None
    verts, tris = piece
    vmin, vmax = verts.min(0), verts.max(0)
    unit = (verts - (vmin + vmax) / 2) / np.maximum(vmax - vmin, 1e-4)
    # Roblox's glTF import turns each mesh half a turn inside its MeshPart (x -> -x, z -> -z).
    local = np.stack([-unit[:, 0], unit[:, 1], -unit[:, 2]], 1) * np.array(part["s"], dtype=float)
    rot, pos = frame(part["cf"])
    world = local @ rot.T + pos
    return world[tris]


def one_prop(pa, pb):
    """Whether two mesh pieces are of one prop as it was modelled (the same prop, placed the way its
    .glb lays them out): a fight between them is in the mesh itself, not in how the game placed it."""
    if pa["c"] != "MeshPart" or pb["c"] != "MeshPart" or not pa.get("prop") or pa.get("prop") != pb.get("prop"):
        return False
    pieces = glb_pieces(pa["prop"])
    if pa["n"] not in pieces or pb["n"] not in pieces:
        return False
    rot_a, pos_a = frame(pa["cf"])
    rot_b, pos_b = frame(pb["cf"])
    if np.abs(rot_a - rot_b).max() > 1e-3:
        return False
    centres, scales = [], []
    for part in (pa, pb):
        verts = pieces[part["n"]][0]
        vmin, vmax = verts.min(0), verts.max(0)
        c = (vmin + vmax) / 2
        centres.append(np.array([-c[0], c[1], -c[2]]))
        scales.append(np.array(part["s"], dtype=float) / np.maximum(vmax - vmin, 1e-4))
    scale = (scales[0] + scales[1]) / 2
    expected = rot_a @ ((centres[1] - centres[0]) * scale)
    return bool(np.abs(expected - (pos_b - pos_a)).max() < 0.05)


# Coplanar triangles (meshes against meshes and parts) ---------------------------------------------


def basis(n):
    helper = np.array([0.0, 1.0, 0.0]) if abs(n[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    u = np.cross(n, helper)
    u /= np.linalg.norm(u)
    return u, np.cross(n, u)


def clip(poly, tri):
    """Sutherland-Hodgman: the convex polygon `poly` (2D) clipped to the triangle `tri` (2D, any winding)."""
    area = (tri[1][0] - tri[0][0]) * (tri[2][1] - tri[0][1]) - (tri[1][1] - tri[0][1]) * (tri[2][0] - tri[0][0])
    sign = 1 if area > 0 else -1
    out = list(poly)
    for i in range(3):
        a, b = tri[i], tri[(i + 1) % 3]
        inp, out = out, []
        if not inp:
            break

        def side(p):
            return sign * ((b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]))

        for j in range(len(inp)):
            p, q = inp[j], inp[(j + 1) % len(inp)]
            sp, sq = side(p), side(q)
            if sp >= 0:
                out.append(p)
            if (sp >= 0) != (sq >= 0):
                t = sp / (sp - sq)
                out.append((p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1])))
    return out


def polygon_area(poly):
    return 0.5 * abs(sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly))))


def polygon_samples(poly, count=6):
    points = []
    for i in range(1, len(poly) - 1):
        a, b, c = np.array(poly[0]), np.array(poly[i]), np.array(poly[i + 1])
        for s in range(1, count):
            for t in range(1, count - s):
                w = (s / count, t / count)
                points.append(a + w[0] * (b - a) + w[1] * (c - a))
    return np.array(points) if points else np.zeros((0, 2))


def triangle_pairs(entries, eps):
    """Candidate pairs of same-facing triangles from different parts within eps of one plane whose
    footprints overlap by more than a touch. entries: list of (part id, triangles T x 3 x 3)."""
    tris = np.concatenate([t for _, t in entries])
    owner = np.concatenate([np.full(len(t), part_id) for part_id, t in entries])
    cross = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    area = np.linalg.norm(cross, axis=1) / 2
    keep = area > 0.003
    tris, owner, cross, area = tris[keep], owner[keep], cross[keep], area[keep]
    normals = cross / (2 * area[:, None])
    planes = (normals * tris[:, 0]).sum(axis=1)  # each triangle's own plane: normals . x = planes
    rounded, key = np.unique(np.round(normals, 2), axis=0, return_inverse=True)
    key = key.reshape(-1)
    shared = rounded / np.linalg.norm(rounded, axis=1)[:, None]  # one normal per bucket
    # Offsets along the bucket's normal (at the middles: arenas sit far from the origin, so a
    # triangle's own, slightly tilted normal would put its offset studs away from its neighbours').
    offsets = (shared[key] * tris.mean(axis=1)).sum(axis=1)
    # Only triangles with another part's triangle facing the same way within eps can fight.
    combined = key * 100000.0 + offsets
    order = np.argsort(combined, kind="stable")
    sorted_combined, sorted_owner = combined[order], owner[order]
    lo = np.searchsorted(sorted_combined, sorted_combined - eps, "left")
    hi = np.searchsorted(sorted_combined, sorted_combined + eps, "right")
    run = np.concatenate([[0], np.cumsum(sorted_owner[1:] != sorted_owner[:-1])])
    lonely = run[hi - 1] == run[lo]
    order = order[~lonely]
    if len(order) == 0:
        return
    tris, owner, normals, key, offsets = tris[order], owner[order], normals[order], key[order], offsets[order]
    planes = planes[order]
    for bucket in np.unique(key):
        members = np.flatnonzero(key == bucket)
        members = members[np.argsort(offsets[members])]
        n = shared[bucket]
        u, v = basis(n)
        t2 = np.stack([tris[members] @ u, tris[members] @ v], axis=2)  # M x 3 x 2
        box_lo, box_hi = t2.min(axis=1), t2.max(axis=1)
        d = offsets[members]
        who = owner[members]
        ends = np.searchsorted(d, d + eps, "right")
        pairs_a, pairs_b = [], []
        for i in range(len(members)):
            j = np.arange(i + 1, ends[i])
            if len(j) == 0:
                continue
            j = j[who[j] != who[i]]
            j = j[(box_lo[j] < box_hi[i] - 0.02).all(axis=1) & (box_hi[j] > box_lo[i] + 0.02).all(axis=1)]
            pairs_a.append(np.full(len(j), i))
            pairs_b.append(j)
        if not pairs_a:
            continue
        a, b = np.concatenate(pairs_a), np.concatenate(pairs_b)
        if len(a) == 0:
            continue
        # Separating axes (each triangle's edge normals): a pair that only touches is let go.
        ta, tb = t2[a], t2[b]
        apart = np.zeros(len(a), dtype=bool)
        for tri in (ta, tb):
            for k in range(3):
                edge = tri[:, (k + 1) % 3] - tri[:, k]
                axis = np.stack([-edge[:, 1], edge[:, 0]], axis=1)
                axis /= np.maximum(np.linalg.norm(axis, axis=1), 1e-12)[:, None]
                pa = (ta * axis[:, None]).sum(axis=2)
                pb = (tb * axis[:, None]).sum(axis=2)
                apart |= (pa.max(axis=1) <= pb.min(axis=1) + 0.01) | (pb.max(axis=1) <= pa.min(axis=1) + 0.01)
        for i, j in zip(a[~apart], b[~apart]):
            poly = clip([tuple(p) for p in t2[i]], [tuple(p) for p in t2[j]])
            if len(poly) < 3 or polygon_area(poly) < 0.003:
                continue
            mi, mj = members[i], members[j]
            yield (who[i], who[j], n, d[i], d[j], poly, u, v, (normals[mi], planes[mi]), (normals[mj], planes[mj]))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("dump")
    parser.add_argument("--eps", type=float, default=0.025)
    parser.add_argument("--all", action="store_true", help="also list the false alarms, with why")
    parser.add_argument("--no-meshes", action="store_true", help="parts and unions only (the old check)")
    args = parser.parse_args()
    data = load(args.dump)
    everything = data["parts"]
    for index, part in enumerate(everything):
        part["_id"] = index
    opaque = [p for p in everything if p["t"] < 0.6]
    solids = {p["_id"]: Solid(p) for p in opaque if p["c"] != "MeshPart"}
    mesh_tris = {}
    if not args.no_meshes:
        for p in opaque:
            if p["c"] == "MeshPart":
                tris = mesh_triangles(p)
                if tris is not None:
                    mesh_tris[p["_id"]] = tris
    cover_meshes = []
    for part_id, tris in mesh_tris.items():
        if everything[part_id]["t"] > 0.05:
            continue
        e = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
        norm = np.linalg.norm(e, axis=1)
        good = norm > 1e-9
        cover_meshes.append((part_id, tris[good], e[good] / norm[good, None], tris[good].min(axis=1), tris[good].max(axis=1)))
    covers = Covers([s for s in solids.values() if s.part["t"] <= 0.05], cover_meshes, data.get("terrain"))

    found = {}

    def surface(index, points, n, u, v, plane):
        """Offsets along n from `points` to part `index`'s surface there (a mesh's: its triangle's plane)."""
        if index in solids:
            return solids[index].flat_surface(points, n, u, v)
        if plane is None:
            return np.zeros(len(points))
        normal, offset = plane
        along = float(np.dot(normal, n))
        return (offset - points @ normal) / along if abs(along) > 1e-6 else np.full(len(points), np.nan)

    def verdict_for(ia, ib, n, points_a, sep, u, v, plane_a=None, plane_b=None):
        """'real' or why not, for spots `points_a` on A's plane (B's plane is `sep` further along n)."""
        pa, pb = everything[ia], everything[ib]
        offset_a = surface(ia, points_a, n, u, v, plane_a)
        points_b = points_a + n * sep
        offset_b = surface(ib, points_b, n, u, v, plane_b)
        both = ~np.isnan(offset_a) & ~np.isnan(offset_b)
        both &= np.abs(sep + offset_b - offset_a) <= args.eps
        if not both.any():
            return "not on the drawn shape (round, sloped or cut where the box has a face)"
        outer = points_a[both] + n * np.maximum(offset_a[both], sep + offset_b[both])[:, None]
        if covers.hidden(outer, n, {ia, ib}).all():
            return "hidden (pressed against something solid)"
        if pa["col"] == pb["col"] and pa["m"] == pb["m"] and pa["m"] in PLAIN:
            return "same colour and material (looks the same whichever wins)"
        if one_prop(pa, pb):
            return "in the mesh"
        return "real"

    def record(ia, ib, n, sep, verdict):
        pa, pb = everything[ia], everything[ib]
        pair = tuple(sorted((label(pa), label(pb))))
        key = tuple(round(float(c), 2) + 0.0 for c in n)
        if pair not in found or (found[pair][0] != "real" and verdict == "real"):
            found[pair] = (verdict, f"{abs(sep):.3f}  normal {key}  {pair[0]}  <->  {pair[1]}")

    # Parts and unions: their box faces.
    flat_parts = [p for p in opaque if p.get("shape") != "Ball" and p["c"] != "MeshPart"]
    buckets = defaultdict(list)
    for part in flat_parts:
        for face in faces(part):
            n, center, _ = face
            key = tuple(round(c, 2) for c in n)
            buckets[key].append((part["_id"], dot(n, center), face))
    for key, items in buckets.items():
        items.sort(key=lambda item: item[1])
        for a in range(len(items)):
            for b in range(a + 1, len(items)):
                ia, da, fa = items[a]
                ib, db, fb = items[b]
                if db - da > args.eps:
                    break
                if ia == ib or not overlap(fa, fb):
                    continue
                points = samples(fa, fb)
                n = np.array(fa[0])
                if len(points) == 0:
                    continue
                (u, _), (v, _) = fa[2]
                record(ia, ib, n, db - da, verdict_for(ia, ib, n, points, db - da, np.array(u), np.array(v)))

    # Meshes: their triangles, against each other and against the parts' box faces.
    if mesh_tris:
        entries = [(part_id, tris) for part_id, tris in mesh_tris.items()]
        for part in flat_parts:
            quads = []
            for n, center, ((u, hu), (v, hv)) in faces(part):
                c, u, v = np.array(center), np.array(u) * hu, np.array(v) * hv
                corners = [c - u - v, c + u - v, c + u + v, c - u + v]
                # wound so the triangle's normal is the face's
                if np.dot(np.cross(corners[1] - corners[0], corners[2] - corners[0]), n) < 0:
                    corners = corners[::-1]
                quads += [[corners[0], corners[1], corners[2]], [corners[0], corners[2], corners[3]]]
            entries.append((-1 - part["_id"], np.array(quads)))  # (negative: a part's face)
        for oa, ob, n, da, db, poly, u, v, plane_a, plane_b in triangle_pairs(entries, args.eps):
            if oa < 0 and ob < 0:
                continue  # part against part: checked above
            ia, ib = (oa if oa >= 0 else -1 - oa), (ob if ob >= 0 else -1 - ob)
            if ia == ib:
                continue
            flat = polygon_samples(poly)
            points = flat[:, :1] * u + flat[:, 1:] * v + n * da
            # (a part's side is checked against its own shape; a mesh's against its triangle's plane)
            record(ia, ib, n, db - da, verdict_for(ia, ib, n, points, db - da, u, v, plane_a, plane_b))

    real = sorted(line for verdict, line in found.values() if verdict == "real")
    in_mesh = sorted(line for verdict, line in found.values() if verdict == "in the mesh")
    false = sorted((line, verdict) for verdict, line in found.values() if verdict not in ("real", "in the mesh"))
    for line in real:
        print(line)
    if args.all:
        for line in in_mesh:
            print(f"{line}   [in one prop's own mesh: fix its tools/meshgen script, rebuild and upload it]")
        for line, verdict in false:
            print(f"{line}   [false alarm: {verdict}]")
    more = "" if args.all else ": --all lists them"
    print(f"{len(real)} flickering face pairs ({len(in_mesh)} more inside mesh props' own pieces, {len(false)} false alarms{more})")


def samples(face_a, face_b, count=24):
    """Points on face A's rectangle that are also inside face B's footprint."""
    (_, ca, ea), (_, cb, eb) = face_a, face_b
    ca, cb = np.array(ca), np.array(cb)
    (ua, hua), (va, hva) = ea
    ua, va = np.array(ua), np.array(va)
    (ub, hub), (vb, hvb) = eb
    ub, vb = np.array(ub), np.array(vb)
    # B's corners in A's (u, v): the overlap lies inside that range.
    corners = [cb + su * hub * ub + sv * hvb * vb for su in (-1, 1) for sv in (-1, 1)]
    us = [np.dot(c - ca, ua) for c in corners]
    vs = [np.dot(c - ca, va) for c in corners]
    u0, u1 = max(-hua, min(us)), min(hua, max(us))
    v0, v1 = max(-hva, min(vs)), min(hva, max(vs))
    if u1 <= u0 or v1 <= v0:
        return np.zeros((0, 3))
    uu, vv = np.meshgrid(np.linspace(u0, u1, count + 2)[1:-1], np.linspace(v0, v1, count + 2)[1:-1])
    points = ca + uu.reshape(-1, 1) * ua + vv.reshape(-1, 1) * va
    rel = points - cb
    return points[(np.abs(rel @ ub) < hub) & (np.abs(rel @ vb) < hvb)]


if __name__ == "__main__":
    main()
