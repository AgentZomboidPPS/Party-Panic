-- Scenario for round_harness.py --bot with --reset-at: in Skate Escape the last stand-in resets in
-- the 3-2-1 and gets its new character only after GO. That character must go to where its racer is
-- on the course, standing on a board (SkateEscape:_seat through the CharacterReady the round gives
-- a late character), and the racer must still be in. The stand-ins push at a steady pace and their
-- rigs are moved to where the race has them (no physics here).
--
--   python3 tools/checks/round_harness.py SkateEscape --players 2 --reset-at 12.3 --seconds 6 \
--       --bot tools/checks/scenarios/SkateEscape_late_body.luau > skate.luau
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local SkateCourse = __require("Shared/Logic/SkateCourse") -- the harness bundle's module loader
	local nextPush = {}
	local reported = false
	return function(elapsed)
		local now = ctx:Now()
		for _, player in env.players do
			local racer = mode.racers and mode.racers[tostring(player.UserId)]
			if not racer or not env.Alive(player) then
				continue
			end
			if not racer.Done and now >= (nextPush[player] or 0) then
				env.Action(player, "Push")
				nextPush[player] = now + 0.25
			end
			local d, lift = SkateCourse.Pose(racer, now)
			local cframe = SkateCourse.StanceCFrame(mode.origin, SkateCourse.LaneX(racer.Lane, 12), d, 2.75 + lift, 0)
			if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
				env.Move(player, cframe.Position, cframe.Position + Vector3.xAxis)
			end
		end
		if not reported and elapsed >= 4 then
			reported = true
			local player = env.players[#env.players]
			local racer = mode.racers[tostring(player.UserId)]
			local character = player.Character
			env.note(
				`{player.Name} {string.format("%.1f", elapsed)}s after GO: in {tostring(env.Alive(player))}, racer's character is the new one {tostring(
					racer ~= nil and racer.Character == character
				)}, on a board {tostring(character ~= nil and character:FindFirstChild("Skateboard") ~= nil)}, at {racer and math.floor(
					racer.D
				) or -1} studs`
			)
		end
	end
end
