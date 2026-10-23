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
-- What tells fun and staying apart (owner: "What information should we collect to gage if players
-- are having fun and staying?", then "lets do 1-7."): every step and event carries custom fields
-- (Creator Hub splits a chart by them):
--   * the device: Phone, Tablet, PC or Console (the screen says which: DeviceKinds);
--   * friends: Party (in a party with someone in the round), Friends (a Roblox friend in it) or Solo;
--   * how many people (not bots) were in the round (PeopleBucket);
--   * the win or loss streak someone left on (StreakLabel);
-- and a custom event "FirstRoundWait": how many seconds a visit waited from joining to its first GO.
-- Coins earned and spent go to Roblox's economy report and levels to its progression report
-- (Services/Telemetry, Services/Economy). Which field is which, per funnel, is FIELDS below.
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

-- Crate seasons ("Crates"; Services/CrateService): once per player, ever (its run is the UserId):
-- their first crate, their first open, 10 and 50 opened, then their first keys bought with Robux.
Funnels.Crates = {
	Name = "Crates",
	Steps = { "First crate", "First open", "Opened 10", "Opened 50", "Bought keys" },
}
-- The Crates step that opening the `opened`th crate reaches (nil: not a step).
function Funnels.CrateStep(opened: number): number?
	return if opened == 1 then 2 elseif opened == 10 then 3 elseif opened == 50 then 4 else nil
end

-- The step of the round ladders (Onboarding, Session) that finishing `rounds` rounds reaches: step 3
-- for the first, then one for each of RoundMarks. Nil when `rounds` isn't one of the marks.
function Funnels.FinishedStep(rounds: number): number?
	local index = table.find(Funnels.RoundMarks, rounds)
	return if index then 2 + index else nil
end

-- What the steps of the client's screens are called on the remote (Services/FunnelService takes no
-- other word from a device), and the devices it can say it is.
Funnels.ClientSteps = { ShopOpen = true, ShopPick = true, GoldSeen = true, Device = true }
Funnels.DeviceKinds = { Phone = true, Tablet = true, PC = true, Console = true }

-- The custom fields, in order (the first is CustomField01), per funnel and event.
Funnels.FIELDS = {
	Onboarding = { "Device", "Friends" },
	Session = { "New or returning", "Device", "Friends" },
	Round = { "Game", "Friends", "People" },
	Shop = { "Item or tab", "Device" },
	GoldPass = { "", "Device" },
	Crates = { "Season" },
	LeftDuring = { "Where", "Device", "Streak" },
	FirstRoundWait = { "New or returning", "Device", "People" },
}

-- How many people (not bots) were in a round.
function Funnels.PeopleBucket(people: number): string
	if people <= 1 then
		return "1 person"
	elseif people == 2 then
		return "2 people"
	elseif people <= 5 then
		return "3-5 people"
	end
	return "6+ people"
end

-- Who someone played with: in a party with someone there, a Roblox friend there, or neither.
function Funnels.Social(party: boolean, friend: boolean): string
	return if party then "Party" elseif friend then "Friends" else "Solo"
end

-- The better of two Social labels (a visit's "with friends so far").
function Funnels.BestSocial(a: string?, b: string?): string
	local rank = { Solo = 1, Friends = 2, Party = 3 }
	local x, y = a or "Solo", b or "Solo"
	return if (rank[y] or 0) > (rank[x] or 0) then y else x
end

-- The streak someone is on after `rounds` rounds this visit, `lost` of the latest in a row lost.
function Funnels.StreakLabel(rounds: number, lost: number): string
	if rounds <= 0 then
		return "No rounds yet"
	elseif lost <= 0 then
		return "Won the last round"
	elseif lost <= 2 then
		return `Lost the last {lost}`
	elseif lost <= 4 then
		return "Lost the last 3-4"
	end
	return "Lost the last 5+"
end

-- Roblox's economy report sorts coins by kind of transaction (Enum.AnalyticsEconomyTransactionType
-- names): where each of the game's reasons for coins goes.
Funnels.CoinKinds = {
	Round = "Gameplay",
	PartyCup = "Gameplay",
	Quest = "Gameplay",
	SecretToken = "Gameplay",
	Road = "Gameplay",
	Daily = "TimedReward",
	GoldPass = "IAP",
	Shop = "Shop",
	Crate = "Gameplay", -- coins out of a season crate (Services/CrateService)
}

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
