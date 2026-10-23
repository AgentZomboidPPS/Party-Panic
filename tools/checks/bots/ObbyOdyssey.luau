-- Test bot for Obby Odyssey (tools/checks/round_harness.py). Luau execution has no physics, so the
-- stand-in players hop from piece to piece along the course with env.Move (each at its own pace, onto a
-- piece of the next row), walking the long pieces (the bridge, the pipes) in short steps so the balls and
-- bars get their chance to hit them. Once, a stand-in jumps into the pool, to see it put back on its
-- checkpoint. The notes say who finished where, the falls and hits the server counted, and whether the
-- client half really swings the balls, turns the bars and blinks the blocks.
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local Course = __require("Shared/Logic/ObbyOdyssey") -- the harness bundle's module loader
	local nextHop = {}
	local at = {} -- the piece each stand-in was last put on
	local pace = {}
	local walking = {}
	for index, player in env.players do
		pace[player] = 0.6 + (index % 5) * 0.15 -- (about a person's pace, so the bots get the whole round)
	end
	local reported = {}
	local dunked: any = nil
	local dunkChecked = false
	local clientChecked = false
	local ballRest: Vector3? = nil

	local function put(player, x: number, top: number, z: number)
		local o = mode.origin
		env.Move(player, o + Vector3.new(x, top + 3, z), o + Vector3.new(x, top + 3, z + 10))
	end

	local orderChecks = 0
	local launched = 0
	local fallsNoted = 0
	local lastFall = {}
	return function(elapsed)
		if not mode.runners or not mode.origin then
			return
		end
		-- The HUD's order (from MG_Runners, ranked as the client half ranks it) against the server's.
		if orderChecks < 3 and elapsed > 5 + orderChecks * 5 then
			orderChecks += 1
			local snapshot = env.SharedJSON("Runners")
			local hud, server = {}, {}
			for key, data in if snapshot then snapshot.R else {} do
				table.insert(
					hud,
					{ Key = key, Score = if data.F then 1e6 - data.F else (data.S or 0) * 1e4 + (data.P or 0) }
				)
			end
			table.sort(hud, function(a, b)
				return a.Score > b.Score
			end)
			for player, runner in mode.runners do
				table.insert(server, { Key = tostring(player.UserId), Name = player.Name, Runner = runner })
			end
			table.sort(server, function(a, b)
				return a.Runner.Stage * 1e4 + a.Runner.Progress > b.Runner.Stage * 1e4 + b.Runner.Progress
			end)
			local line = {}
			for index, item in server do
				local hudIndex = 0
				for at, entry in hud do
					if entry.Key == item.Key then
						hudIndex = at
					end
				end
				table.insert(
					line,
					`{item.Name} ✓{item.Runner.Stage} {math.floor(item.Runner.Progress)} (hud {hudIndex}, server {index})`
				)
			end
			env.note(`order at {math.floor(elapsed)}s: {table.concat(line, ", ")}`)
		end
		-- Where the real bots fall (the first few), to see which jumps they miss.
		for bot, runner in mode.runners do
			local fell = runner.FellAt
			if fell and fell ~= lastFall[bot] and fallsNoted < 24 and not table.find(env.players, bot) then
				lastFall[bot] = fell
				fallsNoted += 1
				env.note(
					`  fall: {bot.Name} from row {fell.Y} at x {string.format("%.1f", fell.X)}, z {string.format(
						"%.1f",
						fell.Z
					)}`
				)
			end
		end
		local now = ctx:Now()
		local t = now - mode.epoch
		-- The client half (when it runs) swings the balls: a ball's part leaves where the server built it.
		if env.client and not clientChecked then
			local folder = ctx.Arena:FindFirstChild("Balls")
			local model = folder and folder:FindFirstChild("Ball1")
			local ball = model and model:FindFirstChild("Ball")
			if ball and not ballRest then
				ballRest = ball.Position
			elseif ball and ballRest and elapsed > 3 then
				clientChecked = true
				local bar = ctx.Arena:FindFirstChild("Bars") and ctx.Arena.Bars:FindFirstChild("Bar1")
				local barPart = bar and bar:FindFirstChild("Bar")
				local blink = ctx.Arena:FindFirstChild("Blinks") and ctx.Arena.Blinks:FindFirstChild("Blink1_1")
				env.note(
					`client check: Ball1 moved {string.format("%.1f", (ball.Position - ballRest).Magnitude)} studs; `
						.. `Bar1 turned to {if barPart
							then string.format(
								"%.0f",
								math.deg(math.atan2(barPart.CFrame.XVector.Z, barPart.CFrame.XVector.X))
							)
							else "?"} deg; `
						.. `Blink1_1 see-through {if blink then string.format("%.2f", blink.Transparency) else "?"}`
				)
			end
		end
		for index, player in env.players do
			local runner = mode.runners[player]
			if not runner or not env.Alive(player) then
				continue
			end
			if runner.Place and not reported[player] then
				reported[player] = true
				env.note(
					`{player.Name} reached the crown {runner.Place} in {string.format(
						"%.1f",
						runner.Finish - mode.startAt
					)}s (falls {runner.Falls}, hits {runner.Hits})`
				)
			end
			if runner.Finish then
				continue
			end
			-- The pool test: one stand-in jumps in once it's past the first pad.
			if not dunked and runner.Stage >= 1 and index == #env.players then
				dunked = { Player = player, Stage = runner.Stage, Falls = runner.Falls }
				local root = env.Root(player)
				if root then
					env.Move(player, root - Vector3.new(0, 14, 0))
				end
				env.note(`{player.Name} jumps into the pool at checkpoint {runner.Stage}`)
				nextHop[player] = now + 1.2
				continue
			end
			if dunked and dunked.Player == player and not dunkChecked and now >= nextHop[player] - 0.2 then
				dunkChecked = true
				local root = env.Root(player)
				local x, y, z = Course.Respawn(dunked.Stage, runner.Slot)
				local spot = mode.origin + Vector3.new(x, y + 3, z)
				env.note(
					`pool test: falls {dunked.Falls} -> {runner.Falls}, back {if root
						then string.format("%.1f", (root - spot).Magnitude)
						else "?"} studs from its checkpoint spot`
				)
			end
			if now < (nextHop[player] or 0) then
				continue
			end
			nextHop[player] = now + pace[player]
			-- Walking a long piece: a few studs at a time along it.
			local walk = walking[player]
			if walk then
				local root = env.Root(player)
				if root then
					local p = root - mode.origin
					local step = math.min(Course.WalkSpeed * pace[player], walk.Z - p.Z)
					put(player, walk.X, walk.Top, p.Z + step)
					nextHop[player] = now + pace[player] * 0.5
					if p.Z + step >= walk.Z - 0.1 then
						walking[player] = nil
					end
				else
					walking[player] = nil
				end
				continue
			end
			-- Onto a piece of the next row (some pick the far side, so they spread out).
			local row = Course.Rows[runner.Row + 1]
			if not row then
				continue
			end
			local here = at[player]
			if not here or here.Row ~= runner.Row then
				here = Course.Rows[runner.Row][1] -- (put back on a pad)
			end
			local ways = Course.WaysOn(here)
			local way = if #ways > 0 then ways[env.rng:NextInteger(1, #ways)] else nil
			local to = if way then way.To else row[1]
			if way and way.Launch then
				-- A launch pad: no client here to fly the stand-in, so it lands where the flight would.
				local x, y, z = Course.LaunchLanding(here, runner.Slot)
				put(player, x, y, z)
				at[player] = to
				launched += 1
				continue
			end
			if to.Blink and not Course.Solid(to, t + 0.05) then
				continue -- wait for it
			end
			local x, z = to.X, to.Z - to.D / 2 + math.min(2, to.D / 2)
			if to.Kind == "Disc" then
				z = to.Z - to.W / 2 + 2
			end
			put(player, x, Course.SurfaceAt(to, x), z)
			at[player] = to
			if to.D > 12 then
				walking[player] = { X = x, Top = to.Top, Z = to.Z + to.D / 2 - 1.5 }
			end
		end
		-- The real bots (not stand-ins): where each is and what it's doing, now and then.
		if elapsed > 1 and elapsed % 10 < 0.05 then
			local players = {}
			for _, player in env.players do
				players[player] = true
			end
			for bot, runner in mode.runners do
				if players[bot] or runner.Finish then
					continue
				end
				local root = env.Root(bot)
				local memory = (bot :: any).Memory or {}
				local target = memory.Target
				env.note(
					`  {bot.Name}: z {if root then string.format("%.1f", (root - mode.origin).Z) else "?"}, y {if root
						then string.format("%.1f", (root - mode.origin).Y)
						else "?"}, row {runner.Row}, ✓{runner.Stage}, falls {runner.Falls}, hits {runner.Hits}, `
						.. `target {if target then target.Id else "-"}, waiting {tostring(memory.Waiting)}, ball {tostring(
							memory.Ball
						)}`
				)
			end
		end
		if elapsed > 1 and elapsed % 10 < 0.05 then
			local finished = 0
			for _, runner in mode.runners do
				if runner.Finish then
					finished += 1
				end
			end
			local flights = 0
			for _, runner in mode.runners do
				flights += runner.Launches or 0
			end
			env.note(
				`t {math.floor(elapsed)}: {finished} at the crown, `
					.. `launches {flights} (stand-ins put across {launched})`
			)
		end
	end
end
