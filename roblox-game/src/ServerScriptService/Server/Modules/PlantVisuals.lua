-- Construit le modele visuel d'une plante sur une case (4 stades + mutations).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local PlantVisuals = {}

local GREEN = Color3.fromRGB(80, 170, 70)
local DARK_GREEN = Color3.fromRGB(50, 130, 60)

local function part(model, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = true
	p.CanTouch = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = model
	return p
end

local function ball(model, cf, size, color, material)
	return part(model, { Shape = Enum.PartType.Ball, Size = Vector3.new(size, size, size), CFrame = cf, Color = color, Material = material })
end

local function stem(model, cf, height, radius, color)
	return part(model, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = cf * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color or GREEN,
	})
end

local function fruitStyle(mutations)
	local color, material = nil, Enum.Material.SmoothPlastic
	for _, name in ipairs(Config.MutationOrder) do
		if table.find(mutations, name) then
			local m = Config.Mutations[name]
			if not color then
				color = m.color
			end
			if name == "Dore" or name == "ArcEnCiel" or name == "Choc" then
				material = Enum.Material.Neon
			elseif name == "Gele" then
				material = Enum.Material.Ice
			elseif name == "Mouille" then
				material = Enum.Material.Glass
			end
		end
	end
	return color, material
end

local function addMutationFx(model, cf, mutations)
	if #mutations == 0 then
		return
	end
	local holder = part(model, { Size = Vector3.new(0.2, 0.2, 0.2), CFrame = cf * CFrame.new(0, 1.5, 0), Transparency = 1, CanQuery = false })
	local att = Instance.new("Attachment")
	att.Parent = holder
	for _, name in ipairs(mutations) do
		local m = Config.Mutations[name]
		if m then
			local e = Instance.new("ParticleEmitter")
			e.Color = ColorSequence.new(m.color)
			e.LightEmission = 1
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
			e.Transparency = NumberSequence.new(0.2, 1)
			e.Lifetime = NumberRange.new(0.8, 1.4)
			e.Rate = (name == "ArcEnCiel") and 14 or 6
			e.Speed = NumberRange.new(1, 2.5)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Acceleration = (name == "Mouille") and Vector3.new(0, -8, 0) or Vector3.new(0, 1.5, 0)
			if name == "ArcEnCiel" then
				e.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
					ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 240, 80)),
					ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 255, 120)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 120, 255)),
				})
			end
			e.Parent = att
		end
	end
end

local function fruits(model, cf, count, size, radius, height, color, material)
	for i = 1, count do
		local a = (i / count) * math.pi * 2
		ball(model, cf * CFrame.new(math.cos(a) * radius, height, math.sin(a) * radius), size, color, material)
	end
end

local builders = {}

builders.bush = function(model, cf, stage, plant, fcolor, fmat)
	if stage == 0 then
		ball(model, cf * CFrame.new(0, 0.3, 0), 0.7, GREEN)
	elseif stage == 1 then
		stem(model, cf, 1.2, 0.15)
		ball(model, cf * CFrame.new(0, 1.3, 0), 1.2, GREEN)
	elseif stage == 2 then
		stem(model, cf, 1.6, 0.2)
		ball(model, cf * CFrame.new(0, 1.8, 0), 2.4, DARK_GREEN)
		fruits(model, cf, 3, 0.4, 1.1, 1.7, Color3.fromRGB(150, 200, 120))
	else
		stem(model, cf, 1.8, 0.25)
		ball(model, cf * CFrame.new(0, 2, 0), 2.8, DARK_GREEN)
		fruits(model, cf, 5, 0.7, 1.3, 1.9, fcolor or plant.color, fmat)
		ball(model, cf * CFrame.new(0, 3.2, 0), 0.7, fcolor or plant.color, fmat)
	end
end

