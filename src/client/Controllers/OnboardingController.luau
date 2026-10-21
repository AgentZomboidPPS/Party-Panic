-- First-join guidance (design doc §12 "Onboarding"): vote → play → collect a reward, with icons and
-- one short line per step. Optional and skippable; it never shows again once finished.
-- PC: the tip sits under the coins, inside the profile chip's scaled frame so it lines up on every
-- screen. Phones (owner: "Wtf is this mobile Ui lol"; the tip was cut off after "tap"): a slim
-- toast at the top middle, under the top bar, with a thumb-sized Skip. It steps aside while the
-- vote cards use that spot.
-- Either way it shows in the lobby and while the rules card is up, and steps aside during the
-- round and the results (the standings use that spot); the last tip waits until you're back in
-- the lobby. Its height comes from its text (not AutomaticSize, which left one line showing on
-- phones while the tip popped in).

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
	{ Icon = "🎁", Text = "Nice! Spend coins in the 🛍️ Shop and check 📜 Quests for bonus rewards." },
}
local HIDDEN_IN = { InRound = true, Results = true }
local HIDDEN_ON_PHONES = { Voting = true } -- the vote cards' spot
local LOBBY = { Waiting = true, Intermission = true, Voting = true, Cleanup = true }

-- PC panel and phone toast sizes (scaled units).
local PC_WIDTH, PC_HEADER, PC_TEXT = 300, 36, 20
local TOUCH_WIDTH, TOUCH_HEIGHT, TOUCH_TEXT = 620, 88, 19

local touch = false
local panel: Frame
local label: TextLabel
local stepLabel: TextLabel?
local step = 0
local finished = false
local rewardTipDue = false -- the last tip, once the results are over

local function refreshVisible()
	local phase = GameState.Get("Phase") or "Waiting"
	local visible = not finished and step > 0 and not HIDDEN_IN[phase] and not (touch and HIDDEN_ON_PHONES[phase])
	if visible and not panel.Visible then
		panel.Visible = true
		UIKit.PopIn(panel, 0.35)
	else
		panel.Visible = visible
	end
end

local function finish()
	if finished then
		return
	end
	finished = true
	panel.Visible = false
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
	if step == #STEPS then
		task.delay(8, finish)
	end
end

local function buildPc(context)
	-- Under the coins pill (HudController's profile chip frame is 130 tall).
	local profile = context.Hud:FindFirstChild("ProfileChip")
	panel = UIKit.Panel({
		Name = "Onboarding",
		Position = if profile then UDim2.fromOffset(0, 138) else UDim2.fromOffset(16, 150),
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
	}, finish, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
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
	}, finish, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
end

function OnboardingController.Start(context)
	touch = UIKit.IsTouch()
	if touch then
		buildTouch(context)
	else
		buildPc(context)
	end

	local function begin(snapshot)
		if snapshot.TutorialDone then
			finished = true
			panel.Visible = false
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
end

return OnboardingController
