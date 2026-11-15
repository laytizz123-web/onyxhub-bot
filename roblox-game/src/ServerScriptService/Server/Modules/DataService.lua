-- Sauvegarde DataStore + leaderstats + classement global (OrderedDataStore).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local DataService = {}

local store, winsStore
pcall(function()
	store = DataStoreService:GetDataStore("OnyxBG_v1")
	winsStore = DataStoreService:GetOrderedDataStore("OnyxBG_Wins_v1")
end)

local cache = {}
local stats = {}

local function defaultData()
	return {
		XP = 0,
		Level = 1,
		Coins = 0,
		Kills = 0,
		Deaths = 0,
		Wins = 0,
		Character = "Fighter",
		Aura = "none",
		Trail = "none",
		Title = "rookie",
		Unlocked = { auras = { none = true }, trails = { none = true }, titles = { rookie = true } },
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
			data.Unlocked = data.Unlocked or defaultData().Unlocked
			data.Unlocked.auras = data.Unlocked.auras or { none = true }
			data.Unlocked.trails = data.Unlocked.trails or { none = true }
			data.Unlocked.titles = data.Unlocked.titles or { rookie = true }
		elseif not ok then
			warn("[OnyxBG] Chargement impossible pour " .. player.Name .. " : " .. tostring(result))
		end
	end
	if not Config.CharacterById[data.Character] then
		data.Character = "Fighter"
	end
	cache[player] = data

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local values = {}
	for _, name in ipairs({ "Wins", "Kills", "Level" }) do
		local v = Instance.new("IntValue")
		v.Name = name
		v.Value = data[name]
		v.Parent = leaderstats
		values[name] = v
	end
	leaderstats.Parent = player
	stats[player] = values
	player:SetAttribute("Level", data.Level)
	return data
end

function DataService.Get(player)
	return cache[player]
end

function DataService.Sync(player)
	local data = cache[player]
	local values = stats[player]
	if data and values then
		values.Wins.Value = data.Wins
		values.Kills.Value = data.Kills
		values.Level.Value = data.Level
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
		warn("[OnyxBG] Sauvegarde impossible pour " .. player.Name .. " : " .. tostring(err))
	end
	if winsStore then
		pcall(function()
			winsStore:SetAsync(tostring(player.UserId), data.Wins)
		end)
	end
end

function DataService.Release(player)
	cache[player] = nil
	stats[player] = nil
end

-- Top global (userId -> wins) ; retourne { {userId=, wins=} }
function DataService.GetTopWins(count)
	if not winsStore then
		return {}
	end
	local ok, pages = pcall(function()
		return winsStore:GetSortedAsync(false, count)
	end)
	if not ok then
		return {}
	end
	local result = {}
	for _, entry in ipairs(pages:GetCurrentPage()) do
		table.insert(result, { userId = tonumber(entry.key), wins = entry.value })
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
