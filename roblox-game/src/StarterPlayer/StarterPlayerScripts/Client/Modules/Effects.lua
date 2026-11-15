-- Effets visuels et sonores, animations des autres joueurs, auras, barres de vie au-dessus des tetes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local State = require(script.Parent.State)
local Anim = require(script.Parent.Anim)

local Effects = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local HUD -- injecte

local SOUNDS = {
	swing = "rbxasset://sounds/swoosh.wav",
	hit = "rbxasset://sounds/snap.wav",
	heavy = "rbxasset://sounds/collide.wav",
	whoosh = "rbxasset://sounds/swoosh.wav",
	slam = "rbxasset://sounds/bass.wav",
	zap = "rbxasset://sounds/flashbulb.wav",
	fire = "rbxasset://sounds/Rocket shot.wav",
	explosion = "rbxasset://sounds/collide.wav",
	thunder = "rbxasset://sounds/bass.wav",
	charge = "rbxasset://sounds/electronicpingshort.wav",
	block = "rbxasset://sounds/button.wav",
	dash = "rbxasset://sounds/swoosh.wav",
	ult = "rbxasset://sounds/HalloweenGhost.wav",
	death = "rbxasset://sounds/uuhhh.mp3",
	win = "rbxasset://sounds/victory.wav",
	level = "rbxasset://sounds/victory.wav",
}

local function playSound(name, volume, pitch, position)
	local s = Instance.new("Sound")
	s.SoundId = SOUNDS[name] or SOUNDS.hit
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
		s.RollOffMaxDistance = 160
		s.Parent = holder
		Debris:AddItem(holder, 4)
	else
		s.Parent = workspace
		Debris:AddItem(s, 4)
	end
	s:Play()
end

local function getCharacter(userId)
	local p = Players:GetPlayerByUserId(userId)
	return p and p.Character
end

local function hrpOf(character)
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function burst(position, color, count, speed, size, gravity, lifetime)
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
	e.Lifetime = NumberRange.new((lifetime or 0.6) * 0.6, lifetime or 0.6)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0, 1)
	e.LightEmission = 1
	e.Acceleration = Vector3.new(0, gravity or -10, 0)
	e.Drag = 3
	e.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	e.Parent = att
	e:Emit(count)
	Debris:AddItem(holder, 2)
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
	TweenService:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = flat and Vector3.new(0.5, size, size) or Vector3.new(size, size, size),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, duration + 0.1)
end

local function floatingText(position, text, color, size)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(1, 1, 1)
	holder.Position = position + Vector3.new(math.random(-2, 2), 2.5, math.random(-2, 2))
	holder.Parent = workspace
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(size or 120, 40)
	gui.AlwaysOnTop = true
	gui.Parent = holder
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Text = text
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.2
	l.Parent = gui
	TweenService:Create(holder, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = holder.Position + Vector3.new(0, 4, 0) }):Play()
	task.delay(0.5, function()
		TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	Debris:AddItem(holder, 1)
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

-- Tremblement + FOV
local shakeAmount = 0
local fovOffset = 0
RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		if shakeAmount > 0.01 then
			hum.CameraOffset = Vector3.new((math.random() - 0.5) * shakeAmount, (math.random() - 0.5) * shakeAmount, 0)
			shakeAmount = shakeAmount * math.max(0, 1 - dt * 9)
		elseif hum.CameraOffset ~= Vector3.zero then
			hum.CameraOffset = Vector3.zero
		end
	end
	if math.abs(fovOffset) > 0.05 then
		fovOffset = fovOffset * math.max(0, 1 - dt * 5)
		camera.FieldOfView = 70 + fovOffset
	elseif camera.FieldOfView ~= 70 then
		camera.FieldOfView = 70
	end
end)

local function shake(amount)
	shakeAmount = math.max(shakeAmount, amount)
end

-- Auras persistantes et trainees ------------------------------------------------------

local auraEmitters = {} -- [character] = { emitter = , id = }

local function colorFor(list, id)
	for _, item in ipairs(list) do
		if item.id == id then
			return item.color
		end
	end
	return nil
end

local function setAura(character, color, ult)
	local existing = auraEmitters[character]
	if existing then
		existing:Destroy()
		auraEmitters[character] = nil
	end
	if not color then
		return
	end
	local hrp = hrpOf(character)
	if not hrp then
		return
	end
	local att = Instance.new("Attachment")
	att.Name = "AuraAttachment"
	att.Position = Vector3.new(0, -1, 0)
	att.Parent = hrp
	local e = Instance.new("ParticleEmitter")
	e.Rate = ult and 60 or 18
	e.Lifetime = NumberRange.new(0.6, 1.1)
	e.Speed = NumberRange.new(ult and 6 or 3, ult and 9 or 5)
	e.SpreadAngle = Vector2.new(25, 25)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, ult and 1.2 or 0.6), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0.3, 1)
	e.LightEmission = 1
	e.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	e.Acceleration = Vector3.new(0, 4, 0)
	e.Parent = att
	if ult then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 20
		light.Brightness = 2
		light.Parent = att
	end
	auraEmitters[character] = att
