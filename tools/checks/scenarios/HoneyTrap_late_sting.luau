-- Scenario for round_harness.py --bot: in Honey Trap the first player to take a turn takes a
-- honeycomb (the scenario puts one at the bottom of the vine), and time runs out 1 s later, while
-- the bees are still chasing them. They must be out (RoundContext.Eliminate's showAfter): before
-- the fix they were only put out 2.1 s after the sting, so time-up counted them as a survivor.
--
--   python3 tools/checks/round_harness.py HoneyTrap --players 2 \
--       --bot tools/checks/scenarios/HoneyTrap_late_sting.luau > honey.luau
return function(env)
	local stung = false
	return function()
		if stung then
			return
		end
		local turn = env.SharedJSON("Turn")
		local now = env.ctx:Now()
		if not turn or turn.Result ~= nil or now < turn.T0 + 0.5 then
			return
		end
		stung = true
		local mode = env.game
		mode.vine = string.sub(mode.vine, 1, mode.next - 1) .. "H" .. string.sub(mode.vine, mode.next + 1)
		for _, player in env.players do
			if player.UserId == turn.User then
				local flips = math.floor((now - turn.T0) / turn.Flip)
				env.Action(player, "Hit", ((turn.First - 1 + flips) % 2) + 1)
				env.note(`{player.Name} takes the honeycomb`)
			end
		end
		task.delay(1, function()
			if not env.ctx.EndReason then
				env.note("time up 1 s after the sting")
				env.ctx:End("TimeUp")
			end
		end)
	end
end
