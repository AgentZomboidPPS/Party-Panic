--!strict
-- The funnels the game logs to Roblox's analytics (owner: "Can you make me some sick ass funnels to
-- track where players leave/complete stuff"). Creator Hub > Analytics > Funnels draws each one as a
-- chart of how many players reached each step, so the drop between two steps is where people leave.
-- Services/FunnelService logs them; this module only names them and says which step a count reaches.
--
--   New players (Roblox's onboarding funnel, once per player, only for someone whose first visit is
--   after this shipped): joined, played a round, finished it, then 3, 5, 10 and 20 rounds finished.
--   Every visit ("Session"): the same ladder for one visit, from joining.
--   Every round ("Round"): in the round, GO, saw the results, stayed for the next round. Its custom
--   field is the game, so Creator Hub can split it by game.
--   Shop ("Shop"): opened the shop, picked an item (the Buy box), bought it.
--   GOLD PASS ("GoldPass"): saw the offer, pressed GET GOLD PASS, bought it.
-- And where players leave: a custom event "LeftDuring" when someone leaves, its field saying what
-- they were doing (LeftWhere) and its value how many minutes they'd played.
--
-- Roblox keys a funnel's steps by number: a step's name must never change once it has been logged,
-- and new steps go on the end. Leaf module: no requires, no Roblox APIs.

local Funnels = {}

-- Rounds finished that are steps of their own, in both round ladders.
Funnels.RoundMarks = { 1, 3, 5, 10, 20 }

Funnels.Onboarding = {
	"Joined",
	"Played a round",
	"Finished a round",
	"Finished 3 rounds",
	"Finished 5 rounds",
	"Finished 10 rounds",
	"Finished 20 rounds",
}

Funnels.Session = {
	Name = "Session",
	Steps = {
		"Joined",
		"Played a round",
		"Finished a round",
		"Finished 3 rounds",
		"Finished 5 rounds",
		"Finished 10 rounds",
		"Finished 20 rounds",
	},
}

Funnels.Round = {
	Name = "Round",
	Steps = { "In the round", "GO", "Saw the results", "Stayed for the next round" },
}

Funnels.Shop = {
	Name = "Shop",
	Steps = { "Opened the shop", "Picked an item", "Bought it" },
}

Funnels.GoldPass = {
	Name = "GoldPass",
	Steps = { "Saw the offer", "Pressed GET GOLD PASS", "Bought it" },
}

-- The step of the round ladders (Onboarding, Session) that finishing `rounds` rounds reaches: step 3
-- for the first, then one for each of RoundMarks. Nil when `rounds` isn't one of the marks.
function Funnels.FinishedStep(rounds: number): number?
	local index = table.find(Funnels.RoundMarks, rounds)
	return if index then 2 + index else nil
end

-- What the steps of the client's screens are called on the remote (Services/FunnelService takes no
-- other word from a device).
Funnels.ClientSteps = { ShopOpen = true, ShopPick = true, GoldSeen = true }

-- What someone was doing when they left, for the "LeftDuring" event: the round's phase if they were
-- in it, else where the server was (the lobby, the vote...).
function Funnels.LeftWhere(phase: string?, inRound: boolean, sittingOut: boolean): string
	if inRound then
		if phase == "Preparing" then
			return "Round: rules card"
		elseif phase == "InRound" then
			return "Round: playing"
		elseif phase == "Results" then
			return "Round: results"
		end
		return "Round"
	end
	if sittingOut then
		return "Sitting out"
	end
	if phase == "Waiting" then
		return "Lobby: waiting for players"
	elseif phase == "Voting" then
		return "Lobby: vote"
	elseif phase == "Preparing" or phase == "InRound" or phase == "Results" then
		return "Lobby: a round on without them"
	end
	return "Lobby"
end

return Funnels
