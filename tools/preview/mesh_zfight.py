"""Finds z-fighting inside our own meshes: two shapes of one prop, as it was modelled, with faces in
the same plane facing the same way and overlapping, so they flicker in game whichever way the prop is
placed (owner, on what gives an AI-built game away: "Z Fighting ... overlapping parts that look like
they flicker when you move the camera"). tools/preview/zfight.py finds them in a world dump and counts
them apart ("inside a mesh"); this checks the .glb files themselves, so a fixed generator can be
checked before anything is uploaded.

    python3 tools/preview/mesh_zfight.py                       # every mesh in assets/meshes
    python3 tools/preview/mesh_zfight.py PrimeCutFence Crate   # these
    python3 tools/preview/mesh_zfight.py --top 30              # the worst 30, worst first

A "shape" is a piece's connected run of triangles (a box, a lathe, a tube), so two boxes merged into
one piece count as two. A spot only counts where it can be seen: not where the face is buried inside
another closed shape of the prop (two blocks sunk into each other), and not a sliver under 0.003
square studs, nor bottoms within 0.1 of the ground the prop stands on (its lowest point). --eps (default 0.02 studs: tools/meshgen/unfight.py keeps a mesh's own faces 0.03 apart, which is
enough and keeps its shape; 0.1 swelled layered props) is
how far apart two faces may be and still fight.
"""

import argparse
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from zfight import MESH_DIR, glb_pieces, polygon_samples, triangle_pairs  # noqa: E402


def components(tris: np.ndarray) -> np.ndarray:
    """Labels each triangle with its connected run (triangles sharing a vertex index)."""
    parent = list(range(int(tris.max()) + 1)) if len(tris) else []

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for a, b, c in tris:
        for x, y in ((a, b), (b, c)):
            rx, ry = find(int(x)), find(int(y))
            if rx != ry:
                parent[rx] = ry
    roots = np.array([find(int(t[0])) for t in tris])
    _, labels = np.unique(roots, return_inverse=True)
    return labels


def merge_welded(verts: np.ndarray, tris: np.ndarray) -> np.ndarray:
    """The triangles with vertices at one spot (to 1e-4) sharing an index: generators often split
    vertices for flat shading, which would break a box into six 'shapes'."""
    _, inverse = np.unique(np.round(verts, 4), axis=0, return_inverse=True)
    return inverse.reshape(-1)[tris]


def inside(points: np.ndarray, tris: np.ndarray) -> np.ndarray:
    """Whether each point is inside the closed surface `tris` (T x 3 x 3), by ray parity along a
    skewed direction (so it doesn't graze edges)."""
    if len(points) == 0 or len(tris) == 0:
        return np.zeros(len(points), dtype=bool)
    direction = np.array([0.5773, 0.5774, 0.5775])
    v0, e1, e2 = tris[:, 0], tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0]
    h = np.cross(direction, e2)
    det = (e1 * h).sum(1)
    ok = np.abs(det) > 1e-12
    inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
    result = np.zeros(len(points), dtype=bool)
    for i, origin in enumerate(points):
        s = origin - v0
        u = (s * h).sum(1) * inv
        q = np.cross(s, e1)
        v = (q @ direction) * inv
        t = (q * e2).sum(1) * inv
        hits = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 1e-6)
        result[i] = int(hits.sum()) % 2 == 1
    return result


def polygon_area(poly):
    return 0.5 * abs(sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
                         for i in range(len(poly))))


def shapes_of(pieces: dict) -> list:
    """[(name, piece, triangle indices into that piece)] for {piece: (verts, tris)}: each piece's
    connected runs of triangles."""
    shapes = []
    for name, (verts, tris) in pieces.items():
        labels = components(merge_welded(verts, tris))
        count = labels.max() + 1 if len(labels) else 0
        for k in range(count):
            shapes.append((f"{name}#{k + 1}" if count > 1 else name, name, np.flatnonzero(labels == k)))
    return shapes


def fights(pieces: dict, shapes: list, eps: float):
    """{(shape a, shape b): (seen area, [(normal, a's plane, b's plane)])} for the shapes of `pieces`
    that fight where it can be seen (a plane is its offset along the normal)."""
    if len(shapes) < 2:
        return {}
    tri_sets = [pieces[piece][0][pieces[piece][1][idx]] for _, piece, idx in shapes]
    base = min(float(t[..., 1].min()) for t in tri_sets)
    found = {}
    for item in triangle_pairs(list(enumerate(tri_sets)), eps):
        a, b, n, d, d_b, poly, u, v = item[:8]
        if n[1] < -0.95 and -d - base < 0.11:
            continue  # (bottoms on or just over the ground the prop stands on: never seen)
        samples = polygon_samples(poly, 5)
        if len(samples) == 0:
            continue
        # The spots in 3D, a hair in front of the faces; a spot inside another closed shape is buried.
        points = samples[:, :1] * u + samples[:, 1:2] * v + n * (d + 0.01)
        seen = np.ones(len(points), dtype=bool)
        for k, tris in enumerate(tri_sets):
            if k in (a, b) or not seen.any():
                continue
            seen &= ~inside(points, tris)
        if seen.any():
            area, planes = found.get((a, b), (0.0, []))
            found[(a, b)] = (area + polygon_area(poly) * seen.mean(), planes + [(tuple(n), float(d), float(d_b))])
    return {pair: value for pair, value in found.items() if value[0] >= 0.003}


def check(prop: str, eps: float):
    """[(shape a, shape b, visible area)] for one prop's .glb."""
    pieces = glb_pieces(prop)
    shapes = shapes_of(pieces)
    return [(shapes[a][0], shapes[b][0], value[0]) for (a, b), value in fights(pieces, shapes, eps).items()]


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("props", nargs="*")
    parser.add_argument("--eps", type=float, default=0.02)
    parser.add_argument("--top", type=int, default=0)
    args = parser.parse_args()
    props = args.props or sorted(p.stem for p in MESH_DIR.glob("*.glb"))
    results = []
    for prop in props:
        pairs = check(prop, args.eps)
        if pairs:
            results.append((sum(p[2] for p in pairs), prop, pairs))
    results.sort(reverse=True)
    if args.top:
        results = results[: args.top]
    # (The props unfight.py leaves as built on purpose are listed apart: see its NO_SEPARATE.)
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "meshgen"))
    from unfight import NO_SEPARATE

    kept = [r for r in results if r[1] in NO_SEPARATE]
    results = [r for r in results if r[1] not in NO_SEPARATE]
    for total, prop, pairs in results:
        print(f"{prop}: {len(pairs)} pair(s), {total:.2f} sq studs")
        for a, b, area in sorted(pairs, key=lambda p: -p[2])[:8]:
            print(f"    {a}  x  {b}  ({area:.3f})")
    if kept:
        print(f"left as built on purpose (unfight.NO_SEPARATE): {', '.join(r[1] for r in kept)}")
    print(f"{len(results)} mesh(es) with fights")


if __name__ == "__main__":
    main()
