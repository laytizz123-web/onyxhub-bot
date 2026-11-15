-- Interface PET RUSH, style simulateur : vraies icones, portraits 3D, panneaux degrades, texte epais.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PetModel = require(ReplicatedStorage.Shared.PetModel)
local Icons = require(ReplicatedStorage.Shared.Icons)
local State = require(script.Parent.State)
local Portrait = require(script.Parent.Portrait)

local HUD = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local FONT = Enum.Font.FredokaOne
local TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local DARK = Color3.fromRGB(22, 24, 52)
local WHITE = Color3.new(1, 1, 1)
local GREEN = Color3.fromRGB(70, 210, 90)
local PURPLE = Color3.fromRGB(170, 90, 255)
local RED = Color3.fromRGB(240, 70, 80)
local GOLD = Color3.fromRGB(255, 195, 40)
local BLUE = Color3.fromRGB(60, 150, 255)
local GREY = Color3.fromRGB(120, 125, 150)

local ui = {}
local panels = {}
local rebuilders = {}
local selectedPet = nil

-- Helpers ------------------------------------------------------------------------------

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end
local function corner(p, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 14) }, p)
end
local function stroke(p, color, thickness)
	return new("UIStroke", { Color = color or DARK, Thickness = thickness or 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, LineJoinMode = Enum.LineJoinMode.Round }, p)
end
local function gradient(p, c1, c2, rotation)
	return new("UIGradient", { Color = ColorSequence.new(c1, c2), Rotation = rotation or 90 }, p)
end
local function lighten(c, t)
	return c:Lerp(WHITE, t)
end
local function darken(c, t)
	return c:Lerp(Color3.new(0, 0, 0), t)
end

-- Texte epais blanc avec contour sombre (style cartoon)
local function text(props, parent, strokeColor, strokeSize)
	local base = { BackgroundTransparency = 1, Font = FONT, TextColor3 = WHITE, TextScaled = true, TextStrokeTransparency = 1, BorderSizePixel = 0 }
	for k, v in pairs(props) do
		base[k] = v
	end
	local l = new("TextLabel", base, parent)
	new("UIStroke", { Color = strokeColor or DARK, Thickness = strokeSize or 2.5, LineJoinMode = Enum.LineJoinMode.Round }, l)
	return l
end

local function fmt(n)
	n = math.floor(n or 0)
	if n >= 1e9 then
		return string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(n)
end

-- Supprime les emojis des messages (garde les lettres accentuees)
local function stripEmoji(s)
	local out = {}
	for _, code in utf8.codes(s) do
		if code < 0x2000 then
			table.insert(out, utf8.char(code))
		end
	end
	return (table.concat(out):gsub("^%s+", ""):gsub("%s%s+", " "))
end

-- Animation "rebond" sur un bouton
local function bouncy(button)
	local scale = button:FindFirstChildOfClass("UIScale") or new("UIScale", { Scale = 1 }, button)
	button.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.08 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.15), { Scale = 1 }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.9 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.05 }):Play()
	end)
	return scale
end

local function pop(gui, amount)
	local scale = gui:FindFirstChildOfClass("UIScale") or new("UIScale", { Scale = 1 }, gui)
	scale.Scale = amount or 1.25
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Bouton colore avec degrade, contour, texte et icone optionnelle
local function button(parent, props, color, label, iconName)
	local b = new("TextButton", { BackgroundColor3 = color, Text = "", AutoButtonColor = false, BorderSizePixel = 0 }, parent)
	for k, v in pairs(props) do
		b[k] = v
	end
	corner(b, 12)
	gradient(b, lighten(color, 0.25), darken(color, 0.15), 90)
	stroke(b, DARK, 3)
	local shine = new("Frame", { Size = UDim2.new(1, -10, 0.35, 0), Position = UDim2.new(0, 5, 0, 4), BackgroundColor3 = WHITE, BackgroundTransparency = 0.75, BorderSizePixel = 0, ZIndex = b.ZIndex + 1 }, b)
	corner(shine, 8)
	if iconName then
		Icons.Image(iconName, b, { Size = UDim2.new(1.2, 0, 1.2, 0), SizeConstraint = Enum.SizeConstraint.RelativeYY, Position = UDim2.new(0, -6, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = b.ZIndex + 2 })
	end
	local t = text({ Name = "Label", Size = UDim2.new(1, iconName and -64 or -16, 0.66, 0), Position = UDim2.new(0.5, iconName and 24 or 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), Text = label or "", ZIndex = b.ZIndex + 2 }, b)
	bouncy(b)
	return b, t
end

-- Panneau style simulateur : degrade bleu, gros contour, icone qui deborde, bouton fermer rond
local function panel(name, size, title, iconName, color)
	color = color or BLUE
	local frame = new("Frame", { Name = name, Size = size, Position = UDim2.fromScale(0.5, 0.52), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color, Visible = false, BorderSizePixel = 0, ZIndex = 10 }, ui.gui)
	corner(frame, 26)
	gradient(frame, lighten(color, 0.3), darken(color, 0.25), 90)
	stroke(frame, DARK, 5)
	new("UIScale", { Scale = 1 }, frame)
	-- motif de points discret
	local pattern = new("Frame", { Size = UDim2.new(1, -24, 1, -86), Position = UDim2.new(0, 12, 0, 74), BackgroundColor3 = darken(color, 0.45), BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 10 }, frame)
	corner(pattern, 18)
	frame:SetAttribute("Inner", true)
	text({ Name = "Title", Size = UDim2.new(1, -220, 0, 50), Position = UDim2.new(0, 110, 0, 14), Text = title, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12 }, frame, DARK, 4)
	Icons.Image(iconName, frame, { Size = UDim2.fromOffset(118, 118), Position = UDim2.new(0, -26, 0, -40), Rotation = -8, ZIndex = 13 })
	local close = Icons.Button("close", frame, { Size = UDim2.fromOffset(60, 60), Position = UDim2.new(1, 18, 0, -18), AnchorPoint = Vector2.new(1, 0), ZIndex = 14 })
	bouncy(close)
	close.Activated:Connect(function()
		HUD.hide(frame)
	end)
	panels[name] = frame
	frame:SetAttribute("FullSize", size)
	return frame, pattern
end

local function scrolling(parent, props, layout)
	local s = new("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 8, ScrollBarImageColor3 = WHITE, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 11 }, parent)
	for k, v in pairs(props) do
		if k ~= "CellSize" then
			s[k] = v
		end
	end
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, s)
	if layout == "grid" then
		new("UIGridLayout", { CellSize = props.CellSize or UDim2.fromOffset(110, 130), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, s)
	else
		new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, s)
	end
	return s
end

local function clear(container)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function HUD.show(frame)
	for _, other in pairs(panels) do
		if other ~= frame and other.Visible then
			other.Visible = false
		end
	end
	frame.Visible = true
	local scale = frame:FindFirstChildOfClass("UIScale")
	scale.Scale = 0.6
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end
function HUD.hide(frame)
	local scale = frame:FindFirstChildOfClass("UIScale")
	local t = TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0.5 })
	t:Play()
	t.Completed:Connect(function()
		frame.Visible = false
		scale.Scale = 1
	end)
