-- How bots play Bumper Ballers (contract in Bots/Default.luau). A bot rides a server-owned ball and
-- steers it with the same stick a player has (ctx:BotAction "Steer"), under the same speed and
-- acceleration limits and the same bump rules, so players and bots bump each other both ways.
--
-- Each think (every bot:Reaction() seconds) a bot picks a victim: someone close, better still
-- someone near the edge. It swings round to the inside of them and charges outward, leading the
-- target a little when skilled. It dodges balls charging at it, side-stepping toward the middle.
-- Every step it looks ahead along its own roll and pulls back from the rim. Skill sets how far it
-- looks ahead, how wide a safety margin it keeps, how often it dodges and how sloppy its aim is, so
-- weaker bots overshoot, get caught and roll off now and then: beatable, but they play for real.

local BumperBallersBrain = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function rotate(v: Vector3, angle: number): Vector3
	local c, s = math.cos(angle), math.sin(angle)
	return Vector3.new(v.X * c - v.Z * s, 0, v.X * s + v.Z * c)
end

local function unit(v: Vector3): Vector3
	return if v.Magnitude > 0.001 then v.Unit else Vector3.zero
end

local function pickTarget(bot, mode, me): any
	local best, bestScore = nil, -math.huge
	for player, other in mode.entries do
		if player == bot or other.Out then
			continue
		end
		local distance = flat(other.Position - me.Position).Magnitude
		local edge = flat(other.Position - mode.center).Magnitude / mode.islandRadius
		local score = -distance * 0.08 + edge * (0.6 + bot.Skill * 1.4) + bot.Rng:NextNumber(0, 1.2)
		if player == bot.Memory.Target then
			score += 0.4 -- some focus: don't flip-flop every think
		end
		if score > bestScore then
			best, bestScore = player, score
		end
	end
	return best
end

function BumperBallersBrain.Step(bot, ctx, mode, _dt)
	local entries = mode.entries
	local me = entries and entries[bot]
	if not me or me.Out then
		return
	end
	local memory = bot.Memory
	local skill = bot.Skill
	local now = os.clock()
	if not memory.Ready then
		memory.Ready = true
		bot:Stop() -- the ball does the moving, not the legs
		memory.NextThink = now + bot:Reaction()
	end

	if now >= memory.NextThink then
		memory.NextThink = now + bot:Reaction() + bot.Rng:NextNumber(0.1, 0.45)
		memory.Target = pickTarget(bot, mode, me)
		memory.Aim = bot.Rng:NextNumber(-1, 1) * (1 - skill) * 0.7
		memory.Lazy = bot:Chance(0.12 * (1 - skill)) -- a sloppy moment: coast instead of steering
		memory.Dodge = nil
		-- Who is charging at me?
		for player, other in entries do
			if player == bot or other.Out then
				continue
			end
			local toMe = flat(me.Position - other.Position)
			local closing = flat(other.Velocity - me.Velocity):Dot(unit(toMe))
			if toMe.Magnitude < 18 and closing > 11 and bot:Chance(0.2 + skill * 0.65) then
				local side = Vector3.new(-toMe.Z, 0, toMe.X).Unit
				local inward = unit(flat(mode.center - me.Position))
				memory.Dodge = if side:Dot(inward) >= 0 then side else -side
				memory.DodgeUntil = now + 0.5 + skill * 0.3
				break
			end
		end
	end

	local center = mode.center
	local radius = mode.islandRadius
	local position = me.Position
	local velocity = flat(me.Velocity)
	local desired = Vector3.zero

	local target = memory.Target and entries[memory.Target]
	if memory.Dodge and now < (memory.DodgeUntil or 0) then
		desired = memory.Dodge
	elseif target and not target.Out then
		local outward = unit(flat(target.Position - center))
		if outward.Magnitude < 0.5 then
			outward = unit(flat(target.Position - position))
		end
		local lead = flat(target.Velocity) * (0.1 + skill * 0.25)
		local toTarget = flat(target.Position + lead - position)
		local inside = flat(position - center):Dot(outward) < flat(target.Position - center).Magnitude - 3
		if inside and unit(toTarget):Dot(outward) > 0.35 then
			desired = unit(toTarget) -- charge: they're between me and the water
		else
			-- Swing round to the inside of them first.
			local behind = target.Position - outward * 10
			desired = unit(flat(behind - position))
			if flat(behind - position).Magnitude < 4 then
				desired = unit(toTarget)
			end
		end
		desired = rotate(desired, memory.Aim or 0)
	else
		desired = unit(flat(center - position)) * 0.4
	end
	if memory.Lazy then
		desired *= 0.25
	end

	-- Stay on the island: look ahead along the roll and pull back from the rim.
	local lookAhead = 0.3 + skill * 0.5
	local margin = 3 + skill * 8
	local ahead = flat(position - center) + velocity * lookAhead
	local danger = (ahead.Magnitude - (radius - margin)) / math.max(margin, 1)
	if danger > 0 then
		local inward = -unit(ahead)
		local weight = math.clamp(danger, 0, 1)
		desired = desired * (1 - weight) + inward * (0.6 + weight * 0.9)
	end
	if desired.Magnitude > 1 then
		desired = desired.Unit
	end
	ctx:BotAction(bot, "Steer", desired.X, desired.Z)
end

return BumperBallersBrain
