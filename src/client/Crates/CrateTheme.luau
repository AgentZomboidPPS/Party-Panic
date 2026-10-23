-- The crate seasons' look on screen (Shared/Seasons; the design pages: "The same tier colors. Gold
-- coins, blue effects, purple hats and pink pets every season, so a pink beam means a pet whatever
-- the season. Only the title's beam takes the season's color"). Shared by the crate screens
-- (Controllers/CrateController), the openings (Crates/CrateShow), the banners and the lobby board.
--
-- Item pictures: the season's icon sheet (Shared/SeasonArt.Icons, one cell per item) once it's
-- uploaded, else the item's emoji. Never one of the glyphs the game's fonts draw as blanks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Cosmetics = require(Shared.Cosmetics)
local SeasonArt = require(Shared.SeasonArt)
local Seasons = require(Shared.Seasons)

local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local CrateTheme = {}

local function rgb(list: { number }): Color3
	return Color3.fromRGB(list[1], list[2], list[3])
end
CrateTheme.rgb = rgb

-- The season's own colours (Shared/Seasons Colors), as Color3s.
function CrateTheme.Colors(season: Seasons.Season?): { [string]: Color3 }
	local out = {}
	for key, value in (season or Seasons.CurrentSeason()).Colors do
		out[key] = rgb(value)
	end
	return out
end

-- Per tier: its colour (the beam, the card), its word, and its emoji.
CrateTheme.Tiers = {
	Title = { Color = Color3.fromRGB(255, 106, 31), Word = "TITLE", Icon = "👑", Rank = 1 },
	Pet = { Color = Color3.fromRGB(255, 92, 190), Word = "PET", Icon = "🐾", Rank = 2 },
	Hat = { Color = Color3.fromRGB(170, 100, 255), Word = "HAT", Icon = "🎩", Rank = 3 },
	Effect = { Color = Color3.fromRGB(70, 170, 255), Word = "EFFECT", Icon = "✨", Rank = 4 },
	Coins = { Color = Color3.fromRGB(255, 205, 50), Word = "COINS", Icon = "💰", Rank = 5 },
}

-- The title's colour is the season's.
function CrateTheme.TierColor(tier: string, season: Seasons.Season?): Color3
	if tier == "Title" then
		return rgb((season or Seasons.CurrentSeason()).Colors.Title)
	end
	local info = CrateTheme.Tiers[tier]
	return if info then info.Color else Theme.Colors.Text
end

-- The tier an item is in (Effect for auras, trails, knockouts and victories).
function CrateTheme.TierOf(itemId: string): string
	local item = Seasons.ItemById[itemId]
	if not item then
		return "Effect"
	end
	return if item.Slot == "Title" or item.Slot == "Pet" or item.Slot == "Hat" then item.Slot else "Effect"
end

-- What an effect is, in a word, for its card ("AURA", "TRAIL", "KNOCKOUT", "VICTORY").
function CrateTheme.KindOf(itemId: string): string
	local item = Seasons.ItemById[itemId]
	local slot = item and item.Slot or ""
	if slot == "Elimination" then
		return "KNOCKOUT"
	end
	return string.upper(slot)
end

function CrateTheme.NameOf(itemId: string): string
	local item = Seasons.ItemById[itemId] or Cosmetics.Get(itemId)
	return if item then item.Name else itemId
end

function CrateTheme.IconOf(itemId: string): string
	local item = Seasons.ItemById[itemId] or Cosmetics.Get(itemId)
	return if item then item.Icon else "📦"
end

-- A picture of an item: its cell of the icon sheet, or its emoji. Fills its parent.
function CrateTheme.Picture(itemId: string, parent: Instance, props: { [string]: any }?): GuiObject
	local cell = SeasonArt.IconCells[itemId]
	local base: { [string]: any } = {
		Name = "Picture",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	}
	local extra: { [string]: any } = props or {}
	for key, value in extra do
		base[key] = value
	end
	if SeasonArt.Icons ~= "" and cell then
		base.Image = SeasonArt.Icons
		base.ImageRectSize = Vector2.new(SeasonArt.IconSize, SeasonArt.IconSize)
		base.ImageRectOffset = Vector2.new(cell[1] * SeasonArt.IconSize, cell[2] * SeasonArt.IconSize)
		base.ScaleType = Enum.ScaleType.Fit
		base.Parent = parent
		return UIKit.new("ImageLabel", base)
	end
	base.Text = CrateTheme.IconOf(itemId)
	base.TextScaled = true
	base.Font = Theme.Fonts.Display
	base.TextColor3 = Color3.new(1, 1, 1)
	base.Parent = parent
	local label = UIKit.new("TextLabel", base)
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 120, Parent = label })
	return label
end

-- A silhouette for an item not found yet: its picture, dark.
function CrateTheme.Silhouette(itemId: string, parent: Instance): GuiObject
	local picture = CrateTheme.Picture(itemId, parent)
	if picture:IsA("ImageLabel") then
		picture.ImageColor3 = Color3.fromRGB(20, 10, 30)
		picture.ImageTransparency = 0.15
	elseif picture:IsA("TextLabel") then
		picture.Text = "?"
		picture.TextColor3 = Color3.fromRGB(150, 110, 150)
	end
	return picture
end

-- A season-coloured window: the crate screens' plum-to-dusk panel with an ember rim.
function CrateTheme.Dress(window: Frame, season: Seasons.Season?)
	local colors = CrateTheme.Colors(season)
	local gradient = window:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new(colors.Panel, colors.Deep)
	end
	local stroke = window:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = colors.Main
		stroke.Transparency = 0.35
		stroke.Thickness = 2.5
	end
end

-- "1 key", "5 keys".
function CrateTheme.Count(count: number, one: string, many: string?): string
	return if count == 1 then `1 {one}` else `{UIKit.FormatNumber(count)} {many or (one .. "s")}`
end

return CrateTheme
