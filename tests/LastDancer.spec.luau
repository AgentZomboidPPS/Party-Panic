local TestKit = require("./TestKit")
local LastDancer = require("../src/shared/Logic/LastDancer")
local Chart = require("../src/shared/LastDancerChart")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

local function near(a: number, b: number, slack: number?): boolean
	return math.abs(a - b) <= (slack or 1e-9)
end

-- A tiny chart: lane 1 at 1.0 s, lane 2 at 1.5 s, lane 1 again at 1.75 s, lane 4 at 3.0 s.
local function small()
	return { Notes = { { T = 1.0, Lane = 1 }, { T = 1.5, Lane = 2 }, { T = 1.75, Lane = 1 }, { T = 3.0, Lane = 4 } } }
end

test("the round is eight phrases of four bars at 120 bpm", function()
	expectEqual(LastDancer.BEAT, 0.5)
	expectEqual(LastDancer.PHRASE, 8)
	expectEqual(LastDancer.DURATION, 64)
end)

test("Judge: perfect, great and ok by how close, nothing beyond the ok window", function()
	expectEqual(LastDancer.Judge(0), "Perfect")
	expectEqual(LastDancer.Judge(-0.06), "Perfect")
	expectEqual(LastDancer.Judge(0.1), "Great")
	expectEqual(LastDancer.Judge(-0.16), "Ok")
	expectEqual(LastDancer.Judge(0.2), nil)
end)

test("Tap: hits the nearest waiting note in the lane and scores it", function()
	local chart, dancer = small(), LastDancer.new()
	local outcome = LastDancer.Tap(chart, dancer, 1, 1.02)
	expectEqual(outcome.Kind, "Perfect")
	expectEqual(outcome.Index, 1)
	expectTrue(near(outcome.Offset :: number, 0.02), "the offset is tap - note")
	expectEqual(dancer.Combo, 1)
	expectEqual(dancer.Score, LastDancer.POINTS.Perfect + LastDancer.COMBO_BONUS)
	expectEqual(dancer.Next, 2)
end)

test("Tap: a note is only hit once", function()
	local chart, dancer = small(), LastDancer.new()
	expectEqual(LastDancer.Tap(chart, dancer, 1, 1.0).Kind, "Perfect")
	expectEqual(LastDancer.Tap(chart, dancer, 1, 1.0).Kind, "Stray")
end)

test("Tap: of two notes in a lane in reach it takes the nearer one", function()
	local chart, dancer = small(), LastDancer.new()
	-- lane 1 has notes at 1.0 and 1.75; 1.66 s is 0.09 s from the second and 0.66 s from the first
	local outcome = LastDancer.Tap(chart, dancer, 1, 1.66)
	expectEqual(outcome.Index, 3)
	expectEqual(outcome.Kind, "Great")
end)

test("Tap: the wrong lane, too early, too late and nonsense are strays", function()
	local chart, dancer = small(), LastDancer.new()
	expectEqual(LastDancer.Tap(chart, dancer, 3, 1.0).Kind, "Stray")
	expectEqual(LastDancer.Tap(chart, dancer, 1, 0.5).Kind, "Stray")
	expectEqual(LastDancer.Tap(chart, dancer, 1, 1.4).Kind, "Stray")
	expectEqual(LastDancer.Tap(chart, dancer, 0, 1.0).Kind, "Stray")
	expectEqual(LastDancer.Tap(chart, dancer, 5, 1.0).Kind, "Stray")
	expectEqual(LastDancer.Tap(chart, dancer, 1.5, 1.0).Kind, "Stray")
	expectEqual(LastDancer.Tap(chart, dancer, "1", 1.0).Kind, "Stray")
	expectEqual(LastDancer.Tap(chart, dancer, 1, 0 / 0).Kind, "Stray")
	expectEqual(LastDancer.Tap(chart, dancer, 1, math.huge).Kind, "Stray")
	expectEqual(dancer.Stray, 9)
	expectEqual(dancer.Score, 0)
end)

test("Tap: a stray breaks the combo and pulls the groove down", function()
	local chart, dancer = small(), LastDancer.new()
	LastDancer.Tap(chart, dancer, 1, 1.0)
	local before = dancer.Groove
	LastDancer.Tap(chart, dancer, 3, 2.0)
	expectEqual(dancer.Combo, 0)
	expectTrue(dancer.Groove < before, "groove fell")
	expectEqual(dancer.BestCombo, 1)
end)

