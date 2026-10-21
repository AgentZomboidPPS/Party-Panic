-- Party Panic server entry point: initializes every service, then starts their loops.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
-- Create replicated state containers before anything else so clients can find them.
require(Shared.Remotes).Get("Notify")
require(Shared.GameState).Folder()

local Services = script.Services

local order = {
	"DataService",
	"ClientReports",
	"CosmeticService",
	"QuestService",
	"ShopService",
	"SocialService",
	"VotingService",
	"LobbyService",
	"SkeeBallService", -- after the lobby exists (its arcade)
	"BotService", -- after the lobby exists (spawns, vote pads)
	"RoundManager",
}

local loaded = {}
for _, name in order do
	loaded[name] = require(Services:FindFirstChild(name) :: ModuleScript)
end

for _, name in order do
	local service = loaded[name]
	if service.Init then
		service.Init()
	end
end

for _, name in order do
	local service = loaded[name]
	if service.Start then
		task.spawn(service.Start)
	end
end

print(`[PartyPanic] Server ready (v{require(Shared.Config).Version})`)
