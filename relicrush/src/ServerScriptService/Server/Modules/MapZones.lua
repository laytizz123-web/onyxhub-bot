-- Decor propre a chaque zone (hors Starter Village, construit par MapBuilder).
-- Chaque zone a son style : couleurs, vegetation, batiments, effets d'ambiance.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Kit = require(script.Parent.MapKit)

local part, wedge, ball, cylinder, sign = Kit.part, Kit.wedge, Kit.ball, Kit.cylinder, Kit.sign
local R, rng = Kit.R, Kit.rng
local avoidCircle = Kit.avoidCircle
local WHITE = Color3.new(1, 1, 1)

local MapZones = {}
MapZones.Forest = nil -- defini plus bas (alias de Foret)

local function sphereMesh(p, scale)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Scale = scale
	m.Parent = p
	return p
end

local function cone(parent, pos, height, radius, color, material)
	-- cone en anneaux empiles (toits de tours, sapins, cornets)
	local n = 6
	for i = 0, n - 1 do
		local r = radius * (1 - i / n)
		local c = cylinder(CFrame.new(pos + Vector3.new(0, (i + 0.5) * height / n, 0)), height / n + 0.05, r, color, parent, material)
		c.CanCollide = i == 0
	end
	ball(CFrame.new(pos + Vector3.new(0, height, 0)), radius * 0.35, color, parent, material)
end

local function ambient(folder, zone, props)
	-- particules d'ambiance sur toute la zone
	local box = part({ Size = Vector3.new(zone.size, props.height or 14, zone.size), CFrame = CFrame.new(zone.center + Vector3.new(0, (props.height or 14) / 2 + (props.y or 1), 0)), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false }, folder)
	local e = Instance.new("ParticleEmitter")
	e.Rate = props.rate or 30
	e.Lifetime = props.life or NumberRange.new(4, 7)
	e.Speed = props.speed or NumberRange.new(0.5, 1.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = props.size or NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.35), NumberSequenceKeypoint.new(1, 0) })
	e.LightEmission = props.light or 1
	e.Color = ColorSequence.new(props.color)
	e.Acceleration = props.accel or Vector3.zero
	e.EmissionDirection = props.dir or Enum.NormalId.Top
	e.Transparency = props.transparency or NumberSequence.new(0)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Parent = box
end

local function bob(p, height, time)
	TweenService:Create(p, TweenInfo.new(time or R(2.5, 4), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { CFrame = p.CFrame + Vector3.new(0, height, 0) }):Play()
end

local function spin(p, time)
	TweenService:Create(p, TweenInfo.new(time, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { CFrame = p.CFrame * CFrame.Angles(0, math.rad(-359), 0) }):Play()
end

-- FORET ----------------------------------------------------------------------------------------

local function bigOak(parent, pos, scale)
	if Kit.TryDecor("GrandArbre", parent, pos, { height = 21 * (scale or 1) }) then
		return
	end
	cylinder(CFrame.new(pos + Vector3.new(0, 6 * scale, 0)), 12 * scale, 1.8 * scale, Color3.fromRGB(110, 72, 42), parent, Enum.Material.Wood)
	for k = 1, 3 do
		local a = k * 2.1
		part({ Size = Vector3.new(1.2, 5, 1.2) * scale, CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 2 * scale, 1.5 * scale, math.sin(a) * 2 * scale)) * CFrame.Angles(math.sin(a) * 0.7, 0, -math.cos(a) * 0.7), Color = Color3.fromRGB(110, 72, 42), Material = Enum.Material.Wood }, parent)
	end
	local top = pos + Vector3.new(0, 14 * scale, 0)
	ball(CFrame.new(top), 14 * scale, Color3.fromRGB(70, 165, 65), parent, Enum.Material.Grass)
	for k = 1, 6 do
		local a = k * 1.05
		ball(CFrame.new(top + Vector3.new(math.cos(a) * 5.5 * scale, R(-2, 2.5) * scale, math.sin(a) * 5.5 * scale)), R(7, 10) * scale, Kit.LEAF_COLORS[rng:NextInteger(1, 3)], parent, Enum.Material.Grass)
	end
	avoidCircle(pos, 8 * scale)
end

local function cabin(parent, cf)
	if Kit.TryDecor("Chalet", parent, cf.Position, { height = 14, cf = cf }) then
		return
	end
	local logC = Color3.fromRGB(150, 98, 58)
	for i = 0, 6 do
		for _, z in ipairs({ -5, 5 }) do
			part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(14, 1.3, 1.3), CFrame = cf * CFrame.new(0, 0.65 + i * 1.2, z), Color = (i % 2 == 0) and logC or logC:Lerp(Color3.new(0, 0, 0), 0.12), Material = Enum.Material.Wood }, parent)
		end
		for _, x in ipairs({ -6.4, 6.4 }) do
			part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(11, 1.3, 1.3), CFrame = cf * CFrame.new(x, 1.25 + i * 1.2, 0) * CFrame.Angles(0, math.rad(90), 0), Color = logC, Material = Enum.Material.Wood }, parent)
		end
	end
	part({ Size = Vector3.new(12, 8, 9), CFrame = cf * CFrame.new(0, 4, 0), Color = Color3.fromRGB(210, 170, 120) }, parent)
	for _, s in ipairs({ -1, 1 }) do
		wedge({ Size = Vector3.new(16, 5, 7), CFrame = cf * CFrame.new(0, 10.8, s * 3.5) * CFrame.Angles(0, s > 0 and math.pi or 0, 0), Color = Color3.fromRGB(90, 140, 70) }, parent)
	end
	part({ Size = Vector3.new(3, 5, 0.4), CFrame = cf * CFrame.new(0, 2.5, -5.8), Color = Color3.fromRGB(110, 70, 40), Material = Enum.Material.WoodPlanks }, parent)
	part({ Size = Vector3.new(2.5, 2.5, 0.3), CFrame = cf * CFrame.new(-4, 4.5, -5.8), Color = Color3.fromRGB(255, 220, 140), Material = Enum.Material.Neon }, parent)
	avoidCircle(cf.Position, 12)
end

local function campfire(parent, pos)
	for k = 1, 8 do
		local a = k / 8 * math.pi * 2
		Kit.rock(parent, pos + Vector3.new(math.cos(a) * 2.6, -0.4, math.sin(a) * 2.6), 0.4, Color3.fromRGB(130, 130, 140))
	end
	for k = 1, 3 do
		part({ Size = Vector3.new(0.7, 0.7, 4), CFrame = CFrame.new(pos + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, k * 1.05, math.rad(10)), Color = Color3.fromRGB(110, 70, 40), Material = Enum.Material.Wood }, parent)
	end
	local fireBase = part({ Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(pos + Vector3.new(0, 1, 0)), Transparency = 1, CanCollide = false }, parent)
	local fire = Instance.new("Fire")
	fire.Size = 5
	fire.Heat = 8
	fire.Parent = fireBase
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 160, 70)
	light.Range = 20
	light.Brightness = 2
	light.Parent = fireBase
	for k = 1, 3 do
		local a = k * 2.1 + 0.5
		part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, 1.4, 1.4), CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 6, 0.7, math.sin(a) * 6)) * CFrame.Angles(0, -a + math.pi / 2, 0), Color = Color3.fromRGB(130, 85, 50), Material = Enum.Material.Wood }, parent)
	end
	avoidCircle(pos, 9)
end

local function tent(parent, cf, color)
	if Kit.TryDecor("Tente", parent, cf.Position, { height = 6, cf = cf }) then
		return
	end
	for _, s in ipairs({ -1, 1 }) do
		wedge({ Size = Vector3.new(7, 6, 4), CFrame = cf * CFrame.new(0, 3, s * 2) * CFrame.Angles(0, s > 0 and math.pi or 0, 0), Color = color }, parent)
	end
	part({ Size = Vector3.new(2, 4, 0.2), CFrame = cf * CFrame.new(0, 2, -3.6), Color = color:Lerp(Color3.new(0, 0, 0), 0.4) }, parent)
	avoidCircle(cf.Position, 6)
end

local function treehouse(parent, pos)
	bigOak(parent, pos, 1.3)
	local deck = pos + Vector3.new(0, 11, 0)
	cylinder(CFrame.new(deck), 1, 8, Color3.fromRGB(170, 115, 70), parent, Enum.Material.WoodPlanks)
	part({ Size = Vector3.new(7, 5, 7), CFrame = CFrame.new(deck + Vector3.new(0, 3, 0)), Color = Color3.fromRGB(200, 140, 85), Material = Enum.Material.WoodPlanks }, parent)
	for _, s in ipairs({ -1, 1 }) do
		wedge({ Size = Vector3.new(9, 3, 4.5), CFrame = CFrame.new(deck + Vector3.new(0, 7, s * 2.25)) * CFrame.Angles(0, s > 0 and math.pi or 0, 0), Color = Color3.fromRGB(220, 75, 65) }, parent)
	end
	for y = 1, 10 do
		part({ Size = Vector3.new(2.4, 0.3, 0.3), CFrame = CFrame.new(pos + Vector3.new(0, y, -9)), Color = Color3.fromRGB(140, 95, 55) }, parent)
	end
	for _, x in ipairs({ -1.2, 1.2 }) do
		part({ Size = Vector3.new(0.3, 11, 0.3), CFrame = CFrame.new(pos + Vector3.new(x, 5.5, -9)), Color = Color3.fromRGB(140, 95, 55) }, parent)
	end
