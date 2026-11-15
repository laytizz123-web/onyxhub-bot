-- Effets : coins qui tournent, collecte, coffres, eclosion, evolution, courses, teleportation, sons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local State = require(script.Parent.State)
local Icons = require(ReplicatedStorage.Shared.Icons)

local Effects = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local HUD

local SOUNDS = {
	coin = "rbxasset://sounds/electronicpingshort.wav",
	chest = "rbxasset://sounds/victory.wav",
	hatch = "rbxasset://sounds/snap.wav",
	rare = "rbxasset://sounds/victory.wav",
	evolve = "rbxasset://sounds/HalloweenGhost.wav",
	race = "rbxasset://sounds/swoosh.wav",
	win = "rbxasset://sounds/victory.wav",
	teleport = "rbxasset://sounds/flashbulb.wav",
	unlock = "rbxasset://sounds/bass.wav",
	click = "rbxasset://sounds/button.wav",
}

local function playSound(name, volume, pitch, position)
	local s = Instance.new("Sound")
	s.SoundId = SOUNDS[name] or SOUNDS.click
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
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0, 1)
	e.LightEmission = 1
	e.Acceleration = Vector3.new(0, gravity or -15, 0)
	e.Drag = 3
	e.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	e.Parent = att
	e:Emit(count)
	Debris:AddItem(holder, 2)
end

local function shockwave(position, color, size, duration)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.4, 1, 1)
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.2
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.new(0.4, size, size), Transparency = 1 }):Play()
	Debris:AddItem(ring, duration + 0.1)
end

