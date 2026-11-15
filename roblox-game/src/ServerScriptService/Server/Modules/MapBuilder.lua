-- Map de PET RUSH : Terrain Roblox (herbe, collines, eau, sable) + props cartoon.
-- 3 zones (Village, Foret, Desert), arches de passage, stands, piste de course, classement.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)

local MapBuilder = {}

local Terrain = workspace.Terrain
local rng = Random.new(42) -- decor identique a chaque lancement

local function R(a, b)
	return rng:NextNumber(a, b)
end

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

local function wedge(props, parent)
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	w.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		w[k] = v
	end
	w.Parent = parent
	return w
end

local function ballPart(cf, size, color, parent, material)
	return part({ Shape = Enum.PartType.Ball, Size = Vector3.new(size, size, size), CFrame = cf, Color = color, Material = material or Enum.Material.SmoothPlastic, CanCollide = false }, parent)
end

local function cylinder(cf, height, radius, color, parent, material)
	-- cylindre vertical
	return part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, radius * 2, radius * 2), CFrame = cf * CFrame.Angles(0, 0, math.rad(90)), Color = color, Material = material or Enum.Material.SmoothPlastic }, parent)
end

local function sign(parent, cf, size, text, textColor, bg)
	local board = part({ Name = "Sign", Size = size, CFrame = cf, Color = bg or Color3.fromRGB(150, 100, 60), Material = Enum.Material.WoodPlanks }, parent)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		local l = Instance.new("TextLabel")
		l.Size = UDim2.fromScale(0.94, 0.86)
		l.Position = UDim2.fromScale(0.03, 0.07)
		l.BackgroundTransparency = 1
		l.Text = text
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextColor3 = textColor or Color3.new(1, 1, 1)
		l.Parent = gui
		local st = Instance.new("UIStroke")
		st.Color = Color3.fromRGB(22, 24, 52)
		st.Thickness = 4
		st.Parent = l
		gui.Parent = board
	end
	return board
end

-- Eclairage ------------------------------------------------------------------------------

local function buildLighting()
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 3
	Lighting.Ambient = Color3.fromRGB(110, 115, 135)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 155, 170)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.ShadowSoftness = 0.3
	Lighting.GlobalShadows = true
	Lighting.FogEnd = 100000
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(200, 225, 255)
	atmosphere.Decay = Color3.fromRGB(110, 160, 230)
	atmosphere.Glare = 0.5
	atmosphere.Haze = 1.4
	atmosphere.Parent = Lighting
	local sky = Instance.new("Sky")
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 8
	sky.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.35
	bloom.Size = 20
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
	local sunRays = Instance.new("SunRaysEffect")
	sunRays.Intensity = 0.06
	sunRays.Spread = 0.6
	sunRays.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "PetColor"
	cc.Saturation = 0.18
	cc.Contrast = 0.06
	cc.Brightness = 0.02
	cc.Parent = Lighting

	local clouds = Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.6
	clouds.Color = Color3.new(1, 1, 1)
	clouds.Parent = Terrain

	Terrain.WaterColor = Color3.fromRGB(50, 170, 255)
	Terrain.WaterTransparency = 0.55
	Terrain.WaterReflectance = 0.5
	Terrain.WaterWaveSize = 0.12
	Terrain.WaterWaveSpeed = 8
	Terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(105, 195, 75))
	Terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(70, 150, 65))
	Terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(240, 210, 140))
	Terrain:SetMaterialColor(Enum.Material.Sandstone, Color3.fromRGB(215, 160, 100))
	Terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(130, 130, 145))
	Terrain:SetMaterialColor(Enum.Material.Cobblestone, Color3.fromRGB(190, 180, 165))
	Terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(140, 100, 70))
end

-- Terrain -------------------------------------------------------------------------------

local ZONE_MATERIAL = { Village = Enum.Material.Grass, Foret = Enum.Material.LeafyGrass, Desert = Enum.Material.Sand }
local avoid = {} -- zones ou les coins ne doivent pas apparaitre { pos, radius }

local function avoidCircle(pos, radius)
	table.insert(avoid, { pos = pos, radius = radius })
end

local function pond(center, radius, rimMaterial)
	Terrain:FillCylinder(CFrame.new(center + Vector3.new(0, -1, 0)), 2, radius + 4, rimMaterial or Enum.Material.Sand)
	Terrain:FillCylinder(CFrame.new(center + Vector3.new(0, -4, 0)), 8, radius, Enum.Material.Air)
	Terrain:FillCylinder(CFrame.new(center + Vector3.new(0, -4.5, 0)), 7, radius, Enum.Material.Water)
	avoidCircle(center, radius + 6)
end

local function hill(center, radius, material)
	Terrain:FillBall(center, radius, material)
end

