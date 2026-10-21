-- Client half of Cake Factory: slides every team's cakes along their belts from the shared
-- schedule ("Belt": T0, V0, Acc), stacks each cake's layers from the shared state ("Cakes_<Team>"),
-- works the machines when anyone presses (the "Add" event, bots included), boxes finished cakes,
-- tips ruined ones into the bin and stacks the boxes on each team's shelf.
--
-- This player gets the ADD button and a lane per machine they run: cakes slide towards the gate in
-- the middle, each marked ✓ (needs your layer: tap when it's in the gate), ✕ (missing a layer or
-- ruined: let it go) or ● (already done). The gate posts over your machine light up and the gate in
-- the lane grows and says TAP! while a cake that needs you is inside, so the cue is never color
-- alone. The server judges every press; the words over your machine (and in the lane's gate) are
-- its verdict. A press with no cake near jams the machine: ADD turns red and says ✕ JAMMED. The
-- pills show each team's 🎂 cakes and ⭐ cakes (every layer perfect, worth 2); the camera starts
-- behind you, looking at your machine.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameState = require(ReplicatedStorage.Shared.GameState)
local Teams = require(ReplicatedStorage.Shared.Teams)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local CakeFactory = {}

local ICONS = { Sponge = "🍰", Cream = "🍦", Berry = "🍓" }
local GREEN = Color3.fromRGB(90, 225, 120)
local RED = Color3.fromRGB(255, 80, 80)
local PLATE_LIFT = 0.08 -- plates ride just above the belt's ribs
-- Where each layer's pivot sits over the plate's (see Props/CakeFactory.luau).
local SPONGE_Y = 0.2
local CREAM_Y = 0.89
local BERRY_ON_CREAM = 1.69
local BERRY_ON_SPONGE = 1.42
local LANE_BEHIND = 13 -- the lane shows cakes this far before the gate...
local LANE_AHEAD = 5 -- ...and this far past it

type Layer = { Model: Model, Parts: { { Part: BasePart, Offset: CFrame } }, Shown: boolean }
type CakeView = {
	K: number,
	Plate: Layer,
	Sponge: Layer,
	Cream: Layer,
	Berry: Layer,
	Box: Layer,
	N: number,
	Bad: boolean,
	Tilt: CFrame,
	Mark: BillboardGui?,
	BoxedAt: number?,
	Shelved: boolean,
}
type Machine = {
	Index: number,
	X: number,
	Kind: string,
	Owner: number,
	Moving: { { Part: BasePart, Rest: CFrame } },
	PressedAt: number,
	JamAt: number,
	Gates: { BasePart },
	Model: Model?,
}
type Line = {
	Team: string,
	Color: Color3,
	Shape: string,
	Center: Vector3,
	Machines: { Machine },
	Cleats: { { Part: BasePart, Rest: CFrame } },
	Cakes: { [number]: CakeView },
	State: { K: number, S: string },
	Good: { [number]: boolean },
	Lamp: BasePart?,
	LampAt: number,
	Shelf: Model?,
	Shelved: number,
	ShelfBoxes: { Model },
	ShelfLabel: TextLabel?,
	Done: number,
	Stars: number,
	Gone: boolean,
	Pill: Frame?,
}

local function named(model: Instance, name: string): { BasePart }
	local list = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name == name then
			table.insert(list, part)
		end
	end
	return list
end

-- A copy of a shared template right now, or nil (never waits: safe inside RenderStep).
local function quickTemplate(name: string): Instance?
	local folder = ReplicatedStorage:FindFirstChild("MiniGameAssets")
	local template = folder and folder:FindFirstChild(name)
	return if template then template:Clone() else nil
end

-- A layer model (a template copy) with each part's place relative to the model's pivot. `quick`:
-- don't wait for the template.
local function layer(api, name: string, quick: boolean?): Layer?
	local model = if quick then quickTemplate(name) else api:Template(name)
	if not model or not model:IsA("Model") then
		return nil
	end
	local pivot = model:GetPivot()
	local parts = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			table.insert(parts, { Part = part, Offset = pivot:ToObjectSpace(part.CFrame) })
		end
	end
	return { Model = model, Parts = parts, Shown = false }
end

local function label(parent: Instance, text: string, size: number, color: Color3?, props: { [string]: any }?): TextLabel
	local options: { [string]: any } = {
		Text = text,
		Font = Theme.Fonts.Display,
		TextSize = size,
		TextColor3 = color or Color3.new(1, 1, 1),
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
		Children = { UIKit.TextStroke(0.15) },
	}
	if props then
		for key, value in props do
			options[key] = value
		end
	end
	return UIKit.Label(options)
end

local function billboard(api, adornee: BasePart, size: Vector2, offset: Vector3, distance: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(size.X, size.Y)
	gui.StudsOffsetWorldSpace = offset
	gui.MaxDistance = distance
	gui.LightInfluence = 0
	gui.Parent = api.World
	return gui
end

function CakeFactory.Start(api)
	api:Mood({ Tint = Color3.fromRGB(255, 246, 250), Saturation = 0.18, Contrast = 0.04 })
	local belt = api:SharedJSON("Belt")
	local waited = 0
	while not belt and waited < 10 do
		waited += task.wait(0.1)
		belt = api:SharedJSON("Belt")
	end
	local arena = api:Arena(10)
	if not belt or not arena then
		return
	end
	local effects = not State.ReducedEffects()
	local me = Players.LocalPlayer.UserId
	local spacing: number = belt.Spacing
	local length: number = belt.Length
	local start: number = belt.Start
	local finish: number = belt.Finish
	local window: number = belt.Window
	local top: number = belt.Top

	local function distance(t: number): number
		local t0 = belt.T0
		if type(t0) ~= "number" then
			return 0
		end
		local stop = if type(belt.StopAt) == "number" then belt.StopAt else math.huge
		local tau = math.clamp(t - t0, 0, stop - t0)
		return belt.V0 * tau + 0.5 * belt.Acc * tau * tau
	end

	-- Lines, machines and the world pieces the client moves.
	local lines = {} :: { [string]: Line }
	local order = {} :: { string }
	local function world(line: Line, u: number, y: number, z: number): Vector3
		return line.Center + Vector3.new(length / 2 - u, y, z)
	end
	for _, info in belt.Lines do
		local team = info.Team
		local folder = arena:FindFirstChild("Line_" .. team)
		local line: Line = {
			Team = team,
			Color = Teams.Colors[team] or Theme.Colors.Pink,
			Shape = info.Shape or "",
			Center = Vector3.new(info.C[1], info.C[2], info.C[3]),
			Machines = {},
			Cleats = {},
			Cakes = {},
			State = { K = 0, S = "" },
			Good = {},
			Lamp = nil,
			LampAt = -math.huge,
			Shelf = nil,
			Shelved = 0,
			ShelfBoxes = {},
			ShelfLabel = nil,
			Done = 0,
			Stars = 0,
			Gone = info.Gone == true,
			Pill = nil,
		}
		if folder then
			local beltModel = folder:FindFirstChild("Belt")
			if beltModel then
				for _, part in named(beltModel, "Cleats") do
					table.insert(line.Cleats, { Part = part, Rest = part.CFrame })
				end
			end
			local boxer = folder:FindFirstChild("Boxer")
			line.Lamp = if boxer then named(boxer, "Lamp")[1] else nil
			line.Shelf = folder:FindFirstChild("Shelf") :: Model?
		end
		for index, station in info.Stations do
			local model = folder and folder:FindFirstChild("Machine_" .. index) :: Model?
			local moving = {}
			if model then
				local piece = if station.Kind == "Sponge"
					then "Stamp"
					elseif station.Kind == "Cream" then "Nozzle"
					else "Chute"
				for _, part in named(model, piece) do
					table.insert(moving, { Part = part, Rest = part.CFrame })
				end
				if station.Kind == "Berry" then
					for _, name in { "Berries", "BerryLeaves" } do
						for _, part in named(model, name) do
							table.insert(moving, { Part = part, Rest = part.CFrame })
						end
					end
				end
			end
			table.insert(line.Machines, {
				Index = index,
				X = station.X,
				Kind = station.Kind,
				Owner = station.Owner,
				Moving = moving,
				PressedAt = -math.huge,
				JamAt = -math.huge,
				Gates = if folder then named(folder, "Gate_" .. index) else {},
				Model = model,
			})
		end
		-- The shelf's count, for everyone watching.
		local shelfRoot = line.Shelf and line.Shelf:FindFirstChildWhichIsA("BasePart", true)
		if shelfRoot then
			local gui = billboard(api, shelfRoot :: BasePart, Vector2.new(120, 50), Vector3.new(0, 4, 0), 160)
			gui.Adornee = nil
			local anchor = Instance.new("Part")
			anchor.Name = "ShelfAnchor"
			anchor.Anchored = true
			anchor.CanCollide = false
			anchor.CanQuery = false
			anchor.CanTouch = false
			anchor.Transparency = 1
			anchor.Size = Vector3.one * 0.2
			anchor.CFrame = (line.Shelf :: Model):GetPivot() + Vector3.new(0, 13.6, 0)
			anchor.Parent = api.World
			gui.Adornee = anchor
			gui.StudsOffsetWorldSpace = Vector3.zero
			line.ShelfLabel = label(gui, "🎂 0", 34, Color3.new(1, 1, 1))
		end
		lines[team] = line
		table.insert(order, team)
	end

	-- Which machines are mine (it changes if a teammate leaves).
	local myTeam: string? = nil
	local mine = {} :: { Machine }
	local function refreshOwners()
		mine = {}
		myTeam = nil
		for _, info in belt.Lines do
			local line = lines[info.Team]
			for index, station in info.Stations do
				local machine = line and line.Machines[index]
				if machine then
					machine.Owner = station.Owner
					if station.Owner == me then
						table.insert(mine, machine)
						myTeam = info.Team
					end
				end
			end
		end
	end
	refreshOwners()
	local myLine = if myTeam then lines[myTeam] else nil
	local myColor = if myLine then myLine.Color else Theme.Colors.Pink

	-- Your machines stand out: an outline and a "YOU" marker over each.
	local marks = {} :: { Instance }
	local function markMine()
		for _, item in marks do
			item:Destroy()
		end
		marks = {}
		if not myLine then
			return
		end
		for _, machine in mine do
			if machine.Model then
				local highlight = Instance.new("Highlight")
				highlight.Adornee = machine.Model
				highlight.FillColor = Color3.new(1, 1, 1)
				highlight.FillTransparency = 0.85
				highlight.OutlineColor = Color3.new(1, 1, 1)
				highlight.DepthMode = Enum.HighlightDepthMode.Occluded
				highlight.Parent = api.World
				table.insert(marks, highlight)
			end
			local anchor = Instance.new("Part")
			anchor.Name = "YouAnchor"
			anchor.Anchored = true
			anchor.CanCollide = false
			anchor.CanQuery = false
			anchor.CanTouch = false
			anchor.Transparency = 1
			anchor.Size = Vector3.one * 0.2
			anchor.CFrame = CFrame.new(world(myLine, machine.X, 18.4, -1))
			anchor.Parent = api.World
			table.insert(marks, anchor)
			local gui = billboard(api, anchor, Vector2.new(120, 46), Vector3.zero, 120)
			label(gui, "▼ YOU", 30, Color3.new(1, 1, 1))
			table.insert(marks, gui)
		end
	end
	markMine()

	-- Everyone's team shape over their head (bots too), so teams read without color.
	local tags = {} :: { [number]: BillboardGui }
	local function refreshTags()
		for _, participant in api:Participants() do
			local team = participant:GetAttribute("PP_Team")
			local line = team and lines[team]
			local character = api:CharacterOf(participant.UserId)
			local head = character and character:FindFirstChild("Head") :: BasePart?
			local tag = tags[participant.UserId]
			if not line or not head or (tag and tag.Parent and tag.Adornee == head) then
				continue
			end
			if tag then
				tag:Destroy()
			end
			local gui = billboard(api, head, Vector2.new(40, 40), Vector3.new(0, 3.1, 0), 90)
			gui.Name = "TeamTag"
			label(gui, line.Shape, 32, line.Color)
			tags[participant.UserId] = gui
		end
	end
	refreshTags()

	-- HUD: a pill per team (shape, name, cakes), yours outlined, all in one row (with 3-4 teams
	-- just the shape; the name floats over each line). Phones draw the HUD smaller, so there the
	-- text is bigger and everything sits as high as it can, clear of the move stick.
	local hud = api:TopHud()
	local y = api:HudY()
	local touch = api:IsTouch()
	local count = #order
	-- (Phones: two to a row, right-aligned over the lanes, clear of the move stick's zone.)
	local compact = count >= 3 or touch
	local columns = if touch then math.min(count, 2) else count
	local pillWidth = if touch then 200 elseif compact then math.min(150, math.floor(470 / count) - 10) else 210
	local textSize = if touch then 26 else 20
	local rowStep = 56
	for index, team in order do
		local line = lines[team]
		local row = (index - 1) // columns
		local inRow = math.min(columns, count - row * columns)
		local column = (index - 1) % columns + 1
		local isMine = team == myTeam
		local pill = UIKit.new("Frame", {
			Name = "Team_" .. team,
			AnchorPoint = if touch then Vector2.new(1, 0) else Vector2.new(0.5, 0),
			Position = if touch
				then UDim2.new(1, -(inRow - column) * (pillWidth + 10), 0, y + row * rowStep)
				else UDim2.new(0.5, (column - (inRow + 1) / 2) * (pillWidth + 10), 0, y + row * rowStep),
			Size = UDim2.fromOffset(pillWidth, 46),
			BackgroundColor3 = Theme.Colors.PanelDark,
			BackgroundTransparency = 0.15,
			Parent = hud,
			Children = {
				UIKit.Corner(14),
				UIKit.Stroke(if isMine then Color3.new(1, 1, 1) else line.Color, if isMine then 3 else 2, 0),
			},
		})
		local nameWidth = if compact then 34 else math.floor(pillWidth * 0.42)
		label(pill, if compact then line.Shape else `{line.Shape} {string.upper(team)}`, textSize, line.Color, {
			Name = "Name",
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(0, nameWidth, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		-- Cakes and ⭐ cakes (shrinks to fit a narrow pill).
		local countLabel = label(pill, "🎂 0  ⭐ 0", textSize, Color3.new(1, 1, 1), {
			Name = "Count",
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.new(1, -nameWidth - 24, 0, textSize + 4),
			TextScaled = true,
		})
		UIKit.new("UITextSizeConstraint", { MaxTextSize = textSize, Parent = countLabel })
		line.Pill = pill
	end
	local pillsBottom = y + (math.ceil(count / columns) - 1) * rowStep + 46
	local function drawPill(line: Line)
		local pill = line.Pill
		local countLabel = pill and pill:FindFirstChild("Count") :: TextLabel?
		if not pill or not countLabel then
			return
		end
		local text = if line.Gone then "— left" else `🎂 {line.Done}  ⭐ {line.Stars}`
		if countLabel.Text ~= text then
			countLabel.Text = text
		end
		pill.BackgroundTransparency = if line.Gone then 0.6 else 0.15
		if line.ShelfLabel then
			line.ShelfLabel.Text = `🎂 {line.Done}`
		end
	end
	for _, team in order do
		drawPill(lines[team])
	end

	-- Your lanes: one per machine you run.
	-- (Phones: on the right half, so the move stick's corner stays clear.)
	type Lane = {
		Machine: Machine,
		Frame: Frame,
		Track: Frame,
		Gate: Frame,
		Kind: TextLabel,
		Dots: { Frame },
		Stroke: UIStroke?,
		FlashText: string,
		FlashAt: number,
		FlashColor: Color3,
	}
	local lanes = {} :: { Lane }
	local laneWidth = if touch then 440 else 380
	local laneHeight = if touch then 80 else 54
	local laneTop = pillsBottom + 10
	local laneHolder = UIKit.new("Frame", {
		Name = "Lanes",
		AnchorPoint = if touch then Vector2.new(1, 0) else Vector2.new(0.5, 0),
		Position = if touch then UDim2.new(1, 0, 0, laneTop) else UDim2.new(0.5, 0, 0, laneTop),
		Size = UDim2.fromOffset(laneWidth, 0),
		BackgroundTransparency = 1,
		Parent = hud,
	})
	local function buildLanes()
		for _, lane in lanes do
			lane.Frame:Destroy()
		end
		lanes = {}
		table.sort(mine, function(a, b)
			return a.Index < b.Index
		end)
		for slot, machine in mine do
			local frame = UIKit.new("Frame", {
				Name = "Lane_" .. machine.Index,
				Position = UDim2.fromOffset(0, (slot - 1) * (laneHeight + 8)),
				Size = UDim2.fromOffset(laneWidth, laneHeight),
				BackgroundColor3 = Theme.Colors.PanelDark,
				BackgroundTransparency = 0.12,
				Parent = laneHolder,
				Children = { UIKit.Corner(14), UIKit.Stroke(myColor, 2, 0) },
			})
			local stroke = frame:FindFirstChildWhichIsA("UIStroke")
			local tagWidth = if touch then 164 else 116
			local kind = label(
				frame,
				`{ICONS[machine.Kind] or ""} {string.upper(machine.Kind)}`,
				if touch then 28 else 19,
				Color3.new(1, 1, 1),
				{
					Name = "Kind",
					Position = UDim2.fromOffset(8, 0),
					Size = UDim2.new(0, tagWidth - 8, 1, 0),
					TextXAlignment = Enum.TextXAlignment.Left,
				}
			)
			local track = UIKit.new("Frame", {
				Name = "Track",
				Position = UDim2.new(0, tagWidth, 0, 6),
				Size = UDim2.new(1, -tagWidth - 8, 1, -12),
				BackgroundColor3 = Color3.fromRGB(60, 54, 76),
				BackgroundTransparency = 0.05,
				ClipsDescendants = true,
				Parent = frame,
				Children = { UIKit.Corner(10) },
			})
			local span = LANE_BEHIND + LANE_AHEAD
			local gateCenter = LANE_BEHIND / span
			local gate = UIKit.new("Frame", {
				Name = "Gate",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(gateCenter, 0.5),
				Size = UDim2.new(window * 2 / span, 0, 1, -4),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.8,
				ZIndex = 2,
				Parent = track,
				Children = { UIKit.Corner(8), UIKit.Stroke(Color3.new(1, 1, 1), 3, 0) },
			})
			local dots = {}
			for _ = 1, 4 do
				local dot = UIKit.new("Frame", {
					Name = "Cake",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromOffset(laneHeight - 18, laneHeight - 18),
					BackgroundColor3 = Color3.new(1, 1, 1),
					Visible = false,
					ZIndex = 3,
					Parent = track,
					Children = { UIKit.Round(), UIKit.Stroke(Color3.new(0, 0, 0), 2, 0.3) },
				})
				label(dot, "", if touch then 34 else 20, Color3.new(1, 1, 1), { Name = "Mark", ZIndex = 4 })
				table.insert(dots, dot)
			end
			table.insert(lanes, {
				Machine = machine,
				Frame = frame,
				Track = track,
				Gate = gate,
				Kind = kind,
				Dots = dots,
				Stroke = stroke,
				FlashText = "",
				FlashAt = -math.huge,
				FlashColor = GREEN,
			})
		end
		laneHolder.Size = UDim2.fromOffset(laneWidth, #mine * (laneHeight + 8))
	end
	buildLanes()

	-- ADD: wakes up at GO; the hint shows for 8 seconds under the lanes (not on phones: the lanes'
	-- TAP! says it, and the move stick's corner stays clear).
	local add = if myLine then api:Button({ Text = "ADD", Key = Enum.KeyCode.E, Color = myColor }) else nil
	if add then
		add:SetEnabled(false)
	end
	local live = false
	local hintUntil = math.huge
	local jamUntil = -math.huge
	local function hintY(): number
		return laneTop + #mine * (laneHeight + 8) + 8
	end
	-- Turn the camera once to look over your shoulder at your machine(s) (the custom camera keeps
	-- that heading; players are put at their spot without turning the lobby's camera).
	local function aimCamera()
		local camera = workspace.CurrentCamera
		if not camera or not myLine or #mine == 0 then
			return
		end
		local sum = 0
		for _, machine in mine do
			sum += machine.X
		end
		local x = sum / #mine
		local eye = world(myLine, x - 3.6, top + 8, -6.4 - 13)
		camera.CFrame = CFrame.lookAt(eye, world(myLine, x, top, 0))
	end
	local function goLive(now: number)
		if live then
			if now > hintUntil then
				hintUntil = math.huge
				api:Hint("")
			end
			return
		elseif GameState.Get("Phase") ~= "InRound" or type(belt.T0) ~= "number" then
			return
		end
		live = true
		aimCamera()
		if add then
			add:SetEnabled(true)
			if not touch then
				api:Hint("Press E (ADD) when a ✓ cake is in the gate", hintY())
				hintUntil = now + 8
			end
		end
	end
	if add then
		add.Pressed:Connect(function()
			if live and not belt.StopAt and os.clock() >= jamUntil then
				api:Action("Add")
			end
		end)
	end

	-- Words that rise and fade over a spot in the world.
	local function popup(position: Vector3, text: string, color: Color3)
		local anchor = Instance.new("Part")
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one * 0.2
		anchor.CFrame = CFrame.new(position)
		anchor.Parent = api.World
		local gui = billboard(api, anchor, Vector2.new(260, 50), Vector3.zero, 90)
		gui.AlwaysOnTop = true
		local text3 = label(gui, text, 32, color)
		UIKit.Tween(gui, 0.7, { StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0) })
		UIKit.Tween(text3, 0.7, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.75, function()
			anchor:Destroy()
			gui:Destroy()
		end)
	end

	-- The verdict over your machine, and flashed on its lane (outline and tag).
	local streak = 0
	local function feedback(machine: Machine, kind: string)
		if not myLine then
			return
		end
		local text, color, short
		if kind == "perfect" then
			streak += 1
			text, color, short = if streak >= 3 then `⭐ PERFECT x{streak}!` else "⭐ PERFECT!", GREEN, "⭐ PERFECT"
		elseif kind == "good" then
			streak += 1
			text, color, short = "GOOD!", Color3.fromRGB(150, 230, 255), "✓ GOOD!"
		elseif kind == "miss" then
			streak = 0
			text, color, short = "✕ NO CAKE!", Theme.Colors.Yellow, "✕ JAMMED"
		elseif kind == "ruined" then
			text, color, short = "✕ ALREADY RUINED", Theme.Colors.Yellow, "✕ RUINED"
		elseif kind == "late" then
			streak = 0
			text, color, short = "MISSED ONE!", Theme.Colors.Yellow, "✕ MISSED"
		else
			streak = 0
			text = if kind == "wrong"
				then "✕ MISSING LAYER!"
				elseif kind == "double" then "✕ TWICE!"
				else "✕ SPLAT!"
			color, short = RED, "✕ RUINED"
		end
		popup(world(myLine, machine.X, top + 3, -3.4), text, color)
		for _, lane in lanes do
			if lane.Machine == machine then
				lane.FlashAt = os.clock()
				lane.FlashColor = color
				lane.FlashText = short
			end
		end
	end

	-- Cake views: made when a cake appears on a belt, put back in a pool when it leaves.
	local pool = {} :: { CakeView }
	local function hideLayer(item: Layer)
		if item.Shown then
			item.Shown = false
			item.Model.Parent = nil
		end
	end
	-- `quick`: called from RenderStep, so never wait for a template (skip the cake this frame).
	local function newView(quick: boolean?): CakeView?
		local view = table.remove(pool)
		if view then
			return view
		end
		local plate = layer(api, "CakePlate", quick)
		local sponge = layer(api, "CakeSponge", quick)
		local cream = layer(api, "CakeCream", quick)
		local berry = layer(api, "CakeBerry", quick)
		local box = layer(api, "CakeBox", quick)
		if not (plate and sponge and cream and berry and box) then
			return nil
		end
		return {
			K = -1,
			Plate = plate,
			Sponge = sponge,
			Cream = cream,
			Berry = berry,
			Box = box,
			N = 0,
			Bad = false,
			Tilt = CFrame.identity,
			Mark = nil,
			BoxedAt = nil,
			Shelved = false,
		}
	end
	local function release(view: CakeView)
		for _, item in { view.Plate, view.Sponge, view.Cream, view.Berry, view.Box } do
			hideLayer(item)
		end
		if view.Mark then
			view.Mark:Destroy()
			view.Mark = nil
		end
		table.insert(pool, view)
	end
	-- Enough views for every belt up front (about six cakes ride a belt at once), made here where
	-- waiting for the templates is fine.
	for _ = 1, 6 * #order do
		local view = newView()
		if not view then
			break
		end
		table.insert(pool, view)
	end
	api:Track(function()
		for _, view in pool do
			for _, item in { view.Plate, view.Sponge, view.Cream, view.Berry, view.Box } do
				item.Model:Destroy()
			end
		end
		for _, line in lines do
			for _, view in line.Cakes do
				for _, item in { view.Plate, view.Sponge, view.Cream, view.Berry, view.Box } do
					item.Model:Destroy()
				end
			end
		end
	end)

	-- A cake's layers and whether it's ruined, from the shared string.
	-- (A cake the server no longer lists, already past the end, keeps what it showed: `known` false.)
	local function cakeState(line: Line, k: number): (number, boolean, boolean)
		local index = k - line.State.K + 1
		local s = line.State.S
		if index < 1 or index > #s then
			return 0, false, index > #s
		end
		local byte = string.byte(s, index)
		if byte >= 97 then
			return byte - 97, true, true
		end
		return byte - 48, false, true
	end
	for _, team in order do
		local line = lines[team]
		local function readCakes()
			local state = api:SharedJSON("Cakes_" .. team)
			if type(state) == "table" and type(state.K) == "number" and type(state.S) == "string" then
				line.State = { K = state.K, S = state.S }
				if type(state.D) == "number" then
					line.Done = math.max(line.Done, state.D)
				end
				if type(state.St) == "number" then
					line.Stars = math.max(line.Stars, state.St)
				end
				drawPill(line)
			end
		end
		api:OnShared("Cakes_" .. team, readCakes)
		readCakes()
	end
	api:OnShared("Belt", function()
		local value = api:SharedJSON("Belt")
		if type(value) == "table" then
			belt = value
			for _, info in belt.Lines do
				local line = lines[info.Team]
				if line then
					line.Gone = info.Gone == true
					drawPill(line)
				end
			end
			refreshOwners()
			buildLanes()
			markMine()
		end
	end)

	-- Machines move when anyone presses; you also hear and see the verdict on your own.
	api:OnEvent("Add", function(team, index, _k, kind, userId)
		local line = lines[team]
		local machine = line and line.Machines[index]
		if not machine then
			return
		end
		if kind == "miss" then
			machine.JamAt = os.clock()
		elseif kind ~= "ruined" then
			machine.PressedAt = os.clock()
		end
		if userId == me then
			if kind == "miss" then
				jamUntil = os.clock() + (tonumber(belt.Jam) or 0.5)
			end
			feedback(machine, kind)
			if kind == "perfect" or kind == "good" then
				api:Sound(if machine.Kind == "Berry" then "Boing" else "Pickup")
			elseif kind == "miss" or kind == "ruined" then
				api:Sound("Click")
			else
				api:Sound("Hit")
			end
		end
	end)
	api:OnEvent("Missed", function(team, index)
		local line = lines[team]
		local machine = line and line.Machines[index]
		if machine and machine.Owner == me then
			feedback(machine, "late")
		end
	end)
	api:OnEvent("Boxed", function(team, k, good, done, star, stars)
		local line = lines[team]
		if not line or line.Gone then
			return
		end
		line.Good[k] = good == true
		if type(done) == "number" then
			line.Done = math.max(line.Done, done)
		end
		if type(stars) == "number" then
			line.Stars = math.max(line.Stars, stars)
		end
		drawPill(line)
		if star and team == myTeam then
			popup(world(line, belt.Box, top + 6, -2), "⭐ CAKE +2", Theme.Colors.Yellow)
		end
		if good then
			line.LampAt = os.clock()
			local view = line.Cakes[k]
			if view then
				view.BoxedAt = os.clock()
			end
			if team == myTeam then
				api:Sound("Victory")
			end
		end
	end)
	-- A teammate left and you took over their machine(s).
	api:OnEvent("Reassigned", function(kinds)
		if type(kinds) ~= "table" then
			return
		end
		local names = {}
		for _, kind in kinds do
			if type(kind) == "string" then
				table.insert(names, `{ICONS[kind] or ""} {string.upper(kind)}`)
			end
		end
		if #names > 0 then
			api:Hint(`You now run {table.concat(names, " + ")}!`, hintY())
			hintUntil = os.clock() + 3
		end
		task.delay(0.3, aimCamera) -- after the new owners arrive
	end)
	api:OnEvent("Faster", function()
		if add then
			api:Sound("HazardWarning")
		end
	end)
	api:OnEvent("Winner", function(team)
		local line = lines[team]
		if line and line.Shelf then
			api:Effect(
				"Confetti",
				line.Shelf:GetPivot().Position + Vector3.new(0, 12, 0),
				{ line.Color, Color3.new(1, 1, 1) }
			)
			if team == myTeam then
				api:Effect(
					"Fireworks",
					line.Shelf:GetPivot().Position + Vector3.new(0, 16, 0),
					{ line.Color, Theme.Colors.Yellow }
				)
			end
		end
	end)

	-- A boxed cake joins its team's shelf (12 at half size; the count says the rest).
	local function shelve(line: Line)
		line.Shelved += 1
		local slot = line.Shelved - 1
		if not line.Shelf or slot >= 12 then
			return
		end
		local box = quickTemplate("CakeBox") :: Model?
		if not box then
			return
		end
		box:ScaleTo(box:GetScale() * 0.48)
		for _, part in box:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				local stripe = part.Name == "Stripe"
				if stripe then
					part.Color = line.Color
				end
			end
		end
		local row, column = slot // 4, slot % 4
		local target = (line.Shelf :: Model):GetPivot() * CFrame.new(-3.75 + column * 2.5, 0.5 + row * 3, 0)
		box:PivotTo(target + Vector3.new(0, 3, 0))
		box.Parent = api.World
		table.insert(line.ShelfBoxes, box)
		local start = os.clock()
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local alpha = math.clamp((os.clock() - start) / 0.25, 0, 1)
			if not box.Parent then
				connection:Disconnect()
				return
			end
			box:PivotTo(target + Vector3.new(0, 3 * (1 - alpha * alpha), 0))
			if alpha >= 1 then
				connection:Disconnect()
			end
		end)
		api:Track(connection)
	end

	local function place(item: Layer, base: CFrame, parts: { BasePart }, frames: { CFrame })
		if not item.Shown then
			item.Shown = true
			item.Model.Parent = api.World
		end
		for _, piece in item.Parts do
			table.insert(parts, piece.Part)
			table.insert(frames, base * piece.Offset)
		end
	end

	local rng = Random.new()
	local tagClock = 0
	local addJammed = false
	api:RenderStep(function(dt)
		local clock = os.clock()
		local now = api:Now()
		goLive(clock)
		local d = distance(now)
		local parts, frames = {}, {}

		for _, team in order do
			local line = lines[team]
			-- The belt's ribs crawl along with it.
			local shift = d % 2
			for _, cleat in line.Cleats do
				table.insert(parts, cleat.Part)
				table.insert(frames, cleat.Rest + Vector3.new(-shift, 0, 0))
			end

			-- The cakes on the belt (and the ones dropping into the bin).
			local newest = math.floor(d / spacing)
			local oldest = math.max(0, math.ceil((start + d - finish - 3) / spacing))
			for k, view in line.Cakes do
				if k < oldest or k > newest then
					line.Cakes[k] = nil
					release(view)
				end
			end
			for k = oldest, newest do
				local view = line.Cakes[k]
				if not view then
					view = newView(true)
					if not view then
						break
					end
					view.K = k
					view.N = -1
					view.Bad = false
					view.BoxedAt = if line.Good[k] then clock - 1 else nil
					view.Shelved = false
					view.Tilt = CFrame.identity
					line.Cakes[k] = view
				end
				local u = start + d - k * spacing
				local n, bad, known = cakeState(line, k)
				if not known then
					n, bad = math.max(view.N, 0), view.Bad
				end
				if n ~= view.N or bad ~= view.Bad then
					if bad and not view.Bad then
						view.Tilt = CFrame.new(rng:NextNumber(-0.5, 0.5), 0, rng:NextNumber(-0.4, 0.4))
							* CFrame.Angles(
								rng:NextNumber(-0.35, 0.35),
								rng:NextNumber(0, 6),
								rng:NextNumber(-0.35, 0.35)
							)
						local anchorPart = view.Plate.Parts[1] and view.Plate.Parts[1].Part
						if anchorPart then
							local gui = billboard(api, anchorPart, Vector2.new(44, 44), Vector3.new(0, 3.6, 0), 80)
							gui.Name = "Ruined"
							label(gui, "✕", 36, RED)
							view.Mark = gui
						end
					end
					view.N = n
					view.Bad = bad
				end
				local drop = 0
				if u > finish then
					local over = u - finish
					if line.Good[k] then
						if not view.Shelved then
							view.Shelved = true
							shelve(line)
						end
						for _, item in { view.Plate, view.Sponge, view.Cream, view.Berry, view.Box } do
							hideLayer(item)
						end
						continue
					end
					drop = 1.8 * over * over + 0.6 * over -- tipped off the end, into the bin
				end
				local base = CFrame.new(world(line, u, top + PLATE_LIFT - drop, 0))
				place(view.Plate, base, parts, frames)
				local tilt = if view.Bad then base * view.Tilt else base
				local steps = #line.Machines
				local hasCream = steps >= 3
				if view.N >= 1 then
					place(view.Sponge, tilt * CFrame.new(0, SPONGE_Y, 0), parts, frames)
				else
					hideLayer(view.Sponge)
				end
				if hasCream and view.N >= 2 then
					place(view.Cream, tilt * CFrame.new(0, CREAM_Y, 0), parts, frames)
				else
					hideLayer(view.Cream)
				end
				local berryFrom = if hasCream then 3 else 2
				if view.N >= berryFrom then
					local yBerry = if hasCream then BERRY_ON_CREAM else BERRY_ON_SPONGE
					place(view.Berry, tilt * CFrame.new(0, yBerry, 0), parts, frames)
				else
					hideLayer(view.Berry)
				end
				-- The packer drops a box over a finished cake.
				if view.BoxedAt and line.Good[k] then
					local alpha = math.clamp((clock - view.BoxedAt) / 0.22, 0, 1)
					place(view.Box, base * CFrame.new(0, 4.5 * (1 - alpha * alpha) - 0.05, 0), parts, frames)
				else
					hideLayer(view.Box)
				end
				if view.Mark then
					view.Mark.Enabled = u < finish + 1
				end
			end

			-- Machines: a press stamps / dips / drops; a jam shakes.
			for _, machine in line.Machines do
				local since = clock - machine.PressedAt
				local jam = clock - machine.JamAt
				local offset = Vector3.zero
				if since < 0.3 then
					local push = math.sin(math.clamp(since / 0.3, 0, 1) * math.pi)
					if machine.Kind == "Sponge" then
						offset = Vector3.new(0, -1.25 * push, 0)
					elseif machine.Kind == "Cream" then
						offset = Vector3.new(0, -0.45 * push, 0)
					else
						offset = Vector3.new(0, 0.5 * push, 0)
					end
				elseif jam < 0.4 and effects then
					offset = Vector3.new(math.sin(jam * 60) * 0.12 * (1 - jam / 0.4), 0, 0)
				end
				for _, piece in machine.Moving do
					table.insert(parts, piece.Part)
					table.insert(frames, piece.Rest + offset)
				end
			end

			-- The packer's lamp blinks for every boxed cake.
			if line.Lamp then
				local lit = clock - line.LampAt < 0.35
				line.Lamp.Color = if lit then Color3.fromRGB(255, 255, 200) else Color3.fromRGB(140, 255, 160)
			end
		end

		-- Your lanes and gates: where the next cakes are, and whether they need you.
		local fill, fillColor = 0, Color3.new(1, 1, 1)
		for _, lane in lanes do
			local machine = lane.Machine
			local line = myLine
			if not line then
				break
			end
			local span = LANE_BEHIND + LANE_AHEAD
			local used = 0
			local ready = false
			local first = math.floor((start + d - machine.X - LANE_AHEAD) / spacing) + 1
			for k = math.max(first, 0), math.floor(d / spacing) do
				local u = start + d - k * spacing
				local offset = u - machine.X
				if offset < -LANE_BEHIND or offset > LANE_AHEAD then
					continue
				end
				used += 1
				local dot = lane.Dots[used]
				if not dot then
					break
				end
				local n, bad = cakeState(line, k)
				local needs = not bad and n == machine.Index - 1
				local done = not bad and n >= machine.Index
				dot.Visible = true
				dot.Position = UDim2.fromScale((offset + LANE_BEHIND) / span, 0.5)
				dot.BackgroundColor3 = if needs then GREEN elseif done then Color3.fromRGB(150, 160, 190) else RED
				local markLabel = dot:FindFirstChild("Mark") :: TextLabel?
				if markLabel then
					markLabel.Text = if needs then "✓" elseif done then "●" else "✕"
				end
				if needs and math.abs(offset) <= window then
					ready = true
				end
				if needs and offset < window then
					local near = 1 - math.clamp(math.abs(offset) / 9, 0, 1)
					if near > fill then
						fill = near
						fillColor = if math.abs(offset) <= window then GREEN else Color3.new(1, 1, 1)
					end
				end
			end
			for index = used + 1, #lane.Dots do
				lane.Dots[index].Visible = false
			end
			lane.Gate.BackgroundTransparency = if ready then 0.35 else 0.8
			lane.Gate.BackgroundColor3 = if ready then GREEN else Color3.new(1, 1, 1)
			-- The last verdict flashes on the lane's outline and in its gate.
			local flashing = clock - lane.FlashAt < 0.3
			if lane.Stroke then
				lane.Stroke.Color = if flashing then lane.FlashColor else myColor
				lane.Stroke.Thickness = if flashing then 4 else 2
			end
			local scale = if ready then 1.12 else 1
			lane.Gate.Size = UDim2.new(window * 2 / span * scale, 0, 1, if ready then 0 else -4)
			local verdict = clock - lane.FlashAt < 0.5
			local kindText = if verdict
				then lane.FlashText
				elseif ready then "👉 TAP!"
				else `{ICONS[machine.Kind] or ""} {string.upper(machine.Kind)}`
			if lane.Kind.Text ~= kindText then
				lane.Kind.Text = kindText
				lane.Kind.TextColor3 = if verdict then lane.FlashColor elseif ready then GREEN else Color3.new(1, 1, 1)
			end
			for _, gate in machine.Gates do
				gate.Material = if ready then Enum.Material.Neon else Enum.Material.SmoothPlastic
				gate.Color = if ready then GREEN else Color3.new(1, 1, 1)
			end
		end
		if add then
			-- Jammed (a press with no cake near): ADD is red, says so and holds presses.
			local jammed = clock < jamUntil
			if jammed then
				add:SetFill(1, RED)
			else
				add:SetFill(fill, fillColor)
			end
			if jammed ~= addJammed then
				addJammed = jammed
				add:SetText(if jammed then "✕ JAMMED" else "ADD")
			end
		end

		if #parts > 0 then
			workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end

		tagClock += dt
		if tagClock > 1 then
			tagClock = 0
			refreshTags()
		end
	end)
end

return CakeFactory
