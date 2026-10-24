-- How bots play Last Dancer (contract in Bots/Default.luau). A bot reads the same chart as everybody
-- (LastDancerChart) and, a few notes ahead, decides for each one whether it hits it and how far off the
-- beat; it taps through ctx:BotAction exactly like a client's tap, so the server judges it by the same
-- rules (a wrong lane is a stray that costs groove for a bot too, and a note it skips is a miss).
--
-- Skill (0.35-0.9) sets how many notes it hits (a sharp bot ~95%, a clumsy one ~83%, a little less as the
-- chart gets busier), how far off the beat it taps (a sharp bot ~35 ms, a clumsy one ~70 ms) and how
-- often it taps the wrong pad. Now and then a bot loses the beat for a bar and hits almost nothing, so
-- the cuts aren't the same every round and a dancer with a bad stretch can be the one that falls.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Chart = require(ReplicatedStorage.Shared.LastDancerChart)
local Logic = require(ReplicatedStorage.Shared.Logic.LastDancer)

local LastDancerBrain = {}

local AHEAD = 0.4 -- plans notes this far ahead (seconds)
local LAPSE_CHANCE = 0.012 -- per note: loses the beat
local LAPSE_LENGTH = 2 -- seconds

local function gauss(rng: Random, sigma: number): number
	local u, v = math.max(rng:NextNumber(), 1e-6), rng:NextNumber()
	return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v) * sigma
end

function LastDancerBrain.Step(bot, ctx, mode, _dt)
	local memory = bot.Memory
	if not mode.go then
		return
	end
	memory.Next = memory.Next or 1
	memory.LapseUntil = memory.LapseUntil or -1
	local notes = Chart.Notes
	local now = ctx:Now()
	local rel = now - mode.go
	local skill = bot.Skill
	while memory.Next <= #notes and notes[memory.Next].T < rel + AHEAD do
		local note = notes[memory.Next]
		memory.Next += 1
		if note.T < rel - Logic.WINDOW.Ok then
			continue -- (a bot that joined late, or a slow step)
		end
		if bot:Chance(LAPSE_CHANCE) then
			memory.LapseUntil = note.T + LAPSE_LENGTH
		end
		local difficulty = (Logic.PhraseAt(note.T) - 1) / (Logic.PHRASES - 1)
		local hit = 0.8 + 0.17 * skill - 0.12 * difficulty * (1 - skill)
		if note.T < memory.LapseUntil then
			hit = 0.12
		end
		local lane = note.Lane
		if bot:Chance(hit) then
			local sigma = 0.095 - 0.065 * skill
			local offset = math.clamp(gauss(bot.Rng, sigma) + 0.008, -0.15, 0.15)
			if bot:Chance((1 - skill) * 0.04) then
				lane = (lane + bot.Rng:NextInteger(0, 1) * 2) % Logic.LANES + 1 -- a neighbouring pad
			end
			local wait = mode.go + note.T + offset - ctx:Now()
			ctx:Delay(math.max(0, wait), function()
				ctx:BotAction(bot, "Tap", lane)
			end)
		elseif bot:Chance(0.3) then
			-- a flailing tap in the wrong place, around the time of the note it missed
			lane = lane % Logic.LANES + 1
			local wait = mode.go + note.T + bot.Rng:NextNumber(-0.1, 0.1) - ctx:Now()
			ctx:Delay(math.max(0, wait), function()
				ctx:BotAction(bot, "Tap", lane)
			end)
		end
	end
end

return LastDancerBrain
