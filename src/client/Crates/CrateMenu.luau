-- The crate season's window (the design page's "Collection log", "Top Unboxers", "Odds" and "Get
-- Keys" mock-ups; owner: "Also do all of your ideas."), opened from the lobby's crate chip, the
-- altars when someone's out of keys, the shop's crate items and State.OpenScreen:Fire("Crates", tab).
-- Tabs, phones first (44 pt buttons, 11 pt text or bigger; the lists scroll):
--   * CRATES: the season, the giant crate turning, your crates and keys, the Lantern Meter, and OPEN
--     (walks you to a free altar and opens there), OPEN HERE (over your head, wherever you are in
--     the lobby), OPEN 5, and how to get keys.
--   * COLLECTION: all 23 items in their tier colours, rarest first; one not found shows its
--     silhouette and its odds; tap one you have for the crate it came out of, the day, and EQUIP.
--     Past seasons get their own tab, VAULTED.
--   * TOP UNBOXERS: crates opened this season, this week and on this server, your own place, and the
--     first in the world to find each pet and the title (Services/CrateBoardService).
--   * ODDS: every outcome of your next crate with your own odds (no duplicates, so they change as
--     you collect: Logic/CrateLogic.PersonalOdds), adding up to exactly 100% (Roblox's rule for paid
--     random items: shown before any key can be bought).
--   * GET KEYS: the Robux key packs (Services/KeyShopService), the starter pack, GIFT for someone in
--     the server, and VIEW ODDS (in words: Roblox doesn't accept a bare info icon). Hidden for
--     players Roblox says can't buy paid random items (PP_KeysLocked): it says so, and that keys
--     they earn still open crates.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local CrateLogic = require(Shared.Logic.CrateLogic)
local DailyLogic = require(Shared.Logic.DailyLogic)
local GoldLane = require(Shared.Logic.GoldLane)
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)
local SeasonArt = require(Shared.SeasonArt)
local Seasons = require(Shared.Seasons)

local State = require(script.Parent.Parent.State)
local HubTabs = require(script.Parent.Parent.UI.HubTabs)
local Modal = require(script.Parent.Parent.UI.Modal)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local CrateTheme = require(script.Parent.CrateTheme)

local CrateMenu = {}

local player = Players.LocalPlayer
local remote = Remotes.Get("Crate")
-- The game's creator can open any item and TRY ON it for a playtest (Services/CosmeticService.TryOn:
-- this visit only, never owned or saved).
local creator = GoldLane.IsCreator(game.CreatorType.Name, game.CreatorId, Players.LocalPlayer.UserId)
local season = Seasons.CurrentSeason()
local colors = CrateTheme.Colors(season)
-- The window wears the game's own bright purple, like the shop, with the season's embers for its
-- accents (owner: "this screen sucks, too dark, hollow night font is bad, needs to be cleaned up and
-- have better UI"): its cards are the game's purple, not the season's dusk plum.
colors.Panel = Color3.fromRGB(98, 68, 186)
colors.Deep = Color3.fromRGB(60, 40, 128)
local EMPTY = Color3.fromRGB(50, 35, 104) -- a card for something not found yet

local TABS = {
	{ Key = "Crates", Label = "Crates", Icon = "📦" },
	{ Key = "Collection", Label = "Collection", Icon = "📖" },
	{ Key = "Top", Label = "Top Unboxers", Icon = "🏆" },
	{ Key = "Odds", Label = "Odds", Icon = "🎲" },
	{ Key = "Keys", Label = "Get Keys", Icon = "🔑" },
}
local MEDALS = { "🥇", "🥈", "🥉" }
local KEYS_HOW =
	"🔑 Keys: 3 · 2 · 1 for the top 3 of every round and the PARTY CUP podium, a key every 5th level and one per weekly quest."
local TITLE_FONT = Theme.Fonts.Display

local touch = false
local modal: Modal.Modal
local pages: { [string]: Frame } = {}
local tabButtons: { [string]: TextButton } = {}
local current = "Crates"
local boardKind = "Season"
local seasonShown = season.Id
local detailItem: string? = nil
local giftPack: string? = nil
local renderers: { [string]: () -> () } = {}

-- What the window does when OPEN / OPEN HERE / OPEN 5 is pressed (CrateController sets it).
CrateMenu.OnOpen = nil :: ((count: number, here: boolean) -> ())?

local function profile(): any
	return State.Profile
end

local function crates(): number
	local p = profile()
	return if p and p.Crates then p.Crates.Count or 0 else 0
end

local function keys(): number
	local p = profile()
	return if p then p.Keys or 0 else 0
end

local function progressOf(seasonId: string): { [string]: any }
	local p = profile()
	local seasons = p and p.Seasons
	local progress = seasons and seasons[seasonId]
	return if type(progress) == "table" then progress else { Opened = 0, Coins = 0, Meter = 0, Found = {} }
end

local function owned(): { [string]: boolean }
	local p = profile()
	return if p then p.Owned else {}
end

local function clear(frame: Instance)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function textSize(pc: number): number
	return if touch then math.max(Theme.Touch.MinText, pc) else pc
end

local function buttonHeight(): number
	return if touch then Theme.Touch.Target else 56
end

-- An ember-gradient headline in the game's display font.
local function headline(props: { [string]: any }): TextLabel
	local defaults: { [string]: any } = {
		Font = TITLE_FONT,
		TextSize = 44,
		TextWrapped = false,
		TextColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(1, 0, 0, 50),
		Children = {
			UIKit.new("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, colors.Gold),
					ColorSequenceKeypoint.new(0.55, colors.Glow),
					ColorSequenceKeypoint.new(1, colors.Main),
				}),
				Rotation = 90,
			}),
			UIKit.new("UIStroke", { Color = Color3.fromRGB(70, 20, 10), Thickness = 2, Transparency = 0.1 }),
		},
	}
	for key, value in props do
		defaults[key] = value
	end
	return UIKit.Label(defaults)
end

local function pill(parent: Instance, text: string, props: { [string]: any }): Frame
	local frame = UIKit.Panel({
		Size = props.Size or UDim2.fromOffset(200, 56),
		Position = props.Position,
		LayoutOrder = props.LayoutOrder,
		CornerRadius = 28,
		Parent = parent,
	}, props.Top or colors.Panel, props.Bottom or colors.Deep)
	UIKit.Label({
		Text = text,
		Font = Theme.Fonts.Display,
		TextSize = props.TextSize or textSize(22),
		TextWrapped = false,
		TextScaled = true,
		Size = UDim2.new(1, -20, 1, -12),
		Position = UDim2.fromOffset(10, 6),
		Parent = frame,
		Children = { UIKit.TextStroke(0.3), UIKit.new("UITextSizeConstraint", { MaxTextSize = props.TextSize or 24 }) },
	})
	return frame
end

-- The crates tab ----------------------------------------------------------------------------------

local viewportModel: Model? = nil

