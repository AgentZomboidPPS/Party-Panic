-- Parties on screen (owner: "stuff to work on right now is parties. The parties work in the way that
-- if you party with others for team games you are on the same team."). The server runs them
-- (Services/PartyService: the PP_Party and PP_PartySeat player attributes, and the "Party" remote);
-- this only shows them and asks.
--   * The 👥 PARTY chip in the lobby's row (UI/LobbyRibbon, priority 2.5: after the cup, before the
--     invite chip; it shows once someone else is on the server) opens the PARTY window: your party (👑 its leader) with LEAVE, and everyone else
--     here with an INVITE each, your Roblox friends (⭐) first. Someone in a full party has no INVITE
--     ("FULL"); someone in another party shows it ("👥 2/4": joining yours takes them out of it). A
--     tapped INVITE says SENT until the answer comes. At the bottom, Roblox's invite to the game for
--     friends who aren't here (on a phone's full row of chips, the 👋 INVITE chip can be the one left
--     out while PARTY shows).
--   * An invite comes as a card: "👥 Bubbles invited you to their party!" with JOIN and NO, and a bar
--     running down its 20 seconds. It shows in the lobby only (its time stops under the rules card
--     and in the round, and it comes back after), one at a time. Phones: in the middle of the gap
--     between the MOVE stick's corner and the menu column, under the chips and above the toasts and
--     the jump button; while the vote cards are up at the bottom middle, at the top of the screen
--     instead (placeCard); thumb-sized buttons. PC: in the middle, under the chips.
--   * Everyone in a party has a 👥 before their name on their name tag (the server's PP_Nameplate),
--     so friends in the lobby can see who's together.
-- Bots are never in parties (they aren't Players, so they're never listed).
--
-- The glow-up (owner: "Also make the party system insane. I want it to look super epic."), drawn
-- with UI/PartyKit in the party's own colour (its look and streak: Client/PartyView):
--   * The window opens on an animated header in place of its title: the party's emblem on a
--     glowing medallion, its name in big letters with a shine sweeping across, how many are in it
--     and its streak (🔥 rounds in a row together). Under it, the squad: four big cards, each a
--     headshot in a glowing ring with the 👑 on the leader and a level badge in the player's prestige
--     colours (the leader's card has a gold rim, yours a white one); the empty ones pulse "+ INVITE"
--     (a tap goes to the people here, or opens Roblox's invite when nobody else is). The leader gets
--     the PARTY LOOK: 🎲 a new name, and the colour and emblem from 8 each (everyone else is told who
--     picks). Then the people here, with their faces, their party's emblem and name, and an INVITE
--     that glows. On your own, the header says NO PARTY YET and your card waits with three empty ones.
--   * The invite card: PARTY INVITE, the inviter's name and their party's emblem, name and size (or
--     "wants you on their team!" when they're on their own), with their face inside a ring that runs
--     down the 20 seconds (gold, orange past half, red at the end), a rim of colours turning round the
--     card, and a JOIN that glows.
-- Everything that moves is a looping tween, paused while the window is closed (PartyKit.Group).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService") -- Roblox's invites to the game

local Shared = ReplicatedStorage.Shared
local GameState = require(Shared.GameState)
local PartyIdentity = require(Shared.Logic.PartyIdentity)
local PartyLogic = require(Shared.Logic.PartyLogic)
local PartyStreak = require(Shared.Logic.PartyStreak)
local Remotes = require(Shared.Remotes)

local AudioController = require(script.Parent.AudioController)
local PartyView = require(script.Parent.Parent.PartyView)
local LobbyRibbon = require(script.Parent.Parent.UI.LobbyRibbon)
local Modal = require(script.Parent.Parent.UI.Modal)
local PartyKit = require(script.Parent.Parent.UI.PartyKit)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local PartyController = {}

type Incoming = { From: number, Name: string, Left: number, Since: number? }

local LOBBY = { Waiting = true, Intermission = true, Voting = true, Cleanup = true }
local MARK = "👥 " -- before a party member's name on their name tag
local SENT_WAIT = 3 -- seconds a tapped INVITE says SENT before the server has said so
local TAG_SWEEP = 1 -- seconds between name tag checks (a new character brings a new tag)
local GREEN_DARK = Color3.fromRGB(60, 160, 90)
local CYAN_DARK = Color3.fromRGB(40, 140, 230)
-- Before anyone's in a party: the window's header and the empty squad wear the panels' lavender.
local NO_PARTY = { Color = Theme.Colors.Lavender, Emblem = "👥" }

-- Scaled units (UIKit.AutoScale: phones get 0.62 points per unit).
local WINDOW = { Touch = Vector2.new(860, 600), Pc = Vector2.new(820, 660) }
local HEADER = 112 -- the header card's height (it sits 12 down, inside the window)
local CLOSE_ROOM = { Touch = 80, Pc = 54 } -- the window's X sits over the header's top right
local STREAK = Vector2.new(112, 86)
local ROW = { Touch = 84, Pc = 66 } -- a person's line in the window: a thumb-sized INVITE on phones
local ROW_FACE = { Touch = 62, Pc = 50 }
local BUTTON = { Touch = Vector2.new(176, 72), Pc = Vector2.new(150, 46) }
local MEMBER = { Touch = Vector2.new(190, 216), Pc = Vector2.new(180, 206) }
local MEMBER_FACE = 112
local SWATCH = { Touch = 72, Pc = 54 }
local CARD = { Touch = Vector2.new(500, 244), Pc = Vector2.new(540, 214) }
local CARD_BUTTON = { Touch = Vector2.new(168, 72), Pc = Vector2.new(170, 52) } -- JOIN; NO is 0.62 of it
local CARD_RING = { Touch = 150, Pc = 138 }
local TIMER_COLORS = { Theme.Colors.Yellow, Theme.Colors.Orange, Theme.Colors.Red }
-- Where the card's middle is, as a share of the screen's safe area: phones, right of the MOVE stick's
-- zone (its left 40%) and left of the menu column; PC, in the middle of the band between the chips'
-- row and the vote cards.
local CARD_AT = { Touch = Vector2.new(0.64, 0.52), Pc = Vector2.new(0.5, 0.46) }
-- Phones and tablets while the vote cards are up at the bottom middle: the card's top, in pixels under
-- the top bar (the chips' row is away during the vote there).
local CARD_TOP = 8

local touch = false
local remote: RemoteEvent
local chip: LobbyRibbon.Chip
local window: Modal.Modal
local list: ScrollingFrame
local loops = PartyKit.Group() -- the window's animations (paused while it's closed)
local cardLoops = PartyKit.Group() -- the invite card's
local peopleHeading: GuiObject? = nil
local memberFaces: { [number]: Frame } = {} -- UserId -> their face on a squad card (SquadController lands there)
local lastEdit = -math.huge -- the leader's last change to the look (the server has a cooldown too)

local header: Frame
local headerTint: UIGradient
local headerMedallion: PartyKit.Medallion
local headerName: TextLabel
local headerLine: TextLabel
local streakPill: Frame
local streakTint: UIGradient
local streakNumber: TextLabel

local cardHolder: Frame
local card: Frame
local voteRow: GuiObject? = nil -- VoteController's row of vote cards
local cardKicker: TextLabel
local cardTitle: TextLabel
local cardParty: TextLabel
local cardFace: PartyKit.Face
local cardTimer: PartyKit.TimerRing
local cardRim: UIStroke
local cardUrgency = 0 -- the countdown ring's colour step (TIMER_COLORS)
local incoming: { Incoming } = {} -- invites waiting for my answer, oldest first
local shown: Incoming? = nil -- the one on the card
local asked: { [number]: number } = {} -- UserId -> until when my invite to them says SENT
local friends: { [number]: boolean } = {}
local watched: { [any]: boolean } = {}
local refreshQueued = false
local canInviteFriends = false -- Roblox lets this player send invites to the game

local function me(): Player
	return Players.LocalPlayer
end

local function partyOf(player: any): number?
	return PartyView.PartyOf(player)
end

local function seatOf(player: any): number
	return PartyView.SeatOf(player)
end

-- The people in a party, its leader first.
local function membersOf(id: number?): { Player }
	return PartyView.Members(id)
end

local function lobbyUp(): boolean
	local phase = GameState.Get("Phase") or "Waiting"
	return LOBBY[phase] == true and not (phase == "Cleanup" and (GameState.Get("Replay") or "") ~= "")
end

local function size(pair: { Touch: any, Pc: any }): any
	return if touch then pair.Touch else pair.Pc
end

-- The look the window wears: my party's, or the panels' lavender on my own.
local function lookOf(id: number?): (Color3, string, PartyView.Info?)
	if id == nil then
		return NO_PARTY.Color, NO_PARTY.Emblem, nil
	end
	local info = PartyView.Info(id)
	return info.Color, info.Emblem, info
end

local queueRefresh: () -> ()

-- The window -----------------------------------------------------------------------------------------

local function label(props: { [string]: any }): TextLabel
	props.BackgroundTransparency = 1
	return UIKit.Label(props)
end

local function clear(frame: Instance)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function line(order: number, height: number): Frame
	return UIKit.new("Frame", {
		Name = "Line",
		Size = UDim2.new(1, -12, 0, height),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = list,
	})
end

-- A heading with room for a button (`room` units wide, a pill's by default) at its right end.
local function heading(order: number, text: string, room: number?): Frame
	local frame = line(order, size(BUTTON).Y)
	label({
		Name = "Heading",
		Text = text,
		Font = Theme.Fonts.Display,
		TextSize = 26,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -((room or size(BUTTON).X) + 12), 1, 0),
		Parent = frame,
		Children = { UIKit.TextStroke(0.2) },
	})
	return frame
end

local function note(order: number, text: string, color: Color3?)
	local frame = line(order, 50)
	local words = label({
		Name = "Note",
		Text = text,
		TextSize = Theme.Touch.MinText + 1,
		TextColor3 = color or Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromScale(1, 1),
		Parent = frame,
	})
	words:SetAttribute("PP_Lines", 2)
end

local function pill(
	frame: Frame,
	text: string,
	onClick: (() -> ())?,
	top: Color3,
	bottom: Color3,
	width: number?
): TextButton
	return UIKit.Button({
		Name = "Action",
		Text = text,
		TextSize = if touch then 26 else 22,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(width or size(BUTTON).X, size(BUTTON).Y),
		CornerRadius = "round",
		AutoButtonColor = false,
		Active = onClick ~= nil,
		ZIndex = 24,
		Parent = frame,
	}, onClick, top, bottom)
end

-- A soft glow that breathes round a button (behind it), for the buttons that invite you in.
local function glowBehind(button: GuiObject, color: Color3, group: PartyKit.Group)
	local glow = UIKit.new("Frame", {
		Name = "Glow",
		AnchorPoint = button.AnchorPoint,
		Position = button.Position,
		Size = button.Size,
		BackgroundTransparency = 1,
		ZIndex = math.max(1, button.ZIndex - 1),
		Parent = button.Parent,
		Children = { UIKit.Round() },
	})
	local stroke = UIKit.new("UIStroke", { Color = color, Thickness = 7, Transparency = 0.35, Parent = glow })
	PartyKit.Loop(stroke, 0.9, { Thickness = 12, Transparency = 0.8 }, group)
end

local function invite(userId: number)
	asked[userId] = os.clock() + SENT_WAIT
	remote:FireServer("Invite", userId)
	task.delay(SENT_WAIT + 0.1, queueRefresh)
	queueRefresh()
end

local function waitingFor(userId: number): boolean
	return (asked[userId] or 0) > os.clock()
end

-- Everyone here but me and my party: friends first, then by name.
local function others(mine: number?): { Player }
	local people = {}
	for _, player in Players:GetPlayers() do
		if player ~= me() and (mine == nil or partyOf(player) ~= mine) then
			table.insert(people, player)
		end
	end
	table.sort(people, function(a, b)
		local fa, fb = friends[a.UserId] == true, friends[b.UserId] == true
		if fa ~= fb then
			return fa
		end
		return string.lower(a.DisplayName) < string.lower(b.DisplayName)
	end)
	return people
end

local function inviteFriendsToGame()
	window:Close()
	local ok, err = pcall(SocialService.PromptGameInvite, SocialService, me())
	if not ok then
		warn(`[PartyController] the invite prompt didn't open: {err}`)
	end
end

-- An empty squad slot's tap: down to the people here, or Roblox's invite when nobody else is.
local function onEmptySlot()
	local target = peopleHeading
	if #others(partyOf(me())) == 0 or not target then
		if canInviteFriends then
			inviteFriendsToGame()
		end
		return
	end
	local goal = target.AbsolutePosition.Y - list.AbsolutePosition.Y + list.CanvasPosition.Y
	UIKit.Tween(list, 0.35, { CanvasPosition = Vector2.new(0, math.max(0, goal)) })
end

-- The header -------------------------------------------------------------------------------------------

local function buildHeader()
	-- The window's own title ("👥 PARTY") makes way for the header; its X stays on top.
	local titleBar = window.Window:FindFirstChild("TitleBar")
	if titleBar then
		for _, item in titleBar:GetChildren() do
			if item:IsA("TextLabel") then
				item.Visible = false
			end
		end
	end
	header = UIKit.Panel({
		Name = "PartyHeader",
		Position = UDim2.fromOffset(14, 12),
		Size = UDim2.new(1, -28, 0, HEADER),
		CornerRadius = 20,
		ZIndex = 21, -- under the title bar's X (its sibling at 22)
		Parent = window.Window,
	})
	headerTint = header:FindFirstChildOfClass("UIGradient") :: UIGradient
	headerTint.Rotation = 20
	local rim = header:FindFirstChildOfClass("UIStroke") :: UIStroke
	rim.Thickness = 3
	rim.Transparency = 0.15
	PartyKit.Shine(header, loops, { ZIndex = 21, Period = 2.4, Strength = 0.4 })
	headerMedallion = PartyKit.Medallion({
		Size = 84,
		Parent = header,
		Position = UDim2.fromOffset(16 + 44, HEADER / 2),
		ZIndex = 23,
		Group = loops,
	})
	local closeRoom = size(CLOSE_ROOM)
	local rightRoom = closeRoom + STREAK.X + 14
	headerName = label({
		Name = "PartyName",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 40,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(124, 12),
		Size = UDim2.new(1, -(124 + rightRoom), 0, 50),
		ZIndex = 23,
		Parent = header,
		Children = { UIKit.TextStroke(0.05) },
	})
	headerLine = label({
		Name = "PartyLine",
		Text = "",
		TextSize = 21,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(240, 236, 255),
		Position = UDim2.fromOffset(126, 64),
		Size = UDim2.new(1, -(126 + rightRoom), 0, 30),
		ZIndex = 23,
		Parent = header,
		Children = { UIKit.TextStroke(0.35) },
	})
	-- The streak: a flame pill left of the window's X.
	streakPill = UIKit.new("Frame", {
		Name = "Streak",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -closeRoom, 0.5, 0),
		Size = UDim2.fromOffset(STREAK.X, STREAK.Y),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 23,
		Parent = header,
		Children = { UIKit.Corner(22), UIKit.Stroke(Color3.new(1, 1, 1), 3, 0.1) },
	})
	streakTint = UIKit.new("UIGradient", { Rotation = 90, Parent = streakPill })
	streakNumber = label({
		Name = "Number",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 34,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, 44),
		ZIndex = 24,
		Parent = streakPill,
		Children = { UIKit.TextStroke(0.05) },
	})
	label({
		Name = "Word",
		Text = "STREAK",
		Font = Theme.Fonts.Display,
		TextSize = Theme.Touch.MinText,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 0, 26),
		ZIndex = 24,
		Parent = streakPill,
		Children = { UIKit.TextStroke(0.2) },
	})
	-- The list starts under the header.
	window.Content.Position = UDim2.fromOffset(20, 12 + HEADER + 10)
	window.Content.Size = UDim2.new(1, -40, 1, -(12 + HEADER + 10 + 14))
end

-- Fits the party's name on its line: the biggest size up to `biggest` it fits at (down to
-- `smallest`), in the room the header leaves it (the window may have been shrunk to fit the screen).
local function fitName(biggest: number, smallest: number)
	local width = window.Window.Size.X.Offset - 28 + headerName.Size.X.Offset
	local textSize = biggest
	while textSize > smallest and UIKit.TextWidth(headerName.Text, textSize, headerName.Font) > width do
		textSize -= 2
	end
	headerName.TextSize = textSize
