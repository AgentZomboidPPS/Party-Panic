-- Client half of Snowball Summit: draws every snowball smoothly from what the server shares and
-- sends this player's ROLL presses.
--   * Thrown balls (MG_Balls) follow the server's schedule exactly (start, direction, speed, slowing,
--     then a drop once past the rim), rolling as they go, so what everyone sees is what the server
--     judges hits against.
--   * Held balls (MG_Held: radius per UserId) sit in front of their holder's character, rolling as
--     they walk and swelling smoothly as the radius grows.
--   * HUD: the snowball's size (a bar and a number) while you roll one, a little feed of knock-offs,
--     and the ROLL button (hold to roll, let go to throw; E on a keyboard). A dotted line on the snow
--     shows where your ball will go.
--   * Falling snow (heavier in the blizzard), off with reduced effects.

local CollectionService = game:GetService("CollectionService")

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local SnowballSummit = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local MIN_R, MAX_R = 0.8, 3.2 -- server: MIN_R, MAX_R
local BODY, HOLD_GAP = 1.0, 0.5 -- server: BODY, HOLD_GAP
local ICE = Color3.fromRGB(120, 200, 255)

type Shown = { Model: Model, Base: number, Scale: number, Spin: CFrame, Last: Vector3? }

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function SnowballSummit.Start(api)
	api:Mood({
		Tint = Color3.fromRGB(236, 246, 255),
		Saturation = -0.02,
		Contrast = 0.08,
		Brightness = 0.03,
		Haze = Color3.fromRGB(214, 230, 252),
		HazeDecay = Color3.fromRGB(176, 200, 236),
		Density = 0.22,
	})
	local reduced = State.ReducedEffects()
	local template = api:Template("Snowball", 10) :: Model?
	local summit = api:SharedJSON("Summit")
	api:OnShared("Summit", function()
		summit = api:SharedJSON("Summit")
	end)

	-- Snowball models -------------------------------------------------------------------------
	local function newBall(): Shown?
		if not template then
			return nil
		end
		local model = template:Clone()
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
			end
		end
		model.Parent = api.World
		return { Model = model, Base = model:GetScale(), Scale = 1, Spin = CFrame.identity }
	end
	local function place(shown: Shown, center: Vector3, r: number)
		if math.abs(shown.Scale - r) > 0.015 then
			shown.Scale = r
			shown.Model:ScaleTo(shown.Base * r)
		end
		if shown.Last then
			local move = flat(center - shown.Last)
			if move.Magnitude > 0.001 and move.Magnitude < 10 then
				local axis = Vector3.yAxis:Cross(move.Unit)
				shown.Spin = CFrame.fromAxisAngle(axis, move.Magnitude / r) * shown.Spin
			end
		end
		shown.Last = center
		shown.Model:PivotTo(CFrame.new(center) * shown.Spin * CFrame.new(0, -r, 0))
	end

	local thrown: { [number]: { Data: any, Shown: Shown } } = {}
	local held: { [string]: { R: number, Shown: Shown } } = {}
	local heldRadius: { [string]: number } = {}

	local function ballAt(data: any, t: number): Vector3
		local decel = summit and summit.D or 5
		local g = summit and summit.G or 196.2
		local top = summit and summit.Y or 0
		local dt = math.clamp(t - data.T, 0, data.S / decel)
		local d = data.S * dt - 0.5 * decel * dt * dt
		local y = top + data.R
		if data.E >= 0 and t > data.E then
			local fall = t - data.E
			y -= 0.5 * g * fall * fall
		end
		return Vector3.new(data.X + data.DX * d, y, data.Z + data.DZ * d)
	end

	local function refreshBalls()
		local list = api:SharedJSON("Balls") or {}
		local seen = {}
		for _, data in list do
			seen[data.I] = true
			local entry = thrown[data.I]
			if not entry then
				local shown = newBall()
				if shown then
					thrown[data.I] = { Data = data, Shown = shown }
				end
			end
		end
		for id, entry in thrown do
			if not seen[id] then
				entry.Shown.Model:Destroy()
				thrown[id] = nil
			end
		end
	end
	api:OnShared("Balls", refreshBalls)
	refreshBalls()

	local function refreshHeld()
		local map = api:SharedJSON("Held") or {}
		heldRadius = {}
		for key, r in map do
			if type(r) == "number" then
				heldRadius[tostring(key)] = r
			end
		end
		for key in heldRadius do
			if not held[key] then
				local shown = newBall()
				if shown then
					held[key] = { R = heldRadius[key], Shown = shown }
				end
			end
		end
		for key, entry in held do
			if not heldRadius[key] then
				entry.Shown.Model:Destroy()
				held[key] = nil
			end
		end
	end
	api:OnShared("Held", refreshHeld)
	refreshHeld()

	-- Aim dots on the snow in front of your own ball ---------------------------------------------
	local dots = {}
	for index = 1, 5 do
		local dot = Instance.new("Part")
		dot.Name = "SnowballSummitAimDot"
		dot.Shape = Enum.PartType.Cylinder
		dot.Anchored = true
		dot.CanCollide = false
		dot.CanQuery = false
		dot.CanTouch = false
		dot.CastShadow = false
		dot.Material = Enum.Material.Neon
		dot.Color = ICE
		dot.Transparency = 0.25 + index * 0.1
		local size = 1.1 - index * 0.13
		dot.Size = Vector3.new(0.06, size, size)
		dot.CFrame = CFrame.new(index * 4, -1000, 0) -- parked apart, out of sight, until you roll a ball
		dot.Parent = api.World
		dots[index] = dot
	end

	-- HUD -----------------------------------------------------------------------------------------
	local hud = api:TopHud()
	local y = api:HudY()
	local meter = UIKit.new("Frame", {
		Name = "SizeMeter",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.fromOffset(300, 44),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.25,
		Visible = false,
		Parent = hud,
		Children = { UIKit.Round(), UIKit.Stroke(Color3.new(1, 1, 1), 3, 0.2) },
	})
	local bar = UIKit.new("Frame", {
		Name = "Bar",
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(0, 0, 1, -12),
		BackgroundColor3 = ICE,
		Parent = meter,
		Children = { UIKit.Round() },
	})
	local sizeLabel = UIKit.Label({
		Name = "Size",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = meter,
		Children = { UIKit.TextStroke(0.15) },
	})
	local feed = UIKit.Label({
		Name = "Feed",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 24,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y + 50),
		Size = UDim2.fromOffset(360, 32),
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0.15) },
	})
	local feedUntil = 0

	api:Hint(
		if api:IsTouch()
			then "Hold ROLL and walk to grow a snowball, let go to throw!"
			else "Hold E and walk to grow a snowball, let go to throw!",
		y
	)
	local hintShown = true
	task.delay(7, function()
		if hintShown then
			hintShown = false
			api:Hint("")
		end
	end)

	local function nameOf(userId: number): string
		for _, person in api:Participants() do
			if person.UserId == userId then
				return person.DisplayName
			end
		end
		return "Someone"
	end

	-- Controls ------------------------------------------------------------------------------------
	local roll = api:Button({ Text = "ROLL", Key = Enum.KeyCode.E, Color = Theme.Colors.Cyan })
	roll.Pressed:Connect(function()
		api:Action("Build")
	end)
	roll.Released:Connect(function()
		local _, _, root = api:Character()
		local look = if root then flat(root.CFrame.LookVector) else Vector3.zero
		if look.Magnitude > 0.01 then
			look = look.Unit
			api:Action("Throw", look.X, look.Z)
		else
			api:Action("Throw")
		end
	end)

	-- Cues ----------------------------------------------------------------------------------------
	local sparkleColors = { Color3.new(1, 1, 1), Color3.fromRGB(190, 230, 255) }
	api:OnEvent("Smash", function(x, yy, z, _r)
		if type(x) == "number" and type(yy) == "number" and type(z) == "number" then
			api:Effect("Poof", Vector3.new(x, yy, z), sparkleColors)
		end
	end)
	api:OnEvent("Hit", function(userId, x, yy, z, _r)
		if type(x) == "number" and type(yy) == "number" and type(z) == "number" then
			api:Effect("Poof", Vector3.new(x, yy, z), sparkleColors)
			api:Effect("Stars", Vector3.new(x, yy + 2, z))
		end
		api:Sound("Hit")
		if type(userId) == "number" then
			local _, _, root = api:Character()
			local character = api:CharacterOf(userId)
			if root and character and root:IsDescendantOf(character) then
				api:Sound("Boing")
			end
		end
	end)
	api:OnEvent("Throw", function(_userId, _r)
		api:Sound("Click")
	end)
	api:OnEvent("KnockOff", function(victim, by)
		if type(victim) ~= "number" then
			return
		end
		feed.Text = if type(by) == "number" and by ~= 0
			then `💥 {nameOf(by)} knocked {nameOf(victim)} off!`
			else `🌨️ {nameOf(victim)} fell off!`
		feed.Visible = true
		feedUntil = os.clock() + 2.6
	end)

	-- Falling snow --------------------------------------------------------------------------------
	local sky = Instance.new("Part")
	sky.Name = "SnowballSummitSnowfall"
	sky.Anchored = true
	sky.CanCollide = false
	sky.CanQuery = false
	sky.CanTouch = false
	sky.Transparency = 1
	sky.Size = Vector3.new(140, 1, 140)
	sky.CFrame = CFrame.new(0, -1000, 0)
	sky.Parent = api.World
	local snow = Instance.new("ParticleEmitter")
	snow.Texture = SPARKLE
	snow.Color = ColorSequence.new(Color3.new(1, 1, 1))
	snow.LightEmission = 0.3
	snow.Size = NumberSequence.new(0.35, 0.25)
	snow.Lifetime = NumberRange.new(8, 11)
	snow.Speed = NumberRange.new(5, 8)
	snow.SpreadAngle = Vector2.new(14, 14)
	snow.Acceleration = Vector3.new(1.5, 0, 0.8)
	snow.EmissionDirection = Enum.NormalId.Bottom
	snow.Rate = 60
	snow.Rotation = NumberRange.new(0, 360)
	snow.RotSpeed = NumberRange.new(-40, 40)
	snow.Enabled = not reduced
	snow.Parent = sky
	CollectionService:AddTag(snow, "PP_Ambient")
	local function blizzard()
		if api:Shared("Blizzard") then
			snow.Rate = 160
			snow.Acceleration = Vector3.new(9, 0, 4)
		end
	end
	api:OnShared("Blizzard", blizzard)
	blizzard()

	-- Every frame ---------------------------------------------------------------------------------
	api:RenderStep(function(dt)
		if not summit then
			return
		end
		local now = api:Now()
		local top = summit.Y
		if sky.Position.Y < top then
			sky.CFrame = CFrame.new(summit.X, top + 40, summit.Z)
		end

		for _, entry in thrown do
			local data = entry.Data
			local center = ballAt(data, now)
			place(entry.Shown, center, data.R)
		end

		local _, _, myRoot = api:Character()
		local mine: { R: number, Shown: Shown }? = nil
		for key, entry in held do
			local target = heldRadius[key] or entry.R
			entry.R += (target - entry.R) * math.min(1, dt * 10)
			local character = api:CharacterOf(tonumber(key))
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then
				entry.Shown.Model:PivotTo(CFrame.new(0, -1000, 0))
				continue
			end
			if root == myRoot then
				mine = entry
			end
			local look = flat(root.CFrame.LookVector)
			look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
			local spot = root.Position + look * (BODY + HOLD_GAP + entry.R)
			place(entry.Shown, Vector3.new(spot.X, top + entry.R, spot.Z), entry.R)
		end

		-- My ball: the size meter and the aim dots.
		if mine and myRoot then
			local share = (mine.R - MIN_R) / (MAX_R - MIN_R)
			meter.Visible = true
			bar.Size = UDim2.new(math.clamp(share, 0.04, 1) * (288 / 300), 0, 1, -12)
			sizeLabel.Text = if share >= 0.99
				then "❄ MAX SIZE!"
				else string.format("❄ SIZE %d%%", math.floor(share * 100))
			roll:SetFill(share, Color3.new(1, 1, 1))
			local look = flat(myRoot.CFrame.LookVector)
			look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
			local start = myRoot.Position + look * (BODY + HOLD_GAP + mine.R * 2 + 1)
			for index, dot in dots do
				local spot = start + look * (index * 2.2)
				dot.CFrame = CFrame.new(spot.X, top + 0.09, spot.Z) * CFrame.Angles(0, 0, math.rad(90))
			end
			if hintShown then
				hintShown = false
				api:Hint("")
			end
		else
			meter.Visible = false
			roll:SetFill(0)
			for index, dot in dots do
				dot.CFrame = CFrame.new(index * 4, -1000, 0)
			end
		end

		if feed.Visible and os.clock() > feedUntil then
			feed.Visible = false
		end
	end)
end

return SnowballSummit
