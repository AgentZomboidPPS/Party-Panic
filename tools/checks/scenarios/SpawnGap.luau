-- Scenario for round_harness.py --bot: how far above what it stands on each character starts the
-- round (owner: "Also I did spawn hovering. Ive had reports of that. can we fix that?", at the start
-- of a mini-game). At the first tick (GO, before anything has moved anyone: no physics on the test
-- servers) every stand-in's soles are measured against the first solid thing under them, the way
-- its device's ArrivalController looks (straight down, what its root collides with), and so is a
-- respawn spot from the mode's Respawn hook if it has one (the root 3 studs over the spot, as
-- RoundContext puts it). Collidable parts the rays can't see (CanQuery off) under a character are
-- listed too: a device's ground check misses those. One line per character:
--   SPAWNGAP <who> gap <studs from soles to ground> on <part> [unseen <part> <gap>]
-- "PROBLEM" marks a gap over 1 stud (it starts in the air) or nothing solid within 60 studs; one the
-- mode has in hand (anchored or PlatformStanding: on a ball, a board, in a sled) only says so.
--
--   python3 tools/checks/round_harness.py BigBadVacuum --players 8 --seconds 2 \
--       --bot tools/checks/scenarios/SpawnGap.luau > gap.luau
return function(env)
	local ctx = env.ctx
	local done = false

	local function legsOf(humanoid: Humanoid, root: BasePart): number
		if humanoid.RigType == Enum.HumanoidRigType.R6 then
			return 3
		end
		return humanoid.HipHeight + root.Size.Y / 2
	end

	local function characters(): { Instance }
		local list = {}
		for _, model in workspace:GetDescendants() do
			if model:IsA("Humanoid") and model.Parent then
				table.insert(list, model.Parent)
			end
		end
		return list
	end

	-- Collidable parts the rays can't see whose box covers `at` (x, z) under it: the highest top.
	local function unseenUnder(at: Vector3): (BasePart?, number?)
		local best, bestTop = nil, -math.huge
		for _, part in ctx.Arena:GetDescendants() do
			if part:IsA("BasePart") and part.CanCollide and not part.CanQuery then
				local cframe, size = part.CFrame, part.Size
				local extent = Vector3.new(
					math.abs(cframe.RightVector.X) * size.X
						+ math.abs(cframe.UpVector.X) * size.Y
						+ math.abs(cframe.LookVector.X) * size.Z,
					math.abs(cframe.RightVector.Y) * size.X
						+ math.abs(cframe.UpVector.Y) * size.Y
						+ math.abs(cframe.LookVector.Y) * size.Z,
					math.abs(cframe.RightVector.Z) * size.X
						+ math.abs(cframe.UpVector.Z) * size.Y
						+ math.abs(cframe.LookVector.Z) * size.Z
				) / 2
				local p = cframe.Position
				local top = p.Y + extent.Y
				if
					math.abs(at.X - p.X) <= extent.X
					and math.abs(at.Z - p.Z) <= extent.Z
					and top <= at.Y + 0.5
					and top > bestTop
				then
					best, bestTop = part, top
				end
			end
		end
		return best, if best then bestTop else nil
	end

	local function measure(who: string, at: Vector3, legs: number, group: string, ridden: boolean?)
		local rays = RaycastParams.new()
		rays.FilterType = Enum.RaycastFilterType.Exclude
		rays.FilterDescendantsInstances = characters()
		rays.RespectCanCollide = true
		rays.CollisionGroup = group
		local hit = workspace:Raycast(at, Vector3.new(0, -60, 0), rays)
		local soles = at.Y - legs
		local text
		local bad = false
		if hit then
			local gap = soles - hit.Position.Y
			bad = gap > 1 and not ridden
			text = string.format("gap %.2f on %s", gap, hit.Instance:GetFullName():gsub("^Workspace%.", ""))
		else
			bad = true
			text = "nothing solid within 60"
		end
		local unseen, top = unseenUnder(at)
		if unseen and top and (not hit or top > hit.Position.Y + 0.05) then
			text ..= string.format(" unseen %s %.2f", unseen.Name, soles - top)
		end
		env.note(`SPAWNGAP{if bad then " PROBLEM" else ""} {who} {text}`)
	end

	return function()
		if done then
			return
		end
		done = true
		for index, player in env.players do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not root or not humanoid then
				env.note(`SPAWNGAP {index} no character`)
				continue
			end
			local legs = legsOf(humanoid, root)
			local state = if root.Anchored
				then " (anchored)"
				elseif humanoid.PlatformStand then " (platformstand)"
				else ""
			measure(`start{index}{state}`, root.Position, legs, root.CollisionGroup, state ~= "")
			if index <= 3 and ctx.Hooks.Respawn then
				local ok, spot = pcall(ctx.Hooks.Respawn, player)
				if ok and typeof(spot) == "CFrame" then
					measure(`respawn{index}`, spot.Position + Vector3.new(0, 3, 0), legs, root.CollisionGroup)
				end
			end
		end
	end
end
