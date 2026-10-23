-- Checks client/PetPoses, how the crate seasons' pets move (owner: "For all of these pets. They all
-- have super cool animations right?"): every pose is a real, modest move; the owl's wings rise
-- together and its lantern stays hung from its beak whatever its head does; the stag gallops with its
-- front and back legs swinging opposite ways, rears on its back legs pawing forward, and its ears ride
-- its head; the Gourdian's roots stream behind it at a run; the Tot hops; the wisp's ghost spins.
-- The hinges are the exported meshes' Hinge markers (tools/meshgen/season/out/*.npz, Roblox space:
-- front -Z, up +Y, the base on y = 0).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local TestKit = require("./TestKit")

local test, expectTrue = TestKit.test, TestKit.expectTrue

local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local PetPoses = luau.load(fs.readFile("src/client/PetPoses.luau"), {
	debugName = "PetPoses",
	environment = {
		CFrame = CFrame,
		Vector3 = Vector3,
		game = {
			GetService = function(_, name)
				assert(name == "ReplicatedStorage", name)
				return { Shared = { Seasons = "Seasons" } }
			end,
		},
		require = function()
			return {}
		end,
	},
})()

local function groups(hinges: { [string]: any })
	local out = {}
	for name, at in hinges do
		out[name] = { Hinge = Vector3.new(at[1], at[2], at[3]), Parts = {} }
	end
	return out
end

local PETS = {
	Owl = {
		Info = { Flourish = "Owl" },
		Height = 4.23,
		Depth = 1.17,
		Run = 0,
		Groups = groups({
			Head = { 0, 2.06, -0.16 },
			WingL = { 0.36, 1.6, 0.14 },
			WingR = { -0.36, 1.6, 0.14 },
			Lantern = { 0, 1.82, -0.72 },
			Tail = { 0, 0.84, 0.4 },
		}),
	},
	Stag = {
		Info = { Flourish = "Stag" },
		Height = 4.49,
		Depth = 1.22,
		Run = 0,
		Groups = groups({
			Head = { 0, 1.74, -0.52 },
			EarL = { 0.09, 2.79, -0.8 },
			EarR = { -0.09, 2.79, -0.8 },
			LegFL = { 0.19, 1.46, -0.42 },
			LegFR = { -0.19, 1.46, -0.42 },
			LegBL = { 0.18, 1.46, 0.5 },
			LegBR = { -0.18, 1.46, 0.5 },
			Tail = { 0, 1.7, 0.73 },
		}),
	},
	Gourdian = {
		Info = { Flourish = "Gourdian" },
		Height = 3.57,
		Depth = 1.47,
		Run = 0,
		Groups = groups({
			Head = { 0, 2.02, 0 },
			Roots = { 0, 0.92, 0 },
			FistL = { 1.26, 1.0, -0.18 },
			FistR = { -1.26, 1.0, -0.18 },
			Seed = { 0, 1.75, 0 },
		}),
	},
	Tot = {
		Info = { Flourish = "Tot" },
		Height = 2.0,
		Depth = 0.94,
		Run = 0,
		Groups = groups({ Cap = { 0, 1.31, 0 } }),
	},
	Wisp = {
		Info = { Flourish = "Wisp" },
		Height = 3.28,
		Depth = 0.69,
		Run = 0,
		Groups = groups({ Ghost = { 0, 0.99, 0 }, Tail = { -0.1, 2.09, 0.05 } }),
	},
}

local function finite(cf): boolean
	local x, y, z = cf:ToEulerAnglesXYZ()
	local p = cf.Position
	for _, value in { x, y, z, p.X, p.Y, p.Z } do
		if value ~= value or math.abs(value) == math.huge then
			return false
		end
	end
	return true
end

local function near(a, b, tolerance: number?): boolean
	return (a - b).Magnitude < (tolerance or 1e-4)
end

-- Where `group`'s move takes a point `offset` from its hinge.
local function moved(pet, moves, group: string, offset)
	local at = pet.Groups[group].Hinge + offset
	local move = moves[group]
	return if move then move * at else at
end

