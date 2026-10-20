"""Finds surfaces that will flicker in Roblox (z-fighting): two opaque parts with a face in the same
plane (within --eps studs) whose footprints overlap. Works on a world dump from dump_world.luau.

    python3 tools/preview/zfight.py dump.json [--eps 0.08]

Faces come from each part's box (unions use their bounding box, so a rounded edge can give a
false alarm; check the names it prints).
"""

import argparse
import json
import math
from collections import defaultdict


def load(path):
    data = json.load(open(path))
    data = data[0] if isinstance(data, list) else data
    return json.loads(data) if isinstance(data, str) else data


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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("dump")
    parser.add_argument("--eps", type=float, default=0.08)
    args = parser.parse_args()
    parts = [p for p in load(args.dump)["parts"] if p["t"] < 0.6 and p.get("shape") != "Ball" and p["c"] != "MeshPart"]
    buckets = defaultdict(list)
    for index, part in enumerate(parts):
        for face in faces(part):
            n, center, _ = face
            key = tuple(round(c, 2) for c in n)
            buckets[key].append((index, dot(n, center), face))
    found = set()
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
                pa, pb = parts[ia], parts[ib]
                pair = tuple(sorted((f"{pa['n']}@{[round(v, 1) for v in pa['cf'][:3]]}", f"{pb['n']}@{[round(v, 1) for v in pb['cf'][:3]]}")))
                if pair not in found:
                    found.add(pair)
                    print(f"{abs(db - da):.3f}  normal {key}  {pair[0]}  <->  {pair[1]}")
    print(f"{len(found)} flickering face pairs")


if __name__ == "__main__":
    main()
