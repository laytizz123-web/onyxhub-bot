-- Planeur du joueur local : ouverture en l'air (Espace / bouton saut), pilotage a la camera
-- (regarder vers le bas = piquer et accelerer, vers le haut = remonter en perdant de la vitesse),
-- boost (Shift / bouton), colonnes de vent, anneaux d'elan. Ailes visibles pour tous les joueurs.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Glider = {}
Glider.Gliding = false
Glider.Speed = 0
Glider.Stamina = 3
Glider.MaxStamina = 3
Glider.Airborne = false
Glider.InUpdraft = false
Glider.Signal = Instance.new("BindableEvent") -- ("open"|"close"|"ring"|"updraft")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local char, hum, hrp
local att, linVel, align
local yaw, pitch, roll = 0, 0, 0
local boosting = false
local lastToggle = 0
local airSince = 0
local ringCooldown = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = false

local function stats()
	return Config.GliderById[player:GetAttribute("Glider") or "Lin"] or Config.Gliders[1]
end

local function convoyNearby()
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local o = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			if o and hrp and (o.Position - hrp.Position).Magnitude <= Config.Delivery.ConvoyRadius then
				return true
			end
		end
	end
	return false
end

local function groundDistance()
	rayParams.FilterDescendantsInstances = { char }
	local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -6, 0), rayParams)
	return hit and (hrp.Position.Y - hit.Position.Y) or math.huge, hit
end

local function setConstraints(on)
	if on then
		att = Instance.new("Attachment")
		att.Name = "GliderAtt"
		att.Parent = hrp
		linVel = Instance.new("LinearVelocity")
		linVel.Attachment0 = att
		linVel.MaxForce = math.huge
		linVel.RelativeTo = Enum.ActuatorRelativeTo.World
		linVel.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		linVel.VectorVelocity = hrp.AssemblyLinearVelocity
		linVel.Parent = hrp
		align = Instance.new("AlignOrientation")
		align.Mode = Enum.OrientationAlignmentMode.OneAttachment
		align.Attachment0 = att
		align.Responsiveness = 18
		align.MaxTorque = math.huge
		align.CFrame = hrp.CFrame.Rotation
		align.Parent = hrp
	else
		for _, o in ipairs({ linVel, align, att }) do
			if o then
				o:Destroy()
			end
		end
		att, linVel, align = nil, nil, nil
	end
end

function Glider.Open()
	if Glider.Gliding or not hrp or hum.Health <= 0 then
		return
	end
	Glider.Gliding = true
	local look = camera.CFrame.LookVector
	yaw = math.atan2(-look.X, -look.Z)
	local v = hrp.AssemblyLinearVelocity
	Glider.Speed = math.max(Vector3.new(v.X, 0, v.Z).Magnitude, stats().cruise * 0.8)
	hum.PlatformStand = true
	setConstraints(true)
	Remotes.Request:FireServer("glide", true)
	Glider.Signal:Fire("open")
end

function Glider.Close()
	if not Glider.Gliding then
		return
	end
	Glider.Gliding = false
	local v = linVel and linVel.VectorVelocity or Vector3.zero
	setConstraints(false)
	if hum then
		hum.PlatformStand = false
		hum:ChangeState(Enum.HumanoidStateType.Freefall)
	end
	if hrp then
		hrp.AssemblyLinearVelocity = Vector3.new(v.X * 0.4, math.min(v.Y, 0), v.Z * 0.4)
		local _, y, _ = hrp.CFrame:ToEulerAnglesYXZ()
		hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, y, 0)
	end
	Remotes.Request:FireServer("glide", false)
	Glider.Signal:Fire("close")
end

local function toggle()
	if os.clock() - lastToggle < 0.3 then
		return
	end
	if Glider.Gliding then
		lastToggle = os.clock()
		Glider.Close()
	elseif Glider.Airborne and os.clock() - airSince > 0.18 then
		lastToggle = os.clock()
		Glider.Open()
	end
end

