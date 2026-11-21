-- Petits outils d'interface : creation d'objets, coins arrondis, contours, animations.
local TweenService = game:GetService("TweenService")

local UI = {}

UI.Colors = {
	Panel = Color3.fromRGB(18, 26, 40),
	Panel2 = Color3.fromRGB(28, 40, 60),
	Line = Color3.fromRGB(70, 95, 130),
	Text = Color3.fromRGB(240, 244, 250),
	Sub = Color3.fromRGB(160, 175, 200),
	Sky = Color3.fromRGB(90, 180, 255),
	Post = Color3.fromRGB(255, 170, 60),
	Gold = Color3.fromRGB(255, 205, 80),
	Good = Color3.fromRGB(100, 220, 140),
	Bad = Color3.fromRGB(240, 90, 90),
}

function UI.new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end

function UI.corner(o, r)
	return UI.new("UICorner", { CornerRadius = UDim.new(0, r or 12) }, o)
end

function UI.stroke(o, color, t, transp)
	return UI.new("UIStroke", { Color = color or UI.Colors.Line, Thickness = t or 1.5, Transparency = transp or 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
end

function UI.pad(o, p)
	return UI.new("UIPadding", { PaddingTop = UDim.new(0, p), PaddingBottom = UDim.new(0, p), PaddingLeft = UDim.new(0, p), PaddingRight = UDim.new(0, p) }, o)
end

function UI.gradient(o, a, b, rot)
	return UI.new("UIGradient", { Color = ColorSequence.new(a, b), Rotation = rot or 90 }, o)
end

-- Panneau sombre semi-transparent, style "verre"
function UI.panel(props, parent)
	local f = UI.new("Frame", props, parent)
	f.BackgroundColor3 = props.BackgroundColor3 or UI.Colors.Panel
	f.BackgroundTransparency = props.BackgroundTransparency or 0.12
	f.BorderSizePixel = 0
	UI.corner(f, 14)
	UI.stroke(f, UI.Colors.Line, 1.5, 0.35)
	return f
end

function UI.text(props, parent)
	local t = UI.new("TextLabel", props, parent)
	t.BackgroundTransparency = 1
	t.Font = props.Font or Enum.Font.GothamBold
	t.TextColor3 = props.TextColor3 or UI.Colors.Text
	if props.TextSize == nil then
		t.TextScaled = true
	end
	return t
end

function UI.button(props, parent, color)
	local b = UI.new("TextButton", props, parent)
	b.AutoButtonColor = false
	b.BackgroundColor3 = color or UI.Colors.Sky
	b.BorderSizePixel = 0
	b.Font = props.Font or Enum.Font.GothamBold
	b.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	if props.TextSize == nil then
		b.TextScaled = true
	end
	UI.corner(b, props.Radius or 10)
	UI.gradient(b, Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 210), 90)
	local scale = UI.new("UIScale", {}, b)
	b.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.05 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	b.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.94 }):Play()
	end)
	b.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1.05 }):Play()
	end)
	return b
end

function UI.tween(o, t, props, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- Barre de progression ; renvoie (cadre, fonction set(ratio))
function UI.bar(props, parent, color)
	local back = UI.new("Frame", props, parent)
	back.BackgroundColor3 = Color3.fromRGB(10, 15, 25)
	back.BackgroundTransparency = 0.2
	back.BorderSizePixel = 0
	UI.corner(back, 99)
	local fill = UI.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = color or UI.Colors.Sky, BorderSizePixel = 0 }, back)
	UI.corner(fill, 99)
	UI.gradient(fill, Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 200), 90)
	return back, function(r, instant)
		r = math.clamp(r, 0, 1)
		if instant then
			fill.Size = UDim2.fromScale(r, 1)
		else
			UI.tween(fill, 0.35, { Size = UDim2.fromScale(r, 1) })
		end
	end, fill
end

return UI
