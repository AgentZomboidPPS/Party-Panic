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
MessyMemory.EYE = Vector3.new(0, 12.5, 10) -- the player's camera (booth frame)
MessyMemory.LOOK = Vector3.new(0, 8.72, -6) -- ...looking here (PC; phones look a little lower)
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

return MessyMemory
