--!strict
-- The rules of Last Dancer as plain math (owner: "Let's make it", after the pitch "Last Dancer Standing":
-- a rhythm dance-off where the lowest dancers fall through the floor at the end of every phrase of the
-- song). The server judges every tap with it, the client draws the same windows and the bots' brain uses
-- the same chart, so all three always agree.
-- Leaf module: no requires, no Roblox APIs, so it can be unit tested under Lune.
--
-- The song and the chart. The round's own song (tools/music/songs/LastDancer.py) is 120 bpm with its
-- drop on GO, and the chart (LastDancerChart.luau, written from the same file by
-- tools/music/lastdancer_chart.py) lists every note as seconds after GO and a lane 1-4: each note is a
-- note the song's lead plays, so tapping on the beat plays along. Everyone gets the same chart.
--
-- Judging. A tap in lane L at `rel` seconds after GO hits the nearest note still waiting in lane L within
-- WINDOW.Ok of its time: Perfect, Great or Ok by how close. A tap that hits nothing is a stray; a note
-- nobody hit by WINDOW.Ok after its time is a miss. The server judges a tap by when the player's device
-- says it was made (PressTime), so a laggy connection doesn't cost anyone a hit.
--
-- Groove (what the cuts go by). Every note's outcome and every stray pulls a dancer's groove, a moving
-- average between 0 and 1, towards its value: a Perfect towards 1, a miss or stray towards 0. It is a
-- recent-form meter rather than a running total: it can't pile up past the top (so a good dancer's
-- groove still tells them apart from a great one's), a bad stretch can be danced out of, a dancer who
-- stops dancing falls to nothing in a few seconds, and mashing all four pads (every stray pulls down as
-- hard as a quarter of a hit lifts) never pays.
--
-- The cuts. The song's phrases are 4 bars (PHRASE seconds). At the end of phrases FIRST_CUT to LAST_CUT
-- the dancers with the lowest groove fall through the floor, as many as it takes to leave FINALISTS
-- dancers for the last phrase (the final duel), spread evenly over the cuts: 12 dancers lose 2, 1, 2, 2, 1
-- and 2. At the buzzer the highest groove wins.

local LastDancer = {}

LastDancer.LANES = 4
LastDancer.BPM = 120 -- the song's tempo (tools/music/songs/LastDancer.py)
LastDancer.BEAT = 60 / LastDancer.BPM
LastDancer.PHRASE = LastDancer.BEAT * 16 -- 4 bars
LastDancer.PHRASES = 8
LastDancer.DURATION = LastDancer.PHRASE * LastDancer.PHRASES -- the round's length, GO to buzzer
LastDancer.FIRST_CUT = 2 -- the first phrase that ends with a cut
LastDancer.LAST_CUT = 7
LastDancer.FINALISTS = 2 -- left for the last phrase

-- How far from a note's time (seconds) a tap still counts.
LastDancer.WINDOW = { Perfect = 0.065, Great = 0.115, Ok = 0.17 }

-- Groove: what each outcome pulls the moving average towards, and how hard.
LastDancer.GROOVE_START = 0.6
LastDancer.FORM = { Perfect = 1.0, Great = 0.8, Ok = 0.5, Miss = 0.0, Stray = 0.0 }
LastDancer.PULL = { Perfect = 0.1, Great = 0.1, Ok = 0.1, Miss = 0.12, Stray = 0.05 }

-- Points (for ties and the results), and the bonus per note of a combo (capped).
LastDancer.POINTS = { Perfect = 300, Great = 200, Ok = 100 }
LastDancer.COMBO_BONUS = 10
LastDancer.COMBO_CAP = 30

-- How far a device's sync setting may shift its taps (seconds): the audio reaching a player later than
-- the clock says (Bluetooth speakers), bounded so a made-up time can't reach far.
LastDancer.SYNC_MAX = 0.3
LastDancer.REACH = 0.1 -- like Buzzer.REACH
LastDancer.WARMUP = 0.5 -- taps this long before the first note (and its window) are free: trying the pads

export type Note = { T: number, Lane: number }
export type Chart = { Notes: { Note } }

export type Dancer = {
	Groove: number, -- 0..1
	Score: number,
	Combo: number,
	BestCombo: number,
	Perfect: number,
	Great: number,
	Ok: number,
	Miss: number,
	Stray: number,
	Next: number, -- the first note not yet hit or missed
	Done: { [number]: boolean }, -- notes hit or missed
}

export type Outcome = { Kind: string, Index: number?, Offset: number?, Points: number }

