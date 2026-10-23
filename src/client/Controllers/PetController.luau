-- The crate seasons' pets (owner: "next tier of loot is pets, 5 total pets per season", then "Hollow
-- night comes first ... This has to be sick. This will be players first season. I want it to look
-- insane."; Shared/Seasons has HOLLOW NIGHT's five: the Harvest Owl, Ember Stag, Gourdian, Toadstool
-- Tot and Lantern Wisp). Everyone's pet is built and moved by every device itself from the season's
-- meshes (World/SeasonWorld's SeasonMeshes): the server only says which pet someone has on
-- (PP_Pet), so pets cost no network traffic or physics.
--
--   * Where: about 3 studs big (the owl's wingspan and the stag's antlers a little more), floating
--     behind its owner's shoulder above head height (3.4 back, 1.9 to the side, 4.4 up), so it never
--     covers a face or a name tag. It springs after them with a little lag, bobs, and turns to face
--     where they're going.
--   * Alive the whole time (owner: "For all of these pets. They all have super cool animations
--     right?"), and more so as its owner runs: the owl beats its wings in flight, rising on each
--     downstroke, its lantern swinging from its beak and its head cocking; the stag looks about,
--     flicks its ears and tail, and gallops after its owner; the Gourdian bobs its head and swings
--     its fists, its roots streaming behind it at a run; the Tot waddles, its cap wobbling a beat
--     behind; the wisp's ghost bobs and looks about in its lantern, its tail swaying, the lantern
--     swinging from its ring.
--   * How it gets noticed without getting bigger: a soft pool of light on the ground under it, its own
--     glow, a few sparkles in its colour, and its flourish every 20 seconds or so: the owl tucks its
--     wings, swoops and flares them wide with big beats, its lantern swinging; the stag rears up,
--     kicking, tossing its antlers in a burst of embers; the Gourdian drums its fists, shakes its head
--     laughing, its face blazing, and its glowing leaves whirl; the Tot hops and spins, its cap
--     bouncing, and puffs glowing spores; the wisp's ghost spins round and its tail curls into a
--     ring. The parts that move are the meshes' named pieces (WingL..., Head..., LegFL...), each
--     turning at its Hinge marker (tools/meshgen/season/hollow_night_pets.py); the moves are
--     client/PetPoses. Wearing the pet's
--     matching hat (PetInfo.Hat: the Scarecrow Hat with the owl, the Antler Circlet with the stag...)
--     makes it flourish more often, with a ring of light. Owning all five of a season's pets
--     (PP_PetSets) gives them that season's sparkle for good.
--   * Never in the way: no collisions, touches or ray hits; 80% see-through when the camera comes
--     within 6 studs of it or in first person.
--   * In the mini-games it follows at 80% size, and other players' pets dim to half while a round is
--     on, so they never hide a hazard. When a game takes the camera over (a top-down or fixed
--     camera: the memory games, the board games), only your own pet shows.
--   * Cheap: sparkles stop beyond 60 studs and pets hide beyond 150; with reduced effects there are
--     fewer particles. At most one pet per player in the server.
-- Its owner winning (their victory effect plays at them) or the cup podium (Celebrate) sets off its
-- flourish there and then.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Cosmetics = require(Shared.Cosmetics)
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)
local Seasons = require(Shared.Seasons)

local PetPoses = require(script.Parent.Parent.PetPoses)
local SeasonParts = require(script.Parent.Parent.SeasonParts)
local State = require(script.Parent.Parent.State)

local PetController = {}

local SIZE = 3 -- studs: a pet's biggest side
-- (the owl's biggest side is its wingspan and the stag's its antlers, so they're a little bigger; the
-- cute one is a little smaller)
local SIZES = { Pet_HarvestOwl = 4.2, Pet_EmberStag = 3.6, Pet_ToadstoolTot = 2.5 }
local ROUND_SIZE = 0.8 -- in a mini-game
local BACK, SIDE, UP = 3.4, 1.9, 4.4 -- where it floats: behind, to the right of, and above the feet
local FOLLOW = 6 -- how quickly it catches up (higher: less lag)
local TURN = 5
local BOB = 0.25
local FLOURISH_EVERY = 20 -- seconds, give or take a few
local MATCHED_EVERY = 13 -- wearing its matching hat
local NEAR_CAMERA = 6
local SPARKLE_RANGE = 60
local SHOW_RANGE = 150
local SNAP = 40 -- studs: further than this (a teleport to the arena) and it's put there at once
local POOL_EVERY = 0.12 -- seconds between finding the ground under it
local ROUND = { Preparing = true, InRound = true }

type Group = PetPoses.Group

type Pet = {
	Owner: Player,
	Id: string,
	Info: Seasons.PetInfo,
	Season: string,
	Model: Model,
	Parts: { BasePart },
	Offsets: { CFrame }, -- each part from the model's pivot
	Groups: { [string]: Group },
	GroupOf: { string | false }, -- each part's group (false: none)
	TailOrder: { [BasePart]: number }, -- the tail's pieces from its root out
	Core: BasePart,
	Depth: number, -- half its length (the stag rears up on its back legs)
	Height: number,
	Run: number, -- 0 to 1: how fast its owner is moving (its gallop, its wingbeat)
	Flare: { { Part: BasePart, Color: Color3 } }, -- the Gourdian's face (it blazes in its flourish)
	FlareLevel: number,
	Scale: number,
	Position: Vector3,
	Yaw: number,
	Clock: number, -- its own time (so pets don't bob in step)
	NextFlourish: number,
	FlourishAt: number?,
	Matched: boolean,
	Light: PointLight,
	Sparkles: ParticleEmitter,
	SetSparkle: ParticleEmitter,
	Burst: ParticleEmitter,
	Pool: Part,
	PoolAt: number,
	Shown: boolean,
	Fade: number, -- the LocalTransparencyModifier its parts have now
}

local localPlayer = Players.LocalPlayer
local folder: Folder
local pets: { [Player]: Pet } = {}
local victoryEffects: { [string]: boolean } = { Confetti = true }
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = false

local function color(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- How far the feet are below the root (R15: hip height and half the root; R6: 3).
local function feetBelow(player: Player, root: BasePart): number
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return 3
end

local function inRound(): boolean
	return ROUND[GameState.Get("Phase") or "Waiting"] == true
end

-- Where a group turns when its mesh has no Hinge marker: wings at their inner top edge, the head
-- and the seeds round their middle, the lantern from its top, the tail from where it leaves the
-- lantern.
local function hingeOf(name: string, low: Vector3, high: Vector3): Vector3
	local middle = (low + high) / 2
	if name == "WingL" then
		return Vector3.new(low.X, high.Y - (high.Y - low.Y) * 0.15, middle.Z)
	elseif name == "WingR" then
		return Vector3.new(high.X, high.Y - (high.Y - low.Y) * 0.15, middle.Z)
	elseif name == "Head" or name == "Seed" then
		return Vector3.new(0, middle.Y, 0)
	elseif name == "Lantern" then
		return Vector3.new(middle.X, high.Y, middle.Z)
	elseif name == "Tail" then
		return Vector3.new(middle.X, low.Y, low.Z)
	end
	return middle
end

-- An emitter on the pet's biggest part.
local function emitter(parent: BasePart, props: { [string]: any }): ParticleEmitter
	local made = Instance.new("ParticleEmitter")
	made.LightEmission = 1
	made.Texture = SeasonParts.Sparkle
	for key, value in props do
		(made :: any)[key] = value
	end
	made.Parent = parent
	return made
end

local function destroy(player: Player)
	local pet = pets[player]
	if pet then
		pets[player] = nil
		pet.Model:Destroy()
		pet.Pool:Destroy()
	end
end

-- Builds `player`'s pet `id` (nil while the season's meshes haven't arrived).
local function build(player: Player, id: string): Pet?
	local season = Seasons.SeasonOf(id)
	local info = season and season.PetInfo[id]
	if not season or not info then
		return nil
	end
	local model = SeasonParts.Copy(info.Prop)
	if not model then
		return nil
	end
	model.Name = `PP_Pet_{player.UserId}`
	local _, size = model:GetBoundingBox()
	local biggest = math.max(size.X, size.Y, size.Z)
	local scale = (SIZES[id] or SIZE) / math.max(biggest, 0.1)
	model:ScaleTo(model:GetScale() * scale)
	-- The pivot at the bottom middle (as the server made it), wherever ScaleTo left it.
	local box, boxSize = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(box.Position - Vector3.new(0, boxSize.Y / 2, 0))
	local pivot = model:GetPivot()

	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	local bounds: { [string]: { Low: Vector3, High: Vector3, Parts: { BasePart } } } = {}
	local markers: { [string]: Vector3 } = {}
	local flare: { { Part: BasePart, Color: Color3 } } = {}
	local core: BasePart? = nil
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		local offset = pivot:ToObjectSpace(part.CFrame)
		-- The flat light disc under the model (it was drawn for a pet sitting on the ground): the pet's
		-- pool of light on the ground takes its place.
		if part.Name == "Glow" and part.Size.Y < 0.12 * scale and offset.Position.Y < 0.12 * scale then
			part.Transparency = 1
		end
		table.insert(parts, part)
		table.insert(offsets, offset)
		if not core or part.Size.Magnitude > core.Size.Magnitude then
			core = part
		end
		local group = PetPoses.GroupOf(part.Name)
		if group and string.sub(part.Name, -5) == "Hinge" then
			-- (an invisible marker where the group turns)
			markers[group] = offset.Position
		end
		if group == "Head" and info.Flourish == "Gourdian" and part.Material == Enum.Material.Neon then
			table.insert(flare, { Part = part, Color = part.Color })
		end
		if group then
			local half = part.Size / 2
			local entry = bounds[group]
				or { Low = Vector3.one * math.huge, High = -Vector3.one * math.huge, Parts = {} }
			entry.Low = entry.Low:Min(offset.Position - half)
			entry.High = entry.High:Max(offset.Position + half)
			table.insert(entry.Parts, part)
			bounds[group] = entry
		end
	end
	if not core then
		model:Destroy()
		return nil
	end
	local groups: { [string]: Group } = {}
	for name, entry in bounds do
		groups[name] = { Hinge = markers[name] or hingeOf(name, entry.Low, entry.High), Parts = entry.Parts }
	end
	local groupOfPart: { string | false } = {}
	local placeOf: { [BasePart]: Vector3 } = {}
	for index, part in parts do
		groupOfPart[index] = PetPoses.GroupOf(part.Name) or false
		placeOf[part] = offsets[index].Position
	end
	-- The wisp's tail curls piece by piece: the further from its root, the more each piece turns.
	local tailOrder: { [BasePart]: number } = {}
	local tail = groups.Tail
	if tail then
		local sorted = table.clone(tail.Parts)
		table.sort(sorted, function(a, b)
			return (placeOf[a] - tail.Hinge).Magnitude < (placeOf[b] - tail.Hinge).Magnitude
		end)
		for index, part in sorted do
			tailOrder[part] = index
		end
	end

	local glow = color(info.Light)
	local light = Instance.new("PointLight")
	light.Color = glow
	light.Range = 9
	light.Brightness = 0.9
	light.Shadows = false
	light.Parent = core
	local reduced = State.ReducedEffects()
	local sparkles = emitter(core, {
		Name = "PetSparkles",
		Color = ColorSequence.new(glow, Color3.new(1, 1, 1)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0.15, 1),
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(0.4, 1.2),
		SpreadAngle = Vector2.new(180, 180),
		Rate = if reduced then 0.8 else 2.5,
	})
	local setSparkle = emitter(core, {
		Name = "SeasonSparkle",
		Color = ColorSequence.new(Color3.fromRGB(255, 226, 130), glow),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.38),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Lifetime = NumberRange.new(0.9, 1.6),
		Speed = NumberRange.new(0.6, 1.6),
		SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-120, 120),
		Rate = if reduced then 1.5 else 5,
		Enabled = false,
	})
	local burstEmitter = emitter(core, {
		Name = "Flourish",
		Enabled = false,
		Color = ColorSequence.new(glow),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.8, 1.5),
		Speed = NumberRange.new(3, 6),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 2.5,
	})

	local pool = Instance.new("Part")
	pool.Name = `PP_PetPool_{player.UserId}`
	pool.Shape = Enum.PartType.Cylinder
	local across = 2.7 * (SIZES[id] or SIZE) / 3
	pool.Size = Vector3.new(0.05, across, across)
	pool.Material = Enum.Material.Neon
	pool.Color = glow
	pool.Transparency = 0.82
	pool.Anchored = true
	pool.CanCollide = false
	pool.CanQuery = false
	pool.CanTouch = false
	pool.CastShadow = false

	local root = rootOf(player)
	local start = if root then root.Position else Vector3.zero
	local pet: Pet = {
		Owner = player,
		Id = id,
		Info = info,
		Season = season.Id,
		Model = model,
		Parts = parts,
		Offsets = offsets,
		Groups = groups,
		GroupOf = groupOfPart,
		TailOrder = tailOrder,
		Core = core,
		Depth = boxSize.Z / 2,
		Height = boxSize.Y,
		Run = 0,
		Flare = flare,
		FlareLevel = 0,
		Scale = 1,
		Position = start,
		Yaw = 0,
		Clock = math.random() * 10,
		NextFlourish = os.clock() + 4 + math.random() * FLOURISH_EVERY,
		FlourishAt = nil,
		Matched = false,
		Light = light,
		Sparkles = sparkles,
		SetSparkle = setSparkle,
		Burst = burstEmitter,
		Pool = pool,
		PoolAt = 0,
		Shown = false,
		Fade = 0,
	}
	return pet
