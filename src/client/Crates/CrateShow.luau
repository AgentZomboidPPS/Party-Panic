-- The opening show (the crate seasons' design: "open like the mystery box in CoD Zombies, right there
-- where everyone can watch ... The same five seconds as Frostfall, dressed for fall: leaves instead of
-- snow, warm light instead of ice"; owner: "This has to be sick ... I want it to look insane."). The
-- server has already rolled and saved the prize (Services/CrateService); every device in the server
-- plays the same show from its "Show" message, timed from the server's clock, so everyone sees the
-- same thing at the same moment:
--   0.0 - 0.35  the crate rattles, light leaks out under its lid
--   0.35 - 0.7  BURST: the lid blasts off, warm light pours up, a burst of leaves flies out, a ring
--               rolls across the ground and the altar's lanterns flare
--   0.7 - 3.4   REEL: items flicker through the beam and slow down, with a rising tick, while the
--               beam cycles through the tier colours
--   3.4 - 5.2   REVEAL: the beam locks to the prize's tier colour (gold coins, blue effect, purple
--               hat, pink pet, ember title), the prize rises out of the crate (a pet or hat as its
--               model, anything else as a card), "<name> unboxed <PRIZE>!" over it, then it floats
--               to the opener and the crate fades back to the altar's own.
-- At an altar (its own crate hides while the show plays), or as a small crate over the opener's head
-- (OPEN HERE, or when every altar is busy), and Open 5 as five crates in an arc, each with its own
-- beam. Shows far from this device's camera aren't drawn (the opener still gets their card). Reduced
-- effects: fewer particles, no rattle. Everything is this device's own (workspace.CrateShows).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage.Shared
local SeasonArt = require(Shared.SeasonArt)
local Seasons = require(Shared.Seasons)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local CrateTheme = require(script.Parent.CrateTheme)

local CrateShow = {}

local DRAW_RANGE = 320 -- studs from the camera: shows further away aren't drawn
local RATTLE_END = 0.35
local BURST_END = 0.7
local BEAM_HEIGHT = 34
local LEAF = "rbxasset://textures/particles/sparkles_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

-- The colours the reel cycles through (the tiers, rarest last so it lands with a bang).
local REEL_TIERS = { "Coins", "Effect", "Hat", "Coins", "Pet", "Effect", "Title", "Hat" }

type Crate = {
	Model: Model,
	Base: CFrame, -- where the crate sits (its pivot, the bottom)
	Scale: number,
	Lid: { { Part: BasePart, From: CFrame, Spin: Vector3, Fling: Vector3 } },
	Parts: { BasePart },
	Beam: Beam?,
	Core: Beam?,
	Top: Attachment?,
	Light: PointLight,
	Leaves: ParticleEmitter,
	Sparks: ParticleEmitter,
	Reel: BillboardGui,
	ReelPicture: Frame,
	Result: { [string]: any },
	Delay: number,
	Prize: Instance?,
	PrizeFrom: CFrame?,
	Ticks: number,
	Burst: boolean,
	Revealed: boolean,
}

type Active = {
	Show: { [string]: any },
	Start: number, -- os.clock() its time 0 was (from the server's clock)
	Crates: { Crate },
	Altar: Model?,
	Hidden: { BasePart },
	Ring: { BasePart },
	RingColors: { [BasePart]: Color3 },
	AltarLight: PointLight?,
	Label: BillboardGui?,
	Shock: BasePart?,
	Folder: Folder,
	Ended: boolean,
}

local active: { Active } = {}
local folder: Folder? = nil
local rng = Random.new()

-- Called once the reveal shows: (show, crateIndex, result). CrateController shows the opener's card.
CrateShow.Revealed = nil :: ((show: { [string]: any }) -> ())?
-- The world's reaction to a show (SeasonWorldController: wisps, the pile's glow): (show, position).
CrateShow.Started = nil :: ((show: { [string]: any }, position: Vector3) -> ())?
CrateShow.Landed = nil :: ((show: { [string]: any }, position: Vector3, color: Color3) -> ())?

