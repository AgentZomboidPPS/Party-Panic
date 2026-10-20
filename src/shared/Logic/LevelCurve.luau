--!strict
-- Account level curve. Party XP is never spent; the level is derived from the lifetime total.
-- Leaf module: no requires, no Roblox APIs.

local LevelCurve = {}

LevelCurve.MaxLevel = 100

-- XP needed to advance from `level` to `level + 1`.
function LevelCurve.XPForLevel(level: number): number
	return 100 + (level - 1) * 50
end

-- Returns level, XP earned inside the current level, and XP needed to reach the next level.
function LevelCurve.FromTotalXP(totalXP: number): (number, number, number)
	local remaining = math.max(0, math.floor(totalXP))
	local level = 1
	while level < LevelCurve.MaxLevel do
		local needed = LevelCurve.XPForLevel(level)
		if remaining < needed then
			return level, remaining, needed
		end
		remaining -= needed
		level += 1
	end
	return LevelCurve.MaxLevel, 0, 0
end

function LevelCurve.TotalXPForLevel(level: number): number
	local total = 0
	for current = 1, math.clamp(level, 1, LevelCurve.MaxLevel) - 1 do
		total += LevelCurve.XPForLevel(current)
	end
	return total
end

return LevelCurve
