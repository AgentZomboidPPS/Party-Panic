-- Scenario for round_harness.py --bot (Minecart Mayhem): what a rider sees while a broken bridge
-- comes up (owner: "Minecart mayhem needs to be fixed on mobile. you cannot see where to jump.").
-- At PLACE_AT seconds the stand-in client (Bot1, the phone or PC whose screen --ui-at and --dump-at
-- catch) is put FROM studs before the course's last gap with a switch after it (front wheels to its
-- near edge; the next switch's two ways are on screen then too), at cruising speed, where nobody
-- else has got to yet, so the snapshots catch it a known distance before the gap (the course is
-- dealt at random). It notes, at each time in MOMENTS (give the same times to --ui-at and
-- --dump-at), how far its front wheels are from the gap and in seconds, its speed, and where the
-- camera is (eye, a point 60 studs along its look, FieldOfView: tools/preview/render.py's
-- --cameras), its cart's frame and its head. After the last moment it jumps (the moment a player
-- would). The other riders press nothing; their rigs ride in their carts.
--
--   python3 tools/checks/round_harness.py MinecartMayhem --players 4 --client --touch --seconds 11 \
--       --ui-at 8,8.7,9.55 --dump-at 8.7 --bot tools/checks/scenarios/MinecartMayhem_jump.luau \
--       --map run.map.json > run.luau
local PLACE_AT = 7
local FROM = 66
local MOMENTS = { 8, 8.7, 9.55 }

return function(env)
	local ctx = env.ctx
	local mode = env.game
	local placed = false
	local jumped = false
	local noted = {}
	local gapTile, gapS = nil, nil

	local function fmt(v: Vector3): string
		return string.format("[%.2f, %.2f, %.2f]", v.X, v.Y, v.Z)
	end

	-- Front wheels to the gap's near edge (studs along the rails).
	local function ahead(rider): number
		local course = mode.course
		local mark = gapS - mode.Track.HALF_BASE
		if rider.Tile == gapTile then
			return mark - rider.S
		end
		local away = mark - rider.S
		for index = rider.Tile, gapTile - 1 do
			local tile = course.Tiles[index]
			away += (tile.Paths[if index == rider.Tile then rider.B else 1] or tile.Paths[1]).Total
		end
		return away
	end

	return function(elapsed)
		local Track = mode.Track
		local course = mode.course
		local me = env.players[1]
		local rider = me and mode.riders and mode.riders[me]
		if not course or not rider or not mode.racing then
			return
		end
		if not gapTile then
			for index, tile in course.Tiles do
				local nextTile = course.Tiles[index + 1]
				for _, feature in tile.Features do
					if feature.K == "Gap" and nextTile and nextTile.K == "Junction" then
						gapTile, gapS = index, feature.S
					end
				end
			end
			env.note(`jump scenario: the last gap before a switch is tile {gapTile} of {#course.Tiles}`)
		end
		for index, player in env.players do
			local other = mode.riders[player]
			if index > 1 and other and not other.Gone and env.Alive(player) then
				local seat = mode:_seat(other)
				env.Move(player, seat.Position, seat.Position + seat.LookVector)
			end
		end
		if not placed and elapsed >= PLACE_AT then
			placed = true
			local s = gapS - Track.HALF_BASE - FROM
			local index = gapTile
			while s < 0 and index > 1 do
				index -= 1
				s += course.Tiles[index].Paths[1].Total
			end
			rider.Tile, rider.B, rider.S, rider.V = index, 1, s, Track.CRUISE
			rider.Lean, rider.JumpAt, rider.DashUntil, rider.DownUntil = 0, -math.huge, 0, 0
			rider.Back, rider.Pending = false, {}
			env.note(
				string.format("placed at %.2f s: tile %d S %.1f, %.1f studs before the gap", elapsed, index, s, FROM)
			)
		end
		if not placed then
			return
		end
		for _, at in MOMENTS do
			if elapsed >= at and not noted[at] then
				noted[at] = true
				local d = ahead(rider)
				local camera = workspace.CurrentCamera
				local cf = camera.CFrame
				local cart = workspace:FindFirstChild("MiniGameClient")
				cart = cart and cart:FindFirstChild("Cart_" .. me.UserId)
				local head = me.Character and me.Character:FindFirstChild("Head")
				local pivot = if cart then (cart :: Model):GetPivot() else nil
				env.note(
					string.format(
						"moment %g (at %.2f s): front wheels %.1f studs before the gap (%.2f s), v %.1f, camera %s look %s fov %.1f %s, cart %s facing %s, head %s",
						at,
						elapsed,
						d,
						d / math.max(rider.V, 1),
						rider.V,
						fmt(cf.Position),
						fmt(cf.Position + cf.LookVector * 60),
						camera.FieldOfView,
						camera.CameraType.Name,
						if pivot then fmt(pivot.Position) else "?",
						if pivot then fmt(pivot.LookVector) else "?",
						if head then fmt((head :: BasePart).Position) else "?"
					)
				)
			end
		end
		if not jumped and noted[MOMENTS[#MOMENTS]] then
			jumped = true
			env.Action(me, "Jump", ctx:Now())
			env.note(string.format("Bot1 jumps %.1f studs before the gap", ahead(rider)))
		end
	end
end