end

-- Puts `player`'s pet right: built, swapped or taken away to match their PP_Pet.
local function refresh(player: Player)
	local id = player:GetAttribute("PP_Pet")
	local wanted = if type(id) == "string" and id ~= "" and Seasons.ItemById[id] then id else nil
	local current = pets[player]
	if current and current.Id == wanted then
		return
	end
	destroy(player)
	if wanted then
		local pet = build(player, wanted)
		if pet then
			pets[player] = pet
		end
	end
end

-- Moves every part of `pet` to its place for this frame: `base` is where the pet is.
local function place(pet: Pet, base: CFrame, t: number?, clock: number, parts: { BasePart }, frames: { CFrame })
	local body, turns = PetPoses.Pose(pet, t, clock)
	local whole = base * body
	local moves = PetPoses.Moves(pet, turns)
	for index, part in pet.Parts do
		local offset = pet.Offsets[index]
		local frame = whole * offset
		local group = pet.GroupOf[index]
		if group then
			local move = moves[group]
			if move and group == "Tail" and pet.Info.Flourish == "Wisp" then
				-- (the wisp's tail curls piece by piece: the further from its root, the more)
				local entry = pet.Groups[group]
				local partial = CFrame.identity
				for _ = 1, pet.TailOrder[part] or 1 do
					partial *= turns[group]
				end
				move = CFrame.new(entry.Hinge) * partial * CFrame.new(-entry.Hinge)
			end
			if move then
				frame = whole * move * offset
			end
		end
		table.insert(parts, part)
		table.insert(frames, frame)
	end
	-- The Gourdian's face blazes through its flourish.
	local level = if t and pet.Info.Flourish == "Gourdian" then math.floor(math.sin(t * math.pi) * 10 + 0.5) / 10 else 0
	if level ~= pet.FlareLevel then
		pet.FlareLevel = level
		for _, entry in pet.Flare do
			entry.Part.Color = entry.Color:Lerp(Color3.fromRGB(255, 246, 200), level)
		end
	end
end

-- The flourish's own sparkle: embers, seeds, spores, wisps. More with reduced effects off.
local function burst(pet: Pet, matched: boolean)
	local count = if State.ReducedEffects() then 6 else 18
	local emitterNow = pet.Burst
	local kind = pet.Info.Flourish
	if kind == "Stag" then
		-- (embers off its antlers)
		emitterNow.Color = ColorSequence.new(Color3.fromRGB(255, 226, 130), Color3.fromRGB(255, 106, 31))
		emitterNow.Speed = NumberRange.new(2, 4)
		emitterNow.Lifetime = NumberRange.new(1.2, 2)
		emitterNow.Acceleration = Vector3.new(0, 1.5, 0)
	elseif kind == "Gourdian" then
		emitterNow.Color = ColorSequence.new(Color3.fromRGB(255, 196, 92), Color3.fromRGB(196, 120, 50))
		emitterNow.Speed = NumberRange.new(5, 8)
		emitterNow.Lifetime = NumberRange.new(0.6, 1)
		emitterNow.Acceleration = Vector3.new(0, -14, 0)
	elseif kind == "Tot" then
		emitterNow.Color = ColorSequence.new(Color3.fromRGB(255, 244, 214), Color3.fromRGB(255, 226, 150))
		emitterNow.Speed = NumberRange.new(0.8, 2)
		emitterNow.Lifetime = NumberRange.new(1.4, 2.2)
		emitterNow.Acceleration = Vector3.new(0, 1.2, 0)
		emitterNow.Size =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.55) })
	elseif kind == "Wisp" then
		emitterNow.Color = ColorSequence.new(Color3.fromRGB(216, 255, 240), Color3.fromRGB(125, 255, 178))
		emitterNow.Speed = NumberRange.new(2, 4)
		emitterNow.Acceleration = Vector3.new(0, 4, 0)
	else
		emitterNow.Color = ColorSequence.new(Color3.fromRGB(255, 208, 74), Color3.fromRGB(214, 72, 38))
		emitterNow.Speed = NumberRange.new(2, 4)
	end
	emitterNow:Emit(count)
	if matched then
		-- The matching hat: a ring of light spreads out round the pet, and a second sparkle.
		local ring = Instance.new("Part")
		ring.Name = "PP_PetRing"
		ring.Shape = Enum.PartType.Cylinder
		ring.Material = Enum.Material.Neon
		ring.Color = color(pet.Info.Light)
		ring.Transparency = 0.35
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring.Size = Vector3.new(0.08, 1, 1)
		ring.CFrame = CFrame.new(pet.Core.Position) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = folder
		local grow = TweenService:Create(ring, TweenInfo.new(0.8, Enum.EasingStyle.Quad), {
			Size = Vector3.new(0.08, 7 * pet.Height / 3, 7 * pet.Height / 3),
			Transparency = 1,
		})
		grow:Play()
		grow.Completed:Once(function()
			ring:Destroy()
		end)
		pet.SetSparkle:Emit(if State.ReducedEffects() then 4 else 12)
	end
	local light = pet.Light
	light.Brightness = 2.4
	task.delay(0.6, function()
		if light.Parent then
			light.Brightness = 0.9
		end
	end)
