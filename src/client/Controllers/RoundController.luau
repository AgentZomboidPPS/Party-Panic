-- Rules card, countdown and in-round HUD (design doc §12): objective, controls and duration before
-- the round; then a live mini-leaderboard, team highlights and an "you're out" prompt. Bots are in
-- the standings and get team outlines like everyone else (Participants).
-- Phones (owner: "Wtf is this mobile Ui lol"): the rules card sits in the upper middle under the
-- tip, sized for a phone; the standings are a strip under the banner (below); the "you're out" pill
-- sits low in the middle.
-- The rules card and the 3-2-1 are for the round's players only: someone sitting it out (or who
-- arrived mid-round) watches from the lobby, with a line under the banner (HudController).
--
-- A small ✕ in the card's top right corner closes it (owner: "Let players close the instructions
-- if they want. add a close button top right. Maybe a small X."): just for that player and that
-- round (it comes back for the next one), and the round starts on time for everyone, with the
-- 3-2-1 as usual. A closed card counts as not up: the mode's HUD comes in (Kit/Api), every toast
-- shows (NotificationController) and the "Read the rules card" tip goes with it (OnboardingController).
-- The ✕ looks small (25 pt on phones) in a 44 pt tap area inside the card (on phones that's under
-- the tip and its Skip), clear of the menu column, the jump button and the MOVE stick.
--
-- In a team round the card says which team you're on (owner: "I couldnt tell what color I was on
-- prime cut."): a tab under it in your team's colour, "YOU'RE ON ★ RED" (or your role in a versus
-- game, "YOU'RE AN 🏹 ARCHER": Teams.YouAre), there from the moment the server puts you on a team.
-- It goes with the card (its ✕ too); the mode's own HUD carries the team on from the 3-2-1.
--
-- The ✕ was a near-black dot on the card (owner: "why are the close menu buttons and the invite
-- friend button so dark?"): it's the windows' bright red round ✕ now (UI/Modal: a red gradient,
-- a white ✕ with a text stroke and a white ring), with the same size and tap area as before.
--
-- The standings on phones (owner: "The standings on mobile takes way too much space. It has to be
-- centered."): one slim strip under the banner in the middle, for the round's players and anyone
-- watching: LIVE, then the top three (place, name, score), with you in third place if you're further
-- down ("6 You 4"). It's part of HudController's round status row, which shows it: for the round's
-- players in the status line's place once the line has faded, so the mode HUDs keep their spot; for
-- anyone watching above their line. PC keeps its board.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local GameDefinitions = require(Shared.GameDefinitions)
local GameState = require(Shared.GameState)
local RoundHud = require(Shared.Logic.RoundHud)
local Teams = require(Shared.Teams)

local Haptics = require(script.Parent.Parent.Haptics)
local Participants = require(script.Parent.Parent.Participants)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local RoundController = {}

local player = Players.LocalPlayer

local TEAM_COLORS = Teams.Colors

local rules: Frame -- the card (PC), or the frame it sits in (phones)
local rulesCard: Frame
local rulesFields: { [string]: TextLabel } = {}
local teamTab: Frame -- under the card in a team round: "YOU'RE ON ★ RED"
local teamTabLabel: TextLabel
local rulesClosed = false -- this player closed this round's card (its ✕); a new phase clears it
local countdown: TextLabel
local board: Frame
local boardRoot: GuiObject -- what shows and hides the board: it, or on phones its tap area
local outPanel: Frame

-- The ✕: its tap area and the round mark in it (scaled units). Phones: 44 pt and 25 pt.
local CLOSE_HIT, CLOSE_MARK = Theme.Touch.Target, 40
local PC_CLOSE_HIT, PC_CLOSE_MARK = 48, 34
-- The team tab under the card (scaled units): its gap, height, text size and side padding.
local TEAM_TAB_GAP, TEAM_TAB_HEIGHT, TEAM_TAB_TEXT, TEAM_TAB_PAD = 8, 50, 30, 26

local refreshBoard: () -> ()

-- Phones and tablets without a keyboard get their own layouts (fewer standings rows, smaller cards).
local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Closes the rules card for this player until the next round (its ✕; the round harness uses this
-- too). Nothing else changes: the round, its 3-2-1 and GO keep their times.
function RoundController.CloseRules()
	if rules and rules.Visible then
		rulesClosed = true
		rules.Visible = false
	end
end

-- The ✕ in the card's top right corner: a small round mark in a bigger, invisible tap area (the
-- name and category lines end before it).
local function buildClose(touch: boolean)
	local hit = if touch then CLOSE_HIT else PC_CLOSE_HIT
	local size = if touch then CLOSE_MARK else PC_CLOSE_MARK
	local button = UIKit.new("TextButton", {
		Name = "Close",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = if touch then UDim2.new(1, -2, 0, 2) else UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(hit, hit),
		Parent = rulesCard,
	})
	local press = UIKit.new("UIScale", { Scale = 1 })
	-- Drawn like the windows' X (UI/Modal, a UIKit.Button): white under a red gradient.
	UIKit.Label({
		Name = "Mark",
		Text = "X",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 24 else 20,
		TextWrapped = false,
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		Parent = button,
		Children = {
			UIKit.Round(),
			UIKit.Gradient(Theme.Colors.Red, Color3.fromRGB(190, 40, 60)),
			UIKit.Stroke(nil, 2, 0.55),
			UIKit.TextStroke(0.35),
			press,
		},
	})
	local function pressTo(value: number, time: number)
		UIKit.Tween(press, time, { Scale = value })
	end
	button.MouseEnter:Connect(function()
		pressTo(1.1, 0.12)
	end)
	button.MouseLeave:Connect(function()
		pressTo(1, 0.12)
	end)
	button.MouseButton1Down:Connect(function()
		pressTo(0.9, 0.06)
	end)
	button.MouseButton1Up:Connect(function()
		pressTo(1, 0.1)
	end)
	button.Activated:Connect(function()
		pressTo(1, 0.05) -- the card hides at once: the next round's ✕ mustn't still look pressed
		RoundController.CloseRules()
	end)
