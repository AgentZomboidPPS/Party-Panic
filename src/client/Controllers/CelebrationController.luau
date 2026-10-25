-- The big moments (owner: "Also we need cool payoffs for players that keep playing the game."):
--   * LEVEL UP! A celebration card: the new level pops out in a badge with its prestige colors,
--     rings and confetti fly, a fanfare plays, and the rewards are revealed one by one (the Rewards
--     Road's coins and any exclusive cosmetic), then the next goal, with EQUIP for a new trail,
--     title or effect and a button to the Rewards screen. Career milestones get the same moment
--     ("MILESTONE!"), and a returning player gets the rewards their level and career had already
--     earned when the update came out ("NEW REWARDS!"). EQUIP puts on what it unlocked; a new
--     emote gets TRY IT.
--   * Over the head of anyone who levels up, a "Lv 10!" pops up for everyone in the lobby to see
--     (a level-up from a round's rewards pops once everyone is back in the lobby); a new Game Mastery
--     rank pops up the same way ("GOLD RANK!" and the game, in the rank's colours).
-- The server has already granted everything (Services/ProgressionService); this only shows it.
-- A celebration waits for a calm moment: never during the vote, the rules card, the round or the
-- results (it shows when everyone's back in the lobby), and several at once make one. It closes
-- itself after a few seconds, with its ✕, when a window opens or when the vote starts.
--
-- Second pass (owner: "it just has to work", phones first): it is a card, not a full-screen
-- pop-up. Nothing dims or blocks the screen, so the MOVE stick, the jump button and the menu keep
-- working while it shows. Phones: the card sits at the top middle (where the first-join tip goes,
-- which steps aside meanwhile; PP_Celebrating), clear of the profile chip, the menu column, the
-- jump button and the toasts on the smallest phone; its buttons are on its right half, outside
-- the thumbstick's corner, and 44 pt tall. PC: the middle of the screen.
--
-- Third pass (review): a card waits for the player's profile (its "Next up" goal comes from it),
-- the rewards are in fixed slots so the row doesn't jump as each one pops in, and the best reward
-- comes first, which is also what EQUIP ALL puts on (a veteran's NEW REWARDS! card would
-- otherwise equip the level-3 trail over the level-35 one). The "Lv 10!" over a head shows once
-- everyone is back in the lobby (ProgressionService holds the ones from the end of a round).
--
-- Shorter lobby (owner: "Less time sitting in the lobby. total of 20 seconds instead of 40."): the
-- calm time between the results and the vote is about 6 seconds now, so a round's card shows for
-- those 6 (the vote closes it), and one that comes in later in the lobby (an emote quest's level-up)
-- waits for the next calm moment rather than start with under MIN_SHOW seconds to go: it would
-- only flash up before the vote took it away, and it wouldn't come back.
--
-- PLAY AGAIN (owner: "Add a vote at the end of each minigame to replay the same minigame."): when
-- the results' vote plays the same game again, Cleanup leads straight into its rules card (the
-- GameState "Replay" attribute says so), so a round's card waits for the lobby after it.
--
-- The card's ✕ wore the panels' dark purple (owner: "why are the close menu buttons and the invite
-- friend button so dark?"): it's the windows' bright red ✕ now, same size and spot.
--
-- The GOLD PASS (owner: "the paid one should also be insane"): an owner's level-up shows the gold
-- lane's reward too: its gold coins on a gold chip of their own ("+7 GOLD") and its cosmetics on gold
-- chips, the best first; "Next up" can be a gold reward. (Buying the pass has its own card:
-- Controllers/GoldPassController.)
-- The crate seasons (Shared/Seasons): every 5th level also gives a key for the season's crates
-- (Services/CrateService), on a chip of its own in the season's colours ("+1 KEY").
-- Game Mastery (owner: "Let's build it. 1 yes 2 gold pass should help a little. 3 yes";
-- Services/MasteryService, UI/Mastery): a new rank in a game gets its own card, "GOLD RANK!", with
-- the rank's badge, "You're GOLD at HEX MELTDOWN!", its coins, keys and crate on chips, and the next
-- goal ("Next: 25 pts to DIAMOND"). It shows after a level-up or milestone card from the same round
-- rather than being folded into it; several new ranks at once make one card (the highest, every
-- reward added up).

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Cosmetics = require(Shared.Cosmetics)
local GameDefinitions = require(Shared.GameDefinitions)
local GameState = require(Shared.GameState)
local GoldPass = require(Shared.GoldPass)
local MasteryLogic = require(Shared.Logic.MasteryLogic)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)
local Seasons = require(Shared.Seasons)

local AudioController = require(script.Parent.AudioController)
local GoldPassController = require(script.Parent.GoldPassController)
local State = require(script.Parent.Parent.State)
local Mastery = require(script.Parent.Parent.UI.Mastery)
local Modal = require(script.Parent.Parent.UI.Modal)
local PartyKit = require(script.Parent.Parent.UI.PartyKit)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local CelebrationController = {}

type Celebration = {
	Kind: string, -- "LevelUp" | "Milestone" | "Welcome" (rewards a returning player had already earned) | "Mastery"
	Game: string?, -- Mastery: the game
	Rank: number?, -- Mastery: the new rank (Config.Mastery.Ranks)
	Crates: number?, -- Mastery: crates (DIAMOND)
	Level: number?,
	From: number?,
	Coins: number,
	GoldCoins: number?, -- LevelUp: the gold lane's coins (GOLD PASS owners)
	Keys: number?, -- LevelUp: crate keys (every 5th level; Services/CrateService)
	Items: { string },
}

local CALM = { Waiting = true, Intermission = true, Cleanup = true }
local SHOW_FOR = 9
local MIN_SHOW = 4 -- a card starts in the lobby only with at least this long before the vote
-- The card, in scaled units (every phone shows it at 0.62 points a unit: 372 x 213 pt).
local CARD_W, CARD_H = 600, 344
local CHIP_Y, CHIP_H = 126, 128
local COIN_CHIP_W, ITEM_CHIP_W, MORE_CHIP_W, CHIP_GAP = 116, 150, 96, 10
local BOTTOM_Y = 262 -- the next goal (left) and the buttons (right half: clear of the thumbstick)
local BUTTONS_LEFT = 296
local PC_BIAS = 1 -- PC: 600 x 344 in the middle, clear of the first-join tip under the coins
local CONFETTI = {
	Color3.fromRGB(255, 90, 140),
	Color3.fromRGB(90, 190, 255),
	Color3.fromRGB(255, 210, 70),
	Color3.fromRGB(150, 110, 255),
	Color3.fromRGB(110, 230, 140),
}
local GOLD = ColorSequence.new(Color3.fromRGB(255, 236, 120), Color3.fromRGB(240, 150, 30))
local CYAN_DARK = Color3.fromRGB(50, 120, 230)
local GREEN_DARK = Color3.fromRGB(60, 160, 90)
local PINK_DARK = Color3.fromRGB(200, 50, 140)

-- Where each cosmetic is in the catalog (the tie-break for "best first").
local catalogIndex: { [string]: number } = {}
for index, item in Cosmetics.List do
	catalogIndex[item.Id] = index
end

-- Best first: the highest road level (free or gold), then the biggest career milestone, then
-- catalog order.
local function better(a: Cosmetics.Cosmetic, b: Cosmetics.Cosmetic): boolean
	local levelA, levelB = a.UnlockLevel or a.GoldLevel or 0, b.UnlockLevel or b.GoldLevel or 0
	if levelA ~= levelB then
		return levelA > levelB
	end
	local statA = if a.UnlockStat then a.UnlockStat.Value else 0
	local statB = if b.UnlockStat then b.UnlockStat.Value else 0
	if statA ~= statB then
		return statA > statB
	end
	return (catalogIndex[a.Id] or 0) < (catalogIndex[b.Id] or 0)
end

local touch = false
local gui: ScreenGui
local queue: { Celebration } = {}
local closeCurrent: (() -> ())? = nil
local windowOpen = false -- a window (Modal) is open: the celebration waits for it to close

-- Several new Game Mastery ranks make one card: the highest (the latest of equals), every reward.
local function mergeMastery(list: { Celebration }): Celebration
	local merged: Celebration = { Kind = "Mastery", Coins = 0, Items = {} }
	for _, entry in list do
		if (entry.Rank or 0) >= (merged.Rank or 0) then
			merged.Rank = entry.Rank
			merged.Game = entry.Game
		end
		merged.Coins += entry.Coins or 0
		if entry.Keys and entry.Keys > 0 then
			merged.Keys = (merged.Keys or 0) + entry.Keys
		end
		if entry.Crates and entry.Crates > 0 then
			merged.Crates = (merged.Crates or 0) + entry.Crates
		end
	end
	return merged
end

-- Several waiting celebrations make one: the highest level reached, every coin and every item.
local function merge(list: { Celebration }): Celebration
	local merged: Celebration = { Kind = "Milestone", Coins = 0, Items = {} }
	local seen = {}
	for _, entry in list do
		if entry.Kind == "Welcome" and merged.Kind == "Milestone" then
			merged.Kind = "Welcome"
		elseif entry.Kind == "LevelUp" then
			merged.Kind = "LevelUp"
			merged.Level = math.max(merged.Level or 0, entry.Level or 0)
			merged.From = math.min(merged.From or math.huge, entry.From or entry.Level or 1)
		end
		merged.Coins += entry.Coins or 0
		if entry.GoldCoins and entry.GoldCoins > 0 then
			merged.GoldCoins = (merged.GoldCoins or 0) + entry.GoldCoins
		end
		if entry.Keys and entry.Keys > 0 then
			merged.Keys = (merged.Keys or 0) + entry.Keys
		end
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

-- The reward chips (nothing on them takes taps: part of the row can be in the thumbstick's corner).
local function coinChip(parent: Instance, coins: number, order: number): Frame
	local chip = UIKit.Panel({
		Name = "Coins",
		Size = UDim2.fromOffset(COIN_CHIP_W, CHIP_H),
		LayoutOrder = order,
		CornerRadius = 18,
		ZIndex = 3,
		Parent = parent,
	}, Color3.fromRGB(255, 196, 60), Color3.fromRGB(230, 130, 30))
	UIKit.Coin({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(44, 44),
		ZIndex = 4,
		Parent = chip,
	})
	label({
		Text = `+{coins}`,
		Font = Theme.Fonts.Display,
		TextSize = 36,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 0, 40),
		ZIndex = 4,
		Parent = chip,
		Children = { UIKit.TextStroke(0.1) },
	})
	label({
		Text = "COINS",
		Font = Theme.Fonts.Display,
		TextSize = 20,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 96),
		Size = UDim2.new(1, 0, 0, 24),
		ZIndex = 4,
		Parent = chip,
		Children = { UIKit.TextStroke(0.2) },
	})
	return chip
end

-- The gold lane's coins: a gold chip with a crown over the coin.
local function goldCoinChip(parent: Instance, coins: number, order: number): Frame
	local chip = coinChip(parent, coins, order)
	chip.Name = "GoldCoins"
	local fill = chip:FindFirstChildOfClass("UIGradient")
	if fill then
		fill.Color = GoldPassController.Fill().Color
	end
	local rim = chip:FindFirstChildOfClass("UIStroke")
	if rim then
		rim.Color, rim.Thickness, rim.Transparency = GoldPass.Colors.Ink, 2.5, 0.1
	end
	for _, child in chip:GetChildren() do
		if child:IsA("TextLabel") and child.Text == "COINS" then
			child.Text = `{GoldPass.Icon} GOLD`
		end
	end
	return chip
end

-- Crate keys: a chip in the season's colours with the key on it.
local function keyChip(parent: Instance, keys: number, order: number): Frame
	local colors = Seasons.CurrentSeason().Colors
	local chip = UIKit.Panel(
		{
			Name = "Keys",
			Size = UDim2.fromOffset(COIN_CHIP_W, CHIP_H),
			LayoutOrder = order,
			CornerRadius = 18,
			ZIndex = 3,
			Parent = parent,
		},
		Color3.fromRGB(colors.Main[1], colors.Main[2], colors.Main[3]),
		Color3.fromRGB(colors.Crimson[1], colors.Crimson[2], colors.Crimson[3])
	)
	label({
		Text = "🔑",
		TextSize = 40,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 48),
		ZIndex = 4,
		Parent = chip,
	})
	label({
		Text = `+{keys}`,
		Font = Theme.Fonts.Display,
		TextSize = 36,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 0, 40),
		ZIndex = 4,
		Parent = chip,
		Children = { UIKit.TextStroke(0.1) },
	})
	label({
		Text = if keys == 1 then "KEY" else "KEYS",
		Font = Theme.Fonts.Display,
		TextSize = 20,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 96),
		Size = UDim2.new(1, 0, 0, 24),
		ZIndex = 4,
		Parent = chip,
		Children = { UIKit.TextStroke(0.2) },
	})
	return chip
