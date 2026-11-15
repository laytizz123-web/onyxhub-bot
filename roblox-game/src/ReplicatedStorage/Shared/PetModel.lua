-- Modeles 3D des pets.
-- Source : ReplicatedStorage.Pets.<Nom> (19 modeles generes par tools/build_pets3d.py, modifiables dans Studio).
-- Chaque Part s'appelle "<Groupe>.<role>" : le groupe sert aux animations (voir PetAnimator),
-- le role aux evolutions (base et accent sont recolores, eye / detail / glow sont conserves).
-- Si un modele manque, un modele simplifie est construit par code (secours).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local PetModel = {}

local function part(model, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = model
	return p
end

local function ball(model, cf, size, color, material, name)
	return part(model, { Name = name or "Body", Shape = Enum.PartType.Ball, Size = Vector3.new(size, size, size), CFrame = cf, Color = color, Material = material })
end

local function eyes(model, cf, spread, height, forward, size)
	for _, x in ipairs({ -spread, spread }) do
		part(model, { Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.new(size, size, size), CFrame = cf * CFrame.new(x, height, -forward), Color = Color3.new(0, 0, 0), Material = Enum.Material.SmoothPlastic })
	end
end

local shapes = {}

shapes.cat = function(m, cf, color, mat)
	ball(m, cf, 1.6, color, mat)
	ball(m, cf * CFrame.new(0, 0.9, -0.6), 1.2, color, mat, "Head")
	for _, x in ipairs({ -0.4, 0.4 }) do
		part(m, { Name = "Ear", Size = Vector3.new(0.35, 0.5, 0.2), CFrame = cf * CFrame.new(x, 1.6, -0.6) * CFrame.Angles(0, 0, x > 0 and -0.3 or 0.3), Color = color, Material = mat })
	end
	part(m, { Name = "Tail", Size = Vector3.new(0.25, 1.2, 0.25), CFrame = cf * CFrame.new(0, 0.6, 0.9) * CFrame.Angles(0.5, 0, 0), Color = color, Material = mat })
	eyes(m, cf, 0.28, 1, 1.1, 0.22)
end

shapes.dog = function(m, cf, color, mat)
	part(m, { Size = Vector3.new(1.3, 1.1, 1.9), CFrame = cf, Color = color, Material = mat })
	ball(m, cf * CFrame.new(0, 0.8, -1), 1.2, color, mat, "Head")
	for _, x in ipairs({ -0.55, 0.55 }) do
		part(m, { Name = "Ear", Size = Vector3.new(0.25, 0.7, 0.4), CFrame = cf * CFrame.new(x, 0.9, -1), Color = color:Lerp(Color3.new(0, 0, 0), 0.25), Material = mat })
	end
	for _, pos in ipairs({ Vector3.new(-0.45, -0.7, -0.6), Vector3.new(0.45, -0.7, -0.6), Vector3.new(-0.45, -0.7, 0.6), Vector3.new(0.45, -0.7, 0.6) }) do
		part(m, { Name = "Leg", Size = Vector3.new(0.35, 0.6, 0.35), CFrame = cf * CFrame.new(pos), Color = color, Material = mat })
	end
	eyes(m, cf, 0.28, 0.9, 1.5, 0.22)
end

shapes.bunny = function(m, cf, color, mat)
	ball(m, cf, 1.4, color, mat)
	ball(m, cf * CFrame.new(0, 0.9, -0.4), 1.1, color, mat, "Head")
	for _, x in ipairs({ -0.3, 0.3 }) do
		part(m, { Name = "Ear", Size = Vector3.new(0.3, 1.2, 0.2), CFrame = cf * CFrame.new(x, 1.9, -0.4) * CFrame.Angles(0, 0, x > 0 and -0.15 or 0.15), Color = color, Material = mat })
	end
	ball(m, cf * CFrame.new(0, 0, 0.8), 0.5, Color3.new(1, 1, 1), mat, "Tail")
	eyes(m, cf, 0.26, 1, 0.9, 0.2)
end

shapes.bird = function(m, cf, color, mat)
	ball(m, cf, 1.4, color, mat)
	ball(m, cf * CFrame.new(0, 0.9, -0.3), 1, color, mat, "Head")
	for _, x in ipairs({ -0.9, 0.9 }) do
		part(m, { Name = "Wing", Size = Vector3.new(0.8, 0.2, 1), CFrame = cf * CFrame.new(x, 0.2, 0) * CFrame.Angles(0, 0, x > 0 and -0.4 or 0.4), Color = color:Lerp(Color3.new(1, 1, 1), 0.2), Material = mat })
	end
	part(m, { Name = "Beak", Size = Vector3.new(0.3, 0.25, 0.5), CFrame = cf * CFrame.new(0, 0.8, -0.9), Color = Color3.fromRGB(255, 180, 40), Material = Enum.Material.SmoothPlastic })
	eyes(m, cf, 0.25, 1, 0.75, 0.2)
end

shapes.dragon = function(m, cf, color, mat)
	part(m, { Size = Vector3.new(1.4, 1.2, 2.2), CFrame = cf, Color = color, Material = mat })
	ball(m, cf * CFrame.new(0, 0.9, -1.2), 1.2, color, mat, "Head")
	for _, x in ipairs({ -1.1, 1.1 }) do
		part(m, { Name = "Wing", Size = Vector3.new(1.4, 0.15, 1.2), CFrame = cf * CFrame.new(x, 0.9, 0.2) * CFrame.Angles(0, 0, x > 0 and -0.6 or 0.6), Color = color:Lerp(Color3.new(0, 0, 0), 0.3), Material = mat })
	end
	for _, x in ipairs({ -0.35, 0.35 }) do
		part(m, { Name = "Horn", Size = Vector3.new(0.2, 0.6, 0.2), CFrame = cf * CFrame.new(x, 1.7, -1.1) * CFrame.Angles(0, 0, x > 0 and -0.3 or 0.3), Color = Color3.fromRGB(240, 240, 220), Material = Enum.Material.SmoothPlastic })
	end
	part(m, { Name = "Tail", Size = Vector3.new(0.4, 0.4, 1.6), CFrame = cf * CFrame.new(0, 0, 1.8) * CFrame.Angles(0.3, 0, 0), Color = color, Material = mat })
	eyes(m, cf, 0.3, 1, 1.7, 0.24)
end

shapes.snake = function(m, cf, color, mat)
	for i = 0, 4 do
		ball(m, cf * CFrame.new(math.sin(i * 1.2) * 0.4, -0.3 + i * 0.1, i * 0.6 - 0.8), 0.9 - i * 0.08, color, mat, i == 0 and "Head" or "Body")
	end
	eyes(m, cf * CFrame.new(0, -0.3, -0.8), 0.22, 0.15, 0.4, 0.18)
end

shapes.bear = function(m, cf, color, mat)
	part(m, { Size = Vector3.new(1.8, 1.6, 1.5), CFrame = cf, Color = color, Material = mat })
	ball(m, cf * CFrame.new(0, 1.2, -0.5), 1.4, color, mat, "Head")
	for _, x in ipairs({ -0.55, 0.55 }) do
		ball(m, cf * CFrame.new(x, 1.9, -0.5), 0.5, color, mat, "Ear")
	end
	ball(m, cf * CFrame.new(0, 1, -1.1), 0.5, color:Lerp(Color3.new(1, 1, 1), 0.4), mat, "Muzzle")
	eyes(m, cf, 0.3, 1.35, 1.1, 0.22)
end

shapes.blob = function(m, cf, color, mat)
	part(m, { Shape = Enum.PartType.Ball, Size = Vector3.new(1.8, 1.4, 1.8), CFrame = cf, Color = color, Material = mat })
	ball(m, cf * CFrame.new(0, 1, 0), 0.9, color, mat, "Head")
	eyes(m, cf, 0.3, 0.3, 0.8, 0.24)
end

-- Retourne un Model anchore centre sur cf. evoIndex : 1 Normal, 2 Golden, 3 Rainbow, 4 Cosmic
local function buildProcedural(petId, evoIndex, cf)
	local def = Config.PetById[petId] or Config.Pets[1]
	local evo = Config.Evolutions[evoIndex or 1] or Config.Evolutions[1]
	local model = Instance.new("Model")
	model.Name = def.id
	local color = def.color
	local material = Enum.Material.SmoothPlastic
	if evo.id == "Golden" then
		color = Color3.fromRGB(255, 215, 0)
		material = Enum.Material.Neon
	elseif evo.id == "Rainbow" then
		color = Color3.fromRGB(255, 120, 255)
		material = Enum.Material.Neon
	elseif evo.id == "Cosmic" then
		color = Color3.fromRGB(110, 60, 220)
		material = Enum.Material.Neon
	end
	local builder = shapes[def.shape] or shapes.blob
	builder(model, cf, color, material)
	local rarity = Config.RarityById[def.rarity]
	local scale = 0.9 + (rarity.index - 1) * 0.08
	if scale ~= 1 then
		model:ScaleTo(scale)
	end
	model:SetAttribute("PetId", def.id)
	model:SetAttribute("Evo", evo.id)
	-- Effets d'evolution
	if evo.id ~= "Normal" then
		local head = model:FindFirstChild("Head") or model:FindFirstChildWhichIsA("BasePart")
		local att = Instance.new("Attachment")
		att.Parent = head
		local e = Instance.new("ParticleEmitter")
		e.Rate = evo.id == "Cosmic" and 18 or 8
		e.Lifetime = NumberRange.new(0.6, 1.2)
		e.Speed = NumberRange.new(1, 2)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new(0.2, 1)
		e.LightEmission = 1
		if evo.id == "Rainbow" then
			e.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 255, 120)), ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 120, 255)) })
		else
			e.Color = ColorSequence.new(evo.color)
		end
		e.Parent = att
	end
	model.PrimaryPart = model:FindFirstChild("Body") or model:FindFirstChildWhichIsA("BasePart")
	return model