end

local function refreshAura(character)
	local p = Players:GetPlayerFromCharacter(character)
	if not p then
		return
	end
	if character:GetAttribute("UltActive") then
		local def = Config.CharacterById[character:GetAttribute("CharacterId") or ""] or Config.Characters[1]
		setAura(character, def.color, true)
	else
		setAura(character, colorFor(Config.Auras, p:GetAttribute("Aura") or "none"), false)
	end
end

-- Etiquettes au-dessus de la tete (nom, titre, vie) ----------------------------------

local function attachOverhead(character)
	local p = Players:GetPlayerFromCharacter(character)
	local head = character:WaitForChild("Head", 5)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not head or not humanoid then
		return
	end
	if character == player.Character then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Overhead"
	gui.Size = UDim2.fromOffset(160, 54)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 120
	gui.Parent = head
	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, 0, 0, 22)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBlack
	name.TextScaled = true
	name.TextStrokeTransparency = 0.4
	name.TextColor3 = Color3.new(1, 1, 1)
	name.Parent = gui
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 14)
	title.Position = UDim2.new(0, 0, 0, 22)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextStrokeTransparency = 0.4
	title.TextColor3 = Config.Colors.Gold
	title.Parent = gui
	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(0.8, 0, 0, 8)
	bg.Position = UDim2.new(0.1, 0, 0, 42)
	bg.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Config.Colors.Health
	fill.BorderSizePixel = 0
	fill.Parent = bg
	local function refresh()
		local def = Config.CharacterById[character:GetAttribute("CharacterId") or ""]
		if p then
			name.Text = p.DisplayName .. "  [" .. (p:GetAttribute("Level") or 1) .. "]"
			name.TextColor3 = def and def.color or Color3.new(1, 1, 1)
			title.Text = p:GetAttribute("Title") or ""
		else
			name.Text = character.Name
			title.Text = "Entrainement"
		end
		local ratio = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
		fill.Size = UDim2.fromScale(ratio, 1)
		fill.BackgroundColor3 = Config.Colors.Health:Lerp(Config.Colors.Danger, 1 - ratio)
	end
	refresh()
	humanoid.HealthChanged:Connect(refresh)
	if p then
		p:GetAttributeChangedSignal("Title"):Connect(refresh)
		p:GetAttributeChangedSignal("Level"):Connect(refresh)
		character:GetAttributeChangedSignal("CharacterId"):Connect(refresh)
	end
end

local function hookCharacter(character)
	task.spawn(attachOverhead, character)
	local p = Players:GetPlayerFromCharacter(character)
	if p then
		task.delay(0.5, function()
			refreshAura(character)
		end)
		character:GetAttributeChangedSignal("UltActive"):Connect(function()
			refreshAura(character)
		end)
		p:GetAttributeChangedSignal("Aura"):Connect(function()
			refreshAura(character)
		end)
	end
end

local function hookPlayer(p)
	if p.Character then
		hookCharacter(p.Character)
	end
	p.CharacterAdded:Connect(function(character)
		task.wait(0.2)
		hookCharacter(character)
	end)
end

-- Evenements de combat ----------------------------------------------------------------

local handlers = {}

handlers.Swing = function(data)
	local character = getCharacter(data.userId)
	Anim.play(character, "m1", data.combo)
	local hrp = hrpOf(character)
	if hrp then
		playSound("swing", 0.5, 0.9 + data.combo * 0.1, hrp.Position)
		if data.combo == 4 then
			burst((hrp.CFrame * CFrame.new(0, 0, -3)).Position, data.color or Config.Colors.Accent, 12, 14, 0.5)
		end
	end
	if data.userId == player.UserId then
		HUD.showCombo(data.combo)
		fovOffset = 2
	end
end

