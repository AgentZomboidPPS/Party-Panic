-- Props for Capy Go Boom. MeshLibrary loads this file at startup. Get one with
-- MeshLibrary.Get("CapyBoomRock", { CFrame = ..., Parent = ctx.Arena }).
--
-- Borrowed from the owner's CAPY GO BOOM (owner: "Why don't you borrow assets from the capy go boom repo?"):
--   * the capybara is that game's CapyMeshTemplate: six textured meshes (body, head, four legs) placed
--     exactly as its template has them (feet on the pivot, facing -Z), and the snack cannon on its front
--     is that game's starter blaster (seven meshes, where its Blaster.MountOffset puts it; "tail_geom",
--     the old stand-in the cannon covers there, is left out);
--   * the snacks are that game's FoodTemplates (twelve foods: strawberry, banana, pizza, burger, ...),
--     made small, tasty, big or golden by the weight they give (Shared/Logic/CapyGoBoom).
-- They are plain uploaded meshes and images, not Models, so each piece is made with
-- AssetService:CreateMeshPartAsync when the prop is first built. The capybara and cannon meshes are the
-- owner's (user 11690979745) and the game must be allowed to use them (assets/capy_borrowed_assets.json,
-- tools/asset_permissions.py); the foods and the sounds are public assets of other creators.
-- If a mesh can't be loaded the prop falls back to rounded parts, so a round never loses its art.
--
-- Only the standing stones collide (owner: "Theres invisible stuff you can jump on and hang on in
-- several games"): a pillar and a ball cap, each collision its own drawn shape. The capys, snacks and
-- shells are drawn by clients and never solid.
local AssetService = game:GetService("AssetService")

local WHITE = Color3.new(1, 1, 1)
local TURNED = CFrame.Angles(0, math.pi, 0) -- the original's meshes are all placed turned half a way round

-- A mesh piece (one uploaded mesh, optionally textured) in `parent`, or nil if it won't load.
local function meshPiece(
	parent: Instance,
	name: string,
	meshId: number,
	textureId: number?,
	cframe: CFrame,
	color: Color3?,
	material: Enum.Material?
): MeshPart?
	local ok, part = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromUri(`rbxassetid://{meshId}`))
	end)
	if not ok or not part then
		return nil
	end
	part.Name = name
	part.Anchored = true
	part.Color = color or WHITE -- (a textured mesh is tinted by its colour: white leaves the texture as it is)
	if material then
		part.Material = material
	end
	if textureId then
		pcall(function()
			part.TextureID = `rbxassetid://{textureId}`
		end)
	end
	part.CFrame = cframe
	part.Parent = parent
	return part
end

-- CapyMeshTemplate: { name, mesh, texture, position }. The feet are on the pivot, the capy faces -Z.
local CAPY_PIECES = {
	{ "CapyBody", 93080775099861, 94036230022220, Vector3.new(0.007, 1.482, 0.424) },
	{ "CapyHead", 129803482539166, 98518208765254, Vector3.new(0.001, 3.551, -0.038) },
	{ "LegFL", 94470541936062, 118276124672525, Vector3.new(-0.679, 0.491, -0.302) },
	{ "LegFR", 114806460309206, 79199450135378, Vector3.new(0.693, 0.488, -0.304) },
	{ "LegRL", 92683668509509, 115607277773652, Vector3.new(-0.732, 0.458, 1.342) },
	{ "LegRR", 135864579714444, 133554136749510, Vector3.new(0.75, 0.459, 1.341) },
}

-- The starter blaster (MeshLibrary.Blaster.starter): { name, mesh, centre in mount space, colour, material }.
-- The client recolours Housing, Light and Glow in each player's colour.
local CANNON_MOUNT = Vector3.new(0, 2.05, -1.8)
local CANNON_PIECES = {
	{ "CannonHousing", 134682802670582, Vector3.new(0.018, -0.277, -0.669), Color3.fromRGB(93, 215, 172) },
	{ "CannonFixed", 111155165276888, Vector3.new(0, -0.539, -0.398), WHITE },
	{
		"CannonGlow",
		96782858585902,
		Vector3.new(-0.087, 0.266, -0.19),
		Color3.fromRGB(129, 224, 190),
		Enum.Material.Neon,
	},
	{ "CannonLight", 84156306803704, Vector3.new(0, 0.065, -0.54), Color3.fromRGB(155, 230, 204) },
	{ "CannonMetal", 101369020676447, Vector3.new(-0.015, 0.235, -0.87), WHITE, Enum.Material.Metal },
	{ "CannonMuzzle", 122162773630250, Vector3.new(0, 0, -1.37), Color3.fromRGB(26, 61, 65) },
	{ "CannonTrim", 73917911948411, Vector3.new(0.12, 0.049, -0.93), Color3.fromRGB(255, 208, 75) },
}

