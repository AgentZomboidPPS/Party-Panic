--!strict
-- Long-term progression rules (owner: "Also we need cool payoffs for players that keep playing the
-- game."): the coins every level pays on the Rewards Road, the prestige colors a level shows in the
-- lobby (name tag and level badge), and the lifetime career stats a finished round adds to, which
-- unlock the career titles (Cosmetics with an UnlockStat).
-- Leaf module: no requires, no Roblox APIs. Tuning values are passed in (Config.Road).

local ProgressionLogic = {}

export type RoadCoins = { PerLevel: number, Every5: number, Every10: number }

-- Coins for reaching `level` on the Rewards Road: every level pays, every 5th and 10th pay more.
function ProgressionLogic.LevelCoins(level: number, road: RoadCoins): number
	if level < 2 then
		return 0
	elseif level % 10 == 0 then
		return road.Every10
	elseif level % 5 == 0 then
		return road.Every5
	end
	return road.PerLevel
end

-- Coins for climbing from `fromLevel` to `toLevel`: each level passed pays once.
function ProgressionLogic.CoinsBetween(fromLevel: number, toLevel: number, road: RoadCoins): number
	local total = 0
	for level = math.max(1, math.floor(fromLevel)) + 1, math.floor(toLevel) do
		total += ProgressionLogic.LevelCoins(level, road)
	end
	return total
end

-- Prestige: the name tag and level badge change color every 10 levels, so long-time players stand
-- out in the lobby. Colors are RGB (0-255) so this module stays free of Roblox types.
export type Tier = {
	Level: number, -- the first level with this look
	Name: string,
	Icon: string, -- shown before "Lv" on name tags ("" for the first tier)
	Colors: { { number } }, -- the badge's gradient (more than two colors: a rainbow)
	Text: { number }, -- the level's color on a name tag
}

local TIERS: { Tier } = {
	{ Level = 1, Name = "Sunny", Icon = "", Colors = { { 255, 212, 70 }, { 255, 150, 60 } }, Text = { 255, 255, 255 } },
	{
		Level = 10,
		Name = "Sky",
		Icon = "⭐",
		Colors = { { 120, 225, 255 }, { 40, 120, 235 } },
		Text = { 120, 220, 255 },
	},
	{
		Level = 20,
		Name = "Bubblegum",
		Icon = "🌟",
		Colors = { { 255, 150, 210 }, { 215, 50, 150 } },
		Text = { 255, 150, 210 },
	},
	{
		Level = 30,
		Name = "Royal",
		Icon = "💫",
		Colors = { { 205, 160, 255 }, { 115, 60, 220 } },
		Text = { 205, 165, 255 },
	},
	{
		Level = 40,
		Name = "Gold",
		Icon = "👑",
		Colors = { { 255, 240, 150 }, { 225, 150, 20 } },
		Text = { 255, 215, 80 },
	},
	{
		Level = 50,
		Name = "Rainbow",
		Icon = "💎",
		Colors = { { 255, 90, 90 }, { 255, 200, 60 }, { 90, 230, 110 }, { 80, 170, 255 }, { 190, 110, 255 } },
		Text = { 255, 255, 255 },
	},
}
ProgressionLogic.Tiers = TIERS

function ProgressionLogic.TierIndex(level: number): number
	local index = 1
	for candidate, tier in TIERS do
		if level >= tier.Level then
			index = candidate
		end
	end
	return index
end

-- The next tier above this level's (nil at the top one).
function ProgressionLogic.NextTier(level: number): Tier?
	return TIERS[ProgressionLogic.TierIndex(level) + 1]
end

-- Career: what one finished round adds to the lifetime stats.
export type RoundRecord = {
	GameId: string,
	Category: string,
	Place: number,
	TopHalf: boolean,
	TeamWin: boolean?, -- on the team that won (team and versus games)
	Survived: number?, -- seconds survived (survival games)
	Today: number, -- DailyLogic.DayNumber
}

export type RoundNews = {
	Podium: boolean, -- 1st to 3rd
	NewGame: boolean, -- the first time this player played this game
	NewDay: boolean, -- this player's first round today
}

function ProgressionLogic.RecordRound(stats: { [string]: any }, record: RoundRecord): RoundNews
	local function add(key: string, amount: number?)
		stats[key] = (tonumber(stats[key]) or 0) + (amount or 1)
	end
	local modePlays = if type(stats.ModePlays) == "table" then stats.ModePlays else {}
	stats.ModePlays = modePlays
	local categoryPlays = if type(stats.CategoryPlays) == "table" then stats.CategoryPlays else {}
	stats.CategoryPlays = categoryPlays

	local newGame = (tonumber(modePlays[record.GameId]) or 0) <= 0
	modePlays[record.GameId] = (tonumber(modePlays[record.GameId]) or 0) + 1
	categoryPlays[record.Category] = (tonumber(categoryPlays[record.Category]) or 0) + 1
	add("RoundsPlayed")
	if newGame then
		add("GamesTried")
	end

	local podium = record.Place <= 3
	if record.TopHalf then
		add("TopHalf")
	end
	if podium then
		add("Podiums")
		if record.Category == "Race" then
			add("RacePodiums")
		end
	end
	if record.Place == 1 then
		add("Wins")
		if record.Category == "Survival" then
			add("SurvivalWins")
		end
	end
	if record.TeamWin then
		add("TeamWins")
	end
	if record.Survived and record.Category == "Survival" then
		add("TimeSurvived", math.max(0, math.floor(record.Survived)))
	end

	local newDay = (tonumber(stats.LastPlayDay) or 0) < record.Today
	if newDay then
		stats.LastPlayDay = record.Today
		add("DaysPlayed")
	end
	return { Podium = podium, NewGame = newGame, NewDay = newDay }
end

return ProgressionLogic