end

-- Crates (Game Mastery's DIAMOND): a chip like the keys', with the crate on it.
local function crateChip(parent: Instance, crates: number, order: number): Frame
	local chip = keyChip(parent, crates, order)
	chip.Name = "Crates"
	for _, child in chip:GetChildren() do
		if child:IsA("TextLabel") then
			if child.Text == "🔑" then
				child.Text = "📦"
			elseif child.Text == "KEY" or child.Text == "KEYS" then
				child.Text = if crates == 1 then "CRATE" else "CRATES"
			end
		end
	end
	return chip
end

local function itemChip(parent: Instance, item: Cosmetics.Cosmetic, order: number): Frame
	local chip = UIKit.Panel({
		Name = item.Id,
		Size = UDim2.fromOffset(ITEM_CHIP_W, CHIP_H),
		LayoutOrder = order,
		CornerRadius = 18,
		ZIndex = 3,
		Parent = parent,
	}, Theme.Colors.Card, Theme.Colors.PanelDark)
	if item.GoldLevel then
		-- A GOLD PASS reward: a gold chip.
		local fill = chip:FindFirstChildOfClass("UIGradient")
		if fill then
			fill.Color = GoldPassController.Fill().Color
		end
		local rim = chip:FindFirstChildOfClass("UIStroke")
		if rim then
			rim.Color, rim.Thickness, rim.Transparency = GoldPass.Colors.Ink, 2.5, 0.1
		end
	end
	if item.Colors and #item.Colors > 1 then
		-- Trails and the like show their colors along the top.
		UIKit.new("Frame", {
			Position = UDim2.fromOffset(12, 7),
			Size = UDim2.new(1, -24, 0, 7),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 4,
			Parent = chip,
			Children = { UIKit.Round(), UIKit.new("UIGradient", { Color = Cosmetics.ColorSequence(item.Colors) }) },
		})
	end
	label({
		Text = item.Icon,
		TextSize = 34,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 38),
		ZIndex = 4,
		Parent = chip,
	})
	local name = label({
		Text = item.Name,
		Font = Theme.Fonts.Display,
		TextSize = 18,
		Position = UDim2.fromOffset(6, 52),
		Size = UDim2.new(1, -12, 0, 44),
		ZIndex = 4,
		Parent = chip,
		Children = { UIKit.TextStroke(0.3) },
	})
	name:SetAttribute("PP_Lines", 2) -- "Rainbow Fireworks" takes two lines on a chip
	label({
		Text = string.upper(Cosmetics.SlotNames[item.Slot] or item.Slot),
		TextSize = Theme.Touch.MinText,
		TextWrapped = false,
		TextColor3 = if item.GoldLevel then GoldPass.Colors.Ink else Theme.Colors.TextDim,
		Position = UDim2.fromOffset(6, 98),
		Size = UDim2.new(1, -12, 0, 22),
		ZIndex = 4,
		Parent = chip,
	})
	return chip
