-- Client half of Honey Trap: draws the vine of fruit and honeycombs (sliding down as they're
-- taken), the 1-or-2 block over whoever's turn it is, fruit flying into baskets and the bees.
-- Shows whose turn it is; on yours the HIT button appears (jumping hits the block too).
--
-- Art pass: warm storybook grading, a leafy vine, and (unless effects are reduced) pollen motes,
-- blossom petals drifting off the oak, butterflies over the flower beds and bees round the hives.

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local HoneyTrap = {}

local SLIDE_TIME = 0.45 -- the vine sliding down after a take
local FLY_TIME = 0.6 -- an item flying into a basket
local ONE = Color3.fromRGB(90, 190, 255)
local TWO = Color3.fromRGB(255, 150, 50)

type Item = {
	Model: Model,
	Kind: string,
	Center: Vector3,
	Turn: CFrame,
	Born: number,
	Bee: Model?,
}

type Flight = {
	Model: Model,
	Center: Vector3,
	From: Vector3,
	To: Vector3,
	Start: number,
	Spin: number,
	Honey: boolean,
	Taker: number?,
}

type Swarm = {
	Bees: { { Model: Model, Angle: number, Radius: number, Height: number, Speed: number } },
	User: number?,
	Fallback: Vector3,
	Start: number,
}

local function vec(list: { number }): Vector3
	return Vector3.new(list[1], list[2], list[3])
end

local function ease(alpha: number): number
	return 1 - (1 - alpha) ^ 3
end

-- The root part of whoever has this UserId, player or bot.
local function rootOf(api, userId: number?): BasePart?
	local character = api:CharacterOf(userId)
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function partsOf(model: Instance): { BasePart }
	local list = {}
	if model:IsA("BasePart") then
		table.insert(list, model)
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(list, descendant)
		end
	end
	return list
end

-- Client-only decoration: anchored, never in the way of anything.
local function settle(model: Instance)
	for _, part in partsOf(model) do
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	end
end

-- A model's bounding-box center relative to its pivot, so it can be placed by its middle.
local function centerOffset(model: Model): Vector3
	local box = model:GetBoundingBox()
	return model:GetPivot():PointToObjectSpace(box.Position)
end

-- A stand-in when a shared template never arrives: a ball for fruit, a slab for a honeycomb, a
-- cube for the block.
local function fallbackModel(kind: string): Model
	local model = Instance.new("Model")
	local part = Instance.new("Part")
	part.Name = if kind == "H" then "Comb" elseif kind == "Dice" then "Block" else "Fruit"
	part.Shape = if kind == "H" or kind == "Dice" then Enum.PartType.Block else Enum.PartType.Ball
	part.Size = if kind == "H"
		then Vector3.new(2.4, 2.8, 0.9)
		elseif kind == "Dice" then Vector3.one * 4
		else Vector3.one * 2.1
	part.Color = Color3.fromRGB(240, 170, 40)
	part.Parent = model
	model.PrimaryPart = part
	return model
end

-- The time-of-turn face of the block (the server uses the same rule).
local function faceAt(turn, t: number): number
	if t <= turn.T0 then
		return turn.First
	end
	local flips = math.floor((t - turn.T0) / turn.Flip)
	return ((turn.First - 1 + flips) % 2) + 1
end

