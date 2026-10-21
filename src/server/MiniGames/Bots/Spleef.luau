-- How bots play Spleef. A bot picks a rival on its own floor, walks over (around the holes: a short
-- path search over the floor's blocks, hopping a one-block gap when it's cut off) to a spot within
-- reach, and digs out the blocks under the rival's feet, the one right under them first. Skilled bots
-- reach further, dig faster, lead a moving rival and keep moving so they're hard to dig under;
-- clumsy ones are slow, sometimes break the block next to the right one, and may not notice a block
-- cracking under them. Every dig goes through ctx:BotAction, the same checks as a player's tap. If a
-- bot is left over a hole, the mode drops it like anyone else (Spleef:_falls).

local Spleef = {}

local function flat(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

-- Whether a bot can stand at `position` on `floor`: a block (cracking ones only if it's not careful)
-- right under its middle.
local function standable(mode, floor: number, position: Vector3, careful: boolean): boolean
	local i, j = mode:GridOf(position)
	local cell = mode:CellAt(floor, i, j)
	return cell ~= nil and cell.State ~= "Gone" and not (careful and cell.State == "Cracking")
end

-- Whether walking straight from `from` to `to` keeps solid snow underfoot.
local function walkable(mode, floor: number, from: Vector3, to: Vector3, careful: boolean): boolean
	local delta = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local steps = math.max(1, math.ceil(delta.Magnitude / 1.2))
	for step = 1, steps do
		if not standable(mode, floor, from + delta * (step / steps), careful) then
			return false
		end
	end
	return true
end

-- A short path over the blocks of `floor` from where the bot is to the goal cell (8 directions, no
-- cutting a corner over a hole). Returns the list of cells, or nil if the goal can't be reached.
local function findPath(mode, floor: number, start, goal, careful: boolean): { any }?
	local function ok(cell): boolean
		return cell ~= nil and cell.State ~= "Gone" and not (careful and cell.State == "Cracking")
	end
	if not ok(goal) then
		return nil
	end
	local came = { [start] = start }
	local queue = { start }
	local head = 1
	while head <= #queue do
		local cell = queue[head]
		head += 1
		if cell == goal then
			local path = {}
			while cell ~= start do
				table.insert(path, 1, cell)
				cell = came[cell]
			end
			return path
		end
		for di = -1, 1 do
			for dj = -1, 1 do
				if di == 0 and dj == 0 then
					continue
				end
				local next = mode:CellAt(floor, cell.I + di, cell.J + dj)
				if not ok(next) or came[next] then
					continue
				end
				if di ~= 0 and dj ~= 0 then
					if
						not ok(mode:CellAt(floor, cell.I + di, cell.J))
						or not ok(mode:CellAt(floor, cell.I, cell.J + dj))
					then
						continue
					end
				end
				came[next] = cell
				table.insert(queue, next)
			end
		end
	end
	return nil
end

-- The closest safe block to stand on, preferring ones with solid neighbors and nearer the middle.
local function safeCell(mode, floor: number, here: Vector3, careful: boolean)
	local i0, j0 = mode:GridOf(here)
	local best, bestScore = nil, math.huge
	for di = -4, 4 do
		for dj = -4, 4 do
			local cell = mode:CellAt(floor, i0 + di, j0 + dj)
			if not cell or cell.State == "Gone" or (careful and cell.State == "Cracking") then
				continue
			end
			local neighbors = 0
			for _, offset in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				local other = mode:CellAt(floor, cell.I + offset[1], cell.J + offset[2])
				if other and other.State == "Solid" then
					neighbors += 1
				end
			end
			local score = flat(cell.Position, here) - neighbors * 1.5 + cell.Rim * 6
			if score < bestScore then
				best, bestScore = cell, score
			end
		end
	end
	return best
end

-- The nearest rival on the same floor (not one the server is dropping).
local function pickRival(bot, ctx, mode, floor: number, here: Vector3): any
	local best, bestDistance = nil, math.huge
	for _, player in ctx:GetAlivePlayers() do
		if player == bot or mode.falling[player] then
			continue
		end
		local _, humanoid, root = ctx:GetCharacter(player)
		if not humanoid or not root or mode:FloorAt(mode:Feet(humanoid, root)) ~= floor then
			continue
		end
		local distance = flat(root.Position, here) + bot.Rng:NextNumber(0, 6)
		if distance < bestDistance then
			best, bestDistance = player, distance
		end
	end
	return best
end

-- Walks toward a goal cell: straight if the snow holds all the way, else along the found path, or a
-- hop over a gap when it's cut off.
local function walkTo(bot, mode, floor: number, root: BasePart, goal, careful: boolean)
	local here = root.Position
	local standY = here.Y
	local target = Vector3.new(goal.Position.X, standY, goal.Position.Z)
	if walkable(mode, floor, here, target, careful) then
		bot:MoveTo(target)
		return
	end
	local i, j = mode:GridOf(here)
	local start = mode:CellAt(floor, i, j)
	local path = start and findPath(mode, floor, start, goal, careful)
	if path and #path > 0 then
		-- The furthest cell along the path that can be walked to in a straight line.
		local waypoint = path[1]
		for index = #path, 1, -1 do
			local cell = path[index]
			if walkable(mode, floor, here, Vector3.new(cell.Position.X, standY, cell.Position.Z), careful) then
				waypoint = cell
				break
			end
		end
		bot:MoveTo(Vector3.new(waypoint.Position.X, standY, waypoint.Position.Z))
		return
	end
	-- Cut off: hop across if the goal is close and the gap is short, else wait for a better goal.
	if flat(goal.Position, here) < 10 then
		bot:MoveTo(target)
		local ahead = here + (target - here).Unit * 2.2
		if not standable(mode, floor, ahead, false) and os.clock() - (bot.Memory.HoppedAt or 0) > 0.9 then
			bot.Memory.HoppedAt = os.clock()
			bot:Jump()
		end
	else
		bot:Stop()
	end
end

-- Picks the block to break under a rival (seen at `position`), or nil if none is in reach.
local function digTarget(bot, mode, floor: number, root: BasePart, feet: number, position: Vector3)
	local mine = {}
	for _, cell in mode:Supports(floor, root.Position) do
		mine[cell] = true
	end
	local cells = mode:Supports(floor, position)
	table.sort(cells, function(a, b)
		return flat(a.Position, position) < flat(b.Position, position)
	end)
	local reach = mode.Reach * (0.72 + 0.28 * bot.Skill)
	local eye = root.Position + Vector3.new(0, mode.Eye, 0)
	for _, cell in cells do
		if mine[cell] then
			continue
		end
		local nearest = Vector3.new(
			math.clamp(eye.X, cell.Position.X - 2, cell.Position.X + 2),
			cell.Position.Y,
			math.clamp(eye.Z, cell.Position.Z - 2, cell.Position.Z + 2)
		)
		if (nearest - eye).Magnitude <= reach and mode:CanBreak(root, feet, cell, 0) then
			-- A clumsy bot sometimes breaks the block beside the right one.
			if bot:Chance((1 - bot.Skill) * 0.35) then
				local other =
					mode:CellAt(floor, cell.I + bot.Rng:NextInteger(-1, 1), cell.J + bot.Rng:NextInteger(-1, 1))
				if other and not mine[other] and other.State ~= "Gone" and mode:CanBreak(root, feet, other, 0) then
					return other
				end
			end
			return cell
		end
	end
	return nil
end

function Spleef.Step(bot, ctx, mode, _dt)
	local root, humanoid = bot:Root(), bot:Humanoid()
	if not root or not humanoid or root.Anchored or mode.falling[bot] then
		return
	end
	local memory = bot.Memory
	local now = os.clock()
	local skill = bot.Skill
	local feet = mode:Feet(humanoid, root)
	local floor = mode:FloorAt(feet)
	if not floor then
		return -- in the air: hopping or falling
	end
	local here = root.Position
	memory.Aggression = memory.Aggression or (0.45 + bot.Rng:NextNumber() * 0.55)
	memory.NextDig = memory.NextDig or now + 0.6 + bot:Reaction()
	if memory.Careful == nil or now > (memory.CarefulUntil or 0) then
		memory.Careful = bot:Chance(0.35 + 0.6 * skill)
		memory.CarefulUntil = now + 2
	end
	local careful = memory.Careful

	-- Rivals: keep one for a few seconds, then look again.
	local rival = memory.Rival
	if rival and (not ctx:IsAlive(rival) or mode.falling[rival] or now > (memory.RivalUntil or 0)) then
		rival = nil
	end
	if rival then
		local _, rivalHumanoid, rivalRoot = ctx:GetCharacter(rival)
		if not rivalHumanoid or not rivalRoot or mode:FloorAt(mode:Feet(rivalHumanoid, rivalRoot)) ~= floor then
			rival = nil
		end
	end
	if not rival then
		rival = pickRival(bot, ctx, mode, floor, here)
		memory.RivalUntil = now + bot.Rng:NextNumber(2.5, 5)
		if rival ~= memory.Rival then
			memory.NextDig = math.max(memory.NextDig, now + bot:Reaction())
			memory.Seen = nil
		end
		memory.Rival = rival
	end
	local rivalRoot: BasePart? = nil
	if rival then
		local _, _, found = ctx:GetCharacter(rival)
		rivalRoot = found
	end

	-- Dig under the rival's feet (skilled bots aim where it's going).
	if rivalRoot and now >= memory.NextDig then
		local position = rivalRoot.Position
		local seen = memory.Seen
		local velocity = Vector3.zero
		if seen and now - seen.Time > 0.05 then
			velocity = (position - seen.Position) / (now - seen.Time)
		end
		memory.Seen = { Position = position, Time = now }
		local lead = position + Vector3.new(velocity.X, 0, velocity.Z) * (0.1 + 0.35 * skill)
		local cell = digTarget(bot, mode, floor, root, feet, lead)
		if cell then
			ctx:BotAction(bot, "Break", cell.Index)
			local pause = 0.72 - 0.42 * skill
			memory.NextDig = now + pause * bot.Rng:NextNumber(0.8, 1.35) / (0.7 + 0.3 * memory.Aggression)
		end
	end

	-- Where to stand: off a block that's going, else near the rival (moving round it), else
	-- somewhere solid away from the rim.
	local i, j = mode:GridOf(here)
	local under = mode:CellAt(floor, i, j)
	local danger = not under or under.State == "Gone" or (careful and under.State == "Cracking")
	local goal = memory.Goal
	if goal and (goal.State == "Gone" or (careful and goal.State == "Cracking") or goal.Floor ~= floor) then
		goal = nil
	end
	if danger then
		goal = safeCell(mode, floor, here, careful)
		memory.GoalUntil = now + 0.6
	elseif not goal or now > (memory.GoalUntil or 0) then
		if rivalRoot then
			-- A spot within reach of the rival, from a new angle every so often.
			local away = Vector3.new(here.X - rivalRoot.Position.X, 0, here.Z - rivalRoot.Position.Z)
			local angle = math.atan2(away.Z, away.X) + bot.Rng:NextNumber(-0.9, 0.9)
			local distance = 9 - 3 * memory.Aggression + bot.Rng:NextNumber(-1, 1)
			local spot = rivalRoot.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance
			local gi, gj = mode:GridOf(spot)
			goal = mode:CellAt(floor, gi, gj)
			if not goal or goal.State ~= "Solid" then
				goal = safeCell(mode, floor, spot, careful)
			end
			memory.GoalUntil = now + bot.Rng:NextNumber(0.9, 1.8) - skill * 0.4
		else
			local angle = bot.Rng:NextNumber(0, math.pi * 2)
			local spot = mode.center
				+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * bot.Rng:NextNumber(0, mode.radius * 2.4)
			goal = safeCell(mode, floor, spot, careful)
			memory.GoalUntil = now + bot.Rng:NextNumber(2, 4)
		end
	end
	memory.Goal = goal
	if goal and flat(goal.Position, here) > 1 then
		walkTo(bot, mode, floor, root, goal, careful)
	else
		bot:Stop()
	end
end

return Spleef
