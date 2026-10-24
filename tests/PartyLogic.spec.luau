-- Checks the party rules (src/shared/Logic/PartyLogic; owner: "stuff to work on right now is
-- parties."): invites and answers, the size cap, the leader handing over, a party of one ending,
-- joining a new party leaving the old one, people leaving the server, invites running out, and
-- nobody being asked again straight after a NO.
local TestKit = require("./TestKit")
local PartyLogic = require("../src/shared/Logic/PartyLogic")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

local function names(list: { any }): { string }
	local result = {}
	for _, who in list do
		table.insert(result, who.Name)
	end
	return result
end

local function kinds(events: { PartyLogic.Event }): { string }
	local result = {}
	for _, event in events do
		table.insert(result, if event.Why then `{event.Kind}:{event.Why}` else event.Kind)
	end
	return result
end

local function people(...: string): ...any
	local list = {}
	for _, name in { ... } do
		table.insert(list, { Name = name })
	end
	return table.unpack(list)
end

-- `from` invites `to`, who joins.
local function join(model: PartyLogic.Model, from: any, to: any)
	expectEqual(model:Invite(from, to), nil)
	expectEqual(model:Answer(to, from, true), "Joined")
end

test("PartyLogic: an invite and a JOIN make a party, the inviter leading", function()
	local model = PartyLogic.new()
	local ann, bo = people("Ann", "Bo")
	expectEqual(model:Invite(ann, bo), nil)
	expectEqual(kinds(model:Drain()), { "Invited" })
	expectEqual(model:PartyOf(ann), nil)
	expectEqual(#model:InvitesTo(bo), 1)
	expectEqual(model:Answer(bo, ann, true), "Joined")
	expectEqual(kinds(model:Drain()), { "InviteGone:Joined", "Joined" })
	local party = model:PartyOf(ann)
	expectTrue(party ~= nil and party == model:PartyOf(bo), "one party")
	expectEqual(names((party :: PartyLogic.Party).Members), { "Ann", "Bo" })
	expectEqual(model:Seat(ann), 1)
	expectEqual(model:Seat(bo), 2)
	expectEqual(#model:InvitesTo(bo), 0)
end)

test("PartyLogic: no answer without an invite waiting, and no inviting yourself", function()
	local model = PartyLogic.new()
	local ann, bo = people("Ann", "Bo")
	expectEqual(model:Answer(bo, ann, true), "NoInvite")
	expectEqual(model:PartyOf(bo), nil)
	expectEqual(model:Invite(ann, ann), "Self")
	expectEqual(model:Invite(ann, bo), nil)
	expectEqual(model:Invite(ann, bo), "Waiting")
	join(model, bo, people("Cy"))
	-- Ann's invite still waits; once Bo answers it, a second answer finds nothing.
	expectEqual(model:Answer(bo, ann, false), "Declined")
	expectEqual(model:Answer(bo, ann, true), "NoInvite")
end)

test("PartyLogic: four at most; a full party can't invite or be invited", function()
	local model = PartyLogic.new()
	local ann, bo, cy, di, ed = people("Ann", "Bo", "Cy", "Di", "Ed")
	join(model, ann, bo)
	join(model, bo, cy) -- anyone in the party can invite
	expectEqual(model:Invite(ann, di), nil)
	expectEqual(model:Invite(cy, ed), nil)
	expectEqual(model:Answer(di, ann, true), "Joined")
	expectEqual(#(model:PartyOf(ann) :: PartyLogic.Party).Members, 4)
	-- Full: Cy's invite to Ed went (it can't be answered any more).
	model:Drain()
	expectEqual(model:Answer(ed, cy, true), "NoInvite")
	expectEqual(model:Invite(ann, ed), "Full")
	expectEqual(model:Invite(ed, ann), "TheyreFull")
	expectEqual(model:PartyOf(ed), nil)
end)

test("PartyLogic: an invite to a party that filled up meanwhile can't be taken", function()
	local model = PartyLogic.new()
	local ann, bo, cy, di, ed = people("Ann", "Bo", "Cy", "Di", "Ed")
	join(model, ann, bo)
	join(model, ann, cy)
	-- Ann asks Di and Bo asks Ed: one place left for the two of them.
	expectEqual(model:Invite(ann, di), nil)
	expectEqual(model:Invite(bo, ed), nil)
	model:Drain()
	expectEqual(model:Answer(di, ann, true), "Joined")
	-- Di filled it, so Bo's invite to Ed went with it.
	expectEqual(kinds(model:Drain()), { "InviteGone:Joined", "Joined", "InviteGone:Full" })
	expectEqual(model:Answer(ed, bo, true), "NoInvite")
	expectEqual(model:PartyOf(ed), nil)
end)

test("PartyLogic: the leader leaves, the next one in leads; a party of one is over", function()
	local model = PartyLogic.new()
	local ann, bo, cy = people("Ann", "Bo", "Cy")
	join(model, ann, bo)
	join(model, ann, cy)
	model:Drain()
	expectTrue(model:Leave(ann), "Ann was in a party")
	local events = model:Drain()
	expectEqual(kinds(events), { "Left" })
	expectEqual(events[1].Leader, bo)
	expectEqual(model:Seat(bo), 1)
	expectEqual(model:Seat(cy), 2)
	expectEqual(model:PartyOf(ann), nil)
	expectTrue(model:Leave(cy), "Cy was in a party")
	events = model:Drain()
	expectEqual(kinds(events), { "Left", "Dissolved" })
	expectEqual(events[2].Member, bo)
	expectEqual(model:PartyOf(bo), nil)
	expectEqual(model:Leave(bo), false)
end)

test("PartyLogic: joining a new party leaves the old one", function()
	local model = PartyLogic.new()
	local ann, bo, cy, di = people("Ann", "Bo", "Cy", "Di")
	join(model, ann, bo)
	join(model, ann, cy)
	join(model, di, ann) -- Ann (leading) goes to Di's party
	expectEqual(names((model:PartyOf(di) :: PartyLogic.Party).Members), { "Di", "Ann" })
	expectEqual(names((model:PartyOf(bo) :: PartyLogic.Party).Members), { "Bo", "Cy" })
	expectEqual(model:Seat(bo), 1)
	join(model, di, bo) -- Bo leaves Cy alone: that party is over
	expectEqual(model:PartyOf(cy), nil)
	expectEqual(names((model:PartyOf(di) :: PartyLogic.Party).Members), { "Di", "Ann", "Bo" })
end)

test("PartyLogic: leaving the server takes you out, and every invite from or to you goes", function()
	local model = PartyLogic.new()
	local ann, bo, cy, di = people("Ann", "Bo", "Cy", "Di")
	join(model, ann, bo)
	expectEqual(model:Invite(bo, cy), nil)
	expectEqual(model:Invite(di, bo), nil)
	model:Drain()
	model:Forget(bo)
	expectEqual(kinds(model:Drain()), { "InviteGone:Gone", "InviteGone:Gone", "Left", "Dissolved" })
	expectEqual(model:PartyOf(ann), nil)
	expectEqual(#model:InvitesTo(cy), 0)
	expectEqual(model:Answer(cy, bo, true), "NoInvite")
end)

test("PartyLogic: invites run out in lobby time; NO or no answer means not again for a while", function()
	local model = PartyLogic.new()
	local ann, bo = people("Ann", "Bo")
	expectEqual(model:Invite(ann, bo), nil)
	model:Drain()
	model:Tick(PartyLogic.InviteSeconds - 1)
	expectEqual(#model:InvitesTo(bo), 1)
	model:Tick(1.5)
	expectEqual(kinds(model:Drain()), { "InviteGone:Expired" })
	expectEqual(model:Answer(bo, ann, true), "NoInvite")
	expectEqual(model:Invite(ann, bo), "Soon")
	model:Tick(PartyLogic.AskAgainAfter)
	expectEqual(model:Invite(ann, bo), nil)
	expectEqual(model:Answer(bo, ann, false), "Declined")
	expectEqual(model:Invite(ann, bo), "Soon")
	-- Bo can still ask Ann.
	expectEqual(model:Invite(bo, ann), nil)
end)

test("PartyLogic: one person has a few invites waiting at most", function()
	local model = PartyLogic.new()
	local target = people("Zed")
	for index = 1, PartyLogic.MaxWaiting do
		expectEqual(model:Invite({ Name = `Fan{index}` }, target), nil)
	end
	expectEqual(model:Invite({ Name = "OneMore" }, target), "Busy")
	expectEqual(#model:InvitesTo(target), PartyLogic.MaxWaiting)
end)

test("PartyLogic: crossing invites, one answered: the other one goes", function()
	local model = PartyLogic.new()
	local ann, bo = people("Ann", "Bo")
	expectEqual(model:Invite(ann, bo), nil)
	expectEqual(model:Invite(bo, ann), nil)
	model:Drain()
	expectEqual(model:Answer(ann, bo, true), "Joined")
	expectEqual(kinds(model:Drain()), { "InviteGone:Joined", "Joined", "InviteGone:Together" })
	expectEqual(names((model:PartyOf(ann) :: PartyLogic.Party).Members), { "Bo", "Ann" })
end)

test("PartyLogic: a party that moved servers together is put back without invites", function()
	local model = PartyLogic.new()
	local ann, bo, cy = people("Ann", "Bo", "Cy")
	expectTrue(model:Reunite(ann, bo), "Bo joins Ann")
	expectEqual(kinds(model:Drain()), { "Joined" })
	expectTrue(model:Reunite(bo, cy), "Cy joins Bo's party")
	expectEqual(names((model:PartyOf(ann) :: PartyLogic.Party).Members), { "Ann", "Bo", "Cy" })
	expectEqual(model:Reunite(ann, cy), false, "already in it")
	expectEqual(model:Reunite(ann, ann), false)
end)

return nil
