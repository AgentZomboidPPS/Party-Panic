-- Results screen (design doc §12): placement, standings, an itemized reward breakdown and a
-- "next vote soon" cue. Short and skippable; it closes itself when the lobby returns. Bots' names
-- in the standings are a little softer than people's (Participants).
-- The breakdown includes the first win of the day's bonus, and a round that levels you up says so
-- in place of the "next vote" cue (owner: "Also we need cool payoffs for players that keep playing
-- the game.").
--
-- Each standings row has the place and name on the left and the result on the right, in its own
-- label: the result always reads whole and a long name gives way ("..."), only as far as its own
-- row's result needs. It used to be one line ("🥇  name  ·  result") that a 15-character name cut
-- short in every mode.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameDefinitions = require(Shared.GameDefinitions)
local GameState = require(Shared.GameState)
local Placement = require(Shared.Logic.Placement)
local Remotes = require(Shared.Remotes)

local AudioController = require(script.Parent.AudioController)
local Participants = require(script.Parent.Parent.Participants)
local Modal = require(script.Parent.Parent.UI.Modal)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local ResultsController = {}

local MEDALS = { "🥇", "🥈", "🥉" }

-- The standings rows (units: the column is about 374 wide on every screen): a result takes as much
-- of its row as it needs, up to RESULT_MAX (the rest stays for the place and name); one that's wider
-- still is drawn smaller, down to RESULT_MIN_TEXT (11 pt on a phone).
local ROW_TEXT, RESULT_MAX, RESULT_MIN_TEXT = 21, 232, 18

-- The room a result needs at this text size: a little more than it measures, because phones draw
-- the scaled-down text up to 4% wider than that (a result given exactly its width ended in "...").
local function resultRoom(text: string, size: number): number
	return UIKit.TextWidth(text, size, Theme.Fonts.Bold) * 1.06 + 4
end

local modal: Modal.Modal
local headline: TextLabel
local standings: Frame
local rewards: Frame

local function clear(frame: Instance)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function show(data)
	local definition = GameDefinitions.Get(data.GameId)
	local medal = MEDALS[data.Place] or "🎉"
	local teamLine = ""
	if data.MyTeam and data.MyTeam ~= "" then
		teamLine = if data.WinningTeam == data.MyTeam
			then "  •  Your team won!"
			elseif data.WinningTeam == nil then "  •  It's a draw!"
			else ""
	end
	headline.Text = if data.Place == 1
		then `{medal} You won {definition and definition.Name or "the round"}!{teamLine}`
		else `{medal} {Placement.Ordinal(data.Place)} of {data.PlayerCount}{teamLine}`

	clear(standings)
	for index, entry in data.Standings do
		local isMe = entry.UserId == game:GetService("Players").LocalPlayer.UserId
		local place = MEDALS[entry.Place] or Placement.Ordinal(entry.Place)
		local name = Participants.ListName(entry.Name, Participants.IsBotId(entry.UserId))
		local color = if isMe then Theme.Colors.Yellow else Theme.Colors.Text
		local result = entry.ScoreText or ""
		local textSize = ROW_TEXT
		local resultWidth = resultRoom(result, textSize)
		while textSize > RESULT_MIN_TEXT and resultWidth > RESULT_MAX do
			textSize -= 1
			resultWidth = resultRoom(result, textSize)
		end
		resultWidth = math.min(math.ceil(resultWidth), RESULT_MAX)
		local row = UIKit.new("Frame", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Parent = standings,
		})
		local nameLabel = UIKit.Label({
			Text = `{place}  {name}`,
			RichText = true,
			TextSize = ROW_TEXT,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = color,
			Size = UDim2.new(1, -(resultWidth + 10), 1, 0),
			Parent = row,
		})
		nameLabel:SetAttribute("PP_TruncateOk", true) -- a long name ends in "..."
		UIKit.Label({
			Name = "Result",
			Text = result,
			TextSize = textSize,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd, -- (only past RESULT_MAX at the smallest size)
			TextColor3 = color,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, resultWidth, 1, 0),
			Parent = row,
		})
	end

	clear(rewards)
	for index, line in data.Lines do
		local row = UIKit.new("Frame", {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundColor3 = Theme.Colors.PanelDark,
			BackgroundTransparency = 0.35,
			LayoutOrder = index,
			Parent = rewards,
			Children = { UIKit.Corner(10) },
		})
		UIKit.Label({
			Text = line.Label,
			TextSize = 19,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(0.6, 0, 1, 0),
			Position = UDim2.fromOffset(12, 0),
			Parent = row,
		})
		UIKit.Label({
			Text = `+{line.Coins} {Theme.CoinIcon}  +{line.XP} XP`,
			TextSize = 19,
			TextColor3 = Theme.Colors.Yellow,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.new(0.4, -12, 1, 0),
			Position = UDim2.fromScale(0.6, 0),
			Parent = row,
		})
		UIKit.PopIn(row, 0.25 + index * 0.08)
	end
	UIKit.Label({
		Text = `Total: +{data.Coins} {Theme.CoinIcon}   +{data.XP} XP`,
		Font = Theme.Fonts.Display,
		TextSize = 26,
		TextColor3 = Theme.Colors.Green,
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = 100,
		Parent = rewards,
	})
	if data.PersonalBest then
		UIKit.Label({
			Text = "⭐ New personal best!",
			Font = Theme.Fonts.Display,
			TextSize = 22,
			TextColor3 = Theme.Colors.Yellow,
			Size = UDim2.new(1, 0, 0, 30),
			LayoutOrder = 101,
			Parent = rewards,
		})
	end
	if type(data.LevelUp) == "number" then
		-- The full celebration plays once everyone's back in the lobby (CelebrationController).
		UIKit.Label({
			Text = `⭐ LEVEL UP! You're level {data.LevelUp}!`,
			Font = Theme.Fonts.Display,
			TextSize = 22,
			TextColor3 = Theme.Colors.Cyan,
			Size = UDim2.new(1, 0, 0, 30),
			LayoutOrder = 102,
			Parent = rewards,
			Children = { UIKit.TextStroke(0.2) },
		})
	else
		UIKit.Label({
			Text = "Next vote soon - get ready!",
			TextSize = 18,
			TextColor3 = Theme.Colors.TextDim,
			Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = 102,
			Parent = rewards,
		})
	end

	modal:Open()
	AudioController.Play(if data.Place == 1 then "Victory" else "Results")
end

function ResultsController.Start(context)
	modal = Modal.new(context.Overlay, "Round Results", "🏆", Vector2.new(820, 470))
	headline = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 34,
		Size = UDim2.new(1, 0, 0, 44),
		Parent = modal.Content,
		Children = { UIKit.TextStroke(0.2) },
	})
	standings = UIKit.new("Frame", {
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(0.48, 0, 1, -54),
		BackgroundTransparency = 1,
		Parent = modal.Content,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left) },
	})
	rewards = UIKit.new("Frame", {
		Position = UDim2.new(0.52, 0, 0, 54),
		Size = UDim2.new(0.48, 0, 1, -54),
		BackgroundTransparency = 1,
		Parent = modal.Content,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 6) },
	})

	Remotes.Get("RoundResults").OnClientEvent:Connect(function(data)
		if type(data) == "table" then
			show(data)
		end
	end)
	GameState.Changed("Phase", function(phase)
		if phase == "Cleanup" or phase == "Intermission" then
			modal:Close()
		end
	end)
end

return ResultsController
