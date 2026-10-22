-- Extra coins on top of a round's reward (owner, asked what keeps players coming back: "Can you work
-- on all of that?"): playing with a friend (FriendsService), double coins weekends (EventService).
-- A feature registers a boost once; RewardService asks every boost when it pays a player for a
-- round, and each one that pays adds a line to that player's results card, like the rest of the
-- reward ("Played with a friend +1").
-- A boost can pay XP as well (owner: "the paid one should also be insane"): the GOLD PASS's 10% more
-- XP from rounds (Services/GoldPassService) is a line of XP only ("👑 GOLD PASS +10% XP  +6 XP").

local Boosts = {}

-- What a boost knows about the round it's paying for. Coins and XP are the reward so far, boosts
-- included.
export type Round = { Definition: any, Place: number, PlayerCount: number, Coins: number, XP: number }
-- Returns the extra coins (0 for none), the line for the results card, and the extra XP (none if nil).
export type Boost = (player: Player, round: Round) -> (number, string?, number?)

local boosts: { { Name: string, Fn: Boost } } = {}

-- Adds a boost (in the order they're registered: a boost that multiplies, like double coins, should
-- come after the ones that add, so it doubles them too).
function Boosts.Register(name: string, boost: Boost)
	table.insert(boosts, { Name = name, Fn = boost })
end

-- Adds every boost that pays to `reward` (RewardLogic's Reward: Coins, XP and Lines). A boost that
-- errors is skipped: a round always pays.
function Boosts.Apply(player: Player, reward: any, round: { Definition: any, Place: number, PlayerCount: number })
	for _, boost in boosts do
		local ok, coins, label, xp = pcall(boost.Fn, player, {
			Definition = round.Definition,
			Place = round.Place,
			PlayerCount = round.PlayerCount,
			Coins = reward.Coins,
			XP = reward.XP,
		})
		if not ok then
			continue
		end
		coins = if type(coins) == "number" and coins >= 1 then math.floor(coins) else 0
		xp = if type(xp) == "number" and xp >= 1 then math.floor(xp) else 0
		if coins > 0 or xp > 0 then
			table.insert(
				reward.Lines,
				{ Label = if type(label) == "string" then label else boost.Name, Coins = coins, XP = xp }
			)
			reward.Coins += coins
			reward.XP += xp
		end
	end
end

return Boosts