end

local function refreshHeader()
	local mine = partyOf(me())
	local color, emblem, info = lookOf(mine)
	local members = membersOf(mine)
	headerTint.Color = ColorSequence.new(PartyKit.Darker(color, 0.05), PartyKit.Darker(color, 0.5))
	PartyKit.SetMedallion(headerMedallion, color, emblem)
	if info then
		headerName.Text = string.upper(info.Name)
		headerLine.Text = `👥 {#members}/{PartyLogic.MaxSize}  ·  same team in team games`
	else
		headerName.Text = "NO PARTY YET"
		headerLine.Text = "Invite people here to team up!"
	end
	fitName(40, 26)
	streakPill.Visible = info ~= nil
	local streak = if info then info.Streak else 0
	streakNumber.Text = `🔥 {streak}`
	streakTint.Color = PartyKit.FlameColors(PartyStreak.Tier(streak))
end

-- The squad -------------------------------------------------------------------------------------------

local function chipLabel(parent: Instance, text: string, color: Color3, order: number)
	local width = math.ceil(UIKit.TextWidth(text, 18, Theme.Fonts.Display)) + 20
	UIKit.Label({
		Name = "Tag",
		Text = text,
		Font = Theme.Fonts.Display,
		TextSize = Theme.Touch.MinText,
		TextWrapped = false,
		BackgroundTransparency = 0,
		BackgroundColor3 = color,
		Size = UDim2.fromOffset(width, 28),
		LayoutOrder = order,
		ZIndex = 25,
		Parent = parent,
		Children = { UIKit.Round(), UIKit.TextStroke(0.2) },
	})
