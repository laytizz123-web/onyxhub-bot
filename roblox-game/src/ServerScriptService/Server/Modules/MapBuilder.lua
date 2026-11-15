-- Map de PET RUSH : 3 zones (Village, Foret, Desert), portes, stands a oeufs, piste de course, classement.

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

local function addLabel(parent, text, face, color)
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
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextStrokeTransparency = 0.5
	label.Parent = gui
	gui.Parent = parent
	return label
end

local function buildLighting()
	Lighting.ClockTime = 13
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(120, 125, 140)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 155, 170)
	Lighting.FogColor = Color3.fromRGB(205, 225, 255)
	Lighting.FogStart = 350
	Lighting.FogEnd = 1400
	Lighting.GlobalShadows = true
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.5
	bloom.Size = 24
	bloom.Threshold = 1.4
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "PetColor"
	cc.Saturation = 0.35
	cc.Contrast = 0.08
	cc.Parent = Lighting
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.22
	atmosphere.Color = Color3.fromRGB(205, 225, 255)
	atmosphere.Decay = Color3.fromRGB(150, 180, 230)
	atmosphere.Glare = 0.4
	atmosphere.Haze = 1
	atmosphere.Parent = Lighting
	local sky = Instance.new("Sky")
	sky.SunAngularSize = 16
	sky.Parent = Lighting
end

local function tree(root, position, scale, leafColor)
	scale = scale or 1
	makePart({ Name = "Tree", Size = Vector3.new(1.4 * scale, 6 * scale, 1.4 * scale), CFrame = CFrame.new(position + Vector3.new(0, 3 * scale, 0)), Material = Enum.Material.Wood, Color = Color3.fromRGB(110, 75, 45) }).Parent = root
	for i = 1, 3 do
		local r = (4.5 - i * 0.8) * scale
		makePart({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(r * 2, r * 2, r * 2), CFrame = CFrame.new(position + Vector3.new(0, (5 + i * 2) * scale, 0)), Material = Enum.Material.Grass, Color = (leafColor or Color3.fromRGB(70, 170, 80)):Lerp(Color3.new(1, 1, 1), i * 0.08), CanCollide = false }).Parent = root
	end
end

local function cactus(root, position)
	makePart({ Name = "Cactus", Size = Vector3.new(1.4, 6, 1.4), CFrame = CFrame.new(position + Vector3.new(0, 3, 0)), Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(70, 160, 80) }).Parent = root
	for _, x in ipairs({ -1.4, 1.4 }) do
		makePart({ Name = "CactusArm", Size = Vector3.new(1, 3, 1), CFrame = CFrame.new(position + Vector3.new(x, 4, 0)), Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(70, 160, 80) }).Parent = root
	end
end

local function stand(root, position, lookAt, title, icon, color, tag, attrs)
	local base = makePart({ Name = tag, Size = Vector3.new(10, 3, 5), CFrame = CFrame.lookAt(position + Vector3.new(0, 1.5, 0), Vector3.new(lookAt.X, position.Y + 1.5, lookAt.Z)), Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(150, 105, 60) })
	base.Parent = root
	local roof = makePart({ Name = "Roof", Size = Vector3.new(12, 0.6, 8), CFrame = base.CFrame * CFrame.new(0, 6, 0), Material = Enum.Material.Fabric, Color = color })
	roof.Parent = root
	for _, x in ipairs({ -5, 5 }) do
		makePart({ Name = "Pole", Size = Vector3.new(0.5, 8, 0.5), CFrame = base.CFrame * CFrame.new(x, 2.5, 2.5), Material = Enum.Material.Wood, Color = Color3.fromRGB(150, 105, 60) }).Parent = root
	end
	local sign = makePart({ Name = "Sign", Size = Vector3.new(11, 2.4, 0.4), CFrame = base.CFrame * CFrame.new(0, 4.5, -3), Material = Enum.Material.SmoothPlastic, Color = Config.Colors.Panel })
	sign.Parent = root
	addLabel(sign, icon .. " " .. title, Enum.NormalId.Front, color)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Ouvrir"
	prompt.ObjectText = title
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = base
	for k, v in pairs(attrs or {}) do
		base:SetAttribute(k, v)
	end
	CollectionService:AddTag(base, tag)
	return base
end

