-- Monde de RELIC RUSH : 7 iles (une par monde), eclairage, point d'arrivee, caisses de reliques,
-- portails, arene de boss, batiments interactifs (boutique, forge, autel de renaissance, tableau
-- des quetes) et emplacements des tresors.
-- Les invites (ProximityPrompt) ont un attribut "Panel" : le client ouvre l'interface correspondante.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local RelicModel = require(ReplicatedStorage.Shared.RelicModel)
local Kit = require(script.Parent.MapKit)
local MapZones = require(script.Parent.MapZones)

local WorldBuilder = {}

local part, wedge, ball, cylinder, sign = Kit.part, Kit.wedge, Kit.ball, Kit.cylinder, Kit.sign
local R, rng = Kit.R, Kit.rng
local avoidCircle = Kit.avoidCircle
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 200, 60)
local NAVY = Color3.fromRGB(30, 35, 80)
local PURPLE = Color3.fromRGB(130, 70, 220)
local STONE = Color3.fromRGB(165, 160, 175)

local spots = {} -- [worldId] = { positions des tresors }
local spawns = {} -- [worldId] = CFrame
local arenas = {} -- [worldId] = Vector3
local crates = {} -- [worldId] = Vector3

local PALETTES = {
	Village = { top = Color3.fromRGB(120, 210, 85), drip = Color3.fromRGB(100, 190, 70), dirt = Color3.fromRGB(165, 112, 70), dirt2 = Color3.fromRGB(135, 88, 55), path = Color3.fromRGB(240, 222, 175) },
	Forest = { top = Color3.fromRGB(80, 175, 85), drip = Color3.fromRGB(60, 150, 70), dirt = Color3.fromRGB(125, 90, 62), dirt2 = Color3.fromRGB(100, 72, 50), path = Color3.fromRGB(205, 170, 115) },
	Cave = { top = Color3.fromRGB(105, 85, 160), drip = Color3.fromRGB(85, 70, 140), dirt = Color3.fromRGB(70, 60, 100), dirt2 = Color3.fromRGB(55, 45, 80), path = Color3.fromRGB(180, 160, 230) },
	Desert = { top = Color3.fromRGB(250, 220, 150), drip = Color3.fromRGB(238, 200, 120), dirt = Color3.fromRGB(222, 155, 92), dirt2 = Color3.fromRGB(192, 128, 75), path = Color3.fromRGB(235, 190, 120) },
	Frozen = { top = Color3.fromRGB(240, 248, 255), drip = Color3.fromRGB(220, 236, 255), dirt = Color3.fromRGB(150, 175, 210), dirt2 = Color3.fromRGB(120, 145, 185), path = Color3.fromRGB(195, 220, 245) },
	Lava = { top = Color3.fromRGB(85, 70, 70), drip = Color3.fromRGB(70, 55, 55), dirt = Color3.fromRGB(55, 42, 42), dirt2 = Color3.fromRGB(40, 30, 30), path = Color3.fromRGB(130, 100, 90) },
	Celestial = { top = Color3.fromRGB(250, 248, 255), drip = Color3.fromRGB(235, 230, 255), dirt = Color3.fromRGB(220, 200, 150), dirt2 = Color3.fromRGB(200, 175, 120), path = Color3.fromRGB(255, 230, 160) },
}

-- Eclairage --------------------------------------------------------------------------------------
local function lighting()
	Lighting.ClockTime = 14.5
	Lighting.GeographicLatitude = 35
	Lighting.Brightness = 2.5
	Lighting.Ambient = Color3.fromRGB(120, 115, 150)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 145, 180)
	Lighting.EnvironmentDiffuseScale = 0.7
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.45
	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)
	for _, c in ipairs(Lighting:GetChildren()) do
		c:Destroy()
	end
	local atm = Instance.new("Atmosphere")
	atm.Density = 0.22
	atm.Offset = 0.1
	atm.Color = Color3.fromRGB(190, 200, 255)
	atm.Decay = Color3.fromRGB(120, 110, 200)
	atm.Glare = 0.2
	atm.Haze = 0.8
	atm.Parent = Lighting
	local sky = Instance.new("Sky")
	sky.SunAngularSize = 13
	sky.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.4
	bloom.Size = 24
	bloom.Threshold = 1.3
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.18
	cc.Contrast = 0.06
	cc.Brightness = 0.02
	cc.Parent = Lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.05
	rays.Parent = Lighting
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.5
	clouds.Density = 0.55
	clouds.Parent = workspace.Terrain
end

