-- Tells the server which of the game's uploaded meshes this device couldn't load, with Roblox's
-- reason (Services/ClientReports keeps it). A mesh Roblox won't let a player load just isn't drawn
-- for them, so this is how we find out without asking anyone for their F9 console (owner: "My
-- friend still cant see shit"). Checked once in the lobby and once in each new arena.
-- The music gets the same check, plus whether it is really playing and how loud, and the player's
-- Roblox volume (owner: "Music isn't working for my friend"): once in the lobby, once in a round.

local ContentProvider = game:GetService("ContentProvider")
local LogService = game:GetService("LogService")
local PolicyService = game:GetService("PolicyService")
local Players = game:GetService("Players")
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

-- Roblox's own words for why this device couldn't load a sound (its console lines about our sound
-- ids, or about loading sounds at all), so the report says why, not just that it failed.
local function soundMessages(ids: { string }): { string }
	local found = {}
	local ok, history = pcall(function()
		return LogService:GetLogHistory()
	end)
	for _, entry in (if ok and type(history) == "table" then history else {}) do
		local text = tostring(entry.message or "")
		local lower = string.lower(text)
		local ours = false
		for _, id in ids do
			if string.find(text, (string.gsub(id, "%D", "")), 1, true) then
				ours = true
				break
			end
		end
		if ours or string.find(lower, "sound", 1, true) or string.find(lower, "audio", 1, true) then
			table.insert(found, string.sub(text, 1, 200))
			if #found >= 6 then
				break
			end
		end
	end
	return found
end

-- The account's content policy flags (some audio rules depend on the player's age and region).
local function policyFlags(): string
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(Players.LocalPlayer)
	end)
	if not ok or type(info) ~= "table" then
		return "?"
	end
	local flags = {}
	for key, value in info do
		if type(value) == "boolean" then
			table.insert(flags, `{key}={if value then 1 else 0}`)
		end
	end
	table.sort(flags)
	return table.concat(flags, " ")
end

local function checkSounds(where: string)
	local sounds, seen, ids = {}, {}, {}
	for _, sound in SoundService:GetChildren() do
		local id = sound:IsA("Sound") and sound.SoundId
		if id and string.find(id, "rbxassetid://", 1, true) and not seen[id] then
			seen[id] = true
			table.insert(sounds, sound)
			table.insert(ids, id)
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
		Messages = if next(failed) then soundMessages(ids) else nil,
		Policy = if next(failed) then policyFlags() else nil,
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
