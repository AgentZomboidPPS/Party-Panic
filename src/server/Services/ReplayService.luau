-- The replay vote on the results card (owner: "Add a vote at the end of each minigame to replay the
-- same minigame."). While a round's results show, every person who played it and will play the next
-- round can tap PLAY AGAIN or NO THANKS on their card (Controllers/ResultsController), and everyone
-- sees how many want a replay ("3/5 want a replay"). Bots don't vote, and nor does anyone sitting out
-- the next round (SitOutService), still loading, or who wasn't in the round (they have no results
-- card). More than half saying yes by the end of the results plays the same game again straight
-- away: no lobby time and no game vote (RoundManager). Once everyone who can has answered, and has
-- also given the game a 👍 or 👎 (Services/RatingService; owner: "I clicked and I couldn't vote."),
-- the results end Config.Session.VoteLastBeat after the last answer, like the game vote
-- (Logic/VoteLogic.ClosesAt), though never before ResultsMinTime (the card's placement and rewards
-- need a moment), and the phase timer says so. After Config.Session.MaxReplays replays
-- in a row the vote isn't offered (the card says a new vote is next), so one keen group can't keep a
-- server on one game. The rule itself is Logic/ReplayVote.
--
-- For clients: GameState "ReplayVote" (JSON: Open, Game, Yes, No, Voters as UserIds, Need, Capped)
-- and each voter's own answer, their PP_Replay attribute ("Yes" or "No").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)
local ReplayVote = require(Shared.Logic.ReplayVote)
local VoteLogic = require(Shared.Logic.VoteLogic)

local BotRegistry = require(script.Parent.BotRegistry)
local DataService = require(script.Parent.DataService)
local Notifier = require(script.Parent.Notifier)
local RateLimiter = require(script.Parent.RateLimiter)
local RatingService = require(script.Parent.RatingService)
local SitOutService = require(script.Parent.SitOutService)
local Telemetry = require(script.Parent.Telemetry)

local ReplayService = {}

local ATTRIBUTE = "PP_Replay"

local open = false
local capped = false
local streak = 0 -- replays of this game in a row so far
local gameId = ""
local played: { [any]: boolean } = {} -- the people who played the round
local choices: { [any]: boolean } = {} -- true: PLAY AGAIN, false: NO THANKS
local lastVoteAt = 0
local published = ""

-- Who can vote: the people who played the round and will play the next one (in SitOutService's
-- lineup: here, loaded and not sitting out), in lineup order.
local function voters(): { Player }
	local list = {}
	for _, who in SitOutService.Lineup().Participants do
		if played[who] and not BotRegistry.IsBot(who) then
			table.insert(list, who)
		end
	end
	return list
end

-- Tells every client how the vote stands (only when something changed).
local function publish(list: { Player }?)
	local current = list or voters()
	local tally = ReplayVote.Tally(current, choices)
	local ids = {}
	for _, who in current do
		table.insert(ids, who.UserId)
	end
	local state = {
		Open = open,
		Game = gameId,
		Yes = tally.Yes,
		No = tally.No,
		Voters = ids,
		Need = tally.Need,
		Capped = capped,
	}
	local key = `{open} {capped} {gameId} {tally.Yes} {tally.No} {table.concat(ids, ",")}`
	if key ~= published then
		published = key
		GameState.SetJSON("ReplayVote", state)
	end
end

local function forget(player: any)
	if choices[player] ~= nil then
		choices[player] = nil
		if player.Parent then
			player:SetAttribute(ATTRIBUTE, nil)
		end
	end
end

