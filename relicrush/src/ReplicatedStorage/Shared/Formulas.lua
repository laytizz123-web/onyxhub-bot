-- Calculs partages client / serveur : puissance, couts, chances, format des nombres.
local Config = require(script.Parent.Config)

local F = {}

function F.UpgradeCost(id, level)
	for _, u in ipairs(Config.Upgrades) do
		if u.id == id then
			return math.floor(u.base * u.growth ^ level)
		end
	end
	return math.huge
end

function F.UpgradeDef(id)
	for _, u in ipairs(Config.Upgrades) do
		if u.id == id then
			return u
		end
	end
end

function F.Slots(data)
	return Config.BaseSlots + (data.Upgrades.Slots or 0)
end

function F.InventoryCap(data)
	return Config.InventoryBase + (data.BagBonus or 0)
end

function F.RebirthCost(rebirths)
	return math.floor(Config.Rebirth.BaseCost * Config.Rebirth.Growth ^ rebirths)
end

function F.BestWorld(data)
	local best = Config.Worlds[1]
	for _, w in ipairs(Config.Worlds) do
		if data.Worlds[w.id] then
			best = w
		end
	end
	return best
end

-- Bonus d'index : mondes dont toutes les reliques non secretes sont decouvertes
function F.IndexBonus(data)
	local done = 0
	for _, w in ipairs(Config.Worlds) do
		local complete = true
		for _, r in ipairs(Config.Relics) do
			if r.world == w.id and not r.secret and not data.Index[r.id] then
				complete = false
				break
			end
		end
		if complete then
			done += 1
		end
	end
	return done * Config.IndexWorldBonus
end

local function boostActive(data, kind, now)
	local t = data.Boosts and data.Boosts[kind]
	return t and t > now
end

-- Puissance totale : base + reliques equipees, x ameliorations x renaissances x index x potion
function F.Power(data, now)
	now = now or os.time()
	local sum = Config.BaseDamage
	for _, uid in ipairs(data.Equipped) do
		local item = data.Relics[tostring(uid)]
		local def = item and Config.RelicById[item.id]
		if def then
			sum += def.power
		end
	end
	local mult = (1 + (data.Upgrades.Power or 0) * F.UpgradeDef("Power").per)
		* (1 + data.Rebirths * Config.Rebirth.PowerBonus)
		* (1 + F.IndexBonus(data))
		* (boostActive(data, "Power", now) and 2 or 1)
	return math.floor(sum * mult)
end

function F.CoinMult(data, now)
	now = now or os.time()
	return (1 + (data.Upgrades.Coins or 0) * F.UpgradeDef("Coins").per)
		* (1 + data.Rebirths * Config.Rebirth.CoinBonus)
		* (boostActive(data, "Coins", now) and 2 or 1)
end

function F.Luck(data, now)
	now = now or os.time()
	return (1 + (data.Upgrades.Luck or 0) * F.UpgradeDef("Luck").per) * (boostActive(data, "Luck", now) and 2 or 1)
end

-- Chances d'une caisse ajustees par la chance (les raretes Rare+ sont multipliees, puis normalisees)
function F.CrateOdds(worldId, luck)
	local crate = Config.Crates[worldId]
	local list, total = {}, 0
	local lowest = math.huge
	for rarityId in pairs(crate.odds) do
		lowest = math.min(lowest, Config.RarityById[rarityId].index)
	end
	for rarityId, pct in pairs(crate.odds) do
		local r = Config.RarityById[rarityId]
		local w = pct * ((r.index > lowest) and luck or 1)
		-- il faut au moins une relique de cette rarete dans le monde
		local found = false
		for _, rel in ipairs(Config.Relics) do
			if rel.world == worldId and rel.rarity == rarityId and not rel.boss then
				found = true
				break
			end
		end
		if found then
			table.insert(list, { rarity = rarityId, weight = w })
			total += w
		end
	end
	table.sort(list, function(a, b)
		return Config.RarityById[a.rarity].index < Config.RarityById[b.rarity].index
	end)
	for _, e in ipairs(list) do
		e.pct = e.weight / total * 100
	end
	return list, total
end

local SUFFIX = { "", "K", "M", "B", "T", "Qa", "Qi" }
function F.Format(n)
	n = math.floor(n or 0)
	if n < 1000 then
		return tostring(n)
	end
	local i = 1
	local v = n
	while v >= 1000 and i < #SUFFIX do
		v /= 1000
		i += 1
	end
	if v >= 100 then
		return string.format("%d%s", v, SUFFIX[i])
	end
	return string.format("%.1f%s", v, SUFFIX[i])
end

function F.Time(sec)
	sec = math.max(0, math.floor(sec))
	if sec >= 3600 then
		return string.format("%dh%02d", sec // 3600, (sec % 3600) // 60)
	end
	return string.format("%d:%02d", sec // 60, sec % 60)
end

return F
