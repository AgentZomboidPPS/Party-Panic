-- Offline check of Minecart Mayhem's chase cameras (lune run tools/checks/MinecartMayhemCamera
-- [rounds]): rides the main way of random courses (Shared/Logic/MinecartMayhemTrack) at a few speeds
-- with each camera of the client half (CAMERA and PHONE_CAMERA there, copied below: change them
-- together), trailing the cart the way it does (eased at 7 a second, phones easing back to the PC
-- camera past the finish line while the cart coasts out), and prints how close each comes to what
-- hangs over the rails: the junction gantries' boards (the server half hangs them GANTRY_UP higher
-- for the phones' camera) and the mine portals' lintels. Both must stay 0.5 studs clear.
--
-- Jump pass (owner: "Minecart mayhem needs to be fixed on mobile. you cannot see where to jump."):
-- written for the phones' higher camera.
local process = require("@lune/process")

local Track = require("../../src/shared/Logic/MinecartMayhemTrack")

local PC = { Up = 7.5, Back = 15 }
local PHONE = { Up = 10, Back = 9.5 }
local EASE = 7 -- (the camera's ease toward where it should be, per second)
local STEEP_EASE = 1.5 -- (phones: back to the PC camera past the finish line)
-- What hangs over the rails, above the rails' path line (server half and the meshes):
local BOARD_BOTTOM = 12.2 + 2.5 - 1.3 -- a gantry board's middle (12.2 + GANTRY_UP) less half its height
local BOARD_HALF_WIDTH = 7.1 -- (the two boards side by side)
local LINTEL = 12.6 -- the portal's timber frame over its opening (MinecartMayhemPortal: rails at 46)
local LINTEL_DEPTH = 11 -- (its rock face and frame, along the rails)
local CLEAR = 0.5

local ROUNDS = tonumber(process.args[1]) or 100
local SPEEDS = { 16, 24, 32, 40 }

local function newRng(seed: number)
	local state = seed
	local rng = {}
	function rng.NextNumber(_self): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
	function rng.NextInteger(self, a: number, b: number): number
		return math.min(b, a + math.floor(self:NextNumber() * (b - a + 1)))
	end
	return rng
end

type Overhead = { Z: number, X: number, Bottom: number, Depth: number, Kind: string }

-- Everything over the rails on a course, in course coordinates.
local function overheads(course: Track.Course): { Overhead }
	local list: { Overhead } = {}
	for _, tile in course.Tiles do
		local entry = tile.Entry
		if tile.K == "Junction" then
			-- (the gantry stands Track.SPLIT - 30 into the tile: before its entry, at the entry's height)
			local f = Track.SPLIT - 30
			table.insert(
				list,
				{ Z = entry[3] - f, X = entry[1], Bottom = entry[2] + BOARD_BOTTOM, Depth = 0.6, Kind = "board" }
			)
		elseif tile.K == "Start" or tile.K == "Finish" then
			local f = if tile.K == "Start" then 58 else Track.FINISH_AT + 2
			local x, y = Track.Shape(tile, 1, f)
			table.insert(list, {
				Z = entry[3] - f,
				X = entry[1] + x,
				Bottom = entry[2] + y + LINTEL,
				Depth = LINTEL_DEPTH,
				Kind = "lintel",
			})
		end
	end
	return list
end

local worst = {}
for _, name in { "PC", "Phone" } do
	worst[name] = { board = math.huge, lintel = math.huge }
end

for round = 1, ROUNDS do
	local course = Track.Build(Track.Generate(newRng(round * 7919)))
	local over = overheads(course)
	for _, speed in SPEEDS do
		for name, camera in { PC = PC, Phone = PHONE } do
			local tileIndex, s, v, t = 1, 0, 0, 0
			local finishedAt: number? = nil
			local steep = if name == "Phone" then 1 else 0
			local ex, ey, ez = nil :: number?, 0, 0 -- (the camera)
			local dt = 1 / 60
			while t < 200 do
				t += dt
				local tile = course.Tiles[tileIndex]
				local path = tile.Paths[1]
				if finishedAt then
					-- (coasting out past the line, as the client half draws a finished cart)
					s = course.FinishS + 18 * (1 - math.exp(-(t - finishedAt) / 1.4))
					steep += (0 - steep) * (1 - math.exp(-dt * STEEP_EASE))
					if t - finishedAt > 4 then
						break
					end
				else
					v += (speed - v) * (1 - math.exp(-1.3 * dt))
					s += v * dt
					if tileIndex == #course.Tiles and s >= course.FinishS then
						finishedAt = t
					elseif s >= path.Total and tileIndex < #course.Tiles then
						s -= path.Total
						tileIndex += 1
						continue
					end
				end
				local x, y, z, hx, _, hz = Track.At(course.Tiles[tileIndex].Paths[1], s)
				local flat = math.sqrt(hx * hx + hz * hz)
				local up = PC.Up + (camera.Up - PC.Up) * steep
				local back = PC.Back + (camera.Back - PC.Back) * steep
				local wx, wy, wz = x - hx / flat * back, y + Track.RAIL_TOP + up, z - hz / flat * back
				if ex == nil then
					ex, ey, ez = wx, wy, wz
				else
					local a = 1 - math.exp(-dt * EASE)
					ex, ey, ez = ex + (wx - ex) * a, ey + (wy - ey) * a, ez + (wz - ez) * a
				end
				for _, item in over do
					if
						math.abs(ez - item.Z) <= item.Depth
						and math.abs((ex :: number) - item.X) <= BOARD_HALF_WIDTH
					then
						local clear = item.Bottom - ey
						if clear < worst[name][item.Kind] then
							worst[name][item.Kind] = clear
						end
					end
				end
			end
		end
	end
end

local failed = false
for _, name in { "PC", "Phone" } do
	local camera = if name == "PC" then PC else PHONE
	local result = worst[name]
	print(
		string.format(
			"%-5s camera (%g up, %g back): %d courses at %s studs/s, closest to a gantry board %.2f studs, to a portal lintel %.2f",
			name,
			camera.Up,
			camera.Back,
			ROUNDS,
			table.concat(SPEEDS, "/"),
			result.board,
			result.lintel
		)
	)
	if result.board < CLEAR or result.lintel < CLEAR then
		failed = true
	end
end
if failed then
	print(`FAIL: a camera passes closer than {CLEAR} studs to something over the rails`)
	process.exit(1)
end
