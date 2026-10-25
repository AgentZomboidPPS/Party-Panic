"""Finds things that hover a little over what they should stand on, from the world dumps zfight.py
reads (tools/preview/dump_world.luau for the lobby, round_harness.py --dump-at for an arena).

    python3 tools/preview/resting.py dump.json [--min 0.08] [--max 2.5] [--all]

Owner: "Make sure everything is super nice. No clipping stuff like that." A crate standing a hand's
width over the floor, a fence post that stops short of the grass, a lamp over its base: the eye
catches the gap at once. An earlier pass found five by hand in the lobby (leaf heaps on the booth
and the patio, Mecha Marathon's boards over the grass); this does it for any dump.

For every opaque part and mesh piece standing upright (a part whose bottom face is level; a mesh
piece: the points of its lowest triangles), it samples its bottom and looks straight down at
everything else that's drawn: parts (unions from their recorded pieces), mesh triangles
(assets/meshes) and the terrain. A thing is FLOATING when no sample touches anything (within --min)
but something lies under all of them within --max: a gap you can see. Things with nothing under
them within --max hang on purpose (signs, clouds, balloons, lamps on a wall) and aren't listed,
unless --all. Each line says how big the gap is and what's under it, so a fix can move the thing
down by exactly that.

What it can't tell: a thing held up from the side (a shelf on a wall, a sign on a post next to it)
reads as floating over the floor far below only if that floor is within --max; and a thing that
stands on something moving (a slide, a turning disc) is judged where the dump caught it.
"""

import argparse
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from zfight import Solid, frame, load, mesh_triangles, one_prop  # noqa: E402  (the same shapes zfight checks)

SMALLEST = 0.4  # a thing smaller than this every way is a detail (a rivet, a petal): not checked
SAMPLES = 5  # bottom samples per side of a part (SAMPLES x SAMPLES)
TERRAIN = -2  # what's under a sample: a part's index in the dump, or the terrain
THIN, THIN_LIFT = 0.35, 0.22  # a piece this thin or less may sit this far over what it lies on


def down_hits(origins, tris, length):
    """For each origin, how far straight down the nearest triangle is (inf if none within length)."""
    best = np.full(len(origins), np.inf)
    if len(origins) == 0 or len(tris) == 0:
        return best
    direction = np.array([0.0, -1.0, 0.0])
    v0, e1, e2 = tris[:, 0], tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0]
    p = np.cross(direction, e2)
    det = (e1 * p).sum(axis=1)
    usable = np.abs(det) > 1e-9
    if not usable.any():
        return best  # (every triangle stands edge-on to a ray straight down)
    v0, e1, e2, p, det = v0[usable], e1[usable], e2[usable], p[usable], det[usable]
    for start in range(0, len(origins), 64):
        o = origins[start : start + 64, None, :]
        s = o - v0[None]
        a = (s * p[None]).sum(axis=2) / det
        q = np.cross(s, e1[None])
        b = (q * direction).sum(axis=2) / det
        t = (q * e2[None]).sum(axis=2) / det
        ok = (a >= -1e-6) & (b >= -1e-6) & (a + b <= 1 + 1e-6) & (t >= -0.02) & (t <= length)
        t = np.where(ok, np.maximum(t, 0), np.inf)
        best[start : start + 64] = np.minimum(best[start : start + 64], t.min(axis=1))
    return best


def terrain_height(terrain, points):
    """The terrain's surface height under each point (-inf where there's none)."""
    out = np.full(len(points), -np.inf)
    if not terrain or not terrain.get("step"):
        return out
    half, step = terrain["half"], terrain["step"]
    count = int(round(2 * half / step)) + 1
    if len(terrain["heights"]) != count * count:
        return out
    grid = np.array(terrain["heights"], dtype=float).reshape(count, count)  # [z][x]
    fx, fz = (points[:, 0] + half) / step, (points[:, 2] + half) / step
    ix, iz = np.floor(fx).astype(int), np.floor(fz).astype(int)
    inside = (ix >= 0) & (iz >= 0) & (ix < count - 1) & (iz < count - 1)
    if inside.any():
        ix, iz = ix[inside], iz[inside]
        fx, fz = fx[inside] - ix, fz[inside] - iz
        h00, h10, h01, h11 = grid[iz, ix], grid[iz, ix + 1], grid[iz + 1, ix], grid[iz + 1, ix + 1]
        h = h00 * (1 - fx) * (1 - fz) + h10 * fx * (1 - fz) + h01 * (1 - fx) * fz + h11 * fx * fz
        valid = np.minimum.reduce([h00, h10, h01, h11]) > -900
        out[np.flatnonzero(inside)[valid]] = h[valid]
    return out


