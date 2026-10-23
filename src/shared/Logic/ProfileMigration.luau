--!strict
-- What loading a saved profile changes, and the mark every save leaves, so the move to the low coin
-- scale (owner: "Also lets balance the shop down. I want low currency not high.") happens exactly
-- once for every player and nothing is ever lost. DataService runs Load on every profile it loads
-- from the DataStore (never on a failed load: that player gets a fresh profile that is never saved)
-- and Stamp just before every save. Both only change the profile in memory; the server writes it
-- back with its usual locked UpdateAsync save, so a load that's never saved changes nothing.
--
-- The rule, in plain words:
--   * A profile not yet on the low scale (no EconomyVersion 2) gets its coins divided by 10,
--     rounded up (1234 -> 124, 5 -> 1, 0 -> 0), and is marked EconomyVersion 2 in the same save.
--     Never twice: servers still running the old code keep fields they don't know, so the mark stays.
--     Owned items, equipped items, XP and levels are never touched.
--   * Servers still running the old code (until the owner restarts them after a publish) pay
--     coins on the old scale. They write Version 1 back when they save; every save from this code
--     writes Version 2 and the coin balance it saved (CoinStamp). So a profile marked
--     EconomyVersion 2 that comes back with Version 1 had a session on an old server: what its
--     coins went up (or down) there is divided by 10 too, once (the next save stamps again).
--   * Counts worked out from other saved stats (GamesTried) are redone on every load.
--   * Either change leaves a note for the player in the profile (Meta.CoinNotice). DataService
--     clears it only once the message was sent, so leaving before it shows never loses it.
-- The career milestones count from the update on, except podiums: every win saved so far was one.
--
-- The GOLD PASS (owner: "Also we do need a paid battle pass too. I like the current free one. But the
-- paid one should also be insane."), which took over from the old VIP pass:
--   * The VIP pass's flag (IsVip) was never saved: it lived on the server's record of the session,
--     was false for everyone (the VIP pass was never on sale) and was asked of Roblox on each join.
--     The GOLD PASS is kept in the profile (GoldPass), so a player who owns it keeps it when Roblox's
--     ownership check fails; Services/GoldPassService confirms it on every join.
--   * Loading never grants the pass: only `Owned = true` (written when Roblox said they own it)
--     counts, a broken GoldPass field goes back to its default (not owned), and a stray IsVip in a
--     save means nothing and is dropped. A save from before the pass gets the default.
--   * CoinsTo, the last level whose gold coins were paid, is a whole level, at least 1. It only goes
--     up (Services/GoldPassService), so no level's gold coins are paid twice.
--   * Servers still running older code keep the field as they found it (they keep fields they don't
--     know), so a game there loses nothing; the levels reached there are paid on the next join.
-- Leaf module: no requires, no Roblox APIs.

local ProfileMigration = {}

ProfileMigration.EconomyVersion = 2 -- coins on the low scale
ProfileMigration.SchemaVersion = 2 -- the Version this code saves (Logic/ProfileTemplate's)
ProfileMigration.LowScaleSchema = 2 -- the first Version saved by code on the low scale
ProfileMigration.CoinScale = 10 -- old coins per new coin

-- The note for the player about their coins, kept in Meta.CoinNotice until they've been told.
export type CoinNotice = {
	Kind: string, -- "Converted" (Before -> After) | "OldServer" (After)
	Before: number?,
	After: number,
}

export type Report = {
	CoinsBefore: number?, -- set when this load moved the balance to the low scale
	CoinsAfter: number?,
	OldServerChange: number?, -- set when it converted a session on an old server: its coins there
	OldServerAfter: number?, -- ... and the balance after converting them
}

-- A saved coin count as a whole number, never below 0 (missing or broken values count as 0).
local function whole(value: any): number
	local number = tonumber(value)
	if number == nil or number ~= number or number == math.huge or number == -math.huge then
		return 0
	end
	return math.max(0, math.floor(number))
end

-- Old-scale coins on the low scale: a tenth, rounded in the player's favour (up; a loss rounds
-- toward zero).
function ProfileMigration.ToLowScale(oldCoins: number): number
	return math.ceil(oldCoins / ProfileMigration.CoinScale)
end

-- The one-time changes, before anything else touches the profile.
function ProfileMigration.Run(data: { [string]: any }): Report
	local report: Report = {}
	local stats = if type(data.Stats) == "table" then data.Stats else nil

	if (tonumber(data.EconomyVersion) or 1) < ProfileMigration.EconomyVersion then
		local before = whole(data.Coins)
		local after = ProfileMigration.ToLowScale(before)
		data.Coins = after
		data.EconomyVersion = ProfileMigration.EconomyVersion
		data.CoinStamp = nil -- (an old server never writes one; nothing to compare with)
		report.CoinsBefore, report.CoinsAfter = before, after
		if stats then
			-- Podiums are counted from now on; every win saved so far was one.
			stats.Podiums = math.max(whole(stats.Podiums), whole(stats.Wins))
		end
	elseif (tonumber(data.Version) or 1) < ProfileMigration.LowScaleSchema and data.CoinStamp ~= nil then
		-- On the low scale already, but last saved by a server on the old code.
		local stamp = whole(data.CoinStamp)
		local change = whole(data.Coins) - stamp
		if change ~= 0 then
			local after = math.max(0, stamp + ProfileMigration.ToLowScale(change))
			data.Coins = after
			report.OldServerChange, report.OldServerAfter = change, after
		end
	end
	return report
end

-- How many of the games a ModePlays table has played (only games in `known`, when given).
function ProfileMigration.GamesTried(modePlays: any, known: { [string]: boolean }?): number
	local count = 0
	if type(modePlays) ~= "table" then
		return count
	end
	for id, plays in modePlays do
		if (tonumber(plays) or 0) > 0 and (known == nil or known[id] == true) then
			count += 1
		end
	end
	return count
end

-- Everything loading a saved profile does, in this order:
--   1. the one-time changes (Run). First: filling in defaults would give an old save today's
--      EconomyVersion, and its coins would never move to the low scale;
--   2. every field `template` has and the save doesn't gets its default (`fill`: TableUtil.Reconcile,
--      which never overwrites a saved value);
--   3. the counts worked out from other stats, and the GOLD PASS field made safe (GoldPass);
--   4. Version: this code's, never lowered (a newer server may have saved it).
function ProfileMigration.Load(
	data: { [string]: any },
	template: { [string]: any },
	fill: (target: { [any]: any }, template: { [any]: any }) -> any,
	knownGames: { [string]: boolean }?
): Report
	local report = ProfileMigration.Run(data)
	fill(data, template)
	if type(data.Stats) == "table" then
		data.Stats.GamesTried = ProfileMigration.GamesTried(data.Stats.ModePlays, knownGames)
	end
	ProfileMigration.GoldPass(data)
	ProfileMigration.Crates(data)
	if type(data.Meta) == "table" then
		ProfileMigration.NoteCoins(data.Meta, report)
	end
	data.Version = math.max(tonumber(data.Version) or 1, ProfileMigration.SchemaVersion)
	return report
