-- Interface stylee : icones dynamiques, degrades, lueurs, animations.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local State = require(script.Parent.State)

local HUD = {}
local C = Config.Combat
local ICON = Config.Icons

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local FONT = Enum.Font.GothamBlack
local FONT_BOLD = Enum.Font.GothamBold
local TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local ui = {}
local Input

-- Helpers ------------------------------------------------------------------------

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end
local function corner(p, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 10) }, p)
end
local function stroke(p, color, thickness, transparency)
	return new("UIStroke", { Color = color, Thickness = thickness or 2, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end
local function gradient(p, c1, c2, rotation)
	return new("UIGradient", { Color = ColorSequence.new(c1, c2), Rotation = rotation or 90 }, p)
end
local function label(props, parent)
	local base = { BackgroundTransparency = 1, Font = FONT, TextColor3 = Color3.new(1, 1, 1), TextScaled = true, TextStrokeTransparency = 0.7, TextStrokeColor3 = Color3.new(0, 0, 0) }
	for k, v in pairs(props) do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end
local function glassFrame(props, parent, color)
	local base = { BackgroundColor3 = Config.Colors.Panel, BackgroundTransparency = 0.12, BorderSizePixel = 0 }
	for k, v in pairs(props) do
		base[k] = v
	end
	local f = new("Frame", base, parent)
	corner(f, 14)
	gradient(f, Config.Colors.Panel, Config.Colors.Panel2, 90)
	stroke(f, color or Config.Colors.Accent, 2, 0.35)
	return f
end
local function button(props, parent, color)
	color = color or Config.Colors.Accent
	local base = { BackgroundColor3 = color, Font = FONT, TextColor3 = Color3.new(1, 1, 1), TextScaled = true, AutoButtonColor = false, Text = "", BorderSizePixel = 0 }
	for k, v in pairs(props) do
		base[k] = v
	end
	local b = new("TextButton", base, parent)
	corner(b, 12)
	gradient(b, Color3.new(1, 1, 1), Color3.fromRGB(160, 160, 160), 90)
	stroke(b, Color3.new(1, 1, 1), 1.5, 0.6)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, b)
	-- Survol / clic animes
	b.MouseEnter:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.25) }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.15), { BackgroundColor3 = color }):Play()
	end)
	b.MouseButton1Down:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.06), { BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.25) }):Play()
	end)
	b.MouseButton1Up:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = color }):Play()
	end)
	return b
end
local function panel(name, size, title, icon, color, parent)
	local frame = new("Frame", { Name = name, Size = size, Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Config.Colors.Panel, BackgroundTransparency = 0.04, Visible = false, BorderSizePixel = 0 }, parent)
	corner(frame, 20)
	gradient(frame, Config.Colors.Panel, Config.Colors.Panel2, 90)
	stroke(frame, color, 3, 0.1)
	local head = new("Frame", { Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = color, BackgroundTransparency = 0.75, BorderSizePixel = 0 }, frame)
	corner(head, 20)
	gradient(head, Color3.new(1, 1, 1), Color3.new(0, 0, 0), 0)
	label({ Size = UDim2.new(1, -80, 0, 36), Position = UDim2.new(0, 18, 0, 10), Text = icon .. "  " .. title, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.new(1, 1, 1) }, head)
	local close = button({ Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, -10, 0, 8), AnchorPoint = Vector2.new(1, 0), Text = "✕" }, head, Config.Colors.Danger)
	close.Activated:Connect(function()
		HUD.hidePanel(frame)
	end)
	return frame
end
local function scrollList(parent, top, bottom)
	local scroll = new("ScrollingFrame", { Size = UDim2.new(1, -24, 1, -(top + (bottom or 12))), Position = UDim2.new(0, 12, 0, top), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, ScrollBarImageColor3 = Config.Colors.Accent, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.Y }, parent)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	return scroll
end

function HUD.showPanel(frame)
	frame.Visible = true
	local size = frame:GetAttribute("FullSize") or frame.Size
	frame:SetAttribute("FullSize", size)
	frame.Size = UDim2.fromOffset(size.X.Offset * 0.8, size.Y.Offset * 0.8)
	TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = size }):Play()
end
function HUD.hidePanel(frame)
	local size = frame:GetAttribute("FullSize") or frame.Size
	local t = TweenService:Create(frame, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.fromOffset(size.X.Offset * 0.85, size.Y.Offset * 0.85) })
	t:Play()
	t.Completed:Connect(function()
		frame.Visible = false
		frame.Size = size
	end)
