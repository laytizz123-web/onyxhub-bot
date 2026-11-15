-- Construit le modele 3D d'un pet (parts uniquement) selon sa forme, sa couleur et son evolution.

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
function PetModel.Build(petId, evoIndex, cf)
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
