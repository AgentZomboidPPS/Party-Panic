--!strict
-- Parties (owner: "stuff to work on right now is parties. The parties work in the way that if you
-- party with others for team games you are on the same team."): who's in a party with whom on this
-- server, and the invites between them. Services/PartyService runs one of these with real players
-- (and Logic/PartyTeams keeps each party on one team); this is the rules, with no Roblox in it.
--
--   * Someone invites someone; the invite waits InviteSeconds of lobby time (its clock stops while
--     a round is on: nobody can answer under a rules card or mid-game) for a JOIN or a NO.
--   * JOIN puts them in the inviter's party (one is made, with the inviter leading, if the inviter
--     had none). Joining a new party leaves the old one.
--   * A party holds MaxSize people. When its leader leaves, the next one in leads; a party down to
--     one person is over (they're on their own again).
--   * Someone leaving the server is out of their party, and every invite from or to them is gone.
--   * A NO (or no answer) means not now: the same person can't be asked again for AskAgainAfter
--     seconds of lobby time, so nobody gets an invite card over and over.
-- What happened goes into a list of events (Drain) for the service to tell people and redraw the
-- parties.
-- Leaf module: no requires, no Roblox APIs, so it can be unit tested under Lune.

local PartyLogic = {}
PartyLogic.__index = PartyLogic

-- Party size cap. Twelve people play at most, and the team games deal two to four teams of two to
-- four; four friends is the usual group, and the most a team has room for in some rounds (fewer in
-- others: then the party is split as evenly as the teams allow, Logic/PartyTeams).
PartyLogic.MaxSize = 4
PartyLogic.InviteSeconds = 20 -- lobby time an invite waits for an answer
PartyLogic.AskAgainAfter = 12 -- lobby seconds before asking the same person again after a NO or no answer
PartyLogic.MaxWaiting = 3 -- invites one person can have waiting for them at once

export type Party = {
	Id: number,
	Members: { any }, -- in the order they joined: Members[1] leads
}

export type Invite = {
	From: any,
	To: any,
	Left: number, -- lobby seconds left to answer it
}

-- Why an invite went: "Joined", "Declined", "Expired", "Gone" (one of them left the server),
-- "Together" (they're in one party now anyway), "Full" (the inviter's party filled up).
export type Event = {
	Kind: string, -- "Invited" | "InviteGone" | "Joined" | "Left" | "Dissolved"
	Invite: Invite?, -- Invited, InviteGone
	Why: string?, -- InviteGone
	Party: Party?, -- Joined, Left, Dissolved
	Member: any?, -- Joined: who joined; Left: who left; Dissolved: who's on their own now
	Leader: any?, -- Left: who leads now, when it was the leader who left
}

export type Model = typeof(setmetatable(
	{} :: {
		ByMember: { [any]: Party },
		Invites: { Invite },
		Asked: { [any]: { [any]: number } }, -- from -> to -> lobby time they can be asked again
		Time: number, -- lobby seconds so far (Tick)
		NextId: number,
		Events: { Event },
	},
	PartyLogic
))

function PartyLogic.new(): Model
	return setmetatable({
		ByMember = {},
		Invites = {},
		Asked = {},
		Time = 0,
		NextId = 0,
		Events = {},
	}, PartyLogic)
end

-- The party someone is in (nil when they're on their own).
function PartyLogic.PartyOf(self: Model, member: any): Party?
	return self.ByMember[member]
end

-- Their place in their party (1 leads), or nil.
function PartyLogic.Seat(self: Model, member: any): number?
	local party = self.ByMember[member]
	return if party then table.find(party.Members, member) else nil
end

local function sizeOf(self: Model, member: any): number
	local party = self.ByMember[member]
	return if party then #party.Members else 1
end

-- The invite `from` sent `to`, if it's still waiting.
function PartyLogic.Pending(self: Model, from: any, to: any): Invite?
	for _, invite in self.Invites do
		if invite.From == from and invite.To == to then
			return invite
		end
	end
	return nil
end

-- The invites waiting for `to`, oldest first.
function PartyLogic.InvitesTo(self: Model, to: any): { Invite }
	local list = {}
	for _, invite in self.Invites do
		if invite.To == to then
			table.insert(list, invite)
		end
	end
	return list
end

local function emit(self: Model, event: Event)
	table.insert(self.Events, event)
end

-- Removes the invites `drop` says to, telling why.
local function dropInvites(self: Model, why: string, drop: (Invite) -> boolean)
	for index = #self.Invites, 1, -1 do
		local invite = self.Invites[index]
		if drop(invite) then
			table.remove(self.Invites, index)
			emit(self, { Kind = "InviteGone", Invite = invite, Why = why })
		end
	end
end

-- Whether `from` may invite `to` now: nil if so, else why not: "Self", "Together" (one party
-- already), "Full" (from's party is full), "TheyreFull" (to's party is full), "Waiting" (asked
-- already, no answer yet), "Busy" (to has MaxWaiting invites waiting), "Soon" (asked a moment ago).
function PartyLogic.CanInvite(self: Model, from: any, to: any): string?
	if from == to then
		return "Self"
	end
	local party = self.ByMember[from]
	if party and self.ByMember[to] == party then
		return "Together"
	elseif sizeOf(self, from) >= PartyLogic.MaxSize then
		return "Full"
	elseif sizeOf(self, to) >= PartyLogic.MaxSize then
		return "TheyreFull"
	elseif PartyLogic.Pending(self, from, to) then
		return "Waiting"
	elseif #PartyLogic.InvitesTo(self, to) >= PartyLogic.MaxWaiting then
		return "Busy"
	end
	local asked = self.Asked[from]
	if asked and (asked[to] or -math.huge) > self.Time then
		return "Soon"
	end
	return nil
end

-- Sends an invite. Returns nil if it went, else why not (CanInvite).
function PartyLogic.Invite(self: Model, from: any, to: any): string?
	local reason = PartyLogic.CanInvite(self, from, to)
	if reason then
		return reason
	end
	local invite: Invite = { From = from, To = to, Left = PartyLogic.InviteSeconds }
	table.insert(self.Invites, invite)
	emit(self, { Kind = "Invited", Invite = invite })
	return nil
end

local function remember(self: Model, invite: Invite)
	self.Asked[invite.From] = self.Asked[invite.From] or {}
	self.Asked[invite.From][invite.To] = self.Time + PartyLogic.AskAgainAfter
end

-- Takes someone out of their party: the next one in leads if they led, and a party left with one
-- person is over. Returns whether they were in one.
function PartyLogic.Leave(self: Model, member: any): boolean
	local party = self.ByMember[member]
	if not party then
		return false
	end
	local seat = table.find(party.Members, member)
	if seat then
		table.remove(party.Members, seat)
	end
	self.ByMember[member] = nil
	local leader = if seat == 1 then party.Members[1] else nil
	emit(self, { Kind = "Left", Party = party, Member = member, Leader = leader })
	if #party.Members <= 1 then
		local last = party.Members[1]
		if last ~= nil then
			self.ByMember[last] = nil
		end
		party.Members = {}
		emit(self, { Kind = "Dissolved", Party = party, Member = last })
	end
	return true
end

-- `to` answers `from`'s invite. Returns "Joined", "Declined", "NoInvite" (none waiting: it ran out,
-- was answered, or never was) or "Full" (the inviter's party filled up meanwhile).
function PartyLogic.Answer(self: Model, to: any, from: any, join: boolean): string
	local invite = PartyLogic.Pending(self, from, to)
	if not invite then
		return "NoInvite"
	end
	table.remove(self.Invites, table.find(self.Invites, invite) :: number)
	if not join then
		remember(self, invite)
		emit(self, { Kind = "InviteGone", Invite = invite, Why = "Declined" })
		return "Declined"
	end
	local party = self.ByMember[from]
	if party and self.ByMember[to] == party then
		emit(self, { Kind = "InviteGone", Invite = invite, Why = "Together" })
		return "Joined"
	elseif sizeOf(self, from) >= PartyLogic.MaxSize then
		emit(self, { Kind = "InviteGone", Invite = invite, Why = "Full" })
		return "Full"
	end
	emit(self, { Kind = "InviteGone", Invite = invite, Why = "Joined" })
	PartyLogic.Leave(self, to)
	local joined: Party = party or { Id = 0, Members = { from } }
	if not party then
		self.NextId += 1
		joined.Id = self.NextId
		self.ByMember[from] = joined
	end
	table.insert(joined.Members, to)
	self.ByMember[to] = joined
	emit(self, { Kind = "Joined", Party = joined, Member = to })
	-- Invites between people now in one party mean nothing any more, and a party that's full can't
	-- take anyone its people asked.
	local full = #joined.Members >= PartyLogic.MaxSize
	dropInvites(self, "Together", function(other: Invite): boolean
		return self.ByMember[other.From] == joined and self.ByMember[other.To] == joined
	end)
	dropInvites(self, "Full", function(other: Invite): boolean
		return full and self.ByMember[other.From] == joined
	end)
	return "Joined"
end

-- Someone left the server: out of their party, and every invite from or to them is gone.
function PartyLogic.Forget(self: Model, member: any)
	dropInvites(self, "Gone", function(invite: Invite): boolean
		return invite.From == member or invite.To == member
	end)
	PartyLogic.Leave(self, member)
	self.Asked[member] = nil
	for _, asked in self.Asked do
		asked[member] = nil
	end
end

-- Lobby time passing (the service doesn't tick it during a round): invites run out.
function PartyLogic.Tick(self: Model, seconds: number)
	self.Time += seconds
	for index = #self.Invites, 1, -1 do
		local invite = self.Invites[index]
		invite.Left -= seconds
		if invite.Left <= 0 then
			table.remove(self.Invites, index)
			remember(self, invite)
			emit(self, { Kind = "InviteGone", Invite = invite, Why = "Expired" })
		end
	end
end

-- What happened since the last call, in order.
function PartyLogic.Drain(self: Model): { Event }
	local events = self.Events
	self.Events = {}
	return events
end

return PartyLogic
