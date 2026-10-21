-- Test bot for Slaparazzi (tools/checks/round_harness.py): walks the stand-in players toward the
-- photo frame at walking speed (some aim well, some badly, a few wander off) and slaps whoever is in
-- reach now and then, through the same action a client sends. Luau execution has no physics, so
-- players move with env.Move and a slap's throw doesn't move anyone here; the notes report photos,
-- points and slaps landed so a round can be checked from its summary.
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local Rules = __require("Shared/Logic/Slaparazzi") -- the harness bundle's module loader
	local aims = {}
	for index, player in env.players do
		aims[player] = if index % 5 == 0 then 9 else env.rng:NextNumber(0, 3)
	end
	local lastPhoto = 0
	local sent = 0
	return function()
		local frame = env.SharedJSON("Frame")
		if not frame then
			return
		end
		local now = ctx:Now()
		local fx, fz = Rules.FrameAt(frame, now)
		for index, player in env.players do
			if env.Alive(player) and (index > 1 or not env.client) then
				local root = env.Root(player)
				if root then
					local angle = index * 2.4
					local goal =
						Vector3.new(fx + math.cos(angle) * aims[player], root.Y, fz + math.sin(angle) * aims[player])
					local step = goal - root
					local flatStep = Vector3.new(step.X, 0, step.Z)
					if flatStep.Magnitude > 0.3 then
						local move = flatStep.Unit * math.min(flatStep.Magnitude, 16 * 0.05)
						env.Move(player, root + move, goal)
					end
					if env.rng:NextNumber() < 0.04 then
						for _, other in env.players do
							local there = other ~= player and env.Alive(other) and env.Root(other)
							if there and Vector3.new(there.X - root.X, 0, there.Z - root.Z).Magnitude < 5 then
								env.Move(player, root, there)
								env.Action(player, "Slap", other.UserId)
								sent += 1
								break
							end
						end
					end
				end
			end
		end
		local photo = env.SharedJSON("Photo")
		if photo and photo.N ~= lastPhoto then
			lastPhoto = photo.N
			local scored, landed = 0, 0
			for _, shot in photo.Shots do
				if shot.P > 0 then
					scored += 1
				end
			end
			for _, count in mode.slaps do
				landed += count
			end
			env.note(
				`photo {photo.N}: {scored} scored of {#photo.Shots} near the frame; slaps sent {sent}, landed {landed}`
			)
		end
	end
end