end

local function moreChip(parent: Instance, count: number, order: number): Frame
	local chip = UIKit.Panel({
		Name = "More",
		Size = UDim2.fromOffset(MORE_CHIP_W, CHIP_H),
		LayoutOrder = order,
		CornerRadius = 18,
		ZIndex = 3,
		Parent = parent,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	local text = label({
		Text = `+{count}\nmore!`,
		Font = Theme.Fonts.Display,
		TextSize = 26,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = chip,
		Children = { UIKit.TextStroke(0.2) },
	})
	text:SetAttribute("PP_Lines", 2)
	return chip
end

-- What to aim for next, after this celebration.
local function nextGoal(celebration: Celebration): string
	local profile = State.Profile
	if celebration.Kind == "Mastery" then
		local progress = Mastery.Progress(celebration.Game or "")
		return if progress.Next then `Next: {MasteryLogic.Goal(progress)}` else "The top rank in this game!"
	end
	if celebration.Kind ~= "Milestone" then
		local level = celebration.Level or (profile and profile.Level) or 1
		local nextLevel, item = Progression.NextReward(level, GoldPassController.Owned())
		if item then
			return `Next up: {item.Icon} {item.Name} at Lv {nextLevel}`
		end
		return "You've unlocked every level reward!"
	end
	local best = profile and Progression.SortedMilestones(profile.Owned, profile.Stats)[1]
	if best and profile and not profile.Owned[best.Id] then
		local have, target = Progression.MilestoneProgress(best, profile.Stats)
		return `Next: {best.Icon} {best.Name} ({have}/{target})`
	end
	return "Every career milestone unlocked!"
end

-- Confetti falls over the card (clipped to it: never over the stick, the jump button or the menu).
local function confetti(layer: Frame, colors: { Color3 }?)
	local palette = colors or CONFETTI
	local count = if State.ReducedEffects() then 8 else 26
	for index = 1, count do
		local piece = UIKit.new("Frame", {
			Name = "Confetti",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.04 + math.random() * 0.92, -0.04 - math.random() * 0.2),
			Size = UDim2.fromOffset(math.random(8, 12), math.random(13, 18)),
			Rotation = math.random(0, 360),
			BackgroundColor3 = palette[(index % #palette) + 1],
			BorderSizePixel = 0,
			ZIndex = 6,
			Parent = layer,
		})
		local fall = 1.8 + math.random() * 1.4
		UIKit.Tween(piece, fall, {
			Position = UDim2.fromScale(piece.Position.X.Scale + (math.random() - 0.5) * 0.15, 0.96),
			Rotation = piece.Rotation + math.random(-540, 540),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(piece, fall + 0.2)
	end
end

local function ring(parent: Instance, center: UDim2, delay: number)
	local circle = UIKit.new("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = center,
		Size = UDim2.fromOffset(96, 96),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = parent,
		Children = { UIKit.Round() },
	})
	local stroke =
		UIKit.new("UIStroke", { Color = Theme.Colors.Yellow, Thickness = 5, Transparency = 0, Parent = circle })
	task.delay(delay, function()
		UIKit.Tween(circle, 0.8, { Size = UDim2.fromOffset(220, 220) })
		UIKit.Tween(stroke, 0.8, { Transparency = 1 })
	end)
	Debris:AddItem(circle, delay + 0.9)
end

local function setCelebrating(on: boolean)
	State.LocalPlayer:SetAttribute("PP_Celebrating", on) -- OnboardingController's phone tip steps aside
end

-- Game Mastery's new rank (owner: "this has to be incredible and make players feel like they
-- accomplished something"): a card in the rank's own colours with a turning rim, rays behind the
-- badge, and the badge forged in front of you: the rank before shakes, flashes white and the new one
-- bursts out with confetti and the crate's big reveal sound. The game's name, "GOLD RANK!" in the
-- rank's metal and a line for it ("A true pro!"); the climb with every rank, the new one lit; its
-- rewards one by one; the next goal and 🏆 MASTERY. DIAMOND and LEGEND get a halo and stay longer.
local MASTERY_H = 410
local function showMastery(celebration: Celebration)
	local rank = celebration.Rank or 1
	local before = math.max(0, rank - 1)
	local definition = GameDefinitions.Get(celebration.Game or "")
	local look = Mastery.Look(rank)
	local big = rank >= 4
	local reduced = State.ReducedEffects()
	local group = PartyKit.Group()
	PartyKit.SetPlaying(group, true)

	local holder = UIKit.new("Frame", {
		Name = "Celebration",
		AnchorPoint = if touch then Vector2.new(0.5, 0) else Vector2.new(0.5, 0.5),
		Position = if touch then UDim2.new(0.5, 0, 0, 4) else UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CARD_W, MASTERY_H),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UIKit.AutoScale(holder, if touch then nil else PC_BIAS)
	local card = UIKit.Panel({
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		CornerRadius = 26,
		ClipsDescendants = true, -- the rays, rings and confetti stay on the card
		ZIndex = 1,
		Parent = holder,
	}, PartyKit.Darker(look.Bottom, 0.25), Theme.Colors.PanelDark)
	card:SetAttribute("PP_Popup", true) -- a few seconds in the lobby; nothing in the stick's corner takes taps
	PartyKit.SpinBorder(
		card,
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, look.Top),
			ColorSequenceKeypoint.new(0.35, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.7, look.Bottom),
			ColorSequenceKeypoint.new(1, look.Top),
		}),
		5,
		group
	)

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		if closeCurrent == close then
			closeCurrent = nil
		end
		PartyKit.SetPlaying(group, false)
		holder:Destroy()
		setCelebrating(false)
		task.delay(0.4, CelebrationController.Pump)
	end
	closeCurrent = close
	setCelebrating(true)

	-- The badge, forged: rays behind, the rank before, a shake and a flash, then the new rank.
	local badgeCenter = UDim2.fromOffset(86, 80)
	PartyKit.Rays({
		Parent = card,
		Size = 320,
		Position = badgeCenter,
		Color = look.Top,
		Count = 10,
		ZIndex = 1,
		Group = group,
		Period = 14,
		Strength = if big then 0.6 else 0.45,
	})
	local forge = UIKit.new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = badgeCenter,
		Size = UDim2.fromOffset(124, 124),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = card,
	})
	local old = Mastery.Badge(before, 108, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 3,
		Parent = forge,
	})
	local function reveal()
		if closed then
			return
		end
		old:Destroy()
		local badge = Mastery.Badge(rank, 116, {
			Name = "Rank",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			ZIndex = 3,
			Parent = forge,
		})
		UIKit.PopIn(badge, 0.55)
		if big then
			PartyKit.Halo(badge, look.Top, 3, group)
		end
		local flash = UIKit.new("Frame", {
			Name = "Flash",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = badgeCenter,
			Size = UDim2.fromOffset(120, 120),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 5,
			Parent = card,
			Children = { UIKit.Round() },
		})
		UIKit.Tween(flash, 0.45, { Size = UDim2.fromOffset(300, 300), BackgroundTransparency = 1 })
		Debris:AddItem(flash, 0.5)
		ring(card, badgeCenter, 0)
		ring(card, badgeCenter, 0.2)
		PartyKit.Burst(card, badgeCenter, { look.Top, look.Bottom, Theme.Colors.Yellow }, 30, 260)
		AudioController.PlayOr("CrateTitle", "Victory")
	end
	if reduced then
		reveal()
	else
		-- (a shake, left and right, then the flash)
		for index, angle in { -10, 10, -12, 12, 0 } do
			task.delay(0.35 + index * 0.08, function()
				if old.Parent then
					UIKit.Tween(old, 0.07, { Rotation = angle })
				end
			end)
		end
		task.delay(0.85, reveal)
	end

	-- The words: the game, the rank in its metal, a line for it; the ✕ in the corner.
	label({
		Name = "Game",
		Text = if definition then string.upper(definition.Name) else "",
		Font = Theme.Fonts.Display,
		TextSize = 22,
		TextWrapped = false,
		TextColor3 = look.Top,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(166, 16),
		Size = UDim2.fromOffset(CARD_W - 166 - 80, 28),
		Parent = card,
		Children = { UIKit.TextStroke(0) },
	})
	local headline = label({
		Name = "Headline",
		Text = `{Mastery.Name(rank)} RANK!`,
		Font = Theme.Fonts.Display,
		TextSize = 48,
		TextWrapped = false,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(164, 42),
		Size = UDim2.fromOffset(CARD_W - 164 - 24, 58),
		Parent = card,
		Children = {
			UIKit.TextStroke(0),
			UIKit.new("UIGradient", { Color = Mastery.Gradient(rank), Rotation = 90 }),
		},
	})
	label({
		Name = "Tagline",
		Text = Mastery.Tagline(rank),
		Font = Theme.Fonts.Display,
		TextSize = 22,
		TextWrapped = false,
		TextColor3 = Theme.Colors.Yellow,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(166, 102),
		Size = UDim2.fromOffset(CARD_W - 166 - 24, 28),
		Parent = card,
		Children = { UIKit.TextStroke(0.1) },
	})
	UIKit.Button({
		Name = "Close",
		Text = "✕", -- (UI/Icons draws the X)
		TextSize = 30,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(if touch then Theme.Touch.Target else 56, if touch then Theme.Touch.Target else 56),
		CornerRadius = "round",
		ZIndex = 5,
		Parent = card,
	}, close, Theme.Colors.Red, Color3.fromRGB(190, 40, 60))

	-- The climb: every rank, the new one lit.
	local ladder = Mastery.Ladder(rank, 44, 34, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 146),
		ZIndex = 3,
		Parent = card,
	})
	UIKit.PopIn(ladder, 0.5)

	-- The rewards, revealed one by one.
	local row = UIKit.new("Frame", {
		Name = "Rewards",
		Position = UDim2.fromOffset(0, 208),
		Size = UDim2.new(1, 0, 0, CHIP_H),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = card,
		Children = { UIKit.List(Enum.FillDirection.Horizontal, CHIP_GAP, Enum.HorizontalAlignment.Center) },
	})
	local chips = {}
	if (celebration.Coins or 0) > 0 then
		table.insert(chips, coinChip(row, celebration.Coins, 1))
	end
	if (celebration.Keys or 0) > 0 then
		table.insert(chips, keyChip(row, celebration.Keys :: number, 2))
	end
	if (celebration.Crates or 0) > 0 then
		table.insert(chips, crateChip(row, celebration.Crates :: number, 3))
	end
	for index, chip in chips do
		local slot = UIKit.new("Frame", {
			Name = chip.Name .. "Slot",
			Size = chip.Size,
			LayoutOrder = chip.LayoutOrder,
			BackgroundTransparency = 1,
			ZIndex = chip.ZIndex,
			Parent = row,
		})
		chip.AnchorPoint = Vector2.new(0.5, 0.5)
		chip.Position = UDim2.fromScale(0.5, 0.5)
		chip.Parent = slot
		chip.Visible = false
		task.delay(1.1 + index * 0.18, function()
			if chip.Parent then
				chip.Visible = true
				UIKit.PopIn(chip, 0.35)
			end
		end)
	end

	-- The next goal (left) and 🏆 MASTERY (right half).
	local bottom = MASTERY_H - 14 - (if touch then Theme.Touch.Target else 56)
	local goal = label({
		Name = "NextGoal",
		Text = nextGoal(celebration),
		TextSize = Theme.Touch.MinText,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(20, bottom),
		Size = UDim2.fromOffset(BUTTONS_LEFT - 28, if touch then Theme.Touch.Target else 56),
		Parent = card,
	})
	goal:SetAttribute("PP_Lines", 2)
	UIKit.Button({
		Name = "SeeMore",
		Text = "🏆 MASTERY",
		TextSize = 22,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, bottom),
		Size = UDim2.fromOffset(176, if touch then Theme.Touch.Target else 56),
		CornerRadius = 18,
		ZIndex = 4,
		Parent = card,
	}, function()
		close()
		State.OpenScreen:Fire("Mastery") -- (the GOALS hub's tab: Controllers/MasteryController)
	end, Theme.Colors.Pink, PINK_DARK)

	-- Motion: the card pops, the headline's metal shimmers, confetti in the rank's colours.
	UIKit.PopIn(card, 0.4)
	UIKit.PopIn(headline, 0.5)
	local metal = headline:FindFirstChildOfClass("UIGradient")
	if metal and not reduced then
		PartyKit.Loop(metal, 2.4, { Rotation = 270 }, group, { Style = Enum.EasingStyle.Sine })
	end
	task.delay(if reduced then 0 else 0.85, function()
		if not closed then
			confetti(card, { look.Top, look.Bottom, Theme.Colors.Yellow, Color3.new(1, 1, 1) })
		end
	end)
	AudioController.Play("Victory")
	task.delay(SHOW_FOR + (if big then 3 else 1), close)
