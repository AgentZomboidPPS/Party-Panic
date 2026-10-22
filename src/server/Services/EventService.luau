-- Limited-time events (the HALLOWEEN PARTY first) and double coins weekends (owner, asked what keeps
-- players coming back, then: "Can you work on all of that? this wont mess with what the other
-- workers are working on right?"; the idea they were offered: "a Halloween event: candy, free
-- limited rewards like a pumpkin hat, a banner with a countdown, lobby decorations and lighting;
-- and double coins weekends").
--
--   * What's on: Shared/Events has the schedule (one line per date, UTC). Every few seconds this
--     works out what's on now (Logic/EventLogic.State) and publishes it as GameState "Event" (JSON:
--     Id, Name, EndsAt, DoubleCoins, DoubleEndsAt; "" when nothing is), which each device counts
--     down from. Servers run for days, so the lobby's decorations (World/EventDecor) are put up and
--     taken down here when an event starts or ends.
--   * Candy (🍬): every person in a round gets a little when it ends (RoundEvents.Finished: 1 for
--     playing, 1 more for the top half, 2 more for a win), and a few golden pumpkins hide in the
--     lobby each day (a touch finds one, once per player per day, like the daily secret token).
--     Bots never get any. Saved in profile.Events[<event id>] = { Candy, Claimed, Found }.
--   * The free reward track: cosmetics nobody can buy, claimed in the event screen through the
--     EventAction remote ("Claim", rewardId), checked here and rate limited. Reaching the end of the
--     track gives the event's medal (MedalService.Award). Rewards reached but never claimed are
--     given when the event ends (or on the next visit after it), so nobody loses one.
--   * Double coins weekends: a boost (Services/Boosts) that pays the round's coins again, with its
--     own line on the results card ("2× COINS WEEKEND"). It's registered after the other features'
--     boosts (EventService starts last), so it doubles a friend bonus too.
-- A test run (workspace attribute PP_Harness) can move this service's clock (SetClockForTests), to
-- check a Saturday on a Thursday; nothing else changes for tests (profiles there are never saved).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Cosmetics = require(Shared.Cosmetics)
local EventLogic = require(Shared.Logic.EventLogic)
local Events = require(Shared.Events)
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)

local EventDecor = require(script.Parent.Parent.World.EventDecor)
local Boosts = require(script.Parent.Boosts)
local BotRegistry = require(script.Parent.BotRegistry)
local DataService = require(script.Parent.DataService)
local MedalService = require(script.Parent.MedalService)
local Notifier = require(script.Parent.Notifier)
local RateLimiter = require(script.Parent.RateLimiter)
local RoundEvents = require(script.Parent.RoundEvents)
local Telemetry = require(script.Parent.Telemetry)

local EventService = {}

local REFRESH_EVERY = 5 -- seconds between looks at the clock (an event or a weekend turns over)
local PUMPKIN_REACH = 9 -- studs: how far from a hidden pumpkin a player touching it may stand
local HALLOWEEN_ORANGE = Color3.fromRGB(255, 150, 40)

local clock: (() -> number)? = nil -- a test run's clock (SetClockForTests)
local published: string? = nil -- GameState "Event" as last set
local eventOn: string? = nil -- the event on at the last look
local huntDay: number? = nil -- the day today's hidden pumpkins are out for
local touchedAt: { [any]: number } = {}

local function now(): number
	return if clock then clock() else os.time()
end

-- The event on now (its entry in Shared/Events), if any.
function EventService.Current(): Events.Event?
	return (EventLogic.Active(Events.List, now()))
end

-- True on a double coins weekend.
function EventService.DoubleCoins(): boolean
	return Events.DoubleCoinsWeekends and EventLogic.WeekendEndsAt(now()) ~= nil
end

-- A person in the game with a loaded profile (never a bot, never someone who just left).
local function profileOf(player: any): DataService.Profile?
	if BotRegistry.IsBot(player) or not player.Parent then
		return nil
	end
	return DataService.Get(player)
end

-- This player's progress in `event` (profile.Events[<id>], made whole on first use).
local function progressOf(profile: DataService.Profile, event: Events.Event): EventLogic.Progress
	local events = profile.Data.Events
	if type(events) ~= "table" then
		events = {}
		profile.Data.Events = events
	end
	local saved = events[event.Id]
	if type(saved) ~= "table" then
		saved = {}
		events[event.Id] = saved
	end
	return EventLogic.Progress(saved)
end

local function awardMedal(player: Player, event: Events.Event)
	local medal = event.Medal
	if medal then
		local ok, err = pcall(MedalService.Award, player, medal)
		if not ok then
			Telemetry.Error("EventMedal", `{event.Id}: {err}`)
		end
	end
end

