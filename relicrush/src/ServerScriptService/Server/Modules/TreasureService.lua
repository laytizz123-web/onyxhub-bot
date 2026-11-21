-- Tresors a detruire dans chaque monde + pieces a ramasser (aimant ameliorable).
-- Chaque participant recoit ses propres pieces en proportion de ses degats.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local F = require(ReplicatedStorage.Shared.Formulas)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local Targets = require(script.Parent.Targets)
local WorldBuilder = require(script.Parent.WorldBuilder)

local TreasureService = {}

local counter = 0
local occupied = {} -- [worldId] = { [spotIndex] = true }
local coinsFolder
local coinData = {} -- [Part] = { owner, value, expires }

local function p(model, props)
	local x = Instance.new("Part")
	x.Anchored = true
	x.CanCollide = false
	x.CanQuery = false
	x.CanTouch = false
	x.TopSurface = Enum.SurfaceType.Smooth
	x.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		x[k] = v
	end
	x.Parent = model
	return x
end

local GOLD = Color3.fromRGB(255, 200, 60)

local function buildVisual(model, def, world, base)
	local s = def.scale
	local gem = world.color:Lerp(Color3.fromRGB(150, 220, 255), 0.3)
	if def.id == "Vase" then
		local clay = world.id == "Frozen" and Color3.fromRGB(170, 210, 240) or (world.id == "Lava" and Color3.fromRGB(80, 60, 60) or Color3.fromRGB(205, 120, 75))
		p(model, { Shape = Enum.PartType.Ball, Size = Vector3.new(3.4, 3.4, 3.4) * s, CFrame = base * CFrame.new(0, 1.8 * s, 0), Color = clay, Material = Enum.Material.SmoothPlastic })
		p(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4 * s, 1.6 * s, 1.6 * s), CFrame = base * CFrame.new(0, 3.6 * s, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = clay })
		p(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35 * s, 2.1 * s, 2.1 * s), CFrame = base * CFrame.new(0, 4.3 * s, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = clay:Lerp(Color3.new(0, 0, 0), 0.15) })
		p(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4 * s, 3.5 * s, 3.5 * s), CFrame = base * CFrame.new(0, 2.1 * s, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = GOLD, Material = Enum.Material.Metal })
		return Vector3.new(3.6, 4.6, 3.6) * s
	elseif def.id == "Coffre" then
		p(model, { Size = Vector3.new(4, 2.4, 2.8) * s, CFrame = base * CFrame.new(0, 1.2 * s, 0), Color = Color3.fromRGB(150, 95, 55), Material = Enum.Material.WoodPlanks })
		local lid = p(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 2.8, 2.8) * s, CFrame = base * CFrame.new(0, 2.4 * s, 0), Color = Color3.fromRGB(130, 80, 45), Material = Enum.Material.WoodPlanks })
		for _, x in ipairs({ -1.4, 1.4 }) do
			p(model, { Size = Vector3.new(0.4, 3.9, 2.9) * s, CFrame = base * CFrame.new(x * s, 1.9 * s, 0), Color = GOLD, Material = Enum.Material.Metal })
		end
		p(model, { Size = Vector3.new(0.8, 0.9, 0.3) * s, CFrame = base * CFrame.new(0, 2 * s, -1.45 * s), Color = GOLD, Material = Enum.Material.Metal })
		p(model, { Size = Vector3.new(0.5, 0.5, 0.2) * s, CFrame = base * CFrame.new(0, 2.1 * s, -1.62 * s) * CFrame.Angles(0, 0, math.rad(45)), Color = gem, Material = Enum.Material.Neon })
		return Vector3.new(4.4, 4, 3.2) * s
	else
		-- tresor geant : monticule d'or, gemmes, coffre ouvert
		for k = 1, 9 do
			local a = k * 0.7
			p(model, { Shape = Enum.PartType.Ball, Size = Vector3.new(2.6, 2.6, 2.6) * s * (1 - k * 0.04), CFrame = base * CFrame.new(math.cos(a) * (2.2 - k * 0.2) * s, (0.8 + k * 0.25) * s, math.sin(a) * (2.2 - k * 0.2) * s), Color = GOLD, Material = Enum.Material.Metal, Reflectance = 0.15 })
		end
		for k = 1, 5 do
			local a = k * 1.25
			p(model, { Size = Vector3.new(0.9, 1.8, 0.9) * s, CFrame = base * CFrame.new(math.cos(a) * 2.2 * s, 2.4 * s, math.sin(a) * 2.2 * s) * CFrame.Angles(0.3, a, 0.3), Color = gem, Material = Enum.Material.Neon })
		end
		local light = Instance.new("PointLight")
		light.Color = GOLD
		light.Range = 14
		light.Brightness = 1.5
		light.Parent = model:GetChildren()[1]
		local sp = Instance.new("Sparkles")
		sp.SparkleColor = GOLD
		sp.Parent = model:GetChildren()[1]
		return Vector3.new(6, 4.5, 6) * s
	end
end

