-- THE HARVESTER, Hollow Night's 1-in-500 title (the crate seasons' design: "A blackletter title that
-- looks lit from inside: a gold-to-ember gradient that flickers like a candle, embers drifting up
-- off it ... an orange outline glow that breathes, and a flicker every few seconds, like a candle in
-- a draft"; owner: "Hollow night comes first ... I want it to look insane."). The server builds the
-- name tag (Shared/NameTag tags the title PP_HarvesterTitle); this device brings every one in view
-- to life:
--   * the glow round the letters breathes, and the fire inside them moves up and down a little;
--   * every few seconds the letters flicker, two or three quick dips, as in a draught;
--   * embers drift up off it and fade (not with reduced effects).
-- Only tags within their 90 studs and on screen are touched, in one loop, so a full server costs
-- next to nothing.
--
-- The chat tag (the design: "In chat. [THE HARVESTER] LeafPileLeo: gg"): a message from someone
-- wearing a title with a look of its own (Cosmetics' Look; their PP_Title) gets the title in its
-- season's colour before their name. Only with Roblox's TextChatService chat (the game's).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage.Shared
local Cosmetics = require(Shared.Cosmetics)
local NameTag = require(Shared.NameTag)
local SeasonArt = require(Shared.SeasonArt)
local Seasons = require(Shared.Seasons)

local State = require(script.Parent.Parent.State)

local TitleController = {}

local RANGE = 90 -- studs: the name tag's own MaxDistance
local MAX_EMBERS = 5 -- per title at once
local EMBER_EVERY = 0.38 -- seconds between embers, about
local EMBER_COLORS = { Color3.fromRGB(255, 226, 140), Color3.fromRGB(255, 160, 60), Color3.fromRGB(255, 106, 31) }

type Ember = { Frame: GuiObject, Born: number, Life: number, X: number, Drift: number }
type Lit = {
	Label: TextLabel,
	Gui: BillboardGui,
	Glow: UIStroke?,
	Flame: UIGradient?,
	Seed: number,
	FlickerAt: number, -- when the next flicker starts
	NextEmber: number,
	Embers: { Ember },
}

local lit: { [TextLabel]: Lit } = {}

local function ember(entry: Lit): GuiObject
	local dot: GuiObject
	if SeasonArt.Ember ~= "" then
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Image = SeasonArt.Ember
		dot = image
	else
		local frame = Instance.new("Frame")
		frame.BorderSizePixel = 0
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = frame
		dot = frame
	end
	dot.Name = "Ember"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.ZIndex = 3
	dot.Parent = entry.Gui
	return dot
end

local function forget(label: Instance)
	local entry = lit[label :: TextLabel]
	if entry then
		for _, spark in entry.Embers do
			spark.Frame:Destroy()
		end
		lit[label :: TextLabel] = nil
	end
end

local function add(label: Instance)
	if not label:IsA("TextLabel") or lit[label] then
		return
	end
	local gui = label:FindFirstAncestorWhichIsA("BillboardGui")
	if not gui then
		return
	end
	lit[label] = {
		Label = label,
		Gui = gui,
		Glow = label:FindFirstChildOfClass("UIStroke"),
		Flame = label:FindFirstChildOfClass("UIGradient"),
		Seed = math.random() * 10,
		FlickerAt = os.clock() + 1 + math.random() * 4,
		NextEmber = os.clock() + math.random() * EMBER_EVERY,
		Embers = {},
	}
end

-- Where the tag is in the world (the head it hangs over), or nil.
local function anchorOf(gui: BillboardGui): Vector3?
	local adornee = gui.Adornee or gui.Parent
	if adornee and adornee:IsA("BasePart") then
		return adornee.Position + gui.StudsOffset
	end
	return nil
end

-- How bright a flicker leaves the letters `into` seconds in (1: steady): two or three quick dips.
local function flicker(into: number, seed: number): number
	if into < 0 or into > 0.55 then
		return 1
	end
	local dips = 0.5 + 0.5 * math.sin(into * 38 + seed)
	return 1 - 0.38 * dips * (1 - into / 0.55)
end

local function step()
	local camera = workspace.CurrentCamera
	if not camera or next(lit) == nil then
		return
	end
	local now = os.clock()
	local reduced = State.ReducedEffects()
	for label, entry in lit do
		if not label.Parent or not entry.Gui.Parent then
			forget(label)
			continue
		end
		local at = anchorOf(entry.Gui)
		local visible = at ~= nil and (at - camera.CFrame.Position).Magnitude <= RANGE
		if visible then
			local _, onScreen = camera:WorldToViewportPoint(at :: Vector3)
			visible = onScreen
		end
		if not visible then
			continue
		end
		local t = now + entry.Seed
		-- The glow breathes; the fire inside the letters moves.
		local breath = 0.5 + 0.5 * math.sin(t * 2.1)
		if entry.Glow then
			entry.Glow.Thickness = 1.3 + 1.3 * breath
			entry.Glow.Transparency = 0.5 - 0.3 * breath
		end
		if entry.Flame then
			entry.Flame.Offset = Vector2.new(0, 0.07 * math.sin(t * 1.7))
		end
		-- A flicker every few seconds.
		local bright = 1
		if not reduced then
			if now > entry.FlickerAt + 0.6 then
				entry.FlickerAt = now + 2.5 + math.random() * 3.5
			end
			bright = flicker(now - entry.FlickerAt, entry.Seed)
		end
		label.TextColor3 = Color3.new(bright, bright * 0.96, bright * 0.9)
		-- Embers rise off it.
		if reduced then
			for _, spark in entry.Embers do
				spark.Frame:Destroy()
			end
			table.clear(entry.Embers)
			continue
		end
		if now >= entry.NextEmber and #entry.Embers < MAX_EMBERS then
			entry.NextEmber = now + EMBER_EVERY * (0.6 + math.random() * 0.8)
			local frame = ember(entry)
			table.insert(entry.Embers, {
				Frame = frame,
				Born = now,
				Life = 1.1 + math.random() * 0.8,
				X = (math.random() - 0.5) * 0.7,
				Drift = (math.random() - 0.5) * 0.12,
			})
		end
		local top = label.Position.Y.Scale
		local rowHeight = label.Size.Y.Scale
		for index = #entry.Embers, 1, -1 do
			local spark = entry.Embers[index]
			local age = (now - spark.Born) / spark.Life
			if age >= 1 then
				spark.Frame:Destroy()
				table.remove(entry.Embers, index)
				continue
			end
			local size = math.floor(4 - 2 * age + 0.5)
			spark.Frame.Size = UDim2.fromOffset(size, size)
			spark.Frame.Position = UDim2.fromScale(
				0.5 + spark.X + spark.Drift * age + 0.02 * math.sin(age * 9 + spark.Born),
				top + rowHeight * 0.6 - (top + rowHeight * 0.6 + 0.25) * age
			)
			local color = EMBER_COLORS[math.clamp(1 + math.floor(age * #EMBER_COLORS), 1, #EMBER_COLORS)]
			if spark.Frame:IsA("ImageLabel") then
				spark.Frame.ImageColor3 = color
				spark.Frame.ImageTransparency = age * age
			else
				spark.Frame.BackgroundColor3 = color
				spark.Frame.BackgroundTransparency = 0.1 + 0.9 * age * age
			end
		end
	end
end

-- [THE HARVESTER] before the sender's name in chat.
local function chatTag(message: TextChatMessage): TextChatMessageProperties?
	local properties = Instance.new("TextChatMessageProperties")
	local source = message.TextSource
	local sender = source and Players:GetPlayerByUserId(source.UserId)
	local id = sender and sender:GetAttribute("PP_Title")
	local title = if type(id) == "string" and id ~= "" then Cosmetics.Get(id) else nil
	if title and title.Look then
		local season = if title.Season then Seasons.Get(title.Season) else nil
		local c = if season then season.Colors.Title else { 255, 106, 31 }
		local hex = Color3.fromRGB(c[1], c[2], c[3]):ToHex()
		properties.PrefixText = `<font color="#{hex}">[{string.upper(title.Name)}]</font> {message.PrefixText}`
	end
	return properties
end

function TitleController.Start()
	for _, label in CollectionService:GetTagged(NameTag.HarvesterTag) do
		add(label)
	end
	CollectionService:GetInstanceAddedSignal(NameTag.HarvesterTag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(NameTag.HarvesterTag):Connect(forget)
	RunService.RenderStepped:Connect(step)

	local ok, err = pcall(function()
		if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
			TextChatService.OnIncomingMessage = chatTag
		end
	end)
	if not ok then
		warn(`[TitleController] chat tag: {err}`)
	end
end

return TitleController
