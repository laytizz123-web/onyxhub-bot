-- Interface : pieces, meteo, barre de graines, sac, boutique, agrandissement, notifications.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Economy = require(ReplicatedStorage.Shared.Economy)
local State = require(script.Parent.State)

local HUD = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local FONT = Enum.Font.FredokaOne
local FONT_BOLD = Enum.Font.GothamBold
local TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local ui = {}

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(parent, radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius or 10) }, parent)
end

local function stroke(parent, color, thickness, transparency)
	return new("UIStroke", { Color = color, Thickness = thickness or 2, Transparency = transparency or 0 }, parent)
end

local function label(props, parent)
	local base = {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		TextStrokeTransparency = 0.7,
		TextStrokeColor3 = Color3.new(0, 0, 0),
	}
	for k, v in pairs(props) do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end

local function button(props, parent)
	local base = {
		BackgroundColor3 = Config.Colors.Accent,
		Font = FONT,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		AutoButtonColor = true,
		Text = "",
	}
	for k, v in pairs(props) do
		base[k] = v
	end
	local b = new("TextButton", base, parent)
	corner(b, 10)
	return b
end

local function panel(name, size, parent)
	local frame = new("Frame", {
		Name = name,
		Size = size,
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Config.Colors.Dark,
		BackgroundTransparency = 0.08,
		Visible = false,
	}, parent)
	corner(frame, 18)
	stroke(frame, Config.Colors.Accent, 3, 0.2)
	local close = button({
		Size = UDim2.fromOffset(36, 36),
		Position = UDim2.new(1, -8, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Config.Colors.Danger,
		Text = "X",
	}, frame)
	close.Activated:Connect(function()
		frame.Visible = false
	end)
	return frame
end

local function scrollList(parent, top)
	local scroll = new("ScrollingFrame", {
		Size = UDim2.new(1, -24, 1, -(top + 12)),
		Position = UDim2.new(0, 12, 0, top),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, parent)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	return scroll
end

-- Construction ---------------------------------------------------------------

local function build()
	local gui = new("ScreenGui", { Name = "OnyxHUD", ResetOnSpawn = false, IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	ui.gui = gui

	-- Pieces (haut gauche)
	local coins = new("Frame", { Size = UDim2.fromOffset(230, 52), Position = UDim2.new(0, 14, 0, 14), BackgroundColor3 = Config.Colors.Dark, BackgroundTransparency = 0.2 }, gui)
	corner(coins, 14)
	stroke(coins, Config.Colors.Gold, 2, 0.2)
	ui.coins = label({ Size = UDim2.new(1, -16, 1, -10), Position = UDim2.new(0, 8, 0, 5), Text = "0 pieces", TextColor3 = Config.Colors.Gold, TextXAlignment = Enum.TextXAlignment.Left }, coins)
	ui.harvests = label({ Size = UDim2.fromOffset(230, 24), Position = UDim2.new(0, 14, 0, 70), Text = "", Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(230, 230, 230) }, gui)

	-- Meteo (haut centre)
	local weather = new("Frame", { Size = UDim2.fromOffset(320, 50), Position = UDim2.new(0.5, 0, 0, 14), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Config.Colors.Dark, BackgroundTransparency = 0.2 }, gui)
	corner(weather, 14)
	ui.weatherStroke = stroke(weather, Config.Colors.Sky, 2, 0.2)
	ui.weather = label({ Size = UDim2.new(1, -16, 1, -10), Position = UDim2.new(0, 8, 0, 5), Text = "Ciel clair", TextColor3 = Config.Colors.Sky }, weather)
	ui.restock = label({ Size = UDim2.fromOffset(320, 22), Position = UDim2.new(0.5, 0, 0, 68), AnchorPoint = Vector2.new(0.5, 0), Text = "", Font = FONT_BOLD, TextColor3 = Color3.fromRGB(230, 230, 230) }, gui)

	-- Boutons droite
	local right = new("Frame", { Size = UDim2.fromOffset(150, 200), Position = UDim2.new(1, -14, 0, 14), AnchorPoint = Vector2.new(1, 0), BackgroundTransparency = 1 }, gui)
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right }, right)
	ui.backpackButton = button({ Size = UDim2.fromOffset(150, 44), Text = TOUCH and "SAC" or "SAC (B)", BackgroundColor3 = Config.Colors.Accent2, LayoutOrder = 1 }, right)
	ui.shopButton = button({ Size = UDim2.fromOffset(150, 44), Text = "BOUTIQUE", BackgroundColor3 = Config.Colors.Accent, LayoutOrder = 2 }, right)
	ui.expandButton = button({ Size = UDim2.fromOffset(150, 44), Text = "AGRANDIR", BackgroundColor3 = Config.Colors.Gold, LayoutOrder = 3 }, right)
	ui.sellButton = button({ Size = UDim2.fromOffset(150, 44), Text = "VENDRE", BackgroundColor3 = Config.Colors.Gold, LayoutOrder = 4, Visible = false }, right)
	for _, b in ipairs({ ui.backpackButton, ui.shopButton, ui.expandButton, ui.sellButton }) do
		stroke(b, Color3.new(0, 0, 0), 2, 0.6)
	end

	-- Barre de graines (bas)
	local hotbar = new("Frame", { Name = "Hotbar", Size = UDim2.fromOffset(700, 86), Position = UDim2.new(0.5, 0, 1, -16), AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1 }, gui)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, hotbar)
	ui.hotbar = hotbar
	ui.hotbarHint = label({ Size = UDim2.fromOffset(700, 22), Position = UDim2.new(0.5, 0, 1, -106), AnchorPoint = Vector2.new(0.5, 1), Text = "", Font = FONT_BOLD, TextColor3 = Color3.fromRGB(235, 235, 235) }, gui)

	-- Notifications
	local toasts = new("Frame", { Name = "Toasts", Size = UDim2.fromOffset(520, 220), Position = UDim2.new(0.5, 0, 0, 100), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1 }, gui)
	new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, toasts)
	ui.toasts = toasts

	-- Panneau SAC
	ui.backpack = panel("Backpack", UDim2.fromOffset(460, 440), gui)
	label({ Size = UDim2.new(1, -60, 0, 36), Position = UDim2.new(0, 16, 0, 10), Text = "MON SAC", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Config.Colors.Accent2 }, ui.backpack)
	ui.backpackTotal = label({ Size = UDim2.new(1, -32, 0, 24), Position = UDim2.new(0, 16, 0, 48), Text = "", Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Config.Colors.Gold }, ui.backpack)
	ui.backpackList = scrollList(ui.backpack, 80)
	ui.backpackHint = label({ Size = UDim2.new(1, -32, 0, 22), Position = UDim2.new(0, 16, 1, -30), Text = "Va au stand VENTE pour tout vendre", Font = FONT_BOLD, TextColor3 = Color3.fromRGB(200, 200, 200) }, ui.backpack)
	ui.backpackList.Size = UDim2.new(1, -24, 1, -120)

	-- Panneau BOUTIQUE
	ui.shop = panel("Shop", UDim2.fromOffset(520, 520), gui)
	label({ Size = UDim2.new(1, -60, 0, 36), Position = UDim2.new(0, 16, 0, 10), Text = "BOUTIQUE DE GRAINES", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Config.Colors.Accent }, ui.shop)
	ui.shopRestock = label({ Size = UDim2.new(1, -32, 0, 24), Position = UDim2.new(0, 16, 0, 48), Text = "", Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(210, 210, 210) }, ui.shop)
	ui.shopList = scrollList(ui.shop, 80)