end

local function show(celebration: Celebration)
	if celebration.Kind == "Mastery" then
		showMastery(celebration)
		return
	end
	local isLevel = celebration.Kind == "LevelUp"
	local welcome = celebration.Kind == "Welcome"
	local items = {}
	for _, id in celebration.Items do
		local item = Cosmetics.Get(id)
		if item then
			table.insert(items, item)
		end
	end
	table.sort(items, better) -- the chips show the best first, and EQUIP ALL puts those on
	local level = celebration.Level or 1
	local look = Progression.Look(level)
	local newColor = isLevel and celebration.From ~= nil and look.Index > Progression.Look(celebration.From).Index

	-- Phones: top middle, under Roblox's top bar. PC: the middle of the screen.
	local holder = UIKit.new("Frame", {
		Name = "Celebration",
		AnchorPoint = if touch then Vector2.new(0.5, 0) else Vector2.new(0.5, 0.5),
		Position = if touch then UDim2.new(0.5, 0, 0, 4) else UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UIKit.AutoScale(holder, if touch then nil else PC_BIAS)
	local card = UIKit.Panel({
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		CornerRadius = 26,
		ClipsDescendants = true, -- the rings and confetti stay on the card
		ZIndex = 1,
		Parent = holder,
	}, Color3.fromRGB(96, 62, 190), Theme.Colors.PanelDark)
	card:SetAttribute("PP_Popup", true) -- a few seconds in the lobby; nothing in the stick's corner takes taps
	local rim = card:FindFirstChildOfClass("UIStroke") :: UIStroke
	rim.Color = if isLevel then look.Gradient.Keypoints[1].Value else Theme.Colors.Yellow
	rim.Thickness = 4
	rim.Transparency = 0

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		if closeCurrent == close then
			closeCurrent = nil
		end
		holder:Destroy()
		setCelebrating(false)
		task.delay(0.4, CelebrationController.Pump)
	end
	closeCurrent = close
	setCelebrating(true)

	-- Row 1: the badge, the headline and what happened; the ✕ in the corner.
	local badgeCenter = UDim2.fromOffset(18 + 48, 16 + 48)
	ring(card, badgeCenter, 0.05)
	ring(card, badgeCenter, 0.3)
	local badge = UIKit.new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = badgeCenter,
		Size = UDim2.fromOffset(96, 96),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 3,
		Parent = card,
		Children = { UIKit.Round(), UIKit.Stroke(nil, 4, 0.1) },
	})
	local badgeGradient = UIKit.new("UIGradient", {
		Color = if isLevel then look.Gradient else GOLD,
		Rotation = 90,
		Parent = badge,
	})
	label({
		Text = if isLevel then tostring(level) elseif welcome then "🎁" else (items[1] and items[1].Icon or "🏅"),
		Font = Theme.Fonts.Display,
		TextSize = if isLevel then (if level >= 100 then 40 else 50) else 46,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = badge,
		Children = { UIKit.TextStroke(0.1) },
	})
	local headline = label({
		Name = "Headline",
		Text = if isLevel then "LEVEL UP!" elseif welcome then "NEW REWARDS!" else "MILESTONE!",
		Font = Theme.Fonts.Display,
		TextSize = if welcome then 44 else 50,
		TextWrapped = false,
		TextColor3 = Theme.Colors.Yellow,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(130, 12),
		Size = UDim2.fromOffset(372, 58),
		Parent = card,
		Children = { UIKit.TextStroke(0) },
	})
	local subline
	if isLevel then
		subline = if newColor then `New name tag color: {look.Icon} {look.Name}!` else `You're level {level}!`
	elseif welcome then
		subline = "Your level and career earned these. They're yours!"
	else
		subline = if items[1] then `{items[1].Name} unlocked!` else "New reward unlocked!"
	end
	local sub = label({
		Name = "Subline",
		Text = subline,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(132, 70),
		Size = UDim2.fromOffset(370, 52),
		Parent = card,
		Children = { UIKit.TextStroke(0.2) },
	})
	sub:SetAttribute("PP_Lines", 2)
	UIKit.Button({
		Name = "Close",
		Text = "✕", -- (UI/Icons draws the X)
		TextSize = 30,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(if touch then Theme.Touch.Target else 56, if touch then Theme.Touch.Target else 56),
		CornerRadius = "round",
		ZIndex = 5,
		Parent = card,
	}, close, Theme.Colors.Red, Color3.fromRGB(190, 40, 60))

	-- Row 2: the rewards, revealed one by one.
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
	local coins = celebration.Coins or 0
	local goldCoins = celebration.GoldCoins or 0
	if coins > 0 then
		table.insert(chips, coinChip(row, coins, 1))
	end
	if goldCoins > 0 then
		table.insert(chips, goldCoinChip(row, goldCoins, 2))
	end
	local keys = celebration.Keys or 0
	if keys > 0 then
		table.insert(chips, keyChip(row, keys, 3))
	end
	-- As many item chips as fit beside the coins (3 less one per coin chip), the rest as "+2 more!"
	-- (every one is on the Rewards screen). At most 576 of the card's 600 units.
	local room = 3 - #chips
	for index, item in items do
		if index > room then
			table.insert(chips, moreChip(row, #items - room, 10))
			break
		end
		table.insert(chips, itemChip(row, item, 3 + index))
	end
	-- Each chip sits in a slot of its own size that is in the row from the start, so the row is
	-- laid out once and the chips pop in one by one without moving the others.
	for index, chip in chips do
		local slot = UIKit.new("Frame", {
			Name = chip.Name .. "Slot",
			Size = chip.Size,
			LayoutOrder = chip.LayoutOrder,
			BackgroundTransparency = 1,
			ZIndex = chip.ZIndex,
			Parent = row,
		})
		chip.AnchorPoint = Vector2.new(0.5, 0.5)
		chip.Position = UDim2.fromScale(0.5, 0.5)
		chip.Parent = slot
		chip.Visible = false
		task.delay(0.4 + index * 0.18, function()
			if chip.Parent then
				chip.Visible = true
				UIKit.PopIn(chip, 0.35)
			end
		end)
	end

	-- Row 3: the next goal (left), EQUIP and the Rewards screen (right half).
	local goal = label({
		Name = "NextGoal",
		Text = nextGoal(celebration),
		TextSize = Theme.Touch.MinText,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(20, BOTTOM_Y),
		Size = UDim2.fromOffset(BUTTONS_LEFT - 28, if touch then Theme.Touch.Target else 60),
		Parent = card,
	})
	goal:SetAttribute("PP_Lines", 2)
	local buttonHeight = if touch then Theme.Touch.Target else 60
	local buttons = UIKit.new("Frame", {
		Name = "Buttons",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, BOTTOM_Y),
		Size = UDim2.fromOffset(CARD_W - 16 - BUTTONS_LEFT, buttonHeight),
		BackgroundTransparency = 1,
		ZIndex = 3,
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
	-- EQUIP puts on what it unlocked (the best new item in each slot: a trail AND a title, say);
	-- an emote gets TRY IT instead. The server checks the player owns each one.
	local toEquip: { Cosmetics.Cosmetic } = {}
	local slotsTaken: { [string]: boolean } = {}
	local emote: Cosmetics.Cosmetic? = nil
	for _, item in items do
		if Cosmetics.IsEquipSlot(item.Slot) and not slotsTaken[item.Slot] then
			slotsTaken[item.Slot] = true
			table.insert(toEquip, item)
		elseif item.Slot == "Emote" and not emote then
			emote = item
		end
	end
	local function allEquipped(): boolean
		local profile = State.Profile
		for _, item in toEquip do
			if not profile or profile.Equipped[item.Slot] ~= item.Id then
				return false
			end
		end
		return true
	end
	local function paintDone(button: TextButton, text: string)
		button.Text = text
		local gradient = button:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Color = ColorSequence.new(Theme.Colors.Green, GREEN_DARK)
		end
	end
	if #toEquip > 0 then
		local done = allEquipped()
		local button
		button = UIKit.Button({
			Name = "Equip",
			Text = if done then "EQUIPPED" elseif #toEquip > 1 then "EQUIP ALL" else "EQUIP",
			TextSize = 20,
			Size = UDim2.fromOffset(130, buttonHeight),
			CornerRadius = 18,
			LayoutOrder = 1,
			ZIndex = 4,
			Parent = buttons,
		}, function()
			for _, item in toEquip do
				Remotes.Get("ShopEquip"):FireServer(item.Slot, item.Id)
			end
			paintDone(button, "EQUIPPED")
		end, if done then Theme.Colors.Green else Theme.Colors.Cyan, if done then GREEN_DARK else CYAN_DARK)
	elseif emote then
		local item = emote
		local button
		button = UIKit.Button({
			Name = "TryEmote",
			Text = "TRY IT!",
			TextSize = 20,
			Size = UDim2.fromOffset(130, buttonHeight),
			CornerRadius = 18,
			LayoutOrder = 1,
			ZIndex = 4,
			Parent = buttons,
		}, function()
			Remotes.Get("UseEmote"):FireServer(item.Id) -- road emotes are effects: the server plays it
			paintDone(button, `{item.Icon} AGAIN`)
		end, Theme.Colors.Cyan, CYAN_DARK)
	end
	UIKit.Button({
		Name = "SeeMore",
		Text = if isLevel or welcome then "⭐ ROAD" else "🏅 CAREER",
		TextSize = 22,
		Size = UDim2.fromOffset(146, buttonHeight),
		CornerRadius = 18,
		LayoutOrder = 2,
		ZIndex = 4,
		Parent = buttons,
	}, function()
		close()
		State.OpenScreen:Fire("Rewards", if isLevel or welcome then "Road" else "Career")
	end, Theme.Colors.Pink, PINK_DARK)

	-- Motion: the card and badge pop, confetti falls, a rainbow badge shimmers.
	UIKit.PopIn(card, 0.4)
	UIKit.PopIn(badge, 0.6)
	UIKit.PopIn(headline, 0.45)
	confetti(card)
	local shimmer = if isLevel
			and look.Rainbow
			and not State.ReducedEffects()
		then RunService.Heartbeat:Connect(function()
			badgeGradient.Rotation = (os.clock() * 90) % 360
		end)
		else nil
	holder.Destroying:Connect(function()
		if shimmer then
			shimmer:Disconnect()
		end
	end)
	AudioController.Play("Victory")
	task.delay(SHOW_FOR, close)
end

-- Shows the next celebration if it's a calm moment (several waiting make one).
function CelebrationController.Pump()
	local phase = GameState.Get("Phase") or "Waiting"
	if closeCurrent or windowOpen or #queue == 0 or not CALM[phase] then
		return
	end
	if phase == "Intermission" and GameState.TimeLeft() < MIN_SHOW then
		return -- the vote is about to start: after the next round instead (Cleanup pumps again)
	end
	if phase == "Cleanup" and (GameState.Get("Replay") or "") ~= "" then
		return -- the same game again straight away: no lobby time to show it in
	end
	if not State.Profile then
		return -- its "Next up" comes from the profile: shown once the first one arrives
	end
	-- A new Game Mastery rank gets its own card, after the round's level-up or milestone card.
	local regular, ranks = {}, {}
	for _, entry in queue do
		table.insert(if entry.Kind == "Mastery" then ranks else regular, entry)
	end
	table.clear(queue)
	if #regular > 0 then
		for _, entry in ranks do
			table.insert(queue, entry) -- (next, once this one closes)
		end
		show(merge(regular))
	else
		show(mergeMastery(ranks))
	end
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

-- A new Game Mastery rank over a player's head, for everyone in the lobby (owner: "make players feel
-- like they accomplished something"): a pill in the rank's colours with its badge, "GOLD RANK!" and
-- the game, rising for a few seconds like the "Lv 10!".
local function masteryPop(character: Instance, rank: number, gameId: string)
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - head.Position).Magnitude > 160 then
		return -- too far away to see
	end
	local definition = GameDefinitions.Get(gameId)
	local reduced = State.ReducedEffects()
	local board = Instance.new("BillboardGui")
	board.Name = "PP_MasteryPop"
	board.Adornee = head
	board.Size = UDim2.fromOffset(230, 64)
	board.StudsOffset = Vector3.new(0, 5, 0)
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
			UIKit.new("UIGradient", { Color = Mastery.Gradient(rank), Rotation = 90 }),
			UIKit.new("UIStroke", { Color = Theme.Colors.Ink, Thickness = 3 }),
		},
	})
	Mastery.Badge(rank, 54, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 5, 0.5, 0), Parent = pill })
	local words = {}
	table.insert(
		words,
		UIKit.Label({
			Text = `{Mastery.Name(rank)} RANK!`,
			Font = Theme.Fonts.Display,
			TextScaled = true,
			Position = UDim2.fromOffset(64, 4),
			Size = UDim2.new(1, -74, 0, 32),
			Parent = pill,
			Children = { UIKit.TextStroke(0) },
		})
	)
	table.insert(
		words,
		UIKit.Label({
			Text = if definition then string.upper(definition.Name) else "",
			Font = Theme.Fonts.Display,
			TextScaled = true,
			Position = UDim2.fromOffset(64, 36),
			Size = UDim2.new(1, -74, 0, 22),
			Parent = pill,
			Children = { UIKit.TextStroke(0.1) },
		})
	)
	board.Parent = head
	if not reduced then
		UIKit.PopIn(pill, 0.5)
		UIKit.Tween(board, 3.6, { StudsOffset = Vector3.new(0, 6.6, 0) }, Enum.EasingStyle.Sine)
	end
	task.delay(3, function()
		if board.Parent then
			UIKit.Tween(pill, 0.6, { BackgroundTransparency = 1 })
			for _, word in words do
				UIKit.Tween(word, 0.6, { TextTransparency = 1 })
			end
			for _, item in pill:GetDescendants() do
				if item:IsA("UIStroke") then
					UIKit.Tween(item, 0.6, { Transparency = 1 })
				elseif item:IsA("ImageLabel") then
					UIKit.Tween(item, 0.6, { ImageTransparency = 1 })
				elseif item:IsA("Frame") then
					UIKit.Tween(item, 0.6, { BackgroundTransparency = 1 })
				end
			end
		end
	end)
	Debris:AddItem(board, 3.8)