end

function MapZones.Foret(folder, zone)
	local c = zone.center
	treehouse(folder, c + Vector3.new(95, 0, 70))
	cabin(folder, CFrame.new(c + Vector3.new(-100, 0, 80)) * CFrame.Angles(0, math.rad(40), 0))
	campfire(folder, c + Vector3.new(-70, 0, -40))
	for k, col in ipairs({ Color3.fromRGB(240, 120, 60), Color3.fromRGB(80, 160, 230), Color3.fromRGB(240, 200, 70) }) do
		local a = k * 2.1
		tent(folder, CFrame.lookAt(c + Vector3.new(-70 + math.cos(a) * 15, 0, -40 + math.sin(a) * 15), c + Vector3.new(-70, 0, -40)), col)
	end
	Kit.river(folder, c + Vector3.new(60, 0, -150), c + Vector3.new(120, 0, 150), 12, Color3.fromRGB(150, 120, 80))
	for k = 1, 5 do
		Kit.bench(folder, CFrame.new(c + Vector3.new(R(-110, -30), 0, R(-120, 120))) * CFrame.Angles(0, R(0, 6.28), 0))
	end
	Kit.scatter(zone, 12, 30, 200, function(pos)
		bigOak(folder, pos, R(0.8, 1.15))
	end, 6)
	Kit.scatter(zone, 70, 15, 200, function(pos)
		if rng:NextNumber() < 0.7 then
			Kit.pineTree(folder, pos, R(0.9, 1.7))
		else
			Kit.roundTree(folder, pos, R(0.9, 1.3))
		end
		avoidCircle(pos, 4.5)
	end, 3)
	Kit.scatter(zone, 40, 10, 200, function(pos)
		Kit.mushroom(folder, pos, R(0.6, 1.5))
	end)
	Kit.scatter(zone, 30, 10, 200, function(pos)
		Kit.bush(folder, pos, R(0.8, 1.3), rng:NextNumber() < 0.5 and Color3.fromRGB(150, 140, 255) or nil)
	end)
	Kit.scatter(zone, 18, 20, 200, function(pos)
		Kit.rock(folder, pos, R(0.8, 2), Color3.fromRGB(120, 125, 135))
	end)
	Kit.scatter(zone, 8, 30, 200, function(pos)
		part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(R(6, 9), 2.2, 2.2), CFrame = CFrame.new(pos + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, R(0, 6.28), 0), Color = Color3.fromRGB(120, 80, 45), Material = Enum.Material.Wood }, folder)
		avoidCircle(pos, 5)
	end)
	ambient(folder, zone, { color = Color3.fromRGB(230, 255, 130), rate = 45 })
end

-- DESERT ---------------------------------------------------------------------------------------

local function pyramid(parent, pos, size)
	if Kit.TryDecor("Pyramide", parent, pos, { height = size }) then
		return
	end
	local steps = 7
	for s = 0, steps - 1 do
		local w = size * (1 - s / steps)
		part({ Size = Vector3.new(w, size / steps, w), CFrame = CFrame.new(pos + Vector3.new(0, (s + 0.5) * size / steps, 0)), Color = Color3.fromRGB(225, 185, 115):Lerp(Color3.fromRGB(245, 215, 150), s / steps) }, parent)
	end
	ball(CFrame.new(pos + Vector3.new(0, size + 1, 0)), 3, Config.Colors.Gold, parent, Enum.Material.Neon)
	part({ Size = Vector3.new(5, 7, 1), CFrame = CFrame.new(pos + Vector3.new(0, 3.5, -size / 2 - 0.2)), Color = Color3.fromRGB(90, 60, 40) }, parent)
	avoidCircle(pos, size * 0.75 + 4)
end

local function cactus(parent, pos)
	if Kit.TryDecor("Cactus", parent, pos, { height = 9 }) then
		return
	end
	local h = R(5, 9)
	local g = Color3.fromRGB(80, 175, 90)
	cylinder(CFrame.new(pos + Vector3.new(0, h / 2, 0)), h, 1, g, parent)
	ball(CFrame.new(pos + Vector3.new(0, h, 0)), 2, g, parent)
	for _, side in ipairs({ -1, 1 }) do
		local ah = R(2, 3.5)
		part({ Size = Vector3.new(2.2, 1.4, 1.4), CFrame = CFrame.new(pos + Vector3.new(side * 1.3, h * 0.45, 0)), Color = g }, parent)
		cylinder(CFrame.new(pos + Vector3.new(side * 2.2, h * 0.45 + ah / 2, 0)), ah, 0.7, g, parent)
		ball(CFrame.new(pos + Vector3.new(side * 2.2, h * 0.45 + ah, 0)), 1.4, g, parent)
	end
	ball(CFrame.new(pos + Vector3.new(0, h + 1, 0)), 0.9, Color3.fromRGB(255, 120, 170), parent)
	avoidCircle(pos, 4)
end

local function obelisk(parent, pos)
	if Kit.TryDecor("Obelisque", parent, pos, { height = 20 }) then
		return
	end
	part({ Size = Vector3.new(5, 1.5, 5), CFrame = CFrame.new(pos + Vector3.new(0, 0.75, 0)), Color = Color3.fromRGB(210, 170, 110) }, parent)
	part({ Size = Vector3.new(3, 16, 3), CFrame = CFrame.new(pos + Vector3.new(0, 9.5, 0)), Color = Color3.fromRGB(235, 200, 135) }, parent)
	wedge({ Size = Vector3.new(3, 2.5, 1.5), CFrame = CFrame.new(pos + Vector3.new(0, 18.75, -0.75)), Color = Config.Colors.Gold }, parent)
	wedge({ Size = Vector3.new(3, 2.5, 1.5), CFrame = CFrame.new(pos + Vector3.new(0, 18.75, 0.75)) * CFrame.Angles(0, math.pi, 0), Color = Config.Colors.Gold }, parent)
	for y = 4, 14, 3 do
		part({ Size = Vector3.new(1.2, 1.2, 0.2), CFrame = CFrame.new(pos + Vector3.new(0, y, -1.55)), Color = Color3.fromRGB(40, 90, 190) }, parent)
	end
	avoidCircle(pos, 4)
end

local function ruins(parent, pos)
	for k = 1, 6 do
		local a = k / 6 * math.pi * 2
		local h = (k % 3 == 0) and 3 or R(6, 12)
		local p = pos + Vector3.new(math.cos(a) * 9, 0, math.sin(a) * 9)
		cylinder(CFrame.new(p + Vector3.new(0, h / 2, 0)), h, 1.3, Color3.fromRGB(240, 220, 175), parent)
		part({ Size = Vector3.new(3.4, 0.8, 3.4), CFrame = CFrame.new(p + Vector3.new(0, h + 0.4, 0)), Color = Color3.fromRGB(225, 200, 150) }, parent)
	end
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(7, 2.4, 2.4), CFrame = CFrame.new(pos + Vector3.new(2, 1.2, 3)) * CFrame.Angles(0, 0.6, 0), Color = Color3.fromRGB(240, 220, 175) }, parent)
	avoidCircle(pos, 12)
end

local function sphinxStatue(parent, pos, facing)
	if Kit.TryDecor("Sphinx", parent, pos, { height = 18, cf = CFrame.lookAt(pos, pos + facing) }) then
		return
	end
	local cf = CFrame.lookAt(pos, pos + facing)
	local sand = Color3.fromRGB(230, 195, 125)
	part({ Size = Vector3.new(14, 3, 26), CFrame = cf * CFrame.new(0, 1.5, 0), Color = Color3.fromRGB(205, 170, 110) }, parent)
	part({ Size = Vector3.new(10, 7, 16), CFrame = cf * CFrame.new(0, 6.5, 3), Color = sand }, parent)
	for _, x in ipairs({ -3, 3 }) do
		part({ Size = Vector3.new(3, 2.5, 10), CFrame = cf * CFrame.new(x, 4.25, -8), Color = sand }, parent)
	end
	part({ Size = Vector3.new(7, 8, 6), CFrame = cf * CFrame.new(0, 13, -4), Color = sand }, parent)
	part({ Size = Vector3.new(9, 9, 5), CFrame = cf * CFrame.new(0, 13.5, -2.5), Color = Color3.fromRGB(60, 110, 220) }, parent)
	for y = 10, 17, 2 do
		part({ Size = Vector3.new(9.2, 0.6, 5.2), CFrame = cf * CFrame.new(0, y, -2.5), Color = Config.Colors.Gold }, parent)
	end
	part({ Size = Vector3.new(5, 5, 1), CFrame = cf * CFrame.new(0, 13, -7.4), Color = sand }, parent)
	avoidCircle(pos, 16)
end

