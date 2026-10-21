-- Tells the server which of the game's uploaded meshes this device couldn't load, with Roblox's
-- reason (Services/ClientReports keeps it). A mesh Roblox won't let a player load just isn't drawn
-- for them, so this is how we find out without asking anyone for their F9 console (owner: "My
-- friend still cant see shit"). Checked once in the lobby and once in each new arena.
-- The music gets the same check, plus whether it is really playing and how loud, and the player's
-- Roblox volume (owner: "Music isn't working for my friend"): once in the lobby, once in a round.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)

local AudioController = require(script.Parent.AudioController)

local AssetReportController = {}

local MAX_CHECKED = 300

local reported: { [string]: boolean } = {} -- content ids already checked on this device

local function check(where: string)
	-- One MeshPart per mesh: PreloadAsync must get the part itself (a bare id string is loaded as an
	-- image, which "fails" for every mesh).
	local parts = {}
	for _, descendant in workspace:GetDescendants() do
		if #parts >= MAX_CHECKED then
			break
		end
		if descendant:IsA("MeshPart") then
			local id = descendant.MeshId
			if id ~= "" and not reported[id] then
				reported[id] = true
				table.insert(parts, descendant)
			end
		end
	end
	if #parts == 0 then
		return
	end
	local failed = {}
	pcall(function()
		ContentProvider:PreloadAsync(parts, function(id: string, status: Enum.AssetFetchStatus)
			if status ~= Enum.AssetFetchStatus.Success and id ~= "" then
				failed[id] = status.Name
			end
		end)
	end)
	Remotes.Get("ClientReport"):FireServer({
		Checked = #parts,
		Failed = failed,
		Where = where,
		Touch = UserInputService.TouchEnabled,
	})
end

local function checkSounds(where: string)
	local sounds, seen = {}, {}
	for _, sound in SoundService:GetChildren() do
		local id = sound:IsA("Sound") and sound.SoundId
		if id and string.find(id, "rbxassetid://", 1, true) and not seen[id] then
			seen[id] = true
			table.insert(sounds, sound)
		end
	end
	local failed = {}
	pcall(function()
		ContentProvider:PreloadAsync(sounds, function(id: string, status: Enum.AssetFetchStatus)
			if status ~= Enum.AssetFetchStatus.Success and id ~= "" then
				failed[id] = status.Name
			end
		end)
	end)
	-- Loudness rises and falls with the beat, so keep the loudest of a few samples.
	local music = AudioController.Status()
	for _ = 1, 8 do
		task.wait(0.25)
		local now = AudioController.Status()
		now.Loudness = math.max(now.Loudness, music.Loudness)
		music = now
	end
	local master = nil
	pcall(function()
		master = UserSettings():GetService("UserGameSettings").MasterVolume
	end)
	Remotes.Get("ClientReport"):FireServer({
		Kind = "Sound",
		Checked = #sounds,
		Failed = failed,
		Where = where,
		Touch = UserInputService.TouchEnabled,
		Music = music,
		Master = master,
	})
end

function AssetReportController.Start()
	task.delay(15, check, "Lobby")
	task.delay(30, checkSounds, "Lobby") -- the music has faded in by then
	local roundSounds = false
	GameState.Changed("Phase", function(phase)
		if phase == "InRound" then
			task.delay(4, check, tostring(GameState.Get("GameId") or "Round"))
			if not roundSounds then
				roundSounds = true
				task.delay(12, checkSounds, "Round")
			end
		end
	end)
end

return AssetReportController
