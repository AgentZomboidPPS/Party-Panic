-- Scenario for round_harness.py --bot: in Honey Trap the first player presses HIT 5.80 s into their
-- turn, while the face before the block's last flip shows (5.46 to 5.88), on a slow phone (0.4 s
-- round trip): the hit reaches the server 0.35 s later, after the 6 s deadline. It must get the face
-- they pressed on (Logic/HoneyBlock.Judge): before the fix the server had already stopped the block
-- on the next face and dropped the hit.
--
--   python3 tools/checks/round_harness.py HoneyTrap --players 2 \
--       --bot tools/checks/scenarios/HoneyTrap_late_hit.luau > honey.luau
return function(env)
	for _, player in env.players do
		player.__ping = 0.4
	end
	local sent = nil
	local reported = false
	local function fmt(value)
		return if value then string.format("%.2f", value) else "never"
	end
	return function()
		local turn = env.SharedJSON("Turn")
		if not turn then
			return
		end
		local now = env.ctx:Now()
		if not sent and turn.Result == nil and now >= turn.T0 + 5.8 then
			local flips = math.floor((now - turn.T0) / turn.Flip)
			local face = ((turn.First - 1 + flips) % 2) + 1
			sent = { Id = turn.Id, Face = face, PressedAt = now - turn.T0 }
			for _, player in env.players do
				if player.UserId == turn.User then
					task.delay(0.35, function()
						sent.ArrivedAt = env.ctx:Now() - turn.T0
						env.Action(player, "Hit", face, now) -- the face on screen, and when (like the client)
					end)
				end
			end
		elseif sent and not reported and turn.Id == sent.Id and turn.Result ~= nil and sent.ArrivedAt then
			reported = true
			local last = ((turn.First - 1 + math.floor((turn.Deadline - turn.T0) / turn.Flip)) % 2) + 1
			local verdict = if turn.Result == sent.Face then "the face pressed on" else "NOT the face pressed on"
			local pressed = `pressed at T0+{fmt(sent.PressedAt)} on face {sent.Face}`
			local arrived = `reached the server at T0+{fmt(sent.ArrivedAt)}`
			local deadline = `deadline T0+{fmt(turn.Deadline - turn.T0)}, face {last} then`
			env.note(`{pressed}; the hit {arrived} ({deadline}); result: face {turn.Result} - {verdict}`)
			task.delay(0.5, function()
				if not env.ctx.EndReason then
					env.ctx:End("HarnessStop")
				end
			end)
		end
	end
end