end

local function memberCard(row: Frame, slot: number, member: Player?, color: Color3)
	local dims = size(MEMBER)
	local mine = member == me()
	local cardFrame = UIKit.Panel({
		Name = `Slot{slot}`,
		Size = UDim2.fromOffset(dims.X, dims.Y),
		LayoutOrder = slot,
		CornerRadius = 22,
		ZIndex = 22,
		Parent = row,
	}, PartyKit.Darker(color, if member then 0.35 else 0.7), Theme.Colors.PanelDark)
	local rim = cardFrame:FindFirstChildOfClass("UIStroke") :: UIStroke
	if not member then
		-- An empty slot: a ring with a + that pulses, "INVITE" under it; a tap finds people.
		cardFrame.BackgroundTransparency = 0.35
		rim.Transparency = 0.6
		local tap = UIKit.new("TextButton", {
			Name = "Tap",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 23,
			Parent = cardFrame,
		})
		tap.Activated:Connect(onEmptySlot)
		local ring = UIKit.new("Frame", {
			Name = "Empty",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 22),
			Size = UDim2.fromOffset(MEMBER_FACE, MEMBER_FACE),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.88,
			ZIndex = 23,
			Parent = tap,
			Children = { UIKit.Round() },
		})
		local ringStroke = UIKit.new("UIStroke", { Color = color, Thickness = 4, Transparency = 0.35, Parent = ring })
		local plus = label({
			Name = "Plus",
			Text = "+",
			Font = Theme.Fonts.Display,
			TextSize = 72,
			TextWrapped = false,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 24,
			Parent = ring,
			Children = { UIKit.TextStroke(0.3) },
		})
		local words = label({
			Name = "Invite",
			Text = "INVITE",
			Font = Theme.Fonts.Display,
			TextSize = 24,
			TextWrapped = false,
			TextColor3 = PartyKit.Lighter(color, 0.4),
			Position = UDim2.fromOffset(0, 146),
			Size = UDim2.new(1, 0, 0, 32),
			ZIndex = 24,
			Parent = tap,
			Children = { UIKit.TextStroke(0.2) },
		})
		local pulse = UIKit.new("UIScale", { Scale = 0.94, Parent = ring })
		local beat = 0.75 + 0.12 * slot -- the empty slots don't pulse in step
		PartyKit.Loop(pulse, beat, { Scale = 1.05 }, loops)
		PartyKit.Loop(ringStroke, beat, { Transparency = 0 }, loops)
		PartyKit.Loop(plus, beat, { TextTransparency = 0.35 }, loops)
		PartyKit.Loop(words, beat, { TextTransparency = 0.3 }, loops)
		return
	end
	local leads = seatOf(member) == 1
	rim.Color = if leads then Theme.Colors.Yellow elseif mine then Color3.new(1, 1, 1) else PartyKit.Lighter(color, 0.3)
	rim.Thickness = if leads or mine then 4 else 3
	rim.Transparency = if leads or mine then 0 else 0.25
	local face = PartyKit.Face({
		Size = MEMBER_FACE,
		Parent = cardFrame,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 22),
		Badge = true,
		Group = loops,
		ZIndex = 23,
	})
	local leader = seatOf(member) == 1
	PartyKit.SetFace(face, member, color, leader, PartyKit.LevelOf(member))
	memberFaces[member.UserId] = face.Frame
	local name = label({
		Name = "Name",
		Text = (member :: Player).DisplayName,
		Font = Theme.Fonts.Display,
		TextSize = 22,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(8, 142),
		Size = UDim2.new(1, -16, 0, 30),
		ZIndex = 24,
		Parent = cardFrame,
		Children = { UIKit.TextStroke(0.15) },
	})
	name:SetAttribute("PP_TruncateOk", true) -- a long name may end in "..."
	local tags = UIKit.new("Frame", {
		Name = "Tags",
		Position = UDim2.fromOffset(0, 176),
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		ZIndex = 24,
		Parent = cardFrame,
		Children = { UIKit.List(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center) },
	})
	if leader then
		chipLabel(tags, "LEADER", Theme.Colors.Orange, 1)
	end
	if mine then
		chipLabel(tags, "YOU", CYAN_DARK, 2)
	end
