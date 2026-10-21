"""Gives the game permission to use its own uploaded assets, so every player can see and hear them.

Roblox's asset privacy makes newly uploaded meshes (and models and audio) "Restricted": the owner
still sees them in their own game, but other players' devices aren't allowed to load them until the
game itself has been granted permission. Without it, friends see an empty world (the props, trees
and arena pieces are invisible to everyone but the owner). See
https://create.roblox.com/docs/projects/assets/privacy

    python3 tools/asset_permissions.py                  # every model and sound the game uses
    python3 tools/asset_permissions.py --ids 123,456    # just these

Granting a model also grants the mesh files inside it (grantToDependencies). upload_assets.py and
publish_place.py call this automatically; a grant can't be undone, and that's fine: it only lets
this game use assets its owner made for it.

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
        request = urllib.request.Request(URL, data=json.dumps(body).encode(), method="PATCH", headers=headers)
        for attempt in range(5):
            try:
                with urllib.request.urlopen(request, timeout=60) as response:
                    data = json.loads(response.read() or b"{}")
                granted += [int(i) for i in data.get("successAssetIds", [])]
                errors += data.get("errors", [])
                break
            except urllib.error.HTTPError as error:
                if error.code == 429 or error.code >= 500:
                    time.sleep(2 * (attempt + 1))
                    continue
                errors.append({"http": error.code, "detail": error.read().decode(errors="replace")[:300], "ids": batch})
                break
    return granted, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ids", help="comma-separated asset ids (default: every model and sound the game uses)")
    parser.add_argument("--universe-id", type=int, default=UNIVERSE)
    args = parser.parse_args()
    if args.ids:
        ids = [int(x) for x in args.ids.split(",") if x.strip()]
    else:
        sys.path.insert(0, str(ROOT / "tools" / "checks"))
        from asset_status import collect

        ids = list(collect().values())
    granted, errors = grant(ids, args.universe_id)
    print(f"Game {args.universe_id} may now use {len(granted)} of {len(set(ids))} assets.")
    if errors:
        print("Errors:", json.dumps(errors)[:2000])
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
