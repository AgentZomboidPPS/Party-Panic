-- Simulates many votes with the real vote picker (Shared/Logic/GamePicker, the same calls as
-- VotingService.BuildOptions: 3 games plus a RANDOM card drawn from the rest) to see how fair the
-- vote is to every mini-game: how often each one is offered and played, how mixed one vote's
-- categories are, how long until every game has been offered, and what RANDOM turns into.
--
--   lune run tools/checks/vote_sim [votes] [players]      (default 10000 votes at 2, 4, 8, 12)
--
-- Players vote at random among the 4 cards (each card equally likely), and the played game joins
-- the recent list the picker down-weights, like RoundManager does.
local fs = require("@lune/fs")
local process = require("@lune/process")

local GamePicker = require("../../src/shared/Logic/GamePicker")
local Pool = require("./vote_pool")

local votes = tonumber(process.args[1]) or 10000
local counts = if process.args[2] then { tonumber(process.args[2]) :: number } else { 2, 4, 8, 12 }
local config = fs.readFile("src/shared/Config.luau")
local memory = tonumber(string.match(config, "RecentGameMemory = (%d+)")) or 2
local choices = tonumber(string.match(config, "VoteChoices = (%d+)")) or 3

local pool = Pool.Read()
local result = Pool.Simulate(GamePicker, pool, votes, counts, memory, choices, 12345)
Pool.Print(result, pool)
for _, players in counts do
	local median, p90 = Pool.Coverage(GamePicker, pool, players, memory, choices, 2000, 777)
	print(
		string.format(
			"%2d players: a fresh server offers every game by vote %d (median), %d (9 in 10)",
			players,
			median,
			p90
		)
	)
end
