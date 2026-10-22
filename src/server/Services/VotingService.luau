-- Builds valid options, records one vote per player, resolves ties and broadcasts live counts
-- (design doc §6 and §14 "VotingService"). Players vote with the cards on screen (the CastVote
-- remote); the stage's portals only show a preview of each option (owner: "the portals being how
-- you vote is dumb. maybe we make the portal do a little video of what the game actually is?").
-- Only people who'll play the next round vote: someone sitting out (SitOutService) can't, and the
-- vote they had goes when they sit out; the vote cards say why (VoteController).
-- The vote doesn't keep anyone waiting (owner: "Less time sitting in the lobby. total of 20
-- seconds instead of 40."): once every person who'll play has voted (bots and people sitting out
-- don't), it ends Config.Session.VoteLastBeat after the last vote, so that voter sees their tick
-- before the winner shows (Wait, Logic/VoteLogic.ClosesAt), and the phase timer says so.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local GameDefinitions = require(Shared.GameDefinitions)
local GamePicker = require(Shared.Logic.GamePicker)
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)
local VoteLogic = require(Shared.Logic.VoteLogic)

local BotRegistry = require(script.Parent.BotRegistry)
local DataService = require(script.Parent.DataService)
local Notifier = require(script.Parent.Notifier)
local QuestService = require(script.Parent.QuestService)
local RateLimiter = require(script.Parent.RateLimiter)
local SitOutService = require(script.Parent.SitOutService)
local Telemetry = require(script.Parent.Telemetry)

local VotingService = {}

export type VoteOption = { Id: string, Mystery: boolean }

local rng = Random.new()
local active = false
local options: { VoteOption } = {}
local votes: { [Player]: number } = {}
local votedThisRound: { [Player]: boolean } = {}
local lastVoteAt = 0 -- os.clock() of the latest vote cast or changed

