-- Construit la map : spawn (zone sure), arene centrale, centre-ville, zone calme, classement.
-- Aucun asset externe.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
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

local function addLabel(parent, text, face, color, scale)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, scale or 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextStrokeTransparency = 0.5
	label.Parent = gui
	gui.Parent = parent
	return gui
end

local function buildLighting()
	Lighting.ClockTime = 17.5
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(70, 70, 90)
	Lighting.OutdoorAmbient = Color3.fromRGB(110, 110, 140)
	Lighting.FogColor = Color3.fromRGB(150, 140, 180)
	Lighting.FogStart = 250
	Lighting.FogEnd = 1100
	Lighting.GlobalShadows = true
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Size = 28
	bloom.Threshold = 1.3
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "BGColor"
	cc.Contrast = 0.15
	cc.Saturation = 0.1
	cc.Parent = Lighting
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.3
	atmosphere.Color = Color3.fromRGB(220, 170, 200)
	atmosphere.Decay = Color3.fromRGB(120, 80, 160)
	atmosphere.Glare = 0.5
	atmosphere.Haze = 2
	atmosphere.Parent = Lighting
	local sky = Instance.new("Sky")
	sky.SunAngularSize = 18
	sky.Parent = Lighting
end

local function buildGround(root)
	makePart({
		Name = "Ground",
		Size = Vector3.new(700, 6, 700),
		CFrame = CFrame.new(0, -3, 0),
		Material = Enum.Material.Concrete,
		Color = Color3.fromRGB(70, 72, 80),
	}).Parent = root
	-- Routes
	for _, def in ipairs({
		{ Vector3.new(24, 0.3, 700), CFrame.new(0, 0.15, 0) },
		{ Vector3.new(700, 0.3, 24), CFrame.new(0, 0.15, 0) },
		{ Vector3.new(24, 0.3, 500), CFrame.new(-120, 0.15, -40) },
		{ Vector3.new(24, 0.3, 500), CFrame.new(120, 0.15, -40) },
	}) do
		makePart({ Name = "Road", Size = def[1], CFrame = def[2], Material = Enum.Material.Asphalt, Color = Color3.fromRGB(40, 40, 46) }).Parent = root
	end
	-- Murs d'enceinte
	for _, def in ipairs({
		{ Vector3.new(700, 60, 4), CFrame.new(0, 30, 350) },
		{ Vector3.new(700, 60, 4), CFrame.new(0, 30, -350) },
		{ Vector3.new(4, 60, 700), CFrame.new(350, 30, 0) },
		{ Vector3.new(4, 60, 700), CFrame.new(-350, 30, 0) },
	}) do
		makePart({ Name = "Border", Size = def[1], CFrame = def[2], Transparency = 0.9, Material = Enum.Material.ForceField, Color = Config.Colors.Accent }).Parent = root
	end
end

