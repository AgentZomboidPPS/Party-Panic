-- Party Cups on screen (owner, asked "If you could do 5 things to keep players addicted what would
-- you do?", got Party Cups among the five, then: "Can you work on all of that? this wont mess with
-- what the other workers are working on right?"): every 5 rounds add up into a cup with a podium,
-- and the champion wears a crown in the lobby until the next cup ends. The server runs the cups
-- (Services/CupService, GameState "Cup"); this only shows them.
--   * The chip in the lobby's row (UI/LobbyRibbon, priority 2): "🏆 CUP 3/5 · 2ND", the cup's next
--     round and your place. Tapping it opens the standings window: everyone's points, what a round
--     pays, who wears the crown and your own cup record.
--   * After each round of a cup, back in the lobby, a short look at the standings (the top three
--     and you, with the points that round gave) for a few seconds under the chip's row. It waits
--     its turn: never over the results card, the vote, a window or a level-up card (which goes
--     first), and on phones not over the first-join tip; it takes no taps, and if there's no calm
--     moment for it, the chip has the news.
--   * After a cup's 5th round, its podium: the top three on gold, silver and bronze steps, the
--     prizes, the crown, confetti and a fanfare. It takes over from the results card just before
--     that card's time is up, so a level-up card from the same round waits for it (and shows after
--     the next round if the lobby has no time left for it), and it closes when the vote starts.
-- Bots are in the standings and can stand on the podium (marked 🤖); only people win prizes.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameState = require(Shared.GameState)
local PartyCup = require(Shared.Logic.PartyCup)
local Placement = require(Shared.Logic.Placement)

local AudioController = require(script.Parent.AudioController)
local Participants = require(script.Parent.Parent.Participants)
local State = require(script.Parent.Parent.State)
local LobbyRibbon = require(script.Parent.Parent.UI.LobbyRibbon)
local Modal = require(script.Parent.Parent.UI.Modal)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local CupController = {}

type Row = { UserId: number, Name: string, Points: number, IsBot: boolean, Place: number, Gain: number }
type Cup = {
	Number: number,
	Round: number,
	Of: number,
	Played: number,
	Done: boolean?,
	EndedAt: number?,
	Standings: { Row },
	Champion: { UserId: number, Name: string, Cup: number }?,
	Last: { Number: number, Podium: { Row } }?,
}

local MEDALS = { "🥇", "🥈", "🥉" }
local CALM = { Waiting = true, Intermission = true, Cleanup = true } -- the lobby, between the results and the vote
local GONE = { Voting = true, Preparing = true, InRound = true } -- too late for a moment or a podium
local FRESH = 40 -- seconds: older news (someone who just joined) isn't shown as a moment
local MOMENT_BEAT = 0.6 -- after the lobby returns: a level-up card claims the spot first
local MOMENT_TIME = 4.5
local MOMENT_MIN = 2 -- seconds before the vote: a moment doesn't start with less
local PODIUM_LEAD = 0.35 -- the podium takes over this long before the results card's time is up
local PODIUM_TIME = 6

-- Scaled units (UIKit.AutoScale: phones get 0.62 points per unit).
-- The moment sits just under the lobby's chips (LobbyRibbon: their row ends 80 units down on
-- phones, 124 on PC, in a holder 4 or 10 points from the top).
local MOMENT_W, MOMENT_ROW, MOMENT_RESULT_W = 500, 30, 150
local MOMENT_TOP = { Touch = 90, Pc = 134 }
local PODIUM_SIZE = Vector2.new(780, 470)
local STANDINGS_SIZE = Vector2.new(640, 560)
local STEP_HEIGHTS = { 84, 64, 50 }
local STEP_W, STEP_GAP, STEP_FLOOR = 210, 18, 246 -- the steps' bottom, in the window's content
local STEP_COLORS = {
	{ Color3.fromRGB(255, 220, 90), Color3.fromRGB(232, 150, 30) },
	{ Color3.fromRGB(228, 232, 245), Color3.fromRGB(150, 160, 186) },
	{ Color3.fromRGB(244, 170, 110), Color3.fromRGB(176, 98, 48) },
}
local CONFETTI = {
	Color3.fromRGB(255, 90, 140),
	Color3.fromRGB(90, 190, 255),
	Color3.fromRGB(255, 210, 70),
	Color3.fromRGB(150, 110, 255),
	Color3.fromRGB(110, 230, 140),
}

