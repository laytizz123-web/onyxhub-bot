-- Monde de PET RUSH : 8 iles flottantes cartoon reliees par des ponts en boucle.
-- Starter Village (grand village de depart), puis Forest, Desert, Beach, Candy Land, Snow Peaks,
-- Mystic Zone et Pet Kingdom. Chaque passage est ferme par une porte magique payante (tag Gate).
-- Decor d'arriere-plan : iles lointaines, montgolfieres, nuages, mer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local Kit = require(script.Parent.MapKit)
local MapZones = require(script.Parent.MapZones)

local MapBuilder = {}

local Terrain = workspace.Terrain
local rng, R = Kit.rng, Kit.R
local part, wedge, ballPart, cylinder, sign, stand = Kit.part, Kit.wedge, Kit.ball, Kit.cylinder, Kit.sign, Kit.stand
local avoidCircle = Kit.avoidCircle
local WHITE = Color3.new(1, 1, 1)

-- Eclairage ------------------------------------------------------------------------------

local function buildLighting()
	Lighting.ClockTime = 14
	Lighting.GeographicLatitude = 30
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(140, 140, 160)
	Lighting.OutdoorAmbient = Color3.fromRGB(165, 165, 185)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.ShadowSoftness = 0.5
	Lighting.GlobalShadows = true
	Lighting.FogEnd = 100000
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.18
	atmosphere.Offset = 0
	atmosphere.Color = Color3.fromRGB(170, 215, 255)
	atmosphere.Decay = Color3.fromRGB(120, 180, 255)
	atmosphere.Glare = 0
	atmosphere.Haze = 0
	atmosphere.Parent = Lighting
	local sky = Instance.new("Sky")
	sky.SunAngularSize = 12
	sky.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.25
	bloom.Size = 18
	bloom.Threshold = 1.8
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "PetColor"
	cc.Saturation = 0.22
	cc.Contrast = 0.05
	cc.Brightness = 0.03
	cc.Parent = Lighting
	local clouds = Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.45
	clouds.Density = 0.5
	clouds.Color = Color3.new(1, 1, 1)
	clouds.Parent = Terrain
end


-- Iles --------------------------------------------------------------------------------------

local PALETTES = {
	Village = { top = Color3.fromRGB(125, 215, 85), drip = Color3.fromRGB(105, 195, 70), dirt = Color3.fromRGB(165, 110, 65), dirt2 = Color3.fromRGB(135, 88, 52), path = Color3.fromRGB(245, 225, 175) },
	Foret = { top = Color3.fromRGB(85, 180, 80), drip = Color3.fromRGB(65, 155, 65), dirt = Color3.fromRGB(130, 92, 62), dirt2 = Color3.fromRGB(105, 74, 50), path = Color3.fromRGB(205, 165, 110) },
	Desert = { top = Color3.fromRGB(252, 222, 150), drip = Color3.fromRGB(240, 200, 120), dirt = Color3.fromRGB(225, 155, 90), dirt2 = Color3.fromRGB(195, 128, 75), path = Color3.fromRGB(235, 185, 115) },
	Plage = { top = Color3.fromRGB(255, 228, 165), drip = Color3.fromRGB(245, 212, 140), dirt = Color3.fromRGB(225, 170, 110), dirt2 = Color3.fromRGB(200, 145, 90), path = Color3.fromRGB(255, 242, 210) },
	Bonbons = { top = Color3.fromRGB(255, 175, 215), drip = Color3.fromRGB(255, 145, 200), dirt = Color3.fromRGB(165, 100, 70), dirt2 = Color3.fromRGB(135, 78, 52), path = Color3.fromRGB(255, 245, 250) },
	Neige = { top = Color3.fromRGB(245, 250, 255), drip = Color3.fromRGB(225, 238, 255), dirt = Color3.fromRGB(150, 175, 210), dirt2 = Color3.fromRGB(120, 145, 185), path = Color3.fromRGB(200, 222, 245) },
	Mystique = { top = Color3.fromRGB(150, 110, 230), drip = Color3.fromRGB(125, 90, 210), dirt = Color3.fromRGB(85, 65, 125), dirt2 = Color3.fromRGB(65, 50, 100), path = Color3.fromRGB(205, 175, 255) },
	Royaume = { top = Color3.fromRGB(130, 215, 95), drip = Color3.fromRGB(110, 195, 80), dirt = Color3.fromRGB(220, 205, 180), dirt2 = Color3.fromRGB(190, 172, 145), path = Color3.fromRGB(250, 238, 200) },
}

-- direction (axe X ou Z) d'une zone vers une autre
local function dirTo(a, b)
	local d = b.center - a.center
	if math.abs(d.X) > math.abs(d.Z) then
		return Vector3.new(math.sign(d.X), 0, 0)
	end
	return Vector3.new(0, 0, math.sign(d.Z))
end

-- sorties d'une zone : liste de directions vers ses voisines (precedente / suivante)
local function exitsOf(index)
	local zone = Config.Zones[index]
	local list = {}
	for _, j in ipairs({ index - 1, index + 1 }) do
		local other = Config.Zones[j]
		if other then
			table.insert(list, { dir = dirTo(zone, other), zone = other, next = j > index })
		end
	end
	return list
end

