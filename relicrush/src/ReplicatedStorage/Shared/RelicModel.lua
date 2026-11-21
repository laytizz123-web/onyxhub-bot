-- Modeles 3D des reliques, construits par code (aucun import necessaire).
-- RelicModel.Build(relicId, opts) -> Model centre sur l'origine (~2 studs), PrimaryPart "Core".
-- opts.effects = false : sans lumiere ni particules (icones de l'interface).
-- opts.silhouette = true : relique non decouverte (noire).

local Config = require(script.Parent.Config)

local RelicModel = {}

local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad
local V = Vector3.new

local function piece(model, shape, size, cf, color, material, transparency)
	local p = Instance.new(shape == "wedge" and "WedgePart" or "Part")
	if shape == "ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "cyl" then
		p.Shape = Enum.PartType.Cylinder
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal
local GLASS = Enum.Material.Glass
local GOLD = Color3.fromRGB(255, 200, 60)

local function ball(m, d, cf, c, mat)
	return piece(m, "ball", V(d, d, d), cf, c, mat)
end
local function box(m, s, cf, c, mat)
	return piece(m, "box", s, cf, c, mat)
end
local function cyl(m, h, d, cf, c, mat) -- cylindre vertical
	return piece(m, "cyl", V(h, d, d), cf * ANG(0, 0, rad(90)), c, mat)
end
local function ring(m, r, thick, cf, c, mat, n)
	n = n or 14
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		box(m, V(r * 2 * math.pi / n + 0.04, thick, thick), cf * CF(math.cos(a) * r, math.sin(a) * r, 0) * ANG(0, 0, a + math.pi / 2), c, mat)
	end
end
local function gem(m, s, cf, c, mat)
	-- octaedre : deux pyramides de coins
	box(m, V(s, s, s) * 0.72, cf * ANG(rad(45), 0, rad(45)), c, mat or GLASS)
	box(m, V(s * 0.45, s * 0.45, s * 0.45), cf * ANG(rad(45), 0, rad(45)), c:Lerp(Color3.new(1, 1, 1), 0.4), NEON)
end

local SHAPES = {}

SHAPES.rune = function(m, a, b)
	box(m, V(1.4, 1.9, 0.5), CF(), a, Enum.Material.Slate)
	box(m, V(0.18, 1.2, 0.1), CF(0, 0, -0.28), b, NEON)
	box(m, V(0.8, 0.18, 0.1), CF(0, 0.3, -0.28) * ANG(0, 0, rad(30)), b, NEON)
	box(m, V(0.6, 0.18, 0.1), CF(0, -0.35, -0.28) * ANG(0, 0, rad(-35)), b, NEON)
end
SHAPES.flask = function(m, a, b)
	ball(m, 1.4, CF(0, -0.3, 0), a, GLASS).Transparency = 0.25
	ball(m, 1.05, CF(0, -0.35, 0), a, NEON)
	cyl(m, 0.8, 0.5, CF(0, 0.6, 0), b, GLASS)
	cyl(m, 0.3, 0.6, CF(0, 1.05, 0), Color3.fromRGB(150, 100, 60), Enum.Material.Wood)
end
SHAPES.feather = function(m, a, b)
	for i = 0, 6 do
		local t = i / 6
		box(m, V(0.9 - math.abs(t - 0.45) * 1.1, 0.34, 0.1), CF(math.sin(t * 2) * 0.2, -1 + t * 2, 0) * ANG(0, 0, rad(-20 + t * 30)), i % 2 == 0 and a or a:Lerp(b, 0.4))
	end
	box(m, V(0.08, 2.3, 0.08), CF(0.05, 0, -0.06) * ANG(0, 0, rad(-8)), b, METAL)
end
SHAPES.amulet = function(m, a, b)
	ring(m, 0.85, 0.18, CF(), a, METAL)
	gem(m, 0.8, CF(), b)
	ring(m, 0.45, 0.1, CF(0, 1.05, 0), a, METAL, 10)
end
SHAPES.idol = function(m, a, b)
	box(m, V(1.6, 1.7, 1.2), CF(), a, METAL)
	box(m, V(1.9, 0.35, 1.3), CF(0, 0.95, 0), a:Lerp(Color3.new(0, 0, 0), 0.15), METAL)
	for _, x in ipairs({ -0.4, 0.4 }) do
		box(m, V(0.36, 0.22, 0.1), CF(x, 0.25, -0.62), b, NEON)
	end
	box(m, V(0.3, 0.5, 0.15), CF(0, -0.15, -0.62), a:Lerp(Color3.new(0, 0, 0), 0.2), METAL)
	box(m, V(0.9, 0.16, 0.1), CF(0, -0.55, -0.62), b, NEON)
	gem(m, 0.45, CF(0, 1.3, 0), b)
end
SHAPES.crown = function(m, a, b)
	cyl(m, 0.6, 1.9, CF(0, -0.4, 0), a, METAL)
	for i = 0, 5 do
		local ang = i / 6 * math.pi * 2
		local p = CF(math.cos(ang) * 0.82, 0.25, math.sin(ang) * 0.82)
		piece(m, "wedge", V(0.3, 0.8, 0.5), p * ANG(0, -ang + math.pi / 2, 0), a, METAL)
		ball(m, 0.26, p * CF(0, 0.5, 0), b, NEON)
	end
	gem(m, 0.5, CF(0, -0.35, -0.95), b)
end
SHAPES.orb = function(m, a, b)
	ball(m, 1.5, CF(), a, NEON).Transparency = 0.1
	ball(m, 1.75, CF(), a, GLASS).Transparency = 0.6
	ring(m, 1.15, 0.12, CF() * ANG(rad(70), 0, 0), b, METAL)
	ring(m, 1.25, 0.1, CF() * ANG(rad(20), rad(60), 0), b, METAL)
end
SHAPES.acorn = function(m, a, b)
	local nut = ball(m, 1.4, CF(0, -0.2, 0), a)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = V(1, 1.25, 1)
	mesh.Parent = nut
	local cap = ball(m, 1.55, CF(0, 0.45, 0), Color3.fromRGB(120, 80, 45), Enum.Material.Wood)
	local cm = Instance.new("SpecialMesh")
	cm.MeshType = Enum.MeshType.Sphere
	cm.Scale = V(1, 0.55, 1)
	cm.Parent = cap
	cyl(m, 0.45, 0.16, CF(0, 0.95, 0), Color3.fromRGB(100, 65, 35))
	box(m, V(0.5, 0.06, 0.25), CF(0.25, 1.05, 0) * ANG(0, 0, rad(25)), b)
end
SHAPES.mushroom = function(m, a, b)
	cyl(m, 1, 0.55, CF(0, -0.5, 0), b)
	local cap = ball(m, 1.9, CF(0, 0.15, 0), a, NEON)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = V(1, 0.55, 1)
	mesh.Parent = cap
	for i = 0, 4 do
		local ang = i * 1.3
		ball(m, 0.25, CF(math.cos(ang) * 0.5, 0.55, math.sin(ang) * 0.5), b)
	end
end
SHAPES.lantern = function(m, a, b)
	box(m, V(1.2, 0.15, 1.2), CF(0, 0.85, 0), a, METAL)
	box(m, V(1.2, 0.15, 1.2), CF(0, -0.85, 0), a, METAL)
	for _, x in ipairs({ -0.55, 0.55 }) do
		for _, z in ipairs({ -0.55, 0.55 }) do
			box(m, V(0.1, 1.6, 0.1), CF(x, 0, z), a, METAL)
		end
	end
	ball(m, 0.8, CF(), b, NEON)
	box(m, V(1, 1.5, 1), CF(), b, GLASS).Transparency = 0.55
	ring(m, 0.3, 0.08, CF(0, 1.15, 0), a, METAL, 8)
end
SHAPES.totem = function(m, a, b)
	for i = 0, 2 do
		local y = -0.75 + i * 0.75
		box(m, V(1, 0.7, 1), CF(0, y, 0), a:Lerp(Color3.new(1, 1, 1), i * 0.08), Enum.Material.Wood)
		for _, x in ipairs({ -0.25, 0.25 }) do
			box(m, V(0.2, 0.15, 0.1), CF(x, y + 0.1, -0.52), b, NEON)
		end
	end
	for _, s in ipairs({ -1, 1 }) do
		piece(m, "wedge", V(0.1, 0.6, 0.8), CF(s * 0.75, 0.8, 0) * ANG(0, rad(90 * s), 0), b)
	end
end
SHAPES.heart = function(m, a, b)
	ball(m, 1.1, CF(-0.38, 0.25, 0), a, NEON)
	ball(m, 1.1, CF(0.38, 0.25, 0), a, NEON)
	box(m, V(1.05, 1.05, 0.95), CF(0, -0.3, 0) * ANG(0, 0, rad(45)), a, NEON)
	ring(m, 1.25, 0.08, CF(), b, METAL)
end
SHAPES.gem = function(m, a, b)
	gem(m, 1.7, CF(), a)
	ring(m, 1.05, 0.08, CF() * ANG(rad(90), 0, 0), b, METAL)
end
SHAPES.geode = function(m, a, b)
	local shell = ball(m, 1.8, CF(), a, Enum.Material.Slate)
	for i = 0, 5 do
		local ang = i / 6 * math.pi * 2
		box(m, V(0.25, 0.7, 0.25), CF(math.cos(ang) * 0.4, 0.2, -0.75 + math.sin(ang) * 0.2) * ANG(rad(-60), ang, 0), b, NEON)
	end
	shell.Transparency = 0
end
SHAPES.prism = function(m, a, b)
	for i = 0, 2 do
		piece(m, "wedge", V(1.2, 1.8, 0.7), CF() * ANG(0, i * math.pi * 2 / 3, 0) * CF(0, 0, -0.35), a:Lerp(b, i / 3), GLASS).Transparency = 0.15
	end
	ball(m, 0.6, CF(), b, NEON)
end
SHAPES.scepter = function(m, a, b)
	cyl(m, 2.2, 0.22, CF(0, -0.3, 0), b, METAL)
	gem(m, 0.9, CF(0, 1.05, 0), a)
	ring(m, 0.55, 0.1, CF(0, 1.05, 0), b, METAL, 10)
	ball(m, 0.4, CF(0, -1.4, 0), b, METAL)
end
SHAPES.cube = function(m, a, b)
	box(m, V(1.4, 1.4, 1.4), CF() * ANG(rad(35), rad(45), 0), a, Enum.Material.Glass)
	box(m, V(0.9, 0.9, 0.9), CF() * ANG(rad(35), rad(45), 0), b, NEON)
	for i = 0, 2 do
		ring(m, 1.25, 0.06, CF() * ANG(rad(i * 60), rad(i * 40), 0), b, NEON, 16)
	end
end
SHAPES.scarab = function(m, a, b)
	local body = ball(m, 1.5, CF(0, 0, 0.1), a, METAL)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = V(0.9, 0.55, 1.2)
	mesh.Parent = body
	ball(m, 0.6, CF(0, 0, -0.85), a, METAL)
	box(m, V(0.06, 0.5, 1.3), CF(0, 0.3, 0.15), b, NEON)
	for _, s in ipairs({ -1, 1 }) do
		for i = 0, 2 do
			box(m, V(0.5, 0.08, 0.08), CF(s * 0.75, -0.1, -0.3 + i * 0.4) * ANG(0, rad(s * (20 - i * 20)), rad(s * -25)), a, METAL)
		end
	end
	gem(m, 0.4, CF(0, 0.25, -0.85), b)
end
SHAPES.hourglass = function(m, a, b)
	cyl(m, 0.2, 1.5, CF(0, 1, 0), a, Enum.Material.Wood)
	cyl(m, 0.2, 1.5, CF(0, -1, 0), a, Enum.Material.Wood)
	for _, x in ipairs({ -0.6, 0.6 }) do
		cyl(m, 2, 0.14, CF(x, 0, 0), a, Enum.Material.Wood)
	end
	ball(m, 1, CF(0, 0.45, 0), b, GLASS).Transparency = 0.4
	ball(m, 1, CF(0, -0.45, 0), b, GLASS).Transparency = 0.4
	ball(m, 0.6, CF(0, -0.55, 0), b, NEON)
end
SHAPES.ankh = function(m, a, b)
	box(m, V(0.35, 1.4, 0.3), CF(0, -0.45, 0), a, METAL)
	box(m, V(1.4, 0.35, 0.3), CF(0, 0.3, 0), a, METAL)
	ring(m, 0.42, 0.22, CF(0, 0.85, 0), a, METAL, 12)
	gem(m, 0.35, CF(0, 0.3, -0.2), b)
end
SHAPES.mask = function(m, a, b)
	box(m, V(1.5, 1.8, 0.4), CF(), a, METAL)
	for i = 0, 4 do
		box(m, V(1.9 - i * 0.12, 0.16, 0.45), CF(0, 0.85 - i * 0.3, 0.15), i % 2 == 0 and b or a, METAL)
	end
	for _, x in ipairs({ -0.35, 0.35 }) do
		box(m, V(0.35, 0.15, 0.1), CF(x, 0.25, -0.22), Color3.fromRGB(20, 20, 40))
	end
	box(m, V(0.25, 0.7, 0.2), CF(0, -1.1, 0), b, METAL)
end
SHAPES.obelisk = function(m, a, b)
	box(m, V(0.7, 1.9, 0.7), CF(0, -0.2, 0), a, Enum.Material.Marble)
	piece(m, "wedge", V(0.7, 0.5, 0.35), CF(0, 0.98, -0.175), b, METAL)
	piece(m, "wedge", V(0.7, 0.5, 0.35), CF(0, 0.98, 0.175) * ANG(0, math.pi, 0), b, METAL)
	box(m, V(0.2, 0.2, 0.05), CF(0, 0.3, -0.37), b, NEON)
	box(m, V(1.1, 0.25, 1.1), CF(0, -1.25, 0), b, METAL)
end
SHAPES.sun = function(m, a, b)
	ball(m, 1.2, CF(), a, NEON)
	for i = 0, 9 do
		local ang = i / 10 * math.pi * 2
		piece(m, "wedge", V(0.12, 0.6, 0.3), CF(math.cos(ang) * 0.95, math.sin(ang) * 0.95, 0) * ANG(0, 0, ang - math.pi / 2) * ANG(0, rad(90), 0), b, NEON)
	end
	ring(m, 0.75, 0.08, CF(), b, METAL)
end
SHAPES.snowflake = function(m, a, b)
	for i = 0, 2 do
		box(m, V(2, 0.16, 0.12), CF() * ANG(0, 0, i * math.pi / 3), a, GLASS)
		for _, s in ipairs({ -0.6, 0.6 }) do
			for _, t in ipairs({ -1, 1 }) do
				box(m, V(0.45, 0.1, 0.1), CF() * ANG(0, 0, i * math.pi / 3) * CF(s, 0, 0) * ANG(0, 0, rad(t * 50)) * CF(0.15 * (s > 0 and 1 or -1), 0, 0), b, NEON)
			end
		end
	end
	gem(m, 0.5, CF(), b)
end
SHAPES.icicle = function(m, a, b)
	for i = 0, 2 do
		local x = (i - 1) * 0.45
		local h = 2 - math.abs(i - 1) * 0.6
		piece(m, "wedge", V(0.35, h, 0.25), CF(x, 0.9 - h / 2, -0.12) * ANG(math.pi, 0, 0), a, GLASS)
		piece(m, "wedge", V(0.35, h, 0.25), CF(x, 0.9 - h / 2, 0.12) * ANG(math.pi, math.pi, 0), a, GLASS)
	end
	box(m, V(1.5, 0.25, 0.6), CF(0, 0.95, 0), b, NEON)
end
SHAPES.bell = function(m, a, b)
	local shell = ball(m, 1.7, CF(0, 0, 0), a, METAL)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = V(0.9, 1.05, 0.9)
	mesh.Parent = shell
	cyl(m, 0.25, 1.8, CF(0, -0.75, 0), a, METAL)
	ball(m, 0.4, CF(0, -1, 0), b, NEON)
	ring(m, 0.25, 0.1, CF(0, 1, 0), b, METAL, 8)
end
SHAPES.horn = function(m, a, b)
	for i = 0, 6 do
		local t = i / 6
		local d = 0.9 - t * 0.7
		ball(m, d, CF(math.sin(t * 2.4) * 0.8 - 0.3, -0.9 + t * 1.8, 0), a:Lerp(b, t * 0.5))
	end
	ring(m, 0.42, 0.08, CF(-0.3, -0.85, 0) * ANG(rad(90), 0, 0), b, METAL, 10)
end
SHAPES.flame = function(m, a, b)
	ball(m, 1.3, CF(0, -0.35, 0), a, NEON)
	piece(m, "wedge", V(0.9, 1.3, 0.6), CF(0, 0.5, -0.2), a, NEON)
	piece(m, "wedge", V(0.9, 1.3, 0.6), CF(0, 0.5, 0.2) * ANG(0, math.pi, 0), a, NEON)
	ball(m, 0.7, CF(0, -0.3, -0.35), b, NEON)
end
SHAPES.hammer = function(m, a, b)
	cyl(m, 2, 0.24, CF(0, -0.3, 0), Color3.fromRGB(110, 75, 45), Enum.Material.Wood)
	box(m, V(1.5, 0.75, 0.75), CF(0, 0.8, 0), a, METAL)
	box(m, V(1.55, 0.2, 0.8), CF(0, 0.8, 0), b, NEON)
end
SHAPES.star = function(m, a, b)
	for i = 0, 4 do
		local ang = i / 5 * math.pi * 2
		piece(m, "wedge", V(0.35, 1, 0.45), CF() * ANG(0, 0, ang) * CF(0, 0.65, -0.11), a, NEON)
		piece(m, "wedge", V(0.35, 1, 0.45), CF() * ANG(0, 0, ang) * CF(0, 0.65, 0.11) * ANG(0, math.pi, 0), a, NEON)
	end
	ball(m, 0.7, CF(), b, NEON)
end
SHAPES.moon = function(m, a, b)
	for i = 0, 10 do
		local t = i / 10
		local ang = -2.2 + t * 4.4
		local d = 0.35 + math.sin(t * math.pi) * 0.45
		ball(m, d, CF(math.cos(ang) * 0.8, math.sin(ang) * 0.8, 0), a, NEON)
	end
	ball(m, 0.25, CF(-0.4, 0.2, 0), b, NEON)
end
SHAPES.halo = function(m, a, b)
	ring(m, 1, 0.22, CF() * ANG(rad(90), 0, 0), a, NEON, 18)
	ring(m, 0.75, 0.08, CF() * ANG(rad(90), 0, 0), b, NEON, 14)
	gem(m, 0.5, CF(0, 0, 0), b)
end
SHAPES.chalice = function(m, a, b)
	local cup = ball(m, 1.5, CF(0, 0.55, 0), a, METAL)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = V(1, 0.7, 1)
	mesh.Parent = cup
	cyl(m, 0.15, 1.3, CF(0, 0.95, 0), b, NEON)
	cyl(m, 0.9, 0.25, CF(0, -0.25, 0), a, METAL)
	cyl(m, 0.2, 1.1, CF(0, -0.75, 0), a, METAL)
	gem(m, 0.35, CF(0, 0.5, -0.72), b)
end
SHAPES.golem = function(m, a, b)
	box(m, V(1.5, 1.3, 1.2), CF(), a, Enum.Material.Slate)
	box(m, V(1.6, 0.3, 1.3), CF(0, 0.55, 0), GOLD, METAL)
	for _, x in ipairs({ -0.35, 0.35 }) do
		box(m, V(0.35, 0.18, 0.1), CF(x, 0.1, -0.62), b, NEON)
	end
	for _, s in ipairs({ -1, 1 }) do
		piece(m, "wedge", V(0.3, 0.7, 0.4), CF(s * 0.85, 0.9, 0) * ANG(0, 0, rad(-s * 25)), GOLD, METAL)
		gem(m, 0.4, CF(s * 0.85, -0.45, -0.3), b)
	end
end

-- Effets selon la rarete
local function effects(model, core, def, rarity)
	local idx = rarity.index
	local glow = def.c2
	if idx >= 3 then
		local l = Instance.new("PointLight")
		l.Color = glow
		l.Range = 6 + idx
		l.Brightness = 0.6 + idx * 0.15
		l.Shadows = false
		l.Parent = core
	end
	if idx >= 4 then
		local att = Instance.new("Attachment")
		att.Parent = core
		local e = Instance.new("ParticleEmitter")
		e.Name = "Aura"
		e.Rate = 4 + idx * 2
		e.Lifetime = NumberRange.new(0.6, 1.2)
		e.Speed = NumberRange.new(0.5, 1.5)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0) })
		e.LightEmission = 1
		e.Color = ColorSequence.new(rarity.color, glow)
		e.Parent = att
	end
	if idx >= 6 then
		-- anneau d'energie autour des reliques Mythiques et plus
		local halo = Instance.new("Part")
		halo.Name = "RarityHalo"
		halo.Shape = Enum.PartType.Cylinder
		halo.Size = V(0.05, 3, 3)
		halo.CFrame = core.CFrame * ANG(0, 0, rad(90))
		halo.Material = Enum.Material.ForceField
		halo.Color = rarity.id == "Secret" and glow or rarity.color
		halo.Anchored = true
		halo.CanCollide = false
		halo.CanQuery = false
		halo.CanTouch = false
		halo.Massless = true
		halo.Parent = model
	end
	if idx >= 7 then
		local att = Instance.new("Attachment")
		att.Parent = core
		local stars = Instance.new("ParticleEmitter")
		stars.Name = "Stars"
		stars.Rate = 10
		stars.Lifetime = NumberRange.new(1, 1.6)
		stars.Speed = NumberRange.new(0, 0.4)
		stars.SpreadAngle = Vector2.new(180, 180)
		stars.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.3), NumberSequenceKeypoint.new(1, 0) })
		stars.LightEmission = 1
		stars.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		stars.Color = ColorSequence.new(Color3.new(1, 1, 1), glow)
		stars.Parent = att
	end