end

function CelebrationController.Start(context)
	touch = UIKit.IsTouch()
	-- Their own layer: above the HUD and the toasts, under the windows (10), which close it anyway.
	gui = UIKit.new("ScreenGui", {
		Name = "PartyPanicCelebrate",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 9,
		Parent = context.Hud.Parent,
	})

	Remotes.Get("Celebrate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or type(payload.Kind) ~= "string" then
			return
		end
		table.insert(queue, {
			Kind = payload.Kind,
			Game = if type(payload.Game) == "string" then payload.Game else nil,
			Rank = tonumber(payload.Rank),
			Crates = tonumber(payload.Crates),
			Level = tonumber(payload.Level),
			From = tonumber(payload.From),
			Coins = tonumber(payload.Coins) or 0,
			GoldCoins = tonumber(payload.GoldCoins),
			Keys = tonumber(payload.Keys),
			Items = if type(payload.Items) == "table" then payload.Items else {},
		})
		CelebrationController.Pump()
	end)
	Remotes.Get("LevelPop").OnClientEvent:Connect(function(character, level)
		if typeof(character) == "Instance" and type(level) == "number" then
			popOver(character, level)
		end
	end)
	Remotes.Get("MasteryPop").OnClientEvent:Connect(function(character, rank, gameId)
		if typeof(character) == "Instance" and type(rank) == "number" and type(gameId) == "string" then
			masteryPop(character, rank, gameId)
		end
	end)
	GameState.Changed("Phase", function(phase)
		if CALM[phase] then
			CelebrationController.Pump()
		else
			CelebrationController.Dismiss() -- the vote or the round: out of the way
		end
	end)
	-- The lobby's end time (MIN_SHOW) can land just after its phase does: look again when it does.
	GameState.Changed("PhaseEndsAt", function()
		CelebrationController.Pump()
	end)
	State.ProfileChanged:Connect(function()
		if #queue > 0 then
			CelebrationController.Pump()
		end
	end)
	-- A window opening (shop, quests, the Rewards screen...) takes over; once it closes, anything
	-- still waiting shows.
	Modal.AnyOpenChanged:Connect(function(open)
		windowOpen = open
		if open then
			CelebrationController.Dismiss()
		else
			task.delay(0.4, CelebrationController.Pump)
		end
	end)
end

return CelebrationController
