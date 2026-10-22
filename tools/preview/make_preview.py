"""Makes a mini-game's preview "video" for the vote stage's portals: a short looping flyover of its
arena mid-round, with the players in action (owner: "maybe we make the portal do a little video of
what the game actually is?").

    python3 tools/preview/make_preview.py FireRope                  # the whole thing
    python3 tools/preview/make_preview.py FireRope --no-upload      # frames and sheet only, to look at
    python3 tools/preview/make_preview.py FireRope --reuse-dump     # skip the server run, re-render
    python3 tools/preview/make_preview.py FireRope --dump-at 14     # snapshot later in the round
    python3 tools/preview/make_preview.py FireRope --upload-only    # upload the sheet you looked at

What it does:

1. Plays a real round on a Roblox test server with the round harness (tools/checks/round_harness.py:
   8 stand-in players, the mode's client half running too, so client-drawn things like the fire
   rope are there) and snapshots the arena a few seconds in (Open Cloud Luau execution).
2. Renders FRAMES small frames with tools/preview/render.py (Blender) along a camera path that
   sways around the frozen moment and comes back to where it started, so the loop is seamless.
   The frames have the shape of a portal's opening and are packed into one sprite sheet,
   assets/previews/<Id>.jpg (Roblox caps images at 1024x1024).
3. Uploads the sheet to Roblox under the owner's account (Open Cloud Assets API, like
   tools/upload_assets.py). That makes a decal holding an image; a test server looks up the image
   (ImageLabels show images, not decals), which is made Open Use, and the game may use both
   (tools/asset_permissions.py).
4. Records the image id and the sheet's layout in assets/previews/previews.json and rewrites
   src/shared/GamePreviews.luau from it. The client plays the sheet as a flipbook; a game with no
   entry there gets its icon-and-name card instead. Rebuild the place to ship the new entry.

A new game: run this once it plays in the harness (it needs tools/checks/bots/<Id>.luau). If the
default camera frames it badly, add an entry to CAMERAS below and re-run with --reuse-dump --no-upload
until the frames look right (look at /tmp/pv_<Id>_frames/), then once more without --no-upload.

Needs: an Open Cloud key with Luau execution, Assets (write) and asset-permissions (write) access
(ROBLOX_API_KEY, or a proxy that adds it), Pillow, and a Python with Blender's `bpy` module for the
renders (--python, or PP_BPY_PYTHON).
"""

from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PREVIEWS = ROOT / "assets" / "previews"
RECORD = PREVIEWS / "previews.json"
LUAU = ROOT / "src" / "shared" / "GamePreviews.luau"
USER_ID = os.environ.get("PP_OWNER_USER_ID", "11690979745")  # the game owner's Roblox account

# The portal opening is 14 x 19.8 studs (LobbyBuilder), so the frames are about that shape: 6 x 4
# frames of 168 x 240 make a 1008 x 960 sheet. (Multiples of 8, so the JPEG's blocks never mix two
# frames.)
FRAME_W, FRAME_H = 168, 240
COLUMNS = 6
FRAMES = 24
FPS = 8

