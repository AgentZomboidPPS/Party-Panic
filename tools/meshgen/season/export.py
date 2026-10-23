"""Exports the season's Blender models as the game's meshes (owner: "Hollow night comes first I want
you to actually work on adding it to the game right now ... I want it to look insane.").

    $PP_BPY_PYTHON tools/meshgen/season/export.py [--only HollowCrate,HarvestOwl]

The models are the ones the concept renders were made from (hollow_night.py, hollow_night_pets.py,
built with blender_lib.py in its EXPORT mode: fewer sides, no sparkles or lights). Each model is
split into pieces by what it's made of, since a Roblox MeshPart has one colour and one material:

- a plain surface is a piece of its colour (SmoothPlastic, or Glass when it's see-through);
- a glowing one (eyes, seams, rings, the lantern's light) is a Neon piece;
- a surface coloured along its length (the stag's antlers, the wisp's flame and tail) is cut into a
  few pieces by colour, each one Neon where it glows and see-through where it fades;
- a group marked `piece_prefix` (the crate's lid, the owl's wings, the crow's wings, the Gourdian's
  fists, the wisp's flame) names its pieces with that prefix, so the game can move them;
- a flat sheet (a leaf, a wing feather) gets a thin back, because Roblox draws only the front of a
  face.

Pieces of the same colour and material are merged, flat-shaded parts stay crisp, and the smooth
ones are simplified (pyfqmr) to the model's triangle budget, so twelve pets in a lobby stay cheap
on phones. Coordinates turn to Roblox's: +Y up, -Z the front, studs; the base sits on y = 0.

Writes tools/meshgen/season/out/<Name>.npz (each piece's vertices and triangles) and <Name>.json
(each piece's colour, material and transparency; the size; Middle, the height of the model's own
origin above its base: a pet's middle, a hat's head centre). tools/meshgen/props/HollowNight.py
turns them into assets/meshes/<Name>.glb (python3 tools/meshgen/generate_meshes.py --only <Name>),
and tools/meshgen/season/write_props.py writes the game's palettes from the .json files.
"""

import argparse
import colorsys
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import blender_lib as lib  # noqa: E402

lib.EXPORT = True
import hollow_night as HN  # noqa: E402
import hollow_night_pets as HP  # noqa: E402

OUT = HERE / "out"


def hat(builder):
    def build():
        g = lib.group()
        builder(g)
        return g

    return build


# name: (builder, triangle budget)
PROPS = {
    "HollowCrate": (lambda: HN.crate((0, 0, 0), 1.0), 3600),
    "LanternKey": (lambda: HN.key((0, 0, 0)), 900),
    "HollowPile": (lambda: HN.crate_pile(game=True, crates=False), 40000),
    "HollowAltar": (lambda: HN.altar_base(), 6000),
    "HollowBoard": (lambda: HN.board_frame(), 6000),
    "LeafHeap": (lambda: HN.leaf_heap(), 4000),
    "PaperLantern": (lambda: HN.paper_lantern(), 600),
    "HarvestCrow": (lambda: HN.crow(), 500),
    "HarvestPumpkin": (lambda: HN.pumpkin((0, 0, 0), 1.0), 1400),
    "LanternPost": (lambda: HN.lantern_post((0, 0, 0), 6.0, 1), 1400),
    "HarvestOwl": (lambda: HP.harvest_owl((0, 0, 0)), 7500),
    "EmberStag": (lambda: HP.ember_stag((0, 0, 0)), 7500),
    "Gourdian": (lambda: HP.gourdian((0, 0, 0)), 7500),
    "ToadstoolTot": (lambda: HP.toadstool_tot((0, 0, 0)), 6500),
    "LanternWisp": (lambda: HP.lantern_wisp((0, 0, 0)), 6500),
    "LeafCrown": (hat(HP.leaf_crown), 3000),
    "ScarecrowHat": (hat(HP.scarecrow_hat), 3000),
    "AntlerCirclet": (hat(HP.antler_circlet), 3000),
    "AcornHelm": (hat(HP.acorn_helm), 3000),
    "CrescentMoon": (hat(HP.crescent_moon), 2500),
}

