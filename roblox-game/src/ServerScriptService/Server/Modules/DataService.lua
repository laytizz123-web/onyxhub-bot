-- Sauvegarde DataStore + leaderstats + classement global coins.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local DataService = {}

local store, topStore
pcall(function()
	store = DataStoreService:GetDataStore("PetRush_v1")
	topStore = DataStoreService:GetOrderedDataStore("PetRush_Coins_v1")
end)

local cache = {}
local stats = {}

local function defaultData()
	return {
		Coins = Config.StartCoins,
		TotalCoins = 0,
		Pets = {}, -- { uid = n, id = "Chaton", evo = 1 }
		NextUid = 1,
		Equipped = {}, -- liste d'uids
		Zones = { Village = true },
		Index = {}, -- [petId] = true (decouverts)
		Hatched = 0,
		RaceWins = 0,
		Races = 0,
		LastDaily = 0,
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
			warn("[PetRush] Chargement impossible pour " .. player.Name .. " : " .. tostring(result))
		end
	end
	data.Zones = data.Zones or { Village = true }
	data.Zones.Village = true
	data.Pets = data.Pets or {}
	data.Equipped = data.Equipped or {}
	data.Index = data.Index or {}
	cache[player] = data

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local values = {}
	for _, name in ipairs({ "Coins", "Pets", "RaceWins" }) do
		local v = Instance.new("IntValue")
		v.Name = name
		v.Parent = leaderstats
		values[name] = v
	end
	leaderstats.Parent = player
	stats[player] = values
	DataService.Sync(player)
	return data
end

function DataService.Get(player)
	return cache[player]
end

function DataService.Sync(player)
	local data = cache[player]
	local values = stats[player]
	if data and values then
		values.Coins.Value = math.floor(data.Coins)
		values.Pets.Value = #data.Pets
		values.RaceWins.Value = data.RaceWins
	end
end

function DataService.Save(player)
	local data = cache[player]
	if not data or not store then
		return
	end
	local ok, err = pcall(function()
		store:UpdateAsync(key(player), function()
			return data
		end)
	end)
	if not ok then
		warn("[PetRush] Sauvegarde impossible pour " .. player.Name .. " : " .. tostring(err))
	end
	if topStore then
		pcall(function()
			topStore:SetAsync(tostring(player.UserId), math.floor(data.TotalCoins))
		end)
	end
end

function DataService.Release(player)
	cache[player] = nil
	stats[player] = nil
end

function DataService.GetTop(count)
	if not topStore then
		return {}
	end
	local ok, pages = pcall(function()
		return topStore:GetSortedAsync(false, count)
	end)
	if not ok then
		return {}
	end
	local result = {}
	for _, entry in ipairs(pages:GetCurrentPage()) do
		table.insert(result, { userId = tonumber(entry.key), value = entry.value })
	end
	return result
end

function DataService.Init()
	game:BindToClose(function()
		for _, p in ipairs(Players:GetPlayers()) do
			DataService.Save(p)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(120)
			for _, p in ipairs(Players:GetPlayers()) do
				DataService.Save(p)
			end
		end
	end)
end

return DataService
