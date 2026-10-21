--!strict
-- The shape of a saved player profile and every field's default (design doc §14). DataService
-- gives new players a copy, and fills in any field a saved profile doesn't have yet; it lives here
-- (no Roblox APIs) so the Lune tests load saved profiles exactly the way the server does.
-- Version 2 is the low coin scale and the career stats (owner: "Also lets balance the shop down. I
-- want low currency not high." and "Also we need cool payoffs for players that keep playing the
-- game."); Logic/ProfileMigration moves older saves over, once.
-- Leaf module: no requires, no Roblox APIs.

return {
	Version = 2, -- ProfileMigration.SchemaVersion: the newest code that saved this profile
	EconomyVersion = 2, -- ProfileMigration.EconomyVersion: the coins are on the low scale
	Coins = 0,
	XP = 0,
	Owned = {} :: { [string]: boolean },
	Equipped = {
		Trail = "",
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
	Tutorial = { Done = false },
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
