-- The big moments (owner: "Also we need cool payoffs for players that keep playing the game."):
--   * LEVEL UP! A full-screen burst: the new level pops out in a badge with its prestige colors,
--     rings and confetti fly, a fanfare plays, and the rewards are revealed one by one (the Rewards
--     Road's coins and any exclusive cosmetic, with an EQUIP button), then the next goal. Career
--     milestones get the same moment ("MILESTONE!").
--   * Over the head of anyone who levels up, a "Lv 10!" pops up for everyone in the lobby to see.
-- The server has already granted everything (Services/ProgressionService); this only shows it.
-- A celebration waits for a calm moment: never during the vote, the round or the results card
-- (it shows when everyone's back in the lobby), and several at once make one. It closes itself
-- after a few seconds, on a tap anywhere, when a window opens or when the vote starts. Reduced
-- effects: less confetti, no shimmer. Phones: 44 pt buttons, all in the middle of the screen.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Cosmetics = require(Shared.Cosmetics)
local GameState = require(Shared.GameState)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)

local AudioController = require(script.Parent.AudioController)
local State = require(script.Parent.Parent.State)
local Modal = require(script.Parent.Parent.UI.Modal)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local CelebrationController = {}

type Celebration = {
	Kind: string, -- "LevelUp" | "Milestone"
	Level: number?,
	From: number?,
	Coins: number,
	Items: { string },
}

local CALM = { Waiting = true, Intermission = true, Cleanup = true }
local SHOW_FOR = 10
local STAGE_W, STAGE_H = 900, 470
local CHIP_H = 200
local CONFETTI = {
	Color3.fromRGB(255, 90, 140),
	Color3.fromRGB(90, 190, 255),
	Color3.fromRGB(255, 210, 70),
	Color3.fromRGB(150, 110, 255),
	Color3.fromRGB(110, 230, 140),
}
local GOLD = ColorSequence.new(Color3.fromRGB(255, 236, 120), Color3.fromRGB(240, 150, 30))

local touch = false
local gui: ScreenGui
local queue: { Celebration } = {}
local closeCurrent: (() -> ())? = nil

-- Several waiting celebrations make one: the highest level reached, every coin and every item.
local function merge(list: { Celebration }): Celebration
	local merged: Celebration = { Kind = "Milestone", Coins = 0, Items = {} }
	local seen = {}
	for _, entry in list do
		if entry.Kind == "LevelUp" then
			merged.Kind = "LevelUp"
			merged.Level = math.max(merged.Level or 0, entry.Level or 0)
			merged.From = math.min(merged.From or math.huge, entry.From or entry.Level or 1)
		end
		merged.Coins += entry.Coins or 0
		for _, id in entry.Items or {} do
			if not seen[id] and Cosmetics.Get(id) then
				seen[id] = true
				table.insert(merged.Items, id)
			end
		end
	end
	return merged
end

local function label(props: { [string]: any }): TextLabel
	props.BackgroundTransparency = 1
	props.ZIndex = props.ZIndex or 3
	return UIKit.Label(props)
end

-- The reward chips: coins, then each item with its EQUIP button.
local function coinChip(parent: Instance, coins: number, order: number)
	local chip = UIKit.Panel({
		Name = "Coins",
		Size = UDim2.fromOffset(150, CHIP_H),
		LayoutOrder = order,
		CornerRadius = 20,
		ZIndex = 3,
		Parent = parent,
	}, Color3.fromRGB(255, 196, 60), Color3.fromRGB(230, 130, 30))
	UIKit.Coin({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 18),
		Size = UDim2.fromOffset(62, 62),
		ZIndex = 4,
		Parent = chip,
	})
	label({
		Text = `+{coins}`,
		Font = Theme.Fonts.Display,
		TextSize = 44,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 92),
		Size = UDim2.new(1, 0, 0, 52),
		ZIndex = 4,
		Parent = chip,
		Children = { UIKit.TextStroke(0.1) },
	})
	label({
		Text = "COINS",
		Font = Theme.Fonts.Display,
		TextSize = 22,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 146),
		Size = UDim2.new(1, 0, 0, 30),
		ZIndex = 4,
		Parent = chip,
		Children = { UIKit.TextStroke(0.2) },
	})
	return chip
