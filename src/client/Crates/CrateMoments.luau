-- The crate season's moments on screen (the design pages; owner: "This has to be sick. This will be
-- players first season. I want it to look insane."):
--   * BANNERS: a pet or the title out of someone's crate puts a banner across the top of every
--     screen in the server ("LeafPileLeo unboxed HARVEST OWL!", in the tier's colour, FIRST IN THE
--     WORLD when they're the first anyone found), and the title one on every other server too ("on
--     another server"). The title's is bigger and burns like a candle.
--   * THE PRIZE CARD: the opener's own card when the reel ends: what came out (NEW PET! and that
--     it's on now, a hat, an effect, the coins, a jackpot), or the five of an Open 5.
--   * GIFTS: keys or crates someone was just given, and why ("3 FREE KEYS to start", "+3 KEYS ·
--     PARTY CUP 1ST", "🎁 Bo sent you 5 keys!", the starter pack's trail).
--   * THE WELCOME: the season's first moment for each player ("Season trailer moment: On the first
--     day, the lobby trees turn from green to orange over a few seconds when the season starts"):
--     letterbox bars, the trees turning (SeasonWorldController), HOLLOW NIGHT in its blackletter,
--     then their first crate and keys with OPEN IT! (walks them to the pile once).
-- They keep out of the way of the screens that mustn't be cut short (the results card, the cup's
-- podium: PP_ResultsShowing, PP_CupPodium) and never show during a round the player is in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Seasons = require(Shared.Seasons)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local CrateTheme = require(script.Parent.CrateTheme)

local CrateMoments = {}

local player = Players.LocalPlayer
local season = Seasons.CurrentSeason()
local colors = CrateTheme.Colors(season)
local TITLE_FONT = Enum.Font.GrenzeGotisch

local BANNER_Y = 200

local touch = false
local gui: ScreenGui
local bannerHolder: Frame
local cardHolder: Frame
local queue: { () -> number } = {} -- cards waiting for the screen (each returns how long it shows)
local cardBusy = false

local function screenTaken(): boolean
	return player:GetAttribute("PP_ResultsShowing") == true
		or player:GetAttribute("PP_CupPodium") == true
		or State.PlayingRound()
end

-- Banners ---------------------------------------------------------------------------------------

-- A banner across the top: `banner` is the server's (Name, Item, Tier, First, Elsewhere). Returns how
-- long it stays (shorter while others wait: `hurry`).
local function showBanner(banner: { [string]: any }, hurry: boolean): number
	local item = banner.Item
	if type(item) ~= "string" then
		return 0
	end
	local tier = CrateTheme.TierOf(item)
	local color = CrateTheme.TierColor(tier, Seasons.SeasonOf(item))
	local title = tier == "Title"
	local mine = banner.UserId == player.UserId
	local width = if title then 760 else 640
	local frame = UIKit.Panel({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, BANNER_Y), -- (under the top bar, the first-join tips and the chips)
		Size = UDim2.fromOffset(width, if title then 124 else 92),
		CornerRadius = 22,
		Parent = bannerHolder,
	}, color:Lerp(colors.Deep, 0.35), colors.Deep)
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Thickness = 3
		stroke.Transparency = 0
	end
	local art = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.fromOffset(if title then 104 else 72, if title then 104 else 72),
		Parent = frame,
	})
	CrateTheme.Picture(item, art)
	local who = if mine then "YOU" else tostring(banner.Name or "Someone")
	local where = if banner.Elsewhere then " on another server" else ""
	UIKit.Label({
		Text = `{who} unboxed{where}`,
		Font = Theme.Fonts.Display,
		TextSize = if touch then 20 else 22,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(if title then 128 else 96, 8),
		Size = UDim2.new(1, if title then -140 else -108, 0, 28),
		Parent = frame,
		Children = { UIKit.TextStroke(0.4) },
	})
	local name = UIKit.Label({
		Text = string.upper(CrateTheme.NameOf(item)) .. "!",
		Font = if title then TITLE_FONT else Theme.Fonts.Display,
		TextSize = if title then 58 else 36,
		TextScaled = true,
		TextWrapped = false,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(if title then 128 else 96, 34),
		Size = UDim2.new(1, if title then -140 else -108, 0, if title then 62 else 42),
		Parent = frame,
		Children = {
			UIKit.new("UIGradient", {
				Color = if title
					then ColorSequence.new({
						ColorSequenceKeypoint.new(0, colors.Gold),
						ColorSequenceKeypoint.new(0.6, colors.Glow),
						ColorSequenceKeypoint.new(1, colors.Main),
					})
					else ColorSequence.new(Color3.new(1, 1, 1), color:Lerp(Color3.new(1, 1, 1), 0.3)),
				Rotation = 90,
			}),
			UIKit.new("UIStroke", { Color = color:Lerp(Color3.new(0, 0, 0), 0.55), Thickness = 2.5 }),
			UIKit.new("UITextSizeConstraint", { MaxTextSize = if title then 58 else 36 }),
		},
	})
	if banner.First then
		UIKit.Label({
			Text = "🌍 FIRST IN THE WORLD!",
			Font = Theme.Fonts.Display,
			TextSize = 20,
			TextColor3 = colors.Deep,
			BackgroundTransparency = 0,
			BackgroundColor3 = colors.Gold,
			AnchorPoint = Vector2.new(1, 1), -- (sitting on the banner's top edge, clear of the name)
			Position = UDim2.new(1, -14, 0, 8),
			Size = UDim2.fromOffset(250, 30),
			Parent = frame,
			Children = { UIKit.Round() },
		})
	end
	UIKit.PopIn(frame, 0.4)
	local born = os.clock()
	local life = if title then (if hurry then 5 else 7) else (if hurry then 3.2 else 5)
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - born
		if title then
			-- It burns like a candle: a flicker now and then.
			local flicker = 1 - (if math.sin(t * 23) > 0.92 then 0.25 else 0) * math.abs(math.sin(t * 7))
			name.TextTransparency = 1 - flicker
		end
		if t > life - 0.4 then
			frame.BackgroundTransparency = math.clamp((t - (life - 0.4)) / 0.4, 0, 1)
		end
		if t > life then
			connection:Disconnect()
			frame:Destroy()
		end
	end)
	return life
