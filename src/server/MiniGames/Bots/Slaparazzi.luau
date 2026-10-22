-- How bots play Slaparazzi (contract in Bots/Default.luau). They slap through ctx:BotAction like a
-- player's client (the same range, facing and cooldown checks), turning to face their target
-- first; a slapped bot is thrown by ctx:Knockback like a player and lies still until it gets up.
--
-- Owner: "Bots are terrible at slaparazzi". They were. They followed the frame as it glided
-- instead of heading for the NEXT disc everyone sees at the flash, so they got to each new spot
-- late. All of them aimed for the same point, so the whole field stood inside each other in one
-- heap (nobody bumps anybody in this mode). And they slapped at random moments: most slaps came
-- long before the flash, when a thrown rival still had time to walk back. Their Skill barely
-- showed, the wrong way round if anything. Now they play like decent players, some better than
-- others:
--
-- A bot takes in the NEXT disc a reaction after the flash (a quick human's, by Skill) and heads
-- straight for the new spot. Like everyone it wants the gold middle, but it never stands inside
-- someone: whoever gets to a spot first keeps it, the gold ring fills up shoulder to shoulder and
-- the rest take spots of their own in the silver ring (or the bronze), so the crowd spreads across
-- the rings instead of piling up on one point. It looks again now and then, more often as the
-- flash nears, and steps into a gold spot as soon as one is free (someone slapped out of it):
-- jostling for the middle. It SLAPs only in the last couple of seconds before the flash, when a
-- thrown rival can't get back in time, and not every photo: someone in reach who'd be in the photo
-- (mostly whoever is near, the gold middle a little more often, now and then the leader), a
-- reaction after they come into reach, and a skilled bot maybe again right at the end. Sloppy bots
-- slap less and misjudge the moment more. Thrown, it gets up and runs straight back (round the
-- backdrop wall if it landed behind it). Skill shows in its reactions, how close to its spot it
-- ends up, how evenly it judges spots and how often and how well it times its slaps.
--
-- Measured in simulated 8-player rounds (7 bots and one person; this brain, the mode's rules, a
-- slap's throw of about 24 studs; tools/checks/bots/Slaparazzi.luau plays the same throw out on a
-- test server): bots reach the next middle 1.6 s after the flash (was 2.6), score 2.3 points a
-- photo among themselves with 75% in the gold ring at the flash (was 2.1 and 66%), about 0.1
-- pairs of bodies overlap a photo (was 5.4) and every slap comes in the last 2.5 s (was 42%). Bots
-- with more Skill score more (15.2 / 16.4 / 16.9 points a round from low to high; was 15.0 / 14.5 /
-- 14.1). They stay beatable: a person who heads for the NEXT disc, takes a gold spot with room and
-- slaps a rival in the gold or silver ring in the last 2 s wins 30% of rounds (one in eight would
-- be an even match; it was 48% against the old bots), and one who always stands in the very
-- middle wins 14% (was 12%).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Logic.Slaparazzi)

local Brain = {}

