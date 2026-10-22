-- The GOLD PASS on this device (owner: "Also we do need a paid battle pass too. I like the current free
-- one. But the paid one should also be insane."). The pass itself is the server's (Services/
-- GoldPassService); this draws its big moment and keeps its shine moving:
--   * UNLOCKED N REWARDS! When the pass is bought (or found on joining: bought on the website, or
--     the experience's creator), a gold card takes the screen: sun rays turning behind it, a crown
--     badge, the headline counting up to how many gold rewards it just unlocked, the rewards popping
--     in one by one (the coins, then the best cosmetics first, "+12 more"), the perks, gold confetti
--     and a fanfare. SEE GOLD LANE opens the Rewards screen on it; AWESOME! (or the X, or a tap
--     outside) closes it. A pass that comes while the player is playing a round waits for the end
--     of it. A player still on level 1 gets "GOLD PASS UNLOCKED!" and the perks.
--   * The shimmer: gradients tagged PP_GoldShimmer (an owner's name tag, the gold titles, the gold
--     buttons and badges) move here, on each device, so nothing is sent for it. "Sweep" runs a white
--     glint across gold every few seconds, "Glint" is a band of light over a gold button, "Drift"
--     eases a title's colours to and fro. With reduced effects they hold still.
--   * Glitter (PP_GoldGlitter: gold trails and hats) is switched off with reduced effects.
-- Phones: the card fits the shortest phone window (800 x 360), its buttons are 44 pt and on its right
-- half, and its text is 11 pt or bigger.
-- GoldPassController.Prompt() asks for Roblox's purchase prompt (the GET GOLD PASS buttons).
-- The price and whether it's for sale come from Roblox (GetProductInfo, asked in a pcall when the
-- game starts and every 10 minutes, kept in between), so they follow what the owner sets on Roblox:
-- off sale, the buttons say COMING SOON and prompt nothing; if Roblox can't be asked, the button
-- shows the usual price (Config.Monetization.GoldPassPrice) and Roblox's prompt has the last word.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Cosmetics = require(Shared.Cosmetics)
local GameState = require(Shared.GameState)
local GoldLane = require(Shared.Logic.GoldLane)
local GoldPass = require(Shared.GoldPass)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)

local AudioController = require(script.Parent.AudioController)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local GoldPassController = {}

local SHIMMER_TAG = "PP_GoldShimmer"
local GLITTER_TAG = "PP_GoldGlitter"
local CARD_W, CARD_H = 760, 404
local CHIP_Y, CHIP_H = 124, 132
local COIN_CHIP_W, ITEM_CHIP_W, MORE_CHIP_W, CHIP_GAP = 118, 146, 100, 10
local SHOW_FOR = 16
local OFFER_EVERY, OFFER_RETRY = 600, 30 -- seconds between asking Roblox for the price (again after a failure)
local GOLD = GoldPass.Colors

local touch = false
local gui: ScreenGui
local queue: { any } = {}
local closeCurrent: (() -> ())? = nil

-- The pass ---------------------------------------------------------------------------------------

-- Whether this player owns it (as the server last said).
function GoldPassController.Owned(): boolean
	local profile = State.Profile
	return profile ~= nil and type(profile.GoldPass) == "table" and profile.GoldPass.Owned == true
end

-- What Roblox offers (nil until it has answered): for sale or not, and the price.
local offer: GoldLane.Offer? = nil
local testOffer = false -- the check tools set it: Roblox's answers wait
GoldPassController.OfferChanged = Signal.new() -- (the Rewards screen redraws its button)

-- Whether it can be bought now: the pass exists and is for sale on Roblox.
function GoldPassController.OnSale(): boolean
	return offer ~= nil and offer.OnSale
end

