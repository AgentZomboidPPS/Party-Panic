-- Test bot for Last Dancer (tools/checks/round_harness.py): every stand-in player taps the chart like a
-- client would (with the client's synced press time), in one of five styles: "good" (nearly every note,
-- ~30 ms off), "ok" (85% of the notes, ~70 ms off), "sloppy" (65%, ~100 ms off), "idle" (never taps) and
-- "masher" (all four pads every 70 ms). The idle one and the masher must be the first cut, the good
-- ones must be the last dancers; it checks that and notes who is cut when. With 4 or more players, one
-- leaves mid-round and the cuts go on without them.
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local Chart = __require("Shared/LastDancerChart") -- the harness bundle's module loader
	local styles = { "good", "ok", "sloppy", "idle", "masher", "good", "ok", "sloppy", "good", "ok", "good", "sloppy" }
	local state = {}
	local reported = {}
	local out = {}
	local function gauss(sigma)
		local u, v = math.max(env.rng:NextNumber(), 1e-6), env.rng:NextNumber()
		return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v) * sigma
	end
	return function(elapsed)
		local go = mode.go
		if not go then
			return
		end
		local now = ctx:Now()
		local rel = now - go
		for index, player in env.players do
			if env.client and index == 1 then
				continue -- driven by the client half
			end
			local s = state[player]
			if not s then
				s = { Style = styles[(index - 1) % #styles + 1], Next = 1, Pending = {}, Mash = 0 }
				state[player] = s
			end
			if not env.Alive(player) then
				if not out[player] then
					out[player] = true
					env.note(`{player.Name} ({s.Style}) is out at {string.format("%.1f", rel)}s`)
				end
				continue
			end
			local notes = Chart.Notes
			if s.Style == "masher" then
				if rel > 1 and now >= s.Mash then
					s.Mash = now + 0.07
					for lane = 1, 4 do
						env.Action(player, "Tap", lane, now)
					end
				end
			elseif s.Style ~= "idle" then
				local hit, sigma = 0.97, 0.03
				if s.Style == "ok" then
					hit, sigma = 0.85, 0.07
				elseif s.Style == "sloppy" then
					hit, sigma = 0.65, 0.1
				end
				while s.Next <= #notes and notes[s.Next].T < rel + 0.5 do
					local note = notes[s.Next]
					s.Next += 1
					if env.rng:NextNumber() < hit then
						table.insert(
							s.Pending,
							{ At = go + note.T + math.clamp(gauss(sigma), -0.15, 0.15), Lane = note.Lane }
						)
					end
				end
				for k = #s.Pending, 1, -1 do
					local tap = s.Pending[k]
					if now >= tap.At then
						table.remove(s.Pending, k)
						env.Action(player, "Tap", tap.Lane, now)
					end
				end
			end
		end
		if elapsed > 20 and #env.players >= 4 and not env.left then
			local leaver = env.players[#env.players]
			env.left = leaver
			env.note(`{leaver.Name} leaves`)
			env.Leave(leaver)
		end
		for _, at in { 20, 40, 60 } do
			if elapsed > at and not reported[at] then
				reported[at] = true
				local parts = {}
				for _, player in env.players do
					local slot = mode.slots[player]
					local s = state[player]
					if slot and s then
						table.insert(
							parts,
							`{s.Style}:{math.floor(slot.State.Groove * 100)}%{if env.Alive(player) then "" else "(out)"}`
						)
					end
				end
				env.note(`groove at {at}s: {table.concat(parts, " ")}`)
			end
		end
	end
end