-- The giant crate turning in its little window (the season's mesh, when the server has sent it).
local function crateViewport(parent: Instance)
	local frame = UIKit.new("ViewportFrame", {
		Name = "Crate",
		Size = if touch then UDim2.fromOffset(240, 240) else UDim2.fromOffset(280, 280),
		Position = UDim2.fromOffset(if touch then 20 else 0, 10),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(150, 110, 120),
		LightColor = Color3.fromRGB(255, 200, 150),
		LightDirection = Vector3.new(-0.4, -1, -0.6),
		Parent = parent,
	})
	-- A warm glow behind it.
	UIKit.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromScale(0.9, 0.9),
		BackgroundColor3 = colors.Glow,
		BackgroundTransparency = 0.2,
		ZIndex = 0,
		Parent = frame,
		Children = {
			UIKit.Round(),
			UIKit.new("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.2),
					NumberSequenceKeypoint.new(0.6, 0.85),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		},
	})
	local folder = ReplicatedStorage:FindFirstChild("SeasonMeshes")
	local template = folder and folder:FindFirstChild(season.Props.Crate)
	if template and template:IsA("Model") then
		local model = template:Clone()
		model:PivotTo(CFrame.new())
		model.Parent = frame
		viewportModel = model
		local camera = Instance.new("Camera")
		camera.FieldOfView = 30
		camera.CFrame = CFrame.lookAt(Vector3.new(0, 4.2, -9.5), Vector3.new(0, 1.6, 0))
		camera.Parent = frame
		frame.CurrentCamera = camera
	else
		viewportModel = nil
		CrateTheme.Picture("Crate", frame, { Size = UDim2.fromScale(0.7, 0.7) })
	end
end

local function meterBar(parent: Instance, y: number, width: number)
	local progress = progressOf(season.Id)
	local meter = progress.Meter or 0
	local guaranteed = CrateLogic.Guaranteed(season, owned(), meter)
	local left = math.max(0, CrateLogic.Meter - meter)
	UIKit.Label({
		Text = `🏮 {string.upper(season.Meter)}  {meter}/{CrateLogic.Meter}`,
		Font = Theme.Fonts.Display,
		TextSize = textSize(20),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.fromOffset(width, 28),
		Parent = parent,
		Children = { UIKit.TextStroke(0.4) },
	})
	local track = UIKit.new("Frame", {
		Position = UDim2.fromOffset(0, y + 32),
		Size = UDim2.fromOffset(width, 20),
		BackgroundColor3 = EMPTY,
		Parent = parent,
		Children = { UIKit.Round(), UIKit.Stroke(colors.Main, 1.5, 0.5) },
	})
	UIKit.new("Frame", {
		Size = UDim2.fromScale(math.clamp(meter / CrateLogic.Meter, 0.02, 1), 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = track,
		Children = { UIKit.Round(), UIKit.Gradient(colors.Gold, colors.Main, 0) },
	})
	local missing = #CrateLogic.Missing(season, "Pet", owned())
	UIKit.Label({
		Text = if missing == 0
			then "Every pet found! The meter rests."
			elseif guaranteed then "Your next crate is a guaranteed pet!"
			else `{left} more crates without a pet, then one is guaranteed.`,
		TextSize = textSize(17),
		TextColor3 = if guaranteed then colors.Gold else Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, y + 56),
		Size = UDim2.fromOffset(width, 26),
		Parent = parent,
	})
end

