-- Runs inside a real Roblox server (Open Cloud Luau execution) against a saved place version:
-- builds the lobby exactly as the game does, then returns the geometry, terrain heights and
-- lighting as JSON so tools/preview/render.py can draw it. Never runs in the game itself.

local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local LogService = game:GetService("LogService")
local ServerScriptService = game:GetService("ServerScriptService")

local logs = {}
LogService.MessageOut:Connect(function(message, kind)
	if kind ~= Enum.MessageType.MessageOutput and #logs < 200 then
		table.insert(logs, kind.Name .. ": " .. message)
	end
end)

-- tools/preview/bundle.py prepends the working-tree World modules as `__require`, so the code
-- under test doesn't have to be published first. Without it, the place's own modules are used.
local world = ServerScriptService.Server.World
local load = __require or function(name: string): any
	return require(world[name])
end
local Shapes = load("Shapes")
Shapes.RecordPieces = true
local MeshLibrary = load("MeshLibrary")
local LobbyBuilder = load("LobbyBuilder")

local started = os.clock()
local ok, err = pcall(LobbyBuilder.Build)
local buildTime = os.clock() - started

-- LobbyService adds the beach balls after the build; add them here too (anchored, so they hold
-- still for the picture) when the bundle provides the module.
local okBalls, BeachBalls = pcall(load, "BeachBalls")
if ok and okBalls and BeachBalls then
	local refs = err :: any
	local okSetup, balls = pcall(BeachBalls.Setup, refs.Root, refs.BallSpots, {
		PlazaRadius = LobbyBuilder.PlazaRadius,
		StageFrontZ = LobbyBuilder.StageFrontZ,
		Traps = LobbyBuilder.BallTraps,
	})
	if okSetup then
		for _, ball in balls do
			ball.Anchored = true
		end
	end
end

local propNames = {}
for _, name in MeshLibrary.Names() do
	propNames[name] = true
end

local function r(x: number): number
	return math.floor(x * 100 + 0.5) / 100
end

local function propOf(part: Instance): string?
	local node = part.Parent
	while node and node ~= workspace do
		if node:IsA("Model") and propNames[node.Name] then
			return node.Name
		end
		node = node.Parent
	end
	return nil
end

local parts = {}
for _, item in workspace:GetDescendants() do
	if not item:IsA("BasePart") or item:IsA("Terrain") or item.Transparency >= 0.999 then
		continue
	end
	local part = item :: BasePart
	local cf = part.CFrame
	local entry: { [string]: any } = {
		c = part.ClassName,
		n = part.Name,
		s = { r(part.Size.X), r(part.Size.Y), r(part.Size.Z) },
		cf = { cf:GetComponents() },
		col = {
			math.floor(part.Color.R * 255 + 0.5),
			math.floor(part.Color.G * 255 + 0.5),
			math.floor(part.Color.B * 255 + 0.5),
		},
		m = part.Material.Name,
		t = r(part.Transparency),
		sh = part.CastShadow,
	}
	if part:IsA("Part") then
		entry.shape = (part :: Part).Shape.Name
	end
	local pieces = part:GetAttribute("PP_Pieces")
	if pieces then
		entry.pieces = HttpService:JSONDecode(pieces)
	end
	local prop = propOf(part)
	if prop then
		entry.prop = prop
	end
	if part:IsA("MeshPart") then
		entry.mesh = (part :: MeshPart).MeshId
	end
	local light = part:FindFirstChildWhichIsA("Light")
	if light then
		entry.light = {
			light.ClassName,
			r(light.Brightness),
			r((light :: any).Range),
			{ light.Color.R, light.Color.G, light.Color.B },
		}
	end
	table.insert(parts, entry)
end

-- Terrain: top surface height and material on a grid (one ray per cell), water separately.
local terrain = workspace.Terrain
local half, step = tonumber(_G.PP_TERRAIN_HALF) or 420, tonumber(_G.PP_TERRAIN_STEP) or 4
local landParams = RaycastParams.new()
landParams.FilterType = Enum.RaycastFilterType.Include
landParams.FilterDescendantsInstances = { terrain }
landParams.IgnoreWater = true
local waterParams = RaycastParams.new()
waterParams.FilterType = Enum.RaycastFilterType.Include
waterParams.FilterDescendantsInstances = { terrain }
waterParams.IgnoreWater = false
local materials, materialIndex = {}, {}
local heights, mats, water = {}, {}, {}
for z = -half, half, step do
	for x = -half, half, step do
		local origin = Vector3.new(x, 400, z)
		local hit = workspace:Raycast(origin, Vector3.new(0, -800, 0), landParams)
		if hit then
			local name = hit.Material.Name
			if not materialIndex[name] then
				table.insert(materials, name)
				materialIndex[name] = #materials
			end
			table.insert(heights, r(hit.Position.Y))
			table.insert(mats, materialIndex[name])
		else
			table.insert(heights, -999)
			table.insert(mats, 0)
		end
		local wet = workspace:Raycast(origin, Vector3.new(0, -800, 0), waterParams)
		table.insert(water, if wet and wet.Material == Enum.Material.Water then r(wet.Position.Y) else -999)
	end
end
local materialColors = {}
for _, name in materials do
	local color = terrain:GetMaterialColor((Enum.Material :: any)[name])
	materialColors[name] = { color.R, color.G, color.B }
end

local function color(c: Color3)
	return { c.R, c.G, c.B }
end
local lighting: { [string]: any } = {
	clock = Lighting.ClockTime,
	brightness = Lighting.Brightness,
	ambient = color(Lighting.Ambient),
	outdoor = color(Lighting.OutdoorAmbient),
	sun = { Lighting:GetSunDirection().X, Lighting:GetSunDirection().Y, Lighting:GetSunDirection().Z },
	exposure = Lighting.ExposureCompensation,
	diffuse = Lighting.EnvironmentDiffuseScale,
	specular = Lighting.EnvironmentSpecularScale,
}
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
if atmosphere then
	lighting.atmosphere = {
		density = atmosphere.Density,
		offset = atmosphere.Offset,
		color = color(atmosphere.Color),
		decay = color(atmosphere.Decay),
		haze = atmosphere.Haze,
		glare = atmosphere.Glare,
	}
end
local correction = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
if correction then
	lighting.correction =
		{ saturation = correction.Saturation, contrast = correction.Contrast, brightness = correction.Brightness }
end

local sources = {}
for _, name in MeshLibrary.Names() do
	sources[name] = MeshLibrary.Source(name)
end

return HttpService:JSONEncode({
	ok = ok,
	err = if ok then nil else tostring(err),
	buildTime = buildTime,
	logs = logs,
	parts = parts,
	terrain = {
		half = half,
		step = step,
		heights = heights,
		mats = mats,
		water = water,
		materials = materials,
		colors = materialColors,
	},
	lighting = lighting,
	sources = sources,
})
