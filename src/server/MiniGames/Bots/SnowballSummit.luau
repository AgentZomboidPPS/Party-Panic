-- How bots play Snowball Summit. A bot starts a snowball and rolls it on a loop round the middle of
-- the summit (it grows with every stud), picks the rival worth hitting (close, and above all near the
-- edge), and once its ball is big enough (or the chance is too good to wait) turns and lets go, aiming
-- where the rival is heading. Balls coming at it make it sidestep, or hop over the small ones; it
-- reacts after its reaction time and not always (bot.Skill), so bots are beatable. It never walks off
-- the summit on its own. The mode judges bots exactly like people (same hit test, no lag leeway as the
-- server moves them) and flies them off on the same knock arc.
local Brain = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function gaussian(rng: Random): number
	return math.sqrt(-2 * math.log(1 - rng:NextNumber())) * math.cos(2 * math.pi * rng:NextNumber())
end

-- The thrown ball (if any) about to reach this bot: the soonest one whose path passes within reach.
local function threat(mode, bot, position: Vector3, now: number): (any, number, number)
	local best, bestT, bestGap = nil, math.huge, math.huge
	for _, ball in mode.balls do
		if ball.Owner == bot or now > ball.Edge then
			continue
		end
		for step = 0, 10 do
			local t = now + step * 0.1
			local at = mode:BallAt(ball, t)
			local gap = flat(at - position).Magnitude
			if gap < ball.R + mode.BODY + 1.6 then
				if t < bestT then
					best, bestT, bestGap = ball, t, gap
				end
				break
			end
		end
	end
	return best, bestT - now, bestGap
end

function Brain.Step(bot, ctx, mode, _dt)
	local root = bot:Root()
	if not root or not mode.center or mode.flights[bot] then
		return
	end
	local memory = bot.Memory
	local now = ctx:Now()
	local center = mode.center
	local radius = mode.radius
	local position = root.Position
	local fromCenter = flat(position - center)
	local skill = bot.Skill

	memory.Reacted = memory.Reacted or {}
	memory.Seen = memory.Seen or {}

	-- 1. Dodge: notice a ball after a reaction time, then sidestep or hop (not every time).
	local ball, eta = threat(mode, bot, position, now)
	if ball then
		memory.Seen[ball.Id] = memory.Seen[ball.Id] or now
		if not memory.Reacted[ball.Id] and now - memory.Seen[ball.Id] >= bot:Reaction() * 0.6 then
			-- (most of the time, like a decent player watching the ball: about 2 in 3 for the clumsiest
			-- bots, 9 in 10 for the best; they used to stand still for nearly half of them)
			memory.Reacted[ball.Id] = if bot:Chance(0.5 + skill * 0.45) then "dodge" else "freeze"
		end
		if memory.Reacted[ball.Id] == "dodge" then
			if ball.R < 2.6 and eta < 0.32 and eta > 0.08 then
				bot:Jump()
			end
			local side = Vector3.new(-ball.Dir.Z, 0, ball.Dir.X)
			if side:Dot(fromCenter) > 0 then
				side = -side -- sidestep toward the middle, never toward the drop
			end
			memory.Dodge = center + fromCenter + side * 7
			memory.DodgeUntil = now + 0.6
		end
	end
	if memory.DodgeUntil and now < memory.DodgeUntil then
		local goal = memory.Dodge
		local off = flat(goal - center)
		if off.Magnitude > radius - 4 then
			goal = center + off.Unit * (radius - 4)
		end
		bot:MoveTo(goal)
		return
	end

	-- 2. Never near the edge on its own.
	if fromCenter.Magnitude > radius - 5 then
		bot:MoveTo(center + fromCenter.Unit * (radius * 0.4))
		return
	end

	-- 3. Pick a rival: close, and much better near the edge.
	local target, targetPos, bestScore = nil, nil, math.huge
	for _, other in ctx:GetAlivePlayers() do
		if other == bot then
			continue
		end
		local _, _, otherRoot = ctx:GetCharacter(other)
		if otherRoot then
			local p = otherRoot.Position
			local edge = flat(p - center).Magnitude / radius
			local score = (p - position).Magnitude - edge * 26
			if score < bestScore then
				target, targetPos, bestScore = other, p, score
			end
		end
	end

	local held = mode.held[bot]
	if not held then
		if bot:Chance(0.25 + skill * 0.4) then
			ctx:BotAction(bot, "Build")
			memory.WantR = mode.MIN_R + (mode.MAX_R - mode.MIN_R) * bot.Rng:NextNumber(0.35, 0.95)
			memory.Orbit = bot.Rng:NextNumber(0, math.pi * 2)
			memory.Spin = if bot:Chance(0.5) then 1 else -1
		end
		if targetPos then
			bot:MoveTo(position + flat(targetPos - position).Unit * 2)
		end
		return
	end

	-- 4. Holding: roll it round a loop near the middle until it's big enough or a rival is teetering.
	local distance = if targetPos then flat(targetPos - position).Magnitude else math.huge
	local edgeShare = if targetPos then flat(targetPos - center).Magnitude / radius else 0
	local tempting = targetPos and distance < 26 and edgeShare > 0.72 and held.R > 1.3
	if targetPos and distance < 34 and (held.R >= memory.WantR or tempting) then
		-- Aim where they're heading (skilled bots lead more), with a wobble that shrinks with skill.
		local velocity = Vector3.zero
		if memory.LastTarget == target and memory.LastPos then
			velocity = flat(targetPos - memory.LastPos) / math.max(0.05, now - (memory.LastT or now))
		end
		local travel = distance / (56 - 4.5 * held.R)
		local aim = targetPos + velocity * travel * skill
		local dir = flat(aim - position)
		if dir.Magnitude > 0.1 then
			local angle = math.atan2(dir.Z, dir.X) + gaussian(bot.Rng) * (1 - skill) * 0.22
			ctx:BotAction(bot, "Throw", math.cos(angle), math.sin(angle))
			memory.WantR = nil
			return
		end
	end
	memory.LastTarget, memory.LastPos, memory.LastT = target, targetPos, now
	memory.Orbit = (memory.Orbit or 0) + (memory.Spin or 1) * 0.2
	local loop = radius * 0.38
	bot:MoveTo(center + Vector3.new(math.cos(memory.Orbit) * loop, 0, math.sin(memory.Orbit) * loop))
end

return Brain
