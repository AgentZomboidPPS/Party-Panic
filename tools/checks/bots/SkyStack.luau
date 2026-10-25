-- Test bot for Sky Stack (tools/checks/round_harness.py): every stand-in player presses DROP for
-- its own tower in its own style (players[1] too, so the client half has a tower to show), sending
-- the moment it pressed like a real client does:
--   perfect  right over the middle on the first pass it can make: should reach the clouds first
--   steady   a little off (0.04 s), sometimes a pass late
--   sloppy   well off (0.1 s): its tower narrows fast and should crumble on the way up
--   spam     presses every frame from the moment a block appears: the double taps in the first
--            READY seconds must be ignored, and the rest are badly off
--   liar     presses 0.3 s late on the first pass but claims it pressed right over the middle:
--            the server must clamp the claim (Buzzer: half a round trip plus 0.1 s back at most),
--            so it still lands well off and crumbles
--   idle     never presses
-- With 4 or more players one leaves 6 s in. It notes every tower's floors, outs, places, combos and
-- gusts, and lists what in the arena is solid.
local ORDER = { "perfect", "steady", "sloppy", "spam", "liar", "steady", "idle", "perfect" }
local AIM = { perfect = 0, steady = 0.04, sloppy = 0.1 }

return function(env)
	local Stack = __require("Shared/Logic/SkyStack") -- the harness bundle's module loader
	local ctx = env.ctx
	local mode = env.game
	local styleOf = {}
	local planned = {}
	local presses = {}
	local combos, gusts = 0, 0
	local notedEnd = false
	for index, player in env.players do
		styleOf[player] = ORDER[(index - 1) % #ORDER + 1]
		presses[player] = 0
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

	local function gauss(): number
		local u = math.max(env.rng:NextNumber(), 1e-6)
		return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * env.rng:NextNumber())
	end

	return function(elapsed)
		local now = ctx:Now()
		for _, player in env.players do
			local tower = mode.towers and mode.towers[player]
			local slide = tower and tower.Slide
			if not slide or not player.Parent or not env.Alive(player) then
				continue
			end
			local style = styleOf[player]
			if style == "spam" then
				presses[player] += 1
				env.Action(player, "Drop", now, slide.Level)
				continue
			end
			if style == "idle" then
				continue
			end
			local plan = planned[player]
			if not plan or plan.Slide ~= slide then
				local target = Stack.NextMiddle(slide, math.max(now, slide.Start + Stack.READY + 0.05))
				if style == "steady" and env.rng:NextNumber() < 0.2 then
					target = Stack.NextMiddle(slide, target + 0.01)
				end
				local at = target + gauss() * (AIM[style] or 0)
				if style == "liar" then
					-- Presses badly late on the first pass and says it pressed right on the middle.
					at = target + 0.3
				end
				plan = { Slide = slide, At = at, Claim = if style == "liar" then target else at }
				planned[player] = plan
			end
			if not plan.Sent and now >= plan.At then
				plan.Sent = true
				presses[player] += 1
				env.Action(player, "Drop", plan.Claim, slide.Level)
			end
		end
		-- Combos and gusts as they happen.
		for _, player in env.players do
			local tower = mode.towers and mode.towers[player]
			if tower and tower.Last and tower.Last.C and tower.Last ~= planned[`combo{player.UserId}`] then
				planned[`combo{player.UserId}`] = tower.Last
				combos += 1
			end
			if tower and tower.GustFrom and tower.GustFrom ~= planned[`gust{player.UserId}`] then
				planned[`gust{player.UserId}`] = tower.GustFrom
				gusts += 1
			end
		end
		if elapsed > 6 and #env.players >= 4 and not env.left then
			local leaver = env.players[#env.players]
			env.left = leaver
			env.note(`{leaver.Name} ({styleOf[leaver]}) leaves`)
			env.Leave(leaver)
		end
		if (mode.phase == "Done" or ctx.EndReason or elapsed > 58) and not notedEnd then
			notedEnd = true
			local parts = {}
			for _, player in env.players do
				local tower = mode.towers[player]
				if tower then
					local top = tower.Top
					table.insert(
						parts,
						string.format(
							"%s:%s=%d%s%s w%.1fx%.1f p%d",
							player.Name,
							styleOf[player],
							#tower.Blocks,
							if tower.Place then ` #{tower.Place}@{tower.FinishedIn}s` else "",
							if tower.Out then " OUT" elseif tower.Gone then " GONE" else "",
							top.X1 - top.X0,
							top.Z1 - top.Z0,
							presses[player]
						)
					)
				end
			end
			env.note(
				`at {math.floor(elapsed * 10) / 10}s towers {table.concat(parts, " ")}; combos {combos}, gusts {gusts}`
			)
		end
	end
end