end

local function buildRules(parent: Instance)
	local touch = isTouch()
	if touch then
		-- Phones: in a frame at the top middle (scaled like the tip toast above it), so the card
		-- starts just under the tip on every screen. Shown for a few seconds before the round and
		-- nothing in its lower left takes taps (its one button, the ✕, is in the top right), so it
		-- may reach into the thumbstick's corner.
		rules = UIKit.new("Frame", {
			Name = "Rules",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 4),
			Size = UDim2.fromOffset(620, 104 + 262 + TEAM_TAB_GAP + TEAM_TAB_HEIGHT),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = parent,
		})
		UIKit.AutoScale(rules)
		rulesCard = UIKit.Panel({
			Name = "Card",
			Position = UDim2.fromOffset(0, 104),
			Size = UDim2.fromOffset(620, 262),
			CornerRadius = 24,
			Parent = rules,
		})
		rulesCard:SetAttribute("PP_Popup", true)
	else
		rules = UIKit.Panel({
			Name = "Rules",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.fromOffset(620, 330),
			CornerRadius = 26,
			Visible = false,
			Parent = parent,
		})
		UIKit.AutoScale(rules)
		rulesCard = rules
	end
	rulesFields.Icon = UIKit.Label({
		Text = "",
		TextSize = if touch then 60 else 80,
		TextWrapped = false,
		Position = if touch then UDim2.fromOffset(14, 10) else UDim2.fromOffset(20, 16),
		Size = if touch then UDim2.fromOffset(78, 72) else UDim2.fromOffset(110, 100),
		Parent = rulesCard,
	})
	rulesFields.Name = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 36 else 44,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = if touch then UDim2.fromOffset(100, 10) else UDim2.fromOffset(140, 18),
		-- Ends before the ✕'s tap area (the longest name, Mecha-Marathon, needs about 280 / 345).
		Size = if touch then UDim2.new(1, -178, 0, 44) else UDim2.new(1, -200, 0, 56),
		Parent = rulesCard,
		Children = { UIKit.TextStroke(0.2) },
	})
	rulesFields.Category = UIKit.Label({
		Text = "",
		TextSize = if touch then 20 else 22,
		TextWrapped = false,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = if touch then UDim2.fromOffset(102, 54) else UDim2.fromOffset(142, 74),
		Size = if touch then UDim2.new(1, -180, 0, 26) else UDim2.new(1, -160, 0, 30),
		Parent = rulesCard,
	})
	rulesFields.Objective = UIKit.Label({
		Text = "",
		TextSize = if touch then 21 else 28,
		TextScaled = not touch, -- PC: long objectives shrink a little to fit
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = if touch then UDim2.fromOffset(20, 90) else UDim2.fromOffset(28, 128),
		Size = if touch then UDim2.new(1, -40, 0, 70) else UDim2.new(1, -56, 0, 84),
		Parent = rulesCard,
		Children = if touch then {} else { UIKit.new("UITextSizeConstraint", { MaxTextSize = 28, MinTextSize = 20 }) },
	})
	local controls = UIKit.new("Frame", {
		Position = if touch then UDim2.fromOffset(14, 168) else UDim2.fromOffset(24, 222),
		Size = if touch then UDim2.new(1, -28, 0, 78) else UDim2.new(1, -48, 0, 84),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.3,
		Parent = rulesCard,
		Children = { UIKit.Corner(14) },
	})
	rulesFields.Controls = UIKit.Label({
		Text = "",
		TextSize = if touch then 20 else 21,
		TextColor3 = Theme.Colors.Yellow,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromScale(1, 1),
		Parent = controls,
		Children = { UIKit.Padding(if touch then 8 else 10, 16) },
	})
	buildClose(touch)

	-- The team tab, centred under the card (phones: in the frame's room below it, between the move
	-- stick's corner and the jump button; it's up only before the round, like the card).
	teamTab = UIKit.new("Frame", {
		Name = "YourTeam",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = if touch then UDim2.new(0.5, 0, 0, 104 + 262 + TEAM_TAB_GAP) else UDim2.new(0.5, 0, 1, TEAM_TAB_GAP),
		Size = UDim2.fromOffset(320, TEAM_TAB_HEIGHT),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Visible = false,
		Parent = rules,
		Children = { UIKit.Round(), UIKit.Stroke(Color3.new(1, 1, 1), 3, 0) },
	})
	teamTab:SetAttribute("PP_Popup", true)
	teamTabLabel = UIKit.Label({
		Name = "Text",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = TEAM_TAB_TEXT,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = teamTab,
		Children = { UIKit.TextStroke(0.05) },
	})

	countdown = UIKit.Label({
		Name = "Countdown",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 140,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(400, 200),
		Visible = false,
		Parent = parent,
		Children = { UIKit.TextStroke(0) },
	})
	countdown:SetAttribute("PP_Popup", true) -- a second or two before the round
	UIKit.AutoScale(countdown)