end

local function squadRow(order: number, mine: number?, members: { Player }, color: Color3)
	local row = line(order, size(MEMBER).Y + 8)
	row.Name = "Squad"
	UIKit.List(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center).Parent = row
	-- On my own, my card first, then the room for a party.
	local shown = if mine then members else { me() }
	for slot = 1, PartyLogic.MaxSize do
		memberCard(row, slot, shown[slot], color)
	end
end

-- The leader's PARTY LOOK: a new name, the colour and the emblem (the server checks it's them).
local function edit(action: string, value: number?)
	if os.clock() - lastEdit < PartyIdentity.EditCooldown then
		return
	end
	lastEdit = os.clock()
	remote:FireServer(action, value)
	AudioController.Play("Click")
end

local function swatchRow(order: number, count: number, build: (index: number, button: TextButton) -> ())
	local frame = line(order, size(SWATCH) + 10)
	frame.Name = "Swatches"
	UIKit.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center).Parent =
		frame
	for index = 1, count do
		local button = UIKit.new("TextButton", {
			Name = `Pick{index}`,
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.fromOffset(size(SWATCH), size(SWATCH)),
			BackgroundColor3 = Color3.new(1, 1, 1),
			LayoutOrder = index,
			ZIndex = 23,
			Parent = frame,
			Children = { UIKit.Round() },
		})
		build(index, button)
	end
