-- Daily and weekly quests. Gameplay systems call QuestService.Track with an event name;
-- completed quests pay out automatically with a toast that says exactly what was earned. A weekly
-- quest also pays a key for the season's crates (Services/CrateService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local DailyLogic = require(Shared.Logic.DailyLogic)
local QuestDefinitions = require(Shared.QuestDefinitions)
local QuestLogic = require(Shared.Logic.QuestLogic)

local CrateService = require(script.Parent.CrateService)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.Economy)
local Notifier = require(script.Parent.Notifier)
local Telemetry = require(script.Parent.Telemetry)

local QuestService = {}

local rng = Random.new()
local function pickIndex(count: number): number
	return rng:NextInteger(1, count)
end

-- Rolls new quests when the day or week changes. Returns true when anything changed.
function QuestService.Refresh(player: Player): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end
	local now = os.time()
	local quests = profile.Data.Quests
	local changed = QuestLogic.Refresh(
		quests.Daily,
		QuestDefinitions.List,
		"Daily",
		DailyLogic.DayNumber(now),
		Config.Quests.DailyCount,
		pickIndex
	)
	changed = QuestLogic.Refresh(
		quests.Weekly,
		QuestDefinitions.List,
		"Weekly",
		DailyLogic.WeekNumber(now),
		Config.Quests.WeeklyCount,
		pickIndex
	) or changed
	if changed then
		DataService.Changed(player)
	end
	return changed
end

function QuestService.Track(player: Player, eventName: string, amount: number?, uniqueKey: string?)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	QuestService.Refresh(player)

	local quests = profile.Data.Quests
	local completed = QuestLogic.ApplyEvent(quests.Daily, QuestDefinitions.ById, eventName, amount, uniqueKey)
	for _, def in QuestLogic.ApplyEvent(quests.Weekly, QuestDefinitions.ById, eventName, amount, uniqueKey) do
		table.insert(completed, def)
	end

	for _, def in completed do
		Economy.AddCoins(player, def.RewardCoins, "Quest")
		Economy.AddXP(player, def.RewardXP)
		local keys = CrateService.QuestKeys(player, def.Period) -- a weekly quest's Lantern Key
		local keyText = if keys > 0 then `, +{keys} key{if keys == 1 then "" else "s"}` else ""
		Notifier.Send(
			player,
			`Quest complete: {def.Text}! +{def.RewardCoins} coins, +{def.RewardXP} XP{keyText}`,
			"reward",
			6
		)
		Telemetry.PlayerEvent(player, "QuestCompleted", 1, def.Id)
	end
	DataService.Changed(player)
end

function QuestService.Init()
	DataService.ProfileLoaded:Connect(function(player: Player)
		QuestService.Refresh(player)
	end)
end

function QuestService.Start()
	-- Roll over quests for players who stay online across midnight UTC.
	while true do
		task.wait(60)
		for player in DataService.All() do
			QuestService.Refresh(player)
		end
	end
end

return QuestService
