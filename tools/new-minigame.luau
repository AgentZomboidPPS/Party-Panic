-- Scaffolds a new mini-game: the server module, its client half, a test bot, a props file with a
-- starter mesh, and its definition.
--
--   lune run tools/new-minigame <Id> "<Display Name>" <Category> [--team]
--   lune run tools/new-minigame HotPotato "Hot Potato" Survival
--
-- Categories: Survival, Race, Knockback, Reaction, Team, Luck, Versus. --team makes it a team mode.

local fs = require("@lune/fs")
local process = require("@lune/process")

local CATEGORIES = {
	Survival = { Icon = "🛡️", Color = "255, 120, 90", Results = "Survival" },
	Race = { Icon = "🏁", Color = "80, 200, 255", Results = "Score" },
	Knockback = { Icon = "🥊", Color = "255, 90, 170", Results = "Survival" },
	Reaction = { Icon = "⚡", Color = "255, 210, 60", Results = "Survival" },
	Team = { Icon = "🤝", Color = "120, 230, 120", Results = "Team" },
	Luck = { Icon = "🎲", Color = "190, 130, 255", Results = "Survival" },
	Versus = { Icon = "⚔️", Color = "255, 150, 60", Results = "Team" },
}

local DEFINITIONS = "src/shared/GameDefinitions.luau"
local MARKER = "\t-- NEW MINI-GAMES GO ABOVE THIS LINE"

local function fail(message: string)
	print("✗ " .. message)
	print('Usage: lune run tools/new-minigame <Id> "<Display Name>" <Category> [--team]')
	process.exit(1)
end

local args = process.args
local id, name, category = args[1], args[2], args[3]
local isTeam = table.find(args, "--team") ~= nil

if not id or not name or not category then
	fail("Missing arguments.")
end
if not string.match(id, "^%u%w+$") then
	fail(`Id '{id}' must be PascalCase letters/digits, e.g. HotPotato.`)
end
local info = CATEGORIES[category]
if not info then
	fail(`Unknown category '{category}'. Use one of: Survival, Race, Knockback, Reaction, Team, Luck, Versus.`)
end
if isTeam then
	info = table.clone(info)
	info.Results = "Team"
end

-- Every file the scaffold writes: template -> destination.
local files = {
	{ "tools/templates/MiniGame.luau.template", `src/server/MiniGames/{id}.luau` },
	{ "tools/templates/MiniGameClient.luau.template", `src/client/MiniGames/{id}.luau` },
	{ "tools/templates/MiniGameBot.luau.template", `tools/checks/bots/{id}.luau` },
	{ "tools/templates/Props.luau.template", `src/server/World/Props/{id}.luau` },
	{ "tools/templates/meshgen_props.py.template", `tools/meshgen/props/{id}.py` },
}
for _, pair in files do
	if fs.isFile(pair[2]) then
		fail(`{pair[2]} already exists.`)
	end
end
local definitions = fs.readFile(DEFINITIONS)
if string.find(definitions, `Id = "{id}"`, 1, true) then
	fail(`{id} is already in {DEFINITIONS}.`)
end
local markerAt = string.find(definitions, MARKER, 1, true)
if not markerAt then
	fail(`Couldn't find the insertion marker in {DEFINITIONS}.`)
end

local survival = info.Results == "Survival"
local replacements = {
	Id = id,
	Name = name,
	Category = category,
	Duration = "75",
	Results = info.Results,
	RespawnMode = if survival then "Eliminate" else "Respawn",
	EndWhenOneLeft = if survival then "true" else "false",
}
for _, pair in files do
	local source = string.gsub(fs.readFile(pair[1]), "{{(%w+)}}", function(key)
		return replacements[key] or ("{{" .. key .. "}}")
	end)
	fs.writeFile(pair[2], source)
	print(`✓ Created {pair[2]}`)
end

local escapedName = string.gsub(name, '"', '\\"')
local entry = table.concat({
	"\t{",
	`\t\tId = "{id}",`,
	`\t\tName = "{escapedName}",`,
	`\t\tCategory = "{category}",`,
	`\t\tIcon = "{info.Icon}",`,
	`\t\tColor = Color3.fromRGB({info.Color}),`,
	'\t\tObjective = "TODO: one sentence that explains how to win.",',
	'\t\tControls = "TODO: one short controls tip.",',
	"\t\tDuration = 75,",
	`\t\tMinPlayers = {if isTeam or category == "Knockback" or category == "Versus" then 2 else 1},`,
	`\t\tIsTeam = {if isTeam then "true" else "false"},`,
	"\t\tIsNew = true, -- a little extra vote exposure while it's new; remove later",
	"\t},",
	"",
}, "\n")
definitions = string.sub(definitions, 1, markerAt - 1) .. entry .. string.sub(definitions, markerAt)
fs.writeFile(DEFINITIONS, definitions)

print(`✓ Registered {id} in {DEFINITIONS} (fill in Objective and Controls)`)
print("")
print("Next steps (docs/ADDING_MINIGAMES.md has the details):")
print(`  1. Play a round on a Roblox server with 12 bots and the client half:`)
print(`       python3 tools/checks/round_harness.py {id} --players 12 --client --map map.json > round.luau`)
print("       python3 tools/preview/luau_task.py round.luau - round.json")
print("       python3 tools/checks/summarize.py round.json map.json")
print(`  2. Or in Studio: set Config.Debug.ForceGame = "{id}", rojo serve, press Play`)
print(`  3. Make its props: tools/meshgen/props/{id}.py, then generate_meshes.py --only, upload_assets.py --only`)
