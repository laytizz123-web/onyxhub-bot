-- Coeur du combat : M1 + combos, blocage, dash, competences, degats, stun, knockback, ultimate.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local ProgressionService = require(script.Parent.ProgressionService)
local MapBuilder = require(script.Parent.MapBuilder)

local CombatService = {}
local C = Config.Combat

local states = {} -- [Player] = state

local function getState(player)
	local s = states[player]
	if not s then
		s = { combo = 0, lastM1 = 0, comboLockUntil = 0, cooldowns = {}, busyUntil = 0, dashAt = 0, buffUntil = 0, buffMult = 1, ultUntil = 0, stunToken = 0 }
		states[player] = s
	end
	return s
end

local function getChar(player)
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if humanoid and hrp and humanoid.Health > 0 then
		return character, humanoid, hrp
	end
	return nil
end

local function getDef(player)
	local data = DataService.Get(player)
	return Config.CharacterById[data and data.Character or "Fighter"] or Config.Characters[1]
end

local function isStunned(character)
	return (character:GetAttribute("StunUntil") or 0) > os.clock()
end

local function updateSpeed(player)
	local character, humanoid = getChar(player)
	if not character then
		return
	end
	local s = getState(player)
	local base = character:GetAttribute("BaseSpeed") or 16
	local speed = base
	if s.buffUntil > os.clock() then
		speed = speed * s.buffMult
	end
	if character:GetAttribute("Blocking") then
		speed = C.BlockMoveSpeed
	end
	if isStunned(character) then
		speed = 0
	end
	humanoid.WalkSpeed = speed
end

local function canAct(player)
	local character, humanoid, hrp = getChar(player)
	if not character then
		return false
	end
	if isStunned(character) then
		return false
	end
	local s = getState(player)
	if s.busyUntil > os.clock() then
		return false
	end
	if MapBuilder.IsSafe(hrp.Position) then
		Remotes.Notify:FireClient(player, "Pas de combat dans la zone sure !", "info")
		return false
	end
	return true, character, humanoid, hrp
end

-- Cibles ------------------------------------------------------------------------

local function collectTargets(parts, attackerCharacter)
	local found = {}
	local list = {}
	for _, part in ipairs(parts) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and model ~= attackerCharacter and not found[model] then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			local hrp = model:FindFirstChild("HumanoidRootPart")
			if humanoid and hrp and humanoid.Health > 0 and not MapBuilder.IsSafe(hrp.Position) then
				found[model] = true
				table.insert(list, model)
			end
		end
	end
	return list
end

local function targetsInBox(attackerCharacter, cframe, size)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attackerCharacter, workspace:FindFirstChild("OnyxBattlegrounds") }
	return collectTargets(workspace:GetPartBoundsInBox(cframe, size, params), attackerCharacter)
end

local function targetsInRadius(attackerCharacter, position, radius)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attackerCharacter, workspace:FindFirstChild("OnyxBattlegrounds") }
	return collectTargets(workspace:GetPartBoundsInRadius(position, radius, params), attackerCharacter)
end

-- Degats ------------------------------------------------------------------------

local function stun(model, duration)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local untilTime = os.clock() + duration
	if (model:GetAttribute("StunUntil") or 0) < untilTime then
		model:SetAttribute("StunUntil", untilTime)
	end
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		local s = getState(player)
		s.stunToken += 1
		local token = s.stunToken
		-- Interrompt le blocage
		model:SetAttribute("Blocking", false)
		updateSpeed(player)
		task.delay(duration, function()
			if s.stunToken == token then
				updateSpeed(player)
			end
		end)
	end
end

