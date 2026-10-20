-- Local character movement effects: bounce pads, knockback from gloves/spills, and the lobby
-- parkour timer. The local client simulates its own character, so these apply instantly.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AudioController = require(script.Parent.AudioController)
local EffectsController = require(script.Parent.EffectsController)
local NotificationController = require(script.Parent.NotificationController)

local MovementController = {}

local player = Players.LocalPlayer
local lastBounce = 0
local parkourStart: number? = nil
local parkourBest: number? = nil

local function getCharacter(): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or humanoid.Health <= 0 or not root then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function isLocalCharacterPart(part: BasePart): boolean
	local character = player.Character
	return character ~= nil and part:IsDescendantOf(character)
end

local function bindBouncePad(pad: Instance)
	if not pad:IsA("BasePart") then
		return
	end
	pad.Touched:Connect(function(hit)
		if not isLocalCharacterPart(hit) then
			return
		end
		local now = os.clock()
		if now - lastBounce < 0.6 then
			return
		end
		local _, _, root = getCharacter()
		if not root then
			return
		end
		lastBounce = now
		local power = pad:GetAttribute("Power") or 90
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, power, velocity.Z)
		AudioController.Play("Boing")
		EffectsController.Play("Sparkles", pad.Position + Vector3.new(0, 2, 0), { pad.Color })
	end)
end

local function bindParkourStart(pad: Instance)
	(pad :: BasePart).Touched:Connect(function(hit)
		if isLocalCharacterPart(hit) and (not parkourStart or os.clock() - parkourStart > 2) then
			parkourStart = os.clock()
		end
	end)
end

local function bindParkourFinish(pad: Instance)
	(pad :: BasePart).Touched:Connect(function(hit)
		if not isLocalCharacterPart(hit) or not parkourStart then
			return
		end
		local time = os.clock() - parkourStart
		parkourStart = nil
		local isBest = parkourBest == nil or time < parkourBest
		if isBest then
			parkourBest = time
		end
		local bestText = if isBest then " New best!" else string.format(" (best %.1fs)", parkourBest :: number)
		NotificationController.Show(string.format("🧗 Parkour complete in %.1fs!%s", time, bestText), "success")
		EffectsController.Play("Confetti", (pad :: BasePart).Position + Vector3.new(0, 3, 0))
	end)
end

-- Binds existing and future instances with a tag (the lobby replicates over a few seconds).
local function onTag(tag: string, callback: (Instance) -> ())
	for _, instance in CollectionService:GetTagged(tag) do
		callback(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(callback)
end

function MovementController.Start(_context)
	onTag("BouncePad", bindBouncePad)
	onTag("ParkourStart", bindParkourStart)
	onTag("ParkourFinish", bindParkourFinish)

	-- Knockback decided by the server (direction, strength, stun), applied to our own physics.
	Remotes.Get("Knockback").OnClientEvent:Connect(function(velocity, stun)
		if typeof(velocity) ~= "Vector3" or type(stun) ~= "number" then
			return
		end
		local _, humanoid, root = getCharacter()
		if not humanoid or not root then
			return
		end
		if stun <= 0 then
			root.AssemblyLinearVelocity += velocity
			return
		end
		humanoid.PlatformStand = true
		root.AssemblyLinearVelocity = velocity
		root.AssemblyAngularVelocity = Vector3.new(math.random(-6, 6), math.random(-6, 6), math.random(-6, 6))
		task.delay(math.clamp(stun, 0.1, 2), function()
			if humanoid.Parent then
				humanoid.PlatformStand = false
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
	end)
end

return MovementController
