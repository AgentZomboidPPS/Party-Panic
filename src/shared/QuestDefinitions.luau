-- Daily and weekly quests (design doc §9). Event names are fired by the server's QuestService.

local QuestDefinitions = {
	-- Daily
	{
		Id = "D_Play3",
		Period = "Daily",
		Text = "Play 3 rounds",
		Event = "RoundPlayed",
		Target = 3,
		RewardCoins = 50,
		RewardXP = 40,
	},
	{
		Id = "D_TopHalf",
		Period = "Daily",
		Text = "Finish in the top half once",
		Event = "TopHalf",
		Target = 1,
		RewardCoins = 40,
		RewardXP = 30,
	},
	{
		Id = "D_Collect25",
		Period = "Daily",
		Text = "Collect 25 items in collection games",
		Event = "ItemCollected",
		Target = 25,
		RewardCoins = 60,
		RewardXP = 40,
	},
	{
		Id = "D_Vote5",
		Period = "Daily",
		Text = "Vote in 5 rounds",
		Event = "Voted",
		Target = 5,
		RewardCoins = 30,
		RewardXP = 25,
	},
	{
		Id = "D_Emotes3",
		Period = "Daily",
		Text = "Use 3 different emotes in the lobby",
		Event = "EmoteUsed",
		Target = 3,
		Unique = true,
		RewardCoins = 30,
		RewardXP = 20,
	},
	{
		Id = "D_TeamObjective",
		Period = "Daily",
		Text = "Deliver treasure for your team",
		Event = "TeamObjective",
		Target = 1,
		RewardCoins = 50,
		RewardXP = 35,
	},
	{
		Id = "D_Win1",
		Period = "Daily",
		Text = "Win a round",
		Event = "Win",
		Target = 1,
		RewardCoins = 75,
		RewardXP = 50,
	},
	{
		Id = "D_Survive120",
		Period = "Daily",
		Text = "Survive 120 seconds in survival games",
		Event = "SurviveSeconds",
		Target = 120,
		RewardCoins = 50,
		RewardXP = 35,
	},
	{
		Id = "D_OffCategory",
		Period = "Daily",
		Text = "Win a round outside your favorite category",
		Event = "WinOffCategory",
		Target = 1,
		RewardCoins = 80,
		RewardXP = 50,
	},
	-- Weekly
	{
		Id = "W_Play25",
		Period = "Weekly",
		Text = "Play 25 rounds",
		Event = "RoundPlayed",
		Target = 25,
		RewardCoins = 250,
		RewardXP = 200,
	},
	{
		Id = "W_Win5",
		Period = "Weekly",
		Text = "Win 5 rounds",
		Event = "Win",
		Target = 5,
		RewardCoins = 300,
		RewardXP = 250,
	},
	{
		Id = "W_Collect150",
		Period = "Weekly",
		Text = "Collect 150 items",
		Event = "ItemCollected",
		Target = 150,
		RewardCoins = 250,
		RewardXP = 200,
	},
	{
		Id = "W_TopHalf10",
		Period = "Weekly",
		Text = "Finish in the top half 10 times",
		Event = "TopHalf",
		Target = 10,
		RewardCoins = 250,
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
