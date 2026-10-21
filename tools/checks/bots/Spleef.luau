-- Test bot for Spleef (tools/checks/round_harness.py): each stand-in walks (in small PivotTo steps,
-- no physics here) toward a rival on its floor and asks to break the blocks under the rival's feet,
-- like a player tapping them. Falls are the mode's own: a stand-in left over a hole is dropped by
-- the server (Spleef:_falls), so this bot never moves one that is falling.
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local plans = {}
	local asked, broke, dropped = 0, 0, 0
	local lastGone = 0
	local floorsSeen = {}
	local reported = {}
	local milestones = {}

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

	return function(elapsed)
		local now = os.clock()
		if not dumped then
			dumped = true
			dumpColliders()
		end
		local gone = 0
		for _, cell in mode.cells do
			if cell.State == "Gone" then
				gone += 1
			end
		end
		if gone > lastGone then
			broke += gone - lastGone
			lastGone = gone
		end
		for _, player in env.players do
			if not env.Alive(player) or mode.falling[player] then
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
			local plan = plans[player] or { NextDig = now + env.rng:NextNumber(1, 3), NextMove = 0 }
			plans[player] = plan
			-- A rival on the same floor: the nearest one.
			local rival, rivalRoot, best = nil, nil, math.huge
			for _, other in ctx:GetAlivePlayers() do
				if other == player or mode.falling[other] then
					continue
				end
				local otherFeet, _, otherRoot = feetOf(other)
				if otherFeet and mode:FloorAt(otherFeet) == floor then
					local d = (otherRoot.Position - root.Position).Magnitude
					if d < best then
						rival, rivalRoot, best = other, otherRoot, d
					end
				end
			end
			-- Walk toward the rival (or the middle), a short step at a time, only onto solid snow.
			if now >= plan.NextMove then
				plan.NextMove = now + 0.1
				local goal = if rivalRoot then rivalRoot.Position else mode.center
				local flatGoal = Vector3.new(goal.X - root.Position.X, 0, goal.Z - root.Position.Z)
				local keep = if rivalRoot then 7 else 3
				if flatGoal.Magnitude > keep then
					local step = root.Position + flatGoal.Unit * 1.5
					local i, j = mode:GridOf(step)
					local cell = mode:CellAt(floor, i, j)
					if cell and cell.State == "Solid" then
						env.Move(player, step, step + flatGoal)
					end
				end
			end
			-- Ask to break the block under the rival's feet.
			if rival and now >= plan.NextDig then
				plan.NextDig = now + env.rng:NextNumber(0.9, 2.2)
				local supports = mode:Supports(floor, rivalRoot.Position)
				local target = supports[1]
				if target and mode:CanBreak(root, feet, target, 0) then
					env.Action(player, "Break", target.Index)
					asked += 1
				end
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
		if second % 10 == 0 and not milestones[second] then
			milestones[second] = true
			env.note(
				`t={math.floor(elapsed)}s: asked {asked} breaks, {broke} blocks gone, alive {ctx:AliveCount()}, crumbling {tostring(
					mode.crumbling
				)}`
			)
		end
	end
end
