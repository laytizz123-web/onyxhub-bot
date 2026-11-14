-- Effets visuels et sonores : renvois, eliminations, cible, pulse, dash, overdrive.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local State = require(script.Parent.State)

local Effects = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local sounds = {}
local function playSound(id, volume, pitch, position)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.5
	s.PlaybackSpeed = pitch or 1
	if position then
		local holder = Instance.new("Part")
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.Transparency = 1
		holder.Size = Vector3.new(1, 1, 1)
		holder.Position = position
		holder.Parent = workspace
		s.RollOffMaxDistance = 250
		s.Parent = holder
		Debris:AddItem(holder, 4)
	else
		s.Parent = workspace
		Debris:AddItem(s, 4)
	end
	s:Play()
	table.insert(sounds, s)
end

local function getCharacter(userId)
	local p = Players:GetPlayerByUserId(userId)
	return p and p.Character
end

-- Tremblement de camera
local shakeAmount = 0
RunService.RenderStepped:Connect(function(dt)
	if shakeAmount > 0.01 then
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.CameraOffset = Vector3.new(
				(math.random() - 0.5) * shakeAmount,
				(math.random() - 0.5) * shakeAmount,
				(math.random() - 0.5) * shakeAmount
			)
		end
		shakeAmount = shakeAmount * math.max(0, 1 - dt * 8)
	elseif shakeAmount ~= 0 then
		shakeAmount = 0
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.CameraOffset = Vector3.zero
		end
	end
end)

function Effects.shake(amount)
	shakeAmount = math.max(shakeAmount, amount)
end

local function shockwave(position, color, size, duration, flat)
	local ring = Instance.new("Part")
	ring.Shape = flat and Enum.PartType.Cylinder or Enum.PartType.Ball
	ring.Size = Vector3.new(1, 1, 1)
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.2
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CFrame = flat and (CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))) or CFrame.new(position)
	ring.Parent = workspace
	local goalSize = flat and Vector3.new(0.4, size, size) or Vector3.new(size, size, size)
	TweenService:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = goalSize,
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, duration + 0.1)
end

local function burstParticles(parent, color, count)
	local att = Instance.new("Attachment")
	att.Parent = parent
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(15, 35)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new(0, 1)
	emitter.LightEmission = 1
	emitter.Drag = 4
	emitter.Color = ColorSequence.new(color)
	emitter.Parent = att
	emitter:Emit(count)
	Debris:AddItem(att, 2)
end

local function flashScreen(color, transparency, duration)
	local gui = player.PlayerGui:FindFirstChild("OnyxFlash")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "OnyxFlash"
		gui.IgnoreGuiInset = true
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 50
		gui.Parent = player.PlayerGui
		local frame = Instance.new("Frame")
		frame.Name = "Flash"
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Parent = gui
	end
	local frame = gui.Flash
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency
	TweenService:Create(frame, TweenInfo.new(duration), { BackgroundTransparency = 1 }):Play()
end

-- Surbrillance de la cible
local highlight = Instance.new("Highlight")
highlight.Name = "TargetHighlight"
highlight.FillColor = Config.Colors.Danger
highlight.OutlineColor = Color3.new(1, 1, 1)
highlight.FillTransparency = 0.6
highlight.OutlineTransparency = 0
highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
highlight.Enabled = false

local billboard = Instance.new("BillboardGui")
billboard.Name = "TargetTag"
billboard.Size = UDim2.fromOffset(120, 40)
billboard.StudsOffset = Vector3.new(0, 3.5, 0)
billboard.AlwaysOnTop = true
billboard.Enabled = false
local tag = Instance.new("TextLabel")
tag.Size = UDim2.fromScale(1, 1)
tag.BackgroundTransparency = 1
tag.Text = "CIBLE"
tag.Font = Enum.Font.GothamBlack
tag.TextScaled = true
tag.TextColor3 = Config.Colors.Danger
tag.TextStrokeTransparency = 0.3
tag.Parent = billboard

local function setTarget(userId)
	State.targetUserId = userId
	local char = userId ~= 0 and getCharacter(userId) or nil
	if char then
		highlight.Parent = char
		highlight.Enabled = true
		local head = char:FindFirstChild("Head")
		billboard.Adornee = head
		billboard.Parent = head
		billboard.Enabled = userId ~= player.UserId
		if userId == player.UserId then
			playSound("rbxasset://sounds/electronicpingshort.wav", 0.8, 1.1)
		end
	else
		highlight.Enabled = false
		highlight.Parent = nil
		billboard.Enabled = false
		billboard.Parent = nil
	end
