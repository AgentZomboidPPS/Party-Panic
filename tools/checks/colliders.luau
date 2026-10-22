-- Collider inventory for tools/checks/colliders.py (round_harness.py --colliders-at, LOBBY --colliders).
-- Owner: "Theres invisible stuff you can jump on and hang on in several games." This lists every part
-- a character could stand on, bump into or cling to, how it looks (transparency, mesh, collision
-- fidelity), a map of collision tops (layered downward raycasts: rays hit collision geometry, not the
-- drawn mesh) and, for every collidable mesh or union, its collision shape measured by raycasts in
-- its own frame, so the offline check can compare it with the drawn mesh (assets/meshes).
-- Never runs in the game.

local __Physics = game:GetService("PhysicsService")
local __probedKeys = {}

local __B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local __b64codes = {}
for index = 1, 64 do
	__b64codes[index - 1] = string.byte(__B64, index)
end

-- A growable little-endian byte writer, returned as base64 (JSON can't carry raw bytes).
local function __writer()
	local self = { buf = buffer.create(65536), n = 0 }
	local function ensure(extra)
		local size = buffer.len(self.buf)
		if self.n + extra <= size then
			return
		end
		while size < self.n + extra do
			size *= 2
		end
		local grown = buffer.create(size)
		buffer.copy(grown, 0, self.buf, 0, self.n)
		self.buf = grown
	end
	function self.u8(value)
		ensure(1)
		buffer.writeu8(self.buf, self.n, value)
		self.n += 1
	end
	function self.i16(value)
		ensure(2)
		buffer.writei16(self.buf, self.n, math.clamp(math.round(value), -32768, 32767))
		self.n += 2
	end
	function self.u16(value)
		ensure(2)
		buffer.writeu16(self.buf, self.n, math.clamp(math.round(value), 0, 65535))
		self.n += 2
	end
	function self.base64(): string
		local length = self.n
		local out = buffer.create(math.ceil(length / 3) * 4)
		local o = 0
		local src = self.buf
		for i = 0, length - 1, 3 do
			local a = buffer.readu8(src, i)
			local b = if i + 1 < length then buffer.readu8(src, i + 1) else 0
			local c = if i + 2 < length then buffer.readu8(src, i + 2) else 0
			local n = a * 65536 + b * 256 + c
			buffer.writeu8(out, o, __b64codes[n // 262144])
			buffer.writeu8(out, o + 1, __b64codes[(n // 4096) % 64])
			buffer.writeu8(out, o + 2, if i + 1 < length then __b64codes[(n // 64) % 64] else 61)
			buffer.writeu8(out, o + 3, if i + 2 < length then __b64codes[n % 64] else 61)
			o += 4
		end
		return buffer.tostring(out)
	end
	return self
end

local function __r2(x: number): number
	return math.floor(x * 100 + 0.5) / 100
end

-- The character model `item` belongs to (a Model with a Humanoid), if any.
local function __characterOf(item: Instance): Model?
	local node = item.Parent
	while node and node ~= workspace do
		if node:IsA("Model") and node:FindFirstChildOfClass("Humanoid") then
			return node :: Model
		end
		node = node.Parent
	end
	return nil
end

local function __collidable(a: string, b: string): boolean
	local ok, result = pcall(__Physics.CollisionGroupsAreCollidable, __Physics, a, b)
	return ok and result == true
end

-- The groups people's and bots' characters are in right now (a real player's "Default" is the
-- lobby's PP_Players, which collides like Default).
local function __characterGroups()
	local people, bots, characters = {}, {}, {}
	local BotRegistry = __cache["Server/Services/BotRegistry"]
	for _, child in workspace:GetChildren() do
		if not (child:IsA("Model") and child:FindFirstChildOfClass("Humanoid")) then
			continue
		end
		table.insert(characters, child)
		local root = child:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			continue
		end
		local isBot = false
		if BotRegistry then
			for _, bot in BotRegistry.List() do
				if bot.Character == child then
					isBot = true
				end
			end
		end
		local group = root.CollisionGroup
		if isBot then
			bots[group] = true
		else
			if group == "Default" and __Physics:IsCollisionGroupRegistered("PP_Players") then
				group = "PP_Players"
			end
			people[group] = true
		end
	end
	if next(people) == nil then
		people[if __Physics:IsCollisionGroupRegistered("PP_Players") then "PP_Players" else "Default"] = true
	end
	if next(bots) == nil then
		bots.Default = true
	end
	return people, bots, characters
end

local function __anyCollides(part: BasePart, groups): boolean
	if not part.CanCollide then
		return false
	end
	for group in groups do
		if __collidable(part.CollisionGroup, group) then
			return true
		end
	end
	return false
end

local function __pathOf(item: Instance): string
	local names = {}
	local node: Instance? = item
	while node and node ~= workspace and node ~= game do
		table.insert(names, 1, node.Name)
		node = node.Parent
	end
	return table.concat(names, "/")
end

-- Snapshot. `label` names it; `opts.probes` (default true) measures every collidable mesh/union.
function __colliderSnapshot(label: string, opts)
	opts = opts or {}
	local started = os.clock()
	local people, bots, characters = __characterGroups()
	local peopleList, botList = {}, {}
	for group in people do
		table.insert(peopleList, group)
	end
	for group in bots do
		table.insert(botList, group)
	end
	local rayGroup = peopleList[1]

	-- Every part in the world except characters.
	local parts, indexOf = {}, {}
	local count = 0
	for _, item in workspace:GetDescendants() do
		if not item:IsA("BasePart") or item:IsA("Terrain") or __characterOf(item) then
			continue
		end
		local part = item :: BasePart
		local cc = __anyCollides(part, people)
		local cb = __anyCollides(part, bots)
		local visible = part.Transparency < 0.999
		-- Only what collides with someone, or can be seen (the offline check redraws what's seen).
		if not cc and not cb and not visible then
			continue
		end
		count += 1
		indexOf[part] = count
		local cf = part.CFrame
		local entry: { [string]: any } = {
			i = count,
			p = __pathOf(part),
			c = part.ClassName,
			n = part.Name,
			s = { __r2(part.Size.X), __r2(part.Size.Y), __r2(part.Size.Z) },
			cf = { cf:GetComponents() },
			t = __r2(part.Transparency),
			col = {
				math.floor(part.Color.R * 255 + 0.5),
				math.floor(part.Color.G * 255 + 0.5),
				math.floor(part.Color.B * 255 + 0.5),
			},
			m = part.Material.Name,
			cc = cc,
			cb = cb,
			cq = part.CanQuery,
			ct = part.CanTouch,
			g = part.CollisionGroup,
			a = part.Anchored,
		}
		for index = 1, 12 do
			entry.cf[index] = math.floor(entry.cf[index] * 10000 + 0.5) / 10000
		end
		if part:IsA("Part") then
			entry.shape = (part :: Part).Shape.Name
		end
		if part:IsA("MeshPart") then
			entry.mesh = (part :: MeshPart).MeshId
			entry.fid = (part :: MeshPart).CollisionFidelity.Name
		elseif part:IsA("PartOperation") then
			entry.fid = (part :: PartOperation).CollisionFidelity.Name
		end
		local special = part:FindFirstChildOfClass("SpecialMesh")
		if special then
			entry.sm = {
				special.MeshType.Name,
				__r2(special.Scale.X),
				__r2(special.Scale.Y),
				__r2(special.Scale.Z),
				special.MeshId,
			}
		end
		if
			part:FindFirstChildOfClass("Decal")
			or part:FindFirstChildOfClass("Texture")
			or part:FindFirstChildOfClass("SurfaceGui")
		then
			entry.deco = true
		end
		local pieces = part:GetAttribute("PP_Pieces")
		if pieces then
			entry.pieces = HttpService:JSONDecode(pieces)
		end
		local node = part.Parent
		while node and node ~= workspace do
			if node:IsA("Model") and node:GetAttribute("PP_Prop") then
				entry.prop = node:GetAttribute("PP_Prop")
				break
			end
			node = node.Parent
		end
		parts[count] = entry
	end

	local result: { [string]: any } = {
		label = label,
		people = peopleList,
		bots = botList,
		parts = parts,
		killY = opts.killY, -- below this a character is out (the mode's KillY)
	}

	-- Where the characters are (seeds for the reachability flood fill).
	local seeds = {}
	for _, character in characters do
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			table.insert(seeds, {
				character.Name,
				__r2(root.Position.X),
				__r2(root.Position.Y),
				__r2(root.Position.Z),
				root.CollisionGroup,
				__r2(humanoid.WalkSpeed),
				__r2(humanoid.JumpHeight),
				__r2(humanoid.JumpPower),
				humanoid.UseJumpPower,
			})
		end
	end
	-- Nobody here (the lobby run): start from the spawn points.
	if #seeds == 0 then
		for _, item in workspace:GetDescendants() do
			if item:IsA("SpawnLocation") then
				local at = item.Position + Vector3.new(0, 3, 0)
				table.insert(seeds, { item.Name, __r2(at.X), __r2(at.Y), __r2(at.Z), "Default", 16, 7.2, 0, false })
			end
		end
	end
	result.seeds = seeds

	-- The collision-top map: bounds from what people collide with (leaving out ground discs).
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local focus = opts.center or Vector3.zero
	for part, index in indexOf do
		if not parts[index].cc or __environmentParts[part] then
			continue -- (the environment's far trees would stretch the map round the arena)
		end
		local size = part.Size
		local cf = part.CFrame
		local right, up, back = cf.RightVector, cf.UpVector, cf.LookVector
		local hx = math.abs(right.X) * size.X / 2 + math.abs(up.X) * size.Y / 2 + math.abs(back.X) * size.Z / 2
		local hy = math.abs(right.Y) * size.X / 2 + math.abs(up.Y) * size.Y / 2 + math.abs(back.Y) * size.Z / 2
		local hz = math.abs(right.Z) * size.X / 2 + math.abs(up.Z) * size.Y / 2 + math.abs(back.Z) * size.Z / 2
		local p = cf.Position
		if hx > 260 or hz > 260 then
			minY = math.min(minY, p.Y - hy)
			maxY = math.max(maxY, p.Y + hy)
			continue -- a ground disc: its top shows up in the map anyway
		end
		minX, maxX = math.min(minX, p.X - hx), math.max(maxX, p.X + hx)
		minY, maxY = math.min(minY, p.Y - hy), math.max(maxY, p.Y + hy)
		minZ, maxZ = math.min(minZ, p.Z - hz), math.max(maxZ, p.Z + hz)
	end
	local reach = opts.reach or 420
	minX, maxX = math.max(minX, focus.X - reach), math.min(maxX, focus.X + reach)
	minZ, maxZ = math.max(minZ, focus.Z - reach), math.min(maxZ, focus.Z + reach)
	if minX < maxX and minZ < maxZ and minY < maxY then
		local area = (maxX - minX) * (maxZ - minZ)
		local step = math.max(opts.step or 1, math.ceil(math.sqrt(area / (opts.columns or 70000)) * 2) / 2)
		local nx = math.floor((maxX - minX) / step) + 1
		local nz = math.floor((maxZ - minZ) / step) + 1
		local top = math.min(maxY + 2, focus.Y + 400)
		local bottom = math.max(minY - 2, focus.Y - 400)
		local upParams = RaycastParams.new()
		upParams.FilterType = Enum.RaycastFilterType.Exclude
		upParams.FilterDescendantsInstances = characters
		upParams.CollisionGroup = rayGroup
		upParams.RespectCanCollide = true
		upParams.IgnoreWater = true
		local writer = __writer()
		local rays = 0
		for iz = 0, nz - 1 do
			local z = minZ + iz * step
			for ix = 0, nx - 1 do
				local x = minX + ix * step
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = characters
				params.CollisionGroup = rayGroup
				params.RespectCanCollide = true
				params.IgnoreWater = true
				local layers = {}
				local y = top
				for _ = 1, 6 do
					local hit = workspace:Raycast(Vector3.new(x, y, z), Vector3.new(0, bottom - y, 0), params)
					rays += 1
					if not hit then
						break
					end
					local hy = hit.Position.Y
					local above =
						workspace:Raycast(Vector3.new(x, hy + 0.05, z), Vector3.new(0, top + 20 - hy, 0), upParams)
					rays += 1
					local instance = hit.Instance
					local index = if instance:IsA("Terrain") then 65535 else (indexOf[instance] or 65534)
					table.insert(layers, { hy, index, if above then above.Position.Y - hy else 1600 })
					params:AddToFilter(instance)
					y = hy - 0.02
				end
				writer.u8(#layers)
				for _, layer in layers do
					writer.i16(layer[1] * 20)
					writer.u16(layer[2])
					writer.i16(math.min(layer[3], 1600) * 20)
				end
			end
			if iz % 8 == 0 then
				task.wait()
			end
		end
		result.grid = {
			x0 = minX,
			z0 = minZ,
			step = step,
			nx = nx,
			nz = nz,
			top = top,
			bottom = bottom,
			rays = rays,
			data = writer.base64(),
		}
	end
	result.gridSeconds = __r2(os.clock() - started)

	-- Terrain round the arena (always solid: the sky islands, the lobby's hills), whether or not the
	-- map above reaches it: every `terrainStep` studs out to `terrainReach` from the middle, the top
	-- of the highest terrain in that column and the bottom of the lowest (a ray down and a ray up
	-- that only see terrain), as int16 tenths of a stud (-32768 = none).
	result.center = { __r2(focus.X), __r2(focus.Y), __r2(focus.Z) }
	local terrainReach = opts.terrainReach or 1300
	local terrainStep = opts.terrainStep or 10
	local terrainStart = os.clock()
	local onlyTerrain = RaycastParams.new()
	onlyTerrain.FilterType = Enum.RaycastFilterType.Include
	onlyTerrain.FilterDescendantsInstances = { workspace.Terrain }
	onlyTerrain.IgnoreWater = true
	local tn = math.floor(terrainReach * 2 / terrainStep) + 1
	local terrainWriter = __writer()
	local columns = 0
	local high, low = focus.Y + 700, focus.Y - 700
	for iz = 0, tn - 1 do
		local z = focus.Z - terrainReach + iz * terrainStep
		for ix = 0, tn - 1 do
			local x = focus.X - terrainReach + ix * terrainStep
			local down = workspace:Raycast(Vector3.new(x, high, z), Vector3.new(0, low - high, 0), onlyTerrain)
			if down then
				local up = workspace:Raycast(Vector3.new(x, low, z), Vector3.new(0, high - low, 0), onlyTerrain)
				terrainWriter.i16((down.Position.Y - focus.Y) * 10)
				terrainWriter.i16(if up then (up.Position.Y - focus.Y) * 10 else -32768)
				columns += 1
			else
				terrainWriter.i16(-32768)
				terrainWriter.i16(-32768)
			end
		end
		if iz % 10 == 0 then
			task.wait()
		end
	end
	result.terrain = {
		x0 = __r2(focus.X - terrainReach),
		z0 = __r2(focus.Z - terrainReach),
		step = terrainStep,
		n = tn,
		columns = columns,
		data = terrainWriter.base64(),
	}
	result.terrainSeconds = __r2(os.clock() - terrainStart)

	-- Every collidable mesh and union measured in its own frame (one per mesh and size).
	if opts.probes ~= false then
		local probeStart = os.clock()
		local seen = __probedKeys -- once per run: later snapshots only measure new shapes
		local probes = {}
		for part, index in indexOf do
			local entry = parts[index]
			if not (entry.cc or entry.cb) then
				continue
			end
			if not (part:IsA("MeshPart") or part:IsA("PartOperation")) then
				continue
			end
			local size = part.Size
			local key = string.format(
				"%s|%s|%.2f|%.2f|%.2f|%s",
				part.ClassName,
				if part:IsA("MeshPart") then (part :: MeshPart).MeshId else (entry.prop or "") .. ":" .. part.Name,
				size.X,
				size.Y,
				size.Z,
				entry.fid or ""
			)
			if part:IsA("PartOperation") then
				-- Unions of the same size can differ in shape: tell them apart by their pieces.
				local pieces = tostring(part:GetAttribute("PP_Pieces") or "")
				local hash = #pieces
				for index = 1, #pieces, 7 do
					hash = (hash * 31 + string.byte(pieces, index)) % 2147483647
				end
				key ..= "|" .. tostring(hash)
			end
			entry.key = key
			if seen[key] then
				continue
			end
			seen[key] = true
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { part }
			params.CollisionGroup = if entry.cc then rayGroup else botList[1]
			params.RespectCanCollide = true
			local cf = part.CFrame
			local writer = __writer()
			local function cast(origin: Vector3, direction: Vector3): number
				local hit = workspace:Raycast(cf:PointToWorldSpace(origin), cf:VectorToWorldSpace(direction), params)
				return if hit then (hit.Position - cf:PointToWorldSpace(origin)).Magnitude else -1
			end
			local margin = 0.3
			local n = opts.probeCells or 40
			local hx, hy, hz = size.X / 2 + margin, size.Y / 2 + margin, size.Z / 2 + margin
			-- Down and up grids over local X/Z: the collision's top and bottom over each spot.
			local grids = {
				{ "down", Vector3.new(0, -2 * hy, 0) },
				{ "up", Vector3.new(0, 2 * hy, 0) },
			}
			for _, grid in grids do
				local name, direction = grid[1], grid[2]
				for a = 0, n - 1 do
					for b = 0, n - 1 do
						local u = (a + 0.5) / n * 2 - 1
						local v = (b + 0.5) / n * 2 - 1
						local origin
						if name == "down" then
							origin = Vector3.new(u * hx, hy, v * hz)
						elseif name == "up" then
							origin = Vector3.new(u * hx, -hy, v * hz)
						elseif name == "east" then
							origin = Vector3.new(hx, v * hy, u * hz)
						elseif name == "west" then
							origin = Vector3.new(-hx, v * hy, u * hz)
						elseif name == "north" then
							origin = Vector3.new(u * hx, v * hy, -hz)
						else
							origin = Vector3.new(u * hx, v * hy, hz)
						end
						local d = cast(origin, direction)
						writer.i16(if d < 0 then -32768 else d * 100)
					end
				end
			end
			table.insert(probes, { key = key, part = index, n = n, margin = margin, data = writer.base64() })
			if #probes % 6 == 0 then
				task.wait()
			end
		end
		result.probes = probes
		result.probeSeconds = __r2(os.clock() - probeStart)
	end
	result.seconds = __r2(os.clock() - started)
	return result
end

-- Parts that stay in the world after a round (anything a character could still bump into).
function __colliderLeftovers(): { any }
	local people, bots = __characterGroups()
	local list = {}
	for _, item in workspace:GetDescendants() do
		if not item:IsA("BasePart") or item:IsA("Terrain") or __characterOf(item) or __environmentParts[item] then
			continue
		end
		local part = item :: BasePart
		if __anyCollides(part, people) or __anyCollides(part, bots) then
			table.insert(list, {
				__pathOf(part),
				part.ClassName,
				__r2(part.Transparency),
				__r2(part.Position.X),
				__r2(part.Position.Y),
				__r2(part.Position.Z),
			})
		end
	end
	return list
end

-- The lobby (round_harness.py LOBBY --colliders): built as the game builds it, with its beach balls.
-- Waits (at most `limit` seconds) until MeshLibrary has given every prop piece its precise collision,
-- one piece at a time in the background, so the snapshot measures what players get once it's done.
-- Returns the seconds waited, the pieces still waiting and the longest the server was held up
-- meanwhile (gap between Heartbeats).
function __waitForRebuilds(limit: number): (number, number, number)
	local MeshLibrary = __require("Server/World/MeshLibrary")
	local start = os.clock()
	local last, longest = os.clock(), 0
	local beat = game:GetService("RunService").Heartbeat:Connect(function()
		local now = os.clock()
		longest = math.max(longest, now - last)
		last = now
	end)
	while MeshLibrary.PendingRebuilds() > 0 and os.clock() - start < limit do
		task.wait(0.25)
	end
	beat:Disconnect()
	return __r2(os.clock() - start), MeshLibrary.PendingRebuilds(), __r2(longest)
end

-- The terrain and sky the game builds when it starts (World/Environment: the lobby's lawn and hills,
-- the sky islands round the arenas), so a round's snapshot has what is really round its arena.
-- (Its parts, the islands' trees, stay after a round: the leftovers check leaves them out.)
__environmentParts = {}
function __buildEnvironment()
	local ok, err = pcall(function()
		__require("Server/World/Environment").Build(75) -- (LobbyBuilder's PLAZA_RADIUS)
	end)
	if not ok then
		warn("[colliders] the environment didn't build: " .. tostring(err))
	end
	for _, item in workspace:GetDescendants() do
		if item:IsA("BasePart") then
			__environmentParts[item] = true
		end
	end
end

-- The slowest collision rebuilds so far ("Prop.Piece seconds"), slowest first.
function __slowestRebuilds(count: number): { string }
	local log = table.clone(__require("Server/World/MeshLibrary").RebuildLog)
	table.sort(log, function(a, b)
		return a[2] > b[2]
	end)
	local out = {}
	for index = 1, math.min(count, #log) do
		table.insert(out, `{log[index][1]} {__r2(log[index][2])}`)
	end
	return out
end

function __runLobbyColliders(reach: number)
	local GameState = __require("Shared/GameState")
	GameState.Folder()
	__require("Server/World/Shapes").RecordPieces = true
	if __noCsg then
		__require("Server/World/Shapes").PauseCsgForTests(1e6)
	end
	local LobbyBuilder = __require("Server/World/LobbyBuilder")
	local BeachBalls = __require("Server/World/BeachBalls")
	local EventDecor = __require("Server/World/EventDecor")
	local summary = {}
	if __decor then
		EventDecor.Show(__decor) -- (round_harness.py --decor: as EventService does while an event is on)
	end
	local buildStart = os.clock()
	local okLobby, refs = pcall(LobbyBuilder.Build)
	if okLobby and __decor then
		local spots = {}
		for index in EventDecor.HuntSpots(__decor) do
			table.insert(spots, index)
		end
		summary.decor = { set = EventDecor.Showing(), pumpkins = #EventDecor.PlaceHunt(__decor, spots) }
	end
	summary.buildSeconds = os.clock() - buildStart
	summary.lobby = if okLobby then "ok" else tostring(refs)
	if okLobby then
		local okBalls, err = pcall(BeachBalls.Setup, refs.Root, refs.BallSpots, {
			PlazaRadius = LobbyBuilder.PlazaRadius,
			StageFrontZ = LobbyBuilder.StageFrontZ,
			Traps = LobbyBuilder.BallTraps,
		})
		summary.balls = if okBalls then "ok" else tostring(err)
	end
	task.wait(2)
	summary.rebuildWait, summary.rebuildsLeft, summary.rebuildHitch = __waitForRebuilds(200)
	summary.rebuildSlowest = __slowestRebuilds(5)
	local okSnap, snapshot = pcall(__colliderSnapshot, "lobby", { center = Vector3.zero, reach = reach })
	summary.colliders = { if okSnap then snapshot else { label = "lobby", failed = tostring(snapshot) } }
	summary.errors = __errors
	summary.log = __log
	return HttpService:JSONEncode(summary)
end
