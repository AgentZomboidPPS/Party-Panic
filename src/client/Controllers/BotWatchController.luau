-- Watches the bots on this screen during each round and tells the server what it saw (owner: "Bots
-- are STILL ruberbanding and floating." "This has got to be fixed. You said last time you did but
-- clearly you didnt fix it."). The test servers run no physics (Open Cloud's Luau tasks can't step
-- it: workspace:StepPhysics needs a plugin's rights), so only a real game shows how bots really
-- move, and this is how a real game tells us. For every bot drawn here:
--   * "snap": where it's drawn jumps more than SNAP studs in one frame beyond where its own motion
--     would have carried it (a rubber band); smaller jerks (over JERK) are only counted ("jerk");
--   * "hover": its feet stay more than HOVER studs above anything it could stand on under it for
--     HOVER_TIME, neither rising nor falling, while it isn't anchored ("head" when what holds it up
--     is someone's body);
--   * how long it was anchored (a mode holding it: a ride, a flight, Spleef's drop), and the
--     server's own counts on it this round (Services/BotService, MiniGames/Spleef): taken back from a
--     player's device (PP_Retakes), dropped by the server (PP_Drops), its speed clamped after a
--     shove (PP_Clamps).
-- And the same for this player's own character ("me"; owner: "Theres still invisible stuff I latched
-- onto on spleef."): its snaps (the server moving it), hovers ("mehover": held up by something no
-- ray can find), standing on something nearly invisible ("invisible", with its name), anchored time
-- and server drops.
-- One report per round (kind "Bots"), a few seconds into the results, through the client-report
-- remote: Services/ClientReports keeps each player's last few, tools/checks/client_reports.py prints
-- them. Light on phones: a few sums per body a frame, and one or two short rays per body ten times a
-- second.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)

local Participants = require(script.Parent.Parent.Participants)

local BotWatchController = {}

local SNAP = 5 -- studs beyond its own motion in one frame: a snap (reported)
local JERK = 2 -- smaller ones are counted
local HOVER = 2 -- feet this far above what's under it...
local HOVER_TIME = 0.5 -- ...this long...
local STILL = 3 -- ...moving up or down slower than this (studs/s): a hover
local PROBE_EVERY = 0.1
local SETTLE = 1.5 -- a character this new is still being placed: not watched yet
local EVENT_GAP = 8 -- the same kind of event for the same body, at most this often
local MAX_EVENTS = 14
local MAX_INVISIBLE = 3 -- of those, "invisible" lines (some arenas stand on invisible colliders)
local REPORT_AFTER = 4 -- seconds into the results

type Watch = {
	Character: Model,
	Since: number,
	Last: Vector3?,
	Velocity: Vector3,
	ProbeAt: number,
	ProbedAt: number?,
	LastY: number?,
	HoverFor: number,
	Noted: { [string]: number },
}

type Tally = {
	Game: string,
	Started: number,
	Closed: boolean,
	In: boolean,
	Events: { string },
	Invisible: number,
	Counts: { [string]: number },
	Anchored: { [string]: number },
	Start: { [Instance]: { [string]: number } },
}

local localPlayer = Players.LocalPlayer
local watches: { [Instance]: Watch } = {}
local tally: Tally? = nil
local rays = RaycastParams.new()
rays.FilterType = Enum.RaycastFilterType.Exclude
rays.RespectCanCollide = true

local SERVER_COUNTS = { "PP_Retakes", "PP_Drops", "PP_Clamps" }

local function round1(value: number): number
	return math.floor(value * 10 + 0.5) / 10
end

local function feetOf(humanoid: Humanoid, root: BasePart): number
	local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 3 else humanoid.HipHeight + root.Size.Y / 2
	return root.Position.Y - legs
end