-- Ile ------------------------------------------------------------------------------------------
local function island(parent, world)
	local pal = PALETTES[world.id]
	local c, s = world.center, world.size
	local half = s / 2
	part({ Name = "Ground", Size = Vector3.new(s, 4, s), CFrame = CFrame.new(c + Vector3.new(0, -2, 0)), Color = pal.top }, parent)
	for t = -half, half, 9 do
		for _, e in ipairs({ Vector3.new(t, -2.6, half), Vector3.new(t, -2.6, -half), Vector3.new(half, -2.6, t), Vector3.new(-half, -2.6, t) }) do
			ball(CFrame.new(c + e), R(5.5, 7.5), pal.drip, parent).CanCollide = false
		end
	end
	local y = -4
	for i, L in ipairs({ { s - 2, 9, pal.dirt }, { s - 22, 11, pal.dirt2 }, { s - 56, 13, pal.dirt }, { s - 104, 14, pal.dirt2 }, { s - 170, 12, pal.dirt } }) do
		if L[1] > 20 then
			part({ Size = Vector3.new(L[1], L[2], L[1]), CFrame = CFrame.new(c + Vector3.new(0, y - L[2] / 2, 0)), Color = L[3] }, parent)
			part({ Size = Vector3.new(L[1] + 0.4, 1.2, L[1] + 0.4), CFrame = CFrame.new(c + Vector3.new(0, y - L[2] * 0.35, 0)), Color = L[3]:Lerp(WHITE, 0.15), CanCollide = false }, parent)
			y -= L[2]
		end
	end
	for k = 1, 10 do
		local a = R(0, math.pi * 2)
		local r = R(20, half - 50)
		ball(CFrame.new(c + Vector3.new(math.cos(a) * r, y - R(0, 10), math.sin(a) * r)), R(8, 16), pal.dirt2, parent)
	end
	-- murs invisibles
	for _, d in ipairs({ Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }) do
		local p = c + d * (half + 1) + Vector3.new(0, 40, 0)
		part({ Name = "Wall", Size = Vector3.new(d.Z ~= 0 and s or 2, 80, d.X ~= 0 and s or 2), CFrame = CFrame.new(p), Transparency = 1 }, parent)
	end
	return pal
end

local function path(parent, a, b, width, color)
	local d = b - a
	part({ Name = "Path", Size = Vector3.new(width, 0.2, d.Magnitude), CFrame = CFrame.lookAt((a + b) / 2 + Vector3.new(0, 0.1, 0), b + Vector3.new(0, 0.1, 0)), Color = color, CanCollide = false }, parent)
	for t = 4, d.Magnitude - 4, 7 do
		part({ Size = Vector3.new(R(2.5, 4), 0.25, R(2, 3)), CFrame = CFrame.lookAt(a, b) * CFrame.new(R(-width / 3, width / 3), 0.18, -t) * CFrame.Angles(0, R(0, 3), 0), Color = color:Lerp(WHITE, 0.35), CanCollide = false }, parent)
	end
	Kit.avoidSegment(a, b, width / 2 + 3)
end

local function plaza(parent, c, radius, color)
	cylinder(CFrame.new(c + Vector3.new(0, 0.12, 0)), 0.25, radius, color, parent).CanCollide = false
	cylinder(CFrame.new(c + Vector3.new(0, 0.1, 0)), 0.25, radius + 1.6, color:Lerp(Color3.new(0, 0, 0), 0.15), parent).CanCollide = false
	for r = radius * 0.35, radius * 0.8, radius * 0.45 do
		cylinder(CFrame.new(c + Vector3.new(0, 0.14, 0)), 0.25, r, color:Lerp(GOLD, 0.25), parent).CanCollide = false
		cylinder(CFrame.new(c + Vector3.new(0, 0.15, 0)), 0.25, r - 1.2, color, parent).CanCollide = false
	end
	avoidCircle(c, radius + 3)
end

-- Invite d'ouverture d'interface
local function prompt(parentPart, action, object, panel, attrs)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0
	p.MaxActivationDistance = 14
	p.RequiresLineOfSight = false
	p:SetAttribute("Panel", panel)
	for k, v in pairs(attrs or {}) do
		p:SetAttribute(k, v)
	end
	p.Parent = parentPart
	return p
end

local function billboard(parentPart, title, sub, color, height)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(220, 70)
	bb.StudsOffsetWorldSpace = Vector3.new(0, height or 8, 0)
	bb.MaxDistance = 140
	bb.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, 0, 0.55, 0)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = color or GOLD
	t.Text = title
	t.Parent = bb
	Instance.new("UIStroke", t).Thickness = 3
	if sub then
		local s = Instance.new("TextLabel")
		s.Name = "Sub"
		s.Size = UDim2.new(1, 0, 0.4, 0)
		s.Position = UDim2.fromScale(0, 0.58)
		s.BackgroundTransparency = 1
		s.Font = Enum.Font.FredokaOne
		s.TextScaled = true
		s.TextColor3 = WHITE
		s.Text = sub
		s.Parent = bb
		Instance.new("UIStroke", s).Thickness = 2.5
	end
	bb.Parent = parentPart
	return bb
end

