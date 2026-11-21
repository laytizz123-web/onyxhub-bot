-- Remplacement des decors par tes propres modeles 3D.
-- Depose des modeles (Model ou MeshPart) dans ReplicatedStorage.Decor (ou ServerStorage.Decor)
-- en leur donnant le nom d'un emplacement (voir docs/DECORS.md) : "Arbre", "Fontaine", "Caisse"...
--   * Variantes choisies au hasard : Arbre, Arbre2, Arbre3 ... Arbre9
--   * Version propre a un monde : Arbre_Forest, Caisse_Lava ... (prioritaire dans ce monde)
--   * Le modele est mis a l'echelle automatiquement (hauteur ou largeur de l'emplacement) et pose au sol.
--     Attribut KeepScale = true sur le modele pour garder sa taille d'origine.
--   * Par securite, tous les scripts contenus dans ces modeles sont supprimes.
-- Si aucun modele n'est trouve, le jeu garde le decor genere.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Decor = {}
Decor.World = nil -- monde en cours de construction (fixe par WorldBuilder)

local warned = {}

local function folders()
	local list = {}
	for _, root in ipairs({ ReplicatedStorage, ServerStorage }) do
		local f = root:FindFirstChild("Decor")
		if f then
			table.insert(list, f)
		end
	end
	return list
end

local function isTemplate(o)
	return o and (o:IsA("Model") or o:IsA("BasePart"))
end

local function variants(base)
	local out = {}
	for _, f in ipairs(folders()) do
		for i = 1, 9 do
			local o = f:FindFirstChild(i == 1 and base or (base .. i))
			if isTemplate(o) then
				table.insert(out, o)
			end
		end
	end
	return out
end

-- Renvoie un modele modele (au hasard parmi les variantes) ou nil
function Decor.Find(name, world)
	world = world or Decor.World
	if world then
		local specific = variants(name .. "_" .. world)
		if #specific > 0 then
			return specific[math.random(#specific)]
		end
	end
	local generic = variants(name)
	if #generic > 0 then
		return generic[math.random(#generic)]
	end
	return nil
end

function Decor.Has(name, world)
	return Decor.Find(name, world) ~= nil
end

-- Pose une copie du modele "name" a cf (au sol). opts : height, width, collide, query, world
-- Renvoie (modele, taille) ou nil
function Decor.Place(name, parent, cf, opts)
	opts = opts or {}
	local template = Decor.Find(name, opts.world)
	if not template then
		return nil
	end
	local model = template:Clone()
	if model:IsA("BasePart") then
		local wrap = Instance.new("Model")
		wrap.Name = template.Name
		model.Parent = wrap
		model = wrap
	end
	-- securite : aucun script venant d'un modele externe
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then
			if not warned[template] then
				warned[template] = true
				warn("[RelicRush] Decor " .. template.Name .. " : script supprime (" .. d.Name .. ")")
			end
			d:Destroy()
		end
	end
	local parts = 0
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			parts += 1
			p.Anchored = true
			if opts.collide == false then
				p.CanCollide = false
			end
			if opts.query == false then
				p.CanQuery = false
				p.CanTouch = false
			end
		end
	end
	if parts == 0 then
		model:Destroy()
		return nil
	end
	model:PivotTo(CFrame.new())
	local _, size = model:GetBoundingBox()
	if not template:GetAttribute("KeepScale") then
		local factor
		if opts.width then
			factor = opts.width / math.max(size.X, size.Z, 0.01)
		elseif opts.height then
			factor = opts.height / math.max(size.Y, 0.01)
		end
		if factor and factor > 0 then
			pcall(function()
				model:ScaleTo(model:GetScale() * factor)
			end)
		end
	end
	model:PivotTo(CFrame.new(cf.Position) * cf.Rotation)
	local bb, s2 = model:GetBoundingBox()
	local offset = Vector3.new(cf.X - bb.X, cf.Y - (bb.Y - s2.Y / 2), cf.Z - bb.Z)
	model:PivotTo(model:GetPivot() + offset)
	model.Parent = parent
	return model, s2
end

-- Batiment interactif : construit le decor genere (invites, panneaux...), puis s'il existe un modele
-- "name", masque le decor genere en gardant les pieces utiles (invites, panneaux, marqueurs) et pose le modele.
function Decor.Swap(name, parent, cf, opts, build)
	local holder = Instance.new("Folder")
	holder.Name = name
	holder.Parent = parent
	local result = build(holder)
	if not Decor.Find(name, opts and opts.world) then
		return result
	end
	for _, d in ipairs(holder:GetDescendants()) do
		if d:IsA("BasePart") then
			local useful = d:FindFirstChildOfClass("ProximityPrompt") or d:FindFirstChildOfClass("BillboardGui") or d:FindFirstChildOfClass("ClickDetector") or #game:GetService("CollectionService"):GetTags(d) > 0
			if useful then
				d.Transparency = 1
				d.CanCollide = false
				for _, c in ipairs(d:GetChildren()) do
					if c:IsA("Light") or c:IsA("ParticleEmitter") or c:IsA("Fire") or c:IsA("Smoke") or c:IsA("Sparkles") or c:IsA("SpecialMesh") then
						c:Destroy()
					end
				end
			end
		end
	end
	for _, d in ipairs(holder:GetDescendants()) do
		local relic = d:FindFirstAncestorWhichIsA("Model")
		if relic and string.sub(relic.Name, 1, 6) == "Relic_" then
			continue -- les reliques qui flottent en vitrine restent
		end
		if d:IsA("BasePart") and d.Transparency < 1 then
			d:Destroy()
		elseif d:IsA("Model") and d.Parent and #d:GetDescendants() == 0 then
			d:Destroy()
		end
	end
	Decor.Place(name, holder, cf, opts)
	return result
end

return Decor