local touch = false
local hud: Instance
local chip: LobbyRibbon.Chip
local cup: Cup? = nil
local windowOpen = false

local moment: Frame
local momentPending: Cup? = nil
local momentToken = 0

local standingsModal: Modal.Modal
local standingsBody: Frame
local podiumModal: Modal.Modal
local podiumBody: Frame
local podiumLayer: Frame
local podiumPending: Cup? = nil
local podiumToken = 0
local podiumShown: { [number]: boolean } = {}
local resultsSince = 0

local function me(): number
	return Players.LocalPlayer.UserId
end

local function myRow(data: Cup?): Row?
	if not data then
		return nil
	end
	for _, row in data.Standings do
		if row.UserId == me() then
			return row
		end
	end
	return nil
end

local function fresh(data: Cup): boolean
	return workspace:GetServerTimeNow() - (data.EndedAt or 0) < FRESH
end

local function placeText(place: number): string
	return MEDALS[place] or Placement.Ordinal(place)
end

-- A name for a list row (RichText): bots a little softer, like the results card; yours says so.
local function rowName(row: Row): string
	local name = Participants.ListName(row.Name, row.IsBot)
	return if row.UserId == me() then `{name} (you)` else name
end

local function pointsText(row: Row): string
	local points = `{row.Points} {if row.Points == 1 then "pt" else "pts"}`
	return if row.Gain > 0 then `{points}  +{row.Gain}` else points
end

local function clear(frame: Instance)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function label(props: { [string]: any }): TextLabel
	props.BackgroundTransparency = 1
	return UIKit.Label(props)
end

-- A window's title (UI/Modal draws it as "<icon>  <title>" in its title bar): this cup's number.
local function setTitle(window: Modal.Modal, text: string)
	local bar = window.Window:FindFirstChild("TitleBar")
	local title = bar and bar:FindFirstChildOfClass("TextLabel")
	if title then
		title.Text = text
	end
end

-- One standings line: place and name on the left, points on the right (both whole: a long name
-- gives way with "...").
local function standingRow(parent: Instance, row: Row, order: number, height: number, text: number, resultWidth: number)
	local mine = row.UserId == me()
	local color = if mine then Theme.Colors.Yellow else Theme.Colors.Text
	local frame = UIKit.new("Frame", {
		Name = "Row",
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = if mine then 0.15 else 0.45,
		LayoutOrder = order,
		Parent = parent,
		Children = { UIKit.Corner(10) },
	})
	local name = label({
		Name = "Name",
		Text = `{placeText(row.Place)}  {rowName(row)}`,
		RichText = true,
		TextSize = text,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = color,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -(resultWidth + 24), 1, 0),
		Parent = frame,
	})
	name:SetAttribute("PP_TruncateOk", true) -- a long name may end in "..."
	label({
		Name = "Points",
		Text = pointsText(row),
		TextSize = text,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = color,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.new(0, resultWidth, 1, 0),
		Parent = frame,
	})
	return frame
end

-- The chip ---------------------------------------------------------------------------------------

local function refreshChip()
	local data = cup
	if not data then
		chip:Set("🏆", "")
		return
	end
	local text = `CUP {data.Round}/{data.Of}`
	local mine = myRow(data)
	if mine then
		text ..= ` · {string.upper(Placement.Ordinal(mine.Place))}`
	end
	chip:Set("🏆", text)
end

-- The standings window -----------------------------------------------------------------------------

local function headline(data: Cup): string
	if data.Done then
		return "FINAL STANDINGS"
	elseif data.Played == 0 then
		return `{data.Of} ROUNDS, STARTING NEXT ROUND`
	end
	return `ROUND {data.Round} OF {data.Of} IS NEXT`
end

