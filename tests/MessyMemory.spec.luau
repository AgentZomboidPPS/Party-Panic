-- Checks Messy Memory's phone camera (src/shared/Logic/MessyMemory.PhoneFraming; owner, from an iPhone:
-- "Weird angle on mobile for this mini game.") on the screens tools/checks/ui_render.py lays the HUD
-- out on: the projection it reasons with is the camera the client builds; the shelf's crown sits just
-- under the HUD's lines and the awning's scallops clear the top shelf; the counter's toys stay on
-- screen and clear of PEEK / CLOSE; the eye looks straight in and moves right only as far as the
-- buttons need (barely on 2.17:1 phones); and while memorising the shelf alone fills the screen,
-- centred and bigger than with the counter.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local TestKit = require("./TestKit")

local test, expectTrue = TestKit.test, TestKit.expectTrue

local Vector2, Vector3, CFrame = roblox.Vector2, roblox.Vector3, roblox.CFrame
local Rules = luau.load(fs.readFile("src/shared/Logic/MessyMemory.luau"), {
	debugName = "MessyMemory",
	environment = { Vector2 = Vector2, Vector3 = Vector3, CFrame = CFrame },
})()

local function near(a: number, b: number, tolerance: number, message: string)
	expectTrue(math.abs(a - b) <= tolerance, `{message}: {a} vs {b}`)
end

-- name, screen size, the bottom of the HUD's lines + 2 (the phase panel's top plus 108 of its units)
-- and PEEK / CLOSE (x, y, radius), as the engine laid them out in a phone round's UI snapshot.
local SCREENS = {
	{ "phone-large", 932, 430, 134.2, { { 643.4, 364, 36.6 }, { 729.4, 364, 36.6 } } },
	{ "phone", 844, 390, 134.2, { { 567.4, 324, 36.6 }, { 653.4, 324, 36.6 } } },
	{ "phone-android", 800, 360, 134.2, { { 570.4, 294, 36.6 }, { 656.4, 294, 36.6 } } },
	{ "phone-small", 667, 375, 134.2, { { 437.4, 309, 36.6 }, { 523.4, 309, 36.6 } } },
	{ "tablet", 1024, 768, 156.4, { { 687.8, 600, 47.2 }, { 794.8, 600, 47.2 } } },
}

local function screen(entry)
	local buttons = {}
	for _, b in entry[5] do
		table.insert(buttons, Vector3.new(b[1], b[2], b[3]))
	end
	return entry[1], Vector2.new(entry[2], entry[3]), entry[4], buttons
end

-- The camera the client builds for its own booth (the booth frame as the world).
local function cameraFrame(eye, pitch: number)
	return CFrame.lookAt(eye, eye + Vector3.new(0, -math.sin(pitch), -math.cos(pitch)))
end

local CROWN = Vector3.new(0, Rules.SHELF_TOP, Rules.CROWN_Z)
local TOP_BOARD = Vector3.new(0, Rules.ROW_FLOORS[1] + 2.5, Rules.SHELF_Z + 1.2) -- the top row's ceiling
local SCALLOPS = Vector3.new(0, 11.8, 0.26) -- the awning's lowest edge, seen from below

test("MessyMemory: the framing's projection is the client's camera", function()
	local size = Vector2.new(932, 430)
	for _, eye in { Rules.PHONE_EYE, Rules.PHONE_EYE + Vector3.new(1.3, 0, 0) } do
		for _, pitch in { 0.05, 0.12, -0.03 } do
			local fov = 57
			local frame = cameraFrame(eye, pitch)
			local k = size.Y / 2 / math.tan(math.rad(fov) / 2)
			for _, point in { CROWN, Vector3.new(3.9, 2.6, -1.6), Vector3.new(-3.825, 3.65, -6.05) } do
				local q = frame:PointToObjectSpace(point)
				local screenPoint = Rules.OnScreen(eye, pitch, fov, size, point)
				near(screenPoint.X, size.X / 2 + k * q.X / -q.Z, 0.01, "x")
				near(screenPoint.Y, size.Y / 2 - k * q.Y / -q.Z, 0.01, "y")
			end
		end
	end
end)

