-- Scenario for round_harness.py --bot: in Arrow Ambush the archer's arrow comes down right on the
-- runner, who stands still on a slow phone (0.4 s round trip), and time runs out 0.1 s later: the
-- runner is judged where their screen showed them when it landed, 0.2 s after the landing, and
-- again 0.1 s later, after the buzzer. The arrow came down before the buzzer, so the tag must count
-- (RoundContext.HoldEnd): the runner is tagged and the archers win. Before the fix the round ended
-- first and the runner "won" untouched. During the held moment the archer shoots again: a shot after
-- the buzzer must not be fired.
--
--   python3 tools/checks/round_harness.py ArrowAmbush --players 2 \
--       --bot tools/checks/scenarios/ArrowAmbush_buzzer.luau > arrow.luau
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local archer, runner = nil, nil
	local shotAt = -math.huge
	local sentFrom = nil -- mode.arrowId when the last shot was sent (actions arrive a moment later)
	local buzzer = nil
	local lateFrom = nil
	return function(elapsed)
		if not archer then
			for _, player in env.players do
				local role = env.Mine(player, "Role")
				if role == "Archer" then
					archer = player
				elseif role == "Runner" then
					runner = player
					player.__ping = 0.4
				end
			end
			if not archer or not runner then
				archer, runner = nil, nil
				return
			end
		end
		local now = ctx:Now()
		local target = env.Root(runner)
		-- Shoot at the runner until an arrow's flight isn't cut short by a board.
		if not buzzer and sentFrom and mode.arrowId > sentFrom then
			local planned = mode.arrows[#mode.arrows]
			sentFrom = nil
			if planned.Board == 0 then
				buzzer = planned.T1 + 0.1
				env.note(`clean shot at the runner: lands {string.format("%.2f", planned.T1 - now)} s from now`)
			else
				env.note("shot blocked by a board; again")
			end
		end
		if not buzzer and not sentFrom and target and elapsed > 1 and now - shotAt > 1.2 then
			shotAt = now
			sentFrom = mode.arrowId
			env.Action(archer, "Shoot", target.X, target.Z)
		elseif not buzzer and sentFrom and now - shotAt > 1 then
			sentFrom = nil -- never arrived: try again
		end
		if buzzer and now >= buzzer and not ctx.EndReason then
			-- (The server knows time is up from its first TimeRanOut; the shot comes after that.)
			local timeUpAt = ctx.TimeUpAt
			if not lateFrom and timeUpAt and now >= timeUpAt + 0.05 and target then
				mode.nextShot[archer] = 0 -- past the archer's cooldown: only the buzzer can stop it
				lateFrom = mode.arrowId
				env.Action(archer, "Shoot", target.X, target.Z)
			end
			if ctx.TimeRanOut then
				ctx:TimeRanOut("TimeUp")
			else
				ctx:End("TimeUp")
			end
			if ctx.EndReason then
				local late = if not lateFrom
					then "not tried"
					elseif mode.arrowId > lateFrom then "FIRED (it shouldn't be)"
					else "refused"
				env.note(
					`time up 0.1 s after the landing; the round ended {string.format("%.2f", now - buzzer)} s after the buzzer; runner tagged: {tostring(
						mode.tagged[runner] == true
					)}; a shot after the buzzer: {late}`
				)
			end
		end
	end
end
