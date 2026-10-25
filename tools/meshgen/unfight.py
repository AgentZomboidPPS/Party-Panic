"""Takes the z-fighting out of our meshes (owner, on what gives an AI-built game away: "Z Fighting ...
overlapping parts that look like they flicker when you move the camera", then "lets fix those right
now"). Where two shapes of a prop have faces in one plane, facing the same way and overlapping where
it can be seen (tools/preview/mesh_zfight.py finds them), the smaller shape's face moves out along its
normal to GAP studs in front of the face it fought (its points on that plane; the rest of it stays),
so it's in front and wins every
frame instead of flickering: a stripe, an emblem or a trim strip flush with the surface it's on stands
a hair proud of it (GAP, 0.03), a picket overlapping the next gets a hair thicker front and back. It
goes round again until nothing fights (or ROUNDS runs out).

    python3 tools/meshgen/unfight.py                   # every .glb in assets/meshes, fixed in place
    python3 tools/meshgen/unfight.py PrimeCutFence Crate
    python3 tools/meshgen/unfight.py --check           # only say what would move

generate_meshes.py runs the same thing on every prop it builds (separate_meshes), so a regenerated
mesh comes out fixed too. A fixed file gets its .obj rewritten from it (Studio's importer); the mesh
must then be uploaded again (tools/upload_assets.py: AssetId = 0 in its World/Props file, or its key
out of assets/uploaded.json) for the game to show it.
"""

from __future__ import annotations

import json
import struct
import sys
from collections import defaultdict
from multiprocessing import Pool
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
MESH_DIR = ROOT / "assets" / "meshes"
sys.path.insert(0, str(ROOT / "tools" / "preview"))
from mesh_zfight import fights, shapes_of  # noqa: E402

# A hair is enough: faces 0.03 apart don't flicker at the distances the game is seen from (a depth
# buffer tells them apart to a few thousandths of a stud at 100 studs). It was 0.1 with faces closer
# than 0.08 fighting, and that broke things (owner, with screenshots: "Eatsa Pizza is bugged.", "the
# circles on the ground arent on the top of the pizza they are below it"): pushes of 0.1 a round, up to
# 8 rounds, stacked through layered props, so the pizza's cheese rose 0.3-0.7 over its toppings and
# pepperoni, bunting flags grew five times thicker, Shark Bait's floatie went from 1 to 2.7 tall and
# Prime Cut's steaks doubled; and a prop more than 5% taller than its spec's Height is scaled down to it
# (MeshLibrary.normalize), so they were drawn shrunk too. 51 of the 145 props it moved changed size by
# more than 5%; with these values almost none moves more than a few hundredths (NO_SEPARATE lists the
# ones it still can't help).
GAP = 0.03  # studs a face moves out per round
EPS = 0.02  # faces closer than this fight (mesh_zfight's default)
ROUNDS = 8
# Props left exactly as built: a push here changes them more than the fights it'd cure. The pizza
# slices' layers fight only on their cut sides (bands seen edge-on between slices), and pushing them
# widens the slice past its wedge; the floatie's stripes hug a curved ring, which a push makes a fifth
# taller (and so drawn smaller); the dough sheet's two fighting flour flecks are one colour.
NO_SEPARATE = {
    "EatsaPizzaSlice",
    "EatsaPizzaSlice1",
    "EatsaPizzaSlice2",
    "EatsaPizzaSlice3",
    "SharkBaitFloatie",
    "DoughSheet",
}


def separate(pieces: dict) -> tuple[dict, int, int]:
    """{piece: (verts, tris)} -> ({piece: new verts}, fights before, fights after)."""
    verts = {name: np.array(v, dtype=np.float64) for name, (v, _) in pieces.items()}
    work = {name: (verts[name], t) for name, (_, t) in pieces.items()}
    shapes = shapes_of(work)
    owned = [np.unique(work[piece][1][idx]) for _, piece, idx in shapes]

    def bulk(k):
        piece = shapes[k][1]
        points = verts[piece][owned[k]]
        return float(np.prod(np.maximum(points.max(0) - points.min(0), 0.05)))

    found = fights(work, shapes, EPS)
    before = len(found)
    for _ in range(ROUNDS):
        if not found:
            break
        # One shape of each pair moves (the smaller; never both, or they'd stay level): biggest
        # fights first, and a pair one of whose shapes is already moving this round is left to it.
        push = defaultdict(set)
        for (a, b), (_, planes) in sorted(found.items(), key=lambda item: -item[1][0]):
            if a in push or b in push:
                mover = a if a in push else b
            else:
                mover = a if bulk(a) <= bulk(b) else b
            for n, plane_a, plane_b in planes:
                mine, theirs = (plane_a, plane_b) if mover == a else (plane_b, plane_a)
                push[mover].add((tuple(np.round(n, 3)), round(mine, 3), round(theirs, 3)))
        # The mover's fighting face itself goes out along its normal to GAP in front of the face it
        # fought (of the furthest out, if it fought several): its points on that plane move, the rest
        # stay (a stripe gets a hair thicker, a slanted side a hair wider).
        for k, faces in push.items():
            piece = shapes[k][1]
            points = verts[piece][owned[k]]
            moved = points.copy()
            shifts = defaultdict(float)
            for n, mine, theirs in faces:
                shifts[(n, mine)] = max(shifts[(n, mine)], theirs + GAP - mine, 0.0)
            for (n, mine), shift in shifts.items():
                n = np.array(n) / np.linalg.norm(n)
                on_face = np.abs(points @ n - mine) < 0.02
                moved[on_face] += n * shift
            verts[piece][owned[k]] = moved
        found = fights(work, shapes, EPS)
    return verts, before, len(found)