local function renderCrates()
	local page = pages.Crates
	clear(page)
	crateViewport(page)
	-- Your crates and keys, what they are, the meter, then OPEN. Phones: the window's content is about
	-- 375 tall, so where keys come from goes under the crate there.
	local L = if touch
		then { Pill = 60, Rule = 68, Meter = 108, Open = 206, Gap = 10 }
		else { Pill = 60, Rule = 70, Meter = 112, Open = 214, Gap = 10 }
	UIKit.Label({
		Text = "Crates and keys never expire",
		TextSize = textSize(16),
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(0, if touch then 250 else 292),
		Size = UDim2.fromOffset(280, 24),
		Parent = page,
	})
	if touch then
		-- Where keys come from, in short, under the crate (the column has no room under the buttons on
		-- a phone; the whole line is in the key shop).
		local keysLine = UIKit.Label({
			Text = "🔑 Top 3 in every round win keys: 3 · 2 · 1. More on the PARTY CUP podium.",
			TextSize = textSize(16),
			TextColor3 = colors.Glow,
			Position = UDim2.fromOffset(0, 280),
			Size = UDim2.fromOffset(280, 72),
			Parent = page,
		})
		keysLine:SetAttribute("PP_Lines", 3)
	end
	local x = 300
	local width = 450 -- (the page is 754 wide: the crate's 280, a gap, then this column)
	local column = UIKit.new("Frame", {
		Position = UDim2.fromOffset(x, 0),
		Size = UDim2.new(1, -x, 1, 0),
		BackgroundTransparency = 1,
		Parent = page,
	})
	local half = (width - 10) / 2
	pill(column, `📦 {CrateTheme.Count(crates(), "CRATE", "CRATES")}`, {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(half, L.Pill),
		TextSize = textSize(26),
	})
	pill(column, `🔑 {CrateTheme.Count(keys(), "KEY", "KEYS")}`, {
		Position = UDim2.fromOffset(half + 10, 0),
		Size = UDim2.fromOffset(half, L.Pill),
		TextSize = textSize(26),
	})
	UIKit.Label({
		Text = "A crate every round · 1 key opens 1 crate",
		Font = Theme.Fonts.Display,
		TextSize = textSize(18),
		TextColor3 = colors.Glow,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, L.Rule),
		Size = UDim2.fromOffset(width, 26),
		Parent = column,
		Children = { UIKit.TextStroke(0.5) },
	})
	meterBar(column, L.Meter, width)

	local h = buttonHeight()
	local canOpen = crates() >= 1 and keys() >= 1
	local inRound = State.StillPlaying() -- (out of a round, back in the lobby, they open)
	local y = L.Open
	-- Each button says what it does: with no keys, it's the key shop.
	local noKeys = not inRound and crates() >= 1 and keys() < 1
	local openText = if inRound
		then "OPENS IN THE LOBBY"
		elseif crates() < 1 then "PLAY A ROUND FOR A CRATE"
		elseif noKeys then "🔑 GET KEYS"
		else "OPEN AT THE PILE"
	UIKit.Button(
		{
			Text = openText,
			TextSize = textSize(24),
			Size = UDim2.fromOffset(width, h),
			Position = UDim2.fromOffset(0, y),
			Parent = column,
		},
		function()
			if canOpen and not inRound and CrateMenu.OnOpen then
				modal:Close()
				CrateMenu.OnOpen(1, false)
			elseif noKeys then
				CrateMenu.Show("Keys")
			end
		end,
		if (canOpen and not inRound) or noKeys then colors.Glow else Theme.Colors.Muted,
		if (canOpen and not inRound) or noKeys then colors.Main else Theme.Colors.MutedDark
	)
	y += h + L.Gap
	local many = crates() >= CrateLogic.OpenMany and keys() >= CrateLogic.OpenMany
	UIKit.Button(
		{
			Text = "OPEN HERE",
			TextSize = textSize(20),
			Size = UDim2.fromOffset(half, h),
			Position = UDim2.fromOffset(0, y),
			Parent = column,
		},
		function()
			if canOpen and not inRound and CrateMenu.OnOpen then
				modal:Close()
				CrateMenu.OnOpen(1, true)
			end
		end,
		if canOpen and not inRound then Theme.Colors.Lavender else Theme.Colors.Muted,
		if canOpen and not inRound then Theme.Colors.Purple else Theme.Colors.MutedDark
	)
	UIKit.Button(
		{
			Text = `OPEN {CrateLogic.OpenMany}`,
			TextSize = textSize(20),
			Size = UDim2.fromOffset(half, h),
			Position = UDim2.fromOffset(half + 10, y),
			Parent = column,
		},
		function()
			if many and not inRound and CrateMenu.OnOpen then
				modal:Close()
				CrateMenu.OnOpen(CrateLogic.OpenMany, false)
			elseif not inRound and crates() >= CrateLogic.OpenMany then
				CrateMenu.Show("Keys") -- (the crates are there, the keys aren't)
			end
		end,
		if many and not inRound then colors.Gold else Theme.Colors.Muted,
		if many and not inRound then colors.Main else Theme.Colors.MutedDark
	)
	if touch then
		return
	end
	y += h + 12
	UIKit.Label({
		Text = KEYS_HOW,
		TextSize = textSize(16),
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.fromOffset(width, 64),
		Parent = column,
	})
end
renderers.Crates = renderCrates

-- The collection tab ------------------------------------------------------------------------------

local function foundLine(seasonId: string, itemId: string): string
	local progress = progressOf(seasonId)
	local found = progress.Found and progress.Found[itemId]
	if type(found) ~= "table" then
		return "Found"
	end
	local day = tonumber(found.Day)
	local date = if day then os.date("!%b %d", day * 86400) else nil
	return `Crate #{found.Crate or "?"}{if date then ` · {date}` else ""}`
end

local function itemOdds(itemId: string): string
	for _, row in CrateLogic.PersonalOdds(season, owned(), progressOf(season.Id).Meter or 0) do
		if row.Key == itemId then
			return CrateLogic.Percent(row.Chance)
		end
	end
	return ""
end

local detail: Frame? = nil

-- An item's details take the collection's place (a page of its own, BACK to the grid), so nothing
-- of the grid shows round it.
local function closeDetail()
	detailItem = nil
	if detail then
		detail.Visible = false
	end
	local page = pages[current]
	if page then
		page.Visible = true
	end
end

local function showDetail(itemId: string)
	local frame = detail
	if not frame then
		return
	end
	detailItem = itemId
	clear(frame)
	frame.Visible = true
	local page = pages[current]
	if page then
		page.Visible = false
	end
	local item = Seasons.ItemById[itemId]
	local tier = CrateTheme.TierOf(itemId)
	local tierColor = CrateTheme.TierColor(tier, Seasons.SeasonOf(itemId))
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = tierColor
		stroke.Transparency = 0.1
	end
	-- The picture on the left; what it is, what it does and where it came from on the right; EQUIP
	-- and BACK along the bottom.
	local artSize = if touch then 196 else 240
	local art = UIKit.new("Frame", {
		Position = UDim2.fromOffset(20, 20),
		Size = UDim2.fromOffset(artSize, artSize),
		BackgroundColor3 = colors.Deep,
		Parent = frame,
		Children = { UIKit.Corner(18), UIKit.Stroke(tierColor, 2, 0.3) },
	})
	UIKit.new("UIGradient", {
		Color = ColorSequence.new(tierColor:Lerp(colors.Deep, 0.55), colors.Deep),
		Rotation = 90,
		Parent = art,
	})
	CrateTheme.Picture(itemId, art, { Size = UDim2.fromScale(0.82, 0.82) })
	local x = 20 + artSize + 24
	local kind = if tier == "Effect" then CrateTheme.KindOf(itemId) else CrateTheme.Tiers[tier].Word
	UIKit.Label({
		Text = `{CrateTheme.Tiers[tier].Icon} {kind}`,
		Font = Theme.Fonts.Display,
		TextSize = textSize(20),
		TextColor3 = tierColor,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		Position = UDim2.fromOffset(x, 24),
		Size = UDim2.new(1, -(x + 20), 0, 26),
		Parent = frame,
		Children = { UIKit.TextStroke(0.4) },
	})
	UIKit.Label({
		Text = if item then item.Name else itemId,
		Font = if tier == "Title" then TITLE_FONT else Theme.Fonts.Display,
		TextSize = 44,
		TextScaled = true,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(x, 52),
		Size = UDim2.new(1, -(x + 20), 0, 52),
		Parent = frame,
		Children = { UIKit.TextStroke(0.3), UIKit.new("UITextSizeConstraint", { MaxTextSize = 44 }) },
	})
	local description = UIKit.Label({
		Text = if item then item.Description else "",
		TextSize = textSize(19),
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(x, 110),
		Size = UDim2.new(1, -(x + 20), 0, 76),
		Parent = frame,
	})
	description:SetAttribute("PP_Lines", 3)
	local have = owned()[itemId] == true
	UIKit.Label({
		Text = if have then `📦 {foundLine(seasonShown, itemId)}` else "🧪 Creator test: worn this visit only",
		Font = Theme.Fonts.Display,
		TextSize = textSize(19),
		TextColor3 = colors.Glow,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		Position = UDim2.fromOffset(x, 192),
		Size = UDim2.new(1, -(x + 20), 0, 28),
		Parent = frame,
	})
	local p = profile()
	local slot = item and item.Slot or ""
	local wearing = p and p.Equipped and p.Equipped[slot] == itemId
	local h = buttonHeight()
	if not have then
		UIKit.Button({
			Text = "TRY ON",
			TextSize = textSize(22),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, x, 1, -18),
			Size = UDim2.fromOffset(220, h),
			Parent = frame,
		}, function()
			remote:FireServer("TryOn", itemId)
			closeDetail()
		end, Theme.Colors.Green, Color3.fromRGB(60, 160, 90))
	end
	UIKit.Button(
		{
			Visible = have,
			Text = if wearing then "TAKE OFF" else "EQUIP",
			TextSize = textSize(22),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, x, 1, -18),
			Size = UDim2.fromOffset(220, h),
			Parent = frame,
		},
		function()
			Remotes.Get("ShopEquip"):FireServer(slot, if wearing then "" else itemId)
			closeDetail()
		end,
		if wearing then Theme.Colors.Lavender else Theme.Colors.Green,
		if wearing then Theme.Colors.Purple else Color3.fromRGB(60, 160, 90)
	)
	UIKit.Button({
		Text = "BACK",
		TextSize = textSize(22),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -18),
		Size = UDim2.fromOffset(170, h),
		Parent = frame,
	}, closeDetail, Theme.Colors.Lavender, Theme.Colors.Purple)
	UIKit.PopIn(frame, 0.2)
