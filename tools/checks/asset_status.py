"""Checks that every uploaded asset the game uses is approved by Roblox moderation, so every player
can see and hear it (an asset that is pending or rejected shows for nobody, or only for its owner).

    python3 tools/checks/asset_status.py            # models and audio
    python3 tools/checks/asset_status.py --meshes   # also the mesh files inside each model

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
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "preview"))


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


def status(asset_id: int) -> tuple[str, str]:
    url = f"https://apis.roblox.com/assets/v1/assets/{asset_id}?readMask=moderationResult,state,assetType"
    try:
        with urllib.request.urlopen(urllib.request.Request(url), timeout=30) as response:
            data = json.loads(response.read())
    except urllib.error.HTTPError as error:
        return "?", f"HTTP {error.code}"
    state = (data.get("moderationResult") or {}).get("moderationState", "?")
    return data.get("assetType", "?"), state


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
    ids = collect()
    problems = []
    for key, asset_id in ids.items():
        kind, state = status(asset_id)
        flag = "" if state == "Approved" else "   <-- NOT APPROVED"
        print(f"{key:24s} {asset_id:<17d} {kind:8s} {state}{flag}")
        if flag:
            problems.append(key)

    if args.meshes:
        from luau_task import run

        models = {key: value for key, value in ids.items() if key.startswith("mesh:")}
        task, _ = run(INNER_SCRIPT % json.dumps(models))
        results = (task.get("output") or {}).get("results") or []
        loaded = json.loads(results[0]) if results else {}
        print(f"\nmesh files inside {len(models)} models:")
        for key in models:
            entry = loaded.get(key)
            if not entry or not entry.get("ok"):
                print(f"{key:24s} failed to load: {entry and entry.get('err')}   <-- PLAYERS GET THE FALLBACK")
                problems.append(key)
                continue
            for piece, mesh_id, texture in entry["meshes"]:
                for label, content in (("mesh", mesh_id), ("texture", texture)):
                    number = re.sub(r"\D", "", content or "")
                    if not number:
                        continue
                    _, state = status(int(number))
                    flag = "" if state == "Approved" else "   <-- NOT APPROVED"
                    print(f"{key + '.' + piece:32s} {label:7s} {number:<17s} {state}{flag}")
                    if flag:
                        problems.append(f"{key}.{piece}")

    if problems:
        print(f"\n{len(problems)} not approved: {', '.join(problems)}")
        print("Pending assets are usually approved within minutes to hours; rejected ones must be replaced.")
        sys.exit(1)
    print("\nEverything is approved.")


if __name__ == "__main__":
    main()
