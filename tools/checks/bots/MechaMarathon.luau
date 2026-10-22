-- Test bot for Mecha-Marathon (tools/checks/round_harness.py): every stand-in player mashes WIND
-- at its own pace during the winding (players[1] too, so the client half has winds to show):
-- fast (11/s), steady (8/s), slow (5/s), one that sends nothing (its toy still hops off the pad)
-- and one auto-clicker (40/s), which must be held to the rate cap. With 4 or more players one
-- leaves mid-winding (its toy stays on its pad). It notes everyone's winds and flights and checks
-- that no flight overtook one with more winds, and lists what in the arena is solid.
local STYLES = { fast = 11, steady = 8, slow = 5, idle = 0, auto = 40 }
local ORDER = { "fast", "steady", "slow", "steady", "auto", "fast", "idle", "slow" }

return function(env)
	local ctx = env.ctx
	local mode = env.game
	local owed = {}
	local styleOf = {}
	local notedWinds, notedFlights, notedEnd = false, false, false
	for index, player in env.players do
		styleOf[player] = ORDER[(index - 1) % #ORDER + 1]
		owed[player] = 0
	end
	-- Nothing solid where nothing is drawn: list every collidable part in the arena by name, and any
	-- of them that is invisible.
	local solid, hidden = {}, {}
	for _, part in ctx.Arena:GetDescendants() do
		if part:IsA("BasePart") and part.CanCollide then
			solid[part.Name] = (solid[part.Name] or 0) + 1
			if part.Transparency >= 0.5 then
				table.insert(hidden, `{part.Name} {part.Size}`)
			end
		end
	end
	local names = {}
	for name, count in solid do
		table.insert(names, `{name} x{count}`)
	end
	table.sort(names)
	env.note(`collidable: {table.concat(names, ", ")}; invisible collidable: {#hidden} {table.concat(hidden, "; ")}`)
	return function(elapsed, dt)
		local now = ctx:Now()
		if mode.phase == "Wind" and now <= mode.windEnd then
			for _, player in env.players do
				if player.Parent and env.Alive(player) then
					owed[player] += STYLES[styleOf[player]] * (dt or 0.05)
					while owed[player] >= 1 do
						owed[player] -= 1
						env.Action(player, "Wind")
					end
				end
			end
		end
		if elapsed > 5 and #env.players >= 4 and not env.left then
			local leaver = env.players[#env.players]
			env.left = leaver
			env.note(`{leaver.Name} ({styleOf[leaver]}) leaves mid-winding`)
			env.Leave(leaver)
		end
		local winds = env.SharedJSON("Winds")
		if mode.phase ~= "Wind" and mode.phase ~= "Ready" and not notedWinds and type(winds) == "table" then
			notedWinds = true
			local parts = {}
			for _, player in env.players do
				table.insert(parts, `{player.Name}:{styleOf[player]}={winds[tostring(player.UserId)] or "?"}`)
			end
			env.note("winds " .. table.concat(parts, " "))
		end
		local flights = env.SharedJSON("Flights")
		if type(flights) == "table" and type(flights.Toys) == "table" and not notedFlights then
			notedFlights = true
			local list = {}
			for user, entry in flights.Toys do
				table.insert(list, { user = user, w = entry.W, m = entry.M })
			end
			table.sort(list, function(a, b)
				return a.m > b.m
			end)
			local parts, flipped = {}, 0
			for i, entry in list do
				table.insert(parts, `{entry.user}:{entry.w}w={entry.m}m`)
				for j = i + 1, #list do
					if list[j].w > entry.w then
						flipped += 1
					end
				end
			end
			env.note(`flights ({#list}) {table.concat(parts, " ")}; flipped leads: {flipped}`)
			local auto = 0
			for _, player in env.players do
				if styleOf[player] == "auto" and player.Parent then
					auto = math.max(auto, (flights.Toys[tostring(player.UserId)] or {}).W or 0)
				end
			end
			if auto > 0 then
				env.note(`auto-clicker counted {auto} winds (cap {mode.windEnd and 12 * 10 + 1 or "?"})`)
			end
		end
		if mode.phase == "Done" and not notedEnd then
			notedEnd = true
			env.note(`all landed at {math.floor(elapsed * 10) / 10}s; winner {tostring(env.Shared("Winner"))}`)
		end
	end
end
