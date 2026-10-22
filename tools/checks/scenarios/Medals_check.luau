-- Medal checks for a round harness run (Services/MedalService; owner: "Medals: a medal for winning
-- each game and a few big ones, Roblox badges, a collect-them-all wall in the lobby"). Not a bot of
-- its own: put it in front of a mode's stand-in bot and run that as the bot, e.g.
--
--   cat tools/checks/scenarios/Medals_check.luau tools/checks/bots/FireRope.luau > /tmp/medals.luau
--   python3 tools/checks/round_harness.py FireRope --players 6 --bots 2 --seconds 30 \
--       --bot /tmp/medals.luau > /tmp/round.luau
--   python3 tools/preview/luau_task.py /tmp/round.luau - /tmp/round.json
--
-- Once the round's rewards are paid (RoundEvents.Finished), the result's log gets "MEDALS ..." lines:
--   round    every placed player: place, team, whether they won, whether they got the game's medal
--            (and "PROBLEM" lines: a winner without it, a loser or a bot with it)
--   once     the same round announced again sends that medal to nobody a second time
--   award    another feature's Award: new the first time, not the second; never for a bot
--   badges   a medal with a badge id: the badge the harness lists instead of awarding it (no real
--            badge is ever awarded from a test, and none is saved: the stand-ins' profiles don't save)
--   veterans the stand-ins seeded with wins (harness_prelude: Bot2 7, Bot3 9) got First Win quietly
--            when the service started ("*" = sent as earned before medals existed)
--   late     a player whose profile loads later: an award made before it loaded, and what their
--            stats had already earned (55 wins, every game played), all sent once
--   sent     every MedalEarned each player was sent

do
	local HttpService = game:GetService("HttpService")
	local sent: { [string]: { string } } = {}
	-- (The harness's own recording Remotes: every Remotes.Get hands out the same remote.)
	local remote = __modules["Shared/Remotes"]().Get("MedalEarned")
	local fire = remote.FireClient
	remote.FireClient = function(self, player, id, earlier, ...)
		local name = if type(player) == "table" then player.Name else tostring(player)
		sent[name] = sent[name] or {}
		table.insert(sent[name], if earlier then id .. "*" else id)
		return fire(self, player, id, earlier, ...)
	end
	local function count(name: string, id: string): number
		local total = 0
		for _, item in sent[name] or {} do
			if item == id or item == id .. "*" then
				total += 1
			end
		end
		return total
	end
	local function line(text: string)
		__note("MEDALS " .. text)
	end

	local RoundEvents = __require("Server/Services/RoundEvents")
	local checked = false
	RoundEvents.Finished:Connect(function(definition, placed, winningTeam)
		if checked then
			return
		end
		checked = true
		-- MedalService hears it in a thread of its own, which never waits: a frame is enough. Nothing
		-- below waits either: the harness returns its result soon after the rewards.
		task.wait()
		local ok, err = pcall(function()
			local DataService = __require("Server/Services/DataService")
			local MedalService = __require("Server/Services/MedalService")
			local BotRegistry = __require("Server/Services/BotRegistry")
			local Medals = __require("Shared/Medals")
			local MedalLogic = __require("Shared/Logic/MedalLogic")
			local medal = Medals.ForGame(definition.Id)
			line(`game {definition.Id}: medal {medal and medal.Id or "none"}, winning team {tostring(winningTeam)}`)

			-- round
			local rows = {}
			for _, item in placed do
				local entry = item.Entry
				local player = entry.Player
				local isBot = BotRegistry.IsBot(player)
				local profile = DataService.Get(player)
				local has = profile ~= nil and medal ~= nil and profile.Data.Medals[medal.Id] ~= nil
				local won = MedalLogic.IsWin(item.Place, entry.Team, winningTeam)
				table.insert(
					rows,
					`{player.Name} #{item.Place}{if entry.Team then " " .. entry.Team else ""} {if won
						then "won"
						else "-"} {if has then "MEDAL" else "no medal"}{if isBot then " (bot)" else ""}`
				)
				if isBot and (has or count(player.Name, medal.Id) > 0) then
					line(`PROBLEM: bot {player.Name} got a medal`)
				elseif not isBot and profile and won ~= has then
					line(`PROBLEM: {player.Name} #{item.Place} won={won} has={has}`)
				end
			end
			line("round: " .. table.concat(rows, "; "))

			-- once
			local before = 0
			for name in sent do
				before += count(name, medal.Id)
			end
			RoundEvents.Finished:Fire(definition, placed, winningTeam) -- (its listeners run right away)
			local after = 0
			for name in sent do
				after += count(name, medal.Id)
			end
			line(`once: {medal.Id} sent {before} times after the round, {after} after it was announced again`)

			-- award (another feature), and never for a bot
			local person = __fakePlayers[1]
			local first = MedalService.Award(person, "CupChampion")
			local second = MedalService.Award(person, "CupChampion")
			local bot = BotRegistry.List()[1]
			local botAward = if bot then tostring(MedalService.Award(bot, "FriendsParty")) else "no bot"
			line(
				`award: CupChampion to {person.Name} first {first}, second {second}, sent {count(
					person.Name,
					"CupChampion"
				)}; to a bot: {botAward}; has {MedalService.Has(person, "CupChampion")}`
			)

			-- badges
			Medals.ById.HallOfFame.BadgeId = 99
			MedalService.Award(person, "HallOfFame") -- (under the harness its badge is listed at once)
			Medals.ById.HallOfFame.BadgeId = 0
			line(`badges (harness list, none awarded): {HttpService:JSONEncode(MedalService.HarnessBadges)}`)

			-- veterans
			local veterans = {}
			for _, player in __fakePlayers do
				local profile = DataService.Get(player)
				if profile and (profile.Data.Stats.Wins or 0) > 0 then
					table.insert(
						veterans,
						`{player.Name} ({profile.Data.Stats.Wins} wins): FirstWin sent {table.concat(
							sent[player.Name] or {},
							","
						)}`
					)
				end
			end
			line("veterans: " .. table.concat(veterans, "; "))

			-- late
			-- (A bare stand-in: building a character could wait, and nothing here may.)
			local late = {
				Name = "Late",
				DisplayName = "Late",
				UserId = 1090,
				Parent = true,
				FindFirstChild = function()
					return nil
				end,
			}
			local waited = MedalService.Award(late, "FriendsParty")
			local plays = {}
			for _, game in Medals.Games do
				plays[game.GameId] = 3
			end
			local data = DataService.Migrate({ EconomyVersion = 2, Stats = { Wins = 55, ModePlays = plays } })
			DataService.All()[late] = {
				Player = late,
				Key = "Harness_Late",
				Data = data,
				CanSave = false,
				Released = false,
			}
			MedalService.ProfileLoaded(late)
			MedalService.ProfileLoaded(late) -- (a second load sends nothing new)
			local owned = {}
			for id in data.Medals do
				table.insert(owned, id)
			end
			table.sort(owned)
			line(
				`late: award before the profile {waited}; sent {table.concat(sent.Late or {}, ",")}; has {table.concat(
					owned,
					","
				)}`
			)
			DataService.All()[late] = nil

			-- sent
			local names = {}
			for name in sent do
				table.insert(names, name)
			end
			table.sort(names)
			local all = {}
			for _, name in names do
				table.insert(all, `{name}: {table.concat(sent[name], ",")}`)
			end
			line("sent: " .. table.concat(all, "; "))
		end)
		if not ok then
			line("check failed: " .. tostring(err))
		end
	end)
end