-- Its price in Robux (Roblox's, or the usual one until Roblox answers).
function GoldPassController.Price(): number
	return if offer then offer.Price else Config.Monetization.GoldPassPrice
end

local function setOffer(new: GoldLane.Offer)
	local changed = offer == nil or offer.OnSale ~= new.OnSale or offer.Price ~= new.Price
	offer = new
	if changed then
		GoldPassController.OfferChanged:Fire()
	end
end

-- Asks Roblox for the pass's price and whether it's for sale. True when Roblox answered.
local function askOffer(): boolean
	local id = Config.Monetization.GoldPassId
	if testOffer then
		return true
	elseif id == 0 then
		setOffer(GoldLane.Offer(0, true, nil, Config.Monetization.GoldPassPrice))
		return true
	end
	local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, Enum.InfoType.GamePass)
	local new = GoldLane.Offer(id, ok, info, Config.Monetization.GoldPassPrice)
	if not testOffer then
		setOffer(new)
	end
	return new.Known
end

-- The check tools set the offer to draw each state (nil: ask Roblox again).
function GoldPassController.SetOfferForTests(test: GoldLane.Offer?)
	testOffer = test ~= nil
	if test then
		setOffer(test)
	else
		task.spawn(askOffer)
	end
end

-- Asks for Roblox's purchase prompt (the server shows it).
function GoldPassController.Prompt()
	Remotes.Get("GoldPass"):FireServer("Prompt")
end

-- A gold gradient for a panel or button (light at the top, deep at the bottom).
function GoldPassController.Fill(rotation: number?): UIGradient
	return UIKit.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, GOLD.Light),
			ColorSequenceKeypoint.new(0.45, GOLD.Gold),
			ColorSequenceKeypoint.new(1, GOLD.Deep),
		}),
		Rotation = rotation or 90,
	})
end

-- A band of light that slides across a gold button or panel now and then (it has `parent`'s
-- rounding; the controller moves it).
function GoldPassController.Glint(parent: GuiObject, radius: number?): Frame
	local band = UIKit.new("Frame", {
		Name = "Glint",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = GOLD.Shine,
		BorderSizePixel = 0,
		ZIndex = parent.ZIndex,
		Parent = parent,
		Children = {
			if radius then UIKit.Corner(radius) else UIKit.Round(),
		},
	})
	local gradient = UIKit.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = 25,
		Offset = Vector2.new(1, 0),
		Parent = band,
	})
	gradient:SetAttribute("PP_Shimmer", "Glint")
	CollectionService:AddTag(gradient, SHIMMER_TAG)
	return band
end

-- The shimmer ------------------------------------------------------------------------------------

local shimmers: { [UIGradient]: number } = {} -- each gradient's own start (they don't all glint at once)

local function addShimmer(instance: Instance)
	if instance:IsA("UIGradient") then
		shimmers[instance] = math.random() * 3
	end
end

local function stepShimmers()
	local reduced = State.ReducedEffects()
	local now = os.clock()
	for gradient, seed in shimmers do
		if not gradient.Parent then
			shimmers[gradient] = nil
			continue
		end
		local kind = gradient:GetAttribute("PP_Shimmer")
		local x
		if kind == "Drift" then
			x = if reduced then 0 else 0.32 * math.sin((now + seed) * 1.3)
		else
			-- Sweep and Glint: a pass every few seconds, gold (or nothing) in between.
			local period, sweep = if kind == "Glint" then 2.8 else 3.6, if kind == "Glint" then 0.9 else 1.2
			local phase = (now + seed) % period
			x = if reduced or phase > sweep then 1 else -1 + 2 * phase / sweep
		end
		gradient.Offset = Vector2.new(x, 0)
	end
end

local function setGlitter(emitter: Instance)
	if emitter:IsA("ParticleEmitter") then
		emitter.Enabled = not State.ReducedEffects()
	end
end

-- The UNLOCKED card ----------------------------------------------------------------------------------

local function label(props: { [string]: any }): TextLabel
	props.BackgroundTransparency = 1
	props.ZIndex = props.ZIndex or 4
	return UIKit.Label(props)
end

-- A dark ink outline for text on gold.
local function ink(transparency: number?): UIStroke
	return UIKit.new("UIStroke", {
		Color = GOLD.Ink,
		Thickness = 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	})
end

