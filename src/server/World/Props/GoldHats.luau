-- Props for the GOLD PASS's hats (owner: "Also we do need a paid battle pass too. I like the current
-- free one. But the paid one should also be insane."): five hats on the Rewards Road's gold lane
-- (Shared/GoldPass), worn like the PUMPKIN HAT (World/Hats puts each on as an Accessory).
--
--   GoldPartyHat (level 10): a gold party cone with two pink spiral stripes, a white rolled trim and
--     a fluffy white pompom.
--   RoyalCrown (level 25): a gold band rising into eight pearl-tipped points, rubies and sapphires
--     set round it, a puffed red velvet cap inside and a gold orb and cross on top.
--   GoldenHalo (level 40): a glowing gold ring that floats above the head.
--   GildedTopHat (level 60): a black silk top hat with a gold band and buckle.
--   SunKingCrown (level 100): a gold circlet with twelve sun rays fanning up and out, a big glowing
--     gem in front and a glowing bead on each long ray.
--
-- The meshes come from tools/meshgen/props/GoldHats.py, made at the size each is worn on a standard
-- 1.2-stud head. Gold pieces have a little shine (Reflectance); the gems and the halo are Neon. Each
-- fallback (only if its mesh can't load) is a few primitives in the same colours.
return function(h)
	local rgb = h.rgb
	local GOLD = rgb(255, 196, 40)

	-- A little shine on the gold pieces (they catch the sky).
	local function shine(pieces: { string })
		return function(model: Model)
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and table.find(pieces, part.Name) then
					part.Reflectance = 0.18
				end
			end
		end
	end

	-- A thin flat ring of `count` blocks round the Y axis (the fallbacks' bands and halo).
	local function ring(m: Model, name: string, radius: number, y: number, thick: number, count: number)
		for index = 1, count do
			local angle = 2 * math.pi * index / count
			local block = h.block(
				m,
				name,
				Vector3.new(2 * math.pi * radius / count + 0.02, thick, thick),
				Vector3.new(math.cos(angle) * radius, y, math.sin(angle) * radius)
			)
			block.CFrame = CFrame.new(block.Position) * CFrame.Angles(0, -angle + math.pi / 2, 0)
		end
	end

	return {
		GoldPartyHat = {
			Height = 1.173, -- the mesh's own height: the cone 1.0, the pompom above it
			AssetId = 97401945002982, -- filled in by tools/upload_assets.py
			Palette = {
				PartyGold = GOLD,
				PartyStripe = rgb(255, 92, 170),
				PartyTrim = rgb(255, 252, 240),
			},
			Materials = {
				PartyGold = Enum.Material.SmoothPlastic,
				PartyStripe = Enum.Material.SmoothPlastic,
				PartyTrim = Enum.Material.Fabric,
			},
			PostProcess = shine({ "PartyGold" }),
			Fallback = function(m)
				-- A stack of shrinking discs makes the cone.
				for step = 0, 4 do
					h.pillar(m, "PartyGold", 0.78 * (1 - step / 5), 0.2, Vector3.new(0, 0.1 + step * 0.2, 0))
				end
				h.ball(m, "PartyTrim", 0.24, Vector3.new(0, 1.06, 0))
			end,
		},
		RoyalCrown = {
			Height = 0.958, -- the band and points 0.54, the velvet, orb and cross above
			AssetId = 83693160050595,
			Palette = {
				CrownGold = GOLD,
				CrownVelvet = rgb(190, 24, 52),
				CrownPearl = rgb(250, 246, 236),
				CrownRuby = rgb(255, 40, 80),
				CrownSapphire = rgb(60, 120, 255),
			},
			Materials = {
				CrownGold = Enum.Material.SmoothPlastic,
				CrownVelvet = Enum.Material.Fabric,
				CrownPearl = Enum.Material.SmoothPlastic,
				CrownRuby = Enum.Material.Neon,
				CrownSapphire = Enum.Material.Neon,
			},
			PostProcess = shine({ "CrownGold" }),
			Fallback = function(m)
				ring(m, "CrownGold", 0.48, 0.12, 0.24, 12)
				h.blob(m, "CrownVelvet", Vector3.new(0.9, 0.9, 0.9), Vector3.new(0, 0.2, 0))
				h.ball(m, "CrownGold", 0.15, Vector3.new(0, 0.7, 0))
				h.ball(m, "CrownRuby", 0.12, Vector3.new(0, 0.13, -0.5))
			end,
		},
		GoldenHalo = {
			Height = 0.13,
			AssetId = 78439363892030,
			Palette = { HaloRing = rgb(255, 214, 90) },
			Materials = { HaloRing = Enum.Material.Neon },
			Fallback = function(m)
				ring(m, "HaloRing", 0.42, 0.066, 0.12, 16)
			end,
		},
		GildedTopHat = {
			Height = 0.825,
			AssetId = 115365464867011,
			Palette = {
				TopHatBody = rgb(30, 26, 36),
				TopHatBand = GOLD,
				TopHatBuckle = rgb(255, 236, 150),
			},
			Materials = {
				TopHatBody = Enum.Material.SmoothPlastic,
				TopHatBand = Enum.Material.SmoothPlastic,
				TopHatBuckle = Enum.Material.SmoothPlastic,
			},
			PostProcess = shine({ "TopHatBand", "TopHatBuckle" }),
			Fallback = function(m)
				h.pillar(m, "TopHatBody", 1.3, 0.06, Vector3.new(0, 0.03, 0))
				h.pillar(m, "TopHatBody", 0.72, 0.76, Vector3.new(0, 0.44, 0))
				h.pillar(m, "TopHatBand", 0.74, 0.14, Vector3.new(0, 0.13, 0))
			end,
		},
		SunKingCrown = {
			Height = 0.694, -- the circlet 0.2, the long rays and their beads above
			AssetId = 98784547444850,
			Palette = {
				SunGold = rgb(255, 200, 40),
				SunRim = rgb(214, 128, 18),
				SunGem = rgb(255, 246, 190),
			},
			Materials = {
				SunGold = Enum.Material.SmoothPlastic,
				SunRim = Enum.Material.SmoothPlastic,
				SunGem = Enum.Material.Neon,
			},
			PostProcess = shine({ "SunGold", "SunRim" }),
			Fallback = function(m)
				ring(m, "SunGold", 0.48, 0.1, 0.2, 12)
				for index = 1, 12 do
					local angle = 2 * math.pi * index / 12
					local long = index % 2 == 0
					local ray = h.block(
						m,
						"SunGold",
						Vector3.new(0.12, if long then 0.5 else 0.32, 0.05),
						Vector3.new(math.cos(angle) * 0.55, if long then 0.4 else 0.3, math.sin(angle) * 0.55)
					)
					ray.CFrame = CFrame.new(ray.Position)
						* CFrame.Angles(0, -angle + math.pi / 2, 0)
						* CFrame.Angles(math.rad(-24), 0, 0)
				end
				h.ball(m, "SunGem", 0.16, Vector3.new(0, 0.1, -0.52))
			end,
		},
	}
end