local function showsFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local made = Instance.new("Folder")
	made.Name = "CrateShows"
	made.Parent = workspace
	folder = made
	return made
end

local function template(name: string): Model?
	local meshes = ReplicatedStorage:FindFirstChild("SeasonMeshes")
	local found = meshes and meshes:FindFirstChild(name)
	return if found and found:IsA("Model") then found else nil
end

local function altarModel(index: number): Model?
	for _, model in CollectionService:GetTagged("PP_CrateAltar") do
		if model:IsA("Model") and model:GetAttribute("PP_Altar") == index then
			return model
		end
	end
	return nil
end

local function headOf(userId: number): BasePart?
	local who = Players:GetPlayerByUserId(userId)
	local character = who and who.Character
	local head = character and character:FindFirstChild("Head")
	return if head and head:IsA("BasePart") then head else nil
end

local function ease(t: number): number
	t = math.clamp(t, 0, 1)
	return 1 - (1 - t) ^ 3
end

-- A plain crate when the season's meshes haven't arrived: a box and a lid.
local function standInCrate(): Model
	local model = Instance.new("Model")
	model.Name = "Crate"
	local function box(name: string, size: Vector3, offset: Vector3, color: Color3)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = CFrame.new(offset)
		part.Color = color
		part.Material = Enum.Material.Wood
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Parent = model
		return part
	end
	local body = box("Wood", Vector3.new(3.2, 2.6, 3.2), Vector3.new(0, 1.3, 0), Color3.fromRGB(150, 92, 52))
	box("LidWood", Vector3.new(3.4, 0.7, 3.4), Vector3.new(0, 2.95, 0), Color3.fromRGB(120, 72, 40))
	model.PrimaryPart = body
	model.WorldPivot = CFrame.new()
	return model
end

local function newCrate(parent: Instance, base: CFrame, scale: number, result: { [string]: any }, delay: number): Crate
	local source = template(Seasons.CurrentSeason().Props.Crate)
	local model = if source then source:Clone() else standInCrate()
	model:PivotTo(CFrame.new())
	if scale ~= 1 then
		model:ScaleTo(model:GetScale() * scale)
	end
	model:PivotTo(base)
	model.Parent = parent
	local parts, lid = {}, {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			table.insert(parts, part)
			if string.sub(part.Name, 1, 3) == "Lid" then
				table.insert(lid, {
					Part = part,
					From = part.CFrame,
					Spin = Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(-3, 3), rng:NextNumber(-4, 4)),
					Fling = Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(9, 13), rng:NextNumber(-3, 3)) * scale,
				})
			end
		end
	end
	local height = 3.55 * scale
	local holder = Instance.new("Part")
	holder.Name = "Glow"
	holder.Size = Vector3.one * 0.2
	holder.Transparency = 1
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CFrame = base * CFrame.new(0, height * 0.85, 0)
	holder.Parent = model
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 110)
	light.Brightness = 0
	light.Range = 16 * math.max(scale, 0.6)
	light.Shadows = false
	light.Parent = holder
	local leaves = Instance.new("ParticleEmitter")
	leaves.Texture = if SeasonArt.Leaves ~= "" then SeasonArt.Leaves else LEAF
	if SeasonArt.Leaves ~= "" then
		leaves.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2
		leaves.FlipbookMode = Enum.ParticleFlipbookMode.Random
	end
	leaves.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(214, 72, 38)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(246, 168, 48)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(232, 190, 70)),
	})
	leaves.Size = NumberSequence.new(0.55 * math.max(scale, 0.6))
	leaves.Lifetime = NumberRange.new(1.2, 2.2)
	leaves.Speed = NumberRange.new(10, 18)
	leaves.SpreadAngle = Vector2.new(70, 70)
	leaves.Acceleration = Vector3.new(0, -14, 0)
	leaves.Drag = 1.6
	leaves.Rotation = NumberRange.new(0, 360)
	leaves.RotSpeed = NumberRange.new(-200, 200)
	leaves.EmissionDirection = Enum.NormalId.Top
	leaves.Rate = 0
	leaves.Parent = holder
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = if SeasonArt.Ember ~= "" then SeasonArt.Ember else SPARK
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.8, 1.6)
	sparks.Speed = NumberRange.new(6, 14)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Drag = 2
	sparks.Rate = 0
	sparks.Parent = holder

	local reel = Instance.new("BillboardGui")
	reel.Name = "Reel"
	reel.Size = UDim2.fromScale(3.6 * math.max(scale, 0.55), 3.6 * math.max(scale, 0.55))
	reel.StudsOffsetWorldSpace = Vector3.new(0, height + 3.4 * math.max(scale, 0.6), 0)
	reel.LightInfluence = 0
	reel.AlwaysOnTop = false
	reel.MaxDistance = DRAW_RANGE
	reel.Enabled = false
	reel.Adornee = holder
	reel.Parent = holder
	local picture = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = reel })
	return {
		Model = model,
		Base = base,
		Scale = scale,
		Lid = lid,
		Parts = parts,
		Beam = nil,
		Core = nil,
		Top = nil,
		Light = light,
		Leaves = leaves,
		Sparks = sparks,
		Reel = reel,
		ReelPicture = picture,
		Result = result,
		Delay = delay,
		Prize = nil,
		PrizeFrom = nil,
		Ticks = 0,
		Burst = false,
		Revealed = false,
	}
