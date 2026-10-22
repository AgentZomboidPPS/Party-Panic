-- Every medal in the game (owner, asked what keeps players coming back: "Medals: a medal for winning
-- each game and a few big ones, Roblox badges, a collect-them-all wall in the lobby", then: "Can you
-- work on all of that? this wont mess with what the other workers are working on right?"): one for
-- winning each game that's on (from GameDefinitions, so a new game gets its medal by itself) and
-- the big ones (Logic/MedalLogic has the list and the rules). Each has an Id, Name, Icon, How (how
-- to earn it), Kind ("Big" or "Game"), BadgeId and Color (its ribbon: a game medal wears its
-- game's colour).
--
-- Roblox badges: a medal becomes a badge once its badge id is in BADGE_IDS below (Creator Hub >
-- Party Panic > Associated Items > Badges > Create). Until then (0) it's a medal in the game only.
-- Players who already have the medal get the badge the next time they join (Services/MedalService).

local GameDefinitions = require(script.Parent.GameDefinitions)
local MedalLogic = require(script.Parent.Logic.MedalLogic)

-- Medal id -> Roblox badge id (0: no badge yet). A game's medal id is "Win" and the game's Id.
local BADGE_IDS: { [string]: number } = {
	FirstWin = 0,
	TenWins = 0,
	FiftyWins = 0,
	EveryGame = 0,
	WonEveryGame = 0,
	CupChampion = 0,
	HallOfFame = 0,
	FriendsParty = 0,
	Halloween2026 = 0,
}

export type Medal = MedalLogic.Medal & { Color: Color3 }

local games: { MedalLogic.GameInfo } = {}
for _, definition in GameDefinitions.List do
	table.insert(
		games,
		{ Id = definition.Id, Name = definition.Name, Icon = definition.Icon, Enabled = definition.Enabled }
	)
end

local catalog = MedalLogic.Build(games, BADGE_IDS)
for _, medal in catalog.List do
	local colored = medal :: Medal
	local definition = medal.GameId and GameDefinitions.Get(medal.GameId)
	local ribbon = medal.Ribbon
	colored.Color = if definition
		then definition.Color
		elseif ribbon then Color3.fromRGB(ribbon[1], ribbon[2], ribbon[3])
		else Color3.fromRGB(255, 204, 64)
end

local Medals = {
	List = catalog.List :: { Medal },
	ById = catalog.ById :: { [string]: Medal },
	Big = catalog.Big :: { Medal },
	Games = catalog.Games :: { Medal },
	Catalog = catalog, -- for MedalLogic's functions
}

function Medals.Get(id: string): Medal?
	return Medals.ById[id]
end

-- The medal for winning this game ("WinFireRope"), if the game has one.
function Medals.ForGame(gameId: string): Medal?
	return Medals.ById[MedalLogic.GameMedalId(gameId)]
end

return Medals