end
function HUD.toggle(name)
	local frame = panels[name]
	if not frame then
		return
	end
	if frame.Visible then
		HUD.hide(frame)
	else
		if rebuilders[name] then
			rebuilders[name]()
		end
		HUD.show(frame)
	end
end

local function rarityOf(petId)
	return Config.RarityById[Config.PetById[petId].rarity]
end

-- Tuile de pet (portrait 3D sur fond de rarete)
local function petTile(parent, pet, order, opts)
	opts = opts or {}
	local rarity = rarityOf(pet.id)
	local evo = Config.Evolutions[pet.evo or 1]
	local tile = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = rarity.color, LayoutOrder = order, BorderSizePixel = 0, ZIndex = 12 }, parent)
	corner(tile, 16)
	gradient(tile, lighten(rarity.color, 0.35), darken(rarity.color, 0.3), 90)
	stroke(tile, opts.selected and WHITE or DARK, opts.selected and 4 or 3)
	if evo.id ~= "Normal" then
		local g = new("Frame", { Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4), BackgroundTransparency = 1, ZIndex = 12 }, tile)
		corner(g, 14)
		new("UIStroke", { Color = evo.color, Thickness = 3, Transparency = 0.1 }, g)
	end
	Portrait.new(tile, pet.id, pet.evo, { Size = UDim2.new(1, -10, 0.72, 0), Position = UDim2.new(0.5, 0, 0, 4), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 13 }, { silhouette = opts.silhouette })
	text({ Size = UDim2.new(1, -8, 0.2, 0), Position = UDim2.new(0.5, 0, 1, -4), AnchorPoint = Vector2.new(0.5, 1), Text = opts.label or pet.id, ZIndex = 14 }, tile)
	if evo.id ~= "Normal" then
		local badge = text({ Size = UDim2.fromOffset(60, 18), Position = UDim2.new(0, 4, 0, 4), Text = evo.name, TextColor3 = evo.color, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 15 }, tile)
		badge.Rotation = -6
	end
	if opts.equipped then
		local check = new("Frame", { Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -4, 0, 4), AnchorPoint = Vector2.new(1, 0), BackgroundColor3 = GREEN, ZIndex = 15 }, tile)
		corner(check, 13)
		stroke(check, DARK, 2.5)
		text({ Size = UDim2.fromScale(1, 1), Text = "E", ZIndex = 16 }, check)
	end
	if opts.silhouette then
		Icons.Image("lock", tile, { Size = UDim2.fromOffset(34, 34), Position = UDim2.new(1, -4, 0, 4), AnchorPoint = Vector2.new(1, 0), ZIndex = 15 })
	end
	bouncy(tile)
	return tile
end

local function statRow(parent, y, iconName, label, value, max, color)
	Icons.Image(iconName, parent, { Size = UDim2.fromOffset(30, 30), Position = UDim2.new(0, 8, 0, y), ZIndex = 13 })
	local bg = new("Frame", { Size = UDim2.new(1, -96, 0, 16), Position = UDim2.new(0, 44, 0, y + 7), BackgroundColor3 = DARK, BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 13 }, parent)
	corner(bg, 8)
	local fill = new("Frame", { Size = UDim2.fromScale(math.clamp(value / max, 0.04, 1), 1), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 14 }, bg)
	corner(fill, 8)
	gradient(fill, lighten(color, 0.3), darken(color, 0.1), 90)
	text({ Size = UDim2.fromOffset(44, 22), Position = UDim2.new(1, -48, 0, y + 4), Text = fmt(value), ZIndex = 14, TextXAlignment = Enum.TextXAlignment.Right }, parent)
end

-- Construction du HUD --------------------------------------------------------------------

