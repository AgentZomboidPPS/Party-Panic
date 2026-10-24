"""Writes stand-in shapes for the preview renderer (tools/preview/render.py) for the props that are the
owner's CAPY GO BOOM meshes.

Capy Go Boom's capybara, cannon and snacks are plain uploaded meshes (Props/CapyGoBoom.luau builds them with
AssetService:CreateMeshPartAsync). The renderer can only draw a mesh from a local .glb, and the real geometry
can't be fetched here, so a portal preview would show them as white boxes. These stand-ins are only for that
render: ellipsoids and rounded blocks that the renderer stretches to each part's real size (the snapshot
carries it), plus a colour per piece. They must NEVER go in assets/meshes/: tools/upload_assets.py uploads
every .glb there and would swap the real meshes in the game for these.

    python3 tools/preview/make_standins.py          # writes assets/previews/standins/*.glb and *.json

A piece is named like the part it stands for (CapyBody, CapyHead, LegFL, CannonHousing, Food ...). A mesh is
authored in a unit box; the front of the capybara is +Z here (the renderer turns it the way Roblox does).
"""

from __future__ import annotations

import json
import struct
from pathlib import Path

import numpy as np

OUT = Path(__file__).resolve().parents[2] / "assets" / "previews" / "standins"


def superellipsoid(exponent: float, n_lat: int = 14, n_lon: int = 24, center=(0, 0, 0), size=(1, 1, 1)):
    """A rounded box (exponent 2 is an ellipsoid, 4+ is nearly a block): vertices and triangles."""
    verts = []
    e = 2.0 / exponent
    for i in range(n_lat + 1):
        v = -np.pi / 2 + np.pi * i / n_lat
        cv = np.sign(np.cos(v)) * abs(np.cos(v)) ** e
        sv = np.sign(np.sin(v)) * abs(np.sin(v)) ** e
        for j in range(n_lon):
            u = 2 * np.pi * j / n_lon
            cu = np.sign(np.cos(u)) * abs(np.cos(u)) ** e
            su = np.sign(np.sin(u)) * abs(np.sin(u)) ** e
            verts.append((0.5 * cv * cu * size[0] + center[0], 0.5 * sv * size[1] + center[1], 0.5 * cv * su * size[2] + center[2]))
    faces = []
    for i in range(n_lat):
        for j in range(n_lon):
            a = i * n_lon + j
            b = i * n_lon + (j + 1) % n_lon
            c = (i + 1) * n_lon + j
            d = (i + 1) * n_lon + (j + 1) % n_lon
            faces += [(a, c, b), (b, c, d)]
    return np.array(verts, dtype=np.float32), np.array(faces, dtype=np.uint32)


def merge(*meshes):
    verts, faces, base = [], [], 0
    for v, f in meshes:
        verts.append(v)
        faces.append(f + base)
        base += len(v)
    return np.concatenate(verts), np.concatenate(faces)


def write_glb(path: Path, pieces: dict):
    """A glTF binary with one node per piece (name -> (vertices, triangles))."""
    blob = bytearray()
    views, accessors, meshes, nodes = [], [], [], []
    for name, (verts, faces) in pieces.items():
        verts = np.ascontiguousarray(verts, dtype=np.float32)
        faces = np.ascontiguousarray(faces.reshape(-1), dtype=np.uint32)
        offset = len(blob)
        blob += verts.tobytes()
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": verts.nbytes, "target": 34962})
        accessors.append({
            "bufferView": len(views) - 1, "componentType": 5126, "count": len(verts), "type": "VEC3",
            "min": verts.min(0).tolist(), "max": verts.max(0).tolist(),
        })
        position = len(accessors) - 1
        offset = len(blob)
        blob += faces.tobytes()
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": faces.nbytes, "target": 34963})
        accessors.append({"bufferView": len(views) - 1, "componentType": 5125, "count": len(faces), "type": "SCALAR"})
        meshes.append({"name": name, "primitives": [{"attributes": {"POSITION": position}, "indices": len(accessors) - 1}]})
        nodes.append({"name": name, "mesh": len(meshes) - 1})
    doc = {
        "asset": {"version": "2.0", "generator": "tools/preview/make_standins.py"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes, "meshes": meshes, "accessors": accessors, "bufferViews": views,
        "buffers": [{"byteLength": len(blob)}],
    }
    text = json.dumps(doc, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    blob += b"\0" * (-len(blob) % 4)
    data = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(text) + 8 + len(blob))
    data += struct.pack("<II", len(text), 0x4E4F534A) + text + struct.pack("<II", len(blob), 0x004E4942) + bytes(blob)
    path.write_bytes(data)


def capy():
    body = superellipsoid(2.0)
    # A big square head with two ears on top and a snout: one mesh (one colour).
    head = merge(
        superellipsoid(3.4, size=(1, 0.8, 1), center=(0, -0.06, 0)),
        superellipsoid(2.2, size=(0.2, 0.2, 0.2), center=(-0.34, 0.42, -0.1)),
        superellipsoid(2.2, size=(0.2, 0.2, 0.2), center=(0.34, 0.42, -0.1)),
        superellipsoid(2.6, size=(0.55, 0.38, 0.28), center=(0, -0.2, 0.42)),
    )
    leg = superellipsoid(2.4)
    block = superellipsoid(4.5)
    pieces = {
        "CapyBody": body, "CapyHead": head, "LegFL": leg, "LegFR": leg, "LegRL": leg, "LegRR": leg,
        "CannonHousing": block, "CannonFixed": block, "CannonGlow": block, "CannonLight": block,
        "CannonMetal": block, "CannonMuzzle": superellipsoid(3.0), "CannonTrim": block,
    }
    colors = {
        "CapyBody": [190, 136, 80], "CapyHead": [204, 150, 90],
        "LegFL": [160, 108, 62], "LegFR": [160, 108, 62], "LegRL": [160, 108, 62], "LegRR": [160, 108, 62],
        "CannonFixed": [225, 225, 230], "CannonMetal": [165, 172, 184],
    }
    return pieces, colors


FOODS = {
    "CapyBoomStrawberry": (235, 60, 70), "CapyBoomBanana": (255, 226, 95), "CapyBoomCarrot": (250, 140, 50),
    "CapyBoomBlueberries": (80, 90, 200), "CapyBoomAvocado": (110, 170, 70), "CapyBoomPizza": (250, 190, 70),
    "CapyBoomBurger": (230, 160, 80), "CapyBoomIceCream": (255, 170, 200), "CapyBoomPancakes": (235, 180, 100),
    "CapyBoomOrange": (255, 150, 40), "CapyBoomWatermelon": (240, 80, 100), "CapyBoomGoldenApple": (255, 205, 60),
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    pieces, colors = capy()
    write_glb(OUT / "CapyBoomCapy.glb", pieces)
    (OUT / "CapyBoomCapy.json").write_text(json.dumps(colors, indent=1))
    ellipsoid = superellipsoid(2.2)
    for prop, color in FOODS.items():
        write_glb(OUT / f"{prop}.glb", {"Food": ellipsoid})
        (OUT / f"{prop}.json").write_text(json.dumps({"Food": list(color)}))
    print(f"wrote {len(FOODS) + 1} stand-ins to {OUT}")


if __name__ == "__main__":
    main()