end

-- The team tab says the player's team (or role) once the server has put them on one, as wide as
-- its words, in a deep shade of the team's colour so the white words read on every team.
local function refreshTeamTab()
	local team = player:GetAttribute("PP_Team")
	local text = Teams.YouAre(team)
	local color = if text then TEAM_COLORS[team] else nil
	if not text or not color then
		teamTab.Visible = false
		return
	end
	teamTabLabel.Text = text
	local width = UIKit.TextWidth(text, TEAM_TAB_TEXT, Theme.Fonts.Display) + 2 * TEAM_TAB_PAD
	teamTab.Size = UDim2.fromOffset(math.ceil(width), TEAM_TAB_HEIGHT)
	teamTab.BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.3)
	if not teamTab.Visible then
		teamTab.Visible = true
		if rules.Visible then
			UIKit.PopIn(teamTab, 0.35)
		end
	end
end

local function showRules()
	local definition = GameDefinitions.Get(GameState.Get("GameId"))
	if not definition or rulesClosed then
		return
	end
	local info = GameDefinitions.Categories[definition.Category]
	rulesFields.Icon.Text = definition.Icon
	rulesFields.Name.Text = definition.Name
	rulesFields.Category.Text =
		`{info and info.Icon or ""} {definition.Category}  •  ⏱ {definition.Duration} seconds`
	rulesFields.Objective.Text = "🎯 " .. definition.Objective
	rulesFields.Controls.Text = "🎮 " .. definition.Controls
	local gradient = rulesCard:FindFirstChildOfClass("UIGradient")
	if gradient then
		local h, s, v = definition.Color:ToHSV()
		gradient.Color = ColorSequence.new(Color3.fromHSV(h, s * 0.8, v * 0.75), Color3.fromHSV(h, s, v * 0.35))
	end
	refreshTeamTab()
	rules.Visible = true
	UIKit.PopIn(rulesCard, 0.45)
