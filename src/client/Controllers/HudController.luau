-- Lobby / in-round HUD (design doc §12 "Primary UI surfaces"):
-- profile chip (level, XP, coins), phase banner with timer, side menu, settings window.
-- Kept to the screen edges so chat and the middle of the screen stay clear.
-- Phones (owner: "Wtf is this mobile Ui lol"): a compact HUD. The phase banner is one short line
-- with the timer ("VOTE! 0:08") up in Roblox's top bar row, beside its buttons; a small profile
-- pill (level, name, XP) with the coins tucked under it at the top left, which makes way for the
-- standings during a round; the round's status line under the top bar; the menu down the right
-- edge, with 44 pt buttons. Nothing goes in the thumbstick's corner or near the jump button.
-- The sit-out switch (owner: "we do need to add somewhere super apparent a toggle where you skip
-- next round", UI/SitOutSwitch) sits right by the banner where everyone looks for the timer:
-- beside it in the top bar row on phones, above it in that row on PC; it's in Settings too.
-- Tapping the profile chip opens the Rewards screen (owner: "Also we need cool payoffs for players
-- that keep playing the game."); RewardsController adds the next reward beside the coins and colors
-- the level badge for the player's prestige tier.
-- The team pill under the status line shows every team in the round with its mark and score, as
-- wide as its line: colour teams by the shape they wear in the team modes, in their colour, versus
-- roles by their icon. On phones it used to read Red and Blue whatever the teams were, so SHARK
-- BAIT, SINKING SANDS and ARROW AMBUSH showed 0 — 0 all round and Green and Yellow never showed.
-- It marks the player's own team too (owner: "I couldnt tell what color I was on prime cut."): a
-- "YOU" beside its mark and a white-rimmed box round it, in every team game.
--
-- The menu column's Settings button wore the panels' dark purple and looked switched off (owner:
-- "why are the close menu buttons and the invite friend button so dark?"): it's lavender to purple
-- now (Theme's neutral button), apart from Shop's pink, Quests' yellow and Emotes' cyan.
--
-- More of the game on screen in a round (owner: "During the mini games, any way we can save UI space
-- so they can see more of the game at one time?"):
--   * While the player is playing a round (State.PlayingRound: its rules card to its end, still in)
--     the menu column slides off the right edge and a small ☰ button waits in the top right corner,
--     in Roblox's top bar row, with the Quests "!" on it. A tap brings the column back until a menu
--     is opened and closed, or 5 seconds pass. It comes back on its own for the results, for anyone
--     knocked out and watching or sitting out, and in the lobby. The ☰ is three drawn bars: the
--     character measures as a missing-glyph box in FredokaOne and Builder Sans, like ★ and ✕.
--   * The status line's "players left" count (Logic/RoundHud: "Players left: 6", "Survivors: 9")
--     is a pill in the banner beside the timer, an icon and the number. Whatever else the line says
--     stays under the banner and fades once it has gone 6 seconds without changing (it comes back
--     when it does). When the line has nothing to say, the team scores and the mode HUDs (Kit/Api's
--     TopHud, through State.TopHudShift) move up into its room, so a mode's chips sit right under
--     the banner; the room stays a few seconds after the line empties, so they don't hop about.
--   * Phones: the round's callouts (NotificationController) show in that line's place, one at a
--     time, in a compact strip with its kind's icon and coloured rim, not over the play area.
-- New motion (the column's slide, the pops, the HUD moving up) is instant with reduced effects.
--
-- The GOLD PASS (owner: "Also we do need a paid battle pass too. I like the current free one. But the
-- paid one should also be insane."): the old "💎 Get VIP" button in Settings is now a gold teaser, a
-- shining 👑 GOLD PASS pill in the Settings window's title bar (the window's list has no room left on
-- the shortest phone) that opens the Rewards screen on the gold lane; an owner's says 👑 GOLD ✓.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local GameDefinitions = require(Shared.GameDefinitions)
local GameState = require(Shared.GameState)
local GoldPass = require(Shared.GoldPass)
local Remotes = require(Shared.Remotes)
local RoundHud = require(Shared.Logic.RoundHud)
local Teams = require(Shared.Teams)

local GoldPassController = require(script.Parent.GoldPassController)
local State = require(script.Parent.Parent.State)
local Modal = require(script.Parent.Parent.UI.Modal)
local SitOutSwitch = require(script.Parent.Parent.UI.SitOutSwitch)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local HudController = {}

local PHASE_ICONS = {
	Waiting = "⏳",
	Intermission = "🎉",
	Voting = "🗳️",
	Preparing = "📋",
	InRound = "🎮",
	Results = "🏆",
	Cleanup = "🏠",
}
-- Phones: the banner's short words for the phases that have a timer.
local SHORT_TITLES = {
	Intermission = "NEXT VOTE",
	Voting = "VOTE!",
	Results = "RESULTS",
}

local player = Players.LocalPlayer
local badges: { [string]: TextLabel } = {}

local STATUS_FADE = 6 -- seconds a status line stays once it stops changing (it comes back when it does)
local ROW_KEEP = 3 -- seconds the line's room stays once it has nothing to say (so mode HUDs don't hop)
local FADE_TIME = 0.6
local SLIDE_TIME = 0.25
local MENU_PEEK = 5 -- seconds the ☰ brings the menu column back for, unless a menu is opened
local LINE_STROKE = 0.2 -- the status line's text stroke

-- Phones and tablets without a keyboard: the HUD keeps clear of the thumbstick and jump button.
local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Level, XP bar and coins follow the profile (both layouts).
local function followProfile(
	levelLabel: TextLabel,
	barFill: Frame,
	xpText: TextLabel,
	badge: GuiObject,
	coins: GuiObject,
	setCoins: (number) -> ()
)
	local shown = 0
	local coinValue = Instance.new("NumberValue")
	coinValue.Changed:Connect(setCoins)
	setCoins(0)
	State.ProfileChanged:Connect(function(profile, previous)
		levelLabel.Text = tostring(profile.Level)
		local ratio = if profile.LevelNeed > 0 then profile.LevelXP / profile.LevelNeed else 1
		UIKit.Tween(barFill, 0.4, { Size = UDim2.fromScale(ratio, 1) })
		if profile.LevelNeed <= 0 then
			xpText.Text = "MAX LEVEL"
		elseif isTouch() then
			xpText.Text = `{profile.LevelXP}/{profile.LevelNeed} XP`
		else
			xpText.Text = `{profile.LevelXP} / {profile.LevelNeed} XP`
		end
		if profile.Coins ~= shown then
			shown = profile.Coins
			UIKit.Tween(coinValue, 0.6, { Value = profile.Coins })
			if previous and profile.Coins > previous.Coins then
				UIKit.PopIn(coins, 0.3)
			end
		end
		if previous and profile.Level > previous.Level then
			UIKit.PopIn(badge, 0.5)
		end
	end)
end

-- The profile chip's holder: a see-through button that opens the Rewards screen.
local function profileHolder(props: { [string]: any }): TextButton
	props.Name = "ProfileChip"
	props.Text = ""
	props.AutoButtonColor = false
	props.BackgroundTransparency = 1
	local holder = UIKit.new("TextButton", props)
	holder.Activated:Connect(function()
		State.OpenScreen:Fire("Rewards")
	end)
	return holder
end

local function buildProfileChip(parent: Instance)
	local width = 310
	local holder = profileHolder({
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.fromOffset(width, 130),
		Parent = parent,
	})
	UIKit.AutoScale(holder)

	local chip = UIKit.Panel({ Size = UDim2.fromOffset(width, 74), CornerRadius = 37, Parent = holder })
	local badge = UIKit.new("Frame", {
		Name = "LevelBadge",
		Size = UDim2.fromOffset(62, 62),
		Position = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = chip,
		Children = {
			UIKit.Round(),
			UIKit.Gradient(Theme.Colors.Yellow, Theme.Colors.Orange),
			UIKit.Stroke(nil, 3, 0.3),
		},
	})
	local levelLabel = UIKit.Label({
		Text = "1",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = badge,
		Children = { UIKit.TextStroke(0.2) },
	})
	local name = UIKit.Label({
		Text = player.DisplayName,
		TextSize = 20,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(80, 8),
		Size = UDim2.new(1, -96, 0, 24),
		Parent = chip,
	})
	name:SetAttribute("PP_TruncateOk", true) -- a long name ends in "..."
	local barBack = UIKit.new("Frame", {
		Position = UDim2.fromOffset(80, 40),
		Size = UDim2.new(1, -100, 0, 18),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = chip,
		Children = { UIKit.Round() },
	})
	local barFill = UIKit.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = barBack,
		Children = { UIKit.Round(), UIKit.Gradient(Theme.Colors.Cyan, Theme.Colors.Green, 0) },
	})
	local xpText = UIKit.Label({
		Text = "",
		TextSize = 14,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = barBack,
		Children = { UIKit.TextStroke(0.3) },
	})

	local coins = UIKit.Panel({
		Name = "Coins",
		Position = UDim2.fromOffset(0, 82),
		Size = UDim2.fromOffset(200, 46),
		CornerRadius = 23,
		Parent = holder,
	}, Color3.fromRGB(255, 196, 60), Color3.fromRGB(230, 130, 30))
	UIKit.Coin({ Position = UDim2.fromOffset(12, 8), Size = UDim2.fromOffset(30, 30), Parent = coins })
	local coinLabel = UIKit.Label({
		Text = "0",
		Font = Theme.Fonts.Display,
		TextSize = 28,
		TextWrapped = false,
		Position = UDim2.fromOffset(46, 0),
		Size = UDim2.new(1, -56, 1, 0),
		Parent = coins,
		Children = { UIKit.TextStroke(0.15) },
	})
	followProfile(levelLabel, barFill, xpText, badge, coins, function(value)
		coinLabel.Text = UIKit.FormatNumber(value)
	end)
end

-- Phones: a small pill (level badge, name, XP bar) with the coins tucked under it, in the top left
-- corner under Roblox's buttons. During a round the standings take its place (RoundController).
local function buildTouchProfile(parent: Instance)
	local holder = profileHolder({
		Position = UDim2.fromOffset(8, 6),
		Size = UDim2.fromOffset(196, 96),
		Parent = parent,
	})
	UIKit.AutoScale(holder)

	local chip = UIKit.Panel({ Size = UDim2.fromOffset(192, 62), CornerRadius = 31, ZIndex = 2, Parent = holder })
	local badge = UIKit.new("Frame", {
		Name = "LevelBadge",
		Size = UDim2.fromOffset(52, 52),
		Position = UDim2.fromOffset(5, 5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = chip,
		Children = {
			UIKit.Round(),
			UIKit.Gradient(Theme.Colors.Yellow, Theme.Colors.Orange),
			UIKit.Stroke(nil, 2, 0.3),
		},
	})
	local levelLabel = UIKit.Label({
		Text = "1",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = badge,
		Children = { UIKit.TextStroke(0.2) },
	})
	local name = UIKit.Label({
		Text = player.DisplayName,
		TextSize = 20,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(64, 6),
		Size = UDim2.fromOffset(118, 24),
		Parent = chip,
	})
	name:SetAttribute("PP_TruncateOk", true)
	local barBack = UIKit.new("Frame", {
		Position = UDim2.fromOffset(64, 33),
		Size = UDim2.fromOffset(118, 22),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = chip,
		Children = { UIKit.Round() },
	})
	local barFill = UIKit.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = barBack,
		Children = { UIKit.Round(), UIKit.Gradient(Theme.Colors.Cyan, Theme.Colors.Green, 0) },
	})
	local xpText = UIKit.Label({
		Text = "",
		TextSize = Theme.Touch.MinText,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = barBack,
		Children = { UIKit.TextStroke(0.3) },
	})

	-- The coins: a gold tab under the pill, as wide as the number.
	local coins = UIKit.Panel({
		Name = "Coins",
		Position = UDim2.fromOffset(12, 52),
		Size = UDim2.fromOffset(110, 42),
		CornerRadius = 18,
		ZIndex = 1,
		Parent = holder,
	}, Color3.fromRGB(255, 196, 60), Color3.fromRGB(230, 130, 30))
	UIKit.Coin({ Position = UDim2.fromOffset(10, 14), Size = UDim2.fromOffset(24, 24), Parent = coins })
	local coinLabel = UIKit.Label({
		Text = "0",
		Font = Theme.Fonts.Display,
		TextSize = 24,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(40, 10),
		Size = UDim2.new(1, -46, 0, 32),
		Parent = coins,
		Children = { UIKit.TextStroke(0.15) },
	})
	local function fitCoins()
		local width = UIKit.TextWidth(coinLabel.Text, 24, Theme.Fonts.Display)
		coins.Size = UDim2.fromOffset(math.max(84, math.ceil(width) + 56), 42)
	end
	followProfile(levelLabel, barFill, xpText, badge, coins, function(value)
		coinLabel.Text = UIKit.FormatNumber(value)
		fitCoins()
	end)
	task.delay(3, fitCoins) -- again once the font has surely loaded

	-- The standings use this corner during a round.
	local function refresh()
		holder.Visible = GameState.Get("Phase") ~= "InRound"
	end
	GameState.Changed("Phase", refresh)
	refresh()
end

-- The words, timer and urgency both banners show.
local function bannerTitle(touch: boolean): string
	local phase = GameState.Get("Phase") or "Waiting"
	local gameId = GameState.Get("GameId")
	local definition = gameId ~= "" and GameDefinitions.Get(gameId)
	local message = GameState.Get("Message") or ""
	local icon = PHASE_ICONS[phase] or "🎉"
	if touch and SHORT_TITLES[phase] then
		return `{icon} {SHORT_TITLES[phase]}`
	elseif (phase == "InRound" or phase == "Preparing" or phase == "Results") and definition then
		return `{definition.Icon} {definition.Name}`
	end
	return `{icon} {if message ~= "" then message else phase}`
end

-- The line under the banner during a round: the mode's status ("Tap ADD when..."), mostly meant
-- for its players, without its players-left count (`rest`: that's the banner's pill). Anyone not in
-- this round gets their own line instead.
local function statusLine(phase: string, rest: string): string
	if phase ~= "InRound" then
		return ""
	elseif State.InRound() then
		return rest
	elseif State.SittingOut() then
		return "💤 Sitting out - tap to jump in next round"
	end
	return "🎮 You're in the next round!"
end

-- The banner's count pill during a round: the players-left number from the mode's status line
-- (Logic/RoundHud), with its icon ("👤 6", "🏃 3"); "" when there's none.
local function countText(): string
	if GameState.Get("Phase") ~= "InRound" then
		return ""
	end
	local count, icon = RoundHud.SplitStatus(GameState.Get("Status"))
	return if count then `{icon} {count}` else ""
end

-- Keeps the count pill on countText (both layouts), as wide as its words, popping when the number
-- changes; `onChanged` runs whenever it comes, goes or changes width, for the banner to make room.
local function followCount(pill: Frame, label: TextLabel, textSize: number, pad: number, onChanged: () -> ())
	local shown = ""
	RunService.Heartbeat:Connect(function()
		local text = countText()
		if text == shown then
			return
		end
		local before = shown
		shown = text
		label.Text = text
		pill.Visible = text ~= ""
		if text ~= "" then
			pill.Size = UDim2.fromOffset(
				math.ceil(UIKit.TextWidth(text, textSize, Theme.Fonts.Display)) + pad,
				pill.Size.Y.Offset
			)
			if before ~= "" and not State.ReducedEffects() then
				UIKit.PopIn(pill, 0.25)
			end
		end
		onChanged()
	end)
end

-- Shows or hides a line's words (and their stroke) with a fade, or at once with `time` 0 (a tween
-- all the same: it takes over from a fade still running, which setting the values wouldn't stop).
local function fadeText(label: TextLabel, shown: boolean, time: number)
	local stroke = label:FindFirstChildOfClass("UIStroke")
	local transparency = if shown then 0 else 1
	UIKit.Tween(label, time, { TextTransparency = transparency })
	if stroke then
		UIKit.Tween(stroke, time, { Transparency = if shown then LINE_STROKE else 1 })
	end
	if time <= 0 then
		label.TextTransparency = transparency
		if stroke then
			stroke.Transparency = if shown then LINE_STROKE else 1
		end
	end
end

-- The status line's row under the banner (both layouts), in its holder's scaled units: where the
-- line starts and how tall it is, where the team pill sits with the line out of the way, and where
-- the line ends in the layout Kit/Api's HudY expects.
type StatusRow = {
	Label: TextLabel,
	Teams: Frame,
	LineTop: number,
	LineHeight: number,
	CollapsedTop: number,
	Base: number,
	Strip: Frame?, -- phones: the round callout strip, in the line's place while it's up
}

-- Keeps the status row: the line's words (fading once they've gone STATUS_FADE seconds without
-- changing, for the round's players), the row's room (kept while the line or a callout has
-- something to say, let go ROW_KEEP seconds after), the team pill under it and State.TopHudShift.
local function followStatusRow(row: StatusRow)
	local label = row.Label
	local shownText = ""
	local changedAt = 0
	local faded = false
	local fadeToken = 0
	local reserved = true -- the line has room (today's layout until a round says otherwise)
	local emptySince: number? = nil
	local teamsY = -1
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local phase = GameState.Get("Phase") or "Waiting"
		local _, _, rest = RoundHud.SplitStatus(GameState.Get("Status"))
		local participant = State.InRound()
		local text = statusLine(phase, rest)
		local strip = row.Strip
		local calloutUp = strip ~= nil and strip.Visible

		-- The words: back at once when they change; for the round's players, gone after a while.
		if text ~= shownText then
			shownText = text
			changedAt = now
			label.Text = text
			if faded then
				faded = false
				fadeToken += 1
				fadeText(label, true, 0)
			end
		end
		if not faded and participant and text ~= "" and now - changedAt >= STATUS_FADE then
			faded = true
			fadeToken += 1
			local token = fadeToken
			fadeText(label, false, FADE_TIME)
			task.delay(FADE_TIME, function()
				if token == fadeToken then
					label.Visible = false
				end
			end)
		end
		if not faded then
			label.Visible = text ~= "" and not calloutUp
		elseif calloutUp then
			label.Visible = false
		end

		-- The room: kept while there's something to say (the line, even faded, or a callout), let go
		-- a few seconds after there's nothing; decided before and during the round only, so the mode
		-- HUD is already in place at GO and stays put through the results.
		if phase == "Preparing" or phase == "InRound" then
			local wanted = calloutUp or (if participant then rest ~= "" else true)
			if wanted then
				reserved = true
				emptySince = nil
			elseif reserved then
				emptySince = emptySince or now
				if now - (emptySince :: number) >= ROW_KEEP then
					reserved = false
				end
			end
		end

		-- The team pill under the line, and the mode HUDs under both.
		local height = if calloutUp and strip then math.max(row.LineHeight, strip.Size.Y.Offset) else row.LineHeight
		local top = if reserved then row.LineTop + height + 4 else row.CollapsedTop
		if top ~= teamsY then
			local first = teamsY < 0
			teamsY = top
			local goal = UDim2.new(0.5, 0, 0, top)
			if first or State.ReducedEffects() then
				row.Teams.Position = goal
			else
				UIKit.Tween(row.Teams, SLIDE_TIME, { Position = goal })
			end
		end
		State.SetTopHudShift(top - (row.Base + 4))
	end)
end

-- The round's team scores, team by team (the team pill under the status line): every team in the
-- round with its mark and score, whatever the mode calls its teams. Colour teams wear their shape in
-- the team's colour (★ Red, ● Blue, ▲ Green, ◆ Yellow: Teams.Shapes), so colour is never the only
-- cue; versus roles their icon (🏹 Archers / 🏃 Runners, 💎 Divers / 👑 SandKings, 🦈 Sharks /
-- 🏊 Swimmers). Two teams read "★ 12 — 9 ●", three or four "★ 12  ● 9  ▲ 7  ◆ 3". The player's own
-- team (`mine`) says so on its outer side: "YOU ★ 12 — 9 ●", "★ 12 — 9 ● YOU". Returns each team's
-- words in order (RichText, and plain to measure) and whether they're the player's team.
type TeamPart = { Team: string, Rich: string, Plain: string, Mine: boolean }
local function teamScoreParts(scores: { [string]: any }, mine: string?): { TeamPart }
	local names = {}
	for _, team in Teams.Order do
		if scores[team] ~= nil then
			table.insert(names, team)
		end
	end
	local others = {}
	for name in scores do
		if not table.find(Teams.Order, name) then
			table.insert(others, name)
		end
	end
	table.sort(others)
	for _, name in others do
		table.insert(names, name)
	end
	local parts = {}
	for index, name in names do
		local value = scores[name]
		local score = if type(value) == "number" then tostring(value) else "0"
		local shape = Teams.Shapes[name]
		local color = Teams.Colors[name]
		local mark = shape or Teams.Icons[name] or string.upper(name)
		local shown = if shape and color then `<font color="#{color:ToHex()}">{shape}</font>` else mark
		local right = #names == 2 and index == 2 -- the second of two reads "9 ●"
		local you = name == mine
		local function words(sign: string): string
			return if right
				then `{score} {sign}{if you then " YOU" else ""}`
				else `{if you then "YOU " else ""}{sign} {score}`
		end
		table.insert(parts, { Team = name, Rich = words(shown), Plain = words(mark), Mine = you })
	end
	return parts
end

-- Keeps a team pill on the round's team scores (both layouts): hidden outside team rounds, each
-- team's words in their own label side by side, and the pill as wide as they are, so four teams with
-- 3-digit scores fit the smallest phone (re-measured every second while it shows, in case the font
-- was still loading). The player's own team (PP_Team) has its "YOU" and a box round its words, a
-- deep shade of its colour with a white rim (owner: "I couldnt tell what color I was on prime
-- cut."): the box is that label's own background, so it always sits round its words, and the team's
-- shape still stands out on it. While the rules card is up the pill steps aside: the card's own tab
-- says your team then, and on PC the card covers the pill's lower half.
local TEAM_TEXT, TEAM_PAD, TEAM_MIN, TEAM_MAX = 24, 22, 160, 600
local PART_PAD = 8 -- room round each team's words (the player's box reaches this far past them)
local PART_GAP = 2 -- between two teams' words (with their room, 18), and round the "—" of two
local function followTeamScores(pill: Frame)
	local row = UIKit.new("Frame", {
		Name = "Row",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = pill,
		Children = {
			UIKit.List(
				Enum.FillDirection.Horizontal,
				PART_GAP,
				Enum.HorizontalAlignment.Center,
				Enum.VerticalAlignment.Center
			),
		},
	})
	type Slot = { Frame: Frame, Words: TextLabel, Rim: UIStroke }
	local slots: { Slot } = {}
	local function slotAt(index: number): Slot
		local existing = slots[index]
		if existing then
			return existing
		end
		local rim = UIKit.Stroke(Color3.new(1, 1, 1), 2, 0)
		local frame = UIKit.new("Frame", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, -8),
			BackgroundColor3 = Theme.Colors.PanelDark,
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Parent = row,
			Children = { UIKit.Round(), rim, UIKit.Padding(0, PART_PAD) },
		})
		local words = UIKit.Label({
			Name = "Words",
			Text = "",
			Font = Theme.Fonts.Display,
			TextSize = TEAM_TEXT,
			TextWrapped = false,
			RichText = true,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			Parent = frame,
			Children = { UIKit.TextStroke(0.2) },
		})
		local made = { Frame = frame, Words = words, Rim = rim }
		slots[index] = made
		return made
	end
	local shown: { string } = {} -- the plain words of what's in the pill, to measure
	local fittedAt = 0
	local function fit()
		fittedAt = os.clock()
		local width = 2 * (TEAM_PAD - PART_PAD) + PART_GAP * math.max(#shown - 1, 0)
		for _, words in shown do
			width += math.ceil(UIKit.TextWidth(words, TEAM_TEXT, Theme.Fonts.Display)) + 2 * PART_PAD
		end
		pill.Size = UDim2.fromOffset(math.clamp(width, TEAM_MIN, TEAM_MAX), pill.Size.Y.Offset)
	end
	local function refresh()
		local scores = GameState.GetJSON("TeamScores")
		if type(scores) ~= "table" or next(scores) == nil or player:GetAttribute("PP_RulesShowing") == true then
			pill.Visible = false
			return
		end
		pill.Visible = true
		local mine = player:GetAttribute("PP_Team")
		local parts = teamScoreParts(scores, if type(mine) == "string" then mine else nil)
		-- (Two teams face each other across a "—".)
		local items: { TeamPart } = {}
		for index, part in parts do
			if #parts == 2 and index == 2 then
				table.insert(items, { Team = "", Rich = "—", Plain = "—", Mine = false })
			end
			table.insert(items, part)
		end
		local plain = {}
		for index, item in items do
			local slot = slotAt(index)
			local color = if item.Mine then Teams.Colors[item.Team] else nil
			slot.Frame.Name = if item.Team ~= "" then `Team_{item.Team}` else "Versus"
			slot.Frame.Visible = true
			slot.Frame.BackgroundTransparency = if item.Mine then 0.1 else 1
			slot.Frame.BackgroundColor3 = if color then color:Lerp(Color3.new(0, 0, 0), 0.5) else Theme.Colors.PanelDark
			slot.Rim.Enabled = item.Mine
			slot.Words.Text = item.Rich
			table.insert(plain, item.Plain)
		end
		for index = #items + 1, #slots do
			slots[index].Frame.Visible = false
		end
		if table.concat(plain, "|") ~= table.concat(shown, "|") then
			shown = plain
			fit()
		end
	end
	GameState.Changed("TeamScores", refresh)
	player:GetAttributeChangedSignal("PP_Team"):Connect(refresh)
	player:GetAttributeChangedSignal("PP_RulesShowing"):Connect(refresh)
	refresh()
	RunService.Heartbeat:Connect(function()
		if pill.Visible and os.clock() - fittedAt > 1 then
			fit()
		end
	end)
end

local function followTimer(timerPill: Frame, timer: TextLabel)
	local lastWhole = -1
	RunService.Heartbeat:Connect(function()
		local phase = GameState.Get("Phase") or "Waiting"
		local left = GameState.TimeLeft()
		timerPill.Visible = GameState.Get("PhaseEndsAt") > 0
		timer.Text = UIKit.FormatTime(left)
		local whole = math.ceil(left)
		-- Urgency: the timer turns red and pulses in the last 10 seconds of a round, and the last 3 of
		-- the vote (it's only 8 long now, owner: "Less time sitting in the lobby").
		local urgent = left > 0 and ((phase == "InRound" and left <= 10) or (phase == "Voting" and left <= 3))
		timer.TextColor3 = if urgent then Theme.Colors.Red else Theme.Colors.Yellow
		if urgent and whole ~= lastWhole then
			UIKit.PopIn(timerPill, 0.25)
		end
		lastWhole = whole
	end)
end

local function buildPhaseBanner(parent: Instance)
	local width = 520
	local holder = UIKit.new("Frame", {
		Name = "PhaseBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(width, 150),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UIKit.AutoScale(holder)
	local banner = UIKit.Panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(width, 70),
		CornerRadius = 35,
		Parent = holder,
	})
	local title = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(28, 0),
		Size = UDim2.new(1, -170, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = banner,
		Children = { UIKit.TextStroke(0.3) },
	})
	title:SetAttribute("PP_Lines", 2) -- PC: a long message ("Waiting for 1 more player...") takes two lines
	local timerPill = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(124, 52),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = banner,
		Children = { UIKit.Round() },
	})
	local timer = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 34,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		TextColor3 = Theme.Colors.Yellow,
		Parent = timerPill,
	})
	-- The players left, beside the timer (the title makes room).
	local countPill = UIKit.new("Frame", {
		Name = "Count",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(10 + 124 + 10), 0.5, 0),
		Size = UDim2.fromOffset(90, 52),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Visible = false,
		Parent = banner,
		Children = { UIKit.Round() },
	})
	local countLabel = UIKit.Label({
		Name = "Text",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = countPill,
	})
	local status = UIKit.Label({
		Name = "Status",
		Text = "",
		TextSize = 22,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 76),
		Size = UDim2.fromOffset(620, 28),
		Parent = holder,
		Children = { UIKit.TextStroke(LINE_STROKE) },
	})
	local teams = UIKit.Panel({
		Name = "TeamScores",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 108),
		Size = UDim2.fromOffset(360, 40),
		CornerRadius = 20,
		Visible = false,
		Parent = holder,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)

	followTimer(timerPill, timer)
	local function makeRoom()
		local count = if countPill.Visible then countPill.Size.X.Offset + 10 else 0
		title.Size = UDim2.new(1, -170 - count, 1, 0)
		countPill.Position = UDim2.new(1, if timerPill.Visible then -(10 + 124 + 10) else -10, 0.5, 0)
	end
	followCount(countPill, countLabel, 30, 28, makeRoom)
	timerPill:GetPropertyChangedSignal("Visible"):Connect(makeRoom)
	RunService.Heartbeat:Connect(function()
		title.Text = bannerTitle(false)
	end)
	-- The line ends 104 down (76 + 28); without it the team pill sits 6 under the banner.
	followStatusRow({ Label = status, Teams = teams, LineTop = 76, LineHeight = 28, CollapsedTop = 76, Base = 104 })
	followTeamScores(teams)
