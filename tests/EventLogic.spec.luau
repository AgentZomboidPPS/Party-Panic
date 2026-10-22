-- The limited-time events and double coins weekends (Logic/EventLogic, Shared/Events): the schedule,
-- the weekend check, the countdown, candy, the reward track and the pumpkin hunt, and that every
-- event reward is a cosmetic nobody can buy.
local fs = require("@lune/fs")

local TestKit = require("./TestKit")
local EventLogic = require("../src/shared/Logic/EventLogic")
local Events = require("../src/shared/Events")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

local DAY = 86400
-- Midnight UTC on these days (Unix seconds).
local THU_OCT_22 = 1792627200 -- 2026-10-22, a Thursday: the HALLOWEEN PARTY starts
local SAT_OCT_24 = 1792800000
local SUN_OCT_25 = 1792886400
local MON_OCT_26 = 1792972800
local SAT_OCT_31 = 1793404800 -- Halloween
local MON_NOV_2 = 1793577600 -- the party is over

local halloween = Events.Get("Halloween2026") :: Events.Event

test("ParseUtc reads the schedule's dates (UTC), with or without a time", function()
	expectEqual(EventLogic.ParseUtc("1970-01-01"), 0)
	expectEqual(EventLogic.ParseUtc("2026-10-22 00:00"), THU_OCT_22)
	expectEqual(EventLogic.ParseUtc("2026-11-02 00:00 UTC"), MON_NOV_2)
	expectEqual(EventLogic.ParseUtc("2026-11-02T00:00"), MON_NOV_2)
	expectEqual(EventLogic.ParseUtc("  2026-10-31 12:30 "), SAT_OCT_31 + 12 * 3600 + 30 * 60)
	expectEqual(EventLogic.ParseUtc("2024-02-29"), 1709164800, "a leap day")
	expectEqual(EventLogic.ParseUtc("2000-03-01"), 951868800)
end)

test("ParseUtc refuses what isn't a date", function()
	for _, text in
		{ "", "soon", "2026-13-01", "2026-02-30", "2025-02-29", "2026-10-22 24:00", "2026-10-22 10:60", "22/10/2026" }
	do
		expectEqual(EventLogic.ParseUtc(text), nil, text)
	end
end)

test("weekdays in UTC, and when a weekend ends", function()
	expectEqual(EventLogic.Weekday(0), 4, "1970-01-01 was a Thursday")
	expectEqual(EventLogic.Weekday(THU_OCT_22), 4)
	expectEqual(EventLogic.Weekday(SAT_OCT_24), 6)
	expectEqual(EventLogic.Weekday(SUN_OCT_25), 0)
	expectEqual(EventLogic.Weekday(MON_OCT_26), 1)
	expectEqual(EventLogic.WeekendEndsAt(SAT_OCT_24), MON_OCT_26, "Saturday's first second")
	expectEqual(EventLogic.WeekendEndsAt(SAT_OCT_24 + 12 * 3600), MON_OCT_26)
	expectEqual(EventLogic.WeekendEndsAt(MON_OCT_26 - 1), MON_OCT_26, "Sunday's last second")
	expectEqual(EventLogic.WeekendEndsAt(SAT_OCT_24 - 1), nil, "Friday's last second")
	expectEqual(EventLogic.WeekendEndsAt(MON_OCT_26), nil, "Monday")
	expectEqual(EventLogic.WeekendEndsAt(THU_OCT_22 + 5000), nil)
end)

test("the HALLOWEEN PARTY is on from 22 October until 2 November 00:00 UTC", function()
	local list = Events.List
	expectEqual(EventLogic.Active(list, THU_OCT_22 - 1), nil, "before it starts")
	expectEqual((EventLogic.Active(list, THU_OCT_22) :: any).Id, "Halloween2026")
	local event, endsAt = EventLogic.Active(list, MON_NOV_2 - 1)
	expectEqual((event :: any).Id, "Halloween2026", "the last second")
	expectEqual(endsAt, MON_NOV_2)
	expectEqual(EventLogic.Active(list, MON_NOV_2), nil, "over at midnight")
	-- A date that isn't one never switches an event on.
	expectEqual(EventLogic.Active({ { Id = "Typo", Starts = "2026-1O-01", Ends = "2026-12-01" } }, MON_NOV_2), nil)
end)

test("State: the event, its end, and double coins weekends with or without it", function()
	local list = Events.List
	expectEqual(
		EventLogic.State(list, true, THU_OCT_22 + 3600),
		{ Id = "Halloween2026", Name = "HALLOWEEN PARTY", EndsAt = MON_NOV_2, DoubleCoins = false, DoubleEndsAt = 0 }
	)
	expectEqual(EventLogic.State(list, true, SAT_OCT_31 + 3600), {
		Id = "Halloween2026",
		Name = "HALLOWEEN PARTY",
		EndsAt = MON_NOV_2,
		DoubleCoins = true,
		DoubleEndsAt = MON_NOV_2,
	})
	-- After the party: a weekend on its own, and nothing on a weekday.
	local saturday = MON_NOV_2 + 5 * DAY
	expectEqual(
		EventLogic.State(list, true, saturday),
		{ Id = "", Name = "", EndsAt = 0, DoubleCoins = true, DoubleEndsAt = saturday + 2 * DAY }
	)
	expectEqual(EventLogic.State(list, true, MON_NOV_2 + DAY), nil)
	expectEqual(EventLogic.State(list, false, saturday), nil, "weekends switched off")
	expectEqual((EventLogic.State(list, false, SAT_OCT_24) :: any).DoubleCoins, false)
end)

