-- Checks client/Pose, which turns characters' joints for every mode that poses them (owner: "Bots are
-- STILL ruberbanding and floating."): it finds a joint of either kind (a Motor6D, or the
-- AnimationConstraint this place's servers give R15 bodies) and never R6's neck for R15's; a turn in
-- the torso's axes points an arm the same way on R15 and R6 (the joints' numbers are the bodies
-- Players:CreateHumanoidModelFromDescription builds, measured on a test server); a turn on top of the
-- Animator's pose never piles up; and nothing else in the client writes a joint's Transform (a
-- Motor6D-only pose finds nothing on those R15 bodies).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local TestKit = require("./TestKit")

local test, expectTrue = TestKit.test, TestKit.expectTrue

local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
local rad = math.rad

local fakeRunService = {
	PreSimulation = {
		Connect = function(_, fn)
			return fn
		end,
	},
}
local Pose = luau.load(fs.readFile("src/client/Pose.luau"), {
	debugName = "Pose",
	environment = {
		CFrame = CFrame,
		game = {
			GetService = function(_, name)
				assert(name == "RunService", name)
				return fakeRunService
			end,
		},
	},
})()

-- Stand-ins for a body's instances: what Pose reads of them.
local function joint(class: string, props: { [string]: any })
	props.ClassName = class
	props.Transform = CFrame.identity
	function props:IsA(name: string): boolean
		return name == class
	end
	return props
end
local function holder(children: { [string]: any })
	return {
		FindFirstChild = function(_, name: string)
			return children[name]
		end,
	}
end
local function attachment(cf)
	return { CFrame = cf }
end

-- The right shoulder of each body (measured): R15's AnimationConstraint between its rig
-- attachments, R6's Motor6D with its turned C0 / C1.
local R15_A0 = CFrame.new(0.972, 0.598, 0)
local R15_A1 = CFrame.new(-0.501, 0.419, 0)
local R6_C0 = CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
local R6_C1 = CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
local R6_NECK = CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)

local function r15Body()
	local shoulder =
		joint("AnimationConstraint", { Attachment0 = attachment(R15_A0), Attachment1 = attachment(R15_A1) })
	local neck = joint("AnimationConstraint", {
		Attachment0 = attachment(CFrame.new(0, 0.849, 0)),
		Attachment1 = attachment(CFrame.new(0, -0.576, 0)),
	})
	return holder({
		RightUpperArm = holder({ RightShoulder = shoulder }),
		Head = holder({ Neck = neck }),
	}),
		shoulder,
		neck
end
local function r6Body()
	local shoulder = joint("Motor6D", { C0 = R6_C0, C1 = R6_C1 })
	local neck = joint("Motor6D", { C0 = R6_NECK, C1 = CFrame.new(0, -0.5, 0) * R6_NECK.Rotation })
	return holder({ Torso = holder({ ["Right Shoulder"] = shoulder, Neck = neck }) }), shoulder, neck
end

local function near(a, b, eps: number?): boolean
	return (a - b).Magnitude < (eps or 1e-4)
end

