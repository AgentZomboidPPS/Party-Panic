"""Party Panic's mini-game round songs: one original song per mini-game, packed for Roblox.

Owner: "put in the backlog custom music for each mini game". Until now every round played "Panic
Mode"; now each arena has its own band, tempo and tune. Each song is one file in tools/music/songs
(<ModeId>.py, written with score.py's lead-sheet notation and played by instruments.py; songkit.py
lists the rules every song keeps):

    FireRope      "Dragon Temple Drums"   taiko, a bamboo flute and koto over a lava temple
    HexMeltdown   "Molten Showdown"       a game-show disco-funk band in a volcano crater
    HoneyTrap     "Honeycomb Hush"        tiptoeing bassoon and pizzicato in a storybook meadow
    ...and one for every other mode as it's written (`python3 tools/music/modes.py list`).

    python3 tools/music/modes.py list                  # the songs, and the modes without one
    python3 tools/music/modes.py render [Id ...]       # render into build/music/<Id>.wav (all if none)
    python3 tools/music/modes.py check                 # lengths against the rounds, loudness, peaks
    python3 tools/music/modes.py pack                  # assets/audio/modes/ModePack<N>.ogg + src/shared/ModeMusic.luau
    python3 tools/music/modes.py preview DIR [Id ...]  # MP3s to listen to

Roblox caps audio uploads per month (10 without ID verification, 100 with) and each file at about
7 minutes, so songs go up packed, several to a file of at most PACK_SECONDS, and the game plays each
as a region of its pack (AudioController: the intro starts so its end, the drop, lands on GO; after
that the part from the drop to the end loops). packs.json records which song sits where. A pack
that's been uploaded (its id in assets/uploaded.json, "modepack:<Pack>") is never rebuilt: new songs
go into a new pack, and `pack` refuses to change an uploaded one (re-render a song in it and you
need --replace <Pack> and a new upload).
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
import tempfile
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))

import synth as s  # noqa: E402
from score import lufs, true_peak_db  # noqa: E402

SONGS_DIR = HERE / "songs"
CACHE = ROOT / "build" / "music"
OUT = ROOT / "assets" / "audio" / "modes"
MANIFEST = HERE / "packs.json"
LUAU = ROOT / "src" / "shared" / "ModeMusic.luau"
RECORD = ROOT / "assets" / "uploaded.json"
DEFINITIONS = ROOT / "src" / "shared" / "GameDefinitions.luau"

PACK_SECONDS = 415.0  # each pack stays under Roblox's 7 minute cap
GAP = 0.5  # silence between songs in a pack
MIN_INTRO = 13.0  # the rules card and the 3-2-1
TARGET_LUFS, LUFS_SLACK, MAX_PEAK = -11.0, 1.0, -1.0


BROKEN: dict[str, str] = {}  # song files that failed to load, and why (check reports them)


def load_songs() -> dict:
    """Every SONG in tools/music/songs, by mode id. A file that fails to load is left out (and listed
    in BROKEN), so one song being written can't stop every other song from rendering."""
    songs = {}
    for path in sorted(SONGS_DIR.glob("*.py")):
        spec = importlib.util.spec_from_file_location(f"songs.{path.stem}", path)
        module = importlib.util.module_from_spec(spec)
        try:
            spec.loader.exec_module(module)
        except Exception as error:  # noqa: BLE001 (any mistake in a song file)
            if path.stem not in BROKEN:
                print(f"warning: {path.name} doesn't load ({type(error).__name__}: {error}); skipping it", file=sys.stderr)
            BROKEN[path.stem] = f"{type(error).__name__}: {error}"
            continue
        song = getattr(module, "SONG", None)
        if song is None:
            raise SystemExit(f"{path.name} has no SONG")
        if song.id != path.stem:
            raise SystemExit(f"{path.name} defines the song for {song.id}; name the file {song.id}.py")
        songs[song.id] = song
    return songs


