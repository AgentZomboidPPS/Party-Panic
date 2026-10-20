-- Mini-game registry with automatic discovery.
--
-- Adding a mode takes two steps (see docs/ADDING_MINIGAMES.md, or run `lune run tools/new-minigame`):
--   1. add a ModuleScript to this folder built on Kit/MiniGame (its Id must match the file name)
--   2. add a matching entry to ReplicatedStorage.Shared.GameDefinitions
-- There is no list to update here. A module that fails to load or is missing its definition is
-- disabled with a warning, so one broken mode can never take the whole server down.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameDefinitions = require(ReplicatedStorage.Shared.GameDefinitions)
local MiniGame = require(script.Kit.MiniGame)

local MiniGames = {}

local modules: { [string]: any } = {}

local function validate(name: string, module: any): string?
	if type(module) ~= "table" then
		return "did not return a table"
	end
	if module.Id ~= name then
		return `Id '{tostring(module.Id)}' must match the file name '{name}'`
	end
	if not GameDefinitions.Get(name) then
		return "has no entry in Shared/GameDefinitions"
	end
	for _, method in MiniGame.RequiredMethods do
		if type(module[method]) ~= "function" then
			return `is missing {method}() (build it with Kit/MiniGame.Define)`
		end
	end
	return nil
end

for _, child in script:GetChildren() do
	if not child:IsA("ModuleScript") then
		continue -- the Kit folder and anything else that isn't a mode
	end
	local ok, result = pcall(require, child)
	if not ok then
		warn(`[MiniGames] {child.Name} failed to load and is disabled: {result}`)
		continue
	end
	local problem = validate(child.Name, result)
	if problem then
		warn(`[MiniGames] {child.Name} {problem} - disabled.`)
		continue
	end
	modules[child.Name] = result
end

for _, definition in GameDefinitions.List do
	if not modules[definition.Id] and definition.Enabled ~= false then
		warn(`[MiniGames] {definition.Id} is defined but has no server module - it won't be offered.`)
		definition.Enabled = false
	end
end

function MiniGames.Get(id: string)
	return modules[id]
end

function MiniGames.Ids(): { string }
	local ids = {}
	for id in modules do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

return MiniGames
