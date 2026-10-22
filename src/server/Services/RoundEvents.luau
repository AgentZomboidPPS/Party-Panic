-- What the round loop tells the rest of the server, so the features that hang off rounds (owner,
-- asked what keeps players coming back: "Can you work on all of that?": Party Cups, the weekly
-- leaderboard, medals, friends, events) listen here instead of each adding code to RoundManager.
--
--   Finished(definition, placed, winningTeam): a round ended normally and its rewards were paid.
--     `definition` is the mode's GameDefinitions entry. `placed` is Logic/Placement's Assign output
--     over the round's result entries, best first: each item has Place and Entry (Entry.Player is
--     the player or bot, plus the mode's ScoreText, Team, Survived...). Rounds that were called off
--     or broke never fire it. Listeners run in their own threads, so one that errors or waits
--     can't hold up the round loop.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)

local RoundEvents = {
	Finished = Signal.new(),
}

return RoundEvents
