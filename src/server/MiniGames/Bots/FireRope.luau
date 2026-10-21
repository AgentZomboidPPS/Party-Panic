-- How bots play Fire Rope. A bot reads the rope's schedule (mode.segments, the one every player's
-- screen draws) and jumps a moment before each bottom pass, like a player timing it by eye. Skilled
-- bots jump close to the best moment; others are less steady, and every bot now and then jumps too
-- late: more often as the rope speeds up, rarely when skilled. The mode judges a bot's jumps
-- exactly like a player's (its height around each pass), so bots really can be beaten.
local FireRope = {}

local LEAD = 0.27 -- jump this long before a pass: the jump is at its highest as the rope goes under
local PLAN_AHEAD = 1 -- a bot settles on its timing this long before each pass
local AIR_TIME = 0.8 -- after a jump, a bot is back on its feet by then
local SLOW, FAST = 3, 1.05 -- the mode's rope speeds (seconds per turn), for how hard a pass is

-- A normally distributed random number (mean 0, spread 1).
local function gaussian(rng: Random): number
	return math.sqrt(-2 * math.log(1 - rng:NextNumber())) * math.cos(2 * math.pi * rng:NextNumber())
end

-- The next time the rope passes under the players after `now`, and the rope's speed coming into it
-- (seconds per turn). Each segment of the schedule starts at a pass (A0 = 0), except the first one,
-- which starts at the top; passes after the last segment follow on from its speed.
local function nextPass(segments: { any }, now: number): (number?, number)
	local previous = nil
	for _, segment in segments do
		if segment.A0 == 0 and segment.T0 > now then
			return segment.T0, if previous then 2 * math.pi / previous.W else SLOW
		end
		previous = segment
	end
	if not previous then
		return nil, SLOW
	end
	local turn = 2 * math.pi / previous.W
	local pass = previous.T0 + (2 * math.pi - previous.A0) / previous.W
	while pass <= now do
		pass += turn
	end
	return pass, turn
end

function FireRope.Step(bot, ctx, mode, _dt)
	local root = bot:Root()
	local now = ctx:Now()
	local pass, period = nextPass(mode.segments or {}, now)
	local memory = bot.Memory
	if not root or not pass or math.abs(pass - (memory.Planned or 0)) < 0.05 or pass - now > PLAN_AHEAD then
		return
	end
	memory.Planned = pass
	local skill = bot.Skill
	memory.Bias = memory.Bias or gaussian(bot.Rng) * 0.04 * (1 - skill) -- a habit of going early or late
	local heat = math.clamp((SLOW - period) / (SLOW - FAST), 0, 1)

	local jumpAt
	if bot:Chance((0.003 + 0.04 * (1 - skill) ^ 2) * (0.4 + 2.4 * heat)) then
		jumpAt = pass + bot.Rng:NextNumber(0.2, 0.45) -- a slip: jumps as the rope hits
	else
		local spread = (0.04 + 0.12 * (1 - skill)) * (1 + 0.8 * heat)
		jumpAt = pass - LEAD + memory.Bias + gaussian(bot.Rng) * spread
	end

	-- Still in the air from the last jump? Go again on landing, like a player would.
	local function attempt()
		if not ctx:IsAlive(bot) then
			return
		end
		local landed = (memory.JumpedAt or -math.huge) + AIR_TIME
		if ctx:Now() < landed then
			if landed < pass + 0.3 then
				ctx:Delay(landed - ctx:Now(), attempt)
			end
			return
		end
		memory.JumpedAt = ctx:Now()
		bot:Jump()
	end
	ctx:Delay(math.max(0, jumpAt - now), attempt)
end

return FireRope
