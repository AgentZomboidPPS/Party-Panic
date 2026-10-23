"""Writes src/server/World/Props/HollowNight.luau, the game's specs for Hollow Night's meshes (owner:
"Hollow night comes first I want you to actually work on adding it to the game right now"), from
what tools/meshgen/season/export.py measured: each prop's height, each piece's colour, material
(Neon for glows, Glass) and transparency, plus a plain stand-in for when a mesh can't load. Asset
ids already in the file are kept (tools/upload_assets.py fills them in).

Also prints the hats' fitting for World/Hats (the piece to hold them by, how wide they are in head
widths, how far they sit down over the head), worked out from the export: the hats are modelled on
a 1.25-stud head whose middle is the model's origin (its top 0.6 above).

    python3 tools/meshgen/season/write_props.py
"""

import json
import re
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = HERE / "out"
LUAU = ROOT / "src" / "server" / "World" / "Props" / "HollowNight.luau"

HEAD = 1.25
HEAD_TOP = 0.6

# name: (what it is, extra spec lines)
PROPS = {
    "HollowCrate": ("The Hollow Crate: planked wood, iron corners, brass studs, a glowing maple leaf on each side and "
                    "leaves on the lid. The lid's pieces are Lid..., so the opening show can blow it off.",
                    ["BlocksCamera = true,"]),
    "LanternKey": ("The Lantern Key: an iron key whose bow is a lantern cage with an ember inside.", []),
    "HollowPile": ("The crate pile on its tree stump, the lobby's middle for the season (the turning crate on top, "
                   "the keys round it and the wisps are separate: the game moves them).",
                   ["BlocksCamera = true,", "Shadow = true,"]),
    "HollowAltar": ("An opening altar: two stone steps, a glowing ring (Ring: the game colours it by tier), lantern "
                    "posts and pumpkins. Its crate is a HollowCrate on top.", ["BlocksCamera = true,"]),
    "HollowBoard": ("The Top Unboxers board's frame: wood, an iron cap, stump legs, lanterns, pumpkins and leaves "
                    "(the screen is a part the game adds).", ["BlocksCamera = true,"]),
    "LeafHeap": ("A heap of fallen leaves to jump into.", []),
    "PaperLantern": ("A round paper lantern (the Lantern Ring aura).", []),
    "HarvestCrow": ("A crow, wings spread (WingL..., WingR...: the game flaps them).", []),
    "HarvestPumpkin": ("A ribbed pumpkin for the lobby's autumn dressing.", []),
    "LanternPost": ("An iron post with a hanging lantern.", []),
    "HarvestOwl": ("Pet: the Harvest Owl, in flight, with leaf-feather wings and a lantern on a chain from its beak "
                   "(Head..., WingL... / WingR..., Lantern..., Tail...: the game moves them, each turning at its "
                   "Hinge).", []),
    "EmberStag": ("Pet: the Ember Stag, white, with leafy antlers cracked with ember light (Head..., EarL... / "
                  "EarR..., LegFL... / LegFR... / LegBL... / LegBR..., Tail...: the game moves them, each turning at "
                  "its Hinge).", []),
    "Gourdian": ("Pet: the Gourdian, a jack-o'-lantern-headed guardian of vines and leaves (Head..., FistL... / "
                 "FistR..., Roots..., Seed...: the game moves them).", []),
    "ToadstoolTot": ("Pet: the Toadstool Tot, under a red cap with glowing gills, hugging a glowing acorn (Cap...: "
                     "the game wobbles it).", []),
    "LanternWisp": ("Pet: the Lantern Wisp, a little ghost in an iron lantern, its smoky tail curling out of the "
                    "roof (Ghost..., Tail...: the game moves them).", []),
    "LeafCrown": ("Hat: the Leaf Crown.", []),
    "ScarecrowHat": ("Hat: the Scarecrow Hat.", []),
    "AntlerCirclet": ("Hat: the Antler Circlet.", []),
    "AcornHelm": ("Hat: the Acorn Helm.", []),
    "CrescentMoon": ("Hat: the Crescent Moon.", []),
}
HATS = {"Hat_LeafCrown": "LeafCrown", "Hat_Scarecrow": "ScarecrowHat", "Hat_AntlerCirclet": "AntlerCirclet",
        "Hat_AcornHelm": "AcornHelm", "Hat_CrescentMoon": "CrescentMoon"}


def existing_ids() -> dict:
    if not LUAU.exists():
        return {}
    ids = {}
    for name, block in re.findall(r"\n\t\t(\w+) = \{\n(.*?)\n\t\t\},", LUAU.read_text(), re.S):
        found = re.search(r"AssetId = (\d+)", block)
        if found:
            ids[name] = int(found.group(1))
    return ids