end

local function card(parent: Instance, itemId: string, order: number, have: boolean, vaulted: boolean): TextButton
	local tier = CrateTheme.TierOf(itemId)
	local tierColor = CrateTheme.TierColor(tier, Seasons.SeasonOf(itemId))
	local button = UIKit.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = if have then colors.Panel else EMPTY,
		LayoutOrder = order,
		Parent = parent,
		Children = {
			UIKit.Corner(14),
			UIKit.new("UIStroke", {
				Color = tierColor,
				Thickness = if have then 2.5 else 1.5,
				Transparency = if have then 0.05 else 0.55,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		},
	})
	if have then
		UIKit.new("UIGradient", {
			Color = ColorSequence.new(tierColor:Lerp(colors.Panel, 0.55), colors.Deep),
			Rotation = 90,
			Parent = button,
		})
	end
	-- Phones: 11 pt text at the least, so the name gets two lines and the picture a little less room.
	local art = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.15, 0.05),
		Size = UDim2.fromScale(0.7, if touch then 0.5 else 0.56),
		Parent = button,
	})
	if have then
		CrateTheme.Picture(itemId, art)
	else
		CrateTheme.Silhouette(itemId, art)
	end
	local p = profile()
	local item = Seasons.ItemById[itemId]
	local wearing = have and p and item and p.Equipped and p.Equipped[item.Slot] == itemId
	UIKit.Label({
		Text = if have then CrateTheme.NameOf(itemId) else "???",
		Font = Theme.Fonts.Display,
		TextSize = textSize(17),
		TextScaled = not touch,
		TextWrapped = touch,
		LineHeight = 0.9,
		Position = UDim2.new(0, 6, if touch then 0.56 else 0.64, 0),
		Size = UDim2.new(1, -12, if touch then 0.25 else 0.17, 0),
		Parent = button,
		Children = if touch
			then { UIKit.TextStroke(0.4) }
			else { UIKit.TextStroke(0.4), UIKit.new("UITextSizeConstraint", { MaxTextSize = 18 }) },
	})
	UIKit.Label({
		Text = if wearing then "ON" elseif have then "TAP TO SEE" elseif vaulted then "VAULTED" else itemOdds(itemId),
		Font = Theme.Fonts.Display,
		TextSize = textSize(15),
		TextScaled = not touch,
		TextColor3 = if wearing then Theme.Colors.Green elseif have then Theme.Colors.TextDim else tierColor,
		Position = UDim2.new(0, 6, 0.81, 0),
		Size = UDim2.new(1, -12, 0.15, 0),
		Parent = button,
		Children = if touch then {} else { UIKit.new("UITextSizeConstraint", { MaxTextSize = 16 }) },
	})
	button.Activated:Connect(function()
		if have or creator then
			showDetail(itemId)
		end
	end)
	return button
end

local function section(parent: Instance, order: number, text: string, color: Color3)
	UIKit.Label({
		Text = text,
		Font = Theme.Fonts.Display,
		TextSize = textSize(20),
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = order,
		Parent = parent,
		Children = { UIKit.TextStroke(0.4) },
	})
end

local function grid(parent: Instance, order: number, perRow: number, height: number): Frame
	local frame = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = parent,
		Children = {
			UIKit.new("UIGridLayout", {
				CellSize = UDim2.new(1 / perRow, -10, 0, height),
				CellPadding = UDim2.fromOffset(10, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
	})
	return frame
end

local function renderCollection()
	local page = pages.Collection
	clear(page)
	local shown = Seasons.Get(seasonShown) or season
	local vaulted = shown.Id ~= Seasons.Current
	local have = owned()
	local found, total = CrateLogic.Progress(shown, have)
	local progress = progressOf(shown.Id)
	-- The season tabs (past seasons are vaulted; with one season, just its name), then the summary.
	local several = #Seasons.Order > 1
	local headerHeight = if several and touch then Theme.Touch.Target else 44
	local header = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, headerHeight),
		Parent = page,
		Children = { UIKit.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left) },
	})
	for order = #Seasons.Order, 1, -1 do
		local id = Seasons.Order[order]
		local info = Seasons.Get(id)
		if info and not several then
			UIKit.Label({
				Text = `📖 {found} OF {total} FOUND`,
				Font = Theme.Fonts.Display,
				TextSize = textSize(22),
				TextColor3 = colors.Glow,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = false,
				Size = UDim2.new(0.45, 0, 1, 0),
				Parent = header,
				Children = { UIKit.TextStroke(0.3) },
			})
		elseif info then
			local label = if id == Seasons.Current then info.Name else `{info.Name} · VAULTED`
			UIKit.Button(
				{
					Text = label,
					TextSize = textSize(18),
					Size = UDim2.fromOffset(
						math.ceil(UIKit.TextWidth(label, textSize(18), Theme.Fonts.Display)) + 36,
						headerHeight
					),
					LayoutOrder = #Seasons.Order - order,
					Parent = header,
				},
				function()
					seasonShown = id
					closeDetail()
					renderCollection()
				end,
				if id == seasonShown then colors.Glow else Theme.Colors.Lavender,
				if id == seasonShown then colors.Main else Theme.Colors.Purple
			)
		end
	end
	UIKit.Label({
		Text = `{if several then `{found} of {total} · ` else ""}{UIKit.FormatNumber(progress.Opened or 0)} crates opened · {UIKit.FormatNumber(
			progress.Coins or 0
		)} coins`,
		Font = Theme.Fonts.Display,
		TextSize = textSize(18),
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.new(0.55, 0, 0, 30),
		Parent = page,
	})

	local list = UIKit.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, headerHeight + 8),
		Size = UDim2.new(1, 0, 1, -(headerHeight + 8)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = page,
		Children = {
			UIKit.List(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left),
			UIKit.new("UIPadding", { PaddingRight = UDim.new(0, 14), PaddingBottom = UDim.new(0, 10) }),
		},
	})
	-- The title: one wide card, in its own look.
	local titleHave = have[shown.Title] == true
	local titleColor = CrateTheme.TierColor("Title", shown)
	local titleCard = UIKit.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.new(1, 0, 0, 96),
		BackgroundColor3 = if titleHave then colors.Panel else EMPTY,
		LayoutOrder = 1,
		Parent = list,
		Children = {
			UIKit.Corner(16),
			UIKit.new("UIStroke", { Color = titleColor, Thickness = 2.5, Transparency = if titleHave then 0 else 0.4 }),
		},
	})
	headline({
		Text = if titleHave then CrateTheme.NameOf(shown.Title) else "THE ??????",
		TextSize = 46,
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 52),
		Parent = titleCard,
	})
	UIKit.Label({
		Text = if titleHave
			then `THE TITLE · {foundLine(shown.Id, shown.Title)}`
			elseif vaulted then "THE TITLE · VAULTED"
			else `THE TITLE · 1 in 500 · {itemOdds(shown.Title)}`,
		Font = Theme.Fonts.Display,
		TextSize = textSize(17),
		TextColor3 = titleColor,
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.new(1, 0, 0, 24),
		Parent = titleCard,
	})
	titleCard.Activated:Connect(function()
		if titleHave then
			showDetail(shown.Title)
		end
	end)

	local petCard = if touch then 168 else 150
	section(
		list,
		2,
		`🐾 PETS · {CrateTheme.Count(#shown.Pets - #CrateLogic.Missing(shown, "Pet", have), "found", "found")}`,
		CrateTheme.Tiers.Pet.Color
	)
	local pets = grid(list, 3, 5, petCard)
	for index, id in shown.Pets do
		card(pets, id, index, have[id] == true, vaulted)
	end
	section(list, 4, "🎩 HATS", CrateTheme.Tiers.Hat.Color)
	local hats = grid(list, 5, 5, petCard)
	for index, id in shown.Hats do
		card(hats, id, index, have[id] == true, vaulted)
	end
	section(list, 6, "✨ AURAS · TRAILS · KNOCKOUTS · VICTORIES", CrateTheme.Tiers.Effect.Color)
	local effects = grid(list, 7, if touch then 4 else 6, if touch then 160 else 140)
	for index, id in shown.Effects do
		card(effects, id, index, have[id] == true, vaulted)
	end
	if found == total then
		section(list, 8, `🏮 {shown.Name} COMPLETE! Your name tag wears its frame.`, colors.Gold)
	end