local function statPill(parent, order, iconName, color)
	local f = new("Frame", { Size = UDim2.fromOffset(230, 58), BackgroundColor3 = color, LayoutOrder = order, BorderSizePixel = 0 }, parent)
	corner(f, 29)
	gradient(f, lighten(color, 0.2), darken(color, 0.35), 90)
	stroke(f, DARK, 3)
	local icon = Icons.Image(iconName, f, { Size = UDim2.fromOffset(70, 70), Position = UDim2.new(0, -14, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 3 })
	local t = text({ Size = UDim2.new(1, -72, 0.72, 0), Position = UDim2.new(0, 62, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Text = "0", TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 }, f, DARK, 3)
	return f, t, icon
end

local function menuButton(parent, order, iconName, size, onClick)
	local holder = new("Frame", { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	local b = Icons.Button(iconName, holder, { Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
	bouncy(b)
	b.Activated:Connect(function()
		pop(b, 0.85)
		onClick()
	end)
	local badge = new("Frame", { Name = "Badge", Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, -6, 0, 6), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = RED, Visible = false, ZIndex = 5 }, holder)
	corner(badge, 15)
	stroke(badge, WHITE, 3)
	text({ Size = UDim2.fromScale(1, 1), Text = "!", ZIndex = 6 }, badge, DARK, 2)
	table.insert(ui.floaters, b)
	return b, badge
end

local function build()
	local gui = new("ScreenGui", { Name = "PetHUD", ResetOnSpawn = false, IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	ui.gui = gui
	ui.floaters = {}

	-- Stats (gauche)
	local stats = new("Frame", { Size = UDim2.fromOffset(240, 210), Position = UDim2.new(0, 24, 0.5, -150), AnchorPoint = Vector2.new(0, 0.5), BackgroundTransparency = 1 }, gui)
	new("UIListLayout", { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, stats)
	ui.coinPill, ui.coinText, ui.coinIcon = statPill(stats, 1, "coin", Color3.fromRGB(255, 170, 30))
	ui.powerPill, ui.powerText = statPill(stats, 2, "power", Color3.fromRGB(255, 90, 60))
	ui.petPill, ui.petText = statPill(stats, 3, "paw", Color3.fromRGB(170, 100, 255))

	-- Boutons secondaires (gauche, sous les stats)
	local left = new("Frame", { Size = UDim2.fromOffset(200, 200), Position = UDim2.new(0, 18, 0.5, 30), BackgroundTransparency = 1 }, gui)
	new("UIGridLayout", { CellSize = UDim2.fromOffset(96, 96), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }, left)
	menuButton(left, 1, "race", 96, function()
		HUD.toggle("Race")
	end)
	ui.dailyButton, ui.dailyBadge = menuButton(left, 2, "daily", 96, function()
		Remotes.Pets:FireServer("daily")
	end)
	menuButton(left, 3, "leaderboard", 96, function()
		HUD.toggle("Leaderboard")
	end)
	menuButton(left, 4, "codes", 96, function()
		HUD.toggle("Codes")
	end)
	ui.dailyTimer = text({ Size = UDim2.fromOffset(96, 20), Position = UDim2.new(0, 120, 0.5, 132), Text = "", ZIndex = 5 }, gui)

	-- Menu principal (droite)
	local right = new("Frame", { Size = UDim2.fromOffset(120, 500), Position = UDim2.new(1, -18, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), BackgroundTransparency = 1 }, gui)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center }, right)
	menuButton(right, 1, "pets", 116, function()
		HUD.toggle("Pets")
	end)
	menuButton(right, 2, "eggs", 116, function()
		HUD.openEgg(HUD.currentZoneEgg())
	end)
	menuButton(right, 3, "index", 116, function()
		HUD.toggle("Index")
	end)
	menuButton(right, 4, "worlds", 116, function()
		HUD.toggle("Worlds")
	end)

	-- Pets equipes (bas centre)
	ui.equipBar = new("Frame", { Size = UDim2.fromOffset(360, 96), Position = UDim2.new(0.5, 0, 1, -14), AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1 }, gui)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, ui.equipBar)

	-- Nom de zone (haut centre)
	ui.zoneBanner = new("Frame", { Size = UDim2.fromOffset(320, 50), Position = UDim2.new(0.5, 0, 0, 10), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = GREEN, BorderSizePixel = 0 }, gui)
	corner(ui.zoneBanner, 25)
	ui.zoneGradient = gradient(ui.zoneBanner, lighten(GREEN, 0.3), darken(GREEN, 0.3), 90)
	stroke(ui.zoneBanner, DARK, 4)
	ui.zoneText = text({ Size = UDim2.new(1, -24, 0.8, 0), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Text = "Starter Village" }, ui.zoneBanner, DARK, 3)

	-- Notifications
	ui.toasts = new("Frame", { Size = UDim2.fromOffset(640, 260), Position = UDim2.new(0.5, 0, 0, 70), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1 }, gui)
	new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, ui.toasts)

	-- Course en direct
	ui.raceLive = new("Frame", { Size = UDim2.fromOffset(300, 190), Position = UDim2.new(1, -150, 0, 14), AnchorPoint = Vector2.new(1, 0), BackgroundColor3 = GOLD, Visible = false, BorderSizePixel = 0 }, gui)
	corner(ui.raceLive, 20)
	gradient(ui.raceLive, lighten(GOLD, 0.2), darken(GOLD, 0.35), 90)
	stroke(ui.raceLive, DARK, 4)
	Icons.Image("race", ui.raceLive, { Size = UDim2.fromOffset(74, 74), Position = UDim2.new(0, -20, 0, -24), Rotation = -10, ZIndex = 3 })
	ui.raceLiveTitle = text({ Size = UDim2.new(1, -70, 0, 30), Position = UDim2.new(0, 60, 0, 8), Text = "COURSE", TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 }, ui.raceLive, DARK, 3)
	ui.raceLiveRows = new("Frame", { Size = UDim2.new(1, -20, 1, -48), Position = UDim2.new(0, 10, 0, 42), BackgroundTransparency = 1 }, ui.raceLive)
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, ui.raceLiveRows)

	-- Panneaux ---------------------------------------------------------------
	local pets, petsInner = panel("Pets", UDim2.fromOffset(860, 540), "MES PETS", "pets", Color3.fromRGB(80, 150, 255))
	ui.petsInfo = text({ Size = UDim2.new(0, 360, 0, 26), Position = UDim2.new(0, 110, 0, 64), Text = "", TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12 }, pets)
	local best = button(pets, { Size = UDim2.fromOffset(190, 44), Position = UDim2.new(1, -56, 0, 20), AnchorPoint = Vector2.new(1, 0), ZIndex = 13 }, GREEN, "EQUIP BEST", "star")
	best.Activated:Connect(function()
		Remotes.Pets:FireServer("equipBest")
	end)
	ui.petsGrid = scrolling(petsInner, { Size = UDim2.new(1, -290, 1, -10), Position = UDim2.fromOffset(4, 5), CellSize = UDim2.fromOffset(116, 136) }, "grid")
	ui.petDetail = new("Frame", { Size = UDim2.new(0, 270, 1, -10), Position = UDim2.new(1, -5, 0, 5), AnchorPoint = Vector2.new(1, 0), BackgroundColor3 = DARK, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 11 }, petsInner)
	corner(ui.petDetail, 16)

	local index, indexInner = panel("Index", UDim2.fromOffset(800, 540), "PET INDEX", "index", Color3.fromRGB(255, 170, 40))
	ui.indexBar = new("Frame", { Size = UDim2.new(0, 400, 0, 26), Position = UDim2.new(0, 110, 0, 62), BackgroundColor3 = DARK, BorderSizePixel = 0, ZIndex = 12 }, index)
	corner(ui.indexBar, 13)
	stroke(ui.indexBar, DARK, 3)
	ui.indexFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = GREEN, BorderSizePixel = 0, ZIndex = 13 }, ui.indexBar)
	corner(ui.indexFill, 13)
	gradient(ui.indexFill, lighten(GREEN, 0.3), darken(GREEN, 0.2), 90)
	ui.indexText = text({ Size = UDim2.new(1, 0, 1, -4), Position = UDim2.fromOffset(0, 2), Text = "", ZIndex = 14 }, ui.indexBar)
	ui.indexGrid = scrolling(indexInner, { Size = UDim2.new(1, -10, 1, -10), Position = UDim2.fromOffset(5, 5), CellSize = UDim2.fromOffset(116, 136) }, "grid")

	local eggs, eggsInner = panel("Eggs", UDim2.fromOffset(640, 540), "OEUF", "eggs", Color3.fromRGB(160, 90, 255))
	ui.eggTitle = eggs.Title
	ui.eggLuck = text({ Size = UDim2.new(0, 400, 0, 24), Position = UDim2.new(0, 110, 0, 64), Text = "", TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12 }, eggs)
	ui.eggGrid = scrolling(eggsInner, { Size = UDim2.new(1, -10, 1, -84), Position = UDim2.fromOffset(5, 5), CellSize = UDim2.fromOffset(106, 132) }, "grid")
	ui.eggButton, ui.eggButtonText = button(eggsInner, { Size = UDim2.new(1, -40, 0, 62), Position = UDim2.new(0.5, 0, 1, -10), AnchorPoint = Vector2.new(0.5, 1), ZIndex = 13 }, GOLD, "OUVRIR", "coin")
	ui.eggButton.Activated:Connect(function()
		if ui.currentEgg then
			Remotes.Pets:FireServer("hatch", ui.currentEgg)
		end
	end)

	local worlds, worldsInner = panel("Worlds", UDim2.fromOffset(660, 520), "MONDES", "worlds", Color3.fromRGB(70, 190, 90))
	ui.worldsList = scrolling(worldsInner, { Size = UDim2.new(1, -10, 1, -10), Position = UDim2.fromOffset(5, 5) }, "list")

	local race, raceInner = panel("Race", UDim2.fromOffset(800, 560), "COURSES DE PETS", "race", Color3.fromRGB(255, 140, 40))
	ui.raceStatus = text({ Size = UDim2.new(0, 520, 0, 24), Position = UDim2.new(0, 110, 0, 64), Text = "", TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12 }, race)
	ui.raceTypes = new("Frame", { Size = UDim2.new(1, -20, 0, 110), Position = UDim2.fromOffset(10, 10), BackgroundTransparency = 1, ZIndex = 11 }, raceInner)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, ui.raceTypes)
	ui.racePets = scrolling(raceInner, { Size = UDim2.new(1, -10, 1, -210), Position = UDim2.fromOffset(5, 128), CellSize = UDim2.fromOffset(106, 132) }, "grid")
	ui.raceJoin, ui.raceJoinText = button(raceInner, { Size = UDim2.new(1, -40, 0, 60), Position = UDim2.new(0.5, 0, 1, -10), AnchorPoint = Vector2.new(0.5, 1), ZIndex = 13 }, GREEN, "LANCER LA COURSE", "speed")
	ui.raceJoin.Activated:Connect(function()
		if ui.raceType and ui.racePet then
			Remotes.Race:FireServer("join", ui.raceType, ui.racePet)
		else
			HUD.toast("Choisis un type de course et un pet.", "info")
		end
	end)

	local board, boardInner = panel("Leaderboard", UDim2.fromOffset(560, 520), "CLASSEMENT", "leaderboard", Color3.fromRGB(255, 180, 40))
	ui.boardList = scrolling(boardInner, { Size = UDim2.new(1, -10, 1, -10), Position = UDim2.fromOffset(5, 5) }, "list")

	local codes, codesInner = panel("Codes", UDim2.fromOffset(520, 300), "CODES", "codes", Color3.fromRGB(60, 160, 255))
	local box = new("TextBox", { Size = UDim2.new(1, -40, 0, 62), Position = UDim2.new(0.5, 0, 0, 24), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = WHITE, Text = "", PlaceholderText = "Entre un code...", Font = FONT, TextScaled = true, TextColor3 = DARK, PlaceholderColor3 = GREY, ClearTextOnFocus = false, ZIndex = 13 }, codesInner)
	corner(box, 14)
	stroke(box, DARK, 3)
	new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }, box)
	local redeem = button(codesInner, { Size = UDim2.new(1, -40, 0, 60), Position = UDim2.new(0.5, 0, 1, -16), AnchorPoint = Vector2.new(0.5, 1), ZIndex = 13 }, GREEN, "VALIDER", "star")
	redeem.Activated:Connect(function()
		Remotes.Pets:FireServer("code", box.Text)
		box.Text = ""
	end)

	-- Eclosion plein ecran
	ui.hatch = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 10, 25), BackgroundTransparency = 0.3, Visible = false, ZIndex = 40, BorderSizePixel = 0 }, gui)
	ui.rays = new("Frame", { Size = UDim2.fromOffset(700, 700), Position = UDim2.fromScale(0.5, 0.45), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 41 }, ui.hatch)
	for i = 1, 12 do
		local ray = new("Frame", { Size = UDim2.new(0, 46, 1, 0), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = i * 15, BackgroundColor3 = WHITE, BackgroundTransparency = 0.8, BorderSizePixel = 0, ZIndex = 41 }, ui.rays)
		new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }), Rotation = 90 }, ray)
	end
	ui.hatchEgg = Icons.Image("egg", ui.hatch, { Size = UDim2.fromOffset(240, 240), Position = UDim2.fromScale(0.5, 0.45), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 42 })
	ui.hatchPet = new("Frame", { Size = UDim2.fromOffset(360, 360), Position = UDim2.fromScale(0.5, 0.42), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 42 }, ui.hatch)
	ui.hatchName = text({ Size = UDim2.fromOffset(700, 70), Position = UDim2.new(0.5, 0, 0.7, 0), AnchorPoint = Vector2.new(0.5, 0.5), Text = "", ZIndex = 43 }, ui.hatch, DARK, 5)
	ui.hatchRarity = text({ Size = UDim2.fromOffset(500, 44), Position = UDim2.new(0.5, 0, 0.78, 0), AnchorPoint = Vector2.new(0.5, 0.5), Text = "", ZIndex = 43 }, ui.hatch, DARK, 4)