def piece_sizes(name: str) -> dict:
    data = np.load(OUT / f"{name}.npz")
    meta = json.loads((OUT / f"{name}.json").read_text())
    sizes = {}
    for piece in meta["pieces"]:
        v = data[f"{piece}__v"]
        sizes[piece] = (v.max(0) - v.min(0), (v.max(0) + v.min(0)) / 2)
    return sizes


def main():
    ids = existing_ids()
    lines = [
        "-- Props for Hollow Night, the first crate season (owner: \"Hollow night comes first I want you to actually",
        "-- work on adding it to the game right now ... This will be players first season. I want it to look",
        "-- insane.\"). The meshes are Blender models exported in coloured pieces by tools/meshgen/season/export.py;",
        "-- this file is written by tools/meshgen/season/write_props.py from what that export measured (heights,",
        "-- each piece's colour, material and transparency). Don't edit it by hand: change the model and re-export.",
        "return function(h)",
        "\tlocal rgb = h.rgb",
        "",
        "\t-- See-through pieces (a wisp's flame and tail, glass), set after the template is made.",
        "\tlocal function seeThrough(amounts: { [string]: number })",
        "\t\treturn function(model: Model)",
        "\t\t\tfor _, part in model:GetDescendants() do",
        "\t\t\t\tif part:IsA(\"BasePart\") and amounts[part.Name] then",
        "\t\t\t\t\tpart.Transparency = amounts[part.Name]",
        "\t\t\t\t\tpart.CastShadow = false",
        "\t\t\t\tend",
        "\t\t\tend",
        "\t\tend",
        "\tend",
        "",
        "\treturn {",
    ]
    for name, (about, extra) in PROPS.items():
        meta = json.loads((OUT / f"{name}.json").read_text())
        size = meta["size"]
        pieces = meta["pieces"]
        biggest = max(piece_sizes(name).items(), key=lambda kv: float(np.prod(kv[1][0] + 0.01)))
        bsize, bcentre = biggest[1]
        main_piece = biggest[0]
        lines.append(f"\t\t-- {about}")
        lines.append(f"\t\t{name} = {{")
        lines.append(f"\t\t\tHeight = {size[1]:.3f},")
        lines.append(f"\t\t\tAssetId = {ids.get(name, 0)},")
        for e in extra:
            lines.append(f"\t\t\t{e}")
        lines.append("\t\t\tPalette = {")
        for piece, info in pieces.items():
            r, g, b = info["color"]
            lines.append(f"\t\t\t\t{piece} = rgb({r}, {g}, {b}),")
        lines.append("\t\t\t},")
        lines.append("\t\t\tMaterials = {")
        for piece, info in pieces.items():
            lines.append(f"\t\t\t\t{piece} = Enum.Material.{info['material']},")
        lines.append("\t\t\t},")
        see = {p: i["transparency"] for p, i in pieces.items() if i["transparency"] > 0 or i["material"] == "Glass"}
        if see:
            inner = ", ".join(f"{p} = {max(t, 0.45 if pieces[p]['material'] == 'Glass' else t):.2f}" for p, t in see.items())
            lines.append(f"\t\t\tPostProcess = seeThrough({{ {inner} }}),")
        lines.append("\t\t\tFallback = function(m)")
        lines.append(
            f"\t\t\t\th.block(m, \"{main_piece}\", Vector3.new({max(bsize[0], 0.2):.2f}, {max(bsize[1], 0.2):.2f}, "
            f"{max(bsize[2], 0.2):.2f}), Vector3.new({bcentre[0]:.2f}, {bcentre[1]:.2f}, {bcentre[2]:.2f}))")
        lines.append("\t\t\tend,")
        lines.append("\t\t},")
    lines += ["\t}", "end", ""]
    LUAU.write_text("\n".join(lines))
    print(f"wrote {LUAU.relative_to(ROOT)}")

    print("\nHats (World/Hats LOOKS):")
    for item, prop in HATS.items():
        meta = json.loads((OUT / f"{prop}.json").read_text())
        sizes = piece_sizes(prop)
        handle = max(sizes.items(), key=lambda kv: max(kv[1][0][0], kv[1][0][2]))
        width = max(handle[1][0][0], handle[1][0][2]) / HEAD
        sink = (HEAD_TOP + meta["middle"]) / HEAD
        glow = next((p for p, i in meta["pieces"].items() if i["material"] == "Neon"), None)
        print(f"\t{item} = {{ Prop = \"{prop}\", Handle = \"{handle[0]}\", Width = {width:.3f}, Sink = {sink:.3f}, "
              f"Glow = {json.dumps(glow) if glow else 'nil'} }},")


if __name__ == "__main__":
    main()