local function crownLine(data: Cup): string
	local champion = data.Champion
	if champion then
		local who = if champion.UserId == me() then "you" else champion.Name
		return `👑 Crown: {who} (won PARTY CUP #{champion.Cup})`
	end
	local lastCup = data.Last
	local winner = lastCup and lastCup.Podium[1]
	if lastCup and winner then
		return `🏆 PARTY CUP #{lastCup.Number} went to {winner.Name}`
	end
	return "👑 The champion wears a crown until the next cup ends"
end

local function recordLine(): string
	local profile = State.Profile
	local cups = profile and profile.Cups
	if type(cups) == "table" and (cups.Played or 0) > 0 then
		local won = cups.Wins or 0
		local podiums = cups.Podiums or 0
		return `Your cups: {cups.Played} played · {won} won · {podiums} {if podiums == 1 then "podium" else "podiums"}`
	end
	return "Your cups: finish one to start your record!"
end

local function fillStandings()
	local data = cup
	clear(standingsBody)
	setTitle(standingsModal, if data then `🏆  PARTY CUP #{data.Number}` else "🏆  PARTY CUP")
	label({
		Name = "Headline",
		Text = if data then headline(data) else "STARTS AFTER THE NEXT ROUND",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		TextWrapped = false,
		Size = UDim2.new(1, 0, 0, 34),
		Parent = standingsBody,
		Children = { UIKit.TextStroke(0.2) },
	})
	local rules = label({
		Name = "Rules",
		Text = `Every round: 1st 10 pts, 2nd 8, 3rd 6, then 5, 4, 3, 2, 1.\nThe top 3 win {Theme.CoinIcon} 5 · 3 · 2, and 1st wears the crown 👑`,
		TextSize = Theme.Touch.MinText,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 0, 48),
		Parent = standingsBody,
	})
	rules:SetAttribute("PP_Lines", 2)
	local list = UIKit.new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(0, 90),
		Size = UDim2.new(1, 0, 1, -(90 + 62)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = standingsBody,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 6), UIKit.Padding(2, 4) },
	})
	local rows = if data then data.Standings else {}
	for index, row in rows do
		standingRow(list, row, index, 40, 21, 150).Size = UDim2.new(1, -10, 0, 40)
	end
	if not myRow(data) then
		local note = label({
			Name = "JoinNote",
			Text = if data and not data.Done
				then "You're not in this cup yet: play a round to join it!"
				else "Play a round to join the next PARTY CUP!",
			TextSize = 20,
			TextColor3 = Theme.Colors.Yellow,
			Size = UDim2.new(1, -16, 0, 40),
			LayoutOrder = 0,
			Parent = list,
		})
		note:SetAttribute("PP_Lines", 2)
	end
	local footer = label({
		Name = "Footer",
		Text = `{if data then crownLine(data) else "👑 The champion wears a crown until the next cup ends"}\n{recordLine()}`,
		TextSize = Theme.Touch.MinText,
		TextColor3 = Theme.Colors.TextDim,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 56),
		Parent = standingsBody,
	})
	footer:SetAttribute("PP_Lines", 2)
end

-- Opens the standings window (the chip does; so does the client harness).
function CupController.OpenStandings()
	fillStandings()
	standingsModal:Open()
end

-- The moment after a round ----------------------------------------------------------------------

local function spotFree(): boolean
	return CALM[State.Phase()] == true
		and not windowOpen
		and Players.LocalPlayer:GetAttribute("PP_Celebrating") ~= true
		and not (touch and hud:GetAttribute("PP_TipShowing") == true)
		and hud:GetAttribute("PP_TipsAside") ~= true
end

local function hideMoment()
	momentToken += 1
	moment.Visible = false
end

