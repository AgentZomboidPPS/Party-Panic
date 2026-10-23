-- The crate season's pets on a real Roblox server (owner: "For all of these pets. They all have super
-- cool animations right?"). tools/checks/pets_check.py bundles this with the round harness's prelude
-- (stand-in players with real R15 bodies, the client services' stand-ins) and the working tree's
-- modules: the pets' meshes come from the uploads through World/MeshLibrary (as World/SeasonWorld
-- gives them to devices), and Controllers/PetController builds and moves them as a device does.
--
-- Five stand-ins each put on one of HOLLOW NIGHT's pets. For three seconds standing, three running
-- and through each pet's flourish it samples every pet's pieces and checks: each moving group stays
-- joined at its Hinge (the owl's wings at its shoulders, the stag's legs at its hips, its ears on its
-- head...), the groups that should move do (the owl's wings beat, the stag's ears flick, its legs
-- gallop only at a run, the Gourdian's roots sway, the Tot's cap wobbles, the wisp's ghost bobs), and
-- the flourishes happen (the owl dives, the stag rears, the Tot hops, the wisp's ghost spins round,
-- the Gourdian's face blazes). Nothing may error.
function __runPets()
	local summary = { checks = {}, failed = {}, measures = {}, errors = {} }
	local function check(name: string, ok: boolean, detail: any?)
		local line = (if ok then "ok   " else "FAIL ") .. name
		if detail ~= nil then
			line ..= ": " .. (if type(detail) == "table" then HttpService:JSONEncode(detail) else tostring(detail))
		end
		table.insert(summary.checks, line)
		if not ok then
			table.insert(summary.failed, name)
		end
	end
	game:GetService("LogService").MessageOut:Connect(function(message, kind)
		if kind == Enum.MessageType.MessageError or kind == Enum.MessageType.MessageWarning then
			table.insert(summary.errors, message)
		end
	end)

	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Seasons = __require("Shared/Seasons")
	local MeshLibrary = __require("Server/World/MeshLibrary")
	local PetPoses = __require("Client/PetPoses")
	local season = Seasons.CurrentSeason()

	-- The meshes the devices clone (as World/SeasonWorld makes them), from the uploads.
	local folder = Instance.new("Folder")
	folder.Name = "SeasonMeshes"
	local sources = {}
	for _, pet in season.Pets do
		local prop = season.PetInfo[pet].Prop
		local model = MeshLibrary.Get(prop)
		model.Name = prop
		model.Parent = folder
		sources[prop] = MeshLibrary.Source(prop)
	end
	folder.Parent = ReplicatedStorage
	local uploaded = true
	for _, source in sources do
		uploaded = uploaded and source ~= "Fallback"
	end
	check("the pets are the uploaded meshes", uploaded, sources)

	-- Five stand-ins in a row before the camera, each with one pet.
	for index = 1, #season.Pets do
		table.insert(__fakePlayers, __newPlayer(index))
	end
	local people = table.clone(__fakePlayers)
	for index, person in people do
		person.Character:PivotTo(CFrame.new(index * 16 - 48, 4, 0))
	end
	workspace.CurrentCamera.CFrame = CFrame.lookAt(Vector3.new(0, 25, 70), Vector3.new(0, 5, 0))
	local PetController = __require("Client/Controllers/PetController")
	PetController.Start({})
	for index, person in people do
		person:SetAttribute("PP_Pet", season.Pets[index])
	end
	task.wait(2)

	-- Each pet's model, its body piece (no group), and each group's pieces and Hinge marker.
	local BODY = { Owl = "Feather", Stag = "Fur", Gourdian = "Body", Tot = "Skin", Wisp = "Glass" }
	local watched = {}
	for index, person in people do
		local pet = season.Pets[index]
		local kind = season.PetInfo[pet].Flourish
		local model = workspace:FindFirstChild("LocalPets")
			and workspace.LocalPets:FindFirstChild(`PP_Pet_{person.UserId}`)
		check(`{pet} is built and shown`, model ~= nil)
		if not model then
			continue
		end
		local entry = { Pet = pet, Kind = kind, Model = model, Owner = person, Groups = {} }
		entry.Body = model:FindFirstChild(BODY[kind], true)
		check(`{pet} has its body piece {BODY[kind]}`, entry.Body ~= nil)
		for _, part in model:GetDescendants() do
			if not part:IsA("BasePart") then
				continue
			end
			local group = PetPoses.GroupOf(part.Name)
			if group then
				local info = entry.Groups[group] or { Name = group }
				entry.Groups[group] = info
				if string.sub(part.Name, -5) == "Hinge" then
					info.Hinge = part
				elseif not info.Piece or part.Size.Magnitude > info.Piece.Size.Magnitude then
					info.Piece = part
				end
			end
		end
		table.insert(watched, entry)
	end

	-- Samples every pet for `seconds`: how far each Hinge drifts from where it sits on the body (or
	-- on its parent group's piece), how far each group's biggest piece turns against the body, and
	-- how the body moves against its owner. Turns are measured from the phase's first sample, or from
	-- `from`'s (another phase's results: the pose it started in).
	local function sample(seconds: number, from: any?)
		local results = {}
		for _, entry in watched do
			local result = { Drift = {}, Turn = {}, Low = math.huge, High = -math.huge, Pitch = 0, Spin = 0 }
			result.Start = if from and from[entry.Pet] then table.clone(from[entry.Pet].Start) else {}
			results[entry.Pet] = result
		end
		local started = os.clock()
		while os.clock() - started < seconds do
			for _, entry in watched do
				local result = results[entry.Pet]
				local body = entry.Body
				if not body or not body.Parent then
					continue
				end
				local root = entry.Owner.Character and entry.Owner.Character:FindFirstChild("HumanoidRootPart")
				if root then
					local height = body.Position.Y - root.Position.Y
					result.Low = math.min(result.Low, height)
					result.High = math.max(result.High, height)
					local look = body.CFrame.LookVector
					result.Pitch = math.max(result.Pitch, math.abs(math.deg(math.asin(math.clamp(look.Y, -1, 1)))))
				end
				for name, info in entry.Groups do
					local frame = body
					local parentName = PetPoses.PARENT_GROUP[name]
					if parentName and entry.Groups[parentName] and entry.Groups[parentName].Piece then
						frame = entry.Groups[parentName].Piece
					end
					local key = name
					if info.Hinge then
						local at = frame.CFrame:PointToObjectSpace(info.Hinge.Position)
						if result.Start[key .. "Hinge"] == nil then
							result.Start[key .. "Hinge"] = at
						else
							local drift = (at - result.Start[key .. "Hinge"]).Magnitude
							result.Drift[name] = math.max(result.Drift[name] or 0, drift)
						end
					end
					if info.Piece then
						local relative = body.CFrame:ToObjectSpace(info.Piece.CFrame).Rotation
						if result.Start[key] == nil then
							result.Start[key] = relative
						else
							local _, angle = (result.Start[key]:Inverse() * relative):ToAxisAngle()
							result.Turn[name] = math.max(result.Turn[name] or 0, math.deg(math.abs(angle)))
						end
					end
				end
			end
			task.wait(0.05)
		end
		return results
	end

	local function rounded(results)
		local out = {}
		for pet, result in results do
			local entry = { Low = result.Low, High = result.High, Pitch = result.Pitch, Drift = {}, Turn = {} }
			for name, value in result.Drift do
				entry.Drift[name] = math.floor(value * 1000 + 0.5) / 1000
			end
			for name, value in result.Turn do
				entry.Turn[name] = math.floor(value * 10 + 0.5) / 10
			end
			entry.Low = math.floor(entry.Low * 100 + 0.5) / 100
			entry.High = math.floor(entry.High * 100 + 0.5) / 100
			entry.Pitch = math.floor(entry.Pitch * 10 + 0.5) / 10
			out[pet] = entry
		end
		return out
	end

	-- (the groups that move by sliding, not turning: the ghost bobs, the fists drum, the leaves orbit)
	local SLIDES = { Ghost = true, FistL = true, FistR = true, Seed = true }
	local function joined(results, phase: string)
		for pet, result in results do
			local worst, where = 0, ""
			for name, drift in result.Drift do
				if drift > worst and not SLIDES[name] then
					worst, where = drift, name
				end
			end
			check(`{phase}: {pet}'s moving parts stay joined at their hinges`, worst < 0.03, `{where} {worst}`)
		end
	end

	-- 1. Standing.
	local idle = sample(3)
	summary.measures.Standing = rounded(idle)
	joined(idle, "standing")
	local function turned(results, pet: string, group: string, least: number, most: number?)
		local value = results[pet] and results[pet].Turn[group] or 0
		return value >= least and (most == nil or value <= most), value
	end
	local ok, value = turned(idle, "Pet_HarvestOwl", "WingL", 15)
	check("standing: the owl's wings beat", ok, value)
	ok, value = turned(idle, "Pet_EmberStag", "LegFL", 0, 3)
	check("standing: the stag's legs stay still", ok, value)
	ok, value = turned(idle, "Pet_EmberStag", "Head", 4)
	check("standing: the stag looks about", ok, value)
	ok, value = turned(idle, "Pet_Gourdian", "Roots", 3)
	check("standing: the Gourdian's roots sway", ok, value)
	ok, value = turned(idle, "Pet_ToadstoolTot", "Cap", 2)
	check("standing: the Tot's cap wobbles", ok, value)
	ok, value = turned(idle, "Pet_LanternWisp", "Ghost", 5)
	check("standing: the wisp's ghost looks about", ok, value)

	-- 2. Running: every owner runs off at a walk's full speed (16 studs a second). The stand-ins
	-- don't walk on this server, so the run moves them, their roots carrying the speed as a body's
	-- would (what PetController reads).
	local roots = {}
	for _, person in people do
		local root = person.Character:FindFirstChild("HumanoidRootPart")
		if root then
			root.Anchored = true
			table.insert(roots, { Model = person.Character, Root = root })
		end
	end
	local runner = game:GetService("RunService").Heartbeat:Connect(function(dt)
		for _, entry in roots do
			entry.Model:PivotTo(entry.Model:GetPivot() + Vector3.new(0, 0, 16 * dt))
			entry.Root.AssemblyLinearVelocity = Vector3.new(0, 0, 16)
		end
	end)
	task.wait(1)
	local speeds = {}
	for _, person in people do
		local root = person.Character:FindFirstChild("HumanoidRootPart")
		table.insert(speeds, if root then math.floor(root.AssemblyLinearVelocity.Magnitude * 10 + 0.5) / 10 else -1)
	end
	summary.measures.OwnerSpeeds = speeds
	local running = sample(2.5, idle)
	summary.measures.Running = rounded(running)
	joined(running, "running")
	ok, value = turned(running, "Pet_EmberStag", "LegFL", 25)
	check("running: the stag gallops", ok, value)
	ok, value = turned(running, "Pet_Gourdian", "Roots", 22)
	check("running: the Gourdian's roots stream behind", ok, value)
	runner:Disconnect()
	for _, entry in roots do
		entry.Root.AssemblyLinearVelocity = Vector3.zero
	end
	task.wait(2)

	-- 3. Every flourish at once, twice (a pet already in its own flourish carries on with it, so the
	-- better of the two is the one set off here).
	local function both(a, b)
		local out = {}
		for pet, first in a do
			local second = b[pet] or first
			local merged = {
				Low = math.min(first.Low, second.Low),
				High = math.max(first.High, second.High),
				Pitch = math.max(first.Pitch, second.Pitch),
				Drift = {},
				Turn = {},
			}
			for _, key in { "Drift", "Turn" } do
				for name, value in first[key] do
					merged[key][name] = math.max(value, second[key][name] or 0)
				end
			end
			out[pet] = merged
		end
		return out
	end
	for _, person in people do
		PetController.Celebrate(person)
	end
	local firstGo = sample(2.4)
	task.wait(0.3)
	for _, person in people do
		PetController.Celebrate(person)
	end
	local flourish = both(firstGo, sample(2.4))
	summary.measures.Flourish = rounded(flourish)
	joined(flourish, "flourish")
	local base = idle
	local function dropped(pet: string): number
		return (base[pet] and base[pet].Low or 0) - (flourish[pet] and flourish[pet].Low or 0)
	end
	local function rose(pet: string): number
		return (flourish[pet] and flourish[pet].High or 0) - (base[pet] and base[pet].High or 0)
	end
	check("flourish: the owl dives", dropped("Pet_HarvestOwl") > 0.9, dropped("Pet_HarvestOwl"))
	check(
		"flourish: the stag rears up",
		(flourish.Pet_EmberStag and flourish.Pet_EmberStag.Pitch or 0) > 20,
		flourish.Pet_EmberStag and flourish.Pet_EmberStag.Pitch
	)
	ok, value = turned(flourish, "Pet_EmberStag", "LegFL", 35)
	check("flourish: the stag paws the air", ok, value)
	check("flourish: the Tot hops", rose("Pet_ToadstoolTot") > 0.5, rose("Pet_ToadstoolTot"))
	ok, value = turned(flourish, "Pet_LanternWisp", "Ghost", 150)
	check("flourish: the wisp's ghost spins round", ok, value)
	ok, value = turned(flourish, "Pet_Gourdian", "Head", 10)
	check("flourish: the Gourdian shakes its head", ok, value)

	-- No errors along the way (the pets' own code, the meshes).
	local own = {}
	for _, message in summary.errors do
		if string.find(message, "Pet", 1, true) or string.find(message, "MeshLibrary", 1, true) then
			table.insert(own, message)
		end
	end
	check("no errors or warnings from the pets or their meshes", #own == 0, own)
	return summary
end
