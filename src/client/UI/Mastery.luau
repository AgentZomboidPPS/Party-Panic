-- Game Mastery on screen (owner: "Let's build it. 1 yes 2 gold pass should help a little. 3 yes";
-- the rules are Shared/Logic/MasteryLogic, the server's Services/MasteryService): each rank's colours,
-- the round badge with the rank's medal on it, a game's progress from the profile, and today's
-- Spotlight games, for the vote cards, the rules card, the results card, the celebration card and
-- the Career screen's wall of games. Nothing here takes taps.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local GameState = require(Shared.GameState)
local MasteryLogic = require(Shared.Logic.MasteryLogic)

local Icons = require(script.Parent.Icons)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local Mastery = {}

Mastery.Ranks = Config.Mastery.Ranks :: { MasteryLogic.Rank }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Each rank's colours, top to bottom (index 0: not ranked yet).
local LOOKS: { [number]: { Top: Color3, Bottom: Color3 } } = {
	[0] = { Top = rgb(160, 150, 200), Bottom = rgb(92, 82, 140) },
	{ Top = rgb(246, 176, 116), Bottom = rgb(176, 92, 40) }, -- BRONZE
	{ Top = rgb(244, 247, 255), Bottom = rgb(146, 158, 192) }, -- SILVER
	{ Top = rgb(255, 228, 92), Bottom = rgb(228, 140, 20) }, -- GOLD
	{ Top = rgb(156, 242, 255), Bottom = rgb(60, 130, 245) }, -- DIAMOND
	{ Top = rgb(255, 146, 228), Bottom = rgb(140, 70, 255) }, -- LEGEND
}

function Mastery.Look(rank: number): { Top: Color3, Bottom: Color3 }
	return LOOKS[rank] or LOOKS[0]
end

function Mastery.Gradient(rank: number): ColorSequence
	local look = Mastery.Look(rank)
	return ColorSequence.new(look.Top, look.Bottom)
end

-- The rank's name ("GOLD"), or "NEW" before the first.
function Mastery.Name(rank: number): string
	local info = Mastery.Ranks[rank]
	return if info then info.Name else "NEW"
end

-- The rank's medal emoji (UI/Icons draws it), or a star before the first.
function Mastery.Icon(rank: number): string
	local info = Mastery.Ranks[rank]
	return if info then info.Icon else "⭐"
end

-- This player's entry for a game, from their profile (nil before they've played it since Mastery).
function Mastery.Entry(gameId: string): MasteryLogic.Entry?
	local profile = State.Profile
	local mastery = profile and profile.Mastery
	local entry = if type(mastery) == "table" then mastery[gameId] else nil
	if type(entry) ~= "table" then
		return nil
	end
	return { P = tonumber(entry.P) or 0, W = tonumber(entry.W) or 0, N = tonumber(entry.N) or 0 }
end

function Mastery.Progress(gameId: string): MasteryLogic.Progress
	return MasteryLogic.Progress(Mastery.Entry(gameId), Mastery.Ranks)
end

-- Today's Spotlight games (double points), as the server published them.
function Mastery.Spotlight(): { string }
	local list = GameState.GetJSON("Spotlight")
	return if type(list) == "table" then list else {}
end

function Mastery.IsSpotlight(gameId: string): boolean
	return table.find(Mastery.Spotlight(), gameId) ~= nil
end

-- A round badge in the rank's colours with its medal in the middle, `size` units across (props go on
-- the badge: Position, AnchorPoint, Parent, ...). Before the first rank it's a faint star.
function Mastery.Badge(rank: number, size: number, props: { [string]: any }?): Frame
	local badge = UIKit.new("Frame", {
		Name = "MasteryBadge",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Children = {
			UIKit.Round(),
			UIKit.new("UIGradient", { Color = Mastery.Gradient(rank), Rotation = 90 }),
			UIKit.Stroke(Theme.Colors.Ink, math.max(1.5, size / 16), 0),
		},
	})
	local parent = nil
	for property, value in (props or {}) :: { [string]: any } do
		if property == "Parent" then
			parent = value
		else
			(badge :: any)[property] = value
		end
	end
	local inner = math.floor(size * 0.74)
	local icon = Icons.Image(Mastery.Icon(rank), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(inner, inner),
		ImageTransparency = if rank == 0 then 0.45 else 0,
		ZIndex = badge.ZIndex + 1,
		Parent = badge,
	})
	if not icon then
		-- (before the icon sheet is uploaded: the emoji itself)
		UIKit.Label({
			Text = Mastery.Icon(rank),
			TextSize = math.floor(size * 0.6),
			TextWrapped = false,
			TextTransparency = if rank == 0 then 0.45 else 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = badge.ZIndex + 1,
			Parent = badge,
		})
	end
	badge.Parent = parent
	return badge