end

local handlers = {}

handlers.Target = function(data)
	setTarget(data.userId or 0)
end

handlers.Deflect = function(data)
	local color = data.deflects and (data.deflects > 12 and Config.Colors.Danger or (data.deflects > 6 and Config.Colors.Gold or Config.Colors.Accent)) or Config.Colors.Accent
	shockwave(data.position, color, 26, 0.45, false)
	shockwave(data.position, Color3.new(1, 1, 1), 34, 0.35, true)
	local pitch = 0.9 + math.min((data.speed or 40) / 240, 1) * 0.6
	playSound("rbxasset://sounds/swoosh.wav", 1, pitch, data.position)
	playSound("rbxasset://sounds/snap.wav", 0.6, pitch, data.position)
	local char = getCharacter(data.userId)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		burstParticles(hrp, color, 25)
	end
	if data.userId == player.UserId then
		Effects.shake(1.2)
		flashScreen(Config.Colors.Accent, 0.85, 0.3)
	else
		local myChar = player.Character
		local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
		if myHrp and (myHrp.Position - data.position).Magnitude < 40 then
			Effects.shake(0.4)
		end
	end
end

handlers.Swing = function(data)
	if data.userId == player.UserId then
		return -- deja affiche localement
	end
	local char = getCharacter(data.userId)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		shockwave(hrp.Position, Color3.new(1, 1, 1), 10, 0.25, true)
		playSound("rbxasset://sounds/swoosh.wav", 0.4, 1.3, hrp.Position)
	end
end

handlers.Hit = function(data)
	local explosion = Instance.new("Explosion")
	explosion.Position = data.position
	explosion.BlastPressure = 0
	explosion.BlastRadius = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Parent = workspace
	shockwave(data.position, Config.Colors.Danger, 40, 0.6, false)
	playSound("rbxasset://sounds/collide.wav", 1, 0.8, data.position)
	playSound("rbxasset://sounds/splat.wav", 0.7, 0.9, data.position)
	if data.userId == player.UserId then
		Effects.shake(3)
		flashScreen(Config.Colors.Danger, 0.5, 0.8)
	else
		Effects.shake(0.8)
	end
end

handlers.Pulse = function(data)
	local color = Config.Colors.Accent2
	shockwave(data.position, color, Config.Abilities.Pulse.Radius * 2, 0.8, false)
	shockwave(data.position, color, Config.Abilities.Pulse.Radius * 2.2, 1, true)
	playSound("rbxasset://sounds/bass.wav", 1, 0.8, data.position)
	if data.userId == player.UserId then
		Effects.shake(1)
		flashScreen(color, 0.8, 0.5)
	end
end

handlers.Dash = function(data)
	local char = getCharacter(data.userId)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		burstParticles(hrp, Config.Colors.Gold, 15)
	end
end

handlers.Overdrive = function(data)
	State.overdrive = data.enabled
	local cc = Lighting:FindFirstChild("ArenaColor")
	if cc then
		TweenService:Create(cc, TweenInfo.new(1), {
			TintColor = data.enabled and Color3.fromRGB(255, 200, 230) or Color3.new(1, 1, 1),
			Saturation = data.enabled and 0.5 or 0.15,
		}):Play()
	end
	if data.enabled then
		playSound("rbxasset://sounds/HalloweenGhost.wav", 1, 0.6)
		flashScreen(Config.Colors.Accent2, 0.6, 1)
		Effects.shake(2)
	end
end

function Effects.Init()
	Remotes.BallEvent.OnClientEvent:Connect(function(kind, data)
		local handler = handlers[kind]
		if handler then
			handler(data or {})
		end
	end)

	State.Changed.Event:Connect(function(what, data)
		if what == "round" and data.phase == "Ending" then
			setTarget(0)
			if data.winnerUserId == player.UserId then
				playSound("rbxasset://sounds/victory.wav", 1, 1)
				flashScreen(Config.Colors.Gold, 0.7, 1.2)
			end
		elseif what == "doublejump" then
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				shockwave(hrp.Position - Vector3.new(0, 2.5, 0), Config.Colors.Accent, 8, 0.3, true)
			end
		elseif what == "dash" then
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				burstParticles(hrp, Config.Colors.Gold, 20)
			end
		end
	end)

	-- Si la cible a deja ete choisie avant le chargement du client
	local ball = State.getBall()
	if ball then
		setTarget(ball:GetAttribute("TargetUserId") or 0)
	end
end

return Effects
