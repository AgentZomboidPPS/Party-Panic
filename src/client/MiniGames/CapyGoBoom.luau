-- Client half of Capy Go Boom: draws a capybara on everyone's character (the real avatar is hidden on
-- this screen, the capy follows its root and grows smoothly with its weight), the snacks (the server's
-- "Snacks" list plus Spawn / Eat events), the shells (from the "Shot" cue, on the server's clock), pops,
-- a name-and-weight tag over every capy, and the HUD: your weight and rank, the leader, the FEAST
-- banner, and the BOOM button (E or a click on PC, beside the jump button on phones).
--
-- Everyone has a colour (the scarf, the cannon's rim, the shell, the tag; Shared/Logic/CapyGoBoom
-- COLORS) and a name tag, so colour is never the only cue. Your own capy stands in a coloured ring.
--
-- Your press goes to the server with when you made it and, on PC, where the mouse points (the capy
-- turns that way for a moment); on a phone the shot goes the way you face and the server bends it
-- toward a rival close to that line. The shell appears from the server's "Shot" cue and flies on the
-- server's clock, so what you see is what is judged. The server turns a press down while you're
-- reloading or staggering ("Refused") and the button's ring says when you can fire again.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local GameState = require(ReplicatedStorage.Shared.GameState)
local Rules = require(ReplicatedStorage.Shared.Logic.CapyGoBoom)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local CapyGoBoom = {}

local ROOT_TO_GROUND = 3.0 -- a standing character's root is this far above the lawn
local GROW = 6 -- how fast a capy's drawn size catches up with its weight (1/s)
local SNACK_SCALE = 1.3 -- snacks are drawn a little bigger than their meshes (easy to spot on phones)
local FLY = 0.25 -- seconds an eaten snack takes to fly to its eater
local FACE = 0.4 -- seconds a capy turns to where it fired
local SHELL_LOOK = 1.25 -- shells are drawn a bit bigger than their hit circle, so they're easy to follow

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

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function CapyGoBoom.Start(api)
	api:Mood({
		Tint = Color3.fromRGB(255, 244, 222),
		Saturation = 0.14,
		Contrast = 0.05,
		Haze = Color3.fromRGB(190, 225, 255),
		HazeDecay = Color3.fromRGB(150, 190, 220),
		Density = 0.22,
	})
	local touch = api:IsTouch()
	local localPlayer = Players.LocalPlayer
	local myId = if localPlayer then localPlayer.UserId else 0
	local reduced = State.ReducedEffects()

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
	local slots: { [number]: number } = {} -- UserId -> colour slot
	local mass: { [number]: { number } } = {} -- UserId -> { weight, pops }
	local feast = false
	local function readField()
		local field = api:SharedJSON("Field")
		if type(field) == "table" and type(field.Center) == "table" then
			center = Vector3.new(field.Center[1], field.Center[2], field.Center[3])
		end
	end
	readField()
	api:OnShared("Field", readField)

	local function colorOf(userId: number): Color3
		return Rules.COLORS[slots[userId] or 1] or Rules.COLORS[1]
	end

	-- The real avatars are hidden on this screen; the capy is drawn instead. Whatever we change we
	-- put back when the round ends (the lobby gives everyone a fresh character anyway).
	local hiddenPart: { [Instance]: number } = {}
	local hiddenName: { [Humanoid]: Enum.HumanoidDisplayDistanceType } = {}
	local hiddenCharacters: { [Model]: boolean } = {}
	local hiddenGui: { [BillboardGui]: boolean } = {}
	local function hideItem(item: Instance)
		if (item:IsA("BasePart") or item:IsA("Decal")) and hiddenPart[item] == nil then
			local visual = item :: any
			hiddenPart[item] = visual.Transparency
			visual.Transparency = 1
		elseif item:IsA("BillboardGui") and hiddenGui[item] == nil then
			-- (a bot's BOT nameplate, a title: the capy's own tag says who it is)
			hiddenGui[item] = item.Enabled
			item.Enabled = false
		end
	end
	local function hideAvatar(character: Model)
		if hiddenCharacters[character] then
			return
		end
		hiddenCharacters[character] = true
		for _, item in character:GetDescendants() do
			hideItem(item)
		end
		api:Track(character.DescendantAdded:Connect(hideItem))
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			hiddenName[humanoid] = humanoid.DisplayDistanceType
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end

	-- Capys ------------------------------------------------------------------------------------------
	type Capy = {
		Model: Model?,
		Parts: { BasePart },
		Scale: number,
		Slot: number,
		Tag: BillboardGui,
		Name: TextLabel,
		Amount: TextLabel,
		Ring: Part?,
		SafeUntil: number,
		Blink: boolean,
		Chomp: number,
		Recoil: number,
		Squash: number,
		FaceDir: Vector3?,
		FaceAt: number,
		Bob: number,
	}
	local capys: { [number]: Capy } = {}
	local names: { [number]: string } = {}
	local bots: { [number]: boolean } = {}
	local function refreshNames()
		for _, participant in api:Participants() do
			names[participant.UserId] = participant.DisplayName
			bots[participant.UserId] = participant.IsBot == true
		end
	end

	local function dropCapy(userId: number)
		local capy = capys[userId]
		if capy then
			if capy.Model then
				capy.Model:Destroy()
			end
			if capy.Ring then
				capy.Ring:Destroy()
			end
			capy.Tag:Destroy()
			capys[userId] = nil
		end
	end

	local function paintCapy(model: Model, color: Color3): { BasePart }
		local parts = partsOf(model)
		for _, part in parts do
			if part.Name == "Band" or part.Name == "CannonRim" then
				part.Color = color
			end
		end
		return parts
	end

	local function makeCapy(userId: number, slot: number): Capy
		local color = Rules.COLORS[slot] or Rules.COLORS[1]
		local tag = Instance.new("BillboardGui")
		tag.Name = "CapyTag"
		tag.Size = UDim2.fromOffset(176, 54)
		tag.LightInfluence = 0
		tag.MaxDistance = 150
		tag.AlwaysOnTop = false
		tag.Parent = api.World
		local nameLabel = UIKit.Label({
			Name = "Name",
			Text = "",
			Font = Theme.Fonts.Bold,
			TextSize = 20,
			TextScaled = true,
			Size = UDim2.new(1, 0, 0, 22),
			Parent = tag,
			Children = { UIKit.TextStroke(0.1) },
		})
		local amountLabel = UIKit.Label({
			Name = "Amount",
			Text = "",
			Font = Theme.Fonts.Display,
			TextSize = 30,
			TextColor3 = color,
			Position = UDim2.fromOffset(0, 22),
			Size = UDim2.new(1, 0, 0, 32),
			Parent = tag,
			Children = { UIKit.TextStroke(0.05) },
		})
		local ring: Part? = nil
		if userId == myId then
			local disc = Instance.new("Part")
			disc.Name = "YouRing"
			disc.Shape = Enum.PartType.Cylinder
			disc.Size = Vector3.new(0.12, 8, 8)
			disc.Material = Enum.Material.Neon
			disc.Color = color
			disc.Transparency = 0.45
			disc.Anchored = true
			disc.CanCollide = false
			disc.CanQuery = false
			disc.CanTouch = false
			disc.CastShadow = false
			disc.Parent = api.World
			ring = disc
		end
		local capy: Capy = {
			Model = nil,
			Parts = {},
			Scale = Rules.ScaleOf(Rules.START_MASS),
			Slot = slot,
			Tag = tag,
			Name = nameLabel,
			Amount = amountLabel,
			Ring = ring,
			SafeUntil = 0,
			Blink = false,
			Chomp = -10,
			Recoil = -10,
			Squash = -10,
			FaceDir = nil,
			FaceAt = -10,
			Bob = (userId % 7) * 0.9,
		}
		capys[userId] = capy
		return capy
	end

	local function refreshTags()
		local leaderId, leaderMass, tie = nil, -1, false
		for userId, entry in mass do
			if entry[1] > leaderMass then
				leaderId, leaderMass, tie = userId, entry[1], false
			elseif entry[1] == leaderMass then
				tie = true
			end
		end
		for userId, capy in capys do
			local entry = mass[userId]
			capy.Amount.Text = if entry then `{entry[1]} {Rules.UNIT}` else ""
			local label = names[userId]
			if not label then
				refreshNames()
				label = names[userId] or "?"
			end
			local crown = if userId == leaderId and not tie then "👑 " else ""
			local robot = if bots[userId] then "🤖 " else ""
			capy.Name.Text = if userId == myId
				then `{crown}YOU`
				else `{crown}{robot}{string.sub(label :: string, 1, 14)}`
			capy.Name.TextColor3 = if userId == myId then Theme.Colors.Yellow else Color3.new(1, 1, 1)
		end
	end

	-- HUD ----------------------------------------------------------------------------------------------
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
	local mineDot = UIKit.new("Frame", {
		Name = "Dot",
		Position = UDim2.fromOffset(12, 14),
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = Rules.COLORS[1],
		Parent = minePill,
		Children = { UIKit.Round(), UIKit.Stroke(Color3.fromRGB(20, 16, 30), 2, 0.2) },
	})
	local mineAmount = UIKit.Label({
		Name = "Amount",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(48, 0),
		Size = UDim2.new(1, -112, 1, 0),
		Parent = minePill,
		Children = { UIKit.TextStroke(0.15) },
	})
	local mineRank = UIKit.Label({
		Name = "Rank",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		TextColor3 = Theme.Colors.Yellow,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(1, -62, 0, 0),
		Size = UDim2.fromOffset(52, 56),
		Parent = minePill,
		Children = { UIKit.TextStroke(0.15) },
	})
	UIKit.Label({
		Name = "Crown",
		Text = "👑",
		TextSize = 28,
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.fromOffset(36, 56),
		Parent = leadPill,
	})
	local leadText = UIKit.Label({
		Name = "Leader",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 24,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(46, 8),
		Size = UDim2.new(1, -54, 0, 40),
		Parent = leadPill,
		Children = { UIKit.TextStroke(0.15) },
	})
	local feastLabel = UIKit.Label({
		Name = "Feast",
		Text = "🍉 FEAST! LAWN SNACKS COUNT DOUBLE! 🍉",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		TextColor3 = Theme.Colors.Yellow,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y + 62),
		Size = UDim2.fromOffset(if touch then 330 else 460, 34),
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0.1) },
	})

	local function refreshHud()
		local mine = mass[myId]
		minePill.Visible = slots[myId] ~= nil
		mineDot.BackgroundColor3 = colorOf(myId)
		mineAmount.Text = if mine then `{mine[1]} {Rules.UNIT}` else ""
		-- Rank: one more than the number heavier than you.
		local rank, count = 1, 0
		local leaderId, leaderMass, tie = nil, -1, false
		for userId, entry in mass do
			count += 1
			if mine and entry[1] > mine[1] then
				rank += 1
			end
			if entry[1] > leaderMass then
				leaderId, leaderMass, tie = userId, entry[1], false
			elseif entry[1] == leaderMass then
				tie = true
			end
		end
		mineRank.Text = if mine then `#{rank}` else ""
		if not leaderId or tie then
			leadText.Text = "TIED!"
		elseif leaderId == myId then
			leadText.Text = `YOU LEAD! {leaderMass}`
		else
			local name = names[leaderId]
			if not name then
				refreshNames()
				name = names[leaderId] or "?"
			end
			leadText.Text = `{string.sub(name :: string, 1, 12)} {leaderMass}`
		end
		refreshTags()
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
				mass[userId] = nil
				dropCapy(userId)
			end
		end
		refreshNames()
		refreshHud()
	end

	local function readMass()
		local map = api:SharedJSON("Mass")
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
		mass = fresh
		refreshHud()
	end
	readRoster()
	readMass()
	api:OnShared("Roster", readRoster)
	api:OnShared("Mass", readMass)

	api:OnShared("Feast", function(value)
		feast = value == true
		feastLabel.Visible = feast
	end)
	feast = api:Shared("Feast") == true
	feastLabel.Visible = feast

	-- Floating words (rise and fade) -------------------------------------------------------------------
	type Floater = { Anchor: Part, Label: TextLabel, Born: number, Life: number, From: Vector3, Rise: number }
	local floaters: { Floater } = {}
	local function floatText(position: Vector3, text: string, color: Color3, size: number, life: number?, rise: number?)
		local anchor = Instance.new("Part")
		anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
		anchor.Transparency = 1
		anchor.Size = Vector3.one * 0.2
		anchor.Position = position
		anchor.Parent = api.World
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(240, 70)
		gui.LightInfluence = 0
		gui.MaxDistance = 130
		gui.Parent = anchor
		local label = UIKit.Label({
			Text = text,
			Font = Theme.Fonts.Display,
			TextSize = size,
			TextColor3 = color,
			Size = UDim2.fromScale(1, 1),
			Parent = gui,
			Children = { UIKit.TextStroke(0.05) },
		})
		table.insert(floaters, {
			Anchor = anchor,
			Label = label,
			Born = os.clock(),
			Life = life or 0.9,
			From = position,
			Rise = rise or 3,
		})
	end

	-- Snacks -----------------------------------------------------------------------------------------------
	type Snack = {
		Data: { number },
		Model: Model?,
		Kind: number,
		Added: number,
		Beam: Part?,
		TakenAt: number?,
		TakenBy: number?,
		From: Vector3?,
	}
	local snacks: { [number]: Snack } = {}
	local gone: { [number]: number } = {} -- ids eaten or vanished, and when (so stale state doesn't revive them)
	local pools: { [string]: { Model } } = {}

	local function borrow(prop: string): Model?
		local pool = pools[prop]
		local model = pool and table.remove(pool)
		if not model then
			local source = template(prop)
			if not source then
				return nil
			end
			model = source:Clone() :: Model
			quiet(model :: Model)
		end
		local ready = model :: Model
		ready.Parent = api.World
		return ready
	end

	local function giveBack(snack: Snack)
		local model = snack.Model
		if model then
			model.Parent = nil
			local prop = Rules.SNACKS[snack.Kind].Prop
			pools[prop] = pools[prop] or {}
			table.insert(pools[prop], model)
			snack.Model = nil
		end
		if snack.Beam then
			snack.Beam:Destroy()
			snack.Beam = nil
		end
	end

	local function addSnack(data: any)
		if type(data) ~= "table" or type(data[1]) ~= "number" or snacks[data[1]] or gone[data[1]] then
			return
		end
		for index = 2, 8 do
			if type(data[index]) ~= "number" then
				return
			end
		end
		local kind = data[2]
		if not Rules.SNACKS[kind] or Rules.FLIGHT[data[8]] == nil then
			return
		end
		local snack: Snack = {
			Data = data,
			Model = borrow(Rules.SNACKS[kind].Prop),
			Kind = kind,
			Added = os.clock(),
		}
		-- A golden melon has a beam of light, easy to find across the lawn.
		if kind == Rules.GOLD and not reduced then
			local beam = Instance.new("Part")
			beam.Name = "GoldBeam"
			beam.Shape = Enum.PartType.Cylinder
			beam.Size = Vector3.new(70, 1.6, 1.6)
			beam.Material = Enum.Material.Neon
			beam.Color = Rules.SNACKS[Rules.GOLD].Color
			beam.Transparency = 0.6
			beam.Anchored, beam.CanCollide, beam.CanQuery, beam.CanTouch, beam.CastShadow =
				true, false, false, false, false
			beam.Parent = api.World
			snack.Beam = beam
		end
		snacks[data[1]] = snack
	end

	local function snackWorld(snack: Snack, now: number): Vector3?
		if not center then
			return nil
		end
		local x, z, height = Rules.SnackAt(snack.Data, now)
		local landed = Rules.Landed(snack.Data, now)
		local bob = if landed then math.sin(now * 3 + snack.Data[1]) * 0.18 else 0
		return (center :: Vector3) + Vector3.new(x, 0.55 + height + bob, z)
	end

	local function readSnacks()
		local list = api:SharedJSON("Snacks")
		if type(list) ~= "table" then
			return
		end
		local present = {}
		for _, data in list do
			if type(data) == "table" and type(data[1]) == "number" then
				present[data[1]] = true
				addSnack(data)
			end
		end
		-- Snacks the state no longer has (and that a Spawn didn't bring a moment ago) went quietly.
		local clock = os.clock()
		for id, snack in snacks do
			if not present[id] and not snack.TakenAt and clock - snack.Added > 1.5 then
				gone[id] = clock
				giveBack(snack)
				snacks[id] = nil
			end
		end
	end
	readSnacks()
	api:OnShared("Snacks", readSnacks)

	api:OnEvent("Spawn", function(list)
		if type(list) == "table" then
			for _, data in list do
				addSnack(data)
			end
		end
	end)

	api:OnEvent("Eat", function(userId, ids, gain, gold)
		if type(userId) ~= "number" or type(ids) ~= "table" then
			return
		end
		local clock = os.clock()
		local now = api:Now()
		for _, id in ids do
			if type(id) == "number" then
				local snack = snacks[id]
				gone[id] = clock
				if snack and not snack.TakenAt then
					snack.TakenAt = clock
					snack.TakenBy = userId
					snack.From = snackWorld(snack, now)
					if snack.Beam then
						snack.Beam:Destroy()
						snack.Beam = nil
					end
				end
			end
		end
		local capy = capys[userId]
		if capy then
			capy.Chomp = clock
		end
		if userId == myId then
			api:Sound("Pickup")
			local character = api:CharacterOf(myId)
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and type(gain) == "number" and gain > 0 then
				local text = if gold == true then `+{gain} GOLDEN MELON!` else `+{gain}`
				floatText(
					root.Position + Vector3.new(0, 4, 0),
					text,
					if gold == true then Rules.SNACKS[Rules.GOLD].Color else Theme.Colors.Green,
					if gold == true then 40 else 30,
					if gold == true then 1.4 else 0.8
				)
				if gold == true and root then
					api:Effect("Confetti", root.Position, { Rules.SNACKS[Rules.GOLD].Color, Color3.new(1, 1, 1) })
				end
			end
		end
	end)

	-- SNACK DROP warnings ------------------------------------------------------------------------------------
	type Warning = { Disc: Part, Beam: Part, LandAt: number, Born: number }
	local warnings: { Warning } = {}
	api:OnEvent("DropWarn", function(x, z, landAt)
		if type(x) ~= "number" or type(z) ~= "number" or type(landAt) ~= "number" or not center then
			return
		end
		local ground = (center :: Vector3) + Vector3.new(x, 0.12, z)
		local gold = Rules.SNACKS[Rules.GOLD].Color
		local disc = Instance.new("Part")
		disc.Name = "DropMark"
		disc.Shape = Enum.PartType.Cylinder
		disc.Size = Vector3.new(0.1, Rules.DROP_SPREAD * 2 + 4, Rules.DROP_SPREAD * 2 + 4)
		disc.CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90))
		disc.Material = Enum.Material.Neon
		disc.Color = gold
		disc.Transparency = 0.6
		disc.Anchored, disc.CanCollide, disc.CanQuery, disc.CanTouch, disc.CastShadow = true, false, false, false, false
		disc.Parent = api.World
		local beam = Instance.new("Part")
		beam.Name = "DropBeam"
		beam.Shape = Enum.PartType.Cylinder
		beam.Size = Vector3.new(90, 5, 5)
		beam.CFrame = CFrame.new(ground + Vector3.new(0, 45, 0)) * CFrame.Angles(0, 0, math.rad(90))
		beam.Material = Enum.Material.Neon
		beam.Color = gold
		beam.Transparency = 0.7
		beam.Anchored, beam.CanCollide, beam.CanQuery, beam.CanTouch, beam.CastShadow = true, false, false, false, false
		beam.Parent = api.World
		table.insert(warnings, { Disc = disc, Beam = beam, LandAt = landAt, Born = os.clock() })
		api:Sound("HazardWarning")
	end)

	-- Shells --------------------------------------------------------------------------------------------------
	type Shell = { Id: number, Origin: Vector3, Dir: Vector3, T0: number, Model: Model, Owner: number }
	local shells: { [number]: Shell } = {}
	local shellPool: { Model } = {}
	local MAX_AGE = Rules.SHELL_RANGE / Rules.SHELL_SPEED

	local function endShell(id: number)
		local shell = shells[id]
		if shell then
			shell.Model.Parent = nil
			table.insert(shellPool, shell.Model)
			shells[id] = nil
		end
	end

	local function newShell(color: Color3): Model?
		local model = table.remove(shellPool)
		if not model then
			local source = template("CapyBoomShell")
			if not source then
				return nil
			end
			model = source:Clone() :: Model
			quiet(model :: Model)
			scaleBy(model :: Model, SHELL_LOOK)
			local primary = (model :: Model).PrimaryPart or partsOf(model :: Model)[1]
			if primary and not reduced then
				local a0 = Instance.new("Attachment")
				a0.Name = "TrailA"
				a0.Position = Vector3.new(0, 0.5, 0)
				a0.Parent = primary
				local a1 = Instance.new("Attachment")
				a1.Name = "TrailB"
				a1.Position = Vector3.new(0, -0.5, 0)
				a1.Parent = primary
				local trail = Instance.new("Trail")
				trail.Attachment0, trail.Attachment1 = a0, a1
				trail.Lifetime = 0.3
				trail.LightEmission = 0.6
				trail.Transparency = NumberSequence.new(0.2, 1)
				trail.WidthScale = NumberSequence.new(1, 0.1)
				trail.Parent = primary
			end
		end
		for _, part in partsOf(model :: Model) do
			part.Color = color
			part.Transparency = 0
		end
		for _, trail in (model :: Model):GetDescendants() do
			if trail:IsA("Trail") then
				trail.Color = ColorSequence.new(color)
			end
		end
		local ready = model :: Model
		ready.Parent = api.World
		return ready
	end

	api:OnEvent("Shot", function(id, userId, ox, oy, oz, dx, dz, t0, _scale)
		if
			type(id) ~= "number"
			or type(userId) ~= "number"
			or type(ox) ~= "number"
			or type(oy) ~= "number"
			or type(oz) ~= "number"
			or type(dx) ~= "number"
			or type(dz) ~= "number"
			or type(t0) ~= "number"
		then
			return
		end
		local dir = Vector3.new(dx, 0, dz)
		if dir.Magnitude < 0.1 then
			return
		end
		dir = dir.Unit
		local color = colorOf(userId)
		local model = newShell(color)
		if model then
			shells[id] =
				{ Id = id, Origin = Vector3.new(ox, oy, oz), Dir = dir, T0 = t0, Model = model, Owner = userId }
		end
		local capy = capys[userId]
		if capy then
			capy.Recoil = os.clock()
			capy.FaceDir = dir
			capy.FaceAt = os.clock()
		end
		if not reduced then
			api:Effect("Sparkles", Vector3.new(ox, oy, oz), { color, Color3.new(1, 1, 1) })
		end
	end)

	api:OnEvent("ShellEnd", function(id, x, y, z, reason)
		if type(id) ~= "number" then
			return
		end
		endShell(id)
		if reason == 1 and type(x) == "number" and type(y) == "number" and type(z) == "number" and not reduced then
			api:Effect("Poof", Vector3.new(x, y, z))
		end
	end)

	-- Your shots ------------------------------------------------------------------------------------------------
	local readyAt = 0
	local stunnedUntil = 0 -- staggered by a pop: presses do nothing until then
	api:OnMine("ReadyAt", function(value)
		if type(value) == "number" then
			readyAt = math.max(readyAt, value)
		end
	end)

	local button = api:Button({ Text = "BOOM", Key = Enum.KeyCode.E, Color = Theme.Colors.Orange })

	-- Where the mouse points on the lawn, as a direction from your capy (nil on phones and pads).
	local function mouseAim(root: BasePart): (number?, number?)
		if touch or not UserInputService.MouseEnabled then
			return nil, nil
		end
		local camera = workspace.CurrentCamera
		if not camera then
			return nil, nil
		end
		local point = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(point.X, point.Y)
		if ray.Direction.Y > -0.01 then
			return nil, nil
		end
		local t = (root.Position.Y - 0.4 - ray.Origin.Y) / ray.Direction.Y
		if t <= 0 then
			return nil, nil
		end
		local flatAim = flat(ray.Origin + ray.Direction * t - root.Position)
		if flatAim.Magnitude < 1 then
			return nil, nil
		end
		return flatAim.Unit.X, flatAim.Unit.Z
	end

	local function fire()
		if not api:CanAct() or GameState.Get("Phase") ~= "InRound" then
			return
		end
		local now = api:Now()
		if now < readyAt - 0.05 or now < stunnedUntil then
			return
		end
		local character = api:CharacterOf(myId)
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end
		readyAt = now + Rules.RELOAD
		local ax, az = mouseAim(root)
		api:Action("Boom", now, ax, az)
		api:Sound("Boing")
		local capy = capys[myId]
		if capy then
			capy.Recoil = os.clock()
			if ax and az then
				capy.FaceDir = Vector3.new(ax, 0, az)
				capy.FaceAt = os.clock()
			end
		end
	end
	button.Pressed:Connect(fire)
	if not touch then
		api:Track(UserInputService.InputBegan:Connect(function(input, processed)
			if not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
				fire()
			end
		end))
	end
	api:Hint(
		if touch then "Walk over snacks to grow. Tap BOOM to fire!" else "Eat snacks to grow! Click or press E to BOOM.",
		y + 66
	)
	task.delay(6, function()
		api:Hint("", y + 66)
	end)

	-- The server turned our press down: say when we can try again.
	api:OnEvent("Refused", function(until_)
		if type(until_) == "number" then
			readyAt = math.max(readyAt, until_)
		end
	end)

	-- Pops -------------------------------------------------------------------------------------------------------
	api:OnEvent("Pop", function(id, attackerId, victimId, spill, at, safe, stunned)
		if type(victimId) ~= "number" or type(attackerId) ~= "number" then
			return
		end
		if type(id) == "number" then
			endShell(id)
		end
		local victim = capys[victimId]
		if victim then
			if type(safe) == "number" then
				victim.SafeUntil = safe
			end
			victim.Squash = os.clock()
		end
		if victimId == myId and type(stunned) == "number" then
			stunnedUntil = math.max(stunnedUntil, stunned)
		end
		if type(at) == "table" and type(at[1]) == "number" and type(at[2]) == "number" and type(at[3]) == "number" then
			local position = Vector3.new(at[1], at[2] + 0.5, at[3])
			local color = colorOf(attackerId)
			api:Effect("Stars", position, { color, Color3.new(1, 1, 1) })
			if not reduced then
				api:Effect("Poof", position)
			end
			floatText(position + Vector3.new(0, 3.5, 0), "BOOM!", Theme.Colors.Yellow, 44, 0.8, 4)
			if type(spill) == "number" and spill > 0 then
				floatText(position + Vector3.new(0, 1.5, 0), `-{spill} {Rules.UNIT}`, Theme.Colors.Red, 30, 1, 3)
			end
			if victimId == myId or attackerId == myId then
				api:Sound("Hit")
			end
		end
	end)

	-- Every frame ----------------------------------------------------------------------------------------------------
	local lastClock = os.clock()
	local minZoomSaved: number? = nil
	local zoomFor = 1
	api:RenderStep(function()
		local now = api:Now()
		local clock = os.clock()
		local dt = math.min(clock - lastClock, 0.1)
		lastClock = clock

		-- Capys on everyone's character.
		for userId, slot in slots do
			local character = api:CharacterOf(userId)
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local capy = capys[userId]
			if not root or not character then
				if capy then
					if capy.Model then
						capy.Model.Parent = nil
					end
					capy.Tag.Enabled = false
					if capy.Ring then
						capy.Ring.Transparency = 1
					end
				end
				continue
			end
			hideAvatar(character)
			if not capy then
				capy = makeCapy(userId, slot)
				refreshTags()
			end
			local c = capy :: Capy
			if not c.Model then
				local source = template("CapyBoomCapy")
				if source then
					local copy = source:Clone() :: Model
					quiet(copy)
					c.Parts = paintCapy(copy, colorOf(userId))
					scaleBy(copy, c.Scale)
					c.Model = copy
				end
			end
			local entry = mass[userId]
			local target = Rules.ScaleOf(if entry then entry[1] else Rules.START_MASS)
			if math.abs(target - c.Scale) > 0.002 then
				c.Scale += (target - c.Scale) * math.min(1, dt * GROW)
			end
			-- The look of the moment: a gulp after eating, a squash after a pop, a bounce on the move.
			local gulp = math.max(0, 1 - (clock - c.Chomp) / 0.25)
			local squash = math.max(0, 1 - (clock - c.Squash) / 0.3)
			local drawn = c.Scale * (1 + 0.09 * gulp * gulp - 0.12 * squash)

			local velocity = flat(root.AssemblyLinearVelocity)
			local moving = velocity.Magnitude > 2
			local bob = if moving then math.abs(math.sin(clock * 11 + c.Bob)) * 0.32 * c.Scale else 0
			local kick = math.max(0, 1 - (clock - c.Recoil) / 0.18)
			local look = flat(root.CFrame.LookVector)
			if look.Magnitude < 0.01 then
				look = -Vector3.zAxis
			end
			look = look.Unit
			-- After a shot the capy turns to where it fired for a moment.
			local face = c.FaceDir
			if face then
				local age = clock - c.FaceAt
				if age >= FACE then
					c.FaceDir = nil
				else
					local k = math.min(age / 0.08, 1) * math.min((FACE - age) / 0.15, 1)
					local blended = look:Lerp(face, k)
					if blended.Magnitude > 0.05 then
						look = blended.Unit
					end
				end
			end
			local base = Vector3.new(root.Position.X, root.Position.Y - ROOT_TO_GROUND + bob, root.Position.Z)
			local model = c.Model
			if model then
				if model.Parent == nil then
					model.Parent = api.World
				end
				if math.abs((model:GetAttribute("PP_Drawn") or 0) - drawn) > 0.004 then
					scaleBy(model, drawn)
					model:SetAttribute("PP_Drawn", drawn)
				end
				model:PivotTo(CFrame.lookAt(base - look * (kick * 0.5), base - look * (kick * 0.5) + look))
				-- Safe after a pop: the capy blinks.
				local blink = c.Parts[1] ~= nil and (c.SafeUntil > now) and math.floor(clock * 10) % 2 == 0
				if blink ~= c.Blink then
					c.Blink = blink
					for _, part in c.Parts do
						part.LocalTransparencyModifier = if blink then 0.6 else 0
					end
				end
			end
			c.Tag.Enabled = true
			c.Tag.Adornee = root
			c.Tag.StudsOffsetWorldSpace = Vector3.new(0, 5.4 * drawn - ROOT_TO_GROUND + 2.2, 0)
			if c.Ring then
				local size = 7.5 * c.Scale
				c.Ring.Size = Vector3.new(0.12, size, size)
				c.Ring.CFrame = CFrame.new(
					Vector3.new(root.Position.X, root.Position.Y - ROOT_TO_GROUND + 0.1, root.Position.Z)
				) * CFrame.Angles(0, 0, math.rad(90))
				c.Ring.Transparency = 0.45 + 0.15 * math.sin(clock * 5)
			end
		end

		-- The camera keeps clear of a big capy.
		local mine = capys[myId]
		if mine and localPlayer and math.abs(mine.Scale - zoomFor) > 0.08 then
			zoomFor = mine.Scale
			if minZoomSaved == nil then
				minZoomSaved = localPlayer.CameraMinZoomDistance
			end
			pcall(function()
				localPlayer.CameraMinZoomDistance = math.max(minZoomSaved :: number, 10 + 5 * (zoomFor - 1))
			end)
		end

		-- Snacks: flying, lying (bobbing and turning), or flying to whoever ate them.
		for id, snack in snacks do
			local model = snack.Model
			if snack.TakenAt then
				local k = (clock - snack.TakenAt) / FLY
				local character = snack.TakenBy and api:CharacterOf(snack.TakenBy)
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if k >= 1 or not model or not snack.From then
					giveBack(snack)
					snacks[id] = nil
				else
					local target = if root then root.Position else snack.From :: Vector3
					local position = (snack.From :: Vector3):Lerp(target, k)
						+ Vector3.new(0, math.sin(k * math.pi) * 1.5, 0)
					model:PivotTo(CFrame.new(position) * CFrame.Angles(0, clock * 6, 0))
					scaleBy(model, SNACK_SCALE * math.max(0.2, 1 - k * 0.7))
				end
				continue
			end
			if model then
				local position = snackWorld(snack, now)
				if position then
					local data = snack.Data
					local landed = Rules.Landed(data, now)
					local spin = clock * (if landed then 1.6 else 7) + id
					model:PivotTo(CFrame.new(position) * CFrame.Angles(0, spin, 0))
					-- A sprouting snack grows in; others are at full size once drawn.
					if data[8] == Rules.SPROUT and now - data[7] < Rules.FLIGHT[0] then
						scaleBy(model, SNACK_SCALE * math.clamp((now - data[7]) / Rules.FLIGHT[0], 0.05, 1))
						snack.Added = math.min(snack.Added, clock)
					elseif model:GetAttribute("PP_Sized") ~= true then
						scaleBy(model, SNACK_SCALE)
						model:SetAttribute("PP_Sized", true)
					end
					if snack.Beam and center then
						snack.Beam.CFrame = CFrame.new(position + Vector3.new(0, 34, 0))
							* CFrame.Angles(0, 0, math.rad(90))
						snack.Beam.Transparency = 0.55 + 0.15 * math.sin(clock * 4)
					end
				end
			end
		end
		for id, at in gone do
			if clock - at > 5 then
				gone[id] = nil
			end
		end

		-- Shells.
		for id, shell in shells do
			local age = now - shell.T0
			if age >= MAX_AGE + 0.05 then
				endShell(id)
			elseif age >= 0 then
				shell.Model:PivotTo(CFrame.new(Rules.ShellAt(shell.Origin, shell.Dir, age)))
			end
		end

		-- SNACK DROP markers pulse until the drop has landed.
		for index = #warnings, 1, -1 do
			local warning = warnings[index]
			if now > warning.LandAt + 0.6 then
				warning.Disc:Destroy()
				warning.Beam:Destroy()
				table.remove(warnings, index)
			else
				local pulse = 0.5 + 0.5 * math.sin(clock * 9)
				warning.Disc.Transparency = 0.5 + 0.3 * pulse
				warning.Beam.Transparency = 0.65 + 0.2 * pulse
			end
		end

		-- Floating words.
		for index = #floaters, 1, -1 do
			local floater = floaters[index]
			local age = clock - floater.Born
			if age >= floater.Life or not floater.Anchor.Parent then
				floater.Anchor:Destroy()
				table.remove(floaters, index)
			else
				floater.Anchor.Position = floater.From + Vector3.new(0, floater.Rise * age / floater.Life, 0)
				floater.Label.TextTransparency = math.max(0, (age / floater.Life - 0.5) * 2)
			end
		end

		-- The FEAST banner and the BOOM button.
		if feast then
			feastLabel.TextColor3 = Theme.Colors.Yellow:Lerp(Color3.new(1, 1, 1), 0.5 + 0.5 * math.sin(clock * 8))
		end
		local wait = readyAt - now
		button:SetFill(if wait > 0 then math.clamp(wait / Rules.RELOAD, 0, 1) else 0)
	end)

	-- Put everything back when the round ends (the rest is in api.World).
	api:Track(function()
		for item, transparency in hiddenPart do
			if item.Parent then
				local visual = item :: any
				visual.Transparency = transparency
			end
		end
		for gui, enabled in hiddenGui do
			if gui.Parent then
				gui.Enabled = enabled
			end
		end
		for humanoid, kind in hiddenName do
			if humanoid.Parent then
				humanoid.DisplayDistanceType = kind
			end
		end
		if minZoomSaved ~= nil and localPlayer then
			pcall(function()
				localPlayer.CameraMinZoomDistance = minZoomSaved :: number
			end)
		end
		for _, pool in pools do
			for _, model in pool do
				model:Destroy()
			end
		end
		for _, model in shellPool do
			model:Destroy()
		end
		for _, copy in templates do
			copy:Destroy()
		end
	end)
end

return CapyGoBoom
