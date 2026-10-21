-- Test bot for Prime Cut (tools/checks/round_harness.py): every stand-in player steers its team's
-- knife towards where it thinks the steak's middle is (the true 50:50 line plus a misjudgement that
-- grows with its index), through the same "Nudge" action a client sends (numbered batches with the
-- press time), a few notches at a time. The stand-in client (Bot1) is left to the client half. It
-- notes each steak's results, one stand-in leaves mid-round (with 3 or more), and at the start it
-- lists any collidable part in the arena that isn't a visible surface (there should be none).
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local marks, seqs, nudges = {}, {}, 0
	local reported = {}
	return function(elapsed)
		if not reported.collision and elapsed > 0.5 then
			reported.collision = true
			local suspicious = {}
			local solid = 0
			for _, item in ctx.Arena:GetDescendants() do
				if item:IsA("BasePart") and item.CanCollide then
					solid += 1
					if item.Transparency > 0.5 or item:IsA("MeshPart") or item:IsA("UnionOperation") then
						table.insert(suspicious, `{item:GetFullName()} ({item.ClassName}, t={item.Transparency})`)
					end
				end
			end
			env.note(`collidable parts: {solid}; invisible or mesh: {#suspicious} {table.concat(suspicious, "; ")}`)
		end
		local now = ctx:Now()
		local steak = mode.steak
		if steak and mode.phase == "Steer" and not mode.locked then
			for index, player in env.players do
				if (env.client and index == 1) or not env.Alive(player) then
					continue
				end
				local member = mode.members[player]
				local station = member and mode.stations[member.Team]
				if not station then
					continue
				end
				local key = `{mode.cut}:{player.Name}`
				if not marks[key] then
					local spread = 0.15 + index * 0.12
					marks[key] = steak.Even + env.rng:NextNumber(-spread, spread)
				end
				if env.rng:NextNumber() < 0.35 and now < mode.closeAt - 0.3 then
					local gap = marks[key] - station.X
					if math.abs(gap) > 0.08 then
						seqs[player] = (seqs[player] or 0) + 1
						local count = math.clamp(math.floor(math.abs(gap) / 0.1 + 0.5), 1, 3)
						env.Action(player, "Nudge", if gap > 0 then 1 else -1, count, seqs[player], now)
						nudges += 1
					end
				end
			end
		end
		for _, entry in mode.history or {} do
			if not reported[entry.N] then
				reported[entry.N] = true
				local parts = {}
				for _, team in mode.order do
					local result = entry.R[team]
					if result then
						table.insert(parts, `{team} {string.format("%.1f", result.P)}% (off {result.O})`)
					end
				end
				env.note(
					`steak {entry.N} ({mode.plan[entry.N].Id}): {table.concat(parts, ", ")}; best {table.concat(
						entry.W,
						"+"
					)}; {nudges} nudges so far`
				)
			end
		end
		if elapsed > 12 and #env.players >= 3 and not env.left then
			local leaver = env.players[#env.players]
			env.left = leaver
			env.note(`{leaver.Name} leaves (team {tostring(leaver:GetAttribute("PP_Team"))})`)
			env.Leave(leaver)
		end
	end
end
