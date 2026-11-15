-- Interface PET RUSH : coins, pets, oeufs, index, zones, courses, cadeau du jour, notifications.

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
local State = require(script.Parent.State)

local HUD = {}
local ICON = Config.Icons

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local FONT = Enum.Font.FredokaOne
local FONT_BOLD = Enum.Font.GothamBold
local TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local ui = {}
local panels = {}

-- Helpers -------------------------------------------------------------------------------

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end
local function corner(p, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 12) }, p)
end
local function stroke(p, color, thickness, transparency)
	return new("UIStroke", { Color = color, Thickness = thickness or 2, Transparency = transparency or 0 }, p)
end
local function gradient(p, c1, c2, rotation)
	return new("UIGradient", { Color = ColorSequence.new(c1, c2), Rotation = rotation or 90 }, p)
end
local function label(props, parent)
	local base = { BackgroundTransparency = 1, Font = FONT, TextColor3 = Color3.new(1, 1, 1), TextScaled = true, TextStrokeTransparency = 0.75, TextStrokeColor3 = Color3.new(0, 0, 0) }
	for k, v in pairs(props) do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end
local function glass(props, parent, color)
	local base = { BackgroundColor3 = Config.Colors.Panel, BackgroundTransparency = 0.1, BorderSizePixel = 0 }
	for k, v in pairs(props) do
		base[k] = v
	end
	local f = new("Frame", base, parent)
	corner(f, 14)
	gradient(f, Config.Colors.Panel, Config.Colors.Panel2, 90)
	stroke(f, color or Config.Colors.Accent, 2, 0.3)
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
	gradient(b, Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170), 90)
	stroke(b, Color3.new(1, 1, 1), 1.5, 0.6)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5) }, b)
	b.MouseEnter:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.25) }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.15), { BackgroundColor3 = color }):Play()
	end)
	return b
end
local function panel(name, size, title, icon, color, parent)
	local frame = new("Frame", { Name = name, Size = size, Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Config.Colors.Panel, BackgroundTransparency = 0.04, Visible = false, BorderSizePixel = 0 }, parent)
	corner(frame, 20)
	gradient(frame, Config.Colors.Panel, Config.Colors.Panel2, 90)
	stroke(frame, color, 3, 0.1)
	local head = new("Frame", { Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = color, BackgroundTransparency = 0.7, BorderSizePixel = 0 }, frame)
	corner(head, 20)
	gradient(head, Color3.new(1, 1, 1), Color3.new(0, 0, 0), 0)
	local t = label({ Name = "Title", Size = UDim2.new(1, -80, 0, 36), Position = UDim2.new(0, 18, 0, 10), Text = icon .. "  " .. title, TextXAlignment = Enum.TextXAlignment.Left }, head)
	local close = button({ Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, -10, 0, 8), AnchorPoint = Vector2.new(1, 0), Text = "✕" }, head, Config.Colors.Danger)
	close.Activated:Connect(function()
		HUD.hide(frame)
	end)
	frame:SetAttribute("FullSize", size)
	panels[name] = frame
	ui[name .. "Title"] = t
	return frame
end
local function scrollList(parent, top, bottom)
	local scroll = new("ScrollingFrame", { Size = UDim2.new(1, -24, 1, -(top + (bottom or 12))), Position = UDim2.new(0, 12, 0, top), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, ScrollBarImageColor3 = Config.Colors.Accent, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.Y }, parent)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	return scroll
end
local function grid(parent, top, cell)
	local scroll = new("ScrollingFrame", { Size = UDim2.new(1, -24, 1, -(top + 12)), Position = UDim2.new(0, 12, 0, top), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, ScrollBarImageColor3 = Config.Colors.Accent, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.Y }, parent)
	new("UIGridLayout", { CellSize = cell, CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	return scroll
end

function HUD.show(frame)
	for _, other in pairs(panels) do
		if other ~= frame and other.Visible then
			other.Visible = false
		end
	end
	frame.Visible = true
	local size = frame:GetAttribute("FullSize")
	frame.Size = UDim2.fromOffset(size.X.Offset * 0.8, size.Y.Offset * 0.8)
	TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = size }):Play()
