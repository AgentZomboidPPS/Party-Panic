-- First-join guidance (design doc §12 "Onboarding"): vote → play → collect a reward, with icons and
-- one short line per step. Optional and skippable; it never shows again once finished.
-- PC: the tip sits under the coins, inside the profile chip's scaled frame so it lines up on every
-- screen. Phones (owner: "Wtf is this mobile Ui lol"; the tip was cut off after "tap"): a slim
-- toast at the top middle, under the top bar, with a thumb-sized Skip. It steps aside while the
-- vote cards use that spot.
-- Either way it shows in the lobby and while the rules card is up, and steps aside during the
-- round and the results (the standings use that spot) and while a lobby game has the screen (the
-- HUD's PP_TipsAside attribute: Skee-Ball); the last tip waits until you're back in the lobby.
-- Its height comes from its text (not AutomaticSize, which left one line showing on phones while
-- the tip popped in).
-- On phones it also steps aside while a level-up or milestone celebration uses its spot
-- (CelebrationController sets PP_Celebrating; owner: "cool payoffs for players that keep playing").
-- The lobby's chips (UI/LobbyRibbon: events, the Party Cup, invites) use that spot too and give way
-- to the tip: it sets the HUD's PP_TipShowing while it's up on a phone.
-- The last tip's 5 seconds only count while it's on screen, so stepping aside never uses it up.
--
-- With the shorter lobby (owner: "Less time sitting in the lobby. total of 20 seconds instead of
-- 40.") the last tip has 5 seconds, not 8: on phones it gets the 6 seconds between the results and
-- the vote (the vote cards take its spot), and 8 only fitted over the next round's rules card. And
-- since players can close the rules card (owner: "Let players close the instructions if they
-- want."), the "Read the rules card" tip is only up while their card is (PP_RulesShowing,
-- RoundController): it goes when they close the card or the 3-2-1 starts.
--
-- Skip was a dark purple button on the bright blue tip (owner: "why are the close menu buttons and
-- the invite friend button so dark?"): it's Theme's neutral lavender button now, clearly tappable.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local OnboardingController = {}

local STEPS = {
	{ Icon = "🗳️", Text = "When voting opens, tap a card to pick the next game. Portals show a preview!" },
	{ Icon = "🎮", Text = "Read the rules card, then go for it! Everyone earns coins just for playing." },
	{ Icon = "🎁", Text = "Nice! Spend coins in the 🛍️ Shop and check 🎃 Season for quests and rewards." },
}
local HIDDEN_IN = { InRound = true, Results = true }
local HIDDEN_ON_PHONES = { Voting = true } -- the vote cards' spot
local LOBBY = { Waiting = true, Intermission = true, Voting = true, Cleanup = true }

-- PC panel and phone toast sizes (scaled units).
local PC_WIDTH, PC_HEADER, PC_TEXT = 300, 36, 20
local TOUCH_WIDTH, TOUCH_HEIGHT, TOUCH_TEXT = 620, 88, 19

local touch = false
local hud: Instance? = nil
local panel: Frame
local label: TextLabel
local stepLabel: TextLabel?
local step = 0
local finished = false
local rewardTipDue = false -- the last tip, once the results are over
local LAST_TIP_TIME = 5 -- seconds the last tip stays on screen before the tips are done
local lastTipTimer: { any }? = nil -- the running countdown (a new one replaces it)
local finish: () -> () -- ends the tips for good (below)

local function refreshVisible()
	local phase = GameState.Get("Phase") or "Waiting"
	local celebrating = touch and State.LocalPlayer:GetAttribute("PP_Celebrating") == true
	local aside = hud ~= nil and hud:GetAttribute("PP_TipsAside") == true
	-- Before a round you're in, only alongside your rules card (closed, or the 3-2-1: aside).
	local rulesDown = phase == "Preparing"
		and State.InRound()
		and State.LocalPlayer:GetAttribute("PP_RulesShowing") ~= true
	local visible = not finished
		and step > 0
		and not aside
		and not HIDDEN_IN[phase]
		and not (touch and HIDDEN_ON_PHONES[phase])
		and not celebrating
		and not rulesDown
	if visible and not panel.Visible then
		panel.Visible = true
		UIKit.PopIn(panel, 0.35)
	else
		panel.Visible = visible
	end
	if touch and hud then
		hud:SetAttribute("PP_TipShowing", visible) -- the lobby's chips (UI/LobbyRibbon) share the spot
	end
	-- The last tip finishes the tips after it has been on screen for LAST_TIP_TIME (the countdown
	-- starts over whenever it comes back after stepping aside).
	if visible and step == #STEPS and not lastTipTimer then
		local timer = {}
		lastTipTimer = timer
		task.delay(LAST_TIP_TIME, function()
			if lastTipTimer == timer and panel.Visible then
				finish()
			end
		end)
	elseif not visible then
		lastTipTimer = nil
	end
end

function finish()
	if finished then
		return
	end
	finished = true
	panel.Visible = false
	if hud then
		hud:SetAttribute("PP_TipShowing", nil)
	end
	Remotes.Get("TutorialDone"):FireServer()
end

-- PC: the panel grows with the tip's lines.
local function fitPanel()
	if touch then
		return
	end
	local width = PC_WIDTH - 28
	local lines = UIKit.TextLines(label.Text, PC_TEXT, label.Font, width)
	local height = lines * PC_TEXT + 6
	label.Size = UDim2.new(1, 0, 0, height)
	panel.Size = UDim2.fromOffset(PC_WIDTH, 10 + PC_HEADER + height + 10)
end

local function show(newStep: number)
	if finished or newStep <= step then
		return
	end
	step = newStep
	local info = STEPS[step]
	if not info then
		finish()
		return
	end
	if touch then
		local tag = Theme.Colors.Yellow:ToHex()
		label.Text = `<font color="#{tag}">TIP {step}/{#STEPS}</font>  {info.Icon} {info.Text}`
	else
		label.Text = `{info.Icon}  {info.Text}`
		if stepLabel then
			stepLabel.Text = `Tip {step}/{#STEPS}`
		end
		fitPanel()
	end
	panel.Visible = false -- pop the new tip in
	refreshVisible()
end

local function buildPc(context)
	-- Under the profile card (HudController.ProfileHeight: its frame is 104 tall).
	local profile = context.Hud:FindFirstChild("ProfileChip")
	panel = UIKit.Panel({
		Name = "Onboarding",
		Position = if profile then UDim2.fromOffset(0, 112) else UDim2.fromOffset(16, 124),
		Size = UDim2.fromOffset(PC_WIDTH, 120),
		CornerRadius = 20,
		Visible = false,
		Parent = profile or context.Hud,
		Children = { UIKit.Padding(10, 14) },
	}, Color3.fromRGB(110, 210, 255), Color3.fromRGB(60, 110, 220))
	if not profile then
		UIKit.AutoScale(panel)
	end
	stepLabel = UIKit.Label({
		Text = "",
		TextSize = 17,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -90, 0, 30),
		Parent = panel,
		Children = { UIKit.TextStroke(0.4) },
	})
	label = UIKit.Label({
		Text = "",
		TextSize = PC_TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(0, PC_HEADER),
		Size = UDim2.new(1, 0, 0, 66),
		Parent = panel,
		Children = { UIKit.TextStroke(0.5) },
	})
	UIKit.Button({
		Text = "Skip",
		TextSize = 17,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(80, 32),
		CornerRadius = 16,
		Parent = panel,
	}, finish, Theme.Colors.Lavender, Theme.Colors.Purple)
	task.delay(3, function() -- again once the font has surely loaded
		if step > 0 and not finished then
			fitPanel()
		end
	end)
end

local function buildTouch(context)
	local holder = UIKit.new("Frame", {
		Name = "Onboarding",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.fromOffset(TOUCH_WIDTH, TOUCH_HEIGHT + 10),
		BackgroundTransparency = 1,
		Parent = context.Hud,
	})
	UIKit.AutoScale(holder)
	panel = UIKit.Panel({
		Name = "Tip",
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.fromOffset(TOUCH_WIDTH, TOUCH_HEIGHT),
		CornerRadius = 22,
		Visible = false,
		Parent = holder,
	}, Color3.fromRGB(110, 210, 255), Color3.fromRGB(60, 110, 220))
	label = UIKit.Label({
		Text = "",
		RichText = true,
		TextSize = TOUCH_TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(18, 6),
		Size = UDim2.new(1, -150, 1, -12),
		Parent = panel,
		Children = { UIKit.TextStroke(0.5) },
	})
	UIKit.Button({
		Text = "Skip",
		TextSize = 22,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(112, Theme.Touch.Target),
		CornerRadius = 18,
		Parent = panel,
	}, finish, Theme.Colors.Lavender, Theme.Colors.Purple)
end

function OnboardingController.Start(context)
	touch = UIKit.IsTouch()
	hud = context.Hud
	if touch then
		buildTouch(context)
	else
		buildPc(context)
	end
	context.Hud:GetAttributeChangedSignal("PP_TipsAside"):Connect(refreshVisible)

	local function begin(snapshot)
		if snapshot.TutorialDone then
			finished = true
			panel.Visible = false
			if hud then
				hud:SetAttribute("PP_TipShowing", nil) -- (finished elsewhere while a tip was up here)
			end
			return
		end
		if step == 0 then
			show(1)
		end
	end
	State.ProfileChanged:Connect(begin)

	GameState.Changed("Phase", function(phase)
		if finished or step == 0 then
			return
		end
		if (phase == "Preparing" or phase == "InRound") and State.InRound() then
			show(2) -- "Read the rules card": only the round's players get one
		elseif rewardTipDue and LOBBY[phase] then
			rewardTipDue = false
			show(3)
		end
		refreshVisible()
	end)
	Remotes.Get("RoundResults").OnClientEvent:Connect(function()
		if not finished and step > 0 then
			rewardTipDue = true
		end
	end)
	State.LocalPlayer:GetAttributeChangedSignal("PP_Celebrating"):Connect(function()
		if not finished and step > 0 then
			refreshVisible()
		end
	end)
	State.LocalPlayer:GetAttributeChangedSignal("PP_RulesShowing"):Connect(function()
		if not finished and step > 0 then
			refreshVisible()
		end
	end)
end

return OnboardingController
