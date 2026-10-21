-- Client half of Eatsa Pizza: the teams' shares eaten (a card each, with a bar and a big percent), the
-- EAT button (E), what the player's own slice is up to, a marker over the next slice to go to, and
-- the crumbs flying wherever someone chews.
--
-- The server owns the pizza ("Pizza": the layout, who owns each slice, the phase and the winner;
-- "Slices": the bites left on each). This client works out which slice its character stands on with
-- the same rule the server judges bites by (Shared/Logic/EatsaPizza.Locate), so "CHOMP!" here means
-- the bite counts there. Each press goes to the server as "Eat"; the crunch, crumbs and button
-- squash play at once. Crumbs for everyone else come from the shared bites left: when a slice loses
-- bites, crumbs fly from the characters standing on it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logic = require(ReplicatedStorage.Shared.Logic.EatsaPizza)
local Teams = require(ReplicatedStorage.Shared.Teams)

local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local EatsaPizza = {}

local SHAPES = { Red = "★", Blue = "●", Green = "▲", Yellow = "◆" }
local CRUMB_COLORS = { Color3.fromRGB(236, 190, 120), Color3.fromRGB(255, 214, 102), Color3.fromRGB(200, 60, 40) }

function EatsaPizza.Start(api)
	local me = api.Player
	local myId = me.UserId
	local touch = api:IsTouch()
	local hud = api:TopHud()
	local hudY = api:HudY()

	local pizza = api:SharedJSON("Pizza")
	local waited = 0
	while not pizza and waited < 10 do
		waited += task.wait(0.1)
		pizza = api:SharedJSON("Pizza")
	end
	if not pizza then
		return
	end
	local center = Vector3.new(pizza.C[1], pizza.C[2], pizza.C[3])
	local radius = pizza.R
	local owners: { string } = pizza.O
	local order = {}
	for _, entry in pizza.T do
		table.insert(order, entry.T)
	end
	local function myTeam(): string?
		local team = me:GetAttribute("PP_Team")
		if type(team) == "string" and table.find(order, team) then
			return team
		end
		for _, entry in pizza.T do
			if table.find(entry.M or {}, myId) then
				return entry.T
			end
		end
		return nil
	end
	local mine = myTeam()
	local myColor = if mine then Teams.Colors[mine] else Theme.Colors.Yellow

	local slices = api:SharedJSON("Slices") or { L = {}, M = {} }
	local function stageOf(index: number): number?
		local left, max = slices.L[index], slices.M[index]
		if owners[index] ~= mine or type(left) ~= "number" or left <= 0 then
			return nil
		end
		return Logic.Stage(left, max or 1)
	end
	local function myRoot(): BasePart?
		local _, _, root = api:Character()
		return root
	end
	-- The slice of mine I'm standing on (with food on it), by the server's rule.
	local function standingOn(): number?
		local root = myRoot()
		if not root or not mine then
			return nil
		end
		local offset = root.Position - center
		if offset.Y < -2 or offset.Y > 9 then
			return nil
		end
		return Logic.Locate(offset, radius, stageOf)
	end

	api:Mood({ Tint = Color3.fromRGB(255, 240, 222), Saturation = 0.14, Contrast = 0.05 })

	-- HUD ----------------------------------------------------------------------------------------
	-- (Phones: the team pill under the banner already shows each team's share with its shape, and
	-- the space under it is short before the move stick's corner, so only the status line shows.)
	local count = if touch then 0 else #order
	local gap = 10
	local cardW = math.min(140, math.floor((600 - (math.max(count, 1) - 1) * gap) / math.max(count, 1)))
	local row = UIKit.new("Frame", {
		Name = "Shares",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, hudY),
		Size = UDim2.fromOffset(math.max(count * cardW + (count - 1) * gap, 0), 62),
		BackgroundTransparency = 1,
		Visible = not touch,
		Parent = hud,
		Children = {
			UIKit.List(Enum.FillDirection.Horizontal, gap, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top),
		},
	})
	type Card = { Frame: Frame, Fill: Frame, Percent: TextLabel }
	local cards: { [string]: Card } = {}
	for index, team in if touch then {} else order do
		local color = Teams.Colors[team] or Color3.new(1, 1, 1)
		local frame = UIKit.new("Frame", {
			Name = `Team_{team}`,
			LayoutOrder = index,
			Size = UDim2.fromOffset(cardW, 62),
			BackgroundColor3 = Color3.fromRGB(32, 24, 54),
			BackgroundTransparency = 0.2,
			Parent = row,
			Children = {
				UIKit.Corner(12),
				UIKit.Stroke(if team == mine then Color3.new(1, 1, 1) else color, if team == mine then 3 else 2, 0),
			},
		})
		UIKit.Label({
			Name = "Name",
			Text = if team == mine then `{SHAPES[team] or ""} YOU` else `{SHAPES[team] or ""} {string.upper(team)}`,
			Font = Theme.Fonts.Display,
			TextSize = 22,
			TextColor3 = color,
			TextWrapped = false,
			Position = UDim2.fromOffset(6, 2),
			Size = UDim2.new(1, -12, 0, 26),
			Parent = frame,
			Children = { UIKit.TextStroke(0.1) },
		})
		local bar = UIKit.new("Frame", {
			Name = "Bar",
			Position = UDim2.fromOffset(6, 30),
			Size = UDim2.new(1, -12, 0, 26),
			BackgroundColor3 = Color3.fromRGB(14, 10, 26),
			BackgroundTransparency = 0.2,
			ClipsDescendants = true,
			Parent = frame,
			Children = { UIKit.Corner(8) },
		})
		local fill = UIKit.new("Frame", {
			Name = "Fill",
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = color,
			Parent = bar,
			Children = { UIKit.Corner(8) },
		})
		local percent = UIKit.Label({
			Name = "Percent",
			Text = "0%",
			Font = Theme.Fonts.Display,
			TextSize = 24,
			TextWrapped = false,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			Parent = bar,
			Children = { UIKit.TextStroke(0.05) },
		})
		cards[team] = { Frame = frame, Fill = fill, Percent = percent }
	end
	local status = UIKit.Label({
		Name = "Status",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, if touch then hudY else hudY + 68),
		Size = UDim2.fromOffset(if touch then 470 else 600, if touch then 28 else 32),
		Parent = hud,
		Children = { UIKit.TextStroke(0.1) },
	})
	if mine and not touch then
		api:Hint("Stand on your team's slices and mash E to eat them!", hudY + 104)
	end
	local hintShown = mine ~= nil and not touch

	local function teamShare(team: string): number
		local left, max = 0, 0
		for index = 1, Logic.SLICES do
			if owners[index] == team then
				left += slices.L[index] or 0
				max += slices.M[index] or 0
			end
		end
		return if max > 0 then math.clamp(1 - left / max, 0, 1) else 0
	end
	local function refreshCards()
		for _, team in order do
			local card = cards[team]
			if not card then
				continue
			end
			local share = teamShare(team)
			card.Fill.Size = UDim2.fromScale(share, 1)
			card.Percent.Text = `{math.floor(share * 100 + 1e-6)}%`
		end
	end
	refreshCards()

	-- Crumbs ---------------------------------------------------------------------------------------
	local crumbHolder = UIKit.new("Part", {
		Name = "Crumbs",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
		Size = Vector3.new(0.5, 0.5, 0.5),
		Parent = api.World,
	})
	local crumbs = UIKit.new("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(CRUMB_COLORS[1], CRUMB_COLORS[2]),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.15) }),
		Lifetime = NumberRange.new(0.4, 0.7),
		Speed = NumberRange.new(6, 11),
		SpreadAngle = Vector2.new(70, 70),
		Acceleration = Vector3.new(0, -40, 0),
		Rate = 0,
		LightInfluence = 0.5,
		Parent = crumbHolder,
	})
	local function crumbsAt(position: Vector3, amount: number)
		crumbHolder.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(-90), 0, 0)
		crumbs.Color = ColorSequence.new(CRUMB_COLORS[math.random(1, 3)], CRUMB_COLORS[math.random(1, 2)])
		crumbs:Emit(amount)
	end
	local function mouthOf(character: Model?): Vector3?
		local head = character and character:FindFirstChild("Head") :: BasePart?
		if not head then
			return nil
		end
		return (head.CFrame * CFrame.new(0, -0.3, -0.7)).Position
	end

	-- The marker over the slice to go to.
	local marker = UIKit.new("Part", {
		Name = "Marker",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
		Size = Vector3.new(0.2, 0.2, 0.2),
		Parent = api.World,
	})
	local markerGui = UIKit.new("BillboardGui", {
		Name = "GoHere",
		Size = UDim2.fromOffset(150, 90),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Enabled = false,
		Parent = marker,
	})
	UIKit.Label({
		Text = "EAT HERE",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		TextColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(1, 0, 0, 30),
		Parent = markerGui,
		Children = { UIKit.TextStroke(0) },
	})
	UIKit.Label({
		Text = "▼",
		Font = Theme.Fonts.Display,
		TextSize = 54,
		TextColor3 = myColor,
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 60),
		Parent = markerGui,
		Children = { UIKit.TextStroke(0) },
	})
	local function nextSlice(): number?
		local root = myRoot()
		if not root or not mine then
			return nil
		end
		local best, bestDistance = nil, math.huge
		for index = 1, Logic.SLICES do
			local stage = stageOf(index)
			if stage then
				local spot = center + Logic.StandSpot(index, stage, radius)
				local distance = (spot - root.Position).Magnitude
				if distance < bestDistance then
					best, bestDistance = index, distance
				end
			end
		end
		return best
	end

	-- Controls -------------------------------------------------------------------------------------
	local eat = nil
	local lastBite = -math.huge
	local deniedAt = -math.huge
	if mine then
		eat = api:Button({ Text = "EAT", Key = Enum.KeyCode.E, Color = myColor })
		eat.Pressed:Connect(function()
			if pizza.Ph ~= "Eat" then
				return
			end
			api:Action("Eat")
			local now = api:Now()
			if standingOn() then
				lastBite = now
				api:Sound("Click")
				local character = api:Character()
				local mouth = mouthOf(character)
				if mouth then
					crumbsAt(mouth, 6)
				end
			else
				deniedAt = now
			end
			if hintShown then
				hintShown = false
				task.delay(2, function()
					api:Hint("")
				end)
			end
		end)
	end

	-- Shared state --------------------------------------------------------------------------------
	local lastCrumbs: { [number]: number } = {}
	api:OnShared("Slices", function()
		local fresh = api:SharedJSON("Slices")
		if not fresh then
			return
		end
		local before = slices
		slices = fresh
		refreshCards()
		-- Crumbs from whoever is chewing a slice that just lost bites.
		local now = os.clock()
		for index = 1, Logic.SLICES do
			local was, is = before.L[index], slices.L[index]
			if
				type(was) == "number"
				and type(is) == "number"
				and is < was
				and now - (lastCrumbs[index] or 0) > 0.15
			then
				lastCrumbs[index] = now
				local team = owners[index]
				for _, participant in api:Participants() do
					if participant.UserId == myId then
						continue
					end
					local character = participant:Character()
					local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if root and participant:GetAttribute("PP_Team") == team then
						local spot = Logic.Locate(root.Position - center, radius, function(other)
							return if other == index then Logic.Stage(math.max(is, 1), slices.M[index] or 1) else nil
						end)
						local mouth = spot and mouthOf(character)
						if mouth then
							crumbsAt(mouth, 4)
						end
					end
				end
			end
		end
	end)
	api:OnShared("Pizza", function()
		local fresh = api:SharedJSON("Pizza")
		if not fresh then
			return
		end
		local wasPhase = pizza.Ph
		pizza = fresh
		if pizza.Ph == "Done" and wasPhase ~= "Done" then
			if hintShown then
				hintShown = false
				api:Hint("")
			end
			if pizza.W and pizza.W == mine then
				local root = myRoot()
				api:Effect("Confetti", (if root then root.Position else center) + Vector3.new(0, 4, 0), {
					myColor,
					Theme.Colors.Yellow,
				})
			end
		end
	end)
	api:OnEvent("SliceGone", function(index)
		if type(index) ~= "number" or index < 1 or index > Logic.SLICES then
			return
		end
		local spot = center + Logic.StandSpot(index, 3, radius) + Vector3.new(0, 1, 0)
		api:Effect("Poof", spot)
		if owners[index] == mine then
			api:Sound("Pickup")
		end
	end)

	-- Every frame ---------------------------------------------------------------------------------
	api:RenderStep(function(_dt)
		local now = api:Now()
		local on = standingOn()
		local playing = mine ~= nil and api:CanAct() and pizza.Ph == "Eat"

		-- The status line: what my slice is up to, or where to go.
		if pizza.Ph == "Done" then
			local winner = pizza.W
			status.Text = if winner then `{SHAPES[winner] or ""} {string.upper(winner)} WINS!` else "TIME UP!"
			status.TextColor3 = if winner then Teams.Colors[winner] or Color3.new(1, 1, 1) else Color3.new(1, 1, 1)
		elseif not playing then
			status.Text = if mine then "" else "Watch them chow down!"
			status.TextColor3 = Color3.new(1, 1, 1)
		elseif on then
			local left = slices.L[on] or 0
			local chomping = now - lastBite < 0.35
			local shape = if touch and mine then `{SHAPES[mine] or ""} ` else ""
			status.Text = if chomping then `{shape}CHOMP! {left} bites left` else `{shape}MASH EAT! {left} bites left`
			status.TextColor3 = if chomping then Theme.Colors.Yellow else Color3.new(1, 1, 1)
		elseif now - deniedAt < 1.2 then
			status.Text = "Not on your slice! Follow ▼"
			status.TextColor3 = Theme.Colors.Red
		else
			status.Text = if teamShare(mine :: string) >= 1 then "ALL EATEN!" else "Go to a slice with ▼!"
			status.TextColor3 = Color3.new(1, 1, 1)
		end

		-- The button fills as my slice goes.
		if eat then
			local max = on and slices.M[on]
			eat:SetFill(if on and max and max > 0 then 1 - (slices.L[on] or 0) / max else 0, Color3.new(1, 1, 1))
		end

		-- The marker over the next slice, while I'm not on one.
		local target = if playing and not on then nextSlice() else nil
		markerGui.Enabled = target ~= nil
		if target then
			local stage = stageOf(target) or 0
			local spot = center + Logic.StandSpot(target, stage, radius)
			marker.CFrame = CFrame.new(spot + Vector3.new(0, 7 + math.sin(now * 5) * 0.6, 0))
		end
	end)
end

return EatsaPizza