end

-- Modeles 3D de ReplicatedStorage.Pets -----------------------------------------------------

local RARITY_FX = {
	Legendary = { light = 1.2, rate = 6, size = 0.35, speed = 1.5 },
	Mythical = { light = 2, rate = 16, size = 0.45, speed = 3, swirl = true },
	Secret = { light = 3, rate = 24, size = 0.55, speed = 2, aura = true },
}

local function roleOf(part)
	return string.match(part.Name, "%.(%w+)$") or "base"
end

local function addRarityFx(model, rarity, root, height)
	local fx = RARITY_FX[rarity.id]
	if not fx or not root then
		return
	end
	local att = Instance.new("Attachment")
	att.Name = "RarityFx"
	att.Position = Vector3.new(0, 0, 0)
	att.Parent = root
	local light = Instance.new("PointLight")
	light.Color = rarity.color
	light.Range = 10
	light.Brightness = fx.light
	light.Shadows = false
	light.Parent = att
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "RaritySparkles"
	sparkles.Rate = fx.rate
	sparkles.Lifetime = NumberRange.new(0.8, 1.4)
	sparkles.Speed = NumberRange.new(fx.speed * 0.5, fx.speed)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, fx.size), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Transparency = NumberSequence.new(0.1, 1)
	sparkles.LightEmission = 1
	sparkles.Color = ColorSequence.new(Color3.new(1, 1, 1), rarity.color)
	if fx.swirl then
		sparkles.RotSpeed = NumberRange.new(-180, 180)
		sparkles.Acceleration = Vector3.new(0, 2, 0)
		sparkles.Shape = Enum.ParticleEmitterShape.Sphere
		sparkles.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		sparkles.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 220, 255)),
			ColorSequenceKeypoint.new(0.5, rarity.color),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 120, 255)),
		})
	end
	sparkles.Parent = att
	if fx.aura then
		-- aura doree : anneau de lumiere au sol + rayons
		local aura = Instance.new("ParticleEmitter")
		aura.Name = "SecretAura"
		aura.Rate = 10
		aura.Lifetime = NumberRange.new(1.2, 1.8)
		aura.Speed = NumberRange.new(0.5, 1)
		aura.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.5, 2.2), NumberSequenceKeypoint.new(1, 0) })
		aura.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.6), NumberSequenceKeypoint.new(1, 1) })
		aura.LightEmission = 1
		aura.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 160, 40))
		aura.EmissionDirection = Enum.NormalId.Top
		aura.Acceleration = Vector3.new(0, 3, 0)
		aura.Parent = att
	end
