-- Props for Spleef (meshes from tools/meshgen/props/Spleef.py): a frozen crater with three floors of
-- snow blocks over an icy pool.
--   SpleefBlock    one snow block of a floor (4 x 3 x 4): two packed courses under a pillowy cap.
--                  One piece, so a block is one part; the game colors it per floor.
--   SpleefShovel   the shovel everyone carries (blade at the bottom, D-grip on top).
--   SpleefCliff    a 60 degree arc of the crater rim, authored around the crater's middle (see
--                  CLIFF_* in MiniGames/Spleef.luau): ice cliff face, snowy crest, outer slope.
--   SpleefPine     a snowy pine for the rim and the snowfield.
--   SpleefCrystal  a cluster of ice crystals at the foot of the cliffs.
--   SpleefFloe     a little ice floe with a snow crust, drifting on the pool.
--   SpleefPeak     a snowy mountain for the horizon.
-- The fallbacks use the same piece names, so the game code works with either.

return function(h)
	local rgb = h.rgb
	local SNOW = rgb(244, 249, 255)
	local ICE = rgb(150, 206, 242)

	return {
		SpleefBlock = {
			Height = 3,
			AssetId = 93166811023448,
			Collide = true,
			Shadow = false,
			Palette = { Snow = SNOW },
			Materials = { Snow = Enum.Material.Snow },
			Fallback = function(m)
				h.block(m, "Snow", Vector3.new(4, 3, 4), Vector3.new(0, 1.5, 0))
			end,
		},
		SpleefShovel = {
			Height = 3.6,
			AssetId = 106513613615382,
			Palette = {
				Blade = rgb(196, 206, 222),
				Collar = rgb(92, 98, 116),
				Shaft = rgb(168, 112, 64),
				Grip = rgb(232, 64, 72),
			},
			Materials = { Blade = Enum.Material.Metal, Collar = Enum.Material.Metal, Shaft = Enum.Material.Wood },
			Fallback = function(m)
				h.block(m, "Blade", Vector3.new(1.1, 1.3, 0.16), Vector3.new(0, 0.65, 0))
				h.pillar(m, "Shaft", 0.24, 2.3, Vector3.new(0, 2.4, 0))
				h.block(m, "Grip", Vector3.new(0.75, 0.22, 0.22), Vector3.new(0, 3.49, 0))
			end,
		},
		SpleefCliff = {
			Height = 30,
			AssetId = 89712776862526,
			Shadow = false,
			Palette = { Ice = ICE, Snow = SNOW, Rock = rgb(104, 118, 146) },
			Materials = { Ice = Enum.Material.Glacier, Snow = Enum.Material.Snow, Rock = Enum.Material.Slate },
			Fallback = function(m)
				-- Three icy ridges along the arc (around the crater's middle; the arc bulges toward -Z).
				for _, spot in { -20, 0, 20 } do
					local angle = math.rad(spot)
					local center = Vector3.new(math.sin(angle) * 96, 15, -math.cos(angle) * 96)
					local ridge = h.blob(m, "Ice", Vector3.new(44, 30, 60), center)
					ridge.CFrame = CFrame.new(center) * CFrame.Angles(0, -angle, 0)
				end
				h.block(m, "Snow", Vector3.new(2, 0.5, 2), Vector3.new(0, 0.25, -64))
			end,
		},
		SpleefPine = {
			Height = 16,
			AssetId = 123535835931172,
			Palette = { Trunk = rgb(112, 76, 52), Needles = rgb(38, 98, 80), Snow = SNOW },
			Materials = { Trunk = Enum.Material.Wood, Needles = Enum.Material.Grass, Snow = Enum.Material.Snow },
			Fallback = function(m)
				h.pillar(m, "Trunk", 1.2, 3, Vector3.new(0, 1.5, 0))
				h.blob(m, "Needles", Vector3.new(8, 7, 8), Vector3.new(0, 6, 0))
				h.blob(m, "Needles", Vector3.new(5.6, 6, 5.6), Vector3.new(0, 10.5, 0))
				h.blob(m, "Snow", Vector3.new(2.6, 3, 2.6), Vector3.new(0, 14.5, 0))
			end,
		},
		SpleefCrystal = {
			Height = 7,
			AssetId = 86111982411845,
			Palette = { Crystal = rgb(170, 226, 255), Base = ICE },
			Materials = { Crystal = Enum.Material.Glass, Base = Enum.Material.Glacier },
			PostProcess = function(model)
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") and part.Name == "Crystal" then
						part.Transparency = 0.15
					end
				end
			end,
			Fallback = function(m)
				h.blob(m, "Base", Vector3.new(5, 1.4, 5), Vector3.new(0, 0.7, 0))
				h.block(m, "Crystal", Vector3.new(1.4, 6, 1.4), Vector3.new(0, 3.5, 0))
				local side = h.block(m, "Crystal", Vector3.new(1, 4, 1), Vector3.new(1.3, 2.4, 0.4))
				side.CFrame = CFrame.new(1.3, 2.4, 0.4) * CFrame.Angles(0, 0, math.rad(-25))
			end,
		},
		SpleefFloe = {
			Height = 1.4,
			AssetId = 109989673837877,
			Shadow = false,
			Palette = { Ice = rgb(170, 216, 242), Snow = SNOW },
			Materials = { Ice = Enum.Material.Glacier, Snow = Enum.Material.Snow },
			Fallback = function(m)
				h.blob(m, "Ice", Vector3.new(9, 1, 7), Vector3.new(0, 0.5, 0))
				h.blob(m, "Snow", Vector3.new(7, 0.8, 5.4), Vector3.new(0, 1, 0))
			end,
		},
		SpleefPeak = {
			Height = 90,
			AssetId = 79658990894258,
			Shadow = false,
			Palette = { Rock = rgb(98, 110, 136), Snow = SNOW },
			Materials = { Rock = Enum.Material.Slate, Snow = Enum.Material.Snow },
			Fallback = function(m)
				local rock = h.block(m, "Rock", Vector3.new(90, 90, 90), Vector3.new(0, 30, 0))
				rock.CFrame = CFrame.new(0, 30, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35))
				h.blob(m, "Snow", Vector3.new(30, 30, 30), Vector3.new(0, 76, 0))
			end,
		},
	}
end