end

-- Banners take turns (a burst of them, an Open 5 with two pets in it, never piles up on screen); a
-- few wait at most, the title always.
local waiting: { { [string]: any } } = {}
local bannerUp = false

local function nextBanner()
	if bannerUp or #waiting == 0 then
		return
	end
	local banner = table.remove(waiting, 1) :: { [string]: any }
	bannerUp = true
	local life = showBanner(banner, #waiting > 0)
	task.delay(life + 0.15, function()
		bannerUp = false
		nextBanner()
	end)
end

function CrateMoments.Banner(banner: { [string]: any })
	if #waiting >= 4 then
		for index, queued in waiting do
			if queued.Tier ~= "Title" then
				table.remove(waiting, index)
				break
			end
		end
	end
	table.insert(waiting, banner)
	nextBanner()
end

-- Cards (one at a time) ---------------------------------------------------------------------------

local function pump()
	if cardBusy or #queue == 0 or screenTaken() then
		return
	end
	cardBusy = true
	local show = table.remove(queue, 1) :: () -> number
	local life = show()
	task.delay(life, function()
		cardBusy = false
		pump()
	end)
end

local function cardFrame(height: number, color: Color3): Frame
	local frame = UIKit.Panel({
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.7),
		Size = UDim2.fromOffset(560, height),
		CornerRadius = 22,
		Parent = cardHolder,
	}, color:Lerp(colors.Deep, 0.45), colors.Deep)
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Thickness = 3
		stroke.Transparency = 0
	end
	UIKit.PopIn(frame, 0.35)
	return frame
