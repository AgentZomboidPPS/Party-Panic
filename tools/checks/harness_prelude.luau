-- Prelude for tools/checks/round_harness.py: module loader, stand-in players and recording remotes.
-- Everything below runs inside one Open Cloud Luau execution task on a real Roblox server.

local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local RealPlayers = game:GetService("Players")

-- A test run, from the first line: services that keep shared data (the weekly leaderboard, the
-- 👍 / 👎 totals, client reports) must never write the real stores from a test; they check this
-- attribute. (The PLAY AGAIN run starts the real RoundManager, which writes the ratings: it once ran
-- without the flag and wrote to the real PP_GameRatings.)
workspace:SetAttribute("PP_Harness", true)

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
	GetPlayerByUserId = function(_, userId)
		for _, player in __fakePlayers do
			if player.UserId == userId then
				return player
			end
		end
		return nil
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
			keys = data.Keys,
			crates = data.Crates and data.Crates.Count,
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
	-- As RoundManager: the features that hang off rounds (cups, leaderboard, medals...) hear about it.
	__require("Server/Services/RoundEvents").Finished:Fire(definition, placed, results.WinningTeam)
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
			keys = `{was.keys} -> {data.Keys}`, -- (the top 3 win 3 / 2 / 1)
			crates = `{was.crates} -> {data.Crates and data.Crates.Count}`,
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
-- Parties (round_harness.py --party; Services/PartyService): what partied stand-ins are told (stand-ins
-- aren't real Players, so Notifier keeps nothing for them), as "Bot2: 👥 You joined Bot1's party!".
function __watchPartyToasts()
	local Notifier = __require("Server/Services/Notifier")
	local toasts = {}
	local function keep(names, text)
		if
			type(text) == "string"
			and (string.find(text, "👥", 1, true) == 1 or string.find(text, "👑", 1, true) == 1)
		then
			if #toasts < 60 then
				table.insert(toasts, `{names}: {text}`)
			end
		end
	end
	local realSend, realPlayers = Notifier.Send, Notifier.Players
	Notifier.Send = function(player, text, ...)
		keep(player.Name, text)
		return realSend(player, text, ...)
	end
	Notifier.Players = function(list, text, ...)
		local names = {}
		for _, player in list do
			table.insert(names, player.Name)
		end
		keep(table.concat(names, "+"), text)
		return realPlayers(list, text, ...)
	end
	return toasts
end

-- Puts the stand-ins with these numbers in parties as players do: the first invites the others
-- through the Party remote, and each says JOIN. Returns what each one's PP_Party became.
function __formParties(parties)
	local remote = __remoteObjects.Party
	local formed = {}
	for _, numbers in parties do
		local members = {}
		for _, number in numbers do
			table.insert(members, __fakePlayers[number])
		end
		local leader = members[1]
		for index = 2, #members do
			remote.__bindable:Fire(__playerKey(leader), "Invite", members[index].UserId)
			task.wait(0.1)
			remote.__bindable:Fire(__playerKey(members[index]), "Answer", leader.UserId, true)
			task.wait(0.1)
		end
		local row = {}
		for _, member in members do
			table.insert(
				row,
				`{member.Name}={member:GetAttribute("PP_Party") or "-"}:{member:GetAttribute("PP_PartySeat") or "-"}`
			)
		end
		table.insert(formed, table.concat(row, " "))
	end
	return formed
end

-- The team (or role) each party's members were dealt, and whether the party is on one.
function __partyTeams(parties)
	local rows = {}
	for _, numbers in parties do
		local members, teams, together = {}, {}, true
		for _, number in numbers do
			local who = __fakePlayers[number]
			local team = who:GetAttribute("PP_Team") or ""
			table.insert(members, who.Name)
			table.insert(teams, team)
			together = together and team ~= "" and team == teams[1]
		end
		table.insert(
			rows,
			{ members = table.concat(members, ","), teams = table.concat(teams, ","), together = together }
		)
	end
	return rows
end

-- Parties on the stand-in client's device (round_harness.py --party with --client; owner: "Also make
-- the party system insane. I want it to look super epic."): what a party controller shows now.
__partyControllers = {}
-- `name` without "Controller" ("Squad"): tools/checks/bundling.py seeds a run with every quoted
-- "...Controller" in the harness's Luau, and these only come along with --party (__partyClient).
function __partyStatus(name)
	local controller = __partyControllers[name .. "Controller"]
	if not controller or not controller.Status then
		return "not running"
	end
	local ok, status = pcall(controller.Status)
	return if ok then status else tostring(status)
end

-- Each party's look and streak as PartyService publishes them ("7: Turbo Pancakes c1 e5 🔥0").
function __partyLooks()
	local GameState = __require("Shared/GameState")
	local looks = GameState.GetJSON("Parties") or {}
	local rows = {}
	for id, look in looks do
		table.insert(rows, `{id}: {look.Name} c{look.Color} e{look.Emblem} streak {look.Streak}`)
	end
	table.sort(rows)
	return rows
end

-- In the lobby with the party just made (the first stand-in of each leads; Bot1 is this device):
-- the world (a ring and a link to each mate, crests over everyone partied), the squad bar and the
-- PARTY UP! moment; then the PARTY LOOK through the Party remote: the leader rolls a new name, picks
-- a colour and an emblem, asks again too soon, sends junk; a member who doesn't lead tries too.
function __partyLobbyChecks(parties)
	local GameState = __require("Shared/GameState")
	local remote = __remoteObjects.Party
	local result = {}
	GameState.Set("Phase", "Intermission")
	GameState.Set("PhaseEndsAt", workspace:GetServerTimeNow() + 20)
	task.wait(0.4)
	result.partyUp = __partyStatus("Squad")
	task.wait(1.4)
	result.world = __partyStatus("PartyWorld")
	result.squad = __partyStatus("Squad")
	result.looks = __partyLooks()
	local leader = __fakePlayers[parties[1][1]]
	local member = __fakePlayers[parties[1][2]]
	local function ask(who, ...)
		remote.__bindable:Fire(__playerKey(who), ...)
		task.wait(0.05)
	end
	-- (Picks the party doesn't wear yet, so each one is a change.)
	local look = (GameState.GetJSON("Parties") or {})[tostring(leader:GetAttribute("PP_Party"))] or {}
	local color = (look.Color or 1) % 8 + 1
	local emblem = (look.Emblem or 1) % 8 + 1
	ask(leader, "Reroll")
	result.rerolled = __partyLooks()
	task.wait(0.7)
	ask(leader, "Color", color)
	task.wait(0.7)
	ask(leader, "Emblem", emblem)
	result.picked = __partyLooks()
	ask(leader, "Color", color % 8 + 1) -- too soon after the emblem
	task.wait(0.7)
	ask(leader, "Color", 99)
	ask(leader, "Emblem", 0 / 0)
	ask(leader, "Color", 2.5)
	ask(leader, "Name", "Cool Kids")
	ask(member, "Color", 2) -- not the leader
	ask(member, "Reroll")
	result.refused = __partyLooks()
	task.wait(0.6)
	result.squadAfterLook = __partyStatus("Squad")
	result.worldAfterLook = __partyStatus("PartyWorld")
	return result
end

-- Back in the lobby after the round: the streak went up (the whole party played), the rings and
-- crests are back on the new characters; then the second member leaves the party and theirs go.
function __partyAfterChecks(parties)
	local remote = __remoteObjects.Party
	local result = {}
	task.wait(1.2)
	result.looks = __partyLooks()
	result.world = __partyStatus("PartyWorld")
	result.squad = __partyStatus("Squad")
	local member = __fakePlayers[parties[1][2]]
	if member then
		remote.__bindable:Fire(__playerKey(member), "Leave")
		task.wait(1.2)
		result.leftLooks = __partyLooks()
		result.leftWorld = __partyStatus("PartyWorld")
		result.leftSquad = __partyStatus("Squad")
	end
	return result
end

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
		-- Parties on this device (--party): the window, the squad bar and PARTY UP!, the world's rings,
		-- crests, links and outlines (round_harness.py names them in __partyClient).
		for _, entry in __partyClient or {} do
			local okLoad, controller = pcall(entry.Load)
			if not okLoad then
				__note(`client {entry.Name} failed to load: {controller}`)
				continue
			end
			__partyControllers[entry.Name] = controller
			task.spawn(function()
				local okStart, err = pcall(controller.Start, context)
				if not okStart then
					__note(`client {entry.Name} failed to start: {err}`)
				end
			end)
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

	-- A test run: services that keep shared data (the weekly leaderboard's DataStore...) must never
	-- write it from a test; they check this attribute.
	workspace:SetAttribute("PP_Harness", true)
	-- The features that hang off rounds (they hear RoundEvents.Finished from __grantRewards), started
	-- the way the server starts them.
	for _, name in
		{ "CupService", "FriendsService", "PartyService", "MedalService", "LeaderboardService", "EventService" }
	do
		local okLoad, service = pcall(__require, "Server/Services/" .. name)
		if not okLoad or type(service) ~= "table" then
			__note(`{name} failed to load: {service}`)
			continue
		end
		if service.Init then
			local okInit, initErr = pcall(service.Init)
			if not okInit then
				__note(`{name}.Init failed: {initErr}`)
			end
		end
		if service.Start then
			task.spawn(function()
				local okStart, startErr = pcall(service.Start)
				if not okStart then
					__note(`{name}.Start failed: {startErr}`)
				end
			end)
		end
	end

	-- Parties (--party): formed the way players form them, before the round.
	local partyToasts = __watchPartyToasts()
	if watch and watch.parties then
		task.wait(0.2) -- PartyService's Start
		summary.parties = __formParties(watch.parties)
		if clientMode and __partyClient then
			summary.partyLobby = __partyLobbyChecks(watch.parties)
		end
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
	if watch and watch.parties then
		summary.partyTeams = __partyTeams(watch.parties) -- dealt in Prepare
		if clientMode and __partyClient then
			task.wait(1) -- the rules card is up: the SQUAD card comes with it
			summary.partySquad = __partyStatus("Squad")
		end
	end
	-- What a device has to draw, at its peak during the round (phone performance): the arena's parts
	-- (MeshParts among them), particle emitters, lights and surface/billboard GUIs, and the parts the
	-- client half made (workspace.MiniGameClient).
	if okPrepare then
		local perf = {
			arenaBaseParts = 0,
			arenaMeshParts = 0,
			arenaEmitters = 0,
			arenaLights = 0,
			arenaGuis = 0,
			clientParts = 0,
		}
		summary.perf = perf
		task.spawn(function()
			while ctx.Arena and ctx.Arena.Parent and not ctx.EndReason do
				local base, mesh, emitters, lights, guis = 0, 0, 0, 0, 0
				for _, item in ctx.Arena:GetDescendants() do
					if item:IsA("BasePart") then
						base += 1
						if item:IsA("MeshPart") then
							mesh += 1
						end
					elseif item:IsA("ParticleEmitter") then
						emitters += 1
					elseif item:IsA("Light") then
						lights += 1
					elseif item:IsA("SurfaceGui") or item:IsA("BillboardGui") then
						guis += 1
					end
				end
				local client = 0
				local folder = workspace:FindFirstChild("MiniGameClient")
				if folder then
					for _, item in folder:GetDescendants() do
						if item:IsA("BasePart") then
							client += 1
						end
					end
				end
				perf.arenaBaseParts = math.max(perf.arenaBaseParts, base)
				perf.arenaMeshParts = math.max(perf.arenaMeshParts, mesh)
				perf.arenaEmitters = math.max(perf.arenaEmitters, emitters)
				perf.arenaLights = math.max(perf.arenaLights, lights)
				perf.arenaGuis = math.max(perf.arenaGuis, guis)
				perf.clientParts = math.max(perf.clientParts, client)
				task.wait(1)
			end
		end)
	end
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
			if watch and watch.parties and __partyClient and not summary.partyRound and now - begin >= 2 then
				summary.partyRound = __partyStatus("PartyWorld") -- mates' outlines
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
	if watch and watch.parties and clientMode and __partyClient then
		summary.partyAfter = __partyAfterChecks(watch.parties)
	end
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
	summary.partyToasts = if #partyToasts > 0 then partyToasts else nil
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

-- Parties (Services/PartyService; owner: "stuff to work on right now is parties."), with stand-in
-- people sending what their devices would through the Party remote: junk and impossible requests do
-- nothing (wrong types, yourself, a bot, someone not here, a JOIN with no invite waiting), an invite
-- and a JOIN make a party led by the inviter, four at most, the leader leaving hands over, leaving
-- the server takes you out, a NO means not again straight away, a flood of requests is rate limited,
-- an invite's time stops in a round and its card comes back after, joining a new party leaves the
-- old one, and a party of one is over. Each step records everyone's party ("Pia=1:1": party 1, its
-- leader); "sent" is what the server sent each device, "told" their toasts.
function __checkParties()
	local PartyService = __require("Server/Services/PartyService")
	local Notifier = __require("Server/Services/Notifier")
	local GameState = __require("Shared/GameState")
	local BotRegistry = __require("Server/Services/BotRegistry")
	local told, sent = {}, {}
	local realSend = Notifier.Send
	Notifier.Send = function(player, text)
		table.insert(told, `{player.Name}: {text}`)
	end
	local result = {}
	local names = { "Pia", "Quin", "Rex", "Sol", "Tess", "Uma" }
	local people = {}
	local clock = nil
	local ok, err = pcall(function()
		PartyService.Init()
		clock = task.spawn(PartyService.Start)
		local remote = __remoteObjects.Party
		local realFire = remote.FireClient
		remote.FireClient = function(self, player, ...)
			local parts = {}
			for _, value in { ... } do
				table.insert(parts, tostring(if type(value) == "number" then math.round(value * 10) / 10 else value))
			end
			table.insert(sent, `{player.Name} <- {table.concat(parts, " ")}`)
			return realFire(self, player, ...)
		end
		for index, name in names do
			local who = __newPlayer(200 + index)
			who.Name, who.DisplayName = name, name
			table.insert(__fakePlayers, who)
			people[name] = who
		end
		local pia, quin, rex, sol, tess, uma = people.Pia, people.Quin, people.Rex, people.Sol, people.Tess, people.Uma
		local function ask(who, ...)
			remote.__bindable:Fire(__playerKey(who), ...)
			task.wait(0.08)
		end
		local function parties()
			local list = {}
			for _, name in names do
				local who = people[name]
				local id = who:GetAttribute("PP_Party")
				if not who.Parent then
					table.insert(list, `{name} gone`)
				else
					table.insert(list, if id then `{name}={id}:{who:GetAttribute("PP_PartySeat")}` else `{name}=-`)
				end
			end
			return table.concat(list, " ")
		end
		local function invitedCount()
			local count = 0
			for _, line in sent do
				if string.find(line, "<- Invited", 1, true) then
					count += 1
				end
			end
			return count
		end
		GameState.Set("Phase", "Intermission")
		GameState.Set("Replay", "")
		task.wait(0.3)

		-- Junk and impossible requests: no invite goes out, nobody's in a party.
		ask(pia, "Invite", "Quin")
		ask(pia, "Invite", 0 / 0)
		ask(pia, 42, quin.UserId)
		ask(pia, "Invite", pia.UserId)
		local bot = BotRegistry.List()[1]
		result.botAsked = if bot then bot.UserId else "no bot"
		if bot then
			ask(pia, "Invite", bot.UserId)
		end
		ask(pia, "Invite", 987654321)
		ask(quin, "Answer", pia.UserId, true) -- no invite waiting
		result.junk = `{parties()}; invites sent {invitedCount()}`

		-- An invite and a JOIN; the answer must be a yes or a no.
		ask(pia, "Invite", quin.UserId)
		ask(quin, "Answer", pia.UserId, "yes please")
		result.junkAnswer = parties()
		ask(quin, "Answer", pia.UserId, true)
		result.joined = parties()

		-- Four at most: anyone in the party can invite; a fifth is refused.
		ask(pia, "Invite", rex.UserId)
		ask(rex, "Answer", pia.UserId, true)
		ask(quin, "Invite", sol.UserId)
		ask(sol, "Answer", quin.UserId, true)
		local before = invitedCount()
		ask(pia, "Invite", tess.UserId)
		ask(tess, "Answer", pia.UserId, true)
		result.full = `{parties()}; a fifth invited: {invitedCount() > before}`

		-- The leader leaves: the next one in leads.
		ask(pia, "Leave")
		result.leaderLeft = parties()

		-- Sol leaves the server.
		table.remove(__fakePlayers, table.find(__fakePlayers, sol))
		sol.Parent = nil
		__playerRemoving:Fire(sol)
		task.wait(0.2)
		result.solGone = parties()

		-- A NO, then asking again at once: not yet.
		ask(quin, "Invite", tess.UserId)
		ask(tess, "Answer", quin.UserId, false)
		before = invitedCount()
		ask(quin, "Invite", tess.UserId)
		result.afterNo = `{parties()}; asked again at once: {invitedCount() > before}`

		-- Uma floods: 25 invites to Pia as fast as she can. The server takes 10 (5 s window).
		local function toUma()
			local count = 0
			for _, line in sent do
				if string.sub(line, 1, 7) == "Uma <- " then
					count += 1
				end
			end
			return count
		end
		local answeredBefore = toUma()
		for _ = 1, 25 do
			remote.__bindable:Fire(__playerKey(uma), "Invite", pia.UserId)
		end
		task.wait(0.5)
		result.flood = `25 asked, {toUma() - answeredBefore} answered`

		-- Uma's invite waits through a round (its time stops) and comes back after.
		GameState.Set("Phase", "Preparing")
		task.wait(1)
		GameState.Set("Phase", "InRound")
		task.wait(3)
		GameState.Set("Phase", "Results")
		task.wait(1)
		GameState.Set("Phase", "Cleanup")
		task.wait(0.6)
		local lastToPia = nil
		for _, line in sent do
			if string.sub(line, 1, 15) == "Pia <- Invited " then
				lastToPia = line
			end
		end
		result.cardAfterRound = lastToPia

		-- Joining a new party leaves the old one: Rex goes to Tess's; Quin is left alone, so that
		-- party is over.
		ask(tess, "Invite", rex.UserId)
		ask(rex, "Answer", tess.UserId, true)
		result.rexMoved = parties()
	end)
	if clock then
		pcall(task.cancel, clock)
	end
	Notifier.Send = realSend
	for _, who in people do
		local index = table.find(__fakePlayers, who)
		if index then
			table.remove(__fakePlayers, index)
		end
		if who.Character then
			who.Character:Destroy()
		end
	end
	if not ok then
		result.failed = tostring(err)
	end
	result.told = told
	result.sent = sent
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
		task.wait(math.min(session.IntermissionTime, 6)) -- (the whole wait would push a run past Open Cloud's 5 minutes)
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
	summary.partyCheck = __checkParties()
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

-- PLAY AGAIN on the results card (round_harness.py <Mode> --replay; owner: "Add a vote at the end of
-- each minigame to replay the same minigame."): the real RoundManager loop, with the run's mode as the
-- only game (a stand-in mode registry: in a harness the real one finds no modes), two stand-in people
-- (Ann, Bo) and `botCount` real bots. The people vote for the mode, play it, and on the results both
-- say PLAY AGAIN: the same game straight again (no lobby, no vote), while Cy joins during those
-- results (not a voter; he plays the replay, and a bot makes room) and a bot's answer is refused. On
-- the replay's results Ann says yes, Bo and Cy no: no replay, so the lobby and a vote follow, where
-- the picker's recent list and options are recorded (the replayed game is left out). "phases" says
-- when each phase started, "replayVotes" every state of the vote, "rounds" who played each round and
-- on which teams, "toasts" what everyone was told. With `party`, Ann and Bo are in a party first
-- (through Services/PartyService's remote): they should be on one team in the round and in its replay.
function __runReplay(id, botCount, party)
	local GameState = __require("Shared/GameState")
	GameState.Folder()
	local DataService = __require("Server/Services/DataService")
	local CosmeticService = __require("Server/Services/CosmeticService")
	local QuestService = __require("Server/Services/QuestService")
	local BotService = __require("Server/Services/BotService")
	local BotRegistry = __require("Server/Services/BotRegistry")
	local SitOutService = __require("Server/Services/SitOutService")
	local VotingService = __require("Server/Services/VotingService")
	local ReplayService = __require("Server/Services/ReplayService")
	local RatingService = __require("Server/Services/RatingService")
	local FunnelService = __require("Server/Services/FunnelService")
	local Notifier = __require("Server/Services/Notifier")
	local summary = { game = id }
	local t0 = os.clock()
	local function at()
		return __round(os.clock() - t0)
	end

	-- What everyone is told (a round sends too many events for the harness's event log to keep).
	local toasts = {}
	local realAll = Notifier.All
	Notifier.All = function(text, kind, duration)
		table.insert(toasts, `{at()} {kind or "info"}: {text}`)
		return realAll(text, kind, duration)
	end

	-- The game registry RoundManager asks: just this mode and its bot brain.
	local mode = __require("Server/MiniGames/" .. id)
	local okBrain, brain = pcall(__require, "Server/MiniGames/Bots/" .. id)
	if not okBrain then
		brain = __require("Server/MiniGames/Bots/Default")
	end
	__modules["Server/MiniGames"] = function()
		return {
			Get = function(name)
				return if name == id then mode else nil
			end,
			Brain = function()
				return brain
			end,
			Ids = function()
				return { id }
			end,
		}
	end
	__cache["Server/MiniGames"] = nil

	-- People with profiles that never save, loaded as DataService loads one.
	local function person(index, name)
		local who = __newPlayer(index)
		who.Name, who.DisplayName = name, name
		table.insert(__fakePlayers, who)
		local data = DataService.Migrate({ EconomyVersion = 2 })
		DataService.All()[who] = {
			Player = who,
			Key = "Harness_" .. name,
			Data = data,
			CanSave = false,
			Released = false,
		}
		CosmeticService.CheckUnlocks(who, true)
		QuestService.Refresh(who)
		DataService.Changed(who)
		FunnelService.Joined(who, DataService.All()[who]) -- (the analytics funnels: a new player's first load)
		return who
	end
	local ann, bo = person(1, "Ann"), person(2, "Bo")
	-- (The funnels' fields: Ann's screen is a phone, Bo's a PC, and they're Roblox friends.)
	FunnelService.DeviceForTests(ann, "Phone")
	FunnelService.DeviceForTests(bo, "PC")
	pcall(function()
		__require("Server/Services/FriendsService").SetFriendsForTest(ann, bo)
	end)
	if party then
		local PartyService = __require("Server/Services/PartyService")
		PartyService.Init()
		task.spawn(PartyService.Start)
		summary.parties = __formParties({ { 1, 2 } })
	end
	BotService.Setup()
	local bots = {}
	for _ = 1, botCount do
		table.insert(bots, BotService.Add())
	end

	-- The first vote offers this mode on its first card (it's the only game the run has); later votes
	-- are the real picker's. Every vote's recent list (RoundManager's memory) and cards are kept.
	local realBuild = VotingService.BuildOptions
	local builds = {}
	VotingService.BuildOptions = function(count, recent, ignoreLimits)
		local options = realBuild(count, recent, ignoreLimits)
		local shown = {}
		for _, option in options do
			table.insert(shown, if option.Mystery then `Random ({option.Id})` else option.Id)
		end
		table.insert(builds, { recent = table.clone(recent), options = shown })
		if #builds == 1 then
			for index, option in options do
				if option.Id == id and index > 1 then
					option.Id = options[1].Id
				end
			end
			options[1] = { Id = id, Mystery = false }
		end
		return options
	end

	local phases, replayVotes, rounds = {}, {}, {}
	local done = false
	local votes, results = 0, 0
	local function tap(who, again)
		__remoteObjects.ReplayVote.__bindable:Fire(__playerKey(who), again)
	end
	-- 👍 / 👎 on the results card (Services/RatingService), through its remote like a device: what
	-- each tap sent and the player's PP_Rating a moment later.
	local rateTaps = {}
	local function rate(who, choice)
		__remoteObjects.RateGame.__bindable:Fire(__playerKey(who), choice)
		task.wait(0.1)
		table.insert(rateTaps, `{at()} {who.Name} {choice} -> {who:GetAttribute("PP_Rating") or "none"}`)
	end
	local function rateLater(delay, who, choice)
		task.delay(delay, rate, who, choice)
	end
	local function teamsNow()
		local people = {}
		for _, who in __fakePlayers do
			people[who.Name] = who:GetAttribute("PP_Team") or ""
		end
		local botTeams = {}
		for _, bot in BotRegistry.List() do
			if bot:GetAttribute("PP_InRound") then
				local team = bot:GetAttribute("PP_Team") or ""
				botTeams[team] = (botTeams[team] or 0) + 1
			end
		end
		return { people = people, bots = botTeams }
	end
	GameState.Changed("ReplayVote", function()
		local vote = GameState.GetJSON("ReplayVote") or {}
		table.insert(replayVotes, {
			at = at(),
			open = vote.Open,
			capped = vote.Capped,
			yes = vote.Yes,
			no = vote.No,
			voters = if type(vote.Voters) == "table" then #vote.Voters else nil,
			need = vote.Need,
		})
	end)
	-- RoundManager's setPhase sets the phase, then its end time, then the banner's line: each phase
	-- takes the first of each that follows it (a vote ending early moves the end time later on).
	local current = nil
	GameState.Changed("PhaseEndsAt", function()
		if current and current.planned == nil then
			current.planned = __round(GameState.TimeLeft())
		end
	end)
	GameState.Changed("Message", function(message)
		if current and current.message == nil then
			current.message = message
		end
	end)
	GameState.Changed("Phase", function(phase)
		current = { phase = phase, at = at(), game = GameState.Get("GameId"), replay = GameState.Get("Replay") }
		table.insert(phases, current)
		if phase == "Voting" then
			votes += 1
			if votes == 1 then
				for index, who in { ann, bo } do
					task.delay(0.5 * index, function()
						__remoteObjects.CastVote.__bindable:Fire(__playerKey(who), 1)
					end)
				end
			else
				task.delay(0.3, function()
					done = true
				end)
			end
		elseif phase == "Preparing" then
			local people, inRound = {}, 0
			for _, who in __fakePlayers do
				if who:GetAttribute("PP_InRound") then
					table.insert(people, who.Name)
				end
			end
			for _, bot in BotRegistry.List() do
				if bot:GetAttribute("PP_InRound") then
					inRound += 1
				end
			end
			table.insert(rounds, { at = at(), game = GameState.Get("GameId"), people = people, bots = inRound })
		elseif phase == "InRound" then
			task.delay(0.5, function()
				if rounds[#rounds] then
					rounds[#rounds].teams = teamsNow()
				end
			end)
		elseif phase == "Results" then
			results += 1
			if results == 1 then
				-- Everyone says PLAY AGAIN; a bot can't vote; Cy joins in the middle of the results.
				task.delay(0.3, function()
					summary.botReplayRefused = not ReplayService.Cast(bots[1], true)
				end)
				task.delay(0.5, tap, ann, true)
				task.delay(0.8, person, 3, "Cy")
				task.delay(1, tap, bo, true)
				-- 👍 from Ann; Bo's 👎 switched to 👍; a bot and Cy (not in this round) can't.
				task.delay(0.3, function()
					summary.botRatingRefused = not RatingService.Cast(bots[1], "Up")
				end)
				rateLater(0.4, ann, "Up")
				rateLater(0.6, bo, "Down")
				rateLater(0.9, bo, "Up")
				task.delay(1.2, function()
					local cy = __fakePlayers[3]
					if cy then
						rate(cy, "Up")
					end
				end)
			elseif results == 2 then
				-- Cy played this one, so he votes too: 1 of 3 want it, no replay (and everyone answered,
				-- so the results end early again).
				task.delay(0.5, tap, ann, true)
				task.delay(1, tap, bo, false)
				task.delay(1.5, function()
					local cy = __fakePlayers[3]
					if cy then
						tap(cy, false)
					end
				end)
				-- 👎 from Ann and Cy; Bo's 👍 taken back (the lit one tapped again sends "None"). Bo has no
				-- 👍 / 👎 in the end, so these results run their full time (everyone answered PLAY AGAIN,
				-- but ending early also takes a 👍 or 👎 from everyone).
				rateLater(0.4, ann, "Down")
				rateLater(0.6, bo, "Up")
				rateLater(0.9, bo, "None")
				task.delay(1.1, function()
					local cy = __fakePlayers[3]
					if cy then
						rate(cy, "Down")
					end
				end)
			end
		end
	end)

	SitOutService.Init()
	VotingService.Init()
	ReplayService.Init()
	RatingService.Init()
	FunnelService.Init()
	-- This game's week in the test store (PP_GameRatings_Test) before the run, to tell what it added.
	local GameRatings = __require("Shared/Logic/GameRatings")
	local ratingKey = `{GameRatings.Week(os.time())}/{id}`
	local ratingStore = game:GetService("DataStoreService"):GetDataStore("PP_GameRatings_Test")
	local okBefore, ratingBefore = pcall(ratingStore.GetAsync, ratingStore, ratingKey)
	local RoundManager = __require("Server/Services/RoundManager")
	RoundManager.Init()
	local loop = task.spawn(RoundManager.Start)
	while not done and os.clock() - t0 < 230 do
		task.wait(0.25)
	end
	summary.finished = done
	summary.seconds = at()
	-- The funnels: Ann visits the shop and buys (through the real ShopService and the screens'
	-- remote), looks at the GOLD PASS, presses GET GOLD PASS and buys it (MarketplaceService stands in
	-- for that: the service's hooks are called), then Bo leaves. summary.funnels: every step logged.
	pcall(function()
		local ShopService = __require("Server/Services/ShopService")
		ShopService.Init()
		local profile = DataService.Get(ann)
		profile.Data.Coins = 100
		local funnel = __remoteObjects.Funnel.__bindable
		funnel:Fire(__playerKey(ann), "ShopOpen", "Trail")
		funnel:Fire(__playerKey(ann), "ShopPick", "Trail_Bubbles")
		funnel:Fire(__playerKey(ann), "Hacked", "nope") -- (not a step: ignored)
		__remoteObjects.ShopPurchase.__bindable:Fire(__playerKey(ann), "Trail_Bubbles")
		task.wait(0.2)
		funnel:Fire(__playerKey(ann), "GoldSeen")
		FunnelService.GoldPrompted(ann)
		FunnelService.GoldBought(ann)
		FunnelService.Left(bo)
	end)
	summary.funnels = FunnelService.Log()
	-- What went to Roblox's economy and progression reports (counted even for the stand-ins).
	local Telemetry = __require("Server/Services/Telemetry")
	summary.telemetry = {
		coinsIn = Telemetry.Counters["Coins:in"],
		coinsOut = Telemetry.Counters["Coins:out"],
		levels = Telemetry.Counters.Levels,
	}
	-- The ratings: the taps, every write (the record after it), and what the run added to this game's
	-- week (read back from the store).
	task.wait(3) -- the last round's write
	local okAfter, ratingAfter = pcall(ratingStore.GetAsync, ratingStore, ratingKey)
	local added = {}
	if okBefore and okAfter then
		local before, after = GameRatings.Clean(ratingBefore), GameRatings.Clean(ratingAfter)
		for _, name in { "Rounds", "Plays", "Up", "Down", "ReplayYes", "ReplayNo", "VoteOffers", "VoteWins" } do
			added[name] = (after :: any)[name] - (before :: any)[name]
		end
		added.Voters = `{GameRatings.CountVoters(before.Seen)} -> {GameRatings.CountVoters(after.Seen)}`
	end
	local writes = {}
	for _, write in RatingService.Writes() do
		local record = write.Record
		table.insert(
			writes,
			if record
				then `{write.Key}: rounds {record.Rounds}, plays {record.Plays}, up {record.Up}, down {record.Down}, replay {record.ReplayYes}/{record.ReplayNo}, vote {record.VoteWins}/{record.VoteOffers}`
				else `{write.Key}: FAILED {write.Error}`
		)
	end
	summary.ratings = {
		key = ratingKey,
		taps = rateTaps,
		added = if okBefore and okAfter then added else `couldn't read: {ratingBefore} {ratingAfter}`,
		writes = writes,
	}
	summary.phases = phases
	summary.replayVotes = replayVotes
	summary.rounds = rounds
	summary.builds = builds
	summary.toasts = toasts
	pcall(task.cancel, loop)
	Notifier.All = realAll
	summary.errors = __errors
	summary.log = __log
	summary.eventCounts = __eventCounts
	return game:GetService("HttpService"):JSONEncode(summary)
end
