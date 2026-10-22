-- Renders the in-world screens from replicated state: the vote stage's four portals (each plays a
-- preview of its vote option's game) and the giant vote cards above them, the announcement board,
-- the personal quest board, the champion board and podium name tags (a bot champion gets a robot
-- portrait: bots have no Roblox avatar to show).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameDefinitions = require(Shared.GameDefinitions)
local GameState = require(Shared.GameState)
local Placement = require(Shared.Logic.Placement)
local QuestDefinitions = require(Shared.QuestDefinitions)

local Participants = require(script.Parent.Parent.Participants)
local State = require(script.Parent.Parent.State)
local Flipbook = require(script.Parent.Parent.UI.Flipbook)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local WorldScreensController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function surface(part: BasePart, face: Enum.NormalId, pixelsPerStud: number?): SurfaceGui
	return UIKit.new("SurfaceGui", {
		Name = "Screen_" .. part.Name,
		Adornee = part,
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = pixelsPerStud or 24,
		LightInfluence = 0,
		Brightness = 1.4,
		MaxDistance = 400,
		ResetOnSpawn = false,
		Parent = playerGui,
	})
end

-- Runs `callback` for every instance with `tag`, now and whenever one is added later. The server
-- builds the lobby over several seconds, so tagged screens can replicate after this script starts.
local function onTag(tag: string, callback: (Instance) -> ())
	for _, instance in CollectionService:GetTagged(tag) do
		task.spawn(callback, instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(callback)
end

local function phaseTitle(phase: string): string
	local gameId = GameState.Get("GameId")
	local definition = gameId ~= "" and GameDefinitions.Get(gameId)
	if phase == "Voting" then
		return "🗳️ VOTE NOW!"
	elseif phase == "Preparing" or phase == "InRound" then
		return if definition then `{definition.Icon} {string.upper(definition.Name)}` else "ROUND IN PROGRESS"
	elseif phase == "Results" then
		return "🏆 RESULTS"
	elseif phase == "Waiting" then
		return "⏳ " .. string.upper(GameState.Get("Message") or "WAITING")
	end
	return "🎉 PARTY PANIC"
end

local function buildAnnouncement(part: BasePart)
	local gui = surface(part, Enum.NormalId.Back, 20)
	local title = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextScaled = true,
		Size = UDim2.fromScale(1, 0.62),
		Parent = gui,
		Children = { UIKit.Padding(8, 16) },
	})
	local sub = UIKit.Label({
		Text = "",
		TextScaled = true,
		TextColor3 = Theme.Colors.Yellow,
		Position = UDim2.fromScale(0, 0.6),
		Size = UDim2.fromScale(1, 0.36),
		Parent = gui,
		Children = { UIKit.Padding(4, 16) },
	})
	RunService.Heartbeat:Connect(function()
		local phase = GameState.Get("Phase")
		title.Text = phaseTitle(phase)
		local left = GameState.TimeLeft()
		if phase == "Intermission" then
			sub.Text = `Next vote in {UIKit.FormatTime(left)}`
		elseif phase == "Voting" then
			sub.Text = `Tap a card to vote • {UIKit.FormatTime(left)}`
		elseif phase == "InRound" then
			sub.Text = `{GameState.Get("Status") or ""}  •  {UIKit.FormatTime(left)}`
		elseif phase == "Preparing" then
			sub.Text = "Get ready..."
		else
			sub.Text = GameState.Get("Message") or ""
		end
	end)
end

-- The portals ------------------------------------------------------------------------------------
-- Each portal on the vote stage plays a little looping preview of its vote option's game (owner:
-- "the portals being how you vote is dumb. maybe we make the portal do a little video of what the
-- game actually is?"): the game's sheet from Shared/GamePreviews as a flipbook (UI/Flipbook), with
-- its icon and name over it. A game without a preview, or while its image loads (or if it never
-- does), shows its card instead: the icon on the game's color. Random (the 4th card) spins the
-- previews like a slot machine reel under a big 🎲 and "?", and lands on its game if it wins.
-- Between votes the portals take turns showing every game. Reduced effects: the previews hold
-- still and the reel doesn't spin.

