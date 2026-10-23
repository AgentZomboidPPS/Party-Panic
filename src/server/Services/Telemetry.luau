-- Lightweight gameplay telemetry (design doc §18 "Events to track").
-- Player events go to Roblox AnalyticsService custom events; server-level events and errors are
-- logged to output so they show up in the Developer Console / Error Report. The funnels, coins
-- (Roblox's economy report) and levels (its progression report) go there too (Services/
-- FunnelService, Services/Economy; owner: "What information should we collect to gage if players
-- are having fun and staying?").

local AnalyticsService = game:GetService("AnalyticsService")
local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Funnels = require(game:GetService("ReplicatedStorage").Shared.Logic.Funnels)

local Telemetry = {}

Telemetry.Counters = {} :: { [string]: number }

local function bump(name: string)
	Telemetry.Counters[name] = (Telemetry.Counters[name] or 0) + 1
end

-- Custom fields from a list (the first is CustomField01, up to three); empty ones are left out.
local FIELD_KEYS = {
	Enum.AnalyticsCustomFieldKeys.CustomField01.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField02.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField03.Name,
}
local function customFields(list: { string? }?): { [string]: string }?
	if not list then
		return nil
	end
	local fields = {}
	local any = false
	for index = 1, 3 do
		local value = list[index]
		if type(value) == "string" and value ~= "" then
			fields[FIELD_KEYS[index]] = string.sub(value, 1, 50)
			any = true
		end
	end
	return if any then fields else nil
end

-- Studio, and anything that only looks like a player (bots, the check tools' stand-ins).
local function skip(player: any): boolean
	return RunService:IsStudio() or typeof(player) ~= "Instance"
end

-- Player-scoped event with a fixed name (e.g. "ShopPurchase") and an optional detail such as the
-- item or mode id. Names stay fixed because Roblox caps the number of distinct custom event names;
-- the detail goes into a custom field instead.
function Telemetry.PlayerEvent(player: Player, name: string, value: number?, detail: string?)
	Telemetry.PlayerEventFields(player, name, value, { detail })
end

-- The same with up to three custom fields (Shared/Logic/Funnels.FIELDS says which is which).
function Telemetry.PlayerEventFields(player: Player, name: string, value: number?, fields: { string? }?)
	bump(name)
	if skip(player) then
		return
	end
	local ok, err = pcall(function()
		AnalyticsService:LogCustomEvent(player, name, value or 1, customFields(fields))
	end)
	if not ok then
		warn(`[Telemetry] LogCustomEvent {name} failed: {err}`)
	end
end

-- A step of a funnel (Creator Hub > Analytics > Funnels; Shared/Logic/Funnels names them): the
-- new-player funnel when `funnel` is nil, else a funnel that runs again and again, `session` telling
-- one run from the next. `fields`: its custom fields (Funnels.FIELDS).
function Telemetry.FunnelStep(
	player: Player,
	funnel: string?,
	session: string?,
	step: number,
	name: string,
	fields: { string? }?
)
	bump(`Funnel:{funnel or "Onboarding"}:{step}`)
	if skip(player) then
		return
	end
	local ok, err = pcall(function()
		if funnel then
			AnalyticsService:LogFunnelStepEvent(player, funnel, session, step, name, customFields(fields))
		else
			AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name, customFields(fields))
		end
	end)
	if not ok then
		warn(`[Telemetry] funnel {funnel or "Onboarding"} step {step} failed: {err}`)
	end
end

-- Coins in (`amount` > 0) or out (< 0) for Roblox's economy report, with the balance after it.
-- `reason` is the game's (Economy's reasons), sorted into Roblox's kinds by Funnels.CoinKinds;
-- `sku`: what was bought or earned (an item id, a game).
function Telemetry.Coins(player: Player, amount: number, balance: number, reason: string, sku: string?)
	bump(if amount >= 0 then "Coins:in" else "Coins:out")
	if skip(player) or amount == 0 then
		return
	end
	local kind = Funnels.CoinKinds[reason] or "Gameplay"
	local ok, err = pcall(function()
		AnalyticsService:LogEconomyEvent(
			player,
			if amount > 0 then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink,
			"Coins",
			math.abs(amount),
			balance,
			kind,
			sku or reason
		)
	end)
	if not ok then
		warn(`[Telemetry] LogEconomyEvent {reason} failed: {err}`)
	end
end

-- Levels completed for Roblox's progression report: every level from `before` to `after` - 1.
function Telemetry.Levels(player: Player, before: number, after: number)
	bump("Levels")
	if skip(player) then
		return
	end
	for level = math.max(1, before), math.min(after - 1, before + 20) do
		local ok, err = pcall(function()
			AnalyticsService:LogProgressionCompleteEvent(player, "Level", level, `Level {level}`)
		end)
		if not ok then
			warn(`[Telemetry] LogProgressionCompleteEvent {level} failed: {err}`)
			return
		end
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