local function waterfall(parent, edgePoint, outward)
	local inward = -outward
	local cf = CFrame.lookAt(edgePoint, edgePoint + outward)
	local stream = part({ Size = Vector3.new(9, 0.3, 26), CFrame = cf * CFrame.new(0, 0.14, 13), Color = Kit.WATER, Material = Enum.Material.Glass, Transparency = 0.1, CanCollide = false }, parent)
	stream.Reflectance = 0.15
	part({ Size = Vector3.new(9, 90, 1.5), CFrame = cf * CFrame.new(0, -45, -1), Color = Color3.fromRGB(150, 215, 255), Material = Enum.Material.Glass, Transparency = 0.15, CanCollide = false }, parent)
	local foam = part({ Size = Vector3.new(9, 2, 2), CFrame = cf * CFrame.new(0, 0, -1), Transparency = 1, CanCollide = false }, parent)
	local spray = Instance.new("ParticleEmitter")
	spray.Rate = 40
	spray.Lifetime = NumberRange.new(0.6, 1)
	spray.Speed = NumberRange.new(4, 8)
	spray.SpreadAngle = Vector2.new(60, 60)
	spray.Acceleration = Vector3.new(0, -20, 0)
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.4) })
	spray.Transparency = NumberSequence.new(0.2, 1)
	spray.Color = ColorSequence.new(WHITE)
	spray.Parent = foam
	Kit.avoidSegment(edgePoint, edgePoint + inward * 28, 8)
end

-- Ile : dessus d'herbe, bord festonne, falaises en escalier, rochers suspendus, collines, chemins
local function island(parent, zone, index)
	local pal = PALETTES[zone.id]
	local c = zone.center
	local s = zone.size
	local half = s / 2
	part({ Name = "Ground", Size = Vector3.new(s, 4, s), CFrame = CFrame.new(c + Vector3.new(0, -2, 0)), Color = pal.top }, parent)
	for t = -half, half, 9 do
		for _, edge in ipairs({ Vector3.new(t, -2.6, half), Vector3.new(t, -2.6, -half), Vector3.new(half, -2.6, t), Vector3.new(-half, -2.6, t) }) do
			local drip = ballPart(CFrame.new(c + edge), R(5.5, 7.5), pal.drip, parent)
			drip.CanCollide = false
		end
	end
	local y = -4
	local layers = { { s - 2, 9, pal.dirt }, { s - 20, 11, pal.dirt2 }, { s - 52, 13, pal.dirt }, { s - 100, 14, pal.dirt2 }, { s - 160, 12, pal.dirt }, { s - 220, 10, pal.dirt2 } }
	for _, L in ipairs(layers) do
		if L[1] > 20 then
			part({ Name = "Cliff", Size = Vector3.new(L[1], L[2], L[1]), CFrame = CFrame.new(c + Vector3.new(0, y - L[2] / 2, 0)), Color = L[3] }, parent)
			part({ Name = "CliffBand", Size = Vector3.new(L[1] + 0.4, 1.2, L[1] + 0.4), CFrame = CFrame.new(c + Vector3.new(0, y - L[2] * 0.35, 0)), Color = L[3]:Lerp(WHITE, 0.15), CanCollide = false }, parent)
			y -= L[2]
		end
	end
	for k = 1, 12 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = R(20, half - 50)
		ballPart(CFrame.new(c + Vector3.new(math.cos(a) * r, y - R(0, 10), math.sin(a) * r)), R(8, 18), pal.dirt2, parent)
	end
	-- chemins : de chaque sortie jusqu'a la place centrale de la zone
	local exits = exitsOf(index)
	if index == 1 then
		table.insert(exits, { dir = Vector3.new(0, 0, 1) }) -- avenue du spawn
	end
	for _, e in ipairs(exits) do
		local a = c + e.dir * half
		local mid = (a + c) / 2
		local cf = CFrame.lookAt(mid + Vector3.new(0, 0.1, 0), c + Vector3.new(0, 0.1, 0))
		part({ Name = "Path", Size = Vector3.new(16, 0.2, half), CFrame = cf, Color = pal.path, CanCollide = false }, parent)
		for _, x in ipairs({ -8.6, 8.6 }) do
			part({ Name = "PathEdge", Size = Vector3.new(1.2, 0.35, half), CFrame = cf * CFrame.new(x, 0.05, 0), Color = pal.path:Lerp(Color3.new(0, 0, 0), 0.12), CanCollide = false }, parent)
		end
		for t = 6, half - 6, 7 do
			part({ Name = "PathStone", Size = Vector3.new(R(2.5, 4), 0.25, R(2, 3)), CFrame = cf * CFrame.new(R(-5, 5), 0.08, -half / 2 + t) * CFrame.Angles(0, R(0, 3), 0), Color = pal.path:Lerp(WHITE, 0.35), CanCollide = false }, parent)
		end
		Kit.avoidSegment(a, c, 11)
	end
	-- place centrale ronde
	local plaza = cylinder(CFrame.new(c + Vector3.new(0, 0.12, 0)), 0.25, 26, pal.path, parent)
	plaza.CanCollide = false
	local ring = cylinder(CFrame.new(c + Vector3.new(0, 0.1, 0)), 0.25, 27.5, pal.path:Lerp(Color3.new(0, 0, 0), 0.12), parent)
	ring.CanCollide = false
	avoidCircle(c, 30)
	-- cascade sur un cote sans pont
	local used = {}
	for _, e in ipairs(exits) do
		used[tostring(e.dir)] = true
	end
	for _, d in ipairs({ Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }) do
		if not used[tostring(d)] then
			local side = Vector3.new(d.Z, 0, d.X)
			waterfall(parent, c + d * half + side * (index == 1 and 70 or R(-60, 60)), d)
			break
		end
	end
