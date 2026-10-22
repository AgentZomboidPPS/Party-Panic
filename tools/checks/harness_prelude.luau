-- Prelude for tools/checks/round_harness.py: module loader, stand-in players and recording remotes.
-- Everything below runs inside one Open Cloud Luau execution task on a real Roblox server.

local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local RealPlayers = game:GetService("Players")

local __log = {}
local __errors = {}
LogService.MessageOut:Connect(function(message, kind)
	if kind == Enum.MessageType.MessageError or kind == Enum.MessageType.MessageWarning then
		if #__errors < 80 then
			table.insert(__errors, kind.Name .. ": " .. string.sub(message, 1, 400))
		end
	end
end)
local function __note(text)
	if #__log < 300 then
		table.insert(__log, string.format("%6.2f %s", os.clock() % 10000, text))
	end
end

local __modules, __cache = {}, {}
local function __require(name)
	if __cache[name] == nil then
		local loader = __modules[name]
		if not loader then
			error("[harness] no module " .. name, 2)
		end
		__cache[name] = loader()
	end
	return __cache[name]
end

-- Client code goes through these: bundled ModuleScripts are "path tokens", not instances.
local __localPlayer = nil
function __req(target)
	if type(target) == "table" and target.__path then
		return __require(target.__path)
	end
	return require(target)
end
local function __moduleToken(full, name)
	return {
		__path = full,
		Name = name,
		IsA = function(_, className)
			return className == "ModuleScript"
		end,
	}
end
function __folder(path)
	return {
		__path = path,
		Name = string.match(path, "[^/]+$"),
		FindFirstChild = function(_, name)
			local full = path .. "/" .. name
			if __modules[full] then
				return __moduleToken(full, name)
			end
			return nil
		end,
		GetChildren = function()
			local children = {}
			for full in __modules do
				local name = string.match(full, "^" .. string.gsub(path, "%p", "%%%0") .. "/([^/]+)$")
				if name then
					table.insert(children, __moduleToken(full, name))
				end
			end
			table.sort(children, function(a, b)
				return a.Name < b.Name
			end)
			return children
		end,
	}
end

-- Recording remotes -------------------------------------------------------------------------------

local __events = {} -- { { t, remote, target, args... } }
local __eventCounts = {}
local function __record(remote, target, ...)
	local key = remote .. ":" .. tostring((...))
	__eventCounts[key] = (__eventCounts[key] or 0) + 1
	if #__events < 400 then
		local args = { ... }
		for index, value in args do
			local kind = typeof(value)
			if kind == "Vector3" then
				args[index] = string.format("(%.1f,%.1f,%.1f)", value.X, value.Y, value.Z)
			elseif kind ~= "string" and kind ~= "number" and kind ~= "boolean" then
				args[index] = kind
			end
		end
		table.insert(__events, { t = math.floor(os.clock() * 100) / 100, remote = remote, to = target, args = args })
	end
end

local __remoteObjects = {}
local __fakePlayers = {}
function __playerKey(player)
	return if type(player) == "table" then "__player:" .. player.Name else player
end
function __playerFromKey(key)
	if type(key) == "string" and string.sub(key, 1, 9) == "__player:" then
		local name = string.sub(key, 10)
		for _, player in __fakePlayers do
			if player.Name == name then
				return player
			end
		end
	end
	return key
end
__modules["Shared/Remotes"] = function()
	local Remotes = {}
	function Remotes.Get(name)
		if not __remoteObjects[name] then
			-- Server <-> client loopback: the stand-in client (Bot1) hears what it would hear.
			local bindable = Instance.new("BindableEvent")
			local clientBindable = Instance.new("BindableEvent")
			-- Bindables copy tables, so a stand-in player crosses as its name and is looked up again.
			local onServerEvent = {
				Connect = function(_, callback)
					return bindable.Event:Connect(function(key, ...)
						callback(__playerFromKey(key), ...)
					end)
				end,
			}
			__remoteObjects[name] = {
				Name = name,
				OnServerEvent = onServerEvent,
				OnClientEvent = clientBindable.Event,
				FireClient = function(_, player, ...)
					__record(name, if type(player) == "table" then player.Name else tostring(player), ...)
					if __localPlayer and player == __localPlayer then
						clientBindable:Fire(...)
					end
				end,
				FireAllClients = function(_, ...)
					__record(name, "all", ...)
					if __localPlayer then
						clientBindable:Fire(...)
					end
				end,
				FireServer = function(_, ...)
					if __localPlayer then
						bindable:Fire(__playerKey(__localPlayer), ...)
					end
				end,
				__bindable = bindable,
			}
		end
		return __remoteObjects[name]
	end
	return Remotes
end

-- Stand-in players ----------------------------------------------------------------------------------

local __byCharacter = {}
local __playerAdded = Instance.new("BindableEvent")
-- Not a BindableEvent: it would copy the stand-in player tables, so nobody could tell who left.
local __playerRemoving = (function()
	local handlers = {}
	local signal = {
		Event = {
			Connect = function(_, fn)
				table.insert(handlers, fn)
				return {
					Disconnect = function()
						local index = table.find(handlers, fn)
						if index then
							table.remove(handlers, index)
						end
					end,
				}
			end,
		},
	}
	function signal.Fire(_, ...)
		for _, fn in table.clone(handlers) do
			task.spawn(fn, ...)
		end
	end
	return signal
end)()
local __playersShim

local function __makeRig(name)
	local ok, rig = pcall(function()
		return RealPlayers:CreateHumanoidModelFromDescription(
			Instance.new("HumanoidDescription"),
			Enum.HumanoidRigType.R15
		)
	end)
	if not ok then
		error("[harness] couldn't build a rig: " .. tostring(rig))
	end
	rig.Name = name
	rig:PivotTo(CFrame.new(math.random(-20, 20), 5, math.random(-20, 20)))
	rig.Parent = workspace
	return rig
end