end

-- The beam of light out of the open crate: a wide soft ribbon and a bright core, both facing the camera.
local function addBeam(crate: Crate)
	local holder = crate.Light.Parent :: BasePart
	local bottom = Instance.new("Attachment")
	bottom.Parent = holder
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, BEAM_HEIGHT * math.max(crate.Scale, 0.6), 0)
	top.Parent = holder
	local function beam(width: number, transparency: number): Beam
		local made = Instance.new("Beam")
		made.Attachment0 = bottom
		made.Attachment1 = top
		made.FaceCamera = true
		made.LightEmission = 1
		made.LightInfluence = 0
		made.Segments = 2
		made.Width0 = width * math.max(crate.Scale, 0.6)
		made.Width1 = width * 1.8 * math.max(crate.Scale, 0.6)
		made.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, transparency),
			NumberSequenceKeypoint.new(0.55, math.min(1, transparency + 0.3)),
			NumberSequenceKeypoint.new(1, 1),
		})
		made.Parent = holder
		return made
	end
	crate.Beam = beam(2.6, 0.35)
	crate.Core = beam(0.9, 0.05)
	crate.Top = top
end

local function setBeam(crate: Crate, color: Color3, strength: number)
	local white = color:Lerp(Color3.new(1, 1, 1), 0.55)
	if crate.Beam then
		crate.Beam.Color = ColorSequence.new(color)
		crate.Beam.Brightness = 2 * strength
	end
	if crate.Core then
		crate.Core.Color = ColorSequence.new(white)
		crate.Core.Brightness = 3 * strength
	end
	crate.Light.Color = color
end

local function reelPicture(crate: Crate, id: string)
	for _, child in crate.ReelPicture:GetChildren() do
		child:Destroy()
	end
	if id == "Coins" then
		UIKit.Label({
			Text = Theme.CoinIcon,
			TextScaled = true,
			Size = UDim2.fromScale(1, 1),
			Parent = crate.ReelPicture,
		})
	else
		CrateTheme.Picture(id, crate.ReelPicture)
	end
end

-- A random thing to flash in the reel: any season item, or coins.
local reelPool: { string } = {}
for _, item in Seasons.Items do
	if Seasons.InCrates(item.Id) then
		table.insert(reelPool, item.Id)
	end
end