-- Colonnes de vent : renvoie la poussee verticale a cette position
local function updraftLift(pos)
	for _, u in ipairs(CollectionService:GetTagged("Updraft")) do
		local r = u:GetAttribute("Radius") or 8
		local bottom = u:GetAttribute("Bottom") or 0
		local top = u:GetAttribute("Top") or 50
		local d = Vector3.new(pos.X - u.Position.X, 0, pos.Z - u.Position.Z).Magnitude
		if d <= r and pos.Y >= bottom - 3 and pos.Y <= top + 6 then
			local k = math.clamp((top + 6 - pos.Y) / 12, 0, 1) -- s'attenue au sommet
			return (u:GetAttribute("Strength") or 45) * k
		end
	end
	return 0
end

local function checkRings(pos)
	for _, c in ipairs(CollectionService:GetTagged("WindRing")) do
		local r = c:GetAttribute("Radius") or 9
		if (c.Position - pos).Magnitude < r and (not ringCooldown[c] or os.clock() - ringCooldown[c] > 2) then
			ringCooldown[c] = os.clock()
			Glider.Speed = math.min(stats().max, Glider.Speed + 28)
			Glider.Stamina = math.min(Glider.MaxStamina, Glider.Stamina + 1)
			Glider.Signal:Fire("ring")
		end
	end
end

local function step(dt)
	if not (hrp and hum and hrp.Parent) then
		return
	end
	dt = math.min(dt, 0.05)
	local s = stats()
	Glider.MaxStamina = s.stamina
	local state = hum:GetState()
	local dist, hit = groundDistance()
	Glider.Airborne = dist > 3.6 and state ~= Enum.HumanoidStateType.Swimming
	if not Glider.Airborne then
		airSince = os.clock()
	end
	local lift = updraftLift(hrp.Position)
	Glider.InUpdraft = lift > 0
	if not Glider.Gliding then
		-- recharge au sol, la colonne de vent porte aussi les pietons (ascenseur naturel)
		if not Glider.Airborne then
			Glider.Stamina = math.min(s.stamina, Glider.Stamina + dt * 1.5)
		end
		if lift > 0 and hum.Health > 0 then
			local v = hrp.AssemblyLinearVelocity
			hrp.AssemblyLinearVelocity = Vector3.new(v.X, math.max(v.Y, lift * 0.75), v.Z)
			if state ~= Enum.HumanoidStateType.Freefall then
				hum:ChangeState(Enum.HumanoidStateType.Freefall)
			end
		end
		return
	end
	-- atterrissage / eau / mort
	if hum.Health <= 0 or (dist < 3.2 and hit) or state == Enum.HumanoidStateType.Swimming or (hit and hit.Material == Enum.Material.Water) then
		Glider.Close()
		return
	end
	local look = camera.CFrame.LookVector
	local targetYaw = math.atan2(-look.X, -look.Z)
	local dyaw = (targetYaw - yaw + math.pi) % (2 * math.pi) - math.pi
	local maxTurn = math.rad(150) * dt
	local turn = math.clamp(dyaw, -maxTurn, maxTurn)
	yaw += turn
	local targetPitch = math.clamp(math.asin(math.clamp(look.Y, -1, 1)), math.rad(-55), math.rad(22))
	pitch += (targetPitch - pitch) * math.clamp(dt * 4, 0, 1)
	roll += (math.clamp(-turn / dt * 0.35, -0.6, 0.6) - roll) * math.clamp(dt * 5, 0, 1)
	-- energie : piquer accelere, cabrer ralentit
	local accel = -math.sin(pitch) * 60 - 0.55 * (Glider.Speed - s.cruise)
	if boosting and Glider.Stamina > 0 then
		accel += 55
		Glider.Stamina = math.max(0, Glider.Stamina - dt)
	end
	Glider.Speed = math.clamp(Glider.Speed + accel * dt, 12, s.max)
	local dir = Vector3.new(-math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch))
	local sink = s.sink
	if player:GetAttribute("Heavy") and not convoyNearby() then
		sink *= 1.6
	end
	local vertical = -sink + lift * 0.9
	if lift > 0 then
		Glider.Speed = math.max(Glider.Speed, s.cruise * 0.7)
	end
	linVel.VectorVelocity = dir * Glider.Speed + Vector3.new(0, vertical, 0)
	align.CFrame = CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(-68) + pitch * 0.6, 0, roll)
	checkRings(hrp.Position)
	Glider.Signal:Fire("tick")
