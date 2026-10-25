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
-- A new player's first visit, start to finish (owner: "We also need the funnel updated its currently
-- shit. Needs to show first game played, what rank they got on that game, how many others were in the
-- lobby, check if they open crate. Also check for which game they leave during and any more data
-- that might be beneficial to us."):
--   * "FirstVisit", a funnel once per new player: joined, their first round's rules card, its GO, its
--     results, a second round, 3 rounds finished, a crate opened, back another day. Every step says
--     their first game (from its results on), their device and how many other people were on the
--     server when they joined (OthersBucket), so Creator Hub splits the whole funnel by first game.
--   * "FirstGame", an event at their first round's results: the game, where they placed in it
--     (Placed: 1st, 2nd, 3rd, top or bottom half, team won or lost) and the others on the server as
--     it was played; its value is the place.
--   * "LeftDuringGame" (anyone leaving in the middle of a round): the game, what they were doing (the
--     rules card, playing, watching after they were out, the results) and new or returning.
--   * "LastGame" (anyone leaving from the lobby after playing): the last game they played, where they
--     placed and how many rounds they played this visit; its value is the seconds since its results,
--     so a game people quit straight after shows up.
--   * "VisitEnd" (everyone leaving): new or returning, rounds this visit (RoundsBucket) and the
--     crates (CrateLabel: opened one, had one and didn't, or had none); its value is the minutes.
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

-- A new player's first visit (once per player, ever: its run is the UserId). The steps after the
-- first round's results may come in any order; each is logged once (Services/FunnelService keeps
-- which in the profile).
Funnels.FirstVisit = {
	Name = "FirstVisit",
	Steps = {
		"Joined",
		"First round: rules card",
		"First round: GO",
		"First round: results",
		"Second round",
		"Finished 3 rounds",
		"Opened a crate",
		"Came back another day",
	},
}

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
	FirstVisit = { "First game", "Device", "Others on the server" },
	FirstGame = { "Game", "Placed", "Others on the server" },
	LeftDuringGame = { "Game", "Doing", "New or returning" },
	LastGame = { "Game", "Placed", "Rounds this visit" },
	VisitEnd = { "New or returning", "Rounds this visit", "Crates" },
}

-- How many other people (not bots) were on the server.
function Funnels.OthersBucket(others: number): string
	if others <= 0 then
		return "Nobody else"
	elseif others == 1 then
		return "1 other"
	elseif others <= 3 then
		return "2-3 others"
	elseif others <= 7 then
		return "4-7 others"
	end
	return "8+ others"
end

-- Where someone placed in a round: their place in an every-player-for-themselves game of `count`, or
-- whether their team won.
function Funnels.Placed(place: number, count: number, team: boolean, won: boolean): string
	if team then
		return if won then "Team won" else "Team lost"
	elseif place == 1 then
		return "1st"
	elseif place == 2 then
		return "2nd"
	elseif place == 3 then
		return "3rd"
	end
	return if place <= math.ceil(count / 2) then "Top half" else "Bottom half"
end

-- How many rounds a visit finished.
function Funnels.RoundsBucket(rounds: number): string
	if rounds <= 0 then
		return "0 rounds"
	elseif rounds == 1 then
		return "1 round"
	elseif rounds <= 3 then
		return "2-3 rounds"
	elseif rounds <= 9 then
		return "4-9 rounds"
	end
	return "10+ rounds"
end

-- A visit's crates: opened at least one, had one to open and didn't, or had none.
function Funnels.CrateLabel(opened: number, unopened: number): string
	if opened > 0 then
		return "Opened a crate"
	end
	return if unopened > 0 then "Had one, didn't open" else "No crate"
end

-- What someone in a round was doing when they left it.
function Funnels.InGameDoing(phase: string?, alive: boolean): string
	if phase == "Preparing" then
		return "Rules card"
	elseif phase == "Results" then
		return "Results"
	end
	return if alive then "Playing" else "Out, watching"
end

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
