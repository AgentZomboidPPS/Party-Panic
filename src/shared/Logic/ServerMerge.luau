--!strict
-- Merging quiet servers (owner: "Is there a way to merge severs automatically that are getting
-- low?"): the rules Services/MergeService plays by. Leaf module: no requires, no Roblox APIs.
--
-- Every server lists itself (its real players, not bots, and its place version) where every other
-- server can read it. A server that has had ServerMerge's Low real players or fewer for a few
-- lobbies in a row moves them, together, to the fullest server on the same version that has room
-- for all of them with a seat to spare. People only ever move to a bigger server (or one as big
-- with the larger id), so two quiet servers never swap their people.

local ServerMerge = {}

export type Entry = {
	JobId: string,
	Count: number, -- real players there
	Version: number, -- its place version (people never move to an older or newer game)
}

-- Whether a server with `count` real players is quiet enough to move them (an empty one has nobody
-- to move).
function ServerMerge.Quiet(count: number, low: number): boolean
	return count >= 1 and count <= low
end

-- The lobbies in a row this server has been quiet, after one more lobby with `count` real players.
function ServerMerge.Streak(streak: number, count: number, low: number): number
	return if ServerMerge.Quiet(count, low) then streak + 1 else 0
end

-- Where `movers` people from server `me` should go: the fullest listed server on `me`'s version
-- with room for them all and one seat to spare, bigger than `me` (or as big, with the larger id).
-- nil when there's none.
function ServerMerge.PickTarget(entries: { Entry }, me: Entry, movers: number, maxPlayers: number): Entry?
	local best: Entry? = nil
	for _, entry in entries do
		local roomy = entry.Count + movers <= maxPlayers - 1
		local bigger = entry.Count > me.Count or (entry.Count == me.Count and entry.JobId > me.JobId)
		if entry.JobId ~= me.JobId and entry.Version == me.Version and roomy and bigger then
			local current = best
			if
				current == nil
				or entry.Count > current.Count
				or (entry.Count == current.Count and entry.JobId > current.JobId)
			then
				best = entry
			end
		end
	end
	return best
end

-- The parties among the people moving, as lists of their user ids (leader first): each party's
-- people who are moving, when at least two of them are. `partyOf` gives a mover's party's members in
-- seat order (nil if they're on their own).
function ServerMerge.Parties(movers: { number }, partyOf: (number) -> { number }?): { { number } }
	local moving: { [number]: boolean } = {}
	for _, userId in movers do
		moving[userId] = true
	end
	local seen: { [number]: boolean } = {}
	local parties = {}
	for _, userId in movers do
		if not seen[userId] then
			local members = partyOf(userId)
			if members then
				local together = {}
				for _, member in members do
					seen[member] = true
					if moving[member] then
						table.insert(together, member)
					end
				end
				if #together >= 2 then
					table.insert(parties, together)
				end
			end
		end
	end
	return parties
end

-- Who `userId` should join on arrival: the first of their party's people (leader first) who's
-- already here (`here`), or nil if none is yet (they'll be joined by the next to arrive).
function ServerMerge.MateHere(parties: { { number } }, userId: number, here: (number) -> boolean): number?
	for _, members in parties do
		if table.find(members, userId) then
			for _, member in members do
				if member ~= userId and here(member) then
					return member
				end
			end
		end
	end
	return nil
end

return ServerMerge
