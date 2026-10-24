-- How bots play Eatsa Pizza (contract in Bots/Default.luau). A bot runs from bite spot to bite spot
-- of its team (mode.spots), like everyone (owner: "can we make players run around while eating
-- instead of just sitting on the slice?"): it picks the nearest spot no teammate is already eating (a
-- spot a teammate stands on costs extra, a slower bot sometimes picks a worse one, and it looks again
-- now and then on the way in case a teammate got there first), runs to it, stops on the ring and
-- mashes EAT through ctx:BotAction, exactly like a player's button. How fast it mashes depends on its
-- skill (about 4.5 to 7 bites a second, under the server's cap), it stops for a breath now and then,
-- and when its spot pops it takes a moment (its reaction) to see where the next one lit up before it
-- runs. A spot of its team it runs over that nobody is eating, it eats. A bot that stops moving short
-- of its spot hops.
--
-- The hot pepper (mode.chili): a bot that notices one close enough (better bots look farther and
-- go more often) runs for it after a moment's reaction, then goes back to its spots.
--
-- Hazard parity: nothing is animated only on clients. Spots and slices are the server's and bites are
-- judged from where the bot's character stands (mode:_spotUnder), like everyone's.

local Brain = {}

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Someone else of the team ate at `spot` a moment ago.
local function taken(mode, bot, team: string, spot, now: number): boolean
	for player, other in mode.members do
		if player ~= bot and other.Team == team and other.Spot == spot.Id and now - other.SpotAt < 0.6 then
			return true
		end
	end
	return false
end

-- Walks on towards `goal`; hops when it hasn't moved for a moment.
local function walk(bot, memory, root: BasePart, goal: Vector3, now: number)
	bot:MoveTo(Vector3.new(goal.X, root.Position.Y, goal.Z))
	if not memory.LastPos or (root.Position - memory.LastPos).Magnitude > 0.8 then
		memory.LastPos = root.Position
		memory.MovedAt = now
	elseif memory.MovedAt and now - memory.MovedAt > 0.8 then
		bot:Jump()
		memory.MovedAt = now
	end
end

function Brain.Step(bot, ctx, mode, dt)
	local member = mode.members and mode.members[bot]
	local root = bot:Root()
	if not member or not root or mode.phase ~= "Eat" or not mode.spots then
		return
	end
	local now = ctx:Now()
	local memory = bot.Memory
	local skill = bot.Skill
	if not memory.Rate then
		memory.Rate = 3.2 + 4.0 * skill
		memory.Acc = 0
		memory.WaitUntil = now + bot:Reaction()
		memory.Noise = {}
		-- (Where on a ring it stops: not every bot on the very middle.)
		memory.Lean = Vector3.new(bot.Rng:NextNumber(-1, 1), 0, bot.Rng:NextNumber(-1, 1)) * 0.9
	end
	if now < memory.WaitUntil then
		bot:Stop()
		return
	end

	local chili = mode.chili
	if chili then
		local offset = chili.Position - root.Position
		local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
		if memory.Chili ~= chili then
			memory.Chili = chili
			memory.ChiliAt = now + bot:Reaction() + bot.Rng:NextNumber(0.1, 0.6)
			memory.ChiliWant = distance < 8 + 14 * skill and bot:Chance(0.45 + 0.4 * skill)
		end
		if memory.ChiliWant and now >= memory.ChiliAt then
			walk(bot, memory, root, chili.Position, now)
			return
		end
	end

	local target = nil
	if memory.Target then
		for _, spot in mode.spots do
			if spot.Id == memory.Target then
				target = spot
				break
			end
		end
		if not target then
			-- Its spot popped (or went): a moment to see where the next one lit up.
			memory.Target = nil
			memory.WaitUntil = now + bot:Reaction() * 0.8
			bot:Stop()
			return
		end
	end

	local on = mode:_spotUnder(bot)
	if on and on ~= target and taken(mode, bot, member.Team, on, now) then
		on = nil -- (a teammate's: run on to its own)
	end
	if on then
		-- Chewing.
		memory.Target = on.Id
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
	memory.Acc = 0

	-- Running to a spot: the nearest no teammate is eating (looked at again every half second).
	if not target or now >= (memory.CheckAt or 0) then
		memory.CheckAt = now + 0.5
		local best, bestCost = nil, math.huge
		for _, spot in mode.spots do
			if spot.Team ~= member.Team then
				continue
			end
			local noise = memory.Noise[spot.Id]
			if not noise then
				noise = bot.Rng:NextNumber(0, 8) * (1 - skill)
				memory.Noise[spot.Id] = noise
			end
			local cost = flat(spot.Position, root.Position) + noise
			if taken(mode, bot, member.Team, spot, now) then
				cost += 14
			end
			if spot == target then
				cost -= 3 -- (no dithering between two)
			end
			if cost < bestCost then
				best, bestCost = spot, cost
			end
		end
		if best ~= target then
			target = best
			memory.Target = if best then best.Id else nil
			memory.LastPos = root.Position
			memory.MovedAt = now
		end
	end
	if not target then
		bot:Stop()
		return
	end
	walk(bot, memory, root, target.Position + memory.Lean, now)
end

return Brain
