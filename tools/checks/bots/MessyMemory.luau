-- Test bot for Messy Memory: every stand-in player puts the toys back like a player would (most
-- right, some in a neighbouring slot), one move at a time, then shuts its curtain. Player 2 also
-- sends junk the server must ignore (a toy that doesn't exist, a slot off the shelf, NaN, a stale
-- move number, a move with its curtain shut, a curtain "maybe"); player 3 peeks at player 1;
-- player 4 leaves halfway through placing; player 5 shuts its curtain early, then opens it again to
-- change an answer. The notes list each player's server-side score at the end.
return function(env)
	local Rules = __require("Shared/Logic/MessyMemory") -- the harness bundle's module loader
	local mode = env.game
	local plans = {}
	local seqs = {}
	local nextAt = {}
	local junk, rejected = 0, 0
	local left, reopened, peeked = false, false, false
	local reported = false
	return function(elapsed)
		if not mode.booths or mode.phase ~= "Place" then
			if mode.phase == "Done" or mode.phase == "Reveal" then
				if not reported and mode.phase == "Reveal" then
					reported = true
					local line = {}
					for index, player in env.players do
						local booth = mode.booths[player]
						if booth then
							table.insert(
								line,
								`P{index}={Rules.Correct(booth.Positions, mode.answer)}{if booth.Open
									then ""
									else "(shut)"}`
							)
						end
					end
					env.note(`reveal: {table.concat(line, " ")}; junk {junk} (moved {rejected})`)
				end
			end
			return
		end
		local info = mode.phaseInfo
		local now = env.ctx:Now()
		for index, player in env.players do
			local booth = mode.booths[player]
			if not player.Parent or not booth or booth.Left then
				continue
			end
			if not plans[player] then
				local plan = {}
				for toy, slot in mode.answer do
					local good = env.rng:NextNumber() < 0.55 + 0.07 * (index % 6)
					table.insert(plan, { toy, if good then slot else (slot % Rules.SLOTS) + 1 })
				end
				plans[player] = plan
				seqs[player] = 0
				nextAt[player] = elapsed + 1 + env.rng:NextNumber(0, 1.5)
			end
			if elapsed < nextAt[player] then
				continue
			end
			nextAt[player] = elapsed + env.rng:NextNumber(0.6, 1.6)
			if index == 2 and env.rng:NextNumber() < 0.4 then
				junk += 1
				local before = table.clone(booth.Positions)
				local kind = env.rng:NextInteger(1, 6)
				if kind == 1 then
					env.Action(player, "Move", seqs[player] + 1, 99, 1)
				elseif kind == 2 then
					env.Action(player, "Move", seqs[player] + 1, 1, 40)
				elseif kind == 3 then
					env.Action(player, "Move", seqs[player] + 1, 0 / 0, 2)
				elseif kind == 4 then
					env.Action(player, "Move", 0, 1, 3) -- a stale move number
				elseif kind == 5 then
					env.Action(player, "Curtain", "maybe")
				else
					env.Action(player, "Move", seqs[player] + 1, 2.5, "x")
				end
				for toy, pos in booth.Positions do
					if before[toy] ~= pos then
						rejected += 1
					end
				end
				continue
			end
			if index == 3 and not peeked then
				peeked = true
				env.Action(player, "Peek", env.players[1].UserId)
				env.note(`P3 peeks at P1`)
			end
			if index == 5 and not reopened and #plans[player] == 4 then
				if booth.Open then
					env.Action(player, "Curtain", false)
					-- A move with the curtain shut must not land.
					local before = booth.Positions[plans[player][1][1]]
					seqs[player] += 1
					env.Action(player, "Move", seqs[player], plans[player][1][1], plans[player][1][2])
					if booth.Positions[plans[player][1][1]] ~= before then
						env.note("BUG: a move landed behind a shut curtain")
					end
				else
					reopened = true
					env.Action(player, "Curtain", true)
					env.note("P5 shut its curtain, then opened it again")
				end
				continue
			end
			local item = table.remove(plans[player], 1)
			if item then
				seqs[player] += 1
				env.Action(player, "Move", seqs[player], item[1], item[2])
			elseif booth.Open then
				env.Action(player, "Curtain", false)
			end
		end
		if not left and #env.players >= 4 and now > info.T0 + 8 then
			left = true
			env.note(`{env.players[4].Name} leaves mid-round`)
			env.Leave(env.players[4])
		end
	end
end