# Camera per game, around the focus: the middle of the biggest bunch of players ("subject":
# "bunch"), the highest player ("highest": someone mid-jump), or the first part named "look_at"
# (e.g. a bump's ring). yaw is where the camera stands, in degrees around the focus (0 = on the +Z
# side looking toward -Z, 90 = on the +X side), pitch is how steeply it looks down, distance is
# from the focus, fov is the vertical view angle, sway is how far the camera swings to each side
# during the loop, and shift moves the focus (studs, x y z). raise tilts the view up so the focus
# sits below the middle of the frame: the portal covers the top with the game's icon and name.
DEFAULT_CAMERA = {"yaw": 0, "pitch": 30, "distance": 40, "fov": 50, "sway": 10, "raise": 8, "shift": [0, 0, 0]}
CAMERAS: dict[str, dict] = {
    # Behind the line of jumpers, looking out over the lava at the Dragon Temple, the rope sweeping
    # along the bridge.
    "FireRope": {"yaw": 14, "pitch": 9, "distance": 30, "shift": [0, 2, 0], "raise": 13, "fov": 62},
    # Players on the hexes of the called color, the other colors sinking into the lava, the
    # referee's flag behind.
    "HexMeltdown": {"yaw": 20, "pitch": 46, "distance": 86, "shift": [0, -6, 8], "raise": 5},
    # The honey tree's vine of fruit and honeycombs, bees chasing someone out, players on their pads.
    "HoneyTrap": {"yaw": -15, "pitch": 26, "distance": 44, "fov": 55, "shift": [-1, 5, -5], "raise": 12},
    # Low in front of the launch line: two wind-up toys just launched, flying toward the camera, the
    # players who wound them behind their pads.
    "MechaMarathon": {"yaw": 200, "pitch": 13, "distance": 26, "fov": 46, "shift": [-3, 4, -15], "raise": 9, "sway": 8},
    # From just past a row of 3D hurdles, looking back down the home straight: the striped standards
    # and crossbars in front, the pack galloping at them on their hobby horses, the grandstand beyond.
    "RockinRaceway": {"yaw": 242, "pitch": 15, "distance": 24, "fov": 50, "shift": [-35, -3, 2], "raise": 9},
    # The turning field from a player's corner: lanes, veggies and bombs, the silo in the middle.
    "RakeItIn": {"look_at": "SiloBody", "yaw": 30, "pitch": 30, "distance": 50, "shift": [0, -4, 0], "raise": 2},
    # Across the giant pizza on its pan: teams on their slices, half of them eaten down to the pan, the
    # wood-fired oven and the pizzeria's sign beyond.
    "EatsaPizza": {"look_at": "Pan", "yaw": 15, "pitch": 40, "distance": 66, "shift": [2, 2, -12], "raise": 9},
    # Over the cutters' shoulders: their boards with the dotted outlines half cut, the giant glass of
    # milk beyond.
    "CrazyCutters": {"yaw": 80, "pitch": 40, "distance": 38, "shift": [-12, -5, 0], "raise": 2},
    # Across the candy factory hall at the CAKE FACTORY sign: the team belts with cakes on them.
    "CakeFactory": {"look_at": "Sign", "yaw": 200, "pitch": 24, "distance": 42, "shift": [0, -29, -26], "raise": 6},
    # Over a team's shoulders at its grill: the giant knife lined up over the steak, the glowing line
    # where it will cut, the coals under the grate.
    "PrimeCut": {"look_at": "CutLine", "yaw": 28, "pitch": 36, "distance": 39, "shift": [-0.5, 0, 10.5], "raise": 4},
    # Down the row of mills from the first one: its axe biting into a log on the stump, the team beside
    # it, the next team's mill with its log rack and stump beyond.
    "LogJam": {"look_at": "Top", "yaw": -110, "pitch": 26, "distance": 32, "shift": [8, 2, 6], "raise": 6},
    # Behind a player at their booth's counter: the mischief's smoke over the cubby shelf, toys
    # tumbling off it onto the counter.
    "MessyMemory": {"look_at": "CounterTop", "yaw": 168, "pitch": 16, "distance": 25, "shift": [0, 2, 0], "raise": 6},
    # Side-on from a little below: two fallers under open umbrellas, the left throwers on their
    # clouds, coins in the air, a hot-air balloon and the sun beyond.
    "ParasolPlummet": {"look_at": "Cap", "yaw": 0, "pitch": -8, "distance": 58, "shift": [12, -1, 0], "raise": 6,
                       "sway": 6},
    # From high over the kettle grill, down at players running round the lawn (one holding a sizzling
    # potato), the picnic tables and the fence with its string lights.
    "HotPotato": {"look_at": "Lawn", "yaw": 240, "pitch": 40, "distance": 30, "fov": 60, "sway": 8, "raise": 6,
                  "shift": [19.9, 3, 9.3]},
    # A team pumping its balloon (with a face), a rival team's balloon beside it.
    "PumpAndPop": {"yaw": 25, "pitch": 12, "distance": 40, "shift": [0, 8.5, -4], "sway": 8},
    # Two riders who just bumped, the sea and a palm island behind.
    "BumperBallers": {"look_at": "BoingRing", "yaw": 120, "pitch": 34, "distance": 58, "shift": [0, 2, 0], "raise": 4},
    # The archers' tower from the field, a runner and a target board in front.
    "ArrowAmbush": {"yaw": 15, "pitch": 22, "distance": 40, "shift": [0, -3, 2], "raise": 12},
    # Behind the pack, down the bridge: crates ahead, the viaduct towers and the canyon either side.
    "SkateEscape": {"yaw": 12, "pitch": 15, "distance": 30, "shift": [0, 2, 0], "raise": 5, "sway": 8},
    # From over the backdrop: everyone crowding into the photo frame's gold ring, the paparazzi on
    # their tripods down the red carpet and the fans' stand beyond.
    "Slaparazzi": {"look_at": "Gold", "yaw": 180, "pitch": 34, "distance": 36, "fov": 55, "shift": [0, 3, 4],
                   "raise": 11},
    # From the air past the rim: a player at the icy edge, rivals with snowballs behind, the peak's
    # icicles and the sea of clouds far below, spires and mountains beyond.
    "SnowballSummit": {"look_at": "SnowballSummitSnowfield", "yaw": -135, "pitch": 24, "distance": 58,
                       "shift": [-14, 1, -8], "raise": 2},
    # Low through the gaps between the floors: rivals around a fresh hole in the packed snow, one
    # dropping through, two more on the blue ice below (no dolly, so they stay in sight under it).
    "Spleef": {"look_at": "Water", "yaw": 210, "pitch": 8, "distance": 49, "fov": 44, "shift": [2, 27.5, -1],
               "raise": 7, "bob": 1, "dolly": 0},
    # A tank going up in a toy explosion (turret and driver flying) beside a pink rival, a toy brick in
    # front, the playroom window and a beach ball beyond.
    "Tanks": {"look_at": "Cork", "yaw": -60, "pitch": 30, "distance": 44, "shift": [-63, 3.5, -26], "raise": 6},
    # Over the paper pad: stampers on their rubber stamps hopping across a patchwork of everyone's ink,
    # bare ruled paper still to win beyond.
    "StampOut": {"look_at": "Paper", "yaw": 20, "pitch": 50, "distance": 38, "shift": [5, 2, 6], "raise": 6},
    # Into the first scrum on the sandlot: foam bats swinging, a wind-up's reach on the sand, orbs knocked
    # loose flying out, the scoreboard over the fence behind.
    "Struggle": {"look_at": "Sand", "yaw": 20, "pitch": 22, "distance": 19, "shift": [-15.5, 3, 1], "raise": 8},
    # Chasing two riders down their lanes: their crayons drawing purple and teal lines behind them, the
    # dotted guides curving away ahead.
    "TraceRace": {"look_at": "StartLine", "yaw": 0, "pitch": 45, "distance": 46, "shift": [29, 3, -110], "raise": 6},
    # Divers at the rim of the swirling sinkhole, treasure on the sand around it.
    "SinkingSands": {"yaw": 30, "pitch": 30, "distance": 36, "shift": [0, 2, 6]},
    # Low over the water: a shark's fin between the rafts, swimmers and coins on the decks, the
    # lighthouse and the sea stacks beyond.
    "SharkBait": {"look_at": "Gills", "yaw": 35, "pitch": 30, "distance": 27, "shift": [0, 1, 0], "raise": 7, "fov": 58},
}