end

local function fadeAway(frame: Frame, after: number)
	task.delay(after, function()
		if frame.Parent then
			UIKit.Tween(frame, 0.3, { Position = UDim2.fromScale(0.5, 0.78), BackgroundTransparency = 1 })
			task.delay(0.3, function()
				frame:Destroy()
			end)
		end
	end)
end

local function headline(text: string, color: Color3, parent: Instance, y: number, size: number)
	UIKit.Label({
		Text = text,
		Font = Theme.Fonts.Display,
		TextSize = size,
		TextColor3 = color,
		TextWrapped = false,
		TextScaled = true,
		Position = UDim2.fromOffset(150, y),
		Size = UDim2.new(1, -170, 0, size + 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
		Children = { UIKit.TextStroke(0.3), UIKit.new("UITextSizeConstraint", { MaxTextSize = size }) },
	})
end

-- The opener's prize card (`show` is the server's: Results, and the meter after it).
function CrateMoments.Prize(show: { [string]: any })
	local results = show.Results
	if type(results) ~= "table" or #results == 0 then
		return
	end
	table.insert(queue, function(): number
		if #results > 1 then
			local frame = cardFrame(200, colors.Main)
			UIKit.Label({
				Text = `YOU OPENED {#results} CRATES!`,
				Font = Theme.Fonts.Display,
				TextSize = 26,
				Position = UDim2.fromOffset(0, 10),
				Size = UDim2.new(1, 0, 0, 32),
				Parent = frame,
				Children = { UIKit.TextStroke(0.3) },
			})
			local row = UIKit.new("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(14, 50),
				Size = UDim2.new(1, -28, 0, 136),
				Parent = frame,
				Children = { UIKit.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center) },
			})
			for index, result in results do
				local tierColor = CrateTheme.TierColor(result.Tier, season)
				local cell = UIKit.new("Frame", {
					BackgroundColor3 = colors.Deep,
					Size = UDim2.fromOffset(96, 132),
					LayoutOrder = index,
					Parent = row,
					Children = { UIKit.Corner(14), UIKit.new("UIStroke", { Color = tierColor, Thickness = 2.5 }) },
				})
				local art = UIKit.new("Frame", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(10, 8),
					Size = UDim2.fromOffset(76, 76),
					Parent = cell,
				})
				if result.Item then
					CrateTheme.Picture(result.Item, art)
				else
					UIKit.Label({ Text = Theme.CoinIcon, TextScaled = true, Size = UDim2.fromScale(1, 1), Parent = art })
				end
				UIKit.Label({
					Text = if result.Item then CrateTheme.NameOf(result.Item) else `+{result.Coins}`,
					Font = Theme.Fonts.Display,
					TextSize = 16,
					TextScaled = true,
					TextColor3 = tierColor,
					Position = UDim2.fromOffset(4, 88),
					Size = UDim2.new(1, -8, 0, 38),
					Parent = cell,
					Children = { UIKit.new("UITextSizeConstraint", { MaxTextSize = 18 }) },
				})
			end
			fadeAway(frame, 4.5)
			return 4.9
		end
		local result = results[1]
		local tier = result.Tier
		local color = CrateTheme.TierColor(tier, season)
		local frame = cardFrame(150, color)
		local art = UIKit.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 15),
			Size = UDim2.fromOffset(120, 120),
			Parent = frame,
		})
		if result.Item then
			CrateTheme.Picture(result.Item, art)
		else
			UIKit.Label({ Text = Theme.CoinIcon, TextScaled = true, Size = UDim2.fromScale(1, 1), Parent = art })
		end
		local item = result.Item and Seasons.ItemById[result.Item]
		local kind = if tier == "Effect" and result.Item
			then CrateTheme.KindOf(result.Item)
			else CrateTheme.Tiers[tier].Word
		if result.Item then
			headline(`NEW {kind}!`, color, frame, 14, 24)
			headline(string.upper(CrateTheme.NameOf(result.Item)), Color3.new(1, 1, 1), frame, 42, 38)
			local on = item
				and (item.Slot == "Pet" or item.Slot == "Hat" or item.Slot == "Aura" or item.Slot == "Title")
			UIKit.Label({
				Text = if on
					then "It's on you now! Change it in the collection."
					else "Equip it in the collection or the shop.",
				TextSize = if touch then 18 else 18,
				TextColor3 = Theme.Colors.TextDim,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(150, 90),
				Size = UDim2.new(1, -170, 0, 44),
				Parent = frame,
			})
		else
			headline(if result.Jackpot then "JACKPOT!" else "COINS!", color, frame, 18, 26)
			headline(`+{result.Coins} COINS`, Theme.Colors.Coin, frame, 50, 42)
			UIKit.Label({
				Text = if result.Jackpot
					then `You have every {string.lower(CrateTheme.Tiers[tier].Word)}, so it paid coins!`
					else `Lantern Meter {show.Meter}/150`,
				TextSize = 18,
				TextColor3 = Theme.Colors.TextDim,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(150, 100),
				Size = UDim2.new(1, -170, 0, 30),
				Parent = frame,
			})
		end
		if result.Guaranteed then
			UIKit.Label({
				Text = "🏮 THE LANTERN METER PAID OUT!",
				Font = Theme.Fonts.Display,
				TextSize = 18,
				TextColor3 = colors.Deep,
				BackgroundTransparency = 0,
				BackgroundColor3 = colors.Gold,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, 0),
				Size = UDim2.fromOffset(340, 30),
				Parent = frame,
				Children = { UIKit.Round() },
			})
		end
		local life = if tier == "Coins" and not result.Jackpot then 2.6 else 4.2
		fadeAway(frame, life)
		return life + 0.4
	end)
	pump()