-- The prize, rising out of the crate: a pet or hat as its model, anything else as a card.
local function addPrize(crate: Crate, color: Color3)
	local result = crate.Result
	local season = Seasons.CurrentSeason()
	local height = 3.55 * crate.Scale
	local from = crate.Base * CFrame.new(0, height + 1.5 * math.max(crate.Scale, 0.6), 0)
	crate.PrizeFrom = from
	local item = result.Item
	local model: Model? = nil
	if item then
		local info = season.PetInfo[item]
		local prop = if info then info.Prop else Seasons.HatProps[item]
		local source = prop and template(prop)
		if source then
			model = source:Clone()
		end
	end
	if model then
		model:PivotTo(CFrame.new())
		local size = model:GetExtentsSize()
		local fit = (if result.Tier == "Pet" then 3.2 else 2.4) * math.max(crate.Scale, 0.6)
		model:ScaleTo(model:GetScale() * fit / math.max(size.X, size.Y, size.Z, 0.1))
		model:PivotTo(from)
		model.Parent = crate.Model
		crate.Prize = model
		return
	end
	-- A card: the title in its own look, an effect's picture, or the coins.
	local holder = Instance.new("Part")
	holder.Name = "Prize"
	holder.Size = Vector3.one * 0.2
	holder.Transparency = 1
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CFrame = from
	holder.Parent = crate.Model
	local gui = Instance.new("BillboardGui")
	local big = math.max(crate.Scale, 0.6)
	gui.Size = UDim2.fromScale((if result.Tier == "Title" then 9 else 4.4) * big, 4.4 * big)
	gui.LightInfluence = 0
	gui.MaxDistance = DRAW_RANGE
	gui.Adornee = holder
	gui.Parent = holder
	if result.Tier == "Title" then
		local colors = CrateTheme.Colors(season)
		UIKit.Label({
			Text = CrateTheme.NameOf(item or season.Title),
			Font = Theme.Fonts.Display,
			TextScaled = true,
			Size = UDim2.fromScale(1, 0.7),
			Position = UDim2.fromScale(0, 0.15),
			Parent = gui,
			Children = {
				UIKit.new("UIGradient", {
					Color = ColorSequence.new(colors.Gold, colors.Main),
					Rotation = 90,
				}),
				UIKit.new("UIStroke", { Color = colors.Title, Thickness = 3, Transparency = 0.2 }),
			},
		})
	elseif item then
		local card = UIKit.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(28, 15, 46),
			BackgroundTransparency = 0.15,
			Size = UDim2.fromScale(1, 1),
			Parent = gui,
			Children = { UIKit.Corner(24), UIKit.new("UIStroke", { Color = color, Thickness = 4 }) },
		})
		CrateTheme.Picture(item, card, { Size = UDim2.fromScale(0.78, 0.78) })
	else
		UIKit.Label({
			Text = `+{result.Coins}`,
			Font = Theme.Fonts.Display,
			TextScaled = true,
			TextColor3 = Theme.Colors.Coin,
			Size = UDim2.fromScale(1, 0.62),
			Parent = gui,
			Children = { UIKit.TextStroke(0.1) },
		})
		UIKit.Label({
			Text = Theme.CoinIcon,
			TextScaled = true,
			Position = UDim2.fromScale(0.3, 0.6),
			Size = UDim2.fromScale(0.4, 0.4),
			Parent = gui,
		})
	end
	crate.Prize = holder
end

