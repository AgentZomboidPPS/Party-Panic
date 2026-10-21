-- How bots play Skate Escape (contract in Bots/Default.luau). A bot presses PUSH like a player mashing
-- the button: skilled bots push faster and take fewer breathers. It looks at the next crate, barrier
-- or gap, works out when to ollie so the board peaks over it (or flies across the gap), and presses
-- JUMP then, a little early or late by skill; now and then it doesn't see one coming at all. Boost
-- pads it just rides over. The race itself (speed, wipeouts, the collapse) is the same server
-- simulation players skate in, so every hazard catches bots exactly like players.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkateCourse = require(ReplicatedStorage.Shared.Logic.SkateCourse)

local Brain = {}

local STEP = 0.15 -- brains run about this often; jumps due sooner are scheduled with ctx:Delay

-- When to jump for obstacle `o`, as a distance before it, going `speed`.
local function takeoffDistance(o, speed: number): number
	local air = speed * SkateCourse.AirTime
	if o.Kind == "Gap" then
		-- Leave the lip so the flight is centered over the gap (never later than the lip itself).
		return math.max(0.8, (air - o.Len) / 2) + o.Len / 2
	end
	return air / 2 -- the board peaks over the middle
end

function Brain.Step(bot, ctx, mode, _dt)
	local racers = mode.racers
	local racer = racers and racers[tostring(bot.UserId)]
	if not racer or racer.Done or not mode.startAt then
		return
	end
	local memory = bot.Memory
	local now = ctx:Now()
	local skill = bot.Skill

	-- Pushing: the presses due before the next step are scheduled at their own moments, so a bot can
	-- mash faster than it thinks.
	if not memory.NextPush then
		memory.NextPush = now + bot:Reaction() * 0.5
	end
	if SkateCourse.IsWiped(racer, now) then
		memory.NextPush = (racer.Wipe or now) + bot:Reaction() * 0.6
	else
		local rate = 2.5 + 3.5 * skill
		while memory.NextPush < now + STEP do
			ctx:Delay(math.max(0, memory.NextPush - now), function()
				ctx:BotAction(bot, "Push")
			end)
			memory.NextPush = math.max(memory.NextPush, now) + bot.Rng:NextNumber(0.85, 1.2) / rate
			if bot:Chance(0.04 * (1.1 - skill)) then
				memory.NextPush += bot.Rng:NextNumber(0.3, 0.8) -- a breather
			end
		end
	end

	-- Jumping: plan once per obstacle.
	local obstacles = mode.obstacles
	local index = racer.Next
	local o = obstacles[index]
	while o and o.Kind == "Boost" do
		index += 1
		o = obstacles[index]
	end
	if not o or memory.Planned == index then
		return
	end
	local speed = racer.V
	if speed < 4 then
		return
	end
	local distance = (o.D - racer.D) - takeoffDistance(o, speed)
	local wait = distance / speed
	if wait > STEP * 2 then
		return -- not yet: decide closer to it
	end
	memory.Planned = index
	if bot:Chance(0.02 + 0.09 * (1 - skill)) then
		return -- didn't see it coming
	end
	local miss = bot.Rng:NextNumber(-1, 1) * (0.04 + 0.18 * (1 - skill))
	ctx:Delay(math.max(0, wait + miss), function()
		ctx:BotAction(bot, "Jump")
	end)
end

return Brain
