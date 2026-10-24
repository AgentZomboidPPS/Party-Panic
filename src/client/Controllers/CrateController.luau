-- The crate season on this player's screen (owner: "Hollow night comes first I want you to actually work
-- on adding it to the game right now ... Also do all of your ideas. This has to be sick."; Shared/
-- Seasons, Services/CrateService). It puts together:
--   * the crate window (Crates/CrateMenu), from State.OpenScreen:Fire("Crates", tab): the profile
--     card's keys and crates (HudController; the lobby's row had a crate chip until layout A, owner:
--     "We dont need a separate open crate button"), the altars (out of keys: the key shop) and the
--     shop's crate items;
--   * OPEN: walks the player to the nearest free altar round the pile (around it, not through it)
--     and opens there; OPEN HERE (or every altar busy) opens over their head; OPEN 5;
--   * every opening in the server, played where it happens (Crates/CrateShow), with the pile, the
--     wisps and the crows joining in (Controllers/SeasonWorldController), and the opener's own prize
--     card when the reel ends (Crates/CrateMoments);
--   * the banners for a pet or the title (this server's and every other server's), the cards for
--     keys and crates given, and the season's welcome the first time someone plays it.
-- Sounds are the game's own effects (AudioController): a tick for the reel (only near the show),
-- the burst and a stinger by tier.

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Seasons = require(Shared.Seasons)

local State = require(script.Parent.Parent.State)
local CrateMenu = require(script.Parent.Parent.Crates.CrateMenu)
local CrateMoments = require(script.Parent.Parent.Crates.CrateMoments)
local CrateShow = require(script.Parent.Parent.Crates.CrateShow)
local LootFly = require(script.Parent.Parent.Crates.LootFly)
local Haptics = require(script.Parent.Parent.Haptics)
local AudioController = require(script.Parent.AudioController)
local NotificationController = require(script.Parent.NotificationController)
local SeasonWorldController = require(script.Parent.SeasonWorldController)

local CrateController = {}

local player = Players.LocalPlayer
local remote = Remotes.Get("Crate")
local season = Seasons.CurrentSeason()

local ALTAR_REACH = 9 -- studs: close enough to open where they stand
local WALK_TIMEOUT = 14
local SOUND_RANGE = 70 -- studs from the camera: a show's sounds are heard this close

local RANK = { Title = 1, Pet = 2, Hat = 3, Effect = 4, Coins = 5 }

local walking = 0 -- bumped for every walk, so a new one (or anything that stops it) ends the last
local welcomed = false

