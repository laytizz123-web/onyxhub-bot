-- Icones 3D des reliques dans l'interface (ViewportFrame) + cadre colore de rarete.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local RelicModel = require(ReplicatedStorage.Shared.RelicModel)
local Icons = require(ReplicatedStorage.Shared.Icons)

local RelicView = {}
local spinning = {}
local bobbing = {}

-- Cree un ViewportFrame montrant la relique ; silhouette = relique non decouverte
function RelicView.Viewport(relicId, parent, props, silhouette, spin)
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(200, 200, 220)
	vp.LightColor = Color3.fromRGB(255, 250, 240)
	vp.LightDirection = Vector3.new(-1, -1.2, -0.8)
	for k, v in pairs(props or {}) do
		vp[k] = v
	end
	local model = RelicModel.Build(relicId, { effects = false, silhouette = silhouette })
	model:PivotTo(CFrame.new())
	model.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 0.6, -5.4), Vector3.zero)
	cam.Parent = vp
	vp.CurrentCamera = cam
	if spin then
		spinning[vp] = { model = model, angle = math.random() * 6 }
		vp.Destroying:Connect(function()
			spinning[vp] = nil
		end)
	end
	vp.Parent = parent
	return vp
end

-- Icone de la relique : l'illustration de la planche si elle existe, sinon le modele 3D.
-- silhouette = relique non decouverte (ombre sombre)
function RelicView.Icon(relicId, parent, props, silhouette, spin)
	local def = Config.RelicById[relicId]
	local key = def and def.img and ("relic_" .. def.img)
	if key and Icons.Has(key) then
		local img = Icons.Image(key, parent, props)
		if silhouette then
			img.ImageColor3 = Color3.fromRGB(14, 10, 32)
		end
		if spin then
			-- leger balancement pour donner de la vie a l'illustration
			bobbing[img] = { base = img.Rotation, phase = math.random() * 6 }
			img.Destroying:Connect(function()
				bobbing[img] = nil
			end)
		end
		return img
	end
	return RelicView.Viewport(relicId, parent, props, silhouette, spin)
end

function RelicView.RarityColor(relicId)
	local def = Config.RelicById[relicId]
	return def and Config.RarityById[def.rarity].color or Color3.new(1, 1, 1)
end

RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	for img, b in pairs(bobbing) do
		if img.Parent then
			img.Rotation = math.sin(t * 2 + b.phase) * 6
		end
	end
	for vp, s in pairs(spinning) do
		if vp.Parent and vp.Visible then
			s.angle += dt * 1.2
			s.model:PivotTo(CFrame.Angles(0, s.angle, 0))
		end
	end
end)

return RelicView
