-- Checks the Skee-Ball play screen in every layout (Shared/Logic/SkeeBallView): from the waiting
-- ball, a drag down to the screen's bottom edge reaches full power (so the 100 cups and every
-- other target can be hit) with room enough to aim the power; the ring board shows under the top
-- bar, and while the vote is up it keeps clear of the vote cards (under their row on phones,
-- the ball above them on PC). Screens are tools/checks/ui_render.py's sizes.
local TestKit = require("./TestKit")
local SkeeBall = require("../src/shared/Logic/SkeeBall")
local SkeeBallView = require("../src/shared/Logic/SkeeBallView")

local test, expectTrue, expectEqual = TestKit.test, TestKit.expectTrue, TestKit.expectEqual

-- Screens in points: size, Roblox's top bar (the HUD starts under it) and whether it's touch.
local SCREENS = {
	{ Name = "pc", W = 1280, H = 720, Top = 58, Touch = false },
	{ Name = "pc-hd", W = 1920, H = 1080, Top = 58, Touch = false },
	{ Name = "laptop", W = 1366, H = 768, Top = 58, Touch = false },
	{ Name = "phone-large", W = 932, H = 430, Top = 56, Touch = true },
	{ Name = "phone", W = 844, H = 390, Top = 56, Touch = true },
	{ Name = "phone-android", W = 800, H = 360, Top = 56, Touch = true },
	{ Name = "phone-small", W = 667, H = 375, Top = 56, Touch = true },
	{ Name = "tablet", W = 1024, H = 768, Top = 56, Touch = true },
}

-- UIKit.ScaleFor: the HUD's scale on a screen.
local function scaleFor(screen): number
	return math.clamp(math.min(screen.W / 1280, screen.H / 720), 0.62, 1.35)
end

local function ballPoint(dy: number): (number, number, number)
	return SkeeBall.ToMachine(0, SkeeBall.LANE_Y + SkeeBall.BALL_R + dy, 0)
end

local function boardTop(): (number, number, number)
	local u, y, s = SkeeBall.BoardPoint(0, SkeeBall.BOARD_LEN)
	return SkeeBall.ToMachine(u, y, s)
end

-- The lowest power that reaches each pocket (any aim): the strongest a drag must be able to give.
local function hardestPower(): number
	local lowest = {}
	for aimQ = 0, 2000, 40 do
		for powerQ = 0, 1000, 5 do
			local pocket = SkeeBall.Path(aimQ, powerQ, 1).Pocket
			if lowest[pocket] == nil or powerQ < lowest[pocket] then
				lowest[pocket] = powerQ
			end
		end
	end
	local hardest = 0
	for pocket, powerQ in lowest do
		if pocket ~= "Over" then
			hardest = math.max(hardest, powerQ / 1000)
		end
	end
	return hardest
end

local function posesFor(screen): { string }
	return { "Play", "Vote" }
end

test("SkeeBallView.Drag: pulling down is power, sideways aims the other way, both clamped", function()
	local w, h = 1000, 500
	local aim, power = SkeeBallView.Drag(500, 100, 500, 100 + 0.32 * h, w, h, h)
	expectEqual(aim, 0)
	expectEqual(power, 1, "a full pull from high on the lane")
	aim, power = SkeeBallView.Drag(500, 100, 500 - 0.17 * w, 100 + 0.16 * h, w, h, h)
	expectTrue(math.abs(aim - 1) < 1e-9, `a pull to the left aims right: {aim}`)
	expectTrue(math.abs(power - 0.5) < 1e-9, `half the pull is half power: {power}`)
	aim, power = SkeeBallView.Drag(500, 300, 900, 200, w, h, h)
	expectEqual(aim, -1)
	expectEqual(power, 0, "pushing up is no power")
	-- Low on the screen, full power is at the bottom edge...
	aim, power = SkeeBallView.Drag(500, 400, 500, h - SkeeBallView.EDGE, w, h, h)
	expectEqual(power, 1, "from low on the screen the bottom edge is full power")
	-- ... but never closer than MIN_REACH.
	aim, power = SkeeBallView.Drag(500, 480, 500, 480 + SkeeBallView.MIN_REACH * h / 2, w, h, h)
	expectTrue(math.abs(power - 0.5) < 1e-9, `half of the shortest reach: {power}`)
end)

test("SkeeBallView: from the waiting ball, a drag to the bottom edge reaches every target", function()
	local hardest = hardestPower()
	expectTrue(hardest > 0.7 and hardest < 1, `the 100 cups need about 0.79 power, got {hardest}`)
	for _, screen in SCREENS do
		for _, name in posesFor(screen) do
			local pose = SkeeBallView.Poses[name]
			local ballY = SkeeBallView.Project(pose, screen.W / screen.H, ballPoint(0)) * screen.H
			-- Touch positions leave out the top bar; the room below is the same either way.
			local startY, bottom = ballY - screen.Top, screen.H - screen.Top
			local _, power = SkeeBallView.Drag(0, startY, 0, bottom - SkeeBallView.EDGE, screen.W, screen.H, bottom)
			expectTrue(power >= hardest, `{screen.Name} {name}: the most a drag from the ball gives is {power}`)
			local reach = SkeeBallView.PowerReach(startY, screen.H, bottom)
			expectTrue(
				reach >= 0.18 * screen.H,
				`{screen.Name} {name}: full power in {reach} points is too twitchy to aim`
			)
		end
	end
end)

test("SkeeBallView: the ring board shows, and keeps clear of the vote cards while they're up", function()
	for _, screen in SCREENS do
		local scale = scaleFor(screen)
		local aspect = screen.W / screen.H
		for _, name in posesFor(screen) do
			local pose = SkeeBallView.Poses[name]
			local topY = SkeeBallView.Project(pose, aspect, boardTop()) * screen.H
			local ballBottom = SkeeBallView.Project(pose, aspect, ballPoint(-SkeeBall.BALL_R)) * screen.H
			expectTrue(ballBottom < screen.H, `{screen.Name} {name}: the ball is off the screen`)
			if screen.Touch then
				-- Under Roblox's top bar row; while voting, the ball above the cards at the bottom
				-- middle (VoteController: 10 up, 110 laid out and drawn 1.25 times).
				expectTrue(topY > screen.Top, `{screen.Name} {name}: the board's top at {topY} is under {screen.Top}`)
				if name == "Vote" then
					local cards = screen.H - (10 + 110 * 1.25) * scale
					expectTrue(
						ballBottom < cards,
						`{screen.Name}: the ball at {ballBottom} is behind the cards at {cards}`
					)
				end
			else
				-- Under the phase banner; while voting, the ball above the cards along the bottom
				-- (VoteController: 18 up, 214 cards, 34 over them for the tag).
				expectTrue(topY > 0.19 * screen.H, `{screen.Name} {name}: the board's top at {topY}`)
				if name == "Vote" then
					local cards = screen.H - (18 + 248) * scale
					expectTrue(
						ballBottom < cards,
						`{screen.Name}: the ball at {ballBottom} is behind the cards at {cards}`
					)
				end
			end
		end
	end
end)

test("SkeeBallView: every pose keeps the same eye (clear of the lobby's scenery)", function()
	local eye = SkeeBallView.Poses.Play.Eye
	for name, pose in SkeeBallView.Poses do
		expectEqual(pose.Eye, eye, `{name} moves the eye`)
	end
end)
