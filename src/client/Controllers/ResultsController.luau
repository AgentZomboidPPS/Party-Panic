-- Results screen (design doc §12): placement, standings, an itemized reward breakdown and a
-- "next vote soon" cue. Short and skippable; it closes itself when the lobby returns. Bots' names
-- in the standings are a little softer than people's (Participants).
-- The breakdown includes the first win of the day's bonus, and a round that levels you up says so
-- in place of the "next vote" cue (owner: "Also we need cool payoffs for players that keep playing
-- the game.").
--
-- Extra coins from what keeps players coming back (Services/Boosts: a friend in the round, double
-- coins weekends) are lines of their own; six lines or more draw compact so they fit a phone, and a
-- line with no XP shows just its coins (one with XP only, the GOLD PASS's +10% XP, just its XP;
-- owner: "the paid one should also be insane"). While the card is up, the local player's
-- PP_ResultsShowing holds the toasts back (NotificationController): the card draws over them.
--
-- The headline names the game in capitals, like every other screen, on one line: a long name with
-- "Your team won!" draws a little smaller rather than wrapping out of its box.
--
-- Each standings row has the place and name on the left and the result on the right, in its own
-- label: the result always reads whole and a long name gives way ("..."), only as far as its own
-- row's result needs. It used to be one line ("🥇  name  ·  result") that a 15-character name cut
-- short in every mode.
--
-- PLAY AGAIN? (owner: "Add a vote at the end of each minigame to replay the same minigame."; the
-- vote itself is Services/ReplayService): the card's title bar, between its title and its ✕, has
-- 🔁 PLAY AGAIN? with how many want a replay ("3/5 want a replay") and NO THANKS, for the people who
-- vote on it (they played the round and play the next one: not someone sitting out). Your answer
-- gets a ✓ and a yellow rim, and you can change it until the results end. The title bar is where
-- phones keep them clear of the menu column, the jump button and the MOVE stick, as 44 pt buttons.
-- After the most replays in a row it says a new vote is next instead.
--
-- Bug sweep (owner: "Let's do a full bug and clean sweep."): the card closed on Cleanup or
-- Intermission only. A replay goes from Results through Cleanup into its own Preparing in one server
-- step (and a round nobody can play next goes to Waiting), and a device only gets the phase set
-- last in a step, so the card stayed up over the replay's rules card and the round. Any phase but
-- Results closes it now.
--
-- NO THANKS wore the panels' dark purple on the card's (owner: "why are the close menu buttons and
-- the invite friend button so dark?"): it's Theme's neutral lavender button now, beside the green
-- PLAY AGAIN.
--
-- 👍 / 👎 on the game (owner: "lets add to the backburner a away for players to downvote a minigame
-- and then we can harvest that data to disable minigames in the future." Then: "Also while you make
-- the downvote for mini games can you also do an upvote one so we can see if players like it"; the
-- totals are Services/RatingService's): two buttons the same size in the title bar, just after its
-- title, for everyone who played the round. 👍 ("Loved it") lights green, 👎 ("Not for me") red, with
-- the yellow rim of an answer; tapping the other one switches the vote and tapping the lit one again
-- takes it back, until the results end. On phones they're 44 pt like the rest of the bar, and the
-- card is wider than it was so the title, the thumbs and PLAY AGAIN all fit beside each other.
-- Only about one round in 17 got a vote, so the thumbs say what they're for: "RATE IT!" in yellow
-- just before them, and they pop in as the card opens (owner: "lets do 1-7."). The card's title is
-- "Results" (not "Round Results") to make room.
--
-- Only the card's X closes it early (owner: "I don't like how clicking skips the ending screen. I
-- clicked and I couldn't vote."): a click beside it, on the dim backdrop, used to close it, and so
-- could a click on the card itself.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local GameDefinitions = require(Shared.GameDefinitions)
local GameState = require(Shared.GameState)
local CrateLogic = require(Shared.Logic.CrateLogic)
local Placement = require(Shared.Logic.Placement)
local Remotes = require(Shared.Remotes)

local AudioController = require(script.Parent.AudioController)
local CrateTheme = require(script.Parent.Parent.Crates.CrateTheme)
local LootFly = require(script.Parent.Parent.Crates.LootFly)
local Haptics = require(script.Parent.Parent.Haptics)
local Participants = require(script.Parent.Parent.Participants)
local State = require(script.Parent.Parent.State)
local Modal = require(script.Parent.Parent.UI.Modal)
local PartyKit = require(script.Parent.Parent.UI.PartyKit)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local ResultsController = {}

-- The standings rows beside the podium: a result takes as much of its row as it needs, up to
-- RESULT_MAX (the rest stays for the place and name); one that's wider still is drawn smaller, down to
-- RESULT_MIN_TEXT (11 pt on a phone).
local RESULT_MAX = 128
-- From this many reward lines the breakdown draws compact (it has room for five at full size).
local COMPACT_LINES = 6
-- The round's crate and keys: two tiles over the totals (lit when won; the keys dim when not).
local LOOT_H = 56
local LOOT_CRATE = { Color3.fromRGB(255, 170, 80), Color3.fromRGB(205, 80, 30) } -- the HUD's 📦 pill
local LOOT_KEYS = { Color3.fromRGB(120, 210, 255), Color3.fromRGB(50, 105, 220) } -- the HUD's 🔑 pill
local LOOT_DIM = { Color3.fromRGB(70, 62, 110), Color3.fromRGB(48, 40, 82) }
local KEY_CHIP = Vector2.new(58, 24) -- the keys a podium place pays, on its step

-- The room a result needs at this text size: a little more than it measures, because phones draw
-- the scaled-down text up to 4% wider than that (a result given exactly its width ended in "...").
local function resultRoom(text: string, size: number): number
	return UIKit.TextWidth(text, size, Theme.Fonts.Bold) * 1.06 + 4
end

local modal: Modal.Modal
local standings: ScrollingFrame
local rewards: Frame
local cardGame = "" -- the game of the card on screen (its PLAY AGAIN vote must be for it)

-- The PLAY AGAIN strip (scaled units): phones, then PC. CLOSE_GAP keeps NO THANKS a finger away from
-- the card's ✕ (which closes the card).
local AGAIN_W, NO_W, STRIP_GAP, CLOSE_GAP = 220, 150, 10, 20
local PC_AGAIN_W, PC_NO_W = 210, 140
local GREEN_DARK = Color3.fromRGB(60, 160, 90)
type ReplayStrip = {
	strip: Frame,
	again: TextButton,
	againTitle: TextLabel,
	againCount: TextLabel,
	againRim: UIStroke,
	no: TextButton,
	noRim: UIStroke,
	note: TextLabel,
}
local replay: ReplayStrip

-- The 👍 / 👎 pair (scaled units): each a square the size of the bar's other buttons, THUMB_GAP apart,
-- RATE_GAP after the title.
local THUMB_GAP, RATE_GAP = 10, 16
local RATE_TEXT = "RATE IT!"
local THUMBS = {
	Up = { Name = "ThumbUp", Icon = "👍", Lit = Theme.Colors.Green, LitDark = GREEN_DARK },
	Down = { Name = "ThumbDown", Icon = "👎", Lit = Theme.Colors.Red, LitDark = Color3.fromRGB(190, 40, 60) },
}
local rating: { row: Frame, buttons: { [string]: TextButton } }

local function clear(frame: Instance)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- Shows the strip as the vote stands: the buttons for a voter while it's open, your answer marked;
-- the note when the game has had its replays; nothing otherwise.
local function refreshReplay()
	local vote = GameState.GetJSON("ReplayVote")
	local current = type(vote) == "table" and cardGame ~= "" and vote.Game == cardGame
	local voters = if current and type(vote.Voters) == "table" then vote.Voters else {}
	local open = current and vote.Open == true and table.find(voters, State.LocalPlayer.UserId) ~= nil
	local capped = current and vote.Capped == true
	replay.strip.Visible = open or capped
	replay.again.Visible = open
	replay.no.Visible = open
	replay.note.Visible = capped and not open
	if not open then
		return
	end
	local mine = State.LocalPlayer:GetAttribute("PP_Replay")
	replay.againTitle.Text = if mine == "Yes" then "✓ PLAY AGAIN" else "🔁 PLAY AGAIN?"
	replay.againCount.Text = `{tonumber(vote.Yes) or 0}/{#voters} want a replay`
	replay.no.Text = if mine == "No" then "✓ NO THANKS" else "NO THANKS"
	local function mark(rim: UIStroke, chosen: boolean)
		rim.Color = if chosen then Theme.Colors.Yellow else Color3.new(1, 1, 1)
		rim.Thickness = if chosen then 4 else 2
		rim.Transparency = if chosen then 0 else 0.55
	end
	mark(replay.againRim, mine == "Yes")
	mark(replay.noRim, mine == "No")
end

-- Shows the 👍 / 👎 pair while the vote on this card's game is open, the player's vote lit.
local function refreshRating()
	local vote = GameState.GetJSON("Rating")
	local open = type(vote) == "table" and vote.Open == true and cardGame ~= "" and vote.Game == cardGame
	if open and not rating.row.Visible and not State.ReducedEffects() then
		UIKit.PopIn(rating.row, 0.35) -- (the eye finds them as the card opens)
	end
	rating.row.Visible = open
	local mine = State.LocalPlayer:GetAttribute("PP_Rating")
	for choice, button in rating.buttons do
		local look = THUMBS[choice]
		local lit = mine == choice
		local gradient = button:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Color = ColorSequence.new(
				if lit then look.Lit else Theme.Colors.Lavender,
				if lit then look.LitDark else Theme.Colors.Purple
			)
		end
		local rim = button:FindFirstChildOfClass("UIStroke")
		if rim then
			rim.Color = if lit then Theme.Colors.Yellow else Color3.new(1, 1, 1)
			rim.Thickness = if lit then 4 else 2
			rim.Transparency = if lit then 0 else 0.55
		end
	end
end

local function buildRating()
	local touch = UIKit.IsTouch()
	local titleBar = modal.Window:FindFirstChild("TitleBar") or modal.Window
	local size = if touch then Theme.Touch.Target else 52
	-- Just after the title (Modal's label, as wide as its text).
	local title: TextLabel? = nil
	for _, child in titleBar:GetChildren() do
		if child:IsA("TextLabel") then
			title = child
		end
	end
	local titleWidth = if title then UIKit.TextWidth(title.Text, title.TextSize, title.Font) else 0
	local textSize = if touch then 22 else 21
	local labelWidth = math.ceil(UIKit.TextWidth(RATE_TEXT, textSize, Theme.Fonts.Display) * 1.06) + 4
	local row = UIKit.new("Frame", {
		Name = "Rating",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 24 + math.ceil(titleWidth) + RATE_GAP, 0, Modal.TitleHeight() / 2 + 2),
		Size = UDim2.fromOffset(labelWidth + THUMB_GAP + 2 * size + THUMB_GAP, size),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 23,
		Parent = titleBar,
		Children = {
			UIKit.List(
				Enum.FillDirection.Horizontal,
				THUMB_GAP,
				Enum.HorizontalAlignment.Left,
				Enum.VerticalAlignment.Center
			),
		},
	})
	UIKit.Label({
		Name = "Ask",
		Text = RATE_TEXT,
		Font = Theme.Fonts.Display,
		TextSize = textSize,
		TextWrapped = false,
		TextColor3 = Theme.Colors.Yellow,
		Size = UDim2.fromOffset(labelWidth, size),
		LayoutOrder = 0,
		ZIndex = 23,
		Parent = row,
		Children = { UIKit.TextStroke(0.3) },
	})
	local buttons = {}
	for order, choice in { "Up", "Down" } do
		local look = THUMBS[choice]
		local button = UIKit.Button({
			Name = look.Name,
			Text = "",
			Size = UDim2.fromOffset(size, size),
			CornerRadius = 18,
			LayoutOrder = order,
			ZIndex = 23,
			Parent = row,
		}, function()
			-- The other one switches the vote; the lit one again takes it back.
			local mine = State.LocalPlayer:GetAttribute("PP_Rating")
			Remotes.Get("RateGame"):FireServer(if mine == choice then "None" else choice)
		end, Theme.Colors.Lavender, Theme.Colors.Purple)
		-- The emoji in a label of its own: the button's gradient tints its own text, and drew the
		-- thumbs dark (owner: "why are the thumbs up and down black? can we revert them to the
		-- standard yellow?").
		UIKit.Label({
			Name = "Icon",
			Text = look.Icon,
			TextSize = if touch then 36 else 30,
			TextWrapped = false,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 24,
			Parent = button,
		})
		buttons[choice] = button
	end
	rating = { row = row, buttons = buttons }
end

local function buildReplay()
	local touch = UIKit.IsTouch()
	local titleBar = modal.Window:FindFirstChild("TitleBar") or modal.Window
	local closeSize = if touch then Theme.Touch.Target else 46
	local height = if touch then Theme.Touch.Target else 52
	local againWidth = if touch then AGAIN_W else PC_AGAIN_W
	local noWidth = if touch then NO_W else PC_NO_W
	local strip = UIKit.new("Frame", {
		Name = "Replay",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(12 + closeSize + CLOSE_GAP), 0, Modal.TitleHeight() / 2 + 2), -- beside the ✕
		Size = UDim2.fromOffset(againWidth + STRIP_GAP + noWidth, height),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 23,
		Parent = titleBar,
		Children = {
			UIKit.List(
				Enum.FillDirection.Horizontal,
				STRIP_GAP,
				Enum.HorizontalAlignment.Right,
				Enum.VerticalAlignment.Center
			),
		},
	})
	local function choose(again: boolean)
		Remotes.Get("ReplayVote"):FireServer(again)
	end
	local again = UIKit.Button({
		Name = "PlayAgain",
		Text = "",
		Size = UDim2.fromOffset(againWidth, height),
		CornerRadius = 18,
		LayoutOrder = 1,
		ZIndex = 23,
		Parent = strip,
	}, function()
		choose(true)
	end, Theme.Colors.Green, GREEN_DARK)
	local againTitle = UIKit.Label({
		Name = "Title",
		Text = "🔁 PLAY AGAIN?",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 22 else 21,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, if touch then 7 else 4),
		Size = UDim2.new(1, 0, 0, if touch then 30 else 26),
		ZIndex = 24,
		Parent = again,
		Children = { UIKit.TextStroke(0.3) },
	})
	local againCount = UIKit.Label({
		Name = "Count",
		Text = "",
		TextSize = if touch then Theme.Touch.MinText else 15,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, if touch then -8 else -5),
		Size = UDim2.new(1, 0, 0, if touch then 24 else 19),
		ZIndex = 24,
		Parent = again,
		Children = { UIKit.TextStroke(0.4) },
	})
	local no = UIKit.Button({
		Name = "NoThanks",
		Text = "NO THANKS",
		TextSize = if touch then 20 else 19,
		Size = UDim2.fromOffset(noWidth, height),
		CornerRadius = 18,
		LayoutOrder = 2,
		ZIndex = 23,
		Parent = strip,
	}, function()
		choose(false)
	end, Theme.Colors.Lavender, Theme.Colors.Purple)
	local note = UIKit.Label({
		Name = "Note",
		Text = `🗳️ {Config.Session.MaxReplays + 1} in a row - a new vote next!`,
		TextSize = if touch then 19 else 18,
		TextWrapped = false,
		TextColor3 = Theme.Colors.Yellow,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromOffset(againWidth + STRIP_GAP + noWidth, height),
		LayoutOrder = 3,
		Visible = false,
		ZIndex = 23,
		Parent = strip,
		Children = { UIKit.TextStroke(0.3) },
	})
	replay = {
		strip = strip,
		again = again,
		againTitle = againTitle,
		againCount = againCount,
		againRim = again:FindFirstChildOfClass("UIStroke") :: UIStroke,
		no = no,
		noRim = no:FindFirstChildOfClass("UIStroke") :: UIStroke,
		note = note,
	}
end

-- The card's look (owner: "Can we make this screen better?", then "make it look sick"): a hero banner
-- (VICTORY!, 2ND PLACE!, DEFEATED!...) over a turning sunburst in the place's colour, with confetti on
-- a win; a podium for the top 3, each on their step in a ring of gold, silver or bronze with their
-- avatar (a live portrait of their character: bots have no Roblox headshot, so they'd show a letter);
-- the rest of the standings beside it, the player's row lit; and the rewards, the totals counting up
-- in big pills. The same footprint as the old card (960 x 470), so it fits a phone the same way.
local HERO_H = 74 -- the banner (units)
local BODY_GAP = 10
local RESULT_SIZE = 18 -- a podium result's text (two lines' room, three when it needs them)
local PODIUM_COLUMN = 104 -- a podium place's width on the card (units: a third of PODIUM_W, less gaps)
-- The three panels' shares of the card's width: the podium, the standings beside it, the rewards.
local PODIUM_W, LIST_W = 0.355, 0.305
local PODIUM: { [number]: { Color: Color3, Dark: Color3, Face: number, Step: number, Number: number } } = {
	{ Color = Color3.fromRGB(255, 206, 64), Dark = Color3.fromRGB(214, 132, 18), Face = 84, Step = 100, Number = 46 },
	{ Color = Color3.fromRGB(222, 228, 245), Dark = Color3.fromRGB(140, 152, 190), Face = 70, Step = 76, Number = 38 },
	{ Color = Color3.fromRGB(244, 164, 104), Dark = Color3.fromRGB(176, 92, 44), Face = 70, Step = 60, Number = 32 },
}
local OTHER_COLOR = Color3.fromRGB(176, 150, 255)
local LOST_COLOR = Color3.fromRGB(255, 96, 110)

local hero: Frame
local heroRays: Frame?
local heroTitle: TextLabel
local heroTint: UIGradient
local heroSub: TextLabel
local podium: Frame
local standingsPanel: Frame
local group = PartyKit.Group() -- the card's loops (the sunburst, the winner's halo), paused while it's shut

