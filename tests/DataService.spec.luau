-- Saved data end to end: the real Services/DataService.luau, run here with stand-ins for Roblox (an
-- in-memory DataStore that can be slow or fail, fake players, a clock 200 times faster), so the
-- saves around joining, leaving and the server closing are checked without touching any real save.
-- (The owner restarts every server after each publish, so closing with players in it is routine.)
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local task = require("@lune/task")

local TestKit = require("./TestKit")
local DailyLogic = require("../src/shared/Logic/DailyLogic")
local LevelCurve = require("../src/shared/Logic/LevelCurve")
local MasteryLogic = require("../src/shared/Logic/MasteryLogic")
local MedalLogic = require("../src/shared/Logic/MedalLogic")
local ProfileMigration = require("../src/shared/Logic/ProfileMigration")
local ProfileTemplate = require("../src/shared/Logic/ProfileTemplate")
local TableUtil = require("../src/shared/Logic/TableUtil")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue
local copy = TableUtil.DeepCopy

local SOURCE = fs.readFile("src/server/Services/DataService.luau")
local SCALE = 0.005 -- real seconds per game second

-- Waits `seconds` of game time.
local function wait(seconds: number)
	task.wait(seconds * SCALE)
end

-- Waits (up to `limit` game seconds) until `check()` is true; returns whether it became true.
local function waitFor(check: () -> boolean, limit: number?): boolean
	local deadline = os.clock() + (limit or 60) * SCALE
	while not check() do
		if os.clock() > deadline then
			return false
		end
		task.wait(SCALE / 4)
	end
	return true
end

local function signal()
	local handlers = {}
	return {
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
		Fire = function(_, ...)
			for _, fn in table.clone(handlers) do
				task.spawn(fn, ...)
			end
		end,
	}
end

-- A stand-in Instance: a name, a parent, children found by name, attributes.
local function node(className: string, fields: { [string]: any }?): any
	local data: { [string]: any } = { ClassName = className, Name = className, Value = 0 }
	local children = {}
	local attributes = {}
	for key, value in fields or {} do
		data[key] = value
	end
	local self
	self = setmetatable({}, {
		__index = function(_, key)
			if key == "FindFirstChild" then
				return function(_, name)
					for _, child in children do
						if child.Name == name then
							return child
						end
					end
					return nil
				end
			elseif key == "SetAttribute" then
				return function(_, name, value)
					attributes[name] = value
				end
			elseif key == "GetAttribute" then
				return function(_, name)
					return attributes[name]
				end
			elseif key == "__children" then
				return children
			end
			return data[key]
		end,
		__newindex = function(_, key, value)
			if key == "Parent" then
				local old = data.Parent
				if type(old) == "table" and old.__children then
					local index = table.find(old.__children, self)
					if index then
						table.remove(old.__children, index)
					end
				end
				data.Parent = value
				if type(value) == "table" and value.__children then
					table.insert(value.__children, self)
				end
			else
				data[key] = value
			end
		end,
	})
	return self
end

-- The DataStore: records by key, and per key a list of plans for the next calls ({ delay = game
-- seconds before it runs, reply = game seconds between its write and its answer, fail = "before"
-- (nothing written) or "after" (written, then an error) }).
local function newStore()
	local store = { records = {} :: { [string]: any }, plans = {} :: { [string]: { any } }, log = {} :: { string } }
	function store.UpdateAsync(_, key: string, transform: (any) -> any): any
		local plan = table.remove(store.plans[key] or {}, 1) or {}
		if plan.delay then
			wait(plan.delay)
		end
		if plan.fail == "before" then
			table.insert(store.log, "fail")
			error("DataStore request failed (test)")
		end
		local result = transform(copy(store.records[key]))
		if result == nil then
			table.insert(store.log, "cancel")
			return nil
		end
		store.records[key] = copy(result)
		table.insert(store.log, "write")
		if plan.reply then
			wait(plan.reply)
		end
		if plan.fail == "after" then
			error("DataStore request timed out after writing (test)")
		end
		return copy(result)
	end
	return store
