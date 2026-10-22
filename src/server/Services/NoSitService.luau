-- Nobody sits (owner: "Also theres times where I will sit on invisible shit in game. NO mini game
-- should require you to sit."): turns the Seated state off (Shared/NoSitting) for every bot's
-- character, which the server simulates (BotService keeps each bot's network owner), for each new
-- character a bot gets. Players' own devices do it for their characters
-- (Controllers/MovementController); the server guards those too, so anything that sets Sit on
-- them here is undone at once.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NoSitting = require(ReplicatedStorage.Shared.NoSitting)

local BotRegistry = require(script.Parent.BotRegistry)

local NoSitService = {}

function NoSitService.Init()
	local function watchBot(bot: any)
		if bot.Character then
			NoSitting.Guard(bot.Character)
		end
		bot.CharacterAdded:Connect(NoSitting.Guard)
	end
	for _, bot in BotRegistry.List() do
		watchBot(bot)
	end
	BotRegistry.Added:Connect(watchBot)

	local function watchPlayer(player: Player)
		if player.Character then
			NoSitting.Guard(player.Character)
		end
		player.CharacterAdded:Connect(NoSitting.Guard)
	end
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
end

return NoSitService