end
function HUD.hide(frame)
	local size = frame:GetAttribute("FullSize")
	local t = TweenService:Create(frame, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.fromOffset(size.X.Offset * 0.85, size.Y.Offset * 0.85) })
	t:Play()
	t.Completed:Connect(function()
		frame.Visible = false
		frame.Size = size
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
		if ui.rebuild[name] then
			ui.rebuild[name]()
		end
		HUD.show(frame)
	end
end

local function rarityOf(petId)
	return Config.RarityById[Config.PetById[petId].rarity]
end

local function statsText(petId, evo)
	local s = PetModel.Stats(petId, evo)
	return string.format("%s %d  %s %d  %s %d  %s %d", ICON.speed, s.speed, ICON.power, s.power, ICON.stamina, s.stamina, ICON.luck, s.luck)
end

-- Construction -------------------------------------------------------------------------------

local function build()
	local gui = new("ScreenGui", { Name = "PetHUD", ResetOnSpawn = false, IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	ui.gui = gui
	ui.rebuild = {}

	-- Barre du haut (gauche)
	local top = glass({ Size = UDim2.fromOffset(330, 92), Position = UDim2.new(0, 14, 0, 14) }, gui, Config.Colors.Gold)
	ui.coins = label({ Size = UDim2.new(1, -16, 0, 40), Position = UDim2.new(0, 10, 0, 6), Text = ICON.coins .. " 0", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Config.Colors.Gold }, top)
	ui.power = label({ Size = UDim2.new(1, -16, 0, 22), Position = UDim2.new(0, 10, 0, 46), Text = "", Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Config.Colors.Accent }, top)
	ui.stats = label({ Size = UDim2.new(1, -16, 0, 18), Position = UDim2.new(0, 10, 0, 68), Text = "", Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(210, 210, 225) }, top)

	-- Boutons menu (droite)
	local right = new("Frame", { Size = UDim2.fromOffset(176, 300), Position = UDim2.new(1, -14, 0, 14), AnchorPoint = Vector2.new(1, 0), BackgroundTransparency = 1 }, gui)
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right }, right)
	local menuDefs = {
		{ "Pets", ICON.pets .. "  MES PETS", Config.Colors.Accent2, "P" },
		{ "Index", ICON.index .. "  INDEX", Config.Colors.Accent, "I" },
		{ "Zones", ICON.zone .. "  ZONES", Config.Colors.Grass, "Z" },
		{ "Race", ICON.race .. "  COURSES", Config.Colors.Gold, "R" },
	}
	ui.menuButtons = {}
	for i, def in ipairs(menuDefs) do
		local b = button({ Size = UDim2.fromOffset(176, 46), Text = def[2] .. (TOUCH and "" or "  " .. def[4]), LayoutOrder = i }, right, def[3])
		b.Activated:Connect(function()
			HUD.toggle(def[1])
		end)
		ui.menuButtons[def[1]] = b
	end
	ui.dailyButton = button({ Size = UDim2.fromOffset(176, 46), Text = ICON.daily .. "  CADEAU", LayoutOrder = 5, Visible = false }, right, Config.Colors.Gold)
	ui.dailyButton.Activated:Connect(function()
		Remotes.Pets:FireServer("daily")
	end)

	-- Pets equipes (bas gauche)
	ui.equippedBar = new("Frame", { Size = UDim2.fromOffset(330, 70), Position = UDim2.new(0, 14, 1, -14), AnchorPoint = Vector2.new(0, 1), BackgroundTransparency = 1 }, gui)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, ui.equippedBar)

	-- Zone actuelle (bas centre)
	ui.zoneLabel = label({ Size = UDim2.fromOffset(400, 30), Position = UDim2.new(0.5, 0, 1, -16), AnchorPoint = Vector2.new(0.5, 1), Text = "", Font = FONT_BOLD, TextColor3 = Color3.fromRGB(230, 230, 240) }, gui)

	-- Notifications
	ui.toasts = new("Frame", { Size = UDim2.fromOffset(620, 240), Position = UDim2.new(0.5, 0, 0, 16), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1 }, gui)
	new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, ui.toasts)

	-- Course en direct (haut centre sous les toasts)
	ui.raceLive = glass({ Size = UDim2.fromOffset(300, 150), Position = UDim2.new(1, -14, 0, 300), AnchorPoint = Vector2.new(1, 0), Visible = false }, gui, Config.Colors.Gold)
	ui.raceLiveTitle = label({ Size = UDim2.new(1, -16, 0, 26), Position = UDim2.new(0, 8, 0, 6), Text = "🏁 COURSE", TextColor3 = Config.Colors.Gold, TextXAlignment = Enum.TextXAlignment.Left }, ui.raceLive)
	ui.raceLiveList = label({ Size = UDim2.new(1, -16, 1, -40), Position = UDim2.new(0, 8, 0, 34), Text = "", Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextScaled = false, TextSize = 16 }, ui.raceLive)

	-- Panneaux
	local pets = panel("Pets", UDim2.fromOffset(760, 540), "MES PETS", ICON.pets, Config.Colors.Accent2, gui)
	ui.petsInfo = label({ Size = UDim2.new(1, -32, 0, 22), Position = UDim2.new(0, 16, 0, 60), Text = "", Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(210, 210, 225) }, pets)
	ui.petsGrid = grid(pets, 88, UDim2.fromOffset(232, 150))

	local index = panel("Index", UDim2.fromOffset(760, 540), "PET INDEX", ICON.index, Config.Colors.Accent, gui)
	ui.indexInfo = label({ Size = UDim2.new(1, -32, 0, 22), Position = UDim2.new(0, 16, 0, 60), Text = "", Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(210, 210, 225) }, index)
	ui.indexGrid = grid(index, 88, UDim2.fromOffset(140, 120))

	local zones = panel("Zones", UDim2.fromOffset(520, 400), "ZONES", ICON.zone, Config.Colors.Grass, gui)
	ui.zonesList = scrollList(zones, 64)

	local egg = panel("Egg", UDim2.fromOffset(520, 560), "OEUF", ICON.egg, Config.Colors.Accent2, gui)
	ui.eggList = scrollList(egg, 64, 70)
	ui.eggButton = button({ Size = UDim2.new(1, -24, 0, 50), Position = UDim2.new(0, 12, 1, -60), Text = "" }, egg, Config.Colors.Gold)
	ui.eggButton.Activated:Connect(function()
		if ui.currentEgg then
			Remotes.Pets:FireServer("hatch", ui.currentEgg)
		end
	end)

	local race = panel("Race", UDim2.fromOffset(640, 540), "COURSES DE PETS", ICON.race, Config.Colors.Gold, gui)
	ui.raceInfo = label({ Size = UDim2.new(1, -32, 0, 40), Position = UDim2.new(0, 16, 0, 60), Text = "", Font = FONT_BOLD, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(220, 220, 235) }, race)
	ui.raceTypes = new("Frame", { Size = UDim2.new(1, -24, 0, 70), Position = UDim2.new(0, 12, 0, 104), BackgroundTransparency = 1 }, race)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, ui.raceTypes)
	ui.racePets = grid(race, 184, UDim2.fromOffset(190, 100))
	ui.racePets.Size = UDim2.new(1, -24, 1, -250)
	ui.raceJoin = button({ Size = UDim2.new(1, -24, 0, 48), Position = UDim2.new(0, 12, 1, -58), Text = "" }, race, Config.Colors.Gold)
	ui.raceJoin.Activated:Connect(function()
		if ui.raceType and ui.racePet then
			Remotes.Race:FireServer("join", ui.raceType, ui.racePet)
		else
			HUD.toast("Choisis un type de course et un pet.", "info")
		end
	end)

	-- Eclosion plein ecran
	ui.hatch = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Config.Colors.Panel2, BackgroundTransparency = 0.25, Visible = false, ZIndex = 30, BorderSizePixel = 0 }, gui)
	ui.hatchEgg = label({ Size = UDim2.fromOffset(220, 220), Position = UDim2.new(0.5, 0, 0.45, 0), AnchorPoint = Vector2.new(0.5, 0.5), Text = "🥚", ZIndex = 31, TextStrokeTransparency = 1 }, ui.hatch)
	ui.hatchName = label({ Size = UDim2.fromOffset(700, 60), Position = UDim2.new(0.5, 0, 0.68, 0), AnchorPoint = Vector2.new(0.5, 0.5), Text = "", ZIndex = 31 }, ui.hatch)
	ui.hatchRarity = label({ Size = UDim2.fromOffset(500, 34), Position = UDim2.new(0.5, 0, 0.76, 0), AnchorPoint = Vector2.new(0.5, 0.5), Text = "", Font = FONT_BOLD, ZIndex = 31 }, ui.hatch)
	ui.hatchStats = label({ Size = UDim2.fromOffset(500, 26), Position = UDim2.new(0.5, 0, 0.82, 0), AnchorPoint = Vector2.new(0.5, 0.5), Text = "", Font = FONT_BOLD, ZIndex = 31, TextColor3 = Color3.fromRGB(220, 220, 235) }, ui.hatch)
