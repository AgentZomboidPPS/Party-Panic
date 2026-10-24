-- Test bot for Capy Go Boom (tools/checks/round_harness.py): every stand-in player walks (env.Move, the
-- test server has no physics) toward a snack nearby or else its nearest rival, faces it, and fires BOOM
-- through the same action a client sends ("Boom" with the press time and, half the time, the direction
-- the mouse would give; the other half leaves it to the server: the way the capy faces, bent toward a
-- rival close to that line). The very first press has no direction at all and must still fire. With 3
-- or more players one leaves mid-round (their weight spills).
-- First thing, it lists anything in the arena that is solid but not drawn.
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local nextShot = {}
	local reported = {}
	local left = false
	local shots, first = 0, false
	local start = {}
	return function(elapsed)
		local now = ctx:Now()
		if not reported.solid then
			reported.solid = true
			-- Nothing may be solid where nothing is drawn (owner: "invisible stuff you can jump on").
			local solid, hidden = {}, {}
			for _, part in ctx.Arena:GetDescendants() do
				if part:IsA("BasePart") and part.CanCollide then
					solid[part.Name] = (solid[part.Name] or 0) + 1
					if part.Transparency > 0.5 then
						table.insert(hidden, part:GetFullName())
					end
				end
			end
			local names = {}
			for name, count in solid do
				table.insert(names, `{name}x{count}`)
			end
			table.sort(names)
			env.note(
				`collidable: {table.concat(names, " ")}; invisible+collidable: {if #hidden > 0
					then table.concat(hidden, ", ")
					else "none"}`
			)
		end
		if not mode.mass or not mode.center then
			return
		end
		if not first and env.players[1] then
			first = true -- a press with no direction: still a shot (the way the capy faces)
			env.Action(env.players[1], "Boom", now)
		end
		local center = mode.center
		local Rules = mode.Rules
		for _, player in env.players do
			if not env.Alive(player) or mode.mass[player] == nil then
				continue
			end
			local pos = env.Root(player)
			if not pos then
				continue
			end
			start[player] = start[player] or mode.mass[player]
			-- Goal: a snack within 14 studs, else the nearest rival.
			local goal, rival, rivalDistance = nil, nil, math.huge
			for _, snack in mode.snacks do
				local spot = center + Vector3.new(snack[3], 0, snack[4])
				local d = Vector3.new(spot.X - pos.X, 0, spot.Z - pos.Z).Magnitude
				if d < 14 and Rules.Landed(snack, now) and (not goal or d < (goal - pos).Magnitude) then
					goal = Vector3.new(spot.X, pos.Y, spot.Z)
				end
			end
			for _, other in env.players do
				if other ~= player and env.Alive(other) and mode.mass[other] ~= nil then
					local otherPos = env.Root(other)
					if otherPos then
						local d = (otherPos - pos).Magnitude
						if d < rivalDistance then
							rival, rivalDistance = otherPos, d
						end
					end
				end
			end
			local target = goal or rival
			if target then
				local flatTarget = Vector3.new(target.X, pos.Y, target.Z)
				local offset = flatTarget - pos
				local step = math.min(offset.Magnitude - (if goal then 0 else 12), 16 * 0.05)
				local nextPos = if offset.Magnitude > 1e-3 and step > 0 then pos + offset.Unit * step else pos
				local lookAt = if rival then Vector3.new(rival.X, nextPos.Y, rival.Z) else flatTarget
				if (lookAt - nextPos).Magnitude < 0.1 then
					lookAt = nextPos + Vector3.new(0, 0, -1)
				end
				env.Move(player, nextPos, lookAt)
			end
			-- Fire at a rival in range.
			if rival and rivalDistance < 45 and now >= (nextShot[player] or 0) then
				nextShot[player] = now + env.rng:NextNumber(0.8, 1.6)
				shots += 1
				if env.rng:NextNumber() < 0.5 then
					local aim = Vector3.new(rival.X - pos.X, 0, rival.Z - pos.Z)
					if aim.Magnitude > 0.1 then
						env.Action(player, "Boom", now, aim.Unit.X, aim.Unit.Z)
					end
				else
					env.Action(player, "Boom", now)
				end
			end
		end
		if not left and elapsed > 25 and #env.players >= 3 then
			left = true
			local leaver = env.players[#env.players]
			env.note(`{leaver.Name} leaves weighing {mode.mass[leaver] or 0} {Rules.UNIT}`)
			env.Leave(leaver)
		end
		local bucket = math.floor(elapsed / 15)
		if bucket >= 1 and not reported[`t{bucket}`] then
			reported[`t{bucket}`] = true
			local lying, total, top, low, pops = 0, 0, 0, math.huge, 0
			for _ in mode.snacks do
				lying += 1
			end
			for player, mass in mode.mass do
				total += mass
				top, low = math.max(top, mass), math.min(low, mass)
				pops += mode.pops[player] or 0
			end
			env.note(
				`{math.floor(elapsed)}s: weight {total} {Rules.UNIT} (top {top}, lowest {low}), pops {pops}, snacks lying {lying}`
			)
		end
		if elapsed > 40 and not reported.stats then
			reported.stats = true
			local lying, total, pops, gained = 0, 0, 0, 0
			for _ in mode.snacks do
				lying += 1
			end
			for player, mass in mode.mass do
				total += mass
				pops += mode.pops[player] or 0
				gained += mass - (start[player] or mass)
			end
			env.note(
				`presses {shots}, shells in flight {#mode.shells}, pops {pops}, weight {total} {Rules.UNIT} (gained {gained}), snacks lying {lying}`
			)
		end
	end
end
