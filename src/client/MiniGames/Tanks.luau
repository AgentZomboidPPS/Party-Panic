-- Client half of Tanks!: every toy tank rolling round the play room with its driver standing in the
-- hatch, shells flying and ricocheting, mines blinking, toy explosions, the follow camera, the
-- controls (drive, aim, FIRE, LAY MINE) and the HUD.
--
-- The server owns every tank (Shared/Logic/TankField has the shared rules). This screen:
--   * drives this player's own tank the moment they steer, with the same driving code, and sends
--     each change of stick or aim ("In", numbered). Each shared snapshot ("Tanks") says which input
--     the server last applied and when it arrived, so the screen compares the server's tank with its
--     own at the matching moment and folds any difference in smoothly (no rubber-banding);
--   * glides everyone else's tank on from the snapshot's speed and turn rate between snapshots;
--   * draws each shell from its "Shot" alone: the flight (straight, one reflection, gone at the next
--     wall) is the same TankField.Path the server judges with, timed on the shared clock. Your own
--     shot leaves your barrel the moment you press FIRE and takes the server's flight when it comes
--     back ("Dud": the server said no, it vanishes);
--   * aims at the mouse (a dotted line shows the flight, ricochet included), at the right
--     thumbstick on a gamepad, or on phones where you drag on the right of the screen; on phones
--     the turret also swings to the nearest enemy in front of you whenever you're not dragging.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local TankField = require(ReplicatedStorage.Shared.Logic.TankField)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local Tanks = {}

local SPEED = TankField.SHELL_SPEED
local SEAT_Y = 4.15 -- a driver's root above the floor (the server's too)
local CAMERA_HEIGHT = 60
local CAMERA_BACK = 33
local TURRET_PIECES = { Turret = true, Barrel = true, Hatch = true, Badge = true }
local AIM_DOTS = 34
local HIDDEN = CFrame.new(0, -1e4, 0)

local function moveControls(): any
	local ok, controls = pcall(function()
		local playerScripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
		local module = playerScripts and playerScripts:FindFirstChild("PlayerModule")
		if not module then
			return nil
		end
		return (require(module) :: any):GetControls()
	end)
	return if ok then controls else nil
end

local function lerpAngle(a: number, b: number, t: number): number
	return a + TankField.Wrap(b - a) * t
end

local function round(x: number, step: number): number
	return math.floor(x / step + 0.5) * step
end

