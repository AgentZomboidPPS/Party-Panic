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
--
-- The crate seasons (Shared/Seasons; owner: "Hollow night comes first ... I want it to look insane."):
--   * THE HARVESTER (Hollow Night's 1-in-500 title, its Look "Harvester"): blackletter (Grenze
--     Gotisch) lit from inside, a gold-to-ember gradient with an orange glow round the letters and a
--     crescent moon either side (SeasonArt.Moon, or until it's uploaded a disc that fades from its
--     outer edge, which reads as a lit crescent: the fonts draw moon symbols as blanks). The title
--     label is tagged PP_HarvesterTitle; each device makes it flicker like a candle, breathes the
--     glow and sends embers up off it (Controllers/TitleController). The tag is no taller.
--   * Frames for crates opened (10, 50, 100, 250, 500) and a season finished (Logic/PlateFrames;
--     the server passes PP_CrateFrame and PP_SeasonComplete in `marks`): a dark pill behind the
--     words, as wide as they are, with the frame's rim. A moving rim is a PP_GoldShimmer gradient
--     (Controllers/GoldPassController moves those). No frame below 10 crates: the tag as before.

local CollectionService = game:GetService("CollectionService")
local TextService = game:GetService("TextService")

local Cosmetics = require(script.Parent.Cosmetics)
local GoldPass = require(script.Parent.GoldPass)
local PlateFrames = require(script.Parent.Logic.PlateFrames)
local Progression = require(script.Parent.Progression)
local SeasonArt = require(script.Parent.SeasonArt)
local Seasons = require(script.Parent.Seasons)

local NameTag = {}

NameTag.Name = "PP_Nameplate"
NameTag.ShimmerTag = "PP_GoldShimmer"
NameTag.HarvesterTag = "PP_HarvesterTitle" -- (Controllers/TitleController animates these)

-- What else a tag shows (the server reads it off the player: PP_CrateFrame, PP_SeasonComplete).
export type Marks = {
	CrateFrame: number?, -- the best crate milestone reached (0, 10, 50, 100, 250, 500)
	SeasonComplete: string?, -- a season whose items are all theirs ("" or nil: none)
}

local WIDTH = 220
local PLUM = Color3.fromRGB(28, 15, 46)
-- THE HARVESTER's fire, top to bottom: candle-white, amber, ember, deep red.
local HARVESTER_FLAME = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 244, 200)),
	ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 196, 70)),
	ColorSequenceKeypoint.new(0.7, Color3.fromRGB(255, 118, 34)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(196, 44, 26)),
})
local HARVESTER_GLOW = Color3.fromRGB(255, 106, 31)

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- How wide `text` is drawn at `size` (a TextScaled label shrinks it to fit `room`).
local function textWidth(text: string, size: number, font: Enum.Font, room: number): number
	local ok, bounds = pcall(TextService.GetTextSize, TextService, text, size, font, Vector2.new(1e4, 1e4))
	local width = if ok then bounds.X else #text * size * 0.55
	return math.min(width, room)
end

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

-- A crescent moon beside THE HARVESTER: the uploaded image, or a disc lit from its outer edge.
local function moon(gui: BillboardGui, x: number, y: UDim, size: number, left: boolean)
	local holder: GuiObject
	if SeasonArt.Moon ~= "" then
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Image = SeasonArt.Moon
		image.ImageColor3 = Color3.fromRGB(255, 214, 120)
		image.Rotation = if left then 0 else 180
		holder = image
	else
		local disc = Instance.new("Frame")
		disc.BackgroundColor3 = Color3.fromRGB(255, 220, 130)
		disc.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = disc
		local lit = Instance.new("UIGradient")
		lit.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.38, 0.05),
			NumberSequenceKeypoint.new(0.62, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		lit.Color = ColorSequence.new(Color3.fromRGB(255, 244, 200), Color3.fromRGB(255, 160, 60))
		lit.Rotation = if left then 0 else 180 -- (lit on its outer side)
		lit.Parent = disc
		holder = disc
	end
	holder.Name = if left then "MoonLeft" else "MoonRight"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.new(0.5, x, y.Scale, y.Offset)
	holder.Size = UDim2.fromOffset(size, size)
	holder.Parent = gui
end

-- The frame behind the words (Logic/PlateFrames): a dark pill with its rim, `width` wide.
local function plate(gui: BillboardGui, frame: PlateFrames.Frame, top: number, width: number)
	local pill = Instance.new("Frame")
	pill.Name = "CrateFrame"
	pill:SetAttribute("PP_Frame", frame.Kind)
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, top, 1)
	pill.Size = UDim2.new(0, width, 1 - top, -2)
	pill.BackgroundColor3 = PLUM
	pill.BackgroundTransparency = frame.Backing
	pill.BorderSizePixel = 0
	pill.ZIndex = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = pill
	local rim = Instance.new("UIStroke")
	rim.Name = "Rim"
	rim.Color = Color3.new(1, 1, 1)
	rim.Thickness = frame.Thickness
	rim.Transparency = 0.05
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Parent = pill
	local colors = {}
	for _, c in frame.Colors do
		table.insert(colors, rgb(c))
	end
	local gradient = Instance.new("UIGradient")
	gradient.Name = "RimColors"
	gradient.Color = Cosmetics.ColorSequence(colors)
	gradient.Parent = rim
	if frame.Shimmer then
		gradient:SetAttribute("PP_Shimmer", frame.Shimmer)
		CollectionService:AddTag(gradient, NameTag.ShimmerTag)
	end
	pill.Parent = gui
	-- What sits at each end: a leaf (a season finished) or a glowing ember.
	for _, side in { -1, 1 } do
		local x = side * width / 2
		if frame.Ends == "Leaf" then
			local leaf = Instance.new("TextLabel")
			leaf.Name = if side < 0 then "EndLeft" else "EndRight"
			leaf.BackgroundTransparency = 1
			leaf.AnchorPoint = Vector2.new(0.5, 0.5)
			leaf.Position = UDim2.new(0.5, x, (1 + top) / 2, 0)
			leaf.Size = UDim2.fromOffset(18, 18)
			leaf.Text = "🍂"
			leaf.TextScaled = true
			leaf.Rotation = side * 20
			leaf.ZIndex = 2
			leaf.Parent = gui
		elseif frame.Ends == "Ember" then
			local dot = Instance.new("Frame")
			dot.Name = if side < 0 then "EndLeft" else "EndRight"
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.new(0.5, x, (1 + top) / 2, 0)
			dot.Size = UDim2.fromOffset(7, 7)
			dot.BackgroundColor3 = Color3.fromRGB(255, 200, 100)
			dot.BorderSizePixel = 0
			dot.ZIndex = 2
			local round = Instance.new("UICorner")
			round.CornerRadius = UDim.new(1, 0)
			round.Parent = dot
			local glow = Instance.new("UIStroke")
			glow.Color = HARVESTER_GLOW
			glow.Thickness = 2
			glow.Transparency = 0.35
			glow.Parent = dot
			dot.Parent = gui
		end
	end
