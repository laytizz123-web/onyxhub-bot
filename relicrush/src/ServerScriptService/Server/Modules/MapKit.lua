-- Boite a outils du decor de PET RUSH : pieces de base, props (arbres, maisons, lanternes...),
-- structures (stands, plateformes, escaliers, ponts) et gestion des emplacements libres.
-- Utilisee par MapBuilder (monde, village) et MapZones (decor de chaque zone).

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Decor = require(script.Parent.Decor)

local Kit = {}

local rng = Random.new(42) -- decor identique a chaque lancement
Kit.rng = rng

local function R(a, b)
	return rng:NextNumber(a, b)
end
Kit.R = R

-- Emplacements reserves (pas de coins / props dessus)
local avoid = {}
Kit.avoid = avoid
local function avoidCircle(pos, radius)
	table.insert(avoid, { pos = pos, radius = radius })
end
Kit.avoidCircle = avoidCircle
function Kit.avoidSegment(a, b, radius)
	local d = (b - a)
	local n = math.max(1, math.ceil(d.Magnitude / (radius * 0.8)))
	for i = 0, n do
		avoidCircle(a + d * (i / n), radius)
	end
end
-- Utilise le modele "name" du dossier Decor s'il existe (sinon renvoie nil et le decor genere est construit)
function Kit.TryDecor(name, parent, pos, opts)
	opts = opts or {}
	local cf = opts.cf or (CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	local model, size = Decor.Place(name, parent, cf, opts)
	if model then
		avoidCircle(pos, math.max(size.X, size.Z) / 2 + 1)
	end
	return model
end

function Kit.isFree(pos, margin)
	margin = margin or 0
	for _, av in ipairs(avoid) do
		local dx, dz = pos.X - av.pos.X, pos.Z - av.pos.Z
		if dx * dx + dz * dz < (av.radius + margin) ^ 2 then
			return false
		end
	end
	return true
end

local KEEP_MATERIAL = { [Enum.Material.Neon] = true, [Enum.Material.Glass] = true, [Enum.Material.ForceField] = true }

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		p[k] = v
	end
	if not KEEP_MATERIAL[p.Material] then
		p.Material = Enum.Material.SmoothPlastic
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
	w.Material = Enum.Material.SmoothPlastic
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


local WATER = Color3.fromRGB(80, 190, 255)

local function pond(parent, center, radius, rimColor)
	local rim = cylinder(CFrame.new(center + Vector3.new(0, 0.05, 0)), 0.3, radius + 3, rimColor, parent)
	rim.CanCollide = false
	local water = cylinder(CFrame.new(center + Vector3.new(0, 0.12, 0)), 0.3, radius, WATER, parent, Enum.Material.Glass)
	water.Transparency = 0.1
	water.Reflectance = 0.15
	water.CanCollide = false
	for k = 1, 4 do
		local a = k * 1.7
		local pad = cylinder(CFrame.new(center + Vector3.new(math.cos(a) * radius * 0.55, 0.3, math.sin(a) * radius * 0.55)), 0.2, R(1.4, 2.2), Color3.fromRGB(90, 190, 80), parent)
		pad.CanCollide = false
		if k % 2 == 0 then
			ballPart(pad.CFrame * CFrame.new(0, 0.4, 0), 0.8, Color3.fromRGB(255, 140, 190), parent)
		end
	end
	avoidCircle(center, radius + 6)
end


local function cloudPuff(parent, pos, scale)
	local puffs = {}
	for k = 1, 5 do
		local b = ballPart(CFrame.new(pos + Vector3.new((k - 3) * 6 * scale, R(-1, 3) * scale, R(-3, 3) * scale)), R(8, 13) * scale, Color3.fromRGB(255, 255, 255), parent)
		b.CastShadow = false
		b.CanQuery = false
		table.insert(puffs, b)
	end
	local offset = Vector3.new(R(30, 60), 0, 0)
	for _, b in ipairs(puffs) do
		TweenService:Create(b, TweenInfo.new(R(30, 50), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { CFrame = b.CFrame + offset }):Play()
	end
end


local LEAF_COLORS = { Color3.fromRGB(95, 200, 75), Color3.fromRGB(120, 220, 85), Color3.fromRGB(75, 180, 70) }

local function roundTree(parent, pos, scale)
	if Kit.TryDecor("Arbre", parent, pos, { height = 14 * (scale or 1) }) then
		return
	end
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
	if Kit.TryDecor("Sapin", parent, pos, { height = 17 * (scale or 1) }) then
		return
	end
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
	if Kit.TryDecor("Palmier", parent, pos, { height = 15 * (scale or 1) }) then
		return
	end
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
	if Kit.TryDecor("Buisson", parent, pos, { height = 4 * (scale or 1), collide = false }) then
		return
	end
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
	if Kit.TryDecor("Fleurs", parent, pos, { height = 1.6, collide = false }) then
		return
	end
	local colors = { Color3.fromRGB(255, 120, 170), Color3.fromRGB(255, 230, 80), Color3.fromRGB(150, 140, 255), Color3.new(1, 1, 1) }
	for k = 1, 6 do
		local p = pos + Vector3.new(R(-3, 3), 0, R(-3, 3))
		part({ Size = Vector3.new(0.15, 1, 0.15), CFrame = CFrame.new(p + Vector3.new(0, 0.5, 0)), Color = Color3.fromRGB(70, 160, 60), CanCollide = false }, parent)
		ballPart(CFrame.new(p + Vector3.new(0, 1.1, 0)), 0.6, colors[rng:NextInteger(1, #colors)], parent)
	end
end

local function rock(parent, pos, scale, color)
	if Kit.TryDecor("Rocher", parent, pos, { height = 3 * (scale or 1) }) then
		return
	end
	scale = scale or 1
	part({ Size = Vector3.new(R(3, 5), R(2, 3.5), R(3, 5)) * scale, CFrame = CFrame.new(pos + Vector3.new(0, 0.6 * scale, 0)) * CFrame.Angles(R(-0.3, 0.3), R(0, 6.28), R(-0.3, 0.3)), Color = color or Color3.fromRGB(140, 140, 155), Material = Enum.Material.Slate }, parent)
end

local function mushroom(parent, pos, scale)
	if Kit.TryDecor("Champignon", parent, pos, { height = 3.2 * (scale or 1), collide = false }) then
		return
	end
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
	if Kit.TryDecor("Lampadaire", parent, pos, { height = 10 }) then
		return
	end
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
	if Kit.TryDecor("Maison", parent, cf.Position, { height = 16, cf = cf }) then
		return
	end
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

-- Nouveaux props ------------------------------------------------------------------------------

local WOOD = Color3.fromRGB(165, 110, 65)
local WOOD_DARK = Color3.fromRGB(125, 82, 48)
local STONE = Color3.fromRGB(205, 200, 210)
local WHITE = Color3.new(1, 1, 1)

-- Banc en bois oriente (face = -Z de cf)
local function bench(parent, cf)
	if Kit.TryDecor("Banc", parent, cf.Position, { height = 4, cf = cf }) then
		return
	end
	for _, z in ipairs({ -0.5, 0.5 }) do
		part({ Size = Vector3.new(6, 0.35, 0.9), CFrame = cf * CFrame.new(0, 1.6, z), Color = WOOD }, parent)
	end
	for k = 0, 2 do
		part({ Size = Vector3.new(6, 0.6, 0.25), CFrame = cf * CFrame.new(0, 2.4 + k * 0.75, 1.05) * CFrame.Angles(math.rad(-10), 0, 0), Color = WOOD }, parent)
	end
	for _, x in ipairs({ -2.6, 2.6 }) do
		part({ Size = Vector3.new(0.4, 1.6, 2.2), CFrame = cf * CFrame.new(x, 0.8, 0.1), Color = Color3.fromRGB(60, 60, 70), Material = Enum.Material.Metal }, parent)
	end
	avoidCircle(cf.Position, 4)
end

-- Lanterne sur poteau (style jardin), couleur de lumiere au choix
local function lantern(parent, pos, color)
	if Kit.TryDecor("Lanterne", parent, pos, { height = 7.5 }) then
		return
	end
	color = color or Color3.fromRGB(255, 210, 140)
	cylinder(CFrame.new(pos + Vector3.new(0, 2.5, 0)), 5, 0.35, WOOD_DARK, parent, Enum.Material.Wood)
	part({ Size = Vector3.new(1.6, 0.3, 1.6), CFrame = CFrame.new(pos + Vector3.new(0, 5.1, 0)), Color = WOOD_DARK }, parent)
	local glass = part({ Size = Vector3.new(1.2, 1.5, 1.2), CFrame = CFrame.new(pos + Vector3.new(0, 6, 0)), Color = color, Material = Enum.Material.Neon, Transparency = 0.1, CanCollide = false }, parent)
	wedge({ Size = Vector3.new(1.9, 0.8, 0.95), CFrame = CFrame.new(pos + Vector3.new(0, 7.1, -0.475)), Color = Color3.fromRGB(200, 70, 60) }, parent)
	wedge({ Size = Vector3.new(1.9, 0.8, 0.95), CFrame = CFrame.new(pos + Vector3.new(0, 7.1, 0.475)) * CFrame.Angles(0, math.pi, 0), Color = Color3.fromRGB(200, 70, 60) }, parent)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 14
	light.Brightness = 1.2
	light.Parent = glass
	avoidCircle(pos, 2)
end

-- Parterre de fleurs rond avec bordure
local FLOWER_COLORS = { Color3.fromRGB(255, 110, 160), Color3.fromRGB(255, 225, 70), Color3.fromRGB(150, 130, 255), Color3.fromRGB(255, 150, 80), WHITE }
local function flowerBed(parent, pos, radius, palette)
	palette = palette or FLOWER_COLORS
	local rim = cylinder(CFrame.new(pos + Vector3.new(0, 0.5, 0)), 1, radius + 0.8, STONE, parent, Enum.Material.Cobblestone)
	rim.CanCollide = true
	cylinder(CFrame.new(pos + Vector3.new(0, 0.75, 0)), 1, radius, Color3.fromRGB(120, 80, 50), parent)
	local n = math.floor(radius * radius * 0.9)
	for k = 1, n do
		local a = R(0, math.pi * 2)
		local r = math.sqrt(R(0, 1)) * (radius - 0.6)
		local p = pos + Vector3.new(math.cos(a) * r, 1.3, math.sin(a) * r)
		ballPart(CFrame.new(p), R(0.7, 1.1), palette[rng:NextInteger(1, #palette)], parent)
	end
	for k = 1, math.max(2, math.floor(radius)) do
		local a = R(0, math.pi * 2)
		ballPart(CFrame.new(pos + Vector3.new(math.cos(a) * radius * 0.5, 1.4, math.sin(a) * radius * 0.5)), R(1.4, 2), LEAF_COLORS[rng:NextInteger(1, 3)], parent, Enum.Material.Grass)
	end
	avoidCircle(pos, radius + 2)
end

-- Haie taillee entre deux points
local function hedge(parent, a, b, height, color)
	height = height or 3
	local d = b - a
	local cf = CFrame.lookAt((a + b) / 2 + Vector3.new(0, height / 2, 0), b + Vector3.new(0, height / 2, 0))
	part({ Size = Vector3.new(2.6, height, d.Magnitude), CFrame = cf, Color = color or Color3.fromRGB(70, 170, 70), Material = Enum.Material.Grass }, parent)
	for t = 0, d.Magnitude, 3 do
		ballPart(CFrame.new(a + d.Unit * t + Vector3.new(0, height, 0)), 2.8, color or Color3.fromRGB(80, 185, 75), parent, Enum.Material.Grass)
	end
end

-- Panneau indicateur avec fleches (vers les zones)
local function signpost(parent, pos, entries)
	cylinder(CFrame.new(pos + Vector3.new(0, 5, 0)), 10, 0.45, WOOD_DARK, parent, Enum.Material.Wood)
	for i, e in ipairs(entries) do
		local dir = Vector3.new(e.dir.X, 0, e.dir.Z).Unit
		local cf = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, math.rad(90), 0)
		local y = 9.5 - i * 1.9
		sign(parent, CFrame.new(pos + Vector3.new(0, y, 0)) * cf.Rotation * CFrame.new(3.4, 0, 0), Vector3.new(6.5, 1.5, 0.3), e.text, WHITE, e.color or WOOD)
		part({ Size = Vector3.new(1.08, 1.08, 0.3), CFrame = CFrame.new(pos + Vector3.new(0, y, 0)) * cf.Rotation * CFrame.new(6.65, 0, 0) * CFrame.Angles(0, 0, math.rad(45)), Color = e.color or WOOD }, parent)
	end
	avoidCircle(pos, 3)
end

-- Plateau rond sureleve (colline douce) avec escalier vers dir ; renvoie le dessus
local function plateau(parent, pos, radius, height, topColor, sideColor, stairDir)
	cylinder(CFrame.new(pos + Vector3.new(0, height / 2, 0)), height, radius, sideColor, parent)
	cylinder(CFrame.new(pos + Vector3.new(0, height + 0.25, 0)), 0.5, radius + 0.6, topColor, parent)
	for k = 1, math.floor(radius * 1.2) do
		local a = (k / math.floor(radius * 1.2)) * math.pi * 2
		local drip = ballPart(CFrame.new(pos + Vector3.new(math.cos(a) * (radius + 0.4), height - 0.2, math.sin(a) * (radius + 0.4))), R(2.4, 3.4), topColor, parent)
		drip.CanCollide = false
	end
	if stairDir then
		local dir = Vector3.new(stairDir.X, 0, stairDir.Z).Unit
		local steps = math.ceil(height / 1)
		local cf = CFrame.lookAt(pos, pos + dir)
		for s = 1, steps do
			local h = height * (1 - (s - 1) / steps)
			part({ Name = "Step", Size = Vector3.new(8, h, 2), CFrame = cf * CFrame.new(0, h / 2, -(radius - 1 + s * 2)), Color = (s % 2 == 0) and STONE or STONE:Lerp(Color3.new(0, 0, 0), 0.08), Material = Enum.Material.Cobblestone }, parent)
		end
		for _, x in ipairs({ -4.6, 4.6 }) do
			lantern(parent, (cf * CFrame.new(x, 0, -(radius + steps * 2 + 1))).Position)
		end
		Kit.avoidSegment(pos, pos + dir * (radius + steps * 2 + 2), 6)
	end
	avoidCircle(pos, radius + 3)
	return pos + Vector3.new(0, height + 0.5, 0)
end

-- Kiosque / gloriette
local function gazebo(parent, pos, roofColor)
	if Kit.TryDecor("Kiosque", parent, pos, { height = 15 }) then
		return
	end
	cylinder(CFrame.new(pos + Vector3.new(0, 0.5, 0)), 1, 9, STONE, parent, Enum.Material.Marble)
	for k = 1, 6 do
		local a = k / 6 * math.pi * 2
		cylinder(CFrame.new(pos + Vector3.new(math.cos(a) * 7.5, 5, math.sin(a) * 7.5)), 8, 0.5, WHITE, parent, Enum.Material.Marble)
	end
	local roof = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(20, 20, 20), CFrame = CFrame.new(pos + Vector3.new(0, 9, 0)), Color = roofColor or Color3.fromRGB(120, 190, 255), CanCollide = false }, parent)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Scale = Vector3.new(1, 0.45, 1)
	m.Parent = roof
	ballPart(CFrame.new(pos + Vector3.new(0, 13.8, 0)), 1.8, Config.Colors.Gold, parent, Enum.Material.Neon)
	bench(parent, CFrame.new(pos + Vector3.new(0, 1, 3)) * CFrame.Angles(0, math.pi, 0))
	avoidCircle(pos, 11)
end

-- Moulin a vent avec pales qui tournent
local function windmill(parent, pos, facing)
	if Kit.TryDecor("Moulin", parent, pos, { height = 26, cf = CFrame.lookAt(pos, pos + facing) }) then
		return
	end
	local cf = CFrame.lookAt(pos, pos + facing)
	cylinder(cf * CFrame.new(0, 9, 0), 18, 5, Color3.fromRGB(250, 240, 220), parent)
	local roof = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(11, 11, 11), CFrame = cf * CFrame.new(0, 18, 0), Color = Color3.fromRGB(220, 75, 65) }, parent)
	part({ Size = Vector3.new(3, 5, 0.4), CFrame = cf * CFrame.new(0, 2.5, -5), Color = WOOD_DARK, Material = Enum.Material.WoodPlanks }, parent)
	local hub = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.5, 2, 2), CFrame = cf * CFrame.new(0, 15, -5.6) * CFrame.Angles(0, math.rad(90), 0), Color = WOOD_DARK, CanCollide = false }, parent)
	local blades = {}
	for k = 0, 3 do
		local b = part({ Size = Vector3.new(2.4, 11, 0.3), CFrame = hub.CFrame * CFrame.Angles(math.rad(k * 90), 0, 0) * CFrame.new(0, 6, 0) * CFrame.Angles(0, math.rad(90), 0), Color = (k % 2 == 0) and WHITE or Color3.fromRGB(255, 200, 200), CanCollide = false }, parent)
		b.Anchored = false
		local w = Instance.new("WeldConstraint")
		w.Part0 = hub
		w.Part1 = b
		w.Parent = b
		table.insert(blades, b)
	end
	TweenService:Create(hub, TweenInfo.new(8, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { CFrame = hub.CFrame * CFrame.Angles(math.rad(-359), 0, 0) }):Play()
	avoidCircle(pos, 8)
end

-- Echoppe de marche decorative (auvent raye + caisses de fruits)
local STALL_COLORS = { Color3.fromRGB(255, 100, 120), Color3.fromRGB(80, 170, 255), Color3.fromRGB(255, 190, 40), Color3.fromRGB(130, 210, 90) }
local function stall(parent, cf, k)
	if Kit.TryDecor("Echoppe", parent, cf.Position, { height = 8.5, cf = cf }) then
		return
	end
	local color = STALL_COLORS[(k % #STALL_COLORS) + 1]
	part({ Size = Vector3.new(8, 3, 3.5), CFrame = cf * CFrame.new(0, 1.5, 0), Color = WOOD, Material = Enum.Material.WoodPlanks }, parent)
	for _, x in ipairs({ -3.8, 3.8 }) do
		part({ Size = Vector3.new(0.5, 7, 0.5), CFrame = cf * CFrame.new(x, 3.5, 1.4), Color = WOOD_DARK }, parent)
	end
	for s = 0, 4 do
		wedge({ Size = Vector3.new(1.6, 1.4, 4.5), CFrame = cf * CFrame.new(-3.2 + s * 1.6, 7.4, -0.3) * CFrame.Angles(0, math.pi, 0), Color = (s % 2 == 0) and color or WHITE, CanCollide = false }, parent)
	end
	local fruit = { Color3.fromRGB(255, 70, 70), Color3.fromRGB(255, 170, 40), Color3.fromRGB(120, 220, 80), Color3.fromRGB(170, 90, 220) }
	for i = 0, 2 do
		part({ Size = Vector3.new(2.2, 0.8, 1.8), CFrame = cf * CFrame.new(-2.6 + i * 2.6, 3.4, -0.4), Color = WOOD_DARK }, parent)
		for j = 1, 4 do
			ballPart(cf * CFrame.new(-2.6 + i * 2.6 + R(-0.6, 0.6), 4, -0.4 + R(-0.5, 0.5)), 0.7, fruit[((k + i) % #fruit) + 1], parent)
		end
	end
	avoidCircle(cf.Position, 6)
end

-- Statue doree de pet (patte geante sur socle) ou d'oeuf
local function statue(parent, pos, kind, color)
	if Kit.TryDecor("Statue", parent, pos, { height = 10 }) then
		return
	end
	color = color or Config.Colors.Gold
	local top
	part({ Size = Vector3.new(7, 3, 7), CFrame = CFrame.new(pos + Vector3.new(0, 1.5, 0)), Color = STONE, Material = Enum.Material.Marble }, parent)
	part({ Size = Vector3.new(7.8, 0.6, 7.8), CFrame = CFrame.new(pos + Vector3.new(0, 3.2, 0)), Color = WHITE, Material = Enum.Material.Marble }, parent)
	if kind == "egg" then
		local e = ballPart(CFrame.new(pos + Vector3.new(0, 7.5, 0)), 6, color, parent, Enum.Material.Metal)
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Scale = Vector3.new(1, 1.3, 1)
		m.Parent = e
		e.Reflectance = 0.25
		top = e
	else
		local pad = ballPart(CFrame.new(pos + Vector3.new(0, 6, 0)), 5, color, parent, Enum.Material.Metal)
		pad.Reflectance = 0.25
		top = pad
		for k = -1.5, 1.5 do
			local toe = ballPart(CFrame.new(pos + Vector3.new(k * 1.6, 9.2 - math.abs(k) * 0.6, 0)), 2.4, color, parent, Enum.Material.Metal)
			toe.Reflectance = 0.25
		end
	end
	local sp = Instance.new("Sparkles")
	sp.SparkleColor = color
	sp.Parent = top
	avoidCircle(pos, 6)
end

-- Arche decorative (entree, jardin)
local function archway(parent, cf, width, height, color, text, textColor)
	local stone = color or STONE
	for _, x in ipairs({ -width / 2, width / 2 }) do
		part({ Size = Vector3.new(4, height, 4), CFrame = cf * CFrame.new(x, height / 2, 0), Color = stone, Material = Enum.Material.Marble }, parent)
		part({ Size = Vector3.new(5, 1.5, 5), CFrame = cf * CFrame.new(x, 0.75, 0), Color = stone:Lerp(Color3.new(0, 0, 0), 0.1), Material = Enum.Material.Marble }, parent)
		ballPart(cf * CFrame.new(x, height + 2.5, 0), 3, Config.Colors.Gold, parent, Enum.Material.Neon)
	end
	-- arc en segments
	local n = 9
	for i = 0, n do
		local a = math.pi * i / n
		local x = math.cos(a) * width / 2
		local y = height + math.sin(a) * width * 0.28
		part({ Size = Vector3.new(width / n + 1.2, 3, 4.4), CFrame = cf * CFrame.new(x, y, 0) * CFrame.Angles(0, 0, a + math.pi / 2), Color = stone, Material = Enum.Material.Marble, CanCollide = false }, parent)
	end
	if text then
		sign(parent, cf * CFrame.new(0, height + width * 0.28 - 0.5, -2.4) * CFrame.Angles(0, math.pi, 0), Vector3.new(width * 0.8, 4, 0.5), text, textColor or Config.Colors.Gold, Color3.fromRGB(120, 70, 200))
	end
end

-- Montgolfiere qui flotte au loin
local function balloon(parent, pos, color)
	local env = ballPart(CFrame.new(pos), 16, color, parent)
	env.CanCollide = false
	local stripes = ballPart(CFrame.new(pos), 16.3, WHITE, parent)
	stripes.CanCollide = false
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Scale = Vector3.new(0.35, 1, 1)
	m.Parent = stripes
	local basket = part({ Size = Vector3.new(4, 3, 4), CFrame = CFrame.new(pos + Vector3.new(0, -12, 0)), Color = WOOD, Material = Enum.Material.WoodPlanks, CanCollide = false }, parent)
	local parts = { env, stripes, basket }
	for _, o in ipairs({ Vector3.new(1.8, 0, 1.8), Vector3.new(-1.8, 0, 1.8), Vector3.new(1.8, 0, -1.8), Vector3.new(-1.8, 0, -1.8) }) do
		table.insert(parts, part({ Size = Vector3.new(0.2, 6, 0.2), CFrame = CFrame.new(pos + o + Vector3.new(0, -8, 0)), Color = WOOD_DARK, CanCollide = false }, parent))
	end
	local rise = Vector3.new(0, R(6, 12), 0)
	for _, p in ipairs(parts) do
		TweenService:Create(p, TweenInfo.new(R(6, 10), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { CFrame = p.CFrame + rise }):Play()
	end
end

-- Petite ile decorative lointaine (profondeur du decor)
local function farIsland(parent, pos, size, top, dirt, decorate)
	part({ Size = Vector3.new(size, 3, size), CFrame = CFrame.new(pos + Vector3.new(0, -1.5, 0)), Color = top, CanCollide = false }, parent)
	local y = -3
	for k, s in ipairs({ size * 0.9, size * 0.6, size * 0.3 }) do
		part({ Size = Vector3.new(s, size * 0.18, s), CFrame = CFrame.new(pos + Vector3.new(0, y - size * 0.09, 0)), Color = (k % 2 == 0) and dirt:Lerp(Color3.new(0, 0, 0), 0.15) or dirt, CanCollide = false }, parent)
		y -= size * 0.18
	end
	for t = -size / 2, size / 2, 8 do
		for _, e in ipairs({ Vector3.new(t, -2, size / 2), Vector3.new(t, -2, -size / 2), Vector3.new(size / 2, -2, t), Vector3.new(-size / 2, -2, t) }) do
			local b = ballPart(CFrame.new(pos + e), 6, top, parent)
			b.CanCollide = false
		end
	end
	if decorate then
		decorate(pos)
	end
end

-- Riviere (bande d'eau avec berges) entre deux points
local function river(parent, a, b, width, bankColor)
	local d = b - a
	local cf = CFrame.lookAt((a + b) / 2, b)
	part({ Name = "RiverBank", Size = Vector3.new(width + 4, 0.3, d.Magnitude), CFrame = cf * CFrame.new(0, 0.08, 0), Color = bankColor or Color3.fromRGB(230, 210, 160), CanCollide = false }, parent)
	local w = part({ Name = "River", Size = Vector3.new(width, 0.3, d.Magnitude), CFrame = cf * CFrame.new(0, 0.16, 0), Color = WATER, Material = Enum.Material.Glass, Transparency = 0.1, CanCollide = false }, parent)
	w.Reflectance = 0.15
	for t = 0, d.Magnitude, 9 do
		for _, x in ipairs({ -width / 2 - 1.6, width / 2 + 1.6 }) do
			if rng:NextNumber() < 0.6 then
				local r = part({ Size = Vector3.new(R(1.5, 2.6), R(0.8, 1.4), R(1.5, 2.6)), CFrame = cf * CFrame.new(x, 0.4, -d.Magnitude / 2 + t) * CFrame.Angles(0, R(0, 3), 0), Color = Color3.fromRGB(160, 160, 175), Material = Enum.Material.Slate }, parent)
				r.CanCollide = false
			end
		end
	end
	Kit.avoidSegment(a, b, width / 2 + 3)
end

-- Petit pont de planches (praticable) en travers d'une riviere
local function footbridge(parent, pos, dir, width, len)
	local cf = CFrame.lookAt(pos, pos + dir)
	local n = math.floor(len / 1.6)
	for i = 0, n do
		local t = i / n
		local y = 0.3 + math.sin(t * math.pi) * 1.4
		part({ Size = Vector3.new(width, 0.5, 1.7), CFrame = cf * CFrame.new(0, y, -len / 2 + t * len), Color = (i % 2 == 0) and WOOD or WOOD_DARK, Material = Enum.Material.WoodPlanks }, parent)
	end
	for _, x in ipairs({ -width / 2, width / 2 }) do
		for i = 0, 2 do
			local t = i / 2
			part({ Size = Vector3.new(0.5, 3, 0.5), CFrame = cf * CFrame.new(x, 1.8 + math.sin(t * math.pi) * 1.4, -len / 2 + t * len), Color = WOOD_DARK }, parent)
		end
	end
end

-- Exports -------------------------------------------------------------------------------------

Kit.part = part
Kit.wedge = wedge
Kit.ball = ballPart
Kit.cylinder = cylinder
Kit.sign = sign
Kit.WATER = WATER
Kit.pond = pond
Kit.cloudPuff = cloudPuff
Kit.LEAF_COLORS = LEAF_COLORS
Kit.roundTree = roundTree
Kit.pineTree = pineTree
Kit.palmTree = palmTree
Kit.bush = bush
Kit.flowerPatch = flowerPatch
Kit.rock = rock
Kit.mushroom = mushroom
Kit.lamp = lamp
Kit.fenceLine = fenceLine
Kit.house = house
Kit.stand = stand
Kit.eggDisplay = eggDisplay
Kit.bench = bench
Kit.lantern = lantern
Kit.flowerBed = flowerBed
Kit.hedge = hedge
Kit.signpost = signpost
Kit.plateau = plateau
Kit.gazebo = gazebo
Kit.windmill = windmill
Kit.stall = stall
Kit.statue = statue
Kit.archway = archway
Kit.balloon = balloon
Kit.farIsland = farIsland
Kit.river = river
Kit.footbridge = footbridge
Kit.WOOD = WOOD
Kit.WOOD_DARK = WOOD_DARK
Kit.STONE = STONE

-- Repartit count props au hasard dans la zone (hors emplacements reserves)
function Kit.scatter(zone, count, minR, maxR, fn, margin)
	local half = zone.size / 2
	local placed = 0
	for k = 1, count * 3 do
		if placed >= count then
			break
		end
		local pos = zone.center + Vector3.new(R(-half + 14, half - 14), 0, R(-half + 14, half - 14))
		local r = (pos - zone.center).Magnitude
		if r >= (minR or 0) and r <= (maxR or half * 1.5) and Kit.isFree(pos, margin or 0) then
			placed += 1
			fn(pos, placed)
		end
	end
end

return Kit
