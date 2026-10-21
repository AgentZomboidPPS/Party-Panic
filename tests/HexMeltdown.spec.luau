-- Checks Hex Meltdown's shared rules (src/shared/Logic/HexMeltdown.luau): the sink schedule, how the
-- round's end calls a call off, and that a stomp is judged on the screen that saw it.
local TestKit = require("./TestKit")
local Rules = require("../src/shared/Logic/HexMeltdown")
local Vector3 = (require("@lune/roblox") :: any).Vector3

local test, expectTrue, expectEqual = TestKit.test, TestKit.expectTrue, TestKit.expectEqual

local function near(a: number, b: number, tolerance: number, message: string)
	expectTrue(math.abs(a - b) <= tolerance, `{message}: {a} vs {b}`)
end

-- A mid-round call: warned at 100, sinking from 102 (down at 102.7), rising from 104.7 (up at 105.4).
local function call(stopAt: number?)
	return { WarnAt = 100, SinkAt = 102, RiseAt = 104.7, Move = 0.7, Depth = 26, StopAt = stopAt }
end

local function times(from: number, to: number): { number }
	local list = {}
	for index = 0, math.floor((to - from) / 0.01 + 0.5) do
		table.insert(list, from + index * 0.01)
	end
	return list
end

test("a call sinks the other hexes and raises them on schedule", function()
	local c = call()
	expectEqual(Rules.Sunk(c, 101), 0, "warning")
	expectEqual(Rules.Sunk(c, 102), 0, "sink starts")
	near(Rules.Sunk(c, 102.35), 13, 1e-9, "half way down")
	expectEqual(Rules.Sunk(c, 103), 26, "down")
	expectEqual(Rules.Sunk(c, 104.7), 26, "rise starts")
	near(Rules.Sunk(c, 105.05), 13, 1e-9, "half way up")
	near(Rules.Sunk(c, 105.4), 0, 1e-9, "up")
	expectEqual(Rules.Sunk(c, 110), 0, "after")
end)

test("time's up during the warning: nothing sinks, then or later", function()
	local c = call(101.2)
	for _, t in times(101.2, 110) do
		expectEqual(Rules.Sunk(c, t), 0, `t {t}`)
	end
end)

test("time's up as the hexes go down: they come straight back up from there", function()
	local stop = 102.3
	local c = call(stop)
	local at = Rules.Sunk(call(), stop)
	expectTrue(at > 1 and at < 26, `part way down at the buzzer ({at})`)
	expectEqual(Rules.Sunk(c, stop), at, "no jump at the buzzer")
	local last = at
	for _, t in times(stop, stop + 0.7) do
		local sunk = Rules.Sunk(c, t)
		expectTrue(sunk <= last + 1e-9, `never further down after the buzzer (t {t})`)
		last = sunk
	end
	near(Rules.Sunk(c, stop + 0.7), 0, 1e-9, "back up one move later")
	expectEqual(Rules.Sunk(c, 104), 0, "and stays up")
end)

test("time's up while they're down: up at once, not when the call would have raised them", function()
	local c = call(103.2)
	expectEqual(Rules.Sunk(c, 103.2), 26, "down at the buzzer")
	near(Rules.Sunk(c, 103.9), 0, 1e-9, "up before the call's own rise (104.7)")
end)

test("time's up after the call, or as it rises: nothing more goes down", function()
	local c = call(106)
	for _, t in times(105.4, 108) do
		near(Rules.Sunk(c, t), 0, 1e-9, `t {t}`)
	end
	local rising = call(105)
	local at = Rules.Sunk(call(), 105)
	expectEqual(Rules.Sunk(rising, 105), at, "no jump at the buzzer")
	expectTrue(Rules.Sunk(rising, 105.2) < at, "still rising")
	near(Rules.Sunk(rising, 105.7), 0, 1e-9, "up")
end)

-- Stomps -------------------------------------------------------------------------------------------

local NOW = 50
local STEP = 1 / 60