# The most triangles one piece may have (Roblox's mesh limit is higher; this keeps big props light).
PIECE_MAX = 19000


def srgb(c):
    c = max(0.0, min(1.0, c))
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def rgb255(linear):
    return [int(round(srgb(v) * 255)) for v in linear[:3]]


def describe(mat):
    """How a Blender material looks in Roblox: (kind, colour 0-255, material, transparency)."""
    if mat is None or not mat.use_nodes:
        return "plain", [200, 200, 200], "SmoothPlastic", 0.0
    nodes = mat.node_tree.nodes
    if any(n.type == "ATTRIBUTE" for n in nodes):
        return ("vsolid" if "Principled BSDF" in nodes else "vmat"), None, None, None
    if "Principled BSDF" not in nodes:
        return "skip", None, None, None
    b = nodes["Principled BSDF"].inputs
    base = b["Base Color"].default_value
    emit, strength = b["Emission Color"].default_value, b["Emission Strength"].default_value
    transmission, alpha = b["Transmission Weight"].default_value, b["Alpha"].default_value
    if strength >= 1.5:
        tint = emit if max(base[:3]) < 0.05 else [0.5 * base[i] + 0.5 * emit[i] for i in range(3)]
        return "plain", rgb255(tint), "Neon", 0.0 if alpha > 0.9 else round(1 - alpha, 2)
    if transmission > 0.5:
        return "plain", rgb255(base), "Glass", 0.45
    return "plain", rgb255(base), "SmoothPlastic", 0.0 if alpha > 0.9 else round(1 - alpha, 2)


def clean(name):
    for junk in ("hollow_", "fall_", "owl_", "stag_", "tot_", "wisp_", "gourd_", "drake_"):
        name = name.replace(junk, "")
    word = "".join(ch if ch.isalnum() else " " for ch in name.split("#")[0]).title().replace(" ", "")
    return word or "Part"


def color_name(rgb):
    h, l, s = colorsys.rgb_to_hls(*(c / 255 for c in rgb))
    if s < 0.15:
        return "White" if l > 0.75 else "Grey" if l > 0.3 else "Black"
    deg = h * 360
    for limit, word in ((15, "Red"), (40, "Orange"), (65, "Gold"), (170, "Green"), (200, "Teal"), (255, "Blue"),
                        (300, "Violet"), (345, "Pink"), (361, "Red")):
        if deg < limit:
            return word
    return "Tint"


NO_PREFIXES = {"HollowPile"}  # (its crates never open: their lids merge with the rest)
USE_PREFIXES = True


def prefix_of(o):
    if not USE_PREFIXES:
        return ""
    while o is not None:
        if "piece_prefix" in o.keys():
            return o["piece_prefix"]
        o = o.parent
    return ""


def descendants(root):
    out, stack = [], [root]
    while stack:
        o = stack.pop()
        out.append(o)
        stack.extend(o.children)
    return out


def open_edges(me):
    count = {}
    for poly in me.polygons:
        vs = list(poly.vertices)
        for a, b in zip(vs, vs[1:] + vs[:1]):
            k = (min(a, b), max(a, b))
            count[k] = count.get(k, 0) + 1
    return any(c == 1 for c in count.values())


def kmeans(x, k, iters=12):
    k = min(k, len(x))
    centers = x[np.linspace(0, len(x) - 1, k).astype(int)].copy()
    for _ in range(iters):
        label = np.argmin(((x[:, None, :] - centers[None]) ** 2).sum(-1), axis=1)
        for j in range(k):
            if (label == j).any():
                centers[j] = x[label == j].mean(0)
    return label, centers


def to_roblox(v):
    """Blender (x, y, z), front -Y, to Roblox (x, y, z), front -Z: a half turn about the up axis on
    top of the axis swap, so the model keeps its handedness (no mirror) and faces -Z."""
    return np.stack([-v[:, 0], v[:, 2], v[:, 1]], 1)


