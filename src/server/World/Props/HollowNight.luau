-- Props for Hollow Night, the first crate season (owner: "Hollow night comes first I want you to actually
-- work on adding it to the game right now ... This will be players first season. I want it to look
-- insane."). The meshes are Blender models exported in coloured pieces by tools/meshgen/season/export.py;
-- this file is written by tools/meshgen/season/write_props.py from what that export measured (heights,
-- each piece's colour, material and transparency). Don't edit it by hand: change the model and re-export.
return function(h)
	local rgb = h.rgb

	-- See-through pieces (a wisp's flame and tail, glass), set after the template is made.
	local function seeThrough(amounts: { [string]: number })
		return function(model: Model)
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and amounts[part.Name] then
					part.Transparency = amounts[part.Name]
					part.CastShadow = false
				end
			end
		end
	end

	return {
		-- The Hollow Crate: planked wood, iron corners, brass studs, a glowing maple leaf on each side and leaves on the lid. The lid's pieces are Lid..., so the opening show can blow it off.
		HollowCrate = {
			Height = 3.550,
			AssetId = 134308408889863,
			BlocksCamera = true,
			Palette = {
				Glow = rgb(255, 138, 42),
				Iron = rgb(47, 43, 58),
				Brass = rgb(212, 145, 58),
				Wood = rgb(138, 85, 48),
				LidBrass = rgb(212, 145, 58),
				LidIron = rgb(47, 43, 58),
				LidWood = rgb(138, 85, 48),
				LidLeaf = rgb(255, 194, 61),
				LidLeaf2 = rgb(255, 138, 42),
				LidLeaf3 = rgb(225, 73, 44),
				LidLeaf4 = rgb(168, 54, 28),
				LidMushStem = rgb(242, 230, 204),
				LidGlow = rgb(255, 138, 42),
				WoodDark = rgb(90, 52, 32),
			},
			Materials = {
				Glow = Enum.Material.Neon,
				Iron = Enum.Material.SmoothPlastic,
				Brass = Enum.Material.SmoothPlastic,
				Wood = Enum.Material.SmoothPlastic,
				LidBrass = Enum.Material.SmoothPlastic,
				LidIron = Enum.Material.SmoothPlastic,
				LidWood = Enum.Material.SmoothPlastic,
				LidLeaf = Enum.Material.SmoothPlastic,
				LidLeaf2 = Enum.Material.SmoothPlastic,
				LidLeaf3 = Enum.Material.SmoothPlastic,
				LidLeaf4 = Enum.Material.SmoothPlastic,
				LidMushStem = Enum.Material.SmoothPlastic,
				LidGlow = Enum.Material.Neon,
				WoodDark = Enum.Material.SmoothPlastic,
			},
			Fallback = function(m)
				h.block(m, "Iron", Vector3.new(3.25, 2.26, 3.26), Vector3.new(0.00, 1.13, 0.00))
			end,
		},
		-- The Lantern Key: an iron key whose bow is a lantern cage with an ember inside.
		LanternKey = {
			Height = 1.808,
			AssetId = 86718277157977,
			Palette = {
				Iron = rgb(47, 43, 58),
				Glow = rgb(255, 181, 48),
				Brass = rgb(212, 145, 58),
				Leaf = rgb(255, 138, 42),
			},
			Materials = {
				Iron = Enum.Material.SmoothPlastic,
				Glow = Enum.Material.Neon,
				Brass = Enum.Material.SmoothPlastic,
				Leaf = Enum.Material.SmoothPlastic,
			},
			Fallback = function(m)
				h.block(m, "Iron", Vector3.new(2.63, 1.33, 1.32), Vector3.new(-0.66, 0.97, 0.00))
			end,
		},
		-- The crate pile on its tree stump, the lobby's middle for the season (the turning crate on top, the keys round it and the wisps are separate: the game moves them).
		HollowPile = {
			Height = 10.912,
			AssetId = 96283343045646,
			BlocksCamera = true,
			Shadow = true,
			Palette = {
				Bark = rgb(88, 52, 32),
				StumpTop = rgb(212, 145, 58),
				Ring = rgb(138, 86, 49),
				Glow = rgb(255, 138, 42),
				Leafpile = rgb(218, 71, 37),
				Leaf = rgb(168, 54, 28),
				Leaf2 = rgb(255, 193, 59),
				Leaf3 = rgb(255, 129, 33),
				Iron = rgb(47, 43, 58),
				MushStem = rgb(242, 228, 197),
				Stem = rgb(93, 107, 42),
			},
			Materials = {
				Bark = Enum.Material.SmoothPlastic,
				StumpTop = Enum.Material.SmoothPlastic,
				Ring = Enum.Material.SmoothPlastic,
				Glow = Enum.Material.Neon,
				Leafpile = Enum.Material.SmoothPlastic,
				Leaf = Enum.Material.SmoothPlastic,
				Leaf2 = Enum.Material.SmoothPlastic,
				Leaf3 = Enum.Material.SmoothPlastic,
				Iron = Enum.Material.SmoothPlastic,
				MushStem = Enum.Material.SmoothPlastic,
				Stem = Enum.Material.SmoothPlastic,
			},
			Fallback = function(m)
				h.block(m, "Bark", Vector3.new(33.37, 8.99, 33.75), Vector3.new(-0.33, 5.19, 0.07))
			end,
		},
		-- An opening altar: two stone steps, a glowing ring (Ring: the game colours it by tier), lantern posts and pumpkins. Its crate is a HollowCrate on top.
		HollowAltar = {
			Height = 5.375,
			AssetId = 85757292146292,
			BlocksCamera = true,
			Palette = {
				Ring = rgb(255, 138, 42),
				Leaf = rgb(255, 208, 74),
				Leaf2 = rgb(184, 52, 35),
				Leaf3 = rgb(255, 123, 27),
				Leaf4 = rgb(232, 82, 30),
				Stone = rgb(47, 43, 58),
				Stem = rgb(93, 107, 42),
				Glow = rgb(255, 241, 194),
				Lglass = rgb(255, 181, 48),
			},
			Materials = {
				Ring = Enum.Material.Neon,
				Leaf = Enum.Material.SmoothPlastic,
				Leaf2 = Enum.Material.SmoothPlastic,
				Leaf3 = Enum.Material.SmoothPlastic,
				Leaf4 = Enum.Material.SmoothPlastic,
				Stone = Enum.Material.SmoothPlastic,
				Stem = Enum.Material.SmoothPlastic,
				Glow = Enum.Material.Neon,
				Lglass = Enum.Material.Neon,
			},
			Fallback = function(m)
				h.block(m, "Stone", Vector3.new(6.00, 5.38, 5.20), Vector3.new(0.00, 2.69, 0.00))
			end,
		},
		-- The Top Unboxers board's frame: wood, an iron cap, stump legs, lanterns, pumpkins and leaves (the screen is a part the game adds).
		HollowBoard = {
			Height = 16.612,
			AssetId = 105664440610541,
			BlocksCamera = true,
			Palette = {
				Iron = rgb(49, 43, 56),
				Wood = rgb(138, 85, 48),
				Leaf = rgb(255, 124, 28),
				Leaf2 = rgb(184, 52, 35),
				Leaf3 = rgb(255, 194, 61),
				Leaf4 = rgb(232, 82, 30),
				Stem = rgb(93, 107, 42),
				Glow = rgb(255, 241, 194),
				Lglass = rgb(255, 181, 48),
			},
			Materials = {
				Iron = Enum.Material.SmoothPlastic,
				Wood = Enum.Material.SmoothPlastic,
				Leaf = Enum.Material.SmoothPlastic,
				Leaf2 = Enum.Material.SmoothPlastic,
				Leaf3 = Enum.Material.SmoothPlastic,
				Leaf4 = Enum.Material.SmoothPlastic,
				Stem = Enum.Material.SmoothPlastic,
				Glow = Enum.Material.Neon,
				Lglass = Enum.Material.Neon,
			},
			Fallback = function(m)
				h.block(m, "Leaf", Vector3.new(10.30, 16.45, 2.46), Vector3.new(0.00, 8.34, -0.72))
			end,
		},
		-- A heap of fallen leaves to jump into.
		LeafHeap = {
			Height = 2.539,
			AssetId = 117663696003803,
			Palette = {
				Leaf = rgb(255, 191, 58),
				Leaf2 = rgb(227, 82, 30),
				Leaf3 = rgb(178, 53, 32),
				Leaf4 = rgb(255, 138, 42),
			},
			Materials = {
				Leaf = Enum.Material.SmoothPlastic,
				Leaf2 = Enum.Material.SmoothPlastic,
				Leaf3 = Enum.Material.SmoothPlastic,
				Leaf4 = Enum.Material.SmoothPlastic,
			},
			Fallback = function(m)
				h.block(m, "Leaf2", Vector3.new(6.10, 2.51, 5.89), Vector3.new(-0.01, 1.26, -0.02))
			end,
		},
		-- A round paper lantern (the Lantern Ring aura).
		PaperLantern = {
			Height = 1.140,
			AssetId = 74138052785863,
			Palette = {
				Rib = rgb(90, 52, 32),
				Paper = rgb(255, 138, 42),
			},
			Materials = {
				Rib = Enum.Material.SmoothPlastic,
				Paper = Enum.Material.Neon,
			},
			Fallback = function(m)
				h.block(m, "Rib", Vector3.new(0.89, 1.14, 0.89), Vector3.new(0.00, 0.57, 0.00))
			end,
		},
		-- A crow, wings spread (WingL..., WingR...: the game flaps them).
		HarvestCrow = {
			Height = 0.359,
			AssetId = 81364645413442,
			Palette = {
				Glow = rgb(255, 181, 48),
				Crow = rgb(26, 22, 34),
				WingRCrow = rgb(26, 22, 34),
				WingLCrow = rgb(26, 22, 34),
				Beak = rgb(224, 160, 48),
			},
			Materials = {
				Glow = Enum.Material.Neon,
				Crow = Enum.Material.SmoothPlastic,
				WingRCrow = Enum.Material.SmoothPlastic,
				WingLCrow = Enum.Material.SmoothPlastic,
				Beak = Enum.Material.SmoothPlastic,
			},
			Fallback = function(m)
				h.block(m, "Crow", Vector3.new(0.36, 0.36, 1.07), Vector3.new(0.00, 0.18, 0.11))
			end,
		},
		-- A ribbed pumpkin for the lobby's autumn dressing.
		HarvestPumpkin = {
			Height = 1.750,
			AssetId = 105837123521714,
			Palette = {
				Stem = rgb(93, 107, 42),
				Pumpkin = rgb(255, 122, 26),
			},
			Materials = {
				Stem = Enum.Material.SmoothPlastic,
				Pumpkin = Enum.Material.SmoothPlastic,
			},
			Fallback = function(m)
				h.block(m, "Pumpkin", Vector3.new(2.00, 1.42, 2.00), Vector3.new(-0.00, 0.71, 0.00))
			end,
		},
		-- An iron post with a hanging lantern.
		LanternPost = {
			Height = 6.363,
			AssetId = 100030627731681,
			Palette = {
				Iron = rgb(47, 43, 58),
				Glow = rgb(255, 241, 194),
				Lglass = rgb(255, 181, 48),
			},
			Materials = {
				Iron = Enum.Material.SmoothPlastic,
				Glow = Enum.Material.Neon,
				Lglass = Enum.Material.Neon,
			},
			Fallback = function(m)
				h.block(m, "Iron", Vector3.new(1.57, 6.36, 0.76), Vector3.new(-0.64, 3.18, 0.00))
			end,
		},
		-- Pet: the Harvest Owl (wings WingL... / WingR...).
		HarvestOwl = {
			Height = 3.147,
			AssetId = 75044229328684,
			Palette = {
				Iron = rgb(47, 43, 58),
				Glow = rgb(255, 138, 42),
				Talon = rgb(237, 160, 47),
				Glow2 = rgb(255, 255, 255),
				Eye = rgb(20, 12, 28),
				Glow3 = rgb(255, 181, 48),
				Face = rgb(245, 226, 189),
				Chest = rgb(233, 196, 138),
				Feather = rgb(160, 98, 44),
				Leaf = rgb(255, 208, 74),
				Leaf2 = rgb(232, 82, 30),
				Leaf3 = rgb(200, 50, 42),
				Glow4 = rgb(255, 241, 194),
				WingRLeaf = rgb(245, 186, 70),
				WingRLeaf2 = rgb(217, 124, 56),
				WingRLeaf3 = rgb(198, 53, 46),
				WingLLeaf = rgb(245, 186, 70),
				WingLLeaf2 = rgb(217, 124, 56),
				WingLLeaf3 = rgb(198, 53, 46),
			},
			Materials = {
				Iron = Enum.Material.SmoothPlastic,
				Glow = Enum.Material.Neon,
				Talon = Enum.Material.SmoothPlastic,
				Glow2 = Enum.Material.Neon,
				Eye = Enum.Material.SmoothPlastic,
				Glow3 = Enum.Material.Neon,
				Face = Enum.Material.SmoothPlastic,
				Chest = Enum.Material.SmoothPlastic,
				Feather = Enum.Material.SmoothPlastic,
				Leaf = Enum.Material.SmoothPlastic,
				Leaf2 = Enum.Material.SmoothPlastic,
				Leaf3 = Enum.Material.SmoothPlastic,
				Glow4 = Enum.Material.Neon,
				WingRLeaf = Enum.Material.SmoothPlastic,
				WingRLeaf2 = Enum.Material.SmoothPlastic,
				WingRLeaf3 = Enum.Material.SmoothPlastic,
				WingLLeaf = Enum.Material.SmoothPlastic,
				WingLLeaf2 = Enum.Material.SmoothPlastic,
				WingLLeaf3 = Enum.Material.SmoothPlastic,
			},
			Fallback = function(m)
				h.block(m, "Feather", Vector3.new(1.32, 1.60, 1.23), Vector3.new(0.00, 1.93, -0.03))
			end,
		},
		-- Pet: the Ember Stag.
		EmberStag = {
			Height = 4.006,
			AssetId = 87580476807700,
			Palette = {
				Fur = rgb(184, 112, 60),
				AntlerOrange = rgb(214, 151, 43),
				AntlerOrange2 = rgb(254, 145, 43),
				AntlerOrange3 = rgb(149, 100, 36),
				Light = rgb(244, 220, 192),
				Glow = rgb(255, 106, 31),
				Glow2 = rgb(255, 255, 255),
				Eye = rgb(22, 18, 36),
				Leaf = rgb(255, 201, 67),
				Leaf2 = rgb(255, 138, 42),
				Leaf3 = rgb(232, 82, 30),
				Leaf4 = rgb(200, 50, 42),
				Glow3 = rgb(255, 226, 122),
			},
			Materials = {
				Fur = Enum.Material.SmoothPlastic,
				AntlerOrange = Enum.Material.SmoothPlastic,
				AntlerOrange2 = Enum.Material.Neon,
				AntlerOrange3 = Enum.Material.SmoothPlastic,
				Light = Enum.Material.SmoothPlastic,
				Glow = Enum.Material.Neon,
				Glow2 = Enum.Material.Neon,
				Eye = Enum.Material.SmoothPlastic,
				Leaf = Enum.Material.SmoothPlastic,
				Leaf2 = Enum.Material.SmoothPlastic,
				Leaf3 = Enum.Material.SmoothPlastic,
				Leaf4 = Enum.Material.SmoothPlastic,
				Glow3 = Enum.Material.Neon,
			},
			Fallback = function(m)
				h.block(m, "AntlerOrange2", Vector3.new(1.75, 3.77, 1.75), Vector3.new(0.00, 1.89, -0.00))
			end,
		},
		-- Pet: the Gourdian (fists FistL... / FistR...).
		Gourdian = {
			Height = 3.262,
			AssetId = 77685675087519,
			Palette = {
				Vine = rgb(79, 107, 36),
				Glow = rgb(255, 138, 42),
				Seed = rgb(251, 221, 152),
				Low = rgb(232, 216, 168),
				Body = rgb(207, 155, 58),
				Leaf = rgb(200, 50, 42),
				Leaf2 = rgb(255, 181, 48),
				Leaf3 = rgb(232, 82, 30),
				Leaf4 = rgb(111, 158, 58),
				FistRStem = rgb(93, 107, 42),
				FistRPumpkin = rgb(255, 154, 58),
				FistLStem = rgb(93, 107, 42),
				FistLPumpkin = rgb(255, 154, 58),
				Pumpkin = rgb(255, 122, 26),
				Glow2 = rgb(255, 181, 48),
			},
			Materials = {
				Vine = Enum.Material.SmoothPlastic,
				Glow = Enum.Material.Neon,
				Seed = Enum.Material.Neon,
				Low = Enum.Material.SmoothPlastic,
				Body = Enum.Material.SmoothPlastic,
				Leaf = Enum.Material.SmoothPlastic,
				Leaf2 = Enum.Material.SmoothPlastic,
				Leaf3 = Enum.Material.SmoothPlastic,
				Leaf4 = Enum.Material.SmoothPlastic,
				FistRStem = Enum.Material.SmoothPlastic,
				FistRPumpkin = Enum.Material.SmoothPlastic,
				FistLStem = Enum.Material.SmoothPlastic,
				FistLPumpkin = Enum.Material.SmoothPlastic,
				Pumpkin = Enum.Material.SmoothPlastic,
				Glow2 = Enum.Material.Neon,
			},
			Fallback = function(m)
				h.block(m, "Vine", Vector3.new(2.58, 2.63, 0.91), Vector3.new(-0.00, 1.94, 0.00))
			end,
		},
		-- Pet: the Toadstool Tot.
		ToadstoolTot = {
			Height = 2.243,
			AssetId = 134819864540042,
			Palette = {
				Glow = rgb(255, 138, 42),
				Skin = rgb(244, 232, 207),
				Eye = rgb(20, 12, 28),
				Blush = rgb(255, 143, 200),
				Glow2 = rgb(255, 255, 255),
				Spot = rgb(255, 238, 191),
				Leaf = rgb(255, 138, 42),
				Cap = rgb(224, 72, 46),
				Acorn = rgb(168, 99, 46),
				AcornCap = rgb(106, 68, 38),
			},
			Materials = {
				Glow = Enum.Material.Neon,
				Skin = Enum.Material.SmoothPlastic,
				Eye = Enum.Material.SmoothPlastic,
				Blush = Enum.Material.SmoothPlastic,
				Glow2 = Enum.Material.Neon,
				Spot = Enum.Material.Neon,
				Leaf = Enum.Material.SmoothPlastic,
				Cap = Enum.Material.SmoothPlastic,
				Acorn = Enum.Material.SmoothPlastic,
				AcornCap = Enum.Material.SmoothPlastic,
			},
			Fallback = function(m)
				h.block(m, "Skin", Vector3.new(1.90, 1.29, 1.90), Vector3.new(0.00, 0.93, 0.00))
			end,
		},
		-- Pet: the Lantern Wisp (its flame is Flame...).
		LanternWisp = {
			Height = 4.023,
			AssetId = 88534974660816,
			Palette = {
				TailGreen = rgb(124, 240, 214),
				TailTeal = rgb(123, 227, 238),
				TailGreen2 = rgb(125, 251, 189),
				Glow = rgb(125, 255, 178),
				Brass = rgb(212, 145, 58),
				Iron = rgb(47, 43, 58),
				Eye = rgb(20, 12, 28),
				Glow2 = rgb(255, 181, 48),
				FlameFlameGreen = rgb(208, 255, 234),
				FlameFlameGreen2 = rgb(178, 255, 212),
				FlameFlameGreen3 = rgb(139, 255, 186),
				Glass = rgb(191, 255, 224),
			},
			Materials = {
				TailGreen = Enum.Material.Neon,
				TailTeal = Enum.Material.Neon,
				TailGreen2 = Enum.Material.Neon,
				Glow = Enum.Material.Neon,
				Brass = Enum.Material.SmoothPlastic,
				Iron = Enum.Material.SmoothPlastic,
				Eye = Enum.Material.SmoothPlastic,
				Glow2 = Enum.Material.Neon,
				FlameFlameGreen = Enum.Material.Neon,
				FlameFlameGreen2 = Enum.Material.Neon,
				FlameFlameGreen3 = Enum.Material.Neon,
				Glass = Enum.Material.Glass,
			},
			PostProcess = seeThrough({
				TailGreen = 0.51,
				TailTeal = 0.75,
				TailGreen2 = 0.32,
				FlameFlameGreen = 0.11,
				FlameFlameGreen2 = 0.30,
				FlameFlameGreen3 = 0.49,
				Glass = 0.45,
			}),
			Fallback = function(m)
				h.block(m, "Glow2", Vector3.new(2.29, 0.90, 2.34), Vector3.new(-0.06, 1.33, 0.00))
			end,
		},
		-- Hat: the Leaf Crown.
		LeafCrown = {
			Height = 0.521,
			AssetId = 86067084657399,
			Palette = {
				Bark = rgb(102, 65, 37),
				Berry = rgb(192, 43, 39),
				Leaf = rgb(255, 138, 42),
				Leaf2 = rgb(255, 193, 59),
				Leaf3 = rgb(232, 82, 30),
				Acorn = rgb(168, 99, 46),
			},
			Materials = {
				Bark = Enum.Material.SmoothPlastic,
				Berry = Enum.Material.SmoothPlastic,
				Leaf = Enum.Material.SmoothPlastic,
				Leaf2 = Enum.Material.SmoothPlastic,
				Leaf3 = Enum.Material.SmoothPlastic,
				Acorn = Enum.Material.SmoothPlastic,
			},
			Fallback = function(m)
				h.block(m, "Berry", Vector3.new(1.48, 0.49, 1.47), Vector3.new(-0.01, 0.27, 0.01))
			end,
		},
		-- Hat: the Scarecrow Hat.
		ScarecrowHat = {
			Height = 0.788,
			AssetId = 140313998451046,
			Palette = {
				Patch = rgb(106, 79, 184),
				Glow = rgb(255, 181, 48),
				Crow = rgb(26, 22, 34),
				Beak = rgb(224, 160, 48),
				Straw = rgb(217, 178, 90),
				Hatband = rgb(122, 42, 26),
			},
			Materials = {
				Patch = Enum.Material.SmoothPlastic,
				Glow = Enum.Material.Neon,
				Crow = Enum.Material.SmoothPlastic,
				Beak = Enum.Material.SmoothPlastic,
				Straw = Enum.Material.SmoothPlastic,
				Hatband = Enum.Material.SmoothPlastic,
			},
			Fallback = function(m)
				h.block(m, "Straw", Vector3.new(2.79, 0.25, 2.79), Vector3.new(0.00, 0.12, -0.00))
			end,
		},
		-- Hat: the Antler Circlet.
		AntlerCirclet = {
			Height = 1.641,
			AssetId = 78569245208088,
			Palette = {
				AntlerOrange = rgb(212, 146, 54),
				AntlerOrange2 = rgb(250, 177, 48),
				AntlerOrange3 = rgb(143, 96, 36),
				Leaf = rgb(255, 194, 61),
				Leaf2 = rgb(184, 52, 35),
				Leaf3 = rgb(232, 82, 30),
				Leaf4 = rgb(255, 138, 42),
				Glow = rgb(255, 226, 122),
			},
			Materials = {
				AntlerOrange = Enum.Material.SmoothPlastic,
				AntlerOrange2 = Enum.Material.Neon,
				AntlerOrange3 = Enum.Material.SmoothPlastic,
				Leaf = Enum.Material.SmoothPlastic,
				Leaf2 = Enum.Material.SmoothPlastic,
				Leaf3 = Enum.Material.SmoothPlastic,
				Leaf4 = Enum.Material.SmoothPlastic,
				Glow = Enum.Material.Neon,
			},
			Fallback = function(m)
				h.block(m, "AntlerOrange", Vector3.new(2.51, 1.50, 1.42), Vector3.new(0.00, 0.75, 0.00))
			end,
		},
		-- Hat: the Acorn Helm.
		AcornHelm = {
			Height = 0.956,
			AssetId = 121083152105198,
			Palette = {
				AcornRidge = rgb(90, 57, 32),
				Glow = rgb(255, 181, 48),
				Leaf = rgb(255, 138, 42),
			},
			Materials = {
				AcornRidge = Enum.Material.SmoothPlastic,
				Glow = Enum.Material.Neon,
				Leaf = Enum.Material.SmoothPlastic,
			},
			Fallback = function(m)
				h.block(m, "AcornRidge", Vector3.new(1.71, 0.96, 1.71), Vector3.new(0.00, 0.48, 0.00))
			end,
		},
		-- Hat: the Crescent Moon.
		CrescentMoon = {
			Height = 1.326,
			AssetId = 92669165397886,
			Palette = {
				MoonhatOrange = rgb(255, 207, 122),
				Glow = rgb(255, 255, 255),
				Crow = rgb(26, 22, 34),
			},
			Materials = {
				MoonhatOrange = Enum.Material.Neon,
				Glow = Enum.Material.Neon,
				Crow = Enum.Material.SmoothPlastic,
			},
			Fallback = function(m)
				h.block(m, "Glow", Vector3.new(1.81, 0.58, 1.04), Vector3.new(-0.09, 0.87, 0.00))
			end,
		},
	}
end