local function knockback(model, direction, power, lift)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp or hrp.Anchored then
		return
	end
	local attachment = hrp:FindFirstChild("RootAttachment") or hrp:FindFirstChildOfClass("Attachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "RootAttachment"
		attachment.Parent = hrp
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = attachment
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.MaxForce = 1e6
	lv.VectorVelocity = flat.Unit * power + Vector3.new(0, lift or 0, 0)
	lv.Parent = hrp
	Debris:AddItem(lv, 0.15)
end

local function knockdown(model, duration)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.PlatformStand = true
	task.delay(duration, function()
		if humanoid.Parent then
			humanoid.PlatformStand = false
		end
	end)
end

local function addUlt(character, amount)
	if character:GetAttribute("UltActive") then
		return
	end
	local current = character:GetAttribute("Ult") or 0
	local newValue = math.clamp(current + amount, 0, 100)
	character:SetAttribute("Ult", newValue)
	if current < 100 and newValue >= 100 then
		local player = Players:GetPlayerFromCharacter(character)
		if player then
			Remotes.Notify:FireClient(player, "ULTIMATE PRET ! Appuie sur G", "ult")
		end
	end
end

local function applyHit(attacker, attackerCharacter, victim, damage, opts)
	local humanoid = victim:FindFirstChildOfClass("Humanoid")
	local vhrp = victim:FindFirstChild("HumanoidRootPart")
	local ahrp = attackerCharacter:FindFirstChild("HumanoidRootPart")
	if not humanoid or not vhrp or not ahrp or humanoid.Health <= 0 then
		return
	end
	local blocked = false
	if victim:GetAttribute("Blocking") and not opts.guardBreak then
		blocked = true
		damage = damage * (1 - (opts.isSkill and C.BlockSkillReduction or C.BlockReduction))
	end
	if attackerCharacter:GetAttribute("UltActive") then
		damage = damage * C.UltDamageMultiplier
	end
	damage = math.floor(damage + 0.5)

	humanoid.Health = math.max(0, humanoid.Health - damage)
	victim:SetAttribute("LastDamager", attacker.UserId)
	victim:SetAttribute("LastDamageTime", os.clock())

	local direction = (vhrp.Position - ahrp.Position)
	if blocked then
		stun(victim, 0.15)
		if opts.knockback then
			knockback(victim, direction, opts.knockback * 0.3, 0)
		end
	else
		if opts.guardBreak and victim:GetAttribute("Blocking") then
			victim:SetAttribute("Blocking", false)
		end
		stun(victim, opts.stun or C.HitStun)
		if opts.knockback and opts.knockback > 0 then
			knockback(victim, direction, opts.knockback, opts.lift or 8)
		end
		if opts.knockdown then
			knockdown(victim, 0.9)
		end
	end

	addUlt(attackerCharacter, damage * C.UltPerDamageDealt)
	if Players:GetPlayerFromCharacter(victim) then
		addUlt(victim, damage * C.UltPerDamageTaken)
	end
	ProgressionService.OnHit(attacker, damage)

	Remotes.CombatFX:FireAllClients("Hit", {
		position = vhrp.Position,
		damage = damage,
		blocked = blocked,
		heavy = opts.heavy or false,
		color = opts.color,
		attacker = attacker.UserId,
		victimName = victim.Name,
	})
end

-- M1 ------------------------------------------------------------------------------

local function onM1(player)
	local ok, character, humanoid, hrp = canAct(player)
	if not ok then
		return
	end
	local s = getState(player)
	local now = os.clock()
	if now < s.comboLockUntil or now - s.lastM1 < C.M1Cooldown then
		return
	end
	if now - s.lastM1 > C.ComboReset then
		s.combo = 0
	end
	s.lastM1 = now
	s.combo += 1
	local def = getDef(player)
	local finisher = s.combo >= 4
	Remotes.CombatFX:FireAllClients("Swing", { userId = player.UserId, combo = s.combo, color = def.color })

	task.delay(0.1, function()
		local character2, _, hrp2 = getChar(player)
		if not character2 then
			return
		end
		local cf = hrp2.CFrame * CFrame.new(0, 0, -C.M1Range / 2)
		for _, victim in ipairs(targetsInBox(character2, cf, C.M1Hitbox)) do
			if finisher then
				applyHit(player, character2, victim, def.m1Finisher, { knockback = C.FinisherKnockback, lift = 14, stun = C.FinisherStun, guardBreak = true, heavy = true, color = def.color })
			else
				applyHit(player, character2, victim, def.m1Damage, { knockback = 6, lift = 2, stun = C.HitStun, color = def.color })
			end
		end
	end)

	if finisher then
		s.combo = 0
		s.comboLockUntil = now + C.ComboEndCooldown
	end
end

-- Blocage ---------------------------------------------------------------------------

local function onBlock(player, enabled)
	local character = getChar(player)
	if not character then
		return
	end
	if enabled and isStunned(character) then
		return
	end
	character:SetAttribute("Blocking", enabled == true)
	updateSpeed(player)
	Remotes.CombatFX:FireAllClients("Block", { userId = player.UserId, enabled = enabled == true })
end

-- Dash (mouvement cote client, le serveur valide le cooldown et diffuse l'effet)

local function onDash(player, direction)
	local character = getChar(player)
	if not character or isStunned(character) then
		return
	end
	local s = getState(player)
	if os.clock() - s.dashAt < C.DashCooldown - 0.2 then
		return
	end
	s.dashAt = os.clock()
	Remotes.CombatFX:FireAllClients("Dash", { userId = player.UserId, direction = tostring(direction) })
end

-- Competences ----------------------------------------------------------------------

local function executeMelee(player, character, hrp, skill, def)
	local cf = hrp.CFrame * CFrame.new(0, 0, -skill.range / 2)
	for _, victim in ipairs(targetsInBox(character, cf, Vector3.new(8, 7, skill.range))) do
		applyHit(player, character, victim, skill.damage, { isSkill = true, knockback = skill.knockback, lift = skill.lift, stun = skill.stun, knockdown = skill.knockdown, heavy = true, color = def.color })
	end
	Remotes.CombatFX:FireAllClients("Strike", { position = (hrp.CFrame * CFrame.new(0, 0, -4)).Position, color = def.color, size = skill.range })
end

local function executeRush(player, character, hrp, skill, def)
	local hit = {}
	local startTime = os.clock()
	while os.clock() - startTime < skill.duration + 0.1 do
		local character2, _, hrp2 = getChar(player)
		if not character2 then
			return
		end
		local cf = hrp2.CFrame * CFrame.new(0, 0, -4)
		for _, victim in ipairs(targetsInBox(character2, cf, Vector3.new(8, 7, 9))) do
			if not hit[victim] then
				hit[victim] = true
				applyHit(player, character2, victim, skill.damage, { isSkill = true, knockback = skill.knockback, lift = skill.lift or 10, stun = skill.stun, knockdown = skill.knockdown, heavy = true, color = def.color })
			end
		end
		task.wait(0.05)
	end
end

local function executeAoe(player, character, hrp, skill, def)
	Remotes.CombatFX:FireAllClients("AOE", { position = hrp.Position, radius = skill.radius, color = def.color, sound = skill.sound })
	for _, victim in ipairs(targetsInRadius(character, hrp.Position, skill.radius)) do
		applyHit(player, character, victim, skill.damage, { isSkill = true, knockback = skill.knockback, lift = skill.lift, stun = skill.stun, knockdown = skill.knockdown, heavy = true, color = def.color })
	end
end

local function executeProjectile(player, character, hrp, skill, def)
	local size = skill.radius > 8 and 4 or 2.5
	local part = Instance.new("Part")
	part.Name = "Projectile"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(size, size, size)
	part.Material = Enum.Material.Neon
	part.Color = def.color
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CFrame = hrp.CFrame * CFrame.new(0, 0.5, -4)
	local att = Instance.new("Attachment")
	att.Parent = part
	local force = Instance.new("VectorForce")
	force.Attachment0 = att
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.Parent = part
	local light = Instance.new("PointLight")
	light.Color = def.color
	light.Range = 18
	light.Brightness = 3
	light.Parent = part
	local trail = Instance.new("ParticleEmitter")
	trail.Rate = 60
	trail.Lifetime = NumberRange.new(0.3, 0.5)
	trail.Speed = NumberRange.new(0, 2)
	trail.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.6), NumberSequenceKeypoint.new(1, 0) })
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(def.color, Color3.new(1, 1, 1))
	trail.Parent = part
	part.Parent = workspace
	force.Force = Vector3.new(0, part:GetMass() * workspace.Gravity, 0)
	pcall(function()
		part:SetNetworkOwner(nil)
	end)
	local direction = hrp.CFrame.LookVector
	part.AssemblyLinearVelocity = direction * skill.speed

	local startTime = os.clock()
	local exploded = false
	local function explode(position)
		if exploded then
			return
		end
		exploded = true
		part:Destroy()
		Remotes.CombatFX:FireAllClients("AOE", { position = position, radius = skill.radius, color = def.color, sound = skill.sound })
		local character2 = player.Character or character
		for _, victim in ipairs(targetsInRadius(character2, position, skill.radius)) do
			applyHit(player, character2, victim, skill.damage, { isSkill = true, knockback = skill.knockback, lift = skill.lift, stun = skill.stun, knockdown = skill.knockdown, heavy = true, color = def.color })
		end
	end
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if exploded or not part.Parent then
			connection:Disconnect()
			return
		end
		part.AssemblyLinearVelocity = direction * skill.speed
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character, part }
		local result = workspace:Raycast(part.Position, direction * (skill.speed / 60 + size), params)
		if result then
			connection:Disconnect()
			explode(result.Position)
		elseif os.clock() - startTime > skill.lifetime then
			connection:Disconnect()
			explode(part.Position)
		end
	end)
