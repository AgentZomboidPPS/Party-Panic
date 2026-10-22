-- Checks Struggle's bat in hand (src/shared/Logic/Struggle.luau) on the standard bodies (owner: "Bats on
-- struggle arent actually being held they are floating. plus they dont even look like bats."): held
-- up ready, the wind-up back over the shoulder (further for a charge), and a level sweep whose tip
-- follows the hit rule's reach through the whole arc, so a swing draws what the server judges (owner:
-- "the precision games will feel super bad if we dont"). The bodies are the R15 and R6 rigs
-- Players:CreateHumanoidModelFromDescription builds from a blank description, measured on a test
-- server (shoulder, elbow and grip joints from the HumanoidRootPart's middle).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local TestKit = require("./TestKit")

local test, expectTrue = TestKit.test, TestKit.expectTrue

local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
local Rules = luau.load(fs.readFile("src/shared/Logic/Struggle.luau"), {
	debugName = "Struggle",
	environment = { Color3 = roblox.Color3, Vector3 = Vector3, CFrame = CFrame },
})()

local rad = math.rad

-- Where a pose puts the fist and the bat (root space: +X right, +Y up, -Z ahead), as the client
-- poses the rig: the body turned, the right arm at the shoulder, the elbow (R6: half at the
-- shoulder, half in the fist), the bat turned in the fist.
local function batOf(pose, rig: string, scale: number?)
	local twist = CFrame.Angles(0, rad(pose.Twist), 0)
	local arm = CFrame.Angles(0, rad(pose.Yaw), 0)
		* CFrame.Angles(rad(pose.Pitch), 0, 0)
		* CFrame.Angles(0, rad(pose.Roll), 0)
	local fist
	if rig == "R15" then
		local upper = twist * CFrame.new(0.972, 0.848, 0) * arm
		local lower = upper * CFrame.new(0.501, -0.774, 0) * CFrame.Angles(rad(pose.Elbow), 0, 0)
		fist = lower * CFrame.new(0, -1.097, 0) * CFrame.Angles(rad(-90), 0, 0) * CFrame.Angles(rad(pose.Tilt), 0, 0)
	else
		local whole = twist * CFrame.new(1, 0.5, 0) * arm * CFrame.Angles(rad(pose.Elbow / 2), 0, 0)
		fist = whole
			* CFrame.new(0.5, -1.5, 0)
			* CFrame.Angles(rad(-90), 0, 0)
			* CFrame.Angles(rad(pose.Tilt + pose.Elbow / 2), 0, 0)
	end
	local tip = fist * Vector3.new(0, (Rules.BAT_LENGTH - Rules.BAT_GRIP) * (scale or 1), 0)
	return fist.Position, fist.UpVector, tip
end

local function flat(v): number
	return math.sqrt(v.X * v.X + v.Z * v.Z)
end

local function bearing(v): number -- degrees round from straight ahead, + to the left
	return math.deg(math.atan2(-v.X, -v.Z))
end

test("Struggle bat: the sweep's tip follows the rule's reach across the arc, on R15 and R6", function()
	local arc = math.deg(Rules.ARC)
	for _, charged in { false, true } do
		local reach = if charged then Rules.RANGE_CHARGED else Rules.RANGE
		local scale = if charged then Rules.CHARGED_BAT else 1
		for _, rig in { "R15", "R6" } do
			for angle = -arc, arc, 10 do
				local _, axis, tip = batOf(Rules.SweepPose(angle, charged), rig, scale)
				local label = `{rig} {if charged then "charged" else "tap"} at {angle}`
				expectTrue(math.abs(flat(tip) - reach) <= 0.45, `{label}: tip {flat(tip)} out, the rule {reach}`)
				expectTrue(math.abs(bearing(tip) - angle) <= 6, `{label}: tip at {bearing(tip)}`)
				expectTrue(math.abs(axis.Y) <= 0.2, `{label}: the bat is level ({axis.Y})`)
			end
			-- Through the middle of the arc, where most hits land, it's closer still.
			for angle = -40, 40, 10 do
				local _, _, tip = batOf(Rules.SweepPose(angle, charged), rig, scale)
				expectTrue(math.abs(flat(tip) - reach) <= 0.3, `{rig} at {angle}: tip {flat(tip)} out`)
			end
		end
	end
end)

test("Struggle bat: held up ready, wound back over the shoulder, further for a charge", function()
	for _, rig in { "R15", "R6" } do
		local fist, axis = batOf(Rules.READY, rig)
		expectTrue(fist.Z < -0.8 and fist.X > 0.5, `{rig} ready: the fist in front, on the right ({fist})`)
		expectTrue(axis.Y > 0.6 and axis.Z < -0.2, `{rig} ready: barrel up and forward ({axis})`)
		local windFist, _, windTip = batOf(Rules.WIND, rig)
		expectTrue(windFist.Y > 0.5, `{rig} wind-up: the fist up by the shoulder ({windFist})`)
		expectTrue(windTip.Z > 1 and windTip.Y > 2, `{rig} wind-up: the bat back over the shoulder ({windTip})`)
		-- A charge winds further: the body turned further round, the bat laid level behind the head.
		local _, chargedAxis, chargedTip = batOf(Rules.WIND_CHARGED, rig)
		local behind = CFrame.Angles(0, rad(-Rules.WIND_CHARGED.Twist), 0) * chargedTip
		expectTrue(behind.Z > 0.5 and chargedTip.Y > 0.3, `{rig} charged wind-up: behind the head ({behind})`)
		expectTrue(math.abs(chargedAxis.Y) < 0.5, `{rig} charged wind-up: the bat laid back level ({chargedAxis})`)
	end
	expectTrue(Rules.WIND_CHARGED.Twist < Rules.WIND.Twist, "a charge turns the body further round")
end)

test("Struggle bat: the strike starts from the wind-up and only unwinds", function()
	-- The sweep's first turn is the wind-up's, so the body never turns back further on the way in.
	expectTrue(Rules.SweepPose(Rules.SWEEP_FROM, false).Twist == Rules.WIND.Twist, "tap: from the wind-up's turn")
	expectTrue(
		Rules.SweepPose(Rules.SWEEP_FROM, true).Twist == Rules.WIND_CHARGED.Twist,
		"charged: from the charged wind-up's turn"
	)
	expectTrue(Rules.SWEEP_FROM < -math.deg(Rules.ARC) and Rules.SWEEP_TO > math.deg(Rules.ARC), "past the arc")
	for _, charged in { false, true } do
		local last = -math.huge
		local from = Rules.WindPose(if charged then Rules.CHARGE else Rules.WINDUP)
		for k = 0, 1, 0.05 do
			local pose = Rules.StrikePose(from, k, charged)
			expectTrue(pose.Twist >= last - 1e-6, `unwinds (k {k}: {pose.Twist} after {last})`)
			last = pose.Twist
		end
	end
	-- A press reaches the wind-up quickly, and a full charge reaches the charged one.
	local tap = Rules.WindPose(Rules.WINDUP)
	expectTrue(math.abs(tap.Twist - Rules.WIND.Twist) < 6, `a tap is wound up by its strike ({tap.Twist})`)
	local full = Rules.WindPose(Rules.CHARGE)
	expectTrue(math.abs(full.Twist - Rules.WIND_CHARGED.Twist) < 1e-6, "a full charge is the charged wind-up")
end)

test("Struggle bat: the drawn size matches the mesh", function()
	local props = fs.readFile("src/server/World/Props/Struggle.luau")
	local height = tonumber(string.match(props, "StruggleBat = {%s*Height = ([%d%.]+)"))
	expectTrue(height == Rules.BAT_LENGTH, `StruggleBat's Height {height} vs BAT_LENGTH {Rules.BAT_LENGTH}`)
	local mesh = fs.readFile("tools/meshgen/props/Struggle.py")
	local length = tonumber(string.match(mesh, "BAT_LENGTH = ([%d%.]+)"))
	expectTrue(length == Rules.BAT_LENGTH, `the mesh's BAT_LENGTH {length}`)
	expectTrue(Rules.BAT_GRIP > 0.6 and Rules.BAT_GRIP < 1, "the fist holds the handle above the knob")
end)

return nil