# Seconds into the round to take the snapshot, where the default (8) isn't the liveliest moment.
DUMP_AT: dict[str, float] = {
    "BobsledRun": 12,  # the sleds well down the run, a banked curve ahead
    "CakeFactory": 14,  # cakes with a few layers on every belt
    "EatsaPizza": 15,  # halfway: some slices eaten down to the pan, teams munching on the rest
    "HexMeltdown": 4.6,  # the first call, halfway through sinking: the called color stays up
    "HoneyTrap": 12,
    "LogJam": 10,  # every mill going, an axe coming down on a log
    "MechaMarathon": 12.5,  # a second after lift-off: the toys climbing away from their pads
    "MessyMemory": 8,  # a second into the mischief: smoke puffs, the last toys tumbling onto the counters
    "ParasolPlummet": 7,  # fallers still spread across the sky, a dozen lobs in the air
    "PrimeCut": 9,  # the first steak, a second before the chop: the knives lined up
    "PumpAndPop": 16,  # the balloons are big by now
    "RockinRaceway": 2.2,  # the pack galloping off the line at the first rows (layouts are random: check)
    "SkateEscape": 10,
    "Slaparazzi": 11.7,  # just before the second photo: everyone crowding into the frame's rings
    "SnowballSummit": 25,  # snowballs rolling, someone teetering at the rim, most still on top
    "Spleef": 12,  # holes dug in every floor, players on all three
    "StampOut": 34,  # BIG STAMPS: the pad patched with everyone's ink, stampers mid-hop
    "Struggle": 4.5,  # the first hits: orbs knocked loose and flying
    "Tanks": 5.5,  # a second after the shields drop: the first tanks blowing up, the rest still rolling
    "TraceRace": 8,  # past the straight start, into the first curves, lines trailing behind
    "SinkingSands": 12,  # treasure out on the sand, someone already in the hole
    "SharkBait": 13,  # a raft tipping, coins spilled in the water, the sharks closing in
}