def bottom_points(part):
    """Sample points on a part's bottom face, if it stands upright (its lowest face is level)."""
    rot, pos = frame(part["cf"])
    size = np.array(part["s"], dtype=float)
    kind = "Wedge" if part["c"] == "WedgePart" else part.get("shape", "Block")
    if part.get("shape") == "Cylinder":
        d = min(size[1], size[2])
        size = np.array([size[0], d, d])
    # The axis pointing most nearly down.
    axis = int(np.argmax(np.abs(rot[1, :])))
    if abs(rot[1, axis]) < 0.995:
        return None
    sign = -np.sign(rot[1, axis])
    if kind == "Ball":
        return None
    if kind == "Cylinder" and axis != 0:
        return None  # lying on its round side: it touches along a line, not a face
    if kind == "Wedge" and not (axis == 1 and sign < 0):
        return None
    others = [i for i in range(3) if i != axis]
    grid = (np.arange(SAMPLES) + 0.5) / SAMPLES * 2 - 1
    u, v = np.meshgrid(grid * 0.9, grid * 0.9)
    local = np.zeros((u.size, 3))
    local[:, axis] = sign * size[axis] / 2
    local[:, others[0]] = u.ravel() * size[others[0]] / 2
    local[:, others[1]] = v.ravel() * size[others[1]] / 2
    if kind == "Cylinder":
        keep = local[:, 1] ** 2 + local[:, 2] ** 2 <= (size[1] / 2) ** 2
        local = local[keep]
    return local @ rot.T + pos


