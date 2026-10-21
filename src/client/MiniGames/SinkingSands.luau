-- Client half of Sinking Sands: turns the sand's swirl rings and draws every treasure riding the
-- swirl from the server's shared schedule (MG_Sand: the flow plus each treasure's radius, angle and
-- time), so they glide smoothly and match what the server judges. Drags this player's own character
-- with the sand while they stand on it (the server does the same for bots). Shows the player's
-- role, the sand's state (spin direction, PULL) and their haul; Sand Kings get SWIRL and PULL.
-- Grabs are predicted: a coin this player runs through pops at once and comes back if the server
-- says someone else got it first (or nobody did, within PENDING_TIME).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameState = require(ReplicatedStorage.Shared.GameState)
local SandSwirl = require(ReplicatedStorage.Shared.Logic.SandSwirl)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local SinkingSands = {}

-- Must match the server's kinds (index = kind number).
-- Mark is the landing marker's dot (the ring round it is always dark, so it reads on pale sand).
local KINDS = {
	{ Prop = "SandCoin", Value = 1, Factor = 1.5, Lift = 0.15, Reach = 3.4, Mark = Color3.fromRGB(255, 214, 60) },
	{ Prop = "SandGem", Value = 3, Factor = 1.4, Lift = 0.5, Reach = 3.4, Mark = Color3.fromRGB(70, 200, 255) },
	{ Prop = "CoinBag", Value = 5, Factor = 1.2, Lift = 0, Reach = 3.7, Mark = Color3.fromRGB(255, 170, 30) },
	{ Prop = "GoldenIdol", Value = 10, Factor = 0.95, Lift = 0, Reach = 3.9, Mark = Color3.fromRGB(255, 170, 30) },
}
local GEM_COLOR = Color3.fromRGB(70, 200, 255) -- every gem is worth the same, so they all look alike
local MARK_RING = Color3.fromRGB(90, 55, 30)
local PENDING_TIME = 0.6 -- a predicted grab the server hasn't confirmed by then comes back
local ALARM_GAP = 2.5 -- Divers hear the sand's alarm at most this often
local FALL_TIME = 1.1
local FALL_HEIGHT = 26
local SWIRL_COOLDOWN, PULL_COOLDOWN = 3, 5

type Treasure = {
	Id: number,
	Kind: number,
	R: number,
	A: number,
	T: number,
	Model: Model,
	Marker: BasePart?,
	Dot: BasePart?,
	Shown: Vector3?,
	Pending: number?, -- when this player's device predicted grabbing it
	PendingFrom: Vector3?,
	Predicted: boolean?, -- the pickup sound already played
	Missing: boolean?, -- no longer in the server's list (while pending)
	Spin: number,
	Gone: string?, -- "Grab" | "Sink" | "Lost" once the server removed it
	GoneAt: number,
	GoneFrom: Vector3?,
	Taker: number?,
}

local function partsOf(model: Instance): { BasePart }
	local list = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(list, descendant)
		end
	end
	return list
end

local function rootOf(api, userId: number?): BasePart?
	local character = api:CharacterOf(userId)
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

