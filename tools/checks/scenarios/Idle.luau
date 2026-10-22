-- A passive human for the bot audit (round_harness.py <Mode> --players 1 --bots 7 --bot
-- tools/checks/scenarios/Idle.luau): the stand-in player joins the round and never presses or moves,
-- so the results show whether the mode's bots beat someone who doesn't play.
return function(env)
	env.note("stand-ins stay idle all round")
	return function() end
end
