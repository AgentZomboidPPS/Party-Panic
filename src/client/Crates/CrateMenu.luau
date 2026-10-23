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
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)
local Seasons = require(Shared.Seasons)

local State = require(script.Parent.Parent.State)
local Modal = require(script.Parent.Parent.UI.Modal)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local CrateTheme = require(script.Parent.CrateTheme)

local CrateMenu = {}

local player = Players.LocalPlayer
local remote = Remotes.Get("Crate")
local season = Seasons.CurrentSeason()
local colors = CrateTheme.Colors(season)

local TABS = {
	{ Key = "Crates", Label = "Crates", Icon = "📦" },
	{ Key = "Collection", Label = "Collection", Icon = "📖" },
	{ Key = "Top", Label = "Top Unboxers", Icon = "🏆" },
	{ Key = "Odds", Label = "Odds", Icon = "🎲" },
	{ Key = "Keys", Label = "Get Keys", Icon = "🔑" },
}
local MEDALS = { "🥇", "🥈", "🥉" }
local KEYS_HOW =
	"🔑 Keys: 3 · 2 · 1 on the PARTY CUP podium, +1 for playing all 5 rounds, +1 for your first cup each day, every 5th level and weekly quests."
local TITLE_FONT = Enum.Font.GrenzeGotisch

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

-- An ember-gradient headline in the season's blackletter.
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
		BackgroundColor3 = Color3.fromRGB(20, 10, 26),
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
	-- Phones: the window's content is about 380 tall, so the column packs tighter and the how-to-get-
	-- keys line moves to the key shop.
	local L = if touch
		then { Season = 44, Pills = 72, Pill = 48, Meter = 126, Open = 212, Gap = 8 }
		else { Season = 48, Pills = 82, Pill = 52, Meter = 146, Open = 236, Gap = 10 }
	UIKit.Label({
		Text = "Crates and keys never expire",
		TextSize = textSize(16),
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(0, if touch then 250 else 292),
		Size = UDim2.fromOffset(280, 24),
		Parent = page,
	})
	local x = 300
	local width = 450 -- (the page is 754 wide: the crate's 280, a gap, then this column)
	local column = UIKit.new("Frame", {
		Position = UDim2.fromOffset(x, 0),
		Size = UDim2.new(1, -x, 1, 0),
		BackgroundTransparency = 1,
		Parent = page,
	})
	headline({ Text = season.Name, Size = UDim2.fromOffset(width, if touch then 42 else 50), Parent = column })
	UIKit.Label({
		Text = `SEASON {season.Number} · open crates at the pile`,
		Font = Theme.Fonts.Display,
		TextSize = textSize(18),
		TextColor3 = colors.Glow,
		Position = UDim2.fromOffset(0, L.Season),
		Size = UDim2.fromOffset(width, 24),
		Parent = column,
	})
	local half = (width - 10) / 2
	pill(column, `📦 {CrateTheme.Count(crates(), "CRATE", "CRATES")}`, {
		Position = UDim2.fromOffset(0, L.Pills),
		Size = UDim2.fromOffset(half, L.Pill),
	})
	pill(column, `🔑 {CrateTheme.Count(keys(), "KEY", "KEYS")}`, {
		Position = UDim2.fromOffset(half + 10, L.Pills),
		Size = UDim2.fromOffset(half, L.Pill),
	})
	meterBar(column, L.Meter, width)

	local h = buttonHeight()
	local canOpen = crates() >= 1 and keys() >= 1
	local inRound = State.InRound()
	local y = L.Open
	local openText = if inRound
		then "OPENS IN THE LOBBY"
		elseif crates() < 1 then "PLAY A ROUND FOR A CRATE"
		elseif keys() < 1 then "NO KEYS YET"
		else "OPEN AT AN ALTAR"
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
			elseif keys() < 1 then
				CrateMenu.Show("Keys")
			end
		end,
		if canOpen and not inRound then colors.Glow else Theme.Colors.PanelLight,
		if canOpen and not inRound then colors.Main else Theme.Colors.PanelDark
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
		if canOpen and not inRound then Theme.Colors.Lavender else Theme.Colors.PanelLight,
		if canOpen and not inRound then Theme.Colors.Purple else Theme.Colors.PanelDark
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
			elseif not many then
				CrateMenu.Show("Keys")
			end
		end,
		if many and not inRound then colors.Gold else Theme.Colors.PanelLight,
		if many and not inRound then colors.Main else Theme.Colors.PanelDark
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

local function closeDetail()
	detailItem = nil
	if detail then
		detail.Visible = false
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
	UIKit.PopIn(frame, 0.25)
	local item = Seasons.ItemById[itemId]
	local tier = CrateTheme.TierOf(itemId)
	local tierColor = CrateTheme.TierColor(tier, season)
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = tierColor
		stroke.Transparency = 0.1
	end
	local art = UIKit.new("Frame", {
		Position = UDim2.fromOffset(20, 20),
		Size = UDim2.fromOffset(150, 150),
		BackgroundColor3 = colors.Deep,
		ZIndex = 41,
		Parent = frame,
		Children = { UIKit.Corner(18), UIKit.Stroke(tierColor, 2, 0.3) },
	})
	CrateTheme.Picture(itemId, art, { Size = UDim2.fromScale(0.8, 0.8), ZIndex = 42 })
	local kind = if tier == "Effect" then CrateTheme.KindOf(itemId) else CrateTheme.Tiers[tier].Word
	UIKit.Label({
		Text = kind,
		Font = Theme.Fonts.Display,
		TextSize = textSize(18),
		TextColor3 = tierColor,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(186, 22),
		Size = UDim2.new(1, -206, 0, 24),
		ZIndex = 41,
		Parent = frame,
	})
	UIKit.Label({
		Text = if item then item.Name else itemId,
		Font = if tier == "Title" then TITLE_FONT else Theme.Fonts.Display,
		TextSize = 34,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(186, 46),
		Size = UDim2.new(1, -206, 0, 44),
		ZIndex = 41,
		Parent = frame,
		Children = { UIKit.TextStroke(0.3), UIKit.new("UITextSizeConstraint", { MaxTextSize = 34 }) },
	})
	UIKit.Label({
		Text = if item then item.Description else "",
		TextSize = textSize(18),
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(186, 94),
		Size = UDim2.new(1, -206, 0, 50),
		ZIndex = 41,
		Parent = frame,
	})
	UIKit.Label({
		Text = `📦 {foundLine(seasonShown, itemId)}`,
		Font = Theme.Fonts.Display,
		TextSize = textSize(18),
		TextColor3 = colors.Glow,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(186, 146),
		Size = UDim2.new(1, -206, 0, 26),
		ZIndex = 41,
		Parent = frame,
	})
	local p = profile()
	local slot = item and item.Slot or ""
	local wearing = p and p.Equipped and p.Equipped[slot] == itemId
	local h = buttonHeight()
	UIKit.Button(
		{
			Text = if wearing then "TAKE OFF" else "EQUIP",
			TextSize = textSize(22),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 20, 1, -18),
			Size = UDim2.fromOffset(200, h),
			ZIndex = 42,
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
		Size = UDim2.fromOffset(160, h),
		ZIndex = 42,
		Parent = frame,
	}, closeDetail, Theme.Colors.Lavender, Theme.Colors.Purple)
