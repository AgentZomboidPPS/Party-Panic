-- How bots play Struggle (contract in Bots/Default.luau). They stroll around the platform and
-- cheer now and then; replace this with how a decent, beatable player would play your mode.
local Brain = {}

function Brain.Step(bot, ctx, _mode, _dt)
	local root = bot:Root()
	if not root then
		return
	end
	local memory = bot.Memory
	local now = os.clock()
	if not memory.Next or now >= memory.Next then
		memory.Next = now + bot.Rng:NextNumber(1, 3)
		local angle = bot.Rng:NextNumber(0, math.pi * 2)
		memory.Goal = ctx.Origin.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * bot.Rng:NextNumber(2, 20)
	end
	bot:MoveTo(memory.Goal)
	if bot:Chance(0.02) then
		ctx:BotAction(bot, "Cheer")
	end
end

return Brain
