-- Spectating (design doc §11 "Spectator options"): watch remaining players during a round,
-- cycle between them, and return to your own camera automatically at results. Bots in the round
-- can be watched too (Participants).
-- Phones: the bar sits low in the middle, with 44 pt buttons.
--
-- Someone not playing the round (sitting it out, or arrived while it was on) gets two big buttons at
-- the bottom in the middle (owner, on layout A: "the bottom not being centrally located is ass",
-- then "certain buttons aren't centered?"), the same width side by side: 👀 WATCH (the bar above)
-- and, for anyone sitting out, 🎮 PLAY NEXT ROUND, which turns sitting out off (UI/SitOutSwitch: the
-- banner's switch steps aside while it shows, so there's one way to do it at a time). With only one
-- of them up, it sits in the middle by itself.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameState = require(ReplicatedStorage.Shared.GameState)

local Participants = require(script.Parent.Parent.Participants)
local State = require(script.Parent.Parent.State)
local SitOutSwitch = require(script.Parent.Parent.UI.SitOutSwitch)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local SpectateController = {}

local player = Players.LocalPlayer
local bar: Frame
local nameLabel: TextLabel
local openButton: TextButton
local index = 1
local spectating = false
local PAIR_PHASES = { Preparing = true, InRound = true }

local function targets(): { Participants.Participant }
	local list = {}
	for _, other in Participants.InRound() do
		if not other.IsLocal and other:GetAttribute("PP_Alive") then
			table.insert(list, other)
		end
	end
	table.sort(list, function(a, b)
		return a.UserId > b.UserId -- players first, then bots in the order they arrived
	end)
	return list
end

local function humanoidOf(target: Participants.Participant): Humanoid?
	local character = target:Character()
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function resetCamera()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		workspace.CurrentCamera.CameraSubject = humanoid
	end
end

local function stop()
	spectating = false
	bar.Visible = false
	resetCamera()
end