local function goldChip(parent: Instance, name: string, width: number, order: number): Frame
	local chip = UIKit.new("Frame", {
		Name = name,
		Size = UDim2.fromOffset(width, CHIP_H),
		BackgroundColor3 = Color3.new(1, 1, 1),
		LayoutOrder = order,
		ZIndex = 3,
		Parent = parent,
		Children = {
			UIKit.Corner(18),
			GoldPassController.Fill(),
			UIKit.new("UIStroke", { Color = GOLD.Ink, Thickness = 2.5, Transparency = 0.1 }),
		},
	})
	return chip
end

local function coinChip(parent: Instance, coins: number, order: number): Frame
	local chip = goldChip(parent, "Coins", COIN_CHIP_W, order)
	UIKit.Coin({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(46, 46),
		ZIndex = 4,
		Parent = chip,
	})
	label({
		Text = `+{coins}`,
		Font = Theme.Fonts.Display,
		TextSize = 34,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 0, 40),
		Parent = chip,
		Children = { ink() },
	})
	label({
		Text = "COINS",
		Font = Theme.Fonts.Display,
		TextSize = 20,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 100),
		Size = UDim2.new(1, 0, 0, 24),
		Parent = chip,
		Children = { ink(0.1) },
	})
	return chip
end

local function itemChip(parent: Instance, item: Cosmetics.Cosmetic, order: number): Frame
	local chip = goldChip(parent, item.Id, ITEM_CHIP_W, order)
	label({
		Text = item.Icon,
		TextSize = 38,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 44),
		Parent = chip,
	})
	local name = label({
		Text = item.Name,
		Font = Theme.Fonts.Display,
		TextSize = 19,
		Position = UDim2.fromOffset(6, 56),
		Size = UDim2.new(1, -12, 0, 46),
		Parent = chip,
		Children = { ink() },
	})
	name:SetAttribute("PP_Lines", 2)
	label({
		Text = string.upper(Cosmetics.SlotNames[item.Slot] or item.Slot),
		Font = Theme.Fonts.Display,
		TextSize = Theme.Touch.MinText,
		TextWrapped = false,
		TextColor3 = GOLD.Shine,
		Position = UDim2.fromOffset(6, 102),
		Size = UDim2.new(1, -12, 0, 22),
		Parent = chip,
		Children = { ink(0.2) },
	})
	return chip
end

local function moreChip(parent: Instance, count: number, order: number): Frame
	local chip = goldChip(parent, "More", MORE_CHIP_W, order)
	local text = label({
		Text = `+{count}\nmore!`,
		Font = Theme.Fonts.Display,
		TextSize = 28,
		Size = UDim2.fromScale(1, 1),
		Parent = chip,
		Children = { ink() },
	})
	text:SetAttribute("PP_Lines", 2)
	return chip
end

local function perkChip(parent: Instance, perk: { Icon: string, Text: string }, order: number): Frame
	local chip = goldChip(parent, "Perk", ITEM_CHIP_W - 4, order)
	label({
		Text = perk.Icon,
		TextSize = 38,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.new(1, 0, 0, 44),
		Parent = chip,
	})
	local text = label({
		Text = perk.Text,
		Font = Theme.Fonts.Display,
		TextSize = Theme.Touch.MinText,
		Position = UDim2.fromOffset(6, 60),
		Size = UDim2.new(1, -12, 0, 64),
		Parent = chip,
		Children = { ink() },
	})
	text:SetAttribute("PP_Lines", 3)
	return chip
end

-- Sun rays turning behind the card, reaching past it across the screen.
local function rays(parent: Instance): Frame
	local holder = UIKit.new("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = parent,
	})
	for index = 1, 12 do
		UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(1500, 70),
			Rotation = index * 15,
			BackgroundColor3 = GOLD.Light,
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = holder,
			Children = {
				UIKit.new("UIGradient", {
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 1),
						NumberSequenceKeypoint.new(0.35, 0.72),
						NumberSequenceKeypoint.new(0.5, 0.55),
						NumberSequenceKeypoint.new(0.65, 0.72),
						NumberSequenceKeypoint.new(1, 1),
					}),
				}),
			},
		})
	end
	return holder
end

