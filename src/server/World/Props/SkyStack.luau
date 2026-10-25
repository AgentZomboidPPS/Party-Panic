-- Props for Sky Stack (meshes from tools/meshgen/props/SkyStack.py):
--   SkyStackBase   a tower's stone base. Its Top plate is the first floor's footprint: 8 x 8 studs
--                  (Logic/SkyStack.FULL), its top face at y = 3 (the mode's BASE_TOP), so floor 1
--                  sits right on it. Trim takes the lane's color.
--   SkyStackStar   the golden star floating at the cloud line over each tower; the Ribbon under it
--                  takes the lane's color; the client sways it and pops it when the tower gets there.
--   SkyStackCloud  a fluffy cloud (the cloud line and the sky), scaled per cloud.
--   SkyStackCrane  a tower crane at each end of the row, its jib reaching over the towers.
-- All of them are only to look at: nothing collides (nothing solid where nothing is drawn).
return function(h)
	local rgb = h.rgb
	local metal = Enum.Material.Metal

	return {
		SkyStackBase = {
			Height = 3,
			AssetId = 80397687535139, -- tools/upload_assets.py --only SkyStackBase fills this in
			Collide = false,
			Shadow = true,
			Palette = {
				Stone = rgb(214, 204, 186),
				Dark = rgb(150, 140, 126),
				Trim = rgb(70, 150, 255),
				Top = rgb(246, 242, 232),
			},
			Materials = { Stone = Enum.Material.Limestone, Dark = Enum.Material.Limestone },
			Fallback = function(m)
				h.rounded(m, "Dark", Vector3.new(10.4, 0.6, 10.4), 0.25, Vector3.new(0, 0.3, 0))
				h.rounded(m, "Stone", Vector3.new(9.6, 1.8, 9.6), 0.3, Vector3.new(0, 1.4, 0))
				h.block(m, "Trim", Vector3.new(9.75, 0.45, 9.75), Vector3.new(0, 1.55, 0))
				h.block(m, "Top", Vector3.new(8, 0.7, 8), Vector3.new(0, 2.65, 0))
			end,
		},
		SkyStackStar = {
			Height = 3.3,
			AssetId = 124661970850866,
			Collide = false,
			Palette = {
				Star = rgb(255, 212, 70),
				Face = rgb(70, 50, 40),
				Cheeks = rgb(255, 150, 120),
				Ribbon = rgb(70, 150, 255),
			},
			Materials = { Star = Enum.Material.Neon },
			Fallback = function(m)
				h.ball(m, "Star", 2.6, Vector3.new(0, 2.1, 0))
				for _, side in { -1, 1 } do
					h.ball(m, "Face", 0.32, Vector3.new(side * 0.42, 2.35, -1.2))
				end
				h.block(m, "Ribbon", Vector3.new(2.4, 0.5, 0.2), Vector3.new(0, 0.5, 0))
			end,
		},
		SkyStackCloud = {
			Height = 4.6,
			AssetId = 107029468779143,
			Collide = false,
			Shadow = false,
			Palette = { Cloud = rgb(255, 255, 255), Shade = rgb(220, 232, 250) },
			Fallback = function(m)
				h.blob(m, "Shade", Vector3.new(12, 2, 6), Vector3.new(0, 1, 0))
				h.ball(m, "Cloud", 4.4, Vector3.new(-3, 2, 0))
				h.ball(m, "Cloud", 5.2, Vector3.new(0.4, 2.4, 0.3))
				h.ball(m, "Cloud", 3.8, Vector3.new(3.6, 1.9, -0.2))
			end,
		},
		SkyStackCrane = {
			Height = 64,
			AssetId = 91075457597437,
			Collide = false,
			Shadow = true,
			Palette = {
				Mast = rgb(255, 196, 40),
				Jib = rgb(255, 196, 40),
				Cab = rgb(245, 245, 240),
				Glass = rgb(110, 170, 220),
				Counter = rgb(150, 150, 150),
				Cable = rgb(60, 62, 70),
				Hook = rgb(230, 70, 60),
				Footing = rgb(120, 120, 126),
			},
			Materials = { Mast = metal, Jib = metal, Cable = metal, Hook = metal, Glass = Enum.Material.Glass },
			Fallback = function(m)
				h.block(m, "Footing", Vector3.new(6, 1, 6), Vector3.new(0, 0.5, 0))
				h.block(m, "Mast", Vector3.new(2.6, 56, 2.6), Vector3.new(0, 29, 0))
				h.block(m, "Cab", Vector3.new(3.4, 2.6, 3.4), Vector3.new(0, 58.3, -1.2))
				h.block(m, "Jib", Vector3.new(1.6, 1.6, 40), Vector3.new(0, 60.8, -16))
				h.block(m, "Jib", Vector3.new(1.4, 1.4, 12), Vector3.new(0, 60.8, 8))
				h.block(m, "Counter", Vector3.new(3, 3, 3), Vector3.new(0, 59, 12))
				h.pillar(m, "Mast", 0.6, 3.6, Vector3.new(0, 62.2, 0))
				h.block(m, "Cable", Vector3.new(0.2, 18, 0.2), Vector3.new(0, 51, -30))
				h.block(m, "Hook", Vector3.new(1, 1.4, 0.4), Vector3.new(0, 41.5, -30))
			end,
		},
	}
end