def mesh_bottom(tris):
    """Points on a mesh piece's lowest level, flat triangles (its feet), if it has some."""
    ys = tris[:, :, 1]
    low = ys.min()
    flat = (ys.max(axis=1) - ys.min(axis=1) < 0.02) & (ys.min(axis=1) < low + 0.05)
    if not flat.any():
        return None
    centres = tris[flat].mean(axis=1)
    corners = tris[flat].reshape(-1, 3)
    points = np.concatenate([centres, corners * 0.8 + np.repeat(centres, 3, axis=0) * 0.2])
    if len(points) > 60:
        points = points[np.linspace(0, len(points) - 1, 60).astype(int)]
    return points


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("dump")
    parser.add_argument("--min", type=float, default=0.08, help="a gap smaller than this counts as touching")
    parser.add_argument("--max", type=float, default=2.5, help="a gap bigger than this is hanging on purpose")
    parser.add_argument("--all", action="store_true", help="also list what hangs with nothing under it")
    args = parser.parse_args()
    data = load(args.dump)
    everything = data["parts"]
    for index, part in enumerate(everything):
        part["_id"] = index
    opaque = [p for p in everything if p["t"] < 0.6]
    solids = [Solid(p) for p in opaque if p["c"] != "MeshPart"]
    meshes = {}
    for p in opaque:
        if p["c"] == "MeshPart":
            tris = mesh_triangles(p)
            if tris is not None:
                meshes[p["_id"]] = tris
    terrain = data.get("terrain")
    step = 0.02
    depths = np.arange(step, args.max + step, step)

    def gap_under(points, skip: set):
        """The gap straight down from each point to the nearest drawn thing, and its name."""
        gap = np.full(len(points), np.inf)
        what = np.full(len(points), -1, dtype=int)
        lo = points.min(axis=0) - np.array([0.05, args.max + 0.05, 0.05])
        hi = points.max(axis=0) + 0.05
        for solid in solids:
            if solid.part["_id"] in skip or (solid.lo > hi).any() or (solid.hi < lo).any():
                continue
            # (the first depth, stepping down, at which each point is inside this solid)
            column = (points[:, None, :] - depths[None, :, None] * np.array([0, 1, 0])).reshape(-1, 3)
            inside = solid.inside(column, box_if_unknown=True).reshape(len(points), len(depths))
            first = np.where(inside.any(axis=1), depths[np.argmax(inside, axis=1)] - step, np.inf)
            closer = first < gap
            gap[closer], what[closer] = first[closer], solid.part["_id"]
        for part_id, tris in meshes.items():
            if part_id in skip:
                continue
            tlo, thi = tris.reshape(-1, 3).min(0), tris.reshape(-1, 3).max(0)
            if (tlo > hi).any() or (thi < lo).any():
                continue
            t = down_hits(points, tris, args.max)
            closer = t < gap
            gap[closer], what[closer] = t[closer], part_id
        ground = points[:, 1] - terrain_height(terrain, points)
        closer = (ground >= -0.05) & (ground < gap)
        gap[closer], what[closer] = np.maximum(ground[closer], 0), TERRAIN
        return gap, what

    # Mesh props are judged whole: the pieces of one placed prop (zfight.one_prop) stand or float
    # together, on the piece(s) at its lowest point (a fence's rails hang between its posts).
    owner = {}
    by_prop = {}
    for part in opaque:
        if part["_id"] in meshes:
            by_prop.setdefault(part["prop"], []).append(part)
    for pieces in by_prop.values():
        for index, a in enumerate(pieces):
            group = owner.setdefault(a["_id"], {a["_id"]})
            for b in pieces[index + 1 :]:
                if b["_id"] not in group and one_prop(a, b):
                    merged = group | owner.get(b["_id"], {b["_id"]})
                    for member in merged:
                        owner[member] = merged
                    group = merged
    seen_groups = set()

    found = []
    for part in opaque:
        if max(part["s"]) < SMALLEST:
            continue
        skip = {part["_id"]}
        if part["c"] == "MeshPart":
            group = owner.get(part["_id"])
            if group is None or id(group) in seen_groups:
                continue
            seen_groups.add(id(group))
            skip = group
            low = min(float(meshes[i][:, :, 1].min()) for i in group)
            feet = [meshes[i] for i in group if float(meshes[i][:, :, 1].min()) < low + 0.05]
            points = mesh_bottom(np.concatenate(feet))
        else:
            points = bottom_points(part)
        if points is None or len(points) == 0:
            continue
        points = points + np.array([0, 0.005, 0])
        gap, what = gap_under(points, skip)
        # A thin piece (a stripe, a decal-like board) is lifted a little on purpose, so it can't
        # flicker with what it lies on (the game keeps faces 0.1 apart); that reads as painted on.
        tall = part["s"][1] if part["c"] != "MeshPart" else max(float(np.ptp(meshes[i][:, :, 1])) for i in skip)
        touching = args.min if tall > THIN else THIN_LIFT
        if (gap <= touching).any():
            continue  # it touches something
        under = np.isfinite(gap)
        if not under.all():
            if args.all and not under.any():
                found.append(("HANGS", np.inf, part, ""))
            continue
        ids = set(int(i) for i in what[under])
        names = sorted({"terrain" if i == TERRAIN else everything[i]["n"] for i in ids})
        found.append(("FLOATING", float(gap.min()), part, ", ".join(names[:3])))
    found.sort(key=lambda item: (item[0], -item[1] if np.isfinite(item[1]) else 0))
    for kind, gap, part, under in found:
        where = [round(v, 2) for v in part["cf"][:3]]
        prop = f" ({part['prop']})" if part.get("prop") else ""
        if kind == "FLOATING":
            print(f"FLOATING {gap:.2f} over {under}: {part['n']}{prop} @ {where} size {[round(s, 2) for s in part['s']]}")
        else:
            print(f"HANGS: {part['n']}{prop} @ {where}")
    print(f"{sum(1 for f in found if f[0] == 'FLOATING')} floating")


if __name__ == "__main__":
    main()
