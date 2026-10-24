-- How bots play Big Bad Vacuum (contract in Bots/Default.luau). They are on the lobby's side, and play like
-- a decent teammate with a skill that varies:
--   * Dodging: every attack is a danger zone the server publishes (mode:Zones), the same ones the clients
--     draw. A bot that finds itself in one (or too close to one) looks for the nearest way out; it only
--     notices after its reaction time, and a clumsy one gives itself less room (and sometimes freezes).
--     They jump the shockwave ring as it reaches them.
--   * Bricks: an empty-handed bot walks to the nearest pile (round the boss, not through it); with a brick
--     it waits for the core to open and throws, a beat apart from the others; some throw at the dust bag
--     when someone is stuck in it; a few clumsy ones waste a brick on the armour now and then.
--   * PANIC: when the party meter fills, bots press it after a human-like delay (a person usually wins).
-- Throws and PANIC go through ctx:BotAction, so the server judges them exactly like a player's.
-- The brain only reads the mode through its public methods (HasBrick, CoreOpen, Zones, RingAt...), so the
-- round harness's test bot can run this very brain on its stand-in players.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Logic.BigBadVacuum)

local Brain = {}

local DIRECTIONS = 16

local function inZone(zones: { any }, x: number, z: number, margin: number): boolean
	for _, zone in zones do
		if Rules.ZoneContains(zone, x, z) then
			return true
		end
		if margin > 0 then
			-- (a zone also counts when it is within `margin` studs: check the four points round)
			if
				Rules.ZoneContains(zone, x + margin, z)
				or Rules.ZoneContains(zone, x - margin, z)
				or Rules.ZoneContains(zone, x, z + margin)
				or Rules.ZoneContains(zone, x, z - margin)
			then
				return true
			end
		end
	end
	return false
end

-- Whether (x, z) is somewhere a bot may stand: inside the walls, clear of the boss's body.
local function walkable(mode, x: number, z: number): boolean
	if Rules.Distance(x, z, mode.center.X, mode.center.Z) > mode.radius - 5 then
		return false
	end
	local boss = mode.boss
	return Rules.Distance(x, z, boss.X, boss.Z) > Rules.BODY_RADIUS + 3.5
end

-- The nearest place out of every zone (and `margin` beyond them), or nil if there is none in reach.
local function escape(mode, zones: { any }, x: number, z: number, margin: number, memory): (number?, number?)
	local best, bestX, bestZ = math.huge, nil, nil
	for _, distance in { 9, 15, 22, 30 } do
		for step = 0, DIRECTIONS - 1 do
			local angle = step / DIRECTIONS * math.pi * 2
			local cx, cz = x + math.cos(angle) * distance, z + math.sin(angle) * distance
			if walkable(mode, cx, cz) and not inZone(zones, cx, cz, margin) then
				-- Prefer the shortest way, and keep going the way it was already going.
				local cost = distance
				if memory.EscapeAngle then
					cost += math.abs(Rules.Turn(memory.EscapeAngle, angle)) * 2
				end
				if cost < best then
					best, bestX, bestZ = cost, cx, cz
				end
			end
		end
		if bestX then
			if memory.EscapeAngle == nil then
				memory.EscapeAngle = math.atan2(bestZ - z, bestX - x)
			end
			return bestX, bestZ
		end
	end
	return nil, nil
end

-- A way round the boss's body on the way to (gx, gz) (a waypoint beside it, or the goal itself).
local function around(mode, x: number, z: number, gx: number, gz: number): (number, number)
	local boss = mode.boss
	local dx, dz = gx - x, gz - z
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 1 then
		return gx, gz
	end
	local ux, uz = dx / length, dz / length
	local along = math.clamp((boss.X - x) * ux + (boss.Z - z) * uz, 0, length)
	local nearX, nearZ = x + ux * along, z + uz * along
	local gap = Rules.Distance(nearX, nearZ, boss.X, boss.Z)
	local clear = Rules.BODY_RADIUS + 6
	if gap >= clear then
		return gx, gz
	end
	-- Pass on the side the straight line already favours.
	local cross = ux * (boss.Z - z) - uz * (boss.X - x)
	local side = if cross >= 0 then 1 else -1
	local wx = boss.X + side * uz * (clear + 3)
	local wz = boss.Z - side * ux * (clear + 3)
	if not walkable(mode, wx, wz) then
		return gx, gz
	end
	return wx, wz
end

