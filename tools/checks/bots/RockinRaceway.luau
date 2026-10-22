-- Test bot for Rockin' Raceway (tools/checks/round_harness.py): every stand-in player rides through
-- the same actions a client sends. Each gallops from a full meter and lets go at its own carrot
-- level (the last few never let go, so they spin out), and hops the hurdles, the first ones on time
-- and later ones sloppily (bumps). No physics here, so their rigs are put where the server has them
-- (the stand-in client, Bot1, seats its own from the client half). With 3 or more, one rider leaves
-- mid-race.
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local galloping = {}
	local hopped = {}
	local counts = { Gallops = 0, Hops = 0 }
	local reported = {}
	return function(elapsed)
		local now = ctx:Now()
		local count = #env.players
		for index, player in env.players do
			local rider = mode.riders and mode.riders[player]
			if not rider or rider.Gone or not env.Alive(player) or not mode.racing then
				continue
			end
			if not rider.Finish then
				local letGo = if index > count - 2 and count >= 4 then -1 else 5 + (index % 5) * 8
				if galloping[player] then
					if rider.C <= letGo then
						galloping[player] = false
						env.Action(player, "Gallop", false)
					end
				elseif rider.C >= 95 and now >= rider.SpinUntil then
					galloping[player] = true
					counts.Gallops += 1
					env.Action(player, "Gallop", true)
				end
				-- The next hurdle: hop when it's about 0.35 s away (later riders hop late or not at all).
				local next = rider.Next
				local panel = mode.panels[next]
				while panel and panel.K ~= "H" do
					next += 1
					panel = mode.panels[next]
				end
				if panel and not hopped[tostring(player.UserId) .. ":" .. next] and rider.V > 1 then
					local seconds = (panel.D - rider.D) / rider.V
					local hopAt = if index % 3 == 0 then 1.0 else 0.35
					if seconds <= hopAt then
						hopped[tostring(player.UserId) .. ":" .. next] = true
						counts.Hops += 1
						env.Action(player, "Hop", now)
					end
				end
			end
			if not (env.client and index == 1) then
				local frame = mode:_frame(rider.D, rider.Offset, 3)
				env.Move(player, frame.Position, frame.Position + frame.LookVector)
			end
			if rider.Place and not reported[player] then
				reported[player] = true
				env.note(
					`{player.Name} home {rider.Place} in {string.format("%.1f", (rider.Finish or 0) - mode.startAt)}s (spins {rider.Spins}, dashes {rider.Dashes}, bumps {rider.Bumps})`
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
						`{player.Name}:{math.floor(rider.D)}@{math.floor(rider.V)} c{math.floor(rider.C)} s{rider.Spins}/d{rider.Dashes}/b{rider.Bumps}`
					)
				end
			end
			env.note(`at 20s: {table.concat(parts, " ")} (gallops {counts.Gallops}, hops {counts.Hops})`)
		end
	end
end
