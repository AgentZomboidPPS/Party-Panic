-- Bot for Fire Rope: bots "jump" (move up 3 studs) around each bottom pass of the rope. Each bot
-- has its own skill; as the rope speeds up they miss more often. No physics in Luau execution, so
-- a jump is a PivotTo up and back down.
return function(env)
	local ctx = env.ctx
	local skill = {}
	for index, player in env.players do
		skill[player] = 0.995 - index * 0.012
	end
	local planned = {} -- passTime -> true once decided
	local jumping = {} -- player -> { from, to }
	local decided = 0

	return function()
		local rope = env.SharedJSON("Rope")
		if not rope or not rope.Segments then
			return
		end
		local now = ctx:Now()
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
			if not position or not env.Alive(player) then
				continue
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