handlers.Hit = function(data)
	local color = data.color or Config.Colors.Accent
	if data.blocked then
		burst(data.position, Config.Colors.Gold, 10, 8, 0.4)
		shockwave(data.position, Config.Colors.Gold, 5, 0.25, false)
		playSound("block", 0.7, 1.2, data.position)
		floatingText(data.position, "BLOQUE " .. data.damage, Config.Colors.Gold, 120)
	else
		burst(data.position, color, data.heavy and 30 or 14, data.heavy and 22 or 12, data.heavy and 0.8 or 0.45)
		shockwave(data.position, Color3.new(1, 1, 1), data.heavy and 12 or 5, 0.25, false)
		playSound(data.heavy and "heavy" or "hit", data.heavy and 1 or 0.7, data.heavy and 0.9 or (0.9 + math.random() * 0.3), data.position)
		floatingText(data.position, tostring(data.damage), data.heavy and Config.Colors.Accent2 or Color3.new(1, 1, 1), data.heavy and 150 or 100)
		-- Animation de recul de la victime
		local victim = workspace:FindFirstChild(data.victimName, true)
		if victim and victim:IsA("Model") then
			Anim.play(victim, "hit")
		end
	end
	if data.attacker == player.UserId then
		shake(data.heavy and 1.5 or 0.5)
		fovOffset = data.heavy and 6 or 2
	elseif player.Character and data.victimName == player.Character.Name then
		shake(data.heavy and 2.5 or 1)
		flashScreen(Config.Colors.Danger, data.heavy and 0.6 or 0.85, 0.35)
	end
end

handlers.Block = function(data)
	local character = getCharacter(data.userId)
	Anim.block(character, data.enabled)
	local hrp = hrpOf(character)
	if not hrp then
		return
	end
	local existing = hrp:FindFirstChild("BlockShield")
	if existing then
		existing:Destroy()
	end
	if data.enabled then
		local shield = Instance.new("Part")
		shield.Name = "BlockShield"
		shield.Shape = Enum.PartType.Ball
		shield.Size = Vector3.new(7, 7, 7)
		shield.Material = Enum.Material.ForceField
		shield.Color = Config.Colors.Gold
		shield.Transparency = 0.4
		shield.CanCollide = false
		shield.CanQuery = false
		shield.Massless = true
		shield.CFrame = hrp.CFrame
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hrp
		weld.Part1 = shield
		weld.Parent = shield
		shield.Parent = hrp
		playSound("block", 0.4, 0.8, hrp.Position)
	end
end

handlers.Dash = function(data)
	local p = Players:GetPlayerByUserId(data.userId)
	local character = p and p.Character
	local hrp = hrpOf(character)
	if not hrp then
		return
	end
	if data.userId ~= player.UserId then
		Anim.play(character, "dash")
	end
	local color = colorFor(Config.Trails, p:GetAttribute("Trail") or "none")
	playSound("dash", 0.5, 1.4, hrp.Position)
	if color then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 1.5, 0)
		a0.Parent = hrp
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -1.5, 0)
		a1.Parent = hrp
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.35
		trail.LightEmission = 1
		trail.WidthScale = NumberSequence.new(1, 0)
		trail.Transparency = NumberSequence.new(0.2, 1)
		trail.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
		trail.Parent = hrp
		Debris:AddItem(a0, 0.7)
		Debris:AddItem(a1, 0.7)
		Debris:AddItem(trail, 0.7)
		burst(hrp.Position, color, 10, 8, 0.4, 0)
	else
		burst(hrp.Position - Vector3.new(0, 2, 0), Color3.fromRGB(220, 220, 230), 8, 6, 0.4, 0)
	end
	if data.userId == player.UserId then
		fovOffset = 8
	end
end

handlers.Cast = function(data)
	local character = getCharacter(data.userId)
	Anim.play(character, data.pose or "cast")
	local hrp = hrpOf(character)
	if not hrp then
		return
	end
	local color = data.ult and Config.Colors.Ult or (data.color or Config.Colors.Accent)
	burst(hrp.Position, color, data.ult and 40 or 18, 6, 0.5, 6, data.windup + 0.3)
	playSound("charge", 0.5, data.ult and 0.7 or 1.1, hrp.Position)
	floatingText(hrp.Position + Vector3.new(0, 2, 0), data.name, color, 200)
	if data.userId == player.UserId then
		fovOffset = -4
	end
end

handlers.Strike = function(data)
	shockwave(data.position, data.color or Config.Colors.Accent, (data.size or 8) * 1.4, 0.3, false)
	playSound("heavy", 0.6, 1.1, data.position)
end

handlers.AOE = function(data)
	local color = data.color or Config.Colors.Accent
	shockwave(data.position, color, data.radius * 2, 0.6, true)
	shockwave(data.position + Vector3.new(0, 1, 0), color, data.radius * 1.4, 0.5, false)
	burst(data.position, color, 60, 30, 1, -15, 1)
	playSound(data.sound or "slam", 1, 0.9, data.position)
	local hrp = hrpOf(player.Character)
	local dist = hrp and (hrp.Position - data.position).Magnitude or 999
	shake(math.clamp(3 - dist / 25, 0.2, 3))
	if dist < data.radius + 10 then
		flashScreen(color, 0.8, 0.4)
	end
