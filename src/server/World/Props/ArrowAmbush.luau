-- Props for Arrow Ambush, a storybook castle archery tournament: the archers' tower (blue-roofed
-- stair turret, banners, painted shields), the cover boards on rails, the bow and the arrow, and the
-- castle and festival around the courtyard (cobbles, low walls, turrets, curtain wall, tents, banner
-- poles, hay targets). Meshes come from tools/meshgen/props/ArrowAmbush.py; until they're uploaded
-- and approved the Fallback is used. Fallbacks keep the mesh's height (MeshLibrary scales a prop to
-- its Height) and never put two faces in one plane.
return function(h)
	local stone = h.rgb(232, 220, 200)
	local mortar = h.rgb(176, 164, 152)
	local trim = h.rgb(224, 192, 142) -- warm sandstone coping, so the merlons read against the stone
	local gold = h.rgb(255, 200, 70)
	local roof = h.rgb(72, 118, 222)
	local red = h.rgb(226, 62, 74)

	-- A cylinder facing Z (a disc on the front of a board).
	local function disc(m: Model, name: string, diameter: number, thickness: number, position: Vector3)
		return h.Build.Part({
			Name = name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(thickness, diameter, diameter),
			CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(90), 0),
			Parent = m,
		})
	end
	-- An invisible speck that stretches a fallback's bounding box to the mesh's (its pivot and height).
	local function speck(m: Model, position: Vector3, height: number?)
		local part = h.block(m, "Anchor", Vector3.new(0.1, height or 0.1, 0.1), position)
		part.Transparency = 1
		return part
	end
	-- A storybook cone roof as three stacked drums, from `y` up.
	local function drums(m: Model, name: string, diameter: number, y: number, height: number, center: Vector3?)
		local at = center or Vector3.zero
		local step = height / 3
		for k = 0, 2 do
			h.pillar(m, name, diameter * (1 - k * 0.3), step, at + Vector3.new(0, y + step * (k + 0.5), 0))
		end
	end

	return {
		ArcherTower = {
			Height = 34.84,
			AssetId = 130628218274897, -- tools/upload_assets.py --only ArcherTower fills this in
			Collide = false, -- the game puts a solid core under the deck
			Palette = {
				Mortar = mortar,
				Stone = stone,
				Trim = trim,
				Deck = h.rgb(186, 132, 86),
				Wood = h.rgb(150, 98, 60),
				Iron = h.rgb(64, 64, 74),
				Window = h.rgb(46, 36, 52),
				Roof = roof,
				Pole = gold,
				Flag = red,
				Banner = red,
				Emblem = gold,
				ShieldA = h.rgb(64, 128, 232),
				ShieldB = h.rgb(250, 246, 236),
			},
			Materials = {
				Mortar = Enum.Material.Slate,
				Stone = Enum.Material.Slate,
				Trim = Enum.Material.Slate,
				Deck = Enum.Material.WoodPlanks,
				Wood = Enum.Material.Wood,
				Iron = Enum.Material.Metal,
				Pole = Enum.Material.Metal,
				Flag = Enum.Material.Fabric,
				Banner = Enum.Material.Fabric,
			},
			Fallback = function(m)
				h.pillar(m, "Mortar", 12.6, 16, Vector3.new(0, 8, 0))
				h.pillar(m, "Trim", 14.7, 1.4, Vector3.new(0, 16.6, 0))
				for k = 0, 11 do
					local angle = k / 12 * math.pi * 2
					if k ~= 3 then -- (k = 3 is where the turret stands, at the back)
						h.rounded(
							m,
							"Trim",
							Vector3.new(1.8, 1.3, 1.8),
							0.2,
							Vector3.new(math.cos(angle) * 6.9, 17.9, math.sin(angle) * 6.9)
						)
					end
				end
				-- The stair turret at the back (+Z) with its roof, pole and pennant.
				local turret = Vector3.new(0, 0, 6.7)
				h.pillar(m, "Mortar", 5, 22.3, turret + Vector3.new(0, 11.25, 0))
				drums(m, "Roof", 6.4, 22.4, 8.6, turret)
				h.pillar(m, "Pole", 0.26, 3.2, turret + Vector3.new(0, 32.6, 0))
				h.ball(m, "Pole", 0.6, turret + Vector3.new(0, 34.5, 0))
				h.block(m, "Flag", Vector3.new(5, 2.2, 0.1), turret + Vector3.new(2.6, 33.4, 0))
				for _, side in { -1, 1 } do
					local banner = h.block(m, "Banner", Vector3.new(2.5, 6, 0.1), Vector3.zero)
					banner.CFrame = CFrame.new(side * 3.7, 10.4, -5.6) * CFrame.Angles(0, -side * math.rad(34), 0)
				end
				for _, x in { -10.2, 10.2 } do
					speck(m, Vector3.new(x, 0.05, 0))
					speck(m, Vector3.new(0, 0.05, x))
				end
			end,
		},
		TargetBoard = {
			Height = 7.79,
			AssetId = 99739879214802,
			Collide = false, -- the client moves boards; arrows are blocked by the server's own check
			Palette = {
				Wood = h.rgb(206, 156, 102),
				Frame = h.rgb(122, 82, 52),
				Iron = h.rgb(64, 64, 74),
				Wheels = h.rgb(96, 66, 44),
				ShieldRim = gold,
				Paint = h.rgb(64, 132, 232), -- the front shield and the back: the client paints it in the board's color
				Crest = gold,
				Face = h.rgb(252, 248, 238),
				Rings = h.rgb(232, 58, 58),
				Bull = h.rgb(255, 205, 60),
			},
			Materials = {
				Wood = Enum.Material.WoodPlanks,
				Frame = Enum.Material.Wood,
				Iron = Enum.Material.Metal,
				ShieldRim = Enum.Material.Metal,
				Paint = Enum.Material.WoodPlanks, -- painted planks: the grain shows through the board's color
				Crest = Enum.Material.Metal,
			},
			Fallback = function(m)
				h.rounded(m, "Wood", Vector3.new(6.2, 0.45, 2.5), 0.12, Vector3.new(0, 0.95, 0))
				for _, x in { -2.3, 2.3 } do
					h.roller(m, "Wheels", 1, 2.2, Vector3.new(x, 0.55, 0)).CFrame = CFrame.new(x, 0.55, 0)
						* CFrame.Angles(0, math.rad(90), 0)
					h.block(m, "Wood", Vector3.new(0.42, 1, 0.42), Vector3.new(x, 1.45, 0.45))
					for _, y in { 1.4, 7.6 } do
						h.ball(m, "Iron", 0.7, Vector3.new(x * 1.56, y, 0.05))
					end
				end
				h.rounded(m, "Wood", Vector3.new(7.2, 6.2, 0.5), 0.15, Vector3.new(0, 4.5, 0.05))
				h.block(m, "Paint", Vector3.new(5.6, 4.6, 0.09), Vector3.new(0, 4.6, -0.245))
				h.block(m, "Paint", Vector3.new(6.6, 5.6, 0.06), Vector3.new(0, 4.5, 0.36))
				-- The target's discs: each sticks out further in front and reaches further back.
				disc(m, "Face", 4.2, 0.44, Vector3.new(0, 4.7, -0.16))
				disc(m, "Rings", 2.6, 0.64, Vector3.new(0, 4.7, -0.16))
				disc(m, "Bull", 0.9, 0.84, Vector3.new(0, 4.7, -0.16))
			end,
		},
		AmbushBow = {
			Height = 4.84,
			AssetId = 114834088053406,
			Palette = {
				Limbs = h.rgb(156, 98, 56),
				Grip = h.rgb(92, 52, 42),
				String = h.rgb(245, 240, 225),
				Tips = h.rgb(255, 205, 80),
			},
			Materials = { Limbs = Enum.Material.Wood, Tips = Enum.Material.Metal },
			Fallback = function(m)
				h.capsule(m, "Limbs", 4.7, 0.3, CFrame.new(0, 2.42, -0.3) * CFrame.Angles(0, 0, math.rad(90)))
				h.block(m, "Grip", Vector3.new(0.5, 1.1, 0.6), Vector3.new(0, 2.42, -0.3))
				h.block(m, "String", Vector3.new(0.06, 4.6, 0.06), Vector3.new(0, 2.42, 0.25))
			end,
		},
		AmbushArrow = {
			Height = 0.63,
			AssetId = 87077821272468,
			Shadow = false,
			Palette = {
				Shaft = h.rgb(210, 166, 112),
				Head = h.rgb(176, 186, 200),
				Fletching = h.rgb(255, 110, 60),
				Nock = h.rgb(255, 205, 80),
			},
			Materials = { Head = Enum.Material.Metal },
			Fallback = function(m)
				h.capsule(m, "Shaft", 3.8, 0.15, CFrame.new(0, 0.315, 0.2) * CFrame.Angles(0, math.rad(90), 0))
				h.block(m, "Head", Vector3.new(0.36, 0.42, 0.7), Vector3.new(0, 0.315, -1.95))
				h.block(m, "Fletching", Vector3.new(0.36, 0.63, 1), Vector3.new(0, 0.315, 1.45))
			end,
		},
		HayBale = {
			Height = 2.52,
			AssetId = 137933577361025,
			Palette = { Straw = h.rgb(240, 208, 116), Twine = h.rgb(150, 100, 60) },
			Materials = { Straw = Enum.Material.Fabric },
			Fallback = function(m)
				h.rounded(m, "Straw", Vector3.new(4, 2.4, 2.6), 0.45, Vector3.new(0, 1.26, 0))
			end,
		},
		ArrowBarrel = {
			Height = 4.14,
			AssetId = 107614183157636,
			Palette = {
				Barrel = h.rgb(160, 105, 62),
				Hoops = h.rgb(80, 80, 92),
				Shafts = h.rgb(210, 166, 112),
				Feathers = h.rgb(255, 110, 60),
			},
			Materials = { Barrel = Enum.Material.Wood, Hoops = Enum.Material.Metal },
			Fallback = function(m)
				h.pillar(m, "Barrel", 2.5, 2.6, Vector3.new(0, 1.3, 0))
				h.block(m, "Shafts", Vector3.new(0.12, 2.6, 0.12), Vector3.new(0, 2.84, 0))
			end,
		},
		Bunting = {
			Height = 2.28,
			AssetId = 119795646147853,
			Shadow = false,
			Palette = {
				Rope = h.rgb(240, 235, 220),
				PennantA = h.rgb(255, 90, 80),
				PennantB = h.rgb(255, 205, 60),
				PennantC = h.rgb(80, 170, 255),
			},
			Materials = {
				PennantA = Enum.Material.Fabric,
				PennantB = Enum.Material.Fabric,
				PennantC = Enum.Material.Fabric,
			},
			Fallback = function(m)
				h.block(m, "Rope", Vector3.new(20, 0.1, 0.1), Vector3.new(0, 2.2, 0))
				local names = { "PennantA", "PennantB", "PennantC" }
				for k = 0, 8 do
					h.block(m, names[k % 3 + 1], Vector3.new(0.9, 1, 0.04), Vector3.new(-8 + k * 2, 1.6, 0))
				end
			end,
		},
		-- One 10.6 x 10.7 tile of cobbles (mostly cream, some honey, a few blue); the courtyard floor
		-- shows through the gaps as grout.
		ArrowAmbushCobbles = {
			Height = 0.4,
			AssetId = 115358561546902,
			Collide = false, -- the courtyard floor under it is what runners stand on
			Shadow = false,
			Palette = {
				Cobble = h.rgb(238, 228, 208),
				CobbleWarm = h.rgb(236, 198, 144),
				CobbleCool = h.rgb(176, 194, 216),
			},
			Fallback = function(m)
				h.block(m, "Cobble", Vector3.new(10.6, 0.24, 10.7), Vector3.new(0, 0.22, 0))
				speck(m, Vector3.new(0, 0.2, 0), 0.4)
			end,
		},
		-- An 8.8 long section of the low courtyard wall: stone courses, coping and little merlons.
		ArrowAmbushWall = {
			Height = 3.31,
			AssetId = 138409413801657,
			Collide = false, -- the mode keeps an invisible collider in the wall
			Palette = { Mortar = mortar, Stone = stone, Cap = trim },
			Materials = { Mortar = Enum.Material.Slate, Stone = Enum.Material.Slate, Cap = Enum.Material.Slate },
			Fallback = function(m)
				h.block(m, "Mortar", Vector3.new(8.8, 2.4, 1.5), Vector3.new(0, 1.2, 0))
				h.block(m, "Cap", Vector3.new(8.8, 0.36, 1.86), Vector3.new(0, 2.58, 0))
				for k = 0, 3 do
					h.block(m, "Cap", Vector3.new(1.3, 0.55, 1.4), Vector3.new(-3.3 + k * 2.2, 3.035, 0))
				end
			end,
		},
		-- A round turret with a blue cone roof and a pennant (the courtyard's corners; scaled up for
		-- the castle's towers).
		ArrowAmbushTurret = {
			Height = 12.69,
			AssetId = 124059599614229,
			Collide = false,
			Palette = {
				Mortar = mortar,
				Stone = stone,
				Trim = trim,
				Roof = roof,
				Gold = gold,
				Flag = red,
				Window = h.rgb(46, 36, 52),
			},
			Materials = {
				Mortar = Enum.Material.Slate,
				Stone = Enum.Material.Slate,
				Trim = Enum.Material.Slate,
				Gold = Enum.Material.Metal,
				Flag = Enum.Material.Fabric,
			},
			Fallback = function(m)
				h.pillar(m, "Mortar", 4, 5.4, Vector3.new(0, 2.7, 0))
				h.pillar(m, "Trim", 4.8, 0.4, Vector3.new(0, 5.4, 0))
				drums(m, "Roof", 4.6, 5.6, 4.8)
				h.pillar(m, "Gold", 0.14, 2, Vector3.new(0, 11.4, 0))
				h.ball(m, "Gold", 0.3, Vector3.new(0, 12.54, 0))
				h.block(m, "Flag", Vector3.new(2.2, 1, 0.07), Vector3.new(1.15, 12, 0))
			end,
		},
		-- A 16 long section of the castle's curtain wall, its banner on the front (-Z).
		ArrowAmbushCastleWall = {
			Height = 12.6,
			AssetId = 80463230898713,
			Collide = false,
			Palette = {
				Mortar = h.rgb(168, 156, 146),
				Stone = h.rgb(218, 206, 188),
				Trim = h.rgb(234, 224, 206),
				Window = h.rgb(46, 36, 52),
				Banner = h.rgb(64, 112, 214),
				Emblem = gold,
				Gold = gold,
			},
			Materials = {
				Mortar = Enum.Material.Slate,
				Stone = Enum.Material.Slate,
				Trim = Enum.Material.Slate,
				Banner = Enum.Material.Fabric,
				Gold = Enum.Material.Metal,
			},
			Fallback = function(m)
				h.block(m, "Mortar", Vector3.new(16, 10.4, 2.6), Vector3.new(0, 5.2, 0))
				h.block(m, "Trim", Vector3.new(16, 0.8, 3.5), Vector3.new(0, 10.4, 0))
				for k = 0, 5 do
					for _, z in { -1.25, 1.25 } do
						h.block(m, "Stone", Vector3.new(1.7, 1.8, 0.9), Vector3.new(-6.667 + k * 2.667, 11.7, z))
					end
				end
				h.block(m, "Banner", Vector3.new(3.2, 7, 0.1), Vector3.new(0, 5.65, -1.86))
			end,
		},
		-- A round festival tent in two-color stripes (StripeA is recolored per tent).
		ArrowAmbushTent = {
			Height = 9.62,
			AssetId = 124230307098304,
			Collide = false,
			Palette = {
				StripeA = red,
				StripeB = h.rgb(252, 246, 232),
				Inside = h.rgb(74, 46, 60),
				Trim = gold,
				Flag = gold,
			},
			Materials = { StripeA = Enum.Material.Fabric, StripeB = Enum.Material.Fabric, Flag = Enum.Material.Fabric },
			Fallback = function(m)
				h.pillar(m, "StripeA", 6.8, 3.3, Vector3.new(0, 1.65, 0))
				drums(m, "StripeB", 7.7, 3.3, 4.3)
				h.pillar(m, "Trim", 0.12, 1.7, Vector3.new(0, 8.45, 0))
				h.ball(m, "Trim", 0.3, Vector3.new(0, 9.47, 0))
				h.block(m, "Inside", Vector3.new(1.7, 2.5, 0.1), Vector3.new(0, 1.25, -3.5))
			end,
		},
		-- A tall banner pole with a swallowtail banner and a gold crossed-arrows badge.
		ArrowAmbushBanner = {
			Height = 11.52,
			AssetId = 80606755230134,
			Collide = false,
			Palette = {
				Foot = stone,
				Pole = h.rgb(150, 100, 62),
				Gold = gold,
				Cloth = red,
				Emblem = gold,
			},
			Materials = { Foot = Enum.Material.Slate, Pole = Enum.Material.Wood, Cloth = Enum.Material.Fabric },
			Fallback = function(m)
				h.block(m, "Foot", Vector3.new(1, 0.5, 1), Vector3.new(0, 0.25, 0))
				h.pillar(m, "Pole", 0.3, 10.7, Vector3.new(0, 5.65, 0))
				h.ball(m, "Gold", 0.64, Vector3.new(0, 11.2, 0))
				h.block(m, "Cloth", Vector3.new(2.9, 6.4, 0.08), Vector3.new(0, 7.02, -0.36))
			end,
		},
		-- A round straw archery target on a wooden easel, three arrows in it.
		ArrowAmbushHayTarget = {
			Height = 5.47,
			AssetId = 113637795512437,
			Collide = false,
			Palette = {
				Straw = h.rgb(242, 208, 112),
				Wood = h.rgb(150, 100, 62),
				Face = h.rgb(252, 248, 238),
				Rings = h.rgb(232, 58, 58),
				Bull = h.rgb(255, 205, 60),
				Shafts = h.rgb(210, 166, 112),
				Fletching = h.rgb(255, 110, 60),
			},
			Materials = { Straw = Enum.Material.Fabric, Wood = Enum.Material.Wood },
			Fallback = function(m)
				h.roller(m, "Straw", 4, 1, Vector3.new(0, 3.1, 0)).CFrame = CFrame.new(0, 3.1, 0)
					* CFrame.Angles(0, math.rad(90), 0)
				disc(m, "Face", 3, 1.2, Vector3.new(0, 3.1, 0))
				for _, x in { -1.1, 1.1 } do
					h.block(m, "Wood", Vector3.new(0.26, 5.47, 0.26), Vector3.new(x, 2.735, 0.9))
				end
			end,
		},
	}
end