end

local function lookSection(order: () -> number, info: PartyView.Info, members: { Player })
	if not PartyView.IsLeader(me()) then
		local leader = members[1]
		note(
			order(),
			`👑 {if leader then leader.DisplayName else "The leader"} picks the party's name, colour and emblem.`
		)
		return
	end
	local rerollWidth = if touch then 230 else 180
	local top = heading(order(), "PARTY LOOK", rerollWidth)
	pill(top, "🎲 NEW NAME", function()
		edit("Reroll")
	end, Theme.Colors.Lavender, Theme.Colors.Purple, rerollWidth)
	swatchRow(order(), #PartyIdentity.Colors, function(index, button)
		local color = PartyView.ColorAt(index)
		local picked = index == info.ColorIndex
		UIKit.Gradient(PartyKit.Lighter(color, 0.25), PartyKit.Darker(color, 0.15)).Parent = button
		UIKit.new("UIStroke", {
			Color = if picked then Color3.new(1, 1, 1) else PartyKit.Darker(color, 0.4),
			Thickness = if picked then 4 else 2,
			Transparency = 0,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = button,
		})
		if picked then
			label({
				Name = "Tick",
				Text = "✓",
				Font = Theme.Fonts.Display,
				TextSize = 32,
				TextWrapped = false,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 24,
				Parent = button,
				Children = { UIKit.TextStroke(0.1) },
			})
		end
		button.Activated:Connect(function()
			edit("Color", index)
		end)
	end)
	swatchRow(order(), #PartyIdentity.Emblems, function(index, button)
		local picked = index == info.EmblemIndex
		button.BackgroundColor3 = if picked then info.Color else Theme.Colors.PanelDark
		button.BackgroundTransparency = if picked then 0 else 0.2
		UIKit.new("UIStroke", {
			Color = Color3.new(1, 1, 1),
			Thickness = if picked then 4 else 2,
			Transparency = if picked then 0 else 0.6,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = button,
		})
		button.Text = PartyIdentity.Emblems[index].Icon
		button.TextSize = if touch then 36 else 30
		button.TextColor3 = Color3.new(1, 1, 1)
		button.Activated:Connect(function()
			edit("Emblem", index)
		end)
	end)
end

-- People here -------------------------------------------------------------------------------------------

local function personRow(order: number, player: Player, full: boolean)
	local theirs = partyOf(player)
	local theirMembers = membersOf(theirs)
	local theyreFull = #theirMembers >= PartyLogic.MaxSize
	local row = line(order, size(ROW))
	row.BackgroundTransparency = 0.4
	row.BackgroundColor3 = Theme.Colors.PanelDark
	UIKit.Corner(16).Parent = row
	local faceSize = size(ROW_FACE)
	local info = if theirs then PartyView.Info(theirs) else nil
	local face = PartyKit.Face({
		Size = faceSize,
		Parent = row,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Halo = false,
		ZIndex = 23,
	})
	PartyKit.SetFace(face, player, if info then info.Color else Color3.new(1, 1, 1), false, nil)
	local textLeft = 12 + faceSize + 14
	local room = size(BUTTON).X + 24
	local friend = if friends[player.UserId] then "⭐ " else ""
	local name = label({
		Name = "Name",
		Text = `{friend}{player.DisplayName}`,
		TextSize = 22,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.new(0, textLeft, 0, if info then 4 else 0),
		Size = UDim2.new(1, -(textLeft + room), if info then 0.5 else 1, if info then -4 else 0),
		ZIndex = 24,
		Parent = row,
	})
	name:SetAttribute("PP_TruncateOk", true) -- a long name may end in "..."
	if info then
		-- Their party: its emblem, name and size, in its colour.
		local party = label({
			Name = "Party",
			Text = `{info.Emblem} {string.upper(info.Name)} · {#theirMembers}/{PartyLogic.MaxSize}`,
			Font = Theme.Fonts.Display,
			TextSize = Theme.Touch.MinText,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = PartyKit.Lighter(info.Color, 0.25),
			Position = UDim2.new(0, textLeft, 0.5, 2),
			Size = UDim2.new(1, -(textLeft + room), 0.5, -8),
			ZIndex = 24,
			Parent = row,
			Children = { UIKit.TextStroke(0.3) },
		})
		party:SetAttribute("PP_TruncateOk", true)
	end
	-- (FULL and SENT wear the panel's colours: they're not buttons.)
	if theyreFull then
		pill(row, "FULL", nil, Theme.Colors.PanelLight, Theme.Colors.Panel)
	elseif waitingFor(player.UserId) then
		pill(row, "SENT ✓", nil, Theme.Colors.PanelLight, Theme.Colors.Panel)
	elseif not full then
		local userId = player.UserId
		local button = pill(row, "INVITE", function()
			invite(userId)
		end, Theme.Colors.Green, GREEN_DARK)
		glowBehind(button, Theme.Colors.Green, loops)
	end
end

