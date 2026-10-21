-- Scenario for round_harness.py --bot: in Honey Trap the first player presses HIT 2 s into their turn
-- on a slow phone (0.5 s round trip), and time runs out 0.1 s later, while the hit is still on its
-- way (it gets there 0.25 s after the press, saying when it was pressed, like the client). The
-- bottom of the vine is a honeycomb. The hit was made before the buzzer, so it must count
-- (RoundContext.HoldEnd, Logic/Buzzer): they take the honeycomb and are out. Before the fix the
-- round ended first and the hit was dropped, so they "survived".
--
--   python3 tools/checks/round_harness.py HoneyTrap --players 2 \
--       --bot tools/checks/scenarios/HoneyTrap_buzzer_hit.luau > honey.luau
return function(env)
	local ctx = env.ctx
	for _, player in env.players do
		player.__ping = 0.5
	end
	local pressed = nil
	local buzzer = nil
	return function()
		local turn = env.SharedJSON("Turn")
		local now = ctx:Now()
		if not pressed and turn and turn.Result == nil and now >= turn.T0 + 2 then
			local mode = env.game
			mode.vine = string.sub(mode.vine, 1, mode.next - 1) .. "H" .. string.sub(mode.vine, mode.next + 1)
			local flips = math.floor((now - turn.T0) / turn.Flip)
			local face = ((turn.First - 1 + flips) % 2) + 1
			for _, player in env.players do
				if player.UserId == turn.User then
					pressed = player
					local pressedAt = now
					task.delay(0.25, function()
						env.note(
							`{player.Name}'s hit gets to the server {string.format("%.2f", ctx:Now() - buzzer)} s after the buzzer`
						)
						env.Action(player, "Hit", face, pressedAt)
					end)
				end
			end
			buzzer = now + 0.1
			env.note(`{pressed and pressed.Name} presses HIT 0.1 s before the buzzer`)
		end
		if buzzer and now >= buzzer and not ctx.EndReason then
			if ctx.TimeRanOut then
				ctx:TimeRanOut("TimeUp")
			else
				ctx:End("TimeUp")
			end
		end
	end
end