R15 = {
    "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm",
    "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg",
    "RightLowerLeg", "RightFoot",
}
SKIN = [(255, 204, 160), (234, 184, 146), (196, 140, 104), (141, 98, 72), (255, 220, 190)]
SHIRTS = [(255, 84, 150), (64, 196, 255), (255, 204, 64), (156, 108, 255), (110, 226, 140), (255, 140, 70),
          (255, 255, 255), (80, 120, 255)]
PANTS = [(40, 52, 110), (60, 60, 70), (30, 90, 160), (90, 50, 30), (50, 50, 60), (120, 40, 90)]


def log(text: str):
    print(text, flush=True)


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    result = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, **kwargs)
    if result.returncode != 0:
        sys.stderr.write(result.stdout[-3000:] + result.stderr[-3000:])
        raise SystemExit(f"failed: {' '.join(cmd)}")
    return result


def dump_round(game: str, dump_at: float, players: int) -> Path:
    """Steps 1: a real round on a test server, snapshotted `dump_at` seconds in."""
    base = Path(f"/tmp/pv_{game}")
    luau, result, line_map, dump = (Path(f"{base}.luau"), Path(f"{base}.json"), Path(f"{base}.map.json"),
                                    Path(f"{base}_dump.json"))
    log(f"Playing a round of {game} on a test server (snapshot at {dump_at}s)...")
    script = run([sys.executable, "tools/checks/round_harness.py", game, "--players", str(players), "--dump-at",
                  str(dump_at), "--seconds", str(dump_at + 1), "--client", "--map", str(line_map)]).stdout
    luau.write_text(script)
    run([sys.executable, "tools/preview/luau_task.py", str(luau), "-", str(result)])
    summary = run([sys.executable, "tools/checks/summarize.py", str(result), str(line_map), "--dump", str(dump),
                   "--log", "10"]).stdout
    errors = [line for line in summary.splitlines() if line.startswith("errors")]
    log("  " + (errors[0] if errors else "no summary"))
    return dump


def dress_players(parts: list[dict]) -> list[list[float]]:
    """The stand-in players have plain black rigs: give each an outfit and a round head, like a
    party of real avatars. Returns each one's head position."""
    groups: list[dict[str, dict]] = []
    for part in parts:
        if part["c"] != "MeshPart" or part["n"] not in R15 or part.get("prop"):
            continue
        if not groups or part["n"] in groups[-1]:
            groups.append({})
        groups[-1][part["n"]] = part
    heads = []
    for index, group in enumerate(groups):
        skin = SKIN[(index * 3) % len(SKIN)]
        shirt = SHIRTS[index % len(SHIRTS)]
        pants = PANTS[(index * 5) % len(PANTS)]
        for name, part in group.items():
            if name in ("Head", "LeftHand", "RightHand"):
                part["col"] = list(skin)
            elif "Leg" in name or "Foot" in name or name == "LowerTorso":
                part["col"] = list(pants) if "Foot" not in name else [30, 30, 36]
            else:
                part["col"] = list(shirt)
            part["m"] = "SmoothPlastic"
            if name == "Head":
                part["c"], part["shape"] = "Part", "Ball"
                part["s"] = [s * 1.15 for s in part["s"]]
                heads.append(part["cf"][:3])
    return heads


