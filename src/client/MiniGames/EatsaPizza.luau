-- Client half of Eatsa Pizza: the teams' shares eaten (a card each, with a bar and a big percent), the
-- EAT button (E), the BITE SPOTS (a glowing ring on the cheese for every spot, a bobbing ▼ over each
-- of my team's, "EAT HERE" over the nearest), what my spot is up to, and the crumbs flying wherever
-- someone chews.
--
-- Run, chomp, run (owner: "eatza pizza is better. can we make players run around while eating instead
-- of just sitting on the slice?"): you eat at your team's spots, not wherever you stand. Each spot's
-- ring is a clock of its bites (its segments go out as it's eaten); when mine is eaten it pops here
-- at once (the server's next one lights up a moment later, about a second's run away) and the status
-- line and ▼ send me to the next. Pressing EAT off a spot says so ("Not on a spot!").
--
-- Every bite shows (owner: "can we make the eatsa pizza game more interactable? In mario party it
-- feels and plays a ton better."): heads dip into the pizza with each chomp (Client/Pose; the
-- player's own at once, everyone else's as their bites come in), the crunch changes pitch, a phone
-- taps back, a combo counts up (it keeps going from one spot to the next if you run straight there)
-- with a cheer at 12 / 24 / 40 / 60, and each pepperoni the bites reach flies into the eater's mouth
-- ("Pep"). THE HOT PEPPER ("Chili") turns and glows over the pizza with a timer over it; whoever grabs
-- it ("Spicy") catches fire and eats two bites a press for a while.
--
-- The server owns the pizza ("Pizza": the layout, who owns each slice, the phase and the winner;
-- "Slices": the bites left on each; "Spots": every spot, its team and bites left). This client works
-- out which spot its character stands on with the same rule the server judges bites by
-- (Shared/Logic/EatsaPizza.OnSpot), so "CHOMP!" here means the bite counts there. Each press goes to
-- the server as "Eat"; the crunch, crumbs and button squash play at once, and my own presses count
-- my spot down here (so it pops when it's eaten, not a ping later). Crumbs for everyone else come
-- from the shared spots: when one loses bites, crumbs fly from the characters standing on it.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logic = require(ReplicatedStorage.Shared.Logic.EatsaPizza)
local Teams = require(ReplicatedStorage.Shared.Teams)

local Haptics = require(script.Parent.Parent.Haptics)
local Pose = require(script.Parent.Parent.Pose)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local EatsaPizza = {}

local SHAPES = { Red = "■", Blue = "●", Green = "▲", Yellow = "◆" }
local CRUMB_COLORS = { Color3.fromRGB(236, 190, 120), Color3.fromRGB(255, 214, 102), Color3.fromRGB(200, 60, 40) }
local CHOMP_TIME = 0.2 -- a head's dip into the pizza and back
local NECK_DIP, WAIST_DIP = math.rad(-30), math.rad(-16)
local COMBO_GAP = 0.9 -- seconds between bites on a spot that still keep a combo going...
local RUN_GAP = 2.8 -- ...and from eating a spot to the first bite of the next (a straight run there)
local CHEERS = { [12] = "TASTY!", [24] = "YUMMY!", [40] = "MAMMA MIA!", [60] = "PIZZA MONSTER!" }
local PEPPERONI = Color3.fromRGB(176, 42, 34)
local SPICY = Color3.fromRGB(255, 110, 40)
local SEGMENTS = 12 -- a spot's ring: one segment lit for each twelfth of its bites left
local DONE_HOLD = 1.0 -- seconds a spot my presses ate stays eaten here before the server has the last word

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
	local cheeseY = center.Y + Logic.MESH_CHEESE * radius / Logic.MESH_RADIUS

	-- The spots: I (id), T (team), X, Z (offset from the middle), L (bites left), M (bites it had).
	type SpotData = { I: number, T: string, X: number, Z: number, L: number, M: number }
	local function readSpots(): { SpotData }
		local fresh = api:SharedJSON("Spots")
		local list = {}
		if type(fresh) == "table" and type(fresh.S) == "table" then
			for _, spot in fresh.S do
				if
					type(spot) == "table"
					and type(spot.I) == "number"
					and type(spot.T) == "string"
					and type(spot.X) == "number"
					and type(spot.Z) == "number"
					and type(spot.L) == "number"
					and type(spot.M) == "number"
				then
					table.insert(list, spot)
				end
			end
		end
		return list
	end
	local spots = readSpots()
	-- My own presses, counted here: the bites I think a spot has left, and the spots I've eaten up (a
	-- moment before the server says so).
	local predicted: { [number]: number } = {}
	local doneAt: { [number]: number } = {}
	local function leftAt(spot: SpotData): number
		return math.min(spot.L, predicted[spot.I] or spot.L)
	end
	local function eatenHere(id: number): boolean
		return doneAt[id] ~= nil and os.clock() - doneAt[id] < DONE_HOLD
	end
	local function mySpots(): { SpotData }
		local list = {}
		for _, spot in spots do
			if spot.T == mine and not eatenHere(spot.I) then
				table.insert(list, spot)
			end
		end
		return list
	end
	local function myRoot(): BasePart?
		local _, _, root = api:Character()
		return root
	end
	-- My team's spot I'm standing on, by the server's rule.
	local function standingOn(): SpotData?
		local root = myRoot()
		if not root or not mine then
			return nil
		end
		local offset = root.Position - center
		if offset.Y < -2 or offset.Y > 9 then
			return nil
		end
		local list = mySpots()
		local index = Logic.OnSpot(offset.X, offset.Z, list)
		return if index then list[index] else nil
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
	local cardTeams: { string } = if touch then {} else order
	for index, team in cardTeams do
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
		TextSize = if touch then 30 else 26,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, if touch then hudY else hudY + 68),
		Size = UDim2.fromOffset(if touch then 470 else 600, 32),
		Parent = hud,
		Children = { UIKit.TextStroke(0.1) },
	})
	-- Under the status line: the combo, its cheers, the pepperoni and the hot pepper's news.
	local callout = UIKit.Label({
		Name = "Callout",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, (if touch then hudY else hudY + 68) + 36),
		Size = UDim2.fromOffset(if touch then 470 else 600, 34),
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0.05) },
	})
	local calloutUntil = 0
	local calloutPriority = 0
	local function showCallout(text: string, color: Color3, life: number, priority: number?)
		local now = os.clock()
		if now < calloutUntil and (priority or 0) < calloutPriority then
			return
		end
		calloutPriority = priority or 0
		calloutUntil = now + life
		callout.Text = text
		callout.TextColor3 = color
		callout.Visible = true
		UIKit.PopIn(callout, 0.2)
	end
	if mine and not touch then
		api:Hint("Run to your team's glowing spots and mash E to eat them!", hudY + 104)
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

	-- Chomping heads: each bite dips the head and shoulders into the pizza and back (over whatever the
	-- body's animation is doing).
	type Chewer = { Rig: { [string]: Pose.Joint }, At: number, Posed: boolean }
	local chewers: { [Model]: Chewer } = {}
	local function chomp(character: Model?)
		if not character then
			return
		end
		local chewer = chewers[character]
		if not chewer then
			chewer = { Rig = Pose.Rig(character, { "Neck", "Waist" }), At = -math.huge, Posed = false }
			chewers[character] = chewer
		end
		chewer.At = os.clock()
	end
	api:Track(Pose.Step(function()
		local clock = os.clock()
		for character, chewer in chewers do
			if not character.Parent then
				chewers[character] = nil
				continue
			end
			local t = (clock - chewer.At) / CHOMP_TIME
			if t >= 1 then
				if chewer.Posed then
					chewer.Posed = false
					Pose.ReleaseAll(chewer.Rig)
				end
				continue
			end
			local dip = math.sin(t * math.pi)
			local neck, waist = chewer.Rig.Neck, chewer.Rig.Waist
			if neck then
				Pose.TurnOver(neck, CFrame.Angles(NECK_DIP * dip, 0, 0))
			end
			if waist then
				Pose.TurnOver(waist, CFrame.Angles(WAIST_DIP * dip, 0, 0))
			end
			chewer.Posed = true
		end
	end))
	api:Track(function()
		for _, chewer in chewers do
			Pose.ReleaseAll(chewer.Rig)
		end
		table.clear(chewers)
	end)

	-- A pepperoni the bites reached, flying off the pizza into its eater's mouth.
	local function flyPepperoni(from: Vector3, character: Model?)
		local size = 1.7 * radius / Logic.MESH_RADIUS
		local disc = UIKit.new("Part", {
			Name = "Pepperoni",
			Shape = Enum.PartType.Cylinder,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Material = Enum.Material.SmoothPlastic,
			Color = PEPPERONI,
			Size = Vector3.new(0.22, size, size),
			CFrame = CFrame.new(from) * CFrame.Angles(0, 0, math.rad(90)),
			Parent = api.World,
		})
		local start = os.clock()
		task.spawn(function()
			while disc.Parent do
				local t = math.min(1, (os.clock() - start) / 0.38)
				local goal = mouthOf(character) or (from + Vector3.new(0, 3, 0))
				local p = from:Lerp(goal, t) + Vector3.new(0, 3.2 * math.sin(t * math.pi), 0)
				local shrink = 1 - 0.7 * t
				disc.Size = Vector3.new(0.22, size * shrink, size * shrink)
				disc.CFrame = CFrame.new(p) * CFrame.Angles(t * 9, 0, math.rad(90))
				if t >= 1 then
					crumbsAt(goal, 8)
					disc:Destroy()
					break
				end
				task.wait()
			end
		end)
	end

	-- The hot pepper's fire on whoever has it.
	local function setAlight(character: Model?, seconds: number)
		local head = character and character:FindFirstChild("Head")
		if not head then
			return
		end
		local fire = Instance.new("Fire")
		fire.Name = "Spicy"
		fire.Color = SPICY
		fire.SecondaryColor = Color3.fromRGB(255, 220, 80)
		fire.Size = 4
		fire.Heat = 9
		fire.Parent = head
		api:Track(fire)
		Debris:AddItem(fire, seconds)
	end

	-- The spots' rings: a glowing disc on the cheese in the team's colour, a ring of segments round it
	-- that go out as its bites do, and over each of my team's a bobbing ▼ with its mark (colour is
	-- never the only cue). Kept in a pool: a spot that pops hands its parts to the next one.
	type SpotView = {
		Holder: Model,
		Disc: Part,
		Ring: { Part },
		Anchor: Part,
		Gui: BillboardGui,
		Mark: TextLabel,
		Arrow: TextLabel,
		Id: number,
		Team: string,
		Base: Vector3,
		Lit: number,
		BornAt: number,
	}
	local views: { [number]: SpotView } = {}
	local spare: { SpotView } = {}
	local function plainPart(props: { [string]: any }): Part
		props.Anchored = true
		props.CanCollide = false
		props.CanQuery = false
		props.CanTouch = false
		props.CastShadow = false
		return UIKit.new("Part", props) :: Part
	end
	local function newView(): SpotView
		local holder = UIKit.new("Model", { Name = "Spot", Parent = api.World }) :: Model
		local disc = plainPart({
			Name = "Disc",
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.Neon,
			Size = Vector3.new(0.12, Logic.SPOT_RADIUS * 2, Logic.SPOT_RADIUS * 2),
			Parent = holder,
		})
		local ring = {}
		local chord = 2 * Logic.SPOT_RADIUS * math.sin(math.pi / SEGMENTS) * 0.92
		for k = 1, SEGMENTS do
			ring[k] = plainPart({
				Name = `Ring{k}`,
				Material = Enum.Material.Neon,
				Size = Vector3.new(chord, 0.22, 0.38),
				Parent = holder,
			})
		end
		local anchor = plainPart({
			Name = "MarkerAnchor",
			Transparency = 1,
			Size = Vector3.new(0.2, 0.2, 0.2),
			Parent = holder,
		})
		local gui = UIKit.new("BillboardGui", {
			Name = "SpotMarker",
			Size = UDim2.fromOffset(60, 70),
			AlwaysOnTop = true,
			LightInfluence = 0,
			Enabled = false,
			Parent = anchor,
		}) :: BillboardGui
		local mark = UIKit.Label({
			Name = "Mark",
			Text = "",
			Font = Theme.Fonts.Display,
			TextSize = 24,
			TextWrapped = false,
			Size = UDim2.new(1, 0, 0, 26),
			Parent = gui,
			Children = { UIKit.TextStroke(0) },
		})
		local arrow = UIKit.Label({
			Name = "Arrow",
			Text = "▼",
			Font = Theme.Fonts.Display,
			TextSize = 40,
			TextWrapped = false,
			Position = UDim2.fromOffset(0, 24),
			Size = UDim2.new(1, 0, 0, 44),
			Parent = gui,
			Children = { UIKit.TextStroke(0) },
		})
		return {
			Holder = holder,
			Disc = disc,
			Ring = ring,
			Anchor = anchor,
			Gui = gui,
			Mark = mark,
			Arrow = arrow,
			Id = 0,
			Team = "",
			Base = Vector3.zero,
			Lit = -1,
			BornAt = 0,
		}
	end
	local function showView(view: SpotView, spot: SpotData)
		local color = Teams.Colors[spot.T] or Color3.new(1, 1, 1)
		local own = spot.T == mine
		local base = Vector3.new(center.X + spot.X, cheeseY + 0.08, center.Z + spot.Z)
		view.Id, view.Team, view.Base, view.Lit, view.BornAt = spot.I, spot.T, base, -1, os.clock()
		view.Disc.Color = color
		view.Disc.Transparency = if own then 0.4 else 0.62
		view.Disc.CFrame = CFrame.new(base) * CFrame.Angles(0, 0, math.pi / 2)
		local bright = color:Lerp(Color3.new(1, 1, 1), 0.35)
		for k, segment in view.Ring do
			local a = (k - 0.5) / SEGMENTS * math.pi * 2
			segment.Color = bright
			segment.CFrame = CFrame.new(base + Vector3.new(0, 0.04, 0))
				* CFrame.Angles(0, a, 0)
				* CFrame.new(0, 0, -(Logic.SPOT_RADIUS - 0.2))
		end
		view.Mark.Text = SHAPES[spot.T] or ""
		view.Mark.TextColor3 = color
		view.Arrow.TextColor3 = color
		view.Gui.Enabled = own and pizza.Ph ~= "Done"
		view.Anchor.CFrame = CFrame.new(base + Vector3.new(0, 4.5, 0))
		view.Holder.Parent = api.World
	end
	-- Lights a spot's ring segments for the bites it has left.
	local function litView(view: SpotView, left: number, max: number)
		local lit = if max > 0 then math.clamp(math.ceil(SEGMENTS * left / max - 1e-6), 0, SEGMENTS) else 0
		if lit == view.Lit then
			return
		end
		view.Lit = lit
		local own = view.Team == mine
		for k, segment in view.Ring do
			segment.Transparency = if k <= lit then (if own then 0 else 0.3) else 0.85
		end
	end
	local function hideView(view: SpotView)
		view.Gui.Enabled = false
		view.Holder.Parent = nil
		table.insert(spare, view)
	end
	local function popAt(spot: SpotData)
		local color = Teams.Colors[spot.T] or Color3.new(1, 1, 1)
		api:Effect("Sparkles", Vector3.new(center.X + spot.X, cheeseY + 1, center.Z + spot.Z), { color })
	end
	-- Draws the spots as shared: new ones get a view, eaten ones pop (unless my presses popped it
	-- already), the rest show their bites left.
	local function syncSpots(fresh: { SpotData })
		local seen = {}
		for _, spot in fresh do
			seen[spot.I] = true
			local view = views[spot.I]
			if not view then
				view = table.remove(spare) or newView()
				views[spot.I] = view
				showView(view, spot)
			end
			if predicted[spot.I] then
				predicted[spot.I] = math.min(predicted[spot.I], spot.L)
			end
			litView(view, leftAt(spot), spot.M)
		end
		for id, view in views do
			if not seen[id] then
				views[id] = nil
				local was = nil
				for _, spot in spots do
					if spot.I == id then
						was = spot
						break
					end
				end
				if was and pizza.Ph == "Eat" and not doneAt[id] then
					popAt(was)
				end
				hideView(view)
				predicted[id] = nil
				doneAt[id] = nil
			end
		end
		spots = fresh
	end
	syncSpots(spots)
	api:Track(function()
		for _, view in views do
			view.Holder:Destroy()
		end
		for _, view in spare do
			view.Holder:Destroy()
		end
	end)

	-- The marker over the spot to go to.
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
	-- My team's spot to go to: the nearest no teammate stands on (one they do counts a run further).
	local function nextSpot(): SpotData?
		local root = myRoot()
		if not root or not mine then
			return nil
		end
		local mates = {}
		for _, participant in api:Participants() do
			if participant.UserId ~= myId and participant:GetAttribute("PP_Team") == mine then
				local character = participant:Character()
				local mate = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if mate then
					table.insert(mates, mate.Position - center)
				end
			end
		end
		local best, bestCost = nil, math.huge
		for _, spot in mySpots() do
			local p = Vector3.new(center.X + spot.X, root.Position.Y, center.Z + spot.Z)
			local cost = (p - root.Position).Magnitude
			for _, offset in mates do
				if Logic.OnSpot(offset.X, offset.Z, { spot }) then
					cost += Logic.SPOT_RUN
					break
				end
			end
			if cost < bestCost then
				best, bestCost = spot, cost
			end
		end
		return best
	end

	-- Controls -------------------------------------------------------------------------------------
	local eat = nil
	local lastBite = -math.huge
	local deniedAt = -math.huge
	local deniedRival = false -- (that press was on another team's spot)
	local spotDoneAt = -math.huge -- (os.clock) I ate a spot up
	local spicyUntil = 0 -- (os.clock) my hot pepper's double bites
	local combo, comboAt, bitesSeen = 0, 0, 0
	-- (The server's bite rate, mirrored: presses over it don't land, so they don't chomp either.)
	local tokens, tokensAt = Logic.BURST, os.clock()
	local function spend(): boolean
		local clock = os.clock()
		tokens = math.min(Logic.BURST, tokens + (clock - tokensAt) * Logic.RATE)
		tokensAt = clock
		if tokens >= 1 then
			tokens -= 1
			return true
		end
		return false
	end
	if mine then
		eat = api:Button({ Text = "EAT", Key = Enum.KeyCode.E, Color = myColor })
		eat.Pressed:Connect(function()
			if pizza.Ph ~= "Eat" then
				return
			end
			api:Action("Eat")
			local now = api:Now()
			local spot = standingOn()
			if spot then
				if not spend() then
					return
				end
				lastBite = now
				local spicy = os.clock() < spicyUntil
				local bites = math.min(if spicy then Logic.SPICY_BITES else 1, leftAt(spot))
				api:Sound("Click", 0.85 + math.random() * 0.4)
				local character = api:Character()
				chomp(character)
				local mouth = mouthOf(character)
				if mouth then
					crumbsAt(mouth, if spicy then 10 else 6)
				end
				bitesSeen += 1
				if bitesSeen % 2 == 0 then
					Haptics.Play("Tap")
				end
				-- The combo: bites close together count up, and it carries on to the next spot if I run
				-- straight there; a pause starts it again.
				local clock = os.clock()
				if clock - comboAt > (if clock - spotDoneAt < RUN_GAP then RUN_GAP else COMBO_GAP) then
					combo = 0
				end
				local before = combo
				combo += bites
				comboAt = clock
				for at, cheer in CHEERS do
					if before < at and combo >= at then
						showCallout(`{cheer}  x{combo}`, Theme.Colors.Yellow, 1.2, 2)
						api:Sound("Boing", 1.2)
					end
				end
				if combo >= 5 then
					showCallout(`x{combo} COMBO`, if spicy then SPICY else Color3.new(1, 1, 1), COMBO_GAP, 0)
				end
				-- My spot, counted down here: eaten up, it pops at once.
				local left = leftAt(spot) - bites
				predicted[spot.I] = left
				local view = views[spot.I]
				if view then
					litView(view, left, spot.M)
				end
				if left <= 0 then
					doneAt[spot.I] = clock
					spotDoneAt = clock
					popAt(spot)
					if view then
						view.Gui.Enabled = false
						view.Holder.Parent = nil
					end
					api:Sound("Pickup", 1.15)
					Haptics.Play("Pulse")
				end
			else
				deniedAt = now
				deniedRival = false
				local root = myRoot()
				if root then
					local offset = root.Position - center
					local rivals = {}
					for _, other in spots do
						if other.T ~= mine then
							table.insert(rivals, other)
						end
					end
					deniedRival = Logic.OnSpot(offset.X, offset.Z, rivals) ~= nil
				end
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
	api:OnShared("Slices", function()
		local fresh = api:SharedJSON("Slices")
		if not fresh then
			return
		end
		slices = fresh
		refreshCards()
	end)
	-- Crumbs from whoever is chewing a spot that just lost bites (or was just eaten up).
	local lastCrumbs: { [number]: number } = {}
	local function chewersOf(spot: SpotData)
		local now = os.clock()
		if now - (lastCrumbs[spot.I] or 0) < 0.15 then
			return
		end
		lastCrumbs[spot.I] = now
		for _, participant in api:Participants() do
			if participant.UserId == myId or participant:GetAttribute("PP_Team") ~= spot.T then
				continue
			end
			local character = participant:Character()
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local offset = root and root.Position - center
			if offset and Logic.OnSpot(offset.X, offset.Z, { spot }) then
				local mouth = mouthOf(character)
				if mouth then
					crumbsAt(mouth, 4)
					chomp(character)
				end
			end
		end
	end
	api:OnShared("Spots", function()
		local fresh = readSpots()
		local before = {}
		for _, spot in spots do
			before[spot.I] = spot
		end
		local still = {}
		for _, spot in fresh do
			still[spot.I] = true
			local was = before[spot.I]
			if was and spot.L < was.L then
				chewersOf(spot)
			end
		end
		for id, spot in before do
			if not still[id] and pizza.Ph == "Eat" then
				chewersOf(spot)
			end
		end
		syncSpots(fresh)
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

	api:OnEvent("Pep", function(_index, _k, x, y, z, userId)
		if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
			return
		end
		local character = api:CharacterOf(userId)
		flyPepperoni(Vector3.new(x, y, z), character)
		if userId == myId then
			api:Sound("Hit", 1.25)
			showCallout("PEPPERONI!", Color3.fromRGB(255, 120, 100), 0.8, 1)
		end
	end)

	-- The hot pepper: where it is (turned and bobbed here) and how long it has left.
	local chiliInfo = api:SharedJSON("Chili") or {}
	local chiliModel: Model? = nil
	local chiliMarker = UIKit.new("Part", {
		Name = "ChiliMarker",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
		Size = Vector3.new(0.2, 0.2, 0.2),
		Parent = api.World,
	})
	local chiliGui = UIKit.new("BillboardGui", {
		Name = "HotPepper",
		Size = UDim2.fromOffset(170, 58),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Enabled = false,
		Parent = chiliMarker,
	})
	UIKit.Label({
		Text = "🌶️ HOT PEPPER!",
		Font = Theme.Fonts.Display,
		TextSize = 24,
		TextColor3 = SPICY,
		TextWrapped = false,
		Size = UDim2.new(1, 0, 0, 30),
		Parent = chiliGui,
		Children = { UIKit.TextStroke(0) },
	})
	local chiliBar = UIKit.new("Frame", {
		Name = "Time",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 36),
		Size = UDim2.fromOffset(110, 10),
		BackgroundColor3 = Color3.fromRGB(30, 16, 20),
		Parent = chiliGui,
		Children = { UIKit.Round() },
	})
	local chiliFill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = SPICY,
		Parent = chiliBar,
		Children = { UIKit.Round() },
	})
	local chiliArena: Instance? = nil
	task.spawn(function()
		chiliArena = api:Arena(10)
	end)
	api:OnShared("Chili", function()
		local fresh = api:SharedJSON("Chili") or {}
		local landed = fresh.P ~= nil and chiliInfo.P == nil
		chiliInfo = fresh
		chiliModel = nil
		if landed and mine and pizza.Ph == "Eat" then
			showCallout("🌶️ A HOT PEPPER! GRAB IT!", SPICY, 2.2, 3)
		end
	end)
	api:OnEvent("Spicy", function(userId, seconds)
		if type(seconds) ~= "number" then
			return
		end
		local character = api:CharacterOf(userId)
		setAlight(character, seconds)
		if userId == myId then
			spicyUntil = os.clock() + seconds
			Haptics.Play("Pulse")
			api:Sound("Pickup", 1.1)
			showCallout("🌶️ SPICY! DOUBLE BITES!", SPICY, 2, 4)
		else
			for _, participant in api:Participants() do
				if participant.UserId == userId then
					showCallout(`🌶️ {participant.DisplayName} got the hot pepper!`, SPICY, 1.6, 1)
					break
				end
			end
		end
	end)

	-- Every frame ---------------------------------------------------------------------------------
	api:RenderStep(function(_dt)
		local now = api:Now()
		local clock = os.clock()
		-- A spot my presses ate that the server still has after a moment: it wasn't (a press it
		-- didn't take), so it's back.
		for id, at in doneAt do
			if clock - at >= DONE_HOLD then
				doneAt[id] = nil
				predicted[id] = nil
			end
		end
		local on = standingOn()
		local playing = mine ~= nil and api:CanAct() and pizza.Ph == "Eat"
		if callout.Visible and clock >= calloutUntil then
			callout.Visible = false
		end

		-- The spots: a new one grows in, mine pulse and their ▼ bob (hidden over the one EAT HERE is on).
		local target = if playing and not on then nextSpot() else nil
		for id, view in views do
			local hidden = eatenHere(id) or pizza.Ph == "Done"
			local parent = if hidden then nil else api.World
			if view.Holder.Parent ~= parent then
				view.Holder.Parent = parent
			end
			if hidden then
				continue
			end
			local age = clock - view.BornAt
			if age < 0.3 then
				local grow = math.clamp(age / 0.3, 0.05, 1) * Logic.SPOT_RADIUS * 2
				view.Disc.Size = Vector3.new(0.12, grow, grow)
			elseif view.Disc.Size.Y < Logic.SPOT_RADIUS * 2 then
				view.Disc.Size = Vector3.new(0.12, Logic.SPOT_RADIUS * 2, Logic.SPOT_RADIUS * 2)
			end
			if view.Team == mine then
				-- (Over the countdown too, so I know where to run at GO.)
				view.Disc.Transparency = 0.42 + 0.14 * math.sin(clock * 6 + id)
				view.Gui.Enabled = not (target and target.I == id) and not (on and on.I == id)
				if view.Gui.Enabled then
					view.Anchor.CFrame = CFrame.new(view.Base + Vector3.new(0, 4.2 + math.sin(clock * 4 + id) * 0.5, 0))
				end
			end
		end

		-- The hot pepper turns and bobs where it floats, its timer running down over it.
		local chiliAt = chiliInfo.P
		if chiliAt and pizza.Ph == "Eat" then
			local base = Vector3.new(chiliAt[1], chiliAt[2], chiliAt[3])
			if not chiliModel or not chiliModel.Parent then
				local found = chiliArena and chiliArena:FindFirstChild("Chili")
				chiliModel = if found and found:IsA("Model") then found else nil
			end
			local model = chiliModel
			if model then
				model:PivotTo(
					CFrame.new(base + Vector3.new(0, math.sin(clock * 3) * 0.45, 0)) * CFrame.Angles(0, clock * 2.2, 0)
				)
			end
			chiliMarker.CFrame = CFrame.new(base + Vector3.new(0, 3.2, 0))
			chiliGui.Enabled = true
			local left = math.clamp(((chiliInfo.U or now) - now) / Logic.CHILI_LIFE, 0, 1)
			chiliFill.Size = UDim2.fromScale(left, 1)
		else
			chiliGui.Enabled = false
		end

		-- The status line: what my spot is up to, or where to go.
		if pizza.Ph == "Done" then
			local winner = pizza.W
			-- (On phones the round's own status line under the team pill already says it.)
			status.Text = if touch
				then ""
				elseif winner then `{SHAPES[winner] or ""} {string.upper(winner)} WINS!`
				else "TIME UP!"
			status.TextColor3 = if winner then Teams.Colors[winner] or Color3.new(1, 1, 1) else Color3.new(1, 1, 1)
		elseif not playing then
			status.Text = if mine then "" else "Watch them chow down!"
			status.TextColor3 = Color3.new(1, 1, 1)
		elseif on then
			local left = leftAt(on)
			local chomping = now - lastBite < 0.35
			local shape = if touch and mine then `{SHAPES[mine] or ""} ` else ""
			if clock < spicyUntil then
				status.Text = `🌶️ x2 BITES! {left} left · {math.ceil(spicyUntil - clock)}s`
				status.TextColor3 = SPICY
			else
				status.Text = if chomping then `{shape}CHOMP! {left} left` else `{shape}MASH EAT! {left} left`
				status.TextColor3 = if chomping then Theme.Colors.Yellow else Color3.new(1, 1, 1)
			end
		elseif clock - spotDoneAt < 1.2 then
			status.Text = "NOM! Next spot ▼ RUN!"
			status.TextColor3 = Theme.Colors.Yellow
		elseif now - deniedAt < 1.2 then
			status.Text = if deniedRival then "Not your spot! Run to ▼" else "Not on a spot! Run to ▼"
			status.TextColor3 = Theme.Colors.Red
		elseif teamShare(mine :: string) >= 1 then
			status.Text = "ALL EATEN!"
			status.TextColor3 = Color3.new(1, 1, 1)
		else
			status.Text = if target then "Run to a glowing spot ▼" else "A new spot is coming!"
			status.TextColor3 = Color3.new(1, 1, 1)
		end

		-- The button fills as my spot goes.
		if eat then
			eat:SetFill(if on and on.M > 0 then 1 - leftAt(on) / on.M else 0, Color3.new(1, 1, 1))
		end

		-- The marker over the spot to go to, while I'm not on one.
		markerGui.Enabled = target ~= nil
		if target then
			local spot = Vector3.new(center.X + target.X, cheeseY, center.Z + target.Z)
			marker.CFrame = CFrame.new(spot + Vector3.new(0, 6.5 + math.sin(now * 5) * 0.6, 0))
		end
	end)
end

return EatsaPizza
