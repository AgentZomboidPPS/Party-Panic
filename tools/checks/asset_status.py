"""Checks that every uploaded asset the game uses is approved by Roblox moderation, so every player
can see and hear it (an asset that is pending or rejected shows for nobody, or only for its owner).

    python3 tools/checks/asset_status.py            # models, audio and images
    python3 tools/checks/asset_status.py --meshes   # also the mesh files inside each model

The images are every rbxassetid:// in src/ that the owner uploaded (the season's icon sheet and
particles, the portal previews, the water textures); Roblox's own (the bots' animations, the music
check's library track) are left out.

The mesh files inside a model are moderated on their own, and they are what other players' devices
download, so run --meshes before publishing. That step loads each model on a Roblox server (Open
Cloud Luau execution), like the game does. Exits with status 1 if anything isn't approved.

Approval isn't enough on its own: with asset privacy, new uploads are Restricted, and other players
only see them once the game has been granted permission (tools/asset_permissions.py, which
upload_assets.py and publish_place.py run automatically).
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
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "preview"))
# The account every upload goes under (the game's owner).
OWNER = int(os.environ.get("PP_OWNER_ID", "11690979745"))


def collect() -> dict[str, int]:
    ids: dict[str, int] = {}
    text = (ROOT / "src" / "server" / "World" / "MeshAssets.luau").read_text()
    for name, value in re.findall(r"^\t(\w+) = (\d+),", text, re.M):
        if int(value) > 0:
            ids[f"mesh:{name}"] = int(value)
    for path in sorted((ROOT / "src" / "server" / "World" / "Props").glob("*.luau")):
        props = path.read_text()
        for match in re.finditer(r"^(\t+)(\w+) = \{\n", props, re.M):
            end = re.compile(rf"^{match.group(1)}\}},?$", re.M).search(props, match.end())
            block = props[match.end(): end.start() if end else len(props)]
            found = re.search(r"\bAssetId = (\d+)", block)
            if found and int(found.group(1)) > 0:
                ids[f"mesh:{match.group(2)}"] = int(found.group(1))
    audio = (ROOT / "src" / "shared" / "AudioAssets.luau").read_text()
    for name, value in re.findall(r"(\w+) = (\d+),", audio):
        if int(value) > 0:
            ids[f"audio:{name}"] = int(value)
    return ids


def info(asset_id: int, mask: str = "moderationResult,state,assetType") -> dict:
    """The Assets API's record of an asset ({"error": "HTTP n"} when it won't say)."""
    url = f"https://apis.roblox.com/assets/v1/assets/{asset_id}?readMask={mask}"
    for attempt in range(6):
        try:
            with urllib.request.urlopen(urllib.request.Request(url), timeout=30) as response:
                return json.loads(response.read())
        except urllib.error.HTTPError as error:
            if error.code != 429 and error.code < 500 or attempt == 5:
                return {"error": f"HTTP {error.code}"}
            time.sleep(2 ** attempt)  # rate limited: back off and ask again
    return {"error": "?"}


def status(asset_id: int) -> tuple[str, str]:
    data = info(asset_id)
    if "error" in data:
        return "?", data["error"]
    state = (data.get("moderationResult") or {}).get("moderationState", "?")
    return data.get("assetType", "?"), state


def collect_images() -> dict[str, int]:
    """Every image the code shows (rbxassetid:// in src/) that the owner uploaded, as
    "image:<file>.<id>": with asset privacy they need the same grants as the meshes."""
    known = set(collect().values())
    found: dict[int, str] = {}
    for path in sorted((ROOT / "src").rglob("*.luau")):
        for number in re.findall(r"rbxassetid://(\d+)", path.read_text()):
            if int(number) not in known:
                found.setdefault(int(number), path.stem)
    images: dict[str, int] = {}
    for asset_id, where in sorted(found.items()):
        data = info(asset_id, "assetType,creationContext")
        creator = ((data.get("creationContext") or {}).get("creator") or {}).get("userId")
        if data.get("assetType") in ("Image", "Decal") and str(creator) == str(OWNER):
            images[f"image:{where}.{asset_id}"] = asset_id
    return images


def inner_meshes(models: dict[str, int]) -> dict:
    """Loads these models on a Roblox server like the game does (InsertService): for each, whether it
    loaded and the mesh files (and textures) inside it."""
    from luau_task import run

    task, _ = run(INNER_SCRIPT % json.dumps(models))
    results = (task.get("output") or {}).get("results") or []
    if not results:
        raise RuntimeError(f"couldn't load the models on a test server: {json.dumps(task.get('error'))[:300]}")
    return json.loads(results[0]) or {}


def audit(meshes: bool = True, quiet: bool = False) -> tuple[list[str], dict[str, int], list[int]]:
    """Checks every model, sound and image (and with `meshes`, every mesh file inside the models) is
    approved. Returns what isn't, every asset by key, and the inner mesh and texture ids. A
    rate-limited answer (HTTP 429) is asked again after a pause, never taken as a verdict."""
    ids = {**collect(), **collect_images()}
    checks: list[tuple[str, int]] = list(ids.items())
    inner: list[int] = []
    load_problems: list[str] = []
    if meshes:
        models = {key: value for key, value in ids.items() if key.startswith("mesh:")}
        loaded = inner_meshes(models)
        for key in models:
            entry = loaded.get(key)
            if not entry or not entry.get("ok"):
                if not quiet:
                    print(f"{key:24s} failed to load: {entry and entry.get('err')}   <-- PLAYERS GET THE FALLBACK")
                load_problems.append(key)
                continue
            for piece, mesh_id, texture in entry["meshes"]:
                for label, content in (("mesh", mesh_id), ("texture", texture)):
                    number = re.sub(r"\D", "", content or "")
                    if number:
                        inner.append(int(number))
                        checks.append((f"{key}.{piece} {label}", int(number)))
    pending = checks
    verdicts: dict[str, tuple[int, str, str]] = {}
    for round_ in range(4):
        retry = []
        for key, asset_id in pending:
            kind, state = status(asset_id)
            verdicts[key] = (asset_id, kind, state)
            if state == "HTTP 429":
                retry.append((key, asset_id))
        if not retry:
            break
        pending = retry
        time.sleep(30 * (round_ + 1))
    problems = list(load_problems)
    for key, (asset_id, kind, state) in verdicts.items():
        flag = "" if state == "Approved" else "   <-- NOT APPROVED"
        if not quiet or flag:
            print(f"{key:36s} {asset_id:<17d} {kind:8s} {state}{flag}")
        if flag:
            problems.append(key)
    return problems, ids, sorted(set(inner))


INNER_SCRIPT = """
local InsertService = game:GetService("InsertService")
local ids = game:GetService("HttpService"):JSONDecode([==[%s]==])
local out = {}
for name, id in ids do
	local ok, container = pcall(InsertService.LoadAsset, InsertService, id)
	local meshes = {}
	if ok then
		for _, descendant in container:GetDescendants() do
			if descendant:IsA("MeshPart") then
				table.insert(meshes, { descendant.Name, descendant.MeshId, descendant.TextureID })
			end
		end
		container:Destroy()
	end
	out[name] = { ok = ok, err = if ok then nil else tostring(container), meshes = meshes }
end
return game:GetService("HttpService"):JSONEncode(out)
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--meshes", action="store_true", help="also check the mesh files inside each model")
    args = parser.parse_args()
    problems, ids, inner = audit(meshes=args.meshes)
    counted = f"{len(ids)} models, sounds and images" + (f" and {len(inner)} mesh files" if args.meshes else "")
    if problems:
        print(f"\n{len(problems)} not approved (of {counted}): {', '.join(problems)}")
        print("Pending assets are usually approved within minutes to hours; rejected ones must be replaced.")
        sys.exit(1)
    print(f"\nEverything is approved ({counted}).")


if __name__ == "__main__":
    main()
