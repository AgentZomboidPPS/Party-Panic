-- Props for Slaparazzi (meshes from tools/meshgen/props/Slaparazzi.py). Nothing here collides
-- (owner: "Theres invisible stuff you can jump on and hang on in several games"): the stage, plaza
-- and backdrop wall the players stand on and bump into are drawn parts built by the mode itself, and
-- these props are scenery you can't get stuck on. The ones big enough for the camera to slide
-- inside stop the camera (BlocksCamera) without ever being solid to characters.
return function(h)
	return {
		-- The photo frame on the stage. Its rings' outer edges are the scoring radii
		-- (Logic/Slaparazzi.luau RINGS: 3.6, 7.2, 11); the whole frame is 24.35 studs across.
		SlaparazziFrame = {
			Height = 0.12,
			AssetId = 113926669652250,
			Shadow = false,
			Palette = {
				Gold = h.rgb(255, 200, 60),
				Silver = h.rgb(215, 225, 240),
				Bronze = h.rgb(215, 130, 70),
				Bracket = h.rgb(255, 255, 255),
			},
			Materials = { Bracket = Enum.Material.Neon, Gold = Enum.Material.Neon },
			Fallback = function(m)
				-- Discs stacked a little apart (parts that share a plane flicker).
				h.pillar(m, "Bronze", 22, 0.03, Vector3.new(0, 0.015, 0))
				h.pillar(m, "Silver", 14.4, 0.03, Vector3.new(0, 0.105, 0))
				h.pillar(m, "Gold", 7.2, 0.03, Vector3.new(0, 0.195, 0))
				for _, sx in { -1, 1 } do
					for _, sz in { -1, 1 } do
						h.block(m, "Bracket", Vector3.new(3.2, 0.03, 0.55), Vector3.new(sx * 10.5, 0.015, sz * 11.9))
						h.block(m, "Bracket", Vector3.new(0.55, 0.03, 3.2), Vector3.new(sx * 11.9, 0.015, sz * 10.5))
					end
				end
			end,
			-- Exactly 24.35 across, whatever the importer did, so the rings sit on the scoring radii.
			PostProcess = function(model)
				local _, size = model:GetBoundingBox()
				if size.X > 1 and math.abs(size.X - 24.35) > 0.05 then
					local pivot = model:GetPivot()
					model:ScaleTo(model:GetScale() * 24.35 / size.X)
					model:PivotTo(pivot)
				end
			end,
		},
		-- The photographer bent to a vintage press camera on a wooden tripod, flash dish up.
		SlaparazziCamera = {
			Height = 8.62,
			AssetId = 139339303946076,
			BlocksCamera = { "Coat", "Body", "Pants" },
			Palette = {
				Tripod = h.rgb(150, 100, 60),
				Chrome = h.rgb(190, 195, 205),
				Body = h.rgb(40, 38, 44),
				Bellows = h.rgb(120, 40, 45),
				Lens = h.rgb(60, 60, 66),
				Glass = h.rgb(70, 110, 170),
				Dish = h.rgb(225, 228, 235),
				Bulb = h.rgb(255, 250, 220),
				Coat = h.rgb(40, 120, 130),
				Skin = h.rgb(240, 190, 150),
				Pants = h.rgb(50, 50, 70),
				Shoes = h.rgb(70, 45, 35),
				Beret = h.rgb(210, 40, 60),
			},
			Materials = {
				Chrome = Enum.Material.Metal,
				Tripod = Enum.Material.Wood,
				Glass = Enum.Material.Glass,
				Dish = Enum.Material.Metal,
				Bulb = Enum.Material.Neon,
				Coat = Enum.Material.Fabric,
			},
			Fallback = function(m)
				h.pillar(m, "Tripod", 0.3, 4.4, Vector3.new(0, 2.2, 0))
				h.block(m, "Body", Vector3.new(2.2, 1.6, 1.5), Vector3.new(0, 5.4, 0))
				h.pillar(m, "Lens", 1, 0.6, Vector3.new(0, 5.4, -1.1))
				h.ball(m, "Dish", 1.8, Vector3.new(-1.3, 7.5, -0.2))
				h.pillar(m, "Coat", 1.4, 2.6, Vector3.new(0, 3.9, 2.3))
				h.pillar(m, "Pants", 1.2, 2.6, Vector3.new(0, 1.3, 2.4))
				h.ball(m, "Skin", 1.1, Vector3.new(0, 5.75, 1.4))
				h.ball(m, "Beret", 1.1, Vector3.new(0, 6.25, 1.55))
			end,
		},
		-- A stage spotlight on a stand, its can tilted down toward the front (-Z).
		SlaparazziSpotlight = {
			Height = 8.62,
			AssetId = 137613494256483,
			Palette = { Stand = h.rgb(60, 60, 66), Can = h.rgb(30, 30, 34), Lens = h.rgb(255, 244, 214) },
			Materials = { Stand = Enum.Material.Metal, Lens = Enum.Material.Neon },
			Fallback = function(m)
				h.pillar(m, "Stand", 0.3, 7, Vector3.new(0, 3.5, 0))
				h.block(m, "Can", Vector3.new(1.5, 1.5, 1.8), Vector3.new(0, 7.6, 0))
				h.block(m, "Lens", Vector3.new(1.2, 1.2, 0.1), Vector3.new(0, 7.6, -0.95))
			end,
		},
		-- A section of cheering fans on a three-tier riser (16 wide), facing -Z.
		SlaparazziCrowd = {
			Height = 6.15,
			AssetId = 131036744580945,
			BlocksCamera = { "Riser" },
			Palette = {
				Riser = h.rgb(90, 50, 120),
				Rail = h.rgb(210, 175, 70),
				Hair = h.rgb(70, 45, 30),
				Phone = h.rgb(30, 30, 34),
				Screen = h.rgb(200, 230, 255),
				Sign = h.rgb(250, 250, 250),
				SignStar = h.rgb(255, 90, 170),
				ShirtA = h.rgb(255, 90, 120),
				ShirtB = h.rgb(80, 170, 255),
				ShirtC = h.rgb(255, 205, 60),
				SkinA = h.rgb(240, 190, 150),
				SkinB = h.rgb(150, 100, 70),
			},
			Materials = { Rail = Enum.Material.Metal, Screen = Enum.Material.Neon },
			Fallback = function(m)
				h.block(m, "Riser", Vector3.new(16, 2.4, 6), Vector3.new(0, 1.2, 0))
				for index = 0, 5 do
					h.pillar(m, "ShirtA", 1, 1.9, Vector3.new(-6.5 + index * 2.6, 3.35, 1))
					h.ball(m, "SkinA", 0.85, Vector3.new(-6.5 + index * 2.6, 4.7, 1))
				end
			end,
		},
		-- The big open glove a slap swings (a client effect, shared with ctx:ShareTemplate).
		SlaparazziGlove = {
			Height = 3.16,
			AssetId = 127215886299352,
			Shadow = false,
			Palette = { Glove = h.rgb(250, 250, 250), Cuff = h.rgb(255, 120, 180), Stitch = h.rgb(40, 40, 50) },
			Fallback = function(m)
				h.rounded(m, "Glove", Vector3.new(1.7, 2.2, 0.7), 0.3, Vector3.new(0, 2, 0))
				h.pillar(m, "Cuff", 1.4, 0.6, Vector3.new(0, 0.4, 0))
			end,
		},
		-- Two brass stanchions with a velvet rope between them (along X), beside the red carpet.
		SlaparazziRope = {
			Height = 3.2,
			AssetId = 82051580058496,
			Palette = { Brass = h.rgb(215, 175, 70), Rope = h.rgb(170, 20, 40) },
			Materials = { Brass = Enum.Material.Metal, Rope = Enum.Material.Fabric },
			Fallback = function(m)
				for _, x in { -3, 3 } do
					h.pillar(m, "Brass", 0.2, 3, Vector3.new(x, 1.5, 0))
				end
				h.block(m, "Rope", Vector3.new(6, 0.2, 0.2), Vector3.new(0, 2.4, 0))
			end,
		},
	}
end
