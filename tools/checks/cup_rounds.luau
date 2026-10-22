-- PARTY CUPs over real rounds, on a real Roblox server (owner, asked what would keep players
-- coming back, then: "Can you work on all of that? this wont mess with what the other workers are
-- working on right?"). tools/checks/round_harness.py CUP bundles this with the working tree's
-- server code and the modes it plays:
--   python3 tools/checks/round_harness.py CUP --modes FireRope,PumpAndPop,CrazyCutters,ArrowAmbush,HexMeltdown \
--       --players 3 --bots 5 --seconds 12 > cup.luau
--   python3 tools/preview/luau_task.py cup.luau - cup.json
--
-- Stand-in people and real bots (Services/BotService, played by each mode's brain) play a whole
-- cup and the next cup's first round, the modes in turn, each round the way RoundManager plays it:
-- RoundContext, the mode's own code, RewardService and RoundEvents.Finished (__grantRewards), then
-- the results and the clean-up. Along the way a person leaves after round 2 and comes back after
-- round 3 (their points come back), a bot fades out after round 2 (it drops off), and someone new
-- joins after round 3 (they start at 0). Then four quick rounds made up on the spot (Finished
-- fired with set places, Bot1 first) finish cup 2, so the crown's path is checked whoever won cup
-- 1: on in the lobby, off while its wearer plays a round, back on after, on a fresh character
-- after a reset, and gone (and off the attribute) when they leave.
-- The result: what the cup showed after each round (GameState "Cup"), each podium, what each
-- person was paid and their cup stats, the medal calls, the toasts, and every check (PASS/FAIL).

-- A profile for a stand-in who arrives during the run (__seedProfiles does the first ones).
function __cupProfile(player, before)
	local DataService = __require("Server/Services/DataService")
	local LevelCurve = __require("Shared/Logic/LevelCurve")
	local data, migration = DataService.Migrate({ EconomyVersion = 2 })
	DataService.All()[player] = {
		Player = player,
		Key = "Harness_" .. player.Name,
		Data = data,
		CanSave = false,
		IsVip = false,
		Released = false,
		Migration = migration,
	}
	DataService.Changed(player)
	before[player] = { coins = data.Coins, xp = data.XP, level = LevelCurve.FromTotalXP(data.XP), owned = {} }
end

-- The attribute, short: "#1 2/5 played", then "1st Bot1 18 (+10)"...
function __cupLines(data)
	if type(data) ~= "table" then
		return { tostring(data) }
	end
	local lines = {
		`#{data.Number} round {data.Round}/{data.Of} played {data.Played}{if data.Done then " DONE" else ""}`
			.. (if data.Champion then ` crown {data.Champion.Name} (#{data.Champion.Cup})` else "")
			.. (if data.Last then ` last #{data.Last.Number}` else ""),
	}
	for _, row in data.Standings or {} do
		table.insert(lines, `{row.Place} {row.Name} {row.Points} (+{row.Gain}){if row.IsBot then " bot" else ""}`)
	end
	return lines
end

function __cupRow(data, userId)
	for _, row in (if type(data) == "table" then data.Standings else nil) or {} do
		if row.UserId == userId then
			return row
		end
	end
	return nil
end

-- Everything about one character's crown: whether it's there and how its parts are set.
function __crownOn(player)
	local character = player.Character
	local crown = character and character:FindFirstChild("PP_CupCrown")
	if not crown then
		return false, "no crown"
	end
	local parts, loose, welded = 0, 0, 0
	for _, part in crown:GetDescendants() do
		if part:IsA("BasePart") then
			parts += 1
			if part.CanCollide or part.CanTouch or part.CanQuery or not part.Massless or part.Anchored then
				loose += 1
			end
			local weld = part:FindFirstChildOfClass("Weld")
			if weld and weld.Part0 and weld.Part0.Name == "Head" and weld.Part0.Parent == character then
				welded += 1
			end
		end
	end
	return true, `{parts} parts, {welded} welded to the head, {loose} that collide/touch/query/weigh`
end

function __runCup(modes, people, botCount, seconds, rounds)
	local GameState = __require("Shared/GameState")
	local GameDefinitions = __require("Shared/GameDefinitions")
	local PartyCup = __require("Shared/Logic/PartyCup")
	local RoundContext = __require("Server/Services/RoundContext")
	local DataService = __require("Server/Services/DataService")
	local BotService = __require("Server/Services/BotService")
	local MedalService = __require("Server/Services/MedalService")
	local Notifier = __require("Server/Services/Notifier")
	local RoundEvents = __require("Server/Services/RoundEvents")
	GameState.Folder()
	local summary = { modes = modes, rounds = {}, checks = {}, cups = {} }
	local function check(name, ok, detail)
		table.insert(
			summary.checks,
			`{if ok then "PASS" else "FAIL"} {name}{if detail ~= nil then ": " .. tostring(detail) else ""}`
		)
	end
	local function setPhase(phase, duration)
		GameState.Set("Phase", phase)
		GameState.Set("PhaseEndsAt", if duration then workspace:GetServerTimeNow() + duration else 0)
	end
	local function cupNow()
		return GameState.GetJSON("Cup")
	end

	for index = 1, people do
		table.insert(__fakePlayers, __newPlayer(index))
	end
	local before = __seedProfiles()
	-- What the cup gives out, as it's given: medals and toasts (stand-ins have no device to get a
	-- toast on, so Notifier would drop them).
	local medals, toasts = {}, {}
	local award = MedalService.Award
	MedalService.Award = function(player, id)
		table.insert(medals, `{player.Name} {id}`)
		return award(player, id)
	end
	local send = Notifier.Send
	Notifier.Send = function(player, text, ...)
		if
			type(text) == "string" and (string.find(text, "PARTY CUP", 1, true) or string.find(text, "crown", 1, true))
		then
			table.insert(toasts, `{player.Name}: {text}`)
		end
		return send(player, text, ...)
	end

	workspace:SetAttribute("PP_Harness", true)
	for _, name in { "CupService", "FriendsService", "MedalService", "LeaderboardService", "EventService" } do
		local okLoad, service = pcall(__require, "Server/Services/" .. name)
		if not okLoad or type(service) ~= "table" then
			__note(`{name} failed to load: {service}`)
			continue
		end
		if service.Init then
			local okInit, initErr = pcall(service.Init)
			if not okInit then
				__note(`{name}.Init failed: {initErr}`)
			end
		end
		if service.Start then
			task.spawn(function()
				local okStart, startErr = pcall(service.Start)
				if not okStart then
					__note(`{name}.Start failed: {startErr}`)
				end
			end)
		end
	end
	check("the attribute is empty before the first round", GameState.Get("Cup") == "", GameState.Get("Cup"))

	BotService.Setup()
	local bots = {}
	for _ = 1, botCount do
		table.insert(bots, BotService.Add())
	end
	task.wait(0.8)

	local function leave(player)
		local index = table.find(__fakePlayers, player)
		if index then
			table.remove(__fakePlayers, index)
		end
		player.Parent = nil
		__playerRemoving:Fire(player)
	end

	local leaver, leaverPoints, droppedBot, returner, joiner = nil, nil, nil, nil, nil
	local prizeCoins = {}
	local finalCup = nil
	for r = 1, rounds do
		local id = modes[(r - 1) % #modes + 1]
		local parts = __cupModes[id]
		local definition = GameDefinitions.Get(id)
		local report = { round = r, mode = id }
		table.insert(summary.rounds, report)
		local roundPlayers = table.clone(__fakePlayers)
		local participants = table.clone(roundPlayers)
		for _, bot in bots do
			if bot.Parent then
				table.insert(participants, bot)
			end
		end
		local champion = nil
		local data = cupNow()
		if type(data) == "table" and data.Champion then
			for _, player in roundPlayers do
				if player.UserId == data.Champion.UserId then
					champion = player
				end
			end
		end
		GameState.Set("RoundId", r)
		GameState.Set("GameId", id)
		local ctx = RoundContext.new(r, definition, participants)
		local mode = parts.Mode().new(ctx)
		setPhase("Preparing", 13)
		local okPrepare, prepareErr = pcall(mode.Prepare, mode)
		report.prepare = if okPrepare then "ok" else tostring(prepareErr)
		local starting = okPrepare and ctx:WaitForStart(os.clock() + 1.5)
		if starting then
			ctx:Begin()
			setPhase("InRound", definition.Duration)
			local okStart, startErr = pcall(mode.Start, mode)
			report.start = if okStart then "ok" else tostring(startErr)
			ctx:RunBots(parts.Brain(), mode)
			local env = {
				ctx = ctx,
				game = mode,
				players = table.clone(roundPlayers),
				rng = Random.new(7 + r),
				note = __note,
				client = false,
			}
			function env.Action(player, name, ...)
				__remoteObjects.MiniGameAction.__bindable:Fire(__playerKey(player), name, ...)
			end
			function env.Root(player)
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				return root and root.Position
			end
			function env.Move(player, position, lookAt)
				local character = player.Character
				if character then
					if lookAt then
						character:PivotTo(CFrame.lookAt(position, Vector3.new(lookAt.X, position.Y, lookAt.Z)))
					else
						character:PivotTo(CFrame.new(position))
					end
				end
			end
			function env.Shared(key)
				return GameState.Get("MG_" .. key)
			end
			function env.SharedJSON(key)
				return GameState.GetJSON("MG_" .. key)
			end
			function env.Mine(player, key)
				return player:GetAttribute("MG_" .. key)
			end
			function env.Alive(player)
				return ctx:IsAlive(player)
			end
			env.Leave = leave
			local okTick, tick = pcall(parts.Script, env)
			if not okTick then
				__note(`{id} stand-in script failed: {tick}`)
				tick = nil
			end
			local begin, last = os.clock(), os.clock()
			local limit = math.min(seconds, definition.Duration)
			local crownChecked = false
			while not ctx.EndReason do
				local now = os.clock()
				if now - begin >= limit then
					ctx:TimeRanOut("HarnessStop")
					if ctx.EndReason then
						break
					end
				end
				-- The crown comes off for the rounds its wearer plays.
				if champion and not crownChecked and now - begin >= 2 then
					crownChecked = true
					local on = __crownOn(champion)
					check(`round {r}: the crown is off while {champion.Name} plays`, not on)
				end
				if tick then
					local okStep, stepErr = pcall(tick, now - begin, now - last)
					if not okStep then
						__note(`{id} stand-in error: {stepErr}`)
						tick = nil
					end
				end
				last = now
				task.wait(0.05)
			end
			report.endReason = ctx.EndReason
			pcall(mode.Stop, mode, ctx.EndReason)
			local okResults, results = pcall(mode.GetResults, mode)
			if okResults and results then
				local places = {}
				local placed = __require("Shared/Logic/Placement").Assign((function()
					local entries = {}
					for _, entry in results.Entries do
						if entry.Player.Parent then
							entry.Key = entry.Player
							table.insert(entries, entry)
						end
					end
					return entries
				end)())
				for _, item in placed do
					table.insert(
						places,
						`{item.Place} {item.Entry.Player.Name}{if item.Entry.Team then " " .. item.Entry.Team else ""}`
					)
				end
				report.places = places
				-- Each person's coins just before the podium is paid (after this round's rewards).
				local okGrant, grant = pcall(__grantRewards, definition, results, before)
				report.rewards = if okGrant then grant.granted else tostring(grant)
				for _, player in __fakePlayers do
					local profile = DataService.Get(player)
					prizeCoins[player] = if profile then profile.Data.Coins else nil
				end
			else
				report.results = tostring(results)
			end
		else
			report.calledOff = true
		end
		task.wait(0.3) -- CupService hears about the round in its own thread
		local afterRound = cupNow()
		report.cup = __cupLines(afterRound)
		if r <= PartyCup.Rounds then
			check(
				`round {r}: cup #1 has counted {r} of {PartyCup.Rounds}`,
				type(afterRound) == "table" and afterRound.Number == 1 and afterRound.Played == r,
				if type(afterRound) == "table" then `#{afterRound.Number} played {afterRound.Played}` else "no cup"
			)
		end
		if r == 1 and type(afterRound) == "table" then
			check(
				"round 1: everyone who played is in the standings, people and bots",
				#afterRound.Standings == #participants,
				`{#afterRound.Standings} of {#participants}`
			)
		end
		if r == PartyCup.Rounds then
			finalCup = afterRound
			check(
				"round 5: the cup is over and its final standings are out with the results",
				type(afterRound) == "table" and afterRound.Done == true,
				if type(afterRound) == "table" then tostring(afterRound.Done) else "no cup"
			)
		end
		if r == 4 and returner and leaverPoints then
			local row = __cupRow(afterRound, returner.UserId)
			check(
				"a person back during the cup has their points back",
				row ~= nil and row.Points == leaverPoints + row.Gain,
				if row then `{row.Points} = {leaverPoints} + {row.Gain}` else "not in the standings"
			)
			local fresh = __cupRow(afterRound, joiner.UserId)
			check(
				"someone who joined mid-cup starts at 0",
				fresh ~= nil and fresh.Points == fresh.Gain,
				if fresh then `{fresh.Points} pts, +{fresh.Gain}` else "not in the standings"
			)
		end

		setPhase("Results", 2)
		task.wait(2)
		setPhase("Cleanup")
		pcall(mode.Cleanup, mode)
		pcall(ctx.Destroy, ctx)
		task.wait(1.5)
		local afterCleanup = cupNow()
		report.cupAfterCleanup = __cupLines(afterCleanup)

		if r == PartyCup.Rounds and type(finalCup) == "table" then
			-- The podium was paid as the results card ended.
			local standings = finalCup.Standings
			local paid, stats = {}, {}
			local payOk, statsOk = true, true
			for _, row in standings do
				local player = nil
				for _, candidate in __fakePlayers do
					if candidate.UserId == row.UserId then
						player = candidate
					end
				end
				if not player then
					continue
				end
				local profile = DataService.Get(player)
				local got = if profile and prizeCoins[player] then profile.Data.Coins - prizeCoins[player] else -1
				local want = PartyCup.PrizeFor(row.Place)
				table.insert(paid, `{player.Name} {row.Place}: +{got} (want +{want})`)
				payOk = payOk and got == want
				local cups = profile and profile.Data.Cups
				local wantStats = `1/{if row.Place == 1 then 1 else 0}/{if row.Place <= 3 then 1 else 0}`
				local gotStats = if cups then `{cups.Played}/{cups.Wins}/{cups.Podiums}` else "none"
				table.insert(stats, `{player.Name}: played/wins/podiums {gotStats} (want {wantStats})`)
				statsOk = statsOk and gotStats == wantStats
			end
			summary.cups[1] = { final = __cupLines(finalCup), paid = paid, stats = stats }
			check("cup #1: the podium pays people 5, 3 and 2 coins (and nobody else)", payOk, table.concat(paid, "; "))
			check("cup #1: everyone in it has the cup in their stats", statsOk, table.concat(stats, "; "))
			local winner = standings[1]
			local medal = winner and not winner.IsBot and table.find(medals, `{winner.Name} CupChampion`) ~= nil
			check(
				"cup #1: the champion's medal (a person) or none (a bot)",
				if winner and winner.IsBot then #medals == 0 else medal,
				`winner {winner and winner.Name}, medals: {table.concat(medals, ", ")}`
			)
			check(
				"cup #1: a new cup starts, with cup #1's podium as the last one",
				type(afterCleanup) == "table"
					and afterCleanup.Number == 2
					and afterCleanup.Played == 0
					and not afterCleanup.Done
					and afterCleanup.Last ~= nil
					and afterCleanup.Last.Number == 1,
				__cupLines(afterCleanup)[1]
			)
			for _, player in __fakePlayers do
				local on, detail = __crownOn(player)
				local row = __cupRow(finalCup, player.UserId)
				local isChampion = row ~= nil and row.Place == 1 -- (people level for 1st share the crown)
				if on or isChampion then
					check(`cup #1: the crown is on the champion only ({player.Name})`, on == isChampion, detail)
				end
			end
			if winner and winner.IsBot then
				check("cup #1: a bot won, so nobody wears the crown", afterCleanup.Champion == nil)
			end
		end
		if r == PartyCup.Rounds + 1 and type(afterCleanup) == "table" then
			check(
				"round 6 is cup #2's first round",
				afterCleanup.Number == 2 and afterCleanup.Played == 1,
				__cupLines(afterCleanup)[1]
			)
			if champion then
				local on = __crownOn(champion)
				check(`the crown is back on {champion.Name} after the round`, on)
			end
		end

		-- Comings and goings between rounds.
		if r == 2 then
			leaver = __fakePlayers[#__fakePlayers]
			leaverPoints = (__cupRow(afterCleanup, leaver.UserId) or { Points = 0 }).Points
			leave(leaver)
			droppedBot = bots[#bots]
			BotService.Remove(droppedBot)
			task.wait(0.3)
			local now = cupNow()
			check("a person who leaves drops off the standings", __cupRow(now, leaver.UserId) == nil)
			check("a bot that fades out drops off the standings", __cupRow(now, droppedBot.UserId) == nil)
		elseif r == 3 then
			returner = __newPlayer(people) -- the leaver's index, so the same UserId
			table.insert(__fakePlayers, returner)
			__cupProfile(returner, before)
			joiner = __newPlayer(people + 1)
			table.insert(__fakePlayers, joiner)
			__cupProfile(joiner, before)
		end
	end

	-- Cup 2, finished with made-up rounds so a person surely wins it: Bot1 first every time.
	local bot1 = __fakePlayers[1]
	local function madeUpRound(order)
		local placed = {}
		for index, who in order do
			table.insert(placed, { Key = who, Rank = #order - index, Place = index, Entry = { Player = who } })
		end
		RoundEvents.Finished:Fire(GameDefinitions.Get(modes[1]), placed, nil)
		task.wait(0.2)
	end
	local everyone = table.clone(__fakePlayers)
	for _, bot in bots do
		if bot.Parent then
			table.insert(everyone, bot)
		end
	end
	local data = cupNow()
	local still = if type(data) == "table" then PartyCup.Rounds - data.Played else 0
	for _ = 1, still do
		setPhase("InRound", 10)
		madeUpRound(everyone)
	end
	local final2 = cupNow()
	check("cup #2: done after its 5th round", type(final2) == "table" and final2.Number == 2 and final2.Done == true)
	setPhase("Results", 1)
	task.wait(1.2)
	setPhase("Cleanup")
	task.wait(3) -- the payout, then the crowning effect over the new champion
	local after2 = cupNow()
	summary.cups[2] = { final = __cupLines(final2), after = __cupLines(after2) }
	local on, detail = __crownOn(bot1)
	check("cup #2: Bot1 won and wears the crown", on, detail)
	check(
		"cup #2: the attribute says who wears it",
		type(after2) == "table" and after2.Champion ~= nil and after2.Champion.UserId == bot1.UserId,
		__cupLines(after2)[1]
	)
	check(
		"cup #2: the CupChampion medal for Bot1",
		table.find(medals, `{bot1.Name} CupChampion`) ~= nil,
		table.concat(medals, ", ")
	)
	check(
		"the crowning effect over the champion",
		(__eventCounts["PlayEffect:Crowns"] or 0) >= 1,
		__eventCounts["PlayEffect:Crowns"]
	)

	-- The crown in the lobby: off for a round they play, back after, on a fresh character too.
	bot1:SetAttribute("PP_InRound", true)
	task.wait(0.2)
	check("the crown comes off when its wearer is put in a round", not (__crownOn(bot1)))
	bot1:SetAttribute("PP_InRound", false)
	task.wait(0.2)
	check("and goes back on when they're back", (__crownOn(bot1)))
	bot1:LoadCharacterAsync()
	task.wait(0.5)
	check("a fresh character (a reset) gets it too", (__crownOn(bot1)))
	leave(bot1)
	task.wait(0.3)
	local gone = cupNow()
	check(
		"leaving the server takes the crown away (and off the attribute)",
		type(gone) == "table" and gone.Champion == nil,
		__cupLines(gone)[1]
	)

	check("the cup sends no toasts (the podium says it all)", #toasts == 0, table.concat(toasts, " | "))
	summary.medals = medals
	summary.toasts = toasts
	summary.effects = { crowns = __eventCounts["PlayEffect:Crowns"], confetti = __eventCounts["PlayEffect:Confetti"] }
	summary.cupJsonBytes = #(GameState.Get("Cup") or "")
	summary.errors = __errors
	summary.log = __log
	for _, bot in bots do
		BotService.Remove(bot)
	end
	return HttpService:JSONEncode(summary)
end