end

-- Phones: the banner sits in Roblox's top bar row (its own ScreenGui inside the device's safe area,
-- level with Roblox's 44 pt buttons), centered, one short line as wide as its words. The sit-out
-- switch rides on its right, in the same row and at the same height (clear of the vote cards and
-- the menu under the top bar).
local TOUCH_BANNER_HEIGHT = 66
local SIT_OUT_GAP = 10 -- between the banner and the sit-out switch
local function buildTopBarBanner(hud: Instance): ScreenGui
	local gui = UIKit.new("ScreenGui", {
		Name = "PartyPanicTopBar",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
	})
	-- Clear of the notch and home bar but not of the top bar (set in this order: either property
	-- alone would do it, and the last one set wins).
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.Parent = hud.Parent
	local holder = UIKit.new("Frame", {
		Name = "PhaseBanner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 34), -- Roblox's buttons run from 12 to 55 pt
		Size = UDim2.fromOffset(700, TOUCH_BANNER_HEIGHT),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UIKit.AutoScale(holder, 0.8) -- phone size on tablets too, like Roblox's own buttons
	local banner = UIKit.Panel({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(300, TOUCH_BANNER_HEIGHT),
		CornerRadius = TOUCH_BANNER_HEIGHT / 2,
		Parent = holder,
	})
	local sitOut = SitOutSwitch.new(holder, { Name = "SitOut", Hud = true, AnchorPoint = Vector2.new(0, 0.5) })
	local title = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(20, 0),
		Size = UDim2.fromOffset(200, TOUCH_BANNER_HEIGHT),
		Parent = banner,
		Children = { UIKit.TextStroke(0.3) },
	})
	local timerPill = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -7, 0.5, 0),
		Size = UDim2.fromOffset(88, 52),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = banner,
		Children = { UIKit.Round() },
	})
	local timer = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 28,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		TextColor3 = Theme.Colors.Yellow,
		Parent = timerPill,
	})
	followTimer(timerPill, timer)
	-- The players left, between the title and the timer.
	local countPill = UIKit.new("Frame", {
		Name = "Count",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(7 + 88 + 8), 0.5, 0),
		Size = UDim2.fromOffset(70, 52),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Visible = false,
		Parent = banner,
		Children = { UIKit.Round() },
	})
	local countLabel = UIKit.Label({
		Name = "Text",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = countPill,
	})
	local measuredFor = ""
	followCount(countPill, countLabel, 26, 24, function()
		measuredFor = "" -- the banner makes room for it at once
	end)

	-- As wide as the words (re-measured every second too, in case the font was still loading).
	local measuredAt = 0
	RunService.Heartbeat:Connect(function()
		local text = bannerTitle(true)
		title.Text = text
		local key = `{text}|{timerPill.Visible}|{countPill.Visible and countLabel.Text}`
		if key == measuredFor and os.clock() - measuredAt < 1 then
			return
		end
		measuredFor, measuredAt = key, os.clock()
		local width = math.ceil(UIKit.TextWidth(text, 26, Theme.Fonts.Display)) + 4
		title.Size = UDim2.fromOffset(width, TOUCH_BANNER_HEIGHT)
		local count = if countPill.Visible then countPill.Size.X.Offset + 8 else 0
		countPill.Position = UDim2.new(1, if timerPill.Visible then -(7 + 88 + 8) else -7, 0.5, 0)
		local bannerWidth = 20 + width + count + (if timerPill.Visible then 12 + 88 + 7 else 20)
		banner.Size = UDim2.fromOffset(bannerWidth, TOUCH_BANNER_HEIGHT)
		sitOut.Position = UDim2.new(0.5, bannerWidth / 2 + SIT_OUT_GAP, 0.5, 0)
	end)
	return gui