end

-- Slot de competence -------------------------------------------------------------------

local function skillSlot(parent, index, key)
	local slot = new("TextButton", { Name = "Skill" .. index, Size = UDim2.fromOffset(96, 96), BackgroundColor3 = Config.Colors.Panel, BackgroundTransparency = 0.1, Text = "", AutoButtonColor = false, LayoutOrder = index, BorderSizePixel = 0 }, parent)
	corner(slot, 16)
	gradient(slot, Config.Colors.Panel, Config.Colors.Panel2, 90)
	local st = stroke(slot, Config.Colors.Accent, 3)
	local glow = new("Frame", { Name = "Glow", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Config.Colors.Accent, BackgroundTransparency = 1, BorderSizePixel = 0 }, slot)
	corner(glow, 16)
	local fill = new("Frame", { Name = "Cooldown", Size = UDim2.fromScale(1, 0), Position = UDim2.fromScale(0, 1), AnchorPoint = Vector2.new(0, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 3 }, slot)
	corner(fill, 16)
	label({ Name = "Icon", Size = UDim2.new(1, 0, 0, 44), Position = UDim2.new(0, 0, 0, 8), Text = "👊", TextStrokeTransparency = 1, ZIndex = 2 }, slot)
	label({ Name = "Key", Size = UDim2.fromOffset(26, 22), Position = UDim2.new(0, 6, 0, 4), Text = key, Font = FONT_BOLD, TextColor3 = Color3.fromRGB(220, 220, 230), ZIndex = 4 }, slot)
	label({ Name = "Title", Size = UDim2.new(1, -8, 0, 30), Position = UDim2.new(0, 4, 1, -36), Text = "", TextWrapped = true, Font = FONT_BOLD, ZIndex = 4 }, slot)
	label({ Name = "Timer", Size = UDim2.new(1, -8, 0, 30), Position = UDim2.new(0, 4, 0, 30), Text = "", TextColor3 = Config.Colors.Gold, ZIndex = 4 }, slot)
	slot:SetAttribute("WasReady", true)
	return slot, st
end

-- Construction --------------------------------------------------------------------------

local function build()
	local gui = new("ScreenGui", { Name = "OnyxHUD", ResetOnSpawn = false, IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	ui.gui = gui

	-- Profil (haut gauche)
	local profile = glassFrame({ Size = UDim2.fromOffset(300, 118), Position = UDim2.new(0, 14, 0, 14) }, gui, Config.Colors.Gold)
	ui.charIcon = label({ Size = UDim2.fromOffset(52, 52), Position = UDim2.new(0, 10, 0, 10), Text = "🥊", TextStrokeTransparency = 1 }, profile)
	ui.levelText = label({ Size = UDim2.new(1, -76, 0, 26), Position = UDim2.new(0, 68, 0, 8), Text = "Niveau 1", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Config.Colors.Gold }, profile)
	ui.titleText = label({ Size = UDim2.new(1, -76, 0, 20), Position = UDim2.new(0, 68, 0, 36), Text = "", Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(220, 220, 235) }, profile)
	local xpBg = new("Frame", { Size = UDim2.new(1, -20, 0, 10), Position = UDim2.new(0, 10, 0, 66), BackgroundColor3 = Color3.fromRGB(40, 40, 55), BorderSizePixel = 0 }, profile)
	corner(xpBg, 5)
	ui.xpFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Config.Colors.Gold, BorderSizePixel = 0 }, xpBg)
	corner(ui.xpFill, 5)
	gradient(ui.xpFill, Color3.new(1, 1, 1), Color3.fromRGB(200, 150, 0), 0)
	ui.xpText = label({ Size = UDim2.new(1, -20, 0, 16), Position = UDim2.new(0, 10, 0, 78), Text = "", Font = FONT_BOLD, TextColor3 = Color3.fromRGB(200, 200, 215), TextXAlignment = Enum.TextXAlignment.Right }, profile)
	ui.recordText = label({ Size = UDim2.new(1, -20, 0, 22), Position = UDim2.new(0, 10, 0, 94), Text = "", Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(230, 230, 240) }, profile)

	-- Pieces
	local coinsFrame = glassFrame({ Size = UDim2.fromOffset(170, 40), Position = UDim2.new(0, 14, 0, 140) }, gui, Config.Colors.Gold)
	ui.coinsText = label({ Size = UDim2.new(1, -16, 1, -8), Position = UDim2.new(0, 8, 0, 4), Text = ICON.coins .. " 0", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Config.Colors.Gold }, coinsFrame)

	-- Boutons menus (haut droite)
	local right = new("Frame", { Size = UDim2.fromOffset(190, 110), Position = UDim2.new(1, -14, 0, 14), AnchorPoint = Vector2.new(1, 0), BackgroundTransparency = 1 }, gui)
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right }, right)
	ui.charButton = button({ Size = UDim2.fromOffset(190, 46), Text = ICON.character .. "  PERSONNAGE" .. (TOUCH and "" or "  C"), LayoutOrder = 1 }, right, Config.Colors.Accent)
	ui.cosmButton = button({ Size = UDim2.fromOffset(190, 46), Text = ICON.cosmetics .. "  COSMETIQUES" .. (TOUCH and "" or "  K"), LayoutOrder = 2 }, right, Config.Colors.Ult)

	-- Vie + ultimate (bas centre)
	local bars = new("Frame", { Size = UDim2.fromOffset(480, 62), Position = UDim2.new(0.5, 0, 1, -142), AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1 }, gui)
	local hpBg = new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Color3.fromRGB(20, 22, 32), BorderSizePixel = 0 }, bars)
	corner(hpBg, 10)
	stroke(hpBg, Color3.new(1, 1, 1), 2, 0.7)
	ui.hpGhost = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.3, BorderSizePixel = 0 }, hpBg)
	corner(ui.hpGhost, 10)
	ui.hpFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Config.Colors.Health, BorderSizePixel = 0, ZIndex = 2 }, hpBg)
	corner(ui.hpFill, 10)
	ui.hpGradient = gradient(ui.hpFill, Color3.new(1, 1, 1), Color3.fromRGB(120, 120, 120), 90)
	ui.hpText = label({ Size = UDim2.fromScale(1, 1), Text = "❤️ 100 / 100", Font = FONT_BOLD, ZIndex = 3 }, hpBg)
	local ultBg = new("Frame", { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 0, 36), BackgroundColor3 = Color3.fromRGB(20, 22, 32), BorderSizePixel = 0 }, bars)
	corner(ultBg, 10)
	ui.ultStroke = stroke(ultBg, Config.Colors.Ult, 2, 0.5)
	ui.ultFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Config.Colors.Ult, BorderSizePixel = 0 }, ultBg)
	corner(ui.ultFill, 10)
	ui.ultGradient = gradient(ui.ultFill, Color3.new(1, 1, 1), Config.Colors.Ult, 0)
	ui.ultText = label({ Size = UDim2.fromScale(1, 1), Text = ICON.ult .. " ULTIMATE 0 %", Font = FONT_BOLD, ZIndex = 3 }, ultBg)

	-- Competences (bas)
	local skills = new("Frame", { Name = "Skills", Size = UDim2.fromOffset(660, 104), Position = UDim2.new(0.5, 0, 1, -24), AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1 }, gui)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, skills)
	ui.slots = {}
	ui.slotStrokes = {}
	for i = 1, 4 do
		local slot, st = skillSlot(skills, i, tostring(i))
		ui.slots[i] = slot
		ui.slotStrokes[i] = st
		slot.Activated:Connect(function()
			Input.skill(i)
		end)
	end
	ui.ultButton = button({ Size = UDim2.fromOffset(96, 96), Text = ICON.ult .. "\nULT" .. (TOUCH and "" or " G"), LayoutOrder = 5 }, skills, Config.Colors.Ult)
	ui.ultButton.Activated:Connect(function()
		Input.ultimate()
	end)

	-- Boutons tactiles M1 / bloquer / dash
	if TOUCH then
		local touch = new("Frame", { Size = UDim2.fromOffset(230, 170), Position = UDim2.new(1, -20, 1, -150), AnchorPoint = Vector2.new(1, 1), BackgroundTransparency = 1 }, gui)
		local m1 = button({ Size = UDim2.fromOffset(116, 116), Position = UDim2.new(1, 0, 1, 0), AnchorPoint = Vector2.new(1, 1), Text = ICON.m1 .. "\nM1" }, touch, Config.Colors.Accent2)
		m1.Activated:Connect(function()
			Input.m1()
		end)
		local dash = button({ Size = UDim2.fromOffset(84, 84), Position = UDim2.new(0, 0, 1, 0), AnchorPoint = Vector2.new(0, 1), Text = ICON.dash .. "\nDASH" }, touch, Config.Colors.Accent)
		dash.Activated:Connect(function()
			Input.dash()
		end)
		local block = button({ Size = UDim2.fromOffset(84, 64), Position = UDim2.new(0, 0, 0, 0), Text = ICON.block .. " BLOC" }, touch, Config.Colors.Gold)
		block.MouseButton1Down:Connect(function()
			Input.setBlock(true)
		end)
		block.MouseButton1Up:Connect(function()
			Input.setBlock(false)
		end)
		block.MouseLeave:Connect(function()
			Input.setBlock(false)
		end)
	end

	-- Combo + etat + dash
	ui.combo = label({ Size = UDim2.fromOffset(320, 56), Position = UDim2.new(0.5, 0, 0.6, 0), AnchorPoint = Vector2.new(0.5, 0.5), Text = "", TextColor3 = Config.Colors.Accent2, Visible = false, TextStrokeTransparency = 0.3 }, gui)
	gradient(ui.combo, Color3.new(1, 1, 1), Config.Colors.Accent2, 90)
	ui.status = label({ Size = UDim2.fromOffset(400, 34), Position = UDim2.new(0.5, 0, 0.69, 0), AnchorPoint = Vector2.new(0.5, 0.5), Text = "", Font = FONT_BOLD, TextColor3 = Config.Colors.Gold }, gui)
	local dashFrame = glassFrame({ Size = UDim2.fromOffset(150, 32), Position = UDim2.new(0.5, 0, 1, -210), AnchorPoint = Vector2.new(0.5, 1) }, gui, Config.Colors.Accent)
	ui.dashFrame = dashFrame
	ui.dashFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Config.Colors.Accent, BackgroundTransparency = 0.6, BorderSizePixel = 0 }, dashFrame)
	corner(ui.dashFill, 14)
	ui.dashHint = label({ Size = UDim2.fromScale(1, 1), Text = "", Font = FONT_BOLD, ZIndex = 2 }, dashFrame)

	-- Notifications
	ui.toasts = new("Frame", { Size = UDim2.fromOffset(600, 230), Position = UDim2.new(0.5, 0, 0, 18), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1 }, gui)
	new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, ui.toasts)

	-- Intro
	ui.intro = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Config.Colors.Panel2, BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 20, Visible = false }, gui)
	gradient(ui.intro, Config.Colors.Panel2, Color3.fromRGB(40, 10, 60), 45)
	ui.introTitle = label({ Size = UDim2.fromOffset(900, 110), Position = UDim2.new(0.5, 0, 0.4, 0), AnchorPoint = Vector2.new(0.5, 0.5), Text = "⚔️ " .. Config.GameName .. " ⚔️", TextColor3 = Config.Colors.Accent, ZIndex = 21, TextStrokeTransparency = 0.2 }, ui.intro)
	gradient(ui.introTitle, Color3.new(1, 1, 1), Config.Colors.Accent, 90)
	ui.introSub = label({ Size = UDim2.fromOffset(700, 40), Position = UDim2.new(0.5, 0, 0.52, 0), AnchorPoint = Vector2.new(0.5, 0.5), Text = "Choisis ton personnage et domine l'arene", Font = FONT_BOLD, TextColor3 = Color3.fromRGB(230, 230, 240), ZIndex = 21 }, ui.intro)

	-- Panneaux
	ui.characters = panel("Characters", UDim2.fromOffset(700, 470), "CHOISIS TON PERSONNAGE", ICON.character, Config.Colors.Accent, gui)
	ui.charGrid = new("Frame", { Size = UDim2.new(1, -24, 1, -72), Position = UDim2.new(0, 12, 0, 62), BackgroundTransparency = 1 }, ui.characters)
	new("UIGridLayout", { CellSize = UDim2.fromOffset(326, 190), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, ui.charGrid)

	ui.cosmetics = panel("Cosmetics", UDim2.fromOffset(600, 540), "COSMETIQUES", ICON.cosmetics, Config.Colors.Ult, gui)
	ui.cosmList = scrollList(ui.cosmetics, 64)
end

-- Notifications ----------------------------------------------------------------------

local toastCount = 0
function HUD.toast(text, kind)
	toastCount += 1
	local styles = {
		danger = { Config.Colors.Danger, ICON.warning },
		gold = { Config.Colors.Gold, ICON.wins },
		good = { Config.Colors.Accent, "✅" },
		kill = { Config.Colors.Accent2, ICON.kills },
		ult = { Config.Colors.Ult, ICON.ult },
		info = { Color3.fromRGB(200, 200, 215), "ℹ️" },
	}
	local style = styles[kind] or styles.info
	local frame = glassFrame({ Size = UDim2.new(1, 0, 0, 40), LayoutOrder = toastCount, BackgroundTransparency = 0.15 }, ui.toasts, style[1])
	local l = label({ Size = UDim2.new(1, -20, 1, -10), Position = UDim2.new(0, 10, 0, 5), Text = style[2] .. "  " .. text, TextColor3 = style[1], Font = FONT_BOLD }, frame)
	frame.Size = UDim2.new(1, 0, 0, 0)
	TweenService:Create(frame, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(1, 0, 0, 40) }):Play()
	task.delay(3.5, function()
		TweenService:Create(frame, TweenInfo.new(0.4), { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0) }):Play()
		TweenService:Create(l, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.45)
		frame:Destroy()
	end)
