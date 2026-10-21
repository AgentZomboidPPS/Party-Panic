-- Bot for Fire Rope: bots "jump" (move up 3 studs) around each bottom pass of the rope. Each bot
-- has its own skill; as the rope speeds up they miss more often. No physics in Luau execution, so
-- a jump is a PivotTo up and back down.
-- With 4 or more, the last one steps off the bridge 5 s in and stays beside it at deck height, as if
-- standing on scenery (nothing falls here): it must be out about 2 s later, with no jumps counted.
return function(env)
	local ctx = env.ctx
	local skill = {}
	for index, player in env.players do
		skill[player] = 0.995 - index * 0.012
	end
	local planned = {} -- passTime -> true once decided
	local jumping = {} -- player -> { from, to }
	local decided = 0
	local stray = if #env.players >= 4 then env.players[#env.players] else nil
	local strayAt = nil

	return function(elapsed)
		local rope = env.SharedJSON("Rope")
		if not rope or not rope.Segments then
			return
		end
		local now = ctx:Now()
		if stray and not strayAt and elapsed > 5 and env.Alive(stray) then
			strayAt = elapsed
			local position = env.Root(stray)
			if position then
				env.Move(stray, Vector3.new(position.X, rope.FloorY + 3, rope.Axis[3] + 10))
				env.note(`{stray.Name} steps off the bridge onto scenery at {math.floor(elapsed * 10) / 10}s`)
			end
		elseif stray and strayAt and not env.Alive(stray) then
			local jumps = env.Mine(stray, "Jumps") or 0
			env.note(`{stray.Name} out at {math.floor(elapsed * 10) / 10}s ({jumps} jumps)`)
			stray = nil
		end
		-- Pass times are the starts of segments with A0 == 0.
		for _, segment in rope.Segments do
			if segment.A0 == 0 and not planned[segment.T0] and segment.T0 - now < 0.5 then
				planned[segment.T0] = true
				decided += 1
				local period = 2 * math.pi / segment.W
				for _, player in env.players do
					if env.Alive(player) then
						local chance = skill[player] - math.max(0, 1.6 - period) * 0.12
						if env.rng:NextNumber() < chance then
							jumping[player] = { From = segment.T0 - 0.22, To = segment.T0 + 0.3 }
						end
					end
				end
			end
		end
		for _, player in env.players do
			local jump = jumping[player]
			local position = env.Root(player)
			if not position or not env.Alive(player) or (player == stray and strayAt) then
				continue -- (the one beside the bridge stays put: no jumping, no falling)
			end
			local base = Vector3.new(position.X, rope.FloorY + 3, position.Z)
			if jump and now >= jump.From and now <= jump.To then
				env.Move(player, base + Vector3.new(0, 3, 0))
			elseif math.abs(position.Y - base.Y) > 0.01 and position.Y < rope.FloorY + 10 then
				env.Move(player, base)
				if jump and now > jump.To then
					jumping[player] = nil
				end
			end
		end
	end
end
