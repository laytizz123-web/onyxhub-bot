-- Le ballon : guidage vers la cible, renvois, vitesse croissante, overdrive.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Ball = {}
Ball.__index = Ball

local function lerpColor(a, b, t)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

local function getRoot(player)
	local char = player and player.Character
	if not char then
		return nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hrp and hum and hum.Health > 0 then
		return hrp
	end
	return nil
end

function Ball.new(options)
	local self = setmetatable({}, Ball)
	self.isAlive = options.isAlive -- function(player) -> bool
	self.getAlive = options.getAlive -- function() -> {Player}
	self.onHit = options.onHit -- function(player, position)
	self.onDeflect = options.onDeflect -- function(player, newTarget, speed)
	self.practice = options.practice == true

	self.baseSpeed = Config.Ball.BaseSpeed
	self.speed = self.baseSpeed
	self.direction = Vector3.new(0, 0, 1)
	self.deflects = 0
	self.target = nil
	self.graceUntil = 0
	self.slowUntil = 0
	self.burstUntil = 0
	self.lastDeflect = {}
	self.overdrive = false
	self.destroyed = false

	self:_build(options.position or (Config.Arena.Center + Vector3.new(0, 8, 0)))
	self.connection = RunService.Heartbeat:Connect(function(dt)
		self:_step(dt)
	end)
	return self
end

function Ball:_build(position)
	local s = Config.Ball.Size
	local part = Instance.new("Part")
	part.Name = "ArenaBall"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(s, s, s)
	part.Material = Enum.Material.Neon
	part.Color = Color3.new(1, 1, 1)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CustomPhysicalProperties = PhysicalProperties.new(0.2, 0, 0)
	part.CFrame = CFrame.new(position)
	part:SetAttribute("Speed", self.speed)
	part:SetAttribute("TargetUserId", 0)
	part:SetAttribute("Deflects", 0)
	part:SetAttribute("Overdrive", false)

	local center = Instance.new("Attachment")
	center.Name = "Center"
	center.Parent = part
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, s / 2, 0)
	top.Parent = part
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -s / 2, 0)
	bottom.Parent = part

	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.4
	trail.MinLength = 0.1
	trail.LightEmission = 1
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.Color = ColorSequence.new(Config.Colors.Accent, Config.Colors.Accent2)
	trail.Parent = part

	local light = Instance.new("PointLight")
	light.Brightness = 4
	light.Range = 30
	light.Color = Config.Colors.Accent
	light.Parent = part

	local particles = Instance.new("ParticleEmitter")
	particles.Rate = 25
	particles.Lifetime = NumberRange.new(0.3, 0.6)
	particles.Speed = NumberRange.new(2, 5)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	particles.Transparency = NumberSequence.new(0.2, 1)
	particles.LightEmission = 1
	particles.Color = ColorSequence.new(Color3.new(1, 1, 1), Config.Colors.Accent)
	particles.Parent = part

	part.Parent = workspace

	-- Annule la gravite
	local force = Instance.new("VectorForce")
	force.Attachment0 = center
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.new(0, part:GetMass() * workspace.Gravity, 0)
	force.Parent = part

	pcall(function()
		part:SetNetworkOwner(nil)
	end)

	self.part = part
	self.light = light
	self.trail = trail
	self.particles = particles
end

function Ball:_updateLook()
	local t = math.clamp((self.speed - Config.Ball.BaseSpeed) / (Config.Ball.MaxSpeed - Config.Ball.BaseSpeed), 0, 1)
	local color
	if self.overdrive then
		color = lerpColor(Config.Colors.Accent2, Config.Colors.Danger, t)
	elseif t < 0.5 then
		color = lerpColor(Color3.new(1, 1, 1), Config.Colors.Gold, t * 2)
	else
		color = lerpColor(Config.Colors.Gold, Config.Colors.Danger, (t - 0.5) * 2)
	end
	self.part.Color = color
	self.light.Color = color
	self.trail.Color = ColorSequence.new(color, self.overdrive and Config.Colors.Accent2 or Config.Colors.Accent)
	self.trail.Lifetime = 0.4 + t * 0.6
	self.part:SetAttribute("Speed", math.floor(self.speed + 0.5))
	self.part:SetAttribute("Deflects", self.deflects)
end

function Ball:_isValidTarget(player)
	if not player or player.Parent ~= Players then
		return false
	end
	if not self.isAlive(player) then
		return false
	end
	return getRoot(player) ~= nil
end

function Ball:_setTarget(player)
	self.target = player
	local now = os.clock()
	self.graceUntil = math.max(self.graceUntil, now + Config.Ball.GraceTime)
	self.part:SetAttribute("TargetUserId", player and player.UserId or 0)
	local hrp = player and getRoot(player)
	if hrp then
		local dir = hrp.Position - self.part.Position
		if dir.Magnitude > 0.01 then
			self.direction = dir.Unit
		end
	end
	Remotes.BallEvent:FireAllClients("Target", { userId = player and player.UserId or 0 })
end

