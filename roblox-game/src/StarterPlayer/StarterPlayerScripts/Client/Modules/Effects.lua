-- Effets : plantation, arrosage, recolte, maturation, eclairs, meteo, sons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Economy = require(ReplicatedStorage.Shared.Economy)
local State = require(script.Parent.State)

local Effects = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

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
		s.RollOffMaxDistance = 120
		s.Parent = holder
		Debris:AddItem(holder, 4)
	else
		s.Parent = workspace
		Debris:AddItem(s, 4)
	end
	s:Play()
end

local function burst(position, color, count, speed, size, gravity)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(1, 1, 1)
	holder.Position = position
	holder.Parent = workspace
	local att = Instance.new("Attachment")
	att.Parent = holder
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.5, 1)
	e.Speed = NumberRange.new(speed * 0.6, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0, 1)
	e.LightEmission = 0.6
	e.Acceleration = Vector3.new(0, gravity or -20, 0)
	e.Drag = 2
	e.Color = ColorSequence.new(color)
	e.Parent = att
	e:Emit(count)
	Debris:AddItem(holder, 2)
end

local function floatingText(position, text, color, size)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(1, 1, 1)
	holder.Position = position + Vector3.new(0, 3, 0)
	holder.Parent = workspace
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(size or 200, 40)
	gui.AlwaysOnTop = true
	gui.Parent = holder
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Text = text
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.2
	l.Parent = gui
	TweenService:Create(holder, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = holder.Position + Vector3.new(0, 5, 0) }):Play()
	task.delay(0.9, function()
		TweenService:Create(l, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	Debris:AddItem(holder, 1.6)
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

local shakeAmount = 0
RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	if shakeAmount > 0.01 then
		hum.CameraOffset = Vector3.new((math.random() - 0.5) * shakeAmount, (math.random() - 0.5) * shakeAmount, 0)
		shakeAmount = shakeAmount * math.max(0, 1 - dt * 6)
	elseif hum.CameraOffset ~= Vector3.zero then
		hum.CameraOffset = Vector3.zero
	end
end)

-- Meteo ---------------------------------------------------------------------

local rainPart = Instance.new("Part")
rainPart.Name = "RainEmitter"
rainPart.Anchored = true
rainPart.CanCollide = false
rainPart.CanQuery = false
rainPart.Transparency = 1
rainPart.Size = Vector3.new(120, 1, 120)
rainPart.Parent = workspace
local rainAtt = Instance.new("Attachment")
rainAtt.Parent = rainPart
local rain = Instance.new("ParticleEmitter")
rain.Enabled = false
rain.Rate = 500
rain.Lifetime = NumberRange.new(1.2, 1.5)
rain.Speed = NumberRange.new(60, 70)
rain.EmissionDirection = Enum.NormalId.Bottom
rain.Size = NumberSequence.new(0.15)
rain.Transparency = NumberSequence.new(0.4)
rain.Color = ColorSequence.new(Color3.fromRGB(180, 210, 255))
rain.Shape = Enum.ParticleEmitterShape.Box
rain.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
rain.Parent = rainPart
local snow = rain:Clone()
snow.Rate = 150
snow.Speed = NumberRange.new(8, 12)
snow.Lifetime = NumberRange.new(5, 7)
snow.Size = NumberSequence.new(0.35)
snow.Color = ColorSequence.new(Color3.new(1, 1, 1))
snow.Parent = rainPart

RunService.Heartbeat:Connect(function()
	rainPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 45, 0))
end)

local function applyWeather(weather)
	local cc = Lighting:FindFirstChild("FarmColor")
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	rain.Enabled = weather.id == "Pluie" or weather.id == "Orage"
	snow.Enabled = weather.id == "Gel"
	local goals = {
		Clair = { tint = Color3.new(1, 1, 1), sat = 0.25, bright = 2.5, density = 0.25 },
		Pluie = { tint = Color3.fromRGB(190, 205, 230), sat = -0.1, bright = 1.4, density = 0.45 },
		Orage = { tint = Color3.fromRGB(150, 160, 190), sat = -0.3, bright = 0.9, density = 0.55 },
		Gel = { tint = Color3.fromRGB(200, 230, 255), sat = -0.2, bright = 2, density = 0.4 },
	}
	local g = goals[weather.id] or goals.Clair
	if cc then
		TweenService:Create(cc, TweenInfo.new(2), { TintColor = g.tint, Saturation = g.sat }):Play()
	end
	TweenService:Create(Lighting, TweenInfo.new(2), { Brightness = g.bright }):Play()
	if atmosphere then
		TweenService:Create(atmosphere, TweenInfo.new(2), { Density = g.density }):Play()
	end
end

-- Evenements ------------------------------------------------------------------

local handlers = {}

handlers.Plant = function(data)
	burst(data.position + Vector3.new(0, 0.5, 0), Config.Colors.Soil, 18, 10, 0.5)
	playSound("rbxasset://sounds/impact_water.mp3", 0.5, 1.4, data.position)
end

