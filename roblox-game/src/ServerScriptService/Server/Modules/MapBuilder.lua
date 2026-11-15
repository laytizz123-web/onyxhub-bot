-- Construit la ferme : terrain, place centrale, boutique, stand de vente, 8 parcelles.
-- Aucun asset externe : tout est fait avec des Parts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)

local MapBuilder = {}

local function makePart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		p[key] = value
	end
	return p
end

local function addLabel(parent, text, face, color, font)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.Font = font or Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextStrokeTransparency = 0.6
	label.Parent = gui
	gui.Parent = parent
	return label
end

local function buildLighting()
	Lighting.ClockTime = 13.5
	Lighting.Brightness = 2.5
	Lighting.Ambient = Color3.fromRGB(120, 130, 120)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 150, 140)
	Lighting.FogColor = Color3.fromRGB(200, 225, 255)
	Lighting.FogStart = 300
	Lighting.FogEnd = 1200
	Lighting.GlobalShadows = true
	Lighting.ExposureCompensation = 0.1

	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.4
	bloom.Size = 24
	bloom.Threshold = 1.5
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "FarmColor"
	cc.Contrast = 0.08
	cc.Saturation = 0.25
	cc.Parent = Lighting

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.25
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(199, 220, 255)
	atmosphere.Decay = Color3.fromRGB(120, 160, 220)
	atmosphere.Glare = 0.4
	atmosphere.Haze = 1.2
	atmosphere.Parent = Lighting

	local sky = Instance.new("Sky")
	sky.SunAngularSize = 14
	sky.Parent = Lighting
end