end

-- PC: the sit-out switch sits in Roblox's top bar row too (free in the middle), right above the
-- phase banner, at about the size of Roblox's own buttons (that row doesn't grow with the screen).
local PC_TOP_BAR_SCALE = 0.75
local function buildTopBarSwitch(hud: Instance): ScreenGui
	local gui = UIKit.new("ScreenGui", {
		Name = "PartyPanicTopBar",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
	})
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.Parent = hud.Parent
	local holder = UIKit.new("Frame", {
		Name = "SitOutHolder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 34), -- level with Roblox's buttons (12 to 55)
		Size = UDim2.fromOffset(400, 72),
		BackgroundTransparency = 1,
		Parent = gui,
		Children = { UIKit.new("UIScale", { Scale = PC_TOP_BAR_SCALE }) },
	})
	SitOutSwitch.new(holder, { Name = "SitOut", Hud = true })
	return gui
end

-- Phones: the round's status line and team scores (teamScoreLine), just under the top bar in the
-- middle. Mode HUDs go under them (Api.TopHud / HudY, moved by State.TopHudShift).
-- The round's callouts (State.RoundCallout, from NotificationController) take the line's place one
-- at a time: a compact strip as wide as its words (up to 560 units, clear of the standings), on two
-- lines if it must, with the kind's icon and its colour on the rim.
local CALLOUT_TEXT, CALLOUT_PAD, CALLOUT_MAX = 20, 12, 560
local function buildTouchStatus(parent: Instance)
	local holder = UIKit.new("Frame", {
		Name = "RoundStatus",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(620, 110),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UIKit.AutoScale(holder)
	local status = UIKit.Label({
		Name = "Status",
		Text = "",
		TextSize = 22,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(600, 30),
		Parent = holder,
		Children = { UIKit.TextStroke(LINE_STROKE) },
	})
	local teams = UIKit.Panel({
		Name = "TeamScores",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.fromOffset(240, 42),
		CornerRadius = 21,
		Visible = false,
		Parent = holder,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	local strip = UIKit.Panel({
		Name = "Callout",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(300, 30),
		CornerRadius = 15,
		Visible = false,
		Parent = holder,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	local rim = strip:FindFirstChildOfClass("UIStroke") :: UIStroke
	rim.Thickness = 2
	rim.Transparency = 0.1
	local words = UIKit.Label({
		Name = "Text",
		Text = "",
		TextSize = CALLOUT_TEXT,
		Size = UDim2.fromScale(1, 1),
		Parent = strip,
		Children = { UIKit.Padding(5, CALLOUT_PAD) },
	})
	local token = 0
	State.RoundCallout:Connect(function(message: string, color: Color3, duration: number)
		token += 1
		local mine = token
		local width = math.ceil(UIKit.TextWidth(message, CALLOUT_TEXT, Theme.Fonts.Bold)) + 2 * CALLOUT_PAD + 4
		local lines = if width <= CALLOUT_MAX
			then 1
			else UIKit.TextLines(message, CALLOUT_TEXT, Theme.Fonts.Bold, CALLOUT_MAX - 2 * CALLOUT_PAD)
		words.Text = message
		words.TextWrapped = lines > 1
		strip.Size = UDim2.fromOffset(math.min(width, CALLOUT_MAX), lines * CALLOUT_TEXT + 10)
		rim.Color = color
		strip.Visible = true
		if not State.ReducedEffects() then
			UIKit.PopIn(strip, 0.25)
		end
		task.delay(duration, function()
			if mine == token then
				strip.Visible = false
			end
		end)
	end)
	GameState.Changed("Phase", function(phase)
		if phase ~= "InRound" then
			token += 1
			strip.Visible = false
		end
	end)
	-- The line ends 36 down (6 + 30); without it the team pill sits just under the top bar.
	followStatusRow({
		Label = status,
		Teams = teams,
		LineTop = 6,
		LineHeight = 30,
		CollapsedTop = 4,
		Base = 36,
		Strip = strip,
	})
	followTeamScores(teams)
end

local function menuButton(
	parent: Instance,
	name: string,
	icon: string,
	caption: string,
	order: number,
	top: Color3,
	bottom: Color3
): TextButton
	local touch = isTouch()
	local size = if touch then Theme.Touch.Target else 74
	local button = UIKit.Button({
		Name = name,
		Text = icon,
		TextSize = if touch then 34 else 36,
		Size = UDim2.fromOffset(size, size),
		CornerRadius = if touch then 22 else 24,
		LayoutOrder = order,
		Parent = parent,
	}, function()
		State.OpenScreen:Fire(name)
	end, top, bottom)
	UIKit.Label({
		Text = caption,
		TextSize = if touch then Theme.Touch.MinText else 15,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, if touch then 4 else 2),
		Size = UDim2.new(1, if touch then 20 else 10, 0, if touch then 20 else 18),
		Parent = button,
		Children = { UIKit.TextStroke(0.1) },
	})
	local badge = UIKit.Label({
		Name = "Badge",
		Text = "!",
		Font = Theme.Fonts.Display,
		TextSize = 20,
		TextWrapped = false,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Colors.Red,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(if touch then 30 else 26, if touch then 30 else 26),
		Visible = false,
		Parent = button,
		Children = { UIKit.Round() },
	})
	badges[name] = badge
	return button
end

local function buildMenu(parent: Instance): Frame
	-- PC: the middle of the right edge. Touch: down from the top right corner, where it can't be
	-- hit by mistake when reaching for the jump button.
	local touch = isTouch()
	local gap = if touch then 12 else 14
	local menu = UIKit.new("Frame", {
		Name = "Menu",
		AnchorPoint = if touch then Vector2.new(1, 0) else Vector2.new(1, 0.5),
		Position = if touch then UDim2.new(1, -8, 0, 6) else UDim2.new(1, -14, 0.5, 0),
		Size = if touch
			then UDim2.fromOffset(Theme.Touch.Target + 20, 4 * Theme.Touch.Target + 3 * gap + 6)
			else UDim2.fromOffset(80, 360),
		BackgroundTransparency = 1,
		Parent = parent,
		Children = {
			UIKit.List(
				Enum.FillDirection.Vertical,
				gap,
				Enum.HorizontalAlignment.Center,
				if touch then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Center
			),
		},
	})
	UIKit.AutoScale(menu)
	menuButton(menu, "Shop", "🛍️", "Shop", 1, Theme.Colors.Pink, Color3.fromRGB(200, 50, 140))
	menuButton(menu, "Quests", "📜", "Quests", 2, Theme.Colors.Yellow, Theme.Colors.Orange)
	menuButton(menu, "Emotes", "🕺", "Emotes", 3, Theme.Colors.Cyan, Color3.fromRGB(50, 120, 230))
	menuButton(menu, "Settings", "⚙️", "Settings", 4, Theme.Colors.Lavender, Theme.Colors.Purple)

	State.ProfileChanged:Connect(function(profile)
		local claimable = profile.Daily.CanClaim
		badges.Quests.Visible = claimable
	end)
	return menu
end

-- The ☰ that stands in for the menu column while the player is playing a round: in Roblox's top
-- bar row, in the top right corner (phones: a 44 pt button level with Roblox's own; PC: their size,
-- like the sit-out switch in that row), with the column's "!" on it when a tile has one. Three
-- drawn bars, since the ☰ character draws as a missing-glyph box in the game's fonts.
local TOGGLE_SIZE, TOGGLE_BAR_W, TOGGLE_BAR_H, TOGGLE_BAR_GAP = 72, 34, 6, 12
local function buildMenuToggle(topBar: ScreenGui, onClick: () -> ()): Frame
	local touch = isTouch()
	local holder = UIKit.new("Frame", {
		Name = "MenuToggle",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0, 34), -- level with Roblox's buttons (12 to 55)
		Size = UDim2.fromOffset(TOGGLE_SIZE, TOGGLE_SIZE),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = topBar,
	})
	if touch then
		UIKit.AutoScale(holder, 0.8) -- phone size on tablets too, like the banner beside it
	else
		UIKit.new("UIScale", { Scale = PC_TOP_BAR_SCALE, Parent = holder })
	end
	-- (Its pop-in scales this frame: the holder's UIScale is the screen's, the button's its press.)
	local pop = UIKit.new("Frame", {
		Name = "Pop",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	local button = UIKit.Button({
		Name = "Button",
		Text = "",
		Size = UDim2.fromScale(1, 1),
		CornerRadius = 22,
		Parent = pop,
	}, onClick, Theme.Colors.Lavender, Theme.Colors.Purple)
	for index = 1, 3 do
		UIKit.new("Frame", {
			Name = `Bar{index}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, (index - 2) * TOGGLE_BAR_GAP),
			Size = UDim2.fromOffset(TOGGLE_BAR_W, TOGGLE_BAR_H),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Parent = button,
			Children = { UIKit.Round(), UIKit.Stroke(Color3.fromRGB(30, 15, 60), 1, 0.5) },
		})
	end
	local badge = UIKit.Label({
		Name = "Badge",
		Text = "!",
		Font = Theme.Fonts.Display,
		TextSize = 20,
		TextWrapped = false,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Colors.Red,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(if touch then 30 else 26, if touch then 30 else 26),
		Visible = false,
		Parent = button,
		Children = { UIKit.Round() },
	})
	local function refreshBadge()
		local any = false
		for _, tileBadge in badges do
			any = any or tileBadge.Visible
		end
		badge.Visible = any
	end
	for _, tileBadge in badges do
		tileBadge:GetPropertyChangedSignal("Visible"):Connect(refreshBadge)
	end
	refreshBadge()
	return holder
end

-- Tucks the menu column away while the player is playing a round (State.PlayingRound) and shows
-- the ☰ instead; a tap on it brings the column back until a menu has been opened and closed, or
-- MENU_PEEK seconds pass with none opened. The column slides off the right edge and back (at once
-- with reduced effects).
local function followMenu(hud: Instance, menu: Frame, topBar: ScreenGui)
	local restAnchor, restPosition = menu.AnchorPoint, menu.Position
	local awayAnchor = Vector2.new(0, restAnchor.Y) -- its left edge just past the screen's right edge
	local awayPosition = UDim2.new(1, 8, restPosition.Y.Scale, restPosition.Y.Offset)
	local shown = true
	local peeking = false
	local peekUntil = 0
	local menuSeen = false -- a menu was opened while the column was back
	local windowOpen = false
	local emotes: GuiObject? = nil -- EmoteController's picker (it starts after this)

	local function emotesOpen(): boolean
		if not emotes or not emotes.Parent then
			emotes = nil
			for _, item in hud:GetDescendants() do
				if item.Name == "Emotes" and item:IsA("Frame") and item:GetAttribute("PP_Popup") then
					emotes = item
					break
				end
			end
		end
		return emotes ~= nil and emotes.Visible
	end

	local function setShown(value: boolean)
		if value == shown then
			return
		end
		shown = value
		local instant = State.ReducedEffects()
		if value then
			menu.Visible = true
			if instant then
				menu.AnchorPoint, menu.Position = restAnchor, restPosition
			else
				menu.AnchorPoint, menu.Position = awayAnchor, awayPosition
				UIKit.Tween(menu, SLIDE_TIME, { AnchorPoint = restAnchor, Position = restPosition })
			end
		elseif instant then
			menu.Visible = false
		else
			local tween = UIKit.Tween(
				menu,
				SLIDE_TIME,
				{ AnchorPoint = awayAnchor, Position = awayPosition },
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			)
			tween.Completed:Connect(function()
				if not shown then
					menu.Visible = false
				end
			end)
		end
	end

	local toggle: Frame
	local function refresh()
		local playing = State.PlayingRound()
		if not playing then
			peeking = false
		end
		setShown(not playing or peeking)
		if toggle.Visible ~= playing then
			toggle.Visible = playing
			if playing and not State.ReducedEffects() then
				UIKit.PopIn(toggle:FindFirstChild("Pop") :: Frame, 0.3)
			end
		end
	end
	-- (HudController.ToggleMenu: the client harness taps it this way.)
	function HudController.ToggleMenu()
		if not State.PlayingRound() then
			return
		end
		peeking = not peeking
		peekUntil = os.clock() + MENU_PEEK
		menuSeen = false
		refresh()
	end
	toggle = buildMenuToggle(topBar, HudController.ToggleMenu)

	State.OnPlayingChanged(refresh)
	Modal.AnyOpenChanged:Connect(function(open)
		windowOpen = open
	end)
	-- While the column is back: a menu opened keeps it there until that menu closes.
	RunService.Heartbeat:Connect(function()
		if not peeking then
			return
		end
		if windowOpen or emotesOpen() then
			menuSeen = true
		elseif menuSeen or os.clock() >= peekUntil then
			peeking = false
			refresh()
		end
	end)
	refresh()
end

local function toggleRow(
	parent: Instance,
	order: number,
	label: string,
	getter: () -> boolean,
	onToggle: (boolean) -> ()
)
	local touch = isTouch()
	local row = UIKit.new("Frame", {
		Size = UDim2.new(1, 0, 0, if touch then 76 else 64),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.Label({
		Text = label,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -150, 1, 0),
		Parent = row,
	})
	local button
	button = UIKit.Button({
		Text = "",
		TextSize = 22,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(130, if touch then Theme.Touch.Target else 50),
		CornerRadius = 25,
		Parent = row,
	}, function()
		onToggle(not getter())
	end, Theme.Colors.Green, Color3.fromRGB(60, 170, 90))
	local function refresh()
		button.Text = if getter() then "ON" else "OFF"
	end
	State.ProfileChanged:Connect(refresh)
	refresh()
end

local MUSIC_LEVELS = {
	{ Value = 0, Label = "🔇 Off" },
	{ Value = 0.25, Label = "🔈 Low" },
	{ Value = 0.5, Label = "🔉 Medium" },
	{ Value = 1, Label = "🔊 High" },
}

local function musicRow(parent: Instance, order: number, setSetting: RemoteEvent)
	local touch = isTouch()
	local row = UIKit.new("Frame", {
		Size = UDim2.new(1, 0, 0, if touch then 76 else 64),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.Label({
		Text = "🎵 Music volume",
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -190, 1, 0),
		Parent = row,
	})
	local function currentIndex(): number
		local volume = State.Setting("MusicVolume")
		if type(volume) ~= "number" then
			return 3
		end
		local best, bestDistance = 1, math.huge
		for index, level in MUSIC_LEVELS do
			local distance = math.abs(level.Value - volume)
			if distance < bestDistance then
				best, bestDistance = index, distance
			end
		end
		return best
	end
	local button
	button = UIKit.Button({
		Text = "",
		TextSize = 22,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(170, if touch then Theme.Touch.Target else 50),
		CornerRadius = 25,
		Parent = row,
	}, function()
		local nextLevel = MUSIC_LEVELS[(currentIndex() % #MUSIC_LEVELS) + 1]
		setSetting:FireServer("MusicVolume", nextLevel.Value)
	end, Theme.Colors.Cyan, Color3.fromRGB(50, 120, 230))
	local function refresh()
		button.Text = MUSIC_LEVELS[currentIndex()].Label
	end
	State.ProfileChanged:Connect(refresh)
	refresh()
end

-- The sit-out switch again, first in Settings: "Next round: PLAYING / SITTING OUT".
local function sitOutRow(parent: Instance, order: number)
	local row = UIKit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 76),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	local switch = SitOutSwitch.new(row, {
		Name = "SitOutSwitch",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
	})
	UIKit.Label({
		Text = "🎮 Next round",
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -(switch.Size.X.Offset + 24), 1, 0),
		Parent = row,
	})
end

-- The GOLD PASS teaser in the Settings window's title bar, left of its X: a shining gold pill that
-- opens the Rewards screen on the gold lane.
local function goldTeaser(modal: Modal.Modal)
	local touch = isTouch()
	local title = Modal.TitleHeight()
	local button = UIKit.Button({
		Name = "GoldTeaser",
		Text = "",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, if touch then -58 else -50, 0, -(title + 6) + title / 2 + 2),
		Size = UDim2.fromOffset(if touch then 214 else 196, if touch then Theme.Touch.Target else 48),
		CornerRadius = "round",
		ZIndex = 25,
		Parent = modal.Content,
	}, function()
		State.OpenScreen:Fire("Rewards", "Road")
	end, GoldPass.Colors.Gold, GoldPass.Colors.Deep)
	local fill = button:FindFirstChildOfClass("UIGradient")
	if fill then
		fill.Color = GoldPassController.Fill().Color
	end
	local rim = button:FindFirstChildOfClass("UIStroke")
	if rim then
		rim.Color, rim.Thickness, rim.Transparency = GoldPass.Colors.Shine, 2.5, 0
	end
	GoldPassController.Glint(button)
	local label = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 22 else 21,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 27,
		Parent = button,
		Children = {
			UIKit.new("UIStroke", {
				Color = GoldPass.Colors.Ink,
				Thickness = 2,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			}),
		},
	})
	local function refresh()
		label.Text = if GoldPassController.Owned() then `{GoldPass.Icon} GOLD ✓` else `{GoldPass.Icon} GOLD PASS`
	end
	State.ProfileChanged:Connect(refresh)
	refresh()
end

local function buildSettings(overlay: Instance)
	local touch = isTouch()
	local modal = Modal.new(overlay, "Settings", "⚙️", Vector2.new(560, if touch then 450 else 420))
	local list = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = modal.Content,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 10) },
	})
	local setSetting = Remotes.Get("SetSetting")
	sitOutRow(list, 0)
	musicRow(list, 1, setSetting)
	toggleRow(list, 2, "✨ Reduced effects", function()
		return State.Setting("ReducedEffects") == true
	end, function(value)
		setSetting:FireServer("ReducedEffects", value)
	end)
	UIKit.Label({
		Text = "Reduced effects tones down particles, flashes and motion.",
		TextSize = 18,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = 3,
		Parent = list,
	})
	goldTeaser(modal)
	local saveNote = UIKit.Label({
		Text = "",
		TextSize = 18,
		TextColor3 = Theme.Colors.TextDim,
		LayoutOrder = 5,
		Parent = list,
	})
	State.ProfileChanged:Connect(function(profile)
		saveNote.Text = if profile.CanSave
			then "Your progress saves automatically."
			else "⚠️ Progress isn't saving this session."
	end)
	return modal
end

function HudController.Start(context)
	local topBar: ScreenGui
	if isTouch() then
		buildTouchProfile(context.Hud)
		topBar = buildTopBarBanner(context.Hud)
		buildTouchStatus(context.Hud)
	else
		buildProfileChip(context.Hud)
		buildPhaseBanner(context.Hud)
		topBar = buildTopBarSwitch(context.Hud)
	end
	followMenu(context.Hud, buildMenu(context.Hud), topBar)
	local settings = buildSettings(context.Overlay)

	State.OpenScreen:Connect(function(name)
		if name == "Settings" then
			settings:Toggle()
		end
	end)

	-- Lobby prompts that open screens (shop counter, quest board).
	ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
		if triggeringPlayer ~= player then
			return
		end
		local action = prompt:GetAttribute("Action")
		if action == "OpenShop" then
			State.OpenScreen:Fire("Shop")
		elseif action == "OpenQuests" then
			State.OpenScreen:Fire("Quests")
		end
	end)

	-- Keyboard shortcuts for desktop players.
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.G then
			State.OpenScreen:Fire("Emotes")
		elseif input.KeyCode == Enum.KeyCode.M then
			State.OpenScreen:Fire("Shop")
		elseif input.KeyCode == Enum.KeyCode.J then
			State.OpenScreen:Fire("Quests")
		end
	end)
end

return HudController