handlers.Water = function(data)
	burst(data.position + Vector3.new(0, 2, 0), Color3.fromRGB(120, 190, 255), 30, 8, 0.4)
	playSound("rbxasset://sounds/impact_water.mp3", 0.7, 1, data.position)
	if data.owner == player.UserId then
		floatingText(data.position, "+" .. math.floor(Config.Water.Boost * 100) .. " %", Color3.fromRGB(120, 190, 255), 120)
	end
end

handlers.Ripe = function(data)
	burst(data.position + Vector3.new(0, 2, 0), Config.Colors.Gold, 20, 6, 0.4, 2)
	if data.owner == player.UserId then
		playSound("rbxasset://sounds/electronicpingshort.wav", 0.6, 1.4, data.position)
		if data.mutations and #data.mutations > 0 then
			floatingText(data.position, Economy.mutationLabel(data.mutations) .. " !", Color3.fromRGB(255, 150, 255), 220)
			playSound("rbxasset://sounds/victory.wav", 0.5, 1.6)
		end
	end
end

handlers.Harvest = function(data)
	burst(data.position + Vector3.new(0, 1.5, 0), data.color or Config.Colors.Accent, 28, 14, 0.6)
	playSound("rbxasset://sounds/snap.wav", 0.8, 1.2, data.position)
	if data.owner == player.UserId then
		local rare = data.mutations and #data.mutations > 0
		floatingText(data.position, data.name .. "  " .. Economy.formatWeight(data.weight), rare and Color3.fromRGB(255, 150, 255) or Color3.new(1, 1, 1), 260)
		task.delay(0.25, function()
			floatingText(data.position + Vector3.new(0, 1.5, 0), "+" .. Economy.formatCoins(data.value) .. " pieces", Config.Colors.Gold, 200)
		end)
		if rare then
			shakeAmount = 1
			flashScreen(Color3.fromRGB(255, 150, 255), 0.8, 0.6)
			playSound("rbxasset://sounds/victory.wav", 0.6, 1.3)
		end
	end
end

handlers.Lightning = function(data)
	local pos = data.position
	local top = pos + Vector3.new(0, 120, 0)
	local segments = 7
	local last = top
	for i = 1, segments do
		local t = i / segments
		local target = top:Lerp(pos, t) + Vector3.new((math.random() - 0.5) * 8 * (1 - t), 0, (math.random() - 0.5) * 8 * (1 - t))
		if i == segments then
			target = pos
		end
		local len = (target - last).Magnitude
		local bolt = Instance.new("Part")
		bolt.Anchored = true
		bolt.CanCollide = false
		bolt.CanQuery = false
		bolt.Material = Enum.Material.Neon
		bolt.Color = Color3.fromRGB(255, 255, 180)
		bolt.Size = Vector3.new(0.5, 0.5, len)
		bolt.CFrame = CFrame.lookAt((last + target) / 2, target)
		bolt.Parent = workspace
		TweenService:Create(bolt, TweenInfo.new(0.35), { Transparency = 1 }):Play()
		Debris:AddItem(bolt, 0.4)
		last = target
	end
	local light = Instance.new("PointLight")
	light.Brightness = 10
	light.Range = 60
	light.Color = Color3.fromRGB(255, 255, 200)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.Transparency = 1
	holder.Position = pos + Vector3.new(0, 5, 0)
	holder.Parent = workspace
	light.Parent = holder
	Debris:AddItem(holder, 0.3)
	burst(pos + Vector3.new(0, 1, 0), Color3.fromRGB(255, 255, 120), 40, 20, 0.5)
	flashScreen(Color3.new(1, 1, 1), 0.6, 0.4)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local dist = hrp and (hrp.Position - pos).Magnitude or 999
	task.delay(math.clamp(dist / 150, 0.05, 1), function()
		playSound("rbxasset://sounds/bass.wav", math.clamp(1.2 - dist / 300, 0.2, 1), 0.5)
	end)
	shakeAmount = math.max(shakeAmount, math.clamp(2 - dist / 60, 0.3, 2))
end

handlers.Sell = function(data)
	playSound("rbxasset://sounds/electronicpingshort.wav", 0.8, 0.9)
	flashScreen(Config.Colors.Gold, 0.85, 0.5)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		burst(hrp.Position + Vector3.new(0, 2, 0), Config.Colors.Gold, 40, 16, 0.5, -5)
		floatingText(hrp.Position, "+" .. Economy.formatCoins(data.total or 0) .. " pieces", Config.Colors.Gold, 240)
	end
end

handlers.Buy = function()
	playSound("rbxasset://sounds/button.wav", 0.6, 1.2)
end

handlers.Expand = function()
	playSound("rbxasset://sounds/victory.wav", 0.7, 1.2)
	flashScreen(Config.Colors.Accent, 0.8, 0.6)
end

function Effects.Init()
	Remotes.FX.OnClientEvent:Connect(function(kind, data)
		local handler = handlers[kind]
		if handler then
			handler(data or {})
		end
	end)
	State.Changed.Event:Connect(function(what, data)
		if what == "weather" then
			applyWeather(data)
		elseif what == "tileAction" then
			playSound("rbxasset://sounds/clickfast.wav", 0.3, 1.5)
		end
	end)
end

return Effects
