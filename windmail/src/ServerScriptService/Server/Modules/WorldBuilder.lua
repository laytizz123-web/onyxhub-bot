-- Monde de WINDMAIL : archipel realiste (Terrain Roblox), villages, boites aux lettres,
-- colonnes de vent (thermiques), anneaux de vent, secrets et eclairage.
-- Tags poses ici et utilises ailleurs :
--   PostCounter (guichet a colis), Mailbox (boite aux lettres), Updraft (colonne de vent),
--   WindRing (anneau de vitesse), StampSpot (timbre cache), Dock (point de sauvetage), TopBoard.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local WorldBuilder = {}

local Terrain = workspace.Terrain
local rng = Random.new(2024)
local function R(a, b)
	return rng:NextNumber(a, b)
end

local root -- dossier Workspace.Windmail
local mailboxCount = 0

-- Pieces ----------------------------------------------------------------------------------------

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = parent or root
	return p
end

local function wedge(props, parent)
	local p = Instance.new("WedgePart")
	p.Anchored = true
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = parent or root
	return p
end

local function cyl(cf, height, radius, color, material, parent)
	return part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, radius * 2, radius * 2), CFrame = cf * CFrame.Angles(0, 0, math.rad(90)), Color = color, Material = material or Enum.Material.SmoothPlastic }, parent)
end

local function ball(pos, size, color, material, parent)
	return part({ Shape = Enum.PartType.Ball, Size = Vector3.new(size, size, size), CFrame = CFrame.new(pos), Color = color, Material = material or Enum.Material.SmoothPlastic }, parent)
end

local function folder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent or root
	return f
end

local function label(parent, face, text, color, ppS)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ppS or 40
	gui.LightInfluence = 0.3
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextScaled = true
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = color or Color3.fromRGB(250, 245, 230)
	l.Parent = gui
	gui.Parent = parent
	return l
end

-- Couleurs et materiaux realistes
local WOOD = Color3.fromRGB(120, 85, 55)
local WOOD_LIGHT = Color3.fromRGB(170, 130, 90)
local PLASTER = { Color3.fromRGB(238, 230, 214), Color3.fromRGB(225, 214, 190), Color3.fromRGB(214, 222, 228), Color3.fromRGB(236, 220, 205), Color3.fromRGB(205, 215, 195) }
local ROOF = { Color3.fromRGB(150, 70, 55), Color3.fromRGB(70, 85, 105), Color3.fromRGB(110, 75, 60), Color3.fromRGB(85, 95, 80) }
local STONE = Color3.fromRGB(150, 145, 140)
local SHUTTER = { Color3.fromRGB(60, 110, 150), Color3.fromRGB(80, 130, 90), Color3.fromRGB(150, 70, 60), Color3.fromRGB(200, 170, 90) }

-- Eclairage --------------------------------------------------------------------------------------

local function lighting()
	Lighting.ClockTime = 15.2
	Lighting.GeographicLatitude = 38
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(95, 100, 115)
	Lighting.OutdoorAmbient = Color3.fromRGB(130, 135, 150)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)
	for _, c in ipairs(Lighting:GetChildren()) do
		c:Destroy()
	end
	local atm = Instance.new("Atmosphere")
	atm.Density = 0.32
	atm.Offset = 0.15
	atm.Color = Color3.fromRGB(200, 220, 240)
	atm.Decay = Color3.fromRGB(110, 140, 175)
	atm.Glare = 0.35
	atm.Haze = 1.6
	atm.Parent = Lighting
	local sky = Instance.new("Sky")
	sky.SunAngularSize = 14
	sky.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.35
	bloom.Size = 30
	bloom.Threshold = 1.4
	bloom.Parent = Lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.06
	rays.Spread = 0.6
	rays.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Contrast = 0.08
	cc.Saturation = 0.08
	cc.TintColor = Color3.fromRGB(255, 250, 242)
	cc.Parent = Lighting
	local dof = Instance.new("DepthOfFieldEffect")
	dof.FarIntensity = 0.12
	dof.FocusDistance = 120
	dof.InFocusRadius = 140
	dof.NearIntensity = 0
	dof.Parent = Lighting
	local clouds = Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.6
	clouds.Parent = Terrain
	Terrain.WaterColor = Color3.fromRGB(40, 120, 150)
	Terrain.WaterTransparency = 0.35
	Terrain.WaterWaveSize = 0.2
	Terrain.WaterWaveSpeed = 12
	Terrain.WaterReflectance = 0.6
	pcall(function()
		Terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(100, 140, 70))
		Terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(125, 120, 115))
		Terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(215, 200, 160))
	end)
end

-- Terrain : iles et mer ---------------------------------------------------------------------------

local function sea()
	Terrain:FillBlock(CFrame.new(-20, -24, -180), Vector3.new(1700, 48, 1500), Enum.Material.Water)
	Terrain:FillBlock(CFrame.new(-20, -50, -180), Vector3.new(1700, 4, 1500), Enum.Material.Sand)
end

-- Ile a falaises : socle rocheux irregulier, dessus herbeux, plage au pied
local function island(center, radius, height, opts)
	opts = opts or {}
	local top = opts.top or Enum.Material.Grass
	local rock = opts.rock or Enum.Material.Rock
	-- socle sous-marin et plage
	Terrain:FillCylinder(CFrame.new(center + Vector3.new(0, -26, 0)), 52, radius * 1.3, Enum.Material.Sand)
	if not opts.noBeach then
		Terrain:FillCylinder(CFrame.new(center + Vector3.new(0, 0.5, 0)), 3, radius * 1.22, Enum.Material.Sand)
	end
	-- falaise : cylindres empiles legerement decales + blocs arrondis sur le pourtour
	local steps = math.max(3, math.floor(height / 12))
	for i = 0, steps - 1 do
		local y0 = (height - 4) * i / steps
		local h = (height - 4) / steps + 2
		local r = radius * (1.06 - 0.08 * (i / steps)) + R(-2, 2)
		Terrain:FillCylinder(CFrame.new(center + Vector3.new(R(-2, 2), y0 + h / 2, R(-2, 2))), h, r, rock)
	end
	for k = 1, math.floor(radius / 3) do
		local a = R(0, math.pi * 2)
		local y = R(4, height - 6)
		local r = radius * (1.02 - 0.06 * (y / height)) + R(-1, 3)
		Terrain:FillBall(center + Vector3.new(math.cos(a) * r, y, math.sin(a) * r), R(6, 12), rock)
	end
	-- dessus
	Terrain:FillCylinder(CFrame.new(center + Vector3.new(0, height - 2, 0)), 4, radius, top)
	if opts.patch then
		for k = 1, 6 do
			local a = R(0, math.pi * 2)
			local r = R(0, radius * 0.7)
			Terrain:FillCylinder(CFrame.new(center + Vector3.new(math.cos(a) * r, height - 1.9, math.sin(a) * r)), 4, R(8, 18), opts.patch)
		end
	end
	return center + Vector3.new(0, height, 0)
end

-- Rocher en mer (pour les thermiques et le decor)
local function seaStack(pos, radius, height)
	Terrain:FillCylinder(CFrame.new(pos + Vector3.new(0, height / 2 - 20, 0)), height + 40, radius, Enum.Material.Rock)
	Terrain:FillBall(pos + Vector3.new(0, height, 0), radius * 1.1, Enum.Material.Rock)
	Terrain:FillCylinder(CFrame.new(pos + Vector3.new(0, height + radius * 0.6, 0)), 2, radius * 0.7, Enum.Material.Grass)
end

-- Vegetation et props ---------------------------------------------------------------------------

local LEAVES = { Color3.fromRGB(70, 110, 50), Color3.fromRGB(85, 125, 60), Color3.fromRGB(60, 95, 45) }

