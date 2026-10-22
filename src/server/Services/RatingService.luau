-- 👍 / 👎 on each mini-game's results card (owner: "lets add to the backburner a away for players to
-- downvote a minigame and then we can harvest that data to disable minigames in the future." Then:
-- "Also while you make the downvote for mini games can you also do an upvote one so we can see if
-- players like it"). While a round's results show, each person who played it can say 👍 ("Loved it")
-- or 👎 ("Not for me"), one vote per round: the other button switches it, the lit one again takes it
-- back, until the results end. Never from bots, or from anyone who wasn't in the round (they have no
-- results card). The rules are Shared/Logic/GameRatings; the buttons Controllers/ResultsController.
--
-- The totals: one key per game and ISO week ("2026-W43/PumpAndPop") in the PP_GameRatings data store
-- of its own (never the profile store, and never a key per player): rounds, people who played, 👍,
-- 👎 and a bit map of who voted (for the unique voters, without keeping anyone's UserId), plus the
-- PLAY AGAIN answers (Services/ReplayService) and how often the game was on the game vote and won it
-- (Services/VotingService, through RoundManager). A round writes once per game it touched, with
-- UpdateAsync increments, when its results end; a write that fails waits for the next round (and the
-- server's close). tools/checks/game_ratings.py reads the last four weeks.
--
-- Test runs (workspace PP_Harness) write to PP_GameRatings_Test instead, so the checks can see their
-- totals land without touching the real ones (game_ratings.py --test reads it); Studio keeps nothing.
--
-- For clients: GameState "Rating" (JSON: Open, Game) and each voter's own vote, their PP_Rating
-- attribute ("Up" or "Down").

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local GameRatings = require(Shared.Logic.GameRatings)
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)

local BotRegistry = require(script.Parent.BotRegistry)
local Notifier = require(script.Parent.Notifier)
local RateLimiter = require(script.Parent.RateLimiter)
local Telemetry = require(script.Parent.Telemetry)

local RatingService = {}

local STORE = "PP_GameRatings"
local TEST_STORE = "PP_GameRatings_Test"
local ATTRIBUTE = "PP_Rating"

local ballot: GameRatings.Ballot? = nil
local open = false
local lastVoteAt = 0 -- os.clock() of the latest 👍 / 👎 (or take-back)
-- What each key still has to add, oldest first: a round's batch, and any that failed before it.
local pending: { [string]: { GameRatings.Additions } } = {}
local writes: { { Key: string, Record: GameRatings.Record?, Error: string? } } = {} -- (test runs: what was written)

local function harness(): boolean
	return workspace:GetAttribute("PP_Harness") == true
end

local function store(): DataStore?
	if RunService:IsStudio() and not harness() then
		return nil
	end
	return DataStoreService:GetDataStore(if harness() then TEST_STORE else STORE)
end

local function key(gameId: string): string
	return `{GameRatings.Week(os.time())}/{gameId}`
end

local function queue(gameId: string, add: GameRatings.Additions)
	local name = key(gameId)
	pending[name] = pending[name] or {}
	table.insert(pending[name], add)
end

local function publish()
	GameState.SetJSON("Rating", { Open = open, Game = if ballot then ballot.Game else "" })
end

local function clearVotes()
	if not ballot then
		return
	end
	for player in ballot.Votes do
		if player.Parent then
			player:SetAttribute(ATTRIBUTE, nil)
		end
	end
end

-- Writes everything pending, one UpdateAsync per key. `wait` waits for the writes (the server
-- closing); otherwise each runs in its own thread.
local function flush(wait: boolean?)
	local target = store()
	local batches = pending
	pending = {}
	if not target then
		return -- Studio: nothing is kept
	end
	local running = 0
	for name, adds in batches do
		running += 1
		task.spawn(function()
			local written: GameRatings.Record? = nil
			local ok, err = pcall(function()
				target:UpdateAsync(name, function(old)
					local record = GameRatings.Clean(old)
					for _, add in adds do
						record = GameRatings.Add(record, add)
					end
					written = record
					return record
				end)
			end)
			if not ok then
				-- Try again with the next round's batch (oldest first).
				local later = pending[name] or {}
				pending[name] = table.move(later, 1, #later, #adds + 1, table.clone(adds))
				Telemetry.Error("GameRatings", tostring(err))
			end
			if harness() then
				table.insert(
					writes,
					{ Key = name, Record = if ok then written else nil, Error = if ok then nil else tostring(err) }
				)
			end
			running -= 1
		end)
	end
	if wait then
		local deadline = os.clock() + 20
		while running > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end
end

-- Opens the vote for a round of `gameId` that `roundPlayers` played (people and bots: bots can't
-- vote). With nobody who played (a round that ended in an error), pass an empty list: nothing opens.
function RatingService.Begin(gameId: string, roundPlayers: { any })
	clearVotes()
	local members = {}
	for _, who in roundPlayers do
		table.insert(members, { Key = who, Id = who.UserId, Bot = BotRegistry.IsBot(who) })
	end
	ballot = GameRatings.NewBallot(gameId, members)
	open = (ballot :: GameRatings.Ballot).Plays > 0
	publish()
end

-- 👍 ("Up"), 👎 ("Down") or taking it back ("None") from one player. Returns whether it counts.
function RatingService.Cast(player: Player, choice: any): boolean
	local current = ballot
	if not open or not current or not player.Parent or BotRegistry.IsBot(player) then
		return false
	end
	local before = GameRatings.Current(current, player)
	if not GameRatings.Vote(current, player, choice) then
		return false -- wasn't in the round, or not a choice
	end
	if before ~= choice then
		lastVoteAt = os.clock()
		player:SetAttribute(ATTRIBUTE, if choice == "None" then nil else choice)
		Notifier.Sound({ player }, "VoteClick")
		Telemetry.PlayerEvent(
			player,
			"GameRated",
			if choice == "Up" then 1 elseif choice == "Down" then -1 else 0,
			current.Game
		)
	end
	return true
end

-- Whether `player` has a 👍 or 👎 in now. ReplayService ends the results early only once everyone
-- has answered PLAY AGAIN and this (owner: "I clicked and I couldn't vote.").
function RatingService.Rated(player: any): boolean
	return open and ballot ~= nil and GameRatings.Current(ballot, player) ~= "None"
end

-- When the latest 👍 / 👎 came in (os.clock()), for the moment after it the results wait.
function RatingService.LastVoteAt(): number
	return lastVoteAt
end

-- Closes the vote and writes the round: its votes and people, and (when PLAY AGAIN was offered) its
-- answers.
function RatingService.End(replay: { Yes: number, No: number }?)
	local current = ballot
	open = false
	publish()
	clearVotes()
	if current and current.Plays > 0 then
		local tally = GameRatings.Tally(current)
		queue(current.Game, {
			Tally = tally,
			ReplayYes = if replay then replay.Yes else 0,
			ReplayNo = if replay then replay.No else 0,
		})
	end
	ballot = nil
	flush()
end

-- The game vote's cards, winner and votes per card (VotingService): a game shown by name was offered,
-- and won if it was picked. The Random card's game doesn't count (nobody saw what it was), nor does
-- a vote nobody voted in (its winner was drawn at random). Written with the next round.
function RatingService.NoteVote(
	options: { { Id: string, Mystery: boolean } },
	winner: { Id: string, Mystery: boolean }?,
	counts: { number }
)
	local cast = 0
	for _, count in counts do
		cast += count
	end
	if cast == 0 then
		return
	end
	for _, option in options do
		if not option.Mystery then
			local won = winner ~= nil and not winner.Mystery and winner.Id == option.Id
			queue(option.Id, { VoteOffers = 1, VoteWins = if won then 1 else 0 })
		end
	end
end

-- Test runs only: what has been written so far (each key's record after the write, or its error).
function RatingService.Writes(): { { Key: string, Record: GameRatings.Record?, Error: string? } }
	return writes
end

function RatingService.Init()
	local limit = Config.RateLimits.RateGame
	local limiter = RateLimiter.new(limit[1], limit[2])
	Remotes.Get("RateGame").OnServerEvent:Connect(function(player, choice)
		if limiter:Check(player) then
			RatingService.Cast(player, choice)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		-- A vote stays counted when its voter leaves: they played the round and said what they thought.
		player:SetAttribute(ATTRIBUTE, nil)
	end)
	pcall(function()
		game:BindToClose(function()
			flush(true) -- the last round's batch, or one that failed
		end)
	end)
	publish()
end

return RatingService