function Ball:_retarget(exclude)
	local candidates = {}
	for _, p in ipairs(self.getAlive()) do
		if p ~= exclude and self:_isValidTarget(p) then
			table.insert(candidates, p)
		end
	end
	if #candidates == 0 then
		if exclude and self:_isValidTarget(exclude) then
			candidates = { exclude }
		else
			self:_setTarget(nil)
			return
		end
	end
	-- Evite de viser quelqu'un colle au ballon (coup impossible a parer)
	local far = {}
	for _, p in ipairs(candidates) do
		local hrp = getRoot(p)
		if hrp and (hrp.Position - self.part.Position).Magnitude > 14 then
			table.insert(far, p)
		end
	end
	local pool = (#far > 0) and far or candidates
	self:_setTarget(pool[math.random(#pool)])
end

function Ball:_hit(target)
	local now = os.clock()
	self.graceUntil = now + 0.5
	local pos = self.part.Position
	Remotes.BallEvent:FireAllClients("Hit", { userId = target.UserId, position = pos })

	self.speed = self.baseSpeed
	self.deflects = 0
	self.burstUntil = 0
	self.slowUntil = 0
	self:_updateLook()

	-- Le ballon repart du centre pour laisser le temps de reagir
	self.part.CFrame = CFrame.new(Config.Arena.Center + Vector3.new(0, 8, 0))
	self.part.AssemblyLinearVelocity = Vector3.zero

	if self.onHit then
		self.onHit(target, pos)
	end
	local exclude = target
	if self.practice then
		exclude = nil
	end
	self:_retarget(exclude)
end

function Ball:_step(dt)
	if self.destroyed then
		return
	end
	local now = os.clock()
	local target = self.target
	if not self:_isValidTarget(target) then
		self:_retarget(nil)
		target = self.target
		if not target then
			self.part.AssemblyLinearVelocity = Vector3.zero
			return
		end
	end

	local hrp = getRoot(target)
	if not hrp then
		return
	end
	local targetPos = hrp.Position + Vector3.new(0, Config.Ball.Height - 2, 0)
	local toTarget = targetPos - self.part.Position
	local dist = toTarget.Magnitude

	local speed = self.speed
	if now < self.burstUntil then
		speed = speed * 1.4
	end
	if now < self.slowUntil then
		speed = speed * Config.Abilities.Pulse.SlowFactor
	end

	if now >= self.graceUntil and dist <= Config.Ball.HitRadius + speed * dt then
		self:_hit(target)
		return
	end

	local desired = toTarget / math.max(dist, 0.001)
	local turnRate = Config.Ball.TurnRate * (1 + speed / 120)
	local turn = math.clamp(dt * turnRate, 0, 1)
	local dir = self.direction:Lerp(desired, turn)
	if dir.Magnitude < 0.01 then
		dir = desired
	end
	self.direction = dir.Unit

	self.part.AssemblyLinearVelocity = self.direction * speed
	self.part.AssemblyAngularVelocity = Vector3.zero

	-- Securite : si le ballon s'est echappe
	local offset = self.part.Position - Config.Arena.Center
	if offset.Magnitude > Config.Arena.Radius * 2 or self.part.Position.Y < Config.Arena.KillHeight then
		self.part.CFrame = CFrame.new(Config.Arena.Center + Vector3.new(0, 8, 0))
	end
end

-- Tentative de renvoi par un joueur. Retourne true si reussi.
function Ball:deflect(player)
	if self.destroyed then
		return false, "no-ball"
	end
	local now = os.clock()
	local last = self.lastDeflect[player] or 0
	if now - last < Config.Ball.DeflectCooldown then
		return false, "cooldown"
	end
	self.lastDeflect[player] = now

	local hrp = getRoot(player)
	if not hrp then
		return false, "dead"
	end
	local dist = (hrp.Position - self.part.Position).Magnitude
	if dist > Config.Ball.DeflectRange or self.target ~= player then
		Remotes.BallEvent:FireAllClients("Swing", { userId = player.UserId, hit = false })
		return false, (dist > Config.Ball.DeflectRange) and "far" or "not-target"
	end

	self.deflects += 1
	self.speed = math.min(self.speed * Config.Ball.SpeedPerDeflect + Config.Ball.SpeedBonus, Config.Ball.MaxSpeed)
	self.burstUntil = now + 0.25
	self.slowUntil = 0
	self:_updateLook()

	-- Petit recul instantane pour que le ballon parte du joueur
	local away = (self.part.Position - hrp.Position)
	if away.Magnitude > 0.01 then
		self.part.CFrame = CFrame.new(hrp.Position + away.Unit * math.max(dist, 5) + Vector3.new(0, 1, 0))
	end

	self:_retarget(player)

	Remotes.BallEvent:FireAllClients("Deflect", {
		userId = player.UserId,
		position = self.part.Position,
		speed = math.floor(self.speed + 0.5),
		deflects = self.deflects,
		newTarget = self.target and self.target.UserId or 0,
	})
	if self.onDeflect then
		self.onDeflect(player, self.target, self.speed)
	end
	return true
end

function Ball:slow(duration)
	if self.destroyed then
		return
	end
	self.slowUntil = os.clock() + duration
end

function Ball:setOverdrive(enabled)
	if self.destroyed then
		return
	end
	self.overdrive = enabled
	self.baseSpeed = Config.Ball.BaseSpeed * (enabled and Config.Ball.OverdriveMultiplier or 1)
	self.speed = math.max(self.speed, self.baseSpeed)
	self.part:SetAttribute("Overdrive", enabled)
	self:_updateLook()
	Remotes.BallEvent:FireAllClients("Overdrive", { enabled = enabled })
end

function Ball:getPosition()
	if self.destroyed then
		return nil
	end
	return self.part.Position
end

function Ball:destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	if self.connection then
		self.connection:Disconnect()
	end
	Remotes.BallEvent:FireAllClients("Target", { userId = 0 })
	if self.part then
		self.part:Destroy()
	end
end

return Ball
