-- Portrait d'un pet dans l'interface : image du pet si disponible, sinon modele 3D (ViewportFrame).
-- opts : silhouette (bool), spin (number : vitesse d'animation), zoom (number)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local PetModel = require(ReplicatedStorage.Shared.PetModel)
local Icons = require(ReplicatedStorage.Shared.Icons)

local Portrait = {}

local animated = {} -- [GuiObject] = { kind, ... }

local function evoId(evo)
	return (Config.Evolutions[evo or 1] or Config.Evolutions[1]).id
end

local function imagePortrait(parent, petId, evo, props, opts)
	local holder = Instance.new("Frame")
	holder.Name = "Portrait"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	for k, v in pairs(props or {}) do
		holder[k] = v
	end
	local image = Icons.PetImage(petId, holder, {
		Size = UDim2.fromScale(opts.zoom and 0.95 * opts.zoom or 0.95, opts.zoom and 0.95 * opts.zoom or 0.95),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = holder.ZIndex,
	})
	if not image then
		holder:Destroy()
		return nil
	end
	local id = evoId(evo)
	if opts.silhouette then
		image.ImageColor3 = Color3.fromRGB(15, 15, 30)
	else
		image.ImageColor3 = Config.EvolutionTint[id] or Color3.new(1, 1, 1)
	end
	if id ~= "Normal" and not opts.silhouette then
		-- etincelle d'evolution dans le coin
		Icons.Image("sparkle", holder, { Size = UDim2.fromScale(0.3, 0.3), Position = UDim2.fromScale(0.98, 0.02), AnchorPoint = Vector2.new(1, 0), ZIndex = holder.ZIndex + 1 })
	end
	if opts.spin or id == "Rainbow" then
		animated[holder] = { image = image, speed = opts.spin or 1, rainbow = id == "Rainbow" and not opts.silhouette, phase = math.random() * 6 }
	end
	holder.Parent = parent
	return holder
end

local function modelPortrait(parent, petId, evo, props, opts)
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Portrait"
	vp.BackgroundTransparency = 1
	vp.BorderSizePixel = 0
	vp.Ambient = Color3.fromRGB(190, 190, 200)
	vp.LightColor = Color3.new(1, 1, 1)
	vp.LightDirection = Vector3.new(-0.6, -1, -0.8)
	for k, v in pairs(props or {}) do
		vp[k] = v
	end
	local model = PetModel.Build(petId, evo, CFrame.new())
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			d.Enabled = false
		elseif d:IsA("BasePart") and opts.silhouette then
			d.Color = Color3.fromRGB(20, 20, 30)
			d.Material = Enum.Material.SmoothPlastic
		end
	end
	model.Parent = vp
	local cf, size = model:GetBoundingBox()
	local radius = math.max(size.X, size.Y, size.Z)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local distance = radius * 2.3 / (opts.zoom or 1)
	camera.CFrame = CFrame.lookAt(cf.Position + Vector3.new(distance * 0.45, distance * 0.3, -distance), cf.Position)
	camera.Parent = vp
	vp.CurrentCamera = camera
	if opts.spin then
		animated[vp] = { model = model, base = model:GetPivot(), center = cf.Position, speed = opts.spin, angle = 0 }
	else
		model:PivotTo(CFrame.new(cf.Position) * CFrame.Angles(0, 0.35, 0) * CFrame.new(-cf.Position) * model:GetPivot())
	end
	vp.Parent = parent
	return vp
end

function Portrait.new(parent, petId, evo, props, opts)
	opts = opts or {}
	return imagePortrait(parent, petId, evo, props, opts) or modelPortrait(parent, petId, evo, props, opts)
end

RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	for gui, s in pairs(animated) do
		if not gui.Parent then
			animated[gui] = nil
		elseif gui.Visible then
			if s.image then
				-- l'image se balance doucement et "respire"
				s.image.Rotation = math.sin(t * 2 * s.speed + s.phase) * 6
				local k = 0.95 + math.sin(t * 3 * s.speed + s.phase) * 0.03
				s.image.Size = UDim2.fromScale(k, k)
				if s.rainbow then
					s.image.ImageColor3 = Color3.fromHSV((t * 0.25 + s.phase) % 1, 0.35, 1)
				end
			elseif s.model then
				s.angle += dt * s.speed
				local c = s.center
				s.model:PivotTo(CFrame.new(c) * CFrame.Angles(0, s.angle, 0) * CFrame.new(-c) * s.base)
			end
		end
	end
end)

return Portrait
