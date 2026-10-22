--!strict
-- The rules of the limited-time events (Halloween first) and their double coins weekends (owner,
-- asked what keeps players coming back, then: "Can you work on all of that? this wont mess with what
-- the other workers are working on right?"; on double coins after Halloween: "NO"): which event is
-- on at a given moment, when one of its double coins weekends ends, how much candy a round pays,
-- claiming a step of the reward track, and the pumpkins hidden in the lobby each day. Shared/Events has the schedule and the tracks; Services/EventService
-- applies these rules, and Controllers/EventController shows the same numbers.
-- Times are Unix seconds (UTC): os.time() on the server, workspace:GetServerTimeNow() on a device.
-- Leaf module: no requires, no Roblox APIs (Lune runs the tests: tests/EventLogic.spec.luau).

local EventLogic = {}

local DAY = 86400

-- One step of an event's reward track: this much candy unlocks this cosmetic.
export type Step = { Candy: number, Reward: string }

-- What an event pays in candy (Shared/Events).
export type CandyRules = {
	Played: number,
	TopHalf: number,
	Win: number,
	Pumpkin: number,
	PumpkinsPerDay: number,
}

-- A player's progress in one event, as saved in profile.Events[<event id>].
export type Progress = {
	Candy: number,
	Claimed: { [string]: boolean }, -- reward id -> claimed
	Found: { Day: number, Spots: { number } }, -- the hidden pumpkins found on that UTC day
}

-- What GameState's "Event" attribute holds (JSON), and what the lobby chip counts down from.
export type State = {
	Id: string, -- the event on now
	Name: string,
	EndsAt: number, -- when the event ends
	DoubleCoins: boolean, -- one of the event's double coins weekends
	DoubleEndsAt: number, -- when that weekend's double coins end (0 when they aren't on)
}

-- Dates ------------------------------------------------------------------------------------------