-- A live portrait of someone's character in a face's disc (head and shoulders, lit like the card), when
-- the character is here: everyone looks like themselves, bots too. Their headshot (or letter) stays
-- underneath for when it isn't.
local function portrait(face: any, userId: number)
	local character = Participants.CharacterOf(userId)
	local head = character and character:FindFirstChild("Head")
	if not character or not head or not head:IsA("BasePart") then
		return
	end
	local wasArchivable = character.Archivable
	character.Archivable = true
	local ok, copy = pcall(character.Clone, character)
	character.Archivable = wasArchivable
	if not ok or not copy then
		return
	end
	for _, item in copy:GetDescendants() do
		if item:IsA("Script") or item:IsA("LocalScript") or item:IsA("BillboardGui") or item:IsA("Sound") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = true
		end
	end
	local view = UIKit.new("ViewportFrame", {
		Name = "Portrait",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.9),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(200, 196, 220),
		LightColor = Color3.fromRGB(255, 248, 235),
		LightDirection = Vector3.new(-0.4, -0.6, -1),
		ZIndex = face.Photo.ZIndex + 1,
		Parent = face.Disc,
		Children = { UIKit.Round() },
	})
	copy.Parent = view
	local copyHead = copy:FindFirstChild("Head") :: BasePart?
	if not copyHead then
		view:Destroy()
		return
	end
	local camera = Instance.new("Camera")
	camera.FieldOfView = 32
	local at = copyHead.Position + Vector3.new(0, -0.15, 0)
	camera.CFrame = CFrame.lookAt(at + copyHead.CFrame.LookVector * 3.4 + Vector3.new(0, 0.35, 0), at)
	camera.Parent = view
	view.CurrentCamera = camera