local function eggDisplay(root, position, color)
	local egg = makePart({ Name = "EggDisplay", Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3.8, 3), CFrame = CFrame.new(position + Vector3.new(0, 8.5, 0)), Material = Enum.Material.Neon, Color = color, CanCollide = false })
	egg.Parent = root
	TweenService:Create(egg, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { CFrame = egg.CFrame * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, math.pi, 0) }):Play()
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 14
	light.Brightness = 2
	light.Parent = egg
end

local zoneRoots = {}
local coinSpots = {}

local function buildZone(root, zone, index)
	local folder = Instance.new("Folder")
	folder.Name = "Zone_" .. zone.id
	folder:SetAttribute("ZoneId", zone.id)
	folder.Parent = root
	zoneRoots[zone.id] = folder
	local c = zone.center
	local half = zone.size / 2

	local ground = makePart({ Name = "Ground", Size = Vector3.new(zone.size, 4, zone.size), CFrame = CFrame.new(c - Vector3.new(0, 2, 0)), Material = zone.id == "Desert" and Enum.Material.Sand or Enum.Material.Grass, Color = zone.ground })
	ground.Parent = folder
	-- Bordure
	local border = makePart({ Name = "Border", Size = Vector3.new(zone.size + 2, 1, zone.size + 2), CFrame = CFrame.new(c - Vector3.new(0, 4.4, 0)), Material = Enum.Material.Neon, Color = Config.Colors.Accent })
	border.Parent = folder
	-- Murs invisibles
	for _, def in ipairs({ { Vector3.new(zone.size, 40, 2), Vector3.new(0, 20, half) }, { Vector3.new(zone.size, 40, 2), Vector3.new(0, 20, -half) }, { Vector3.new(2, 40, zone.size), Vector3.new(half, 20, 0) }, { Vector3.new(2, 40, zone.size), Vector3.new(-half, 20, 0) } }) do
		local wall = makePart({ Name = "Wall", Size = def[1], CFrame = CFrame.new(c + def[2]), Transparency = 1 })
		wall.Parent = folder
	end

	-- Panneau de zone
	local sign = makePart({ Name = "ZoneSign", Size = Vector3.new(30, 6, 1), CFrame = CFrame.new(c + Vector3.new(0, 12, half - 6)), Material = Enum.Material.SmoothPlastic, Color = Config.Colors.Panel })
	sign.Parent = folder
	addLabel(sign, zone.icon .. " " .. zone.name, Enum.NormalId.Front, Config.Colors.Gold)
	addLabel(sign, zone.icon .. " " .. zone.name, Enum.NormalId.Back, Config.Colors.Gold)

	-- Decor
	for i = 1, 22 do
		local a = (i / 22) * math.pi * 2
		local r = half - 12 - (i % 3) * 8
		local pos = c + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		if math.abs(pos.Z - c.Z) < half - 30 or math.abs(pos.X - c.X) > 30 then
			if zone.id == "Desert" then
				cactus(folder, pos)
			else
				tree(folder, pos, 0.8 + (i % 4) * 0.25, zone.id == "Foret" and Color3.fromRGB(40, 130, 60) or nil)
			end
		end
	end
	if zone.id == "Foret" then
		for i = 1, 30 do
			makePart({ Name = "Mushroom", Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 0.8, 1.2), CFrame = CFrame.new(c + Vector3.new(math.random(-half + 10, half - 10), 0.4, math.random(-half + 10, half - 10))), Material = Enum.Material.Neon, Color = (i % 2 == 0) and Color3.fromRGB(255, 90, 90) or Color3.fromRGB(120, 200, 255), CanCollide = false }).Parent = folder
		end
	elseif zone.id == "Desert" then
		for i = 1, 4 do
			local a = i * 1.7
			local pyr = makePart({ Name = "Pyramid", Size = Vector3.new(14, 14, 14), CFrame = CFrame.new(c + Vector3.new(math.cos(a) * 70, 2, math.sin(a) * 70)) * CFrame.Angles(math.rad(45), 0, math.rad(45)), Material = Enum.Material.Sandstone, Color = Color3.fromRGB(220, 190, 120) })
			pyr.Parent = folder
		end
	else
		-- Maisons du village
		for i = 1, 6 do
			local a = i * 1.05 + 0.5
			local pos = c + Vector3.new(math.cos(a) * 75, 0, math.sin(a) * 75)
			local colors = { Color3.fromRGB(255, 200, 150), Color3.fromRGB(180, 220, 255), Color3.fromRGB(255, 180, 200) }
			makePart({ Name = "House", Size = Vector3.new(12, 9, 12), CFrame = CFrame.new(pos + Vector3.new(0, 4.5, 0)), Material = Enum.Material.SmoothPlastic, Color = colors[(i % 3) + 1] }).Parent = folder
			makePart({ Name = "RoofHouse", Size = Vector3.new(13, 5, 13), CFrame = CFrame.new(pos + Vector3.new(0, 11, 0)) * CFrame.Angles(0, math.rad(45), 0) * CFrame.Angles(math.rad(45), 0, 0) * CFrame.Angles(0, 0, math.rad(45)), Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(200, 70, 60), CanCollide = false }).Parent = folder
		end
	end

	-- Stand a oeuf
	local egg = Config.Eggs[index]
	local eggPos = c + Vector3.new(-50, 0, 20)
	stand(folder, eggPos, c, egg.name, egg.icon, egg.color, "EggStand", { EggId = egg.id })
	eggDisplay(folder, eggPos, egg.color)

	-- Points de spawn des coins
	coinSpots[zone.id] = {}
	for i = 1, zone.coinCount do
		local a = math.random() * math.pi * 2
		local r = 15 + math.random() * (half - 30)
		table.insert(coinSpots[zone.id], c + Vector3.new(math.cos(a) * r, 2.2, math.sin(a) * r))
	end

	-- Porte vers la zone suivante (au nord : -Z)
	local nextZone = Config.Zones[index + 1]
	if nextZone then
		local gate = makePart({ Name = "Gate", Size = Vector3.new(24, 16, 3), CFrame = CFrame.new(c + Vector3.new(0, 8, -half)), Material = Enum.Material.Neon, Color = Config.Colors.Gold, Transparency = 0.35 })
		gate:SetAttribute("ZoneId", nextZone.id)
		CollectionService:AddTag(gate, "Gate")
		gate.Parent = folder
		local gateSign = makePart({ Name = "GateSign", Size = Vector3.new(24, 4, 0.5), CFrame = CFrame.new(c + Vector3.new(0, 18.5, -half)), Material = Enum.Material.SmoothPlastic, Color = Config.Colors.Panel })
		gateSign.Parent = folder
		addLabel(gateSign, nextZone.icon .. " " .. nextZone.name .. "  🔒 " .. nextZone.price .. " coins", Enum.NormalId.Front, Config.Colors.Gold)
		addLabel(gateSign, nextZone.icon .. " " .. nextZone.name .. "  🔒 " .. nextZone.price .. " coins", Enum.NormalId.Back, Config.Colors.Gold)
		for _, x in ipairs({ -13, 13 }) do
			makePart({ Name = "GatePillar", Size = Vector3.new(3, 20, 3), CFrame = CFrame.new(c + Vector3.new(x, 10, -half)), Material = Enum.Material.Marble, Color = Color3.fromRGB(235, 235, 240) }).Parent = folder
		end
		-- Chemin entre les zones
		makePart({ Name = "Path", Size = Vector3.new(20, 0.4, 90), CFrame = CFrame.new(c + Vector3.new(0, 0.2, -half - 40)), Material = Enum.Material.Cobblestone, Color = Color3.fromRGB(200, 190, 170) }).Parent = folder
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Debloquer"
		prompt.ObjectText = nextZone.name
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 16
		prompt.RequiresLineOfSight = false
		prompt.Parent = gate
	end