-- (Less a round's keys and crate still flying in from its results card: Crates/LootFly.)
local function counts(): (number, number)
	local profile = State.Profile
	if not profile then
		return 0, 0
	end
	return LootFly.Shown("Crates", if profile.Crates then profile.Crates.Count or 0 else 0),
		LootFly.Shown("Keys", profile.Keys or 0)
end

local function rootOf(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- The free altars, nearest first (with where to stand: in front of each).
local function freeAltars(from: Vector3): { { Index: number, Stand: Vector3, Distance: number } }
	local list = {}
	for _, model in CollectionService:GetTagged("PP_CrateAltar") do
		if model:IsA("Model") and (model:GetAttribute("PP_AltarBusy") or 0) == 0 then
			local frame = model:GetPivot()
			local stand = (frame * CFrame.new(0, 0, -4.6)).Position
			table.insert(list, {
				Index = model:GetAttribute("PP_Altar") :: number,
				Stand = stand,
				Distance = (stand - from).Magnitude,
			})
		end
	end
	table.sort(list, function(a, b)
		return a.Distance < b.Distance
	end)
	return list
end

local function openAt(count: number, altar: number)
	remote:FireServer("Open", count, altar)
end

-- Walks to `stand` (round the pile, by Roblox's pathfinding when it finds a way), then calls
-- `arrived`. Gives up if the player takes over (moves away), a round pulls them in, or it's slow.
local function walkTo(stand: Vector3, arrived: () -> ())
	walking += 1
	local mine = walking
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = rootOf()
	if not humanoid or not root then
		return
	end
	task.spawn(function()
		local points = { stand }
		local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
		local ok = pcall(function()
			path:ComputeAsync(root.Position, stand)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			points = {}
			for _, waypoint in path:GetWaypoints() do
				table.insert(points, waypoint.Position)
			end
		end
		local deadline = os.clock() + WALK_TIMEOUT
		for _, point in points do
			if walking ~= mine or State.StillPlaying() or not root.Parent then
				return
			end
			humanoid:MoveTo(point)
			local reached = false
			local connection = humanoid.MoveToFinished:Connect(function(done)
				reached = done or true
			end)
			while not reached and os.clock() < deadline and walking == mine do
				task.wait(0.1)
				if (root.Position - point).Magnitude < 3 then
					reached = true
				end
			end
			connection:Disconnect()
			if os.clock() >= deadline then
				break
			end
		end
		if walking == mine and (root.Position - stand).Magnitude < ALTAR_REACH + 2 then
			arrived()
		end
	end)
end

-- OPEN (count 1 or 5) at the nearest free altar, or over their head (`here`, or none free).
local function open(count: number, here: boolean)
	local crates, keys = counts()
	if crates < count or keys < count then
		if keys < count then
			CrateMenu.Show("Keys")
		end
		return
	end
	if State.StillPlaying() then
		NotificationController.Show("Crates open in the lobby, after the round.", "info", 3)
		return
	end
	local root = rootOf()
	if here or not root then
		openAt(count, 0)
		return
	end
	local altars = freeAltars(root.Position)
	local best = altars[1]
	if not best then
		NotificationController.Show("The pile is busy: opening it right here!", "info", 3)
		openAt(count, 0)
		return
	end
	if best.Distance <= ALTAR_REACH then
		openAt(count, best.Index)
		return
	end
	walkTo(best.Stand, function()
		-- Still free? Else the next one, or right here.
		local now = rootOf()
		local list = freeAltars(if now then now.Position else best.Stand)
		local target = list[1]
		openAt(count, if target and target.Distance <= ALTAR_REACH + 2 then target.Index else 0)
	end)
end

-- A show's sounds, for a device close enough to hear it.
local function nearCamera(position: Vector3?): boolean
	local camera = workspace.CurrentCamera
	return position ~= nil and camera ~= nil and (camera.CFrame.Position - position).Magnitude < SOUND_RANGE
end

local function showPosition(show: { [string]: any }): Vector3?
	if (show.Altar or 0) > 0 then
		for _, model in CollectionService:GetTagged("PP_CrateAltar") do
			if model:IsA("Model") and model:GetAttribute("PP_Altar") == show.Altar then
				return model:GetPivot().Position
			end
		end
	end
	local who = Players:GetPlayerByUserId(show.UserId or 0)
	local character = who and who.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function onShow(show: { [string]: any })
	CrateShow.Play(show)
	local mine = show.UserId == player.UserId
	local position = showPosition(show)
	if mine or nearCamera(position) then
		AudioController.PlayOr("CrateOpen", "Splash")
	end
	-- The opener's card when the reel ends (whether or not the show is drawn here).
	if mine then
		walking += 1
		local revealAt = tonumber(show.RevealAt) or 3.4
		local wait = math.max(0, revealAt - (workspace:GetServerTimeNow() - (tonumber(show.At) or 0)))
		task.delay(wait, function()
			CrateMoments.Prize(show)
			-- The stinger for the best thing that came out.
			local best = 5
			for _, result in show.Results do
				best = math.min(best, RANK[result.Tier] or 5)
			end
			if best == 1 then
				AudioController.PlayOr("CrateTitle", "Victory")
			elseif best == 2 then
				AudioController.PlayOr("CratePet", "Victory")
			elseif best == 3 then
				AudioController.PlayOr("CrateHat", "Purchase")
			elseif best == 4 then
				AudioController.PlayOr("CrateEffect", "Pickup")
			else
				AudioController.PlayOr("CrateCoins", "Pickup")
			end
		end)
	end
end

local function onBanner(banner: { [string]: any })
	CrateMoments.Banner(banner)
	if banner.Elsewhere then
		return
	end
	SeasonWorldController.ScareCrows()
	if banner.Tier == "Title" then
		SeasonWorldController.TitleMoment()
	end
	-- The lobby-wide chime (the opener heard their own stinger already).
	if banner.UserId ~= player.UserId then
		AudioController.PlayOr(if banner.Tier == "Title" then "CrateTitle" else "CratePet", "Victory")
	end
end

-- The season's welcome, once: when they're in the lobby, past the first-join tutorial, with nothing
-- else on the screen.
local function tryWelcome()
	local profile = State.Profile
	if welcomed or not profile or not profile.CrateFlags or profile.CrateFlags.Welcome == season.Id then
		return
	end
	if not profile.TutorialDone or State.StillPlaying() then
		return
	end
	local phase = State.Phase()
	if phase ~= "Waiting" and phase ~= "Intermission" and phase ~= "Voting" then
		return
	end
	if
		player:GetAttribute("PP_Celebrating") == true
		or player:GetAttribute("PP_ResultsShowing") == true
		or player:GetAttribute("PP_CupPodium") == true
	then
		return
	end
	welcomed = true
	CrateMoments.Welcome(SeasonWorldController.TurnTrees, function()
		remote:FireServer("Welcome")
	end, function()
		task.delay(1.2, open, 1, false) -- (the welcome's crate is on its way)
	end)
end

function CrateController.Start(context)
	CrateMenu.Build(context)
	CrateMoments.Build()
	CrateShow.Start()
	CrateMenu.OnOpen = open
	CrateShow.Started = SeasonWorldController.ShowStarted
	CrateShow.Landed = SeasonWorldController.ShowLanded
	CrateShow.Tick = function(p: number, position: Vector3?)
		if nearCamera(position) and math.random() < 0.6 + p * 0.4 then
			AudioController.PlayOr("CrateTick", "Click")
		end
	end

	-- A round's keys and crate landing on the profile card's pills (HudController).
	LootFly.OnLand = function()
		AudioController.PlayOr("CrateTick", "Pickup")
		Haptics.Play("Tap")
	end

	remote.OnClientEvent:Connect(function(action, payload)
		if action == "Show" and type(payload) == "table" then
			onShow(payload)
		elseif action == "Banner" and type(payload) == "table" then
			onBanner(payload)
		elseif action == "Gift" and type(payload) == "table" then
			CrateMoments.Gift(payload)
		elseif action == "Denied" and payload == "NoKeys" then
			CrateMenu.Show("Keys")
		end
	end)
	State.OpenScreen:Connect(function(name, tab)
		if name == "Crates" then
			CrateMenu.Show(if type(tab) == "string" then tab else nil)
		end
	end)
	State.ProfileChanged:Connect(tryWelcome)
	State.GameState.Changed("Phase", tryWelcome)
	for _, attribute in { "PP_Celebrating", "PP_ResultsShowing", "PP_CupPodium", "PP_InRound" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if attribute == "PP_InRound" and State.InRound() then
				walking += 1 -- a round pulled them in: no walking to an altar any more
			end
			task.delay(1, tryWelcome)
		end)
	end
end

return CrateController
