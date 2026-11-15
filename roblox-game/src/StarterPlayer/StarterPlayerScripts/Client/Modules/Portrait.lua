-- Portraits 3D des pets dans l'interface (ViewportFrame), avec rotation douce.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PetModel = require(ReplicatedStorage.Shared.PetModel)

local Portrait = {}

local spinning = {} -- [ViewportFrame] = { model, base, speed }

-- opts : silhouette (bool), spin (number de rad/s), zoom (number)
function Portrait.new(parent, petId, evo, props, opts)
	opts = opts or {}
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
		spinning[vp] = { model = model, base = model:GetPivot(), center = cf.Position, speed = opts.spin, angle = math.random() * 0.6 - 0.3 }
		vp.Destroying:Connect(function()
			spinning[vp] = nil
		end)
	else
		model:PivotTo(CFrame.new(cf.Position) * CFrame.Angles(0, 0.35, 0) * CFrame.new(-cf.Position) * model:GetPivot())
	end
	vp.Parent = parent
	return vp
end

RunService.RenderStepped:Connect(function(dt)
	for vp, s in pairs(spinning) do
		if vp.Parent and vp.Visible then
			s.angle += dt * s.speed
			local c = s.center
			s.model:PivotTo(CFrame.new(c) * CFrame.Angles(0, s.angle, 0) * CFrame.new(-c) * s.base)
		elseif not vp.Parent then
			spinning[vp] = nil
		end
	end
end)

return Portrait
