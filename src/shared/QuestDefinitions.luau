-- Daily and weekly quests (design doc §9). Event names are fired by the server's QuestService
-- (RewardService, VotingService, SocialService); every event here must be one of those.
-- Rewards are on the low coin scale (owner: "I want low currency not high"): a daily quest pays
-- about as much as one or two rounds, a weekly one about ten.
-- Retired (no game ever reported their progress, so they could never be finished): D_Collect25,
-- D_TeamObjective, W_Collect150. A player who still has one gets a fresh quest in its place
-- (QuestLogic.Refresh).

local QuestDefinitions = {
	-- Daily
	{
		Id = "D_Play3",
		Period = "Daily",
		Text = "Play 3 rounds",
		Event = "RoundPlayed",
		Target = 3,
		RewardCoins = 5,
		RewardXP = 40,
	},
	{
		Id = "D_TopHalf",
		Period = "Daily",
		Text = "Finish in the top half once",
		Event = "TopHalf",
		Target = 1,
		RewardCoins = 4,
		RewardXP = 30,
	},
	{
		Id = "D_Variety3",
		Period = "Daily",
		Text = "Play 3 different games",
		Event = "GamePlayed",
		Target = 3,
		Unique = true,
		RewardCoins = 6,
		RewardXP = 40,
	},
	{
		Id = "D_Vote5",
		Period = "Daily",
		Text = "Vote in 5 rounds",
		Event = "Voted",
		Target = 5,
		RewardCoins = 3,
		RewardXP = 25,
	},
	{
		Id = "D_Emotes3",
		Period = "Daily",
		Text = "Use 3 different emotes in the lobby",
		Event = "EmoteUsed",
		Target = 3,
		Unique = true,
		RewardCoins = 3,
		RewardXP = 20,
	},
	{
		Id = "D_TeamWin",
		Period = "Daily",
		Text = "Win a round with your team",
		Event = "TeamWin",
		Target = 1,
		RewardCoins = 5,
		RewardXP = 35,
	},
	{
		Id = "D_Win1",
		Period = "Daily",
		Text = "Win a round",
		Event = "Win",
		Target = 1,
		RewardCoins = 8,
		RewardXP = 50,
	},
	{
		Id = "D_Survive120",
		Period = "Daily",
		Text = "Survive 120 seconds in survival games",
		Event = "SurviveSeconds",
		Target = 120,
		RewardCoins = 5,
		RewardXP = 35,
	},
	{
		Id = "D_OffCategory",
		Period = "Daily",
		Text = "Win a round outside your favorite category",
		Event = "WinOffCategory",
		Target = 1,
		RewardCoins = 8,
		RewardXP = 50,
	},
	-- Weekly
	{
		Id = "W_Play25",
		Period = "Weekly",
		Text = "Play 25 rounds",
		Event = "RoundPlayed",
		Target = 25,
		RewardCoins = 25,
		RewardXP = 200,
	},
	{
		Id = "W_Win5",
		Period = "Weekly",
		Text = "Win 5 rounds",
		Event = "Win",
		Target = 5,
		RewardCoins = 30,
		RewardXP = 250,
	},
	{
		Id = "W_Podium10",
		Period = "Weekly",
		Text = "Make the podium (top 3) 10 times",
		Event = "Podium",
		Target = 10,
		RewardCoins = 25,
		RewardXP = 200,
	},
	{
		Id = "W_TopHalf10",
		Period = "Weekly",
		Text = "Finish in the top half 10 times",
		Event = "TopHalf",
		Target = 10,
		RewardCoins = 25,
		RewardXP = 200,
	},
}

local byId = {}
for _, quest in QuestDefinitions do
	byId[quest.Id] = quest
end

return {
	List = QuestDefinitions,
	ById = byId,
}
