-- Props for Messy Memory. MeshLibrary loads this file at startup (see World/Props/README.md).
-- The meshes come from tools/meshgen/props/MessyMemory.py; until they're uploaded the Fallback is
-- used. The shelf's cubbies and the counter's height match Shared/Logic/MessyMemory, so a toy the
-- game puts in a slot stands on that cubby's floor.
--
-- None of these collide (nothing here is meant to be stood on or bumped: players stay at their
-- booths, and the shop floor is a plain drawn part), so there is nothing solid where nothing is drawn.
-- A fallback that starts with a cylinder resets its pivot (m.WorldPivot), so MeshLibrary sizes it upright.
return function(h)
	local smooth = Enum.Material.SmoothPlastic
	local fabric = Enum.Material.Fabric
	local wood = Enum.Material.Wood

	return {
		MessyMemoryShelf = {
			Height = 12.7,
			AssetId = 0,
			Palette = {
				Wood = h.rgb(236, 186, 122),
				Back = h.rgb(255, 238, 210),
				Trim = h.rgb(170, 120, 210),
				Legs = h.rgb(206, 146, 92),
				Knobs = h.rgb(255, 215, 90),
			},
			Materials = { Wood = wood, Back = smooth, Trim = smooth, Legs = wood, Knobs = smooth },
			Fallback = function(m)
				h.block(m, "Back", Vector3.new(10.3, 8.5, 0.25), Vector3.new(0, 7.65, 1.07))
				for _, y in { 3.525, 6.275, 9.025, 11.775 } do
					h.block(m, "Wood", Vector3.new(10.45, 0.25, 2.4), Vector3.new(0, y, 0))
				end
				for _, x in { -5.1, -2.55, 0, 2.55, 5.1 } do
					h.block(m, "Wood", Vector3.new(0.25, 9, 2.4), Vector3.new(x, 7.4, 0))
				end
				h.block(m, "Trim", Vector3.new(10.85, 0.8, 2.6), Vector3.new(0, 12.3, 0))
				h.block(m, "Trim", Vector3.new(10.45, 0.65, 2.4), Vector3.new(0, 3.07, 0))
				for _, x in { -4.8, 4.8 } do
					h.block(m, "Legs", Vector3.new(0.5, 2.8, 0.5), Vector3.new(x, 1.4, -0.8))
					h.block(m, "Legs", Vector3.new(0.5, 2.8, 0.5), Vector3.new(x, 1.4, 0.8))
				end
			end,
		},
		MessyMemoryBooth = {
			Height = 14.9,
			AssetId = 0,
			BlocksCamera = { "Wall", "Roof" },
			Palette = {
				Wall = h.rgb(255, 240, 228),
				Roof = h.rgb(170, 120, 210),
				Awning = h.rgb(255, 120, 170),
				Awning2 = h.rgb(255, 255, 255),
				Post = h.rgb(255, 120, 170),
				Counter = h.rgb(120, 200, 235),
				CounterTop = h.rgb(250, 245, 235),
				Badges = h.rgb(255, 215, 90),
				Rod = h.rgb(255, 205, 80),
			},
			Materials = {
				Wall = smooth,
				Roof = smooth,
				Awning = fabric,
				Awning2 = fabric,
				Post = smooth,
				Counter = wood,
				CounterTop = smooth,
				Badges = smooth,
				Rod = Enum.Material.Metal,
			},
			Fallback = function(m)
				h.block(m, "Wall", Vector3.new(0.4, 14.4, 7.8), Vector3.new(-6.6, 7.2, 0.4))
				h.block(m, "Wall", Vector3.new(0.4, 14.4, 7.8), Vector3.new(6.6, 7.2, 0.4))
				h.block(m, "Wall", Vector3.new(13.6, 14.4, 0.4), Vector3.new(0, 7.2, 4.1))
				h.block(m, "Roof", Vector3.new(14, 0.5, 8.6), Vector3.new(0, 14.65, 0))
				h.block(m, "Awning", Vector3.new(13.6, 2.4, 0.36), Vector3.new(0, 13.2, -4.12))
				h.block(m, "Counter", Vector3.new(11.2, 2.35, 3.6), Vector3.new(0, 1.175, -1))
				h.block(m, "CounterTop", Vector3.new(11.7, 0.25, 4.05), Vector3.new(0, 2.475, -1.025))
				h.block(m, "Rod", Vector3.new(13, 0.18, 0.18), Vector3.new(0, 12.55, -3.72))
			end,
		},
		-- One half of a booth's curtain (the client stretches it shut or bunches it open).
		MessyMemoryCurtain = {
			Height = 12.5,
			AssetId = 0,
			Shadow = false,
			Palette = { Cloth = h.rgb(210, 40, 70), Trim = h.rgb(255, 205, 80) },
			Materials = { Cloth = fabric, Trim = fabric },
			Fallback = function(m)
				h.block(m, "Cloth", Vector3.new(6.6, 12.5, 0.12), Vector3.new(0, 6.25, 0))
				h.block(m, "Trim", Vector3.new(6.64, 0.45, 0.24), Vector3.new(0, 0.225, 0))
			end,
		},
		MessyMemorySmoke = {
			Height = 3.55,
			AssetId = 0,
			Shadow = false,
			Palette = { Puff = h.rgb(240, 238, 248) },
			Materials = { Puff = smooth },
			Fallback = function(m)
				h.ball(m, "Puff", 3, Vector3.new(0, 1.6, 0))
				h.ball(m, "Puff", 2.2, Vector3.new(1.3, 1.2, 0.3))
				h.ball(m, "Puff", 2.3, Vector3.new(-1.3, 1.3, -0.2))
			end,
		},

		-- The eight toys (each about 1.4-1.9 tall; they face -Z, the game turns them to the player).
		MessyMemoryTeddy = {
			Height = 1.78,
			AssetId = 0,
			Palette = {
				Fur = h.rgb(190, 125, 70),
				Snout = h.rgb(245, 210, 165),
				Face = h.rgb(40, 28, 28),
				Bow = h.rgb(235, 50, 90),
			},
			Materials = { Fur = fabric, Snout = fabric, Face = smooth, Bow = smooth },
			Fallback = function(m)
				h.blob(m, "Fur", Vector3.new(0.95, 1.1, 0.85), Vector3.new(0, 0.6, 0))
				h.ball(m, "Fur", 0.8, Vector3.new(0, 1.35, 0))
				h.ball(m, "Snout", 0.3, Vector3.new(0, 1.25, -0.32))
				h.ball(m, "Fur", 0.3, Vector3.new(-0.3, 1.64, 0))
				h.ball(m, "Fur", 0.3, Vector3.new(0.3, 1.64, 0))
			end,
		},
		MessyMemoryDuck = {
			Height = 1.43,
			AssetId = 0,
			Palette = { Body = h.rgb(255, 214, 40), Beak = h.rgb(255, 135, 30), Face = h.rgb(35, 30, 30) },
			Materials = { Body = smooth, Beak = smooth, Face = smooth },
			Fallback = function(m)
				h.blob(m, "Body", Vector3.new(1.25, 0.9, 1.45), Vector3.new(0, 0.45, 0.05))
				h.ball(m, "Body", 0.68, Vector3.new(0, 1.09, -0.28))
				h.blob(m, "Beak", Vector3.new(0.4, 0.14, 0.4), Vector3.new(0, 1.04, -0.6))
			end,
		},
		MessyMemoryRocket = {
			Height = 1.82,
			AssetId = 0,
			Palette = {
				Body = h.rgb(250, 250, 255),
				Nose = h.rgb(235, 55, 65),
				Window = h.rgb(110, 205, 255),
				Rim = h.rgb(185, 190, 210),
			},
			Materials = { Body = smooth, Nose = smooth, Window = Enum.Material.Glass, Rim = Enum.Material.Metal },
			Fallback = function(m)
				h.pillar(m, "Body", 0.75, 1.1, Vector3.new(0, 0.8, 0))
				m.WorldPivot = CFrame.identity
				h.ball(m, "Nose", 0.66, Vector3.new(0, 1.45, 0))
				h.block(m, "Nose", Vector3.new(1.1, 0.5, 0.08), Vector3.new(0, 0.3, 0))
				h.ball(m, "Window", 0.28, Vector3.new(0, 0.95, -0.33))
			end,
		},
		MessyMemoryRobot = {
			Height = 1.92,
			AssetId = 0,
			Palette = {
				Metal = h.rgb(150, 185, 225),
				Screen = h.rgb(40, 50, 72),
				Light = h.rgb(255, 70, 70),
				Eyes = h.rgb(90, 240, 255),
				Bolts = h.rgb(255, 200, 60),
			},
			Materials = {
				Metal = Enum.Material.Metal,
				Screen = smooth,
				Light = Enum.Material.Neon,
				Eyes = Enum.Material.Neon,
				Bolts = smooth,
			},
			Fallback = function(m)
				h.rounded(m, "Metal", Vector3.new(0.84, 0.63, 0.6), 0.1, Vector3.new(0, 0.735, 0))
				h.rounded(m, "Metal", Vector3.new(0.72, 0.5, 0.6), 0.1, Vector3.new(0, 1.35, 0))
				h.block(m, "Metal", Vector3.new(0.64, 0.45, 0.42), Vector3.new(0, 0.225, 0))
				h.block(m, "Screen", Vector3.new(0.54, 0.3, 0.06), Vector3.new(0, 1.35, -0.3))
				h.ball(m, "Light", 0.16, Vector3.new(0, 1.84, 0))
			end,
		},
		MessyMemoryBall = {
			Height = 1.65,
			AssetId = 0,
			Palette = {
				Red = h.rgb(235, 60, 60),
				White = h.rgb(252, 252, 252),
				Blue = h.rgb(60, 130, 240),
				Yellow = h.rgb(255, 215, 50),
			},
			Materials = { Red = smooth, White = smooth, Blue = smooth, Yellow = smooth },
			Fallback = function(m)
				h.ball(m, "White", 1.6, Vector3.new(0, 0.8, 0))
				h.block(m, "Red", Vector3.new(0.4, 1.62, 0.4), Vector3.new(0, 0.8, -0.62))
			end,
		},
		MessyMemoryTop = {
			Height = 1.72,
			AssetId = 0,
			Palette = { Body = h.rgb(160, 110, 235), Band = h.rgb(255, 130, 195), Handle = h.rgb(255, 205, 80) },
			Materials = { Body = smooth, Band = smooth, Handle = smooth },
			Fallback = function(m)
				h.blob(m, "Body", Vector3.new(1.4, 0.9, 1.4), Vector3.new(0, 0.7, 0))
				h.pillar(m, "Handle", 0.18, 0.6, Vector3.new(0, 1.35, 0))
			end,
		},
		MessyMemoryBlock = {
			Height = 1.52,
			AssetId = 0,
			Palette = { Block = h.rgb(90, 200, 110), Star = h.rgb(255, 225, 80) },
			Materials = { Block = smooth, Star = smooth },
			Fallback = function(m)
				h.rounded(m, "Block", Vector3.new(1.45, 1.45, 1.45), 0.16, Vector3.new(0, 0.725, 0))
				h.block(m, "Star", Vector3.new(0.7, 0.7, 0.08), Vector3.new(0, 0.725, -0.75))
			end,
		},
		MessyMemoryBoat = {
			Height = 1.88,
			AssetId = 0,
			Palette = {
				Hull = h.rgb(60, 120, 225),
				Stripe = h.rgb(255, 255, 255),
				Mast = h.rgb(190, 130, 80),
				Sail = h.rgb(255, 255, 248),
				Flag = h.rgb(235, 60, 60),
			},
			Materials = { Hull = smooth, Stripe = smooth, Mast = wood, Sail = fabric, Flag = fabric },
			Fallback = function(m)
				h.blob(m, "Hull", Vector3.new(1.7, 0.5, 0.7), Vector3.new(0, 0.25, 0))
				h.block(m, "Mast", Vector3.new(0.08, 1.35, 0.08), Vector3.new(0.05, 1.15, 0))
				h.block(m, "Sail", Vector3.new(0.6, 1.0, 0.05), Vector3.new(0.4, 1.1, 0))
			end,
		},

		-- The shop's centrepiece: an open toy chest with toys spilling out of the top.
		MessyMemoryToyBox = {
			Height = 6.53,
			AssetId = 0,
			BlocksCamera = { "Chest", "Lid" },
			Palette = {
				Chest = h.rgb(255, 150, 190),
				Trim = h.rgb(255, 215, 90),
				Lid = h.rgb(255, 150, 190),
				PileRed = h.rgb(235, 70, 70),
				PileBlue = h.rgb(80, 150, 240),
				PileYellow = h.rgb(255, 215, 60),
				PilePink = h.rgb(190, 120, 240),
			},
			Materials = {
				Chest = wood,
				Trim = smooth,
				Lid = wood,
				PileRed = smooth,
				PileBlue = smooth,
				PileYellow = smooth,
				PilePink = smooth,
			},
			Fallback = function(m)
				h.rounded(m, "Chest", Vector3.new(5.2, 2.9, 3.6), 0.2, Vector3.new(0, 1.45, -0.6))
				h.block(m, "Lid", Vector3.new(5.3, 3.7, 0.35), Vector3.new(0, 4.7, 1.6))
				h.ball(m, "PileRed", 1.5, Vector3.new(-1.2, 3.1, -0.8))
				h.ball(m, "PileBlue", 1.2, Vector3.new(0.5, 3.25, -1.3))
			end,
		},
	}
end
