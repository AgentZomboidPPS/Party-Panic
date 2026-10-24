-- Parties (owner: "stuff to work on right now is parties. The parties work in the way that if you
-- party with others for team games you are on the same team."): the server owns them. The rules
-- are Logic/PartyLogic's (invites, JOIN or NO, four at most, the leader handing over, a party of one
-- ending); this runs them with real players, checks every request, tells people what happened, and
-- marks each party's people for everyone to see:
--   * PP_Party, a player attribute: their party's id (none when on their own). RoundContext reads it
--     to deal teams with each party on one team (Logic/PartyTeams); clients read it for the 👥 on
--     name tags and the PARTY window (Controllers/PartyController).
--   * PP_PartySeat: their place in it, 1 for the leader (👑), then in the order they joined.
-- The "Party" remote, client to server: ("Invite", userId), ("Answer", userId, join: boolean),
-- ("Leave"). Server to client: ("Invited", fromUserId, fromName, secondsLeft) shows the invite card
-- (again, with the time it has left, when the lobby comes back after a round), ("InviteGone",
-- fromUserId) closes it, ("Sent", toUserId) and ("Done", toUserId) say an invite of yours is waiting
-- for an answer or isn't any more.
-- Every request is checked: its types, that the other one is a person here (bots are never in
-- parties: they aren't Players) and not you, the size cap, an invite waiting before a JOIN, and a
-- rate limit. Invites are sent in the lobby only, and their 20 s run in lobby time: under a rules
-- card or mid-round nobody can answer, so the clock stops and the card comes back afterwards.
-- Nothing is saved: a party lasts while its people are on this server (across rounds and PLAY
-- AGAIN replays), and sitting out keeps you in it (you just don't play those rounds).
--
-- The glow-up (owner: "Also make the party system insane. I want it to look super epic."): each
-- party has a look and a streak, kept here and shown by everyone's screens:
--   * Its look (Logic/PartyIdentity): a name from two fixed lists of friendly words ("Turbo
--     Pancakes"), a colour and an emblem from sets of 8, given at random when the party is made
--     (a colour and an emblem no other party here wears). The leader can roll a new name or pick
--     another colour or emblem: ("Reroll"), ("Color", index), ("Emblem", index) on the Party remote,
--     checked like every request (the rate limit) and then by PartyIdentity.Edit (the leader only,
--     real indices, a short cooldown). Nobody types a name, so there's nothing to filter.
--   * Its streak (Logic/PartyStreak): rounds in a row the whole party played, counted when a round
--     finishes (RoundEvents.Finished). In memory only, and no coins.
--   * Both go to every device as the GameState attribute "Parties": JSON of { [party id] = { Name,
--     Color, Emblem, Streak } } (the indices into PartyIdentity's sets).
--   * When someone joins, everyone in the party (the newcomer too) gets ("PartyUp", userId, name)
--     for the PARTY UP! moment (Controllers/SquadController), sent after their PP_Party is set; it
--     says what the "joined" toasts used to.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameState = require(Shared.GameState)
local PartyIdentity = require(Shared.Logic.PartyIdentity)
local PartyLogic = require(Shared.Logic.PartyLogic)
local PartyStreak = require(Shared.Logic.PartyStreak)
local Remotes = require(Shared.Remotes)

local BotRegistry = require(script.Parent.BotRegistry)
local Notifier = require(script.Parent.Notifier)
local RateLimiter = require(script.Parent.RateLimiter)
local RoundEvents = require(script.Parent.RoundEvents)

local PartyService = {}

local LOBBY = { Waiting = true, Intermission = true, Voting = true, Cleanup = true }
local TICK = 0.25 -- seconds between the invite clock's steps
local TOAST_TIME = 4
local LIMIT, WINDOW = 10, 5 -- requests per player: taps, not a stream

-- What the inviter is told when an invite can't go (PartyLogic.CanInvite); %s is the other one.
local REFUSED = {
	Full = `👥 Your party is full ({PartyLogic.MaxSize} at most).`,
	TheyreFull = "👥 %s's party is full.",
	Busy = "👥 %s has invites waiting - ask again in a moment.",
	Soon = "👥 Give %s a moment before asking again.",
}

local model = PartyLogic.new()
local remote: RemoteEvent? = nil
local limiter = RateLimiter.new(LIMIT, WINDOW)
local identities: { [number]: PartyIdentity.Identity } = {} -- party id -> its look
local streaks: { [number]: number } = {} -- party id -> rounds in a row the whole party played
local published = "" -- the "Parties" JSON everyone has
local rng = Random.new()

local function pick(count: number): number
	return rng:NextInteger(1, count)
end

-- Whether the lobby is up: between rounds, but not a PLAY AGAIN replay's Cleanup (it goes straight
-- into the replay's rules card).
local function lobbyUp(): boolean
	local phase = GameState.Get("Phase") or "Waiting"
	return LOBBY[phase] == true and not (phase == "Cleanup" and (GameState.Get("Replay") or "") ~= "")
end

-- The person here with this UserId: a Player (bots aren't), found by the number a client sent.
local function personHere(userId: any): Player?
	if type(userId) ~= "number" or userId ~= userId then
		return nil
	end
	for _, player in Players:GetPlayers() do
		if player.UserId == userId and not BotRegistry.IsBot(player) then
			return player
		end
	end
	return nil
end

local function send(player: any, ...: any)
	if remote and player and player.Parent then
		remote:FireClient(player, ...)
	end
end

-- Every party here now, each once.
local function partiesNow(): { PartyLogic.Party }
	local list, seen = {}, {}
	for _, player in Players:GetPlayers() do
		local party = model:PartyOf(player)
		if party and not seen[party] then
			seen[party] = true
			table.insert(list, party)
		end
	end
	return list
end

-- Tells everyone each party's look and streak (GameState "Parties"), when it changed.
local function publishLooks()
	local shown = {}
	for id, identity in identities do
		local entry: any = PartyIdentity.Show(identity)
		entry.Streak = streaks[id] or 0
		shown[tostring(id)] = entry
	end
	local json = if next(shown) then HttpService:JSONEncode(shown) else ""
	if json ~= published then
		published = json
		GameState.Set("Parties", json)
	end
end

-- A new party's look: one no other party here wears.
local function newLook(): PartyIdentity.Identity
	local taken = { Colors = {}, Emblems = {}, Names = {} }
	for _, identity in identities do
		taken.Colors[identity.Color] = true
		taken.Emblems[identity.Emblem] = true
		taken.Names[PartyIdentity.Name(identity)] = true
	end
	return PartyIdentity.New(pick, taken)
end

-- Marks everyone's party (PP_Party, PP_PartySeat) as the rules have it now.
local function publish()
	for _, player in Players:GetPlayers() do
		if BotRegistry.IsBot(player) then
			continue
		end
		local party = model:PartyOf(player)
		local id = if party then party.Id else nil
		local seat = if party then model:Seat(player) else nil
		if player:GetAttribute("PP_Party") ~= id then
			player:SetAttribute("PP_Party", id)
		end
		if player:GetAttribute("PP_PartySeat") ~= seat then
			player:SetAttribute("PP_PartySeat", seat)
		end
	end
end

-- Tells people what the rules just did, then redraws the parties.
local function handle()
	local events = model:Drain()
	if #events == 0 then
		return
	end
	-- The PARTY UP! moments go out once everyone's PP_Party says who's in the party now.
	local partyUps: { { To: Player, Who: Player } } = {}
	for _, event in events do
		local invite = event.Invite
		if event.Kind == "Invited" and invite then
			send(invite.To, "Invited", invite.From.UserId, invite.From.DisplayName, invite.Left)
			send(invite.From, "Sent", invite.To.UserId)
		elseif event.Kind == "InviteGone" and invite then
			send(invite.To, "InviteGone", invite.From.UserId)
			send(invite.From, "Done", invite.To.UserId)
			if event.Why == "Declined" then
				Notifier.Send(invite.From, `👥 {invite.To.DisplayName} said no thanks.`, "info", TOAST_TIME)
			elseif event.Why == "Expired" then
				Notifier.Send(
					invite.From,
					`👥 {invite.To.DisplayName} didn't answer your invite.`,
					"info",
					TOAST_TIME
				)
			end
		elseif event.Kind == "Joined" and event.Party and event.Member then
			local party = event.Party
			if not identities[party.Id] then
				identities[party.Id] = newLook() -- a new party
				streaks[party.Id] = 0
			end
			for _, member in party.Members do
				table.insert(partyUps, { To = member, Who = event.Member })
			end
		elseif event.Kind == "Left" and event.Party and event.Member then
			local who = event.Member.DisplayName
			for _, member in event.Party.Members do
				if member == event.Leader then
					Notifier.Send(member, `👑 {who} left the party - you lead it now.`, "info", TOAST_TIME)
				else
					Notifier.Send(member, `👥 {who} left the party.`, "info", TOAST_TIME)
				end
			end
		elseif event.Kind == "Dissolved" and event.Party then
			identities[event.Party.Id] = nil
			streaks[event.Party.Id] = nil
			if event.Member and event.Member.Parent then
				Notifier.Send(event.Member, "👥 Your party is over: everyone else left it.", "info", TOAST_TIME)
			end
		end
	end
	publish()
	publishLooks()
	for _, up in partyUps do
		-- (Someone who has moved on to another party since doesn't get this one's moment.)
		if model:PartyOf(up.To) == model:PartyOf(up.Who) then
			send(up.To, "PartyUp", up.Who.UserId, up.Who.DisplayName)
		end
	end
end

-- The leader changes the party's look: a new name, a colour or an emblem (PartyIdentity.Edit
-- checks who's asking, the value and the cooldown).
local function edit(player: Player, action: string, value: any)
	local party = model:PartyOf(player)
	local identity = party and identities[party.Id]
	if not identity then
		return
	end
	if PartyIdentity.Edit(identity, model:Seat(player), action, value, os.clock(), pick) then
		publishLooks()
	end
end

-- A round finished: every party's streak goes on (all of it played) or back to 0.
local function onRoundFinished(_definition: any, placed: { any })
	local played = {}
	for _, item in placed do
		local entry = item.Entry
		if entry and entry.Player then
			played[entry.Player] = true
		end
	end
	local parties = partiesNow()
	local after = PartyStreak.Round(streaks, parties, played)
	for _, party in parties do
		if identities[party.Id] then
			streaks[party.Id] = after[party.Id]
		end
	end
	publishLooks()
end

local function invite(player: Player, userId: any)
	local other = personHere(userId)
	if not other or other == player or not lobbyUp() then
		if type(userId) == "number" and userId == userId then
			send(player, "Done", userId) -- the button goes back
		end
		return
	end
	local reason = model:Invite(player, other)
	if reason == "Waiting" then
		send(player, "Sent", other.UserId) -- still waiting for an answer
	elseif reason then
		send(player, "Done", other.UserId)
		local text = REFUSED[reason]
		if text then
			Notifier.Send(player, string.format(text, other.DisplayName), "info", TOAST_TIME)
		end
	end
	handle()
end

local function answer(player: Player, userId: any, join: any)
	if type(join) ~= "boolean" then
		return
	end
	local other = personHere(userId)
	if not other then
		return -- they left: their invites went with them, and the card was told
	end
	if model:Answer(player, other, join) == "Full" then
		Notifier.Send(player, `👥 {other.DisplayName}'s party filled up - it's full now.`, "info", TOAST_TIME)
	end
	handle()
end

local function onRequest(player: Player, action: any, target: any, choice: any)
	if BotRegistry.IsBot(player) or not limiter:Check(player) then
		return
	end
	if action == "Invite" then
		invite(player, target)
	elseif action == "Answer" then
		answer(player, target, choice)
	elseif action == "Leave" then
		model:Leave(player)
		handle()
	elseif action == "Reroll" or action == "Color" or action == "Emblem" then
		edit(player, action, target)
	end
end

function PartyService.Init()
	local partyRemote = Remotes.Get("Party")
	remote = partyRemote
	partyRemote.OnServerEvent:Connect(onRequest)
	Players.PlayerRemoving:Connect(function(player)
		model:Forget(player)
		handle()
	end)
	RoundEvents.Finished:Connect(onRoundFinished)
end

-- The user ids of `player`'s party, leader first (nil when they're on their own): MergeService takes
-- parties along when it moves people to another server.
function PartyService.MembersOf(player: Player): { number }?
	local party = model:PartyOf(player)
	if not party then
		return nil
	end
	local ids = {}
	for _, member in party.Members do
		table.insert(ids, member.UserId)
	end
	return ids
end

-- `player` arrived from another server with `mateId`, their party there: they're in one again here.
function PartyService.Reunite(player: Player, mateId: number)
	local mate = personHere(mateId)
	if mate and mate ~= player and model:Reunite(mate, player) then
		handle()
	end
end

-- Each party's look and streak as everyone sees it (the harness checks read it).
function PartyService.Looks(): { [string]: any }
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, published)
	return if ok and type(decoded) == "table" then decoded else {}
end

-- The invite clock: it runs in lobby time only, and when the lobby comes back after a round, every
-- invite still waiting is shown again with the time it has left.
function PartyService.Start()
	local wasUp = lobbyUp()
	local last = os.clock()
	while true do
		task.wait(TICK)
		local now = os.clock()
		local up = lobbyUp()
		if up then
			model:Tick(now - last)
			if not wasUp then
				for _, waiting in model.Invites do
					send(waiting.To, "Invited", waiting.From.UserId, waiting.From.DisplayName, waiting.Left)
				end
			end
			handle()
		end
		wasUp = up
		last = now
	end
end

return PartyService