local function buildTerrain()
	Terrain:Clear()
	local first = Config.Zones[1]
	local last = Config.Zones[#Config.Zones]
	local zMax = first.center.Z + first.size / 2 + 60
	local zMin = last.center.Z - last.size / 2 - 60
	local length = zMax - zMin
	-- Sous-sol
	Terrain:FillBlock(CFrame.new(0, -14, (zMax + zMin) / 2), Vector3.new(420, 20, length + 80), Enum.Material.Ground)
	-- Sol de chaque zone + couloirs
	for i, zone in ipairs(Config.Zones) do
		local half = zone.size / 2
		Terrain:FillBlock(CFrame.new(zone.center + Vector3.new(0, -3, 0)), Vector3.new(zone.size + 120, 6, zone.size + (i == #Config.Zones and 120 or 80)), ZONE_MATERIAL[zone.id])
		local nextZone = Config.Zones[i + 1]
		if nextZone then
			local z0 = zone.center.Z - half
			local z1 = nextZone.center.Z + nextZone.size / 2
			Terrain:FillBlock(CFrame.new(0, -3, (z0 + z1) / 2), Vector3.new(160, 6, math.abs(z0 - z1) + 2), ZONE_MATERIAL[zone.id])
			-- chemin pave
			Terrain:FillBlock(CFrame.new(0, -1, (z0 + z1) / 2), Vector3.new(16, 2, math.abs(z0 - z1) + 24), Enum.Material.Cobblestone)
			-- collines qui bordent le couloir
			for z = z1 + 6, z0 - 6, 14 do
				hill(Vector3.new(-38 - R(0, 8), -6, z), R(16, 22), Enum.Material.Rock)
				hill(Vector3.new(38 + R(0, 8), -6, z), R(16, 22), Enum.Material.Rock)
			end
		end
		-- Collines / montagnes autour de la zone
		local mat = zone.id == "Desert" and Enum.Material.Sandstone or (zone.id == "Foret" and Enum.Material.Rock or Enum.Material.Grass)
		local edge = half + 16
		for t = -half, half, 22 do
			for _, side in ipairs({ -1, 1 }) do
				hill(zone.center + Vector3.new(side * (edge + R(-4, 8)), -10 + R(0, 8), t), R(22, 34), mat)
			end
			if math.abs(t) > 24 then
				if i == 1 then
					hill(zone.center + Vector3.new(t, -10 + R(0, 8), edge + R(-4, 8)), R(22, 34), mat)
				end
				hill(zone.center + Vector3.new(t, -10 + R(0, 8), -(edge + R(-4, 8))), R(22, 34), mat)
				if i > 1 then
					hill(zone.center + Vector3.new(t, -10 + R(0, 8), edge + R(-4, 8)), R(22, 34), mat)
				end
			end
		end
		if i == #Config.Zones then
			hill(zone.center + Vector3.new(0, -8, -(edge + 6)), 34, mat)
		end
		-- Sommets enneiges/roches plus loin pour l'horizon
		for k = 1, 8 do
			local a = (k / 8) * math.pi * 2
			hill(zone.center + Vector3.new(math.cos(a) * (half + 80), -20, math.sin(a) * (half + 80)), R(45, 65), zone.id == "Desert" and Enum.Material.Sandstone or Enum.Material.Rock)
		end
	end
	-- Pas de colline sur l'entree du village (le spawn regarde vers le sud)
	-- Eaux et reliefs propres a chaque zone
	local village = Config.ZoneById.Village
	pond(village.center + Vector3.new(-62, 0, -55), 20, Enum.Material.Sand)
	local foret = Config.ZoneById.Foret
	pond(foret.center + Vector3.new(55, 0, 40), 18, Enum.Material.Ground)
	for k = 1, 6 do
		hill(foret.center + Vector3.new(R(-80, 80), -9, R(-80, 80)), R(10, 13), Enum.Material.LeafyGrass)
	end
	local desert = Config.ZoneById.Desert
	pond(desert.center + Vector3.new(-50, 0, -40), 16, Enum.Material.Grass)
	for k = 1, 14 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = R(86, 104)
		hill(desert.center + Vector3.new(math.cos(a) * r, -12, math.sin(a) * r), R(14, 20), Enum.Material.Sand)
	end
end

-- Props ---------------------------------------------------------------------------------

local LEAF_COLORS = { Color3.fromRGB(90, 190, 70), Color3.fromRGB(110, 210, 80), Color3.fromRGB(70, 170, 70) }

local function roundTree(parent, pos, scale)
	scale = scale or 1
	cylinder(CFrame.new(pos + Vector3.new(0, 4 * scale, 0)), 8 * scale, 0.9 * scale, Color3.fromRGB(120, 80, 45), parent, Enum.Material.Wood)
	local base = pos + Vector3.new(0, 9 * scale, 0)
	ballPart(CFrame.new(base), 9 * scale, LEAF_COLORS[rng:NextInteger(1, 3)], parent, Enum.Material.Grass)
	for k = 1, 4 do
		local a = k * 1.7
		ballPart(CFrame.new(base + Vector3.new(math.cos(a) * 3 * scale, R(-1, 2) * scale, math.sin(a) * 3 * scale)), R(5, 7) * scale, LEAF_COLORS[rng:NextInteger(1, 3)], parent, Enum.Material.Grass)
	end
	-- petits fruits
	for k = 1, 3 do
		local a = k * 2.1
		ballPart(CFrame.new(base + Vector3.new(math.cos(a) * 4.2 * scale, R(-1, 1.5) * scale, math.sin(a) * 4.2 * scale)), 0.9 * scale, Color3.fromRGB(255, 80, 80), parent)
	end
end

local function pineTree(parent, pos, scale)
	scale = scale or 1
	cylinder(CFrame.new(pos + Vector3.new(0, 3 * scale, 0)), 6 * scale, 0.8 * scale, Color3.fromRGB(100, 65, 40), parent, Enum.Material.Wood)
	for k = 0, 3 do
		local r = (5.5 - k * 1.2) * scale
		local tier = cylinder(CFrame.new(pos + Vector3.new(0, (5 + k * 3) * scale, 0)), 3.2 * scale, r, Color3.fromRGB(40, 120 + k * 12, 60), parent, Enum.Material.Grass)
		tier.CanCollide = false
	end
	ballPart(CFrame.new(pos + Vector3.new(0, 16.5 * scale, 0)), 1.6 * scale, Color3.fromRGB(60, 160, 80), parent, Enum.Material.Grass)
end

local function palmTree(parent, pos, scale)
	scale = scale or 1
	local lean = R(-0.25, 0.25)
	local cf = CFrame.new(pos) * CFrame.Angles(0, R(0, 6.28), 0)
	for k = 0, 5 do
		cylinder(cf * CFrame.Angles(lean * k * 0.4, 0, 0) * CFrame.new(0, (1.2 + k * 2) * scale, 0), 2.2 * scale, (0.9 - k * 0.06) * scale, k % 2 == 0 and Color3.fromRGB(160, 115, 70) or Color3.fromRGB(140, 95, 55), parent, Enum.Material.Wood)
	end
	local top = (cf * CFrame.Angles(lean * 2.2, 0, 0) * CFrame.new(0, 13 * scale, 0)).Position
	for k = 1, 7 do
		local a = (k / 7) * math.pi * 2
		part({ Size = Vector3.new(1.6 * scale, 0.3 * scale, 7 * scale), CFrame = CFrame.new(top) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(-25), 0, 0) * CFrame.new(0, 0, -3.2 * scale), Color = Color3.fromRGB(70, 175, 70), Material = Enum.Material.Grass, CanCollide = false }, parent)
	end
	for k = 1, 3 do
		ballPart(CFrame.new(top + Vector3.new(math.cos(k * 2) * 0.8, -0.8, math.sin(k * 2) * 0.8)), 1 * scale, Color3.fromRGB(120, 80, 40), parent)
	end
end

local function bush(parent, pos, scale, flowerColor)
	scale = scale or 1
	for k = 1, 3 do
		ballPart(CFrame.new(pos + Vector3.new((k - 2) * 1.6 * scale, 1.2 * scale, R(-0.6, 0.6))), R(2.8, 3.6) * scale, LEAF_COLORS[rng:NextInteger(1, 3)], parent, Enum.Material.Grass)
	end
	if flowerColor then
		for k = 1, 4 do
			ballPart(CFrame.new(pos + Vector3.new(R(-2.5, 2.5) * scale, R(2, 3) * scale, R(-1.2, 1.2) * scale)), 0.7 * scale, flowerColor, parent)
		end
	end
end

local function flowerPatch(parent, pos)
	local colors = { Color3.fromRGB(255, 120, 170), Color3.fromRGB(255, 230, 80), Color3.fromRGB(150, 140, 255), Color3.new(1, 1, 1) }
	for k = 1, 6 do
		local p = pos + Vector3.new(R(-3, 3), 0, R(-3, 3))
		part({ Size = Vector3.new(0.15, 1, 0.15), CFrame = CFrame.new(p + Vector3.new(0, 0.5, 0)), Color = Color3.fromRGB(70, 160, 60), CanCollide = false }, parent)
		ballPart(CFrame.new(p + Vector3.new(0, 1.1, 0)), 0.6, colors[rng:NextInteger(1, #colors)], parent)
	end
end

local function rock(parent, pos, scale, color)
	scale = scale or 1
	part({ Size = Vector3.new(R(3, 5), R(2, 3.5), R(3, 5)) * scale, CFrame = CFrame.new(pos + Vector3.new(0, 0.6 * scale, 0)) * CFrame.Angles(R(-0.3, 0.3), R(0, 6.28), R(-0.3, 0.3)), Color = color or Color3.fromRGB(140, 140, 155), Material = Enum.Material.Slate }, parent)
end

local function mushroom(parent, pos, scale)
	scale = scale or 1
	cylinder(CFrame.new(pos + Vector3.new(0, 1 * scale, 0)), 2 * scale, 0.45 * scale, Color3.fromRGB(245, 235, 220), parent)
	local cap = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3) * scale, CFrame = CFrame.new(pos + Vector3.new(0, 2.2 * scale, 0)), Color = Color3.fromRGB(235, 60, 70), CanCollide = false }, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 0.6, 1)
	mesh.Parent = cap
	for k = 1, 4 do
		local a = k * 1.6
		ballPart(CFrame.new(pos + Vector3.new(math.cos(a) * 0.8 * scale, 2.75 * scale, math.sin(a) * 0.8 * scale)), 0.5 * scale, Color3.new(1, 1, 1), parent)
	end
end

local function lamp(parent, pos)
	cylinder(CFrame.new(pos + Vector3.new(0, 0.3, 0)), 0.6, 0.8, Color3.fromRGB(50, 50, 60), parent, Enum.Material.Metal)
	cylinder(CFrame.new(pos + Vector3.new(0, 4.5, 0)), 9, 0.25, Color3.fromRGB(50, 50, 60), parent, Enum.Material.Metal)
	local bulb = ballPart(CFrame.new(pos + Vector3.new(0, 9.4, 0)), 1.6, Color3.fromRGB(255, 230, 170), parent, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 160)
	light.Range = 18
	light.Brightness = 1.5
	light.Parent = bulb
end

local function fenceLine(parent, from, to)
	local dir = to - from
	local len = dir.Magnitude
	local posts = math.floor(len / 6)
	for k = 0, posts do
		local p = from + dir * (k / posts)
		part({ Size = Vector3.new(0.6, 3.2, 0.6), CFrame = CFrame.new(p + Vector3.new(0, 1.6, 0)), Color = Color3.fromRGB(240, 235, 225), Material = Enum.Material.WoodPlanks }, parent)
	end
	for _, h in ipairs({ 1.2, 2.4 }) do
		part({ Size = Vector3.new(0.3, 0.4, len), CFrame = CFrame.lookAt((from + to) / 2 + Vector3.new(0, h, 0), to + Vector3.new(0, h, 0)), Color = Color3.fromRGB(240, 235, 225), Material = Enum.Material.WoodPlanks }, parent)
	end
end

local HOUSE_WALLS = { Color3.fromRGB(255, 225, 180), Color3.fromRGB(190, 225, 255), Color3.fromRGB(255, 200, 215), Color3.fromRGB(215, 245, 190) }
local HOUSE_ROOFS = { Color3.fromRGB(220, 75, 65), Color3.fromRGB(70, 120, 210), Color3.fromRGB(230, 140, 50), Color3.fromRGB(150, 80, 190) }

local function house(parent, cf, k)
	local w, d, h = 14, 12, 9
	local wall = HOUSE_WALLS[(k % #HOUSE_WALLS) + 1]
	local roof = HOUSE_ROOFS[(k % #HOUSE_ROOFS) + 1]
	part({ Size = Vector3.new(w + 1, 1, d + 1), CFrame = cf * CFrame.new(0, 0.5, 0), Color = Color3.fromRGB(150, 150, 160), Material = Enum.Material.Cobblestone }, parent)
	part({ Size = Vector3.new(w, h, d), CFrame = cf * CFrame.new(0, h / 2 + 1, 0), Color = wall }, parent)
	-- poutres
	for _, x in ipairs({ -w / 2, w / 2 }) do
		for _, z in ipairs({ -d / 2, d / 2 }) do
			part({ Size = Vector3.new(0.8, h, 0.8), CFrame = cf * CFrame.new(x, h / 2 + 1, z), Color = Color3.fromRGB(130, 85, 50), Material = Enum.Material.Wood }, parent)
		end
	end
	-- toit a deux pans
	local rh = 6
	wedge({ Size = Vector3.new(w + 2, rh, d / 2 + 1), CFrame = cf * CFrame.new(0, h + 1 + rh / 2, -(d / 4 + 0.5)), Color = roof }, parent)
	wedge({ Size = Vector3.new(w + 2, rh, d / 2 + 1), CFrame = cf * CFrame.new(0, h + 1 + rh / 2, d / 4 + 0.5) * CFrame.Angles(0, math.pi, 0), Color = roof }, parent)
	-- cheminee
	part({ Size = Vector3.new(1.8, 4, 1.8), CFrame = cf * CFrame.new(w / 3, h + rh, d / 5), Color = Color3.fromRGB(170, 90, 70), Material = Enum.Material.Brick }, parent)
	-- porte (face -Z, vers l'avant de cf)
	part({ Size = Vector3.new(3.2, 5.5, 0.4), CFrame = cf * CFrame.new(0, 3.75, -d / 2 - 0.2), Color = Color3.fromRGB(140, 90, 50), Material = Enum.Material.WoodPlanks }, parent)
	ballPart(cf * CFrame.new(1, 3.6, -d / 2 - 0.5), 0.4, Color3.fromRGB(255, 210, 60), parent, Enum.Material.Metal)
	-- fenetres
	for _, x in ipairs({ -w / 3.2, w / 3.2 }) do
		part({ Size = Vector3.new(2.8, 2.6, 0.3), CFrame = cf * CFrame.new(x, 5.5, -d / 2 - 0.15), Color = Color3.fromRGB(170, 220, 255), Material = Enum.Material.Glass, Transparency = 0.2 }, parent)
		part({ Size = Vector3.new(3.4, 0.4, 0.6), CFrame = cf * CFrame.new(x, 4, -d / 2 - 0.3), Color = Color3.new(1, 1, 1) }, parent)
		bush(parent, (cf * CFrame.new(x, 0, -d / 2 - 1.8)).Position, 0.45, Color3.fromRGB(255, 120, 170))
	end
end

-- Stand avec auvent raye (style boutique)
local function stand(parent, pos, lookAt, title, color, tag, attrs, promptText)
	local cf = CFrame.lookAt(pos, Vector3.new(lookAt.X, pos.Y, lookAt.Z))
	local counter = part({ Name = tag, Size = Vector3.new(12, 3.4, 4), CFrame = cf * CFrame.new(0, 1.7, 0), Color = Color3.fromRGB(170, 115, 65), Material = Enum.Material.WoodPlanks }, parent)
	part({ Size = Vector3.new(12.6, 0.5, 4.6), CFrame = cf * CFrame.new(0, 3.6, 0), Color = Color3.fromRGB(240, 235, 225), Material = Enum.Material.WoodPlanks }, parent)
	for _, x in ipairs({ -6, 6 }) do
		part({ Size = Vector3.new(0.7, 9, 0.7), CFrame = cf * CFrame.new(x, 4.5, 1.5), Color = Color3.fromRGB(240, 235, 225), Material = Enum.Material.Wood }, parent)
	end
	-- auvent raye incline
	for k = 0, 7 do
		local stripe = wedge({ Size = Vector3.new(1.6, 2, 6), CFrame = cf * CFrame.new(-5.6 + k * 1.6, 9.8, -0.5) * CFrame.Angles(0, math.pi, 0), Color = (k % 2 == 0) and color or Color3.new(1, 1, 1) }, parent)
		stripe.CanCollide = false
		local scallop = ballPart(cf * CFrame.new(-5.6 + k * 1.6, 8.8, -3.5), 1.6, (k % 2 == 0) and color or Color3.new(1, 1, 1), parent)
		scallop.CanCollide = false
	end
	sign(parent, cf * CFrame.new(0, 12, 0.5), Vector3.new(11, 2.6, 0.5), title, Color3.new(1, 1, 1), color)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = promptText or "Ouvrir"
	prompt.ObjectText = title
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter
	for k, v in pairs(attrs or {}) do
		counter:SetAttribute(k, v)
	end
	CollectionService:AddTag(counter, tag)
	avoidCircle(pos, 12)
	return counter, cf
end

-- Grand oeuf decoratif tournant sur un piedestal
local function eggDisplay(parent, pos, color)
	cylinder(CFrame.new(pos + Vector3.new(0, 1, 0)), 2, 4, Color3.fromRGB(240, 240, 245), parent, Enum.Material.Marble)
	local ring = cylinder(CFrame.new(pos + Vector3.new(0, 2.1, 0)), 0.3, 4.3, color, parent, Enum.Material.Neon)
	ring.CanCollide = false
	local egg = part({ Name = "EggDisplay", Shape = Enum.PartType.Ball, Size = Vector3.new(5, 5, 5), CFrame = CFrame.new(pos + Vector3.new(0, 6, 0)), Color = color, CanCollide = false }, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.3, 1)
	mesh.Parent = egg
	for k = 1, 5 do
		local a = k * 1.25
		local spot = ballPart(egg.CFrame * CFrame.new(math.cos(a) * 2.35, R(-1.5, 2), math.sin(a) * 2.35), 1.2, color:Lerp(Color3.new(1, 1, 1), 0.55), parent)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = egg
		weld.Part1 = spot
		weld.Parent = spot
		spot.Anchored = false
	end
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 14
	light.Brightness = 1.5
	light.Parent = egg
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Rate = 6
	sparkles.Lifetime = NumberRange.new(1, 1.6)
	sparkles.Speed = NumberRange.new(1, 2)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	sparkles.LightEmission = 1
	sparkles.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	sparkles.Parent = egg
	TweenService:Create(egg, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { CFrame = egg.CFrame * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, math.pi, 0) }):Play()
end

-- Arche de pierre + barriere magique (tag Gate)
local function gateArch(parent, pos, nextZone)
	local stone = Color3.fromRGB(175, 170, 180)
	for _, x in ipairs({ -12, 12 }) do
		part({ Size = Vector3.new(5, 20, 5), CFrame = CFrame.new(pos + Vector3.new(x, 10, 0)), Color = stone, Material = Enum.Material.Cobblestone }, parent)
		part({ Size = Vector3.new(6.4, 1.6, 6.4), CFrame = CFrame.new(pos + Vector3.new(x, 0.8, 0)), Color = stone:Lerp(Color3.new(0, 0, 0), 0.15), Material = Enum.Material.Cobblestone }, parent)
		ballPart(CFrame.new(pos + Vector3.new(x, 21.6, 0)), 3.2, Config.Colors.Gold, parent, Enum.Material.Neon)
	end
	part({ Size = Vector3.new(30, 4, 6), CFrame = CFrame.new(pos + Vector3.new(0, 21, 0)), Color = stone, Material = Enum.Material.Cobblestone }, parent)
	sign(parent, CFrame.new(pos + Vector3.new(0, 21, -3.3)), Vector3.new(20, 3, 0.4), string.upper(nextZone.name), Config.Colors.Gold, Color3.fromRGB(60, 50, 80))
	local barrier = part({ Name = "Gate", Size = Vector3.new(19, 19, 1), CFrame = CFrame.new(pos + Vector3.new(0, 9.5, 0)), Color = Color3.fromRGB(120, 200, 255), Material = Enum.Material.ForceField, Transparency = 0.2 }, parent)
	barrier:SetAttribute("ZoneId", nextZone.id)
	CollectionService:AddTag(barrier, "Gate")
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Debloquer (" .. nextZone.price .. ")"
	prompt.ObjectText = nextZone.name
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = barrier
end

-- Murs invisibles avec ouverture pour les couloirs
local function walls(parent, zone, index)
	local c = zone.center
	local half = zone.size / 2
	local hasNorth = Config.Zones[index + 1] ~= nil
	local hasSouth = index > 1
	local h = 60
	part({ Size = Vector3.new(2, h, zone.size), CFrame = CFrame.new(c + Vector3.new(half, h / 2, 0)), Transparency = 1 }, parent)
	part({ Size = Vector3.new(2, h, zone.size), CFrame = CFrame.new(c + Vector3.new(-half, h / 2, 0)), Transparency = 1 }, parent)
	for _, side in ipairs({ { -1, hasNorth }, { 1, hasSouth } }) do
		local z = side[1] * half
		if side[2] then
			local seg = (zone.size - 24) / 2
			part({ Size = Vector3.new(seg, h, 2), CFrame = CFrame.new(c + Vector3.new(-(12 + seg / 2), h / 2, z)), Transparency = 1 }, parent)
			part({ Size = Vector3.new(seg, h, 2), CFrame = CFrame.new(c + Vector3.new(12 + seg / 2, h / 2, z)), Transparency = 1 }, parent)
		else
			part({ Size = Vector3.new(zone.size, h, 2), CFrame = CFrame.new(c + Vector3.new(0, h / 2, z)), Transparency = 1 }, parent)
		end
	end
	if hasNorth then
		local nextZone = Config.Zones[index + 1]
		local z0 = c.Z - half
		local z1 = nextZone.center.Z + nextZone.size / 2
		for _, x in ipairs({ -12, 12 }) do
			part({ Size = Vector3.new(2, h, math.abs(z0 - z1)), CFrame = CFrame.new(x, h / 2, (z0 + z1) / 2), Transparency = 1 }, parent)
		end
	end
end

-- Zones -----------------------------------------------------------------------------------

local coinSpots = {}

local function scatter(zone, count, minR, maxR, fn)
	local half = zone.size / 2
	for k = 1, count do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = R(minR or 20, maxR or (half - 12))
		local pos = zone.center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local blocked = math.abs(pos.X) < 14 -- allee centrale
		for _, av in ipairs(avoid) do
			if (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(av.pos.X, 0, av.pos.Z)).Magnitude < av.radius then
				blocked = true
			end
		end
		if not blocked then
			fn(pos, k)
		end
	end
end

local function buildVillage(folder, zone)
	local c = zone.center
	-- Place centrale avec fontaine
	Terrain:FillCylinder(CFrame.new(c + Vector3.new(0, -1, 20)), 2, 22, Enum.Material.Cobblestone)
	Terrain:FillBlock(CFrame.new(c + Vector3.new(0, -1, 0)), Vector3.new(14, 2, zone.size), Enum.Material.Cobblestone)
	avoidCircle(c + Vector3.new(0, 0, 20), 14)
	local fc = c + Vector3.new(0, 0, 20)
	cylinder(CFrame.new(fc + Vector3.new(0, 1, 0)), 2, 9, Color3.fromRGB(235, 235, 240), folder, Enum.Material.Marble)
	local water = cylinder(CFrame.new(fc + Vector3.new(0, 1.8, 0)), 0.6, 8, Color3.fromRGB(80, 180, 255), folder, Enum.Material.Glass)
	water.Transparency = 0.25
	water.CanCollide = false
	cylinder(CFrame.new(fc + Vector3.new(0, 4, 0)), 5, 1.2, Color3.fromRGB(235, 235, 240), folder, Enum.Material.Marble)
	cylinder(CFrame.new(fc + Vector3.new(0, 6.6, 0)), 0.8, 3.6, Color3.fromRGB(235, 235, 240), folder, Enum.Material.Marble)
	local jet = part({ Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(fc + Vector3.new(0, 7.2, 0)), Transparency = 1, CanCollide = false }, folder)
	local spray = Instance.new("ParticleEmitter")
	spray.Rate = 60
	spray.Lifetime = NumberRange.new(1, 1.3)
	spray.Speed = NumberRange.new(14, 18)
	spray.SpreadAngle = Vector2.new(14, 14)
	spray.Acceleration = Vector3.new(0, -40, 0)
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.9) })
	spray.Transparency = NumberSequence.new(0.2, 1)
	spray.Color = ColorSequence.new(Color3.fromRGB(200, 235, 255))
	spray.Parent = jet

	-- Maisons
	local spots = {
		{ Vector3.new(-75, 0, 70), 0.6 }, { Vector3.new(-80, 0, 20), 1.2 }, { Vector3.new(80, 0, 75), -0.6 },
		{ Vector3.new(-30, 0, 92), math.pi }, { Vector3.new(85, 0, -85), -2.3 }, { Vector3.new(-85, 0, -95), 2.3 },
	}
	for k, s in ipairs(spots) do
		local pos = c + s[1]
		house(folder, CFrame.new(pos) * CFrame.Angles(0, s[2], 0) * CFrame.Angles(0, math.pi, 0), k)
		avoidCircle(pos, 14)
	end
	-- Lampadaires le long de l'allee
	for z = -90, 90, 30 do
		lamp(folder, c + Vector3.new(-10, 0, z))
		lamp(folder, c + Vector3.new(10, 0, z))
	end
	-- Barrieres decoratives autour de l'etang
	fenceLine(folder, c + Vector3.new(-90, 0, -30), c + Vector3.new(-40, 0, -30))
	scatter(zone, 30, 20, 100, function(pos)
		roundTree(folder, pos, R(0.8, 1.2))
		avoidCircle(pos, 5)
	end)
	scatter(zone, 26, 15, 100, function(pos)
		if rng:NextNumber() < 0.5 then
			bush(folder, pos, R(0.8, 1.2), rng:NextNumber() < 0.6 and Color3.fromRGB(255, 120, 170) or nil)
		else
			flowerPatch(folder, pos)
		end
	end)
	scatter(zone, 10, 30, 100, function(pos)
		rock(folder, pos, R(0.7, 1.3))
	end)
end

local function buildForest(folder, zone)
	local c = zone.center
	Terrain:FillBlock(CFrame.new(c + Vector3.new(0, -1, 0)), Vector3.new(12, 2, zone.size), Enum.Material.Ground)
	scatter(zone, 70, 15, 104, function(pos)
		if rng:NextNumber() < 0.75 then
			pineTree(folder, pos, R(0.9, 1.6))
		else
			roundTree(folder, pos, R(0.9, 1.3))
		end
		avoidCircle(pos, 4)
	end)
	scatter(zone, 30, 12, 100, function(pos)
		mushroom(folder, pos, R(0.6, 1.4))
	end)
	scatter(zone, 18, 20, 100, function(pos)
		rock(folder, pos, R(0.8, 1.8), Color3.fromRGB(120, 125, 135))
	end)
	scatter(zone, 20, 12, 100, function(pos)
		bush(folder, pos, R(0.8, 1.3), Color3.fromRGB(150, 140, 255))
	end)
	-- Rondins et pont
	for k = 1, 5 do
		local pos = c + Vector3.new(R(-70, 70), 0, R(-70, 70))
		part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(R(6, 9), 2.2, 2.2), CFrame = CFrame.new(pos + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, R(0, 6.28), 0), Color = Color3.fromRGB(120, 80, 45), Material = Enum.Material.Wood }, folder)
	end
	-- Lucioles
	local zoneBox = part({ Size = Vector3.new(zone.size, 14, zone.size), CFrame = CFrame.new(c + Vector3.new(0, 8, 0)), Transparency = 1, CanCollide = false, CanQuery = false }, folder)
	local flies = Instance.new("ParticleEmitter")
	flies.Rate = 40
	flies.Lifetime = NumberRange.new(4, 7)
	flies.Speed = NumberRange.new(0.5, 1.5)
	flies.SpreadAngle = Vector2.new(180, 180)
	flies.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.35), NumberSequenceKeypoint.new(1, 0) })
	flies.LightEmission = 1
	flies.Color = ColorSequence.new(Color3.fromRGB(230, 255, 130))
	flies.Shape = Enum.ParticleEmitterShape.Box
	flies.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	flies.Parent = zoneBox
