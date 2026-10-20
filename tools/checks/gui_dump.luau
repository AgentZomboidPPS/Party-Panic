-- Snapshot of a player's on-screen UI for tools/checks/ui_render.py (used by round_harness.py and
-- client_harness.py). Records every GuiObject and the UI modifiers that affect its layout.
function __dumpGui(playerGui)
	local nodes = {}
	local function color(c)
		return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
	end
	local function udim2(u)
		return { u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset }
	end
	local function udim(u)
		return { u.Scale, u.Offset }
	end
	local function describe(inst, parentId)
		local e = { c = inst.ClassName, n = inst.Name, p = parentId }
		if inst:IsA("ScreenGui") then
			e.order = inst.DisplayOrder
			e.inset = not inst.IgnoreGuiInset
			e.enabled = inst.Enabled
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
			e.touchSlot = inst:GetAttribute("TouchSlot")
			e.underProfile = inst:GetAttribute("PP_UnderProfile")
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
			end
			if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
				e.img = inst.Image
				e.ic = color(inst.ImageColor3)
				e.it = inst.ImageTransparency
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
		elseif inst:IsA("UIListLayout") then
			e.dir = inst.FillDirection.Name
			e.pad = udim(inst.Padding)
			e.ha = inst.HorizontalAlignment.Name
			e.va = inst.VerticalAlignment.Name
			e.sort = inst.SortOrder.Name
		elseif inst:IsA("UIPadding") then
			e.pad = { udim(inst.PaddingLeft), udim(inst.PaddingRight), udim(inst.PaddingTop), udim(inst.PaddingBottom) }
		elseif inst:IsA("UIAspectRatioConstraint") then
			e.ratio = inst.AspectRatio
		else
			return nil
		end
		return e
	end
	local function visit(inst, parentId)
		local ok, entry = pcall(describe, inst, parentId)
		if ok and entry then
			table.insert(nodes, entry)
			local id = #nodes
			for _, child in inst:GetChildren() do
				visit(child, id)
			end
		end
	end
	for _, gui in playerGui:GetChildren() do
		visit(gui, 0)
	end
	return nodes
end
