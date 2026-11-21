-- Kit d'interface RELIC RUSH : bleu nuit, violet, or ; coins arrondis, contours dores, animations.
local TweenService = game:GetService("TweenService")

local UI = {}

UI.C = {
	Navy = Color3.fromRGB(18, 20, 52),
	Navy2 = Color3.fromRGB(30, 30, 80),
	Purple = Color3.fromRGB(110, 60, 200),
	Purple2 = Color3.fromRGB(70, 35, 140),
	Gold = Color3.fromRGB(255, 200, 60),
	Gold2 = Color3.fromRGB(230, 150, 30),
	Text = Color3.fromRGB(255, 250, 240),
	Sub = Color3.fromRGB(185, 180, 225),
	Green = Color3.fromRGB(90, 210, 100),
	Red = Color3.fromRGB(235, 80, 90),
	Blue = Color3.fromRGB(70, 160, 255),
	Dark = Color3.fromRGB(20, 12, 35),
}
local C = UI.C
UI.Font = Enum.Font.FredokaOne

-- cles de configuration propres au kit (pas des proprietes Roblox)
local CUSTOM = { Stroke = true, StrokeThickness = true, Radius = true }

function UI.new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do
		if not CUSTOM[k] then
			o[k] = v
		end
	end
	if parent then
		o.Parent = parent
	end
	return o
end

function UI.corner(o, r)
	return UI.new("UICorner", { CornerRadius = UDim.new(0, r or 14) }, o)
end

function UI.stroke(o, color, t, transp)
	return UI.new("UIStroke", { Color = color or C.Gold, Thickness = t or 3, Transparency = transp or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
end

function UI.gradient(o, a, b, rot)
	return UI.new("UIGradient", { Color = ColorSequence.new(a, b), Rotation = rot or 90 }, o)
end

function UI.pad(o, p)
	return UI.new("UIPadding", { PaddingTop = UDim.new(0, p), PaddingBottom = UDim.new(0, p), PaddingLeft = UDim.new(0, p), PaddingRight = UDim.new(0, p) }, o)
end

-- Panneau : degrade bleu nuit -> violet, contour dore
function UI.panel(props, parent, flat)
	local f = UI.new("Frame", props, parent)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = props.BackgroundColor3 or Color3.new(1, 1, 1)
	UI.corner(f, props.Radius or 18)
	if not flat then
		UI.gradient(f, C.Navy2, C.Navy, 90)
		UI.stroke(f, C.Gold, 3)
	end
	return f
end

-- Carte interieure (plus sombre)
function UI.card(props, parent, color)
	local f = UI.new("Frame", props, parent)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color or C.Purple2
	UI.corner(f, props.Radius or 14)
	UI.gradient(f, Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 200), 90)
	UI.stroke(f, Color3.fromRGB(255, 255, 255), 2, 0.75)
	return f
end

function UI.text(props, parent)
	local t = UI.new("TextLabel", props, parent)
	t.BackgroundTransparency = 1
	t.Font = props.Font or UI.Font
	t.TextColor3 = props.TextColor3 or C.Text
	if props.TextSize == nil then
		t.TextScaled = true
	end
	if props.Stroke ~= false then
		UI.new("UIStroke", { Color = C.Dark, Thickness = props.StrokeThickness or 2, Transparency = 0.1 }, t)
	end
	return t
end

-- Bouton 3D (degrade + ombre portee + rebond)
function UI.button(props, parent, color)
	color = color or C.Gold
	local holder = UI.new("Frame", { Size = props.Size, Position = props.Position, AnchorPoint = props.AnchorPoint or Vector2.zero, BackgroundTransparency = 1, LayoutOrder = props.LayoutOrder or 0, ZIndex = props.ZIndex or 1 }, parent)
	local shadow = UI.new("Frame", { Size = UDim2.new(1, 0, 1, 0), Position = UDim2.fromOffset(0, 4), BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.45), BorderSizePixel = 0, ZIndex = holder.ZIndex }, holder)
	UI.corner(shadow, props.Radius or 12)
	local b = UI.new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BorderSizePixel = 0, AutoButtonColor = false, Text = props.Text or "", Font = UI.Font, TextScaled = true, TextColor3 = props.TextColor3 or Color3.new(1, 1, 1), ZIndex = holder.ZIndex + 1 }, holder)
	UI.corner(b, props.Radius or 12)
	UI.gradient(b, color:Lerp(Color3.new(1, 1, 1), 0.25), color:Lerp(Color3.new(0, 0, 0), 0.1), 90)
	UI.new("UIStroke", { Color = C.Dark, Thickness = 2, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	UI.new("UIStroke", { Color = C.Dark, Thickness = 2, Transparency = 0.1 }, b)
	UI.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5) }, b)
	local scale = UI.new("UIScale", {}, holder)
	b.MouseEnter:Connect(function()
		UI.tween(scale, 0.12, { Scale = 1.05 })
	end)
	b.MouseLeave:Connect(function()
		UI.tween(scale, 0.12, { Scale = 1 })
	end)
	b.MouseButton1Down:Connect(function()
		UI.tween(scale, 0.06, { Scale = 0.93 })
	end)
	b.MouseButton1Up:Connect(function()
		UI.tween(scale, 0.12, { Scale = 1.05 })
	end)
	holder:SetAttribute("Button", true)
	return b, holder
end

function UI.setButtonColor(b, color)
	b.BackgroundColor3 = color
	local g = b:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.25), color:Lerp(Color3.new(0, 0, 0), 0.1))
	end
	local shadow = b.Parent:FindFirstChildWhichIsA("Frame")
	if shadow then
		shadow.BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.45)
	end
end

function UI.tween(o, t, props, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

function UI.bar(props, parent, color)
	local back = UI.new("Frame", props, parent)
	back.BackgroundColor3 = C.Dark
	back.BorderSizePixel = 0
	UI.corner(back, 99)
	UI.new("UIStroke", { Color = C.Dark, Thickness = 2 }, back)
	local fill = UI.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = color or C.Green, BorderSizePixel = 0, ZIndex = back.ZIndex }, back)
	UI.corner(fill, 99)
	UI.gradient(fill, (color or C.Green):Lerp(Color3.new(1, 1, 1), 0.3), color or C.Green, 90)
	return back, function(r, instant)
		r = math.clamp(r, 0, 1)
		if instant then
			fill.Size = UDim2.fromScale(r, 1)
		else
			UI.tween(fill, 0.2, { Size = UDim2.fromScale(r, 1) })
		end
	end, fill
end

function UI.list(parent, padding, horizontal)
	return UI.new("UIListLayout", { Padding = UDim.new(0, padding or 8), FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder }, parent)
end

function UI.scroll(props, parent)
	local s = UI.new("ScrollingFrame", props, parent)
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.ScrollBarThickness = 8
	s.ScrollBarImageColor3 = C.Gold
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.CanvasSize = UDim2.new()
	return s
end

return UI
