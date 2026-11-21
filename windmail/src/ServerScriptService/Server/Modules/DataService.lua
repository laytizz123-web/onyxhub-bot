-- Sauvegarde des joueurs : DataStore avec nouvelles tentatives, sauvegarde automatique,
-- sauvegarde a la deconnexion et a la fermeture du serveur. Leaderstats + classement global.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DataService = {}

local STORE_NAME = "Windmail_v1"
local store, topStore
pcall(function()
	store = DataStoreService:GetDataStore(STORE_NAME)
	topStore = DataStoreService:GetOrderedDataStore("Windmail_Deliveries_v1")
end)

local cache = {} -- [player] = data
local loaded = {} -- [player] = true quand le chargement a reussi (on ne sauvegarde jamais des donnees vides)
local onLoaded = Instance.new("BindableEvent")
DataService.Loaded = onLoaded.Event

local function defaults()
	return {
		Version = 1,
		Coins = Config.StartCoins,
		TotalCoins = 0,
		XP = 0,
		Deliveries = 0,
		Grades = { S = 0, A = 0, B = 0, C = 0 },
		Gliders = { Lin = true },
		Glider = "Lin",
		Satchel = 1,
		Trails = { Aucune = true },
		Trail = "Aucune",
		Stamps = {}, -- [id] = nombre
		DailyStreak = 0,
		LastDaily = 0,
		Tutorial = false,
		Playtime = 0,
	}
end

local function merge(into, from)
	for k, v in pairs(from) do
		if type(v) == "table" and type(into[k]) == "table" then
			merge(into[k], v)
		else
			into[k] = v
		end
	end
end

local function retry(fn)
	for attempt = 1, 4 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn("[Windmail] DataStore (essai " .. attempt .. ") : " .. tostring(result))
		task.wait(attempt * 1.5)
	end
	return false
end

local function key(player)
	return "u_" .. player.UserId
end

local function makeLeaderstats(player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	for _, name in ipairs({ "Rang", "Livraisons", "Pieces" }) do
		local v = Instance.new("IntValue")
		v.Name = name
		v.Parent = ls
	end
	ls.Parent = player
end

function DataService.Get(player)
	return cache[player]
end

function DataService.IsLoaded(player)
	return loaded[player] == true
end

-- Envoie l'etat utile au client + met a jour leaderstats et attributs visibles par tous
function DataService.Sync(player)
	local data = cache[player]
	if not data then
		return
	end
	local rank, xpIn, xpNeed = Progress.RankFromXP(data.XP)
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls.Rang.Value = rank
		ls.Livraisons.Value = data.Deliveries
		ls.Pieces.Value = math.floor(data.Coins)
	end
	player:SetAttribute("Rank", rank)
	player:SetAttribute("Glider", data.Glider)
	player:SetAttribute("Trail", data.Trail)
	Remotes.Sync:FireClient(player, {
		coins = data.Coins,
		xp = data.XP,
		rank = rank,
		xpIn = xpIn,
		xpNeed = xpNeed,
		deliveries = data.Deliveries,
		grades = data.Grades,
		gliders = data.Gliders,
		glider = data.Glider,
		satchel = data.Satchel,
		trails = data.Trails,
		trail = data.Trail,
		stamps = data.Stamps,
		dailyIn = math.max(0, Config.Daily.Cooldown - (os.time() - data.LastDaily)),
		dailyStreak = data.DailyStreak,
		tutorial = data.Tutorial,
	})
end

function DataService.AddCoins(player, amount)
	local data = cache[player]
	if not data then
		return
	end
	data.Coins += amount
	if amount > 0 then
		data.TotalCoins += amount
	end
end

-- Ajoute de l'XP ; renvoie le nouveau rang si le joueur monte de rang
function DataService.AddXP(player, amount)
	local data = cache[player]
	if not data then
		return nil
	end
	local before = Progress.RankFromXP(data.XP)
	data.XP += amount
	local after = Progress.RankFromXP(data.XP)
	if after > before then
		return after
	end
	return nil
end

function DataService.Save(player)
	local data = cache[player]
	if not (store and data and loaded[player]) then
		return
	end
	retry(function()
		store:UpdateAsync(key(player), function()
			return data
		end)
	end)
	if topStore then
		pcall(function()
			topStore:SetAsync(key(player), data.Deliveries)
		end)
	end
end

local function load(player)
	makeLeaderstats(player)
	local data = defaults()
	local ok = true
	if store then
		local result
		ok, result = retry(function()
			return store:GetAsync(key(player))
		end)
		if ok and type(result) == "table" then
			merge(data, result)
		end
	end
	if player.Parent ~= Players then
		return
	end
	if not ok then
		-- pas de sauvegarde pour eviter d'ecraser les vraies donnees
		Remotes.Notify:FireClient(player, "Sauvegarde indisponible : ta progression de cette session ne sera pas enregistree.", "danger")
	end
	cache[player] = data
	loaded[player] = ok
	DataService.Sync(player)
	onLoaded:Fire(player, data)
end

-- Classement global (top 10 livraisons) lu toutes les 2 minutes
local top = {}
function DataService.GetTop()
	return top
end

local function refreshTop()
	if not topStore then
		return
	end
	local ok, pages = pcall(function()
		return topStore:GetSortedAsync(false, 10)
	end)
	if not ok then
		return
	end
	local list = {}
	for rank, entry in ipairs(pages:GetCurrentPage()) do
		local id = tonumber(string.sub(entry.key, 3))
		local name = "Facteur"
		if id then
			local ok2, n = pcall(Players.GetNameFromUserIdAsync, Players, id)
			if ok2 then
				name = n
			end
		end
		table.insert(list, { rank = rank, name = name, value = entry.value })
	end
	top = list
end

function DataService.Init()
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(load, p)
	end
	Players.PlayerAdded:Connect(load)
	Players.PlayerRemoving:Connect(function(player)
		DataService.Save(player)
		cache[player] = nil
		loaded[player] = nil
	end)
	game:BindToClose(function()
		if RunService:IsStudio() then
			task.wait(1)
		end
		local pending = 0
		for _, player in ipairs(Players:GetPlayers()) do
			pending += 1
			task.spawn(function()
				DataService.Save(player)
				pending -= 1
			end)
		end
		local t0 = os.clock()
		while pending > 0 and os.clock() - t0 < 25 do
			task.wait(0.2)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(120)
			for _, player in ipairs(Players:GetPlayers()) do
				local data = cache[player]
				if data then
					data.Playtime += 120
				end
				task.spawn(DataService.Save, player)
			end
			refreshTop()
		end
	end)
	task.delay(5, refreshTop)
end

return DataService
