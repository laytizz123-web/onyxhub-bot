-- Animations procedurales des pets 3D : idle, marche, course, saut, vol et petits mouvements.
-- Chaque Part est rattachee a un groupe (prefixe de son nom). Les groupes tournent autour des pivots
-- definis dans PetRigs. Tout est calcule en une passe et applique avec workspace:BulkMoveTo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetRigs = require(ReplicatedStorage.Shared.PetRigs)

local PetAnimator = {}
PetAnimator.__index = PetAnimator

local rad = math.rad
local sin = math.sin
local cos = math.cos

local DEFAULT_PARENT = {
	Head = "Body",
	Tail = "Body",
	WingL = "Body",
	WingR = "Body",
	EarL = "Head",
	EarR = "Head",
	Fx = "Body",
}
local ORDER = { "Body", "Head", "EarL", "EarR", "Tail", "WingL", "WingR", "LegFL", "LegFR", "LegBL", "LegBR", "Fx" }

function PetAnimator.new(model, petId)
	local self = setmetatable({}, PetAnimator)
	local rig = PetRigs[petId] or { kind = "quad", hover = 0, pivots = {}, parents = {} }
	local scale = model:GetAttribute("PetScale") or 1
	self.model = model
	self.kind = rig.kind
	self.hover = (rig.hover or 0) * scale
	self.scale = scale
	self.phase = math.random() * 10
	self.pivots = {}
	for name, p in pairs(rig.pivots or {}) do
		self.pivots[name] = p * scale
	end
	self.parents = {}
	for _, g in ipairs(ORDER) do
		self.parents[g] = (rig.parents and rig.parents[g]) or DEFAULT_PARENT[g]
	end
	local pivot = model:GetPivot()
	self.parts = {}
	self.offsets = {}
	self.groups = {}
	self.rainbow = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			table.insert(self.parts, part)
			table.insert(self.offsets, pivot:ToObjectSpace(part.CFrame))
			local group = string.match(part.Name, "^(%w+)") or "Body"
			if not self.parents[group] and not string.match(group, "^Leg") and group ~= "Body" then
				group = "Body"
			end
			table.insert(self.groups, group)
			if string.match(part.Name, "%.eye$") then
				self.eyeIndex = self.eyeIndex or {}
				self.eyeIndex[#self.parts] = true
			end
			if part:GetAttribute("Rainbow") then
				table.insert(self.rainbow, part)
			end
		end
	end
	self.cframes = table.create(#self.parts)
	-- modele d'une seule piece (importe) : animation par sauts et ecrasement
	self.simple = model:GetAttribute("SimplePet") == true
	if self.simple then
		self.sizes = {}
		for i, part in ipairs(self.parts) do
			self.sizes[i] = part.Size
		end
		self.glow = model:FindFirstChild("EvolutionGlow")
	end
	self.hopPhase = 0
	self.nextBlink = os.clock() + 1 + math.random() * 3
	self.blinkUntil = 0
	self.nextTrick = os.clock() + 4 + math.random() * 5
	self.trick = nil
	self.bank = 0
	self.blink = 0
	self.nextBlink = os.clock() + math.random(2, 5)
	return self
end

local function around(pivot, rotation)
	if not pivot then
		return rotation
	end
	return CFrame.new(pivot) * rotation * CFrame.new(-pivot)
end

-- Animation "sautillante" pour les modeles d'une seule piece
function PetAnimator:updateSimple(rootCF, state, now, dt)
	local t = now + self.phase
	local s = self.scale
	local airborne = self.kind == "fly" or self.kind == "float"
	local moving = state == "walk" or state == "run"
	local y, pitch, roll, yawWobble = 0, 0, 0, 0
	local sx, sy = 1, 1
	if airborne then
		y = sin(t * 2.2) * 0.35 * s
		pitch = moving and -12 or sin(t * 1.3) * 4
		roll = sin(t * 1.6) * 6
		sy = 1 + sin(t * 4.4) * 0.03
	elseif moving or state == "jump" then
		-- bonds successifs : arc de saut + ecrasement a l'atterrissage
		local rate = state == "run" and 9 or 6.5
		self.hopPhase = (self.hopPhase + dt * rate) % (math.pi)
		local h = sin(self.hopPhase)
		local height = (state == "run" and 1.3 or 0.9) * s
		if state == "jump" then
			height = 1.8 * s
		end
		y = h * height
		local landing = math.max(0, 1 - self.hopPhase / 0.6) + math.max(0, (self.hopPhase - (math.pi - 0.45)) / 0.45)
		sy = 1 - 0.18 * landing + 0.08 * h
		sx = 1 + 0.12 * landing - 0.04 * h
		pitch = -h * 10
		roll = sin(t * rate * 0.5) * 6
	else
		-- repos : respiration, petit balancement, regarde autour
		sy = 1 + sin(t * 2.6) * 0.035
		sx = 1 - sin(t * 2.6) * 0.02
		roll = sin(t * 0.9) * 4
		yawWobble = sin(t * 0.55) * 14
		self.hopPhase = 0
	self.nextBlink = os.clock() + 1 + math.random() * 3
	self.blinkUntil = 0
	self.nextTrick = os.clock() + 4 + math.random() * 5
	self.trick = nil
	self.bank = 0
	end
	local base = rootCF * CFrame.new(0, y, 0) * CFrame.Angles(0, rad(yawWobble), 0) * CFrame.Angles(rad(pitch), 0, rad(roll))
	local cframes = self.cframes
	for i, part in ipairs(self.parts) do
		local off = self.offsets[i]
		local p = off.Position
		cframes[i] = base * CFrame.new(p.X * sx, p.Y * sy, p.Z * sx) * off.Rotation
		local size = self.sizes[i]
		part.Size = Vector3.new(size.X * sx, size.Y * sy, size.Z * sx)
	end
	workspace:BulkMoveTo(self.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	if self.glow and self.glow:GetAttribute("Rainbow") then
		local c = Color3.fromHSV((now * 0.3) % 1, 0.7, 1)
		self.glow.OutlineColor = c
		self.glow.FillColor = c
	end
end

-- state : "idle" | "walk" | "run" | "jump" ; speed : vitesse du proprietaire (studs/s)
function PetAnimator:update(rootCF, state, now)
	local dt = math.clamp(now - (self.lastUpdate or now), 0, 0.1)
	self.lastUpdate = now
	if self.simple then
		return self:updateSimple(rootCF, state, now, dt)
	end
	local t = now + self.phase
	local s = self.scale
	local kind = self.kind
	local moving = state == "walk" or state == "run"
	local stride = state == "run" and 15 or 10
	local legAmp = (state == "run" and 50) or (state == "walk" and 32) or 0

	local local_ = {}
	-- Corps : respiration, rebond de marche, inclinaison en course
	local bob, lean, roll = 0, 0, 0
	if kind == "fly" or kind == "float" then
		bob = sin(t * 2.2) * 0.25 * s
		lean = moving and -12 or sin(t * 1.3) * 3
		roll = sin(t * 1.1) * 4
	elseif kind == "slither" then
		bob = sin(t * 2) * 0.05 * s
		roll = moving and sin(t * 6) * 10 or sin(t * 1.5) * 4
	else
		if moving then
			bob = math.abs(sin(t * stride)) * (state == "run" and 0.32 or 0.18) * s
			lean = state == "run" and -8 or -3
			roll = sin(t * stride) * 3
		else
			bob = (sin(t * 2.4) * 0.5 + 0.5) * 0.06 * s
		end
	end
	if state == "jump" then
		lean = 10
	end
	-- sautillement (pets a pattes) : tout le pet bondit, les pattes avant battent un peu
	local hopY, hopPitch = 0, 0
	if kind == "quad" and (moving or state == "jump") then
		self.hopPhase = (self.hopPhase + dt * (state == "run" and 11 or 8)) % math.pi
		local h = sin(self.hopPhase)
		hopY = h * (state == "run" and 0.95 or (state == "jump" and 1.4 or 0.65)) * s
		hopPitch = (self.hopPhase < math.pi / 2) and -h * 10 or h * 6
		legAmp = 28
		stride = state == "run" and 11 or 8
	else
		self.hopPhase = 0
	end
	-- petites figures au repos : saut, pirouette, tortillement
	local trickY, trickSpin, trickRoll = 0, 0, 0
	if state ~= "idle" then
		self.trick = nil
		self.nextTrick = now + 4 + math.random() * 5
	elseif not self.trick and now >= self.nextTrick then
		local kinds = { "hop", "spin", "wiggle" }
		self.trick = { kind = kinds[math.random(#kinds)], t0 = now }
	end
	if self.trick then
		local k = (now - self.trick.t0) / 0.9
		if k >= 1 then
			self.trick = nil
			self.nextTrick = now + 5 + math.random() * 5
		else
			local ease = k * k * (3 - 2 * k)
			if self.trick.kind == "hop" then
				trickY = sin(math.pi * k) * 1.3 * s
			elseif self.trick.kind == "spin" then
				trickY = sin(math.pi * k) * 0.7 * s
				trickSpin = 360 * ease
			else
				trickRoll = sin(k * math.pi * 6) * 14 * (1 - k)
			end
		end
	end
	-- virage penche pour les pets qui volent
	local _, yawNow = rootCF:ToEulerAnglesYXZ()
	if self.lastYaw and dt > 0 then
		local dy = (yawNow - self.lastYaw + math.pi) % (2 * math.pi) - math.pi
		local target = (kind == "fly" or kind == "float") and math.clamp(-dy / dt * 9, -30, 30) or 0
		self.bank += (target - self.bank) * math.clamp(dt * 6, 0, 1)
	end
	self.lastYaw = yawNow
	rootCF = rootCF * CFrame.new(0, hopY + trickY, 0) * CFrame.Angles(rad(hopPitch), rad(trickSpin), rad(trickRoll + self.bank))

	local bodyPivot = self.pivots.Body
	local yaw = 0
	if kind == "slither" then
		yaw = moving and sin(t * 6) * 12 or 0
	end
	local_.Body = CFrame.new(0, bob, 0) * around(bodyPivot, CFrame.Angles(rad(lean), rad(yaw), rad(roll)))

	-- Tete : regarde autour en idle, hoche la tete en marchant
	local headYaw, headPitch, headRoll
	if moving then
		headYaw = sin(t * 1.5) * 6
		headPitch = sin(t * stride * 2) * (state == "run" and 6 or 4)
		headRoll = 0
	else
		headYaw = sin(t * 0.6) * 22 + sin(t * 1.7) * 6
		headPitch = sin(t * 0.9) * 6
		headRoll = sin(t * 0.75) * 8
	end
	if kind == "slither" then
		headYaw = headYaw * 0.6 - yaw * 1.2
	end
	if state == "jump" then
		headPitch = -10
	end
	local_.Head = around(self.pivots.Head, CFrame.Angles(rad(headPitch), rad(headYaw), rad(headRoll)))

	-- Oreilles : petits frissons de temps en temps
	local twitch = math.max(0, sin(t * 0.9) - 0.92) * 220
	local_.EarL = around(self.pivots.EarL, CFrame.Angles(0, 0, rad(-twitch - (moving and sin(t * stride) * 6 or 0))))
	local_.EarR = around(self.pivots.EarR, CFrame.Angles(0, 0, rad(twitch + (moving and sin(t * stride) * 6 or 0))))

	-- Queue : remue
	local wagSpeed = moving and 12 or 5
	local wagAmp = (kind == "crawl") and 6 or (moving and 26 or 16)
	if kind == "crawl" then
		local_.Tail = around(self.pivots.Tail, CFrame.Angles(rad(sin(t * 3) * 8), rad(sin(t * 2) * wagAmp), 0))
	elseif kind == "float" then
		local_.Tail = around(self.pivots.Tail, CFrame.Angles(rad(sin(t * 2) * 10), rad(sin(t * 1.6) * 20), 0))
	else
		local_.Tail = around(self.pivots.Tail, CFrame.Angles(rad(state == "jump" and -20 or 0), rad(sin(t * wagSpeed) * wagAmp), 0))
	end

	-- Ailes : battent (plus vite en mouvement)
	local flapRate = (kind == "fly") and (moving and 16 or 9) or 5
	local flapAmp = (kind == "fly") and (moving and 40 or 28) or 10
	if state == "jump" then
		flapRate, flapAmp = 18, 45
	end
	local flap = sin(t * flapRate) * flapAmp
	local_.WingL = around(self.pivots.WingL, CFrame.Angles(0, 0, rad(-flap)))
	local_.WingR = around(self.pivots.WingR, CFrame.Angles(0, 0, rad(flap)))

	-- Pattes
	local swing = sin(t * stride) * legAmp
	if kind == "crawl" then
		swing = sin(t * (moving and 22 or 3)) * (moving and 22 or 4)
	end
	local tuck = state == "jump" and 35 or 0
	if kind == "fly" or kind == "float" then
		swing = sin(t * 2) * 8
		tuck = 15
	end
	local_.LegFL = around(self.pivots.LegFL, CFrame.Angles(rad(swing - tuck), 0, 0))
	local_.LegBR = around(self.pivots.LegBR, CFrame.Angles(rad(swing + tuck), 0, 0))
	local_.LegFR = around(self.pivots.LegFR, CFrame.Angles(rad(-swing - tuck), 0, 0))
	local_.LegBL = around(self.pivots.LegBL, CFrame.Angles(rad(-swing + tuck), 0, 0))
	local_.Fx = CFrame.new()

	-- Compose la hierarchie
	local world = {}
	for _, g in ipairs(ORDER) do
		local parent = self.parents[g]
		local l = local_[g] or CFrame.new()
		if parent and world[parent] then
			world[g] = world[parent] * l
		else
			world[g] = l
		end
	end

	if now >= self.nextBlink then
		self.blinkUntil = now + 0.13
		self.nextBlink = now + 2.2 + math.random() * 3.5
	end
	local blinking = now < self.blinkUntil and self.eyeIndex ~= nil
	local blinkOffset = CFrame.new(0, 0, 0.32 * s)
	local cframes = self.cframes
	for i, part in ipairs(self.parts) do
		local cf = rootCF * (world[self.groups[i]] or world.Body) * self.offsets[i]
		if blinking and self.eyeIndex[i] then
			cf = cf * blinkOffset -- l'oeil rentre dans la tete un instant
		end
		cframes[i] = cf
	end
	workspace:BulkMoveTo(self.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)

	if #self.rainbow > 0 then
		local color = Color3.fromHSV((now * 0.25 + self.phase) % 1, 0.55, 1)
		for _, part in ipairs(self.rainbow) do
			part.Color = color
		end
	end
end

function PetAnimator:destroy()
	self.model:Destroy()
end

return PetAnimator
