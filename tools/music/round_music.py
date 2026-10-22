"""Renders, checks, packs and uploads the mini-games' own round tracks (tools/music/songs/<Id>.py).

Owner: "put in the backlog custom music for each mini game". Every mini-game gets an original
track (modes.py says how they're written); this tool turns them into what the game plays:

    python3 tools/music/round_music.py render [--only FireRope,HoneyTrap] [--preview DIR]
        renders each song to assets/audio/music/rounds/<Id>.ogg and checks it (below)
    python3 tools/music/round_music.py pack
        packs the rendered tracks into a few "RoundMusic<N>.ogg" files and writes
        src/shared/RoundMusic.luau (which file, where in it, the intro length)
    python3 tools/music/round_music.py check
        decodes the packed files the way a device would and re-checks every track in them
    python3 tools/music/round_music.py upload --user-id 11690979745
        uploads the packed files whose content changed, grants the game permission to play them
        and writes their ids into RoundMusic.luau

Why packed: Roblox allows 10 audio uploads a month without ID verification (100 with). One file
per mini-game would need 25+ uploads; packing ~6 minutes of tracks per file needs about 5, and
the client plays each track as a PlaybackRegion + LoopRegion of its file (like the effects
sprite). A pack keeps its id until its content changes (assets/audio/music/rounds/packs.json).

The checks (a track that fails one is reported and the command exits 1):
- loudness -11 LUFS +-0.5 and true peak under -1 dBTP;
- an intro of at least INTRO_MIN seconds (the rules card and the 3-2-1, Config.Session.RulesTime +
  CountdownTime = 13 s), so the drop lands on GO;
- at least the round's Duration (GameDefinitions) of music after the intro;
- a seamless loop: no jump in level or in the waveform where the end runs into the start;
- no clipping (sample peaks under 0 dBFS after decoding).

Adding a mini-game's track: write tools/music/songs/<Id>.py (copy one, change the band and tune,
keep SONG = Song(Id, title, bpm, intro bars, bars, render)), then render --only <Id>, pack, check,
upload. Until its pack is uploaded and approved the mini-game plays "Panic Mode".
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))

import modes  # noqa: E402
import score  # noqa: E402
import synth as s  # noqa: E402

OUT = ROOT / "assets" / "audio" / "music" / "rounds"
REPORT = OUT / "report.json"
PACKS = OUT / "packs.json"
LUAU = ROOT / "src" / "shared" / "RoundMusic.luau"
DEFINITIONS = ROOT / "src" / "shared" / "GameDefinitions.luau"

INTRO_MIN = 13.0
TARGET_LUFS = -11.0
LUFS_TOLERANCE = 0.5
MAX_TRUE_PEAK = -1.0
PACK_SECONDS = 360.0  # the most music in one uploaded file
PACK_GAP = 1.0  # silence between tracks in a pack (a region seek never catches the next track)
TRACK_QUALITY = "6"  # vorbis quality of the per-track renders (kept as the masters)
PACK_QUALITY = "4"  # and of the packed files the game downloads (~128 kbps)


def durations() -> dict[str, float]:
    """Each mini-game's round length (s) from GameDefinitions."""
    text = DEFINITIONS.read_text()
    out = {}
    for block in re.findall(r"\{\s*\n\s*Id = \"(\w+)\",(.*?)\n\t\}", text, re.S):
        found = re.search(r"Duration = (\d+(?:\.\d+)?)", block[1])
        if found:
            out[block[0]] = float(found.group(1))
    return out


def decode(path: Path) -> np.ndarray:
    raw = subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-i", str(path), "-f", "f32le", "-ac", "2", "-ar", str(s.SR), "-"],
        check=True, capture_output=True,
    ).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).T.astype(np.float64)


def encode(audio: np.ndarray, target: Path, quality: str):
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "x.wav"
        s.write_wav(wav, audio)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", quality, str(target)], check=True)


def seam(audio: np.ndarray) -> dict:
    """How audible the loop point is: the level either side of it, and the sample jump across it
    compared with the track's own biggest sample-to-sample steps."""
    win = s.samples(0.05)
    before, after = audio[:, -win:], audio[:, :win]
    rms = lambda x: 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-9)  # noqa: E731
    jump = float(np.max(np.abs(audio[:, 0] - audio[:, -1])))
    steps = np.abs(np.diff(audio, axis=1))
    typical = float(np.percentile(steps, 99.9))
    return {"levelStep": round(rms(after) - rms(before), 2), "jump": round(jump, 4), "typicalStep": round(typical, 4)}


