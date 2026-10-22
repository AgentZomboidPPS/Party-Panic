-- Friends (owner, asked what keeps players coming back, then: "Can you work on all of that? this
-- wont mess with what the other workers are working on right?"; the idea as given: "Friends: an
-- invite button, a coin bonus for playing with friends, beat-a-friend moments"):
--   * A round played with a Roblox friend pays +1 coin, on a line of its own on the results card
--     ("Played with a friend"; Services/Boosts), and gives the FriendsParty medal (MedalService).
--   * Beat-a-friend moments: after a round, everyone who placed above a friend gets "🎉 You beat
--     Ann!" (or "You beat 2 friends!"), and a friend they beat gets "Bo beat you - get them next
--     round!": one toast each, the happy one first (Logic/FriendLogic).
--   * A friend arriving: everyone they're friends with here gets "⭐ Ann is here! Play together for
--     +1 💰 a round", and the newcomer hears who's here once their screen has loaded.
-- The invite button is the client's (Controllers/InviteController).
--
-- Toasts wait for the lobby: the results card is a window and draws over them, and a round is no
-- time to read about friends. Held ones go out a second into Cleanup, when the card has closed; a
-- player's held "is here" toasts make one.
--
-- Who's friends with whom: Roblox's Player:IsFriendsWithAsync yields and can fail, so each pair of
-- people is asked about once, when the second of the two joins (the newcomer asks; if that call
-- fails, the other one does), and the answer is kept while both are here. The reward path only
-- reads what's kept. Bots are never anyone's friend, and never get a bonus, a medal or a toast.
-- Who played the round: a boost is only told about its own player, and the boosts run before
-- RoundEvents.Finished, so the bonus looks for friends among the players RoundContext has marked
-- PP_InRound (it clears that at the round's cleanup, after the rewards). The medal and the beat
-- moments go by the round's places (RoundEvents.Finished).
--
-- Test servers have no friendships: on a harness run (workspace PP_Harness) a check marks two
-- stand-ins as friends with FriendsService.SetFriendsForTest (tools/checks/scenarios/Friends.luau).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local FriendLogic = require(Shared.Logic.FriendLogic)
local GameState = require(Shared.GameState)

local BotRegistry = require(script.Parent.BotRegistry)
local Boosts = require(script.Parent.Boosts)
local MedalService = require(script.Parent.MedalService)
local Notifier = require(script.Parent.Notifier)
local RoundEvents = require(script.Parent.RoundEvents)

local FriendsService = {}

-- Phases a toast waits out: the rules card, the round and its results (the card covers toasts).
local HOLD_IN = { Preparing = true, InRound = true, Results = true }
local AFTER_RESULTS = 1 -- seconds into Cleanup: the results card has closed on every screen
local WELCOME_AFTER = 8 -- seconds after joining: the newcomer's screen is up to show "who's here"
local ASK_TRIES, ASK_RETRY = 2, 4 -- Roblox's friends check: tries per pair, and seconds between them
local TOAST_TIME = 5

type Held = { Moment: { Text: string, Kind: string }?, Here: { any } } -- Here: the friends who arrived

-- Every pair of people here that Roblox has been asked about (FriendLogic.PairKey of their
-- UserIds): who they are, and the answer (nil while it's being asked).
local pairsHere: { [string]: { A: number, B: number, Friends: boolean? } } = {}
local joinedAt: { [any]: number } = {} -- player -> os.clock() when they arrived
local held: { [any]: Held } = {} -- player -> toasts waiting for the lobby
local flushQueued = false

-- A real player, with a Roblox account to ask about (not a check's stand-in, which is a table).
local function isReal(player: any): boolean
	return typeof(player) == "Instance"
end

-- Someone who can have friends here: a player (or a check's stand-in for one), never a bot.
local function isPerson(player: any): boolean
	return player ~= nil and not BotRegistry.IsBot(player) and type(player.UserId) == "number" and player.UserId > 0
end

-- Whether Roblox has said these two are friends (it's only asked when they join, never here).
function FriendsService.AreFriends(a: Player, b: Player): boolean
	if a == nil or b == nil or a == b then
		return false
	end
	local entry = pairsHere[FriendLogic.PairKey(a.UserId, b.UserId)]
	return entry ~= nil and entry.Friends == true
end

local function holding(): boolean
	return HOLD_IN[GameState.Get("Phase") or "Waiting"] == true
end

local function heldFor(player: any): Held
	local entry = held[player]
	if not entry then
		entry = { Moment = nil, Here = {} }
		held[player] = entry
	end
	return entry
end

-- A beat-a-friend moment: now, or once everyone's back in the lobby.
local function sendMoment(player: any, text: string, kind: string)
	if holding() then
		heldFor(player).Moment = { Text = text, Kind = kind }
	elseif player.Parent then
		Notifier.Send(player, text, kind, TOAST_TIME)
	end
end

-- The names of `player`'s friends in `friends` who are still here.
local function namesHere(player: any, friends: { any }): { string }
	local names = {}
	for _, friend in friends do
		if friend.Parent and FriendsService.AreFriends(player, friend) then
			table.insert(names, friend.DisplayName)
		end
	end
	return names
end

-- "⭐ Ann is here!" about `friends`: now, or once everyone's back in the lobby (one toast with any
-- others held for them; a friend who has left by then isn't in it).
local function sendHere(player: any, friends: { any })
	if holding() then
		local list = heldFor(player).Here
		for _, friend in friends do
			if not table.find(list, friend) then
				table.insert(list, friend)
			end
		end
		return
	end
	local names = namesHere(player, friends)
	if #names > 0 and player.Parent then
		Notifier.Send(player, FriendLogic.HereText(names), "info", TOAST_TIME)
	end
end

-- The toasts held through a round, once the lobby is back (the moment first: it's about the round).
local function flush()
	flushQueued = false
	if holding() then
		return -- a new round already: they wait for its end
	end
	for player, entry in held do
		held[player] = nil
		if not player.Parent then
			continue
		end
		if entry.Moment then
			Notifier.Send(player, entry.Moment.Text, entry.Moment.Kind, TOAST_TIME)
		end
		local names = namesHere(player, entry.Here)
		if #names > 0 then
			Notifier.Send(player, FriendLogic.HereText(names), "info", TOAST_TIME)
		end
	end
end

local function onPhase(phase: string?)
	if HOLD_IN[phase or "Waiting"] or flushQueued or next(held) == nil then
		return
	end
	flushQueued = true
	task.delay(if phase == "Cleanup" then AFTER_RESULTS else 0, flush)
end

-- Asks Roblox whether two players are friends: the newcomer asks, and if that call fails the other
-- one does. nil when neither got an answer (or one of them left meanwhile).
local function ask(newcomer: Player, other: Player): boolean?
	for try = 1, ASK_TRIES do
		for _, side in { { newcomer, other }, { other, newcomer } } do
			local ok, friends = pcall(function()
				return side[1]:IsFriendsWithAsync(side[2].UserId)
			end)
			if ok then
				return friends == true
			end
		end
		if try < ASK_TRIES then
			task.wait(ASK_RETRY)
			if not (newcomer.Parent and other.Parent) then
				return nil
			end
		end
	end
	return nil
end

-- A newcomer: asks about them and each person already here, tells each friend here that they've
-- arrived, then tells them who's here.
local function onJoin(player: Player)
	if joinedAt[player] or not isPerson(player) then
		return
	end
	joinedAt[player] = os.clock()
	if not isReal(player) then
		return -- a check's stand-in: no Roblox account to ask about (SetFriendsForTest)
	end
	task.spawn(function()
		local found: { Player } = {}
		for _, other in Players:GetPlayers() do
			if not player.Parent then
				return -- gone again
			elseif other == player or not isReal(other) or not isPerson(other) then
				continue
			end
			local key = FriendLogic.PairKey(player.UserId, other.UserId)
			if pairsHere[key] then
				continue -- already asked (they arrived together, and the other's check got here first)
			end
			local entry: { A: number, B: number, Friends: boolean? } =
				{ A = player.UserId, B = other.UserId, Friends = nil }
			pairsHere[key] = entry
			local friends = ask(player, other)
			if pairsHere[key] ~= entry then
				continue -- one of them left meanwhile (and may be back, asking again)
			elseif friends == nil then
				pairsHere[key] = nil -- no answer: asked again if one of them comes back
				continue
			end
			entry.Friends = friends
			if friends then
				table.insert(found, other)
				sendHere(other, { player })
			end
		end
		if #found == 0 then
			return
		end
		local remaining = WELCOME_AFTER - (os.clock() - (joinedAt[player] or 0))
		if remaining > 0 then
			task.wait(remaining)
		end
		if player.Parent then
			sendHere(player, found)
		end
	end)
end

local function forget(player: Player)
	joinedAt[player] = nil
	held[player] = nil
	local id = player.UserId
	for key, entry in pairsHere do
		if entry.A == id or entry.B == id then
			pairsHere[key] = nil
		end
	end
end

-- The bonus (Services/Boosts): +1 coin when a friend played the round too. Both are people in it:
-- RoundContext marks the round's players PP_InRound until its cleanup, which comes after rewards.
local function friendBoost(player: Player, _round: Boosts.Round): (number, string?)
	if not isPerson(player) or player:GetAttribute("PP_InRound") ~= true then
		return 0, nil
	end
	for _, other in Players:GetPlayers() do
		if
			other ~= player
			and other:GetAttribute("PP_InRound") == true
			and FriendsService.AreFriends(player, other)
		then
			return FriendLogic.Bonus, FriendLogic.BonusLabel
		end
	end
	return 0, nil
end

-- After a round's rewards: the beat-a-friend moments (held until the results card has closed), and
-- the FriendsParty medal for everyone who played it with a friend (after them: an award may wait on
-- Roblox).
local function onRoundFinished(_definition, placed: { any })
	local finishers: { FriendLogic.Finisher } = {}
	local byId: { [number]: any } = {}
	for _, item in placed do
		local player = item.Entry and item.Entry.Player
		if isPerson(player) and player.Parent then
			table.insert(finishers, { Id = player.UserId, Place = item.Place })
			byId[player.UserId] = player
		end
	end
	if #finishers < 2 then
		return
	end
	local function areFriends(a: number, b: number): boolean
		return FriendsService.AreFriends(byId[a], byId[b])
	end
	local function names(ids: { number }): { string }
		local list = {}
		for _, id in ids do
			table.insert(list, byId[id].DisplayName)
		end
		return list
	end
	for id, moments in FriendLogic.Moments(finishers, areFriends) do
		local text, kind = FriendLogic.MomentToast(names(moments.Beat), names(moments.BeatenBy))
		if text and kind then
			sendMoment(byId[id], text, kind)
		end
	end
	for id in FriendLogic.WithFriends(finishers, areFriends) do
		local ok, err = pcall(MedalService.Award, byId[id], "FriendsParty")
		if not ok then
			warn(`[FriendsService] FriendsParty medal: {err}`)
		end
	end
end

-- Test seam: marks two players as friends, as if Roblox had said so when the second one joined
-- (the bonus, the medal, the moments and the "is here" toasts follow). Honoured on a harness run
-- only (workspace PP_Harness): test servers have no friendships.
function FriendsService.SetFriendsForTest(a: Player, b: Player)
	if workspace:GetAttribute("PP_Harness") ~= true or not isPerson(a) or not isPerson(b) or a == b then
		return
	end
	pairsHere[FriendLogic.PairKey(a.UserId, b.UserId)] = { A = a.UserId, B = b.UserId, Friends = true }
	sendHere(a, { b })
	sendHere(b, { a })
end

function FriendsService.Init()
	Boosts.Register("Friend", friendBoost)
	RoundEvents.Finished:Connect(onRoundFinished)
	GameState.Changed("Phase", onPhase)
	Players.PlayerAdded:Connect(onJoin)
	Players.PlayerRemoving:Connect(forget)
end

function FriendsService.Start()
	for _, player in Players:GetPlayers() do
		onJoin(player) -- anyone who was here before the server's scripts were (Studio)
	end
end

return FriendsService