local ATTRACT_SECONDS = 7 -- between votes, each portal moves on to another game this often
local REEL_SPEED = 2.6 -- Random's reel, in previews per second
local REVEAL_TIME = 2 -- Random's reel slowing down onto the game that won
local ANIMATE_RANGE = 420 -- the screens aren't drawn from further away (SurfaceGui MaxDistance)
local RANDOM_COLOR = Color3.fromRGB(150, 110, 255)

type Tile = {
	frame: Frame,
	gradient: UIGradient,
	icon: TextLabel,
	book: Flipbook.Flipbook,
	gameId: string?,
}

type Portal = {
	index: number,
	part: BasePart,
	main: Tile,
	reel: { Tile },
	reelFrame: Frame,
	badge: TextLabel,
	name: TextLabel,
	ribbon: TextLabel,
	question: TextLabel,
	dim: Frame,
	flash: Frame,
	mode: string, -- Attract, Vote, Mystery, Reveal, Winner, Loser
	gameId: string?,
	reelPos: number,
	reelQueue: { string },
	reelNext: number,
	revealFrom: number,
	revealStarted: number,
}

local portals: { [number]: Portal } = {}
local portalChanged = Instance.new("BindableEvent") -- (index): a portal shows another game
local showcase: { string } = {} -- the games the portals show between votes and on Random's reel
local vote = { Phase = "", Options = {} :: { { Id: string, Mystery: boolean } }, GameId = "", Mine = 0 }

local function darker(color: Color3): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, math.min(1, s * 1.1), v * 0.55)
end

-- Every game with a preview, or every game if none has one yet (they show as cards).
local function showcaseGames(): { string }
	local ids, all = {}, {}
	for _, definition in GameDefinitions.List do
		if definition.Enabled ~= false then
			table.insert(all, definition.Id)
			if Flipbook.PreviewOf(definition.Id) then
				table.insert(ids, definition.Id)
			end
		end
	end
	return if #ids > 0 then ids else all
end

local function newTile(parent: Instance): Tile
	local frame = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = parent,
	})
	local gradient = UIKit.Gradient(RANDOM_COLOR, darker(RANDOM_COLOR))
	gradient.Parent = frame
	local icon = UIKit.Label({
		Text = "",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromScale(0.7, 0.3),
		ZIndex = 1,
		Parent = frame,
	})
	local image = UIKit.new("ImageLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = frame,
	})
	return { frame = frame, gradient = gradient, icon = icon, book = Flipbook.new(image), gameId = nil }
end

-- Puts a game on a tile: its preview playing from `clock` seconds in, over its card. nil: Random's.
local function showGame(tile: Tile, gameId: string?, clock: number?)
	tile.gameId = gameId
	local definition = if gameId then GameDefinitions.Get(gameId) else nil
	local color = if definition then definition.Color else RANDOM_COLOR
	tile.gradient.Color = ColorSequence.new(color, darker(color))
	tile.icon.Text = if definition then definition.Icon else "🎲"
	tile.book:Show(Flipbook.PreviewOf(gameId), clock)
end