-- A trail (oldest first, ending at NOW, a sample a frame) of a root that is at `at(t)` at time t.
local function trail(at: (t: number) -> any): { Rules.Sample }
	local samples = {}
	for index = 24, 0, -1 do
		local t = NOW - index * STEP
		local position = at(t)
		local last = samples[#samples]
		table.insert(samples, {
			Time = t,
			Position = position,
			Falling = last ~= nil and position.Y < last.Position.Y - 0.05,
		})
	end
	return samples
end

local SEEN = 0.15 -- how late others are drawn on a screen
local PING = 0.06

local function standing(x: number): { Rules.Sample }
	return trail(function()
		return Vector3.new(x, 0, 0)
	end)
end

test("the head: from a little above it to standing on it, within about a body's width", function()
	expectTrue(Rules.StompsOn(Vector3.new(0, 5, 0), Vector3.zero), "on the head")
	expectTrue(Rules.StompsOn(Vector3.new(2, 4, 0), Vector3.zero), "on a shoulder")
	expectTrue(not Rules.StompsOn(Vector3.new(2.3, 4, 0), Vector3.zero), "beside")
	expectTrue(not Rules.StompsOn(Vector3.new(0, 2.4, 0), Vector3.zero), "level with it")
	expectTrue(not Rules.StompsOn(Vector3.new(0, 6.1, 0), Vector3.zero), "far above it")
end)

test("going up through someone is no stomp", function()
	local up = trail(function(t)
		return Vector3.new(0, 2 + 14 * (t - (NOW - 0.4)), 0)
	end)
	expectTrue(not Rules.Stomped(up, 0, standing(0), SEEN + PING, NOW), "a person jumping up")
	expectTrue(not Rules.Stomped(up, SEEN + PING, standing(0), 0, NOW), "a bot jumping up")
end)

test("a person stomping counts the victim where their own screen showed them", function()
	-- The person comes down on x = 0 now (5 up: on the head). The bot that was under them walked on
	-- at 16 studs/s and is 2.9 studs away on the server, but their screen (0.21s late) shows it there.
	local person = trail(function(t)
		return Vector3.new(0, 5 + (NOW - t) * 10, 0)
	end)
	local bot = trail(function(t)
		return Vector3.new(2.9 - 16 * (NOW - t), 0, 0)
	end)
	expectTrue(Rules.Stomped(person, 0, bot, SEEN + PING, NOW), "where their screen showed it")
	expectTrue(not Rules.Stomped(person, 0, bot, 0, NOW), "not where it is now")
end)

test("a bot stomping is judged on the victim's screen: stepping away from the leap is a dodge", function()
	-- The bot comes down on x = 2, where the person stood; they saw the leap coming and walked off at
	-- 16 studs/s 0.35s ago. On their screen (the bot drawn 0.21s late) it comes down 3.6 studs behind.
	local bot = trail(function(t)
		return Vector3.new(2, 3 + 10 * (NOW - t), 0)
	end)
	local person = trail(function(t)
		return Vector3.new(math.max(0, t - (NOW - 0.35)) * 16, 0, 0)
	end)
	expectTrue(not Rules.Stomped(bot, SEEN + PING, person, 0, NOW), "a dodge")
	-- The old rule (the bot now against any of the person's spots from the last 0.15s, meant for a
	-- person's screen) stunned them for it.
	expectTrue(Rules.Stomped(bot, 0, person, SEEN, NOW), "what the old rule did")
end)

test("a bot stomping someone who stays put still lands", function()
	local bot = trail(function(t)
		return Vector3.new(0.5, 3 + 10 * (NOW - t), 0)
	end)
	expectTrue(Rules.Stomped(bot, SEEN + PING, standing(0), 0, NOW), "on the head")
end)

test("a bot on a bot goes by the server, where both are", function()
	local attacker = trail(function(t)
		return Vector3.new(0, 5 + (NOW - t) * 10, 0)
	end)
	local gone = trail(function(t)
		return Vector3.new(1 + 16 * (t - (NOW - 0.4)), 0, 0)
	end)
	expectTrue(Rules.Stomped(attacker, 0, standing(1), 0, NOW), "under it")
	expectTrue(not Rules.Stomped(attacker, 0, gone, 0, NOW), "walked off")
end)

return nil