end

local EVO_COLORS = {
	Golden = { base = Color3.fromRGB(255, 200, 55), accent = Color3.fromRGB(255, 232, 140), reflect = 0.2 },
	Rainbow = { base = Color3.fromRGB(255, 120, 220), accent = Color3.fromRGB(255, 220, 245), reflect = 0.05 },
	Cosmic = { base = Color3.fromRGB(70, 40, 170), accent = Color3.fromRGB(150, 110, 255), reflect = 0.1 },
}

local function applyEvolution(model, evo, root)
	local colors = EVO_COLORS[evo.id]
	if not colors then
		return
	end
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local role = roleOf(part)
			if role == "base" then
				part.Color = colors.base
				part.Reflectance = colors.reflect
				part:SetAttribute("Rainbow", evo.id == "Rainbow")
			elseif role == "accent" then
				part.Color = colors.accent
				part.Reflectance = colors.reflect
			end
		end
	end
	if root then
		local att = Instance.new("Attachment")
		att.Name = "EvolutionFx"
		att.Parent = root
		local e = Instance.new("ParticleEmitter")
		e.Rate = evo.id == "Cosmic" and 14 or 6
		e.Lifetime = NumberRange.new(0.7, 1.2)
		e.Speed = NumberRange.new(1, 2.5)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
		e.LightEmission = 1
		e.Color = ColorSequence.new(evo.color or Color3.new(1, 1, 1))
		e.Parent = att
	end
end