end

-- Makes a loaded profile's GOLD PASS field safe to use (see the top): known fields fixed in place
-- (anything newer code keeps in it stays), never granting the pass, and the old IsVip dropped.
function ProfileMigration.GoldPass(data: { [string]: any })
	data.IsVip = nil
	local saved = data.GoldPass
	if type(saved) ~= "table" then
		saved = {}
		data.GoldPass = saved
	end
	saved.Owned = saved.Owned == true
	local since = tonumber(saved.Since)
	saved.Since = if since and since == since and since > 0 and since < math.huge then math.floor(since) else 0
	local coinsTo = tonumber(saved.CoinsTo)
	saved.CoinsTo = if coinsTo
			and coinsTo == coinsTo
			and coinsTo >= 1
			and coinsTo < math.huge
		then math.floor(coinsTo)
		else 1
end

-- Makes a loaded profile's crate-season fields safe to use (owner: "seasonal crates ... Keys to open
-- the crate ... we also need to be able to sell keys for Robux"): keys and crates are whole numbers,
-- never below 0 (a broken value is 0, never more); each season's progress is a table of numbers and
-- found items; the flags have their types; the receipts list holds strings only and keeps the
-- latest 60. Fields newer code keeps in them stay.
local MAX_RECEIPTS = 60
ProfileMigration.MaxReceipts = MAX_RECEIPTS
function ProfileMigration.Crates(data: { [string]: any })
	data.Keys = whole(data.Keys)
	if type(data.Crates) ~= "table" then
		data.Crates = { Season = "", Count = 0 }
	end
	data.Crates.Season = if type(data.Crates.Season) == "string" then data.Crates.Season else ""
	data.Crates.Count = whole(data.Crates.Count)
	if type(data.Seasons) ~= "table" then
		data.Seasons = {}
	end
	for id, progress in data.Seasons do
		if type(id) ~= "string" or type(progress) ~= "table" then
			data.Seasons[id] = nil
			continue
		end
		progress.Earned = whole(progress.Earned)
		progress.Opened = whole(progress.Opened)
		progress.Coins = whole(progress.Coins)
		progress.Meter = whole(progress.Meter)
		progress.Week = whole(progress.Week)
		progress.WeekOpened = whole(progress.WeekOpened)
		if type(progress.Found) ~= "table" then
			progress.Found = {}
		end
	end
	if type(data.CrateFlags) ~= "table" then
		data.CrateFlags = {}
	end
	local flags = data.CrateFlags
	flags.StarterKeys = flags.StarterKeys == true
	flags.StarterPack = flags.StarterPack == true
	flags.Welcome = if type(flags.Welcome) == "string" then flags.Welcome else ""
	flags.DailyKeyDay = whole(flags.DailyKeyDay)
	flags.Bought = whole(flags.Bought)
	local receipts = {}
	if type(data.Receipts) == "table" then
		for _, id in data.Receipts do
			if type(id) == "string" then
				table.insert(receipts, id)
			end
		end
	end
	while #receipts > MAX_RECEIPTS do
		table.remove(receipts, 1)
	end
	data.Receipts = receipts
	if type(data.Equipped) == "table" then
		for _, slot in { "Pet", "Aura" } do
			if type(data.Equipped[slot]) ~= "string" then
				data.Equipped[slot] = ""
			end
		end
	end
end

-- Leaves the note about what this load did to the coins in `meta.CoinNotice` (kept until the
-- player has been told). The one-time conversion wins over a later old-server change: that one is
-- small, and "your 1234 coins are now 124" is the message that matters.
function ProfileMigration.NoteCoins(meta: { [string]: any }, report: Report)
	local pending = meta.CoinNotice
	local converted = type(pending) == "table" and pending.Kind == "Converted"
	if report.CoinsBefore and report.CoinsBefore > 0 then
		local notice: CoinNotice = { Kind = "Converted", Before = report.CoinsBefore, After = report.CoinsAfter or 0 }
		meta.CoinNotice = notice
	elseif report.OldServerChange and not converted then
		local notice: CoinNotice = { Kind = "OldServer", After = report.OldServerAfter or 0 }
		meta.CoinNotice = notice
	end
end

-- Just before every save: the balance this save writes, so a later load can tell what a session
-- on a server still running the old code changed (Run).
function ProfileMigration.Stamp(data: { [string]: any })
	data.CoinStamp = data.Coins
end

return ProfileMigration
