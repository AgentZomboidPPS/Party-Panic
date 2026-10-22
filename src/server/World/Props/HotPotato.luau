-- Props for Hot Potato: the potato bomb (a lumpy baked spud with a metal cap and a fizzing fuse), the
-- backyard's picket fence panels with string lights, the giant kettle grill in the middle, picnic
-- tables and hay bales to dodge round, and the cartoon blast puff. Meshes come from
-- tools/meshgen/props/HotPotato.py; until one is uploaded its Fallback is used.
--
-- Nothing solid where nothing is drawn (owner: "Theres invisible stuff you can jump on and hang on
-- in several games"): the solid props (fence, grill, table, hay) get collision that follows their
-- meshes (MeshLibrary rebuilds it precise); the potato, lights and puffs never collide.
return function(h)
	return {
		HotPotatoSpud = {
			Height = 2.6,
			AssetId = 91667410422335,
			Palette = {
				Spud = h.rgb(196, 140, 78),
				Eyes = h.rgb(120, 78, 40),
				Cap = h.rgb(150, 156, 168),
				Fuse = h.rgb(70, 52, 40),
				Spark = h.rgb(255, 200, 60),
			},
			Materials = { Cap = Enum.Material.Metal, Spark = Enum.Material.Neon },
			Fallback = function(m)
				h.blob(m, "Spud", Vector3.new(2.2, 1.8, 1.6), Vector3.new(0, 0.9, 0))
				h.pillar(m, "Cap", 0.8, 0.4, Vector3.new(0, 1.9, 0))
				h.pillar(m, "Fuse", 0.18, 0.5, Vector3.new(0, 2.3, 0))
				h.ball(m, "Spark", 0.35, Vector3.new(0, 2.5, 0))
			end,
		},
		HotPotatoPuff = {
			Height = 3.7,
			AssetId = 111494431788956,
			Shadow = false,
			Palette = { Puff = h.rgb(255, 250, 240) },
			Fallback = function(m)
				h.ball(m, "Puff", 4, Vector3.new(0, 2, 0))
			end,
		},
		HotPotatoFence = {
			Height = 10.5,
			AssetId = 70543224773631,
			Collide = true,
			Palette = { Pickets = h.rgb(250, 246, 236), Rails = h.rgb(232, 224, 208), Posts = h.rgb(240, 234, 220) },
			Materials = { Pickets = Enum.Material.Wood, Rails = Enum.Material.Wood, Posts = Enum.Material.Wood },
			Fallback = function(m)
				h.block(m, "Pickets", Vector3.new(8.4, 10.5, 1.4), Vector3.new(0, 5.25, 0))
			end,
		},
		HotPotatoLights = {
			Height = 1.0,
			AssetId = 131816898096963,
			Shadow = false,
			Palette = {
				Wire = h.rgb(40, 40, 46),
				BulbA = h.rgb(255, 214, 110),
				BulbB = h.rgb(255, 140, 90),
				BulbC = h.rgb(140, 220, 255),
			},
			Materials = { BulbA = Enum.Material.Neon, BulbB = Enum.Material.Neon, BulbC = Enum.Material.Neon },
			Fallback = function(m)
				h.block(m, "Wire", Vector3.new(8, 0.1, 0.1), Vector3.new(0, 1.2, 0))
				h.ball(m, "BulbA", 0.4, Vector3.new(-2, 0.6, 0))
				h.ball(m, "BulbB", 0.4, Vector3.new(0, 0.3, 0))
				h.ball(m, "BulbC", 0.4, Vector3.new(2, 0.6, 0))
			end,
		},
		HotPotatoGrill = {
			Height = 8,
			AssetId = 125271739096064,
			Collide = true,
			Palette = {
				Bowl = h.rgb(200, 50, 45),
				Grate = h.rgb(70, 70, 76),
				Coals = h.rgb(255, 110, 40),
				Legs = h.rgb(60, 60, 66),
				Wheels = h.rgb(30, 30, 34),
				Spuds = h.rgb(196, 140, 78),
				Foil = h.rgb(210, 214, 222),
			},
			Materials = {
				Bowl = Enum.Material.SmoothPlastic,
				Grate = Enum.Material.Metal,
				Coals = Enum.Material.Neon,
				Legs = Enum.Material.Metal,
				Foil = Enum.Material.Foil,
			},
			Fallback = function(m)
				h.pillar(m, "Legs", 1, 4.5, Vector3.new(0, 2.25, 0))
				h.pillar(m, "Bowl", 7, 3, Vector3.new(0, 6, 0))
				h.pillar(m, "Coals", 6.4, 0.3, Vector3.new(0, 7.55, 0))
			end,
		},
		HotPotatoTable = {
			Height = 3.6,
			AssetId = 105868232967252,
			Collide = true,
			Palette = {
				Top = h.rgb(176, 112, 64),
				Benches = h.rgb(160, 100, 58),
				Legs = h.rgb(130, 82, 48),
				Cloth = h.rgb(230, 70, 70),
			},
			Materials = {
				Top = Enum.Material.Wood,
				Benches = Enum.Material.Wood,
				Legs = Enum.Material.Wood,
				Cloth = Enum.Material.Fabric,
			},
			Fallback = function(m)
				h.block(m, "Top", Vector3.new(7, 0.4, 3), Vector3.new(0, 3.4, 0))
				h.block(m, "Benches", Vector3.new(7, 0.35, 1.2), Vector3.new(0, 1.8, 2.4))
				h.block(m, "Benches", Vector3.new(7, 0.35, 1.2), Vector3.new(0, 1.8, -2.4))
				h.block(m, "Legs", Vector3.new(0.4, 3.2, 5.8), Vector3.new(-2.8, 1.6, 0))
				h.block(m, "Legs", Vector3.new(0.4, 3.2, 5.8), Vector3.new(2.8, 1.6, 0))
			end,
		},
		HotPotatoHay = {
			Height = 2.9,
			AssetId = 75355374808258,
			Collide = true,
			Palette = { Hay = h.rgb(226, 190, 96), Twine = h.rgb(150, 100, 60) },
			Materials = { Hay = Enum.Material.Fabric },
			Fallback = function(m)
				h.rounded(m, "Hay", Vector3.new(5, 2.8, 2.8), 0.4, Vector3.new(0, 1.4, 0))
			end,
		},
	}
end
