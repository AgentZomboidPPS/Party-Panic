-- Lantern Keys for Robux (the crate seasons' design: "we also need to be able to sell keys for Robux";
-- owner: "Also do all of your ideas."). Developer products (Config.Monetization.KeyPacks): 1, 5, 15
-- and 40 keys, each also as a gift for someone else in the server, and the once-per-player starter
-- pack (5 keys and the season's Harvest Banner trail, sold only there). Crates stay free; keys are
-- the scarce half. Bought keys never expire and open crates in every season.
--
-- Roblox's rules for paid random items (the design page's notes, from Roblox's guidelines):
--   * Odds before buying: the key shop's VIEW ODDS (Controllers/CrateController) shows every outcome
--     with this player's real odds, adding up to 100% (Logic/CrateLogic.PersonalOdds).
--   * Players who can't buy them: Roblox's PolicyService says per player whether paid random items
--     are restricted for them (ArePaidRandomItemsRestricted; country and age). For them the key shop
--     is hidden and says it isn't available where they are (PP_KeysLocked), and no prompt is ever
--     shown. A check that fails twice counts as restricted. Keys they earn by playing still open
--     crates. There's no trading in the game, and crate items never become tradeable.
--   * Safe purchases: keys are granted in ProcessReceipt, saved to the DataStore before Roblox is
--     told the purchase went through (DataService.SaveNow; a save that fails takes back just that
--     purchase, never other purchases or keys spent meanwhile, and Roblox asks again later), and a
--     receipt already granted (its PurchaseId in the profile's Receipts) is never granted twice. A
--     buyer who leaves while their save waits isn't told it went through: their leave save either
--     carries it (with the PurchaseId, so Roblox's retry on their next visit grants nothing more)
--     or doesn't (and the retry grants it).
-- Prices and whether each product is on sale are Roblox's (GetProductInfo, asked at start and every
-- 10 minutes): GameState KeyShop has what the screens show; a pack whose id is 0 isn't shown.
--
-- Gifts: GIFT on a pack names a person in the server who may have paid random items; the buyer pays,
-- the friend gets the keys and a banner saying who sent them. The friend's keys are saved first,
-- straight after they're added (a friend who leaves meanwhile takes them in their leave save), and
-- once they're on the friend's record the purchase is delivered. If the friend has left by the time
-- the receipt arrives (or it arrives on another server), the keys go to the buyer instead, and
-- they're told.
--
-- The starter pack can't be prompted again while one is on its way (between the prompt and its
-- receipt), so it's bought once. A second receipt (bought on another server meanwhile) still grants
-- its keys: it was paid for.
--
-- Tests: SetRobloxForTests stands in for Roblox (the purchase prompt, product info, policy) in the
-- check tools' runs, which can't buy anything; Harness.Receipt hands ProcessReceipt a made-up receipt.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local GameState = require(Shared.GameState)
local ProfileMigration = require(Shared.Logic.ProfileMigration)
local Remotes = require(Shared.Remotes)
local Seasons = require(Shared.Seasons)

local BotRegistry = require(script.Parent.BotRegistry)
local CosmeticService = require(script.Parent.CosmeticService)
local CrateService = require(script.Parent.CrateService)
local DataService = require(script.Parent.DataService)
local Notifier = require(script.Parent.Notifier)
local RateLimiter = require(script.Parent.RateLimiter)
local Telemetry = require(script.Parent.Telemetry)

local KeyShopService = {}

local INFO_EVERY, INFO_RETRY = 600, 30
local POLICY_RETRY = 3
local GIFT_KEPT = 300 -- seconds a gift's friend is remembered while the buyer pays

local remote = Remotes.Get("Crate")
local season = Seasons.CurrentSeason()

-- What a product gives.
type Product = { Key: string, Keys: number, Gift: boolean, Starter: boolean }

local STARTER_PENDING = 120 -- seconds a starter pack prompt blocks another (until its receipt)

local products: { [number]: Product } = {} -- product id -> what it gives
local gifts: { [Player]: { UserId: number, Key: string, At: number } } = {}
local starterPrompted: { [Player]: number } = {} -- when each player was last shown the starter pack
local known = false

export type Roblox = {
	Prompt: (player: Player, productId: number) -> (),
	Info: (productId: number) -> any,
	Restricted: (player: Player) -> boolean,
}
local ROBLOX: Roblox = {
	Prompt = function(player, productId)
		MarketplaceService:PromptProductPurchase(player, productId)
	end,
	Info = function(productId)
		return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
	end,
	Restricted = function(player)
		local info = PolicyService:GetPolicyInfoForPlayerAsync(player)
		return info.ArePaidRandomItemsRestricted == true
	end,
}
local roblox = ROBLOX

function KeyShopService.SetRobloxForTests(standIn: Roblox?)
	roblox = standIn or ROBLOX
end

-- A person who's still here (bots look like players but are flagged; the check tools' stand-ins are
-- tables like bots, with a UserId above 0).
local function isPerson(player: any): boolean
	return player ~= nil
		and player.Parent ~= nil
		and not BotRegistry.IsBot(player)
		and type(player.UserId) == "number"
		and player.UserId > 0
