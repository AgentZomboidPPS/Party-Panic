-- Test bot for Minecart Mayhem (tools/checks/round_harness.py): every stand-in player rides through
-- the same actions a client sends. Riders differ on purpose: most pick the shortcut at every
-- junction, some pick the TNT or dead-end way, some never press (the long way); most jump the gaps in
-- the middle of the take-off marker, every fourth rider never jumps (it falls and comes back), and
-- half lean into the bends. No physics here, so their rigs are put where the server has them (the
-- stand-in client, Bot1, seats its own from the client half). With 3 or more, one rider leaves
-- mid-race. It also notes, once, everything solid in the arena (only the station deck should be)
-- and, at 20 s, every rider's state.
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local reported = {}
	local leaning = {}
	local counts = { Leans = 0, Jumps = 0 }
	local noted = false

	local function noteSolids()
		local groups = {}
		for _, part in ctx.Arena:GetDescendants() do
			if part:IsA("BasePart") and (part.CanCollide or part.CanQuery or part.CanTouch) then
				local size = part.Size
				local label =
					`{part.Name} {math.floor(size.X)}x{math.floor(size.Y * 10) / 10}x{math.floor(size.Z)} transparency {part.Transparency} collide {part.CanCollide}`
				groups[label] = (groups[label] or 0) + 1
			end
		end
		local lines = {}
		for label, count in groups do
			table.insert(lines, `{count} x {label}`)
		end
		table.sort(lines)
		env.note(`solid or queryable parts in the arena: {if #lines > 0 then table.concat(lines, "; ") else "none"}`)
		local tiles = {}
		for _, tile in mode.course.Tiles do
			table.insert(tiles, tile.K .. (if tile.O then "/" .. tile.O else ""))
		end
		env.note(`course: {table.concat(tiles, " ")}`)
	end

	return function(elapsed)
		if not noted and mode.course then
			noted = true
			noteSolids()
		end
		local Track = mode.Track
		local now = ctx:Now()
		local count = #env.players
		for index, player in env.players do
			local rider = mode.riders and mode.riders[player]
			if not rider or rider.Gone or not env.Alive(player) or not mode.racing then
				continue
			end
			if not rider.Finish and rider.DownUntil == 0 and not rider.Back then
				-- Junctions: shortcut riders (most), contrary riders (every fifth) and no-pressers.
				local want = 0
				local junction, away = Track.NextSwitch(mode.course, rider, Track.CHOOSE)
				if junction and away < 25 then
					local tile = mode.course.Tiles[junction]
					local long = tile.L or 1
					if index % 5 == 2 then
						want = -long -- always the other way, whatever it is
					elseif index % 5 ~= 4 then
						want = if tile.O == "Short" then -long else 0
					end
				end
				local tile = mode.course.Tiles[rider.Tile]
				if want == 0 and index % 2 == 0 then
					want = Track.LeanAt(tile, rider.B, rider.S + 2)
				end
				if leaning[player] ~= want then
					leaning[player] = want
					counts.Leans += 1
					env.Action(player, "Lean", want, now)
				end
				-- Gaps: jump in the middle of the window (every fourth rider never jumps).
				if index % 4 ~= 0 then
					for _, feature in tile.Features do
						if feature.K == "Gap" and rider.V > 1 then
							local front = feature.S - Track.HALF_BASE - rider.S
							local lead = Track.JUMP_TIME / 2
								- ((feature.S1 - feature.S) + Track.WHEELBASE) / (2 * rider.V)
							if front > 0 and front / rider.V <= lead + 0.025 and now > rider.JumpAt + 1.2 then
								counts.Jumps += 1
								env.Action(player, "Jump", now)
							end
						end
					end
				end
			end
			if not (env.client and index == 1) then
				local seat = mode:_seat(rider)
				env.Move(player, seat.Position, seat.Position + seat.LookVector)
			end
			if rider.Place and not reported[player] then
				reported[player] = true
				env.note(
					`{player.Name} home {rider.Place} in {string.format("%.1f", (rider.Finish or 0) - mode.startAt)}s (falls {rider.Falls}, blasts {rider.Blasts}, dead ends {rider.Bumps}, dashes {rider.Dashes}, shortcuts {rider.Shortcuts})`
				)
			end
		end
		if elapsed > 12 and count >= 3 and not env.left then
			local leaver = env.players[count]
			env.left = leaver
			env.note(`{leaver.Name} leaves mid-race`)
			env.Leave(leaver)
		end
		if elapsed > 20 and not reported.summary then
			reported.summary = true
			local parts = {}
			for _, player in env.players do
				local rider = mode.riders[player]
				if rider then
					table.insert(
						parts,
						`{player.Name}:t{rider.Tile}b{rider.B}@{math.floor(rider.V)} f{rider.Falls}/x{rider.Blasts}/d{rider.Bumps}/s{rider.Shortcuts}`
					)
				end
			end
			env.note(`at 20s: {table.concat(parts, " ")} (leans {counts.Leans}, jumps {counts.Jumps})`)
		end
	end
end