end

local function buildDesert(folder, zone)
	local c = zone.center
	Terrain:FillBlock(CFrame.new(c + Vector3.new(0, -1, 0)), Vector3.new(12, 2, zone.size), Enum.Material.Sandstone)
	-- Pyramides a degres
	for k, def in ipairs({ { Vector3.new(70, 0, -60), 28 }, { Vector3.new(-80, 0, 70), 20 }, { Vector3.new(80, 0, 60), 16 } }) do
		local pos = c + def[1]
		local size = def[2]
		local steps = 6
		for s = 0, steps - 1 do
			local w = size * (1 - s / steps)
			part({ Size = Vector3.new(w, size / steps, w), CFrame = CFrame.new(pos + Vector3.new(0, (s + 0.5) * size / steps, 0)), Color = Color3.fromRGB(225, 185, 115):Lerp(Color3.fromRGB(245, 215, 150), s / steps), Material = Enum.Material.Sandstone }, folder)
		end
		ballPart(CFrame.new(pos + Vector3.new(0, size + 1, 0)), 2.4, Config.Colors.Gold, folder, Enum.Material.Neon)
		avoidCircle(pos, size * 0.75 + 4)
	end
	-- Oasis : palmiers autour de l'eau
	local oasis = c + Vector3.new(-50, 0, -40)
	for k = 1, 7 do
		local a = (k / 7) * math.pi * 2
		palmTree(folder, oasis + Vector3.new(math.cos(a) * 24, 0, math.sin(a) * 24), R(0.9, 1.3))
	end
	scatter(zone, 26, 18, 100, function(pos)
		local h = R(5, 9)
		local g = Color3.fromRGB(80, 175, 90)
		cylinder(CFrame.new(pos + Vector3.new(0, h / 2, 0)), h, 1, g, folder)
		ballPart(CFrame.new(pos + Vector3.new(0, h, 0)), 2, g, folder)
		for _, side in ipairs({ -1, 1 }) do
			local ah = R(2, 3.5)
			part({ Size = Vector3.new(2.2, 1.4, 1.4), CFrame = CFrame.new(pos + Vector3.new(side * 1.3, h * 0.45, 0)), Color = g }, folder)
			cylinder(CFrame.new(pos + Vector3.new(side * 2.2, h * 0.45 + ah / 2, 0)), ah, 0.7, g, folder)
			ballPart(CFrame.new(pos + Vector3.new(side * 2.2, h * 0.45 + ah, 0)), 1.4, g, folder)
		end
		ballPart(CFrame.new(pos + Vector3.new(0, h + 1, 0)), 0.9, Color3.fromRGB(255, 120, 170), folder)
		avoidCircle(pos, 4)
	end)
	scatter(zone, 16, 20, 100, function(pos)
		rock(folder, pos, R(0.8, 2), Color3.fromRGB(200, 150, 100))
	end)
	-- Ossements et sable volant
	local box = part({ Size = Vector3.new(zone.size, 6, zone.size), CFrame = CFrame.new(c + Vector3.new(0, 3, 0)), Transparency = 1, CanCollide = false, CanQuery = false }, folder)
	local dust = Instance.new("ParticleEmitter")
	dust.Rate = 25
	dust.Lifetime = NumberRange.new(3, 5)
	dust.Speed = NumberRange.new(3, 6)
	dust.EmissionDirection = Enum.NormalId.Right
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.4), NumberSequenceKeypoint.new(1, 0) })
	dust.Transparency = NumberSequence.new(0.4, 1)
	dust.Color = ColorSequence.new(Color3.fromRGB(250, 225, 170))
	dust.Shape = Enum.ParticleEmitterShape.Box
	dust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	dust.Parent = box
