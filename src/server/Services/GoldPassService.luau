-- The GOLD PASS (owner: "Also we do need a paid battle pass too. I like the current free one. But
-- the paid one should also be insane."): one permanent Roblox game pass (Config.Monetization
-- .GoldPassId) that opens the Rewards Road's gold lane (Shared/GoldPass, Logic/GoldLane). It took
-- over from the old VIP pass, which was never on sale; the two VIP items are gold rewards now.
--
--   * Who owns it: Roblox is asked on every join (UserOwnsGamePassAsync, in a pcall, once more a
--     moment later if that fails); a purchase in the game counts as soon as Roblox says it went
--     through (PromptGamePassPurchaseFinished); and the experience's creator always owns it, so the
--     owner sees everything. It's kept in the profile (GoldPass.Owned): a failed check never takes
--     it away, and nothing but Roblox's word or the creator rule sets it.
--   * Getting it gives every gold reward already reached, at once (Grant): the gold coins of every
--     level reached (each level once: GoldPass.CoinsTo), the gold cosmetics (CosmeticService
--     .CheckUnlocks), the GOLD badge and gold shimmer on the name tag (CosmeticService.Refresh), and
--     the "UNLOCKED N REWARDS!" card on the player's screen (the GoldPass remote's "Unlocked").
--   * After that each level gives its gold reward when it's reached (Economy.AddXP calls LevelUp;
--     the level-up card shows it), and every round pays 10% more XP, on a line of its own on the
--     results card (a Boost). Nothing in a mini-game changes.
--   * Buying: GET GOLD PASS sends "Prompt" and the server shows Roblox's purchase prompt. Whether the
--     pass is for sale is Roblox's (GetProductInfo, asked when the server starts and every 10
--     minutes, kept in between): while it's off sale (or its id is 0) nothing is prompted and the
--     lane is a preview, COMING SOON. If Roblox can't be asked, the prompt goes ahead (Roblox's
--     prompt says if it can't be bought).
--   * A returning owner whose last game was on a server still running older code (it pays no gold
--     coins) gets the gold coins of the levels reached there when they join.
--   * Tests: TestGrant gives a stand-in the pass under the check tools' flag (workspace PP_Harness)
--     and nowhere else; no remote reaches it. SetRobloxForTests stands in for Roblox (who owns it,
--     the purchase prompt, the product info) in the check tools' runs, which can't buy anything.

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Cosmetics = require(Shared.Cosmetics)
local GoldLane = require(Shared.Logic.GoldLane)
local LevelCurve = require(Shared.Logic.LevelCurve)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)

local Boosts = require(script.Parent.Boosts)
local CosmeticService = require(script.Parent.CosmeticService)
local DataService = require(script.Parent.DataService)
local FunnelService = require(script.Parent.FunnelService)
local Notifier = require(script.Parent.Notifier)
local RateLimiter = require(script.Parent.RateLimiter)
local Telemetry = require(script.Parent.Telemetry)

local GoldPassService = {}

local RETRY_AFTER = 3 -- seconds before asking Roblox a second time
local OFFER_EVERY, OFFER_RETRY = 600, 30 -- seconds between asking Roblox about the pass's sale
local remote = Remotes.Get("GoldPass")
local offer: GoldLane.Offer? = nil -- Roblox's last answer about the pass's sale (nil: not yet)