local function fillMoment(data: Cup)
	local panel = moment:FindFirstChild("Panel") :: Frame
	local rowsFrame = panel:FindFirstChild("Rows") :: Frame
	clear(rowsFrame)
	local title = panel:FindFirstChild("Title") :: TextLabel
	title.Text = `🏆 PARTY CUP · {data.Played} OF {data.Of} PLAYED` -- (the chip above says the next one)
	local shown = 0
	local mineShown = false
	for _, row in data.Standings do
		if shown >= 3 then
			break
		end
		shown += 1
		mineShown = mineShown or row.UserId == me()
		standingRow(rowsFrame, row, shown, MOMENT_ROW, 21, MOMENT_RESULT_W)
	end
	local mine = myRow(data)
	if mine and not mineShown then
		shown += 1
		standingRow(rowsFrame, mine, shown, MOMENT_ROW, 21, MOMENT_RESULT_W)
	end
	local left = data.Of - data.Played
	local footer = panel:FindFirstChild("Footer") :: TextLabel
	footer.Text = if left == 1
		then `Last round next! The top 3 win {Theme.CoinIcon}`
		else `{left} rounds to go. The top 3 win {Theme.CoinIcon}`
	local rowsHeight = shown * MOMENT_ROW + math.max(0, shown - 1) * 4
	rowsFrame.Size = UDim2.new(1, -28, 0, rowsHeight)
	footer.Position = UDim2.fromOffset(16, 50 + rowsHeight + 8)
	panel.Size = UDim2.fromOffset(MOMENT_W, 50 + rowsHeight + 8 + 26 + 12)
end

local function showMoment(data: Cup)
	fillMoment(data)
	moment.Visible = true
	UIKit.PopIn(moment:FindFirstChild("Panel") :: Frame, 0.35)
	momentToken += 1
	local token = momentToken
	task.delay(MOMENT_TIME, function()
		if momentToken == token then
			hideMoment()
		end
	end)
end

-- Shows the waiting moment if the spot is free and there's time for it before the vote.
local function pumpMoment()
	local data = momentPending
	if not data then
		return
	end
	if not fresh(data) then
		momentPending = nil
		return
	end
	if State.Phase() == "Intermission" and GameState.TimeLeft() < MOMENT_MIN then
		return
	end
	if not spotFree() then
		return
	end
	momentPending = nil
	showMoment(data)
end

-- Takes the moment away when its spot is taken (a level-up card, the tip, a window).
local function spotChanged()
	if moment.Visible and not spotFree() then
		hideMoment()
	elseif momentPending then
		pumpMoment()
	end
end

local function buildMoment(context)
	local top = if touch then MOMENT_TOP.Touch else MOMENT_TOP.Pc
	moment = UIKit.new("Frame", {
		Name = "CupMoment",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, if touch then 4 else 10),
		Size = UDim2.fromOffset(MOMENT_W, top + 260),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = context.Hud,
	})
	UIKit.AutoScale(moment)
	local panel = UIKit.Panel({
		Name = "Panel",
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.fromOffset(MOMENT_W, 200),
		CornerRadius = 22,
		Parent = moment,
	}, Color3.fromRGB(96, 62, 190), Theme.Colors.PanelDark)
	panel:SetAttribute("PP_Popup", true) -- a few seconds in the lobby; nothing on it takes taps
	local rim = panel:FindFirstChildOfClass("UIStroke") :: UIStroke
	rim.Color = Theme.Colors.Yellow
	rim.Transparency = 0.2
	rim.Thickness = 3
	label({
		Name = "Title",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		TextWrapped = false,
		TextColor3 = Theme.Colors.Yellow,
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -32, 0, 34),
		Parent = panel,
		Children = { UIKit.TextStroke(0.1) },
	})
	UIKit.new("Frame", {
		Name = "Rows",
		Position = UDim2.fromOffset(14, 50),
		Size = UDim2.new(1, -28, 0, 100),
		BackgroundTransparency = 1,
		Parent = panel,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 4) },
	})
	label({
		Name = "Footer",
		Text = "",
		TextSize = Theme.Touch.MinText + 1,
		TextWrapped = false,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(16, 160),
		Size = UDim2.new(1, -32, 0, 26),
		Parent = panel,
	})
end

-- The podium ---------------------------------------------------------------------------------------