end

local BUILDERS = { Village = buildVillage, Foret = buildForest, Desert = buildDesert }

local function buildZone(root, zone, index)
	local folder = Instance.new("Folder")
	folder.Name = "Zone_" .. zone.id
	folder:SetAttribute("ZoneId", zone.id)
	folder.Parent = root
	local c = zone.center
	local half = zone.size / 2
	walls(folder, zone, index)

	-- Stand a oeuf (avant le decor pour reserver la place)
	local egg = Config.Eggs[index]
	local eggPos = c + Vector3.new(-45, 0, 30)
	stand(folder, eggPos, c + Vector3.new(0, 0, 30), string.upper(egg.name), egg.color:Lerp(Color3.fromRGB(150, 80, 255), 0.45), "EggStand", { EggId = egg.id }, "Ouvrir un oeuf")
	eggDisplay(folder, eggPos + Vector3.new(-8, 0, -8), egg.color)
	eggDisplay(folder, eggPos + Vector3.new(8, 0, -8), egg.color:Lerp(Color3.fromRGB(255, 200, 255), 0.5))

	-- Panneau d'entree de zone
	sign(folder, CFrame.new(c + Vector3.new(20, 6, half - 8)) * CFrame.Angles(0, math.pi, 0), Vector3.new(18, 4, 0.6), string.upper(zone.name), Config.Colors.Gold, Color3.fromRGB(150, 100, 60))
	part({ Size = Vector3.new(0.8, 6, 0.8), CFrame = CFrame.new(c + Vector3.new(14, 3, half - 8)), Color = Color3.fromRGB(130, 85, 50), Material = Enum.Material.Wood }, folder)
	part({ Size = Vector3.new(0.8, 6, 0.8), CFrame = CFrame.new(c + Vector3.new(26, 3, half - 8)), Color = Color3.fromRGB(130, 85, 50), Material = Enum.Material.Wood }, folder)

	if index == 1 then
		MapBuilder._reserveVillage(folder, zone)
	end

	BUILDERS[zone.id](folder, zone)

	local nextZone = Config.Zones[index + 1]
	if nextZone then
		gateArch(folder, c + Vector3.new(0, 0, -half), nextZone)
	end

	-- Points de spawn des coins (sur le sol libre)
	coinSpots[zone.id] = {}
	local tries = 0
	while #coinSpots[zone.id] < zone.coinCount and tries < 2000 do
		tries += 1
		local a = rng:NextNumber(0, math.pi * 2)
		local r = R(10, half - 22)
		local pos = c + Vector3.new(math.cos(a) * r, 2.2, math.sin(a) * r)
		local ok = true
		for _, av in ipairs(avoid) do
			if (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(av.pos.X, 0, av.pos.Z)).Magnitude < av.radius then
				ok = false
				break
			end
		end
		if ok then
			table.insert(coinSpots[zone.id], pos)
		end
	end