-- Adds candy (and gives the medal when it reaches the end of the track).
local function addCandy(
	player: Player,
	profile: DataService.Profile,
	event: Events.Event,
	amount: number,
	reason: string
)
	if amount <= 0 then
		return
	end
	local progress = progressOf(profile, event)
	local complete = EventLogic.Complete(progress, event.Track)
	progress.Candy += math.floor(amount)
	Telemetry.PlayerEvent(player, "EventCandy", amount, reason)
	if not complete and EventLogic.Complete(progress, event.Track) then
		awardMedal(player, event)
	end
	DataService.Changed(player)
end

-- Rewards the candy reached but never claimed, given now (the event is over). The names given.
local function giveUnclaimed(profile: DataService.Profile, event: Events.Event): { string }
	local saved = profile.Data.Events and profile.Data.Events[event.Id]
	if type(saved) ~= "table" then
		return {}
	end
	local progress = EventLogic.Progress(saved)
	local names = {}
	for _, rewardId in EventLogic.Claimable(progress, event.Track) do
		local item = Cosmetics.Get(rewardId)
		if item then
			EventLogic.Claim(progress, event.Track, rewardId)
			profile.Data.Owned[rewardId] = true
			table.insert(names, `{item.Icon} {item.Name}`)
		end
	end
	return names
end

local function tellUnclaimed(player: Player, event: Events.Event, names: { string })
	if #names > 0 then
		Notifier.Send(
			player,
			`The {event.Name} is over! Your rewards are in the Shop: {table.concat(names, ", ")}.`,
			"reward",
			8
		)
		DataService.Changed(player)
	end
end

-- Rounds ---------------------------------------------------------------------------------------------

-- A round ended normally (RoundEvents.Finished, after its coins): candy for every person in it.
local function onRoundFinished(definition, placed, _winningTeam)
	local event = EventService.Current()
	if not event then
		return
	end
	local count = #placed
	for _, item in placed do
		local player = item.Entry.Player
		local profile = profileOf(player)
		if profile then
			-- One player's trouble never costs the others their candy.
			local ok, err = pcall(function()
				addCandy(player, profile, event, EventLogic.RoundCandy(item.Place, count, event.Candy), definition.Id)
			end)
			if not ok then
				Telemetry.Error("EventCandy", tostring(err))
			end
		end
	end
end

-- The reward track -------------------------------------------------------------------------------------

local function claim(player: Player, rewardId: any)
	if type(rewardId) ~= "string" or #rewardId > 64 then
		return
	end
	local event = EventService.Current()
	local profile = profileOf(player)
	if not event or not profile then
		return
	end
	local item = Cosmetics.Get(rewardId)
	if not item or item.Event ~= event.Id then
		return
	end
	local progress = progressOf(profile, event)
	if not EventLogic.Claim(progress, event.Track, rewardId) then
		return -- (the screen only offers what can be claimed; a stale tap does nothing)
	end
	profile.Data.Owned[rewardId] = true
	-- The event screen (a window, over the toasts) shows the claim itself: the card pops and offers
	-- EQUIP. Here, a sound and a sparkle for everyone around.
	Notifier.Sound({ player }, "Purchase")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		Notifier.Effect("Sparkles", root.Position + Vector3.new(0, 3, 0), { HALLOWEEN_ORANGE })
	end
	local _, index = EventLogic.Step(event.Track, rewardId)
	Telemetry.PlayerEvent(player, "EventClaim", index or 0, rewardId)
	DataService.Changed(player)
end

-- The pumpkin hunt -------------------------------------------------------------------------------------

