-- First-join guidance (design doc §12 "Onboarding"): vote → play → collect a reward, with icons and
-- one short line per step. Optional and skippable; it never shows again once finished.
-- The tip sits under the coins, inside the profile chip's scaled frame so it lines up on every
-- screen. It shows in the lobby and while the rules card is up, and steps aside during the round
-- and the results (the standings use that spot); the last tip waits until you're back in the lobby.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local OnboardingController = {}

local STEPS = {
	{ Icon = "🗳️", Text = "When voting opens, tap a card or step on a glowing portal pad to pick the next game." },
	{ Icon = "🎮", Text = "Read the rules card, then go for it! Everyone earns coins just for playing." },
	{ Icon = "🎁", Text = "Nice! Spend coins in the 🛍️ Shop and check 📜 Quests for bonus rewards." },
}
local HIDDEN_IN = { InRound = true, Results = true }
local LOBBY = { Waiting = true, Intermission = true, Voting = true, Cleanup = true }

local panel: Frame
local label: TextLabel
local stepLabel: TextLabel
local step = 0
local finished = false
local rewardTipDue = false -- the last tip, once the results are over

local function refreshVisible()
	local visible = not finished and step > 0 and not HIDDEN_IN[GameState.Get("Phase") or "Waiting"]
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
	label.Text = `{info.Icon}  {info.Text}`
	stepLabel.Text = `Tip {step}/{#STEPS}`
	panel.Visible = false -- pop the new tip in
	refreshVisible()
	if step == #STEPS then
		task.delay(8, finish)
	end
end

function OnboardingController.Start(context)
	local touch = UIKit.IsTouch()
	-- Under the coins pill (HudController's profile chip frame is 130 tall).
	local profile = context.Hud:FindFirstChild("ProfileChip")
	panel = UIKit.Panel({
		Name = "Onboarding",
		Position = if profile then UDim2.fromOffset(0, 138) else UDim2.fromOffset(16, 150),
		Size = UDim2.fromOffset(if touch then 240 else 300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
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
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -90, 0, if touch then 40 else 30),
		Parent = panel,
		Children = { UIKit.TextStroke(0.4) },
	})
	label = UIKit.Label({
		Text = "",
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(0, if touch then 44 else 36),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = panel,
		Children = { UIKit.TextStroke(0.5) },
	})
	-- Phones: a bigger Skip button for thumbs.
	UIKit.Button({
		Text = "Skip",
		TextSize = if touch then 19 else 17,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = if touch then UDim2.fromOffset(90, 40) else UDim2.fromOffset(80, 32),
		CornerRadius = 16,
		Parent = panel,
	}, finish, Theme.Colors.PanelLight, Theme.Colors.PanelDark)

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
		if phase == "Preparing" or phase == "InRound" then
			show(2)
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
