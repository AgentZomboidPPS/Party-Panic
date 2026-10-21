--!strict
-- One-time changes to saved profiles, run when a profile loads (before DataService fills in the
-- template's new fields).
--
-- Economy v2 (owner: "Also lets balance the shop down. I want low currency not high."): coins moved
-- to a low scale, so a saved balance is divided by 10 and rounded up, exactly once. Owned items are
-- never touched. The step is keyed on its own marker, EconomyVersion, not on Version: a server
-- still running older code writes its own (lower) Version back when it saves, and that must never
-- cause a second rescale.
-- Also on every load: stats that are worked out from other saved stats (GamesTried).
-- Leaf module: no requires, no Roblox APIs.

local ProfileMigration = {}

ProfileMigration.EconomyVersion = 2
ProfileMigration.CoinScale = 10 -- old coins per new coin

export type Report = {
	CoinsBefore: number?, -- set when this load moved the balance to the low scale
	CoinsAfter: number?,
}

function ProfileMigration.Run(data: { [string]: any }): Report
	local report: Report = {}
	local stats = if type(data.Stats) == "table" then data.Stats else nil

	if (tonumber(data.EconomyVersion) or 1) < ProfileMigration.EconomyVersion then
		local before = math.max(0, math.floor(tonumber(data.Coins) or 0))
		local after = math.ceil(before / ProfileMigration.CoinScale)
		data.Coins = after
		data.EconomyVersion = ProfileMigration.EconomyVersion
		report.CoinsBefore, report.CoinsAfter = before, after
		if stats then
			-- Podiums are counted from now on; every win saved so far was one.
			stats.Podiums = math.max(tonumber(stats.Podiums) or 0, tonumber(stats.Wins) or 0)
		end
	end

	if stats and type(stats.ModePlays) == "table" then
		local tried = 0
		for _, plays in stats.ModePlays do
			if (tonumber(plays) or 0) > 0 then
				tried += 1
			end
		end
		stats.GamesTried = tried
	end
	return report
end

return ProfileMigration