end

-- Collines douces posees apres le decor, sur les espaces encore libres
local function hills(parent, zone)
	local pal = PALETTES[zone.id]
	local c = zone.center
	local half = zone.size / 2
	for k = 1, 8 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = R(60, half - 22)
		local pos = c + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local size = R(18, 30)
		if Kit.isFree(pos, size / 2) then
			local mound = ballPart(CFrame.new(pos), size, pal.top:Lerp(Color3.new(0, 0, 0), 0.05), parent)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Scale = Vector3.new(1, 0.3, 1)
			mesh.Parent = mound
			avoidCircle(pos, size / 2 + 2)
		end
	end
end

-- Pont entre deux iles (planches, cordes, lanternes)
local function bridge(parent, a, b)
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt((a + b) / 2, b)
	local count = math.floor(len / 2.2)
	for k = 0, count do
		local z = -len / 2 + 1.1 + k * (len / (count + 1))
		part({ Name = "Plank", Size = Vector3.new(16, 0.8, 2), CFrame = cf * CFrame.new(0, -0.4, z) * CFrame.Angles(0, math.rad(R(-1.5, 1.5)), 0), Color = (k % 2 == 0) and Color3.fromRGB(205, 145, 85) or Color3.fromRGB(185, 125, 70) }, parent)
	end
	for _, x in ipairs({ -6.5, 6.5 }) do
		part({ Name = "Beam", Size = Vector3.new(1, 1, len), CFrame = cf * CFrame.new(x, -1.2, 0), Color = Color3.fromRGB(140, 90, 55) }, parent)
	end
	for _, x in ipairs({ -8.3, 8.3 }) do
		for z = -len / 2, len / 2, 12 do
			part({ Name = "Post", Size = Vector3.new(0.9, 4.5, 0.9), CFrame = cf * CFrame.new(x, 1.8, z), Color = Color3.fromRGB(150, 100, 60) }, parent)
			local bulb = ballPart(cf * CFrame.new(x, 4.4, z), 1.3, Color3.fromRGB(255, 215, 120), parent, Enum.Material.Neon)
			if math.floor(z) % 24 == 0 then
				local l = Instance.new("PointLight")
				l.Range = 10
				l.Color = Color3.fromRGB(255, 210, 140)
				l.Parent = bulb
			end
		end
		part({ Name = "Rope", Size = Vector3.new(0.35, 0.35, len), CFrame = cf * CFrame.new(x, 3.6, 0), Color = Color3.fromRGB(240, 220, 180), CanCollide = false }, parent)
	end
	-- petits fanions colores
	local flags = { Color3.fromRGB(255, 90, 120), Color3.fromRGB(255, 210, 60), Color3.fromRGB(90, 190, 255), Color3.fromRGB(130, 220, 100) }
	for k, z in ipairs({ -len / 4, len / 4 }) do
		for i = -7, 7, 2 do
			wedge({ Size = Vector3.new(0.1, 1.4, 1.2), CFrame = cf * CFrame.new(i, 9 - math.abs(i) * 0.15, z) * CFrame.Angles(math.rad(180), math.rad(90), 0), Color = flags[((i + 9) % #flags) + 1], CanCollide = false }, parent)
		end
		for _, x in ipairs({ -8.3, 8.3 }) do
			part({ Size = Vector3.new(0.5, 10, 0.5), CFrame = cf * CFrame.new(x, 5, z), Color = Color3.fromRGB(150, 100, 60) }, parent)
		end
		part({ Size = Vector3.new(16.6, 0.15, 0.15), CFrame = cf * CFrame.new(0, 9.6, z), Color = WHITE, CanCollide = false }, parent)
	end
end

-- Arche de pierre + barriere magique (tag Gate), orientee vers la zone suivante
local function gateArch(parent, pos, dir, nextZone)
	local cf = CFrame.lookAt(pos, pos + dir)
	local stone = Color3.fromRGB(175, 170, 180)
	for _, x in ipairs({ -12, 12 }) do
		part({ Size = Vector3.new(5, 20, 5), CFrame = cf * CFrame.new(x, 10, 0), Color = stone, Material = Enum.Material.Cobblestone }, parent)
		part({ Size = Vector3.new(6.4, 1.6, 6.4), CFrame = cf * CFrame.new(x, 0.8, 0), Color = stone:Lerp(Color3.new(0, 0, 0), 0.15), Material = Enum.Material.Cobblestone }, parent)
		ballPart(cf * CFrame.new(x, 21.6, 0), 3.2, Config.Colors.Gold, parent, Enum.Material.Neon)
	end
	part({ Size = Vector3.new(30, 4, 6), CFrame = cf * CFrame.new(0, 21, 0), Color = stone, Material = Enum.Material.Cobblestone }, parent)
	sign(parent, cf * CFrame.new(0, 21, 3.3), Vector3.new(22, 3, 0.4), nextZone.icon .. " " .. string.upper(nextZone.name), Config.Colors.Gold, Color3.fromRGB(60, 50, 80))
	local barrier = part({ Name = "Gate", Size = Vector3.new(19, 19, 1), CFrame = cf * CFrame.new(0, 9.5, 0), Color = Color3.fromRGB(120, 200, 255), Material = Enum.Material.ForceField, Transparency = 0.2 }, parent)
	barrier:SetAttribute("ZoneId", nextZone.id)
	CollectionService:AddTag(barrier, "Gate")
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Debloquer (" .. nextZone.price .. ")"
	prompt.ObjectText = nextZone.name
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = barrier
	Kit.avoidSegment(pos, pos - dir * 20, 14)
end

-- Murs invisibles autour de l'ile avec ouvertures vers les ponts
local function walls(parent, zone, index)
	local c = zone.center
	local half = zone.size / 2
	local h = 80
	local openings = {}
	for _, e in ipairs(exitsOf(index)) do
		openings[tostring(e.dir)] = e
	end
	for _, d in ipairs({ Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }) do
		local center = c + d * half + Vector3.new(0, h / 2, 0)
		local cf = CFrame.lookAt(center, center + d)
		if openings[tostring(d)] then
			local seg = (zone.size - 26) / 2
			part({ Size = Vector3.new(seg, h, 2), CFrame = cf * CFrame.new(-(13 + seg / 2), 0, 0), Transparency = 1 }, parent)
			part({ Size = Vector3.new(seg, h, 2), CFrame = cf * CFrame.new(13 + seg / 2, 0, 0), Transparency = 1 }, parent)
			local e = openings[tostring(d)]
			if e.next then
				-- couloir le long du pont
				local other = e.zone
				local b = other.center - d * (other.size / 2)
				local a = c + d * half
				local mid = (a + b) / 2 + Vector3.new(0, h / 2, 0)
				local ccf = CFrame.lookAt(mid, mid + (b - a))
				for _, x in ipairs({ -13, 13 }) do
					part({ Size = Vector3.new(2, h, (b - a).Magnitude), CFrame = ccf * CFrame.new(x, 0, 0), Transparency = 1 }, parent)
				end
			end
		else
			part({ Size = Vector3.new(zone.size, h, 2), CFrame = cf, Transparency = 1 }, parent)
		end
	end
end

local coinSpots = {}

local function computeCoinSpots(zone)
	local half = zone.size / 2
	coinSpots[zone.id] = {}
	local tries = 0
	while #coinSpots[zone.id] < zone.coinCount and tries < 4000 do
		tries += 1
		local pos = zone.center + Vector3.new(R(-half + 22, half - 22), 2.2, R(-half + 22, half - 22))
		if Kit.isFree(pos, 2) then
			table.insert(coinSpots[zone.id], pos)
			avoidCircle(pos, 3) -- pas de decor pose sur un coin
		end
	end
end

-- Starter Village ------------------------------------------------------------------------------

local raceWaypoints = {}

local function buildRaceTrack(root, center)
	local rx, rz = 36, 22
	local n = 28
	for i = 0, n - 1 do
		local a = (i / n) * math.pi * 2
		table.insert(raceWaypoints, center + Vector3.new(math.cos(a) * rx, 1.2, math.sin(a) * rz))
	end
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


local function buildVillage(folder, zone)
	local c = zone.center
	local spawnPos = Config.Map.SpawnPosition
	local pal = PALETTES.Village

	-- Spawn
	local existing = workspace:FindFirstChildOfClass("SpawnLocation")
	if existing then
		existing:Destroy()
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "MainSpawn"
	spawn.Shape = Enum.PartType.Cylinder
	spawn.Size = Vector3.new(0.6, 16, 16)
	spawn.CFrame = CFrame.new(spawnPos.X, 0.3, spawnPos.Z) * CFrame.Angles(0, 0, math.rad(90))
	spawn.Anchored = true
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Color = Color3.fromRGB(120, 210, 255)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder
	local ring = cylinder(CFrame.new(spawnPos.X, 0.4, spawnPos.Z), 0.4, 8.5, WHITE, folder, Enum.Material.Neon)
	ring.CanCollide = false
	ring.Transparency = 0.4
	-- place du spawn pavee + fleurs
	cylinder(CFrame.new(spawnPos.X, 0.1, spawnPos.Z), 0.2, 24, pal.path, folder).CanCollide = false
	avoidCircle(Vector3.new(spawnPos.X, 0, spawnPos.Z), 26)
	for _, x in ipairs({ -1, 1 }) do
		Kit.flowerBed(folder, Vector3.new(spawnPos.X + x * 30, 0, spawnPos.Z + 6), 6)
		Kit.statue(folder, Vector3.new(spawnPos.X + x * 22, 0, spawnPos.Z - 26), x > 0 and "egg" or "paw")
	end

	-- Grande entree : arche "PET RUSH" sur l'avenue
	Kit.archway(folder, CFrame.new(c + Vector3.new(0, 0, 112)) * CFrame.Angles(0, math.pi, 0), 30, 16, Color3.fromRGB(250, 245, 255), "PET RUSH", Color3.fromRGB(255, 210, 60))
	for _, x in ipairs({ -1, 1 }) do
		Kit.hedge(folder, c + Vector3.new(x * 19, 0, 112), c + Vector3.new(x * 60, 0, 112), 3.4)
		Kit.lantern(folder, c + Vector3.new(x * 20, 0, 104))
	end

	-- Avenue : lanternes + echoppes du marche
	for z = 20, 190, 20 do
		for _, x in ipairs({ -11, 11 }) do
			if math.abs(z - 112) > 8 then
				Kit.lantern(folder, c + Vector3.new(x, 0, z))
			end
		end
	end
	for z = -180, -40, 20 do
		for _, x in ipairs({ -11, 11 }) do
			Kit.lantern(folder, c + Vector3.new(x, 0, z))
		end
	end
	local k = 0
	for _, z in ipairs({ 58, 76, 94 }) do
		for _, x in ipairs({ -1, 1 }) do
			k += 1
			Kit.stall(folder, CFrame.lookAt(c + Vector3.new(x * 22, 0, z), c + Vector3.new(0, 0, z)), k)
		end
	end

	-- Grande place centrale : fontaine monumentale, parterres, bancs, panneau des zones
	local plaza = cylinder(CFrame.new(c + Vector3.new(0, 0.14, 0)), 0.25, 44, Color3.fromRGB(240, 232, 215), folder)
	plaza.CanCollide = false
	for r = 12, 40, 14 do
		local band = cylinder(CFrame.new(c + Vector3.new(0, 0.16, 0)), 0.25, r, (r % 28 == 12) and Color3.fromRGB(225, 205, 170) or Color3.fromRGB(245, 238, 222), folder)
		band.CanCollide = false
	end
	cylinder(CFrame.new(c + Vector3.new(0, 1, 0)), 2, 14, Color3.fromRGB(235, 235, 240), folder, Enum.Material.Marble)
	local water = cylinder(CFrame.new(c + Vector3.new(0, 1.8, 0)), 0.6, 13, Kit.WATER, folder, Enum.Material.Glass)
	water.Transparency = 0.25
	water.CanCollide = false
	cylinder(CFrame.new(c + Vector3.new(0, 4.5, 0)), 6, 2.2, Color3.fromRGB(235, 235, 240), folder, Enum.Material.Marble)
	cylinder(CFrame.new(c + Vector3.new(0, 7.8, 0)), 0.8, 6.5, Color3.fromRGB(235, 235, 240), folder, Enum.Material.Marble)
	local w2 = cylinder(CFrame.new(c + Vector3.new(0, 8.3, 0)), 0.4, 6, Kit.WATER, folder, Enum.Material.Glass)
	w2.Transparency = 0.25
	w2.CanCollide = false
	-- oeuf dore geant au sommet
	local egg = ballPart(CFrame.new(c + Vector3.new(0, 13, 0)), 7, Config.Colors.Gold, folder, Enum.Material.Metal)
	egg.Reflectance = 0.3
	local em = Instance.new("SpecialMesh")
	em.MeshType = Enum.MeshType.Sphere
	em.Scale = Vector3.new(1, 1.3, 1)
	em.Parent = egg
	local sp = Instance.new("Sparkles")
	sp.SparkleColor = Config.Colors.Gold
	sp.Parent = egg
	local jet = part({ Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(c + Vector3.new(0, 9, 0)), Transparency = 1, CanCollide = false }, folder)
	local spray = Instance.new("ParticleEmitter")
	spray.Rate = 70
	spray.Lifetime = NumberRange.new(1, 1.4)
	spray.Speed = NumberRange.new(12, 16)
	spray.SpreadAngle = Vector2.new(35, 35)
	spray.Acceleration = Vector3.new(0, -40, 0)
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.9) })
	spray.Transparency = NumberSequence.new(0.2, 1)
	spray.Color = ColorSequence.new(Color3.fromRGB(200, 235, 255))
	spray.Parent = jet
	avoidCircle(c, 46)
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		Kit.flowerBed(folder, c + Vector3.new(math.cos(a) * 28, 0, math.sin(a) * 28), 5)
		Kit.bench(folder, CFrame.lookAt(c + Vector3.new(math.cos(a) * 20, 0, math.sin(a) * 20), c))
	end
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2 + 0.26
		Kit.lantern(folder, c + Vector3.new(math.cos(a) * 41, 0, math.sin(a) * 41))
	end
	local entries = {}
	for _, z in ipairs(Config.Zones) do
		if z.id ~= "Village" then
			table.insert(entries, { text = z.icon .. " " .. z.name, dir = z.center - c, color = z.ground:Lerp(Color3.new(0, 0, 0), 0.25) })
		end
	end
	Kit.signpost(folder, c + Vector3.new(14, 0, 36), { entries[1], entries[2], entries[3], entries[4] })
	Kit.signpost(folder, c + Vector3.new(-14, 0, 36), { entries[5], entries[6], entries[7] })

	-- Rue est-ouest vers les belvederes (vue sur Beach et Pet Kingdom)
	for _, sx in ipairs({ -1, 1 }) do
		local a = c + Vector3.new(sx * 44, 0, 0)
		local b = c + Vector3.new(sx * 186, 0, 0)
		local cf = CFrame.lookAt((a + b) / 2 + Vector3.new(0, 0.11, 0), b + Vector3.new(0, 0.11, 0))
		part({ Name = "Path", Size = Vector3.new(12, 0.2, (b - a).Magnitude), CFrame = cf, Color = pal.path, CanCollide = false }, folder)
		Kit.avoidSegment(a, b, 9)
		for x = 60, 170, 22 do
			Kit.lantern(folder, c + Vector3.new(sx * x, 0, 9))
		end
		-- belvedere sureleve au bord de l'ile
		local top = Kit.plateau(folder, c + Vector3.new(sx * 172, 0, 0), 14, 5, Color3.fromRGB(235, 225, 205), Color3.fromRGB(190, 175, 150), Vector3.new(-sx, 0, 0))
		for _, z in ipairs({ -6, 6 }) do
			Kit.bench(folder, CFrame.lookAt(top + Vector3.new(0, 0, z), top + Vector3.new(sx * 10, 0, z)))
		end
		-- longue-vue
		cylinder(CFrame.new(top + Vector3.new(sx * 6, 1.5, 0)), 3, 0.3, Color3.fromRGB(60, 60, 70), folder, Enum.Material.Metal)
		part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 0.9, 0.9), CFrame = CFrame.new(top + Vector3.new(sx * 6, 3.3, 0)) * CFrame.Angles(0, 0, math.rad(sx * 15)), Color = Config.Colors.Gold, Material = Enum.Material.Metal }, folder)
		Kit.fenceLine(folder, top + Vector3.new(sx * 12, 0, -6), top + Vector3.new(sx * 12, 0, 6))
	end

	-- Zone des oeufs (ouest de la place)
	local eggDef = Config.EggById[zone.egg]
	local eggPos = c + Vector3.new(-70, 0, -40)
	stand(folder, eggPos, c, string.upper(eggDef.name), eggDef.color:Lerp(Color3.fromRGB(150, 80, 255), 0.45), "EggStand", { EggId = eggDef.id }, "Ouvrir un oeuf")
	Kit.eggDisplay(folder, eggPos + Vector3.new(-9, 0, -9), eggDef.color)
	Kit.eggDisplay(folder, eggPos + Vector3.new(9, 0, 9), eggDef.color:Lerp(Color3.fromRGB(255, 200, 255), 0.5))
	Kit.archway(folder, CFrame.lookAt(eggPos + Vector3.new(-14, 0, -14), c) , 22, 12, Color3.fromRGB(255, 235, 250), "ECLOSERIE", Color3.new(1, 1, 1))
	Kit.avoidSegment(eggPos, c, 10)

	-- Cadeau du jour + classement (est de la place)
	stand(folder, c + Vector3.new(66, 0, 34), c, "CADEAU", Color3.fromRGB(255, 170, 30), "DailyStand", {}, "Recuperer")
	-- Classement
	local boardPos = c + Vector3.new(48, 0, -42)
	local board = part({ Name = "Leaderboard", Size = Vector3.new(20, 16, 1), CFrame = CFrame.lookAt(boardPos + Vector3.new(0, 10, 0), Vector3.new(c.X, 10, c.Z)), Color = Color3.fromRGB(40, 45, 90) }, folder)
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


	-- Piste de course (nord-est)
	buildRaceTrack(folder, c + Vector3.new(110, 0, -110))

	-- Maisons autour de la place, tournees vers le centre
	local houses = {
		Vector3.new(-120, 0, 60), Vector3.new(-150, 0, 20), Vector3.new(-95, 0, 105), Vector3.new(-140, 0, -80),
		Vector3.new(-160, 0, 150), Vector3.new(120, 0, 60), Vector3.new(95, 0, 105), Vector3.new(150, 0, 30), Vector3.new(60, 0, 150),
	}
	for i, p in ipairs(houses) do
		local pos = c + p
		if Kit.isFree(pos, 6) then
			Kit.house(folder, CFrame.lookAt(pos, Vector3.new(c.X, 0, c.Z)), i)
			avoidCircle(pos, 15)
			Kit.lantern(folder, pos + (c - pos).Unit * 12 + Vector3.new(4, 0, 0))
		end
	end

	-- Etang, ruisseau et cascade a l'ouest, petite colline avec kiosque
	Kit.pond(folder, c + Vector3.new(-110, 0, -150), 20, Color3.fromRGB(250, 230, 170))
	Kit.footbridge(folder, c + Vector3.new(-110, 0, -150), Vector3.new(1, 0, 0), 6, 44)
	local top = Kit.plateau(folder, c + Vector3.new(-160, 0, -40), 18, 7, pal.top, pal.dirt, Vector3.new(1, 0, 0))
	Kit.gazebo(folder, top + Vector3.new(0, -0.5, 0), Color3.fromRGB(255, 140, 180))
	Kit.windmill(folder, c + Vector3.new(160, 0, 150), Vector3.new(-1, 0, -1))
	-- champ de fleurs en rangees pres du moulin
	local flowerCols = { Color3.fromRGB(255, 110, 160), Color3.fromRGB(255, 225, 70), Color3.fromRGB(150, 130, 255) }
	for row = 0, 4 do
		for t = 0, 9 do
			local p = c + Vector3.new(120 + t * 4, 0, 112 + row * 5)
			if Kit.isFree(p) then
				ballPart(CFrame.new(p + Vector3.new(0, 0.9, 0)), 1.4, Kit.LEAF_COLORS[1], folder, Enum.Material.Grass)
				ballPart(CFrame.new(p + Vector3.new(0, 1.6, 0)), 0.9, flowerCols[row % 3 + 1], folder)
			end
		end
	end
	Kit.avoidSegment(c + Vector3.new(118, 0, 114), c + Vector3.new(158, 0, 134), 6)

	-- Vegetation repartie
	Kit.scatter(zone, 55, 30, 300, function(pos)
		Kit.roundTree(folder, pos, R(0.8, 1.3))
		avoidCircle(pos, 5)
	end, 4)
	Kit.scatter(zone, 14, 60, 300, function(pos)
		Kit.pineTree(folder, pos, R(1, 1.4))
		avoidCircle(pos, 4)
	end, 3)
	Kit.scatter(zone, 45, 20, 300, function(pos)
		if rng:NextNumber() < 0.5 then
			Kit.bush(folder, pos, R(0.8, 1.2), rng:NextNumber() < 0.6 and Color3.fromRGB(255, 120, 170) or nil)
		else
			Kit.flowerPatch(folder, pos)
		end
		avoidCircle(pos, 2.5)
	end, 1)
	Kit.scatter(zone, 12, 40, 300, function(pos)
		Kit.rock(folder, pos, R(0.7, 1.3))
		avoidCircle(pos, 3)
	end)
	Kit.scatter(zone, 8, 50, 300, function(pos)
		Kit.bench(folder, CFrame.new(pos) * CFrame.Angles(0, R(0, 6.28), 0))
	end, 3)
