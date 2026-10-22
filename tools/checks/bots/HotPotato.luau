-- Test bot for Hot Potato (tools/checks/round_harness.py): moves the stand-in players at walking speed
-- (holders 10% faster, as the mode sets) and sends the passes a real client would. A holder chases the
-- nearest player it may pass to, tags them once within the client's tag reach and now and then THROWs
-- at someone in range in front; everyone else runs from holders near them (each at its own angle) or
-- strolls. Luau execution has no physics, so players move with env.Move. The notes count tags, throws,
-- refusals and blasts so a round can be checked from its summary.
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local Rules = __require("Shared/Logic/HotPotato") -- the harness bundle's module loader
	local SPEED = 16
	local veer = {}
	local goals = {}
	for _, player in env.players do
		veer[player] = env.rng:NextNumber(-0.9, 0.9)
	end
	local counts = { Tag = 0, Throw = 0, Boom = 0 }
	local lastPotatoes = {}
	local reported = false

	local function flat(v: Vector3): Vector3
		return Vector3.new(v.X, 0, v.Z)
	end
	local function onLawn(goal: Vector3): Vector3
		local offset = flat(goal - mode.center)
		local distance = math.clamp(offset.Magnitude, 7, mode.radius - 3)
		local direction = if offset.Magnitude > 0.1 then offset.Unit else Vector3.new(1, 0, 0)
		local at = mode.center + direction * distance
		return Vector3.new(at.X, mode.center.Y + 3, at.Z)
	end
	local function step(player, root, goal: Vector3, speed: number, dt: number)
		local offset = flat(goal - root.Position)
		if offset.Magnitude < 0.2 then
			return
		end
		local move = offset.Unit * math.min(offset.Magnitude, speed * dt)
		local at = onLawn(root.Position + move)
		env.Move(player, at, at + offset.Unit)
	end

	return function(elapsed)
		local dt = 0.05
		if not mode.center or not mode.potatoes then
			return
		end
		local now = ctx:Now()
		-- Count blasts: a potato that vanished while its fuse had run out.
		local current = {}
		for _, potato in mode.potatoes do
			current[potato.Id] = potato
		end
		for id, potato in lastPotatoes do
			if not current[id] and now >= potato.FuseEnd - 0.1 then
				counts.Boom += 1
			end
		end
		lastPotatoes = current

		for _, player in env.players do
			if not env.Alive(player) then
				continue
			end
			local position = env.Root(player) -- a Vector3 here
			if not position then
				continue
			end
			local root = { Position = position }
			local potato = mode:HolderOf(player)
			if potato then
				local best, bestRoot, bestDistance = nil, nil, math.huge
				for _, other in ctx:GetAlivePlayers() do
					if other ~= player and mode:CanTake(potato, other, now) then
						local _, _, otherRoot = ctx:GetCharacter(other)
						if otherRoot then
							local distance = flat(otherRoot.Position - root.Position).Magnitude
							if distance < bestDistance then
								best, bestRoot, bestDistance = other, otherRoot, distance
							end
						end
					end
				end
				if bestRoot then
					step(player, root, bestRoot.Position, SPEED * Rules.SPEED, dt)
					if now >= potato.LockUntil then
						if bestDistance <= Rules.CLIENT_TAG then
							env.Action(player, "Tag", best.UserId)
							counts.Tag += 1
						elseif bestDistance <= Rules.CLIENT_THROW and env.rng:NextNumber() < 0.03 then
							env.Action(player, "Throw", best.UserId)
							counts.Throw += 1
						end
					end
				end
				continue
			end
			local away = Vector3.zero
			for _, other in mode.potatoes do
				local holder = other.Holder
				local holderRoot = if holder then select(3, ctx:GetCharacter(holder)) else nil
				if holderRoot then
					local offset = flat(root.Position - holderRoot.Position)
					if offset.Magnitude < 14 and offset.Magnitude > 0.1 then
						away += offset.Unit * (14 - offset.Magnitude)
					end
				end
			end
			if away.Magnitude > 0.1 then
				local direction = CFrame.Angles(0, veer[player], 0):VectorToWorldSpace(away.Unit)
				step(player, root, root.Position + direction * 8, SPEED, dt)
			else
				local goal = goals[player]
				if not goal or flat(goal - root.Position).Magnitude < 2 then
					local angle = env.rng:NextNumber(0, math.pi * 2)
					goal = onLawn(
						mode.center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * env.rng:NextNumber(8, 30)
					)
					goals[player] = goal
				end
				step(player, root, goal, SPEED * 0.7, dt)
			end
		end
		if elapsed > 40 and not reported then
			reported = true
			env.note(
				`by 40s: {counts.Tag} tag presses, {counts.Throw} throws, {counts.Boom} blasts, {#mode.potatoes} potatoes in play, {ctx:AliveCount()} left`
			)
		end
	end
end