-- Caisse a reliques sur piedestal (le couvercle s'entrouvre en boucle)
local function crateStand(parent, pos, world, facing)
	local cf = CFrame.lookAt(pos, pos + facing)
	cylinder(cf * CFrame.new(0, 0.8, 0), 1.6, 9, STONE, parent, Enum.Material.Marble)
	cylinder(cf * CFrame.new(0, 1.7, 0), 0.3, 9.4, GOLD, parent, Enum.Material.Metal)
	local ring = cylinder(cf * CFrame.new(0, 1.9, 0), 0.2, 8, PURPLE, parent, Enum.Material.Neon)
	ring.Transparency = 0.3
	local base = part({ Name = "Crate", Size = Vector3.new(7, 4.5, 5), CFrame = cf * CFrame.new(0, 4.25, 0), Color = Color3.fromRGB(150, 95, 55), Material = Enum.Material.WoodPlanks }, parent)
	for _, x in ipairs({ -2.2, 2.2 }) do
		part({ Size = Vector3.new(0.6, 4.6, 5.1), CFrame = cf * CFrame.new(x, 4.25, 0), Color = GOLD, Material = Enum.Material.Metal }, parent)
	end
	local lid = part({ Size = Vector3.new(7.3, 1.4, 5.3), CFrame = cf * CFrame.new(0, 7.2, 0), Color = Color3.fromRGB(120, 75, 45), Material = Enum.Material.WoodPlanks }, parent)
	part({ Size = Vector3.new(1.2, 1.2, 0.4), CFrame = cf * CFrame.new(0, 5.6, -2.6), Color = GOLD, Material = Enum.Material.Metal }, parent)
	local glow = part({ Size = Vector3.new(6.4, 0.2, 4.4), CFrame = cf * CFrame.new(0, 6.6, 0), Color = Config.WorldById[world.id].color, Material = Enum.Material.Neon }, parent)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(190, 130, 255)
	light.Range = 18
	light.Brightness = 2
	light.Parent = glow
	TweenService:Create(lid, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { CFrame = lid.CFrame * CFrame.new(0, 0.5, 1.8) * CFrame.Angles(math.rad(-25), 0, 0) }):Play()
	local e = Instance.new("ParticleEmitter")
	e.Rate = 8
	e.Lifetime = NumberRange.new(1, 1.6)
	e.Speed = NumberRange.new(2, 4)
	e.SpreadAngle = Vector2.new(25, 25)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	e.LightEmission = 1
	e.Color = ColorSequence.new(GOLD, Color3.fromRGB(190, 120, 255))
	e.Parent = glow
	local crate = Config.Crates[world.id]
	billboard(base, string.upper(crate.name), "", GOLD, 9).Sub.Text = "Ouvre pour obtenir une relique"
	prompt(base, "Ouvrir", crate.name, "Crate", { World = world.id })
	-- reliques de ce monde qui flottent autour de la caisse (vitrine)
	local list = {}
	for _, r in ipairs(Config.Relics) do
		if r.world == world.id and not r.boss and not r.secret then
			table.insert(list, r.id)
		end
	end
	for i, id in ipairs(list) do
		local a = i / #list * math.pi * 2
		local m = RelicModel.Build(id)
		local p = cf * CFrame.new(math.cos(a) * 8, 6 + math.sin(i) * 0.8, math.sin(a) * 8)
		m:PivotTo(p)
		m.Parent = parent
		local parts = {}
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
		for _, d in ipairs(parts) do
			TweenService:Create(d, TweenInfo.new(2 + i * 0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { CFrame = d.CFrame + Vector3.new(0, 1.2, 0) }):Play()
		end
	end
	crates[world.id] = pos
	avoidCircle(pos, 13)
end

-- Portail vers un autre monde
local function portal(parent, pos, facing, target)
	local cf = CFrame.lookAt(pos, pos + facing)
	local n = 22
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		local stone = part({ Size = Vector3.new(3.4, 3.4, 3), CFrame = cf * CFrame.new(math.cos(a) * 10, 11 + math.sin(a) * 10, 0) * CFrame.Angles(0, 0, a), Color = (i % 4 == 0) and GOLD or STONE, Material = (i % 4 == 0) and Enum.Material.Metal or Enum.Material.Cobblestone }, parent)
	end
	local disk = part({ Name = "PortalDisk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 18, 18), CFrame = cf * CFrame.new(0, 11, 0) * CFrame.Angles(0, math.rad(90), 0), Color = target.color:Lerp(Color3.fromRGB(80, 160, 255), 0.4), Material = Enum.Material.ForceField, CanCollide = false }, parent)
	local swirl = Instance.new("ParticleEmitter")
	swirl.Rate = 35
	swirl.Lifetime = NumberRange.new(1, 1.6)
	swirl.Speed = NumberRange.new(1, 3)
	swirl.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	swirl.LightEmission = 1
	swirl.Color = ColorSequence.new(WHITE, target.color)
	swirl.Parent = disk
	local l = Instance.new("PointLight")
	l.Color = target.color
	l.Range = 24
	l.Brightness = 2
	l.Parent = disk
	part({ Size = Vector3.new(26, 1.6, 8), CFrame = cf * CFrame.new(0, 0.8, 0), Color = STONE, Material = Enum.Material.Cobblestone }, parent)
	local base = part({ Name = "PortalBase", Size = Vector3.new(4, 4, 4), CFrame = cf * CFrame.new(0, 3, -2), Transparency = 1, CanCollide = false }, parent)
	billboard(base, string.upper(target.name), "", target.color:Lerp(WHITE, 0.3), 20)
	local p = prompt(base, "Voyager", target.name, "Worlds", { Target = target.id })
	p.MaxActivationDistance = 16
	CollectionService:AddTag(p, "Portal")
	avoidCircle(pos, 16)
end

-- Arene de boss (sol circulaire, colonnes, gradins)
local function arena(parent, pos, world)
	cylinder(CFrame.new(pos + Vector3.new(0, 0.3, 0)), 0.6, 34, Color3.fromRGB(150, 145, 165), parent, Enum.Material.Cobblestone)
	local inner = cylinder(CFrame.new(pos + Vector3.new(0, 0.45, 0)), 0.4, 26, Color3.fromRGB(110, 95, 150), parent, Enum.Material.Slate)
	local glow = cylinder(CFrame.new(pos + Vector3.new(0, 0.5, 0)), 0.4, 25, PURPLE, parent, Enum.Material.Neon)
	glow.Transparency = 0.7
	cylinder(CFrame.new(pos + Vector3.new(0, 0.55, 0)), 0.4, 24, Color3.fromRGB(110, 95, 150), parent, Enum.Material.Slate)
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		local p = pos + Vector3.new(math.cos(a) * 32, 0, math.sin(a) * 32)
		if i ~= 2 then
			cylinder(CFrame.new(p + Vector3.new(0, 7, 0)), 14, 1.6, STONE, parent, Enum.Material.Cobblestone)
			part({ Size = Vector3.new(4.2, 1.2, 4.2), CFrame = CFrame.new(p + Vector3.new(0, 14.6, 0)), Color = GOLD, Material = Enum.Material.Metal }, parent)
			local torch = ball(CFrame.new(p + Vector3.new(0, 16, 0)), 1.6, Color3.fromRGB(200, 120, 255), parent, Enum.Material.Neon)
			local f = Instance.new("Fire")
			f.Size = 3
			f.Color = Color3.fromRGB(180, 90, 255)
			f.SecondaryColor = Color3.fromRGB(255, 200, 255)
			f.Parent = torch
		end
	end
	local signPart = part({ Name = "ArenaSign", Size = Vector3.new(2, 2, 2), CFrame = CFrame.new(pos + Vector3.new(0, 1, 0)), Transparency = 1, CanCollide = false }, parent)
	billboard(signPart, "ARENE DU BOSS", Config.Boss[world.id].name, Color3.fromRGB(220, 150, 255), 22)
	local marker = part({ Name = "BossArena", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(pos + Vector3.new(0, 1, 0)), Transparency = 1, CanCollide = false, CanQuery = false }, parent)
	marker:SetAttribute("World", world.id)
	CollectionService:AddTag(marker, "BossArena")
	arenas[world.id] = pos
	avoidCircle(pos, 38)
end

-- Batiments du village -------------------------------------------------------------------------------
local function shopBuilding(parent, cf)
	part({ Size = Vector3.new(22, 1, 14), CFrame = cf * CFrame.new(0, 0.5, 0), Color = STONE, Material = Enum.Material.Cobblestone }, parent)
	part({ Size = Vector3.new(20, 10, 1), CFrame = cf * CFrame.new(0, 6, 6.5), Color = Color3.fromRGB(150, 100, 60), Material = Enum.Material.WoodPlanks }, parent)
	for _, x in ipairs({ -9.5, 9.5 }) do
		part({ Size = Vector3.new(1, 10, 13), CFrame = cf * CFrame.new(x, 6, 0), Color = Color3.fromRGB(150, 100, 60), Material = Enum.Material.WoodPlanks }, parent)
		part({ Size = Vector3.new(1.4, 13, 1.4), CFrame = cf * CFrame.new(x, 6.5, -6.6), Color = Color3.fromRGB(110, 70, 40), Material = Enum.Material.Wood }, parent)
	end
	local counter = part({ Name = "ShopCounter", Size = Vector3.new(16, 3.4, 3), CFrame = cf * CFrame.new(0, 2.7, -4), Color = Color3.fromRGB(130, 85, 50), Material = Enum.Material.WoodPlanks }, parent)
	part({ Size = Vector3.new(16.6, 0.4, 3.6), CFrame = cf * CFrame.new(0, 4.6, -4), Color = GOLD, Material = Enum.Material.Metal }, parent)
	-- auvent raye turquoise et creme (comme l'icone)
	for k = 0, 9 do
		local w = wedge({ Size = Vector3.new(2.2, 2.4, 7), CFrame = cf * CFrame.new(-9.9 + k * 2.2, 12.5, -4.5) * CFrame.Angles(0, math.pi, 0), Color = (k % 2 == 0) and Color3.fromRGB(40, 170, 170) or Color3.fromRGB(250, 240, 220) }, parent)
		w.CanCollide = false
		ball(cf * CFrame.new(-9.9 + k * 2.2, 11.2, -8.1), 2.2, (k % 2 == 0) and Color3.fromRGB(40, 170, 170) or Color3.fromRGB(250, 240, 220), parent).CanCollide = false
	end
	local emblem = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 6, 6), CFrame = cf * CFrame.new(0, 15.5, -1) * CFrame.Angles(0, math.rad(90), 0), Color = GOLD, Material = Enum.Material.Metal }, parent)
	-- marchandises : pieces et cristaux
	for k = 1, 8 do
		ball(cf * CFrame.new(R(-6, 6), 5.1, R(-4.8, -3.2)), 0.9, GOLD, parent, Enum.Material.Metal)
	end
	for _, x in ipairs({ -4, 4 }) do
		part({ Size = Vector3.new(0.9, 1.8, 0.9), CFrame = cf * CFrame.new(x, 5.6, -4) * CFrame.Angles(0, math.rad(45), math.rad(10)), Color = Color3.fromRGB(150, 100, 255), Material = Enum.Material.Neon }, parent)
	end
	for _, x in ipairs({ -10.5, 10.5 }) do
		local lamp = part({ Size = Vector3.new(1, 1.4, 1), CFrame = cf * CFrame.new(x, 9, -7.4), Color = Color3.fromRGB(255, 210, 140), Material = Enum.Material.Neon }, parent)
		local l = Instance.new("PointLight")
		l.Range = 14
		l.Color = Color3.fromRGB(255, 200, 130)
		l.Parent = lamp
	end
	local banner = part({ Size = Vector3.new(3, 5, 0.2), CFrame = cf * CFrame.new(11.5, 7, -7.6), Color = Color3.fromRGB(200, 50, 60), Material = Enum.Material.Fabric }, parent)
	billboard(counter, "BOUTIQUE", "Potions et avantages", GOLD, 14)
	prompt(counter, "Ouvrir", "Boutique", "Shop")
	avoidCircle(cf.Position, 16)
end

local function forge(parent, cf)
	part({ Size = Vector3.new(16, 1, 14), CFrame = cf * CFrame.new(0, 0.5, 0), Color = STONE, Material = Enum.Material.Cobblestone }, parent)
	local anvil = part({ Name = "Anvil", Size = Vector3.new(6, 2.4, 2.8), CFrame = cf * CFrame.new(0, 4.8, 0), Color = Color3.fromRGB(110, 110, 120), Material = Enum.Material.Metal }, parent)
	part({ Size = Vector3.new(3, 3, 2.2), CFrame = cf * CFrame.new(0, 2.5, 0), Color = Color3.fromRGB(95, 95, 105), Material = Enum.Material.Metal }, parent)
	part({ Size = Vector3.new(5, 1, 3.6), CFrame = cf * CFrame.new(0, 1.3, 0), Color = Color3.fromRGB(85, 85, 95), Material = Enum.Material.Metal }, parent)
	wedge({ Size = Vector3.new(2.8, 1.4, 2.4), CFrame = cf * CFrame.new(-4.2, 5.3, 0) * CFrame.Angles(0, math.rad(-90), 0), Color = Color3.fromRGB(110, 110, 120), Material = Enum.Material.Metal }, parent)
	part({ Size = Vector3.new(1.4, 0.3, 1.4), CFrame = cf * CFrame.new(0.5, 6.1, 0), Color = GOLD, Material = Enum.Material.Neon }, parent)
	-- marteau pose
	part({ Size = Vector3.new(0.4, 0.4, 4), CFrame = cf * CFrame.new(1.8, 6.3, 0.6) * CFrame.Angles(0, math.rad(30), 0), Color = Color3.fromRGB(120, 80, 45), Material = Enum.Material.Wood }, parent)
	part({ Size = Vector3.new(1.4, 1, 1), CFrame = cf * CFrame.new(2.6, 6.4, -0.8) * CFrame.Angles(0, math.rad(30), 0), Color = Color3.fromRGB(90, 90, 100), Material = Enum.Material.Metal }, parent)
	-- foyer
	local fire = part({ Size = Vector3.new(4, 2, 4), CFrame = cf * CFrame.new(0, 1.5, 5), Color = Color3.fromRGB(80, 70, 70), Material = Enum.Material.Brick }, parent)
	local f = Instance.new("Fire")
	f.Size = 5
	f.Heat = 9
	f.Parent = fire
	local l = Instance.new("PointLight")
	l.Color = Color3.fromRGB(255, 160, 70)
	l.Range = 20
	l.Brightness = 2
	l.Parent = fire
	local arrow = part({ Size = Vector3.new(1.2, 4, 0.4), CFrame = cf * CFrame.new(0, 12, 0), Color = GOLD, Material = Enum.Material.Neon, CanCollide = false }, parent)
	TweenService:Create(arrow, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { CFrame = arrow.CFrame + Vector3.new(0, 1.5, 0) }):Play()
	billboard(anvil, "FORGE", "Ameliorations", GOLD, 9)
	prompt(anvil, "Ameliorer", "Forge", "Upgrades")
	avoidCircle(cf.Position, 12)
end

local function rebirthAltar(parent, cf)
	cylinder(cf * CFrame.new(0, 0.6, 0), 1.2, 10, STONE, parent, Enum.Material.Cobblestone)
	local n = 16
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		part({ Size = Vector3.new(2.6, 2.6, 2.4), CFrame = cf * CFrame.new(math.cos(a) * 7, 8.5 + math.sin(a) * 7, 0) * CFrame.Angles(0, 0, a), Color = (i % 4 == 0) and GOLD or Color3.fromRGB(110, 100, 130), Material = Enum.Material.Cobblestone }, parent)
	end
	local disk = part({ Name = "RebirthDisk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 12, 12), CFrame = cf * CFrame.new(0, 8.5, 0) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(170, 70, 255), Material = Enum.Material.Neon, Transparency = 0.25, CanCollide = false }, parent)
	TweenService:Create(disk, TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { CFrame = disk.CFrame * CFrame.Angles(math.rad(-359), 0, 0) }):Play()
	for _, x in ipairs({ -6, 6 }) do
		part({ Size = Vector3.new(1.4, 3, 1.4), CFrame = cf * CFrame.new(x, 2, -2) * CFrame.Angles(0, math.rad(45), math.rad(15)), Color = Color3.fromRGB(110, 200, 255), Material = Enum.Material.Neon }, parent)
	end
	billboard(disk, "RENAISSANCE", "Bonus permanents", Color3.fromRGB(220, 160, 255), 10)
	prompt(disk, "Renaitre", "Autel", "Rebirth")
	avoidCircle(cf.Position, 12)
end

local function questBoard(parent, cf)
	for _, x in ipairs({ -4, 4 }) do
		part({ Size = Vector3.new(0.8, 9, 0.8), CFrame = cf * CFrame.new(x, 4.5, 0), Color = Color3.fromRGB(110, 70, 40), Material = Enum.Material.Wood }, parent)
	end
	local board = part({ Name = "QuestBoard", Size = Vector3.new(8, 5, 0.5), CFrame = cf * CFrame.new(0, 5.5, 0), Color = Color3.fromRGB(160, 110, 65), Material = Enum.Material.WoodPlanks }, parent)
	for i = 0, 2 do
		part({ Size = Vector3.new(2, 2.6, 0.1), CFrame = cf * CFrame.new(-2.6 + i * 2.6, 5.5, -0.3) * CFrame.Angles(0, 0, math.rad(R(-6, 6))), Color = Color3.fromRGB(245, 230, 195), Material = Enum.Material.SmoothPlastic }, parent)
	end
	wedge({ Size = Vector3.new(9.5, 1.5, 1.2), CFrame = cf * CFrame.new(0, 8.8, 0), Color = Color3.fromRGB(180, 60, 50) }, parent)
	billboard(board, "QUETES", "Missions du jour", GOLD, 6)
	prompt(board, "Lire", "Tableau des quetes", "Quests")
	avoidCircle(cf.Position, 7)
end

local function fountain(parent, c)
	cylinder(CFrame.new(c + Vector3.new(0, 1, 0)), 2, 12, Color3.fromRGB(235, 232, 245), parent, Enum.Material.Marble)
	local w = cylinder(CFrame.new(c + Vector3.new(0, 1.8, 0)), 0.6, 11, Kit.WATER, parent, Enum.Material.Glass)
	w.Transparency = 0.25
	w.CanCollide = false
	cylinder(CFrame.new(c + Vector3.new(0, 5, 0)), 6, 2, Color3.fromRGB(235, 232, 245), parent, Enum.Material.Marble)
	cylinder(CFrame.new(c + Vector3.new(0, 8.3, 0)), 0.8, 6, GOLD, parent, Enum.Material.Metal)
	-- grande relique doree tournant au sommet
	local idol = RelicModel.Build("IdoleOr")
	idol:ScaleTo(2.6)
	idol:PivotTo(CFrame.new(c + Vector3.new(0, 13.5, 0)))
	idol.Parent = parent
	for _, d in ipairs(idol:GetDescendants()) do
		if d:IsA("BasePart") then
			local off = CFrame.new(c + Vector3.new(0, 13.5, 0)):ToObjectSpace(d.CFrame)
			local v = Instance.new("CFrameValue")
			v.Value = CFrame.new()
			v.Changed:Connect(function(val)
				d.CFrame = CFrame.new(c + Vector3.new(0, 13.5, 0)) * val * off
			end)
			TweenService:Create(v, TweenInfo.new(10, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Value = CFrame.Angles(0, math.rad(359), 0) }):Play()
			v.Parent = d
		end
	end
	local jet = part({ Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(c + Vector3.new(0, 9, 0)), Transparency = 1, CanCollide = false }, parent)
	local spray = Instance.new("ParticleEmitter")
	spray.Rate = 50
	spray.Lifetime = NumberRange.new(1, 1.3)
	spray.Speed = NumberRange.new(10, 14)
	spray.SpreadAngle = Vector2.new(30, 30)
	spray.Acceleration = Vector3.new(0, -35, 0)
	spray.Size = NumberSequence.new(0.5, 0.9)
	spray.Transparency = NumberSequence.new(0.2, 1)
	spray.Color = ColorSequence.new(Color3.fromRGB(200, 235, 255))
	spray.Parent = jet
	avoidCircle(c, 15)
end

-- Grotte aux tresors (village) : dome de rochers avec entree, cristaux lumineux a l'interieur
local function treasureCave(parent, c, facing)
	local rock = Color3.fromRGB(120, 110, 130)
	local R0 = 30
	local cf = CFrame.lookAt(c, c + facing)
	for i = 0, 27 do
		local a = i / 28 * math.pi * 2
		local local_ = Vector3.new(math.cos(a), 0, math.sin(a))
		local lp = cf:VectorToObjectSpace(local_)
		if not (lp.Z < -0.8) then -- ouverture face a l'entree
			local p = c + local_ * R0
			part({ Size = Vector3.new(9, R(16, 22), 9), CFrame = CFrame.new(p + Vector3.new(0, 9, 0)) * CFrame.Angles(R(-0.2, 0.2), R(0, 3), R(-0.2, 0.2)), Color = rock:Lerp(Color3.new(0, 0, 0), R(0, 0.15)), Material = Enum.Material.Slate }, parent)
		end
	end
	-- toit
	for i = 1, 9 do
		local a = R(0, math.pi * 2)
		local r = R(0, R0 * 0.7)
		local b = ball(CFrame.new(c + Vector3.new(math.cos(a) * r, 22 + R(0, 4), math.sin(a) * r)), R(18, 26), rock, parent, Enum.Material.Slate)
		b.CanCollide = true
	end
	-- arche d'entree
	local entrance = (cf * CFrame.new(0, 0, -R0)).Position
	for _, x in ipairs({ -7, 7 }) do
		part({ Size = Vector3.new(4, 16, 5), CFrame = CFrame.lookAt(entrance, entrance + facing) * CFrame.new(x, 8, 0), Color = rock, Material = Enum.Material.Slate }, parent)
	end
	part({ Size = Vector3.new(18, 4, 5), CFrame = CFrame.lookAt(entrance, entrance + facing) * CFrame.new(0, 16, 0), Color = rock, Material = Enum.Material.Slate }, parent)
	billboard(part({ Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(entrance + Vector3.new(0, 18, 0)), Transparency = 1, CanCollide = false }, parent), "GROTTE AUX TRESORS", "Gros butin a l'interieur !", Color3.fromRGB(150, 220, 255), 3)
	-- cristaux lumineux
	local cols = { Color3.fromRGB(90, 200, 255), Color3.fromRGB(180, 100, 255), Color3.fromRGB(255, 120, 220) }
	for i = 1, 16 do
		local a = R(0, math.pi * 2)
		local r = R(R0 - 7, R0 - 3)
		local p = c + Vector3.new(math.cos(a) * r, R(0, 8), math.sin(a) * r)
		local col = cols[rng:NextInteger(1, 3)]
		for k = 1, 3 do
			local h = R(3, 7)
			part({ Size = Vector3.new(1.4, h, 1.4), CFrame = CFrame.new(p) * CFrame.Angles(R(-0.5, 0.5), R(0, 6), R(-0.5, 0.5)) * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, math.rad(45), 0), Color = col, Material = Enum.Material.Neon, Transparency = 0.15, CanCollide = false }, parent)
		end
		if i % 3 == 0 then
			local l = Instance.new("PointLight")
			l.Color = col
			l.Range = 22
			l.Brightness = 1.8
			l.Parent = parent:GetChildren()[#parent:GetChildren()]
		end
	end
	-- emplacements de tresors interieurs (plus riches)
	local inside = {}
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		table.insert(inside, c + Vector3.new(math.cos(a) * 14, 0, math.sin(a) * 14))
	end
	table.insert(inside, c)
	avoidCircle(c, R0 + 6)
	return inside
end

-- Starter Village ------------------------------------------------------------------------------------
local function buildVillage(folder, world)
	local c = world.center
	local pal = PALETTES.Village
	-- reservations
	plaza(folder, c, 34, Color3.fromRGB(240, 228, 195))
	fountain(folder, c)
	path(folder, c + Vector3.new(0, 0, 34), c + Vector3.new(0, 0, 165), 14, pal.path) -- vers la plage
	path(folder, c + Vector3.new(34, 0, 0), c + Vector3.new(150, 0, 0), 12, pal.path) -- vers le portail
	path(folder, c + Vector3.new(-34, 0, 0), c + Vector3.new(-100, 0, 40), 12, pal.path) -- vers l'arene
	path(folder, c + Vector3.new(24, 0, -24), c + Vector3.new(95, 0, -85), 10, pal.path) -- vers la grotte
	path(folder, c + Vector3.new(-24, 0, -24), c + Vector3.new(-90, 0, -90), 10, pal.path) -- vers la foret
	crateStand(folder, c + Vector3.new(0, 0, -52), world, Vector3.new(0, 0, 1))
	shopBuilding(folder, CFrame.lookAt(c + Vector3.new(56, 0, 26), c + Vector3.new(0, 0, 26)))
	forge(folder, CFrame.lookAt(c + Vector3.new(52, 0, -32), c))
	rebirthAltar(folder, CFrame.lookAt(c + Vector3.new(-52, 0, -32), c))
	questBoard(folder, CFrame.lookAt(c + Vector3.new(-40, 0, 26), c))
	portal(folder, c + Vector3.new(152, 0, 0), Vector3.new(-1, 0, 0), Config.Worlds[2])
	arena(folder, c + Vector3.new(-110, 0, 60), world)
	local caveSpots = treasureCave(folder, c + Vector3.new(105, 0, -100), Vector3.new(-1, 0, 1))
	-- lampadaires et bancs autour de la place
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2 + 0.3
		Kit.lantern(folder, c + Vector3.new(math.cos(a) * 38, 0, math.sin(a) * 38), Color3.fromRGB(255, 200, 140))
	end
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		Kit.bench(folder, CFrame.lookAt(c + Vector3.new(math.cos(a) * 25, 0, math.sin(a) * 25), c))
		Kit.flowerBed(folder, c + Vector3.new(math.cos(a) * 30, 0, math.sin(a) * 30), 3.5)
	end
	-- plage (sud)
	local beach = part({ Name = "Sand", Size = Vector3.new(world.size - 2, 0.3, 70), CFrame = CFrame.new(c + Vector3.new(0, 0.05, world.size / 2 - 36)), Color = Color3.fromRGB(250, 225, 160), CanCollide = false }, folder)
	local sea = part({ Size = Vector3.new(world.size - 2, 0.3, 22), CFrame = CFrame.new(c + Vector3.new(0, 0.12, world.size / 2 - 12)), Color = Color3.fromRGB(70, 200, 230), Material = Enum.Material.Glass, Transparency = 0.15, Reflectance = 0.2, CanCollide = false }, folder)
	Kit.avoidSegment(c + Vector3.new(-170, 0, 160), c + Vector3.new(170, 0, 160), 14)
	for i = 0, 3 do
		local x = -110 + i * 70
		if math.abs(x) > 20 then
			local p = c + Vector3.new(x, 0, 120)
			cylinder(CFrame.new(p + Vector3.new(0, 4, 0)), 8, 0.25, WHITE, folder)
			for k = 0, 7 do
				part({ Size = Vector3.new(3.4, 0.3, 4.4), CFrame = CFrame.new(p + Vector3.new(0, 8, 0)) * CFrame.Angles(0, k * math.pi / 4, 0) * CFrame.new(0, -0.6, -2) * CFrame.Angles(math.rad(-20), 0, 0), Color = (k % 2 == 0) and Color3.fromRGB(40, 170, 170) or WHITE, CanCollide = false }, folder)
			end
			avoidCircle(p, 6)
		end
	end
	Kit.scatter({ center = c + Vector3.new(0, 0, 125), size = 60 }, 9, 0, 200, function(pos)
		if math.abs(pos.X - c.X) > 14 then
			Kit.palmTree(folder, pos, R(1, 1.4))
			avoidCircle(pos, 4)
		end
	end, 3)
	-- foret (nord-ouest) : zone dense
	Kit.scatter({ center = c + Vector3.new(-105, 0, -95), size = 120 }, 38, 0, 200, function(pos)
		if rng:NextNumber() < 0.55 then
			Kit.pineTree(folder, pos, R(1, 1.7))
		else
			Kit.roundTree(folder, pos, R(0.9, 1.4))
		end
		avoidCircle(pos, 4.5)
	end, 3)
	Kit.scatter({ center = c + Vector3.new(-105, 0, -95), size = 120 }, 16, 0, 200, function(pos)
		Kit.mushroom(folder, pos, R(0.7, 1.4))
	end, 1)
	-- decor general
	Kit.scatter(world, 30, 40, 250, function(pos)
		Kit.roundTree(folder, pos, R(0.8, 1.2))
		avoidCircle(pos, 4.5)
	end, 4)
	Kit.scatter(world, 40, 20, 250, function(pos)
		if rng:NextNumber() < 0.5 then
			Kit.bush(folder, pos, R(0.8, 1.2), Color3.fromRGB(255, 130, 180))
		else
			Kit.flowerPatch(folder, pos)
		end
	end, 1)
	return caveSpots
end

-- Autres mondes --------------------------------------------------------------------------------------
local function buildOther(folder, world)
	local c = world.center
	local pal = PALETTES[world.id]
	plaza(folder, c, 26, pal.path)
	path(folder, c + Vector3.new(-26, 0, 0), c + Vector3.new(-150, 0, 0), 12, pal.path)
	path(folder, c + Vector3.new(0, 0, 26), c + Vector3.new(0, 0, 70), 12, pal.path)
	crateStand(folder, c + Vector3.new(0, 0, -44), world, Vector3.new(0, 0, 1))
	portal(folder, c + Vector3.new(-152, 0, 0), Vector3.new(1, 0, 0), Config.Worlds[1])
	local nextW = Config.Worlds[world.index + 1]
	if nextW then
		path(folder, c + Vector3.new(26, 0, 0), c + Vector3.new(150, 0, 0), 12, pal.path)
		portal(folder, c + Vector3.new(152, 0, 0), Vector3.new(-1, 0, 0), nextW)
	end
	arena(folder, c + Vector3.new(0, 0, 105), world)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2 + 0.39
		Kit.lantern(folder, c + Vector3.new(math.cos(a) * 30, 0, math.sin(a) * 30), world.color:Lerp(WHITE, 0.4))
	end
	local builder = MapZones[world.id]
	if builder then
		local ok, err = pcall(builder, folder, { center = c, size = world.size, id = world.id })
		if not ok then
			warn("[RelicRush] Decor de " .. world.id .. " : " .. tostring(err))
		end
	end
end

local function computeSpots(world, extra)
	local list = {}
	for _, p in ipairs(extra or {}) do
		table.insert(list, p + Vector3.new(0, 0, 0))
	end
	local half = world.size / 2
	local tries = 0
	while #list < Config.TreasurePerWorld + 10 and tries < 4000 do
		tries += 1
		local p = world.center + Vector3.new(R(-half + 18, half - 18), 0, R(-half + 18, half - 18))
		if Kit.isFree(p, 3) then
			table.insert(list, p)
			avoidCircle(p, 7)
		end
	end
	spots[world.id] = list
end

function WorldBuilder.Build()
	for _, n in ipairs({ "RelicRushWorld", "Baseplate" }) do
		local o = workspace:FindFirstChild(n)
		if o then
			o:Destroy()
		end
	end
	for _, s in ipairs(workspace:GetDescendants()) do
		if s:IsA("SpawnLocation") then
			s:Destroy()
		end
	end
	lighting()
	local root = Instance.new("Folder")
	root.Name = "RelicRushWorld"
	root.Parent = workspace
	for _, w in ipairs(Config.Worlds) do
		local folder = Instance.new("Folder")
		folder.Name = w.id
		folder.Parent = root
		island(folder, w)
		spawns[w.id] = CFrame.new(w.center + (w.id == "Village" and Config.SpawnOffset or Vector3.new(-120, 4, 0)))
		local extra
		local ok, err = pcall(function()
			if w.id == "Village" then
				extra = buildVillage(folder, w)
			else
				buildOther(folder, w)
			end
		end)
		if not ok then
			warn("[RelicRush] Monde " .. w.id .. " : " .. tostring(err))
		end
		computeSpots(w, extra)
		-- nuages et mer autour de l'ile
		part({ Name = "Sea", Size = Vector3.new(1100, 2, 1100), CFrame = CFrame.new(w.center + Vector3.new(0, -150, 0)), Color = Color3.fromRGB(80, 150, 240), CanCollide = false, CanQuery = false }, folder)
		for k = 1, 14 do
			local a = R(0, math.pi * 2)
			Kit.cloudPuff(folder, w.center + Vector3.new(math.cos(a) * R(220, 420), R(-60, 60), math.sin(a) * R(220, 420)), R(1, 2))
		end
		task.wait()
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "MainSpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = spawns.Village - Vector3.new(0, 3.5, 0)
	spawn.Anchored = true
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = root
	Players.RespawnTime = 2
end

function WorldBuilder.Spots(worldId)
	return spots[worldId] or {}
end

function WorldBuilder.Spawn(worldId)
	return spawns[worldId]
end

function WorldBuilder.Crate(worldId)
	return crates[worldId]
end

function WorldBuilder.Arena(worldId)
	return arenas[worldId]
end

function WorldBuilder.WorldAt(position)
	for _, w in ipairs(Config.Worlds) do
		local half = w.size / 2 + 40
		if math.abs(position.X - w.center.X) <= half and math.abs(position.Z - w.center.Z) <= half then
			return w
		end
	end
	return nil
end

return WorldBuilder
