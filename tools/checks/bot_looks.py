"""Checks every catalog item bots wear (src/shared/Logic/BotLooks.luau) on a real Roblox server (Open
Cloud Luau execution): a bot is built wearing each one alone, the way Services/BotService builds them
(Players:CreateHumanoidModelFromDescription), and the item must really be on it: the accessory, the
shirt or pants with their picture, the dynamic head's face controls, the body's own parts. Catalog items can be taken down, so run this now and then and before a publish
that changes the lists. (Owner: "Can we make the bots look more like real players?")

    python3 tools/checks/bot_looks.py

Prints each list's result and every item that didn't show up; exits with status 1 if any didn't.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "preview"))
from luau_task import run  # noqa: E402

LISTS = ("Heads", "Hair", "Hats", "Glasses", "Backs", "Shirts", "Pants")


def read_lists() -> dict:
    text = (ROOT / "src" / "shared" / "Logic" / "BotLooks.luau").read_text()
    lists = {}
    for key in LISTS:
        body = re.search(r"^BotLooks\." + key + r" = \{(.*?)^\}", text, re.S | re.M)
        if not body:
            raise SystemExit(f"BotLooks.{key} not found")
        lists[key] = [int(n) for n in re.findall(r"^\s*(\d+),", body.group(1), re.M)]
    bodies = re.search(r"^BotLooks\.Bodies = \{(.*?)^\}", text, re.S | re.M)
    lists["Bodies"] = {name: [int(n) for n in ids.split(",") if n.strip()]
                       for name, ids in re.findall(r"(\w+) = \{([\d,\s]+)\}", bodies.group(1))}
    return lists


SCRIPT = r"""
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local lists = HttpService:JSONDecode('%s')
local ACCESSORY = { Hair = "HairAccessory", Hats = "HatAccessory", Glasses = "FaceAccessory", Backs = "BackAccessory" }
local function build(setup)
	local description = Instance.new("HumanoidDescription")
	setup(description)
	local ok, model = pcall(Players.CreateHumanoidModelFromDescription, Players, description, Enum.HumanoidRigType.R15)
	if not ok then
		return nil, tostring(model)
	end
	return model, nil
end
local plain = build(function() end)
local plainTorso = plain and (plain:FindFirstChild("UpperTorso") :: MeshPart).MeshId or ""
local results = {}
local function check(key, id, ok, why)
	table.insert(results, { key, id, ok, why or "" }) -- (a nil would drop out of the JSON array)
end
for key, ids in lists do
	if key == "Bodies" then
		for name, parts in ids do
			local model, err = build(function(d)
				d.Torso, d.LeftArm, d.RightArm, d.LeftLeg, d.RightLeg = parts[1], parts[2], parts[3], parts[4], parts[5]
			end)
			local torso = model and model:FindFirstChild("UpperTorso") :: MeshPart?
			check("Bodies", name, torso ~= nil and torso.MeshId ~= plainTorso, err or "its torso is the plain one")
		end
		continue
	end
	for _, id in ids do
		local model, err = build(function(d)
			if ACCESSORY[key] then
				(d :: any)[ACCESSORY[key]] = tostring(id)
			elseif key == "Shirts" then
				d.Shirt = id
			elseif key == "Pants" then
				d.Pants = id
			elseif key == "Heads" then
				d.Head = id
			end
		end)
		local ok, why = false, err
		if model then
			if ACCESSORY[key] then
				ok = model:FindFirstChildOfClass("Accessory") ~= nil
				why = "no accessory on it"
			elseif key == "Shirts" then
				local shirt = model:FindFirstChildOfClass("Shirt")
				ok = shirt ~= nil and shirt.ShirtTemplate ~= ""
				why = "no shirt picture"
			elseif key == "Pants" then
				local pants = model:FindFirstChildOfClass("Pants")
				ok = pants ~= nil and pants.PantsTemplate ~= ""
				why = "no pants picture"
			elseif key == "Heads" then
				local head = model:FindFirstChild("Head")
				ok = head ~= nil and head:FindFirstChildOfClass("FaceControls") ~= nil
				why = "not a dynamic head"
			end
		end
		check(key, id, ok, if ok then nil else why)
	end
end
return HttpService:JSONEncode(results)
"""


def main():
    lists = read_lists()
    task, _ = run(SCRIPT % json.dumps(lists).replace("'", "\\'"))
    output = (task.get("output") or {}).get("results") or []
    if not output:
        print(json.dumps(task.get("error"))[:1000])
        sys.exit(1)
    results = json.loads(output[0])
    bad = [r for r in results if not r[2]]
    counts = {}
    for key, _, ok, _ in results:
        total, good = counts.get(key, (0, 0))
        counts[key] = (total + 1, good + (1 if ok else 0))
    for key in (*LISTS, "Bodies"):
        total, good = counts.get(key, (0, 0))
        print(f"{key:8s} {good}/{total}")
    for key, item, _, why in bad:
        print(f"FAIL {key} {item}: {why}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
