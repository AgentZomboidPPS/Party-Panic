-- Scenario for round_harness.py --bot: the second shop pass's knockout and victory effects in a real
-- round (owner: "Yes lets add more items after everything else is finished"). Each stand-in owns and
-- wears a new knockout effect and a new victory effect (their harness profiles only: CanSave is
-- false, nothing touches a DataStore). They're knocked out one by one, a second apart, through the
-- round's own RoundContext:Eliminate, so CosmeticService plays each one's effect where they stand;
-- the last one standing wins, and the win plays their victory effect. The summary's event counts
-- show "PlayEffect:<name>" for each, and the client half (--client) draws them on the phone.
--
--   python3 tools/checks/round_harness.py HexMeltdown --players 6 --client --touch \
--       --bot tools/checks/scenarios/ShopEffects_round.luau > shop_effects.luau
return function(env)
	local ctx = env.ctx
	local DataService = __require("Server/Services/DataService")
	local CosmeticService = __require("Server/Services/CosmeticService")
	local KNOCKOUTS = { "Elim_Zap", "Elim_Splat", "Elim_Ducks", "Elim_Frozen", "Elim_Zap", "Elim_Splat" }
	local VICTORIES = {
		"Victory_Supernova",
		"Victory_Spotlight",
		"Victory_Streamers",
		"Victory_Balloons",
		"Victory_Supernova",
		"Victory_Spotlight",
	}
	local dressed = false
	local nextOut = 3
	local outCount = 0
	return function(elapsed)
		if not dressed then
			dressed = true
			for index, player in env.players do
				local profile = DataService.Get(player)
				if profile then
					local knockout = KNOCKOUTS[(index - 1) % #KNOCKOUTS + 1]
					local victory = VICTORIES[(index - 1) % #VICTORIES + 1]
					profile.Data.Owned[knockout] = true
					profile.Data.Owned[victory] = true
					profile.Data.Equipped.Elimination = knockout
					profile.Data.Equipped.Victory = victory
					CosmeticService.Refresh(player)
					env.note(`{player.Name} wears {knockout} and {victory}`)
				end
			end
		end
		-- Everyone but the last stand-in goes out, a second apart: Bot2, Bot3, ... and the client's
		-- Bot1 last of them, so the phone sees the others' effects first.
		local count = #env.players
		if elapsed >= nextOut and outCount < count - 1 then
			outCount += 1
			nextOut = elapsed + 1
			local player = if outCount < count - 1 then env.players[outCount + 1] else env.players[1]
			if ctx:IsAlive(player) then
				ctx:Eliminate(player, "Harness")
				env.note(`{player.Name} out`)
			end
		end
	end
end
