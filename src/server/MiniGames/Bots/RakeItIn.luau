-- How bots play Rake It In (the contract is in Bots/Default.luau). A bot stands at its stand watching
-- its lane. When its rake is ready it looks ahead along the field's own schedule (the same one the
-- server judges rakes with) for a moment, a reaction time from now, when its lane holds something
-- worth raking, and presses RAKE then through ctx:BotAction, like a player's client.
--
-- Skilled bots wait for a fuller lane (2+ when the field is busy), catch the haul at its fullest and
-- nearly always let bombs pass. Less skilled bots take whatever is there, often don't notice a bomb
-- in the pile (each bomb is noticed or not once, when the bot first sees it; one it missed looks like
-- a veggie to it) and press a little early or late, so the produce has sometimes moved on. Another
-- player can always rake the produce first: a bot's plan isn't redone, just like a real press.

local RakeItInBrain = {}

local LOOK = 1.3 -- how far ahead (seconds) a bot looks for a good moment
local STEP = 0.1 -- between the moments it checks
local HOP = 0.004 -- chance per step (about 7 a second) of an idle hop

-- A random number from a bell curve (middle 0, spread 1).
local function bell(rng: Random): number
	return math.sqrt(-2 * math.log(1 - rng:NextNumber())) * math.cos(2 * math.pi * rng:NextNumber())
end

-- What the bot thinks raking its lane at time t would get: the value as it sees it, and whether it
-- spotted a bomb in there.
local function haul(bot, mode, station, t: number): (number, number, boolean)
	local seen = bot.Memory.Seen
	local count, value, bomb = 0, 0, false
	for _, item in mode.items do
		if mode:Takes(station, item, t) then
			count += 1
			local worth = mode.Kinds[item.Kind].Value
			if worth < 0 then
				if seen[item.Id] == nil then
					seen[item.Id] = bot:Chance(0.4 + 0.6 * bot.Skill)
				end
				if seen[item.Id] then
					bomb = true
				else
					worth = 1 -- didn't notice it: looks like any other veggie
				end
			end
			value += worth
		end
	end
	return count, value, bomb
end

local function plan(bot, mode, station, now: number): number?
	local rng = bot.Rng
	local skill = bot.Skill
	local ready = mode:ReadyAt(bot)
	local from = math.max(now + bot:Reaction(), ready)
	local busy = 0
	for _ in mode.items do
		busy += 1
	end
	local want = if skill >= 0.6 and busy >= 14 then 2 else 1
	local best, bestValue = nil, 0
	local t = from
	while t <= from + LOOK do
		local count, value, bomb = haul(bot, mode, station, t)
		-- A bomb it spotted is a no-go for a decent bot; a weak one still takes a big enough pile.
		local acceptable = count > 0 and value >= want and not (bomb and skill >= 0.5)
		if acceptable and value > bestValue then
			best, bestValue = t, value
		elseif best and value < bestValue then
			break -- the haul is past its fullest: take it
		end
		t += STEP
	end
	if not best then
		return nil
	end
	-- Unskilled bots press a little off the moment they wanted (never before the rake is ready).
	return math.max(best + bell(rng) * (1 - skill) * 0.22, ready)
end

function RakeItInBrain.Step(bot, ctx, mode, _dt)
	local station = mode.stations and mode.stations[bot]
	if not station or not bot:Root() then
		return
	end
	local memory = bot.Memory
	if memory.SeenFor ~= mode then
		memory.SeenFor = mode
		memory.Seen = {}
	end
	local now = ctx:Now()
	if memory.PressAt then
		if now >= memory.PressAt then
			ctx:BotAction(bot, "Rake", math.max(memory.PressAt, now - 0.1))
			memory.PressAt = nil
			memory.LookAt = now + 0.2
			if bot:Chance(0.08) then
				bot:Jump()
			end
		end
		return
	end
	if now < (memory.LookAt or 0) or now < mode:ReadyAt(bot) - 0.4 then
		if bot:Chance(HOP) then
			bot:Jump()
		end
		return
	end
	local pressAt = plan(bot, mode, station, now)
	if pressAt then
		memory.PressAt = pressAt
	else
		memory.LookAt = now + 0.15
	end
end

return RakeItInBrain
