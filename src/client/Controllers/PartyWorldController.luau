-- Parties in the world (owner: "Also make the party system insane. I want it to look super epic."),
-- drawn by each device for itself in the party's colour (Client/PartyView):
--   * In the lobby: a glowing ring at your party mates' feet (two rings: a bright one and a soft
--     one round it that breathes), a sparkly beam linking you to each of them while they're within
--     LINK_RANGE studs (it arcs up between you and its sparkles run along it), and a crest over
--     everyone in a party: their party's emblem and name on a pill of its colour, just above the
--     server's name tag (PP_Nameplate, which this doesn't touch).
--   * In a round: an outline in the party's colour on your party mates who are still in it, seen
--     through walls so you can find them (in a team game it keeps their team's colour inside, and the
--     round's own team outline steps aside for it: RoundController).
-- Light for phones: the rings are handle adornments (no parts, nothing to simulate), the beams and
-- crests are one each per person, everything hangs on their character (so it goes with it), and
-- nothing runs every frame: it's set up when something changes (a party, a phase, a character), with
-- a check every CHECK seconds for who's within reach and characters that loaded late. A round
-- starting or ending, someone leaving the party or the server takes theirs away.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameState = require(Shared.GameState)
local Teams = require(Shared.Teams)

local PartyView = require(script.Parent.Parent.PartyView)
local PartyKit = require(script.Parent.Parent.UI.PartyKit)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local PartyWorldController = {}

local LOBBY = { Waiting = true, Intermission = true, Voting = true, Cleanup = true }
local ROUND = { Preparing = true, InRound = true }
local CHECK = 0.5 -- seconds between checks of who's in reach (and late characters)
local LINK_RANGE = 80 -- studs: farther apart than this, the link beam rests
local CREST_DISTANCE = 80 -- studs: crests (like name tags) don't show from farther away
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local WHITE = Color3.new(1, 1, 1)
local RING = 2.3 -- studs: the bright ring's radius at the feet
-- The crest: a pill of this many pixels, just above the name tag (220 x 54, 2.4 studs over the head).
local CREST = Vector2.new(210, 38)
local NAMEPLATE_HALF = 27

-- Names the harness looks for.
PartyWorldController.Names = {
	Ring = "PP_PartyRing",
	Glow = "PP_PartyRingGlow",
	Crest = "PP_PartyCrest",
	Link = "PP_PartyLink",
	Highlight = "PP_PartyHighlight",
}
local NAMES = PartyWorldController.Names

type Ring = { Root: BasePart, Bright: CylinderHandleAdornment, Glow: CylinderHandleAdornment, Color: Color3 }
type Crest = { Head: BasePart, Gui: BillboardGui, Key: string }
type Link = { From: BasePart, To: BasePart, Beam: Beam, A0: Attachment, A1: Attachment, Color: Color3 }

local player = Players.LocalPlayer
local folder: Folder
local rings: { [Player]: Ring } = {}
local crests: { [Player]: Crest } = {}
local links: { [Player]: Link } = {}
local outlines: { [Player]: Highlight } = {}
local outlineTeams: { [Player]: string } = {} -- the team each outline's fill shows ("" for none)
local queued = false
local watched: { [any]: boolean } = {}

local function phase(): string
	return GameState.Get("Phase") or "Waiting"
end

local function lobbyUp(): boolean
	local now = phase()
	return LOBBY[now] == true and not (now == "Cleanup" and (GameState.Get("Replay") or "") ~= "")
end

local function partOf(character: Model?, name: string): BasePart?
	local part = character and character:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part else nil
end

local function alive(instance: Instance?): boolean
	return instance ~= nil and instance.Parent ~= nil
end

-- Rings -------------------------------------------------------------------------------------------------

local function dropRing(who: Player)
	local ring = rings[who]
	rings[who] = nil
	if ring then
		ring.Bright:Destroy()
		ring.Glow:Destroy()
	end
end

-- How far under the root the feet are (the hips' height plus half the root).
local function feetBelow(character: Model, root: BasePart): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hips = if humanoid then humanoid.HipHeight else 2
	return hips + root.Size.Y / 2 - 0.12
end

local function makeRing(who: Player, root: BasePart, color: Color3)
	local character = root.Parent :: Model
	local flat = CFrame.new(0, -feetBelow(character, root), 0) * CFrame.Angles(math.rad(90), 0, 0)
	local bright = UIKit.new("CylinderHandleAdornment", {
		Name = NAMES.Ring,
		Adornee = root,
		CFrame = flat,
		Radius = RING,
		InnerRadius = RING - 0.32,
		Height = 0.12,
		Color3 = color,
		Transparency = 0.05,
		AlwaysOnTop = false,
		ZIndex = 1,
		Parent = root,
	})
	local glow = UIKit.new("CylinderHandleAdornment", {
		Name = NAMES.Glow,
		Adornee = root,
		CFrame = flat,
		Radius = RING + 0.55,
		InnerRadius = RING - 0.1,
		Height = 0.06,
		Color3 = PartyKit.Lighter(color, 0.35),
		Transparency = 0.6,
		AlwaysOnTop = false,
		ZIndex = 0,
		Parent = root,
	})
	PartyKit.Loop(glow, 1.1, { Radius = RING + 1.1, Transparency = 0.88 })
	rings[who] = { Root = root, Bright = bright, Glow = glow, Color = color }
end

-- Crests ------------------------------------------------------------------------------------------------

local function dropCrest(who: Player)
	local crest = crests[who]
	crests[who] = nil
	if crest then
		crest.Gui:Destroy()
	end
end

local function makeCrest(who: Player, head: BasePart, info: PartyView.Info)
	local text = string.upper(info.Name)
	local textWidth = math.ceil(UIKit.TextWidth(text, 18, Theme.Fonts.Display))
	local width = math.min(CREST.X + 60, 10 + 30 + 8 + textWidth + 14)
	local gui = UIKit.new("BillboardGui", {
		Name = NAMES.Crest,
		Adornee = head,
		Size = UDim2.fromOffset(width, CREST.Y),
		StudsOffset = Vector3.new(0, 2.4, 0), -- where the name tag is...
		SizeOffset = Vector2.new(0, 0.5 + (NAMEPLATE_HALF + 4) / CREST.Y), -- ...and just above it
		MaxDistance = CREST_DISTANCE,
		LightInfluence = 0,
		AlwaysOnTop = false,
		ResetOnSpawn = false,
	})
	local pill = UIKit.new("Frame", {
		Name = "Pill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.1,
		Parent = gui,
		Children = {
			UIKit.Round(),
			UIKit.Gradient(PartyKit.Darker(info.Color, 0.1), PartyKit.Darker(info.Color, 0.5)),
			UIKit.new("UIStroke", { Color = WHITE, Thickness = 2, Transparency = 0.1 }),
		},
	})
	local emblem = UIKit.new("Frame", {
		Name = "Emblem",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.fromOffset(CREST.Y - 8, CREST.Y - 8),
		BackgroundColor3 = WHITE,
		Parent = pill,
		Children = { UIKit.Round(), UIKit.Gradient(PartyKit.Lighter(info.Color, 0.45), info.Color) },
	})
	UIKit.Label({
		Name = "Icon",
		Text = info.Emblem,
		TextSize = 20,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = emblem,
	})
	UIKit.Label({
		Name = "Name",
		Text = text,
		Font = Theme.Fonts.Display,
		TextSize = 18,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(CREST.Y + 2, 0),
		Size = UDim2.new(1, -(CREST.Y + 8), 1, 0),
		Parent = pill,
		Children = { UIKit.TextStroke(0.1) },
	})
	gui.Parent = head
	crests[who] = { Head = head, Gui = gui, Key = `{info.Id}|{info.Name}|{info.ColorIndex}|{info.EmblemIndex}` }
end

-- Links ---------------------------------------------------------------------------------------------------

local function dropLink(who: Player)
	local link = links[who]
	links[who] = nil
	if link then
		link.Beam:Destroy()
		link.A0:Destroy()
		link.A1:Destroy()
	end
end

local function attachment(root: BasePart): Attachment
	-- Its X axis points up, so the beam's curve arcs up between the two of you.
	return UIKit.new("Attachment", {
		Name = NAMES.Link,
		CFrame = CFrame.fromMatrix(Vector3.new(0, -0.6, 0), Vector3.new(0, 1, 0), Vector3.new(1, 0, 0)),
		Parent = root,
	})
end

local function makeLink(who: Player, from: BasePart, to: BasePart, color: Color3)
	local a0, a1 = attachment(from), attachment(to)
	local beam = UIKit.new("Beam", {
		Name = NAMES.Link,
		Attachment0 = a0,
		Attachment1 = a1,
		Texture = SPARKLE,
		TextureMode = Enum.TextureMode.Wrap,
		TextureLength = 2.5,
		TextureSpeed = 1.4,
		LightEmission = 1,
		LightInfluence = 0,
		Width0 = 0.7,
		Width1 = 0.7,
		CurveSize0 = 3,
		CurveSize1 = -3,
		Segments = 16,
		FaceCamera = true,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, color),
			ColorSequenceKeypoint.new(0.5, PartyKit.Lighter(color, 0.6)),
			ColorSequenceKeypoint.new(1, color),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(0.5, 0.1),
			NumberSequenceKeypoint.new(1, 0.6),
		}),
		Parent = folder,
	})
	links[who] = { From = from, To = to, Beam = beam, A0 = a0, A1 = a1, Color = color }
