-- How bots play Cake Factory (the contract is in Bots/Default.luau). A bot stands at its machine(s)
-- and watches the belt: about 0.9 s before each cake reaches one of its machines it decides, then
-- presses ADD through ctx:BotAction when the cake should be in the gate (scheduled with ctx:Delay, so
-- its timing is as fine as a player's). The server judges the press exactly like a player's.
--
-- Skill sets how close to the middle of the gate a press lands (an unskilled bot's error is several
-- times the gate at full speed, so it splats cakes as the belt speeds up), how often it misses a
-- cake it should have done, and how often it carelessly presses on a cake that isn't ready (one
-- that already has its layer gets ruined). Even the best bot has a floor of error, runs a little
-- late as the belt speeds up and skips one cake in fifteen, so a sharp human team beats a team of
-- them (a full-skill team finishes about 22-24 of the 27 plates, few of them ⭐). A bot that runs
-- two machines plans each one on its own. (Bots on the winning team hop in CakeFactory:Stop.)
-- The belt carries no hazards, so there's nothing for the server to check on them.

local CakeFactoryBrain = {}

local LOOK_AHEAD = 0.9 -- seconds before a cake arrives that a bot makes up its mind

function CakeFactoryBrain.Step(bot, ctx, mode, _dt)
	local memory = bot.Memory
	if mode.stopAt or not mode.t0 or not bot:Root() then
		return
	end
	local line, owned = mode:StationsOf(bot)
	if not line then
		return
	end
	memory.Planned = memory.Planned or {}
	local now = ctx:Now()
	local distance = mode:Distance(now)
	local skill = bot.Skill
	for _, index in owned do
		local station = line.Stations[index]
		-- The first cake that hasn't reached the middle of this machine's gate yet.
		local k = math.max(0, math.ceil((mode.START + distance - station.X) / mode.SPACING))
		local planned = memory.Planned[index]
		if planned and planned >= k then
			continue
		end
		local at = mode:ArrivalTime(k, station.X)
		if not at or at - now > LOOK_AHEAD then
			continue
		end
		memory.Planned[index] = k
		local cake = line.Cakes[k]
		local layers = if cake then cake.N else 0
		local ready = not (cake and cake.Bad) and layers == index - 1
		local press
		if ready then
			press = not bot:Chance(math.max(0.07, (1 - skill) * 0.25)) -- now and then a bot just misses one
		else
			press = bot:Chance((1 - skill) * 0.22) -- a careless press on a cake that isn't ready
		end
		if press then
			local spread = 0.18 + (1 - skill) * 0.5
			local err = (bot.Rng:NextNumber() + bot.Rng:NextNumber() - 1) * spread
				+ (1 - skill) * 0.03
				+ 0.03 * mode:Speed(now) / mode.V_END -- a little late as the belt speeds up
			ctx:Delay(math.max(at - now + err, 0.02), function()
				ctx:BotAction(bot, "Add")
			end)
		end
	end
end

return CakeFactoryBrain
