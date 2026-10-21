-- Test bot for Tanks! (tools/checks/round_harness.py): every stand-in player drives toward its
-- nearest enemy with some wander, stops at a fighting distance, aims at it (a little off) and fires
-- when it has a shell, and lays a mine now and then, through the same actions a client sends. The
-- tanks are the server's anyway (no physics needed); the rigs are stood in their hatches here for
-- the arena snapshot (the stand-in client, Bot1, seats its own, and its inputs are numbered above
-- anything the client sends, so the client follows the server's tank). With 3 or more, one player
-- leaves mid-round. First thing, it lists anything in the arena that is solid but not drawn.
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local seqs, nextFire, nextMine, wander = {}, {}, {}, {}
	local shots, mines = 0, 0
	local reported = {}
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
		for index, player in env.players do
			local tank = mode.tanks and mode.tanks[player]
			if not tank or tank.Out or not env.Alive(player) then
				continue
			end
			local best, bestD = nil, math.huge
			for _, other in mode.list do
				if other ~= tank and not other.Out then
					local d = math.sqrt((other.X - tank.X) ^ 2 + (other.Z - tank.Z) ^ 2)
					if d < bestD then
						best, bestD = other, d
					end
				end
			end
			if not wander[player] or now >= wander[player].Until then
				wander[player] = { Angle = env.rng:NextNumber(-1, 1), Until = now + env.rng:NextNumber(0.8, 2) }
			end
			local mx, mz, aim = 0, 0, tank.Aim
			if best then
				local dx, dz = best.X - tank.X, best.Z - tank.Z
				local toward = math.atan2(dx, dz) + wander[player].Angle
				local push = if bestD > 30 then 1 elseif bestD < 16 then -0.8 else 0.4
				mx, mz = math.sin(toward) * push, math.cos(toward) * push
				aim = math.atan2(-dx, -dz) + env.rng:NextNumber(-0.45, 0.45)
			end
			seqs[player] = (seqs[player] or 1e6) + 1
			env.Action(player, "In", seqs[player], mx, mz, aim)
			-- Only with a clear line (a shot into a brick would bounce straight back at it).
			local clear = best and mode.Field.Clear(mode.field, tank.X, tank.Z, best.X, best.Z, 0.6)
			if clear then
				-- Not a shot whose ricochet would come straight back (a player would see that coming).
				local back = mode.Field.Path(mode.field, tank.X, tank.Z, aim).Segments[2]
				local tx, tz = tank.X - back.X, tank.Z - back.Z
				local along = tx * back.DX + tz * back.DZ
				if along > 0 and along < back.Length and math.abs(tx * back.DZ - tz * back.DX) < 6 then
					clear = false
				end
			end
			if clear and now >= (nextFire[player] or 0) and tank.Shells < 2 then
				nextFire[player] = now + env.rng:NextNumber(1, 2.4)
				env.Action(player, "Fire", aim, now)
				shots += 1
			end
			if best and bestD < 25 and now >= (nextMine[player] or now + 4) then
				nextMine[player] = now + env.rng:NextNumber(5, 9)
				env.Action(player, "Mine")
				mines += 1
			elseif not nextMine[player] then
				nextMine[player] = now + env.rng:NextNumber(3, 6)
			end
			if not (env.client and index == 1) then
				local seat = mode:_seat(tank)
				env.Move(player, seat.Position, seat.Position + seat.LookVector)
			end
		end
		if elapsed > 10 and #env.players >= 3 and not env.left then
			local leaver = env.players[#env.players]
			env.left = leaver
			env.note(`{leaver.Name} leaves`)
			env.Leave(leaver)
		end
		if elapsed > 14 and not reported.summary then
			reported.summary = true
			local alive, hits, live = 0, 0, 0
			for _, tank in mode.list do
				if not tank.Out then
					alive += 1
				end
				hits += tank.Hits
			end
			for _, shell in mode.shells do
				if not shell.Dead then
					live += 1
				end
			end
			env.note(`t14: {shots} shots, {mines} mines, {hits} hits, {alive} tanks left, {live} shells flying`)
		end
	end
end