def check_track(song_id: str, audio: np.ndarray, intro: float, rounds: dict[str, float]) -> tuple[dict, list[str]]:
    length = audio.shape[1] / s.SR
    loud = score.lufs(audio)
    peak = score.true_peak_db(audio)
    sample_peak = 20 * np.log10(np.max(np.abs(audio)) + 1e-12)
    joint = seam(audio)
    body = length - intro
    duration = rounds.get(song_id)
    stats = {
        "seconds": round(length, 2),
        "intro": round(intro, 3),
        "body": round(body, 2),
        "round": duration,
        "lufs": round(loud, 2),
        "truePeak": round(peak, 2),
        "samplePeak": round(sample_peak, 2),
        "seam": joint,
    }
    problems = []
    if abs(loud - TARGET_LUFS) > LUFS_TOLERANCE:
        problems.append(f"loudness {loud:.2f} LUFS (target {TARGET_LUFS})")
    if peak > MAX_TRUE_PEAK:
        problems.append(f"true peak {peak:.2f} dBTP (max {MAX_TRUE_PEAK})")
    if sample_peak >= -0.01:
        problems.append("clipping")
    if intro < INTRO_MIN - 1e-6:
        problems.append(f"intro {intro:.2f}s (needs {INTRO_MIN}s)")
    if duration is None:
        problems.append("no GameDefinitions entry")
    elif body < duration:
        problems.append(f"{body:.1f}s after the intro, the round is {duration:.0f}s")
    if abs(joint["levelStep"]) > 6 or joint["jump"] > max(4 * joint["typicalStep"], 0.02):
        problems.append(f"loop seam {joint}")
    return stats, problems


def load_report() -> dict:
    return json.loads(REPORT.read_text()) if REPORT.exists() else {}


def cmd_render(args) -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    wanted = set(args.only.split(",")) if args.only else None
    rounds = durations()
    report = load_report()
    failed = 0
    if args.preview:
        args.preview.mkdir(parents=True, exist_ok=True)
    for song in modes.songs():
        if wanted and song.id not in wanted:
            continue
        audio, track = song.render()
        intro = song.intro * track.bar
        target = OUT / f"{song.id}.ogg"
        encode(audio, target, TRACK_QUALITY)
        # Judge what a device decodes, not the float render.
        stats, problems = check_track(song.id, decode(target), intro, rounds)
        stats.update({"title": song.title, "bpm": song.bpm, "problems": problems})
        report[song.id] = stats
        if args.preview:
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(target), "-b:a", "160k", str(args.preview / f"{song.id}.mp3")], check=True)
        mark = "ok" if not problems else "PROBLEMS: " + "; ".join(problems)
        print(f"{song.id:15} {stats['seconds']:6.1f}s intro {intro:5.2f}s body {stats['body']:5.1f}s (round {stats['round']}) "
              f"{stats['lufs']:6.2f} LUFS {stats['truePeak']:6.2f} dBTP  {mark}")
        failed += bool(problems)
    REPORT.write_text(json.dumps(report, indent=1, sort_keys=True) + "\n")
    missing = sorted(set(rounds) - {song.id for song in modes.songs()})
    if missing and not wanted:
        print("no track yet (plays Panic Mode):", ", ".join(missing))
    return 1 if failed else 0


def plan_packs(ids: list[str]) -> list[list[str]]:
    """Tracks in a stable order, a new pack whenever the next one would go over PACK_SECONDS."""
    report = load_report()
    packs, current, used = [], [], 0.0
    for song_id in ids:
        length = report[song_id]["seconds"] + PACK_GAP
        if current and used + length > PACK_SECONDS:
            packs.append(current)
            current, used = [], 0.0
        current.append(song_id)
        used += length
    if current:
        packs.append(current)
    return packs


def cmd_pack(_args) -> int:
    report = load_report()
    ids = [song.id for song in modes.songs() if (OUT / f"{song.id}.ogg").exists() and song.id in report]
    bad = [i for i in ids if report[i].get("problems")]
    if bad:
        print("render these again first (they failed a check):", ", ".join(bad))
        return 1
    previous = json.loads(PACKS.read_text()) if PACKS.exists() else {}
    packs = {}
    regions = {}
    for number, members in enumerate(plan_packs(ids), start=1):
        name = f"RoundMusic{number}"
        gap = np.zeros((2, s.samples(PACK_GAP)))
        pieces, cursor = [], 0.0
        for song_id in members:
            audio = decode(OUT / f"{song_id}.ogg")
            length = audio.shape[1] / s.SR
            regions[song_id] = (name, cursor, length, report[song_id]["intro"], report[song_id]["title"])
            pieces += [audio, gap]
            cursor += length + PACK_GAP
        audio = np.hstack(pieces)
        digest = hashlib.sha256(np.round(audio * 32767).astype(np.int16).tobytes()).hexdigest()[:16]
        encode(audio, OUT / f"{name}.ogg", PACK_QUALITY)
        old = previous.get(name, {})
        packs[name] = {"tracks": members, "hash": digest, "id": old.get("id", 0) if old.get("hash") == digest else 0}
        size = (OUT / f"{name}.ogg").stat().st_size / 1e6
        state = "unchanged, keeps its id" if packs[name]["id"] else "needs uploading"
        print(f"{name}: {cursor:.0f}s, {size:.1f} MB, {len(members)} tracks ({', '.join(members)}) - {state}")
    for stale in set(previous) - set(packs):
        (OUT / f"{stale}.ogg").unlink(missing_ok=True)
    PACKS.write_text(json.dumps(packs, indent=1) + "\n")
    write_luau(packs, regions)
    return 0


