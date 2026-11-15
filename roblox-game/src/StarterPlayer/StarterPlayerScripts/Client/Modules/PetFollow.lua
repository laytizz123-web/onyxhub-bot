-- Pets equipes qui suivent chaque joueur (rendu local fluide).
-- Affiche l'image du pet sur un panneau tourne vers la camera, avec ombre au sol.
-- Si l'image n'est pas disponible, utilise le modele 3D. Habille aussi les coureurs de la course.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PetModel = require(ReplicatedStorage.Shared.PetModel)
local Icons = require(ReplicatedStorage.Shared.Icons)

local PetFollow = {}

local folder = Instance.new("Folder")
folder.Name = "ClientPets"
folder.Parent = workspace

local PET_SIZE = 4.2 -- taille de l'image en studs

local tracked = {} -- [player] = { pets = { ... }, json = string }

local function evoIndexOf(evo)
	if type(evo) == "number" then
		return evo
	end
	for i, e in ipairs(Config.Evolutions) do
		if e.id == evo then
			return i
		end
	end
	return 1
end

-- Cree le visuel d'un pet. Retourne { root = BasePart|Model, image = ImageLabel?, isSprite = bool }
local function makeVisual(petId, evo, parent, scale)
	scale = scale or 1
	local evoIndex = evoIndexOf(evo)
	local anchor = Instance.new("Part")
	anchor.Name = "PetAnchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Parent = parent

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(PET_SIZE * scale, PET_SIZE * scale)
	gui.LightInfluence = 0.25
	gui.MaxDistance = 220
	gui.Adornee = anchor
	gui.Parent = anchor
	local image = Icons.PetImage(petId, gui, { Size = UDim2.fromScale(1, 1) })
	if image then
		local evoId = Config.Evolutions[evoIndex].id
		image.ImageColor3 = Config.EvolutionTint[evoId] or Color3.new(1, 1, 1)
		if evoId ~= "Normal" then
			local evoDef = Config.Evolutions[evoIndex]
			local att = Instance.new("Attachment")
			att.Parent = anchor
			local sparkle = Instance.new("ParticleEmitter")
			sparkle.Rate = evoId == "Cosmic" and 14 or 7
			sparkle.Lifetime = NumberRange.new(0.6, 1.1)
			sparkle.Speed = NumberRange.new(1, 2.5)
			sparkle.SpreadAngle = Vector2.new(180, 180)
			sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
			sparkle.LightEmission = 1
			sparkle.Color = ColorSequence.new(evoDef.color or Color3.new(1, 1, 1))
			sparkle.Parent = att
		end
		-- ombre au sol
		local shadow = Instance.new("Part")
		shadow.Name = "PetShadow"
		shadow.Shape = Enum.PartType.Cylinder
		shadow.Size = Vector3.new(0.1, 2.6 * scale, 2.6 * scale)
		shadow.Color = Color3.new(0, 0, 0)
		shadow.Material = Enum.Material.SmoothPlastic
		shadow.Transparency = 0.65
		shadow.Anchored = true
		shadow.CanCollide = false
		shadow.CanQuery = false
		shadow.CanTouch = false
		shadow.CastShadow = false
		shadow.Parent = anchor
		return { root = anchor, image = image, shadow = shadow, isSprite = true, rainbow = evoIndex == 3, scale = scale }
	end
	-- repli : modele 3D
	gui:Destroy()
	anchor:Destroy()
	local model = PetModel.Build(petId, evoIndex, CFrame.new(0, -1000, 0))
	model.Parent = parent
	return { root = model, isSprite = false, rainbow = evoIndex == 3, scale = scale }
end

local function placeVisual(v, cf, groundY)
	if v.isSprite then
		local s = v.scale or 1
		v.root.CFrame = cf * CFrame.new(0, PET_SIZE * s * 0.35, 0)
		if v.shadow then
			local p = cf.Position
			local y = groundY or (p.Y - 1)
			v.shadow.CFrame = CFrame.new(p.X, y + 0.08, p.Z) * CFrame.Angles(0, 0, math.rad(90))
		end
	else
		v.root:PivotTo(cf)
	end
end

