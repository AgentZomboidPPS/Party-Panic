-- How the crate seasons' pets move (Controllers/PetController builds and places them; owner: "For all
-- of these pets. They all have super cool animations right?"): each pet's whole-body move and each of
-- its piece groups' turns, now, from its own clock, its flourish's progress and how fast its owner is
-- running. Pure (CFrames and numbers), so tests/PetPoses.spec.luau checks it under Lune.
--
-- The groups are the meshes' named pieces (tools/meshgen/season/hollow_night_pets.py: WingL...,
-- Head..., LegFL...), each turning at its Hinge marker: a turn is in the model's space, about the
-- hinge, with the pet's front toward -Z and up +Y.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Seasons = require(ReplicatedStorage.Shared.Seasons)

local PetPoses = {}

-- A piece group: where it turns, and its parts.
export type Group = { Hinge: Vector3, Parts: { BasePart } }

export type Posed = {
	Info: Seasons.PetInfo,
	Height: number, -- its height (studs)
	Depth: number, -- half its length
	Run: number, -- 0 to 1: how fast its owner is moving
	Groups: { [string]: Group },
}

-- How long each pet's flourish lasts (seconds; others FLOURISH_TIME).
PetPoses.FLOURISH_TIME = 1.6
PetPoses.FLOURISH_TIMES = { Owl = 2.2, Stag = 2, Gourdian = 1.8, Tot = 1.8 } :: { [string]: number }
-- The pieces that move together, by their names' prefix (the meshes' groups).
local GROUPS = {
	"WingL",
	"WingR",
	"FistL",
	"FistR",
	"Tail",
	"Head",
	"Lantern",
	"EarL",
	"EarR",
	"LegFL",
	"LegFR",
	"LegBL",
	"LegBR",
	"Seed",
	"Roots",
	"Cap",
	"Ghost",
}
-- Groups that also move with another: the stag's ears with its head, the owl's lantern (it hangs
-- from its beak).
local PARENT_GROUP = { EarL = "Head", EarR = "Head", Lantern = "Head" }
PetPoses.GROUPS = GROUPS
PetPoses.PARENT_GROUP = PARENT_GROUP

