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
local __playerRemoving = Instance.new("BindableEvent")
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
		return 0.06
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

function __runRound(id, playerCount, seconds, botFactory, clientMode, dumpAt)
	local GameDefinitions = __require("Shared/GameDefinitions")
	local GameState = __require("Shared/GameState")
	local Config = __require("Shared/Config")
	GameState.Folder()
	local RoundContext = __require("Server/Services/RoundContext")
	__require("Server/World/Shapes").RecordPieces = true
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
		for _, name in { "NotificationController", "EffectsController", "RoundController", "MiniGameController" } do
			local okLoad, controller = pcall(__require, "Client/Controllers/" .. name)
			if not okLoad then
				__note(`client {name} failed to load: {controller}`)
				continue
			end
			task.spawn(function()
				local okStart, err = pcall(controller.Start, context)
				if not okStart then
					__note(`client {name} failed to start: {err}`)
				end
			end)
		end
		clientGuis = __localPlayer.PlayerGui
	end

	GameState.Set("RoundId", 1)
	GameState.Set("GameId", id)
	local ctx = RoundContext.new(1, definition, table.clone(__fakePlayers))
	local miniGame = module.new(ctx)
	local prepTime = Config.Session.RulesTime + Config.Session.CountdownTime
	local prepDeadline = os.clock() + prepTime
	setPhase("Preparing", prepTime)

	local t0 = os.clock()
	local okPrepare, prepareErr = pcall(miniGame.Prepare, miniGame)
	summary.prepare = if okPrepare then "ok" else tostring(prepareErr)
	summary.prepareSeconds = __round(os.clock() - t0)
	summary.arenaParts = #ctx.Arena:GetDescendants()
	while os.clock() < prepDeadline do
		task.wait(0.1)
	end

	local env = {
		ctx = ctx,
		game = miniGame,
		players = table.clone(__fakePlayers),
		rng = Random.new(7),
		note = __note,
		client = clientMode,
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
	function env.Leave(player)
		local index = table.find(__fakePlayers, player)
		if index then
			table.remove(__fakePlayers, index)
		end
		player.Parent = nil
		__playerRemoving:Fire(player)
	end

	local tick = if okPrepare then botFactory(env) else nil
	if okPrepare then
		ctx:Begin()
		setPhase("InRound", definition.Duration)
		local okStart, startErr = pcall(miniGame.Start, miniGame)
		summary.start = if okStart then "ok" else tostring(startErr)
		local limit = if seconds > 0 then math.min(seconds, definition.Duration) else definition.Duration
		local begin = os.clock()
		local last = begin
		while not ctx.EndReason do
			local now = os.clock()
			if now - begin >= limit then
				ctx:End(if now - begin >= definition.Duration then "TimeUp" else "HarnessStop")
				break
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
	local okCleanup, cleanupErr = pcall(miniGame.Cleanup, miniGame)
	summary.cleanup = if okCleanup then "ok" else tostring(cleanupErr)
	local okDestroy, destroyErr = pcall(ctx.Destroy, ctx)
	summary.destroy = if okDestroy then "ok" else tostring(destroyErr)
	task.wait(0.2)
	summary.arenaLeftovers = if ctx.Arena.Parent then #ctx.Arena:GetDescendants() else 0
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
	summary.errors = __errors
	summary.log = __log
	summary.eventCounts = __eventCounts
	summary.events = __events
	return HttpService:JSONEncode(summary)
end
