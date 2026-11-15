-- Sauvegarde DataStore (pieces, graines, fruits, parcelle) + leaderstats.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local DataService = {}

local STORE_NAME = "OnyxFarm_v1"

local store = nil
pcall(function()
	store = DataStoreService:GetDataStore(STORE_NAME)
end)

local cache = {}
local stats = {}

DataService.BeforeSave = nil -- function(player, data) rempli par PlotService

local function defaultData()
	return {
		Coins = Config.StartCoins,
		Seeds = { Carotte = 3 },
		Fruits = {},
		Tiles = {},
		ExpandLevel = 0,
		Harvests = 0,
		Earned = 0,
		SavedAt = os.time(),
	}
end

local function key(player)
	return "p_" .. player.UserId
end

function DataService.Load(player)
	local data = defaultData()
	if store then
		local ok, result = pcall(function()
			return store:GetAsync(key(player))
		end)
		if ok and type(result) == "table" then
			for k, v in pairs(result) do
				data[k] = v
			end
		elseif not ok then
			warn("[OnyxFarm] Chargement impossible pour " .. player.Name .. " : " .. tostring(result))
		end
	end
	cache[player] = data

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Pieces"
	coins.Value = data.Coins
	coins.Parent = leaderstats
	local harvests = Instance.new("IntValue")
	harvests.Name = "Recoltes"
	harvests.Value = data.Harvests
	harvests.Parent = leaderstats
	leaderstats.Parent = player
	stats[player] = { Coins = coins, Harvests = harvests }
	return data
end

function DataService.Get(player)
	return cache[player]
end

function DataService.Sync(player)
	local data = cache[player]
	local s = stats[player]
	if data and s then
		s.Coins.Value = math.floor(data.Coins)
		s.Harvests.Value = data.Harvests
	end
end

function DataService.Save(player)
	local data = cache[player]
	if not data then
		return
	end
	if DataService.BeforeSave then
		DataService.BeforeSave(player, data)
	end
	data.SavedAt = os.time()
	if not store then
		return
	end
	local ok, err = pcall(function()
		store:UpdateAsync(key(player), function()
			return data
		end)
	end)
	if not ok then
		warn("[OnyxFarm] Sauvegarde impossible pour " .. player.Name .. " : " .. tostring(err))
	end
end

function DataService.Release(player)
	cache[player] = nil
	stats[player] = nil
end

function DataService.Init()
	game:BindToClose(function()
		for _, p in ipairs(Players:GetPlayers()) do
			DataService.Save(p)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(90)
			for _, p in ipairs(Players:GetPlayers()) do
				DataService.Save(p)
			end
		end
	end)
end

return DataService
