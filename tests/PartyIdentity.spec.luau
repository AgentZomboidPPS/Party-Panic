-- Checks a party's look (src/shared/Logic/PartyIdentity; owner: "Also make the party system insane. I
-- want it to look super epic."): the fixed word lists stay short and friendly, the colours and emblems
-- are sets of 8 that tell parties apart, a new party gets a look of its own, a reroll always changes
-- the name, and every request a client can send is checked (the leader only, real indices, a cooldown).
local TestKit = require("./TestKit")
local PartyIdentity = require("../src/shared/Logic/PartyIdentity")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

local function picker(seed: number): PartyIdentity.Pick
	return TestKit.seeded(seed).index
end

-- A picker that always says `value` (clamped to the count it's asked for).
local function always(value: number): PartyIdentity.Pick
	return function(count: number): number
		return math.clamp(value, 1, count)
	end
end

-- Mild words no generated name may ever contain (the lists are fixed and reviewed; this keeps a
-- careless addition out).
local NEVER = { "kill", "dead", "die", "gun", "blood", "hate", "dumb", "stupid", "butt", "poop", "fart" }

test("PartyIdentity: the word lists are short, friendly words, each once, none in both", function()
	local seen = {}
	for _, list in { PartyIdentity.Adjectives, PartyIdentity.Nouns } do
		expectTrue(#list >= 20, "plenty of words to roll")
		for _, word in list do
			expectTrue(string.match(word, "^%u%l+$") ~= nil, `{word}: one capitalised word, letters only`)
			expectTrue(#word <= 8, `{word}: 8 letters at most`)
			expectTrue(seen[string.lower(word)] == nil, `{word} is listed once`)
			seen[string.lower(word)] = true
			for _, bad in NEVER do
				expectTrue(string.find(string.lower(word), bad, 1, true) == nil, `{word} contains "{bad}"`)
			end
		end
	end
	-- No adjective is a noun's stem ("Rocket Rockets").
	for _, adjective in PartyIdentity.Adjectives do
		for _, noun in PartyIdentity.Nouns do
			expectTrue(string.sub(string.lower(noun), 1, #adjective) ~= string.lower(adjective), `{adjective} {noun}`)
		end
	end
end)

test("PartyIdentity: 8 colours and 8 emblems, each its own", function()
	expectEqual(#PartyIdentity.Colors, 8)
	expectEqual(#PartyIdentity.Emblems, 8)
	local names, icons = {}, {}
	for index, color in PartyIdentity.Colors do
		expectTrue(names[color.Name] == nil, `colour {color.Name} is listed once`)
		names[color.Name] = true
		expectEqual(#color.Rgb, 3, `{color.Name} is RGB`)
		for _, channel in color.Rgb do
			expectTrue(channel >= 0 and channel <= 255 and channel % 1 == 0, `{color.Name}: 0-255`)
		end
		-- Bright enough for white words with a dark stroke, and apart from every other one.
		expectTrue(math.max(color.Rgb[1], color.Rgb[2], color.Rgb[3]) >= 200, `{color.Name} is bright`)
		for other = index + 1, #PartyIdentity.Colors do
			local rgb = PartyIdentity.Colors[other].Rgb
			local distance = math.abs(rgb[1] - color.Rgb[1])
				+ math.abs(rgb[2] - color.Rgb[2])
				+ math.abs(rgb[3] - color.Rgb[3])
			expectTrue(distance >= 90, `{color.Name} and {PartyIdentity.Colors[other].Name} look alike`)
		end
	end
	for _, emblem in PartyIdentity.Emblems do
		expectTrue(icons[emblem.Icon] == nil, `emblem {emblem.Name} has its own icon`)
		icons[emblem.Icon] = true
		expectTrue(names[emblem.Name] == nil, `emblem {emblem.Name} has its own name`)
		names[emblem.Name] = true
	end
	-- Marks the party HUD already uses for something else: the leader, a friend, the streak.
	for _, used in { "👑", "⭐", "🔥", "👥" } do
		expectTrue(icons[used] == nil, `{used} means something else`)
	end
end)

test("PartyIdentity: a name is its adjective and noun, and every one fits the crest", function()
	local identity = PartyIdentity.New(always(1))
	expectEqual(PartyIdentity.Name(identity), `{PartyIdentity.Adjectives[1]} {PartyIdentity.Nouns[1]}`)
	local longest = 0
	for _, adjective in PartyIdentity.Adjectives do
		for _, noun in PartyIdentity.Nouns do
			longest = math.max(longest, #adjective + 1 + #noun)
		end
	end
	expectTrue(longest <= 17, `the longest name has {longest} characters`)
	expectEqual(
		PartyIdentity.Show(identity),
		{ Name = PartyIdentity.Name(identity), Color = identity.Color, Emblem = identity.Emblem }
	)
end)

test("PartyIdentity: a new party wears a colour and an emblem no other party has", function()
	local pick = picker(7)
	local colors, emblems, names = {}, {}, {}
	for _ = 1, 8 do
		local identity = PartyIdentity.New(pick, { Colors = colors, Emblems = emblems, Names = names })
		expectTrue(PartyIdentity.Index(identity.Adjective, #PartyIdentity.Adjectives) ~= nil, "a real adjective")
		expectTrue(PartyIdentity.Index(identity.Noun, #PartyIdentity.Nouns) ~= nil, "a real noun")
		expectTrue(not colors[identity.Color], `colour {identity.Color} is free`)
		expectTrue(not emblems[identity.Emblem], `emblem {identity.Emblem} is free`)
		expectTrue(not names[PartyIdentity.Name(identity)], "a name of its own")
		colors[identity.Color] = true
		emblems[identity.Emblem] = true
		names[PartyIdentity.Name(identity)] = true
	end
	-- All 8 taken: a ninth still gets a real one.
	local ninth = PartyIdentity.New(pick, { Colors = colors, Emblems = emblems })
	expectTrue(PartyIdentity.Index(ninth.Color, 8) ~= nil and PartyIdentity.Index(ninth.Emblem, 8) ~= nil, "valid")
	-- Without anything taken it's just random, and the same seed gives the same look.
	local a, b = PartyIdentity.New(picker(3)), PartyIdentity.New(picker(3))
	expectEqual(PartyIdentity.Show(a), PartyIdentity.Show(b))
end)

test("PartyIdentity: a reroll always changes the name", function()
	local identity = PartyIdentity.New(picker(11))
	local pick = picker(12)
	for _ = 1, 300 do
		local before = PartyIdentity.Name(identity)
		PartyIdentity.Reroll(identity, pick)
		expectTrue(PartyIdentity.Name(identity) ~= before, `rerolled to the same name {before}`)
		expectTrue(PartyIdentity.Index(identity.Adjective, #PartyIdentity.Adjectives) ~= nil, "a real adjective")
		expectTrue(PartyIdentity.Index(identity.Noun, #PartyIdentity.Nouns) ~= nil, "a real noun")
	end
	-- The edges of the roll: the first pair and the last pair.
	local total = #PartyIdentity.Adjectives * #PartyIdentity.Nouns
	identity.Adjective, identity.Noun = 1, 1
	PartyIdentity.Reroll(identity, always(1))
	expectEqual({ identity.Adjective, identity.Noun }, { 1, 2 }) -- the first pair is skipped
	PartyIdentity.Reroll(identity, always(total - 1))
	expectEqual({ identity.Adjective, identity.Noun }, { #PartyIdentity.Adjectives, #PartyIdentity.Nouns })
	PartyIdentity.Reroll(identity, always(total - 1))
	expectEqual(
		{ identity.Adjective, identity.Noun },
		{ #PartyIdentity.Adjectives, #PartyIdentity.Nouns - 1 },
		"from the last pair, the roll's top lands just before it"
	)
end)

test("PartyIdentity: an index is a whole number in range, and nothing else", function()
	for _, good in { 1, 4, 8 } do
		expectEqual(PartyIdentity.Index(good, 8), good)
	end
	for _, bad in { 0, 9, -1, 1.5, 0 / 0, math.huge, -math.huge, "1", true, {} } do
		expectEqual(PartyIdentity.Index(bad, 8), nil, `{tostring(bad)} isn't an index`)
	end
	expectEqual(PartyIdentity.Index(nil, 8), nil)
end)

test("PartyIdentity: only the leader changes the look, with real values, not too often", function()
	local pick = picker(5)
	local identity = PartyIdentity.New(pick)
	identity.Color, identity.Emblem = 1, 1
	local cooldown = PartyIdentity.EditCooldown
	-- Not the leader.
	expectEqual({ PartyIdentity.Edit(identity, 2, "Color", 3, 100, pick) }, { false, "NotLeader" })
	expectEqual({ PartyIdentity.Edit(identity, nil, "Reroll", nil, 100, pick) }, { false, "NotLeader" })
	-- Junk.
	expectEqual({ PartyIdentity.Edit(identity, 1, "Name", "Cool Kids", 100, pick) }, { false, "Bad" })
	expectEqual({ PartyIdentity.Edit(identity, 1, 42, 3, 100, pick) }, { false, "Bad" })
	expectEqual({ PartyIdentity.Edit(identity, 1, "Color", 9, 100, pick) }, { false, "Bad" })
	expectEqual({ PartyIdentity.Edit(identity, 1, "Color", 2.5, 100, pick) }, { false, "Bad" })
	expectEqual({ PartyIdentity.Edit(identity, 1, "Emblem", 0 / 0, 100, pick) }, { false, "Bad" })
	expectEqual({ PartyIdentity.Edit(identity, 1, "Emblem", "3", 100, pick) }, { false, "Bad" })
	expectEqual({ PartyIdentity.Edit(identity, 1, "Color", 1, 100, pick) }, { false, "Same" })
	expectEqual({ identity.Color, identity.Emblem }, { 1, 1 }, "nothing changed")
	-- The leader picks a colour, then has to wait a moment before the next change.
	expectEqual({ PartyIdentity.Edit(identity, 1, "Color", 3, 100, pick) }, { true, nil })
	expectEqual(identity.Color, 3)
	expectEqual({ PartyIdentity.Edit(identity, 1, "Emblem", 6, 100 + cooldown / 2, pick) }, { false, "Soon" })
	expectEqual(identity.Emblem, 1)
	expectEqual({ PartyIdentity.Edit(identity, 1, "Emblem", 6, 100 + cooldown + 0.01, pick) }, { true, nil })
	expectEqual(identity.Emblem, 6)
	local before = PartyIdentity.Name(identity)
	expectEqual({ PartyIdentity.Edit(identity, 1, "Reroll", nil, 100 + 3 * cooldown, pick) }, { true, nil })
	expectTrue(PartyIdentity.Name(identity) ~= before, "a new name")
	expectEqual(identity.EditedAt, 100 + 3 * cooldown)
end)

return nil
