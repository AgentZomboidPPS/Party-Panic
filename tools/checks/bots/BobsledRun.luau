-- Test bot for Bobsled Run (tools/checks/round_harness.py): every stand-in player leans the next
-- curve's way once its window opens, through the same action a client sends. The first ones lean
-- well; later ones are sloppier (wrong way, late or not at all), so crews take some curves clean
-- and bump others. No physics here, so their rigs are put in their seats (the stand-in client, Bot1,
-- seats its own from the client half). With 4 or more, one rider leaves mid-run.
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local BobsledCourse = __require("Shared/Logic/BobsledCourse") -- the harness bundle's module loader
	local planned = {}
	local leans, results, reported = 0, {}, {}
	return function(elapsed)
		local now = ctx:Now()
		for index, player in env.players do
			local rider = mode.riders and mode.riders[player]
			local sled = rider and mode.sleds[rider.Team]
			if not sled or not env.Alive(player) then
				continue
			end
			local skill = math.clamp(1 - index * 0.07, 0.2, 0.95)
			local curve = mode.course.Curves[sled.Next]
			if curve and mode.startAt and not sled.Place and planned[player] ~= curve.Index then
				local seconds = (curve.D0 - sled.D) / math.max(sled.V, 1)
				if seconds <= BobsledCourse.OPEN - 0.25 then
					planned[player] = curve.Index
					local roll = env.rng:NextNumber()
					if roll < skill then
						env.Action(player, "Lean", curve.Dir)
						leans += 1
					elseif roll < skill + (1 - skill) * 0.5 then
						env.Action(player, "Lean", -curve.Dir)
						leans += 1
					end
				end
			end
			if not (env.client and index == 1) then
				local seat = mode:_seat(player)
				if seat then
					env.Move(player, seat.Position, seat.Position + seat.LookVector)
				end
			end
		end
		for _, team in mode.order or {} do
			local sled = mode.sleds[team]
			if sled.Place and not reported[team] then
				reported[team] = true
				env.note(
					`{team} home {sled.Place} in {string.format("%.1f", sled.Time or 0)}s (clean {sled.Clean}, bumps {sled.Bumps}, crew {#sled.Riders})`
				)
			end
			results[team] = `{team}:{math.floor(sled.D)}@{math.floor(sled.V)} c{sled.Clean}/b{sled.Bumps}`
		end
		if elapsed > 9 and #env.players >= 4 and not env.left then
			local leaver = env.players[#env.players]
			env.left = leaver
			env.note(`{leaver.Name} leaves (team {tostring(leaver:GetAttribute("PP_Team"))})`)
			env.Leave(leaver)
		end
		if elapsed > 14 and not reported.summary then
			reported.summary = true
			local lines = {}
			for _, line in results do
				table.insert(lines, line)
			end
			table.sort(lines)
			env.note(`t14: {leans} leans; {table.concat(lines, " ")}`)
		end
	end
end
