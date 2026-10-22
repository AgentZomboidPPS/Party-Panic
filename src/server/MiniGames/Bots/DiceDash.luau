-- How bots play Dice Dash (contract in Bots/Default.luau). It's all luck: a bot just presses ROLL
-- like a person would, a moment after the die starts spinning (some quick, some slow, and now and
-- then one daydreams and lets the die stop by itself). The server moves bots by the same rules
-- as everyone (and poses their characters on the board), so every tile treats them alike.
local Brain = {}

function Brain.Step(bot, ctx, mode, _dt)
	local racer = mode.racers and mode.racers[bot]
	if not racer or racer.Gone or racer.Finish ~= nil or mode.phase ~= "Roll" then
		return
	end
	local memory = bot.Memory
	if memory.Turn ~= mode.turn then
		memory.Turn = mode.turn
		-- (bot.Skill only changes how eager they are: it's luck, so it changes nothing else)
		local daydream = bot:Chance(0.08)
		memory.RollAt = if daydream
			then math.huge
			else mode.turnAt + 0.35 + bot:Reaction() + bot.Rng:NextNumber(0, 1.4 - bot.Skill)
	end
	if racer.Roll == nil and ctx:Now() >= memory.RollAt then
		memory.RollAt = math.huge
		ctx:BotAction(bot, "Roll")
	end
end

return Brain
