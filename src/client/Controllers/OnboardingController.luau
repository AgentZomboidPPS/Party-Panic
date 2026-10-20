-- First-join guidance (design doc §12 "Onboarding"): vote → play → collect a reward, with icons and
-- one short line per step. Optional and skippable; it never shows again once finished.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local OnboardingController = {}

local STEPS = {
	{ Icon = "🗳️", Text = "When voting opens, step on a glowing portal pad or tap a card to pick the next game." },
	{ Icon = "🎮", Text = "Read the rules card, then go for it! Everyone earns coins just for playing." },
	{ Icon = "🎁", Text = "Nice! Spend coins in the 🛍️ Shop and check 📜 Quests for bonus rewards." },
}

local panel: Frame
local label: TextLabel
local stepLabel: TextLabel
local step = 0
local finished = false

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
	panel.Visible = true
	UIKit.PopIn(panel, 0.35)
	if step == #STEPS then
		task.delay(8, finish)
	end
end

function OnboardingController.Start(context)
	panel = UIKit.Panel({
		Name = "Onboarding",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -150),
		Size = UDim2.fromOffset(380, 150),
		CornerRadius = 20,
		Visible = false,
		Parent = context.Hud,
	}, Color3.fromRGB(110, 210, 255), Color3.fromRGB(60, 110, 220))
	UIKit.AutoScale(panel, 0.9)
	stepLabel = UIKit.Label({
		Text = "",
		TextSize = 16,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -100, 0, 20),
		Parent = panel,
	})
	label = UIKit.Label({
		Text = "",
		TextSize = 21,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(16, 32),
		Size = UDim2.new(1, -32, 1, -40),
		Parent = panel,
		Children = { UIKit.TextStroke(0.5) },
	})
	UIKit.Button({
		Text = "Skip",
		TextSize = 16,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(70, 30),
		CornerRadius = 15,
		Parent = panel,
	}, finish, Theme.Colors.PanelLight, Theme.Colors.PanelDark)

	local function begin(profile)
		if profile.TutorialDone then
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
		end
	end)
	Remotes.Get("RoundResults").OnClientEvent:Connect(function()
		if not finished and step > 0 then
			task.delay(2, show, 3)
		end
	end)
end

return OnboardingController
