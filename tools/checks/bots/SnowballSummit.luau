-- Test bot for Snowball Summit (tools/checks/round_harness.py): the stand-in players stroll round the
-- summit rolling snowballs (Build), turn to a rival and let go (Throw). The test server has no
-- physics, so a stand-in that gets hit is flown along the mode's own knock arc (game:FlightAt, the
-- same one the server flies bots on): past the rim it falls and the mode puts it out.
return function(env)
	local ctx = env.ctx
	local game = env.game
	local state = {}
	local throws, hits, last = 0, 0, 0
	local seenKnock = {}
	return function(elapsed)
		local now = ctx:Now()
		local dt = math.clamp(elapsed - last, 0, 0.2)
		last = elapsed
		local center = game.center
		local radius = game.radius
		if not center or not radius then
			return
		end
		for index, player in env.players do
			if not env.Alive(player) then
				continue
			end
			local root = env.Root(player)
			if not root then
				continue
			end
			-- Replay a knock (people fly on their own device; here, on the mode's arc).
			local knock = game.knocks and game.knocks[player]
			if knock then
				if not seenKnock[knock] then
					seenKnock[knock] = true
					hits += 1
				end
				local spot = game:FlightAt(knock, now)
				if spot then
					env.Move(player, spot, spot + knock.V)
					continue
				end
				game.knocks[player] = nil
			end
			if env.client and index == 1 then
				continue -- the client half plays this one
			end
			local me = state[player]
			if not me then
				me = { Goal = root, Until = 0, ThrowAt = 0 }
				state[player] = me
			end
			if elapsed > me.Until or (Vector3.new(me.Goal.X - root.X, 0, me.Goal.Z - root.Z)).Magnitude < 1.5 then
				local angle = env.rng:NextNumber(0, math.pi * 2)
				local distance = env.rng:NextNumber(0.1, 0.7) * radius
				me.Goal = center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
				me.Until = elapsed + env.rng:NextNumber(1, 3)
			end
			local holding = game.held and game.held[player] ~= nil
			if not holding and elapsed > 3 and env.rng:NextNumber() < 0.05 then
				env.Action(player, "Build")
				me.ThrowAt = elapsed + env.rng:NextNumber(1.2, 3.5)
			elseif holding and elapsed > me.ThrowAt then
				-- Turn to the nearest rival and let go.
				local best, bestD = nil, math.huge
				for _, other in env.players do
					local at = other ~= player and env.Alive(other) and env.Root(other)
					if at then
						local d = (at - root).Magnitude
						if d < bestD then
							best, bestD = at, d
						end
					end
				end
				if best then
					local dir = Vector3.new(best.X - root.X, 0, best.Z - root.Z)
					if dir.Magnitude > 0.1 then
						dir = dir.Unit
						env.Move(player, root, root + dir)
						env.Action(player, "Throw", dir.X, dir.Z)
						throws += 1
					end
				end
				continue
			end
			local step = Vector3.new(me.Goal.X - root.X, 0, me.Goal.Z - root.Z)
			if step.Magnitude > 0.1 then
				local move = step.Unit * math.min(step.Magnitude, 14 * dt)
				local spot = Vector3.new(root.X + move.X, center.Y + 3, root.Z + move.Z)
				env.Move(player, spot, spot + move)
			end
		end
		if elapsed > 20 and not env.reported then
			env.reported = true
			env.note(`stand-ins threw {throws} snowballs, {hits} hits so far`)
		end
	end
end
