"""Finds inside-out prop meshes: closed parts whose faces point inward. Roblox only draws the front of
a mesh face, so an inside-out part shows its far wall's inside, lit from the wrong side (dark,
hollow-looking props); open sheets like flags and leaves are left alone.

    python3 tools/checks/mesh_orientation.py                   # every assets/meshes/*.glb
    python3 tools/checks/mesh_orientation.py assets/meshes/Bee.glb ...

generate_meshes.py warns about the same thing as it writes each prop. Exits with status 1 if any
prop has an inside-out part; fix its builder (see tools/meshgen/props/README.md), regenerate and
re-upload it.
"""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]


def read_glb(path: Path) -> dict[str, tuple[np.ndarray, np.ndarray]]:
    """{piece name: (positions, triangles)} from a glb written by generate_meshes.py."""
    data = path.read_bytes()
    json_length = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20 : 20 + json_length])
    binary = data[20 + json_length + 8 :]

    def accessor(index: int) -> np.ndarray:
        info = gltf["accessors"][index]
        view = gltf["bufferViews"][info["bufferView"]]
        dtype = {5126: "<f4", 5125: "<u4", 5123: "<u2"}[info["componentType"]]
        width = 3 if info["type"] == "VEC3" else 1
        offset = view.get("byteOffset", 0) + info.get("byteOffset", 0)
        return np.frombuffer(binary, dtype=dtype, count=info["count"] * width, offset=offset).reshape(-1, width)

    pieces = {}
    for mesh in gltf["meshes"]:
        primitive = mesh["primitives"][0]
        positions = accessor(primitive["attributes"]["POSITION"]).astype(np.float64)
        triangles = accessor(primitive["indices"]).reshape(-1, 3).astype(np.int64)
        pieces[mesh["name"]] = (positions, triangles)
    return pieces


def inside_out_parts(positions: np.ndarray, triangles: np.ndarray) -> tuple[int, int]:
    """(inside-out closed parts, closed parts) of one piece. A part is a connected, watertight
    group of triangles; its signed volume is negative when its faces point inward. A part whose
    faces don't all agree (each edge must run one way in one face and the other way in its
    neighbour) is partly inside-out whatever its volume: the referee's flag had its two big faces
    turned in and its thin edges out, which reads as a positive volume but renders black."""
    # Flat-shaded pieces repeat each corner per face, so join corners by position first.
    _, corner = np.unique(np.round(positions / 1e-4).astype(np.int64), axis=0, return_inverse=True)
    faces = corner.reshape(-1)[triangles]
    parent = list(range(int(faces.max()) + 1 if len(faces) else 0))

    def root(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for a, b, c in faces:
        parent[root(b)] = root(a)
        parent[root(c)] = root(a)
    part_of = np.array([root(a) for a in faces[:, 0]])
    closed = bad = 0
    for part in np.unique(part_of):
        mine = part_of == part
        edges: dict[tuple[int, int], int] = {}
        forward: dict[tuple[int, int], int] = {}  # times each edge runs from its lower corner up
        for a, b, c in faces[mine]:
            for edge in ((a, b), (b, c), (c, a)):
                key = (min(edge), max(edge))
                edges[key] = edges.get(key, 0) + 1
                forward[key] = forward.get(key, 0) + (edge[0] < edge[1])
        if any(count != 2 for count in edges.values()):
            continue  # an open sheet (flag, leaf, decal): it faces whichever way its builder chose
        closed += 1
        if any(count != 1 for count in forward.values()):
            bad += 1  # some faces point in, some out
            continue
        tri = positions[triangles[mine]]
        tri = tri - tri.reshape(-1, 3).mean(axis=0)
        volume = np.einsum("ij,ij->i", tri[:, 0], np.cross(tri[:, 1], tri[:, 2])).sum() / 6
        if volume < 0:
            bad += 1
    return bad, closed


def main() -> int:
    paths = [Path(arg) for arg in sys.argv[1:]] or sorted((ROOT / "assets" / "meshes").glob("*.glb"))
    problems = 0
    for path in paths:
        for piece, (positions, triangles) in read_glb(path).items():
            bad, closed = inside_out_parts(positions, triangles)
            if bad:
                problems += 1
                print(f"{path.stem}.{piece}: {bad} of {closed} closed parts are inside-out")
    print(f"{len(paths)} props checked, {problems} inside-out pieces")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
