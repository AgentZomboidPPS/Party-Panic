-- How bots play Prime Cut (contract in Bots/Default.luau). A bot sizes up each steak and settles on
-- where it thinks the middle is: the true 50:50 line (mode.steak.Even) plus its own misjudgement,
-- wider for clumsier bots (about 8% of the steak for the clumsiest, 1% for the best). Once the knives
-- unlock it takes a moment to think, then nudges the knife towards its mark through ctx:BotAction,
-- exactly like a player's ◀ ▶ (a few notches at a time, a bit slower than a held button), and stops
-- when it's close enough for its eye. Two bots who disagree pull against each other for a while,
-- then meet halfway. A bot never fights a person: once a person on its team has steered this steak,
-- it leaves the knife to them.
--
-- Hazard parity: nothing here is animated only on clients. Every team's knife is the server's, the
-- cut is judged there, and bots' characters stand at their grills like everyone's.

local BotRegistry = require(script.Parent.Parent.Parent.Services.BotRegistry)
local PrimeCutLogic = require(game:GetService("ReplicatedStorage").Shared.Logic.PrimeCut)

local Brain = {}

-- A normally distributed number (Box-Muller).
local function gaussian(rng: Random): number
	local u = math.max(rng:NextNumber(), 1e-6)
	return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * rng:NextNumber())
end

function Brain.Step(bot, ctx, mode, _dt)
	local member = mode.members and mode.members[bot]
	local station = member and mode.stations[member.Team]
	local steak = mode.steak
	if not station or not steak or mode.phase ~= "Steer" or mode.locked then
		return
	end
	local now = ctx:Now()
	local memory = bot.Memory
	local skill = bot.Skill
	if memory.Cut ~= mode.cut then
		-- A new steak: size it up.
		memory.Cut = mode.cut
		local width = steak.Hi - steak.Lo - 2 * PrimeCutLogic.MARGIN
		local spread = width * (0.085 - 0.075 * math.clamp((skill - 0.35) / 0.55, 0, 1))
		memory.Mark = steak.Even + gaussian(bot.Rng) * spread
		memory.Tolerance = 0.06 + (1 - skill) * 0.16
		memory.StartAt = now + bot:Reaction() + bot.Rng:NextNumber(0.2, 1.1) * (1.4 - skill)
		memory.Tug = 0
		memory.LastX = station.X
	end
	if now < memory.StartAt or now > mode.closeAt - 0.25 then
		return
	end
	-- People steer; bots help only crews of bots (and people who haven't touched it yet).
	for _, player in station.Members do
		local other = mode.members[player]
		if other and other.Nudges > 0 and not BotRegistry.IsBot(player) and other.DirAt >= mode.openAt then
			return
		end
	end
	local gap = memory.Mark - station.X
	-- Pulling against a teammate (pushing, but the knife isn't coming): meet them halfway.
	if math.abs(station.X - memory.LastX) < PrimeCutLogic.STEP * 0.5 and memory.Pushed then
		memory.Tug += 1
		if memory.Tug >= 8 then
			memory.Mark = (memory.Mark + station.X) / 2
			memory.Tug = 0
		end
	else
		memory.Tug = 0
	end
	memory.LastX = station.X
	memory.Pushed = false
	if math.abs(gap) <= memory.Tolerance then
		return
	end
	-- Now and then it pauses to look again (more often when it's nearly there).
	if bot:Chance(if math.abs(gap) < 0.6 then 0.25 else 0.08) then
		return
	end
	local count = math.clamp(math.floor(math.abs(gap) / PrimeCutLogic.STEP + 0.5), 1, if skill > 0.6 then 3 else 2)
	memory.Seq = (memory.Seq or 0) + 1
	memory.Pushed = true
	ctx:BotAction(bot, "Nudge", if gap > 0 then 1 else -1, count, memory.Seq, now)
end

return Brain
