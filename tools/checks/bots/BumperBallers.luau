-- Test bot for Bumper Ballers: steers each stand-in's ball with the Steer action (the server rolls
-- stand-ins' balls itself, like bots', since Luau execution has no physics). Most chase the nearest
-- rival and pull back from the rim; a few are careless so ring-outs happen.
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local careless = {}
	for index, player in env.players do
		careless[player] = index % 3 == 0
	end
	local reported = {}
	return function(elapsed)
		local entries = mode.entries
		if not entries then
			return
		end
		for _, player in env.players do
			local me = entries[player]
			if not env.Alive(player) or not me or me.Out then
				continue
			end
			local best, bestDistance = nil, math.huge
			for other, entry in entries do
				if other ~= player and not entry.Out then
					local d = (entry.Position - me.Position).Magnitude
					if d < bestDistance then
						best, bestDistance = entry, d
					end
				end
			end
			local desired = Vector3.zero
			if best then
				local gap = best.Position - me.Position
				desired = Vector3.new(gap.X, 0, gap.Z).Unit
			end
			local fromCenter = me.Position - mode.center
			fromCenter = Vector3.new(fromCenter.X, 0, fromCenter.Z)
			if not careless[player] and fromCenter.Magnitude > mode.islandRadius - 9 then
				desired = -fromCenter.Unit
			end
			env.Action(player, "Steer", desired.X, desired.Z)
		end
		for _, mark in { 5, 20, 40 } do
			if elapsed > mark and not reported[mark] then
				reported[mark] = true
				env.note(
					`t={mark}: bumps {mode.bumpCount or 0}, ring-outs {mode.ringOuts or 0}, alive {ctx:AliveCount()}`
				)
			end
		end
	end
end
