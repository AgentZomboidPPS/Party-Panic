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
local Placement = require(Shared.Logic.Placement)
local Remotes = require(Shared.Remotes)

local AudioController = require(script.Parent.AudioController)
local Participants = require(script.Parent.Parent.Participants)
local State = require(script.Parent.Parent.State)
local Modal = require(script.Parent.Parent.UI.Modal)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local ResultsController = {}

local MEDALS = { "🥇", "🥈", "🥉" }

-- The standings rows (units: the column is about 374 wide on every screen): a result takes as much
-- of its row as it needs, up to RESULT_MAX (the rest stays for the place and name); one that's wider
-- still is drawn smaller, down to RESULT_MIN_TEXT (11 pt on a phone).
local ROW_TEXT, RESULT_MAX, RESULT_MIN_TEXT = 21, 232, 18
-- From this many reward lines the breakdown draws compact (it has room for five at full size).
local COMPACT_LINES = 6

-- The room a result needs at this text size: a little more than it measures, because phones draw
-- the scaled-down text up to 4% wider than that (a result given exactly its width ended in "...").
local function resultRoom(text: string, size: number): number
	return UIKit.TextWidth(text, size, Theme.Fonts.Bold) * 1.06 + 4
end

local modal: Modal.Modal
local headline: TextLabel
local standings: Frame
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