end

-- Autres zones : stand a oeuf eventuel, panneau d'entree, decor thematique
local function buildZone(root, zone, index)
	local folder = Instance.new("Folder")
	folder.Name = "Zone_" .. zone.id
	folder:SetAttribute("ZoneId", zone.id)
	folder.Parent = root
	local c = zone.center
	local half = zone.size / 2
	island(root:FindFirstChild("World"), zone, index)
	walls(folder, zone, index)
	for _, e in ipairs(exitsOf(index)) do
		if e.next then
			gateArch(folder, c + e.dir * half, e.dir, e.zone)
		else
			-- panneau de bienvenue a l'entree de la zone
			local p = c + e.dir * (half - 16)
			local side = Vector3.new(e.dir.Z, 0, e.dir.X)
			local cf = CFrame.lookAt(p + side * 18 + Vector3.new(0, 6, 0), p + side * 18 + Vector3.new(0, 6, 0) + e.dir)
			sign(folder, cf, Vector3.new(18, 4, 0.6), zone.icon .. " " .. string.upper(zone.name), Config.Colors.Gold, Color3.fromRGB(150, 100, 60))
			for _, x in ipairs({ -6, 6 }) do
				part({ Size = Vector3.new(0.8, 6, 0.8), CFrame = cf * CFrame.new(x, -3, 0), Color = Color3.fromRGB(130, 85, 50), Material = Enum.Material.Wood }, folder)
			end
			avoidCircle(p + side * 18, 10)
			for _, s in ipairs({ -1, 1 }) do
				Kit.lantern(folder, p + side * s * 11 - e.dir * 6)
			end
		end
	end
	if index == 1 then
		buildVillage(folder, zone)
	else
		if zone.egg then
			local egg = Config.EggById[zone.egg]
			-- stand a oeuf a cote de la place centrale
			local d = exitsOf(index)[1].dir
			local side = Vector3.new(d.Z, 0, d.X)
			local eggPos = c + side * 48 + d * 16
			stand(folder, eggPos, c, string.upper(egg.name), egg.color:Lerp(Color3.fromRGB(150, 80, 255), 0.45), "EggStand", { EggId = egg.id }, "Ouvrir un oeuf")
			Kit.eggDisplay(folder, eggPos + side * 9 + d * 9, egg.color)
			Kit.eggDisplay(folder, eggPos + side * 9 - d * 9, egg.color:Lerp(Color3.fromRGB(255, 200, 255), 0.5))
			Kit.avoidSegment(eggPos, c, 10)
		end
		-- lanternes autour de la place
		for i = 0, 7 do
			local a = i / 8 * math.pi * 2 + 0.39
			Kit.lantern(folder, c + Vector3.new(math.cos(a) * 30, 0, math.sin(a) * 30))
		end
		MapZones[zone.id](folder, zone)
	end
	hills(root:FindFirstChild("World"), zone)
	computeCoinSpots(zone)