end

-- Notifications ------------------------------------------------------------------------------

local toastCount = 0
function HUD.toast(text, kind)
	toastCount += 1
	local colors = { danger = Config.Colors.Danger, gold = Config.Colors.Gold, good = Config.Colors.Accent, info = Color3.fromRGB(210, 210, 225) }
	local color = colors[kind] or colors.info
	local frame = glass({ Size = UDim2.new(1, 0, 0, 40), LayoutOrder = toastCount, BackgroundTransparency = 0.15 }, ui.toasts, color)
	local l = label({ Size = UDim2.new(1, -20, 1, -10), Position = UDim2.new(0, 10, 0, 5), Text = text, TextColor3 = color, Font = FONT_BOLD }, frame)
	frame.Size = UDim2.new(1, 0, 0, 0)
	TweenService:Create(frame, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(1, 0, 0, 40) }):Play()
	task.delay(4, function()
		TweenService:Create(frame, TweenInfo.new(0.4), { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0) }):Play()
		TweenService:Create(l, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.45)
		frame:Destroy()
	end)
end

-- Carte de pet ---------------------------------------------------------------------------------

local function petCard(parent, pet, order, options)
	local def = Config.PetById[pet.id]
	local rarity = rarityOf(pet.id)
	local evo = Config.Evolutions[pet.evo]
	local card = new("Frame", { BackgroundColor3 = Config.Colors.Panel, LayoutOrder = order, BorderSizePixel = 0 }, parent)
	corner(card, 12)
	gradient(card, rarity.color:Lerp(Config.Colors.Panel, 0.7), Config.Colors.Panel2, 90)
	stroke(card, options.selected and Config.Colors.Gold or (evo.color or rarity.color), options.selected and 4 or 2)
	label({ Size = UDim2.fromOffset(54, 54), Position = UDim2.new(0, 6, 0, 6), Text = def.icon, TextStrokeTransparency = 1 }, card)
	label({ Size = UDim2.new(1, -70, 0, 24), Position = UDim2.new(0, 64, 0, 8), Text = (evo.icon ~= "" and evo.icon .. " " or "") .. pet.id, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = evo.color or Color3.new(1, 1, 1) }, card)
	label({ Size = UDim2.new(1, -70, 0, 18), Position = UDim2.new(0, 64, 0, 34), Text = rarity.icon .. " " .. rarity.name .. (evo.name ~= "" and ("  •  " .. evo.name) or ""), Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = rarity.color }, card)
	label({ Size = UDim2.new(1, -12, 0, 18), Position = UDim2.new(0, 6, 0, 62), Text = statsText(pet.id, pet.evo), Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(215, 215, 230) }, card)
	return card
