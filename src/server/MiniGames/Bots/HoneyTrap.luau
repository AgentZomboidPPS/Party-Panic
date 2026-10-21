-- How bots play Honey Trap (owner: "we need bots in the mini games"; the contract is in
-- Bots/Default.luau). A bot stands on its pad watching the tree. On its turn it notices
-- (bot:Reaction()), looks at the vine for a moment and stops the block, now and then by jumping
-- into it like a player can.
--
-- Skilled bots count the fruit before the next honeycomb and go for the face that keeps them clear
-- of it and leaves the next player in trouble: Nim with takes of 1 or 2 when two are left (leave a
-- multiple of 3), looking around the circle when there are more, and never 2 when 1 fruit is left.
-- They time the hit while that face shows (HoneyTrap.FaceAt, the server's own clock) and sometimes
-- miss the window. Less skilled bots mostly hit at a random moment. Every bot hits well before the
-- block would stop by itself, so no turn waits for the timer.

local HoneyTrapBrain = {}

local SCAN = 0.02 -- seconds between looks at the block's schedule when finding when a face shows
local LATEST = 0.4 -- a bot always hits at least this long before the block stops by itself
local JUMP_HIT = 0.35 -- how often a bot hits the block by jumping into it
local IDLE_HOP = 0.005 -- chance per step (about 7 a second) of a little hop while waiting
local CHEER = 0.3 -- chance of a hop when the bees come out for someone else

-- Fruit left before the next honeycomb, counting up from the bottom of the vine.
local function fruitBeforeHoney(mode): number
	local vine: string = mode.vine
	local count = 0
	for index = mode.next, #vine do
		if string.sub(vine, index, index) == "H" then
			break
		end
		count += 1
	end
	return count
end

-- Odds seen from the next player's turn, moved back one seat to the player taking now.
local function shifted(later: { number }): { number }
	local seats = #later
	local odds = table.create(seats, 0)
	for seat = 1, seats do
		odds[seat % seats + 1] = later[seat]
	end
	return odds
end

-- Who ends up with the honeycomb when `fruit` are left before it and `seats` players take turns
-- taking 1 or 2, each keeping clear of it when they can (a coin toss when it makes no difference to
-- them). odds[s + 1] is the chance for the player s turns after the one about to take.
local function honeyOdds(fruit: number, seats: number): { number }
	if fruit <= 0 then
		local odds = table.create(seats, 0)
		odds[1] = 1
		return odds
	end
	local one = shifted(honeyOdds(fruit - 1, seats))
	if fruit == 1 then
		return one -- taking 2 would take the honeycomb too
	end
	local two = shifted(honeyOdds(fruit - 2, seats))
	if math.abs(one[1] - two[1]) > 1e-6 then
		return if one[1] < two[1] then one else two
	end
	local odds = table.create(seats, 0)
	for seat = 1, seats do
		odds[seat] = (one[seat] + two[seat]) / 2
	end
	return odds
end

-- The take a player who counts wants with `fruit` left before the next honeycomb and `players`
-- still in: clear of the honeycomb first, then the one that leaves the next player in trouble.
-- With two players that's Nim (leave a multiple of 3). nil when it makes no difference.
function HoneyTrapBrain.BestTake(fruit: number, players: number): number?
	if fruit <= 0 then
		return nil -- the honeycomb is at the bottom: either face takes it
	elseif fruit == 1 then
		return 1 -- never step onto a honeycomb when 1 avoids it
	end
	local seats = math.max(players, 2)
	local one = shifted(honeyOdds(fruit - 1, seats))
	local two = shifted(honeyOdds(fruit - 2, seats))
	if math.abs(one[1] - two[1]) > 1e-6 then
		return if one[1] < two[1] then 1 else 2
	elseif math.abs(one[2] - two[2]) > 1e-6 then
		return if one[2] > two[2] then 1 else 2
	end
	return nil
end

-- When `face` shows during this turn, as { from, to } in server time: read off the mode's own rule
-- for the block, so a bot's timing matches what players see.
local function windows(mode, turn, face: number): { { number } }
	local list = {}
	local from: number? = nil
	local t = turn.T0
	while t <= turn.Deadline do
		local showing = mode.FaceAt(turn, t) == face
		if showing and not from then
			from = t
		elseif not showing and from then
			table.insert(list, { from, t })
			from = nil
		end
		t += SCAN
	end
	if from then
		table.insert(list, { from, turn.Deadline })
	end
	return list
end

-- A random number from a bell curve (middle 0, spread 1): how far off a hit lands.
local function bell(rng: Random): number
	return math.sqrt(-2 * math.log(1 - rng:NextNumber())) * math.cos(2 * math.pi * rng:NextNumber())
end

-- Decides, once, when this turn's hit happens (server time).
local function plan(bot, ctx, mode, turn)
	local memory = bot.Memory
	local rng = bot.Rng
	memory.Turn = turn.Id
	memory.Pressed = nil
	memory.Hops = 0
	memory.Jump = bot:Chance(JUMP_HIT)
	-- It notices its turn, and the block has to be up (T0) before it can be hit.
	local ready = math.max(ctx:Now() + bot:Reaction(), turn.T0 + 0.05)
	local hitAt
	if bot:Chance(math.clamp((bot.Skill - 0.2) / 0.7, 0.1, 0.95)) then
		-- It counts the fruit before the next honeycomb, then waits for the face it wants.
		ready += rng:NextNumber(0.15, 0.55)
		local fruit = fruitBeforeHoney(mode)
		local face = HoneyTrapBrain.BestTake(fruit, ctx:AliveCount())
		memory.Want = face
		hitAt = ready + (if fruit == 0 then rng:NextNumber(0.3, 0.9) else 0) -- nothing to be done: a sigh
		if face then
			for _, window in windows(mode, turn, face) do
				local middle = (window[1] + window[2]) / 2
				if middle >= ready then
					-- Aims for the middle; the less skilled, the wider it lands (now and then on the
					-- other face).
					local spread = (window[2] - window[1]) * math.max(0.2, 0.3 + (0.9 - bot.Skill) * 0.36)
					hitAt = middle + bell(rng) * spread
					break
				end
			end
		end
	else
		memory.Want = nil
		hitAt = ready + rng:NextNumber(0.05, 0.9) -- whatever the block shows by then
	end
	memory.HitAt = math.max(turn.T0 + 0.05, math.min(hitAt, turn.Deadline - LATEST))
end

-- Stops the block (with a jump now and then: a player's jump hits it too), claiming the face that
-- shows right now, like a player's client does.
local function press(bot, ctx, mode, turn)
	if mode.current ~= turn or turn.Done or not bot.Parent or not ctx:IsAlive(bot) then
		return
	end
	if bot.Memory.Jump then
		bot:Jump()
	end
	ctx:BotAction(bot, "Hit", mode.FaceAt(turn, ctx:Now()))
end

function HoneyTrapBrain.Step(bot, ctx, mode, _dt)
	local root = bot:Root()
	if not root or not mode.vine then
		return
	end
	local memory = bot.Memory
	-- Stay on the pad facing the tree: it heads for a spot just in front, toward the tree, but walking
	-- speed is 0 in this mode, so it only turns.
	if not memory.Look then
		local origin = ctx.Origin.Position
		local toward = Vector3.new(origin.X - root.Position.X, 0, origin.Z - root.Position.Z)
		memory.Look = root.Position + (if toward.Magnitude > 0.1 then toward.Unit else root.CFrame.LookVector) * 3
	end
	bot:MoveTo(memory.Look)

	local turn = mode.current
	if turn and turn.Player == bot and not turn.Done then
		if memory.Turn ~= turn.Id then
			plan(bot, ctx, mode, turn)
		end
		local now = ctx:Now()
		if not memory.Pressed and memory.HitAt - now < 0.2 then
			-- Due before the next step: press at the exact moment.
			memory.Pressed = now
			ctx:Delay(math.max(0, memory.HitAt - now), function()
				press(bot, ctx, mode, turn)
			end)
		elseif memory.Pressed and now - math.max(memory.Pressed, memory.HitAt) > 0.5 then
			-- The hit didn't count: press again rather than wait for the block to stop by itself.
			memory.Pressed = nil
			memory.HitAt = now
		end
		return
	end

	-- Waiting: cheer when the bees come out for someone else, flail when they come for this bot,
	-- and hop now and then.
	local bottom = mode.next
	if memory.Bottom and bottom > memory.Bottom then
		if string.find(string.sub(mode.vine, memory.Bottom, bottom - 1), "H", 1, true) then
			if turn and turn.Player == bot then
				memory.Hops, memory.HopAt = 2, os.clock() + 0.8
			elseif bot:Chance(CHEER) then
				memory.Hops, memory.HopAt = 1, os.clock() + bot:Reaction() + 0.4
			end
		end
	end
	memory.Bottom = bottom
	if (memory.Hops or 0) > 0 and os.clock() >= memory.HopAt then
		memory.Hops -= 1
		memory.HopAt = os.clock() + 0.85
		bot:Jump()
	elseif bot:Chance(IDLE_HOP) then
		bot:Jump()
	end
end

return HoneyTrapBrain