end

local function card(parent: Instance, itemId: string, order: number, have: boolean, vaulted: boolean): TextButton
	local tier = CrateTheme.TierOf(itemId)
	local tierColor = CrateTheme.TierColor(tier, Seasons.SeasonOf(itemId))
	local button = UIKit.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = if have then colors.Panel else Color3.fromRGB(24, 14, 30),
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
		if have then
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
				Text = `SEASON {info.Number} · {info.Name}`,
				Font = Theme.Fonts.Display,
				TextSize = textSize(20),
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
				if id == seasonShown then colors.Glow else Theme.Colors.PanelLight,
				if id == seasonShown then colors.Main else Theme.Colors.PanelDark
			)
		end
	end
	UIKit.Label({
		Text = `{found} of {total} · {UIKit.FormatNumber(progress.Opened or 0)} crates opened · {UIKit.FormatNumber(
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
		BackgroundColor3 = if titleHave then colors.Panel else Color3.fromRGB(24, 14, 30),
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
			if kind.Key == boardKind then colors.Glow else Theme.Colors.PanelLight,
			if kind.Key == boardKind then colors.Main else Theme.Colors.PanelDark
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
			UIKit.List(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left),
			UIKit.new("UIPadding", { PaddingRight = UDim.new(0, 14), PaddingBottom = UDim.new(0, 10) }),
		},
	})
	local order = 0
	local function line(left: string, right: string, color: Color3, bold: boolean)
		order += 1
		local row = UIKit.new("Frame", {
			BackgroundTransparency = if bold then 0.35 else 1,
			BackgroundColor3 = colors.Deep,
			Size = UDim2.new(1, 0, 0, if touch then 34 else 30),
			LayoutOrder = order,
			Parent = list,
			Children = { UIKit.Corner(8) },
		})
		UIKit.Label({
			Text = left,
			Font = if bold then Theme.Fonts.Display else Theme.Fonts.Bold,
			TextSize = textSize(if bold then 19 else 17),
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(if bold then 10 else 30, 0),
			Size = UDim2.new(1, -(if bold then 10 else 30) - 140, 1, 0),
			Parent = row,
		})
		UIKit.Label({
			Text = right,
			Font = Theme.Fonts.Display,
			TextSize = textSize(if bold then 19 else 17),
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 0),
			Size = UDim2.fromOffset(120, if touch then 34 else 30),
			Parent = row,
		})
	end
	order += 1
	UIKit.Label({
		Text = "Your odds for your next crate. No duplicates: you never get an item twice, so your odds change as you collect, and a tier you've finished pays coins instead.",
		TextSize = textSize(17),
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 48),
		LayoutOrder = order,
		Parent = list,
	})
	local groups = { "Title", "Pet", "Hat", "Effect", "Coins" }
	local total = 0
	for _, tier in groups do
		local tierRows = {}
		local tierTotal = 0
		for _, row in rows do
			if row.Tier == tier then
				table.insert(tierRows, row)
				tierTotal += row.Chance
			end
		end
		if #tierRows == 0 then
			continue
		end
		total += tierTotal
		local info = CrateTheme.Tiers[tier]
		local color = CrateTheme.TierColor(tier, season)
		local missing = if tier ~= "Coins" then #CrateLogic.Missing(season, tier :: any, have) else 0
		local heading = if tier == "Title"
			then `{info.Icon} {CrateTheme.NameOf(season.Title)} (the title)`
			elseif tier == "Coins" then `{info.Icon} Coins (5 to 150)`
			elseif missing == 0 then `{info.Icon} {string.lower(info.Word)}s: all found, coins instead`
			else `{info.Icon} A {string.lower(info.Word)} you don't own ({missing} left)`
		line(heading, CrateLogic.Percent(tierTotal), color, true)
		for _, row in tierRows do
			local label = if string.find(row.Key, "Jackpot", 1, true) or row.Tier == "Coins"
				then row.Label
				else CrateTheme.NameOf(row.Key)
			line(label, CrateLogic.Percent(row.Chance), Theme.Colors.Text, false)
		end
	end
	line("Total", CrateLogic.Percent(total), colors.Gold, true)
	local missingPets = #CrateLogic.Missing(season, "Pet", have)
	order += 1
	UIKit.Label({
		Text = if missingPets == 0
			then `🏮 {season.Meter}: every pet found.`
			elseif
				CrateLogic.Guaranteed(season, have, meter)
			then `🏮 {season.Meter}: your next crate is a guaranteed pet (shown above).`
			else `🏮 {season.Meter}: {CrateLogic.Meter - meter} more crates without a pet or the title, then the next is a guaranteed pet you don't own. A friend standing near you when you open adds a point.`,
		TextSize = textSize(17),
		TextColor3 = colors.Glow,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 52),
		LayoutOrder = order,
		Parent = list,
	})
end
renderers.Odds = renderOdds

-- Get Keys ----------------------------------------------------------------------------------------

local giftPicker: Frame? = nil

local function shop(): { [string]: any }?
	local data = GameState.GetJSON("KeyShop")
	return if type(data) == "table" then data else nil
end

local function closeGift()
	giftPack = nil
	if giftPicker then
		giftPicker.Visible = false
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
	UIKit.PopIn(frame, 0.25)
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
			Text = "🔒 Keys aren't for sale where you are. Keys you win in PARTY CUPS, with levels and weekly quests still open crates!",
			Font = Theme.Fonts.Display,
			TextSize = textSize(22),
			Position = UDim2.fromOffset(20, 20),
			Size = UDim2.new(1, -40, 1, -40),
			Parent = panel,
		})
		return
	end
	local data = shop()
	local packs = data and data.Packs or {}
	local starter = data and data.Starter
	local p = profile()
	local h = buttonHeight()
	-- Phones: the content is about 380 tall: the starter pack (or how to get keys), the packs, then
	-- VIEW ODDS and GIFT.
	local top = if touch then 92 else 96
	local bottomRow = h + 8
	local starterShown = type(starter) == "table" and not (p and p.CrateFlags and p.CrateFlags.StarterPack)
	if starterShown then
		local banner = UIKit.Panel({
			Size = UDim2.new(1, 0, 0, top),
			CornerRadius = 16,
			Parent = page,
		}, colors.Main, colors.Crimson)
		UIKit.Label({
			Text = `🏮 {season.Name} STARTER`,
			Font = Theme.Fonts.Display,
			TextSize = textSize(22),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = false,
			Position = UDim2.fromOffset(16, 8),
			Size = UDim2.new(1, -220, 0, 30),
			Parent = banner,
			Children = { UIKit.TextStroke(0.2) },
		})
		UIKit.Label({
			Text = `{CrateTheme.Count(starter.Keys, "key")} + the {CrateTheme.NameOf(starter.Item or season.Starter)} trail, sold only here. Once per player.`,
			TextSize = textSize(17),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(16, 40),
			Size = UDim2.new(1, -220, 0, top - 44),
			Parent = banner,
		})
		UIKit.Button({
			Text = `R$ {starter.Price}`,
			TextSize = textSize(24),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(180, math.min(h, top - 12)),
			Parent = banner,
		}, function()
			remote:FireServer("Buy", starter.Key)
		end, Theme.Colors.Green, Color3.fromRGB(60, 160, 90))
	else
		UIKit.Label({
			Text = KEYS_HOW,
			TextSize = textSize(17),
			TextColor3 = Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, top),
			Parent = page,
		})
	end
	local y = top + 10
	if #packs == 0 then
		UIKit.Label({
			Text = if data then "Key packs are coming soon!" else "Asking Roblox for the prices...",
			TextSize = textSize(20),
			TextColor3 = Theme.Colors.TextDim,
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, 0, 0, 60),
			Parent = page,
		})
	end
	local row = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 1, -(y + bottomRow + 6)),
		Parent = page,
		Children = { UIKit.List(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left) },
	})
	local onePrice = nil
	for _, pack in packs do
		if pack.Keys == 1 then
			onePrice = pack.Price
		end
	end
	for order, pack in packs do
		local cardFrame = UIKit.Panel({
			Size = UDim2.new(1 / math.max(1, #packs), -8, 1, 0),
			LayoutOrder = order,
			CornerRadius = 16,
			Parent = row,
		}, colors.Panel, colors.Deep)
		if pack.Badge then
			UIKit.Label({
				Text = pack.Badge,
				Font = Theme.Fonts.Display,
				TextSize = textSize(15),
				TextColor3 = colors.Deep,
				BackgroundTransparency = 0,
				BackgroundColor3 = colors.Gold,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 6),
				Size = UDim2.new(1, -20, 0, 24),
				Parent = cardFrame,
				Children = { UIKit.Round() },
			})
		end
		-- (Short enough for the smallest phone: the badge, the keys, the saving, then BUY.)
		UIKit.Label({
			Text = `🔑 {CrateTheme.Count(pack.Keys, "KEY", "KEYS")}`,
			Font = Theme.Fonts.Display,
			TextSize = textSize(24),
			Position = UDim2.fromOffset(0, 32),
			Size = UDim2.new(1, 0, 0, 30),
			Parent = cardFrame,
			Children = { UIKit.TextStroke(0.3) },
		})
		local save = if onePrice and pack.Keys > 1
			then math.floor((1 - pack.Price / (pack.Keys * onePrice)) * 100 + 0.5)
			else 0
		if save > 0 then
			UIKit.Label({
				Text = `save {save}%`,
				TextSize = textSize(16),
				TextColor3 = colors.Glow,
				Position = UDim2.fromOffset(0, 62),
				Size = UDim2.new(1, 0, 0, 22),
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
				else ColorSequence.new(colors.Panel, colors.Deep)
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
		end, colors.Panel, colors.Deep)
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
	-- The overlays: an item's details (the collection) and the gift picker (the key shop).
	detail = UIKit.Panel({
		Name = "Detail",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 93, 0.5, 0),
		Size = UDim2.fromOffset(600, if touch then 300 else 270),
		CornerRadius = 20,
		Visible = false,
		ZIndex = 40,
		Parent = content,
	}, colors.Panel, colors.Deep)
	giftPicker = UIKit.Panel({
		Name = "Gift",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 93, 0.5, 0),
		Size = UDim2.fromOffset(460, 440),
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
	-- The crate in its window turns.
	RunService.RenderStepped:Connect(function()
		local model = viewportModel
		if modal.IsOpen and current == "Crates" and model and model.Parent then
			model:PivotTo(CFrame.Angles(0, os.clock() * 0.6, 0))
		end
	end)
end

return CrateMenu