local function floatingText(position, text, color, size, iconName)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(1, 1, 1)
	holder.Position = position + Vector3.new(0, 2, 0)
	holder.Parent = workspace
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(size or 140, 46)
	gui.AlwaysOnTop = true
	gui.Parent = holder
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, iconName and -46 or 0, 1, 0)
	l.Position = UDim2.fromOffset(iconName and 46 or 0, 0)
	l.BackgroundTransparency = 1
	l.Text = text
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = color
	l.TextXAlignment = iconName and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center
	l.Parent = gui
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(22, 24, 52)
	st.Thickness = 3
	st.Parent = l
	local icon
	if iconName then
		icon = Icons.Image(iconName, gui, { Size = UDim2.fromOffset(46, 46) })
	end
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = l
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(holder, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = holder.Position + Vector3.new(0, 4, 0) }):Play()
	task.delay(0.65, function()
		TweenService:Create(l, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
		TweenService:Create(st, TweenInfo.new(0.35), { Transparency = 1 }):Play()
		if icon then
			TweenService:Create(icon, TweenInfo.new(0.35), { ImageTransparency = 1 }):Play()
		end
	end)
	Debris:AddItem(holder, 1.1)
end

local function flashScreen(color, transparency, duration)
	local gui = player.PlayerGui:FindFirstChild("PetFlash")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "PetFlash"
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

-- Rotation des coins et coffres (rendu local)
RunService.Heartbeat:Connect(function()
	local folder = workspace:FindFirstChild("Coins")
	if not folder then
		return
	end
	local t = os.clock()
	for _, coin in ipairs(folder:GetChildren()) do
		if coin:IsA("BasePart") then
			local base = coin:GetAttribute("BaseY")
			if not base then
				base = coin.Position.Y
				coin:SetAttribute("BaseY", base)
			end
			local p = coin.Position
			if coin.Name == "Coin" then
				coin.CFrame = CFrame.new(p.X, base + math.sin(t * 3 + p.X) * 0.4, p.Z) * CFrame.Angles(0, t * 2.5, math.rad(90))
			else
				coin.CFrame = CFrame.new(p.X, base + math.sin(t * 2) * 0.6, p.Z) * CFrame.Angles(0, t * 1.2, 0)
			end
		end
	end
end)

local handlers = {}

handlers.Collect = function(data)
	local mine = data.userId == player.UserId
	if data.chest then
		burst(data.position, Config.Colors.Accent2, 60, 25, 0.9, -10)
		shockwave(data.position, Config.Colors.Accent2, 30, 0.8)
		playSound("chest", mine and 1 or 0.5, 1.1, data.position)
	else
		burst(data.position, Config.Colors.Gold, 10, 8, 0.4, -10)
		if mine then
			playSound("coin", 0.4, 1.2 + math.random() * 0.4, data.position)
		end
	end
	if mine then
		floatingText(data.position, "+" .. data.amount, Config.Colors.Gold, data.chest and 220 or 140, "coin")
		if data.chest then
			flashScreen(Config.Colors.Gold, 0.75, 0.6)
		end
	end
end

handlers.ChestSpawn = function(data)
	shockwave(data.position, Config.Colors.Accent2, 40, 1.2)
	playSound("unlock", 0.6, 1.2)
end

handlers.Hatch = function(data)
	local rarity = Config.RarityById[data.rarity]
	HUD.playHatch(data)
	playSound("hatch", 0.7, 0.9)
	task.delay(0.95, function()
		playSound(rarity.index >= 4 and "rare" or "coin", 0.8, rarity.index >= 4 and 1 or 1.5)
		flashScreen(rarity.color, 0.6, 0.8)
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			burst(hrp.Position, rarity.color, 40 + rarity.index * 10, 15, 0.7, 2)
			shockwave(hrp.Position - Vector3.new(0, 2, 0), rarity.color, 10 + rarity.index * 4, 0.8)
		end
	end)
end

handlers.Evolve = function(data)
	local evo = Config.Evolutions[data.evo]
	playSound("evolve", 0.8, 1.3)
	flashScreen(evo.color or Config.Colors.Gold, 0.5, 1.2)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		burst(hrp.Position, evo.color or Config.Colors.Gold, 80, 20, 0.9, 4)
		shockwave(hrp.Position - Vector3.new(0, 2, 0), evo.color or Config.Colors.Gold, 30, 1)
		floatingText(hrp.Position + Vector3.new(0, 3, 0), string.upper(evo.name) .. " !", evo.color or Config.Colors.Gold, 260, "sparkle")
	end
	HUD.playHatch({ petId = data.petId, rarity = Config.PetById[data.petId].rarity, egg = "Village" })
end

handlers.ZoneUnlock = function(data)
	local zone = Config.ZoneById[data.zoneId]
	playSound("unlock", 1, 1)
	flashScreen(Config.Colors.Gold, 0.5, 1)
	HUD.toast(zone.name .. " debloque ! Ouvre MONDES pour t'y rendre.", "gold")
end

handlers.Teleport = function(data)
	playSound("teleport", 0.6, 1)
	flashScreen(Config.Colors.Accent, 0.4, 0.8)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		shockwave(hrp.Position - Vector3.new(0, 2, 0), Config.Colors.Accent, 20, 0.8)
	end
end

handlers.Daily = function(data)
	playSound("win", 0.8, 1.2)
	flashScreen(Config.Colors.Gold, 0.6, 1)
	HUD.toast("Cadeau du jour : +" .. data.coins .. " coins et un oeuf gratuit !", "gold")
end

handlers.Code = function(data)
	playSound("win", 0.8, 1.3)
	flashScreen(Config.Colors.Gold, 0.65, 0.8)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		floatingText(hrp.Position + Vector3.new(0, 3, 0), "+" .. data.coins, Config.Colors.Gold, 220, "coin")
		burst(hrp.Position, Config.Colors.Gold, 50, 16, 0.6, -5)
	end
end

handlers.RaceStart = function()
	playSound("race", 1, 0.8)
	flashScreen(Color3.new(1, 1, 1), 0.7, 0.5)
end

handlers.RaceEnd = function(data)
	if data.position then
		burst(data.position, Config.Colors.Gold, 60, 20, 0.8, 2)
		shockwave(data.position, Config.Colors.Gold, 30, 1)
	end
	if data.winnerUserId == player.UserId then
		playSound("win", 1, 1)
		flashScreen(Config.Colors.Gold, 0.5, 1.5)
	else
		playSound("win", 0.4, 1.3)
	end
end

function Effects.Init(hudModule)
	HUD = hudModule
	Remotes.FX.OnClientEvent:Connect(function(kind, data)
		local handler = handlers[kind]
		if handler then
			local ok, err = pcall(handler, data or {})
			if not ok then
				warn("[PetRush] Effet " .. kind .. " : " .. tostring(err))
			end
		end
	end)
	-- Compteur de coins anime
	local lastCoins = nil
	State.Changed.Event:Connect(function(what, data)
		if what == "sync" then
			if lastCoins and data.coins > lastCoins then
				playSound("click", 0.15, 1.6)
			end
			lastCoins = data.coins
		end
	end)
end

return Effects
