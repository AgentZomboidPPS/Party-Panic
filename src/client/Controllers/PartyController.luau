-- Parties on screen (owner: "stuff to work on right now is parties. The parties work in the way that
-- if you party with others for team games you are on the same team."). The server runs them
-- (Services/PartyService: the PP_Party and PP_PartySeat player attributes, and the "Party" remote);
-- this only shows them and asks.
--   * The 👥 PARTY chip in the lobby's row (UI/LobbyRibbon, priority 2.5: after the cup, before the
--     invite chip) opens the PARTY window: your party (👑 its leader) with LEAVE, and everyone else
--     here with an INVITE each, your Roblox friends (⭐) first. Someone in a full party has no INVITE
--     ("FULL"); someone in another party shows it ("👥 2/4": joining yours takes them out of it). A
--     tapped INVITE says SENT until the answer comes.
--   * An invite comes as a card: "👥 Bubbles invited you to their party!" with JOIN and NO, and a bar
--     running down its 20 seconds. It shows in the lobby only (its time stops under the rules card
--     and in the round, and it comes back after), one at a time. Phones: in the middle of the gap
--     between the MOVE stick's corner and the menu column, under the chips and vote cards and above
--     the toasts and the jump button; thumb-sized buttons. PC: in the middle, under the chips.
--   * Everyone in a party has a 👥 before their name on their name tag (the server's PP_Nameplate),
--     so friends in the lobby can see who's together.
-- Bots are never in parties (they aren't Players, so they're never listed).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameState = require(Shared.GameState)
local PartyLogic = require(Shared.Logic.PartyLogic)
local Remotes = require(Shared.Remotes)

local AudioController = require(script.Parent.AudioController)
local LobbyRibbon = require(script.Parent.Parent.UI.LobbyRibbon)
local Modal = require(script.Parent.Parent.UI.Modal)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local PartyController = {}

type Incoming = { From: number, Name: string, Left: number, Since: number? }

local LOBBY = { Waiting = true, Intermission = true, Voting = true, Cleanup = true }
local MARK = "👥 " -- before a party member's name on their name tag
local SENT_WAIT = 3 -- seconds a tapped INVITE says SENT before the server has said so
local TAG_SWEEP = 1 -- seconds between name tag checks (a new character brings a new tag)

-- Scaled units (UIKit.AutoScale: phones get 0.62 points per unit).
local WINDOW = Vector2.new(620, 600)
local ROW = { Touch = 76, Pc = 50 } -- a player's line in the window: a thumb-sized INVITE on phones
local BUTTON = { Touch = Vector2.new(176, 72), Pc = Vector2.new(140, 44) }
local CARD = { Touch = Vector2.new(500, 236), Pc = Vector2.new(500, 210) }
local CARD_BUTTON = { Touch = Vector2.new(200, 72), Pc = Vector2.new(180, 52) }
-- Where the card's middle is, as a share of the screen's safe area: phones, right of the MOVE stick's
-- zone (its left 40%) and left of the menu column; PC, in the middle under the chips.
local CARD_AT = { Touch = Vector2.new(0.64, 0.52), Pc = Vector2.new(0.5, 0.42) }

local touch = false
local remote: RemoteEvent
local chip: LobbyRibbon.Chip
local window: Modal.Modal
local list: ScrollingFrame
local card: Frame
local cardTitle: TextLabel
local cardBar: Frame
local incoming: { Incoming } = {} -- invites waiting for my answer, oldest first
local shown: Incoming? = nil -- the one on the card
local asked: { [number]: number } = {} -- UserId -> until when my invite to them says SENT
local friends: { [number]: boolean } = {}
local watched: { [any]: boolean } = {}
local refreshQueued = false

local function me(): Player
	return Players.LocalPlayer
end

local function partyOf(player: any): number?
	local id = player:GetAttribute("PP_Party")
	return if type(id) == "number" then id else nil
end

local function seatOf(player: any): number
	local seat = player:GetAttribute("PP_PartySeat")
	return if type(seat) == "number" then seat else math.huge
end

-- The people in a party, its leader first.
local function membersOf(id: number?): { Player }
	local members = {}
	if id == nil then
		return members
	end
	for _, player in Players:GetPlayers() do
		if partyOf(player) == id then
			table.insert(members, player)
		end
	end
	table.sort(members, function(a, b)
		return seatOf(a) < seatOf(b)
	end)
	return members
end

local function lobbyUp(): boolean
	local phase = GameState.Get("Phase") or "Waiting"
	return LOBBY[phase] == true and not (phase == "Cleanup" and (GameState.Get("Replay") or "") ~= "")
end

local function size(pair: { Touch: any, Pc: any }): any
	return if touch then pair.Touch else pair.Pc
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

-- A heading with an optional button at its right end.
local function heading(order: number, text: string): Frame
	local frame = line(order, size(BUTTON).Y)
	label({
		Name = "Heading",
		Text = text,
		Font = Theme.Fonts.Display,
		TextSize = 26,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -(size(BUTTON).X + 12), 1, 0),
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
		TextSize = Theme.Touch.MinText,
		TextColor3 = color or Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromScale(1, 1),
		Parent = frame,
	})
	words:SetAttribute("PP_Lines", 2)