local function buildTree(root, position, scale)
	scale = scale or 1
	local trunk = makePart({
		Name = "Tree",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(7 * scale, 1.6 * scale, 1.6 * scale),
		CFrame = CFrame.new(position + Vector3.new(0, 3.5 * scale, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(110, 75, 45),
	})
	trunk.Parent = root
	for i = 1, 3 do
		local r = (5.5 - i * 0.9) * scale
		local leaves = makePart({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(r * 2, r * 2, r * 2),
			CFrame = CFrame.new(position + Vector3.new(0, (6 + i * 2.2) * scale, 0)),
			Material = Enum.Material.Grass,
			Color = Color3.fromRGB(60 + i * 15, 150 + i * 15, 60),
			CanCollide = false,
		})
		leaves.Parent = root
	end
end

local function buildStand(root, position, lookAt, title, color, promptText, tag)
	local base = makePart({
		Name = tag,
		Size = Vector3.new(12, 4, 5),
		CFrame = CFrame.lookAt(position + Vector3.new(0, 2, 0), Vector3.new(lookAt.X, position.Y + 2, lookAt.Z)),
		Material = Enum.Material.WoodPlanks,
		Color = Config.Colors.Wood,
	})
	base.Parent = root
	local roof = makePart({
		Name = "Roof",
		Size = Vector3.new(14, 0.6, 8),
		CFrame = base.CFrame * CFrame.new(0, 6, 0),
		Material = Enum.Material.Fabric,
		Color = color,
	})
	roof.Parent = root
	for _, x in ipairs({ -6, 6 }) do
		local pole = makePart({
			Name = "Pole",
			Size = Vector3.new(0.6, 8, 0.6),
			CFrame = base.CFrame * CFrame.new(x, 2.5, 2.5),
			Material = Enum.Material.Wood,
			Color = Config.Colors.Wood,
		})
		pole.Parent = root
	end
	local sign = makePart({
		Name = "Sign",
		Size = Vector3.new(12, 2.4, 0.4),
		CFrame = base.CFrame * CFrame.new(0, 4.6, -3.2),
		Material = Enum.Material.SmoothPlastic,
		Color = Config.Colors.Dark,
	})
	sign.Parent = root
	addLabel(sign, title, Enum.NormalId.Front, color)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = promptText
	prompt.ObjectText = title
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = base
	CollectionService:AddTag(base, tag)
	return base
end

local function buildHub(root)
	local ground = makePart({
		Name = "Ground",
		Size = Vector3.new(520, 4, 520),
		CFrame = CFrame.new(0, -2, 0),
		Material = Enum.Material.Grass,
		Color = Config.Colors.Grass,
	})
	ground.Parent = root

	local plaza = makePart({
		Name = "Plaza",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 70, 70),
		CFrame = CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Cobblestone,
		Color = Color3.fromRGB(190, 180, 160),
	})
	plaza.Parent = root

	-- Fontaine centrale
	local fountain = makePart({
		Name = "Fountain",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 14, 14),
		CFrame = CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Marble,
		Color = Color3.fromRGB(230, 230, 235),
	})
	fountain.Parent = root
	local water = makePart({
		Name = "Water",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 12, 12),
		CFrame = CFrame.new(0, 2.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Glass,
		Color = Color3.fromRGB(80, 170, 255),
		Transparency = 0.3,
		CanCollide = false,
	})
	water.Parent = root
	local jet = makePart({
		Name = "Jet",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(0, 3, 0),
		Transparency = 1,
		CanCollide = false,
	})
	jet.Parent = root
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 40
	emitter.Lifetime = NumberRange.new(1, 1.4)
	emitter.Speed = NumberRange.new(18, 24)
	emitter.SpreadAngle = Vector2.new(8, 8)
	emitter.Acceleration = Vector3.new(0, -40, 0)
	emitter.Size = NumberSequence.new(0.6)
	emitter.Transparency = NumberSequence.new(0.3, 1)
	emitter.Color = ColorSequence.new(Color3.fromRGB(170, 220, 255))
	emitter.Parent = jet

	-- Boutique et stand de vente
	buildStand(root, Vector3.new(-22, 0.4, -14), Vector3.new(0, 0, 0), "GRAINES", Config.Colors.Accent, "Ouvrir", "ShopStand")
	buildStand(root, Vector3.new(22, 0.4, -14), Vector3.new(0, 0, 0), "VENTE", Config.Colors.Gold, "Tout vendre", "SellStand")

	-- Spawn
	local existingSpawn = workspace:FindFirstChildOfClass("SpawnLocation")
	if existingSpawn then
		existingSpawn:Destroy()
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Size = Vector3.new(10, 0.4, 10)
	spawn.CFrame = CFrame.new(0, 0.5, 16)
	spawn.Anchored = true
	spawn.Material = Enum.Material.Cobblestone
	spawn.Color = Color3.fromRGB(210, 200, 180)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = root

	-- Decor
	for i = 1, 26 do
		local angle = (i / 26) * math.pi * 2 + 0.3
		local radius = 150 + (i % 3) * 25
		buildTree(root, Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius), 0.9 + (i % 4) * 0.25)
	end
	for i = 1, 40 do
		local angle = math.random() * math.pi * 2
		local radius = 40 + math.random() * 200
		local flower = makePart({
			Name = "Flower",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.8, 0.8, 0.8),
			CFrame = CFrame.new(math.cos(angle) * radius, 0.4, math.sin(angle) * radius),
			Material = Enum.Material.Neon,
			Color = ({ Color3.fromRGB(255, 120, 180), Color3.fromRGB(255, 230, 80), Color3.fromRGB(150, 150, 255) })[(i % 3) + 1],
			CanCollide = false,
		})
		flower.Parent = root
	end
end

-- Parcelles --------------------------------------------------------------

local plotFolders = {}
local plotSpawns = {}

local function plotOrigin(plotId)
	local angle = ((plotId - 1) / Config.Plot.Count) * math.pi * 2
	return Vector3.new(math.cos(angle) * Config.Plot.Distance, 0, math.sin(angle) * Config.Plot.Distance), angle
end

