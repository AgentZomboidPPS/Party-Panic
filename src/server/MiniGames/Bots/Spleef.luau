-- How bots play Spleef.
--
-- First pass: bots picked a rival on their floor, walked around the holes to within reach and dug
-- out the blocks under the rival's feet.
--
-- Second pass (owner: "Bots are awful at spleef. also spleef doesnt require you to dig. It should be
-- you walk over it and it fades out within like 1 second or so"): there's no digging any more; every
-- block fades about a second after anyone steps on it, so surviving is all about where you step.
-- A bot hops from block to block over fresh snow only:
--   * It stands on its block while it fades and leaves just before it goes (skilled bots cut it
--     fine, which saves snow; clumsy ones misjudge now and then and drop through). A few restless
--     bots never wait, which burns through the floor faster.
--   * Where to: a search over the untouched blocks it can walk to (a few steps out, further for
--     skilled bots) for the spot with the most fresh snow around it, away from everyone else, a
--     little noisier for clumsy bots. It only ever walks onto untouched blocks.
--   * Cornered (hardly any fresh snow left to walk to): skilled bots jump a one-block gap to a
--     bigger patch; otherwise, above the last floor, it drops on purpose: it walks into the hole (or
--     waits on its fading block) over the best fresh patch of the floor below, away from others. On
--     the last floor with nowhere fresh to go it takes the fading block with the most time left.
-- Bots step on blocks exactly like players (the mode judges everyone's feet the same way), and a
-- bot left over a hole is dropped by the mode like anyone else (Spleef:_falls).

local Spleef = {}

local ORTHO = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

local function flat(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

local function solid(cell): boolean
	return cell ~= nil and cell.State == "Solid"
end

-- Untouched blocks within two of a cell (0-24): how much fresh snow there is around it.
local function openness(mode, floor: number, i: number, j: number): number
	local count = 0
	for di = -2, 2 do
		for dj = -2, 2 do
			if (di ~= 0 or dj ~= 0) and solid(mode:CellAt(floor, i + di, j + dj)) then
				count += 1
			end
		end
	end
	return count
end

-- How crowded a spot is: closer rivals (on this floor) count more.
local function crowd(position: Vector3, others: { Vector3 }): number
	local total = 0
	for _, other in others do
		local distance = flat(position, other)
		if distance < 14 then
			total += (14 - distance) / 14
		end
	end
	return total
end

-- The block a step from `cell` lands on, if it's untouched and the way there holds (a diagonal
-- step passes the corner of the two blocks beside it, so neither may be gone).
local function stepTo(mode, floor: number, cell, di: number, dj: number)
	local next = mode:CellAt(floor, cell.I + di, cell.J + dj)
	if not solid(next) then
		return nil
	end
	if di ~= 0 and dj ~= 0 then
		local a = mode:CellAt(floor, cell.I + di, cell.J)
		local b = mode:CellAt(floor, cell.I, cell.J + dj)
		if not a or a.State == "Gone" or not b or b.State == "Gone" then
			return nil
		end
		if mode:TimeLeft(a) < 0.4 or mode:TimeLeft(b) < 0.4 then
			return nil
		end
	end
	return next
end

-- Searches the untouched blocks a bot can walk to from `start` (up to `depth` steps) for the best
-- place to head for. Returns the first step toward it (nil if there's none) and how many fresh
-- blocks it could reach at all (small: it's cornered).
local function plan(bot, mode, floor: number, start, others: { Vector3 }, depth: number)
	local skill = bot.Skill
	local came = { [start] = start }
	local steps = { [start] = 0 }
	local queue = { start }
	local head = 1
	local best, bestScore = nil, -math.huge
	local heading = bot.Memory.Heading
	while head <= #queue do
		local cell = queue[head]
		head += 1
		local d = steps[cell]
		if cell ~= start then
			local score = openness(mode, floor, cell.I, cell.J)
				- crowd(cell.Position, others) * (3 + 5 * skill)
				- d * 0.35
				- cell.Rim * 2
				+ bot.Rng:NextNumber(0, 1 + (1 - skill) * 6)
			if heading then
				local way = Vector3.new(cell.I - start.I, 0, cell.J - start.J)
				if way.Magnitude > 0 then
					score += way.Unit:Dot(heading) * 1.2 -- keep going the same way: smoother paths
				end
			end
			if score > bestScore then
				best, bestScore = cell, score
			end
		end
		if d < depth then
			for _, dir in DIRS do
				local next = stepTo(mode, floor, cell, dir[1], dir[2])
				if next and steps[next] == nil then
					steps[next] = d + 1
					came[next] = cell
					table.insert(queue, next)
				end
			end
		end
	end
	if not best then
		return nil, 0
	end
	local cell = best
	while came[cell] ~= start do
		cell = came[cell]
	end
	return cell, #queue - 1
end

-- Every rival's position on this floor (not ones the mode is dropping).
local function othersOn(bot, ctx, mode, floor: number): { Vector3 }
	local list = {}
	for _, player in ctx:GetAlivePlayers() do
		if player == bot or mode.falling[player] then
			continue
		end
		local _, humanoid, root = ctx:GetCharacter(player)
		if humanoid and root and mode:FloorAt(mode:Feet(humanoid, root)) == floor then
			table.insert(list, root.Position)
		end
	end
	return list
end

-- The block a bot is standing on: the one under its middle, else the one under its footprint
-- with the most time left.
local function cellUnder(mode, floor: number, position: Vector3)
	local i, j = mode:GridOf(position)
	local cell = mode:CellAt(floor, i, j)
	if cell and cell.State ~= "Gone" then
		return cell
	end
	local best, bestLeft = nil, -1
	for _, other in mode:Supports(floor, position) do
		local left = mode:TimeLeft(other)
		if left > bestLeft then
			best, bestLeft = other, left
		end
	end
	return best
end

-- Cornered: the way out. A jump over a one-block gap to a bigger patch (skilled bots), else a drop
-- to the best fresh patch below, else (on the last floor) the neighbor with the most time left.
local function escape(bot, ctx, mode, floor: number, cur, here: Vector3)
	local memory = bot.Memory
	local skill = bot.Skill
	local below = floor + 1
	local belowOthers = if below <= mode.Floors then othersOn(bot, ctx, mode, below) else {}

	local hop, hopScore = nil, -math.huge
	if skill >= 0.5 then
		for _, dir in ORTHO do
			local middle = mode:CellAt(floor, cur.I + dir[1], cur.J + dir[2])
			local far = mode:CellAt(floor, cur.I + dir[1] * 2, cur.J + dir[2] * 2)
			if solid(far) and not solid(middle) then
				local score = openness(mode, floor, far.I, far.J)
				if score > hopScore then
					hop, hopScore = far, score
				end
			end
		end
	end

	local drop, dropScore = nil, -math.huge
	if below <= mode.Floors then
		local options = { cur }
		for _, dir in DIRS do
			local cell = mode:CellAt(floor, cur.I + dir[1], cur.J + dir[2])
			if cell then
				table.insert(options, cell)
			end
		end
		for _, cell in options do
			local under = mode:CellAt(below, cell.I, cell.J)
			if solid(under) then
				local score = openness(mode, below, under.I, under.J)
					- crowd(under.Position, belowOthers) * 4
					+ bot.Rng:NextNumber(0, (1 - skill) * 6)
				if score > dropScore then
					drop, dropScore = cell, score
				end
			end
		end
	end

	if hop and hopScore >= 6 and (not drop or hopScore > dropScore + 2) then
		memory.Target, memory.Kind = hop, "Hop"
		bot:Jump()
		bot:MoveTo(Vector3.new(hop.Position.X, here.Y, hop.Position.Z))
		return
	end
	if drop then
		memory.Dropping = true
		if drop == cur then
			bot:Stop() -- its block goes soon: down it drops, onto fresh snow
		else
			memory.Target, memory.Kind = drop, "Drop"
			bot:MoveTo(Vector3.new(drop.Position.X, here.Y, drop.Position.Z))
		end
		return
	end
	-- Nowhere fresh: the neighbor that lasts longest, if it outlasts this block.
	local best, bestLeft = nil, mode:TimeLeft(cur) + 0.15
	for _, dir in DIRS do
		local cell = mode:CellAt(floor, cur.I + dir[1], cur.J + dir[2])
		if cell and cell.State ~= "Gone" and mode:TimeLeft(cell) > bestLeft then
			best, bestLeft = cell, mode:TimeLeft(cell)
		end
	end
	if best then
		memory.Target, memory.Kind = best, "Walk"
		bot:MoveTo(Vector3.new(best.Position.X, here.Y, best.Position.Z))
	elseif hop then
		memory.Target, memory.Kind = hop, "Hop"
		bot:Jump()
		bot:MoveTo(Vector3.new(hop.Position.X, here.Y, hop.Position.Z))
	else
		bot:Stop()
	end
end

-- When to leave the block it's on (seconds left on it): skilled bots wait until just before it
-- goes, clumsy ones are less exact and now and then forget until it's too late.
local function leaveTime(bot): number
	local skill = bot.Skill
	if bot.Memory.Restless then
		return math.huge
	end
	if bot:Chance((1 - skill) * 0.05) then
		return 0.03 -- daydreaming
	end
	return 0.27 + 0.13 * skill + bot.Rng:NextNumber(-0.1, 0.1) * (1 - skill)
end

function Spleef.Step(bot, ctx, mode, _dt)
	local root, humanoid = bot:Root(), bot:Humanoid()
	if not root or not humanoid or root.Anchored or mode.falling[bot] then
		return
	end
	local memory = bot.Memory
	local skill = bot.Skill
	local now = os.clock()
	local feet = mode:Feet(humanoid, root)
	local floor = mode:FloorAt(feet)
	if not floor then
		return -- in the air: jumping a gap or dropping down (it keeps heading where it was going)
	end
	local here = root.Position
	if memory.Restless == nil then
		memory.Restless = bot:Chance((1 - skill) * 0.45)
	end
	if memory.Floor ~= floor then
		-- A new floor (the start, or it just landed): a moment to look around.
		memory.Floor = floor
		memory.Target, memory.Dropping, memory.Heading = nil, nil, nil
		memory.WaitUntil = now + bot:Reaction() * 0.5
		memory.LeaveAt = leaveTime(bot)
	end

	-- On the way somewhere: keep going until it's there (or the plan went bad).
	local target = memory.Target
	if target then
		local kind = memory.Kind
		if target.Floor ~= floor or (kind ~= "Drop" and target.State == "Gone") then
			target = nil
		elseif flat(target.Position, here) < 0.6 then
			target = nil
			memory.LeaveAt = leaveTime(bot)
		end
		memory.Target = target
		if target then
			bot:MoveTo(Vector3.new(target.Position.X, here.Y, target.Position.Z))
			return
		end
	end
	local cur = cellUnder(mode, floor, here)
	if not cur then
		return -- over a hole: the mode drops it in a moment
	end
	if memory.Dropping then
		bot:Stop()
		return -- waiting for its block to go (or already falling)
	end
	if now < (memory.WaitUntil or 0) then
		bot:Stop()
		return
	end
	-- Stay while the block holds (it fades from the moment it was stepped on).
	local left = mode:TimeLeft(cur)
	if left > (memory.LeaveAt or 0.35) then
		bot:Stop()
		return
	end

	local others = othersOn(bot, ctx, mode, floor)
	local depth = 2 + math.floor(skill * 5 + 0.5)
	local nextCell, reach = plan(bot, mode, floor, cur, others, depth)
	if nextCell and reach > 3 then
		memory.CorneredAt = nil
		memory.Target, memory.Kind = nextCell, "Walk"
		local way = Vector3.new(nextCell.I - cur.I, 0, nextCell.J - cur.J)
		memory.Heading = if way.Magnitude > 0 then way.Unit else nil
		bot:MoveTo(Vector3.new(nextCell.Position.X, here.Y, nextCell.Position.Z))
		return
	end
	-- Cornered. Skilled bots see it at once; clumsy ones take a moment (and their block keeps going).
	if not memory.CorneredAt then
		memory.CorneredAt = now
	end
	if now - memory.CorneredAt < bot:Reaction() * 0.4 and left > 0.25 then
		if nextCell then
			memory.Target, memory.Kind = nextCell, "Walk"
			bot:MoveTo(Vector3.new(nextCell.Position.X, here.Y, nextCell.Position.Z))
		else
			bot:Stop()
		end
		return
	end
	memory.CorneredAt = nil
	escape(bot, ctx, mode, floor, cur, here)
end

return Spleef
