-- Tells the server which of the game's uploaded meshes this device couldn't load, with Roblox's
-- reason (Services/ClientReports keeps it). A mesh Roblox won't let a player load just isn't drawn
-- for them, so this is how we find out without asking anyone for their F9 console (owner: "My
-- friend still cant see shit"). Checked once in the lobby and once in each new arena.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)

local AssetReportController = {}

local MAX_CHECKED = 300

local reported: { [string]: boolean } = {} -- content ids already checked on this device

local function check(where: string)
	local ids = {}
	for _, descendant in workspace:GetDescendants() do
		if #ids >= MAX_CHECKED then
			break
		end
		if descendant:IsA("MeshPart") then
			local id = descendant.MeshId
			if id ~= "" and not reported[id] then
				reported[id] = true
				table.insert(ids, id)
			end
		end
	end
	if #ids == 0 then
		return
	end
	local failed = {}
	pcall(function()
		ContentProvider:PreloadAsync(ids, function(id: string, status: Enum.AssetFetchStatus)
			if status ~= Enum.AssetFetchStatus.Success then
				failed[id] = status.Name
			end
		end)
	end)
	Remotes.Get("ClientReport"):FireServer({
		Checked = #ids,
		Failed = failed,
		Where = where,
		Touch = UserInputService.TouchEnabled,
	})
end

function AssetReportController.Start()
	task.delay(15, check, "Lobby")
	GameState.Changed("Phase", function(phase)
		if phase == "InRound" then
			task.delay(4, check, tostring(GameState.Get("GameId") or "Round"))
		end
	end)
end

return AssetReportController
