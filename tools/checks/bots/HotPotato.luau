-- Test bot for Hot Potato (tools/checks/round_harness.py): moves the stand-in players and sends the
-- actions a real client would. Luau execution has no physics, so bots move rigs with env.Move.
--
-- env: ctx, game (your mode's instance), players, rng, note(text), client, Action(player, name, ...),
-- Root(player), Move(player, position, lookAt), Shared(key), SharedJSON(key), Mine(player, key),
-- Alive(player), Leave(player). The returned function runs every 0.05 s.
return function(env)
	local cheers = 0
	return function(elapsed)
		for _, player in env.players do
			if env.Alive(player) and env.rng:NextNumber() < 0.02 then
				env.Action(player, "Cheer")
				cheers += 1
			end
		end
		if elapsed > 5 and cheers > 0 and not env.reported then
			env.reported = true
			env.note(`bots cheered {cheers} times; lead: {tostring(env.Shared("Lead"))}`)
		end
	end
end
