--!strict
-- The party streak (owner: "Also make the party system insane. I want it to look super epic."): how
-- many rounds in a row a party has played together, the 🔥 on the squad bar and in the PARTY window.
--   * A round counts when every member of the party played it to its results (knocked out early
--     still counts: they played). A round that one of them sat out, or wasn't in, ends the streak.
--   * Rounds that were called off or broke never count either way: the server only hears about
--     rounds that finished (RoundEvents.Finished).
--   * Someone joining or leaving keeps the party's streak; a party that's over takes it with it,
--     and a new party starts at 0.
-- Kept in memory only (Services/PartyService): no coins, nothing saved.
-- Leaf module: no requires, no Roblox APIs, so it can be unit tested under Lune.

local PartyStreak = {}

export type Party = { Id: number, Members: { any } }

-- The look of a streak (the flame's colours on screen): from Warm on, it shows on the squad bar.
PartyStreak.Tiers = {
	{ Name = "Warm", From = 2 },
	{ Name = "Hot", From = 5 },
	{ Name = "Blazing", From = 10 },
}

-- A party's streak after a round: one more when every member played it (a party has two or more),
-- else back to 0. `played` has everyone who played it.
function PartyStreak.Next(streak: number, members: { any }, played: { [any]: boolean }): number
	if #members < 2 then
		return 0
	end
	for _, member in members do
		if not played[member] then
			return 0
		end
	end
	return math.max(0, math.floor(streak)) + 1
end

-- Every party's streak after a round: the parties here now (each once), what they had (`streaks`,
-- by party id) and who played. A party that isn't here any more is left out.
function PartyStreak.Round(
	streaks: { [number]: number },
	parties: { Party },
	played: { [any]: boolean }
): { [number]: number }
	local after = {}
	for _, party in parties do
		after[party.Id] = PartyStreak.Next(streaks[party.Id] or 0, party.Members, played)
	end
	return after
end

-- Which tier a streak is in: 0 below Warm (nothing to show yet), then 1 (Warm), 2 (Hot), 3 (Blazing).
function PartyStreak.Tier(streak: number): number
	local tier = 0
	for index, info in PartyStreak.Tiers do
		if streak >= info.From then
			tier = index
		end
	end
	return tier
end

return PartyStreak