def collect(root):
    everything = descendants(root) if root is not None else list(bpy.context.scene.objects)
    objects = [o for o in everything if o.type == "MESH"]
    for o in objects:
        if open_edges(o.data) and not any(m.type == "SOLIDIFY" for m in o.modifiers):
            mod = o.modifiers.new("back", "SOLIDIFY")
            mod.thickness = 0.02 / max(1e-6, max(o.matrix_world.to_scale()))
            mod.offset = 0.0
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    raw = {}  # (name, colour, material, transparency) -> {"smooth": [(v, f)], "flat": [(v, f)]}
    for o in objects:
        mat = o.material_slots[0].material if o.material_slots else None
        kind, colour, material, transparency = describe(mat)
        if kind == "skip":
            continue
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        me.calc_loop_triangles()
        n = len(me.vertices)
        co = np.zeros(n * 3)
        me.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        mw = np.array(o.matrix_world)
        world = co @ mw[:3, :3].T + mw[:3, 3]
        tris = np.zeros(len(me.loop_triangles) * 3, dtype=np.int64)
        me.loop_triangles.foreach_get("vertices", tris)
        tris = tris.reshape(-1, 3)
        smooth = all(p.use_smooth for p in me.polygons) if len(me.polygons) else True
        prefix = prefix_of(o)
        groups = []
        if kind in ("vsolid", "vmat"):
            attr = me.color_attributes.get("Col")
            cols = np.zeros(n * 4)
            attr.data.foreach_get("color", cols)
            cols = cols.reshape(-1, 4)
            face = cols[tris].mean(1)
            if kind == "vmat":
                keep = face[:, 3] > 0.12
                tris, face = tris[keep], face[keep]
            if len(tris):
                label, centers = kmeans(face, 3)
                for j, c in enumerate(centers):
                    sel = tris[label == j]
                    if not len(sel):
                        continue
                    rgb = rgb255(c[:3])
                    if kind == "vmat":
                        groups.append((sel, rgb, "Neon", round(min(0.75, max(0.0, 1 - c[3])), 2)))
                    else:
                        groups.append((sel, rgb, "Neon" if c[3] > 0.45 else "SmoothPlastic", 0.0))
        else:
            groups.append((tris, colour, material, transparency))
        base = o.get("piece") or clean(mat.name if mat else "Part")
        for sel, rgb, material, transparency in groups:
            name = prefix + (base if kind == "plain" else base + color_name(rgb))
            key = (prefix, tuple(rgb), material, transparency)
            entry = raw.setdefault(key, {"name": name, "smooth": [], "flat": []})
            entry["smooth" if smooth else "flat"].append((world, sel))
        ev.to_mesh_clear()
    return raw


def stack(parts):
    vs, fs, offset = [], [], 0
    for v, f in parts:
        used = np.unique(f)
        remap = np.full(len(v), -1)
        remap[used] = np.arange(len(used))
        vs.append(v[used])
        fs.append(remap[f] + offset)
        offset += len(used)
    if not vs:
        return np.zeros((0, 3)), np.zeros((0, 3), dtype=np.int64)
    return np.vstack(vs), np.vstack(fs)


def weld(v, f, tol=1e-5):
    keys = np.round(v / tol).astype(np.int64)
    _, index, inverse = np.unique(keys, axis=0, return_index=True, return_inverse=True)
    f = inverse.reshape(-1)[f]
    keep = (f[:, 0] != f[:, 1]) & (f[:, 1] != f[:, 2]) & (f[:, 0] != f[:, 2])
    return v[index], f[keep]


def simplify(v, f, target):
    if len(f) <= target:
        return v, f
    import pyfqmr

    s = pyfqmr.Simplify()
    s.setMesh(v.astype(np.float64), f.astype(np.int32))
    s.simplify_mesh(target_count=int(target), aggressiveness=5, preserve_border=True, verbose=False)
    nv, nf, _ = s.getMesh()
    return nv, nf.astype(np.int64)


