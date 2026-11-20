-- Pets 3D equipes qui suivent chaque joueur (rendu local fluide, aucun cout reseau).
-- Les pets restent derriere le proprietaire, evitent les murs, se posent au sol ou flottent,
-- et jouent idle / marche / course / saut selon le mouvement du joueur.
-- Habille aussi les coureurs de la course avec des modeles animes.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetModel = require(ReplicatedStorage.Shared.PetModel)
local PetAnimator = require(ReplicatedStorage.Shared.PetAnimator)
local PetMeshFactory = require(ReplicatedStorage.Shared.PetMeshFactory)
local Config = require(ReplicatedStorage.Shared.Config)

local PetFollow = {}

local folder = Instance.new("Folder")
folder.Name = "ClientPets"
folder.Parent = workspace

local tracked = {} -- [player] = { pets = { ... }, json = string }
local MAX_DISTANCE = 220 -- au-dela, les pets des autres joueurs ne sont pas animes

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function evoIndexOf(evo)
	if type(evo) == "number" then
		return evo
	end
	return ({ Normal = 1, Golden = 2, Rainbow = 3, Cosmic = 4 })[evo] or 1
end

local outlines = 0
local MAX_OUTLINES = 24 -- Roblox limite le nombre de Highlight affiches en meme temps

local function spawnPet(petId, evo, cf)
	local model = PetModel.Build(petId, evoIndexOf(evo), cf)
	-- contour sombre facon dessin anime
	if outlines < MAX_OUTLINES and not model:FindFirstChildOfClass("Highlight") then
		local h = Instance.new("Highlight")
		h.Name = "CartoonOutline"
		h.FillTransparency = 1
		h.OutlineColor = Color3.fromRGB(35, 28, 50)
		h.OutlineTransparency = 0.15
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = model
		outlines += 1
		model.Destroying:Connect(function()
			outlines -= 1
		end)
	end
	model.Parent = folder
	-- petit saut d'apparition
	local anim = PetAnimator.new(model, petId)
	anim.trick = { kind = "hop", t0 = os.clock() }
	return anim
end

local function clearEntry(entry)
	for _, p in ipairs(entry.pets) do
		p.anim:destroy()
	end
	entry.pets = {}
end

local function rebuild(player)
	local entry = tracked[player]
	if not entry then
		entry = { pets = {}, json = "" }
		tracked[player] = entry
	end
	local json = player:GetAttribute("EquippedPets") or "[]"
	if json == entry.json then
		return
	end
	entry.json = json
	clearEntry(entry)
	local ok, list = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	if not ok or type(list) ~= "table" then
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local start = hrp and (hrp.CFrame * CFrame.new(0, -2.5, 5)) or CFrame.new(0, 5, 0)
	for i, pet in ipairs(list) do
		local ok2, anim = pcall(spawnPet, pet.id, pet.evo, start)
		if ok2 then
			table.insert(entry.pets, { anim = anim, index = i, pos = start.Position, yaw = 0, lift = 0 })
		else
			warn("[PetRush] Pet " .. tostring(pet.id) .. " : " .. tostring(anim))
		end
	end
end

local function ownerState(char, hrp)
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local v = hrp.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	if humanoid then
		local st = humanoid:GetState()
		if st == Enum.HumanoidStateType.Jumping or st == Enum.HumanoidStateType.Freefall then
			return "jump", speed
		end
	end
	if speed > 18 then
		return "run", speed
	elseif speed > 1.5 then
		return "walk", speed
	end
	return "idle", speed
end

-- Position cible derriere le joueur, sans traverser les murs
local function targetFor(hrp, index, count, ignore)
	local spread = (index - (count + 1) / 2) * 4.6
	local back = 6 + math.abs(spread) * 0.35
	local origin = hrp.Position
	local desired = (hrp.CFrame * CFrame.new(spread, 0, back)).Position
	rayParams.FilterDescendantsInstances = ignore
	local dir = desired - origin
	local hit = workspace:Raycast(origin, dir, rayParams)
	if hit then
		desired = hit.Position - dir.Unit * 2
	end
	return desired
end

local function groundY(pos, ignore)
	rayParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -40, 0), rayParams)
	return hit and hit.Position.Y or nil
end

-- Coureurs de la course : modele client anime qui suit le modele serveur
local racers = {} -- [Model serveur] = { anim, pos, yaw, last }

local function decorateRacer(model)
	if racers[model] or not model:IsA("Model") then
		return
	end
	local petId = model:GetAttribute("PetId")
	if not petId then
		return
	end
	local ok, anim = pcall(spawnPet, petId, model:GetAttribute("Evo"), model:GetPivot())
	if not ok then
		return
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
		elseif d:IsA("ParticleEmitter") or d:IsA("Light") then
			d.Enabled = false
		end
	end
	racers[model] = { anim = anim, pos = model:GetPivot().Position, yaw = 0, last = model:GetPivot().Position }
	model.Destroying:Connect(function()
		local r = racers[model]
		racers[model] = nil
		if r then
			r.anim:destroy()
		end
	end)
end

local function yawTowards(current, dir, alpha)
	if dir.Magnitude < 0.05 then
		return current
	end
	local target = math.atan2(-dir.X, -dir.Z)
	local diff = (target - current + math.pi) % (2 * math.pi) - math.pi
	return current + diff * alpha
end

