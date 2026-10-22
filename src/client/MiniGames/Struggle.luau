-- Client half of Struggle: draws everyone's foam bat (from the server's Wind / Strike / Hit cues; your
-- own swings the moment you press), the loose orbs (shared state "Orbs" plus Drop / Take events), a
-- shape-and-count tag over every head, and the HUD: your orbs, the leader, and the SWING button
-- (hold to charge; E or a click on PC, beside the jump button on phones).
--
-- Everyone has a colour and a shape (● ■ ▲ ◆ ★ ...; Shared/Logic/Struggle SLOTS): their orbs are that
-- shape in that colour, and the tags and HUD draw the same shape, so colour is never the only cue.
-- The shapes are built from UI frames or from glyphs Roblox's fonts draw everywhere.
--
-- A wind-up is visible to everyone: the bat goes back over the shoulder and the swing's reach shows on
-- the sand exactly as the server judges it (a fan of +-ARC out to RANGE, and the small CLOSE circle:
-- any part of you inside is hit). It grows while a charge builds; a charged bat glows and is drawn
-- longer, out to RANGE_CHARGED. So you can see a hit coming and step out of it.
--
-- Your own press draws your swing at once, but only when the server will take it: not during the
-- 3-2-1, the wait after a swing or while you're knocked down; if the server still turns it down it
-- says so ("Refused") and the swing is dropped. A charge held to the end is let go by the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local GameState = require(ReplicatedStorage.Shared.GameState)
local Rules = require(ReplicatedStorage.Shared.Logic.Struggle)

local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local Struggle = {}

local REST_BACK = 0.3 -- seconds the bat takes back to rest after a strike
local FLY = 0.25 -- seconds a picked-up orb takes to fly to its taker
local ORB_SCALE = 1.25 -- orbs are drawn a little bigger than their meshes (easy to spot on phones)

-- Bat poses in the holder's root space (the bat's pivot is the knob; it points along its +Y).
local REST = CFrame.new(1.05, -0.1, -0.35) * CFrame.Angles(math.rad(55), 0, math.rad(-12))
local WIND = CFrame.new(1.25, 0.55, 0.15) * CFrame.Angles(math.rad(105), math.rad(-25), math.rad(-35))
-- The strike sweeps the bat through exactly the rule's arc (+-ARC), its knob 0.4 in front of the
-- swinger's middle, so the tip passes RANGE out (RANGE_CHARGED with the longer charged bat).
local SWEEP_FROM, SWEEP_TO = -Rules.ARC, Rules.ARC

local function sweepPose(yaw: number): CFrame
	return CFrame.new(0, 0.15, -0.4) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(-90), 0, 0)
end

local function partsOf(model: Instance): { BasePart }
	local list = {}
	if model:IsA("BasePart") then
		table.insert(list, model)
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(list, descendant)
		end
	end
	return list
end

-- Scales a copy of a shared model by `factor` from the size it was shared at (MeshLibrary may have
-- scaled the template to its canonical height already, so ScaleTo's 1 isn't always "as shipped").
local function scaleBy(model: Model, factor: number)
	local base = model:GetAttribute("PP_BaseScale")
	if type(base) ~= "number" then
		base = model:GetScale()
		model:SetAttribute("PP_BaseScale", base)
	end
	model:ScaleTo((base :: number) * factor)
end

local function quiet(model: Instance)
	for _, part in partsOf(model) do
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
	end
end