end
renderers.Collection = renderCollection

-- Top Unboxers ------------------------------------------------------------------------------------

local function board(): { [string]: any }?
	local data = GameState.GetJSON("CrateBoard")
	return if type(data) == "table" then data else nil
end

local function renderTop()
	local page = pages.Top
	clear(page)
	local data = board()
	local h = if touch then Theme.Touch.Target else 46
	local kinds = {
		{ Key = "Season", Label = "SEASON", Rows = "Top" },
		{ Key = "Week", Label = "THIS WEEK", Rows = "WeekTop" },
		{ Key = "Server", Label = "THIS SERVER", Rows = "Server" },
	}
	local left = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0.6, -10, 1, 0),
		Parent = page,
	})
	local toggles = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, h),
		Parent = left,
		Children = { UIKit.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left) },
	})
	local rowsKey = "Top"
	for order, kind in kinds do
		if kind.Key == boardKind then
			rowsKey = kind.Rows
		end
		UIKit.Button(
			{
				Text = kind.Label,
				TextSize = textSize(18),
				Size = UDim2.new(1 / 3, -6, 0, h),
				LayoutOrder = order,
				Parent = toggles,
			},
			function()
				boardKind = kind.Key
				renderTop()
			end,
			if kind.Key == boardKind then colors.Glow else Theme.Colors.Lavender,
			if kind.Key == boardKind then colors.Main else Theme.Colors.Purple
		)
	end
	local rows = UIKit.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, h + 10),
		Size = UDim2.new(1, 0, 1, -(h + 10) - 50),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = left,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left) },
	})
	local list = data and data[rowsKey]
	if type(list) ~= "table" or #list == 0 then
		UIKit.Label({
			Text = if data then "No crates opened yet. Be the first!" else "Loading the board...",
			TextSize = textSize(20),
			TextColor3 = Theme.Colors.TextDim,
			Size = UDim2.new(1, 0, 0, 60),
			Parent = rows,
		})
	else
		for index, row in list do
			local mine = row.UserId == player.UserId
			local line = UIKit.Panel({
				Size = UDim2.new(1, -10, 0, if touch then 44 else 38),
				LayoutOrder = index,
				CornerRadius = 12,
				Parent = rows,
			}, if mine then colors.Main else colors.Panel, if mine then colors.Crimson else colors.Deep)
			UIKit.Label({
				Text = `{MEDALS[index] or `#{index}`}  {row.Name}`,
				Font = Theme.Fonts.Display,
				TextSize = textSize(19),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Position = UDim2.fromOffset(12, 0),
				Size = UDim2.new(1, -120, 1, 0),
				Parent = line,
				Children = { UIKit.TextStroke(0.4) },
			})
			UIKit.Label({
				Text = `📦 {UIKit.FormatNumber(row.Opened or 0)}`,
				Font = Theme.Fonts.Display,
				TextSize = textSize(19),
				TextColor3 = colors.Gold,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 0),
				Size = UDim2.fromOffset(110, if touch then 44 else 38),
				Parent = line,
			})
		end
	end
	-- Your own line.
	local progress = progressOf(season.Id)
	local week = DailyLogic.WeekNumber(os.time())
	local yours = if boardKind == "Week"
		then (if progress.Week == week then progress.WeekOpened or 0 else 0)
		else progress.Opened or 0
	local rank = player:GetAttribute(if boardKind == "Week" then "PP_CrateWeekRank" else "PP_CrateRank")
	UIKit.Label({
		Text = if boardKind == "Server"
			then "Crates opened on this server since it started"
			else `YOU: {if type(rank) == "number" and rank > 0 then `#{rank}` else "not in the top 100 yet"} · 📦 {UIKit.FormatNumber(
				yours
			)}`,
		Font = Theme.Fonts.Display,
		TextSize = textSize(19),
		TextColor3 = colors.Glow,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 4, 1, 0),
		Size = UDim2.new(1, -8, 0, 40),
		Parent = left,
	})

	-- First in the world.
	local right = UIKit.Panel({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.4, 0, 1, 0),
		CornerRadius = 16,
		Parent = page,
	}, colors.Panel, colors.Deep)
	UIKit.Label({
		Text = "🌍 FIRST IN THE WORLD",
		Font = Theme.Fonts.Display,
		TextSize = textSize(20),
		TextColor3 = colors.Gold,
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.new(1, -20, 0, 30),
		Parent = right,
		Children = { UIKit.TextStroke(0.3) },
	})
	local firsts = data and data.Firsts or {}
	local items = { season.Title }
	for _, pet in season.Pets do
		table.insert(items, pet)
	end
	for index, id in items do
		local first = type(firsts) == "table" and firsts[id]
		local y = 44 + (index - 1) * (if touch then 52 else 46)
		local art = UIKit.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(10, y),
			Size = UDim2.fromOffset(40, 40),
			Parent = right,
		})
		CrateTheme.Picture(id, art)
		UIKit.Label({
			Text = CrateTheme.NameOf(id),
			Font = Theme.Fonts.Display,
			TextSize = textSize(16),
			TextColor3 = CrateTheme.TierColor(CrateTheme.TierOf(id), season),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(58, y - 2),
			Size = UDim2.new(1, -66, 0, 22),
			Parent = right,
		})
		local firstLine = UIKit.Label({
			Text = if type(first) == "table"
				then `{first.Name} · {os.date("!%b %d", (tonumber(first.Day) or 0) * 86400)}`
				else "Not found yet!",
			TextSize = textSize(15),
			TextColor3 = if type(first) == "table" then Theme.Colors.Text else Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(58, y + 18),
			Size = UDim2.new(1, -66, 0, 20),
			Parent = right,
		})
		firstLine:SetAttribute("PP_TruncateOk", true) -- (a long name ends in "...")
	end
end
renderers.Top = renderTop

-- Odds --------------------------------------------------------------------------------------------

local function renderOdds()
	local page = pages.Odds
	clear(page)
	local have = owned()
	local meter = progressOf(season.Id).Meter or 0
	local rows = CrateLogic.PersonalOdds(season, have, meter)
	local list = UIKit.new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = page,
		Children = {
			UIKit.List(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Left),
			UIKit.new("UIPadding", { PaddingRight = UDim.new(0, 14), PaddingBottom = UDim.new(0, 10) }),
		},
	})
	local rowHeight = if touch then 44 else 36
	local headHeight = if touch then 52 else 44
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local intro = UIKit.Label({
		Text = "🎲 Every outcome of your next crate. You never get the same item twice, so these change as you collect.",
		TextSize = textSize(17),
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, if touch then 52 else 44),
		LayoutOrder = nextOrder(),
		Parent = list,
	})
	intro:SetAttribute("PP_Lines", 2)

	-- One card per tier: its name and total in its colour, then each outcome with its picture.
	local function tierCard(color: Color3): Frame
		local cardFrame = UIKit.Panel({
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			CornerRadius = 16,
			LayoutOrder = nextOrder(),
			Parent = list,
			Children = { UIKit.List(Enum.FillDirection.Vertical, 2), UIKit.Padding(8, 12) },
		}, colors.Panel, colors.Deep)
		local stroke = cardFrame:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = color
			stroke.Transparency = 0.25
			stroke.Thickness = 2
		end
		return cardFrame
	end
	local function header(cardFrame: Frame, title: string, right: string, color: Color3, pillColor: Color3)
		local head = UIKit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, headHeight),
			LayoutOrder = 0,
			Parent = cardFrame,
		})
		UIKit.Label({
			Text = title,
			Font = Theme.Fonts.Display,
			TextSize = textSize(22),
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.new(1, -150, 1, 0),
			Parent = head,
			Children = { UIKit.TextStroke(0.3) },
		})
		local pill = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(140, headHeight - 12),
			BackgroundColor3 = pillColor,
			Parent = head,
			Children = { UIKit.Round() },
		})
		UIKit.Label({
			Text = right,
			Font = Theme.Fonts.Display,
			TextSize = textSize(20),
			TextWrapped = false,
			Size = UDim2.fromScale(1, 1),
			Parent = pill,
			Children = { UIKit.TextStroke(0.2) },
		})
	end
	local function outcome(cardFrame: Frame, index: number, picture: string?, name: string, chance: string)
		local row = UIKit.new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = if index % 2 == 1 then 0.92 else 1,
			Size = UDim2.new(1, 0, 0, rowHeight),
			LayoutOrder = index,
			Parent = cardFrame,
			Children = { UIKit.Corner(10) },
		})
		local art = UIKit.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(6, 3),
			Size = UDim2.fromOffset(rowHeight - 6, rowHeight - 6),
			Parent = row,
		})
		if picture then
			CrateTheme.Picture(picture, art)
		else
			UIKit.Label({ Text = Theme.CoinIcon, TextScaled = true, Size = UDim2.fromScale(1, 1), Parent = art })
		end
		UIKit.Label({
			Text = name,
			Font = Theme.Fonts.Bold,
			TextSize = textSize(18),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(rowHeight + 8, 0),
			Size = UDim2.new(1, -(rowHeight + 8) - 110, 1, 0),
			Parent = row,
		})
		UIKit.Label({
			Text = chance,
			Font = Theme.Fonts.Display,
			TextSize = textSize(18),
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 0),
			Size = UDim2.fromOffset(100, rowHeight),
			Parent = row,
		})
	end

	local names = { Title = "THE TITLE", Pet = "PETS", Hat = "HATS", Effect = "EFFECTS", Coins = "COINS" }
	local total = 0
	for _, tier in { "Title", "Pet", "Hat", "Effect", "Coins" } do
		local tierRows = {}
		local tierTotal = 0
		for _, row in rows do
			if row.Tier == tier then
				table.insert(tierRows, row)
				tierTotal += row.Chance
			end
		end
		local info = CrateTheme.Tiers[tier]
		local color = CrateTheme.TierColor(tier, season)
		local missing = if tier ~= "Coins" then #CrateLogic.Missing(season, tier :: any, have) else 0
		if #tierRows == 0 then
			-- A finished tier is out of the roll (its share is in the coins).
			if tier ~= "Coins" and missing == 0 then
				header(tierCard(color), `{info.Icon} {names[tier]}`, "✓ ALL FOUND", color, Theme.Colors.Green)
			end
			continue
		end
		total += tierTotal
		local cardFrame = tierCard(color)
		local left = if tier ~= "Coins" and tier ~= "Title" then ` · {missing} LEFT` else ""
		header(cardFrame, `{info.Icon} {names[tier]}{left}`, CrateLogic.Percent(tierTotal), color, color)
		for index, row in tierRows do
			if row.Tier == "Coins" then
				outcome(cardFrame, index, nil, row.Label, CrateLogic.Percent(row.Chance))
			else
				outcome(cardFrame, index, row.Key, CrateTheme.NameOf(row.Key), CrateLogic.Percent(row.Chance))
			end
		end
	end
	local totalCard = tierCard(colors.Gold)
	header(totalCard, "TOTAL", CrateLogic.Percent(total), colors.Gold, colors.Main)
	local missingPets = #CrateLogic.Missing(season, "Pet", have)
	local note = UIKit.Label({
		Text = if missingPets == 0
			then `🏮 {season.Meter}: every pet found.`
			elseif
				CrateLogic.Guaranteed(season, have, meter)
			then `🏮 {season.Meter}: your next crate is a guaranteed pet (shown above).`
			else `🏮 {season.Meter}: {CrateLogic.Meter - meter} more crates without a pet or the title, then the next is a guaranteed pet you don't own. A friend standing near you when you open adds a point.`,
		TextSize = textSize(17),
		TextColor3 = colors.Glow,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, if touch then 78 else 52),
		LayoutOrder = nextOrder(),
		Parent = list,
	})
	note:SetAttribute("PP_Lines", 3)
