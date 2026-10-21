-- Sitting out (owner: "Also we do need to add somewhere super apparent a toggle where you skip
-- next round or somethiong like that").
--
-- A player can take a break: they stay in the lobby (explore, chat, do the obby) while rounds go
-- on without them, and bots fill in as usual. It's a switch that stays on until they turn it off,
-- and it's gone when they leave the game: the PP_SitOut player attribute, never saved, which every
-- client can see. Turning it on during a round you're in takes effect from the next round (you
-- finish this one); turning it off puts you in the next round that starts.
--
-- Who plays is decided here (Lineup, with Logic/Roster): people sitting out aren't in the round,
-- don't count towards MinPlayers and don't vote (VotingService); when everyone here is sitting
-- out, rounds wait in the lobby (RoundManager). The switch is client/UI/SitOutSwitch, by the phase
-- banner and in Settings. Nobody is put on a break automatically (no AFK detection).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)
local Roster = require(Shared.Logic.Roster)
local Signal = require(Shared.Signal)

local BotRegistry = require(script.Parent.BotRegistry)
local DataService = require(script.Parent.DataService)
local Notifier = require(script.Parent.Notifier)
local RateLimiter = require(script.Parent.RateLimiter)
local Telemetry = require(script.Parent.Telemetry)

local SitOutService = {}

local ATTRIBUTE = "PP_SitOut"

SitOutService.Changed = Signal.new() -- (player, sitOut) after a player sits out or comes back

-- Bots never sit out; people do when they've flipped the switch.
function SitOutService.IsSittingOut(player: any): boolean
	return not BotRegistry.IsBot(player) and player:GetAttribute(ATTRIBUTE) == true
end

-- Who'd play the next round right now: people whose profile has loaded and who aren't sitting
-- out, then the bots that are in the world (Logic/Roster).
function SitOutService.Lineup(): Roster.Lineup<any>
	local everyone: { any } = Players:GetPlayers()
	for _, bot in BotRegistry.List() do
		table.insert(everyone, bot)
	end
	return Roster.Build(everyone, function(who: any): Roster.Candidate
		if BotRegistry.IsBot(who) then
			return { IsBot = true, Ready = who.Character ~= nil, SittingOut = false }
		end
		return {
			IsBot = false,
			Ready = DataService.Get(who) ~= nil,
			SittingOut = SitOutService.IsSittingOut(who),
		}
	end)
end

-- Sits a player out (true) or puts them back in (false), and tells them what happens next.
-- Returns whether anything changed.
function SitOutService.Set(player: Player, sitOut: boolean): boolean
	if BotRegistry.IsBot(player) or not player.Parent or SitOutService.IsSittingOut(player) == sitOut then
		return false
	end
	player:SetAttribute(ATTRIBUTE, sitOut)
	local phase = GameState.Get("Phase")
	if sitOut then
		local playingNow = (phase == "Preparing" or phase == "InRound")
			and player:GetAttribute("PP_InRound") == true
			and player:GetAttribute("PP_Alive") == true
		Notifier.Send(
			player,
			if playingNow
				then "Got it! Finish this round, then you're taking a break."
				else "Taking a break! Rounds go on without you. Tap SITTING OUT to jump back in.",
			"info",
			5
		)
	else
		Notifier.Send(
			player,
			if phase == "Voting"
				then "You're back in! Vote for the next game!"
				else "You're back in! You'll play the next round.",
			"success",
			4
		)
	end
	Telemetry.PlayerEvent(player, "SitOut", 1, if sitOut then "On" else "Off")
	SitOutService.Changed:Fire(player, sitOut)
	return true
end

function SitOutService.Init()
	local limit = Config.RateLimits.SitOut
	local limiter = RateLimiter.new(limit[1], limit[2])
	Remotes.Get("SetSitOut").OnServerEvent:Connect(function(player, sitOut)
		if limiter:Check(player) and type(sitOut) == "boolean" then
			SitOutService.Set(player, sitOut)
		end
	end)
end

return SitOutService