end

-- Piste de course (boucle dans le village)
local raceWaypoints = {}

local function buildRaceTrack(root)
	local c = Config.Zones[1].center + Vector3.new(60, 0, 40)
	local rx, rz = 38, 24
	local n = 24
	for i = 0, n - 1 do
		local a = (i / n) * math.pi * 2
		table.insert(raceWaypoints, c + Vector3.new(math.cos(a) * rx, 1.2, math.sin(a) * rz))
	end
	for i = 1, n do
		local p1 = raceWaypoints[i]
		local p2 = raceWaypoints[(i % n) + 1]
		local seg = makePart({ Name = "Track", Size = Vector3.new(8, 0.4, (p2 - p1).Magnitude + 1), CFrame = CFrame.lookAt((p1 + p2) / 2 - Vector3.new(0, 1, 0), p2 - Vector3.new(0, 1, 0)), Material = Enum.Material.Asphalt, Color = Color3.fromRGB(60, 60, 70), CanCollide = false })
		seg.Parent = root
		local line = makePart({ Name = "TrackLine", Size = Vector3.new(0.4, 0.45, (p2 - p1).Magnitude + 1), CFrame = seg.CFrame, Material = Enum.Material.Neon, Color = Config.Colors.Accent, CanCollide = false })
		line.Parent = root
	end
	local start = raceWaypoints[1]
	local finish = makePart({ Name = "FinishLine", Size = Vector3.new(10, 0.5, 2), CFrame = CFrame.new(start + Vector3.new(0, 0.1, 0)), Material = Enum.Material.Neon, Color = Color3.new(1, 1, 1), CanCollide = false })
	finish.Parent = root
	local arch = makePart({ Name = "FinishArch", Size = Vector3.new(12, 1.5, 1.5), CFrame = CFrame.new(start + Vector3.new(0, 8, 0)), Material = Enum.Material.Neon, Color = Config.Colors.Accent2 })
	arch.Parent = root
	addLabel(arch, "🏁 ARRIVEE", Enum.NormalId.Front, Color3.new(1, 1, 1))
	for _, z in ipairs({ -5.5, 5.5 }) do
		makePart({ Name = "ArchPole", Size = Vector3.new(1, 8, 1), CFrame = CFrame.new(start + Vector3.new(0, 4, z)), Material = Enum.Material.Marble, Color = Color3.new(1, 1, 1) }).Parent = root
	end
	-- Stand d'inscription
	stand(root, c + Vector3.new(0, 0, 0), c + Vector3.new(0, 0, -10), "COURSES DE PETS", "🏁", Config.Colors.Accent2, "RaceStand", {})
	-- Tribunes
	for i = 1, 3 do
		makePart({ Name = "Stand", Size = Vector3.new(30, 1.5 * i, 3), CFrame = CFrame.new(c + Vector3.new(0, 0.75 * i, rz + 12 + i * 3)), Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(230, 230, 240) }).Parent = root
	end
