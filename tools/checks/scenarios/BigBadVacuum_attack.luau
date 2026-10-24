-- Scenario for round_harness.py --bot: makes the Big Bad Vacuum start one particular attack at a known moment
-- and puts a few stand-ins in harm's way, so its warning zones (and the "MOVE!" edge) can be seen on the
-- client half with --client and an arena dump (--dump-at), then drawn with tools/preview/render.py:
--
--   sed 's/KIND_HERE/Sweep/; s/PHASE_HERE/1/' tools/checks/scenarios/BigBadVacuum_attack.luau > /tmp/atk.luau
--   python3 tools/checks/round_harness.py BigBadVacuum --players 4 --client --seconds 14 --dump-at 8.4 \
--       --bot /tmp/atk.luau > /tmp/atk_round.luau
--
-- KIND_HERE is one of Sweep, Whirl, Charge, Suction, Cord, Bombs; PHASE_HERE is 1..3 (the boss starts there).
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local KIND = "KIND_HERE"
	local PHASE = tonumber("PHASE_HERE") or 1
	local triggered = false
	return function(elapsed)
		local boss = mode.boss
		if not boss then
			return
		end
		if PHASE > 1 and boss.Phase < PHASE and boss.State ~= "Intro" then
			boss.Phase = PHASE
		end
		if boss.State == "Chase" and not triggered and elapsed > 6.5 then
			triggered = true
			boss.Until = math.huge
			mode:_beginAttack(ctx:Now(), KIND)
			-- Put the first two stand-ins in front of the boss, in the warning.
			local ahead = Vector3.new(math.cos(boss.Face), 0, math.sin(boss.Face))
			local side = Vector3.new(-ahead.Z, 0, ahead.X)
			local y = mode.center.Y + 3
			for index, player in env.players do
				if index <= 2 then
					local at = Vector3.new(boss.X, y, boss.Z) + ahead * (22 + index * 4) + side * (index - 1.5) * 6
					env.Move(player, at, Vector3.new(boss.X, y, boss.Z))
				end
			end
			env.note(`attack {KIND} forced at {string.format("%.1f", elapsed)}s, phase {boss.Phase}`)
		end
	end
end
