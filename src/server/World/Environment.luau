-- Sky, lighting and terrain scenery (design doc §13 "Visual identity").
--
-- Terrain gives soft, organic shapes (rolling hills, a lake, mountains, floating islands) that
-- would take thousands of parts to fake, and the engine renders it with automatic level of detail,
-- so it's both the prettiest and the cheapest way to fill the horizon.

local Lighting = game:GetService("Lighting")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local MeshLibrary = require(script.Parent.MeshLibrary)

local Environment = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function setupSky()
	local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 9
	sky.StarCount = 1500
	sky.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.06
	rays.Spread = 0.7
	rays.Parent = Lighting

	local clouds = Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.55
	clouds.Color = rgb(255, 250, 255)
	clouds.Parent = workspace.Terrain

	local terrain = workspace.Terrain
	terrain.WaterColor = rgb(70, 190, 230)
	terrain.WaterReflectance = 0.6
	terrain.WaterTransparency = 0.55
	terrain.WaterWaveSize = 0.12
	terrain.WaterWaveSpeed = 8
	-- Brighter, toy-like terrain colors.
	terrain:SetMaterialColor(Enum.Material.Grass, rgb(110, 200, 95))
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, rgb(90, 185, 85))
	terrain:SetMaterialColor(Enum.Material.Sand, rgb(250, 225, 170))
	terrain:SetMaterialColor(Enum.Material.Rock, rgb(150, 145, 135))
	terrain:SetMaterialColor(Enum.Material.Ground, rgb(150, 110, 80))
end

local function lobbyTerrain(plazaRadius: number)
	local terrain = workspace.Terrain
	local rng = Random.new(7)

	-- Lawn around the plaza (grass blades come from Terrain.Decoration).
	terrain:FillCylinder(CFrame.new(0, -8, 0), 14, 330, Enum.Material.Ground)
	terrain:FillCylinder(CFrame.new(0, -1.8, 0), 3, 325, Enum.Material.Grass) -- surface at y = -0.3
	-- Carve it away under the plaza disc so grass never grows through the floor.
	terrain:FillCylinder(CFrame.new(0, 3, 0), 10, plazaRadius + 1, Enum.Material.Air)

	-- Soft rolling hills just past the trees, so the view ends in green, not a flat horizon.
	for index = 1, 30 do
		local angle = index / 30 * math.pi * 2 + rng:NextNumber(-0.05, 0.05)
		local distance = rng:NextNumber(170, 230)
		local radius = rng:NextNumber(38, 62)
		local center =
			Vector3.new(math.cos(angle) * distance, -radius * rng:NextNumber(0.55, 0.75), math.sin(angle) * distance)
		terrain:FillBall(center, radius, if index % 4 == 0 then Enum.Material.LeafyGrass else Enum.Material.Grass)
	end

	-- A lake with sandy shores, visible from the parkour deck.
	local lake = Vector3.new(-170, 0, 150)
	terrain:FillCylinder(CFrame.new(lake + Vector3.new(0, -5, 0)), 8, 62, Enum.Material.Sand)
	terrain:FillCylinder(CFrame.new(lake + Vector3.new(0, -3.5, 0)), 7, 54, Enum.Material.Water)

	-- Big grassy mountains far away frame the horizon (rock only peeks out low on the sides).
	for index = 1, 12 do
		local angle = index / 12 * math.pi * 2 + 0.3
		local distance = rng:NextNumber(560, 680)
		local radius = rng:NextNumber(100, 160)
		local center = Vector3.new(math.cos(angle) * distance, -radius * 0.45, math.sin(angle) * distance)
		terrain:FillBall(center, radius, Enum.Material.Rock)
		terrain:FillBall(center + Vector3.new(0, radius * 0.12, 0), radius * 0.97, Enum.Material.Grass)
	end
end

-- Floating islands around (never under) the arena area, so rounds happen up in the sky.
local function skyIslands()
	local terrain = workspace.Terrain
	local origin = Config.ArenaOrigin
	local islands = {
		{ Vector3.new(-230, -40, -140), 34 },
		{ Vector3.new(-280, 10, 220), 26 },
		{ Vector3.new(360, -60, 120), 40 },
		{ Vector3.new(320, 15, 470), 30 },
		{ Vector3.new(-150, -70, 480), 36 },
		{ Vector3.new(120, 30, -230), 24 },
		{ Vector3.new(-330, 60, 40), 18 },
		{ Vector3.new(420, 40, -60), 20 },
	}
	for _, island in islands do
		local center = origin + island[1]
		local radius = island[2]
		-- Rocky cone underneath, grassy cap on top.
		terrain:FillBall(center - Vector3.new(0, radius * 0.4, 0), radius * 0.9, Enum.Material.Rock)
		terrain:FillBall(center - Vector3.new(0, radius * 1.0, 0), radius * 0.55, Enum.Material.Rock)
		terrain:FillCylinder(
			CFrame.new(center + Vector3.new(0, radius * 0.1, 0)),
			radius * 0.35,
			radius,
			Enum.Material.Grass
		)
		MeshLibrary.Get("Tree", {
			Scale = radius / 22,
			CFrame = CFrame.new(center + Vector3.new(radius * 0.3, radius * 0.27, -radius * 0.2)),
			Parent = workspace,
		})
	end
end

function Environment.Build(plazaRadius: number)
	setupSky()
	lobbyTerrain(plazaRadius)
	skyIslands()
end

return Environment
