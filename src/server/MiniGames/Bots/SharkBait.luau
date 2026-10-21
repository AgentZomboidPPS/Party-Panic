-- How bots play Shark Bait (owner: "we need bots in the mini games"; the contract is in
-- Bots/Default.luau). Bots are judged by the same server code as players: the jaws' reach, who a
-- flip throws off, every grab and who's in the water are the mode's own position checks.
--
-- SHARK bots hunt. A swimmer they've noticed in the water (sooner with skill) is chased, aiming
-- where it's swimming, and chomped once it's well inside the jaws' reach. With nobody in the water
-- they pick a raft worth tipping (swimmers and coins on it, and near), swim up to its side and
-- chomp it; while the jaws reset they lurk by coins floating in the water (bait!) or circle. They
-- steer round the rafts, never through them.
--
-- SWIMMER bots stay up on the rafts and go for coins: on their own deck, a hop away (they run and
-- jump from the edge, grabbing gap coins mid-hop) and, the braver and better ones, coins in the
-- water while no shark is near. A raft that starts to wobble under them sends them hopping to a
-- neighbour that's up (after their reaction time); in the water they swim for the nearest raft
-- that's up, away from the sharks, and jump on.

local SharkBaitBrain = {}

local CLEARANCE = 1.8 -- how far a shark keeps its middle off a raft's edge

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

local function unit(v: Vector3, fallback: Vector3): Vector3
	local f = flat(v)
	return if f.Magnitude > 0.05 then f.Unit else fallback
end

local function rootOf(ctx, player): BasePart?
	local _, _, root = ctx:GetCharacter(player)
	return root
end

-- The nearest shark's middle to `point` (and how far), for swimmers weighing a risk.
local function nearestShark(ctx, mode, point: Vector3): (Vector3?, number)
	local best, bestDistance = nil, math.huge
	for _, shark in mode.sharks do
		local root = rootOf(ctx, shark)
		if root and ctx:IsAlive(shark) then
			local distance = flatDistance(root.Position, point)
			if distance < bestDistance then
				best, bestDistance = root.Position, distance
			end
		end
	end
	return best, bestDistance
end

-- Sharks ---------------------------------------------------------------------------------------------

-- Flat distance from `point` to the segment `a`-`b`.
local function segmentDistance(point: Vector3, a: Vector3, b: Vector3): number
	local ab = Vector2.new(b.X - a.X, b.Z - a.Z)
	local ap = Vector2.new(point.X - a.X, point.Z - a.Z)
	local length = ab:Dot(ab)
	local t = if length > 1e-9 then math.clamp(ap:Dot(ab) / length, 0, 1) else 0
	return (ap - ab * t).Magnitude
end

-- Whether a shark can swim straight from `a` to `b` without touching a raft that's up. A raft
-- either end is already close to only has to be kept that far off (so a shark beside a raft can
-- still swim away from it, or up to a swimmer by its edge).
local function clearPath(mode, a: Vector3, b: Vector3): boolean
	for _, raft in mode.rafts do
		if raft.State == mode.FLIPPED then
			continue -- under the water: nothing in the way
		end
		local need =
			math.min(raft.Radius + CLEARANCE, flatDistance(a, raft.Center) - 0.05, flatDistance(b, raft.Center) - 0.05)
		if segmentDistance(raft.Center, a, b) < need then
			return false
		end
	end
	return true
end