def round_lengths() -> dict[str, int]:
    """Every mode's round Duration from GameDefinitions.luau."""
    text = DEFINITIONS.read_text()
    return {m.group(1): int(m.group(2)) for m in re.finditer(r'Id = "(\w+)",.*?Duration = (\d+)', text, re.S)}


def seconds_of(song, bars: int) -> float:
    return bars * 4 * 60 / song.bpm


def _render_one(song_id: str) -> str:
    song = load_songs()[song_id]
    audio, track = song.render()
    if track.bars != song.bars or abs(track.bpm - song.bpm) > 1e-9:
        raise SystemExit(f"{song_id}: SONG says {song.bars} bars at {song.bpm}, the track is {track.bars} at {track.bpm}")
    CACHE.mkdir(parents=True, exist_ok=True)
    s.write_wav(CACHE / f"{song_id}.wav", audio)
    info = {
        "title": song.title,
        "seconds": audio.shape[1] / s.SR,
        "intro": seconds_of(song, song.intro),
        "lufs": round(lufs(audio), 2),
        "peak": round(true_peak_db(audio), 2),
    }
    (CACHE / f"{song_id}.json").write_text(json.dumps(info, indent=1) + "\n")
    return f"{song_id}: {info['seconds']:.1f}s, intro {info['intro']:.1f}s, {info['lufs']} LUFS, peak {info['peak']} dBTP"


def render(ids: list[str], workers: int):
    songs = load_songs()
    ids = ids or sorted(songs)
    unknown = [i for i in ids if i not in songs]
    if unknown:
        raise SystemExit(f"no song for {unknown} (songs: {sorted(songs)})")
    with ProcessPoolExecutor(max_workers=max(1, workers)) as pool:
        for line in pool.map(_render_one, ids):
            print(line, flush=True)


def check() -> int:
    """Prints every song against its round; returns the number of hard problems."""
    songs, rounds = load_songs(), round_lengths()
    problems = 0
    print(f"{'mode':16s} {'song':24s} {'total':>6s} {'intro':>6s} {'after':>6s} {'round':>6s} {'LUFS':>6s} {'peak':>6s}  notes")
    for song_id in sorted(songs):
        song = songs[song_id]
        cached = CACHE / f"{song_id}.json"
        info = json.loads(cached.read_text()) if cached.exists() else None
        intro = seconds_of(song, song.intro)
        total = seconds_of(song, song.bars)
        after = total - intro
        length = rounds.get(song_id)
        notes = []
        if song_id not in rounds:
            notes.append("not in GameDefinitions yet")  # a game still being built elsewhere
        if intro < MIN_INTRO:
            notes.append(f"INTRO UNDER {MIN_INTRO:.0f}s")
            problems += 1
        if length and after < length:
            notes.append(f"loops after {after:.0f}s")
        if info is None:
            notes.append("not rendered")
        else:
            if abs(info["lufs"] - TARGET_LUFS) > LUFS_SLACK:
                notes.append("LOUDNESS OFF")
                problems += 1
            if info["peak"] > MAX_PEAK:
                notes.append("PEAKS TOO HOT")
                problems += 1
        print(
            f"{song_id:16s} {song.title[:24]:24s} {total:6.1f} {intro:6.1f} {after:6.1f} {length or 0:6d} "
            f"{info['lufs'] if info else 0:6.1f} {info['peak'] if info else 0:6.1f}  {', '.join(notes)}"
        )
    for song_id, why in sorted(BROKEN.items()):
        print(f"{song_id:16s} BROKEN FILE: {why}")
        problems += 1
    missing = sorted(set(rounds) - set(songs) - set(BROKEN))
    if missing:
        print(f"\nModes without a song yet (they play \"Panic Mode\"): {', '.join(missing)}")
    return problems


def uploaded_packs() -> set[str]:
    record = json.loads(RECORD.read_text()) if RECORD.exists() else {}
    return {key.split(":", 1)[1] for key in record if key.startswith("modepack:")}