end

local function itemChip(parent: Instance, item: Cosmetics.Cosmetic, order: number)
	local chip = UIKit.Panel({
		Name = item.Id,
		Size = UDim2.fromOffset(210, CHIP_H),
		LayoutOrder = order,
		CornerRadius = 20,
		ZIndex = 3,
		Parent = parent,
	}, Theme.Colors.Card, Theme.Colors.PanelDark)
	if item.Colors and #item.Colors > 1 then
		-- Trails and the like show their colors along the top.
		UIKit.new("Frame", {
			Position = UDim2.fromOffset(10, 8),
			Size = UDim2.new(1, -20, 0, 8),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 4,
			Parent = chip,
			Children = { UIKit.Round(), UIKit.new("UIGradient", { Color = Cosmetics.ColorSequence(item.Colors) }) },
		})
	end
	label({
		Text = item.Icon,
		TextSize = 40,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.new(1, 0, 0, 44),
		ZIndex = 4,
		Parent = chip,
	})
	local name = label({
		Text = item.Name,
		Font = Theme.Fonts.Display,
		TextSize = 20,
		Position = UDim2.fromOffset(8, 56),
		Size = UDim2.new(1, -16, 0, 44),
		ZIndex = 4,
		Parent = chip,
		Children = { UIKit.TextStroke(0.3) },
	})
	name:SetAttribute("PP_Lines", 2)
	label({
		Text = string.upper(Cosmetics.SlotNames[item.Slot] or item.Slot),
		TextSize = Theme.Touch.MinText,
		TextWrapped = false,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(8, 100),
		Size = UDim2.new(1, -16, 0, 22),
		ZIndex = 4,
		Parent = chip,
	})
	local buttonProps = {
		Name = "Action",
		TextSize = 22,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -20, 0, if touch then Theme.Touch.Target else 60),
		CornerRadius = 16,
		ZIndex = 5,
		Parent = chip,
	}
	if Cosmetics.IsEquipSlot(item.Slot) then
		local equipped = State.Profile and State.Profile.Equipped[item.Slot] == item.Id
		buttonProps.Text = if equipped then "EQUIPPED ✓" else "EQUIP"
		local button
		button = UIKit.Button(buttonProps, function()
			Remotes.Get("ShopEquip"):FireServer(item.Slot, item.Id)
			button.Text = "EQUIPPED ✓"
			local gradient = button:FindFirstChildOfClass("UIGradient")
			if gradient then
				gradient.Color = ColorSequence.new(Theme.Colors.Green, Color3.fromRGB(60, 160, 90))
			end
		end, Theme.Colors.Cyan, Color3.fromRGB(50, 120, 230))
	else
		buttonProps.Text = if item.Slot == "Emote" then "✓ IN EMOTES" else "✓ UNLOCKED"
		buttonProps.Font = Theme.Fonts.Display
		buttonProps.TextWrapped = false
		buttonProps.TextColor3 = Theme.Colors.Green
		label(buttonProps)
	end
	return chip
end