local function show(data)
	local definition = GameDefinitions.Get(data.GameId)
	local medal = MEDALS[data.Place] or "🎉"
	local teamLine = ""
	if data.MyTeam and data.MyTeam ~= "" then
		teamLine = if data.WinningTeam == data.MyTeam
			then "  •  Your team won!"
			elseif data.WinningTeam == nil then "  •  It's a draw!"
			else ""
	end
	headline.Text = if data.Place == 1
		then `{medal} You won {if definition then string.upper(definition.Name) else "the round"}!{teamLine}`
		else `{medal} {Placement.Ordinal(data.Place)} of {data.PlayerCount}{teamLine}`

	clear(standings)
	for index, entry in data.Standings do
		local isMe = entry.UserId == game:GetService("Players").LocalPlayer.UserId
		local place = MEDALS[entry.Place] or Placement.Ordinal(entry.Place)
		local name = Participants.ListName(entry.Name, Participants.IsBotId(entry.UserId))
		local color = if isMe then Theme.Colors.Yellow else Theme.Colors.Text
		local result = entry.ScoreText or ""
		local textSize = ROW_TEXT
		local resultWidth = resultRoom(result, textSize)
		while textSize > RESULT_MIN_TEXT and resultWidth > RESULT_MAX do
			textSize -= 1
			resultWidth = resultRoom(result, textSize)
		end
		resultWidth = math.min(math.ceil(resultWidth), RESULT_MAX)
		local row = UIKit.new("Frame", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Parent = standings,
		})
		local nameLabel = UIKit.Label({
			Text = `{place}  {name}`,
			RichText = true,
			TextSize = ROW_TEXT,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = color,
			Size = UDim2.new(1, -(resultWidth + 10), 1, 0),
			Parent = row,
		})
		nameLabel:SetAttribute("PP_TruncateOk", true) -- a long name ends in "..."
		UIKit.Label({
			Name = "Result",
			Text = result,
			TextSize = textSize,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd, -- (only past RESULT_MAX at the smallest size)
			TextColor3 = color,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, resultWidth, 1, 0),
			Parent = row,
		})
	end

	clear(rewards)
	-- Six or more lines (the boosts: a friend in the round, a double coins weekend) draw a little
	-- tighter, and the personal best is left to its own line, so the card still fits a phone.
	local crate = if type(data.Crate) == "table" then data.Crate else nil -- the round's season crate
	local compact = #data.Lines + (if crate then 1 else 0) >= COMPACT_LINES
	local list = rewards:FindFirstChildOfClass("UIListLayout")
	if list then
		list.Padding = UDim.new(0, if compact then 4 else 6)
	end
	for index, line in data.Lines do
		local row = UIKit.new("Frame", {
			Size = UDim2.new(1, 0, 0, if compact then 26 else 34),
			BackgroundColor3 = Theme.Colors.PanelDark,
			BackgroundTransparency = 0.35,
			LayoutOrder = index,
			Parent = rewards,
			Children = { UIKit.Corner(10) },
		})
		UIKit.Label({
			Text = line.Label,
			TextSize = if compact then 18 else 19,
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
			TextSize = if compact then 18 else 19,
			TextColor3 = Theme.Colors.Yellow,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.new(0.4, -12, 1, 0),
			Position = UDim2.fromScale(0.6, 0),
			Parent = row,
		})
		UIKit.PopIn(row, 0.25 + index * 0.08)
	end
	if crate then
		-- The crate season (Services/CrateService): one crate for every round played to the end, in
		-- the season's ember colours, with the keys the top 3 won (3 / 2 / 1) or the keys they have to
		-- open it.
		local row = UIKit.new("Frame", {
			Size = UDim2.new(1, 0, 0, if compact then 26 else 34),
			BackgroundColor3 = Color3.fromRGB(110, 46, 30),
			BackgroundTransparency = 0.2,
			LayoutOrder = #data.Lines + 1,
			Parent = rewards,
			Children = { UIKit.Corner(10), UIKit.Stroke(Color3.fromRGB(255, 150, 60), 1.5, 0.3) },
		})
		UIKit.Label({
			Text = `📦 +{crate.Count or 1} {crate.Name or "Crate"}`,
			Font = Theme.Fonts.Display,
			TextSize = if compact then 18 else 19,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(0.6, 0, 1, 0),
			Position = UDim2.fromOffset(12, 0),
			Parent = row,
		})
		local keys = tonumber(crate.Keys) or 0
		local won = tonumber(crate.KeysWon) or 0
		UIKit.Label({
			Text = if won > 0
				then `🔑 +{won} key{if won == 1 then "" else "s"}!`
				elseif keys > 0 then `🔑 {keys} to open it`
				else "🔑 top 3 win keys",
			TextSize = 18,
			TextColor3 = Color3.fromRGB(255, 196, 92),
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.new(0.4, -12, 1, 0),
			Position = UDim2.fromScale(0.6, 0),
			Parent = row,
		})
		UIKit.PopIn(row, 0.25 + (#data.Lines + 1) * 0.08)
	end
	UIKit.Label({
		Text = `Total: +{data.Coins} {Theme.CoinIcon}   +{data.XP} XP`,
		Font = Theme.Fonts.Display,
		TextSize = 26,
		TextColor3 = Theme.Colors.Green,
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = 100,
		Parent = rewards,
	})
	if data.PersonalBest and not compact then
		UIKit.Label({
			Text = "⭐ New personal best!",
			Font = Theme.Fonts.Display,
			TextSize = 22,
			TextColor3 = Theme.Colors.Yellow,
			Size = UDim2.new(1, 0, 0, 30),
			LayoutOrder = 101,
			Parent = rewards,
		})
	end
	if type(data.LevelUp) == "number" then
		-- The full celebration plays once everyone's back in the lobby (CelebrationController).
		UIKit.Label({
			Text = `⭐ LEVEL UP! You're level {data.LevelUp}!`,
			Font = Theme.Fonts.Display,
			TextSize = 22,
			TextColor3 = Theme.Colors.Cyan,
			Size = UDim2.new(1, 0, 0, 30),
			LayoutOrder = 102,
			Parent = rewards,
			Children = { UIKit.TextStroke(0.2) },
		})
	else
		UIKit.Label({
			Text = "Next round soon - get ready!",
			TextSize = 18,
			TextColor3 = Theme.Colors.TextDim,
			Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = 102,
			Parent = rewards,
		})
	end

	cardGame = if type(data.GameId) == "string" then data.GameId else ""
	refreshReplay()
	refreshRating()
	modal:Open()
	AudioController.Play(if data.Place == 1 then "Victory" else "Results")
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
	end)
	headline = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextScaled = true, -- one line: a long game name with "Your team won!" shrinks a little
		TextWrapped = false,
		Size = UDim2.new(1, 0, 0, 44),
		Parent = modal.Content,
		Children = { UIKit.TextStroke(0.2), UIKit.new("UITextSizeConstraint", { MaxTextSize = 34 }) },
	})
	standings = UIKit.new("Frame", {
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(0.48, 0, 1, -54),
		BackgroundTransparency = 1,
		Parent = modal.Content,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left) },
	})
	rewards = UIKit.new("Frame", {
		Position = UDim2.new(0.52, 0, 0, 54),
		Size = UDim2.new(0.48, 0, 1, -54),
		BackgroundTransparency = 1,
		Parent = modal.Content,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 6) },
	})

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