end

-- Every product the game sells, by id.
local function index()
	table.clear(products)
	for _, pack in Config.Monetization.KeyPacks do
		if pack.Id ~= 0 then
			products[pack.Id] = { Key = pack.Key, Keys = pack.Keys, Gift = false, Starter = false }
		end
		if pack.GiftId ~= 0 then
			products[pack.GiftId] = { Key = pack.Key, Keys = pack.Keys, Gift = true, Starter = false }
		end
	end
	local starter = Config.Monetization.StarterPack
	if starter.Id ~= 0 then
		products[starter.Id] = { Key = starter.Key, Keys = starter.Keys, Gift = false, Starter = true }
	end
end

-- Asks Roblox for every product's price and sale, and puts what's on sale on the screens.
function KeyShopService.AskInfo(): boolean
	local packs = {}
	local all = true
	local function ask(id: number, fallback: number): (number, boolean)
		if id == 0 then
			return fallback, false
		end
		local ok, info = pcall(roblox.Info, id)
		if not ok or type(info) ~= "table" then
			all = false
			return fallback, true -- (Roblox's prompt says if it can't be bought)
		end
		local price = tonumber(info.PriceInRobux) or fallback
		return price, info.IsForSale ~= false
	end
	for _, pack in Config.Monetization.KeyPacks do
		local price, onSale = ask(pack.Id, pack.Price)
		local _, giftOnSale = ask(pack.GiftId, pack.Price)
		if onSale then
			table.insert(packs, {
				Key = pack.Key,
				Keys = pack.Keys,
				Price = price,
				Gift = giftOnSale,
				Badge = pack.Badge,
			})
		end
	end
	local starter = Config.Monetization.StarterPack
	local starterPrice, starterOnSale = ask(starter.Id, starter.Price)
	GameState.SetJSON("KeyShop", {
		Packs = packs,
		Starter = if starterOnSale
			then { Key = starter.Key, Keys = starter.Keys, Price = starterPrice, Item = season.Starter }
			else nil,
	})
	known = all
	return all
end

-- Whether paid random items are restricted for `player` (PP_KeysLocked; asked once per visit).
local function checkPolicy(player: Player)
	for attempt = 1, 2 do
		local ok, restricted = pcall(roblox.Restricted, player)
		if ok then
			player:SetAttribute("PP_KeysLocked", restricted == true)
			return
		end
		Telemetry.Error("KeyShop", `{player.UserId} policy check {attempt}: {restricted}`)
		task.wait(POLICY_RETRY)
		if not player.Parent then
			return
		end
	end
	player:SetAttribute("PP_KeysLocked", true) -- couldn't be asked: nothing is sold
end

local function packOf(key: string): ({ [string]: any }?, boolean)
	for _, pack in Config.Monetization.KeyPacks do
		if pack.Key == key then
			return pack, false
		end
	end
	if key == Config.Monetization.StarterPack.Key then
		return Config.Monetization.StarterPack, true
	end
	return nil, false
end

-- BUY (or GIFT, with `giftTo` a UserId in the server) on a pack.
local function prompt(player: Player, key: any, giftTo: any)
	if type(key) ~= "string" then
		return
	end
	if player:GetAttribute("PP_KeysLocked") ~= false then
		Notifier.Send(player, "Keys aren't for sale where you are. Keys you earn still open crates!", "info", 5)
		return
	end
	local pack, starter = packOf(key)
	if not pack then
		return
	end
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local id = pack.Id
	if starter then
		if (profile.Data :: any).CrateFlags.StarterPack then
			Notifier.Send(player, "You have the starter pack already!", "info", 4)
			return
		end
		local prompted = starterPrompted[player]
		if prompted and os.clock() - prompted < STARTER_PENDING then
			Notifier.Send(player, "Your starter pack is on its way!", "info", 4)
			return
		end
		starterPrompted[player] = os.clock()
	elseif type(giftTo) == "number" then
		local friend = Players:GetPlayerByUserId(giftTo)
		if not friend or friend == player or not isPerson(friend) or not DataService.Get(friend) then
			Notifier.Send(player, "They aren't in this server any more.", "warning", 4)
			return
		end
		if friend:GetAttribute("PP_KeysLocked") ~= false then
			Notifier.Send(player, `Keys can't be gifted to {friend.DisplayName} where they are.`, "info", 5)
			return
		end
		id = pack.GiftId
		gifts[player] = { UserId = giftTo, Key = key, At = os.clock() }
	end
	if id == 0 then
		Notifier.Send(player, "That pack is coming soon!", "info", 4)
		return
	end
	Telemetry.PlayerEvent(player, "KeysPrompted", pack.Keys, key)
	roblox.Prompt(player, id)