-- The water's lanes, once per round: a ring of points round the middle raft, one in each gap
-- between two outer rafts and a ring outside them all, joined wherever the water between two
-- points is clear of every raft.
local graphs = setmetatable({}, { __mode = "k" })
local function graphFor(mode)
	local graph = graphs[mode]
	if graph then
		return graph
	end
	local origin: Vector3 = mode.origin
	local y = mode.floorY + 3
	local nodes = {}
	local function add(radius: number, angle: number)
		table.insert(nodes, Vector3.new(origin.X + math.cos(angle) * radius, y, origin.Z + math.sin(angle) * radius))
	end
	local inner = (mode.CENTER_RADIUS + mode.RING - mode.RING_RADIUS) / 2
	local gaps = mode.RING * math.cos(math.pi / 6) -- where two outer rafts are closest
	local outer = mode.RING + mode.RING_RADIUS + 6
	for k = 0, 11 do
		add(inner, k * math.pi / 6)
		add(outer, k * math.pi / 6)
	end
	for k = 0, 5 do
		add(gaps, k * math.pi / 3)
	end
	local edges = {}
	for i, a in nodes do
		edges[i] = {}
		for j, b in nodes do
			if i ~= j and flatDistance(a, b) <= 17 then
				local clear = true
				for _, raft in mode.rafts do
					if segmentDistance(raft.Center, a, b) < raft.Radius + CLEARANCE then
						clear = false
						break
					end
				end
				if clear then
					table.insert(edges[i], { j, flatDistance(a, b) })
				end
			end
		end
	end
	graph = { Nodes = nodes, Edges = edges }
	graphs[mode] = graph
	return graph
end

