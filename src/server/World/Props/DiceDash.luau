-- Props for Dice Dash. MeshLibrary loads this file at startup (see World/Props/README.md); get one
-- with MeshLibrary.Get("DiceDashDie", { CFrame = ..., Parent = ctx.Arena }).
-- The meshes come from tools/meshgen/props/DiceDash.py; until they're uploaded the Fallbacks are used.
--
-- Only the board's tiles and pads collide (their Base and Top: the walkable plate is drawn where it
-- is solid; the mode makes the low Icon relief non-solid). Everything else is decoration.
return function(h)
	local TILE_HEIGHT = 1.24
	local tileMaterials =
		{ Base = Enum.Material.Wood, Top = Enum.Material.SmoothPlastic, Icon = Enum.Material.SmoothPlastic }
	local base = h.rgb(120, 82, 58)

	-- A tile's primitive stand-in: the same chunky slab and plate (the icon a flat disc).
	local function tileFallback(m)
		h.rounded(m, "Base", Vector3.new(9, 0.9, 9), 0.35, Vector3.new(0, 0.45, 0))
		h.rounded(m, "Top", Vector3.new(8.3, 0.4, 8.3), 0.16, Vector3.new(0, 0.9, 0))
		h.pillar(m, "Icon", 3.6, 0.24, Vector3.new(0, 1.12, 0))
	end
	-- (a fallback's first part sets the frame its size is measured in: never a turned cylinder)
	local function padFallback(m)
		h.rounded(m, "Icon", Vector3.new(4, 0.24, 4), 0.1, Vector3.new(0, 1.12, 0))
		h.pillar(m, "Base", 15, 0.9, Vector3.new(0, 0.45, 0))
		h.pillar(m, "Top", 14, 0.4, Vector3.new(0, 0.9, 0))
	end

	return {
		DiceDashDie = {
			Height = 3.672,
			AssetId = 87006048960769,
			Palette = { Body = h.rgb(250, 248, 240), Pips = h.rgb(40, 36, 60) },
			Materials = { Body = Enum.Material.SmoothPlastic, Pips = Enum.Material.SmoothPlastic },
			Fallback = function(m)
				h.rounded(m, "Body", Vector3.new(3.4, 3.4, 3.4), 0.6, Vector3.new(0, 1.836, 0))
				h.ball(m, "Pips", 0.7, Vector3.new(0, 3.322, 0))
			end,
		},
		DiceDashTile = {
			Height = TILE_HEIGHT,
			AssetId = 83438567974099,
			Collide = true,
			Precise = { "Base", "Top" },
			Palette = { Base = base, Top = h.rgb(245, 236, 212), Icon = h.rgb(205, 190, 160) },
			Materials = tileMaterials,
			Fallback = tileFallback,
		},
		DiceDashTileBoost = {
			Height = TILE_HEIGHT,
			AssetId = 91684865212653,
			Collide = true,
			Precise = { "Base", "Top" },
			Palette = { Base = base, Top = h.rgb(90, 205, 110), Icon = h.rgb(250, 255, 245) },
			Materials = tileMaterials,
			Fallback = tileFallback,
		},
		DiceDashTileSlip = {
			Height = TILE_HEIGHT,
			AssetId = 123977914482805,
			Collide = true,
			Precise = { "Base", "Top" },
			Palette = { Base = base, Top = h.rgb(80, 120, 210), Icon = h.rgb(255, 222, 70) },
			Materials = tileMaterials,
			Fallback = tileFallback,
		},
		DiceDashTileCannon = {
			Height = TILE_HEIGHT,
			AssetId = 103489491237469,
			Collide = true,
			Precise = { "Base", "Top" },
			Palette = { Base = base, Top = h.rgb(255, 150, 60), Icon = h.rgb(45, 42, 58) },
			Materials = tileMaterials,
			Fallback = tileFallback,
		},
		DiceDashTileSwap = {
			Height = TILE_HEIGHT,
			AssetId = 78737161462120,
			Collide = true,
			Precise = { "Base", "Top" },
			Palette = { Base = base, Top = h.rgb(255, 205, 50), Icon = h.rgb(255, 255, 250) },
			Materials = { Base = Enum.Material.Wood, Top = Enum.Material.Metal, Icon = Enum.Material.SmoothPlastic },
			Fallback = tileFallback,
		},
		DiceDashTileEvent = {
			Height = TILE_HEIGHT,
			AssetId = 114749537808222,
			Collide = true,
			Precise = { "Base", "Top" },
			Palette = { Base = base, Top = h.rgb(170, 110, 255), Icon = h.rgb(255, 255, 255) },
			Materials = tileMaterials,
			Fallback = tileFallback,
		},
		DiceDashTileTrap = {
			Height = TILE_HEIGHT,
			AssetId = 90587810467421,
			Collide = true,
			Precise = { "Base", "Top" },
			Palette = { Base = base, Top = h.rgb(230, 70, 80), Icon = h.rgb(70, 46, 36) },
			Materials = {
				Base = Enum.Material.Wood,
				Top = Enum.Material.SmoothPlastic,
				Icon = Enum.Material.WoodPlanks,
			},
			Fallback = tileFallback,
		},
		DiceDashPadStart = {
			Height = TILE_HEIGHT,
			AssetId = 135414053964641,
			Collide = true,
			Precise = { "Base", "Top" },
			Palette = { Base = base, Top = h.rgb(70, 160, 255), Icon = h.rgb(255, 215, 60) },
			Materials = tileMaterials,
			Fallback = padFallback,
		},
		DiceDashPadFinish = {
			Height = TILE_HEIGHT,
			AssetId = 98308065425939,
			Collide = true,
			Precise = { "Base", "Top" },
			Palette = { Base = base, Top = h.rgb(250, 250, 250), Icon = h.rgb(30, 30, 38) },
			Materials = tileMaterials,
			Fallback = padFallback,
		},
		DiceDashArchStart = {
			Height = 17,
			AssetId = 122317180580908,
			Palette = {
				Posts = h.rgb(245, 245, 250),
				Beam = h.rgb(70, 160, 255),
				Banner = h.rgb(70, 160, 255),
				Poles = h.rgb(220, 220, 228),
				Flags = h.rgb(255, 210, 60),
			},
			Materials = { Poles = Enum.Material.Metal },
			Fallback = function(m)
				h.block(m, "Posts", Vector3.new(1.5, 12, 1.5), Vector3.new(-8.8, 6, 0))
				h.block(m, "Posts", Vector3.new(1.5, 12, 1.5), Vector3.new(8.8, 6, 0))
				h.block(m, "Banner", Vector3.new(18, 3, 0.6), Vector3.new(0, 12.6, 0))
				h.block(m, "Flags", Vector3.new(0.3, 4.4, 0.3), Vector3.new(0, 15, 0))
			end,
		},
		DiceDashArchFinish = {
			Height = 17,
			AssetId = 83868574789999,
			Palette = {
				Posts = h.rgb(245, 245, 250),
				Beam = h.rgb(255, 90, 100),
				Banner = h.rgb(250, 250, 250),
				Poles = h.rgb(220, 220, 228),
				Flags = h.rgb(255, 90, 100),
				Checks = h.rgb(30, 30, 38),
			},
			Materials = { Poles = Enum.Material.Metal },
			Fallback = function(m)
				h.block(m, "Posts", Vector3.new(1.5, 12, 1.5), Vector3.new(-8.8, 6, 0))
				h.block(m, "Posts", Vector3.new(1.5, 12, 1.5), Vector3.new(8.8, 6, 0))
				h.block(m, "Banner", Vector3.new(18, 3, 0.6), Vector3.new(0, 12.6, 0))
				h.block(m, "Flags", Vector3.new(0.3, 4.4, 0.3), Vector3.new(0, 15, 0))
			end,
		},
		DiceDashSpring = {
			Height = 2.685,
			AssetId = 87290167864681,
			Palette = { Base = h.rgb(70, 72, 90), Coil = h.rgb(200, 205, 220), Plate = h.rgb(90, 205, 110) },
			Materials = { Coil = Enum.Material.Metal, Base = Enum.Material.Metal },
			Fallback = function(m)
				h.block(m, "Base", Vector3.new(3.4, 0.4, 3.4), Vector3.new(0, 0.2, 0))
				h.pillar(m, "Coil", 2, 1.9, Vector3.new(0, 1.25, 0))
				h.block(m, "Plate", Vector3.new(3.6, 0.35, 3.6), Vector3.new(0, 2.3, 0))
			end,
		},
		DiceDashCannon = {
			Height = 4.047,
			AssetId = 71613096589997,
			Palette = { Barrel = h.rgb(58, 60, 74), Carriage = h.rgb(160, 100, 58), Wheels = h.rgb(110, 70, 45) },
			Materials = {
				Barrel = Enum.Material.Metal,
				Carriage = Enum.Material.WoodPlanks,
				Wheels = Enum.Material.Wood,
			},
			Fallback = function(m)
				h.block(m, "Carriage", Vector3.new(2, 1.3, 3.2), Vector3.new(0, 1.35, 0.6))
				h.capsule(m, "Barrel", 3.6, 1.5, CFrame.new(0, 2.6, -0.4) * CFrame.Angles(math.rad(-72), 0, 0))
			end,
		},
		DiceDashTableLeg = {
			Height = 29.7,
			AssetId = 78884615498790,
			Palette = { Leg = h.rgb(150, 100, 62) },
			Materials = { Leg = Enum.Material.Wood },
			Fallback = function(m)
				h.rounded(m, "Leg", Vector3.new(4, 29.7, 4), 1.2, Vector3.new(0, 14.85, 0))
			end,
		},
		DiceDashSpinner = {
			Height = 1.9,
			AssetId = 96950710674004,
			Palette = {
				Card = h.rgb(250, 245, 230),
				SegA = h.rgb(255, 90, 100),
				SegB = h.rgb(70, 150, 255),
				SegC = h.rgb(255, 205, 60),
				SegD = h.rgb(90, 210, 110),
				Rim = h.rgb(255, 255, 255),
				Arrow = h.rgb(40, 36, 60),
			},
			Fallback = function(m)
				h.block(m, "Card", Vector3.new(20, 0.6, 20), Vector3.new(0, 0.3, 0))
				h.pillar(m, "SegA", 16, 0.36, Vector3.new(0, 0.72, 0))
				h.block(m, "Arrow", Vector3.new(1, 0.35, 9), Vector3.new(0, 1.55, 0))
			end,
		},
		DiceDashRuleBook = {
			Height = 3.67,
			AssetId = 140052668173931,
			Palette = { Cover = h.rgb(200, 50, 70), Pages = h.rgb(250, 245, 230), Band = h.rgb(255, 205, 60) },
			Materials = { Cover = Enum.Material.Fabric },
			Fallback = function(m)
				h.block(m, "Cover", Vector3.new(16, 0.5, 22), Vector3.new(0, 0.25, 0))
				h.block(m, "Pages", Vector3.new(15.2, 2.6, 21.2), Vector3.new(0.3, 1.75, 0))
				h.block(m, "Cover", Vector3.new(16, 0.5, 22), Vector3.new(0, 3.25, 0))
			end,
		},
		DiceDashCards = {
			Height = 1.6,
			AssetId = 91706938473131,
			Palette = { Face = h.rgb(252, 250, 245), Mark = h.rgb(230, 50, 70), Back = h.rgb(60, 90, 200) },
			Fallback = function(m)
				h.block(m, "Face", Vector3.new(8, 0.2, 12), Vector3.new(0, 0.1, -4))
				h.block(m, "Back", Vector3.new(8, 1.6, 12), Vector3.new(8.5, 0.8, 1.5))
			end,
		},
		DiceDashPawn = {
			Height = 10.4,
			AssetId = 130722575504269,
			Palette = { Body = h.rgb(255, 90, 100) },
			Materials = { Body = Enum.Material.SmoothPlastic },
			Fallback = function(m)
				h.ball(m, "Body", 3.8, Vector3.new(0, 8.5, 0))
				h.pillar(m, "Body", 6, 1.2, Vector3.new(0, 0.6, 0))
				h.pillar(m, "Body", 2.4, 6.2, Vector3.new(0, 4, 0))
			end,
		},
	}
end
