-- Your party, always in view (owner: "Also make the party system insane. I want it to look super
-- epic."). Three things, drawn with UI/PartyKit in the party's colour (Client/PartyView):
--   * The squad bar, on the lobby HUD while you're in a party: the party's emblem on a medallion,
--     everyone's face in a glowing ring of the party's colour (the leader wears the 👑) and the streak
--     (🔥 rounds in a row together) once it's 2, on a dark pill with a rim of colours turning round
--     it, a neon glow breathing round that and a shine sweeping over now and then. A tap opens the
--     PARTY window. Phones: compact, low in the middle of the screen (like the toasts, which sit
--     above it: NotificationController; owner, on layout A: "the bottom not being centrally located"),
--     clear of the chip row and the menu column up top and of the ☰ in the top bar row. The vote
--     cards take that spot while they're up (VoteController's row at the bottom middle), so the bar
--     steps aside for the vote, as the chip row does on phones; the party still shows in the world
--     meanwhile (PartyWorldController), and the bar's back in the next lobby. PC: on the
--     left under the profile chip, its coins and the first-join tip's room, above the vote cards' row
--     and left of the invite card; the party's name and the streak over the faces.
--   * PARTY UP! When someone joins (the server's ("PartyUp", userId, name) on the Party remote),
--     everyone in the party gets a banner in the party's colours: a sunburst turning behind the
--     newcomer's face, PARTY UP! in gold between two 🎉, twinkles, a rim of colours turning round it,
--     confetti on screen and over the newcomer in the world, and the fanfare; then the newcomer's
--     face flies into the squad bar (or into their card on the PARTY window when it's open). It waits
--     for the lobby (and for a level-up card to finish, up to CALM_WAIT seconds), goes at once if a
--     round starts, and the chips step aside meanwhile, as for a level-up (PP_Celebrating).
--   * The SQUAD card: in a team game (or a role game), while the rules card is up, a card slides in on
--     the left: the party's emblem and SQUAD, your team as a chip of its colour, and the party mates
--     the round put on your team, faces and names, for SQUAD_TIME seconds. (Everyone is frozen then,
--     so on phones it can use the left side.) It never covers the rules card: the room left of it is
--     measured where the rules card really is on this screen, and a screen too narrow for the full
--     card (narrower than an iPhone SE) gets a compact one, faces only; one too narrow even for that
--     gets none.
-- Bots are never in parties: nothing here shows one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameState = require(Shared.GameState)
local PartyStreak = require(Shared.Logic.PartyStreak)
local Remotes = require(Shared.Remotes)
local Teams = require(Shared.Teams)

local AudioController = require(script.Parent.AudioController)
local EffectsController = require(script.Parent.EffectsController)
local PartyController = require(script.Parent.PartyController)
local PartyView = require(script.Parent.Parent.PartyView)
local State = require(script.Parent.Parent.State)
local PartyKit = require(script.Parent.Parent.UI.PartyKit)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local SquadController = {}

type Moment = { UserId: number, Name: string, At: number }
type Slot = { Holder: Frame, Land: UIScale, Face: PartyKit.Face }

local LOBBY = { Waiting = true, Intermission = true, Voting = true, Cleanup = true }
local WHITE = Color3.new(1, 1, 1)
local MAX = 4 -- PartyLogic.MaxSize: the most faces a bar shows

-- The squad bar, in scaled units (phones get 0.62 points a unit: 84 is 52 pt).
local BAR = {
	Touch = { Height = 84, Medallion = 60, Face = 56, Gap = 10, Pad = 14, Streak = Vector2.new(96, 56) },
	Pc = { Height = 96, Medallion = 70, Face = 46, Gap = 7, Pad = 12, Streak = Vector2.new(64, 28) },
}
-- PC: under the profile chip, its coins and the first-join tip's room, and above the vote cards'
-- row; no wider than PC_ROOM, so it ends left of the invite card in the middle of the screen.
local PC_BAR_Y = 290
local PC_NAME = 22 -- the party's name over the faces (smaller for a long one, down to PC_NAME_MIN)
local PC_NAME_MIN = 16
local PC_ROOM = 344

-- The PARTY UP! banner and the SQUAD card.
local BANNER = Vector2.new(680, 176)
local BANNER_FACE = 128
local BANNER_TIME = 3.2 -- seconds it's up
local FLY_AT = 1.3 -- seconds in, the newcomer's face flies to the squad
local FLY_TIME = 0.6
local CALM_WAIT = 10 -- seconds a moment waits for a level-up card to finish before showing anyway
local MOMENT_AGE = 120 -- a moment older than this (a long round in between) isn't shown any more
local SQUAD_TIME = 5.5
local SQUAD_GAP = 20 -- scaled units kept clear between the SQUAD card and the rules card
-- The SQUAD card (scaled units), on the left: phones under the profile pill, PC under the profile
-- chip and its coins, keys and crates (HudController.ProfileHeight). Width is the full card (it fits beside the rules card from a 667-point iPhone
-- SE up, and on PC from about 800 pixels wide); Compact is the faces-only one for narrower screens.
local SQUAD = {
	Touch = {
		Width = 188,
		Compact = 100,
		Top = 106,
		Medallion = 50,
		Title = 30,
		Chip = 30,
		ChipText = 20,
		Row = 62,
		Face = 50,
		First = 108,
	},
	Pc = {
		Width = 280,
		Compact = 112,
		Top = 204,
		Medallion = 58,
		Title = 34,
		Chip = 32,
		ChipText = 21,
		Row = 68,
		Face = 56,
		First = 116,
	},
}

local touch = false
local player = Players.LocalPlayer
local hud: ScreenGui
local layer: ScreenGui -- the moments' own layer, over the windows
local bar: TextButton
local barScale: UIScale
local barGlow: UIStroke
local medallion: PartyKit.Medallion
local partyName: TextLabel?
local streakPill: Frame
local streakTint: UIGradient
local streakText: TextLabel
local barLoops = PartyKit.Group()
local slots: { Slot } = {}
local slotFor: { [number]: Slot } = {} -- UserId -> the slot showing them
local landing: { [number]: number } = {} -- UserId -> until when their slot waits for their face to land
local barShown = false
local voteRow: GuiObject? = nil -- VoteController's row of vote cards
local moments: { Moment } = {}
local playing = false
local squadCard: Frame? = nil
local squadCompact = false -- whether it's the compact one
local squadWatch: RBXScriptConnection? = nil -- the screen changing under it
local squadRound = -1 -- the round whose SQUAD card has been shown

local function sizes(): any
	return if touch then BAR.Touch else BAR.Pc
end

local function lobbyUp(): boolean
	local phase = GameState.Get("Phase") or "Waiting"
	return LOBBY[phase] == true and not (phase == "Cleanup" and (GameState.Get("Replay") or "") ~= "")
end

local function playerById(userId: number): Player?
	for _, other in Players:GetPlayers() do
		if other.UserId == userId then
			return other
		end
	end
	return nil
end

-- The squad bar ----------------------------------------------------------------------------------------

local function buildSlot(index: number): Slot
	local s = sizes()
	local holder = UIKit.new("Frame", {
		Name = `Member{index}`,
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(s.Face, s.Face),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 3,
		Parent = bar,
	})
	-- One glow ring is plenty this small; it breathes. (The holder keeps the slot's place on the bar
	-- for a newcomer's face to fly to; the face in it pops in when it lands.)
	local face = PartyKit.Face({ Size = s.Face, Parent = holder, ZIndex = 3, Group = barLoops, HaloLayers = 1 })
	local land = UIKit.new("UIScale", { Name = "Land", Scale = 1, Parent = face.Frame })
	return { Holder = holder, Land = land, Face = face }
end

local function buildBar(context)
	local s = sizes()
	local holder = UIKit.new("Frame", {
		Name = "SquadBar",
		AnchorPoint = if touch then Vector2.new(0.5, 1) else Vector2.zero,
		Position = if touch then UDim2.new(0.5, 0, 1, -8) else UDim2.fromOffset(16, 12),
		Size = if touch then UDim2.fromOffset(460, s.Height + 30) else UDim2.fromOffset(440, PC_BAR_Y + s.Height + 30),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = context.Hud,
	})
	UIKit.AutoScale(holder)
	bar = UIKit.new("TextButton", {
		Name = "Bar",
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = if touch then Vector2.new(0.5, 1) else Vector2.zero,
		Position = if touch then UDim2.fromScale(0.5, 1) else UDim2.fromOffset(0, PC_BAR_Y),
		Size = UDim2.fromOffset(300, s.Height),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Parent = holder,
		Children = {
			UIKit.Corner(s.Height / 2),
			UIKit.Gradient(Theme.Colors.PanelLight, Theme.Colors.PanelDark),
		},
	})
	barScale = UIKit.new("UIScale", { Name = "PopScale", Scale = 1, Parent = bar }) -- (UIKit.PopIn's too)
	bar.MouseButton1Down:Connect(function()
		UIKit.Tween(barScale, 0.06, { Scale = 0.95 })
	end)
	bar.MouseButton1Up:Connect(function()
		UIKit.Tween(barScale, 0.12, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	bar.MouseLeave:Connect(function()
		UIKit.Tween(barScale, 0.12, { Scale = 1 })
	end)
	bar.Activated:Connect(function()
		AudioController.Play("Click")
		pcall(PartyController.Open)
	end)
	-- The rim turns through the party's colours, a neon glow breathes round it, and a shine sweeps
	-- over now and then.
	PartyKit.SpinBorder(bar, PartyKit.RimColors(Theme.Colors.Cyan), 4, barLoops)
	barGlow = PartyKit.Glow(bar, Theme.Colors.Cyan, 7, barLoops)
	PartyKit.Shine(bar, barLoops, { ZIndex = 2, Period = 4, Strength = 0.3 })
	medallion = PartyKit.Medallion({
		Size = s.Medallion,
		Parent = bar,
		Position = UDim2.new(0, s.Pad + s.Medallion / 2, 0.5, 0),
		ZIndex = 4,
		Halo = false,
	})
	if not touch then
		partyName = UIKit.Label({
			Name = "PartyName",
			Text = "",
			Font = Theme.Fonts.Display,
			TextSize = PC_NAME,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(s.Pad + s.Medallion + 12, 8),
			Size = UDim2.fromOffset(200, 28),
			ZIndex = 4,
			Parent = bar,
			Children = { UIKit.TextStroke(0.15) },
		})
	end
	-- The streak: at the bar's end on phones, after the party's name on PC.
	streakPill = UIKit.new("Frame", {
		Name = "Streak",
		AnchorPoint = if touch then Vector2.new(1, 0.5) else Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(s.Streak.X, s.Streak.Y),
		BackgroundColor3 = WHITE,
		Visible = false,
		ZIndex = 4,
		Parent = bar,
		Children = { UIKit.Round(), UIKit.Stroke(WHITE, 2, 0.15) },
	})
	streakTint = UIKit.new("UIGradient", { Rotation = 90, Parent = streakPill })
	streakText = UIKit.Label({
		Name = "Text",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 28 else 20,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = streakPill,
		Children = { UIKit.TextStroke(0.1) },
	})
	for index = 1, MAX do
		slots[index] = buildSlot(index)
	end
end

local function holderOf(): Frame
	return bar.Parent :: Frame
end

-- Lays the bar out for its party: the medallion, a face per member (the leader first), the streak.
local function layoutBar()
	local s = sizes()
	local mine = PartyView.Mine()
	local members = PartyView.Members(mine)
	local info = PartyView.Info(mine)
	PartyKit.SetMedallion(medallion, info.Color, info.Emblem)
	local rim = bar:FindFirstChildOfClass("UIStroke")
	local spin = rim and rim:FindFirstChild("Spin") :: UIGradient?
	if spin then
		spin.Color = PartyKit.RimColors(info.Color)
	end
	local tint = bar:FindFirstChildOfClass("UIGradient")
	if tint then
		tint.Color = ColorSequence.new(PartyKit.Darker(info.Color, 0.45), Theme.Colors.PanelDark)
	end
	barGlow.Color = info.Color
	local faceTop = if touch then s.Height / 2 else 8 + 28 + 6 + s.Face / 2 -- (PC: under the name; the 👑 clears it)
	local x = s.Pad + s.Medallion + 12
	local firstFace = x
	table.clear(slotFor)
	for index, slot in slots do
		local member = members[index]
		slot.Holder.Visible = member ~= nil
		if member then
			slot.Holder.Position = UDim2.fromOffset(x, faceTop)
			x += s.Face + s.Gap
			PartyKit.SetFace(slot.Face, member, info.Color, PartyView.SeatOf(member) == 1, nil)
			slotFor[member.UserId] = slot
			-- A newcomer's face is still on its way (PARTY UP!): their slot waits, empty.
			local waiting = (landing[member.UserId] or 0) > os.clock()
			slot.Face.Frame.Visible = not waiting
		end
	end
	local facesEnd = x - s.Gap
	-- The streak, from Warm on (a streak of 2).
	local tier = PartyStreak.Tier(info.Streak)
	streakPill.Visible = tier > 0
	if tier > 0 then
		streakText.Text = `🔥{info.Streak}`
		streakTint.Color = PartyKit.FlameColors(tier)
	end
	local width = facesEnd
	if partyName then
		-- PC: the name (smaller when it's long) and the streak after it, all within PC_ROOM.
		local streakRoom = if tier > 0 then 8 + s.Streak.X else 0
		local room = PC_ROOM - s.Pad - firstFace - streakRoom
		partyName.Text = string.upper(info.Name)
		local textSize = PC_NAME
		local nameWidth = UIKit.TextWidth(partyName.Text, textSize, Theme.Fonts.Display)
		while nameWidth > room and textSize > PC_NAME_MIN do
			textSize -= 1
			nameWidth = UIKit.TextWidth(partyName.Text, textSize, Theme.Fonts.Display)
		end
		partyName.TextSize = textSize
		partyName.Size = UDim2.fromOffset(math.ceil(nameWidth) + 4, 28)
		streakPill.Position = UDim2.fromOffset(firstFace + math.ceil(nameWidth) + 12, 8 + 14)
		width = math.max(width, firstFace + math.ceil(nameWidth) + streakRoom + 4)
	elseif tier > 0 then
		width += 12 + s.Streak.X
		streakPill.Position = UDim2.new(0, width, 0.5, 0)
	end
	bar.Size = UDim2.fromOffset(width + s.Pad, s.Height)
end

local function refreshBar()
	local mine = PartyView.Mine()
	local members = PartyView.Members(mine)
	local voting = touch and voteRow ~= nil and voteRow.Visible -- (phones: the vote cards are in its spot)
	local wanted = mine ~= nil
		and #members >= 2
		and lobbyUp()
		and not voting
		and hud:GetAttribute("PP_TipsAside") ~= true -- a lobby game has the screen (Skee-Ball)
	local holder = holderOf()
	if wanted then
		layoutBar()
	end
	if wanted and not barShown then
		holder.Visible = true
		UIKit.PopIn(bar, 0.35)
	end
	holder.Visible = wanted
	barShown = wanted
	PartyKit.SetPlaying(barLoops, wanted)
end

-- The PARTY UP! moment ---------------------------------------------------------------------------------

-- An expanding ring behind the face (like a level-up's).
local function ring(parent: Instance, center: UDim2, color: Color3, delay: number, from: number, to: number)
	local circle = UIKit.new("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = center,
		Size = UDim2.fromOffset(from, from),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = parent,
		Children = { UIKit.Round() },
	})
	local stroke = UIKit.new("UIStroke", { Color = color, Thickness = 6, Transparency = 0, Parent = circle })
	task.delay(delay, function()
		UIKit.Tween(circle, 0.8, { Size = UDim2.fromOffset(to, to) })
		UIKit.Tween(stroke, 0.8, { Transparency = 1 })
		task.delay(0.85, function()
			circle:Destroy()
		end)
	end)
end

-- Where the newcomer's face goes: their card on the open PARTY window, else their squad bar slot.
local function landingSpot(userId: number): (GuiObject?, Slot?)
	local ok, windowFace = pcall(PartyController.FaceOf, userId)
	if ok and windowFace then
		return windowFace, nil
	end
	local slot = slotFor[userId]
	if slot and barShown then
		return slot.Holder, slot
	end
	return nil, nil
end

-- The newcomer's face flies from the banner to `target`, which pops as it lands.
local function fly(from: Frame, target: GuiObject, slot: Slot?, who: Player, color: Color3)
	local origin = layer.AbsolutePosition
	local startAt, startSize = from.AbsolutePosition - origin, from.AbsoluteSize
	local goalAt, goalSize = target.AbsolutePosition - origin, target.AbsoluteSize
	if goalSize.X < 2 then
		return
	end
	local hideTarget = slot == nil and target.Visible -- the window's card: hidden till it lands
	if hideTarget then
		target.Visible = false
	end
	local flier = PartyKit.Face({
		Size = startSize.X,
		Parent = layer,
		Position = UDim2.fromOffset(startAt.X, startAt.Y),
		Halo = false,
		ZIndex = 60,
	})
	PartyKit.SetFace(flier, who, color, false, nil)
	-- Up and out a little, then down into place.
	local lift = UDim2.fromOffset((startAt.X + goalAt.X) / 2, math.min(startAt.Y, goalAt.Y) - startSize.Y * 0.5)
	UIKit.Tween(flier.Frame, FLY_TIME * 0.4, { Position = lift }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	task.delay(FLY_TIME * 0.4, function()
		UIKit.Tween(flier.Frame, FLY_TIME * 0.6, {
			Position = UDim2.fromOffset(goalAt.X, goalAt.Y),
			Size = UDim2.fromOffset(goalSize.X, goalSize.Y),
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end)
	task.delay(FLY_TIME, function()
		flier.Frame:Destroy()
		landing[who.UserId] = nil
		if slot and slotFor[who.UserId] == slot then
			slot.Face.Frame.Visible = true
			slot.Land.Scale = 0.6
			UIKit.Tween(slot.Land, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		elseif target.Parent then
			target.Visible = true
			UIKit.PopIn(target, 0.35)
		end
		-- A flash where it landed.
		local center = UDim2.fromOffset(goalAt.X + goalSize.X / 2, goalAt.Y + goalSize.Y / 2)
		ring(layer, center, color, 0, goalSize.X, goalSize.X * 2.2)
		PartyKit.Burst(layer, center, { color, WHITE }, if touch then 10 else 14, goalSize.X * 1.6)
	end)
end

local function setCelebrating(on: boolean): boolean
	local was = player:GetAttribute("PP_Celebrating") == true
	if on and not was then
		player:SetAttribute("PP_Celebrating", true) -- on phones the chips and the tip step aside
		return true
	elseif not on then
		player:SetAttribute("PP_Celebrating", false)
	end
	return false
end

local function showPartyUp(moment: Moment)
	local mine = PartyView.Mine()
	local who = playerById(moment.UserId)
	if not mine or not who or PartyView.PartyOf(who) ~= mine then
		landing[moment.UserId] = nil
		return -- they (or I) moved on meanwhile
	end
	local info = PartyView.Info(mine)
	local color = info.Color
	local itsMe = who == player
	local owned = setCelebrating(true)

	local holder = UIKit.new("Frame", {
		Name = "PartyUp",
		AnchorPoint = Vector2.new(0.5, if touch then 0 else 0.5),
		Position = if touch then UDim2.new(0.5, 0, 0, 2) else UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(BANNER.X, BANNER.Y),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	holder:SetAttribute("PP_Popup", true) -- a few seconds; nothing on it takes taps
	UIKit.AutoScale(holder)
	local pop = UIKit.new("Frame", {
		Name = "Pop",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	local loops = PartyKit.Group()
	local faceCenter = UDim2.fromOffset(64 + 10, 30 + (BANNER.Y - 44) / 2)
	-- A sunburst behind the newcomer's face, and a shadow under the ribbon.
	PartyKit.Rays({
		Parent = pop,
		Size = BANNER_FACE * 2.6,
		Position = faceCenter,
		Color = PartyKit.Lighter(color, 0.6),
		Count = 9,
		ZIndex = 1,
		Group = loops,
		Period = 6,
		Strength = 0.7,
	})
	UIKit.new("Frame", {
		Name = "Shadow",
		Position = UDim2.fromOffset(64, 30 + 8),
		Size = UDim2.fromOffset(BANNER.X - 64, BANNER.Y - 44),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.6,
		ZIndex = 2,
		Parent = pop,
		Children = { UIKit.Corner(30) },
	})
	local ribbon = UIKit.Panel({
		Name = "Ribbon",
		Position = UDim2.fromOffset(64, 30),
		Size = UDim2.fromOffset(BANNER.X - 64, BANNER.Y - 44),
		CornerRadius = 30,
		ZIndex = 2,
		Parent = pop,
	}, PartyKit.Lighter(color, 0.1), PartyKit.Darker(color, 0.45))
	PartyKit.SpinBorder(ribbon, PartyKit.RimColors(color), 6, loops)
	PartyKit.Shine(ribbon, loops, { ZIndex = 2, Period = 0.6, Strength = 0.45 })
	ring(pop, faceCenter, WHITE, 0.05, BANNER_FACE, BANNER_FACE * 2.4)
	ring(pop, faceCenter, color, 0.3, BANNER_FACE, BANNER_FACE * 2.8)
	local face = PartyKit.Face({
		Size = BANNER_FACE,
		Parent = pop,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = faceCenter,
		ZIndex = 6,
		Group = loops,
	})
	PartyKit.SetFace(face, who, color, PartyView.SeatOf(who) == 1, nil)
	local textLeft = 64 + 10 + BANNER_FACE / 2 + 16
	-- 🎉 PARTY UP! 🎉: the words in gold, the poppers either side bobbing.
	local titleSize = 56
	local titleWidth = math.ceil(UIKit.TextWidth("PARTY UP!", titleSize, Theme.Fonts.Display)) + 8
	local titleRow = UIKit.new("Frame", {
		Name = "TitleRow",
		Position = UDim2.fromOffset(textLeft, 30),
		Size = UDim2.new(1, -(textLeft + 14), 0, 70),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = pop,
		Children = {
			UIKit.List(
				Enum.FillDirection.Horizontal,
				6,
				Enum.HorizontalAlignment.Center,
				Enum.VerticalAlignment.Center
			),
		},
	})
	local title = UIKit.Label({
		Name = "Title",
		Text = "PARTY UP!",
		Font = Theme.Fonts.Display,
		TextSize = titleSize,
		TextWrapped = false,
		Size = UDim2.fromOffset(titleWidth, 70),
		LayoutOrder = 2,
		ZIndex = 5,
		Parent = titleRow,
		Children = {
			UIKit.new("UIStroke", { Color = Color3.fromRGB(70, 20, 60), Thickness = 4, Transparency = 0 }),
			UIKit.new("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, WHITE),
					ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 236, 120)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 160, 40)),
				}),
			}),
		},
	})
	title:SetAttribute("PP_Lines", 1)
	for order, side in { 1, 3 } do
		local popper = UIKit.Label({
			Name = `Popper{order}`,
			Text = "🎉",
			TextSize = 46,
			TextWrapped = false,
			Size = UDim2.fromOffset(58, 70),
			LayoutOrder = side,
			Rotation = if side == 1 then -12 else 12,
			ZIndex = 5,
			Parent = titleRow,
		})
		PartyKit.Loop(popper, 0.35, { Rotation = if side == 1 then 10 else -10 }, loops)
	end
	-- Twinkles round the ribbon.
	for index, spot in
		{
			Vector2.new(BANNER.X - 40, 26),
			Vector2.new(textLeft + 10, BANNER.Y - 18),
			Vector2.new(BANNER.X - 120, BANNER.Y - 12),
		}
	do
		local twinkle = UIKit.Label({
			Name = `Twinkle{index}`,
			Text = "✨",
			TextSize = 30,
			TextWrapped = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(spot.X, spot.Y),
			Size = UDim2.fromOffset(36, 36),
			ZIndex = 6,
			Parent = pop,
		})
		local scale = UIKit.new("UIScale", { Scale = 0.5, Parent = twinkle })
		PartyKit.Loop(scale, 0.45 + 0.15 * index, { Scale = 1.15 }, loops)
	end
	local whose = `{info.Emblem} {string.upper(info.Name)}`
	local line = UIKit.Label({
		Name = "Line",
		Text = if itsMe then `You joined {whose}!` else `{who.DisplayName} joined {whose}!`,
		Font = Theme.Fonts.Display,
		TextSize = 24,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(textLeft, 100),
		Size = UDim2.new(1, -(textLeft + 14), 0, 32),
		ZIndex = 5,
		Parent = pop,
		Children = { UIKit.TextStroke(0.1) },
	})
	line:SetAttribute("PP_TruncateOk", true) -- a long name may end in "..."
	UIKit.PopIn(pop, 0.45)
	PartyKit.Burst(pop, UDim2.fromOffset(BANNER.X / 2, BANNER.Y / 2), { color, WHITE }, 34, 320)
	AudioController.Play("Victory")
	-- Confetti in the world too, over the newcomer.
	local character = who.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		EffectsController.Play("Confetti", root.Position + Vector3.new(0, 3, 0), { color, WHITE, Theme.Colors.Yellow })
	end

	-- Up for BANNER_TIME, the newcomer's face flying off to the squad FLY_AT in; gone at once if the
	-- lobby goes (the round's rules card is next).
	local started = os.clock()
	local flown = false
	while os.clock() - started < BANNER_TIME and lobbyUp() do
		if not flown and os.clock() - started >= FLY_AT then
			flown = true
			local target, slot = landingSpot(who.UserId)
			if target then
				fly(face.Frame, target, slot, who, color)
				face.Frame.Visible = false
			else
				landing[who.UserId] = nil
				refreshBar()
			end
		end
		task.wait(0.05)
	end
	local scale = pop:FindFirstChild("PopScale") :: UIScale?
	if scale and lobbyUp() then
		UIKit.Tween(scale, 0.25, { Scale = 0.05 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.wait(0.27)
	end
	holder:Destroy()
	if owned then
		setCelebrating(false)
	end
	task.wait(0.4)
end

-- Plays the moments one at a time, each when the lobby's up and calm.
local function pump()
	if playing then
		return
	end
	playing = true
	task.spawn(function()
		while #moments > 0 do
			local moment = moments[1]
			local waitedFrom = os.clock()
			while
				not lobbyUp()
				or (player:GetAttribute("PP_Celebrating") == true and os.clock() - waitedFrom < CALM_WAIT)
			do
				task.wait(0.25)
				if os.clock() - moment.At > MOMENT_AGE then
					break
				end
			end
			table.remove(moments, 1)
			if os.clock() - moment.At <= MOMENT_AGE then
				local ok, err = pcall(showPartyUp, moment)
				if not ok then
					warn(`[SquadController] the PARTY UP! moment failed: {err}`)
				end
			end
			-- However it went, their slot shows them now.
			landing[moment.UserId] = nil
			refreshBar()
		end
		playing = false
	end)
end

local function onServer(kind: any, userId: any, name: any)
	if kind ~= "PartyUp" or type(userId) ~= "number" or userId ~= userId or type(name) ~= "string" then
		return
	end
	landing[userId] = os.clock() + CALM_WAIT + MOMENT_AGE
	table.insert(moments, { UserId = userId, Name = name, At = os.clock() })
	refreshBar()
	pump()
end

-- The SQUAD card ---------------------------------------------------------------------------------------

-- My party mates the round put on my team (or my side), the leader first.
local function squadMates(): ({ Player }, string?)
	local team = player:GetAttribute("PP_Team")
	if type(team) ~= "string" or team == "" or not State.InRound() then
		return {}, nil
	end
	local mates = {}
	for _, member in PartyView.Members(PartyView.Mine()) do
		if
			member ~= player
			and member:GetAttribute("PP_InRound") == true
			and member:GetAttribute("PP_Team") == team
		then
			table.insert(mates, member)
		end
	end
	return mates, team
end

-- The SQUAD card's room on this screen, in scaled units: from its holder's left edge (`left` pixels
-- into the HUD) to the rules card's, less SQUAD_GAP. Measured where the rules card really is
-- (RoundController's Rules in the middle of the screen; on phones the Card inside it), so it holds on
-- any screen. Nil without a rules card.
local function roomBesideRules(left: number): number?
	local rules = hud:FindFirstChild("Rules")
	if not (rules and rules:IsA("GuiObject")) then
		return nil
	end
	local card = rules:FindFirstChild("Card")
	local edge = if card and card:IsA("GuiObject") then card.AbsolutePosition.X else rules.AbsolutePosition.X
	return (edge - (hud.AbsolutePosition.X + left)) / UIKit.CurrentScale() - SQUAD_GAP
end

local function hideSquad()
	local cardFrame = squadCard
	squadCard = nil
	if squadWatch then
		squadWatch:Disconnect()
		squadWatch = nil
	end
	if not cardFrame then
		return
	end
	-- (Quint: Back would swing it right first, towards the rules card.)
	local width = cardFrame.Size.X.Offset
	UIKit.Tween(
		cardFrame,
		0.3,
		{ Position = UDim2.fromOffset(-width - 40, cardFrame.Position.Y.Offset) },
		Enum.EasingStyle.Quint,
		Enum.EasingDirection.In
	)
	task.delay(0.32, function()
		local holder = cardFrame.Parent
		if holder then
			holder:Destroy()
		end
	end)
end

local function showSquad(mates: { Player }, team: string)
	local layout = if touch then SQUAD.Touch else SQUAD.Pc
	local left = if touch then 8 else 16 -- where its holder sits, in pixels
	-- The full card when it fits left of the rules card on this screen, else the compact one, else
	-- none this round (a screen narrower than any phone).
	local room = roomBesideRules(left)
	local compact = false
	if room and room < layout.Width then
		if room < layout.Compact then
			return
		end
		compact = true
	end
	local width = if compact then layout.Compact else layout.Width
	local info = PartyView.Info(PartyView.Mine())
	local teamColor = Teams.Colors[team] or info.Color
	-- Compact: the emblem, SQUAD and the team's mark stacked over the faces, all a little smaller.
	local medal = if compact then layout.Medallion - 6 else layout.Medallion
	local titleSize = if compact then layout.Title - 8 else layout.Title
	local row = if compact then layout.Row - 6 else layout.Row
	local faceSize = if compact then layout.Face - 4 else layout.Face
	local chipTop = if compact then 10 + medal + 4 + titleSize + 6 + 4 else 12 + medal + 8
	local first = if compact then chipTop + layout.Chip + 10 else layout.First
	local height = first + #mates * row + 8
	local holder = UIKit.new("Frame", {
		Name = "SquadIntro",
		Position = UDim2.fromOffset(left, if touch then 6 else 12),
		Size = UDim2.fromOffset(width + 20, layout.Top + height + 10),
		BackgroundTransparency = 1,
		Parent = hud,
	})
	UIKit.AutoScale(holder)
	local cardFrame = UIKit.Panel({
		Name = "Card",
		Position = UDim2.fromOffset(-width - 40, layout.Top),
		Size = UDim2.fromOffset(width, height),
		CornerRadius = 22,
		ZIndex = 2,
		Parent = holder,
	}, PartyKit.Darker(teamColor, 0.2), PartyKit.Darker(info.Color, 0.75))
	cardFrame:SetAttribute("PP_Popup", true) -- before the round (everyone's frozen); nothing on it takes taps
	local loops = PartyKit.Group()
	PartyKit.SpinBorder(
		cardFrame,
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, teamColor),
			ColorSequenceKeypoint.new(0.35, WHITE),
			ColorSequenceKeypoint.new(0.65, info.Color),
			ColorSequenceKeypoint.new(1, teamColor),
		}),
		5,
		loops
	)
	PartyKit.Shine(cardFrame, loops, { ZIndex = 2, Period = 1.6, Strength = 0.35 })
	-- The party's emblem and SQUAD, then the team the round put you on, as a chip of its colour.
	local emblem = PartyKit.Medallion({
		Size = medal,
		Parent = cardFrame,
		Position = if compact
			then UDim2.fromOffset(width / 2, 10 + medal / 2)
			else UDim2.fromOffset(12 + medal / 2, 12 + medal / 2),
		ZIndex = 4,
		Halo = false,
	})
	PartyKit.SetMedallion(emblem, info.Color, info.Emblem)
	UIKit.Label({
		Name = "Title",
		Text = "SQUAD",
		Font = Theme.Fonts.Display,
		TextSize = titleSize,
		TextWrapped = false,
		TextXAlignment = if compact then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left,
		Position = if compact then UDim2.fromOffset(8, 10 + medal + 4) else UDim2.fromOffset(12 + medal + 10, 12),
		Size = if compact then UDim2.new(1, -16, 0, titleSize + 6) else UDim2.new(1, -(12 + medal + 16), 0, medal),
		ZIndex = 4,
		Parent = cardFrame,
		Children = { UIKit.TextStroke(0) },
	})
	-- (Compact: the team's mark alone, "■" or "🦈".)
	local teamText = if compact
		then Teams.Shapes[team] or Teams.Icons[team] or string.sub(string.upper(team), 1, 1)
		else Teams.Label(team)
	local chipWidth = math.min(
		width - 24,
		math.ceil(UIKit.TextWidth(teamText, layout.ChipText, Theme.Fonts.Display)) + (if compact then 34 else 26)
	)
	UIKit.Label({
		Name = "Team",
		Text = teamText,
		Font = Theme.Fonts.Display,
		TextSize = layout.ChipText,
		TextWrapped = false,
		BackgroundTransparency = 0,
		BackgroundColor3 = PartyKit.Darker(teamColor, 0.15),
		AnchorPoint = Vector2.new(if compact then 0.5 else 0, 0),
		Position = if compact then UDim2.new(0.5, 0, 0, chipTop) else UDim2.fromOffset(12, chipTop),
		Size = UDim2.fromOffset(chipWidth, layout.Chip),
		ZIndex = 4,
		Parent = cardFrame,
		Children = { UIKit.Round(), UIKit.Stroke(WHITE, 2, 0.1), UIKit.TextStroke(0.1) },
	})
	-- Your party mates on your team: face (the leader wears the crown) and name; compact, faces only.
	for index, mate in mates do
		local top = first + (index - 1) * row
		UIKit.new("Frame", {
			Name = "Row",
			Position = UDim2.fromOffset(8, top),
			Size = UDim2.new(1, -16, 0, row - 6),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.7,
			ZIndex = 3,
			Parent = cardFrame,
			Children = { UIKit.Round() },
		})
		local face = PartyKit.Face({
			Size = faceSize,
			Parent = cardFrame,
			AnchorPoint = Vector2.new(if compact then 0.5 else 0, 0.5),
			Position = UDim2.fromOffset(if compact then width / 2 else 12, top + (row - 6) / 2),
			Halo = false,
			ZIndex = 4,
		})
		PartyKit.SetFace(face, mate, info.Color, PartyView.SeatOf(mate) == 1, nil)
		if not compact then
			local name = UIKit.Label({
				Name = "Mate",
				Text = mate.DisplayName,
				Font = Theme.Fonts.Display,
				TextSize = 22,
				TextWrapped = false,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.fromOffset(12 + faceSize + 10, top),
				Size = UDim2.new(1, -(12 + faceSize + 20), 0, row - 6),
				ZIndex = 5,
				Parent = cardFrame,
				Children = { UIKit.TextStroke(0.1) },
			})
			name:SetAttribute("PP_TruncateOk", true)
		end
	end
	squadCard = cardFrame
	squadCompact = compact
	-- (Quint: Back would overshoot to the right, into the gap kept for the rules card.)
	UIKit.Tween(cardFrame, 0.45, { Position = UDim2.fromOffset(0, layout.Top) }, Enum.EasingStyle.Quint)
	AudioController.Play("Pickup")
	-- A screen that changes under it (a window made smaller) takes it away if it no longer fits.
	squadWatch = hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local now = roomBesideRules(left)
		if squadCard == cardFrame and now and now < width then
			hideSquad()
		end
	end)
	task.delay(SQUAD_TIME, function()
		if squadCard == cardFrame then
			hideSquad()
		end
	end)
end

local function refreshSquad()
	local phase = GameState.Get("Phase")
	local rulesUp = player:GetAttribute("PP_RulesShowing") == true
	if phase ~= "Preparing" or not rulesUp then
		hideSquad()
		return
	end
	local round = GameState.Get("RoundId") or 0
	if squadRound == round or squadCard then
		return
	end
	local mates, team = squadMates()
	if #mates == 0 or not team then
		return
	end
	squadRound = round
	showSquad(mates, team)
end

-- What's on screen, for the harnesses.
function SquadController.Status(): { [string]: any }
	local faces = {}
	for _, slot in slots do
		if slot.Holder.Visible then
			local crown = slot.Face.Crown.Visible
			table.insert(faces, `{slot.Face.Initial.Text}{if crown then "👑" else ""}`)
		end
	end
	local squad = nil
	if squadCard then
		local texts = {}
		for _, item in squadCard:GetDescendants() do
			if item:IsA("TextLabel") and item.Text ~= "" and item.Name ~= "Initial" then
				table.insert(texts, item.Text)
			end
		end
		squad = table.concat(texts, " | ")
	end
	return {
		Bar = barShown,
		Faces = faces,
		Streak = if streakPill and streakPill.Visible then streakText.Text else nil,
		Name = if partyName then partyName.Text else nil,
		Squad = squad,
		SquadCompact = if squadCard then squadCompact else nil,
		SquadWidth = if squadCard then squadCard.Size.X.Offset else nil,
		Moments = #moments,
		Banner = layer and layer:FindFirstChild("PartyUp") ~= nil,
	}
end

function SquadController.Start(context)
	touch = UIKit.IsTouch()
	hud = context.Hud
	PartyView.Start()
	layer = UIKit.new("ScreenGui", {
		Name = "PartyPanicParty",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, -- the HUD's safe area: faces fly between them
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 11, -- over the windows (10): the moment shows on the PARTY window too
		Parent = context.Hud.Parent,
	})
	buildBar(context)
	PartyKit.SetPlaying(barLoops, false)
	refreshBar()
	PartyView.Changed:Connect(refreshBar)
	GameState.Changed("Phase", function()
		refreshBar()
		refreshSquad()
	end)
	GameState.Changed("Replay", refreshBar)
	context.Hud:GetAttributeChangedSignal("PP_TipsAside"):Connect(refreshBar)
	PartyKit.WhenChild(context.Hud, "Vote", function(child)
		if child:IsA("GuiObject") then
			voteRow = child
			child:GetPropertyChangedSignal("Visible"):Connect(refreshBar)
			refreshBar()
		end
	end)
	Remotes.Get("Party").OnClientEvent:Connect(onServer)
	-- The SQUAD card: once the rules card is up and the round has put everyone on teams.
	player:GetAttributeChangedSignal("PP_RulesShowing"):Connect(refreshSquad)
	player:GetAttributeChangedSignal("PP_Team"):Connect(function()
		task.defer(refreshSquad) -- (mates' teams land in the same moment)
	end)
	player:GetAttributeChangedSignal("PP_InRound"):Connect(refreshSquad)
	-- A streak going up pops the pill.
	local lastStreak = 0
	PartyView.Changed:Connect(function()
		local streak = PartyView.Info(PartyView.Mine()).Streak
		if streak > lastStreak and barShown and streakPill.Visible and not State.ReducedEffects() then
			UIKit.PopIn(streakPill, 0.4)
		end
		lastStreak = streak
	end)
end

return SquadController