end

-- Piste de course, spawn, classement, cadeau (Village) -------------------------------------

local raceWaypoints = {}

local function buildRaceTrack(root, center)
	local rx, rz = 36, 22
	local n = 28
	for i = 0, n - 1 do
		local a = (i / n) * math.pi * 2
		table.insert(raceWaypoints, center + Vector3.new(math.cos(a) * rx, 1.2, math.sin(a) * rz))
	end
	Terrain:FillBlock(CFrame.new(center + Vector3.new(0, -1, 0)), Vector3.new(rx * 2 + 20, 2, rz * 2 + 20), Enum.Material.Grass)
	for i = 1, n do
		local p1 = raceWaypoints[i] - Vector3.new(0, 1.2, 0)
		local p2 = raceWaypoints[(i % n) + 1] - Vector3.new(0, 1.2, 0)
		local len = (p2 - p1).Magnitude + 1.2
		local cf = CFrame.lookAt((p1 + p2) / 2 + Vector3.new(0, 0.15, 0), p2 + Vector3.new(0, 0.15, 0))
		part({ Name = "Track", Size = Vector3.new(11, 0.3, len), CFrame = cf, Color = Color3.fromRGB(215, 110, 70), Material = Enum.Material.Sand, CanCollide = false }, root)
		for _, x in ipairs({ -5.8, 5.8 }) do
			part({ Name = "TrackEdge", Size = Vector3.new(0.6, 0.6, len), CFrame = cf * CFrame.new(x, 0.15, 0), Color = (i % 2 == 0) and Color3.fromRGB(240, 60, 60) or Color3.new(1, 1, 1), CanCollide = false }, root)
		end
	end
	-- Ligne d'arrivee en damier
	local start = raceWaypoints[1] - Vector3.new(0, 1.2, 0)
	for row = 0, 1 do
		for col = 0, 5 do
			part({ Size = Vector3.new(1.8, 0.35, 1.8), CFrame = CFrame.new(start + Vector3.new(-1.8 + row * 1.8 + 0.9, 0.2, -5 + col * 1.8 + 0.9)), Color = ((row + col) % 2 == 0) and Color3.new(1, 1, 1) or Color3.fromRGB(25, 25, 30), CanCollide = false }, root)
		end
	end
	for _, z in ipairs({ -7, 7 }) do
		part({ Size = Vector3.new(1.2, 10, 1.2), CFrame = CFrame.new(start + Vector3.new(0, 5, z)), Color = Color3.new(1, 1, 1), Material = Enum.Material.Metal }, root)
	end
	sign(root, CFrame.new(start + Vector3.new(0, 10.5, 0)) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(15, 2.8, 0.5), "ARRIVEE", Color3.new(1, 1, 1), Color3.fromRGB(230, 60, 60))
	-- Tribunes
	for k = 0, 2 do
		part({ Size = Vector3.new(34, 1.4 + k * 1.4, 3.2), CFrame = CFrame.new(center + Vector3.new(0, 0.7 + k * 0.7, rz + 12 + k * 3.2)), Color = (k % 2 == 0) and Color3.fromRGB(70, 150, 255) or Color3.new(1, 1, 1) }, root)
	end
	for _, x in ipairs({ -30, -10, 10, 30 }) do
		local flag = part({ Size = Vector3.new(0.3, 8, 0.3), CFrame = CFrame.new(center + Vector3.new(x, 4, rz + 22)), Color = Color3.new(1, 1, 1) }, root)
		part({ Size = Vector3.new(0.1, 2, 3), CFrame = CFrame.new(center + Vector3.new(x, 7, rz + 23.5)), Color = Color3.fromRGB(255, 200, 40), CanCollide = false }, root)
	end
	stand(root, center + Vector3.new(0, 0, -rz - 14), center + Vector3.new(0, 0, -rz - 40), "COURSES", Color3.fromRGB(240, 60, 60), "RaceStand", {}, "Courses")
	avoidCircle(center, rx + 10)