end

local function flashCountdown(text: string, color: Color3)
	countdown.Text = text
	countdown.TextColor3 = color
	countdown.Visible = true
	UIKit.PopIn(countdown, 0.3)
	task.delay(0.85, function()
		if countdown.Text == text then
			countdown.Visible = false
		end
	end)
end

-- PC: the standings sit under the profile card, clear of the tips panel now that bots keep the
-- board full. Phones: the strip (scaled units, in the round status row; a long name is shortened).
local STRIP_H, STRIP_TEXT, STRIP_NAME = 40, 20, 92
local SCORE_MAX = 104 -- PC: the score column's widest (the board's rows are 246 wide)
local PLACE_COLORS = { Color3.fromRGB(255, 200, 60), Color3.fromRGB(205, 210, 225), Color3.fromRGB(215, 135, 75) }

local function buildBoard(parent: Instance)
	if isTouch() then
		-- (HudController's round status row: it moves what's under it down while this shows.)
		local row = parent:FindFirstChild("RoundStatus")
		local holder = row
		if not holder then
			holder = UIKit.new("Frame", {
				Name = "StandingsHolder",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0),
				Size = UDim2.fromOffset(620, STRIP_H + 8),
				BackgroundTransparency = 1,
				Parent = parent,
			})
			UIKit.AutoScale(holder)
		end
		board = UIKit.Panel({
			Name = "Leaderboard",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 4),
			Size = UDim2.fromOffset(300, STRIP_H),
			CornerRadius = STRIP_H / 2,
			Visible = false,
			Parent = holder,
		}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
		boardRoot = board
		return
	end
	board = UIKit.Panel({
		Name = "Leaderboard",
		Size = UDim2.fromOffset(270, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		CornerRadius = 18,
		Visible = false,
		Parent = parent,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 4), UIKit.Padding(10, 12) },
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	UIKit.AutoScale(board, 0.9)
	boardRoot = board
	-- Just under the profile card (HudController.ProfileHeight: 104 tall at y 12, scaled the same way).
	local function place()
		board.Position = UDim2.fromOffset(14, 12 + 104 * UIKit.CurrentScale() + 8)
	end
	board:SetAttribute("PP_UnderProfile", true)
	place()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(place)
end

local boardKey = ""

-- Phones: the strip's words, laid out left to right (LIVE, then each place's number, name and score).
local function drawStrip(entries: { any })
	local mine = nil
	for index, entry in entries do
		if entry.who.IsLocal then
			mine = index
		end
	end
	local shown = RoundHud.BoardPlaces(#entries, mine)
	local x = 8
	local live = UIKit.new("Frame", {
		Name = "Live",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, x, 0.5, 0),
		Size = UDim2.fromOffset(60, 26),
		BackgroundColor3 = Theme.Colors.Red,
		LayoutOrder = 0,
		Parent = board,
		Children = { UIKit.Round() },
	})
	UIKit.Label({
		Text = "LIVE",
		Font = Theme.Fonts.Display,
		TextSize = Theme.Touch.MinText,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = live,
	})
	x += 60 + 10
	for _, index in shown do
		local entry = entries[index]
		local who = entry.who
		local teamColor = TEAM_COLORS[entry.team]
		local name = if who.IsLocal then "You" else Participants.ListName(who.DisplayName, who.IsBot and not teamColor)
		local color = if who.IsLocal
			then Theme.Colors.Yellow
			elseif teamColor then teamColor
			elseif entry.alive then Theme.Colors.Text
			else Theme.Colors.TextDim
		local score = Participants.Escape(if entry.text ~= "" then entry.text else tostring(entry.score))
		local plainName = string.gsub(name, "<[^>]+>", "")
		local plainScore = string.gsub(score, "<[^>]+>", "")
		local nameWidth = math.min(STRIP_NAME, math.ceil(UIKit.TextWidth(plainName, STRIP_TEXT, Theme.Fonts.Bold)) + 2)
		local scoreWidth = math.min(80, math.ceil(UIKit.TextWidth(plainScore, STRIP_TEXT, Theme.Fonts.Display)) + 2)
		local place = UIKit.new("Frame", {
			Name = `Place{index}`,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, x, 0.5, 0),
			Size = UDim2.fromOffset(28 + 6 + nameWidth + 6 + scoreWidth, STRIP_H),
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Parent = board,
		})
		local badge = UIKit.new("Frame", {
			Name = "Badge",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(28, 28),
			BackgroundColor3 = PLACE_COLORS[index] or Theme.Colors.PanelDark,
			Parent = place,
			Children = { UIKit.Round(), UIKit.Stroke(nil, 1.5, 0.4) },
		})
		UIKit.Label({
			Text = tostring(index),
			Font = Theme.Fonts.Display,
			TextSize = Theme.Touch.MinText,
			TextWrapped = false,
			TextColor3 = if PLACE_COLORS[index] then Color3.fromRGB(40, 24, 70) else Theme.Colors.Text,
			Size = UDim2.fromScale(1, 1),
			Parent = badge,
		})
		local nameLabel = UIKit.Label({
			Text = name,
			RichText = true,
			TextSize = STRIP_TEXT,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = color,
			Position = UDim2.fromOffset(34, 0),
			Size = UDim2.new(0, nameWidth, 1, 0),
			Parent = place,
			Children = { UIKit.TextStroke(0.3) },
		})
		nameLabel:SetAttribute("PP_TruncateOk", true)
		UIKit.Label({
			Text = score,
			RichText = true,
			Font = Theme.Fonts.Display,
			TextSize = STRIP_TEXT,
			TextWrapped = false,
			TextScaled = scoreWidth >= 80,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Colors.Yellow,
			Position = UDim2.fromOffset(34 + nameWidth + 6, 0),
			Size = UDim2.new(0, scoreWidth, 1, 0),
			Parent = place,
			Children = { UIKit.TextStroke(0.3), UIKit.new("UITextSizeConstraint", { MaxTextSize = STRIP_TEXT }) },
		})
		x += place.Size.X.Offset + 14
	end
	board.Size = UDim2.fromOffset(x - 14 + 12, STRIP_H)