-- What portal `index` should show now: its vote option during the vote and the reveal, or its
-- turn of the showcase.
local function portalTarget(index: number, now: number): (string, string?)
	local option = vote.Options[index]
	if option and (vote.Phase == "Voting" or vote.Phase == "Preparing") then
		if vote.Phase == "Voting" then
			return if option.Mystery then "Mystery" else "Vote", option.Id
		elseif vote.GameId ~= option.Id then
			return "Loser", if option.Mystery then nil else option.Id
		end
		return if option.Mystery then "Reveal" else "Winner", option.Id
	end
	if #showcase == 0 then
		return "Attract", nil
	end
	local turn = math.floor((now + index * 0.6) / ATTRACT_SECONDS)
	return "Attract", showcase[(turn + index - 1) % #showcase + 1]
end

-- Random's reel: two tiles sliding down, the lower one going back on top with the next game.
local function nextReelGame(portal: Portal): string
	if #portal.reelQueue > 0 then
		return table.remove(portal.reelQueue, 1) :: string
	end
	portal.reelNext = portal.reelNext % #showcase + 1
	return showcase[portal.reelNext]
end

local function setReel(portal: Portal, position: number)
	while math.floor(position) > math.floor(portal.reelPos) do
		portal.reelPos = math.floor(portal.reelPos) + 1
		portal.reel[1], portal.reel[2] = portal.reel[2], portal.reel[1]
		showGame(portal.reel[2], nextReelGame(portal))
	end
	portal.reelPos = position
	local offset = position % 1
	portal.reel[1].frame.Position = UDim2.fromScale(0, offset)
	portal.reel[2].frame.Position = UDim2.fromScale(0, offset - 1)
end

local function setPortal(portal: Portal, mode: string, gameId: string?, now: number, reduced: boolean)
	local previousMode = portal.mode
	portal.mode = mode
	portal.gameId = gameId
	local definition = if gameId then GameDefinitions.Get(gameId) else nil
	local mystery = mode == "Mystery" or mode == "Reveal" or (mode == "Loser" and gameId == nil)
	local spinning = (mode == "Mystery" or mode == "Reveal") and #showcase > 0 and not reduced
	portal.reelFrame.Visible = spinning
	portal.question.Visible = mode == "Mystery"
	portal.dim.BackgroundTransparency = if mode == "Loser" then 0.5 else 1
	portal.badge.Text = if mystery or not definition then "🎲" else definition.Icon
	portal.name.Text = if mystery or not definition then "RANDOM" else string.upper(definition.Name)
	if spinning then
		showGame(portal.main, nil)
		if mode == "Mystery" or previousMode ~= "Mystery" then
			-- A fresh spin from a random spot in the showcase.
			portal.reelQueue = {}
			portal.reelNext = math.random(1, #showcase)
			portal.reelPos = 0
			showGame(portal.reel[1], nextReelGame(portal))
			showGame(portal.reel[2], nextReelGame(portal))
			setReel(portal, 0)
		end
		if mode == "Reveal" and gameId then
			-- Slow down over three more previews and stop on the game that won (see setReel).
			local other = showcase[math.random(1, #showcase)]
			portal.reelQueue = { other, gameId, other }
			portal.revealFrom = portal.reelPos
			portal.revealStarted = now
		end
	else
		-- Portals showing the same game start at different points of its loop; Random's reel hands
		-- over on the frame it stopped at.
		showGame(
			portal.main,
			if mystery then nil else gameId,
			if previousMode == "Reveal" then 0 else portal.index * 0.7
		)
		if not reduced and previousMode ~= "" then
			portal.flash.BackgroundTransparency = 0.15
			UIKit.Tween(portal.flash, 0.45, { BackgroundTransparency = 1 })
		end
	end
	portalChanged:Fire(portal.index)
end

local function refreshRibbon(portal: Portal)
	local mode = portal.mode
	local text, color = "", Theme.Colors.Green
	if (mode == "Vote" or mode == "Mystery") and vote.Mine == portal.index then
		text = "✓ YOUR VOTE"
	elseif mode == "Winner" then
		local option = vote.Options[portal.index]
		text, color = if option and option.Mystery then "🎲 RANDOM PICK!" else "🏆 WINNER!", Theme.Colors.Yellow
	end
	if portal.ribbon.Text ~= text then
		portal.ribbon.Text = text
		portal.ribbon.BackgroundColor3 = color
		portal.ribbon.Visible = text ~= ""
	end
end

local function updatePortal(portal: Portal, dt: number, now: number, reduced: boolean)
	local mode, gameId = portalTarget(portal.index, now)
	if portal.mode == "Winner" and mode == "Reveal" then
		mode = "Winner" -- Random's reel has landed on it
	end
	if mode ~= portal.mode or gameId ~= portal.gameId then
		setPortal(portal, mode, gameId, now, reduced)
	end
	if portal.mode == "Reveal" and portal.reelFrame.Visible then
		local t = math.clamp((now - portal.revealStarted) / REVEAL_TIME, 0, 1)
		local target = math.floor(portal.revealFrom) + 3
		setReel(portal, portal.revealFrom + (target - portal.revealFrom) * (1 - (1 - t) ^ 3))
		if t >= 1 then
			setPortal(portal, "Winner", portal.gameId, now, true) -- the same picture, now playing
		end
	elseif portal.mode == "Reveal" then
		setPortal(portal, "Winner", portal.gameId, now, reduced) -- reduced effects: no reel
	elseif portal.mode == "Mystery" then
		if portal.reelFrame.Visible and not reduced then
			setReel(portal, portal.reelPos + dt * REEL_SPEED)
		end
	elseif portal.mode ~= "Loser" then
		portal.main.book:Step(dt, if reduced then 0 else 1)
	end
	refreshRibbon(portal)
end

local function buildPortal(part: BasePart)
	local index = part:GetAttribute("VoteIndex") :: number
	local color = part:GetAttribute("PortalColor") :: Color3? or Theme.Colors.PanelLight
	local gui = surface(part, Enum.NormalId.Back, 18)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Brightness = 1.2
	local root = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = gui,
	})
	local main = newTile(root)
	local reelFrame = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Visible = false,
		ZIndex = 2,
		Parent = root,
	})
	local reel = { newTile(reelFrame), newTile(reelFrame) }
	local question = UIKit.Label({
		Text = "?",
		Font = Theme.Fonts.Display,
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.64),
		Size = UDim2.fromScale(0.8, 0.4),
		Visible = false,
		ZIndex = 3,
		Parent = root,
		Children = {
			UIKit.new("UIStroke", {
				Color = Color3.fromRGB(30, 15, 60),
				Thickness = 6,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			}),
		},
	})
	-- The game's icon in a medallion in the round top, its name on a plate under it: high on the
	-- portal, where people standing on the stage don't hide it.
	local medallion = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.135),
		Size = UDim2.fromScale(0.32, 0.32),
		SizeConstraint = Enum.SizeConstraint.RelativeXX,
		BackgroundColor3 = darker(color),
		ZIndex = 4,
		Parent = root,
		Children = { UIKit.Round(), UIKit.Stroke(Color3.new(1, 1, 1), 4, 0) },
	})
	local badge = UIKit.Label({
		Text = "",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.7, 0.7),
		Parent = medallion,
	})
	local plate = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.265),
		Size = UDim2.fromScale(0.94, 0.115),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.15,
		ZIndex = 4,
		Parent = root,
		Children = { UIKit.Round(), UIKit.Stroke(color, 3, 0) },
	})
	local name = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
		Parent = plate,
		Children = { UIKit.Padding(5, 12), UIKit.TextStroke(0.3) },
	})
	local ribbon = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.395),
		Size = UDim2.fromScale(0.74, 0.075),
		BackgroundTransparency = 0,
		Visible = false,
		ZIndex = 4,
		Parent = root,
		Children = { UIKit.Round(), UIKit.Padding(3, 10), UIKit.TextStroke(0.3) },
	})
	local dim = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = root,
	})
	local flash = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = root,
	})
	portals[index] = {
		index = index,
		part = part,
		main = main,
		reel = reel,
		reelFrame = reelFrame,
		badge = badge,
		name = name,
		ribbon = ribbon,
		question = question,
		dim = dim,
		flash = flash,
		mode = "",
		gameId = nil,
		reelPos = 0,
		reelQueue = {},
		reelNext = 0,
		revealFrom = 0,
		revealStarted = 0,
	}
	-- The glowing film in the opening would wash the picture out: it's only the server's look.
	for _, film in CollectionService:GetTagged("PortalFilm") do
		if film:GetAttribute("VoteIndex") == index then
			(film :: BasePart).Transparency = 1
		end
	end