end

-- Outlines in rounds ------------------------------------------------------------------------------------

local function dropOutline(who: Player)
	local outline = outlines[who]
	outlines[who] = nil
	outlineTeams[who] = nil
	if outline then
		outline:Destroy()
	end
end

local function teamOf(who: Player): string
	local team = who:GetAttribute("PP_Team")
	return if type(team) == "string" then team else ""
end

local function makeOutline(who: Player, character: Model, color: Color3)
	local team = teamOf(who)
	local teamColor = Teams.Colors[team]
	outlineTeams[who] = team
	outlines[who] = UIKit.new("Highlight", {
		Name = NAMES.Highlight,
		Adornee = character,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		OutlineColor = color,
		OutlineTransparency = 0,
		FillColor = teamColor or color,
		FillTransparency = if teamColor then 0.8 else 1,
		Parent = character,
	})
end

-- Keeping up --------------------------------------------------------------------------------------------

local function clearAll()
	for who in rings do
		dropRing(who)
	end
	for who in crests do
		dropCrest(who)
	end
	for who in links do
		dropLink(who)
	end
	for who in outlines do
		dropOutline(who)
	end
end

local function sync()
	local mine = PartyView.Mine()
	local inLobby = lobbyUp()
	local inRound = ROUND[phase()] == true
	local myRoot = partOf(player.Character, "HumanoidRootPart")
	for _, who in Players:GetPlayers() do
		local theirs = PartyView.PartyOf(who)
		local mate = mine ~= nil and theirs == mine and who ~= player
		local character = who.Character
		local root = partOf(character, "HumanoidRootPart")
		local head = partOf(character, "Head")
		local info = if theirs then PartyView.Info(theirs) else nil

		-- The crest over everyone in a party, in the lobby.
		local crest = crests[who]
		if inLobby and info and head then
			local key = `{info.Id}|{info.Name}|{info.ColorIndex}|{info.EmblemIndex}`
			if not crest or crest.Head ~= head or crest.Key ~= key or not alive(crest.Gui) then
				dropCrest(who)
				makeCrest(who, head, info)
			end
		elseif crest then
			dropCrest(who)
		end

		-- The ring at a mate's feet and the link to them, in the lobby.
		local ring = rings[who]
		if inLobby and mate and info and root then
			if not ring or ring.Root ~= root or ring.Color ~= info.Color or not alive(ring.Bright) then
				dropRing(who)
				makeRing(who, root, info.Color)
			end
		elseif ring then
			dropRing(who)
		end
		local link = links[who]
		if inLobby and mate and info and root and myRoot then
			if
				not link
				or link.From ~= myRoot
				or link.To ~= root
				or link.Color ~= info.Color
				or not alive(link.Beam)
				or not alive(link.A0)
				or not alive(link.A1)
			then
				dropLink(who)
				makeLink(who, myRoot, root, info.Color)
				link = links[who]
			end
			if link then
				link.Beam.Enabled = (root.Position - myRoot.Position).Magnitude <= LINK_RANGE
			end
		elseif link then
			dropLink(who)
		end

		-- The outline on a mate still in the round.
		local outline = outlines[who]
		local playing = who:GetAttribute("PP_InRound") == true and who:GetAttribute("PP_Alive") == true
		if inRound and mate and info and character and playing then
			if
				not outline
				or outline.Adornee ~= character
				or outline.OutlineColor ~= info.Color
				or outlineTeams[who] ~= teamOf(who)
				or not alive(outline)
			then
				dropOutline(who)
				makeOutline(who, character, info.Color)
			end
		elseif outline then
			dropOutline(who)
		end
	end
	-- Whoever left the server takes theirs along.
	for _, list in { rings, crests, links, outlines } do
		for who in list :: { [Player]: any } do
			if not who.Parent then
				dropRing(who)
				dropCrest(who)
				dropLink(who)
				dropOutline(who)
			end
		end
	end
