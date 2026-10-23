-- The crate season on a real Roblox server (owner: "Hollow night comes first I want you to actually
-- work on adding it to the game right now ... Also do all of your ideas."). tools/checks/crates_check.py
-- bundles this with the round harness's prelude (stand-in players with profiles, the recording
-- remotes) and the working tree's modules. Nothing touches a real store or another server: the run
-- sets workspace PP_Harness, so the boards and first-in-the-world claims stay in memory, and Roblox's
-- purchase side is a stand-in (nothing can be bought here).
--
-- It builds the real lobby (the pile, the altars, the board, the autumn dressing, the meshes the
-- devices get) and checks: starter keys once, last season's crates carried over, a crate a round (not
-- for bots), the cup's keys (3 / 2 / 1, the whole cup, the day's first cup, the GOLD PASS), quest and
-- level keys, the welcome's crate once, opening at an altar (rolled and saved before the show, the
-- altar busy until it ends, too far / busy / in a round / no keys refused), Open 5, over the head, a
-- forced pet (put on at the reveal, the banner, first in the world), the title (every other server
-- told), the friend bonus on the meter, the Top Unboxers board and ranks, and the key shop (prices
-- from Roblox, a receipt granted once, a gift to a friend here, the starter pack once, a restricted
-- player never prompted).
function __runCrates()
	local summary = { checks = {}, failed = {} }
	local function check(name: string, ok: boolean, detail: any?)
		local line = (if ok then "ok   " else "FAIL ") .. name
		if detail ~= nil then
			line ..= ": " .. (if type(detail) == "table" then HttpService:JSONEncode(detail) else tostring(detail))
		end
		table.insert(summary.checks, line)
		if not ok then
			table.insert(summary.failed, name)
		end
	end

	workspace:SetAttribute("PP_Harness", true) -- before anything can reach a store
	local CollectionService = game:GetService("CollectionService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local GameState = __require("Shared/GameState")
	GameState.Folder()
	GameState.Set("Phase", "Intermission")
	local Config = __require("Shared/Config")
	local CrateLogic = __require("Shared/Logic/CrateLogic")
	local ProfileMigration = __require("Shared/Logic/ProfileMigration")
	local Seasons = __require("Shared/Seasons")
	local DataService = __require("Server/Services/DataService")
	local Notifier = __require("Server/Services/Notifier")
	local FriendsService = __require("Server/Services/FriendsService")
	local LobbyBuilder = __require("Server/World/LobbyBuilder")
	local SeasonWorld = __require("Server/World/SeasonWorld")
	local season = Seasons.CurrentSeason()

	-- Fake product ids, so the key shop has something to sell (before it's required: it indexes them).
	local packs = Config.Monetization.KeyPacks
	packs[1].Id, packs[1].GiftId = 9000001, 9100001
	packs[2].Id, packs[2].GiftId = 9000005, 9100005
	packs[3].Id, packs[3].GiftId = 9000015, 9100015
	packs[4].Id, packs[4].GiftId = 9000040, 9100040
	Config.Monetization.StarterPack.Id = 9000099

	-- Every message the crate remote sends, with its payload (the prelude's recorder keeps only kinds).
	__require("Server/Services/CrateService") -- (makes the remote)
	local crate = __remoteObjects["Crate"]
	local sent = {}
	crate.FireAllClients = function(_, action, payload)
		table.insert(sent, { To = "all", Action = action, Payload = payload })
	end
	crate.FireClient = function(_, player, action, payload)
		table.insert(sent, { To = player.Name, Action = action, Payload = payload })
	end
	local function lastSent(action: string, to: string?): any
		for index = #sent, 1, -1 do
			local entry = sent[index]
			if entry.Action == action and (to == nil or entry.To == to) then
				return entry.Payload
			end
		end
		return nil
	end
	local toasts = {}
	Notifier.Send = function(player, text)
		table.insert(toasts, `{player.Name}: {text}`)
	end
	Notifier.All = function(text)
		table.insert(toasts, `all: {text}`)
	end

	-- 1. The lobby: the pile, the altars, the board, the dressing.
	local okLobby, refs = pcall(LobbyBuilder.Build)
	check("lobby builds", okLobby, if okLobby then nil else tostring(refs))
	local altars = SeasonWorld.Altars()
	check("three altars with prompts", #altars == 3 and altars[1].Prompt ~= nil, #altars)
	local root = if okLobby then refs.Root else workspace
	local pile = root:FindFirstChild("CratePile", true)
	check("the pile stands where the fountain was", pile ~= nil and root:FindFirstChild("Fountain", true) == nil)
	check(
		"the pile's top crate turns and its keys circle",
		pile and pile:FindFirstChild("TopCrate") ~= nil and pile:FindFirstChild("Keys") ~= nil
	)
	local board = root:FindFirstChild("TopUnboxers", true)
	check("the Top Unboxers board", board ~= nil and board:FindFirstChild("Screen") ~= nil)
	local counts = {}
	for _, tagName in { "PP_Crow", "PP_LeafHeap", "PP_AutumnTree", "PP_CrateAltar", "PP_CrateBoard" } do
		counts[tagName] = #CollectionService:GetTagged(tagName)
	end
	check(
		"crows, leaf heaps, autumn trees",
		counts.PP_Crow >= 5 and counts.PP_LeafHeap == 5 and counts.PP_AutumnTree > 20,
		counts
	)
	local lanterns = root:FindFirstChild("Lanterns", true)
	check("lantern posts", lanterns ~= nil and #lanterns:GetChildren() == 12)
	local sky = root:FindFirstChild("FallingLeaves", true)
	check("leaves fall instead of confetti", sky ~= nil)
	-- The meshes every device gets (made in the background).
	local deadline = os.clock() + 60
	local meshes
	repeat
		task.wait(0.5)
		meshes = ReplicatedStorage:FindFirstChild("SeasonMeshes")
	until (meshes and #meshes:GetChildren() >= 14) or os.clock() > deadline
	local names = {}
	for _, child in (if meshes then meshes:GetChildren() else {}) do
		table.insert(names, child.Name)
	end
	table.sort(names)
	check("the devices' season meshes", meshes ~= nil and #names >= 14, names)
	local sources = {}
	local MeshLibrary = __require("Server/World/MeshLibrary")
	for _, name in { "HollowCrate", "HollowPile", "HarvestOwl", "LanternWisp", "CrescentMoon" } do
		sources[name] = MeshLibrary.Source(name)
	end
	check(
		"meshes come from the uploads, not the stand-ins",
		sources.HollowCrate ~= "Fallback" and sources.HarvestOwl ~= "Fallback",
		sources
	)

	-- 2. People: starter keys once, last season's crates carried over.
	for index = 1, 4 do
		table.insert(__fakePlayers, __newPlayer(index))
	end
	__seedProfiles()
	local people = table.clone(__fakePlayers)
	local Ann, Bo, Cy, Di = people[1], people[2], people[3], people[4]
	local function data(player)
		return DataService.Get(player).Data
	end
	data(Di).Crates = { Season = "OldSeason", Count = 4 }
	local CrateService = __require("Server/Services/CrateService")
	local CrateBoardService = __require("Server/Services/CrateBoardService")
	local KeyShopService = __require("Server/Services/KeyShopService")
	local bought = {}
	KeyShopService.SetRobloxForTests({
		Prompt = function(player, productId)
			table.insert(bought, `{player.Name}:{productId}`)
		end,
		Info = function(productId)
			local prices = { [9000001] = 25, [9000005] = 99, [9000015] = 249, [9000040] = 549 }
			return { PriceInRobux = prices[productId] or 79, IsForSale = true }
		end,
		Restricted = function(player)
			return player.Name == "Bot3"
		end,
	})
	CrateBoardService.Init()
	CrateService.Init()
	KeyShopService.Init()
	task.spawn(CrateService.Start)
	for _, person in people do
		CrateService.ProfileReady(person)
	end
	check("3 starter keys each", data(Ann).Keys == 3 and data(Bo).Keys == 3, { data(Ann).Keys, data(Bo).Keys })
	CrateService.ProfileReady(Ann)
	check("starter keys only once", data(Ann).Keys == 3, data(Ann).Keys)
	check(
		"last season's crates are this season's",
		data(Di).Crates.Season == season.Id and data(Di).Crates.Count == 4,
		data(Di).Crates
	)

	-- 3. A crate a round, never for a bot.
	local line = CrateService.RoundCrate(Ann)
	check("a round's crate, on the results card", line ~= nil and line.Count == 1 and data(Ann).Crates.Count == 1, line)
	local bot = { IsBot = true, UserId = -1, Name = "Bot_1", DisplayName = "🤖", Parent = true }
	check("no crate for a bot", CrateService.RoundCrate(bot :: any) == nil)

	-- 4. Keys: the cup, quests, levels.
	local first = CrateService.CupKeysFor(Bo, 1, true)
	check("cup winner who played it all, first cup today: 3 + 1 + 1", first == 5, first)
	CrateService.GiveCupKeys(Bo, first, 1)
	local again = CrateService.CupKeysFor(Bo, 1, true)
	check("the day's first-cup key only once", again == 4, again)
	check("off the podium, part of the cup: just the day's key", CrateService.CupKeysFor(Cy, 5, false) == 1)
	data(Cy).GoldPass.Owned = true
	check("GOLD PASS on the podium: +1", CrateService.CupKeysFor(Cy, 3, false) == 1 + 1 + 1)
	check("weekly quest key", CrateService.QuestKeys(Cy, "Weekly") == 1 and CrateService.QuestKeys(Cy, "Daily") == 0)
	check("a key every 5th level", CrateService.LevelKeys(Cy, 4, 11) == 2)
	local gift = lastSent("Gift", "Bot3")
	check("keys given say why", gift ~= nil and gift.Reason == "Road", gift)

	-- 5. The welcome's crate, once.
	local fire = crate.__bindable
	fire:Fire(__playerKey(Bo), "Welcome")
	task.wait(0.2)
	fire:Fire(__playerKey(Bo), "Welcome")
	task.wait(0.2)
	check(
		"the welcome's crate once",
		data(Bo).Crates.Count == 1 and data(Bo).CrateFlags.Welcome == season.Id,
		data(Bo).Crates
	)

	-- 6. Opening at an altar.
	local altar = altars[1]
	local function standAt(player, position: Vector3)
		player.Character:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))
	end
	CrateService.TestGive(Ann, 10, 10)
	standAt(Ann, (altar.Model:GetPivot() * CFrame.new(0, 0, -4.6)).Position)
	standAt(Bo, Vector3.new(60, 0, 60))
	local keysBefore, cratesBefore = data(Ann).Keys, data(Ann).Crates.Count
	CrateService.TestRolls({ 0.005, 0 }) -- a pet: the first one not owned
	local ok, why = CrateService.Open(Ann, 1, 1)
	check("opens at the altar", ok, why)
	local show = lastSent("Show")
	local pet = season.Pets[1]
	check(
		"the show says what came out",
		show and show.Results[1].Tier == "Pet" and show.Results[1].Item == pet,
		show and show.Results
	)
	check(
		"saved before the show: owned, found, a key and a crate used",
		data(Ann).Owned[pet] == true
			and data(Ann).Keys == keysBefore - 1
			and data(Ann).Crates.Count == cratesBefore - 1
			and data(Ann).Seasons[season.Id].Found[pet] ~= nil
	)
	check("the altar's busy", altar.Model:GetAttribute("PP_AltarBusy") == Ann.UserId and altar.Prompt.Enabled == false)
	local ok2, why2 = CrateService.Open(Ann, 1, 2)
	check("one show at a time", not ok2 and why2 == "Busy", why2)
	CrateService.TestGive(Bo, 2, 2)
	local ok3, why3 = CrateService.Open(Bo, 1, 1)
	check("someone else at a busy altar", not ok3 and why3 == "AltarBusy", why3)
	local ok4, why4 = CrateService.Open(Bo, 1, 2)
	check("too far from an altar", not ok4 and why4 == "TooFar", why4)
	task.wait(Config.Crates.RevealAt + 0.6)
	check("the pet goes on at the reveal", data(Ann).Equipped.Pet == pet, data(Ann).Equipped.Pet)
	check("PP_Pet tells every device", Ann:GetAttribute("PP_Pet") == pet)
	local banner = lastSent("Banner")
	check(
		"a banner for every screen, first in the world",
		banner and banner.Item == pet and banner.First == true,
		banner
	)
	task.wait(Config.Crates.ShowTime - Config.Crates.RevealAt + 0.6)
	check("the altar frees up", altar.Model:GetAttribute("PP_AltarBusy") == 0 and altar.Prompt.Enabled == true)

	-- 7. The title: every other server hears it.
	CrateService.TestRolls({ 0.001, 0 })
	local okTitle = CrateService.Open(Ann, 1, 1)
	task.wait(Config.Crates.RevealAt + 0.6)
	local messages = CrateBoardService.Harness.Messages
	check("THE HARVESTER: owned and on", okTitle and data(Ann).Equipped.Title == season.Title)
	check("every other server told", #messages == 1 and messages[1].Item == season.Title, messages)
	task.wait(Config.Crates.ShowTime - Config.Crates.RevealAt + 0.3)

	-- 8. Open 5 over the head; the friend bonus on the meter; refusals.
	CrateService.TestRolls({ 0.99, 0.5 })
	FriendsService.SetFriendsForTest(Ann, Bo)
	standAt(Bo, Ann.Character:GetPivot().Position + Vector3.new(4, 0, 0))
	local meterBefore = data(Ann).Seasons[season.Id].Meter
	local okMany = CrateService.Open(Ann, CrateLogic.OpenMany, 0)
	local many = lastSent("Show")
	check("Open 5 over the head", okMany and many.Altar == 0 and #many.Results == 5, many and #many.Results)
	check(
		"a friend nearby: +2 on the meter a crate",
		data(Ann).Seasons[season.Id].Meter == meterBefore + 10 and many.Friend == true,
		{ meterBefore, data(Ann).Seasons[season.Id].Meter }
	)
	check("coins from crates paid", data(Ann).Seasons[season.Id].Coins > 0)
	task.wait(Config.Crates.ShowTimeMany + 0.3)
	Cy:SetAttribute("PP_InRound", true)
	Cy:SetAttribute("PP_Alive", true)
	CrateService.TestGive(Cy, 1, 1)
	local _, inRound = CrateService.Open(Cy, 1, 0)
	check("never while playing a round", inRound == "InRound", inRound)
	-- Out of the round (back in the lobby while it goes on): crates open (owner: "Bug: cant open
	-- crates in the lobby while a game is happenin").
	Cy:SetAttribute("PP_Alive", false)
	local outOpened, outWhy = CrateService.Open(Cy, 1, 0)
	check("out of the round, in the lobby: opens", outOpened == true, outWhy)
	Cy:SetAttribute("PP_InRound", false)
	task.wait(Config.Crates.ShowTime + 0.3)
	data(Di).Keys = 0
	local _, noKeys = CrateService.Open(Di, 1, 0)
	check("no keys: refused (the key shop opens)", noKeys == "NoKeys", noKeys)

	-- 9. Top Unboxers.
	CrateBoardService.Harness.Refresh()
	local crateBoard = GameState.GetJSON("CrateBoard")
	check(
		"the board: Ann on top this season, this week and here",
		crateBoard
			and crateBoard.Top[1]
			and crateBoard.Top[1].UserId == Ann.UserId
			and crateBoard.WeekTop[1].UserId == Ann.UserId
			and crateBoard.Server[1].UserId == Ann.UserId,
		crateBoard and crateBoard.Top
	)
	check(
		"first in the world on the board",
		crateBoard and crateBoard.Firsts[pet] and crateBoard.Firsts[pet].UserId == Ann.UserId
	)
	check("Ann's place", Ann:GetAttribute("PP_CrateRank") == 1, Ann:GetAttribute("PP_CrateRank"))

	-- 10. The key shop.
	task.wait(4) -- (the policy checks)
	KeyShopService.AskInfo()
	local shop = GameState.GetJSON("KeyShop")
	check(
		"packs on sale with Roblox's prices",
		shop
			and #shop.Packs == 4
			and shop.Packs[1].Price == 25
			and shop.Packs[2].Price == 99
			and shop.Packs[4].Price == 549
			and shop.Starter ~= nil,
		shop
	)
	check(
		"a restricted player is locked out",
		Cy:GetAttribute("PP_KeysLocked") == true and Ann:GetAttribute("PP_KeysLocked") == false
	)
	fire:Fire(__playerKey(Cy), "Buy", "Keys5")
	fire:Fire(__playerKey(Ann), "Buy", "Keys5")
	task.wait(0.3)
	check("only the unrestricted player is prompted", #bought == 1 and bought[1] == `{Ann.Name}:9000005`, bought)
	local keys0 = data(Ann).Keys
	local decision = KeyShopService.Harness.Receipt(Ann.UserId, 9000005, "receipt-1")
	check(
		"a receipt grants 5 keys",
		decision == Enum.ProductPurchaseDecision.PurchaseGranted and data(Ann).Keys == keys0 + 5,
		data(Ann).Keys - keys0
	)
	local repeatDecision = KeyShopService.Harness.Receipt(Ann.UserId, 9000005, "receipt-1")
	check("never twice", repeatDecision == Enum.ProductPurchaseDecision.PurchaseGranted and data(Ann).Keys == keys0 + 5)
	fire:Fire(__playerKey(Ann), "Buy", "Keys15", Di.UserId)
	task.wait(0.3)
	local diKeys = data(Di).Keys
	KeyShopService.Harness.Receipt(Ann.UserId, 9100015, "receipt-2")
	check(
		"a gift goes to the friend",
		data(Di).Keys == diKeys + 15 and lastSent("Gift", "Bot4").From == Ann.DisplayName,
		data(Di).Keys - diKeys
	)
	KeyShopService.Harness.Receipt(Ann.UserId, 9000099, "receipt-3")
	check(
		"the starter pack: keys and the banner trail",
		data(Ann).CrateFlags.StarterPack == true and data(Ann).Owned[season.Starter] == true
	)
	fire:Fire(__playerKey(Ann), "Buy", "Starter")
	task.wait(0.3)
	check("the starter pack only once", #bought == 2, bought)
	local unknown = KeyShopService.Harness.Receipt(Ann.UserId, 12345, "receipt-4")
	check("a product that isn't ours waits", unknown == Enum.ProductPurchaseDecision.NotProcessedYet)

	-- 11. Purchases whose saves go wrong (the pre-release sweep): only that purchase is ever taken
	-- back, a buyer who leaves mid-save isn't told it went through, a gift is delivered once.
	local Receipt, Saves = KeyShopService.Harness.Receipt, KeyShopService.Harness.Saves
	local GRANTED, WAITS = Enum.ProductPurchaseDecision.PurchaseGranted, Enum.ProductPurchaseDecision.NotProcessedYet
	local annData = data(Ann)
	table.clear(annData.Receipts)
	for k = 1, ProfileMigration.MaxReceipts do
		table.insert(annData.Receipts, `old-{k}`)
	end
	local before = annData.Keys
	Saves[Ann.UserId] = "Failed"
	local failed = Receipt(Ann.UserId, 9000005, "receipt-5")
	check(
		"a failed save: not granted, Roblox asks again",
		failed == WAITS and annData.Keys == before,
		annData.Keys - before
	)
	check(
		"a failed save takes back just its own receipt (a full list keeps its oldest)",
		#annData.Receipts == ProfileMigration.MaxReceipts
			and annData.Receipts[1] == "old-1"
			and table.find(annData.Receipts, "receipt-5") == nil,
		{ #annData.Receipts, annData.Receipts[1] }
	)
	Saves[Ann.UserId] = nil
	local retried = Receipt(Ann.UserId, 9000005, "receipt-5")
	check("Roblox's retry grants it", retried == GRANTED and annData.Keys == before + 5, annData.Keys - before)
	local spentFrom = annData.Keys
	Saves[Ann.UserId] = function()
		annData.Keys -= 1 -- (a crate opened while the save waits)
		return "Failed"
	end
	Receipt(Ann.UserId, 9000005, "receipt-6")
	check("a failed save keeps keys spent meanwhile spent", annData.Keys == spentFrom - 1, annData.Keys - spentFrom)
	Saves[Ann.UserId] = "Left"
	local leftFrom = annData.Keys
	local left = Receipt(Ann.UserId, 9000005, "receipt-7")
	check("a buyer who left mid-save isn't told it went through", left == WAITS and annData.Keys == leftFrom)
	Saves[Ann.UserId] = nil
	task.wait(10.5) -- (the shop's buttons: 4 presses in 10 s)
	fire:Fire(__playerKey(Ann), "Buy", "Keys15", Di.UserId)
	task.wait(0.3)
	local diBefore, annBefore = data(Di).Keys, annData.Keys
	Saves[Di.UserId] = "Left"
	local giftLeft = Receipt(Ann.UserId, 9100015, "receipt-8")
	Saves[Di.UserId] = nil
	local giftAgain = Receipt(Ann.UserId, 9100015, "receipt-8")
	check(
		"a gift whose friend left mid-save is theirs, once",
		giftLeft == GRANTED and giftAgain == GRANTED and data(Di).Keys == diBefore + 15 and annData.Keys == annBefore,
		{ data(Di).Keys - diBefore, annData.Keys - annBefore }
	)
	fire:Fire(__playerKey(Ann), "Buy", "Keys15", Di.UserId)
	task.wait(0.3)
	local diFrom = data(Di).Keys
	Saves[Di.UserId] = "Failed"
	local giftFailed = Receipt(Ann.UserId, 9100015, "receipt-9")
	Saves[Di.UserId] = nil
	check("a gift whose save failed isn't granted", giftFailed == WAITS and data(Di).Keys == diFrom)
	local giftRetry = Receipt(Ann.UserId, 9100015, "receipt-9")
	check(
		"its retry still goes to the friend",
		giftRetry == GRANTED and data(Di).Keys == diFrom + 15,
		data(Di).Keys - diFrom
	)
	local prompts = #bought
	fire:Fire(__playerKey(Ann), "Buy", "Keys5", Cy.UserId)
	task.wait(0.3)
	check("no gift for a player keys can't be sold to", #bought == prompts, bought)
	fire:Fire(__playerKey(Bo), "Buy", "Starter")
	task.wait(0.3)
	fire:Fire(__playerKey(Bo), "Buy", "Starter")
	task.wait(0.3)
	check("the starter pack can't be prompted twice before its receipt", #bought == prompts + 1, bought)

	-- 12. The creator's TRY ON (a playtest): any season item, worn this visit only, never owned or
	-- saved. (The creator here is a bare stand-in with the game's CreatorId and no profile: nothing
	-- reads or writes a real save.)
	local CosmeticService = __require("Server/Services/CosmeticService")
	local tried = {}
	local creator = { UserId = game.CreatorId, Name = "Creator", DisplayName = "Creator", Parent = true }
	function creator.SetAttribute(_, key, value)
		tried[key] = value
	end
	function creator.GetAttribute(_, key)
		return tried[key]
	end
	local annPet = Ann:GetAttribute("PP_Pet")
	check(
		"only the game's creator can try items on",
		CosmeticService.TryOn(Ann, season.Pets[2]) == false and Ann:GetAttribute("PP_Pet") == annPet
	)
	check(
		"the creator tries a pet on",
		CosmeticService.TryOn(creator, season.Pets[3]) and tried.PP_Pet == season.Pets[3],
		tried.PP_Pet
	)
	check(
		"trying it again takes it off",
		CosmeticService.TryOn(creator, season.Pets[3]) and tried.PP_Pet == "",
		tried.PP_Pet
	)
	check("only season items", CosmeticService.TryOn(creator, "Trail_Bubbles") == false)

	summary.toasts = toasts
	summary.sent = #sent
	return summary
end