test("Pose finds a joint of either kind, and never R6's neck for R15's", function()
	local r15, shoulder, neck = r15Body()
	local found = Pose.Joint(r15, "RightShoulder")
	expectTrue(found ~= nil and found.Instance == shoulder, "R15's AnimationConstraint shoulder")
	expectTrue(Pose.Joint(r15, "Neck") ~= nil and Pose.Joint(r15, "Neck").Instance == neck, "R15's neck")
	local motor = joint("Motor6D", { C0 = R15_A0, C1 = R15_A1 })
	local older = Pose.Joint(holder({ RightUpperArm = holder({ RightShoulder = motor }) }), "RightShoulder")
	expectTrue(older ~= nil and older.Instance == motor, "an R15 body's Motor6D shoulder")
	local r6, r6Shoulder, r6Neck = r6Body()
	local arm = Pose.Joint(r6, "Right Shoulder")
	expectTrue(arm ~= nil and arm.Instance == r6Shoulder, "R6's shoulder in its torso")
	expectTrue(Pose.Joint(r6, "Neck") == nil, "R6's neck (other axes) is not R15's")
	local asked = Pose.Joint(r6, "Neck", "Torso")
	expectTrue(asked ~= nil and asked.Instance == r6Neck, "R6's neck when asked for in its torso")
	local weld = {
		IsA = function(_, name)
			return name == "Weld"
		end,
	}
	expectTrue(
		Pose.Joint(holder({ RightUpperArm = holder({ RightShoulder = weld }) }), "RightShoulder") == nil,
		"a weld is no joint"
	)
	local rig = Pose.Rig(r6, { "RightShoulder", "Right Shoulder", "Left Shoulder" })
	local names = {}
	for name in rig do
		table.insert(names, name)
	end
	expectTrue(#names == 1 and rig["Right Shoulder"] ~= nil, "Rig keeps the joints the body has")
end)

test("Set and Ease write the Transform as Motor6D.Transform was, Release puts it back", function()
	local r15, shoulder = r15Body()
	local found = Pose.Joint(r15, "RightShoulder")
	local target = CFrame.Angles(rad(40), 0, rad(-10))
	Pose.Ease(found, target, 0.25)
	expectTrue(shoulder.Transform:FuzzyEq(CFrame.identity:Lerp(target, 0.25), 1e-6), "eases from rest")
	Pose.Ease(found, target, 0.5)
	expectTrue(
		shoulder.Transform:FuzzyEq(CFrame.identity:Lerp(target, 0.25):Lerp(target, 0.5), 1e-6),
		"from what it wrote, whatever the Animator wrote since"
	)
	Pose.Set(found, target)
	expectTrue(shoulder.Transform == target, "Set writes it as given")
	Pose.Release(found)
	expectTrue(shoulder.Transform == CFrame.identity and found.Written == nil, "released to rest")
end)

test("a turn in the torso's axes points the arm the same way on R15 and R6", function()
	local r15 = Pose.Joint((r15Body()), "RightShoulder")
	local r6 = Pose.Joint((r6Body()), "Right Shoulder")
	for _, turn in { { 0, 0, 0 }, { 70, 0, 23 }, { 150, 0, 50 }, { -40, 30, 160 }, { 90, -60, 10 } } do
		local rotation = CFrame.Angles(rad(turn[1]), rad(turn[2]), rad(turn[3]))
		Pose.Turn(r15, rotation)
		Pose.Turn(r6, rotation)
		-- Each upper arm in its torso's space (part1 = part0 * C0|A0 * Transform * (C1|A1)^-1).
		local arm15 = R15_A0 * r15.Instance.Transform * R15_A1:Inverse()
		local arm6 = R6_C0 * r6.Instance.Transform * R6_C1:Inverse()
		expectTrue(near(-arm15.UpVector, -arm6.UpVector), `arm down the same way for {table.concat(turn, ",")}`)
		expectTrue(near(arm15.LookVector, arm6.LookVector), `arm faces the same way for {table.concat(turn, ",")}`)
		expectTrue(near(-arm15.UpVector, rotation:VectorToWorldSpace(Vector3.new(0, -1, 0))), "the turn as given")
	end
	-- The test server's R15 arm after a 70° / 23.3° turn (probe): down (0.396, -0.314, -0.863).
	Pose.Turn(r15, CFrame.Angles(rad(70), 0, rad(70 / 3)))
	local down = -(R15_A0 * r15.Instance.Transform * R15_A1:Inverse()).UpVector
	expectTrue(near(down, Vector3.new(0.396, -0.314, -0.863), 2e-3), `as measured: {down}`)
end)

test("TurnOver adds to the Animator's pose each frame and never piles up", function()
	local r15, shoulder = r15Body()
	local found = Pose.Joint(r15, "RightShoulder")
	local twist = CFrame.Angles(0, rad(30), 0)
	local walkA = CFrame.Angles(rad(12), 0, rad(3))
	local walkB = CFrame.Angles(rad(-9), 0, rad(-2))
	shoulder.Transform = walkA -- the Animator's frame
	Pose.TurnOver(found, twist)
	expectTrue(shoulder.Transform:FuzzyEq(walkA * twist, 1e-6), "on top of the walk")
	Pose.TurnOver(found, twist) -- no Animator write between (a frame it skipped)
	expectTrue(shoulder.Transform:FuzzyEq(walkA * twist, 1e-6), "not twisted twice")
	shoulder.Transform = walkB
	Pose.TurnOver(found, twist)
	expectTrue(shoulder.Transform:FuzzyEq(walkB * twist, 1e-6), "follows the next frame of the walk")
	Pose.Release(found)
	expectTrue(shoulder.Transform:FuzzyEq(walkB, 1e-6), "released to the Animator's pose")
	expectTrue(
		Pose.Over(walkA, R6_C0.Rotation, twist):FuzzyEq(walkA * R6_C0.Rotation:Inverse() * twist * R6_C0.Rotation, 1e-6),
		"in the joint's own axes"
	)
end)

test("nothing else in the client writes a joint's Transform or looks for Motor6Ds to pose", function()
	local function walk(dir: string)
		for _, name in fs.readDir(dir) do
			local path = `{dir}/{name}`
			if fs.isDir(path) then
				walk(path)
			elseif string.match(name, "%.luau$") and path ~= "src/client/Pose.luau" then
				local number = 0
				for line in string.gmatch(fs.readFile(path) .. "\n", "([^\n]*)\n") do
					number += 1
					if string.match(line, "^%s*%-%-") then
						continue
					end
					expectTrue(
						string.find(line, "%.Transform%s*=") == nil,
						`{path}:{number} writes a Transform (use client/Pose: it finds either kind of joint)`
					)
					expectTrue(
						string.find(line, 'IsA%("Motor6D"%)') == nil,
						`{path}:{number} looks for a Motor6D (this place's R15 bodies have AnimationConstraints)`
					)
				end
			end
		end
	end
	walk("src/client")
end)