-- The piece group a part of a pet moves with (by its name's prefix), or nil.
function PetPoses.GroupOf(name: string): string?
	for _, prefix in GROUPS do
		if string.sub(name, 1, #prefix) == prefix then
			return prefix
		end
	end
	return nil
end

-- 0 outside `from`..`to`, rising to 1 and back across it.
local function bump(t: number, from: number, to: number): number
	if t <= from or t >= to then
		return 0
	end
	return math.sin(math.pi * (t - from) / (to - from))
end

-- `rotation` about `point` (in the model's space).
local function about(point: Vector3, rotation: CFrame): CFrame
	return CFrame.new(point) * rotation * CFrame.new(-point)
end

-- The pet's whole-body move and each group's, now: `clock` its own time, `t` from 0 to 1 through
-- its flourish (nil: none). Angles: about X tips the front up (+) or down (-); a leg or the roots
-- swing forward (+) or back (-) about X; wings rise (+) about Z.
function PetPoses.Pose(pet: Posed, t: number?, clock: number): (CFrame, { [string]: CFrame })
	local kind = pet.Info.Flourish
	local body = CFrame.identity
	local turns: { [string]: CFrame } = {}
	local s = pet.Height / 3 -- (moves are in studs for a 3-stud pet)
	local wave = if t then math.sin(t * math.pi) else 0 -- 0 -> 1 -> 0 through the flourish
	local run = pet.Run
	local middle = Vector3.new(0, pet.Height / 2, 0)
	if kind == "Owl" then
		-- In flight: wingbeats (faster at a run), rising on each downstroke, leaning into it.
		local beat = clock * (5 + 3 * run)
		local flap = math.rad(14 + 6 * run) * math.sin(beat)
		local lift = -0.07 * s * math.sin(beat)
		local pitch = -math.rad(8) * run
		local swing = math.rad(5 + 6 * run) * math.sin(clock * 1.7)
		local tilt = math.rad(8) * math.sin(clock * 0.6)
		if t then
			-- The swoop: wings tucked, it dives and climbs, then flares them wide with big beats.
			local dive, climb = bump(t, 0, 0.45), bump(t, 0.35, 1)
			lift += s * (-1.2 * dive + 0.7 * climb)
			pitch += -math.rad(25) * dive + math.rad(12) * climb
			flap = flap * (1 - wave)
				+ math.rad(50) * bump(t, 0, 0.5)
				- math.rad(25) * bump(t, 0.4, 0.6)
				+ math.rad(32) * math.sin(t * math.pi * 6) * bump(t, 0.45, 1)
			swing += math.rad(30) * math.sin(t * math.pi * 3) * wave
			tilt += math.rad(14) * math.sin(t * math.pi * 2) * wave
		end
		body = CFrame.new(0, lift, 0) * about(middle, CFrame.Angles(pitch, 0, 0))
		turns.WingL = CFrame.Angles(0, 0, flap)
		turns.WingR = CFrame.Angles(0, 0, -flap)
		turns.Head = CFrame.Angles(0, 0, tilt)
		turns.Lantern = CFrame.Angles(swing, 0, math.rad(4) * math.sin(clock * 1.3))
		turns.Tail = CFrame.Angles(math.rad(6) * math.sin(beat + 1), 0, 0)
	elseif kind == "Stag" then
		-- It looks about and flicks its ears and tail; at a run it gallops (front and back legs in
		-- pairs, the body rocking).
		local gait = clock * 9
		local stride = math.rad(34) * run
		turns.LegFL = CFrame.Angles(stride * math.sin(gait), 0, 0)
		turns.LegFR = CFrame.Angles(stride * math.sin(gait + 0.7), 0, 0)
		turns.LegBL = CFrame.Angles(stride * math.sin(gait + math.pi), 0, 0)
		turns.LegBR = CFrame.Angles(stride * math.sin(gait + math.pi + 0.7), 0, 0)
		body = CFrame.new(0, 0.12 * s * run * math.abs(math.sin(gait)) + 0.015 * s * math.sin(clock * 1.5), 0)
			* about(middle, CFrame.Angles(math.rad(5) * run * math.sin(gait), 0, 0))
		local look = CFrame.Angles(
			math.rad(4) * math.sin(clock * 0.6) - math.rad(6) * run,
			math.rad(16) * math.sin(clock * 0.35) * (1 - run),
			0
		)
		local flickL = math.rad(30) * math.max(0, math.sin(clock * 1.9)) ^ 12
		local flickR = math.rad(30) * math.max(0, math.sin(clock * 1.7 + 2.1)) ^ 12
		turns.EarL = CFrame.Angles(0, -flickL, 0)
		turns.EarR = CFrame.Angles(0, flickR, 0)
		local tail = math.rad(25) * math.max(0, math.sin(clock * 1.3 + 1)) ^ 10 + math.rad(15) * run
		turns.Tail = CFrame.Angles(-tail, 0, math.rad(10) * math.sin(clock * 7) * math.min(1, tail * 3))
		if t then
			-- Rearing on its back hooves, pawing the air, tossing its antlers.
			local hinge = Vector3.new(0, 0, pet.Depth * 0.8) -- (its back legs: its front is -Z)
			body = about(hinge, CFrame.Angles(math.rad(32) * wave, 0, 0)) * body
			local paw = math.rad(25) * math.sin(t * math.pi * 8) * wave
			turns.LegFL = CFrame.Angles(math.rad(55) * wave + paw, 0, 0)
			turns.LegFR = CFrame.Angles(math.rad(55) * wave - paw, 0, 0)
			turns.LegBL = CFrame.Angles(-math.rad(12) * wave, 0, 0)
			turns.LegBR = CFrame.Angles(-math.rad(12) * wave, 0, 0)
			look = look * CFrame.Angles(math.rad(10) * wave + math.rad(18) * math.sin(t * math.pi * 4) * wave, 0, 0)
			turns.Tail = CFrame.Angles(-math.rad(35) * wave, 0, 0)
		end
		turns.Head = look
	elseif kind == "Gourdian" then
		-- Its fists swing, its head bobs, its roots sway; at a run it leans in, roots streaming.
		local beat = if t then math.sin(t * math.pi * 8) * wave else math.sin(clock * 2) * 0.15
		turns.FistL = CFrame.new(-0.25 * s * math.max(beat, 0), -0.35 * s * math.max(beat, 0), 0)
		turns.FistR = CFrame.new(0.25 * s * math.max(-beat, 0), -0.35 * s * math.max(-beat, 0), 0)
		turns.Seed = CFrame.Angles(0, clock * 0.6 + (if t then t * math.pi * 4 else 0), 0)
		local head = CFrame.Angles(
			math.rad(4) * math.sin(clock * 1.6),
			math.rad(10) * math.sin(clock * 0.7),
			math.rad(5) * math.sin(clock * 1.1)
		)
		turns.Roots = CFrame.Angles(
			-math.rad(28) * run + math.rad(6) * math.sin(clock * 1.8),
			0,
			math.rad(6) * math.sin(clock * 1.3)
		)
		body = about(middle, CFrame.Angles(-math.rad(10) * run, 0, 0))
		if t then
			-- Laughing: its head shakes, it bounces.
			head = head
				* CFrame.Angles(
					math.rad(10) * math.sin(t * math.pi * 10) * wave,
					math.rad(14) * math.sin(t * math.pi * 6) * wave,
					0
				)
			body = CFrame.new(0, 0.35 * s * math.abs(math.sin(t * math.pi * 2)) * wave, 0) * body
		end
		turns.Head = head
	elseif kind == "Tot" then
		-- It waddles (faster at a run), its cap wobbling a beat behind.
		local pace = clock * (2.4 + 5 * run)
		local waddle = math.rad(5 + 5 * run) * math.sin(pace)
		body = CFrame.new(0, 0.05 * s * math.abs(math.sin(pace)) * (0.4 + run), 0) * CFrame.Angles(0, 0, waddle)
		turns.Cap =
			CFrame.Angles(math.rad(3) * math.sin(pace - 0.8), 0, -waddle * 0.6 + math.rad(3) * math.sin(pace * 2))
		if t then
			-- A hop and a spin, the cap bouncing.
			local hop = math.abs(math.sin(t * math.pi * 2)) * (1 - t * 0.4)
			body = CFrame.new(0, 1.1 * s * hop, 0)
				* about(middle, CFrame.Angles(0, t * math.pi * 2, math.rad(8) * math.sin(t * math.pi * 4)))
			turns.Cap = CFrame.Angles(
				math.rad(12) * math.sin(t * math.pi * 6) * wave,
				0,
				math.rad(10) * math.sin(t * math.pi * 4) * wave
			)
		end
	elseif kind == "Wisp" then
		-- The ghost bobs and looks about inside its lantern, its smoky tail sways, the lantern swings
		-- from its ring; in its flourish the ghost spins round and the tail curls into a ring.
		local curl = if t then -math.rad(60) * wave else math.rad(6) * math.sin(clock * 1.3)
		turns.Tail = CFrame.Angles(curl, math.rad(8) * math.sin(clock * 0.9), 0)
		turns.Ghost = CFrame.new(0, 0.05 * s * math.sin(clock * 2) + (if t then 0.12 * s * wave else 0), 0)
			* CFrame.Angles(0, math.rad(15) * math.sin(clock * 0.8) + (if t then t * math.pi * 2 else 0), 0)
		local ring = pet.Groups.Tail
		if ring then
			local swing = math.rad(4 + 4 * run) * math.sin(clock * 1.2)
				+ (if t then math.rad(10) * math.sin(t * math.pi * 3) * wave else 0)
			body = about(ring.Hinge, CFrame.Angles(math.rad(3) * run, 0, swing))
		end
	end
	return body, turns
end

-- Each group's move in the model's space, now: its own turn about its hinge, after the move of the
-- group it hangs from (the stag's ears ride its head; the owl's lantern hangs from its beak).
function PetPoses.Moves(pet: Posed, turns: { [string]: CFrame }): { [string]: CFrame }
	local own: { [string]: CFrame } = {}
	for name, entry in pet.Groups do
		local turn = turns[name]
		if turn then
			own[name] = CFrame.new(entry.Hinge) * turn * CFrame.new(-entry.Hinge)
		end
	end
	local moves: { [string]: CFrame } = {}
	for name in pet.Groups do
		local parent = PARENT_GROUP[name]
		local parentMove = if parent then own[parent] else nil
		local move = own[name]
		if parentMove then
			moves[name] = parentMove * (move or CFrame.identity)
		elseif move then
			moves[name] = move
		end
	end
	return moves
end

return PetPoses