end

function MapBuilder._reserveVillage(folder, zone)
	local c = zone.center
	local spawnPos = Config.Map.SpawnPosition
	avoidCircle(Vector3.new(spawnPos.X, 0, spawnPos.Z), 16)
	buildRaceTrack(folder, c + Vector3.new(55, 0, -45))

	-- Spawn
	local existing = workspace:FindFirstChildOfClass("SpawnLocation")
	if existing then
		existing:Destroy()
	end
	Terrain:FillCylinder(CFrame.new(spawnPos.X, -1, spawnPos.Z), 2, 12, Enum.Material.Cobblestone)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "MainSpawn"
	spawn.Shape = Enum.PartType.Cylinder
	spawn.Size = Vector3.new(0.6, 14, 14)
	spawn.CFrame = CFrame.new(spawnPos.X, 0.3, spawnPos.Z) * CFrame.Angles(0, 0, math.rad(90))
	spawn.Anchored = true
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Color = Color3.fromRGB(120, 210, 255)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder
	local ring = cylinder(CFrame.new(spawnPos.X, 0.4, spawnPos.Z), 0.4, 7.5, Color3.new(1, 1, 1), folder, Enum.Material.Neon)
	ring.CanCollide = false
	ring.Transparency = 0.4

	-- Grand panneau titre
	local title = sign(folder, CFrame.new(spawnPos.X, 13, spawnPos.Z + 20) * CFrame.Angles(0, math.pi, 0), Vector3.new(34, 8, 1), "PET RUSH", Color3.fromRGB(255, 210, 60), Color3.fromRGB(120, 70, 200))
	for _, x in ipairs({ -15, 15 }) do
		part({ Size = Vector3.new(1.2, 13, 1.2), CFrame = CFrame.new(spawnPos.X + x, 6.5, spawnPos.Z + 20), Color = Color3.new(1, 1, 1), Material = Enum.Material.Wood }, folder)
	end

	-- Classement
	local boardPos = c + Vector3.new(-45, 0, 85)
	local board = part({ Name = "Leaderboard", Size = Vector3.new(20, 16, 1), CFrame = CFrame.lookAt(boardPos + Vector3.new(0, 10, 0), Vector3.new(spawnPos.X, 10, spawnPos.Z)), Color = Color3.fromRGB(40, 45, 90) }, folder)
	part({ Size = Vector3.new(21.6, 17.6, 0.8), CFrame = board.CFrame * CFrame.new(0, 0, 0.3), Color = Config.Colors.Gold, Material = Enum.Material.Metal }, folder)
	for _, x in ipairs({ -8, 8 }) do
		part({ Size = Vector3.new(1, 3, 1), CFrame = board.CFrame * CFrame.new(x, -9.5, 0.3), Color = Config.Colors.Gold, Material = Enum.Material.Metal }, folder)
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	local head = Instance.new("TextLabel")
	head.Size = UDim2.new(1, 0, 0.16, 0)
	head.BackgroundTransparency = 1
	head.Text = "TOP COINS"
	head.TextColor3 = Config.Colors.Gold
	head.Font = Enum.Font.FredokaOne
	head.TextScaled = true
	head.Parent = gui
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(22, 24, 52)
	st.Thickness = 4
	st.Parent = head
	local list = Instance.new("TextLabel")
	list.Size = UDim2.new(1, -30, 0.8, 0)
	list.Position = UDim2.new(0, 15, 0.18, 0)
	list.BackgroundTransparency = 1
	list.Text = "Chargement..."
	list.TextColor3 = Color3.new(1, 1, 1)
	list.Font = Enum.Font.FredokaOne
	list.TextScaled = true
	list.TextXAlignment = Enum.TextXAlignment.Left
	list.TextYAlignment = Enum.TextYAlignment.Top
	list.Parent = gui
	gui.Parent = board
	MapBuilder.LeaderboardLabel = list
	avoidCircle(boardPos, 12)

	-- Stand cadeau du jour
	stand(folder, c + Vector3.new(45, 0, 88), Vector3.new(spawnPos.X, 0, spawnPos.Z), "CADEAU", Color3.fromRGB(255, 170, 30), "DailyStand", {}, "Recuperer")
end

-- Construction ------------------------------------------------------------------------------

function MapBuilder.Build()
	for _, name in ipairs({ "PetRush", "Baseplate" }) do
		local old = workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local root = Instance.new("Folder")
	root.Name = "PetRush"
	root.Parent = workspace
	buildLighting()
	buildTerrain()
	for i, zone in ipairs(Config.Zones) do
		buildZone(root, zone, i)
	end
	for _, name in ipairs({ "Coins", "Racers" }) do
		if not workspace:FindFirstChild(name) then
			local f = Instance.new("Folder")
			f.Name = name
			f.Parent = workspace
		end
	end
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