-- Days since 1970-01-01 of a calendar date (Howard Hinnant's days_from_civil).
local function daysFromCivil(year: number, month: number, day: number): number
	local y = if month <= 2 then year - 1 else year
	local era = (if y >= 0 then y else y - 399) // 400
	local yearOfEra = y - era * 400
	local dayOfYear = (153 * (if month > 2 then month - 3 else month + 9) + 2) // 5 + day - 1
	local dayOfEra = yearOfEra * 365 + yearOfEra // 4 - yearOfEra // 100 + dayOfYear
	return era * 146097 + dayOfEra - 719468
end

local DAYS_IN_MONTH = { 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

-- "2026-11-02 00:00" (UTC; the time can be left out, and a trailing "UTC" is fine) as Unix seconds,
-- or nil when it isn't a real date and time.
function EventLogic.ParseUtc(text: string): number?
	local trimmed = string.match(text, "^%s*(.-)%s*$") :: string
	trimmed = string.gsub(trimmed, "%s*[Uu][Tt][Cc]$", "")
	local year, month, day, hour, minute = string.match(trimmed, "^(%d%d%d%d)%-(%d%d?)%-(%d%d?)[ T](%d%d?):(%d%d)$")
	if not year then
		year, month, day = string.match(trimmed, "^(%d%d%d%d)%-(%d%d?)%-(%d%d?)$")
		hour, minute = "0", "0"
	end
	if not year then
		return nil
	end
	local y, m, d = tonumber(year) :: number, tonumber(month) :: number, tonumber(day) :: number
	local h, n = tonumber(hour) :: number, tonumber(minute) :: number
	if m < 1 or m > 12 or d < 1 or d > DAYS_IN_MONTH[m] or h > 23 or n > 59 then
		return nil
	end
	local leap = (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0
	if m == 2 and d == 29 and not leap then
		return nil
	end
	return daysFromCivil(y, m, d) * DAY + h * 3600 + n * 60
end

-- Whole UTC days since the Unix epoch (the same numbering as DailyLogic.DayNumber).
function EventLogic.DayNumber(unixTime: number): number
	return math.floor(unixTime / DAY)
end

-- Day of the week in UTC: 0 Sunday, 1 Monday ... 6 Saturday (the epoch was a Thursday).
function EventLogic.Weekday(unixTime: number): number
	return (EventLogic.DayNumber(unixTime) + 4) % 7
end

-- When the weekend `unixTime` falls in ends (the Monday 00:00 UTC after it), or nil on a weekday.
function EventLogic.WeekendEndsAt(unixTime: number): number?
	local weekday = EventLogic.Weekday(unixTime)
	if weekday ~= 6 and weekday ~= 0 then
		return nil
	end
	local day = EventLogic.DayNumber(unixTime)
	return (day + (if weekday == 6 then 2 else 1)) * DAY
end

-- The schedule ---------------------------------------------------------------------------------

-- The event on at `unixTime` (its Starts <= time < its Ends), the first one listed if two overlap.
-- An event with a date that doesn't read as one is never on.
function EventLogic.Active<T>(events: { T }, unixTime: number): (T?, number?)
	for _, event in events do
		local entry = event :: any
		local starts = EventLogic.ParseUtc(entry.Starts or "")
		local ends = EventLogic.ParseUtc(entry.Ends or "")
		if starts and ends and starts <= unixTime and unixTime < ends then
			return event, ends
		end
	end
	return nil, nil
end

-- What's on at `unixTime`: the event, and whether it's one of its double coins weekends (a Saturday
-- or Sunday in UTC while an event with DoubleCoinsWeekends is on; the double coins stop when the
-- weekend or the event ends, whichever comes first). Nil when no event is on: double coins never
-- come on their own.
function EventLogic.State(events: { any }, unixTime: number): State?
	local event, endsAt = EventLogic.Active(events, unixTime)
	if not event or not endsAt then
		return nil
	end
	local weekendEnds = if event.DoubleCoinsWeekends == true then EventLogic.WeekendEndsAt(unixTime) else nil
	local doubleEnds = if weekendEnds then math.min(weekendEnds, endsAt) else nil
	return {
		Id = event.Id,
		Name = event.Name,
		EndsAt = endsAt,
		DoubleCoins = doubleEnds ~= nil,
		DoubleEndsAt = doubleEnds or 0,
	}
end

-- Time left, short, for the lobby chip and the event screen: "9D", "1D 4H", "4H 12M", "42M".
function EventLogic.Countdown(seconds: number): string
	if seconds >= 2 * DAY then
		return `{math.floor(seconds / DAY)}D`
	elseif seconds >= DAY then
		return `1D {math.floor((seconds - DAY) / 3600)}H`
	elseif seconds >= 3600 then
		return `{math.floor(seconds / 3600)}H {math.floor((seconds % 3600) / 60)}M`
	end
	-- The last hour counts minutes up (half a minute left still says 1M, never 60M).
	local minutes = math.ceil(seconds / 60)
	return if minutes > 0 then `{math.min(59, minutes)}M` else "0M"
end

-- Candy --------------------------------------------------------------------------------------------

-- A place counts as "top half" the way the round's coins count it (Logic/RewardLogic).
local function isTopHalf(place: number, playerCount: number): boolean
	return place <= math.max(1, math.ceil(playerCount / 2))
end

-- The candy a round pays for this place: some for playing, more for the top half, more for a win.
function EventLogic.RoundCandy(place: number, playerCount: number, rules: CandyRules): number
	local candy = rules.Played
	if isTopHalf(place, playerCount) then
		candy += rules.TopHalf
	end
	if place == 1 then
		candy += rules.Win
	end
	return candy
end

-- A player's saved progress in an event, made whole (a new player's, or one saved by an older
-- version): `saved` is the table in profile.Events, which this fills in place.
function EventLogic.Progress(saved: { [string]: any }): Progress
	if type(saved.Candy) ~= "number" or saved.Candy ~= saved.Candy or saved.Candy < 0 then
		saved.Candy = 0
	end
	if type(saved.Claimed) ~= "table" then
		saved.Claimed = {}
	end
	if type(saved.Found) ~= "table" or type(saved.Found.Day) ~= "number" or type(saved.Found.Spots) ~= "table" then
		saved.Found = { Day = 0, Spots = {} }
	end
	return saved :: any
end

-- The reward track -------------------------------------------------------------------------------

-- The step that unlocks `rewardId`, and its place on the track.
function EventLogic.Step(track: { Step }, rewardId: string): (Step?, number?)
	for index, step in track do
		if step.Reward == rewardId then
			return step, index
		end
	end
	return nil, nil
end

-- Whether `rewardId` can be claimed now: (true) or (false, "unknown" | "claimed" | "candy").
function EventLogic.CanClaim(progress: Progress, track: { Step }, rewardId: string): (boolean, string?)
	local step = EventLogic.Step(track, rewardId)
	if not step then
		return false, "unknown"
	elseif progress.Claimed[rewardId] then
		return false, "claimed"
	elseif progress.Candy < step.Candy then
		return false, "candy"
	end
	return true, nil
end

-- Claims `rewardId` (marks it claimed in `progress`). Same answers as CanClaim.
function EventLogic.Claim(progress: Progress, track: { Step }, rewardId: string): (boolean, string?)
	local ok, reason = EventLogic.CanClaim(progress, track, rewardId)
	if ok then
		progress.Claimed[rewardId] = true
	end
	return ok, reason
end

-- Every reward the candy has reached that isn't claimed yet, in track order.
function EventLogic.Claimable(progress: Progress, track: { Step }): { string }
	local list = {}
	for _, step in track do
		if progress.Candy >= step.Candy and not progress.Claimed[step.Reward] then
			table.insert(list, step.Reward)
		end
	end
	return list
end

-- The first step the candy hasn't reached (nil once it has reached them all).
function EventLogic.NextStep(progress: Progress, track: { Step }): Step?
	for _, step in track do
		if progress.Candy < step.Candy then
			return step
		end
	end
	return nil
end

-- True once the candy reaches the track's last step: the whole track is theirs (the event's medal).
function EventLogic.Complete(progress: Progress, track: { Step }): boolean
	local last = track[#track]
	return last ~= nil and progress.Candy >= last.Candy
end

-- The pumpkin hunt -------------------------------------------------------------------------------

-- The spots (1..spotCount) where `perDay` pumpkins hide on UTC day `day`: the same for everyone all
-- day, different the next day, never twice the same spot on one day.
function EventLogic.HuntSpots(day: number, spotCount: number, perDay: number): { number }
	local spots = {}
	for index = 1, spotCount do
		spots[index] = index
	end
	-- A shuffle from a little generator seeded by the day (an LCG well inside double precision).
	local state = (day * 7919 + 104729) % 2147483647
	local function nextNumber(): number
		state = (state * 48271) % 2147483647
		return state
	end
	for index = spotCount, 2, -1 do
		local other = nextNumber() % index + 1
		spots[index], spots[other] = spots[other], spots[index]
	end
	local picked = {}
	for index = 1, math.min(perDay, spotCount) do
		table.insert(picked, spots[index])
	end
	return picked
end

-- How many of today's pumpkins this player has found.
function EventLogic.FoundToday(progress: Progress, day: number): number
	return if progress.Found.Day == day then #progress.Found.Spots else 0
end

-- Whether this player has found the pumpkin at `spot` today.
function EventLogic.HasFound(progress: Progress, day: number, spot: number): boolean
	return progress.Found.Day == day and table.find(progress.Found.Spots, spot) ~= nil
end

-- Finds the pumpkin at `spot` on `day` (`today`: the day's spots, HuntSpots). Marks it in
-- `progress` and returns true the first time; false for a spot with no pumpkin today or one found
-- already. A new day starts a fresh list.
function EventLogic.FindPumpkin(progress: Progress, day: number, spot: number, today: { number }): boolean
	if not table.find(today, spot) then
		return false
	end
	if progress.Found.Day ~= day then
		progress.Found = { Day = day, Spots = {} }
	end
	if table.find(progress.Found.Spots, spot) then
		return false
	end
	table.insert(progress.Found.Spots, spot)
	return true
end

return EventLogic
