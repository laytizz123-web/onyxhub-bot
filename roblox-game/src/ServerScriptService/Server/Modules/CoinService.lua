-- Coins dans les zones, collecte automatique par les pets, coffres rares.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local MapBuilder = require(script.Parent.MapBuilder)
local PetService = require(script.Parent.PetService)

local CoinService = {}

local coinsFolder
local coins = {} -- [part] = { zone = zone, value = n, chest = bool }

local function spawnCoin(zone, position)
	local coin = Instance.new("Part")
	coin.Name = "Coin"
	coin.Shape = Enum.PartType.Cylinder
	coin.Size = Vector3.new(0.4, 2.2, 2.2)
	coin.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	coin.Material = Enum.Material.Neon
	coin.Color = Config.Colors.Gold
	coin.Anchored = true
	coin.CanCollide = false
	coin.CanQuery = false
	coin:SetAttribute("Value", zone.coinValue)
	coin.Parent = coinsFolder
	local light = Instance.new("PointLight")
	light.Color = Config.Colors.Gold
	light.Range = 8
	light.Brightness = 1
	light.Parent = coin
	coins[coin] = { zone = zone, value = zone.coinValue }
	return coin
end

local function spawnChest(zone)
	local half = zone.size / 2
	local a = math.random() * math.pi * 2
	local r = 20 + math.random() * (half - 40)
	local pos = zone.center + Vector3.new(math.cos(a) * r, 2.5, math.sin(a) * r)
	local chest = Instance.new("Part")
	chest.Name = "Chest"
	chest.Size = Vector3.new(4, 3, 3)
	chest.CFrame = CFrame.new(pos)
	chest.Material = Enum.Material.Neon
	chest.Color = Config.Colors.Accent2
	chest.Anchored = true
	chest.CanCollide = false
	chest.CanQuery = false
	chest:SetAttribute("Value", zone.chestValue)
	chest:SetAttribute("Chest", true)
	chest.Parent = coinsFolder
	local light = Instance.new("PointLight")
	light.Color = Config.Colors.Accent2
	light.Range = 30
	light.Brightness = 3
	light.Parent = chest
	local beam = Instance.new("Part")
	beam.Name = "ChestBeam"
	beam.Size = Vector3.new(1.5, 200, 1.5)
	beam.CFrame = CFrame.new(pos + Vector3.new(0, 100, 0))
	beam.Material = Enum.Material.Neon
	beam.Color = Config.Colors.Accent2
	beam.Transparency = 0.6
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.Parent = chest
	coins[chest] = { zone = zone, value = zone.chestValue, chest = true }
	Remotes.Notify:FireAllClients("🎁 Un coffre rare est apparu dans " .. zone.icon .. " " .. zone.name .. " ! (" .. zone.chestValue .. " coins)", "gold")
	Remotes.FX:FireAllClients("ChestSpawn", { position = pos, zoneId = zone.id })
	task.delay(Config.Collect.ChestLifetime, function()
		if coins[chest] then
			coins[chest] = nil
			chest:Destroy()
		end
	end)
end

local function collect(player, coin, info)
	coins[coin] = nil
	local data = DataService.Get(player)
	if not data then
		coin:Destroy()
		return
	end
	local power = PetService.GetPower(player)
	local amount = math.floor(info.value * (1 + power * 0.08) + 0.5)
	PetService.AddCoins(player, amount)
	Remotes.FX:FireAllClients("Collect", { position = coin.Position, userId = player.UserId, amount = amount, chest = info.chest or false })
	if info.chest then
		Remotes.Notify:FireAllClients("🎁 " .. player.DisplayName .. " a ouvert le coffre et gagne " .. amount .. " coins !", "gold")
	end
	coin:Destroy()
	PetService.Sync(player)
	if not info.chest then
		task.delay(Config.Collect.CoinRespawn + math.random() * 4, function()
			local spots = MapBuilder.GetCoinSpots(info.zone.id)
			spawnCoin(info.zone, spots[math.random(#spots)])
		end)
	end
end

local function collectLoop()
	while true do
		task.wait(Config.Collect.Tick)
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local data = DataService.Get(player)
			if hrp and data then
				local equipped = PetService.GetEquippedPets(player)
				local radius = Config.Collect.BaseRadius + #equipped * Config.Collect.RadiusPerPet
				for coin, info in pairs(coins) do
					if coin.Parent then
						local dist = (coin.Position - hrp.Position).Magnitude
						local reach = info.chest and 8 or radius
						if dist <= reach and (info.chest or data.Zones[info.zone.id]) then
							collect(player, coin, info)
						end
					else
						coins[coin] = nil
					end
				end
			end
		end
	end
end

function CoinService.Init()
	coinsFolder = workspace:FindFirstChild("Coins") or Instance.new("Folder")
	coinsFolder.Name = "Coins"
	coinsFolder.Parent = workspace
	for _, zone in ipairs(Config.Zones) do
		for _, spot in ipairs(MapBuilder.GetCoinSpots(zone.id)) do
			spawnCoin(zone, spot)
		end
	end
	task.spawn(collectLoop)
	task.spawn(function()
		task.wait(60)
		while true do
			local zone = Config.Zones[math.random(#Config.Zones)]
			spawnChest(zone)
			task.wait(math.random(Config.Collect.ChestInterval[1], Config.Collect.ChestInterval[2]))
		end
	end)
end

return CoinService