function PetModel.Build(petId, evoIndex, cf)
	cf = cf or CFrame.new()
	local folder = ReplicatedStorage:FindFirstChild("Pets")
	-- cherche d'abord directement dans Pets, puis dans un modele importe d'un bloc (ex. TousLesPets)
	local template = folder and (folder:FindFirstChild(petId) or folder:FindFirstChild(petId .. "_Node", true) or folder:FindFirstChild(petId, true))
	if not template then
		return buildProcedural(petId, evoIndex, cf)
	end
	local def = Config.PetById[petId] or Config.Pets[1]
	local evo = Config.Evolutions[evoIndex or 1] or Config.Evolutions[1]
	local rarity = Config.RarityById[def.rarity]
	local model = template:Clone()
	if model:IsA("BasePart") then
		-- piece importee posee seule dans le dossier : on l'emballe dans un Model
		local wrapper = Instance.new("Model")
		wrapper.Name = petId
		model.Parent = wrapper
		model = wrapper
	elseif not model:IsA("Model") then
		model:Destroy()
		return buildProcedural(petId, evoIndex, cf)
	end
	local root
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			if not root and part.Name == "Body.base" then
				root = part
			end
		end
	end
	root = root or model:FindFirstChildWhichIsA("BasePart", true)
	model.PrimaryPart = root
	local simple = true
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and string.find(part.Name, ".", 1, true) then
			simple = false
			break
		end
	end
	if simple then
		-- modele importe : orientation d'origine du fichier, pivot au centre du dessous, taille ~4,2 studs
		local fix = Config.ImportedPetRotation or {}
		local extra = fix.Extra or Vector3.zero
		local extraRot = CFrame.Angles(math.rad(extra.X), math.rad(extra.Y), math.rad(extra.Z))
		model.PrimaryPart = nil
		local center = model:GetBoundingBox().Position
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				local rel = part.Position - center
				if fix.ResetRotation ~= false then
					part.CFrame = CFrame.new(center) * extraRot * CFrame.new(rel)
				else
					part.CFrame = CFrame.new(center) * extraRot * CFrame.new(rel) * part.CFrame.Rotation
				end
			end
		end
		model.WorldPivot = CFrame.new(model:GetBoundingBox().Position)
		model.PrimaryPart = nil
		local boxCF, boxSize = model:GetBoundingBox()
		model.WorldPivot = CFrame.new(boxCF.Position - Vector3.new(0, boxSize.Y / 2, 0))
		model.PrimaryPart = root
		if boxSize.Y > 7 or boxSize.Y < 2 then
			model:ScaleTo(model:GetScale() * (4.2 / boxSize.Y))
		end
	else
		model.WorldPivot = CFrame.new() -- modeles generes : sol a Y = 0 sous le pet
	end
	local scale = 0.92 + (rarity.index - 1) * 0.05
	if math.abs(scale - 1) > 0.01 then
		model:ScaleTo(model:GetScale() * scale)
	end
	if simple then
		-- modele texture d'une seule piece : l'evolution se voit par un contour lumineux
		local colors = { Golden = Color3.fromRGB(255, 205, 50), Rainbow = Color3.fromRGB(255, 120, 230), Cosmic = Color3.fromRGB(140, 90, 255) }
		if colors[evo.id] then
			local h = Instance.new("Highlight")
			h.Name = "EvolutionGlow"
			h.FillColor = colors[evo.id]
			h.FillTransparency = 0.75
			h.OutlineColor = colors[evo.id]
			h.OutlineTransparency = 0
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h:SetAttribute("Rainbow", evo.id == "Rainbow")
			h.Parent = model
		end
		model:SetAttribute("SimplePet", true)
	end
	applyEvolution(model, evo, root)
	addRarityFx(model, rarity, root)
	model:SetAttribute("PetId", def.id)
	model:SetAttribute("Evo", evo.id)
	model:SetAttribute("PetScale", scale)
	model:PivotTo(cf)
	return model
end

-- Stats effectives d'un pet { speed, power, stamina, luck, total }
function PetModel.Stats(petId, evoIndex)
	local def = Config.PetById[petId]
	if not def then
		return { speed = 0, power = 0, stamina = 0, luck = 0 }
	end
	local rarity = Config.RarityById[def.rarity]
	local mult = (Config.Evolutions[evoIndex or 1] or Config.Evolutions[1]).mult
	return {
		speed = def.speed * mult,
		power = rarity.power * mult,
		stamina = def.stamina * mult,
		luck = def.luck * mult,
	}
end

function PetModel.DisplayName(petId, evoIndex)
	local def = Config.PetById[petId]
	local evo = Config.Evolutions[evoIndex or 1]
	if not def then
		return petId
	end
	local name = def.id
	if evo and evo.id ~= "Normal" then
		name = evo.icon .. " " .. evo.name .. " " .. name
	end
	return def.icon .. " " .. name
end

return PetModel
