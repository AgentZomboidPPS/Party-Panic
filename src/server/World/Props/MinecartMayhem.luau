-- Props for Minecart Mayhem (meshes from tools/meshgen/props/MinecartMayhem.py). None of them is
-- solid: the carts are carried along the rails by the game and the riders sit in them, so there is
-- nothing anyone could stand or hang on where nothing is drawn.
--   MinecartMayhemCart        a riveted mine cart; Trim takes the rider's colour, Badge (a disc on the
--                             back) carries the rider's lane number. Wheels on the rails' top (y 0),
--                             front -Z.
--   MinecartMayhemRail*       the course's rail tiles (Start, BendL/R, JunctionL/R, Gap, Hill,
--                             Finish): rails, ties and trestles swept along the same shapes as
--                             Shared/Logic/MinecartMayhemTrack (Track.Anchor places them); the gap
--                             tile also draws the yellow take-off chevrons, which glow (Neon: owner,
--                             "you cannot see where to jump", so they read in the cave's gloom).
--                             Their fallbacks carry an invisible, non-colliding "Bounds" box the
--                             size of the mesh, so both versions get the same pivot.
--   MinecartMayhemCave        a ring of cave rock round the track with crystals on its inside.
--   MinecartMayhemPortal      the mine's portal: a cliff with the tunnel through it, a timber frame.
--   MinecartMayhemSign        the gantry over the track before a switch (the game hangs the boards).
--   MinecartMayhemPost        a post for a board beside a way.
--   MinecartMayhemTNT         a crate of dynamite (on a TNT track's rails).
--   MinecartMayhemBuffer      a dead end's buffer stop; MinecartMayhemRubble the cave-in past it.
--   MinecartMayhemCrystal     the dash crystal on the ties between the rails.
--   MinecartMayhemCluster     a cluster of big glowing crystals (cave floor).
--   MinecartMayhemLantern     a miner's lantern on a post (Glow carries the light).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Track = require(ReplicatedStorage.Shared.Logic.MinecartMayhemTrack)

return function(h)
	local rgb = h.rgb
	local wood = Enum.Material.Wood
	local metal = Enum.Material.Metal
	local neon = Enum.Material.Neon
	local rock = Enum.Material.Slate

	local railPalette = {
		Rails = rgb(128, 128, 138),
		Ties = rgb(120, 82, 50),
		Trestle = rgb(92, 62, 38),
		Marker = rgb(255, 205, 40),
	}
	local railMaterials = { Rails = metal, Ties = wood, Trestle = wood, Marker = neon }

	-- A primitive stand-in for a rail tile: rails, ties and a few posts along its paths.
	local function railFallback(name: string)
		return function(m: Model)
			local anchor = Track.Anchor[name]
			local size = Vector3.new(anchor[4], anchor[5], anchor[6])
			h.Build.Decor({
				Name = "Bounds",
				Size = size,
				CFrame = CFrame.new(anchor[1], anchor[2] + size.Y / 2, anchor[3]),
				Transparency = 1,
				Parent = m,
			})
			local course = Track.Build({ Track.RailTile[name] })
			local tile = course.Tiles[1]
			for branch, path in tile.Paths do
				local s = 0
				while s < path.Total - 0.5 do
					local s1 = math.min(s + 6, path.Total)
					local ax, ay, az = Track.At(path, s)
					local bx, by, bz = Track.At(path, s1)
					local a, b = Vector3.new(ax, ay, az), Vector3.new(bx, by, bz)
					local frame = CFrame.lookAt((a + b) / 2, b)
					local skip = branch == 2 and math.abs(ax - Track.At(tile.Paths[1], s)) < 4
					local gap = tile.K == "Gap" and -az > Track.GAP_FROM - 3 and -az < Track.GAP_TO
					if not skip and not gap then
						for _, side in { -1, 1 } do
							h.Build.Decor({
								Name = "Rails",
								Size = Vector3.new(0.32, 0.3, (b - a).Magnitude + 0.05),
								CFrame = frame * CFrame.new(side * Track.GAUGE / 2, 0.6, 0),
								Parent = m,
							})
						end
						h.Build.Decor({
							Name = "Ties",
							Size = Vector3.new(5, 0.25, 1.4),
							CFrame = frame * CFrame.new(0, 0.32, 0),
							Parent = m,
						})
					end
					s = s1
				end
			end
		end
	end

	local function rail(name: string)
		local anchor = Track.Anchor[name]
		return {
			Height = anchor[5],
			Shadow = true,
			Palette = railPalette,
			Materials = railMaterials,
			Fallback = railFallback(name),
		}
	end
	local timber = rgb(110, 76, 46)
	local rockColor = rgb(82, 70, 96)
	local crystal = rgb(120, 220, 255)

	local props = {
		MinecartMayhemCart = {
			Height = 3.12,
			AssetId = 88019574168994, -- tools/upload_assets.py --only MinecartMayhemCart fills this in
			Shadow = true,
			Palette = {
				Body = rgb(96, 100, 110),
				Trim = rgb(255, 80, 90),
				Rivets = rgb(225, 185, 95),
				Chassis = rgb(60, 55, 60),
				Wheels = rgb(45, 45, 52),
				Badge = rgb(250, 250, 245),
			},
			Materials = { Body = metal, Rivets = metal, Chassis = metal, Wheels = metal },
			Fallback = function(m)
				h.block(m, "Body", Vector3.new(3.4, 2.0, 4.4), Vector3.new(0, 2.0, 0))
				h.block(m, "Trim", Vector3.new(3.6, 0.25, 4.6), Vector3.new(0, 3.0, 0))
				h.block(m, "Chassis", Vector3.new(2.5, 0.3, 4.0), Vector3.new(0, 0.8, 0))
				for _, z in { -1.4, 1.4 } do
					h.roller(m, "Wheels", 1.1, 3.4, Vector3.new(0, 0.55, z))
				end
				h.Build.Decor({
					Name = "Badge",
					Size = Vector3.new(1.1, 1.1, 0.06),
					CFrame = CFrame.new(0, 2.0, 2.24),
					Parent = m,
				})
			end,
		},
		-- The rail tiles share everything but their shape (filled in below); each keeps its own block
		-- with its AssetId, which is where the upload and permission tools look.
		MinecartMayhemRailStart = {
			AssetId = 130707805490539,
			Rail = true,
		},
		MinecartMayhemRailBendL = {
			AssetId = 115815017233744,
			Rail = true,
		},
		MinecartMayhemRailBendR = {
			AssetId = 77662819118252,
			Rail = true,
		},
		MinecartMayhemRailJunctionL = {
			AssetId = 106494779995004,
			Rail = true,
		},
		MinecartMayhemRailJunctionR = {
			AssetId = 112712754403066,
			Rail = true,
		},
		MinecartMayhemRailGap = {
			AssetId = 73589202258867,
			Rail = true,
		},
		MinecartMayhemRailHill = {
			AssetId = 71146920759880,
			Rail = true,
		},
		MinecartMayhemRailFinish = {
			AssetId = 131188828381113,
			Rail = true,
		},
		MinecartMayhemCave = {
			Height = 88.63,
			AssetId = 72581873531246,
			Shadow = false,
			Palette = { Rock = rockColor, Crystal = crystal },
			Materials = { Rock = rock, Crystal = neon },
			Fallback = function(m)
				for _, side in { -1, 1 } do
					h.block(m, "Rock", Vector3.new(9, 60, 54), Vector3.new(side * 50, 30, 0))
				end
				h.block(m, "Rock", Vector3.new(110, 9, 54), Vector3.new(0, 84, 0))
			end,
		},
		MinecartMayhemPortal = {
			Height = 111.5,
			AssetId = 130311793125291,
			Shadow = true,
			Palette = { Rock = rgb(110, 98, 92), Timber = timber, Glow = rgb(255, 200, 120) },
			Materials = { Rock = rock, Timber = wood, Glow = neon },
			Fallback = function(m)
				h.block(m, "Rock", Vector3.new(72, 111, 18), Vector3.new(-43.5, 55.5, 0))
				h.block(m, "Rock", Vector3.new(72, 111, 18), Vector3.new(43.5, 55.5, 0))
				h.block(m, "Rock", Vector3.new(15, 52, 18), Vector3.new(0, 85.5, 0))
				h.block(m, "Rock", Vector3.new(15, 44, 18), Vector3.new(0, 22, 0))
				h.block(m, "Timber", Vector3.new(17, 1.5, 2), Vector3.new(0, 59.4, -9.6))
			end,
		},
		MinecartMayhemSign = {
			Height = 35,
			AssetId = 137126766476536,
			Shadow = true,
			Palette = { Timber = timber, Chains = rgb(70, 70, 75), Glow = rgb(255, 200, 120) },
			Materials = { Timber = wood, Glow = neon },
			Fallback = function(m)
				for _, side in { -1, 1 } do
					h.block(m, "Timber", Vector3.new(0.7, 35, 0.7), Vector3.new(side * 7.2, 17.5, 0))
				end
				h.block(m, "Timber", Vector3.new(15.6, 0.7, 0.8), Vector3.new(0, 34.65, 0))
			end,
		},
		MinecartMayhemPost = {
			Height = 29,
			AssetId = 91043378019756,
			Shadow = true,
			Palette = { Timber = timber },
			Materials = { Timber = wood },
			Fallback = function(m)
				h.block(m, "Timber", Vector3.new(0.5, 29, 0.5), Vector3.new(0, 14.5, 0))
			end,
		},
		MinecartMayhemTNT = {
			Height = 2.87,
			AssetId = 98077139723023,
			Shadow = true,
			Palette = {
				Crate = rgb(170, 120, 70),
				Slats = rgb(125, 85, 50),
				Sticks = rgb(220, 50, 45),
				Band = rgb(40, 35, 35),
				Fuse = rgb(230, 200, 150),
			},
			Materials = { Crate = wood, Slats = wood },
			Fallback = function(m)
				h.block(m, "Crate", Vector3.new(1.7, 1.3, 1.3), Vector3.new(0, 0.65, 0))
				h.block(m, "Sticks", Vector3.new(1.2, 1.0, 0.8), Vector3.new(0, 1.8, 0))
				h.block(m, "Fuse", Vector3.new(0.1, 0.57, 0.1), Vector3.new(0, 2.585, 0))
			end,
		},
		MinecartMayhemBuffer = {
			Height = 2.63,
			AssetId = 106185453978193,
			Shadow = true,
			Palette = {
				Timber = timber,
				StripeA = rgb(230, 50, 50),
				StripeB = rgb(245, 245, 240),
				Pads = rgb(40, 40, 45),
			},
			Materials = { Timber = wood },
			Fallback = function(m)
				for _, x in { -1.5, 1.5 } do
					h.block(m, "Timber", Vector3.new(0.6, 2.6, 0.6), Vector3.new(x, 1.3, 0))
				end
				h.block(m, "StripeA", Vector3.new(4.8, 0.9, 0.45), Vector3.new(0, 1.85, -0.5))
			end,
		},
		MinecartMayhemRubble = {
			Height = 4.43,
			AssetId = 104325293328734,
			Shadow = true,
			Palette = { Rock = rgb(100, 88, 104) },
			Materials = { Rock = rock },
			Fallback = function(m)
				h.blob(m, "Rock", Vector3.new(8, 4.4, 10), Vector3.new(0, 2.2, 0))
			end,
		},
		MinecartMayhemCrystal = {
			Height = 1.16,
			AssetId = 86997312242607,
			Shadow = false,
			Palette = { Crystal = rgb(110, 255, 200), Stones = rgb(90, 80, 100) },
			Materials = { Crystal = neon, Stones = rock },
			Fallback = function(m)
				h.blob(m, "Crystal", Vector3.new(0.7, 1.1, 0.7), Vector3.new(0, 0.6, 0))
				h.blob(m, "Stones", Vector3.new(1.4, 0.3, 1.3), Vector3.new(0, 0.1, 0))
			end,
		},
		MinecartMayhemCluster = {
			Height = 9.73,
			AssetId = 127888765282466,
			Shadow = false,
			Palette = { Crystal = crystal, Rock = rockColor },
			Materials = { Crystal = neon, Rock = rock },
			Fallback = function(m)
				h.blob(m, "Rock", Vector3.new(5, 1.6, 5), Vector3.new(0, 0.8, 0))
				h.blob(m, "Crystal", Vector3.new(2, 9, 2), Vector3.new(0, 5, 0))
			end,
		},
		MinecartMayhemLantern = {
			Height = 30.2,
			AssetId = 78040428653614,
			Shadow = true,
			Palette = { Timber = timber, Iron = rgb(50, 50, 55), Glow = rgb(255, 205, 120) },
			Materials = { Timber = wood, Glow = neon, Iron = metal },
			Fallback = function(m)
				h.block(m, "Timber", Vector3.new(0.4, 30.2, 0.4), Vector3.new(0, 15.1, 0))
				h.block(m, "Timber", Vector3.new(1.6, 0.3, 0.24), Vector3.new(-0.6, 30.15, 0))
				h.block(m, "Glow", Vector3.new(0.5, 1.0, 0.5), Vector3.new(-1.3, 28.6, 0))
			end,
		},
	}
	for name, spec in props do
		if spec.Rail then
			spec.Rail = nil
			for key, value in rail(name) do
				spec[key] = value
			end
		end
	end
	return props
end
