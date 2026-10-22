-- Medals (owner: "Medals: a medal for winning each game and a few big ones, Roblox badges, a
-- collect-them-all wall in the lobby"): the list (every game that's on gets its medal, the ids the
-- other features award exist), who won a round, which medals career stats have already earned
-- (players who won before medals existed), the dates on the medal screen, and the medal wall's
-- layout as the game list grows.
local fs = require("@lune/fs")

local TestKit = require("./TestKit")
local MedalLogic = require("../src/shared/Logic/MedalLogic")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

-- The games as GameDefinitions lists them (read from the source, like the other specs).
local definitions = fs.readFile("src/shared/GameDefinitions.luau")
local games = {}
for entry in string.gmatch(definitions, "\n\t{\n(.-)\n\t},") do
	local block = "\n" .. entry
	local id = string.match(block, '\n\t\tId = "(%w+)"')
	if id then
		table.insert(games, {
			Id = id,
			Name = string.match(block, '\n\t\tName = "([^"]+)"'),
			Icon = string.match(block, '\n\t\tIcon = "([^"]+)"'),
			Enabled = if string.find(block, "\n\t\tEnabled = false", 1, true) then false else nil,
		})
	end
end

local catalog = MedalLogic.Build(games)

local function ids(list: { any }): { string }
	local out = {}
	for _, medal in list do
		table.insert(out, medal.Id)
	end
	return out
end

