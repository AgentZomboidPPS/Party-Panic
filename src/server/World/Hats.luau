-- The hats players wear (the Hat cosmetic slot; owner, offered "free limited rewards like a pumpkin
-- hat" for the Halloween event, then: "do pumpkin hat now"). Services/CosmeticService decides when
-- one is worn (in the lobby; not in the rounds its wearer plays, nor under the PARTY CUP crown) and
-- calls Attach and Remove here.
--
-- A hat is a real Accessory on the head: its Handle (the hat's main mesh, from World/Props/Hats via
-- MeshLibrary) with every other piece welded to it, put on with Humanoid:AddAccessory at the head's
-- HatAttachment, so it follows the head through every animation, on R15 and R6 alike (a head
-- without that attachment gets one at its top). It's sized to the head it sits on (heads differ
-- from avatar to avatar) and is only decoration: no mass, no collisions, touches or ray hits, so
-- nothing in the lobby (the obby, the beach balls, the secret token, Skee-Ball) treats it as part
-- of the player's body.
--
-- The PUMPKIN HAT (the HALLOWEEN PARTY's headline reward): a carved jack-o'-lantern 1.3 heads wide,
-- sitting a little down over the top of the head, its face looking where the wearer looks, with a
-- soft warm light inside.
--
-- The GOLD PASS's hats (owner: "Also we do need a paid battle pass too. I like the current free one.
-- But the paid one should also be insane."; Shared/GoldPass, meshes in World/Props/GoldHats): the
-- GOLD PARTY HAT, the ROYAL CROWN (its gems glowing, a little gold glitter), the GOLDEN HALO (a
-- glowing ring that floats above the head: a hat that sits up off it, Sink below 0), the GILDED TOP
-- HAT and the SUN KING CROWN (a bright gem, a warm light and gold glitter). Glitter is a slow
-- sparkle emitter on the hat (PP_GoldGlitter: off on a device with reduced effects).

local CollectionService = game:GetService("CollectionService")

local MeshLibrary = require(script.Parent.MeshLibrary)

local Hats = {}

Hats.Name = "PP_Hat" -- the Accessory's name in the character

type Look = {
	Prop: string, -- World/Props/Hats
	Handle: string, -- the piece that becomes the Handle (the hat's biggest)
	Width: number, -- how wide it's worn, in head widths
	Sink: number, -- how far its bottom sits down over the top of the head, in head widths (below 0: above it)
	Glow: string?, -- the piece the light is in
	Light: { Color: Color3, Brightness: number, Range: number }?, -- Range in head widths
	Glitter: { Color: Color3, Rate: number }?, -- gold sparkles drifting off it
}

local GLITTER_TAG = "PP_GoldGlitter" -- (Controllers/GoldPassController switches them off with reduced effects)

local LOOKS: { [string]: Look } = {
	Hat_Pumpkin = {
		Prop = "PumpkinHat",
		Handle = "HatShell",
		Width = 1.3,
		Sink = 0.2,
		Glow = "HatGlow",
		Light = { Color = Color3.fromRGB(255, 170, 70), Brightness = 0.9, Range = 4.5 },
	},
	-- The GOLD PASS's hats.
	Hat_GoldParty = { Prop = "GoldPartyHat", Handle = "PartyGold", Width = 0.62, Sink = 0.04 },
	Hat_RoyalCrown = {
		Prop = "RoyalCrown",
		Handle = "CrownGold",
		Width = 0.95,
		Sink = 0.2,
		Glow = "CrownRuby",
		Light = { Color = Color3.fromRGB(255, 205, 120), Brightness = 0.6, Range = 4 },
		Glitter = { Color = Color3.fromRGB(255, 228, 130), Rate = 4 },
	},
	Hat_GoldenHalo = {
		Prop = "GoldenHalo",
		Handle = "HaloRing",
		Width = 0.8,
		Sink = -0.32,
		Glow = "HaloRing",
		Light = { Color = Color3.fromRGB(255, 214, 90), Brightness = 1, Range = 5 },
		Glitter = { Color = Color3.fromRGB(255, 240, 170), Rate = 3 },
	},
	Hat_GildedTopHat = { Prop = "GildedTopHat", Handle = "TopHatBody", Width = 1.1, Sink = 0.1 },
	Hat_SunKing = {
		Prop = "SunKingCrown",
		Handle = "SunGold",
		Width = 1.3,
		Sink = 0.16,
		Glow = "SunGem",
		Light = { Color = Color3.fromRGB(255, 200, 90), Brightness = 1.2, Range = 6 },
		Glitter = { Color = Color3.fromRGB(255, 220, 110), Rate = 7 },
	},
}

-- Whether there's a hat to build for this cosmetic.
function Hats.Has(itemId: string): boolean
	return LOOKS[itemId] ~= nil
end

-- How wide the head looks: an R15 head's part is as wide as it looks; R6's classic head is a
-- 2 x 1 x 1 part drawn by a "Head" SpecialMesh as a head about 1.25 x its height.
local function headWidth(head: BasePart): number
	local mesh = head:FindFirstChildWhichIsA("SpecialMesh")
	local width = if mesh and mesh.MeshType == Enum.MeshType.Head
		then math.min(head.Size.X, head.Size.Y, head.Size.Z) * math.min(mesh.Scale.X, mesh.Scale.Z)
		else head.Size.X
	return math.clamp(width, 0.6, 3)
end

-- The head's HatAttachment (made at its top if the head has none).
local function hatAttachment(head: BasePart): Attachment
	local found = head:FindFirstChild("HatAttachment")
	if found and found:IsA("Attachment") then
		return found
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "HatAttachment"
	attachment.Position = Vector3.new(0, headWidth(head) / 2, 0)
	attachment.Parent = head
	return attachment
end

-- The id of the hat `character` wears, if any.
function Hats.Worn(character: Instance?): string?
	local hat = character and character:FindFirstChild(Hats.Name)
	local id = hat and hat:GetAttribute("PP_Hat")
	return if type(id) == "string" then id else nil
end

-- Takes `character`'s hat off, if it wears one.
function Hats.Remove(character: Instance?)
	local hat = character and character:FindFirstChild(Hats.Name)
	if hat then
		hat:Destroy()
	end
end

-- Puts the hat for cosmetic `itemId` on `character` (in place of any it wears). Returns it, or nil
-- for a character without a head or humanoid. Yields the first time a hat's mesh loads.
function Hats.Attach(character: Model, itemId: string): Accessory?
	local look = LOOKS[itemId]
	local head = character:FindFirstChild("Head")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not look or not head or not head:IsA("BasePart") or not humanoid then
		return nil
	end
	local model = MeshLibrary.Get(look.Prop)
	if not character.Parent or character:FindFirstChild("Head") ~= head then
		model:Destroy() -- (the character went while the mesh loaded)
		return nil
	end
	local handle = model:FindFirstChild(look.Handle, true)
	if not handle or not handle:IsA("BasePart") then
		model:Destroy()
		error(`{look.Prop} has no {look.Handle}`)
	end
	-- Sized by its widest piece, the Handle (the pumpkin itself).
	local width = headWidth(head)
	model:ScaleTo(model:GetScale() * look.Width * width / math.max(math.max(handle.Size.X, handle.Size.Z), 0.01))
	local pivot = model:GetPivot() -- the middle of its bottom, its front looking along -Z

	local accessory = Instance.new("Accessory")
	accessory.Name = Hats.Name
	accessory.AccessoryType = Enum.AccessoryType.Hat
	accessory:SetAttribute("PP_Hat", itemId)
	-- (An uploaded mesh's pieces come wrapped in nodes of their own: the pieces are all that's kept.)
	local others: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end
		local part = descendant :: BasePart
		part.Anchored = false
		part.Massless = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = part.Name ~= look.Glow
		if part ~= handle then
			local weld = Instance.new("Weld")
			weld.Part0 = handle
			weld.Part1 = part
			weld.C0 = handle.CFrame:ToObjectSpace(part.CFrame)
			weld.Parent = part
			table.insert(others, part)
		end
	end
	-- Where the head's HatAttachment meets the hat: a little up from the middle of its bottom, so
	-- the hat sits down over the top of the head, facing the way the head faces.
	local attachment = Instance.new("Attachment")
	attachment.Name = "HatAttachment"
	attachment.CFrame = handle.CFrame:ToObjectSpace(pivot * CFrame.new(0, look.Sink * width, 0))
	attachment.Parent = handle
	local glow = look.Glow and look.Light and model:FindFirstChild(look.Glow, true)
	if glow and look.Light then
		local light = Instance.new("PointLight")
		light.Color = look.Light.Color
		light.Brightness = look.Light.Brightness
		light.Range = look.Light.Range * width
		light.Shadows = false
		light.Parent = glow
	end
	if look.Glitter then
		local glitter = Instance.new("ParticleEmitter")
		glitter.Name = "Glitter"
		glitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		glitter.Color = ColorSequence.new(look.Glitter.Color)
		glitter.LightEmission = 1
		glitter.Size = NumberSequence.new(0.3 * width, 0)
		glitter.Transparency = NumberSequence.new(0.1, 1)
		glitter.Lifetime = NumberRange.new(0.8, 1.4)
		glitter.Rate = look.Glitter.Rate
		glitter.Speed = NumberRange.new(0.3, 1)
		glitter.SpreadAngle = Vector2.new(180, 180)
		glitter.Acceleration = Vector3.new(0, 0.6, 0)
		glitter.Drag = 1
		glitter.Parent = handle
		CollectionService:AddTag(glitter, GLITTER_TAG)
	end
	handle.Name = "Handle"
	handle.Parent = accessory
	for _, part in others do
		part.Parent = handle
	end
	model:Destroy()

	Hats.Remove(character)
	hatAttachment(head)
	local made, seat = handle.Size, attachment.CFrame
	humanoid:AddAccessory(accessory)
	-- On R15 the engine scales an accessory's Handle (not the pieces welded to it) to the avatar's
	-- proportions. This hat is already sized to this head, so it goes back the way it was made.
	if (handle.Size - made).Magnitude > 1e-3 then
		handle.Size = made
		attachment.CFrame = seat
	end
	return accessory
end

return Hats