end

-- Mes pets --------------------------------------------------------------------------------------

local function rebuildPets()
	for _, child in ipairs(ui.petsGrid:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local data = State.data
	ui.petsInfo.Text = string.format("%d / %d pets  •  %d / %d equipes  •  %s Puissance totale %d  •  %s %d exemplaires identiques = evolution", #data.pets, Config.MaxPets, #data.equipped, Config.MaxEquipped, ICON.power, data.power, ICON.evolve, Config.EvolveCost)
	local sorted = table.clone(data.pets)
	table.sort(sorted, function(a, b)
		local ra, rb = rarityOf(a.id).index, rarityOf(b.id).index
		if ra ~= rb then
			return ra > rb
		end
		if a.evo ~= b.evo then
			return a.evo > b.evo
		end
		return a.uid < b.uid
	end)
	local counts = {}
	for _, pet in ipairs(data.pets) do
		local k = pet.id .. ":" .. pet.evo
		counts[k] = (counts[k] or 0) + 1
	end
	for i, pet in ipairs(sorted) do
		local equipped = table.find(data.equipped, pet.uid) ~= nil
		local card = petCard(ui.petsGrid, pet, i, { selected = equipped })
		local eq = button({ Size = UDim2.new(0.5, -8, 0, 30), Position = UDim2.new(0, 6, 1, -36), Text = equipped and "✔ EQUIPE" or ICON.equip .. " EQUIPER" }, card, equipped and Color3.fromRGB(70, 70, 90) or Config.Colors.Accent)
		eq.Activated:Connect(function()
			Remotes.Pets:FireServer("equip", pet.uid)
		end)
		local same = counts[pet.id .. ":" .. pet.evo] or 0
		local canEvolve = same >= Config.EvolveCost and pet.evo < #Config.Evolutions
		local ev = button({ Size = UDim2.new(0.5, -8, 0, 30), Position = UDim2.new(0.5, 2, 1, -36), Text = pet.evo >= #Config.Evolutions and "🌌 MAX" or (ICON.evolve .. " " .. same .. "/" .. Config.EvolveCost) }, card, canEvolve and Config.Colors.Accent2 or Color3.fromRGB(70, 70, 90))
		ev.Activated:Connect(function()
			Remotes.Pets:FireServer("evolve", pet.uid)
		end)
		local del = button({ Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -4, 0, 4), AnchorPoint = Vector2.new(1, 0), Text = ICON.delete }, card, Config.Colors.Danger)
		del.Activated:Connect(function()
			Remotes.Pets:FireServer("delete", pet.uid)
		end)
	end
end

local function rebuildEquippedBar()
	for _, child in ipairs(ui.equippedBar:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, uid in ipairs(State.data.equipped) do
		local pet = State.petByUid(uid)
		if pet then
			local rarity = rarityOf(pet.id)
			local evo = Config.Evolutions[pet.evo]
			local slot = glass({ Size = UDim2.fromOffset(70, 70), LayoutOrder = i }, ui.equippedBar, evo.color or rarity.color)
			label({ Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 4), Text = Config.PetById[pet.id].icon, TextStrokeTransparency = 1 }, slot)
			label({ Size = UDim2.new(1, -4, 0, 16), Position = UDim2.new(0, 2, 1, -20), Text = (evo.icon ~= "" and evo.icon or rarity.icon) .. " " .. pet.id, Font = FONT_BOLD }, slot)
		end
	end
	for i = #State.data.equipped + 1, Config.MaxEquipped do
		local slot = glass({ Size = UDim2.fromOffset(70, 70), LayoutOrder = i, BackgroundTransparency = 0.5 }, ui.equippedBar, Color3.fromRGB(90, 90, 110))
		label({ Size = UDim2.fromScale(1, 1), Text = "+", TextColor3 = Color3.fromRGB(120, 120, 140) }, slot)
	end
end

-- Index ----------------------------------------------------------------------------------------

local function rebuildIndex()
	for _, child in ipairs(ui.indexGrid:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local found = 0
	for _, pet in ipairs(Config.Pets) do
		if State.data.index[pet.id] then
			found += 1
		end
	end
	ui.indexInfo.Text = string.format("%d / %d pets decouverts  •  %s %d oeufs ouverts", found, #Config.Pets, ICON.egg, State.data.hatched)
	for i, pet in ipairs(Config.Pets) do
		local known = State.data.index[pet.id] == true
		local rarity = Config.RarityById[pet.rarity]
		local egg = Config.EggById[pet.egg]
		local card = new("Frame", { BackgroundColor3 = Config.Colors.Panel, LayoutOrder = i, BorderSizePixel = 0 }, ui.indexGrid)
		corner(card, 12)
		gradient(card, known and rarity.color:Lerp(Config.Colors.Panel, 0.65) or Config.Colors.Panel, Config.Colors.Panel2, 90)
		stroke(card, known and rarity.color or Color3.fromRGB(70, 70, 90), 2)
		label({ Size = UDim2.new(1, 0, 0, 50), Position = UDim2.new(0, 0, 0, 6), Text = known and pet.icon or "❓", TextStrokeTransparency = 1, TextTransparency = known and 0 or 0.4 }, card)
		label({ Size = UDim2.new(1, -8, 0, 20), Position = UDim2.new(0, 4, 0, 58), Text = known and pet.id or "???", Font = FONT_BOLD, TextColor3 = known and Color3.new(1, 1, 1) or Color3.fromRGB(140, 140, 160) }, card)
		label({ Size = UDim2.new(1, -8, 0, 16), Position = UDim2.new(0, 4, 0, 80), Text = rarity.icon .. " " .. rarity.name, Font = FONT_BOLD, TextColor3 = rarity.color }, card)
		label({ Size = UDim2.new(1, -8, 0, 14), Position = UDim2.new(0, 4, 0, 98), Text = egg.icon .. " " .. egg.name, Font = FONT_BOLD, TextColor3 = Color3.fromRGB(190, 190, 210) }, card)
	end
end

-- Zones ----------------------------------------------------------------------------------------

local function rebuildZones()
	for _, child in ipairs(ui.zonesList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, zone in ipairs(Config.Zones) do
		local unlocked = State.data.zones[zone.id] == true
		local row = glass({ Size = UDim2.new(1, 0, 0, 72), LayoutOrder = i }, ui.zonesList, unlocked and zone.ground or Color3.fromRGB(90, 90, 110))
		label({ Size = UDim2.fromOffset(50, 50), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Text = zone.icon, TextStrokeTransparency = 1 }, row)
		label({ Size = UDim2.new(0.5, 0, 0, 28), Position = UDim2.new(0, 70, 0, 8), Text = zone.name, TextXAlignment = Enum.TextXAlignment.Left }, row)
		local egg = Config.Eggs[i]
		label({ Size = UDim2.new(0.55, 0, 0, 18), Position = UDim2.new(0, 70, 0, 40), Text = ICON.coins .. " " .. zone.coinValue .. " / coin   " .. egg.icon .. " oeuf " .. egg.price, Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(210, 210, 225) }, row)
		local b = button({ Size = UDim2.fromOffset(150, 40), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Text = unlocked and "➡️ Y ALLER" or (ICON.lock .. " " .. zone.price) }, row, unlocked and Config.Colors.Accent or Config.Colors.Gold)
		b.Activated:Connect(function()
			if unlocked then
				Remotes.Pets:FireServer("teleport", zone.id)
				HUD.hide(panels.Zones)
			else
				Remotes.Pets:FireServer("unlock", zone.id)
			end
		end)
	end
end

-- Oeuf -----------------------------------------------------------------------------------------

function HUD.openEgg(eggId)
	local egg = Config.EggById[eggId]
	if not egg then
		return
	end
	ui.currentEgg = eggId
	ui.EggTitle.Text = egg.icon .. "  " .. egg.name
	for _, child in ipairs(ui.eggList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	-- Chances (avec la chance des pets equipes)
	local luck = 0
	for _, uid in ipairs(State.data.equipped) do
		local pet = State.petByUid(uid)
		if pet then
			luck += PetModel.Stats(pet.id, pet.evo).luck
		end
	end
	local luckMult = 1 + math.min(luck, 300) / 150
	local pool, total = {}, 0
	for _, pet in ipairs(Config.Pets) do
		if pet.egg == eggId then
			local rarity = Config.RarityById[pet.rarity]
			local weight = rarity.weight * (rarity.index >= 3 and luckMult or 1)
			table.insert(pool, { pet = pet, weight = weight })
			total += weight
		end
	end
	for i, entry in ipairs(pool) do
		local pet = entry.pet
		local rarity = Config.RarityById[pet.rarity]
		local known = State.data.index[pet.id]
		local row = glass({ Size = UDim2.new(1, 0, 0, 50), LayoutOrder = i }, ui.eggList, rarity.color)
		label({ Size = UDim2.fromOffset(40, 40), Position = UDim2.new(0, 8, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Text = known and pet.icon or "❓", TextStrokeTransparency = 1 }, row)
		label({ Size = UDim2.new(0.45, 0, 0, 24), Position = UDim2.new(0, 56, 0, 5), Text = known and pet.id or "???", TextXAlignment = Enum.TextXAlignment.Left }, row)
		label({ Size = UDim2.new(0.45, 0, 0, 16), Position = UDim2.new(0, 56, 0, 30), Text = rarity.icon .. " " .. rarity.name, Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = rarity.color }, row)
		local pct = entry.weight / total * 100
		label({ Size = UDim2.new(0.3, -10, 1, -12), Position = UDim2.new(0.7, 0, 0, 6), Text = pct >= 1 and string.format("%.1f %%", pct) or string.format("%.2f %%", pct), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = rarity.color }, row)
	end
	ui.eggButton.Text = ICON.egg .. "  OUVRIR  •  " .. ICON.coins .. " " .. egg.price .. (luck > 0 and ("   " .. ICON.luck .. " +" .. math.floor((luckMult - 1) * 100) .. " %") or "")
	HUD.show(panels.Egg)
end

-- Courses ---------------------------------------------------------------------------------------

local function rebuildRace()
	for _, child in ipairs(ui.raceTypes:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for _, child in ipairs(ui.racePets:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, t in ipairs(Config.Race.Types) do
		local selected = ui.raceType == t.id
		local b = button({ Size = UDim2.new(0.5, -5, 1, 0), Text = t.icon .. " " .. t.name .. "\n" .. t.description .. "  •  " .. ICON.coins .. " " .. t.reward, LayoutOrder = i }, ui.raceTypes, selected and Config.Colors.Gold or Color3.fromRGB(70, 70, 90))
		b.Activated:Connect(function()
			ui.raceType = t.id
			rebuildRace()
		end)
	end
	for i, pet in ipairs(State.data.pets) do
		local card = petCard(ui.racePets, pet, i, { selected = ui.racePet == pet.uid })
		local b = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 5 }, card)
		b.Activated:Connect(function()
			ui.racePet = pet.uid
			rebuildRace()
		end)
	end
	local race = State.race
	if race.phase == "Idle" then
		ui.raceInfo.Text = "Aucune course en cours. Choisis un type et un pet, puis lance la course : les autres joueurs ont " .. Config.Race.LobbyTime .. " s pour te rejoindre. Les places vides sont prises par des bots."
		ui.raceJoin.Text = ICON.race .. "  LANCER / REJOINDRE"
	elseif race.phase == "Lobby" then
		ui.raceInfo.Text = "🏁 Course " .. tostring(race.type) .. " en preparation : " .. #race.racers .. " / " .. Config.Race.MaxRacers .. " inscrits. Rejoins maintenant !"
		ui.raceJoin.Text = ICON.race .. "  REJOINDRE"
	else
		ui.raceInfo.Text = "Course en cours, regarde la piste !"
		ui.raceJoin.Text = "⏳ EN COURS"
	end
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
	local lines = {}
	if race.phase == "Lobby" then
		ui.raceLiveTitle.Text = "🏁 LOBBY " .. tostring(race.type)
		for _, r in ipairs(race.racers) do
			table.insert(lines, Config.PetById[r.petId].icon .. " " .. r.name)
		end
	elseif race.phase == "Countdown" then
		ui.raceLiveTitle.Text = "🏁 DEPART IMMINENT"
		for _, r in ipairs(race.racers) do
			table.insert(lines, Config.PetById[r.petId].icon .. " " .. r.name)
		end
	elseif race.phase == "Racing" then
		ui.raceLiveTitle.Text = "🏁 COURSE " .. tostring(race.type)
		local sorted = table.clone(race.racers)
		table.sort(sorted, function(a, b)
			return (a.progress or 0) > (b.progress or 0)
		end)
		for i, r in ipairs(sorted) do
			local pct = race.total and math.floor((r.progress or 0) / race.total * 100) or 0
			table.insert(lines, string.format("%d. %s %s  %d%%", i, Config.PetById[r.petId].icon, r.name, pct))
		end
	else
		ui.raceLiveTitle.Text = "🏆 RESULTATS"
		local medals = { "🥇", "🥈", "🥉", "4." }
		for _, r in ipairs(race.results or race.racers) do
			table.insert(lines, (medals[r.rank] or "") .. " " .. Config.PetById[r.petId].icon .. " " .. r.name)
		end
	end
	ui.raceLiveList.Text = table.concat(lines, "\n")
end

-- Eclosion ---------------------------------------------------------------------------------------

function HUD.playHatch(data)
	local def = Config.PetById[data.petId]
	local rarity = Config.RarityById[data.rarity]
	ui.hatch.Visible = true
	ui.hatchEgg.Text = Config.EggById[data.egg or "Village"].icon
	ui.hatchEgg.TextTransparency = 0
	ui.hatchName.Text = ""
	ui.hatchRarity.Text = ""
	ui.hatchStats.Text = ""
	task.spawn(function()
		for i = 1, 10 do
			ui.hatchEgg.Rotation = (i % 2 == 0) and 12 or -12
			ui.hatchEgg.Size = UDim2.fromOffset(220 + i * 6, 220 + i * 6)
			task.wait(0.09)
		end
		ui.hatchEgg.Rotation = 0
		ui.hatchEgg.Text = def.icon
		ui.hatchEgg.Size = UDim2.fromOffset(60, 60)
		TweenService:Create(ui.hatchEgg, TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(300, 300) }):Play()
		ui.hatchName.Text = def.id
		ui.hatchName.TextColor3 = rarity.color
		ui.hatchRarity.Text = rarity.icon .. " " .. rarity.name
		ui.hatchRarity.TextColor3 = rarity.color
		ui.hatchStats.Text = statsText(def.id, 1)
		task.wait(2.6)
		TweenService:Create(ui.hatch, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		task.wait(0.4)
		ui.hatch.Visible = false
		ui.hatch.BackgroundTransparency = 0.25
	end)
end

-- Mises a jour ----------------------------------------------------------------------------------

local function onSync(data)
	State.data = data
	ui.coins.Text = ICON.coins .. " " .. data.coins
	ui.power.Text = ICON.power .. " Puissance " .. data.power .. "   " .. ICON.pets .. " " .. #data.pets .. " pets"
	ui.stats.Text = string.format("%s %d courses gagnees   %s %d oeufs   %s %d total", ICON.trophy, data.raceWins, ICON.egg, data.hatched, ICON.coins, data.totalCoins)
	ui.dailyButton.Visible = data.dailyReady
	rebuildEquippedBar()
	if panels.Pets.Visible then
		rebuildPets()
	end
	if panels.Index.Visible then
		rebuildIndex()
	end
	if panels.Zones.Visible then
		rebuildZones()
	end
	if panels.Race.Visible then
		rebuildRace()
	end
	if panels.Egg.Visible and ui.currentEgg then
		HUD.openEgg(ui.currentEgg)
	end
	State.fire("sync", data)
end

local function isNear(tag, distance)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end
	for _, s in ipairs(CollectionService:GetTagged(tag)) do
		if (s.Position - hrp.Position).Magnitude <= distance then
			return true
		end
	end
	return false
end

function HUD.Init()
	build()
	ui.rebuild = { Pets = rebuildPets, Index = rebuildIndex, Zones = rebuildZones, Race = rebuildRace }
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
		local map = { [Enum.KeyCode.P] = "Pets", [Enum.KeyCode.I] = "Index", [Enum.KeyCode.Z] = "Zones", [Enum.KeyCode.R] = "Race" }
		local name = map[input.KeyCode]
		if name then
			HUD.toggle(name)
		elseif input.KeyCode == Enum.KeyCode.Escape then
			for _, f in pairs(panels) do
				if f.Visible then
					HUD.hide(f)
				end
			end
		end
	end)

	-- Zone actuelle + pulsation du bouton cadeau
	RunService.Heartbeat:Connect(function()
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local current
			for _, zone in ipairs(Config.Zones) do
				if math.abs(hrp.Position.X - zone.center.X) <= zone.size / 2 + 50 and math.abs(hrp.Position.Z - zone.center.Z) <= zone.size / 2 + 50 then
					current = zone
				end
			end
			ui.zoneLabel.Text = current and (current.icon .. " " .. current.name .. "   •   " .. ICON.coins .. " " .. current.coinValue .. " par coin") or ""
		end
		if ui.dailyButton.Visible then
			ui.dailyButton.Rotation = math.sin(os.clock() * 6) * 4
		end
	end)
	task.delay(1, function()
		Remotes.Pets:FireServer("sync")
		Remotes.Race:FireServer("state")
	end)
end

return HUD
