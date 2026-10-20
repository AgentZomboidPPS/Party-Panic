--!strict
-- Daily reward streaks and day/week numbering.
-- Leaf module: no requires, no Roblox APIs.

local DailyLogic = {}

export type DailyState = {
	LastClaimDay: number,
	Streak: number,
}

local SECONDS_PER_DAY = 86400

-- Whole UTC days since the Unix epoch.
function DailyLogic.DayNumber(unixTime: number): number
	return math.floor(unixTime / SECONDS_PER_DAY)
end

-- Weeks start on Monday (the epoch was a Thursday, hence the +3).
function DailyLogic.WeekNumber(unixTime: number): number
	return math.floor((DailyLogic.DayNumber(unixTime) + 3) / 7)
end

function DailyLogic.CanClaim(state: DailyState, today: number): boolean
	return state.LastClaimDay < today
end

-- The streak the player would be on if they claimed today.
function DailyLogic.NextStreak(state: DailyState, today: number): number
	if state.LastClaimDay == today - 1 then
		return state.Streak + 1
	end
	return 1
end

-- Claims today's reward, mutating `state`. Returns success, new streak and coins earned.
-- A missed day resets the streak; streaks past the end of the table keep the final reward.
function DailyLogic.Claim(state: DailyState, today: number, rewardTable: { number }): (boolean, number, number)
	if not DailyLogic.CanClaim(state, today) then
		return false, state.Streak, 0
	end
	local streak = DailyLogic.NextStreak(state, today)
	local coins = rewardTable[math.min(streak, #rewardTable)] or 0
	state.LastClaimDay = today
	state.Streak = streak
	return true, streak, coins
end

return DailyLogic
