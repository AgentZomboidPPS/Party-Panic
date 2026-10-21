-- Scenario for round_harness.py --bot: in Fire Rope two stand-ins clear every pass, one on a quick
-- connection (0.06 s round trip) and one on a slow one (0.45 s), and time runs out 0.45 s after the
-- third pass: the quick one's verdict on it is in by then, the slow one's isn't. They both cleared
-- everything, so they must tie (a pass counts once it's settled for everyone): before the fix the
-- quick one got the jump and won on the jumps tie-break, so ping picked the winner.
--
--   python3 tools/checks/round_harness.py FireRope --players 2 \
--       --bot tools/checks/scenarios/FireRope_time_up.luau > rope.luau
return function(env)
	local pings = { 0.06, 0.45 }
	for index, player in env.players do
		player.__ping = pings[(index - 1) % #pings + 1]
	end
	local passes = {} -- every pass time seen in the schedule
	local count = 0
	return function()
		local rope = env.SharedJSON("Rope")
		if not rope or not rope.Segments then
			return
		end
		local now = env.ctx:Now()
		for _, segment in rope.Segments do
			if segment.A0 == 0 and not passes[segment.T0] then
				passes[segment.T0] = true
				count += 1
				if count == 3 then
					task.delay(math.max(0, segment.T0 + 0.45 - now), function()
						if not env.ctx.EndReason then
							env.note("time up 0.45 s after the third pass")
							env.ctx:End("TimeUp")
						end
					end)
				end
			end
		end
		-- Over every pass. The server sees a player's moves half a round trip late (FireRope:_sweep
		-- allows for it), so a stand-in, which the server moves itself, jumps that much later.
		for _, player in env.players do
			local position = env.Root(player)
			if not position or not env.Alive(player) then
				continue
			end
			local late = 0.03 + player.__ping / 2
			local up = false
			for at in passes do
				if now >= at - 0.22 + late and now <= at + 0.3 + late then
					up = true
				end
			end
			local base = Vector3.new(position.X, rope.FloorY + 3, position.Z)
			env.Move(player, if up then base + Vector3.new(0, 3, 0) else base)
		end
	end
end