end

-- Counts a pill's number up from 0 (at once with reduced effects).
local function countUp(label: TextLabel, value: number, format: (number) -> string, delay: number)
	if State.ReducedEffects() or value <= 0 then
		label.Text = format(value)
		return
	end
	label.Text = format(0)
	task.delay(delay, function()
		local started = os.clock()
		while label.Parent do
			local f = math.clamp((os.clock() - started) / 0.8, 0, 1)
			label.Text = format(math.floor(value * (1 - (1 - f) ^ 3) + 0.5))
			if f >= 1 then
				break
			end
			task.wait()
		end
	end)
end

-- The banner's words and colour for how the round went.
local function heroFor(data, definition): (string, string, Color3)
	local gameName = if definition then string.upper(definition.Name) else "THE ROUND"
	local ordinal = Placement.Ordinal(data.Place)
	local of = `{ordinal} of {data.PlayerCount}`
	if data.WinningTeam == "Vacuum" and data.MyTeam == "Squad" then
		-- (a co-op fight the boss won: nobody won it, whatever their contribution)
		return "DEFEATED!", `The Vacuum won  •  you were {of}`, LOST_COLOR
	end
	local team = data.MyTeam and data.MyTeam ~= ""
	if team and data.WinningTeam == nil then
		return "DRAW!", `{gameName}  •  {of}`, Theme.Colors.Cyan
	end
	if data.Place == 1 then
		return "VICTORY!",
			`You won {gameName}!{if team and data.WinningTeam == data.MyTeam then "  •  Your team won!" else ""}`,
			PODIUM[1].Color
	end
	if team and data.WinningTeam == data.MyTeam then
		return "TEAM WIN!", `Your team won {gameName}!  •  {of}`, Theme.Colors.Green
	end
	local look = PODIUM[data.Place]
	return `{string.upper(ordinal)} PLACE!`, `{gameName}  •  {of}`, if look then look.Color else OTHER_COLOR