function LastDancer.new(): Dancer
	return {
		Groove = LastDancer.GROOVE_START,
		Score = 0,
		Combo = 0,
		BestCombo = 0,
		Perfect = 0,
		Great = 0,
		Ok = 0,
		Miss = 0,
		Stray = 0,
		Next = 1,
		Done = {},
	}
end

local function pull(dancer: Dancer, kind: string)
	local weight = LastDancer.PULL[kind]
	dancer.Groove += (LastDancer.FORM[kind] - dancer.Groove) * weight
end

local function advance(chart: Chart, dancer: Dancer)
	local notes = chart.Notes
	while dancer.Done[dancer.Next] do
		dancer.Next += 1
	end
	if dancer.Next > #notes then
		dancer.Next = #notes + 1
	end
end

-- The kind of hit a tap `offset` seconds from a note's time makes (nil: too far).
function LastDancer.Judge(offset: number): string?
	local distance = math.abs(offset)
	if distance <= LastDancer.WINDOW.Perfect then
		return "Perfect"
	elseif distance <= LastDancer.WINDOW.Great then
		return "Great"
	elseif distance <= LastDancer.WINDOW.Ok then
		return "Ok"
	end
	return nil
end

-- A tap in `lane` at `rel` seconds after GO. Returns what it did: a hit ("Perfect" | "Great" | "Ok", with
-- the note's index, the offset (tap - note, seconds) and the points) or a "Stray" that hit nothing.
-- Anything that isn't a lane 1-4 at a real time is a stray too.
function LastDancer.Tap(chart: Chart, dancer: Dancer, lane: any, rel: any): Outcome
	local notes = chart.Notes
	local valid = type(lane) == "number"
		and lane % 1 == 0
		and lane >= 1
		and lane <= LastDancer.LANES
		and type(rel) == "number"
		and rel == rel
		and math.abs(rel) < 1e6
	local bestIndex, bestOffset = nil, math.huge
	if valid then
		local limit = rel + LastDancer.WINDOW.Ok
		local index = dancer.Next
		while index <= #notes and notes[index].T <= limit do
			local note = notes[index]
			if note.Lane == lane and not dancer.Done[index] then
				local offset = rel - note.T
				if math.abs(offset) <= LastDancer.WINDOW.Ok and math.abs(offset) < math.abs(bestOffset) then
					bestIndex, bestOffset = index, offset
				end
			end
			index += 1
		end
	end
	if not bestIndex then
		dancer.Stray += 1
		dancer.Combo = 0
		pull(dancer, "Stray")
		return { Kind = "Stray", Points = 0 }
	end
	local kind = LastDancer.Judge(bestOffset) :: string
	dancer.Done[bestIndex] = true
	dancer.Combo += 1
	dancer.BestCombo = math.max(dancer.BestCombo, dancer.Combo)
	local points = LastDancer.POINTS[kind] + LastDancer.COMBO_BONUS * math.min(dancer.Combo, LastDancer.COMBO_CAP)
	dancer.Score += points
	if kind == "Perfect" then
		dancer.Perfect += 1
	elseif kind == "Great" then
		dancer.Great += 1
	else
		dancer.Ok += 1
	end
	pull(dancer, kind)
	advance(chart, dancer)
	return { Kind = kind, Index = bestIndex, Offset = bestOffset, Points = points }
end

-- Marks every note nobody hit by WINDOW.Ok after its time (`rel` is the time to judge by: the server
-- passes the clock less the dancer's lag, so a tap still on its way isn't missed). Returns the misses'
-- indices, oldest first.
function LastDancer.Expire(chart: Chart, dancer: Dancer, rel: number): { number }
	local missed = {}
	local notes = chart.Notes
	local index = dancer.Next
	while index <= #notes and notes[index].T + LastDancer.WINDOW.Ok < rel do
		if not dancer.Done[index] then
			dancer.Done[index] = true
			dancer.Miss += 1
			dancer.Combo = 0
			pull(dancer, "Miss")
			table.insert(missed, index)
		end
		index += 1
	end
	advance(chart, dancer)
	return missed
end

-- Whether a tap `rel` seconds after GO comes before the chart's first note and its warm-up: such a tap is
-- ignored (not a stray), so nobody is punished for trying the pads while the count-in plays.
function LastDancer.InWarmup(chart: Chart, rel: number): boolean
	local first = chart.Notes[1]
	return first ~= nil and rel < first.T - LastDancer.WINDOW.Ok - LastDancer.WARMUP
end

-- When a tap that reached the server at `now` was made: by the player's own clock (`sentAt`, synced to
-- the server's, less their sync setting), but never after it arrived and never further back than half
-- their round trip (`lag`) plus REACH plus the most a sync setting may shift it. Without a time (bots,
-- which have no lag) it is `now`.
function LastDancer.PressTime(sentAt: any, now: number, lag: number): number
	local oneWay = math.max(0, lag) / 2
	if type(sentAt) == "number" and sentAt == sentAt then
		return math.clamp(sentAt, now - oneWay - LastDancer.REACH - LastDancer.SYNC_MAX, now)
	end
	return now - oneWay
end

-- Phrases and cuts --------------------------------------------------------------------------------

-- The phrase (1-based) `rel` seconds after GO falls in.
function LastDancer.PhraseAt(rel: number): number
	return math.floor(rel / LastDancer.PHRASE) + 1
end

-- When the cut at the end of `phrase` happens (seconds after GO), nil if that phrase doesn't end with one.
function LastDancer.CutTime(phrase: number): number?
	if phrase < LastDancer.FIRST_CUT or phrase > LastDancer.LAST_CUT then
		return nil
	end
	return phrase * LastDancer.PHRASE
end

-- How many dancers should be left on the floor after the cut at the end of `phrase`, when `start` danced:
-- the surplus over FINALISTS is cut evenly across the cuts (each cut's cumulative share, rounded to the
-- nearest dancer): 12 dancers go 10, 9, 7, 5, 4, 2 and 3 dancers lose their third in the middle cut.
-- Always FINALISTS at the last cut, so the final duel is between two.
function LastDancer.Target(start: number, phrase: number): number
	local cuts = LastDancer.LAST_CUT - LastDancer.FIRST_CUT + 1
	local done = math.clamp(phrase - LastDancer.FIRST_CUT + 1, 0, cuts)
	local surplus = math.max(0, start - LastDancer.FINALISTS)
	return start - math.floor(surplus * done / cuts + 0.5)
end

-- How many of `alive` dancers fall at the end of `phrase` (`start` is how many danced at GO): enough to
-- be down to the target, none if people have already left (or fallen) to reach it.
function LastDancer.CutCount(alive: number, phrase: number, start: number): number
	if phrase < LastDancer.FIRST_CUT or phrase > LastDancer.LAST_CUT then
		return 0
	end
	return math.max(0, alive - LastDancer.Target(start, phrase))
end

export type Entry = { Key: any, Groove: number, Score: number, Order: number }

-- The `count` dancers who fall: the lowest groove, then the fewest points, then the higher Order (a
-- number the round draws once for each dancer, so a dead heat is settled by luck that never changes).
function LastDancer.PickCuts(entries: { Entry }, count: number): { any }
	local sorted = table.clone(entries)
	table.sort(sorted, function(a, b)
		if a.Groove ~= b.Groove then
			return a.Groove < b.Groove
		end
		if a.Score ~= b.Score then
			return a.Score < b.Score
		end
		return a.Order > b.Order
	end)
	local out = {}
	for index = 1, math.min(count, #sorted) do
		out[index] = sorted[index].Key
	end
	return out
end

-- Whether `a` finishes ahead of `b` among the dancers left at the buzzer.
function LastDancer.Ahead(a: Entry, b: Entry): boolean
	if a.Groove ~= b.Groove then
		return a.Groove > b.Groove
	end
	if a.Score ~= b.Score then
		return a.Score > b.Score
	end
	return a.Order < b.Order
end

-- Where `alive` dancers would be cut, from a client's point of view: the 1-based place of `groove` among
-- `grooves` (1 is the best), for the rank readout and the danger warning.
function LastDancer.Place(grooves: { number }, groove: number): number
	local place = 1
	for _, other in grooves do
		if other > groove then
			place += 1
		end
	end
	return place
end

-- The time of beat number `beat` (0 is GO), in seconds after GO.
function LastDancer.BeatTime(beat: number): number
	return beat * LastDancer.BEAT
end

-- Whether the chart is well formed: sorted, lanes 1-4, no two notes closer than `gap` seconds, and none
-- later than the round. Returns nil when fine, else what is wrong (for the tests).
function LastDancer.Check(chart: Chart, gap: number): string?
	local previous = -math.huge
	for index, note in chart.Notes do
		if note.Lane % 1 ~= 0 or note.Lane < 1 or note.Lane > LastDancer.LANES then
			return `note {index}: lane {note.Lane}`
		end
		if note.T < previous then
			return `note {index}: out of order`
		end
		if note.T - previous < gap - 1e-9 then
			return `note {index}: only {note.T - previous}s after the one before`
		end
		if note.T < 0 or note.T > LastDancer.DURATION - LastDancer.WINDOW.Ok then
			return `note {index}: at {note.T}s is outside the round`
		end
		previous = note.T
	end
	return nil
end

return LastDancer
