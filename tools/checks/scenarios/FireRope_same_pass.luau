-- Scenario for round_harness.py --bot: in Fire Rope nobody jumps, so the rope's first pass hits every
-- stand-in, one on a quick connection (0.06 s round trip) and one on a slow one (0.45 s), whose
-- verdict needs their positions from later on. They must go out together and tie (FireRope:_settle,
-- RoundContext.Eliminate): before the fix the quick one was judged first, was out, and the round
-- ended before the slow one was judged, who then won with "Survived!".
--
--   python3 tools/checks/round_harness.py FireRope --players 2 \
--       --bot tools/checks/scenarios/FireRope_same_pass.luau > rope.luau
return function(env)
	local pings = { 0.06, 0.45, 0.2, 0.3 }
	for index, player in env.players do
		player.__ping = pings[(index - 1) % #pings + 1]
	end
	local reported = {}
	return function(t)
		for _, player in env.players do
			if not reported[player] and not env.Alive(player) then
				reported[player] = true
				local state = env.ctx:State(player)
				env.note(
					`{player.Name} (ping {player.__ping}) out at {string.format("%.2f", t)}s, EliminatedAt {state and state.EliminatedAt}`
				)
			end
		end
	end
end