end

local function queueSync()
	if queued then
		return
	end
	queued = true
	task.defer(function()
		queued = false
		sync()
	end)
end

local function watch(who: Player)
	if watched[who] then
		return
	end
	watched[who] = true
	who.CharacterAdded:Connect(queueSync)
	for _, attribute in { "PP_InRound", "PP_Alive", "PP_Team" } do
		who:GetAttributeChangedSignal(attribute):Connect(queueSync)
	end
end

-- What's in the world, for the harnesses: how many of each, and whose.
function PartyWorldController.Status(): { [string]: any }
	local function names(list: { [Player]: any }): { string }
		local out = {}
		for who in list do
			table.insert(out, who.Name)
		end
		table.sort(out)
		return out
	end
	local beamsOn = 0
	for _, link in links do
		if link.Beam.Enabled then
			beamsOn += 1
		end
	end
	return {
		Rings = names(rings),
		Crests = names(crests),
		Links = names(links),
		LinksShowing = beamsOn,
		Outlines = names(outlines),
	}
end

function PartyWorldController.Start(_context)
	PartyView.Start()
	folder = UIKit.new("Folder", { Name = "PartyFX", Parent = workspace })
	for _, who in Players:GetPlayers() do
		watch(who)
	end
	Players.PlayerAdded:Connect(function(who)
		watch(who)
		queueSync()
	end)
	Players.PlayerRemoving:Connect(function(who)
		watched[who] = nil
		dropRing(who)
		dropCrest(who)
		dropLink(who)
		dropOutline(who)
	end)
	PartyView.Changed:Connect(queueSync)
	GameState.Changed("Phase", function()
		clearAll() -- a round starting or ending: everyone's somewhere new
		queueSync()
	end)
	GameState.Changed("Replay", queueSync)
	task.spawn(function()
		while true do
			task.wait(CHECK)
			local ok, err = pcall(sync)
			if not ok then
				warn(`[PartyWorldController] {err}`)
				task.wait(5)
			end
		end
	end)
end

return PartyWorldController
