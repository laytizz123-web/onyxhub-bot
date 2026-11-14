-- Sauvegarde des pieces / victoires (DataStore) + leaderstats.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DataService = {}

local STORE_NAME = "OnyxArena_v1"
local DEFAULT = { Coins = 0, Wins = 0, Deflects = 0, BestStreak = 0 }

local store = nil
pcall(function()
	store = DataStoreService:GetDataStore(STORE_NAME)
end)

local cache = {}
local values = {}

local function key(player)
	return "p_" .. player.UserId
end

local function syncValues(player)
	local data = cache[player]
	local v = values[player]
	if not data or not v then
		return
	end
	v.Coins.Value = data.Coins
	v.Wins.Value = data.Wins
	v.Deflects.Value = data.Deflects
end

function DataService.Setup(player)
	local data = table.clone(DEFAULT)
	if store then
		local ok, result = pcall(function()
			return store:GetAsync(key(player))
		end)
		if ok and type(result) == "table" then
			for k, v in pairs(DEFAULT) do
				if type(result[k]) == "number" then
					data[k] = result[k]
				end
			end
		elseif not ok then
			warn("[OnyxArena] Chargement impossible pour " .. player.Name .. " : " .. tostring(result))
		end
	end
	cache[player] = data

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Parent = leaderstats
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = leaderstats
	local streak = Instance.new("IntValue")
	streak.Name = "Streak"
	streak.Parent = leaderstats
	local deflects = Instance.new("IntValue")
	deflects.Name = "Deflects"
	deflects.Parent = player -- hors leaderstats (visible dans le HUD seulement)

	values[player] = { Coins = coins, Wins = wins, Streak = streak, Deflects = deflects }
	leaderstats.Parent = player
	syncValues(player)
end

function DataService.Get(player, field)
	local data = cache[player]
	return data and data[field] or 0
end

function DataService.Add(player, field, amount)
	local data = cache[player]
	if not data or DEFAULT[field] == nil then
		return
	end
	data[field] = math.max(0, data[field] + amount)
	syncValues(player)
end

function DataService.SetStreak(player, streak)
	local v = values[player]
	local data = cache[player]
	if v then
		v.Streak.Value = streak
	end
	if data and streak > data.BestStreak then
		data.BestStreak = streak
	end
end

function DataService.GetStreak(player)
	local v = values[player]
	return v and v.Streak.Value or 0
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
		warn("[OnyxArena] Sauvegarde impossible pour " .. player.Name .. " : " .. tostring(err))
	end
end

function DataService.Init()
	Players.PlayerAdded:Connect(DataService.Setup)
	for _, p in ipairs(Players:GetPlayers()) do
		if not cache[p] then
			DataService.Setup(p)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		DataService.Save(player)
		cache[player] = nil
		values[player] = nil
	end)
	game:BindToClose(function()
		if RunService:IsStudio() and not store then
			return
		end
		for _, p in ipairs(Players:GetPlayers()) do
			DataService.Save(p)
		end
	end)
	-- Sauvegarde automatique
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
