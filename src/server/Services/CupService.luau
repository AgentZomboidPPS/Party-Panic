-- Party Cups: every 5 rounds add up into a cup with a podium; the champion wears a crown in the
-- lobby until the next cup ends.
-- (owner, asked "If you could do 5 things to keep players addicted what would you do?", got Party
-- Cups among the five, then: "Can you work on all of that? this wont mess with what the other
-- workers are working on right?")
--
-- A cup is 5 rounds on this server (Logic/PartyCup has the scoring). Each round that finishes
-- (RoundEvents.Finished: called-off rounds never do) adds points by place to everyone who played
-- it, players and bots alike, so a lone player with bots still has a cup to win. People who join
-- mid-cup start at 0. People who leave drop off the standings (someone who comes back during the
-- same cup gets their points back); bots that fade out drop off for good.
--
-- After the cup's 5th round its final standings go out with that round's results (GameState
-- "Cup", Done), and every screen shows the podium as the results card ends (Controllers/
-- CupController). That's when the podium is paid, so the coins come with it: 5, 3 and 2 coins for
-- the people in 1st, 2nd and 3rd (bots on the podium win nothing), and everyone in the final
-- standings gets the cup in their stats (profile Cups: Played, Wins, Podiums). The podium says
-- what each one won and where the crown went, so there are no toasts: at the end of a round the
-- results card and the podium cover them, and other features need the two toast slots more. The
-- champion gets the "CupChampion" medal and wears a crown (World/CupCrown) in the lobby until the
-- next cup ends. A bot can win a cup: then nobody is crowned (and last cup's crown comes off).
-- The crown comes off for the rounds its wearer plays, so no mode ever has to deal with it, goes
-- back on their lobby character after, and leaving the server takes it away. Then a new cup starts.
-- Bots are never paid, saved, given medals or crowned.
--
-- GameState "Cup" (JSON; "" until this server's first round counts):
--   Number     the cup's number on this server (1, 2, ...)
--   Round      the cup's round that's next (1 to Of); with Done, its last
--   Of         rounds in a cup (5)
--   Played     rounds counted so far
--   Done       true from the end of the cup's last round until its podium is paid (Standings final)
--   EndedAt    server time the latest counted round ended (screens only celebrate fresh news)
--   Standings  the top 12, best first: { UserId, Name, Points, IsBot, Place, Gain } (Gain: the
--              points the latest round gave them)
--   Champion   who wears the crown now (a person, still here): { UserId, Name, Cup }; absent if nobody
--   Last       the last finished cup's podium: { Number, Podium = rows like Standings' }; absent at first
--   Keys       with Done: the crate keys each person gets, by UserId (as text); the podium shows them
--              (the crate seasons: "3 keys for 1st place, 2 keys for second, and 1 key for third")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local GameState = require(Shared.GameState)
local PartyCup = require(Shared.Logic.PartyCup)

local BotRegistry = require(script.Parent.BotRegistry)
local CrateService = require(script.Parent.CrateService)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.Economy)
local MedalService = require(script.Parent.MedalService)
local Notifier = require(script.Parent.Notifier)
local RoundEvents = require(script.Parent.RoundEvents)
local Telemetry = require(script.Parent.Telemetry)

local CupCrown = require(script.Parent.Parent.World.CupCrown)

local CupService = {}

local CROWN_EFFECT_AFTER = 2.5 -- seconds after the podium: the champion's lobby character is in

type Wearer = { Player: any, Cup: number, Connections: { RBXScriptConnection } }

local cup: PartyCup.Cup = PartyCup.New(1)
local started = false -- the attribute stays "" until this server's first round counts
local finishing = false -- a finished cup's podium is up: its prizes are paid as the results card ends
local endedAt = 0
local members: { [number]: any } = {} -- UserId -> the player or bot who played in this server's cups
local away: { [number]: PartyCup.Entry } = {} -- people who left during this cup, by UserId
local last: { [string]: any }? = nil -- the last finished cup's podium (the attribute's Last)
local wearers: { Wearer } = {} -- who wears the crown (the last cup's champions still here)

local function isBot(who: any): boolean
	return BotRegistry.IsBot(who)
end

-- Who wears the crown now, for the attribute.
local function championInfo(): { [string]: any }?
	for _, wearer in wearers do
		if wearer.Player.Parent then
			return { UserId = wearer.Player.UserId, Name = wearer.Player.DisplayName, Cup = wearer.Cup }
		end
	end
	return nil
end

-- The cup in progress, for every screen.
local function publish()
	if not started or finishing then
		return
	end
	GameState.SetJSON("Cup", {
		Number = cup.Number,
		Round = PartyCup.NextRound(cup),
		Of = PartyCup.Rounds,
		Played = cup.Played,
		Done = false,
		EndedAt = endedAt,
		Standings = PartyCup.Rows(PartyCup.Standings(cup)),
		Champion = championInfo(),
		Last = last,
	})
end

-- A finished cup's final standings, out with its last round's results: the podium's news. `keys`:
-- the crate keys each person in it gets (by UserId, as text for the JSON), shown on the podium.
local function publishFinal(finished: PartyCup.Cup, standings: { PartyCup.Standing }, keys: { [string]: number })
	GameState.SetJSON("Cup", {
		Number = finished.Number,
		Round = PartyCup.Rounds,
		Of = PartyCup.Rounds,
		Played = finished.Played,
		Done = true,
		EndedAt = endedAt,
		Standings = PartyCup.Rows(standings),
		Champion = championInfo(),
		Last = last,
		Keys = keys,
	})
end

-- The crown --------------------------------------------------------------------------------------

local function wearerOf(player: any): Wearer?
	for _, wearer in wearers do
		if wearer.Player == player then
			return wearer
		end
	end
	return nil
end

-- On in the lobby, off for a round they're playing (sitting a round out, they keep it on).
local function refreshCrown(player: any)
	local character = player.Character
	if not character then
		return
	end
	if player.Parent and wearerOf(player) and player:GetAttribute("PP_InRound") ~= true then
		if not character:FindFirstChild(CupCrown.Name) then
			CupCrown.Attach(character)
		end
	else
		CupCrown.Remove(character)
	end
end

local function crown(player: any, number: number)
	local wearer: Wearer = { Player = player, Cup = number, Connections = {} }
	table.insert(
		wearer.Connections,
		player.CharacterAdded:Connect(function(character: Model)
			character:WaitForChild("Head", 10)
			if player.Character == character then
				refreshCrown(player)
			end
		end)
	)
	table.insert(
		wearer.Connections,
		player:GetAttributeChangedSignal("PP_InRound"):Connect(function()
			refreshCrown(player)
		end)
	)
	table.insert(wearers, wearer)
	refreshCrown(player)
	-- Crowns and confetti over the new champion once they're back in the lobby, for everyone.
	task.delay(CROWN_EFFECT_AFTER, function()
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		if wearerOf(player) and head and head:IsA("BasePart") and character:FindFirstChild(CupCrown.Name) then
			Notifier.Effect("Crowns", head.Position + Vector3.new(0, 2, 0))
			Notifier.Effect("Confetti", head.Position + Vector3.new(0, 1, 0))
		end
	end)
end

local function uncrown(player: any)
	for index, wearer in wearers do
		if wearer.Player == player then
			for _, connection in wearer.Connections do
				connection:Disconnect()
			end
			table.remove(wearers, index)
			break
		end
	end
	CupCrown.Remove(player.Character)
end

-- The podium ---------------------------------------------------------------------------------------

-- The podium shows as the cup's last results card ends (CupController opens it then): wait for that.
local function waitForResultsCard()
	local deadline = os.clock() + 3
	while GameState.Get("Phase") ~= "Results" and os.clock() < deadline do
		task.wait(0.1)
	end
	deadline = os.clock() + Config.Session.ResultsTime + 3
	while GameState.Get("Phase") == "Results" and os.clock() < deadline do
		task.wait(0.1)
	end
end

-- The crate keys a finished cup gives each person in its standings (Services/CrateService: exactly
-- 3 / 2 / 1 on the podium).
local function cupKeys(standings: { PartyCup.Standing }): { [string]: number }
	local keys = {}
	for _, standing in standings do
		local player = members[standing.UserId]
		if standing.IsBot or not player or isBot(player) or not player.Parent then
			continue
		end
		local ok, count = pcall(CrateService.CupKeysFor, player, standing.Place)
		if ok and count > 0 then
			keys[tostring(standing.UserId)] = count
		end
	end
	return keys
end

-- Prizes, stats and medals for the people in a finished cup's standings who are still here.
local function payOut(standings: { PartyCup.Standing }, keys: { [string]: number })
	for _, standing in standings do
		local player = members[standing.UserId]
		if standing.IsBot or not player or isBot(player) or not player.Parent then
			continue
		end
		local profile = DataService.Get(player)
		if profile then
			local stats = profile.Data.Cups
			if type(stats) ~= "table" then
				stats = { Played = 0, Wins = 0, Podiums = 0 }
				profile.Data.Cups = stats
			end
			stats.Played = (stats.Played or 0) + 1
			if standing.Place <= #PartyCup.Prizes then
				stats.Podiums = (stats.Podiums or 0) + 1
			end
			if standing.Place == 1 then
				stats.Wins = (stats.Wins or 0) + 1
			end
			DataService.Changed(player)
		end
		local coins = PartyCup.PrizeFor(standing.Place)
		if coins > 0 then
			Economy.AddCoins(player, coins, "PartyCup")
		end
		local cupKeyCount = keys[tostring(standing.UserId)]
		if cupKeyCount then
			local ok, err = pcall(CrateService.GiveCupKeys, player, cupKeyCount, standing.Place)
			if not ok then
				Telemetry.Error("CupKeys", tostring(err))
			end
		end
		if standing.Place == 1 then
			local ok, err = pcall(MedalService.Award, player, "CupChampion")
			if not ok then
				Telemetry.Error("CupMedal", tostring(err))
			end
		end
	end
end

-- The crown goes from last cup's champions to this one's (nobody's, when a bot won).
local function passCrown(finished: PartyCup.Cup, standings: { PartyCup.Standing })
	local winners: { [any]: boolean } = {}
	for _, champion in PartyCup.Champions(standings) do
		local player = members[champion.UserId]
		if player and player.Parent and not isBot(player) then
			winners[player] = true
		end
	end
	for _, wearer in table.clone(wearers) do
		if not winners[wearer.Player] then
			uncrown(wearer.Player) -- (their podium says where it went)
		end
	end
	for player in winners do
		local wearer = wearerOf(player)
		if wearer then
			wearer.Cup = finished.Number -- won again: the crown stays on
		else
			crown(player, finished.Number)
		end
	end
end

local function finish()
	local finished = cup
	local standings = PartyCup.Standings(finished)
	cup = PartyCup.New(finished.Number + 1) -- the next cup counts from the next round on
	table.clear(away)
	finishing = true
	local keys = cupKeys(standings)
	publishFinal(finished, standings, keys)
	task.spawn(function()
		waitForResultsCard()
		local okPay, payErr = pcall(payOut, standings, keys)
		if not okPay then
			Telemetry.Error("CupPayout", tostring(payErr))
		end
		local okCrown, crownErr = pcall(passCrown, finished, standings)
		if not okCrown then
			Telemetry.Error("CupCrown", tostring(crownErr))
		end
		last = { Number = finished.Number, Podium = PartyCup.Rows(PartyCup.Podium(standings)) }
		local champion = standings[1]
		Telemetry.ServerEvent("CupFinished", {
			cup = finished.Number,
			champion = if champion then champion.Name else "",
			standings = #standings,
		})
		finishing = false
		publish()
	end)
end

-- A round finished (its rewards are paid): its places go into the cup.
local function onFinished(_definition, placed, _winningTeam)
	local results: { PartyCup.Result } = {}
	for _, item in placed do
		local who = item.Entry and item.Entry.Player
		if who and who.Parent then
			members[who.UserId] = who
			local back = away[who.UserId]
			if back and not isBot(who) then
				away[who.UserId] = nil -- back during this cup (PlayerAdded usually did this already)
				PartyCup.Restore(cup, back)
			end
			table.insert(results, {
				UserId = who.UserId,
				Name = who.DisplayName,
				IsBot = isBot(who),
				Place = item.Place,
			})
		end
	end
	if not PartyCup.AddRound(cup, results) then
		return -- nobody's people were in it
	end
	started = true
	endedAt = workspace:GetServerTimeNow()
	if PartyCup.IsOver(cup) then
		finish()
	else
		publish()
	end
end

function CupService.Init()
	RoundEvents.Finished:Connect(onFinished)
	Players.PlayerRemoving:Connect(function(player)
		local entry = PartyCup.Remove(cup, player.UserId)
		if entry then
			away[player.UserId] = entry -- back during this cup: their points too
		end
		members[player.UserId] = nil
		local wore = wearerOf(player) ~= nil
		if wore then
			uncrown(player) -- leaving takes the crown away
		end
		if entry or wore then
			publish()
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		local entry = away[player.UserId]
		if entry then
			away[player.UserId] = nil
			members[player.UserId] = player
			PartyCup.Restore(cup, entry)
			publish()
		end
	end)
	BotRegistry.Removed:Connect(function(bot)
		if PartyCup.Remove(cup, bot.UserId) then
			members[bot.UserId] = nil
			publish()
		end
	end)
end

function CupService.Start() end

return CupService
