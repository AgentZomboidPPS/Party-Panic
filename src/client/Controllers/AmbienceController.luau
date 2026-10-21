-- Brings the world to life on each client: balloons bob, trophies turn, the lobby's Ferris wheel
-- turns with its cabins hanging level, hot-air balloons drift, ambient particles drift.
-- All of this is cosmetic and local, so it costs the server nothing and can be switched off by
-- the "reduced effects" setting.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local State = require(script.Parent.Parent.State)

local AmbienceController = {}

type Animated = { model: Model, base: CFrame, phase: number }
type Cabin = { model: Model, base: CFrame, hang: Vector3 }
type Wheel = { wheel: Model, base: CFrame, hub: Vector3, axis: Vector3, cabins: { Cabin } }

local WHEEL_SPEED = 0.07 -- radians per second: one turn in about a minute and a half

local bobbing: { [Model]: Animated } = {}
local spinning: { [Model]: Animated } = {}
local floating: { [Model]: Animated } = {}
local wheels: { [Model]: Wheel } = {}

local function track(list: { [Model]: Animated }, instance: Instance)
	if instance:IsA("Model") then
		list[instance] = { model = instance, base = instance:GetPivot(), phase = math.random() * math.pi * 2 }
	end
end

local function watchTag(tagName: string, list: { [Model]: Animated })
	for _, instance in CollectionService:GetTagged(tagName) do
		track(list, instance)
	end
	CollectionService:GetInstanceAddedSignal(tagName):Connect(function(instance)
		track(list, instance)
	end)
	CollectionService:GetInstanceRemovedSignal(tagName):Connect(function(instance)
		list[instance :: Model] = nil
	end)
end

-- A Ferris wheel (LobbyBuilder): a LobbyFerrisWheel prop that turns about Hub along Axis, and
-- LobbyFerrisCabin props that hang from it by their "Hang" point.
local function trackWheel(instance: Instance)
	local hub, axis = instance:GetAttribute("Hub"), instance:GetAttribute("Axis")
	local wheel = instance:FindFirstChild("LobbyFerrisWheel")
	if not instance:IsA("Model") or typeof(hub) ~= "Vector3" or typeof(axis) ~= "Vector3" then
		return
	end
	if not (wheel and wheel:IsA("Model")) then
		return
	end
	local cabins = {}
	for _, child in instance:GetChildren() do
		local hang = child:GetAttribute("Hang")
		if child:IsA("Model") and typeof(hang) == "Vector3" then
			table.insert(cabins, { model = child, base = child:GetPivot(), hang = hang })
		end
	end
	wheels[instance] = { wheel = wheel, base = wheel:GetPivot(), hub = hub, axis = axis.Unit, cabins = cabins }
end

local function turnWheel(item: Wheel, angle: number)
	local turn = CFrame.fromAxisAngle(item.axis, angle)
	local hub = CFrame.new(item.hub)
	item.wheel:PivotTo(hub * turn * hub:Inverse() * item.base)
	for _, cabin in item.cabins do
		local hang = cabin.base.Position + cabin.hang
		local moved = item.hub + turn:VectorToWorldSpace(hang - item.hub)
		cabin.model:PivotTo(cabin.base + (moved - hang))
	end
end

local function applyAmbientParticles()
	local enabled = not State.ReducedEffects()
	for _, emitter in CollectionService:GetTagged("PP_Ambient") do
		if emitter:IsA("ParticleEmitter") then
			emitter.Enabled = enabled
		end
	end
end

function AmbienceController.Start(_context)
	watchTag("PP_Bob", bobbing)
	watchTag("PP_Spin", spinning)
	watchTag("PP_Float", floating)
	for _, instance in CollectionService:GetTagged("PP_Wheel") do
		trackWheel(instance)
	end
	CollectionService:GetInstanceAddedSignal("PP_Wheel"):Connect(function(instance)
		-- Replication can deliver the model before all its children; give them a moment.
		task.delay(2, trackWheel, instance)
	end)
	CollectionService:GetInstanceRemovedSignal("PP_Wheel"):Connect(function(instance)
		wheels[instance :: Model] = nil
	end)
	CollectionService:GetInstanceAddedSignal("PP_Ambient"):Connect(function(emitter)
		if emitter:IsA("ParticleEmitter") then
			emitter.Enabled = not State.ReducedEffects()
		end
	end)
	State.SettingsChanged:Connect(applyAmbientParticles)
	applyAmbientParticles()

	local camera = workspace.CurrentCamera
	RunService.RenderStepped:Connect(function()
		if State.ReducedEffects() then
			return
		end
		local now = os.clock()
		local cameraPosition = camera.CFrame.Position
		for model, item in bobbing do
			if (item.base.Position - cameraPosition).Magnitude < 220 then
				model:PivotTo(
					item.base
						* CFrame.new(0, math.sin(now * 1.6 + item.phase) * 0.6, 0)
						* CFrame.Angles(0, 0, math.sin(now * 1.1 + item.phase) * 0.05)
				)
			end
		end
		for model, item in spinning do
			if (item.base.Position - cameraPosition).Magnitude < 260 then
				model:PivotTo(item.base * CFrame.Angles(0, now * 0.5 + item.phase, 0))
			end
		end
		-- Big, slow and far away: drift up and down a few studs and turn gently.
		for model, item in floating do
			model:PivotTo(
				item.base
					* CFrame.new(0, math.sin(now * 0.35 + item.phase) * 3, 0)
					* CFrame.Angles(0, math.sin(now * 0.1 + item.phase) * 0.6, 0)
			)
		end
		for _, item in wheels do
			if (item.hub - cameraPosition).Magnitude < 600 then
				turnWheel(item, now * WHEEL_SPEED)
			end
		end
	end)
end

return AmbienceController