-- Opens the vote for a round of `id` that `roundPlayers` played (people and bots: bots are left out
-- here), `replays` replays into a run of the same game. Past the cap it isn't open, and the cards say
-- so. With nobody who played (a round that ended in an error), pass an empty list: nothing opens.
function ReplayService.Begin(id: string, roundPlayers: { any }, replays: number)
	for player in choices do
		if player.Parent then
			player:SetAttribute(ATTRIBUTE, nil)
		end
	end
	gameId = id
	streak = replays
	played = {}
	for _, who in roundPlayers do
		if not BotRegistry.IsBot(who) then
			played[who] = true
		end
	end
	choices = {}
	lastVoteAt = 0
	capped = next(played) ~= nil and not ReplayVote.Offered(streak, Config.Session.MaxReplays)
	open = next(played) ~= nil and not capped
	GameState.Set("Replay", "")
	publish()
end

function ReplayService.IsOpen(): boolean
	return open
end

-- PLAY AGAIN (`again` true) or NO THANKS (false) from one player; they can change their mind until
-- the vote closes. Returns whether it counts.
function ReplayService.Cast(player: Player, again: any): boolean
	if not open or type(again) ~= "boolean" or not player.Parent or BotRegistry.IsBot(player) then
		return false
	end
	if not played[player] or SitOutService.IsSittingOut(player) or not DataService.Get(player) then
		return false -- wasn't in the round, is taking a break, or is still loading
	end
	if choices[player] == again then
		return true
	end
	local changed = choices[player] ~= nil
	choices[player] = again
	lastVoteAt = os.clock()
	player:SetAttribute(ATTRIBUTE, if again then "Yes" else "No")
	publish()
	Notifier.Sound({ player }, "VoteClick")
	Telemetry.PlayerEvent(player, if changed then "ReplayVoteChanged" else "ReplayVote", if again then 1 else 0, gameId)
	return true
end

-- Waits out the results: `duration` seconds, or until VoteLastBeat after the last answer once
-- everyone who can vote has answered, but at least `minimum` seconds (someone new to wait for puts
-- the full time back). The phase timer (PhaseEndsAt) follows.
function ReplayService.Wait(duration: number, minimum: number?)
	local start = os.clock()
	local deadline = start + duration
	local earliest = start + math.min(minimum or 0, duration)
	local closesAt = deadline
	while true do
		local now = os.clock()
		local list = voters()
		-- Someone counts as done once they've answered PLAY AGAIN and given the game a 👍 or 👎.
		local done = {}
		for _, who in list do
			if choices[who] ~= nil and RatingService.Rated(who) then
				done[who] = true
			end
		end
		local latest = math.max(lastVoteAt, RatingService.LastVoteAt())
		local due = if open
			then math.max(earliest, VoteLogic.ClosesAt(deadline, list, done, latest, Config.Session.VoteLastBeat))
			else deadline
		if due ~= closesAt then
			closesAt = due
			GameState.Set("PhaseEndsAt", workspace:GetServerTimeNow() + math.max(0, due - now))
		end
		publish(list) -- the voters can change: someone leaves, or goes on a break
		if now >= closesAt then
			return
		end
		task.wait(0.1)
	end
end

-- Closes the vote: whether the same game goes again, and the final count.
function ReplayService.End(): (boolean, ReplayVote.Tally)
	local list = voters()
	local tally = ReplayVote.Tally(list, choices)
	local again = open and ReplayVote.Passes(tally, streak, Config.Session.MaxReplays)
	open = false
	publish(list)
	if again then
		Telemetry.ServerEvent("ReplayVoted", { game = gameId, yes = tally.Yes, voters = tally.Voters })
	end
	return again, tally
end

function ReplayService.Init()
	local limit = Config.RateLimits.ReplayVote
	local limiter = RateLimiter.new(limit[1], limit[2])
	Remotes.Get("ReplayVote").OnServerEvent:Connect(function(player, again)
		if limiter:Check(player) then
			ReplayService.Cast(player, again)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		forget(player)
		played[player] = nil
		if open then
			publish()
		end
	end)
	-- Going on a break takes the answer back: only the people who'll play the next round decide it.
	SitOutService.Changed:Connect(function(player, sitOut)
		if sitOut then
			forget(player)
		end
		if open then
			publish()
		end
	end)
end

return ReplayService