test("every pose is a real, modest move: no NaN, the body never strays far", function()
	local worst, broken = 0, {}
	for kind, pet in PETS do
		for _, run in { 0, 0.5, 1 } do
			pet.Run = run
			for step = 0, 50 do
				local clock = step * 0.37
				for flourish = -1, 20 do
					local t = if flourish < 0 then nil else flourish / 20
					local body, turns = PetPoses.Pose(pet, t, clock)
					if not finite(body) then
						table.insert(broken, `{kind} body`)
					end
					worst = math.max(worst, body.Position.Magnitude / pet.Height)
					for name, turn in turns do
						if not finite(turn) then
							table.insert(broken, `{kind} {name}`)
						end
					end
					for name, move in PetPoses.Moves(pet, turns) do
						if not finite(move) then
							table.insert(broken, `{kind} {name} move`)
						end
					end
				end
			end
		end
		pet.Run = 0
	end
	expectTrue(#broken == 0, table.concat(broken, ", "))
	expectTrue(worst < 0.7, `the body moved {worst} of its height`)
end)

test("the owl's wings rise together on the upstroke, its body dipping", function()
	local owl = PETS.Owl
	local body, turns = PetPoses.Pose(owl, nil, math.pi / 10) -- (the beat's peak)
	local moves = PetPoses.Moves(owl, turns)
	local left = moved(owl, moves, "WingL", Vector3.new(1.5, 0, 0))
	local right = moved(owl, moves, "WingR", Vector3.new(-1.5, 0, 0))
	expectTrue(left.Y > owl.Groups.WingL.Hinge.Y + 0.2, `left wing tip at {left.Y}`)
	expectTrue(right.Y > owl.Groups.WingR.Hinge.Y + 0.2, `right wing tip at {right.Y}`)
	expectTrue(math.abs(left.Y - right.Y) < 1e-4, "the wings move together")
	expectTrue(body.Position.Y < 0, "the body dips as the wings rise")
end)

test("the owl's lantern stays hung from its beak whatever its head does", function()
	local owl = PETS.Owl
	for step = 0, 30 do
		local t = if step % 2 == 0 then step / 30 else nil
		local _, turns = PetPoses.Pose(owl, t, step * 0.41)
		local moves = PetPoses.Moves(owl, turns)
		local beak = owl.Groups.Lantern.Hinge
		expectTrue(near(moves.Lantern * beak, moves.Head * beak), "the chain's top moves with the beak")
	end
end)

test("the owl's flourish dives nose-down with its wings tucked, then climbs", function()
	local owl = PETS.Owl
	local body, turns = PetPoses.Pose(owl, 0.22, 0)
	expectTrue(body.Position.Y < -0.5, `it dives ({body.Position.Y})`)
	expectTrue(body.LookVector.Y < -0.2, "nose down")
	local moves = PetPoses.Moves(owl, turns)
	expectTrue(moved(owl, moves, "WingL", Vector3.new(1.5, 0, 0)).Y > owl.Groups.WingL.Hinge.Y + 0.5, "wings tucked up")
	local climb = PetPoses.Pose(owl, 0.7, 0)
	expectTrue(climb.Position.Y > 0.3, `then climbs ({climb.Position.Y})`)
end)

test("the stag gallops at a run, front and back legs swinging opposite ways", function()
	local stag = PETS.Stag
	stag.Run = 1
	local _, turns = PetPoses.Pose(stag, nil, math.pi / 18) -- (the gait's peak)
	stag.Run = 0
	local moves = PetPoses.Moves(stag, turns)
	local hoof = Vector3.new(0, -1.4, 0)
	local front = moved(stag, moves, "LegFL", hoof)
	local back = moved(stag, moves, "LegBL", hoof)
	expectTrue(front.Z < stag.Groups.LegFL.Hinge.Z - 0.4, `the front hoof reaches forward ({front.Z})`)
	expectTrue(back.Z > stag.Groups.LegBL.Hinge.Z + 0.4, `the back hoof kicks back ({back.Z})`)
	local _, still = PetPoses.Pose(stag, nil, math.pi / 18)
	local calm = PetPoses.Moves(stag, still)
	expectTrue(near(moved(stag, calm, "LegFL", hoof), stag.Groups.LegFL.Hinge + hoof), "standing still, legs still")
end)

test("the stag rears on its back legs, pawing forward, its ears riding its head", function()
	local stag = PETS.Stag
	local body, turns = PetPoses.Pose(stag, 0.5, 0)
	local nose = body * Vector3.new(0, 2, -stag.Depth)
	local rump = body * Vector3.new(0, 2, stag.Depth)
	expectTrue(nose.Y > rump.Y + 1, `the front rises ({nose.Y} over {rump.Y})`)
	expectTrue(
		near(body * Vector3.new(0, 0, stag.Depth * 0.8), Vector3.new(0, 0, stag.Depth * 0.8), 0.05),
		"it pivots on its back hooves"
	)
	local moves = PetPoses.Moves(stag, turns)
	expectTrue(moved(stag, moves, "LegFL", Vector3.new(0, -1.4, 0)).Z < stag.Groups.LegFL.Hinge.Z - 0.6, "paws forward")
	for step = 0, 20 do
		local _, idle = PetPoses.Pose(stag, nil, step * 0.53)
		local idleMoves = PetPoses.Moves(stag, idle)
		for _, ear in { "EarL", "EarR" } do
			local root = stag.Groups[ear].Hinge
			expectTrue(near(idleMoves[ear] * root, idleMoves.Head * root), `{ear} stays on the head`)
		end
	end
end)

test("the Gourdian's roots stream behind it at a run", function()
	local gourdian = PETS.Gourdian
	gourdian.Run = 1
	local _, turns = PetPoses.Pose(gourdian, nil, 0)
	gourdian.Run = 0
	local tip = moved(gourdian, PetPoses.Moves(gourdian, turns), "Roots", Vector3.new(0, -0.9, 0))
	expectTrue(tip.Z > 0.3, `the roots trail back ({tip.Z})`)
end)

test("the Tot hops in its flourish; the wisp's ghost spins round", function()
	local tot = PETS.Tot
	local hop = PetPoses.Pose(tot, 0.25, 0)
	expectTrue(hop.Position.Y > 0.5, `it hops ({hop.Position.Y})`)
	local wisp = PETS.Wisp
	local _, turns = PetPoses.Pose(wisp, 0.5, 0)
	expectTrue(turns.Ghost.LookVector.Z > 0.9, "halfway round, the ghost faces away")
end)