local function buildSpawn(root)
	local pos = Config.Map.SpawnPosition
	local plate = makePart({
		Name = "SafeZone",
		Size = Vector3.new(70, 1, 50),
		CFrame = CFrame.new(pos.X, 0.5, pos.Z),
		Material = Enum.Material.Marble,
		Color = Color3.fromRGB(220, 225, 235),
	})
	plate:SetAttribute("SafeRadius", 45)
	CollectionService:AddTag(plate, "SafeZone")
	plate.Parent = root
	local ring = makePart({
		Name = "SafeRing",
		Size = Vector3.new(72, 0.4, 52),
		CFrame = CFrame.new(pos.X, 0.2, pos.Z),
		Material = Enum.Material.Neon,
		Color = Config.Colors.Accent,
	})
	ring.Parent = root

	local existingSpawn = workspace:FindFirstChildOfClass("SpawnLocation")
	if existingSpawn then
		existingSpawn:Destroy()
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "MainSpawn"
	spawn.Size = Vector3.new(12, 0.5, 12)
	spawn.CFrame = CFrame.new(pos.X, 1.25, pos.Z)
	spawn.Anchored = true
	spawn.Material = Enum.Material.Neon
	spawn.Color = Config.Colors.Accent
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = root

	-- Panneau de bienvenue
	local sign = makePart({ Name = "WelcomeSign", Size = Vector3.new(40, 8, 1), CFrame = CFrame.new(pos.X, 8, pos.Z + 24), Material = Enum.Material.SmoothPlastic, Color = Config.Colors.Dark })
	sign.Parent = root
	addLabel(sign, Config.GameName, Enum.NormalId.Back, Config.Colors.Accent)
	local hint = makePart({ Name = "HintSign", Size = Vector3.new(40, 3, 1), CFrame = CFrame.new(pos.X, 3, pos.Z + 24), Material = Enum.Material.SmoothPlastic, Color = Config.Colors.Dark })
	hint.Parent = root
	addLabel(hint, "Clic : M1  |  F : Bloquer  |  Q : Dash  |  1-4 : Competences  |  G : Ultimate  |  C : Personnage", Enum.NormalId.Back, Color3.new(1, 1, 1))

	-- Tableau de classement
	local board = makePart({ Name = "Leaderboard", Size = Vector3.new(22, 16, 1), CFrame = CFrame.new(pos.X - 40, 9, pos.Z), Material = Enum.Material.SmoothPlastic, Color = Config.Colors.Dark })
	board.Parent = root
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BoardGui"
	gui.Face = Enum.NormalId.Right
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0.14, 0)
	title.BackgroundTransparency = 1
	title.Text = "TOP JOUEURS"
	title.TextColor3 = Config.Colors.Gold
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.Parent = gui
	local list = Instance.new("TextLabel")
	list.Name = "List"
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
	local frame = makePart({ Name = "BoardFrame", Size = Vector3.new(23, 17, 0.6), CFrame = board.CFrame * CFrame.new(0, 0, 0.1), Material = Enum.Material.Neon, Color = Config.Colors.Gold })
	frame.Parent = root
	MapBuilder.LeaderboardLabel = list
end