local function decor(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		if key ~= "Parent" then
			(part :: any)[key] = value
		end
	end
	part.Parent = props.Parent
	return part
end

type Visual = {
	Id: number,
	Slot: number,
	Model: Model?,
	Hull: { BasePart },
	HullOff: { CFrame },
	Turret: { BasePart },
	TurretOff: { CFrame },
	Axis: CFrame,
	X: number,
	Z: number,
	H: number,
	Aim: number,
	VX: number,
	VZ: number,
	Recoil: number,
	Seen: number, -- last snapshot that had it
	Out: boolean,
	OutAt: number,
	Character: Model?,
	PopFrom: CFrame?,
	Debris: { { any } }?,
	Plate: BillboardGui?,
	Bubble: BasePart?,
}

type ShellVisual = {
	Id: number?,
	Token: number?,
	Owner: number,
	T0: number,
	Path: TankField.Path,
	Part: BasePart?,
	Bounced: boolean,
	OffX: number,
	OffZ: number,
	Born: number,
	Done: boolean,
}

type MineVisual = {
	Owner: number,
	X: number,
	Z: number,
	ArmAt: number,
	BlowAt: number,
	Model: Model?,
	Light: BasePart?,
	Ring: BasePart?,
}

function Tanks.Start(api)
	api:Mood({
		Tint = Color3.fromRGB(255, 246, 232),
		Saturation = 0.14,
		Contrast = 0.05,
		Brightness = 0.02,
	})

	local localPlayer = Players.LocalPlayer
	local myId = localPlayer.UserId
	local camera = workspace.CurrentCamera
	local touch = api:IsTouch()
	local reduced = State.ReducedEffects()
	local controls = moveControls()

	local field: TankField.Field? = nil
	local origin = Vector3.zero
	local slots: { [number]: number } = {}
	local goAt = math.huge
	local snapshot: { t: number, k: { [string]: { number } } } = { t = 0, k = {} }

	local visuals: { [number]: Visual } = {}
	local shells: { ShellVisual } = {}
	local mines: { [number]: MineVisual } = {}
	local marks = Instance.new("Folder")
	marks.Name = "Marks"
	marks.Parent = api.World

	-- Templates arrive with the round (ctx:ShareTemplate); until then nothing is drawn.
	local templates: { [string]: Instance } = {}
	task.spawn(function()
		for _, name in { "TanksTank", "TanksShell", "TanksMine" } do
			local template = api:Template(name, 10)
			if template then
				templates[name] = template
			end
		end
	end)

	local function readField()
		local value = api:SharedJSON("Field")
		if field or type(value) ~= "table" or type(value.o) ~= "table" then
			return
		end
		field = TankField.Build(if value.m == "L" then "L" else "S")
		origin = Vector3.new(value.o[1], value.o[2], value.o[3])
		for _, entry in value.k or {} do
			slots[entry[1]] = entry[2]
		end
	end
	readField()
	api:OnShared("Field", readField)
	local function readGo()
		local value = api:Shared("GoAt")
		goAt = if type(value) == "number" then value else math.huge
	end
	readGo()
	api:OnShared("GoAt", readGo)

	local function aliveCount(): number
		local value = api:Shared("Alive")
		return if type(value) == "number" then value else 12
	end

	local function world(x: number, y: number, z: number): Vector3
		return origin + Vector3.new(x, y, z)
	end

	local function nameOf(userId: number): string
		for _, participant in api:Participants() do
			if participant.UserId == userId then
				return participant.DisplayName
			end
		end
		return "?"
	end

	local function colorOf(userId: number): Color3
		return TankField.COLORS[slots[userId] or 1] or Theme.Colors.Pink
	end

	-- Tanks ------------------------------------------------------------------------------------------

	local function makeTank(userId: number): Visual?
		local template = templates.TanksTank
		if not template then
			return nil
		end
		local model = template:Clone() :: Model
		local color = colorOf(userId)
		local pivot = model:GetPivot()
		local turretPart = model:FindFirstChild("Turret") :: BasePart?
		-- The hull's center: the middle of everything that isn't the turret (the barrel sticks out).
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and not TURRET_PIECES[part.Name] then
				local cf, size = part.CFrame, part.Size
				local ex = math.abs(cf.RightVector.X) * size.X
					+ math.abs(cf.UpVector.X) * size.Y
					+ math.abs(cf.LookVector.X) * size.Z
				local ez = math.abs(cf.RightVector.Z) * size.X
					+ math.abs(cf.UpVector.Z) * size.Y
					+ math.abs(cf.LookVector.Z) * size.Z
				minX, maxX = math.min(minX, cf.X - ex / 2), math.max(maxX, cf.X + ex / 2)
				minZ, maxZ = math.min(minZ, cf.Z - ez / 2), math.max(maxZ, cf.Z + ez / 2)
			end
		end
		local center = if minX < math.huge then Vector3.new((minX + maxX) / 2, 0, (minZ + maxZ) / 2) else pivot.Position
		local base = CFrame.new(center.X, pivot.Y, center.Z)
		local axisAt = if turretPart then turretPart.Position else center
		local axis = CFrame.new(axisAt.X, pivot.Y, axisAt.Z)
		local visual: Visual = {
			Id = userId,
			Slot = slots[userId] or 1,
			Model = model,
			Hull = {},
			HullOff = {},
			Turret = {},
			TurretOff = {},
			Axis = base:ToObjectSpace(axis),
			X = 0,
			Z = 0,
			H = 0,
			Aim = 0,
			VX = 0,
			VZ = 0,
			Recoil = 0,
			Seen = 0,
			Out = false,
			OutAt = 0,
		}
		for _, part in model:GetDescendants() do
			if not part:IsA("BasePart") then
				continue
			end
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			if part.Name == "Body" or part.Name == "Turret" then
				part.Color = color
			end
			if TURRET_PIECES[part.Name] then
				table.insert(visual.Turret, part)
				table.insert(visual.TurretOff, axis:ToObjectSpace(part.CFrame))
			else
				table.insert(visual.Hull, part)
				table.insert(visual.HullOff, base:ToObjectSpace(part.CFrame))
			end
		end
		-- The spawn shield: a bubble round the tank until it wears off (TankField.SHIELD after GO).
		visual.Bubble = decor({
			Name = "Bubble",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 10.5,
			Color = Color3.fromRGB(150, 220, 255),
			Material = Enum.Material.ForceField,
			Transparency = 0.2,
			CFrame = HIDDEN,
			Parent = model,
		})
		model.Parent = api.World
		-- Whose tank: the driver's name over it in the tank's colour ("YOU" for your own).
		local anchor = turretPart or model.PrimaryPart
		if anchor then
			local plate = Instance.new("BillboardGui")
			plate.Name = "Plate"
			plate.Adornee = anchor
			plate.Size = UDim2.fromOffset(if userId == myId then 90 else 170, 34)
			plate.StudsOffsetWorldSpace = Vector3.new(0, 7.2, 0)
			plate.MaxDistance = 220
			plate.LightInfluence = 0
			plate.Parent = model
			UIKit.Label({
				Text = if userId == myId then "YOU ▼" else nameOf(userId),
				Font = Theme.Fonts.Display,
				TextSize = 24,
				TextColor3 = if userId == myId then Theme.Colors.Yellow else color:Lerp(Color3.new(1, 1, 1), 0.35),
				Size = UDim2.fromScale(1, 1),
				Parent = plate,
				Children = { UIKit.TextStroke(0) },
			})
			visual.Plate = plate
		end
		return visual
	end

	local function placeTank(visual: Visual)
		local hull = CFrame.new(world(visual.X, 0, visual.Z)) * CFrame.Angles(0, visual.H, 0)
		for index, part in visual.Hull do
			part.CFrame = hull * visual.HullOff[index]
		end
		local axis = CFrame.new((hull * visual.Axis).Position) * CFrame.Angles(0, visual.Aim, 0)
		local bubble = visual.Bubble
		if bubble then
			bubble.CFrame = if api:Now() < goAt + TankField.SHIELD then hull + Vector3.new(0, 2.6, 0) else HIDDEN
		end
		local kick = if visual.Recoil > 0 then CFrame.new(0, 0, visual.Recoil * 0.5) else CFrame.identity
		for index, part in visual.Turret do
			local offset = visual.TurretOff[index]
			part.CFrame = axis * (if part.Name == "Barrel" then kick * offset else offset)
		end
	end

	-- The turret's frame (where the driver stands and shells leave from), at floor level.
	local function turretFrame(visual: Visual): CFrame
		local hull = CFrame.new(world(visual.X, 0, visual.Z)) * CFrame.Angles(0, visual.H, 0)
		return CFrame.new((hull * visual.Axis).Position) * CFrame.Angles(0, visual.Aim, 0)
	end

	-- My own tank: predicted here, corrected toward the server's ------------------------------------

	local me = { X = 0, Z = 0, H = 0, V = 0, Rev = false }
	local meReady = false
	local offX, offZ, offH = 0, 0, 0 -- display offset that eases a correction in
	local history: { { number } } = {} -- { t, x, z, h, v }
	local sentAt: { [number]: number } = {}
	local seq = 0
	local sentMX, sentMZ, sentAim = 0, 0, 0
	local lastSend = -math.huge
	local aim = 0

	local function myVisual(): Visual?
		return visuals[myId]
	end

	local function canDrive(): boolean
		local mine = myVisual()
		return field ~= nil and meReady and mine ~= nil and not mine.Out and api:CanAct() and api:Now() >= goAt
	end

	local function stateAt(t: number): { number }?
		local count = #history
		if count == 0 then
			return nil
		end
		if t <= history[1][1] then
			return history[1]
		end
		for index = count, 1, -1 do
			local a = history[index]
			if a[1] <= t then
				local b = history[index + 1]
				if not b then
					return a
				end
				local u = (t - a[1]) / math.max(b[1] - a[1], 1e-6)
				return {
					t,
					a[2] + (b[2] - a[2]) * u,
					a[3] + (b[3] - a[3]) * u,
					lerpAngle(a[4], b[4], u),
					a[5] + (b[5] - a[5]) * u,
				}
			end
		end
		return history[1]
	end

	local function reconcile(entry: { number }, t: number)
		local sx, sz, sh, sv = entry[1], entry[2], entry[3], entry[5]
		local ack, ackAt = entry[7], entry[8]
		if not meReady then
			me.X, me.Z, me.H, me.V = sx, sz, sh, sv
			aim = entry[4] or sh
			meReady = true
			return
		end
		local sent = ack and sentAt[ack]
		if not sent or not ackAt then
			if (ack or 0) == 0 and seq > 0 then
				return -- my first inputs haven't reached the server yet: it's still where I started
			end
			-- An input I don't know (someone else drives this tank, e.g. a test): follow it.
			local dx, dz = sx - me.X, sz - me.Z
			me.X, me.Z, me.H, me.V = sx, sz, sh, sv
			if dx * dx + dz * dz < 64 then
				offX -= dx
				offZ -= dz
			end
			return
		end
		local match = math.min(sent + math.max(t - ackAt, 0), api:Now())
		local past = stateAt(match)
		if not past then
			return
		end
		local ex, ez = sx - past[2], sz - past[3]
		local eh = TankField.Wrap(sh - past[4])
		local ev = sv - past[5]
		if ex * ex + ez * ez < 0.0025 and math.abs(eh) < 0.003 then
			return
		end
		me.X += ex
		me.Z += ez
		me.H = TankField.Wrap(me.H + eh)
		me.V += ev
		for _, item in history do
			if item[1] >= match then
				item[2] += ex
				item[3] += ez
				item[4] = TankField.Wrap(item[4] + eh)
				item[5] += ev
			end
		end
		if ex * ex + ez * ez > 64 then
			offX, offZ, offH = 0, 0, 0 -- too far off to ease: jump there
		else
			offX -= ex
			offZ -= ez
			offH -= eh
		end
	end

	local function readTanks()
		local value = api:SharedJSON("Tanks")
		if type(value) ~= "table" or type(value.k) ~= "table" or type(value.t) ~= "number" then
			return
		end
		snapshot = value
		local mine = value.k[tostring(myId)]
		if mine and field then
			reconcile(mine, value.t)
		end
	end
	api:OnShared("Tanks", readTanks)

	-- Input ------------------------------------------------------------------------------------------

	local function cameraAxes(): (Vector3, Vector3)
		local look = camera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 1e-3 then
			return Vector3.new(0, 0, -1), Vector3.new(1, 0, 0)
		end
		local forward = flat.Unit
		return forward, Vector3.new(-forward.Z, 0, forward.X)
	end

	local function moveInput(): (number, number)
		local forward, right = cameraAxes()
		local move = Vector3.zero
		if controls then
			local ok, value = pcall(controls.GetMoveVector, controls)
			if ok and typeof(value) == "Vector3" then
				move = right * value.X - forward * value.Z
			end
		elseif not touch then
			local x = (if UserInputService:IsKeyDown(Enum.KeyCode.D) then 1 else 0)
				- (if UserInputService:IsKeyDown(Enum.KeyCode.A) then 1 else 0)
			local z = (if UserInputService:IsKeyDown(Enum.KeyCode.S) then 1 else 0)
				- (if UserInputService:IsKeyDown(Enum.KeyCode.W) then 1 else 0)
			move = right * x - forward * z
		end
		if move.Magnitude > 1 then
			move = move.Unit
		end
		return move.X, move.Z
	end

	-- Where a screen point lands on the shells' flying height.
	local function groundAt(ray: Ray): Vector3?
		local planeY = origin.Y + TankField.SHELL_Y
		if ray.Direction.Y > -1e-3 then
			return nil
		end
		local t = (planeY - ray.Origin.Y) / ray.Direction.Y
		return ray.Origin + ray.Direction * t
	end

	local aimTouch: InputObject? = nil
	local dragUntil = 0
	local stickAim: Vector3? = nil
	local reticle: Part? = nil

	api:Track(UserInputService.TouchStarted:Connect(function(input, processed)
		if processed or not touch then
			return
		end
		if input.Position.X < camera.ViewportSize.X * 0.42 then
			return -- the thumbstick's side
		end
		aimTouch = input
	end))
	api:Track(UserInputService.TouchEnded:Connect(function(input)
		if input == aimTouch then
			aimTouch = nil
			dragUntil = os.clock() + 1.5 -- keep the dragged aim a moment before the assist takes over
		end
	end))
	api:Track(UserInputService.InputChanged:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local value = input.Position
			if Vector2.new(value.X, value.Y).Magnitude > 0.35 then
				local forward, right = cameraAxes()
				stickAim = right * value.X + forward * value.Y
			else
				stickAim = nil
			end
		end
	end))

	-- The nearest enemy in front of my hull (phones' aim-assist), within `cone` radians of `around`.
	local function assistTarget(around: number, cone: number, range: number): Visual?
		local best, bestScore = nil, math.huge
		for userId, visual in visuals do
			if userId == myId or visual.Out then
				continue
			end
			local dx, dz = visual.X - me.X, visual.Z - me.Z
			local distance = math.sqrt(dx * dx + dz * dz)
			if distance > range or distance < 1 then
				continue
			end
			local off = math.abs(TankField.Wrap(math.atan2(-dx, -dz) - around))
			if off > cone then
				continue
			end
			local score = distance / range + off / cone * 0.6
			if field and not TankField.Clear(field, me.X, me.Z, visual.X, visual.Z, 0.2) then
				score += 0.8
			end
			if score < bestScore then
				best, bestScore = visual, score
			end
		end
		return best
	end

	local function updateAim(dt: number)
		local headingTo = function(point: Vector3): number
			local local_ = point - origin
			return math.atan2(-(local_.X - me.X), -(local_.Z - me.Z))
		end
		if touch then
			if aimTouch then
				local point = groundAt(camera:ScreenPointToRay(aimTouch.Position.X, aimTouch.Position.Y))
				if point then
					local want = headingTo(point)
					-- A little magnet toward an enemy close to where the finger points.
					local magnet = assistTarget(want, math.rad(10), 120)
					if magnet then
						want = math.atan2(-(magnet.X - me.X), -(magnet.Z - me.Z))
					end
					aim = lerpAngle(aim, want, 1 - math.exp(-dt * 25))
				end
			elseif os.clock() > dragUntil then
				local hullFront = if me.Rev then me.H + math.pi else me.H
				local target = assistTarget(hullFront, math.rad(75), 95)
				local want = if target then math.atan2(-(target.X - me.X), -(target.Z - me.Z)) else hullFront
				aim = lerpAngle(aim, want, 1 - math.exp(-dt * (if target then 9 else 3)))
			end
		elseif stickAim then
			aim = math.atan2(-stickAim.X, -stickAim.Z)
		else
			local mouse = UserInputService:GetMouseLocation()
			local point = groundAt(camera:ViewportPointToRay(mouse.X, mouse.Y))
			if point then
				aim = headingTo(point)
				if reticle then
					reticle.CFrame = CFrame.new(point.X, origin.Y + 0.08, point.Z) * CFrame.Angles(0, 0, math.rad(90))
				end
			end
		end
		aim = TankField.Wrap(aim)
	end

	-- Shells -----------------------------------------------------------------------------------------

	local token = 0
	local lastShot = -math.huge
	local lastMine = -math.huge

	local function makeShellPart(owner: number): BasePart?
		local template = templates.TanksShell
		local part: BasePart? = nil
		if template then
			local model = template:Clone()
			part = if model:IsA("BasePart") then model else model:FindFirstChildWhichIsA("BasePart", true)
			if part and model:IsA("Model") then
				-- One piece is enough: the shell's mesh is a single part.
				part.Parent = nil
				model:Destroy()
			end
		end
		if not part then
			part = decor({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.9, Color = Color3.fromRGB(70, 70, 80) })
		end
		local shell = part :: BasePart
		shell.Anchored = true
		shell.CanCollide = false
		shell.CanQuery = false
		shell.CanTouch = false
		shell.CFrame = HIDDEN
		-- A smoke trail in the shooter's colour, fading to white.
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.25, 0.4)
		a0.Parent = shell
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.25, 0.4)
		a1.Parent = shell
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = if reduced then 0.18 else 0.35
		trail.Color = ColorSequence.new(colorOf(owner):Lerp(Color3.new(1, 1, 1), 0.3), Color3.new(1, 1, 1))
		trail.Transparency = NumberSequence.new(0.25, 1)
		trail.WidthScale = NumberSequence.new(1, 0.2)
		trail.LightEmission = 0.3
		trail.FaceCamera = true
		trail.Parent = shell
		shell.Parent = api.World
		return shell
	end

	-- Toy puffs (explosions, muzzle flashes, sparks): balls that swell, rise and fade (animated in
	-- the frame loop below).
	local effects: { { any } } = {}
	local function puff(position: Vector3, color: Color3, size: number, life: number)
		if #effects > 90 then
			return
		end
		local ball = decor({
			Name = "Puff",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * size * 0.4,
			CFrame = CFrame.new(position),
			Color = color,
			Transparency = 0.05,
			Parent = api.World,
		})
		table.insert(effects, { ball, position, size, life, os.clock() })
	end

	local function sparks(position: Vector3, color: Color3)
		puff(position, Color3.new(1, 1, 1), 1.6, 0.18)
		if not reduced then
			puff(position, color, 1.1, 0.3)
		end
	end

	-- Whether something happens close to what this screen looks at (no sound for far-off shots).
	local function near(position: Vector3, range: number): boolean
		local view = camera.CFrame
		local look = view.LookVector
		local focus = if look.Y < -0.1
			then view.Position + look * math.clamp((view.Position.Y - origin.Y) / -look.Y, 0, 200)
			else view.Position
		return (focus - position).Magnitude < range
	end

	local function addShell(entry: ShellVisual)
		entry.Part = makeShellPart(entry.Owner)
		table.insert(shells, entry)
	end

	local ended: { [number]: boolean } = {} -- shells that are gone (a late snapshot never brings one back)

	local function endShell(entry: ShellVisual, position: Vector3?, kind: string)
		if entry.Done then
			return
		end
		entry.Done = true
		if entry.Id then
			ended[entry.Id] = true
		end
		local part = entry.Part
		local at = position or (part and part.Position)
		if part then
			part.CFrame = HIDDEN
			task.delay(0.4, function()
				part:Destroy() -- after its trail has faded
			end)
		end
		if at and kind ~= "quiet" then
			sparks(at, colorOf(entry.Owner))
			if kind == "shield" and near(at, 90) then
				api:Sound("Boing")
			elseif kind == "shell" and near(at, 90) then
				api:Sound("Click")
			end
		end
	end

	local myShells = function(): number
		local count = 0
		for _, entry in shells do
			if entry.Owner == myId and not entry.Done then
				count += 1
			end
		end
		return count
	end

	api:OnEvent("Shot", function(id, owner, t0, x, z, shotAim, shotToken)
		if not field or type(id) ~= "number" or type(t0) ~= "number" then
			return
		end
		local path = TankField.Path(field, x, z, shotAim)
		local known = ended[id] ~= nil
		for _, entry in shells do
			if entry.Id == id then
				known = true -- already drawn from the shared state
			end
		end
		if owner == myId and type(shotToken) == "number" and shotToken > 0 then
			for _, entry in shells do
				if entry.Token == shotToken and not entry.Id and known then
					endShell(entry, nil, "quiet") -- the shared copy already flies the server's flight
					return
				elseif entry.Token == shotToken and not entry.Id then
					-- My own shot: take the server's flight, easing out the small difference.
					local now = api:Now()
					local ox, oz = TankField.At(entry.Path, math.max(now - entry.T0, 0) * SPEED)
					local nx, nz = TankField.At(path, math.max(now - t0, 0) * SPEED)
					entry.Id = id
					entry.Path = path
					entry.T0 = t0
					entry.OffX, entry.OffZ = ox - nx, oz - nz
					return
				end
			end
		end
		if not known then
			addShell({
				Id = id,
				Owner = owner,
				T0 = t0,
				Path = path,
				Bounced = false,
				OffX = 0,
				OffZ = 0,
				Born = os.clock(),
				Done = false,
			})
		end
		local visual = visuals[owner]
		if visual then
			visual.Aim = shotAim
			visual.Recoil = 1
			local tip = turretFrame(visual) * CFrame.new(0, TankField.SHELL_Y, -TankField.MUZZLE)
			if near(tip.Position, 70) then
				puff(tip.Position, Color3.fromRGB(255, 236, 190), 1.8, 0.16)
			end
		end
	end)

	-- The shells in flight as shared state: draws any this screen missed (it started late).
	local function readShells()
		local value = api:SharedJSON("Shells")
		if type(value) ~= "table" or not field then
			return
		end
		local now = api:Now()
		for key, item in value do
			local id = tonumber(key)
			if not id or ended[id] or type(item) ~= "table" or type(item[2]) ~= "number" then
				continue
			end
			local drawn = false
			local pending = false -- one of my own shots still waiting for the server's word
			for _, entry in shells do
				if entry.Id == id then
					drawn = true
				elseif item[1] == myId and entry.Owner == myId and not entry.Id and not entry.Done then
					pending = true
				end
			end
			if drawn or pending then
				continue
			end
			local path = TankField.Path(field, item[3], item[4], item[5])
			if (now - item[2]) * SPEED < path.Length then
				addShell({
					Id = id,
					Owner = item[1],
					T0 = item[2],
					Path = path,
					Bounced = (now - item[2]) * SPEED >= path.Bounce,
					OffX = 0,
					OffZ = 0,
					Born = os.clock(),
					Done = false,
				})
			end
		end
	end
	api:OnShared("Shells", readShells)
	readShells()

	api:OnEvent("Dud", function(dudToken)
		for _, entry in shells do
			if entry.Token == dudToken and not entry.Id then
				endShell(entry, nil, "quiet")
			end
		end
	end)

	api:OnEvent("Pop", function(id, x, z, kind)
		for _, entry in shells do
			if entry.Id == id then
				endShell(entry, if type(x) == "number" then world(x, TankField.SHELL_Y, z) else nil, kind)
			end
		end
	end)

	local function fire()
		if not canDrive() or not field then
			return
		end
		local now = api:Now()
		local cap, reload = TankField.Limits(aliveCount())
		if myShells() >= cap or now - lastShot < reload then
			return
		end
		lastShot = now
		token += 1
		local shotAim = aim
		addShell({
			Token = token,
			Owner = myId,
			T0 = now - TankField.MUZZLE / SPEED,
			Path = TankField.Path(field, me.X, me.Z, shotAim),
			Bounced = false,
			OffX = 0,
			OffZ = 0,
			Born = os.clock(),
			Done = false,
		})
		api:Action("Fire", shotAim, now, token)
		api:Sound("Hit")
		local visual = myVisual()
		if visual then
			visual.Recoil = 1
			local tip = turretFrame(visual) * CFrame.new(0, TankField.SHELL_Y, -TankField.MUZZLE)
			puff(tip.Position, Color3.fromRGB(255, 236, 190), 2, 0.16)
		end
		-- A shell that never comes back from the server (refused) fades away.
		local mine = token
		task.delay(1.2, function()
			for _, entry in shells do
				if entry.Token == mine and not entry.Id then
					endShell(entry, nil, "quiet")
				end
			end
		end)
	end

	local function layMine()
		if not canDrive() then
			return
		end
		local now = api:Now()
		local count = 0
		for _, mine in mines do
			if mine.Owner == myId then
				count += 1
			end
		end
		if count >= TankField.MAX_MINES or now - lastMine < TankField.MINE_GAP then
			return
		end
		lastMine = now
		api:Action("Mine")
	end

	-- Mines ------------------------------------------------------------------------------------------

	local blown: { [number]: boolean } = {} -- mines that went off (a late snapshot never brings one back)

	-- A mine's model (again later if its template hadn't arrived yet).
	local function mineModel(entry: MineVisual)
		local template = templates.TanksMine
		if entry.Model or not template or not field then
			return -- (placed later, once the field and template are here)
		end
		local model = template:Clone() :: Model
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				if part.Name == "Band" then
					part.Color = colorOf(entry.Owner)
				elseif part.Name == "Light" then
					entry.Light = part
				end
			end
		end
		model:PivotTo(CFrame.new(world(entry.X, -0.02, entry.Z)))
		model.Parent = api.World
		entry.Model = model
	end

	local function addMine(id: number, owner: number, x: number, z: number, armAt: number, blowAt: number): boolean
		if mines[id] or blown[id] then
			return false
		end
		local entry: MineVisual = { Owner = owner, X = x, Z = z, ArmAt = armAt, BlowAt = blowAt }
		mines[id] = entry
		mineModel(entry)
		return true
	end

	local function removeMine(id: number)
		local entry = mines[id]
		blown[id] = true
		if entry then
			mines[id] = nil
			if entry.Model then
				entry.Model:Destroy()
			end
			if entry.Ring then
				entry.Ring:Destroy()
			end
		end
	end

	api:OnEvent("Mine", function(id, owner, x, z, armAt, blowAt)
		if type(id) ~= "number" or type(x) ~= "number" or type(z) ~= "number" then
			return
		end
		if addMine(id, owner, x, z, armAt, blowAt) and owner == myId then
			api:Sound("Click")
		end
	end)

	-- The live mines as shared state: draws any this screen missed (it started late) and drops any
	-- whose blast it missed.
	local function readMines()
		local value = api:SharedJSON("Mines")
		if type(value) ~= "table" then
			return
		end
		for key, entry in value do
			local id = tonumber(key)
			if id and type(entry) == "table" and type(entry[2]) == "number" then
				addMine(id, entry[1], entry[2], entry[3], entry[4], entry[5])
			end
		end
		for id in mines do
			if value[tostring(id)] == nil then
				-- Give the blast's own event a moment (it brings the bang); then just remove it.
				task.delay(0.6, function()
					local now = api:SharedJSON("Mines")
					if mines[id] and type(now) == "table" and now[tostring(id)] == nil then
						removeMine(id)
					end
				end)
			end
		end
	end
	api:OnShared("Mines", readMines)
	readMines()
	api:OnShared("Field", function()
		readMines()
		readShells()
	end)

	local shake = 0
	local function boom(position: Vector3, color: Color3, scale: number)
		local count = if reduced then 4 else 9
		puff(position + Vector3.new(0, 1, 0), Color3.fromRGB(255, 250, 220), 9 * scale, 0.22)
		for index = 1, count do
			local angle = index / count * math.pi * 2
			local offset = Vector3.new(math.cos(angle), 0.5 + (index % 3) * 0.35, math.sin(angle)) * 3.2 * scale
			local tint = if index % 3 == 0
				then color
				elseif index % 3 == 1 then Color3.fromRGB(255, 170, 50)
				else Color3.fromRGB(255, 225, 90)
			puff(position + offset, tint, (3.5 + (index % 2) * 1.5) * scale, 0.45 + (index % 4) * 0.08)
		end
		if not reduced then
			for index = 1, 4 do
				local angle = index * 1.7
				puff(
					position + Vector3.new(math.cos(angle) * 2.5, 3 + index, math.sin(angle) * 2.5) * scale,
					Color3.fromRGB(120, 115, 125),
					5 * scale,
					1.1
				)
			end
		end
		local mine = myVisual()
		if mine and not mine.Out then
			local distance = (world(mine.X, 0, mine.Z) - position).Magnitude
			shake = math.max(shake, math.clamp(1 - distance / 70, 0, 1) * 0.6)
		end
		if near(position, 110) then
			api:Sound("Hit")
		end
	end

	api:OnEvent("Boom", function(id, x, z)
		if type(id) == "number" then
			removeMine(id)
		end
		if type(x) == "number" then
			boom(world(x, 1, z), Color3.fromRGB(255, 120, 60), 1.25)
			-- A scorch on the cork where it went off.
			decor({
				Name = "Scorch",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.05, 7, 7),
				CFrame = CFrame.new(world(x, 0.31, z)) * CFrame.Angles(0, 0, math.rad(90)), -- over the grooves
				Color = Color3.fromRGB(70, 52, 40),
				Transparency = 0.35,
				Parent = marks,
			})
		end
	end)

	-- Knock-outs -------------------------------------------------------------------------------------

	local hud = api:TopHud()
	local hudY = api:HudY()
	local feed: { TextLabel } = {}
	local hintUp = true -- the controls hint, until 8 s after GO (the rules card hides it before then)
	-- The kill feed sits under the hits line (under the hint while it's up); fewer lines on phones,
	-- where the thumbstick's corner starts not far below.
	local function layoutFeed()
		local top = hudY + 38 + (if hintUp then 36 else 0)
		local most = (if touch then 2 else 3) - (if hintUp and touch then 1 else 0)
		for index, item in feed do
			item.Position = UDim2.new(0.5, 0, 0, top + (index - 1) * 32)
			item.Visible = index <= most
		end
	end
	local hitsLabel = UIKit.Label({
		Name = "Hits",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, hudY),
		Size = UDim2.fromOffset(320, 36),
		Parent = hud,
		Children = { UIKit.TextStroke(0.15) },
	})
	local function refreshHits()
		local hits = localPlayer:GetAttribute("PP_Score")
		local count = if type(hits) == "number" then hits else 0
		local inRound = myVisual() ~= nil
		hitsLabel.Visible = inRound
		hitsLabel.Text = `💥 {count} {if count == 1 then "HIT" else "HITS"}`
	end
	api:Track(localPlayer:GetAttributeChangedSignal("PP_Score"):Connect(refreshHits))

	local function addFeed(text: string, color: Color3)
		local label = UIKit.Label({
			Name = "Feed",
			Text = text,
			Font = Theme.Fonts.Display,
			TextSize = 28,
			TextColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromOffset(440, 32),
			Parent = hud,
			Children = { UIKit.TextStroke(0.1) },
		})
		table.insert(feed, 1, label)
		while #feed > 3 do
			local oldest = table.remove(feed)
			if oldest then
				oldest:Destroy()
			end
		end
		layoutFeed()
		task.delay(4.5, function()
			local index = table.find(feed, label)
			if index then
				table.remove(feed, index)
				label:Destroy()
				layoutFeed()
			end
		end)
	end

	local function knockOut(userId: number, x: number?, z: number?, by: number?, cause: string?)
		local visual = visuals[userId]
		if not visual or visual.Out then
			return
		end
		visual.Out = true
		visual.OutAt = os.clock()
		if type(x) == "number" and type(z) == "number" then
			visual.X, visual.Z = x, z
		end
		placeTank(visual)
		local position = world(visual.X, 2, visual.Z)
		boom(position, colorOf(userId), 1)
		-- The turret flies off spinning; the hull chars and fades; an X in the tank's colour stays.
		local debris = {}
		for _, part in visual.Turret do
			table.insert(debris, {
				part,
				Vector3.new((math.random() - 0.5) * 16, 34 + math.random() * 10, (math.random() - 0.5) * 16),
				Vector3.new(math.random() * 8 - 4, math.random() * 6 - 3, math.random() * 8 - 4),
			})
		end
		visual.Debris = debris
		for _, part in visual.Hull do
			part.Color = part.Color:Lerp(Color3.fromRGB(40, 36, 34), 0.75)
		end
		if visual.Plate then
			visual.Plate.Enabled = false
		end
		for index = -1, 1, 2 do
			decor({
				Name = "Cross",
				Size = Vector3.new(0.9, 0.06, 7),
				CFrame = CFrame.new(world(visual.X, 0.48 + index * 0.06, visual.Z))
					* CFrame.Angles(0, math.rad(45 * index), 0),
				Color = colorOf(userId),
				Material = Enum.Material.SmoothPlastic,
				Transparency = 0.15,
				Parent = marks,
			})
		end
		-- The driver pops out of the hatch.
		local character = api:CharacterOf(userId)
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if character and root then
			visual.Character = character
			visual.PopFrom = root.CFrame
		end
		local victim = if userId == myId then "You" else nameOf(userId)
		local text = if by and by ~= 0
			then `{if by == myId then "You" else nameOf(by)} 💥 {victim}`
			elseif cause == "mined" or cause == "shelled" then `{victim} 💥 own goal!`
			else `{victim} is out`
		addFeed(text, if by and by ~= 0 then colorOf(by):Lerp(Color3.new(1, 1, 1), 0.3) else Theme.Colors.TextDim)
	end

	api:OnEvent("Out", function(userId, x, z, by, cause)
		knockOut(userId, x, z, by, cause)
	end)
	api:OnEvent("Gone", function(userId)
		local visual = visuals[userId]
		if visual and not visual.Out then
			visual.Out = true
			visual.OutAt = os.clock() - 5 -- no explosion: just gone
			if visual.Model then
				puff(world(visual.X, 2, visual.Z), Color3.new(1, 1, 1), 8, 0.4)
				visual.Model:Destroy()
				visual.Model = nil
			end
		end
	end)

	-- HUD --------------------------------------------------------------------------------------------

	local fireButton = api:Button({ Text = "FIRE", Key = Enum.KeyCode.Space, Color = Theme.Colors.Red })
	fireButton.Pressed:Connect(fire)
	local mineButton = api:Button({ Text = "MINE", Key = Enum.KeyCode.E, Color = Theme.Colors.Orange, Slot = 2 })
	mineButton.Pressed:Connect(layMine)
	api:Track(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local click = input.UserInputType == Enum.UserInputType.MouseButton1 and not touch
		if click or input.KeyCode == Enum.KeyCode.ButtonR2 or input.KeyCode == Enum.KeyCode.ButtonR1 then
			fire()
		elseif input.KeyCode == Enum.KeyCode.ButtonL2 or input.KeyCode == Enum.KeyCode.ButtonL1 then
			layMine()
		end
	end))
	api:Hint(
		if touch
			then "Stick: drive • Drag right: aim • FIRE!"
			else "WASD drive • Mouse aim • Click to FIRE • E: mine",
		hudY + 38
	)

	if not touch then
		reticle = decor({
			Name = "Reticle",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.08, 2.2, 2.2),
			Color = Theme.Colors.Yellow,
			Material = Enum.Material.Neon,
			Transparency = 0.45,
			CFrame = HIDDEN,
			Parent = api.World,
		})
	end
	local dots: { BasePart } = {}
	for index = 1, AIM_DOTS do
		dots[index] = decor({
			Name = "AimDot",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.42,
			Color = Color3.fromRGB(255, 250, 225),
			Material = Enum.Material.Neon,
			Transparency = 0.2,
			CFrame = HIDDEN,
			Parent = api.World,
		})
	end
	local NO_DOTS: { BasePart } = {}
	local lastAimX, lastAimZ, lastAim, lastAimAt = math.huge, math.huge, math.huge, -math.huge
	local function hideAim()
		lastAimX = math.huge
		for _, dot in dots do
			dot.CFrame = HIDDEN
		end
		if reticle then
			reticle.CFrame = HIDDEN
		end
	end

	-- Camera -----------------------------------------------------------------------------------------

	local cameraTaken = false
	local cameraPosition: Vector3? = nil
	local function releaseCamera()
		if cameraTaken then
			cameraTaken = false
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = 70
			local _, humanoid = api:Character()
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
	end
	api:Track(function()
		releaseCamera()
		local _, humanoid, root = api:Character()
		if humanoid then
			humanoid.PlatformStand = false
		end
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end)

	-- Every frame ------------------------------------------------------------------------------------

	api:RenderStep(function(rawDt)
		local run = field
		if not run then
			return
		end
		local dt = math.min(rawDt, 0.1)
		local now = api:Now()
		local clock = os.clock()
		if hintUp and now > goAt + 8 then
			hintUp = false
			api:Hint("")
			layoutFeed()
		end

		for index = #effects, 1, -1 do
			local item = effects[index]
			local ball, position, size, life = item[1], item[2], item[3], item[4]
			local t = (clock - item[5]) / life
			if t >= 1 then
				ball:Destroy()
				table.remove(effects, index)
			else
				ball.Size = Vector3.one * size * (0.4 + 0.8 * math.sqrt(t))
				ball.Transparency = 0.05 + 0.95 * t * t
				ball.CFrame = CFrame.new(position + Vector3.new(0, t * size * 0.6, 0))
			end
		end

		-- Tanks the server shares (made on first sight).
		for key, entry in snapshot.k do
			local userId = tonumber(key)
			if not userId then
				continue
			end
			local visual = visuals[userId]
			if not visual then
				local made = makeTank(userId)
				if not made then
					continue
				end
				visual = made
				visuals[userId] = visual
				visual.X, visual.Z, visual.H, visual.Aim = entry[1], entry[2], entry[3], entry[4]
				refreshHits()
			end
			visual.Seen = clock
		end

		-- My tank: drive it here from the input I've sent (the server drives its copy the same way).
		local mine = myVisual()
		local driving = canDrive()
		if mine and not mine.Out and meReady then
			updateAim(dt)
			if driving then
				local mx, mz = moveInput()
				mx, mz = round(mx, 0.01), round(mz, 0.01)
				local changed = math.abs(mx - sentMX) > 0.04
					or math.abs(mz - sentMZ) > 0.04
					or math.abs(TankField.Wrap(aim - sentAim)) > 0.03
				if (changed and now - lastSend >= 0.05) or now - lastSend >= 0.25 then
					seq += 1
					sentAt[seq] = now
					sentAt[seq - 40] = nil
					sentMX, sentMZ, sentAim = mx, mz, round(aim, 0.001)
					lastSend = now
					api:Action("In", seq, sentMX, sentMZ, sentAim)
				end
				local left = dt
				while left > 1e-4 do
					local h = math.min(left, 1 / 30)
					left -= h
					TankField.Drive(me, sentMX, sentMZ, h)
					TankField.Collide(run, me)
					for userId, other in visuals do
						if userId ~= myId and not other.Out then
							local depth, nx, nz = TankField.HullOverlap(me, other :: any)
							if depth then
								me.X += nx * depth
								me.Z += nz * depth
							end
						end
					end
				end
				table.insert(history, { now, me.X, me.Z, me.H, me.V })
				while #history > 0 and history[1][1] < now - 1.5 do
					table.remove(history, 1)
				end
			else
				local entry = snapshot.k[tostring(myId)]
				if entry then
					me.X, me.Z, me.H, me.V = entry[1], entry[2], entry[3], 0
				end
			end
			local ease = math.exp(-dt * 7)
			offX *= ease
			offZ *= ease
			offH *= ease
			mine.X, mine.Z, mine.H = me.X + offX, me.Z + offZ, TankField.Wrap(me.H + offH)
			mine.VX, mine.VZ = -math.sin(me.H) * me.V, -math.cos(me.H) * me.V
			mine.Aim = aim
		end

		-- Everyone else: on from the snapshot's speed and turn rate, eased toward it.
		local age = math.clamp(now - (snapshot.t or now), 0, 0.3)
		for userId, visual in visuals do
			if userId == myId or visual.Out then
				continue
			end
			local entry = snapshot.k[tostring(userId)]
			if not entry then
				continue
			end
			local h = entry[3] + (entry[6] or 0) * age
			local v = entry[5] or 0
			local vx, vz = -math.sin(h) * v, -math.cos(h) * v
			local tx, tz = entry[1] + vx * age, entry[2] + vz * age
			visual.VX, visual.VZ = vx, vz
			visual.X += vx * dt
			visual.Z += vz * dt
			local gx, gz = tx - visual.X, tz - visual.Z
			if gx * gx + gz * gz > 100 then
				visual.X, visual.Z = tx, tz
			else
				local k = 1 - math.exp(-dt * 9)
				visual.X += gx * k
				visual.Z += gz * k
			end
			visual.H = lerpAngle(visual.H, h, 1 - math.exp(-dt * 14))
			visual.Aim = lerpAngle(visual.Aim, entry[4], 1 - math.exp(-dt * 14))
		end

		-- Draw the tanks and seat their drivers (my own character moves for real).
		for userId, visual in visuals do
			if visual.Out then
				local since = clock - visual.OutAt
				local debris = visual.Debris
				if debris and visual.Model then
					for _, item in debris do
						local part, velocity, spin = item[1], item[2], item[3]
						item[2] = velocity - Vector3.new(0, 70 * dt, 0)
						local nextCF = (part.CFrame + item[2] * dt)
							* CFrame.Angles(spin.X * dt, spin.Y * dt, spin.Z * dt)
						if nextCF.Position.Y < origin.Y + 0.4 then
							item[2] = Vector3.zero
							item[3] = Vector3.zero
						else
							part.CFrame = nextCF
						end
					end
				end
				if visual.Model and since > 2.4 then
					local fade = math.clamp((since - 2.4) / 0.8, 0, 1)
					-- (The wreck's parts are found once, not every frame of the fade.)
					local fadeParts = visual.FadeParts
					if not fadeParts then
						fadeParts = {}
						for _, part in visual.Model:GetDescendants() do
							if part:IsA("BasePart") then
								table.insert(fadeParts, part)
							end
						end
						visual.FadeParts = fadeParts
					end
					for _, part in fadeParts do
						part.Transparency = fade
					end
					if fade >= 1 then
						visual.Model:Destroy()
						visual.Model = nil
					end
				end
				local character = visual.Character
				local from = visual.PopFrom
				if character and from and character.Parent and since < 2 then
					local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if root then
						local t = since
						local lift = 22 * t - 14 * t * t
						root.CFrame = from * CFrame.new(0, math.max(lift, -2), t * 3) * CFrame.Angles(t * 5, t * 7, 0)
						if userId == myId then
							root.AssemblyLinearVelocity = Vector3.zero
						end
					end
				end
				continue
			end
			if clock - visual.Seen > 1.5 then
				-- Not in the snapshot any more (the event that took it may have been missed).
				visual.Out = true
				visual.OutAt = clock - 5
				if visual.Model then
					visual.Model:Destroy()
					visual.Model = nil
				end
				continue
			end
			visual.Recoil = math.max(0, visual.Recoil - dt * 6)
			placeTank(visual)
			local character = api:CharacterOf(userId)
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if character and root then
				local seat = turretFrame(visual) * CFrame.new(0, SEAT_Y, 0)
				if userId == myId then
					local humanoid = character:FindFirstChildOfClass("Humanoid")
					if humanoid and not humanoid.PlatformStand then
						humanoid.PlatformStand = true
					end
					root.AssemblyLinearVelocity = Vector3.new(visual.VX, 0, visual.VZ)
					root.AssemblyAngularVelocity = Vector3.zero
				end
				root.CFrame = seat
			end
		end

		-- Shells along their flights.
		for index = #shells, 1, -1 do
			local entry = shells[index]
			if entry.Done then
				table.remove(shells, index)
				continue
			end
			local s = (now - entry.T0) * SPEED
			local part = entry.Part
			if s >= entry.Path.Length then
				local x, z = TankField.At(entry.Path, entry.Path.Length)
				endShell(entry, world(x, TankField.SHELL_Y, z), "wall")
				table.remove(shells, index)
				continue
			end
			if not entry.Bounced and s >= entry.Path.Bounce then
				entry.Bounced = true
				local x, z = TankField.At(entry.Path, entry.Path.Bounce)
				local at = world(x, TankField.SHELL_Y, z)
				sparks(at, Color3.fromRGB(255, 240, 160))
				if near(at, 80) then
					api:Sound("Boing")
				end
			end
			local ease = math.exp(-dt * 10)
			entry.OffX *= ease
			entry.OffZ *= ease
			if part then
				if s < TankField.MUZZLE * 0.85 then
					part.CFrame = HIDDEN
				else
					local x, z, dx, dz = TankField.At(entry.Path, s)
					local position = world(x + entry.OffX, TankField.SHELL_Y, z + entry.OffZ)
					part.CFrame = CFrame.lookAt(position, position + Vector3.new(dx, 0, dz))
				end
			end
		end

		-- Mines blink faster as they get ready to blow; the blast's reach shows in their last moments.
		for _, entry in mines do
			if not entry.Model then
				mineModel(entry) -- its template arrived after it did
			end
			local left = entry.BlowAt - now
			local light = entry.Light
			if light then
				local period = math.clamp(left / 5, 0.08, 0.6)
				local on = (now % period) < period * 0.5 or now < entry.ArmAt and (now % 0.5) < 0.1
				light.Color = if on then Color3.fromRGB(255, 60, 50) else Color3.fromRGB(110, 20, 20)
				light.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
			end
			if left < 1.6 and not entry.Ring then
				entry.Ring = decor({
					Name = "Blast",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(0.06, TankField.MINE_BLAST * 2, TankField.MINE_BLAST * 2),
					CFrame = CFrame.new(world(entry.X, 0.7, entry.Z)) * CFrame.Angles(0, 0, math.rad(90)),
					Color = Color3.fromRGB(255, 70, 60),
					Material = Enum.Material.Neon,
					Transparency = 0.75,
					Parent = api.World,
				})
				local visual = myVisual()
				if
					visual
					and not visual.Out
					and (visual.X - entry.X) ^ 2 + (visual.Z - entry.Z) ^ 2 < (TankField.MINE_BLAST + 8) ^ 2
				then
					api:Sound("HazardWarning")
				end
			end
			if entry.Ring then
				entry.Ring.Transparency = 0.55 + 0.3 * math.abs(math.sin(now * 12))
			end
		end

		-- My aim: a dotted line along the flight, ricochet included.
		local myTank = myVisual()
		if myTank and not myTank.Out and api:CanAct() then
			-- (The flight is traced again only when the aim or the tank moved, or every 0.2 s for
			-- walls that broke: the trace and 34 dots every frame cost phones for nothing.)
			local retrace = math.abs(myTank.X - lastAimX) > 0.05
				or math.abs(myTank.Z - lastAimZ) > 0.05
				or math.abs(aim - lastAim) > 0.002
				or clock - lastAimAt > 0.2
			if retrace then
				lastAimX, lastAimZ, lastAim, lastAimAt = myTank.X, myTank.Z, aim, clock
			end
			local path = if retrace then TankField.Path(run, myTank.X, myTank.Z, aim) else nil
			local stop = if path then math.min(path.Bounce + 16, 96) else 0
			local step = 2.8
			local shown: { BasePart } = if path then dots else NO_DOTS
			for index, dot in shown do
				local s = TankField.MUZZLE + (index - 1) * step
				if s > stop or not path then
					dot.CFrame = HIDDEN
				else
					local x, z = TankField.At(path, s)
					dot.CFrame = CFrame.new(world(x, TankField.SHELL_Y, z))
					dot.Transparency = if s > path.Bounce then 0.55 else 0.2
				end
			end
			local cap = TankField.Limits(aliveCount())
			fireButton:SetFill(math.max(cap - myShells(), 0) / cap, Color3.new(1, 1, 1))
			local minesDown = 0
			for _, entry in mines do
				if entry.Owner == myId then
					minesDown += 1
				end
			end
			mineButton:SetFill((TankField.MAX_MINES - minesDown) / TankField.MAX_MINES, Color3.new(1, 1, 1))
		else
			hideAim()
		end

		-- The camera follows my tank from high behind (north is always up the screen).
		if myTank and (not myTank.Out or clock - myTank.OutAt < 2.2) then
			local lead = Vector3.new(-math.sin(aim), 0, -math.cos(aim)) * (if touch then 6 else 9)
			local focus = world(myTank.X, 0, myTank.Z) + (if myTank.Out then Vector3.zero else lead)
			local desired = focus + Vector3.new(0, CAMERA_HEIGHT, CAMERA_BACK)
			cameraPosition = if cameraPosition then cameraPosition:Lerp(desired, 1 - math.exp(-dt * 6)) else desired
			if not cameraTaken then
				cameraTaken = true
				camera.CameraType = Enum.CameraType.Scriptable
			end
			shake = math.max(0, shake - dt * 1.5)
			local jolt = if shake > 0
				then Vector3.new(math.sin(clock * 71), math.sin(clock * 83), 0) * shake * 1.2
				else Vector3.zero
			local position = cameraPosition :: Vector3
			camera.CFrame = CFrame.lookAt(position + jolt, position - Vector3.new(0, CAMERA_HEIGHT, CAMERA_BACK))
			camera.FieldOfView = if touch then 62 else 58
		else
			releaseCamera()
		end
	end)
end

return Tanks
