--!strict
-- The rules of the medals (owner, asked what keeps players coming back: "Medals: a medal for winning
-- each game and a few big ones, Roblox badges, a collect-them-all wall in the lobby", then: "Can you
-- work on all of that? this wont mess with what the other workers are working on right?"):
--   * the list: one medal for winning each game (built from the game list, so a game added later
--     gets its own medal), and the big ones: four other features give (a PARTY CUP won, a week in
--     the top three, the Halloween 2026 party, a round with a friend) and five that come from
--     playing (a first win, 10 and 50 wins, every game played, every game won: the collect-them-all
--     goal);
--   * who won a round, the way the round's rewards count it;
--   * which medals a player's career stats have already earned (players who won before medals
--     existed get those when they next join);
--   * where each medal goes on the lobby's medal wall, however many games there are.
-- Shared/Medals builds the game's list from GameDefinitions; Services/MedalService gives the medals,
-- World/MedalWall builds the wall and Controllers/MedalController shows them.
-- Leaf module: no requires, no Roblox APIs.

local MedalLogic = {}

export type Medal = {
	Id: string,
	Name: string, -- the medal's name: "FIRE ROPE Winner", "First Win"
	Short: string, -- on a tile in the medal screen: "FIRE ROPE", "First Win"
	Icon: string, -- emoji (Unicode 12 or older: newer ones show blank on phones)
	How: string, -- how to earn it, one short line
	Kind: string, -- "Big" (the few big ones) or "Game" (won that game)
	GameId: string?, -- a game medal's game
	Ribbon: { number }?, -- a big medal's ribbon colour (RGB 0-255); a game medal's is its game's colour
	BadgeId: number, -- its Roblox badge (0 until the owner makes one)
	Order: number, -- its place in the list (the wall and the screen go in this order)
}

export type Catalog = {
	List: { Medal },
	ById: { [string]: Medal },
	Big: { Medal },
	Games: { Medal },
}

-- What the list needs to know about a game (a GameDefinitions entry has all of it).
export type GameInfo = { Id: string, Name: string, Icon: string, Enabled: boolean? }

-- The career's win counts that earn a medal.
MedalLogic.WinSteps = { FirstWin = 1, TenWins = 10, FiftyWins = 50 }

-- The big medals, in the order the wall and the screen show them. The last four are given by the
-- other features (MedalService.Award with these ids); the first five come from playing.
local BIG: { { Id: string, Name: string, Icon: string, How: string, Ribbon: { number } } } = {
	{ Id = "FirstWin", Name = "First Win", Icon = "🥇", How = "Win any round", Ribbon = { 255, 84, 150 } },
	{ Id = "TenWins", Name = "10 Wins", Icon = "🌟", How = "Win 10 rounds", Ribbon = { 64, 196, 255 } },
	{ Id = "FiftyWins", Name = "50 Wins", Icon = "👑", How = "Win 50 rounds", Ribbon = { 156, 108, 255 } },
	{
		Id = "EveryGame",
		Name = "Tried Them All",
		Icon = "🧭",
		How = "Play every game once",
		Ribbon = { 110, 226, 140 },
	},
	{
		Id = "WonEveryGame",
		Name = "Medal Master",
		Icon = "💎",
		How = "Win every game once",
		Ribbon = { 80, 230, 230 },
	},
	{
		Id = "CupChampion",
		Name = "PARTY CUP Champion",
		Icon = "🏆",
		How = "Win a PARTY CUP",
		Ribbon = { 255, 204, 64 },
	},
	{
		Id = "HallOfFame",
		Name = "Hall of Fame",
		Icon = "🏛️",
		How = "Finish a week in the top 3",
		Ribbon = { 120, 84, 230 },
	},
	{
		Id = "FriendsParty",
		Name = "Party Pals",
		Icon = "🙌",
		How = "Play a round with a friend",
		Ribbon = { 255, 120, 175 },
	},
	{
		Id = "Halloween2026",
		Name = "Halloween 2026",
		Icon = "🎃",
		How = "Join the HALLOWEEN 2026 party",
		Ribbon = { 255, 140, 40 },
	},
}

