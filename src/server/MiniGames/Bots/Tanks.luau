-- How bots play Tanks! (contract in Bots/Default.luau). A bot drives its tank through the same
-- controls a player's client sends ("In" with a stick direction and a turret aim, "Fire", "Mine"),
-- so the server drives, judges and blows it up exactly like a player's tank: every hazard (shells,
-- ricochets, mines, chain blasts) catches bots on the server the same way.
--
-- Each step (about 7 a second) a bot:
--   * picks a target: the nearest enemy, preferring one it can see;
--   * dodges a shell that will reach it within ~1.2 s (once it has noticed: a skill-based reaction
--     time, and weaker bots sometimes don't), trying forward, back and both sides of the shell's
--     line and taking the one that clears it best; skilled bots also shoot incoming shells down;
--   * keeps out of blasts (mines about to blow, its own fresh mines) and routes round mines;
--   * fights: in sight it keeps a middle distance and strafes, slips behind cover while both its
--     shells are out, otherwise it drives a tile path (BFS over the open tiles) toward its target;
--   * aims with a lead on the target's motion (better with skill) plus a little skill-based error,
--     turning its turret at a limited rate, and fires when lined up; with no line of sight it looks
--     for a bank shot off one wall (and won't take one that comes back at itself first);
--   * now and then lays a mine when an enemy is close, then drives off it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TankField = require(ReplicatedStorage.Shared.Logic.TankField)

local Brain = {}

local SPEED = TankField.SHELL_SPEED
local HORIZON = 1.2 -- seconds of shell flight a bot looks ahead
local wrap = TankField.Wrap

local function heading(dx: number, dz: number): number
	return math.atan2(-dx, -dz)
end

local function round(x: number): number
	return math.floor(x * 1000 + 0.5) / 1000
end

local function segmentDistance(px: number, pz: number, ax: number, az: number, bx: number, bz: number): (number, number)
	local dx, dz = bx - ax, bz - az
	local length2 = dx * dx + dz * dz
	local t = if length2 > 1e-9 then math.clamp(((px - ax) * dx + (pz - az) * dz) / length2, 0, 1) else 0
	local cx, cz = ax + dx * t - px, az + dz * t - pz
	return math.sqrt(cx * cx + cz * cz), t
end

-- The next tile on the shortest open path from (c0, r0) to (c1, r1) (8-way, no corner cutting).
local function nextTile(field, blocked, c0: number, r0: number, c1: number, r1: number): (number?, number?)
	local cols = field.Cols
	local function open(c: number, r: number): boolean
		return TankField.Open(field, c, r) and not blocked[(r - 1) * cols + c]
	end
	if c0 == c1 and r0 == r1 then
		return c1, r1
	end
	local goal = (r1 - 1) * cols + c1
	local dist = { [goal] = 0 }
	local queue = { goal }
	local head = 1
	local start = (r0 - 1) * cols + c0
	while head <= #queue do
		local cell = queue[head]
		head += 1
		if cell == start then
			break
		end
		local c, r = (cell - 1) % cols + 1, (cell - 1) // cols + 1
		for dr = -1, 1 do
			for dc = -1, 1 do
				if dc == 0 and dr == 0 then
					continue
				end
				local nc, nr = c + dc, r + dr
				local index = (nr - 1) * cols + nc
				if dist[index] == nil and (open(nc, nr) or index == start) then
					if dc ~= 0 and dr ~= 0 and not (open(c + dc, r) and open(c, r + dr)) then
						continue
					end
					dist[index] = dist[cell] + 1
					table.insert(queue, index)
				end
			end
		end
	end
	if dist[start] == nil then
		return nil, nil
	end
	local bestC, bestR, best = nil, nil, dist[start]
	for dr = -1, 1 do
		for dc = -1, 1 do
			local nc, nr = c0 + dc, r0 + dr
			local value = dist[(nr - 1) * cols + nc]
			if value and value < best and (dc == 0 or dr == 0 or (open(c0 + dc, r0) and open(c0, r0 + dr))) then
				bestC, bestR, best = nc, nr, value
			end
		end
	end
	return bestC, bestR
end

-- The shell that will reach this hull soonest within HORIZON: (shell, seconds, x, z, dx, dz).
local function threatOf(mode, tank, now: number)
	local best, bestT, bx, bz, bdx, bdz = nil, HORIZON, 0, 0, 0, 0
	for _, shell in mode.shells do
		if shell.Dead or now >= shell.End then
			continue
		end
		local own = shell.Owner == tank
		local s0 = (now - shell.T0) * SPEED
		local safe = if own then math.max(shell.Path.Bounce, TankField.OWN_SAFE * SPEED) else 0
		for k = 0, 12 do
			local t = k * HORIZON / 12
			local s = s0 + t * SPEED
			if s > shell.Path.Length or t >= bestT then
				break
			end
			if s < safe then
				continue
			end
			local x, z, dx, dz = TankField.At(shell.Path, s)
			if TankField.HullDistance(tank, x, z) < 1.6 then
				best, bestT, bx, bz, bdx, bdz = shell, t, x, z, dx, dz
				break
			end
		end
	end
	return best, bestT, bx, bz, bdx, bdz
end

-- Which way to drive to get out of a shell's way: the candidate (hull forward/back, either side of
-- the shell's line) that leaves the most room where the shell will be, allowing for turning.
local function dodge(field, tank, t: number, x: number, z: number, dx: number, dz: number): (number, number)
	local fx, fz = -math.sin(tank.H), -math.cos(tank.H)
	local options = { { fx, fz }, { -fx, -fz }, { -dz, dx }, { dz, -dx } }
	local bestX, bestZ, bestRoom = -dz, dx, -math.huge
	for _, option in options do
		local ox, oz = option[1], option[2]
		local turn = math.abs(wrap(heading(ox, oz) - tank.H))
		turn = math.min(turn, math.pi - turn) -- it can back up instead
		local moving = math.max(0, t - turn / TankField.TURN - 0.12)
		local travel = TankField.SPEED * moving
		local wall = TankField.Cast(field, tank.X, tank.Z, ox, oz, travel + TankField.HALF_LENGTH, 0)
		if wall then
			travel = math.max(0, wall - TankField.HALF_LENGTH - 0.5)
		end
		local moved = { X = tank.X + ox * travel, Z = tank.Z + oz * travel, H = tank.H }
		local room = TankField.HullDistance(moved :: any, x, z)
		if room > bestRoom then
			bestX, bestZ, bestRoom = ox, oz, room
		end
	end
	return bestX, bestZ
end

-- A one-wall bank shot at the target, or nil (never one that comes back past this tank first).
local function bankShot(field, tank, target): number?
	local best, bestS = nil, math.huge
	local steps = 72
	for index = 0, steps - 1 do
		local angle = index / steps * 2 * math.pi - math.pi
		local path = TankField.Path(field, tank.X, tank.Z, angle)
		local second = path.Segments[2]
		local reach = math.min(second.Length, 120 - second.S)
		if reach <= 0 then
			continue
		end
		local ex, ez = second.X + second.DX * reach, second.Z + second.DZ * reach
		local miss, along = segmentDistance(target.X, target.Z, second.X, second.Z, ex, ez)
		if miss > TankField.HALF_WIDTH * 0.8 then
			continue
		end
		local mine, mineAlong = segmentDistance(tank.X, tank.Z, second.X, second.Z, ex, ez)
		if mine < TankField.HALF_LENGTH + 2 and mineAlong <= along then
			continue
		end
		local s = second.S + along * reach
		if s < bestS then
			best, bestS = angle, s
		end
	end
	return best
end

function Brain.Step(bot, ctx, mode, dt)
	local tank = mode.tanks and mode.tanks[bot]
	local field = mode.field
	local now = ctx:Now()
	if not tank or tank.Out or not field or now < (mode.startAt or math.huge) then
		return
	end
	local m = bot.Memory
	local skill = bot.Skill
	local rng = bot.Rng
	m.Seq = (m.Seq or 0) + 1
	m.Aim = m.Aim or tank.Aim
	m.Seen = m.Seen or {}
	m.NextShot = m.NextShot or now + bot:Reaction() * 1.5 -- nobody fires the instant it's GO

	local enemies = {}
	for _, other in mode.list do
		if other ~= tank and not other.Out then
			table.insert(enemies, other)
		end
	end
	if #enemies == 0 then
		ctx:BotAction(bot, "In", m.Seq, 0, 0, m.Aim)
		return
	end

	-- Target: the nearest enemy, preferring one in sight (re-chosen every second or so).
	local target = m.Target
	if not target or target.Out or now >= (m.TargetUntil or 0) then
		local best, bestScore = nil, math.huge
		for _, other in enemies do
			local distance = math.sqrt((other.X - tank.X) ^ 2 + (other.Z - tank.Z) ^ 2)
			local score = distance * (if TankField.Clear(field, tank.X, tank.Z, other.X, other.Z, 0.6) then 1 else 1.6)
			if score < bestScore then
				best, bestScore = other, score
			end
		end
		target = best
		m.Target = best
		m.TargetUntil = now + rng:NextNumber(0.8, 1.6)
	end
	local tx, tz = target.X - tank.X, target.Z - tank.Z
	local distance = math.sqrt(tx * tx + tz * tz)
	local inSight = TankField.Clear(field, tank.X, tank.Z, target.X, target.Z, 0.6)

	-- Shells coming: noticed after a reaction time (weaker bots sometimes never notice).
	local shell, impactIn, sx, sz, sdx, sdz = threatOf(mode, tank, now)
	local noticed = false
	if shell then
		local seen = m.Seen[shell.Id]
		if not seen then
			seen = { At = now + bot:Reaction() * 0.6, Dodge = bot:Chance(0.3 + 0.65 * skill) }
			m.Seen[shell.Id] = seen
		end
		noticed = now >= seen.At and seen.Dodge
	end
	if m.Seq % 40 == 0 then
		for id in m.Seen do
			if not mode.shells[id] then
				m.Seen[id] = nil
			end
		end
	end

	-- Moving.
	local mx, mz = 0, 0
	local function toward(px: number, pz: number)
		local dx, dz = px - tank.X, pz - tank.Z
		local length = math.sqrt(dx * dx + dz * dz)
		if length > 0.5 then
			mx, mz = dx / length, dz / length
		end
	end
	local function route(goalX: number, goalZ: number)
		if now >= (m.RouteAt or 0) or m.RouteGoal ~= target then
			m.RouteAt = now + 0.45
			m.RouteGoal = target
			local blocked = {}
			for _, mine in mode.mines do
				if not mine.Dead then
					local c, r = TankField.Tile(field, mine.X, mine.Z)
					for dr = -1, 1 do
						for dc = -1, 1 do
							local cx, cz = TankField.Center(field, c + dc, r + dr)
							if (cx - mine.X) ^ 2 + (cz - mine.Z) ^ 2 < 64 then
								blocked[(r + dr - 1) * field.Cols + c + dc] = true
							end
						end
					end
				end
			end
			local c0, r0 = TankField.Tile(field, tank.X, tank.Z)
			local c1, r1 = TankField.Tile(field, goalX, goalZ)
			local nc, nr = nextTile(field, blocked, c0, r0, c1, r1)
			m.NextC, m.NextR = nc, nr
		end
		if m.NextC and m.NextR then
			local cx, cz = TankField.Center(field, m.NextC, m.NextR)
			if (cx - tank.X) ^ 2 + (cz - tank.Z) ^ 2 < 6 then
				m.RouteAt = 0 -- there: next tile
			end
			toward(cx, cz)
		else
			toward(goalX, goalZ)
		end
	end

	local danger = nil
	for _, mine in mode.mines do
		if mine.Dead then
			continue
		end
		local d2 = (mine.X - tank.X) ^ 2 + (mine.Z - tank.Z) ^ 2
		if d2 < (TankField.MINE_BLAST + 4) ^ 2 and mine.BlowAt - now < 2.5 then
			danger = mine
			break
		end
	end

	if shell and noticed then
		mx, mz = dodge(field, tank, impactIn, sx, sz, sdx, sdz)
	elseif danger then
		toward(tank.X * 2 - danger.X, tank.Z * 2 - danger.Z)
	elseif m.Flee and now < m.Flee.Until then
		toward(tank.X * 2 - m.Flee.X, tank.Z * 2 - m.Flee.Z)
	elseif m.Unstick and now < m.Unstick.Until then
		mx, mz = m.Unstick.X, m.Unstick.Z
	elseif m.Cover and now < m.Cover.Until then
		toward(m.Cover.X, m.Cover.Z)
		if (m.Cover.X - tank.X) ^ 2 + (m.Cover.Z - tank.Z) ^ 2 < 4 then
			mx, mz = 0, 0
		end
	elseif inSight then
		if distance > 50 then
			route(target.X, target.Z)
		elseif distance < 18 then
			toward(tank.X - tx, tank.Z - tz)
		else
			-- Strafe across its line of fire, switching sides now and then (or when a wall's in the way).
			if not m.Strafe or now >= (m.StrafeUntil or 0) then
				m.Strafe = if bot:Chance(0.5) then 1 else -1
				m.StrafeUntil = now + rng:NextNumber(1.2, 2.6)
			end
			local ux, uz = tx / distance, tz / distance
			local px, pz = -uz * m.Strafe, ux * m.Strafe
			if TankField.Cast(field, tank.X, tank.Z, px, pz, 7, 0) then
				m.Strafe = -m.Strafe
				px, pz = -px, -pz
			end
			mx, mz = px * 0.9 + ux * 0.15, pz * 0.9 + uz * 0.15
			-- Both shells out: duck behind something for a moment (skilled bots more often).
			if tank.Shells >= TankField.MAX_SHELLS and bot:Chance(0.08 + 0.25 * skill) then
				local c0, r0 = TankField.Tile(field, tank.X, tank.Z)
				local best, bestD = nil, math.huge
				for r = r0 - 3, r0 + 3 do
					for c = c0 - 3, c0 + 3 do
						if TankField.Open(field, c, r) then
							local cx, cz = TankField.Center(field, c, r)
							local d = (cx - tank.X) ^ 2 + (cz - tank.Z) ^ 2
							if d < bestD and not TankField.Clear(field, cx, cz, target.X, target.Z, 0.6) then
								best, bestD = { X = cx, Z = cz }, d
							end
						end
					end
				end
				if best then
					m.Cover = { X = best.X, Z = best.Z, Until = now + rng:NextNumber(1.2, 2.2) }
				end
			end
		end
	else
		route(target.X, target.Z)
	end

	-- Keep clear of mines on the way.
	for _, mine in mode.mines do
		if not mine.Dead then
			local ax, az = tank.X - mine.X, tank.Z - mine.Z
			local d = math.sqrt(ax * ax + az * az)
			if d < 9 and d > 0.01 and (mine.Owner ~= tank or mine.Clear) then
				local push = (9 - d) / 9 * 1.6
				mx += ax / d * push
				mz += az / d * push
			end
		end
	end
	local length = math.sqrt(mx * mx + mz * mz)
	if length > 1 then
		mx, mz = mx / length, mz / length
	end

	-- Stuck against something: back out a random way for a moment.
	if length > 0.3 then
		if not m.StuckAt then
			m.StuckAt, m.StuckX, m.StuckZ = now, tank.X, tank.Z
		elseif now - m.StuckAt > 1.1 then
			if (tank.X - m.StuckX) ^ 2 + (tank.Z - m.StuckZ) ^ 2 < 1 then
				local angle = rng:NextNumber(0, 2 * math.pi)
				m.Unstick = { X = math.cos(angle), Z = math.sin(angle), Until = now + 0.7 }
			end
			m.StuckAt, m.StuckX, m.StuckZ = now, tank.X, tank.Z
		end
	end

	-- Aiming and firing.
	local wantAim, clear = m.Aim, false
	if shell and noticed and skill > 0.55 and tank.Shells < TankField.MAX_SHELLS and m.ShootDown ~= shell.Id then
		-- Shoot it down: aim where it will be when a shell from here meets it.
		local d = math.sqrt((sx - tank.X) ^ 2 + (sz - tank.Z) ^ 2)
		local meet = d / (2 * SPEED)
		local ax, az = sx - sdx * SPEED * meet, sz - sdz * SPEED * meet
		local s = (now - shell.T0) * SPEED + meet * SPEED
		ax, az = TankField.At(shell.Path, s)
		wantAim = heading(ax - tank.X, az - tank.Z)
		clear = bot:Chance(0.5 + 0.4 * skill)
		if clear then
			m.ShootDown = shell.Id
		end
	elseif inSight then
		local vx, vz = -math.sin(target.H) * target.V, -math.cos(target.H) * target.V
		local lead = 0.3 + 0.7 * skill
		local px, pz = target.X, target.Z
		for _ = 1, 2 do
			local fly = math.max(math.sqrt((px - tank.X) ^ 2 + (pz - tank.Z) ^ 2) - TankField.MUZZLE, 0) / SPEED
			px, pz = target.X + vx * fly * lead, target.Z + vz * fly * lead
		end
		if now >= (m.NoiseUntil or 0) then
			m.Noise = (rng:NextNumber() - 0.5 + rng:NextNumber() - 0.5) * (1 - skill) * 0.22
			m.NoiseUntil = now + rng:NextNumber(0.5, 1.1)
		end
		wantAim = heading(px - tank.X, pz - tank.Z) + (m.Noise or 0)
		clear = TankField.Clear(field, tank.X, tank.Z, px, pz, 0.5)
	else
		if skill > 0.4 and now >= (m.BankAt or 0) then
			m.BankAt = now + rng:NextNumber(0.7, 1.2)
			m.Bank = bankShot(field, tank, target)
		end
		if m.Bank then
			wantAim = m.Bank + (m.Noise or 0) * 0.3
			clear = true
		elseif m.NextC then
			local cx, cz = TankField.Center(field, m.NextC, m.NextR)
			wantAim = heading(cx - tank.X, cz - tank.Z) -- ready where it's heading
		else
			wantAim = heading(tx, tz)
		end
	end
	local rate = (2.4 + 4.5 * skill) * math.max(dt, 0.05)
	m.Aim = wrap(m.Aim + math.clamp(wrap(wantAim - m.Aim), -rate, rate))
	if
		clear
		and math.abs(wrap(wantAim - m.Aim)) < math.rad(5)
		and tank.Shells < TankField.MAX_SHELLS
		and now >= (m.NextShot or 0)
	then
		ctx:BotAction(bot, "Fire", m.Aim, now)
		m.NextShot = now + rng:NextNumber(0.35, 1.1) * (1.4 - skill)
		m.Bank = nil
	end

	-- A mine when an enemy is close (then drive off it).
	if tank.Mines < TankField.MAX_MINES and now >= (m.NextMine or now + rng:NextNumber(3, 6)) then
		m.NextMine = m.NextMine or now
		local close = math.huge
		for _, other in enemies do
			close = math.min(close, math.sqrt((other.X - tank.X) ^ 2 + (other.Z - tank.Z) ^ 2))
		end
		if close < 24 and bot:Chance(0.06 + 0.12 * skill) then
			ctx:BotAction(bot, "Mine")
			m.Flee = { X = tank.X, Z = tank.Z, Until = now + 1.8 }
			m.NextMine = now + rng:NextNumber(4, 8)
		end
	end

	ctx:BotAction(bot, "In", m.Seq, round(mx), round(mz), round(m.Aim))
end

return Brain
