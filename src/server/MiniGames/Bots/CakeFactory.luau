-- How bots play Cake Factory (the contract is in Bots/Default.luau). A bot stands at its machine(s)
-- and watches the belt: about 0.9 s before each cake reaches one of its machines it decides, then
-- presses ADD through ctx:BotAction when the cake should be in the gate (scheduled with ctx:Delay, so
-- its timing is as fine as a player's). The server judges the press exactly like a player's.
--
-- Skill sets how close to the middle of the gate a press lands (an unskilled bot's error is several
-- times the gate at full speed, so it splats cakes as the belt speeds up), how often it misses a
-- cake it should have done, and how often it carelessly presses on a cake that's missing a layer
-- (which ruins it). A bot that runs two machines plans each one on its own. Bots hop for joy when
-- their team wins. The belt carries no hazards, so there's nothing for the server to check on them.

local CakeFactoryBrain = {}

local LOOK_AHEAD = 0.9 -- seconds before a cake arrives that a bot makes up its mind

function CakeFactoryBrain.Step(bot, ctx, mode, _dt)
	local memory = bot.Memory
	if mode.stopAt then
		local worker = mode.workers[bot]
		if worker and not memory.Cheered and mode:_leader() == worker.Team then
			memory.Cheered = true
			bot:Jump()
		end
		return
	end
	if not mode.t0 or not bot:Root() then
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
			press = not bot:Chance((1 - skill) * 0.12) -- now and then a bot just misses one
		else
			press = bot:Chance((1 - skill) * 0.22) -- a careless press on a cake that isn't ready
		end
		if press then
			local spread = (1 - skill) * 0.42
			local err = (bot.Rng:NextNumber() + bot.Rng:NextNumber() - 1) * spread + (1 - skill) * 0.03
			ctx:Delay(math.max(at - now + err, 0.02), function()
				ctx:BotAction(bot, "Add")
			end)
		end
	end
end

return CakeFactoryBrain
