-- Client half of Trace Race: the chase camera behind your crayon, your steering, everyone's crayons,
-- riders and drawn lines, and the HUD (your accuracy, how far you are, which way to steer).
--
-- The server shares the course ("Layout": the guide's pieces and who rides which lane) and the
-- ride's clock ("Race": T0, T1). A crayon's distance down its lane comes from that clock alone, so
-- this client only steers your crayon sideways (MOVE stick, A / D, arrow keys, gamepad), samples it
-- every Rules.SAMPLE_GAP and sends those positions ("Trace") together with any the server hasn't
-- relayed back yet (a lost batch never turns a curve into a shortcut). The server relays every
-- position it takes ("Trails"); other riders' crayons follow their relayed line (a little behind,
-- eased forward so they glide), and every line is drawn as straight strokes between positions, the
-- way the server scores it. Your accuracy on the HUD comes from the same Tracker the server uses.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Rules = require(ReplicatedStorage.Shared.Logic.TraceRace)

local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local TraceRace = {}

local TIP = 6.37 -- the crayon prop's pivot behind its tip (server: TIP)
local SEAT = CFrame.new(0, 4.35 + 3, 7.5) -- a rider's root from the crayon's tip (server: SEAT)
local SEND_EVERY = 0.1
local LATE_SEND = 0.6 -- keep sending unconfirmed positions this long after the ride
local LINE_HEIGHT = 0.08
local MERGE_ANGLE = math.cos(math.rad(0.8)) -- strokes this close to straight join into one part

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

type Rider = {
	User: number,
	Index: number,
	Color: Color3,
	ColorName: string,
	Frame: CFrame,
	Samples: { number }, -- flat { t, x, ... } in order
	LastT: number,
	Drawn: { number }?, -- the last drawn point { s, x }
	Stroke: Part?, -- the last stroke part (extended while the line runs straight)
	StrokeFrom: { number }?,
	StrokeCount: number,
	Live: Part?, -- the stroke from the last relayed point to the crayon's tip
	X: number,
	V: number,
	Crayon: Model?,
	Left: boolean,
}