builders.root = function(model, cf, stage, plant, fcolor, fmat)
	local leaves = math.max(stage, 1) + 1
	for i = 1, leaves do
		local a = (i / leaves) * math.pi * 2
		part(model, {
			Size = Vector3.new(0.25, 0.9 + stage * 0.4, 0.5),
			CFrame = cf * CFrame.new(math.cos(a) * 0.3, 0.6 + stage * 0.2, math.sin(a) * 0.3) * CFrame.Angles(math.rad(25) * math.sin(a), -a, math.rad(25) * math.cos(a)),
			Color = GREEN,
		})
	end
	if stage >= 2 then
		local size = stage == 2 and 0.8 or 1.3
		part(model, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(size, size * 0.7, size),
			CFrame = cf * CFrame.new(0, 0.25, 0),
			Color = stage == 2 and Color3.fromRGB(230, 190, 120) or (fcolor or plant.color),
			Material = stage == 3 and fmat or Enum.Material.SmoothPlastic,
		})
	end
end

builders.big = function(model, cf, stage, plant, fcolor, fmat)
	if stage == 0 then
		ball(model, cf * CFrame.new(0, 0.3, 0), 0.7, GREEN)
		return
	end
	stem(model, cf * CFrame.new(-1, 0, 0), 0.6 + stage * 0.3, 0.15)
	ball(model, cf * CFrame.new(-1, 1 + stage * 0.3, 0), 1 + stage * 0.3, GREEN)
	if stage >= 2 then
		local size = stage == 2 and 1.6 or 3
		part(model, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(size, size * 0.8, size),
			CFrame = cf * CFrame.new(0.6, size * 0.4 + 0.1, 0),
			Color = stage == 2 and Color3.fromRGB(140, 190, 100) or (fcolor or plant.color),
			Material = stage == 3 and fmat or Enum.Material.SmoothPlastic,
		})
	end
end

builders.tall = function(model, cf, stage, plant, fcolor, fmat)
	local heights = ({ { 0.8 }, { 2, 1.2 }, { 4, 3, 2 }, { 7, 5.5, 4 } })[stage + 1]
	for i, h in ipairs(heights) do
		local a = i * 2.1
		stem(model, cf * CFrame.new(math.cos(a) * 0.7, 0, math.sin(a) * 0.7), h, 0.3, stage == 3 and (fcolor or plant.color) or GREEN).Material = stage == 3 and fmat or Enum.Material.SmoothPlastic
	end
end

builders.cactus = function(model, cf, stage, plant, fcolor, fmat)
	local h = ({ 0.8, 1.6, 3, 4 })[stage + 1]
	stem(model, cf, h, 0.5 + stage * 0.1, plant.color)
	if stage >= 2 then
		for _, side in ipairs({ -1, 1 }) do
			part(model, { Size = Vector3.new(0.8, 0.8, 0.8), CFrame = cf * CFrame.new(side * 0.9, h * 0.5, 0), Color = plant.color })
			stem(model, cf * CFrame.new(side * 0.9, h * 0.5, 0), h * 0.5, 0.35, plant.color)
		end
	end
	if stage == 3 then
		fruits(model, cf, 3, 0.6, 0.6, h + 0.3, fcolor or Color3.fromRGB(255, 90, 160), fmat)
	end
end

function PlantVisuals.Clear(tile)
	local existing = tile:FindFirstChild("Plant")
	if existing then
		existing:Destroy()
	end
end

-- stage : 0 graine, 1 pousse, 2 en croissance, 3 mur
function PlantVisuals.Build(tile, plant, stage, mutations)
	PlantVisuals.Clear(tile)
	mutations = mutations or {}
	local model = Instance.new("Model")
	model.Name = "Plant"
	local cf = tile.CFrame * CFrame.new(0, 0.25, 0)
	local fcolor, fmat = fruitStyle(mutations)
	local builder = builders[plant.shape] or builders.bush
	builder(model, cf, stage, plant, fcolor, fmat)
	if stage == 3 then
		addMutationFx(model, cf, mutations)
	end
	model.Parent = tile
	return model
end

return PlantVisuals
