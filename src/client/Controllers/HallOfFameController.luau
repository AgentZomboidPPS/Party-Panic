-- The weekly leaderboard on this player's screens. The owner, asked "If you could do 5 things to keep
-- players addicted what would you do?", got "Weekly leaderboard and Hall of Fame statues of last
-- week's top three" as one of them, then said: "Can you work on all of that? this wont mess with what
-- the other workers are working on right?".
--
--   * The board in the Hall of Fame (World/HallOfFame tags it WeeklyBoard): this week's top 10, this
--     player's own line ("YOU: #14 · 35 PTS", or how to get on it), the time to Monday's reset and
--     how points are won, drawn on its Front face.
--   * A chip in the lobby's row (UI/LobbyRibbon, priority 4: the first to give way when the row is
--     full): "📈 #14 THIS WEEK", or "📈 WEEKLY TOP 10" before they're on the board. Tapping it opens
--     the THIS WEEK window: the same board (readable on a phone from anywhere) and last week's top
--     three. State.OpenScreen:Fire("Weekly") opens it too.
-- The server owns all of it (Services/LeaderboardService): the board comes in GameState's
-- HallOfFame, this player's points in their profile (Weekly), their place in PP_WeeklyRank.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameState = require(Shared.GameState)
local WeeklyLogic = require(Shared.Logic.WeeklyLogic)

local State = require(script.Parent.Parent.State)
local LobbyRibbon = require(script.Parent.Parent.UI.LobbyRibbon)
local Modal = require(script.Parent.Parent.UI.Modal)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local HallOfFameController = {}

local player = Players.LocalPlayer

local MEDALS = { "🥇", "🥈", "🥉" }
local GOLD = Color3.fromRGB(255, 204, 64)
local REFRESH_EVERY = 30 -- the reset countdown, in minutes at its finest

export type Row = { UserId: number, Name: string, Points: number }
export type Hall = { Week: number, LastWeek: { Row }, Top: { Row } }

-- What the server says (nil before it has said anything).
local function hall(): Hall?
	local data = GameState.GetJSON("HallOfFame")
	if type(data) ~= "table" or type(data.Week) ~= "number" then
		return nil
	end
	return {
		Week = data.Week,
		LastWeek = if type(data.LastWeek) == "table" then data.LastWeek else {},
		Top = if type(data.Top) == "table" then data.Top else {},
	}
end

-- This player's points this week (their profile) and their place on the board (the server's word).
local function mine(week: number?): (number, number?)
	local weekly = State.Profile and State.Profile.Weekly
	local points = 0
	if type(weekly) == "table" and type(weekly.Points) == "number" and (week == nil or weekly.Week == week) then
		points = weekly.Points
	end
	local rank = player:GetAttribute("PP_WeeklyRank")
	return points, if type(rank) == "number" and rank > 0 then rank else nil
end

local function resetsIn(week: number): string
	return "RESETS IN " .. WeeklyLogic.ResetsIn(WeeklyLogic.WeekEnd(week) - workspace:GetServerTimeNow())
end

