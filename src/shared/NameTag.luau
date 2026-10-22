-- The name tag over a player's head (PP_Nameplate; Services/CosmeticService puts it on and redoes it
-- when something on it changes): their name with their level in its prestige colour (owner: "Also we
-- need cool payoffs for players that keep playing the game."), and their title under it.
--
-- The GOLD PASS (owner: "Also we do need a paid battle pass too. I like the current free one. But the
-- paid one should also be insane."): an owner's tag is taller, with a GOLD badge over the name (a gold
-- pill, "👑 GOLD") and the name in shimmering gold; a gold title shimmers in its own colours. The
-- gradients are tagged PP_GoldShimmer, and each device slides the glint across them (Controllers/
-- GoldPassController), so nothing is sent for the motion. Built here, apart from CosmeticService, so
-- the check tools can draw it too (tools/checks/client_harness.py's "Name tags").
-- The name stays a label called PlayerName right under the tag (Controllers/PartyController puts a
-- 👥 before it).

local CollectionService = game:GetService("CollectionService")

local Cosmetics = require(script.Parent.Cosmetics)
local GoldPass = require(script.Parent.GoldPass)
local Progression = require(script.Parent.Progression)

local NameTag = {}

NameTag.Name = "PP_Nameplate"
NameTag.ShimmerTag = "PP_GoldShimmer"

-- A gradient each device slides a glint across: "Sweep" runs a white glint over gold now and then,
-- "Drift" eases a title's colours to and fro.
function NameTag.Shimmer(target: GuiObject, colors: ColorSequence, kind: string): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Name = "GoldShimmer"
	gradient.Color = colors
	gradient:SetAttribute("PP_Shimmer", kind)
	gradient.Parent = target
	CollectionService:AddTag(gradient, NameTag.ShimmerTag)
	return gradient
end

-- The GOLD badge over an owner's name: a gold pill with a dark rim, "👑 GOLD".
local function goldBadge(gui: BillboardGui, height: number)
	local pill = Instance.new("Frame")
	pill.Name = "GoldBadge"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.fromScale(0.5, 0)
	pill.Size = UDim2.new(0, 78, height, 0)
	pill.BackgroundColor3 = Color3.new(1, 1, 1)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = pill
	local fill = Instance.new("UIGradient")
	fill.Color = ColorSequence.new(GoldPass.Colors.Light, GoldPass.Colors.Deep)
	fill.Rotation = 90
	fill.Parent = pill
	local rim = Instance.new("UIStroke")
	rim.Color = GoldPass.Colors.Ink
	rim.Thickness = 1.5
	rim.Parent = pill
	local label = Instance.new("TextLabel")
	label.Name = "Gold"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.08, 0.06)
	label.Size = UDim2.fromScale(0.84, 0.88)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "👑 GOLD"
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = GoldPass.Colors.Ink
	label.TextStrokeTransparency = 0.1
	label.Parent = pill
	pill.Parent = gui
end

-- A name tag for `displayName` at `level`, with `title` (equipped) under the name; `gold`: a GOLD
-- PASS owner's.
function NameTag.Build(displayName: string, level: number, gold: boolean, title: Cosmetics.Cosmetic?): BillboardGui
	-- An owner's tag is taller: the GOLD badge, then the name and the title as always.
	local badgeShare = if gold then 0.27 else 0
	local nameShare = if gold then 0.42 else 0.55
	local gui = Instance.new("BillboardGui")
	gui.Name = NameTag.Name
	gui.Size = UDim2.fromOffset(220, if gold then 74 else 54)
	gui.StudsOffset = Vector3.new(0, if gold then 2.75 else 2.4, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	if gold then
		goldBadge(gui, badgeShare - 0.02)
	end

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "PlayerName"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.fromScale(0, badgeShare)
	nameLabel.Size = UDim2.new(1, 0, nameShare, 0)
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.RichText = true
	local text, gradient = Progression.NameTag(displayName, level)
	nameLabel.Text = text
	if gold then
		NameTag.Shimmer(nameLabel, GoldPass.Shimmer, "Sweep") -- the gold name (over the tier's own colours)
	elseif gradient then
		local tint = Instance.new("UIGradient")
		tint.Color = gradient
		tint.Parent = nameLabel
	end
	nameLabel.Parent = gui

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.fromScale(0, badgeShare + nameShare)
	titleLabel.Size = UDim2.new(1, 0, if gold then 0.3 else 0.42, 0)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextScaled = true
	titleLabel.TextStrokeTransparency = 0.5
	titleLabel.Text = if title then `{title.Icon} {title.Name}` else ""
	titleLabel.TextColor3 = if title and title.Colors then title.Colors[1] else Color3.new(1, 1, 1)
	if title and title.GoldLevel then
		-- A gold title shimmers in its own colours (one colour: in gold).
		local colors = title.Colors or {}
		titleLabel.TextColor3 = Color3.new(1, 1, 1)
		NameTag.Shimmer(
			titleLabel,
			if #colors > 1 then Cosmetics.ColorSequence(colors) else GoldPass.Shimmer,
			if #colors > 1 then "Drift" else "Sweep"
		)
	end
	titleLabel.Parent = gui
	return gui
end

return NameTag