-- How far the nearest other person is from a body (people's bumps were what threw bots about).
local function nearestPerson(position: Vector3, own: Model): string
	local best, mine = math.huge, false
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character ~= own and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local distance = (root.Position - position).Magnitude
			if distance < best then
				best, mine = distance, player == localPlayer
			end
		end
	end
	if best == math.huge then
		return "none"
	end
	return `{round1(best)}{if mine then "(me)" else ""}`
end

local function note(t: Tally, watch: Watch, who: string, kind: string, text: string)
	t.Counts[kind] = (t.Counts[kind] or 0) + 1
	local now = os.clock()
	local last = watch.Noted[kind]
	if last and now - last < EVENT_GAP then
		return
	end
	watch.Noted[kind] = now
	if kind == "invisible" then
		if t.Invisible >= MAX_INVISIBLE then
			return
		end
		t.Invisible += 1
	end
	if #t.Events < MAX_EVENTS then
		table.insert(t.Events, `{kind} {who} t={round1(now - t.Started)} {text}`)
	end
end

-- The first thing under a body's middle it could stand on (as its own collision group sees it).
local function under(root: BasePart, exclude: { Instance }, depth: number): RaycastResult?
	rays.FilterDescendantsInstances = exclude
	rays.CollisionGroup = root.CollisionGroup
	return workspace:Raycast(root.Position, Vector3.new(0, -depth, 0), rays)
end

-- One look at a body: snaps every frame, the rest every PROBE_EVERY. `everyone`: every character.
local function look(
	t: Tally,
	watch: Watch,
	who: string,
	isMe: boolean,
	humanoid: Humanoid,
	root: BasePart,
	dt: number,
	everyone: { Instance }
)
	local now = os.clock()
	local position = root.Position
	local last = watch.Last
	watch.Last = position
	if now - watch.Since < SETTLE then
		return
	end
	local character = watch.Character
	-- (Not on a frame this device hitched: a landing from a long fall would read as a jump.)
	if last and dt > 0 and dt < 0.05 then
		local moved = position - last
		local miss = moved - watch.Velocity * dt
		local off = miss.Magnitude
		if off > SNAP then
			note(
				t,
				watch,
				who,
				if isMe then "mesnap" else "snap",
				`off={round1(off)} speed={round1(watch.Velocity.Magnitude)} anchored={root.Anchored} state={humanoid:GetState().Name} near={nearestPerson(
					position,
					character
				)}`
			)
		elseif Vector2.new(miss.X, miss.Z).Magnitude > JERK then
			-- (Sideways only: jumps and landings change speed up and down in a frame.)
			local kind = if isMe then "mejerk" else "jerk"
			t.Counts[kind] = (t.Counts[kind] or 0) + 1
		end
		watch.Velocity += (moved / dt - watch.Velocity) * 0.5
	end

	if now < watch.ProbeAt then
		return
	end
	local span = if watch.ProbedAt then math.min(now - watch.ProbedAt, 0.5) else 0
	watch.ProbedAt = now
	watch.ProbeAt = now + PROBE_EVERY
	local vy = if watch.LastY and span > 0 then (position.Y - watch.LastY) / span else 0
	watch.LastY = position.Y
	if not isMe then
		t.Counts.watched = (t.Counts.watched or 0) + span
	end
	if root.Anchored then
		watch.HoverFor = 0
		t.Anchored[who] = (t.Anchored[who] or 0) + span
		return
	end
	if humanoid.Sit or humanoid.PlatformStand or root.AssemblyRootPart ~= root then
		watch.HoverFor = 0 -- riding something (a ball, a board, a seat): not standing anywhere
		return
	end
	local feet = feetOf(humanoid, root)
	local depth = position.Y - feet + 80
	local ground = under(root, everyone, depth)
	local gap = if ground then feet - ground.Position.Y else math.huge
	if isMe and ground and gap < 0.6 and ground.Instance.Transparency > 0.9 then
		local part = ground.Instance
		note(t, watch, who, "invisible", `on={part:GetFullName()} ({part.ClassName} {part.Size})`)
	end
	if gap <= HOVER or math.abs(vy) >= STILL then
		watch.HoverFor = 0
		return
	end
	watch.HoverFor += span
	if watch.HoverFor < HOVER_TIME then
		return
	end
	watch.HoverFor = -math.huge -- (once per hover: it starts over when it's back on something)
	local holder = under(root, { character }, depth)
	local body = holder and holder.Instance:FindFirstAncestorOfClass("Model")
	if holder and body and body:FindFirstChildOfClass("Humanoid") and feet - holder.Position.Y < 0.6 then
		note(t, watch, who, "head", `on={body.Name} near={nearestPerson(position, character)}`)
	else
		note(
			t,
			watch,
			who,
			if isMe then "mehover" else "hover",
			`gap={if gap == math.huge then "none" else tostring(round1(gap))} vy={round1(vy)} state={humanoid:GetState().Name} near={nearestPerson(
				position,
				character
			)}`
		)
	end
end

local function step(dt: number)
	local t = tally
	if not t or t.Closed then
		return
	end
	local list = Participants.All()
	local everyone = {}
	for _, entry in list do
		local character = entry:Character()
		if character then
			table.insert(everyone, character)
		end
	end
	for _, entry in list do
		if not entry.IsBot and not entry.IsLocal then
			continue
		end
		local character = entry:Character()
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not humanoid or not root or humanoid.Health <= 0 then
			continue
		end
		local watch = watches[entry.Instance]
		if not watch or watch.Character ~= character then
			watch = {
				Character = character,
				Since = os.clock(),
				Velocity = Vector3.zero,
				ProbeAt = 0,
				HoverFor = 0,
				Noted = {},
			}
			watches[entry.Instance] = watch :: Watch
		end
		local who = if entry.IsLocal then "me" else (string.gsub(entry.Name, "^Bot_", ""))
		look(t, watch :: Watch, who, entry.IsLocal, humanoid, root, dt, everyone)
	end
end

local function counts(instance: Instance): { [string]: number }
	local list = {}
	for _, name in SERVER_COUNTS do
		list[name] = tonumber(instance:GetAttribute(name)) or 0
	end
	return list
end

local function begin()
	local start = {}
	for _, entry in Participants.All() do
		if entry.IsBot or entry.IsLocal then
			start[entry.Instance] = counts(entry.Instance)
		end
	end
	tally = {
		Game = tostring(GameState.Get("GameId") or "?"),
		Started = os.clock(),
		Closed = false,
		In = localPlayer:GetAttribute("PP_InRound") == true,
		Events = {},
		Invisible = 0,
		Counts = {},
		Anchored = {},
		Start = start,
	}
	table.clear(watches)
end

local function finish(t: Tally)
	if tally == t then
		tally = nil
	end
	if (t.Counts.watched or 0) <= 0 then
		return -- no bots seen this round
	end
	-- The server's own counts on each one this round.
	local server = {}
	for instance, before in t.Start do
		if not instance.Parent then
			continue
		end
		local now = counts(instance)
		local parts = {}
		for _, name in SERVER_COUNTS do
			local delta = now[name] - before[name]
			if delta > 0 then
				local short = string.sub(name, 4)
				t.Counts[short] = (t.Counts[short] or 0) + delta
				table.insert(parts, `{short}={delta}`)
			end
		end
		if #parts > 0 then
			local who = if instance == localPlayer then "me" else (string.gsub(instance.Name, "^Bot_", ""))
			table.insert(server, `{who} {table.concat(parts, " ")}`)
		end
	end
	local anchored = {}
	for who, seconds in t.Anchored do
		if seconds >= 0.05 then
			table.insert(anchored, `{who} {round1(seconds)}s`)
		end
	end
	t.Counts.watched = round1(t.Counts.watched or 0)
	Remotes.Get("ClientReport"):FireServer({
		Kind = "Bots",
		Where = t.Game,
		Touch = UserInputService.TouchEnabled,
		In = t.In,
		Seconds = round1(os.clock() - t.Started),
		Counts = t.Counts,
		Events = t.Events,
		Server = server,
		Anchored = anchored,
	})
end

function BotWatchController.Start()
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(step, dt)
		local t = tally
		if not ok and t then
			t.Counts.errors = (t.Counts.errors or 0) + 1
			if #t.Events < MAX_EVENTS and (t.Counts.errors or 0) <= 1 then
				table.insert(t.Events, `error {string.sub(tostring(err), 1, 120)}`)
			end
		end
	end)
	GameState.Changed("Phase", function(phase)
		local t = tally
		if phase == "InRound" then
			if t then
				pcall(finish, t)
			end
			begin()
		elseif t and not t.Closed then
			-- The round is over: stop watching, report a moment into the results.
			t.Closed = true
			task.delay(if phase == "Results" then REPORT_AFTER else 0, function()
				pcall(finish, t)
			end)
		end
	end)
	if GameState.Get("Phase") == "InRound" then
		begin()
	end
end

return BotWatchController