local function text(props: { [string]: any }): TextLabel
	local defaults: { [string]: any } = {
		Font = Theme.Fonts.Display,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for key, value in props do
		defaults[key] = value
	end
	return UIKit.Label(defaults)
end

-- The board ----------------------------------------------------------------------------------------

-- Pixels on the board's face: World/HallOfFame's 14.4 x 11.2 stud screen at 40 per stud.
local BOARD_PIXELS = Vector2.new(576, 448)
local BOARD_ROW = 29

-- Draws the board into `gui` (the screen's SurfaceGui); returns what redraws it with the board,
-- this player's points and place. (Tools draw it this way too, to check every line fits.)
function HallOfFameController.BuildBoard(gui: Instance): (data: Hall?, points: number, rank: number?) -> ()
	local width = BOARD_PIXELS.X
	text({
		Name = "Title",
		Text = "📈 THIS WEEK'S TOP 10",
		TextSize = 36,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.fromOffset(width - 32, 44),
		TextColor3 = GOLD,
		Parent = gui,
		Children = { UIKit.TextStroke(0.4) },
	})
	local rows = {}
	for index = 1, WeeklyLogic.BoardSize do
		local y = 56 + (index - 1) * BOARD_ROW
		rows[index] = {
			rank = text({
				Name = `Rank{index}`,
				TextSize = 24,
				TextXAlignment = Enum.TextXAlignment.Right,
				Position = UDim2.fromOffset(12, y),
				Size = UDim2.fromOffset(62, BOARD_ROW),
				Parent = gui,
			}),
			name = text({
				Name = `Name{index}`,
				TextSize = 24,
				Position = UDim2.fromOffset(88, y),
				Size = UDim2.fromOffset(326, BOARD_ROW),
				Parent = gui,
			}),
			points = text({
				Name = `Points{index}`,
				TextSize = 24,
				TextXAlignment = Enum.TextXAlignment.Right,
				Position = UDim2.fromOffset(414, y),
				Size = UDim2.fromOffset(width - 414 - 18, BOARD_ROW),
				Parent = gui,
			}),
		}
	end
	local you = text({
		Name = "You",
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(16, 352),
		Size = UDim2.fromOffset(width - 32, 38),
		TextColor3 = Theme.Colors.Yellow,
		Parent = gui,
		Children = { UIKit.TextStroke(0.4) },
	})
	local resets = text({
		Name = "Resets",
		TextSize = 20,
		Position = UDim2.fromOffset(18, 400),
		Size = UDim2.fromOffset(200, 34),
		TextColor3 = Theme.Colors.TextDim,
		Parent = gui,
	})
	text({
		Name = "Rules",
		Text = WeeklyLogic.RulesText(),
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(218, 400),
		Size = UDim2.fromOffset(width - 218 - 18, 34),
		TextColor3 = Theme.Colors.TextDim,
		Parent = gui,
	})

	return function(data: Hall?, points: number, rank: number?)
		local top = if data then data.Top else {}
		for index, row in rows do
			local entry = top[index]
			local isMe = entry ~= nil and entry.UserId == player.UserId
			row.rank.Text = if entry then `#{index}` else ""
			row.name.Text = if entry
				then (if isMe then `▶ {entry.Name}` else entry.Name)
				elseif index == 1 then "Nobody yet: play a round!"
				else ""
			row.points.Text = if entry then WeeklyLogic.Pts(entry.Points) else ""
			local color = if isMe then Theme.Colors.Yellow elseif entry then Theme.Colors.Text else Theme.Colors.TextDim
			row.rank.TextColor3, row.name.TextColor3, row.points.TextColor3 = color, color, color
		end
		you.Text = WeeklyLogic.YouLine(rank, points)
		resets.Text = if data then resetsIn(data.Week) else ""
	end
end

local function bindBoard(part: BasePart)
	local gui = UIKit.new("SurfaceGui", {
		Name = "Screen_WeeklyBoard",
		Adornee = part,
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = BOARD_PIXELS.X / part.Size.X,
		LightInfluence = 0,
		Brightness = 1.4,
		MaxDistance = 250,
		ResetOnSpawn = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local draw = HallOfFameController.BuildBoard(gui)
	local function redraw()
		local data = hall()
		draw(data, mine(data and data.Week))
	end
	GameState.Changed("HallOfFame", redraw)
	State.ProfileChanged:Connect(redraw)
	player:GetAttributeChangedSignal("PP_WeeklyRank"):Connect(redraw)
	part.Destroying:Connect(function()
		gui:Destroy()
	end)
	task.spawn(function()
		while gui.Parent do
			task.wait(REFRESH_EVERY)
			redraw()
		end
	end)
	redraw()
end

-- The THIS WEEK window --------------------------------------------------------------------------------

local modal: Modal.Modal
local list: ScrollingFrame

local function clear(frame: Instance)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- One line of the window: a place, a name and points (or one text across).
local function windowRow(order: number, rank: string, name: string, points: string, color: Color3, card: boolean)
	local touch = UIKit.IsTouch()
	local row = if card
		then UIKit.Panel({
			Name = `Row{order}`,
			Size = UDim2.new(1, -8, 0, 44),
			LayoutOrder = order,
			CornerRadius = 12,
			Parent = list,
		}, Theme.Colors.Card, Theme.Colors.PanelDark)
		else UIKit.new("Frame", {
			Name = `Row{order}`,
			Size = UDim2.new(1, -8, 0, 40),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = list,
		})
	local size = if touch then 24 else 22
	text({
		Name = "Rank",
		Text = rank,
		TextSize = size,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(0, 62, 1, 0),
		Parent = row,
	})
	text({
		Name = "Name",
		Text = name,
		TextSize = size,
		TextColor3 = color,
		Position = UDim2.fromOffset(80, 0),
		Size = UDim2.new(1, -80 - 150, 1, 0),
		Parent = row,
	})
	text({
		Name = "Points",
		Text = points,
		TextSize = size,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 0),
		Size = UDim2.new(0, 136, 1, 0),
		Parent = row,
	})
end

local function note(order: number, words: string, color: Color3, size: number?)
	local touch = UIKit.IsTouch()
	text({
		Name = `Note{order}`,
		Text = words,
		TextSize = size or (if touch then Theme.Touch.MinText + 2 else 19),
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = color,
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = list,
	})
end

local function renderWindow()
	clear(list)
	local data = hall()
	local points, rank = mine(data and data.Week)
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local top = if data then data.Top else {}
	if #top == 0 then
		note(nextOrder(), "Nobody's on the board yet this week: play a round!", Theme.Colors.TextDim)
	end
	for index, entry in top do
		local isMe = entry.UserId == player.UserId
		windowRow(
			nextOrder(),
			`#{index}`,
			if isMe then `▶ {entry.Name}` else entry.Name,
			WeeklyLogic.Pts(entry.Points),
			if isMe then Theme.Colors.Yellow else Theme.Colors.Text,
			true
		)
	end
	note(nextOrder(), WeeklyLogic.YouLine(rank, points), Theme.Colors.Yellow, if UIKit.IsTouch() then 26 else 24)
	if data then
		note(nextOrder(), resetsIn(data.Week), Theme.Colors.Text)
	end
	note(nextOrder(), WeeklyLogic.RulesText(), Theme.Colors.TextDim)
	note(nextOrder(), "The TOP 3 on Monday get a statue in the HALL OF FAME!", Theme.Colors.TextDim)
	local last = if data then data.LastWeek else {}
	if #last > 0 then
		note(nextOrder(), "🏆 LAST WEEK", GOLD, if UIKit.IsTouch() then 26 else 24)
		for place, entry in last do
			windowRow(
				nextOrder(),
				MEDALS[place] or `#{place}`,
				entry.Name,
				WeeklyLogic.Pts(entry.Points),
				Theme.Colors.Text,
				false
			)
		end
	end
end

-- The chip ---------------------------------------------------------------------------------------------

function HallOfFameController.Start(context)
	modal = Modal.new(context.Overlay, "THIS WEEK", "📈", Vector2.new(620, 600))
	list = UIKit.new("ScrollingFrame", {
		Name = "Board",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = modal.Content,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 6), UIKit.Padding(4) },
	})
	modal.Opened:Connect(renderWindow)

	local chip = LobbyRibbon.Add(context, {
		Name = "Weekly",
		Priority = 4,
		OnClick = function()
			modal:Toggle()
		end,
	})
	local function refresh()
		local data = hall()
		if not data then
			chip:Set("", "") -- nothing to show before the server's first word
		else
			local points, rank = mine(data.Week)
			chip:Set("📈", WeeklyLogic.ChipText(rank, points))
		end
		if modal.IsOpen then
			renderWindow()
		end
	end
	GameState.Changed("HallOfFame", refresh)
	State.ProfileChanged:Connect(refresh)
	player:GetAttributeChangedSignal("PP_WeeklyRank"):Connect(refresh)
	State.OpenScreen:Connect(function(name)
		if name == "Weekly" then
			modal:Toggle()
		end
	end)
	refresh()

	-- The board, whenever the lobby's Hall of Fame has been built (it builds over a few seconds).
	for _, part in CollectionService:GetTagged("WeeklyBoard") do
		task.spawn(bindBoard, part :: BasePart)
	end
	CollectionService:GetInstanceAddedSignal("WeeklyBoard"):Connect(function(part)
		bindBoard(part :: BasePart)
	end)
end

return HallOfFameController
