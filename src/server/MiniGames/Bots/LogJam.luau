-- How bots play Log Jam (contract in Bots/Default.luau). A bot stands at its mill and, whenever it's
-- its turn (placing or chopping, read from the mode's own station state), presses a shape after a
-- reaction time once the prompt shows, through ctx:BotAction exactly like a client's press, so the
-- server judges it by the same rules (a wrong shape jams the mill for a bot too).
--
-- Skill sets the reaction (a sharp bot ~0.4 s, a clumsy one ~0.9 s) and how often it hits the wrong
-- shape (up to ~1 in 6 for the clumsiest). The press is scheduled with ctx:Delay rather than on the
-- next ~0.15 s step, and it checks the log and phase are still the same before pressing. Bots hop
-- now and then when their team chops a log.

local LogJamBrain = {}

function LogJamBrain.Step(bot, ctx, mode, _dt)
	local memory = bot.Memory
	local team = mode.teamOf and mode.teamOf[bot]
	local station = team and mode.stations[team]
	if not station or not bot:Root() then
		return
	end
	if (memory.Logs or 0) < station.Logs then
		memory.Logs = station.Logs
		if bot:Chance(0.3) then
			bot:Jump()
		end
	end
	local phase = station.Phase
	local mine = (phase == "Place" and station.Placer == bot) or (phase == "Chop" and station.Chopper == bot)
	if not mine then
		return
	end
	local key = `{station.Seq}:{phase}:{station.JamUntil}:{station.ShowAt}`
	if memory.Planned == key then
		return
	end
	memory.Planned = key
	local now = ctx:Now()
	local showAt = math.max(station.ShowAt, station.JamUntil)
	local skill = bot.Skill
	local reaction = 0.3 + (1 - skill) * 0.6 + bot.Rng:NextNumber(0, 0.25)
	local wait = math.max(showAt - now, 0) + reaction
	local symbol = station.Symbol
	if bot:Chance((1 - skill) * 0.28) then
		symbol = symbol % #mode.SYMBOLS + 1 -- a fumbled press: the wrong shape
	end
	local seq = station.Seq
	ctx:Delay(wait, function()
		if station.Seq == seq and station.Phase == phase then
			ctx:BotAction(bot, "Press", symbol, seq, phase)
		end
	end)
end

return LogJamBrain