end
renderers.Odds = renderOdds

-- Get Keys ----------------------------------------------------------------------------------------

local giftPicker: Frame? = nil

local function shop(): { [string]: any }?
	local data = GameState.GetJSON("KeyShop")
	return if type(data) == "table" then data else nil
end

-- The gift picker takes the key shop's place, as an item's details do the collection's.
local function closeGift()
	giftPack = nil
	if giftPicker then
		giftPicker.Visible = false
	end
	local page = pages[current]
	if page then
		page.Visible = true
	end
end

local function openGift(pack: { [string]: any })
	local frame = giftPicker
	if not frame then
		return
	end
	giftPack = pack.Key
	clear(frame)
	frame.Visible = true
	local page = pages[current]
	if page then
		page.Visible = false
	end
	UIKit.PopIn(frame, 0.2)
	UIKit.Label({
		Text = `🎁 GIFT {CrateTheme.Count(pack.Keys, "KEY")} TO...`,
		Font = Theme.Fonts.Display,
		TextSize = textSize(24),
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.new(1, -32, 0, 32),
		ZIndex = 41,
		Parent = frame,
		Children = { UIKit.TextStroke(0.3) },
	})
	local list = UIKit.new("ScrollingFrame", {
		Position = UDim2.fromOffset(16, 52),
		Size = UDim2.new(1, -32, 1, -52 - buttonHeight() - 30),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 41,
		Parent = frame,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left) },
	})
	local count = 0
	for _, other in Players:GetPlayers() do
		if other ~= player then
			count += 1
			UIKit.Button({
				Text = other.DisplayName,
				TextSize = textSize(20),
				Size = UDim2.new(1, -10, 0, buttonHeight()),
				LayoutOrder = count,
				ZIndex = 42,
				Parent = list,
			}, function()
				remote:FireServer("Buy", pack.Key, other.UserId)
				closeGift()
			end, colors.Glow, colors.Main)
		end
	end
	if count == 0 then
		UIKit.Label({
			Text = "Nobody else is here right now.",
			TextSize = textSize(18),
			TextColor3 = Theme.Colors.TextDim,
			Size = UDim2.new(1, 0, 0, 40),
			ZIndex = 41,
			Parent = list,
		})
	end
	UIKit.Button({
		Text = "CANCEL",
		TextSize = textSize(20),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(200, buttonHeight()),
		ZIndex = 42,
		Parent = frame,
	}, closeGift, Theme.Colors.Lavender, Theme.Colors.Purple)