end

-- "Place 2" (the server's detail for a cup's keys) as "2ND PLACE"; "Played": "YOU PLAYED IT".
local function cupPlace(detail: any): string
	local place = tonumber(string.match(tostring(detail or ""), "Place (%d+)"))
	if place then
		local suffix = if place == 1 then "ST" elseif place == 2 then "ND" elseif place == 3 then "RD" else "TH"
		return `{place}{suffix} PLACE`
	end
	return "YOU PLAYED IT"
end

-- Keys or crates given (the server's "Gift": Keys?, Crates?, Reason, Detail?, From?, Item?).
function CrateMoments.Gift(gift: { [string]: any })
	local keys = tonumber(gift.Keys) or 0
	local crates = tonumber(gift.Crates) or 0
	if keys <= 0 and crates <= 0 then
		return
	end
	local reason = tostring(gift.Reason or "")
	if reason == "Welcome" then
		return -- (the welcome shows its own)
	end
	table.insert(queue, function(): number
		local frame = cardFrame(124, colors.Glow)
		local art = UIKit.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(20, 12),
			Size = UDim2.fromOffset(100, 100),
			Parent = frame,
		})
		UIKit.Label({
			Text = if keys > 0 then "🔑" else "📦",
			TextScaled = true,
			Size = UDim2.fromScale(1, 1),
			Parent = art,
		})
		local what = if keys > 0 then CrateTheme.Count(keys, "KEY") else CrateTheme.Count(crates, "CRATE")
		local top = if gift.From
			then `🎁 {gift.From} sent you`
			elseif reason == "PartyCup" then `PARTY CUP · {cupPlace(gift.Detail)}`
			elseif reason == "Road" then `REWARDS ROAD · {string.upper(tostring(gift.Detail or ""))}`
			elseif reason == "Quest" then "WEEKLY QUEST"
			elseif reason == "Starter pack" then `{season.Name} STARTER PACK`
			elseif reason == "Bought" then "THANK YOU!"
			else "FOR YOU"
		headline(top, colors.Glow, frame, 16, 22)
		headline(`+{what}`, Color3.new(1, 1, 1), frame, 42, 40)
		UIKit.Label({
			Text = if gift.Item
				then `and the {CrateTheme.NameOf(gift.Item)} trail!`
				else "Open crates at the pile in the middle of the lobby.",
			TextSize = 18,
			TextColor3 = Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(150, 88),
			Size = UDim2.new(1, -170, 0, 26),
			Parent = frame,
		})
		fadeAway(frame, 3.6)
		return 4
	end)
	pump()