local function moreChip(parent: Instance, count: number, order: number)
	local chip = UIKit.Panel({
		Name = "More",
		Size = UDim2.fromOffset(150, CHIP_H),
		LayoutOrder = order,
		CornerRadius = 20,
		ZIndex = 3,
		Parent = parent,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	label({
		Text = `+{count}\nmore!`,
		Font = Theme.Fonts.Display,
		TextSize = 34,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = chip,
		Children = { UIKit.TextStroke(0.2) },
	})
	return chip
end

-- What to aim for next, after this celebration.
local function nextGoal(celebration: Celebration): string
	local profile = State.Profile
	if celebration.Kind == "LevelUp" then
		local level = celebration.Level or (profile and profile.Level) or 1
		local nextLevel = Progression.NextItemLevel(level)
		local item = nextLevel and Progression.ItemsAt(nextLevel)[1]
		if item then
			return `Next up: {item.Icon} Lv {nextLevel}: {item.Name}`
		end
		return "You've unlocked every level reward!"
	end
	local best, bestRatio = nil, -1
	for _, item in Progression.Milestones do
		if profile and not profile.Owned[item.Id] then
			local have, target = Progression.MilestoneProgress(item, profile.Stats)
			if have / math.max(1, target) > bestRatio then
				best, bestRatio = item, have / math.max(1, target)
			end
		end
	end
	if best and profile then
		local have, target = Progression.MilestoneProgress(best, profile.Stats)
		return `Next milestone: {best.Icon} {best.Name} ({have}/{target})`
	end
	return "Every career milestone unlocked!"
end

local function confetti(layer: Frame)
	local count = if State.ReducedEffects() then 10 else 36
	for index = 1, count do
		local piece = UIKit.new("Frame", {
			Name = "Confetti",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(math.random(), -0.08 - math.random() * 0.25),
			Size = UDim2.fromOffset(math.random(8, 13), math.random(14, 20)),
			Rotation = math.random(0, 360),
			BackgroundColor3 = CONFETTI[(index % #CONFETTI) + 1],
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = layer,
		})
		local fall = 2.2 + math.random() * 1.6
		UIKit.Tween(piece, fall, {
			Position = UDim2.fromScale(piece.Position.X.Scale + (math.random() - 0.5) * 0.25, 1.1),
			Rotation = piece.Rotation + math.random(-540, 540),
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(piece, fall + 0.2)
	end
end

local function ring(parent: Instance, center: UDim2, delay: number)
	local circle = UIKit.new("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = center,
		Size = UDim2.fromOffset(120, 120),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = parent,
		Children = { UIKit.Round() },
	})
	local stroke =
		UIKit.new("UIStroke", { Color = Theme.Colors.Yellow, Thickness = 6, Transparency = 0, Parent = circle })
	task.delay(delay, function()
		UIKit.Tween(circle, 0.9, { Size = UDim2.fromOffset(460, 460) })
		UIKit.Tween(stroke, 0.9, { Transparency = 1 })
	end)
	Debris:AddItem(circle, delay + 1)
end

local function show(celebration: Celebration)
	local isLevel = celebration.Kind == "LevelUp"
	local items = {}
	for _, id in celebration.Items do
		local item = Cosmetics.Get(id)
		if item then
			table.insert(items, item)
		end
	end
	local level = celebration.Level or 1
	local look = Progression.Look(level)
	local newColor = isLevel and celebration.From ~= nil and look.Index > Progression.Look(celebration.From).Index

	local root = UIKit.new("Frame", {
		Name = "Celebration",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		if closeCurrent == close then
			closeCurrent = nil
		end
		root:Destroy()
		task.delay(0.4, CelebrationController.Pump)
	end
	closeCurrent = close

	-- The dim backdrop reaches past the safe area to cover the whole screen; a tap closes.
	local backdrop = UIKit.new("TextButton", {
		Name = "Backdrop",
		Position = UDim2.fromOffset(-300, -300),
		Size = UDim2.new(1, 600, 1, 600),
		BackgroundColor3 = Color3.fromRGB(20, 10, 45),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 1,
		Parent = root,
	})
	backdrop.Activated:Connect(close)
	UIKit.Tween(backdrop, 0.25, { BackgroundTransparency = 0.3 })
	confetti(root)

	local stage = UIKit.new("Frame", {
		Name = "Stage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(STAGE_W, STAGE_H),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = root,
	})
	UIKit.AutoScale(stage)
	stage:SetAttribute("PP_Popup", true) -- shown for a moment over the middle of the screen

	-- Row 1: the badge and the headline, centered together.
	local badgeX = 170
	local badgeCenter = UDim2.fromOffset(badgeX + 60, 60)
	ring(stage, badgeCenter, 0.05)
	ring(stage, badgeCenter, 0.3)
	local badge = UIKit.new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = badgeCenter,
		Size = UDim2.fromOffset(120, 120),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 3,
		Parent = stage,
		Children = { UIKit.Round(), UIKit.Stroke(nil, 4, 0.1) },
	})
	local badgeGradient = UIKit.new("UIGradient", {
		Color = if isLevel then look.Gradient else GOLD,
		Rotation = 90,
		Parent = badge,
	})
	label({
		Text = if isLevel then tostring(level) else (items[1] and items[1].Icon or "🏅"),
		Font = Theme.Fonts.Display,
		TextSize = if isLevel then (if level >= 100 then 50 else 62) else 58,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = badge,
		Children = { UIKit.TextStroke(0.1) },
	})
	local headline = label({
		Text = if isLevel then "LEVEL UP!" else "MILESTONE!",
		Font = Theme.Fonts.Display,
		TextSize = 64,
		TextWrapped = false,
		TextColor3 = Theme.Colors.Yellow,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(badgeX + 140, 2),
		Size = UDim2.fromOffset(440, 72),
		Parent = stage,
		Children = { UIKit.TextStroke(0) },
	})
	local subline
	if isLevel then
		subline = if newColor
			then `Level {level} and a new color: {look.Icon} {look.Name}!`
			else `You're level {level}!`
	else
		subline = if items[1] then `{items[1].Name} unlocked!` else "New reward unlocked!"
	end
	label({
		Text = subline,
		TextSize = 26,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(badgeX + 142, 76),
		Size = UDim2.fromOffset(500, 36),
		Parent = stage,
		Children = { UIKit.TextStroke(0.2) },
	})

	-- Row 2: the rewards, revealed one by one.
	local row = UIKit.new("Frame", {
		Name = "Rewards",
		Position = UDim2.fromOffset(0, 132),
		Size = UDim2.new(1, 0, 0, CHIP_H),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = stage,
		Children = { UIKit.List(Enum.FillDirection.Horizontal, 14, Enum.HorizontalAlignment.Center) },
	})
	local chips = {}
	if (celebration.Coins or 0) > 0 then
		table.insert(chips, coinChip(row, celebration.Coins, 1))
	end
	local room = if #items > 3 then 2 else 3
	for index, item in items do
		if index > room then
			table.insert(chips, moreChip(row, #items - room, 10))
			break
		end
		table.insert(chips, itemChip(row, item, 1 + index))
	end
	for index, chip in chips do
		chip.Visible = false
		task.delay(0.45 + index * 0.18, function()
			if chip.Parent then
				chip.Visible = true
				UIKit.PopIn(chip, 0.35)
			end
		end)
	end

	-- Row 3: the next goal. Row 4: the buttons.
	label({
		Text = nextGoal(celebration),
		TextSize = 22,
		TextWrapped = false,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(0, 344),
		Size = UDim2.new(1, 0, 0, 30),
		Parent = stage,
		Children = { UIKit.TextStroke(0.3) },
	})
	local buttons = UIKit.new("Frame", {
		Name = "Buttons",
		Position = UDim2.fromOffset(0, 386),
		Size = UDim2.new(1, 0, 0, 76),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = stage,
		Children = { UIKit.List(Enum.FillDirection.Horizontal, 20, Enum.HorizontalAlignment.Center) },
	})
	local buttonHeight = if touch then Theme.Touch.Target else 64
	UIKit.Button({
		Name = "Awesome",
		Text = "AWESOME!",
		TextSize = 28,
		Size = UDim2.fromOffset(240, buttonHeight),
		CornerRadius = 20,
		LayoutOrder = 1,
		ZIndex = 4,
		Parent = buttons,
	}, close, Theme.Colors.Green, Color3.fromRGB(60, 160, 90))
	UIKit.Button({
		Name = "SeeMore",
		Text = if isLevel then "⭐ SEE ROAD" else "🏅 CAREER",
		TextSize = 24,
		Size = UDim2.fromOffset(240, buttonHeight),
		CornerRadius = 20,
		LayoutOrder = 2,
		ZIndex = 4,
		Parent = buttons,
	}, function()
		close()
		State.OpenScreen:Fire("Rewards", if isLevel then "Road" else "Career")
	end, Theme.Colors.Pink, Color3.fromRGB(200, 50, 140))

	-- Motion: the badge and headline pop, a rainbow badge shimmers.
	UIKit.PopIn(badge, 0.6)
	UIKit.PopIn(headline, 0.45)
	local shimmer = if isLevel
			and look.Rainbow
			and not State.ReducedEffects()
		then RunService.Heartbeat:Connect(function()
			badgeGradient.Rotation = (os.clock() * 90) % 360
		end)
		else nil
	root.Destroying:Connect(function()
		if shimmer then
			shimmer:Disconnect()
		end
	end)
	AudioController.Play(if #items > 0 or not isLevel then "Victory" else "VoteOpen")
	task.delay(SHOW_FOR, close)
end

-- Shows the next celebration if it's a calm moment (several waiting make one).
function CelebrationController.Pump()
	if closeCurrent or #queue == 0 or not CALM[GameState.Get("Phase") or "Waiting"] then
		return
	end
	local celebration = merge(queue)
	table.clear(queue)
	show(celebration)
end

-- Closes the celebration on screen (the client harness uses this too).
function CelebrationController.Dismiss()
	if closeCurrent then
		closeCurrent()
	end
end

-- "Lv 10!" over a player's head, for a few seconds.
local function popOver(character: Instance, level: number)
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - head.Position).Magnitude > 160 then
		return -- too far away to see
	end
	local look = Progression.Look(level)
	local reduced = State.ReducedEffects()
	local board = Instance.new("BillboardGui")
	board.Name = "PP_LevelPop"
	board.Adornee = head
	board.Size = UDim2.fromOffset(160, 58)
	board.StudsOffset = Vector3.new(0, 4.4, 0)
	board.MaxDistance = 160
	board.LightInfluence = 0
	board.AlwaysOnTop = true
	board.ResetOnSpawn = false
	local pill = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = board,
		Children = {
			UIKit.Round(),
			UIKit.new("UIGradient", { Color = look.Gradient, Rotation = 90 }),
			UIKit.new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 3, Transparency = 0.1 }),
		},
	})
	local text = UIKit.Label({
		Text = `{look.Icon}Lv {level}!`,
		Font = Theme.Fonts.Display,
		TextScaled = true,
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		Parent = pill,
		Children = { UIKit.TextStroke(0.1) },
	})
	board.Parent = head
	if not reduced then
		UIKit.PopIn(pill, 0.45)
		UIKit.Tween(board, 2.8, { StudsOffset = Vector3.new(0, 6, 0) }, Enum.EasingStyle.Sine)
	end
	task.delay(2.2, function()
		if board.Parent then
			UIKit.Tween(pill, 0.6, { BackgroundTransparency = 1 })
			UIKit.Tween(text, 0.6, { TextTransparency = 1 })
			for _, item in pill:GetDescendants() do
				if item:IsA("UIStroke") then
					UIKit.Tween(item, 0.6, { Transparency = 1 })
				end
			end
		end
	end)
	Debris:AddItem(board, 3)
end

function CelebrationController.Start(context)
	touch = UIKit.IsTouch()
	-- Their own layer: above the HUD, the toasts and windows (10), so nothing covers the moment.
	gui = UIKit.new("ScreenGui", {
		Name = "PartyPanicCelebrate",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 11,
		Parent = context.Hud.Parent,
	})

	Remotes.Get("Celebrate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or type(payload.Kind) ~= "string" then
			return
		end
		table.insert(queue, {
			Kind = payload.Kind,
			Level = tonumber(payload.Level),
			From = tonumber(payload.From),
			Coins = tonumber(payload.Coins) or 0,
			Items = if type(payload.Items) == "table" then payload.Items else {},
		})
		CelebrationController.Pump()
	end)
	Remotes.Get("LevelPop").OnClientEvent:Connect(function(character, level)
		if typeof(character) == "Instance" and type(level) == "number" then
			popOver(character, level)
		end
	end)
	GameState.Changed("Phase", function(phase)
		if CALM[phase] then
			CelebrationController.Pump()
		else
			CelebrationController.Dismiss() -- the vote or the round: out of the way
		end
	end)
	-- A window opening (shop, quests, the Rewards screen...) takes over.
	Modal.AnyOpenChanged:Connect(function(open)
		if open then
			CelebrationController.Dismiss()
		end
	end)
end

return CelebrationController
