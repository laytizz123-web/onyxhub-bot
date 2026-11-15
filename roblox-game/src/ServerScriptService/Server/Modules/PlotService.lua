-- Parcelles : attribution, plantation, croissance, arrosage, recolte, mutations, expansion.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Economy = require(ReplicatedStorage.Shared.Economy)
local MapBuilder = require(script.Parent.MapBuilder)
local PlantVisuals = require(script.Parent.PlantVisuals)
local DataService = require(script.Parent.DataService)

local PlotService = {}

local WeatherService -- injecte

-- plots[plotId] = { owner = Player?, tiles = { [index] = record } }
-- record = { id, progress, mutations = {}, ripe = bool, stage = n }
local plots = {}
local playerPlot = {} -- [Player] = plotId
local waterCooldown = {} -- [Player] = os.clock()

for plotId = 1, Config.Plot.Count do
	plots[plotId] = { owner = nil, tiles = {} }
end

local function stageFor(progress)
	if progress >= 1 then
		return 3
	elseif progress >= 0.6 then
		return 2
	elseif progress >= 0.25 then
		return 1
	end
	return 0
end

local function tileOf(plotId, index)
	return MapBuilder.GetTile(plotId, index)
end

local function tileIsUnlocked(plotId, tile)
	local folder = MapBuilder.GetPlotFolder(plotId)
	local level = folder and folder:GetAttribute("ExpandLevel") or 0
	return (tile:GetAttribute("Ring") or 0) <= level + 1
end

local function refreshTile(plotId, index, rebuild)
	local tile = tileOf(plotId, index)
	if not tile then
		return
	end
	local record = plots[plotId].tiles[index]
	if not record then
		tile:SetAttribute("Plant", "")
		tile:SetAttribute("Progress", 0)
		tile:SetAttribute("Ripe", false)
		tile:SetAttribute("Mutations", "")
		PlantVisuals.Clear(tile)
		return
	end
	tile:SetAttribute("Plant", record.id)
	tile:SetAttribute("Progress", math.floor(math.min(record.progress, 1) * 100) / 100)
	tile:SetAttribute("Ripe", record.ripe)
	tile:SetAttribute("Mutations", table.concat(record.mutations, ","))
	local stage = stageFor(record.progress)
	if rebuild or stage ~= record.stage then
		record.stage = stage
		PlantVisuals.Build(tile, Config.PlantById[record.id], stage, record.mutations)
	end
end

local function setTileLocks(plotId)
	local folder = MapBuilder.GetPlotFolder(plotId)
	if not folder then
		return
	end
	for _, tile in ipairs(folder.Tiles:GetChildren()) do
		local locked = not tileIsUnlocked(plotId, tile)
		tile:SetAttribute("Locked", locked)
		tile.Material = locked and Enum.Material.Cobblestone or Enum.Material.Ground
		tile.Color = locked and Color3.fromRGB(120, 120, 115) or Config.Colors.Soil
		tile.Transparency = locked and 0.35 or 0
	end
end

local function ripen(plotId, index, record)
	record.progress = 1
	record.ripe = true
	-- Mutations rares a la maturation
	for name, chance in pairs(Config.RipeMutationChance) do
		if math.random() < chance and not table.find(record.mutations, name) then
			table.insert(record.mutations, name)
		end
	end
	refreshTile(plotId, index, true)
	local tile = tileOf(plotId, index)
	local owner = plots[plotId].owner
	if tile then
		Remotes.FX:FireAllClients("Ripe", { position = tile.Position, mutations = record.mutations, owner = owner and owner.UserId or 0 })
	end
end

-- Inventaire -------------------------------------------------------------