def separate_meshes(pieces: dict) -> dict:
    """generate_meshes.py's hook: the same on its {piece: Mesh}, in place. Returns the pieces."""
    plain = {name: (mesh.v, mesh.f) for name, mesh in pieces.items()}
    fixed, _, _ = separate(plain)
    for name, mesh in pieces.items():
        mesh.v = fixed[name]
    return pieces


def read_glb(path: Path):
    data = path.read_bytes()
    json_len = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20 : 20 + json_len])
    bin_len = struct.unpack_from("<I", data, 20 + json_len)[0]
    blob = bytearray(data[20 + json_len + 8 : 20 + json_len + 8 + bin_len])
    return doc, blob


def write_glb(path: Path, doc: dict, blob: bytearray):
    json_bytes = json.dumps(doc, separators=(",", ":")).encode()
    while len(json_bytes) % 4:
        json_bytes += b" "
    while len(blob) % 4:
        blob.append(0)
    total = 12 + 8 + len(json_bytes) + 8 + len(blob)
    with open(path, "wb") as handle:
        handle.write(struct.pack("<III", 0x46546C67, 2, total))
        handle.write(struct.pack("<II", len(json_bytes), 0x4E4F534A))
        handle.write(json_bytes)
        handle.write(struct.pack("<II", len(blob), 0x004E4942))
        handle.write(bytes(blob))


def accessor_array(doc, blob, index):
    acc = doc["accessors"][index]
    view = doc["bufferViews"][acc["bufferView"]]
    comps = {"SCALAR": 1, "VEC3": 3}[acc["type"]]
    dtype = {5126: np.float32, 5125: np.uint32, 5123: np.uint16}[acc["componentType"]]
    offset = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    arr = np.frombuffer(bytes(blob), dtype=dtype, count=acc["count"] * comps, offset=offset)
    return (arr.reshape(acc["count"], comps) if comps > 1 else arr), offset


def fix_file(name: str, check_only: bool = False) -> tuple[str, int, int]:
    if name in NO_SEPARATE:
        return name, 0, 0
    path = MESH_DIR / f"{name}.glb"
    doc, blob = read_glb(path)
    pieces, where = {}, {}
    for node in doc.get("nodes", []):
        if "mesh" not in node:
            continue
        mesh = doc["meshes"][node["mesh"]]
        if len(mesh["primitives"]) != 1:
            return name, -1, -1  # (not one of ours: generate_meshes writes one primitive a piece)
        prim = mesh["primitives"][0]
        positions, offset = accessor_array(doc, blob, prim["attributes"]["POSITION"])
        indices, _ = accessor_array(doc, blob, prim["indices"])
        piece = node.get("name") or mesh.get("name")
        pieces[piece] = (positions.astype(np.float64), indices.astype(np.int64).reshape(-1, 3))
        where[piece] = (prim["attributes"]["POSITION"], offset)
    fixed, before, after = separate(pieces)
    if check_only or before == 0:
        return name, before, after
    for piece, (accessor, offset) in where.items():
        data = fixed[piece].astype("<f4")
        blob[offset : offset + data.nbytes] = data.tobytes()
        doc["accessors"][accessor]["min"] = data.min(axis=0).tolist()
        doc["accessors"][accessor]["max"] = data.max(axis=0).tolist()
    write_glb(path, doc, blob)
    write_obj(path.with_suffix(".obj"), fixed, pieces)
    return name, before, after


def write_obj(path: Path, fixed: dict, pieces: dict):
    lines = [f"mtllib {path.stem}.mtl"]
    base = 1
    for piece, verts in fixed.items():
        lines.append(f"o {piece}")
        lines.append(f"usemtl {piece}")
        lines += [f"v {x:.4f} {y:.4f} {z:.4f}" for x, y, z in verts]
        lines += [f"f {a + base} {b + base} {c + base}" for a, b, c in pieces[piece][1]]
        base += len(verts)
    path.write_text("\n".join(lines) + "\n")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check_only = "--check" in sys.argv
    names = args or sorted(p.stem for p in MESH_DIR.glob("*.glb"))
    with Pool() as pool:
        results = pool.starmap(fix_file, [(n, check_only) for n in names])
    changed = 0
    for name, before, after in results:
        if before > 0:
            changed += 1
            verdict = "would fix" if check_only else "fixed"
            print(f"{name}: {before} fight(s) -> {after}" + ("" if after == 0 else "  (some left)") + f"  [{verdict}]")
        elif before < 0:
            print(f"{name}: skipped (more than one primitive a piece)")
    print(f"{changed} mesh(es) {'to fix' if check_only else 'fixed'}")


if __name__ == "__main__":
    main()