end

local function onCharacter(c)
	Glider.Gliding = false
	setConstraints(false)
	char = c
	hum = c:WaitForChild("Humanoid")
	hrp = c:WaitForChild("HumanoidRootPart")
	Glider.Stamina = stats().stamina
	hum.Died:Connect(function()
		if Glider.Gliding then
			Glider.Close()
		end
	end)
end

-- Ailes visibles sur tous les personnages en vol ------------------------------------------------
local wings = {} -- [player] = Model

local function buildWings(p)
	local c = p.Character
	local torso = c and (c:FindFirstChild("UpperTorso") or c:FindFirstChild("Torso"))
	if not torso then
		return
	end
	local g = Config.GliderById[p:GetAttribute("Glider") or "Lin"] or Config.Gliders[1]
	local m = Instance.new("Model")
	m.Name = "GliderWings"
	local function piece(size, cf, color, material, transparency)
		local w = Instance.new("WedgePart")
		w.Size = size
		w.Color = color
		w.Material = material
		w.Transparency = transparency or 0
		w.CanCollide = false
		w.CanQuery = false
		w.CanTouch = false
		w.Massless = true
		w.CastShadow = true
		w.CFrame = torso.CFrame * cf
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = torso
		weld.Part1 = w
		weld.Parent = w
		w.Parent = m
		return w
	end
	local span = 5.5 + g.index * 0.5
	for _, s in ipairs({ -1, 1 }) do
		-- toile principale (triangle) + bord d'attaque
		piece(Vector3.new(0.12, 2.6, span), CFrame.new(s * (span / 2 + 0.4), 0.2, 0.9) * CFrame.Angles(0, math.rad(s * 90), 0) * CFrame.Angles(0, 0, 0), g.color, Enum.Material.Fabric)
		local spar = Instance.new("Part")
		spar.Size = Vector3.new(span + 0.6, 0.22, 0.22)
		spar.Color = g.accent
		spar.Material = Enum.Material.Wood
		spar.CanCollide = false
		spar.CanQuery = false
		spar.Massless = true
		spar.CFrame = torso.CFrame * CFrame.new(s * (span / 2 + 0.4), 1.45, 0.9)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = torso
		weld.Part1 = spar
		weld.Parent = spar
		spar.Parent = m
	end
	m.Parent = c
	wings[p] = m
end

local function updateWings(p)
	local on = p:GetAttribute("Gliding") == true
	if p == player then
		on = Glider.Gliding
	end
	local existing = wings[p]
	if on and not (existing and existing.Parent) then
		buildWings(p)
	elseif not on and existing then
		existing:Destroy()
		wings[p] = nil
	end
end

local function watch(p)
	p:GetAttributeChangedSignal("Gliding"):Connect(function()
		updateWings(p)
	end)
	p:GetAttributeChangedSignal("Glider"):Connect(function()
		if wings[p] then
			wings[p]:Destroy()
			wings[p] = nil
			updateWings(p)
		end
	end)
	p.CharacterAdded:Connect(function()
		wings[p] = nil
	end)
end

function Glider.Init()
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
	UserInputService.JumpRequest:Connect(toggle)
	ContextActionService:BindAction("WindmailBoost", function(_, inputState)
		boosting = inputState == Enum.UserInputState.Begin
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonR2)
	ContextActionService:SetTitle("WindmailBoost", "Boost")
	ContextActionService:SetPosition("WindmailBoost", UDim2.new(1, -170, 1, -150))
	ContextActionService:BindAction("WindmailGlide", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			if Glider.Gliding then
				Glider.Close()
			elseif Glider.Airborne then
				Glider.Open()
			end
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle("WindmailGlide", "Planer")
	ContextActionService:SetPosition("WindmailGlide", UDim2.new(1, -95, 1, -210))
	for _, p in ipairs(Players:GetPlayers()) do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(p)
		wings[p] = nil
	end)
	Glider.Signal.Event:Connect(function(kind)
		if kind == "open" or kind == "close" then
			updateWings(player)
		end
	end)
	RunService.Heartbeat:Connect(step)
end

return Glider