end

local giftMode = false

local function renderKeys()
	local page = pages.Keys
	clear(page)
	if player:GetAttribute("PP_KeysLocked") == true then
		local panel =
			UIKit.Panel({ Size = UDim2.new(1, 0, 0, 200), CornerRadius = 16, Parent = page }, colors.Panel, colors.Deep)
		UIKit.Label({
			Text = "🔒 Keys aren't for sale where you are",
			Font = Theme.Fonts.Display,
			TextSize = textSize(26),
			TextWrapped = false,
			Position = UDim2.fromOffset(20, 34),
			Size = UDim2.new(1, -40, 0, 36),
			Parent = panel,
			Children = { UIKit.TextStroke(0.3) },
		})
		UIKit.Label({
			Text = "Keys you win in rounds and PARTY CUPS, with levels and weekly quests, still open crates!",
			TextSize = textSize(19),
			TextColor3 = Theme.Colors.TextDim,
			Position = UDim2.fromOffset(20, 84),
			Size = UDim2.new(1, -40, 0, 70),
			Parent = panel,
		})
		return
	end
	local data = shop()
	local packs = data and data.Packs or {}
	local starter = data and data.Starter
	local p = profile()
	local h = buttonHeight()
	-- One row of cards, the starter pack first while it's theirs to buy, each with its picture: one
	-- key, five on a ring, a heap, the crate brimming (owner: "This should show different quanities of
	-- keys (images). 1 key, 5 keys, pile of keys, chest of keys etc."). Under them VIEW ODDS and GIFT.
	-- Without the starter, how to earn keys goes over the row.
	local bottomRow = h + 8
	local starterShown = type(starter) == "table"
		and not giftMode
		and not (p and p.CrateFlags and p.CrateFlags.StarterPack)
	local top = 0
	if not starterShown then
		top = if touch then 56 else 50
		local how = UIKit.Label({
			Text = KEYS_HOW,
			TextSize = textSize(16),
			TextColor3 = Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, top - 6),
			Parent = page,
		})
		how:SetAttribute("PP_Lines", 2)
	end
	if #packs == 0 then
		UIKit.Label({
			Text = if data then "Key packs are coming soon!" else "Asking Roblox for the prices...",
			TextSize = textSize(20),
			TextColor3 = Theme.Colors.TextDim,
			Position = UDim2.fromOffset(0, top),
			Size = UDim2.new(1, 0, 0, 60),
			Parent = page,
		})
	end
	local row = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.new(1, 0, 1, -(top + bottomRow + 6)),
		Parent = page,
		Children = { UIKit.List(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left) },
	})
	local onePrice = nil
	for _, pack in packs do
		if pack.Keys == 1 then
			onePrice = pack.Price
		end
	end
	local cards = {}
	if starterShown then
		table.insert(cards, { Starter = true, Pack = starter })
	end
	for _, pack in packs do
		table.insert(cards, { Starter = false, Pack = pack })
	end
	for order, entry in cards do
		local pack = entry.Pack
		local isStarter = entry.Starter
		local cardFrame = UIKit.Panel({
			Size = UDim2.new(1 / math.max(1, #cards), -8, 1, 0),
			LayoutOrder = order,
			CornerRadius = 16,
			Parent = row,
		}, if isStarter then colors.Main else colors.Panel, if isStarter then colors.Crimson else colors.Deep)
		local badge = if isStarter then "STARTER" else pack.Badge
		if badge then
			UIKit.Label({
				Text = badge,
				Font = Theme.Fonts.Display,
				TextSize = textSize(15),
				TextColor3 = colors.Deep,
				TextWrapped = false,
				BackgroundTransparency = 0,
				BackgroundColor3 = colors.Gold,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 6),
				Size = UDim2.new(1, -16, 0, 24),
				Parent = cardFrame,
				Children = { UIKit.Round() },
			})
		end
		-- The picture fills what's left between the badge and the words (square, as big as fits, in the
		-- middle of that space).
		local picture = SeasonArt.KeyPacks[if isStarter then "Starter" else pack.Key]
		local below = 26 + 22 + h + 16
		local art = UIKit.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, (32 - below) / 2),
			Size = UDim2.new(1, -12, 1, -(32 + below)),
			Parent = cardFrame,
			Children = { UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1 }) },
		})
		if picture and picture ~= "" then
			UIKit.new("ImageLabel", {
				BackgroundTransparency = 1,
				Image = picture,
				ScaleType = Enum.ScaleType.Fit,
				Size = UDim2.fromScale(1, 1),
				Parent = art,
			})
		else
			UIKit.Label({ Text = "🔑", TextScaled = true, Size = UDim2.fromScale(1, 1), Parent = art })
		end
		UIKit.Label({
			Text = CrateTheme.Count(pack.Keys, "KEY", "KEYS"),
			Font = Theme.Fonts.Display,
			TextSize = textSize(22),
			TextWrapped = false,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -(h + 16 + 22)),
			Size = UDim2.new(1, -8, 0, 26),
			Parent = cardFrame,
			Children = { UIKit.TextStroke(0.3) },
		})
		local save = if not isStarter
				and onePrice
				and pack.Keys > 1
			then math.floor((1 - pack.Price / (pack.Keys * onePrice)) * 100 + 0.5)
			else 0
		local line = if isStarter then "+ a trail · once" elseif save > 0 then `save {save}%` else ""
		if line ~= "" then
			UIKit.Label({
				Text = line,
				TextSize = textSize(16),
				TextColor3 = if isStarter then colors.Gold else colors.Glow,
				TextWrapped = false,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -(h + 14)),
				Size = UDim2.new(1, -8, 0, 22),
				Parent = cardFrame,
			})
		end
		local gifting = giftMode and pack.Gift
		UIKit.Button(
			{
				Text = if gifting then `🎁 R$ {pack.Price}` else `R$ {pack.Price}`,
				TextSize = textSize(20),
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -8),
				Size = UDim2.new(1, -14, 0, h),
				Parent = cardFrame,
			},
			function()
				if gifting then
					openGift(pack)
				else
					remote:FireServer("Buy", pack.Key)
				end
			end,
			if gifting then Theme.Colors.Lavender else Theme.Colors.Green,
			if gifting then Theme.Colors.Purple else Color3.fromRGB(60, 160, 90)
		)
	end
	UIKit.Button({
		Text = "VIEW ODDS FOR EVERY OUTCOME",
		TextSize = textSize(19),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(0.62, -6, 0, h),
		Parent = page,
	}, function()
		CrateMenu.Show("Odds")
	end, colors.Glow, colors.Main)
	UIKit.Button(
		{
			Text = if giftMode then "BUY FOR ME" else "🎁 GIFT KEYS",
			TextSize = textSize(19),
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.fromScale(1, 1),
			Size = UDim2.new(0.38, -6, 0, h),
			Parent = page,
		},
		function()
			giftMode = not giftMode
			renderKeys()
		end,
		if giftMode then Theme.Colors.Green else Theme.Colors.Lavender,
		if giftMode then Color3.fromRGB(60, 160, 90) else Theme.Colors.Purple
	)