local function update(dt)
	local now = os.clock()
	local camPos = workspace.CurrentCamera.CFrame.Position
	local breakFolder = workspace:FindFirstChild("Breakables")
	local ignore = { folder, workspace:FindFirstChild("Coins"), workspace:FindFirstChild("Racers"), breakFolder }
	for player in pairs(tracked) do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	for player, entry in pairs(tracked) do
		if player.Parent ~= Players then
			clearEntry(entry)
			tracked[player] = nil
		else
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and #entry.pets > 0 and (hrp.Position - camPos).Magnitude < MAX_DISTANCE then
				local state, speed = ownerState(char, hrp)
				local count = #entry.pets
				-- objet a casser vise par le joueur : les pets l'entourent et l'attaquent
				local attack
				local targetName = player:GetAttribute("BreakTarget")
				if targetName and breakFolder then
					local m = breakFolder:FindFirstChild(targetName)
					local box = m and m:FindFirstChild("Hitbox")
					if box and (box.Position - hrp.Position).Magnitude < 95 then
						attack = box
					end
				end
				for _, p in ipairs(entry.pets) do
					local anim = p.anim
					local target
					if attack then
						local a = (p.index / count) * math.pi * 2 + now * 0.15
						local r = math.max(attack.Size.X, attack.Size.Z) / 2 + 2.2
						target = attack.Position + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
					else
						target = targetFor(hrp, p.index, count, ignore)
					end
					-- deplacement doux (plus rapide si le pet est loin)
					local flat = Vector3.new(target.X - p.pos.X, 0, target.Z - p.pos.Z)
					local dist = flat.Magnitude
					if dist > 60 then
						p.pos = target
					else
						p.pos += flat * math.clamp(dt * (dist > 12 and 9 or 6), 0, 1)
					end
					local ground = groundY(p.pos, ignore) or (hrp.Position.Y - 3)
					local airborne = anim.kind == "fly" or anim.kind == "float"
					local hoverY = airborne and (anim.hover + 0.6) or 0
					-- petit bond quand le joueur saute
					local jumpLift = (state == "jump" and not airborne) and 1.6 or 0
					p.lift += (jumpLift - p.lift) * math.clamp(dt * 10, 0, 1)
					local y = ground + hoverY + p.lift
					p.pos = Vector3.new(p.pos.X, y, p.pos.Z)
					-- orientation : dans le sens de la marche, sinon vers le joueur
					local petState = state
					if state ~= "jump" then
						if dist > 10 or (speed > 18 and not attack) then
							petState = "run"
						elseif dist > 0.6 or (speed > 1.5 and not attack) then
							petState = "walk"
						else
							petState = "idle"
						end
					end
					local lookAt = attack and attack.Position or hrp.Position
					local facing = (petState ~= "idle") and flat or Vector3.new(lookAt.X - p.pos.X, 0, lookAt.Z - p.pos.Z)
					if attack and petState == "idle" and not anim.trick and now - (p.lastHit or 0) > 0.5 + (p.index % 3) * 0.12 then
						-- coup : petit bond vers l'objet
						p.lastHit = now
						anim.trick = { kind = "hop", t0 = now }
					end
					p.yaw = yawTowards(p.yaw, facing, math.clamp(dt * 8, 0, 1))
					anim:update(CFrame.new(p.pos) * CFrame.Angles(0, p.yaw, 0), petState, now)
				end
			end
		end
	end
	for model, r in pairs(racers) do
		if model.Parent then
			local target = model:GetPivot().Position
			local delta = target - r.pos
			r.pos += delta * math.clamp(dt * 10, 0, 1)
			local move = Vector3.new(delta.X, 0, delta.Z)
			r.yaw = yawTowards(r.yaw, move, math.clamp(dt * 10, 0, 1))
			local ground = groundY(r.pos, ignore) or r.pos.Y
			local airborne = r.anim.kind == "fly" or r.anim.kind == "float"
			local y = ground + (airborne and r.anim.hover or 0)
			local moving = move.Magnitude > 0.05
			r.anim:update(CFrame.new(r.pos.X, y, r.pos.Z) * CFrame.Angles(0, r.yaw, 0), moving and "run" or "idle", now)
		end
	end
end

function PetFollow.Init()
	local function hook(player)
		rebuild(player)
		player:GetAttributeChangedSignal("EquippedPets"):Connect(function()
			rebuild(player)
		end)
		player.CharacterAdded:Connect(function()
			local entry = tracked[player]
			if entry then
				entry.json = ""
			end
			task.wait(0.5)
			rebuild(player)
		end)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		hook(p)
	end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function(player)
		local entry = tracked[player]
		if entry then
			clearEntry(entry)
			tracked[player] = nil
		end
	end)
	task.spawn(function()
		local racersFolder = workspace:WaitForChild("Racers", 15)
		if racersFolder then
			for _, m in ipairs(racersFolder:GetChildren()) do
				task.defer(decorateRacer, m)
			end
			racersFolder.ChildAdded:Connect(function(m)
				task.wait(0.15)
				decorateRacer(m)
			end)
		end
	end)
	RunService.RenderStepped:Connect(update)
	-- pets sculptes : quand un maillage est pret, on remplace les pets affiches par la version sculptee
	local refreshQueued = false
	PetMeshFactory.Ready:Connect(function()
		if refreshQueued then
			return
		end
		refreshQueued = true
		task.delay(0.3, function()
			refreshQueued = false
			for player, entry in pairs(tracked) do
				entry.json = ""
				rebuild(player)
			end
		end)
	end)
	task.spawn(function()
		local list = {}
		local ok, mine = pcall(function()
			return HttpService:JSONDecode(Players.LocalPlayer:GetAttribute("EquippedPets") or "[]")
		end)
		if ok and type(mine) == "table" then
			for _, pet in ipairs(mine) do
				table.insert(list, { pet.id, evoIndexOf(pet.evo) })
			end
		end
		for _, def in ipairs(Config.Pets) do
			table.insert(list, { def.id, 1 })
		end
		PetMeshFactory.Preload(list)
	end)
end

return PetFollow
