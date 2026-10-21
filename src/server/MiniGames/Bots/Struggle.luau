-- How bots play Struggle (contract in Bots/Default.luau). A bot swings through the same controls a
-- player's client sends ("Charge" on the press, "Swing" on the release, via ctx:BotAction), so the
-- server judges, knocks back and drops orbs for bots exactly as for players; it picks orbs up by the
-- same distance check. Every step (about 7 a second) a bot:
--   * sits still while it's knocked down;
--   * watches for wind-ups: a rival charging near it and facing it is noticed after the bot's
--     reaction time, and then (more often for skilled bots) it steps out of reach, sideways and back,
--     or, if it's ready and the rival is in its own reach, hits first with a quick tap;
--   * picks a goal every half second or so: loose orbs close by (it loves a pile), else the rival
--     worth the most (many orbs, close, not safe after a hit); weaker bots dither now and then;
--   * attacks a rival in reach once it's been there for its reaction time: mostly quick taps, a
--     charged swing when the rival is busy (looking away or grabbing orbs); clumsier bots swing a
--     little out of reach sometimes.
local Brain = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function Brain.Step(bot, ctx, mode, _dt)
	local root = bot:Root()
	if not root or not mode.held or mode.held[bot] == nil then
		return
	end
	local Rules = mode.Rules
	local memory = bot.Memory
	local now = ctx:Now()
	local clock = os.clock()
	local pos = root.Position
	local center = mode.center
	local skill = bot.Skill
	memory.Seen = memory.Seen or {}
	memory.Dodge = memory.Dodge or {}

	if (mode.stunUntil[bot] or 0) > now then
		bot:Stop()
		return
	end

	local mySwing = mode.swings[bot]
	local ready = not mySwing and now >= (mode.readyAt[bot] or 0) and not ctx:TimeIsUp()
	local function inField(point: Vector3): Vector3
		local mx, mz = Rules.FIELD_X - 2, Rules.FIELD_Z - 2
		return Vector3.new(
			math.clamp(point.X, center.X - mx, center.X + mx),
			pos.Y,
			math.clamp(point.Z, center.Z - mz, center.Z + mz)
		)
	end
	local function rootOf(player): BasePart?
		local _, _, r = ctx:GetCharacter(player)
		return r
	end

	-- 1. A wind-up coming our way.
	if clock < (memory.DodgeUntil or 0) and memory.DodgeTo then
		bot:MoveTo(memory.DodgeTo)
		return
	end
	for other, swing in mode.swings do
		if other == bot or swing.StrikeAt or swing.Cancelled then
			continue
		end
		local otherRoot = rootOf(other)
		if not otherRoot then
			continue
		end
		local offset = flat(pos - otherRoot.Position)
		local distance = offset.Magnitude
		if distance > Rules.RANGE_CHARGED + 3 or distance < 1e-3 then
			continue
		end
		local facing = flat(otherRoot.CFrame.LookVector)
		if facing.Magnitude < 1e-3 or facing.Unit:Dot(offset.Unit) < 0.2 then
			continue
		end
		memory.Seen[swing] = memory.Seen[swing] or clock + bot:Reaction()
		if memory.Dodge[swing] == nil then
			memory.Dodge[swing] = bot.Rng:NextNumber() < 0.25 + 0.65 * skill
		end
		if clock < memory.Seen[swing] or not memory.Dodge[swing] then
			continue
		end
		-- Hit first if it's in reach and we're ready (skilled bots), else get out of reach.
		if ready and distance <= Rules.RANGE * 0.85 and bot.Rng:NextNumber() < skill * 0.7 then
			bot:MoveTo(otherRoot.Position)
			ctx:BotAction(bot, "Charge", now)
			memory.ReleaseAt = clock + 0.05
			memory.Target = other
			return
		end
		local side = Vector3.new(-offset.Z, 0, offset.X).Unit * (if bot.Rng:NextNumber() < 0.5 then -1 else 1)
		memory.DodgeTo = inField(pos + offset.Unit * 9 + side * 5)
		memory.DodgeUntil = clock + 0.7
		bot:MoveTo(memory.DodgeTo)
		return
	end

	-- 2. Finish a swing we're holding: release when the target's in reach (or it's charged enough).
	if mySwing and not mySwing.StrikeAt then
		local target = memory.Target
		local targetRoot = target and rootOf(target)
		if targetRoot then
			bot:MoveTo(targetRoot.Position)
		end
		local held = now - mySwing.Start
		local wantCharge = memory.WantCharge == true
		local distance = if targetRoot then flat(targetRoot.Position - pos).Magnitude else math.huge
		local reach = (if held >= Rules.CHARGE then Rules.RANGE_CHARGED else Rules.RANGE) + (1 - skill) * 1.5
		if clock >= (memory.ReleaseAt or 0) and (not wantCharge or held >= Rules.CHARGE) then
			if distance <= reach or held >= Rules.CHARGE + 0.4 or not targetRoot then
				ctx:BotAction(bot, "Swing", now)
				memory.WantCharge = false
			end
		end
		return
	end

	-- 3. Pick a goal now and then.
	if not memory.NextPick or clock >= memory.NextPick then
		memory.NextPick = clock + bot.Rng:NextNumber(0.35, 0.7) + (1 - skill) * 0.3
		memory.Goal, memory.Target = nil, nil
		if bot.Rng:NextNumber() < 0.08 * (1 - skill) then
			local angle = bot.Rng:NextNumber(0, math.pi * 2)
			memory.Goal = inField(pos + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 10)
		else
			-- Loose orbs: the nearest, counting neighbours (a pile is worth more).
			local bestOrb, bestOrbScore = nil, -math.huge
			for _, orb in mode.orbs do
				local spot = center + Vector3.new(orb[3], 0, orb[4])
				local distance = flat(spot - pos).Magnitude
				local score = -distance
				if now < orb[7] + Rules.FLIGHT - 0.4 then
					score -= 4
				end
				if score > bestOrbScore then
					bestOrb, bestOrbScore = spot, score
				end
			end
			-- Rivals: many orbs, close, not safe.
			local bestRival, bestRivalScore = nil, -math.huge
			for _, other in ctx:GetAlivePlayers() do
				if other == bot or mode.held[other] == nil then
					continue
				end
				local otherRoot = rootOf(other)
				if not otherRoot then
					continue
				end
				local distance = flat(otherRoot.Position - pos).Magnitude
				local worth = math.min(mode.held[other], 8) + 1
				local score = worth * 3 - distance
				if (mode.safeUntil[other] or 0) > now + 0.3 then
					score -= 25
				end
				if score > bestRivalScore then
					bestRival, bestRivalScore = other, score
				end
			end
			if bestOrb and (bestOrbScore > -14 or not bestRival or bestOrbScore + 10 > bestRivalScore) then
				memory.Goal = Vector3.new(bestOrb.X, pos.Y, bestOrb.Z)
			elseif bestRival then
				memory.Target = bestRival
			end
		end
	end

	-- 4. Go for it; swing at a rival in reach.
	local target = memory.Target
	local targetRoot = target and ctx:IsAlive(target) and rootOf(target)
	if targetRoot then
		local offset = flat(targetRoot.Position - pos)
		local distance = offset.Magnitude
		-- Close in to a little inside reach.
		bot:MoveTo(targetRoot.Position)
		if distance <= Rules.RANGE + (1 - skill) * 1.2 and (mode.safeUntil[target] or 0) <= now + 0.2 then
			memory.InReachSince = memory.InReachSince or clock
			if ready and clock - memory.InReachSince >= bot:Reaction() * 0.6 then
				local theirFacing = flat(targetRoot.CFrame.LookVector)
				local busy = theirFacing.Magnitude > 1e-3
					and distance > 1e-3
					and theirFacing.Unit:Dot(offset.Unit) > 0.2
				memory.WantCharge = busy and bot.Rng:NextNumber() < 0.25 + 0.4 * skill
				memory.ReleaseAt = clock + 0.05
				ctx:BotAction(bot, "Charge", now)
				memory.InReachSince = nil
			end
		else
			memory.InReachSince = nil
		end
	elseif memory.Goal then
		bot:MoveTo(memory.Goal)
		if flat(memory.Goal - pos).Magnitude < 1.5 then
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
