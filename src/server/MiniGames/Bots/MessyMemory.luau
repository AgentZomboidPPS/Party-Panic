-- How bots play Messy Memory. While the shelf is on show a bot "memorises" it: each toy's spot is
-- remembered right with a chance that grows with skill (about 2 in 3 for a clumsy bot, 9 in 10 for a
-- sharp one); a wrong memory is usually a neighbouring slot, like a person's. Once placing starts
-- it puts the toys back one at a time at a human pace (quicker with skill), unsure toys last; for
-- an unsure toy it sometimes PEEKs at an open rival booth and copies where that rival put it (the
-- rival may be wrong too). When every toy is on the shelf it waits a moment and shuts its curtain.
-- Every move goes through ctx:BotAction, so the server checks it exactly like a player's. There are
-- no hazards in this mode: the mischief changes the shared positions for bots and players alike.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Logic.MessyMemory)

local MessyMemory = {}

-- A slot next to `slot` (left, right, above or below), or any slot now and then.
local function neighbour(slot: number, random: Random): number
	if random:NextNumber() < 0.25 then
		return random:NextInteger(1, Rules.SLOTS)
	end
	local row = math.floor((slot - 1) / Rules.COLS)
	local col = (slot - 1) % Rules.COLS
	local options = {}
	for _, offset in { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } } do
		local r, c = row + offset[1], col + offset[2]
		if r >= 0 and r < Rules.ROWS and c >= 0 and c < Rules.COLS then
			table.insert(options, r * Rules.COLS + c + 1)
		end
	end
	return options[random:NextInteger(1, #options)]
end

function MessyMemory.Step(bot, ctx, mode, _dt)
	local memory = bot.Memory
	local random = bot.Rng
	local now = ctx:Now()
	local phase = mode.phase
	if (phase == "Study" or phase == "Mess") and not memory.Plan then
		-- What this bot will remember.
		local recall = math.clamp(0.5 + 0.45 * bot.Skill + random:NextNumber(-0.06, 0.06), 0.4, 0.95)
		local plan = {}
		for toy, slot in mode.answer do
			local sure = random:NextNumber() < recall
			table.insert(plan, {
				Toy = toy,
				Slot = if sure then slot else neighbour(slot, random),
				Sure = sure,
			})
		end
		-- Sure toys first (in a shuffled order), the doubtful ones last.
		for index = #plan, 2, -1 do
			local other = random:NextInteger(1, index)
			plan[index], plan[other] = plan[other], plan[index]
		end
		table.sort(plan, function(a, b)
			return a.Sure and not b.Sure
		end)
		memory.Plan = plan
		memory.Next = 0
		memory.Seq = 0
		memory.Pace = 2.6 - 1.6 * bot.Skill -- seconds per toy
		memory.Peeker = random:NextNumber() < 0.55
	end
	if phase ~= "Place" or not memory.Plan then
		return
	end
	local booth = mode.booths[bot]
	if not booth or booth.Left then
		return
	end
	if memory.Next == 0 then
		memory.Next = now + 0.8 + bot:Reaction() + random:NextNumber(0, 1)
	end
	if now < memory.Next then
		return
	end
	local item = table.remove(memory.Plan, 1)
	if item then
		if not booth.Open then
			ctx:BotAction(bot, "Curtain", true)
		end
		if not item.Sure and memory.Peeker and random:NextNumber() < 0.6 and not item.Peeked then
			-- Not sure: have a look at a rival's shelf first, and trust it.
			local open = mode:OpenBooths(bot)
			if #open > 0 then
				local rival = open[random:NextInteger(1, #open)]
				ctx:BotAction(bot, "Peek", rival.Player.UserId)
				local seen = rival.Positions[item.Toy]
				if seen and Rules.IsSlot(seen) then
					item.Slot = seen
				end
				item.Peeked = true
				table.insert(memory.Plan, 1, item) -- place it after the look
				memory.Next = now + 1.8 + random:NextNumber(0, 1)
				return
			end
		end
		memory.Seq += 1
		ctx:BotAction(bot, "Move", memory.Seq, item.Toy, item.Slot)
		memory.Next = now + memory.Pace * random:NextNumber(0.7, 1.4)
		if #memory.Plan == 0 then
			memory.Next = now + random:NextNumber(1, 3)
		end
	elseif booth.Open and not memory.Shut then
		-- A toy bumped back onto the counter (two toys remembered in one slot): best guess, an empty slot.
		local taken = {}
		for _, pos in booth.Positions do
			taken[pos] = true
		end
		for toy, pos in booth.Positions do
			if not Rules.IsSlot(pos) then
				local empty = {}
				for slot = 1, Rules.SLOTS do
					if not taken[slot] then
						table.insert(empty, slot)
					end
				end
				if #empty > 0 then
					memory.Seq += 1
					ctx:BotAction(bot, "Move", memory.Seq, toy, empty[random:NextInteger(1, #empty)])
					memory.Next = now + memory.Pace * random:NextNumber(0.8, 1.4)
					return
				end
			end
		end
		memory.Shut = true
		ctx:BotAction(bot, "Curtain", false)
	end
end

return MessyMemory
