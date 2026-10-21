-- Brings the world to life on each client: balloons bob, trophies turn, the lobby's Ferris wheel
-- turns with its cabins hanging level, hot-air balloons drift, rubber ducks rock on the water,
-- ambient particles drift.
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
local WHEEL_WAIT = 30 -- seconds to wait for a wheel's parts to replicate before giving up

local bobbing: { [Model]: Animated } = {}
local spinning: { [Model]: Animated } = {}
local floating: { [Model]: Animated } = {}
local ducks: { [Model]: Animated } = {}
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

local function hangingCabins(instance: Instance): { Model }
	local cabins = {}
	for _, child in instance:GetChildren() do
		if child:IsA("Model") and typeof(child:GetAttribute("Hang")) == "Vector3" then
			table.insert(cabins, child)
		end
	end
	return cabins
end

-- A Ferris wheel (LobbyBuilder): a LobbyFerrisWheel prop that turns about Hub along Axis, and
-- "Cabins" LobbyFerrisCabin props that hang from it by their "Hang" point. Replication can deliver
-- the model before its children, so this waits (in its own thread) until every piece is here;
-- snapshotting too early would leave the late cabins hanging still while the wheel turns.
local function trackWheel(instance: Instance)
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	local hub, axis = instance:GetAttribute("Hub"), instance:GetAttribute("Axis")
	if not instance:IsA("Model") or typeof(hub) ~= "Vector3" or typeof(axis) ~= "Vector3" then
		return
	end
	local wheel = instance:WaitForChild("LobbyFerrisWheel", WHEEL_WAIT)
	if not (wheel and wheel:IsA("Model")) then
		return
	end
	local expected = instance:GetAttribute("Cabins")
	local cabins = hangingCabins(instance)
	local deadline = os.clock() + WHEEL_WAIT
	while typeof(expected) == "number" and #cabins < expected and os.clock() < deadline and instance.Parent do
		task.wait(0.5)
		cabins = hangingCabins(instance)
	end
	if not instance.Parent then
		return
	end
	local tracked = {}
	for _, cabin in cabins do
		table.insert(tracked, { model = cabin, base = cabin:GetPivot(), hang = cabin:GetAttribute("Hang") })
	end
	wheels[instance] = { wheel = wheel, base = wheel:GetPivot(), hub = hub, axis = axis.Unit, cabins = tracked }
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
	watchTag("PP_Duck", ducks)
	for _, instance in CollectionService:GetTagged("PP_Wheel") do
		task.spawn(trackWheel, instance)
	end
	CollectionService:GetInstanceAddedSignal("PP_Wheel"):Connect(function(instance)
		task.spawn(trackWheel, instance)
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
		-- Rubber ducks stay sitting in the water: a tiny bob, a slow turn and a little rock.
		for model, item in ducks do
			if (item.base.Position - cameraPosition).Magnitude < 160 then
				model:PivotTo(
					item.base
						* CFrame.new(0, math.sin(now * 1.3 + item.phase) * 0.1, 0)
						* CFrame.Angles(
							0,
							math.sin(now * 0.2 + item.phase) * 0.5,
							math.sin(now * 1.7 + item.phase) * 0.06
						)
				)
			end
		end
		for _, item in wheels do
			if (item.hub - cameraPosition).Magnitude < 600 then
				turnWheel(item, now * WHEEL_SPEED)
			end
		end
	end)
end

return AmbienceController
