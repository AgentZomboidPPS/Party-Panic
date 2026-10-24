-- Vibration for the moments that matter (owner: "I want playing on mobile to feel really good."): a
-- light tap when a mode's action button goes down, a pulse at GO and for a win, a thud when you're
-- knocked out. Phones only (Roblox's HapticEffect, on phones that can buzz); anywhere else, or where
-- the engine has no HapticEffect, it's quietly nothing. Off with Settings' 📳 Vibration (phones).
--
--   Haptics.Play("Tap" | "Pulse" | "Thud")

local UserInputService = game:GetService("UserInputService")

local State = require(script.Parent.State)

local Haptics = {}

export type Kind = "Tap" | "Pulse" | "Thud"

local TYPES: { [Kind]: string } = { Tap = "UIClick", Pulse = "UINotification", Thud = "GameplayCollision" }

local effects: { [Kind]: any } = {} -- one HapticEffect a kind, made the first time (false: can't)

local function effectFor(kind: Kind): any
	local effect = effects[kind]
	if effect == nil then
		local ok, made = pcall(function()
			local instance = (Instance.new :: any)("HapticEffect")
			instance.Type = (Enum :: any).HapticEffectType[TYPES[kind]]
			instance.Parent = workspace
			return instance
		end)
		effect = if ok then made else false
		effects[kind] = effect
	end
	return if effect then effect else nil
end

-- Whether this device buzzes for the game: a phone, with the setting on.
function Haptics.Enabled(): boolean
	return UserInputService.TouchEnabled and State.Setting("Vibration") ~= false
end

function Haptics.Play(kind: Kind)
	if not Haptics.Enabled() then
		return
	end
	local effect = effectFor(kind)
	if effect then
		pcall(effect.Play, effect)
	end
end

return Haptics