function SinkingSands.Start(api)
	api:Mood({
		Tint = Color3.fromRGB(255, 240, 220),
		Saturation = 0.14,
		Contrast = 0.06,
		Brightness = 0.02,
		Haze = Color3.fromRGB(255, 214, 160),
		HazeDecay = Color3.fromRGB(230, 160, 100),
		Density = 0.3,
	})
	local arena = api:Arena()
	if not arena then
		return
	end
	local origin = arena:GetAttribute("Center")
	local center: Vector3 = if typeof(origin) == "Vector3" then origin else Vector3.new(0, 250, 1400)

	-- The flow, the treasure and the swirl rings ------------------------------------------------

	local segments: { SandSwirl.Segment } = {}
	local treasures: { [number]: Treasure } = {}
	local templates: { [string]: Instance | false } = {}

	-- The treasure models load in the background (during the countdown) so drawing never waits.
	for _, kind in KINDS do
		task.spawn(function()
			templates[kind.Prop] = api:Template(kind.Prop, 10) or false
		end)
	end
	local function template(name: string): Instance?
		local found = templates[name]
		return if found then found:Clone() else nil
	end

	local function newModel(kind: number): Model
		local model = template(KINDS[kind].Prop) :: Model?
		if not model then
			model = Instance.new("Model")
			local part = Instance.new("Part")
			part.Name = "Coin"
			part.Shape = Enum.PartType.Ball
			part.Size = Vector3.one * 1.6
			part.Color = Theme.Colors.Coin
			part.Material = Enum.Material.Metal
			part.Parent = model
		end
		local built = model :: Model
		for _, part in partsOf(built) do
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
		end
		if kind == 2 then
			for _, part in partsOf(built) do
				part.Color = GEM_COLOR
			end
		elseif kind == 4 then
			local primary = built.PrimaryPart or partsOf(built)[1]
			if primary then
				local light = Instance.new("PointLight")
				light.Color = Color3.fromRGB(255, 210, 90)
				light.Range = 14
				light.Brightness = 2
				light.Parent = primary
				if not State.ReducedEffects() then
					local sparkle = Instance.new("ParticleEmitter")
					sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
					sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
					sparkle.Size = NumberSequence.new(0.5, 0)
					sparkle.Rate = 8
					sparkle.Lifetime = NumberRange.new(0.6, 1)
					sparkle.Speed = NumberRange.new(1, 2)
					sparkle.SpreadAngle = Vector2.new(180, 180)
					sparkle.LightEmission = 1
					sparkle.Parent = primary
				end
			end
		end
		built.Parent = api.World
		return built
	end

	-- Landing marker: a dark shadow ring that grows as the treasure falls, with a bright dot in the
	-- treasure's color in the middle.
	local function disc(name: string, color: Color3, material: Enum.Material): BasePart
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(0.1, 1, 1)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = material
		part.Color = color
		part.Parent = api.World
		return part
	end
	local function newMarker(kind: number): (BasePart, BasePart)
		local ring = disc("Landing", MARK_RING, Enum.Material.SmoothPlastic)
		ring.Transparency = 0.3
		local dot = disc("LandingDot", KINDS[kind].Mark, Enum.Material.Neon)
		dot.Size = Vector3.new(0.1, 1.1, 1.1)
		return ring, dot
	end

	local function polar(item: Treasure, t: number): (number, number, number?)
		if t <= item.T then
			return item.R, item.A, nil
		end
		return SandSwirl.Advance(segments, item.R, item.A, item.T, t, KINDS[item.Kind].Factor, SandSwirl.TREASURE_DRAIN)
	end

	local function surface(r: number, a: number): Vector3
		local x, z = SandSwirl.ToXZ(r, a)
		return center + Vector3.new(x, SandSwirl.Height(r), z)
	end

	local function refresh()
		local sand = api:SharedJSON("Sand")
		if type(sand) ~= "table" then
			return
		end
		local flow = {}
		for _, entry in sand.F or {} do
			table.insert(flow, { T = entry[1], S = entry[2], V = entry[3] })
		end
		segments = flow
		local seen = {}
		for _, entry in sand.I or {} do
			local id = entry[1]
			seen[id] = true
			local item = treasures[id]
			if item then
				item.R, item.A, item.T = entry[3], entry[4], entry[5]
			elseif KINDS[entry[2]] then
				local kind = entry[2]
				local ring, dot = newMarker(kind)
				treasures[id] = {
					Id = id,
					Kind = kind,
					R = entry[3],
					A = entry[4],
					T = entry[5],
					Model = newModel(kind),
					Marker = ring,
					Dot = dot,
					Spin = math.random() * math.pi * 2,
					GoneAt = 0,
				}
			end
		end
		local now = api:Now()
		for id, item in treasures do
			if not seen[id] and not item.Gone then
				if item.Pending then
					item.Missing = true -- the Grab event says who got it (or it times out)
				else
					item.Gone = "Lost"
					item.GoneAt = now
					item.GoneFrom = item.Shown
				end
			end
		end
	end
	api:OnShared("Sand", refresh)
	refresh()

	-- The swirl rings: each turns with the sand at its middle radius.
	local rings = {}
	local swirl = arena:WaitForChild("SandSwirl", 10)
	if swirl then
		for _, part in partsOf(swirl) do
			local k = tonumber(string.match(part.Name, "^Swirl(%d)$"))
			local radius = if k
				then (SandSwirl.RINGS[k] + SandSwirl.RINGS[k + 1]) / 2
				elseif part.Name == "Whirl" then SandSwirl.HOLE * 0.7
				else nil
			if radius then
				table.insert(rings, {
					Part = part,
					Radius = radius,
					Angle = 0,
					Offset = CFrame.new(center):ToObjectSpace(part.CFrame),
				})
			end
		end
	end

	-- HUD ---------------------------------------------------------------------------------------

	local hud = api:TopHud()
	local isKing = false
	local panel = UIKit.Panel({
		Name = "Sand",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, api:HudY()),
		Size = UDim2.fromOffset(340, 58),
		CornerRadius = 20,
		Parent = hud,
	}, Color3.fromRGB(150, 96, 52), Color3.fromRGB(96, 56, 30))
	-- The spin: an arrow glyph that turns the way the sand does (sped up so it reads).
	local spinIcon = UIKit.Label({
		Name = "Spin",
		Text = "🔃",
		TextSize = 32,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 34, 0.5, 0),
		Size = UDim2.fromOffset(42, 42),
		Parent = panel,
	})
	local stateLabel = UIKit.Label({
		Name = "Flow",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(60, 0),
		Size = UDim2.new(0.62, -54, 1, 0),
		Parent = panel,
		Children = { UIKit.TextStroke(0.2) },
	})
	local haulLabel = UIKit.Label({
		Name = "Haul",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		TextColor3 = Theme.Colors.Coin,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 0),
		Size = UDim2.new(0.38, -10, 1, 0),
		Parent = panel,
		Children = { UIKit.TextStroke(0.2) },
	})
	local function refreshHaul()
		local score = api.Player:GetAttribute("PP_Score") or 0
		haulLabel.Text = `{if isKing then "👑" else "💎"} {score}`
	end
	api:Track(api.Player:GetAttributeChangedSignal("PP_Score"):Connect(refreshHaul))
	refreshHaul()

	-- The role hint: narrower than api:Hint so it clears the standings on small phones.
	local hint = UIKit.Label({
		Name = "RoleHint",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, api:HudY() + 66),
		Size = UDim2.fromOffset(400, 66),
		TextYAlignment = Enum.TextYAlignment.Top,
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0.2) },
	})

	-- Big flashes in the middle of the screen: "SWIRL!", "PULL!", "GULP!".
	local flash = UIKit.Label({
		Name = "Flash",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 54,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, api:HudY() + 66),
		Size = UDim2.fromOffset(400, 64),
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0.05) },
	})
	local flashUntil = 0
	local function showFlash(text: string, color: Color3, seconds: number)
		flash.Text = text
		flash.TextColor3 = color
		flash.Visible = true
		flashUntil = os.clock() + seconds
		hint.Visible = false -- same spot: the flash takes over
		UIKit.PopIn(flash, 0.25)
	end

	local hintUntil = 0
	local swirlButton, pullButton = nil, nil
	local function refreshRole()
		local role = api:Mine("Role")
		if role == nil then
			return
		end
		isKing = role == "King"
		refreshHaul()
		if isKing then
			hint.Text = "👑 SAND KING: SWIRL and PULL to sink the treasure!"
		else
			hint.Text = "💎 DIVER: grab the treasure! Stay out of the hole!"
		end
		hint.Visible = true
		hintUntil = math.huge -- counted from GO (below)
		if isKing and not swirlButton then
			local swirl = api:Button({ Text = "SWIRL", Key = Enum.KeyCode.E, Color = Theme.Colors.Orange })
			local pull = api:Button({ Text = "PULL", Key = Enum.KeyCode.Q, Color = Theme.Colors.Pink, Slot = 2 })
			-- Instant feedback for the King's own press (the server's echo is then ignored).
			local lastPress = { Swirl = 0, Pull = 0 }
			local function press(name: string, readyAt: string)
				local clock = os.clock()
				if (api:Mine(readyAt) or 0) <= api:Now() and clock - lastPress[name] > 0.5 then
					lastPress[name] = clock
					api:Sound("Click")
					if name == "Swirl" then
						showFlash("🌀 SWIRL!", Theme.Colors.Orange, 0.7)
					else
						showFlash("⏬ PULL! ⏬", Theme.Colors.Red, 1.2)
					end
				end
				api:Action(name)
			end
			swirl.Pressed:Connect(function()
				press("Swirl", "SwirlAt")
			end)
			pull.Pressed:Connect(function()
				press("Pull", "PullAt")
			end)
			swirlButton, pullButton = swirl, pull
		end
	end
	api:OnMine("Role", refreshRole)
	refreshRole()

	-- Events ------------------------------------------------------------------------------------

	local function floatText(position: Vector3, text: string, color: Color3)
		local anchor = Instance.new("Part")
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one * 0.2
		anchor.CFrame = CFrame.new(position)
		anchor.Parent = api.World
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(120, 50)
		gui.AlwaysOnTop = true
		gui.MaxDistance = 160
		gui.Parent = anchor
		UIKit.Label({
			Text = text,
			Font = Theme.Fonts.Display,
			TextSize = 34,
			TextColor3 = color,
			Size = UDim2.fromScale(1, 1),
			Parent = gui,
			Children = { UIKit.TextStroke(0.1) },
		})
		local start = os.clock()
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local t = os.clock() - start
			if t > 1 or not anchor.Parent then
				connection:Disconnect()
				anchor:Destroy()
				return
			end
			anchor.CFrame = CFrame.new(position + Vector3.new(0, 2 + t * 4, 0))
		end)
		api:Track(connection)
	end

	local function unpend(item: Treasure)
		if item.Pending then
			item.Pending = nil
			item.Model.Parent = api.World
			item.Model:ScaleTo(1)
		end
	end

	api:OnEvent("Grab", function(id: number, userId: number, value: number)
		local item = treasures[id]
		local now = api:Now()
		local mine = userId == api.Player.UserId
		local where = if item then item.PendingFrom or item.Shown else nil
		if item then
			if mine and item.Pending then
				-- Predicted right: the fly-to-me animation simply carries on.
				item.Gone = "Grab"
				item.GoneAt = item.Pending
				item.GoneFrom = item.PendingFrom
				item.Pending = nil
			else
				unpend(item)
				item.Gone = "Grab"
				item.GoneAt = now
				item.GoneFrom = item.Shown
			end
			item.Taker = userId
		end
		if where then
			floatText(where, `+{value}`, Theme.Colors.Coin)
			api:Effect("Sparkles", where, { Theme.Colors.Coin, Color3.new(1, 1, 1) })
		end
		if mine and not (item and item.Predicted) then
			api:Sound("Pickup")
		end
	end)
	api:OnEvent("Sink", function(id: number, value: number)
		local item = treasures[id]
		if item and item.Gone ~= "Grab" then
			unpend(item)
			item.Gone = "Sink"
			item.GoneAt = api:Now()
			item.GoneFrom = item.Shown
		end
		if isKing then
			floatText(center - Vector3.new(0, SandSwirl.DEPTH - 2, 0), `+{value}`, Theme.Colors.Orange)
		end
	end)
	api:OnEvent("Gulp", function(userId: number)
		local root = rootOf(api, userId)
		api:Effect("Poof", center - Vector3.new(0, SandSwirl.DEPTH, 0))
		if userId == api.Player.UserId then
			showFlash("GULP! 😵", Theme.Colors.Orange, 1.6)
			api:Sound("Splash")
		elseif root then
			api:Sound("Splash")
		end
	end)
	-- Divers get the alarm only when it matters (a PULL, or the spin reversing), and not too often;
	-- the panel shows every SWIRL anyway. Kings see their own presses (flashed when pressed).
	local lastAlarm = -math.huge
	api:OnEvent("Power", function(kind: string, _start: number, userId: number, flipped: boolean)
		if not isKing and (kind == "PULL" or flipped) and os.clock() - lastAlarm >= ALARM_GAP then
			lastAlarm = os.clock()
			if kind == "SWIRL" then
				showFlash("🌀 SWIRL! 🔄", Theme.Colors.Orange, 0.7)
			else
				showFlash("⏬ PULL! ⏬", Theme.Colors.Red, 1.2)
			end
			api:Sound("HazardWarning")
		end
		local root = rootOf(api, userId)
		if root then
			api:Effect("Poof", root.Position + Vector3.new(0, 3, 0))
		end
	end)

	-- Dragging this player's character with the sand (Heartbeat: after the humanoid moved) ----------

	api:Track(RunService.Heartbeat:Connect(function(dt)
		if isKing or not api:Alive() or #segments == 0 or GameState.Get("Phase") ~= "InRound" then
			return
		end
		local _, humanoid, root = api:Character()
		if not humanoid or not root then
			return
		end
		-- Hopping only softens the drag (the server drags bots the same way).
		local k = if humanoid.FloorMaterial == Enum.Material.Air then SandSwirl.AIR_DRAG else 1
		local position = root.Position
		if position.Y < center.Y - SandSwirl.DEPTH - 2 then
			return -- down the sinkhole, waiting to come back
		end
		local offset = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
		local r = offset.Magnitude
		if r < 0.05 or r > SandSwirl.RIM + SandSwirl.EDGE then
			return
		end
		local inward, spin = SandSwirl.WalkerFlow(segments, r, api:Now())
		local u = offset / r
		local move = (-u * inward + Vector3.new(-u.Z, 0, u.X) * spin) * math.min(dt, 0.1) * k
		root.CFrame += move
	end))

	-- Every frame: rings, treasure, HUD ---------------------------------------------------------------

	local baseDrain = SandSwirl.DRAIN[2] + 1.5
	api:RenderStep(function(dt)
		local now = api:Now()
		local s, v = SandSwirl.FlowAt(segments, now)

		for _, ring in rings do
			ring.Angle += s / ring.Radius * dt
			ring.Part.CFrame = CFrame.new(center) * CFrame.Angles(0, -ring.Angle, 0) * ring.Offset
		end

		local inRound = GameState.Get("Phase") == "InRound"
		local myRoot = if not isKing and inRound and api:Alive() then rootOf(api, api.Player.UserId) else nil
		for id, item in treasures do
			local kind = KINDS[item.Kind]
			if item.Pending and not item.Gone then
				-- Predicted grab: fly to me and vanish, or come back if the server disagrees.
				local t = now - item.Pending
				if t > PENDING_TIME then
					if item.Missing then
						item.Gone = "Lost"
						item.GoneAt = now
						item.GoneFrom = item.PendingFrom
					end
					unpend(item)
				else
					local from = item.PendingFrom :: Vector3
					local to = if myRoot then myRoot.Position + Vector3.new(0, 1.5, 0) else from + Vector3.new(0, 4, 0)
					local k = math.clamp(t / 0.3, 0, 1)
					if k >= 1 then
						item.Model.Parent = nil
					else
						item.Model:PivotTo(
							CFrame.new(from:Lerp(to, k) + Vector3.new(0, math.sin(k * math.pi) * 2.5, 0))
								* CFrame.Angles(0, item.Spin + t * 20, 0)
						)
						item.Model:ScaleTo(math.max(0.1, 1 - k * 0.8))
					end
					continue
				end
			end
			if item.Gone then
				local t = now - item.GoneAt
				local from = item.GoneFrom or surface(item.R, item.A)
				if item.Gone == "Grab" then
					local root = rootOf(api, item.Taker)
					local to = if root then root.Position + Vector3.new(0, 1.5, 0) else from + Vector3.new(0, 4, 0)
					local k = math.clamp(t / 0.3, 0, 1)
					local scale = 1 - k * 0.8
					item.Model:PivotTo(
						CFrame.new(from:Lerp(to, k) + Vector3.new(0, math.sin(k * math.pi) * 2.5, 0))
							* CFrame.Angles(0, item.Spin + t * 20, 0)
					)
					item.Model:ScaleTo(math.max(0.1, scale))
					if k >= 1 then
						item.Model:Destroy()
						treasures[id] = nil
					end
				else
					-- Swallowed: down the throat, spinning, and gone.
					local k = math.clamp(t / 0.7, 0, 1)
					local hole = center - Vector3.new(0, SandSwirl.DEPTH, 0)
					local start = if item.Gone == "Sink" then from:Lerp(hole, 0.6) else from
					item.Model:PivotTo(
						CFrame.new(start:Lerp(hole - Vector3.new(0, 6, 0), k)) * CFrame.Angles(0, item.Spin + t * 12, k)
					)
					if k >= 1 then
						item.Model:Destroy()
						treasures[id] = nil
					end
				end
				if item.Marker then
					item.Marker:Destroy()
					item.Marker = nil
				end
				if item.Dot then
					item.Dot:Destroy()
					item.Dot = nil
				end
				continue
			end
			local r, a, sunk = polar(item, now)
			local ground = surface(r, a)
			local target: Vector3
			local turn: CFrame
			if now < item.T then
				-- Falling from the sky onto its landing spot (marked on the sand).
				local k = math.clamp(1 - (item.T - now) / FALL_TIME, 0, 1)
				target = ground + Vector3.new(0, FALL_HEIGHT * (1 - k * k) + kind.Lift, 0)
				turn = CFrame.Angles(0, item.Spin + now * 6, 0)
				if item.Marker and item.Dot then
					-- Lying on the slope (tilted to the funnel), the ring growing like a falling shadow.
					local slope = SandSwirl.Height(r + 0.5) - SandSwirl.Height(r - 0.5)
					local x, z = SandSwirl.ToXZ(1, a)
					local flatOn = CFrame.lookAt(ground, ground + Vector3.new(x, 0, z))
						* CFrame.Angles(math.atan(slope), 0, 0)
						* CFrame.Angles(0, 0, math.rad(90))
					local size = 1.6 + 1.8 * k + (if item.Kind >= 3 then 0.8 else 0)
					item.Marker.Size = Vector3.new(0.06, size, size)
					item.Marker.CFrame = flatOn * CFrame.new(0.08, 0, 0)
					item.Dot.CFrame = flatOn * CFrame.new(0.2, 0, 0) -- clear of the ring (no flicker)
				end
			else
				if item.Marker then
					item.Marker:Destroy()
					item.Marker = nil
				end
				if item.Dot then
					item.Dot:Destroy()
					item.Dot = nil
				end
				local sinking = if sunk then math.clamp((now - sunk) / 0.6, 0, 1) else 0
				-- Treasure bobs on the sand and slowly turns; it tips into the hole at the end.
				local bob = math.sin(now * 3 + item.Spin) * 0.12
				target = ground + Vector3.new(0, kind.Lift + bob - sinking * 5, 0)
				turn = CFrame.Angles(0, item.Spin + a + now * 1.4, 0)
					* CFrame.Angles(math.sin(now * 2 + item.Spin) * 0.12, 0, 0)
			end
			local shown = item.Shown
			if shown and (shown - target).Magnitude < 6 then
				shown = shown:Lerp(target, 1 - math.exp(-dt * 18))
			else
				shown = target
			end
			item.Shown = shown
			item.Model:PivotTo(CFrame.new(shown :: Vector3) * turn)

			-- Ran through it: grab it now (the server confirms within a moment).
			if myRoot and now >= item.T and not sunk and not item.Predicted then
				local p = myRoot.Position
				local dy = p.Y - ground.Y
				if Vector2.new(p.X - ground.X, p.Z - ground.Z).Magnitude < kind.Reach and dy > -2 and dy < 7.5 then
					item.Pending = now
					item.PendingFrom = shown
					item.Predicted = true
					api:Sound("Pickup")
				end
			end
		end

		-- The sand's state: the arrow turns with the spin (seen from above, a positive spin turns
		-- clockwise), and the words say SWIRL! / PULL! / CALM.
		local pulling = v > baseDrain
		spinIcon.Text = if s >= 0 then "🔃" else "🔄"
		spinIcon.Rotation = (spinIcon.Rotation + math.deg(s / 6) * dt) % 360
		if pulling then
			stateLabel.Text = "PULL!"
			stateLabel.TextColor3 = Theme.Colors.Red
		elseif math.abs(s) > SandSwirl.SPIN[2] + 2 then
			stateLabel.Text = "SWIRL!"
			stateLabel.TextColor3 = Theme.Colors.Orange
		else
			stateLabel.Text = "CALM"
			stateLabel.TextColor3 = Theme.Colors.Text
		end

		-- The role hint stays through the countdown and 6 seconds into the round.
		if hintUntil == math.huge and GameState.Get("Phase") == "InRound" then
			hintUntil = os.clock() + 6
		end
		if hintUntil > 0 and os.clock() > hintUntil then
			hintUntil = 0
			hint.Visible = false
		end
		if flash.Visible and os.clock() > flashUntil then
			flash.Visible = false
		end

		if swirlButton and pullButton then
			local swirlAt = api:Mine("SwirlAt") or 0
			local pullAt = api:Mine("PullAt") or 0
			local swirlLeft = math.max(0, swirlAt - now)
			local pullLeft = math.max(0, pullAt - now)
			swirlButton:SetFill(1 - swirlLeft / (api:Mine("SwirlLength") or SWIRL_COOLDOWN))
			pullButton:SetFill(1 - pullLeft / (api:Mine("PullLength") or PULL_COOLDOWN))
			swirlButton:SetEnabled(swirlLeft <= 0)
			pullButton:SetEnabled(pullLeft <= 0)
		end
	end)

	api:Track(function()
		for _, item in treasures do
			item.Model:Destroy()
			if item.Marker then
				item.Marker:Destroy()
			end
			if item.Dot then
				item.Dot:Destroy()
			end
		end
	end)
end

return SinkingSands
