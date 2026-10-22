--!strict
-- The GOLD PASS's lane on the Rewards Road (owner: "Also we do need a paid battle pass too. I like
-- the current free one. But the paid one should also be insane."): every level from 2 to 100 has a
-- gold reward. A level with gold cosmetics (Shared/GoldPass: an item's GoldLevel) gives those; every
-- other level pays gold coins, more the higher it is (Config.GoldRoad: Base, plus PerTen for every
-- ten levels: 6 at level 3, 15 at level 99), since a level takes hours early on and days later.
--
-- Buying the pass gives every gold reward already reached at once (Retroactive), and each level after
-- gives its own as it's reached. Each level's coins are paid exactly once: the profile keeps the last
-- level whose gold coins were paid (CoinsTo), so a level reached on a server still running older
-- code, or a purchase while the profile is busy, is caught up later and never paid twice. Owning an
-- item is the record for cosmetics (Services/CosmeticService.CheckUnlocks). Owners get 10% more XP
-- from a round (XPBonus, rounded up); the experience's creator always owns the pass (IsCreator).
-- Leaf module: no requires, no Roblox APIs. Tuning values are passed in (Config.GoldRoad).

local GoldLane = {}

GoldLane.FirstLevel = 2

export type Road = { Base: number, PerTen: number, XPBoost: number }

-- One level's gold reward: its coins (0 on a cosmetic level) and its cosmetics (ids).
export type Reward = { Level: number, Coins: number, Items: { string } }
export type Lane = { [number]: Reward }

-- What a purchase (or a catch-up) gives at once.
export type Unlock = {
	Count: number, -- rewards: coin levels paid plus cosmetics newly owned
	Coins: number,
	CoinLevels: number,
	Items: { string }, -- cosmetics not owned yet, highest level first
}

-- The gold coins a level without a gold cosmetic pays.
function GoldLane.Coins(level: number, road: Road): number
	return road.Base + road.PerTen * math.floor(level / 10)
end

-- The whole lane: a reward for every level from FirstLevel to maxLevel. `itemLevels` is every gold
-- cosmetic's level (id -> GoldLevel); a level's items are in id order.
function GoldLane.Build(itemLevels: { [string]: number }, road: Road, maxLevel: number): Lane
	local byLevel: { [number]: { string } } = {}
	for id, level in itemLevels do
		local list = byLevel[level] or {}
		byLevel[level] = list
		table.insert(list, id)
	end
	local lane: Lane = {}
	for level = GoldLane.FirstLevel, maxLevel do
		local items = byLevel[level] or {}
		table.sort(items)
		lane[level] = { Level = level, Coins = if #items > 0 then 0 else GoldLane.Coins(level, road), Items = items }
	end
	return lane
end

-- The gold coins for the levels after `fromLevel` up to `toLevel` (each level once).
function GoldLane.CoinsBetween(lane: Lane, fromLevel: number, toLevel: number): (number, number)
	local coins, levels = 0, 0
	for level = math.max(GoldLane.FirstLevel - 1, math.floor(fromLevel)) + 1, math.floor(toLevel) do
		local reward = lane[level]
		if reward and reward.Coins > 0 then
			coins += reward.Coins
			levels += 1
		end
	end
	return coins, levels
end

-- Every gold reward a player at `level` has reached: the coins of the levels after `coinsTo` (the
-- ones before were paid already) and the cosmetics they don't own yet. What buying the pass unlocks
-- at once, and what a level-up or a returning owner gets.
function GoldLane.Retroactive(lane: Lane, level: number, coinsTo: number, owned: { [string]: boolean }): Unlock
	local coins, coinLevels = GoldLane.CoinsBetween(lane, coinsTo, level)
	local items: { string } = {}
	for at = math.floor(level), GoldLane.FirstLevel, -1 do
		local reward = lane[at]
		if reward then
			for _, id in reward.Items do
				if not owned[id] then
					table.insert(items, id)
				end
			end
		end
	end
	return { Count = coinLevels + #items, Coins = coins, CoinLevels = coinLevels, Items = items }
end

-- How many gold rewards there are from level 2 up to `level` (coin levels and cosmetics).
function GoldLane.RewardCount(lane: Lane, level: number): number
	local count = 0
	for at = GoldLane.FirstLevel, math.floor(level) do
		local reward = lane[at]
		if reward then
			count += if #reward.Items > 0 then #reward.Items else 1
		end
	end
	return count
end

-- An owner's extra XP for a round that paid `xp` (at least 1 once a round pays any).
function GoldLane.XPBonus(xp: number, road: Road): number
	if xp ~= xp or xp <= 0 then
		return 0
	end
	return math.max(1, math.ceil(xp * road.XPBoost - 1e-9))
end

-- The experience's creator always has the pass: a user-owned experience and that user.
function GoldLane.IsCreator(creatorType: string, creatorId: number, userId: number): boolean
	return creatorType == "User" and creatorId > 0 and userId == creatorId
end

-- What the GET GOLD PASS button offers: whether it's for sale and its price in Robux, from Roblox's
-- product info (MarketplaceService:GetProductInfo, asked in a pcall: `ok` and `info`). No pass yet
-- (id 0) or off sale on Roblox: nothing to buy (COMING SOON). Roblox couldn't be asked: offered at
-- its usual price, `fallbackPrice` (Roblox's own prompt has the last word). Known says Roblox answered.
export type Offer = { OnSale: boolean, Price: number, Known: boolean }

function GoldLane.Offer(passId: number, ok: boolean, info: any, fallbackPrice: number): Offer
	if passId == 0 then
		return { OnSale = false, Price = fallbackPrice, Known = true }
	elseif not ok or type(info) ~= "table" then
		return { OnSale = true, Price = fallbackPrice, Known = false }
	end
	local price = tonumber(info.PriceInRobux)
	local priced = price ~= nil and price == price and price > 0
	return {
		OnSale = info.IsForSale == true and priced,
		Price = if priced then math.floor(price :: number) else fallbackPrice,
		Known = true,
	}
end

return GoldLane