def player_focus(heads: list[list[float]]) -> list[float]:
    """The middle of the biggest bunch of players (knocked-out ones are back in the lobby, and a
    race spreads out)."""
    best = max(heads, key=lambda head: sum(1 for other in heads if math.dist(head, other) < 25))
    near = [head for head in heads if math.dist(head, best) < 25]
    return [sum(h[i] for h in near) / len(near) for i in range(3)]


def find_focus(camera: dict, parts: list[dict], heads: list[list[float]]) -> list[float]:
    name = camera.get("look_at")
    for part in parts if name else []:
        if part["n"] == name:
            return part["cf"][:3]
    if camera.get("subject") == "highest":
        bunch = player_focus(heads)
        return max((h for h in heads if math.dist(h, bunch) < 80), key=lambda h: h[1])
    return player_focus(heads)


def camera_settings(game: str, overrides: dict | None = None) -> dict:
    camera = dict(DEFAULT_CAMERA)
    camera.update(CAMERAS.get(game, {}))
    camera.update(overrides or {})
    return camera


def camera_path(cam: dict, focus: list[float], frames: int) -> dict[str, list]:
    """A loop: the camera sways side to side around the focus (and bobs and dollies a little),
    ending where it started."""
    fx, fy, fz = (focus[i] + cam["shift"][i] for i in range(3))
    views = {}
    for frame in range(frames):
        phase = 2 * math.pi * frame / frames
        yaw = math.radians(cam["yaw"] + cam["sway"] * math.sin(phase))
        pitch = math.radians(cam["pitch"] + cam.get("bob", 3) * math.sin(2 * phase))
        distance = cam["distance"] * (1 + cam.get("dolly", 0.06) * math.cos(phase))
        flat = distance * math.cos(pitch)
        eye = [fx + flat * math.sin(yaw), fy + distance * math.sin(pitch), fz + flat * math.cos(yaw)]
        lift = distance * math.tan(math.radians(cam["raise"])) / max(0.2, math.cos(pitch))
        views[f"f{frame:02d}"] = [eye, [fx, fy + lift, fz], cam["fov"]]
    return views


def render_frames(game: str, dump: Path, frames: int, samples: int, python: str) -> list[Path]:
    """Step 2: the frames, rendered with Blender."""
    data = json.loads(dump.read_text())
    heads = dress_players(data["parts"])
    if not heads:
        raise SystemExit("No players in the snapshot - is the round over already? Try an earlier --dump-at.")
    camera = camera_settings(game)
    focus = find_focus(camera, data["parts"], heads)
    out_dir = Path(f"/tmp/pv_{game}_frames")
    out_dir.mkdir(exist_ok=True)
    dressed = out_dir / "scene.json"
    dressed.write_text(json.dumps(data))
    cameras = out_dir / "cameras.json"
    views = camera_path(camera, focus, frames)
    cameras.write_text(json.dumps(views))
    nobody = out_dir / "dummies.json"
    nobody.write_text("[]")  # the snapshot has the players; no extra stand-ins
    log(f"Rendering {frames} frames ({FRAME_W}x{FRAME_H}, {samples} samples) around {[round(v) for v in focus]}...")
    started = time.time()
    run([python, str(ROOT / "tools" / "preview" / "render.py"), str(dressed), str(out_dir / game), "--views",
         ",".join(views), "--cameras", str(cameras), "--dummies", str(nobody), "--samples", str(samples),
         "--width", str(FRAME_W), "--height", str(FRAME_H)])
    log(f"  done in {time.time() - started:.0f}s: {out_dir}")
    return [out_dir / f"{game}_{name}.png" for name in views]