local WALK = 16 -- studs a second
local DOWN_GRACE = 0.4 -- (MiniGames/Slaparazzi) someone thrown can't be slapped until this long after getting up
local REACH = Rules.CLIENT_REACH - 0.5 -- bots slap from a little nearer than a player's button offers
local BODY = 2.2 -- bodies nearer than this stand shoulder to shoulder...
local CROWD = 1.5 -- ...which puts a bot off a spot this much at most (a ring further out costs 1)...
local INSIDE = 1.3 -- ...and nearer than this they'd stand inside each other, which it never picks
local MOVING = 0.3 -- a rival who went this far since its last look is on the move (no one's spot yet)
local HURRY = 0.15 -- a second of walking to a spot costs this much
local STICK = 0.3 -- the spot it's already headed for counts this much more
local NEAR = 0.25 -- a slap goes to a rival who'd be in the photo, nearer ones (this much less per stud)...
local GOLD = 0.3 -- ...and ones in the gold middle (this much more) a little more often...
local PICKY = 1.5 -- ...give or take up to this much (nobody picks perfectly)
-- How Skill shows (each pair goes from Skill 0 to Skill 1):
local AIM = { 1.2, 0.3 } -- how far from its spot it may end up (studs)
local TASTE = { 0.5, 0 } -- how unevenly it judges spots
local REPLAN = { 1.2, 0.5 } -- seconds between looks at where to stand (less than half that near the flash)
local WINDOW = { 1.8, 2.4 } -- it slaps from this long before the flash...
local WINDOW_SLOP = { 0.9, 0.2 } -- ...give or take this much (a fresh guess each photo)
local FIGHT = { 0.1, 0.35 } -- chance it slaps at all for a photo (once; more is a free-for-all)...
local AGAIN = 1 -- ...and, by Skill, again if someone's still in reach this long before the flash
local LEADER = { 0, 0.3 } -- how much more it wants to slap the leader
-- In reaction times (Bot:Reaction(), by Skill):
local NOTICE = 1 -- after the flash, to take in the NEXT disc
local GET_UP = 0.6 -- after getting up, to see where it landed
local SEE = 1.3 -- after a rival worth slapping comes into reach

-- Where in the frame a bot may stand: the middle and spots on circles round it (the gold ring's
-- edge is 3.6 out, the silver's 7.2, the bronze's 11).
local SPOTS = { Vector2.new(0, 0) }
for _, circle in { { 1.6, 6 }, { 2.9, 10 }, { 5.3, 12 }, { 8.8, 14 } } do
	for index = 1, circle[2] do
		local angle = (index - 0.5) / circle[2] * math.pi * 2
		table.insert(SPOTS, Vector2.new(math.cos(angle), math.sin(angle)) * circle[1])
	end
end

type Rival = { Player: any, At: Vector2, Down: boolean, Moving: boolean }

local function lerp(pair: { number }, skill: number): number
	return pair[1] + (pair[2] - pair[1]) * skill
end

local function flat(v: Vector3): Vector2
	return Vector2.new(v.X, v.Z)
end

-- Where this bot should stand at the flash, of SPOTS round `center`: the best ring it can reach in
-- time where it doesn't stand inside anyone (see the top).
local function pickSpot(bot, memory, me: Vector2, center: Vector2, rivals: { Rival }, left: number): Vector2
	local aim = lerp(AIM, bot.Skill)
	local best, bestValue = memory.Spot or center, -math.huge
	for index, offset in SPOTS do
		local spot = center + offset
		local stand = spot + memory.Aim -- where it would really end up
		local walk = (stand - me).Magnitude / WALK
		local points = Rules.PointsFor(offset.Magnitude + aim)
		local mine = memory.Spot ~= nil and (memory.Spot - spot).Magnitude < 0.1
		if (walk > left - 0.15 and not mine) or points == 0 then
			continue -- out of the shot, or no time to get there
		end
		local crowd = 0
		for _, rival in rivals do
			local distance = (rival.At - stand).Magnitude
			if distance < BODY and not rival.Down and not rival.Moving then
				crowd += if distance < INSIDE then 3 else 1 - distance / BODY
			end
		end
		local value = points - crowd * CROWD - walk * HURRY + memory.Taste[index] + (if mine then STICK else 0)
		if value > bestValue then
			best, bestValue = spot, value
		end
	end
	return best
end

-- The way from `from` to `to` round the backdrop wall behind the stage, if the straight line runs
-- into it: along it to past its nearer end, then round the end.
local function aroundWall(wall: BasePart?, from: Vector2, to: Vector2): Vector2
	if not wall then
		return to
	end
	local frame = wall.CFrame
	local a = frame:PointToObjectSpace(Vector3.new(from.X, frame.Position.Y, from.Y))
	local b = frame:PointToObjectSpace(Vector3.new(to.X, frame.Position.Y, to.Y))
	local halfX, halfZ = wall.Size.X / 2 + 1.5, wall.Size.Z / 2 + 1 -- with room for a body
	if math.sign(a.Z) == math.sign(b.Z) then
		return to -- both on the same side of it
	end
	local x = a.X + (b.X - a.X) * a.Z / (a.Z - b.Z)
	if math.abs(x) > halfX then
		return to -- the line passes its end
	end
	local side = if x >= 0 then 1 else -1
	local past = math.abs(a.X) > halfX + 1 -- already beside the end: round it to the other side
	local corner = frame:PointToWorldSpace(
		Vector3.new(side * (halfX + 2), 0, math.sign(a.Z) * (if past then -1 else 1) * (halfZ + 1.5))
	)
	return Vector2.new(corner.X, corner.Z)
end

function Brain.Step(bot, ctx, mode, _dt)
	local root = bot:Root()
	local frame = mode.frame
	if not root or not frame then
		return
	end
	local memory = bot.Memory
	local now = ctx:Now()
	local skill = bot.Skill

	-- Thrown: it lies there until it gets up, then takes a moment to see where it landed.
	local downUntil = mode.stunnedUntil[bot] or 0
	if downUntil > now then
		if memory.DownUntil ~= downUntil then
			memory.DownUntil = downUntil
			memory.UpAt = downUntil + bot:Reaction() * GET_UP
			memory.Spot = nil
			memory.SlapAt = nil
		end
		bot:Stop()
		return
	end
	if frame.Done or now < (memory.UpAt or 0) then
		bot:Stop()
		return
	end

	-- A new photo: everyone's NEXT disc shows the frame's next spot from the flash on; the bot takes
	-- it in a reaction later. Before that it stays where the last photo was taken.
	if memory.Shot ~= frame.Shot then
		memory.Shot = frame.Shot
		memory.NoticeAt = now + bot:Reaction() * NOTICE
		memory.Spot = nil
		memory.SlapAt = nil
		memory.Window = lerp(WINDOW, skill) + bot.Rng:NextNumber(-1, 1) * lerp(WINDOW_SLOP, skill)
		memory.Slaps = if bot:Chance(lerp(FIGHT, skill)) then 1 + (if bot:Chance(skill) then 1 else 0) else 0
		memory.Slapped = 0
		local angle = bot.Rng:NextNumber(0, math.pi * 2)
		memory.Aim = Vector2.new(math.cos(angle), math.sin(angle)) * bot.Rng:NextNumber(0, lerp(AIM, skill))
		memory.Taste = {}
		local taste = lerp(TASTE, skill)
		for index = 1, #SPOTS do
			memory.Taste[index] = bot.Rng:NextNumber(-taste, taste)
		end
	end
	if now < memory.NoticeAt then
		bot:Stop()
		return
	end

	local me = flat(root.Position)
	local center = Vector2.new(frame.X1, frame.Z1)
	local left = frame.Shot - now
	local rivals: { Rival } = {}
	local seen = memory.Seen or {}
	memory.Seen = seen
	for _, other in ctx:GetAlivePlayers() do
		local _, _, otherRoot = ctx:GetCharacter(other)
		if other ~= bot and otherRoot and math.abs(otherRoot.Position.Y - root.Position.Y) <= 5 then
			local at = flat(otherRoot.Position)
			local last = seen[other]
			seen[other] = at
			table.insert(rivals, {
				Player = other,
				At = at,
				Down = (mode.stunnedUntil[other] or 0) + DOWN_GRACE > now,
				Moving = last ~= nil and (at - last).Magnitude > MOVING,
			})
		end
	end

	-- Where to stand, looked at again now and then (more often as the flash nears), and at once if
	-- someone else is standing on its spot before it gets there (whoever is there first keeps it).
	local stand = if memory.Spot then memory.Spot + memory.Aim else nil
	local taken = false
	if stand and (stand - me).Magnitude > 0.6 then
		for _, rival in rivals do
			if not rival.Down and not rival.Moving and (rival.At - stand).Magnitude < INSIDE then
				taken = true
			end
		end
	end
	if not memory.Spot or now >= (memory.ReplanAt or 0) or taken then
		memory.ReplanAt = now + lerp(REPLAN, skill) * (if left < WINDOW[2] then 0.4 else 1)
		memory.Spot = pickSpot(bot, memory, me, center, rivals, left)
	end
	local goal = aroundWall(mode.backdrop, me, memory.Spot + memory.Aim)
	if (goal - me).Magnitude > 0.6 then
		bot:MoveTo(Vector3.new(goal.X, root.Position.Y, goal.Y))
	else
		bot:Stop()
	end

	-- SLAP, only in the last moments before the flash (see the top).
	local opens = if memory.Slapped == 0 then memory.Window else AGAIN
	if memory.Slapped >= memory.Slaps or left > opens or left < 0.05 or now < (mode.readyAt[bot] or 0) then
		memory.SlapAt = nil
		return
	end
	local myPoints = mode.points[bot] or 0
	local best = 0
	for _, rival in rivals do
		best = math.max(best, mode.points[rival.Player] or 0)
	end
	local pick, pickScore = nil, -math.huge
	for _, rival in rivals do
		local distance = (rival.At - me).Magnitude
		local worth = Rules.PointsFor((rival.At - center).Magnitude)
		if rival.Down or distance > REACH or worth < (if left < AGAIN then 1 else 2) then
			continue
		end
		local points = mode.points[rival.Player] or 0
		local score = (if worth == 3 then GOLD else 0) - distance * NEAR + bot.Rng:NextNumber(0, PICKY)
		if points >= best and points > myPoints then
			score += lerp(LEADER, skill) * bot.Rng:NextNumber()
		end
		if score > pickScore then
			pick, pickScore = rival, score
		end
	end
	if not pick then
		memory.SlapAt = nil
		return
	end
	if not memory.SlapAt then
		memory.SlapAt = now + bot:Reaction() * SEE
		return
	end
	if now < memory.SlapAt then
		return
	end
	memory.SlapAt = nil
	memory.Slapped += 1
	if (pick.At - me).Magnitude > 0.1 then
		root.CFrame = CFrame.lookAt(root.Position, Vector3.new(pick.At.X, root.Position.Y, pick.At.Y))
	end
	ctx:BotAction(bot, "Slap", pick.Player.UserId)
end

return Brain