end

local function buildPodium(data)
	clear(podium)
	local byPlace: { [number]: any } = {}
	for _, entry in data.Standings do
		if entry.Place <= 3 and not byPlace[entry.Place] then
			byPlace[entry.Place] = entry
		end
	end
	local me = Players.LocalPlayer.UserId
	for column, place in { 2, 1, 3 } do
		local look = PODIUM[place]
		local entry = byPlace[place]
		local holder = UIKit.new("Frame", {
			Name = `Place{place}`,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new((column - 0.5) / 3, 0, 1, 0),
			Size = UDim2.new(1 / 3, -8, 1, -6),
			BackgroundTransparency = 1,
			ZIndex = 3,
			Parent = podium,
		})
		local step = UIKit.new("Frame", {
			Name = "Step",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.new(1, 0, 0, look.Step),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = if entry then 0 else 0.6,
			ZIndex = 3,
			Parent = holder,
			Children = {
				UIKit.Corner(12),
				UIKit.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(look.Color, look.Dark) }),
				UIKit.Stroke(Color3.new(1, 1, 1), 2, 0.45),
			},
		})
		UIKit.Label({
			Name = "Number",
			Text = tostring(place),
			Font = Theme.Fonts.Display,
			TextSize = look.Number,
			TextWrapped = false,
			Size = UDim2.new(1, 0, 1, if entry then -(KEY_CHIP.Y + 4) else 0), -- (over its keys)
			ZIndex = 4,
			Parent = step,
			Children = { UIKit.TextStroke(0.15) },
		})
		if place == 1 and entry and not State.ReducedEffects() then
			PartyKit.Shine(step, group)
		end
		-- What the place pays in keys (3 / 2 / 1: Logic/CrateLogic), on its step for everyone to see.
		local keys = CrateLogic.PodiumKeys[place]
		if keys and entry then
			local chip = UIKit.new("Frame", {
				Name = "Keys",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -4),
				Size = UDim2.fromOffset(KEY_CHIP.X, KEY_CHIP.Y),
				BackgroundColor3 = Color3.fromRGB(40, 70, 160),
				BackgroundTransparency = 0.25,
				ZIndex = 5,
				Parent = step,
				Children = { UIKit.Round(), UIKit.Stroke(Color3.fromRGB(150, 220, 255), 1.5, 0.3) },
			})
			local art = UIKit.new("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(4, 1),
				Size = UDim2.fromOffset(KEY_CHIP.Y - 2, KEY_CHIP.Y - 2),
				ZIndex = 6,
				Parent = chip,
			})
			CrateTheme.Picture("Key", art, { ZIndex = 6 })
			UIKit.Label({
				Text = `+{keys}`,
				Font = Theme.Fonts.Display,
				TextSize = 18,
				TextWrapped = false,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(KEY_CHIP.Y + 3, 0),
				Size = UDim2.new(1, -(KEY_CHIP.Y + 5), 1, 0),
				ZIndex = 6,
				Parent = chip,
				Children = { UIKit.TextStroke(0.2) },
			})
		end
		if not entry then
			continue
		end
		local isMe = entry.UserId == me
		local nameColor = if isMe then Theme.Colors.Yellow else Theme.Colors.Text
		-- (Under the name, its first part on a line of its own: "45 coins" over "never chomped!",
		-- wrapping onto a third line rather than shrinking or losing its end.)
		local resultText = string.gsub(entry.ScoreText or "", " • ", "\n", 1)
		local lines = math.clamp(UIKit.TextLines(resultText, RESULT_SIZE, Theme.Fonts.Bold, PODIUM_COLUMN), 1, 3)
		local resultHeight = math.max(2, lines) * (RESULT_SIZE + 2)
		local result = UIKit.Label({
			Name = "Result",
			Text = resultText,
			TextSize = RESULT_SIZE,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			TextColor3 = if isMe then Theme.Colors.Yellow else Theme.Colors.TextDim,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -(look.Step + 4)),
			Size = UDim2.new(1, 4, 0, resultHeight),
			ZIndex = 4,
			Parent = holder,
			Children = { UIKit.TextStroke(0.35) },
		})
		local name = UIKit.Label({
			Name = "Name",
			Text = Participants.ListName(entry.Name, Participants.IsBotId(entry.UserId)),
			RichText = true,
			TextSize = 19,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = nameColor,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -(look.Step + 4 + resultHeight)),
			Size = UDim2.new(1, 4, 0, 24),
			ZIndex = 4,
			Parent = holder,
			Children = { UIKit.TextStroke(0.25) },
		})
		name:SetAttribute("PP_TruncateOk", true)
		local face = PartyKit.Face({
			Size = look.Face,
			Parent = holder,
			Name = "Face",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -(look.Step + 4 + resultHeight + 24 + 6)),
			ZIndex = 4,
			Halo = place == 1,
			Group = group,
		})
		PartyKit.SetFace(face, { UserId = entry.UserId, DisplayName = entry.Name }, look.Color, place == 1, nil)
		face.Ring.Thickness = if isMe then 5 else face.Ring.Thickness
		pcall(portrait, face, entry.UserId) -- (a portrait that can't be made never costs the card)
		if not State.ReducedEffects() then
			-- The steps rise, 3rd, 2nd then 1st, and each face pops up on its own.
			local delay = 0.15 + (3 - place) * 0.18
			local full = step.Size
			step.Size = UDim2.new(1, 0, 0, 0)
			task.delay(delay, function()
				UIKit.Tween(step, 0.35, { Size = full }, Enum.EasingStyle.Back)
			end)
			UIKit.PopIn(face.Frame, 0.35 + delay)
			UIKit.PopIn(name, 0.4 + delay)
			UIKit.PopIn(result, 0.45 + delay)
		end
	end
end

-- Places 4 and down beside the podium (scrolling if a big lobby needs it); the player's row lit.
local function buildStandings(data)
	clear(standings)
	local me = Players.LocalPlayer.UserId
	local count = 0
	for index, entry in data.Standings do
		if entry.Place <= 3 then
			continue
		end
		count += 1
		local isMe = entry.UserId == me
		local color = if isMe then Theme.Colors.Yellow else Theme.Colors.Text
		local result = entry.ScoreText or ""
		-- A result that leaves the name too little room goes on a second line under it.
		local twoLines = resultRoom(result, 18) > RESULT_MAX
		local row = UIKit.new("Frame", {
			Name = `Row{entry.Place}`,
			Size = UDim2.new(1, -6, 0, if twoLines then 46 else 32),
			BackgroundColor3 = if isMe then Theme.Colors.Yellow else Theme.Colors.PanelDark,
			BackgroundTransparency = if isMe then 0.78 else (if count % 2 == 1 then 0.45 else 0.7),
			LayoutOrder = index,
			Parent = standings,
			Children = {
				UIKit.Corner(10),
				if isMe then UIKit.Stroke(Theme.Colors.Yellow, 2, 0.1) else nil,
			} :: any,
		})
		UIKit.Label({
			Name = "Place",
			Text = Placement.Ordinal(entry.Place),
			Font = Theme.Fonts.Display,
			TextSize = 18,
			TextWrapped = false,
			TextColor3 = if isMe then Theme.Colors.Yellow else Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.new(0, 40, 0, 32),
			Parent = row,
		})
		local resultWidth = if twoLines then 0 else math.min(math.ceil(resultRoom(result, 18)), RESULT_MAX)
		local nameLabel = UIKit.Label({
			Name = "Name",
			Text = Participants.ListName(entry.Name, Participants.IsBotId(entry.UserId)),
			RichText = true,
			TextSize = 18,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = color,
			Position = UDim2.fromOffset(50, if twoLines then 2 else 0),
			Size = UDim2.new(1, -(50 + resultWidth + 12), 0, if twoLines then 24 else 32),
			Parent = row,
		})
		nameLabel:SetAttribute("PP_TruncateOk", true) -- a long name ends in "..."
		UIKit.Label({
			Name = "Result",
			Text = result,
			TextSize = 18,
			TextWrapped = false,
			TextXAlignment = if twoLines then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = if isMe then Theme.Colors.Yellow else Theme.Colors.TextDim,
			AnchorPoint = if twoLines then Vector2.zero else Vector2.new(1, 0),
			Position = if twoLines then UDim2.fromOffset(50, 23) else UDim2.new(1, -8, 0, 0),
			Size = if twoLines then UDim2.new(1, -58, 0, 21) else UDim2.new(0, resultWidth, 1, 0),
			Parent = row,
		})
		UIKit.PopIn(row, 0.5 + count * 0.06)
	end
	return count
end

local function buildRewards(data)
	clear(rewards)
	-- Six or more lines (the boosts: a friend in the round, a double coins weekend) draw a little
	-- tighter, and the personal best is left to its own line, so the card still fits a phone.
	local crate = if type(data.Crate) == "table" then data.Crate else nil -- the round's season crate
	local compact = #data.Lines + (if crate then 2 else 0) >= COMPACT_LINES
	local list = rewards:FindFirstChildOfClass("UIListLayout")
	if list then
		list.Padding = UDim.new(0, if compact then 4 else 5)
	end
	local rowHeight = if compact then 27 else 31
	for index, line in data.Lines do
		local row = UIKit.new("Frame", {
			Size = UDim2.new(1, 0, 0, rowHeight),
			BackgroundColor3 = Theme.Colors.PanelDark,
			BackgroundTransparency = 0.35,
			LayoutOrder = index,
			Parent = rewards,
			Children = { UIKit.Corner(10) },
		})
		UIKit.Label({
			Text = line.Label,
			TextSize = 18,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(0.6, 0, 1, 0),
			Position = UDim2.fromOffset(12, 0),
			Parent = row,
		})
		UIKit.Label({
			-- (A line of XP only: the GOLD PASS's +10% XP.)
			Text = if line.XP > 0 and line.Coins <= 0
				then `+{line.XP} XP`
				elseif line.XP > 0 then `+{line.Coins} {Theme.CoinIcon}  +{line.XP} XP`
				else `+{line.Coins} {Theme.CoinIcon}`,
			TextSize = 18,
			TextWrapped = false,
			TextColor3 = Theme.Colors.Yellow,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.new(0.4, -12, 1, 0),
			Position = UDim2.fromScale(0.6, 0),
			Parent = row,
		})
		UIKit.PopIn(row, 0.3 + index * 0.07)
	end
	if crate then
		-- The crate season (Services/CrateService): one crate for every round played to the end and
		-- 3 / 2 / 1 keys for the top 3, as two big tiles over the totals (owner: "Can we make the
		-- earning of keys and crates more apparent?"). When the card closes they fly into the 🔑 and
		-- 📦 counters (Crates/LootFly).
		local won = math.max(0, math.floor(tonumber(crate.KeysWon) or 0))
		local count = math.max(1, math.floor(tonumber(crate.Count) or 1))
		local loot = UIKit.new("Frame", {
			Name = "Loot",
			Size = UDim2.new(1, 0, 0, LOOT_H),
			BackgroundTransparency = 1,
			LayoutOrder = 99,
			Parent = rewards,
			Children = {
				UIKit.List(
					Enum.FillDirection.Horizontal,
					10,
					Enum.HorizontalAlignment.Center,
					Enum.VerticalAlignment.Center
				),
			},
		})
		local function tile(name: string, picture: string, look: { Color3 }, big: string, small: string, order: number)
			local lit = look ~= LOOT_DIM
			local frame = UIKit.new("Frame", {
				Name = name,
				Size = UDim2.new(0.5, -5, 1, 0),
				BackgroundColor3 = Color3.new(1, 1, 1),
				LayoutOrder = order,
				Parent = loot,
				Children = {
					UIKit.Corner(14),
					UIKit.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(look[1], look[2]) }),
					UIKit.Stroke(if lit then Color3.new(1, 1, 1) else look[1], 2, if lit then 0.2 else 0.5),
				},
			})
			local art = UIKit.new("Frame", {
				Name = "Art",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 4, 0.5, 0),
				Size = UDim2.fromOffset(LOOT_H - 6, LOOT_H - 6),
				Parent = frame,
			})
			local image = CrateTheme.Picture(picture, art)
			if not lit then
				if image:IsA("ImageLabel") then
					image.ImageTransparency = 0.45
				elseif image:IsA("TextLabel") then
					image.TextTransparency = 0.45
				end
			end
			UIKit.Label({
				Name = "Big",
				Text = big,
				Font = Theme.Fonts.Display,
				TextSize = 30,
				TextWrapped = false,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = if lit then Color3.new(1, 1, 1) else Theme.Colors.TextDim,
				Position = UDim2.fromOffset(LOOT_H - 2, 2),
				Size = UDim2.new(1, -(LOOT_H + 2), 0, 31),
				Parent = frame,
				Children = { UIKit.TextStroke(0.1) },
			})
			UIKit.Label({
				Name = "Small",
				Text = small,
				Font = Theme.Fonts.Display,
				TextSize = 18,
				TextWrapped = false,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = if lit then Color3.new(1, 1, 1) else Theme.Colors.TextDim,
				Position = UDim2.fromOffset(LOOT_H - 2, 33),
				Size = UDim2.new(1, -(LOOT_H + 2), 0, 21),
				Parent = frame,
				Children = { UIKit.TextStroke(0.2) },
			})
			if State.ReducedEffects() then
				return
			end
			-- They land after the lines with a bigger bounce (and a tick), the lit ones shining.
			local at = 0.45 + order * 0.12
			frame.Visible = false
			task.delay(at, function()
				frame.Visible = true
				UIKit.PopIn(frame, 0.45)
				if lit then
					AudioController.PlayOr("CrateTick", "Pickup")
				end
			end)
			if lit then
				PartyKit.Shine(frame, group)
				task.delay(at + 0.4, function()
					-- (the crate or key gives a little wiggle as it lands)
					art.Rotation = -12
					UIKit.Tween(art, 0.5, { Rotation = 0 }, Enum.EasingStyle.Elastic)
				end)
			end
		end
		tile("Crate", "Crate", LOOT_CRATE, `+{count}`, if count == 1 then "CRATE" else "CRATES", 1)
		if won > 0 then
			tile("Keys", "Key", LOOT_KEYS, `+{won}`, if won == 1 then "KEY!" else "KEYS!", 2)
		else
			tile("Keys", "Key", LOOT_DIM, "TOP 3", "WIN KEYS", 2)
		end
	end
	-- The totals: two big pills, counting up.
	local totals = UIKit.new("Frame", {
		Name = "Totals",
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundTransparency = 1,
		LayoutOrder = 100,
		Parent = rewards,
		Children = {
			UIKit.List(
				Enum.FillDirection.Horizontal,
				10,
				Enum.HorizontalAlignment.Center,
				Enum.VerticalAlignment.Center
			),
		},
	})
	local function pill(name: string, top: Color3, bottom: Color3, order: number): TextLabel
		local frame = UIKit.new("Frame", {
			Name = name,
			Size = UDim2.new(0.5, -5, 1, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			LayoutOrder = order,
			Parent = totals,
			Children = {
				UIKit.Round(),
				UIKit.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(top, bottom) }),
				UIKit.Stroke(Color3.new(1, 1, 1), 2, 0.35),
			},
		})
		local label = UIKit.Label({
			Name = "Value",
			Text = "",
			Font = Theme.Fonts.Display,
			TextSize = 26,
			TextWrapped = false,
			Size = UDim2.fromScale(1, 1),
			Parent = frame,
			Children = { UIKit.TextStroke(0.15) },
		})
		UIKit.PopIn(frame, 0.55 + order * 0.08)
		return label
	end
	local coins = pill("Coins", Color3.fromRGB(255, 214, 80), Color3.fromRGB(230, 140, 20), 1)
	local xp = pill("XP", Color3.fromRGB(110, 230, 255), Color3.fromRGB(70, 130, 240), 2)
	local delay = if State.ReducedEffects() then 0 else 0.7
	countUp(coins, tonumber(data.Coins) or 0, function(n)
		return `+{n} {Theme.CoinIcon}`
	end, delay)
	countUp(xp, tonumber(data.XP) or 0, function(n)
		return `+{n} XP`
	end, delay)
	if data.PersonalBest and not compact then
		UIKit.Label({
			Text = "⭐ New personal best!",
			Font = Theme.Fonts.Display,
			TextSize = 21,
			TextColor3 = Theme.Colors.Yellow,
			Size = UDim2.new(1, 0, 0, 28),
			LayoutOrder = 101,
			Parent = rewards,
			Children = { UIKit.TextStroke(0.2) },
		})
	end
	if type(data.LevelUp) == "number" then
		-- The full celebration plays once everyone's back in the lobby (CelebrationController).
		UIKit.Label({
			Text = `⭐ LEVEL UP! You're level {data.LevelUp}!`,
			Font = Theme.Fonts.Display,
			TextSize = 21,
			TextColor3 = Theme.Colors.Cyan,
			Size = UDim2.new(1, 0, 0, 28),
			LayoutOrder = 102,
			Parent = rewards,
			Children = { UIKit.TextStroke(0.2) },
		})
	elseif not compact then
		UIKit.Label({
			Text = "Next round soon - get ready!",
			TextSize = 18,
			TextColor3 = Theme.Colors.TextDim,
			Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = 102,
			Parent = rewards,
		})
	end
