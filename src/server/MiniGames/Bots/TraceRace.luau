-- How bots play Trace Race. A bot steers its crayon like a player with a thumb on the stick: it
-- looks a little ahead down the guide (skilled bots start each turn in time, clumsy ones late),
-- reacts with a skill-based quickness, wobbles and now and then slips off the line and back. Skilled
-- bots score in the 90s, clumsy ones in the 60s-70s, so a careful player beats most of them. The
-- positions come from the mode (TraceRace:BotSamples) and are sent with ctx:BotAction, so the
-- server checks, scores and draws them exactly like a player's.
--
-- Hazard parity: this mode has no hazards. The only thing a client drives itself is its own crayon
-- and rider; bots' crayons are driven by these same samples on the server, which also seats bots
-- on their crayons (TraceRace:_placeBot), so everyone sees them ride.
local TraceRace = {}

function TraceRace.Step(bot, ctx, mode, _dt)
	if not mode.race then
		return
	end
	local memory = bot.Memory
	-- Each bot has a steady hand or not for the whole ride, a little off its overall skill.
	memory.Hand = memory.Hand or math.clamp(bot.Skill + bot.Rng:NextNumber(-0.08, 0.08), 0.3, 0.95)
	local samples = mode:BotSamples(bot, memory.Hand, bot.Rng, ctx:Now())
	if samples then
		ctx:BotAction(bot, "Trace", samples)
	end
end

return TraceRace