end

local function executeBuff(player, character, hrp, skill, def)
	local s = getState(player)
	s.buffUntil = os.clock() + skill.duration
	s.buffMult = skill.speedMultiplier or 1.3
	updateSpeed(player)
	Remotes.CombatFX:FireAllClients("Buff", { userId = player.UserId, color = def.color, duration = skill.duration })
	task.delay(skill.duration, function()
		updateSpeed(player)
	end)
end

local executors = { melee = executeMelee, rush = executeRush, aoe = executeAoe, projectile = executeProjectile, buff = executeBuff }

local function onSkill(player, slot)
	slot = tonumber(slot)
	if not slot or slot < 1 or slot > 4 then
		return
	end
	local ok, character, humanoid, hrp = canAct(player)
	if not ok then
		return
	end
	if character:GetAttribute("Blocking") then
		return
	end
	local def = getDef(player)
	local ultActive = character:GetAttribute("UltActive") == true
	local skill = (ultActive and def.ultSkills or def.skills)[slot]
	if not skill then
		return
	end
	local s = getState(player)
	local key = (ultActive and "U" or "S") .. slot
	local now = os.clock()
	if (s.cooldowns[key] or 0) > now then
		return
	end
	s.cooldowns[key] = now + skill.cooldown
	s.busyUntil = now + skill.windup + 0.1
	s.combo = 0

	Remotes.SkillAck:FireClient(player, { slot = slot, cooldown = skill.cooldown, type = skill.type, windup = skill.windup, distance = skill.distance, duration = skill.duration })
	Remotes.CombatFX:FireAllClients("Cast", { userId = player.UserId, name = skill.name, pose = skill.pose, color = def.color, type = skill.type, windup = skill.windup, sound = skill.sound, ult = ultActive })

	task.delay(skill.windup, function()
		local character2, _, hrp2 = getChar(player)
		if not character2 or isStunned(character2) then
			return
		end
		executors[skill.type](player, character2, hrp2, skill, def)
	end)
