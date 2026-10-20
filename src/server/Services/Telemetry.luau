-- Lightweight gameplay telemetry (design doc §18 "Events to track").
-- Player events go to Roblox AnalyticsService custom events; server-level events and errors are
-- logged to output so they show up in the Developer Console / Error Report.

local AnalyticsService = game:GetService("AnalyticsService")
local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local Telemetry = {}

Telemetry.Counters = {} :: { [string]: number }

local function bump(name: string)
	Telemetry.Counters[name] = (Telemetry.Counters[name] or 0) + 1
end

-- Player-scoped event, e.g. "VoteCast", "QuestCompleted", "ShopPurchase".
function Telemetry.PlayerEvent(player: Player, name: string, value: number?)
	bump(name)
	if RunService:IsStudio() then
		return
	end
	local ok, err = pcall(function()
		AnalyticsService:LogCustomEvent(player, name, value or 1)
	end)
	if not ok then
		warn(`[Telemetry] LogCustomEvent {name} failed: {err}`)
	end
end

-- Server-level event, e.g. "RoundStarted", "RoundEnded", "TieResolved".
function Telemetry.ServerEvent(name: string, details: { [string]: any }?)
	bump(name)
	if Config.Debug.LogPhases then
		local parts = {}
		for key, value in details or ({} :: { [string]: any }) do
			table.insert(parts, `{key}={tostring(value)}`)
		end
		table.sort(parts)
		print(`[PartyPanic] {name} {table.concat(parts, " ")}`)
	end
end

-- Errors such as spawn failures, stalled phases, cleanup failures and data-save failures.
function Telemetry.Error(kind: string, message: string)
	bump("Error:" .. kind)
	warn(`[PartyPanic:{kind}] {message}`)
end

return Telemetry
