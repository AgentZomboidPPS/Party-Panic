"""Builds Party Panic and publishes it to an existing Roblox experience (Open Cloud), then sets the
place's name, store description and server size.

    python3 tools/publish_place.py --universe-id 1234567890 --place-id 9876543210 --dry-run
    python3 tools/publish_place.py --universe-id 1234567890 --place-id 9876543210

Open Cloud can't create a new experience, so create it once in Studio (File > Publish to Roblox
As > New experience, which starts private) and pass its ids here. Both ids are in the Creator Hub
URL of the experience and of its start place.

Authentication: set ROBLOX_API_KEY to an Open Cloud API key with "universe-places" write
(publishing) and "universe.place" write (name and description) for this experience.

If Studio has the place open with Collaborative Editing, Roblox refuses with 409 until that session
ends (up to ~20 minutes after everyone leaves); --wait-minutes keeps retrying until then.

Safety: this refuses to publish when the experience is public, so a test build can't go live by
accident. Pass --allow-public to publish to a public experience on purpose.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLACE_FILE = ROOT / "build" / "PartyPanic.rbxl"
DESCRIPTION_FILE = ROOT / "docs" / "STORE_DESCRIPTION.txt"
CLOUD = "https://apis.roblox.com/cloud/v2"
PUBLISH = "https://apis.roblox.com/universes/v1"

DISPLAY_NAME = "Party Panic"
SERVER_SIZE = 12  # matches Config.Session.MaxPlayers
DESCRIPTION_LIMIT = 1000


def request(method: str, url: str, body: bytes | None = None, headers: dict | None = None) -> dict:
    all_headers = dict(headers or {})
    key = os.environ.get("ROBLOX_API_KEY")
    if key:
        all_headers["x-api-key"] = key
    req = urllib.request.Request(url, data=body, method=method, headers=all_headers)
    try:
        with urllib.request.urlopen(req, timeout=300) as response:
            return json.loads(response.read() or b"{}")
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise SystemExit(f"{method} {url} failed: HTTP {error.code}\n{detail}") from error


def read_description() -> str:
    description = DESCRIPTION_FILE.read_text(encoding="utf-8").strip()
    if len(description) > DESCRIPTION_LIMIT:
        raise SystemExit(f"{DESCRIPTION_FILE.name} is {len(description)} characters (limit {DESCRIPTION_LIMIT})")
    return description


def build():
    PLACE_FILE.parent.mkdir(exist_ok=True)
    subprocess.run(["rojo", "build", "-o", str(PLACE_FILE)], cwd=ROOT, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--universe-id", type=int, required=True)
    parser.add_argument("--place-id", type=int, required=True)
    parser.add_argument("--no-build", action="store_true", help="publish the existing build/PartyPanic.rbxl")
    parser.add_argument("--allow-public", action="store_true", help="allow publishing to a public experience")
    parser.add_argument("--dry-run", action="store_true", help="check everything, publish nothing")
    parser.add_argument("--wait-minutes", type=float, default=0, help="keep retrying while Studio holds the place")
    args = parser.parse_args()

    description = read_description()
    universe_url = f"{CLOUD}/universes/{args.universe_id}"
    place_url = f"{universe_url}/places/{args.place_id}"

    universe = request("GET", universe_url)
    visibility = universe.get("visibility", "UNKNOWN")
    print(f"Experience: {universe.get('displayName')!r}, visibility {visibility}")
    if visibility != "PRIVATE" and not args.allow_public:
        sys.exit(f"Refusing to publish: the experience is {visibility}, not PRIVATE (use --allow-public).")

    place = request("GET", place_url)
    print(f"Place: {place.get('displayName')!r}, server size {place.get('serverSize')}")

    if not args.no_build:
        build()
    if not PLACE_FILE.exists():
        sys.exit(f"{PLACE_FILE} not found; build it first")
    size_mb = PLACE_FILE.stat().st_size / 1e6
    print(f"Place file: {PLACE_FILE.relative_to(ROOT)} ({size_mb:.1f} MB), description {len(description)} chars")

    if args.dry_run:
        print("Dry run: nothing published.")
        return

    # Asset privacy: new uploads are Restricted, and only the owner sees them until the game is
    # granted permission. Re-grant every model and sound on each publish so nothing is invisible.
    sys.path.insert(0, str(ROOT / "tools"))
    sys.path.insert(0, str(ROOT / "tools" / "checks"))
    from asset_permissions import grant
    from asset_status import collect

    asset_ids = list(collect().values())
    granted, grant_errors = grant(asset_ids, args.universe_id)
    print(f"The game may use {len(granted)} of {len(set(asset_ids))} models and sounds")
    if grant_errors:
        sys.exit(f"Refusing to publish: couldn't grant asset permissions: {json.dumps(grant_errors)[:1000]}")

    # 409 "Server is busy" means a Collaborative Editing session still holds the place. It can stay
    # alive for up to ~20 minutes after everyone leaves Studio, so retry with backoff.
    deadline = time.time() + args.wait_minutes * 60
    delay = 30
    while True:
        try:
            version = request(
                "POST",
                f"{PUBLISH}/{args.universe_id}/places/{args.place_id}/versions?versionType=Published",
                PLACE_FILE.read_bytes(),
                {"Content-Type": "application/octet-stream"},
            )
            break
        except SystemExit as error:
            if "HTTP 409" not in str(error) or time.time() + delay > deadline:
                raise
            print(f"Place is locked by a Studio session; retrying in {delay}s", flush=True)
            time.sleep(delay)
            delay = min(delay * 2, 240)
    print(f"Published version {version.get('versionNumber')}")

    patch = {"displayName": DISPLAY_NAME, "description": description, "serverSize": SERVER_SIZE}
    try:
        request(
            "PATCH",
            f"{place_url}?updateMask={','.join(patch)}",
            json.dumps(patch).encode(),
            {"Content-Type": "application/json"},
        )
        # The API can accept an update it didn't apply (missing scope), so read it back.
        place = request("GET", place_url)
        mismatched = [field for field, value in patch.items() if place.get(field) != value]
        if mismatched:
            print(f"Warning: these place settings did not apply: {', '.join(mismatched)} (check the key's scopes)")
        else:
            print(f"Set name {DISPLAY_NAME!r}, description and server size {SERVER_SIZE}")
    except SystemExit as error:
        # The version is already live; settings are a separate permission (universe.place write).
        print(f"Warning: published, but couldn't update the place settings: {error}")

    universe = request("GET", universe_url)
    print(f"Experience visibility is still {universe.get('visibility', 'UNKNOWN')}")


if __name__ == "__main__":
    main()
