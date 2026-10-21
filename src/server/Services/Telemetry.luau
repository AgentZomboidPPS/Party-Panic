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

-- Player-scoped event with a fixed name (e.g. "ShopPurchase") and an optional detail such as the
-- item or mode id. Names stay fixed because Roblox caps the number of distinct custom event names;
-- the detail goes into a custom field instead.
function Telemetry.PlayerEvent(player: Player, name: string, value: number?, detail: string?)
	bump(name)
	-- Studio, and anything that only looks like a player (bots, the check tools' stand-ins).
	if RunService:IsStudio() or typeof(player) ~= "Instance" then
		return
	end
	local fields = if detail then { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = detail } else nil
	local ok, err = pcall(function()
		AnalyticsService:LogCustomEvent(player, name, value or 1, fields)
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
