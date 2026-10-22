-- Messy Memory's shared numbers and rules: the booth geometry (where each shelf slot and each spot
-- on the counter is, in a booth's own frame), the round's timings and the move rule. The server
-- (MiniGames/MessyMemory) and the client half (client MiniGames/MessyMemory) both use this module,
-- so a toy the server puts in slot 7 sits exactly where the client draws slot 7, and the client's
-- instant (predicted) moves follow the same swap rule the server applies.
--
-- A booth's frame: its origin is on the floor in the middle of the booth's open front (where the
-- curtain hangs), -Z points into the booth (towards the shelf), +X is the player's right.
-- Positions: 1..SLOTS are shelf slots (row 1 is the top row, left to right), SLOTS + k is spot k on
-- the counter (each toy has its own counter spot after the mischief, its "home" there).
--
-- The phones' camera is worked out here too (PhoneFraming, for the client's header "Phones"), as plain
-- maths on the booth's geometry, so tests/MessyMemory.spec.luau can check it on every phone screen.

local MessyMemory = {}

MessyMemory.TOYS = {
	"MessyMemoryTeddy",
	"MessyMemoryDuck",
	"MessyMemoryRocket",
	"MessyMemoryRobot",
	"MessyMemoryBall",
	"MessyMemoryTop",
	"MessyMemoryBlock",
	"MessyMemoryBoat",
}
MessyMemory.TOY_ICONS = { "🧸", "🦆", "🚀", "🤖", "⚽", "🌀", "🧱", "⛵" }
MessyMemory.TOY_NAMES = { "Teddy", "Duck", "Rocket", "Robot", "Ball", "Top", "Block", "Boat" }

MessyMemory.COLS = 4
MessyMemory.ROWS = 3
MessyMemory.SLOTS = MessyMemory.COLS * MessyMemory.ROWS
MessyMemory.BOOTHS = 12 -- always a full ring; empty booths stay shut

-- Shelf geometry (studs, booth frame). The shelf mesh is built from the same numbers
-- (tools/meshgen/props/MessyMemory.py).
MessyMemory.SHELF_Z = -6.2 -- the shelf's middle (its pivot)
MessyMemory.SLOT_Z = -6.05 -- toys stand here (inside the cubbies, clear of the back panel)
MessyMemory.COL_X0 = -3.825 -- the first column's middle
MessyMemory.COL_PITCH = 2.55
MessyMemory.ROW_FLOORS = { 9.15, 6.4, 3.65 } -- cubby floors, top row first
MessyMemory.COUNTER_TOP = 2.6
MessyMemory.TRAY_X = { -3.9, -1.3, 1.3, 3.9 }
MessyMemory.TRAY_Z = { -3.4, -1.6 } -- back row, front row
MessyMemory.STAND_Z = 7.5 -- the player stands here, facing the shelf
MessyMemory.EYE = Vector3.new(0, 12.5, 10) -- the player's camera on PC (booth frame)
MessyMemory.LOOK = Vector3.new(0, 8.72, -6) -- ...looking here
MessyMemory.RING = 27.5 -- booth fronts from the arena's middle

-- Timings (seconds).
MessyMemory.STUDY = 7
MessyMemory.MESS = 2.6
MessyMemory.PLACE = 30
MessyMemory.REVEAL_STEP = 0.55
MessyMemory.REVEAL_HOLD = 2.6
MessyMemory.ALL_LOCKED_GRACE = 1.2 -- everyone's curtain shut: the reveal starts this soon

function MessyMemory.TrayPos(spot: number): number
	return MessyMemory.SLOTS + spot
end

function MessyMemory.IsSlot(pos: number): boolean
	return pos >= 1 and pos <= MessyMemory.SLOTS
end

-- Where a position is, in the booth frame (the toy's bottom middle).
function MessyMemory.LocalPoint(pos: number): Vector3
	if MessyMemory.IsSlot(pos) then
		local row = math.floor((pos - 1) / MessyMemory.COLS) + 1
		local col = (pos - 1) % MessyMemory.COLS + 1
		return Vector3.new(
			MessyMemory.COL_X0 + (col - 1) * MessyMemory.COL_PITCH,
			MessyMemory.ROW_FLOORS[row],
			MessyMemory.SLOT_Z
		)
	end
	local spot = pos - MessyMemory.SLOTS - 1 -- 0..7
	local row = math.floor(spot / 4) + 1
	local col = spot % 4 + 1
	return Vector3.new(MessyMemory.TRAY_X[col], MessyMemory.COUNTER_TOP, MessyMemory.TRAY_Z[row])
end

-- A booth's frame from its ring index (1..BOOTHS) around `center` (the arena floor's middle).
function MessyMemory.BoothFrame(center: Vector3, index: number): CFrame
	local angle = (index - 1) / MessyMemory.BOOTHS * math.pi * 2
	local outward = Vector3.new(math.sin(angle), 0, math.cos(angle))
	local origin = center + outward * MessyMemory.RING
	return CFrame.lookAt(origin, origin + outward)