def pack(replace: set[str], fresh: bool = False) -> None:
    """Fills packs with the rendered songs, builds every pack that isn't uploaded, writes the Luau table.
    With `fresh`, every pack that isn't uploaded is filled again from scratch (longest songs first), so
    the songs take as few packs, and uploads, as possible."""
    songs = load_songs()
    manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}
    frozen = uploaded_packs() - replace
    if fresh:
        manifest = {name: p for name, p in manifest.items() if name in frozen}
    placed = {entry["id"]: name for name, p in manifest.items() for entry in p["songs"]}

    def wav(song_id: str) -> np.ndarray:
        path = CACHE / f"{song_id}.wav"
        if not path.exists():
            raise SystemExit(f"{song_id} isn't rendered: python3 tools/music/modes.py render {song_id}")
        return read_wav(path)

    # Songs already in a pack that's not uploaded yet are re-packed from their latest render; songs in
    # a frozen pack stay exactly where the uploaded file has them.
    for name in list(manifest):
        if name not in frozen:
            manifest[name]["songs"] = [e for e in manifest[name]["songs"] if e["id"] in songs]
    renders = {song_id: wav(song_id) for song_id in songs if placed.get(song_id) not in frozen}
    # First fit, longest songs first: the fewest packs.
    order = sorted((i for i in songs if i not in placed), key=lambda i: (-renders[i].shape[1], i))
    for song_id in order:
        if placed.get(song_id) in frozen:
            continue
        seconds = renders[song_id].shape[1] / s.SR
        if seconds > PACK_SECONDS:
            raise SystemExit(f"{song_id} is {seconds:.0f}s, longer than a pack ({PACK_SECONDS:.0f}s)")
        home = placed.get(song_id)
        if home is None:
            for name in sorted(manifest, key=pack_number):
                if name in frozen:
                    continue
                used = sum(renders[e["id"]].shape[1] / s.SR + GAP for e in manifest[name]["songs"])
                if used + seconds <= PACK_SECONDS:
                    home = name
                    break
            if home is None:
                home = f"ModePack{1 + max([pack_number(n) for n in manifest] or [0])}"
                manifest[home] = {"songs": []}
            manifest[home]["songs"].append({"id": song_id})
            placed[song_id] = home

    OUT.mkdir(parents=True, exist_ok=True)
    for name in sorted(manifest, key=pack_number):
        if name in frozen:
            print(f"{name}: uploaded, unchanged ({', '.join(e['id'] for e in manifest[name]['songs'])})")
            continue
        pieces, cursor = [], 0.0
        for entry in manifest[name]["songs"]:
            audio = renders[entry["id"]]
            song = songs[entry["id"]]
            length = audio.shape[1] / s.SR
            entry.update(
                title=song.title,
                start=round(cursor, 3),
                drop=round(cursor + seconds_of(song, song.intro), 3),
                end=round(cursor + length, 3),
            )
            pieces += [audio, np.zeros((2, s.samples(GAP)))]
            cursor += length + GAP
        if not pieces:
            del manifest[name]
            continue
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / f"{name}.wav"
            s.write_wav(path, np.hstack(pieces))
            s.encode(path, OUT / f"{name}.ogg", "ogg")
        size = (OUT / f"{name}.ogg").stat().st_size / 1e6
        print(f"{name}: {cursor:.1f}s, {size:.1f} MB ({', '.join(e['id'] for e in manifest[name]['songs'])})")

    MANIFEST.write_text(json.dumps(manifest, indent=1) + "\n")
    write_luau(manifest)


def pack_number(name: str) -> int:
    match = re.search(r"(\d+)$", name)
    return int(match.group(1)) if match else 0


def read_wav(path: Path) -> np.ndarray:
    from scipy.io import wavfile

    rate, data = wavfile.read(path)
    if rate != s.SR:
        raise SystemExit(f"{path} is {rate} Hz, expected {s.SR}")
    if data.dtype.kind == "i":
        data = data.astype(np.float64) / np.iinfo(data.dtype).max
    return data.T.astype(np.float64)