end
renderers.Keys = renderKeys

-- The window --------------------------------------------------------------------------------------

local function render()
	for key, button in tabButtons do
		local gradient = button:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Color = if key == current
				then ColorSequence.new(colors.Glow, colors.Main)
				else ColorSequence.new(Theme.Colors.Lavender, Theme.Colors.Purple)
		end
	end
	for key, page in pages do
		page.Visible = key == current
	end
	local renderer = renderers[current]
	if renderer then
		renderer()
	end
	if detailItem then
		showDetail(detailItem)
	elseif giftPack and pages[current] then
		pages[current].Visible = false -- (the gift picker is still up in its place)
	end
end

-- Opens the window on `tab` ("Crates", "Collection", "Top", "Odds", "Keys").
function CrateMenu.Show(tab: string?)
	if tab and pages[tab] then
		if tab ~= current then
			closeDetail()
			closeGift()
		end
		current = tab
	end
	if not modal.IsOpen then
		modal:Open()
	end
	render()
end

-- Opens the key shop's gift picker for a pack (the UI checks show it this way).
function CrateMenu.ShowGift(packKey: string)
	CrateMenu.Show("Keys")
	local data = shop()
	for _, pack in (if data and type(data.Packs) == "table" then data.Packs else {}) do
		if pack.Key == packKey then
			openGift(pack)
		end
	end
end

-- Opens the collection on one item's details (the UI checks show it this way).
function CrateMenu.ShowItem(itemId: string)
	local itemSeason = Seasons.SeasonOf(itemId)
	seasonShown = if itemSeason then itemSeason.Id else season.Id
	CrateMenu.Show("Collection")
	showDetail(itemId)
end

function CrateMenu.IsOpen(): boolean
	return modal ~= nil and modal.IsOpen
end

function CrateMenu.Close()
	if modal then
		modal:Close()
	end
end

function CrateMenu.Build(context)
	touch = UIKit.IsTouch()
	modal = Modal.new(context.Overlay, season.Name, "🎃", Vector2.new(980, 600))
	CrateTheme.Dress(modal.Window, season)
	-- The hub's tabs in the title bar (UI/HubTabs): this one wears the season's name.
	HubTabs.Attach(modal, "Season")
	local content = modal.Content
	local tabGap = if touch then 6 else 10
	local tabs = UIKit.new(if touch then "ScrollingFrame" else "Frame", {
		Size = UDim2.new(0, 170, 1, 0),
		BackgroundTransparency = 1,
		Parent = content,
		Children = { UIKit.List(Enum.FillDirection.Vertical, tabGap) },
	})
	if touch then
		tabs.BorderSizePixel = 0
		tabs.ScrollBarThickness = 4
		tabs.AutomaticCanvasSize = Enum.AutomaticSize.Y
		tabs.CanvasSize = UDim2.new()
	end
	for order, tab in TABS do
		tabButtons[tab.Key] = UIKit.Button({
			Text = `{tab.Icon} {tab.Label}`,
			TextSize = textSize(20),
			Size = UDim2.new(1, if touch then -6 else 0, 0, if touch then 66 else 54),
			LayoutOrder = order,
			Parent = tabs,
		}, function()
			CrateMenu.Show(tab.Key)
		end, Theme.Colors.Lavender, Theme.Colors.Purple)
		local page = UIKit.new("Frame", {
			Name = tab.Key,
			Position = UDim2.fromOffset(186, 0),
			Size = UDim2.new(1, -186, 1, 0),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = content,
		})
		pages[tab.Key] = page
	end
	-- An item's details (in the collection's place) and the gift picker (over the key shop).
	detail = UIKit.Panel({
		Name = "Detail",
		Position = UDim2.fromOffset(186, 0),
		Size = UDim2.new(1, -186, 1, 0),
		CornerRadius = 20,
		Visible = false,
		Parent = content,
	}, colors.Panel, colors.Deep)
	giftPicker = UIKit.Panel({
		Name = "Gift",
		Position = UDim2.fromOffset(186, 0),
		Size = UDim2.new(1, -186, 1, 0),
		CornerRadius = 20,
		Visible = false,
		ZIndex = 40,
		Parent = content,
	}, colors.Panel, colors.Deep)

	modal.Closed:Connect(function()
		closeDetail()
		closeGift()
	end)
	State.ProfileChanged:Connect(function()
		if modal.IsOpen and current ~= "Keys" and not giftPack then
			render()
		end
	end)
	for _, key in { "CrateBoard", "KeyShop" } do
		GameState.Changed(key, function()
			if
				modal.IsOpen
				and ((key == "CrateBoard" and current == "Top") or (key == "KeyShop" and current == "Keys"))
			then
				render()
			end
		end)
	end
	player:GetAttributeChangedSignal("PP_KeysLocked"):Connect(function()
		if modal.IsOpen and current == "Keys" then
			render()
		end
	end)
	-- OPEN wakes up when they're out of a round (and back in the lobby).
	for _, attribute in { "PP_InRound", "PP_Alive" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if modal.IsOpen and current == "Crates" then
				render()
			end
		end)
	end
	-- The crate in its window turns.
	RunService.RenderStepped:Connect(function()
		local model = viewportModel
		if modal.IsOpen and current == "Crates" and model and model.Parent then
			model:PivotTo(CFrame.Angles(0, os.clock() * 0.6, 0))
		end
	end)
end

return CrateMenu
