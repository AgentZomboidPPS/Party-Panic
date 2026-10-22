-- Party Panic server entry point: initializes every service, then starts their loops.
--
-- NoSitService (owner: "Also theres times where I will sit on invisible shit in game. NO mini game
-- should require you to sit.") starts before the bots, so every bot's first character can't sit.

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
	"GoldPassService", -- the GOLD PASS: after CosmeticService (a returning owner's rewards come first)
	"SocialService",
	"SitOutService",
	"VotingService",
	"ReplayService", -- the results card's PLAY AGAIN vote
	"LobbyService",
	"SkeeBallService", -- after the lobby exists (its arcade)
	-- What keeps players coming back (they listen to RoundEvents; the lobby exists for their pieces).
	"CupService",
	"FriendsService",
	"PartyService", -- parties: same team in team games (RoundContext reads its PP_Party)
	"MedalService",
	"LeaderboardService",
	"EventService",
	"NoSitService", -- before the bots arrive: no character sits (Shared/NoSitting)
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
