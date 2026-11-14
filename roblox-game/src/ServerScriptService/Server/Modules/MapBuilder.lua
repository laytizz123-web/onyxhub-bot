-- Construit l'arene, le lobby et l'eclairage entierement par script.
-- Aucun asset externe : tout est fait avec des Parts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
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

local function flatCylinder(name, radius, thickness, position, color, material, transparency)
	return makePart({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, radius * 2, radius * 2),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Transparency = transparency or 0,
	})
end

local function addLabel(parent, text, face, size)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Config.Colors.Accent
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextStrokeTransparency = 0.5
	label.TextStrokeColor3 = Config.Colors.Accent2
	label.Parent = gui
	gui.Parent = parent
	return gui
end

local function buildLighting()
	Lighting.ClockTime = 0
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(45, 45, 70)
	Lighting.OutdoorAmbient = Color3.fromRGB(60, 60, 95)
	Lighting.FogColor = Color3.fromRGB(10, 10, 20)
	Lighting.FogStart = 200
	Lighting.FogEnd = 900
	Lighting.GlobalShadows = true

	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.8
	bloom.Size = 32
	bloom.Threshold = 1.1
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "ArenaColor"
	cc.Contrast = 0.12
	cc.Saturation = 0.15
	cc.TintColor = Color3.fromRGB(255, 255, 255)
	cc.Parent = Lighting

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(120, 90, 200)
	atmosphere.Decay = Color3.fromRGB(40, 20, 80)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 2
	atmosphere.Parent = Lighting

	local sky = Instance.new("Sky")
	sky.StarCount = 4000
	sky.CelestialBodiesShown = false
	sky.Parent = Lighting
end