end

function refreshBoard()
	local touch = isTouch()
	local entries = {}
	for _, other in Participants.InRound() do
		table.insert(entries, {
			who = other,
			alive = other:GetAttribute("PP_Alive") == true,
			score = other:GetAttribute("PP_Score") or 0,
			text = other:GetAttribute("PP_ScoreText") or "",
			team = other:GetAttribute("PP_Team") or "",
		})
	end
	table.sort(entries, function(a, b)
		if a.alive ~= b.alive then
			return a.alive
		end
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.who.UserId > b.who.UserId -- ties keep their places (players, then bots)
	end)
	-- Rebuilt only when something on it changed (it's checked ~3 times a second all round, and
	-- rebuilding every row and measuring its text each time cost phones for nothing).
	local parts = { if touch then "T" else "P" }
	for _, entry in entries do
		table.insert(
			parts,
			`{entry.who.UserId}|{entry.who.DisplayName}|{entry.alive}|{entry.score}|{entry.text}|{entry.team}`
		)
	end
	local key = table.concat(parts, "\n")
	if key == boardKey and #board:GetChildren() > 0 then
		return
	end
	boardKey = key
	for _, child in board:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if touch then
		drawStrip(entries)
		return
	end
	UIKit.Label({
		Text = "🏁 Standings",
		Font = Theme.Fonts.Display,
		TextSize = 22,
		TextWrapped = false,
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = 0,
		Parent = board,
	})
	-- The top rows, and always your own (in place of the last row if you're further down).
	local shown = {}
	for index = 1, math.min(6, #entries) do
		table.insert(shown, index)
	end
	for index, entry in entries do
		if entry.who.IsLocal and index > 6 then
			shown[#shown] = index
		end
	end
	-- The score column is as wide as the widest score shown ("5 perfect", "2 KOs", "Alive"), up to
	-- a bit under half the board, and a longer score shrinks to fit it: the names keep the rest (with
	-- a wider column Big Bad Vacuum's "16 dmg · 2 saved" left them as "1...."; owner, circling them).
	local textSize = 18
	local scoreWidth = 76
	local needs: { [number]: number } = {}
	for _, index in shown do
		local entry = entries[index]
		local plain = if entry.text ~= "" then entry.text else tostring(entry.score)
		local ok, bounds =
			pcall(TextService.GetTextSize, TextService, plain, textSize, Theme.Fonts.Bold, Vector2.new(1000, 100))
		if ok then
			needs[index] = math.ceil(bounds.X) + 8
			scoreWidth = math.max(scoreWidth, needs[index])
		end
	end
	scoreWidth = math.min(scoreWidth, SCORE_MAX)
	for _, index in shown do
		local entry = entries[index]
		local who = entry.who
		local status = if entry.alive then "" else "💀 "
		local teamColor = TEAM_COLORS[entry.team]
		local name = Participants.ListName(who.DisplayName, who.IsBot and not teamColor) -- teams keep their color
		local detail = Participants.Escape(if entry.text ~= "" then entry.text else tostring(entry.score))
		local color = if who.IsLocal
			then Theme.Colors.Yellow
			elseif teamColor then teamColor
			elseif entry.alive then Theme.Colors.Text
			else Theme.Colors.TextDim
		-- The name (shortened if it must be) and the score on the right, always shown.
		local row = UIKit.new("Frame", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Parent = board,
		})
		local nameLabel = UIKit.Label({
			Text = `{index}. {status}{name}`,
			RichText = true,
			TextSize = textSize,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = color,
			Size = UDim2.new(1, -(scoreWidth + 4), 1, 0),
			Parent = row,
		})
		nameLabel:SetAttribute("PP_TruncateOk", true)
		-- (a score longer than the column, "16 dmg · 2 saved", shrinks to fit rather than being cut off)
		local tight = (needs[index] or 0) > scoreWidth
		UIKit.Label({
			Text = detail,
			RichText = true,
			TextSize = textSize,
			TextScaled = tight,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = color,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, scoreWidth, 1, 0),
			Parent = row,
			Children = if tight then { UIKit.new("UITextSizeConstraint", { MaxTextSize = textSize }) } else nil,
		})
	end
end

local function buildOutPanel(parent: Instance)
	if isTouch() then
		-- Phones: one low pill in the middle (owner, on layout A: "the bottom not being centrally
		-- located is ass").
		outPanel = UIKit.Panel({
			Name = "OutPanel",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.fromOffset(400, 86),
			CornerRadius = 30,
			Visible = false,
			Parent = parent,
		}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
		UIKit.AutoScale(outPanel)
		-- (In the middle its left end reaches the MOVE stick's zone on smaller phones: someone just
		-- knocked out isn't walking. tools/checks: allowed there.)
		outPanel:SetAttribute("PP_Popup", true)
		UIKit.Label({
			Text = "💥 You're out!",
			Font = Theme.Fonts.Display,
			TextSize = 26,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(20, 0),
			Size = UDim2.new(1, -190, 1, 0),
			Parent = outPanel,
		})
		UIKit.Button({
			Text = "👀 Watch",
			TextSize = 22,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -7, 0.5, 0),
			Size = UDim2.fromOffset(160, Theme.Touch.Target),
			CornerRadius = 26,
			Parent = outPanel,
		}, function()
			outPanel.Visible = false
			State.OpenScreen:Fire("Spectate")
		end, Theme.Colors.Cyan, Color3.fromRGB(50, 120, 230))
		return
	end
	outPanel = UIKit.Panel({
		Name = "OutPanel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(420, 120),
		CornerRadius = 22,
		Visible = false,
		Parent = parent,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	UIKit.AutoScale(outPanel)
	UIKit.Label({
		Text = "💥 You're out! Nice try.",
		Font = Theme.Fonts.Display,
		TextSize = 28,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 36),
		Parent = outPanel,
	})
	UIKit.Button({
		Text = "👀 Spectate",
		TextSize = 22,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(220, 52),
		CornerRadius = 26,
		Parent = outPanel,
	}, function()
		outPanel.Visible = false
		State.OpenScreen:Fire("Spectate")
	end, Theme.Colors.Cyan, Color3.fromRGB(50, 120, 230))
end

-- Team-colored outlines so teammates and rivals are readable at a glance.
local highlights: { [Participants.Participant]: Highlight } = {}
local function refreshHighlights()
	local here = {}
	for _, other in Participants.All() do
		here[other] = true
		local team = other:GetAttribute("PP_Team") or ""
		local color = TEAM_COLORS[team]
		local character = other:Character()
		local existing = highlights[other]
		-- (A party mate's own outline, PartyWorldController's, keeps their team colour inside it.)
		if
			color
			and character
			and GameState.Get("Phase") == "InRound"
			and not character:FindFirstChild("PP_PartyHighlight")
		then
			if not existing or existing.Adornee ~= character then
				if existing then
					existing:Destroy()
				end
				existing = UIKit.new("Highlight", {
					Adornee = character,
					FillTransparency = 0.8,
					OutlineTransparency = 0.1,
					DepthMode = Enum.HighlightDepthMode.Occluded,
					Parent = character,
				})
				highlights[other] = existing
			end
			existing.FillColor = color
			existing.OutlineColor = color
		elseif existing then
			existing:Destroy()
			highlights[other] = nil
		end
	end
	-- Whoever left (a bot fading out, a player quitting) takes their outline with them.
	for other, highlight in highlights do
		if not here[other] then
			highlight:Destroy()
			highlights[other] = nil
		end
	end
end

function RoundController.Start(context)
	buildRules(context.Hud)
	buildBoard(context.Hud)
	buildOutPanel(context.Hud)
	-- A mode's own HUD waits while the rules card is up (Kit/Api reads this), so nothing is drawn
	-- over the card (owner: "This looks bad", Cake Factory's team scores and meter on the rules).
	rules:GetPropertyChangedSignal("Visible"):Connect(function()
		player:SetAttribute("PP_RulesShowing", rules.Visible)
	end)

	local lastSecond = -1
	GameState.Changed("Phase", function(phase)
		rules.Visible = false
		rulesClosed = false -- a card closed with its ✕ stays closed for the rest of that round only
		outPanel.Visible = false
		if phase == "Preparing" and State.InRound() then
			showRules()
		elseif phase == "InRound" and State.InRound() then
			flashCountdown("GO!", Theme.Colors.Green)
			Haptics.Play("Pulse")
		end
		if not isTouch() then -- (phones: HudController's status row shows the strip when there's room)
			boardRoot.Visible = phase == "InRound"
		end
		refreshHighlights()
	end)
	-- The round's players get PP_InRound as it's set up; it can land just after the phase does (but
	-- a card its player closed doesn't come back).
	player:GetAttributeChangedSignal("PP_InRound"):Connect(function()
		if GameState.Get("Phase") == "Preparing" and State.InRound() and not rules.Visible and not rulesClosed then
			showRules()
		end
	end)
	-- The server puts players on teams while the card is up (the mode's Prepare).
	player:GetAttributeChangedSignal("PP_Team"):Connect(refreshTeamTab)

	player:GetAttributeChangedSignal("PP_Alive"):Connect(function()
		if GameState.Get("Phase") == "InRound" and State.InRound() and not State.Alive() then
			outPanel.Visible = true
			UIKit.PopIn(outPanel, 0.35)
			Haptics.Play("Thud")
		end
	end)
	-- A bot fading in or out shows up in the standings right away.
	Participants.Changed:Connect(function()
		if GameState.Get("Phase") == "InRound" then
			refreshBoard()
		end
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		local phase = GameState.Get("Phase")
		if phase == "Preparing" then
			local second = math.ceil(GameState.TimeLeft())
			if second ~= lastSecond and second <= 3 and second >= 1 and State.InRound() then
				rules.Visible = false
				flashCountdown(tostring(second), Theme.Colors.Yellow)
			end
			lastSecond = second
		else
			lastSecond = -1
		end
		accumulator += dt
		if accumulator > 0.3 then
			accumulator = 0
			if phase == "InRound" then
				refreshBoard()
			end
			if phase == "InRound" then
				refreshHighlights()
			end
		end
	end)
end

return RoundController
