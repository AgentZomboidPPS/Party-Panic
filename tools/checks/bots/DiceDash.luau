-- Test bot for Dice Dash (tools/checks/round_harness.py): each stand-in player presses ROLL a
-- moment after its turn starts (one in ten lets the die stop by itself), and the notes say how the
-- race went: turns played, rolls pressed and auto, where everyone is, who finished when.
-- env: ctx, game, players, rng, note(text), client, Action(player, name, ...), Root, Move, Shared,
-- SharedJSON, Mine, Alive, Leave. The returned function runs every 0.05 s.
return function(env)
	local ctx = env.ctx
	local game = env.game
	local lastTurn = nil
	local pressAt = {}
	local presses, autos, finishes = 0, 0, 0
	local seenFinish = {}
	return function(elapsed)
		local turn = env.SharedJSON("Turn")
		local racers = env.SharedJSON("Racers")
		if not turn or not racers then
			return
		end
		if turn.N ~= lastTurn then
			if lastTurn and game.racers then
				local tiles = {}
				for _, racer in game.racers do
					if not racer.Gone then
						table.insert(tiles, tostring(racer.Pos))
						if racer.Auto then
							autos += 1
						end
					end
				end
				env.note(`turn {lastTurn} done at {string.format("%.1f", elapsed)}s: tiles {table.concat(tiles, ",")}`)
			end
			lastTurn = turn.N
			for _, player in env.players do
				pressAt[player] = if env.rng:NextNumber() < 0.1
					then math.huge
					else turn.A + env.rng:NextNumber(0.2, 2.6)
			end
		end
		for _, player in env.players do
			local mine = racers.R[tostring(player.UserId)]
			if mine and mine.F and not seenFinish[player] then
				seenFinish[player] = true
				finishes += 1
				env.note(`{player.Name} finishes {mine.F} at {string.format("%.1f", elapsed)}s`)
			end
			if
				mine
				and mine.D == nil
				and not mine.F
				and turn.M == nil
				and ctx:Now() >= (pressAt[player] or math.huge)
			then
				pressAt[player] = math.huge
				env.Action(player, "Roll")
				presses += 1
			end
		end
		if elapsed > 20 and not env.reported then
			env.reported = true
			env.note(`by 20s: {presses} presses, {autos} auto rolls, {finishes} home`)
		end
	end
end