test("the countdown is short: days, then hours, then minutes", function()
	expectEqual(EventLogic.Countdown(9 * DAY + 23 * 3600), "9D")
	expectEqual(EventLogic.Countdown(2 * DAY), "2D")
	expectEqual(EventLogic.Countdown(DAY + 4 * 3600 + 59), "1D 4H")
	expectEqual(EventLogic.Countdown(DAY), "1D 0H")
	expectEqual(EventLogic.Countdown(23 * 3600 + 59 * 60 + 30), "23H 59M")
	expectEqual(EventLogic.Countdown(3600), "1H 0M")
	expectEqual(EventLogic.Countdown(3599), "59M")
	expectEqual(EventLogic.Countdown(30), "1M")
	expectEqual(EventLogic.Countdown(0), "0M")
	expectEqual(EventLogic.Countdown(-50), "0M")
end)

test("candy from a round: some for playing, more for the top half, more for a win", function()
	local rules = halloween.Candy
	expectEqual(EventLogic.RoundCandy(1, 8, rules), rules.Played + rules.TopHalf + rules.Win)
	expectEqual(EventLogic.RoundCandy(4, 8, rules), rules.Played + rules.TopHalf)
	expectEqual(EventLogic.RoundCandy(5, 8, rules), rules.Played)
	expectEqual(EventLogic.RoundCandy(12, 12, rules), rules.Played)
	expectEqual(EventLogic.RoundCandy(2, 3, rules), rules.Played + rules.TopHalf, "the same top half as the coins")
	expectEqual(EventLogic.RoundCandy(1, 1, rules), rules.Played + rules.TopHalf + rules.Win, "a lone tester")
	expectEqual(EventLogic.RoundCandy(1, 8, rules), 4, "small amounts")
end)

test("a saved progress is made whole without losing anything", function()
	local fresh = EventLogic.Progress({})
	expectEqual(fresh, { Candy = 0, Claimed = {}, Found = { Day = 0, Spots = {} } })
	local saved = { Candy = 31, Claimed = { Emote_CandyToss = true }, Found = { Day = 20750, Spots = { 3 } } }
	expectEqual(
		EventLogic.Progress(saved),
		{ Candy = 31, Claimed = { Emote_CandyToss = true }, Found = { Day = 20750, Spots = { 3 } } }
	)
	local broken = EventLogic.Progress({ Candy = -4, Claimed = "x", Found = { Day = "today" } } :: any)
	expectEqual(broken, { Candy = 0, Claimed = {}, Found = { Day = 0, Spots = {} } })
	expectEqual(EventLogic.Progress({ Candy = 0 / 0 }).Candy, 0, "NaN")
end)

