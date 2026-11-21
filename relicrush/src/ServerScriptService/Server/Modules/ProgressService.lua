-- Progression : ameliorations (forge), boutique (potions, sac, avantages), renaissance, mondes
-- (deblocage, voyage, portails), recompenses quotidiennes, quetes du jour et succes, parametres.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Config = require(ReplicatedStorage.Shared.Config)
local F = require(ReplicatedStorage.Shared.Formulas)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local Actions = require(script.Parent.Actions)
local WorldBuilder = require(script.Parent.WorldBuilder)
local RelicService = require(script.Parent.RelicService)

local ProgressService = {}

local function notify(p, t, k)
	Actions.Notify(p, t, k)
end

local function shopPrice(item, data)
	if item.kind == "potion" and item.scale then
		return math.floor(item.price * F.BestWorld(data).mult ^ 0.85)
	elseif item.kind == "inventory" then
		return math.floor(item.price * item.growth ^ (data.BagLevel or 0))
	end
	return item.price
end
ProgressService.ShopPrice = shopPrice

-- Quetes du jour : 3 quetes tirees selon le jour et le joueur ; progression = stat - stat au debut
local function ensureQuests(player, data)
	local day = os.time() // 86400
	if data.Quests.Day == day and #data.Quests.List > 0 then
		return
	end
	local rng = Random.new(day * 7919 + player.UserId % 100000)
	local pool = table.clone(Config.DailyQuestPool)
	local list = {}
	for _ = 1, Config.DailyQuestCount do
		local q = table.remove(pool, rng:NextInteger(1, #pool))
		table.insert(list, { id = q.id, claimed = false })
	end
	data.Quests = { Day = day, List = list, Base = table.clone(data.Stats) }
end
ProgressService.EnsureQuests = ensureQuests

local function questDef(id)
	for _, q in ipairs(Config.DailyQuestPool) do
		if q.id == id then
			return q
		end
	end
end

function ProgressService.QuestGoal(q, data)
	if q.worldScaled then
		return math.floor(q.goal * F.BestWorld(data).mult)
	end
	return q.goal
end

local function milestoneValue(data, stat)
	if stat == "Equipped" then
		return #data.Equipped
	elseif stat == "Worlds" then
		local n = 0
		for _ in pairs(data.Worlds) do
			n += 1
		end
		return n
	elseif stat == "Discovered" then
		return DataService.Discovered(data)
	elseif stat == "Rebirths" then
		return data.Rebirths
	end
	return data.Stats[stat] or 0
end
ProgressService.MilestoneValue = milestoneValue

local function teleport(player, worldId)
	local cf = WorldBuilder.Spawn(worldId)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if cf and hrp then
		player:SetAttribute("Target", nil)
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.CFrame = cf
		Remotes.FX:FireClient(player, "Teleport", { world = worldId })
	end
end
ProgressService.Teleport = teleport

function ProgressService.Init()
	Actions.Register("buyUpgrade", function(player, data, id)
		local u = F.UpgradeDef(id)
		if not u then
			return
		end
		local lvl = data.Upgrades[id] or 0
		if lvl >= u.max then
			return notify(player, u.name .. " est au niveau maximum.", "info")
		end
		local cost = F.UpgradeCost(id, lvl)
		if data.Coins < cost then
			return notify(player, "Il te manque " .. F.Format(cost - data.Coins) .. " pieces.", "danger")
		end
		data.Coins -= cost
		data.Upgrades[id] = lvl + 1
		data.Stats.Upgrades += 1
		Remotes.FX:FireClient(player, "Upgrade", { id = id, level = lvl + 1 })
	end)

	Actions.Register("buyShop", function(player, data, id)
		local item
		for _, it in ipairs(Config.Shop) do
			if it.id == id then
				item = it
			end
		end
		if not item then
			return
		end
		if item.kind == "perk" and data.Perks[id] then
			return notify(player, "Tu possedes deja " .. item.name .. ".", "info")
		end
		local price = shopPrice(item, data)
		if data.Coins < price then
			return notify(player, "Il te manque " .. F.Format(price - data.Coins) .. " pieces.", "danger")
		end
		data.Coins -= price
		if item.kind == "potion" then
			local now = os.time()
			data.Boosts[item.boost] = math.max(data.Boosts[item.boost] or 0, now) + item.duration
		elseif item.kind == "inventory" then
			data.BagBonus += item.amount
			data.BagLevel = (data.BagLevel or 0) + 1
		elseif item.kind == "perk" then
			data.Perks[id] = true
		end
		Remotes.FX:FireClient(player, "Purchase", { name = item.name })
	end)

	Actions.Register("rebirth", function(player, data)
		local cost = F.RebirthCost(data.Rebirths)
		if data.Coins < cost then
			return notify(player, "Il te faut " .. F.Format(cost) .. " pieces pour renaitre.", "danger")
		end
		data.Rebirths += 1
		data.Coins = 0
		local keep = {}
		for _, u in ipairs(Config.Upgrades) do
			if u.keepOnRebirth then
				keep[u.id] = data.Upgrades[u.id]
			end
		end
		data.Upgrades = keep
		Remotes.FX:FireClient(player, "Rebirth", { count = data.Rebirths })
		Remotes.Notify:FireAllClients(player.DisplayName .. " a atteint la renaissance " .. data.Rebirths .. " !", "gold")
	end)

	Actions.Register("unlockWorld", function(player, data, id)
		local w = Config.WorldById[id]
		if not w or data.Worlds[id] then
			return
		end
		local prev = Config.Worlds[w.index - 1]
		if prev and not data.Worlds[prev.id] then
			return notify(player, "Debloque d'abord " .. prev.name .. ".", "danger")
		end
		if data.Coins < w.price then
			return notify(player, "Il te manque " .. F.Format(w.price - data.Coins) .. " pieces.", "danger")
		end
		data.Coins -= w.price
		data.Worlds[id] = true
		Remotes.FX:FireClient(player, "WorldUnlock", { world = id })
		Remotes.Notify:FireAllClients(player.DisplayName .. " a debloque " .. w.name .. " !", "gold")
		task.delay(1.2, teleport, player, id)
	end)

	Actions.Register("teleport", function(player, data, id)
		if Config.WorldById[id] and data.Worlds[id] then
			teleport(player, id)
		end
		return true
	end)

	Actions.Register("daily", function(player, data)
		local since = os.time() - data.LastDaily
		if since < Config.Daily.Cooldown then
			return notify(player, "Prochaine recompense dans " .. F.Time(Config.Daily.Cooldown - since), "info")
		end
		data.DailyStreak = (since < Config.Daily.Reset) and (data.DailyStreak % #Config.Daily.Days) + 1 or 1
		data.LastDaily = os.time()
		local day = Config.Daily.Days[data.DailyStreak]
		local mult = F.BestWorld(data).mult
		local text = {}
		if day.coins then
			local c = math.floor(day.coins * mult)
			DataService.AddCoins(player, c)
			table.insert(text, F.Format(c) .. " pieces")
		end
		if day.potion then
			for _, it in ipairs(Config.Shop) do
				if it.id == day.potion then
					data.Boosts[it.boost] = math.max(data.Boosts[it.boost] or 0, os.time()) + it.duration
					table.insert(text, it.name)
				end
			end
		end
		if day.crate then
			local best = F.BestWorld(data)
			local got = 0
			for _ = 1, day.crate do
				local odds = F.CrateOdds(best.id, F.Luck(data) * 1.5)
				local r = math.random() * 100
				local rarity = odds[1].rarity
				for _, e in ipairs(odds) do
					r -= e.pct
					if r <= 0 then
						rarity = e.rarity
						break
					end
				end
				local pool = {}
				for _, rel in ipairs(Config.Relics) do
					if rel.world == best.id and rel.rarity == rarity and not rel.boss then
						table.insert(pool, rel.id)
					end
				end
				if #pool > 0 and DataService.GiveRelic(player, pool[math.random(#pool)]) then
					got += 1
				end
			end
			table.insert(text, got .. " relique(s)")
		end
		Remotes.FX:FireClient(player, "Daily", { day = data.DailyStreak, text = table.concat(text, " + ") })
	end)

	Actions.Register("claimQuest", function(player, data, index)
		ensureQuests(player, data)
		local q = data.Quests.List[tonumber(index) or 0]
		local def = q and questDef(q.id)
		if not def or q.claimed then
			return
		end
		local progress = (data.Stats[def.stat] or 0) - (data.Quests.Base[def.stat] or 0)
		if progress < ProgressService.QuestGoal(def, data) then
			return notify(player, "Quete pas encore terminee.", "info")
		end
		q.claimed = true
		local coins = math.floor(Config.QuestRewardBase * def.reward * F.BestWorld(data).mult)
		DataService.AddCoins(player, coins)
		Remotes.FX:FireClient(player, "Reward", { title = "Quete terminee !", text = "+" .. F.Format(coins) .. " pieces" })
	end)

	Actions.Register("claimMilestone", function(player, data, id)
		for _, m in ipairs(Config.Milestones) do
			if m.id == id and not data.Milestones[id] and milestoneValue(data, m.stat) >= m.goal then
				data.Milestones[id] = true
				DataService.AddCoins(player, m.coins)
				Remotes.FX:FireClient(player, "Reward", { title = "Succes debloque !", text = "+" .. F.Format(m.coins) .. " pieces" })
			end
		end
	end)

	Actions.Register("settings", function(player, data, s)
		if type(s) ~= "table" then
			return
		end
		for k, v in pairs(s) do
			if data.Settings[k] ~= nil and type(v) == type(data.Settings[k]) then
				data.Settings[k] = type(v) == "number" and math.clamp(v, 0, 1) or v
			end
		end
		if s.AutoHit ~= nil and type(s.AutoHit) == "boolean" then
			data.Settings.AutoHit = s.AutoHit
		end
	end)

	Actions.Register("target", function(player, data, model)
		local Targets = require(script.Parent.Targets)
		if typeof(model) == "Instance" and model:IsA("Model") then
			Targets.SetTarget(player, model)
		else
			player:SetAttribute("Target", nil)
		end
		return true
	end)

	-- portails : voyage si le monde est debloque (sinon le client ouvre le menu Mondes)
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		local target = prompt:GetAttribute("Target")
		if target and prompt:GetAttribute("Panel") == "Worlds" then
			local data = DataService.Get(player)
			if data and data.Worlds[target] then
				teleport(player, target)
			end
		end
	end)

	DataService.Loaded:Connect(function(player, data)
		ensureQuests(player, data)
		player.CharacterAdded:Connect(function()
			task.wait(0.2)
			DataService.Sync(player)
		end)
	end)
	-- renouvellement des quetes a minuit (UTC)
	task.spawn(function()
		while true do
			task.wait(60)
			for _, p in ipairs(Players:GetPlayers()) do
				local data = DataService.Get(p)
				if data and data.Quests.Day ~= os.time() // 86400 then
					ensureQuests(p, data)
					DataService.Sync(p)
				end
			end
		end
	end)
end

return ProgressService