function PlotService.SyncInventory(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local fruits = {}
	local totalValue = 0
	for i, fruit in ipairs(data.Fruits) do
		local value = Economy.value(fruit)
		totalValue += value
		fruits[i] = { id = fruit.id, mutations = fruit.mutations, weight = fruit.weight, value = value }
	end
	Remotes.Inventory:FireClient(player, {
		coins = math.floor(data.Coins),
		seeds = data.Seeds,
		fruits = fruits,
		fruitValue = totalValue,
		plotId = playerPlot[player] or 0,
		expandLevel = data.ExpandLevel or 0,
		expandPrice = Config.Plot.ExpandPrices[(data.ExpandLevel or 0) + 1],
		harvests = data.Harvests or 0,
	})
end

-- Actions joueur -----------------------------------------------------------

local function plant(player, plotId, index, seedId)
	local data = DataService.Get(player)
	local def = Config.PlantById[seedId]
	if not data or not def then
		Remotes.Notify:FireClient(player, "Choisis une graine dans ta barre (touches 1-9).", "info")
		return
	end
	if (data.Seeds[seedId] or 0) <= 0 then
		Remotes.Notify:FireClient(player, "Tu n'as plus de graine de " .. def.id .. ".", "danger")
		return
	end
	data.Seeds[seedId] -= 1
	if data.Seeds[seedId] <= 0 then
		data.Seeds[seedId] = nil
	end
	plots[plotId].tiles[index] = { id = seedId, progress = 0, mutations = {}, ripe = false, stage = -1 }
	refreshTile(plotId, index, true)
	local tile = tileOf(plotId, index)
	Remotes.FX:FireAllClients("Plant", { position = tile.Position })
	PlotService.SyncInventory(player)
end

local function harvest(player, plotId, index, record)
	local data = DataService.Get(player)
	local def = Config.PlantById[record.id]
	if not data or not def then
		return
	end
	if #data.Fruits >= 300 then
		Remotes.Notify:FireClient(player, "Ton sac est plein ! Va vendre au stand.", "danger")
		return
	end
	local fruit = { id = record.id, mutations = table.clone(record.mutations), weight = Economy.rollWeight(def) }
	table.insert(data.Fruits, fruit)
	data.Harvests += 1
	DataService.Sync(player)

	local tile = tileOf(plotId, index)
	local value = Economy.value(fruit)
	Remotes.FX:FireAllClients("Harvest", {
		position = tile.Position,
		color = def.color,
		name = Economy.fruitName(fruit),
		weight = fruit.weight,
		value = value,
		owner = player.UserId,
		mutations = fruit.mutations,
	})

	if def.multi then
		record.progress = 0.55
		record.ripe = false
		record.mutations = {}
		refreshTile(plotId, index, true)
	else
		plots[plotId].tiles[index] = nil
		refreshTile(plotId, index, true)
	end
	PlotService.SyncInventory(player)
end

local function water(player, plotId, index, record)
	local now = os.clock()
	local last = waterCooldown[player] or 0
	if now - last < Config.Water.Cooldown then
		Remotes.Notify:FireClient(player, string.format("Arrosoir en recharge (%.0fs)", Config.Water.Cooldown - (now - last)), "info")
		return
	end
	waterCooldown[player] = now
	record.progress = math.min(record.progress + Config.Water.Boost, 1)
	if record.progress >= 1 then
		ripen(plotId, index, record)
	else
		refreshTile(plotId, index, false)
	end
	local tile = tileOf(plotId, index)
	Remotes.FX:FireAllClients("Water", { position = tile.Position, owner = player.UserId })
end

local function onAction(player, plotId, index, seedId)
	plotId = tonumber(plotId)
	index = tonumber(index)
	if not plotId or not index or playerPlot[player] ~= plotId then
		return
	end
	local tile = tileOf(plotId, index)
	if not tile then
		return
	end
	if not tileIsUnlocked(plotId, tile) then
		local price = Config.Plot.ExpandPrices[(DataService.Get(player).ExpandLevel or 0) + 1]
		Remotes.Notify:FireClient(player, price and ("Case verrouillee : agrandis ta parcelle (" .. Economy.formatCoins(price) .. " pieces)") or "Case verrouillee", "info")
		return
	end
	local record = plots[plotId].tiles[index]
	if not record then
		plant(player, plotId, index, tostring(seedId))
	elseif record.ripe then
		harvest(player, plotId, index, record)
	else
		water(player, plotId, index, record)
	end
end

-- Meteo ------------------------------------------------------------------

function PlotService.AddMutation(tile, name)
	local plotId = tile:GetAttribute("PlotId")
	local index = tile:GetAttribute("Index")
	local record = plots[plotId] and plots[plotId].tiles[index]
	if not record or table.find(record.mutations, name) then
		return
	end
	if name == "Gele" then
		local i = table.find(record.mutations, "Mouille")
		if i then
			table.remove(record.mutations, i)
		end
	end
	table.insert(record.mutations, name)
	refreshTile(plotId, index, true)
	local owner = plots[plotId].owner
	if owner then
		Remotes.Notify:FireClient(owner, "Mutation " .. Config.Mutations[name].label .. " sur ta " .. record.id .. " !", "mutation")
	end
end

function PlotService.ApplyWeatherMutation(name, chance)
	for plotId, plot in pairs(plots) do
		if plot.owner then
			for index, record in pairs(plot.tiles) do
				if record.progress > 0.05 and math.random() < chance then
					local tile = tileOf(plotId, index)
					if tile then
						PlotService.AddMutation(tile, name)
					end
				end
			end
		end
	end
end

function PlotService.RandomPlantedTile()
	local candidates = {}
	for plotId, plot in pairs(plots) do
		if plot.owner then
			for index, record in pairs(plot.tiles) do
				if record.progress > 0.05 then
					table.insert(candidates, tileOf(plotId, index))
				end
			end
		end
	end
	if #candidates == 0 then
		return nil
	end
	return candidates[math.random(#candidates)]
end

-- Expansion ---------------------------------------------------------------

function PlotService.ApplyExpandLevel(player)
	local plotId = playerPlot[player]
	local data = DataService.Get(player)
	local folder = plotId and MapBuilder.GetPlotFolder(plotId)
	if not folder or not data then
		return
	end
	folder:SetAttribute("ExpandLevel", data.ExpandLevel or 0)
	setTileLocks(plotId)
end

-- Croissance --------------------------------------------------------------

local function growthLoop()
	local last = os.clock()
	while true do
		task.wait(1)
		local now = os.clock()
		local dt = now - last
		last = now
		local mult = WeatherService and WeatherService.GetGrowthMultiplier() or 1
		for plotId, plot in pairs(plots) do
			if plot.owner then
				for index, record in pairs(plot.tiles) do
					if not record.ripe then
						local def = Config.PlantById[record.id]
						record.progress += (dt / def.growTime) * mult
						if record.progress >= 1 then
							ripen(plotId, index, record)
						else
							refreshTile(plotId, index, false)
						end
					end
				end
			end
		end
	end
end

-- Joueurs ---------------------------------------------------------------------

local function findFreePlot()
	for plotId = 1, Config.Plot.Count do
		if not plots[plotId].owner then
			return plotId
		end
	end
	return nil
end

local function loadTiles(player, plotId, data)
	local elapsed = math.clamp(os.time() - (data.SavedAt or os.time()), 0, Config.OfflineGrowthCap)
	local grown = 0
	for key, saved in pairs(data.Tiles or {}) do
		local index = tonumber(key)
		local def = Config.PlantById[saved.id]
		if index and def and tileOf(plotId, index) then
			local record = { id = saved.id, progress = saved.progress or 0, mutations = saved.mutations or {}, ripe = saved.ripe == true, stage = -1 }
			if not record.ripe then
				record.progress += elapsed / def.growTime
				if record.progress >= 1 then
					record.progress = 1
					record.ripe = true
					grown += 1
				end
			end
			plots[plotId].tiles[index] = record
			refreshTile(plotId, index, true)
		end
	end
	if grown > 0 then
		task.delay(2, function()
			if player.Parent ~= Players then
				return
			end
			Remotes.Notify:FireClient(player, grown .. " plante(s) ont muri pendant ton absence !", "good")
		end)
	end
end

local function serializeTiles(player, data)
	local plotId = playerPlot[player]
	if not plotId then
		return
	end
	local tiles = {}
	for index, record in pairs(plots[plotId].tiles) do
		tiles[tostring(index)] = { id = record.id, progress = record.progress, mutations = record.mutations, ripe = record.ripe }
	end
	data.Tiles = tiles
end

local function onPlayerAdded(player)
	local data = DataService.Load(player)
	local plotId = findFreePlot()
	if not plotId then
		Remotes.Notify:FireClient(player, "Toutes les parcelles sont occupees sur ce serveur.", "danger")
		return
	end
	plots[plotId].owner = player
	plots[plotId].tiles = {}
	playerPlot[player] = plotId
	MapBuilder.SetPlotOwner(plotId, player)
	local folder = MapBuilder.GetPlotFolder(plotId)
	folder:SetAttribute("ExpandLevel", data.ExpandLevel or 0)
	setTileLocks(plotId)
	loadTiles(player, plotId, data)

	local function onCharacter(character)
		local hrp = character:WaitForChild("HumanoidRootPart", 5)
		task.wait(0.2)
		local spawnCF = MapBuilder.GetPlotSpawn(plotId)
		if hrp and spawnCF then
			hrp.CFrame = spawnCF
		end
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end

	task.wait(1)
	if player.Parent ~= Players then
		return
	end
	PlotService.SyncInventory(player)
	if (data.Harvests or 0) == 0 then
		Remotes.Notify:FireClient(player, "Bienvenue ! Clique sur une case de ta parcelle pour planter une carotte.", "good")
	else
		Remotes.Notify:FireClient(player, "Bon retour sur ta ferme, " .. player.DisplayName .. " !", "good")
	end
end

local function onPlayerRemoving(player)
	DataService.Save(player)
	local plotId = playerPlot[player]
	if plotId then
		plots[plotId].owner = nil
		for index in pairs(plots[plotId].tiles) do
			local tile = tileOf(plotId, index)
			if tile then
				PlantVisuals.Clear(tile)
				tile:SetAttribute("Plant", "")
				tile:SetAttribute("Progress", 0)
				tile:SetAttribute("Ripe", false)
				tile:SetAttribute("Mutations", "")
			end
		end
		plots[plotId].tiles = {}
		MapBuilder.SetPlotOwner(plotId, nil)
		local folder = MapBuilder.GetPlotFolder(plotId)
		folder:SetAttribute("ExpandLevel", 0)
		setTileLocks(plotId)
	end
	playerPlot[player] = nil
	waterCooldown[player] = nil
	DataService.Release(player)
end

function PlotService.Init(weatherService)
	WeatherService = weatherService
	DataService.BeforeSave = serializeTiles
	for plotId = 1, Config.Plot.Count do
		setTileLocks(plotId)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, p)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	Remotes.Action.OnServerEvent:Connect(onAction)
	task.spawn(growthLoop)
end

return PlotService
