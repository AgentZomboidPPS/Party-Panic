-- Scenario for round_harness.py --bot: the suggestion box on a real server (owner: "Can we add a
-- suggestion box?"; Services/SuggestionService, writing to PP_Suggestions_Test on test runs). Two
-- seconds in, the stand-ins send what a player might: too short, a kind that isn't one, a real idea,
-- a second one straight after (one a minute), and another player's two-line bug report. Each line
-- says what the server answered; then the hour's key is read back. "PROBLEM" marks anything that
-- came out wrong; then the owner's inbox reads the week back (and a stand-in isn't the owner).
-- tools/checks/suggestions.py --test --days 1 shows them as the owner would.
--
--   python3 tools/checks/round_harness.py FireRope --players 2 --seconds 8 \
--       --bot tools/checks/scenarios/SuggestionBox.luau > box.luau
return function(env)
	local started = false
	return function(elapsed)
		if started or elapsed < 2 then
			return
		end
		started = true
		task.spawn(function()
			local SuggestionService = __require("Server/Services/SuggestionService")
			local Suggestions = __require("Shared/Logic/Suggestions")
			local ann, bo = env.players[1], env.players[2]
			local cases = {
				{ ann, "Bug", "hi", false, "too short" },
				{ ann, "Spam", "this is long enough to count", false, "not a kind" },
				{ ann, "Game", "A go-kart racing game with item boxes!", true, "a real idea" },
				{ ann, "Better", "And another one straight away", false, "one a minute" },
				{ bo, "Bug", "Spleef blocks vanish too fast\non my phone", true, "another player's bug" },
			}
			for _, case in cases do
				local ok, words = SuggestionService.Submit(case[1], case[2], case[3])
				env.note(
					`SUGGEST{if ok ~= case[4] then " PROBLEM" else ""} {case[5]}: {if ok then "kept" else "turned down"} ({words})`
				)
			end
			local store = game:GetService("DataStoreService"):GetDataStore("PP_Suggestions_Test")
			local okRead, list = pcall(store.GetAsync, store, Suggestions.Key(os.time()))
			local mine = 0
			for _, entry in if okRead and type(list) == "table" then list else {} do
				if entry.U == ann.UserId or entry.U == bo.UserId then
					mine += 1
				end
			end
			env.note(
				`SUGGEST{if mine < 2 then " PROBLEM" else ""} read back: {if okRead
					then `{mine} of this run's 2 in the hour's key`
					else tostring(list)}`
			)
			-- The owner's inbox (the last week, newest first), as the owner's INBOX window gets it.
			local entries, okInbox = SuggestionService.Inbox()
			local found, newestFirst = 0, true
			for index, entry in entries do
				if entry.U == ann.UserId or entry.U == bo.UserId then
					found += 1
				end
				if index > 1 and (entry.T or 0) > (entries[index - 1].T or 0) then
					newestFirst = false
				end
			end
			local broken = not okInbox or found < 2 or not newestFirst
			env.note(
				`SUGGEST{if broken then " PROBLEM" else ""} inbox: {#entries} in the last week, this run's {found} of 2, newest first {newestFirst}`
			)
			local owner = SuggestionService.IsOwner(ann)
			env.note(`SUGGEST{if owner then " PROBLEM" else ""} inbox is the owner's only: a stand-in is owner {owner}`)
		end)
	end
end