end

-- A server running DataService (its own module state), on `store`.
local function server(store, options: { [string]: any }?)
	local world = {
		store = store,
		notices = {} :: { string },
		errors = {} :: { string },
		closers = {} :: { () -> () },
		stopped = false,
	}
	local function gameWait(seconds: number?)
		if world.stopped then
			coroutine.yield() -- the test is over: park background loops for good
		end
		return task.wait((seconds or 0) * SCALE)
	end
	local scaledTask = {
		wait = gameWait,
		delay = function(seconds: number?, fn, ...)
			return task.delay((seconds or 0) * SCALE, fn, ...)
		end,
		spawn = task.spawn,
		defer = task.defer,
		cancel = task.cancel,
	}
	local players = { PlayerAdded = signal(), PlayerRemoving = signal(), list = {} }
	function players.GetPlayers(_)
		return table.clone(players.list)
	end
	world.players = players
	local remotes = {
		Get = function(_name)
			return {
				FireClient = function() end,
				FireAllClients = function() end,
			}
		end,
	}
	local config = {
		Data = {
			StoreName = "Test",
			KeyPrefix = "Player_",
			AutosaveInterval = (options and options.autosave) or 120,
			SessionLockTimeout = 600,
			LoadRetries = 4,
		},
		DailyRewards = { 5, 6, 7 },
		Mastery = {
			Ranks = {
				{ Id = "Bronze", Name = "BRONZE", Icon = "", Points = 1, Wins = 0, Coins = 0, Keys = 0, Crates = 0 },
				{ Id = "Gold", Name = "GOLD", Icon = "", Points = 20, Wins = 0, Coins = 0, Keys = 0, Crates = 0 },
			},
		},
	}
	local shared = {
		Config = config,
		GameDefinitions = { List = { { Id = "FireRope" }, { Id = "HexMeltdown" } } },
		Remotes = remotes,
		Logic = {
			DailyLogic = DailyLogic,
			LevelCurve = LevelCurve,
			MasteryLogic = MasteryLogic,
			MedalLogic = MedalLogic,
			ProfileMigration = ProfileMigration,
			ProfileTemplate = ProfileTemplate,
			TableUtil = TableUtil,
		},
	}
	local services = {
		DataStoreService = {
			GetDataStore = function()
				return store
			end,
		},
		Players = players,
		ReplicatedStorage = { Shared = shared },
		RunService = {
			IsStudio = function()
				return false
			end,
		},
	}
	local env = {
		game = {
			JobId = (options and options.jobId) or "server-A",
			GetService = function(_, name)
				return services[name]
			end,
			BindToClose = function(_, fn)
				table.insert(world.closers, fn)
			end,
		},
		script = {
			Parent = {
				Notifier = {
					Send = function(_player, text)
						table.insert(world.notices, text)
					end,
				},
				Telemetry = {
					Error = function(kind, message)
						table.insert(world.errors, `{kind}: {message}`)
					end,
					PlayerEvent = function() end,
				},
			},
		},
		require = function(module)
			return module
		end,
		Instance = {
			new = function(className: string)
				if className == "BindableEvent" then
					local event = signal()
					return {
						Event = event,
						Fire = function(_, ...)
							event:Fire(...)
						end,
					}
				end
				return node(className)
			end,
		},
		task = scaledTask,
		warn = function() end,
		-- Luau's own library, as the game has it (os.clock counts game seconds, like task.wait).
		math = math,
		table = table,
		string = string,
		os = {
			time = os.time,
			date = os.date,
			clock = function()
				return os.clock() / SCALE
			end,
		},
		coroutine = coroutine,
		pcall = pcall,
		error = error,
		assert = assert,
		type = type,
		typeof = typeof,
		tostring = tostring,
		tonumber = tonumber,
		next = next,
		pairs = pairs,
		ipairs = ipairs,
		select = select,
		setmetatable = setmetatable,
		getmetatable = getmetatable,
		rawget = rawget,
		rawset = rawset,
		print = print,
	}
	local DataService = luau.load(SOURCE, { debugName = "DataService", environment = env })()
	world.DataService = DataService
	DataService.Init()

	function world.join(userId: number): any
		local player = node("Player", { UserId = userId, Name = `P{userId}`, DisplayName = `P{userId}` })
		player.Parent = players
		table.insert(players.list, player)
		players.PlayerAdded:Fire(player)
		return player
	end
	function world.leave(player)
		local index = table.find(players.list, player)
		if index then
			table.remove(players.list, index)
		end
		players.PlayerRemoving:Fire(player)
		player.Parent = nil
	end
	-- Runs the server's close (BindToClose) and returns how long it held the server (game seconds).
	function world.close(): number
		local started = os.clock()
		for _, fn in world.closers do
			fn()
		end
		return (os.clock() - started) / SCALE
	end
	function world.stop()
		world.stopped = true
	end
	return world
