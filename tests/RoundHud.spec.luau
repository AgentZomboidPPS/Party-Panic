-- Checks what the round's HUD keeps when room is tight (src/shared/Logic/RoundHud; owner: "During the
-- mini games, any way we can save UI space so they can see more of the game at one time?"): the
-- players-left count every elimination mode writes in its status goes into the banner's pill, the
-- rest of the line stays, and the phone standings show you and the leader.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local TestKit = require("./TestKit")

local test, expectEqual = TestKit.test, TestKit.expectEqual

local RoundHud = luau.load(fs.readFile("src/shared/Logic/RoundHud.luau"), { debugName = "RoundHud" })()

local function split(text: string?): { any }
	local count, icon, rest = RoundHud.SplitStatus(text)
	return { count or false, icon or false, rest }
end

test("SplitStatus: a status that's just the count goes into the pill whole", function()
	expectEqual(split("Players left: 6"), { 6, "👤", "" })
	expectEqual(split("Survivors: 9"), { 9, "👤", "" })
	expectEqual(split("On the summit: 4"), { 4, "👤", "" })
	expectEqual(split("5 tanks left"), { 5, "👤", "" })
	expectEqual(split("1 tank left!"), { 1, "👤", "" })
	expectEqual(split("Players left: 0"), { 0, "👤", "" })
end)

test("SplitStatus: a count with its own icon keeps it", function()
	expectEqual(split("🏃 3 runners left"), { 3, "🏃", "" })
	expectEqual(split("🏃 1 runner left!"), { 1, "🏃", "" })
end)

test("SplitStatus: the rest of the line stays, either side of the count", function()
	expectEqual(split("❄ The ice is cracking!  •  Players left: 3"), { 3, "👤", "❄ The ice is cracking!" })
	expectEqual(split("Players left: 5  •  💥 BIG BUMPS!"), { 5, "👤", "💥 BIG BUMPS!" })
	expectEqual(split("Jumps: 4  •  Players left: 7"), { 7, "👤", "Jumps: 4" })
	expectEqual(split("Bubbles's turn  •  Players left: 6"), { 6, "👤", "Bubbles's turn" })
	expectEqual(split("🟥 RED!  •  Players left: 8"), { 8, "👤", "🟥 RED!" })
end)

test("SplitStatus: lines without a players-left count are left alone", function()
	expectEqual(split("Rake veggies into your basket - skip the bombs!"), {
		false,
		false,
		"Rake veggies into your basket - skip the bombs!",
	})
	expectEqual(split("🏁 2 home  •  🛹 5 skating"), { false, false, "🏁 2 home  •  🛹 5 skating" })
	expectEqual(split("🏊 3 coins to go!"), { false, false, "🏊 3 coins to go!" })
	expectEqual(split("2 orbs on the ground - grab them!"), { false, false, "2 orbs on the ground - grab them!" })
	expectEqual(split("STEAK 2/5  •  Cut it 50 : 50!"), { false, false, "STEAK 2/5  •  Cut it 50 : 50!" })
	expectEqual(
		split("🥕 Hold GALLOP · HOP over the hurdles!"),
		{ false, false, "🥕 Hold GALLOP · HOP over the hurdles!" }
	)
	expectEqual(split(""), { false, false, "" })
	expectEqual(split(nil), { false, false, "" })
end)

test("BoardPlaces: you and the leader, or just you when you lead", function()
	expectEqual(RoundHud.BoardPlaces(8, 6, false), { 1, 6 })
	expectEqual(RoundHud.BoardPlaces(8, 2, false), { 1, 2 })
	expectEqual(RoundHud.BoardPlaces(8, 1, false), { 1 })
	expectEqual(RoundHud.BoardPlaces(1, 1, false), { 1 })
end)

test("BoardPlaces: after a tap, the top three plus you", function()
	expectEqual(RoundHud.BoardPlaces(8, 6, true), { 1, 2, 3, 6 })
	expectEqual(RoundHud.BoardPlaces(8, 2, true), { 1, 2, 3 })
	expectEqual(RoundHud.BoardPlaces(2, 2, true), { 1, 2 })
end)

test("BoardPlaces: someone not in the round sees the top three", function()
	expectEqual(RoundHud.BoardPlaces(8, nil, false), { 1, 2, 3 })
	expectEqual(RoundHud.BoardPlaces(2, nil, true), { 1, 2 })
	expectEqual(RoundHud.BoardPlaces(0, nil, false), {})
end)
