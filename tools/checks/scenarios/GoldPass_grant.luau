-- Scenario for round_harness.py --bot: the GOLD PASS bought, found and granted on a real server
-- (Services/GoldPassService; owner: "Also we do need a paid battle pass too. I like the current free
-- one. But the paid one should also be insane."). Any mode works; the stand-ins don't play it.
--
--   python3 tools/checks/round_harness.py RakeItIn --players 4 --bots 1 --seconds 40 \
--       --bot tools/checks/scenarios/GoldPass_grant.luau > gold.luau
--
-- A check server can't buy anything, so Roblox is stood in for (GoldPassService.SetRobloxForTests:
-- who owns the pass, the purchase prompt, the product info). Each line of the log starts "gold:":
--   * offer:     off sale on Roblox, GET (the "Prompt" remote) only says COMING SOON; on sale, it
--                shows Roblox's prompt
--   * purchase:  Bot2 (level 9, a save from the old coin scale) buys it: granted at once with the gold
--                coins of levels 3, 5, 7 and 9, the four gold cosmetics reached and the UNLOCKED
--                card's payload; the same event again grants nothing; another pass, or a cancelled
--                purchase, nothing
--   * nametag:   Bot2's name tag has the GOLD badge and the gold shimmer
--   * join:      Bot3 owns it on Roblox (bought on the website): the join check grants it; Bot4
--                doesn't: nothing; a check that fails twice: nothing (asked twice, a moment apart)
--   * test:      TestGrant refuses without the check tools' flag, and gives Bot1 (level 1) the pass
--   * levelup:   Bot2 to level 10 (the GOLD PARTY HAT, no gold coins) and 11 (7 gold coins): the
--                level-up cards' payloads
--   * catchup:   Bot3's level went up on an older server (no gold coins paid): its join pays them,
--                once
--   * creator:   the experience's creator (this server's game.CreatorId) always owns it
--   * trail:     LIQUID SUNLIGHT on Bot2: textured, wide, glitter and a light
--   * hats:      each gold hat on Bot2's head in the lobby (its uploaded mesh, light and glitter)
--   * results:   the round's rewards: the owners' results cards have "👑 GOLD PASS +10% XP"; Bot4's
--                doesn't
-- The stand-ins' profiles never save (the harness's), and no real player's data is read or written.
return function(env)
	local GoldPassService = __require("Server/Services/GoldPassService")
	local CosmeticService = __require("Server/Services/CosmeticService")
	local DataService = __require("Server/Services/DataService")
	local Economy = __require("Server/Services/Economy")
	local Hats = __require("Server/World/Hats")
	local Config = __require("Shared/Config")
	local LevelCurve = __require("Shared/Logic/LevelCurve")
	local Remotes = __modules["Shared/Remotes"]() -- (the harness's recording remotes: every Get hands out the same one)
	local RoundEvents = __require("Server/Services/RoundEvents")

	local function note(text)
		env.note("gold: " .. text)
	end
	local bot1, bot2, bot3, bot4 = env.players[1], env.players[2], env.players[3], env.players[4]
	if not bot4 then
		note("PROBLEM: run it with --players 4")
		return function() end
	end
	local passId = Config.Monetization.GoldPassId
	local function data(player)
		return DataService.Get(player).Data
	end
	local function goldItems(player)
		local list = {}
		for id in data(player).Owned do
			local item = __require("Shared/Cosmetics").Get(id)
			if item and item.GoldLevel then
				table.insert(list, `{id}@{item.GoldLevel}`)
			end
		end
		table.sort(list)
		return table.concat(list, ",")
	end
	local function send(remote, player, ...)
		__remoteObjects[remote].__bindable:Fire(__playerKey(player), ...)
	end

	-- What the server sends: the UNLOCKED card, the level-up cards, toasts and results cards.
	local sent = { GoldPass = {}, Celebrate = {}, Notify = {}, RoundResults = {} }
	for name, list in sent do
		local remote = Remotes.Get(name)
		local fire = remote.FireClient
		remote.FireClient = function(self, player, ...)
			table.insert(
				list,
				{ who = if type(player) == "table" then player.Name else tostring(player), args = { ... } }
			)
			return fire(self, player, ...)
		end
	end
	local function lastTo(name, player)
		for index = #sent[name], 1, -1 do
			if sent[name][index].who == player.Name then
				return sent[name][index].args
			end
		end
		return nil
	end
	local function count(name, player)
		local total = 0
		for _, entry in sent[name] do
			total += if entry.who == player.Name then 1 else 0
		end
		return total
	end

	-- Roblox, stood in for.
	local prompted = {}
	local ownsOnRoblox = { [bot3.UserId] = true }
	local failing, asked = false, 0
	local info = { IsForSale = false, PriceInRobux = 399 }
	GoldPassService.SetRobloxForTests({
		Owns = function(userId, id)
			asked += 1
			if failing then
				error("HTTP 503 (stand-in)")
			end
			return ownsOnRoblox[userId] == true and id == passId
		end,
		Prompt = function(player, id)
			table.insert(prompted, `{player.Name} {id}`)
		end,
		Info = function()
			return info
		end,
	})
	for name, service in { CosmeticService = CosmeticService, GoldPassService = GoldPassService } do
		local ok, err = pcall(service.Init)
		if not ok then
			note(`{name}.Init failed: {err}`)
		end
	end

	-- The round's rewards: who got the XP line.
	RoundEvents.Finished:Connect(function()
		task.wait()
		local rows = {}
		for _, who in { bot1, bot2, bot3, bot4 } do
			local payload = lastTo("RoundResults", who)
			local result = payload and payload[1]
			local line = "no results card"
			if type(result) == "table" then
				line = "no gold line"
				for _, entry in result.Lines or {} do
					if string.find(entry.Label, "GOLD PASS", 1, true) then
						line = `{entry.Label} +{entry.XP} XP (round XP {result.XP})`
					end
				end
			end
			table.insert(rows, `{who.Name} ({if GoldPassService.Owns(who) then "owner" else "no pass"}): {line}`)
		end
		note("results: " .. table.concat(rows, "; "))
		GoldPassService.SetRobloxForTests(nil)
	end)

	task.spawn(function()
		task.wait(0.5)
		-- offer
		local offer = GoldPassService.AskOffer()
		note(`offer: off sale -> OnSale {offer.OnSale}, R$ {offer.Price}, Known {offer.Known}`)
		send("GoldPass", bot4, "Prompt")
		task.wait(0.2)
		local toast = lastTo("Notify", bot4)
		note(`offer: GET while off sale -> prompts {#prompted}, toast "{toast and toast[1] or "none"}"`)
		info = { IsForSale = true, PriceInRobux = 449 }
		offer = GoldPassService.AskOffer()
		send("GoldPass", bot4, "Prompt")
		task.wait(0.2)
		note(`offer: on sale -> R$ {offer.Price}; GET -> prompted {table.concat(prompted, ", ")}`)

		-- purchase
		local before2 = { coins = data(bot2).Coins, level = LevelCurve.FromTotalXP(data(bot2).XP) }
		GoldPassService.PurchaseFinished(bot2, passId, true)
		local pass2 = data(bot2).GoldPass
		local card = lastTo("GoldPass", bot2)
		local payload = card and card[2]
		note(
			`purchase: Bot2 at level {before2.level}: owned {pass2.Owned}, coins +{data(bot2).Coins - before2.coins}, `
				.. `CoinsTo {pass2.CoinsTo}, gold items {goldItems(bot2)}; card {card and card[1] or "none"} `
				.. `Count {payload and payload.Count}, Coins {payload and payload.Coins}, Items {payload and table.concat(
					payload.Items,
					","
				)}, Source {payload and payload.Source}`
		)
		local coinsNow = data(bot2).Coins
		GoldPassService.PurchaseFinished(bot2, passId, true)
		note(`purchase: again -> cards to Bot2 {count("GoldPass", bot2)}, coins +{data(bot2).Coins - coinsNow}`)
		GoldPassService.PurchaseFinished(bot4, 12345, true)
		GoldPassService.PurchaseFinished(bot4, passId, false)
		note(
			`purchase: another pass, or cancelled -> Bot4 owns {GoldPassService.Owns(bot4)}, cards {count(
				"GoldPass",
				bot4
			)}`
		)

		-- nametag
		local head = bot2.Character and bot2.Character:FindFirstChild("Head")
		local plate = head and head:FindFirstChild("PP_Nameplate")
		local name = plate and plate:FindFirstChild("PlayerName")
		local shimmer = name and name:FindFirstChild("GoldShimmer")
		note(
			`nametag: {if plate then plate.Size.Y.Offset .. " tall" else "MISSING"}, badge {plate and plate:FindFirstChild(
				"GoldBadge"
			) ~= nil}, `
				.. `shimmer {shimmer and shimmer:GetAttribute("PP_Shimmer") or "none"} (tagged {shimmer ~= nil and game
					:GetService("CollectionService")
					:HasTag(shimmer, "PP_GoldShimmer")})`
		)

		-- join
		GoldPassService.CheckOwnership(bot3)
		local card3 = lastTo("GoldPass", bot3)
		note(
			`join: Bot3 (owns it on Roblox) -> owned {GoldPassService.Owns(bot3)}, card Source {card3 and card3[2].Source}, Count {card3 and card3[2].Count}`
		)
		asked = 0
		GoldPassService.CheckOwnership(bot4)
		note(`join: Bot4 (doesn't) -> owned {GoldPassService.Owns(bot4)}, asked {asked}`)
		failing, asked = true, 0
		local started = os.clock()
		GoldPassService.CheckOwnership(bot4)
		failing = false
		note(
			`join: a check failing twice -> owned {GoldPassService.Owns(bot4)}, asked {asked}, over {math.round(
				(os.clock() - started) * 10
			) / 10} s`
		)

		-- test
		workspace:SetAttribute("PP_Harness", nil)
		local refused = GoldPassService.TestGrant(bot1)
		workspace:SetAttribute("PP_Harness", true)
		local granted = GoldPassService.TestGrant(bot1)
		local card1 = lastTo("GoldPass", bot1)
		note(
			`test: without the flag -> {refused}; with it -> {granted}, card Count {card1 and card1[2].Count}, Coins {card1 and card1[2].Coins}`
		)

		-- levelup
		local function levelUp(player, toLevel)
			local need = LevelCurve.TotalXPForLevel(toLevel) - data(player).XP
			Economy.AddXP(player, need)
			local cardArgs = lastTo("Celebrate", player)
			local c = cardArgs and cardArgs[1]
			return if c
				then `Lv {c.From} -> {c.Level}: Coins {c.Coins}, GoldCoins {c.GoldCoins}, Items {table.concat(
					c.Items,
					","
				)}`
				else "no card"
		end
		note(`levelup: Bot2 {levelUp(bot2, 10)}`)
		note(`levelup: Bot2 {levelUp(bot2, 11)}; CoinsTo {data(bot2).GoldPass.CoinsTo}`)

		-- catchup: a game on an older server took Bot3 from level 4 to 8 (no gold coins there).
		local d3 = data(bot3)
		local level3 = LevelCurve.FromTotalXP(d3.XP)
		d3.XP = LevelCurve.TotalXPForLevel(8)
		local coins3 = d3.Coins
		GoldPassService.CheckOwnership(bot3)
		local first = d3.Coins - coins3
		GoldPassService.CheckOwnership(bot3)
		local toast3 = lastTo("Notify", bot3)
		note(
			`catchup: Bot3 {level3} -> 8 elsewhere: +{first} coins, then +{d3.Coins - coins3 - first}; CoinsTo {d3.GoldPass.CoinsTo}; gold items {goldItems(
				bot3
			)}; toast "{toast3 and toast3[1] or "none"}"`
		)

		-- creator
		note(
			`creator: this server's creator {game.CreatorType.Name} {game.CreatorId}: owns it {GoldPassService.IsCreator(
				{ UserId = game.CreatorId } :: any
			)}; a stand-in {GoldPassService.IsCreator(bot4)}`
		)

		-- trail
		local d2 = data(bot2)
		d2.Owned.Trail_LiquidSunlight = true
		d2.Equipped.Trail = "Trail_LiquidSunlight"
		CosmeticService.Refresh(bot2)
		local root = bot2.Character and bot2.Character:FindFirstChild("HumanoidRootPart")
		local trail = root and root:FindFirstChild("PP_Trail")
		local top = root and root:FindFirstChild("PP_TrailTop")
		local glitter = root and root:FindFirstChild("PP_TrailGlitter")
		note(
			`trail: {if trail
				then `texture {trail.Texture}, width {math.round(top.Position.Y * 200) / 100}, lifetime {trail.Lifetime}, light emission {trail.LightEmission}`
				else "MISSING"}; `
				.. `glitter {glitter and glitter.Rate or "none"} (tagged {glitter ~= nil and game:GetService(
					"CollectionService"
				):HasTag(glitter, "PP_GoldGlitter")}); light {root and root:FindFirstChild("PP_TrailLight") ~= nil}`
		)

		-- hats: each on Bot2's head in the lobby.
		bot2:SetAttribute("PP_InRound", false)
		local props = {
			Hat_GoldParty = "GoldPartyHat",
			Hat_RoyalCrown = "RoyalCrown",
			Hat_GoldenHalo = "GoldenHalo",
			Hat_GildedTopHat = "GildedTopHat",
			Hat_SunKing = "SunKingCrown",
		}
		for _, id in { "Hat_GoldParty", "Hat_RoyalCrown", "Hat_GoldenHalo", "Hat_GildedTopHat", "Hat_SunKing" } do
			d2.Owned[id] = true
			d2.Equipped.Hat = id
			CosmeticService.Refresh(bot2)
			local t0 = os.clock()
			while Hats.Worn(bot2.Character) ~= id and os.clock() - t0 < 20 do
				task.wait(0.1)
			end
			local hat = bot2.Character:FindFirstChild(Hats.Name)
			local handle = hat and hat:FindFirstChild("Handle")
			local headPart = bot2.Character:FindFirstChild("Head")
			local parts, lights, glitters, low, high = 0, 0, 0, math.huge, -math.huge
			for _, item in if hat then hat:GetDescendants() else {} do
				if item:IsA("BasePart") then
					parts += 1
					local y = headPart.CFrame:PointToObjectSpace(item.Position).Y
					low, high = math.min(low, y - item.Size.Y / 2), math.max(high, y + item.Size.Y / 2)
				elseif item:IsA("PointLight") then
					lights += 1
				elseif item:IsA("ParticleEmitter") then
					glitters += 1
				end
			end
			local source = __require("Server/World/MeshLibrary").Source
			note(
				`hats: {id} worn {Hats.Worn(bot2.Character) == id} after {math.round((os.clock() - t0) * 10) / 10} s, `
					.. `{if handle
						then `{handle.ClassName} {math.round(handle.Size.X * 100) / 100} wide`
						else "no handle"}, {parts} parts, `
					.. `{lights} light, {glitters} glitter; from y {math.round(low * 100) / 100} to {math.round(
						high * 100
					) / 100} on a head `
					.. `{math.round(headPart.Size.Y * 100) / 100} tall; mesh from {if source
						then source(props[id])
						else "?"}`
			)
		end
		d2.Equipped.Hat = ""
		CosmeticService.Refresh(bot2)
		bot2:SetAttribute("PP_InRound", true)
		note("done")
	end)

	return function() end
end
