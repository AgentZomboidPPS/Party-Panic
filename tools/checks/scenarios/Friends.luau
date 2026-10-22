-- Scenario for round_harness.py --bot (Services/FriendsService): four stand-ins in a last-one-
-- standing mode. Bot1, Bot2 and Bot3 are friends with each other (FriendsService.SetFriendsForTest,
-- honoured on harness runs only: test servers have no friendships); Bot4 has no friend here. Bot2 is
-- out first, then Bot4, then Bot3, so Bot1 wins. The log should show:
--   * the results lines: "Played with a friend +1" for Bot1, Bot2 and Bot3, not for Bot4;
--   * the FriendsParty medal for Bot1, Bot2 and Bot3, not for Bot4;
--   * a second into Cleanup (none during the round or its results): Bot1 "🎉 You beat 2 friends!",
--     Bot3 "🎉 You beat Bot2!" (beating a friend wins over being beaten), Bot2 "2 friends beat you -
--     get them next round!", and one "⭐ 2 friends are here! ..." each for Bot1, Bot2 and Bot3 (the
--     arrivals marked during the rules card, held until the lobby); nothing for Bot4.
-- Stand-ins aren't real Players, so Notifier skips them: the toasts, the medal calls and each
-- player's reward lines are noted here instead. Run it with --client: the client half keeps the run
-- going past Cleanup, when the held toasts go out.
--
--   python3 tools/checks/round_harness.py HexMeltdown --players 4 --client \
--       --bot tools/checks/scenarios/Friends.luau > friends.luau
return function(env)
	local FriendsService = __require("Server/Services/FriendsService")
	local MedalService = __require("Server/Services/MedalService")
	local Notifier = __require("Server/Services/Notifier")
	local GameState = __require("Shared/GameState")
	local players = env.players
	local bot1, bot2, bot3, bot4 = players[1], players[2], players[3], players[4]
	assert(bot4, "the friends scenario needs --players 4")

	local function phase()
		return GameState.Get("Phase") or "?"
	end
	local send = Notifier.Send
	Notifier.Send = function(player, text, kind, duration)
		env.note(`toast to {player.Name} in {phase()} ({kind or "info"}): {text}`)
		return send(player, text, kind, duration)
	end
	local award = MedalService.Award
	MedalService.Award = function(player, id)
		env.note(`medal {id} for {player.Name}`)
		return award(player, id)
	end
	-- Each player's reward once the boosts have added theirs: the lines their results card shows.
	local Boosts = __require("Server/Services/Boosts")
	local apply = Boosts.Apply
	Boosts.Apply = function(player, reward, round)
		apply(player, reward, round)
		local lines = {}
		for _, line in reward.Lines do
			table.insert(lines, `{line.Label} +{line.Coins}`)
		end
		env.note(`results for {player.Name}: place {round.Place}, {table.concat(lines, ", ")}; total {reward.Coins}`)
	end

	FriendsService.SetFriendsForTest(bot1, bot2)
	FriendsService.SetFriendsForTest(bot1, bot3)
	FriendsService.SetFriendsForTest(bot2, bot3)
	env.note(
		`friends: 1-2 {FriendsService.AreFriends(bot1, bot2)}, 1-3 {FriendsService.AreFriends(bot1, bot3)}, `
			.. `2-3 {FriendsService.AreFriends(bot2, bot3)}, 1-4 {FriendsService.AreFriends(bot1, bot4)}`
	)

	local outAt = { { bot2, 1 }, { bot4, 2 }, { bot3, 3 } }
	return function(elapsed)
		for _, out in outAt do
			if elapsed >= out[2] and env.Alive(out[1]) then
				env.ctx:Eliminate(out[1], "harness")
				env.note(`{out[1].Name} out at {math.floor(elapsed * 10) / 10}s`)
			end
		end
	end
end