local function buildPlot(root, plotId)
	local plot = Config.Plot
	local origin, angle = plotOrigin(plotId)
	local pitch = plot.TileSize + plot.TileGap
	local span = plot.Grid * pitch

	local folder = Instance.new("Folder")
	folder.Name = "Plot" .. plotId
	folder:SetAttribute("PlotId", plotId)
	folder:SetAttribute("OwnerId", 0)
	folder:SetAttribute("OwnerName", "")
	folder:SetAttribute("ExpandLevel", 0)

	local rotation = CFrame.new(origin) * CFrame.Angles(0, -angle + math.pi / 2, 0)

	local base = makePart({
		Name = "PlotBase",
		Size = Vector3.new(span + 8, 0.6, span + 8),
		CFrame = rotation * CFrame.new(0, 0.3, 0),
		Material = Enum.Material.Grass,
		Color = Color3.fromRGB(120, 190, 85),
	})
	base.Parent = folder

	-- Cloture
	local half = (span + 8) / 2
	local fenceLen = span + 8
	for _, side in ipairs({ { 0, half }, { 0, -half }, { half, 0 }, { -half, 0 } }) do
		local horizontal = side[2] ~= 0
		local fence = makePart({
			Name = "Fence",
			Size = horizontal and Vector3.new(fenceLen, 2.2, 0.4) or Vector3.new(0.4, 2.2, fenceLen),
			CFrame = rotation * CFrame.new(side[1], 1.5, side[2]),
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(220, 200, 160),
			CanCollide = false,
		})
		fence.Parent = folder
	end

	-- Panneau du proprietaire
	local sign = makePart({
		Name = "Sign",
		Size = Vector3.new(14, 3, 0.5),
		CFrame = rotation * CFrame.new(0, 4.5, -half - 1),
		Material = Enum.Material.WoodPlanks,
		Color = Config.Colors.Wood,
	})
	sign.Parent = folder
	local label = addLabel(sign, "Parcelle libre", Enum.NormalId.Front, Color3.new(1, 1, 1))
	label.Name = "OwnerLabel"
	addLabel(sign, "Parcelle libre", Enum.NormalId.Back, Color3.new(1, 1, 1)).Name = "OwnerLabelBack"

	-- Point d'apparition du joueur devant sa parcelle (cote centre)
	local spawnPoint = rotation * CFrame.new(0, 3, -half - 5)
	plotSpawns[plotId] = spawnPoint

	-- Cases
	local tiles = Instance.new("Folder")
	tiles.Name = "Tiles"
	tiles.Parent = folder
	local center = (plot.Grid + 1) / 2
	for row = 1, plot.Grid do
		for col = 1, plot.Grid do
			local index = (row - 1) * plot.Grid + col
			local ring = math.max(math.abs(row - center), math.abs(col - center)) -- 0 = centre, 1, 2
			local tile = makePart({
				Name = "Tile" .. index,
				Size = Vector3.new(plot.TileSize, 0.5, plot.TileSize),
				CFrame = rotation * CFrame.new((col - center) * pitch, 0.75, (row - center) * pitch),
				Material = Enum.Material.Ground,
				Color = Config.Colors.Soil,
			})
			tile:SetAttribute("PlotId", plotId)
			tile:SetAttribute("Index", index)
			tile:SetAttribute("Ring", ring)
			tile:SetAttribute("Plant", "")
			tile:SetAttribute("Progress", 0)
			tile:SetAttribute("Ripe", false)
			tile:SetAttribute("Mutations", "")
			tile:SetAttribute("Locked", ring >= 1)
			CollectionService:AddTag(tile, "Tile")
			tile.Parent = tiles
		end
	end

	folder.Parent = root
	plotFolders[plotId] = folder
	return folder
end

function MapBuilder.Build()
	local old = workspace:FindFirstChild("OnyxFarm")
	if old then
		old:Destroy()
	end
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = "OnyxFarm"
	root.Parent = workspace

	buildLighting()
	buildHub(root)
	for plotId = 1, Config.Plot.Count do
		buildPlot(root, plotId)
	end

	Players.RespawnTime = 2
	return root
end

function MapBuilder.GetPlotFolder(plotId)
	return plotFolders[plotId]
end

function MapBuilder.GetTile(plotId, index)
	local folder = plotFolders[plotId]
	return folder and folder.Tiles:FindFirstChild("Tile" .. index)
end

function MapBuilder.SetPlotOwner(plotId, player)
	local folder = plotFolders[plotId]
	if not folder then
		return
	end
	folder:SetAttribute("OwnerId", player and player.UserId or 0)
	folder:SetAttribute("OwnerName", player and player.DisplayName or "")
	local text = player and ("Ferme de " .. player.DisplayName) or "Parcelle libre"
	for _, gui in ipairs(folder.Sign:GetChildren()) do
		local label = gui:IsA("SurfaceGui") and gui:FindFirstChildOfClass("TextLabel")
		if label then
			label.Text = text
			label.TextColor3 = player and Config.Colors.Accent or Color3.new(1, 1, 1)
		end
	end
end

function MapBuilder.GetPlotSpawn(plotId)
	return plotSpawns[plotId]
end

return MapBuilder
