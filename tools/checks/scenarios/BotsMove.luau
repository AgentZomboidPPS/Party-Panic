-- Scenario for round_harness.py --client --bots N --bot (the ride modes: Trace Race, Minecart
-- Mayhem, Rockin' Raceway, Bobsled Run, Dice Dash): do the bots' bodies get where their race says?
-- The server seats bot riders at the start and every client stands every rider in place each frame
-- (owner: "Bots are STILL ruberbanding and floating."); this checks the client really carries them.
-- The stand-ins press nothing. Every 2 s it notes how far each real bot's body moved since the last
-- look, and at the end each bot's total; a bot whose body stayed put all round is a PROBLEM.
--
--   python3 tools/checks/round_harness.py TraceRace --players 1 --client --bots 5 --seconds 30 \
--       --bot tools/checks/scenarios/BotsMove.luau > moves.luau
return function(env)
	local BotRegistry = __require("Server/Services/BotRegistry")
	local last: { [any]: Vector3 } = {}
	local total: { [any]: number } = {}
	local nextLook = 2
	local reported = false
	return function(elapsed)
		if elapsed >= nextLook then
			nextLook += 2
			local parts = {}
			for _, bot in BotRegistry.List() do
				local root = bot.Character and bot.Character:FindFirstChild("HumanoidRootPart")
				if root and bot:GetAttribute("PP_InRound") then
					local from = last[bot]
					last[bot] = root.Position
					if from then
						local moved = (root.Position - from).Magnitude
						total[bot] = (total[bot] or 0) + moved
						table.insert(parts, `{bot.DisplayName} {math.floor(moved + 0.5)}`)
					end
				end
			end
			env.note(`BOTSMOVE {math.floor(elapsed)} s: {table.concat(parts, ", ")}`)
		end
		if elapsed >= 24 and not reported then
			reported = true
			local parts, still = {}, 0
			for bot, moved in total do
				table.insert(parts, `{bot.DisplayName} {math.floor(moved + 0.5)}`)
				if moved < 5 then
					still += 1
				end
			end
			env.note(
				`BOTSMOVE total: {table.concat(parts, ", ")}{if still > 0 then ` PROBLEM: {still} stayed put` else ""}`
			)
		end
	end
end