end

-- The welcome -------------------------------------------------------------------------------------

local welcomeShowing = false

-- The season's welcome: `turnTrees(seconds)` turns the lobby's trees (SeasonWorldController),
-- `onSeen()` tells the server (its crate), `onOpen()` walks them to an altar.
function CrateMoments.Welcome(turnTrees: (number) -> (), onSeen: () -> (), onOpen: () -> ())
	if welcomeShowing then
		return
	end
	welcomeShowing = true
	-- The lobby's chips and the first-join tip step aside meanwhile (UI/LobbyRibbon).
	player:SetAttribute("PP_Celebrating", true)
	local holder = UIKit.new("Frame", {
		Name = "Welcome",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	-- The lobby dims behind it (the HUD too, as for a full-screen moment), between letterbox bars.
	-- Both reach past the safe area to the screen's edges (a phone's notch side too), as a modal's
	-- backdrop does (UI/Modal).
	local dim = UIKit.new("Frame", {
		Position = UDim2.fromOffset(-300, -300),
		Size = UDim2.new(1, 600, 1, 600),
		BackgroundColor3 = Color3.fromRGB(10, 4, 16),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = holder,
	})
	UIKit.Tween(dim, 0.8, { BackgroundTransparency = 0.3 })
	local bars = {}
	local function barAt(anchor: number, shown: boolean): UDim2
		local out = if shown then 0 elseif anchor == 0 then -0.14 else 0.14
		return UDim2.new(0, -300, anchor + out, if anchor == 0 then -300 else 300)
	end
	for index, anchor in { 0, 1 } do
		bars[index] = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0, anchor),
			Position = barAt(anchor, false),
			Size = UDim2.new(1, 600, 0.14, 300),
			BackgroundColor3 = Color3.fromRGB(8, 4, 12),
			BorderSizePixel = 0,
			Parent = holder,
		})
		UIKit.Tween(bars[index], 0.6, { Position = barAt(anchor, true) })
	end
	local text = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(900, 220),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	UIKit.AutoScale(text)
	local small = UIKit.Label({
		Text = `THE {season.Time} SEASON HAS BEGUN`,
		Font = Theme.Fonts.Display,
		TextSize = 30,
		TextColor3 = colors.Glow,
		TextTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
		Parent = text,
		Children = { UIKit.TextStroke(0.3) },
	})
	local big = UIKit.Label({
		Text = season.Name,
		Font = TITLE_FONT,
		TextSize = 120,
		TextScaled = true,
		TextTransparency = 1,
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 150),
		Parent = text,
		Children = {
			UIKit.new("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, colors.Gold),
					ColorSequenceKeypoint.new(0.5, colors.Glow),
					ColorSequenceKeypoint.new(1, colors.Main),
				}),
				Rotation = 90,
			}),
			UIKit.new("UIStroke", { Color = Color3.fromRGB(70, 20, 10), Thickness = 3 }),
		},
	})
	turnTrees(4.5)
	task.delay(1.2, function()
		UIKit.Tween(small, 0.8, { TextTransparency = 0 })
		UIKit.Tween(big, 1.4, { TextTransparency = 0 })
	end)
	local born = os.clock()
	local flicker = RunService.Heartbeat:Connect(function()
		local t = os.clock() - born
		if t > 2.6 then
			big.TextTransparency = if math.sin(t * 19) > 0.9 then 0.2 else 0
		end
	end)
	task.delay(5.6, function()
		flicker:Disconnect()
		-- Up out of the card's way, still clear of Roblox's buttons on a small phone.
		UIKit.Tween(text, 0.5, { Position = UDim2.fromScale(0.5, 0.32) })
		onSeen()
		local p = State.Profile
		local keys = if p then p.Keys or 0 else 0
		local card = UIKit.Panel({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.66),
			Size = UDim2.fromOffset(620, if touch then 250 else 230),
			CornerRadius = 24,
			Parent = holder,
		}, colors.Panel, colors.Deep)
		UIKit.AutoScale(card)
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = colors.Main
			stroke.Transparency = 0
			stroke.Thickness = 3
		end
		local headline = UIKit.Label({
			Text = `Your first {season.Crate} is waiting{if keys > 0
				then `, with {CrateTheme.Count(keys, season.Key)}`
				else ""}!`,
			Font = Theme.Fonts.Display,
			TextSize = 26,
			Position = UDim2.fromOffset(20, 18),
			Size = UDim2.new(1, -40, 0, 70),
			Parent = card,
			Children = { UIKit.TextStroke(0.3) },
		})
		headline:SetAttribute("PP_Lines", 2) -- room for two (the UI checks)
		UIKit.Label({
			Text = "A crate every round you play. Keys on the PARTY CUP podium. 5 pets, 5 hats, 12 effects and one title.",
			TextSize = 18,
			TextColor3 = Theme.Colors.TextDim,
			Position = UDim2.fromOffset(20, 88),
			Size = UDim2.new(1, -40, 0, 50),
			Parent = card,
		})
		local h = if touch then Theme.Touch.Target else 56
		local function close()
			UIKit.Tween(dim, 0.5, { BackgroundTransparency = 1 })
			UIKit.Tween(bars[1], 0.5, { Position = barAt(0, false) })
			UIKit.Tween(bars[2], 0.5, { Position = barAt(1, false) })
			card:Destroy()
			text:Destroy()
			task.delay(0.6, function()
				holder:Destroy()
				welcomeShowing = false
				player:SetAttribute("PP_Celebrating", false)
			end)
		end
		UIKit.Button({
			Text = "OPEN IT!",
			TextSize = 26,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(0.5, -8, 1, -18),
			Size = UDim2.fromOffset(250, h),
			Parent = card,
		}, function()
			close()
			onOpen()
		end, colors.Glow, colors.Main)
		UIKit.Button({
			Text = "LATER",
			TextSize = 24,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0.5, 8, 1, -18),
			Size = UDim2.fromOffset(200, h),
			Parent = card,
		}, close, Theme.Colors.Lavender, Theme.Colors.Purple)
		UIKit.PopIn(card, 0.35)
	end)
end

function CrateMoments.Build()
	touch = UIKit.IsTouch()
	gui = UIKit.new("ScreenGui", {
		Name = "PartyPanicCrates",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 12,
		Parent = player:WaitForChild("PlayerGui"),
	})
	-- Both laid out at the design size and scaled to the screen (UIKit.AutoScale): the banners from
	-- the top, the cards round the middle.
	bannerHolder = UIKit.new("Frame", {
		Name = "Banners",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(Theme.DesignSize.X, Theme.DesignSize.Y),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UIKit.AutoScale(bannerHolder)
	cardHolder = UIKit.new("Frame", {
		Name = "Cards",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Theme.DesignSize.X, Theme.DesignSize.Y),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UIKit.AutoScale(cardHolder)
	for _, attribute in { "PP_ResultsShowing", "PP_CupPodium" } do
		player:GetAttributeChangedSignal(attribute):Connect(pump)
	end
	State.OnPlayingChanged(pump)
end

return CrateMoments