end

-- Moves `toy` to `target` in `positions` (toy -> position), in place, and returns whether anything
-- changed. A counter target sends the toy to its own counter spot (`homes[toy]`). A slot holding
-- another toy swaps: that toy goes where the moved one was (or to its own counter spot if the moved
-- one came from the counter).
function MessyMemory.Move(positions: { number }, homes: { number }, toy: number, target: number): boolean
	local from = positions[toy]
	if not from then
		return false
	end
	if not MessyMemory.IsSlot(target) then
		if not MessyMemory.IsSlot(from) then
			return false
		end
		positions[toy] = MessyMemory.TrayPos(homes[toy])
		return true
	end
	if from == target then
		return false
	end
	for other, pos in positions do
		if other ~= toy and pos == target then
			positions[other] = if MessyMemory.IsSlot(from) then from else MessyMemory.TrayPos(homes[other])
			break
		end
	end
	positions[toy] = target
	return true
end

-- How many toys are on their own spot.
function MessyMemory.Correct(positions: { number }?, answer: { number }): number
	if not positions then
		return 0
	end
	local count = 0
	for toy, slot in answer do
		if positions[toy] == slot then
			count += 1
		end
	end
	return count
end

-- Phones' camera ----------------------------------------------------------------------------------
-- Straight into the booth (no turn) from PHONE_EYE: low enough that the awning's scallops clear the
-- shelf, and in front of the player's own head. The pitch and the vertical field of view come from
-- the screen (`size`, pixels; `top`, the bottom of the HUD's lines, pixels down it). "Shelf" frames the
-- shelf alone, from the top of its crown at `top` to the counter's back row just above the bottom
-- edge; "Booth" the shelf and the counter's toys, and if a toy would sit under a button (`buttons`:
-- circles, x, y and radius in pixels) the eye slides right, up to MAX_SHIFT studs, before the framing
-- shrinks. Returns the eye, pitch (down, radians) and field of view (degrees), or nil if it can't fit.
MessyMemory.PHONE_EYE = Vector3.new(0, 11, 11)
MessyMemory.MAX_SHIFT = 2.5
MessyMemory.SHELF_TOP = 12.7 -- the top of the shelf's crown...
MessyMemory.CROWN_Z = -5.1 -- ...and its front edge
local FOOT_GAP = 6 -- pixels between the framing's foot and the screen's bottom edge
local BUTTON_GAP = 8 -- pixels between the counter's toys and a button
local TOY_REACH = 0.85 -- the widest toy's half width on its counter spot...
local TOY_HEIGHT = 1.9 -- ...and the tallest toy

local TOY_CORNERS = {} -- the box any toy on a counter spot fits in
for _, x in { -TOY_REACH, TOY_REACH } do
	for _, y in { 0, TOY_HEIGHT } do
		for _, z in { -TOY_REACH, TOY_REACH } do
			table.insert(TOY_CORNERS, Vector3.new(x, y, z))
		end
	end
