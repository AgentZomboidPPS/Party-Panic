-- How bots ride in Rockin' Raceway (contract in Bots/Default.luau). They press GALLOP and HOP
-- through ctx:BotAction, so the server races and judges them exactly like players: a bot that runs
-- its carrots dry spins out, a bot that mistimes a hurdle is slowed.
--
-- Carrots: a bot gallops from a full-ish meter and lets go somewhere above empty. Better bots
-- (bot.Skill up to 0.9) ride the meter down near the red line and wait for it to fill up again;
-- weaker ones let go early, press again sooner (shorter, slower gallops) and now and then forget to
-- let go at all, which spins them out.
-- Hurdles: a bot hops when the next hurdle is about half a hop away (the hop's peak over the bar),
-- a little off for weaker bots, and sometimes not at all.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Track = require(ReplicatedStorage.Shared.Logic.RockinRacewayTrack)

local Brain = {}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- A new gallop: where this bot will let go and whether it forgets to.
local function planGallop(bot)
	local memory = bot.Memory
	local skill = bot.Skill
	memory.LetGo = lerp(42, 7, skill) + bot.Rng:NextNumber(-3, 5)
	memory.Forget = bot.Rng:NextNumber() < (1 - skill) * 0.3
	memory.PressAt = lerp(68, 97, skill) + bot.Rng:NextNumber(-6, 3)
end

function Brain.Step(bot, ctx, mode, _dt)
	local rider = mode.riders and mode.riders[bot]
	if not rider or rider.Gone or rider.Finish or not mode.racing then
		return
	end
	local memory = bot.Memory
	local now = ctx:Now()
	if memory.LetGo == nil then
		planGallop(bot)
		memory.Galloping = false
		memory.Hopped = {}
		memory.WaitUntil = now + bot:Reaction()
	end

	-- Carrots.
	local spinning = now < rider.SpinUntil
	if spinning then
		if memory.Galloping then
			memory.Galloping = false
			ctx:BotAction(bot, "Gallop", false)
		end
		memory.WaitUntil = rider.SpinUntil + bot:Reaction()
	elseif memory.Galloping then
		if rider.C <= memory.LetGo and not memory.Forget then
			memory.Galloping = false
			ctx:BotAction(bot, "Gallop", false)
			memory.WaitUntil = now + bot:Reaction() * 0.5
		end
	elseif now >= memory.WaitUntil and rider.C >= math.min(memory.PressAt, Track.CARROTS - 1) then
		planGallop(bot)
		memory.Galloping = true
		ctx:BotAction(bot, "Gallop", true)
	end
	-- (a gallop that never got through, or a reset after a spin, is pressed again)
	if memory.Galloping ~= rider.Gallop and not spinning then
		ctx:BotAction(bot, "Gallop", memory.Galloping)
	end

	-- Hurdles: hop about half a hop before the bar.
	local index = rider.Next
	local panel = mode.panels[index]
	while panel and panel.K ~= "H" do
		index += 1
		panel = mode.panels[index]
	end
	if panel and not memory.Hopped[index] and rider.V > 1 then
		local seconds = (panel.D - rider.D) / rider.V
		if memory.HopIn == nil or memory.HopFor ~= index then
			memory.HopFor = index
			local good = bot.Rng:NextNumber() < lerp(0.55, 0.95, bot.Skill)
			if good then
				memory.HopIn = bot.Rng:NextNumber(0.22, 0.5)
			elseif bot.Rng:NextNumber() < 0.5 then
				memory.HopIn = bot.Rng:NextNumber(0.8, 1.1) -- too early: down before the bar
			else
				memory.HopIn = -1 -- doesn't hop
			end
		end
		if memory.HopIn > 0 and seconds <= memory.HopIn then
			memory.Hopped[index] = true
			ctx:BotAction(bot, "Hop", now)
		end
	end
end

return Brain