end

-- Whether `player` wears the hat that matches `pet`.
local function wearsMatch(player: Player, pet: Pet): boolean
	local hat = player.Character and player.Character:FindFirstChild("PP_Hat")
	return hat ~= nil and pet.Info.Hat ~= nil and hat:GetAttribute("PP_Hat") == pet.Info.Hat
end

-- Every frame: each pet springs after its owner, poses, fades and shows or hides.
local function step(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local now = os.clock()
	local cameraAt = camera.CFrame.Position
	local round = inRound()
	local takenOver = round and camera.CameraType ~= Enum.CameraType.Custom
	local reduced = State.ReducedEffects()
	local parts: { BasePart } = {}
	local frames: { CFrame } = {}
	local filtered = false

	for owner, pet in pets do
		local root = rootOf(owner)
		local mine = owner == localPlayer
		local far = root == nil or (root.Position - cameraAt).Magnitude > SHOW_RANGE
		local hidden = far or (takenOver and not mine)
		if hidden then
			if pet.Shown then
				pet.Shown = false
				pet.Model.Parent = nil
				pet.Pool.Parent = nil
			end
			continue
		end
		local body = root :: BasePart
		if not pet.Shown then
			pet.Shown = true
			pet.Model.Parent = folder
			pet.Pool.Parent = folder
		end

		-- Its size: 80% in a round the owner plays.
		local wantScale = if owner:GetAttribute("PP_InRound") == true then ROUND_SIZE else 1
		if math.abs(pet.Scale - wantScale) > 0.01 then
			local ratio = wantScale / pet.Scale
			pet.Scale = wantScale
			pet.Height *= ratio
			for index, offset in pet.Offsets do
				pet.Offsets[index] = CFrame.new(offset.Position * ratio) * offset.Rotation
				local part = pet.Parts[index]
				part.Size *= ratio
			end
			for _, group in pet.Groups do
				group.Hinge *= ratio
			end
		end

		-- Where it wants to be: behind the right shoulder, above the head.
		local look = body.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
		local right = Vector3.new(-flat.Z, 0, flat.X)
		local feet = body.Position.Y - feetBelow(owner, body)
		local scale = pet.Scale
		local target = Vector3.new(body.Position.X, feet + UP * (0.85 + 0.15 * scale), body.Position.Z)
			- flat * BACK * scale
			+ right * SIDE * scale
		if (target - pet.Position).Magnitude > SNAP then
			pet.Position = target
		else
			pet.Position = pet.Position:Lerp(target, 1 - math.exp(-FOLLOW * dt))
		end
		-- Facing where its owner goes (or looks, standing still).
		local moving = Vector3.new(body.AssemblyLinearVelocity.X, 0, body.AssemblyLinearVelocity.Z)
		local heading = if moving.Magnitude > 2 then moving.Unit else flat
		-- How fast its owner goes (a walk is 16 studs a second): its gallop, its wingbeat.
		local wantRun = math.clamp((moving.Magnitude - 1) / 15, 0, 1)
		pet.Run += (wantRun - pet.Run) * (1 - math.exp(-5 * dt))
		local wantYaw = math.atan2(-heading.X, -heading.Z)
		local delta = (wantYaw - pet.Yaw + math.pi) % (2 * math.pi) - math.pi
		pet.Yaw += delta * (1 - math.exp(-TURN * dt))

		-- The flourish, now and then (more often in its matching hat).
		pet.Clock += dt
		local t: number? = nil
		if pet.FlourishAt then
			local elapsed = now - pet.FlourishAt
			local length = PetPoses.FLOURISH_TIMES[pet.Info.Flourish] or PetPoses.FLOURISH_TIME
			if elapsed >= length then
				pet.FlourishAt = nil
			else
				t = elapsed / length
			end
		elseif now >= pet.NextFlourish then
			pet.Matched = wearsMatch(owner, pet)
			pet.FlourishAt = now
			pet.NextFlourish = now + (if pet.Matched then MATCHED_EVERY else FLOURISH_EVERY) + math.random() * 6 - 3
			t = 0
			burst(pet, pet.Matched)
		end

		-- (its bob gives way to its flourish)
		local bob = math.sin(pet.Clock * 2.1) * BOB * scale * (if t then 1 - math.sin(t * math.pi) else 1)
		local base = CFrame.new(pet.Position + Vector3.new(0, bob, 0)) * CFrame.Angles(0, pet.Yaw, 0)
		place(pet, base, t, pet.Clock, parts, frames)

		-- See-through near the camera or in first person; other players' pets dim in a round.
		local distance = (pet.Position - cameraAt).Magnitude
		local firstPerson = mine and (cameraAt - (body.Position + Vector3.new(0, 1.5, 0))).Magnitude < 1.6
		local fade = if distance < NEAR_CAMERA or firstPerson then 0.8 elseif round and not mine then 0.5 else 0
		if fade ~= pet.Fade then
			pet.Fade = fade
			for _, part in pet.Parts do
				part.LocalTransparencyModifier = fade
			end
			pet.Pool.LocalTransparencyModifier = fade
		end

		-- Sparkles near enough to see them; the season's sparkle with the full set.
		local sets = owner:GetAttribute("PP_PetSets")
		local hasSet = type(sets) == "string" and table.find(string.split(sets, ","), pet.Season) ~= nil
		local near = distance <= SPARKLE_RANGE
		pet.Sparkles.Enabled = near
		pet.Sparkles.Rate = if reduced then 0.8 else 2.5
		pet.SetSparkle.Enabled = near and hasSet
		pet.Light.Enabled = distance <= SPARKLE_RANGE * 1.5

		-- Its pool of light on the ground under it.
		if now >= pet.PoolAt then
			pet.PoolAt = now + POOL_EVERY
			if not filtered then
				filtered = true
				local exclude: { Instance } = { folder }
				for _, other in Players:GetPlayers() do
					if other.Character then
						table.insert(exclude, other.Character)
					end
				end
				rayParams.FilterDescendantsInstances = exclude
			end
			local hit = workspace:Raycast(pet.Position, Vector3.new(0, -20, 0), rayParams)
			if hit then
				pet.Pool.CFrame = CFrame.new(hit.Position + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90))
				pet.Pool.Transparency = 0.82
			else
				pet.Pool.Transparency = 1
			end
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Sets off `player`'s pet's flourish now (the cup podium; their win).
function PetController.Celebrate(player: Player)
	local pet = pets[player]
	if pet and not pet.FlourishAt then
		pet.Matched = wearsMatch(player, pet)
		pet.FlourishAt = os.clock()
		pet.NextFlourish = os.clock() + FLOURISH_EVERY
		burst(pet, true)
	end
end

-- The pet of whoever a victory effect plays at (the server plays it 3 studs over their root).
local function onEffect(name: any, position: any)
	if type(name) ~= "string" or typeof(position) ~= "Vector3" or not victoryEffects[name] then
		return
	end
	for owner in pets do
		local root = rootOf(owner)
		if root and (root.Position + Vector3.new(0, 3, 0) - position).Magnitude < 2.5 then
			PetController.Celebrate(owner)
		end
	end
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("PP_Pet"):Connect(function()
		refresh(player)
	end)
	refresh(player)
end

function PetController.Start(_context)
	folder = Instance.new("Folder")
	folder.Name = "LocalPets"
	folder.Parent = workspace
	for _, item in Cosmetics.List do
		if item.Slot == "Victory" and item.Effect then
			victoryEffects[item.Effect] = true
		end
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(destroy)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	-- The season's meshes arrive a few seconds after joining: pets waiting for them are built then.
	SeasonParts.OnTemplates(function()
		for _, player in Players:GetPlayers() do
			refresh(player)
		end
	end)
	Remotes.Get("PlayEffect").OnClientEvent:Connect(onEffect)
	RunService:BindToRenderStep("PP_Pets", Enum.RenderPriority.Camera.Value + 2, step)
end

return PetController