end
local CROWN = Vector3.new(0, MessyMemory.SHELF_TOP, MessyMemory.CROWN_Z)
local SHELF_FOOT = Vector3.new(0, MessyMemory.COUNTER_TOP, MessyMemory.TRAY_Z[1] - 0.2) -- the counter's back row
local COUNTER_FOOT = -- in front of its front row
	Vector3.new(0, MessyMemory.COUNTER_TOP, MessyMemory.TRAY_Z[#MessyMemory.TRAY_Z] + TOY_REACH)

-- The pitch and the field of view of a camera at `eye` looking straight into the booth that put
-- `high` (booth frame) `highY` pixels down a `height`-tall screen and `low` at `lowY`. A point whose
-- angle above level has tangent a shows k * tan(a + pitch) above the screen's middle, so with
-- t = tan(pitch) the two points' ratio is a quadratic in t.
function MessyMemory.Fit(
	eye: Vector3,
	high: Vector3,
	highY: number,
	low: Vector3,
	lowY: number,
	height: number
): (number?, number?)
	local a = (high.Y - eye.Y) / (eye.Z - high.Z)
	local b = (low.Y - eye.Y) / (eye.Z - low.Z)
	local s1, s2 = height / 2 - highY, height / 2 - lowY
	local qa, qb, qc = s1 * a - s2 * b, (s2 - s1) * (1 - a * b), s2 * a - s1 * b
	local roots: { number } = {}
	if math.abs(qa) > 1e-9 then
		local disc = qb * qb - 4 * qa * qc
		if disc >= 0 then
			roots = { (-qb + math.sqrt(disc)) / (2 * qa), (-qb - math.sqrt(disc)) / (2 * qa) }
		end
	elseif math.abs(qb) > 1e-9 then
		roots = { -qc / qb }
	end
	local bestPitch: number?, bestFov: number? = nil, nil
	for _, t in roots do
		local pitch = math.atan(t)
		if 1 - a * t > 0 and 1 - b * t > 0 and math.abs(pitch) < math.rad(50) then
			local k = (s1 - s2) / ((a + t) / (1 - a * t) - (b + t) / (1 - b * t))
			if k > 0 and (bestPitch == nil or math.abs(pitch) < math.abs(bestPitch)) then
				bestPitch, bestFov = pitch, math.deg(2 * math.atan(height / 2 / k))
			end
		end
	end
	return bestPitch, bestFov
end

-- Where a booth-frame point shows on a `size` screen (pixels from its top left) for that camera.
function MessyMemory.OnScreen(eye: Vector3, pitch: number, fov: number, size: Vector2, point: Vector3): Vector2
	local k = size.Y / 2 / math.tan(math.rad(fov) / 2)
	local d = point - eye
	local down, level = math.sin(pitch), math.cos(pitch)
	local depth = -d.Y * down - d.Z * level
	return Vector2.new(size.X / 2 + k * d.X / depth, size.Y / 2 - k * (d.Y * level - d.Z * down) / depth)
end

-- Whether every toy on the counter (any toy, on any spot) stays clear of the buttons.
function MessyMemory.ToysClear(eye: Vector3, pitch: number, fov: number, size: Vector2, buttons: { Vector3 }): boolean
	if #buttons == 0 then
		return true
	end
	for spot = 1, #MessyMemory.TOYS do
		local base = MessyMemory.LocalPoint(MessyMemory.TrayPos(spot))
		local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
		for _, corner in TOY_CORNERS do
			local p = MessyMemory.OnScreen(eye, pitch, fov, size, base + corner)
			left, top = math.min(left, p.X), math.min(top, p.Y)
			right, bottom = math.max(right, p.X), math.max(bottom, p.Y)
		end
		for _, button in buttons do
			local gapX = math.max(left - button.X, 0, button.X - right)
			local gapY = math.max(top - button.Y, 0, button.Y - bottom)
			if gapX * gapX + gapY * gapY < (button.Z + BUTTON_GAP) ^ 2 then
				return false
			end
		end
	end
	return true
end

function MessyMemory.PhoneFraming(
	kind: string,
	size: Vector2,
	top: number,
	buttons: { Vector3 }
): (Vector3?, number?, number?)
	local eye = MessyMemory.PHONE_EYE
	if size.Y < 100 then
		return nil, nil, nil
	end
	if kind == "Shelf" then
		local pitch, fov = MessyMemory.Fit(eye, CROWN, top, SHELF_FOOT, size.Y - FOOT_GAP, size.Y)
		if pitch and fov then
			return eye, pitch, fov
		end
		return nil, nil, nil
	end
	local foot = size.Y - FOOT_GAP
	while foot > top + 80 do
		local pitch, fov = MessyMemory.Fit(eye, CROWN, top, COUNTER_FOOT, foot, size.Y)
		if pitch and fov then
			for step = 0, MessyMemory.MAX_SHIFT * 10 do
				local moved = eye + Vector3.new(step / 10, 0, 0)
				if MessyMemory.ToysClear(moved, pitch, fov, size, buttons) then
					return moved, pitch, fov
				end
			end
		end
		foot -= 4
	end
	return nil, nil, nil
end

return MessyMemory
