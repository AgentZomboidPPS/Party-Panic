-- Test bot for Parasol Plummet (tools/checks/round_harness.py): every stand-in player flies through
-- the same "Input" action a client sends. Each one chases the nearest coin it can see (steer under
-- it, shut the umbrella to drop onto a low one, open it to float up into a high one); the first ones
-- also try to dodge hammers, later ones don't, so some get bonked. No physics here, so their rigs are
-- put where the server has their faller (the stand-in client, Bot1, flies its own from the client
-- half). With 2 or more, one player leaves mid-round.
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local Sim = __require("Shared/Logic/ParasolPlummetSim") -- the harness bundle's module loader
	local sent = {}
	local inputs, reported = 0, {}
	return function(elapsed)
		local now = ctx:Now()
		for index, player in env.players do
			local f = mode.fallers and mode.fallers[player]
			if not f or not env.Alive(player) then
				continue
			end
			if mode.startAt and not (env.client and index == 1) then
				local steer, open = 0, f.Y < 0
				local bestD = math.huge
				for _, item in mode.items do
					if now < item.At then
						continue
					end
					local x, y = Sim.ItemAt(item, now + 0.6)
					local d = math.abs(x - f.X) + math.abs(y - f.Y) * 0.5
					if item.Kind == "Hammer" then
						if index <= 3 and d < 7 then
							steer = if f.X >= x then 1 else -1
							open = y < f.Y
							bestD = -1
						end
					elseif d < bestD then
						bestD = d
						steer = math.clamp((x - f.X) / 3, -1, 1)
						open = f.Y < y - 2.5
					end
				end
				steer = math.floor(steer * 4 + 0.5) / 4
				local key = `{steer}:{open}`
				if sent[player] ~= key then
					sent[player] = key
					env.Action(player, "Input", steer, open)
					inputs += 1
				end
			end
			if not (env.client and index == 1) then
				local frame = mode:_frame(f)
				env.Move(player, frame.Position, frame.Position + frame.LookVector)
			end
		end
		if elapsed > 9 and #env.players >= 2 and not env.left then
			local leaver = env.players[#env.players]
			env.left = leaver
			env.note(`{leaver.Name} leaves`)
			env.Leave(leaver)
		end
		if elapsed > 14 and not reported.summary then
			reported.summary = true
			local lines = {}
			local items = 0
			for _ in mode.items or {} do
				items += 1
			end
			for player, f in mode.fallers or {} do
				table.insert(
					lines,
					`{player.Name}:{f.Coins}c/{f.Bonks}b@{math.floor(f.X)},{math.floor(f.Y)}{if f.Open then "o" else "s"}`
				)
			end
			table.sort(lines)
			env.note(`t14: {inputs} inputs, {items} items in the air; {table.concat(lines, " ")}`)
		end
	end
end