-- A slot's shape as UI: frames for the plain shapes, glyphs that every Roblox font draws for the rest.
local function shapeIcon(slotIndex: number, size: number, parent: Instance?): Frame
	local slot = Rules.SLOTS[slotIndex] or Rules.SLOTS[1]
	local color = slot.Color
	local holder = UIKit.new("Frame", {
		Name = "Shape",
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local function piece(w: number, h: number, rotation: number, round: boolean?, hollow: boolean?): Frame
		local frame = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(w, h),
			Rotation = rotation,
			BackgroundColor3 = color,
			BackgroundTransparency = if hollow then 1 else 0,
			BorderSizePixel = 0,
			Parent = holder,
		})
		local corner = Instance.new("UICorner")
		corner.CornerRadius = if round then UDim.new(0.5, 0) else UDim.new(0.12, 0)
		corner.Parent = frame
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		if hollow then
			stroke.Color = color
			stroke.Thickness = math.max(2, size * 0.14)
		else
			stroke.Color = Color3.fromRGB(20, 16, 30)
			stroke.Thickness = math.max(1, size * 0.05)
		end
		stroke.Parent = frame
		return frame
	end
	local function glyph(text: string)
		UIKit.Label({
			Text = text,
			Font = Theme.Fonts.Bold,
			TextScaled = true,
			TextColor3 = color,
			Size = UDim2.fromScale(1.15, 1.15),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Parent = holder,
			Children = { UIKit.TextStroke(0.2) },
		})
	end
	local name = slot.Name
	if name == "Ball" then
		piece(0.86, 0.86, 0, true)
	elseif name == "Cube" then
		piece(0.76, 0.76, 0)
	elseif name == "Pyramid" then
		glyph("▲")
	elseif name == "Diamond" then
		piece(0.6, 0.6, 45)
	elseif name == "Star" then
		glyph("★")
	elseif name == "Ring" then
		piece(0.7, 0.7, 0, true, true)
	elseif name == "Plus" then
		piece(0.9, 0.28, 0)
		piece(0.28, 0.9, 0)
	elseif name == "Cross" then
		piece(0.95, 0.26, 45)
		piece(0.95, 0.26, -45)
	elseif name == "Cone" then
		glyph("▼")
	elseif name == "Frame" then
		piece(0.66, 0.66, 0, false, true)
	elseif name == "Pill" then
		piece(0.95, 0.46, 0, true)
	else -- Kite
		piece(0.52, 0.52, 45, false, true)
	end
	return holder
end