end

-- A progress bar in the next rank's colours, filled `fraction` of the way, with `text` on it.
function Mastery.Bar(
	nextRank: number,
	fraction: number,
	text: string,
	textSize: number,
	props: { [string]: any }
): Frame
	local bar = UIKit.new("Frame", {
		Name = "MasteryBar",
		BackgroundColor3 = Theme.Colors.PanelDark,
		Children = { UIKit.Round(), UIKit.Stroke(Theme.Colors.Ink, 2, 0) },
	})
	for property, value in props do
		if property ~= "Parent" then
			(bar :: any)[property] = value
		end
	end
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = bar.ZIndex,
		Parent = bar,
		Children = { UIKit.Round(), UIKit.new("UIGradient", { Color = Mastery.Gradient(nextRank), Rotation = 90 }) },
	})
	fill.Visible = fraction > 0
	UIKit.Label({
		Name = "Text",
		Text = text,
		Font = Theme.Fonts.Display,
		TextSize = textSize,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = bar.ZIndex + 1,
		Parent = bar,
		Children = { UIKit.TextStroke(0.1) },
	})
	bar.Parent = props.Parent
	return bar
end

-- A chip with the player's rank in a game and how far they are toward the next ("SILVER 14/20",
-- "GOLD WINS 2/3", "LEGEND MAX", "FIRST PLAY"), and a yellow "×2" on today's Spotlight games: as wide
-- as it needs, `height` units tall (the rules card's).
function Mastery.Chip(gameId: string, height: number, textSize: number): Frame
	local progress = Mastery.Progress(gameId)
	local text = if progress.Rank == 0
		then "FIRST PLAY"
		else `{Mastery.Name(progress.Rank)} {MasteryLogic.BarText(progress)}`
	local lit = Mastery.IsSpotlight(gameId)
	local badgeSize = height - 6
	local textWidth = math.ceil(UIKit.TextWidth(text, textSize, Theme.Fonts.Display) * 1.06) + 4
	local spotWidth = if lit then math.ceil(UIKit.TextWidth("×2", textSize, Theme.Fonts.Display)) + 20 else 0
	local width = 3 + badgeSize + 8 + textWidth + 12 + (if lit then spotWidth + 4 else 0)
	local chip = UIKit.new("Frame", {
		Name = "MasteryChip",
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.25,
		Children = { UIKit.Round(), UIKit.Stroke(Mastery.Look(progress.Rank).Top, 2, 0.1) },
	})
	Mastery.Badge(progress.Rank, badgeSize, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Parent = chip,
	})
	UIKit.Label({
		Name = "Rank",
		Text = text,
		Font = Theme.Fonts.Display,
		TextSize = textSize,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(3 + badgeSize + 8, 0),
		Size = UDim2.new(0, textWidth, 1, 0),
		Parent = chip,
		Children = { UIKit.TextStroke(0.2) },
	})
	if lit then
		UIKit.Label({
			Name = "Spotlight",
			Text = "×2",
			Font = Theme.Fonts.Display,
			TextSize = textSize,
			TextWrapped = false,
			TextColor3 = Theme.Colors.Ink,
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Colors.Yellow,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -4, 0.5, 0),
			Size = UDim2.fromOffset(spotWidth, height - 8),
			Parent = chip,
			Children = { UIKit.Round() },
		})
	end
	return chip
end

return Mastery
