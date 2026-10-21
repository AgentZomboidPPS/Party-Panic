-- Props for Bumper Ballers. MeshLibrary loads this file at startup (see World/Props/README.md).
-- The meshes come from tools/meshgen/props/BumperBallers.py; until they're uploaded the Fallback is
-- used. Balls: Shell takes the rider's color (MeshLibrary.Get Colors), Pattern stays white.
return function(h)
	local white = h.rgb(248, 248, 248)
	local function ballSpec(pattern: (m: Model) -> ())
		return {
			Height = 8,
			AssetId = 0,
			Palette = { Shell = h.rgb(240, 70, 70), Pattern = white },
			Materials = { Shell = Enum.Material.SmoothPlastic, Pattern = Enum.Material.SmoothPlastic },
			Fallback = function(m)
				h.ball(m, "Shell", 8, Vector3.new(0, 4, 0))
				pattern(m)
			end,
		}
	end
	return {
		BumperBallGores = ballSpec(function(m)
			h.roller(m, "Pattern", 8.12, 1.2, Vector3.new(0, 4, 0))
		end),
		BumperBallBands = ballSpec(function(m)
			h.pillar(m, "Pattern", 8.12, 1.4, Vector3.new(0, 4, 0))
		end),
		BumperBallDots = ballSpec(function(m)
			for _, offset in
				{ Vector3.new(0, 4, 0), Vector3.new(0, -4, 0), Vector3.new(4, 0, 0), Vector3.new(-4, 0, 0) }
			do
				h.ball(m, "Pattern", 2.4, Vector3.new(0, 4, 0) + offset * 0.86)
			end
		end),
		-- The beach ring, striped warning lip, cliffs, surf rocks and foam. The grass top is a part
		-- the mode builds (it's also what the balls roll on); this mesh's top sits 0.15 above it.
		BumperIsland = {
			Height = 14,
			AssetId = 0,
			Palette = {
				Sand = h.rgb(240, 222, 165),
				StripeRed = h.rgb(232, 62, 62),
				StripeWhite = h.rgb(250, 250, 250),
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
			Height = 18.36,
			AssetId = 0,
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
			Height = 3.62,
			AssetId = 0,
			Palette = { Sand = h.rgb(240, 222, 165), Rock = h.rgb(128, 120, 112), Grass = h.rgb(90, 180, 80) },
			Materials = { Rock = Enum.Material.Slate },
			Fallback = function(m)
				h.blob(m, "Sand", Vector3.new(20, 6, 20), Vector3.new(0, 0.6, 0))
			end,
		},
	}
end