end

handlers.Buff = function(data)
	local character = getCharacter(data.userId)
	local hrp = hrpOf(character)
	if hrp then
		shockwave(hrp.Position, data.color or Config.Colors.Accent, 14, 0.6, false)
		burst(hrp.Position, data.color or Config.Colors.Accent, 40, 12, 0.6, 8)
		playSound("charge", 0.8, 1.4, hrp.Position)
	end
end

local ultSound = nil
handlers.UltStart = function(data)
	local character = getCharacter(data.userId)
	local hrp = hrpOf(character)
	if hrp then
		shockwave(hrp.Position, data.color, 40, 1, false)
		shockwave(hrp.Position, Config.Colors.Ult, 50, 1.2, true)
		burst(hrp.Position, Config.Colors.Ult, 80, 30, 1.2, 5, 1.2)
		playSound("ult", 1, 0.8, hrp.Position)
	end
	shake(2)
	flashScreen(Config.Colors.Ult, 0.5, 1)
	if data.userId == player.UserId then
		local cc = Lighting:FindFirstChild("BGColor")
		if cc then
			TweenService:Create(cc, TweenInfo.new(1), { TintColor = Color3.fromRGB(255, 220, 255), Saturation = 0.5, Contrast = 0.3 }):Play()
		end
		if ultSound then
			ultSound:Destroy()
		end
		ultSound = Instance.new("Sound")
		ultSound.SoundId = SOUNDS.ult
		ultSound.Volume = 0.35
		ultSound.PlaybackSpeed = 0.5
		ultSound.Looped = true
		ultSound.Parent = workspace
		ultSound:Play()
	end
end

handlers.UltEnd = function(data)
	if data.userId == player.UserId then
		local cc = Lighting:FindFirstChild("BGColor")
		if cc then
			TweenService:Create(cc, TweenInfo.new(1), { TintColor = Color3.new(1, 1, 1), Saturation = 0.1, Contrast = 0.15 }):Play()
		end
		if ultSound then
			ultSound:Destroy()
			ultSound = nil
		end
	end
end

handlers.Death = function(data)
	burst(data.position, Config.Colors.Danger, 40, 20, 0.8)
	shockwave(data.position, Config.Colors.Danger, 16, 0.5, false)
	playSound("death", 0.8, 1, data.position)
	if data.userId == player.UserId then
		flashScreen(Config.Colors.Danger, 0.4, 1.5)
		shake(3)
		if ultSound then
			ultSound:Destroy()
			ultSound = nil
		end
		local cc = Lighting:FindFirstChild("BGColor")
		if cc then
			TweenService:Create(cc, TweenInfo.new(0.5), { TintColor = Color3.new(1, 1, 1), Saturation = 0.1, Contrast = 0.15 }):Play()
		end
	end
end

handlers.LevelUp = function(data)
	local hrp = hrpOf(getCharacter(data.userId))
	if hrp then
		burst(hrp.Position, Config.Colors.Gold, 40, 12, 0.6, 6)
		shockwave(hrp.Position, Config.Colors.Gold, 14, 0.7, false)
	end
	if data.userId == player.UserId then
		playSound("level", 0.8, 1.2)
		flashScreen(Config.Colors.Gold, 0.8, 0.8)
	end
end

handlers.Win = function(data)
	local hrp = hrpOf(getCharacter(data.userId))
	if hrp then
		shockwave(hrp.Position, Config.Colors.Gold, 30, 1, true)
	end
	if data.userId == player.UserId then
		playSound("win", 1, 1)
		flashScreen(Config.Colors.Gold, 0.6, 1.2)
	end
end

function Effects.Init(hudModule)
	HUD = hudModule
	Remotes.CombatFX.OnClientEvent:Connect(function(kind, data)
		local handler = handlers[kind]
		if handler then
			local ok, err = pcall(handler, data or {})
			if not ok then
				warn("[OnyxBG] Effet " .. kind .. " : " .. tostring(err))
			end
		end
	end)

	for _, p in ipairs(Players:GetPlayers()) do
		hookPlayer(p)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	for _, dummy in ipairs(CollectionService:GetTagged("Dummy")) do
		task.spawn(attachOverhead, dummy)
	end
	CollectionService:GetInstanceAddedSignal("Dummy"):Connect(function(dummy)
		task.spawn(attachOverhead, dummy)
	end)

	State.Changed.Event:Connect(function(what, data)
		if what == "block" then
			-- feedback local immediat (le serveur diffuse aussi l'evenement)
			if data then
				fovOffset = -2
			end
		end
	end)
end

return Effects