end

-- A veteran's save from live version 30 (old coin scale, no low-scale mark).
local function veteranRecord(coins: number)
	return {
		Data = {
			Version = 1,
			Coins = coins,
			XP = 5400,
			Owned = { Title_Rookie = true, Trail_Fire = true },
			Equipped = { Trail = "Trail_Fire", Title = "Title_Rookie", Victory = "", Elimination = "" },
			Stats = { RoundsPlayed = 61, Wins = 7 },
			Meta = { FirstJoin = 1, LastJoin = 2, Sessions = 3 },
		},
	}
end

local function loaded(world, player): any
	expectTrue(
		waitFor(function()
			return world.DataService.Get(player) ~= nil
		end),
		"the profile loads"
	)
	return world.DataService.Get(player)
end

local function released(world, key: string): boolean
	return waitFor(function()
		local record = world.store.records[key]
		return record ~= nil and record.Lock == nil and #world.store.log > 0
	end)
end

test("a veteran joins and leaves: coins converted once, told once, saved, lock let go", function()
	local store = newStore()
	store.records.Player_101 = veteranRecord(1234)
	local world = server(store)
	local player = world.join(101)
	local profile = loaded(world, player)
	expectEqual(profile.Data.Coins, 124)
	expectEqual(profile.Data.Meta.CoinNotice, { Kind = "Converted", Before = 1234, After = 124 })
	expectEqual(store.records.Player_101.Lock.JobId, "server-A", "loading took the lock")

	wait(7) -- the message comes 6 s after joining
	expectEqual(world.notices, { "Coins got smaller numbers, and prices too! Your 1234 coins are now 124." })
	expectEqual(profile.Data.Meta.CoinNotice, nil, "cleared once said")

	world.leave(player)
	expectTrue(released(world, "Player_101"), "the leave save lets go of the lock")
	local saved = store.records.Player_101.Data
	expectEqual(saved.Coins, 124)
	expectEqual(saved.EconomyVersion, 2)
	expectEqual(saved.CoinStamp, 124)
	expectEqual(saved.Meta.CoinNotice, nil)
	expectEqual(saved.Owned, { Title_Rookie = true, Trail_Fire = true })
	expectEqual(saved.Meta.Sessions, 4)
	expectEqual(world.errors, {})
	world.stop()
end)