end

function RelicModel.Build(relicId, opts)
	opts = opts or {}
	local def = Config.RelicById[relicId]
	local model = Instance.new("Model")
	model.Name = "Relic_" .. relicId
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Size = V(0.2, 0.2, 0.2)
	core.Transparency = 1
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.Massless = true
	core.Parent = model
	model.PrimaryPart = core
	if not def then
		ball(model, 1.4, CF(), Color3.fromRGB(150, 150, 160))
		return model
	end
	local build = SHAPES[def.shape] or SHAPES.gem
	build(model, def.c1, def.c2)
	local rarity = Config.RarityById[def.rarity]
	if opts.silhouette then
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") and p ~= core then
				p.Color = Color3.fromRGB(12, 10, 24)
				p.Material = Enum.Material.SmoothPlastic
				p.Transparency = math.max(p.Transparency, 0)
			end
		end
	elseif opts.effects ~= false then
		effects(model, core, def, rarity)
	end
	model:SetAttribute("RelicId", relicId)
	return model
end

-- Deplace un modele construit (pieces ancrees) : plus rapide que PivotTo pour beaucoup de reliques
function RelicModel.Parts(model)
	local parts, offsets = {}, {}
	local origin = model.PrimaryPart.CFrame
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			table.insert(parts, p)
			table.insert(offsets, origin:ToObjectSpace(p.CFrame))
		end
	end
	return parts, offsets
end

return RelicModel
