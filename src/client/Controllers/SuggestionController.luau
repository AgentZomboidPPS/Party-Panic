-- The suggestion box's window (owner: "Can we add a suggestion box?"): what it's about (🎮 New
-- game, ⭐ Improve, 🐛 Bug, 💬 Other), a few lines of the player's own words (Shared/Logic/
-- Suggestions: 8 to 300 characters, with a counter), and SEND. The server keeps it
-- (Services/SuggestionService) and answers on the same remote: a thank-you, and the window closes a
-- moment later; or why not (one a minute, the write failed), with the words still there to send
-- again. Nobody else in the game ever sees what's sent.
-- It opens from the Settings window's 💡 button (HudController), the mailbox by the quest board in
-- the lobby (World/LobbyBuilder's "OpenSuggestions" prompt) and State.OpenScreen:Fire("Suggestions").
-- Phones: it fits the shortest phone, 44 pt buttons and the game's smallest text or bigger.

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
	remote.OnClientEvent:Connect(function(ok, words)
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