-- Confetti over the window (clipped to it; ReducedEffects: a few pieces).
local function confetti()
	local count = if State.ReducedEffects() then 10 else 36
	for index = 1, count do
		local piece = UIKit.new("Frame", {
			Name = "Confetti",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.03 + math.random() * 0.94, -0.03 - math.random() * 0.25),
			Size = UDim2.fromOffset(math.random(9, 13), math.random(14, 20)),
			Rotation = math.random(0, 360),
			BackgroundColor3 = CONFETTI[(index % #CONFETTI) + 1],
			BorderSizePixel = 0,
			ZIndex = 40,
			Parent = podiumLayer,
		})
		local fall = 2 + math.random() * 1.6
		UIKit.Tween(piece, fall, {
			Position = UDim2.fromScale(piece.Position.X.Scale + (math.random() - 0.5) * 0.15, 0.98),
			Rotation = piece.Rotation + math.random(-540, 540),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(piece, fall + 0.2)
	end
end

-- One step of the podium: who's on it (if anyone), their points and prize, on a step as tall as
-- their place.
local function podiumStep(parent: Instance, row: Row?, slot: number, x: number)
	local width, floor = STEP_W, STEP_FLOOR
	local place = if row then row.Place else slot
	local tier = math.clamp(place, 1, 3)
	local height = STEP_HEIGHTS[tier]
	local colors = STEP_COLORS[tier]
	local step = UIKit.Panel({
		Name = `Step{slot}`,
		Position = UDim2.fromOffset(x, floor - height),
		Size = UDim2.fromOffset(width, height),
		CornerRadius = 14,
		ZIndex = 23,
		Parent = parent,
	}, colors[1], colors[2])
	label({
		Name = "Place",
		Text = string.upper(Placement.Ordinal(place)),
		Font = Theme.Fonts.Display,
		TextSize = if tier == 1 then 40 else 32,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 24,
		Parent = step,
		Children = { UIKit.TextStroke(0.1) },
	})
	if not row then
		return
	end
	local mine = row.UserId == me()
	local prize = if row.IsBot then 0 else PartyCup.PrizeFor(row.Place)
	-- From the step up: the prize, the points, the name, the medal (and the crown over a champion).
	-- The prize's line is kept for a bot too, so the higher step always has the higher name.
	local y = floor - height - 6 - 28
	if prize > 0 then
		label({
			Name = "Prize",
			Text = `+{prize} {Theme.CoinIcon}`,
			Font = Theme.Fonts.Display,
			TextSize = 22,
			TextWrapped = false,
			TextColor3 = Theme.Colors.Yellow,
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(width, 28),
			ZIndex = 24,
			Parent = parent,
			Children = { UIKit.TextStroke(0.2) },
		})
	end
	y -= 26
	label({
		Name = "Points",
		Text = `{row.Points} pts`,
		TextSize = 20,
		TextWrapped = false,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(width, 26),
		ZIndex = 24,
		Parent = parent,
	})
	y -= 32
	local name = label({
		Name = "Name",
		Text = if mine then "YOU" else row.Name,
		Font = Theme.Fonts.Display,
		TextSize = 24,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = if mine then Theme.Colors.Yellow else Theme.Colors.Text,
		Position = UDim2.fromOffset(x + 4, y),
		Size = UDim2.fromOffset(width - 8, 32),
		ZIndex = 24,
		Parent = parent,
		Children = { UIKit.TextStroke(0.2) },
	})
	name:SetAttribute("PP_TruncateOk", true)
	y -= 44
	label({
		Name = "Medal",
		Text = if row.Place == 1 and not row.IsBot then "👑🥇" else MEDALS[tier],
		TextSize = 36,
		TextWrapped = false,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(width, 44),
		ZIndex = 24,
		Parent = parent,
	})
end

local function fillPodium(data: Cup)
	clear(podiumBody)
	setTitle(podiumModal, `🏆  PARTY CUP #{data.Number} · FINAL`)
	-- The steps, in the middle: 2nd on the left, 1st in the middle, 3rd on the right.
	local steps = UIKit.new("Frame", {
		Name = "Steps",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(3 * STEP_W + 2 * STEP_GAP, STEP_FLOOR),
		BackgroundTransparency = 1,
		ZIndex = 23,
		Parent = podiumBody,
	})
	for position, slot in { 2, 1, 3 } do
		podiumStep(steps, data.Standings[slot], slot, (position - 1) * (STEP_W + STEP_GAP))
	end
	local floor = STEP_FLOOR
	-- You, then the crown, then what's next.
	local mine = myRow(data)
	local yours
	if mine then
		local prize = PartyCup.PrizeFor(mine.Place)
		if mine.Place == 1 then
			yours = `👑 You won the PARTY CUP! +{prize} {Theme.CoinIcon}`
		elseif prize > 0 then
			yours = `{MEDALS[mine.Place]} You finished {Placement.Ordinal(mine.Place)}! +{prize} {Theme.CoinIcon}`
		else
			yours = `You finished {Placement.Ordinal(mine.Place)} with {mine.Points} pts. Next cup!`
		end
	else
		yours = "Join the next PARTY CUP: it starts now!"
	end
	label({
		Name = "Yours",
		Text = yours,
		Font = Theme.Fonts.Display,
		TextSize = 26,
		TextWrapped = false,
		TextColor3 = if mine and mine.Place <= 3 then Theme.Colors.Yellow else Theme.Colors.Text,
		Position = UDim2.fromOffset(0, floor + 10),
		Size = UDim2.new(1, 0, 0, 36),
		ZIndex = 24,
		Parent = podiumBody,
		Children = { UIKit.TextStroke(0.2) },
	})
	-- Where the crown goes (the server has no toasts for it: this says it). Champion is still last
	-- cup's winner here: the crown passes as the podium is paid.
	local winner = data.Standings[1]
	local wore = data.Champion ~= nil and data.Champion.UserId == me()
	local crownText
	if not winner then
		crownText = ""
	elseif winner.IsBot then
		crownText = if wore
			then "👑 Your crown comes off: a bot won. Win it back next cup!"
			else `{winner.Name} won it: no crown this time. Beat the bots next cup!`
	elseif winner.UserId == me() then
		crownText = if wore
			then "👑 You keep your crown until the next cup ends!"
			else "👑 Your crown is on! Wear it in the lobby until the next cup ends."
	else
		crownText = if wore
			then `👑 Your crown goes to {winner.Name}. Win it back next cup!`
			else `👑 {winner.Name} wears the crown until the next cup ends!`
	end
	local crownLabel = label({
		Name = "Crown",
		Text = crownText,
		TextSize = 20,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(0, floor + 48),
		Size = UDim2.new(1, 0, 0, 28),
		ZIndex = 24,
		Parent = podiumBody,
	})
	crownLabel:SetAttribute("PP_TruncateOk", true) -- (a long name)
	label({
		Name = "Next",
		Text = `A new PARTY CUP starts now: {data.Of} rounds!`,
		TextSize = Theme.Touch.MinText,
		TextWrapped = false,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(0, floor + 78),
		Size = UDim2.new(1, 0, 0, 26),
		ZIndex = 24,
		Parent = podiumBody,
	})
end

local function closePodium()
	podiumToken += 1
	podiumModal:Close()
end

local function openPodium(data: Cup)
	podiumShown[data.Number] = true
	hideMoment()
	-- While it's up (other features can hold their own pop-ups for it, as for a level-up card).
	Players.LocalPlayer:SetAttribute("PP_CupPodium", true)
	podiumModal:Open()
	fillPodium(data)
	confetti()
	AudioController.Play("Victory")
	podiumToken += 1
	local token = podiumToken
	task.delay(PODIUM_TIME, function()
		if podiumToken == token then
			closePodium()
		end
	end)
end

-- Opens the waiting podium when its time comes: just before the results card's time is up (it
-- takes over from it), or now in the lobby.
local function pumpPodium()
	local data = podiumPending
	if not data then
		return
	end
	local phase = State.Phase()
	if phase == "InRound" then
		return -- the cup's last round is about to show its results: they come first
	end
	if not fresh(data) or GONE[phase] then
		podiumPending = nil -- the vote or the next round has the screen: too late
		return
	end
	if phase == "Results" then
		local left = GameState.TimeLeft()
		local justBegan = os.clock() - resultsSince < 0.5
		if left > PODIUM_LEAD or (justBegan and left <= 0) then
			podiumToken += 1
			local token = podiumToken
			task.delay(math.max(0.2, left - PODIUM_LEAD), function()
				if podiumToken == token then
					pumpPodium()
				end
			end)
			return
		end
	elseif not CALM[phase] then
		return
	end
	podiumPending = nil
	openPodium(data)
end

-- The cup's news --------------------------------------------------------------------------------

local function onCup(data: Cup?, firstLook: boolean?)
	local before = cup
	cup = data
	refreshChip()
	if standingsModal.IsOpen then
		fillStandings()
	end
	if not data or firstLook then
		return -- (what was there when this screen started isn't news)
	end
	if data.Done then
		if not podiumShown[data.Number] and fresh(data) then
			podiumPending = data
			momentPending = nil
			pumpPodium()
		end
	elseif
		data.Played > 0
		and (not before or data.Number ~= before.Number or data.Played ~= before.Played)
		and fresh(data)
	then
		momentPending = data
		if moment.Visible then
			fillMoment(data)
		end
	end
end

local function readCup(): Cup?
	local data = GameState.GetJSON("Cup")
	if type(data) ~= "table" or type(data.Standings) ~= "table" then
		return nil
	end
	return data :: Cup
end

-- What the cup's screens show now (the client harness reads it).
function CupController.Status()
	local panel = moment and moment:FindFirstChild("Panel")
	local title = panel and panel:FindFirstChild("Title")
	return {
		Chip = if chip then chip.Button.Text else "",
		ChipShown = chip ~= nil and chip.Button.Visible,
		Moment = if moment and moment.Visible and title then (title :: TextLabel).Text else "",
		Podium = podiumModal ~= nil and podiumModal.IsOpen,
		Standings = standingsModal ~= nil and standingsModal.IsOpen,
	}
end

function CupController.Start(context)
	touch = UIKit.IsTouch()
	hud = context.Hud
	chip = LobbyRibbon.Add(context, { Name = "Cup", Priority = 2, OnClick = CupController.OpenStandings })
	buildMoment(context)

	standingsModal = Modal.new(context.Overlay, "PARTY CUP", "🏆", STANDINGS_SIZE)
	standingsBody = UIKit.new("Frame", {
		Name = "Cup",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = standingsModal.Content,
	})
	podiumModal = Modal.new(context.Overlay, "PARTY CUP", "🏆", PODIUM_SIZE)
	podiumModal.Closed:Connect(function()
		Players.LocalPlayer:SetAttribute("PP_CupPodium", nil)
	end)
	podiumBody = UIKit.new("Frame", {
		Name = "Podium",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = podiumModal.Content,
	})
	podiumLayer = UIKit.new("Frame", {
		Name = "ConfettiLayer",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 40,
		Parent = podiumModal.Window,
		Children = { UIKit.Corner(22) },
	})

	GameState.Changed("Cup", function()
		onCup(readCup())
	end)
	GameState.Changed("Phase", function(phase)
		if phase == "Results" then
			resultsSince = os.clock()
		end
		if GONE[phase] then
			momentPending = nil
			hideMoment()
			if podiumModal.IsOpen then
				closePodium() -- the vote has the screen now
			end
		end
		if CALM[phase] then
			task.delay(MOMENT_BEAT, pumpMoment)
		end
		pumpPodium()
	end)
	GameState.Changed("PhaseEndsAt", function()
		if podiumPending then
			pumpPodium()
		end
	end)
	Players.LocalPlayer:GetAttributeChangedSignal("PP_Celebrating"):Connect(spotChanged)
	context.Hud:GetAttributeChangedSignal("PP_TipShowing"):Connect(spotChanged)
	context.Hud:GetAttributeChangedSignal("PP_TipsAside"):Connect(spotChanged)
	Modal.AnyOpenChanged:Connect(function(open)
		windowOpen = open
		if open then
			hideMoment()
		else
			task.delay(0.4, spotChanged)
		end
	end)
	State.ProfileChanged:Connect(function()
		if standingsModal.IsOpen then
			fillStandings() -- your cup record
		end
	end)
	onCup(readCup(), true)
end

return CupController
