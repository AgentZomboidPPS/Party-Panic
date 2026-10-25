-- How bots play Sky Stack (the contract is in Bots/Default.luau): for every block that slides over
-- its tower a bot picks the moment it'll be over the middle (Logic/SkyStack.NextMiddle) and presses
-- DROP then, give or take its aim, through ctx:BotAction with that moment as the press time, so the
-- server judges it exactly like a player's press (same rules, same READY window).
--
-- Bots stay beatable (owner: "dont make bots overpowered"): a bot's timing is off by a random amount
-- (about 0.06 s for the best, 0.08 s for the weakest, which is more studs off as the blocks speed
-- up), so its tower narrows like a person's does and most crumble on the way up; slower bots can't
-- react to the first pass on the higher floors and wait for the next one; and a bot often hesitates
-- for a pass (a fifth to a third of the time). A steady player who taps on the first pass beats
-- most of them. Measured with the round harness: see the numbers in the round's notes.
-- Nothing in this mode can hurt anyone, so there's no hazard to dodge. Bots hop for joy at the top.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Stack = require(ReplicatedStorage.Shared.Logic.SkyStack)

local SkyStackBrain = {}

local SKILL = 0.8 -- how much of a bot's Skill counts here
local BEST_AIM = 0.04 -- seconds off, typically, for a perfect bot...
local WORST_AIM = 0.1 -- ...and for the weakest

-- A normally distributed number (Box-Muller), mean 0 and spread 1.
local function gauss(rng: Random): number
	local u = math.max(rng:NextNumber(), 1e-6)
	return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * rng:NextNumber())
end

function SkyStackBrain.Step(bot, ctx, mode, _dt)
	local memory = bot.Memory
	local tower = mode.towers and mode.towers[bot]
	if not tower then
		return
	end
	if tower.Place and not memory.Cheered then
		memory.Cheered = true
		bot:Jump()
		return
	end
	local slide = tower.Slide
	if mode.phase ~= "Stack" or not slide or tower.Out or memory.Planned == slide then
		return
	end
	memory.Planned = slide
	local now = ctx:Now()
	local skill = bot.Skill * SKILL
	-- The first pass over the middle it can react to (or, hesitating, the one after).
	local earliest = math.max(now, slide.Start) + bot:Reaction() * 0.7
	earliest = math.max(earliest, slide.Start + Stack.READY + 0.05)
	local target = Stack.NextMiddle(slide, earliest)
	if bot:Chance(0.1 + 0.3 * (1 - skill)) then
		target = Stack.NextMiddle(slide, target + 0.01)
	end
	local aim = BEST_AIM + (WORST_AIM - BEST_AIM) * (1 - skill)
	local press = target + gauss(bot.Rng) * aim
	if not Stack.Counts(slide, press) then
		press = target
	end
	ctx:Delay(math.max(press - now, 0), function()
		if tower.Slide == slide then
			ctx:BotAction(bot, "Drop", press, slide.Level)
		end
	end)
end

return SkyStackBrain