end

local function startPortals()
	showcase = showcaseGames()
	local function readVote()
		vote.Phase = GameState.Get("Phase") or ""
		vote.Options = GameState.GetJSON("VoteOptions") or {}
		vote.GameId = GameState.Get("GameId") or ""
	end
	GameState.Changed("Phase", readVote)
	GameState.Changed("VoteOptions", readVote)
	GameState.Changed("GameId", readVote)
	readVote()
	local function readMine()
		vote.Mine = player:GetAttribute("PP_Vote") or 0
	end
	player:GetAttributeChangedSignal("PP_Vote"):Connect(readMine)
	readMine()

	onTag("PortalScreen", function(part)
		buildPortal(part :: BasePart)
	end)
	onTag("PortalFilm", function(film)
		if portals[film:GetAttribute("VoteIndex") :: number] then
			(film :: BasePart).Transparency = 1
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		local camera = workspace.CurrentCamera
		local now = workspace:GetServerTimeNow() -- everyone sees the same game on the same portal
		local reduced = State.ReducedEffects()
		for _, portal in portals do
			if camera and (camera.CFrame.Position - portal.part.Position).Magnitude > ANIMATE_RANGE then
				continue
			end
			updatePortal(portal, dt, now, reduced)
		end
	end)
end

local function buildVoteScreen(part: BasePart)
	local index = part:GetAttribute("VoteIndex") :: number
	local gui = surface(part, Enum.NormalId.Back, 22)
	local frame = UIKit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
	local icon = UIKit.Label({
		Text = "",
		TextScaled = true,
		Size = UDim2.fromScale(0.28, 0.5),
		Position = UDim2.fromScale(0.02, 0.05),
		Parent = frame,
	})
	local name = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromScale(0.68, 0.3),
		Position = UDim2.fromScale(0.3, 0.06),
		Parent = frame,
	})
	local category = UIKit.Label({
		Text = "",
		TextScaled = true,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromScale(0.68, 0.16),
		Position = UDim2.fromScale(0.3, 0.36),
		Parent = frame,
	})
	local objective = UIKit.Label({
		Text = "",
		TextScaled = true,
		Size = UDim2.fromScale(0.94, 0.22),
		Position = UDim2.fromScale(0.03, 0.55),
		Parent = frame,
	})
	local barBack = UIKit.new("Frame", {
		Size = UDim2.fromScale(0.94, 0.12),
		Position = UDim2.fromScale(0.03, 0.82),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = frame,
		Children = { UIKit.Round() },
	})
	local bar = UIKit.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Colors.Yellow,
		Parent = barBack,
		Children = { UIKit.Round() },
	})
	local votes = UIKit.Label({
		Text = "",
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
		Font = Theme.Fonts.Display,
		TextColor3 = Theme.Colors.PanelDark,
		Parent = barBack,
	})

	local function refresh()
		local phase = GameState.Get("Phase")
		local options = GameState.GetJSON("VoteOptions") or {}
		local counts = GameState.GetJSON("VoteCounts") or {}
		local option = options[index]
		local showVote = (phase == "Voting" or phase == "Preparing") and option ~= nil
		frame.Visible = true
		votes.TextColor3 = if showVote then Theme.Colors.PanelDark else Theme.Colors.Text
		if not showVote then
			-- Between votes: about the game the portal below is showing.
			local portal = portals[index]
			local shown = if portal and portal.gameId then GameDefinitions.Get(portal.gameId) else nil
			local shownCategory = shown and GameDefinitions.Categories[shown.Category]
			icon.Text = if shown then shown.Icon else "🎉"
			name.Text = if shown then shown.Name else "PARTY PANIC"
			category.Text = if shown
				then `{shownCategory and shownCategory.Icon or ""} {shown.Category} • ~{shown.Duration}s`
				else "Games appear here at vote time"
			objective.Text = if shown then shown.Objective else ""
			bar.Size = UDim2.fromScale(0, 1)
			votes.Text = if phase == "Intermission" then `Next vote in {UIKit.FormatTime(GameState.TimeLeft())}` else ""
			return
		end
		local definition = GameDefinitions.Get(option.Id)
		local revealed = not option.Mystery or (phase == "Preparing" and GameState.Get("GameId") == option.Id)
		if definition and revealed then
			icon.Text = definition.Icon
			name.Text = definition.Name
			local categoryInfo = GameDefinitions.Categories[definition.Category]
			category.Text =
				`{categoryInfo and categoryInfo.Icon or ""} {definition.Category} • ~{definition.Duration}s`
			objective.Text = definition.Objective
		else
			icon.Text = "🎲"
			name.Text = "RANDOM"
			category.Text = "Any game - revealed if it wins!"
			objective.Text = "Feeling lucky?"
		end
		local total = 0
		for _, count in counts do
			total += count
		end
		local mine = counts[index] or 0
		UIKit.Tween(bar, 0.25, { Size = UDim2.fromScale(if total > 0 then mine / total else 0, 1) })
		votes.Text = `{mine} vote{if mine == 1 then "" else "s"}`
	end
	GameState.Changed("VoteOptions", refresh)
	GameState.Changed("VoteCounts", refresh)
	GameState.Changed("Phase", refresh)
	GameState.Changed("GameId", refresh)
	portalChanged.Event:Connect(function(changed: number)
		if changed == index then
			refresh()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if GameState.Get("Phase") == "Intermission" then
				refresh()
			end
		end
	end)
	refresh()
