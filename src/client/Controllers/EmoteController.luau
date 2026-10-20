-- Emote picker: every owned emote, one tap to play. Dances loop until you move or jump.
-- Animations play on the local character (and replicate like any character animation); the
-- server validates ownership for effect emotes and quest progress.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Cosmetics = require(Shared.Cosmetics)
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local EmoteController = {}

local player = Players.LocalPlayer
local panel: Frame
local grid: Frame
local currentTrack: AnimationTrack? = nil
local lastUse = 0

local function stopEmote()
	if currentTrack then
		currentTrack:Stop(0.2)
		currentTrack = nil
	end
end

local function play(item: Cosmetics.Cosmetic)
	if os.clock() - lastUse < 1.5 then
		return
	end
	lastUse = os.clock()
	Remotes.Get("UseEmote"):FireServer(item.Id)
	if not item.Animation then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return
	end
	stopEmote()
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. item.Animation
	local track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = item.Looped == true
	track:Play(0.2)
	currentTrack = track
end

local function render()
	for _, child in grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local order = 0
	for _, item in Cosmetics.List do
		if item.Slot == "Emote" and State.Owns(item.Id) then
			order += 1
			local button = UIKit.Button({
				Text = item.Icon,
				TextSize = 38,
				Size = UDim2.fromOffset(84, 84),
				CornerRadius = 22,
				LayoutOrder = order,
				Parent = grid,
			}, function()
				play(item)
				panel.Visible = false
			end, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
			UIKit.Label({
				Text = item.Name,
				TextSize = 14,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -2),
				Size = UDim2.new(1, 0, 0, 16),
				Parent = button,
				Children = { UIKit.TextStroke(0.2) },
			})
		end
	end
	UIKit.Label({
		Text = "More emotes in the 🛍️ Shop",
		TextSize = 16,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.fromOffset(180, 84),
		LayoutOrder = order + 1,
		Parent = grid,
	})
end

function EmoteController.Start(context)
	panel = UIKit.Panel({
		Name = "Emotes",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(600, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		CornerRadius = 24,
		Visible = false,
		Parent = context.Hud,
	})
	UIKit.AutoScale(panel)
	UIKit.Label({
		Text = "🕺 Emotes  (G)",
		Font = Theme.Fonts.Display,
		TextSize = 24,
		Size = UDim2.new(1, 0, 0, 40),
		Parent = panel,
	})
	grid = UIKit.new("Frame", {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = panel,
		Children = {
			UIKit.new("UIGridLayout", {
				CellSize = UDim2.fromOffset(84, 84),
				CellPadding = UDim2.fromOffset(10, 10),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			UIKit.Padding(12),
		},
	})

	State.OpenScreen:Connect(function(name)
		if name == "Emotes" then
			panel.Visible = not panel.Visible
			if panel.Visible then
				render()
				UIKit.PopIn(panel, 0.3)
			end
		end
	end)
	State.ProfileChanged:Connect(function()
		if panel.Visible then
			render()
		end
	end)

	-- Moving or jumping cancels a dance, like any good party.
	RunService.Heartbeat:Connect(function()
		if not currentTrack then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.MoveDirection.Magnitude > 0.1 or humanoid.Jump then
			stopEmote()
		end
	end)
	player.CharacterAdded:Connect(function()
		currentTrack = nil
	end)
end

return EmoteController
