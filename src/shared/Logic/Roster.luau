--!strict
-- Who plays the next round (design doc §3 "Round lifecycle states"): the people here who aren't
-- sitting out (owner: "we do need to add somewhere super apparent a toggle where you skip next
-- round"), then the bots filling in. Bots never play without at least one person, so when
-- everyone here is taking a break, rounds wait in the lobby instead of running with bots only.
-- People sitting out don't count towards MinPlayers either.
-- Leaf module: no requires, no Roblox APIs, so it can be unit tested under Lune.

local Roster = {}

export type Candidate = {
	IsBot: boolean,
	Ready: boolean, -- a person: profile loaded and still here; a bot: in the world (has a character)
	SittingOut: boolean, -- a person sitting out the next rounds (PP_SitOut); never a bot
}

export type Lineup<T> = {
	Participants: { T }, -- who'd play the next round: the people playing, then the bots
	Here: number, -- people who are ready, playing or not
	Playing: number, -- people who'd play
	SittingOut: number, -- people who are ready but sitting out
}

-- `everyone` lists people and bots (in the order they should play in); `describe` says what each is.
function Roster.Build<T>(everyone: { T }, describe: (T) -> Candidate): Lineup<T>
	local people: { T } = {}
	local bots: { T } = {}
	local here, sittingOut = 0, 0
	for _, who in everyone do
		local info = describe(who)
		if info.IsBot then
			if info.Ready then
				table.insert(bots, who)
			end
		elseif info.Ready then
			here += 1
			if info.SittingOut then
				sittingOut += 1
			else
				table.insert(people, who)
			end
		end
	end
	local participants = table.clone(people)
	if #people > 0 then
		for _, bot in bots do
			table.insert(participants, bot)
		end
	end
	return { Participants = participants, Here = here, Playing = #people, SittingOut = sittingOut }
end

-- Why the next round can't start yet: "" when it can, "Break" when everyone here is sitting out,
-- "TooFew" when it needs more players (and how many more).
function Roster.Blocker<T>(lineup: Lineup<T>, minPlayers: number): (string, number)
	if lineup.Playing == 0 and lineup.Here > 0 then
		return "Break", 0
	end
	local needed = minPlayers - #lineup.Participants
	if lineup.Playing == 0 or needed > 0 then
		return "TooFew", math.max(1, needed)
	end
	return "", 0
end

-- The lobby banner's line while the next round can't start.
function Roster.WaitingMessage(reason: string, needed: number): string
	if reason == "Break" then
		return "Everyone's taking a break!"
	end
	return if needed == 1 then "Waiting for 1 more player..." else `Waiting for {needed} more players...`
end

return Roster