function MapZones.Desert(folder, zone)
	local c = zone.center
	pyramid(folder, c + Vector3.new(90, 0, -90), 36)
	pyramid(folder, c + Vector3.new(-110, 0, 100), 24)
	pyramid(folder, c + Vector3.new(110, 0, 90), 18)
	sphinxStatue(folder, c + Vector3.new(-100, 0, -95), Vector3.new(1, 0, 1))
	ruins(folder, c + Vector3.new(50, 0, 40))
	for _, p in ipairs({ Vector3.new(-26, 0, -100), Vector3.new(26, 0, -100), Vector3.new(-26, 0, 100), Vector3.new(26, 0, 100) }) do
		obelisk(folder, c + p)
	end
	-- oasis
	local oasis = c + Vector3.new(-60, 0, 20)
	Kit.pond(folder, oasis, 18, Color3.fromRGB(120, 210, 90))
	for k = 1, 8 do
		local a = (k / 8) * math.pi * 2
		Kit.palmTree(folder, oasis + Vector3.new(math.cos(a) * 25, 0, math.sin(a) * 25), R(0.9, 1.3))
	end
	-- marche de tentes
	local tentColors = { Color3.fromRGB(230, 70, 70), Color3.fromRGB(60, 120, 220), Color3.fromRGB(240, 180, 40), Color3.fromRGB(150, 80, 200) }
	for k = 0, 3 do
		tent(folder, CFrame.lookAt(c + Vector3.new(40 + k * 16, 0, -40), c + Vector3.new(40 + k * 16, 0, 0)), tentColors[k + 1])
	end
	Kit.scatter(zone, 34, 18, 200, cactus)
	Kit.scatter(zone, 20, 20, 200, function(pos)
		Kit.rock(folder, pos, R(0.8, 2.2), Color3.fromRGB(200, 150, 100))
	end)
	ambient(folder, zone, { color = Color3.fromRGB(250, 225, 170), rate = 25, speed = NumberRange.new(3, 6), dir = Enum.NormalId.Right, light = 0, height = 6, transparency = NumberSequence.new(0.4, 1) })
end

-- PLAGE ----------------------------------------------------------------------------------------

local function umbrella(parent, pos, color)
	if Kit.TryDecor("Parasol", parent, pos, { height = 8.5 }) then
		return
	end
	cylinder(CFrame.new(pos + Vector3.new(0, 4, 0)), 8, 0.25, WHITE, parent)
	for k = 0, 7 do
		local w = part({ Size = Vector3.new(3.4, 0.3, 4.4), CFrame = CFrame.new(pos + Vector3.new(0, 8, 0)) * CFrame.Angles(0, k * math.pi / 4, 0) * CFrame.new(0, -0.6, -2) * CFrame.Angles(math.rad(-20), 0, 0), Color = (k % 2 == 0) and color or WHITE, CanCollide = false }, parent)
	end
	ball(CFrame.new(pos + Vector3.new(0, 8.4, 0)), 0.8, color, parent)
	local towel = part({ Size = Vector3.new(3.5, 0.12, 6.5), CFrame = CFrame.new(pos + Vector3.new(3, 0.07, 1)) * CFrame.Angles(0, R(-0.3, 0.3), 0), Color = color:Lerp(WHITE, 0.3), CanCollide = false }, parent)
	part({ Size = Vector3.new(3.6, 0.13, 1), CFrame = towel.CFrame * CFrame.new(0, 0.01, 2.2), Color = WHITE, CanCollide = false }, parent)
	avoidCircle(pos, 6)
end

local function sandcastle(parent, pos)
	local sand = Color3.fromRGB(240, 205, 140)
	part({ Size = Vector3.new(9, 3, 9), CFrame = CFrame.new(pos + Vector3.new(0, 1.5, 0)), Color = sand }, parent)
	for _, o in ipairs({ Vector3.new(-4, 0, -4), Vector3.new(4, 0, -4), Vector3.new(-4, 0, 4), Vector3.new(4, 0, 4) }) do
		cylinder(CFrame.new(pos + o + Vector3.new(0, 2.5, 0)), 5, 1.6, sand, parent)
		cone(parent, pos + o + Vector3.new(0, 5, 0), 2.5, 1.8, sand:Lerp(WHITE, 0.15))
	end
	cylinder(CFrame.new(pos + Vector3.new(0, 4.5, 0)), 3, 2.6, sand, parent)
	part({ Size = Vector3.new(0.2, 3, 0.2), CFrame = CFrame.new(pos + Vector3.new(0, 7.5, 0)), Color = WHITE }, parent)
	part({ Size = Vector3.new(0.1, 1, 1.6), CFrame = CFrame.new(pos + Vector3.new(0, 8.4, 0.8)), Color = Color3.fromRGB(255, 80, 80) }, parent)
	avoidCircle(pos, 8)
end

local function lighthouse(parent, pos)
	if Kit.TryDecor("Phare", parent, pos, { height = 40 }) then
		return
	end
	part({ Size = Vector3.new(14, 3, 14), CFrame = CFrame.new(pos + Vector3.new(0, 1.5, 0)), Color = Color3.fromRGB(150, 150, 160), Material = Enum.Material.Slate }, parent)
	for i = 0, 6 do
		cylinder(CFrame.new(pos + Vector3.new(0, 3 + i * 4 + 2, 0)), 4, 4.6 - i * 0.3, (i % 2 == 0) and Color3.fromRGB(235, 60, 60) or WHITE, parent)
	end
	local lampY = 3 + 7 * 4
	cylinder(CFrame.new(pos + Vector3.new(0, lampY + 0.5, 0)), 1, 4, Color3.fromRGB(60, 60, 70), parent, Enum.Material.Metal)
	local glass = cylinder(CFrame.new(pos + Vector3.new(0, lampY + 3, 0)), 4, 2.6, Color3.fromRGB(255, 240, 160), parent, Enum.Material.Neon)
	cone(parent, pos + Vector3.new(0, lampY + 5, 0), 3.5, 3.4, Color3.fromRGB(235, 60, 60))
	local beam = part({ Size = Vector3.new(1.5, 1.5, 40), CFrame = CFrame.new(pos + Vector3.new(0, lampY + 3, 0)) * CFrame.new(0, 0, -20), Color = Color3.fromRGB(255, 245, 190), Material = Enum.Material.Neon, Transparency = 0.6, CanCollide = false }, parent)
	local pivot = part({ Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(pos + Vector3.new(0, lampY + 3, 0)), Transparency = 1, CanCollide = false }, parent)
	beam.Anchored = false
	local w = Instance.new("WeldConstraint")
	w.Part0 = pivot
	w.Part1 = beam
	w.Parent = beam
	spin(pivot, 6)
	local light = Instance.new("PointLight")
	light.Range = 30
	light.Color = Color3.fromRGB(255, 240, 170)
	light.Parent = glass
	avoidCircle(pos, 10)
end

local function beachHut(parent, cf, color)
	for _, x in ipairs({ -4, 4 }) do
		for _, z in ipairs({ -3.5, 3.5 }) do
			part({ Size = Vector3.new(0.8, 3, 0.8), CFrame = cf * CFrame.new(x, 1.5, z), Color = Kit.WOOD_DARK }, parent)
		end
	end
	part({ Size = Vector3.new(10, 0.6, 9), CFrame = cf * CFrame.new(0, 3.2, 0), Color = Kit.WOOD, Material = Enum.Material.WoodPlanks }, parent)
	part({ Size = Vector3.new(8, 6, 7), CFrame = cf * CFrame.new(0, 6.5, 0.5), Color = color }, parent)
	for i = 0, 3 do
		part({ Size = Vector3.new(8.1, 0.4, 7.1), CFrame = cf * CFrame.new(0, 4.5 + i * 1.5, 0.5), Color = WHITE }, parent)
	end
	for _, s in ipairs({ -1, 1 }) do
		wedge({ Size = Vector3.new(11, 3.5, 5), CFrame = cf * CFrame.new(0, 11.2, 0.5 + s * 2.5) * CFrame.Angles(0, s > 0 and math.pi or 0, 0), Color = Color3.fromRGB(225, 190, 110) }, parent)
	end
	part({ Size = Vector3.new(2.6, 4, 0.3), CFrame = cf * CFrame.new(0, 5.5, -3.1), Color = Kit.WOOD_DARK }, parent)
	for i = 0, 3 do
		part({ Size = Vector3.new(3, 0.4, 1.2), CFrame = cf * CFrame.new(0, 0.6 + i * 0.75, -5.2 - i * -0.5 - 1.5 + i * 0), Color = Kit.WOOD }, parent)
	end
	avoidCircle(cf.Position, 9)
end

local function surfboard(parent, pos, color)
	local b = part({ Size = Vector3.new(2, 7, 0.4), CFrame = CFrame.new(pos + Vector3.new(0, 3.3, 0)) * CFrame.Angles(math.rad(-10), R(0, 6.28), 0), Color = color }, parent)
	sphereMesh(b, Vector3.new(1, 1, 1))
	part({ Size = Vector3.new(0.4, 6.4, 0.45), CFrame = b.CFrame, Color = WHITE, CanCollide = false }, parent)
end

local function starfish(parent, pos, color)
	for k = 0, 4 do
		part({ Size = Vector3.new(0.6, 0.3, 1.4), CFrame = CFrame.new(pos + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, k * math.pi * 2 / 5, 0) * CFrame.new(0, 0, -0.7), Color = color, CanCollide = false }, parent)
	end
end