end

-- Notes a granted receipt on a profile (its newest MaxReceipts are kept): the ids it pushed out.
local function noteReceipt(data: any, purchaseId: string): { string }
	table.insert(data.Receipts, purchaseId)
	local dropped: { string } = {}
	while #data.Receipts > ProfileMigration.MaxReceipts do
		table.insert(dropped, tostring(table.remove(data.Receipts, 1)))
	end
	return dropped
end

-- Takes back just one receipt's grant (other purchases and keys spent meanwhile stay): its keys,
-- its id, and the old ids its note pushed out.
local function takeBack(data: any, purchaseId: string, keys: number, dropped: { string })
	data.Keys = math.max(0, data.Keys - keys)
	local at = table.find(data.Receipts, purchaseId)
	if at then
		table.remove(data.Receipts, at)
	end
	for index = #dropped, 1, -1 do
		table.insert(data.Receipts, 1, dropped[index])
	end
end

-- Saves a profile now (a check run can make a save fail, find the player gone, or do something
-- while it waits).
local function save(player: Player): DataService.SaveResult
	local forced = KeyShopService.Harness.Saves[player.UserId]
	if forced and workspace:GetAttribute("PP_Harness") == true then
		return if type(forced) == "function" then forced() else forced
	end
	return DataService.SaveNow(player)
end

-- The friend a gift receipt goes to: the one picked, still here (and not just leaving), who may
-- have paid random items. Nil: the keys go to the buyer.
local function giftFriend(buyer: Player, product: Product): Player?
	local pending = gifts[buyer]
	if not pending or pending.Key ~= product.Key or os.clock() - pending.At >= GIFT_KEPT then
		return nil
	end
	local other = Players:GetPlayerByUserId(pending.UserId)
	local otherProfile = other and DataService.Get(other)
	if
		not other
		or not isPerson(other)
		or not otherProfile
		or otherProfile.Released
		or other:GetAttribute("PP_KeysLocked") ~= false
	then
		return nil
	end
	return other
end

local function announce(buyer: Player, receiver: Player, product: Product, wasGift: boolean)
	local receiverData = (DataService.Get(receiver) :: DataService.Profile).Data :: any
	local friend = if receiver ~= buyer then receiver else nil
	local reason = if product.Starter then "Starter pack" elseif friend then "Gift" else "Bought"
	Telemetry.PlayerEvent(buyer, "KeysBought", product.Keys, product.Key)
	Telemetry.Keys(receiver, product.Keys, receiverData.Keys, reason, product.Key)
	if friend then
		remote:FireClient(friend, "Gift", { Keys = product.Keys, Reason = "Gift", From = buyer.DisplayName })
		Notifier.Send(buyer, `🎁 You sent {friend.DisplayName} {product.Keys} {season.Key}s!`, "success", 6)
		Notifier.All(`🎁 {buyer.DisplayName} gifted {friend.DisplayName} {product.Keys} keys!`, "reward", 5)
	else
		remote:FireClient(buyer, "Gift", {
			Keys = product.Keys,
			Reason = reason,
			Item = if product.Starter then season.Starter else nil,
		})
		if wasGift then
			Notifier.Send(buyer, "Your friend had left, so the keys are yours!", "info", 6)
		end
	end
	if product.Starter then
		CosmeticService.Refresh(buyer)
	end
	Notifier.Sound({ receiver }, "Purchase")
	DataService.Changed(buyer)
	if receiver ~= buyer then
		DataService.Changed(receiver)
	end
end