end

local function buildHub(root)
	local pos = Config.Map.SpawnPosition
	local existingSpawn = workspace:FindFirstChildOfClass("SpawnLocation")
	if existingSpawn then
		existingSpawn:Destroy()
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "MainSpawn"
	spawn.Size = Vector3.new(12, 0.5, 12)
	spawn.CFrame = CFrame.new(pos.X, 0.25, pos.Z)
	spawn.Anchored = true
	spawn.Material = Enum.Material.Neon
	spawn.Color = Config.Colors.Accent
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = root

	local sign = makePart({ Name = "WelcomeSign", Size = Vector3.new(36, 8, 1), CFrame = CFrame.new(pos.X, 8, pos.Z + 22), Material = Enum.Material.SmoothPlastic, Color = Config.Colors.Panel })
	sign.Parent = root
	addLabel(sign, "🐾 " .. Config.GameName .. " 🐾", Enum.NormalId.Back, Config.Colors.Accent2)
	local hint = makePart({ Name = "HintSign", Size = Vector3.new(36, 3, 1), CFrame = CFrame.new(pos.X, 3, pos.Z + 22), Material = Enum.Material.SmoothPlastic, Color = Config.Colors.Panel })
	hint.Parent = root
	addLabel(hint, "Ramasse les 🪙 avec tes pets  •  Ouvre des 🥚  •  Fais evoluer 🧬  •  Gagne des courses 🏁", Enum.NormalId.Back, Color3.new(1, 1, 1))

	-- Fontaine
	makePart({ Name = "Fountain", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 14, 14), CFrame = CFrame.new(pos.X - 40, 1, pos.Z - 10) * CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.Marble, Color = Color3.fromRGB(235, 235, 240) }).Parent = root
	local water = makePart({ Name = "Water", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 12, 12), CFrame = CFrame.new(pos.X - 40, 2, pos.Z - 10) * CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.Glass, Color = Color3.fromRGB(80, 170, 255), Transparency = 0.3, CanCollide = false })
	water.Parent = root
	local jet = makePart({ Name = "Jet", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(pos.X - 40, 3, pos.Z - 10), Transparency = 1, CanCollide = false })
	jet.Parent = root
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 40
	emitter.Lifetime = NumberRange.new(1, 1.4)
	emitter.Speed = NumberRange.new(16, 22)
	emitter.SpreadAngle = Vector2.new(8, 8)
	emitter.Acceleration = Vector3.new(0, -40, 0)
	emitter.Size = NumberSequence.new(0.6)
	emitter.Transparency = NumberSequence.new(0.3, 1)
	emitter.Color = ColorSequence.new(Color3.fromRGB(170, 220, 255))
	emitter.Parent = jet

	-- Classement
	local board = makePart({ Name = "Leaderboard", Size = Vector3.new(22, 16, 1), CFrame = CFrame.new(pos.X + 45, 9, pos.Z), Material = Enum.Material.SmoothPlastic, Color = Config.Colors.Panel })
	board.Parent = root
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Left
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.14, 0)
	title.BackgroundTransparency = 1
	title.Text = "📈 TOP COINS"
	title.TextColor3 = Config.Colors.Gold
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Parent = gui
	local list = Instance.new("TextLabel")
	list.Size = UDim2.new(1, -20, 0.84, 0)
	list.Position = UDim2.new(0, 10, 0.15, 0)
	list.BackgroundTransparency = 1
	list.Text = "Chargement..."
	list.TextColor3 = Color3.new(1, 1, 1)
	list.Font = Enum.Font.GothamBold
	list.TextScaled = true
	list.TextXAlignment = Enum.TextXAlignment.Left
	list.TextYAlignment = Enum.TextYAlignment.Top
	list.Parent = gui
	gui.Parent = board
	makePart({ Name = "BoardFrame", Size = Vector3.new(23, 17, 0.6), CFrame = board.CFrame * CFrame.new(0, 0, 0.1), Material = Enum.Material.Neon, Color = Config.Colors.Gold }).Parent = root
	MapBuilder.LeaderboardLabel = list

	-- Stand recompense quotidienne
	stand(root, Vector3.new(pos.X + 40, 0, pos.Z + 30), Vector3.new(pos.X, 0, pos.Z), "CADEAU DU JOUR", "🎁", Config.Colors.Gold, "DailyStand", {})
