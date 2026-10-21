-- How bots play Pump & Pop (owner: "we need bots in the mini games"; the contract is in
-- Bots/Default.luau). A bot stands at its pump and pumps in a rhythm: it presses Down, holds for
-- about the right time and lets go (ctx:BotAction, so the server times it exactly like a player's
-- press), waits for the plunger to spring back, and goes again.
--
-- Skill sets how close each hold lands to the middle of the green band and how quickly a bot gets
-- back on the handle: a skilled bot pumps nearly every press perfectly, a clumsy one lets go early
-- or holds too long now and then and pauses between pumps. The release is scheduled with ctx:Delay,
-- not on the next ~0.15 s step, so a bot's timing is as fine as a player's. Like the client, a bot
-- waits out the server's minimum CYCLE between presses, so its hold is timed from when the server
-- starts counting (a fumbled tap no longer cuts its next press short). Bots hop for joy when their
-- team pops its balloon.

local PumpAndPopBrain = {}

function PumpAndPopBrain.Step(bot, ctx, mode, _dt)
	local memory = bot.Memory
	local now = os.clock()
	if mode.winner then
		local pumper = mode.pumpers[bot]
		if pumper and pumper.Team == mode.winner and not memory.Cheered then
			memory.Cheered = true
			bot:Jump()
		end
		return
	end
	if not bot:Root() then
		return
	end
	if not memory.Next then
		memory.Next = now + bot:Reaction() -- a moment to get going after GO
	end
	if memory.Holding or now < memory.Next then
		return
	end

	local fill = mode.FILL_TIME
	local target = fill * (mode.SWEET + 1) / 2 -- the middle of the green band
	local wobble = (1 - bot.Skill) * 0.2
	local hold = target + bot.Rng:NextNumber(-1, 1) * wobble * 1.4
	if bot:Chance((1 - bot.Skill) * 0.12) then
		hold = bot.Rng:NextNumber(0.1, 0.3) -- a fumbled, hurried press
	end
	memory.Holding = true
	memory.DownAt = now
	ctx:BotAction(bot, "Down")
	ctx:Delay(math.max(hold, 0.05), function()
		ctx:BotAction(bot, "Up")
		memory.Holding = false
		local pause = bot.Rng:NextNumber(0.04, 0.2) + (1 - bot.Skill) * bot.Rng:NextNumber(0.05, 0.45)
		memory.Next = math.max(os.clock() + mode.SPRING, memory.DownAt + mode.CYCLE) + pause
	end)
end

return PumpAndPopBrain