local function tree(parent, pos, scale, fruit)
	scale = scale or 1
	local trunk = cyl(CFrame.new(pos + Vector3.new(0, 5 * scale, 0)) * CFrame.Angles(R(-0.08, 0.08), 0, R(-0.08, 0.08)), 10 * scale, 0.7 * scale, Color3.fromRGB(95, 70, 50), Enum.Material.Wood, parent)
	local top = pos + Vector3.new(0, 10.5 * scale, 0)
	for k = 1, 6 do
		local o = Vector3.new(R(-2.6, 2.6), R(-1.2, 2.2), R(-2.6, 2.6)) * scale
		local b = ball(top + o, R(5, 7.5) * scale, LEAVES[rng:NextInteger(1, 3)], Enum.Material.Grass, parent)
		b.CanCollide = false
	end
	if fruit then
		for k = 1, 7 do
			local a = R(0, math.pi * 2)
			local b = ball(top + Vector3.new(math.cos(a) * 3.6 * scale, R(-1.5, 1.5) * scale, math.sin(a) * 3.6 * scale), 0.7 * scale, fruit, Enum.Material.SmoothPlastic, parent)
			b.CanCollide = false
		end
	end
end

local function pine(parent, pos, scale)
	scale = scale or 1
	cyl(CFrame.new(pos + Vector3.new(0, 4 * scale, 0)), 8 * scale, 0.6 * scale, Color3.fromRGB(90, 65, 45), Enum.Material.Wood, parent)
	for i = 0, 3 do
		local r = (5 - i * 1.1) * scale
		local c = cyl(CFrame.new(pos + Vector3.new(0, (5 + i * 2.6) * scale, 0)), 3 * scale, r, Color3.fromRGB(45, 80 + i * 6, 50), Enum.Material.Grass, parent)
		c.CanCollide = false
	end
end

local function rockProp(parent, pos, scale)
	part({ Size = Vector3.new(R(3, 6), R(2, 4), R(3, 6)) * scale, CFrame = CFrame.new(pos + Vector3.new(0, 0.8 * scale, 0)) * CFrame.Angles(R(-0.4, 0.4), R(0, 6.28), R(-0.4, 0.4)), Color = Color3.fromRGB(135, 130, 125), Material = Enum.Material.Slate }, parent)
end

local function bush(parent, pos)
	for k = 1, 3 do
		local b = ball(pos + Vector3.new(R(-1.4, 1.4), 1.1, R(-1.4, 1.4)), R(2.2, 3.2), LEAVES[rng:NextInteger(1, 3)], Enum.Material.Grass, parent)
		b.CanCollide = false
	end
	if rng:NextNumber() < 0.5 then
		local col = ({ Color3.fromRGB(230, 90, 110), Color3.fromRGB(250, 220, 90), Color3.fromRGB(240, 240, 250) })[rng:NextInteger(1, 3)]
		for k = 1, 4 do
			local f = ball(pos + Vector3.new(R(-1.6, 1.6), R(1.8, 2.4), R(-1.6, 1.6)), 0.5, col, Enum.Material.SmoothPlastic, parent)
			f.CanCollide = false
		end
	end
end

local function lampPost(parent, pos)
	cyl(CFrame.new(pos + Vector3.new(0, 0.3, 0)), 0.6, 0.6, Color3.fromRGB(40, 40, 45), Enum.Material.Metal, parent)
	cyl(CFrame.new(pos + Vector3.new(0, 4.5, 0)), 9, 0.18, Color3.fromRGB(40, 40, 45), Enum.Material.Metal, parent)
	local lamp = part({ Size = Vector3.new(1, 1.3, 1), CFrame = CFrame.new(pos + Vector3.new(0, 9.4, 0)), Color = Color3.fromRGB(255, 225, 170), Material = Enum.Material.Neon, Transparency = 0.15 }, parent)
	part({ Size = Vector3.new(1.4, 0.3, 1.4), CFrame = CFrame.new(pos + Vector3.new(0, 10.2, 0)), Color = Color3.fromRGB(40, 40, 45), Material = Enum.Material.Metal }, parent)
	local l = Instance.new("PointLight")
	l.Range = 16
	l.Brightness = 0.9
	l.Color = Color3.fromRGB(255, 210, 150)
	l.Shadows = false
	l.Parent = lamp
end

local function crate(parent, pos, s)
	s = s or 2
	part({ Size = Vector3.new(s, s, s), CFrame = CFrame.new(pos + Vector3.new(0, s / 2, 0)) * CFrame.Angles(0, R(0, 1.5), 0), Color = WOOD_LIGHT, Material = Enum.Material.WoodPlanks }, parent)
end

local function barrel(parent, pos)
	cyl(CFrame.new(pos + Vector3.new(0, 1.4, 0)), 2.8, 1.1, Color3.fromRGB(120, 80, 50), Enum.Material.Wood, parent)
	for _, y in ipairs({ 0.5, 2.3 }) do
		cyl(CFrame.new(pos + Vector3.new(0, y, 0)), 0.2, 1.15, Color3.fromRGB(70, 70, 75), Enum.Material.Metal, parent)
	end
end

local function fence(parent, a, b)
	local d = b - a
	local n = math.max(1, math.floor(d.Magnitude / 5))
	for i = 0, n do
		part({ Size = Vector3.new(0.4, 3, 0.4), CFrame = CFrame.new(a + d * (i / n) + Vector3.new(0, 1.5, 0)), Color = WOOD, Material = Enum.Material.Wood }, parent)
	end
	for _, h in ipairs({ 1.1, 2.3 }) do
		part({ Size = Vector3.new(0.25, 0.3, d.Magnitude), CFrame = CFrame.lookAt((a + b) / 2 + Vector3.new(0, h, 0), b + Vector3.new(0, h, 0)), Color = WOOD, Material = Enum.Material.Wood }, parent)
	end
end

-- Batiments -------------------------------------------------------------------------------------

