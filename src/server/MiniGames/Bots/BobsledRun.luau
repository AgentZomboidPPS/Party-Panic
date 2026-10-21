-- How bots play Bobsled Run (contract in Bots/Default.luau). A bot rides in its crew's sled and,
-- for each curve, waits for the lean window to open, then leans the curve's way after its own
-- reaction time (bot:Reaction(), quicker with skill), pressed through ctx:BotAction at that exact
-- moment (ctx:Delay), so the server judges it like any rider's press. Clumsier bots now and then
-- lean the wrong way, miss a curve or react too late; a skilled crew takes most curves clean, a
-- clumsy one bumps the wall a few times: good players can beat them.
--
-- Hazard parity: there's nothing a client animates that a bot could dodge. Wall bumps come from the
-- server's own judging of every crew's leans, and the server moves bots' characters with their sled.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BobsledCourse = require(ReplicatedStorage.Shared.Logic.BobsledCourse)

local Brain = {}

function Brain.Step(bot, ctx, mode, _dt)
	local rider = mode.riders and mode.riders[bot]
	local sled = rider and mode.sleds[rider.Team]
	if not sled or sled.Place or sled.Gone or not mode.startAt then
		return
	end
	local curve = mode.course.Curves[sled.Next]
	local memory = bot.Memory
	if not curve or memory.Planned == curve.Index then
		return
	end
	-- Wait for the window (leaning earlier wouldn't count).
	local secondsToCurve = (curve.D0 - sled.D) / math.max(sled.V, 1)
	if secondsToCurve > BobsledCourse.OPEN then
		return
	end
	memory.Planned = curve.Index
	local skill = bot.Skill
	local roll = bot.Rng:NextNumber()
	local miss = 0.1 * (1 - skill) + 0.02
	local wrong = miss + 0.1 * (1 - skill) + 0.02
	local late = wrong + 0.08 * (1 - skill)
	if roll < miss then
		return -- didn't see it coming
	end
	local dir = curve.Dir
	local delay = bot:Reaction() * 0.9
	if roll < wrong then
		dir = -dir
	elseif roll < late then
		delay = secondsToCurve + 0.4 -- too late: the sled's already in the curve
	end
	delay = math.min(delay, secondsToCurve + 0.6)
	ctx:Delay(math.max(0, delay), function()
		ctx:BotAction(bot, "Lean", dir)
	end)
	-- A wrong lean is sometimes corrected in time.
	if dir ~= curve.Dir and bot:Chance(skill * 0.6) then
		ctx:Delay(math.max(0, delay + 0.25 + bot.Rng:NextNumber(0, 0.25)), function()
			ctx:BotAction(bot, "Lean", curve.Dir)
		end)
	end
end

return Brain