end

-- A name tag for `displayName` at `level`, with `title` (equipped) under the name; `gold`: a GOLD
-- PASS owner's; `marks`: the crate seasons' frame (nil: none).
function NameTag.Build(
	displayName: string,
	level: number,
	gold: boolean,
	title: Cosmetics.Cosmetic?,
	marks: Marks?
): BillboardGui
	local harvester = title ~= nil and title.Look == "Harvester"
	-- An owner's tag is taller: the GOLD badge, then the name and the title as always. THE
	-- HARVESTER's row is a little taller (blackletter wants the room), the name's a little shorter.
	local badgeShare = if gold then 0.27 else 0
	local nameShare = if gold then (if harvester then 0.37 else 0.42) else (if harvester then 0.5 else 0.55)
	local titleShare = if gold then (if harvester then 0.35 else 0.3) else (if harvester then 0.47 else 0.42)
	local height = if gold then 74 else 54
	local gui = Instance.new("BillboardGui")
	gui.Name = NameTag.Name
	gui.Size = UDim2.fromOffset(WIDTH, height)
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
	titleLabel.Size = UDim2.new(1, 0, titleShare, 0)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextScaled = true
	titleLabel.TextStrokeTransparency = 0.5
	titleLabel.Text = if title then `{title.Icon} {title.Name}` else ""
	titleLabel.TextColor3 = if title and title.Colors then title.Colors[1] else Color3.new(1, 1, 1)
	local rowPx = titleShare * height -- the title row's height in pixels
	local titleWidth = if title then textWidth(titleLabel.Text, math.floor(rowPx), titleLabel.Font, WIDTH) else 0
	if harvester and title then
		-- THE HARVESTER: blackletter lit from inside, an ember glow round it, a moon either side.
		local moonSize = math.floor(rowPx * 0.82)
		local room = WIDTH - 2 * (moonSize + 6)
		titleLabel.Text = title.Name
		titleLabel.Font = Enum.Font.GrenzeGotisch
		titleLabel.TextStrokeTransparency = 1
		titleLabel.TextColor3 = Color3.new(1, 1, 1)
		titleLabel.AnchorPoint = Vector2.new(0.5, 0)
		titleLabel.Position = UDim2.fromScale(0.5, badgeShare + nameShare)
		titleLabel.Size = UDim2.new(0, room, titleShare, 0)
		local flame = Instance.new("UIGradient")
		flame.Name = "Flame"
		flame.Color = HARVESTER_FLAME
		flame.Rotation = 90
		flame.Parent = titleLabel
		local glow = Instance.new("UIStroke")
		glow.Name = "Glow"
		glow.Color = HARVESTER_GLOW
		glow.Thickness = 1.8
		glow.Transparency = 0.25
		glow.LineJoinMode = Enum.LineJoinMode.Round
		glow.Parent = titleLabel
		titleWidth = textWidth(title.Name, math.floor(rowPx * 1.05), titleLabel.Font, room)
		local gap = titleWidth / 2 + moonSize / 2 + 4
		local y = UDim.new(badgeShare + nameShare + titleShare / 2, 0)
		moon(gui, -gap, y, moonSize, true)
		moon(gui, gap, y, moonSize, false)
		titleWidth += 2 * (moonSize + 4)
		CollectionService:AddTag(titleLabel, NameTag.HarvesterTag)
	elseif title and title.GoldLevel then
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

	-- The crate seasons' frame behind the words, as wide as the widest of them.
	local season = marks and marks.SeasonComplete and marks.SeasonComplete ~= "" and Seasons.Get(marks.SeasonComplete)
	local frame = PlateFrames.For(marks and marks.CrateFrame, if season then season.Colors else nil)
	if frame then
		local plain = string.gsub(text, "<[^>]+>", "")
		-- (The name gets room for the 👥 a party puts before it: Controllers/PartyController.)
		local nameWidth = textWidth(plain, math.floor(nameShare * height), nameLabel.Font, WIDTH) + 24
		local width = math.clamp(math.max(nameWidth, titleWidth) + 18, 96, WIDTH - 4)
		plate(gui, frame, badgeShare, math.floor(width))
	end
	return gui
end

return NameTag
