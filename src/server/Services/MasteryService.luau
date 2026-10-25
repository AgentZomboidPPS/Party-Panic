-- Game Mastery (owner: "If you could add a progression system what would it be?", then, on the plan:
-- "Let's build it. 1 yes 2 gold pass should help a little. 3 yes"): every game has its own rank,
-- BRONZE to LEGEND (Logic/MasteryLogic has the rules, Config.Mastery the numbers).
--   * RewardService asks Record about every person's round played to the end: its mastery points
--     (by place, Multiplier times as many for today's Spotlight games, GoldBonus more for a GOLD
--     PASS owner's top-half finish or team win) and whether its win counts toward the top ranks
--     (ProvenPeople real players in the round, not a private server). A new rank pays its coins,
--     keys and crate at once, shows a celebration card in the lobby (Celebrate, Kind "Mastery"; not
--     for BRONZE, which every game's first round gives), and lets everyone see it (owner: "make
--     players feel like they accomplished something"): the rank pops over their head for everyone
--     in the lobby (MasteryPop, once everyone's back from the round, like the "Lv 10!"), and DIAMOND
--     and LEGEND are told to the whole server. What Record returns goes on the results card.
--   * Today's Spotlight is in GameState "Spotlight" (a JSON list of game ids), redone when the UTC day
--     changes; VotingService offers those games a little more often.
--   * Someone whose past rounds were credited when Mastery came out (Logic/MasteryLogic.Load) is told
--     once, a few seconds after they join.
-- Bots have no profile and get nothing; the server decides everything, the screens only show it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local DailyLogic = require(Shared.Logic.DailyLogic)
local GameDefinitions = require(Shared.GameDefinitions)
local GameState = require(Shared.GameState)
local MasteryLogic = require(Shared.Logic.MasteryLogic)
local Placement = require(Shared.Logic.Placement)
local Remotes = require(Shared.Remotes)

local CrateService = require(script.Parent.CrateService)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.Economy)
local GoldPassService = require(script.Parent.GoldPassService)
local Notifier = require(script.Parent.Notifier)
local Telemetry = require(script.Parent.Telemetry)

local MasteryService = {}

local INTRO_DELAY = 10 -- seconds after joining before the "your past rounds earned..." toast
-- The pop over a head waits while the round (and its results) is on: the players are in the arena.
local HOLD_IN = { Preparing = true, InRound = true, Results = true }
local POP_AFTER_RESPAWN = 2.5 -- seconds into Cleanup (just after the "Lv 10!", which goes at 2)

-- What the results card shows about a round's mastery.
export type Summary = {
	Game: string,
	Gained: number, -- points this round, all in
	Spotlight: number, -- of which the Spotlight's extra
	Gold: number, -- of which the GOLD PASS's bonus
	Before: number, -- rank before the round (0: none)
	After: number, -- rank after it
	P: number, -- points now
	W: number, -- wins that count, now
	Win: boolean, -- this round's win counted toward the top ranks
}

local celebrateRemote = Remotes.Get("Celebrate")
local popRemote = Remotes.Get("MasteryPop")
local heldPops: { [Player]: { Rank: number, Game: string } } = {} -- to pop once back in the lobby

-- The games that count (on in the rotation), and their ids in the game list's order.
local known: { [string]: boolean } = {}
local gameIds: { string } = {}
for _, definition in GameDefinitions.List do
	if definition.Enabled ~= false then
		known[definition.Id] = true
		table.insert(gameIds, definition.Id)
	end
end

local spotlightDay = -1
local spotlight: { string } = {}

-- Today's Spotlight games (worked out again when the UTC day changes, and published).
function MasteryService.Spotlight(): { string }
	local day = DailyLogic.DayNumber(os.time())
	if day ~= spotlightDay then
		spotlightDay = day
		spotlight = MasteryLogic.Spotlight(day, gameIds, Config.Mastery.Spotlight.Count)
		GameState.SetJSON("Spotlight", spotlight)
	end
	return spotlight
end

function MasteryService.IsSpotlight(gameId: string): boolean
	return table.find(MasteryService.Spotlight(), gameId) ~= nil
end

-- A new rank (or several): its rewards, its card (not for BRONZE, which every first round of a game
-- gives: the results card says so), and LEGEND's news for everyone.
local function rankUp(player: Player, definition: any, before: number, after: number)
	local ranks = Config.Mastery.Ranks
	local rank = ranks[after]
	local coins, keys, crates = MasteryLogic.Rewards(ranks, before, after)
	if coins > 0 then
		Economy.AddCoins(player, coins, "Mastery")
	end
	local detail = `{definition.Id} {rank.Id}`
	local gotKeys = keys > 0 and CrateService.GiveKeys(player, keys, "Mastery", detail, true)
	local gotCrates = crates > 0 and CrateService.GiveCrates(player, crates)
	Telemetry.PlayerEvent(player, "MasteryRank", after, definition.Id)
	if rank.Id == "Bronze" then
		return
	end
	local held = heldPops[player]
	if not held or after >= held.Rank then
		heldPops[player] = { Rank = after, Game = definition.Id }
	end
	celebrateRemote:FireClient(player, {
		Kind = "Mastery",
		Game = definition.Id,
		Rank = after,
		Coins = coins,
		Keys = if gotKeys then keys else nil,
		Crates = if gotCrates then crates else nil,
		Items = {},
	})
	if rank.Id == "Legend" then
		Notifier.All(`👑 {player.DisplayName} is now a LEGEND at {string.upper(definition.Name)}!`, "reward", 7)
	elseif rank.Id == "Diamond" then
		Notifier.All(`💎 {player.DisplayName} reached DIAMOND at {string.upper(definition.Name)}!`, "reward", 6)
	end
end

-- The held pops, once everyone is back in the lobby: each new rank over its player's head.
local function flushPops()
	if HOLD_IN[GameState.Get("Phase") or "Waiting"] then
		return
	end
	for player, pop in heldPops do
		heldPops[player] = nil
		local character = player.Character
		if character and player.Parent then
			popRemote:FireAllClients(character, pop.Rank, pop.Game)
		end
	end
end

-- RewardService: `player` played a round of `definition` to the end, in `place` of `playerCount`
-- (`won`: first, or on the winning team), with `people` real players in it. Adds its mastery and
-- pays any new rank. What the results card shows (nil for nobody: bots, someone who left).
function MasteryService.Record(
	player: Player,
	definition: any,
	place: number,
	playerCount: number,
	won: boolean,
	people: number
): Summary?
	local profile = DataService.Get(player)
	if not profile or not known[definition.Id] then
		return nil
	end
	local data = profile.Data :: any
	local settings = Config.Mastery
	local team = definition.IsTeam == true
	local base =
		MasteryLogic.Points({ Place = place, PlayerCount = playerCount, Team = team, Won = won }, settings.Points)
	local goodRound = if team then won else Placement.IsTopHalf(place, playerCount)
	local gained, extra, bonus = MasteryLogic.Earned(
		base,
		MasteryService.IsSpotlight(definition.Id),
		GoldPassService.Owns(player),
		goodRound,
		settings.Spotlight.Multiplier,
		settings.GoldBonus
	)
	local counted = MasteryLogic.ProvenWin(won, people, game.PrivateServerId ~= "", settings.ProvenPeople)
	local before, after, entry = MasteryLogic.Record(data.Mastery, definition.Id, gained, counted, settings.Ranks)
	if after > before then
		rankUp(player, definition, before, after)
	end
	MasteryLogic.SetStats(data.Stats, data.Mastery, settings.Ranks, known)
	DataService.Changed(player)
	return {
		Game = definition.Id,
		Gained = gained,
		Spotlight = extra,
		Gold = bonus,
		Before = before,
		After = after,
		P = entry.P,
		W = entry.W,
		Win = counted,
	}
end

-- Tells a returning player, once, what their past rounds earned.
local function intro(player: Player, profile: any)
	local note = profile.Data.MasteryIntro
	if type(note) ~= "table" or note.Told or not note.Credited then
		return
	end
	note.Told = true
	DataService.Changed(player)
	local ranks = tonumber(note.Ranks) or 0
	if ranks <= 0 then
		return
	end
	task.delay(INTRO_DELAY, function()
		if player.Parent then
			Notifier.Send(
				player,
				`🎮 NEW: GAME MASTERY! Your past rounds already earned {ranks} rank{if ranks == 1 then "" else "s"}. See them in Rewards > Career.`,
				"reward",
				9
			)
		end
	end)
end

function MasteryService.Init()
	MasteryService.Spotlight()
	DataService.ProfileLoaded:Connect(intro)
	GameState.Changed("Phase", function(phase)
		if not HOLD_IN[phase] and next(heldPops) ~= nil then
			task.delay(if phase == "Cleanup" then POP_AFTER_RESPAWN else 0.5, flushPops)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		heldPops[player] = nil
	end)
end

function MasteryService.Start()
	while true do
		task.wait(30)
		MasteryService.Spotlight() -- (publishes the new day's games when the day changes)
	end
end

return MasteryService