function MapZones.Plage(folder, zone)
	local c = zone.center
	local half = zone.size / 2
	-- lagon cote ouest (pas de pont de ce cote) avec ponton
	local lagoon = c + Vector3.new(-half + 60, 0, 30)
	local water = cylinder(CFrame.new(lagoon + Vector3.new(0, 0.15, 0)), 0.3, 50, Color3.fromRGB(60, 210, 230), folder, Enum.Material.Glass)
	water.Transparency = 0.15
	water.CanCollide = false
	water.Reflectance = 0.2
	local shallow = cylinder(CFrame.new(lagoon + Vector3.new(0, 0.1, 0)), 0.3, 56, Color3.fromRGB(150, 235, 235), folder)
	shallow.CanCollide = false
	avoidCircle(lagoon, 56)
	for i = 0, 14 do
		part({ Size = Vector3.new(7, 0.6, 2.2), CFrame = CFrame.new(lagoon + Vector3.new(30 - i * 2.4, 1, -10)) * CFrame.Angles(0, math.rad(90), 0), Color = (i % 2 == 0) and Kit.WOOD or Kit.WOOD_DARK, Material = Enum.Material.WoodPlanks }, folder)
		if i % 3 == 0 then
			for _, z in ipairs({ -3.4, 3.4 }) do
				part({ Size = Vector3.new(0.8, 3.5, 0.8), CFrame = CFrame.new(lagoon + Vector3.new(30 - i * 2.4, 0.5, -10 + z)), Color = Kit.WOOD_DARK }, folder)
			end
		end
	end
	-- petit bateau amarre
	local boat = lagoon + Vector3.new(-6, 0.8, -18)
	part({ Size = Vector3.new(5, 1.6, 11), CFrame = CFrame.new(boat), Color = Color3.fromRGB(240, 240, 245) }, folder)
	part({ Size = Vector3.new(5.2, 0.5, 11.2), CFrame = CFrame.new(boat + Vector3.new(0, 0.6, 0)), Color = Color3.fromRGB(60, 140, 230) }, folder)
	part({ Size = Vector3.new(0.4, 9, 0.4), CFrame = CFrame.new(boat + Vector3.new(0, 5, 1)), Color = Kit.WOOD_DARK }, folder)
	wedge({ Size = Vector3.new(0.2, 7, 5), CFrame = CFrame.new(boat + Vector3.new(0, 5.5, -1.5)), Color = WHITE, CanCollide = false }, folder)
	lighthouse(folder, c + Vector3.new(-half + 25, 0, -half + 25))
	local cols = { Color3.fromRGB(255, 90, 110), Color3.fromRGB(60, 170, 255), Color3.fromRGB(255, 200, 50), Color3.fromRGB(110, 220, 120) }
	for k = 0, 3 do
		beachHut(folder, CFrame.lookAt(c + Vector3.new(40 + k * 24, 0, 120), c + Vector3.new(40 + k * 24, 0, 0)), cols[k + 1])
	end
	sandcastle(folder, c + Vector3.new(60, 0, -60))
	sandcastle(folder, c + Vector3.new(-40, 0, -100))
	-- filet de volley
	local net = c + Vector3.new(90, 0, -20)
	for _, z in ipairs({ -10, 10 }) do
		part({ Size = Vector3.new(0.6, 8, 0.6), CFrame = CFrame.new(net + Vector3.new(0, 4, z)), Color = WHITE }, folder)
	end
	part({ Size = Vector3.new(0.2, 2.5, 20), CFrame = CFrame.new(net + Vector3.new(0, 6.5, 0)), Color = Color3.fromRGB(250, 250, 250), Transparency = 0.3, CanCollide = false }, folder)
	ball(CFrame.new(net + Vector3.new(5, 1.2, 3)), 2, Color3.fromRGB(255, 220, 80), folder)
	avoidCircle(net, 14)
	Kit.scatter(zone, 14, 20, 200, function(pos)
		umbrella(folder, pos, cols[rng:NextInteger(1, #cols)])
	end, 4)
	Kit.scatter(zone, 26, 15, 200, function(pos)
		Kit.palmTree(folder, pos, R(1, 1.5))
		avoidCircle(pos, 4)
	end, 3)
	Kit.scatter(zone, 10, 20, 200, function(pos)
		surfboard(folder, pos, cols[rng:NextInteger(1, #cols)])
		avoidCircle(pos, 3)
	end)
	Kit.scatter(zone, 30, 10, 200, function(pos)
		if rng:NextNumber() < 0.5 then
			starfish(folder, pos, Color3.fromRGB(255, 130, 90))
		else
			ball(CFrame.new(pos + Vector3.new(0, 0.3, 0)), R(0.8, 1.4), Color3.fromRGB(255, 220, 230), folder)
		end
	end)
	ambient(folder, zone, { color = WHITE, rate = 10, light = 0.3 })
end

-- CANDY LAND -----------------------------------------------------------------------------------

local CANDY = { Color3.fromRGB(255, 90, 160), Color3.fromRGB(120, 200, 255), Color3.fromRGB(255, 220, 80), Color3.fromRGB(150, 240, 140), Color3.fromRGB(190, 130, 255), Color3.fromRGB(255, 150, 90) }

local function lollipop(parent, pos, scale)
	local h = 9 * scale
	cylinder(CFrame.new(pos + Vector3.new(0, h / 2, 0)), h, 0.35 * scale, WHITE, parent)
	local col = CANDY[rng:NextInteger(1, #CANDY)]
	local rot = R(0, 6.28)
	local disc = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 7 * scale, 7 * scale), CFrame = CFrame.new(pos + Vector3.new(0, h + 3 * scale, 0)) * CFrame.Angles(0, rot, 0), Color = col }, parent)
	for k = 1, 3 do
		part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.05, (7 - k * 1.8) * scale, (7 - k * 1.8) * scale), CFrame = disc.CFrame, Color = (k % 2 == 1) and WHITE or col, CanCollide = false }, parent)
	end
	avoidCircle(pos, 4 * scale)
end

local function candyCane(parent, pos, scale)
	local h = 12 * scale
	for i = 0, 7 do
		cylinder(CFrame.new(pos + Vector3.new(0, (i + 0.5) * h / 8, 0)), h / 8, 0.9 * scale, (i % 2 == 0) and Color3.fromRGB(240, 50, 70) or WHITE, parent)
	end
	local rot = CFrame.Angles(0, R(0, 6.28), 0)
	for i = 0, 6 do
		local a = math.pi * i / 6
		local p = CFrame.new(pos + Vector3.new(0, h, 0)) * rot * CFrame.new(-math.cos(a) * 2 * scale + 2 * scale, math.sin(a) * 2 * scale, 0)
		ball(p, 1.9 * scale, (i % 2 == 0) and Color3.fromRGB(240, 50, 70) or WHITE, parent)
	end
	avoidCircle(pos, 4 * scale)
end

local function gumdrop(parent, pos, scale)
	local g = ball(CFrame.new(pos), 8 * scale, CANDY[rng:NextInteger(1, #CANDY)], parent, Enum.Material.Glass)
	g.Transparency = 0.1
	g.CanCollide = true
	sphereMesh(g, Vector3.new(1, 0.9, 1))
	avoidCircle(pos, 5 * scale)
end

local function cupcakeHouse(parent, pos, k)
	local base = CANDY[(k % #CANDY) + 1]
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		part({ Size = Vector3.new(4, 10, 1.6), CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 7.2, 5, math.sin(a) * 7.2)) * CFrame.Angles(0, -a + math.pi / 2, 0), Color = (i % 2 == 0) and base or base:Lerp(WHITE, 0.3) }, parent)
	end
	cylinder(CFrame.new(pos + Vector3.new(0, 5, 0)), 10, 7, base:Lerp(WHITE, 0.5), parent)
	local frost = ball(CFrame.new(pos + Vector3.new(0, 11, 0)), 18, Color3.fromRGB(255, 245, 250), parent)
	sphereMesh(frost, Vector3.new(1, 0.55, 1))
	ball(CFrame.new(pos + Vector3.new(0, 14, 0)), 9, Color3.fromRGB(255, 220, 235), parent)
	ball(CFrame.new(pos + Vector3.new(0, 18.5, 0)), 3.5, Color3.fromRGB(230, 30, 60), parent)
	for i = 1, 14 do
		local a = R(0, 6.28)
		local sprinkle = part({ Size = Vector3.new(0.3, 0.3, 1.1), CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * R(2, 7), R(12.5, 14.5), math.sin(a) * R(2, 7))) * CFrame.Angles(R(0, 3), R(0, 3), 0), Color = CANDY[rng:NextInteger(1, #CANDY)], CanCollide = false }, parent)
	end
	part({ Size = Vector3.new(3.2, 5, 0.4), CFrame = CFrame.new(pos + Vector3.new(0, 2.5, -7.9)), Color = Color3.fromRGB(130, 75, 45) }, parent)
	avoidCircle(pos, 11)
end

local function iceCream(parent, pos)
	for i = 0, 5 do
		cylinder(CFrame.new(pos + Vector3.new(0, i * 1.6 + 0.8, 0)), 1.6, 0.6 + i * 0.45, Color3.fromRGB(225, 170, 100), parent)
	end
	ball(CFrame.new(pos + Vector3.new(0, 10.5, 0)), 6.5, CANDY[rng:NextInteger(1, #CANDY)], parent)
	ball(CFrame.new(pos + Vector3.new(0, 14.5, 0)), 5.5, CANDY[rng:NextInteger(1, #CANDY)], parent)
	ball(CFrame.new(pos + Vector3.new(0, 17.6, 0)), 1.6, Color3.fromRGB(230, 30, 60), parent)
	avoidCircle(pos, 5)
end

local function donut(parent, pos, color)
	local n = 14
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		ball(CFrame.new(pos + Vector3.new(math.cos(a) * 4.5, 2.3, math.sin(a) * 4.5)), 4.8, Color3.fromRGB(225, 170, 100), parent)
		ball(CFrame.new(pos + Vector3.new(math.cos(a) * 4.5, 3, math.sin(a) * 4.5)), 4.2, color, parent)
	end
	avoidCircle(pos, 8)
end

local function cottonTree(parent, pos, scale)
	cylinder(CFrame.new(pos + Vector3.new(0, 4 * scale, 0)), 8 * scale, 0.5 * scale, WHITE, parent)
	local col = rng:NextNumber() < 0.5 and Color3.fromRGB(255, 170, 220) or Color3.fromRGB(170, 215, 255)
	for k = 1, 5 do
		ball(CFrame.new(pos + Vector3.new(R(-2.5, 2.5), 9 + R(-1, 2), R(-2.5, 2.5)) * scale), R(5, 7) * scale, col, parent)
	end
	avoidCircle(pos, 4 * scale)
end

function MapZones.Bonbons(folder, zone)
	local c = zone.center
	Kit.river(folder, c + Vector3.new(-150, 0, -60), c + Vector3.new(150, 0, -40), 12, Color3.fromRGB(255, 220, 235))
	for _, r in ipairs(folder:GetChildren()) do
		if r.Name == "River" then
			r.Color = Color3.fromRGB(120, 70, 45)
			r.Material = Enum.Material.SmoothPlastic
			r.Transparency = 0
		end
	end
	Kit.footbridge(folder, c + Vector3.new(0, 0, -51), Vector3.new(0, 0, 1), 14, 20)
	for k, p in ipairs({ Vector3.new(-100, 0, 80), Vector3.new(-60, 0, 120), Vector3.new(80, 0, 100), Vector3.new(110, 0, 50), Vector3.new(-110, 0, -110) }) do
		cupcakeHouse(folder, c + p, k)
	end
	for k, p in ipairs({ Vector3.new(60, 0, -110), Vector3.new(-40, 0, 40), Vector3.new(100, 0, -10) }) do
		donut(folder, c + p, CANDY[k])
	end
	for _, p in ipairs({ Vector3.new(40, 0, 60), Vector3.new(-80, 0, -10), Vector3.new(120, 0, -120) }) do
		iceCream(folder, c + p)
	end
	Kit.scatter(zone, 20, 20, 200, function(pos)
		lollipop(folder, pos, R(0.8, 1.4))
	end, 3)
	Kit.scatter(zone, 16, 20, 200, function(pos)
		candyCane(folder, pos, R(0.8, 1.3))
	end, 3)
	Kit.scatter(zone, 16, 20, 200, function(pos)
		cottonTree(folder, pos, R(0.9, 1.4))
	end, 3)
	Kit.scatter(zone, 18, 15, 200, function(pos)
		gumdrop(folder, pos, R(0.5, 1.2))
	end, 2)
	ambient(folder, zone, { color = Color3.fromRGB(255, 180, 230), rate = 35 })
end

-- NEIGE ----------------------------------------------------------------------------------------

local SNOW = Color3.fromRGB(248, 252, 255)

local function snowPine(parent, pos, scale)
	if Kit.TryDecor("SapinNeige", parent, pos, { height = 17 * (scale or 1) }) then
		return
	end
	Kit.pineTree(parent, pos, scale)
	for k = 0, 3 do
		local r = (5.5 - k * 1.2) * scale
		local cap = cylinder(CFrame.new(pos + Vector3.new(0, (6.7 + k * 3) * scale, 0)), 0.6 * scale, r * 0.75, SNOW, parent)
		cap.CanCollide = false
	end
	ball(CFrame.new(pos + Vector3.new(0, 17.3 * scale, 0)), 1.4 * scale, SNOW, parent)
	avoidCircle(pos, 5 * scale)
end

local function snowman(parent, pos)
	if Kit.TryDecor("BonhommeNeige", parent, pos, { height = 13 }) then
		return
	end
	ball(CFrame.new(pos + Vector3.new(0, 2.6, 0)), 5.5, SNOW, parent)
	ball(CFrame.new(pos + Vector3.new(0, 6.4, 0)), 4.2, SNOW, parent)
	ball(CFrame.new(pos + Vector3.new(0, 9.4, 0)), 3.2, SNOW, parent)
	for _, x in ipairs({ -0.55, 0.55 }) do
		ball(CFrame.new(pos + Vector3.new(x, 9.8, -1.45)), 0.45, Color3.fromRGB(30, 30, 40), parent)
	end
	local nose = part({ Size = Vector3.new(0.4, 0.4, 1.8), CFrame = CFrame.new(pos + Vector3.new(0, 9.3, -2.2)), Color = Color3.fromRGB(255, 140, 40), CanCollide = false }, parent)
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 4.4, 4.4), CFrame = CFrame.new(pos + Vector3.new(0, 8, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(230, 60, 60), CanCollide = false }, parent)
	cylinder(CFrame.new(pos + Vector3.new(0, 11.3, 0)), 0.4, 2.2, Color3.fromRGB(40, 40, 50), parent)
	cylinder(CFrame.new(pos + Vector3.new(0, 12.6, 0)), 2.4, 1.4, Color3.fromRGB(40, 40, 50), parent)
	for _, s in ipairs({ -1, 1 }) do
		part({ Size = Vector3.new(4, 0.3, 0.3), CFrame = CFrame.new(pos + Vector3.new(s * 3.4, 7, 0)) * CFrame.Angles(0, 0, math.rad(s * 25)), Color = Color3.fromRGB(110, 70, 40), CanCollide = false }, parent)
	end
	avoidCircle(pos, 4)
end

local function igloo(parent, pos, facing)
	if Kit.TryDecor("Igloo", parent, pos, { height = 9, cf = CFrame.lookAt(pos, pos + facing) }) then
		return
	end
	local dome = ball(CFrame.new(pos), 18, SNOW, parent)
	sphereMesh(dome, Vector3.new(1, 1, 1))
	local cf = CFrame.lookAt(pos, pos + facing)
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(7, 6, 6), CFrame = cf * CFrame.new(0, 2.5, -9) * CFrame.Angles(0, math.rad(90), 0), Color = SNOW }, parent)
	part({ Size = Vector3.new(3.4, 4, 0.4), CFrame = cf * CFrame.new(0, 2, -12.5), Color = Color3.fromRGB(70, 90, 130) }, parent)
	for y = 2, 7, 2.5 do
		cylinder(CFrame.new(pos + Vector3.new(0, y, 0)), 0.15, math.sqrt(math.max(81 - y * y, 1)) + 0.05, Color3.fromRGB(215, 230, 245), parent).CanCollide = false
	end
	avoidCircle(pos, 13)
end

local function iceCrystal(parent, pos, scale)
	if Kit.TryDecor("CristalGlace", parent, pos, { height = 7 * (scale or 1) }) then
		return
	end
	for k = 1, 4 do
		local h = R(4, 9) * scale
		part({ Size = Vector3.new(1.4, h, 1.4) * Vector3.new(scale, 1, scale), CFrame = CFrame.new(pos) * CFrame.Angles(R(-0.4, 0.4), R(0, 6.28), R(-0.4, 0.4)) * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, math.rad(45), 0), Color = Color3.fromRGB(170, 230, 255), Material = Enum.Material.Glass, Transparency = 0.2, CanCollide = false }, parent)
	end
	avoidCircle(pos, 3 * scale)
end

local function present(parent, pos)
	local col = CANDY[rng:NextInteger(1, #CANDY)]
	local s = R(2, 3.4)
	part({ Size = Vector3.new(s, s, s), CFrame = CFrame.new(pos + Vector3.new(0, s / 2, 0)) * CFrame.Angles(0, R(0, 3), 0), Color = col }, parent)
	part({ Size = Vector3.new(s + 0.1, s + 0.1, 0.5), CFrame = CFrame.new(pos + Vector3.new(0, s / 2, 0)), Color = WHITE, CanCollide = false }, parent)
end

function MapZones.Neige(folder, zone)
	local c = zone.center
	-- lac gele + patineurs (bonhommes)
	local lake = c + Vector3.new(70, 0, 60)
	local ice = cylinder(CFrame.new(lake + Vector3.new(0, 0.15, 0)), 0.3, 34, Color3.fromRGB(190, 235, 255), folder, Enum.Material.Glass)
	ice.Reflectance = 0.35
	ice.Transparency = 0.1
	cylinder(CFrame.new(lake + Vector3.new(0, 0.1, 0)), 0.3, 37, SNOW, folder)
	avoidCircle(lake, 40)
	igloo(folder, c + Vector3.new(-90, 0, 90), Vector3.new(1, 0, -1))
	igloo(folder, c + Vector3.new(-120, 0, 40), Vector3.new(1, 0, 0))
	-- chalet enneige
	local chalet = CFrame.new(c + Vector3.new(100, 0, -90)) * CFrame.Angles(0, math.rad(-130), 0)
	cabin(folder, chalet)
	for _, s in ipairs({ -1, 1 }) do
		wedge({ Size = Vector3.new(16.4, 1.2, 7.4), CFrame = chalet * CFrame.new(0, 13.6, s * 3.4) * CFrame.Angles(0, s > 0 and math.pi or 0, 0), Color = SNOW }, folder)
	end
	-- colline de neige avec escalier
	Kit.plateau(folder, c + Vector3.new(-80, 0, -90), 22, 7, SNOW, Color3.fromRGB(205, 225, 245), Vector3.new(1, 0, 0.6))
	snowman(folder, c + Vector3.new(-80, 7.5, -90))
	Kit.scatter(zone, 50, 20, 200, function(pos)
		snowPine(folder, pos, R(0.9, 1.6))
	end, 3)
	Kit.scatter(zone, 10, 20, 200, function(pos)
		snowman(folder, pos)
	end, 3)
	Kit.scatter(zone, 16, 15, 200, function(pos)
		iceCrystal(folder, pos, R(0.7, 1.4))
	end, 2)
	Kit.scatter(zone, 20, 10, 200, function(pos)
		present(folder, pos)
	end)
	ambient(folder, zone, { color = WHITE, rate = 120, height = 40, y = 5, speed = NumberRange.new(2, 4), dir = Enum.NormalId.Bottom, light = 0.2, life = NumberRange.new(6, 9), size = NumberSequence.new(0.35) })
end

-- MYSTIQUE -------------------------------------------------------------------------------------

local MYST = { Color3.fromRGB(190, 90, 255), Color3.fromRGB(80, 220, 255), Color3.fromRGB(255, 90, 210), Color3.fromRGB(120, 255, 200) }

local function glowCrystal(parent, pos, scale, color)
	if Kit.TryDecor("Cristal", parent, pos, { height = 9 * (scale or 1) }) then
		return
	end
	for k = 1, 5 do
		local h = R(4, 11) * scale
		local w = R(1.2, 2.2) * scale
		local cf = CFrame.new(pos) * CFrame.Angles(R(-0.45, 0.45), R(0, 6.28), R(-0.45, 0.45)) * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, math.rad(45), 0)
		part({ Size = Vector3.new(w, h, w), CFrame = cf, Color = color, Material = Enum.Material.Neon, Transparency = 0.15, CanCollide = false }, parent)
	end
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = 16 * scale
	l.Brightness = 1.5
	l.Parent = parent:GetChildren()[#parent:GetChildren()]
	avoidCircle(pos, 4 * scale)
end

local function glowMushroom(parent, pos, scale, color)
	if Kit.TryDecor("ChampignonMagique", parent, pos, { height = 9 * (scale or 1) }) then
		return
	end
	cylinder(CFrame.new(pos + Vector3.new(0, 3 * scale, 0)), 6 * scale, 0.9 * scale, Color3.fromRGB(230, 220, 255), parent)
	local cap = ball(CFrame.new(pos + Vector3.new(0, 6.5 * scale, 0)), 8 * scale, color, parent, Enum.Material.Neon)
	sphereMesh(cap, Vector3.new(1, 0.55, 1))
	for k = 1, 5 do
		local a = k * 1.25
		ball(CFrame.new(pos + Vector3.new(math.cos(a) * 2.2 * scale, 7.8 * scale, math.sin(a) * 2.2 * scale)), 0.9 * scale, WHITE, parent, Enum.Material.Neon)
	end
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = 14 * scale
	l.Parent = cap
	avoidCircle(pos, 4 * scale)
end

local function magicTree(parent, pos, scale)
	if Kit.TryDecor("ArbreMagique", parent, pos, { height = 14 * (scale or 1) }) then
		return
	end
	cylinder(CFrame.new(pos + Vector3.new(0, 5 * scale, 0)), 10 * scale, 1 * scale, Color3.fromRGB(70, 50, 100), parent)
	local col = MYST[rng:NextInteger(1, #MYST)]
	for k = 1, 5 do
		ball(CFrame.new(pos + Vector3.new(R(-3, 3), 11 + R(-1.5, 2), R(-3, 3)) * scale), R(5, 7) * scale, col:Lerp(Color3.fromRGB(60, 30, 110), 0.45), parent, Enum.Material.Grass)
	end
	for k = 1, 4 do
		ball(CFrame.new(pos + Vector3.new(R(-4, 4), 9 + R(-1, 3), R(-4, 4)) * scale), 0.9 * scale, col, parent, Enum.Material.Neon)
	end
	avoidCircle(pos, 5 * scale)
end

local function runeCircle(parent, pos)
	local ring = cylinder(CFrame.new(pos + Vector3.new(0, 0.12, 0)), 0.2, 16, Color3.fromRGB(190, 120, 255), parent, Enum.Material.Neon)
	ring.CanCollide = false
	cylinder(CFrame.new(pos + Vector3.new(0, 0.16, 0)), 0.2, 15, Color3.fromRGB(45, 25, 80), parent).CanCollide = false
	cylinder(CFrame.new(pos + Vector3.new(0, 0.2, 0)), 0.2, 6, Color3.fromRGB(120, 230, 255), parent, Enum.Material.Neon).CanCollide = false
	for k = 1, 8 do
		local a = k / 8 * math.pi * 2
		local p = pos + Vector3.new(math.cos(a) * 18, 0, math.sin(a) * 18)
		part({ Size = Vector3.new(2.2, 7, 2.2), CFrame = CFrame.new(p + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, a, 0), Color = Color3.fromRGB(90, 80, 120), Material = Enum.Material.Slate }, parent)
		part({ Size = Vector3.new(0.3, 2, 1.2), CFrame = CFrame.new(p + Vector3.new(0, 4.5, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(-1.15, 0, 0), Color = MYST[(k % #MYST) + 1], Material = Enum.Material.Neon }, parent)
	end
	local orb = ball(CFrame.new(pos + Vector3.new(0, 7, 0)), 4, Color3.fromRGB(200, 140, 255), parent, Enum.Material.Neon)
	orb.CanCollide = false
	bob(orb, 2, 3)
	local l = Instance.new("PointLight")
	l.Color = Color3.fromRGB(200, 140, 255)
	l.Range = 30
	l.Brightness = 2
	l.Parent = orb
	avoidCircle(pos, 21)
end

local function portal(parent, pos, facing)
	local cf = CFrame.lookAt(pos, pos + facing)
	local n = 20
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		ball(cf * CFrame.new(math.cos(a) * 9, 10 + math.sin(a) * 9, 0), 2.6, Color3.fromRGB(110, 90, 150), parent)
	end
	local disk = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 17, 17), CFrame = cf * CFrame.new(0, 10, 0) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(180, 100, 255), Material = Enum.Material.ForceField, CanCollide = false }, parent)
	local swirl = Instance.new("ParticleEmitter")
	swirl.Rate = 30
	swirl.Lifetime = NumberRange.new(1, 2)
	swirl.Speed = NumberRange.new(1, 3)
	swirl.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	swirl.LightEmission = 1
	swirl.Color = ColorSequence.new(Color3.fromRGB(220, 160, 255), Color3.fromRGB(100, 220, 255))
	swirl.Parent = disk
	part({ Size = Vector3.new(24, 2, 8), CFrame = cf * CFrame.new(0, 1, 0), Color = Color3.fromRGB(90, 80, 120), Material = Enum.Material.Slate }, parent)
	avoidCircle(pos, 14)
end

local function floatingRock(parent, pos, scale)
	local r = part({ Size = Vector3.new(R(5, 9), R(3, 5), R(5, 9)) * scale, CFrame = CFrame.new(pos) * CFrame.Angles(R(-0.3, 0.3), R(0, 6), R(-0.3, 0.3)), Color = Color3.fromRGB(110, 95, 140), Material = Enum.Material.Slate, CanCollide = false }, parent)
	local g = ball(CFrame.new(pos + Vector3.new(0, r.Size.Y / 2, 0)), r.Size.X * 0.9, Color3.fromRGB(150, 110, 230), parent, Enum.Material.Grass)
	sphereMesh(g, Vector3.new(1, 0.25, 1))
	g.CanCollide = false
	for _, p in ipairs({ r, g }) do
		bob(p, R(2, 4), R(3, 5))
	end
end

function MapZones.Mystique(folder, zone)
	local c = zone.center
	runeCircle(folder, c + Vector3.new(0, 0, 0) + Vector3.new(70, 0, 40))
	portal(folder, c + Vector3.new(110, 0, -100), Vector3.new(-1, 0, 1))
	portal(folder, c + Vector3.new(-110, 0, 110), Vector3.new(1, 0, -1))
	Kit.plateau(folder, c + Vector3.new(-90, 0, -80), 20, 8, Color3.fromRGB(150, 110, 230), Color3.fromRGB(90, 70, 130), Vector3.new(1, 0, 0.4))
	glowCrystal(folder, c + Vector3.new(-90, 8.5, -80), 2, MYST[2])
	for k = 1, 16 do
		local a = k / 16 * math.pi * 2
		floatingRock(folder, c + Vector3.new(math.cos(a) * R(100, 150), R(20, 45), math.sin(a) * R(100, 150)), R(0.8, 1.6))
	end
	Kit.scatter(zone, 26, 20, 200, function(pos)
		magicTree(folder, pos, R(0.9, 1.4))
	end, 3)
	Kit.scatter(zone, 22, 15, 200, function(pos)
		glowCrystal(folder, pos, R(0.7, 1.4), MYST[rng:NextInteger(1, #MYST)])
	end, 2)
	Kit.scatter(zone, 20, 15, 200, function(pos)
		glowMushroom(folder, pos, R(0.6, 1.3), MYST[rng:NextInteger(1, #MYST)])
	end, 2)
	ambient(folder, zone, { color = Color3.fromRGB(210, 150, 255), rate = 60, height = 20 })
end

-- PET KINGDOM ----------------------------------------------------------------------------------

local ROYAL = Color3.fromRGB(235, 230, 245)
local ROYAL_ROOF = Color3.fromRGB(70, 90, 220)

local function tower(parent, pos, radius, height, roof)
	cylinder(CFrame.new(pos + Vector3.new(0, height / 2, 0)), height, radius, ROYAL, parent)
	cylinder(CFrame.new(pos + Vector3.new(0, height + 0.5, 0)), 1, radius + 1, ROYAL:Lerp(Color3.new(0, 0, 0), 0.08), parent)
	for k = 1, 8 do
		local a = k / 8 * math.pi * 2
		part({ Size = Vector3.new(1.8, 2, 1.8), CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * radius, height + 2, math.sin(a) * radius)), Color = ROYAL }, parent)
	end
	cone(parent, pos + Vector3.new(0, height + 1, 0), radius * 2.2, radius + 0.6, roof or ROYAL_ROOF)
	part({ Size = Vector3.new(0.3, 5, 0.3), CFrame = CFrame.new(pos + Vector3.new(0, height + radius * 2.2 + 3, 0)), Color = Config.Colors.Gold }, parent)
	local flag = part({ Size = Vector3.new(0.15, 1.8, 3), CFrame = CFrame.new(pos + Vector3.new(0, height + radius * 2.2 + 4.5, 1.5)), Color = Color3.fromRGB(230, 50, 70), CanCollide = false }, parent)
	for y = height * 0.35, height * 0.8, height * 0.22 do
		part({ Size = Vector3.new(1.6, 2.6, 0.4), CFrame = CFrame.new(pos + Vector3.new(0, y, -radius)), Color = Color3.fromRGB(255, 220, 120), Material = Enum.Material.Neon }, parent)
	end
end

local function castle(parent, pos, facing)
	if Kit.TryDecor("Chateau", parent, pos, { width = 70, cf = CFrame.lookAt(pos, pos + facing) }) then
		return
	end
	local cf = CFrame.lookAt(pos, pos + facing)
	local W, D, H = 60, 40, 22
	-- remparts
	for _, side in ipairs({ { 0, -D / 2, W, 0 }, { 0, D / 2, W, 0 }, { -W / 2, 0, D, 90 }, { W / 2, 0, D, 90 } }) do
		local wcf = cf * CFrame.new(side[1], 0, side[2]) * CFrame.Angles(0, math.rad(side[4]), 0)
		if side[2] == -D / 2 then
			-- facade avec porte
			for _, x in ipairs({ -W / 2 + (W / 2 - 7) / 2, W / 2 - (W / 2 - 7) / 2 }) do
				part({ Size = Vector3.new(W / 2 - 7, H, 4), CFrame = wcf * CFrame.new(x, H / 2, 0), Color = ROYAL }, parent)
			end
			part({ Size = Vector3.new(14, H - 14, 4), CFrame = wcf * CFrame.new(0, 14 + (H - 14) / 2, 0), Color = ROYAL }, parent)
			part({ Size = Vector3.new(12, 13, 1), CFrame = wcf * CFrame.new(0, 6.5, 1.5), Color = Color3.fromRGB(120, 75, 45), Material = Enum.Material.WoodPlanks }, parent)
			sign(parent, wcf * CFrame.new(0, 17, -2.3) * CFrame.Angles(0, math.pi, 0), Vector3.new(26, 4, 0.5), "PET KINGDOM", Config.Colors.Gold, Color3.fromRGB(120, 40, 160))
		else
			part({ Size = Vector3.new(side[3], H, 4), CFrame = wcf * CFrame.new(0, H / 2, 0), Color = ROYAL }, parent)
		end
		for t = -side[3] / 2 + 2, side[3] / 2 - 2, 4 do
			part({ Size = Vector3.new(2, 2.4, 4.4), CFrame = wcf * CFrame.new(t, H + 1.2, 0), Color = ROYAL }, parent)
		end
	end
	for _, o in ipairs({ Vector3.new(-W / 2, 0, -D / 2), Vector3.new(W / 2, 0, -D / 2), Vector3.new(-W / 2, 0, D / 2), Vector3.new(W / 2, 0, D / 2) }) do
		tower(parent, (cf * CFrame.new(o)).Position, 6, H + 10)
	end
	-- donjon central
	tower(parent, (cf * CFrame.new(0, 0, 4)).Position, 11, H + 26, Color3.fromRGB(230, 60, 90))
	avoidCircle(pos, 46)
end

local function topiary(parent, pos)
	if Kit.TryDecor("Topiaire", parent, pos, { height = 10 }) then
		return
	end
	part({ Size = Vector3.new(3, 2, 3), CFrame = CFrame.new(pos + Vector3.new(0, 1, 0)), Color = Color3.fromRGB(220, 120, 80) }, parent)
	cylinder(CFrame.new(pos + Vector3.new(0, 3.5, 0)), 3, 0.3, Kit.WOOD_DARK, parent)
	ball(CFrame.new(pos + Vector3.new(0, 6, 0)), 4.5, Color3.fromRGB(70, 170, 70), parent, Enum.Material.Grass)
	ball(CFrame.new(pos + Vector3.new(0, 9, 0)), 3, Color3.fromRGB(80, 185, 75), parent, Enum.Material.Grass)
	avoidCircle(pos, 3)
end

local function banner(parent, pos, color)
	cylinder(CFrame.new(pos + Vector3.new(0, 7, 0)), 14, 0.35, Config.Colors.Gold, parent, Enum.Material.Metal)
	part({ Size = Vector3.new(4, 0.3, 0.3), CFrame = CFrame.new(pos + Vector3.new(0, 13.5, 0)), Color = Config.Colors.Gold }, parent)
	part({ Size = Vector3.new(3.6, 6, 0.2), CFrame = CFrame.new(pos + Vector3.new(0, 10.4, 0)), Color = color, CanCollide = false }, parent)
	wedge({ Size = Vector3.new(0.2, 1.5, 1.8), CFrame = CFrame.new(pos + Vector3.new(-0.9, 6.65, 0)) * CFrame.Angles(math.rad(180), math.rad(90), 0), Color = color, CanCollide = false }, parent)
	wedge({ Size = Vector3.new(0.2, 1.5, 1.8), CFrame = CFrame.new(pos + Vector3.new(0.9, 6.65, 0)) * CFrame.Angles(math.rad(180), math.rad(-90), 0), Color = color, CanCollide = false }, parent)
	ball(CFrame.new(pos + Vector3.new(0, 10.6, -0.2)), 1.4, Config.Colors.Gold, parent, Enum.Material.Neon)
	avoidCircle(pos, 2)
end

function MapZones.Royaume(folder, zone)
	local c = zone.center
	local half = zone.size / 2
	-- on arrive par le sud (+Z) ; chateau au nord, tapis rouge jusqu'a sa porte
	local castlePos = c + Vector3.new(0, 0, -105)
	castle(folder, castlePos, Vector3.new(0, 0, 1))
	local z0, z1 = half, -84
	part({ Size = Vector3.new(10, 0.25, z0 - z1), CFrame = CFrame.new(c + Vector3.new(0, 0.15, (z0 + z1) / 2)), Color = Color3.fromRGB(210, 40, 60), CanCollide = false }, folder)
	for _, x in ipairs({ -5.3, 5.3 }) do
		part({ Size = Vector3.new(0.6, 0.3, z0 - z1), CFrame = CFrame.new(c + Vector3.new(x, 0.16, (z0 + z1) / 2)), Color = Config.Colors.Gold, CanCollide = false }, folder)
	end
	local n = 0
	for z = half - 30, -70, -22 do
		n += 1
		for _, x in ipairs({ -12, 12 }) do
			banner(folder, c + Vector3.new(x, 0, z), n % 2 == 0 and Color3.fromRGB(120, 60, 200) or Color3.fromRGB(220, 50, 80))
		end
	end
	-- statues dorees de pets
	for k, p in ipairs({ Vector3.new(-40, 0, 40), Vector3.new(40, 0, 40), Vector3.new(-45, 0, -30), Vector3.new(45, 0, -30) }) do
		Kit.statue(folder, c + p, k % 2 == 0 and "egg" or "paw")
	end
	-- fontaine royale doree (le tapis passe autour)
	local f = c + Vector3.new(0, 0, 10)
	cylinder(CFrame.new(f + Vector3.new(0, 1, 0)), 2, 13, ROYAL, folder, Enum.Material.Marble)
	local w = cylinder(CFrame.new(f + Vector3.new(0, 1.8, 0)), 0.6, 12, Kit.WATER, folder, Enum.Material.Glass)
	w.Transparency = 0.2
	w.CanCollide = false
	cylinder(CFrame.new(f + Vector3.new(0, 5, 0)), 6, 2, Config.Colors.Gold, folder, Enum.Material.Metal)
	cylinder(CFrame.new(f + Vector3.new(0, 8.3, 0)), 0.8, 6, Config.Colors.Gold, folder, Enum.Material.Metal)
	local crown = f + Vector3.new(0, 9.5, 0)
	cylinder(CFrame.new(crown + Vector3.new(0, 1, 0)), 2, 2.6, Config.Colors.Gold, folder, Enum.Material.Neon)
	for k = 1, 5 do
		local a = k / 5 * math.pi * 2
		ball(CFrame.new(crown + Vector3.new(math.cos(a) * 2.4, 2.6, math.sin(a) * 2.4)), 1.2, Color3.fromRGB(255, 80, 120), folder, Enum.Material.Neon)
	end
	avoidCircle(f, 16)
	-- jardins a la francaise de chaque cote
	for _, sx in ipairs({ -1, 1 }) do
		local g = c + Vector3.new(sx * 90, 0, 40)
		Kit.hedge(folder, g + Vector3.new(-20, 0, -30), g + Vector3.new(-20, 0, 30))
		Kit.hedge(folder, g + Vector3.new(20, 0, -30), g + Vector3.new(20, 0, 30))
		Kit.hedge(folder, g + Vector3.new(-20, 0, -30), g + Vector3.new(20, 0, -30))
		Kit.flowerBed(folder, g, 9)
		for _, z in ipairs({ -20, 20 }) do
			topiary(folder, g + Vector3.new(0, 0, z))
		end
		Kit.avoidSegment(g + Vector3.new(0, 0, -32), g + Vector3.new(0, 0, 32), 22)
	end
	Kit.scatter(zone, 16, 30, 200, function(pos)
		topiary(folder, pos)
	end, 3)
	Kit.scatter(zone, 14, 30, 200, function(pos)
		Kit.roundTree(folder, pos, R(1, 1.4))
		avoidCircle(pos, 5)
	end, 4)
	Kit.scatter(zone, 14, 20, 200, function(pos)
		Kit.flowerPatch(folder, pos)
	end)
	ambient(folder, zone, { color = Color3.fromRGB(255, 225, 120), rate = 30 })
end

-- MONDE DE LAVE ----------------------------------------------------------------------------------

local function volcano(parent, pos)
	if Kit.TryDecor("Volcan", parent, pos, { height = 45 }) then
		return
	end
	local rock = Color3.fromRGB(70, 55, 55)
	for i = 0, 5 do
		local r = 36 - i * 5.5
		cylinder(CFrame.new(pos + Vector3.new(0, i * 7 + 3.5, 0)), 7.05, r, rock:Lerp(Color3.fromRGB(110, 80, 70), i / 6), parent)
	end
	local crater = cylinder(CFrame.new(pos + Vector3.new(0, 42.2, 0)), 0.6, 7, Color3.fromRGB(255, 110, 30), parent, Enum.Material.Neon)
	local fire = Instance.new("Fire")
	fire.Size = 14
	fire.Heat = 20
	fire.Color = Color3.fromRGB(255, 120, 40)
	fire.SecondaryColor = Color3.fromRGB(255, 220, 90)
	fire.Parent = crater
	local smoke = Instance.new("Smoke")
	smoke.Size = 18
	smoke.RiseVelocity = 12
	smoke.Color = Color3.fromRGB(70, 60, 60)
	smoke.Opacity = 0.25
	smoke.Parent = crater
	for k = 1, 5 do
		local a = k * 1.25
		part({ Size = Vector3.new(3, 30, 1), CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 20, 22, math.sin(a) * 20)) * CFrame.Angles(0, -a, math.rad(30)), Color = Color3.fromRGB(255, 120, 30), Material = Enum.Material.Neon, CanCollide = false }, parent)
	end
	avoidCircle(pos, 40)
end

local function obsidianSpike(parent, pos, scale)
	if Kit.TryDecor("Obsidienne", parent, pos, { height = 8 * (scale or 1) }) then
		return
	end
	for k = 1, 3 do
		local h = R(4, 10) * scale
		part({ Size = Vector3.new(1.6 * scale, h, 1.6 * scale), CFrame = CFrame.new(pos) * CFrame.Angles(R(-0.35, 0.35), R(0, 6.28), R(-0.35, 0.35)) * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, math.rad(45), 0), Color = Color3.fromRGB(35, 25, 45), Material = Enum.Material.Glass, Reflectance = 0.3 }, parent)
	end
	avoidCircle(pos, 3 * scale)
end

local function deadTree(parent, pos, scale)
	if Kit.TryDecor("ArbreMort", parent, pos, { height = 11 * (scale or 1) }) then
		return
	end
	cylinder(CFrame.new(pos + Vector3.new(0, 5 * scale, 0)), 10 * scale, 0.8 * scale, Color3.fromRGB(45, 35, 35), parent, Enum.Material.Wood)
	for k = 1, 3 do
		local a = k * 2.1
		part({ Size = Vector3.new(0.5, 4, 0.5) * scale, CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 1.4, 8.5, math.sin(a) * 1.4) * scale) * CFrame.Angles(math.sin(a) * 0.8, 0, math.cos(a) * 0.8), Color = Color3.fromRGB(45, 35, 35), Material = Enum.Material.Wood }, parent)
	end
	ball(CFrame.new(pos + Vector3.new(0, 10.2 * scale, 0)), 0.8 * scale, Color3.fromRGB(255, 140, 50), parent, Enum.Material.Neon)
	avoidCircle(pos, 3)
end

function MapZones.Lava(folder, zone)
	local c = zone.center
	volcano(folder, c + Vector3.new(95, 0, -95))
	Kit.river(folder, c + Vector3.new(-150, 0, -70), c + Vector3.new(60, 0, -60), 12, Color3.fromRGB(60, 45, 45))
	Kit.river(folder, c + Vector3.new(-40, 0, 160), c + Vector3.new(-60, 0, 40), 10, Color3.fromRGB(60, 45, 45))
	for _, r in ipairs(folder:GetChildren()) do
		if r.Name == "River" then
			r.Color = Color3.fromRGB(255, 110, 30)
			r.Material = Enum.Material.Neon
			r.Transparency = 0
		end
	end
	Kit.footbridge(folder, c + Vector3.new(0, 0, -62), Vector3.new(0, 0, 1), 14, 20)
	for k = 1, 4 do
		local p = c + Vector3.new(R(-120, 120), 0, R(-120, 120))
		if Kit.isFree(p, 10) then
			local pool = cylinder(CFrame.new(p + Vector3.new(0, 0.15, 0)), 0.3, R(6, 10), Color3.fromRGB(255, 120, 30), folder, Enum.Material.Neon)
			pool.CanCollide = false
			cylinder(CFrame.new(p + Vector3.new(0, 0.1, 0)), 0.3, pool.Size.Y / 2 + 2, Color3.fromRGB(50, 40, 40), folder).CanCollide = false
			avoidCircle(p, pool.Size.Y / 2 + 4)
		end
	end
	Kit.scatter(zone, 28, 20, 200, function(pos)
		obsidianSpike(folder, pos, R(0.7, 1.5))
	end, 2)
	Kit.scatter(zone, 24, 20, 200, function(pos)
		deadTree(folder, pos, R(0.8, 1.3))
	end, 3)
	Kit.scatter(zone, 20, 20, 200, function(pos)
		Kit.rock(folder, pos, R(0.8, 2), Color3.fromRGB(80, 65, 65))
	end)
	ambient(folder, zone, { color = Color3.fromRGB(255, 140, 50), rate = 50, speed = NumberRange.new(2, 5), height = 25 })
end

-- MONDE CELESTE ----------------------------------------------------------------------------------

function MapZones.Celestial(folder, zone)
	MapZones.Royaume(folder, zone)
	local c = zone.center
	for k = 1, 14 do
		local a = k / 14 * math.pi * 2
		floatingRock(folder, c + Vector3.new(math.cos(a) * R(110, 150), R(25, 55), math.sin(a) * R(110, 150)), R(0.8, 1.5))
	end
	Kit.scatter(zone, 14, 20, 200, function(pos)
		glowCrystal(folder, pos, R(0.7, 1.2), Color3.fromRGB(255, 230, 140))
	end, 2)
	ambient(folder, zone, { color = Color3.fromRGB(255, 250, 220), rate = 40, height = 30 })
end

-- GROTTE DE CRISTAL ------------------------------------------------------------------------------

function MapZones.Cave(folder, zone)
	MapZones.Mystique(folder, zone)
	Kit.scatter(zone, 26, 20, 200, function(pos)
		glowCrystal(folder, pos, R(1, 2.2), MYST[rng:NextInteger(1, #MYST)])
	end, 3)
end


MapZones.Forest = MapZones.Foret
MapZones.Frozen = MapZones.Neige

return MapZones
