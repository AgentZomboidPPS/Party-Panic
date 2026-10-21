-- Test bot for Skate Escape (tools/checks/round_harness.py): the stand-in players mash PUSH at their
-- own pace and press JUMP before each obstacle (the weaker ones late or not at all), through the same
-- actions a client sends. No physics here, so their rigs are moved to where the server's race has
-- them (the stand-in client, Bot1, moves its own rig from the client half).
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local SkateCourse = __require("Shared/Logic/SkateCourse") -- the harness bundle's module loader
	local plans = {}
	local skill = {}
	local nextPush = {}
	for index, player in env.players do
		skill[player] = math.clamp(1 - index * 0.08, 0.1, 0.95)
	end
	local pushes, jumps, reported = 0, 0, {}
	local wipes, lastWipe = 0, {}

	return function(elapsed)
		local now = ctx:Now()
		for index, player in env.players do
			local racer = mode.racers and mode.racers[tostring(player.UserId)]
			if not racer or not env.Alive(player) then
				if racer and racer.Out and not reported[player] then
					reported[player] = true
					env.note(`{player.Name} fell with the bridge at {math.floor(racer.D)} (t {math.floor(elapsed)})`)
				end
				continue
			end
			if racer.Place and not reported[player] then
				reported[player] = true
				env.note(`{player.Name} finished {racer.Place} in {string.format("%.1f", racer.Time)}s`)
			end
			if racer.WipeAt and racer.WipeAt ~= lastWipe[player] then
				lastWipe[player] = racer.WipeAt
				wipes += 1
			end
			local s = skill[player]
			if not racer.Done and now >= (nextPush[player] or 0) then
				env.Action(player, "Push")
				pushes += 1
				nextPush[player] = now + 1 / (2.5 + 5 * s)
			end
			-- Jump for the next obstacle that isn't a boost pad.
			local o, at = nil, racer.Next
			while mode.obstacles[at] and mode.obstacles[at].Kind == "Boost" do
				at += 1
			end
			o = mode.obstacles[at]
			if o and racer.V > 4 and plans[player] ~= at then
				local takeoff = o.D - racer.V * SkateCourse.AirTime / 2
				if racer.D >= takeoff - racer.V * 0.05 then
					plans[player] = at
					if env.rng:NextNumber() < 0.55 + s * 0.45 then
						env.Action(player, "Jump")
						jumps += 1
					end
				end
			end
			-- Stand-ins have no client: put the rig where the race has it.
			if not (env.client and index == 1) then
				local d, lift = SkateCourse.Pose(racer, now)
				local x = SkateCourse.LaneX(racer.Lane, 12)
				local cframe = SkateCourse.StanceCFrame(mode.origin, x, d, 2.75 + lift, 0)
				env.Move(player, cframe.Position, cframe.Position + Vector3.xAxis)
			end
		end
		if elapsed > 12 and not reported.summary then
			reported.summary = true
			local front = SkateCourse.CollapseAt(mode.collapse, now)
			local lines = {}
			for _, player in env.players do
				local racer = mode.racers[tostring(player.UserId)]
				if racer then
					table.insert(lines, `{player.Name}:{math.floor(racer.D)}@{math.floor(racer.V)}`)
				end
			end
			env.note(
				`t12: pushes {pushes}, jumps {jumps}, wipes {wipes}, collapse at {math.floor(front)}; {table.concat(
					lines,
					" "
				)}`
			)
		end
	end
end