test("every game that's on has its own medal, after the big ones", function()
	expectTrue(#games >= 25, `read {#games} games from GameDefinitions`)
	for _, game in games do
		local medal = catalog.ById["Win" .. game.Id]
		if game.Enabled == false then
			expectEqual(medal, nil, `{game.Id} is off: no medal`)
		else
			expectTrue(medal ~= nil, `{game.Id} has a medal`)
			expectEqual(medal.Kind, "Game")
			expectEqual(medal.GameId, game.Id)
			expectEqual(medal.Icon, game.Icon, "a game's medal wears its game's icon")
			expectEqual(medal.Short, string.upper(game.Name), "game names in capitals")
			expectEqual(medal.How, `Win a round of {string.upper(game.Name)}`)
		end
	end
	expectEqual(#catalog.List, #catalog.Big + #catalog.Games)
	for index, medal in catalog.List do
		expectEqual(medal.Order, index, "Order is the place in the list")
		expectEqual(medal.Kind == "Big", index <= #catalog.Big, "the big medals come first")
		expectEqual(catalog.ById[medal.Id], medal)
	end
end)

test("a game added later gets its medal; a game switched off loses it", function()
	local more = table.clone(games)
	table.insert(more, { Id = "HotPotato", Name = "Hot Potato", Icon = "🥔" })
	table.insert(more, { Id = "OldGame", Name = "Old Game", Icon = "🎮", Enabled = false })
	local grown = MedalLogic.Build(more)
	expectEqual(#grown.Games, #catalog.Games + 1)
	expectEqual(grown.ById.WinHotPotato.Name, "HOT POTATO Winner")
	expectEqual(grown.ById.WinOldGame, nil)
end)

test("the ids the other features award are medals (MedalService's header)", function()
	for _, id in { "CupChampion", "HallOfFame", "Halloween2026", "FriendsParty" } do
		local medal = catalog.ById[id]
		expectTrue(medal ~= nil and medal.Kind == "Big", `{id} is a big medal`)
	end
	for _, id in { "FirstWin", "TenWins", "FiftyWins", "EveryGame", "WonEveryGame" } do
		expectTrue(catalog.ById[id] ~= nil, `{id} is a medal`)
	end
end)

test("every medal has a name, an icon phones can show, and how to earn it in one short line", function()
	local seen = {}
	for _, medal in catalog.List do
		expectTrue(not seen[medal.Id], `{medal.Id} is listed once`)
		seen[medal.Id] = true
		expectTrue(#medal.Name > 0 and #medal.Short > 0 and #medal.Icon > 0, `{medal.Id} has a name and an icon`)
		expectTrue(utf8.len(medal.How) ~= nil and (utf8.len(medal.How) :: number) <= 36, `{medal.Id}: "{medal.How}"`)
		expectTrue(utf8.len(medal.Name) ~= nil and (utf8.len(medal.Name) :: number) <= 28, `{medal.Id}: "{medal.Name}"`)
		-- Emoji from Unicode 13 or later show blank on phones (tools/checks/ui_render.py NEW_EMOJI).
		for _, code in utf8.codes(medal.Icon) do
			local new = (code >= 0x1FA74 and code <= 0x1FAFF and not (code >= 0x1FA78 and code <= 0x1FA7A))
				or (code >= 0x1FA80 and code <= 0x1FA82)
				or code == 0x1F6D6
				or code == 0x1F6D7
				or (code >= 0x1F6DC and code <= 0x1F6DF)
				or code == 0x1F6FB
				or code == 0x1F6FC
				or code == 0x1F90C
				or code == 0x1F972
				or (code >= 0x1F977 and code <= 0x1F979)
				or code == 0x1F9A3
				or code == 0x1F9A4
				or (code >= 0x1F9AB and code <= 0x1F9AD)
				or code == 0x1F9CB
				or code == 0x1F9CC
				or code == 0x1F7F0
			expectTrue(not new, `{medal.Id}'s icon is newer than phones show`)
		end
		expectEqual(medal.BadgeId, 0, "no badges until the owner makes them")
	end
end)

test("badge ids come from the table they're given", function()
	local withBadges = MedalLogic.Build(games, { CupChampion = 123, WinFireRope = 456 })
	expectEqual(withBadges.ById.CupChampion.BadgeId, 123)
	expectEqual(withBadges.ById.WinFireRope.BadgeId, 456)
	expectEqual(withBadges.ById.HallOfFame.BadgeId, 0)
end)

test("a round's winners: first place, and everyone on the winning team", function()
	expectTrue(MedalLogic.IsWin(1, nil, nil), "first place")
	expectEqual(MedalLogic.IsWin(2, nil, nil), false)
	expectTrue(MedalLogic.IsWin(1, "Red", "Red"), "the winning team shares first place")
	expectTrue(MedalLogic.IsWin(3, "Red", "Red"), "on the winning team")
	expectEqual(MedalLogic.IsWin(2, "Blue", "Red"), false)
	expectTrue(MedalLogic.IsWin(1, "Blue", nil), "a draw makes everyone a winner (all share first place)")
	expectEqual(MedalLogic.IsWin(2, "", ""), false, "no team is nobody's team")
end)

test("career stats earn the win medals, once each", function()
	expectEqual(MedalLogic.Earned({ Wins = 0 }, {}, catalog), {})
	expectEqual(MedalLogic.Earned(nil, nil, catalog), {})
	expectEqual(MedalLogic.Earned({ Wins = 1 }, {}, catalog), { "FirstWin" })
	expectEqual(MedalLogic.Earned({ Wins = 12 }, {}, catalog), { "FirstWin", "TenWins" })
	expectEqual(MedalLogic.Earned({ Wins = 50 }, {}, catalog), { "FirstWin", "TenWins", "FiftyWins" })
	expectEqual(MedalLogic.Earned({ Wins = 60 }, { FirstWin = 20000, TenWins = 20100 }, catalog), { "FiftyWins" })
end)

test("playing every game and winning every game", function()
	local all = {}
	for _, medal in catalog.Games do
		all[medal.GameId] = 2
	end
	local some = table.clone(all)
	some[catalog.Games[1].GameId] = nil
	expectEqual(MedalLogic.Earned({ ModePlays = all }, {}, catalog), { "EveryGame" })
	expectEqual(MedalLogic.Earned({ ModePlays = some }, {}, catalog), {})
	-- Only the games that count (a game switched off on this server doesn't).
	local counted = {}
	for gameId in some do
		table.insert(counted, gameId)
	end
	expectEqual(MedalLogic.Earned({ ModePlays = some }, {}, catalog, counted), { "EveryGame" })
	-- Every game's medal is the collect-them-all medal.
	local owned = {}
	for _, medal in catalog.Games do
		owned[medal.Id] = 20000
	end
	expectEqual(MedalLogic.Earned({ ModePlays = all, Wins = 30 }, owned, catalog), {
		"FirstWin",
		"TenWins",
		"EveryGame",
		"WonEveryGame",
	})
	owned[catalog.Games[3].Id] = nil
	expectEqual(MedalLogic.Earned({}, owned, catalog), {}, "one game short")
	expectEqual(MedalLogic.Earned({}, {}, MedalLogic.Build({})), {}, "no games: nothing to collect")
end)

test("progress counts only the medals in the list", function()
	local have, total = MedalLogic.Progress(catalog, { FirstWin = 1, WinFireRope = 2, RetiredMedal = 3 })
	expectEqual(have, 2)
	expectEqual(total, #catalog.List)
	expectEqual(select(1, MedalLogic.Progress(catalog, nil)), 0)
end)

test("the day a medal was earned reads as a date", function()
	local day = 20748 -- 2026-10-22 (UTC)
	expectEqual(MedalLogic.DateText(day, day), "Oct 22")
	expectEqual(MedalLogic.DateText(day, day + 100), "Oct 22, 2026", "another year shows its year")
	expectEqual(MedalLogic.DateText(0), "Jan 1, 1970")
end)

local function checkWall(bigCount: number, gameCount: number)
	local wall = MedalLogic.WallLayout(bigCount, gameCount)
	local where = `{bigCount} big + {gameCount} games`
	expectEqual(#wall.Slots, bigCount + gameCount, where)
	expectEqual(wall.Width, MedalLogic.WallLayout(9, 25).Width, `{where}: the wall keeps its width`)
	expectTrue(wall.Height <= 16, `{where}: {wall.Height} studs tall`)
	expectTrue(wall.Disc >= 0.8, `{where}: medals stay big enough to see`)
	-- Rows share the medals out evenly (28 games: four rows of 7, not three of 9 and one of 1).
	local perRow = {}
	for _, slot in wall.Slots do
		local key = string.format("%s%.3f", tostring(slot.Big), slot.Y)
		perRow[key] = (perRow[key] or 0) + 1
	end
	local fewest, most = math.huge, 0
	for key, count in perRow do
		if string.sub(key, 1, 5) == "false" then
			fewest, most = math.min(fewest, count), math.max(most, count)
		end
	end
	if gameCount > 0 then
		expectTrue(most - fewest <= 2, `{where}: game rows of {fewest} to {most}`)
	end
	for index, slot in wall.Slots do
		expectEqual(slot.Big, index <= bigCount, `{where}: big medals first`)
		expectTrue(math.abs(slot.X) + wall.Disc / 2 <= wall.Width / 2, `{where}: slot {index} inside across`)
		expectTrue(slot.Y - wall.Disc / 2 >= 0, `{where}: slot {index} above the bottom`)
		expectTrue(slot.Y + wall.Disc / 2 + wall.Ribbon <= wall.Height, `{where}: slot {index}'s ribbon inside`)
		for other = index + 1, #wall.Slots do
			local b = wall.Slots[other]
			local apart = math.sqrt((slot.X - b.X) ^ 2 + (slot.Y - b.Y) ^ 2)
			expectTrue(apart >= wall.Disc, `{where}: slots {index} and {other} don't overlap`)
			if b.Y < slot.Y - 0.01 then
				-- A ribbon reaches up toward the disc above; it never touches it.
				expectTrue(slot.Y - wall.Disc / 2 > b.Y + wall.Disc / 2 + wall.Ribbon, `{where}: ribbon {other} clear`)
			end
		end
		if slot.Big then
			for game = bigCount + 1, #wall.Slots do
				expectTrue(wall.Slots[game].Y < slot.Y, `{where}: the games sit under the big medals`)
			end
		end
	end
	-- Each row is centred.
	local rows = {}
	for _, slot in wall.Slots do
		local key = string.format("%.3f", slot.Y)
		rows[key] = (rows[key] or 0) + slot.X
	end
	for key, sum in rows do
		expectTrue(math.abs(sum) < 1e-6, `{where}: row at {key} is centred`)
	end
end

test("the medal wall fits today's medals and grows with the game list", function()
	local today = MedalLogic.WallLayout(#catalog.Big, #catalog.Games)
	expectEqual(today.Columns, 9)
	checkWall(#catalog.Big, #catalog.Games)
	for _, gameCount in { 1, 9, 26, 27, 28, 36, 45, 46, 60, 80 } do
		checkWall(9, gameCount)
	end
	checkWall(11, 30) -- more big medals: a second row
	checkWall(0, 25)
end)

test("the rules module is a leaf (no requires), so these tests run it as the game does", function()
	local source = fs.readFile("src/shared/Logic/MedalLogic.luau")
	expectTrue(not string.find(source, "require(", 1, true), "MedalLogic requires nothing")
end)

return nil