end

-- Notifications ----------------------------------------------------------------------------

local toastCount = 0
function HUD.toast(message, kind)
	toastCount += 1
	local styles = { danger = { RED, "close" }, gold = { GOLD, "coin" }, good = { GREEN, "star" }, info = { BLUE, "gem" } }
	local style = styles[kind] or styles.info
	local frame = new("Frame", { Size = UDim2.new(0.9, 0, 0, 46), BackgroundColor3 = style[1], LayoutOrder = toastCount, BorderSizePixel = 0 }, ui.toasts)
	corner(frame, 23)
	gradient(frame, lighten(style[1], 0.25), darken(style[1], 0.3), 90)
	stroke(frame, DARK, 3)
	Icons.Image(style[2], frame, { Size = UDim2.fromOffset(52, 52), Position = UDim2.new(0, -8, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 3 })
	text({ Size = UDim2.new(1, -70, 0.66, 0), Position = UDim2.new(0, 52, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Text = stripEmoji(message), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 }, frame)
	pop(frame, 0.6)
	task.delay(4, function()
		local t = TweenService:Create(frame:FindFirstChildOfClass("UIScale"), TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
		t:Play()
		t.Completed:Wait()
		frame:Destroy()
	end)
end

-- Mes pets ------------------------------------------------------------------------------------

local function countSame(pet)
	local n = 0
	for _, other in ipairs(State.data.pets) do
		if other.id == pet.id and other.evo == pet.evo then
			n += 1
		end
	end
	return n
end

local function rebuildDetail()
	clear(ui.petDetail)
	local pet = selectedPet and State.petByUid(selectedPet)
	if not pet then
		text({ Size = UDim2.new(1, -20, 0, 60), Position = UDim2.fromScale(0.5, 0.45), AnchorPoint = Vector2.new(0.5, 0.5), Text = "Clique sur un pet", ZIndex = 13 }, ui.petDetail)
		return
	end
	local rarity = rarityOf(pet.id)
	local evo = Config.Evolutions[pet.evo]
	local bg = new("Frame", { Size = UDim2.new(1, -16, 0, 170), Position = UDim2.fromOffset(8, 8), BackgroundColor3 = rarity.color, BorderSizePixel = 0, ZIndex = 12 }, ui.petDetail)
	corner(bg, 14)
	gradient(bg, lighten(rarity.color, 0.4), darken(rarity.color, 0.35), 90)
	stroke(bg, DARK, 3)
	Portrait.new(bg, pet.id, pet.evo, { Size = UDim2.fromScale(1, 1), ZIndex = 13 }, { spin = 1.2 })
	text({ Size = UDim2.new(1, -16, 0, 34), Position = UDim2.fromOffset(8, 184), Text = (evo.name ~= "" and evo.name .. " " or "") .. pet.id, TextColor3 = evo.color or WHITE, ZIndex = 13 }, ui.petDetail, DARK, 3)
	Icons.Rarity(rarity.id, ui.petDetail, { Size = UDim2.fromOffset(26, 26), Position = UDim2.new(0.5, -70, 0, 222), ZIndex = 13 })
	text({ Size = UDim2.fromOffset(130, 24), Position = UDim2.new(0.5, -40, 0, 223), Text = rarity.name, TextColor3 = rarity.color, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13 }, ui.petDetail)
	local s = PetModel.Stats(pet.id, pet.evo)
	statRow(ui.petDetail, 254, "speed", "Speed", s.speed, 150, Color3.fromRGB(255, 210, 50))
	statRow(ui.petDetail, 288, "power", "Power", s.power, 600, Color3.fromRGB(255, 100, 60))
	statRow(ui.petDetail, 322, "stamina", "Stamina", s.stamina, 150, Color3.fromRGB(70, 150, 255))
	statRow(ui.petDetail, 356, "luck", "Luck", s.luck, 150, Color3.fromRGB(80, 210, 90))
	local equipped = table.find(State.data.equipped, pet.uid) ~= nil
	local eq = button(ui.petDetail, { Size = UDim2.new(1, -20, 0, 42), Position = UDim2.new(0, 10, 1, -104), ZIndex = 13 }, equipped and GREY or GREEN, equipped and "RETIRER" or "EQUIPER")
	eq.Activated:Connect(function()
		Remotes.Pets:FireServer("equip", pet.uid)
	end)
	local same = countSame(pet)
	local maxed = pet.evo >= #Config.Evolutions
	local canEvolve = same >= Config.EvolveCost and not maxed
	local nextEvo = Config.Evolutions[math.min(pet.evo + 1, #Config.Evolutions)]
	local ev = button(ui.petDetail, { Size = UDim2.new(0.68, -14, 0, 42), Position = UDim2.new(0, 10, 1, -54), ZIndex = 13 }, canEvolve and PURPLE or GREY, maxed and "MAX" or (nextEvo.name .. " " .. same .. "/" .. Config.EvolveCost), "sparkle")
	ev.Activated:Connect(function()
		Remotes.Pets:FireServer("evolve", pet.uid)
	end)
	local del = button(ui.petDetail, { Size = UDim2.new(0.32, -6, 0, 42), Position = UDim2.new(1, -10, 1, -54), AnchorPoint = Vector2.new(1, 0), ZIndex = 13 }, RED, "SUPPR")
	del.Activated:Connect(function()
		Remotes.Pets:FireServer("delete", pet.uid)
		selectedPet = nil
	end)
end

local function rebuildPets()
	clear(ui.petsGrid)
	local data = State.data
	ui.petsInfo.Text = #data.pets .. "/" .. Config.MaxPets .. " pets  -  " .. #data.equipped .. "/" .. Config.MaxEquipped .. " equipes"
	local sorted = table.clone(data.pets)
	table.sort(sorted, function(a, b)
		local pa, pb = PetModel.Stats(a.id, a.evo).power, PetModel.Stats(b.id, b.evo).power
		if pa ~= pb then
			return pa > pb
		end
		return a.uid < b.uid
	end)
	if selectedPet and not State.petByUid(selectedPet) then
		selectedPet = nil
	end
	if not selectedPet and sorted[1] then
		selectedPet = sorted[1].uid
	end
	for i, pet in ipairs(sorted) do
		local tile = petTile(ui.petsGrid, pet, i, { selected = selectedPet == pet.uid, equipped = table.find(data.equipped, pet.uid) ~= nil })
		tile.Activated:Connect(function()
			selectedPet = pet.uid
			rebuildPets()
		end)
	end
	rebuildDetail()
end

local function rebuildEquipBar()
	clear(ui.equipBar)
	for i = 1, Config.MaxEquipped do
		local uid = State.data.equipped[i]
		local pet = uid and State.petByUid(uid)
		local color = pet and rarityOf(pet.id).color or GREY
		local slot = new("TextButton", { Size = UDim2.fromOffset(92, 92), Text = "", AutoButtonColor = false, BackgroundColor3 = color, LayoutOrder = i, BorderSizePixel = 0 }, ui.equipBar)
		corner(slot, 20)
		gradient(slot, lighten(color, 0.35), darken(color, 0.35), 90)
		stroke(slot, DARK, 4)
		if pet then
			Portrait.new(slot, pet.id, pet.evo, { Size = UDim2.fromScale(1, 1), ZIndex = 2 }, { spin = 0.8 })
			local evo = Config.Evolutions[pet.evo]
			if evo.id ~= "Normal" then
				text({ Size = UDim2.new(1, -8, 0, 18), Position = UDim2.new(0.5, 0, 1, -4), AnchorPoint = Vector2.new(0.5, 1), Text = evo.name, TextColor3 = evo.color, ZIndex = 3 }, slot)
			end
		else
			text({ Size = UDim2.fromScale(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Text = "+", ZIndex = 2 }, slot)
		end
		bouncy(slot)
		slot.Activated:Connect(function()
			HUD.toggle("Pets")
		end)
	end
end

-- Index -------------------------------------------------------------------------------------------

local function rebuildIndex()
	clear(ui.indexGrid)
	local found = 0
	for _, pet in ipairs(Config.Pets) do
		if State.data.index[pet.id] then
			found += 1
		end
	end
	ui.indexFill.Size = UDim2.fromScale(math.max(found / #Config.Pets, 0.02), 1)
	ui.indexText.Text = found .. " / " .. #Config.Pets .. " decouverts"
	for i, def in ipairs(Config.Pets) do
		local known = State.data.index[def.id] == true
		local tile = petTile(ui.indexGrid, { id = def.id, evo = 1 }, i, { silhouette = not known, label = known and def.id or "???" })
		if not known then
			tile.BackgroundColor3 = GREY
			tile:FindFirstChildOfClass("UIGradient").Color = ColorSequence.new(lighten(GREY, 0.2), darken(GREY, 0.4))
		end
		Icons.Rarity(def.rarity, tile, { Size = UDim2.fromOffset(24, 24), Position = UDim2.fromOffset(6, 6), ZIndex = 15 })
	end
end

-- Oeufs -------------------------------------------------------------------------------------------

function HUD.currentZoneEgg()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		for i, zone in ipairs(Config.Zones) do
			if math.abs(hrp.Position.X - zone.center.X) <= zone.size / 2 + 50 and math.abs(hrp.Position.Z - zone.center.Z) <= zone.size / 2 + 50 then
				return Config.Eggs[i].id
			end
		end
	end
	return "Village"
end

local function equippedLuck()
	local luck = 0
	for _, uid in ipairs(State.data.equipped) do
		local pet = State.petByUid(uid)
		if pet then
			luck += PetModel.Stats(pet.id, pet.evo).luck
		end
	end
	return 1 + math.min(luck, 300) / 150
end

function HUD.openEgg(eggId)
	local egg = Config.EggById[eggId]
	if not egg then
		return
	end
	ui.currentEgg = eggId
	ui.eggTitle.Text = string.upper(egg.name)
	clear(ui.eggGrid)
	local luck = equippedLuck()
	local pool, total = {}, 0
	for _, pet in ipairs(Config.Pets) do
		if pet.egg == eggId then
			local rarity = Config.RarityById[pet.rarity]
			local weight = rarity.weight * (rarity.index >= 3 and luck or 1)
			table.insert(pool, { pet = pet, weight = weight })
			total += weight
		end
	end
	for i, entry in ipairs(pool) do
		local def = entry.pet
		local known = State.data.index[def.id] == true
		local pct = entry.weight / total * 100
		local tile = petTile(ui.eggGrid, { id = def.id, evo = 1 }, i, { silhouette = not known, label = pct >= 1 and string.format("%.1f%%", pct) or string.format("%.2f%%", pct) })
		Icons.Rarity(def.rarity, tile, { Size = UDim2.fromOffset(24, 24), Position = UDim2.fromOffset(6, 6), ZIndex = 15 })
	end
	ui.eggLuck.Text = luck > 1 and string.format("Bonus de chance +%d%%", math.floor((luck - 1) * 100)) or "Equipe des pets chanceux pour plus de raretes"
	ui.eggButtonText.Text = "OUVRIR  " .. fmt(egg.price)
	local affordable = State.data.coins >= egg.price
	ui.eggButton.BackgroundColor3 = affordable and GOLD or GREY
	if not panels.Eggs.Visible then
		HUD.show(panels.Eggs)
	end
end

-- Mondes ------------------------------------------------------------------------------------------

local function rebuildWorlds()
	clear(ui.worldsList)
	for i, zone in ipairs(Config.Zones) do
		local unlocked = State.data.zones[zone.id] == true
		local row = new("Frame", { Size = UDim2.new(1, 0, 0, 128), BackgroundColor3 = zone.ground, LayoutOrder = i, BorderSizePixel = 0, ZIndex = 12 }, ui.worldsList)
		corner(row, 18)
		gradient(row, lighten(zone.ground, 0.3), darken(zone.ground, 0.4), 90)
		stroke(row, DARK, 4)
		text({ Size = UDim2.new(0.6, 0, 0, 44), Position = UDim2.fromOffset(20, 12), Text = zone.name, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13 }, row, DARK, 4)
		Icons.Image("coin", row, { Size = UDim2.fromOffset(34, 34), Position = UDim2.fromOffset(18, 64), ZIndex = 13 })
		text({ Size = UDim2.fromOffset(180, 28), Position = UDim2.fromOffset(58, 67), Text = zone.coinValue .. " / piece", TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13 }, row)
		Icons.Image("egg", row, { Size = UDim2.fromOffset(34, 34), Position = UDim2.fromOffset(200, 64), ZIndex = 13, ImageColor3 = Config.Eggs[i].color })
		text({ Size = UDim2.fromOffset(140, 28), Position = UDim2.fromOffset(240, 67), Text = fmt(Config.Eggs[i].price), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13 }, row)
		if unlocked then
			local go = Icons.Button("teleport", row, { Size = UDim2.fromOffset(150, 150), Position = UDim2.new(1, 10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), ZIndex = 14 })
			bouncy(go)
			go.Activated:Connect(function()
				Remotes.Pets:FireServer("teleport", zone.id)
				HUD.hide(panels.Worlds)
			end)
		else
			local b = button(row, { Size = UDim2.fromOffset(190, 56), Position = UDim2.new(1, -16, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), ZIndex = 14 }, GOLD, fmt(zone.price), "lock")
			b.Activated:Connect(function()
				Remotes.Pets:FireServer("unlock", zone.id)
			end)
			local veil = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 12 }, row)
			corner(veil, 18)
		end
	end
end

-- Courses ------------------------------------------------------------------------------------------

local function rebuildRace()
	clear(ui.raceTypes)
	clear(ui.racePets)
	for i, t in ipairs(Config.Race.Types) do
		local selected = ui.raceType == t.id
		local color = t.id == "Sprint" and Color3.fromRGB(255, 190, 40) or Color3.fromRGB(70, 150, 255)
		local card = new("TextButton", { Size = UDim2.new(0.5, -6, 1, 0), Text = "", AutoButtonColor = false, BackgroundColor3 = color, LayoutOrder = i, BorderSizePixel = 0, ZIndex = 12 }, ui.raceTypes)
		corner(card, 18)
		gradient(card, lighten(color, 0.3), darken(color, 0.3), 90)
		stroke(card, selected and WHITE or DARK, selected and 5 or 3)
		Icons.Image(t.id == "Sprint" and "speed" or "stamina", card, { Size = UDim2.fromOffset(80, 80), Position = UDim2.new(0, 8, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 13 })
		text({ Size = UDim2.new(1, -100, 0, 36), Position = UDim2.fromOffset(92, 8), Text = string.upper(t.name), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13 }, card, DARK, 3)
		text({ Size = UDim2.new(1, -100, 0, 22), Position = UDim2.fromOffset(92, 46), Text = t.laps .. " tour" .. (t.laps > 1 and "s" or ""), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13 }, card)
		Icons.Image("coin", card, { Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(90, 72), ZIndex = 13 })
		text({ Size = UDim2.fromOffset(120, 24), Position = UDim2.fromOffset(122, 74), Text = fmt(t.reward), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13 }, card)
		bouncy(card)
		card.Activated:Connect(function()
			ui.raceType = t.id
			rebuildRace()
		end)
	end
	for i, pet in ipairs(State.data.pets) do
		local s = PetModel.Stats(pet.id, pet.evo)
		local tile = petTile(ui.racePets, pet, i, { selected = ui.racePet == pet.uid, label = fmt(s.speed) .. " / " .. fmt(s.stamina) })
		tile.Activated:Connect(function()
			ui.racePet = pet.uid
			rebuildRace()
		end)
	end
	local race = State.race
	if race.phase == "Idle" then
		ui.raceStatus.Text = "Vitesse / Endurance affichees sous chaque pet"
		ui.raceJoinText.Text = "LANCER LA COURSE"
	elseif race.phase == "Lobby" then
		ui.raceStatus.Text = "Course " .. tostring(race.type) .. " : " .. #race.racers .. "/" .. Config.Race.MaxRacers .. " inscrits"
		ui.raceJoinText.Text = "REJOINDRE"
	else
		ui.raceStatus.Text = "Course en cours, regarde la piste !"
		ui.raceJoinText.Text = "EN COURS..."
	end
end

local function raceRow(order, r, labelText, color)
	local row = new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = color or DARK, BackgroundTransparency = 0.35, LayoutOrder = order, BorderSizePixel = 0 }, ui.raceLiveRows)
	corner(row, 10)
	Portrait.new(row, r.petId, r.evo, { Size = UDim2.fromOffset(30, 30), ZIndex = 3 })
	text({ Size = UDim2.new(1, -40, 0.8, 0), Position = UDim2.new(0, 36, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Text = labelText, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = r.userId == player.UserId and Color3.fromRGB(255, 240, 120) or WHITE, ZIndex = 3 }, row)
end

local function onRace(race)
	State.race = race
	if panels.Race.Visible then
		rebuildRace()
	end
	if race.phase == "Idle" then
		ui.raceLive.Visible = false
		return
	end
	ui.raceLive.Visible = true
	clear(ui.raceLiveRows)
	local function stripName(n)
		return stripEmoji(n)
	end
	if race.phase == "Lobby" or race.phase == "Countdown" then
		ui.raceLiveTitle.Text = race.phase == "Lobby" and ("LOBBY " .. string.upper(tostring(race.type))) or "DEPART !"
		for i, r in ipairs(race.racers) do
			raceRow(i, r, stripName(r.name))
		end
	elseif race.phase == "Racing" then
		ui.raceLiveTitle.Text = string.upper(tostring(race.type))
		local sorted = table.clone(race.racers)
		table.sort(sorted, function(a, b)
			return (a.progress or 0) > (b.progress or 0)
		end)
		for i, r in ipairs(sorted) do
			local pct = race.total and math.floor((r.progress or 0) / race.total * 100) or 0
			raceRow(i, r, i .. ". " .. stripName(r.name) .. "  " .. pct .. "%")
		end
	else
		ui.raceLiveTitle.Text = "RESULTATS"
		local colors = { GOLD, Color3.fromRGB(190, 200, 215), Color3.fromRGB(215, 140, 80) }
		for i, r in ipairs(race.results or race.racers) do
			raceRow(i, r, (r.rank or i) .. ". " .. stripName(r.name), colors[r.rank or i])
		end
	end
end

-- Classement ------------------------------------------------------------------------------------

local function rebuildBoard()
	clear(ui.boardList)
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local ls = p:FindFirstChild("leaderstats")
		table.insert(list, { player = p, coins = ls and ls:FindFirstChild("Coins") and ls.Coins.Value or 0, wins = ls and ls:FindFirstChild("RaceWins") and ls.RaceWins.Value or 0 })
	end
	table.sort(list, function(a, b)
		return a.coins > b.coins
	end)
	local medal = { GOLD, Color3.fromRGB(200, 210, 225), Color3.fromRGB(220, 140, 80) }
	for i, entry in ipairs(list) do
		local color = medal[i] or Color3.fromRGB(90, 110, 190)
		local row = new("Frame", { Size = UDim2.new(1, 0, 0, 70), BackgroundColor3 = color, LayoutOrder = i, BorderSizePixel = 0, ZIndex = 12 }, ui.boardList)
		corner(row, 16)
		gradient(row, lighten(color, 0.25), darken(color, 0.35), 90)
		stroke(row, DARK, 3)
		text({ Size = UDim2.fromOffset(46, 46), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Text = "#" .. i, ZIndex = 13 }, row, DARK, 3)
		local avatar = new("ImageLabel", { Size = UDim2.fromOffset(54, 54), Position = UDim2.new(0, 64, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = WHITE, ZIndex = 13 }, row)
		corner(avatar, 27)
		stroke(avatar, DARK, 3)
		task.spawn(function()
			local ok, img = pcall(function()
				return Players:GetUserThumbnailAsync(entry.player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			end)
			if ok then
				avatar.Image = img
			end
		end)
		text({ Size = UDim2.new(0.42, 0, 0, 30), Position = UDim2.new(0, 128, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Text = entry.player.DisplayName, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13 }, row)
		Icons.Image("coin", row, { Size = UDim2.fromOffset(34, 34), Position = UDim2.new(1, -150, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 13 })
		text({ Size = UDim2.fromOffset(100, 28), Position = UDim2.new(1, -112, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Text = fmt(entry.coins), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13 }, row)
	end
end

-- Eclosion ------------------------------------------------------------------------------------------

function HUD.playHatch(data)
	local def = Config.PetById[data.petId]
	local rarity = Config.RarityById[data.rarity]
	local egg = Config.EggById[data.egg or "Village"]
	ui.hatch.Visible = true
	ui.hatch.BackgroundTransparency = 0.3
	ui.rays.Visible = false
	clear(ui.hatchPet)
	ui.hatchEgg.Visible = true
	ui.hatchEgg.ImageColor3 = egg and egg.color or WHITE
	ui.hatchEgg.Size = UDim2.fromOffset(240, 240)
	ui.hatchName.Text = ""
	ui.hatchRarity.Text = ""
	task.spawn(function()
		for i = 1, 12 do
			ui.hatchEgg.Rotation = (i % 2 == 0) and (6 + i) or -(6 + i)
			ui.hatchEgg.Size = UDim2.fromOffset(240 + i * 5, 240 + i * 5)
			task.wait(0.08)
		end
		ui.hatchEgg.Rotation = 0
		ui.hatchEgg.Visible = false
		ui.rays.Visible = true
		for _, ray in ipairs(ui.rays:GetChildren()) do
			ray.BackgroundColor3 = lighten(rarity.color, 0.4)
		end
		local vp = Portrait.new(ui.hatchPet, def.id, data.evo or 1, { Size = UDim2.fromScale(1, 1), ZIndex = 42 }, { spin = 1.5, zoom = 1.1 })
		pop(ui.hatchPet, 0.2)
		ui.hatchName.Text = string.upper(def.id)
		ui.hatchName.TextColor3 = WHITE
		ui.hatchRarity.Text = string.upper(rarity.name)
		ui.hatchRarity.TextColor3 = rarity.color
		pop(ui.hatchName, 0.4)
		local start = os.clock()
		while os.clock() - start < 2.6 do
			ui.rays.Rotation = (os.clock() - start) * 40
			task.wait()
		end
		TweenService:Create(ui.hatch, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		task.wait(0.3)
		ui.hatch.Visible = false
		vp:Destroy()
	end)
end

-- Synchronisation --------------------------------------------------------------------------------

local shownCoins = 0
local function animateCoins(target)
	local from = shownCoins
	local start = os.clock()
	task.spawn(function()
		while os.clock() - start < 0.4 do
			local t = (os.clock() - start) / 0.4
			ui.coinText.Text = fmt(from + (target - from) * t)
			task.wait()
		end
		ui.coinText.Text = fmt(target)
	end)
	if target > from then
		pop(ui.coinIcon, 1.3)
	end
	shownCoins = target
end

local function onSync(data)
	State.data = data
	animateCoins(data.coins)
	ui.powerText.Text = fmt(data.power)
	ui.petText.Text = #data.pets .. "/" .. Config.MaxPets
	ui.dailyBadge.Visible = data.dailyReady
	ui.dailyTimer.Text = data.dailyReady and "" or string.format("%dh%02d", math.floor(data.dailyIn / 3600), math.floor(data.dailyIn % 3600 / 60))
	rebuildEquipBar()
	for name, fn in pairs(rebuilders) do
		if panels[name] and panels[name].Visible then
			fn()
		end
	end
	if panels.Eggs.Visible and ui.currentEgg then
		HUD.openEgg(ui.currentEgg)
	end
	State.fire("sync", data)
end

function HUD.Init()
	build()
	rebuilders = { Pets = rebuildPets, Index = rebuildIndex, Worlds = rebuildWorlds, Race = rebuildRace, Leaderboard = rebuildBoard }
	Remotes.PetsSync.OnClientEvent:Connect(onSync)
	Remotes.RaceSync.OnClientEvent:Connect(onRace)
	Remotes.Notify.OnClientEvent:Connect(HUD.toast)

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local s = prompt.Parent
		if not s then
			return
		end
		if CollectionService:HasTag(s, "EggStand") then
			HUD.openEgg(s:GetAttribute("EggId"))
		elseif CollectionService:HasTag(s, "RaceStand") then
			rebuildRace()
			HUD.show(panels.Race)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		local map = { [Enum.KeyCode.P] = "Pets", [Enum.KeyCode.I] = "Index", [Enum.KeyCode.Z] = "Worlds", [Enum.KeyCode.R] = "Race" }
		if map[input.KeyCode] then
			HUD.toggle(map[input.KeyCode])
		elseif input.KeyCode == Enum.KeyCode.Escape then
			for _, f in pairs(panels) do
				if f.Visible then
					HUD.hide(f)
				end
			end
		end
	end)

	-- Animations continues : boutons qui flottent, badge qui pulse, banniere de zone
	local currentZone = nil
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for i, b in ipairs(ui.floaters) do
			b.Rotation = math.sin(t * 2 + i) * 3
			b.Position = UDim2.new(0.5, 0, 0.5, math.sin(t * 2.4 + i * 0.7) * 3)
		end
		if ui.dailyBadge.Visible then
			ui.dailyBadge.Rotation = math.sin(t * 8) * 12
		end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local zone
			for _, z in ipairs(Config.Zones) do
				if math.abs(hrp.Position.X - z.center.X) <= z.size / 2 + 50 and math.abs(hrp.Position.Z - z.center.Z) <= z.size / 2 + 50 then
					zone = z
				end
			end
			if zone ~= currentZone then
				currentZone = zone
				if zone then
					ui.zoneText.Text = string.upper(zone.name)
					ui.zoneBanner.BackgroundColor3 = zone.ground
					ui.zoneGradient.Color = ColorSequence.new(lighten(zone.ground, 0.3), darken(zone.ground, 0.4))
					pop(ui.zoneBanner, 1.3)
				end
			end
		end
	end)
	task.delay(1, function()
		Remotes.Pets:FireServer("sync")
		Remotes.Race:FireServer("state")
	end)
end

return HUD
