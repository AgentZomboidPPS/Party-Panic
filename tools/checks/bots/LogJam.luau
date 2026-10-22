-- Test bot for Log Jam (tools/checks/round_harness.py): every stand-in player watches its mill's
-- shared state ("Mill_<Team>") and, on its turn, presses the shape after a reaction time, like the
-- client does (with the client's synced press time). Styles: "good" (quick, right), "slow", "sloppy"
-- (wrong a quarter of the time) and two cheats to check they lose: "masher" (tries all four shapes in
-- turn as fast as the server takes them) and "early" (presses before its prompt shows). With 4 or
-- more, one player leaves mid-round and the turn goes on without them.
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local state = {}
	local reported = false
	return function(elapsed)
		local now = ctx:Now()
		for index, player in env.players do
			local s = state[player]
			if not s then
				local style = if index == 3
					then "masher"
					elseif index == 6 then "early"
					elseif index % 4 == 0 then "sloppy"
					elseif index % 5 == 0 then "slow"
					else "good"
				s = { Style = style, Key = "", At = math.huge, Symbol = 1, Seq = 0, Phase = "", Next = 1 }
				state[player] = s
			end
			if not env.Alive(player) then
				continue
			end
			local team = player:GetAttribute("PP_Team")
			local mill = team and env.SharedJSON("Mill_" .. team)
			if type(mill) ~= "table" then
				continue
			end
			local phase = mill.Phase
			local mine = (phase == "Place" and mill.Placer == player.UserId)
				or (phase == "Chop" and mill.Chopper == player.UserId)
			if not mine then
				continue
			end
			local showAt = math.max(mill.ShowAt, mill.JamUntil)
			if s.Style == "masher" then
				if now >= mill.JamUntil then
					env.Action(player, "Press", s.Next, mill.Seq, phase, now)
					s.Next = s.Next % 4 + 1
				end
				continue
			end
			local key = `{mill.Seq}:{phase}:{mill.JamUntil}`
			if s.Key ~= key then
				s.Key = key
				local reaction = if s.Style == "slow"
					then env.rng:NextNumber(0.8, 1.2)
					else env.rng:NextNumber(0.35, 0.6)
				s.At = if s.Style == "early" and env.rng:NextNumber() < 0.5 then now else showAt + reaction
				s.Symbol = mill.Symbol
				if s.Style == "sloppy" and env.rng:NextNumber() < 0.25 then
					s.Symbol = mill.Symbol % 4 + 1
				end
				s.Seq, s.Phase = mill.Seq, phase
			end
			if now >= s.At then
				s.At = math.huge
				env.Action(player, "Press", s.Symbol, s.Seq, s.Phase, now)
			end
		end
		if elapsed > 9 and #env.players >= 4 and not env.left then
			local leaver = env.players[#env.players]
			env.left = leaver
			env.note(`{leaver.Name} leaves (team {tostring(leaver:GetAttribute("PP_Team"))})`)
			env.Leave(leaver)
		end
		if elapsed > 20 and not reported then
			reported = true
			local parts = {}
			for _, team in mode.order do
				local station = mode.stations[team]
				table.insert(parts, `{team} {station.Logs} ({#station.Members} left, {station.Phase})`)
			end
			env.note(`logs at 20s: {table.concat(parts, ", ")}`)
			local lines = {}
			for index, player in env.players do
				local stats = mode.stats[player]
				if stats and index <= 8 then
					table.insert(
						lines,
						`{state[player] and state[player].Style or "?"} p{stats.Placed}/c{stats.Chopped}/j{stats.Jams}`
					)
				end
			end
			env.note(`players: {table.concat(lines, ", ")}`)
		end
	end
end