local function fillWindow()
	clear(list)
	memberFaces = {}
	peopleHeading = nil
	PartyKit.SetPlaying(loops, window.IsOpen) -- (drops the loops of what was just cleared)
	local mine = partyOf(me())
	local members = membersOf(mine)
	local color, _, info = lookOf(mine)
	local full = #members >= PartyLogic.MaxSize
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	refreshHeader()

	-- The squad.
	if mine then
		local top = heading(nextOrder(), `YOUR SQUAD {#members}/{PartyLogic.MaxSize}`)
		pill(top, "LEAVE", function()
			remote:FireServer("Leave")
		end, Theme.Colors.Orange, Color3.fromRGB(215, 95, 40))
	else
		heading(nextOrder(), "YOUR SQUAD")
	end
	squadRow(nextOrder(), mine, members, color)
	if info then
		lookSection(nextOrder, info, members)
	else
		note(nextOrder(), "A party plays on one team in team games. Invite people below!")
	end

	-- Everyone else.
	peopleHeading = heading(nextOrder(), "PEOPLE HERE")
	if full then
		note(nextOrder(), `Your party is full ({PartyLogic.MaxSize} at most).`, Theme.Colors.Yellow)
	end
	local people = others(mine)
	if #people == 0 then
		note(nextOrder(), "Nobody else is here yet.")
	end
	for _, player in people do
		personRow(nextOrder(), player, full)
	end

	-- Friends who aren't here yet: Roblox's invite (the lobby's 👋 INVITE chip does the same, but on
	-- a phone's full row it can be the chip left out).
	if canInviteFriends then
		UIKit.Button({
			Name = "InviteFriends",
			Text = "👋 INVITE FRIENDS TO THE GAME",
			TextSize = if touch then 24 else 22,
			Size = UDim2.new(1, -12, 0, size(BUTTON).Y),
			CornerRadius = "round",
			LayoutOrder = nextOrder(),
			ZIndex = 23,
			Parent = list,
		}, inviteFriendsToGame, Theme.Colors.Green, GREEN_DARK)
	end
end

-- Opens the PARTY window (the chip does; so does the client harness).
function PartyController.Open()
	window:Open()
	fillWindow()
end

-- Where someone's face is on the window's squad while it's open (the PARTY UP! face lands there).
function PartyController.FaceOf(userId: number): Frame?
	if not window or not window.IsOpen then
		return nil
	end
	local face = memberFaces[userId]
	return if face and face.Parent then face else nil
end

-- The invite card -------------------------------------------------------------------------------------

local function timeLeft(entry: Incoming): number
	return entry.Left - (if entry.Since then os.clock() - entry.Since else 0)
end

local function answer(join: boolean)
	local entry = shown
	if not entry then
		return
	end
	remote:FireServer("Answer", entry.From, join)
	local index = table.find(incoming, entry)
	if index then
		table.remove(incoming, index)
	end
	shown = nil
	queueRefresh()
end

-- The card's JOIN (true) or NO (false) (the client harness answers with it too).
function PartyController.Answer(join: boolean)
	answer(join)
end

-- Someone here by their UserId.
local function playerById(userId: number): Player?
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			return player
		end
	end
	return nil
end

-- The inviter's face, party and colours on the card.
local function dressCard(entry: Incoming)
	local inviter = playerById(entry.From)
	local theirs = if inviter then partyOf(inviter) else nil
	local info = if theirs then PartyView.Info(theirs) else nil
	local color = if info then info.Color else Theme.Colors.Cyan
	cardKicker.Text = "👥 PARTY INVITE"
	cardTitle.Text = entry.Name
	if info then
		cardParty.Text = `{info.Emblem} {string.upper(info.Name)} · {#membersOf(theirs)}/{PartyLogic.MaxSize}`
		cardParty.TextColor3 = PartyKit.Lighter(color, 0.45)
	else
		cardParty.Text = "wants you on their team!"
		cardParty.TextColor3 = Color3.fromRGB(225, 235, 255)
	end
	PartyKit.SetFace(cardFace, inviter or { UserId = entry.From, DisplayName = entry.Name }, color, false, nil)
	local spin = cardRim:FindFirstChild("Spin") :: UIGradient?
	if spin then
		spin.Color = PartyKit.RimColors(color)
	end
	local tint = card:FindFirstChildOfClass("UIGradient")
	if tint then
		tint.Color = ColorSequence.new(PartyKit.Darker(color, 0.15), Color3.fromRGB(60, 40, 150))
	end
end

-- Shows the oldest invite when the lobby's up, and hides the card (stopping its time) when not.
local function refreshCard()
	local free = lobbyUp()
	if shown and (not free or not table.find(incoming, shown)) then
		local entry = shown :: Incoming
		entry.Left = timeLeft(entry)
		entry.Since = nil
		shown = nil
	end
	if free and not shown and incoming[1] then
		local entry = incoming[1]
		entry.Since = os.clock()
		shown = entry
		dressCard(entry)
		card.Visible = true
		UIKit.PopIn(card, 0.3)
		AudioController.Play("Pickup")
	elseif shown then
		dressCard(shown :: Incoming) -- (the inviter's party can change while it's up)
	end
	card.Visible = shown ~= nil
	PartyKit.SetPlaying(cardLoops, card.Visible)
end

local function stepCard()
	local entry = shown
	if not entry then
		return
	end
	local left = timeLeft(entry)
	local share = left / PartyLogic.InviteSeconds
	PartyKit.TimerSet(cardTimer, share)
	-- Gold while there's plenty of time, orange past half, red at the end.
	local urgency = if share > 0.5 then 1 elseif share > 0.25 then 2 else 3
	if urgency ~= cardUrgency then
		cardUrgency = urgency
		PartyKit.TimerColor(cardTimer, TIMER_COLORS[urgency])
	end
	if left <= 0 then
		-- Its time ran out here: the server says so too, a moment later.
		local index = table.find(incoming, entry)
		if index then
			table.remove(incoming, index)
		end
		shown = nil
		refreshCard()
	end
end

-- Where the card goes: its spot (CARD_AT), or on phones and tablets while the vote cards are up at the
-- bottom middle, the top of the screen, which keeps it clear of them, of the toasts over them and of
-- the jump button on every screen (from its spot, the card would reach the cards on most phones).
-- It glides there when it's showing.
local function placeCard(animate: boolean)
	local vote = voteRow
	local goal
	if touch and vote and vote.Visible then
		goal = { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(CARD_AT.Touch.X, 0, 0, CARD_TOP) }
	else
		local at = size(CARD_AT)
		goal = { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(at.X, at.Y) }
	end
	if animate and card.Visible then
		UIKit.Tween(cardHolder, 0.3, goal)
	else
		cardHolder.AnchorPoint = goal.AnchorPoint
		cardHolder.Position = goal.Position
	end
end

local function buildCard(context)
	local dims = size(CARD)
	-- (The screen's scale on a holder, the pop-in on the card: one UIScale each.)
	cardHolder = UIKit.new("Frame", {
		Name = "PartyInviteHolder",
		Size = UDim2.fromOffset(dims.X, dims.Y),
		BackgroundTransparency = 1,
		ZIndex = 40,
		Parent = context.Overlay,
	})
	UIKit.AutoScale(cardHolder)
	card = UIKit.Panel({
		Name = "PartyInvite",
		AnchorPoint = Vector2.new(0.5, 0.5), -- (it pops from its middle)
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 40,
		CornerRadius = 26,
		Parent = cardHolder,
	}, Color3.fromRGB(70, 150, 255), Color3.fromRGB(60, 52, 170))
	-- A rim of colours turning round the card.
	cardRim = PartyKit.SpinBorder(card, PartyKit.RimColors(Theme.Colors.Cyan), 5, cardLoops)
	PartyKit.Shine(card, cardLoops, { ZIndex = 40, Period = 2, Strength = 0.3 })

	-- The inviter's face in the ring that runs down their invite's time.
	local ring = size(CARD_RING)
	local ringAt = UDim2.fromOffset(20 + ring / 2, dims.Y / 2)
	cardTimer = PartyKit.TimerRing({
		Size = ring,
		Thickness = 10,
		Color = Theme.Colors.Yellow,
		Parent = card,
		Position = ringAt,
		ZIndex = 41,
	})
	cardFace = PartyKit.Face({
		Size = ring - 34,
		Parent = card,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = ringAt,
		Halo = false,
		ZIndex = 42,
	})
	local textLeft = 20 + ring + 18
	cardKicker = label({
		Name = "Kicker",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = Theme.Touch.MinText + 1,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Colors.Yellow,
		Position = UDim2.fromOffset(textLeft, 14),
		Size = UDim2.new(1, -(textLeft + 16), 0, 26),
		ZIndex = 43,
		Parent = card,
		Children = { UIKit.TextStroke(0.15) },
	})
	cardTitle = label({
		Name = "Title",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 32,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(textLeft, 40),
		Size = UDim2.new(1, -(textLeft + 16), 0, 42),
		ZIndex = 43,
		Parent = card,
		Children = { UIKit.TextStroke(0.1) },
	})
	cardTitle:SetAttribute("PP_TruncateOk", true) -- a long name may end in "..."
	-- (A new card starts its ring gold.)
	card:GetPropertyChangedSignal("Visible"):Connect(function()
		cardUrgency = 0
	end)
	cardParty = label({
		Name = "Why",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = Theme.Touch.MinText + 3,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(textLeft, 84),
		Size = UDim2.new(1, -(textLeft + 16), 0, 30),
		ZIndex = 43,
		Parent = card,
		Children = { UIKit.TextStroke(0.15) },
	})
	cardParty:SetAttribute("PP_TruncateOk", true)
	local buttonSize = size(CARD_BUTTON)
	local buttons = UIKit.new("Frame", {
		Name = "Buttons",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, textLeft, 1, -20),
		Size = UDim2.new(1, -(textLeft + 16), 0, buttonSize.Y),
		BackgroundTransparency = 1,
		ZIndex = 43,
		Parent = card,
	})
	local join = UIKit.Button({
		Name = "Join",
		Text = "✓ JOIN",
		TextSize = if touch then 30 else 27,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(buttonSize.X, buttonSize.Y),
		CornerRadius = "round",
		ZIndex = 45,
		Parent = buttons,
	}, function()
		answer(true)
	end, Color3.fromRGB(140, 255, 160), GREEN_DARK)
	glowBehind(join, Theme.Colors.Green, cardLoops)
	PartyKit.Shine(join, cardLoops, { ZIndex = 45, Period = 1.4, Strength = 0.5 })
	UIKit.Button({
		Name = "No",
		Text = "NO",
		TextSize = if touch then 28 else 25,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(math.floor(buttonSize.X * 0.62), buttonSize.Y),
		CornerRadius = "round",
		ZIndex = 45,
		Parent = buttons,
	}, function()
		answer(false)
	end, Theme.Colors.Lavender, Theme.Colors.Purple)
	RunService.Heartbeat:Connect(stepCard)
end

-- Name tags --------------------------------------------------------------------------------------------

-- Puts the 👥 on (or takes it off) a player's name tag, the server's PP_Nameplate over their head.
local function markTag(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local plate = head and head:FindFirstChild("PP_Nameplate")
	local name = plate and plate:FindFirstChild("PlayerName")
	if not (name and name:IsA("TextLabel")) then
		return
	end
	local marked = string.sub(name.Text, 1, #MARK) == MARK
	local wanted = partyOf(player) ~= nil
	if wanted and not marked then
		name.Text = MARK .. name.Text
	elseif marked and not wanted then
		name.Text = string.sub(name.Text, #MARK + 1)
	end
end

local function markTags()
	for _, player in Players:GetPlayers() do
		pcall(markTag, player)
	end
end

-- Keeping up ------------------------------------------------------------------------------------------

-- The chip shows when there's someone to party with: alone (bots aren't players), the row's room goes
-- to the 👋 INVITE chip, which brings friends in.
local function refreshChip()
	local someone = #Players:GetPlayers() > 1 or partyOf(me()) ~= nil
	chip:Set("👥", if someone then "PARTY" else "")
end

local function refreshAll()
	refreshChip()
	if window.IsOpen then
		fillWindow()
	end
	refreshCard()
	markTags()
end

queueRefresh = function()
	if refreshQueued then
		return
	end
	refreshQueued = true
	task.defer(function()
		refreshQueued = false
		refreshAll()
	end)
end

-- Asks Roblox once whether someone is my friend (friends go first in the window).
local function askFriend(player: Player)
	if player == me() or friends[player.UserId] ~= nil then
		return
	end
	task.spawn(function()
		local ok, result = pcall(function()
			return me():IsFriendsWithAsync(player.UserId)
		end)
		if ok then
			friends[player.UserId] = result == true
			queueRefresh()
		end
	end)
end

local function watch(player: Player)
	if watched[player] then
		return
	end
	watched[player] = true
	player:GetAttributeChangedSignal("PP_Level"):Connect(function()
		if window.IsOpen then
			queueRefresh()
		end
	end)
	askFriend(player)
end

local function onServer(kind: any, userId: any, name: any, left: any)
	if type(userId) ~= "number" or userId ~= userId then
		return
	end
	if kind == "Invited" and type(name) == "string" and type(left) == "number" then
		local entry: Incoming? = nil
		for _, existing in incoming do
			if existing.From == userId then
				entry = existing
			end
		end
		if entry then
			entry.Name, entry.Left = name, left -- the lobby is back: the time it has left
			entry.Since = if entry == shown then os.clock() else nil
		else
			table.insert(incoming, { From = userId, Name = name, Left = left, Since = nil })
		end
	elseif kind == "InviteGone" then
		for index = #incoming, 1, -1 do
			if incoming[index].From == userId then
				table.remove(incoming, index)
			end
		end
	elseif kind == "Sent" then
		asked[userId] = math.huge
	elseif kind == "Done" then
		asked[userId] = nil
	end
	queueRefresh()
end

-- What's on screen, for the client harness.
function PartyController.Status(): { [string]: any }
	local rows = {}
	if list then
		for _, item in list:GetDescendants() do
			if item:IsA("TextLabel") or item:IsA("TextButton") then
				if item.Text ~= "" then
					table.insert(rows, item.Text)
				end
			end
		end
	end
	local slots = {}
	local squad = list and list:FindFirstChild("Squad", true)
	if squad then
		for slot = 1, PartyLogic.MaxSize do
			local slotFrame = squad:FindFirstChild(`Slot{slot}`)
			local name = slotFrame and slotFrame:FindFirstChild("Name")
			local crown = slotFrame and slotFrame:FindFirstChild("Crown", true)
			local level = slotFrame and slotFrame:FindFirstChild("Level", true)
			local levelText = level and level:FindFirstChild("Text")
			if name and name:IsA("TextLabel") then
				local extras = (if crown and crown:IsA("GuiObject") and crown.Visible then " 👑" else "")
					.. (
						if levelText and levelText:IsA("TextLabel") and level.Visible then ` Lv{levelText.Text}` else ""
					)
				table.insert(slots, name.Text .. extras)
			elseif slotFrame then
				table.insert(slots, "+ INVITE")
			end
		end
	end
	return {
		Chip = if chip then chip.Button.Text else nil,
		ChipShown = if chip then chip.Button.Visible else nil,
		WindowOpen = if window then window.IsOpen else nil,
		Header = if header then `{headerName.Text} | {headerLine.Text}` else nil,
		Streak = if streakPill and streakPill.Visible then streakNumber.Text else nil,
		Slots = slots,
		Window = rows,
		Card = if card and card.Visible then `{cardKicker.Text} | {cardTitle.Text} | {cardParty.Text}` else nil,
		CardParty = if card and card.Visible then cardParty.Text else nil,
		CardTimer = if card and card.Visible
			then math.floor(cardTimer.Right.Rotation + cardTimer.Left.Rotation)
			else nil,
		CardAtTop = if card and card.Visible then cardHolder.AnchorPoint.Y == 0 else nil,
		Waiting = #incoming,
	}
end

function PartyController.Start(context)
	touch = UIKit.IsTouch()
	remote = Remotes.Get("Party")
	PartyView.Start()
	chip = LobbyRibbon.Add(context, {
		Name = "Party",
		Priority = 2.5,
		OnClick = function()
			if window.IsOpen then
				window:Close()
			else
				PartyController.Open()
			end
		end,
		Top = Theme.Colors.Cyan,
		Bottom = CYAN_DARK,
	})
	window = Modal.new(context.Overlay, "PARTY", "👥", size(WINDOW))
	buildHeader()
	list = UIKit.new("ScrollingFrame", {
		Name = "Party",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 22,
		Parent = window.Content,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 10), UIKit.Padding(6, 4) },
	})
	window.Opened:Connect(function()
		PartyKit.SetPlaying(loops, true)
	end)
	window.Closed:Connect(function()
		PartyKit.SetPlaying(loops, false)
		clear(list) -- nothing in it animates while it's shut; it's rebuilt when it opens
		memberFaces = {}
	end)
	PartyKit.SetPlaying(loops, false)
	buildCard(context)
	placeCard(false)
	PartyKit.WhenChild(context.Hud, "Vote", function(child)
		if child:IsA("GuiObject") then
			voteRow = child
			child:GetPropertyChangedSignal("Visible"):Connect(function()
				placeCard(true)
			end)
			placeCard(false)
		end
	end)
	refreshChip()
	task.spawn(function()
		local ok, result = pcall(SocialService.CanSendGameInviteAsync, SocialService, me())
		canInviteFriends = ok and result == true
		queueRefresh()
	end)

	remote.OnClientEvent:Connect(onServer)
	PartyView.Changed:Connect(queueRefresh)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(function(player)
		watch(player)
		queueRefresh()
	end)
	Players.PlayerRemoving:Connect(function(player)
		watched[player] = nil
		asked[player.UserId] = nil
		queueRefresh()
	end)
	-- A round starting closes the window (the rules card is next) and puts the card away.
	GameState.Changed("Phase", function()
		if not lobbyUp() and window.IsOpen then
			window:Close()
		end
		queueRefresh()
	end)
	GameState.Changed("Replay", queueRefresh)
	task.spawn(function()
		while true do
			task.wait(TAG_SWEEP)
			markTags()
		end
	end)
end

return PartyController