-- What the "UNLOCKED N REWARDS!" card shows (the client's GoldPassController).
export type Unlocked = {
	Level: number, -- the level they're at
	Count: number, -- gold rewards unlocked: coin levels and cosmetics
	Coins: number,
	Items: { string }, -- the cosmetics, best (highest level) first
	Source: string, -- "Purchase" | "Owned" (bought elsewhere) | "Creator" | "Test"
}

-- Roblox's side of the pass: who owns it, its purchase prompt and its product info (price, for sale).
export type Roblox = {
	Owns: (userId: number, passId: number) -> boolean,
	Prompt: (player: Player, passId: number) -> (),
	Info: (passId: number) -> any,
}
local ROBLOX: Roblox = {
	Owns = function(userId, passId)
		return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
	end,
	Prompt = function(player, passId)
		MarketplaceService:PromptGamePassPurchase(player, passId)
	end,
	Info = function(passId)
		return MarketplaceService:GetProductInfo(passId, Enum.InfoType.GamePass)
	end,
}
local roblox = ROBLOX

-- The check tools' stand-in for Roblox (nil: the real one again).
function GoldPassService.SetRobloxForTests(standIn: Roblox?)
	roblox = standIn or ROBLOX
end

local function passOf(profile: DataService.Profile): { [string]: any }
	return (profile.Data :: any).GoldPass
end

function GoldPassService.Owns(player: Player): boolean
	local profile = DataService.Get(player)
	return profile ~= nil and passOf(profile).Owned == true
end

-- The experience's creator (a user-owned experience) always owns it.
function GoldPassService.IsCreator(player: Player): boolean
	return GoldLane.IsCreator(game.CreatorType.Name, game.CreatorId, player.UserId)
end

-- Pays an owner the gold coins of the levels after the last one paid, up to `level` (each once).
local function payCoins(profile: DataService.Profile, level: number): (number, number)
	local pass = passOf(profile)
	local coins, levels = GoldLane.CoinsBetween(Progression.GoldLane, pass.CoinsTo, level)
	pass.CoinsTo = math.max(pass.CoinsTo, math.floor(level))
	if coins > 0 then
		profile.Data.Coins += coins
	end
	return coins, levels
end

-- The best first: the highest gold level, then catalog order.
local function bestFirst(items: { Cosmetics.Cosmetic }): { string }
	local list = table.clone(items)
	local index = {}
	for position, item in Cosmetics.List do
		index[item.Id] = position
	end
	table.sort(list, function(a, b)
		local la, lb = a.GoldLevel or a.UnlockLevel or 0, b.GoldLevel or b.UnlockLevel or 0
		return if la ~= lb then la > lb else (index[a.Id] or 0) < (index[b.Id] or 0)
	end)
	local ids = {}
	for _, item in list do
		table.insert(ids, item.Id)
	end
	return ids
end

-- An owner's gold rewards that are due and not given yet (levels reached on a server still running
-- older code): their coins, quietly, with a toast. Their cosmetics come with the join's NEW REWARDS!
-- card (CosmeticService), or here.
local function catchUp(player: Player, profile: DataService.Profile)
	local level = LevelCurve.FromTotalXP(profile.Data.XP)
	local coins = payCoins(profile, level)
	local items = CosmeticService.CheckUnlocks(player, true)
	if coins > 0 or #items > 0 then
		local parts = {}
		if coins > 0 then
			table.insert(parts, `+{coins} coins`)
		end
		for _, item in items do
			table.insert(parts, `{item.Icon} {item.Name}`)
		end
		Notifier.Send(player, `👑 GOLD PASS: {table.concat(parts, ", ")} from the levels you reached!`, "reward", 7)
		DataService.Changed(player)
	end
end

-- Gives `player` the pass and every gold reward they've reached, and shows them what it unlocked.
-- True when they didn't have it before (an owner just has anything due caught up).
function GoldPassService.Grant(player: Player, source: string): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end
	local pass = passOf(profile)
	if pass.Owned then
		catchUp(player, profile)
		return false
	end
	pass.Owned = true
	pass.Since = os.time()
	local level = LevelCurve.FromTotalXP(profile.Data.XP)
	local coins, coinLevels = payCoins(profile, level)
	local unlocked = CosmeticService.CheckUnlocks(player, true)
	CosmeticService.Refresh(player) -- the name tag: the GOLD badge and the shimmer
	local payload: Unlocked = {
		Level = level,
		Count = coinLevels + #unlocked,
		Coins = coins,
		Items = bestFirst(unlocked),
		Source = source,
	}
	remote:FireClient(player, "Unlocked", payload)
	Telemetry.PlayerEvent(player, "GoldPassGranted", level, source)
	DataService.Changed(player)
	return true
end

