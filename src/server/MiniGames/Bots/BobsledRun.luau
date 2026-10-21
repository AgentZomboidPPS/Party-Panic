-- How bots play Bobsled Run (contract in Bots/Default.luau). A bot rides in its crew's sled and,
-- as soon as the next curve's window opens (its cue shows: mode:_openCurve, the same moment a
-- player's screen switches to it), leans the curve's way after its own reaction time
-- (bot:Reaction(), quicker with skill), pressed through ctx:BotAction at that exact moment
-- (ctx:Delay), so the server judges it like any rider's press. Clumsier bots now and then
-- lean the wrong way, miss a curve or react too late; a skilled crew takes most curves clean, a
-- clumsy one bumps the wall a few times: good players can beat them.
--
-- Hazard parity: there's nothing a client animates that a bot could dodge. Wall bumps come from the
-- server's own judging of every crew's leans, and the server moves bots' characters with their sled.

local Brain = {}

function Brain.Step(bot, ctx, mode, _dt)
	local rider = mode.riders and mode.riders[bot]
	local sled = rider and mode.sleds[rider.Team]
	if not sled or sled.Place or sled.Gone or not mode.startAt then
		return
	end
	-- The curve whose window is open (from GO, then from just after the sled entered the last one).
	local index, openedAt = mode:_openCurve(sled, ctx:Now())
	local curve = mode.course.Curves[index]
	local memory = bot.Memory
	if not curve or memory.Planned == curve.Index or not openedAt then
		return
	end
	local secondsToCurve = (curve.D0 - sled.D) / math.max(sled.V, 1)
	memory.Planned = curve.Index
	local skill = bot.Skill
	local roll = bot.Rng:NextNumber()
	local miss = 0.18 * (1 - skill) + 0.05
	local wrong = miss + 0.14 * (1 - skill) + 0.05
	local late = wrong + 0.12 * (1 - skill) + 0.03
	if roll < miss then
		return -- didn't see it coming
	end
	local dir = curve.Dir
	-- Reads the cue, then presses (a little slower when the curve is still far off).
	local delay = bot:Reaction() * 0.9 + math.clamp(secondsToCurve - 2, 0, 1.5) * bot.Rng:NextNumber(0.2, 0.6)
	if roll < wrong then
		dir = -dir
	elseif roll < late then
		delay = secondsToCurve + 0.4 -- too late: the sled's already in the curve
	end
	delay = math.min(delay, secondsToCurve + 0.6)
	-- A press that comes after the curve's window closed is dropped: it mustn't count for the next.
	local function press(lean: number)
		if (mode:_openCurve(sled, ctx:Now())) == curve.Index and not sled.Place then
			ctx:BotAction(bot, "Lean", lean)
		end
	end
	ctx:Delay(math.max(0, delay), function()
		press(dir)
	end)
	-- A wrong lean is sometimes corrected in time.
	if dir ~= curve.Dir and bot:Chance(skill * 0.4) then
		ctx:Delay(math.max(0, delay + 0.25 + bot.Rng:NextNumber(0, 0.25)), function()
			press(curve.Dir)
		end)
	end
end

return Brain