-- Roblox's receipt for a purchase: grant it once, saved, then say it went through.
function KeyShopService.ProcessReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local product = products[receipt.ProductId]
	if not product then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- (not ours, or an id not set yet)
	end
	local buyer = Players:GetPlayerByUserId(receipt.PlayerId)
	if not buyer then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- granted on their next visit
	end
	local profile = DataService.Get(buyer) or DataService.WaitFor(buyer, 10)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	local data = profile.Data :: any
	if table.find(data.Receipts, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- already granted (a repeat from Roblox)
	end
	local firstBuy = data.CrateFlags.Bought == 0

	-- A gift: the friend's keys and the receipt go on their record and are saved at once (nothing
	-- waits in between, so a friend who leaves meanwhile takes them in their leave save). Once
	-- they're there the purchase is delivered; the buyer's note of it is saved after.
	local friend = if product.Gift then giftFriend(buyer, product) else nil
	if friend then
		local friendData = (DataService.Get(friend) :: DataService.Profile).Data :: any
		friendData.Keys += product.Keys
		local dropped = noteReceipt(friendData, purchaseId)
		if save(friend) == "Failed" then
			takeBack(friendData, purchaseId, product.Keys, dropped)
			Telemetry.Error("KeyShop", `{receipt.PlayerId} {purchaseId}: gift save failed, not granted yet`)
			return Enum.ProductPurchaseDecision.NotProcessedYet -- (the friend is still remembered)
		end
		gifts[buyer] = nil
		noteReceipt(data, purchaseId)
		data.CrateFlags.Bought += 1
		task.spawn(save, buyer)
		if firstBuy then
			CrateService.FunnelStep(buyer, 5)
		end
		announce(buyer, friend, product, true)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if product.Gift then
		gifts[buyer] = nil
	end

	-- The buyer's own keys (or a gift whose friend has gone): saved before Roblox hears it went
	-- through. Not saved by this call: just this purchase is taken back, and Roblox asks again.
	data.Keys += product.Keys
	local dropped = noteReceipt(data, purchaseId)
	data.CrateFlags.Bought += 1
	local setStarter = product.Starter and not data.CrateFlags.StarterPack
	local ownedBefore = data.Owned[season.Starter]
	if product.Starter then
		data.CrateFlags.StarterPack = true
		data.Owned[season.Starter] = true
	end
	local result = save(buyer)
	if result ~= "Saved" then
		takeBack(data, purchaseId, product.Keys, dropped)
		data.CrateFlags.Bought = math.max(0, data.CrateFlags.Bought - 1)
		if setStarter then
			data.CrateFlags.StarterPack = false
			data.Owned[season.Starter] = ownedBefore
		end
		Telemetry.Error("KeyShop", `{receipt.PlayerId} {purchaseId}: {result}, not granted yet`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if firstBuy then
		CrateService.FunnelStep(buyer, 5)
	end
	announce(buyer, buyer, product, product.Gift)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Test runs only (workspace PP_Harness): hands ProcessReceipt a made-up receipt; Saves[UserId] makes
-- that player's purchase saves fail or find them gone ("Failed" / "Left"), or is a function run as
-- the save (what happens while it waits) that says how it went.
KeyShopService.Harness = {
	Receipt = function(userId: number, productId: number, purchaseId: string): Enum.ProductPurchaseDecision?
		if workspace:GetAttribute("PP_Harness") ~= true then
			return nil
		end
		return KeyShopService.ProcessReceipt({ PlayerId = userId, ProductId = productId, PurchaseId = purchaseId })
	end,
	Index = index,
	Saves = {} :: { [number]: DataService.SaveResult | () -> DataService.SaveResult },
}

function KeyShopService.Init()
	index()
	MarketplaceService.ProcessReceipt = function(receipt)
		local ok, decision = pcall(KeyShopService.ProcessReceipt, receipt)
		if not ok then
			Telemetry.Error("KeyShop", `receipt {receipt.PurchaseId}: {decision}`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return decision
	end
	local limiter = RateLimiter.new(4, 10)
	remote.OnServerEvent:Connect(function(player, action, key, giftTo)
		if action == "Buy" and limiter:Check(player) then
			prompt(player, key, giftTo)
		end
	end)
	local function joined(player: Player)
		if isPerson(player) then
			task.spawn(checkPolicy, player)
		end
	end
	Players.PlayerAdded:Connect(joined)
	for _, player in Players:GetPlayers() do
		joined(player)
	end
	-- (a starter pack prompt closed without buying lets them ask again)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		if not purchased and productId == Config.Monetization.StarterPack.Id then
			local player = Players:GetPlayerByUserId(userId)
			if player then
				starterPrompted[player] = nil
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		gifts[player] = nil
		starterPrompted[player] = nil
	end)
end

function KeyShopService.Start()
	while true do
		task.wait(if KeyShopService.AskInfo() and known then INFO_EVERY else INFO_RETRY)
	end
end

return KeyShopService
