-- How bots play Eatsa Pizza (contract in Bots/Default.luau). A bot walks to a slice of its team that
-- still has food on it (the nearest one, but it spreads out: a slice a teammate is already chewing
-- costs extra), stands on what's left of it and mashes EAT through ctx:BotAction, exactly like a
-- player's button. How fast it mashes depends on its skill (about 4 to 8 bites a second, under the
-- server's cap), it stops for a breath now and then, and it takes a moment to notice its slice is
-- gone before it walks on. A bot that stops moving short of its slice (the step up from an eaten
-- slice) hops.
--
-- Hazard parity: nothing is animated only on clients. Slices are the server's and bites are judged
-- from where the bot's character stands, like everyone's.

local Logic = require(game:GetService("ReplicatedStorage").Shared.Logic.EatsaPizza)

local Brain = {}

function Brain.Step(bot, ctx, mode, dt)
	local member = mode.members and mode.members[bot]
	local root = bot:Root()
	if not member or not root or mode.phase ~= "Eat" then
		return
	end
	local now = ctx:Now()
	local memory = bot.Memory
	local skill = bot.Skill
	if not memory.Side then
		memory.Side = bot.Rng:NextNumber(-0.8, 0.8)
		memory.Rate = 3.6 + 4.6 * skill
		memory.Acc = 0
		memory.WaitUntil = now + bot:Reaction()
	end
	if now < memory.WaitUntil then
		return
	end

	local on = mode:_locate(bot)
	if on and (not memory.Target or memory.Target == on or bot:Chance(0.3)) then
		-- Chewing.
		if memory.Target ~= on then
			memory.Target = on
		end
		bot:Stop()
		if memory.PauseUntil and now < memory.PauseUntil then
			return
		end
		if bot:Chance(0.025 * (1.3 - skill)) then
			memory.PauseUntil = now + bot.Rng:NextNumber(0.25, 0.7)
			return
		end
		memory.Acc += dt * memory.Rate * bot.Rng:NextNumber(0.8, 1.2)
		local guard = 0
		while memory.Acc >= 1 and guard < 3 do
			guard += 1
			memory.Acc -= 1
			ctx:BotAction(bot, "Eat")
		end
		memory.Acc = math.min(memory.Acc, 1.5)
		return
	end

	-- Walking to a slice with food left.
	local state = mode.teams[member.Team]
	local target = memory.Target and mode.slices[memory.Target]
	if not target or target.Left <= 0 then
		if target and target.Left <= 0 and memory.Target then
			memory.Target = nil
			memory.WaitUntil = now + bot:Reaction() * 0.8
			return
		end
		local best, bestCost = nil, math.huge
		for _, index in state.Slices do
			local slice = mode.slices[index]
			if slice.Left > 0 then
				local spot = mode.center + Logic.StandSpot(index, slice.Stage, mode.radius, memory.Side)
				local cost = (spot - root.Position).Magnitude
				for player, other in mode.members do
					if player ~= bot and other.Team == member.Team and other.On == index and now - other.OnAt < 0.6 then
						cost += 14
					end
				end
				cost += bot.Rng:NextNumber(0, 6) * (1 - skill)
				if cost < bestCost then
					best, bestCost = index, cost
				end
			end
		end
		memory.Target = best
		memory.MovedAt = now
		memory.LastPos = root.Position
	end
	local index = memory.Target
	if not index then
		bot:Stop()
		return
	end
	local slice = mode.slices[index]
	local spot = mode.center + Logic.StandSpot(index, slice.Stage, mode.radius, memory.Side)
	bot:MoveTo(Vector3.new(spot.X, root.Position.Y, spot.Z))
	-- Stuck (a step up onto a slice): hop.
	if memory.LastPos and (root.Position - memory.LastPos).Magnitude > 0.8 then
		memory.LastPos = root.Position
		memory.MovedAt = now
	elseif memory.MovedAt and now - memory.MovedAt > 0.8 then
		bot:Jump()
		memory.MovedAt = now
	end
end

return Brain
