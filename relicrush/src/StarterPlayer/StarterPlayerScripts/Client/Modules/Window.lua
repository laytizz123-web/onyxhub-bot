-- Fenetres de l'interface : une seule ouverte a la fois, en-tete avec l'icone de la planche,
-- titre, bouton fermer, contenu reconstruit a chaque synchronisation.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Icons = require(ReplicatedStorage.Shared.Icons)
local UI = require(script.Parent.UI)
local State = require(script.Parent.State)

local Window = {}
local C = UI.C

local defs = {} -- [name] = { title, icon, build(content, ctx), refreshOn }
local frame, titleLabel, iconHolder, content, scale
Window.Current = nil
Window.Ctx = {}
Window.Opened = Instance.new("BindableEvent")

function Window.Register(name, def)
	defs[name] = def
end

local function fit()
	local vs = workspace.CurrentCamera.ViewportSize
	scale.Scale = math.min(1, (vs.X - 20) / 780, (vs.Y - 30) / 540)
end

function Window.Init(screen)
	frame = UI.panel({ Name = "Window", Size = UDim2.fromOffset(780, 520), Position = UDim2.new(0.5, 0, 0.5, 8), AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 20 }, screen)
	scale = UI.new("UIScale", {}, frame)
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	local header = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = C.Purple, BorderSizePixel = 0, ZIndex = 21 }, frame)
	UI.corner(header, 18)
	UI.gradient(header, C.Purple, C.Purple2, 90)
	UI.new("Frame", { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 1, -20), BackgroundColor3 = C.Purple2, BorderSizePixel = 0, ZIndex = 21 }, header)
	iconHolder = UI.new("Frame", { Size = UDim2.fromOffset(110, 110), Position = UDim2.fromOffset(-26, -42), BackgroundTransparency = 1, ZIndex = 25 }, frame)
	titleLabel = UI.text({ Size = UDim2.new(1, -200, 0, 40), Position = UDim2.fromOffset(96, 12), Text = "", TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22, StrokeThickness = 3 }, frame)
	local close = Icons.Button("close", frame, { Size = UDim2.fromOffset(54, 54), Position = UDim2.new(1, -30, 0, -14), ZIndex = 26 })
	close.Activated:Connect(function()
		Window.Close()
	end)
	content = UI.new("Frame", { Name = "Content", Size = UDim2.new(1, -32, 1, -84), Position = UDim2.fromOffset(16, 74), BackgroundTransparency = 1, ZIndex = 21 }, frame)
	State.Changed.Event:Connect(function(what)
		if Window.Current then
			local def = defs[Window.Current]
			if def.refreshOn and def.refreshOn[what] then
				Window.Render()
			end
		end
	end)
end

function Window.Render()
	local def = defs[Window.Current]
	if not def then
		return
	end
	local scrollPos = {}
	for _, d in ipairs(content:GetDescendants()) do
		if d:IsA("ScrollingFrame") and d.Name ~= "" then
			scrollPos[d.Name] = d.CanvasPosition
		end
	end
	content:ClearAllChildren()
	if State.data then
		local ok, err = pcall(def.build, content, Window.Ctx)
		if not ok then
			warn("[RelicRush] Fenetre " .. Window.Current .. " : " .. tostring(err))
		end
	end
	for _, d in ipairs(content:GetDescendants()) do
		if d:IsA("ScrollingFrame") and scrollPos[d.Name] then
			d.CanvasPosition = scrollPos[d.Name]
		end
	end
end

function Window.Open(name, ctx)
	local def = defs[name]
	if not def then
		return
	end
	if Window.Current == name and not ctx then
		return Window.Close()
	end
	Window.Current = name
	Window.Ctx = ctx or {}
	titleLabel.Text = def.title
	iconHolder:ClearAllChildren()
	Icons.Image(def.icon, iconHolder, { Size = UDim2.fromScale(1, 1), ZIndex = 25 })
	frame.Visible = true
	Window.Render()
	local s = scale.Scale
	scale.Scale = s * 0.8
	UI.tween(scale, 0.25, { Scale = s }, Enum.EasingStyle.Back)
	Window.Opened:Fire(name)
end

function Window.Close()
	Window.Current = nil
	if frame then
		frame.Visible = false
	end
end

return Window
