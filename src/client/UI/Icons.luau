-- Party Panic's own icons (owner, with a guide to what gives an AI-made game away, where emoji as
-- icons is "THE BIG ONE": "Can we fix these issues?"): little toys modelled and lit for the game
-- (tools/art/ui_art.py, on Shared/UiArt's sheet) in place of the emoji the screens used to show.
--
-- A label or button made by UIKit whose text starts with one of those emoji ("🏆 Winner", "💡
-- SUGGESTION BOX") shows the picture in its place, sized to its text and lined up with it however
-- the text is aligned (Icons.Decorate; later text keeps it up to date). Anything else can ask for a
-- picture by name or by emoji (Icons.Image, Icons.Apply). Until the sheet is uploaded
-- (UiArt.Icons == "") everything keeps its emoji.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local UiArt = require(ReplicatedStorage.Shared.UiArt)

local Icons = {}

local SELECTOR = utf8.char(0xFE0F) -- (the emoji-style variation selector some text carries)
local SCALE = 1.3 -- the picture's size for text this size (its cell has a clear margin round the toy)
local GAP = 0.22 -- the space between picture and words, for text this size

-- The emoji, longest first (so a longer one is never mistaken for a shorter one it starts with).
local emoji = {}
for key in UiArt.Emoji do
	table.insert(emoji, key)
end
table.sort(emoji, function(a, b)
	return #a > #b
end)

local function ready(): boolean
	return UiArt.Icons ~= ""
end

-- The icon's name for a name ("Trophy") or an emoji ("🏆"); nil if there's no picture for it.
function Icons.Name(key: string?): string?
	if not key or not ready() then
		return nil
	end
	if UiArt.Cells[key] then
		return key
	end
	local bare = string.gsub(key, SELECTOR, "")
	return UiArt.Emoji[bare]
end

-- The icon a text starts with, and the rest of the text (nil and the text as it is if none).
function Icons.Split(text: string): (string?, string)
	if not ready() or text == "" then
		return nil, text
	end
	local first = string.byte(text, 1)
	if first and first < 0xC0 then
		return nil, text -- (starts with plain ASCII: no emoji)
	end
	for _, key in emoji do
		if string.sub(text, 1, #key) == key then
			local rest = string.sub(text, #key + 1)
			if string.sub(rest, 1, #SELECTOR) == SELECTOR then
				rest = string.sub(rest, #SELECTOR + 1)
			end
			return UiArt.Emoji[key], (string.gsub(rest, "^%s+", ""))
		end
	end
	return nil, text
end

-- Shows icon `key` (a name or an emoji) on an ImageLabel/ImageButton. False if there's no picture.
function Icons.Apply(image: ImageLabel, key: string?): boolean
	local name = Icons.Name(key)
	if not name then
		return false
	end
	local cell = UiArt.Cells[name]
	image.Image = UiArt.Icons
	image.ImageRectOffset = Vector2.new(cell[1] * UiArt.Cell, cell[2] * UiArt.Cell)
	image.ImageRectSize = Vector2.new(UiArt.Cell, UiArt.Cell)
	image.ScaleType = Enum.ScaleType.Fit
	return true
end

-- A new ImageLabel showing icon `key`, with `props` on it (nil if there's no picture for it).
function Icons.Image(key: string?, props: { [string]: any }?): ImageLabel?
	if not Icons.Name(key) then
		return nil
	end
	local image = Instance.new("ImageLabel")
	image.Name = "Icon"
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromOffset(32, 32)
	Icons.Apply(image, key)
	local parent = nil
	for property, value in (props or {}) :: { [string]: any } do
		if property == "Parent" then
			parent = value
		else
			(image :: any)[property] = value
		end
	end
	image.Parent = parent
	return image
end

local function textWidth(text: string, size: number, font: Enum.Font): number
	local ok, bounds = pcall(TextService.GetTextSize, TextService, text, size, font, Vector2.new(1e4, 1e4))
	return if ok then bounds.X else #text * size * 0.6
end

-- Keeps a TextLabel/TextButton's leading emoji shown as its picture: the emoji comes off the text
-- and the picture sits where it was, the words moved over to make room (a UIPadding). Text set later
-- is looked at again; text without an emoji puts the picture away.
function Icons.Decorate(object: GuiObject)
	if not ready() or object:GetAttribute("PP_Icons") then
		return
	end
	object:SetAttribute("PP_Icons", true)
	local icon: ImageLabel? = nil
	local padding: UIPadding? = nil
	local baseLeft = 0 -- the padding's own left side before the picture's room was added
	local stripped: string? = nil -- the text as this left it (so its own change isn't looked at again)
	local current: string? = nil

	local function layout()
		local image = icon
		if not image then
			return
		end
		local pad = padding :: UIPadding
		if not current then
			image.Visible = false
			pad.PaddingLeft = UDim.new(0, baseLeft)
			return
		end
		local o = object :: any
		local size = o.TextSize
		local height = o.Size.Y.Offset
		if o.TextScaled then
			size = if o.Size.Y.Scale == 0 and height > 0 then height * 0.62 else size
		end
		local side = math.floor(size * SCALE + 0.5)
		if o.TextScaled and o.Text == "" and o.Size.X.Scale == 0 and o.Size.X.Offset > 0 and height > 0 then
			side = math.floor(math.min(o.Size.X.Offset, height) * SCALE + 0.5) -- (just the picture: fill the box)
		end
		local gap = math.floor(size * GAP + 0.5)
		local room = side - math.floor(size * 0.15) + gap -- (the picture's clear margin may tuck in a little)
		image.Size = UDim2.fromOffset(side, side)
		image.ImageTransparency = o.TextTransparency
		image.ZIndex = o.ZIndex
		local right = pad.PaddingRight.Offset
		local top, bottom = pad.PaddingTop.Offset, pad.PaddingBottom.Offset
		local y = if o.TextYAlignment == Enum.TextYAlignment.Top
			then UDim.new(0, top + size * 0.55)
			elseif o.TextYAlignment == Enum.TextYAlignment.Bottom then UDim.new(1, -(bottom + size * 0.55))
			else UDim.new(0.5, (top - bottom) / 2)
		local words = if o.RichText then string.gsub(o.Text, "<[^>]+>", "") else o.Text
		local width = textWidth(words, size, o.Font)
		local box = o.Size.X.Offset
		if o.Size.X.Scale == 0 and box > 0 then
			width = math.min(width, box - baseLeft - right - room)
		end
		local x
		if words == "" then
			-- Just the picture (a close button's X): in the middle.
			x = UDim.new(0.5, (baseLeft - right - side) / 2)
			pad.PaddingLeft = UDim.new(0, baseLeft)
		elseif o.TextScaled or o.TextXAlignment == Enum.TextXAlignment.Left then
			x = UDim.new(0, baseLeft - math.floor(size * 0.08))
			pad.PaddingLeft = UDim.new(0, baseLeft + room)
		elseif o.TextXAlignment == Enum.TextXAlignment.Right then
			x = UDim.new(1, -(right + width + room))
			pad.PaddingLeft = UDim.new(0, baseLeft)
		else
			-- Centred: the picture and the words together, centred where the words were.
			x = UDim.new(0.5, (baseLeft - right - room - width) / 2 - math.floor(size * 0.08))
			pad.PaddingLeft = UDim.new(0, baseLeft + room)
		end
		image.AnchorPoint = Vector2.new(0, 0.5)
		image.Position = UDim2.new(x, y)
		image.Visible = true
	end

	local function refresh()
		local text = (object :: any).Text
		if text == stripped then
			layout()
			return
		end
		local name, rest = Icons.Split(text)
		current = name
		if name then
			if not icon then
				local room = object:FindFirstChildOfClass("UIPadding")
				if not room then
					local made = Instance.new("UIPadding")
					made.Name = "IconRoom"
					made.Parent = object
					room = made
				end
				padding = room
				baseLeft = (room :: UIPadding).PaddingLeft.Offset
				local image = Instance.new("ImageLabel")
				image.Name = "Icon"
				image.BackgroundTransparency = 1
				image.Parent = object
				icon = image
			end
			Icons.Apply(icon :: ImageLabel, name)
			stripped = rest
			local writable: any = object
			writable.Text = rest -- (its change comes back here and is left alone)
		else
			stripped = nil
		end
		layout()
	end

	local watched: any = object
	watched:GetPropertyChangedSignal("Text"):Connect(refresh)
	for _, property in { "TextSize", "Font", "TextXAlignment", "TextYAlignment", "TextTransparency", "ZIndex" } do
		object:GetPropertyChangedSignal(property):Connect(layout)
	end
	refresh()
end

return Icons