test("the reward track: claim each step once its candy is reached", function()
	local track = halloween.Track
	local mine = EventLogic.Progress({ Candy = 9 })
	expectEqual({ EventLogic.CanClaim(mine, track, track[1].Reward) }, { false, "candy" })
	expectEqual({ EventLogic.CanClaim(mine, track, "Trail_Rainbow") }, { false, "unknown" })
	expectEqual(EventLogic.Claimable(mine, track), {})
	expectEqual((EventLogic.NextStep(mine, track) :: any).Reward, track[1].Reward)
	mine.Candy = track[2].Candy
	expectEqual(EventLogic.Claimable(mine, track), { track[1].Reward, track[2].Reward })
	expectEqual({ EventLogic.Claim(mine, track, track[2].Reward) }, { true, nil })
	expectEqual({ EventLogic.Claim(mine, track, track[2].Reward) }, { false, "claimed" }, "never twice")
	expectEqual(EventLogic.Claimable(mine, track), { track[1].Reward })
	expectEqual((EventLogic.NextStep(mine, track) :: any).Reward, track[3].Reward)
	expectEqual(EventLogic.Complete(mine, track), false)
	mine.Candy = track[#track].Candy
	expectTrue(EventLogic.Complete(mine, track), "the last step is the whole track")
	expectEqual(EventLogic.NextStep(mine, track), nil)
	expectEqual(#EventLogic.Claimable(mine, track), #track - 1)
	local _, index = EventLogic.Step(track, track[3].Reward)
	expectEqual(index, 3)
end)

test("the hunt: a few spots a day, the same for everyone, moving every day", function()
	local spots, perDay = 8, halloween.Candy.PumpkinsPerDay
	local used = {}
	local changes = 0
	local previous = nil
	for day = 20748, 20748 + 59 do
		local today = EventLogic.HuntSpots(day, spots, perDay)
		expectEqual(#today, perDay)
		expectEqual(EventLogic.HuntSpots(day, spots, perDay), today, "the same all day")
		local seen = {}
		for _, spot in today do
			expectTrue(spot >= 1 and spot <= spots, `spot {spot} is a spot`)
			expectTrue(not seen[spot], "never twice the same spot on one day")
			seen[spot] = true
			used[spot] = true
		end
		if previous and table.concat(previous, ",") ~= table.concat(today, ",") then
			changes += 1
		end
		previous = today
	end
	for spot = 1, spots do
		expectTrue(used[spot], `spot {spot} gets a pumpkin some days`)
	end
	expectTrue(changes >= 55, `they move most days ({changes} of 59)`)
	expectEqual(#EventLogic.HuntSpots(1, 2, 3), 2, "no more pumpkins than spots")
end)

test("finding pumpkins: today's spots, once each, a fresh list the next day", function()
	local mine = EventLogic.Progress({})
	local today = { 2, 5, 7 }
	expectEqual(EventLogic.FindPumpkin(mine, 100, 3, today), false, "no pumpkin there today")
	expectEqual(EventLogic.FindPumpkin(mine, 100, 5, today), true)
	expectEqual(EventLogic.FindPumpkin(mine, 100, 5, today), false, "already found")
	expectEqual(EventLogic.FindPumpkin(mine, 100, 7, today), true)
	expectEqual(EventLogic.FoundToday(mine, 100), 2)
	expectTrue(EventLogic.HasFound(mine, 100, 5) and not EventLogic.HasFound(mine, 100, 2))
	expectEqual(EventLogic.FoundToday(mine, 101), 0, "a new day")
	expectEqual(EventLogic.FindPumpkin(mine, 101, 5, { 5, 1, 3 }), true, "the same spot again tomorrow")
	expectEqual(mine.Found, { Day = 101, Spots = { 5 } })
	expectEqual(EventLogic.HasFound(mine, 100, 5), false, "yesterday's list is gone")
end)

-- Each catalog entry's text (the top-level `{ ... },` blocks in Cosmetics.luau's list).
local cosmeticsSource = fs.readFile("src/shared/Cosmetics.luau")
local items = {}
for block in string.gmatch(cosmeticsSource, "\n\t{\n(.-)\n\t},") do
	local id = string.match(block, 'Id = "([%w_]+)"')
	if id then
		items[id] = block
	end
end

test("every event in the schedule reads right", function()
	expectTrue(#Events.List >= 1, "there's an event")
	for _, event in Events.List do
		local starts, ends = EventLogic.ParseUtc(event.Starts), EventLogic.ParseUtc(event.Ends)
		expectTrue(starts ~= nil and ends ~= nil, `{event.Id}'s dates read as dates`)
		expectTrue((starts :: number) < (ends :: number), `{event.Id} ends after it starts`)
		expectEqual(event.Name, string.upper(event.Name), "event names in capitals")
		expectEqual(event.Short, string.upper(event.Short))
		expectTrue(#event.Track >= 3, `{event.Id} has a track`)
		for index, step in event.Track do
			expectTrue(step.Candy > 0 and step.Candy <= 150, `{step.Reward}: a reachable amount of candy`)
			if index > 1 then
				expectTrue(step.Candy > event.Track[index - 1].Candy, "the steps go up")
			end
		end
		for _, key in { "Played", "TopHalf", "Win", "Pumpkin", "PumpkinsPerDay" } do
			local value = (event.Candy :: any)[key]
			expectTrue(type(value) == "number" and value >= 1 and value <= 5, `candy {key} stays small`)
		end
	end
	expectEqual(Events.Get("Halloween2026"), halloween)
	expectEqual(Events.Get("Nope"), nil)
	expectEqual(halloween.Ends, "2026-11-02 00:00", "the owner's date")
end)

test("event rewards are free cosmetics nobody can buy, each on its event's track", function()
	local onTrack = {}
	for _, event in Events.List do
		for _, step in event.Track do
			local block = items[step.Reward]
			expectTrue(block ~= nil, `{step.Reward} is in Cosmetics.luau`)
			expectTrue(
				string.find(block, `Event = "{event.Id}"`, 1, true) ~= nil,
				`{step.Reward} is marked as {event.Id}'s`
			)
			onTrack[step.Reward] = true
		end
	end
	local count = 0
	for id, block in items do
		if string.find(block, "Event =", 1, true) then
			count += 1
			expectTrue(onTrack[id], `{id} is an event reward on no track`)
			for _, field in { "Price =", "UnlockLevel =", "UnlockStat =", "Default =", "Vip =" } do
				expectTrue(not string.find(block, field, 1, true), `{id} is an event reward but has {field}`)
			end
			-- The shop's card names the event it came from (its Label).
			local event = Events.Get(string.match(block, 'Event = "([%w_]+)"'))
			expectTrue(event ~= nil and event.Label == string.upper(event.Label), `{id} names an event with a label`)
		end
	end
	expectEqual(count, #halloween.Track)
end)
