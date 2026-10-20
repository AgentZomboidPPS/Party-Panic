-- Renders the in-world screens from replicated state: the three giant vote cards, the
-- announcement board, the personal quest board, the champion board and podium name tags.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameDefinitions = require(Shared.GameDefinitions)
local GameState = require(Shared.GameState)
local Placement = require(Shared.Logic.Placement)
local QuestDefinitions = require(Shared.QuestDefinitions)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local WorldScreensController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function surface(part: BasePart, face: Enum.NormalId, pixelsPerStud: number?): SurfaceGui
	return UIKit.new("SurfaceGui", {
		Name = "Screen_" .. part.Name,
		Adornee = part,
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = pixelsPerStud or 24,
		LightInfluence = 0,
		Brightness = 1.4,
		MaxDistance = 400,
		ResetOnSpawn = false,
		Parent = playerGui,
	})
end

local function phaseTitle(phase: string): string
	local gameId = GameState.Get("GameId")
	local definition = gameId ~= "" and GameDefinitions.Get(gameId)
	if phase == "Voting" then
		return "🗳️ VOTE NOW!"
	elseif phase == "Preparing" or phase == "InRound" then
		return if definition then `{definition.Icon} {string.upper(definition.Name)}` else "ROUND IN PROGRESS"
	elseif phase == "Results" then
		return "🏆 RESULTS"
	elseif phase == "Waiting" then
		return "⏳ " .. string.upper(GameState.Get("Message") or "WAITING")
	end
	return "🎉 PARTY PANIC"
end

local function buildAnnouncement(part: BasePart)
	local gui = surface(part, Enum.NormalId.Back, 20)
	local title = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextScaled = true,
		Size = UDim2.fromScale(1, 0.62),
		Parent = gui,
		Children = { UIKit.Padding(8, 16) },
	})
	local sub = UIKit.Label({
		Text = "",
		TextScaled = true,
		TextColor3 = Theme.Colors.Yellow,
		Position = UDim2.fromScale(0, 0.6),
		Size = UDim2.fromScale(1, 0.36),
		Parent = gui,
		Children = { UIKit.Padding(4, 16) },
	})
	RunService.Heartbeat:Connect(function()
		local phase = GameState.Get("Phase")
		title.Text = phaseTitle(phase)
		local left = GameState.TimeLeft()
		if phase == "Intermission" then
			sub.Text = `Next vote in {UIKit.FormatTime(left)}`
		elseif phase == "Voting" then
			sub.Text = `Step on a portal pad or tap a card • {UIKit.FormatTime(left)}`
		elseif phase == "InRound" then
			sub.Text = `{GameState.Get("Status") or ""}  •  {UIKit.FormatTime(left)}`
		elseif phase == "Preparing" then
			sub.Text = "Get ready..."
		else
			sub.Text = GameState.Get("Message") or ""
		end
	end)
end