end

-- Personnages ------------------------------------------------------------------------------

local function statBar(parent, y, text, ratio, color)
	label({ Size = UDim2.new(0.38, 0, 0, 16), Position = UDim2.new(0, 10, 0, y), Text = text, Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(210, 210, 225) }, parent)
	local bg = new("Frame", { Size = UDim2.new(0.56, -14, 0, 8), Position = UDim2.new(0.42, 0, 0, y + 4), BackgroundColor3 = Color3.fromRGB(40, 40, 55), BorderSizePixel = 0 }, parent)
	corner(bg, 4)
	local fill = new("Frame", { Size = UDim2.fromScale(math.clamp(ratio, 0.05, 1), 1), BackgroundColor3 = color, BorderSizePixel = 0 }, bg)
	corner(fill, 4)
end

local function rebuildCharacters()
	for _, child in ipairs(ui.charGrid:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, def in ipairs(Config.Characters) do
		local selected = State.stats.character == def.id
		local card = new("Frame", { BackgroundColor3 = Config.Colors.Panel, LayoutOrder = i, BorderSizePixel = 0 }, ui.charGrid)
		corner(card, 14)
		gradient(card, def.color:Lerp(Config.Colors.Panel, 0.65), Config.Colors.Panel2, 90)
		stroke(card, selected and Config.Colors.Gold or def.color, selected and 4 or 2)
		label({ Size = UDim2.fromOffset(60, 60), Position = UDim2.new(0, 8, 0, 6), Text = def.icon or "🥊", TextStrokeTransparency = 1 }, card)
		label({ Size = UDim2.new(1, -80, 0, 30), Position = UDim2.new(0, 72, 0, 8), Text = def.name .. (selected and "  ✔" or ""), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = def.color }, card)
		label({ Size = UDim2.new(1, -80, 0, 18), Position = UDim2.new(0, 72, 0, 40), Text = def.description, Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(210, 210, 225) }, card)
		statBar(card, 68, "❤️ Vie " .. def.health, def.health / 150, Config.Colors.Health)
		statBar(card, 88, "💨 Vitesse " .. def.walkSpeed, def.walkSpeed / 22, Config.Colors.Accent)
		statBar(card, 108, "👊 M1 " .. def.m1Damage, def.m1Damage / 12, Config.Colors.Accent2)
		local icons = {}
		for _, s in ipairs(def.skills) do
			table.insert(icons, (s.icon or "") .. " " .. s.name)
		end
		label({ Size = UDim2.new(1, -16, 0, 18), Position = UDim2.new(0, 8, 0, 130), Text = table.concat(icons, "   "), Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(235, 235, 245) }, card)
		local b = button({ Size = UDim2.new(1, -16, 0, 32), Position = UDim2.new(0, 8, 1, -40), Text = selected and "✔ SELECTIONNE" or "CHOISIR " .. (def.icon or "") }, card, selected and Color3.fromRGB(70, 70, 85) or def.color)
		b.Activated:Connect(function()
			Remotes.Menu:FireServer("character", def.id)
			HUD.hidePanel(ui.characters)
		end)
	end
end

-- Cosmetiques ------------------------------------------------------------------------------

local function rebuildCosmetics()
	for _, child in ipairs(ui.cosmList:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local order = 0
	local function section(icon, title, kind, list, equipped, bag, color)
		order += 1
		label({ Size = UDim2.new(1, 0, 0, 30), Text = icon .. "  " .. title, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = color, LayoutOrder = order }, ui.cosmList)
		for _, item in ipairs(list) do
			order += 1
			local owned = bag[item.id] == true
			local isEquipped = equipped == item.id
			local row = glassFrame({ Size = UDim2.new(1, 0, 0, 48), LayoutOrder = order }, ui.cosmList, isEquipped and Config.Colors.Gold or (item.color or Color3.fromRGB(90, 90, 110)))
			if item.color then
				local dot = new("Frame", { Size = UDim2.fromOffset(26, 26), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = item.color, BorderSizePixel = 0 }, row)
				corner(dot, 13)
				gradient(dot, Color3.new(1, 1, 1), item.color, 90)
			else
				label({ Size = UDim2.fromOffset(26, 26), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Text = kind == "title" and ICON.title or "⭕", TextStrokeTransparency = 1 }, row)
			end
			label({ Size = UDim2.new(0.48, 0, 1, -14), Position = UDim2.new(0, 46, 0, 7), Text = item.name, Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left }, row)
			local info
			if kind == "title" then
				local req = item.requirement
				info = (req.kind == "level" and (ICON.level .. " Niveau " .. req.value)) or (req.kind == "kills" and (ICON.kills .. " " .. req.value .. " kills")) or (ICON.wins .. " " .. req.value .. " victoires")
			else
				info = owned and "✔ Possede" or (ICON.coins .. " " .. item.price)
			end
			label({ Size = UDim2.new(0.26, 0, 1, -14), Position = UDim2.new(0.5, 0, 0, 7), Text = info, Font = FONT_BOLD, TextColor3 = Color3.fromRGB(200, 200, 215) }, row)
			local text = isEquipped and "✔ EQUIPE" or (owned and "EQUIPER" or (kind == "title" and "🔒" or "ACHETER"))
			local color2 = isEquipped and Color3.fromRGB(70, 70, 85) or (owned and Config.Colors.Accent or (kind == "title" and Color3.fromRGB(80, 80, 95) or Config.Colors.Gold))
			local b = button({ Size = UDim2.fromOffset(104, 34), Position = UDim2.new(1, -8, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Text = text }, row, color2)
			b.Activated:Connect(function()
				if isEquipped then
					return
				end
				if owned then
					Remotes.Menu:FireServer("equip", kind, item.id)
				elseif kind ~= "title" then
					Remotes.Menu:FireServer("buy", kind, item.id)
				end
			end)
		end
	end
	local s = State.stats
	section(ICON.aura, "AURAS", "aura", Config.Auras, s.aura, s.unlocked.auras or {}, Config.Colors.Accent)
	section(ICON.trail, "EFFETS DE DASH", "trail", Config.Trails, s.trail, s.unlocked.trails or {}, Config.Colors.Accent2)
	section(ICON.title, "TITRES", "title", Config.Titles, s.title, s.unlocked.titles or {}, Config.Colors.Gold)
end

-- Mises a jour ------------------------------------------------------------------------------

local function titleName(id)
	for _, t in ipairs(Config.Titles) do
		if t.id == id then
			return t.name
		end
	end
	return ""
end

local function onStats(stats)
	State.stats = stats
	local def = Config.CharacterById[stats.character] or Config.Characters[1]
	ui.charIcon.Text = def.icon or "🥊"
	ui.levelText.Text = ICON.level .. " Niveau " .. stats.level .. "  ·  " .. def.name
	ui.levelText.TextColor3 = def.color
	ui.titleText.Text = ICON.title .. " " .. titleName(stats.title)
	TweenService:Create(ui.xpFill, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(math.clamp(stats.xp / math.max(1, stats.xpNext), 0, 1), 1) }):Play()
	ui.xpText.Text = ICON.xp .. " " .. stats.xp .. " / " .. stats.xpNext .. " XP"
	ui.coinsText.Text = ICON.coins .. " " .. stats.coins
	ui.recordText.Text = string.format("%s %d   %s %d   %s %d", ICON.kills, stats.kills, ICON.wins, stats.wins, ICON.deaths, stats.deaths)
	if ui.characters.Visible then
		rebuildCharacters()
	end
	if ui.cosmetics.Visible then
		rebuildCosmetics()
	end
	State.fire("stats", stats)
end

local function refreshSkillNames()
	local character = player.Character
	local id = (character and character:GetAttribute("CharacterId")) or State.stats.character
	local def = Config.CharacterById[id] or Config.Characters[1]
	local ult = character and character:GetAttribute("UltActive") == true
	local list = ult and def.ultSkills or def.skills
	for i = 1, 4 do
		local skill = list[i]
		ui.slots[i].Title.Text = skill and skill.name or ""
		ui.slots[i].Icon.Text = skill and (skill.icon or "👊") or ""
		ui.slotStrokes[i].Color = ult and Config.Colors.Ult or def.color
		ui.slots[i].Glow.BackgroundColor3 = ult and Config.Colors.Ult or def.color
	end
	ui.charIcon.Text = def.icon or "🥊"
end

local function toggle(name)
	if name == "close" then
		if ui.characters.Visible then
			HUD.hidePanel(ui.characters)
		end
		if ui.cosmetics.Visible then
			HUD.hidePanel(ui.cosmetics)
		end
	elseif name == "characters" then
		if ui.characters.Visible then
			HUD.hidePanel(ui.characters)
		else
			rebuildCharacters()
			HUD.showPanel(ui.characters)
			if ui.cosmetics.Visible then
				HUD.hidePanel(ui.cosmetics)
			end
		end
	elseif name == "cosmetics" then
		if ui.cosmetics.Visible then
			HUD.hidePanel(ui.cosmetics)
		else
			rebuildCosmetics()
			Remotes.Menu:FireServer("stats")
			HUD.showPanel(ui.cosmetics)
			if ui.characters.Visible then
				HUD.hidePanel(ui.characters)
			end
		end
	end
end

local lastHp = 1
local function update(dt)
	local now = os.clock()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local ratio = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
		ui.hpFill.Size = UDim2.fromScale(ratio, 1)
		ui.hpFill.BackgroundColor3 = Config.Colors.Health:Lerp(Config.Colors.Danger, 1 - ratio)
		-- Barre fantome qui suit avec retard
		if ratio < lastHp then
			lastHp = math.max(ratio, lastHp - dt * 0.6)
		else
			lastHp = ratio
		end
		ui.hpGhost.Size = UDim2.fromScale(lastHp, 1)
		ui.hpText.Text = "❤️ " .. math.floor(humanoid.Health) .. " / " .. math.floor(humanoid.MaxHealth)

		local ult = character:GetAttribute("Ult") or 0
		local active = character:GetAttribute("UltActive") == true
		ui.ultFill.Size = UDim2.fromScale(ult / 100, 1)
		ui.ultGradient.Offset = Vector2.new((now * 0.6) % 2 - 1, 0)
		if active then
			ui.ultText.Text = ICON.ult .. " ULTIMATE MODE " .. math.floor(ult) .. " %"
			ui.ultFill.BackgroundColor3 = Config.Colors.Gold
			ui.ultStroke.Color = Config.Colors.Gold
		elseif ult >= 100 then
			ui.ultText.Text = ICON.ult .. " ULTIMATE PRET !" .. (TOUCH and "" or "  (G)")
			ui.ultFill.BackgroundColor3 = Config.Colors.Ult:Lerp(Color3.new(1, 1, 1), 0.5 + 0.5 * math.sin(now * 8))
			ui.ultStroke.Color = Color3.new(1, 1, 1)
			ui.ultStroke.Transparency = 0.2 + 0.3 * math.sin(now * 8)
			local scale = 1 + 0.06 * math.sin(now * 8)
			ui.ultButton.Size = UDim2.fromOffset(96 * scale, 96 * scale)
		else
			ui.ultText.Text = ICON.ult .. " ULTIMATE " .. math.floor(ult) .. " %"
			ui.ultFill.BackgroundColor3 = Config.Colors.Ult
			ui.ultStroke.Color = Config.Colors.Ult
			ui.ultStroke.Transparency = 0.5
			ui.ultButton.Size = UDim2.fromOffset(96, 96)
		end
		ui.ultButton.BackgroundColor3 = (ult >= 100 and not active) and Config.Colors.Gold or Config.Colors.Ult

		local stunned = (character:GetAttribute("StunUntil") or 0) > now
		if stunned then
			ui.status.Text = "💫 ETOURDI"
			ui.status.TextColor3 = Config.Colors.Danger
		elseif State.blocking then
			ui.status.Text = ICON.block .. " BLOCAGE"
			ui.status.TextColor3 = Config.Colors.Gold
		else
			ui.status.Text = ""
		end
	end

	for i = 1, 4 do
		local cd = State.cooldowns[i]
		local slot = ui.slots[i]
		local ready = not (cd and cd.untilTime > now)
		if not ready then
			local left = cd.untilTime - now
			slot.Cooldown.Size = UDim2.fromScale(1, math.clamp(left / cd.duration, 0, 1))
			slot.Timer.Text = string.format("%.1f", left)
			slot.Icon.TextTransparency = 0.5
			slot.Glow.BackgroundTransparency = 1
		else
			slot.Cooldown.Size = UDim2.fromScale(1, 0)
			slot.Timer.Text = ""
			slot.Icon.TextTransparency = 0
			slot.Glow.BackgroundTransparency = 0.88 + 0.08 * math.sin(now * 3 + i)
		end
		if ready and not slot:GetAttribute("WasReady") then
			-- Flash "pret"
			slot.Size = UDim2.fromOffset(110, 110)
			TweenService:Create(slot, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(96, 96) }):Play()
			slot.Glow.BackgroundTransparency = 0.3
		end
		slot:SetAttribute("WasReady", ready)
	end

	local dashLeft = State.dashReadyAt - now
	if dashLeft > 0 then
		ui.dashHint.Text = ICON.dash .. string.format(" %.1fs", dashLeft)
		ui.dashFill.Size = UDim2.fromScale(1 - math.clamp(dashLeft / C.DashCooldown, 0, 1), 1)
	else
		ui.dashHint.Text = ICON.dash .. " DASH PRET" .. (TOUCH and "" or "  Q")
		ui.dashFill.Size = UDim2.fromScale(1, 1)
	end
	if now - State.comboAt > C.ComboReset then
		ui.combo.Visible = false
	end
end

function HUD.showCombo(count)
	State.combo = count
	State.comboAt = os.clock()
	local words = { "HIT", "DOUBLE", "TRIPLE", "SMASH !" }
	ui.combo.Text = (count >= 4 and "💥 " or "👊 ") .. count .. " " .. (words[count] or "HITS")
	ui.combo.Visible = true
	ui.combo.Size = UDim2.fromOffset(220, 36)
	ui.combo.Rotation = (math.random() - 0.5) * 8
	TweenService:Create(ui.combo, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(320, 56), Rotation = 0 }):Play()
