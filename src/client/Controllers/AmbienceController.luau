-- Brings the world to life on each client: balloons bob, trophies turn, ambient particles drift.
-- All of this is cosmetic and local, so it costs the server nothing and can be switched off by
-- the "reduced effects" setting.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local State = require(script.Parent.Parent.State)

local AmbienceController = {}

type Animated = { model: Model, base: CFrame, phase: number }

local bobbing: { [Model]: Animated } = {}
local spinning: { [Model]: Animated } = {}

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
	end)
end

return AmbienceController