-- Economy.AddXP: an owner just reached `after`, so the gold coins of the levels passed are paid (its
-- cosmetics are unlocked with the level's own, by ProgressionService). Returns the coins.
function GoldPassService.LevelUp(player: Player, after: number): number
	local profile = DataService.Get(player)
	if not profile or passOf(profile).Owned ~= true then
		return 0
	end
	return (payCoins(profile, after))
end

-- The check tools' grant (tools/checks/scenarios/GoldPass_grant.luau): only under their flag, so a
-- live server never gives the pass this way. No remote calls it.
function GoldPassService.TestGrant(player: Player): boolean
	if workspace:GetAttribute("PP_Harness") ~= true then
		warn("[GoldPassService] TestGrant is only for the check tools (workspace PP_Harness)")
		return false
	end
	return GoldPassService.Grant(player, "Test")
end

-- Whether Roblox says `player` owns the pass: asked once, and once more a moment later if asking
-- failed. Nil when it couldn't be asked either time.
local function ownsOnRoblox(player: Player, passId: number): boolean?
	for attempt = 1, 2 do
		local ok, owns = pcall(roblox.Owns, player.UserId, passId)
		if ok then
			return owns == true
		end
		Telemetry.Error("GoldPass", `{player.UserId} ownership check {attempt}: {owns}`)
		if attempt == 1 then
			task.wait(RETRY_AFTER)
			if not player.Parent then
				return nil
			end
		end
	end
	return nil
end

-- On joining: the creator gets it, an owner has anything due caught up, and anyone else who owns the
-- pass on Roblox (bought it on the website, or on another server whose save didn't land) gets it.
function GoldPassService.CheckOwnership(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	if passOf(profile).Owned then
		catchUp(player, profile)
		return
	elseif GoldPassService.IsCreator(player) then
		GoldPassService.Grant(player, "Creator")
		return
	end
	local passId = Config.Monetization.GoldPassId
	if passId == 0 then
		return -- not on sale yet
	end
	if ownsOnRoblox(player, passId) and player.Parent and DataService.Get(player) == profile then
		GoldPassService.Grant(player, "Owned")
	end
end

-- Roblox's purchase prompt finished: bought means granted, right away.
function GoldPassService.PurchaseFinished(player: Player, passId: number, purchased: boolean)
	local id = Config.Monetization.GoldPassId
	if not purchased or id == 0 or passId ~= id then
		return
	end
	Telemetry.PlayerEvent(player, "GoldPassBought", 1)
	FunnelService.GoldBought(player)
	if DataService.WaitFor(player, 30) then
		GoldPassService.Grant(player, "Purchase")
	end
end

-- Asks Roblox whether the pass is for sale (and its price). Returns what it learned.
function GoldPassService.AskOffer(): GoldLane.Offer
	local id = Config.Monetization.GoldPassId
	local ok, info = true, nil
	if id ~= 0 then
		ok, info = pcall(roblox.Info, id)
	end
	local answer = GoldLane.Offer(id, ok, info, Config.Monetization.GoldPassPrice)
	offer = answer
	return answer
end

local function prompt(player: Player)
	local passId = Config.Monetization.GoldPassId
	local known = offer
	if GoldPassService.Owns(player) then
		Notifier.Send(player, "👑 You have the GOLD PASS!", "success")
	elseif passId == 0 or (known and known.Known and not known.OnSale) then
		Notifier.Send(player, "👑 The GOLD PASS is coming soon!", "info")
	else
		FunnelService.GoldPrompted(player) -- the GOLD PASS funnel's middle step
		roblox.Prompt(player, passId)
	end
end

function GoldPassService.Init()
	DataService.ProfileLoaded:Connect(function(player: Player)
		task.spawn(GoldPassService.CheckOwnership, player)
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		GoldPassService.PurchaseFinished(player, passId, purchased)
	end)
	local limiter = RateLimiter.new(3, 10) -- (it forgets players who leave)
	remote.OnServerEvent:Connect(function(player, action)
		if action == "Prompt" and limiter:Check(player) then
			prompt(player)
		end
	end)
	-- 10% more XP from every round for owners, on its own line of the results card.
	Boosts.Register("GoldPass", function(player: Player, round: Boosts.Round): (number, string?, number?)
		if not GoldPassService.Owns(player) then
			return 0, nil, nil
		end
		return 0, "👑 GOLD PASS +10% XP", GoldLane.XPBonus(round.XP, Config.GoldRoad)
	end)
end

function GoldPassService.Start()
	while true do
		task.wait(if GoldPassService.AskOffer().Known then OFFER_EVERY else OFFER_RETRY)
	end
end

return GoldPassService
