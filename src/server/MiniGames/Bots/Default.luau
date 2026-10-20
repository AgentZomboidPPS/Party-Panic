-- How a bot plays a mode that has no brain of its own: it wanders a little and hops now and then,
-- so it never just stands there.
--
-- Every mode can teach bots to play with a brain here, Bots/<Id>.luau:
--   Brain.Start(ctx, mode)            optional, once when the round starts
--   Brain.Step(bot, ctx, mode, dt)    about 7 times a second for each bot still in the round
-- `mode` is the mode's instance (its own fields: schedules, hexes, turn...). `bot` has MoveTo(position),
-- Stop(), Jump(), Root(), Humanoid(), Reaction() (seconds, by skill), Chance(p), Skill (0..1), Memory (a
-- table that's fresh each round) and Rng. ctx:BotAction(bot, name, ...) presses a control exactly like a
-- player's client does (ctx:OnAction validates it). Bots should be beatable: use Skill and Reaction().
local Default = {}

function Default.Step(bot, _ctx, _mode, _dt)
	local root = bot:Root()
	if not root then
		return
	end
	local memory = bot.Memory
	local now = os.clock()
	memory.Home = memory.Home or root.Position
	if not memory.Next or now >= memory.Next then
		memory.Next = now + bot.Rng:NextNumber(1.5, 4)
		local angle = bot.Rng:NextNumber(0, math.pi * 2)
		memory.Goal = memory.Home + Vector3.new(math.cos(angle), 0, math.sin(angle)) * bot.Rng:NextNumber(2, 10)
	end
	bot:MoveTo(memory.Goal)
	if bot:Chance(0.03) then
		bot:Jump()
	end
end

return Default
