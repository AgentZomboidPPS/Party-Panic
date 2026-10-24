-- Props for the hats players wear (the Hat cosmetic slot: World/Hats puts each on as an Accessory).
--
-- The PUMPKIN HAT, the HALLOWEEN PARTY's headline reward (owner: "do pumpkin hat now"): a carved
-- jack-o'-lantern worn on top of the head. A ribbed orange shell (HatShell) with triangle eyes, a
-- nose and a toothy grin cut into its front; a warm glow inside that shows through the cuts
-- (HatGlow, Neon); a curly green stem with a leaf (HatStem). The meshes come from
-- tools/meshgen/props/Hats.py, made at the size it's worn on a standard 1.2-stud head.
-- The fallback (only if the mesh can't load) is an orange ball with a glowing face on its front.
return function(h)
	local rgb = h.rgb

	-- A flat triangle in the XY plane (apex up), `size` wide and tall, facing -Z, made of two
	-- wedges: a glowing eye or nose for the fallback.
	local function triangle(m: Model, name: string, size: number, center: Vector3)
		for _, side in { -1, 1 } do
			local wedge = Instance.new("WedgePart")
			wedge.Name = name
			wedge.Size = Vector3.new(0.04, size, size / 2)
			-- A wedge's upright edge is at its +Z end, its slope runs down to the -Z end: turned so
			-- each half's upright edge is on the triangle's middle and its slope runs outward.
			wedge.CFrame = CFrame.new(center + Vector3.new(side * size / 4, 0, 0))
				* CFrame.Angles(0, -side * math.rad(90), 0)
			wedge.Anchored = true
			wedge.TopSurface = Enum.SurfaceType.Smooth
			wedge.BottomSurface = Enum.SurfaceType.Smooth
			wedge.Parent = m
		end
	end

	return {
		PumpkinHat = {
			Height = 1.356, -- the mesh's own height (the shell 1.04, the curl of its stem above)
			AssetId = 124438654039918, -- filled in by tools/upload_assets.py
			Palette = {
				HatShell = rgb(255, 128, 24),
				HatGlow = rgb(255, 186, 64),
				HatStem = rgb(86, 142, 52),
			},
			Materials = {
				HatShell = Enum.Material.SmoothPlastic,
				HatGlow = Enum.Material.Neon,
				HatStem = Enum.Material.SmoothPlastic,
			},
			Fallback = function(m)
				h.blob(m, "HatShell", Vector3.new(1.58, 1.04, 1.58), Vector3.new(0, 0.52, 0))
				h.pillar(m, "HatStem", 0.14, 0.3, Vector3.new(0, 1.12, 0))
				-- The face sits on the ball's front (its surface there is about 0.72 in front of
				-- the middle at the eyes, 0.75 at the mouth).
				triangle(m, "HatGlow", 0.22, Vector3.new(-0.25, 0.7, -0.7))
				triangle(m, "HatGlow", 0.22, Vector3.new(0.25, 0.7, -0.7))
				triangle(m, "HatGlow", 0.1, Vector3.new(0, 0.53, -0.78))
				h.block(m, "HatGlow", Vector3.new(0.56, 0.1, 0.05), Vector3.new(0, 0.33, -0.74))
			end,
		},
	}
end
