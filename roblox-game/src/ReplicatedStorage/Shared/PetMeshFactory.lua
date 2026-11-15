-- Construit les pets sculptes (maillages organiques) a partir des donnees de Shared/PetMeshes,
-- avec EditableMesh + CreateMeshPartAsync (comme les icones avec EditableImage).
-- Cote client uniquement. Si Roblox refuse (API indisponible, budget memoire...), le jeu garde
-- les anciens modeles en pieces : PetModel bascule automatiquement.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PetMeshFactory = {}

local folder = script.Parent:FindFirstChild("PetMeshes")
local templates = {} -- [petId .. "|" .. evo] = Model
local pending = {} -- cle -> true pendant la construction
local failed = false -- une erreur d'API desactive le systeme pour toute la session
local readyEvent = Instance.new("BindableEvent")
PetMeshFactory.Ready = readyEvent.Event -- (petId, evoIndex)

local B64 = {}
do
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i = 1, #chars do
		B64[string.byte(chars, i)] = i - 1
	end
end

local function b64decode(s)
	local len = #s
	local pad = 0
	if string.sub(s, -2) == "==" then
		pad = 2
	elseif string.sub(s, -1) == "=" then
		pad = 1
	end
	local outLen = (len // 4) * 3 - pad
	local out = buffer.create(outLen)
	local o = 0
	for i = 1, len, 4 do
		local a, b, c, d = string.byte(s, i, i + 3)
		local n = (B64[a] or 0) * 262144 + (B64[b] or 0) * 4096 + (B64[c] or 0) * 64 + (B64[d] or 0)
		if o < outLen then
			buffer.writeu8(out, o, n // 65536)
		end
		if o + 1 < outLen then
			buffer.writeu8(out, o + 1, (n // 256) % 256)
		end
		if o + 2 < outLen then
			buffer.writeu8(out, o + 2, n % 256)
		end
		o += 3
	end
	return out
end

local function roleOf(name)
	local dot = string.find(name, ".", 1, true)
	return dot and string.sub(name, dot + 1) or "base"
end

-- Teintes d'evolution appliquees aux sommets (garde les ombres, rayures et details peints)
local function lum(r, g, b)
	return 0.3 * r + 0.59 * g + 0.11 * b
end

local function tint(evo, r, g, b, pos, index)
	if evo == 2 then -- Golden : or chaud qui garde le modele
		local l = math.clamp(lum(r, g, b) * 1.15, 0, 1)
		return 0.55 + 0.45 * l, 0.36 + 0.52 * l, 0.06 + 0.32 * l * l
	elseif evo == 3 then -- Rainbow : arc-en-ciel le long du corps
		local l = math.clamp(lum(r, g, b), 0, 1)
		local h = (pos.Y * 0.16 + pos.X * 0.07 + pos.Z * 0.05) % 1
		local c = Color3.fromHSV(h, 0.5, 0.55 + 0.45 * l)
		return c.R, c.G, c.B
	elseif evo == 4 then -- Cosmic : nuit violette pailletee d'etoiles
		local l = math.clamp(lum(r, g, b), 0, 1)
		local star = ((index * 7919) % 97) == 0
		if star then
			return 1, 0.95, 1
		end
		local t = (math.sin(pos.Y * 1.7 + pos.X * 1.1) + 1) / 2
		return 0.12 + 0.3 * l + 0.18 * t, 0.06 + 0.16 * l, 0.3 + 0.45 * l + 0.1 * (1 - t)
	end
	return r, g, b
end

local function buildPart(entry, evo)
	local data = b64decode(entry.data)
	local nv, nt = entry.nv, entry.nt
	local center, ext = entry.center, entry.ext
	local role = roleOf(entry.name)
	local tinted = evo > 1 and (role == "base" or role == "accent")
	local em = AssetService:CreateEditableMesh({})
	local vid = table.create(nv)
	local nid = table.create(nv)
	local cid = table.create(nv)
	local offN = nv * 6
	local offC = offN + nv * 3
	local offT = offC + nv * 3
	for i = 0, nv - 1 do
		local x = (buffer.readu16(data, i * 6) - 32768) / 32767 * ext.X
		local y = (buffer.readu16(data, i * 6 + 2) - 32768) / 32767 * ext.Y
		local z = (buffer.readu16(data, i * 6 + 4) - 32768) / 32767 * ext.Z
		local p = Vector3.new(x, y, z)
		vid[i + 1] = em:AddVertex(p)
		local n = Vector3.new(buffer.readi8(data, offN + i * 3), buffer.readi8(data, offN + i * 3 + 1), buffer.readi8(data, offN + i * 3 + 2))
		nid[i + 1] = em:AddNormal(n.Magnitude > 0 and n.Unit or Vector3.yAxis)
		local r = buffer.readu8(data, offC + i * 3) / 255
		local g = buffer.readu8(data, offC + i * 3 + 1) / 255
		local b = buffer.readu8(data, offC + i * 3 + 2) / 255
		if tinted then
			r, g, b = tint(evo, r, g, b, p + center, i)
		end
		cid[i + 1] = em:AddColor(Color3.new(math.clamp(r, 0, 1), math.clamp(g, 0, 1), math.clamp(b, 0, 1)), 1)
		if i % 1500 == 1499 then
			task.wait()
		end
	end
	for t = 0, nt - 1 do
		local a = buffer.readu16(data, offT + t * 6) + 1
		local b = buffer.readu16(data, offT + t * 6 + 2) + 1
		local c = buffer.readu16(data, offT + t * 6 + 4) + 1
		local f = em:AddTriangle(vid[a], vid[b], vid[c])
		em:SetFaceNormals(f, { nid[a], nid[b], nid[c] })
		em:SetFaceColors(f, { cid[a], cid[b], cid[c] })
		if t % 3000 == 2999 then
			task.wait()
		end
	end
	local part = AssetService:CreateMeshPartAsync(Content.fromObject(em), {
		CollisionFidelity = Enum.CollisionFidelity.Box,
		RenderFidelity = Enum.RenderFidelity.Precise,
	})
	part.Name = entry.name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = true
	part.Material = entry.glow and Enum.Material.Neon or Enum.Material.SmoothPlastic
	part.Color = Color3.new(1, 1, 1)
	part.CFrame = CFrame.new(center)
	if role == "base" or role == "accent" then
		part:SetAttribute("Sculpted", true)
	end
	return part
end

function PetMeshFactory.Has(petId)
	return RunService:IsClient() and not failed and folder ~= nil and folder:FindFirstChild(petId) ~= nil
end

local function build(petId, evo)
	local key = petId .. "|" .. evo
	local ok, result = pcall(function()
		local list = require(folder[petId])
		local model = Instance.new("Model")
		model.Name = petId
		for _, entry in ipairs(list) do
			buildPart(entry, evo).Parent = model
			task.wait()
		end
		model.PrimaryPart = model:FindFirstChild("Body.base") or model:FindFirstChildWhichIsA("BasePart")
		model.WorldPivot = CFrame.new()
		model:SetAttribute("SculptedPet", true)
		return model
	end)
	pending[key] = nil
	if ok then
		templates[key] = result
		readyEvent:Fire(petId, evo)
	else
		failed = true
		warn("[PetRush] Pets sculptes indisponibles, modeles classiques utilises : " .. tostring(result))
	end
end

-- Renvoie un modele pret (clone) ou nil ; lance la construction en arriere-plan si besoin.
function PetMeshFactory.Get(petId, evo)
	evo = evo or 1
	if not PetMeshFactory.Has(petId) then
		return nil
	end
	local key = petId .. "|" .. evo
	local t = templates[key]
	if t then
		return t:Clone()
	end
	if not pending[key] then
		pending[key] = true
		task.spawn(build, petId, evo)
	end
	return nil
end

-- Prepare a l'avance les pets les plus visibles (appele au demarrage du client).
function PetMeshFactory.Preload(list)
	task.spawn(function()
		for _, item in ipairs(list) do
			if failed then
				return
			end
			local key = item[1] .. "|" .. (item[2] or 1)
			if not templates[key] and not pending[key] and PetMeshFactory.Has(item[1]) then
				pending[key] = true
				build(item[1], item[2] or 1)
			end
		end
	end)
end

function PetMeshFactory.Failed()
	return failed
end

return PetMeshFactory
