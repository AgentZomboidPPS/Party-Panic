"""Uploads Party Panic's generated meshes and audio to Roblox (Open Cloud Assets API) and writes the
resulting asset ids into the game config, so the next build uses the real meshes and soundtrack.

    python3 tools/upload_assets.py --user-id 12345678            # upload everything
    python3 tools/upload_assets.py --group-id 7654321 --what audio
    python3 tools/upload_assets.py --user-id 12345678 --dry-run  # show what would happen

Authentication: set ROBLOX_API_KEY to an Open Cloud API key with the "assets" read+write
permission. Upload under the same user or group that owns the game, because the game loads mesh
models with InsertService, which only works for assets its creator owns.

Limits (Roblox): audio uploads are capped per month (10 without ID verification, 100 with). This
tool needs 4 audio uploads (3 music tracks + 1 sound-effects sprite). Uploaded assets go through
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


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    who = parser.add_mutually_exclusive_group(required=True)
    who.add_argument("--user-id", help="upload as this Roblox user (must own the game)")
    who.add_argument("--group-id", help="upload as this group (must own the game)")
    parser.add_argument("--what", choices=["all", "meshes", "audio"], default="all")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    creator = {"userId": str(args.user_id)} if args.user_id else {"groupId": str(args.group_id)}

    jobs = []
    if args.what in ("all", "meshes"):
        for glb in sorted((ROOT / "assets" / "meshes").glob("*.glb")):
            jobs.append(("mesh", glb.stem, glb, "Model", "model/gltf-binary", f"Party Panic prop: {glb.stem}"))
    if args.what in ("all", "audio"):
        for name, title in MUSIC.items():
            jobs.append(("music", name, ROOT / "assets" / "audio" / "music" / f"{name}.ogg", "Audio", "audio/ogg", f"Party Panic - {title} (original soundtrack)"))
        jobs.append(("sprite", "SfxSprite", ROOT / "assets" / "audio" / "sfx" / "SfxSprite.ogg", "Audio", "audio/ogg", "Party Panic - sound effects"))

    record = json.loads(RECORD.read_text()) if RECORD.exists() else {}
    for kind, name, path, asset_type, content_type, display in jobs:
        key = f"{kind}:{name}"
        if not path.exists():
            raise SystemExit(f"Missing {path} - run the generators first (see docs/ASSETS.md)")
        if key in record:
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
        else:
            set_luau_value(AUDIO_CONFIG, ["SfxSprite"], asset_id)

    if not args.dry_run:
        print("\nDone. Rebuild the place (rojo build) to use the uploaded assets.")


if __name__ == "__main__":
    sys.exit(main())
