-- Scaffolds a new mini-game: creates the server module and registers its definition.
--
--   lune run tools/new-minigame <Id> "<Display Name>" <Category> [--team]
--   lune run tools/new-minigame HotPotato "Hot Potato" Survival
--
-- Categories: Survival, Race, Knockback, Reaction, Team. --team makes it a two-team mode.

local fs = require("@lune/fs")
local process = require("@lune/process")

local CATEGORIES = {
	Survival = { Icon = "🛡️", Color = "255, 120, 90", Results = "Survival" },
	Race = { Icon = "🏁", Color = "80, 200, 255", Results = "Score" },
	Knockback = { Icon = "🥊", Color = "255, 90, 170", Results = "Survival" },
	Reaction = { Icon = "⚡", Color = "255, 210, 60", Results = "Survival" },
	Team = { Icon = "🤝", Color = "120, 230, 120", Results = "Team" },
}

local MODULE_DIR = "src/server/MiniGames"
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
	fail(`Unknown category '{category}'. Use one of: Survival, Race, Knockback, Reaction, Team.`)
end
if isTeam then
	info = table.clone(info)
	info.Results = "Team"
end

local modulePath = `{MODULE_DIR}/{id}.luau`
if fs.isFile(modulePath) then
	fail(`{modulePath} already exists.`)
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
local template = fs.readFile("tools/templates/MiniGame.luau.template")
local source = string.gsub(template, "{{(%w+)}}", function(key)
	return replacements[key] or ("{{" .. key .. "}}")
end)
fs.writeFile(modulePath, source)

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
	`\t\tMinPlayers = {if isTeam or category == "Knockback" then 2 else 1},`,
	`\t\tIsTeam = {if isTeam then "true" else "false"},`,
	"\t\tIsNew = true, -- a little extra vote exposure while it's new; remove later",
	"\t},",
	"",
}, "\n")
definitions = string.sub(definitions, 1, markerAt - 1) .. entry .. string.sub(definitions, markerAt)
fs.writeFile(DEFINITIONS, definitions)

print(`✓ Created {modulePath}`)
print(`✓ Registered {id} in {DEFINITIONS} (fill in Objective and Controls)`)
print("")
print("Next steps:")
print(`  1. Set Config.Debug.ForceGame = "{id}" in src/shared/Config.luau`)
print("  2. rojo serve (or rojo build) and press Play in Studio - every vote will offer your mode")
print("  3. Edit Prepare/Start in the new module until it's fun, then clear ForceGame")
