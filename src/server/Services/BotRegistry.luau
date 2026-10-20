-- Who the bots are: the list other services check so they can treat a bot like a player (find one
-- from a character, skip rewards and remotes for it). BotService fills and empties it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)

local BotRegistry = {}

local active: { any } = {}
local byCharacter: { [Model]: any } = {}

BotRegistry.Added = Signal.new() -- (bot)
BotRegistry.Removed = Signal.new() -- (bot), like Players.PlayerRemoving

-- True for a bot (bots are tables that look like players; real players are Instances).
function BotRegistry.IsBot(player: any): boolean
	return type(player) == "table" and player.IsBot == true
end

function BotRegistry.List(): { any }
	return table.clone(active)
end

function BotRegistry.FromCharacter(character: Instance?): any
	return if character then byCharacter[character :: Model] else nil
end

function BotRegistry.FromUserId(userId: number): any
	for _, bot in active do
		if bot.UserId == userId then
			return bot
		end
	end
	return nil
end

function BotRegistry.Add(bot: any)
	table.insert(active, bot)
	BotRegistry.Added:Fire(bot)
end

function BotRegistry.Remove(bot: any)
	local index = table.find(active, bot)
	if index then
		table.remove(active, index)
		BotRegistry.Removed:Fire(bot)
	end
end

function BotRegistry.SetCharacter(bot: any, character: Model?, previous: Model?)
	if previous then
		byCharacter[previous] = nil
	end
	if character then
		byCharacter[character] = bot
	end
end

return BotRegistry
