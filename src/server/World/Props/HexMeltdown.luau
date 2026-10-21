-- Props for Hex Meltdown (meshes from tools/meshgen/props/HexMeltdown.py): a toy volcano crater with
-- a game-show referee. Art pass, owner's words: "make every arena look really cool".
--   HexColumn     one hex of the grid: carved basalt drums, a cream rim, the colored tile and band
--                 (piece Top: the game recolors it per hex and the client makes it glow), lava cracks.
--   CraterWall    a 100 degree arc of the crater wall; four turned copies close the ring. Its pivot
--                 is not the crater center (see WALL_PIVOT in MiniGames/HexMeltdown.luau).
--   LavaCrust     a raft of cooled crust split into angular plates, hot lava glowing in the cracks.
--   RefereeStand  the basalt plinth with the striped referee stage on top (the stage is the top).
--   RefereeBot    the referee robot, holding up the call flag on its right (+X). The server colors
--                 the Flag piece with every call.
--   CallMarquee   the light-bulb frame the call board sits in.
--   LavaTorch     basalt torch with a gold bowl and a big flame, either side of the referee.
-- The fallbacks use the same piece names, so the game code works with either.

return function(h)
	local rgb = h.rgb
	local Shapes = h.Shapes

	local BASALT = rgb(84, 60, 80)
	local GOLD = rgb(255, 196, 60)
	local BULB = rgb(255, 236, 190)
	local LAVA = rgb(255, 130, 40)

	-- A hexagonal prism (flat-top, corners on +-X) as one cached union.
	local function hex(m: Model, name: string, radius: number, height: number, y: number): BasePart
		local width, depth = radius, radius * math.sqrt(3)
		return Shapes.Custom(`PropHex|{radius}|{height}`, function(piece)
			return {
				piece(Vector3.new(width, height, depth), CFrame.identity),
				piece(Vector3.new(width, height, depth), CFrame.Angles(0, math.rad(60), 0)),
				piece(Vector3.new(width, height, depth), CFrame.Angles(0, math.rad(120), 0)),
			}
		end, Vector3.new(radius * 2, height, depth), { Name = name, CFrame = CFrame.new(0, y, 0), Parent = m })
	end

	local props = {
		HexColumn = {
			Height = 30.95,
			AssetId = 101443752523189,
			Palette = { Rock = BASALT, Top = rgb(250, 250, 255), Rim = rgb(255, 244, 226), Glow = LAVA },
			Materials = { Glow = Enum.Material.Neon },
			Fallback = function(m)
				hex(m, "Rock", 6.4, 26.6, 13.3)
				hex(m, "Top", 6.6, 3, 28)
				hex(m, "Rim", 7.45, 1, 29.85)
				hex(m, "Top", 6.95, 0.6, 30.65)
			end,
		},
		CraterWall = {
			Height = 38.3,
			AssetId = 72361166933085,
			Shadow = false,
			Palette = { Rock = rgb(66, 50, 62), Ledge = rgb(104, 74, 88), Lava = LAVA },
			Materials = { Lava = Enum.Material.Neon },
			Fallback = function(m)
				-- Three lumpy ridges along the arc (mesh coordinates: the arc bulges toward -Z).
				for _, spot in { { -62, -112, 0.55 }, { 0, -128, 0.5 }, { 62, -112, -0.55 } } do
					local ridge = h.blob(m, "Rock", Vector3.new(80, 38, 34), Vector3.new(spot[1], 19, spot[2]))
					ridge.CFrame = CFrame.new(spot[1], 19, spot[2]) * CFrame.Angles(0, spot[3], 0)
				end
				h.block(m, "Ledge", Vector3.new(4, 0.5, 4), Vector3.new(0, 0.25, -62))
			end,
		},
		LavaCrust = {
			Height = 2.73,
			AssetId = 140539903076790,
			Shadow = false,
			Palette = { Crust = rgb(88, 52, 58), Glow = rgb(255, 176, 64) },
			Materials = { Glow = Enum.Material.Neon },
			Fallback = function(m)
				h.block(m, "Glow", Vector3.new(9.5, 1.6, 10), Vector3.new(0, 0.8, 0))
				for _, plate in { { -2.4, -2.6, 0.3 }, { 2.2, -2.4, -0.2 }, { -2.1, 2.7, -0.4 }, { 2.4, 2.5, 0.25 } } do
					local part = h.block(m, "Crust", Vector3.new(3.8, 2, 4.2), Vector3.new(plate[1], 1.35, plate[2]))
					part.CFrame = CFrame.new(plate[1], 1.35, plate[2]) * CFrame.Angles(0, plate[3], 0)
				end
			end,
		},
		RefereeStand = {
			Height = 19.3,
			AssetId = 100506146578384,
			Palette = {
				Rock = BASALT,
				Stage = rgb(250, 248, 240),
				StageAlt = rgb(48, 42, 62),
				Trim = GOLD,
				Bulbs = BULB,
			},
			Materials = { Bulbs = Enum.Material.Neon },
			Fallback = function(m)
				h.pillar(m, "Rock", 16, 18, Vector3.new(0, 9, 0))
				h.pillar(m, "Stage", 22, 1.3, Vector3.new(0, 18.65, 0))
				h.pillar(m, "Trim", 22.6, 0.6, Vector3.new(0, 18.4, 0))
			end,
		},
		RefereeBot = {
			Height = 18.41,
			AssetId = 80595116655074,
			Palette = {
				Body = rgb(248, 248, 255),
				Dark = rgb(46, 42, 60),
				Eyes = rgb(70, 230, 255),
				Bulb = rgb(255, 70, 80),
				Gold = GOLD,
				Lanyard = rgb(255, 70, 90),
				Flag = rgb(255, 255, 255),
			},
			Materials = { Eyes = Enum.Material.Neon, Bulb = Enum.Material.Neon },
			Fallback = function(m)
				-- Same layout as the mesh: body at x = 0, flag out to x = 19.3.
				h.rounded(m, "Body", Vector3.new(6.2, 5.4, 4.4), 1.2, Vector3.new(0, 4.6, 0))
				h.rounded(m, "Body", Vector3.new(5.4, 4.2, 4.4), 1.2, Vector3.new(0, 10.1, 0))
				h.block(m, "Eyes", Vector3.new(3.6, 1.2, 0.4), Vector3.new(0, 10.3, -2.2))
				h.pillar(m, "Dark", 5, 2, Vector3.new(0, 1.1, 0))
				h.pillar(m, "Gold", 0.5, 10.8, Vector3.new(7.3, 12.4, -0.6))
				h.block(m, "Dark", Vector3.new(10.2, 7.2, 0.5), Vector3.new(12.7, 13.9, -0.6))
				h.block(m, "Flag", Vector3.new(9.6, 6.6, 0.7), Vector3.new(12.7, 13.9, -0.6))
				h.ball(m, "Bulb", 0.9, Vector3.new(0, 16.3, 0))
			end,
		},
		CallMarquee = {
			Height = 39.7,
			AssetId = 137569703457097,
			Palette = {
				Frame = rgb(124, 64, 214),
				Trim = GOLD,
				Bulbs = BULB,
				Badge = rgb(255, 128, 40),
				Flame = rgb(255, 228, 100),
			},
			Materials = { Bulbs = Enum.Material.Neon, Flame = Enum.Material.Neon },
			Fallback = function(m)
				h.block(m, "Frame", Vector3.new(30, 2.2, 2.2), Vector3.new(0, 32.4, 0))
				h.block(m, "Frame", Vector3.new(30, 2.2, 2.2), Vector3.new(0, 21.6, 0))
				h.block(m, "Frame", Vector3.new(2.2, 8.6, 2.2), Vector3.new(-13.9, 27, 0))
				h.block(m, "Frame", Vector3.new(2.2, 8.6, 2.2), Vector3.new(13.9, 27, 0))
				h.block(m, "Frame", Vector3.new(2.2, 20.5, 2.2), Vector3.new(-4, 10.25, 0))
				h.block(m, "Frame", Vector3.new(2.2, 20.5, 2.2), Vector3.new(4, 10.25, 0))
				h.blob(m, "Badge", Vector3.new(7.2, 6.2, 1.6), Vector3.new(0, 36.5, 0))
			end,
		},
		LavaTorch = {
			Height = 30.9,
			AssetId = 78134047543428,
			Palette = { Rock = BASALT, Gold = GOLD, Flame = rgb(255, 120, 30), Core = rgb(255, 230, 110) },
			Materials = { Flame = Enum.Material.Neon, Core = Enum.Material.Neon },
			Fallback = function(m)
				h.pillar(m, "Rock", 6, 21.2, Vector3.new(0, 10.6, 0))
				h.pillar(m, "Gold", 9.6, 2.8, Vector3.new(0, 22.4, 0))
				h.blob(m, "Flame", Vector3.new(6, 8, 6), Vector3.new(0, 26.8, 0))
			end,
		},
	}
	-- Toy look: every piece without a material of its own is smooth plastic.
	for _, spec in props do
		local materials = spec.Materials or {}
		for name in spec.Palette do
			materials[name] = materials[name] or Enum.Material.SmoothPlastic
		end
		spec.Materials = materials
	end
	return props
end
