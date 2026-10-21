-- Test bot for Pump & Pop (tools/checks/round_harness.py): every stand-in player pumps in its own
-- rhythm, pressing Down and Up like the client does. Some hold well (perfect pumps), some let go
-- early, some hold too long, and one in eight mashes (quick taps) to check mashing loses to rhythm.
-- Like the client, a press waits out the spring and the mode's minimum cycle since the last one.
-- Bot7 plays a hacked client: it fires Down and Up straight at the server as fast as the server
-- takes them, ignoring the spring and the cycle, to check that can't out-pump rhythm either.
return function(env)
	local mode = env.game
	local ctx = env.ctx
	local state = {}
	local reported = false
	return function(elapsed)
		local now = ctx:Now()
		for index, player in env.players do
			local s = state[player]
			if not s then
				local style = if index == 7
					then "spam"
					elseif index % 8 == 0 then "mash"
					elseif index % 3 == 0 then "sloppy"
					else "good"
				s = { Style = style, Next = now + env.rng:NextNumber(0.2, 1), Down = false, DownAt = 0, UpAt = 0 }
				state[player] = s
			end
			if not env.Alive(player) then
				continue
			end
			if s.Style == "spam" then
				-- Down and Up on alternate steps (0.05 s apart): each action every 0.1 s, under the
				-- server's rate limit.
				s.Down = not s.Down
				env.Action(player, if s.Down then "Down" else "Up")
				continue
			end
			if s.Down then
				if now >= s.UpAt then
					s.Down = false
					env.Action(player, "Up")
					s.Next = math.max(now + mode.SPRING, s.DownAt + mode.CYCLE) + 0.03
					s.Next += env.rng:NextNumber(0, if s.Style == "good" then 0.15 else 0.4)
				end
			elseif now >= s.Next then
				local hold
				if s.Style == "mash" then
					hold = 0.08
				elseif s.Style == "sloppy" then
					hold = env.rng:NextNumber(0.2, 0.9)
				else
					hold = env.rng:NextNumber(0.47, 0.58)
				end
				s.Down = true
				s.DownAt = now
				s.UpAt = now + hold
				env.Action(player, "Down")
			end
		end
		-- With 4 or more, one player leaves mid-round: their team needs less air and plays on.
		if elapsed > 9 and #env.players >= 4 and not env.left then
			local leaver = env.players[#env.players]
			env.left = leaver
			env.note(`{leaver.Name} leaves (team {tostring(leaver:GetAttribute("PP_Team"))})`)
			env.Leave(leaver)
		end
		if elapsed > 12 and not reported then
			reported = true
			local parts = {}
			for _, team in { "Red", "Blue", "Green", "Yellow" } do
				local air = env.Shared("Air_" .. team)
				if air ~= nil then
					table.insert(parts, `{team} {math.floor(air * 100)}%`)
				end
			end
			env.note(`air at 12s: {table.concat(parts, ", ")}`)
			-- The hacked client's air against the best honest pumper's (it must not be ahead).
			local spammer = env.players[7]
			local cheat = spammer and mode.pumpers[spammer]
			if cheat then
				local best = 0
				for player, pumper in mode.pumpers do
					if player ~= spammer then
						best = math.max(best, pumper.Air)
					end
				end
				local air, bestAir = math.floor(cheat.Air * 10) / 10, math.floor(best * 10) / 10
				env.note(`spam {spammer.Name}: air {air} in {cheat.Pumps} pumps at 12s; best rhythm player {bestAir}`)
			end
		end
		local popped = env.Shared("Popped")
		if popped and not env.poppedNoted then
			env.poppedNoted = true
			env.note(`{popped} popped at {math.floor(elapsed * 10) / 10}s`)
		end
	end
end