local function publishCounts()
	local counts = VoteLogic.Tally(votes, #options)
	GameState.SetJSON("VoteCounts", counts)
end

-- The vote: three games, then always a fourth card, Random (owner: "4 options always. and the 4th
-- option should be random"). Random is a game picked now and kept hidden (Mystery) until it wins:
-- one that isn't on the other cards when there's one to spare.
function VotingService.BuildOptions(playerCount: number, recent: { string }, ignoreLimits: boolean): { VoteOption }
	local pool = {}
	for _, definition in GameDefinitions.List do
		table.insert(pool, {
			Id = definition.Id,
			Category = definition.Category,
			MinPlayers = definition.MinPlayers,
			Weight = definition.Weight,
			IsNew = definition.IsNew,
			Enabled = definition.Enabled,
		})
	end
	local function pick(from, count: number): { string }
		return GamePicker.Pick(from, {
			PlayerCount = playerCount,
			Count = count,
			Recent = recent,
			RecentMemory = Config.Session.RecentGameMemory,
			RandomFloat = function()
				return rng:NextNumber()
			end,
			IgnorePlayerLimits = ignoreLimits,
		})
	end
	local result: { VoteOption } = {}
	for _, id in pick(pool, Config.Session.VoteChoices) do
		table.insert(result, { Id = id, Mystery = false })
	end
	if #result == 0 then
		return result
	end
	local rest = {}
	for _, entry in pool do
		local shown = false
		for _, option in result do
			shown = shown or option.Id == entry.Id
		end
		if not shown then
			table.insert(rest, entry)
		end
	end
	local random = pick(rest, 1)[1] or result[rng:NextInteger(1, #result)].Id
	table.insert(result, { Id = random, Mystery = true })
	return result
end

function VotingService.Begin(newOptions: { VoteOption })
	options = newOptions
	votes = {}
	votedThisRound = {}
	lastVoteAt = 0
	active = true
	for _, player in Players:GetPlayers() do
		player:SetAttribute("PP_Vote", 0)
	end
	GameState.SetJSON("VoteOptions", options)
	publishCounts()
	Notifier.Sound(nil, "VoteOpen")
end

function VotingService.IsActive(): boolean
	return active
end

function VotingService.Cast(player: Player, index: any): boolean
	if not active or not player.Parent then
		return false
	end
	if not VoteLogic.IsValidChoice(index, #options) then
		return false
	end
	if BotRegistry.IsBot(player) then
		return false -- only people pick the next game (owner: "remove the option for bots voting"); bots play whatever wins
	end
	if SitOutService.IsSittingOut(player) then
		return false -- taking a break: only the people who'll play pick the game
	end
	if not DataService.Get(player) then
		return false -- profile still loading
	end
	if votes[player] == index then
		return true
	end
	local changed = votes[player] ~= nil
	votes[player] = index
	lastVoteAt = os.clock()
	player:SetAttribute("PP_Vote", index)
	publishCounts()
	Notifier.Sound({ player }, "VoteClick")

	if not votedThisRound[player] then
		votedThisRound[player] = true
		local profile = DataService.Get(player)
		if profile then
			profile.Data.Stats.Votes += 1
		end
		QuestService.Track(player, "Voted")
	end
	Telemetry.PlayerEvent(player, if changed then "VoteChanged" else "VoteCast", index)
	return true
end

-- Who votes on the next game: the people who'll play it (SitOutService's lineup, without its
-- bots; people sitting out or still loading aren't in it).
local function voters(): { Player }
	local list = {}
	for _, who in SitOutService.Lineup().Participants do
		if not BotRegistry.IsBot(who) then
			table.insert(list, who)
		end
	end
	return list
end

-- Waits out the open vote: `duration` seconds, or until VoteLastBeat after the last vote once every
-- person who'll play has voted (VoteLogic.ClosesAt; someone arriving puts the full time back). The
-- phase timer (PhaseEndsAt) follows, so everyone's banner shows the vote closing. Returns false at
-- once if `abort` says so (RoundManager: everyone went on a break, so nobody can vote).
function VotingService.Wait(duration: number, abort: (() -> boolean)?): boolean
	local deadline = os.clock() + duration
	local closesAt = deadline
	while true do
		if abort and abort() then
			return false
		end
		local now = os.clock()
		local due = VoteLogic.ClosesAt(deadline, voters(), votes, lastVoteAt, Config.Session.VoteLastBeat)
		if due ~= closesAt then
			closesAt = due
			GameState.Set("PhaseEndsAt", workspace:GetServerTimeNow() + math.max(0, due - now))
		end
		if now >= closesAt then
			return true
		end
		task.wait(0.1)
	end
end

-- Ends voting and returns the winning option (ties broken randomly between tied options).
function VotingService.End(): (VoteOption?, { number }, boolean)
	active = false
	-- Ignore votes from players who left during the vote.
	for player in votes do
		if not player.Parent then
			votes[player] = nil
		end
	end
	local counts = VoteLogic.Tally(votes, #options)
	GameState.SetJSON("VoteCounts", counts)
	if #options == 0 then
		return nil, counts, false
	end
	local winnerIndex, wasTie = VoteLogic.ResolveWinner(counts, function(count)
		return rng:NextInteger(1, count)
	end)
	if wasTie then
		Telemetry.ServerEvent("TieResolved", { winner = options[winnerIndex].Id })
	end
	return options[winnerIndex], counts, wasTie
end

function VotingService.Options(): { VoteOption }
	return options
end

function VotingService.Init()
	local limit = Config.RateLimits.CastVote
	local limiter = RateLimiter.new(limit[1], limit[2])
	Remotes.Get("CastVote").OnServerEvent:Connect(function(player, index)
		if limiter:Check(player) then
			VotingService.Cast(player, index)
		end
	end)
	local function dropVote(player: any)
		if votes[player] then
			votes[player] = nil
			if active then
				publishCounts()
			end
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		dropVote(player)
		votedThisRound[player] = nil
	end)
	-- Sitting out mid-vote takes the vote back. It still counted for their quest and stats, so
	-- coming back and voting again in the same vote doesn't count twice.
	SitOutService.Changed:Connect(function(player, sitOut)
		if sitOut then
			dropVote(player)
			if player.Parent then
				player:SetAttribute("PP_Vote", 0)
			end
		end
	end)
end

return VotingService
