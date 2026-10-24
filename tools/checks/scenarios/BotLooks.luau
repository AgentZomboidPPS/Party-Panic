-- Scenario for round_harness.py --bots N --bot: how the round's bots are dressed (owner: "Can we make
-- the bots look more like real players?"; Shared/Logic/BotLooks). A few seconds in it notes each
-- bot's name and what its character really wears: its accessories, a shirt and pants with pictures, a
-- dynamic head, its body; a bot in nothing but its body is a PROBLEM.
--
--   python3 tools/checks/round_harness.py HexMeltdown --players 1 --bots 8 --seconds 20 \
--       --bot tools/checks/scenarios/BotLooks.luau > looks.luau
return function(env)
	local BotRegistry = __require("Server/Services/BotRegistry")
	local reported = false
	return function(elapsed)
		if elapsed < 3 or reported then
			return
		end
		reported = true
		local bare = 0
		for _, bot in BotRegistry.List() do
			local character = bot.Character
			if not character then
				continue
			end
			local wears = {}
			for _, item in character:GetChildren() do
				if item:IsA("Accessory") then
					table.insert(wears, item.Name)
				end
			end
			local shirt = character:FindFirstChildOfClass("Shirt")
			local pants = character:FindFirstChildOfClass("Pants")
			local head = character:FindFirstChild("Head")
			local dressed = shirt ~= nil and shirt.ShirtTemplate ~= "" and pants ~= nil and pants.PantsTemplate ~= ""
			if not dressed then
				bare += 1
			end
			env.note(
				`BOTLOOKS {bot.DisplayName}: {if dressed then "shirt + pants" else "NO CLOTHES"}, `
					.. `{if head and head:FindFirstChildOfClass("FaceControls") then "dynamic head" else "classic head"}, `
					.. `{#wears} accessories ({table.concat(wears, ", ")})`
			)
		end
		env.note(`BOTLOOKS {if bare > 0 then `PROBLEM: {bare} undressed` else "every bot dressed"}`)
	end
end
