-- Extra coins on top of a round's reward (owner, asked what keeps players coming back: "Can you work
-- on all of that?"): playing with a friend (FriendsService), double coins weekends (EventService).
-- A feature registers a boost once; RewardService asks every boost when it pays a player for a
-- round, and each one that pays adds a line to that player's results card, like the rest of the
-- reward ("Played with a friend +1").

local Boosts = {}

-- What a boost knows about the round it's paying for. Coins is the reward so far, boosts included.
export type Round = { Definition: any, Place: number, PlayerCount: number, Coins: number }
-- Returns the extra coins (0 for none) and the line for the results card.
export type Boost = (player: Player, round: Round) -> (number, string?)

local boosts: { { Name: string, Fn: Boost } } = {}

-- Adds a boost (in the order they're registered: a boost that multiplies, like double coins, should
-- come after the ones that add, so it doubles them too).
function Boosts.Register(name: string, boost: Boost)
	table.insert(boosts, { Name = name, Fn = boost })
end

-- Adds every boost that pays to `reward` (RewardLogic's Reward: Coins and Lines). A boost that errors
-- is skipped: a round always pays.
function Boosts.Apply(player: Player, reward: any, round: { Definition: any, Place: number, PlayerCount: number })
	for _, boost in boosts do
		local ok, coins, label = pcall(boost.Fn, player, {
			Definition = round.Definition,
			Place = round.Place,
			PlayerCount = round.PlayerCount,
			Coins = reward.Coins,
		})
		if ok and type(coins) == "number" and coins >= 1 then
			coins = math.floor(coins)
			table.insert(
				reward.Lines,
				{ Label = if type(label) == "string" then label else boost.Name, Coins = coins, XP = 0 }
			)
			reward.Coins += coins
		end
	end
end

return Boosts