function Struggle.Start(api)
	api:Mood({
		Tint = Color3.fromRGB(255, 226, 196),
		Saturation = 0.12,
		Contrast = 0.06,
		Haze = Color3.fromRGB(255, 168, 120),
		HazeDecay = Color3.fromRGB(190, 110, 100),
		Density = 0.32,
	})
	local touch = api:IsTouch()
	local localPlayer = game:GetService("Players").LocalPlayer
	local myId = if localPlayer then localPlayer.UserId else 0

	-- Models the server shared (looked up when first needed, so nothing here waits for them).
	local templates: { [string]: Instance } = {}
	local function template(name: string): Instance?
		local found = templates[name]
		if not found then
			local folder = ReplicatedStorage:FindFirstChild("MiniGameAssets")
			local shared = folder and folder:FindFirstChild(name)
			if shared then
				found = shared:Clone()
				templates[name] = found :: Instance
			end
		end
		return found
	end

	-- Round state from the server ---------------------------------------------------------------
	local center: Vector3? = nil
	local slots: { [number]: number } = {} -- UserId -> slot
	local held: { [number]: { number } } = {} -- UserId -> { orbs, hits }
	local function readField()
		local field = api:SharedJSON("Field")
		if type(field) == "table" and type(field.Center) == "table" then
			center = Vector3.new(field.Center[1], field.Center[2], field.Center[3])
		end
	end
	readField()
	api:OnShared("Field", readField)

	-- Swings: UserId -> { Wind = t, Strike = t?, Charged = bool }
	local swings: { [number]: { Wind: number, Strike: number?, Charged: boolean } } = {}
	local safeUntil: { [number]: number } = {}

	-- Bats and head tags ---------------------------------------------------------------------------
	type Gear = {
		Bat: Model?,
		Foam: { BasePart },
		Disc: Part,
		Fan: Model?,
		BatScale: number,
		Tag: BillboardGui,
		Count: TextLabel,
		Slot: number,
	}
	local gear: { [number]: Gear } = {}

	local function dropGear(userId: number)
		local entry = gear[userId]
		if entry then
			if entry.Bat then
				entry.Bat:Destroy()
			end
			entry.Disc:Destroy()
			if entry.Fan then
				entry.Fan:Destroy()
			end
			entry.Tag:Destroy()
			gear[userId] = nil
		end
	end

	-- A bat in the slot's colour (nil until the server's template has arrived).
	local function makeBat(slotIndex: number): (Model?, { BasePart })
		local slot = Rules.SLOTS[slotIndex] or Rules.SLOTS[1]
		local foam = {}
		local batTemplate = template("StruggleBat")
		if not batTemplate then
			return nil, foam
		end
		local copy = batTemplate:Clone()
		quiet(copy)
		for _, part in partsOf(copy) do
			if part.Name == "Foam" then
				part.Color = slot.Color
				table.insert(foam, part)
			end
		end
		copy.Parent = api.World
		return copy :: Model, foam
	end

	-- The reach fan on the sand (radius 1 as shipped; scaled to the swing's RANGE when drawn).
	local function makeFan(slotIndex: number): Model?
		local fanTemplate = template("StruggleReach")
		if not fanTemplate then
			return nil
		end
		local copy = fanTemplate:Clone() :: Model
		quiet(copy)
		-- Its radius as shared (MeshLibrary may have rescaled the thin mesh), to scale it exactly.
		local _, size = copy:GetBoundingBox()
		copy:SetAttribute("PP_Radius", math.max(size.Z, 0.01))
		for _, part in partsOf(copy) do
			part.Color = (Rules.SLOTS[slotIndex] or Rules.SLOTS[1]).Color
			part.Material = Enum.Material.Neon
			part.Transparency = 1
		end
		copy.Parent = api.World
		return copy
	end

	local function makeGear(userId: number, slotIndex: number): Gear
		local slot = Rules.SLOTS[slotIndex] or Rules.SLOTS[1]
		local bat, foam = makeBat(slotIndex)
		local disc = Instance.new("Part")
		disc.Name = "Reach"
		disc.Shape = Enum.PartType.Cylinder
		disc.Size = Vector3.new(0.05, 1, 1)
		disc.Material = Enum.Material.Neon
		disc.Color = slot.Color
		disc.Transparency = 1
		disc.Anchored = true
		disc.CanCollide = false
		disc.CanQuery = false
		disc.CanTouch = false
		disc.CastShadow = false
		disc.Parent = api.World
		local tag = Instance.new("BillboardGui")
		tag.Name = "OrbTag"
		tag.Size = UDim2.fromOffset(96, 40)
		tag.StudsOffset = Vector3.new(0, 3.6, 0)
		tag.MaxDistance = 110
		tag.LightInfluence = 0
		tag.AlwaysOnTop = false
		tag.Parent = api.World
		local icon = shapeIcon(slotIndex, 30, tag)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 6, 0.5, 0)
		local count = UIKit.Label({
			Name = "Count",
			Text = "",
			Font = Theme.Fonts.Display,
			TextSize = 30,
			TextXAlignment = Enum.TextXAlignment.Left,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 42, 0.5, 0),
			Size = UDim2.new(1, -42, 1, 0),
			Parent = tag,
			Children = { UIKit.TextStroke(0.1) },
		})
		local entry: Gear = {
			Bat = bat,
			Foam = foam,
			Disc = disc,
			Fan = makeFan(slotIndex),
			BatScale = 1,
			Tag = tag,
			Count = count,
			Slot = slotIndex,
		}
		gear[userId] = entry
		return entry
	end

	-- HUD ------------------------------------------------------------------------------------------
	local hud = api:TopHud()
	local y = api:HudY()
	local pillWidth = if touch then 250 else 230
	local function pill(name: string, x: number): Frame
		return UIKit.new("Frame", {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, x, 0, y),
			Size = UDim2.fromOffset(pillWidth, 56),
			BackgroundColor3 = Theme.Colors.PanelDark,
			BackgroundTransparency = 0.2,
			Parent = hud,
			Children = { UIKit.Round(), UIKit.Stroke(Color3.new(1, 1, 1), 2, 0.4) },
		})
	end
	local minePill = pill("Mine", -(pillWidth / 2 + 6))
	local leadPill = pill("Lead", pillWidth / 2 + 6)
	local mineIcon: Frame? = nil
	local mineCount = UIKit.Label({
		Name = "Count",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 36,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(58, 0),
		Size = UDim2.new(1, -64, 1, 0),
		Parent = minePill,
		Children = { UIKit.TextStroke(0.15) },
	})
	local leadIconHolder = UIKit.new("Frame", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.fromOffset(40, 40),
		Parent = leadPill,
	})
	local leadIcon: Frame? = nil
	local leadIconSlot = 0
	local leadText = UIKit.Label({
		Name = "Leader",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 24,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(58, 8),
		Size = UDim2.new(1, -66, 0, 40),
		Parent = leadPill,
		Children = { UIKit.TextStroke(0.15) },
	})

	local nameOf: { [number]: string } = {}
	local function refreshNames()
		for _, participant in api:Participants() do
			nameOf[participant.UserId] = participant.DisplayName
		end
	end

	local function refreshHud()
		local mine = held[myId]
		local mySlot = slots[myId]
		minePill.Visible = mySlot ~= nil
		if mySlot and not mineIcon then
			local icon = shapeIcon(mySlot, 40, minePill)
			icon.Position = UDim2.fromOffset(10, 8)
			mineIcon = icon
		end
		mineCount.Text = if mine then (if mine[1] == 1 then "1 orb" else `{mine[1]} orbs`) else ""
		-- The leader: most orbs, then most hits (players who left are gone from Held).
		local bestId, best, tie = nil, nil, false
		for userId, entry in held do
			if not best or entry[1] > best[1] or (entry[1] == best[1] and entry[2] > best[2]) then
				bestId, best, tie = userId, entry, false
			elseif entry[1] == best[1] and entry[2] == best[2] then
				tie = true
			end
		end
		if not bestId or not best or tie then
			leadText.Text = "TIED!"
			if leadIcon then
				leadIcon:Destroy()
				leadIcon, leadIconSlot = nil, 0
			end
			return
		end
		local slot = slots[bestId] or 1
		if slot ~= leadIconSlot then
			if leadIcon then
				leadIcon:Destroy()
			end
			leadIcon = shapeIcon(slot, 40, leadIconHolder)
			leadIconSlot = slot
		end
		if bestId == myId then
			leadText.Text = `YOU LEAD! {best[1]}`
		else
			local name = nameOf[bestId]
			if not name then
				refreshNames()
				name = nameOf[bestId] or "?"
			end
			leadText.Text = `{string.sub(name, 1, 12)} {best[1]}`
		end
	end

	local function readRoster()
		local roster = api:SharedJSON("Roster")
		if type(roster) ~= "table" then
			return
		end
		local present = {}
		for _, entry in roster do
			if type(entry) == "table" and type(entry[1]) == "number" and type(entry[2]) == "number" then
				slots[entry[1]] = entry[2]
				present[entry[1]] = true
			end
		end
		for userId in slots do
			if not present[userId] then
				slots[userId] = nil
				held[userId] = nil
				swings[userId] = nil
				dropGear(userId)
			end
		end
		refreshNames()
		refreshHud()
	end

	local function readHeld()
		local map = api:SharedJSON("Held")
		if type(map) ~= "table" then
			return
		end
		local fresh = {}
		for key, entry in map do
			local userId = tonumber(key)
			if userId and type(entry) == "table" then
				fresh[userId] = { tonumber(entry[1]) or 0, tonumber(entry[2]) or 0 }
			end
		end
		held = fresh
		for userId, entry in gear do
			local value = held[userId]
			entry.Count.Text = if value then tostring(value[1]) else ""
		end
		refreshHud()
	end
	readRoster()
	readHeld()
	api:OnShared("Roster", readRoster)
	api:OnShared("Held", readHeld)

	-- Orbs -----------------------------------------------------------------------------------------
	type Orb = {
		Data: { number },
		Model: Model?,
		Parts: { BasePart },
		Prop: string,
		Added: number,
		TakenAt: number?,
		TakenBy: number?,
		From: Vector3?,
	}
	local orbs: { [number]: Orb } = {}
	local gone: { [number]: number } = {} -- ids taken or vanished, and when (so stale state doesn't revive them)
	local pools: { [string]: { Model } } = {}

	local function borrow(prop: string, color: Color3): (Model?, { BasePart })
		local pool = pools[prop]
		local model = pool and table.remove(pool)
		if not model then
			local source = template(prop)
			if not source then
				return nil, {}
			end
			model = source:Clone() :: Model
			quiet(model :: Model)
		end
		scaleBy(model :: Model, ORB_SCALE)
		local parts = partsOf(model :: Model)
		for _, part in parts do
			part.Color = color
			part.Material = Enum.Material.Neon
			part.Transparency = 0
		end
		(model :: Model).Parent = api.World
		return model, parts
	end

	local function giveBack(orb: Orb)
		local model = orb.Model
		if model then
			model.Parent = nil
			pools[orb.Prop] = pools[orb.Prop] or {}
			table.insert(pools[orb.Prop], model)
			orb.Model = nil
		end
	end

	local function addOrb(data: any)
		if type(data) ~= "table" or type(data[1]) ~= "number" or orbs[data[1]] or gone[data[1]] then
			return
		end
		for index = 2, 7 do
			if type(data[index]) ~= "number" then
				return
			end
		end
		local slot = Rules.SLOTS[data[2]] or Rules.SLOTS[1]
		local model, parts = borrow(slot.Prop, slot.Color)
		orbs[data[1]] = {
			Data = data,
			Model = model,
			Parts = parts,
			Prop = slot.Prop,
			Added = os.clock(),
		}
	end

	local function orbWorld(orb: Orb, now: number): Vector3?
		if not center then
			return nil
		end
		local x, z, height = Rules.OrbAt(orb.Data, now)
		local bob = math.sin(now * 3 + orb.Data[1]) * 0.15
		return (center :: Vector3) + Vector3.new(x, 0.45 + height + (if height <= 0 then bob else 0), z)
	end

	local function take(id: number, userId: number)
		local orb = orbs[id]
		gone[id] = os.clock()
		if orb and not orb.TakenAt then
			orb.TakenAt = os.clock()
			orb.TakenBy = userId
			orb.From = orbWorld(orb, api:Now())
		end
	end

	local function readOrbs()
		local list = api:SharedJSON("Orbs")
		if type(list) ~= "table" then
			return
		end
		local present = {}
		for _, data in list do
			if type(data) == "table" and type(data[1]) == "number" then
				present[data[1]] = true
				addOrb(data)
			end
		end
		-- Orbs the state no longer has (and that a Drop didn't bring a moment ago) went quietly.
		local clock = os.clock()
		for id, orb in orbs do
			if not present[id] and not orb.TakenAt and clock - orb.Added > 1.5 then
				gone[id] = clock
				giveBack(orb)
				orbs[id] = nil
			end
		end
	end
	readOrbs()
	api:OnShared("Orbs", readOrbs)

	api:OnEvent("Drop", function(list)
		if type(list) == "table" then
			for _, data in list do
				addOrb(data)
			end
		end
	end)
	api:OnEvent("Take", function(userId, ids)
		if type(userId) ~= "number" or type(ids) ~= "table" then
			return
		end
		for _, id in ids do
			if type(id) == "number" then
				take(id, userId)
			end
		end
		if userId == myId then
			api:Sound("Pickup")
		end
	end)

	-- Your swings --------------------------------------------------------------------------------
	local readyAt = 0
	local stunnedUntil = 0 -- knocked down after a hit: presses do nothing until then
	local holding = false -- the button (or mouse) is down for a swing we started
	local spent = false -- this press's swing already went (hit out of your hands, or held too long)
	api:OnMine("ReadyAt", function(value)
		if type(value) == "number" then
			readyAt = math.max(readyAt, value)
		end
	end)

	local button = api:Button({ Text = "SWING", Key = Enum.KeyCode.E, Color = Theme.Colors.Orange })

	local function press()
		if holding or not api:CanAct() then
			return
		end
		local now = api:Now()
		-- Not ready (the 3-2-1, the wait after a swing, knocked down): this press does nothing, and
		-- neither does its release (the server would turn both down).
		if GameState.Get("Phase") ~= "InRound" or now < readyAt - 0.05 or now < stunnedUntil then
			holding, spent = true, true
			return
		end
		holding, spent = true, false
		swings[myId] = { Wind = now, Charged = false }
		api:Action("Charge", now)
	end
	local function release()
		if not holding then
			return
		end
		holding = false
		if spent then
			spent = false
			return
		end
		local now = api:Now()
		local swing = swings[myId]
		if not swing or swing.Strike then
			return
		end
		if now - swing.Wind >= Rules.MAX_HOLD - 0.05 then
			return -- held to the end: the server lets it go by itself (its Strike cue draws it)
		end
		local strike = math.max(now, swing.Wind + Rules.WINDUP)
		swing.Strike = strike
		swing.Charged = now - swing.Wind >= Rules.CHARGE - 0.03
		readyAt = strike + (if swing.Charged then Rules.RECOVER_CHARGED else Rules.RECOVER)
		api:Action("Swing", now)
		api:Sound("Boing")
	end
	button.Pressed:Connect(press)
	button.Released:Connect(release)
	if not touch then
		api:Track(UserInputService.InputBegan:Connect(function(input, processed)
			if not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
				press()
			end
		end))
		api:Track(UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				release()
			end
		end))
	end
	api:Hint(if touch then "Hold SWING to charge a big hit!" else "Click or hold E: let go to swing!", y + 66)
	task.delay(6, function()
		api:Hint("", y + 66)
	end)

	-- The server turned our press down: stop drawing that swing.
	api:OnEvent("Refused", function(until_)
		local swing = swings[myId]
		if swing and not swing.Strike then
			swings[myId] = nil
		end
		if holding then
			spent = true
		end
		if type(until_) == "number" then
			readyAt = math.max(readyAt, until_)
		end
	end)

	-- Everyone's swings (server cues) -------------------------------------------------------------
	api:OnEvent("Wind", function(userId, start)
		if type(userId) ~= "number" or type(start) ~= "number" or userId == myId then
			return
		end
		swings[userId] = { Wind = start, Charged = false }
	end)
	api:OnEvent("Strike", function(userId, start, strike, charged)
		if type(userId) ~= "number" or type(start) ~= "number" or type(strike) ~= "number" then
			return
		end
		local swing = swings[userId]
		if userId == myId then
			-- Ours: the server's word on when it struck (a charge held too long went by itself).
			if swing and math.abs(swing.Wind - start) < 0.6 then
				swing.Strike = strike
				swing.Charged = charged == true
				if holding then
					spent = true
				end
				return
			end
		end
		swings[userId] = { Wind = start, Strike = strike, Charged = charged == true }
	end)
	api:OnEvent("Hit", function(attacker, victim, count, charged, safe, at, stunned)
		if type(victim) ~= "number" or type(attacker) ~= "number" then
			return
		end
		local swing = swings[victim]
		if swing and (not swing.Strike or swing.Strike > api:Now()) then
			swings[victim] = nil
			if victim == myId and holding then
				spent = true
			end
		end
		if type(safe) == "number" then
			safeUntil[victim] = safe
		end
		if victim == myId and type(stunned) == "number" then
			stunnedUntil = math.max(stunnedUntil, stunned)
		end
		if type(at) == "table" and type(at[1]) == "number" then
			local position = Vector3.new(at[1], (at[2] or 0) + 1, at[3] or 0)
			local slot = Rules.SLOTS[slots[victim] or 1]
			api:Effect("Sparkles", position, { slot.Color, Color3.new(1, 1, 1) })
			if charged then
				api:Effect("Poof", position)
			end
			if victim == myId or attacker == myId then
				api:Sound("Hit")
			end
			if type(count) == "number" and count > 0 then
				-- "-3" rises over the victim.
				local anchor = Instance.new("Part")
				anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
				anchor.Transparency = 1
				anchor.Size = Vector3.one * 0.2
				anchor.Position = position + Vector3.new(0, 3, 0)
				anchor.Parent = api.World
				local gui = Instance.new("BillboardGui")
				gui.Size = UDim2.fromOffset(90, 44)
				gui.LightInfluence = 0
				gui.MaxDistance = 90
				gui.Parent = anchor
				local label = UIKit.Label({
					Text = `-{count}`,
					Font = Theme.Fonts.Display,
					TextSize = 38,
					TextColor3 = if charged then Theme.Colors.Yellow else Color3.new(1, 1, 1),
					Size = UDim2.fromScale(1, 1),
					Parent = gui,
					Children = { UIKit.TextStroke(0.1) },
				})
				local born = os.clock()
				local connection
				connection = game:GetService("RunService").RenderStepped:Connect(function()
					local age = os.clock() - born
					if age > 0.9 or not anchor.Parent then
						connection:Disconnect()
						anchor:Destroy()
						return
					end
					anchor.Position = position + Vector3.new(0, 3 + age * 3, 0)
					label.TextTransparency = math.max(0, (age - 0.5) / 0.4)
				end)
				api:Track(connection)
			end
		end
	end)

	-- Every frame ------------------------------------------------------------------------------------
	api:RenderStep(function()
		local now = api:Now()
		local clock = os.clock()

		-- Gear for everyone in the round with a character.
		for userId, slotIndex in slots do
			local character = api:CharacterOf(userId)
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local entry = gear[userId]
			if not root then
				if entry then
					if entry.Bat then
						entry.Bat.Parent = nil
					end
					if entry.Fan then
						for _, part in partsOf(entry.Fan) do
							part.Transparency = 1
						end
					end
					entry.Disc.Transparency = 1
					entry.Tag.Enabled = false
				end
				continue
			end
			if not entry then
				entry = makeGear(userId, slotIndex)
				local value = held[userId]
				entry.Count.Text = if value then tostring(value[1]) else ""
			end
			local g = entry :: Gear
			if not g.Bat then
				g.Bat, g.Foam = makeBat(slotIndex)
			end
			if g.Bat and g.Bat.Parent == nil then
				g.Bat.Parent = api.World
			end
			g.Tag.Enabled = true
			g.Tag.Adornee = root
			-- Safe after a hit: the tag blinks.
			local safe = (safeUntil[userId] or 0) > now
			g.Tag.Enabled = not safe or math.floor(clock * 8) % 2 == 0

			local rootCF = root.CFrame
			local swing = swings[userId]
			local pose = REST * CFrame.new(0, math.sin(clock * 4 + userId % 7) * 0.05, 0)
			local glow = false
			local reach = 0
			if swing then
				local strike = swing.Strike
				if strike and now >= strike + Rules.SWEEP + REST_BACK then
					swings[userId] = nil
				elseif strike and now >= strike + Rules.SWEEP then
					local k = (now - strike - Rules.SWEEP) / REST_BACK
					pose = sweepPose(SWEEP_TO):Lerp(REST, k)
				elseif strike and now >= strike then
					local k = (now - strike) / Rules.SWEEP
					k = 1 - (1 - k) * (1 - k)
					pose = sweepPose(SWEEP_FROM + (SWEEP_TO - SWEEP_FROM) * k)
					glow = swing.Charged
				elseif now >= swing.Wind then
					local held_ = now - swing.Wind
					local k = math.clamp(held_ / 0.15, 0, 1)
					local charge = math.clamp(held_ / Rules.CHARGE, 0, 1)
					glow = held_ >= Rules.CHARGE or swing.Charged
					local shake = if glow then CFrame.Angles(0, 0, math.sin(clock * 40) * 0.06) else CFrame.identity
					pose = REST:Lerp(WIND, k) * shake
					-- (A swing that never got its Strike cue is gone after its longest hold.)
					if not strike and held_ > Rules.MAX_HOLD + 1 then
						swings[userId] = nil
					end
					reach = Rules.RANGE + (Rules.RANGE_CHARGED - Rules.RANGE) * charge
				end
			end
			-- A charged swing's bat is drawn longer, to its longer reach.
			local batScale = if glow then Rules.CHARGED_BAT else 1
			if g.Bat then
				if g.BatScale ~= batScale then
					scaleBy(g.Bat, batScale)
					g.BatScale = batScale
				end
				g.Bat:PivotTo(rootCF * pose)
				for _, part in g.Foam do
					part.Material = if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
				end
			end
			-- The reach, drawn as the rule: a +-ARC fan of radius RANGE in front and the CLOSE circle
			-- (any part of you inside either is hit).
			if not g.Fan then
				g.Fan = makeFan(slotIndex)
			end
			if reach > 0 then
				local flat = Vector3.new(rootCF.LookVector.X, 0, rootCF.LookVector.Z)
				-- On the sand (its top is the field's centre height), under the swinger.
				local sandY = if center then (center :: Vector3).Y else root.Position.Y - 3
				local ground = Vector3.new(root.Position.X, sandY, root.Position.Z)
				local facing = CFrame.lookAt(ground, ground + (if flat.Magnitude > 0.01 then flat else Vector3.zAxis))
				local size = Rules.CLOSE * 2
				g.Disc.Size = Vector3.new(0.05, size, size)
				g.Disc.CFrame = facing * CFrame.new(0, 0.09, 0) * CFrame.Angles(0, 0, math.rad(90))
				g.Disc.Transparency = if glow then 0.62 else 0.8
				local fan = g.Fan
				if fan then
					scaleBy(fan, reach / (fan:GetAttribute("PP_Radius") or 1))
					fan:PivotTo(facing * CFrame.new(0, 0.08, -reach / 2))
					for _, part in partsOf(fan) do
						part.Transparency = if glow then 0.62 else 0.8
					end
				end
			else
				g.Disc.Transparency = 1
				if g.Fan then
					for _, part in partsOf(g.Fan) do
						part.Transparency = 1
					end
				end
			end
		end

		-- Orbs: flying, lying (bobbing and turning), or flying to whoever took them.
		for id, orb in orbs do
			local model = orb.Model
			if orb.TakenAt then
				local k = (clock - orb.TakenAt) / FLY
				local character = orb.TakenBy and api:CharacterOf(orb.TakenBy)
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if k >= 1 or not model or not orb.From then
					giveBack(orb)
					orbs[id] = nil
				elseif model then
					local target = if root then root.Position else orb.From :: Vector3
					local position = (orb.From :: Vector3):Lerp(target, k)
						+ Vector3.new(0, math.sin(k * math.pi) * 1.5, 0)
					model:PivotTo(CFrame.new(position) * CFrame.Angles(0, clock * 6, 0))
					scaleBy(model, ORB_SCALE * math.max(0.2, 1 - k * 0.7))
				end
				continue
			end
			if model then
				local position = orbWorld(orb, now)
				if position then
					local landed = now >= orb.Data[7] + Rules.FLIGHT
					local spin = clock * (if landed then 1.6 else 8) + id
					model:PivotTo(CFrame.new(position) * CFrame.Angles(0, spin, 0))
				end
			end
		end
		for id, at in gone do
			if clock - at > 5 then
				gone[id] = nil
			end
		end

		-- The button: charge while holding, the wait after a swing.
		if holding and not spent then
			local swing = swings[myId]
			if swing and not swing.Strike then
				local charge = math.clamp((now - swing.Wind) / Rules.CHARGE, 0, 1)
				button:SetFill(charge, if charge >= 1 then Theme.Colors.Yellow else Color3.new(1, 1, 1))
				button:SetText(if charge >= 1 then "LET GO!" else "CHARGE")
			end
		else
			local wait = readyAt - now
			button:SetFill(if wait > 0 then math.clamp(wait / Rules.RECOVER_CHARGED, 0, 1) else 0)
			button:SetText("SWING")
		end
	end)

	-- Pooled orbs and the template copies go when the round ends (the rest is in api.World).
	api:Track(function()
		for _, pool in pools do
			for _, model in pool do
				model:Destroy()
			end
		end
		for _, copy in templates do
			copy:Destroy()
		end
	end)
end

return Struggle