function TraceRace.Start(api)
	api:Mood({ Tint = rgb(255, 250, 240), Saturation = 0.12, Contrast = 0.04 })
	local layout = api:SharedJSON("Layout")
	local waited = 0
	while not layout and waited < 10 do
		waited += task.wait(0.1)
		layout = api:SharedJSON("Layout")
	end
	if type(layout) ~= "table" or type(layout.Pieces) ~= "table" or type(layout.Lanes) ~= "table" then
		return
	end
	local course = Rules.Build(layout.Pieces)
	local paperY = layout.Y
	local touch = api:IsTouch()
	local myId = api.Player.UserId
	local world = api.World

	local riders: { [number]: Rider } = {}
	for _, entry in layout.Lanes do
		local info = Rules.Colors[entry.C] or Rules.Colors[1]
		local x = layout.X + (entry.I - (layout.Count + 1) / 2) * Rules.LANE
		riders[entry.U] = {
			User = entry.U,
			Index = entry.I,
			Color = info.Color,
			ColorName = info.Name,
			Frame = CFrame.new(x, paperY, layout.Z),
			Samples = {},
			LastT = -math.huge,
			Drawn = { 0, 0 },
			StrokeCount = 0,
			X = 0,
			V = 0,
			Left = false,
		}
	end
	local mine = riders[myId]
	local playing = mine ~= nil and api:Alive()
	local race: { T0: number, T1: number }? = nil

	local function tipFrame(rider: Rider, s: number, x: number): CFrame
		return rider.Frame * CFrame.new(x, 0, -s)
	end

	-- Lines ------------------------------------------------------------------------------------------
	local lines = Instance.new("Folder")
	lines.Name = "TraceRaceLines"
	lines.Parent = world

	local function strokePart(rider: Rider): Part
		local part = Instance.new("Part")
		part.Name = "Line"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Color = rider.Color
		part.Parent = lines
		return part
	end

	-- Places a stroke from (s0, x0) to (s1, x1) on the rider's lane (a hair higher every other one, so
	-- overlapping ends never flicker).
	local function placeStroke(rider: Rider, part: BasePart, a: { number }, b: { number }, lift: number)
		local pa = tipFrame(rider, a[1], a[2]).Position
		local pb = tipFrame(rider, b[1], b[2]).Position
		local span = (pb - pa).Magnitude
		local y = 0.06 + lift
		part.Size = Vector3.new(Rules.LINE_WIDTH, LINE_HEIGHT, span + Rules.LINE_WIDTH * 0.6)
		if span < 1e-3 then
			part.CFrame = CFrame.new(pa + Vector3.new(0, y, 0))
		else
			part.CFrame = CFrame.lookAt(pa, pb) * CFrame.new(0, y, -span / 2)
		end
	end

	-- The line goes on to (s, x): a new stroke, or the last one longer if it runs on straight.
	local function draw(rider: Rider, s: number, x: number)
		local from = rider.Drawn
		if not from or s <= from[1] + 0.05 then
			return
		end
		local point = { s, x }
		local stroke, start = rider.Stroke, rider.StrokeFrom
		if stroke and start then
			local d1 = Vector2.new(from[1] - start[1], from[2] - start[2])
			local d2 = Vector2.new(s - from[1], x - from[2])
			if d1.Magnitude > 1e-3 and d1.Unit:Dot(d2.Unit) >= MERGE_ANGLE and d1.Magnitude < 40 then
				placeStroke(rider, stroke, start, point, (rider.StrokeCount % 2) * 0.004)
				rider.Drawn = point
				return
			end
		end
		local part = strokePart(rider)
		rider.StrokeCount += 1
		placeStroke(rider, part, from, point, (rider.StrokeCount % 2) * 0.004)
		rider.Stroke = part
		rider.StrokeFrom = from
		rider.Drawn = point
	end

	-- Steering -----------------------------------------------------------------------------------------
	local controls = nil
	pcall(function()
		local scripts = api.Player:FindFirstChild("PlayerScripts")
		local module = scripts and scripts:FindFirstChild("PlayerModule")
		if module then
			controls = (require(module :: any) :: any):GetControls()
		end
	end)
	local function steerInput(): number
		local keys = 0
		pcall(function()
			if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
				keys += 1
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
				keys -= 1
			end
		end)
		if keys ~= 0 then
			return keys
		end
		if controls then
			local ok, value = pcall(controls.GetMoveVector, controls)
			if ok and typeof(value) == "Vector3" and math.abs(value.X) > 0.08 then
				return math.clamp(value.X, -1, 1)
			end
		end
		return 0
	end

	local tracker = Rules.Tracker(course) -- what this screen shows: the server's own scoring
	local recent: { number } = {} -- my positions, flat { t, x, ... }
	local confirmed = -math.huge -- the newest of my positions the server relayed back
	local lastSample = -math.huge
	local lastSend = 0
	local myX, myV = 0, 0

	local function flush(now: number)
		if not race or now - lastSend < SEND_EVERY or now > race.T1 + LATE_SEND then
			return
		end
		local batch = {}
		for at = 1, #recent - 1, 2 do
			if recent[at] > confirmed + 1e-4 then
				table.insert(batch, recent[at])
				table.insert(batch, recent[at + 1])
				if #batch >= Rules.MAX_CHUNK * 2 then
					break
				end
			end
		end
		if #batch > 0 then
			api:Action("Trace", batch)
			lastSend = now
		end
	end

	-- Shared state and relays --------------------------------------------------------------------------
	local function onRace()
		local data = api:SharedJSON("Race")
		if type(data) == "table" and type(data.T0) == "number" and type(data.T1) == "number" then
			race = { T0 = data.T0, T1 = data.T1 }
			if mine then
				mine.LastT = data.T0 - Rules.SAMPLE_GAP
			end
		end
	end
	api:OnShared("Race", onRace)
	onRace()

	api:OnEvent("Trails", function(relay: any)
		if type(relay) ~= "table" or not race then
			return
		end
		local t0 = race.T0
		for key, flat in relay do
			local rider = riders[tonumber(key) or 0]
			if not rider or type(flat) ~= "table" then
				continue
			end
			for at = 1, #flat - 1, 2 do
				local t, x = flat[at], flat[at + 1]
				if type(t) ~= "number" or type(x) ~= "number" then
					continue
				end
				if rider == mine then
					confirmed = math.max(confirmed, t)
				elseif t > rider.LastT then
					rider.LastT = t
					table.insert(rider.Samples, t)
					table.insert(rider.Samples, x)
					draw(rider, (t - t0) * Rules.SPEED, x)
				end
			end
		end
		-- Forget what the server confirmed.
		if #recent > 400 then
			local keep = {}
			for at = 1, #recent - 1, 2 do
				if recent[at] > confirmed then
					table.insert(keep, recent[at])
					table.insert(keep, recent[at + 1])
				end
			end
			recent = keep
		end
	end)

	api:OnEvent("Left", function(userId: number)
		local rider = riders[userId]
		if rider then
			rider.Left = true
			if rider.Live then
				rider.Live:Destroy()
				rider.Live = nil
			end
		end
	end)

	-- HUD -----------------------------------------------------------------------------------------------
	local hud = api:TopHud()
	local hudY = api:HudY()
	local hintY = hudY + (if touch then 80 else 94)
	local panelW = if touch then 250 else 300
	local panel = UIKit.Panel({
		Name = "TraceRacePanel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, hudY),
		Size = UDim2.fromOffset(panelW, if touch then 74 else 86),
		BackgroundTransparency = 0.1,
		Visible = playing,
		Parent = hud,
	})
	local accuracy = UIKit.Label({
		Name = "Accuracy",
		Text = "100%",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 34 else 40,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(14, 4),
		Size = UDim2.new(0.5, -14, 0, if touch then 40 else 46),
		Parent = panel,
		Children = { UIKit.TextStroke(0.3) },
	})
	local state = UIKit.Label({
		Name = "OnLine",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 20 else 24,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.new(0.5, -14, 0, if touch then 36 else 42),
		Parent = panel,
		Children = { UIKit.TextStroke(0.3) },
	})
	local track = UIKit.new("Frame", {
		Name = "Progress",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -28, 0, 12),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BorderSizePixel = 0,
		Parent = panel,
	}, { UIKit.Round() })
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = if mine then mine.Color else Theme.Colors.Cyan,
		BorderSizePixel = 0,
		Parent = track,
	}, { UIKit.Round() })
	UIKit.Label({
		Name = "Flag",
		Text = "🏁",
		TextSize = 18,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(22, 22),
		Parent = track,
	})
	-- The arrow towards the guide when you drift off it (shape and word, not just colour).
	local steer = UIKit.Label({
		Name = "Steer",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 30 else 36,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, hintY),
		Size = UDim2.fromOffset(260, 40),
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0.15) },
	})

	if playing then
		api:Hint(
			if touch
				then "Steer with the MOVE stick: stay on the dotted line!"
				else "Steer with A / D: stay on the dotted line!",
			hintY
		)
		task.delay(5, function()
			api:Hint("")
		end)
	end

	local finalShown = false
	api:OnEvent("Final", function(results: any)
		if type(results) ~= "table" then
			return
		end
		finalShown = true
		local mineScore = tonumber(results[tostring(myId)])
		if not mineScore then
			return
		end
		local place = 1
		for _, score in results do
			if type(score) == "number" and score > mineScore then
				place += 1
			end
		end
		local suffix = if place == 1 then "st" elseif place == 2 then "nd" elseif place == 3 then "rd" else "th"
		accuracy.Text = `{math.floor(mineScore + 0.5)}%`
		state.Text = `🏆 {place}{suffix}`
		steer.Visible = false
		api:Hint(if place == 1 then "The most accurate line!" else "Ride's over: look at your line!", hintY)
		api:Sound(if place == 1 then "Victory" else "Pickup")
		UIKit.PopIn(panel, 0.25)
	end)

	-- Camera ---------------------------------------------------------------------------------------------
	local camera = workspace.CurrentCamera
	local savedType, savedFov = camera.CameraType, camera.FieldOfView
	local cameraX = 0
	local cameraUp = 0
	if playing then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 62
		api:Track(function()
			camera.CameraType = savedType
			camera.FieldOfView = savedFov
			local _, humanoid, root = api:Character()
			if humanoid then
				humanoid.PlatformStand = false
				camera.CameraSubject = humanoid
			end
			if root then
				root.AssemblyLinearVelocity = Vector3.zero
			end
		end)
	end

	-- Crayons are the server's models (tagged with their rider); this client moves them smoothly.
	local function findCrayons()
		for _, model in CollectionService:GetTagged("TraceRaceCrayon") do
			local user = model:GetAttribute("TraceRaceUser")
			local rider = type(user) == "number" and riders[user]
			if rider and model:IsA("Model") then
				rider.Crayon = model
			end
		end
	end
	findCrayons()
	api:Track(CollectionService:GetInstanceAddedSignal("TraceRaceCrayon"):Connect(findCrayons))

	-- Every frame ------------------------------------------------------------------------------------------
	local lastState = ""
	local finished = false
	api:RenderStep(function(dt)
		dt = math.min(dt, 0.1)
		local now = api:Now()
		local t0 = if race then race.T0 else math.huge
		local t1 = if race then race.T1 else math.huge
		local s = if race then math.clamp((now - t0) * Rules.SPEED, 0, course.Length) else 0

		-- My crayon: steer while the ride is on, sample it, send it.
		if mine and playing and race then
			if now >= t0 and now <= t1 then
				local want = steerInput() * Rules.STEER
				myV += (want - myV) * (1 - math.exp(-dt * 16))
				myV = math.clamp(myV, -Rules.STEER, Rules.STEER)
				myX = math.clamp(myX + myV * dt, -Rules.LIMIT, Rules.LIMIT)
				if now - lastSample >= Rules.SAMPLE_GAP then
					lastSample = now
					-- (Never further than the server lets the crayon steer since the last position.)
					local lastT = if #recent >= 2 then recent[#recent - 1] else t0 - Rules.SAMPLE_GAP
					local lastX = if #recent >= 2 then recent[#recent] else 0
					local reach = Rules.STEER * (now - lastT)
					local x = math.clamp(myX, lastX - reach, lastX + reach)
					table.insert(recent, now)
					table.insert(recent, x)
					tracker:Add((now - t0) * Rules.SPEED, x)
					draw(mine, (now - t0) * Rules.SPEED, x)
				end
			else
				myV = 0
				if now > t1 and not finished then
					finished = true
					api:Sound("Click")
				end
			end
			mine.X, mine.V = myX, myV
			flush(now)
		end

		-- Everyone's crayon, rider and the live stroke to the tip.
		for user, rider in riders do
			if rider.Left then
				continue
			end
			if rider ~= mine then
				-- Follow the relayed line: its last position, carried on at its last sideways speed for
				-- a moment, eased so the crayon glides.
				local samples = rider.Samples
				local n = #samples
				local target = rider.X
				if n >= 2 then
					local tl, xl = samples[n - 1], samples[n]
					local v = 0
					if n >= 4 and tl - samples[n - 3] > 1e-3 then
						v = (xl - samples[n - 2]) / (tl - samples[n - 3])
					end
					target = math.clamp(xl + v * math.clamp(now - tl, 0, 0.25), -Rules.LIMIT, Rules.LIMIT)
				end
				local before = rider.X
				rider.X += (target - rider.X) * (1 - math.exp(-dt * 12))
				rider.V += ((rider.X - before) / math.max(dt, 1e-3) - rider.V) * (1 - math.exp(-dt * 8))
			end
			local tip = tipFrame(rider, s, rider.X)
			local yaw = if race and now >= t0 and now <= t1 then -math.atan2(rider.V, Rules.SPEED) else 0
			local turned = tip * CFrame.Angles(0, yaw, 0)
			local crayon = rider.Crayon
			if crayon and crayon.Parent then
				crayon:PivotTo(turned * CFrame.new(0, 0, TIP))
			end
			-- The stroke from the last drawn point to the tip.
			local drawn = rider.Drawn
			if race and drawn and now >= t0 then
				local live = rider.Live
				if not live then
					live = strokePart(rider)
					rider.Live = live
				end
				placeStroke(rider, live :: Part, drawn, { s, rider.X }, 0.002)
			end
			-- The rider stands on the crayon's back.
			local character = api:CharacterOf(user)
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if character and root then
				if rider == mine then
					local humanoid = character:FindFirstChildOfClass("Humanoid")
					if humanoid and playing and not humanoid.PlatformStand then
						humanoid.PlatformStand = true
					end
					root.AssemblyLinearVelocity = Vector3.new(rider.V, 0, if race and now < t1 then -Rules.SPEED else 0)
					root.AssemblyAngularVelocity = Vector3.zero
				end
				if rider ~= mine or playing then
					root.CFrame = turned * SEAT
				end
			end
		end

		-- Chase camera behind my crayon: the guide scrolls at you.
		if mine and playing then
			cameraX += (myX * 0.55 - cameraX) * (1 - math.exp(-dt * 5))
			if race and now > t1 + 0.4 then
				cameraUp += (1 - cameraUp) * (1 - math.exp(-dt * 1.2))
			end
			local eye = mine.Frame * Vector3.new(cameraX, 12 + cameraUp * 22, -s + 19 + cameraUp * 16)
			local look = mine.Frame * Vector3.new(cameraX * 0.7, 0, -s - 22 + cameraUp * 6)
			camera.CFrame = CFrame.lookAt(eye, look)
		end

		-- HUD: accuracy, on the line or not, progress, which way to steer.
		if mine and playing and not finalShown then
			fill.Size = UDim2.fromScale(if course.Length > 0 then s / course.Length else 0, 1)
			if race and now >= t0 then
				accuracy.Text = `{tracker:Live()}%`
				local off = Rules.Distance(course, s, myX)
				local key
				if now > t1 then
					key = "Done"
				elseif off <= Rules.FULL then
					key = "On"
				elseif off <= 2.2 then
					key = "Close"
				else
					key = "Off"
				end
				if key ~= lastState then
					lastState = key
					if key == "On" then
						state.Text = "✓ ON THE LINE"
						state.TextColor3 = Theme.Colors.Green
					elseif key == "Close" then
						state.Text = "~ CLOSE"
						state.TextColor3 = Theme.Colors.Yellow
					elseif key == "Off" then
						state.Text = "✗ OFF!"
						state.TextColor3 = Theme.Colors.Red
					else
						state.Text = "🏁 FINISHED"
						state.TextColor3 = Theme.Colors.Text
					end
				end
				local guide = Rules.GuideAt(course, s + Rules.SPEED * 0.15)
				if key == "Off" or (key == "Close" and math.abs(guide - myX) > 1.6) then
					steer.Visible = true
					steer.Text = if guide < myX then "◀◀ STEER LEFT" else "STEER RIGHT ▶▶"
					steer.TextColor3 = if key == "Off" then Theme.Colors.Red else Theme.Colors.Yellow
				else
					steer.Visible = false
				end
			else
				state.Text = "GET READY"
				state.TextColor3 = Theme.Colors.TextDim
			end
		end
	end)
end

return TraceRace