-- One of the original's foods: its mesh and texture, and the height it is drawn at (chosen so the longest
-- side is about 1.5 to 3.4 studs; the client draws them a little bigger still).
local FOODS = {
	CapyBoomStrawberry = { 13031493968, 13031494080, 1.59, Color3.fromRGB(235, 60, 70) },
	CapyBoomBanana = { 13031536524, 13031536638, 2.0, Color3.fromRGB(255, 226, 95) },
	CapyBoomCarrot = { 13031525542, 13031525618, 0.59, Color3.fromRGB(250, 140, 50) },
	CapyBoomBlueberries = { 13031531853, 13031531935, 1.5, Color3.fromRGB(80, 90, 200) },
	CapyBoomAvocado = { 13031533727, 13031533789, 1.8, Color3.fromRGB(110, 170, 70) },
	CapyBoomPizza = { 13031501236, 13031501320, 0.39, Color3.fromRGB(250, 190, 70) },
	CapyBoomBurger = { 13031510157, 13031510247, 1.05, Color3.fromRGB(230, 160, 80) },
	CapyBoomIceCream = { 13031494318, 13031494414, 2.4, Color3.fromRGB(255, 170, 200) },
	CapyBoomPancakes = { 13031502546, 13031502622, 0.95, Color3.fromRGB(235, 180, 100) },
	CapyBoomOrange = { 13031502802, 13031502884, 1.83, Color3.fromRGB(255, 150, 40) },
	CapyBoomWatermelon = { 13031491806, 13031491872, 1.27, Color3.fromRGB(240, 80, 100) },
	CapyBoomGoldenApple = { 13031513098, 13031513175, 2.87, Color3.fromRGB(255, 205, 60) },
}

