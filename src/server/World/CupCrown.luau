-- The PARTY CUP champion's crown (owner, asked "If you could do 5 things to keep players addicted
-- what would you do?", got "the champion wears a crown in the lobby until the next cup ends" with
-- the Party Cups, then: "Can you work on all of that? this wont mess with what the other workers
-- are working on right?"). Services/CupService puts it on the champion in the lobby.
--
-- A golden band with five points, a party-coloured pearl on each and a pink gem at the front,
-- sized to the head it sits on. It's welded to the head and is only decoration: no collisions,
-- touches or ray hits, no mass, no shadow, so nothing in the lobby (the obby, the beach balls, the
-- secret token, Skee-Ball) treats it as part of the player's body. It goes inside the character, so
-- it goes with it (a reset, leaving), and the camera fades it with the character in first person.

local CupCrown = {}

CupCrown.Name = "PP_CupCrown"

local GOLD = Color3.fromRGB(255, 200, 45)
local GOLD_DARK = Color3.fromRGB(226, 140, 24)
local GEM = Color3.fromRGB(255, 92, 170)
local PEARLS = {
	Color3.fromRGB(80, 205, 255),
	Color3.fromRGB(110, 230, 140),
	Color3.fromRGB(255, 240, 220),
	Color3.fromRGB(150, 110, 255),
	Color3.fromRGB(255, 212, 70),
}
local POINTS = 5

-- A piece of the crown at `offset` from the head, welded to it.
local function piece(model: Model, head: BasePart, props: { [string]: any }, offset: CFrame): BasePart
	local part = Instance.new("Part")
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(part :: any)[key] = value
	end
	part.CFrame = head.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = head
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
	part.Parent = model
	return part
end

-- Puts a crown on `character`'s head (none without a head). Returns it.
function CupCrown.Attach(character: Model): Model?
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end
	local old = character:FindFirstChild(CupCrown.Name)
	if old then
		old:Destroy()
	end
	-- Sized to the head (heads differ from avatar to avatar), sitting a little into its top.
	local w = math.clamp(head.Size.X, 0.8, 2.4)
	local base = head.Size.Y / 2 - 0.1 * w -- the band's bottom, from the head's middle
	local radius = 0.43 * w
	local bandHeight = 0.24 * w
	local top = base + bandHeight

	local model = Instance.new("Model")
	model.Name = CupCrown.Name
	local upright = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder's length runs along its X
	local band = piece(model, head, {
		Name = "Band",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(bandHeight, 2 * radius, 2 * radius),
		Color = GOLD,
		Reflectance = 0.2,
	}, CFrame.new(0, base + bandHeight / 2, 0) * upright)
	model.PrimaryPart = band
	piece(model, head, {
		Name = "Rim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.07 * w, 2 * radius + 0.06 * w, 2 * radius + 0.06 * w),
		Color = GOLD_DARK,
	}, CFrame.new(0, base + 0.035 * w, 0) * upright)

	-- The points: diamonds standing on the band's top edge, set in far enough that their lower
	-- halves hide inside it, so a triangle shows above it; a pearl on each tip. The first one faces
	-- the front.
	local side = 0.26 * w
	local tip = top + side / math.sqrt(2)
	local edge = radius - 0.065 * w
	for index = 1, POINTS do
		local angle = math.rad(90 + (index - 1) * 360 / POINTS)
		local out = Vector3.new(math.cos(angle), 0, -math.sin(angle)) -- the head's front is -Z
		local facing = CFrame.lookAt(Vector3.zero, out)
		piece(model, head, {
			Name = "Point",
			Size = Vector3.new(side, side, 0.05 * w),
			Color = GOLD,
			Reflectance = 0.2,
		}, CFrame.new(out * edge + Vector3.new(0, top, 0)) * facing * CFrame.Angles(0, 0, math.rad(45)))
		piece(model, head, {
			Name = "Pearl",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.11 * w,
			Color = PEARLS[(index - 1) % #PEARLS + 1],
		}, CFrame.new(out * edge + Vector3.new(0, tip, 0)))
	end
	piece(model, head, {
		Name = "Gem",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.14 * w,
		Color = GEM,
		Material = Enum.Material.Neon,
	}, CFrame.new(0, base + bandHeight / 2, -radius))
	model.Parent = character
	return model
end

-- Takes the crown off `character`, if it wears one.
function CupCrown.Remove(character: Model?)
	local crown = character and character:FindFirstChild(CupCrown.Name)
	if crown then
		crown:Destroy()
	end
end

return CupCrown
