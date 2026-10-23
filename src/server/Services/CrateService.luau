-- Crate seasons (owner: "seasonal crates are awarded at end of match. every player gets one crate per
-- match. Keys to open the crate are available to be awarded upon winning", then, for the first
-- season: "Hollow night comes first I want you to actually work on adding it to the game right now.
-- The season should always run ... Also do all of your ideas. This has to be sick. This will be
-- players first season. I want it to look insane."). The season is Shared/Seasons.Current (it runs
-- until the next one is named there); what's in a crate and how it's rolled is Logic/CrateLogic.
--
-- Earning (all server side, never for bots, the check tools' stand-ins or anyone without a profile):
--   * a crate for every round a person plays to the end (RewardService: it's on the results card),
--     the same rule round coins use, so nobody farms them standing still in the lobby;
--   * keys from a Party Cup (CupService: 3 / 2 / 1 on the podium, 1 more for playing all 5 rounds, 1
--     more on the podium for a GOLD PASS owner, 1 more for the first cup finished each day, UTC);
--   * 3 keys to start (once per player), a crate with the season's welcome (once per season), a key
--     for each weekly quest finished (QuestService) and every 5th level (ProgressionService);
--   * keys bought with Robux (KeyShopService).
-- Keys work in every season and never expire. Unopened crates are the season's they were earned
-- in; when a new season starts they become its crates, one for one, the next time the player joins.
--
-- Opening (owner's design: "open like the mystery box in CoD Zombies, right there where everyone
-- can watch"): one crate and one key each. At one of the pile's three altars (World/SeasonWorld:
-- its prompt, or the HUD's OPEN CRATES walking them there), or over their own head when every
-- altar is busy (the menu's OPEN HERE). "Open 5" opens five at once in one bigger show. Lobby only
-- (never while they play a round), one show at a time per player and one opener per altar. The
-- server rolls, saves the prize into the profile (a pet or the title is saved to the DataStore at
-- once) and only then tells every screen to play the same show ("Show"); leaving, lagging out or
-- being pulled into a round mid-show never loses a prize. A Roblox friend standing close by adds a
-- point to the Lantern Meter (the watch-party bonus). When the reel ends: the prize goes on (a new
-- pet, hat, aura or the title is put on at once; anything else if its slot is empty), a pet or the
-- title puts a banner on every screen here ("Banner"), and the title a message on every other
-- server too (CrateBoardService). The first person in the world to find each pet and the title is
-- named on the Top Unboxers board.
--
-- Milestones: 10, 50, 100, 250 and 500 crates opened (every season together) give the name tag a
-- frame (PP_CrateFrame, CosmeticService); finding every pet of a season gives that season's pets a
-- sparkle for good, and all 23 items the season's own frame.
--
-- Remote "Crate" (client -> server): "Open" (count 1 or 5, altar index or 0 for over the head),
-- "Welcome" (the season's welcome was seen: its crate), "Buy" (pack key, gift UserId?: KeyShopService).
-- Server -> client: "Show" (everyone: an opening to play), "Banner" (everyone: a pet or title pull),
-- "Gift" (one player: keys or crates they were just given, and why), "Denied" (one player: why an
-- open didn't happen: NoKeys opens the key shop).
--
-- Analytics: the Crates funnel (first crate, first open, 10 and 50 opened, bought keys: Logic/
-- Funnels), the coins crates pay in the economy report (reason "Crate"), and an event for every
-- open and every rare pull.
--
-- Tests: TestGive and TestRolls only under the check tools' flag (workspace PP_Harness).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local CrateLogic = require(Shared.Logic.CrateLogic)
local DailyLogic = require(Shared.Logic.DailyLogic)
local Funnels = require(Shared.Logic.Funnels)
local Remotes = require(Shared.Remotes)
local Seasons = require(Shared.Seasons)

local BotRegistry = require(script.Parent.BotRegistry)
local CosmeticService = require(script.Parent.CosmeticService)
local CrateBoardService = require(script.Parent.CrateBoardService)
local DataService = require(script.Parent.DataService)
local FriendsService = require(script.Parent.FriendsService)
local Notifier = require(script.Parent.Notifier)
local RateLimiter = require(script.Parent.RateLimiter)
local Telemetry = require(script.Parent.Telemetry)

local SeasonWorld = require(script.Parent.Parent.World.SeasonWorld)

local CrateService = {}

local remote = Remotes.Get("Crate")
local season = Seasons.CurrentSeason()
local rng = Random.new()
local random: () -> number = function()
	return rng:NextNumber()
end

export type Show = {
	Id: number,
	UserId: number,
	Name: string,
	Altar: number, -- 1 to 3, or 0: over the opener's head
	Season: string,
	At: number, -- server time (workspace:GetServerTimeNow()) it started
	Duration: number,
	RevealAt: number, -- seconds in: the prize shows
	Results: { { Tier: string, Item: string?, Coins: number, Jackpot: boolean, Guaranteed: boolean, Crate: number } },
	Friend: boolean, -- a friend nearby added to the meter
	Meter: number, -- the Lantern Meter after it
}

type Altar = { Index: number, Model: Model, Prompt: ProximityPrompt?, Position: Vector3, Busy: Player?, Until: number }

local altars: { Altar } = {}
local showing: { [Player]: number } = {} -- os.clock() their show ends
-- The day (UTC) each player's coming cup keys counted the day's first cup key for (CupKeysFor at the
-- cup's end, GiveCupKeys when they're paid a few seconds later, maybe past midnight).
local cupDays: { [Player]: number } = {}
local shows = 0
local limiter = RateLimiter.new(Config.RateLimits.Crate[1], Config.RateLimits.Crate[2])

-- A person who's still here (bots look like players but are flagged; the check tools' stand-ins are
-- tables like bots, with a UserId above 0).
local function isPerson(player: any): boolean
	return player ~= nil
		and player.Parent ~= nil
		and not BotRegistry.IsBot(player)
		and type(player.UserId) == "number"
		and player.UserId > 0
end

local function harness(): boolean
	return workspace:GetAttribute("PP_Harness") == true
end

local function today(): number
	return DailyLogic.DayNumber(os.time())
end

-- A season's progress in a profile (made on first use).
local function progressOf(data: any, seasonId: string): { [string]: any }
	local progress = data.Seasons[seasonId]
	if type(progress) ~= "table" then
		progress = { Earned = 0, Opened = 0, Coins = 0, Meter = 0, Week = 0, WeekOpened = 0, Found = {} }
		data.Seasons[seasonId] = progress
	end
	return progress
end

-- Crates opened over every season (the milestones and the name tag's frame count these).
local function lifetimeOpened(data: any): number
	local total = 0
	for _, progress in data.Seasons do
		total += progress.Opened or 0
	end
	return total
end

-- The Crates funnel (once per player: its run is their UserId).
local function funnelStep(player: Player, index: number)
	Telemetry.FunnelStep(player, Funnels.Crates.Name, tostring(player.UserId), index, Funnels.Crates.Steps[index], {
		season.Id,
	})
end
CrateService.FunnelStep = funnelStep

-- The name tag's frame, the pets' set sparkle and the season frame (CosmeticService draws them).
local function refreshMarks(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local data = profile.Data :: any
	player:SetAttribute("PP_CrateFrame", CrateLogic.FrameFor(lifetimeOpened(data)))
	local complete = ""
	local petSets = {}
	for _, id in Seasons.Order do
		local info = Seasons.Get(id)
		if info then
			local have, total = CrateLogic.Progress(info, data.Owned)
			if total > 0 and have == total then
				complete = id -- (the latest season finished wins)
			end
			if #CrateLogic.Missing(info, "Pet", data.Owned) == 0 then
				table.insert(petSets, id)
			end
		end
	end
	player:SetAttribute("PP_SeasonComplete", complete)
	player:SetAttribute("PP_PetSets", table.concat(petSets, ","))
end
CrateService.RefreshMarks = refreshMarks

-- Gives keys (and says why on their screen). Never to bots.
function CrateService.GiveKeys(player: Player, amount: number, reason: string, detail: string?): boolean
	local profile = DataService.Get(player)
	if not isPerson(player) or not profile or amount <= 0 then
		return false
	end
	local data = profile.Data :: any
	data.Keys += math.floor(amount)
	Telemetry.PlayerEvent(player, "KeysEarned", amount, reason)
	Telemetry.Keys(player, math.floor(amount), data.Keys, reason, detail)
	remote:FireClient(player, "Gift", { Keys = math.floor(amount), Reason = reason, Detail = detail })
	DataService.Changed(player)
	return true
end

-- Gives crates of this season.
local function giveCrates(player: Player, amount: number): boolean
	local profile = DataService.Get(player)
	if not isPerson(player) or not profile or amount <= 0 then
		return false
	end
	local data = profile.Data :: any
	data.Crates.Season = season.Id
	data.Crates.Count += amount
	local progress = progressOf(data, season.Id)
	local before = 0
	for _, other in data.Seasons do
		before += other.Earned or 0
	end
	progress.Earned += amount
	if before == 0 then
		funnelStep(player, 1)
	end
	DataService.Changed(player)
	return true
end

-- RewardService: a person played a round to the end, so they get its crate. What the results card
-- shows about it (nil for nobody: bots, someone who left).
function CrateService.RoundCrate(player: Player): { [string]: any }?
	if not giveCrates(player, CrateLogic.CratesPerRound) then
		return nil
	end
	local profile = DataService.Get(player) :: DataService.Profile
	local data = profile.Data :: any
	return {
		Count = CrateLogic.CratesPerRound,
		Name = season.Crate,
		Season = season.Id,
		Total = data.Crates.Count,
		Keys = data.Keys,
	}
end

-- The keys a finished Party Cup gives `player` (CupService shows them on the podium, then pays them
-- with GiveCupKeys): their place (1 to 3 on the podium), whether they played all its rounds, a
-- GOLD PASS owner's extra on the podium, and the day's first cup. 0 for bots.
function CrateService.CupKeysFor(player: Player, place: number?, wholeCup: boolean): number
	local profile = DataService.Get(player)
	if not isPerson(player) or not profile then
		return 0
	end
	local data = profile.Data :: any
	local keys = CrateLogic.CupKeys(place, wholeCup, data.GoldPass.Owned == true, false)
	local day = today()
	if data.CrateFlags.DailyKeyDay < day then
		keys += CrateLogic.DailyCupKeys
		cupDays[player] = day
	else
		cupDays[player] = nil
	end
	return keys
end

function CrateService.GiveCupKeys(player: Player, keys: number, place: number?)
	local profile = DataService.Get(player)
	if not profile or keys <= 0 then
		return
	end
	local data = profile.Data :: any
	-- (the day the keys counted the day's first cup key for, not the day they're paid)
	local day = cupDays[player]
	cupDays[player] = nil
	if day and data.CrateFlags.DailyKeyDay < day then
		data.CrateFlags.DailyKeyDay = day
	end
	CrateService.GiveKeys(player, keys, "PartyCup", if place and place <= 3 then `Place {place}` else "Played")
end

-- QuestService: a weekly quest was finished.
function CrateService.QuestKeys(player: Player, period: string): number
	if period ~= "Weekly" then
		return 0
	end
	return if CrateService.GiveKeys(player, CrateLogic.QuestKeys, "Quest", "Weekly") then CrateLogic.QuestKeys else 0
end

-- ProgressionService: levels from `before` to `after` were reached.
function CrateService.LevelKeys(player: Player, before: number, after: number): number
	local keys = CrateLogic.LevelKeys(before, after)
	if keys > 0 and CrateService.GiveKeys(player, keys, "Road", `Level {after}`) then
		return keys
	end
	return 0
end

-- The altars -------------------------------------------------------------------------------------

local function altarFree(altar: Altar): boolean
	return altar.Busy == nil or os.clock() >= altar.Until or not (altar.Busy :: Player).Parent
end

local function setAltar(altar: Altar, player: Player?, untilTime: number)
	altar.Busy = player
	altar.Until = untilTime
	altar.Model:SetAttribute("PP_AltarBusy", if player then player.UserId else 0)
	if altar.Prompt then
		altar.Prompt.Enabled = player == nil
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- A Roblox friend of `player` standing close by (a person, in the lobby).
local function friendNearby(player: Player, position: Vector3): boolean
	for _, other in Players:GetPlayers() do
		if other ~= player and isPerson(other) and FriendsService.AreFriends(player, other) then
			local root = rootOf(other)
			if root and (root.Position - position).Magnitude <= CrateLogic.FriendRadius then
				return true
			end
		end
	end
	return false
end

-- Opening ----------------------------------------------------------------------------------------

-- Puts a new crate item on, at the reveal: a pet, hat, aura or the title always (the newest is the
-- one to show off), anything else only if that slot has nothing better than its default on.
local function putOn(data: any, itemId: string): boolean
	local item = Seasons.ItemById[itemId]
	if not item then
		return false
	end
	local slot = item.Slot
	local current = data.Equipped[slot]
	local always = slot == "Pet" or slot == "Hat" or slot == "Aura" or slot == "Title"
	local defaults = { Victory_Confetti = true, Elim_Poof = true, Title_Rookie = true }
	if always or current == nil or current == "" or defaults[current] then
		data.Equipped[slot] = itemId
		return true
	end
	return false
end

-- After the reel: the prizes go on, and the server hears about a pet or the title.
local function reveal(player: Player, show: Show)
	local profile = DataService.Get(player)
	local changed = false
	for _, result in show.Results do
		if result.Item and profile then
			changed = putOn(profile.Data, result.Item) or changed
		end
	end
	if changed and player.Parent then
		CosmeticService.Refresh(player)
		DataService.Changed(player)
	end
	refreshMarks(player)
	for _, result in show.Results do
		if result.Tier == "Pet" or result.Tier == "Title" then
			if result.Item then
				local first = CrateBoardService.FoundFirst(player, season.Id, result.Item)
				remote:FireAllClients("Banner", {
					Name = show.Name,
					UserId = show.UserId,
					Item = result.Item,
					Tier = result.Tier,
					Season = season.Id,
					First = first,
				})
				if result.Tier == "Title" then
					CrateBoardService.TellEveryServer(show.Name, show.UserId, result.Item)
				end
			end
		elseif result.Tier == "Coins" and result.Coins >= CrateLogic.Coins[#CrateLogic.Coins].Coins then
			Notifier.All(`💰 {show.Name} unboxed the {result.Coins} coin jackpot!`, "reward", 5)
		end
	end
end

-- Opens `count` crates for `player` (1, or CrateLogic.OpenMany) at altar `altarIndex` (0: over their
-- head). Returns whether it opened, or why not ("NoCrates", "NoKeys", "InRound", "Busy", "AltarBusy",
-- "TooFar", "NoProfile").
function CrateService.Open(player: Player, count: number, altarIndex: number): (boolean, string?)
	local profile = DataService.Get(player)
	if not isPerson(player) or not profile then
		return false, "NoProfile"
	end
	if player:GetAttribute("PP_InRound") == true then
		return false, "InRound"
	end
	if (showing[player] or 0) > os.clock() then
		return false, "Busy"
	end
	local data = profile.Data :: any
	count = if count == CrateLogic.OpenMany then CrateLogic.OpenMany else 1
	if data.Crates.Count < count then
		return false, "NoCrates"
	end
	if data.Keys < count then
		return false, "NoKeys"
	end

	local root = rootOf(player)
	local altar: Altar? = nil
	if altarIndex ~= 0 then
		altar = altars[altarIndex]
		if not altar then
			return false, "AltarBusy"
		end
		if not altarFree(altar :: Altar) then
			return false, "AltarBusy"
		end
		if not root or (root.Position - (altar :: Altar).Position).Magnitude > Config.Crates.AltarRange then
			return false, "TooFar"
		end
	end

	local many = count > 1
	local duration = if many then Config.Crates.ShowTimeMany else Config.Crates.ShowTime
	local revealAt = if many then Config.Crates.RevealAtMany else Config.Crates.RevealAt
	local friend = root ~= nil and friendNearby(player, root.Position)
	local bonus = if friend then 1 else 0

	-- The rolls, saved into the profile before anyone sees anything.
	local progress = progressOf(data, season.Id)
	local week = DailyLogic.WeekNumber(os.time())
	if progress.Week ~= week then
		progress.Week = week
		progress.WeekOpened = 0
	end
	local results = {}
	local coins = 0
	local rare = false
	for _ = 1, count do
		local roll = CrateLogic.Roll(season, data.Owned, progress.Meter, random, bonus)
		data.Keys -= 1
		data.Crates.Count -= 1
		progress.Opened += 1
		progress.WeekOpened += 1
		progress.Meter = roll.Meter
		if roll.Item then
			data.Owned[roll.Item] = true
			progress.Found[roll.Item] = { Crate = progress.Opened, Day = today() }
			if roll.Tier == "Pet" or roll.Tier == "Title" then
				rare = true
				CrateBoardService.Claim(player, season.Id, roll.Item)
			end
			Telemetry.PlayerEvent(player, "CratePull", progress.Opened, roll.Item)
		else
			coins += roll.Coins
		end
		table.insert(results, {
			Tier = roll.Tier :: string,
			Item = roll.Item,
			Coins = roll.Coins,
			Jackpot = roll.Jackpot,
			Guaranteed = roll.Guaranteed,
			Crate = progress.Opened,
		})
		local step = Funnels.CrateStep(lifetimeOpened(data))
		if step then
			funnelStep(player, step)
		end
	end
	if coins > 0 then
		data.Coins += coins
		progress.Coins += coins
		Telemetry.Coins(player, coins, data.Coins, "Crate", season.Id)
	end
	Telemetry.PlayerEvent(player, "CratesOpened", count, if altar then "Altar" else "Overhead")
	Telemetry.Keys(player, -count, data.Keys, "Open", season.Id)
	DataService.Changed(player)
	if rare then
		task.spawn(DataService.SaveNow, player) -- a pet or the title: on the DataStore now
	end
	CrateBoardService.Opened(player, season.Id, progress.Opened, progress.WeekOpened, count)

	shows += 1
	local show: Show = {
		Id = shows,
		UserId = player.UserId,
		Name = player.DisplayName,
		Altar = if altar then altar.Index else 0,
		Season = season.Id,
		At = workspace:GetServerTimeNow(),
		Duration = duration,
		RevealAt = revealAt,
		Results = results,
		Friend = friend,
		Meter = progress.Meter,
	}
	showing[player] = os.clock() + duration
	if altar then
		local free = os.clock() + duration + 0.4
		setAltar(altar, player, free)
		task.delay(duration + 0.4, function()
			-- (unless they've started another show here since: that one frees it)
			if altar.Busy == player and altar.Until == free then
				setAltar(altar, nil, 0)
			end
		end)
	end
	remote:FireAllClients("Show", show)
	task.delay(revealAt, reveal, player, show)
	return true, nil
end

-- What a player sees when an open didn't happen.
local DENIED = {
	NoCrates = "No crates left! Play a round to earn one.",
	InRound = "Crates open in the lobby, after the round.",
	Busy = "Your crate is still opening!",
	AltarBusy = "That altar's busy. Try another, or OPEN HERE.",
	TooFar = "Walk up to the altar to open it.",
}

local function tryOpen(player: Player, count: number, altarIndex: number)
	local ok, why = CrateService.Open(player, count, altarIndex)
	if not ok and why then
		remote:FireClient(player, "Denied", why)
		local text = DENIED[why]
		if text then
			Notifier.Send(player, text, "info", 3)
		end
	end
end

-- The season's welcome was seen (the client's intro): its crate, once per season.
local function welcome(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local flags = (profile.Data :: any).CrateFlags
	if flags.Welcome == season.Id then
		return
	end
	flags.Welcome = season.Id
	if giveCrates(player, 1) then
		remote:FireClient(player, "Gift", { Crates = 1, Reason = "Welcome" })
	end
	Telemetry.PlayerEvent(player, "SeasonWelcome", 1, season.Id)
end

-- A profile loaded: last season's crates become this season's, the starter keys (once), the marks.
local function onLoaded(player: Player)
	local profile = DataService.Get(player)
	if not profile or not isPerson(player) then
		return
	end
	local data = profile.Data :: any
	local crates = data.Crates
	if crates.Season ~= season.Id then
		if crates.Season ~= "" and crates.Count > 0 then
			local from = Seasons.Get(crates.Season)
			task.delay(8, function()
				if player.Parent then
					Notifier.Send(
						player,
						`Your {crates.Count} {if from then from.Crate else "crate"}s are {season.Crate}s now!`,
						"reward",
						7
					)
				end
			end)
		end
		crates.Season = season.Id
	end
	if not data.CrateFlags.StarterKeys then
		data.CrateFlags.StarterKeys = true
		data.Keys += CrateLogic.StarterKeys
		Telemetry.Keys(player, CrateLogic.StarterKeys, data.Keys, "Starter", season.Id)
	end
	refreshMarks(player)
	DataService.Changed(player)
end

CrateService.ProfileReady = onLoaded -- (the check tools' stand-ins have no ProfileLoaded of their own)

-- The altars the lobby built (World/SeasonWorld), with their prompts.
local function hookAltars()
	for index, built in SeasonWorld.Altars() do
		local altar: Altar = {
			Index = index,
			Model = built.Model,
			Prompt = built.Prompt,
			Position = built.Position,
			Busy = nil,
			Until = 0,
		}
		altars[index] = altar
		setAltar(altar, nil, 0)
		if built.Prompt then
			built.Prompt.Triggered:Connect(function(player)
				if limiter:Check(player) then
					tryOpen(player, 1, index)
				end
			end)
		end
	end
end

-- Test runs only (workspace PP_Harness): keys and crates for a stand-in, and the next rolls' numbers.
function CrateService.TestGive(player: Player, keys: number, crates: number)
	if not harness() then
		warn("[CrateService] TestGive is only for the check tools (workspace PP_Harness)")
		return
	end
	local profile = DataService.Get(player)
	if profile then
		(profile.Data :: any).Keys += keys
		giveCrates(player, crates)
		DataService.Changed(player)
	end
end

function CrateService.TestRolls(numbers: { number }?)
	if not harness() then
		return
	end
	if numbers then
		local index = 0
		random = function()
			index += 1
			return numbers[(index - 1) % #numbers + 1]
		end
	else
		random = function()
			return rng:NextNumber()
		end
	end
end

function CrateService.Init()
	DataService.ProfileLoaded:Connect(onLoaded)
	remote.OnServerEvent:Connect(function(player, action, a, b)
		if not limiter:Check(player) then
			return
		end
		if action == "Open" then
			local count = if a == CrateLogic.OpenMany then CrateLogic.OpenMany else 1
			local altarIndex = if type(b) == "number" and b == b and altars[b] then b else 0
			tryOpen(player, count, altarIndex)
		elseif action == "Welcome" then
			welcome(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		showing[player] = nil
		cupDays[player] = nil
		for _, altar in altars do
			if altar.Busy == player then
				setAltar(altar, nil, 0)
			end
		end
	end)
end

function CrateService.Start()
	hookAltars()
	-- An altar whose opener's show ended (or who left) frees up even if a delay was missed.
	while true do
		task.wait(1)
		for _, altar in altars do
			if altar.Busy and altarFree(altar) then
				setAltar(altar, nil, 0)
			end
		end
	end
end

return CrateService