return function(h)
	-- A part turned to lie along Z (the rounded cannon).
	local function alongZ(part: BasePart, position: Vector3)
		part.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(90), 0)
		return part
	end

	-- The capybara from rounded parts: what a round uses if the meshes won't load.
	local function roundedCapy(m: Model)
		h.blob(m, "Body", Vector3.new(4.5, 3.1, 5.8), Vector3.new(0, 2, 0))
		h.blob(m, "Body", Vector3.new(3.6, 2.8, 3.3), Vector3.new(0, 2.65, -2.1)) -- the big square head
		h.blob(m, "Snout", Vector3.new(3.1, 1.65, 2), Vector3.new(0, 2, -3.1))
		h.blob(m, "Nose", Vector3.new(1.4, 0.5, 0.5), Vector3.new(0, 2.3, -3.95))
		for _, x in { -1, 1 } do
			for _, z in { -1.3, 1.5 } do
				h.blob(m, "Foot", Vector3.new(1.45, 1.6, 1.6), Vector3.new(x * 1.3, 0.8, z))
			end
			h.blob(m, "Body", Vector3.new(0.85, 0.95, 0.72), Vector3.new(x * 1.35, 4, -1.8)) -- an ear
			h.blob(m, "Eye", Vector3.new(0.34, 0.46, 0.34), Vector3.new(x * 1.61, 3, -2.8))
		end
		h.blob(m, "Orange", Vector3.new(1.36, 1.3, 1.36), Vector3.new(0, 4.45, -2.1))
		local leaf = h.blob(m, "Leaf", Vector3.new(0.7, 0.16, 0.33), Vector3.new(0.28, 5.08, -2.1))
		leaf.CFrame *= CFrame.Angles(0, 0, math.rad(18))
		-- The scarf round the neck, with a knot at the back.
		alongZ(h.roller(m, "Band", 3.5, 0.55, Vector3.new(0, 2.3, -1.15)), Vector3.new(0, 2.3, -1.15))
		h.blob(m, "Band", Vector3.new(0.9, 1.1, 0.7), Vector3.new(0, 1.7, -0.45))
		-- The snack cannon on its right side, pointing forward.
		alongZ(h.roller(m, "RoundCannon", 1.1, 2.5, Vector3.new(2.65, 2.1, -1.35)), Vector3.new(2.65, 2.1, -1.35))
		alongZ(h.roller(m, "RoundRim", 1.3, 0.25, Vector3.new(2.65, 2.1, -2.65)), Vector3.new(2.65, 2.1, -2.65))
	end

	-- The real capybara and its cannon from the original's meshes. False if the capybara's won't load
	-- (nothing is left in the model then); a cannon that won't load is replaced by a rounded one.
	local function meshCapy(m: Model): boolean
		local made: { BasePart } = {}
		for _, piece in CAPY_PIECES do
			local part = meshPiece(m, piece[1], piece[2], piece[3], CFrame.new(piece[4]) * TURNED)
			if not part then
				for _, other in made do
					other:Destroy()
				end
				return false
			end
			table.insert(made, part)
		end
		local cannon: { BasePart } = {}
		for _, piece in CANNON_PIECES do
			local at = CFrame.new(CANNON_MOUNT) * CFrame.new(piece[3]) * TURNED
			local part = meshPiece(m, piece[1], piece[2], nil, at, piece[4], piece[5])
			if not part then
				for _, other in cannon do
					other:Destroy()
				end
				cannon = {}
				alongZ(h.roller(m, "RoundCannon", 1.1, 2.1, Vector3.new(0, 2.05, -2.6)), Vector3.new(0, 2.05, -2.6))
				alongZ(h.roller(m, "RoundRim", 1.3, 0.25, Vector3.new(0, 2.05, -3.7)), Vector3.new(0, 2.05, -3.7))
				break
			end
			table.insert(cannon, part)
		end
		return true
	end

	local specs = {
		CapyBoomCapy = {
			Height = 5.0,
			AssetId = 0,
			Shadow = true,
			-- (Only the rounded fallback has colours of its own: the meshes' textures are left as they are.)
			Palette = {
				Body = h.rgb(198, 143, 84),
				Snout = h.rgb(173, 119, 67),
				Foot = h.rgb(150, 100, 58),
				Eye = h.rgb(35, 25, 21),
				Nose = h.rgb(77, 47, 30),
				Orange = h.rgb(255, 151, 33),
				Leaf = h.rgb(96, 192, 55),
				RoundCannon = h.rgb(130, 225, 174),
				RoundRim = h.rgb(247, 215, 117),
				Band = h.rgb(235, 70, 70),
			},
			Fallback = function(m)
				if not meshCapy(m) then
					roundedCapy(m)
				end
			end,
		},
		CapyBoomShell = {
			Height = 1.5,
			AssetId = 0,
			Shadow = false,
			Palette = { Shell = h.rgb(255, 255, 255), Core = h.rgb(255, 255, 255) },
			Materials = { Shell = Enum.Material.Neon, Core = Enum.Material.Neon },
			Fallback = function(m)
				h.ball(m, "Shell", 1.5, Vector3.new(0, 0.75, 0))
			end,
		},
		CapyBoomRock = {
			Height = 12.7,
			AssetId = 0,
			Collide = true,
			BlocksCamera = true,
			Palette = { Stone = h.rgb(150, 146, 152), Cap = h.rgb(168, 164, 170) },
			Materials = { Stone = Enum.Material.Slate, Cap = Enum.Material.Slate },
			Fallback = function(m)
				h.pillar(m, "Stone", 7.0, 9, Vector3.new(0, 4.5, 0))
				h.ball(m, "Cap", 7.4, Vector3.new(0, 9, 0))
			end,
		},
	}
	-- The foods: the real mesh, or a ball in the food's colour.
	for name, food in FOODS do
		specs[name] = {
			Height = food[3],
			AssetId = 0,
			Shadow = false,
			Palette = { FoodBall = food[4] },
			Fallback = function(m)
				if not meshPiece(m, "Food", food[1], food[2], CFrame.identity) then
					h.ball(m, "FoodBall", food[3], Vector3.new(0, food[3] / 2, 0))
				end
			end,
		}
	end
	return specs
end
