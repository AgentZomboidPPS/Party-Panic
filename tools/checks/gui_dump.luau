-- Snapshot of a player's on-screen UI for tools/checks/ui_render.py (used by round_harness.py and
-- client_harness.py). Records every GuiObject and the UI modifiers that affect its layout, and
-- measures each text with the engine's own fonts (TextService), so the renderer wraps, fits and
-- truncates text like Roblox does (its stand-in fonts are much wider than Builder Sans).
--
-- With __devices (a list of screens, written by the harness from ui_render.py's SIZES), it also
-- lays the UI out with the ENGINE for each screen: a server lays out GUIs inside SurfaceGuis with
-- Roblox's own layout and text code, so each ScreenGui's contents are cloned into a SurfaceGui the
-- size of that screen (into a frame for the ScreenGui's safe area), the parts that depend on the
-- screen size are redone for it (UIKit.AutoScale scales, windows shrunk to fit, buttons beside the
-- jump button), and every visible object's real position and size, and every text's real
-- measurements, are recorded:
--     e.L[screen] = { x, y, w, h }  or for text  { x, y, w, h, textW, textH, fits, px, lines, needW, needH }
-- Fonts are loaded first: a label laid out before its font has loaded keeps a fallback font's
-- (narrower) measurements for good, which is how text cut off on phones used to pass these checks.
--
-- Kept small (Open Cloud refuses a task result over 4 MB, and a phone run of the client harness
-- reached 6 MB): a snapshot records only what's on screen (a hidden object, a switched-off screen,
-- stroke or gradient, and everything inside them, are left out: that was most of the UI, every
-- closed window), numbers are rounded to 3 decimals, and a value most objects of a class share is
-- left out of their entries (__uiDefaults: the harnesses return it beside the snapshots as
-- "uiDefaults", and ui_render.py fills those values back in).

local __fontsLoaded = {}
local function __loadFonts(root)
	local TextService = game:GetService("TextService")
	local fonts = { [Enum.Font.BuilderSans] = true }
	for _, item in root:GetDescendants() do
		if item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox") then
			fonts[item.Font] = true
		end
	end
	for font in fonts do
		if not __fontsLoaded[font] then
			__fontsLoaded[font] = true
			local params = Instance.new("GetTextBoundsParams")
			params.Text = "Ag 0 🎉🗳️🪙"
			params.Font = Font.fromEnum(font)
			params.Size = 20
			params.Width = 1e5
			pcall(TextService.GetTextBoundsAsync, TextService, params)
		end
	end
end

-- UIKit.ScaleFor when the harness provides it (__uiScaleFor), else the same rule with its numbers.
local function __autoScale(width, height, bias)
	if __uiScaleFor then
		return __uiScaleFor(Vector2.new(width, height), bias)
	end
	return math.clamp(math.min(width / 1280, height / 720) * (bias or 1), 0.62, 1.35)
end

-- The area a ScreenGui's contents get on a screen (left, top, width, height).
local function __screenArea(gui, device)
	local insets = gui.ScreenInsets
	if insets == Enum.ScreenInsets.None or (gui.IgnoreGuiInset and insets == Enum.ScreenInsets.CoreUISafeInsets) then
		return 0, 0, device.w, device.h
	elseif insets == Enum.ScreenInsets.DeviceSafeInsets then
		return device.l, 0, device.w - device.l - device.r, device.h - device.b
	elseif insets == Enum.ScreenInsets.TopbarSafeInsets then
		return device.bar, 0, device.w - device.r - 12 - device.bar, device.t
	end
	return device.l, device.t, device.w - device.l - device.r, device.h - device.t - device.b
end

local function __engineLayout(playerGui, entries)
	local TextService = game:GetService("TextService")
	__loadFonts(playerGui)
	local folder = Instance.new("Folder")
	folder.Name = "__EngineLayout"
	folder.Parent = workspace
	local copies = {} -- [device name] = { [original] = copy }
	local areas = {} -- [device name] = { [copy] = true } (the ScreenGui frames)
	for index, device in __devices do
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.Transparency = 1
		part.Size = Vector3.new(device.w / 20, device.h / 20, 1)
		part.CFrame = CFrame.new(index * 200, -2000, 0)
		part.Parent = folder
		local surface = Instance.new("SurfaceGui")
		surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		surface.CanvasSize = Vector2.new(device.w, device.h)
		surface.Adornee = part
		surface.Parent = folder
		local map = {}
		local frames = {}
		local function pair(original, copy)
			map[original] = copy
			local a, b = original:GetChildren(), copy:GetChildren()
			for i, child in a do
				local other = b[i]
				if other and other.Name == child.Name and other.ClassName == child.ClassName then
					pair(child, other)
				end
			end
		end
		for _, gui in playerGui:GetChildren() do
			if gui:IsA("ScreenGui") and gui.Enabled then
				local x, y, w, h = __screenArea(gui, device)
				local area = Instance.new("Frame")
				area.Name = gui.Name
				area.BackgroundTransparency = 1
				area.Position = UDim2.fromOffset(x, y)
				area.Size = UDim2.fromOffset(w, h)
				area.ZIndex = gui.DisplayOrder + 1
				area.Parent = surface
				frames[area] = Vector2.new(w, h)
				map[gui] = area
				for _, child in gui:GetChildren() do
					local ok, copy = pcall(child.Clone, child)
					if ok and copy then
						pair(child, copy)
						copy.Parent = area
					end
				end
			end
		end
		-- Redo what depends on the screen size for this screen, like the client code does.
		for area, size in frames do
			for _, item in area:GetDescendants() do
				if item:IsA("UIScale") and item:GetAttribute("AutoScale") then
					item.Scale = __autoScale(device.w, device.h, item:GetAttribute("AutoScale"))
				end
			end
			for _, item in area:GetDescendants() do
				if not item:IsA("GuiObject") then
					continue
				end
				local own = item:FindFirstChildOfClass("UIScale")
				local scale = if own then own.Scale else 1
				local fit = item:GetAttribute("PP_Fit") -- UI/Modal: a window shrinks to fit the screen
				if typeof(fit) == "Vector2" then
					item.Size = UDim2.fromOffset(
						math.min(fit.X, (size.X - 2 * 8) / scale),
						math.min(fit.Y, (size.Y - 2 * 8) / scale)
					)
				end
				-- Api.Button on touch screens: beside the jump button (its holder sits on the screen
				-- area, so the jump button's screen spot is moved into the area's coordinates).
				local slot = item:GetAttribute("TouchSlot")
				if slot and device.touch and frames[item.Parent] then
					local area = item.Parent :: Frame
					local jx, jy, js = device.jump[1], device.jump[2], device.jump[3]
					local left = jx - area.Position.X.Offset
					local centerY = jy + js / 2 - area.Position.Y.Offset
					local width = 118 * scale
					item.Position = UDim2.fromOffset(left - 12 - (slot - 1) * (width + 12), centerY - js * 0.15)
				end
				-- NotificationController on touch screens during a round: the toasts sit above the mode's
				-- action buttons (their row beside the jump button, as placed just above).
				if item:GetAttribute("PP_AboveActions") and device.touch and frames[item.Parent] then
					local area = item.Parent :: Frame
					local jy, js = device.jump[2], device.jump[3]
					local centerY = jy + js / 2 - area.Position.Y.Offset
					local top = centerY - js * 0.15 - 118 * __autoScale(device.w, device.h, 1) / 2
					item.Position = UDim2.new(item.Position.X.Scale, item.Position.X.Offset, 0, top - 8)
				end
				-- RoundController's standings on PC: under the profile card (104 tall at y 12, scaled).
				if item:GetAttribute("PP_UnderProfile") then
					item.Position = UDim2.fromOffset(14, 12 + 104 * __autoScale(device.w, device.h, 1) + 8)
				end
			end
		end
		copies[device.n] = map
		areas[device.n] = frames
	end
	task.wait()
	task.wait()
	task.wait()
	-- A copy's scroll starts at the top (its canvas wasn't laid out when it was made): now that it
	-- is, each scrolling frame goes to the same place as the original. Scroll positions are screen
	-- pixels, so they're scaled by the copy's UIScales over the original's (the harness's own GUI is
	-- never laid out, so its scales are what it has to go by).
	local function scaleOf(item: Instance): number
		local k = 1
		local node: Instance? = item
		while node and not node:IsA("LayerCollector") do
			for _, child in node:GetChildren() do
				if child:IsA("UIScale") then
					k *= child.Scale -- (UI/Modal's window has two: its screen's scale and the pop-in's)
				end
			end
			node = node.Parent
		end
		return k
	end
	for _, map in copies do
		for original, copy in map do
			if original:IsA("ScrollingFrame") and copy:IsA("ScrollingFrame") then
				local from = scaleOf(original)
				copy.CanvasPosition = original.CanvasPosition * (if from > 0 then scaleOf(copy) / from else 1)
			end
		end
	end
	task.wait()
	-- A list the harness scrolled to its end (PP_ScrollToEnd) is scrolled to the end of this
	-- screen's canvas once it has been laid out (the engine keeps the position inside the canvas).
	local scrolled = false
	for _, frames in areas do
		for area in frames do
			for _, item in area:GetDescendants() do
				if item:IsA("ScrollingFrame") and item:GetAttribute("PP_ScrollToEnd") then
					item.CanvasPosition = Vector2.new(0, 100000)
					scrolled = true
				end
			end
		end
	end
	if scrolled then
		task.wait()
		task.wait()
	end

	local lineHeights = {}
	local function lineHeight(font)
		if not lineHeights[font] then
			local ok, two = pcall(TextService.GetTextSize, TextService, "A\nA", 100, font, Vector2.new(1e5, 1e5))
			lineHeights[font] = if ok then two.Y / 200 else 1
		end
		return lineHeights[font]
	end
	-- Text is laid out at its own TextSize in the unscaled box and then drawn scaled (UIScale), so
	-- it's measured that way too.
	local function measure(text, size, font, width)
		local ok, bounds =
			pcall(TextService.GetTextSize, TextService, text, size, font, Vector2.new(math.max(1, width), 1e5))
		return if ok then bounds else Vector2.zero
	end
	local function round(value)
		return math.floor(value * 10 + 0.5) / 10
	end
	for _, device in __devices do
		local map = copies[device.n]
		for _, entry in entries do
			local original, e = entry[1], entry[2]
			local copy = map[original]
			if not copy or not copy:IsA("GuiObject") then
				continue
			end
			local position, size = copy.AbsolutePosition, copy.AbsoluteSize
			local record = { round(position.X), round(position.Y), round(size.X), round(size.Y) }
			if copy:IsA("TextLabel") or copy:IsA("TextButton") or copy:IsA("TextBox") then
				-- The scale the text is drawn at (every UIScale above it).
				local k = 1
				local node = copy
				while node and not areas[device.n][node] do
					local uiScale = node:FindFirstChildOfClass("UIScale")
					if uiScale then
						k *= uiScale.Scale
					end
					node = node.Parent
				end
				local text = copy.Text
				if copy.RichText then
					text = text:gsub("<[^>]+>", "")
				end
				local boxW, boxH = size.X / k, size.Y / k
				local textSize = copy.TextSize
				local wraps = copy.TextWrapped or copy.TextScaled
				if copy.TextScaled then
					-- The biggest size that fits, within the UITextSizeConstraint (TextScaled's rule).
					local limits = copy:FindFirstChildOfClass("UITextSizeConstraint")
					local high = math.min(100, if limits then limits.MaxTextSize else 100)
					local low = math.max(1, if limits then limits.MinTextSize else 1)
					textSize = low
					for candidate = high, low, -1 do
						local bounds = measure(text, candidate, copy.Font, boxW)
						if bounds.X <= boxW + 0.5 and bounds.Y <= boxH + 0.5 then
							textSize = candidate
							break
						end
					end
				end
				local px = textSize * k
				local need = measure(text, textSize, copy.Font, if wraps then boxW else 1e5) * k
				local bounds = copy.TextBounds
				local lines = math.max(1, math.floor(need.Y / math.max(1, px * lineHeight(copy.Font)) + 0.5))
				table.insert(record, round(bounds.X))
				table.insert(record, round(bounds.Y))
				table.insert(record, if copy.TextFits then 1 else 0)
				table.insert(record, round(px))
				table.insert(record, if text == "" then 0 else lines)
				table.insert(record, round(need.X))
				table.insert(record, round(need.Y))
				-- The plain list in the results (ui_render.py reports these and more, with paths).
				local problem = nil
				if text:match("%S") and copy.TextTransparency < 0.9 then
					if not copy.TextFits then
						if copy.TextTruncate == Enum.TextTruncate.None then
							problem =
								`cut off (needs {math.ceil(need.X)}x{math.ceil(need.Y)}, has {math.floor(size.X)}x{math.floor(
									size.Y
								)})`
						elseif not copy:GetAttribute("PP_TruncateOk") then -- a long name may end in "..."
							problem = "truncated"
						end
					elseif copy.TextScaled and device.touch and px < 11 then
						problem = `scaled down to {round(px)} pt`
					end
				end
				if problem and __textReport and #__textReport < 400 then
					local where = original:GetFullName():gsub("^.-PlayerGui%.", "")
					table.insert(__textReport, `{__dumpLabel or "?"} {device.n}: {where} "{text:sub(1, 40)}" {problem}`)
				end
			end
			e.L = e.L or {}
			e.L[device.n] = record
		end
	end
	folder:Destroy()
end

-- The values left out of snapshot entries, by class (keys as describe() below writes them).
local __guiDefaults = {
	vis = true,
	pos = { 0, 0, 0, 0 },
	anchor = { 0, 0 },
	bgt = 1,
	z = 1,
	lo = 0,
	rot = 0,
	autosize = "None",
	clip = false,
}
local __textDefaults = {
	tc = { 255, 255, 255 },
	scaled = false,
	wrap = false,
	font = "BuilderSansExtraBold",
	xa = "Center",
	ya = "Center",
	tt = 0,
	st = 1,
	trunc = "None",
}
local function __merged(...)
	local out = {}
	for _, part in { ... } do
		for key, value in part do
			out[key] = value
		end
	end
	return out
end
__uiDefaults = {
	ScreenGui = { enabled = true, inset = true, insets = "CoreUISafeInsets", order = 0 },
	Frame = __guiDefaults,
	ScrollingFrame = __merged(__guiDefaults, { cpos = { 0, 0 }, autocanvas = "None" }),
	ImageLabel = __merged(__guiDefaults, { ic = { 255, 255, 255 }, it = 0 }),
	ImageButton = __merged(__guiDefaults, { ic = { 255, 255, 255 }, it = 0 }),
	TextLabel = __merged(__guiDefaults, __textDefaults),
	TextButton = __merged(__guiDefaults, __textDefaults),
	TextBox = __merged(__guiDefaults, __textDefaults),
	UIScale = { scale = 1 },
	UIStroke = { enabled = true, mode = "Contextual", thick = 2 },
	UIGradient = { rot = 90 },
	UIListLayout = { dir = "Vertical", ha = "Center", va = "Top", sort = "LayoutOrder" },
}
local function __same(a, b)
	if type(a) == "table" and type(b) == "table" then
		if #a ~= #b then
			return false
		end
		for index, value in a do
			if not __same(value, b[index]) then
				return false
			end
		end
		return true
	end
	return a == b
end
-- Numbers to 3 decimals (properties are 32-bit floats: 0.62 reads 0.6200000047683716).
local function __tidy(value)
	if type(value) == "number" then
		return math.floor(value * 1000 + 0.5) / 1000
	elseif type(value) == "table" then
		local out = {}
		for key, item in value do
			out[key] = __tidy(item)
		end
		return out
	end
	return value
end

__textReport = {} -- "<snapshot> <screen>: <path> "<text>" <problem>" for every text that doesn't fit
function __dumpGui(playerGui, label)
	__dumpLabel = label
	local TextService = game:GetService("TextService")
	__loadFonts(playerGui)
	local nodes = {}
	local shown = {} -- { original, entry } for every object that's on screen
	local widths = {} -- [font][word] = width at TextSize 100
	local function color(c)
		return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
	end
	local function udim2(u)
		return { u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset }
	end
	local function udim(u)
		return { u.Scale, u.Offset }
	end
	local function measure(font, text)
		local cache = widths[font]
		if not cache then
			cache = {}
			widths[font] = cache
		end
		if cache[text] == nil then
			local ok, size = pcall(TextService.GetTextSize, TextService, text, 100, font, Vector2.new(1e5, 1e5))
			cache[text] = if ok then size.X else false
		end
		return cache[text]
	end
	-- Word widths per paragraph, the width of a space and the line height, all at TextSize 100.
	local function measureText(e, inst)
		local text = inst.Text
		if inst.RichText then
			text = text:gsub("<[^>]+>", "")
		end
		local paragraphs = {}
		for _, paragraph in string.split(text, "\n") do
			local words = {}
			for _, word in string.split(paragraph, " ") do
				local width = if word == "" then 0 else measure(inst.Font, word)
				if width == false then
					return
				end
				table.insert(words, width)
			end
			table.insert(paragraphs, words)
		end
		local space = measure(inst.Font, "a a")
		local pair = measure(inst.Font, "aa")
		local ok, twoLines = pcall(TextService.GetTextSize, TextService, "A\nA", 100, inst.Font, Vector2.new(1e5, 1e5))
		if space and pair and ok then
			e.tw = paragraphs
			e.sw = space - pair
			e.lh = twoLines.Y / 200
		end
	end
	local function describe(inst, parentId)
		local e = { c = inst.ClassName, n = inst.Name, p = parentId }
		if inst:IsA("ScreenGui") then
			e.order = inst.DisplayOrder
			e.inset = not inst.IgnoreGuiInset
			e.insets = inst.ScreenInsets.Name
			e.enabled = inst.Enabled
			e.billboards = inst:GetAttribute("PP_Billboards") -- 3D name tags copied onto a screen to draw them
			e.noTouch = inst:GetAttribute("PP_NoTouchControls") -- the MOVE stick and jump button are put away
		elseif inst:IsA("GuiObject") then
			e.vis = inst.Visible
			e.pos = udim2(inst.Position)
			e.size = udim2(inst.Size)
			e.anchor = { inst.AnchorPoint.X, inst.AnchorPoint.Y }
			e.bg = color(inst.BackgroundColor3)
			e.bgt = inst.BackgroundTransparency
			e.z = inst.ZIndex
			e.lo = inst.LayoutOrder
			e.rot = inst.Rotation
			e.autosize = inst.AutomaticSize.Name
			e.clip = inst.ClipsDescendants
			e.touchSlot = inst:GetAttribute("TouchSlot")
			e.underProfile = inst:GetAttribute("PP_UnderProfile")
			e.aboveActions = inst:GetAttribute("PP_AboveActions")
			e.lines = inst:GetAttribute("PP_Lines") -- text allowed to wrap onto this many lines
			e.truncOk = inst:GetAttribute("PP_TruncateOk") -- a name that may be shortened with "..."
			e.popup = inst:GetAttribute("PP_Popup") -- a picker shown on request (may cover the thumbstick)
			e.glint = inst:GetAttribute("PP_Glint") -- a shine band that slides past now and then (not a fill)
			local fit = inst:GetAttribute("PP_Fit") -- UI/Modal: a window shrunk to fit the screen
			if typeof(fit) == "Vector2" then
				e.fit = { fit.X, fit.Y }
			end
			if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
				e.text = inst.Text
				e.tc = color(inst.TextColor3)
				e.ts = inst.TextSize
				e.scaled = inst.TextScaled
				e.wrap = inst.TextWrapped
				e.font = inst.Font.Name
				e.xa = inst.TextXAlignment.Name
				e.ya = inst.TextYAlignment.Name
				e.tt = inst.TextTransparency
				e.st = inst.TextStrokeTransparency
				e.trunc = inst.TextTruncate.Name
				pcall(measureText, e, inst)
			end
			if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
				e.img = inst.Image
				e.ic = color(inst.ImageColor3)
				e.it = inst.ImageTransparency
				if inst.ImageRectSize.X > 0 then
					-- (a cell of a sheet: ui_render.py draws just that part of a local copy)
					e.irect =
						{ inst.ImageRectOffset.X, inst.ImageRectOffset.Y, inst.ImageRectSize.X, inst.ImageRectSize.Y }
				end
			end
			if inst:IsA("ScrollingFrame") then
				e.canvas = udim2(inst.CanvasSize)
				e.cpos = { inst.CanvasPosition.X, inst.CanvasPosition.Y }
				e.autocanvas = inst.AutomaticCanvasSize.Name
				e.clip = true
			end
		elseif inst:IsA("UIScale") then
			e.scale = inst.Scale
			e.auto = inst:GetAttribute("AutoScale")
		elseif inst:IsA("UICorner") then
			e.radius = udim(inst.CornerRadius)
		elseif inst:IsA("UIStroke") then
			e.color = color(inst.Color)
			e.thick = inst.Thickness
			e.t = inst.Transparency
			e.mode = inst.ApplyStrokeMode.Name
			e.enabled = inst.Enabled
		elseif inst:IsA("UIGradient") then
			local keys = inst.Color.Keypoints
			e.c0 = color(keys[1].Value)
			e.c1 = color(keys[#keys].Value)
			e.rot = inst.Rotation
			-- More than two colours (a rainbow), see-through parts (a shine, a countdown ring's hard
			-- edge) and a moved gradient (a sweeping shine), when there are any.
			if #keys > 2 then
				local list = {}
				for _, key in keys do
					local rgb = color(key.Value)
					table.insert(list, { key.Time, rgb[1], rgb[2], rgb[3] })
				end
				e.cs = list
			end
			local fades = inst.Transparency.Keypoints
			local seeThrough = false
			for _, key in fades do
				seeThrough = seeThrough or key.Value > 0.001
			end
			if seeThrough then
				local list = {}
				for _, key in fades do
					table.insert(list, { key.Time, key.Value })
				end
				e.ts = list
			end
			if inst.Offset.Magnitude > 0.0001 then
				e.off = { inst.Offset.X, inst.Offset.Y }
			end
		elseif inst:IsA("UIListLayout") then
			e.dir = inst.FillDirection.Name
			e.pad = udim(inst.Padding)
			e.ha = inst.HorizontalAlignment.Name
			e.va = inst.VerticalAlignment.Name
			e.sort = inst.SortOrder.Name
		elseif inst:IsA("UIGridLayout") then
			e.cell = udim2(inst.CellSize)
			e.cpad = udim2(inst.CellPadding)
			e.dir = inst.FillDirection.Name
			e.ha = inst.HorizontalAlignment.Name
			e.va = inst.VerticalAlignment.Name
			e.sort = inst.SortOrder.Name
			e.maxcells = inst.FillDirectionMaxCells
		elseif inst:IsA("UIPadding") then
			e.pad = { udim(inst.PaddingLeft), udim(inst.PaddingRight), udim(inst.PaddingTop), udim(inst.PaddingBottom) }
		elseif inst:IsA("UIAspectRatioConstraint") then
			e.ratio = inst.AspectRatio
		elseif inst:IsA("UITextSizeConstraint") then
			e.mints = inst.MinTextSize
			e.maxts = inst.MaxTextSize
		elseif inst:IsA("UISizeConstraint") then
			e.minsz = { inst.MinSize.X, inst.MinSize.Y }
			e.maxsz = { math.min(inst.MaxSize.X, 1e6), math.min(inst.MaxSize.Y, 1e6) }
		else
			return nil
		end
		-- Rounded, and without the values most objects of its class share (__uiDefaults); a colour
		-- behind nothing (fully see-through) isn't needed either.
		for key, value in e do
			e[key] = __tidy(value)
		end
		for key, value in __uiDefaults[e.c] or {} do
			if __same(e[key], value) then
				e[key] = nil
			end
		end
		if e.bg and e.bgt == nil then
			e.bg = nil
		end
		return e
	end
	-- Only what's on screen: a hidden object, or a screen, stroke or gradient that's switched off,
	-- draws nothing and neither does anything inside it.
	local function onScreen(inst)
		if inst:IsA("GuiObject") then
			return inst.Visible
		elseif inst:IsA("ScreenGui") or inst:IsA("UIStroke") or inst:IsA("UIGradient") then
			return inst.Enabled
		end
		return true
	end
	local function visit(inst, parentId)
		if not onScreen(inst) then
			return
		end
		local ok, entry = pcall(describe, inst, parentId)
		if ok and entry then
			table.insert(nodes, entry)
			local id = #nodes
			if inst:IsA("GuiObject") then
				table.insert(shown, { inst, entry })
			end
			for _, child in inst:GetChildren() do
				visit(child, id)
			end
		end
	end
	for _, gui in playerGui:GetChildren() do
		visit(gui, 0)
	end
	if __devices and #__devices > 0 then
		local ok, err = pcall(__engineLayout, playerGui, shown)
		if not ok then
			warn("[gui_dump] engine layout failed: " .. tostring(err))
		end
	end
	return nodes
end
