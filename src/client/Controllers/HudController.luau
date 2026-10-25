-- Lobby / in-round HUD (design doc §12 "Primary UI surfaces"):
-- profile chip (level, XP, coins), phase banner with timer, side menu, settings window.
-- Kept to the screen edges so chat and the middle of the screen stay clear.
-- Phones (owner: "Wtf is this mobile Ui lol"; then layout A, owner: "I like a but damn have we got
-- to clean up the mobile UI", "move the ones we keep over more. we have more usable space"): the
-- phase banner is one short line with the timer ("VOTE! 0:08") up in Roblox's top bar row, in the
-- middle; the profile card at the top left under Roblox's buttons and the menu as a 2 x 2 grid in
-- the top right corner, both in part of the safe area's side insets (the edge ScreenGui, clear of
-- the notch or Dynamic Island further down the sides); the round's standings strip and status line
-- under the banner; everything at the bottom in the middle. Little goes in the thumbstick's zone,
-- nothing near the jump button.
-- The sit-out switch (owner: "we do need to add somewhere super apparent a toggle where you skip
-- next round", UI/SitOutSwitch) sits right by the banner where everyone looks for the timer: under
-- it in the lobby on phones, above it in the top bar row on PC; it's in Settings too.
-- Tapping the profile card opens the Rewards screen (owner: "Also we need cool payoffs for players
-- that keep playing the game."); RewardsController puts the next reward beside the XP bar and colors
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
-- now (Theme's neutral button), apart from Shop's pink, the Season hub's orange and Emotes' cyan.
--
-- More of the game on screen in a round (owner: "During the mini games, any way we can save UI space
-- so they can see more of the game at one time?"):
--   * While the player is playing a round (State.PlayingRound: its rules card to its end, still in)
--     the menu column slides off the right edge and a small ☰ button waits in the top right corner,
--     in Roblox's top bar row, with the column's "!" on it. A tap brings the column back until a menu
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
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local GameDefinitions = require(Shared.GameDefinitions)
local GameState = require(Shared.GameState)
local GoldPass = require(Shared.GoldPass)
local Remotes = require(Shared.Remotes)
local RoundHud = require(Shared.Logic.RoundHud)
local Teams = require(Shared.Teams)

local GoldPassController = require(script.Parent.GoldPassController)
local CrateNudge = require(script.Parent.Parent.Crates.CrateNudge)
local LootFly = require(script.Parent.Parent.Crates.LootFly)
local State = require(script.Parent.Parent.State)
local HubTabs = require(script.Parent.Parent.UI.HubTabs)
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

-- The profile card (layout A; owner, picking it: "I like a but damn have we got to clean up the
-- mobile UI"): the level badge, the name, the XP bar with the next reward beside it (the NextSlot:
-- RewardsController), then the coins, keys and crates in a row (owner: "show keys as a currency,
-- show crates as a currency. both under the coins."). A tap on the card opens the Rewards screen;
-- the keys and crates open the crate window (the keys its key shop), and the crates ask to be opened
-- (Crates/CrateNudge). A round's keys and crate fly into them (Crates/LootFly).
-- PC: the top left corner, always (the standings and the first-join tip go under it). Phones: in the
-- top left corner under Roblox's buttons, Theme.Touch.Edge points from the screen's side (the edge
-- ScreenGui), outside rounds: from the rules card on for the round's players, and while the round is
-- on for everyone (the round's standings strip under the banner, RoundController, reaches its corner
-- on the smallest phones). It steps aside for the first-join tip too (OnboardingController's
-- PP_TipShowing), for the same reason.
-- Phones: it ends where the MOVE stick's zone starts on the smallest phones (a third of the way down).
local CARD = Vector2.new(336, 104) -- scaled units (phones: 208 x 64 points)
local TOUCH_CARD_TOP = 58 -- points: under Roblox's buttons (12 to 55)
local PILL_Y, PILL_H = 56, 42
local TAP_H = 65 -- the keys' and crates' tap areas (40 points on phones)
-- What sits under the card on PC (OnboardingController's tip, RoundController's standings) starts
-- this far down its frame.
HudController.ProfileHeight = CARD.Y
local function buildProfileCard(parent: Instance, hud: Instance, touch: boolean)
	local holder = profileHolder({
		Position = if touch then UDim2.fromOffset(Theme.Touch.Edge, TOUCH_CARD_TOP) else UDim2.fromOffset(16, 12),
		Size = UDim2.fromOffset(CARD.X, CARD.Y),
		Parent = parent,
	})
	UIKit.AutoScale(holder)

	local card = UIKit.Panel({
		Name = "Card",
		Size = UDim2.fromOffset(CARD.X, CARD.Y),
		CornerRadius = 24,
		Parent = holder,
	})
	local badge = UIKit.new("Frame", {
		Name = "LevelBadge",
		Size = UDim2.fromOffset(44, 44),
		Position = UDim2.fromOffset(8, 6),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = card,
		Children = {
			UIKit.Round(),
			UIKit.Gradient(Theme.Colors.Yellow, Theme.Colors.Orange),
			UIKit.Stroke(nil, 2, 0.3),
		},
	})
	local levelLabel = UIKit.Label({
		Text = "1",
		Font = Theme.Fonts.Display,
		TextSize = 24,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = badge,
		Children = { UIKit.TextStroke(0.2) },
	})
	local name = UIKit.Label({
		Text = player.DisplayName,
		Font = Theme.Fonts.Display,
		TextSize = 20,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(60, 2),
		Size = UDim2.fromOffset(CARD.X - 60 - 10, 22),
		Parent = card,
		Children = { UIKit.TextStroke(0.2) },
	})
	name:SetAttribute("PP_TruncateOk", true) -- a long name ends in "..."
	local barBack = UIKit.new("Frame", {
		Position = UDim2.fromOffset(60, 25),
		Size = UDim2.fromOffset(150, 22),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = card,
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
	-- The next reward's pill goes here (RewardsController).
	UIKit.new("Frame", {
		Name = "NextSlot",
		Position = UDim2.fromOffset(216, 25),
		Size = UDim2.fromOffset(CARD.X - 216 - 8, 22),
		BackgroundTransparency = 1,
		Parent = card,
	})

	-- The coins, keys and crates in a row along the bottom.
	local function pill(pillName: string, x: number, width: number, top: Color3, bottom: Color3): Frame
		return UIKit.Panel({
			Name = pillName,
			Position = UDim2.fromOffset(x, PILL_Y),
			Size = UDim2.fromOffset(width, PILL_H),
			CornerRadius = PILL_H / 2,
			Parent = card,
		}, top, bottom)
	end
	local function number(parent: Instance, x: number): TextLabel
		return UIKit.Label({
			Text = "0",
			Font = Theme.Fonts.Display,
			TextSize = 24,
			TextWrapped = false,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(x, 5),
			Size = UDim2.new(1, -(x + 8), 1, -10),
			Parent = parent,
			Children = { UIKit.TextStroke(0.15), UIKit.new("UITextSizeConstraint", { MaxTextSize = 24 }) },
		})
	end
	local coins = pill("Coins", 8, 120, Color3.fromRGB(255, 196, 60), Color3.fromRGB(230, 130, 30))
	UIKit.Coin({ Position = UDim2.fromOffset(8, 9), Size = UDim2.fromOffset(24, 24), Parent = coins })
	local coinLabel = number(coins, 38)
	followProfile(levelLabel, barFill, xpText, badge, coins, function(value)
		coinLabel.Text = UIKit.FormatNumber(value)
	end)
	-- Keys and crates: a tap opens the crate window. The tap area is a 40 pt touch target round the
	-- pill (its words are on it; it reaches a little past the card's bottom edge).
	local function currency(pillName: string, icon: string, x: number, top: Color3, bottom: Color3, tab: string)
		local face = pill(pillName, x, 94, top, bottom)
		local tap = UIKit.new("TextButton", {
			Name = "Tap",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(1, 0, 0, TAP_H),
			ZIndex = 3,
			Parent = face,
		})
		tap.Activated:Connect(function()
			State.OpenScreen:Fire("Crates", tab)
		end)
		local words = UIKit.new("Frame", {
			Name = "Words",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(1, 0, 0, PILL_H),
			BackgroundTransparency = 1,
			Parent = tap,
		})
		local iconLabel = UIKit.Label({
			Text = icon,
			TextScaled = true,
			Position = UDim2.fromOffset(8, 9),
			Size = UDim2.fromOffset(24, 24),
			Parent = words,
		})
		return face, number(words, 36), iconLabel
	end
	local keysPill, keysLabel =
		currency("Keys", "🔑", 134, Color3.fromRGB(120, 210, 255), Color3.fromRGB(60, 120, 230), "Keys")
	local cratesPill, cratesLabel, cratesIcon =
		currency("Crates", "📦", 234, Color3.fromRGB(255, 170, 80), Color3.fromRGB(225, 95, 40), "Crates")
	CrateNudge.Attach(cratesPill, cratesIcon, cratesLabel) -- a crate to open: the pill asks
	LootFly.Target("Keys", keysPill, 1)
	LootFly.Target("Crates", cratesPill, 1)
	local shownKeys, shownCrates = nil :: number?, nil :: number?
	local function redraw()
		local profile = State.Profile
		if not profile then
			return
		end
		local keys = LootFly.Shown("Keys", profile.Keys or 0)
		local crates = LootFly.Shown("Crates", if profile.Crates then profile.Crates.Count or 0 else 0)
		keysLabel.Text = UIKit.FormatNumber(keys)
		cratesLabel.Text = UIKit.FormatNumber(crates)
		if shownKeys and keys > shownKeys then
			UIKit.PopIn(keysPill, 0.3)
		end
		if shownCrates and crates > shownCrates then
			UIKit.PopIn(cratesPill, 0.3)
		end
		shownKeys, shownCrates = keys, crates
	end
	State.ProfileChanged:Connect(redraw)
	LootFly.Changed:Connect(redraw)

	if not touch then
		return
	end
	-- (A level-up or medal card at the top middle reached over it on the smaller phones: it steps
	-- aside for that too, PP_Celebrating, and is back with the new totals when the card goes.)
	local function refresh()
		holder.Visible = not State.PlayingRound()
			and GameState.Get("Phase") ~= "InRound"
			and hud:GetAttribute("PP_TipShowing") ~= true
			and player:GetAttribute("PP_Celebrating") ~= true
	end
	State.OnPlayingChanged(refresh)
	GameState.Changed("Phase", refresh)
	hud:GetAttributeChangedSignal("PP_TipShowing"):Connect(refresh)
	player:GetAttributeChangedSignal("PP_Celebrating"):Connect(refresh)
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
	Holder: Instance?, -- phones: the row's frame, where RoundController's standings strip goes on top
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
	local lineY = -1
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

		-- Phones: the standings strip (RoundController) while the round is on. For its players it takes
		-- the line's room once the line has faded, so the mode HUDs keep their spot: not when the line
		-- has no room (a mode with nothing to say there has its own HUD up top), nor in a team round
		-- (the team pill is the race there). For anyone watching it sits above their line.
		local board = row.Holder and row.Holder:FindFirstChild("Leaderboard")
		local boardOn = false
		if board and board:IsA("GuiObject") then
			local lineBusy = label.Visible or calloutUp or row.Teams.Visible
			boardOn = phase == "InRound" and (not participant or (reserved and not lineBusy))
			board.Visible = boardOn
		end
		local boardHeight = if board and board:IsA("GuiObject") then board.Size.Y.Offset else 0
		-- (Watchers: the line under the strip.)
		local below = if boardOn and not participant then boardHeight + 4 else 0
		if row.LineTop + below ~= lineY then
			lineY = row.LineTop + below
			label.Position = UDim2.new(0.5, 0, 0, lineY)
			if strip then
				strip.Position = UDim2.new(0.5, 0, 0, lineY)
			end
		end

		-- The team pill under the line, and the mode HUDs under both.
		local height = if calloutUp and strip then math.max(row.LineHeight, strip.Size.Y.Offset) else row.LineHeight
		if boardOn and participant then
			height = math.max(height, boardHeight - 2) -- (the strip in the line's place, from 4 down)
		end
		local top = if reserved then lineY + height + 4 else row.CollapsedTop + below
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
-- switch is under it (buildTouchSwitch): the menu has that row's right end.
local TOUCH_BANNER_HEIGHT = 66
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
	end)
	return gui
end

-- Phones: the sit-out switch sits under the banner in the middle, in the lobby (the top bar row has
-- the menu at its right end now: beside the banner the switch ran into it on the smallest phones).
-- During a round, someone sitting it out has PLAY NEXT ROUND at the bottom instead
-- (SpectateController). It gives way to whatever else uses the spot: the first-join tip, a level-up
-- card. The lobby's chips line up under it (UI/LobbyRibbon).
local SWITCH_PHASES = { Waiting = true, Intermission = true, Voting = true, Cleanup = true }
local function buildTouchSwitch(hud: Instance)
	local holder = UIKit.new("Frame", {
		Name = "SitOutRow",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.fromOffset(400, 72),
		BackgroundTransparency = 1,
		Parent = hud,
	})
	UIKit.AutoScale(holder)
	SitOutSwitch.new(holder, {
		Name = "SitOut",
		Hud = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
	})
	local function refresh()
		local phase = GameState.Get("Phase") or "Waiting"
		local replaying = phase == "Cleanup" and (GameState.Get("Replay") or "") ~= "" -- (straight into its rules)
		SitOutSwitch.SetAside("Round", not SWITCH_PHASES[phase] or replaying)
		SitOutSwitch.SetAside(
			"Spot",
			hud:GetAttribute("PP_TipShowing") == true or player:GetAttribute("PP_Celebrating") == true
		)
	end
	GameState.Changed("Phase", refresh)
	GameState.Changed("Replay", refresh)
	hud:GetAttributeChangedSignal("PP_TipShowing"):Connect(refresh)
	player:GetAttributeChangedSignal("PP_Celebrating"):Connect(refresh)
	refresh()
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
		Holder = holder,
	})
	followTeamScores(teams)
end

-- Phones: the menu's tiles (scaled units: 52 points) and the grid's place (points from the top).
local TOUCH_TILE, TOUCH_TILE_GAP = Theme.Touch.Menu.Tile, Theme.Touch.Menu.Gap
local TOUCH_MENU_TOP = Theme.Touch.Menu.Top

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
	local size = if touch then TOUCH_TILE else 74
	local button = UIKit.Button({
		Name = name,
		Text = if touch then "" else icon,
		TextSize = if touch then 34 else 36,
		Size = UDim2.fromOffset(size, size),
		CornerRadius = if touch then 22 else 24,
		LayoutOrder = order,
		Parent = parent,
	}, function()
		State.OpenScreen:Fire(name)
	end, top, bottom)
	if touch then
		-- (The icon over the caption, both inside the tile.)
		UIKit.Label({
			Name = "Icon",
			Text = icon,
			TextSize = 36,
			TextWrapped = false,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.fromOffset(44, 44), -- (clear of the "!" on the corner)
			Parent = button,
		})
	end
	UIKit.Label({
		Text = caption,
		TextSize = if touch then Theme.Touch.MinText else 15,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, if touch then -5 else 2),
		Size = UDim2.new(1, if touch then -4 else 10, 0, if touch then 22 else 18),
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
	-- PC: the middle of the right edge. Phones (layout A): a 2 x 2 grid in the top right corner, in
	-- Roblox's top bar row and under it, Theme.Touch.Edge points from the screen's side (the edge
	-- ScreenGui), where it can't be hit by mistake when reaching for the jump button. It ends above
	-- where a notch or the Dynamic Island starts on that side.
	local touch = isTouch()
	local menu
	if touch then
		local side = 2 * TOUCH_TILE + TOUCH_TILE_GAP
		menu = UIKit.new("Frame", {
			Name = "Menu",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -Theme.Touch.Edge, 0, TOUCH_MENU_TOP),
			Size = UDim2.fromOffset(side, side),
			BackgroundTransparency = 1,
			Parent = parent,
			Children = {
				UIKit.new("UIGridLayout", {
					CellSize = UDim2.fromOffset(TOUCH_TILE, TOUCH_TILE),
					CellPadding = UDim2.fromOffset(TOUCH_TILE_GAP, TOUCH_TILE_GAP),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
		})
	else
		menu = UIKit.new("Frame", {
			Name = "Menu",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(80, 360),
			BackgroundTransparency = 1,
			Parent = parent,
			Children = {
				UIKit.List(
					Enum.FillDirection.Vertical,
					14,
					Enum.HorizontalAlignment.Center,
					Enum.VerticalAlignment.Center
				),
			},
		})
	end
	UIKit.AutoScale(menu)
	-- (Phones: Season and Shop on top, Emotes and Settings under them.)
	menuButton(menu, "Shop", "🛍️", "Shop", if touch then 2 else 1, Theme.Colors.Pink, Color3.fromRGB(200, 50, 140))
	-- The GOALS hub (owner: "Do we not have a button to open the season rewards?", then "What if we
	-- rolled season/event/quests into one button?", then with Game Mastery in it: "I want to rename
	-- that button to better reflect everything in it"): the season's crates, the event, the quests and
	-- every game's mastery, one window with their tabs (UI/HubTabs), with a "!" when a quest or event
	-- reward is ready.
	menuButton(menu, "Hub", "🎯", "Goals", if touch then 1 else 2, Theme.Colors.Orange, Color3.fromRGB(205, 92, 24))
	menuButton(menu, "Emotes", "🕺", "Emotes", 3, Theme.Colors.Cyan, Color3.fromRGB(50, 120, 230))
	menuButton(menu, "Settings", "⚙️", "Settings", 4, Theme.Colors.Lavender, Theme.Colors.Purple)

	State.ProfileChanged:Connect(function(profile)
		HubTabs.SetBadge("Quests", profile.Daily.CanClaim == true)
	end)
	local function hubBadge()
		badges.Hub.Visible = HubTabs.AnyBadge()
	end
	HubTabs.Changed:Connect(hubBadge)
	hubBadge()
	return menu
end

-- The ☰ that stands in for the menu column while the player is playing a round: in Roblox's top
-- bar row, in the top right corner (phones: a 44 pt button level with Roblox's own; PC: their size,
-- like the sit-out switch in that row), with the column's "!" on it when a tile has one. Three
-- drawn bars, since the ☰ character draws as a missing-glyph box in the game's fonts.
local TOGGLE_SIZE, TOGGLE_BAR_W, TOGGLE_BAR_H, TOGGLE_BAR_GAP = 72, 34, 6, 12
local function buildMenuToggle(parent: Instance, onClick: () -> ()): Frame
	local touch = isTouch()
	local holder = UIKit.new("Frame", {
		Name = "MenuToggle",
		AnchorPoint = Vector2.new(1, 0.5),
		-- Level with Roblox's buttons (12 to 55); phones: in the menu's corner (the edge ScreenGui).
		Position = UDim2.new(1, if touch then -Theme.Touch.Edge else -8, 0, 34),
		Size = UDim2.fromOffset(TOGGLE_SIZE, TOGGLE_SIZE),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
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
local function followMenu(hud: Instance, menu: Frame, toggleParent: Instance)
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
		-- (Phones: the menu's grid comes back over the ☰'s corner; it goes again by itself.)
		local wantToggle = playing and not (peeking and isTouch())
		if toggle.Visible ~= wantToggle then
			toggle.Visible = wantToggle
			if wantToggle and not State.ReducedEffects() then
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
	toggle = buildMenuToggle(toggleParent, HudController.ToggleMenu)

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

-- Phones: the Settings window's rows (scaled units), five of them on the shortest phone with their 44 pt
-- buttons (the suggestion box's is the fifth).
local SETTINGS_ROW = 70

local function toggleRow(
	parent: Instance,
	order: number,
	label: string,
	getter: () -> boolean,
	onToggle: (boolean) -> ()
)
	local touch = isTouch()
	local row = UIKit.new("Frame", {
		Size = UDim2.new(1, 0, 0, if touch then SETTINGS_ROW else 64),
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
		Size = UDim2.new(1, 0, 0, if touch then SETTINGS_ROW else 64),
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
		Size = UDim2.new(1, 0, 0, if isTouch() then SETTINGS_ROW else 76),
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
	local modal = Modal.new(overlay, "Settings", "⚙️", Vector2.new(560, if touch then 480 else 420))
	local list = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = modal.Content,
		Children = { UIKit.List(Enum.FillDirection.Vertical, if touch then 6 else 10) },
	})
	local setSetting = Remotes.Get("SetSetting")
	sitOutRow(list, 0)
	musicRow(list, 1, setSetting)
	toggleRow(list, 2, "✨ Reduced effects", function()
		return State.Setting("ReducedEffects") == true
	end, function(value)
		setSetting:FireServer("ReducedEffects", value)
	end)
	if not touch then
		UIKit.Label({
			Text = "Reduced effects tones down particles, flashes and motion.",
			TextSize = 18,
			TextColor3 = Theme.Colors.TextDim,
			Size = UDim2.new(1, 0, 0, 44),
			LayoutOrder = 3,
			Parent = list,
		})
	else
		-- (Phones: the Vibration switch in the explanation's place, so the window still fits a small phone.)
		-- (Haptics: a tap for a mode's button, a pulse at GO and for a win, a thud when you're out.)
		toggleRow(list, 4, "📳 Vibration", function()
			return State.Setting("Vibration") ~= false
		end, function(value)
			setSetting:FireServer("Vibration", value)
		end)
	end
	goldTeaser(modal)
	-- The suggestion box (owner: "Can we add a suggestion box?"; SuggestionController), where the
	-- "Your progress saves automatically." line was: that line now only shows when it isn't saving.
	local bottom = UIKit.new("Frame", {
		Size = UDim2.new(1, 0, 0, if touch then Theme.Touch.Target else 54),
		BackgroundTransparency = 1,
		LayoutOrder = 6,
		Parent = list,
	})
	UIKit.Button({
		Name = "Suggest",
		Text = "💡 SUGGESTION BOX",
		TextSize = 22,
		TextWrapped = false,
		Size = UDim2.fromOffset(250, if touch then Theme.Touch.Target else 54),
		CornerRadius = "round",
		Parent = bottom,
	}, function()
		modal:Close()
		State.OpenScreen:Fire("Suggestions")
	end, Theme.Colors.Yellow, Theme.Colors.Orange)
	local saveNote = UIKit.Label({
		Text = "",
		TextSize = 18,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(262, 0),
		Size = UDim2.new(1, -262, 1, 0),
		Parent = bottom,
	})
	State.ProfileChanged:Connect(function(profile)
		saveNote.Text = if profile.CanSave then "" else "⚠️ Progress isn't saving this session."
	end)
	return modal
end

-- PC: Roblox's chat window opens in the top left corner, over the profile card and the round's
-- standings (owner, with a screenshot of it: "is there anything we can do about the chatbox?"). It
-- goes to the bottom left instead, shorter, where the HUD has nothing (it stays under the squad bar,
-- which is on the left halfway down). Phones keep Roblox's own place: there the chat starts closed
-- and a player opens it on purpose.
local function placeChat()
	if isTouch() or TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		return
	end
	local window = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
	if window then
		window.HorizontalAlignment = Enum.HorizontalAlignment.Left
		window.VerticalAlignment = Enum.VerticalAlignment.Bottom
		window.HeightScale = 0.6
	end
end

function HudController.Start(context)
	pcall(placeChat) -- (a chat setting Roblox renames must never stop the HUD)
	if isTouch() then
		-- (The edge ScreenGui: the whole screen, init.client.luau; a harness may not make one.)
		local edge = context.Edge or context.Hud
		buildProfileCard(edge, context.Hud, true)
		buildTopBarBanner(context.Hud)
		buildTouchSwitch(context.Hud)
		buildTouchStatus(context.Hud)
		followMenu(context.Hud, buildMenu(edge), edge)
	else
		buildProfileCard(context.Hud, context.Hud, false)
		buildPhaseBanner(context.Hud)
		followMenu(context.Hud, buildMenu(context.Hud), buildTopBarSwitch(context.Hud))
	end
	local settings = buildSettings(context.Overlay)

	State.OpenScreen:Connect(function(name)
		if name == "Settings" then
			settings:Toggle()
		elseif name == "Hub" then
			State.OpenScreen:Fire(HubTabs.Last())
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
		elseif action == "OpenSuggestions" then
			State.OpenScreen:Fire("Suggestions") -- (the mailbox by the quest board)
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
