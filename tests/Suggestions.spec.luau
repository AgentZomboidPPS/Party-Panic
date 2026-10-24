-- The suggestion box (owner: "Can we add a suggestion box?"; Shared/Logic/Suggestions): the words as
-- they're kept, what's turned down, the kinds, the hour keys and a full hour.
local TestKit = require("./TestKit")
local Suggestions = require("../src/shared/Logic/Suggestions")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

test("Suggestions: the words are tidied, not changed", function()
	expectEqual(Suggestions.Clean("  more maps please!  "), "more maps please!")
	expectEqual(Suggestions.Clean("two   spaces\tand a tab"), "two spaces and a tab")
	expectEqual(Suggestions.Clean("line one\r\nline two"), "line one\nline two")
	expectEqual(Suggestions.Clean("a\n\n\n\n\nlong gap here"), "a\n\nlong gap here")
	expectEqual(Suggestions.Clean("bell\7 and null\0 gone"), "bell and null gone")
	expectEqual(Suggestions.Clean("Add a 🦈 shark game"), "Add a 🦈 shark game")
end)

test("Suggestions: too short, too long or not text is turned down", function()
	expectEqual(Suggestions.Clean("hi"), nil, "too short")
	expectEqual(Suggestions.Clean("        lol         "), nil, "short once trimmed")
	expectEqual(Suggestions.Clean(string.rep("a", 301)), nil, "too long")
	expectEqual(Suggestions.Clean(string.rep("a", 300)), string.rep("a", 300), "the longest that fits")
	expectEqual(Suggestions.Clean(string.rep("🎉", 300)), string.rep("🎉", 300), "300 emoji are 300 characters")
	expectEqual(Suggestions.Clean(nil), nil)
	expectEqual(Suggestions.Clean(42), nil)
	expectEqual(Suggestions.Clean({ "table" }), nil)
	expectEqual(Suggestions.Clean("broken \255\254 bytes here"), nil, "not UTF-8")
end)

test("Suggestions: the four kinds", function()
	expectEqual(#Suggestions.Kinds, 4)
	expectTrue(Suggestions.IsKind("Game") and Suggestions.IsKind("Bug"), "known kinds")
	expectEqual(Suggestions.IsKind("Spam"), false)
	expectEqual(Suggestions.IsKind(nil), false)
end)

test("Suggestions: one key per UTC hour", function()
	expectEqual(Suggestions.Key(0), "1970-01-01T00")
	expectEqual(Suggestions.Key(1792800000 + 17 * 3600 + 59 * 60), "2026-10-24T17")
end)

test("Suggestions: a key's list grows to its cap and no further", function()
	local entry = { T = 1, U = 2, N = "Ann", K = "Game", S = "more maps please", V = 55 }
	local list, added = Suggestions.Append(nil, entry)
	expectEqual(#list, 1)
	expectEqual(added, true)
	local full = table.create(Suggestions.PER_KEY, entry)
	local kept, addedToFull = Suggestions.Append(full, entry)
	expectEqual(#kept, Suggestions.PER_KEY, "a full hour keeps what it has")
	expectEqual(addedToFull, false)
end)