local function pickDef()
	local total = 0
	for _, d in ipairs(Config.Treasures) do
		total += d.weight
	end
	local r = math.random() * total
	for _, d in ipairs(Config.Treasures) do
		r -= d.weight
		if r <= 0 then
			return d
		end
	end
	return Config.Treasures[1]
end

local spawnTreasure

local function dropCoins(model, info)
	local pos = model.PrimaryPart.Position
	local world = Config.WorldById[info.world]
	local total = 0
	for _, dmg in pairs(info.hits) do
		total += dmg
	end
	for player, dmg in pairs(info.hits) do
		local data = DataService.Get(player)
		if data and player.Parent == Players then
			local share = total > 0 and dmg / total or 1
			local value = info.coins * share * F.CoinMult(data)
			data.Stats.Breaks += 1
			local n = math.clamp(math.floor(3 + share * 4), 2, 7)
			for i = 1, n do
				local c = Instance.new("Part")
				c.Name = "Coin"
				c.Shape = Enum.PartType.Cylinder
				c.Size = Vector3.new(0.35, 1.6, 1.6)
				c.Color = GOLD
				c.Material = Enum.Material.Metal
				c.Reflectance = 0.2
				c.Anchored = true
				c.CanCollide = false
				c.CanQuery = false
				c.CanTouch = false
				local a = math.random() * math.pi * 2
				local r = 3 + math.random() * 5
				local target = pos + Vector3.new(math.cos(a) * r, -pos.Y + world.center.Y + 1.2, math.sin(a) * r)
				c.CFrame = CFrame.new(pos + Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
				c:SetAttribute("Owner", player.UserId)
				c.Parent = coinsFolder
				TweenService:Create(c, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(target) * CFrame.Angles(0, a, math.rad(90)) }):Play()
				coinData[c] = { owner = player, value = value / n, expires = os.clock() + 12, ready = os.clock() + 0.45 }
			end
		end
	end
	Remotes.FX:FireAllClients("Break", { position = pos, world = info.world, kind = model:GetAttribute("TreasureType") })
	-- disparition
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			TweenService:Create(d, TweenInfo.new(0.35), { Transparency = 1, Size = d.Size * 0.3 }):Play()
		end
	end
	task.delay(0.4, function()
		model:Destroy()
	end)
	occupied[info.world][info.spot] = nil
	task.delay(math.random(Config.TreasureRespawn[1], Config.TreasureRespawn[2]), function()
		spawnTreasure(world)
	end)
end

function spawnTreasure(world)
	local list = WorldBuilder.Spots(world.id)
	occupied[world.id] = occupied[world.id] or {}
	local free = {}
	for i = 1, #list do
		if not occupied[world.id][i] then
			table.insert(free, i)
		end
	end
	if #free == 0 then
		return
	end
	local spot = free[math.random(#free)]
	occupied[world.id][spot] = true
	local def = pickDef()
	-- les 7 premiers emplacements du village sont dans la grotte : tresors plus riches
	if world.id == "Village" and spot <= 7 and def.id == "Vase" then
		def = Config.Treasures[2]
	end
	counter += 1
	local model = Instance.new("Model")
	model.Name = "Treasure" .. counter
	local base = CFrame.new(list[spot]) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	local size = buildVisual(model, def, world, base)
	local hit = p(model, { Name = "Hitbox", Size = size, CFrame = base * CFrame.new(0, size.Y / 2, 0), Transparency = 1, CanQuery = true })
	model.PrimaryPart = hit
	model:SetAttribute("TreasureType", def.id)
	model:SetAttribute("Label", def.name)
	Targets.Register(model, {
		kind = "treasure",
		world = world.id,
		maxHp = math.floor(def.hp * world.mult),
		coins = def.coins * world.mult,
		spot = spot,
		onDeath = dropCoins,
	})
end

-- Ramassage des pieces (rayon = base + aimant)
local dirty = {}
local function collectLoop()
	local tickN = 0
	while true do
		task.wait(0.15)
		tickN += 1
		local now = os.clock()
		for c, info in pairs(coinData) do
			local player = info.owner
			local data = DataService.Get(player)
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local expired = now > info.expires
			if not data or player.Parent ~= Players then
				coinData[c] = nil
				c:Destroy()
			elseif now >= info.ready and (expired or (hrp and (hrp.Position - c.Position).Magnitude <= Config.CoinPickupRadius + (data.Upgrades.Magnet or 0) * F.UpgradeDef("Magnet").per)) then
				coinData[c] = nil
				DataService.AddCoins(player, info.value)
				Remotes.FX:FireClient(player, "Coin", { position = c.Position, amount = info.value })
				c:Destroy()
				dirty[player] = true
			end
		end
		if tickN % 4 == 0 then
			for p2 in pairs(dirty) do
				dirty[p2] = nil
				if p2.Parent == Players then
					DataService.Sync(p2)
				end
			end
		end
	end
end

function TreasureService.Init()
	coinsFolder = Instance.new("Folder")
	coinsFolder.Name = "Coins"
	coinsFolder.Parent = workspace
	for _, w in ipairs(Config.Worlds) do
		for _ = 1, Config.TreasurePerWorld do
			spawnTreasure(w)
		end
	end
	task.spawn(collectLoop)
end

return TreasureService