end

local function show(data)
	local definition = GameDefinitions.Get(data.GameId)
	local title, sub, color = heroFor(data, definition)
	heroTitle.Text = title
	heroTint.Color = ColorSequence.new(PartyKit.Lighter(color, 0.55), color)
	heroSub.Text = sub
	local top = data.Place <= 3 or title == "TEAM WIN!"
	local won = title == "VICTORY!" or title == "TEAM WIN!"
	if heroRays then
		heroRays:Destroy()
		heroRays = nil
	end
	if top and not State.ReducedEffects() then
		heroRays = PartyKit.Rays({
			Parent = hero,
			Size = 340,
			Position = UDim2.fromScale(0.5, 0.42),
			Color = color,
			Count = 10,
			ZIndex = 1,
			Group = group,
			Period = 16,
			Strength = if won then 0.5 else 0.3,
		})
	end

	buildPodium(data)
	local below = buildStandings(data)
	-- Nobody below the podium (three or fewer): the rewards take the standings' room.
	standingsPanel.Visible = below > 0
	local left = if below > 0 then PODIUM_W + LIST_W else PODIUM_W
	rewards.Position = UDim2.new(left, BODY_GAP, 0, HERO_H)
	rewards.Size = UDim2.new(1 - left, -BODY_GAP, 1, -HERO_H)
	buildRewards(data)
	-- The round's crate and keys wait on the card, then fly into their counters when it closes.
	if type(data.Crate) == "table" then
		local crate = data.Crate
		LootFly.Hold("Crates", tonumber(crate.Count) or 0, tonumber(crate.Total) or 0)
		LootFly.Hold("Keys", tonumber(crate.KeysWon) or 0, tonumber(crate.Keys) or 0)
	end

	cardGame = if type(data.GameId) == "string" then data.GameId else ""
	refreshReplay()
	refreshRating()
	PartyKit.SetPlaying(group, true)
	modal:Open()
	if not State.ReducedEffects() then
		UIKit.PopIn(heroTitle, 0.3)
		if won then
			task.delay(0.25, function()
				PartyKit.Burst(hero, UDim2.fromScale(0.5, 0.45), { color, Theme.Colors.Yellow }, 34, 300)
			end)
		end
	end
	AudioController.Play(if data.Place == 1 then "Victory" else "Results")
	if data.Place == 1 then
		Haptics.Play("Pulse")
	end
