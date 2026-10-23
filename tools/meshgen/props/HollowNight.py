"""Hollow Night, the first crate season (owner: "Hollow night comes first I want you to actually work
on adding it to the game right now ... This will be players first season. I want it to look
insane."): the crate, its key, the crate pile, the opening altars, the leaderboard's frame, the
lobby's lanterns, pumpkins, crows and leaf heaps, the five pets and the five hats.

These are modelled in Blender (tools/meshgen/season: the same models as the concept renders) and
exported by tools/meshgen/season/export.py into tools/meshgen/season/out/<Name>.npz, already in
studs and Roblox's axes (+Y up, -Z the front, base on y = 0) and split into pieces by colour and
material. This file only hands those pieces to generate_meshes.py, which writes the .glb:

    $PP_BPY_PYTHON tools/meshgen/season/export.py --only HarvestOwl
    python3 tools/meshgen/generate_meshes.py --only HarvestOwl

Each piece's colour, material and transparency are in out/<Name>.json; src/server/World/Props/
HollowNight.luau carries them (tools/meshgen/season/write_props.py writes it).
"""

import json
from pathlib import Path

import numpy as np
from generate_meshes import Mesh

OUT = Path(__file__).resolve().parents[1] / "season" / "out"

NAMES = [
    "HollowCrate", "LanternKey", "HollowPile", "HollowAltar", "HollowBoard", "LeafHeap", "PaperLantern",
    "HarvestCrow", "HarvestPumpkin", "LanternPost",
    "HarvestOwl", "EmberStag", "Gourdian", "ToadstoolTot", "LanternWisp",
    "LeafCrown", "ScarecrowHat", "AntlerCirclet", "AcornHelm", "CrescentMoon",
]


def loader(name):
    def build():
        data = np.load(OUT / f"{name}.npz")
        meta = json.loads((OUT / f"{name}.json").read_text())
        return {piece: Mesh(data[f"{piece}__v"], data[f"{piece}__f"]) for piece in meta["pieces"]}

    return build


PROPS = {name: loader(name) for name in NAMES if (OUT / f"{name}.json").exists()}