-- `player` found the hidden pumpkin at `spot` (EventDecor.HuntSpots): candy the first time today.
-- The server checks it's out today and that the player is standing at it. True when it counted.
function EventService.FindPumpkin(player: Player, spot: any): boolean
	local event = EventService.Current()
	local profile = profileOf(player)
	if not event or not profile or type(spot) ~= "number" then
		return false
	end
	local spots = EventDecor.HuntSpots(event.Decor)
	local where = spots[spot]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not where or not root then
		return false
	end
	local offset = root.Position - where
	if Vector3.new(offset.X, 0, offset.Z).Magnitude > PUMPKIN_REACH then
		return false
	end
	local perDay = event.Candy.PumpkinsPerDay
	local day = EventLogic.DayNumber(now())
	local progress = progressOf(profile, event)
	if not EventLogic.FindPumpkin(progress, day, spot, EventLogic.HuntSpots(day, #spots, perDay)) then
		return false
	end
	local candy = event.Candy.Pumpkin
	addCandy(player, profile, event, candy, "Pumpkin")
	local found = EventLogic.FoundToday(progress, day)
	Notifier.Send(
		player,
		if found >= perDay
			then `🎃 You found all {perDay} hidden pumpkins today! +{candy} 🍬 New ones tomorrow.`
			else `🎃 You found a hidden pumpkin! +{candy} 🍬 ({found} of {perDay} today)`,
		"reward",
		5
	)
	Notifier.Sound({ player }, "Pickup")
	Notifier.Effect("Sparkles", where + Vector3.new(0, 2, 0), { Color3.fromRGB(255, 220, 110) })
	Telemetry.PlayerEvent(player, "EventPumpkin", found, event.Id)
	return true
end

local function onPumpkinTouched(hit: BasePart, spot: number)
	local character = hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	local clockNow = os.clock()
	if clockNow - (touchedAt[player] or 0) < 1 then
		return
	end
	touchedAt[player] = clockNow
	EventService.FindPumpkin(player, spot)
end

-- Today's hidden pumpkins (the event's decorations are up).
local function placeHunt(event: Events.Event, day: number)
	local decorSet = event.Decor
	local spots = EventDecor.HuntSpots(decorSet)
	if not decorSet or #spots == 0 then
		return
	end
	local today = EventLogic.HuntSpots(day, #spots, event.Candy.PumpkinsPerDay)
	for _, model in EventDecor.PlaceHunt(decorSet, today) do
		model:SetAttribute("Event", event.Id)
		model:SetAttribute("Day", day)
		local spot = model:GetAttribute("Spot")
		local hitbox = model:FindFirstChild("Hitbox")
		if hitbox and hitbox:IsA("BasePart") and type(spot) == "number" then
			hitbox.Touched:Connect(function(hit)
				onPumpkinTouched(hit, spot)
			end)
		end
	end
end

-- The schedule ----------------------------------------------------------------------------------------

-- Looks at the clock: publishes what's on, puts the decorations up or down, moves the hidden
-- pumpkins at midnight, and gives everyone here what they reached in an event that just ended.
local function refresh()
	local time = now()
	local state = EventLogic.State(Events.List, Events.DoubleCoinsWeekends, time)
	local encoded = if state then HttpService:JSONEncode(state) else ""
	if encoded ~= published then
		published = encoded
		GameState.Set("Event", encoded)
	end

	local event = EventService.Current()
	local id = if event then event.Id else nil
	if id ~= eventOn then
		local ended = Events.Get(eventOn)
		eventOn = id
		huntDay = nil
		local ok, err = pcall(EventDecor.Show, if event then event.Decor else nil)
		if not ok then
			Telemetry.Error("EventDecor", tostring(err))
		end
		if ended then
			for player, profile in DataService.All() do
				tellUnclaimed(player, ended, giveUnclaimed(profile, ended))
			end
		end
	end
	local day = EventLogic.DayNumber(time)
	if event and day ~= huntDay and EventDecor.Showing() == event.Decor then
		huntDay = day
		local ok, err = pcall(placeHunt, event, day)
		if not ok then
			Telemetry.Error("EventDecor", `hunt: {err}`)
		end
	end
end

-- A player joins: rewards they reached in an event that's over since they last played, and the
-- medal for a track they finished (if the medal came after they did).
local function onProfileLoaded(player: Player, profile: DataService.Profile)
	local time = now()
	for _, event in Events.List do
		local saved = profile.Data.Events and profile.Data.Events[event.Id]
		if type(saved) ~= "table" then
			continue
		end
		local progress = EventLogic.Progress(saved)
		if EventLogic.Complete(progress, event.Track) then
			awardMedal(player, event)
		end
		local ends = EventLogic.ParseUtc(event.Ends)
		if ends and time >= ends then
			local names = giveUnclaimed(profile, event)
			task.delay(8, function()
				if player.Parent then
					tellUnclaimed(player, event, names)
				end
			end)
		end
	end
end

-- Test runs only (workspace PP_Harness): this service's clock, e.g. a Saturday. Nil goes back to the
-- real one.
function EventService.SetClockForTests(fake: (() -> number)?)
	if workspace:GetAttribute("PP_Harness") ~= true then
		warn("[EventService] SetClockForTests is for test runs only")
		return
	end
	clock = fake
	refresh()
end

function EventService.Init()
	-- Last of the boosts: pays the round's coins again (a friend bonus included).
	Boosts.Register("DoubleCoins", function(_player, round)
		if EventService.DoubleCoins() then
			return round.Coins, "2× COINS WEEKEND"
		end
		return 0, nil
	end)
	RoundEvents.Finished:Connect(onRoundFinished)
	local limits = Config.RateLimits.Claim
	local limiter = RateLimiter.new(limits[1], limits[2])
	Remotes.Get("EventAction").OnServerEvent:Connect(function(player, action, ...)
		if action == "Claim" and limiter:Check(player) then
			claim(player, ...)
		end
	end)
	DataService.ProfileLoaded:Connect(onProfileLoaded)
	Players.PlayerRemoving:Connect(function(player)
		touchedAt[player] = nil
	end)
	local ok, err = pcall(refresh)
	if not ok then
		Telemetry.Error("Event", tostring(err))
	end
end

function EventService.Start()
	while true do
		task.wait(REFRESH_EVERY)
		local ok, err = pcall(refresh)
		if not ok then
			Telemetry.Error("Event", tostring(err))
		end
	end
end

return EventService
