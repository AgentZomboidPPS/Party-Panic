-- The "moving you to a busier party" card (owner: "Is there a way to merge severs automatically that
-- are getting low?"; Services/MergeService decides): when this server is quiet and a busier one has
-- room, everyone here sees the countdown with STAY, and goes along unless they press it. The card
-- goes when the server calls the move off ("Cancel") or the countdown runs out (Roblox's teleport
-- screen takes over).
-- Phones: at the top in the middle, under the phase banner and above the thumbstick's part of the
-- screen (its bottom two thirds); STAY is a 44 pt button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AudioController = require(script.Parent.AudioController)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local ServerMoveController = {}

function ServerMoveController.Start(context)
	local touch = UIKit.IsTouch()
	local remote = Remotes.Get("ServerMove")
	local height = 100
	local holder = UIKit.new("Frame", {
		Name = "ServerMove",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, if touch then 4 else 150), -- (Overlay starts under the top bar)
		Size = UDim2.fromOffset(560, height),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = context.Overlay,
	})
	UIKit.AutoScale(holder)
	local card = UIKit.Panel({
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		CornerRadius = 24,
		Parent = holder,
	}, Theme.Colors.Cyan, Color3.fromRGB(50, 120, 230))
	local title = UIKit.Label({
		Name = "Title",
		Text = "🎉 Moving you to a busier party!",
		Font = Theme.Fonts.Display,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		Position = UDim2.fromOffset(20, 14),
		Size = UDim2.new(1, -220, 0, 34),
		Parent = card,
		Children = { UIKit.TextStroke(0.2) },
	})
	title:SetAttribute("PP_TruncateOk", true)
	local count = UIKit.Label({
		Name = "Count",
		Text = "",
		TextSize = Theme.Touch.MinText + 2,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		Position = UDim2.fromOffset(20, 54),
		Size = UDim2.new(1, -220, 0, 30),
		Parent = card,
		Children = { UIKit.TextStroke(0.3) },
	})
	local stayHeight = if touch then Theme.Touch.Target else 60
	local token = 0
	local stay = UIKit.Button({
		Name = "Stay",
		Text = "STAY HERE",
		TextSize = if touch then 24 else 22,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(180, stayHeight),
		CornerRadius = stayHeight / 2,
		Parent = card,
	}, function()
		token += 1
		remote:FireServer("Stay")
		holder.Visible = false
	end, Theme.Colors.Lavender, Theme.Colors.Purple)
	stay:SetAttribute("PP_Keep", true)

	remote.OnClientEvent:Connect(function(action, seconds)
		token += 1
		if action ~= "Countdown" or type(seconds) ~= "number" then
			holder.Visible = false
			return
		end
		local mine = token
		holder.Visible = true
		UIKit.PopIn(holder, 0.3)
		AudioController.Play("Pickup")
		task.spawn(function()
			local left = math.floor(seconds)
			while left > 0 and mine == token do
				count.Text = `More players there. Going in {left}s`
				task.wait(1)
				left -= 1
			end
			if mine == token then
				count.Text = "Off we go!"
			end
		end)
	end)
end

return ServerMoveController
