-- Central tuning values. Numbers come from the design outline and are starting points for playtests.
--
-- Bot reports (owner: "Bots are STILL ruberbanding and floating."): RateLimits.ClientReport allows
-- five reports a minute, so each round's bot report (Controllers/BotWatchController) never crowds
-- out a device's mesh and sound reports.

local Config = {}

Config.Version = "0.1.0"

-- §4 Recommended initial server settings
Config.Session = {
	MaxPlayers = 12, -- set the same value in Game Settings > Places
	MinPlayers = 2,
	MinPlayersInStudio = 1, -- lets a single tester run the loop in Studio
	IgnoreModePlayerLimitsInStudio = true,
	-- Between two rounds, ResultsTime + IntermissionTime + VoteTime: 6 + 6 + 8 = 20 seconds at most
	-- (owner: "Less time sitting in the lobby. total of 20 seconds instead of 40.").
	IntermissionTime = 6, -- lobby social time before each vote
	VoteTime = 8, -- at most: once every person playing has voted, it ends VoteLastBeat after the last vote
	VoteLastBeat = 1, -- so the last voter sees their tick before the winner shows (VotingService.Wait)
	VoteChoices = 3, -- games shown in a vote; a 4th card, Random, is always added (owner: "4 options always")
	RulesTime = 10, -- the rules card's time on screen before 3-2-1 (owner: "give players more time to read the instructions")
	CountdownTime = 3,
	ResultsTime = 6, -- the results card, before everyone's back in the lobby
	-- The replay vote on the results card (owner: "Add a vote at the end of each minigame to replay
	-- the same minigame."): over half of the round's people saying PLAY AGAIN plays it again at once.
	-- Everyone having answered (PLAY AGAIN and 👍 / 👎) ends the results early, but never before
	-- ResultsMinTime (the card's placement and rewards need a moment to be seen).
	ResultsMinTime = 3,
	MaxReplays = 2, -- replays in a row at most (3 plays of one game), then a new vote
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
	ReplayVote = { 6, 2 }, -- PLAY AGAIN / NO THANKS on the results card
	RateGame = { 6, 2 }, -- 👍 / 👎 on the results card
	Funnel = { 10, 5 }, -- the screens' funnel steps (shop opened, item picked, GOLD PASS seen)
	Shop = { 6, 2 },
	Emote = { 4, 3 },
	Claim = { 3, 2 },
	Settings = { 10, 5 },
	Tutorial = { 5, 5 },
	ClientReport = { 5, 60 }, -- mesh, sound and (each round) bot reports: Services/ClientReports
	SitOut = { 4, 4 }, -- the sit-out switch: a few quick changes of mind, not a stream
	Crate = { 8, 4 }, -- the crates: open, buy keys, the season's welcome (Services/CrateService)
}

Config.EmoteCooldown = 1.5
Config.ConfettiCannonCooldown = 8

-- Robux products (§10). Leave as 0 until you create them in the Creator Dashboard.
-- The GOLD PASS (owner: "Also we do need a paid battle pass too. I like the current free one. But the
-- paid one should also be insane."): one permanent game pass that opens the Rewards Road's gold lane
-- (Shared/GoldPass, Services/GoldPassService). It took over from the old VIP pass, which was never
-- on sale. The pass is made (399 Robux, set on Roblox); the game asks Roblox for its price and
-- whether it's for sale (GetProductInfo), so changing either on Roblox needs no update. While it's
-- off sale, or with the id 0, nothing can be bought and the gold lane shows as a preview, COMING
-- SOON. (The experience's creator always has it.)
Config.Monetization = {
	GoldPassId = 2048378768,
	GoldPassPrice = 399, -- Robux: shown only if Roblox can't be asked for the price
	-- Lantern Keys for Robux (the crate seasons' design: "we also need to be able to sell keys for
	-- Robux"; Services/KeyShopService): developer products. Price is what's shown only if Roblox can't
	-- be asked (the game asks Roblox for each one's price and whether it's on sale, so changing them on
	-- Roblox needs no update). A pack's Gift is the same pack bought for someone else in the server.
	-- The starter pack is once per player: 5 keys and the season's banner trail, sold only there. Keys
	-- never expire and work in every season. An id of 0 is a pack that isn't made: it isn't shown.
	KeyPacks = {
		{ Key = "Keys1", Keys = 1, Price = 25, Id = 0, GiftId = 0 },
		{ Key = "Keys5", Keys = 5, Price = 99, Id = 0, GiftId = 0, Badge = "POPULAR" },
		{ Key = "Keys15", Keys = 15, Price = 249, Id = 0, GiftId = 0, Badge = "BEST VALUE" },
		{ Key = "Keys40", Keys = 40, Price = 549, Id = 0, GiftId = 0 },
	},
	StarterPack = { Key = "Starter", Keys = 5, Price = 79, Id = 0 },
}

-- The crate seasons' openings (Shared/Seasons, Services/CrateService): how long the show at an
-- altar lasts (the burst, the reel, the reveal; Open 5 a little longer), how close to an altar its
-- opener must be, and how long the HUD waits before saying the crates are ready.
Config.Crates = {
	ShowTime = 5.2,
	ShowTimeMany = 6.6,
	RevealAt = 3.4, -- when the prize shows (the reel ends): banners and the pet wait for it
	RevealAtMany = 4.4,
	AltarRange = 16,
}
-- The gold lane's coins and XP boost (Logic/GoldLane): a level without a gold cosmetic pays Base
-- coins plus PerTen for every ten levels (6 at level 3, 15 at level 99: 733 over the lane's 67 coin
-- levels, half again the free road's 487), and owners get XPBoost more XP from rounds (10%).
Config.GoldRoad = { Base = 6, PerTen = 1, XPBoost = 0.1 }

Config.Debug = {
	LogPhases = true,
	-- Studio-only helpers for building new modes. Ignored in live servers.
	ForceGame = "", -- e.g. "HexMeltdown": every vote offers only this mode
	StudioIntermissionTime = 3, -- shorter lobby wait while testing (live: Session.IntermissionTime)
}

return Config
