-- Cibles attaquables (tresors et boss). Le joueur choisit une cible (clic / toucher, ou frappe
-- automatique) ; ses reliques l'attaquent a chaque intervalle avec toute sa puissance.
-- Les degats sont calcules et appliques uniquement par le serveur.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local F = require(ReplicatedStorage.Shared.Formulas)
local DataService = require(script.Parent.DataService)

local Targets = {}
local entities = {} -- [Model] = { hp, maxHp, world, onDeath(entity, hits), hits = {[player]=dmg}, kind }
local folder

function Targets.Folder()
	return folder
end

function Targets.Register(model, info)
	info.hits = {}
	info.hp = info.maxHp
	entities[model] = info
	model:SetAttribute("HP", info.hp)
	model:SetAttribute("MaxHP", info.maxHp)
	model:SetAttribute("Kind", info.kind)
	model:SetAttribute("World", info.world)
	local hitbox = model.PrimaryPart
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = Config.MaxTargetDistance
	click.Parent = hitbox
	click.MouseClick:Connect(function(player)
		Targets.SetTarget(player, model)
	end)
	model.Parent = folder
end

function Targets.Unregister(model)
	entities[model] = nil
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("Target") == model.Name then
			p:SetAttribute("Target", nil)
		end
	end
end

function Targets.Get(model)
	return entities[model]
end

function Targets.SetTarget(player, model)
	if not model or not entities[model] then
		player:SetAttribute("Target", nil)
		return
	end
	if player:GetAttribute("Target") == model.Name then
		player:SetAttribute("Target", nil) -- deuxieme clic : on rappelle les reliques
	else
		player:SetAttribute("Target", model.Name)
	end
end

local function hrpOf(player)
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

-- Frappe automatique (avantage achete) : tresor le plus proche
local function autoTarget(player, hrp)
	local best, bd
	for m, info in pairs(entities) do
		if info.kind == "treasure" and m.PrimaryPart then
			local d = (m.PrimaryPart.Position - hrp.Position).Magnitude
			if d < 60 and (not bd or d < bd) then
				best, bd = m, d
			end
		end
	end
	if best then
		player:SetAttribute("Target", best.Name)
	end
end

local function tick()
	local now = os.time()
	for _, player in ipairs(Players:GetPlayers()) do
		local data = DataService.Get(player)
		local hrp = hrpOf(player)
		if data and hrp then
			local name = player:GetAttribute("Target")
			if not name and data.Perks.AutoHit and data.Settings.AutoHit ~= false then
				autoTarget(player, hrp)
				name = player:GetAttribute("Target")
			end
			if name then
				local model = folder:FindFirstChild(name)
				local info = model and entities[model]
				if not info or not model.PrimaryPart or (model.PrimaryPart.Position - hrp.Position).Magnitude > Config.MaxTargetDistance then
					player:SetAttribute("Target", nil)
				elseif info.hp > 0 then
					local dmg = F.Power(data, now)
					info.hp -= dmg
					info.hits[player] = (info.hits[player] or 0) + dmg
					if info.onHit then
						info.onHit(model, info, player, dmg)
					end
					if info.hp <= 0 then
						info.hp = 0
						model:SetAttribute("HP", 0)
						Targets.Unregister(model)
						task.spawn(info.onDeath, model, info)
					else
						model:SetAttribute("HP", info.hp)
					end
				end
			end
		end
	end
end

function Targets.Init()
	folder = Instance.new("Folder")
	folder.Name = "Targets"
	folder.Parent = workspace
	task.spawn(function()
		while true do
			task.wait(Config.HitInterval)
			local ok, err = pcall(tick)
			if not ok then
				warn("[RelicRush] Targets : " .. tostring(err))
			end
		end
	end)
end

return Targets
