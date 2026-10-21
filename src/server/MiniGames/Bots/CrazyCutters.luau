-- How bots play Crazy Cutters. A bot runs its cutter round the outline like a player tracing with
-- a finger: it starts a moment after GO, goes at its own pace and wobbles off the line and back,
-- with now and then a slip. Skilled bots are quicker and steadier (scores in the 90s); clumsy ones
-- wander (60s-80s), so a careful player beats most of them. The positions come from the mode
-- (CrazyCutters:BotSamples) and are sent with ctx:BotAction, so the server checks, scores and draws
-- them exactly like a player's. There are no hazards in this mode, and nothing a client animates
-- on its own that a bot would need on the server: the cutter is drawn from the same relayed
-- positions for players and bots alike.
local CrazyCutters = {}

function CrazyCutters.Step(bot, ctx, mode, _dt)
	local round = mode.round
	if not round or round.Phase ~= "Cut" then
		return
	end
	local memory = bot.Memory
	-- Each bot has a steady hand or not for the whole game, a little off its overall skill.
	memory.Hand = memory.Hand or math.clamp(bot.Skill + bot.Rng:NextNumber(-0.08, 0.08), 0.3, 0.95)
	local samples = mode:BotSamples(bot, memory.Hand, bot.Rng, ctx:Now())
	if samples then
		ctx:BotAction(bot, "Cut", round.Index, samples)
	end
end

return CrazyCutters
