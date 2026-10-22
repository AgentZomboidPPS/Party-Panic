-- Scenario for round_harness.py --client --bot: nobody is held in mid-air over the lobby (owner:
-- "Friend spawned above the lobby floating. We need to make sure this doesnt happen again."). Two
-- seconds into the round the stand-in client (Bot1) is moved, one case at a time, next to a test
-- floor built beside the arena, and the log says whether its device holds it there
-- (Controllers/ArrivalController.HeldAt) and what the server's lobby watch sees
-- (LobbyService.Floating):
--   lobby, 5 up        as a respawn on top of a bot: never held (it drops to the floor)
--   lobby, nothing     no floor under it for 80 studs (the lobby still downloading): held
--   arena, 5 up        in the round, nothing within reach of its soles: held (the arena loading)
--   arena, on floor    never held
--   lobby, 9 up / on floor / heel on the edge   the server's watch: floating / not / not
-- "PROBLEM" marks any that came out wrong. Then it goes back where it was.
--
--   python3 tools/checks/round_harness.py FireRope --players 2 --client --seconds 20 \
--       --bot tools/checks/scenarios/LobbyFloat.luau > float.luau
return function(env)
	local started = false
	return function(elapsed)
		if started or elapsed < 2 then
			return
		end
		started = true
		task.spawn(function()
			local arrival = __require("Client/Controllers/ArrivalController")
			local LobbyService = __require("Server/Services/LobbyService")
			local me = env.players[1]
			local character = me.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not root or not humanoid then
				env.note("LOBBYFLOAT PROBLEM: no character")
				return
			end
			local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 3 else humanoid.HipHeight + root.Size.Y / 2
			local home = root.CFrame
			local wasIn, wasAlive = me:GetAttribute("PP_InRound"), me:GetAttribute("PP_Alive")
			-- (above the round's KillY, or the round would take the stand-in back to its spot)
			local origin = __require("Shared/Config").ArenaOrigin
			local base = Vector3.new(origin.X + 400, origin.Y + 120, origin.Z)
			local floor = Instance.new("Part")
			floor.Name = "LobbyFloatTestFloor"
			floor.Anchored = true
			floor.Size = Vector3.new(40, 1, 40)
			floor.CFrame = CFrame.new(base - Vector3.new(0, legs + 0.5, 0))
			floor.Parent = workspace
			local top = floor.Position.Y + 0.5
			-- (each case takes the stand-in's character as it is then: the harness can give it a new one)
			local function place(lobby: boolean, at: Vector3, settle: number?)
				me:SetAttribute("PP_InRound", not lobby)
				me:SetAttribute("PP_Alive", not lobby)
				task.wait(0.2)
				character = me.Character
				root = character and character:FindFirstChild("HumanoidRootPart")
				humanoid = character and character:FindFirstChildOfClass("Humanoid")
				character:PivotTo(CFrame.new(at))
				task.wait(settle or 0.4)
			end
			-- Whether the device holds it there: its ground check (ArrivalController.GroundUnder: no ground
			-- means held) and, a moment after the move, whether it's held.
			local function check(label: string, want: boolean)
				local ground = arrival.GroundUnder(character, humanoid, root)
				local held = arrival.HeldAt() ~= nil
				local p = root.Position - base
				env.note(
					`LOBBYFLOAT {label}: {if ground then "ground" else "no ground: held"}{if ground == want
						then " PROBLEM"
						else ""} (HeldAt {if held then "set" else "nil"}, root at {math.floor(p.X + 0.5)}, {math.floor(
						p.Y + 0.5
					)}, {math.floor(p.Z + 0.5)} from the test spot)`
				)
			end
			local over = Vector3.new(base.X, top + legs, base.Z)
			place(true, over + Vector3.new(0, 5, 0))
			check("lobby, 5 up", false)
			place(true, over + Vector3.new(900, 0, 0))
			check("lobby, nothing under it", true)
			place(false, over + Vector3.new(0, 5, 0))
			check("arena, 5 up", true)
			place(false, over)
			check("arena, on the floor", false)
			for _, case in
				{
					{ "lobby watch, 9 up", over + Vector3.new(0, 9, 0), true },
					{ "lobby watch, on the floor", over, false },
					{ "lobby watch, heel on the edge", over + Vector3.new(21.5, 0, 0), false },
				}
			do
				place(true, case[2], 0.05) -- (the server's watch needs no frames: right away)
				local floating, where = LobbyService.Floating(me)
				env.note(
					`LOBBYFLOAT {case[1]}: {if floating then "floating " .. where else "standing"}{if floating
							~= case[3]
						then " PROBLEM"
						else ""}`
				)
			end
			me:SetAttribute("PP_InRound", wasIn)
			me:SetAttribute("PP_Alive", wasAlive)
			character:PivotTo(home)
			floor:Destroy()
		end)
	end
end
