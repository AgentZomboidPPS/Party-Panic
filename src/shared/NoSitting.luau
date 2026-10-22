-- No character ever sits (owner: "Also theres times where I will sit on invisible shit in game. NO
-- mini game should require you to sit."). Two invisible Seats used to catch people, one in every
-- lobby bench and one on each Sand King's throne; both are gone, nothing in the game sits anyone
-- down, and tests/NoSeats.spec.luau keeps Seats out of the code. This is the guard behind that: a
-- character can't take the Seated state at all, so a Seat that turns up anyway (a new prop, a
-- model from somewhere) can't catch anyone, and if something sets Sit regardless, the character
-- stands straight back up.
--
-- A humanoid's states change only on the machine that simulates it, so Guard runs there: on each
-- player's own device for their character (Controllers/MovementController) and on the server for
-- the bots (Services/NoSitService, which also watches players' characters from the server's side).
-- The rides that look seated, Bobsled Run's sleds and Minecart Mayhem's carts, pose their riders
-- themselves (PlatformStand and their own joint poses), not with the Seated state, so this leaves
-- them alone; Shark Bait's stuck watchdog still frees a character held by any other state.

local NoSitting = {}

-- Turns sitting off for a character's humanoid, waiting a moment for it on a fresh character.
function NoSitting.Guard(character: Model)
	task.spawn(function()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			local found = character:WaitForChild("Humanoid", 10)
			humanoid = if found and found:IsA("Humanoid") then found else nil
		end
		if not humanoid then
			return
		end
		local guarded = humanoid :: Humanoid
		guarded:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
		local function stand()
			if guarded.Sit then
				guarded.Sit = false
			end
		end
		stand()
		guarded:GetPropertyChangedSignal("Sit"):Connect(stand)
	end)
end

return NoSitting