test("Expire: notes nobody hit become misses once their window is over", function()
	local chart, dancer = small(), LastDancer.new()
	expectEqual(#LastDancer.Expire(chart, dancer, 1.1), 0) -- inside the window of the first note
	local missed = LastDancer.Expire(chart, dancer, 1.2)
	expectEqual(#missed, 1)
	expectEqual(missed[1], 1)
	expectEqual(dancer.Miss, 1)
	expectEqual(dancer.Next, 2)
	expectEqual(#LastDancer.Expire(chart, dancer, 1.2), 0) -- only once
end)

test("Expire: a note that was hit is not missed, and a late tap on a missed note is a stray", function()
	local chart, dancer = small(), LastDancer.new()
	LastDancer.Tap(chart, dancer, 1, 1.0)
	expectEqual(#LastDancer.Expire(chart, dancer, 1.3), 0)
	LastDancer.Expire(chart, dancer, 2.0) -- the lane 2 note at 1.5 and lane 1 note at 1.75 are gone
	expectEqual(dancer.Miss, 2)
	expectEqual(LastDancer.Tap(chart, dancer, 2, 1.55).Kind, "Stray")
end)

test("groove: perfect play climbs towards 1 without passing it, misses pull it to 0", function()
	local dancer = LastDancer.new()
	local chart = { Notes = {} }
	for index = 1, 200 do
		table.insert(chart.Notes, { T = index * 0.5, Lane = 1 })
	end
	for index = 1, 200 do
		LastDancer.Tap(chart, dancer, 1, index * 0.5)
	end
	expectTrue(dancer.Groove > 0.99 and dancer.Groove <= 1, "perfect play: groove " .. dancer.Groove)
	LastDancer.Expire({ Notes = {} }, dancer, 0)
	local lazy = LastDancer.new()
	LastDancer.Expire(chart, lazy, 100)
	expectTrue(lazy.Groove < 0.01, "a dancer who never taps: groove " .. lazy.Groove)
end)

test("groove: mashing every pad never beats dancing it", function()
	local chart = { Notes = {} }
	for index = 1, 60 do
		table.insert(chart.Notes, { T = index * 0.5, Lane = (index % 4) + 1 })
	end
	local masher, dancer = LastDancer.new(), LastDancer.new()
	for index = 1, 60 do
		local t = index * 0.5
		LastDancer.Tap(chart, dancer, (index % 4) + 1, t + 0.04) -- a decent dancer, a little late
		-- the masher hits all four pads every 80 ms
		for step = -3, 3 do
			for lane = 1, 4 do
				LastDancer.Tap(chart, masher, lane, t + step * 0.08)
			end
		end
	end
	expectTrue(masher.Groove < dancer.Groove - 0.3, `masher {masher.Groove} dancer {dancer.Groove}`)
	expectTrue(masher.Groove < 0.3, "the masher's groove is low: " .. masher.Groove)
end)

test("PressTime: the device's time, within half the lag plus the reach and the sync limit", function()
	expectTrue(near(LastDancer.PressTime(99.95, 100, 0.1), 99.95), "an honest time stands")
	expectTrue(near(LastDancer.PressTime(100.5, 100, 0.1), 100), "never after it arrived")
	local earliest = 100 - 0.05 - LastDancer.REACH - LastDancer.SYNC_MAX
	expectTrue(near(LastDancer.PressTime(50, 100, 0.1), earliest), "a made-up time can't reach back")
	expectTrue(near(LastDancer.PressTime(nil, 100, 0.1), 99.95), "no time: half a round trip ago")
	expectTrue(near(LastDancer.PressTime(0 / 0, 100, 0), 100), "nan is no time")
	expectTrue(near(LastDancer.PressTime("x", 100, 0), 100), "nor is a string")
end)

test("PhraseAt and CutTime: the cuts fall at the end of phrases 2 to 7", function()
	expectEqual(LastDancer.PhraseAt(0), 1)
	expectEqual(LastDancer.PhraseAt(7.99), 1)
	expectEqual(LastDancer.PhraseAt(8), 2)
	expectEqual(LastDancer.PhraseAt(63.9), 8)
	expectEqual(LastDancer.CutTime(1), nil)
	expectEqual(LastDancer.CutTime(2), 16)
	expectEqual(LastDancer.CutTime(7), 56)
	expectEqual(LastDancer.CutTime(8), nil)
end)

-- Plays a whole round of cuts from `alive` dancers, nobody falling any other way.
local function remaining(alive: number): { number }
	local history = { alive }
	for phrase = LastDancer.FIRST_CUT, LastDancer.LAST_CUT do
		alive -= LastDancer.CutCount(alive, phrase)
		table.insert(history, alive)
	end
	return history
end

test("CutCount: 12 dancers lose 2, 2, 2, 2, 1, 1 and two are left for the final duel", function()
	expectEqual(table.concat(remaining(12), ","), "12,10,8,6,4,3,2")
end)

test("CutCount: any size leaves two for the final phrase, and never cuts into them", function()
	for alive = 2, 24 do
		local history = remaining(alive)
		expectEqual(history[#history], 2)
		for index = 2, #history do
			expectTrue(history[index] >= 2, `{alive} dancers: {table.concat(history, ",")}`)
		end
	end
	expectEqual(remaining(1)[7], 1)
	expectEqual(LastDancer.CutCount(12, 1), 0)
	expectEqual(LastDancer.CutCount(12, 8), 0)
end)

test("PickCuts: the lowest groove falls, then the fewest points, then the unluckiest draw", function()
	local entries = {
		{ Key = "a", Groove = 0.9, Score = 5000, Order = 1 },
		{ Key = "b", Groove = 0.3, Score = 900, Order = 2 },
		{ Key = "c", Groove = 0.3, Score = 400, Order = 3 },
		{ Key = "d", Groove = 0.3, Score = 400, Order = 4 },
		{ Key = "e", Groove = 0.7, Score = 100, Order = 5 },
	}
	local cut = LastDancer.PickCuts(entries, 3)
	expectEqual(table.concat(cut, ","), "d,c,b")
	expectEqual(#LastDancer.PickCuts(entries, 99), 5)
	expectEqual(entries[1].Key, "a") -- the input isn't reordered
end)

test("Ahead: higher groove wins, then more points, then the luckier draw", function()
	local a = { Key = "a", Groove = 0.8, Score = 10, Order = 1 }
	local b = { Key = "b", Groove = 0.7, Score = 99, Order = 2 }
	expectTrue(LastDancer.Ahead(a, b), "groove first")
	b.Groove = 0.8
	expectTrue(LastDancer.Ahead(b, a), "then points")
	b.Score = 10
	expectTrue(LastDancer.Ahead(a, b), "then the draw")
	expectTrue(not LastDancer.Ahead(b, a), "and not both ways")
end)

test("Place: where a groove stands among the others", function()
	expectEqual(LastDancer.Place({ 0.9, 0.5, 0.7 }, 0.7), 2)
	expectEqual(LastDancer.Place({ 0.9, 0.5, 0.7 }, 0.95), 1)
	expectEqual(LastDancer.Place({ 0.9, 0.5, 0.7 }, 0.1), 4)
end)

test("the chart: well formed, on the song's eighth notes, with the cut beats free", function()
	expectEqual(LastDancer.Check(Chart, LastDancer.BEAT / 2), nil)
	expectEqual(Chart.Bpm, LastDancer.BPM)
	for index, note in Chart.Notes do
		local eighths = note.T / (LastDancer.BEAT / 2)
		expectTrue(near(eighths, math.floor(eighths + 0.5), 1e-6), `note {index} at {note.T}s is off the grid`)
		local phrase = LastDancer.PhraseAt(note.T)
		if LastDancer.CutTime(phrase) then
			local into = note.T - (phrase - 1) * LastDancer.PHRASE
			expectTrue(
				into < LastDancer.PHRASE - LastDancer.BEAT - 1e-6,
				`note {index}: a note in the last beat before a cut`
			)
		end
	end
end)

test("the chart: gets busier and has a note for every lane", function()
	local perPhrase = {}
	local lanes = {}
	for _, note in Chart.Notes do
		local phrase = LastDancer.PhraseAt(note.T)
		perPhrase[phrase] = (perPhrase[phrase] or 0) + 1
		lanes[note.Lane] = true
	end
	for lane = 1, LastDancer.LANES do
		expectTrue(lanes[lane], "lane " .. lane .. " is never used")
	end
	expectTrue(perPhrase[1] < perPhrase[4], "phrase 4 is busier than phrase 1")
	expectTrue(perPhrase[8] >= perPhrase[4], "the final duel is at least as busy as phrase 4")
	for phrase = 1, LastDancer.PHRASES do
		expectTrue((perPhrase[phrase] or 0) >= 10, "phrase " .. phrase .. " has too few notes")
	end
end)

test("a perfect player in every cut stays in; a player who never taps is cut first", function()
	local good, idle = LastDancer.new(), LastDancer.new()
	for _, note in Chart.Notes do
		LastDancer.Tap(Chart, good, note.Lane, note.T)
	end
	LastDancer.Expire(Chart, idle, LastDancer.DURATION)
	expectEqual(good.Miss, 0)
	expectEqual(good.Perfect, #Chart.Notes)
	expectEqual(idle.Miss, #Chart.Notes)
	local cut = LastDancer.PickCuts({
		{ Key = "good", Groove = good.Groove, Score = good.Score, Order = 1 },
		{ Key = "idle", Groove = idle.Groove, Score = idle.Score, Order = 2 },
	}, 1)
	expectEqual(cut[1], "idle")
end)

return nil
