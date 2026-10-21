-- Emote picker: every owned emote, one tap to play. Dances loop until you move or jump.
-- Animations play on the local character (and replicate like any character animation); the
-- server validates ownership for effect emotes and quest progress.
-- The picker pops up in the middle of the screen, clear of the thumbstick, the jump button and the
-- vote cards; two rows show at a time (the rest scroll), and it closes when the game moves on to
-- the next phase or a window opens, so it's never left covering the vote.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Cosmetics = require(Shared.Cosmetics)
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.Parent.State)
local Modal = require(script.Parent.Parent.UI.Modal)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local EmoteController = {}

local COLUMNS = 4
local CELL = 84
local GAP = 10
local PADDING = 12
local MAX_ROWS = 2

local player = Players.LocalPlayer
local panel: Frame
local grid: ScrollingFrame
local touch = false
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

-- One square button: a big icon with its name underneath.
local function cell(order: number, icon: string, name: string, onClick: () -> (), top: Color3, bottom: Color3)
	local button = UIKit.Button({
		Text = icon,
		TextSize = 38,
		Size = UDim2.fromOffset(CELL, CELL),
		CornerRadius = 22,
		LayoutOrder = order,
		Parent = grid,
	}, onClick, top, bottom)
	UIKit.Label({
		Text = name,
		TextSize = if touch then 17 else 15,
		TextScaled = true,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(1, -8, 0, 18),
		Parent = button,
		Children = {
			UIKit.TextStroke(0.2),
			UIKit.new("UITextSizeConstraint", { MaxTextSize = if touch then 17 else 15 }),
		},
	})
end

local setOpen: (boolean) -> ()

local function render()
	for _, child in grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local count = 0
	for _, item in Cosmetics.List do
		if item.Slot == "Emote" and State.Owns(item.Id) then
			count += 1
			cell(count, item.Icon, item.Name, function()
				play(item)
				setOpen(false)
			end, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
		end
	end
	count += 1
	cell(count, "🛍️", "Get more", function()
		setOpen(false)
		State.OpenScreen:Fire("Shop", "Emote")
	end, Theme.Colors.Pink, Color3.fromRGB(200, 50, 140))
	local rows = math.min(math.ceil(count / COLUMNS), MAX_ROWS)
	grid.Size = UDim2.new(1, 0, 0, rows * CELL + (rows - 1) * GAP + 2 * PADDING)
end

setOpen = function(open: boolean)
	if open == panel.Visible then
		return
	end
	panel.Visible = open
	if open then
		render()
		grid.CanvasPosition = Vector2.zero
		UIKit.PopIn(panel, 0.3)
	end
end

function EmoteController.Start(context)
	touch = UIKit.IsTouch()
	panel = UIKit.Panel({
		Name = "Emotes",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(COLUMNS * CELL + (COLUMNS - 1) * GAP + 2 * PADDING, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		CornerRadius = 24,
		Visible = false,
		Parent = context.Hud,
	})
	UIKit.AutoScale(panel)
	-- Phones: a taller title row, so the close button is big enough for a thumb.
	local header = if touch then 56 else 44
	local closeSize = if touch then 46 else 34
	UIKit.Label({
		Text = if touch then "🕺 Emotes" else "🕺 Emotes  (G)",
		Font = Theme.Fonts.Display,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(PADDING + 4, (header - 40) / 2),
		Size = UDim2.new(1, -70, 0, 40),
		Parent = panel,
	})
	UIKit.Button({
		Name = "Close",
		Text = "✕",
		TextSize = if touch then 24 else 20,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -PADDING, 0, (header - closeSize) / 2),
		Size = UDim2.fromOffset(closeSize, closeSize),
		CornerRadius = "round",
		Parent = panel,
	}, function()
		setOpen(false)
	end, Theme.Colors.Red, Color3.fromRGB(190, 40, 60))
	grid = UIKit.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, header),
		Size = UDim2.new(1, 0, 0, CELL + 2 * PADDING),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel,
		Children = {
			UIKit.new("UIGridLayout", {
				CellSize = UDim2.fromOffset(CELL, CELL),
				CellPadding = UDim2.fromOffset(GAP, GAP),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			UIKit.Padding(PADDING),
		},
	})

	State.OpenScreen:Connect(function(name)
		if name == "Emotes" then
			setOpen(not panel.Visible)
		end
	end)
	State.ProfileChanged:Connect(function()
		if panel.Visible then
			render()
		end
	end)
	-- Out of the way when the vote opens, a round starts or a window (shop, quests...) opens.
	GameState.Changed("Phase", function()
		setOpen(false)
	end)
	Modal.AnyOpenChanged:Connect(function(open)
		if open then
			setOpen(false)
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