local function buildVoteScreen(part: BasePart)
	local index = part:GetAttribute("VoteIndex") :: number
	local gui = surface(part, Enum.NormalId.Back, 22)
	local frame = UIKit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
	local icon = UIKit.Label({
		Text = "",
		TextScaled = true,
		Size = UDim2.fromScale(0.28, 0.5),
		Position = UDim2.fromScale(0.02, 0.05),
		Parent = frame,
	})
	local name = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromScale(0.68, 0.3),
		Position = UDim2.fromScale(0.3, 0.06),
		Parent = frame,
	})
	local category = UIKit.Label({
		Text = "",
		TextScaled = true,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromScale(0.68, 0.16),
		Position = UDim2.fromScale(0.3, 0.36),
		Parent = frame,
	})
	local objective = UIKit.Label({
		Text = "",
		TextScaled = true,
		Size = UDim2.fromScale(0.94, 0.22),
		Position = UDim2.fromScale(0.03, 0.55),
		Parent = frame,
	})
	local barBack = UIKit.new("Frame", {
		Size = UDim2.fromScale(0.94, 0.12),
		Position = UDim2.fromScale(0.03, 0.82),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = frame,
		Children = { UIKit.Round() },
	})
	local bar = UIKit.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Colors.Yellow,
		Parent = barBack,
		Children = { UIKit.Round() },
	})
	local votes = UIKit.Label({
		Text = "",
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
		Font = Theme.Fonts.Display,
		TextColor3 = Theme.Colors.PanelDark,
		Parent = barBack,
	})

	local function refresh()
		local phase = GameState.Get("Phase")
		local options = GameState.GetJSON("VoteOptions") or {}
		local counts = GameState.GetJSON("VoteCounts") or {}
		local option = options[index]
		local showVote = (phase == "Voting" or phase == "Preparing") and option ~= nil
		frame.Visible = true
		if not showVote then
			icon.Text = "🎉"
			name.Text = `PORTAL {index}`
			category.Text = "Games appear here at vote time"
			objective.Text = if phase == "Intermission"
				then `Next vote in {UIKit.FormatTime(GameState.TimeLeft())}`
				else ""
			bar.Size = UDim2.fromScale(0, 1)
			votes.Text = ""
			return
		end
		local definition = GameDefinitions.Get(option.Id)
		local revealed = not option.Mystery or (phase == "Preparing" and GameState.Get("GameId") == option.Id)
		if definition and revealed then
			icon.Text = definition.Icon
			name.Text = definition.Name
			local categoryInfo = GameDefinitions.Categories[definition.Category]
			category.Text =
				`{categoryInfo and categoryInfo.Icon or ""} {definition.Category} • ~{definition.Duration}s`
			objective.Text = definition.Objective
		else
			icon.Text = "❓"
			name.Text = "MYSTERY GAME"
			category.Text = "Revealed only if it wins!"
			objective.Text = "Feeling lucky?"
		end
		local total = 0
		for _, count in counts do
			total += count
		end
		local mine = counts[index] or 0
		UIKit.Tween(bar, 0.25, { Size = UDim2.fromScale(if total > 0 then mine / total else 0, 1) })
		votes.Text = `{mine} vote{if mine == 1 then "" else "s"}`
	end
	GameState.Changed("VoteOptions", refresh)
	GameState.Changed("VoteCounts", refresh)
	GameState.Changed("Phase", refresh)
	GameState.Changed("GameId", refresh)
	task.spawn(function()
		while true do
			task.wait(1)
			if GameState.Get("Phase") == "Intermission" then
				refresh()
			end
		end
	end)
	refresh()
end

local function buildQuestBoard(part: BasePart)
	local gui = surface(part, Enum.NormalId.Front, 28)
	local list = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 6), UIKit.Padding(14) },
	})
	local function refresh()
		for _, child in list:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		UIKit.Label({
			Text = "📜 YOUR QUESTS",
			Font = Theme.Fonts.Display,
			TextSize = 44,
			Size = UDim2.new(1, 0, 0, 52),
			LayoutOrder = 0,
			Parent = list,
		})
		local profile = State.Profile
		if not profile then
			return
		end
		local order = 1
		for _, period in { "Daily", "Weekly" } do
			for _, quest in profile.Quests[period] do
				local def = QuestDefinitions.ById[quest.Id]
				if def then
					local mark = if quest.Done then "✅" else `{quest.Progress}/{def.Target}`
					UIKit.Label({
						Text = `{if period == "Weekly" then "⭐ " else ""}{def.Text}  —  {mark}`,
						TextSize = 30,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextColor3 = if quest.Done then Theme.Colors.Green else Theme.Colors.Text,
						Size = UDim2.new(1, 0, 0, 38),
						LayoutOrder = order,
						Parent = list,
					})
					order += 1
				end
			end
		end
	end
	State.ProfileChanged:Connect(refresh)
	refresh()
end

local thumbnails: { [number]: string } = {}
local function headshot(userId: number): string
	if not thumbnails[userId] then
		local ok, url = pcall(
			Players.GetUserThumbnailAsync,
			Players,
			userId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size150x150
		)
		thumbnails[userId] = if ok then url else ""
	end
	return thumbnails[userId]
