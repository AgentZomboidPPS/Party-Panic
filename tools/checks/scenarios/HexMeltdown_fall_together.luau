-- Scenario for round_harness.py --bot: in Hex Meltdown every stand-in drops into the lava at the same
-- moment, 3 seconds in, so the fall check finds them all below KillY in one go. They must all go
-- out and tie (RoundContext.Eliminate): before the fix the first one checked ended the round as the
-- last survivor's win and the others stayed in with "Survived!", picked by table order.
--
--   python3 tools/checks/round_harness.py HexMeltdown --players 2 \
--       --bot tools/checks/scenarios/HexMeltdown_fall_together.luau > hex.luau
return function(env)
	local dropped = false
	local reported = {}
	return function(t)
		if not dropped and t >= 3 then
			dropped = true
			for _, player in env.players do
				local position = env.Root(player)
				if position then
					env.Move(player, position - Vector3.new(0, 40, 0))
				end
			end
			env.note(`dropped all {#env.players} into the lava at {string.format("%.2f", t)}s`)
		end
		for _, player in env.players do
			if dropped and not reported[player] and not env.Alive(player) then
				reported[player] = true
				local state = env.ctx:State(player)
				env.note(`{player.Name} out, EliminatedAt {state and state.EliminatedAt}`)
			end
		end
	end
end