def pack_sheet(game: str, paths: list[Path]) -> Path:
    from PIL import Image, ImageEnhance

    rows = math.ceil(len(paths) / COLUMNS)
    sheet = Image.new("RGB", (FRAME_W * COLUMNS, FRAME_H * rows), (20, 14, 40))
    for index, path in enumerate(paths):
        frame = Image.open(path).convert("RGB")
        if frame.size != (FRAME_W, FRAME_H):
            frame = frame.resize((FRAME_W, FRAME_H), Image.LANCZOS)
        # Roblox colors are bold: a little more color and snap than the renderer's soft look.
        frame = ImageEnhance.Color(frame).enhance(1.25)
        frame = ImageEnhance.Contrast(frame).enhance(1.08)
        frame = ImageEnhance.Sharpness(frame).enhance(1.3)
        sheet.paste(frame, ((index % COLUMNS) * FRAME_W, (index // COLUMNS) * FRAME_H))
    assert sheet.width <= 1024 and sheet.height <= 1024, "Roblox caps images at 1024x1024"
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    out = PREVIEWS / f"{game}.jpg"
    sheet.save(out, quality=90, subsampling=0, optimize=True)
    log(f"Sheet: {out.relative_to(ROOT)} ({sheet.width}x{sheet.height}, {out.stat().st_size // 1024} KB)")
    return out


# Runs on a test server: the image inside an uploaded decal.
DECAL_IMAGE = """
local ok, model = pcall(function()
	return game:GetService("InsertService"):LoadAsset(%d)
end)
for _, item in if ok then model:GetDescendants() else {} do
	if item:IsA("Decal") then
		return item.Texture
	end
end
return ""
"""


def image_in(decal_id: int) -> int:
    sys.path.insert(0, str(ROOT / "tools" / "preview"))
    from luau_task import run as run_luau

    for _ in range(6):
        task, _ = run_luau(DECAL_IMAGE % decal_id)
        results = (task.get("output") or {}).get("results") or [""]
        digits = "".join(ch for ch in str(results[0]) if ch.isdigit())
        if digits:
            return int(digits)
        time.sleep(15)  # a brand-new decal can take a moment to load
    raise SystemExit(f"Couldn't find the image in decal {decal_id}; try again with --upload-only later")


def upload_sheet(game: str, sheet: Path, name: str) -> tuple[int, int]:
    """Step 3: upload, find the image, make it Open Use, and let the game use it. Returns the
    image and decal ids."""
    sys.path.insert(0, str(ROOT / "tools"))
    from asset_permissions import grant, open_use
    from upload_assets import upload

    display = f"Party Panic preview: {name}"[:50]
    decal = upload(sheet, "Decal", display, f"Party Panic: a looping preview of {name} for the vote stage.",
                   {"userId": USER_ID}, "image/jpeg")
    image = image_in(decal)
    log(f"Uploaded {sheet.name}: decal {decal}, image {image}")
    opened, errors = open_use([image])
    granted, grant_errors = grant([image, decal])
    log(f"  Open Use: {'yes' if image in opened else 'no'}; the game may use it: {'yes' if image in granted else 'no'}")
    if errors or grant_errors:
        log(f"  permission errors: {json.dumps(errors + grant_errors)[:600]}")
    return image, decal


def write_luau(record: dict):
    """Step 4: src/shared/GamePreviews.luau, generated from the record."""
    lines = [
        "-- Preview \"videos\" of the mini-games for the vote stage's portals (owner: \"maybe we make the",
        "-- portal do a little video of what the game actually is?\"): one sprite sheet per game, played as a",
        "-- flipbook (frame 1 at the top left, then across and down). A game without an entry gets its",
        "-- icon-and-name card.",
        "--",
        "-- GENERATED by tools/preview/make_preview.py from assets/previews/previews.json; don't edit by hand.",
        "-- Make or remake one with: python3 tools/preview/make_preview.py <GameId>",
        "",
        "export type Preview = {",
        "\tImage: string,",
        "\tFrames: number,",
        "\tColumns: number,",
        "\tFrameSize: Vector2,",
        "\tFps: number,",
        "}",
        "",
        "local previews: { [string]: Preview } = {" + ("" if record else "}"),
    ]
    for game in sorted(record):
        entry = record[game]
        lines += [
            f"\t{game} = {{",
            f"\t\tImage = \"rbxassetid://{entry['image']}\",",
            f"\t\tFrames = {entry['frames']},",
            f"\t\tColumns = {entry['columns']},",
            f"\t\tFrameSize = Vector2.new({entry['width']}, {entry['height']}),",
            f"\t\tFps = {entry['fps']},",
            "\t},",
        ]
    lines += (["}"] if record else []) + ["", "return previews", ""]
    LUAU.write_text("\n".join(lines))
    log(f"Wrote {LUAU.relative_to(ROOT)} ({len(record)} previews)")


def game_name(game: str) -> str:
    text = (ROOT / "src" / "shared" / "GameDefinitions.luau").read_text()
    marker = f'Id = "{game}",'
    if marker not in text:
        raise SystemExit(f"{game} isn't in src/shared/GameDefinitions.luau")
    after = text[text.index(marker):]
    return after.split('Name = "', 1)[1].split('"', 1)[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("game", help="the mini-game's Id, e.g. FireRope (or --write-luau alone)", nargs="?")
    parser.add_argument("--dump-at", type=float, help="seconds into the round for the snapshot (default 8)")
    parser.add_argument("--players", type=int, default=8)
    parser.add_argument("--reuse-dump", action="store_true", help="re-render the last snapshot (/tmp/pv_<Id>_dump.json)")
    parser.add_argument("--no-upload", action="store_true", help="stop after the sheet: nothing is uploaded or recorded")
    parser.add_argument("--upload-only", action="store_true", help="upload and record assets/previews/<Id>.jpg as it is")
    parser.add_argument("--frames", type=int, default=FRAMES)
    parser.add_argument("--samples", type=int, default=20)
    parser.add_argument("--python", default=os.environ.get("PP_BPY_PYTHON", "python3"),
                        help="a Python with Blender's bpy module (default: $PP_BPY_PYTHON or python3)")
    parser.add_argument("--write-luau", action="store_true", help="just regenerate GamePreviews.luau from the record")
    args = parser.parse_args()

    record = json.loads(RECORD.read_text()) if RECORD.exists() else {}
    if args.write_luau:
        write_luau(record)
        return
    if not args.game:
        parser.error("which game?")
    name = game_name(args.game)
    if args.frames > COLUMNS * (1024 // FRAME_H):
        raise SystemExit(f"At most {COLUMNS * (1024 // FRAME_H)} frames fit in a 1024x1024 sheet")
    if args.upload_only:
        sheet = PREVIEWS / f"{args.game}.jpg"
        if not sheet.exists():
            raise SystemExit(f"No {sheet.relative_to(ROOT)} yet: make it first (--no-upload)")
        frame_count = args.frames
    else:
        dump = Path(f"/tmp/pv_{args.game}_dump.json")
        if not args.reuse_dump or not dump.exists():
            dump = dump_round(args.game, args.dump_at or DUMP_AT.get(args.game, 8), args.players)
        frames = render_frames(args.game, dump, args.frames, args.samples, args.python)
        sheet = pack_sheet(args.game, frames)
        frame_count = len(frames)
        if args.no_upload:
            log("Not uploaded (--no-upload).")
            return
    image, decal = upload_sheet(args.game, sheet, name)
    record[args.game] = {
        "image": image,
        "decal": decal,
        "frames": frame_count,
        "columns": COLUMNS,
        "width": FRAME_W,
        "height": FRAME_H,
        "fps": FPS,
        "made": time.strftime("%Y-%m-%d"),
    }
    RECORD.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    write_luau(record)
    log("Done. Rebuild the place (rojo build) to ship it; new images show once Roblox's moderation passes them.")


if __name__ == "__main__":
    main()
