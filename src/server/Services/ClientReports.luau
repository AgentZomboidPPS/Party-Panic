-- Records which uploaded meshes a player's device couldn't load (Controllers/AssetReportController
-- sends it), so an invisible prop on someone else's screen shows up here with Roblox's reason
-- instead of only in their F9 console (owner: "My friend still cant see shit"). Reports are kept
-- per player in the PP_ClientReports data store (tools/checks/client_reports.py reads them) and
-- logged to the server output.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local RateLimiter = require(script.Parent.RateLimiter)

local ClientReports = {}

local MAX_FAILED = 60

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
		Checked = if type(report.Checked) == "number" then math.floor(report.Checked) else 0,
		Failed = failed,
		FailedCount = count,
		Where = if type(report.Where) == "string" then string.sub(report.Where, 1, 24) else "?",
		Touch = report.Touch == true,
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
		if entry.FailedCount > 0 then
			warn(
				`[ClientReports] {player.Name} couldn't load {entry.FailedCount} of {entry.Checked} meshes ({entry.Where})`
			)
		end
		if store then
			task.spawn(function()
				pcall(function()
					store:SetAsync(`u{player.UserId}`, entry)
				end)
			end)
		end
	end)
end

return ClientReports
