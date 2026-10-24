-- Client half of Sinking Sands: turns the sand's swirl rings and draws every treasure riding the
-- swirl from the server's shared schedule (MG_Sand: the flow plus each treasure's radius, angle and
-- time), so they glide smoothly and match what the server judges. Drags this player's own character
-- with the sand while they stand on it (the server does the same for bots). Shows the player's
-- role, the sand's state (spin direction, PULL) and their haul; Sand Kings get SWIRL and PULL.
-- Grabs are predicted: a coin this player runs through pops at once and comes back if the server
-- says someone else got it first (or nobody did, within PENDING_TIME). The prediction is the
-- server's grab rule seen from here: within reach of the treasure as drawn or of its true spot,
-- swept between frames (the server sweeps the same paths, allowing for ping and the easing).
--
-- Phone pass (handoff: "Sinking Sands' Sand King hint wraps to two lines"): the role hints are
-- short enough for one line on the smallest phone, "👑 SAND KING: SWIRL & PULL!" and "💎 DIVER: grab
-- the treasure!" (the status line above them says the rest).
--
-- Owner, after playing it: "sand king needs to have more interaction, is boring" and "sand one more
-- valuable stuff near the bottom". A Sand King SAND BLASTs a spot by tapping it on the sand (a click
-- on PC, where a faint ring under the pointer shows where), or with BLAST (R) beside the jump
-- button, which blasts the Diver nearest the middle of their view. Kings stay at their thrones, so
-- their move stick is put away and the whole screen is theirs to tap; dragging still turns the view.
-- Everyone sees a blast's ring on the sand with a second ring closing in on it until it erupts, a
-- Diver standing in a new one is told to MOVE!, and a Diver it catches is BLASTED! (the King who
-- threw it sees HIT!). The King's hint is now how to blast ("👑 Tap the sand to BLAST it!"; SWIRL,
-- PULL and BLAST are on the buttons). The SUNKEN CHEST (+8) sits heavy on the slope near the bottom.
--
-- Your role all round, not just in the hint's first seconds (after "I couldnt tell what color I was
-- on prime cut."): a chip like Arrow Ambush's under the sand panel, "💎 DIVER" or "👑 SAND KING" in
-- the role's colours, with the hint and the flashes just under it, clear of the buttons beside
-- JUMP, the move stick and the menu column on every phone.
--
-- Bug sweep (owner: "Let's do a full bug and clean sweep."): a flash ("🌀 SWIRL! 🔄") kept its
-- 400-wide box on phones, and on the smallest one the box reached into the move stick's corner (the
-- phone checks: 15%). On phones a flash is now only as wide as its words, like the hints.
--
-- Kings stand (owner: "Also theres times where I will sit on invisible shit in game. NO mini game
-- should require you to sit."): a Sand King now stands at their throne instead of sitting on an
-- invisible Seat; on this side nothing changes but the words.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local GameState = require(ReplicatedStorage.Shared.GameState)
local SandSwirl = require(ReplicatedStorage.Shared.Logic.SandSwirl)
local Teams = require(ReplicatedStorage.Shared.Teams)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local SinkingSands = {}

-- Must match the server's kinds (index = kind number).
-- Mark is the landing marker's dot (the ring round it is always dark, so it reads on pale sand).
local KINDS = {
	{ Prop = "SandCoin", Value = 1, Factor = 1.5, Lift = 0.15, Reach = 2.7, Mark = Color3.fromRGB(255, 214, 60) },
	{ Prop = "SandGem", Value = 3, Factor = 1.4, Lift = 0.5, Reach = 2.6, Mark = Color3.fromRGB(70, 200, 255) },
	{ Prop = "CoinBag", Value = 5, Factor = 1.2, Lift = 0, Reach = 3.0, Mark = Color3.fromRGB(255, 170, 30) },
	{ Prop = "GoldenIdol", Value = 10, Factor = 0.95, Lift = 0, Reach = 2.7, Mark = Color3.fromRGB(255, 170, 30) },
	{ Prop = "SandChest", Value = 8, Factor = 0.03, Lift = 0, Reach = 2.9, Mark = Color3.fromRGB(255, 110, 60) },
}
local IDOL, CHEST = 4, 5 -- (the CHEST sits on the slope: no spin, no bob; a "+8" floats over it)
local GEM_COLOR = Color3.fromRGB(70, 200, 255) -- every gem is worth the same, so they all look alike
local MARK_RING = Color3.fromRGB(90, 55, 30)
local PENDING_TIME = 0.6 -- a predicted grab the server hasn't confirmed by then comes back
local ALARM_GAP = 2.5 -- Divers hear the sand's alarm at most this often
local FALL_TIME = 1.1
local FALL_HEIGHT = 26
local SWIRL_COOLDOWN, PULL_COOLDOWN, BLAST_COOLDOWN = 3, 5, 6 -- (only until the server says)
-- SAND BLAST rings: the server sends each one's size; this is for a King's own tap until its echo.
local BLAST_RING, BLAST_DELAY = 4.5, 0.75
local RING_BARS, FUSE_BARS = 28, 20 -- bars in a blast's ring and in the ring closing in on it
local BLAST_COLOR, FUSE_COLOR = Color3.fromRGB(255, 70, 50), Color3.fromRGB(255, 240, 200)
-- The HUD under the sand panel (TopHud units below api:HudY()): the role chip, then the hint's and
-- the flashes' line.
local CHIP_Y, CHIP_SIZE = 64, Vector2.new(240, 44)
local HINT_Y = CHIP_Y + CHIP_SIZE.Y + 8

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
	Rel: Vector2?, -- this player's middle relative to the treasure last frame (for the swept test)
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

-- Flat distance from the origin to the segment a-b (same test as the server's grab sweep).
local function segmentReach(a: Vector2, b: Vector2): number
	local d = b - a
	local length = d:Dot(d)
	local t = if length > 1e-9 then math.clamp(-a:Dot(d) / length, 0, 1) else 0
	return (a + d * t).Magnitude
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
		if kind ~= IDOL and not State.ReducedEffects() then
			-- Treasure twinkles in its own color, so it catches the eye on the pale sand.
			local primary = built.PrimaryPart or partsOf(built)[1]
			if primary then
				local twinkle = Instance.new("ParticleEmitter")
				twinkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
				twinkle.Color = ColorSequence.new(Color3.new(1, 1, 1):Lerp(KINDS[kind].Mark, 0.6))
				twinkle.Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(0.4, 0.45),
					NumberSequenceKeypoint.new(1, 0),
				})
				twinkle.Rate = if kind == 1 then 1.5 else 3
				twinkle.Lifetime = NumberRange.new(0.4, 0.7)
				twinkle.Speed = NumberRange.new(0.3, 0.8)
				twinkle.SpreadAngle = Vector2.new(180, 180)
				twinkle.LightEmission = 1
				twinkle.Parent = primary
				CollectionService:AddTag(twinkle, "PP_Ambient") -- the reduced-effects setting switches it
			end
		end
		if kind == 2 then
			for _, part in partsOf(built) do
				part.Color = GEM_COLOR
			end
		elseif kind == IDOL or kind == CHEST then
			local primary = built.PrimaryPart or partsOf(built)[1]
			if primary then
				local light = Instance.new("PointLight")
				light.Color = Color3.fromRGB(255, 210, 90)
				light.Range = 14
				light.Brightness = 2
				light.Parent = primary
				if kind == CHEST then
					-- What it's worth, over it (it lies down near the hole: worth the risk?).
					local tag = Instance.new("BillboardGui")
					tag.Name = "Worth"
					tag.Size = UDim2.fromOffset(80, 40)
					tag.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
					tag.MaxDistance = 150
					tag.Parent = primary
					UIKit.Label({
						Text = `+{KINDS[kind].Value}`,
						Font = Theme.Fonts.Display,
						TextSize = 30,
						TextColor3 = Theme.Colors.Coin,
						Size = UDim2.fromScale(1, 1),
						Parent = tag,
						Children = { UIKit.TextStroke(0.1) },
					})
				end
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

	-- The role chip (like Arrow Ambush's): "💎 DIVER" or "👑 SAND KING" in the role's colours, all
	-- round, centred under the panel (it shows once the server gives this player a role).
	local roleChip = UIKit.Panel({
		Name = "Role",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, api:HudY() + CHIP_Y),
		Size = UDim2.fromOffset(CHIP_SIZE.X, CHIP_SIZE.Y),
		Visible = false,
		Parent = hud,
	}, Teams.Colors.Divers, Teams.Colors.Divers)
	local roleText = UIKit.Label({
		Name = "Text",
		Text = "",
		Font = Theme.Fonts.Display,
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -20, 1, -12),
		Parent = roleChip,
		Children = { UIKit.TextStroke(0.2) },
	})
	local function showRole(king: boolean)
		local color = Teams.Colors[if king then "SandKings" else "Divers"] or Theme.Colors.Panel
		roleText.Text = if king then "👑 SAND KING" else "💎 DIVER"
		local gradient = roleChip:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Color = ColorSequence.new(color, color:Lerp(Color3.new(0, 0, 0), 0.4))
		end
		roleChip.Visible = true
	end

	-- The role hint: narrower than api:Hint so it clears the standings on small phones.
	local hint = UIKit.Label({
		Name = "RoleHint",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, api:HudY() + HINT_Y),
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
		Position = UDim2.new(0.5, 0, 0, api:HudY() + HINT_Y),
		Size = UDim2.fromOffset(400, 64),
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0.05) },
	})
	local flashUntil = 0
	local function showFlash(text: string, color: Color3, seconds: number)
		flash.Text = text
		if api:IsTouch() then
			-- (Phones: only as wide as the words, so it stays clear of the move stick's corner.)
			local width = math.ceil(UIKit.TextWidth(text, 54, Theme.Fonts.Display)) + 24
			flash.Size = UDim2.fromOffset(math.min(400, width), 64)
		end
		flash.TextColor3 = color
		flash.Visible = true
		flashUntil = os.clock() + seconds
		hint.Visible = false -- same spot: the flash takes over
		UIKit.PopIn(flash, 0.25)
	end

	-- SAND BLAST ----------------------------------------------------------------------------------

	-- A ring lying on the sand: a loop of short bars, each laid on the funnel's slope where it is.
	local function sandAt(x: number, z: number): Vector3
		local r = Vector2.new(x - center.X, z - center.Z).Magnitude
		return Vector3.new(x, center.Y + SandSwirl.Height(r) + 0.18, z)
	end
	local function newRing(count: number, color: Color3, width: number): { BasePart }
		local bars = {}
		for _ = 1, count do
			local bar = Instance.new("Part")
			bar.Name = "BlastRing"
			bar.Anchored = true
			bar.CanCollide = false
			bar.CanQuery = false
			bar.CanTouch = false
			bar.CastShadow = false
			bar.Material = Enum.Material.Neon
			bar.Color = color
			bar.Size = Vector3.new(width, 0.14, 1)
			bar.Parent = api.World
			table.insert(bars, bar)
		end
		return bars
	end
	local function placeRing(bars: { BasePart }, x: number, z: number, radius: number)
		local count = #bars
		local previous = sandAt(x + radius, z)
		for index, bar in bars do
			local angle = index / count * math.pi * 2
			local point = sandAt(x + math.cos(angle) * radius, z + math.sin(angle) * radius)
			local along = point - previous
			local mid = (point + previous) / 2
			local out = Vector3.new(mid.X - center.X, 0, mid.Z - center.Z)
			local r = out.Magnitude
			local slope = SandSwirl.Height(r + 0.25) - SandSwirl.Height(r - 0.25)
			local up = if r > 0.01
				then Vector3.new(-out.X / r * slope * 2, 1, -out.Z / r * slope * 2)
				else Vector3.yAxis
			if along.Magnitude > 1e-3 then
				bar.Size = Vector3.new(bar.Size.X, bar.Size.Y, along.Magnitude + 0.1)
				bar.CFrame = CFrame.lookAt(mid, point, up)
			end
			previous = point
		end
	end
	local function dropRing(bars: { BasePart }?)
		if bars then
			for _, bar in bars do
				bar:Destroy()
			end
		end
	end

	-- The blasts on their way: a ring where it will erupt and a second one closing in on it, so the
	-- moment it erupts reads without a number. Blasts[0] is this King's own tap, drawn at once until
	-- the server's ring for it arrives.
	type Blast = {
		X: number,
		Z: number,
		T: number,
		Start: number,
		Radius: number,
		Ring: { BasePart },
		Fuse: { BasePart },
		Born: number,
	}
	local blasts: { [number]: Blast } = {}
	local throwers: { [number]: number } = {} -- who threw each blast (for HIT! on their screen)
	local function addBlast(id: number, x: number, z: number, t: number, radius: number)
		local blast = blasts[id]
		if not blast then
			blast = {
				X = x,
				Z = z,
				T = t,
				Start = api:Now(),
				Radius = radius,
				Ring = newRing(RING_BARS, BLAST_COLOR, 0.5),
				Fuse = newRing(FUSE_BARS, FUSE_COLOR, 0.3),
				Born = os.clock(),
			}
			blasts[id] = blast
		end
		blast.X, blast.Z, blast.T, blast.Radius = x, z, t, radius
		placeRing(blast.Ring, x, z, radius)
	end
	local function removeBlast(id: number)
		local blast = blasts[id]
		if blast then
			blasts[id] = nil
			dropRing(blast.Ring)
			dropRing(blast.Fuse)
		end
	end
	api:Track(function()
		for id in blasts do
			removeBlast(id)
		end
	end)

	-- Where on the sand a ray from the camera lands (the funnel's own shape, so thrones and people
	-- in the way don't matter); nil for the sky or the far mesa.
	local function sandPoint(ray: Ray): Vector3?
		local origin, direction = ray.Origin, ray.Direction.Unit
		if direction.Y > -1e-3 then
			return nil -- (the King looks down on the funnel: this is the sky)
		end
		local function above(t: number): number
			local p = origin + direction * t
			return p.Y - center.Y - SandSwirl.Height(Vector2.new(p.X - center.X, p.Z - center.Z).Magnitude)
		end
		if above(0) <= 0 then
			return nil
		end
		local step = 1
		for t = step, 300, step do
			if above(t) <= 0 then
				local low, high = t - step, t
				for _ = 1, 14 do
					local middle = (low + high) / 2
					if above(middle) > 0 then
						low = middle
					else
						high = middle
					end
				end
				local hit = origin + direction * high
				local r = Vector2.new(hit.X - center.X, hit.Z - center.Z).Magnitude
				return if r <= SandSwirl.RIM + 3 then hit else nil
			end
		end
		return nil
	end

	-- The Diver nearest the middle of this King's view (for BLAST without aiming): someone on the sand.
	local function diverInView(): Vector3?
		local camera = workspace.CurrentCamera
		local eye, look = camera.CFrame.Position, camera.CFrame.LookVector
		local best, bestDot = nil, -math.huge
		for _, participant in api:Participants() do
			if participant.IsLocal or participant:GetAttribute("MG_Role") == "King" then
				continue
			end
			local character = participant:Character()
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then
				continue
			end
			local p = root.Position
			if
				Vector2.new(p.X - center.X, p.Z - center.Z).Magnitude > SandSwirl.RIM
				or p.Y < center.Y - SandSwirl.DEPTH - 2
			then
				continue -- off the sand, or down the hole
			end
			local dot = (p - eye).Unit:Dot(look)
			if dot > bestDot then
				best, bestDot = p, dot
			end
		end
		return best
	end

	-- A King's blast: at once on their own screen (the click, the ring, the empty button), the server
	-- judges it where they tapped.
	local blastReadyAt = 0 -- (predicted on a tap; the server's BlastAt arrives a moment later)
	local function blastReady(): boolean
		return math.max(api:Mine("BlastAt") or 0, blastReadyAt) <= api:Now()
	end
	local function blast(point: Vector3?)
		if not point or GameState.Get("Phase") ~= "InRound" or not api:Alive() then
			return
		end
		if not blastReady() then
			api:Sound("Countdown") -- (not back yet: the button is still filling)
			return
		end
		blastReadyAt = api:Now() + (api:Mine("BlastLength") or BLAST_COOLDOWN)
		api:Action("Blast", point.X, point.Z)
		api:Sound("Click")
		removeBlast(0)
		addBlast(0, point.X, point.Z, api:Now() + BLAST_DELAY, BLAST_RING)
	end
	local hover: { BasePart }? = nil -- PC: where a click would blast
	local aimingSet = false
	local function startAiming()
		if aimingSet then
			return
		end
		aimingSet = true
		-- Kings stay at their thrones: the move stick and jump button go away so a tap anywhere on the
		-- sand blasts it (dragging still turns the view), and come back when the round is over. (The
		-- UI checks then draw no stick or jump button either: tools/checks/ui_render.py.)
		api.Gui:SetAttribute("PP_NoTouchControls", if api:IsTouch() then true else nil)
		pcall(function()
			local scripts = api.Player:FindFirstChild("PlayerScripts")
			local module = scripts and scripts:FindFirstChild("PlayerModule")
			if module then
				local controls = (require(module :: any) :: any):GetControls()
				controls:Disable()
				api:Track(function()
					pcall(function()
						controls:Enable()
					end)
				end)
			end
		end)
		local camera = workspace.CurrentCamera
		api:Track(UserInputService.TouchTap:Connect(function(positions, processed)
			if not processed and positions[1] then
				blast(sandPoint(camera:ScreenPointToRay(positions[1].X, positions[1].Y)))
			end
		end))
		api:Track(UserInputService.InputBegan:Connect(function(input, processed)
			if not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
				blast(sandPoint(camera:ScreenPointToRay(input.Position.X, input.Position.Y)))
			end
		end))
		if not api:IsTouch() then
			hover = newRing(RING_BARS, Color3.new(1, 1, 1), 0.3)
			api:Track(function()
				dropRing(hover)
			end)
		end
	end
	-- BLAST (R): at the pointer on PC, else at the Diver nearest the middle of the view.
	local function blastButtonPressed()
		local point = nil
		if not api:IsTouch() then
			local mouse = UserInputService:GetMouseLocation()
			point = sandPoint(workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y))
		end
		blast(point or diverInView())
	end

	local hintUntil = 0
	local swirlButton, pullButton, blastButton = nil, nil, nil
	local function refreshRole()
		local role = api:Mine("Role")
		if role == nil then
			return
		end
		isKing = role == "King"
		refreshHaul()
		showRole(isKing)
		-- (short enough for one line in the hint's 400 points: the longer ones wrapped onto two on
		-- phones; the status line above says the rest, "Divers: grab the treasure! Sand Kings: sink it!",
		-- and a King's buttons say SWIRL, PULL and BLAST)
		if isKing then
			hint.Text = if api:IsTouch() then "👑 Tap the sand to BLAST it!" else "👑 Click the sand to BLAST it!"
		else
			hint.Text = "💎 DIVER: grab the treasure!"
		end
		hint.Visible = true
		hintUntil = math.huge -- counted from GO (below)
		if isKing and not swirlButton then
			startAiming()
			blastButton = api:Button({ Text = "BLAST", Key = Enum.KeyCode.R, Color = Theme.Colors.Red, Slot = 3 })
			blastButton.Pressed:Connect(blastButtonPressed)
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
	-- SAND BLAST: the ring (a King's own tap is already drawn: it becomes this one), the eruption,
	-- and who it caught.
	api:OnEvent("Blast", function(id: number, x: number, z: number, t: number, by: number, radius: number?)
		throwers[id] = by
		local mine = blasts[0]
		if by == api.Player.UserId and mine then
			blasts[0] = nil
			blasts[id] = mine
		end
		addBlast(id, x, z, t, radius or BLAST_RING)
		local _, _, root = api:Character()
		if not isKing and root and api:Alive() then
			local gap = Vector2.new(root.Position.X - x, root.Position.Z - z).Magnitude
			if gap < (radius or BLAST_RING) + 1.5 then
				showFlash("💥 MOVE!", Theme.Colors.Red, 0.6)
				api:Sound("HazardWarning")
			end
		end
	end)
	local sandBurst = { Color3.fromRGB(240, 204, 140), Color3.fromRGB(200, 150, 96) }
	api:OnEvent("Erupt", function(id: number)
		local blast = blasts[id]
		if not blast then
			return
		end
		removeBlast(id)
		-- A geyser of sand where it was.
		local anchor = Instance.new("Part")
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(blast.Radius * 1.4, 0.2, blast.Radius * 1.4)
		anchor.CFrame = CFrame.new(sandAt(blast.X, blast.Z))
		anchor.Parent = api.World
		local burst = Instance.new("ParticleEmitter")
		burst.Texture = "rbxasset://textures/particles/smoke_main.dds"
		burst.Color = ColorSequence.new(sandBurst[1], sandBurst[2])
		burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4.5) })
		burst.Transparency = NumberSequence.new(0.1, 1)
		burst.Lifetime = NumberRange.new(0.6, 1.1)
		burst.Speed = NumberRange.new(16, 28)
		burst.SpreadAngle = Vector2.new(22, 22)
		burst.Acceleration = Vector3.new(0, -40, 0)
		burst.EmissionDirection = Enum.NormalId.Top
		burst.Rate = 0
		burst.Parent = anchor
		burst:Emit(if State.ReducedEffects() then 8 else 26)
		task.delay(2, function()
			anchor:Destroy()
		end)
	end)
	api:OnEvent("BlastHit", function(id: number, userId: number, dropped: number)
		local root = rootOf(api, userId)
		if userId == api.Player.UserId then
			showFlash("💥 BLASTED!", Theme.Colors.Red, 1.2)
			api:Sound("Hit")
		elseif throwers[id] == api.Player.UserId and root then
			floatText(root.Position + Vector3.new(0, 2, 0), "💥 HIT!", Theme.Colors.Orange)
			api:Sound("Hit")
			return
		end
		if root and dropped > 0 then
			floatText(root.Position, `-{dropped}`, Theme.Colors.Red)
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
					local size = 1.6 + 1.8 * k + (if item.Kind == CHEST then 1.6 elseif item.Kind >= 3 then 0.8 else 0)
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
				if item.Kind == CHEST then
					-- Too heavy to bob: it lies on the slope, its front (and padlock) facing up it.
					local slope = SandSwirl.Height(r + 0.5) - SandSwirl.Height(r - 0.5)
					local x, z = SandSwirl.ToXZ(1, a)
					target = ground + Vector3.new(0, kind.Lift - sinking * 5, 0)
					turn = CFrame.lookAt(Vector3.zero, Vector3.new(x, slope, z), Vector3.new(-x * slope, 1, -z * slope))
				else
					-- Treasure bobs on the sand and slowly turns; it tips into the hole at the end.
					local bob = math.sin(now * 3 + item.Spin) * 0.12
					target = ground + Vector3.new(0, kind.Lift + bob - sinking * 5, 0)
					turn = CFrame.Angles(0, item.Spin + a + now * 1.4, 0)
						* CFrame.Angles(math.sin(now * 2 + item.Spin) * 0.12, 0, 0)
				end
			end
			local shown = item.Shown
			if shown and (shown - target).Magnitude < 6 then
				shown = shown:Lerp(target, 1 - math.exp(-dt * 18))
			else
				shown = target
			end
			item.Shown = shown
			item.Model:PivotTo(CFrame.new(shown :: Vector3) * turn)

			-- Ran through it (or it whipped through me): grab it now (the server confirms in a moment).
			if myRoot and now >= item.T and not sunk and not item.Predicted then
				local p = myRoot.Position
				local dy = p.Y - ground.Y
				local rel = Vector2.new(p.X - ground.X, p.Z - ground.Z)
				local drawnAt = shown :: Vector3
				local drawn = Vector2.new(p.X - drawnAt.X, p.Z - drawnAt.Z).Magnitude
				local before = item.Rel
				if not before or (before - rel).Magnitude > 8 then
					before = rel -- a hitch or a teleport: no sweep across it
				end
				local reach = math.min(segmentReach(before, rel), drawn)
				item.Rel = rel
				if reach < kind.Reach and dy > -2 and dy < 5.5 then -- (the server's inHeight)
					item.Pending = now
					item.PendingFrom = shown
					item.Predicted = true
					api:Sound("Pickup")
				end
			else
				item.Rel = nil
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
		if blastButton then
			local blastLeft = math.max(0, math.max(api:Mine("BlastAt") or 0, blastReadyAt) - now)
			blastButton:SetFill(1 - blastLeft / (api:Mine("BlastLength") or BLAST_COOLDOWN))
			blastButton:SetEnabled(blastLeft <= 0)
		end

		-- The blasts' rings, each with its fuse closing in until it erupts (one whose eruption never
		-- came goes a moment later, and a King's own tap if the server turned it away).
		for id, blast in blasts do
			if now > blast.T + 1 or (id == 0 and os.clock() - blast.Born > 1.5) then
				removeBlast(id)
				continue
			end
			local k = math.clamp((now - blast.Start) / math.max(0.05, blast.T - blast.Start), 0, 1)
			placeRing(blast.Fuse, blast.X, blast.Z, 0.4 + (blast.Radius - 0.4) * k)
			local pulse = 0.1 + 0.25 * (0.5 + 0.5 * math.sin(os.clock() * 20))
			for _, bar in blast.Ring do
				bar.Transparency = pulse
			end
		end
		-- PC Kings: a faint ring under the pointer, where a click would blast, while BLAST is ready.
		if hover then
			local point = nil
			if inRound and api:Alive() and blastReady() then
				local mouse = UserInputService:GetMouseLocation()
				point = sandPoint(workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y))
			end
			for _, bar in hover do
				bar.Transparency = if point then 0.55 else 1
			end
			if point then
				placeRing(hover, point.X, point.Z, BLAST_RING)
			end
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