end

local function buildQuestBoard(part: BasePart)
	local gui = surface(part, Enum.NormalId.Front, 28)
	local list = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 6), UIKit.Padding(14) },
	})
	local function refresh()
		for _, child in list:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		UIKit.Label({
			Text = "📜 YOUR QUESTS",
			Font = Theme.Fonts.Display,
			TextSize = 44,
			Size = UDim2.new(1, 0, 0, 52),
			LayoutOrder = 0,
			Parent = list,
		})
		local profile = State.Profile
		if not profile then
			return
		end
		local order = 1
		for _, period in { "Daily", "Weekly" } do
			for _, quest in profile.Quests[period] do
				local def = QuestDefinitions.ById[quest.Id]
				if def then
					local mark = if quest.Done then "✅" else `{quest.Progress}/{def.Target}`
					UIKit.Label({
						Text = `{if period == "Weekly" then "⭐ " else ""}{def.Text}  —  {mark}`,
						TextSize = 30,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextColor3 = if quest.Done then Theme.Colors.Green else Theme.Colors.Text,
						Size = UDim2.new(1, 0, 0, 38),
						LayoutOrder = order,
						Parent = list,
					})
					order += 1
				end
			end
		end
	end
	State.ProfileChanged:Connect(refresh)
	refresh()