-- Where a shark at `from` should head next for `goal`: straight there if the way is clear, else
-- the next point along the shortest way through the lanes.
local function steer(mode, from: Vector3, goal: Vector3): Vector3
	if clearPath(mode, from, goal) then
		return goal
	end
	local graph = graphFor(mode)
	local nodes = graph.Nodes
	local dist: { [number]: number } = {}
	local previous: { [number]: number } = {}
	local done: { [number]: boolean } = {}
	for index, node in nodes do
		if clearPath(mode, from, node) then
			dist[index] = flatDistance(from, node)
		end
	end
	local finish, finishTotal = nil, math.huge
	while true do
		local u, ud = nil, math.huge
		for index, d in dist do
			if not done[index] and d < ud then
				u, ud = index, d
			end
		end
		if not u or ud >= finishTotal then
			break
		end
		done[u] = true
		if clearPath(mode, nodes[u], goal) then
			local total = ud + flatDistance(nodes[u], goal)
			if total < finishTotal then
				finish, finishTotal = u, total
			end
		end
		for _, edge in graph.Edges[u] do
			local v, length = edge[1], edge[2]
			if not done[v] and ud + length < (dist[v] or math.huge) then
				dist[v] = ud + length
				previous[v] = u
			end
		end
	end
	if not finish then
		return goal -- no way through (it'll come): head straight for it
	end
	local path = { finish }
	while previous[path[1]] do
		table.insert(path, 1, previous[path[1]])
	end
	-- Already at the first point: on to the next one.
	local index = if #path > 1 and flatDistance(from, nodes[path[1]]) < 2 then 2 else 1
	local point = nodes[path[index]]
	return Vector3.new(point.X, goal.Y, point.Z)
end

-- A raft worth chomping: swimmers and coins on it count, distance counts against it.
local function pickRaft(bot, ctx, mode, from: Vector3, now: number)
	if mode:ReadyCount() <= mode.MIN_READY then
		return nil
	end
	local best, bestScore = nil, -math.huge
	for _, raft in mode.rafts do
		if raft.State ~= mode.READY or now < raft.SafeUntil + 0.3 then
			continue
		end
		local score = -flatDistance(from, raft.Center) * 0.12 + bot.Rng:NextNumber(0, 2.5 - bot.Skill * 1.5)
		for _, swimmer in ctx:GetAlivePlayers() do
			local root = rootOf(ctx, swimmer)
			if mode.role[swimmer] == "Swimmer" and root and flatDistance(root.Position, raft.Center) <= raft.Radius then
				score += 3
			end
		end
		for _, coin in mode.coins do
			if coin.Raft == raft.Index then
				score += 0.8
			end
		end
		if score > bestScore then
			best, bestScore = raft, score
		end
	end
	return best
end

local function sharkStep(bot, ctx, mode, now: number)
	local root = bot:Root()
	if not root then
		return
	end
	local memory = bot.Memory
	local position = root.Position
	memory.Noticed = memory.Noticed or {}
	memory.Seen = memory.Seen or {}
	local ready = now >= mode:ChompReadyAt(bot)

	-- 1. Prey: the nearest swimmer in the water this bot has noticed.
	local prey, preyRoot, preyDistance = nil, nil, math.huge
	for _, swimmer in ctx:GetAlivePlayers() do
		if mode.role[swimmer] ~= "Swimmer" or mode:IsEaten(swimmer) then
			continue
		end
		local swimmerRoot = rootOf(ctx, swimmer)
		if not swimmerRoot or not mode:InWater(swimmerRoot.Position) then
			memory.Noticed[swimmer] = nil
			continue
		end
		local noticed = memory.Noticed[swimmer]
		if not noticed then
			noticed = now + bot:Reaction() * 0.8
			memory.Noticed[swimmer] = noticed
		end
		local distance = flatDistance(position, swimmerRoot.Position)
		if now >= noticed and distance < 42 and distance < preyDistance then
			prey, preyRoot, preyDistance = swimmer, swimmerRoot, distance
		end
	end
	if prey and preyRoot then
		-- Aim where it's swimming (skilled bots lead it more).
		local seen = memory.Seen[prey]
		local velocity = Vector3.zero
		if seen and now > seen.T then
			velocity = flat(preyRoot.Position - seen.P) / (now - seen.T)
		end
		memory.Seen[prey] = { P = preyRoot.Position, T = now }
		local lead = math.min(preyDistance / mode.SHARK_SPEED, 0.8) * bot.Skill
		local target = preyRoot.Position + velocity * lead
		local goal = steer(mode, position, target)
		bot:MoveTo(Vector3.new(goal.X, position.Y, goal.Z))
		if ready and now >= (memory.ChompAt or 0) then
			-- Chomp once the swimmer is well inside the jaws (better bots wait for a surer bite).
			local facing = unit(root.CFrame.LookVector, Vector3.new(0, 0, -1))
			local dir = unit(preyRoot.Position - position, facing)
			local reach = mode.JawDistance(preyRoot.Position, position, dir)
			local along = flat(preyRoot.Position - position):Dot(dir)
			local sure = mode.BITE_RADIUS - 0.4 - bot.Skill * 0.6
			-- (Only at prey roughly ahead: a bot turns to bite, but not right round.)
			if reach <= sure and along <= mode.JAW_FAR - 1.2 and facing:Dot(dir) > 0.4 then
				mode:Aim(bot, preyRoot.Position)
				ctx:BotAction(bot, "Chomp")
				memory.ChompAt = now + 0.25 + (1 - bot.Skill) * 0.5
			end
		end
		return
	end

	-- 2. A raft worth tipping, chomped from the side facing us.
	if ready then
		local raft = if memory.Raft then mode.rafts[memory.Raft] else nil
		if not raft or raft.State ~= mode.READY or now < raft.SafeUntil or mode:ReadyCount() <= mode.MIN_READY then
			raft = pickRaft(bot, ctx, mode, position, now)
			memory.Raft = if raft then raft.Index else nil
			memory.RaftSince = now
		end
		if raft then
			local side = unit(position - raft.Center, Vector3.new(1, 0, 0))
			local spot = raft.Center + side * (raft.Radius + 2)
			local goal = steer(mode, position, spot)
			bot:MoveTo(Vector3.new(goal.X, position.Y, goal.Z))
			if flatDistance(position, raft.Center) <= raft.Radius + 3.6 and now >= (memory.ChompAt or 0) then
				mode:Aim(bot, raft.Center)
				ctx:BotAction(bot, "Chomp")
				memory.ChompAt = now + 0.3 + (1 - bot.Skill) * 0.5
				memory.Raft = nil
			elseif now - (memory.RaftSince or now) > 9 then
				memory.Raft = nil -- stuck: pick again
			end
			return
		end
	end

	-- 3. Lurk by coins floating in the water, or circle the rafts.
	local bait, baitDistance = nil, math.huge
	for _, coin in mode.coins do
		if coin.Raft == 0 and coin.Position.Y < mode.waterY + 1.5 then
			local distance = flatDistance(position, coin.Position)
			if distance < baitDistance then
				bait, baitDistance = coin, distance
			end
		end
	end
	local goal
	if bait and baitDistance < 30 then
		local off = unit(position - bait.Position, Vector3.new(1, 0, 0))
		goal = bait.Position + off * 4
	else
		local origin = mode.origin
		local offset = flat(position - origin)
		local angle = math.atan2(offset.Z, offset.X) + (if bot.Rng:NextNumber() < 0.5 then 0.5 else 0.6)
		local radius = mode.RING + mode.RING_RADIUS + 5
		goal = origin + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	end
	goal = steer(mode, position, goal)
	bot:MoveTo(Vector3.new(goal.X, position.Y, goal.Z))
end

-- Swimmers -------------------------------------------------------------------------------------------

-- Runs at `target` (a point on another raft, or past a gap) and jumps from the edge of `here`.
local function hop(bot, mode, position: Vector3, here, target: Vector3, now: number)
	local memory = bot.Memory
	bot:MoveTo(Vector3.new(target.X, mode.deckY + 3, target.Z))
	memory.Goal = Vector3.new(target.X, mode.deckY + 3, target.Z)
	local fromMiddle = flatDistance(position, here.Center)
	local outward = flatDistance(target, here.Center) > here.Radius
	if outward and fromMiddle >= here.Radius - 1.7 and now >= (memory.JumpAt or 0) then
		bot:Jump()
		memory.JumpAt = now + 0.8
	end
end

-- The best raft to climb onto from the water: near, up, and away from the sharks.
local function climbTarget(ctx, mode, position: Vector3)
	local best, bestScore = nil, math.huge
	for _, raft in mode.rafts do
		if raft.State == mode.FLIPPED then
			continue
		end
		local score = flatDistance(position, raft.Center) - raft.Radius
		if raft.State == mode.WOBBLING then
			score += 12
		end
		local _, sharkDistance = nearestShark(ctx, mode, raft.Center)
		if sharkDistance < raft.Radius + 4 then
			score += 5
		end
		if score < bestScore then
			best, bestScore = raft, score
		end
	end
	return best
end

-- Picks a coin to go for from raft `here`: its value against how far, with a hop or a swim costing
-- extra (and water coins only for the brave, with no shark near).
local function pickCoin(bot, ctx, mode, position: Vector3, here, now: number)
	local best, bestScore, bestTarget = nil, 0, nil
	local brave = bot.Skill * 0.7 + bot.Rng:NextNumber(0, 0.4)
	for id, coin in mode.coins do
		if coin.Born > now + 0.4 then
			continue
		end
		local value = mode.Kinds[coin.Kind].Value
		local p = coin.Position
		local distance = flatDistance(position, p)
		local cost, target = distance, p
		if coin.Raft == here.Index then
			target = p
		elseif coin.Raft > 0 then
			local raft = mode.rafts[coin.Raft]
			if raft.State ~= mode.READY or not table.find(here.Neighbours, raft.Index) then
				continue
			end
			cost += 6
		elseif p.Y > mode.deckY + 1 then
			-- Over a gap: hop through it to the raft beyond.
			local beyond, gap = nil, math.huge
			for _, index in here.Neighbours do
				local other = mode.rafts[index]
				local d = flatDistance(other.Center, p) - other.Radius
				if other.State == mode.READY and d < gap then
					beyond, gap = other, d
				end
			end
			if not beyond or flatDistance(here.Center, p) - here.Radius > 4.5 then
				continue
			end
			local dir = unit(beyond.Center - here.Center, Vector3.new(1, 0, 0))
			target = beyond.Center - dir * (beyond.Radius - 2.2)
			cost += 4
		else
			-- In the water: only with nerve, near the raft, and no shark close.
			local _, sharkDistance = nearestShark(ctx, mode, p)
			if brave < 0.55 or sharkDistance < 15 or flatDistance(here.Center, p) - here.Radius > 7 then
				continue
			end
			cost += 12 - bot.Skill * 5
		end
		local score = value / (cost + 2) + bot.Rng:NextNumber(0, 0.05)
		if id == bot.Memory.CoinId then
			score *= 1.3 -- stick with a choice
		end
		if score > bestScore then
			best, bestScore, bestTarget = id, score, target
		end
	end
	return best, bestTarget
end

local function swimmerStep(bot, ctx, mode, now: number)
	local root = bot:Root()
	if not root or mode:IsEaten(bot) then
		return
	end
	local memory = bot.Memory
	local position = root.Position

	if mode:InWater(position) then
		memory.FleeAt = nil
		-- A coin they jumped in for, while it's still there and no shark is close.
		local coin = if memory.CoinId then mode.coins[memory.CoinId] else nil
		local _, sharkDistance = nearestShark(ctx, mode, position)
		if coin and coin.Raft == 0 and coin.Position.Y < mode.waterY + 1.5 and sharkDistance > 9 then
			bot:MoveTo(Vector3.new(coin.Position.X, position.Y, coin.Position.Z))
			return
		end
		memory.CoinId = nil
		local raft = climbTarget(ctx, mode, position)
		if raft then
			local side = unit(position - raft.Center, Vector3.new(1, 0, 0))
			local edge = raft.Center + side * (raft.Radius - 1.6)
			bot:MoveTo(Vector3.new(edge.X, mode.deckY + 3, edge.Z))
			if flatDistance(position, raft.Center) <= raft.Radius + 2.6 and now >= (memory.JumpAt or 0) then
				bot:Jump()
				memory.JumpAt = now + 0.7
			end
		end
		return
	end

	local here = mode:RaftUnder(position, 0.3)
	if not here then
		-- Mid-hop: keep going.
		if memory.Goal then
			bot:MoveTo(memory.Goal)
		end
		return
	end

	-- A wobbling raft: hop to a neighbour that's up, once it registers.
	if here.State == mode.WOBBLING then
		memory.FleeAt = memory.FleeAt or (now + bot:Reaction())
		if now >= memory.FleeAt then
			local best, bestDistance = nil, math.huge
			for _, index in here.Neighbours do
				local other = mode.rafts[index]
				local distance = flatDistance(position, other.Center) - other.Radius
				if other.State == mode.READY and distance < bestDistance then
					best, bestDistance = other, distance
				end
			end
			if best then
				local dir = unit(best.Center - here.Center, Vector3.new(1, 0, 0))
				hop(bot, mode, position, here, best.Center - dir * (best.Radius - 2.5), now)
			end
		end
		return
	end
	memory.FleeAt = nil

	-- Coins: re-think now and then, or when the coin is gone.
	if not memory.CoinId or not mode.coins[memory.CoinId] or now >= (memory.ThinkAt or 0) then
		memory.CoinId, memory.Target = pickCoin(bot, ctx, mode, position, here, now)
		memory.ThinkAt = now + bot.Rng:NextNumber(0.6, 1.2) + bot:Reaction() * 0.5
	end
	local target: Vector3? = memory.Target
	if memory.CoinId and target then
		if flatDistance(target, here.Center) <= here.Radius - 0.5 then
			bot:MoveTo(Vector3.new(target.X, mode.deckY + 3, target.Z))
			memory.Goal = nil
		else
			hop(bot, mode, position, here, target, now)
		end
		return
	end

	-- Nothing worth it: drift about the middle of the deck (away from the edges the sharks bump).
	if not memory.WanderAt or now >= memory.WanderAt then
		memory.WanderAt = now + bot.Rng:NextNumber(1, 2.5)
		local angle = bot.Rng:NextNumber(0, math.pi * 2)
		local distance = bot.Rng:NextNumber(0, here.Radius * 0.45)
		memory.Wander = here.Center + Vector3.new(math.cos(angle) * distance, 3, math.sin(angle) * distance)
	end
	memory.Goal = nil
	bot:MoveTo(memory.Wander)
end

function SharkBaitBrain.Step(bot, ctx, mode, _dt)
	local now = ctx:Now()
	if mode:IsShark(bot) then
		sharkStep(bot, ctx, mode, now)
	else
		swimmerStep(bot, ctx, mode, now)
	end
end

return SharkBaitBrain
