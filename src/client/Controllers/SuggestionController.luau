-- The suggestion box's window (owner: "Can we add a suggestion box?"): what it's about (🎮 New
-- game, ⭐ Improve, 🐛 Bug, 💬 Other), a few lines of the player's own words (Shared/Logic/
-- Suggestions: 8 to 300 characters, with a counter), and SEND. The server keeps it
-- (Services/SuggestionService) and answers on the same remote: a thank-you, and the window closes a
-- moment later; or why not (one a minute, the write failed), with the words still there to send
-- again. Nobody else in the game ever sees what's sent.
-- It opens from the Settings window's 💡 button (HudController), the mailbox by the quest board in
-- the lobby (World/LobbyBuilder's "OpenSuggestions" prompt) and State.OpenScreen:Fire("Suggestions").
-- Phones: it fits the shortest phone, 44 pt buttons and the game's smallest text or bigger.
-- The game's owner also gets INBOX (owner: "did we ever add in a way for me the dev to read the
-- suggestion box?"): a window of the last week's suggestions, newest first, read from the server
-- (Services/SuggestionService: only the owner hears back).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Suggestions = require(Shared.Logic.Suggestions)

local AudioController = require(script.Parent.AudioController)
local State = require(script.Parent.Parent.State)
local Modal = require(script.Parent.Parent.UI.Modal)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local SuggestionController = {}

local CLOSE_AFTER = 1.6 -- seconds the thank-you shows before the window closes
local ANSWER_TIME = 8 -- seconds to wait for the server's answer before letting them try again

local KIND_COLORS = {
	Game = { Theme.Colors.Pink, Color3.fromRGB(200, 50, 140) },
	Better = { Theme.Colors.Orange, Color3.fromRGB(205, 92, 24) },
	Bug = { Theme.Colors.Green, Color3.fromRGB(60, 160, 90) },
	Other = { Theme.Colors.Cyan, Color3.fromRGB(50, 120, 230) },
}

-- How long ago a time was, short ("just now", "5m", "3h", "2d").
local function ago(seconds: number): string
	local passed = math.max(0, os.time() - seconds)
	if passed < 60 then
		return "just now"
	elseif passed < 3600 then
		return `{passed // 60}m ago`
	elseif passed < 86400 then
		return `{passed // 3600}h ago`
	end
	return `{passed // 86400}d ago`
end

-- The owner's inbox: a window listing what players sent (asked for each time it opens).
local function buildInbox(context, remote: RemoteEvent, touch: boolean)
	local inbox = Modal.new(context.Overlay, "SUGGESTION INBOX", "💌", Vector2.new(760, 520))
	local status = UIKit.Label({
		Name = "Status",
		Text = "",
		TextSize = Theme.Touch.MinText + 2,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 28),
		ZIndex = 23,
		Parent = inbox.Content,
	})
	local list = UIKit.new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 1, -34),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = if touch then 10 else 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 23,
		Parent = inbox.Content,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left) },
	})
	local labels: { [string]: string } = {}
	for _, kind in Suggestions.Kinds do
		labels[kind.Id] = `{kind.Icon} {kind.Label}`
	end
	local function show(entries: { any }, ok: boolean)
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		status.Text = if not ok
			then "Couldn't read the box just now. Try again in a moment."
			elseif #entries == 0 then "No suggestions in the last week yet."
			else `{#entries} suggestion{if #entries == 1 then "" else "s"} in the last week`
		for index, entry in entries do
			local card = UIKit.new("Frame", {
				Name = "Entry",
				Size = UDim2.new(1, -14, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = Theme.Colors.PanelDark,
				LayoutOrder = index,
				ZIndex = 23,
				Parent = list,
				Children = {
					UIKit.Corner(14),
					UIKit.Padding(10, 14),
					UIKit.List(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left),
				},
			})
			UIKit.Label({
				Name = "Who",
				Text = `{labels[entry.K] or tostring(entry.K)}  ·  {entry.N or "?"}  ·  {ago(entry.T or 0)}`,
				TextSize = Theme.Touch.MinText,
				TextColor3 = Theme.Colors.Yellow,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, 0, 0, 24),
				LayoutOrder = 1,
				ZIndex = 24,
				Parent = card,
			})
			UIKit.Label({
				Name = "Words",
				Text = tostring(entry.S or ""),
				KeepEmoji = true, -- (a player's own words, as they typed them)
				Font = Theme.Fonts.Body,
				TextSize = Theme.Touch.MinText + 2,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 2,
				ZIndex = 24,
				Parent = card,
			})
		end
	end
	inbox.Opened:Connect(function()
		status.Text = "Reading the box..."
		remote:FireServer("Inbox")
	end)
	return inbox, show
end

function SuggestionController.Start(context)
	local touch = UIKit.IsTouch()
	local remote = Remotes.Get("Suggest")
	local modal = Modal.new(context.Overlay, "SUGGESTION BOX", "💡", Vector2.new(620, if touch then 470 else 440))
	local chipHeight = if touch then Theme.Touch.Target else 54
	local buttonHeight = if touch then Theme.Touch.Target else 56
	local body = UIKit.new("Frame", {
		Name = "Suggestions",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = modal.Content,
	})
	UIKit.Label({
		Name = "Ask",
		Text = "Got an idea, a fix or a bug? Tell the team!",
		TextSize = Theme.Touch.MinText + 2,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 26),
		ZIndex = 23,
		Parent = body,
	})

	-- The owner's INBOX (only the game's creator: the server answers nobody else).
	local player = Players.LocalPlayer
	local owner = game.CreatorType == Enum.CreatorType.User and game.CreatorId ~= 0 and player.UserId == game.CreatorId
	local showInbox: ((entries: { any }, ok: boolean) -> ())? = nil
	if owner then
		local inbox, show = buildInbox(context, remote, touch)
		showInbox = show
		UIKit.Button({
			Name = "Inbox",
			Text = "💌 INBOX",
			TextSize = 18,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(130, 30),
			CornerRadius = 15,
			ZIndex = 24,
			Parent = body,
		}, function()
			modal:Close()
			inbox:Open()
		end, Theme.Colors.Yellow, Theme.Colors.Orange)
	end

	-- What it's about: four chips, one lit.
	local chosen = Suggestions.Kinds[1].Id
	local chipRow = UIKit.new("Frame", {
		Name = "Kinds",
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, chipHeight),
		BackgroundTransparency = 1,
		ZIndex = 23,
		Parent = body,
		Children = {
			UIKit.new("UIGridLayout", {
				CellSize = UDim2.new(0.25, -6, 1, 0),
				CellPadding = UDim2.fromOffset(8, 0),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
	})
	local chips: { [string]: TextButton } = {}
	local function paintChips()
		for id, chip in chips do
			local lit = id == chosen
			local stroke = chip:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if lit then Color3.new(1, 1, 1) else Theme.Colors.Stroke
				stroke.Thickness = if lit then 3 else 2
				stroke.Transparency = if lit then 0 else 0.55
			end
			chip.TextTransparency = if lit then 0 else 0.25
			chip.BackgroundTransparency = if lit then 0 else 0.35
		end
	end
	for index, kind in Suggestions.Kinds do
		local colors = KIND_COLORS[kind.Id] or { Theme.Colors.Lavender, Theme.Colors.Purple }
		chips[kind.Id] = UIKit.Button({
			Name = kind.Id,
			Text = `{kind.Icon} {kind.Label}`,
			TextSize = 20,
			TextWrapped = false,
			CornerRadius = chipHeight / 2,
			LayoutOrder = index,
			ZIndex = 24,
			Parent = chipRow,
		}, function()
			chosen = kind.Id
			paintChips()
		end, colors[1], colors[2])
	end
	paintChips()

	-- The words.
	local boxTop = 32 + chipHeight + 10
	local box = UIKit.new("TextBox", {
		Name = "Words",
		Text = "",
		PlaceholderText = "Type your idea here...",
		PlaceholderColor3 = Theme.Colors.TextDim,
		ClearTextOnFocus = false,
		MultiLine = true,
		TextWrapped = true,
		TextSize = 20,
		Font = Theme.Fonts.Bold,
		TextColor3 = Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		BackgroundColor3 = Theme.Colors.PanelDark,
		Position = UDim2.fromOffset(0, boxTop),
		Size = UDim2.new(1, 0, 1, -(boxTop + buttonHeight + 12)),
		ZIndex = 24,
		Parent = body,
		Children = { UIKit.Corner(16), UIKit.Stroke(nil, 2, 0.5), UIKit.Padding(10, 14) },
	}) :: TextBox

	-- The counter, the answer, and SEND.
	local counter = UIKit.Label({
		Name = "Counter",
		Text = `0/{Suggestions.MAX_LENGTH}`,
		TextSize = Theme.Touch.MinText,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true, -- (the server's answer can take two lines)
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, -230, 0, buttonHeight),
		ZIndex = 23,
		Parent = body,
	})
	local send = UIKit.Button({
		Name = "Send",
		Text = "💌 SEND",
		TextSize = 26,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(210, buttonHeight),
		CornerRadius = buttonHeight / 2,
		ZIndex = 24,
		Parent = body,
	}, nil, Theme.Colors.Green, Color3.fromRGB(40, 160, 80))

	local waiting = false
	local answerToken = 0
	local note: string? = nil -- the server's last word (shown in the counter's place until they type)
	local function refresh()
		local length = Suggestions.Length(box.Text)
		local ready = Suggestions.Clean(box.Text) ~= nil
		if note then
			counter.Text = note
		elseif length > Suggestions.MAX_LENGTH then
			counter.Text = `{length}/{Suggestions.MAX_LENGTH}: a bit shorter, please`
		elseif length > 0 and not ready then
			counter.Text = `{length}/{Suggestions.MAX_LENGTH}: tell us a bit more`
		else
			counter.Text = `{length}/{Suggestions.MAX_LENGTH}`
		end
		counter.TextColor3 = if length > Suggestions.MAX_LENGTH then Theme.Colors.Red else Theme.Colors.TextDim
		send.AutoButtonColor = false
		send.Active = ready and not waiting
		send.TextTransparency = if ready and not waiting then 0 else 0.45
		send.Text = if waiting then "SENDING..." else "💌 SEND"
	end
	box:GetPropertyChangedSignal("Text"):Connect(function()
		note = nil
		refresh()
	end)

	send.Activated:Connect(function()
		local words = Suggestions.Clean(box.Text)
		if waiting or not words then
			return
		end
		waiting = true
		note = nil
		answerToken += 1
		local token = answerToken
		refresh()
		remote:FireServer(chosen, words)
		task.delay(ANSWER_TIME, function()
			if waiting and token == answerToken then
				waiting = false
				note = "No answer yet. Try again in a moment!"
				refresh()
			end
		end)
	end)
	remote.OnClientEvent:Connect(function(ok, words, read)
		if ok == "Inbox" then
			if showInbox then
				showInbox(if type(words) == "table" then words else {}, read == true)
			end
			return
		end
		waiting = false
		answerToken += 1
		note = if type(words) == "string" then words else nil
		if ok == true then
			AudioController.Play("Pickup")
			box.Text = "" -- (its Text signal clears the note: set it again after)
			note = if type(words) == "string" then `💡 {words}` else "💡 Thanks!"
			counter.TextColor3 = Theme.Colors.Green
			local token = answerToken
			task.delay(CLOSE_AFTER, function()
				if token == answerToken and modal.IsOpen then
					modal:Close()
				end
			end)
		end
		refresh()
		if ok == true then
			counter.TextColor3 = Theme.Colors.Green
		end
	end)
	modal.Closed:Connect(function()
		box:ReleaseFocus()
		if not waiting then
			note = nil
			refresh()
		end
	end)
	refresh()

	State.OpenScreen:Connect(function(name)
		if name == "Suggestions" then
			modal:Toggle()
		end
	end)
end

return SuggestionController