end

local thumbnails: { [number]: string } = {}
local function headshot(userId: number): string
	if Participants.IsBotId(userId) then
		return "" -- no Roblox avatar (GetUserThumbnailAsync fails for a bot's negative id)
	end
	if not thumbnails[userId] then
		local ok, url = pcall(
			Players.GetUserThumbnailAsync,
			Players,
			userId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size150x150
		)
		thumbnails[userId] = if ok then url else ""
	end
	return thumbnails[userId]
end

type PodiumTag = {
	image: ImageLabel,
	robot: TextLabel,
	glow: UIGradient,
	label: TextLabel,
	gui: BillboardGui,
	userId: number?,
}

-- Puts a champion's face on a podium tag: their headshot, or a robot on the bot's own color.
local function showPortrait(tag: PodiumTag, userId: number)
	tag.userId = userId
	local isBot = Participants.IsBotId(userId)
	tag.robot.Visible = isBot
	tag.glow.Enabled = isBot
	if isBot then
		local bot = Participants.FromUserId(userId)
		tag.image.Image = ""
		tag.image.BackgroundColor3 = bot and bot.Color or Theme.Colors.Cyan
		return
	end
	tag.image.BackgroundColor3 = Theme.Colors.Panel
	task.spawn(function()
		local url = headshot(userId)
		if tag.userId == userId then -- still this champion's spot (a new round may have finished)
			tag.image.Image = url
		end
	end)
end

local function buildChampions()
	local tags: { [number]: PodiumTag } = {}
	local boardText: TextLabel? = nil

	local function refresh()
		local champions = GameState.GetJSON("Champions") or {}
		local lines = { "🏆 LAST ROUND" }
		for place, tag in tags do
			local champion = nil
			for _, entry in champions do
				if entry.Place == place and not champion then
					champion = entry
				end
			end
			tag.gui.Enabled = champion ~= nil
			if champion then
				tag.label.Text = champion.Name
				showPortrait(tag, champion.UserId)
			end
		end
		for _, entry in champions do
			table.insert(lines, `{Placement.Ordinal(entry.Place)}  {entry.Name}`)
		end
		if #champions == 0 then
			table.insert(lines, "Win a round to\nclaim the podium!")
		end
		if boardText then
			boardText.Text = table.concat(lines, "\n")
		end
	end
	-- Podium spots and the board are bound as they appear (the lobby builds over a few seconds).
	onTag("PodiumSpot", function(instance)
		local spot = instance :: BasePart
		local place = spot:GetAttribute("Place") :: number
		local gui = UIKit.new("BillboardGui", {
			Adornee = spot,
			Size = UDim2.fromOffset(150, 170),
			MaxDistance = 140,
			LightInfluence = 0,
			ResetOnSpawn = false,
			Parent = playerGui,
		})
		local glow = UIKit.Gradient(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 170))
		glow.Enabled = false
		local image = UIKit.new("ImageLabel", {
			Size = UDim2.fromOffset(110, 110),
			Position = UDim2.fromOffset(20, 0),
			BackgroundColor3 = Theme.Colors.Panel,
			Parent = gui,
			Children = { UIKit.Round(), UIKit.Stroke(Theme.Colors.Yellow, 3, 0), glow },
		})
		local robot = UIKit.Label({
			Name = "Robot",
			Text = "🤖",
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.fromScale(0.68, 0.68),
			Visible = false,
			Parent = image,
		})
		local label = UIKit.Label({
			Text = "",
			Font = Theme.Fonts.Display,
			TextSize = 24,
			Position = UDim2.fromOffset(0, 116),
			Size = UDim2.new(1, 0, 0, 50),
			Parent = gui,
			Children = { UIKit.TextStroke(0.2) },
		})
		label:SetAttribute("PP_Lines", 2) -- a long name takes two lines under the picture
		tags[place] = { image = image, robot = robot, glow = glow, label = label, gui = gui, userId = nil }
		refresh()
	end)
	onTag("ChampionBoard", function(instance)
		local gui = surface(instance :: BasePart, Enum.NormalId.Left, 20)
		boardText = UIKit.Label({
			Text = "",
			TextScaled = true,
			Size = UDim2.fromScale(1, 1),
			Font = Theme.Fonts.Display,
			Parent = gui,
			Children = { UIKit.Padding(18) },
		})
		refresh()
	end)

	GameState.Changed("Champions", refresh)
	Participants.Changed:Connect(refresh) -- a bot champion's color, once the bots have loaded in
	refresh()