-- Maison en pierre et crepi, toit a deux pans, volets, cheminee. Porte vers -Z de cf.
local function house(parent, cf, w, d, floors)
	w, d, floors = w or 14, d or 12, floors or 1
	local h = 8 * floors
	local wall = PLASTER[rng:NextInteger(1, #PLASTER)]
	local roof = ROOF[rng:NextInteger(1, #ROOF)]
	local shutter = SHUTTER[rng:NextInteger(1, #SHUTTER)]
	part({ Size = Vector3.new(w + 1, 1.2, d + 1), CFrame = cf * CFrame.new(0, 0.6, 0), Color = STONE, Material = Enum.Material.Cobblestone }, parent)
	part({ Size = Vector3.new(w, h, d), CFrame = cf * CFrame.new(0, 1.2 + h / 2, 0), Color = wall, Material = Enum.Material.Plaster }, parent)
	for _, x in ipairs({ -w / 2, w / 2 }) do
		for _, z in ipairs({ -d / 2, d / 2 }) do
			part({ Size = Vector3.new(1, h, 1), CFrame = cf * CFrame.new(x, 1.2 + h / 2, z), Color = STONE, Material = Enum.Material.Cobblestone }, parent)
		end
	end
	local rh = 5.5
	for _, s in ipairs({ -1, 1 }) do
		wedge({ Size = Vector3.new(w + 2, rh, d / 2 + 1), CFrame = cf * CFrame.new(0, 1.2 + h + rh / 2, s * (d / 4 + 0.5)) * CFrame.Angles(0, s > 0 and math.pi or 0, 0), Color = roof, Material = Enum.Material.Slate }, parent)
	end
	part({ Size = Vector3.new(1.8, 5, 1.8), CFrame = cf * CFrame.new(w / 3, h + rh + 0.5, d / 6), Color = Color3.fromRGB(120, 75, 60), Material = Enum.Material.Brick }, parent)
	part({ Size = Vector3.new(3, 5.5, 0.4), CFrame = cf * CFrame.new(0, 3.95, -d / 2 - 0.15), Color = Color3.fromRGB(90, 60, 40), Material = Enum.Material.WoodPlanks }, parent)
	part({ Size = Vector3.new(3.8, 0.4, 1.2), CFrame = cf * CFrame.new(0, 7, -d / 2 - 0.5), Color = STONE, Material = Enum.Material.Slate }, parent)
	for f = 0, floors - 1 do
		for _, x in ipairs({ -w / 3.2, w / 3.2 }) do
			if not (f == 0 and math.abs(x) < 2.5) then
				local y = 5.5 + f * 8
				part({ Size = Vector3.new(2.4, 2.8, 0.3), CFrame = cf * CFrame.new(x, y, -d / 2 - 0.1), Color = Color3.fromRGB(170, 200, 215), Material = Enum.Material.Glass, Transparency = 0.25, Reflectance = 0.2 }, parent)
				for _, sx in ipairs({ -1, 1 }) do
					part({ Size = Vector3.new(1.1, 3, 0.25), CFrame = cf * CFrame.new(x + sx * 1.8, y, -d / 2 - 0.25), Color = shutter, Material = Enum.Material.WoodPlanks }, parent)
				end
				local box = part({ Size = Vector3.new(2.8, 0.6, 0.8), CFrame = cf * CFrame.new(x, y - 1.8, -d / 2 - 0.5), Color = WOOD, Material = Enum.Material.Wood }, parent)
				for k = -1, 1 do
					local fl = ball((box.CFrame * CFrame.new(k * 0.8, 0.5, 0)).Position, 0.6, ({ Color3.fromRGB(220, 70, 90), Color3.fromRGB(250, 200, 80) })[rng:NextInteger(1, 2)], Enum.Material.SmoothPlastic, parent)
					fl.CanCollide = false
				end
			end
		end
	end
end

-- Boite aux lettres (destination). Le drapeau rouge se leve quand un colis est attendu.
local function mailbox(parent, pos, facing, zoneId, owner)
	mailboxCount += 1
	local cf = CFrame.lookAt(pos, pos + Vector3.new(facing.X, 0, facing.Z))
	local m = Instance.new("Model")
	m.Name = "Mailbox_" .. mailboxCount
	part({ Size = Vector3.new(0.5, 3.6, 0.5), CFrame = cf * CFrame.new(0, 1.8, 0), Color = WOOD, Material = Enum.Material.Wood }, m)
	local box = part({ Name = "Box", Size = Vector3.new(1.8, 1.6, 2.6), CFrame = cf * CFrame.new(0, 4.1, 0), Color = Color3.fromRGB(45, 95, 150), Material = Enum.Material.Metal }, m)
	cyl(cf * CFrame.new(0, 4.9, 0) * CFrame.Angles(math.rad(90), 0, 0), 2.6, 0.9, Color3.fromRGB(45, 95, 150), Enum.Material.Metal, m)
	local flag = part({ Name = "Flag", Size = Vector3.new(0.15, 1.6, 0.25), CFrame = cf * CFrame.new(1, 4.6, 0.6), Color = Color3.fromRGB(210, 50, 50), Material = Enum.Material.Metal }, m)
	part({ Size = Vector3.new(0.15, 0.6, 0.9), CFrame = cf * CFrame.new(1, 5.15, 0.25), Color = Color3.fromRGB(210, 50, 50), Material = Enum.Material.Metal }, m).Parent = m
	-- plaque du proprietaire
	local plate = part({ Size = Vector3.new(1.7, 0.6, 0.1), CFrame = cf * CFrame.new(0, 3.65, -1.34), Color = Color3.fromRGB(235, 225, 200), Material = Enum.Material.SmoothPlastic }, m)
	label(plate, Enum.NormalId.Front, owner, Color3.fromRGB(40, 40, 50), 60)
	-- pastille d'atterrissage
	local pad = cyl(cf * CFrame.new(0, 0.12, -5), 0.25, 5, Color3.fromRGB(190, 170, 130), Enum.Material.Cobblestone, m)
	pad.Name = "Pad"
	pad.CanCollide = false
	m.PrimaryPart = box
	m:SetAttribute("Zone", zoneId)
	m:SetAttribute("Owner", owner)
	m.Parent = parent
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Livrer"
	prompt.ObjectText = owner
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Enabled = true
	prompt.Parent = box
	CollectionService:AddTag(m, "Mailbox")
	return m
end

local OWNERS = {
	"Margot", "Famille Leroux", "Pepe Albin", "Ines & Tom", "Capitaine Yann", "Mme Rosier", "Atelier Noe", "Lucie", "Les Moreau",
	"Docteur Hugo", "Boulangerie Lina", "Oscar", "Mamie Jo", "Ferme Belair", "Paul le peintre", "Les Garnier", "Zoe", "Elio",
	"Maison Aubin", "Gaspard", "Clemence", "Rita", "Victor", "Nora", "L'horloger", "Felix", "Adele", "Bastien", "Celeste", "Mael",
	"Jade", "Sacha", "Theo", "Luna", "Armand", "Ada", "Vieux Marcel", "Salome", "Anouk", "Max",
}
local ownerIndex = 0
local function nextOwner()
	ownerIndex += 1
	return OWNERS[((ownerIndex - 1) % #OWNERS) + 1]
end

-- Guichet de poste (point de depart des missions)
local function postCounter(parent, cf, title)
	local counter = part({ Name = "PostCounter", Size = Vector3.new(10, 3.6, 3), CFrame = cf * CFrame.new(0, 1.8, 0), Color = Color3.fromRGB(110, 75, 50), Material = Enum.Material.WoodPlanks }, parent)
	part({ Size = Vector3.new(10.6, 0.4, 3.6), CFrame = cf * CFrame.new(0, 3.8, 0), Color = Color3.fromRGB(70, 50, 35), Material = Enum.Material.Wood }, parent)
	for i = 0, 4 do
		local s = R(1.2, 2)
		local p = part({ Size = Vector3.new(s, s * 0.7, s), CFrame = cf * CFrame.new(-3.5 + i * 1.7, 4 + s * 0.35, 0.4) * CFrame.Angles(0, R(-0.4, 0.4), 0), Color = Color3.fromRGB(200, 170, 120), Material = Enum.Material.Fabric }, parent)
		p.CanCollide = false
	end
	local sign = part({ Size = Vector3.new(9, 2, 0.4), CFrame = cf * CFrame.new(0, 8.5, 1), Color = Color3.fromRGB(40, 70, 110), Material = Enum.Material.Wood }, parent)
	label(sign, Enum.NormalId.Front, title, Color3.fromRGB(255, 225, 150))
	label(sign, Enum.NormalId.Back, title, Color3.fromRGB(255, 225, 150))
	for _, x in ipairs({ -4.3, 4.3 }) do
		part({ Size = Vector3.new(0.5, 9.5, 0.5), CFrame = cf * CFrame.new(x, 4.75, 1), Color = Color3.fromRGB(70, 50, 35), Material = Enum.Material.Wood }, parent)
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Prendre des colis"
	prompt.ObjectText = title
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter
	CollectionService:AddTag(counter, "PostCounter")
	return counter
end

-- Grande poste de Port-Brise
local function postOffice(parent, cf)
	local w, d, h = 34, 24, 16
	local brick = Color3.fromRGB(165, 90, 70)
	part({ Size = Vector3.new(w + 2, 1.5, d + 2), CFrame = cf * CFrame.new(0, 0.75, 0), Color = STONE, Material = Enum.Material.Cobblestone }, parent)
	-- murs (ouverture large a l'avant)
	part({ Size = Vector3.new(w, h, 1.2), CFrame = cf * CFrame.new(0, 1.5 + h / 2, d / 2), Color = brick, Material = Enum.Material.Brick }, parent)
	for _, s in ipairs({ -1, 1 }) do
		part({ Size = Vector3.new(1.2, h, d), CFrame = cf * CFrame.new(s * w / 2, 1.5 + h / 2, 0), Color = brick, Material = Enum.Material.Brick }, parent)
		part({ Size = Vector3.new(w / 2 - 7, h, 1.2), CFrame = cf * CFrame.new(s * (w / 4 + 3.5), 1.5 + h / 2, -d / 2), Color = brick, Material = Enum.Material.Brick }, parent)
		for _, x in ipairs({ 9.5, 13.5 }) do
			part({ Size = Vector3.new(2.6, 5, 0.3), CFrame = cf * CFrame.new(s * x, 9, -d / 2 - 0.6), Color = Color3.fromRGB(180, 205, 220), Material = Enum.Material.Glass, Transparency = 0.3 }, parent)
		end
	end
	part({ Size = Vector3.new(14, h - 10, 1.2), CFrame = cf * CFrame.new(0, 1.5 + 10 + (h - 10) / 2, -d / 2), Color = brick, Material = Enum.Material.Brick }, parent)
	-- colonnes et fronton
	for _, x in ipairs({ -6, 6 }) do
		cyl(cf * CFrame.new(x, 6.5, -d / 2 - 2), 10, 0.8, Color3.fromRGB(235, 230, 220), Enum.Material.Marble, parent)
	end
	part({ Size = Vector3.new(16, 1.2, 5), CFrame = cf * CFrame.new(0, 12, -d / 2 - 1.5), Color = Color3.fromRGB(235, 230, 220), Material = Enum.Material.Marble }, parent)
	local sign = part({ Size = Vector3.new(20, 3.4, 0.5), CFrame = cf * CFrame.new(0, h - 1.5, -d / 2 - 0.9), Color = Color3.fromRGB(30, 55, 90), Material = Enum.Material.Wood }, parent)
	label(sign, Enum.NormalId.Front, "POSTE DES VENTS", Color3.fromRGB(255, 215, 120))
	-- toit
	for _, s in ipairs({ -1, 1 }) do
		wedge({ Size = Vector3.new(w + 3, 7, d / 2 + 1.5), CFrame = cf * CFrame.new(0, 1.5 + h + 3.5, s * (d / 4 + 0.75)) * CFrame.Angles(0, s > 0 and math.pi or 0, 0), Color = Color3.fromRGB(65, 75, 90), Material = Enum.Material.Slate }, parent)
	end
	-- horloge et girouette
	local clock = cyl(cf * CFrame.new(0, h + 4, -d / 4 - 1) * CFrame.Angles(0, math.rad(90), 0), 0.6, 2.6, Color3.fromRGB(245, 240, 225), Enum.Material.SmoothPlastic, parent)
	clock.CFrame = cf * CFrame.new(0, h + 3.2, -d / 4 - 1.2) * CFrame.Angles(math.rad(90), 0, 0) * CFrame.Angles(0, 0, 0)
	part({ Size = Vector3.new(0.3, 4, 0.3), CFrame = cf * CFrame.new(0, h + 10, 0), Color = Color3.fromRGB(60, 60, 65), Material = Enum.Material.Metal }, parent)
	local vane = part({ Size = Vector3.new(0.2, 1.2, 3), CFrame = cf * CFrame.new(0, h + 11.5, 0), Color = Color3.fromRGB(200, 160, 70), Material = Enum.Material.Metal }, parent)
	TweenService:Create(vane, TweenInfo.new(6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { CFrame = vane.CFrame * CFrame.Angles(0, math.rad(70), 0) }):Play()
	-- interieur : sol, guichet, casiers, panneau du classement
	part({ Size = Vector3.new(w - 1, 0.3, d - 1), CFrame = cf * CFrame.new(0, 1.65, 0), Color = Color3.fromRGB(150, 110, 75), Material = Enum.Material.WoodPlanks }, parent)
	postCounter(parent, cf * CFrame.new(0, 1.5, 4) * CFrame.Angles(0, math.pi, 0), "Guichet principal")
	for i = 0, 5 do
		part({ Size = Vector3.new(4.5, 9, 2), CFrame = cf * CFrame.new(-13 + i * 5.2, 6, d / 2 - 1.6), Color = Color3.fromRGB(100, 70, 45), Material = Enum.Material.WoodPlanks }, parent)
	end
	local board = part({ Name = "TopBoard", Size = Vector3.new(10, 8, 0.4), CFrame = cf * CFrame.new(w / 2 - 1, 7.5, 0) * CFrame.Angles(0, math.rad(-90), 0), Color = Color3.fromRGB(30, 40, 55), Material = Enum.Material.Wood }, parent)
	CollectionService:AddTag(board, "TopBoard")
	local lamp = part({ Size = Vector3.new(2, 0.5, 2), CFrame = cf * CFrame.new(0, h, 0), Color = Color3.fromRGB(255, 230, 180), Material = Enum.Material.Neon }, parent)
	local l = Instance.new("PointLight")
	l.Range = 30
	l.Brightness = 1.2
	l.Color = Color3.fromRGB(255, 220, 170)
	l.Parent = lamp
end

local function lighthouse(parent, pos, height)
	local base = pos
	for i = 0, 7 do
		local r = 6 - i * 0.35
		cyl(CFrame.new(base + Vector3.new(0, i * height / 8 + height / 16, 0)), height / 8 + 0.05, r, (i % 2 == 0) and Color3.fromRGB(240, 240, 235) or Color3.fromRGB(190, 50, 45), Enum.Material.Concrete, parent)
	end
	local top = base + Vector3.new(0, height, 0)
	cyl(CFrame.new(top + Vector3.new(0, 0.5, 0)), 1, 5.5, Color3.fromRGB(50, 50, 55), Enum.Material.Metal, parent)
	-- garde-corps de la galerie
	for k = 0, 15 do
		local a = k / 16 * math.pi * 2
		part({ Size = Vector3.new(0.2, 2.5, 0.2), CFrame = CFrame.new(top + Vector3.new(math.cos(a) * 5.2, 2.2, math.sin(a) * 5.2)), Color = Color3.fromRGB(50, 50, 55), Material = Enum.Material.Metal }, parent)
	end
	local glass = cyl(CFrame.new(top + Vector3.new(0, 3.5, 0)), 5, 3, Color3.fromRGB(255, 240, 190), Enum.Material.Glass, parent)
	glass.Transparency = 0.3
	local bulb = ball(top + Vector3.new(0, 3.5, 0), 2.4, Color3.fromRGB(255, 235, 170), Enum.Material.Neon, parent)
	local l = Instance.new("SpotLight")
	l.Range = 60
	l.Angle = 30
	l.Brightness = 3
	l.Face = Enum.NormalId.Front
	l.Parent = bulb
	TweenService:Create(bulb, TweenInfo.new(8, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { CFrame = bulb.CFrame * CFrame.Angles(0, math.rad(-359), 0) }):Play()
	local roof = ball(top + Vector3.new(0, 6.5, 0), 7, Color3.fromRGB(190, 50, 45), Enum.Material.Metal, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 0.6, 1)
	mesh.Parent = roof
	-- echelle cachee a l'arriere (+X)
	local truss = Instance.new("TrussPart")
	truss.Anchored = true
	truss.Size = Vector3.new(2, height, 2)
	truss.CFrame = CFrame.new(base + Vector3.new(6.2, height / 2, 0))
	truss.Color = Color3.fromRGB(80, 80, 85)
	truss.Material = Enum.Material.Metal
	truss.Parent = parent
	return top
end

local function windmill(parent, pos, facing)
	local cf = CFrame.lookAt(pos, pos + facing)
	for i = 0, 4 do
		cyl(cf * CFrame.new(0, i * 4 + 2, 0), 4.05, 7 - i * 0.6, Color3.fromRGB(225, 215, 195), Enum.Material.Plaster, parent)
	end
	local cap = ball((cf * CFrame.new(0, 21, 0)).Position, 9, Color3.fromRGB(110, 75, 55), Enum.Material.WoodPlanks, parent)
	local hub = part({ Size = Vector3.new(1.6, 1.6, 2), CFrame = cf * CFrame.new(0, 19, -5), Color = WOOD, Material = Enum.Material.Wood, CanCollide = false }, parent)
	for k = 0, 3 do
		local blade = part({ Size = Vector3.new(2.6, 13, 0.3), CFrame = hub.CFrame * CFrame.Angles(0, 0, math.rad(k * 90)) * CFrame.new(0, 7, 0), Color = Color3.fromRGB(235, 225, 205), Material = Enum.Material.Fabric, CanCollide = false }, parent)
		blade.Anchored = false
		local w = Instance.new("WeldConstraint")
		w.Part0 = hub
		w.Part1 = blade
		w.Parent = blade
	end
	TweenService:Create(hub, TweenInfo.new(10, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { CFrame = hub.CFrame * CFrame.Angles(0, 0, math.rad(-359)) }):Play()
	part({ Size = Vector3.new(3.4, 6, 0.4), CFrame = cf * CFrame.new(0, 3, -6.7), Color = Color3.fromRGB(90, 60, 40), Material = Enum.Material.WoodPlanks }, parent)
end

local function dock(parent, pos, dir, length)
	local cf = CFrame.lookAt(pos, pos + dir)
	for i = 0, math.floor(length / 2.2) do
		part({ Size = Vector3.new(8, 0.5, 2), CFrame = cf * CFrame.new(0, 1.6, -i * 2.2), Color = (i % 2 == 0) and WOOD_LIGHT or WOOD, Material = Enum.Material.WoodPlanks }, parent)
		if i % 3 == 0 then
			for _, x in ipairs({ -3.6, 3.6 }) do
				cyl(cf * CFrame.new(x, -1, -i * 2.2), 6, 0.45, WOOD, Enum.Material.Wood, parent)
			end
		end
	end
	barrel(parent, (cf * CFrame.new(2.5, 1.85, -4)).Position)
	crate(parent, (cf * CFrame.new(-2.5, 1.85, -6)).Position)
	-- petite barque amarree
	local boat = cf * CFrame.new(7, 0.6, -length * 0.6)
	part({ Size = Vector3.new(4, 1.4, 9), CFrame = boat, Color = Color3.fromRGB(60, 110, 140), Material = Enum.Material.WoodPlanks }, parent)
	part({ Size = Vector3.new(4.2, 0.3, 9.2), CFrame = boat * CFrame.new(0, 0.75, 0), Color = Color3.fromRGB(230, 225, 210), Material = Enum.Material.Wood }, parent)
	local spawnPoint = part({ Name = "DockSpawn", Size = Vector3.new(4, 1, 4), CFrame = cf * CFrame.new(0, 2.4, -3), Transparency = 1, CanCollide = false, CanQuery = false }, parent)
	CollectionService:AddTag(spawnPoint, "Dock")
end

-- Colonne de vent : souleve les joueurs (a pied ou en vol). top = altitude atteinte.
local function updraft(parent, pos, radius, top, strength)
	local h = top - pos.Y
	local col = part({ Name = "Updraft", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, radius * 2, radius * 2), CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false }, parent)
	col:SetAttribute("Radius", radius)
	col:SetAttribute("Bottom", pos.Y)
	col:SetAttribute("Top", top)
	col:SetAttribute("Strength", strength or 45)
	CollectionService:AddTag(col, "Updraft")
	-- base : bouche d'aeration en pierre
	cyl(CFrame.new(pos + Vector3.new(0, 0.4, 0)), 0.8, radius * 0.7, Color3.fromRGB(110, 105, 100), Enum.Material.Slate, parent)
	cyl(CFrame.new(pos + Vector3.new(0, 0.6, 0)), 0.8, radius * 0.55, Color3.fromRGB(70, 130, 160), Enum.Material.Neon, parent).Transparency = 0.6
	local emitterPart = part({ Size = Vector3.new(radius * 1.4, 1, radius * 1.4), CFrame = CFrame.new(pos + Vector3.new(0, 1, 0)), Transparency = 1, CanCollide = false, CanQuery = false }, parent)
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Rate = 18
	e.Lifetime = NumberRange.new(h / 40, h / 30)
	e.Speed = NumberRange.new(30, 40)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 4) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(0.5, 0.75), NumberSequenceKeypoint.new(1, 1) })
	e.Color = ColorSequence.new(Color3.fromRGB(235, 245, 255))
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-60, 60)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.Parent = emitterPart
	local leaves = Instance.new("ParticleEmitter")
	leaves.Rate = 6
	leaves.Lifetime = NumberRange.new(h / 35, h / 28)
	leaves.Speed = NumberRange.new(28, 36)
	leaves.Size = NumberSequence.new(0.35)
	leaves.Color = ColorSequence.new(Color3.fromRGB(140, 180, 90), Color3.fromRGB(220, 190, 110))
	leaves.SpreadAngle = Vector2.new(8, 8)
	leaves.Rotation = NumberRange.new(0, 360)
	leaves.RotSpeed = NumberRange.new(-200, 200)
	leaves.Parent = emitterPart
	return col
end

-- Anneau de vent : traverser l'anneau donne un elan
local function windRing(parent, pos, facing, radius)
	radius = radius or 9
	local cf = CFrame.lookAt(pos, pos + facing)
	local m = Instance.new("Model")
	m.Name = "WindRing"
	for k = 0, 17 do
		local a = k / 18 * math.pi * 2
		part({ Size = Vector3.new(radius * 0.38, 0.6, 0.6), CFrame = cf * CFrame.new(math.cos(a) * radius, math.sin(a) * radius, 0) * CFrame.Angles(0, 0, a + math.pi / 2), Color = Color3.fromRGB(200, 240, 255), Material = Enum.Material.Neon, Transparency = 0.2, CanCollide = false, CanQuery = false }, m)
	end
	local center = part({ Name = "Center", Size = Vector3.new(1, 1, 1), CFrame = cf, Transparency = 1, CanCollide = false, CanQuery = false }, m)
	center:SetAttribute("Radius", radius)
	m.PrimaryPart = center
	m.Parent = parent
	CollectionService:AddTag(center, "WindRing")
end

-- Timbre cache (secret)
local function stampSpot(parent, pos, stampId)
	local p = part({ Name = "Stamp_" .. stampId, Size = Vector3.new(2.2, 2.8, 0.2), CFrame = CFrame.new(pos), Color = Color3.fromRGB(255, 240, 200), Material = Enum.Material.SmoothPlastic, CanCollide = false }, parent)
	label(p, Enum.NormalId.Front, "✉", Color3.fromRGB(200, 70, 60), 30)
	label(p, Enum.NormalId.Back, "✉", Color3.fromRGB(200, 70, 60), 30)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 220, 150)
	glow.Range = 10
	glow.Parent = p
	local sp = Instance.new("Sparkles")
	sp.SparkleColor = Color3.fromRGB(255, 230, 160)
	sp.Parent = p
	p:SetAttribute("StampId", stampId)
	CollectionService:AddTag(p, "StampSpot")
	TweenService:Create(p, TweenInfo.new(4, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { CFrame = p.CFrame * CFrame.Angles(0, math.rad(-359), 0) }):Play()
end

local function scatter(center, radius, count, fn, avoid)
	for k = 1, count do
		local a = R(0, math.pi * 2)
		local r = math.sqrt(R(0, 1)) * radius
		local p = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local ok = true
		for _, av in ipairs(avoid or {}) do
			if (Vector3.new(p.X, 0, p.Z) - Vector3.new(av[1].X, 0, av[1].Z)).Magnitude < av[2] then
				ok = false
				break
			end
		end
		if ok then
			fn(p)
		end
	end
end

-- Chemin de terre (terrain) entre deux points du dessus d'une ile
local function trail(a, b, width)
	local d = b - a
	local n = math.ceil(d.Magnitude / 4)
	for i = 0, n do
		local p = a + d * (i / n)
		Terrain:FillBlock(CFrame.new(p + Vector3.new(0, -1.9, 0)) * CFrame.Angles(0, math.atan2(d.X, d.Z), 0), Vector3.new(width, 4, 5), Enum.Material.Ground)
	end
end

-- Iles ------------------------------------------------------------------------------------------

local function buildPort(z)
	local f = folder("Port-Brise")
	local c = z.center
	local top = island(c, 120, 62, { patch = Enum.Material.LeafyGrass })
	local avoid = {}
	-- place pavee et poste
	Terrain:FillCylinder(CFrame.new(top + Vector3.new(0, -1.9, 0)), 4, 30, Enum.Material.Cobblestone)
	postOffice(f, CFrame.new(top + Vector3.new(0, 0, -6)) * CFrame.Angles(0, math.pi, 0))
	table.insert(avoid, { top, 34 })
	-- fontaine
	local fpos = top + Vector3.new(0, 0, 26)
	cyl(CFrame.new(fpos + Vector3.new(0, 0.8, 0)), 1.6, 6, STONE, Enum.Material.Cobblestone, f)
	local water = cyl(CFrame.new(fpos + Vector3.new(0, 1.4, 0)), 0.6, 5.4, Color3.fromRGB(70, 140, 170), Enum.Material.Glass, f)
	water.Transparency = 0.3
	cyl(CFrame.new(fpos + Vector3.new(0, 3, 0)), 3.5, 0.8, STONE, Enum.Material.Cobblestone, f)
	-- rues vers les quatre directions
	for _, d in ipairs({ Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }) do
		trail(top + d * 28, top + d * 108, 9)
		table.insert(avoid, { top + d * 68, 10 })
		for t = 40, 100, 20 do
			lampPost(f, top + d * t + Vector3.new(d.Z, 0, d.X) * 6)
		end
	end
	-- maisons + boites aux lettres
	local spots = {
		{ 45, 40 }, { 75, 30 }, { -45, 42 }, { -78, 25 }, { 45, -45 }, { 80, -38 }, { -50, -48 }, { -80, -30 }, { 20, 85 }, { -22, 82 },
	}
	for i, s in ipairs(spots) do
		local pos = top + Vector3.new(s[1], 0, s[2])
		local toCenter = (top - pos) * Vector3.new(1, 0, 1)
		local cf = CFrame.lookAt(pos, pos + toCenter)
		house(f, cf, R(12, 16), R(10, 13), rng:NextInteger(1, 2))
		mailbox(f, (cf * CFrame.new(5, 0, -10)).Position, toCenter, z.id, nextOwner())
		bush(f, (cf * CFrame.new(-5, 0, -8)).Position)
		table.insert(avoid, { pos, 14 })
	end
	-- tremplin d'envol au bord nord
	local edge = top + Vector3.new(0, 0, -112)
	local ramp = CFrame.lookAt(edge, edge + Vector3.new(0, 0, -1))
	wedge({ Size = Vector3.new(10, 3, 14), CFrame = ramp * CFrame.new(0, 1.5, 4) * CFrame.Angles(0, math.pi, 0), Color = WOOD_LIGHT, Material = Enum.Material.WoodPlanks }, f)
	part({ Size = Vector3.new(10, 3, 6), CFrame = ramp * CFrame.new(0, 1.5, -6), Color = WOOD_LIGHT, Material = Enum.Material.WoodPlanks }, f)
	for _, x in ipairs({ -5.5, 5.5 }) do
		local flagPole = part({ Size = Vector3.new(0.3, 10, 0.3), CFrame = ramp * CFrame.new(x, 5, -8), Color = Color3.fromRGB(230, 230, 230), Material = Enum.Material.Metal }, f)
		part({ Size = Vector3.new(0.1, 2, 3), CFrame = ramp * CFrame.new(x, 9, -6.5), Color = Color3.fromRGB(200, 60, 60), Material = Enum.Material.Fabric, CanCollide = false }, f)
	end
	local sign = part({ Size = Vector3.new(8, 2, 0.3), CFrame = ramp * CFrame.new(0, 4, 8) * CFrame.Angles(0, math.pi, 0), Color = Color3.fromRGB(40, 70, 110), Material = Enum.Material.Wood }, f)
	label(sign, Enum.NormalId.Front, "TREMPLIN - saute et ouvre ton planeur !", Color3.fromRGB(255, 225, 150))
	table.insert(avoid, { edge, 14 })
	-- phare a l'est (timbre secret sur la galerie)
	local lh = lighthouse(f, top + Vector3.new(102, 0, 52), 34)
	stampSpot(f, lh + Vector3.new(-3.5, 2, 0), "Sommet")
	table.insert(avoid, { top + Vector3.new(102, 0, 52), 10 })
	-- port en bas (sud) : quai + colonne de vent pour remonter
	dock(f, c + Vector3.new(0, 0, 150), Vector3.new(0, 0, 1), 30)
	updraft(f, c + Vector3.new(14, 1.5, 152), 9, 82, 55)
	updraft(f, c + Vector3.new(-152, 1.5, -10), 8, 80, 50)
	-- grotte secrete derriere une cascade (falaise ouest)
	local cave = c + Vector3.new(-121, 8, 40)
	Terrain:FillBall(cave + Vector3.new(6, 0, 0), 9, Enum.Material.Air)
	Terrain:FillBlock(CFrame.new(cave + Vector3.new(-4, -1, 0)), Vector3.new(16, 9, 8), Enum.Material.Air)
	stampSpot(f, cave + Vector3.new(9, -2, 0), "Grotte")
	local fallTop = c + Vector3.new(-126, 62, 40)
	local fall = part({ Size = Vector3.new(1.2, 60, 12), CFrame = CFrame.new(fallTop + Vector3.new(0, -30, 0)), Color = Color3.fromRGB(190, 225, 240), Material = Enum.Material.Glass, Transparency = 0.45, CanCollide = false }, f)
	local mist = Instance.new("ParticleEmitter")
	mist.Rate = 25
	mist.Lifetime = NumberRange.new(1, 2)
	mist.Speed = NumberRange.new(2, 5)
	mist.SpreadAngle = Vector2.new(80, 80)
	mist.Size = NumberSequence.new(3, 6)
	mist.Transparency = NumberSequence.new(0.6, 1)
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Parent = fall
	-- vegetation
	scatter(top, 110, 70, function(p)
		if rng:NextNumber() < 0.6 then
			tree(f, p, R(0.9, 1.3))
		else
			bush(f, p)
		end
	end, avoid)
	scatter(top, 100, 12, function(p)
		crate(f, p)
	end, avoid)
	return top
end

local function buildVerger(z)
	local f = folder("Le Verger")
	local c = z.center
	local top = island(c, 105, 30, { patch = Enum.Material.Ground })
	local avoid = {}
	postCounter(f, CFrame.new(top + Vector3.new(-12, 0, 0)) * CFrame.Angles(0, math.rad(90), 0), "Relais du Verger")
	table.insert(avoid, { top + Vector3.new(-12, 0, 0), 12 })
	windmill(f, top + Vector3.new(40, 0, -55), Vector3.new(-1, 0, 1))
	table.insert(avoid, { top + Vector3.new(40, 0, -55), 12 })
	-- vergers en rangees
	local fruits = { Color3.fromRGB(200, 40, 40), Color3.fromRGB(240, 160, 40), Color3.fromRGB(150, 200, 60) }
	for row = 0, 4 do
		for col = 0, 5 do
			local p = top + Vector3.new(-70 + col * 12, 0, 25 + row * 11)
			tree(f, p, R(0.8, 1), fruits[(row % 3) + 1])
		end
	end
	table.insert(avoid, { top + Vector3.new(-40, 0, 47), 40 })
	-- fermes
	local spots = { { 35, 20 }, { 65, 5 }, { 60, 45 }, { -30, -40 }, { -65, -20 }, { 10, -70 }, { 75, -20 } }
	for _, s in ipairs(spots) do
		local pos = top + Vector3.new(s[1], 0, s[2])
		if (pos - top).Magnitude < 92 then
			local dir = (top - pos) * Vector3.new(1, 0, 1)
			local cf = CFrame.lookAt(pos, pos + dir)
			house(f, cf, R(13, 17), R(11, 14), 1)
			mailbox(f, (cf * CFrame.new(5, 0, -10)).Position, dir, z.id, nextOwner())
			fence(f, (cf * CFrame.new(-9, 0, -9)).Position, (cf * CFrame.new(-9, 0, 9)).Position)
			table.insert(avoid, { pos, 15 })
		end
	end
	-- ruches (timbre a theme) et bottes de foin
	for k = 1, 5 do
		local p = top + Vector3.new(-80 + k * 5, 0, -10)
		part({ Size = Vector3.new(2.4, 3, 2.4), CFrame = CFrame.new(p + Vector3.new(0, 1.5, 0)), Color = Color3.fromRGB(230, 190, 90), Material = Enum.Material.WoodPlanks }, f)
		part({ Size = Vector3.new(3, 0.4, 3), CFrame = CFrame.new(p + Vector3.new(0, 3.2, 0)), Color = Color3.fromRGB(150, 110, 70), Material = Enum.Material.Wood }, f)
	end
	scatter(top, 90, 14, function(p)
		cyl(CFrame.new(p + Vector3.new(0, 1.3, 0)) * CFrame.Angles(math.rad(90), 0, 0), 3, 1.4, Color3.fromRGB(225, 195, 110), Enum.Material.Fabric, f)
	end, avoid)
	scatter(top, 95, 30, function(p)
		bush(f, p)
	end, avoid)
	dock(f, c + Vector3.new(-128, 0, 0), Vector3.new(-1, 0, 0), 26)
	updraft(f, c + Vector3.new(-136, 1.5, 22), 8, 60, 50)
	return top
end

local function buildFalaises(z)
	local f = folder("Falaises Brumeuses")
	local c = z.center
	local top = island(c, 95, 95, { top = Enum.Material.Grass, patch = Enum.Material.Rock })
	local avoid = {}
	postCounter(f, CFrame.new(top + Vector3.new(0, 0, 10)), "Relais des Falaises")
	table.insert(avoid, { top + Vector3.new(0, 0, 10), 12 })
	local spots = { { 40, 35 }, { -40, 40 }, { 55, -25 }, { -55, -20 }, { 0, -60 }, { 25, 65 } }
	for _, s in ipairs(spots) do
		local pos = top + Vector3.new(s[1], 0, s[2])
		local dir = (top - pos) * Vector3.new(1, 0, 1)
		local cf = CFrame.lookAt(pos, pos + dir)
		house(f, cf, R(11, 14), R(10, 12), rng:NextInteger(1, 2))
		mailbox(f, (cf * CFrame.new(5, 0, -10)).Position, dir, z.id, nextOwner())
		table.insert(avoid, { pos, 14 })
	end
	-- ruines et cercle de pierres
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		local p = top + Vector3.new(-30 + math.cos(a) * 11, 0, -55 + math.sin(a) * 11)
		part({ Size = Vector3.new(2.5, R(4, 8), 2), CFrame = CFrame.new(p + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, a, R(-0.1, 0.1)), Color = Color3.fromRGB(120, 120, 125), Material = Enum.Material.Slate }, f)
	end
	scatter(top, 85, 45, function(p)
		if rng:NextNumber() < 0.6 then
			pine(f, p, R(1, 1.5))
		else
			rockProp(f, p, R(0.8, 1.6))
		end
	end, avoid)
	-- brume permanente
	local mistBox = part({ Size = Vector3.new(190, 30, 190), CFrame = CFrame.new(top + Vector3.new(0, 10, 0)), Transparency = 1, CanCollide = false, CanQuery = false }, f)
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Rate = 22
	mist.Lifetime = NumberRange.new(8, 12)
	mist.Speed = NumberRange.new(0.5, 1.5)
	mist.Size = NumberSequence.new(14, 22)
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.82), NumberSequenceKeypoint.new(1, 1) })
	mist.Color = ColorSequence.new(Color3.fromRGB(220, 225, 235))
	mist.Shape = Enum.ParticleEmitterShape.Box
	mist.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	mist.Parent = mistBox
	dock(f, c + Vector3.new(0, 0, 120), Vector3.new(0, 0, 1), 24)
	updraft(f, c + Vector3.new(14, 1.5, 124), 9, 120, 60)
	return top
end

local function buildMarche(z)
	local f = folder("Marche Celeste")
	local c = z.center
	-- trois pitons relies par des ponts de corde
	local stacks = { c + Vector3.new(-45, 0, 0), c + Vector3.new(40, 0, -25), c + Vector3.new(15, 0, 50) }
	local tops = {}
	for i, s in ipairs(stacks) do
		tops[i] = island(s, 34, 105 + i * 6, { noBeach = i ~= 1 })
	end
	for i = 1, 3 do
		local a, b = tops[i], tops[(i % 3) + 1]
		local dir = (b - a) * Vector3.new(1, 0, 1)
		local p0 = a + dir.Unit * 30
		local p1 = b - dir.Unit * 30
		local n = math.floor((p1 - p0).Magnitude / 2.3)
		for k = 0, n do
			local t = k / n
			local p = p0:Lerp(p1, t) - Vector3.new(0, math.sin(t * math.pi) * 4 + 0.3, 0)
			part({ Size = Vector3.new(6, 0.4, 2), CFrame = CFrame.lookAt(p, p + dir), Color = WOOD_LIGHT, Material = Enum.Material.WoodPlanks }, f)
		end
		for _, side in ipairs({ -3.2, 3.2 }) do
			local off = Vector3.new(dir.Unit.Z, 0, -dir.Unit.X) * side
			for k = 0, n, 3 do
				local t = k / n
				local p = p0:Lerp(p1, t) - Vector3.new(0, math.sin(t * math.pi) * 4, 0) + off
				part({ Size = Vector3.new(0.25, 3, 0.25), CFrame = CFrame.new(p + Vector3.new(0, 1.2, 0)), Color = WOOD, Material = Enum.Material.Wood }, f)
			end
		end
	end
	local stallColors = { Color3.fromRGB(200, 60, 60), Color3.fromRGB(60, 110, 180), Color3.fromRGB(220, 170, 50), Color3.fromRGB(70, 150, 90) }
	for i, t in ipairs(tops) do
		if i == 1 then
			postCounter(f, CFrame.new(t + Vector3.new(0, 0, 8)), "Relais du Marche")
		end
		for k = 0, 2 do
			local a = k / 3 * math.pi * 2 + i
			local p = t + Vector3.new(math.cos(a) * 18, 0, math.sin(a) * 18)
			local cf = CFrame.lookAt(p, t)
			part({ Size = Vector3.new(7, 3, 3), CFrame = cf * CFrame.new(0, 1.5, 0), Color = WOOD, Material = Enum.Material.WoodPlanks }, f)
			for s = 0, 3 do
				wedge({ Size = Vector3.new(1.75, 1.2, 4), CFrame = cf * CFrame.new(-2.6 + s * 1.75, 7, -0.5) * CFrame.Angles(0, math.pi, 0), Color = (s % 2 == 0) and stallColors[(k + i) % 4 + 1] or Color3.fromRGB(240, 235, 225), Material = Enum.Material.Fabric, CanCollide = false }, f)
			end
			for _, x in ipairs({ -3.3, 3.3 }) do
				part({ Size = Vector3.new(0.3, 6.5, 0.3), CFrame = cf * CFrame.new(x, 3.25, 1.2), Color = WOOD, Material = Enum.Material.Wood }, f)
			end
			local lantern = part({ Size = Vector3.new(0.8, 1, 0.8), CFrame = cf * CFrame.new(0, 6, 0.8), Color = Color3.fromRGB(255, 200, 120), Material = Enum.Material.Neon }, f)
			local l = Instance.new("PointLight")
			l.Range = 12
			l.Color = Color3.fromRGB(255, 190, 120)
			l.Parent = lantern
		end
		for k = 1, 3 do
			local a = k * 2.1 + i * 0.7
			local p = t + Vector3.new(math.cos(a) * 25, 0, math.sin(a) * 25)
			mailbox(f, p, (t - p) * Vector3.new(1, 0, 1), z.id, nextOwner())
		end
		barrel(f, t + Vector3.new(-6, 0, -12))
		crate(f, t + Vector3.new(7, 0, -11))
	end
	updraft(f, stacks[1] + Vector3.new(-60, 1.5, 0), 9, 135, 60)
	dock(f, stacks[1] + Vector3.new(-62, 0, 14), Vector3.new(-1, 0, 0), 20)
	return tops[1]
end

local function buildPic(z)
	local f = folder("Pic des Tempetes")
	local c = z.center
	-- montagne : cylindres de plus en plus etroits, neige au sommet
	local h = 0
	local layers = { { 90, 40 }, { 70, 40 }, { 52, 35 }, { 36, 30 }, { 24, 25 } }
	for i, L in ipairs(layers) do
		Terrain:FillCylinder(CFrame.new(c + Vector3.new(R(-3, 3), h + L[2] / 2, R(-3, 3))), L[2], L[1], Enum.Material.Rock)
		Terrain:FillCylinder(CFrame.new(c + Vector3.new(0, h + L[2] - 1, 0)), 3, L[1] - 3, i >= 4 and Enum.Material.Snow or Enum.Material.Grass)
		h += L[2]
	end
	Terrain:FillCylinder(CFrame.new(c + Vector3.new(0, -26, 0)), 52, 120, Enum.Material.Sand)
	Terrain:FillCylinder(CFrame.new(c + Vector3.new(0, 0.5, 0)), 3, 110, Enum.Material.Sand)
	local top = c + Vector3.new(0, h, 0)
	-- observatoire au sommet
	cyl(CFrame.new(top + Vector3.new(0, 5, 0)), 10, 9, Color3.fromRGB(230, 230, 235), Enum.Material.Concrete, f)
	local dome = ball(top + Vector3.new(0, 10, 0), 18, Color3.fromRGB(190, 195, 205), Enum.Material.Metal, f)
	dome.Reflectance = 0.2
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(10, 2, 2), CFrame = CFrame.new(top + Vector3.new(4, 15, 0)) * CFrame.Angles(0, 0, math.rad(35)), Color = Color3.fromRGB(60, 60, 70), Material = Enum.Material.Metal }, f)
	postCounter(f, CFrame.new(top + Vector3.new(0, 0, 16)), "Relais du Pic")
	-- refuges sur les replats
	local ledges = { { 1, 0 }, { 2, 1.6 }, { 3, 3.2 }, { 2, 4.4 }, { 1, 5.5 } }
	local hh = 0
	local heights = {}
	for i, L in ipairs(layers) do
		hh += L[2]
		heights[i] = hh
	end
	for i, L in ipairs(ledges) do
		local li = L[1]
		local r = layers[li + 1][1] + (layers[li][1] - layers[li + 1][1]) / 2
		local p = c + Vector3.new(math.cos(L[2]) * r, heights[li], math.sin(L[2]) * r)
		local dir = (c - p) * Vector3.new(1, 0, 1)
		local cf = CFrame.lookAt(p, p + dir) * CFrame.Angles(0, math.pi, 0)
		house(f, cf * CFrame.new(0, 0, 3), 10, 9, 1)
		mailbox(f, (cf * CFrame.new(6, 0, -5)).Position, -dir, z.id, nextOwner())
	end
	for k = 1, 30 do
		local a = R(0, math.pi * 2)
		pine(f, c + Vector3.new(math.cos(a) * R(72, 86), 40, math.sin(a) * R(72, 86)), R(1, 1.6))
	end
	updraft(f, c + Vector3.new(-118, 1.5, 0), 10, 200, 70)
	updraft(f, c + Vector3.new(0, 1.5, 116), 9, 150, 60)
	dock(f, c + Vector3.new(-125, 0, 15), Vector3.new(-1, 0, 0), 20)
	-- neige qui vole
	local box = part({ Size = Vector3.new(120, 60, 120), CFrame = CFrame.new(top + Vector3.new(0, 0, 0)), Transparency = 1, CanCollide = false, CanQuery = false }, f)
	local snow = Instance.new("ParticleEmitter")
	snow.Rate = 60
	snow.Lifetime = NumberRange.new(4, 6)
	snow.Speed = NumberRange.new(8, 14)
	snow.EmissionDirection = Enum.NormalId.Right
	snow.Size = NumberSequence.new(0.25)
	snow.Color = ColorSequence.new(Color3.new(1, 1, 1))
	snow.Shape = Enum.ParticleEmitterShape.Box
	snow.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	snow.Parent = box
	return top
end

-- Routes aeriennes : thermiques en mer + anneaux de vent entre les iles
local function airRoutes()
	local f = folder("Routes du vent")
	local thermals = {
		{ Vector3.new(170, 0, -55), 120 }, { Vector3.new(-160, 0, -120), 140 }, { Vector3.new(200, 0, -340), 150 },
		{ Vector3.new(-140, 0, -420), 150 }, { Vector3.new(290, 0, -500), 210 }, { Vector3.new(-420, 0, 40), 140 },
	}
	for _, t in ipairs(thermals) do
		seaStack(t[1], 9, R(10, 18))
		updraft(f, t[1] + Vector3.new(0, R(24, 30), 0), 12, t[2], 55)
	end
	local rings = {
		{ Vector3.new(80, 60, -30), Vector3.new(1, -0.1, -0.4) }, { Vector3.new(250, 70, -90), Vector3.new(1, 0, -0.1) },
		{ Vector3.new(-80, 60, -60), Vector3.new(-1, -0.1, -0.5) }, { Vector3.new(-240, 90, -180), Vector3.new(-1, 0, -0.6) },
		{ Vector3.new(120, 110, -420), Vector3.new(0.3, 0, -1) }, { Vector3.new(380, 160, -520), Vector3.new(1, 0, -0.3) },
		{ Vector3.new(0, 75, -180), Vector3.new(0, -0.1, -1) }, { Vector3.new(0, 90, -330), Vector3.new(0.1, 0, -1) },
	}
	for _, r in ipairs(rings) do
		windRing(f, r[1], r[2])
	end
	-- secrets en mer : epave sur un banc de sable, ilot oublie
	local wreck = Vector3.new(250, 0, 250)
	Terrain:FillCylinder(CFrame.new(wreck + Vector3.new(0, -1, 0)), 6, 28, Enum.Material.Sand)
	local hull = CFrame.new(wreck + Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0.6, math.rad(14))
	part({ Size = Vector3.new(9, 5, 26), CFrame = hull, Color = Color3.fromRGB(85, 60, 40), Material = Enum.Material.WoodPlanks }, f)
	part({ Size = Vector3.new(7, 0.6, 22), CFrame = hull * CFrame.new(0, 2.6, 0), Color = Color3.fromRGB(110, 80, 55), Material = Enum.Material.WoodPlanks }, f)
	part({ Size = Vector3.new(0.8, 16, 0.8), CFrame = hull * CFrame.new(0, 10, 2) * CFrame.Angles(0.3, 0, 0), Color = Color3.fromRGB(85, 60, 40), Material = Enum.Material.Wood }, f)
	stampSpot(f, (hull * CFrame.new(0, 4.5, -6)).Position, "Epave")
	dock(f, wreck + Vector3.new(0, 0, 24), Vector3.new(0, 0, 1), 8)
	local islet = Vector3.new(-600, 0, 160)
	island(islet, 22, 18, {})
	local lone = islet + Vector3.new(0, 18, 0)
	tree(f, lone + Vector3.new(6, 0, 4), 1.3, Color3.fromRGB(240, 200, 60))
	local golden = mailbox(f, lone + Vector3.new(-4, 0, 0), Vector3.new(1, 0, 0), "Secret", "???")
	for _, p in ipairs(golden:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "Pad" then
			p.Color = Color3.fromRGB(230, 185, 60)
			p.Reflectance = 0.3
		end
	end
	CollectionService:RemoveTag(golden, "Mailbox")
	golden.PrimaryPart:FindFirstChildOfClass("ProximityPrompt"):Destroy()
	stampSpot(f, lone + Vector3.new(-4, 7.5, 0), "Ilot")
end

-- Construction ----------------------------------------------------------------------------------

function WorldBuilder.Build()
	local old = workspace:FindFirstChild("Windmail")
	if old then
		old:Destroy()
	end
	Terrain:Clear()
	root = Instance.new("Folder")
	root.Name = "Windmail"
	root.Parent = workspace
	lighting()
	sea()
	local builders = { Port = buildPort, Verger = buildVerger, Falaises = buildFalaises, Marche = buildMarche, Pic = buildPic }
	for _, z in ipairs(Config.Zones) do
		local ok, err = pcall(builders[z.id], z)
		if not ok then
			warn("[Windmail] Construction de " .. z.name .. " : " .. tostring(err))
		end
		task.wait()
	end
	local ok, err = pcall(airRoutes)
	if not ok then
		warn("[Windmail] Routes du vent : " .. tostring(err))
	end
	-- point d'apparition sur la place de Port-Brise
	for _, s in ipairs(workspace:GetDescendants()) do
		if s:IsA("SpawnLocation") then
			s:Destroy()
		end
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(Config.SpawnPosition - Vector3.new(0, 3.5, 0))
	spawn.Anchored = true
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = root
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
end

return WorldBuilder
