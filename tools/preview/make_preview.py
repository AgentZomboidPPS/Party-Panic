"""Makes a mini-game's preview "video" for the vote stage's portals: a short looping flyover of its
arena mid-round, with the players in action (owner: "maybe we make the portal do a little video of
what the game actually is?").

    python3 tools/preview/make_preview.py FireRope                  # the whole thing
    python3 tools/preview/make_preview.py FireRope --no-upload      # frames and sheet only, to look at
    python3 tools/preview/make_preview.py FireRope --reuse-dump     # skip the server run, re-render
    python3 tools/preview/make_preview.py FireRope --dump-at 14     # snapshot later in the round

What it does:

1. Plays a real round on a Roblox test server with the round harness (tools/checks/round_harness.py:
   8 stand-in players, the mode's client half running too, so client-drawn things like the fire
   rope are there) and snapshots the arena a few seconds in (Open Cloud Luau execution).
2. Renders FRAMES small frames with tools/preview/render.py (Blender) along a camera path that
   sways around the frozen moment and comes back to where it started, so the loop is seamless.
   The frames have the shape of a portal's opening and are packed into one sprite sheet,
   assets/previews/<Id>.png (Roblox caps images at 1024x1024).
3. Uploads the sheet to Roblox as an image under the owner's account (Open Cloud Assets API, like
   tools/upload_assets.py), makes it Open Use and lets the game use it (tools/asset_permissions.py).
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

# The portal opening is 14 x 19.8 studs (LobbyBuilder), so the frames are that shape: 6 x 4 frames
# of 170 x 240 make a 1020 x 960 sheet.
FRAME_W, FRAME_H = 170, 240
COLUMNS = 6
FRAMES = 24
FPS = 10

# Camera per game, around the players' middle (the focus): yaw is where the camera stands, in
# degrees around the focus (0 = on the +Z side looking toward -Z, 90 = on the +X side), pitch is
# how steeply it looks down, distance is from the focus, fov is the vertical view angle, sway is
# how far the camera swings to each side during the loop, and shift moves the focus (studs, x y z).
DEFAULT_CAMERA = {"yaw": 0, "pitch": 32, "distance": 60, "fov": 50, "sway": 12, "shift": [0, 0, 0]}
CAMERAS: dict[str, dict] = {}

# Seconds into the round to take the snapshot, where the default (8) isn't the liveliest moment.
DUMP_AT: dict[str, float] = {}

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


def camera_path(game: str, focus: list[float], frames: int) -> dict[str, list]:
    cam = dict(DEFAULT_CAMERA)
    cam.update(CAMERAS.get(game, {}))
    fx, fy, fz = (focus[i] + cam["shift"][i] for i in range(3))
    views = {}
    for frame in range(frames):
        phase = 2 * math.pi * frame / frames
        yaw = math.radians(cam["yaw"] + cam["sway"] * math.sin(phase))
        pitch = math.radians(cam["pitch"] + cam.get("bob", 3) * math.sin(2 * phase))
        distance = cam["distance"] * (1 + cam.get("dolly", 0.06) * math.cos(phase))
        flat = distance * math.cos(pitch)
        eye = [fx + flat * math.sin(yaw), fy + distance * math.sin(pitch), fz + flat * math.cos(yaw)]
        views[f"f{frame:02d}"] = [eye, [fx, fy, fz], cam["fov"]]
    return views


def render_frames(game: str, dump: Path, frames: int, samples: int, python: str) -> list[Path]:
    """Step 2: the frames, rendered with Blender."""
    data = json.loads(dump.read_text())
    heads = dress_players(data["parts"])
    if not heads:
        raise SystemExit("No players in the snapshot - is the round over already? Try an earlier --dump-at.")
    focus = [sum(h[i] for h in heads) / len(heads) for i in range(3)]
    out_dir = Path(f"/tmp/pv_{game}_frames")
    out_dir.mkdir(exist_ok=True)
    dressed = out_dir / "scene.json"
    dressed.write_text(json.dumps(data))
    cameras = out_dir / "cameras.json"
    views = camera_path(game, focus, frames)
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
    from PIL import Image

    rows = math.ceil(len(paths) / COLUMNS)
    sheet = Image.new("RGB", (FRAME_W * COLUMNS, FRAME_H * rows), (20, 14, 40))
    for index, path in enumerate(paths):
        frame = Image.open(path).convert("RGB")
        sheet.paste(frame, ((index % COLUMNS) * FRAME_W, (index // COLUMNS) * FRAME_H))
    assert sheet.width <= 1024 and sheet.height <= 1024, "Roblox caps images at 1024x1024"
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    out = PREVIEWS / f"{game}.png"
    sheet.save(out, optimize=True)
    log(f"Sheet: {out.relative_to(ROOT)} ({sheet.width}x{sheet.height}, {out.stat().st_size // 1024} KB)")
    return out


def upload_sheet(game: str, sheet: Path, name: str) -> int:
    """Step 3: upload as an image, make it Open Use, and let the game use it."""
    sys.path.insert(0, str(ROOT / "tools"))
    from asset_permissions import grant, open_use
    from upload_assets import API, request, upload

    display = f"Party Panic preview: {name}"[:50]
    asset_id = upload(sheet, "Decal", display, f"Party Panic: a looping preview of {name} for the vote stage.",
                      {"userId": USER_ID}, "image/png")
    info = request("GET", f"{API}/assets/{asset_id}")
    log(f"Uploaded {sheet.name}: asset {asset_id} ({info.get('assetType', '?')})")
    opened, errors = open_use([asset_id])
    granted, grant_errors = grant([asset_id])
    log(f"  Open Use: {'yes' if opened else 'no'}; the game may use it: {'yes' if granted else 'no'}")
    if errors or grant_errors:
        log(f"  permission errors: {json.dumps(errors + grant_errors)[:600]}")
    return asset_id


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
        "local previews: { [string]: Preview } = {",
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
    lines += ["}", "", "return previews", ""]
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
    dump = Path(f"/tmp/pv_{args.game}_dump.json")
    if not args.reuse_dump or not dump.exists():
        dump = dump_round(args.game, args.dump_at or DUMP_AT.get(args.game, 8), args.players)
    frames = render_frames(args.game, dump, args.frames, args.samples, args.python)
    sheet = pack_sheet(args.game, frames)
    if args.no_upload:
        log("Not uploaded (--no-upload).")
        return
    asset_id = upload_sheet(args.game, sheet, name)
    record[args.game] = {
        "image": asset_id,
        "frames": len(frames),
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
