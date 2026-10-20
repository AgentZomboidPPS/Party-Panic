-- Spectating (design doc §11 "Spectator options"): watch remaining players during a round,
-- cycle between them, and return to your own camera automatically at results. Bots in the round
-- can be watched too (Participants).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameState = require(ReplicatedStorage.Shared.GameState)

local Participants = require(script.Parent.Parent.Participants)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local SpectateController = {}

local player = Players.LocalPlayer
local bar: Frame
local nameLabel: TextLabel
local openButton: TextButton
local index = 1
local spectating = false

local function targets(): { Participants.Participant }
	local list = {}
	for _, other in Participants.InRound() do
		if not other.IsLocal and other:GetAttribute("PP_Alive") then
			table.insert(list, other)
		end
	end
	table.sort(list, function(a, b)
		return a.UserId > b.UserId -- players first, then bots in the order they arrived
	end)
	return list
end

local function humanoidOf(target: Participants.Participant): Humanoid?
	local character = target:Character()
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function resetCamera()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		workspace.CurrentCamera.CameraSubject = humanoid
	end
end

local function stop()
	spectating = false
	bar.Visible = false
	resetCamera()
end

local function focus()
	local list = targets()
	if #list == 0 then
		stop()
		return
	end
	index = ((index - 1) % #list) + 1
	local target = list[index]
	local humanoid = humanoidOf(target)
	if humanoid then
		workspace.CurrentCamera.CameraSubject = humanoid
	end
	nameLabel.Text = `👀 {target.DisplayName}  ({index}/{#list})`
end

local function start()
	if #targets() == 0 then
		return
	end
	spectating = true
	bar.Visible = true
	UIKit.PopIn(bar, 0.3)
	focus()
end

function SpectateController.Start(context)
	bar = UIKit.Panel({
		Name = "Spectate",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(560, 76),
		CornerRadius = 38,
		Visible = false,
		Parent = context.Hud,
	})
	UIKit.AutoScale(bar)
	UIKit.Button({
		Text = "◀",
		Size = UDim2.fromOffset(60, 60),
		Position = UDim2.fromOffset(8, 8),
		CornerRadius = "round",
		Parent = bar,
	}, function()
		index -= 1
		focus()
	end, Theme.Colors.Cyan, Color3.fromRGB(50, 120, 230))
	nameLabel = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 24,
		Position = UDim2.fromOffset(76, 0),
		Size = UDim2.new(1, -250, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = bar,
	})
	UIKit.Button({
		Text = "▶",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(60, 60),
		Position = UDim2.new(1, -110, 0, 8),
		CornerRadius = "round",
		Parent = bar,
	}, function()
		index += 1
		focus()
	end, Theme.Colors.Cyan, Color3.fromRGB(50, 120, 230))
	UIKit.Button({
		Text = "✕",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(90, 60),
		Position = UDim2.new(1, -10, 0, 8),
		CornerRadius = 30,
		Parent = bar,
	}, stop, Theme.Colors.Red, Color3.fromRGB(190, 40, 60))

	-- Lobby players can also watch a round in progress.
	openButton = UIKit.Button({
		Name = "SpectateButton",
		Text = "👀 Watch the round",
		TextSize = 20,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(250, 56),
		CornerRadius = 28,
		Visible = false,
		Parent = context.Hud,
	}, start, Theme.Colors.Cyan, Color3.fromRGB(50, 120, 230))
	UIKit.AutoScale(openButton)

	State.OpenScreen:Connect(function(name)
		if name == "Spectate" then
			start()
		end
	end)

	-- The "you're out" panel (RoundController) has its own Spectate button in the same spot.
	local outPanel = context.Hud:FindFirstChild("OutPanel") :: GuiObject?
	local function refresh()
		local phase = GameState.Get("Phase")
		local roundLive = phase == "InRound"
		if not roundLive and spectating then
			stop()
		end
		openButton.Visible = roundLive
			and not spectating
			and not (State.InRound() and State.Alive())
			and not (outPanel and outPanel.Visible)
			and #targets() > 0
	end
	GameState.Changed("Phase", refresh)
	Participants.Changed:Connect(refresh)
	task.spawn(function()
		while true do
			task.wait(0.5)
			refresh()
			if spectating then
				-- Follow the next survivor when the current one is knocked out.
				local list = targets()
				local subject = workspace.CurrentCamera.CameraSubject
				local watching = false
				for _, other in list do
					local character = other:Character()
					if character and subject and subject:IsDescendantOf(character) then
						watching = true
					end
				end
				if not watching then
					focus()
				end
			end
		end
	end)
	player.CharacterAdded:Connect(function()
		if not spectating then
			task.defer(resetCamera)
		end
	end)
end

return SpectateController