end

local function rowFrame(order: number, height: number, mine: boolean): Frame
	local frame = line(order, height)
	frame.BackgroundTransparency = if mine then 0.15 else 0.45
	frame.BackgroundColor3 = Theme.Colors.PanelDark
	UIKit.Corner(12).Parent = frame
	return frame
end

local function nameLabel(frame: Frame, text: string, rightRoom: number, color: Color3?)
	local name = label({
		Name = "Name",
		Text = text,
		TextSize = 22,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = color or Theme.Colors.Text,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -(rightRoom + 24), 1, 0),
		Parent = frame,
	})
	name:SetAttribute("PP_TruncateOk", true) -- a long name may end in "..."
end

local function pill(frame: Frame, text: string, onClick: (() -> ())?, top: Color3, bottom: Color3): TextButton
	local button = UIKit.Button({
		Name = "Action",
		Text = text,
		TextSize = if touch then 26 else 22,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(size(BUTTON).X, size(BUTTON).Y),
		CornerRadius = "round",
		AutoButtonColor = false,
		Active = onClick ~= nil,
		Parent = frame,
	}, onClick, top, bottom)
	return button
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

local function fillWindow()
	clear(list)
	local mine = partyOf(me())
	local members = membersOf(mine)
	local full = #members >= PartyLogic.MaxSize
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	-- Your party.
	if mine then
		local top = heading(nextOrder(), `YOUR PARTY {#members}/{PartyLogic.MaxSize}`)
		pill(top, "LEAVE", function()
			remote:FireServer("Leave")
		end, Theme.Colors.Orange, Color3.fromRGB(215, 95, 40))
		for _, member in members do
			local row = rowFrame(nextOrder(), 44, member == me())
			local mark = if seatOf(member) == 1 then "👑" else "👥"
			nameLabel(row, `{mark} {member.DisplayName}{if member == me() then " (you)" else ""}`, 0)
		end
		note(nextOrder(), "Your party plays on one team in team games.")
	else
		heading(nextOrder(), "YOUR PARTY")
		note(nextOrder(), "You're on your own. Invite people below: a party plays on one team in team games!")
	end

	-- Everyone else.
	heading(nextOrder(), "INVITE")
	if full then
		note(nextOrder(), `Your party is full ({PartyLogic.MaxSize} at most).`, Theme.Colors.Yellow)
	end
	local people = others(mine)
	if #people == 0 then
		note(nextOrder(), "Nobody else is here yet. Invite friends to the game with 👋 INVITE!")
	end
	for _, player in people do
		local theirs = partyOf(player)
		local theirSize = #membersOf(theirs)
		local theyreFull = theirSize >= PartyLogic.MaxSize
		local row = rowFrame(nextOrder(), size(ROW), false)
		local status = if theirs then ` · 👥 {theirSize}/{PartyLogic.MaxSize}` else ""
		local friend = if friends[player.UserId] then "⭐ " else ""
		nameLabel(row, `{friend}{player.DisplayName}{status}`, size(BUTTON).X)
		if theyreFull then
			pill(row, "FULL", nil, Theme.Colors.PanelLight, Theme.Colors.Panel)
		elseif waitingFor(player.UserId) then
			pill(row, "SENT ✓", nil, Theme.Colors.Lavender, Theme.Colors.Purple)
		elseif not full then
			local userId = player.UserId
			pill(row, "INVITE", function()
				invite(userId)
			end, Theme.Colors.Green, Color3.fromRGB(60, 160, 90))
		end
	end
end

-- Opens the PARTY window (the chip does; so does the client harness).
function PartyController.Open()
	fillWindow()
	window:Open()
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
		cardTitle.Text = `👥 {entry.Name} invited you to their party!`
		card.Visible = true
		UIKit.PopIn(card, 0.3)
		AudioController.Play("Pickup")
	end
	card.Visible = shown ~= nil