end

function HUD.playIntro()
	ui.intro.Visible = true
	ui.intro.BackgroundTransparency = 0.2
	ui.introTitle.TextTransparency = 1
	ui.introTitle.Position = UDim2.new(0.5, 0, 0.3, 0)
	ui.introSub.TextTransparency = 1
	TweenService:Create(ui.introTitle, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextTransparency = 0, Position = UDim2.new(0.5, 0, 0.4, 0) }):Play()
	task.delay(0.4, function()
		TweenService:Create(ui.introSub, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()
	end)
	task.delay(2.4, function()
		TweenService:Create(ui.intro, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(ui.introTitle, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(ui.introSub, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		task.wait(0.7)
		ui.intro.Visible = false
	end)
end

function HUD.Init(inputModule)
	Input = inputModule
	build()
	Remotes.Stats.OnClientEvent:Connect(onStats)
	Remotes.Notify.OnClientEvent:Connect(HUD.toast)
	ui.charButton.Activated:Connect(function()
		toggle("characters")
	end)
	ui.cosmButton.Activated:Connect(function()
		toggle("cosmetics")
	end)
	State.Changed.Event:Connect(function(what, data)
		if what == "toggle" then
			toggle(data)
		elseif what == "notify" then
			HUD.toast(data.text, data.kind)
		elseif what == "respawn" then
			task.delay(0.5, refreshSkillNames)
		end
	end)
	local function hookCharacter(character)
		task.wait(0.3)
		refreshSkillNames()
		character:GetAttributeChangedSignal("UltActive"):Connect(refreshSkillNames)
		character:GetAttributeChangedSignal("CharacterId"):Connect(refreshSkillNames)
	end
	if player.Character then
		task.spawn(hookCharacter, player.Character)
	end
	player.CharacterAdded:Connect(hookCharacter)
	RunService.RenderStepped:Connect(update)
	task.delay(0.5, HUD.playIntro)
end

return HUD