local function __newPlayer(index)
	local attributes = {}
	local signals = {}
	local backpack = Instance.new("Folder")
	backpack.Name = "Backpack"
	local playerGui = Instance.new("Folder")
	playerGui.Name = "PlayerGui"
	playerGui.Parent = game:GetService("ServerStorage")
	local characterAdded = Instance.new("BindableEvent")
	local player = {
		Name = "Bot" .. index,
		DisplayName = "Bot" .. index,
		UserId = 1000 + index,
		Parent = true,
		CharacterAdded = characterAdded.Event,
		__characterAdded = characterAdded,
	}
	function player.SetAttribute(_, key, value)
		attributes[key] = value
		if signals[key] then
			signals[key]:Fire()
		end
	end
	function player.GetAttribute(_, key)
		return attributes[key]
	end
	function player.GetAttributeChangedSignal(_, key)
		signals[key] = signals[key] or Instance.new("BindableEvent")
		return signals[key].Event
	end
	function player.FindFirstChildOfClass(_, className)
		if className == "Backpack" then
			return backpack
		end
		return nil
	end
	function player.FindFirstChild(_, name)
		if name == "Backpack" then
			return backpack
		elseif name == "PlayerGui" then
			return playerGui
		end
		return nil
	end
	player.WaitForChild = player.FindFirstChild
	player.PlayerGui = playerGui
	function player.IsA(_, className)
		return className == "Player" or className == "Instance"
	end
	function player.GetNetworkPing()
		return player.__ping or 0.06 -- a stand-in bot script can give one a slower connection
	end
	function player.Kick() end
	function player.LoadCharacterAsync(self)
		local old = self.Character
		if old then
			__byCharacter[old] = nil
			old:Destroy()
		end
		local rig = __makeRig(self.Name)
		self.Character = rig
		__byCharacter[rig] = self
		characterAdded:Fire(rig)
	end
	player.Character = __makeRig(player.Name)
	__byCharacter[player.Character] = player
	return player
end

__playersShim = setmetatable({
	LocalPlayer = nil,
	PlayerAdded = __playerAdded.Event,
	PlayerRemoving = __playerRemoving.Event,
	GetPlayers = function()
		return table.clone(__fakePlayers)
	end,
	GetPlayerFromCharacter = function(_, model)
		return __byCharacter[model]
	end,
	GetUserThumbnailAsync = function()
		return "", true
	end,
}, {
	__index = function(_, key)
		local value = RealPlayers[key]
		if type(value) == "function" then
			return function(_, ...)
				return value(RealPlayers, ...)
			end
		end
		return value
	end,
})

local function __service(name)
	if name == "Players" then
		return __playersShim
	end
	return game:GetService(name)
end

local function __wrap(real, overrides)
	return setmetatable(overrides, {
		__index = function(_, key)
			local value = real[key]
			if type(value) == "function" then
				return function(_, ...)
					return value(real, ...)
				end
			end
			return value
		end,
	})
end
local __realRun = game:GetService("RunService")
local __clientShims = {
	RunService = __wrap(__realRun, {
		RenderStepped = __realRun.Heartbeat,
		IsClient = function()
			return true
		end,
		IsServer = function()
			return false
		end,
		BindToRenderStep = function(_, _name, _priority, callback)
			__realRun.Heartbeat:Connect(callback)
		end,
		UnbindFromRenderStep = function() end,
	}),
	UserInputService = __wrap(game:GetService("UserInputService"), {
		TouchEnabled = __touchMode == true,
		KeyboardEnabled = __touchMode ~= true,
		MouseEnabled = __touchMode ~= true,
	}),
	StarterGui = __wrap(game:GetService("StarterGui"), {
		SetCore = function() end,
		SetCoreGuiEnabled = function() end,
		GetCore = function()
			return nil
		end,
	}),
}
function __clientService(name)
	return __clientShims[name] or game:GetService(name)
end

-- Snapshot of the arena (and the stand-in characters) for tools/preview/render.py.
local function __dumpParts(roots)
	local parts = {}
	local function r(x)
		return math.floor(x * 100 + 0.5) / 100
	end
	for _, root in roots do
		for _, item in root:GetDescendants() do
			if not item:IsA("BasePart") or item.Transparency >= 0.999 then
				continue
			end
			local cf = item.CFrame
			local entry = {
				c = item.ClassName,
				n = item.Name,
				s = { r(item.Size.X), r(item.Size.Y), r(item.Size.Z) },
				cf = { cf:GetComponents() },
				col = {
					math.floor(item.Color.R * 255 + 0.5),
					math.floor(item.Color.G * 255 + 0.5),
					math.floor(item.Color.B * 255 + 0.5),
				},
				m = item.Material.Name,
				t = r(item.Transparency),
				sh = item.CastShadow,
			}
			if item:IsA("Part") then
				entry.shape = item.Shape.Name
			end
			local pieces = item:GetAttribute("PP_Pieces")
			if pieces then
				entry.pieces = HttpService:JSONDecode(pieces)
			end
			local node = item.Parent
			while node and node ~= workspace do
				if node:IsA("Model") and node:GetAttribute("PP_Prop") then
					entry.prop = node:GetAttribute("PP_Prop")
					break
				end
				node = node.Parent
			end
			table.insert(parts, entry)
		end
	end
	return parts
end

-- The round -----------------------------------------------------------------------------------------

local function __round(value)
	if type(value) == "number" then
		return math.floor(value * 100 + 0.5) / 100
	end
	return value
end

-- Rewards ---------------------------------------------------------------------------------------