end

-- Hide today's secret token for players who already found it. The token's Day attribute is the
-- day it's for (it moves at midnight UTC), so it shows again for the new day without waiting for
-- a new profile.
local function bindSecretToken()
	local lobby = workspace:WaitForChild("Lobby", 30)
	local token = lobby and lobby:WaitForChild("SecretToken", 30) :: BasePart?
	if not token then
		return
	end
	local function refresh()
		local daily = State.Profile and State.Profile.Daily
		local tokenDay = token:GetAttribute("Day")
		local found
		if daily and type(daily.SecretDay) == "number" and type(tokenDay) == "number" then
			found = daily.SecretDay >= tokenDay
		else
			found = daily ~= nil and daily.SecretFound == true
		end
		token.LocalTransparencyModifier = if found then 1 else 0
		local sparkles = token:FindFirstChildOfClass("Sparkles")
		if sparkles then
			sparkles.Enabled = not found
		end
	end
	State.ProfileChanged:Connect(refresh)
	token:GetAttributeChangedSignal("Day"):Connect(refresh)
	refresh()
	-- Its gentle bob and spin, drawn here (the server only says where it is: its Spot), and only
	-- while it's near enough to see.
	local angle = 0
	RunService.RenderStepped:Connect(function(dt)
		local spot = token:GetAttribute("Spot")
		local camera = workspace.CurrentCamera
		if typeof(spot) ~= "Vector3" or not camera or (camera.CFrame.Position - spot).Magnitude > 250 then
			return
		end
		angle += dt * 1.5
		token.CFrame = CFrame.new(spot + Vector3.new(0, math.sin(angle * 2) * 0.3, 0)) * CFrame.Angles(0, angle, 0)
	end)
end

function WorldScreensController.Start(_context)
	onTag("AnnouncementScreen", function(part)
		buildAnnouncement(part :: BasePart)
	end)
	startPortals()
	onTag("VoteScreen", function(part)
		buildVoteScreen(part :: BasePart)
	end)
	onTag("QuestBoard", function(part)
		buildQuestBoard(part :: BasePart)
	end)
	buildChampions()
	task.spawn(bindSecretToken)
end

return WorldScreensController