end

-- Arriere-plan : iles lointaines, montgolfieres, nuages, mer -----------------------------------

local function buildBackdrop(world)
	part({ Name = "Sea", Size = Vector3.new(4000, 2, 4000), CFrame = CFrame.new(0, -190, 0), Color = Color3.fromRGB(70, 170, 245), Reflectance = 0.1, CanCollide = false, CanQuery = false }, world)
	local far = Instance.new("Folder")
	far.Name = "Backdrop"
	far.Parent = world
	local spots = {
		{ Vector3.new(-900, 40, -800), 90, "castle" }, { Vector3.new(0, 70, -1000), 120, "trees" }, { Vector3.new(900, 30, -700), 80, "pine" },
		{ Vector3.new(1050, 60, 300), 100, "trees" }, { Vector3.new(950, 20, 1000), 90, "candy" }, { Vector3.new(0, 50, 1100), 110, "pine" },
		{ Vector3.new(-950, 35, 900), 90, "palm" }, { Vector3.new(-1100, 70, 100), 100, "castle" }, { Vector3.new(-300, -60, -900), 60, "trees" },
		{ Vector3.new(400, -50, 900), 60, "trees" }, { Vector3.new(-720, 120, -300), 50, "trees" }, { Vector3.new(760, 110, -260), 50, "candy" },
	}
	for _, s in ipairs(spots) do
		local pos, size, kind = s[1], s[2], s[3]
		local top = kind == "candy" and Color3.fromRGB(255, 175, 215) or (kind == "palm" and Color3.fromRGB(255, 228, 165) or Color3.fromRGB(125, 215, 85))
		Kit.farIsland(far, pos, size, top, Color3.fromRGB(165, 110, 65), function(p)
			for i = 1, math.floor(size / 12) do
				local q = p + Vector3.new(R(-size * 0.35, size * 0.35), 0, R(-size * 0.35, size * 0.35))
				if kind == "pine" then
					Kit.pineTree(far, q, R(2, 3))
				elseif kind == "palm" then
					Kit.palmTree(far, q, R(2, 3))
				elseif kind == "candy" then
					local col = Color3.fromHSV(R(0, 1), 0.5, 1)
					cylinder(CFrame.new(q + Vector3.new(0, 10, 0)), 20, 0.8, WHITE, far)
					part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 14, 14), CFrame = CFrame.new(q + Vector3.new(0, 26, 0)) * CFrame.Angles(0, R(0, 3), 0), Color = col, CanCollide = false }, far)
				else
					Kit.roundTree(far, q, R(2, 3))
				end
			end
			if kind == "castle" then
				for _, o in ipairs({ Vector3.new(-14, 0, 0), Vector3.new(14, 0, 0), Vector3.new(0, 0, -10) }) do
					cylinder(CFrame.new(p + o + Vector3.new(0, 18, 0)), 36, 6, Color3.fromRGB(235, 230, 245), far)
					local roofBall = ballPart(CFrame.new(p + o + Vector3.new(0, 38, 0)), 13, Color3.fromRGB(70, 90, 220), far)
					roofBall.CanCollide = false
				end
				part({ Size = Vector3.new(30, 20, 14), CFrame = CFrame.new(p + Vector3.new(0, 10, 0)), Color = Color3.fromRGB(235, 230, 245), CanCollide = false }, far)
			end
		end)
	end
	-- arc-en-ciel au-dessus du monde
	local rainbow = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 160, 60), Color3.fromRGB(255, 230, 70), Color3.fromRGB(110, 220, 90), Color3.fromRGB(80, 170, 255), Color3.fromRGB(160, 100, 255) }
	local center = Vector3.new(-200, -40, -1150)
	for b, col in ipairs(rainbow) do
		local r = 520 - b * 14
		for i = 0, 40 do
			local a = math.pi * i / 40
			local seg = part({ Size = Vector3.new(14, 40, 4), CFrame = CFrame.new(center + Vector3.new(math.cos(a) * r, math.sin(a) * r, 0)) * CFrame.Angles(0, 0, a), Color = col, Material = Enum.Material.Neon, Transparency = 0.45, CanCollide = false, CanQuery = false }, far)
			seg.CastShadow = false
		end
	end
	-- montgolfieres
	local balloonCols = { Color3.fromRGB(255, 90, 120), Color3.fromRGB(90, 180, 255), Color3.fromRGB(255, 200, 60), Color3.fromRGB(140, 220, 100), Color3.fromRGB(190, 120, 255) }
	for k = 1, 9 do
		local a = k / 9 * math.pi * 2
		Kit.balloon(far, Vector3.new(math.cos(a) * R(650, 850), R(70, 150), math.sin(a) * R(650, 850)), balloonCols[(k % #balloonCols) + 1])
	end
	for k = 1, 40 do
		local a = R(0, math.pi * 2)
		local r = R(700, 1300)
		Kit.cloudPuff(far, Vector3.new(math.cos(a) * r, R(-90, 60), math.sin(a) * r), R(1, 2.2))
	end
	for k = 1, 18 do
		Kit.cloudPuff(far, Vector3.new(R(-700, 700), R(110, 170), R(-700, 700)), R(1.2, 2.2))
	end
end

-- Construction ------------------------------------------------------------------------------

function MapBuilder.Build()
	for _, name in ipairs({ "PetRush", "Baseplate" }) do
		local old = workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	Terrain:Clear()
	local root = Instance.new("Folder")
	root.Name = "PetRush"
	root.Parent = workspace
	local world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = root
	buildLighting()
	-- ponts d'abord (reservent leurs couloirs), puis chaque zone
	for i, zone in ipairs(Config.Zones) do
		local nextZone = Config.Zones[i + 1]
		if nextZone then
			local d = dirTo(zone, nextZone)
			bridge(world, zone.center + d * (zone.size / 2), nextZone.center - d * (nextZone.size / 2))
		end
	end
	for i, zone in ipairs(Config.Zones) do
		local ok, err = pcall(buildZone, root, zone, i)
		if not ok then
			warn("[PetRush] Decor de " .. zone.id .. " : " .. tostring(err))
			if not coinSpots[zone.id] then
				computeCoinSpots(zone)
			end
		end
	end
	buildBackdrop(world)
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
