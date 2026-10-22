-- Client half of Hot Potato (server: src/server/MiniGames/HotPotato.luau). Draws every potato from
-- the shared MG_Potatoes (who holds which, flights, warnings), so a player who joins late sees the
-- same thing as everyone else, and sends this player's passes.
--
-- Everyone must always see who holds a potato (owner's pitch: "a few ticking bombs get handed out"):
-- the potato itself bobs big above each holder's head with a ▼ marker over it (a shape, not just a
-- colour), and in its last 3 s it glows, sparks and shows "!!". The holder gets a pulsing "YOU HAVE
-- THE POTATO! PASS IT!" banner, a red screen edge and a THROW button; everyone sees how many are left.
--
-- Passing: touching an empty-handed player tags them (sent as soon as they're within the server's
-- rule, Logic/HotPotato.CLIENT_TAG, so a tag drawn on screen is one the server counts); THROW lobs it
-- to the nearest empty-handed player in front within CLIENT_THROW, marked with a ◆. Both are drawn at
-- once (a prediction) and undone if the server answers "Refused". Nothing is sent before GO.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Logic.HotPotato)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local HotPotato = {}

local HOT = Color3.fromRGB(255, 120, 40)
local DANGER = Color3.fromRGB(255, 50, 50)
local SPUD = Color3.fromRGB(196, 140, 78)

type Entry = {
	I: number,
	H: number,
	F: number,
	N: number,
	L: number,
	W: number?,
	Fl: { A: number, B: number, T0: number, T1: number, P: { number } }?,
}
type Guess = { To: number, Until: number, Throw: boolean, T0: number, From: Vector3? }
type Visual = {
	Model: Model,
	Spud: BasePart?,
	Spark: BasePart?,
	Light: PointLight,
	Marker: TextLabel,
	Gui: BillboardGui,
	Fallback: boolean,
}

