-- Test bot for Spleef (tools/checks/round_harness.py): each stand-in walks (in small PivotTo steps,
-- no physics here, about walking speed) from block to block over untouched snow, like a careful
-- player: it waits on its block while it fades and steps to the neighbor with the most fresh snow
-- around it (away from others) just before it goes. With nowhere fresh to go it walks into a hole
-- over fresh snow below, or onto the neighbor that lasts longest. The mode judges the steps and the
-- falls itself (Spleef:_falls drops a stand-in left over a hole), so this bot never moves one that is
-- falling. It also notes how the floors wear down, and dumps everything solid in the arena once.
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local plans = {}
	local floorsSeen = {}
	local reported = {}
	local milestones = {}
	local dropped = 0
	local SPEED = 16

	local function feetOf(player): (number?, any, any)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root then
			return nil, nil, nil
		end
		return mode:Feet(humanoid, root), humanoid, root
	end

	-- Everything solid in the arena, once: nothing may be solid where nothing is drawn.
	local function dumpColliders()
		local groups = {}
		for _, part in ctx.Arena:GetDescendants() do
			if part:IsA("BasePart") and part.CanCollide then
				local size = part.Size
				local label =
					`{part.ClassName} {part.Name} {math.floor(size.X * 10) / 10}x{math.floor(size.Y * 10) / 10}x{math.floor(
						size.Z * 10
					) / 10} transparency {part.Transparency}`
				groups[label] = (groups[label] or 0) + 1
			end
		end
		local lines = {}
		for label, count in groups do
			table.insert(lines, `{count} x {label}`)
		end
		table.sort(lines)
		env.note(`collidable parts in the arena: {if #lines > 0 then table.concat(lines, "; ") else "none"}`)
	end
	local dumped = false

	local function solid(cell): boolean
		return cell ~= nil and cell.State == "Solid"
	end

	local function openness(floor: number, i: number, j: number): number
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

	-- Where everyone else on this floor is.
	local function othersOn(player, floor: number): { Vector3 }
		local list = {}
		for _, other in ctx:GetAlivePlayers() do
			if other ~= player and not mode.falling[other] then
				local otherFeet, _, otherRoot = feetOf(other)
				if otherFeet and mode:FloorAt(otherFeet) == floor then
					table.insert(list, otherRoot.Position)
				end
			end
		end
		return list
	end

	local function choose(player, floor: number, cur)
		local others = othersOn(player, floor)
		local best, bestScore = nil, -math.huge
		for _, dir in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local cell = mode:CellAt(floor, cur.I + dir[1], cur.J + dir[2])
			if solid(cell) then
				local score = openness(floor, cell.I, cell.J) + env.rng:NextNumber(0, 2)
				for _, other in others do
					local d = (Vector3.new(other.X, 0, other.Z) - Vector3.new(cell.Position.X, 0, cell.Position.Z)).Magnitude
					if d < 12 then
						score -= (12 - d) / 2
					end
				end
				if score > bestScore then
					best, bestScore = cell, score
				end
			end
		end
		if best then
			return best
		end
		-- Nowhere fresh: a hole over fresh snow below, else the neighbor that lasts longest.
		if floor < mode.Floors then
			for _, dir in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				local cell = mode:CellAt(floor, cur.I + dir[1], cur.J + dir[2])
				if cell and cell.State == "Gone" and solid(mode:CellAt(floor + 1, cell.I, cell.J)) then
					return cell
				end
			end
		end
		local longest, left = nil, mode:TimeLeft(cur)
		for _, dir in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local cell = mode:CellAt(floor, cur.I + dir[1], cur.J + dir[2])
			if cell and cell.State ~= "Gone" and mode:TimeLeft(cell) > left then
				longest, left = cell, mode:TimeLeft(cell)
			end
		end
		return longest
	end

	return function(elapsed, dt)
		if not dumped then
			dumped = true
			dumpColliders()
		end
		for _, player in env.players do
			if not env.Alive(player) or mode.falling[player] then
				plans[player] = nil
				continue
			end
			local feet, _, root = feetOf(player)
			if not feet or root.Anchored then
				continue
			end
			local floor = mode:FloorAt(feet)
			if not floor then
				continue
			end
			if not floorsSeen[floor] then
				floorsSeen[floor] = true
				env.note(`{player.Name} reached floor {floor} at {math.floor(elapsed)}s`)
			end
			local plan = plans[player] or { Leave = env.rng:NextNumber(0.3, 0.45) }
			plans[player] = plan
			if plan.Floor ~= floor then
				plan.Floor, plan.Target = floor, nil
			end
			local here = root.Position
			-- On the way: a step at walking speed toward the target block's middle.
			local target = plan.Target
			if target then
				local way = Vector3.new(target.Position.X - here.X, 0, target.Position.Z - here.Z)
				if way.Magnitude < 0.3 then
					plan.Target = nil
					plan.Leave = env.rng:NextNumber(0.3, 0.45)
				else
					local step = here + way.Unit * math.min(way.Magnitude, SPEED * math.min(dt, 0.1))
					env.Move(player, step, step + way)
				end
				continue
			end
			local i, j = mode:GridOf(here)
			local cur = mode:CellAt(floor, i, j)
			if not cur or cur.State == "Gone" then
				continue -- over a hole: the mode drops it
			end
			if mode:TimeLeft(cur) <= plan.Leave then
				plan.Target = choose(player, floor, cur)
			end
		end
		for player in mode.falling do
			if not reported[player] then
				reported[player] = true
				dropped += 1
				env.note(`{player.Name} dropped by the server at {math.floor(elapsed)}s ({dropped} so far)`)
			end
		end
		for player in reported do
			if not mode.falling[player] then
				reported[player] = nil
			end
		end
		local second = math.floor(elapsed)
		if second % 5 == 0 and not milestones[second] then
			milestones[second] = true
			local left = { 0, 0, 0 }
			for _, cell in mode.cells do
				if cell.State ~= "Gone" then
					left[cell.Floor] += 1
				end
			end
			local on = { 0, 0, 0 }
			for _, player in ctx:GetAlivePlayers() do
				local playerFeet = feetOf(player)
				local floor = playerFeet and mode:FloorBelow(playerFeet)
				if floor then
					on[floor] += 1
				end
			end
			env.note(
				`t={second}s: blocks left {left[1]}/{left[2]}/{left[3]} of {mode.floorCount[1]} each, alive {ctx:AliveCount()} (floors {on[1]}/{on[2]}/{on[3]}), crumbling {tostring(
					mode.crumbling
				)}`
			)
		end
	end
end