local function buildArena(root)
	local center = Config.Map.ArenaCenter
	local R = Config.Map.ArenaRadius
	local floor = makePart({
		Name = "ArenaFloor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, R * 2, R * 2),
		CFrame = CFrame.new(center + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(45, 45, 60),
	})
	floor.Parent = root
	local ring = makePart({
		Name = "ArenaRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, R * 2 + 4, R * 2 + 4),
		CFrame = CFrame.new(center + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Neon,
		Color = Config.Colors.Accent2,
	})
	ring.Parent = root
	-- Piliers lumineux autour de l'arene
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2
		local pillar = makePart({
			Name = "ArenaPillar",
			Size = Vector3.new(3, 18, 3),
			CFrame = CFrame.new(center + Vector3.new(math.cos(a) * (R + 6), 9, math.sin(a) * (R + 6))),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(60, 60, 75),
		})
		pillar.Parent = root
		local top = makePart({
			Name = "PillarLight",
			Size = Vector3.new(3.4, 1, 3.4),
			CFrame = pillar.CFrame * CFrame.new(0, 9.5, 0),
			Material = Enum.Material.Neon,
			Color = Config.Colors.Accent2,
		})
		top.Parent = root
	end
end

local function buildCity(root)
	local origin = Config.Map.CityOrigin
	local palette = {
		Color3.fromRGB(60, 65, 85),
		Color3.fromRGB(85, 70, 80),
		Color3.fromRGB(50, 75, 90),
		Color3.fromRGB(95, 90, 85),
	}
	local i = 0
	for gx = -3, 3 do
		for gz = -3, 0 do
			i += 1
			-- laisse les routes libres
			if gx ~= 0 and math.abs(gx) ~= 2 then
				local w = 22 + (i % 3) * 6
				local d = 22 + ((i * 7) % 3) * 6
				local h = 18 + ((i * 13) % 5) * 12
				local x = origin.X + gx * 60
				local z = origin.Z + gz * 60 - 30
				local building = makePart({
					Name = "Building",
					Size = Vector3.new(w, h, d),
					CFrame = CFrame.new(x, h / 2, z),
					Material = Enum.Material.Concrete,
					Color = palette[(i % #palette) + 1],
				})
				building.Parent = root
				-- Fenetres
				local windows = makePart({
					Name = "Windows",
					Size = Vector3.new(w + 0.2, h - 4, d + 0.2),
					CFrame = CFrame.new(x, h / 2, z),
					Material = Enum.Material.Glass,
					Color = Config.Colors.Accent,
					Transparency = 0.65,
					CanCollide = false,
				})
				windows.Parent = root
				-- Toit accessible avec rebord neon
				local roof = makePart({
					Name = "RoofEdge",
					Size = Vector3.new(w + 1, 0.6, d + 1),
					CFrame = CFrame.new(x, h + 0.3, z),
					Material = Enum.Material.Neon,
					Color = (i % 2 == 0) and Config.Colors.Accent or Config.Colors.Accent2,
				})
				roof.Parent = root
				-- Escalier de caisses pour monter sur le toit
				local steps = math.floor(h / 4)
				for s = 1, steps do
					local box = makePart({
						Name = "Step",
						Size = Vector3.new(5, 4, 5),
						CFrame = CFrame.new(x + w / 2 + 3 + (s % 2) * 5, s * 4 - 2, z + d / 2 - 3 - s * 3.5),
						Material = Enum.Material.Metal,
						Color = Color3.fromRGB(90, 90, 100),
					})
					box.Parent = root
				end
			end
		end
	end
	-- Lampadaires
	for k = 1, 10 do
		local x = -150 + k * 30
		for _, z in ipairs({ -60, -180 }) do
			local pole = makePart({ Name = "Lamp", Size = Vector3.new(0.6, 12, 0.6), CFrame = CFrame.new(x + 13, 6, z + 13), Material = Enum.Material.Metal, Color = Color3.fromRGB(50, 50, 55) })
			pole.Parent = root
			local lamp = makePart({ Name = "LampLight", Size = Vector3.new(1.5, 1, 1.5), CFrame = pole.CFrame * CFrame.new(0, 6.3, 0), Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 230, 180) })
			local light = Instance.new("PointLight")
			light.Range = 30
			light.Brightness = 1.5
			light.Color = Color3.fromRGB(255, 230, 180)
			light.Parent = lamp
			lamp.Parent = root
		end
	end
end

local function buildTree(root, position, scale)
	local trunk = makePart({ Name = "Tree", Size = Vector3.new(1.6 * scale, 7 * scale, 1.6 * scale), CFrame = CFrame.new(position + Vector3.new(0, 3.5 * scale, 0)), Material = Enum.Material.Wood, Color = Color3.fromRGB(110, 75, 45) })
	trunk.Parent = root
	for i = 1, 3 do
		local r = (5 - i * 0.8) * scale
		makePart({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(r * 2, r * 2, r * 2), CFrame = CFrame.new(position + Vector3.new(0, (6 + i * 2) * scale, 0)), Material = Enum.Material.Grass, Color = Color3.fromRGB(50 + i * 15, 140 + i * 15, 70), CanCollide = false }).Parent = root
	end
end

local function buildCalmZone(root)
	local pos = Config.Map.CalmZone
	local grass = makePart({ Name = "Park", Size = Vector3.new(130, 0.6, 110), CFrame = CFrame.new(pos.X, 0.3, pos.Z), Material = Enum.Material.Grass, Color = Color3.fromRGB(90, 160, 70) })
	grass.Parent = root
	for i = 1, 10 do
		local a = (i / 10) * math.pi * 2
		buildTree(root, pos + Vector3.new(math.cos(a) * 52, 0.6, math.sin(a) * 45), 0.9 + (i % 3) * 0.3)
	end
	local sign = makePart({ Name = "TrainingSign", Size = Vector3.new(26, 5, 1), CFrame = CFrame.new(pos.X, 7, pos.Z - 50), Material = Enum.Material.SmoothPlastic, Color = Config.Colors.Dark })
	sign.Parent = root
	addLabel(sign, "ZONE D'ENTRAINEMENT", Enum.NormalId.Front, Config.Colors.Accent)
	addLabel(sign, "ZONE D'ENTRAINEMENT", Enum.NormalId.Back, Config.Colors.Accent)
end

-- Mannequins d'entrainement ---------------------------------------------------------

local function buildDummy(root, position, index)
	local model = Instance.new("Model")
	model.Name = "Mannequin " .. index
	local color = Color3.fromRGB(200, 200, 210)

	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.Transparency = 1
	hrp.CanCollide = false
	hrp.Anchored = true
	hrp.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
	hrp.Parent = model

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.Color = color
	torso.Material = Enum.Material.SmoothPlastic
	torso.CFrame = hrp.CFrame
	torso.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.4, 1.4, 1.4)
	head.Color = Color3.fromRGB(255, 200, 60)
	head.Material = Enum.Material.SmoothPlastic
	head.CFrame = hrp.CFrame * CFrame.new(0, 1.7, 0)
	head.Parent = model

	local limbs = {
		{ "Left Arm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 0, 0) },
		{ "Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.5, 0, 0) },
		{ "Left Leg", Vector3.new(1, 2, 1), Vector3.new(-0.5, -2, 0) },
		{ "Right Leg", Vector3.new(1, 2, 1), Vector3.new(0.5, -2, 0) },
	}
	for _, def in ipairs(limbs) do
		local limb = Instance.new("Part")
		limb.Name = def[1]
		limb.Size = def[2]
		limb.Color = color
		limb.Material = Enum.Material.SmoothPlastic
		limb.CFrame = hrp.CFrame * CFrame.new(def[3])
		limb.Parent = model
	end
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") and part ~= hrp then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = hrp
			weld.Part1 = part
			weld.Parent = part
			part.Anchored = false
		end
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = Config.Map.DummyHealth
	humanoid.Health = Config.Map.DummyHealth
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model
	model.PrimaryPart = hrp
	model:SetAttribute("Dummy", true)
	CollectionService:AddTag(model, "Dummy")
	model.Parent = root

	humanoid.Died:Connect(function()
		task.delay(3, function()
			model:Destroy()
			buildDummy(root, position, index)
		end)
	end)
	-- Regeneration
	task.spawn(function()
		while model.Parent and humanoid.Health > 0 do
			task.wait(2)
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + 15)
		end
	end)
end

function MapBuilder.Build()
	local old = workspace:FindFirstChild("OnyxBattlegrounds")
	if old then
		old:Destroy()
	end
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "OnyxBattlegrounds"
	root.Parent = workspace

	buildLighting()
	buildGround(root)
	buildSpawn(root)
	buildArena(root)
	buildCity(root)
	buildCalmZone(root)

	local dummies = Instance.new("Folder")
	dummies.Name = "Dummies"
	dummies.Parent = workspace
	local pos = Config.Map.CalmZone
	for i = 1, Config.Map.DummyCount do
		buildDummy(dummies, pos + Vector3.new(-30 + i * 15, 0.6, 0), i)
	end

	Players.RespawnTime = Config.Combat.RespawnTime
	return root
end

-- Un point est-il dans une zone sure ?
function MapBuilder.IsSafe(position)
	for _, zone in ipairs(CollectionService:GetTagged("SafeZone")) do
		local radius = zone:GetAttribute("SafeRadius") or 40
		local flat = (Vector3.new(position.X, 0, position.Z) - Vector3.new(zone.Position.X, 0, zone.Position.Z)).Magnitude
		if flat <= radius then
			return true
		end
	end
	return false
end

return MapBuilder