test("MessyMemory: Fit puts both points where it's asked to", function()
	for _, entry in SCREENS do
		local name, size, top = screen(entry)
		local high, low = CROWN, Vector3.new(0, Rules.COUNTER_TOP, -0.75)
		local pitch, fov = Rules.Fit(Rules.PHONE_EYE, high, top, low, size.Y - 20, size.Y)
		expectTrue(pitch ~= nil and fov ~= nil, `{name}: a fit`)
		if pitch and fov then
			near(Rules.OnScreen(Rules.PHONE_EYE, pitch, fov, size, high).Y, top, 0.01, `{name} high`)
			near(Rules.OnScreen(Rules.PHONE_EYE, pitch, fov, size, low).Y, size.Y - 20, 0.01, `{name} low`)
		end
	end
end)

test("MessyMemory: putting toys back, the shelf and the counter fit and the toys stay clear", function()
	for _, entry in SCREENS do
		local name, size, top, buttons = screen(entry)
		local eye, pitch, fov = Rules.PhoneFraming("Booth", size, top, buttons)
		expectTrue(eye ~= nil and pitch ~= nil and fov ~= nil, `{name}: a framing`)
		if not (eye and pitch and fov) then
			continue
		end
		local function at(point)
			return Rules.OnScreen(eye, pitch, fov, size, point)
		end
		near(at(CROWN).Y, top, 0.01, `{name}: the crown just under the HUD`)
		expectTrue(at(SCALLOPS).Y < at(TOP_BOARD).Y, `{name}: the awning clears the top shelf`)
		expectTrue(eye.Y == Rules.PHONE_EYE.Y and eye.Z == Rules.PHONE_EYE.Z, `{name}: the eye only slides`)
		expectTrue(eye.X >= 0 and eye.X <= Rules.MAX_SHIFT + 1e-9, `{name}: slides {eye.X}`)
		if size.X / size.Y > 2.1 then
			expectTrue(eye.X <= 1, `{name}: a 2.17:1 phone stays (almost) centred ({eye.X})`)
		end
		expectTrue(Rules.ToysClear(eye, pitch, fov, size, buttons), `{name}: the toys clear PEEK / CLOSE`)
		for spot = 1, #Rules.TOYS do
			local base = Rules.LocalPoint(Rules.TrayPos(spot))
			for _, corner in { Vector3.new(-0.85, 0, 0.85), Vector3.new(0.85, 1.9, -0.85) } do
				local p = at(base + corner)
				expectTrue(p.X > 0 and p.X < size.X and p.Y > top and p.Y < size.Y, `{name}: spot {spot} on screen`)
			end
		end
		-- The player's own head (standing at STAND_Z) stays below the bottom edge.
		expectTrue(at(Vector3.new(0, 5.6, Rules.STAND_Z + 0.6)).Y > size.Y, `{name}: no head in the way`)
	end
end)

test("MessyMemory: memorising, the shelf alone fills the screen, centred", function()
	for _, entry in SCREENS do
		local name, size, top, buttons = screen(entry)
		local eye, pitch, fov = Rules.PhoneFraming("Shelf", size, top, {})
		local boothEye, boothPitch, boothFov = Rules.PhoneFraming("Booth", size, top, buttons)
		expectTrue(eye ~= nil and pitch ~= nil and fov ~= nil and boothFov ~= nil, `{name}: framings`)
		if not (eye and pitch and fov and boothEye and boothPitch and boothFov) then
			continue
		end
		expectTrue(eye == Rules.PHONE_EYE, `{name}: centred`)
		local function at(point)
			return Rules.OnScreen(eye, pitch, fov, size, point)
		end
		near(at(CROWN).Y, top, 0.01, `{name}: the crown just under the HUD`)
		expectTrue(at(SCALLOPS).Y < at(TOP_BOARD).Y, `{name}: the awning clears the top shelf`)
		local left, right = at(Vector3.new(-5.225, 7, -5)), at(Vector3.new(5.225, 7, -5))
		near((left.X + right.X) / 2, size.X / 2, 0.01, `{name}: the shelf in the middle`)
		local bottomRow = at(Vector3.new(0, Rules.ROW_FLOORS[#Rules.ROW_FLOORS], Rules.SLOT_Z))
		expectTrue(bottomRow.Y < size.Y - 20, `{name}: the bottom row on screen`)
		local booth = Rules.OnScreen(boothEye, boothPitch, boothFov, size, Vector3.new(5.225, 7, -5)).X
			- Rules.OnScreen(boothEye, boothPitch, boothFov, size, Vector3.new(-5.225, 7, -5)).X
		expectTrue(right.X - left.X > booth * 1.1, `{name}: the shelf alone is bigger`)
	end
end)
