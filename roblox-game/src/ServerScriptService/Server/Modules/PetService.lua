-- Pets : eclosion, equipement, evolution, index, zones, cadeau du jour, classement.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PetModel = require(ReplicatedStorage.Shared.PetModel)
local DataService = require(script.Parent.DataService)
local MapBuilder = require(script.Parent.MapBuilder)

local PetService = {}

local function notify(player, text, kind)
	Remotes.Notify:FireClient(player, text, kind or "info")
end

-- Synchronisation ------------------------------------------------------------------

function PetService.Sync(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	DataService.Sync(player)
	-- Attribut lu par tous les clients pour afficher les pets qui suivent
	local equipped = {}
	for _, uid in ipairs(data.Equipped) do
		for _, pet in ipairs(data.Pets) do
			if pet.uid == uid then
				table.insert(equipped, { id = pet.id, evo = pet.evo })
			end
		end
	end
	player:SetAttribute("EquippedPets", HttpService:JSONEncode(equipped))
	player:SetAttribute("Power", PetService.GetPower(player))
	Remotes.PetsSync:FireClient(player, {
		coins = math.floor(data.Coins),
		totalCoins = math.floor(data.TotalCoins),
		pets = data.Pets,
		equipped = data.Equipped,
		zones = data.Zones,
		index = data.Index,
		hatched = data.Hatched,
		raceWins = data.RaceWins,
		races = data.Races,
		dailyReady = os.time() - (data.LastDaily or 0) >= Config.Daily.Cooldown,
		dailyIn = math.max(0, Config.Daily.Cooldown - (os.time() - (data.LastDaily or 0))),
		power = PetService.GetPower(player),
	})
end

function PetService.GetPower(player)
	local data = DataService.Get(player)
	if not data then
		return 0
	end
	local total = 0
	for _, uid in ipairs(data.Equipped) do
		for _, pet in ipairs(data.Pets) do
			if pet.uid == uid then
				total += PetModel.Stats(pet.id, pet.evo).power
			end
		end
	end
	return total
end

function PetService.GetEquippedPets(player)
	local data = DataService.Get(player)
	local list = {}
	if not data then
		return list
	end
	for _, uid in ipairs(data.Equipped) do
		for _, pet in ipairs(data.Pets) do
			if pet.uid == uid then
				table.insert(list, pet)
			end
		end
	end
	return list
end

function PetService.AddCoins(player, amount)
	local data = DataService.Get(player)
	if not data then
		return
	end
	data.Coins += amount
	if amount > 0 then
		data.TotalCoins += amount
	end
end

local function findPet(data, uid)
	for i, pet in ipairs(data.Pets) do
		if pet.uid == uid then
			return pet, i
		end
	end
	return nil
end

local function givePet(player, data, petId, evo)
	local pet = { uid = data.NextUid, id = petId, evo = evo or 1 }
	data.NextUid += 1
	table.insert(data.Pets, pet)
	if not data.Index[petId] then
		data.Index[petId] = true
		notify(player, "📖 Nouveau pet dans ton index : " .. Config.PetById[petId].icon .. " " .. petId, "good")
	end
	return pet
end

-- Eclosion --------------------------------------------------------------------------

local function luckBonus(player)
	local luck = 0
	for _, pet in ipairs(PetService.GetEquippedPets(player)) do
		luck += PetModel.Stats(pet.id, pet.evo).luck
	end
	return 1 + math.min(luck, 300) / 150 -- jusqu'a x3 sur les raretes hautes
end

function PetService.EggChances(eggId, luck)
	luck = luck or 1
	local pool = {}
	local total = 0
	for _, pet in ipairs(Config.Pets) do
		if pet.egg == eggId then
			local rarity = Config.RarityById[pet.rarity]
			local weight = rarity.weight * (rarity.index >= 3 and luck or 1)
			table.insert(pool, { pet = pet, weight = weight })
			total += weight
		end
	end
	return pool, total
end

local function hatch(player, eggId)
	local data = DataService.Get(player)
	local egg = Config.EggById[eggId]
	if not data or not egg then
		return
	end
	if not data.Zones[egg.zone] then
		notify(player, "🔒 Debloque d'abord la zone " .. Config.ZoneById[egg.zone].name, "danger")
		return
	end
	if #data.Pets >= Config.MaxPets then
		notify(player, "🐾 Inventaire plein (" .. Config.MaxPets .. " pets). Fais evoluer ou supprime des pets.", "danger")
		return
	end
	if data.Coins < egg.price then
		notify(player, "🪙 Il te faut " .. egg.price .. " coins pour cet oeuf.", "danger")
		return
	end
	data.Coins -= egg.price
	data.Hatched += 1
	local pool, total = PetService.EggChances(eggId, luckBonus(player))
	local r = math.random() * total
	local chosen = pool[1].pet
	for _, entry in ipairs(pool) do
		r -= entry.weight
		if r <= 0 then
			chosen = entry.pet
			break
		end
	end
	local pet = givePet(player, data, chosen.id, 1)
	local rarity = Config.RarityById[chosen.rarity]
	Remotes.FX:FireClient(player, "Hatch", { petId = chosen.id, uid = pet.uid, rarity = chosen.rarity, egg = eggId })
	if rarity.index >= 5 then
		Remotes.Notify:FireAllClients("🎉 " .. player.DisplayName .. " a obtenu un pet " .. rarity.icon .. " " .. rarity.name .. " : " .. chosen.icon .. " " .. chosen.id .. " !", "gold")
	end
	PetService.Sync(player)
end

-- Equipement / evolution / suppression ----------------------------------------------------

local function equip(player, uid)
	local data = DataService.Get(player)
	if not data then
		return
	end
	uid = tonumber(uid)
	local pet = findPet(data, uid)
	if not pet then
		return
	end
	local idx = table.find(data.Equipped, uid)
	if idx then
		table.remove(data.Equipped, idx)
	else
		if #data.Equipped >= Config.MaxEquipped then
			notify(player, "Tu peux equiper " .. Config.MaxEquipped .. " pets maximum.", "danger")
			return
		end
		table.insert(data.Equipped, uid)
	end
	PetService.Sync(player)
end

local function evolve(player, uid)
	local data = DataService.Get(player)
	if not data then
		return
	end
	uid = tonumber(uid)
	local pet = findPet(data, uid)
	if not pet then
		return
	end
	if pet.evo >= #Config.Evolutions then
		notify(player, "Ce pet est deja au niveau maximum 🌌", "info")
		return
	end
	local same = {}
	for _, other in ipairs(data.Pets) do
		if other.id == pet.id and other.evo == pet.evo then
			table.insert(same, other)
		end
	end
	if #same < Config.EvolveCost then
		notify(player, "Il faut " .. Config.EvolveCost .. " x " .. PetModel.DisplayName(pet.id, pet.evo) .. " (tu en as " .. #same .. ")", "danger")
		return
	end
	-- Consomme 3 exemplaires (celui choisi en premier)
	local consumed = 0
	local toRemove = { pet }
	for _, other in ipairs(same) do
		if other ~= pet and #toRemove < Config.EvolveCost then
			table.insert(toRemove, other)
		end
	end
	for _, rem in ipairs(toRemove) do
		local _, i = findPet(data, rem.uid)
		if i then
			table.remove(data.Pets, i)
			local eq = table.find(data.Equipped, rem.uid)
			if eq then
				table.remove(data.Equipped, eq)
			end
			consumed += 1
		end
	end
	local newPet = givePet(player, data, pet.id, pet.evo + 1)
	if #data.Equipped < Config.MaxEquipped then
		table.insert(data.Equipped, newPet.uid)
	end
	local evo = Config.Evolutions[newPet.evo]
	Remotes.FX:FireClient(player, "Evolve", { petId = newPet.id, uid = newPet.uid, evo = newPet.evo })
	Remotes.Notify:FireAllClients("🧬 " .. player.DisplayName .. " a fait evoluer un " .. Config.PetById[pet.id].icon .. " " .. pet.id .. " en " .. evo.icon .. " " .. evo.name .. " !", "gold")
	PetService.Sync(player)
end

local function deletePet(player, uid)
	local data = DataService.Get(player)
	if not data then
		return
	end
	uid = tonumber(uid)
	local pet, i = findPet(data, uid)
	if not pet then
		return
	end
	table.remove(data.Pets, i)
	local eq = table.find(data.Equipped, uid)
	if eq then
		table.remove(data.Equipped, eq)
	end
	local rarity = Config.RarityById[Config.PetById[pet.id].rarity]
	local refund = math.floor(10 * rarity.power * Config.Evolutions[pet.evo].mult)
	PetService.AddCoins(player, refund)
	notify(player, "🗑️ Pet supprime (+" .. refund .. " coins)", "info")
	PetService.Sync(player)
end

-- Zones -----------------------------------------------------------------------------

local function unlockZone(player, zoneId)
	local data = DataService.Get(player)
	local zone = Config.ZoneById[zoneId]
	if not data or not zone or data.Zones[zoneId] then
		return
	end
	if data.Coins < zone.price then
		notify(player, "🔒 Il te faut " .. zone.price .. " coins pour " .. zone.name .. " (tu as " .. math.floor(data.Coins) .. ").", "danger")
		return
	end
	data.Coins -= zone.price
	data.Zones[zoneId] = true
	Remotes.Notify:FireAllClients("🗺️ " .. player.DisplayName .. " a debloque " .. zone.icon .. " " .. zone.name .. " !", "gold")
	Remotes.FX:FireClient(player, "ZoneUnlock", { zoneId = zoneId })
	PetService.Sync(player)
end

local function teleport(player, zoneId)
	local data = DataService.Get(player)
	local zone = Config.ZoneById[zoneId]
	if not data or not zone then
		return
	end
	if not data.Zones[zoneId] then
		notify(player, "🔒 Zone verrouillee : va a la porte pour la debloquer.", "danger")
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = CFrame.new(zone.center + Vector3.new(0, 4, zone.size / 2 - 20))
		Remotes.FX:FireClient(player, "Teleport", { zoneId = zoneId })
	end
end

-- Cadeau du jour ---------------------------------------------------------------------

local function daily(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	if os.time() - (data.LastDaily or 0) < Config.Daily.Cooldown then
		local left = Config.Daily.Cooldown - (os.time() - data.LastDaily)
		notify(player, string.format("🎁 Reviens dans %dh%02d pour ton cadeau.", math.floor(left / 3600), math.floor(left % 3600 / 60)), "info")
		return
	end
	data.LastDaily = os.time()
	PetService.AddCoins(player, Config.Daily.Coins)
	-- Petit bonus : un oeuf du village gratuit (pet Common/Uncommon)
	local pool, total = PetService.EggChances("Village", 1)
	local r = math.random() * total
	local chosen = pool[1].pet
	for _, entry in ipairs(pool) do
		r -= entry.weight
		if r <= 0 then
			chosen = entry.pet
			break
		end
	end
	local pet = givePet(player, data, chosen.id, 1)
	Remotes.FX:FireClient(player, "Daily", { coins = Config.Daily.Coins, petId = chosen.id })
	Remotes.FX:FireClient(player, "Hatch", { petId = chosen.id, uid = pet.uid, rarity = chosen.rarity, egg = "Village" })
	PetService.Sync(player)
end

-- Joueurs -------------------------------------------------------------------------------

local function onPlayerAdded(player)
	local data = DataService.Load(player)
	if #data.Pets == 0 then
		local pet = givePet(player, data, "Chaton", 1)
		data.Equipped = { pet.uid }
	end
	player.CharacterAdded:Connect(function(character)
		task.spawn(function()
			local humanoid = character:WaitForChild("Humanoid", 5)
			while character.Parent and humanoid and humanoid.Health > 0 do
				task.wait(0.5)
				local hrp = character:FindFirstChild("HumanoidRootPart")
				if hrp and hrp.Position.Y < Config.Map.KillHeight then
					hrp.CFrame = CFrame.new(Config.Map.SpawnPosition)
				end
			end
		end)
	end)
	task.wait(1)
	if player.Parent ~= Players then
		return
	end
	PetService.Sync(player)
	if data.Hatched == 0 then
		notify(player, "🐾 Bienvenue ! Ton Chaton ramasse les coins avec toi. Va au stand 🥚 pour ouvrir des oeufs.", "good")
	else
		notify(player, "🐾 Bon retour, " .. player.DisplayName .. " !", "good")
	end
end

-- Classement ----------------------------------------------------------------------------

local function updateLeaderboard()
	local label = MapBuilder.LeaderboardLabel
	if not label then
		return
	end
	local entries, seen = {}, {}
	for _, p in ipairs(Players:GetPlayers()) do
		local data = DataService.Get(p)
		if data then
			table.insert(entries, { name = p.DisplayName, value = math.floor(data.TotalCoins) })
			seen[p.UserId] = true
		end
	end
	for _, entry in ipairs(DataService.GetTop(10)) do
		if not seen[entry.userId] then
			local ok, name = pcall(function()
				return Players:GetNameFromUserIdAsync(entry.userId)
			end)
			table.insert(entries, { name = ok and name or "???", value = entry.value })
		end
	end
	table.sort(entries, function(a, b)
		return a.value > b.value
	end)
	local lines = {}
	local medals = { "🥇", "🥈", "🥉" }
	for i = 1, math.min(10, #entries) do
		table.insert(lines, string.format("%s %s  -  %d 🪙", medals[i] or (i .. "."), entries[i].name, entries[i].value))
	end
	label.Text = #lines > 0 and table.concat(lines, "\n") or "Aucun joueur classe"
end

function PetService.Init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		DataService.Save(player)
		DataService.Release(player)
	end)

	Remotes.Pets.OnServerEvent:Connect(function(player, action, a)
		if action == "hatch" then
			hatch(player, tostring(a))
		elseif action == "equip" then
			equip(player, a)
		elseif action == "evolve" then
			evolve(player, a)
		elseif action == "delete" then
			deletePet(player, a)
		elseif action == "unlock" then
			unlockZone(player, tostring(a))
		elseif action == "teleport" then
			teleport(player, tostring(a))
		elseif action == "daily" then
			daily(player)
		elseif action == "sync" then
			PetService.Sync(player)
		end
	end)

	for _, gate in ipairs(CollectionService:GetTagged("Gate")) do
		local prompt = gate:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player)
				unlockZone(player, gate:GetAttribute("ZoneId"))
			end)
		end
	end
	for _, standPart in ipairs(CollectionService:GetTagged("DailyStand")) do
		local prompt = standPart:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(daily)
		end
	end

	task.spawn(function()
		while true do
			pcall(updateLeaderboard)
			task.wait(30)
		end
	end)
end

return PetService