end

local function stepCard()
	local entry = shown
	if not entry then
		return
	end
	local left = timeLeft(entry)
	cardBar.Size = UDim2.fromScale(math.clamp(left / PartyLogic.InviteSeconds, 0, 1), 1)
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

local function buildCard(context)
	local dims = size(CARD)
	local at = size(CARD_AT)
	card = UIKit.Panel({
		Name = "PartyInvite",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(at.X, at.Y),
		Size = UDim2.fromOffset(dims.X, dims.Y),
		Visible = false,
		ZIndex = 40,
		CornerRadius = 22,
		Parent = context.Overlay,
	}, Color3.fromRGB(70, 150, 255), Color3.fromRGB(60, 52, 170))
	UIKit.AutoScale(card)
	cardTitle = label({
		Name = "Title",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 27,
		Position = UDim2.fromOffset(18, 12),
		Size = UDim2.new(1, -36, 0, 70),
		ZIndex = 41,
		Parent = card,
		Children = { UIKit.TextStroke(0.15) },
	})
	cardTitle:SetAttribute("PP_Lines", 2)
	label({
		Name = "Why",
		Text = "Party up to play on the same team!",
		TextSize = Theme.Touch.MinText,
		TextColor3 = Color3.fromRGB(225, 235, 255),
		Position = UDim2.fromOffset(18, 82),
		Size = UDim2.new(1, -36, 0, 26),
		ZIndex = 41,
		Parent = card,
	})
	local buttons = UIKit.new("Frame", {
		Name = "Buttons",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.new(1, -36, 0, size(CARD_BUTTON).Y),
		BackgroundTransparency = 1,
		ZIndex = 41,
		Parent = card,
		Children = { UIKit.List(Enum.FillDirection.Horizontal, 20, Enum.HorizontalAlignment.Center) },
	})
	local buttonSize = size(CARD_BUTTON)
	UIKit.Button({
		Name = "Join",
		Text = "✓ JOIN",
		TextSize = if touch then 30 else 26,
		Size = UDim2.fromOffset(buttonSize.X, buttonSize.Y),
		CornerRadius = "round",
		LayoutOrder = 1,
		ZIndex = 42,
		Parent = buttons,
	}, function()
		answer(true)
	end, Theme.Colors.Green, Color3.fromRGB(60, 160, 90))
	UIKit.Button({
		Name = "No",
		Text = "NO",
		TextSize = if touch then 30 else 26,
		Size = UDim2.fromOffset(buttonSize.X * 0.7, buttonSize.Y),
		CornerRadius = "round",
		LayoutOrder = 2,
		ZIndex = 42,
		Parent = buttons,
	}, function()
		answer(false)
	end, Theme.Colors.Lavender, Theme.Colors.Purple)
	-- The time left to answer: a bar along the bottom edge that runs down.
	local track = UIKit.new("Frame", {
		Name = "Time",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -9),
		Size = UDim2.new(1, -44, 0, 8),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ZIndex = 41,
		Parent = card,
		Children = { UIKit.Round() },
	})
	cardBar = UIKit.new("Frame", {
		Name = "Bar",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Yellow,
		BorderSizePixel = 0,
		ZIndex = 42,
		Parent = track,
		Children = { UIKit.Round() },
	})
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

local function refreshChip()
	chip:Set("👥", "PARTY")
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
	player:GetAttributeChangedSignal("PP_Party"):Connect(queueRefresh)
	player:GetAttributeChangedSignal("PP_PartySeat"):Connect(queueRefresh)
	askFriend(player)
end

local function onServer(kind: any, userId: any, name: any, left: any)
	if type(userId) ~= "number" then
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
	return {
		Chip = if chip then chip.Button.Text else nil,
		ChipShown = if chip then chip.Button.Visible else nil,
		WindowOpen = if window then window.IsOpen else nil,
		Window = rows,
		Card = if card and card.Visible then cardTitle.Text else nil,
		Waiting = #incoming,
	}
end

function PartyController.Start(context)
	touch = UIKit.IsTouch()
	remote = Remotes.Get("Party")
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
		Bottom = Color3.fromRGB(40, 140, 230),
	})
	window = Modal.new(context.Overlay, "PARTY", "👥", WINDOW)
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
		Children = { UIKit.List(Enum.FillDirection.Vertical, 8), UIKit.Padding(4, 4) },
	})
	buildCard(context)
	refreshChip()

	remote.OnClientEvent:Connect(onServer)
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