local function rootOf(model: Model?): BasePart?
	return if model then model:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function HotPotato.Start(api)
	local localPlayer = Players.LocalPlayer
	local me = localPlayer.UserId
	api:Mood({ Tint = Color3.fromRGB(255, 240, 222), Saturation = 0.12 })

	-- Shared state ------------------------------------------------------------------------------------
	local potatoes: { Entry } = {}
	local function readPotatoes()
		local list = api:SharedJSON("Potatoes")
		potatoes = if type(list) == "table" then list else {}
	end
	readPotatoes()
	local guesses: { [number]: Guess } = {} -- passes this client drew before the server answered
	local backoff: { [number]: number } = {} -- targets a pass was just refused for, until when
	-- People whose blast this client saw: out, though their character still flies for a moment.
	local blown: { [number]: boolean } = {}
	api:OnShared("Potatoes", function()
		readPotatoes()
		local alive = {}
		for _, entry in potatoes do
			alive[entry.I] = true
		end
		for id in guesses do
			if not alive[id] then
				guesses[id] = nil
			end
		end
	end)

	local function inRound(): boolean
		return State.Phase() == "InRound" and api:CanAct()
	end

	-- Who holds `entry` on this screen (0 while it flies), and its flight if any.
	local function holderOf(entry: Entry, now: number): number
		local guess = guesses[entry.I]
		if guess and now < guess.Until then
			return if guess.Throw and now < guess.T0 + Rules.FLIGHT then 0 else guess.To
		end
		return entry.H
	end

	local function busy(userId: number, now: number): boolean
		for _, entry in potatoes do
			if holderOf(entry, now) == userId then
				return true
			end
			local flight = entry.Fl
			if flight and (flight.A == userId or flight.B == userId) then
				return true
			end
			local guess = guesses[entry.I]
			if guess and now < guess.Until and guess.To == userId then
				return true
			end
		end
		return false
	end

	local function myPotato(now: number): Entry?
		for _, entry in potatoes do
			if holderOf(entry, now) == me then
				return entry
			end
		end
		return nil
	end

	-- Everyone who could take `entry` from me now, with their root.
	local function takers(entry: Entry, now: number): { { Id: number, Root: BasePart } }
		local list = {}
		for _, person in api:Participants() do
			local id = person.UserId
			if id == me or person:GetAttribute("PP_Alive") == false then
				continue
			end
			if busy(id, now) or (id == entry.F and now < entry.N) or blown[id] or (backoff[id] or 0) > now then
				continue
			end
			local root = rootOf(person:Character())
			if root then
				table.insert(list, { Id = id, Root = root })
			end
		end
		return list
	end

	-- HUD ---------------------------------------------------------------------------------------------
	local hud = api:TopHud()
	local left = UIKit.Label({
		Name = "Left",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, api:HudY()),
		Size = UDim2.fromOffset(300, 38),
		Parent = hud,
		Children = { UIKit.TextStroke(0.15) },
	})
	local function refreshLeft()
		local count = api:Shared("Left")
		left.Text = if type(count) == "number" then `★ {count} LEFT` else ""
	end
	api:OnShared("Left", refreshLeft)
	refreshLeft()

	local banner = UIKit.Label({
		Name = "Banner",
		Text = "YOU HAVE THE POTATO! PASS IT!",
		Font = Theme.Fonts.Display,
		TextSize = 34,
		TextColor3 = Theme.Colors.Yellow,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, api:HudY() + 40),
		Size = UDim2.fromOffset(600, 44),
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0) },
	})
	local bannerScale = Instance.new("UIScale")
	bannerScale.Parent = banner

	-- The red screen edge while holding a potato: a faint vignette on the sides and bottom (none along
	-- the top bar), in its own screen layer under the HUD, the menu column and the buttons, so it never
	-- tints them or the status line and never takes a touch.
	local vignette = api:Track(UIKit.new("ScreenGui", {
		Name = "HotPotatoEdge",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		DisplayOrder = -1, -- under every HUD layer (the main HUD is 0)
		Enabled = false,
		Parent = localPlayer:WaitForChild("PlayerGui"),
	}))
	local edges: { Frame } = {}
	for _, side in { "Bottom", "Left", "Right" } do
		local vertical = side == "Left" or side == "Right"
		local edge = UIKit.new("Frame", {
			Name = "Edge" .. side,
			BackgroundColor3 = DANGER,
			BorderSizePixel = 0,
			Active = false,
			ZIndex = 0,
			Visible = false,
			AnchorPoint = Vector2.new(if side == "Right" then 1 else 0, if side == "Bottom" then 1 else 0),
			Position = UDim2.fromScale(if side == "Right" then 1 else 0, if side == "Bottom" then 1 else 0),
			Size = if vertical then UDim2.new(0, 48, 1, 0) else UDim2.new(1, 0, 0, 48),
			Parent = vignette,
		})
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = NumberSequence.new(0, 1)
		gradient.Rotation = ({ Bottom = -90, Left = 0, Right = 180 })[side]
		gradient.Parent = edge
		table.insert(edges, edge)
	end

	-- The THROW button and the ◆ over whoever it would go to.
	local throw = api:Button({ Text = "THROW", Key = Enum.KeyCode.E, Color = Theme.Colors.Orange })
	throw:SetVisible(false)
	local aimGui = UIKit.new("BillboardGui", {
		Name = "ThrowTarget",
		Size = UDim2.fromOffset(52, 52),
		StudsOffset = Vector3.new(0, 4, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Enabled = false,
		Parent = api.World,
	})
	UIKit.Label({
		Text = "◆",
		TextScaled = true,
		TextColor3 = Theme.Colors.Cyan,
		Size = UDim2.fromScale(1, 1),
		Parent = aimGui,
		Children = { UIKit.TextStroke(0) },
	})

	-- Potatoes on screen --------------------------------------------------------------------------------
	local template: Instance? = nil
	task.spawn(function()
		template = api:Template("HotPotatoSpud", 10)
	end)
	local puffTemplate: Instance? = nil
	task.spawn(function()
		puffTemplate = api:Template("HotPotatoPuff", 10)
	end)

	local visuals: { [number]: Visual } = {}
	-- A potato's model: the shared mesh, or (until it arrives, or if it never does) a plain spud-coloured
	-- ball, so whoever holds one is always shown, with its marker either way.
	local function newVisual(): Visual?
		local model: Model
		if template then
			model = template:Clone() :: Model
		else
			model = Instance.new("Model")
			local ball = Instance.new("Part")
			ball.Name = "Spud"
			ball.Shape = Enum.PartType.Ball
			ball.Size = Vector3.new(2.2, 2.2, 2.2)
			ball.Color = SPUD
			ball.Material = Enum.Material.SmoothPlastic
			ball.CFrame = CFrame.new(0, 1.1, 0)
			ball.Parent = model
			model.PrimaryPart = ball
			model.WorldPivot = CFrame.new()
		end
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.CastShadow = false
			end
		end
		model.Parent = api.World
		local spud = model:FindFirstChild("Spud", true) :: BasePart?
		local spark = model:FindFirstChild("Spark", true) :: BasePart?
		local light = Instance.new("PointLight")
		light.Color = HOT
		light.Range = 10
		light.Brightness = 0
		light.Parent = spark or spud or model.PrimaryPart
		local gui = UIKit.new("BillboardGui", {
			Name = "PotatoMarker",
			Size = UDim2.fromOffset(46, 46),
			StudsOffset = Vector3.new(0, 3.6, 0),
			AlwaysOnTop = true,
			LightInfluence = 0,
			Adornee = spud or model.PrimaryPart,
			Parent = model,
		})
		local marker = UIKit.Label({
			Text = "▼",
			TextScaled = true,
			TextColor3 = HOT,
			Size = UDim2.fromScale(1, 1),
			Parent = gui,
			Children = { UIKit.TextStroke(0) },
		})
		return {
			Model = model,
			Spud = spud,
			Spark = spark,
			Light = light,
			Marker = marker,
			Gui = gui,
			Fallback = template == nil,
		}
	end

	local function headPoint(userId: number): Vector3?
		local root = rootOf(api:CharacterOf(userId))
		return if root then root.Position + Vector3.new(0, 3.3, 0) else nil
	end

	-- Puffs flying out of a blast.
	local puffs: { { Model: Model, T: number, From: Vector3, To: Vector3, Size: number } } = {}
	local function blast(at: Vector3)
		api:Sound("Hit")
		if puffTemplate then
			for index = 1, if State.ReducedEffects() then 3 else 7 do
				local model = puffTemplate:Clone() :: Model
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") then
						part.Anchored = true
						part.CanCollide = false
						part.CanQuery = false
						part.CanTouch = false
						part.CastShadow = false
						if index <= 2 then
							part.Color = Color3.fromRGB(255, 190, 90)
						end
					end
				end
				model.Parent = api.World
				local angle = math.random() * math.pi * 2
				local out = Vector3.new(math.cos(angle), 0.4 + math.random() * 0.8, math.sin(angle))
				table.insert(puffs, {
					Model = model,
					T = 0,
					From = at,
					To = at + out * (4 + math.random() * 4),
					Size = 0.8 + math.random() * 0.8,
				})
			end
		else
			api:Effect("Poof", at)
		end
		local root = select(3, api:Character())
		if root and (root.Position - at).Magnitude < 30 and not State.ReducedEffects() then
			local camera = workspace.CurrentCamera
			for step = 1, 6 do
				task.delay(step * 0.03, function()
					camera.CFrame *= CFrame.Angles(
						math.rad(math.random(-10, 10) * 0.07),
						math.rad(math.random(-10, 10) * 0.07),
						0
					)
				end)
			end
		end
	end

	-- Cues ----------------------------------------------------------------------------------------------
	-- A refused pass: drop the prediction and leave that target alone for a moment, so a press the
	-- server keeps turning down (a big lag, someone the server already has out) isn't resent every
	-- frame with the potato flickering between the two.
	api:OnEvent("Refused", function(id, targetId)
		if type(id) == "number" then
			guesses[id] = nil
		end
		if type(targetId) == "number" then
			backoff[targetId] = api:Now() + 0.8
		end
	end)
	api:OnEvent("Pass", function(fromId, toId, _how, id)
		if type(id) == "number" then
			guesses[id] = nil
		end
		if toId == me then
			api:Sound("HazardWarning")
			UIKit.PopIn(banner, 0.25)
		elseif fromId == me then
			api:Sound("Boing")
		end
	end)
	api:OnEvent("Drop", function(list)
		if type(list) == "table" and table.find(list, me) then
			api:Sound("Pickup")
			UIKit.PopIn(banner, 0.25)
		end
	end)
	api:OnEvent("Boom", function(userId, x, y, z)
		if type(userId) == "number" and userId ~= 0 then
			blown[userId] = true
		end
		if type(x) == "number" and type(y) == "number" and type(z) == "number" then
			blast(Vector3.new(x, y, z))
		end
	end)

	-- Passing -------------------------------------------------------------------------------------------
	local lastSend = 0
	local lastThrow = 0
	local function canPass(entry: Entry, now: number): boolean
		return inRound() and now >= entry.L and guesses[entry.I] == nil and now - lastSend > 0.15
	end

	local function throwTarget(entry: Entry, now: number): (number?, BasePart?)
		local _, _, root = api:Character()
		if not root then
			return nil, nil
		end
		local look = root.CFrame.LookVector
		local cameraLook = workspace.CurrentCamera.CFrame.LookVector
		local best, bestRoot, bestDistance = nil, nil, math.huge
		for _, taker in takers(entry, now) do
			local at = taker.Root.Position
			local distance = flat(at - root.Position).Magnitude
			if distance > Rules.CLIENT_THROW or math.abs(at.Y - root.Position.Y) > Rules.REACH_UP then
				continue
			end
			if not Rules.InFront(root.Position, look, at) and not Rules.InFront(root.Position, cameraLook, at) then
				continue
			end
			if distance < bestDistance then
				best, bestRoot, bestDistance = taker.Id, taker.Root, distance
			end
		end
		return best, bestRoot
	end

	throw.Pressed:Connect(function()
		local now = api:Now()
		local entry = myPotato(now)
		-- (the server takes one throw per 0.25 s: a quicker one would be dropped without an answer)
		if not entry or not canPass(entry, now) or now - lastThrow < 0.27 then
			return
		end
		local target, targetRoot = throwTarget(entry, now)
		local _, humanoid, root = api:Character()
		if not target or not targetRoot or not root or not humanoid then
			return
		end
		local at = Vector3.new(targetRoot.Position.X, root.Position.Y, targetRoot.Position.Z)
		if flat(at - root.Position).Magnitude > 0.1 then
			root.CFrame = CFrame.lookAt(root.Position, at)
		end
		lastSend = now
		lastThrow = now
		guesses[entry.I] = {
			To = target,
			Until = now + Rules.FLIGHT + 1,
			Throw = true,
			T0 = now,
			From = root.Position + Vector3.new(0, 3.3, 0),
		}
		api:Action("Throw", target)
		api:Sound("Boing")
	end)

	-- Every frame -------------------------------------------------------------------------------------
	local beepAt = 0
	local hintUntil = 0
	local shownHint = ""
	api:RenderStep(function(dt)
		local now = api:Now()
		-- How to play, for the first seconds of the round (under the holder's banner).
		if hintUntil == 0 and State.Phase() == "InRound" then
			hintUntil = now + 8
		end
		local hint = if hintUntil > 0
				and now < hintUntil
				and api:CanAct()
				and myPotato(now) == nil
			then "Run from the ▼ potato!"
			else ""
		if hint ~= shownHint then
			shownHint = hint
			api:Hint(hint, api:HudY() + 40)
		end
		local mine = myPotato(now)
		local holding = mine ~= nil and inRound()

		-- Tags: whoever I touch takes it.
		if mine and canPass(mine, now) then
			local _, _, root = api:Character()
			if root then
				local best, bestDistance = nil, math.huge
				for _, taker in takers(mine, now) do
					local at = taker.Root.Position
					if Rules.Reaches(root.Position, at, Rules.CLIENT_TAG) then
						local distance = flat(at - root.Position).Magnitude
						if distance < bestDistance then
							best, bestDistance = taker.Id, distance
						end
					end
				end
				if best then
					lastSend = now
					guesses[mine.I] = { To = best, Until = now + 1, Throw = false, T0 = now }
					api:Action("Tag", best)
				end
			end
		end

		-- The holder's HUD.
		local warned = mine ~= nil and mine.W ~= nil and now >= (mine.W :: number)
		banner.Visible = holding
		throw:SetVisible(holding)
		local pulse = 0.5 + 0.5 * math.sin(now * (if warned then 18 else 8))
		if holding then
			bannerScale.Scale = 1 + 0.06 * pulse
			banner.TextColor3 = if warned then DANGER:Lerp(Color3.new(1, 1, 1), pulse * 0.5) else Theme.Colors.Yellow
			banner.Text = if warned then "!! IT'S ABOUT TO BLOW! PASS IT !!" else "YOU HAVE THE POTATO! PASS IT!"
		end
		vignette.Enabled = holding
		for _, edge in edges do
			edge.Visible = holding
			-- Never more opaque than 0.55 (and the gradient fades it out toward the middle).
			edge.BackgroundTransparency = if warned then 0.45 + 0.3 * pulse else 0.6 + 0.25 * pulse
		end
		local target, targetRoot = nil, nil
		if holding and mine and now >= mine.L and guesses[mine.I] == nil then
			target, targetRoot = throwTarget(mine, now)
		end
		throw:SetEnabled(target ~= nil)
		aimGui.Adornee = targetRoot
		aimGui.Enabled = targetRoot ~= nil
		if holding and warned and mine and now >= beepAt then
			api:Sound("Countdown")
			local left = math.max(mine.W :: number + Rules.WARN - now, 0)
			beepAt = now + math.clamp(left / 6, 0.12, 0.5)
		end

		-- Draw every potato.
		local seen = {}
		for _, entry in potatoes do
			seen[entry.I] = true
			local visual = visuals[entry.I]
			if visual and visual.Fallback and template then
				visual.Model:Destroy() -- the mesh has arrived: swap the stand-in ball for it
				visual = nil
				visuals[entry.I] = nil
			end
			if not visual then
				local made = newVisual()
				if not made then
					continue
				end
				visual = made
				visuals[entry.I] = made
			end
			local guess = guesses[entry.I]
			local position: Vector3? = nil
			if guess and now < guess.Until and guess.Throw and guess.From then
				local to = headPoint(guess.To) or guess.From
				position = Rules.Arc(guess.From, to, (now - guess.T0) / Rules.FLIGHT)
			elseif not (guess and now < guess.Until) and entry.Fl then
				local flight = entry.Fl
				local p = flight.P
				local from = Vector3.new(p[1], p[2], p[3])
				local to = headPoint(flight.B) or from
				position = Rules.Arc(from, to, (now - flight.T0) / math.max(flight.T1 - flight.T0, 0.05))
			else
				local holder = holderOf(entry, now)
				local head = if holder ~= 0 then headPoint(holder) else nil
				if head then
					position = head + Vector3.new(0, 0.3 + 0.25 * math.sin(now * 6 + entry.I), 0)
				end
			end
			local hot = entry.W ~= nil and now >= (entry.W :: number)
			visual.Model.Parent = if position then api.World else nil
			if position then
				visual.Model:PivotTo(
					CFrame.new(position) * CFrame.Angles(0, now * 2.5 + entry.I, math.sin(now * 5) * 0.15)
				)
			end
			local blink = 0.5 + 0.5 * math.sin(now * (if hot then 20 else 4))
			if visual.Spud then
				visual.Spud.Color = if hot then SPUD:Lerp(DANGER, 0.4 + 0.5 * blink) else SPUD
			end
			if visual.Spark then
				visual.Spark.Transparency = 0.3 * (1 - blink)
			end
			visual.Light.Brightness = if hot then 2 + 3 * blink else 0.6
			visual.Marker.Text = if hot then "!!" else "▼"
			visual.Marker.TextColor3 = if hot then DANGER else HOT
		end
		for id, visual in visuals do
			if not seen[id] then
				visual.Model:Destroy()
				visuals[id] = nil
			end
		end

		-- Blast puffs.
		for index = #puffs, 1, -1 do
			local puff = puffs[index]
			puff.T += dt
			local t = puff.T / 0.9
			if t >= 1 then
				puff.Model:Destroy()
				table.remove(puffs, index)
				continue
			end
			local ease = 1 - (1 - t) ^ 3
			puff.Model:PivotTo(CFrame.new(puff.From:Lerp(puff.To, ease)))
			puff.Model:ScaleTo(math.max(0.05, puff.Size * (0.4 + ease)))
			for _, part in puff.Model:GetDescendants() do
				if part:IsA("BasePart") then
					part.Transparency = t ^ 2
				end
			end
		end
	end)
end

return HotPotato