def merge_close(built, limit=40.0):
    """Merges pieces that look alike (same prefix, material and transparency, colours within
    `limit` of each other on the 0-255 scale): fewer MeshParts for the same look."""
    merged = True
    while merged:
        merged = False
        for i in range(len(built)):
            for j in range(i + 1, len(built)):
                (pa, ca, ma, ta), (pb, cb, mb, tb) = built[i][0], built[j][0]
                if pa != pb or ma != mb or ta != tb or math.dist(ca, cb) > limit:
                    continue
                wa = len(built[i][3]) + len(built[i][5]) + 1
                wb = len(built[j][3]) + len(built[j][5]) + 1
                colour = tuple(int(round((ca[k] * wa + cb[k] * wb) / (wa + wb))) for k in range(3))
                sv, sf = stack([(built[i][2], built[i][3]), (built[j][2], built[j][3])])
                fv, ff = stack([(built[i][4], built[i][5]), (built[j][4], built[j][5])])
                built[i] = [(pa, colour, ma, ta), built[i][1], sv, sf, fv, ff]
                del built[j]
                merged = True
                break
            if merged:
                break
    return built


def flat_split(v, f):
    return v[f].reshape(-1, 3), np.arange(len(f) * 3).reshape(-1, 3)


def export(name, builder, budget):
    global USE_PREFIXES
    USE_PREFIXES = name not in NO_PREFIXES
    bpy.ops.wm.read_factory_settings(use_empty=True)
    lib._M.clear()
    lib._ME.clear()
    lib._DEFAULT = None
    HN._LEAF.clear()
    HN._PUMPKIN.clear()
    root = builder()
    raw = collect(root)
    built = []
    for key, entry in raw.items():
        sv, sf = stack(entry["smooth"])
        sv, sf = weld(sv, sf) if len(sf) else (sv, sf)
        fv, ff = stack(entry["flat"])
        built.append([key, entry["name"], sv, sf, fv, ff])
    built = merge_close(built)
    flat_total = sum(len(b[5]) for b in built)
    smooth_total = sum(len(b[3]) for b in built)
    factor = min(1.0, max(0.05, (budget - flat_total) / max(1, smooth_total)))
    pieces, info, names = {}, {}, {}
    for key, pname, sv, sf, fv, ff in built:
        if len(sf):
            sv, sf = simplify(sv, sf, min(PIECE_MAX, max(48, len(sf) * factor)))
        parts = []
        if len(sf):
            parts.append((sv, sf))
        if len(ff):
            parts.append(flat_split(fv, ff))
        v, f = stack(parts)
        if not len(f):
            continue
        n = names.get(pname, 0)
        names[pname] = n + 1
        unique = pname if n == 0 else f"{pname}{n + 1}"
        pieces[unique] = (to_roblox(v), f)
        _, rgb, material, transparency = key
        info[unique] = {"color": list(rgb), "material": material, "transparency": transparency}
    allv = np.vstack([p[0] for p in pieces.values()])
    lo, hi = allv.min(0), allv.max(0)
    for unique in pieces:
        v, f = pieces[unique]
        pieces[unique] = (v - np.array([0, lo[1], 0]), f)
    OUT.mkdir(exist_ok=True)
    np.savez_compressed(OUT / f"{name}.npz", **{f"{k}__v": p[0].astype(np.float32) for k, p in pieces.items()},
                        **{f"{k}__f": p[1].astype(np.int32) for k, p in pieces.items()})
    size = (hi - lo).tolist()
    meta = {"pieces": info, "size": [round(x, 3) for x in size], "middle": round(float(-lo[1]), 3),
            "tris": int(sum(len(p[1]) for p in pieces.values()))}
    (OUT / f"{name}.json").write_text(json.dumps(meta, indent=1))
    print(f"{name:15s} {meta['tris']:6d} tris  {len(pieces):2d} pieces  size {size[0]:.2f} x {size[1]:.2f} x {size[2]:.2f}"
          f"  middle {meta['middle']:.2f}")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    args = parser.parse_args(argv)
    wanted = set(args.only.split(",")) if args.only else set(PROPS)
    for name, (builder, budget) in PROPS.items():
        if name in wanted:
            export(name, builder, budget)


if __name__ == "__main__":
    main()