-- Profiles for the stand-in players, loaded the way DataService loads a saved one (no DataStore):
-- Bot1 is a new player a few XP from level 2 (the Rewards Road's first reward), Bot2 a saved
-- profile still on the old, high coin scale 10 XP short of level 10, Bot3 one round short of the
-- Party Animal milestone; the rest are new players.
local function __seedProfiles()
	local DataService = __require("Server/Services/DataService")
	local CosmeticService = __require("Server/Services/CosmeticService")
	local QuestService = __require("Server/Services/QuestService")
	local LevelCurve = __require("Shared/Logic/LevelCurve")
	local seeds = {
		{ EconomyVersion = 2, Coins = 4, XP = 95 },
		{ Version = 1, Coins = 1234, XP = LevelCurve.TotalXPForLevel(10) - 10, Stats = { Wins = 7 } },
		{ EconomyVersion = 2, Coins = 10, XP = 500, Stats = { RoundsPlayed = 49, Wins = 9 } },
	}
	local before = {}
	for index, player in __fakePlayers do
		local data, migration = DataService.Migrate(seeds[index] or { EconomyVersion = 2 })
		DataService.All()[player] = {
			Player = player,
			Key = "Harness_" .. index,
			Data = data,
			CanSave = false,
			IsVip = false,
			Released = false,
			Migration = migration,
		}
		-- What ProfileLoaded does: free items and what the level has earned, quests for today.
		CosmeticService.CheckUnlocks(player, true)
		QuestService.Refresh(player)
		DataService.Changed(player)
		local owned = {}
		for itemId in data.Owned do
			owned[itemId] = true
		end
		before[player] = {
			coins = data.Coins,
			xp = data.XP,
			level = LevelCurve.FromTotalXP(data.XP),
			owned = owned,
			migrated = if migration and migration.CoinsBefore
				then `{migration.CoinsBefore} -> {migration.CoinsAfter}`
				else nil,
		}
	end
	return before
end

-- Grants the round's rewards as RoundManager does, and reports what each stand-in got.
local function __grantRewards(definition, results, before)
	local DataService = __require("Server/Services/DataService")
	local LevelCurve = __require("Shared/Logic/LevelCurve")
	local Placement = __require("Shared/Logic/Placement")
	local RewardService = __require("Server/Services/RewardService")
	local entries = {}
	for _, entry in results.Entries do
		if entry.Player.Parent then
			entry.Key = entry.Player
			table.insert(entries, entry)
		end
	end
	local placed = Placement.Assign(entries)
	local ok, err = pcall(RewardService.GrantRound, definition, placed, results.WinningTeam)
	local report = { granted = if ok then "ok" else tostring(err), players = {} }
	local places = {}
	for _, item in placed do
		places[item.Entry.Player] = item.Place
	end
	for player, was in before do
		local profile = DataService.Get(player)
		if not profile then
			continue
		end
		local data = profile.Data
		local unlocked = {}
		for itemId in data.Owned do
			if not was.owned[itemId] then
				table.insert(unlocked, itemId)
			end
		end
		table.sort(unlocked)
		local quests = {}
		for _, period in { "Daily", "Weekly" } do
			for _, quest in data.Quests[period].Active do
				table.insert(quests, `{quest.Id} {quest.Progress}{if quest.Done then " done" else ""}`)
			end
		end
		report.players[player.Name] = {
			place = places[player],
			coins = `{was.coins} -> {data.Coins}`,
			xp = `{was.xp} -> {data.XP}`,
			level = `{was.level} -> {LevelCurve.FromTotalXP(data.XP)}`,
			migrated = was.migrated,
			unlocked = unlocked,
			stats = `rounds {data.Stats.RoundsPlayed}, wins {data.Stats.Wins}, podiums {data.Stats.Podiums}, race podiums {data.Stats.RacePodiums}, team wins {data.Stats.TeamWins}, games {data.Stats.GamesTried}, days {data.Stats.DaysPlayed}`,
			firstWinDay = data.Daily.FirstWinDay,
			quests = table.concat(quests, ", "),
		}
	end
	return report
end

-- round_harness.py --drop-at T: T seconds into the rules card the last stand-in drops straight
-- through its floor to under KillY, as on a device that hadn't loaded the floor yet (owner: "Friend
-- fell through the floor while loading into pump and pop."). Before GO that isn't a fall: the round
-- puts the same character straight back on its spot (RoundContext._putBack), alive and still in.
-- The report says where it is a moment later, just before GO and after.
local function __dropThrough(ctx, player, at, summary, prepStart, prepDeadline)
	task.delay(math.max(0, prepStart + at - os.clock()), function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not root then
			summary.drop = "no character to drop"
			return
		end
		local spot = root.Position
		local report = { who = player.Name, at = at, checks = {} }
		summary.drop = report
		character:PivotTo(character:GetPivot() - Vector3.new(0, spot.Y - ctx.KillY + 20, 0))
		report.droppedTo = `{__round(ctx.KillY - root.Position.Y)} under KillY`
		local function check(label)
			local _, _, rootNow = ctx:GetCharacter(player)
			table.insert(report.checks, {
				label = label,
				alive = ctx:IsAlive(player),
				sameCharacter = player.Character == character,
				fromSpot = if rootNow then __round((rootNow.Position - spot).Magnitude) else "no character",
			})
		end
		task.wait(0.5)
		check("0.5s later")
		task.wait(math.max(0, prepDeadline - 0.3 - os.clock()))
		check("just before GO")
		while not ctx.Started and ctx.Active do
			task.wait(0.05)
		end
		task.wait(1)
		check("1s after GO")
		report.putBacks = __require("Server/Services/Telemetry").Counters.PutBack or 0
	end)
end

-- What happens to the stand-ins during the rules card (round_harness.py --leave-at / --reset-at /
-- --drop-at): every one of them leaves `leaveAt` seconds in (only real bots stay), or the last one's
-- character dies `resetAt` seconds in, like a reset from the Roblox menu, or drops through its floor
-- `dropAt` seconds in (__dropThrough); the report says where it is at GO and after (it should be
-- back on its spot, or where a respawn mode's Respawn hook puts it, and still in).
function __prepEvents(ctx, roundPlayers, watch, summary, leave, prepStart, prepDeadline)
	if watch.leaveAt then
		task.delay(math.max(0, prepStart + watch.leaveAt - os.clock()), function()
			for _, player in roundPlayers do
				leave(player)
			end
			summary.peopleLeftAt = watch.leaveAt
		end)
	end
	local player = roundPlayers[#roundPlayers]
	if watch.dropAt and player then
		__dropThrough(ctx, player, watch.dropAt, summary, prepStart, prepDeadline)
	end
	if not watch.resetAt or not player then
		return
	end
	task.delay(math.max(0, prepStart + watch.resetAt - os.clock()), function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root then
			summary.reset = "no character to reset"
			return
		end
		local spot = root.Position
		local report = { who = player.Name, at = watch.resetAt, died = false, checks = {} }
		summary.reset = report
		humanoid.Died:Connect(function()
			report.died = report.died or "fired"
		end)
		humanoid.Health = 0
		-- Without physics a humanoid may never notice: then ask it to die the other way.
		task.wait(0.2)
		if not report.died then
			pcall(humanoid.ChangeState, humanoid, Enum.HumanoidStateType.Dead)
			task.wait(0.2)
			report.died = if report.died then "fired after ChangeState(Dead)" else "never fired"
		end
		-- Roblox gives a dead player a new character Players.RespawnTime seconds later, unless they
		-- got one before that; stand-ins aren't real players, so the harness does it.
		report.respawnTime = RealPlayers.RespawnTime
		task.delay(math.max(0, RealPlayers.RespawnTime - 0.4), function()
			if player.Parent and player.Character == character then
				report.autoRespawn = __round(os.clock() - prepStart)
				player:LoadCharacterAsync()
			end
		end)
		local function check(label)
			local _, humanoidNow, rootNow = ctx:GetCharacter(player)
			table.insert(report.checks, {
				label = label,
				alive = ctx:IsAlive(player),
				newCharacter = player.Character ~= character,
				fromSpot = if rootNow then __round((rootNow.Position - spot).Magnitude) else "no character",
				walkSpeed = if humanoidNow then humanoidNow.WalkSpeed else nil,
			})
		end
		task.wait(math.max(0, prepDeadline - 0.3 - os.clock()))
		check("just before GO")
		while not ctx.Started and ctx.Active do
			task.wait(0.05)
		end
		local go = os.clock()
		for _, after in { 0.5, 3 } do
			task.wait(math.max(0, go + after - os.clock()))
			check(`{after}s after GO`)
		end
	end)
end

-- The stand-in client's ArrivalController (owner: "Friend fell through the floor while loading into
-- pump and pop."): every hold of the stand-in's character goes in summary.clientHolds (from and to,
-- in seconds since the rules card came up, and how far from the spot the round gave it: 0 is on it,
-- "not placed yet" is before, at its start in the empty test world). Placed on a floor that's there,
-- it's never held. With round_harness.py --late-floor T its ground probe finds nothing for the first
-- T seconds, like a phone still loading the arena: it must be held on its spot until then, and let go
-- then. Returns a function that stops watching.
function __watchHolds(ctx, summary, prepStart, lateFloor)
	local ok, arrival = pcall(__require, "Client/Controllers/ArrivalController")
	if not ok then
		summary.clientHolds = "no ArrivalController: " .. tostring(arrival)
		return nil
	end
	if lateFloor then
		local probe = arrival.GroundUnder
		local floorAt = prepStart + lateFloor
		arrival.GroundUnder = function(...)
			if os.clock() < floorAt then
				return false -- this device hasn't got the arena yet
			end
			return probe(...)
		end
		summary.lateFloor = lateFloor
	end
	local RunService = game:GetService("RunService")
	local holds = {}
	summary.clientHolds = holds
	local open, at = nil, nil
	local function close()
		if open then
			open.to = __round(os.clock() - prepStart)
			table.insert(holds, open)
			open, at = nil, nil
		end
	end
	local watching = RunService.Heartbeat:Connect(function()
		local heldAt = arrival.HeldAt()
		if at and (not heldAt or (heldAt - at).Magnitude > 1) then
			close()
		end
		if heldAt and not open then
			-- Where it's held, against where the round put it (its spot, root 3 studs up).
			local spot = ctx._spots[__localPlayer]
			open = {
				from = __round(os.clock() - prepStart),
				offSpot = if spot
					then __round((heldAt - (spot.CFrame.Position + Vector3.yAxis * 3)).Magnitude)
					else "not placed yet",
			}
			at = heldAt
		end
	end)
	return function()
		watching:Disconnect()
		close()
	end
end

-- The stand-in client's rules card (round_harness.py --client --ui-at rules,closed): "rules" is a
-- snapshot of the screen once the card has popped up, "closed" one just after the player closed it
-- with its ✕ (RoundController.CloseRules). summary.rulesCard says what was up each time (the card,
-- PP_RulesShowing, the mode's HUD), whether the card came back before GO, and what the 3-2-1 showed.
function __rulesShots(uiAt, clientGuis, summary, prepDeadline)
	local wanted = {}
	for _, at in uiAt or {} do
		wanted[at] = true
	end
	if not clientGuis or not (wanted.rules or wanted.closed) then
		return
	end
	local countdownAt = prepDeadline - __require("Shared/Config").Session.CountdownTime
	task.spawn(function()
		local report = {}
		summary.rulesCard = report
		while __localPlayer:GetAttribute("PP_RulesShowing") ~= true and os.clock() < countdownAt do
			task.wait(0.05)
		end
		local hud = clientGuis:FindFirstChild("PartyPanicHUD")
		local card = hud and hud:FindFirstChild("Rules")
		local function look()
			local modeHud = "none"
			for _, gui in clientGuis:GetChildren() do
				if gui:IsA("ScreenGui") and string.sub(gui.Name, 1, 9) == "MiniGame_" then
					modeHud = if gui.Enabled then "shown" else "waiting"
				end
			end
			return {
				card = if card then (if card.Visible then "up" else "down") else "missing",
				showing = __localPlayer:GetAttribute("PP_RulesShowing") == true,
				modeHud = modeHud,
				left = __round(countdownAt - os.clock()), -- seconds to the 3-2-1
			}
		end
		task.wait(1.5) -- it pops in
		report.up = look()
		summary.ui = summary.ui or {}
		if wanted.rules then
			summary.ui.rules = __dumpGui(clientGuis, "rules")
		end
		if not wanted.closed or os.clock() > countdownAt - 1 then
			return
		end
		__require("Client/Controllers/RoundController").CloseRules()
		task.wait(0.5)
		report.closed = look()
		summary.ui.closed = __dumpGui(clientGuis, "closed")
		-- It stays closed, and the 3-2-1 and GO come at their times.
		local countdown = hud and hud:FindFirstChild("Countdown")
		local seen, cameBack = {}, false
		while os.clock() < prepDeadline + 1.5 do
			cameBack = cameBack or (card ~= nil and card.Visible)
			if countdown and countdown.Visible and seen[#seen] ~= countdown.Text then
				table.insert(seen, countdown.Text)
			end
			task.wait(0.03)
		end
		report.cameBack = cameBack
		report.countdown = table.concat(seen, " ")
	end)
end

-- `watch` (round_harness.py --client-sits-out / --client-out-at): the stand-in client sits the round
-- out ({ sitOut = true }), or is knocked out `outAt` seconds in.
-- `colliders` (round_harness.py --colliders-at, tools/checks/colliders.luau): snapshots of every part
-- characters collide with, { times = { seconds into the round, 0 = after Prepare } }.
function __runRound(id, playerCount, seconds, botFactory, clientMode, dumpAt, uiAt, botCount, watch, colliders)
	local GameDefinitions = __require("Shared/GameDefinitions")
	local GameState = __require("Shared/GameState")
	local Config = __require("Shared/Config")
	GameState.Folder()
	local RoundContext = __require("Server/Services/RoundContext")
	__require("Server/World/Shapes").RecordPieces = true
	if __noCsg then
		__require("Server/World/Shapes").PauseCsgForTests(1e6) -- as if CSG failed on this server
	end
	if colliders then
		__buildEnvironment() -- the terrain round the arenas, as on a real server (colliders.luau)
	end
	local module = __require("Server/MiniGames/" .. id)
	local definition = GameDefinitions.Get(id)
	assert(definition, "no definition for " .. id)
	local function setPhase(phase, duration)
		GameState.Set("Phase", phase)
		GameState.Set("PhaseEndsAt", if duration then workspace:GetServerTimeNow() + duration else 0)
	end

	for index = 1, playerCount do
		table.insert(__fakePlayers, __newPlayer(index))
	end
	local summary = { id = id, players = playerCount }

	-- The stand-in client: Bot1 runs the HUD bits and the mode's client half, like a real player.
	local clientGuis = nil
	if clientMode then
		__localPlayer = __fakePlayers[1]
		rawset(__playersShim, "LocalPlayer", __localPlayer)
		local State = __require("Client/State")
		local okState, stateErr = pcall(State.Init)
		if not okState then
			__note("client State.Init failed: " .. tostring(stateErr))
		end
		local context = {}
		for key, guiName in { Hud = "PartyPanicHUD", Overlay = "PartyPanicOverlay" } do
			local gui = Instance.new("ScreenGui")
			gui.Name = guiName
			gui.Parent = __localPlayer.PlayerGui
			context[key] = gui
		end
		for _, name in
			{
				"NotificationController",
				"EffectsController",
				"HudController",
				"RoundController",
				"ResultsController",
				"RewardsController",
				"CelebrationController",
				"MiniGameController",
				"ArrivalController",
			}
		do
			local okLoad, controller = pcall(__require, "Client/Controllers/" .. name)
			if not okLoad then
				__note(`client {name} failed to load: {controller}`)
				continue
			end
			-- No physics here, so PreSimulation and PostSimulation never fire: ArrivalController steps on
			-- Heartbeat instead, its "after the physics step" deferred to the end of the frame. (Only for
			-- it, while it starts: the modes' own pose loops stay as they always ran here.)
			local physicsShim = name == "ArrivalController"
			if physicsShim then
				rawset(__clientShims.RunService, "PreSimulation", __realRun.Heartbeat)
				rawset(__clientShims.RunService, "PostSimulation", {
					Connect = function(_, fn)
						return __realRun.Heartbeat:Connect(function(...)
							task.defer(fn, ...)
						end)
					end,
				})
			end
			task.spawn(function()
				local okStart, err = pcall(controller.Start, context)
				if not okStart then
					__note(`client {name} failed to start: {err}`)
				end
			end)
			if physicsShim then
				rawset(__clientShims.RunService, "PreSimulation", nil)
				rawset(__clientShims.RunService, "PostSimulation", nil)
			end
		end
		clientGuis = __localPlayer.PlayerGui
		__uiScaleFor = __require("Client/UI/UIKit").ScaleFor -- gui_dump.luau: the scale per screen
	end

	-- The stand-ins' profiles, so the round can grant rewards like a real one (__seedProfiles).
	local okSeed, seeded = pcall(__seedProfiles)
	if not okSeed then
		__note("seeding profiles failed: " .. tostring(seeded))
		seeded = nil
	end

	-- Real bots (Services/BotService) driven by the mode's brain, alongside the scripted stand-ins.
	local bots = {}
	local BotService = nil
	if botCount and botCount > 0 then
		BotService = __require("Server/Services/BotService")
		BotService.Setup()
		for _ = 1, botCount do
			table.insert(bots, BotService.Add())
		end
		task.wait(0.8)
	end
	summary.bots = #bots

	GameState.Set("RoundId", 1)
	GameState.Set("GameId", id)
	-- A stand-in client sitting out is on the server but not in the round (Services/SitOutService).
	local watcher = if clientMode and watch and watch.sitOut then __localPlayer else nil
	local roundPlayers = table.clone(__fakePlayers)
	if watcher then
		table.remove(roundPlayers, table.find(roundPlayers, watcher))
		watcher:SetAttribute("PP_SitOut", true)
		summary.clientSitsOut = true
	end
	local participants = table.clone(roundPlayers)
	for _, bot in bots do
		table.insert(participants, bot)
	end
	if watch and watch.spawnFails then
		-- No character, and none to be had: SpawnPlayer gives up on every stand-in.
		for _, player in roundPlayers do
			if player.Character then
				player.Character:Destroy()
			end
			player.Character = nil
			player.LoadCharacterAsync = function() end
		end
		summary.spawnFails = #roundPlayers
	end
	local ctx = RoundContext.new(1, definition, participants)
	local miniGame = module.new(ctx)
	local prepTime = Config.Session.RulesTime + Config.Session.CountdownTime
	local prepDeadline = os.clock() + prepTime
	setPhase("Preparing", prepTime)
	__rulesShots(uiAt, clientGuis, summary, prepDeadline)

	local function leave(player)
		local index = table.find(__fakePlayers, player)
		if index then
			table.remove(__fakePlayers, index)
		end
		player.Parent = nil
		__playerRemoving:Fire(player)
		-- The signal above already tells the round (RoundContext._onLeave ignores a second call);
		-- calling it directly too keeps leaves working if the stand-in signal ever changes.
		if type(player) == "table" then
			ctx:_onLeave(player)
		end
	end

	local t0 = os.clock()
	local stopWatchingHolds = if clientMode and not watcher
		then __watchHolds(ctx, summary, t0, watch and watch.lateFloor)
		else nil
	local okPrepare, prepareErr = pcall(miniGame.Prepare, miniGame)
	summary.prepare = if okPrepare then "ok" else tostring(prepareErr)
	summary.prepareSeconds = __round(os.clock() - t0)
	summary.arenaParts = #ctx.Arena:GetDescendants()
	if okPrepare and watch then
		__prepEvents(ctx, roundPlayers, watch, summary, leave, t0, prepDeadline)
	end
	-- The rules card, as RoundManager waits it out: called off once no person is left in the round.
	local starting = okPrepare
	if okPrepare and ctx.WaitForStart then
		starting = ctx:WaitForStart(prepDeadline)
	elseif okPrepare then -- an older RoundContext (a run of a branch from before it)
		while os.clock() < prepDeadline do
			task.wait(0.1)
		end
	end
	if okPrepare and not starting then
		summary.calledOff = __round(os.clock() - t0)
	end
	local colliderTimes = if colliders then table.clone(colliders.times) else {}
	if colliders then
		summary.rebuildWait, summary.rebuildsLeft, summary.rebuildHitch = __waitForRebuilds(150)
		summary.rebuildSlowest = __slowestRebuilds(5)
	end
	local function snapColliders(label)
		local okSnap, snapshot = pcall(
			__colliderSnapshot,
			label,
			{ center = ctx.Origin.Position, reach = colliders.reach, killY = ctx.KillY }
		)
		summary.colliders = summary.colliders or {}
		table.insert(summary.colliders, if okSnap then snapshot else { label = label, failed = tostring(snapshot) })
	end
	if colliders and colliderTimes[1] == 0 then
		table.remove(colliderTimes, 1)
		snapColliders("prepare")
	end

	local env = {
		ctx = ctx,
		game = miniGame,
		players = table.clone(roundPlayers),
		rng = Random.new(7),
		note = __note,
		client = clientMode and not watcher, -- players[1] is driven by the client half
		localPlayer = __localPlayer,
	}
	function env.Action(player, name, ...)
		__remoteObjects.MiniGameAction.__bindable:Fire(__playerKey(player), name, ...)
	end
	function env.Root(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		return root and root.Position
	end
	function env.Move(player, position, lookAt)
		local character = player.Character
		if character then
			if lookAt then
				character:PivotTo(CFrame.lookAt(position, Vector3.new(lookAt.X, position.Y, lookAt.Z)))
			else
				character:PivotTo(CFrame.new(position))
			end
		end
	end
	function env.Shared(key)
		return GameState.Get("MG_" .. key)
	end
	function env.SharedJSON(key)
		return GameState.GetJSON("MG_" .. key)
	end
	function env.Mine(player, key)
		return player:GetAttribute("MG_" .. key)
	end
	function env.Alive(player)
		return ctx:IsAlive(player)
	end
	env.Leave = leave

	local tick = if starting then botFactory(env) else nil
	if starting then
		ctx:Begin()
		setPhase("InRound", definition.Duration)
		local okStart, startErr = pcall(miniGame.Start, miniGame)
		summary.start = if okStart then "ok" else tostring(startErr)
		if #bots > 0 then
			local okBrain, brain = pcall(__require, "Server/MiniGames/Bots/" .. id)
			if not okBrain then
				brain = __require("Server/MiniGames/Bots/Default")
				summary.brain = "Default"
			else
				summary.brain = id
			end
			ctx:RunBots(brain, miniGame)
		end
		local limit = if seconds > 0 then math.min(seconds, definition.Duration) else definition.Duration
		local begin = os.clock()
		local last = begin
		while not ctx.EndReason do
			local now = os.clock()
			if now - begin >= limit then
				local reason = if now - begin >= definition.Duration then "TimeUp" else "HarnessStop"
				if ctx.TimeRanOut then
					ctx:TimeRanOut(reason) -- as RoundManager: a moment for anything in flight (HoldEnd)
				else
					ctx:End(reason)
				end
				if ctx.EndReason then
					break
				end
			end
			if watch and watch.outAt and clientMode and not watcher and not summary.clientOutAt then
				if now - begin >= watch.outAt then
					summary.clientOutAt = __round(now - begin)
					ctx:Eliminate(__localPlayer, "harness")
				end
			end
			if uiAt and clientGuis then
				summary.ui = summary.ui or {}
				for _, at in uiAt do
					local key = tostring(at)
					if type(at) == "number" and not summary.ui[key] and now - begin >= at then
						summary.ui[key] = __dumpGui(clientGuis)
					end
				end
			end
			if colliderTimes[1] and now - begin >= colliderTimes[1] then
				snapColliders(string.format("t%.0f", table.remove(colliderTimes, 1)))
			end
			if dumpAt and not summary.dump and now - begin >= dumpAt then
				local roots = { ctx.Arena }
				local clientWorld = workspace:FindFirstChild("MiniGameClient")
				if clientWorld then
					table.insert(roots, clientWorld)
				end
				for _, player in __fakePlayers do
					if player.Character then
						table.insert(roots, player.Character)
					end
				end
				summary.dump = {
					parts = __dumpParts(roots),
					terrain = { half = 0, step = 4, heights = {}, mats = {}, water = {}, materials = {}, colors = {} },
					lighting = { sun = { 0.4, 0.75, 0.3 }, brightness = 2.4 },
					ok = true,
					logs = {},
				}
			end
			if tick then
				local okTick, tickErr = pcall(tick, now - begin, now - last)
				if not okTick then
					__note("bot error: " .. tostring(tickErr))
					tick = nil
				end
			end
			last = now
			task.wait(0.05)
		end
		summary.endReason = ctx.EndReason
		if ctx.TimeUpAt then
			summary.endHeld = __round(ctx:Now() - ctx.TimeUpAt) -- seconds the end waited at time-up
		end
		summary.roundSeconds = __round(os.clock() - begin)
		local okStop, stopErr = pcall(miniGame.Stop, miniGame, ctx.EndReason)
		summary.stop = if okStop then "ok" else tostring(stopErr)
		local okResults, results = pcall(miniGame.GetResults, miniGame)
		if okResults and results then
			local rows = {}
			for _, entry in results.Entries do
				table.insert(rows, {
					player = entry.Player.Name,
					rank = __round(entry.Rank),
					text = entry.ScoreText,
					team = entry.Team,
				})
			end
			table.sort(rows, function(a, b)
				return a.rank > b.rank
			end)
			summary.results = rows
			summary.winningTeam = results.WinningTeam
			if seeded then
				local okGrant, report = pcall(__grantRewards, definition, results, seeded)
				summary.rewards = if okGrant then report else tostring(report)
			end
		else
			summary.results = tostring(results)
		end
	end
	setPhase("Results", 2)
	if clientGuis then
		task.wait(1)
		summary.clientGuiDuringResults = #clientGuis:GetDescendants()
	end
	setPhase("Cleanup")
	if clientGuis then
		-- Back in the lobby, the stand-in client celebrates what the round's rewards unlocked.
		task.wait(1.2)
		local celebrate = clientGuis:FindFirstChild("PartyPanicCelebrate")
		local shown = celebrate and celebrate:FindFirstChild("Celebration")
		local texts = {}
		for _, item in if shown then shown:GetDescendants() else {} do
			if item:IsA("TextLabel") or item:IsA("TextButton") then
				if item.Text ~= "" and item.Visible then
					table.insert(texts, item.Text)
				end
			end
		end
		summary.clientCelebration = if shown then table.concat(texts, " | ") else "none"
		local chip = clientGuis:FindFirstChild("ProfileChip", true)
		local tab = chip and chip:FindFirstChild("NextReward")
		local tabLabel = tab and tab:FindFirstChildWhichIsA("TextLabel", true)
		summary.clientNextReward = if tabLabel then tabLabel.Text else "none"
	end
	local okCleanup, cleanupErr = pcall(miniGame.Cleanup, miniGame)
	summary.cleanup = if okCleanup then "ok" else tostring(cleanupErr)
	local okDestroy, destroyErr = pcall(ctx.Destroy, ctx)
	summary.destroy = if okDestroy then "ok" else tostring(destroyErr)
	task.wait(0.2)
	-- Everyone who played should be back in the lobby (new characters start within a few dozen
	-- studs of its centre), not left wherever the arena was.
	local notHome = {}
	for _ = 1, 40 do -- respawning a character takes a moment
		notHome = {}
		for _, player in participants do
			local character = player.Parent and player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				local flat = Vector3.new(root.Position.X, 0, root.Position.Z).Magnitude
				if flat > 80 or root.Position.Y > 40 then
					table.insert(
						notHome,
						`{player.Name} at {math.round(flat)} studs out, y {math.round(root.Position.Y)}`
					)
				end
			end
		end
		if #notHome == 0 then
			break
		end
		task.wait(0.1)
	end
	summary.notHomeAfterCleanup = notHome
	summary.arenaLeftovers = if ctx.Arena.Parent then #ctx.Arena:GetDescendants() else 0
	if colliders then
		summary.colliderLeftovers = __colliderLeftovers()
	end
	if clientGuis then
		local modeGuis = {}
		for _, gui in clientGuis:GetChildren() do
			if string.sub(gui.Name, 1, 9) == "MiniGame_" then
				table.insert(modeGuis, gui.Name)
			end
		end
		summary.clientModeGuisAfterCleanup = modeGuis
	end
	local leftoverShared = {}
	for key in GameState.Folder():GetAttributes() do
		if string.sub(key, 1, 3) == "MG_" then
			table.insert(leftoverShared, key)
		end
	end
	summary.sharedLeftovers = leftoverShared
	if BotService then
		for _, bot in bots do
			BotService.Remove(bot)
		end
	end
	if stopWatchingHolds then
		stopWatchingHolds()
	end
	summary.errors = __errors
	summary.textReport = if summary.ui then __textReport else nil
	summary.uiDefaults = if summary.ui then __uiDefaults else nil -- what gui_dump.luau left out of them
	summary.log = __log
	summary.eventCounts = __eventCounts
	summary.events = __events
	return HttpService:JSONEncode(summary)
end

-- Sitting out (Services/SitOutService), with stand-in people who have profiles: the switch's
-- request through the remote (validated and rate limited), the notifications, votes, the lineup
-- RoundManager plays (people sitting out aren't in it; everyone on a break pauses rounds) and how
-- many bots BotService wants. Runs during __runLobby, with its bots in the world.
function __checkSitOut(VotingService, BotService)
	local SitOutService = __require("Server/Services/SitOutService")
	local DataService = __require("Server/Services/DataService")
	local Notifier = __require("Server/Services/Notifier")
	local Telemetry = __require("Server/Services/Telemetry")
	local GameState = __require("Shared/GameState")
	local Roster = __require("Shared/Logic/Roster")
	local TableUtil = __require("Shared/Logic/TableUtil")
	-- Stand-ins aren't real Players: keep their notifications here (Notifier only sends to real
	-- ones) and leave them out of AnalyticsService.
	local told = {}
	local realSend, realEvent = Notifier.Send, Telemetry.PlayerEvent
	Notifier.Send = function(player, text, kind)
		table.insert(told, `{player.Name}: {text} ({kind or "info"})`)
	end
	Telemetry.PlayerEvent = function() end
	local result = {}
	local ok, err = pcall(function()
		SitOutService.Init()
		VotingService.Init()
		local people = {}
		for index, name in { "Ann", "Bo", "Cy", "Di" } do
			local person = __newPlayer(index)
			person.Name, person.DisplayName = name, name
			table.insert(__fakePlayers, person)
			DataService.All()[person] = {
				Player = person,
				Key = "",
				Data = TableUtil.DeepCopy(DataService.Template),
				CanSave = false,
				IsVip = false,
				Released = false,
			}
			people[name] = person
		end
		local function ask(person, value)
			__remoteObjects.SetSitOut.__bindable:Fire(__playerKey(person), value)
			task.wait(0.05)
		end
		local function lineup()
			local current = SitOutService.Lineup()
			local names, bots = {}, 0
			for _, who in current.Participants do
				if who.IsBot then
					bots += 1
				else
					table.insert(names, who.Name)
				end
			end
			local reason, needed = Roster.Blocker(current, 2)
			return {
				people = table.concat(names, ","),
				bots = bots,
				blocker = reason,
				banner = if reason ~= "" then Roster.WaitingMessage(reason, needed) else "",
				botsWanted = BotService.Desired(),
			}
		end
		local ann, bo, cy, di = people.Ann, people.Bo, people.Cy, people.Di
		-- Di isn't in these: she's here for the rate limit below.
		local function lineupWithoutDi()
			local index = table.find(__fakePlayers, di)
			table.remove(__fakePlayers, index)
			local current = lineup()
			table.insert(__fakePlayers, di)
			return current
		end
		result.allPlaying = lineupWithoutDi()

		GameState.Set("Phase", "Voting")
		VotingService.Begin({
			{ Id = "FireRope", Mystery = false },
			{ Id = "HexMeltdown", Mystery = false },
			{ Id = "HoneyTrap", Mystery = false },
			{ Id = "PumpAndPop", Mystery = true },
		})
		result.annVotes = VotingService.Cast(ann, 2)
		ask(ann, true)
		result.annSitsOut = {
			attribute = ann:GetAttribute("PP_SitOut"),
			voteAttribute = ann:GetAttribute("PP_Vote"),
			counts = GameState.GetJSON("VoteCounts"),
			voteAgainRefused = not VotingService.Cast(ann, 3),
		}
		result.annOut = lineupWithoutDi()
		ask(bo, "yes please")
		result.junkIgnored = bo:GetAttribute("PP_SitOut") == nil
		ask(bo, true)
		ask(cy, true)
		result.everyoneOut = lineupWithoutDi()
		ask(ann, false)
		result.annBack = { votes = VotingService.Cast(ann, 1), lineup = lineupWithoutDi() }
		VotingService.End()

		-- Sitting out mid-round: they finish it (the round's own list), and miss the next one.
		GameState.Set("Phase", "InRound")
		ann:SetAttribute("PP_InRound", true)
		ann:SetAttribute("PP_Alive", true)
		ask(ann, true)
		ann:SetAttribute("PP_InRound", false)
		ann:SetAttribute("PP_Alive", false)
		result.annOutMidRound = lineupWithoutDi()

		-- Di flips the switch eight times as fast as she can: the server takes four (Config.RateLimits).
		local flips = 0
		di:GetAttributeChangedSignal("PP_SitOut"):Connect(function()
			flips += 1
		end)
		for index = 1, 8 do
			ask(di, index % 2 == 1)
		end
		result.rateLimitedFlips = flips
	end)
	Notifier.Send, Telemetry.PlayerEvent = realSend, realEvent
	result.told = told
	if not ok then
		result.failed = tostring(err)
	end
	return result
end

-- The lobby with bots (round_harness.py LOBBY): builds the lobby, adds bots, and plays the time
-- between rounds three times with Config.Session's times (owner: "Less time sitting in the lobby.
-- total of 20 seconds instead of 40."): a round's results, back to the lobby, then the vote, with
-- two stand-in people who'll play the next round. Bots wander and never vote (people pick games).
-- First both people vote (two games: a tie, broken at random), so the vote ends a beat after the
-- last vote (VotingService.Wait); then Bo doesn't vote (Ann picks Random), so it runs its full time;
-- then Bo sits out instead of voting, which leaves nobody to wait for. "phases" says when each phase
-- started (seconds into the run), "votes" how each vote went (when it closed, what the banner's
-- timer said just after each vote, the winner). Then people sit out (__checkSitOut). The run lasts
-- at least `seconds` (the bots keep wandering).
function __runLobby(botCount, seconds)
	local Config = __require("Shared/Config")
	local GameState = __require("Shared/GameState")
	GameState.Folder()
	local LobbyBuilder = __require("Server/World/LobbyBuilder")
	local VotingService = __require("Server/Services/VotingService")
	local BotService = __require("Server/Services/BotService")
	local BotRegistry = __require("Server/Services/BotRegistry")
	local SitOutService = __require("Server/Services/SitOutService")
	local DataService = __require("Server/Services/DataService")
	local Notifier = __require("Server/Services/Notifier")
	local Telemetry = __require("Server/Services/Telemetry")
	local Roster = __require("Shared/Logic/Roster")
	local TableUtil = __require("Shared/Logic/TableUtil")
	local session = Config.Session
	local summary = {}
	local okLobby, refs = pcall(LobbyBuilder.Build)
	summary.lobby = if okLobby then "ok" else tostring(refs)
	if okLobby then
		-- The vote stage: one portal (with its preview screen) per vote card, and no vote pads.
		local stage = refs.Root:FindFirstChild("VoteStage")
		local portals, padCount = {}, 0
		for _, item in (if stage then stage:GetDescendants() else {}) do
			if item:IsA("BasePart") and item:HasTag("PortalScreen") then
				table.insert(portals, item:GetAttribute("VoteIndex"))
			elseif item:IsA("BasePart") and string.find(item.Name, "VotePad", 1, true) then
				padCount += 1
			end
		end
		table.sort(portals)
		summary.portalScreens = portals
		summary.votePads = padCount
	end
	BotService.Setup()
	local bots = {}
	for _ = 1, botCount do
		table.insert(bots, BotService.Add())
	end
	local function positions()
		local list = {}
		for _, bot in bots do
			local root = bot:Root()
			if root then
				table.insert(
					list,
					{ bot.DisplayName, __round(root.Position.X), __round(root.Position.Y), __round(root.Position.Z) }
				)
			end
		end
		return list
	end
	summary.spawned = positions()
	local stepper = task.spawn(function()
		while true do
			for _, bot in BotRegistry.List() do
				BotService.LobbyStep(bot, os.clock())
			end
			task.wait(0.4)
		end
	end)

	-- The phases as RoundManager sets them, and when each started.
	local t0 = os.clock()
	local phases = {}
	local function setPhase(phase, duration, message)
		GameState.Set("Phase", phase)
		GameState.Set("PhaseEndsAt", if duration then workspace:GetServerTimeNow() + duration else 0)
		GameState.Set("Message", message or "")
		table.insert(phases, { phase = phase, at = __round(os.clock() - t0), planned = duration })
	end

	-- Two people who'll play the next round, with profiles that never save. Stand-ins aren't real
	-- Players: their notifications stay here (Notifier only sends to real ones) and they're left out
	-- of AnalyticsService.
	local told = {}
	local realSend, realEvent = Notifier.Send, Telemetry.PlayerEvent
	Notifier.Send = function(player, text)
		table.insert(told, `{player.Name}: {text}`)
	end
	Telemetry.PlayerEvent = function() end
	local people = {}
	for index, name in { "Ann", "Bo" } do
		local person = __newPlayer(100 + index)
		person.Name, person.DisplayName = name, name
		table.insert(__fakePlayers, person)
		DataService.All()[person] = {
			Player = person,
			Key = "",
			Data = TableUtil.DeepCopy(DataService.Template),
			CanSave = false,
			IsVip = false,
			Released = false,
		}
		table.insert(people, person)
	end
	local ann, bo = people[1], people[2]
	local function everyoneOnBreak() -- RoundManager's abort for the vote
		return (Roster.Blocker(SitOutService.Lineup(), session.MinPlayers)) == "Break"
	end

	-- A round's results, back to the lobby, then the vote; `casts` are { seconds into the vote, who,
	-- the card they tap (or "sitOut") }.
	local votes = {}
	local function betweenRounds(label, casts)
		setPhase("Results", session.ResultsTime, "Results")
		task.wait(session.ResultsTime)
		setPhase("Cleanup", nil, "Back to the lobby!")
		task.wait(0.3)
		setPhase("Intermission", session.IntermissionTime, "Next vote soon!")
		task.wait(session.IntermissionTime)
		summary.afterIntermission = summary.afterIntermission or positions()
		local lineup = SitOutService.Lineup()
		local options = VotingService.BuildOptions(#lineup.Participants, {}, false)
		setPhase("Voting", session.VoteTime, "Vote for the next game!")
		VotingService.Begin(options)
		local opened = os.clock()
		local report = { label = label, options = {}, casts = {}, timerAfter = {}, voters = lineup.Playing }
		for index, option in options do
			report.options[index] = if option.Mystery then `Random ({option.Id})` else option.Id
		end
		for _, cast in casts do
			task.delay(cast[1], function()
				local who, card = cast[2], cast[3]
				local when = __round(os.clock() - opened)
				if card == "sitOut" then
					SitOutService.Set(who, true)
					table.insert(report.casts, `{who.Name} sat out at {when}`)
				else
					local ok = VotingService.Cast(who, card)
					table.insert(report.casts, `{who.Name} tapped {card} at {when}{if ok then "" else " (refused)"}`)
					if BotRegistry.IsBot(who) then
						summary.botVoteRefused = not ok
					end
				end
				task.wait(0.3) -- what everyone's banner says just after
				table.insert(report.timerAfter, __round(GameState.TimeLeft()))
			end)
		end
		report.voted = VotingService.Wait(session.VoteTime, everyoneOnBreak)
		report.closedAfter = __round(os.clock() - opened)
		local winner, counts, tie = VotingService.End()
		report.counts = counts
		report.winner = winner and (if winner.Mystery then `Random: {winner.Id}` else winner.Id)
		report.tie = tie
		table.insert(votes, report)
	end
	betweenRounds("everyone votes", { { 0.5, bots[1], 1 }, { 1, ann, 2 }, { 2, bo, 3 } })
	summary.afterVote = positions()
	betweenRounds("Bo doesn't vote", { { 1, ann, 4 } })
	betweenRounds("Bo sits out", { { 1, ann, 1 }, { 3, bo, "sitOut" } })
	summary.phases = phases
	summary.votes = votes
	-- Ann and Bo leave before the sit-out check (it brings its own people).
	SitOutService.Set(bo, false)
	for _, person in people do
		table.remove(__fakePlayers, table.find(__fakePlayers, person))
		DataService.All()[person] = nil
		person.Parent = nil
		if person.Character then
			person.Character:Destroy()
		end
	end
	Notifier.Send, Telemetry.PlayerEvent = realSend, realEvent
	summary.told = told
	task.wait(math.max(0, seconds - (os.clock() - t0)))

	summary.sitOut = __checkSitOut(VotingService, BotService)
	task.cancel(stepper)
	-- One leaves (as if a player joined), to see the fade-out.
	BotService.Remove(bots[1])
	task.wait(1)
	summary.remaining = #BotRegistry.List()
	for _, bot in BotRegistry.List() do
		BotService.Remove(bot)
	end
	summary.errors = __errors
	summary.log = __log
	summary.eventCounts = __eventCounts
	return game:GetService("HttpService"):JSONEncode(summary)
end
