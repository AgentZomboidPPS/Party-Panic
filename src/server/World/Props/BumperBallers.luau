-- Props for Bumper Ballers. MeshLibrary loads this file at startup (see World/Props/README.md).
-- The meshes come from tools/meshgen/props/BumperBallers.py; until they're uploaded the Fallback is
-- used. Balls: Shell takes the rider's color (MeshLibrary.Get Colors), Pattern stays white.
return function(h)
	local ballPalette = { Shell = h.rgb(240, 70, 70), Pattern = h.rgb(248, 248, 248) }
	local ballMaterials = { Shell = Enum.Material.SmoothPlastic, Pattern = Enum.Material.SmoothPlastic }
	return {
		BumperBallGores = {
			Height = 8,
			AssetId = 101756819052049,
			Palette = ballPalette,
			Materials = ballMaterials,
			Fallback = function(m)
				h.ball(m, "Shell", 8, Vector3.new(0, 4, 0))
				h.roller(m, "Pattern", 8.12, 1.2, Vector3.new(0, 4, 0))
			end,
		},
		BumperBallBands = {
			Height = 8,
			AssetId = 124794818084464,
			Palette = ballPalette,
			Materials = ballMaterials,
			Fallback = function(m)
				h.ball(m, "Shell", 8, Vector3.new(0, 4, 0))
				h.pillar(m, "Pattern", 8.12, 1.4, Vector3.new(0, 4, 0))
			end,
		},
		BumperBallDots = {
			Height = 8,
			AssetId = 124123644253149,
			Palette = ballPalette,
			Materials = ballMaterials,
			Fallback = function(m)
				h.ball(m, "Shell", 8, Vector3.new(0, 4, 0))
				for _, offset in { Vector3.yAxis, -Vector3.yAxis, Vector3.xAxis, -Vector3.xAxis } do
					h.ball(m, "Pattern", 2.4, Vector3.new(0, 4, 0) + offset * 3.45)
				end
			end,
		},
		-- The beach ring, striped warning lip, cliffs, surf rocks and foam. The grass top is a part
		-- the mode builds (it's also what the balls roll on); this mesh's top sits 0.15 above it.
		BumperIsland = {
			Height = 14,
			AssetId = 135104412261869,
			Palette = {
				Sand = h.rgb(240, 222, 165),
				StripeRed = h.rgb(232, 62, 62),
				StripeWhite = h.rgb(255, 255, 255),
				Rock = h.rgb(128, 120, 112),
				Foam = h.rgb(245, 252, 255),
			},
			Materials = { Rock = Enum.Material.Slate, Foam = Enum.Material.SmoothPlastic },
			Fallback = function(m)
				h.pillar(m, "Rock", 104, 4, Vector3.new(0, 2, 0))
				h.pillar(m, "Rock", 96, 8, Vector3.new(0, 8, 0))
				h.pillar(m, "Sand", 92, 1.6, Vector3.new(0, 12.9, 0))
			end,
			PostProcess = function(model: Model)
				local foam = model:FindFirstChild("Foam", true)
				if foam and foam:IsA("BasePart") then
					foam.Transparency = 0.25
					foam.CastShadow = false
				end
			end,
		},
		BumperPalm = {
			Height = 18.35,
			AssetId = 84557085753971,
			Palette = {
				Trunk = h.rgb(150, 110, 72),
				Leaves = h.rgb(66, 168, 72),
				Coconuts = h.rgb(110, 74, 40),
			},
			Materials = { Trunk = Enum.Material.Wood },
			Fallback = function(m)
				h.pillar(m, "Trunk", 1.2, 15, Vector3.new(0, 7.5, 0))
				h.blob(m, "Leaves", Vector3.new(12, 3, 12), Vector3.new(0, 15.5, 0))
				h.ball(m, "Coconuts", 1.1, Vector3.new(0.6, 14.4, 0))
			end,
		},
		BumperIslet = {
			Height = 3.57,
			AssetId = 118505733776037,
			Palette = { Sand = h.rgb(240, 222, 165), Rock = h.rgb(128, 120, 112), Grass = h.rgb(90, 180, 80) },
			Materials = { Rock = Enum.Material.Slate },
			Fallback = function(m)
				h.blob(m, "Sand", Vector3.new(20, 6, 20), Vector3.new(0, 0.6, 0))
			end,
		},
	}
end
