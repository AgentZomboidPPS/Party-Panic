-- Central tuning values. Numbers come from the design outline and are starting points for playtests.

local Config = {}

Config.Version = "0.1.0"

-- §4 Recommended initial server settings
Config.Session = {
	MaxPlayers = 12, -- set the same value in Game Settings > Places
	MinPlayers = 2,
	MinPlayersInStudio = 1, -- lets a single tester run the loop in Studio
	IgnoreModePlayerLimitsInStudio = true,
	IntermissionTime = 20, -- lobby social time before each vote
	VoteTime = 12,
	VoteChoices = 3, -- games shown in a vote; a 4th card, Random, is always added (owner: "4 options always")
	RulesTime = 6,
	CountdownTime = 3,
	ResultsTime = 8,
	RoundGraceTime = 10, -- watchdog: hard stop this long after a mode's own time limit
	RecentGameMemory = 2,
}

-- Bots: friendly AI players that fill empty spots so every round feels full. They fade in when
-- someone leaves and fade out when someone joins (after their round if they're playing one).
Config.Bots = {
	Enabled = true,
	FillTo = 8, -- keep this many participants (players + bots) while at least one player is here
	MaxBots = 11,
	InStudio = true,
	ArriveEvery = 1.2, -- seconds between bots fading in
}

-- Arenas are built far away from the lobby so they never overlap it.
Config.ArenaOrigin = Vector3.new(0, 250, 1400)
Config.LobbySpawnHeight = 4

-- §9 reward model on the low coin scale (owner: "Also lets balance the shop down. I want low
-- currency not high."): a round pays 2 coins for playing, up to 6 for a win with a personal best,
-- and shop items cost tens of coins, so an item takes about as many rounds as before. Coins used
-- to be 10 times bigger; Logic/ProfileMigration moves saved balances over once. XP is unchanged.
Config.Rewards = {
	Participation = { Coins = 2, XP = 25 },
	TopHalf = { Coins = 1, XP = 10 },
	Winner = { Coins = 2, XP = 20 },
	PersonalBest = { Coins = 1, XP = 5 },
	FirstWin = { Coins = 5, XP = 50 }, -- the first win of each day (UTC), on top of the rest
}
-- The Rewards Road (owner: "Also we need cool payoffs for players that keep playing the game."):
-- every level pays coins, every 5th and 10th level more. Its exclusive cosmetics are the Cosmetics
-- with an UnlockLevel; Logic/ProgressionLogic has the prestige colors every 10 levels.
Config.Road = { PerLevel = 3, Every5 = 10, Every10 = 15 }
Config.DailyRewards = { 5, 6, 7, 8, 9, 10, 15 } -- by streak day
Config.SecretTokenCoins = 3
Config.Quests = {
	DailyCount = 3,
	WeeklyCount = 2,
}

-- §14 Profile / data layer
Config.Data = {
	StoreName = "PartyPanic_Profiles_v1",
	KeyPrefix = "Player_",
	AutosaveInterval = 120,
	SessionLockTimeout = 600, -- a lock older than this is treated as abandoned
	LoadRetries = 4,
}

-- §15 Remote rate limits: calls allowed per window (seconds)
Config.RateLimits = {
	CastVote = { 8, 2 },
	Shop = { 6, 2 },
	Emote = { 4, 3 },
	Claim = { 3, 2 },
	Settings = { 10, 5 },
	Tutorial = { 5, 5 },
	ClientReport = { 3, 60 },
}

Config.EmoteCooldown = 1.5
Config.ConfettiCannonCooldown = 8

-- Optional Robux products (§10). Leave as 0 until you create them in the Creator Dashboard.
Config.Monetization = {
	VipGamePassId = 0,
}

Config.Debug = {
	LogPhases = true,
	-- Studio-only helpers for building new modes. Ignored in live servers.
	ForceGame = "", -- e.g. "HexMeltdown": every vote offers only this mode
	StudioIntermissionTime = 8, -- shorter lobby wait while testing
}

return Config
