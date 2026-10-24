-- How bots play Capy Go Boom (contract in Bots/Default.luau). A bot fires through the same control a
-- player's client sends ("Boom", via ctx:BotAction), so the server judges, pops and spills for bots
-- exactly as for players; it eats by the same distance check. Every step (about 7 a second) a bot:
--   * sits still while it's staggered by a pop;
--   * watches for shells heading its way: after its reaction time (more often for skilled bots) it
--     steps out of the line, sometimes with a hop (a jump clears a shell);
--   * fires at a rival in range with a clear line (not behind a standing stone, not blinking after a
--     pop), nearer ones first and heavy ones only a little more (so the leader isn't ganged up on),
--     leading a moving target only partly and missing by a wide, skill-dependent angle, slowly (a shot
--     every few seconds) and with no aim assist, so a bot is clearly easier than a person who tries;
--   * picks a goal every half second or so: mostly the most worthwhile snack (big ones, golden apples
--     and the SNACK DROP's beam first), sometimes closing in on a rival to a firing distance and
--     circling it; bots also stop to dither now and then, and a bot well ahead of the others holds
--     its fire and slows down, so bots rarely run away with a round;
--   * walks round standing stones in its way.
local Brain = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- The first standing stone on the way from a to b, as { x, z } (world), or nil.
local function stoneBetween(mode, a: Vector3, b: Vector3, margin: number): (number?, number?)
	local Rules = mode.Rules
	local origin = mode.center
	for _, rock in mode.rocks do
		local cx, cz = origin.X + rock.X, origin.Z + rock.Z
		if Rules.SegmentEnter(a.X, a.Z, b.X, b.Z, cx, cz, Rules.ROCK_R + margin) then
			return cx, cz
		end
	end
	return nil, nil
end

local function inside(mode, point: Vector3): Vector3
	local origin = mode.center
	local offset = flat(point - origin)
	local limit = mode.radius - 4
	if offset.Magnitude > limit then
		offset = offset.Unit * limit
	end
	return Vector3.new(origin.X + offset.X, point.Y, origin.Z + offset.Z)
end

-- A waypoint round a stone that is in the way from `from` to `to` (or `to` itself).
local function around(mode, from: Vector3, to: Vector3): Vector3
	local Rules = mode.Rules
	local cx, cz = stoneBetween(mode, from, to, 2.4)
	if not cx or not cz then
		return to
	end
	-- Out from the stone on the side the path passes.
	local dx, dz = to.X - from.X, to.Z - from.Z
	local length2 = dx * dx + dz * dz
	local t = if length2 > 1 then math.clamp(((cx - from.X) * dx + (cz - from.Z) * dz) / length2, 0, 1) else 0
	local nx, nz = from.X + dx * t - cx, from.Z + dz * t - cz
	local n = math.sqrt(nx * nx + nz * nz)
	if n < 0.2 then
		nx, nz, n = -dz, dx, math.max(math.sqrt(dx * dx + dz * dz), 1e-3)
	end
	local reach = Rules.ROCK_R + 5
	return inside(mode, Vector3.new(cx + nx / n * reach, from.Y, cz + nz / n * reach))
end

function Brain.Step(bot, ctx, mode, _dt)
	local root = bot:Root()
	if not root or not mode.mass or mode.mass[bot] == nil then
		return
	end
	local Rules = mode.Rules
	local memory = bot.Memory
	local now = ctx:Now()
	local clock = os.clock()
	local pos = root.Position
	local origin = mode.center
	-- Bots here are deliberately gentler than their 0.35-0.9 skill says (and slower to react): a person
	-- who tries should beat them.
	local skill = bot.Skill * 0.65
	local function react(): number
		return bot:Reaction() * 1.4
	end
	memory.Noticed = memory.Noticed or {}
	memory.Dodges = memory.Dodges or {}
	if next(memory.Noticed) and #mode.shells == 0 then
		table.clear(memory.Noticed)
		table.clear(memory.Dodges)
	end

	if (mode.stunUntil[bot] or 0) > now then
		bot:Stop()
		return
	end
	local myMass = mode.mass[bot]
	local myScale = Rules.ScaleOf(myMass)
	local ready = now >= (mode.readyAt[bot] or 0) and not ctx:TimeIsUp()

	-- 1. A shell coming our way.
	if clock < (memory.DodgeUntil or 0) and memory.DodgeTo then
		bot:MoveTo(memory.DodgeTo)
		return
	end
	for _, shell in mode.shells do
		if shell.Owner == bot then
			continue
		end
		local p = shell.Origin + shell.Dir * (Rules.SHELL_SPEED * (now - shell.T0))
		local rel = flat(pos - p)
		local along = rel:Dot(shell.Dir)
		if along < 0 or along > 40 then
			continue
		end
		local sideways = rel - shell.Dir * along
		if sideways.Magnitude > Rules.HitRadius(myScale) + 2 then
			continue
		end
		if memory.Noticed[shell.Id] == nil then
			memory.Noticed[shell.Id] = clock + react()
			memory.Dodges[shell.Id] = bot.Rng:NextNumber() < 0.1 + 0.4 * skill
		end
		if clock >= memory.Noticed[shell.Id] and memory.Dodges[shell.Id] and along / Rules.SHELL_SPEED > 0.1 then
			memory.Dodges[shell.Id] = false
			local away = if sideways.Magnitude > 0.2
				then sideways.Unit
				else Vector3.new(-shell.Dir.Z, 0, shell.Dir.X) * (if bot.Rng:NextNumber() < 0.5 then -1 else 1)
			memory.DodgeTo = inside(mode, pos + away * 7)
			memory.DodgeUntil = clock + 0.35
			if bot:Chance(0.2 * skill) then
				bot:Jump()
			end
			bot:MoveTo(memory.DodgeTo)
			return
		end
	end

	-- 2. The best rival to fire at: big and close, a clear line, not blinking.
	local target, targetRoot, targetScore = nil, nil, -math.huge
	local rivals, massSum, count = {}, 0, 0
	for _, other in ctx:GetAlivePlayers() do
		local otherMass = mode.mass[other]
		if other == bot or otherMass == nil then
			continue
		end
		local _, _, otherRoot = ctx:GetCharacter(other)
		if not otherRoot then
			continue
		end
		massSum += otherMass
		count += 1
		local distance = flat(otherRoot.Position - pos).Magnitude
		table.insert(rivals, { Player = other, Root = otherRoot, Distance = distance, Mass = otherMass })
		if
			distance <= Rules.SHELL_RANGE * 0.7
			and (mode.safeUntil[other] or 0) <= now + 0.3
			and not stoneBetween(mode, pos, otherRoot.Position, Rules.SHELL_R)
		then
			-- (nearer first; weight counts for little, and a little luck, so nobody is singled out)
			local score = math.min(otherMass, 120) / 40 - distance / 7 + bot.Rng:NextNumber(0, 1.2)
			if score > targetScore then
				target, targetRoot, targetScore = other, otherRoot, score
			end
		end
	end
	-- A bot well ahead of the rest holds back (they shouldn't run away with a round).
	local average = if count > 0 then massSum / count else myMass
	local ahead = count > 0 and myMass > average * 1.3
	if target and targetRoot then
		memory.AimSince = memory.AimSince or clock
		if ready and clock >= (memory.FireAt or 0) and clock - memory.AimSince >= react() * 0.8 then
			memory.FireAt = clock + bot.Rng:NextNumber(1.1, 2.2) + (1 - skill) * 1.4
			memory.AimSince = nil
			if bot.Rng:NextNumber() < (0.38 + 0.3 * skill) * (if ahead then 0.4 else 1) then
				local distance = flat(targetRoot.Position - pos).Magnitude
				-- (a partial lead: a moving rival is usually missed)
				local lead = flat(targetRoot.AssemblyLinearVelocity) * (0.5 * skill * distance / Rules.SHELL_SPEED)
				local aim = flat(targetRoot.Position + lead - pos)
				if aim.Magnitude > 0.1 then
					local error = bot.Rng:NextNumber(-1, 1) * (0.14 + (1 - skill) * 0.5)
					local direction = CFrame.Angles(0, error, 0):VectorToWorldSpace(aim.Unit)
					ctx:BotAction(bot, "Boom", now, direction.X, direction.Z)
				end
			end
		end
	else
		memory.AimSince = nil
	end

	-- 3. Pick a goal now and then.
	if not memory.NextPick or clock >= memory.NextPick then
		memory.NextPick = clock + bot.Rng:NextNumber(0.5, 1.0) + (1 - skill) * 0.4
		memory.Goal, memory.Hunt = nil, nil
		local hunting = #rivals > 0
			and not ahead
			and bot.Rng:NextNumber() < (if myMass >= average then 0.1 + 0.15 * skill else 0.04)
		if bot.Rng:NextNumber() < (0.14 + (1 - skill) * 0.2) * (if ahead then 1.8 else 1) then
			-- Dithering: stands about for a moment, or wanders off, instead of going for the best snack.
			if bot.Rng:NextNumber() < 0.5 then
				memory.IdleUntil = clock + bot.Rng:NextNumber(0.5, 1.2)
			else
				local angle = bot.Rng:NextNumber(0, math.pi * 2)
				memory.Goal = inside(mode, pos + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 10)
			end
		elseif hunting then
			-- Close in on a rival (the heaviest within reach counts most) to a firing distance.
			local best, bestScore = nil, -math.huge
			for _, rival in rivals do
				local score = math.min(rival.Mass, 120) / 10 - rival.Distance / 10
				if score > bestScore then
					best, bestScore = rival, score
				end
			end
			if best then
				memory.Hunt = best.Player
			end
		elseif
			mode.dropSpot
			and flat(mode.dropSpot - pos).Magnitude < 70
			and bot.Rng:NextNumber() < 0.2 + 0.3 * skill
		then
			memory.Goal = mode.dropSpot
		else
			-- The most worthwhile snack: big ones count more, near ones count more.
			local bestSpot, bestScore = nil, -math.huge
			for _, snack in mode.snacks do
				if not Rules.Landed(snack, now + 0.6) then
					continue
				end
				local spot = Vector3.new(origin.X + snack[3], pos.Y, origin.Z + snack[4])
				local distance = flat(spot - pos).Magnitude
				local score = Rules.SNACKS[snack[2]].Mass * 1.6 - distance
				if score > bestScore then
					bestSpot, bestScore = spot, score
				end
			end
			memory.Goal = bestSpot
		end
	end

	-- 4. Go for it.
	if clock < (memory.IdleUntil or 0) then
		bot:Stop()
		return
	end
	local hunt = memory.Hunt
	local huntRoot = hunt and mode.mass[hunt] ~= nil and ctx:IsAlive(hunt) and select(3, ctx:GetCharacter(hunt))
	if huntRoot then
		local offset = flat(huntRoot.Position - pos)
		local distance = offset.Magnitude
		local wanted = 20 + (1 - skill) * 6
		local sidestep = Vector3.new(-offset.Z, 0, offset.X)
		if distance > 1e-3 then
			sidestep = sidestep.Unit * (if math.floor(clock / 1.7 + bot.Skill * 10) % 2 == 0 then 1 else -1)
		end
		local goal
		if distance > wanted + 4 then
			goal = huntRoot.Position - (if distance > 1e-3 then offset.Unit else Vector3.zero) * wanted
		elseif distance < wanted - 7 then
			goal = pos - (if distance > 1e-3 then offset.Unit else Vector3.zero) * 8 + sidestep * 4
		else
			goal = pos + sidestep * 8
		end
		bot:MoveTo(around(mode, pos, inside(mode, goal)))
	elseif memory.Goal then
		bot:MoveTo(around(mode, pos, memory.Goal))
		if flat(memory.Goal - pos).Magnitude < 2 then
			memory.NextPick = 0
		end
	else
		bot:Stop()
	end
	-- A little hop now and then, like players do.
	if bot:Chance(0.01) then
		bot:Jump()
	end
end

return Brain