function HoneyTrap.Start(api)
	api:Mood({
		Tint = Color3.fromRGB(255, 246, 228),
		Saturation = 0.2,
		Contrast = 0.06,
		Brightness = 0.02,
		Haze = Color3.fromRGB(255, 236, 206),
	})
	local layout = api:SharedJSON("Layout")
	while not layout do
		task.wait(0.1)
		layout = api:SharedJSON("Layout")
	end
	local effects = not State.ReducedEffects()
	local rng = Random.new()
	local anchor = vec(layout.Anchor)
	local bottomY = layout.Bottom
	local spacing = layout.Spacing
	local visible = math.floor((anchor.Y - 1.6 - bottomY) / spacing) + 1
	local pads = {}
	for index, pad in layout.Pads do
		pads[pad.User] = { Index = index, Pos = vec(pad.Pos), Basket = vec(pad.Basket), Count = 0 }
	end
	local me = api.Player.UserId

	-- Templates the server shared (fruit is recolored per kind).
	local templates = {}
	for _, name in { "Fruit", "Honeycomb", "Bee", "DiceBlock", "Vine" } do
		task.spawn(function()
			templates[name] = api:Template(name)
		end)
	end
	local waited = 0
	while waited < 5 and not (templates.Fruit and templates.Honeycomb and templates.Bee and templates.DiceBlock) do
		waited += task.wait(0.1)
	end
	local fruitColors = {}
	for index, color in layout.Fruits or {} do
		fruitColors[tostring(index)] = Color3.fromRGB(color[1], color[2], color[3])
	end

	local function makeItem(kind: string): Model
		local template = if kind == "H" then templates.Honeycomb else templates.Fruit
		local model = if template then template:Clone() else fallbackModel(kind)
		local color = fruitColors[kind]
		if color then
			for _, part in partsOf(model) do
				if part.Name == "Fruit" then
					part.Color = color
				end
			end
		end
		settle(model)
		model.Parent = api.World
		return model
	end

	local function makeBee(): Model?
		local template = templates.Bee
		if not template then
			return nil
		end
		local bee = template:Clone()
		settle(bee)
		for _, part in partsOf(bee) do
			part.CastShadow = false
			if part.Name == "Wings" then
				part.Transparency = 0.35
			end
		end
		bee.Parent = api.World
		return bee
	end

	-- The vine itself: a leafy vine from inside the branch tip down past the lowest item (its leaves
	-- grow to the sides and the back, away from the hanging fruit); a plain rope if it never came.
	local ropeLength = anchor.Y - bottomY + 1.2
	if templates.Vine then
		local vineModel = templates.Vine:Clone()
		settle(vineModel)
		local _, size = vineModel:GetBoundingBox()
		vineModel:PivotTo(CFrame.new(anchor.X, anchor.Y + 1.2 - size.Y, anchor.Z))
		vineModel.Parent = api.World
	else
		local rope = Instance.new("Part")
		rope.Name = "Vine"
		rope.Shape = Enum.PartType.Cylinder
		rope.Size = Vector3.new(ropeLength, 0.4, 0.4)
		rope.CFrame = CFrame.new(anchor.X, anchor.Y - ropeLength / 2, anchor.Z) * CFrame.Angles(0, 0, math.rad(90))
		rope.Color = Color3.fromRGB(80, 130, 50)
		rope.Material = Enum.Material.SmoothPlastic
		settle(rope)
		rope.Parent = api.World
	end

	-- Items hang on the front of the vine (towards the players), zigzagging a little.
	local shown: { [number]: Item } = {}
	local vine = api:SharedJSON("Vine") or { Start = 1, Items = "" }
	local viewFrom, viewTo, slideStart = vine.Start, vine.Start, 0
	local function view(now: number): number
		local alpha = math.clamp((now - slideStart) / SLIDE_TIME, 0, 1)
		return viewFrom + (viewTo - viewFrom) * ease(alpha)
	end
	local function hangPosition(index: number, viewStart: number, t: number): Vector3
		local side = if index % 2 == 0 then 1 else -1
		local sway = math.sin(t * 1.4 + index * 0.9) * 0.12
		-- Items still coming down out of the branch wait at its tip.
		local height = math.min(bottomY + (index - viewStart) * spacing, anchor.Y - 0.8)
		return Vector3.new(anchor.X + side * 0.35 + sway, height, anchor.Z + 1.0)
	end
	local function ensureItems()
		for offset = 0, visible - 1 do
			local index = vine.Start + offset
			local kind = string.sub(vine.Items, offset + 1, offset + 1)
			if kind ~= "" and not shown[index] then
				local model = makeItem(kind)
				-- Honeycombs face the players; fruit turn every which way.
				local turn = if kind == "H"
					then CFrame.Angles(0, math.pi, 0)
					else CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.2, 0.2))
				shown[index] = {
					Model = model,
					Kind = kind,
					Center = centerOffset(model),
					Turn = turn,
					Born = os.clock(),
					Bee = if kind == "H" and effects then makeBee() else nil,
				}
			end
		end
	end
	ensureItems()

	-- Taken items fly in an arc into the taker's basket and stay there.
	local flights: { Flight } = {}
	local swarms: { Swarm } = {}
	local function basketSpot(pad): Vector3
		local n = pad.Count
		pad.Count += 1
		local layer = math.floor(n / 7) % 3
		local slot = n % 7
		local ring = if slot == 0
			then Vector3.zero
			else Vector3.new(math.cos(slot * math.pi / 3), 0, math.sin(slot * math.pi / 3)) * 0.85
		return pad.Basket + ring + Vector3.new(0, 1.0 + layer * 0.75, 0)
	end
	local function launch(item: Item, from: Vector3, taker: number?, order: number, honey: boolean)
		if item.Bee then
			item.Bee:Destroy()
			item.Bee = nil
		end
		local pad = if taker then pads[taker] else nil
		local to = if pad then basketSpot(pad) else from - Vector3.new(0, 6, 0)
		table.insert(flights, {
			Model = item.Model,
			Center = item.Center,
			From = from,
			To = to,
			Start = os.clock() + order * 0.18,
			Spin = rng:NextNumber(-8, 8),
			Honey = honey,
			Taker = taker,
		})
	end

	local function startSwarm(userId: number?, near: Vector3)
		if not effects then
			api:Effect("Poof", near)
			return
		end
		local swarm: Swarm = { Bees = {}, User = userId, Fallback = near, Start = os.clock() }
		for index = 1, 7 do
			local bee = makeBee()
			if bee then
				table.insert(swarm.Bees, {
					Model = bee,
					Angle = index / 7 * math.pi * 2,
					Radius = rng:NextNumber(1.8, 3.2),
					Height = rng:NextNumber(-0.5, 2.5),
					Speed = rng:NextNumber(5, 8) * (if index % 2 == 0 then 1 else -1),
				})
			end
		end
		table.insert(swarms, swarm)
	end

	api:OnShared("Vine", function()
		local new = api:SharedJSON("Vine")
		if not new then
			return
		end
		if new.Start > vine.Start then
			local now = os.clock()
			local current = view(now)
			local t = api:Now()
			local order = 0
			for index = vine.Start, new.Start - 1 do
				local item = shown[index]
				if item then
					shown[index] = nil
					local honey = new.Honey == true and item.Kind == "H"
					launch(item, hangPosition(index, current, t), new.Taker, order, honey)
					order += 1
				end
			end
			viewFrom, viewTo, slideStart = current, new.Start, now
		end
		vine = new
		ensureItems()
	end)

	-- The 1-or-2 block, with its number on every side.
	local dice = templates.DiceBlock or fallbackModel("Dice")
	settle(dice)
	local block: BasePart? = dice:FindFirstChild("Block", true) :: BasePart?
	for _, part in partsOf(dice) do
		part.CastShadow = false
		if part.Name == "Wings" then
			part.Transparency = 0.3
		end
		if not dice:FindFirstChild("Block", true) and (not block or part.Size.Magnitude > block.Size.Magnitude) then
			block = part
		end
	end
	local numbers = {}
	if block then
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
			local gui = Instance.new("SurfaceGui")
			gui.Face = face
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 50
			gui.LightInfluence = 0.2
			gui.Parent = block
			local label = UIKit.Label({
				Text = "1",
				Font = Theme.Fonts.Display,
				TextScaled = true,
				Size = UDim2.fromScale(0.8, 0.8),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Parent = gui,
				Children = { UIKit.TextStroke(0) },
			})
			table.insert(numbers, label)
		end
	end
	local diceCenter = centerOffset(dice)
	dice.Parent = nil

	-- Turn HUD: whose turn, a timer bar, your fruit, and the HIT button on your turn.
	local hud = api:TopHud()
	local y = api:HudY()
	local panel = UIKit.Panel({
		Name = "Turn",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.fromOffset(420, 66),
		CornerRadius = 22,
		Visible = false,
		Parent = hud,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	local turnText = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 34,
		Size = UDim2.new(1, -24, 0, 46),
		Position = UDim2.fromOffset(12, 4),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = panel,
		Children = { UIKit.TextStroke(0.15) },
	})
	local timerBack = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -40, 0, 8),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = panel,
		Children = { UIKit.Round() },
	})
	local timerBar = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Yellow,
		Parent = timerBack,
		Children = { UIKit.Round() },
	})
	local fruitPill = UIKit.Panel({
		Name = "Fruit",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, y + 8),
		Size = UDim2.fromOffset(92, 50),
		CornerRadius = 25,
		Visible = pads[me] ~= nil,
		Parent = hud,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	local fruitText = UIKit.Label({
		Text = "🍎 0",
		Font = Theme.Fonts.Display,
		TextSize = 28,
		Size = UDim2.fromScale(1, 1),
		Parent = fruitPill,
	})
	api:OnMine("Fruit", function(value)
		fruitText.Text = `🍎 {value or 0}`
		UIKit.PopIn(fruitPill, 0.25)
	end)
	api:Hint("Take 1 or 2 each turn - don't take the 🍯 honeycomb!", y + 74)

	local hit = api:Button({ Text = "HIT!", Key = Enum.KeyCode.E, Color = Theme.Colors.Yellow })
	hit:SetVisible(false)

	local turn = api:SharedJSON("Turn")
	local turnShownAt = 0
	local pending: number? = nil -- turn id we already sent a hit for
	local predicted: number? = nil
	local announcedResult: number? = nil
	local resultAt = 0

	local function myTurnLive(t: number): boolean
		return turn ~= nil
			and turn.User == me
			and turn.Result == nil
			and pending ~= turn.Id
			and t >= turn.T0 - 0.05
			and t <= turn.Deadline
			and api:Alive()
	end

	local function tryHit()
		local t = api:Now()
		if not myTurnLive(t) then
			return
		end
		pending = turn.Id
		predicted = faceAt(turn, t)
		api:Action("Hit", predicted)
		api:Sound("Hit")
	end
	hit.Pressed:Connect(tryHit)

	-- Jumping into the block hits it, like the real thing.
	local function watchJumps(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
		if humanoid then
			api:Track(humanoid.StateChanged:Connect(function(_, new)
				if new == Enum.HumanoidStateType.Jumping then
					tryHit()
				end
			end))
		end
	end
	if api.Player.Character then
		task.spawn(watchJumps, api.Player.Character)
	end
	api:Track(api.Player.CharacterAdded:Connect(watchJumps))

	local function onTurn()
		local new = api:SharedJSON("Turn")
		if not new then
			return
		end
		local fresh = not turn or new.Id ~= turn.Id
		turn = new
		if fresh then
			turnShownAt = os.clock()
			predicted = nil
			local pad = pads[new.User]
			if pad then
				dice:PivotTo(CFrame.new(pad.Pos + Vector3.new(0, 9, 0)) * CFrame.new(-diceCenter))
				dice.Parent = api.World
			end
			panel.Visible = true
			if new.User == me then
				turnText.Text = "🎲 YOUR TURN!"
				turnText.TextColor3 = Theme.Colors.Yellow
				api:Sound("Countdown")
				api:Hint("Jump or press HIT to stop the block!", y + 74)
			else
				turnText.Text = `🎲 {new.Name}'s turn`
				turnText.TextColor3 = Theme.Colors.Text
				api:Hint(if new.Next == me and api:Alive() then "You're up next - count the fruit!" else "", y + 74)
			end
			UIKit.PopIn(panel, 0.3)
		end
		if new.Result and announcedResult ~= new.Id then
			announcedResult = new.Id
			resultAt = os.clock()
			if new.User == me then
				api:Hint("", y + 74)
			end
			local pad = pads[new.User]
			if pad then
				api:Effect("Stars", pad.Pos + Vector3.new(0, 9, 0))
			end
		end
	end
	api:OnShared("Turn", onTurn)
	if turn then
		turn = nil
		onTurn()
	end

	-- Bees that live around the hive on the tree.
	local arena = api:Arena(5)
	local hiveBees = {}
	if arena and effects then
		local tree = arena:FindFirstChild("HoneyOak")
		local hive = tree and tree:FindFirstChild("Hive", true) :: BasePart?
		if hive then
			for index = 1, 4 do
				local bee = makeBee()
				if bee then
					table.insert(hiveBees, { Model = bee, Center = hive.Position, Phase = index * 1.6, Radius = 4.5 })
				end
			end
		end
		-- One bee buzzing round each straw beehive.
		for index, child in arena:GetChildren() do
			if child.Name == "HoneySkep" and child:IsA("Model") then
				local bee = makeBee()
				if bee then
					local center = child:GetPivot().Position + Vector3.new(0, 4.2, 0)
					table.insert(hiveBees, { Model = bee, Center = center, Phase = index * 2.3, Radius = 2.6 })
				end
			end
		end
	end

	-- Ambient life (off with reduced effects): pollen motes over the glade, blossom glints drifting
	-- down from the oak, and butterflies flitting round the tree below the vine.
	local ground = bottomY
	for _, pad in pads do
		ground = math.min(ground, pad.Pos.Y - 0.6)
	end
	local trunk = Vector3.new(anchor.X, ground, anchor.Z - 14.5)
	local butterflies = {}
	if effects then
		local function carrier(name: string, size: Vector3, position: Vector3): Part
			local part = Instance.new("Part")
			part.Name = name
			part.Size = size
			part.CFrame = CFrame.new(position)
			part.Transparency = 1
			settle(part)
			part.CastShadow = false
			part.Parent = api.World
			return part
		end
		local pollen = Instance.new("ParticleEmitter")
		pollen.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pollen.Color = ColorSequence.new(Color3.fromRGB(255, 236, 150))
		pollen.LightEmission = 0.8
		pollen.Transparency = NumberSequence.new(0.15)
		pollen.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.22),
			NumberSequenceKeypoint.new(1, 0),
		})
		pollen.Lifetime = NumberRange.new(6, 10)
		pollen.Speed = NumberRange.new(0.3, 0.9)
		pollen.SpreadAngle = Vector2.new(180, 180)
		pollen.Acceleration = Vector3.new(0, 0.2, 0)
		pollen.Rate = 10
		pollen.Parent = carrier("Pollen", Vector3.new(56, 4, 56), Vector3.new(anchor.X, ground + 4, anchor.Z - 4))

		local petals = Instance.new("ParticleEmitter")
		petals.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		petals.Color = ColorSequence.new(Color3.fromRGB(255, 190, 220), Color3.fromRGB(255, 240, 248))
		petals.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.1, 0.1),
			NumberSequenceKeypoint.new(0.85, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		petals.Size = NumberSequence.new(0.45)
		petals.Lifetime = NumberRange.new(8, 11)
		petals.Speed = NumberRange.new(0.2, 0.6)
		petals.SpreadAngle = Vector2.new(60, 60)
		petals.EmissionDirection = Enum.NormalId.Bottom
		petals.Acceleration = Vector3.new(0.6, -1.6, 0.8)
		petals.Drag = 0.45
		petals.Rotation = NumberRange.new(0, 360)
		petals.RotSpeed = NumberRange.new(-90, 90)
		petals.Rate = 4
		petals.Parent = carrier("Petals", Vector3.new(34, 1, 30), trunk + Vector3.new(0, 35, 0))

		local wingColors = {
			Color3.fromRGB(255, 150, 200),
			Color3.fromRGB(180, 150, 255),
			Color3.fromRGB(255, 220, 90),
			Color3.fromRGB(130, 200, 255),
			Color3.fromRGB(255, 170, 110),
		}
		for index, color in wingColors do
			local wings = {}
			for _ = 1, 2 do
				local wing = Instance.new("Part")
				wing.Name = "Butterfly"
				wing.Size = Vector3.new(0.9, 0.05, 0.75)
				wing.Color = color
				wing.Material = Enum.Material.SmoothPlastic
				local shape = Instance.new("SpecialMesh")
				shape.MeshType = Enum.MeshType.Sphere
				shape.Parent = wing
				settle(wing)
				wing.CastShadow = false
				wing.Parent = api.World
				table.insert(wings, wing)
			end
			table.insert(butterflies, {
				Wings = wings,
				Angle = index / #wingColors * math.pi * 2,
				Radius = rng:NextNumber(15, 21),
				Height = rng:NextNumber(1.8, 4.2),
				Speed = rng:NextNumber(0.14, 0.22) * (if index % 2 == 0 then 1 else -1),
				Phase = rng:NextNumber(0, 6),
			})
		end
	end

	api:RenderStep(function()
		local now = os.clock()
		local t = api:Now()
		local viewStart = view(now)

		-- The vine.
		for index, item in shown do
			local center = hangPosition(index, viewStart, t)
			item.Model:PivotTo(CFrame.new(center) * item.Turn * CFrame.new(-item.Center))
			if item.Bee then
				local angle = t * 3 + index
				local spot = center
					+ Vector3.new(math.cos(angle) * 1.9, 0.6 + math.sin(t * 7) * 0.15, math.sin(angle) * 1.9)
				item.Bee:PivotTo(CFrame.lookAt(spot, spot + Vector3.new(-math.sin(angle), 0, math.cos(angle))))
			end
		end

		-- Flying items.
		for index = #flights, 1, -1 do
			local flight = flights[index]
			local alpha = (now - flight.Start) / FLY_TIME
			if alpha < 0 then
				continue
			end
			if alpha >= 1 then
				flight.Model:PivotTo(CFrame.new(flight.To) * CFrame.new(-flight.Center))
				table.remove(flights, index)
				if flight.Honey then
					api:Sound("HazardWarning")
					startSwarm(flight.Taker, flight.To)
				else
					api:Sound("Pickup")
				end
				continue
			end
			local arc = 4 * 4 * alpha * (1 - alpha) -- peaks 4 studs above the straight line
			local position = flight.From:Lerp(flight.To, alpha) + Vector3.new(0, arc, 0)
			flight.Model:PivotTo(
				CFrame.new(position)
					* CFrame.Angles(flight.Spin * alpha, flight.Spin * alpha * 0.5, 0)
					* CFrame.new(-flight.Center)
			)
		end

		-- Bee swarms chasing whoever took a honeycomb.
		for index = #swarms, 1, -1 do
			local swarm = swarms[index]
			local age = now - swarm.Start
			local root = rootOf(api, swarm.User)
			local target = if root then root.Position else swarm.Fallback
			local leaving = math.max(0, age - 3.2)
			for _, bee in swarm.Bees do
				local angle = bee.Angle + age * bee.Speed
				local spot = target
					+ Vector3.new(
						math.cos(angle) * bee.Radius,
						bee.Height + math.sin(age * 9 + bee.Angle) * 0.4,
						math.sin(angle) * bee.Radius
					)
					+ Vector3.new(0, leaving * 14, 0)
				bee.Model:PivotTo(
					CFrame.lookAt(spot, spot + Vector3.new(-math.sin(angle), 0, math.cos(angle)) * bee.Speed)
				)
			end
			if age > 4.2 then
				for _, bee in swarm.Bees do
					bee.Model:Destroy()
				end
				table.remove(swarms, index)
			end
		end

		-- Hive bees.
		for _, bee in hiveBees do
			local angle = t * 1.7 + bee.Phase
			local spot = bee.Center
				+ Vector3.new(
					math.cos(angle) * bee.Radius,
					math.sin(t * 2.3 + bee.Phase) * 1.5,
					math.sin(angle) * bee.Radius
				)
			bee.Model:PivotTo(CFrame.lookAt(spot, spot + Vector3.new(-math.sin(angle), 0, math.cos(angle))))
		end

		-- Butterflies: lazy loops round the oak, bobbing, wings flapping.
		for _, fly in butterflies do
			local angle = fly.Angle + t * fly.Speed + math.sin(t * 0.7 + fly.Phase) * 0.3
			local radius = fly.Radius + math.sin(t * 0.5 + fly.Phase) * 2
			local spot = trunk
				+ Vector3.new(
					math.sin(angle) * radius,
					fly.Height + math.sin(t * 1.9 + fly.Phase) * 0.6,
					math.cos(angle) * radius
				)
			local ahead = Vector3.new(math.cos(angle), 0, -math.sin(angle)) * math.sign(fly.Speed)
			local body = CFrame.lookAt(spot, spot + ahead)
			local flap = math.sin(t * 16 + fly.Phase) * 0.9
			fly.Wings[1].CFrame = body * CFrame.Angles(0, 0, flap) * CFrame.new(-0.5, 0, 0)
			fly.Wings[2].CFrame = body * CFrame.Angles(0, 0, -flap) * CFrame.new(0.5, 0, 0)
		end

		-- The block and the turn HUD.
		if turn and dice.Parent then
			local pad = pads[turn.User]
			local face = turn.Result or (if turn.User == me and predicted then predicted else faceAt(turn, t))
			local drop = math.clamp((now - turnShownAt) / 0.35, 0, 1)
			local done = turn.Result ~= nil
			local hop = if done then 0 else math.max(0, 0.35 - ((t - turn.T0) % turn.Flip)) * 1.2
			local lift = (1 - ease(drop)) * 5 + hop + math.sin(now * 3) * 0.2
			if pad then
				dice:PivotTo(
					CFrame.new(pad.Pos + Vector3.new(0, 9 + lift, 0))
						* CFrame.Angles(0, now * 0.8, 0)
						* CFrame.new(-diceCenter)
				)
			end
			if block then
				block.Color = if face == 1 then ONE else TWO
			end
			for _, label in numbers do
				label.Text = tostring(face)
			end
			if done and now - resultAt > 1.1 then
				dice.Parent = nil -- the take has played out
			end
			local left = math.clamp((turn.Deadline - t) / (turn.Deadline - turn.T0), 0, 1)
			timerBar.Size = UDim2.fromScale(if done then 0 else left, 1)
			timerBar.BackgroundColor3 = if left < 0.3 then Theme.Colors.Red else Theme.Colors.Yellow
		end
		local live = myTurnLive(t)
		hit:SetVisible(live)
		if live then
			hit:SetFill(math.clamp((turn.Deadline - t) / (turn.Deadline - turn.T0), 0, 1))
		end
	end)

	api:Track(function()
		dice:Destroy()
	end)
end

return HoneyTrap
