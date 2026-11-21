-- Caisses et inventaire de reliques : ouverture (tirage serveur avec chance), equipement,
-- equipement automatique des meilleures, verrouillage, recyclage contre des pieces.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local F = require(ReplicatedStorage.Shared.Formulas)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local Actions = require(script.Parent.Actions)

local RelicService = {}

local function isEquipped(data, uid)
	for i, u in ipairs(data.Equipped) do
		if u == uid then
			return i
		end
	end
	return nil
end
RelicService.IsEquipped = isEquipped

function RelicService.Unequip(data, uid)
	local i = isEquipped(data, uid)
	if i then
		table.remove(data.Equipped, i)
	end
end

local function powerOf(data, uid)
	local item = data.Relics[tostring(uid)]
	local def = item and Config.RelicById[item.id]
	return def and def.power or 0
end

function RelicService.EquipBest(data)
	local all = {}
	for k in pairs(data.Relics) do
		table.insert(all, tonumber(k))
	end
	table.sort(all, function(a, b)
		return powerOf(data, a) > powerOf(data, b)
	end)
	data.Equipped = {}
	for i = 1, math.min(F.Slots(data), #all) do
		table.insert(data.Equipped, all[i])
	end
end

-- Tirage d'une relique dans la caisse d'un monde
local function roll(worldId, luck)
	local odds, total = F.CrateOdds(worldId, luck)
	local r = math.random() * total
	local rarity = odds[#odds].rarity
	for _, e in ipairs(odds) do
		r -= e.weight
		if r <= 0 then
			rarity = e.rarity
			break
		end
	end
	local pool = {}
	for _, rel in ipairs(Config.Relics) do
		if rel.world == worldId and rel.rarity == rarity and not rel.boss then
			table.insert(pool, rel.id)
		end
	end
	return pool[math.random(#pool)]
end

local function nearCrate(player, worldId)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local pos = require(script.Parent.WorldBuilder).Crate(worldId)
	return hrp ~= nil and pos ~= nil and (Vector3.new(pos.X, hrp.Position.Y, pos.Z) - hrp.Position).Magnitude <= 30
end

local function openCrate(player, data, worldId, count)
	count = (count == 3) and 3 or 1
	local crate = Config.Crates[worldId]
	if not crate or not data.Worlds[worldId] then
		return
	end
	if count == 3 and not data.Perks.TripleOpen then
		return Actions.Notify(player, "Achete l'ouverture x3 dans la Boutique !", "danger")
	end
	if not nearCrate(player, worldId) then
		return Actions.Notify(player, "Approche-toi de la caisse pour l'ouvrir.", "danger")
	end
	local cost = crate.price * count
	if data.Coins < cost then
		return Actions.Notify(player, "Il te manque " .. F.Format(cost - data.Coins) .. " pieces.", "danger")
	end
	if DataService.Count(data) + count > F.InventoryCap(data) then
		return Actions.Notify(player, "Inventaire plein ! Recycle des reliques ou agrandis ton sac.", "danger")
	end
	data.Coins -= cost
	local luck = F.Luck(data)
	local results = {}
	for _ = 1, count do
		local id = roll(worldId, luck)
		local uid, first = DataService.GiveRelic(player, id)
		data.Stats.Crates += 1
		table.insert(results, { uid = uid, id = id, first = first })
		local def = Config.RelicById[id]
		if Config.RarityById[def.rarity].index >= 5 then
			Remotes.Notify:FireAllClients(player.DisplayName .. " a obtenu " .. def.name .. " (" .. Config.RarityById[def.rarity].name .. ") !", "gold")
		end
		-- equipement automatique si un emplacement est libre
		if #data.Equipped < F.Slots(data) then
			table.insert(data.Equipped, uid)
		end
	end
	Remotes.FX:FireClient(player, "CrateOpen", { world = worldId, results = results })
end

local function recycleValue(def)
	local crate = Config.Crates[def.world]
	return math.floor(crate.price * 0.15 * Config.RarityById[def.rarity].index)
end
RelicService.RecycleValue = recycleValue

function RelicService.Init()
	Actions.Register("openCrate", openCrate)
	Actions.Register("equip", function(player, data, uid)
		uid = tonumber(uid)
		if not uid or not data.Relics[tostring(uid)] or isEquipped(data, uid) then
			return
		end
		if #data.Equipped >= F.Slots(data) then
			return Actions.Notify(player, "Tous tes emplacements sont pleins (ameliore-les a la Forge).", "danger")
		end
		table.insert(data.Equipped, uid)
	end)
	Actions.Register("unequip", function(player, data, uid)
		RelicService.Unequip(data, tonumber(uid))
	end)
	Actions.Register("equipBest", function(player, data)
		RelicService.EquipBest(data)
	end)
	Actions.Register("lock", function(player, data, uid)
		local item = data.Relics[tostring(tonumber(uid))]
		if item then
			item.locked = not item.locked or nil
		end
	end)
	Actions.Register("recycle", function(player, data, list)
		if type(list) ~= "table" then
			return
		end
		local total, n = 0, 0
		for i, uid in ipairs(list) do
			if i > 100 then
				break
			end
			uid = tonumber(uid)
			local item = uid and data.Relics[tostring(uid)]
			if item and not item.locked then
				RelicService.Unequip(data, uid)
				data.Relics[tostring(uid)] = nil
				total += recycleValue(Config.RelicById[item.id])
				n += 1
			end
		end
		if n > 0 then
			DataService.AddCoins(player, total)
			Actions.Notify(player, n .. " relique(s) recyclee(s) : +" .. F.Format(total) .. " pieces", "good")
		end
	end)
end

return RelicService