end

-- Ultimate ---------------------------------------------------------------------------

local function onUltimate(player)
	local character = getChar(player)
	if not character or isStunned(character) then
		return
	end
	if character:GetAttribute("UltActive") or (character:GetAttribute("Ult") or 0) < 100 then
		return
	end
	local s = getState(player)
	local def = getDef(player)
	character:SetAttribute("UltActive", true)
	s.ultUntil = os.clock() + C.UltDuration
	s.busyUntil = os.clock() + 0.8
	Remotes.CombatFX:FireAllClients("UltStart", { userId = player.UserId, color = def.color, duration = C.UltDuration })
	Remotes.Notify:FireAllClients(player.DisplayName .. " active son ULTIMATE !", "ult")
	task.spawn(function()
		local startTime = os.clock()
		while os.clock() - startTime < C.UltDuration do
			task.wait(0.25)
			local c = player.Character
			if not c or c ~= character then
				return
			end
			character:SetAttribute("Ult", 100 * (1 - (os.clock() - startTime) / C.UltDuration))
		end
		if character.Parent then
			character:SetAttribute("Ult", 0)
			character:SetAttribute("UltActive", false)
			Remotes.CombatFX:FireAllClients("UltEnd", { userId = player.UserId })
		end
	end)
end

function CombatService.Init()
	Remotes.Combat.OnServerEvent:Connect(function(player, action, arg)
		if action == "m1" then
			onM1(player)
		elseif action == "block" then
			onBlock(player, arg == true)
		elseif action == "dash" then
			onDash(player, arg)
		elseif action == "skill" then
			onSkill(player, arg)
		elseif action == "ult" then
			onUltimate(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			local s = getState(player)
			s.cooldowns = {}
			s.combo = 0
			s.busyUntil = 0
			s.buffUntil = 0
		end)
	end)
end

return CombatService
