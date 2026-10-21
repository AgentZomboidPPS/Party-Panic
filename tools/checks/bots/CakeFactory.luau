-- Test bot for Cake Factory (tools/checks/round_harness.py): every stand-in player watches the
-- cakes coming to its machines (from the mode's own schedule) and presses Add like the client does.
-- Most press on time, some are sloppy (a wide timing error), and one in eight mashes the button to
-- check that mashing ruins cakes instead of making them. With 4 or more, one player leaves at 9 s
-- (their machines go to their teammates).
return function(env)
	local mode = env.game
	local ctx = env.ctx
	local state = {}
	local presses, reported = 0, false
	return function(elapsed)
		local now = ctx:Now()
		if not mode.t0 or mode.stopAt then
			return
		end
		local distance = mode:Distance(now)
		for index, player in env.players do
			local s = state[player]
			if not s then
				s = {
					Style = if index % 8 == 0 then "mash" elseif index % 3 == 0 then "sloppy" else "good",
					Planned = {},
					Queue = {},
					NextMash = now + 0.5,
				}
				state[player] = s
			end
			if not env.Alive(player) then
				continue
			end
			if s.Style == "mash" then
				if now >= s.NextMash then
					s.NextMash = now + env.rng:NextNumber(0.15, 0.4)
					env.Action(player, "Add")
					presses += 1
				end
				continue
			end
			local line, owned = mode:StationsOf(player)
			if line then
				for _, station in owned do
					local x = line.Stations[station].X
					local k = math.max(0, math.ceil((mode.START + distance - x) / mode.SPACING))
					if (s.Planned[station] or -1) < k then
						local at = mode:ArrivalTime(k, x)
						if at and at - now < 0.6 then
							s.Planned[station] = k
							local cake = line.Cakes[k]
							if not (cake and (cake.Bad or cake.N ~= station - 1)) then
								local err = if s.Style == "good"
									then env.rng:NextNumber(-0.06, 0.06)
									else env.rng:NextNumber(-0.3, 0.3)
								table.insert(s.Queue, at + err)
							end
						end
					end
				end
			end
			for position = #s.Queue, 1, -1 do
				if now >= s.Queue[position] then
					table.remove(s.Queue, position)
					env.Action(player, "Add")
					presses += 1
				end
			end
		end
		if elapsed > 9 and #env.players >= 4 and not env.left then
			local leaver = env.players[#env.players]
			env.left = leaver
			env.note(`{leaver.Name} leaves (team {tostring(leaver:GetAttribute("PP_Team"))})`)
			env.Leave(leaver)
		end
		if elapsed > 14 and not reported then
			reported = true
			local parts = {}
			for _, team in mode.order do
				local line = mode.lines[team]
				table.insert(
					parts,
					`{team} {line.Done} cakes/{line.Ruined} binned/{line.Layers} layers ({#line.Members}p)`
				)
			end
			env.note(`at 14s ({presses} presses): {table.concat(parts, ", ")}`)
		end
	end
end
