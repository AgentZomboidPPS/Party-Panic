-- Props for Snowball Summit (meshes from tools/meshgen/props/SnowballSummit.py): a snowy mountain top
-- above a sea of clouds.
--   SnowballSummitPeak      the summit, authored for a platform of radius 32 (the game scales it to the
--                           round's radius): the ice band round the rim, the icy lip with icicles and
--                           the rocky mountain beneath. The snowfield inside the ice band is a real
--                           part the game builds (the one everyone stands on), so this never collides.
--   SnowballSummitSnowball  a snowball of radius 1 (2 tall); the game scales it to each ball's size.
--   SnowballSummitPine      a snowy pine (on the spires around the summit).
--   SnowballSummitFlag      a summit pennant on a pole.
--   SnowballSummitSpire     a rock pinnacle rising out of the clouds, flat snowy top (60 up).
--   SnowballSummitMountain  a jagged snowy mountain for the horizon.
-- None of them collide: the only thing anyone stands on is the summit's snowfield part.

return function(h)
	local rgb = h.rgb
	local SNOW = rgb(244, 249, 255)
	local ICE = rgb(160, 214, 246)
	local ROCK = rgb(98, 108, 134)

	return {
		SnowballSummitPeak = {
			Height = 46,
			AssetId = 0,
			Shadow = false,
			Palette = { Ice = ICE, Icicles = rgb(196, 234, 255), Snow = SNOW, Rock = ROCK },
			Materials = {
				Ice = Enum.Material.Glacier,
				Icicles = Enum.Material.Ice,
				Snow = Enum.Material.Snow,
				Rock = Enum.Material.Slate,
			},
			Fallback = function(m)
				-- The ice band (a thin disc under the game's snowfield part shows only round its rim)
				-- and the mountain narrowing beneath.
				h.pillar(m, "Ice", 65, 2.3, Vector3.new(0, 46 - 1.25, 0))
				h.pillar(m, "Snow", 60, 6, Vector3.new(0, 40.7, 0))
				h.pillar(m, "Rock", 44, 22, Vector3.new(0, 26.7, 0))
				h.pillar(m, "Rock", 22, 16, Vector3.new(0, 8, 0))
			end,
		},
		SnowballSummitSnowball = {
			Height = 2,
			AssetId = 0,
			Palette = { Snow = SNOW, Ice = rgb(178, 218, 248) },
			Materials = { Snow = Enum.Material.Snow, Ice = Enum.Material.Ice },
			Fallback = function(m)
				h.ball(m, "Snow", 2, Vector3.new(0, 1, 0))
				h.ball(m, "Ice", 0.3, Vector3.new(0.8, 1.4, 0))
			end,
		},
		SnowballSummitPine = {
			Height = 15.6,
			AssetId = 0,
			Palette = { Trunk = rgb(112, 76, 52), Needles = rgb(36, 96, 82), Snow = SNOW },
			Materials = { Trunk = Enum.Material.Wood, Needles = Enum.Material.Grass, Snow = Enum.Material.Snow },
			Fallback = function(m)
				h.pillar(m, "Trunk", 1.2, 3, Vector3.new(0, 1.5, 0))
				h.blob(m, "Needles", Vector3.new(8, 7, 8), Vector3.new(0, 6, 0))
				h.blob(m, "Needles", Vector3.new(5.6, 6, 5.6), Vector3.new(0, 10.5, 0))
				h.blob(m, "Snow", Vector3.new(2.6, 3, 2.6), Vector3.new(0, 14.1, 0))
			end,
		},
		SnowballSummitFlag = {
			Height = 10.4,
			AssetId = 0,
			Palette = { Mound = SNOW, Pole = rgb(200, 206, 220), Knob = rgb(255, 200, 60), Cloth = rgb(232, 60, 80) },
			Materials = { Mound = Enum.Material.Snow, Pole = Enum.Material.Metal, Knob = Enum.Material.Metal },
			Fallback = function(m)
				h.blob(m, "Mound", Vector3.new(3.2, 1.9, 3.2), Vector3.new(0, 0, 0))
				h.pillar(m, "Pole", 0.24, 9.6, Vector3.new(0, 5.2, 0))
				h.ball(m, "Knob", 0.52, Vector3.new(0, 10.15, 0))
				h.block(m, "Cloth", Vector3.new(4.4, 2.2, 0.1), Vector3.new(2.3, 9, 0))
			end,
		},
		SnowballSummitSpire = {
			Height = 60,
			AssetId = 0,
			Shadow = false,
			Palette = { Rock = ROCK, Snow = SNOW },
			Materials = { Rock = Enum.Material.Slate, Snow = Enum.Material.Snow },
			Fallback = function(m)
				h.pillar(m, "Rock", 20, 57, Vector3.new(0, 28.5, 0))
				h.pillar(m, "Snow", 16, 3, Vector3.new(0, 58.5, 0))
			end,
		},
		SnowballSummitMountain = {
			Height = 152,
			AssetId = 0,
			Shadow = false,
			Palette = { Rock = ROCK, Snow = SNOW },
			Materials = { Rock = Enum.Material.Slate, Snow = Enum.Material.Snow },
			Fallback = function(m)
				h.blob(m, "Rock", Vector3.new(140, 200, 140), Vector3.new(0, 52, 0))
				h.blob(m, "Snow", Vector3.new(50, 60, 50), Vector3.new(0, 122, 0))
			end,
		},
	}
end