end

-- Ambiance : nuages, particules
local function buildLife(root)
	for i = 1, 14 do
		local cloud = makePart({ Name = "Cloud", Size = Vector3.new(30 + (i % 3) * 12, 7, 18 + (i % 2) * 8), CFrame = CFrame.new(-250 + i * 40, 120 + (i % 4) * 12, -700 + (i * 97) % 900), Material = Enum.Material.SmoothPlastic, Color = Color3.new(1, 1, 1), Transparency = 0.3, CanCollide = false, CanQuery = false })
		cloud.Parent = root
		TweenService:Create(cloud, TweenInfo.new(40 + i * 4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true), { CFrame = cloud.CFrame * CFrame.new(100, 0, 0) }):Play()
	end
	for _, zone in ipairs(Config.Zones) do
		local z = makePart({ Name = "Ambient", Size = Vector3.new(zone.size, 20, zone.size), CFrame = CFrame.new(zone.center + Vector3.new(0, 10, 0)), Transparency = 1, CanCollide = false, CanQuery = false })
		z.Parent = root
		local e = Instance.new("ParticleEmitter")
		e.Rate = 30
		e.Lifetime = NumberRange.new(4, 7)
		e.Speed = NumberRange.new(0.5, 1.5)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new(0.3)
		e.LightEmission = 1
		e.Color = ColorSequence.new(zone.id == "Desert" and Color3.fromRGB(255, 220, 150) or (zone.id == "Foret" and Color3.fromRGB(170, 255, 140) or Color3.fromRGB(255, 240, 200)))
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.Parent = z
	end
end

function MapBuilder.Build()
	local old = workspace:FindFirstChild("PetRush")
	if old then
		old:Destroy()
	end
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "PetRush"
	root.Parent = workspace
	buildLighting()
	for i, zone in ipairs(Config.Zones) do
		buildZone(root, zone, i)
	end
	buildHub(root)
	buildRaceTrack(root)
	buildLife(root)
	local coins = Instance.new("Folder")
	coins.Name = "Coins"
	coins.Parent = workspace
	local runners = Instance.new("Folder")
	runners.Name = "Racers"
	runners.Parent = workspace
	Players.RespawnTime = 2
	return root
end

function MapBuilder.GetCoinSpots(zoneId)
	return coinSpots[zoneId] or {}
end

function MapBuilder.GetRaceWaypoints()
	return raceWaypoints
end

function MapBuilder.ZoneAt(position)
	for _, zone in ipairs(Config.Zones) do
		local half = zone.size / 2 + 50
		if math.abs(position.X - zone.center.X) <= half and math.abs(position.Z - zone.center.Z) <= half then
			return zone
		end
	end
	return nil
end

return MapBuilder
