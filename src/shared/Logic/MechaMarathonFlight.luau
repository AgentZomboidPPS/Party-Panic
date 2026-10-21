-- Mecha-Marathon's numbers and flight path, shared by the server (which counts the winds, works out
-- every flight and ends the round when the last toy lands), the clients (which fly the toys along
-- the very same path) and the bots (which mash at their own pace), so all of them agree on when and
-- where every toy comes down.
--
-- Distance: a toy flies BASE + PER_WIND * winds meters, plus its wobble. The wobble is under half a
-- wind's worth either way, so it only ever splits toys with the same number of winds: a clear lead
-- never flips. A meter is STUDS_PER_METER studs on the field.
--
-- Winding: the server counts at most RATE winds a second (a fast human drumming two fingers), with
-- up to BURST presses that arrive bunched together (network jitter) still counting. An auto-clicker
-- gets no more than that. Clients and bots use the same counter (Flight.Take), so the number a
-- player sees is the number the server counts.
--
-- The path: every toy leaves its pad at the same moment, speeds up to SPEED over ACCEL seconds and
-- cruises (so the pack flies side by side) until its spring runs down GLIDE studs short of its
-- landing spot; then it glides, slowing to LAND of its speed, and touches down exactly on the spot.

local Flight = {}

Flight.WIND_TIME = 10 -- seconds of winding, from GO
Flight.LAUNCH_DELAY = 1.6 -- from the end of the winding to lift-off (the "LAUNCH!" beat)
Flight.RATE = 12 -- the most winds counted per second
Flight.BURST = 8 -- presses that can arrive bunched together and still count
Flight.STUDS_PER_METER = 4
Flight.BASE = 2 -- meters a toy with no winds hops off its pad
Flight.PER_WIND = 0.6 -- meters per wind
Flight.WOBBLE = 0.25 -- most the flight's wobble moves a landing either way (m): under half a wind
Flight.SPEED = 28 -- cruise speed (studs/s)
Flight.ACCEL = 0.9 -- seconds from the pad to cruise speed
Flight.GLIDE = 30 -- studs a toy glides once its spring has run down
Flight.LAND = 0.35 -- share of its speed a toy has left when it touches down
Flight.HEIGHT = 12 -- cruise height over the field (studs)
Flight.PAD = 1.3 -- the launch pad's top over the field: where a toy starts from
Flight.MARKER = 10 -- meters between distance markers
Flight.MAX_WINDS = Flight.RATE * Flight.WIND_TIME + 1 -- a hard cap on top of the rate

export type Plan = {
	Distance: number, -- studs from the pad to the landing spot
	Power: number, -- seconds of powered flight
	Speed: number, -- speed when the spring runs down
	Glide: number, -- studs of glide
	GlideTime: number,
	Total: number, -- seconds from lift-off to touchdown
	TopHeight: number, -- height when the spring runs down
}

-- Meters flown for a number of winds and a wobble (-WOBBLE..WOBBLE), to the centimeter.
function Flight.Meters(winds: number, wobble: number): number
	local meters = Flight.BASE
		+ Flight.PER_WIND * math.max(winds, 0)
		+ math.clamp(wobble, -Flight.WOBBLE, Flight.WOBBLE)
	return math.floor(meters * 100 + 0.5) / 100
end

-- A press of WIND at `now` against a counter { Tokens, At }: true if it counts (and takes a token).
function Flight.Take(counter: { Tokens: number, At: number }, now: number): boolean
	local tokens = math.min(Flight.BURST, counter.Tokens + math.max(now - counter.At, 0) * Flight.RATE)
	counter.At = math.max(now, counter.At)
	if tokens < 1 then
		counter.Tokens = tokens
		return false
	end
	counter.Tokens = tokens - 1
	return true
end

local function heightAt(t: number): number
	return Flight.PAD + (Flight.HEIGHT - Flight.PAD) * (1 - math.exp(-t / 0.55))
end

function Flight.Plan(meters: number): Plan
	local distance = math.max(meters, 0.5) * Flight.STUDS_PER_METER
	local glide = math.min(Flight.GLIDE, distance * 0.6)
	local power = distance - glide
	local accel = Flight.SPEED / Flight.ACCEL
	local reach = Flight.SPEED * Flight.ACCEL / 2 -- distance covered while speeding up
	local powerTime, speed
	if power <= reach then
		powerTime = math.sqrt(2 * power / accel)
		speed = accel * powerTime
	else
		powerTime = Flight.ACCEL + (power - reach) / Flight.SPEED
		speed = Flight.SPEED
	end
	local glideTime = 2 * glide / (math.max(speed, 1) * (1 + Flight.LAND))
	return {
		Distance = distance,
		Power = powerTime,
		Speed = speed,
		Glide = glide,
		GlideTime = glideTime,
		Total = powerTime + glideTime,
		TopHeight = heightAt(powerTime),
	}
end

-- Where a toy is `t` seconds after lift-off: studs along its lane, height over the field, the stage
-- ("pad", "power", "glide" or "landed") and how far through that stage it is (0..1).
function Flight.At(plan: Plan, t: number): (number, number, string, number)
	if t <= 0 then
		return 0, Flight.PAD, "pad", 0
	end
	if t < plan.Power then
		local accelTime = math.min(t, Flight.ACCEL)
		local along = Flight.SPEED / Flight.ACCEL * accelTime * accelTime / 2
		if t > Flight.ACCEL then
			along += Flight.SPEED * (t - Flight.ACCEL)
		end
		return math.min(along, plan.Distance - plan.Glide), heightAt(t), "power", t / plan.Power
	end
	local glideT = t - plan.Power
	if glideT < plan.GlideTime then
		local u = glideT / plan.GlideTime
		local slowing = plan.Speed * (1 - Flight.LAND) / (2 * plan.GlideTime)
		local along = plan.Distance - plan.Glide + plan.Speed * glideT - slowing * glideT * glideT
		return along, plan.TopHeight * math.cos(u * math.pi / 2), "glide", u
	end
	return plan.Distance, 0, "landed", 1
end

return Flight
