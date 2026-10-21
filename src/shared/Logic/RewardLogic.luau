--!strict
-- Round reward calculation (design doc §9 "Example reward model").
-- Everyone who finishes a round earns something; strong play earns visible bonuses,
-- and every line of the breakdown says exactly why it was earned. The first win of each day pays
-- a bonus on top (owner: "Also we need cool payoffs for players that keep playing the game.").
-- Leaf module: no requires, no Roblox APIs.

local RewardLogic = {}

export type RewardValue = { Coins: number, XP: number }

export type RewardTable = {
	Participation: RewardValue,
	TopHalf: RewardValue,
	Winner: RewardValue,
	PersonalBest: RewardValue,
	FirstWin: RewardValue?,
}

export type RoundOutcome = {
	Place: number,
	PlayerCount: number,
	PersonalBest: boolean?,
	FirstWin: boolean?, -- this win is the player's first today (DailyLogic.ClaimFirstWin)
}

export type Line = { Label: string, Coins: number, XP: number }

export type Reward = {
	Coins: number,
	XP: number,
	Lines: { Line },
	IsWinner: boolean,
	IsTopHalf: boolean,
}

local function isTopHalf(place: number, playerCount: number): boolean
	return place <= math.max(1, math.ceil(playerCount / 2))
end

function RewardLogic.ForRound(outcome: RoundOutcome, rewards: RewardTable): Reward
	local lines: { Line } = {}
	local function add(label: string, value: RewardValue)
		table.insert(lines, { Label = label, Coins = value.Coins, XP = value.XP })
	end

	add("Played the round", rewards.Participation)

	local topHalf = isTopHalf(outcome.Place, outcome.PlayerCount)
	if topHalf then
		add("Top half finish", rewards.TopHalf)
	end

	local winner = outcome.Place == 1
	if winner then
		add("Winner!", rewards.Winner)
	end

	if outcome.PersonalBest then
		add("New personal best", rewards.PersonalBest)
	end

	if winner and outcome.FirstWin and rewards.FirstWin then
		add("First win today!", rewards.FirstWin)
	end

	local coins, xp = 0, 0
	for _, line in lines do
		coins += line.Coins
		xp += line.XP
	end

	return {
		Coins = coins,
		XP = xp,
		Lines = lines,
		IsWinner = winner,
		IsTopHalf = topHalf,
	}
end

return RewardLogic
