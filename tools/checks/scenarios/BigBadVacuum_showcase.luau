-- Scenario for round_harness.py --bot: lays the Big Bad Vacuum's client-drawn parts out in its arena (the
-- boss, its brush arm, the dust bag, the plug, a brick and a pile of debris), so an arena dump
-- (--dump-at) can be rendered with tools/preview/render.py and the art checked without a client:
--
--   python3 tools/checks/round_harness.py BigBadVacuum --players 2 --seconds 12 --dump-at 8 \
--       --bot tools/checks/scenarios/BigBadVacuum_showcase.luau --map /tmp/bbv.map.json > /tmp/bbv.luau
--
-- The parts are copies of the templates the mode shares for its clients (ReplicatedStorage.MiniGameAssets).
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local done = false
	return function(elapsed)
		if done or elapsed < 2 or not mode.center then
			return
		end
		done = true
		local folder = game:GetService("ReplicatedStorage"):FindFirstChild("MiniGameAssets")
		if not folder then
			env.note("showcase: no MiniGameAssets")
			return
		end
		local center = mode.center
		local function put(name: string, cframe: CFrame): Model?
			local template = folder:FindFirstChild(name)
			if not template then
				env.note("showcase: missing " .. name)
				return nil
			end
			local copy = template:Clone()
			copy:PivotTo(cframe)
			copy.Parent = ctx.Arena
			return copy :: Model
		end
		local floorAt = CFrame.new(center.X, center.Y, center.Z)
		put("BigBadVacuumBody", floorAt)
		put("BigBadVacuumBrush", floorAt * CFrame.new(0, 0.2, 0))
		-- The dust bag hangs behind the boss (its pivot is its bottom).
		put("BigBadVacuumBag", floorAt * CFrame.new(0, 17 - 7.3, 12))
		put("BigBadVacuumPlug", floorAt * CFrame.new(0, 0, 40) * CFrame.Angles(0, math.rad(180), 0))
		put("BigBadVacuumCordLink", floorAt * CFrame.new(0, 0, 30))
		put("BigBadVacuumBrick", floorAt * CFrame.new(-8, 0, -34) * CFrame.Angles(0, math.rad(30), 0))
		put("BigBadVacuumBrick", floorAt * CFrame.new(-4, 0, -34) * CFrame.Angles(0, math.rad(-20), 0))
		put("BigBadVacuumDebris", floorAt * CFrame.new(6, 0, -34))
		env.note("showcase: parts placed")
	end
end
