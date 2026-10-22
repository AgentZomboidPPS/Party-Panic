-- Scenario for round_harness.py --bot: the PUMPKIN HAT on a real server (owner: "do pumpkin hat now";
-- Services/CosmeticService, World/Hats). Any mode works; the stand-ins don't play it.
--
--   python3 tools/checks/round_harness.py RakeItIn --players 3 --bots 1 --seconds 30 \
--       --bot tools/checks/scenarios/Hat_pumpkin.luau > hat.luau
--
-- The round harness doesn't start the cosmetics or the shop's remotes, so this starts them the way
-- the server does. Then, with the clock in the HALLOWEEN PARTY (each line of the log starts "hat:"):
--   * Bot1 (60 candy) claims the hat through EventAction: it owns it;
--   * EQUIP through ShopEquip while in the round (PP_InRound): equipped, but no hat on in a round;
--   * PP_InRound off, as back in the lobby: the Accessory goes on the head, and what it's made of
--     (Handle, welds, sizes, mass, collisions, light, which way it faces) is noted;
--   * PP_InRound on and off again: off, then back; the PARTY CUP crown on and off: the hat steps
--     aside, then comes back; a fresh character (LoadCharacterAsync): it's on that one too;
--   * an R6 rig, and an R15 head without its HatAttachment: the hat fits both;
--   * unequip: off. The round state is put back after.
return function(env)
	local CosmeticService = __require("Server/Services/CosmeticService")
	local ShopService = __require("Server/Services/ShopService")
	local EventService = __require("Server/Services/EventService")
	local EventLogic = __require("Shared/Logic/EventLogic")
	local DataService = __require("Server/Services/DataService")
	local Hats = __require("Server/World/Hats")
	local CupCrown = __require("Server/World/CupCrown")

	local function note(text)
		env.note("hat: " .. text)
	end
	local bot1 = env.players[1]
	local HAT = "Hat_Pumpkin"

	for name, service in { CosmeticService = CosmeticService, ShopService = ShopService } do
		local ok, err = pcall(service.Init)
		if not ok then
			note(`{name}.Init failed: {err}`)
		end
	end
	local halloween = EventLogic.ParseUtc("2026-10-26 12:00") :: number
	local started = os.clock()
	EventService.SetClockForTests(function()
		return halloween + (os.clock() - started)
	end)

	local function profile(player)
		return DataService.Get(player).Data
	end
	local function send(remote, player, ...)
		__remoteObjects[remote].__bindable:Fire(__playerKey(player), ...)
	end
	-- Waits (up to `limit` seconds) for `check`, and says how long it took.
	local function waitFor(check, limit)
		local t0 = os.clock()
		while not check() and os.clock() - t0 < limit do
			task.wait(0.05)
		end
		return check(), math.round((os.clock() - t0) * 100) / 100
	end
	local function worn(player)
		return Hats.Worn(player.Character) or "none"
	end

	-- How the hat sits on `character`: the Accessory's make-up and its fit on the head.
	local function describe(character)
		local hat = character:FindFirstChild(Hats.Name)
		local head = character:FindFirstChild("Head")
		if not hat or not head then
			return "no hat"
		end
		local handle = hat:FindFirstChild("Handle")
		local parts, massless, solid, anchored, lights = 0, 0, 0, 0, 0
		local box = { math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge }
		for _, part in hat:GetDescendants() do
			if part:IsA("BasePart") then
				parts += 1
				massless += if part.Massless then 1 else 0
				solid += if part.CanCollide or part.CanTouch or part.CanQuery then 1 else 0
				anchored += if part.Anchored then 1 else 0
				-- Its corners in the head's space (the head's own axes, whatever way it turns).
				for _, sx in { -0.5, 0.5 } do
					for _, sy in { -0.5, 0.5 } do
						for _, sz in { -0.5, 0.5 } do
							local p = head.CFrame:PointToObjectSpace(
								part.CFrame:PointToWorldSpace(part.Size * Vector3.new(sx, sy, sz))
							)
							box[1], box[2] = math.min(box[1], p.X), math.max(box[2], p.X)
							box[3], box[4] = math.min(box[3], p.Y), math.max(box[4], p.Y)
							box[5], box[6] = math.min(box[5], p.Z), math.max(box[6], p.Z)
						end
					end
				end
			elseif part:IsA("PointLight") then
				lights += 1
			end
		end
		-- What holds it to the head (AddAccessory's weld, wherever the engine puts it).
		local joint = "NONE"
		for _, item in character:GetDescendants() do
			local a = item:IsA("JointInstance") and (item :: any).Part0
				or item:IsA("WeldConstraint") and (item :: any).Part0
			local b = item:IsA("JointInstance") and (item :: any).Part1
				or item:IsA("WeldConstraint") and (item :: any).Part1
			if (a == handle and b == head) or (a == head and b == handle) then
				joint = `{item.ClassName} {item.Name} in {item.Parent and item.Parent.Name}`
			elseif item:IsA("RigidConstraint") then
				local c0, c1 = (item :: any).Attachment0, (item :: any).Attachment1
				if c0 and c1 and (c0.Parent == handle or c1.Parent == handle) then
					joint = `RigidConstraint {item.Name} in {item.Parent and item.Parent.Name}`
				end
			end
		end
		local attachment = handle and handle:FindFirstChild("HatAttachment")
		local facing = if attachment
			then (handle.CFrame * attachment.CFrame).LookVector:Dot(head.CFrame.LookVector)
			else 0
		local r = function(x)
			return math.round(x * 100) / 100
		end
		local mesh = head:FindFirstChildWhichIsA("SpecialMesh")
		local kind = head.ClassName .. (if mesh then ` with a {mesh.MeshType.Name} mesh` else "")
		return `{hat.ClassName} {hat.AccessoryType.Name}, Handle {handle and handle.ClassName or "MISSING"}, `
			.. `held by {joint}, {parts} parts ({massless} massless, {anchored} anchored, `
			.. `{solid} colliding/touching/queried), {lights} light; head ({kind}) {r(head.Size.X)} x {r(head.Size.Y)} x `
			.. `{r(head.Size.Z)}, top at {r(head.Size.Y / 2)}; `
			.. `hat {r(box[2] - box[1])} wide ({r((box[2] - box[1]) / head.Size.X)} heads), from y {r(box[3])} to {r(
				box[4]
			)}, `
			.. `centred x {r((box[1] + box[2]) / 2)} z {r((box[5] + box[6]) / 2)}; faces the head's front {r(facing)}`
	end

	task.spawn(function()
		task.wait(0.5)
		-- Claim it (60 candy is past its 55).
		local saved = profile(bot1).Events
		saved.Halloween2026 = saved.Halloween2026 or {}
		EventLogic.Progress(saved.Halloween2026).Candy = 60
		send("EventAction", bot1, "Claim", HAT)
		task.wait(0.3)
		note(`claim: owned {profile(bot1).Owned[HAT] == true}, claimed {saved.Halloween2026.Claimed[HAT] == true}`)

		-- EQUIP in the round.
		note(`in the round: PP_InRound {bot1:GetAttribute("PP_InRound")}`)
		send("ShopEquip", bot1, "Hat", HAT)
		task.wait(0.3)
		note(`equip: Equipped.Hat {profile(bot1).Equipped.Hat}, worn in the round: {worn(bot1)}`)

		-- Back in the lobby.
		bot1:SetAttribute("PP_InRound", false)
		local on, took = waitFor(function()
			return worn(bot1) == HAT
		end, 20)
		note(`lobby: worn {worn(bot1)} after {took} s (on: {on})`)
		note("on Bot1 (R15): " .. describe(bot1.Character))
		local MeshLibrary = __require("Server/World/MeshLibrary")
		local loaded = MeshLibrary.Get("PumpkinHat")
		local pieces = {}
		for _, part in loaded:GetDescendants() do
			if part:IsA("BasePart") then
				local s = part.Size
				table.insert(
					pieces,
					`{part.ClassName} {part.Name} {math.round(s.X * 1000) / 1000} x {math.round(s.Y * 1000) / 1000} x {math.round(
						s.Z * 1000
					) / 1000} {part.Material.Name}`
				)
			end
		end
		note(
			`the prop as loaded ({MeshLibrary.Source and MeshLibrary.Source("PumpkinHat") or "?"}): {table.concat(
				pieces,
				"; "
			)}`
		)
		loaded:Destroy()

		bot1:SetAttribute("PP_InRound", true)
		local offInRound = worn(bot1)
		bot1:SetAttribute("PP_InRound", false)
		local _, back = waitFor(function()
			return worn(bot1) == HAT
		end, 5)
		note(`PP_InRound on: {offInRound}; off again: {worn(bot1)} after {back} s`)

		CupCrown.Attach(bot1.Character)
		task.wait(0.1)
		local underCrown = worn(bot1)
		local crowned = bot1.Character:FindFirstChild(CupCrown.Name) ~= nil
		CupCrown.Remove(bot1.Character)
		local _, afterCrown = waitFor(function()
			return worn(bot1) == HAT
		end, 5)
		note(`crown on: hat {underCrown} (the crown is on: {crowned}); crown off: {worn(bot1)} after {afterCrown} s`)

		local oldCharacter = bot1.Character
		bot1:LoadCharacterAsync()
		local _, fresh = waitFor(function()
			return bot1.Character ~= oldCharacter and worn(bot1) == HAT
		end, 15)
		note(`fresh character: new {bot1.Character ~= oldCharacter}, worn {worn(bot1)} after {fresh} s`)
		note("on the fresh character: " .. describe(bot1.Character))

		-- Other heads: R6, and an R15 head without its HatAttachment.
		local okR6, r6 = pcall(function()
			return RealPlayers:CreateHumanoidModelFromDescription(
				Instance.new("HumanoidDescription"),
				Enum.HumanoidRigType.R6
			)
		end)
		if okR6 then
			r6:PivotTo(CFrame.new(0, 5, 30))
			r6.Parent = workspace
			local ok, err = pcall(Hats.Attach, r6, HAT)
			note(`R6: {if ok then describe(r6) else tostring(err)}`)
			r6:Destroy()
		else
			note("R6 rig: " .. tostring(r6))
		end
		local bare = __makeRig("Bare")
		bare.Head.HatAttachment:Destroy()
		local okBare, bareErr = pcall(Hats.Attach, bare, HAT)
		note(
			`R15 without HatAttachment: {if okBare then describe(bare) else tostring(bareErr)}; `
				.. `the head has one now: {bare.Head:FindFirstChild("HatAttachment") ~= nil}`
		)
		bare:Destroy()

		-- Unequip, then the round's state as it was.
		send("ShopEquip", bot1, "Hat", "")
		task.wait(0.3)
		note(`unequip: Equipped.Hat "{profile(bot1).Equipped.Hat}", worn {worn(bot1)}`)
		bot1:SetAttribute("PP_InRound", true)
		EventService.SetClockForTests(nil)
	end)

	return function() end
end