-- The id of the medal for winning a game ("WinFireRope").
function MedalLogic.GameMedalId(gameId: string): string
	return "Win" .. gameId
end

-- Every medal: the big ones, then one for each game that's on (in the game list's order).
-- `badgeIds` gives medals their Roblox badges (medal id -> badge id; missing means none yet).
function MedalLogic.Build(games: { GameInfo }, badgeIds: { [string]: number }?): Catalog
	local badges = badgeIds or {}
	local catalog: Catalog = { List = {}, ById = {}, Big = {}, Games = {} }
	local function add(medal: Medal)
		if catalog.ById[medal.Id] then
			return -- (a game whose id made a big medal's id: the big one stays)
		end
		medal.Order = #catalog.List + 1
		table.insert(catalog.List, medal)
		table.insert(if medal.Kind == "Game" then catalog.Games else catalog.Big, medal)
		catalog.ById[medal.Id] = medal
	end
	for _, spec in BIG do
		add({
			Id = spec.Id,
			Name = spec.Name,
			Short = spec.Name,
			Icon = spec.Icon,
			How = spec.How,
			Kind = "Big",
			Ribbon = spec.Ribbon,
			BadgeId = tonumber(badges[spec.Id]) or 0,
			Order = 0,
		})
	end
	for _, game in games do
		if game.Enabled == false then
			continue
		end
		local id = MedalLogic.GameMedalId(game.Id)
		local name = string.upper(game.Name)
		add({
			Id = id,
			Name = `{name} Winner`,
			Short = name,
			Icon = game.Icon,
			How = `Win a round of {name}`,
			Kind = "Game",
			GameId = game.Id,
			BadgeId = tonumber(badges[id]) or 0,
			Order = 0,
		})
	end
	return catalog
end

-- Whether a player won the round, the way its rewards count it ("Winner!", and a win in the
-- career stats): first place (every member of the winning team shares it in the team games, and a
-- draw makes everyone a winner: RoundContext.TeamResults), or being on the winning team.
function MedalLogic.IsWin(place: number, team: string?, winningTeam: string?): boolean
	if place == 1 then
		return true
	end
	return winningTeam ~= nil and winningTeam ~= "" and team ~= nil and team ~= "" and team == winningTeam
end

-- The medals a player's career stats (Logic/ProgressionLogic.RecordRound keeps them) and collection
-- have earned that they don't have yet: wins, every game played, every game's medal. `games` are
-- the games that count (default: every game medal's game). The stats don't say which games were
-- won, only how many, so the game medals themselves are only given for wins.
function MedalLogic.Earned(
	stats: { [string]: any }?,
	owned: { [string]: any }?,
	catalog: Catalog,
	games: { string }?
): { string }
	local have = owned or {}
	local found: { string } = {}
	local function check(id: string, earned: boolean)
		if earned and catalog.ById[id] and have[id] == nil then
			table.insert(found, id)
		end
	end
	local wins = tonumber(stats and stats.Wins) or 0
	check("FirstWin", wins >= MedalLogic.WinSteps.FirstWin)
	check("TenWins", wins >= MedalLogic.WinSteps.TenWins)
	check("FiftyWins", wins >= MedalLogic.WinSteps.FiftyWins)

	local counted: { string } = {}
	if games then
		counted = games
	else
		for _, medal in catalog.Games do
			table.insert(counted, medal.GameId :: string)
		end
	end
	local plays = if stats and type(stats.ModePlays) == "table" then stats.ModePlays else {}
	local playedAll, wonAll = #counted > 0, #counted > 0
	for _, gameId in counted do
		if (tonumber(plays[gameId]) or 0) <= 0 then
			playedAll = false
		end
		if have[MedalLogic.GameMedalId(gameId)] == nil then
			wonAll = false
		end
	end
	check("EveryGame", playedAll)
	check("WonEveryGame", wonAll)
	return found
end

-- How many of the list's medals a player has, and how many there are.
function MedalLogic.Progress(catalog: Catalog, owned: { [string]: any }?): (number, number)
	local have = 0
	for _, medal in catalog.List do
		if owned and owned[medal.Id] ~= nil then
			have += 1
		end
	end
	return have, #catalog.List
end

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

-- The day a medal was earned (a UTC day number, Logic/DailyLogic.DayNumber) as a date: "Oct 22", or
-- "Oct 22, 2026" when it isn't this year (`today` is today's day number).
function MedalLogic.DateText(day: number, today: number?): string
	local date = os.date("!*t", math.floor(day) * 86400) :: any
	local text = `{MONTHS[date.month]} {date.day}`
	if today then
		local now = os.date("!*t", math.floor(today) * 86400) :: any
		if now.year == date.year then
			return text
		end
	end
	return `{text}, {date.year}`
end

-- The medal wall (World/MedalWall): a grid of medals on a panel of fixed width, the big medals in
-- their own rows on top, then the games' rows under a divider. Rows are centred. More games make
-- more rows (the panel grows taller); past MAX_GAME_ROWS the rows take more medals, smaller.
export type WallSlot = { X: number, Y: number, Big: boolean }
export type WallLayout = {
	Columns: number,
	Pitch: number, -- medal to medal, across (studs)
	RowPitch: number, -- row to row
	Disc: number, -- a medal's diameter
	Ribbon: number, -- how far its ribbon reaches above the disc
	Width: number, -- the panel
	Height: number,
	DividerY: number, -- the line between the big medals and the games (from the panel's bottom)
	Slots: { WallSlot }, -- one per medal, big ones first: X across from the middle, Y up from the bottom
}

local WALL_INNER = 16.2 -- the panel's width inside its margins (studs)
local WALL_MARGIN = 0.4 -- each side, and above the top row and below the bottom one
local MIN_COLUMNS = 9
local MAX_GAME_ROWS = 5
local DIVIDER = 0.5 -- the gap the divider line sits in
-- A row is a medal's disc with its ribbon over it: the disc's middle sits this far up the row, the
-- ribbon's top this far (the rest is the gap to the disc above).
local DISC_AT, RIBBON_TOP = 0.35, 0.93

function MedalLogic.WallLayout(bigCount: number, gameCount: number): WallLayout
	local columns = math.max(MIN_COLUMNS, math.ceil(gameCount / MAX_GAME_ROWS))
	local pitch = WALL_INNER / columns
	local disc = pitch * 0.8
	local rowPitch = disc * 1.6
	local bigRows = math.ceil(bigCount / columns)
	local gameRows = math.ceil(gameCount / columns)
	local divided = bigRows > 0 and gameRows > 0
	local height = 2 * WALL_MARGIN + (bigRows + gameRows) * rowPitch + (if divided then DIVIDER else 0)
	local slots: { WallSlot } = {}
	-- Rows from the top down, sharing the medals out evenly (28 games: four rows of 7).
	local top = height - WALL_MARGIN
	local function rows(count: number, big: boolean)
		local rowCount = math.ceil(count / columns)
		for row = 1, rowCount do
			-- The first rows take one more when they don't share out exactly.
			local inRow = count // rowCount + (if row <= count % rowCount then 1 else 0)
			local y = top - row * rowPitch + rowPitch * DISC_AT
			for index = 1, inRow do
				table.insert(slots, { X = (index - (inRow + 1) / 2) * pitch, Y = y, Big = big })
			end
		end
		top -= rowCount * rowPitch
	end
	rows(bigCount, true)
	local dividerY = top - (if divided then DIVIDER / 2 else 0)
	if divided then
		top -= DIVIDER
	end
	rows(gameCount, false)
	return {
		Columns = columns,
		Pitch = pitch,
		RowPitch = rowPitch,
		Disc = disc,
		Ribbon = rowPitch * (RIBBON_TOP - DISC_AT) - disc / 2,
		Width = WALL_INNER + 2 * WALL_MARGIN,
		Height = height,
		DividerY = dividerY,
		Slots = slots,
	}
end

return MedalLogic