local function buildArena(root)
	local arena = Config.Arena
	local center = arena.Center
	local R = arena.Radius

	-- Sol principal
	local floor = flatCylinder("ArenaFloor", R, 4, center - Vector3.new(0, 2, 0), Config.Colors.Floor, Enum.Material.Slate)
	floor.Parent = root

	-- Anneau neon sous le sol
	local ring = flatCylinder("ArenaRing", R + 2.5, 2.5, center - Vector3.new(0, 4.5, 0), Config.Colors.Accent, Enum.Material.Neon)
	ring.Parent = root

	-- Cercles decoratifs au sol (neon + disque sombre par dessus = anneau)
	for _, radius in ipairs({ 44, 22 }) do
		local glow = flatCylinder("FloorGlow", radius, 0.2, center + Vector3.new(0, 0.05, 0), Config.Colors.Accent2, Enum.Material.Neon, 0.2)
		glow.CanCollide = false
		glow.Parent = root
		local cover = flatCylinder("FloorCover", radius - 1.2, 0.2, center + Vector3.new(0, 0.12, 0), Config.Colors.Floor, Enum.Material.Slate)
		cover.CanCollide = false
		cover.Parent = root
	end
	local core = flatCylinder("ArenaCore", 6, 0.3, center + Vector3.new(0, 0.2, 0), Config.Colors.Accent, Enum.Material.Neon)
	core.CanCollide = false
	core.Parent = root

	-- Murs en verre tout autour
	local segments = arena.WallSegments
	local wallRadius = R + 1
	local segWidth = (2 * math.pi * wallRadius) / segments + 0.8
	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local wall = makePart({
			Name = "ArenaWall",
			Size = Vector3.new(segWidth, arena.WallHeight, 1.5),
			CFrame = CFrame.new(center) * CFrame.Angles(0, angle, 0) * CFrame.new(0, arena.WallHeight / 2, -wallRadius),
			Material = Enum.Material.Glass,
			Color = Config.Colors.Accent,
			Transparency = 0.75,
		})
		wall.Parent = root
		if i % 3 == 0 then
			local bar = makePart({
				Name = "WallBar",
				Size = Vector3.new(0.6, arena.WallHeight, 0.6),
				CFrame = wall.CFrame * CFrame.new(segWidth / 2, 0, 0),
				Material = Enum.Material.Neon,
				Color = Config.Colors.Accent2,
				CanCollide = false,
			})
			bar.Parent = root
		end
	end
	-- Anneau superieur
	local topRing = flatCylinder("ArenaTopRing", R + 3, 1, center + Vector3.new(0, arena.WallHeight + 0.5, 0), Config.Colors.Accent2, Enum.Material.Neon, 0.3)
	topRing.CanCollide = false
	topRing.Parent = root
	local topCover = flatCylinder("ArenaTopCover", R - 1, 1.2, center + Vector3.new(0, arena.WallHeight + 0.5, 0), Config.Colors.Dark, Enum.Material.SmoothPlastic, 1)
	topCover.CanCollide = false
	topCover.Parent = root

	-- Piliers mobiles (montent et descendent en continu)
	for i = 1, arena.PillarCount do
		local angle = (i / arena.PillarCount) * math.pi * 2
		local x = math.cos(angle) * arena.PillarRadius
		local z = math.sin(angle) * arena.PillarRadius
		local h = 16
		local downCF = CFrame.new(center + Vector3.new(x, -h / 2 + 0.8, z))
		local upCF = CFrame.new(center + Vector3.new(x, h / 2, z))
		local pillar = makePart({
			Name = "Pillar",
			Size = Vector3.new(7, h, 7),
			CFrame = downCF,
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(50, 50, 70),
		})
		pillar.Parent = root
		local cap = makePart({
			Name = "PillarCap",
			Size = Vector3.new(7.4, 0.5, 7.4),
			CFrame = downCF * CFrame.new(0, h / 2 + 0.25, 0),
			Material = Enum.Material.Neon,
			Color = Config.Colors.Accent,
		})
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = pillar
		weld.Part1 = cap
		weld.Parent = cap
		cap.Anchored = false
		cap.Parent = root

		local duration = 3 + (i % 4) * 0.9
		local info = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, (i % 3) * 1.1)
		TweenService:Create(pillar, info, { CFrame = upCF }):Play()
	end

	-- Jump pads (geres cote client via le tag "JumpPad")
	for i = 1, arena.JumpPadCount do
		local angle = (i / arena.JumpPadCount) * math.pi * 2 + math.pi / arena.JumpPadCount
		local x = math.cos(angle) * arena.JumpPadRadius
		local z = math.sin(angle) * arena.JumpPadRadius
		local pad = flatCylinder("JumpPad", 3.5, 0.6, center + Vector3.new(x, 0.3, z), Config.Colors.Gold, Enum.Material.Neon)
		pad:SetAttribute("Power", arena.JumpPadPower)
		CollectionService:AddTag(pad, "JumpPad")
		pad.Parent = root
		local light = Instance.new("PointLight")
		light.Color = Config.Colors.Gold
		light.Range = 12
		light.Brightness = 2
		light.Parent = pad
	end

	-- Cubes flottants decoratifs en rotation
	for i = 1, 14 do
		local angle = (i / 14) * math.pi * 2
		local radius = R - 6
		local y = 10 + (i % 4) * 4
		local cube = makePart({
			Name = "FloatingCube",
			Size = Vector3.new(2, 2, 2),
			CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * radius, y, math.sin(angle) * radius)),
			Material = Enum.Material.Neon,
			Color = (i % 2 == 0) and Config.Colors.Accent or Config.Colors.Accent2,
			CanCollide = false,
		})
		cube.Parent = root
		local info = TweenInfo.new(4 + (i % 3), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		TweenService:Create(cube, info, {
			CFrame = cube.CFrame * CFrame.new(0, 3, 0) * CFrame.Angles(math.rad(90), math.rad(90), 0),
		}):Play()
	end
end

local function buildLobby(root)
	local lobby = Config.Lobby
	local center = lobby.Center
	local size = lobby.Size

	local floor = makePart({
		Name = "LobbyFloor",
		Size = size,
		CFrame = CFrame.new(center),
		Material = Enum.Material.Slate,
		Color = Config.Colors.Floor,
	})
	floor.Parent = root

	local trim = makePart({
		Name = "LobbyTrim",
		Size = Vector3.new(size.X + 2, 1, size.Z + 2),
		CFrame = CFrame.new(center - Vector3.new(0, 1.2, 0)),
		Material = Enum.Material.Neon,
		Color = Config.Colors.Accent,
	})
	trim.Parent = root

	-- Murs invisibles
	local h = 30
	local walls = {
		{ Vector3.new(size.X + 2, h, 1), Vector3.new(0, h / 2, size.Z / 2 + 0.5) },
		{ Vector3.new(size.X + 2, h, 1), Vector3.new(0, h / 2, -size.Z / 2 - 0.5) },
		{ Vector3.new(1, h, size.Z + 2), Vector3.new(size.X / 2 + 0.5, h / 2, 0) },
		{ Vector3.new(1, h, size.Z + 2), Vector3.new(-size.X / 2 - 0.5, h / 2, 0) },
	}
	for _, w in ipairs(walls) do
		local wall = makePart({
			Name = "LobbyWall",
			Size = w[1],
			CFrame = CFrame.new(center + w[2]),
			Transparency = 1,
		})
		wall.Parent = root
	end

	-- Panneau titre
	local sign = makePart({
		Name = "LobbySign",
		Size = Vector3.new(40, 10, 1),
		CFrame = CFrame.new(center + Vector3.new(0, 14, -size.Z / 2 + 2)),
		Material = Enum.Material.SmoothPlastic,
		Color = Config.Colors.Dark,
	})
	sign.Parent = root
	addLabel(sign, Config.GameName, Enum.NormalId.Front)
	addLabel(sign, Config.GameName, Enum.NormalId.Back)

	local hint = makePart({
		Name = "LobbyHint",
		Size = Vector3.new(40, 3, 1),
		CFrame = CFrame.new(center + Vector3.new(0, 7.5, -size.Z / 2 + 2)),
		Material = Enum.Material.SmoothPlastic,
		Color = Config.Colors.Dark,
	})
	hint.Parent = root
	local hintGui = addLabel(hint, "F / Clic : RENVOYER   |   Q : DASH   |   E : PULSE   |   Double saut", Enum.NormalId.Front)
	hintGui.TextLabel.TextColor3 = Color3.new(1, 1, 1)
	hintGui.TextLabel.Font = Enum.Font.GothamBold

	-- Spawn
	local existingSpawn = workspace:FindFirstChildOfClass("SpawnLocation")
	if existingSpawn then
		existingSpawn:Destroy()
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.new(center + Vector3.new(0, 1.5, 0))
	spawn.Anchored = true
	spawn.Material = Enum.Material.Neon
	spawn.Color = Config.Colors.Accent2
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = root
end

function MapBuilder.Build()
	local old = workspace:FindFirstChild("OnyxArena")
	if old then
		old:Destroy()
	end
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = "OnyxArena"
	root.Parent = workspace

	buildLighting()
	buildArena(root)
	buildLobby(root)

	Players.RespawnTime = 3
	return root
end

-- Positions de depart reparties en cercle autour de l'arene.
function MapBuilder.GetSpawnPoints(count)
	local points = {}
	local offset = math.random() * math.pi * 2
	for i = 1, count do
		local angle = offset + (i / count) * math.pi * 2
		local pos = Config.Arena.Center + Vector3.new(
			math.cos(angle) * Config.Arena.SpawnRadius,
			4,
			math.sin(angle) * Config.Arena.SpawnRadius
		)
		table.insert(points, pos)
	end
	return points
end

function MapBuilder.GetLobbySpawn()
	return Config.Lobby.Center + Vector3.new(0, 5, 0)
end

return MapBuilder