end

-- Notifications ---------------------------------------------------------------

local toastCount = 0
function HUD.toast(text, kind)
	toastCount += 1
	local colors = {
		danger = Config.Colors.Danger,
		gold = Config.Colors.Gold,
		good = Config.Colors.Accent,
		weather = Config.Colors.Sky,
		shop = Config.Colors.Accent2,
		mutation = Color3.fromRGB(255, 120, 255),
	}
	local color = colors[kind] or Color3.new(1, 1, 1)
	local frame = new("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = Config.Colors.Dark, BackgroundTransparency = 0.25, LayoutOrder = toastCount }, ui.toasts)
	corner(frame, 10)
	stroke(frame, color, 2, 0.3)
	local l = label({ Size = UDim2.new(1, -16, 1, -8), Position = UDim2.new(0, 8, 0, 4), Text = text, TextColor3 = color, Font = FONT_BOLD }, frame)
	task.delay(3.5, function()
		TweenService:Create(frame, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.45)
		frame:Destroy()
	end)
end

-- Barre de graines ----------------------------------------------------------------

local hotbarSlots = {}

local function rebuildHotbar()
	for _, slot in ipairs(hotbarSlots) do
		slot:Destroy()
	end
	hotbarSlots = {}
	local seeds = {}
	for _, plant in ipairs(Config.Plants) do
		local count = State.inventory.seeds[plant.id]
		if count and count > 0 then
			table.insert(seeds, { plant = plant, count = count })
		end
	end
	if State.selectedSeed and not State.inventory.seeds[State.selectedSeed] then
		State.selectedSeed = nil
	end
	if #seeds == 0 then
		ui.hotbarHint.Text = "Aucune graine : passe a la BOUTIQUE !"
	else
		ui.hotbarHint.Text = State.selectedSeed and ("Graine : " .. State.selectedSeed .. "  |  Clique sur une case de ta parcelle") or "Choisis une graine (clic ou touches 1-9)"
	end
	for i, entry in ipairs(seeds) do
		if i > 9 then
			break
		end
		local selected = State.selectedSeed == entry.plant.id
		local slot = button({
			Size = UDim2.fromOffset(78, 78),
			BackgroundColor3 = Config.Colors.Dark,
			BackgroundTransparency = selected and 0 or 0.3,
			LayoutOrder = i,
		}, ui.hotbar)
		stroke(slot, selected and Config.Colors.Gold or entry.plant.color, selected and 4 or 2)
		local dot = new("Frame", { Size = UDim2.fromOffset(26, 26), Position = UDim2.new(0.5, 0, 0, 10), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = entry.plant.color }, slot)
		corner(dot, 13)
		label({ Size = UDim2.new(1, -4, 0, 18), Position = UDim2.new(0, 2, 0, 40), Text = entry.plant.id, Font = FONT_BOLD }, slot)
		label({ Size = UDim2.new(1, -4, 0, 16), Position = UDim2.new(0, 2, 1, -18), Text = "x" .. entry.count, TextColor3 = Config.Colors.Gold, Font = FONT_BOLD }, slot)
		if not TOUCH then
			label({ Size = UDim2.fromOffset(16, 16), Position = UDim2.new(0, 4, 0, 2), Text = tostring(i), TextColor3 = Color3.fromRGB(200, 200, 200), Font = FONT_BOLD }, slot)
		end
		slot.Activated:Connect(function()
			State.selectedSeed = (State.selectedSeed == entry.plant.id) and nil or entry.plant.id
			rebuildHotbar()
		end)
		table.insert(hotbarSlots, slot)
	end
	ui.hotbarSeeds = seeds
end

-- Sac ---------------------------------------------------------------------------

local function rebuildBackpack()
	for _, child in ipairs(ui.backpackList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local fruits = State.inventory.fruits
	ui.backpackTotal.Text = #fruits .. " fruit(s)  |  Valeur : " .. Economy.formatCoins(State.inventory.fruitValue) .. " pieces"
	-- Tri par valeur decroissante
	local sorted = table.clone(fruits)
	table.sort(sorted, function(a, b)
		return a.value > b.value
	end)
	for i, fruit in ipairs(sorted) do
		if i > 60 then
			break
		end
		local plant = Config.PlantById[fruit.id]
		local row = new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Color3.fromRGB(40, 50, 42), LayoutOrder = i }, ui.backpackList)
		corner(row, 8)
		local hasMutation = fruit.mutations and #fruit.mutations > 0
		local dot = new("Frame", { Size = UDim2.fromOffset(22, 22), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = plant and plant.color or Color3.new(1, 1, 1) }, row)
		corner(dot, 11)
		label({ Size = UDim2.new(0.55, 0, 1, -10), Position = UDim2.new(0, 42, 0, 5), Text = Economy.fruitName(fruit), Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = hasMutation and Color3.fromRGB(255, 200, 255) or Color3.new(1, 1, 1) }, row)
		label({ Size = UDim2.new(0.18, 0, 1, -10), Position = UDim2.new(0.6, 0, 0, 5), Text = Economy.formatWeight(fruit.weight), Font = FONT_BOLD, TextColor3 = Color3.fromRGB(200, 200, 200) }, row)
		label({ Size = UDim2.new(0.2, -10, 1, -10), Position = UDim2.new(0.8, 0, 0, 5), Text = Economy.formatCoins(fruit.value), Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Config.Colors.Gold }, row)
	end
	if #sorted > 60 then
		label({ Size = UDim2.new(1, 0, 0, 24), Text = "... et " .. (#sorted - 60) .. " autres", Font = FONT_BOLD, LayoutOrder = 999 }, ui.backpackList)
	end
end

-- Boutique ---------------------------------------------------------------------------

local function rebuildShop()
	for _, child in ipairs(ui.shopList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, plant in ipairs(Config.Plants) do
		local stock = State.shop.stock[plant.id] or 0
		local row = new("Frame", { Size = UDim2.new(1, 0, 0, 58), BackgroundColor3 = stock > 0 and Color3.fromRGB(40, 50, 42) or Color3.fromRGB(45, 40, 40), LayoutOrder = i }, ui.shopList)
		corner(row, 8)
		local dot = new("Frame", { Size = UDim2.fromOffset(26, 26), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = plant.color }, row)
		corner(dot, 13)
		label({ Size = UDim2.new(0.42, 0, 0, 24), Position = UDim2.new(0, 46, 0, 6), Text = plant.id, TextXAlignment = Enum.TextXAlignment.Left }, row)
		local info = string.format("%s pieces  |  %ds  |  vend %s", Economy.formatCoins(plant.price), plant.growTime, Economy.formatCoins(plant.value))
		if plant.multi then
			info = info .. "  |  repousse"
		end
		label({ Size = UDim2.new(0.6, 0, 0, 18), Position = UDim2.new(0, 46, 0, 32), Text = info, Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(200, 200, 200) }, row)
		label({ Size = UDim2.new(0.14, 0, 0, 22), Position = UDim2.new(0.62, 0, 0, 6), Text = stock > 0 and ("Stock " .. stock) or "Epuise", Font = FONT_BOLD, TextColor3 = stock > 0 and Config.Colors.Accent or Config.Colors.Danger }, row)
		if stock > 0 then
			local b1 = button({ Size = UDim2.fromOffset(44, 36), Position = UDim2.new(1, -100, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Text = "x1", BackgroundColor3 = Config.Colors.Accent }, row)
			local bAll = button({ Size = UDim2.fromOffset(46, 36), Position = UDim2.new(1, -52, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Text = "MAX", BackgroundColor3 = Config.Colors.Accent2 }, row)
			b1.Activated:Connect(function()
				Remotes.Shop:FireServer("buy", plant.id, 1)
			end)
			bAll.Activated:Connect(function()
				Remotes.Shop:FireServer("buy", plant.id, 99)
			end)
		end
	end
end

-- Mises a jour ----------------------------------------------------------------------

local function onInventory(inv)
	State.inventory = inv
	ui.coins.Text = Economy.formatCoins(inv.coins) .. " pieces"
	ui.harvests.Text = inv.harvests .. " recoltes  |  Parcelle " .. inv.plotId
	if inv.expandPrice then
		ui.expandButton.Text = "AGRANDIR " .. Economy.formatCoins(inv.expandPrice)
		ui.expandButton.Visible = true
	else
		ui.expandButton.Visible = false
	end
	ui.backpackButton.Text = (TOUCH and "SAC " or "SAC (B) ") .. #inv.fruits
	rebuildHotbar()
	if ui.backpack.Visible then
		rebuildBackpack()
	end
	State.fire("inventory", inv)
end

local function onShopState(shop)
	State.shop = shop
	if ui.shop.Visible then
		rebuildShop()
	end
end

local function onWeather(weather)
	State.weather = weather
	if weather.id == "Clair" then
		ui.weather.Text = "Ciel clair"
		ui.weather.TextColor3 = Config.Colors.Sky
		ui.weatherStroke.Color = Config.Colors.Sky
	else
		local color = weather.id == "Gel" and Color3.fromRGB(190, 240, 255) or (weather.id == "Orage" and Color3.fromRGB(255, 240, 120) or Color3.fromRGB(120, 180, 255))
		ui.weather.TextColor3 = color
		ui.weatherStroke.Color = color
	end
	State.fire("weather", weather)
end

local function isNear(tag, distance)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end
	for _, stand in ipairs(CollectionService:GetTagged(tag)) do
		if (stand.Position - hrp.Position).Magnitude <= distance then
			return true
		end
	end
	return false
end

local function toggle(name)
	if name == "close" then
		ui.shop.Visible = false
		ui.backpack.Visible = false
	elseif name == "backpack" then
		ui.backpack.Visible = not ui.backpack.Visible
		ui.shop.Visible = false
		if ui.backpack.Visible then
			rebuildBackpack()
		end
	elseif name == "shop" then
		if not ui.shop.Visible and not isNear("ShopStand", 40) then
			HUD.toast("Va au stand GRAINES pour ouvrir la boutique.", "info")
			return
		end
		ui.shop.Visible = not ui.shop.Visible
		ui.backpack.Visible = false
		if ui.shop.Visible then
			rebuildShop()
			Remotes.Shop:FireServer("state")
		end
	end
end

function HUD.Init()
	build()
	Remotes.Inventory.OnClientEvent:Connect(onInventory)
	Remotes.ShopState.OnClientEvent:Connect(onShopState)
	Remotes.Weather.OnClientEvent:Connect(onWeather)
	Remotes.Notify.OnClientEvent:Connect(HUD.toast)

	ui.backpackButton.Activated:Connect(function()
		toggle("backpack")
	end)
	ui.shopButton.Activated:Connect(function()
		toggle("shop")
	end)
	ui.expandButton.Activated:Connect(function()
		Remotes.Shop:FireServer("expand")
	end)
	ui.sellButton.Activated:Connect(function()
		Remotes.Shop:FireServer("sell")
	end)

	State.Changed.Event:Connect(function(what, data)
		if what == "toggle" then
			toggle(data)
		elseif what == "hotbar" then
			local entry = ui.hotbarSeeds and ui.hotbarSeeds[data]
			if entry then
				State.selectedSeed = (State.selectedSeed == entry.plant.id) and nil or entry.plant.id
				rebuildHotbar()
			end
		elseif what == "notify" then
			HUD.toast(data.text, data.kind)
		end
	end)

	-- Timers (meteo, reassort, bouton vendre a proximite)
	RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()
		if State.weather.id ~= "Clair" then
			local left = math.max(0, math.floor(State.weather.endsAt - now))
			ui.weather.Text = State.weather.label .. "  " .. left .. "s"
		end
		local restockLeft = math.max(0, math.floor((State.shop.nextRestock or 0) - now))
		local text = string.format("Reassort dans %d:%02d", math.floor(restockLeft / 60), restockLeft % 60)
		ui.restock.Text = text
		ui.shopRestock.Text = text
		ui.sellButton.Visible = #State.inventory.fruits > 0 and isNear("SellStand", 40)
	end)
end

return HUD
