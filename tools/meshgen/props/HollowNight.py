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


def ground_bark(pieces: dict) -> dict:
    """The pile's stump stands on the court (the clipping sweep; owner: "Make sure everything is super
    nice. No clipping stuff like that."): its leaf heap reaches the pile's base inside the stump, so the
    prop's base is there, but the bark wall and its roots stopped 0.59-0.75 above it, and the stump hung
    over the court. The bark's bottom edge goes down to the base (y = 0); the rest stays."""
    bark = pieces.get("Bark")
    if bark is None:
        return pieces
    v = np.array(bark.v, dtype=float)
    low = v[:, 1].min()
    edge = v[:, 1] < low + 0.2  # (the wall's foot and the roots' undersides)
    v[edge, 1] = 0.0
    bark.v = v
    return pieces


FIXES = {"HollowPile": ground_bark}


def loader(name):
    def build():
        data = np.load(OUT / f"{name}.npz")
        meta = json.loads((OUT / f"{name}.json").read_text())
        pieces = {piece: Mesh(data[f"{piece}__v"], data[f"{piece}__f"]) for piece in meta["pieces"]}
        return FIXES[name](pieces) if name in FIXES else pieces

    return build


PROPS = {name: loader(name) for name in NAMES if (OUT / f"{name}.json").exists()}