test("leaving before the coin message shows: it's saved, and said on the next visit (once)", function()
	local store = newStore()
	store.records.Player_102 = veteranRecord(500)
	local world = server(store)
	local player = world.join(102)
	loaded(world, player)
	wait(1)
	world.leave(player)
	expectTrue(released(world, "Player_102"))
	expectEqual(world.notices, {})
	expectEqual(store.records.Player_102.Data.Meta.CoinNotice, { Kind = "Converted", Before = 500, After = 50 })

	local again = world.join(102)
	local profile = loaded(world, again)
	expectEqual(profile.Data.Coins, 50, "never converted twice")
	wait(7)
	expectEqual(world.notices, { "Coins got smaller numbers, and prices too! Your 500 coins are now 50." })
	world.leave(again)
	expectTrue(waitFor(function()
		local record = store.records.Player_102
		return record.Lock == nil and record.Data.Meta.CoinNotice == nil
	end))

	local third = world.join(102)
	loaded(world, third)
	wait(7)
	expectEqual(#world.notices, 1, "said once")
	world.leave(third)
	world.stop()
end)

test("left while loading: only the lock is released, the save itself is untouched", function()
	local store = newStore()
	store.records.Player_103 = veteranRecord(1234)
	local before = copy(store.records.Player_103.Data)
	store.plans.Player_103 = { { reply = 3 } } -- a slow load (the lock is taken, the answer is late)
	local world = server(store)
	local player = world.join(103)
	wait(1)
	world.leave(player) -- gone before the load finished
	expectTrue(waitFor(function()
		return #store.log >= 2
	end))
	expectEqual(store.log, { "write", "write" }, "the load, then the lock release")
	expectEqual(store.records.Player_103.Lock, nil)
	expectEqual(store.records.Player_103.Data, before, "the coins wait for a real visit to be converted")
	expectEqual(world.DataService.Get(player), nil)

	-- Gone before the load's request was even read: it takes no lock at all.
	store.plans.Player_103 = { { delay = 3 } }
	local again = world.join(103)
	wait(1)
	world.leave(again)
	expectTrue(waitFor(function()
		return #store.log >= 3
	end))
	wait(2)
	expectEqual(store.log, { "write", "write", "cancel" }, "nothing written")
	expectEqual(store.records.Player_103.Lock, nil)
	expectEqual(store.records.Player_103.Data, before)
	world.stop()
end)

test("a leave save that fails is tried again until it's written", function()
	local store = newStore()
	local world = server(store)
	local player = world.join(104)
	local profile = loaded(world, player)
	profile.Data.Coins += 9 -- played a round
	store.plans.Player_104 = { { fail = "before" }, { fail = "before" } }
	world.leave(player)
	expectTrue(released(world, "Player_104"))
	expectEqual(store.records.Player_104.Data.Coins, 9)
	expectEqual(store.log, { "write", "fail", "fail", "write" })
	expectEqual(#world.errors, 2, "each failed try is logged")
	-- Written but reported as failed: tried again, same result.
	local other = world.join(105)
	loaded(world, other).Data.Coins += 3
	store.plans.Player_105 = { { fail = "after" } }
	world.leave(other)
	expectTrue(waitFor(function()
		return #store.log >= 7
	end))
	expectEqual(store.records.Player_105.Data.Coins, 3)
	expectEqual(store.records.Player_105.Lock, nil)
	world.stop()
end)

test("the server's close waits for every save still running, including players who just left", function()
	local store = newStore()
	local world = server(store)
	local leaving = world.join(106)
	local staying = world.join(107)
	loaded(world, leaving).Data.Coins += 5
	loaded(world, staying).Data.Coins += 7
	store.plans.Player_106 = { { delay = 3 } } -- the leave save takes a while
	store.plans.Player_107 = { { fail = "before" }, { delay = 1 } } -- the close's save fails once
	world.leave(leaving)
	wait(0.5)
	local held = world.close()
	-- Both written by the time the close lets the server go.
	expectEqual(store.records.Player_106.Data.Coins, 5)
	expectEqual(store.records.Player_106.Lock, nil)
	expectEqual(store.records.Player_107.Data.Coins, 7)
	expectEqual(store.records.Player_107.Lock, nil)
	expectTrue(held >= 2 and held < 25, `the close held the server {held} s`)
	world.stop()
end)

test("an autosave still running when the player leaves never locks the record again", function()
	local store = newStore()
	local world = server(store, { autosave = 10 })
	local player = world.join(108)
	loaded(world, player).Data.Coins += 4
	task.spawn(world.DataService.Start)
	store.plans.Player_108 = { { delay = 20 } } -- the autosave at 10 s is slow
	wait(12)
	world.leave(player) -- its release save goes through first
	expectTrue(waitFor(function()
		return #store.log >= 3
	end, 40))
	expectEqual(store.log, { "write", "write", "cancel" }, "load, release, the late autosave cancelled")
	expectEqual(store.records.Player_108.Lock, nil)
	expectEqual(store.records.Player_108.Data.Coins, 4)
	world.stop()
end)

test("back on the same server while their last save is still being tried: the load waits for it", function()
	local store = newStore()
	local world = server(store)
	local first = world.join(109)
	loaded(world, first).Data.Coins += 6
	store.plans.Player_109 = { { fail = "before" } }
	world.leave(first)
	wait(0.3)
	local again = world.join(109) -- the release is waiting for its second try
	local profile = loaded(world, again)
	expectEqual(profile.Data.Coins, 6, "loaded what the last visit saved")
	world.leave(again)
	expectTrue(released(world, "Player_109"))
	world.stop()
end)

-- Two visits of one player to the same server: each lock names its session, so the first visit
-- can't clear the second one's lock (the second would play unlocked until its first autosave).
test("back on the same server while the load they left is still running: it waits, and keeps its lock", function()
	local store = newStore()
	store.records.Player_112 = veteranRecord(1000)
	store.plans.Player_112 = { { reply = 5 } } -- the first visit's load: lock taken, a slow answer
	local world = server(store)
	local first = world.join(112)
	wait(1)
	world.leave(first)
	wait(0.5)
	local again = world.join(112) -- that load is still running
	local profile = loaded(world, again)
	wait(6) -- (the first visit's load is over by now, whenever this one loaded)
	local lock = store.records.Player_112.Lock
	expectTrue(lock ~= nil and lock.JobId == "server-A", "this visit holds the lock")
	expectEqual(lock.Session, profile.Session)
	expectEqual(store.log, { "write", "write", "write" }, "the first load, its lock release, then this load")
	profile.Data.Coins += 5
	world.leave(again)
	expectTrue(released(world, "Player_112"))
	expectEqual(store.records.Player_112.Data.Coins, 105)
	expectEqual(world.errors, {})
	world.stop()
end)

test("the load they left answers after the 30 s wait: its lock release leaves the next visit's lock", function()
	local store = newStore()
	store.records.Player_115 = veteranRecord(1000)
	store.plans.Player_115 = { { reply = 40 } } -- the first visit's load: lock taken, the answer 40 s late
	local world = server(store)
	local first = world.join(115)
	wait(1)
	world.leave(first)
	wait(0.5)
	local again = world.join(115) -- waits 30 s for that load, then loads anyway
	local profile = loaded(world, again)
	expectTrue(
		waitFor(function()
			return #store.log >= 3
		end),
		"the late answer came, and its lock release ran"
	)
	local lock = store.records.Player_115.Lock
	expectTrue(lock ~= nil and lock.JobId == "server-A", "this visit still holds the lock")
	expectEqual(lock.Session, profile.Session)
	expectEqual(store.log, { "write", "write", "cancel" }, "the first load, this load, then that release refused")
	profile.Data.Coins += 5
	world.leave(again)
	expectTrue(released(world, "Player_115"))
	expectEqual(store.records.Player_115.Data.Coins, 105)
	expectEqual(world.errors, {})
	world.stop()
end)

test("a leave save slower than the wait on rejoining never clears the next visit's lock", function()
	local store = newStore()
	local world = server(store)
	local first = world.join(113)
	loaded(world, first).Data.Coins += 7
	store.plans.Player_113 = {
		{ delay = 9, fail = "before" }, -- the leave save fails slowly...
		{ delay = 9, fail = "before" },
		{ delay = 9, fail = "before" },
		{}, -- (the next visit's load, once its 30 s wait is over)
		{ delay = 2 }, -- ...and its last try comes after that load
	}
	world.leave(first)
	wait(1)
	local again = world.join(113)
	local profile = loaded(world, again)
	expectTrue(waitFor(function()
		return #store.log >= 6
	end))
	expectEqual(store.log[6], "cancel", "the late leave save is refused")
	local lock = store.records.Player_113.Lock
	expectTrue(lock ~= nil and lock.Session == profile.Session, "the next visit keeps its lock")
	expectEqual(world.errors[#world.errors], "DataSave: Player_113: session lock lost, save skipped")
	profile.Data.Coins += 3
	world.leave(again)
	expectTrue(released(world, "Player_113"))
	expectEqual(store.records.Player_113.Data.Coins, 3, "saved what the next visit had (it loaded before 7 were)")
	world.stop()
end)

test("locks from before sessions were numbered: another server's keeps us out, our own lets us save", function()
	local store = newStore()
	store.records.Player_114 = veteranRecord(1000)
	store.records.Player_114.Lock = { JobId = "server-OLD", Time = os.time() } -- an older server, still playing
	local world = server(store, { autosave = 5 })
	local player = world.join(114)
	wait(2)
	expectEqual(world.DataService.Get(player), nil, "kept out while the older server holds it")
	store.records.Player_114.Lock = nil -- (its leave save lets go)
	local profile = loaded(world, player)
	expectEqual(store.records.Player_114.Lock.Session, profile.Session)
	task.spawn(world.DataService.Start)
	-- A lock with this server's JobId and no Session (the old form) still counts as this session's.
	store.records.Player_114.Lock = { JobId = "server-A", Time = os.time() }
	profile.Data.Coins += 4
	expectTrue(
		waitFor(function()
			return store.records.Player_114.Data.Coins == 104
		end, 10),
		"the autosave went through"
	)
	expectEqual(store.records.Player_114.Lock.Session, profile.Session, "and locked it as this session's")
	store.records.Player_114.Lock = { JobId = "server-A", Time = os.time() }
	profile.Data.Coins += 1
	world.leave(player)
	expectTrue(released(world, "Player_114"), "the leave save went through")
	expectEqual(store.records.Player_114.Data.Coins, 105)
	expectEqual(world.errors, {})
	world.stop()
end)

test("a save this code can't read is never overwritten: the player plays on a temporary profile", function()
	local store = newStore()
	store.records.Player_111 = { Data = { Coins = 77, Meta = "broken" } }
	local world = server(store)
	local player = world.join(111)
	local profile = loaded(world, player)
	expectEqual(profile.CanSave, false)
	expectTrue(released(world, "Player_111"), "the lock goes at once")
	profile.Data.Coins += 5
	wait(4)
	expectEqual(
		world.notices,
		{ "Progress saving is unavailable right now. Your progress this session won't be saved." }
	)
	world.leave(player)
	wait(2)
	expectEqual(store.records.Player_111.Data, { Coins = 77, Meta = "broken" }, "the save is as it was")
	expectEqual(store.log, { "write", "write" }, "the load and the lock release, nothing else")
	world.stop()
end)

test("another server can't load a profile this one holds, and takes it over only from a dead server", function()
	local store = newStore()
	local a = server(store, { jobId = "server-A" })
	local player = a.join(110)
	loaded(a, player).Data.Coins += 8
	-- The player shows up on server B while A still has them (A's lock is live): B waits, A's
	-- leave save lands, B loads what A saved.
	local b = server(store, { jobId = "server-B" })
	local onB = b.join(110)
	wait(1)
	a.leave(player)
	local profile = loaded(b, onB)
	expectEqual(profile.Data.Coins, 8)
	expectEqual(store.records.Player_110.Lock.JobId, "server-B")
	b.leave(onB)
	expectTrue(released(b, "Player_110"))
	a.stop()
	b.stop()
end)

return nil
