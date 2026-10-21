-- Records which uploaded meshes a player's device couldn't load (Controllers/AssetReportController
-- sends it), so an invisible prop on someone else's screen shows up here with Roblox's reason
-- instead of only in their F9 console (owner: "My friend still cant see shit"). Sound reports say
-- the same for the music and effects, and whether the music really plays on that device (owner:
-- "Music isn't working for my friend"). Reports are kept per player in the PP_ClientReports data
-- store (tools/checks/client_reports.py reads them) and logged to the server output.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local RateLimiter = require(script.Parent.RateLimiter)

local ClientReports = {}

local MAX_FAILED = 60

local function number(value: any): number?
	return if type(value) == "number" and value == value then math.floor(value * 100 + 0.5) / 100 else nil
end

-- The music part of a sound report: which track, and whether it is loaded, playing and audible.
local function music(value: any): { [string]: any }?
	if type(value) ~= "table" then
		return nil
	end
	return {
		Track = if type(value.Track) == "string" then string.sub(value.Track, 1, 24) else "?",
		Loaded = value.Loaded == true,
		Playing = value.Playing == true,
		Time = number(value.Time),
		Volume = number(value.Volume),
		Loudness = number(value.Loudness),
		Level = number(value.Level),
	}
end

-- Console lines the device saw about loading sounds (Roblox's reason for a failure).
local function messages(value: any): { string }?
	if type(value) ~= "table" then
		return nil
	end
	local list = {}
	for _, text in value do
		if type(text) == "string" and #list < 6 then
			table.insert(list, string.sub(text, 1, 200))
		end
	end
	return list
end

-- Keeps only what a report can sensibly hold: content ids mapped to a short status.
local function clean(report: any): { [string]: any }?
	if type(report) ~= "table" then
		return nil
	end
	local failed = {}
	local count = 0
	if type(report.Failed) == "table" then
		for id, status in report.Failed do
			if type(id) == "string" and #id <= 64 and type(status) == "string" and count < MAX_FAILED then
				failed[id] = string.sub(status, 1, 40)
				count += 1
			end
		end
	end
	return {
		Kind = if report.Kind == "Sound" then "Sound" else "Mesh",
		Checked = if type(report.Checked) == "number" then math.floor(report.Checked) else 0,
		Failed = failed,
		FailedCount = count,
		Where = if type(report.Where) == "string" then string.sub(report.Where, 1, 24) else "?",
		Touch = report.Touch == true,
		Music = music(report.Music),
		Master = number(report.Master),
		Messages = messages(report.Messages),
		Policy = if type(report.Policy) == "string" then string.sub(report.Policy, 1, 400) else nil,
		Control = if type(report.Control) == "string" then string.sub(report.Control, 1, 24) else nil,
		Time = os.time(),
		Version = Config.Version,
		PlaceVersion = game.PlaceVersion,
	}
end

function ClientReports.Init()
	local limit = Config.RateLimits.ClientReport
	local limiter = RateLimiter.new(limit[1], limit[2])
	local store = if RunService:IsStudio() then nil else DataStoreService:GetDataStore("PP_ClientReports")
	Remotes.Get("ClientReport").OnServerEvent:Connect(function(player, report)
		if not limiter:Check(player) then
			return
		end
		local entry = clean(report)
		if not entry then
			return
		end
		local sound = entry.Kind == "Sound"
		if entry.FailedCount > 0 then
			local what = if sound then "sounds" else "meshes"
			warn(
				`[ClientReports] {player.Name} couldn't load {entry.FailedCount} of {entry.Checked} {what} ({entry.Where})`
			)
		end
		-- Mesh reports keep the latest per player; sound reports one from the lobby and one from a round.
		local key = if sound
			then `s{player.UserId}_{if entry.Where == "Lobby" then "lobby" else "round"}`
			else `u{player.UserId}`
		if store then
			task.spawn(function()
				pcall(function()
					store:SetAsync(key, entry)
				end)
			end)
		end
	end)
end

return ClientReports
