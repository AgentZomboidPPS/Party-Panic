--!strict
-- The shape of a saved player profile and every field's default (design doc §14). DataService
-- gives new players a copy, and fills in any field a saved profile doesn't have yet; it lives here
-- (no Roblox APIs) so the Lune tests load saved profiles exactly the way the server does.
-- Version 2 is the low coin scale and the career stats (owner: "Also lets balance the shop down. I
-- want low currency not high." and "Also we need cool payoffs for players that keep playing the
-- game."); Logic/ProfileMigration moves older saves over, once. The GOLD PASS's field (GoldPass)
-- came later: older saves get its default (not owned), and loading makes it safe (ProfileMigration).
-- Leaf module: no requires, no Roblox APIs.

return {
	Version = 2, -- ProfileMigration.SchemaVersion: the newest code that saved this profile
	EconomyVersion = 2, -- ProfileMigration.EconomyVersion: the coins are on the low scale
	Coins = 0,
	XP = 0,
	Owned = {} :: { [string]: boolean },
	Equipped = {
		Trail = "",
		Hat = "", -- the Hat slot (World/Hats), worn in the lobby
		Title = "Title_Rookie",
		Victory = "Victory_Confetti",
		Elimination = "Elim_Poof",
	},
	Stats = {
		RoundsPlayed = 0,
		Wins = 0,
		TopHalf = 0,
		Votes = 0,
		ItemsCollected = 0,
		TimeSurvived = 0,
		SurvivalWins = 0,
		TreasureDelivered = 0,
		RaceFinishes = 0,
		Knockouts = 0,
		-- Career milestones (Logic/ProgressionLogic.RecordRound keeps these)
		Podiums = 0, -- 1st to 3rd
		TeamWins = 0, -- on the winning team
		RacePodiums = 0, -- 1st to 3rd in race games
		GamesTried = 0, -- different games played (worked out from ModePlays on every load)
		DaysPlayed = 0, -- different days (UTC) with a round played
		LastPlayDay = 0,
		ModePlays = {} :: { [string]: number },
		CategoryPlays = {} :: { [string]: number },
		Best = {} :: { [string]: number },
	},
	Daily = {
		LastClaimDay = 0,
		Streak = 0,
		SecretDay = 0,
		FirstWinDay = 0, -- the day the first-win-of-the-day bonus was last paid
	},
	Quests = {
		Daily = { Number = 0, Active = {} },
		Weekly = { Number = 0, Active = {} },
	},
	-- The owner's "keep players coming back" features (owner: "Can you work on all of that?").
	Cups = { Played = 0, Wins = 0, Podiums = 0 }, -- Party Cups finished, won, on the podium (CupService)
	Medals = {} :: { [string]: number }, -- medal id -> the UTC day it was earned (MedalService)
	Weekly = { Week = 0, Points = 0 }, -- the weekly leaderboard: which week, and its points (LeaderboardService)
	Events = {} :: { [string]: { [string]: any } }, -- per limited-time event id, its progress (EventService)
	-- The GOLD PASS (owner: "the paid one should also be insane"; Services/GoldPassService): whether
	-- they own the game pass (kept, so a failed ownership check never takes it away), when they got it,
	-- and the last level whose gold coins were paid (Logic/GoldLane: each level pays once).
	GoldPass = { Owned = false, Since = 0, CoinsTo = 1 },
	Tutorial = { Done = false },
	-- The new-player funnel (Services/FunnelService): the last step logged for this player, -1 for
	-- someone who had played before it shipped (never logged), 0 before their first load decides.
	Funnel = { Onboarding = 0 },
	Settings = {
		ReducedEffects = false,
		MusicVolume = 0.5, -- 0 = off; the client also starts quiet and fades in
	},
	Meta = {
		FirstJoin = 0,
		LastJoin = 0,
		Sessions = 0,
		-- What a load did to the coins, until the player was told (Logic/ProfileMigration). Never a
		-- default: only a load that changed the coins sets it, and DataService clears it once said.
		CoinNotice = nil :: { Kind: string, Before: number?, After: number }?,
	},
}
