-- Props for the lobby's Skee-Ball arcade (owner: "Can we also add skiball to the lobby?"). Meshes:
-- tools/meshgen/props/Arcade.py, built from the ball path's numbers (Shared/Logic/SkeeBall), so
-- the lane, hop and rings a ball follows are the ones you see. World/Arcade.luau places them; the
-- client (Controllers/SkeeBallController) rolls the balls and lights the pieces up:
--   ArcadeSkeeMachine  a machine, its player's side at -Z: maple lane, red hop, the ring board in
--                      a caged target box (Band10..Band50 round the middle, Cup100L/Cup100R in the
--                      top corners, flashed when a ball drops in), a score screen and a lit
--                      SKEE-BALL marquee (BulbsA / BulbsB chase), and the chute along the
--                      right-hand rail where the balls wait. Its box is centered on its pivot.
--   ArcadeSkeeBall     a ball with a white band (so you can see it roll).
--   ArcadeTicketFloor  the arcade's patio of giant tickets and the ticket path to it.
--   ArcadeBestBoard    the TODAY'S BEST board over the machines, on candy-striped posts.
-- Names start with "Arcade" so they never clash with anyone else's props.
return function(h)
	local rgb = h.rgb
	local Build = h.Build
	local neon = Enum.Material.Neon
	local metal = Enum.Material.Metal

	-- A part tilted back by `degrees` about X (the lane's and the board's slopes).
	local function tilted(
		m: Model,
		name: string,
		size: Vector3,
		position: Vector3,
		degrees: number,
		shape: Enum.PartType?
	)
		return Build.Part({
			Name = name,
			Shape = shape or Enum.PartType.Block,
			Size = size,
			CFrame = CFrame.new(position) * CFrame.Angles(math.rad(-degrees), 0, 0),
			Parent = m,
		})
	end

	-- A disc lying on the ring board (which rises 0.75 per stud, about 36.9 degrees), centered
	-- `w` up it from its bottom edge, `lift` out of it.
	local function onBoard(m: Model, name: string, diameter: number, u: number, w: number, lift: number)
		local normal = Vector3.new(0, 0.8, -0.6)
		local position = Vector3.new(-u, 3.15 + w * 0.6, 2.65 + w * 0.8) + normal * lift
		return Build.Part({
			Name = name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, diameter, diameter),
			CFrame = CFrame.fromMatrix(position, normal, Vector3.xAxis),
			Parent = m,
		})
	end

	return {
		ArcadeSkeeMachine = {
			Height = 12.09,
			AssetId = 0,
			Collide = true,
			Palette = {
				Cabinet = rgb(255, 84, 150), -- World/Arcade gives each machine its own color
				Base = rgb(52, 36, 104),
				Glow = rgb(255, 120, 220),
				Trim = rgb(255, 204, 64),
				Stripes = rgb(255, 255, 255),
				Stars = rgb(255, 222, 96),
				Chute = rgb(225, 232, 245),
				Lane = rgb(240, 202, 150),
				Hop = rgb(240, 70, 80),
				Arrows = rgb(255, 255, 255),
				Board = rgb(42, 34, 110),
				Band10 = rgb(156, 108, 255),
				Band20 = rgb(64, 196, 255),
				Band30 = rgb(110, 226, 140),
				Band40 = rgb(255, 204, 64),
				Band50 = rgb(255, 84, 150),
				Lips = rgb(255, 255, 255),
				Holes = rgb(22, 16, 38),
				Cup100L = rgb(255, 160, 40),
				Cup100R = rgb(255, 160, 40),
				Gutter = rgb(44, 36, 76),
				Back = rgb(86, 62, 170),
				Tufts = rgb(255, 204, 64),
				Cage = rgb(225, 232, 245),
				Display = rgb(24, 20, 40),
				Marquee = rgb(255, 204, 64),
				Sign = rgb(40, 24, 90),
				BulbsA = rgb(255, 240, 170),
				BulbsB = rgb(255, 170, 220),
			},
			Materials = {
				Glow = neon,
				Trim = metal,
				Chute = metal,
				Cage = metal,
				Lane = Enum.Material.Wood,
				Cup100L = metal,
				Cup100R = metal,
				Tufts = metal,
				BulbsA = neon,
				BulbsB = neon,
				Back = Enum.Material.Fabric,
			},
			Fallback = function(m)
				h.block(m, "Base", Vector3.new(5.4, 0.32, 14.6), Vector3.new(0, 0.16, 0))
				for _, side in { -1, 1 } do
					h.block(m, "Cabinet", Vector3.new(0.98, 3.3, 9.1), Vector3.new(side * 2.11, 1.95, -2.6))
					h.block(m, "Cabinet", Vector3.new(0.73, 5.7, 4.65), Vector3.new(side * 2.24, 3.15, 4.28))
					h.block(m, "Trim", Vector3.new(1.2, 0.14, 9.2), Vector3.new(side * 2.1, 3.67, -2.6))
					h.block(m, "Glow", Vector3.new(0.1, 0.1, 8.6), Vector3.new(side * 1.62, 3.8, -2.6)).Material = neon
				end
				h.block(m, "Cabinet", Vector3.new(5.2, 2.32, 0.5), Vector3.new(0, 1.46, -6.85))
				h.block(m, "Cabinet", Vector3.new(5.2, 8.85, 0.6), Vector3.new(0, 4.73, 6.9))
				tilted(m, "Lane", Vector3.new(3.24, 0.6, 8.05), Vector3.new(0, 2.33, -2.6), 4)
				tilted(m, "Hop", Vector3.new(3.24, 0.5, 0.65), Vector3.new(0, 2.85, 1.66), 28)
				h.block(m, "Gutter", Vector3.new(3.74, 0.9, 0.95), Vector3.new(0, 2.25, 2.3))
				tilted(m, "Board", Vector3.new(3.74, 0.3, 3.9), Vector3.new(0, 4.2, 4.3), 36.87)
				for index, ring in { { 10, 3.2 }, { 20, 2.54 }, { 30, 1.94 }, { 40, 1.36 }, { 50, 0.8 } } do
					onBoard(m, "Band" .. ring[1], ring[2], 0, 1.85, 0.02 * index)
				end
				onBoard(m, "Cup100L", 0.75, -1.36, 3.4, 0.02)
				onBoard(m, "Cup100R", 0.75, 1.36, 3.4, 0.02)
				h.block(m, "Back", Vector3.new(3.74, 2.8, 0.3), Vector3.new(0, 6.05, 6.75))
				h.block(m, "Cage", Vector3.new(4.5, 0.1, 0.1), Vector3.new(0, 7.45, 3.2))
				h.block(m, "Cage", Vector3.new(4.5, 0.1, 0.1), Vector3.new(0, 7.45, 5.4))
				h.block(m, "Chute", Vector3.new(0.12, 0.12, 7), Vector3.new(-2.48, 3.9, -3.6))
				h.block(m, "Chute", Vector3.new(0.12, 0.12, 7), Vector3.new(-1.68, 3.9, -3.6))
				h.block(m, "Display", Vector3.new(4.8, 1.95, 0.5), Vector3.new(0, 8.3, 6.65))
				h.block(m, "Marquee", Vector3.new(5.2, 2.5, 0.6), Vector3.new(0, 10.4, 6.9))
				h.block(m, "Sign", Vector3.new(4.86, 1.46, 0.08), Vector3.new(0, 10.05, 6.48))
				for index = 0, 5 do
					local part = h.ball(
						m,
						if index % 2 == 0 then "BulbsA" else "BulbsB",
						0.26,
						Vector3.new(-2.1 + index * 0.84, 11.5, 6.4)
					)
					part.Material = neon
				end
			end,
		},
		ArcadeSkeeBall = {
			Height = 0.778,
			AssetId = 0,
			Palette = { Ball = rgb(255, 84, 150), Band = rgb(255, 255, 255) },
			Fallback = function(m)
				h.ball(m, "Ball", 0.72, Vector3.new(0, 0.389, 0))
				h.roller(m, "Band", 0.76, 0.1, Vector3.new(0, 0.389, 0))
			end,
		},
		ArcadeTicketFloor = {
			Height = 1.05,
			AssetId = 0,
			Collide = true,
			Shadow = false,
			Palette = {
				Rim = rgb(255, 255, 255),
				Band = rgb(84, 190, 238),
				Grout = rgb(250, 240, 225),
				TicketA = rgb(255, 140, 70),
				TicketB = rgb(255, 92, 150),
				TicketC = rgb(255, 204, 64),
				Stars = rgb(255, 236, 140),
			},
			Fallback = function(m)
				h.block(m, "Rim", Vector3.new(26, 0.7, 20.5), Vector3.new(0, -0.25, 5.75))
				h.block(m, "Rim", Vector3.new(7.2, 0.3, 22.5), Vector3.new(0, 0.15, -15.75))
				h.block(m, "TicketA", Vector3.new(23, 0.1, 17.5), Vector3.new(0, 0.35, 5.75))
				h.block(m, "TicketB", Vector3.new(6.2, 0.1, 22), Vector3.new(0, 0.35, -15.75))
			end,
		},
		ArcadeBestBoard = {
			Height = 22.3,
			AssetId = 0,
			Collide = true,
			Palette = {
				Posts = rgb(255, 255, 255),
				PostStripes = rgb(255, 84, 150),
				Trim = rgb(255, 204, 64),
				Panel = rgb(40, 28, 90),
				BulbsA = rgb(255, 240, 170),
				BulbsB = rgb(255, 170, 220),
				Stars = rgb(255, 214, 92),
			},
			Materials = { Trim = metal, Stars = metal, BulbsA = neon, BulbsB = neon },
			Fallback = function(m)
				for _, x in { -12.6, 12.6 } do
					h.pillar(m, "Posts", 1.1, 19.8, Vector3.new(x, 9.9, 0.6))
					h.ball(m, "Trim", 1.6, Vector3.new(x, 20.45, 0.6))
				end
				h.block(m, "Panel", Vector3.new(24, 6.4, 0.95), Vector3.new(0, 16, 0.525))
				h.block(m, "Trim", Vector3.new(24.5, 0.48, 0.5), Vector3.new(0, 19.2, 0))
				h.block(m, "Trim", Vector3.new(24.5, 0.48, 0.5), Vector3.new(0, 12.8, 0))
				h.ball(m, "Stars", 2, Vector3.new(0, 20.7, 0.3))
				for index = 0, 9 do
					local part = h.ball(
						m,
						if index % 2 == 0 then "BulbsA" else "BulbsB",
						0.4,
						Vector3.new(-10.8 + index * 2.4, 19.2, -0.25)
					)
					part.Material = neon
				end
			end,
		},
	}
end