end

function ResultsController.Start(context)
	-- (960 wide: the title, 👍 / 👎 and PLAY AGAIN side by side in the title bar.)
	modal = Modal.new(context.Overlay, "Results", "🏆", Vector2.new(960, 470))
	modal.CloseOnBackdrop = false -- a stray click never skips the card (and its votes)
	-- Toasts wait while the card is up (it draws over them: NotificationController).
	modal.Opened:Connect(function()
		Players.LocalPlayer:SetAttribute("PP_ResultsShowing", true)
	end)
	modal.Closed:Connect(function()
		Players.LocalPlayer:SetAttribute("PP_ResultsShowing", nil)
		LootFly.Fly()
	end)
	-- The banner.
	hero = UIKit.new("Frame", {
		Name = "Hero",
		Size = UDim2.new(1, 0, 0, HERO_H),
		BackgroundTransparency = 1,
		ClipsDescendants = false,
		ZIndex = 2,
		Parent = modal.Content,
	})
	heroTitle = UIKit.Label({
		Name = "Title",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 46,
		TextWrapped = false,
		Size = UDim2.new(1, 0, 0, 46),
		ZIndex = 3,
		Parent = hero,
		Children = { UIKit.new("UIStroke", { Color = Color3.fromRGB(40, 16, 70), Thickness = 3, Transparency = 0.05 }) },
	})
	heroTint = UIKit.new("UIGradient", { Rotation = 90, Parent = heroTitle })
	heroSub = UIKit.Label({
		Name = "Sub",
		Text = "",
		Font = Theme.Fonts.Display,
		TextScaled = true, -- one line: a long game name with "Your team won!" shrinks a little
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 0, 26),
		ZIndex = 3,
		Parent = hero,
		Children = { UIKit.TextStroke(0.2), UIKit.new("UITextSizeConstraint", { MaxTextSize = 22 }) },
	})
	-- The podium, the rest of the standings and the rewards, side by side.
	podium = UIKit.new("Frame", {
		Name = "Podium",
		Position = UDim2.fromOffset(0, HERO_H),
		Size = UDim2.new(PODIUM_W, 0, 1, -HERO_H),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.45,
		ZIndex = 2,
		Parent = modal.Content,
		Children = { UIKit.Corner(18) },
	})
	standingsPanel = UIKit.new("Frame", {
		Name = "Standings",
		Position = UDim2.new(PODIUM_W, BODY_GAP, 0, HERO_H),
		Size = UDim2.new(LIST_W, -BODY_GAP, 1, -HERO_H),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = modal.Content,
	})
	standings = UIKit.new("ScrollingFrame", {
		Name = "List",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 2,
		Parent = standingsPanel,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 5, Enum.HorizontalAlignment.Left) },
	})
	rewards = UIKit.new("Frame", {
		Name = "Rewards",
		Position = UDim2.new(PODIUM_W + LIST_W, BODY_GAP, 0, HERO_H),
		Size = UDim2.new(1 - PODIUM_W - LIST_W, -BODY_GAP, 1, -HERO_H),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = modal.Content,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 5) },
	})
	modal.Closed:Connect(function()
		PartyKit.SetPlaying(group, false)
	end)

	buildReplay()
	buildRating()

	Remotes.Get("RoundResults").OnClientEvent:Connect(function(data)
		if type(data) == "table" then
			show(data)
		end
	end)
	-- (The card opens as the round ends, just before Results: InRound can't come back after it.)
	GameState.Changed("Phase", function(phase)
		if phase ~= "Results" then
			modal:Close()
		end
	end)
	GameState.Changed("ReplayVote", refreshReplay)
	State.LocalPlayer:GetAttributeChangedSignal("PP_Replay"):Connect(refreshReplay)
	GameState.Changed("Rating", refreshRating)
	State.LocalPlayer:GetAttributeChangedSignal("PP_Rating"):Connect(refreshRating)
end

return ResultsController