local function destroyVisual(v)
	v.root:Destroy()
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
	for _, p in ipairs(entry.pets) do
		destroyVisual(p.visual)
	end
	entry.pets = {}
	local ok, list = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	if not ok or type(list) ~= "table" then
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	for i, pet in ipairs(list) do
		local visual = makeVisual(pet.id, pet.evo, folder)
		local start = hrp and hrp.CFrame or CFrame.new(0, 5, 0)
		table.insert(entry.pets, { visual = visual, index = i, current = start, phase = i * 1.7 })
	end
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundBelow(position, ignore)
	rayParams.FilterDescendantsInstances = ignore
	local result = workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), rayParams)
	return result and result.Position.Y or nil
end

-- Coureurs de la course : remplace les modeles en blocs par les images
local racerVisuals = {} -- [Model] = visual

local function decorateRacer(model)
	if racerVisuals[model] or not model:IsA("Model") then
		return
	end
	local petId = model:GetAttribute("PetId")
	if not petId then
		return
	end
	if not Icons.HasImage("pet_" .. petId) then
		return
	end
	local visual = makeVisual(petId, model:GetAttribute("Evo"), folder, 1.15)
	if not visual.isSprite then
		destroyVisual(visual)
		return
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
		elseif d:IsA("ParticleEmitter") then
			d.Enabled = false
		end
	end
	racerVisuals[model] = visual
	model.Destroying:Connect(function()
		racerVisuals[model] = nil
		destroyVisual(visual)
	end)
end

local function update(dt)
	local now = os.clock()
	local ignore = { folder }
	for player in pairs(tracked) do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	for player, entry in pairs(tracked) do
		if player.Parent ~= Players then
			for _, p in ipairs(entry.pets) do
				destroyVisual(p.visual)
			end
			tracked[player] = nil
		else
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local count = #entry.pets
			for _, p in ipairs(entry.pets) do
				if hrp then
					-- en arc derriere le joueur
					local spread = (p.index - (count + 1) / 2) * 4.2
					local behind = hrp.CFrame * CFrame.new(spread, 0, 5.5 + math.abs(spread) * 0.3)
					local target = behind.Position
					local ground = groundBelow(target, ignore) or (hrp.Position.Y - 3)
					local hop = math.abs(math.sin(now * 7 + p.phase)) * 0.8
					local moving = hrp.AssemblyLinearVelocity.Magnitude > 2
					local goal = CFrame.new(Vector3.new(target.X, ground + 0.2 + (moving and hop or math.sin(now * 2 + p.phase) * 0.15 + 0.15), target.Z))
					p.current = p.current:Lerp(goal, math.clamp(dt * 8, 0, 1))
					placeVisual(p.visual, p.current, ground)
					if p.visual.image then
						p.visual.image.Rotation = moving and math.sin(now * 14 + p.phase) * 8 or math.sin(now * 2 + p.phase) * 3
						if p.visual.rainbow then
							p.visual.image.ImageColor3 = Color3.fromHSV((now * 0.25 + p.phase) % 1, 0.35, 1)
						end
					elseif p.visual.rainbow then
						local hue = (now * 0.4 + p.index * 0.2) % 1
						for _, part in ipairs(p.visual.root:GetChildren()) do
							if part:IsA("BasePart") and part.Name ~= "Eye" then
								part.Color = Color3.fromHSV(hue, 0.7, 1)
							end
						end
					end
				end
			end
		end
	end
	for model, visual in pairs(racerVisuals) do
		if model.Parent then
			local cf = model:GetPivot()
			local pos = cf.Position
			placeVisual(visual, CFrame.new(pos.X, pos.Y - 0.6, pos.Z), pos.Y - 1.4)
			if visual.image then
				visual.image.Rotation = math.sin(now * 16 + pos.X) * 9
			end
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
	local racers = workspace:WaitForChild("Racers", 10)
	if racers then
		for _, m in ipairs(racers:GetChildren()) do
			task.defer(decorateRacer, m)
		end
		racers.ChildAdded:Connect(function(m)
			task.wait(0.1)
			decorateRacer(m)
		end)
	end
	RunService.RenderStepped:Connect(update)
end

return PetFollow