def write_luau(manifest: dict) -> None:
    lines = [
        "-- GENERATED by tools/music/modes.py - do not edit by hand.",
        "-- Each mini-game's own round song: which packed file in assets/audio/modes it's in (its asset id is",
        "-- AudioAssets.ModeMusic[Pack]) and where, in seconds: the song plays from Start, its intro ends at",
        "-- Drop (timed to land on GO), and the part from Drop to End loops in a longer round.",
        "",
        "return {",
    ]
    entries = sorted((e["id"], name, e) for name, p in manifest.items() for e in p["songs"])
    for song_id, name, e in entries:
        title = e["title"].replace('"', '\\"')
        lines.append(
            f'\t{song_id} = {{ Pack = "{name}", Title = "{title}", Start = {e["start"]:.3f}, '
            f'Drop = {e["drop"]:.3f}, End = {e["end"]:.3f} }},'
        )
    lines.append("}")
    LUAU.write_text("\n".join(lines) + "\n")
    print(f"wrote {LUAU.relative_to(ROOT)} ({len(entries)} songs in {len(manifest)} packs)")
    add_pack_ids(sorted(manifest, key=pack_number))


AUDIO_ASSETS = ROOT / "src" / "shared" / "AudioAssets.luau"


def add_pack_ids(packs: list[str]) -> None:
    """Gives every pack a line in AudioAssets.ModeMusic (0 until tools/upload_assets.py uploads it)."""
    text = AUDIO_ASSETS.read_text()
    text = text.replace("\n\tModeMusic = {},\n", "\n\tModeMusic = {\n\t},\n")  # StyLua writes an empty table on one line
    block = re.search(r"\n\tModeMusic = \{\n(.*?)\t\},?\n", text, re.S)
    if not block:
        raise SystemExit(f"{AUDIO_ASSETS.relative_to(ROOT)} has no ModeMusic table")
    have = set(re.findall(r"\b(ModePack\d+) = \d+", block.group(1)))
    added = [name for name in packs if name not in have]
    if added:
        lines = "".join(f"\t\t{name} = 0,\n" for name in added)
        text = text[: block.end(1)] + lines + text[block.end(1):]
        AUDIO_ASSETS.write_text(text)
        print(f"added {', '.join(added)} to {AUDIO_ASSETS.relative_to(ROOT)} (0 until uploaded)")


def preview(folder: Path, ids: list[str]) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    for song_id in ids or sorted(load_songs()):
        path = CACHE / f"{song_id}.wav"
        if not path.exists():
            raise SystemExit(f"{song_id} isn't rendered")
        s.encode(path, folder / f"{song_id}.mp3", "mp3")
        print(folder / f"{song_id}.mp3")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list")
    r = sub.add_parser("render")
    r.add_argument("ids", nargs="*")
    r.add_argument("--workers", type=int, default=3)
    sub.add_parser("check")
    p = sub.add_parser("pack")
    p.add_argument("--replace", default="", help="comma-separated uploaded packs to rebuild anyway (needs a new upload)")
    p.add_argument("--fresh", action="store_true", help="fill every pack that isn't uploaded again, longest songs first")
    v = sub.add_parser("preview")
    v.add_argument("folder", type=Path)
    v.add_argument("ids", nargs="*")
    args = parser.parse_args()
    if args.command == "list":
        songs, rounds = load_songs(), round_lengths()
        for song_id, song in sorted(songs.items()):
            print(f"{song_id:16s} {song.title:28s} {song.bpm:5.0f} bpm, {seconds_of(song, song.bars):5.1f}s")
        print(f"\nwithout a song: {', '.join(sorted(set(rounds) - set(songs))) or 'none'}")
    elif args.command == "render":
        render(args.ids, args.workers)
    elif args.command == "check":
        return 1 if check() else 0
    elif args.command == "pack":
        pack({name for name in args.replace.split(",") if name}, args.fresh)
    elif args.command == "preview":
        preview(args.folder, args.ids)
    return 0


if __name__ == "__main__":
    sys.exit(main())
