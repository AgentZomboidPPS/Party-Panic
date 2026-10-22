-- Scenario for round_harness.py --bot: the HALLOWEEN PARTY and a double coins weekend on a real
-- server (Services/EventService). Any mode works; the stand-ins don't play it (Rake It In: they
-- score nothing, the bots do).
--
--   python3 tools/checks/round_harness.py RakeItIn --players 3 --bots 2 --seconds 15 \
--       --bot tools/checks/scenarios/Event_halloween.luau > event.luau
--
-- What it checks (each line of the run's log starts with "event:"):
--   * the clock moved to Halloween, Saturday 31 October 12:00 UTC: GameState "Event" says the party
--     and a double coins weekend are on;
--   * during the round, claims through the EventAction remote: Bot1 (99 candy) taps every reward
--     at once: three go through (the rate limit) and the 100-candy one never does; it claims the
--     fourth and fifth (the PUMPKIN HAT and BAT BURST) 2.5 s later. Bot2 (9 candy) can't claim the
--     first. Bad payloads do nothing;
--   * after the round: each stand-in's results lines (the "2× COINS WEEKEND" line pays the round's
--     coins again), the candy it paid (bots get none), the medal for Bot1 reaching the end of the
--     track (once), the golden pumpkin hunt for Bot3 (today's spot, once, not from afar, not a spot
--     with nothing), then the clock moved past the end: the rewards reached but not claimed are given,
--     and double coins are on only on the party's weekends (24 Oct and 1 Nov yes; 7 and 8 Nov no).
return function(env)
	local EventService = __require("Server/Services/EventService")
	local EventLogic = __require("Shared/Logic/EventLogic")
	local EventDecor = __require("Server/World/EventDecor")
	local Events = __require("Shared/Events")
	local DataService = __require("Server/Services/DataService")
	local MedalService = __require("Server/Services/MedalService")
	local Boosts = __require("Server/Services/Boosts")
	local RoundEvents = __require("Server/Services/RoundEvents")
	local GameState = __require("Shared/GameState")
	local BotRegistry = __require("Server/Services/BotRegistry")

	local function note(text)
		env.note("event: " .. text)
	end
	local event = Events.Get("Halloween2026")
	local track = event.Track
	local bot1, bot2, bot3 = env.players[1], env.players[2], env.players[3]

	note(`before: GameState Event = {GameState.Get("Event")}`)
	local halloween = EventLogic.ParseUtc("2026-10-31 12:00") :: number
	local started = os.clock()
	local function fakeNow()
		return halloween + (os.clock() - started)
	end
	EventService.SetClockForTests(fakeNow)
	note(`Saturday: GameState Event = {GameState.Get("Event")}`)

	-- Candy to start from (the profiles are the harness's, never saved).
	local function progress(player)
		local profile = DataService.Get(player)
		profile.Data.Events.Halloween2026 = profile.Data.Events.Halloween2026 or {}
		return EventLogic.Progress(profile.Data.Events.Halloween2026)
	end
	progress(bot1).Candy = 99
	progress(bot2).Candy = 9
	local function describe(player)
		local mine = progress(player)
		local claimed, owned = {}, {}
		for _, step in track do
			if mine.Claimed[step.Reward] then
				table.insert(claimed, step.Reward)
			end
			if DataService.Get(player).Data.Owned[step.Reward] then
				table.insert(owned, step.Reward)
			end
		end
		return `{player.Name}: candy {mine.Candy}, claimed [{table.concat(claimed, ",")}], owned [{table.concat(
			owned,
			","
		)}]`
	end

	-- Every medal given, and every stand-in's results lines.
	local medals = {}
	local realAward = MedalService.Award
	MedalService.Award = function(player, id)
		table.insert(medals, `{player.Name}:{id}`)
		return realAward(player, id)
	end
	local realApply = Boosts.Apply
	Boosts.Apply = function(player, reward, round)
		realApply(player, reward, round)
		local lines = {}
		for _, line in reward.Lines do
			table.insert(lines, `{line.Label} +{line.Coins}`)
		end
		note(
			`{player.Name} place {round.Place}/{round.PlayerCount}: {table.concat(lines, " | ")} = {reward.Coins} coins`
		)
	end

	local function send(player, ...)
		__remoteObjects.EventAction.__bindable:Fire(__playerKey(player), ...)
	end

	-- During the round: claims through the remote.
	task.spawn(function()
		task.wait(0.5)
		for _, step in track do
			send(bot1, "Claim", step.Reward)
		end
		send(bot2, "Claim", track[1].Reward)
		send(bot3, "Claim", 12345)
		send(bot3, "Claim", string.rep("x", 100))
		send(bot3, "Nope", track[1].Reward)
		task.wait(0.6)
		note(`a burst of {#track} claims: ` .. describe(bot1))
		note("too early: " .. describe(bot2))
		note("bad payloads: " .. describe(bot3))
		task.wait(2.2)
		send(bot1, "Claim", track[4].Reward)
		send(bot1, "Claim", track[5].Reward)
		task.wait(0.6)
		note("2.8 s later: " .. describe(bot1))
	end)

	-- After the round (its rewards and candy are in: RoundEvents.Finished, then this, deferred).
	RoundEvents.Finished:Connect(function()
		task.defer(function()
			for _, player in env.players do
				note("after the round: " .. describe(player))
			end
			for _, bot in BotRegistry.List() do
				note(`{bot.DisplayName}: profile {if DataService.Get(bot) then "YES (wrong)" else "none, no candy"}`)
			end
			note(`medals given: [{table.concat(medals, ", ")}]`)

			-- The pumpkin hunt (Bot3): today's spots under the fake clock.
			local spots = EventDecor.HuntSpots(event.Decor)
			local day = EventLogic.DayNumber(fakeNow())
			local today = EventLogic.HuntSpots(day, #spots, event.Candy.PumpkinsPerDay)
			note(`hunt: day {day}, today's spots {table.concat(today, ",")} of {#spots}`)
			local empty = 1
			while table.find(today, empty) do
				empty += 1
			end
			local before = progress(bot3).Candy
			env.Move(bot3, spots[today[1]] + Vector3.new(1, 3, 1))
			local first = EventService.FindPumpkin(bot3, today[1])
			local again = EventService.FindPumpkin(bot3, today[1])
			env.Move(bot3, spots[empty] + Vector3.new(0, 3, 0))
			local nothing = EventService.FindPumpkin(bot3, empty)
			env.Move(bot3, spots[today[2]] + Vector3.new(25, 3, 0))
			local far = EventService.FindPumpkin(bot3, today[2])
			env.Move(bot3, spots[today[2]] + Vector3.new(0, 3, 2))
			local second = EventService.FindPumpkin(bot3, today[2])
			local found = EventLogic.FoundToday(progress(bot3), day)
			note(
				`hunt: first {first}, again {again}, empty spot {nothing}, from 25 studs {far}, second {second}; `
					.. `candy {before} -> {progress(bot3).Candy}, found today {found}`
			)

			-- The party ends: the rewards reached but not claimed are given.
			local over = EventLogic.ParseUtc(event.Ends) :: number
			EventService.SetClockForTests(function()
				return over + 10
			end)
			note(`after the end: GameState Event = "{GameState.Get("Event")}"`)
			for _, player in env.players do
				note("after the end: " .. describe(player))
			end
			-- No double coins after it, weekends included (owner: no double coins after Halloween).
			local doubles = {}
			for _, when in { "2026-10-24 09:00", "2026-11-01 23:00", "2026-11-07 12:00", "2026-11-08 12:00" } do
				local at = EventLogic.ParseUtc(when) :: number
				EventService.SetClockForTests(function()
					return at
				end)
				table.insert(doubles, `{when} {EventService.DoubleCoins()}`)
			end
			note(`double coins: {table.concat(doubles, ", ")}`)
			EventService.SetClockForTests(nil)
			MedalService.Award, Boosts.Apply = realAward, realApply
		end)
	end)

	return function() end
end