local function focus()
	local list = targets()
	if #list == 0 then
		stop()
		return
	end
	index = ((index - 1) % #list) + 1
	local target = list[index]
	local humanoid = humanoidOf(target)
	if humanoid then
		workspace.CurrentCamera.CameraSubject = humanoid
	end
	nameLabel.Text = `👀 {target.DisplayName}  ({index}/{#list})`
end

local function start()
	if #targets() == 0 then
		return
	end
	spectating = true
	bar.Visible = true
	UIKit.PopIn(bar, 0.3)
	focus()
end

function SpectateController.Start(context)
	local touch = UIKit.IsTouch()
	local button = if touch then Theme.Touch.Target else 60
	local inset = if touch then 7 else 8
	bar = UIKit.Panel({
		Name = "Spectate",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = if touch then UDim2.new(0.5, 0, 1, -8) else UDim2.new(0.5, 0, 1, -24),
		Size = if touch then UDim2.fromOffset(460, button + 2 * inset) else UDim2.fromOffset(560, 76),
		CornerRadius = if touch then 30 else 38,
		Visible = false,
		Parent = context.Hud,
	})
	UIKit.AutoScale(bar)
	-- (In the middle its ◀ reaches the MOVE stick's zone on smaller phones: someone spectating isn't
	-- walking. tools/checks: allowed there.)
	bar:SetAttribute("PP_Popup", true)
	UIKit.Button({
		Text = "◀",
		Size = UDim2.fromOffset(button, button),
		Position = UDim2.fromOffset(inset, inset),
		CornerRadius = "round",
		Parent = bar,
	}, function()
		index -= 1
		focus()
	end, Theme.Colors.Cyan, Color3.fromRGB(50, 120, 230))
	nameLabel = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 22 else 24,
		TextWrapped = false,
		Position = UDim2.fromOffset(inset + button + 8, 0),
		Size = if touch then UDim2.new(1, -(inset + button + 8) - 167, 1, 0) else UDim2.new(1, -250, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = bar,
	})
	nameLabel:SetAttribute("PP_TruncateOk", true) -- a long name ends in "..."
	UIKit.Button({
		Text = "▶",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(button, button),
		Position = if touch then UDim2.new(1, -(inset + button + 8), 0, inset) else UDim2.new(1, -110, 0, 8),
		CornerRadius = "round",
		Parent = bar,
	}, function()
		index += 1
		focus()
	end, Theme.Colors.Cyan, Color3.fromRGB(50, 120, 230))
	UIKit.Button({
		Text = "X",
		AnchorPoint = Vector2.new(1, 0),
		Size = if touch then UDim2.fromOffset(button, button) else UDim2.fromOffset(90, 60),
		Position = UDim2.new(1, -inset - (if touch then 0 else 2), 0, inset),
		CornerRadius = if touch then "round" else 30,
		Parent = bar,
	}, stop, Theme.Colors.Red, Color3.fromRGB(190, 40, 60))

	-- Lobby players can also watch a round in progress; someone sitting it out can jump into the
	-- next one. (Scaled units: phones 52 points tall.)
	local width, height, gap = if touch then 300 else 270, if touch then 84 else 64, 16
	local pair = UIKit.new("Frame", {
		Name = "SpectateButton",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = if touch then UDim2.new(0.5, 0, 1, -8) else UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(2 * width + gap, height),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = context.Hud,
	})
	UIKit.AutoScale(pair)
	-- In the middle, as the owner asked, WATCH reaches into the MOVE stick's zone on smaller phones
	-- (a thumb starting further left still walks). tools/checks: allowed there.
	pair:SetAttribute("PP_Popup", true)
	openButton = UIKit.Button({
		Name = "Watch",
		Text = "👀 WATCH",
		TextSize = if touch then 30 else 26,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(width, height),
		CornerRadius = height / 2,
		Parent = pair,
	}, start, Theme.Colors.Cyan, Color3.fromRGB(50, 120, 230))
	local playButton = UIKit.Button({
		Name = "Play",
		Text = "🎮 PLAY NEXT ROUND",
		TextSize = if touch then 28 else 24,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(width, height),
		CornerRadius = height / 2,
		Parent = pair,
	}, function()
		SitOutSwitch.Request(false)
	end, Theme.Colors.Green, Color3.fromRGB(40, 160, 80))

	State.OpenScreen:Connect(function(name)
		if name == "Spectate" then
			start()
		end
	end)

	-- The "you're out" panel (RoundController) has its own Spectate button in the same spot.
	local outPanel = context.Hud:FindFirstChild("OutPanel") :: GuiObject?
	local function refresh()
		local phase = GameState.Get("Phase")
		local roundLive = phase == "InRound"
		if not roundLive and spectating then
			stop()
		end
		local watching = not spectating and not State.PlayingRound() and not (outPanel and outPanel.Visible)
		local watch = roundLive and watching and #targets() > 0
		local play = PAIR_PHASES[phase] == true and watching and State.SittingOut()
		openButton.Visible = watch
		playButton.Visible = play
		-- Side by side, or the one up in the middle.
		local both = watch and play
		openButton.Position = UDim2.new(0.5, if both then -(width + gap) / 2 else 0, 0, 0)
		playButton.Position = UDim2.new(0.5, if both then (width + gap) / 2 else 0, 0, 0)
		pair.Visible = watch or play
		SitOutSwitch.SetAside("Play", play)
	end
	GameState.Changed("Phase", refresh)
	Participants.Changed:Connect(refresh)
	player:GetAttributeChangedSignal("PP_SitOut"):Connect(refresh)
	player:GetAttributeChangedSignal("PP_InRound"):Connect(refresh)
	player:GetAttributeChangedSignal("PP_Alive"):Connect(refresh)
	task.spawn(function()
		while true do
			task.wait(0.5)
			refresh()
			if spectating then
				-- Follow the next survivor when the current one is knocked out.
				local list = targets()
				local subject = workspace.CurrentCamera.CameraSubject
				local watching = false
				for _, other in list do
					local character = other:Character()
					if character and subject and subject:IsDescendantOf(character) then
						watching = true
					end
				end
				if not watching then
					focus()
				end
			end
		end
	end)
	player.CharacterAdded:Connect(function()
		if not spectating then
			task.defer(resetCamera)
		end
	end)
end

return SpectateController
