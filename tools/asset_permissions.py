"""Makes sure every player can see and hear the game's own uploaded assets.

Roblox's asset privacy makes uploaded meshes (and models and audio) "Restricted": the owner still
sees them in their own game, but other players' devices aren't allowed to load them, so friends see
an empty world (the props, trees and arena pieces are invisible to everyone but the owner). See
https://create.roblox.com/docs/projects/assets/privacy . Two grants fix it:

- the game (universe) may Use every model, sound and image it loads, and
- every mesh file inside those models, and every image, is Open Use (subject "All"), the way they
  worked before asset privacy, so any device can load it whatever account or test mode it's in.

    python3 tools/asset_permissions.py                  # all of it (loads the models on a test server)
                                                        # (models, sounds, and the images in src/)
    python3 tools/asset_permissions.py --quick          # skip the mesh files (no test server)
    python3 tools/asset_permissions.py --ids 123,456    # grant the game just these

upload_assets.py and publish_place.py call this automatically. Grants can't be undone, and that's
fine: they only open up props the owner made for this game.

Authentication: an Open Cloud API key with the "asset-permissions" write permission
(ROBLOX_API_KEY, or a proxy that adds it).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UNIVERSE = int(os.environ.get("PP_UNIVERSE_ID", "10772087888"))
URL = "https://apis.roblox.com/asset-permissions-api/v1/assets/permissions"
BATCH = 20
# Roblox rate-limits these calls (HTTP 429): wait and ask again, longer each time.
BACKOFF = (5, 10, 20, 40, 60, 60)


def patch(body: dict, headers: dict) -> tuple[dict | None, dict | None]:
    """One permissions call: (its answer, or None and the error after the retries)."""
    request = urllib.request.Request(URL, data=json.dumps(body).encode(), method="PATCH", headers=headers)
    for attempt, wait in enumerate((0,) + BACKOFF):
        time.sleep(wait)
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.loads(response.read() or b"{}"), None
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")[:300]
            if (error.code == 429 or error.code >= 500) and attempt < len(BACKOFF):
                continue
            return None, {"http": error.code, "detail": detail}
    return None, {"http": "?"}


def grant(asset_ids: list[int], universe_id: int = UNIVERSE) -> tuple[list[int], list]:
    """Grants the game `universe_id` use of these assets (and what they contain). Returns the ids
    Roblox confirmed and any errors."""
    headers = {"Content-Type": "application/json"}
    if os.environ.get("ROBLOX_API_KEY"):
        headers["x-api-key"] = os.environ["ROBLOX_API_KEY"]
    granted: list[int] = []
    errors: list = []
    ids = sorted(set(int(i) for i in asset_ids if int(i) > 0))
    for start in range(0, len(ids), BATCH):
        batch = ids[start : start + BATCH]
        body = {
            "subjectType": "Universe",
            "subjectId": str(universe_id),
            "action": "Use",
            "requests": [{"assetId": asset_id, "grantToDependencies": True} for asset_id in batch],
        }
        data, error = patch(body, headers)
        if data is None:
            errors.append({**(error or {}), "ids": batch})
            continue
        granted += [int(i) for i in data.get("successAssetIds", [])]
        errors += data.get("errors", [])
    return granted, errors


def open_use(mesh_ids: list[int]) -> tuple[list[int], list]:
    """Makes these mesh (or image) assets Open Use: anyone's device may load them."""
    headers = {"Content-Type": "application/json"}
    if os.environ.get("ROBLOX_API_KEY"):
        headers["x-api-key"] = os.environ["ROBLOX_API_KEY"]
    opened: list[int] = []
    errors: list = []
    ids = sorted(set(int(i) for i in mesh_ids if int(i) > 0))
    for start in range(0, len(ids), BATCH):
        batch = ids[start : start + BATCH]
        body = {"subjectType": "All", "action": "Use", "requests": [{"assetId": asset_id} for asset_id in batch]}
        data, error = patch(body, headers)
        if data is None:
            errors.append({**(error or {}), "ids": batch})
            continue
        opened += [int(i) for i in data.get("successAssetIds", [])]
        errors += data.get("errors", [])
    return opened, errors


def inner_meshes(model_ids: dict[str, int]) -> list[int]:
    """The mesh files (and textures) inside these uploaded models (loads them on a Roblox test server)."""
    sys.path.insert(0, str(ROOT / "tools" / "checks"))
    sys.path.insert(0, str(ROOT / "tools" / "preview"))
    from asset_status import inner_meshes as load

    ids: list[int] = []
    for entry in load(model_ids).values():
        for _, mesh_id, texture in (entry or {}).get("meshes", []):
            for content in (mesh_id, texture):
                number = "".join(ch for ch in (content or "") if ch.isdigit())
                if number:
                    ids.append(int(number))
    return ids


def grant_all(universe_id: int = UNIVERSE, meshes: bool = True, inner: list[int] | None = None) -> tuple[str, list, list[int]]:
    """Both grants for everything the game uses: the game may Use every model, sound and image (and
    what they hold), and every mesh file inside the models and every image is Open Use. `inner`: the
    mesh files, if they're known already (else the models are loaded on a test server to find them).
    Returns a summary line, any errors, and the ids Roblox didn't confirm (all must be, for every
    player to see everything)."""
    sys.path.insert(0, str(ROOT / "tools" / "checks"))
    from asset_status import collect, collect_images

    ids = {**collect(), **collect_images()}
    wanted = set(ids.values())
    granted, errors = grant(list(wanted), universe_id)
    missing = sorted(wanted - set(granted))
    summary = f"the game may use {len(wanted & set(granted))} of {len(wanted)} models, sounds and images"
    # The owner's CAPY GO BOOM meshes and textures that Capy Go Boom borrows (plain assets, not models).
    borrowed = ROOT / "assets" / "capy_borrowed_assets.json"
    if borrowed.exists():
        extra = set(json.loads(borrowed.read_text()).get("grant", []))
        extra_granted, extra_errors = grant(sorted(extra), universe_id)
        errors += extra_errors
        missing += sorted(extra - set(extra_granted))
        summary += f"; {len(extra & set(extra_granted))} of {len(extra)} borrowed Capy Go Boom assets"
    if meshes:
        if inner is None:
            inner = inner_meshes({key: value for key, value in ids.items() if key.startswith("mesh:")})
        images = {value for key, value in ids.items() if key.startswith("image:")}
        to_open = set(inner) | images
        opened, open_errors = open_use(sorted(to_open))
        errors += open_errors
        missing += sorted(to_open - set(opened))
        summary += f"; {len(to_open & set(opened))} of {len(to_open)} mesh files and images are Open Use"
    return summary, errors, missing


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ids", help="comma-separated asset ids (default: every model and sound the game uses)")
    parser.add_argument("--universe-id", type=int, default=UNIVERSE)
    parser.add_argument("--quick", action="store_true", help="skip opening the mesh files (no test server)")
    args = parser.parse_args()
    if args.ids:
        ids = [int(x) for x in args.ids.split(",") if x.strip()]
        granted, errors = grant(ids, args.universe_id)
        print(f"Game {args.universe_id} may now use {len(granted)} of {len(set(ids))} assets.")
    else:
        summary, errors, missing = grant_all(args.universe_id, meshes=not args.quick)
        print(summary[0].upper() + summary[1:] + ".")
        if missing:
            print(f"Not confirmed by Roblox: {missing[:50]}")
            return 1
    if errors:
        print("Errors:", json.dumps(errors)[:2000])
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