end

local function buildChampions()
	local spots: { [number]: BasePart } = {}
	for _, spot in CollectionService:GetTagged("PodiumSpot") do
		spots[spot:GetAttribute("Place") :: number] = spot :: BasePart
	end
	local tags: { [number]: { image: ImageLabel, label: TextLabel, gui: BillboardGui } } = {}
	for place, spot in spots do
		local gui = UIKit.new("BillboardGui", {
			Adornee = spot,
			Size = UDim2.fromOffset(150, 170),
			MaxDistance = 140,
			LightInfluence = 0,
			ResetOnSpawn = false,
			Parent = playerGui,
		})
		local image = UIKit.new("ImageLabel", {
			Size = UDim2.fromOffset(110, 110),
			Position = UDim2.fromOffset(20, 0),
			BackgroundColor3 = Theme.Colors.Panel,
			Parent = gui,
			Children = { UIKit.Round(), UIKit.Stroke(Theme.Colors.Yellow, 3, 0) },
		})
		local label = UIKit.Label({
			Text = "",
			Font = Theme.Fonts.Display,
			TextSize = 24,
			Position = UDim2.fromOffset(0, 116),
			Size = UDim2.new(1, 0, 0, 50),
			Parent = gui,
			Children = { UIKit.TextStroke(0.2) },
		})
		tags[place] = { image = image, label = label, gui = gui }
	end

	local boardPart = CollectionService:GetTagged("ChampionBoard")[1] :: BasePart?
	local boardText: TextLabel? = nil
	if boardPart then
		local gui = surface(boardPart, Enum.NormalId.Left, 20)
		boardText = UIKit.Label({
			Text = "",
			TextScaled = true,
			Size = UDim2.fromScale(1, 1),
			Font = Theme.Fonts.Display,
			Parent = gui,
			Children = { UIKit.Padding(18) },
		})
	end

	local function refresh()
		local champions = GameState.GetJSON("Champions") or {}
		local lines = { "🏆 LAST ROUND" }
		for place, tag in tags do
			local champion = nil
			for _, entry in champions do
				if entry.Place == place and not champion then
					champion = entry
				end
			end
			tag.gui.Enabled = champion ~= nil
			if champion then
				tag.label.Text = champion.Name
				task.spawn(function()
					tag.image.Image = headshot(champion.UserId)
				end)
			end
		end
		for _, entry in champions do
			table.insert(lines, `{Placement.Ordinal(entry.Place)}  {entry.Name}`)
		end
		if #champions == 0 then
			table.insert(lines, "Win a round to\nclaim the podium!")
		end
		if boardText then
			boardText.Text = table.concat(lines, "\n")
		end
	end
	GameState.Changed("Champions", refresh)
	refresh()
end

-- Hide today's secret token for players who already found it.
local function bindSecretToken()
	local lobby = workspace:WaitForChild("Lobby", 30)
	local token = lobby and lobby:WaitForChild("SecretToken", 30) :: BasePart?
	if not token then
		return
	end
	local function refresh()
		local found = State.Profile and State.Profile.Daily and State.Profile.Daily.SecretFound
		token.LocalTransparencyModifier = if found then 1 else 0
		local sparkles = token:FindFirstChildOfClass("Sparkles")
		if sparkles then
			sparkles.Enabled = not found
		end
	end
	State.ProfileChanged:Connect(refresh)
	refresh()
end

function WorldScreensController.Start(_context)
	task.spawn(function()
		workspace:WaitForChild("Lobby", 60)
		task.wait(0.5)
		for _, part in CollectionService:GetTagged("AnnouncementScreen") do
			buildAnnouncement(part :: BasePart)
		end
		for _, part in CollectionService:GetTagged("VoteScreen") do
			buildVoteScreen(part :: BasePart)
		end
		for _, part in CollectionService:GetTagged("QuestBoard") do
			buildQuestBoard(part :: BasePart)
		end
		buildChampions()
		bindSecretToken()
	end)
end

return WorldScreensController
