-- Sauvegarde des joueurs (DataStoreService) : nouvelles tentatives, sauvegarde automatique,
-- sauvegarde immediate apres un echange, a la deconnexion et a la fermeture du serveur.
-- Si le chargement echoue, la session n'est jamais sauvegardee (protection des donnees).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage.Shared.Config)
local F = require(ReplicatedStorage.Shared.Formulas)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DataService = {}

local store, powerStore, rebirthStore, indexStore
pcall(function()
	store = DataStoreService:GetDataStore("RelicRush_v1")
	powerStore = DataStoreService:GetOrderedDataStore("RelicRush_Power_v1")
	rebirthStore = DataStoreService:GetOrderedDataStore("RelicRush_Rebirths_v1")
	indexStore = DataStoreService:GetOrderedDataStore("RelicRush_Index_v1")
end)

local cache, loaded = {}, {}
local loadedEvent = Instance.new("BindableEvent")
DataService.Loaded = loadedEvent.Event
local changedEvent = Instance.new("BindableEvent")
DataService.Changed = changedEvent.Event -- (player) apres chaque Sync

local function defaults()
	return {
		Coins = 0,
		TotalCoins = 0,
		Relics = {}, -- [uid (string)] = { id = relicId, locked = bool }
		NextUid = 1,
		Equipped = {}, -- liste d'uids (nombres)
		Index = {}, -- [relicId] = true
		Upgrades = {},
		Worlds = { Village = true },
		Rebirths = 0,
		BagBonus = 0,
		BagLevel = 0,
		Perks = {}, -- AutoHit, TripleOpen
		Boosts = {}, -- [Coins|Luck|Power] = fin (os.time)
		Stats = { Breaks = 0, Crates = 0, CoinsEarned = 0, BossFights = 0, BossWins = 0, Upgrades = 0, RarePlus = 0, Legendary = 0 },
		Quests = { Day = 0, List = {}, Base = {} }, -- quetes du jour
		Milestones = {}, -- [id] = true (reclamee)
		DailyStreak = 0,
		LastDaily = 0,
		Settings = { Music = 0.5, Sfx = 0.7, ShowOthers = true, LowGraphics = false, DamageNumbers = true },
	}
end

local function merge(into, from)
	for k, v in pairs(from) do
		if type(v) == "table" and type(into[k]) == "table" and #into[k] == 0 and next(into[k]) ~= nil then
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
		warn("[RelicRush] DataStore (essai " .. attempt .. ") : " .. tostring(result))
		task.wait(attempt * 1.5)
	end
	return false
end

local function key(player)
	return "u_" .. player.UserId
end

function DataService.Get(player)
	return cache[player]
end

function DataService.Count(data)
	local n = 0
	for _ in pairs(data.Relics) do
		n += 1
	end
	return n
end

function DataService.Discovered(data)
	local n = 0
	for _ in pairs(data.Index) do
		n += 1
	end
	return n
end

-- Etat envoye au client + attributs visibles par tous (reliques equipees, puissance)
function DataService.Sync(player)
	local data = cache[player]
	if not data then
		return
	end
	local now = os.time()
	local power = F.Power(data, now)
	local equippedIds = {}
	for _, uid in ipairs(data.Equipped) do
		local item = data.Relics[tostring(uid)]
		if item then
			table.insert(equippedIds, item.id)
		end
	end
	player:SetAttribute("Power", power)
	player:SetAttribute("Relics", HttpService:JSONEncode(equippedIds))
	player:SetAttribute("Rebirths", data.Rebirths)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = 16 + (data.Upgrades.Speed or 0) * F.UpgradeDef("Speed").per
	end
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls.Puissance.Value = power
		ls.Pieces.Value = math.min(math.floor(data.Coins), 2 ^ 52)
		ls.Rebirths.Value = data.Rebirths
	end
	Remotes.Sync:FireClient(player, data, { power = power, serverTime = now, discovered = DataService.Discovered(data), count = DataService.Count(data) })
	changedEvent:Fire(player)
end

function DataService.AddCoins(player, amount)
	local data = cache[player]
	if not data then
		return
	end
	data.Coins += amount
	if amount > 0 then
		data.TotalCoins += amount
		data.Stats.CoinsEarned += amount
	end
end

-- Ajoute une relique a l'inventaire (renvoie uid ou nil si plein)
function DataService.GiveRelic(player, relicId, noStats)
	local data = cache[player]
	local def = Config.RelicById[relicId]
	if not (data and def) then
		return nil
	end
	if DataService.Count(data) >= F.InventoryCap(data) then
		return nil
	end
	local uid = data.NextUid
	data.NextUid += 1
	data.Relics[tostring(uid)] = { id = relicId }
	local first = not data.Index[relicId]
	data.Index[relicId] = true
	local r = Config.RarityById[def.rarity]
	if noStats then
		return uid, first
	end
	if r.index >= 3 then
		data.Stats.RarePlus += 1
	end
	if r.index >= 5 then
		data.Stats.Legendary += 1
	end
	return uid, first
end

function DataService.Save(player)
	local data = cache[player]
	if not (store and data and loaded[player]) then
		return false
	end
	local ok = retry(function()
		store:UpdateAsync(key(player), function()
			return data
		end)
	end)
	pcall(function()
		powerStore:SetAsync(key(player), math.min(F.Power(data), 2 ^ 52))
		rebirthStore:SetAsync(key(player), data.Rebirths)
		indexStore:SetAsync(key(player), DataService.Discovered(data))
	end)
	return ok
end

local function makeLeaderstats(player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	for _, n in ipairs({ "Puissance", "Pieces", "Rebirths" }) do
		Instance.new("NumberValue", ls).Name = n
	end
	ls.Parent = player
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
		Remotes.Notify:FireClient(player, "Sauvegarde indisponible : ta progression de cette session ne sera pas enregistree.", "danger")
	end
	cache[player] = data
	loaded[player] = ok
	loadedEvent:Fire(player, data)
	DataService.Sync(player)
end

-- Classements globaux (mis en cache, rafraichis toutes les 2 minutes)
local tops = { Power = {}, Rebirths = {}, Index = {} }
local names = {}
function DataService.GetTop(kind)
	return tops[kind] or {}
end

local function refreshTops()
	for kind, st in pairs({ Power = powerStore, Rebirths = rebirthStore, Index = indexStore }) do
		if st then
			local ok, pages = pcall(function()
				return st:GetSortedAsync(false, 50)
			end)
			if ok then
				local list = {}
				for rank, entry in ipairs(pages:GetCurrentPage()) do
					local id = tonumber(string.sub(entry.key, 3))
					local name = names[id]
					if not name and id then
						local ok2, n = pcall(Players.GetNameFromUserIdAsync, Players, id)
						name = ok2 and n or "Joueur"
						names[id] = name
					end
					table.insert(list, { rank = rank, name = name or "Joueur", userId = id, value = entry.value })
				end
				tops[kind] = list
			end
		end
	end
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
		for _, p in ipairs(Players:GetPlayers()) do
			pending += 1
			task.spawn(function()
				DataService.Save(p)
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
			task.wait(90)
			for _, p in ipairs(Players:GetPlayers()) do
				task.spawn(DataService.Save, p)
			end
			refreshTops()
		end
	end)
	task.delay(6, refreshTops)
end

return DataService