local function nameLabel(active: Active, position: Vector3, text: string, color: Color3)
	local holder = Instance.new("Part")
	holder.Name = "Label"
	holder.Size = Vector3.one * 0.2
	holder.Transparency = 1
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CFrame = CFrame.new(position)
	holder.Parent = active.Folder
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(420, 70)
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	gui.Adornee = holder
	gui.Parent = holder
	UIKit.Label({
		Text = text,
		Font = Theme.Fonts.Display,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
		Children = {
			UIKit.new("UIStroke", { Color = color:Lerp(Color3.new(0, 0, 0), 0.5), Thickness = 3 }),
			UIKit.new("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), color), Rotation = 90 }),
		},
	})
	active.Label = gui
	UIKit.PopIn(gui:FindFirstChildOfClass("TextLabel") :: TextLabel, 0.35)
end

local function shockwave(active: Active, at: CFrame, color: Color3)
	local ring = Instance.new("Part")
	ring.Name = "Shock"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.3
	ring.Size = Vector3.new(0.12, 1, 1)
	ring.CFrame = at * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = active.Folder
	active.Shock = ring
end

-- Starts a show (the server's "Show" message).
function CrateShow.Play(show: { [string]: any })
	local elapsed = workspace:GetServerTimeNow() - (tonumber(show.At) or 0)
	local duration = tonumber(show.Duration) or 5.2
	if elapsed > duration - 0.3 or type(show.Results) ~= "table" then
		return -- (over already: someone who joined during it)
	end
	local altar = if (show.Altar or 0) > 0 then altarModel(show.Altar) else nil
	local head = headOf(show.UserId)
	local anchor: CFrame
	if altar then
		local crate = altar:FindFirstChild("AltarCrate")
		anchor = if crate and crate:IsA("Model") then crate:GetPivot() else altar:GetPivot() * CFrame.new(0, 1.35, 0)
	elseif head then
		local look = head.CFrame.LookVector
		anchor = CFrame.lookAt(
			head.Position + Vector3.new(0, 2.4, 0),
			head.Position + Vector3.new(0, 2.4, 0) - Vector3.new(look.X, 0, look.Z)
		)
	else
		return
	end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - anchor.Position).Magnitude > DRAW_RANGE then
		return
	end
	local showFolder = Instance.new("Folder")
	showFolder.Name = `Show{show.Id}`
	showFolder.Parent = showsFolder()
	local entry: Active = {
		Show = show,
		Start = os.clock() - math.max(0, elapsed),
		Crates = {},
		Altar = altar,
		Hidden = {},
		Ring = {},
		RingColors = {},
		AltarLight = nil,
		Label = nil,
		Shock = nil,
		Folder = showFolder,
		Ended = false,
	}
	-- The altar's own crate and key hide while the show plays.
	if altar then
		for _, name in { "AltarCrate", "FloatingKey" } do
			local model = altar:FindFirstChild(name)
			if model then
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") then
						part.LocalTransparencyModifier = 1
						table.insert(entry.Hidden, part)
					end
				end
			end
		end
		for _, part in altar:GetDescendants() do
			if part:IsA("BasePart") and part.Name == "Ring" then
				table.insert(entry.Ring, part)
				entry.RingColors[part] = part.Color
			elseif part:IsA("PointLight") and part.Name == "AltarLight" then
				entry.AltarLight = part
			end
		end
	end
	local results = show.Results
	local count = #results
	for index, result in results do
		local base, scale
		if count == 1 then
			base, scale = anchor, if altar then 1 else 0.55
		else
			local x = (index - (count + 1) / 2) * 2.3
			local lift = if altar then 2.6 - math.abs(x) * 0.12 else 1.2
			base = anchor * CFrame.new(x, lift, -math.abs(x) * 0.25) * CFrame.Angles(0, -x * 0.08, 0)
			scale = if altar then 0.6 else 0.42
		end
		table.insert(entry.Crates, newCrate(showFolder, base, scale, result, (index - 1) * 0.12))
	end
	table.insert(active, entry)
	if CrateShow.Started then
		CrateShow.Started(show, anchor.Position)
	end
end

local function finish(entry: Active)
	entry.Ended = true
	for _, part in entry.Hidden do
		part.LocalTransparencyModifier = 0
	end
	for part, color in entry.RingColors do
		part.Color = color
	end
	if entry.AltarLight then
		entry.AltarLight.Brightness = 0.9
	end
	entry.Folder:Destroy()
end

local function stepCrate(entry: Active, crate: Crate, t: number, reduced: boolean)
	local show = entry.Show
	local revealAt = tonumber(show.RevealAt) or 3.4
	local duration = tonumber(show.Duration) or 5.2
	local season = Seasons.CurrentSeason()
	local tierColor = CrateTheme.TierColor(crate.Result.Tier or "Coins", season)
	local local_t = t - crate.Delay
	if local_t < 0 then
		return
	end
	-- Rattle, light leaking under the lid.
	if local_t < RATTLE_END then
		local shake = if reduced then 0 else (1 - local_t / RATTLE_END) * 0.08 + 0.03
		crate.Model:PivotTo(
			crate.Base * CFrame.Angles(math.sin(local_t * 70) * shake, 0, math.cos(local_t * 63) * shake)
		)
		crate.Light.Brightness = local_t / RATTLE_END * 2
		return
	end
	if not crate.Burst then
		crate.Burst = true
		crate.Model:PivotTo(crate.Base)
		for _, lid in crate.Lid do
			lid.From = lid.Part.CFrame
		end
		crate.Leaves:Emit(if reduced then 12 else 40)
		crate.Sparks.Color = ColorSequence.new(Color3.fromRGB(255, 220, 150), Color3.fromRGB(255, 140, 50))
		crate.Sparks:Emit(if reduced then 8 else 26)
		addBeam(crate)
		setBeam(crate, Color3.fromRGB(255, 210, 150), 1)
		crate.Reel.Enabled = true
		if crate == entry.Crates[1] then
			shockwave(entry, crate.Base * CFrame.new(0, 0.3, 0), Color3.fromRGB(255, 200, 130))
		end
	end
	-- The lid flies off and fades.
	local flight = local_t - RATTLE_END
	for _, lid in crate.Lid do
		local k = math.clamp(flight / 1.1, 0, 1)
		local offset = lid.Fling * k + Vector3.new(0, -workspace.Gravity * 0.05 * (flight ^ 2), 0)
		lid.Part.CFrame = CFrame.new(offset)
			* lid.From
			* CFrame.Angles(lid.Spin.X * flight, lid.Spin.Y * flight, lid.Spin.Z * flight)
		lid.Part.LocalTransparencyModifier = math.clamp((flight - 0.35) / 0.6, 0, 1)
	end
	-- The burst's light, then the reel.
	if local_t < BURST_END then
		crate.Light.Brightness = 2 + (1 - (local_t - RATTLE_END) / (BURST_END - RATTLE_END)) * 6
		return
	end
	if local_t < revealAt then
		-- The reel slows: a tick every 0.07 s at first, 0.4 s at the end (the gap grows evenly, so the
		-- ticks so far are the integral of 1 / gap).
		local span = revealAt - BURST_END
		local p = (local_t - BURST_END) / span
		local first, last = 0.07, 0.4
		local ticks = math.floor(span / (last - first) * math.log((first + (last - first) * p) / first))
		if ticks ~= crate.Ticks then
			crate.Ticks = ticks
			local tier = REEL_TIERS[ticks % #REEL_TIERS + 1]
			setBeam(crate, CrateTheme.TierColor(tier, season), 0.9)
			local id = if tier == "Coins" then "Coins" else reelPool[rng:NextInteger(1, #reelPool)]
			reelPicture(crate, id)
			for _, part in entry.Ring do
				part.Color = CrateTheme.TierColor(tier, season)
			end
			if crate == entry.Crates[1] and CrateShow.Tick then
				CrateShow.Tick(p, crate.Base.Position)
			end
		end
		crate.Light.Brightness = 2.5
		return
	end
	-- The reveal.
	if not crate.Revealed then
		crate.Revealed = true
		crate.Reel.Enabled = false
		setBeam(crate, tierColor, 1.6)
		crate.Sparks.Color = ColorSequence.new(tierColor, Color3.new(1, 1, 1))
		crate.Sparks:Emit(if reduced then 14 else 60)
		addPrize(crate, tierColor)
		for _, part in entry.Ring do
			part.Color = tierColor
		end
		if crate == entry.Crates[1] then
			shockwave(entry, crate.Base * CFrame.new(0, 0.3, 0), tierColor)
			local result = crate.Result
			local name = if result.Item then string.upper(CrateTheme.NameOf(result.Item)) else `{result.Coins} COINS`
			local words = if #entry.Crates > 1
				then `{show.Name} opened {#entry.Crates} crates!`
				else `{show.Name} unboxed {name}!`
			nameLabel(entry, crate.Base.Position + Vector3.new(0, 3.55 * crate.Scale + 7.5, 0), words, tierColor)
			if CrateShow.Landed then
				CrateShow.Landed(show, crate.Base.Position, tierColor)
			end
			if CrateShow.Revealed then
				CrateShow.Revealed(show)
			end
		end
	end
	local r = local_t - revealAt
	local rest = duration - revealAt
	crate.Light.Brightness = 3 + math.sin(r * 8) * 0.5
	local prize = crate.Prize
	local from = crate.PrizeFrom
	if prize and from then
		-- Rise and turn, then float to the opener and shrink away.
		local rise = ease(r / 0.6)
		local spot = from * CFrame.new(0, rise * 2.2 * math.max(crate.Scale, 0.6), 0) * CFrame.Angles(0, r * 2.4, 0)
		local fly = math.clamp((r - (rest - 0.9)) / 0.8, 0, 1)
		local head = headOf(show.UserId)
		if fly > 0 and head then
			local target = head.Position + Vector3.new(0, 1.5, 0)
			spot = spot:Lerp(CFrame.new(target) * spot.Rotation, ease(fly))
		end
		if prize:IsA("Model") then
			prize:PivotTo(spot)
			if fly > 0 then
				for _, part in prize:GetDescendants() do
					if part:IsA("BasePart") then
						part.LocalTransparencyModifier = fly
					end
				end
			end
		elseif prize:IsA("BasePart") then
			prize.CFrame = spot
			local gui = prize:FindFirstChildOfClass("BillboardGui")
			if gui and fly > 0 then
				local base = gui:GetAttribute("PP_Size") or gui.Size
				gui:SetAttribute("PP_Size", base)
				gui.Size = UDim2.fromScale(
					(base :: UDim2).X.Scale * (1 - fly * 0.8),
					(base :: UDim2).Y.Scale * (1 - fly * 0.8)
				)
			end
		end
	end
	-- The crate and the beam fade out at the end.
	local fade = math.clamp((r - (rest - 0.6)) / 0.5, 0, 1)
	if fade > 0 then
		for _, part in crate.Parts do
			if part.Parent and string.sub(part.Name, 1, 3) ~= "Lid" then
				part.LocalTransparencyModifier = fade
			end
		end
		setBeam(crate, tierColor, 1.6 * (1 - fade))
		crate.Light.Brightness = 3 * (1 - fade)
	end
end

local function step()
	local now = os.clock()
	local reduced = State.ReducedEffects()
	for index = #active, 1, -1 do
		local entry = active[index]
		local t = now - entry.Start
		local duration = tonumber(entry.Show.Duration) or 5.2
		if t >= duration or not entry.Folder.Parent then
			table.remove(active, index)
			finish(entry)
			continue
		end
		for _, crate in entry.Crates do
			stepCrate(entry, crate, t, reduced)
		end
		if entry.AltarLight then
			entry.AltarLight.Brightness = if t < BURST_END then 0.9 + t * 6 else 2.5
		end
		local shock = entry.Shock
		if shock then
			local born = shock:GetAttribute("PP_Born") or t
			shock:SetAttribute("PP_Born", born)
			local k = math.clamp((t - born) / 0.55, 0, 1)
			local size = 1 + k * 14
			shock.Size = Vector3.new(0.12, size, size)
			shock.Transparency = 0.3 + 0.7 * k
			if k >= 1 then
				shock:Destroy()
				entry.Shock = nil
			end
		end
	end
end

-- A tick of the reel (CrateController plays the sound near it: p goes 0 to 1 as it slows).
CrateShow.Tick = nil :: ((p: number, position: Vector3) -> ())?

function CrateShow.Start()
	RunService.RenderStepped:Connect(step)
end

return CrateShow
