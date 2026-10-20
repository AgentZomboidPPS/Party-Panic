-- Emotes, the daily reward, the hidden daily token, settings and tutorial state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Cosmetics = require(Shared.Cosmetics)
local DailyLogic = require(Shared.Logic.DailyLogic)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.Economy)
local Notifier = require(script.Parent.Notifier)
local QuestService = require(script.Parent.QuestService)
local RateLimiter = require(script.Parent.RateLimiter)
local Telemetry = require(script.Parent.Telemetry)

local SocialService = {}

local lastEmote: { [Player]: number } = {}

local SETTINGS_SCHEMA = {
	ReducedEffects = "boolean",
	MusicVolume = "number",
}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function useEmote(player: Player, itemId: any)
	if type(itemId) ~= "string" then
		return
	end
	local item = Cosmetics.Get(itemId)
	local profile = DataService.Get(player)
	if not item or item.Slot ~= "Emote" or not profile or not profile.Data.Owned[itemId] then
		return
	end
	local now = os.clock()
	if now - (lastEmote[player] or 0) < Config.EmoteCooldown then
		return
	end
	lastEmote[player] = now

	local root = rootOf(player)
	if item.Effect and root then
		Notifier.Effect(item.Effect, root.Position + Vector3.new(0, 2.5, 0), item.Colors)
	end
	-- Quest only counts lobby emotes, as the quest text says.
	if not player:GetAttribute("PP_InRound") then
		QuestService.Track(player, "EmoteUsed", 1, itemId)
	end
end

function SocialService.ClaimDaily(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local today = DailyLogic.DayNumber(os.time())
	local ok, streak, coins = DailyLogic.Claim(profile.Data.Daily, today, Config.DailyRewards)
	if not ok then
		Notifier.Send(player, "You've already claimed today's reward. Come back tomorrow!")
		return
	end
	Economy.AddCoins(player, coins, "Daily")
	Notifier.Send(player, `Daily reward: +{coins} coins (day {streak} streak)!`, "reward", 5)
	local root = rootOf(player)
	if root then
		Notifier.Effect("Confetti", root.Position + Vector3.new(0, 3, 0))
	end
	Telemetry.PlayerEvent(player, "DailyClaimed", streak)
	DataService.Changed(player)
end

-- The hidden lobby token: one claim per day, never required for progression.
function SocialService.ClaimSecretToken(player: Player): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end
	local today = DailyLogic.DayNumber(os.time())
	if profile.Data.Daily.SecretDay >= today then
		return false
	end
	profile.Data.Daily.SecretDay = today
	Economy.AddCoins(player, Config.SecretTokenCoins, "SecretToken")
	Notifier.Send(player, `You found today's secret token! +{Config.SecretTokenCoins} coins`, "reward", 5)
	Telemetry.PlayerEvent(player, "SecretTokenFound")
	DataService.Changed(player)
	return true
end

local function setSetting(player: Player, key: any, value: any)
	if type(key) ~= "string" or SETTINGS_SCHEMA[key] == nil or type(value) ~= SETTINGS_SCHEMA[key] then
		return
	end
	if type(value) == "number" then
		if value ~= value then
			return -- NaN
		end
		value = math.clamp(value, 0, 1)
	end
	local profile = DataService.Get(player)
	if profile then
		profile.Data.Settings[key] = value
		DataService.Changed(player)
	end
end

function SocialService.Init()
	local limits = Config.RateLimits
	local emoteLimiter = RateLimiter.new(limits.Emote[1], limits.Emote[2])
	local claimLimiter = RateLimiter.new(limits.Claim[1], limits.Claim[2])
	local settingsLimiter = RateLimiter.new(limits.Settings[1], limits.Settings[2])
	local tutorialLimiter = RateLimiter.new(limits.Tutorial[1], limits.Tutorial[2])

	Remotes.Get("UseEmote").OnServerEvent:Connect(function(player, itemId)
		if emoteLimiter:Check(player) then
			useEmote(player, itemId)
		end
	end)
	Remotes.Get("ClaimDaily").OnServerEvent:Connect(function(player)
		if claimLimiter:Check(player) then
			SocialService.ClaimDaily(player)
		end
	end)
	Remotes.Get("SetSetting").OnServerEvent:Connect(function(player, key, value)
		if settingsLimiter:Check(player) then
			setSetting(player, key, value)
		end
	end)
	Remotes.Get("TutorialDone").OnServerEvent:Connect(function(player)
		local profile = DataService.Get(player)
		if profile and tutorialLimiter:Check(player) and not profile.Data.Tutorial.Done then
			profile.Data.Tutorial.Done = true
			Telemetry.PlayerEvent(player, "TutorialCompleted")
			DataService.Changed(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastEmote[player] = nil
	end)
end

return SocialService
