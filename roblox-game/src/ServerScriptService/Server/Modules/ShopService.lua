-- Boutique de graines avec reassort periodique, achat, vente, agrandissement.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Economy = require(ReplicatedStorage.Shared.Economy)
local DataService = require(script.Parent.DataService)

local ShopService = {}

local stock = {}
local nextRestock = 0
local PlotService

local function broadcastStock(player)
	local payload = { stock = stock, nextRestock = nextRestock, serverTime = workspace:GetServerTimeNow() }
	if player then
		Remotes.ShopState:FireClient(player, payload)
	else
		Remotes.ShopState:FireAllClients(payload)
	end
end

local function restock()
	for _, plant in ipairs(Config.Plants) do
		local chance, minQ, maxQ = plant.stock[1], plant.stock[2], plant.stock[3]
		if math.random() < chance then
			stock[plant.id] = math.random(minQ, maxQ)
		else
			stock[plant.id] = 0
		end
	end
	-- La carotte est toujours disponible
	if stock.Carotte < 5 then
		stock.Carotte = 5
	end
	nextRestock = workspace:GetServerTimeNow() + Config.Shop.RestockInterval
	broadcastStock()
	Remotes.Notify:FireAllClients("La boutique a ete reapprovisionnee !", "shop")
end

local function buy(player, plantId, amount)
	local data = DataService.Get(player)
	local plant = Config.PlantById[plantId]
	if not data or not plant then
		return
	end
	amount = math.clamp(math.floor(tonumber(amount) or 1), 1, 99)
	local available = stock[plantId] or 0
	if available <= 0 then
		Remotes.Notify:FireClient(player, "Rupture de stock !", "danger")
		return
	end
	amount = math.min(amount, available)
	local affordable = math.floor(data.Coins / plant.price)
	if affordable <= 0 then
		Remotes.Notify:FireClient(player, "Pas assez de pieces (" .. Economy.formatCoins(plant.price) .. " necessaires)", "danger")
		return
	end
	amount = math.min(amount, affordable)
	data.Coins -= plant.price * amount
	data.Seeds[plantId] = (data.Seeds[plantId] or 0) + amount
	stock[plantId] = available - amount
	DataService.Sync(player)
	PlotService.SyncInventory(player)
	broadcastStock()
	Remotes.Notify:FireClient(player, "+" .. amount .. " graine(s) de " .. plant.id, "good")
	Remotes.FX:FireClient(player, "Buy", {})
end

local function sellAll(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	if #data.Fruits == 0 then
		Remotes.Notify:FireClient(player, "Ton sac est vide. Recolte d'abord !", "danger")
		return
	end
	local total = 0
	local count = #data.Fruits
	for _, fruit in ipairs(data.Fruits) do
		total += Economy.value(fruit)
	end
	data.Fruits = {}
	data.Coins += total
	data.Earned += total
	DataService.Sync(player)
	PlotService.SyncInventory(player)
	Remotes.Notify:FireClient(player, count .. " fruit(s) vendu(s) pour " .. Economy.formatCoins(total) .. " pieces !", "gold")
	Remotes.FX:FireClient(player, "Sell", { total = total })
end

local function expand(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local level = data.ExpandLevel or 0
	local price = Config.Plot.ExpandPrices[level + 1]
	if not price then
		Remotes.Notify:FireClient(player, "Ta parcelle est deja au maximum !", "info")
		return
	end
	if data.Coins < price then
		Remotes.Notify:FireClient(player, "Il te faut " .. Economy.formatCoins(price) .. " pieces pour agrandir.", "danger")
		return
	end
	data.Coins -= price
	data.ExpandLevel = level + 1
	DataService.Sync(player)
	PlotService.ApplyExpandLevel(player)
	PlotService.SyncInventory(player)
	Remotes.Notify:FireClient(player, "Parcelle agrandie !", "gold")
	Remotes.FX:FireClient(player, "Expand", {})
end

function ShopService.Init(plotService)
	PlotService = plotService
	restock()
	task.spawn(function()
		while true do
			task.wait(Config.Shop.RestockInterval)
			restock()
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		task.wait(1)
		broadcastStock(player)
	end)

	Remotes.Shop.OnServerEvent:Connect(function(player, action, a, b)
		if action == "buy" then
			buy(player, tostring(a), b)
		elseif action == "sell" then
			sellAll(player)
		elseif action == "expand" then
			expand(player)
		elseif action == "state" then
			broadcastStock(player)
		end
	end)

	for _, stand in ipairs(CollectionService:GetTagged("SellStand")) do
		local prompt = stand:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(sellAll)
		end
	end
end

return ShopService
