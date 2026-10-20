-- Coin shop purchases and equipping (design doc §10 "Shop layout").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Cosmetics = require(Shared.Cosmetics)
local Remotes = require(Shared.Remotes)

local CosmeticService = require(script.Parent.CosmeticService)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.Economy)
local Notifier = require(script.Parent.Notifier)
local RateLimiter = require(script.Parent.RateLimiter)
local Telemetry = require(script.Parent.Telemetry)

local ShopService = {}

local function purchase(player: Player, itemId: any)
	if type(itemId) ~= "string" then
		return
	end
	local item = Cosmetics.Get(itemId)
	local profile = DataService.Get(player)
	if not item or not profile then
		return
	end
	if profile.Data.Owned[itemId] then
		Notifier.Send(player, `You already own {item.Name}.`)
		return
	end
	local price = item.Price
	if price == nil then
		Notifier.Send(player, `{item.Name} can't be bought with coins. {item.Description}`, "warning")
		return
	end
	if not Economy.SpendCoins(player, price, "Shop") then
		Notifier.Send(player, `You need {price - profile.Data.Coins} more coins for {item.Name}.`, "warning")
		return
	end
	profile.Data.Owned[itemId] = true
	if Cosmetics.IsEquipSlot(item.Slot) then
		profile.Data.Equipped[item.Slot] = itemId
		CosmeticService.Refresh(player)
	end
	Notifier.Send(player, `Purchased {item.Icon} {item.Name}!`, "success")
	Notifier.Sound({ player }, "Purchase")
	Telemetry.PlayerEvent(player, "ShopPurchase", price, itemId)
	DataService.Changed(player)
end

local function equip(player: Player, slot: any, itemId: any)
	if type(slot) ~= "string" or not Cosmetics.IsEquipSlot(slot) then
		return
	end
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	if itemId == nil or itemId == "" then
		profile.Data.Equipped[slot] = ""
	else
		if type(itemId) ~= "string" then
			return
		end
		local item = Cosmetics.Get(itemId)
		if not item or item.Slot ~= slot or not profile.Data.Owned[itemId] then
			return
		end
		profile.Data.Equipped[slot] = itemId
		Telemetry.PlayerEvent(player, "CosmeticEquipped", 1, itemId)
	end
	CosmeticService.Refresh(player)
	DataService.Changed(player)
end

function ShopService.Init()
	local limit = Config.RateLimits.Shop
	local purchaseLimiter = RateLimiter.new(limit[1], limit[2])
	local equipLimiter = RateLimiter.new(limit[1] * 2, limit[2])

	Remotes.Get("ShopPurchase").OnServerEvent:Connect(function(player, itemId)
		if purchaseLimiter:Check(player) then
			purchase(player, itemId)
		end
	end)
	Remotes.Get("ShopEquip").OnServerEvent:Connect(function(player, slot, itemId)
		if equipLimiter:Check(player) then
			equip(player, slot, itemId)
		end
	end)
end

return ShopService
