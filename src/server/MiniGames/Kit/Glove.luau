-- Melee "glove" tool used by Yeet Arena and Greedy Goblins.
--
-- The server validates every swing (design doc §8 "Server validates hits and cooldowns"):
-- cooldown, range and facing are checked here; the client only sends the click.
-- Knockback is applied by the victim's client because each player's client simulates their own
-- character's physics; the server decides direction, strength and stun.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local MeshLibrary = require(script.Parent.Parent.Parent.World.MeshLibrary)
local Notifier = require(script.Parent.Parent.Parent.Services.Notifier)

local knockbackRemote = Remotes.Get("Knockback")

local Glove = {}

export type GloveOptions = {
	Name: string,
	Color: Color3,
	Cooldown: number,
	Range: number,
	Power: () -> number,
	Lift: number,
	Stun: number,
	CanHit: ((attacker: Player, victim: Player) -> boolean)?,
	OnHit: ((attacker: Player, victim: Player) -> ())?,
}

local function swingAnimation(tool: Tool)
	-- The default Animate script plays its tool slash animation when it sees this value.
	local value = Instance.new("StringValue")
	value.Name = "toolanim"
	value.Value = "Slash"
	value.Parent = tool
	task.delay(0.5, function()
		value:Destroy()
	end)
end

function Glove.Give(context, player: Player, options: GloveOptions): Tool?
	local character, humanoid = context:GetCharacter(player)
	if not character or not humanoid then
		return nil
	end

	local tool = Instance.new("Tool")
	tool.Name = options.Name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = "Click / tap to swing"
	tool:SetAttribute("PP_RoundTool", true)

	local model = MeshLibrary.Get("YeetGlove", { Colors = { Glove = options.Color } })
	local handle = MeshLibrary.Assemble(model, true)
	handle.Name = "Handle"
	for _, part in model:GetChildren() do
		part.Parent = tool
	end
	model:Destroy()
	tool.Grip = CFrame.new(0, 0, 0.6)

	local lastSwing = 0
	context:Track(tool.Activated:Connect(function()
		if not context:IsRunning() or not context:IsAlive(player) then
			return
		end
		local now = os.clock()
		if now - lastSwing < options.Cooldown then
			return
		end
		lastSwing = now
		swingAnimation(tool)

		local _, _, attackerRoot = context:GetCharacter(player)
		if not attackerRoot then
			return
		end
		local look = attackerRoot.CFrame.LookVector
		local hitAny = false
		for _, victim in context:GetAlivePlayers() do
			if victim == player then
				continue
			end
			local _, _, victimRoot = context:GetCharacter(victim)
			if not victimRoot then
				continue
			end
			local offset = victimRoot.Position - attackerRoot.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local distance = flat.Magnitude
			if distance > options.Range or math.abs(offset.Y) > 6 then
				continue
			end
			if distance > 2 and look:Dot(flat.Unit) < 0.25 then
				continue -- must be roughly in front of the attacker
			end
			if options.CanHit and not options.CanHit(player, victim) then
				continue
			end
			local direction = if distance > 0.1 then flat.Unit else Vector3.new(look.X, 0, look.Z).Unit
			local velocity = direction * options.Power() + Vector3.new(0, options.Lift, 0)
			knockbackRemote:FireClient(victim, velocity, options.Stun)
			hitAny = true
			if options.OnHit then
				options.OnHit(player, victim)
			end
		end
		if hitAny then
			Notifier.Sound(nil, "Hit")
			Notifier.Effect("Stars", attackerRoot.Position + look * 3 + Vector3.new(0, 1, 0))
		end
	end))

	tool.Parent = player:FindFirstChildOfClass("Backpack")
	humanoid:EquipTool(tool)
	return tool
end

-- Removes round tools from every participant (idempotent).
function Glove.RemoveAll(context)
	for _, player in context:GetPlayers() do
		for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
			if not container then
				continue
			end
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute("PP_RoundTool") then
					child:Destroy()
				end
			end
		end
	end
end

return Glove