function Brain.Step(bot, ctx, mode, _dt)
	local root = bot:Root()
	if not root or not mode.boss or not mode.center then
		return
	end
	local memory = bot.Memory
	local rng = bot.Rng
	local skill = bot.Skill
	local now = ctx:Now()
	local boss = mode.boss
	local position = root.Position
	local x, z = position.X, position.Z
	local floorY = mode.center.Y + Rules.STAND

	if not memory.Init then
		memory.Init = true
		memory.Rescuer = rng:NextNumber() < 0.45 + 0.3 * skill
		memory.Waster = skill < 0.5 and rng:NextNumber() < 0.5
		memory.Spot = rng:NextNumber(0, math.pi * 2)
	end

	-- Nothing to do while stuck in the bag, dazed, or once the fight is over.
	if mode:IsTrapped(bot) or mode:IsDazed(bot, now) or boss.State == "Dying" or boss.State == "Done" then
		bot:Stop()
		memory.Threat = nil
		return
	end

	-- A frozen moment now and then for the clumsy (caught like a deer in headlights).
	if memory.FrozenUntil and now < memory.FrozenUntil then
		bot:Stop()
		return
	end

	-- PANIC: pressed after a delay, so a person usually gets there first.
	if mode.meterReady and not boss.Shield then
		if not memory.PanicAt then
			memory.PanicAt = now + bot:Reaction() + rng:NextNumber(0.8, 2.6)
		elseif now >= memory.PanicAt then
			memory.PanicAt = nil
			ctx:BotAction(bot, "Panic")
		end
	else
		memory.PanicAt = nil
	end

	-- The shockwave ring: jump as it reaches us.
	local ring = mode:RingAt(now)
	if ring and position.Y - floorY < 1 then
		local away = Rules.Distance(x, z, ring.X, ring.Z)
		local reach = (now - ring.T0) * Rules.RING_SPEED
		local arrives = (away - reach) / Rules.RING_SPEED
		if arrives > -0.1 and arrives < 0.2 + 0.12 * (1 - skill) and not memory.Jumped then
			memory.Jumped = now
			if rng:NextNumber() < 0.55 + 0.45 * skill then
				bot:Jump()
			end
		end
	end
	if memory.Jumped and now - memory.Jumped > 1.5 then
		memory.Jumped = nil
	end

	-- Dodging: leave any warning zone we are in (or beside), after the reaction time.
	local zones = mode:Zones(now)
	local margin = 1.5 + 4.5 * skill
	if #zones > 0 and inZone(zones, x, z, margin) then
		if not memory.Threat then
			memory.Threat = now + bot:Reaction()
			if skill < 0.5 and bot:Chance(0.2) then
				memory.FrozenUntil = now + rng:NextNumber(0.25, 0.7)
			end
		end
		if now >= memory.Threat then
			local gx, gz = escape(mode, zones, x, z, margin, memory)
			if gx and gz then
				bot:MoveTo(Vector3.new(gx, position.Y, gz))
				return
			end
		end
	else
		memory.Threat = nil
		memory.EscapeAngle = nil
	end

	-- Throwing.
	local carrying = mode:HasBrick(bot)
	if carrying then
		local open = mode:CoreOpen(now)
		local stuck = mode:TrappedCount() > 0
		if stuck and (memory.Rescuer or not open) then
			memory.ThrowAt = memory.ThrowAt or (now + bot:Reaction() * 0.6 + rng:NextNumber(0, 0.5))
			if now >= memory.ThrowAt then
				memory.ThrowAt = nil
				ctx:BotAction(bot, "Throw", "Bag")
			end
		elseif open then
			memory.ThrowAt = memory.ThrowAt or (now + bot:Reaction() * 0.9 + rng:NextNumber(0.1, 0.9))
			if now >= memory.ThrowAt then
				memory.ThrowAt = nil
				ctx:BotAction(bot, "Throw", "Core")
			end
		else
			memory.ThrowAt = nil
			if memory.Waster and boss.State ~= "Intro" and bot:Chance(0.012) then
				ctx:BotAction(bot, "Throw", "Core") -- a chip on the armour; not the best use of a brick
			end
		end
	else
		memory.ThrowAt = nil
	end

	-- Where to be: at a pile when empty-handed, otherwise loitering at a safe distance from the boss.
	local goalX, goalZ
	if not carrying then
		local pile = mode:NearestPile(x, z, now)
		if pile then
			goalX, goalZ = pile.X, pile.Z
		end
	end
	if not goalX then
		local ringRadius = math.min(mode.radius - 8, Rules.BODY_RADIUS + 18 + 8 * skill)
		local angle = memory.Spot + math.sin(now * 0.35 + memory.Spot) * 0.6
		goalX = boss.X + math.cos(angle) * ringRadius
		goalZ = boss.Z + math.sin(angle) * ringRadius
		if Rules.Distance(goalX, goalZ, mode.center.X, mode.center.Z) > mode.radius - 7 then
			local dx, dz = goalX - mode.center.X, goalZ - mode.center.Z
			local m = math.max(math.sqrt(dx * dx + dz * dz), 1)
			goalX = mode.center.X + dx / m * (mode.radius - 7)
			goalZ = mode.center.Z + dz / m * (mode.radius - 7)
		end
		if bot:Chance(0.004) then
			memory.Spot = rng:NextNumber(0, math.pi * 2)
		end
	end
	-- Don't walk into a warning on the way (wait outside it instead).
	if #zones > 0 and inZone(zones, goalX, goalZ, 3) then
		bot:Stop()
		return
	end
	local wx, wz = around(mode, x, z, goalX, goalZ)
	bot:MoveTo(Vector3.new(wx, position.Y, wz))
	if bot:Chance(0.006) then
		bot:Jump()
	end
end

return Brain