def write_luau(packs: dict, regions: dict):
    lines = [
        "-- GENERATED by tools/music/round_music.py (pack / upload) - do not edit by hand.",
        "-- Each mini-game's own round track: which packed file it's in (Packs), where in that file it",
        "-- sits (Start, Length; seconds) and when its drop lands (Intro: seconds from the start of the",
        "-- track; AudioController lines that up with GO). A pack id of 0 isn't uploaded yet: those",
        "-- mini-games play Panic Mode.",
        "",
        "return {",
        "\tPacks = {",
    ]
    for name, pack in packs.items():
        lines.append(f"\t\t{name} = {pack['id']},")
    lines += ["\t},", "\tTracks = {"]
    for song_id in sorted(regions):
        name, start, length, intro, title = regions[song_id]
        lines.append(
            f'\t\t{song_id} = {{ Pack = "{name}", Start = {start:.4f}, Length = {length:.4f}, Intro = {intro:.4f}, Title = "{title}" }},'
        )
    lines += ["\t},", "}", ""]
    LUAU.write_text("\n".join(lines))
    print(f"wrote {LUAU.relative_to(ROOT)}")


def cmd_check(_args) -> int:
    packs = json.loads(PACKS.read_text())
    report = load_report()
    rounds = durations()
    failed = 0
    text = LUAU.read_text()
    for name, pack in packs.items():
        audio = decode(OUT / f"{name}.ogg")
        for song_id in pack["tracks"]:
            found = re.search(rf"\b{song_id} = \{{ Pack = \"{name}\", Start = ([\d.]+), Length = ([\d.]+), Intro = ([\d.]+)", text)
            start, length, intro = (float(found.group(k)) for k in (1, 2, 3))
            piece = audio[:, s.samples(start): s.samples(start) + s.samples(length)]
            stats, problems = check_track(song_id, piece, intro, rounds)
            if abs(stats["seconds"] - report[song_id]["seconds"]) > 0.05:
                problems.append("region length differs from the render")
            mark = "ok" if not problems else "PROBLEMS: " + "; ".join(problems)
            print(f"{name} {song_id:15} {stats['lufs']:6.2f} LUFS {stats['truePeak']:6.2f} dBTP seam {stats['seam']}  {mark}")
            failed += bool(problems)
    return 1 if failed else 0


def cmd_upload(args) -> int:
    sys.path.insert(0, str(ROOT / "tools"))
    import asset_permissions  # noqa: E402
    import upload_assets  # noqa: E402

    packs = json.loads(PACKS.read_text())
    creator = {"groupId": str(args.group_id)} if args.group_id else {"userId": str(args.user_id)}
    todo = [name for name, pack in packs.items() if not pack["id"]]
    if not todo:
        print("every pack is uploaded")
        return 0
    print(f"uploading {len(todo)} pack(s): {', '.join(todo)}")
    if args.dry_run:
        return 0
    new_ids = []
    for name in todo:
        pack = packs[name]
        titles = ", ".join(pack["tracks"])
        asset_id = upload_assets.upload(
            OUT / f"{name}.ogg", "Audio", f"Party Panic - round music {name[len('RoundMusic'):]}",
            f"Original mini-game music for Party Panic ({titles}).", creator, "audio/ogg",
        )
        pack["id"] = asset_id
        new_ids.append(asset_id)
        PACKS.write_text(json.dumps(packs, indent=1) + "\n")
        text = LUAU.read_text()
        LUAU.write_text(re.sub(rf"(\n\t\t{name} = )\d+,", rf"\g<1>{asset_id},", text, count=1))
        print(f"{name}: {asset_id}")
    granted, errors = asset_permissions.grant(new_ids)
    print(f"granted the game use of {len(granted)} pack(s)" + (f"; errors: {errors}" if errors else ""))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    render = sub.add_parser("render")
    render.add_argument("--only", help="comma-separated mini-game ids")
    render.add_argument("--preview", type=Path, help="also write MP3s to listen to into this folder")
    sub.add_parser("pack")
    sub.add_parser("check")
    upload = sub.add_parser("upload")
    upload.add_argument("--user-id", type=int)
    upload.add_argument("--group-id", type=int)
    upload.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    return {"render": cmd_render, "pack": cmd_pack, "check": cmd_check, "upload": cmd_upload}[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
