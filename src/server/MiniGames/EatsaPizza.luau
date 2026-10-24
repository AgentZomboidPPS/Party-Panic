-- Eatsa Pizza (Team, 30s, 2-12 players). After "Eatsa Pizza" (Mario Party 3, 2 vs 2): two teams stand
-- on a pizza the size of a swimming pool and race to eat their half by mashing the button; the
-- pepperoni bits take extra chewing, and when the slice under you is gone you walk to the next one.
-- First team to clear its part wins; at time up the team that ate the biggest share wins.
--
-- Here 2-4 teams (Teams.CountFor, about two a team) share one giant pizza on a pizzeria rooftop. It
-- is cut in twelve slices and each team owns a run of them (its flag stands at the rim). Each slice
-- takes a number of bites (more with more pepperoni on it), shrinks in four stages as it's eaten
-- (the crust first, then bitten back towards the tip) and disappears when it's gone. Bigger teams
-- get the same slices with more bites in them (PER_PLAYER bites per player), so every team needs the
-- same chewing per player; when someone leaves, their team's pizza shrinks to match.
--
-- BITE SPOTS (owner: "eatza pizza is better. can we make players run around while eating instead of
-- just sitting on the slice?"): you don't chew wherever you stand. Glowing spots light up on each
-- team's slices, one per player of the team; stand on one of your team's and mash EAT (E) to eat it
-- (about six bites, each one a bite of the slice under it), and when it's eaten it pops and a new one
-- lights up about a second's run away (SPOT_RUN from whoever ate it, away from the team's other
-- spots), so a round is run, chomp, run, chomp. Pressing EAT off a spot does nothing. Spots only go
-- where there's food for all their bites (each claims its bites from its slice, and sits inside what
-- the slice will still be when they're eaten: Shared/Logic/EatsaPizza.PlaceSpot), so the last spots
-- of a part are near its slices' tips, and a team that has eaten everything has none.
--
-- How it works: the server owns every slice and spot ("Pizza": the layout, once; "Slices": the bites
-- left; "Spots": where each spot is and the bites left in it, shared about ten times a second while
-- they change, and at once when spots come and go) and swaps a slice's model as it reaches a new
-- stage. A client sends "Eat" per press; the server caps the rate (a token bucket, RATE a second)
-- and finds the spot under the player's character with Logic.OnSpot (the ring and a bit, and the
-- spot they stood on a moment ago still counting for their ping, so a bite pressed as you step off
-- still lands). Team scores are the share eaten, in percent.
--
-- More to do than mash (owner: "can we make the eatsa pizza game more interactable? In mario party it
-- feels and plays a ton better."):
--   * THE HOT PEPPER: now and then a chili lands where two teams' parts meet ("Chili": where, and
--     until when). The first to reach it is SPICY for a few seconds ("Spicy" to everyone): each press
--     eats two bites. One at a time; one nobody grabs goes.
--   * Pepperoni go one at a time as the bites reach them (Logic.Front), each one flying into the
--     eater's mouth on every screen ("Pep"), instead of a stage's worth vanishing at once.
-- Clients add the rest (the spots' rings and markers, chomping heads, combos, the crunch):
-- Client/MiniGames/EatsaPizza.
--
-- Bots run from spot to spot of their team (the nearest one no teammate is eating) and mash through
-- ctx:BotAction like a player's button (Bots/EatsaPizza.luau). Nothing here is animated only on
-- clients: the slices and spots are the server's, and everybody stands on the same pan.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Logic = require(ReplicatedStorage.Shared.Logic.EatsaPizza)
local Teams = require(ReplicatedStorage.Shared.Teams)

local MiniGame = require(script.Parent.Kit.MiniGame)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local EatsaPizza = MiniGame.Define("EatsaPizza", { Results = "Team" })

EatsaPizza.Logic = Logic -- (for the round harness's test bot)
EatsaPizza.Shapes = { Red = "■", Blue = "●", Green = "▲", Yellow = "◆" }

local FINALE = 3 -- after a team clears its part, before the round ends
local CHILI_FLOAT = 2.6 -- studs the hot pepper floats over the cheese (about a character's middle)
local PAN_RIM = 20.7 -- the pan floor's radius, in slice-mesh units (the pizza is 20)

local rng = Random.new()

type Slice = {
	Index: number,
	Team: string?,
	Max: number,
	Left: number,
	Stage: number,
	Pepperoni: { { Rho: number, Phi: number, Model: Model?, Eaten: boolean? } },
	Model: Model?,
}
type Member = {
	Player: any,
	Team: string,
	Tokens: number,
	TokensAt: number,
	Bites: number,
	Spot: number?, -- the spot (Id) they last stood on...
	SpotAt: number, -- ...and when
	SpicyUntil: number, -- the hot pepper's double bites last until then
}
-- A bite spot: where (offset from the pizza's middle, and on the cheese in the world), on which of
-- its team's slices, and its bites (claimed from that slice).
type Spot = {
	Id: number,
	Team: string,
	Slice: number,
	X: number,
	Z: number,
	Position: Vector3,
	Left: number,
	Bites: number,
}
type Chili = { Position: Vector3, Until: number, Model: Model }
type TeamState = {
	Name: string,
	Members: { any },
	Size: number, -- players the pizza is sized for
	Slices: { number },
	Shown: number, -- the team score shown (percent)
	Gone: boolean?,
	ClearedAt: number?,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function round(x: number, step: number): number
	return math.floor(x / step + 0.5) * step
end

local function ping(player: any): number
	if BotRegistry.IsBot(player) then
		return 0
	end
	local ok, value = pcall(function()
		return player:GetNetworkPing()
	end)
	return if ok and type(value) == "number" then math.clamp(value, 0, 0.5) else 0.15
end

local function label(team: string): string
	return `{EatsaPizza.Shapes[team] or ""} {string.upper(team)}`
end

-- Arena -------------------------------------------------------------------------------------------

-- A copy of a prop scaled by `scale` (kept as this round's own template; clones never yield).
local function scaledTemplate(name: string, scale: number): (Model, number)
	local model = MeshLibrary.Get(name)
	if math.abs(scale - 1) > 1e-3 then
		model:ScaleTo(model:GetScale() * scale)
	end
	local _, size = model:GetBoundingBox()
	return model, size.Z
end

function EatsaPizza:_buildArena()
	local ctx = self.context
	local arena = ctx.Arena
	local c = self.center
	local R = self.radius
	local scale = self.scale
	local floorY = c.Y - 0.6
	local H = math.max(R + 32, 60) -- half the roof's width

	-- The pan (the floor everyone stands on: a plain, visible part), its rolled rim, the roof.
	local panRadius = PAN_RIM * scale
	Build.Part({
		Name = "Pan",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, panRadius * 2, panRadius * 2),
		CFrame = CFrame.new(c + Vector3.new(0, -0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = rgb(176, 180, 190),
		Material = Enum.Material.Metal,
		Parent = arena,
	})
	local rim = MeshLibrary.Get("EatsaPizzaPan")
	rim:ScaleTo(rim:GetScale() * scale)
	rim:PivotTo(CFrame.new(c))
	rim.Parent = arena

	Build.Part({
		Name = "Roof",
		Size = Vector3.new(H * 2, 2, H * 2),
		CFrame = CFrame.new(c.X, floorY - 1, c.Z),
		Color = rgb(196, 184, 170),
		Material = Enum.Material.Concrete,
		Parent = arena,
	})
	-- Tar seams across the roof (flat strips just over it).
	-- (They stop short of the pan and of the teams' arcs round it.)
	local clear = 22.2 * scale + 3
	for k = -3, 3 do
		local z = k * (H / 3.5)
		local gap = if math.abs(z) < clear then math.sqrt(clear * clear - z * z) else 0
		for _, side in (if gap > 0 then { -1, 1 } else { 0 }) :: { number } do
			local from, to = if side == 0 then -(H - 2) else gap, H - 2
			if to - from < 1 then
				continue
			end
			Build.Decor({
				Name = "Seam",
				Size = Vector3.new(to - from, 0.06, 0.5),
				CFrame = CFrame.new(c.X + (if side == 0 then 0 else side * (from + to) / 2), floorY + 0.08, c.Z + z),
				Color = rgb(150, 140, 130),
				Material = Enum.Material.Concrete,
				Parent = arena,
			})
		end
	end
	Build.Decor({
		Name = "Building",
		Size = Vector3.new(H * 2, 160, H * 2),
		CFrame = CFrame.new(c.X, floorY - 2 - 80, c.Z),
		Color = rgb(168, 82, 62),
		Material = Enum.Material.Brick,
		Parent = arena,
	})
	-- The parapet round the roof.
	for _, side in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local x, z = side[1], side[2]
		local size = if x ~= 0 then Vector3.new(2, 4, H * 2 - 3.4) else Vector3.new(H * 2 + 2, 4, 2)
		local position = Vector3.new(c.X + x * H, floorY + 2, c.Z + z * H)
		Build.Part({
			Name = "Parapet",
			Size = size,
			CFrame = CFrame.new(position),
			Color = rgb(176, 86, 64),
			Material = Enum.Material.Brick,
			Parent = arena,
		})
		Build.Part({
			Name = "Coping",
			Size = size + Vector3.new(0.6, -3.6, 0.6),
			CFrame = CFrame.new(position + Vector3.new(0, 2.2, 0)),
			Color = rgb(214, 206, 196),
			Material = Enum.Material.Concrete,
			Parent = arena,
		})
	end

	local function place(name: string, position: Vector3, facing: Vector3?, options: any?)
		local opts = options or {}
		local at = Vector3.new(position.X, floorY, position.Z)
		local frame = if facing
			then CFrame.lookAt(at, Vector3.new(facing.X, floorY, facing.Z))
			else CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		return MeshLibrary.Get(name, {
			CFrame = frame * CFrame.Angles(0, opts.Turn or 0, 0),
			Scale = opts.Scale,
			Colors = opts.Colors,
			Parent = arena,
		})
	end

	-- Behind the pizza: the brick oven and the big sign on the parapet.
	place("EatsaPizzaOven", c + Vector3.new(0, 0, -(R + 17)), c, { Scale = 1.15 })
	local sign = place("EatsaPizzaSign", c + Vector3.new(0, 0, -(H - 4)), c, { Scale = 1.5 })
	local board = Build.Decor({
		Name = "SignText",
		Size = Vector3.new(42, 11.2, 0.1),
		CFrame = sign:GetPivot() * CFrame.new(0, 12.5 * 1.5, -0.62 * 1.5),
		Transparency = 1,
		Parent = arena,
	})
	Build.SurfaceText(board, Enum.NormalId.Front, "EATSA PIZZA!", {
		PixelsPerStud = 10,
		TextColor3 = rgb(255, 240, 200),
		TextStrokeTransparency = 0.2,
		Brightness = 1.4,
		MaxDistance = 600,
	})

	-- Boxes, air conditioners, a giant cutter and lamps round the roof (outside the pan).
	local ring = R + 9
	local boxSpots = {
		{ -1, -0.55 },
		{ 1, -0.6 },
		{ -1.05, 0.5 },
		{ 1.0, 0.45 },
		{ -0.3, 1.05 },
		{ 0.45, 1.0 },
	}
	for index, spot in boxSpots do
		local p = c + Vector3.new(spot[1], 0, spot[2]).Unit * (ring + 4 + (index % 3) * 3)
		place("EatsaPizzaBoxes", p, nil, { Scale = 1.4 })
		if index % 2 == 0 then
			place(
				"EatsaPizzaBoxes",
				p + Vector3.new(rng:NextNumber(-6, 6), 0, rng:NextNumber(5, 8)),
				nil,
				{ Scale = 1.2 }
			)
		end
	end
	place("EatsaPizzaVent", c + Vector3.new(-(H - 9), 0, H - 10), c, { Scale = 1.6 })
	place("EatsaPizzaVent", c + Vector3.new(H - 9, 0, H - 11), c, { Scale = 1.6 })
	place("EatsaPizzaVent", c + Vector3.new(H - 9, 0, -(H - 12)), c, { Scale = 1.6 })
	place("EatsaPizzaCutter", c + Vector3.new(-(H - 8), 0, -(H - 22)), c + Vector3.new(-(H - 8), 0, 0), {
		Scale = 1.6,
		Turn = math.pi / 2,
	})
	for _, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		place("LampPost", c + Vector3.new(corner[1] * (H - 5), 0, corner[2] * (H - 5)), c)
	end

	-- Each team's flags at its part of the rim, and a glowing arc on the roof round it.
	local rimOut = 22.2 * scale
	for _, team in self.order do
		local state = self.teams[team]
		local color = Teams.Colors[team]
		local first, last = state.Slices[1], state.Slices[#state.Slices]
		local a0 = Logic.Angle(first) - Logic.SLICE_ANGLE / 2
		local a1 = Logic.Angle(last) + Logic.SLICE_ANGLE / 2
		local middle = (a0 + a1) / 2
		for _, a in { a0 + 0.06, middle, a1 - 0.06 } do
			local p = c + Vector3.new(math.sin(a), 0, math.cos(a)) * (rimOut + 1.2)
			local stick = MeshLibrary.Get("EatsaPizzaFlag", {
				Colors = { Flag = color },
				Scale = 1.3,
				CFrame = CFrame.new(Vector3.new(p.X, floorY, p.Z)) * CFrame.Angles(0, a + math.pi / 2, 0),
				Parent = arena,
			})
			if a == middle then
				local anchor = Build.Decor({
					Name = "TeamLabel",
					Size = Vector3.new(0.2, 0.2, 0.2),
					CFrame = stick:GetPivot() + Vector3.new(0, 10.5, 0),
					Transparency = 1,
					Parent = arena,
				})
				Build.Billboard(anchor, label(team), {
					Size = UDim2.fromOffset(170, 44),
					StudsOffset = Vector3.new(0, 1.5, 0),
					MaxDistance = 220,
					TextColor3 = color,
				})
			end
		end
		local steps = math.max(4, math.floor((a1 - a0) * rimOut / 3))
		for k = 0, steps - 1 do
			local t0 = a0 + (a1 - a0) * (k + 0.12) / steps
			local t1 = a0 + (a1 - a0) * (k + 0.88) / steps
			local a = (t0 + t1) / 2
			local r = rimOut + 0.9
			local p = c + Vector3.new(math.sin(a), 0, math.cos(a)) * r
			Build.Decor({
				Name = "TeamArc",
				Size = Vector3.new((t1 - t0) * r, 0.1, 1.1),
				CFrame = CFrame.lookAt(Vector3.new(p.X, floorY + 0.25, p.Z), Vector3.new(c.X, floorY + 0.25, c.Z)),
				Color = color,
				Material = Enum.Material.Neon,
				Parent = arena,
			})
		end
	end

	-- The city round the building (far off, nothing solid).
	local windows = rgb(255, 226, 150)
	for index = 1, 18 do
		local a = (index / 18) * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
		local distance = H + rng:NextNumber(40, 110)
		local width = rng:NextNumber(26, 46)
		local height = rng:NextNumber(70, 200)
		local p = c + Vector3.new(math.sin(a), 0, math.cos(a)) * distance
		local base = floorY - 160 - index * 0.7
		local frame = CFrame.lookAt(Vector3.new(p.X, base + height / 2, p.Z), Vector3.new(c.X, base + height / 2, c.Z))
		local tone = ({ rgb(120, 130, 150), rgb(160, 120, 100), rgb(190, 180, 160), rgb(100, 110, 130) })[index % 4 + 1]
		Build.Decor({
			Name = "City",
			Size = Vector3.new(width, height, width),
			CFrame = frame,
			Color = tone,
			Material = Enum.Material.Concrete,
			Parent = arena,
		})
		for row = 1, math.floor(height / 12) do
			Build.Decor({
				Name = "Windows",
				Size = Vector3.new(width - 6, 2.2, 0.2),
				CFrame = frame * CFrame.new(0, -height / 2 + row * 12 - 4, -width / 2 - 0.1),
				Color = windows,
				Material = Enum.Material.Glass,
				Parent = arena,
			})
		end
	end

	-- A little warm haze from the oven's chimney (ambient: off with reduced effects).
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(rgb(235, 235, 235))
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 7) })
	smoke.Lifetime = NumberRange.new(3, 5)
	smoke.Speed = NumberRange.new(3, 5)
	smoke.SpreadAngle = Vector2.new(10, 10)
	smoke.Rate = 4
	local chimney = Build.Decor({
		Name = "Chimney",
		Size = Vector3.new(1, 0.2, 1),
		CFrame = CFrame.new(c + Vector3.new(0, 13.3 * 1.15 - 0.6, -(R + 17) + 2 * 1.15 * -1)),
		Transparency = 1,
		Parent = arena,
	})
	smoke.Parent = chimney
	CollectionService:AddTag(smoke, "PP_Ambient")
end

-- Slices -------------------------------------------------------------------------------------------

function EatsaPizza:_tipFrame(index: number): CFrame
	local c = self.center
	return CFrame.lookAt(c, c + Logic.Direction(index))
end

-- Puts a slice's model for its stage on the pan, and only the pepperoni still in front of its bites.
function EatsaPizza:_drawSlice(slice: Slice)
	if slice.Model then
		slice.Model:Destroy()
		slice.Model = nil
	end
	if slice.Left <= 0 then
		for _, pep in slice.Pepperoni do
			if pep.Model then
				pep.Model:Destroy()
				pep.Model = nil
			end
		end
		return
	end
	local template = self.sliceTemplates[slice.Stage + 1]
	local model = template.Model:Clone()
	model.Name = `Slice_{slice.Index}`
	model:PivotTo(self:_tipFrame(slice.Index) * CFrame.new(0, 0, -template.Reach / 2))
	model.Parent = self.pizza
	slice.Model = model
	local reach = Logic.Reach(slice.Stage, self.radius) - (if slice.Stage > 0 then self.radius * 0.1 + 1 else 1.5)
	local top = self.center.Y + Logic.MESH_CHEESE * self.scale - 0.03
	for k, pep in slice.Pepperoni do
		local r = pep.Rho * self.radius
		if r + 1.1 * self.scale > reach then
			if pep.Model then
				pep.Model:Destroy()
				pep.Model = nil
			end
		elseif not pep.Model and not pep.Eaten then
			local a = Logic.Angle(slice.Index) + pep.Phi * Logic.SLICE_ANGLE * 0.36
			local p = Vector3.new(self.center.X + math.sin(a) * r, top, self.center.Z + math.cos(a) * r)
			local copy = self.pepperoniTemplate:Clone()
			copy.Name = `Pepperoni_{slice.Index}_{k}`
			copy:PivotTo(CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0))
			copy.Parent = self.pizza
			pep.Model = copy
		end
	end
end

-- Each team's part gets the same slices (the same pepperoni counts, shuffled), PER_PLAYER bites for
-- each of its players spread over them by size.
function EatsaPizza:_sizeTeam(state: TeamState)
	local weights, total = {}, 0
	for _, index in state.Slices do
		local slice = self.slices[index]
		local weight = 1 + #slice.Pepperoni * Logic.PEPPERONI_WEIGHT
		weights[index] = weight
		total += weight
	end
	local bites = Logic.PER_PLAYER * math.max(state.Size, 1)
	for _, index in state.Slices do
		local slice = self.slices[index]
		slice.Max = math.max(4, math.floor(bites * weights[index] / total + 0.5))
		slice.Left = slice.Max
	end
end

function EatsaPizza:_teamShare(team: string): number
	local state = self.teams[team]
	local left, max = 0, 0
	for _, index in state.Slices do
		local slice = self.slices[index]
		left += slice.Left
		max += slice.Max
	end
	return if max > 0 then 1 - left / max else 0
end

-- Round -------------------------------------------------------------------------------------------

function EatsaPizza:_standAt(player: any): CFrame?
	local member = self.members[player]
	local state = member and self.teams[member.Team]
	if not state then
		return nil
	end
	-- (On a slice with food left, spread out: the k-th player of the team on the k-th one.)
	local open = {}
	for _, index in state.Slices do
		if self.slices[index].Left > 0 then
			table.insert(open, index)
		end
	end
	if #open == 0 then
		open = state.Slices
	end
	local k = table.find(state.Members, player) or 1
	local index = open[(k - 1) % #open + 1]
	local lap = math.floor((k - 1) / #open)
	local side = if lap == 0 then 0 elseif lap % 2 == 1 then -1 else 1
	local slice = self.slices[index]
	local spot = self.center + Logic.StandSpot(index, slice.Stage, self.radius, side)
	return CFrame.lookAt(spot, Vector3.new(self.center.X, spot.Y, self.center.Z))
end

function EatsaPizza:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Respawn"
	ctx.EndWhenOneLeft = false
	local origin = ctx.Origin.Position
	ctx.KillY = origin.Y - 40
	self.center = origin
	self.phase = "Wait"
	self.spots = {} :: { Spot }
	self.spotCount = 0

	local players = ctx:GetPlayers()
	local names = {}
	for index = 1, math.min(Teams.CountFor(#players, 2), math.max(#players, 1)) do
		table.insert(names, Teams.Order[index])
	end
	self.order = names
	self.radius = Logic.Radius(#players)
	self.scale = self.radius / Logic.MESH_RADIUS
	self.cheeseY = self.center.Y + Logic.MESH_CHEESE * self.scale
	local assigned = ctx:AssignTeams(names)
	self.teams = {} :: { [string]: TeamState }
	self.members = {} :: { [any]: Member }
	for _, team in names do
		local members = assigned[team] or {}
		self.teams[team] = { Name = team, Members = members, Size = #members, Slices = {}, Shown = 0 }
		for _, player in members do
			self.members[player] = {
				Player = player,
				Team = team,
				Tokens = Logic.BURST,
				TokensAt = 0,
				Bites = 0,
				Spot = nil,
				SpotAt = -math.huge,
				SpicyUntil = 0,
			}
		end
	end

	-- The slices: owners, pepperoni (the same counts for every team), bites.
	local per = Logic.PerTeam(#names)
	local counts = {}
	for k = 1, per do
		counts[k] = ({ 1, 2, 3, 4, 2, 3 })[(k - 1) % 6 + 1] + rng:NextInteger(0, 1)
	end
	self.slices = {} :: { [number]: Slice }
	for index = 1, Logic.SLICES do
		local owner = Logic.Owner(names, index)
		self.slices[index] = {
			Index = index,
			Team = owner,
			Max = 0,
			Left = 1,
			Stage = 0,
			Pepperoni = {},
		}
		if owner then
			table.insert(self.teams[owner].Slices, index)
		end
	end
	for _, team in names do
		local state = self.teams[team]
		local shuffled = table.clone(counts)
		for k = #shuffled, 2, -1 do
			local other = rng:NextInteger(1, k)
			shuffled[k], shuffled[other] = shuffled[other], shuffled[k]
		end
		for k, index in state.Slices do
			self:_scatter(self.slices[index], shuffled[k] or 2)
		end
		self:_sizeTeam(state)
	end
	for index, slice in self.slices do
		if not slice.Team then
			self:_scatter(slice, rng:NextInteger(1, 4)) -- (nobody's slices, in a solo test)
			slice.Max = 1
			slice.Left = 1
		end
		slice.Index = index
	end

	-- This round's slice and pepperoni templates, scaled to the pizza (loaded now, so a new stage
	-- never waits on a mesh).
	self.sliceTemplates = {}
	for stage, name in Logic.STAGES do
		local model, reach = scaledTemplate(name, self.scale)
		self.sliceTemplates[stage] = { Model = model, Reach = reach }
	end
	self.pepperoniTemplate = scaledTemplate("EatsaPizzaPepperoni", self.scale * 1.15)

	self:_buildArena()
	self.pizza = Build.Model("Pizza", ctx.Arena)
	for _, slice in self.slices do
		self:_drawSlice(slice)
	end

	ctx.Hooks.Respawn = function(player)
		return self:_standAt(player)
	end
	ctx.Hooks.PlayerLeft = function(player)
		self:_leave(player)
	end
	local points, from = {}, {}
	for _, player in ctx:GetPlayers() do
		local point = self:_standAt(player) or CFrame.new(self.center + Vector3.new(0, 0, self.radius * 0.5))
		table.insert(points, point)
		from[player] = point.Position
	end
	-- The first spots, one for each player, each about a run from one of the team's spawn points (so
	-- at GO everyone has the same dash to make).
	for _, team in names do
		local state = self.teams[team]
		for _, player in state.Members do
			if self:_countSpots(team) < self:_spotTarget(state) then
				self:_addSpot(state, from[player])
			end
		end
	end
	self:_shareLayout()
	self:_shareSlices()
	self:_shareSpots()
	ctx:SpawnAll(points, true)
	ctx:SetStatus("Run to your team's spots and EAT!")
end

-- Scatters `count` pepperoni over a slice (spots as shares of the radius and of its width).
function EatsaPizza:_scatter(slice: Slice, count: number)
	local spots = {}
	local tries = 0
	while #spots < count and tries < 200 do
		tries += 1
		local rho = rng:NextNumber(0.22, 0.86)
		local phi = rng:NextNumber(-1, 1) * math.clamp((rho - 0.12) * 1.6, 0.2, 1)
		local ok = true
		for _, other in spots do
			local dr = (rho - other.Rho) * 20
			local dp = (phi - other.Phi) * rho * 20 * Logic.SLICE_ANGLE * 0.36
			if dr * dr + dp * dp < 2.6 * 2.6 then
				ok = false
				break
			end
		end
		if ok then
			table.insert(spots, { Rho = rho, Phi = phi })
		end
	end
	slice.Pepperoni = spots
end

function EatsaPizza:_leave(player: any)
	local member = self.members[player]
	self.members[player] = nil
	local state = member and self.teams[member.Team]
	if not state then
		return
	end
	local index = table.find(state.Members, player)
	if index then
		table.remove(state.Members, index)
	end
	if #state.Members == 0 then
		state.Gone = true
		self:_fixSpots(state)
	elseif not state.ClearedAt and state.Size > 1 then
		-- Their part shrinks to fit the players left (what's eaten stays eaten, as a share).
		local factor = (state.Size - 1) / state.Size
		state.Size -= 1
		for _, sliceIndex in state.Slices do
			local slice = self.slices[sliceIndex]
			local hadFood = slice.Left > 0
			slice.Max = math.max(1, math.floor(slice.Max * factor + 0.5))
			slice.Left = math.clamp(math.floor(slice.Left * factor + 0.5), if hadFood then 1 else 0, slice.Max)
			-- (A slice only ever gets smaller: rounding must never grow it back a stage.)
			local stage = math.max(slice.Stage, Logic.Stage(slice.Left, slice.Max))
			if stage ~= slice.Stage then
				slice.Stage = stage
				self:_drawSlice(slice)
			end
		end
		self:_updateScore(state)
		-- (Its spots: one fewer, none claiming more than their slice now has, all still on the food.)
		self:_fixSpots(state)
	end
	self:_shareLayout()
	self.dirty = true
	if self.phase == "Eat" then
		self:_checkUnopposed()
	end
end

-- Every rival left: the team still here wins.
function EatsaPizza:_checkUnopposed()
	if #self.order < 2 then
		return
	end
	local left = {}
	for _, team in self.order do
		if not self.teams[team].Gone then
			table.insert(left, team)
		end
	end
	if #left == 1 then
		self:_finish(left[1], "Unopposed")
	end
end

function EatsaPizza:Start()
	local ctx = self.context
	for player in table.clone(self.members) do
		if not ctx:State(player) then
			self:_leave(player)
		end
	end
	self.phase = "Eat"
	self:_shareLayout()
	-- (A whole team may have gone before GO.)
	self:_checkUnopposed()
	if self.phase ~= "Eat" then
		return
	end

	ctx:OnAction("Eat", function(player)
		self:_bite(player)
	end, { Interval = 0 })
	self.chili = nil :: Chili?
	self.chiliCount = 0
	self.chiliFirst = rng:NextInteger(0, math.max(#self.order, 1) - 1) -- (which border goes first)
	self.chiliNext = ctx:Now() + Logic.CHILI_FIRST

	-- Where everyone stands, ten times a second (a bite pressed just after stepping off a spot still
	-- counts for the player's ping); a team short of spots (there was no room a moment ago) gets them.
	ctx:Loop(function()
		local now = ctx:Now()
		for player, member in self.members do
			local spot = self:_spotUnder(player)
			if spot then
				member.Spot = spot.Id
				member.SpotAt = now
			end
		end
		if self.phase == "Eat" then
			self:_stepChili(now)
			for _, team in self.order do
				self:_fillSpots(self.teams[team], nil)
			end
		end
		return 0.1
	end)
	local lastShare = 0
	ctx:Heartbeat(function()
		local now = ctx:Now()
		-- (Bites left: ten times a second at most. A spot that pops or lights up: at once.)
		if self.spotsChanged or (self.dirty and now - lastShare >= 0.1) then
			lastShare = now
			self.dirty = false
			self:_shareSlices()
			self:_shareSpots()
		end
	end)
end

-- Bite spots ---------------------------------------------------------------------------------------

-- How many spots a team has out at a time: one for each of its players (none once it's done).
function EatsaPizza:_spotTarget(state: TeamState): number
	if self.phase == "Done" or state.Gone or state.ClearedAt then
		return 0
	end
	return Logic.SpotsFor(#state.Members)
end

function EatsaPizza:_countSpots(team: string): number
	local count = 0
	for _, spot in self.spots do
		if spot.Team == team then
			count += 1
		end
	end
	return count
end

function EatsaPizza:_spotById(id: number?): Spot?
	if not id then
		return nil
	end
	for _, spot in self.spots do
		if spot.Id == id then
			return spot
		end
	end
	return nil
end

-- Lights up a new spot on the team's part (Logic.PlaceSpot: about a run from `from`, the eater of the
-- last one, if given). nil when there's no food left to claim, or no room just now.
function EatsaPizza:_addSpot(state: TeamState, from: Vector3?): Spot?
	local infos = {}
	for _, spot in self.spots do
		table.insert(
			infos,
			{ Slice = spot.Slice, X = spot.X, Z = spot.Z, Left = spot.Left, Mine = spot.Team == state.Name }
		)
	end
	local slices = {}
	for _, index in state.Slices do
		local slice = self.slices[index]
		table.insert(slices, { Index = index, Left = slice.Left, Max = slice.Max, Stage = slice.Stage })
	end
	local c = self.center
	local placed = Logic.PlaceSpot(
		slices,
		infos,
		self.radius,
		if from then { X = from.X - c.X, Z = from.Z - c.Z } else nil,
		function()
			return rng:NextNumber()
		end
	)
	if not placed then
		return nil
	end
	self.spotCount += 1
	local spot: Spot = {
		Id = self.spotCount,
		Team = state.Name,
		Slice = placed.Slice,
		X = placed.X,
		Z = placed.Z,
		Position = Vector3.new(c.X + placed.X, self.cheeseY, c.Z + placed.Z),
		Left = placed.Bites,
		Bites = placed.Bites,
	}
	table.insert(self.spots, spot)
	self.spotsChanged = true
	return spot
end

-- Tops the team up to its spots (the first new one about a run from `from`).
function EatsaPizza:_fillSpots(state: TeamState, from: Vector3?)
	local have, target = self:_countSpots(state.Name), self:_spotTarget(state)
	while have < target do
		if not self:_addSpot(state, from) then
			break
		end
		have += 1
		from = nil
	end
end

function EatsaPizza:_removeSpot(spot: Spot)
	local index = table.find(self.spots, spot)
	if index then
		table.remove(self.spots, index)
		self.spotsChanged = true
	end
end

-- A spot eaten (by `eater`): it goes and the team's next one lights up about a run from them.
function EatsaPizza:_popSpot(spot: Spot, eater: any?)
	self:_removeSpot(spot)
	local state = self.teams[spot.Team]
	if not state then
		return
	end
	local from = spot.Position
	if eater then
		local _, _, root = self.context:GetCharacter(eater)
		if root then
			from = root.Position
		end
	end
	self:_fillSpots(state, from)
end

-- Puts a team's spots right after its part changed under them (someone left: the slices shrank and
-- there's a spot too many): none claims more than its slice has left (the newest give theirs up
-- first), none is left off the food, the extra ones go (ones nobody is eating first), then the team
-- is topped up.
function EatsaPizza:_fixSpots(state: TeamState)
	for _, index in state.Slices do
		local slice = self.slices[index]
		local on, claimed = {}, 0
		for _, spot in self.spots do
			if spot.Team == state.Name and spot.Slice == index then
				table.insert(on, spot)
				claimed += spot.Left
			end
		end
		table.sort(on, function(a, b)
			return a.Id > b.Id
		end)
		local outer = Logic.SpotOuter(slice.Stage, self.radius) + 0.5
		for _, spot in on do
			if claimed > slice.Left then
				local cut = math.min(spot.Left, claimed - slice.Left)
				spot.Left -= cut
				claimed -= cut
				self.dirty = true
			end
			if spot.Left <= 0 or math.sqrt(spot.X * spot.X + spot.Z * spot.Z) > outer then
				claimed -= spot.Left
				self:_removeSpot(spot)
			end
		end
	end
	local target = self:_spotTarget(state)
	local now = self.context:Now()
	while self:_countSpots(state.Name) > target do
		local worst, worstCost = nil, math.huge
		for _, spot in self.spots do
			if spot.Team == state.Name then
				local cost = spot.Id * 1e-6
				for _, member in self.members do
					if member.Spot == spot.Id and now - member.SpotAt < 0.6 then
						cost += 1
					end
				end
				if cost < worstCost then
					worst, worstCost = spot, cost
				end
			end
		end
		if not worst then
			break
		end
		self:_removeSpot(worst)
	end
	self:_fillSpots(state, nil)
end

-- The spot of their own team a player stands on, if any.
function EatsaPizza:_spotUnder(player: any): Spot?
	local member = self.members[player]
	if not member then
		return nil
	end
	local _, _, root = self.context:GetCharacter(player)
	if not root then
		return nil
	end
	local offset = root.Position - self.center
	if offset.Y < -2 or offset.Y > 9 then
		return nil
	end
	local mine = {}
	for _, spot in self.spots do
		if spot.Team == member.Team then
			table.insert(mine, spot)
		end
	end
	local index = Logic.OnSpot(offset.X, offset.Z, mine)
	return if index then mine[index] else nil
end

function EatsaPizza:_shareSpots()
	local list = {}
	for _, spot in self.spots do
		table.insert(list, {
			I = spot.Id,
			T = spot.Team,
			X = round(spot.X, 0.01),
			Z = round(spot.Z, 0.01),
			L = spot.Left,
			M = spot.Bites,
		})
	end
	self.spotsChanged = false
	self.context:SetSharedJSON("Spots", { S = list })
end

function EatsaPizza:_clearSpots()
	if self.spots and #self.spots > 0 then
		table.clear(self.spots)
		self:_shareSpots()
	end
end

-- Eating -------------------------------------------------------------------------------------------

function EatsaPizza:_bite(player: any)
	local member = self.members[player]
	if self.phase ~= "Eat" or not member then
		return
	end
	local ctx = self.context
	local now = ctx:Now()
	member.Tokens = math.min(Logic.BURST, member.Tokens + (now - member.TokensAt) * Logic.RATE)
	member.TokensAt = now
	if member.Tokens < 1 then
		return
	end
	-- (Off every spot of their team: nothing, unless they stood on one a ping ago.)
	local spot = self:_spotUnder(player)
	if not spot and member.Spot and now - member.SpotAt <= ping(player) + 0.25 then
		local recent = self:_spotById(member.Spot)
		if recent and recent.Team == member.Team then
			spot = recent
		end
	end
	if not spot then
		return
	end
	local index = spot.Slice
	local slice = self.slices[index]
	-- (Two bites a press while the hot pepper lasts.)
	local bites = math.min(if now < member.SpicyUntil then Logic.SPICY_BITES else 1, spot.Left, slice.Left)
	if bites <= 0 then
		self:_popSpot(spot, player) -- (nothing left in it: never happens, but it mustn't stick)
		return
	end
	member.Tokens -= 1
	member.Bites += bites
	member.Spot = spot.Id
	member.SpotAt = now
	slice.Left -= bites
	spot.Left -= bites
	ctx:AddScore(player, bites)
	self.dirty = true
	self:_eatPepperoni(slice, player)
	local stage = if slice.Left > 0 then Logic.Stage(slice.Left, slice.Max) else slice.Stage
	if slice.Left <= 0 then
		self:_drawSlice(slice)
		ctx:Fire(nil, "SliceGone", index)
	elseif stage ~= slice.Stage then
		slice.Stage = stage
		self:_drawSlice(slice)
	end
	local state = self.teams[member.Team]
	self:_updateScore(state)
	if self:_teamShare(member.Team) >= 1 - 1e-9 then
		self:_finish(member.Team, "Cleared")
	elseif spot.Left <= 0 or slice.Left <= 0 then
		self:_popSpot(spot, player)
	end
end

-- The pepperoni the bites on `slice` have reached: off the pizza, flying into `player`'s mouth on
-- every screen.
function EatsaPizza:_eatPepperoni(slice: Slice, player: any)
	local front = Logic.Front(slice.Left, slice.Max) * self.radius
	for k, pep in slice.Pepperoni do
		local model = pep.Model
		if model and pep.Rho * self.radius + 0.6 * self.scale > front then
			local p = model:GetPivot().Position
			pep.Model = nil
			pep.Eaten = true
			model:Destroy()
			self.context:Fire(
				nil,
				"Pep",
				slice.Index,
				k,
				round(p.X, 0.01),
				round(p.Y, 0.01),
				round(p.Z, 0.01),
				player.UserId
			)
		end
	end
end

-- The hot pepper -----------------------------------------------------------------------------------

-- A chili (made of parts: no mesh to wait on), floating over the pizza; clients turn and bob it.
function EatsaPizza:_chiliModel(position: Vector3): Model
	local model = Build.Model("Chili")
	local base = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(-20))
	local function blob(name: string, size: Vector3, offset: CFrame, color: Color3, scale: Vector3)
		local part = Build.Decor({
			Name = name,
			Size = size,
			CFrame = base * offset,
			Color = color,
			Parent = model,
		})
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = scale
		mesh.Parent = part
		return part
	end
	local red = rgb(235, 36, 30)
	local body = blob("Body", Vector3.new(1.5, 1.5, 3.4), CFrame.new(), red, Vector3.new(1, 1, 1))
	blob(
		"Tip",
		Vector3.new(0.9, 0.9, 1.8),
		CFrame.new(0, -0.35, 1.7) * CFrame.Angles(math.rad(28), 0, 0),
		red,
		Vector3.one
	)
	blob("Shine", Vector3.new(0.35, 0.35, 1.6), CFrame.new(-0.45, 0.5, -0.2), rgb(255, 170, 160), Vector3.one)
	Build.Decor({
		Name = "Cap",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.35, 1.1, 1.1),
		CFrame = base * CFrame.new(0, 0, -1.65) * CFrame.Angles(0, math.rad(90), 0),
		Color = rgb(60, 170, 60),
		Parent = model,
	})
	Build.Decor({
		Name = "Stem",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.9, 0.3, 0.3),
		CFrame = base * CFrame.new(0, 0.25, -2.1) * CFrame.Angles(math.rad(30), math.rad(90), 0),
		Color = rgb(40, 130, 50),
		Parent = model,
	})
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 120, 60)
	light.Range = 12
	light.Brightness = 2.5
	light.Parent = body
	model.PrimaryPart = body
	model.WorldPivot = CFrame.new(position)
	model.Parent = self.context.Arena
	return model
end

function EatsaPizza:_shareChili()
	local chili = self.chili
	self.context:SetSharedJSON(
		"Chili",
		if chili
			then {
				P = { round(chili.Position.X, 0.01), round(chili.Position.Y, 0.01), round(chili.Position.Z, 0.01) },
				U = round(chili.Until, 0.01),
			}
			else {}
	)
end

function EatsaPizza:_removeChili()
	if self.chili then
		self.chili.Model:Destroy()
		self.chili = nil
		self:_shareChili()
	end
end

-- Ten times a second: a chili lands when it's due, goes when nobody took it in time, and goes to the
-- first one of the eaters to reach it.
function EatsaPizza:_stepChili(now: number)
	local chili = self.chili
	if not chili then
		if now >= self.chiliNext then
			self.chiliCount += 1
			local x, z = Logic.ChiliSpot(self.chiliCount, #self.order, self.radius, self.chiliFirst)
			local top = self.center.Y + Logic.MESH_CHEESE * self.scale
			local position = Vector3.new(self.center.X + x, top + CHILI_FLOAT, self.center.Z + z)
			self.chili = { Position = position, Until = now + Logic.CHILI_LIFE, Model = self:_chiliModel(position) }
			self:_shareChili()
			self.context:Sound("Pickup")
		end
		return
	end
	if now >= chili.Until then
		self:_removeChili()
		self.chiliNext = now + Logic.CHILI_EVERY
		return
	end
	local best, bestDistance = nil, Logic.CHILI_REACH
	for player, member in self.members do
		local _, _, root = self.context:GetCharacter(player)
		if root and self.context:State(player) then
			local offset = root.Position - chili.Position
			local flat = math.sqrt(offset.X * offset.X + offset.Z * offset.Z)
			if flat <= bestDistance and math.abs(offset.Y) < 7 then
				best, bestDistance = member, flat
			end
		end
	end
	if best then
		best.SpicyUntil = now + Logic.SPICY_TIME
		self:_removeChili()
		self.chiliNext = now + Logic.CHILI_EVERY
		self.context:Fire(nil, "Spicy", best.Player.UserId, Logic.SPICY_TIME)
	end
end

function EatsaPizza:_updateScore(state: TeamState)
	local shown = math.floor(self:_teamShare(state.Name) * 100 + 1e-6)
	if shown ~= state.Shown then
		self.context:AddTeamScore(state.Name, shown - state.Shown)
		state.Shown = shown
	end
end

function EatsaPizza:_finish(team: string, reason: string)
	if self.phase ~= "Eat" then
		return
	end
	local ctx = self.context
	self.phase = "Done"
	self.winner = team
	self.teams[team].ClearedAt = ctx:Now()
	self:_removeChili()
	self:_shareLayout()
	self:_shareSlices()
	self:_clearSpots()
	ctx:Sound("Victory")
	if reason == "Cleared" then
		ctx:Announce(`{label(team)} ATE THEIR PIZZA FIRST!`, "success", 3)
	else
		ctx:Announce(`{label(team)} WINS!`, "success", 3)
	end
	ctx:SetStatus(`{label(team)} WINS!`)
	ctx:Delay(FINALE, function()
		ctx:End(reason)
	end)
end

function EatsaPizza:Stop(_reason: string?)
	self:_removeChili()
	if self.phase == "Eat" then
		self.phase = "Done"
		self.winner = self:_winner()
		self:_shareLayout()
	end
	self:_clearSpots()
end

-- Sharing ------------------------------------------------------------------------------------------

function EatsaPizza:_shareLayout()
	local owners, teams = {}, {}
	for index = 1, Logic.SLICES do
		owners[index] = self.slices[index].Team or ""
	end
	for _, team in self.order do
		local state = self.teams[team]
		local ids = {}
		for _, player in state.Members do
			table.insert(ids, player.UserId)
		end
		table.insert(teams, { T = team, M = ids, G = if state.Gone then 1 else nil })
	end
	local c = self.center
	self.context:SetSharedJSON("Pizza", {
		C = { round(c.X, 0.01), round(c.Y, 0.01), round(c.Z, 0.01) },
		R = round(self.radius, 0.01),
		O = owners,
		T = teams,
		Ph = self.phase,
		W = self.winner,
	})
end

function EatsaPizza:_shareSlices()
	local left, max = {}, {}
	for index = 1, Logic.SLICES do
		local slice = self.slices[index]
		left[index] = slice.Left
		max[index] = slice.Max
	end
	self.context:SetSharedJSON("Slices", { L = left, M = max })
end

-- Results ------------------------------------------------------------------------------------------

-- Clearing first beats everything; then the share eaten (teams whose players all left come last).
function EatsaPizza:_rank(team: string): number
	local state = self.teams[team]
	if not state or state.Gone then
		return -1
	end
	if self.winner == team and state.ClearedAt then
		return 1000
	end
	return self:_teamShare(team) * 100
end

function EatsaPizza:_winner(): string?
	if self.winner then
		return self.winner
	end
	local best, bestRank, tie = nil, -math.huge, false
	for _, team in self.order do
		local rank = self:_rank(team)
		if rank > bestRank + 1e-6 then
			best, bestRank, tie = team, rank, false
		elseif math.abs(rank - bestRank) <= 1e-6 then
			tie = true
		end
	end
	return if tie or #self.order < 2 and bestRank <= 0 then nil else best
end

function EatsaPizza:GetResults()
	local results = self.context:TeamResults()
	for _, entry in results.Entries do
		local state = entry.Team and self.teams[entry.Team]
		if not state then
			continue
		end
		entry.Rank = self:_rank(entry.Team)
		local percent = math.floor(self:_teamShare(entry.Team) * 100 + 1e-6)
		local member = self.members[entry.Player]
		local bites = if member then member.Bites else 0
		-- ("◆ YELLOW 100% • 120 bites": the team with its mark, as short as fits the results card's
		-- result column; "Yellow ate 100% • you 120 bites" ended in "...".)
		entry.ScoreText = `{Teams.Label(entry.Team)} {percent}% • {bites} bites`
		entry.BestScore = bites
	end
	results.WinningTeam = self:_winner()
	return results
end

return EatsaPizza