-- Gold confetti falling over the card (clipped to it).
local function confetti(layer: Frame)
	local colors = { GOLD.Light, GOLD.Gold, GOLD.Shine, GOLD.Deep, Color3.fromRGB(255, 120, 190) }
	for index = 1, if State.ReducedEffects() then 8 else 30 do
		local piece = UIKit.new("Frame", {
			Name = "Confetti",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.03 + math.random() * 0.94, -0.04 - math.random() * 0.25),
			Size = UDim2.fromOffset(math.random(8, 12), math.random(13, 18)),
			Rotation = math.random(0, 360),
			BackgroundColor3 = colors[(index % #colors) + 1],
			BorderSizePixel = 0,
			ZIndex = 8,
			Parent = layer,
		})
		local fall = 2 + math.random() * 1.6
		UIKit.Tween(piece, fall, {
			Position = UDim2.fromScale(piece.Position.X.Scale + (math.random() - 0.5) * 0.15, 0.97),
			Rotation = piece.Rotation + math.random(-540, 540),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(piece, fall + 0.2)
	end
end

local function show(payload: any)
	local count = tonumber(payload.Count) or 0
	local coins = tonumber(payload.Coins) or 0
	local items: { Cosmetics.Cosmetic } = {}
	for _, id in if type(payload.Items) == "table" then payload.Items else {} do
		local item = Cosmetics.Get(id)
		if item then
			table.insert(items, item)
		end
	end

	-- A full-screen moment: the backdrop dims everything (it reaches past the safe area) and closes it.
	local root = UIKit.new("Frame", {
		Name = "GoldUnlocked",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local backdrop = UIKit.new("TextButton", {
		Name = "Backdrop",
		Position = UDim2.fromOffset(-300, -300),
		Size = UDim2.new(1, 600, 1, 600),
		BackgroundColor3 = Color3.fromRGB(30, 16, 4),
		BackgroundTransparency = 0.3,
		AutoButtonColor = false,
		Text = "",
		Parent = root,
	})
	local holder = UIKit.new("Frame", {
		Name = "Holder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundTransparency = 1,
		Parent = root,
	})
	UIKit.AutoScale(holder)
	local sun = rays(holder)
	local card = UIKit.new("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = holder,
		Children = {
			UIKit.Corner(28),
			UIKit.Gradient(Color3.fromRGB(70, 44, 140), Theme.Colors.PanelDark),
			UIKit.new("UIStroke", { Color = GOLD.Gold, Thickness = 5, Transparency = 0 }),
		},
	})
	card:SetAttribute("PP_Popup", true)
	-- A gold band across the top, behind the headline.
	UIKit.new("Frame", {
		Name = "Band",
		Size = UDim2.new(1, 0, 0, 112),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = card,
		Children = {
			UIKit.new("UIGradient", {
				Color = ColorSequence.new(GOLD.Deep, GOLD.Gold),
				Transparency = NumberSequence.new(0.35, 0.85),
				Rotation = 90,
			}),
		},
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
		task.delay(0.4, GoldPassController.Pump)
	end
	closeCurrent = close
	backdrop.Activated:Connect(close)

	-- Row 1: the crown badge, the pass's name and the headline; the X in the corner.
	local badge = UIKit.new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(20 + 46, 14 + 46),
		Size = UDim2.fromOffset(92, 92),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 4,
		Parent = card,
		Children = {
			UIKit.Round(),
			GoldPassController.Fill(),
			UIKit.new("UIStroke", { Color = GOLD.Shine, Thickness = 4, Transparency = 0 }),
		},
	})
	label({
		Text = GoldPass.Icon,
		TextSize = 54,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = badge,
	})
	label({
		Name = "PassName",
		Text = GoldPass.Name,
		Font = Theme.Fonts.Display,
		TextSize = 24,
		TextWrapped = false,
		TextColor3 = GOLD.Shine,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(128, 14),
		Size = UDim2.fromOffset(420, 30),
		Parent = card,
		Children = { ink(0.1) },
	})
	local headline = label({
		Name = "Headline",
		Text = if count > 0 then "UNLOCKED 0 REWARDS!" else "GOLD PASS UNLOCKED!",
		Font = Theme.Fonts.Display,
		TextSize = 40,
		TextWrapped = false,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(126, 46),
		Size = UDim2.fromOffset(CARD_W - 126 - 100, 54),
		Parent = card,
		Children = { ink() },
	})
	local headGradient = UIKit.new("UIGradient", { Color = GoldPass.Shimmer, Parent = headline })
	headGradient:SetAttribute("PP_Shimmer", "Sweep")
	CollectionService:AddTag(headGradient, SHIMMER_TAG)
	UIKit.Button({
		Name = "Close",
		Text = "X",
		TextSize = 30,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(if touch then Theme.Touch.Target else 56, if touch then Theme.Touch.Target else 56),
		CornerRadius = "round",
		ZIndex = 6,
		Parent = card,
	}, close, Theme.Colors.Red, Color3.fromRGB(190, 40, 60))

	-- Row 2: what it unlocked, popping in one by one (or the perks, for a player on level 1).
	local row = UIKit.new("Frame", {
		Name = "Rewards",
		Position = UDim2.fromOffset(0, CHIP_Y),
		Size = UDim2.new(1, 0, 0, CHIP_H),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = card,
		Children = { UIKit.List(Enum.FillDirection.Horizontal, CHIP_GAP, Enum.HorizontalAlignment.Center) },
	})
	local chips = {}
	if count > 0 then
		if coins > 0 then
			table.insert(chips, coinChip(row, coins, 1))
		end
		-- As many cosmetics as fit beside the coins (3, or 4 without), the rest as "+12 more!".
		local room = if coins > 0 then 3 else 4
		for index, item in items do
			if index >= room and #items > room then
				table.insert(chips, moreChip(row, #items - index + 1, 10))
				break
			end
			table.insert(chips, itemChip(row, item, 1 + index))
		end
	else
		for index, perk in GoldPass.Perks do
			table.insert(chips, perkChip(row, perk, index))
		end
	end
	for index, chip in chips do
		local slot = UIKit.new("Frame", {
			Name = chip.Name .. "Slot",
			Size = chip.Size,
			LayoutOrder = chip.LayoutOrder,
			BackgroundTransparency = 1,
			ZIndex = 3,
			Parent = row,
		})
		chip.AnchorPoint = Vector2.new(0.5, 0.5)
		chip.Position = UDim2.fromScale(0.5, 0.5)
		chip.Parent = slot
		chip.Visible = false
		task.delay(0.5 + index * 0.16, function()
			if chip.Parent then
				chip.Visible = true
				UIKit.PopIn(chip, 0.35)
			end
		end)
	end

	-- Row 3: the perks (when rewards took row 2), and the buttons on the right half.
	local perks = {}
	for _, perk in GoldPass.Perks do
		table.insert(perks, `{perk.Icon} {perk.Text}`)
	end
	local note = label({
		Name = "Perks",
		Text = if count > 0
			then "Plus: " .. table.concat(perks, "   ")
			else "Every level from here on gives you a gold reward too!",
		TextSize = Theme.Touch.MinText,
		TextColor3 = GOLD.Light,
		Position = UDim2.fromOffset(20, CHIP_Y + CHIP_H + 10),
		Size = UDim2.new(1, -40, 0, 48),
		Parent = card,
	})
	note:SetAttribute("PP_Lines", 2)
	local buttonHeight = if touch then Theme.Touch.Target else 60
	local buttons = UIKit.new("Frame", {
		Name = "Buttons",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -18, 1, -14),
		Size = UDim2.fromOffset(CARD_W / 2, buttonHeight),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = card,
		Children = {
			UIKit.List(
				Enum.FillDirection.Horizontal,
				10,
				Enum.HorizontalAlignment.Right,
				Enum.VerticalAlignment.Center
			),
		},
	})
	UIKit.Button({
		Name = "SeeLane",
		Text = "SEE GOLD LANE",
		TextSize = 20,
		Size = UDim2.fromOffset(168, buttonHeight),
		CornerRadius = 18,
		LayoutOrder = 1,
		ZIndex = 5,
		Parent = buttons,
	}, function()
		close()
		State.OpenScreen:Fire("Rewards", "Road")
	end, Theme.Colors.Lavender, Theme.Colors.Purple)
	local awesome = UIKit.Button({
		Name = "Awesome",
		Text = "AWESOME!",
		TextSize = 24,
		Size = UDim2.fromOffset(150, buttonHeight),
		CornerRadius = 18,
		LayoutOrder = 2,
		ZIndex = 5,
		Parent = buttons,
	}, close, GOLD.Gold, GOLD.Deep)
	GoldPassController.Glint(awesome, 18)

	-- Motion: the card pops, the headline counts up, the sun turns, confetti falls.
	UIKit.PopIn(holder, 0.45)
	UIKit.PopIn(badge, 0.7)
	confetti(card)
	if count > 0 then
		task.spawn(function()
			local started = os.clock()
			local duration = math.clamp(count * 0.04, 0.5, 1.4)
			while not closed and headline.Parent do
				local t = math.min(1, (os.clock() - started) / duration)
				local shown = math.floor(count * (1 - (1 - t) ^ 2) + 0.5)
				headline.Text = `UNLOCKED {shown} REWARD{if shown == 1 then "" else "S"}!`
				if t >= 1 then
					break
				end
				task.wait()
			end
			if not closed then
				UIKit.PopIn(headline, 0.3)
			end
		end)
	end
	if not State.ReducedEffects() then
		local spin = RunService.Heartbeat:Connect(function()
			sun.Rotation = (os.clock() * 12) % 360
		end)
		root.Destroying:Connect(function()
			spin:Disconnect()
		end)
	end
	AudioController.Play("Victory")
	task.delay(0.6, AudioController.Play, "Purchase")
	task.delay(SHOW_FOR, close)
end

-- Shows the next card if it's a good moment: never over a round the player is playing.
function GoldPassController.Pump()
	if closeCurrent or #queue == 0 or State.PlayingRound() or not State.Profile then
		return
	end
	local payload = table.remove(queue, 1)
	show(payload)
end

-- Closes the card on screen (the client harness uses this too).
function GoldPassController.Dismiss()
	if closeCurrent then
		closeCurrent()
	end
end

function GoldPassController.Start(context)
	touch = UIKit.IsTouch()
	-- Its own layer, above the windows (10): it's the moment right after buying, often from one.
	gui = UIKit.new("ScreenGui", {
		Name = "PartyPanicGold",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 12,
		Parent = context.Hud.Parent,
	})

	Remotes.Get("GoldPass").OnClientEvent:Connect(function(kind, payload)
		if kind == "Unlocked" and type(payload) == "table" then
			table.insert(queue, payload)
			GoldPassController.Pump()
		end
	end)
	State.OnPlayingChanged(function()
		GoldPassController.Pump()
	end)
	State.ProfileChanged:Connect(function()
		GoldPassController.Pump()
	end)
	GameState.Changed("Phase", function()
		if State.PlayingRound() then
			GoldPassController.Dismiss() -- the round's on: out of the way (it doesn't come back)
		end
	end)

	for _, gradient in CollectionService:GetTagged(SHIMMER_TAG) do
		addShimmer(gradient)
	end
	CollectionService:GetInstanceAddedSignal(SHIMMER_TAG):Connect(addShimmer)
	CollectionService:GetInstanceRemovedSignal(SHIMMER_TAG):Connect(function(gradient)
		shimmers[gradient :: any] = nil
	end)
	RunService.RenderStepped:Connect(stepShimmers)

	for _, emitter in CollectionService:GetTagged(GLITTER_TAG) do
		setGlitter(emitter)
	end
	CollectionService:GetInstanceAddedSignal(GLITTER_TAG):Connect(setGlitter)
	State.SettingsChanged:Connect(function()
		for _, emitter in CollectionService:GetTagged(GLITTER_TAG) do
			setGlitter(emitter)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(if askOffer() then OFFER_EVERY else OFFER_RETRY)
		end
	end)
end

return GoldPassController
