"""Uploads Party Panic's generated meshes and audio to Roblox (Open Cloud Assets API) and writes the
resulting asset ids into the game config, so the next build uses the real meshes and soundtrack.

    python3 tools/upload_assets.py --user-id 12345678            # upload everything
    python3 tools/upload_assets.py --group-id 7654321 --what audio
    python3 tools/upload_assets.py --user-id 12345678 --dry-run  # show what would happen
    python3 tools/upload_assets.py --user-id 12345678 --what meshes --only Pump,Balloon
    python3 tools/upload_assets.py --user-id 12345678 --what meshes --only Pump --again   # a changed mesh
    python3 tools/upload_assets.py --user-id 12345678 --what modes   # the mini-game song packs
    python3 tools/upload_assets.py --user-id 12345678 --what season  # the crate season's effects

A mini-game's own props (defined in src/server/World/Props/<Game>.luau) get their asset id written
into that file's spec (AssetId = ...); older props use assets/uploaded.json and MeshAssets.luau.

Authentication: set ROBLOX_API_KEY to an Open Cloud API key with the "assets" read+write
permission. Upload under the same user or group that owns the game, because the game loads mesh
models with InsertService, which only works for assets its creator owns.

Limits (Roblox): audio uploads are capped per month (10 without ID verification, 100 with). This
tool needs 4 audio uploads (3 music tracks + 1 sound-effects sprite), plus one per pack of mini-game
songs (build/music/packs/ModePack<N>.ogg, several songs to a file; tools/music/modes.py pack). Uploaded assets go through
moderation; until approved, the game automatically keeps using its built-in fallbacks.
Already-uploaded files are recorded in assets/uploaded.json and skipped on re-runs.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
API = "https://apis.roblox.com/assets/v1"
RECORD = ROOT / "assets" / "uploaded.json"
MESH_CONFIG = ROOT / "src" / "server" / "World" / "MeshAssets.luau"
AUDIO_CONFIG = ROOT / "src" / "shared" / "AudioAssets.luau"

MUSIC = {"Lobby": "Party Plaza", "Lobby2": "Sunset Social", "Round": "Panic Mode"}


def request(method: str, url: str, body: bytes | None = None, headers: dict | None = None) -> dict:
    all_headers = dict(headers or {})
    key = os.environ.get("ROBLOX_API_KEY")
    if key:
        all_headers["x-api-key"] = key
    req = urllib.request.Request(url, data=body, method=method, headers=all_headers)
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            return json.loads(response.read() or b"{}")
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise SystemExit(f"{method} {url} failed: HTTP {error.code}\n{detail}") from error


def multipart(fields: dict[str, tuple[str, bytes, str | None]]) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    parts = []
    for name, (filename, data, content_type) in fields.items():
        header = f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"'
        if filename:
            header += f'; filename="{filename}"'
        header += "\r\n"
        if content_type:
            header += f"Content-Type: {content_type}\r\n"
        parts.append(header.encode() + b"\r\n" + data + b"\r\n")
    body = b"".join(parts) + f"--{boundary}--\r\n".encode()
    return body, f"multipart/form-data; boundary={boundary}"


def upload(path: Path, asset_type: str, display_name: str, description: str, creator: dict, content_type: str) -> int:
    meta = {
        "assetType": asset_type,
        "displayName": display_name,
        "description": description,
        "creationContext": {"creator": creator},
    }
    body, ctype = multipart({
        "request": ("", json.dumps(meta).encode(), None),
        "fileContent": (path.name, path.read_bytes(), content_type),
    })
    operation = request("POST", f"{API}/assets", body, {"Content-Type": ctype})
    op_path = operation.get("path") or f"operations/{operation.get('operationId')}"
    for _ in range(90):
        if operation.get("done"):
            break
        time.sleep(2)
        operation = request("GET", f"{API}/{op_path}")
    if not operation.get("done"):
        raise SystemExit(f"Timed out waiting for {path.name} ({op_path})")
    response = operation.get("response") or {}
    asset_id = response.get("assetId")
    if not asset_id:
        raise SystemExit(f"Upload of {path.name} finished without an asset id: {json.dumps(operation)}")
    return int(asset_id)


def set_luau_value(path: Path, key_path: list[str], value: int):
    """Replaces `Name = <number>,` for the last key, inside the table named by the earlier keys."""
    text = path.read_text()
    if len(key_path) == 2:
        block = re.search(rf"\b{key_path[0]} = \{{(.*?)\n\t\}}", text, re.S)
        if not block:
            raise SystemExit(f"Couldn't find table {key_path[0]} in {path}")
        inner = re.sub(rf"(\b{key_path[1]} = )\d+", rf"\g<1>{value}", block.group(1), count=1)
        text = text[: block.start(1)] + inner + text[block.end(1):]
    else:
        text = re.sub(rf"(\n\t{key_path[0]} = )\d+", rf"\g<1>{value}", text, count=1)
    path.write_text(text)


PROPS_DIR = ROOT / "src" / "server" / "World" / "Props"


def props_file_for(name: str) -> tuple[Path, re.Match] | None:
    """The World/Props/<Game>.luau file whose table defines prop `name`, if any."""
    for path in sorted(PROPS_DIR.glob("*.luau")):
        match = re.search(rf"^(\t+){re.escape(name)} = \{{\n", path.read_text(), re.M)
        if match:
            return path, match
    return None


def spec_block(text: str, match: re.Match) -> tuple[int, int]:
    """Start and end offsets of the spec table that `match` opens."""
    indent = match.group(1)
    end = re.compile(rf"^{indent}\}},?$", re.M).search(text, match.end())
    if not end:
        raise SystemExit(f"Couldn't find the end of the {match.group(0).strip()} spec")
    return match.end(), end.start()


def props_asset_id(path: Path, match: re.Match) -> int:
    text = path.read_text()
    start, end = spec_block(text, match)
    found = re.search(r"\bAssetId = (\d+)", text[start:end])
    return int(found.group(1)) if found else 0


def set_props_asset_id(path: Path, name: str, value: int):
    text = path.read_text()
    match = re.search(rf"^(\t+){re.escape(name)} = \{{\n", text, re.M)
    start, end = spec_block(text, match)
    block = text[start:end]
    if re.search(r"\bAssetId = \d+", block):
        block = re.sub(r"\bAssetId = \d+", f"AssetId = {value}", block, count=1)
    else:
        block = f"{match.group(1)}\tAssetId = {value},\n" + block
    path.write_text(text[:start] + block + text[end:])


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    who = parser.add_mutually_exclusive_group(required=True)
    who.add_argument("--user-id", help="upload as this Roblox user (must own the game)")
    who.add_argument("--group-id", help="upload as this group (must own the game)")
    parser.add_argument("--what", choices=["all", "meshes", "audio", "modes", "season"], default="all")
    parser.add_argument("--only", help="comma-separated mesh names (default: every mesh)")
    parser.add_argument("--again", action="store_true", help="with --only: upload those meshes again even if they're "
                        "up (a mesh whose .glb changed, e.g. tools/meshgen/unfight.py; the new id replaces the old)")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    only = set(args.only.split(",")) if args.only else None
    creator = {"userId": str(args.user_id)} if args.user_id else {"groupId": str(args.group_id)}

    jobs = []
    if args.what in ("all", "meshes"):
        for glb in sorted((ROOT / "assets" / "meshes").glob("*.glb")):
            if only and glb.stem not in only:
                continue
            jobs.append(("mesh", glb.stem, glb, "Model", "model/gltf-binary", f"Party Panic prop: {glb.stem}"))
    if args.what in ("all", "audio"):
        for name, title in MUSIC.items():
            jobs.append(("music", name, ROOT / "assets" / "audio" / "music" / f"{name}.ogg", "Audio", "audio/ogg", f"Party Panic - {title} (original soundtrack)"))
        jobs.append(("sprite", "SfxSprite", ROOT / "assets" / "audio" / "sfx" / "SfxSprite.ogg", "Audio", "audio/ogg", "Party Panic - sound effects"))
    if args.what in ("all", "audio", "season"):
        # The crate season's effects, a sprite of their own (tools/music/compose.py --season).
        jobs.append(("seasonsprite", "SeasonSprite", ROOT / "assets" / "audio" / "sfx" / "SeasonSprite.ogg", "Audio", "audio/ogg", "Party Panic - season sound effects"))
    if args.what in ("all", "audio", "modes"):
        # The mini-games' own round songs, packed several to a file (tools/music/modes.py pack).
        for pack in sorted((ROOT / "build" / "music" / "packs").glob("ModePack*.ogg"), key=lambda p: int(re.sub(r"\D", "", p.stem) or 0)):
            jobs.append(("modepack", pack.stem, pack, "Audio", "audio/ogg", f"Party Panic - mini-game songs ({pack.stem})"))

    record = json.loads(RECORD.read_text()) if RECORD.exists() else {}
    for kind, name, path, asset_type, content_type, display in jobs:
        key = f"{kind}:{name}"
        if not path.exists():
            raise SystemExit(f"Missing {path} - run the generators first (see docs/ASSETS.md)")
        props = props_file_for(name) if kind == "mesh" else None
        if props:
            # A mini-game's own prop: its id lives in its World/Props file, not the shared record.
            existing = 0 if args.again and only else props_asset_id(*props)
            if existing > 0:
                print(f"skip   {key:22s} already uploaded as {existing} ({props[0].name})")
            elif args.dry_run:
                print(f"would upload {key:16s} {path.relative_to(ROOT)} -> {props[0].name}")
            else:
                print(f"upload {key:22s} {path.relative_to(ROOT)} ...", end=" ", flush=True)
                asset_id = upload(path, asset_type, display[:50], display, creator, content_type)
                set_props_asset_id(props[0], name, asset_id)
                print(f"{asset_id} -> {props[0].name}")
            continue
        if key in record and not (args.again and only and kind == "mesh"):
            asset_id = record[key]
            print(f"skip   {key:22s} already uploaded as {asset_id}")
        elif args.dry_run:
            print(f"would upload {key:16s} {path.relative_to(ROOT)} as {asset_type}")
            continue
        else:
            print(f"upload {key:22s} {path.relative_to(ROOT)} ...", end=" ", flush=True)
            asset_id = upload(path, asset_type, display[:50], display, creator, content_type)
            record[key] = asset_id
            RECORD.write_text(json.dumps(record, indent=2) + "\n")
            print(asset_id)
        if kind == "mesh":
            set_luau_value(MESH_CONFIG, [name], asset_id)
        elif kind == "music":
            set_luau_value(AUDIO_CONFIG, ["Music", name], asset_id)
        elif kind == "modepack":
            set_luau_value(AUDIO_CONFIG, ["ModeMusic", name], asset_id)
        elif kind == "seasonsprite":
            set_luau_value(AUDIO_CONFIG, ["SeasonSprite"], asset_id)
        else:
            set_luau_value(AUDIO_CONFIG, ["SfxSprite"], asset_id)

    if not args.dry_run:
        # New uploads are Restricted (asset privacy): without this, only the owner would see them.
        sys.path.insert(0, str(ROOT / "tools"))
        from asset_permissions import grant

        uploaded = [int(v) for v in record.values()]
        for path in (ROOT / "src" / "server" / "World" / "Props").glob("*.luau"):
            uploaded += [int(v) for v in re.findall(r"\bAssetId = (\d+)", path.read_text()) if int(v) > 0]
        granted, errors = grant(uploaded)
        print(f"\nThe game may use {len(granted)} uploaded assets" + (f" (errors: {errors})" if errors else "."))
        print("Done. Rebuild the place (rojo build) to use the uploaded assets.")


if __name__ == "__main__":
    sys.exit(main())
